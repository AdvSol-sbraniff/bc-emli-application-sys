import React, { useCallback, useEffect, useState } from 'react';
import {
  Box,
  Container,
  Drawer,
  DrawerBody,
  DrawerCloseButton,
  DrawerContent,
  DrawerHeader,
  DrawerOverlay,
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
  VStack,
} from '@chakra-ui/react';
import { FilePdf, Info } from '@phosphor-icons/react';
import { useLocation } from 'react-router-dom';
import { ThinBlueTitleBar } from '../../shared/base/thin-blue-title-bar';

type ContextPayload = {
  invoice_id: string;
  session_id: string;
  session_created_at?: string | null;
  contractor_business_name?: string | null;
  invoice_created_at?: string | null;
  latest_invoice_version_id?: string | null;
  latest_ocr_invoice_number?: string | null;
};

type SupportingDocumentLocatedField = {
  id?: string;
  field_key?: string | null;
  contractor_display_name?: string | null;
  value_text?: string | null;
  value_json?: any;
  confidence?: number | null;
  page?: number | null;
  evidence_text?: string | null;
  field_number?: number | null;
  prompt_text?: string | null;
};

type SupportingDocumentVisualFinding = {
  id?: string;
  finding_seqno?: number | null;
  source_engine?: string | null;
  finding_type?: string | null;
  page?: number | null;
  summary?: string | null;
  legibility?: string | null;
  confidence?: number | null;
};

type SupportingDocumentRow = {
  id: string;
  invoice_version_id: string;
  supporting_document_type_id?: string | null;
  supporting_document_type_key?: string | null;
  supporting_document_type_description?: string | null;
  classification_status?: string | null;
  classification_confidence?: number | null;
  classification_reason?: string | null;
  supporting_document_routing_quality?: string | null;
  supporting_document_routing_quality_reason?: string | null;
  located_fields?: SupportingDocumentLocatedField[];
  visual_findings?: SupportingDocumentVisualFinding[];
  storage_provider?: string | null;
  storage_key?: string | null;
  original_filename?: string | null;
  content_type?: string | null;
  mime_content_type?: string | null;
  byte_size?: number | null;
  sha256?: string | null;
  created_at?: string | null;
  updated_at?: string | null;
};

function getParam(search: string, key: string): string {
  return new URLSearchParams(search).get(key) ?? '';
}

function fmtTs(s?: string | null) {
  return s ? String(s).replace('T', ' ').replace('Z', '') : '—';
}

