import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  Badge,
  Box,
  Button,
  Container,
  Flex,
  Heading,
  HStack,
  IconButton,
  Spinner,
  Table,
  Tbody,
  Td,
  Text,
  Th,
  Thead,
  Tooltip,
  Tr,
} from '@chakra-ui/react';
import { ArrowsClockwise, UploadSimple } from '@phosphor-icons/react';
import { useLocation } from 'react-router-dom';
import { ThinBlueTitleBar } from '../../shared/base/thin-blue-title-bar';

type ContextPayload = {
  invoice_id: string;
  session_id: string;
  status?: string | null;
  session_created_at?: string | null;
  contractor_business_name?: string | null;
  latest_invoice_version_id?: string | null;
  latest_invoice_versionno?: number | null;
  latest_original_filename?: string | null;
  latest_ocr_invoice_number?: string | null;
};

type IngestStepRow = {
  id: string;
  ingest_run_id?: string | null;
  invoice_version_id?: string | null;
  original_filename?: string | null;
  document_kind?: string | null;
  step_type?: string | null;
  status?: string | null;
  error_text?: string | null;
  validationgenai_ruleset_id?: string | null;
  created_at?: string | null;
  updated_at?: string | null;
};

function getParam(search: string, key: string): string {
  return new URLSearchParams(search).get(key) ?? '';
}

function sanitizeDisplayTs(s?: string | null) {
  if (!s) return '';
  return String(s).replace('T', ' ').replace('Z', '');
}

