import React, { useCallback, useEffect, useMemo, useState } from 'react';
import {
  Badge,
  Box,
  Button,
  Container,
  Flex,
  HStack,
  Spinner,
  Table,
  Tbody,
  Td,
  Text,
  Th,
  Thead,
  Tr,
  VStack,
} from '@chakra-ui/react';
import { ArrowsClockwise, CheckCircle, Sparkle } from '@phosphor-icons/react';
import { useLocation } from 'react-router-dom';
import { ThinBlueTitleBar } from '../../shared/base/thin-blue-title-bar';
import { IngestRunMonitorTabs } from '../../shared/claims/ingest-run-monitor-tabs';

type SupportingDocumentRow = {
  id: string;
  original_filename?: string | null;
  content_type?: string | null;
  mime_content_type?: string | null;
  byte_size?: number | null;
  supporting_document_type_key?: string | null;
  supporting_document_type_description?: string | null;
};

type CurrentReadPayload = {
  invoice?: {
    id?: string;
    session_id?: string | null;
    status?: string | null;
  };
  read?: {
    id?: string;
    invoice_id?: string;
    invoice_versionno?: number | null;
    original_filename?: string | null;
    content_type?: string | null;
    byte_size?: number | null;
    updated_at?: string | null;
    uploaded_supporting_documents?: SupportingDocumentRow[];
  };
};

type EvidenceRow = {
  id: string;
  role: 'invoice' | 'supporting_document';
  filename: string;
  type?: string | null;
  byteSize?: number | null;
};

function getParam(search: string, key: string): string {
  return new URLSearchParams(search).get(key) ?? '';
}