function fmtBytes(n?: number | null) {
  if (n === null || n === undefined) return '—';
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`;
  return `${(n / (1024 * 1024)).toFixed(2)} MB`;
}

function evidenceCountLabel(count: number, singular: string) {
  return `${count} ${singular}${count === 1 ? '' : 's'}`;
}

function fmtLocatedFieldValue(field: SupportingDocumentLocatedField) {
  if (field.value_text !== null && field.value_text !== undefined && String(field.value_text).trim()) {
    return String(field.value_text);
  }
  if (field.value_json !== null && field.value_json !== undefined) return JSON.stringify(field.value_json);
  return '-';
}

export default function InvoiceSupportingDocumentsAdminScreen() {
  const location = useLocation();
  const invoiceId = getParam(location.search, 'invoice_id');

  const [context, setContext] = useState<ContextPayload | null>(null);
  const [rows, setRows] = useState<SupportingDocumentRow[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const [selectedInfoRow, setSelectedInfoRow] = useState<SupportingDocumentRow | null>(null);

  const loadData = useCallback(async () => {
    if (!invoiceId.trim()) {
      setError('Missing invoice_id in URL.');
      setContext(null);
      setRows([]);
      return;
    }

    setLoading(true);
    setError('');

    try {
      const [contextRes, listRes] = await Promise.all([
        fetch(`/api/claims/admin/invoices/${encodeURIComponent(invoiceId)}/supporting_documents/context`, {
          method: 'GET',
          headers: { Accept: 'application/json' },
          credentials: 'include',
        }),
        fetch(`/api/claims/admin/invoices/${encodeURIComponent(invoiceId)}/supporting_documents`, {
          method: 'GET',
          headers: { Accept: 'application/json' },
          credentials: 'include',
        }),
      ]);

      const contextJson = await contextRes.json().catch(() => ({}));
      const listJson = await listRes.json().catch(() => ({ rows: [] }));

      if (!contextRes.ok) throw new Error(contextJson?.error || `HTTP ${contextRes.status}`);
      if (!listRes.ok) throw new Error(listJson?.error || `HTTP ${listRes.status}`);

      setContext(contextJson as ContextPayload);
      setRows(Array.isArray(listJson?.rows) ? listJson.rows : []);
    } catch (e: any) {
      setContext(null);
      setRows([]);
      setError(e?.message || 'Failed to load supporting-document screen.');
    } finally {
      setLoading(false);
    }
  }, [invoiceId]);

  useEffect(() => {
    void loadData();
  }, [loadData]);

  const handleOpenSupportingPdf = async (id: string) => {
    try {
      const res = await fetch(`/api/claims/admin/supporting_documents/${encodeURIComponent(id)}/pdf_url`, {
        method: 'GET',
        headers: { Accept: 'application/json' },
        credentials: 'include',
      });

      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data?.error || `HTTP ${res.status}`);
      if (!data?.sas_url) throw new Error('Supporting PDF URL not returned.');

      window.open(String(data.sas_url), '_blank', 'noopener,noreferrer');
    } catch (e: any) {
      setError(e?.message || 'Failed to open supporting PDF.');
    }
  };

  return (
    <Flex as="main" direction="column" w="full" bg="greys.white" pb="24" minH="100vh">
      <ThinBlueTitleBar title="Invoice Supporting Documents" />

      <Container maxW="container.xl" pb={4} flex="1" pt={6}>
        <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="lg" p={5} bg="white" mb={5}>
          <Text fontSize="sm" fontWeight="bold" mb={4}>
            Invoice Context
          </Text>

          {loading && !context ? (
            <Spinner size="sm" />
          ) : (
            <Flex wrap="wrap" gap={6}>
              <Box minW="240px">
                <Text fontSize="xs" opacity={0.7}>
                  contractor
                </Text>
                <Text fontSize="sm">{context?.contractor_business_name || '—'}</Text>
              </Box>
              <Box minW="220px">
                <Text fontSize="xs" opacity={0.7}>
                  latest OCR invoice number
                </Text>
                <Text fontSize="sm">{context?.latest_ocr_invoice_number || '—'}</Text>
              </Box>
            </Flex>
          )}
        </Box>

        {error && (
          <Box mb={4} p={3} bg="red.50" borderWidth="1px" borderColor="red.200" borderRadius="md">
            <Text fontSize="sm" color="red.700">
              {error}
            </Text>
          </Box>
        )}

        <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="lg" p={5} bg="white">
          {loading && (
            <Flex justify="flex-end" mb={3}>
              <Spinner size="sm" />
            </Flex>
          )}

          <Table size="sm">
            <Thead bg="gray.50">
              <Tr>
                <Th>filename</Th>
                <Th>type</Th>
                <Th>routing</Th>
                <Th>evidence</Th>
                <Th isNumeric>size</Th>
                <Th>actions</Th>
              </Tr>
            </Thead>
            <Tbody>
              {rows.map((row) => (
                <Tr key={row.id}>
                  <Td fontSize="sm">
                    <Text>{row.original_filename || '—'}</Text>
                  </Td>
                  <Td fontSize="xs" maxW="220px">
                    <Text fontSize="xs">
                      {row.supporting_document_type_description ||
                        row.supporting_document_type_key ||
                        row.content_type ||
                        '—'}
                    </Text>
                    {row.classification_confidence !== null && row.classification_confidence !== undefined && (
                      <Text fontSize="xs" opacity={0.65}>
                        conf {Number(row.classification_confidence).toFixed(0)}
                      </Text>
                    )}
                    {String(row.classification_reason || '').trim() && (
                      <Text fontSize="xs" opacity={0.65} noOfLines={2}>
                        {row.classification_reason}
                      </Text>
                    )}
                  </Td>
                  <Td fontSize="xs" maxW="220px">
                    <Text fontSize="xs">{row.supporting_document_routing_quality || '—'}</Text>
                    {String(row.supporting_document_routing_quality_reason || '').trim() && (
                      <Text fontSize="xs" opacity={0.65} noOfLines={2}>
                        {row.supporting_document_routing_quality_reason}
                      </Text>
                    )}
                  </Td>
                  <Td fontSize="xs" whiteSpace="nowrap">
                    <Text>{evidenceCountLabel(row.located_fields?.length || 0, 'field')}</Text>
                    <Text opacity={0.68}>{evidenceCountLabel(row.visual_findings?.length || 0, 'visual finding')}</Text>
                  </Td>
                  <Td isNumeric fontSize="xs">
                    {fmtBytes(row.byte_size)}
                  </Td>
                  <Td>
                    <HStack spacing={2}>
                      <Tooltip label="View document details and located fields">
                        <IconButton
                          aria-label="View supporting document details"
                          size="xs"
                          variant="outline"
                          icon={<Info size={14} />}
                          onClick={() => setSelectedInfoRow(row)}
                        />
                      </Tooltip>
                      <Tooltip label="Open supporting PDF in a new browser tab">
                        <IconButton
                          aria-label="Open supporting PDF"
                          size="xs"
                          variant="outline"
                          icon={<FilePdf size={14} />}
                          onClick={() => void handleOpenSupportingPdf(row.id)}
                        />
                      </Tooltip>
                    </HStack>
                  </Td>
                </Tr>
              ))}

              {!loading && rows.length === 0 && (
                <Tr>
                  <Td colSpan={6}>
                    <Text fontSize="sm" opacity={0.7}>
                      No supporting documents uploaded for this invoice yet.
                    </Text>
                  </Td>
                </Tr>
              )}
            </Tbody>
          </Table>
        </Box>
      </Container>

      <Drawer isOpen={!!selectedInfoRow} placement="right" onClose={() => setSelectedInfoRow(null)} size="xl">
        <DrawerOverlay />
        <DrawerContent>
          <DrawerCloseButton />
          <DrawerHeader>Supporting Document Details</DrawerHeader>
          <DrawerBody>
            {selectedInfoRow && (
              <Flex direction="column" gap={5}>
                <Box>
                  <Heading size="sm" mb={2}>
                    Document
                  </Heading>
                  <Table size="sm">
                    <Tbody>
                      <Tr>
                        <Td fontWeight="semibold">filename</Td>
                        <Td>{selectedInfoRow.original_filename || '—'}</Td>
                      </Tr>
                      <Tr>
                        <Td fontWeight="semibold">supporting type</Td>
                        <Td>
                          {selectedInfoRow.supporting_document_type_description ||
                            selectedInfoRow.supporting_document_type_key ||
                            '—'}
                        </Td>
                      </Tr>
                      <Tr>
                        <Td fontWeight="semibold">routing</Td>
                        <Td>{selectedInfoRow.supporting_document_routing_quality || '—'}</Td>
                      </Tr>
                      <Tr>
                        <Td fontWeight="semibold">classification confidence</Td>
                        <Td>{selectedInfoRow.classification_confidence ?? '—'}</Td>
                      </Tr>
                      <Tr>
                        <Td fontWeight="semibold">size</Td>
                        <Td>{fmtBytes(selectedInfoRow.byte_size)}</Td>
                      </Tr>
                      <Tr>
                        <Td fontWeight="semibold">created</Td>
                        <Td>{fmtTs(selectedInfoRow.created_at)}</Td>
                      </Tr>
                    </Tbody>
                  </Table>
                </Box>

                {String(selectedInfoRow.classification_reason || '').trim() && (
                  <Box>
                    <Heading size="sm" mb={2}>
                      Classification Reason
                    </Heading>
                    <Text fontSize="sm">{selectedInfoRow.classification_reason}</Text>
                  </Box>
                )}

                {String(selectedInfoRow.supporting_document_routing_quality_reason || '').trim() && (
                  <Box>
                    <Heading size="sm" mb={2}>
                      Routing Quality Reason
                    </Heading>
                    <Text fontSize="sm">{selectedInfoRow.supporting_document_routing_quality_reason}</Text>
                  </Box>
                )}

                <Box>
                  <Heading size="sm" mb={2}>
                    Visual Findings
                  </Heading>

                  {Array.isArray(selectedInfoRow.visual_findings) && selectedInfoRow.visual_findings.length > 0 ? (
                    <VStack align="stretch" spacing={3}>
                      {selectedInfoRow.visual_findings.map((finding, index) => (
                        <Box
                          key={finding.id || `${selectedInfoRow.id}:visual:${index}`}
                          borderWidth="1px"
                          borderColor="orange.200"
                          bg="orange.50"
                          borderRadius="md"
                          p={3}
                        >
                          <Flex justify="space-between" align="start" gap={3} wrap="wrap" mb={1}>
                            <Text fontSize="xs" fontWeight="bold">
                              {finding.finding_type || `visual_finding_${finding.finding_seqno || index + 1}`}
                            </Text>
                            <Text fontSize="xs" opacity={0.72}>
                              page {finding.page ?? '—'} | conf {finding.confidence ?? 0} |{' '}
                              {finding.legibility || 'not_applicable'}
                            </Text>
                          </Flex>
                          <Text fontSize="sm">{finding.summary || '—'}</Text>
                        </Box>
                      ))}
                    </VStack>
                  ) : (
                    <Text fontSize="sm" opacity={0.7}>
                      No visual findings were stored for this supporting document.
                    </Text>
                  )}
                </Box>

                <Box>
                  <Heading size="sm" mb={2}>
                    Located Fields
                  </Heading>

                  {Array.isArray(selectedInfoRow.located_fields) && selectedInfoRow.located_fields.length > 0 ? (
                    <Table size="sm">
                      <Thead bg="gray.50">
                        <Tr>
                          <Th>field</Th>
                          <Th>value</Th>
                          <Th>confidence</Th>
                          <Th>page</Th>
                          <Th>evidence</Th>
                        </Tr>
                      </Thead>
                      <Tbody>
                        {selectedInfoRow.located_fields.map((field) => (
                          <Tr key={field.id || `${selectedInfoRow.id}:${field.field_key}`}>
                            <Td fontSize="xs" fontWeight="semibold">
                              <Tooltip label={`Field key: ${field.field_key || 'unknown'}`} hasArrow>
                                <Text as="span" fontSize="xs" fontWeight="semibold" cursor="help">
                                  {field.contractor_display_name || field.field_key || 'Field'}
                                </Text>
                              </Tooltip>
                            </Td>
                            <Td fontSize="xs">{fmtLocatedFieldValue(field)}</Td>
                            <Td fontSize="xs">{field.confidence ?? 0}</Td>
                            <Td fontSize="xs">{field.page ?? '—'}</Td>
                            <Td fontSize="xs" whiteSpace="pre-wrap">
                              {field.evidence_text || '—'}
                            </Td>
                          </Tr>
                        ))}
                      </Tbody>
                    </Table>
                  ) : (
                    <Text fontSize="sm" opacity={0.7}>
                      No located fields were stored for this supporting document.
                    </Text>
                  )}
                </Box>
              </Flex>
            )}
          </DrawerBody>
        </DrawerContent>
      </Drawer>
    </Flex>
  );
}
