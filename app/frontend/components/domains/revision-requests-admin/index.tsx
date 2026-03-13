import React, { useEffect, useMemo, useState } from 'react';
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
  HStack,
  IconButton,
  Table,
  Tbody,
  Td,
  Text,
  Th,
  Thead,
  Tooltip,
  Tr,
  useDisclosure,
} from '@chakra-ui/react';
import { ArrowsClockwise, Info, PencilSimple, PlusCircle, Trash } from '@phosphor-icons/react';
import { useLocation, useNavigate } from 'react-router-dom';
import { ThinBlueTitleBar } from '../../shared/base/thin-blue-title-bar';

type RevisionRequestGridRow = {
  session_id?: string | null;
  session_created_at?: string | null;
  session_status?: string | null;
  invoice_id?: string | null;
  invoice_status?: string | null;
  contractor_business_name?: string | null;
  invoice_version_id?: string | null;
  invoice_version_created_at?: string | null;
  invoice_versionno?: number | null;
  invoice_version_original_filename?: string | null;
  di_ocr_invoice_id?: string | null;
  revision_request_id?: string | null;
  revision_request_seqno?: number | null;
  revision_request_status?: string | null;
  revision_request_requester_id?: string | null;
  revision_request_text?: string | null;
  revision_request_response_text?: string | null;
  revision_request_created_at?: string | null;
  revision_request_updated_at?: string | null;
  revision_request_closed_at?: string | null;
};

type RevisionRequestGridResponse = {
  rows: RevisionRequestGridRow[];
  meta?: { total?: number; page?: number; per?: number; sort?: string; filters?: any };
};

function getParam(search: string, key: string): string {
  return new URLSearchParams(search).get(key) ?? '';
}

function fmtDate(s?: string | null) {
  if (!s) return '—';
  const raw = String(s);
  if (raw.includes('T')) return raw.split('T')[0];
  return raw.slice(0, 10);
}

function Field({ label, value }: { label: string; value: any }) {
  return (
    <Box>
      <Text fontSize="xs" opacity={0.7} mb={1}>
        {label}
      </Text>
      <Text fontSize="sm" fontFamily={label.endsWith('_id') ? 'mono' : undefined} whiteSpace="pre-wrap">
        {value === null || value === undefined || value === '' ? '—' : String(value)}
      </Text>
    </Box>
  );
}