function fmtBytes(n?: number | null) {
  if (n === null || n === undefined) return '-';
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`;
  return `${(n / (1024 * 1024)).toFixed(2)} MB`;
}

export default function AdviceRefreshSimulationAdminScreen() {
  const location = useLocation();
  const invoiceId = getParam(location.search, 'invoice_id');
  const contractorBusinessName = getParam(location.search, 'contractor_business_name');

  const [loading, setLoading] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState('');
  const [success, setSuccess] = useState('');
  const [readPayload, setReadPayload] = useState<CurrentReadPayload | null>(null);
  const [runId, setRunId] = useState('');

  const loadCurrentPackage = useCallback(async () => {
    if (!invoiceId.trim()) {
      setError('Missing invoice_id in URL.');
      setReadPayload(null);
      return;
    }

    setLoading(true);
    setError('');
    try {
      const res = await fetch(`/api/claims/admin/invoices/${encodeURIComponent(invoiceId)}/current_version/read`, {
        method: 'GET',
        headers: { Accept: 'application/json' },
        credentials: 'include',
      });
      const data = (await res.json().catch(() => ({}))) as CurrentReadPayload & { error?: string };
      if (!res.ok) throw new Error(data?.error || `HTTP ${res.status}`);
      setReadPayload(data);
    } catch (e: any) {
      setError(e?.message || 'Failed to load current package.');
      setReadPayload(null);
    } finally {
      setLoading(false);
    }
  }, [invoiceId]);

  useEffect(() => {
    void loadCurrentPackage();
  }, [loadCurrentPackage]);

  const evidenceRows = useMemo<EvidenceRow[]>(() => {
    const invoiceRow: EvidenceRow[] = readPayload?.read?.id
      ? [
          {
            id: `invoice-${readPayload.read.id}`,
            role: 'invoice',
            filename: readPayload.read.original_filename || 'Current invoice PDF',
            type: readPayload.read.content_type || 'application/pdf',
            byteSize: readPayload.read.byte_size,
          },
        ]
      : [];

    const supportRows = Array.isArray(readPayload?.read?.uploaded_supporting_documents)
      ? readPayload.read.uploaded_supporting_documents.map((doc) => ({
          id: `support-${doc.id}`,
          role: 'supporting_document' as const,
          filename: doc.original_filename || 'Supporting document',
          type: doc.supporting_document_type_description || doc.supporting_document_type_key || doc.mime_content_type,
          byteSize: doc.byte_size,
        }))
      : [];

    return [...invoiceRow, ...supportRows];
  }, [readPayload]);

  const handleRefreshAdvice = async () => {
    if (!invoiceId.trim()) return;
    setSubmitting(true);
    setError('');
    setSuccess('');
    setRunId('');
    try {
      const res = await fetch(`/api/claims/admin/invoices/${encodeURIComponent(invoiceId)}/reanalyze_advice`, {
        method: 'POST',
        headers: { Accept: 'application/json' },
        credentials: 'include',
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok || data?.ok === false) throw new Error(data?.error || data?.message || `HTTP ${res.status}`);

      const nextRunId = String(data?.ingest_run_id || '').trim();
      setRunId(nextRunId);
      setReadPayload((previous) => {
        if (!previous?.read) return previous;
        return {
          ...previous,
          read: {
            ...previous.read,
            id: data?.invoice_version_id || previous.read.id,
            invoice_versionno: data?.invoice_versionno ?? previous.read.invoice_versionno,
          },
        };
      });
      setSuccess(
        `AI Advice refresh started for version ${data?.invoice_versionno ?? '-'}. Ingest run ${nextRunId || '-'} was queued.`,
      );
      void loadCurrentPackage();
    } catch (e: any) {
      setError(e?.message || 'Failed to refresh AI Advice.');
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <Flex as="main" direction="column" w="full" bg="greys.white" pb="24" minH="100vh">
      <ThinBlueTitleBar title="Refresh AI Advice" />

      <Container maxW="container.xl" pb={4} flex="1" pt={6}>
        <VStack align="stretch" spacing={5}>
          <Box
            bg="linear-gradient(135deg, rgba(235, 248, 255, 0.95), white 62%)"
            p={6}
            borderRadius="2xl"
            boxShadow="0 22px 60px rgba(15, 23, 42, 0.10)"
          >
            <Flex justify="space-between" align="center" gap={4} wrap="wrap">
              <HStack align="start" spacing={4}>
                <Box color="blue.600" pt={1}>
                  <Sparkle size={34} />
                </Box>
                <Box>
                  <Text fontSize="xl" fontWeight="semibold">
                    Reuse this evidence and regenerate advice
                  </Text>
                  <Text fontSize="sm" opacity={0.75} mt={1} maxW="760px">
                    This flow does not upload files or re-extract evidence. It creates a new invoice version by cloning
                    the current evidence context, then reruns the current AI Advice checks, prompts, code checks, and
                    aggregation.
                  </Text>
                </Box>
              </HStack>

              <Box textAlign="right">
                <Text fontSize="xs" opacity={0.68}>
                  contractor
                </Text>
                <Text fontSize="sm" fontWeight="semibold">
                  {contractorBusinessName || 'Unknown contractor'}
                </Text>
                <Text fontSize="xs" opacity={0.68}>
                  v{readPayload?.read?.invoice_versionno ?? '-'}
                </Text>
              </Box>
            </Flex>
          </Box>

          {error && (
            <Box p={3} bg="red.50" borderWidth="1px" borderColor="red.200" borderRadius="md">
              <Text fontSize="sm" color="red.700">
                {error}
              </Text>
            </Box>
          )}

          {success && (
            <Box p={3} bg="green.50" borderWidth="1px" borderColor="green.200" borderRadius="md">
              <HStack spacing={2}>
                <CheckCircle size={18} />
                <Text fontSize="sm" color="green.800">
                  {success}
                </Text>
              </HStack>
            </Box>
          )}

          <Box bg="white" p={5} borderRadius="xl" boxShadow="0 12px 34px rgba(15, 23, 42, 0.06)">
            <Flex justify="space-between" align="center" mb={3} gap={3} wrap="wrap">
              <Box>
                <Text fontSize="sm" fontWeight="bold">
                  Evidence that will be reused
                </Text>
                <Text fontSize="xs" opacity={0.68}>
                  No file contents will change in this flow.
                </Text>
              </Box>
              {loading && <Spinner size="sm" />}
            </Flex>

            <Table size="sm">
              <Thead bg="gray.50">
                <Tr>
                  <Th>filename</Th>
                  <Th>role</Th>
                  <Th>type</Th>
                  <Th isNumeric>size</Th>
                </Tr>
              </Thead>
              <Tbody>
                {evidenceRows.map((row) => (
                  <Tr key={row.id}>
                    <Td fontSize="sm">{row.filename}</Td>
                    <Td>
                      <Badge colorScheme={row.role === 'invoice' ? 'blue' : 'gray'}>{row.role}</Badge>
                    </Td>
                    <Td fontSize="xs">{row.type || '-'}</Td>
                    <Td isNumeric fontSize="xs">
                      {fmtBytes(row.byteSize)}
                    </Td>
                  </Tr>
                ))}
                {!loading && evidenceRows.length === 0 && (
                  <Tr>
                    <Td colSpan={4}>
                      <Text fontSize="sm" opacity={0.7}>
                        No current evidence was found.
                      </Text>
                    </Td>
                  </Tr>
                )}
              </Tbody>
            </Table>
          </Box>

          <Box bg="white" p={5} borderRadius="xl" boxShadow="0 18px 45px rgba(15, 23, 42, 0.08)">
            <Flex justify="space-between" align="center" gap={3} wrap="wrap">
              <Box>
                <Text fontSize="sm" fontWeight="bold">
                  Ready to refresh AI Advice
                </Text>
                <Text fontSize="xs" opacity={0.68}>
                  A new invoice version and run will start, then the invoice will move back through the AI Advice
                  statuses.
                </Text>
              </Box>
              <Button
                colorScheme="blue"
                leftIcon={<ArrowsClockwise size={18} />}
                onClick={() => void handleRefreshAdvice()}
                isLoading={submitting}
                loadingText="Refreshing..."
                isDisabled={loading || !readPayload?.read?.id}
              >
                Refresh AI Advice
              </Button>
            </Flex>
          </Box>

          <Box bg="white" p={5} borderRadius="xl" boxShadow="0 18px 45px rgba(15, 23, 42, 0.08)">
            <IngestRunMonitorTabs runId={runId} emptyMessage="Refresh AI Advice to see run and step history." />
          </Box>
        </VStack>
      </Container>
    </Flex>
  );
}