function fmtBytes(n?: number | null) {
  if (n === null || n === undefined) return '-';
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`;
  return `${(n / (1024 * 1024)).toFixed(2)} MB`;
}

function StepStatusBadge({ status }: { status?: string | null }) {
  const value = String(status || '').toLowerCase();

  if (value === 'in_progress') return <Spinner size="sm" />;
  if (value === 'queued') return <Badge colorScheme="yellow">QUEUED</Badge>;
  if (value === 'succeeded') return <Badge colorScheme="green">OK</Badge>;
  if (value === 'failed') return <Badge colorScheme="red">FAIL</Badge>;

  return <Badge colorScheme="gray">{String(status || 'unknown').toUpperCase()}</Badge>;
}

export default function RedoInvoicePackageScreen() {
  const location = useLocation();
  const invoiceId = getParam(location.search, 'invoice_id');

  const [context, setContext] = useState<ContextPayload | null>(null);
  const [loading, setLoading] = useState(false);
  const [uploading, setUploading] = useState(false);
  const [redoing, setRedoing] = useState(false);
  const [error, setError] = useState('');
  const [success, setSuccess] = useState('');
  const [selectedFiles, setSelectedFiles] = useState<File[]>([]);
  const [isDragActive, setIsDragActive] = useState(false);
  const [stepsLoading, setStepsLoading] = useState(false);
  const [stepsError, setStepsError] = useState('');
  const [steps, setSteps] = useState<IngestStepRow[]>([]);
  const [autoPollEnabled, setAutoPollEnabled] = useState(false);
  const [pollGraceUntilMs, setPollGraceUntilMs] = useState(0);

  const fileInputRef = useRef<HTMLInputElement | null>(null);
  const POLL_INTERVAL_MS = 2500;
  const POLL_GRACE_MS = 60000;

  const canUpload = useMemo(
    () => invoiceId.trim().length > 0 && selectedFiles.length > 0 && !uploading,
    [invoiceId, selectedFiles, uploading],
  );

  const canRedo = invoiceId.trim().length > 0 && !redoing;

  const fetchStepsByInvoice = useCallback(async () => {
    if (!invoiceId.trim()) {
      setSteps([]);
      return;
    }

    setStepsLoading(true);
    setStepsError('');

    try {
      const params = new URLSearchParams();
      params.set('limit', '200');

      const res = await fetch(
        `/api/claims/ingest/invoices/${encodeURIComponent(invoiceId)}/steps?${params.toString()}`,
        {
          method: 'GET',
          headers: { Accept: 'application/json' },
          credentials: 'include',
        },
      );

      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data?.error || data?.message || `HTTP ${res.status}`);

      setSteps(Array.isArray(data?.rows) ? data.rows : []);
    } catch (e: any) {
      setSteps([]);
      setStepsError(e?.message || 'Failed to load steps.');
    } finally {
      setStepsLoading(false);
    }
  }, [invoiceId]);

  const loadData = useCallback(async () => {
    if (!invoiceId.trim()) {
      setError('Missing invoice_id in URL.');
      setContext(null);
      return;
    }

    setLoading(true);
    setError('');

    try {
      const contextRes = await fetch(
        `/api/claims/admin/invoices/${encodeURIComponent(invoiceId)}/redo_package/context`,
        {
          method: 'GET',
          headers: { Accept: 'application/json' },
          credentials: 'include',
        },
      );

      const contextJson = await contextRes.json().catch(() => ({}));

      if (!contextRes.ok) throw new Error(contextJson?.error || `HTTP ${contextRes.status}`);

      setContext(contextJson as ContextPayload);
    } catch (e: any) {
      setContext(null);
      setError(e?.message || 'Failed to load redo package screen.');
    } finally {
      setLoading(false);
    }
  }, [invoiceId]);

  useEffect(() => {
    void loadData();
    void fetchStepsByInvoice();
  }, [fetchStepsByInvoice, loadData]);

  const hasPendingStep = useMemo(
    () => steps.some((s) => ['queued', 'in_progress'].includes(String(s.status || '').toLowerCase())),
    [steps],
  );

  const shouldPollSteps =
    autoPollEnabled && !!invoiceId.trim() && (redoing || Date.now() < pollGraceUntilMs || hasPendingStep);

  useEffect(() => {
    if (!shouldPollSteps) return;

    const intervalId = window.setInterval(() => {
      void fetchStepsByInvoice();
    }, POLL_INTERVAL_MS);

    return () => window.clearInterval(intervalId);
  }, [fetchStepsByInvoice, shouldPollSteps]);

  const mergeFiles = (incoming: File[]) => {
    const pdfsOnly = incoming.filter((f) => {
      const byType = String(f.type || '').toLowerCase() === 'application/pdf';
      const byExt = String(f.name || '')
        .toLowerCase()
        .endsWith('.pdf');
      return byType || byExt;
    });

    setSelectedFiles((prev) => {
      const seen = new Set(prev.map((f) => `${f.name}:${f.size}:${f.lastModified}`));
      const next = [...prev];
      pdfsOnly.forEach((f) => {
        const key = `${f.name}:${f.size}:${f.lastModified}`;
        if (!seen.has(key)) next.push(f);
      });
      return next;
    });
  };

  const handleUpload = async () => {
    if (!canUpload) return;

    setUploading(true);
    setError('');
    setSuccess('');

    try {
      const form = new FormData();
      selectedFiles.forEach((f) => form.append('pdfs[]', f, f.name));

      const res = await fetch(`/api/claims/admin/invoices/${encodeURIComponent(invoiceId)}/redo_package/documents`, {
        method: 'POST',
        credentials: 'include',
        body: form,
      });

      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data?.error || `HTTP ${res.status}`);

      setSelectedFiles([]);
      setSuccess(
        `Added ${Number(data?.uploaded_count || 0)} raw package PDF(s). Click Redo Entire Package when ready.`,
      );
      await loadData();
      await fetchStepsByInvoice();
    } catch (e: any) {
      setError(e?.message || 'Failed to add package PDFs.');
    } finally {
      setUploading(false);
    }
  };

  const handleRedo = async () => {
    if (!canRedo) return;

    const confirmed = window.confirm(
      'Redo the entire invoice package from the current invoice PDF, processed supporting PDFs, and staged package PDFs?',
    );
    if (!confirmed) return;

    setRedoing(true);
    setAutoPollEnabled(true);
    setPollGraceUntilMs(Date.now() + POLL_GRACE_MS);
    setError('');
    setSuccess('');

    try {
      await fetchStepsByInvoice();

      const res = await fetch(`/api/claims/admin/invoices/${encodeURIComponent(invoiceId)}/redo_package`, {
        method: 'POST',
        headers: { Accept: 'application/json', 'Content-Type': 'application/json' },
        credentials: 'include',
        body: JSON.stringify({}),
      });

      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data?.error || `HTTP ${res.status}`);

      setSuccess(`Redo queued for ${Number(data?.queued_count || 0)} package PDF(s).`);
      setPollGraceUntilMs(Date.now() + POLL_GRACE_MS);
      await loadData();
      await fetchStepsByInvoice();
    } catch (e: any) {
      setError(e?.message || 'Redo Entire Package failed.');
      await fetchStepsByInvoice();
    } finally {
      setRedoing(false);
    }
  };

  return (
    <Flex as="main" direction="column" w="full" bg="greys.white" pb="24" minH="100vh">
      <ThinBlueTitleBar title="Redo Invoice Package" />

      <Container maxW="container.xl" pb={4} flex="1" pt={6}>
        <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="lg" p={5} bg="white" mb={5}>
          <Flex justify="space-between" align="center" gap={4} wrap="wrap">
            <Box>
              <Text fontSize="sm" fontWeight="bold" mb={1}>
                Package Context
              </Text>
              <Text fontSize="sm" opacity={0.75}>
                Add ad hoc PDFs here, then redo the whole package so OCR, classifier, supporting-doc extraction, invoice
                OCR, and GenAI all rebuild from the same source set.
              </Text>
            </Box>
            <Button
              colorScheme="blue"
              leftIcon={<ArrowsClockwise size={16} />}
              onClick={() => void handleRedo()}
              isLoading={redoing}
              isDisabled={!canRedo}
            >
              Redo Entire Package
            </Button>
          </Flex>

          {loading && !context ? (
            <Spinner size="sm" />
          ) : (
            <Flex wrap="wrap" gap={6} mt={5}>
              <Box minW="220px">
                <Text fontSize="xs" opacity={0.7}>
                  contractor
                </Text>
                <Text fontSize="sm">{context?.contractor_business_name || '-'}</Text>
              </Box>
              <Box minW="180px">
                <Text fontSize="xs" opacity={0.7}>
                  invoice status
                </Text>
                <Text fontSize="sm">{context?.status || '-'}</Text>
              </Box>
              <Box minW="220px">
                <Text fontSize="xs" opacity={0.7}>
                  current invoice PDF
                </Text>
                <Text fontSize="sm">{context?.latest_original_filename || '-'}</Text>
              </Box>
              <Box minW="170px">
                <Text fontSize="xs" opacity={0.7}>
                  invoice version
                </Text>
                <Text fontSize="sm">{context?.latest_invoice_versionno ?? '-'}</Text>
              </Box>
            </Flex>
          )}
        </Box>

        <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="lg" p={5} bg="white" mb={5}>
          <Text fontSize="sm" fontWeight="bold" mb={4}>
            Add Raw Package PDFs
          </Text>

          <input
            ref={fileInputRef}
            type="file"
            multiple
            accept="application/pdf,.pdf"
            style={{ display: 'none' }}
            onChange={(e) => {
              mergeFiles(Array.from(e.target.files || []));
              e.target.value = '';
            }}
          />

          <Box
            borderWidth="2px"
            borderStyle="dashed"
            borderColor={isDragActive ? 'blue.400' : 'gray.200'}
            borderRadius="lg"
            p={7}
            textAlign="center"
            bg={isDragActive ? 'blue.50' : 'gray.50'}
            onDragEnter={(e) => {
              e.preventDefault();
              setIsDragActive(true);
            }}
            onDragOver={(e) => {
              e.preventDefault();
              setIsDragActive(true);
            }}
            onDragLeave={(e) => {
              e.preventDefault();
              setIsDragActive(false);
            }}
            onDrop={(e) => {
              e.preventDefault();
              setIsDragActive(false);
              mergeFiles(Array.from(e.dataTransfer.files || []));
            }}
          >
            <Text fontWeight="bold" mb={2}>
              Drag and drop package PDFs here
            </Text>
            <Text fontSize="sm" opacity={0.8} mb={4}>
              These PDFs are staged only. They become processed invoice/supporting docs after Redo Entire Package.
            </Text>
            <Button
              variant="outline"
              leftIcon={<UploadSimple size={16} />}
              onClick={() => fileInputRef.current?.click()}
            >
              Select Files
            </Button>
          </Box>

          <Box mt={4}>
            <Text fontSize="xs" opacity={0.7} mb={2}>
              Selected files
            </Text>
            {selectedFiles.length ? (
              selectedFiles.map((file) => (
                <Flex
                  key={`${file.name}:${file.size}:${file.lastModified}`}
                  justify="space-between"
                  align="center"
                  py={1}
                >
                  <Text fontSize="sm">{file.name}</Text>
                  <Text fontSize="xs" opacity={0.7}>
                    {fmtBytes(file.size)}
                  </Text>
                </Flex>
              ))
            ) : (
              <Text fontSize="sm" opacity={0.7}>
                No files selected.
              </Text>
            )}
          </Box>

          <HStack mt={4} spacing={3}>
            <Button
              colorScheme="blue"
              onClick={() => void handleUpload()}
              isLoading={uploading}
              isDisabled={!canUpload}
            >
              Add{' '}
              {selectedFiles.length ? `${selectedFiles.length} PDF${selectedFiles.length === 1 ? '' : 's'}` : 'PDFs'}
            </Button>
            {!!selectedFiles.length && (
              <Button variant="outline" onClick={() => setSelectedFiles([])} isDisabled={uploading}>
                Clear Selection
              </Button>
            )}
          </HStack>
        </Box>

        {error && (
          <Box mb={4} p={3} bg="red.50" borderWidth="1px" borderColor="red.200" borderRadius="md">
            <Text fontSize="sm" color="red.700">
              {error}
            </Text>
          </Box>
        )}

        {success && (
          <Box mb={4} p={3} bg="green.50" borderWidth="1px" borderColor="green.200" borderRadius="md">
            <Text fontSize="sm" color="green.700">
              {success}
            </Text>
          </Box>
        )}

        <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="md" p={4} bg="gray.50">
          <Flex align="center" justify="space-between" mb={3} wrap="wrap" gap={3}>
            <Box>
              <Heading size="sm">Step Run Tracker</Heading>
              <Text as="div" fontSize="xs" opacity={0.7}>
                ingest_step_runs filtered by <Box as="code">invoice_id</Box>
              </Text>
            </Box>

            <Tooltip label="Refresh steps">
              <IconButton
                aria-label="Refresh steps"
                icon={<ArrowsClockwise size={18} />}
                size="sm"
                variant="outline"
                onClick={fetchStepsByInvoice}
                isLoading={stepsLoading}
                isDisabled={!invoiceId.trim()}
              />
            </Tooltip>
          </Flex>

          {stepsError && (
            <Box mb={3} p={3} bg="red.50" borderWidth="1px" borderColor="red.200" borderRadius="md">
              <Text as="div" fontSize="sm" color="red.700">
                {stepsError}
              </Text>
            </Box>
          )}

          <Box bg="white" borderWidth="1px" borderColor="greys.grey20" borderRadius="md" p={3}>
            <Flex align="center" justify="space-between" mb={2}>
              <Text as="div" fontSize="sm" fontWeight="bold">
                Steps
              </Text>
              {stepsLoading ? <Spinner size="sm" /> : null}
            </Flex>

            <Table size="sm">
              <Thead>
                <Tr>
                  <Th>created</Th>
                  <Th>step_id</Th>
                  <Th>file</Th>
                  <Th>type</Th>
                  <Th>state</Th>
                  <Th>invoice_version_id</Th>
                  <Th>ruleset</Th>
                  <Th>error</Th>
                </Tr>
              </Thead>

              <Tbody>
                {steps.map((s) => (
                  <Tr key={s.id}>
                    <Td fontFamily="mono" fontSize="xs">
                      {sanitizeDisplayTs(s.created_at)}
                    </Td>
                    <Td fontFamily="mono" fontSize="xs">
                      {s.id}
                    </Td>
                    <Td fontSize="xs" maxW="240px">
                      <Text as="div" fontSize="xs">
                        {s.original_filename || ''}
                      </Text>
                      {s.document_kind ? (
                        <Text as="div" fontSize="xs" opacity={0.65}>
                          {s.document_kind}
                        </Text>
                      ) : null}
                    </Td>
                    <Td fontFamily="mono" fontSize="xs">
                      {s.step_type ?? ''}
                    </Td>
                    <Td fontSize="xs">
                      <StepStatusBadge status={s.status} />
                    </Td>
                    <Td fontFamily="mono" fontSize="xs">
                      {s.invoice_version_id ?? ''}
                    </Td>
                    <Td fontFamily="mono" fontSize="xs">
                      {s.validationgenai_ruleset_id ?? ''}
                    </Td>
                    <Td fontFamily="mono" fontSize="xs" whiteSpace="pre-wrap">
                      {s.error_text ?? ''}
                    </Td>
                  </Tr>
                ))}

                {!stepsLoading && steps.length === 0 && (
                  <Tr>
                    <Td colSpan={8}>
                      <Text as="div" fontSize="sm" opacity={0.7}>
                        No steps found.
                      </Text>
                    </Td>
                  </Tr>
                )}
              </Tbody>
            </Table>
          </Box>
        </Box>
      </Container>
    </Flex>
  );
}