export default function RevisionRequestsAdminScreen() {
  const location = useLocation();
  const navigate = useNavigate();

  const invoiceId = getParam(location.search, 'invoice_id');
  const contextSessionId = getParam(location.search, 'context_session_id');
  const contextSessionCreatedAt = getParam(location.search, 'context_session_created_at');
  const contextSessionStatus = getParam(location.search, 'context_session_status');
  const contextInvoiceStatus = getParam(location.search, 'context_invoice_status');
  const contextContractorBusinessName = getParam(location.search, 'context_contractor_business_name');
  const contextDiOcrInvoiceId = getParam(location.search, 'context_di_ocr_invoice_id');

  const [gridLoading, setGridLoading] = useState(false);
  const [gridError, setGridError] = useState('');
  const [rows, setRows] = useState<RevisionRequestGridRow[]>([]);
  const [total, setTotal] = useState<number>(0);
  const [deletingId, setDeletingId] = useState<string>('');

  const fetchRows = async () => {
    setGridLoading(true);
    setGridError('');

    try {
      const params = new URLSearchParams();
      if (invoiceId.trim()) params.set('invoice_id', invoiceId.trim());
      params.set('sort', 'invoice_versionno:asc');
      params.set('page', '1');
      params.set('per', '100');

      const res = await fetch(`/api/claims/admin/revision_requests?${params.toString()}`, {
        method: 'GET',
        headers: { Accept: 'application/json' },
        credentials: 'include',
      });

      const data: RevisionRequestGridResponse = await res.json().catch(() => ({ rows: [] }));
      if (!res.ok) throw new Error((data as any)?.error || (data as any)?.message || `HTTP ${res.status}`);

      const nextRows = Array.isArray(data?.rows) ? data.rows : [];
      setRows(nextRows);
      setTotal(Number(data?.meta?.total ?? 0));
    } catch (e: any) {
      setGridError(e?.message || 'Failed to load revision request grid.');
      setRows([]);
      setTotal(0);
    } finally {
      setGridLoading(false);
    }
  };

  useEffect(() => {
    fetchRows();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [invoiceId]);

  const { isOpen, onOpen, onClose } = useDisclosure();
  const [selected, setSelected] = useState<RevisionRequestGridRow | null>(null);

  const openDrawer = (row: RevisionRequestGridRow) => {
    setSelected(row);
    onOpen();
  };

  const closeDrawer = () => {
    onClose();
    setSelected(null);
  };

  const revisionRequestEntries = useMemo(() => {
    if (!selected) return [] as Array<[string, any]>;

    return [
      ['revision_request_id', selected.revision_request_id],
      ['invoice_version_id', selected.invoice_version_id],
      ['revision_request_seqno', selected.revision_request_seqno],
      ['revision_request_requester_id', selected.revision_request_requester_id],
      ['revision_request_status', selected.revision_request_status],
      ['revision_request_text', selected.revision_request_text],
      ['revision_request_response_text', selected.revision_request_response_text],
      ['revision_request_created_at', selected.revision_request_created_at],
      ['revision_request_updated_at', selected.revision_request_updated_at],
      ['revision_request_closed_at', selected.revision_request_closed_at],
    ];
  }, [selected]);

  const hasInvoiceContext =
    !!invoiceId ||
    !!contextSessionId ||
    !!contextSessionCreatedAt ||
    !!contextSessionStatus ||
    !!contextInvoiceStatus ||
    !!contextContractorBusinessName ||
    !!contextDiOcrInvoiceId;

  const openInsert = (row: RevisionRequestGridRow) => {
    const params = new URLSearchParams();
    params.set('mode', 'create');
    if (row.invoice_version_id) params.set('invoice_version_id', String(row.invoice_version_id));
    if (row.invoice_id) params.set('invoice_id', String(row.invoice_id));
    if (row.session_id) params.set('session_id', String(row.session_id));
    if (row.session_created_at) params.set('session_created_at', String(row.session_created_at));
    if (row.contractor_business_name) params.set('contractor_business_name', String(row.contractor_business_name));
    if (row.invoice_version_created_at) params.set('invoice_version_created_at', String(row.invoice_version_created_at));
    if (row.invoice_versionno !== null && row.invoice_versionno !== undefined) params.set('invoice_versionno', String(row.invoice_versionno));
    if (row.di_ocr_invoice_id) params.set('di_ocr_invoice_id', String(row.di_ocr_invoice_id));
    navigate(`/revision-request-editor?${params.toString()}`);
  };

  const openUpdate = (row: RevisionRequestGridRow) => {
    if (!row.revision_request_id) return;
    const params = new URLSearchParams();
    params.set('id', String(row.revision_request_id));
    if (row.invoice_version_id) params.set('invoice_version_id', String(row.invoice_version_id));
    if (row.invoice_id) params.set('invoice_id', String(row.invoice_id));
    if (row.session_id) params.set('session_id', String(row.session_id));
    if (row.session_created_at) params.set('session_created_at', String(row.session_created_at));
    if (row.contractor_business_name) params.set('contractor_business_name', String(row.contractor_business_name));
    if (row.invoice_version_created_at) params.set('invoice_version_created_at', String(row.invoice_version_created_at));
    if (row.invoice_versionno !== null && row.invoice_versionno !== undefined) params.set('invoice_versionno', String(row.invoice_versionno));
    if (row.di_ocr_invoice_id) params.set('di_ocr_invoice_id', String(row.di_ocr_invoice_id));
    navigate(`/revision-request-editor?${params.toString()}`);
  };

  const handleDelete = async (row: RevisionRequestGridRow) => {
    const rrid = String(row.revision_request_id || '').trim();
    if (!rrid) return;

    const ok = window.confirm(`Delete revision request ${rrid}? This cannot be undone.`);
    if (!ok) return;

    setGridError('');
    setDeletingId(rrid);
    try {
      const res = await fetch(`/api/claims/admin/revision_requests/${encodeURIComponent(rrid)}`, {
        method: 'DELETE',
        headers: { Accept: 'application/json' },
        credentials: 'include',
      });

      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data?.error || data?.message || `Delete failed (${res.status}).`);

      if (selected?.revision_request_id && String(selected.revision_request_id) === rrid) {
        closeDrawer();
      }

      await fetchRows();
    } catch (e: any) {
      setGridError(e?.message || 'Failed to delete revision request.');
    } finally {
      setDeletingId('');
    }
  };

  return (
    <Flex as="main" direction="column" w="full" bg="greys.white" pb="24" minH="100vh">
      <ThinBlueTitleBar title="Revision Requests Admin" />

      <Container maxW="container.xl" pb={4} flex="1" pt={6}>
        <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="lg" p={5} bg="white">
          <Flex justify="flex-end" mb={4}>
            <Tooltip label="Refresh grid">
              <IconButton
                aria-label="Refresh grid"
                icon={<ArrowsClockwise size={18} />}
                variant="outline"
                onClick={fetchRows}
                isLoading={gridLoading}
              />
            </Tooltip>
          </Flex>

          {gridError && (
            <Box mb={3} p={3} bg="red.50" borderWidth="1px" borderColor="red.200" borderRadius="md">
              <Text as="div" fontSize="sm" color="red.700">
                {gridError}
              </Text>
            </Box>
          )}

          <Box mb={4} p={3} borderWidth="1px" borderColor="greys.grey20" borderRadius="md" bg="gray.50">
            {!hasInvoiceContext ? (
              <Text fontSize="sm" opacity={0.7}>No context available.</Text>
            ) : (
              <Flex direction="column" gap={3}>
                <Text fontSize="sm" fontWeight="bold">Context (selected invoice)</Text>
                <Flex wrap="wrap" gap={6}>
                  <Box>
                    <Text fontSize="xs" opacity={0.7}>session_id</Text>
                    <Text fontSize="sm" fontFamily="mono">{contextSessionId || '—'}</Text>
                  </Box>
                  <Box>
                    <Text fontSize="xs" opacity={0.7}>session_status</Text>
                    <Text fontSize="sm">{contextSessionStatus || '—'}</Text>
                  </Box>
                  <Box>
                    <Text fontSize="xs" opacity={0.7}>session_created_at</Text>
                    <Text fontSize="sm">{fmtDate(contextSessionCreatedAt)}</Text>
                  </Box>
                  <Box>
                    <Text fontSize="xs" opacity={0.7}>invoice_id</Text>
                    <Text fontSize="sm" fontFamily="mono">{invoiceId || '—'}</Text>
                  </Box>
                  <Box>
                    <Text fontSize="xs" opacity={0.7}>invoice_status</Text>
                    <Text fontSize="sm">{contextInvoiceStatus || '—'}</Text>
                  </Box>
                  <Box>
                    <Text fontSize="xs" opacity={0.7}>contractor_name</Text>
                    <Text fontSize="sm">{contextContractorBusinessName || '—'}</Text>
                  </Box>
                  <Box>
                    <Text fontSize="xs" opacity={0.7}>invoice # (DI)</Text>
                    <Text fontSize="sm">{contextDiOcrInvoiceId || '—'}</Text>
                  </Box>
                </Flex>
              </Flex>
            )}
          </Box>

          <Box borderWidth="1px" borderRadius="md" overflow="auto">
            <Table size="sm" minW="1180px">
              <Thead bg="gray.50">
                <Tr>
                  <Th>invoice version no</Th>
                  <Th>invoice version created</Th>
                  <Th>request created</Th>
                  <Th>request updated</Th>
                  <Th>request status</Th>
                  <Th textAlign="right">actions</Th>
                </Tr>
              </Thead>
              <Tbody>
                {rows.map((r, idx) => (
                  <Tr
                    key={`${r.invoice_version_id || 'iv'}-${r.revision_request_id || 'rr'}-${idx}`}
                  >
                    <Td fontSize="xs">{r.invoice_versionno ?? '—'}</Td>
                    <Td fontSize="xs">{fmtDate(r.invoice_version_created_at)}</Td>
                    <Td fontSize="xs">{fmtDate(r.revision_request_created_at)}</Td>
                    <Td fontSize="xs">{fmtDate(r.revision_request_updated_at)}</Td>
                    <Td fontSize="xs">{r.revision_request_status || '—'}</Td>
                    <Td>
                      <HStack spacing={1} justify="flex-end">
                        <Tooltip label="Details">
                          <IconButton
                            aria-label="Details"
                            icon={<Info size={16} />}
                            size="sm"
                            variant="ghost"
                            onClick={() => openDrawer(r)}
                          />
                        </Tooltip>

                        <Tooltip label="Insert revision request">
                          <IconButton
                            aria-label="Insert revision request"
                            icon={<PlusCircle size={16} />}
                            size="sm"
                            variant="ghost"
                            onClick={() => openInsert(r)}
                            isDisabled={!r.invoice_version_id}
                          />
                        </Tooltip>

                        <Tooltip label="Update revision request">
                          <IconButton
                            aria-label="Update revision request"
                            icon={<PencilSimple size={16} />}
                            size="sm"
                            variant="ghost"
                            onClick={() => openUpdate(r)}
                            isDisabled={!r.revision_request_id}
                          />
                        </Tooltip>

                        <Tooltip label="Delete revision request">
                          <IconButton
                            aria-label="Delete revision request"
                            icon={<Trash size={16} />}
                            size="sm"
                            variant="ghost"
                            colorScheme="red"
                            onClick={() => handleDelete(r)}
                            isLoading={!!r.revision_request_id && deletingId === String(r.revision_request_id).trim()}
                            isDisabled={!r.revision_request_id}
                          />
                        </Tooltip>
                      </HStack>
                    </Td>
                  </Tr>
                ))}

                {!gridLoading && rows.length === 0 && (
                  <Tr>
                    <Td colSpan={6}>
                      <Text as="div" fontSize="sm" opacity={0.7} p={3}>
                        No rows found.
                      </Text>
                    </Td>
                  </Tr>
                )}
              </Tbody>
            </Table>
          </Box>

          <Flex mt={3} align="center" justify="space-between" wrap="wrap" gap={2}>
            <Text fontSize="xs" opacity={0.7}>
              total: {total}
            </Text>
          </Flex>
        </Box>
      </Container>

      <Drawer isOpen={isOpen} placement="right" onClose={closeDrawer} size="md">
        <DrawerOverlay />
        <DrawerContent>
          <DrawerCloseButton />
          <DrawerHeader>Revision Request Details</DrawerHeader>
          <DrawerBody>
            {!selected && (
              <Text fontSize="sm" opacity={0.7}>
                No row selected.
              </Text>
            )}

            {!!selected && (
              <Flex direction="column" gap={4}>
                {revisionRequestEntries.map(([k, v]) => (
                  <Box key={k}>
                    <Field label={k} value={v} />
                  </Box>
                ))}
              </Flex>
            )}
          </DrawerBody>
        </DrawerContent>
      </Drawer>
    </Flex>
  );
}
