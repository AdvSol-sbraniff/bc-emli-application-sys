// /app/frontend/components/domains/upload-invoice-admin/index.tsx
import {
  Box,
  Button,
  Container,
  Flex,
  Heading,
  HStack,
  Input,
  Select,
  Spinner,
  Tab,
  TabList,
  TabPanel,
  TabPanels,
  Tabs,
  Table,
  Tbody,
  Td,
  Text,
  Th,
  Thead,
  Tr,
} from '@chakra-ui/react';

import React, { useEffect, useMemo, useRef, useState } from 'react';
import { observer } from 'mobx-react-lite';
import { BlueTitleBar } from '../../shared/base/blue-title-bar';
import { useLocation, useNavigate } from 'react-router-dom';

// ============================================================
// SECTION 00 — FILE OVERVIEW
// PURPOSE: Upload Invoice (Admin)
// - Tab 1: Session chooser (bookmarkable grid) via:
//     GET /api/claims/admin/sessions_with_contractors?q=&status=&sort=&page=&per=
// - Tab 2: Upload a single PDF to the selected session via:
//     POST /api/claims/sessions/:session_id/upload  (multipart/form-data)
// - Stores selection in URL as session_id
// - After upload, shows invoice_id + invoice_version_id with copy buttons
// - Optional: button to open Job Admin in new tab with session_id + invoice_version_id
// ============================================================

type SessionRow = {
  id: string; // session id
  contractor_id?: string | null;
  submitter_id?: string | null;
  status?: string | null;
  created_at?: string | null;
  updated_at?: string | null;
  submitted_at?: string | null;

  contractor_business_name?: string | null;
  contractor_number?: string | null;
  contractor_email?: string | null;
  contractor_phone_number?: string | null;
  contractor_cellphone_number?: string | null;
  contractor_city?: string | null;
  contractor_postal_code?: string | null;
  contractor_onboarded?: boolean | null;
};

type SessionsSearchResponse = {
  rows: SessionRow[];
  meta?: { total?: number; page?: number; per?: number; sort?: string; filters?: any };
};

function safeJsonStringify(obj: any): string {
  try {
    return JSON.stringify(obj, null, 2);
  } catch {
    return String(obj);
  }
}

function getParam(search: string, key: string): string {
  return new URLSearchParams(search).get(key) ?? '';
}

function setParams(navigate: any, location: any, patch: Record<string, string>) {
  const params = new URLSearchParams(location.search);

  Object.entries(patch).forEach(([k, v]) => {
    if (v === '' || v == null) params.delete(k);
    else params.set(k, v);
  });

  const qs = params.toString();
  navigate(`${location.pathname}${qs ? `?${qs}` : ''}`, { replace: true });
}

function sanitizeSqlLike(string: string): string {
  // matches backend sanitize_sql_like behavior for % and _
  return string.toString().replace(/[\\%_]/g, (x) => `\\${x}`);
}

function fmtTs(s?: string | null) {
  return s ? String(s).replace('T', ' ').replace('Z', '') : '—';
}

function tryExtractUploadIds(data: any): { invoice_id: string; invoice_version_id: string } {
  const invoice_id = data?.invoice_id ?? data?.invoice?.id ?? '';
  const invoice_version_id = data?.invoice_version_id ?? data?.invoice_version?.id ?? '';
  return {
    invoice_id: invoice_id ? String(invoice_id) : '',
    invoice_version_id: invoice_version_id ? String(invoice_version_id) : '',
  };
}

export default observer(function UploadInvoiceAdminScreen() {
  const location = useLocation();
  const navigate = useNavigate();

  // ============================================================
  // SECTION 01 — URL-DRIVEN STATE (grid)
  // ============================================================

  const q = getParam(location.search, 'q');
  const status = getParam(location.search, 'status'); // optional
  const sort = getParam(location.search, 'sort') || 'updated_at:desc';
  const pageStr = getParam(location.search, 'page') || '1';
  const perStr = getParam(location.search, 'per') || '25';
  const sessionIdFromUrl = getParam(location.search, 'session_id');

  const page = Math.max(1, parseInt(pageStr || '1', 10) || 1);
  const per = [25, 50, 100].includes(parseInt(perStr, 10)) ? parseInt(perStr, 10) : 25;

  // local draft input (so typing doesn’t update URL per-keystroke)
  const [qDraft, setQDraft] = useState<string>(q);
  useEffect(() => setQDraft(q), [q]);

  // ============================================================
  // SECTION 02 — GRID DATA
  // ============================================================

  const [gridLoading, setGridLoading] = useState(false);
  const [gridError, setGridError] = useState('');
  const [rows, setRows] = useState<SessionRow[]>([]);
  const [total, setTotal] = useState<number>(0);

  const fetchSessions = async () => {
    setGridLoading(true);
    setGridError('');

    try {
      const params = new URLSearchParams();
      if (q.trim()) params.set('q', q.trim());
      if (status.trim()) params.set('status', status.trim());
      params.set('sort', sort);
      params.set('page', String(page));
      params.set('per', String(per));

      const url = `/api/claims/admin/sessions_with_contractors?${params.toString()}`;

      const res = await fetch(url, {
        method: 'GET',
        headers: { Accept: 'application/json' },
        credentials: 'include',
      });

      const data: SessionsSearchResponse = await res.json().catch(() => ({ rows: [] }));

      if (!res.ok) {
        throw new Error((data as any)?.error || (data as any)?.message || `HTTP ${res.status}`);
      }

      setRows(Array.isArray(data?.rows) ? data.rows : []);
      setTotal(Number(data?.meta?.total ?? 0));
    } catch (e: any) {
      setGridError(e?.message || 'Failed to load sessions.');
      setRows([]);
      setTotal(0);
    } finally {
      setGridLoading(false);
    }
  };

  useEffect(() => {
    fetchSessions();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [q, status, sort, page, per]);

  const totalPages = Math.max(1, Math.ceil((total || 0) / per));

  const selectedSession = useMemo(() => {
    if (!sessionIdFromUrl) return null;
    return rows.find((r) => r.id === sessionIdFromUrl) ?? null;
  }, [rows, sessionIdFromUrl]);

  const handleSelectSession = (s: SessionRow) => {
    setParams(navigate, location, { session_id: s.id });
  };

  // ============================================================
  // SECTION 03 — UPLOAD
  // ============================================================

  const fileInputRef = useRef<HTMLInputElement | null>(null);

  const [selectedFile, setSelectedFile] = useState<File | null>(null);
  const [isUploading, setIsUploading] = useState<boolean>(false);
  const [uploadError, setUploadError] = useState<string>('');
  const [uploadOkMsg, setUploadOkMsg] = useState<string>('');

  const [invoiceId, setInvoiceId] = useState<string>('');
  const [invoiceVersionId, setInvoiceVersionId] = useState<string>('');


  const clearUploadOutputs = () => {
    setUploadError('');
    setUploadOkMsg('');
    setInvoiceId('');
    setInvoiceVersionId('');
    setSelectedFile(null);
  };

  const openFileChooser = () => {
    setUploadError('');
    setUploadOkMsg('');

    if (!sessionIdFromUrl.trim()) {
      setUploadError('Select a session first (Tab 1).');
      return;
    }

    fileInputRef.current?.click();
  };

  const handleFilesChosen = async (e: React.ChangeEvent<HTMLInputElement>) => {
    setUploadError('');
    setUploadOkMsg('');

    const files = Array.from(e.target.files || []);
    const firstFile = files[0] ?? null;

    // allow selecting same file again
    e.target.value = '';

    if (!firstFile) return;

    setSelectedFile(firstFile);

    if (!sessionIdFromUrl.trim()) {
      setUploadError('Select a session first (Tab 1).');
      return;
    }

    await uploadSinglePdf(sessionIdFromUrl.trim(), firstFile);
  };

  const uploadSinglePdf = async (sid: string, file: File) => {
    setIsUploading(true);
    setUploadError('');
    setUploadOkMsg('');


    // new upload => new ids
    setInvoiceId('');
    setInvoiceVersionId('');

    try {
      const endpoint = `/api/claims/sessions/${encodeURIComponent(sid)}/upload`;

      const form = new FormData();
      form.append('session_id', sid);
      form.append('pdfs[]', file, file.name);

      const res = await fetch(endpoint, {
        method: 'POST',
        credentials: 'include',
        body: form,
      });



      const data = await res.json().catch(() => ({}));

      if (!res.ok) {
        throw new Error(data?.error || data?.message || `HTTP ${res.status} ${res.statusText}`);
      }

      const ids = tryExtractUploadIds(data);
      if (ids.invoice_id) setInvoiceId(ids.invoice_id);
      if (ids.invoice_version_id) setInvoiceVersionId(ids.invoice_version_id);

      const msg =
        data?.message ||
        data?.summary ||
        `Upload accepted for session ${sid} (1 file).`;

      setUploadOkMsg(String(msg));
    } catch (err: any) {
      setUploadError(err?.message || 'Upload failed.');
    } finally {
      setIsUploading(false);
    }
  };

const openJobAdmin = () => {
  const sid = sessionIdFromUrl.trim();
  const iid = invoiceId.trim();
  const ivid = invoiceVersionId.trim();

  if (!sid) return;
  if (!iid) return;
  if (!ivid) return;

  const url =
    `/ai-admin?session_id=${encodeURIComponent(sid)}` +
    `&invoice_id=${encodeURIComponent(iid)}` +
    `&invoice_version_id=${encodeURIComponent(ivid)}`;

  window.open(url, '_blank');
};

  // ============================================================
  // SECTION 04 — RENDER
  // ============================================================

  return (
    <Flex as="main" direction="column" w="full" bg="greys.white" pb="24" minH="100vh">
      <BlueTitleBar title="Upload Invoice (Admin)" />

      <Container maxW="container.xl" pb={4} flex="1" pt={6}>
        <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="lg" p={5} bg="white">
          <Tabs variant="line" isFitted colorScheme="gray">
            <TabList mb="1em">
              <Tab>Choose session</Tab>
              <Tab>Upload invoice</Tab>
            </TabList>

            <TabPanels>
              {/* ============================================================
                  TAB 1 — SESSION CHOOSER
              ============================================================ */}
              <TabPanel px={0}>
                <Flex justify="space-between" align="center" mb={3} wrap="wrap" gap={3}>
                  <Box>
                    <Heading size="sm">Sessions</Heading>
                    <Text as="div" fontSize="xs" opacity={0.7}>
                      Search and select a session. Selection is stored in the URL as{' '}
                      <Box as="code">session_id</Box>.
                    </Text>
                  </Box>

                  <HStack spacing={2}>
                    <Select
                      size="sm"
                      value={per}
                      onChange={(e) => setParams(navigate, location, { per: e.target.value, page: '1' })}
                      width="110px"
                    >
                      <option value="25">25</option>
                      <option value="50">50</option>
                      <option value="100">100</option>
                    </Select>

                    <Select
                      size="sm"
                      value={sort}
                      onChange={(e) => setParams(navigate, location, { sort: e.target.value, page: '1' })}
                      width="200px"
                    >
                      <option value="updated_at:desc">updated_at:desc</option>
                      <option value="created_at:desc">created_at:desc</option>
                      <option value="submitted_at:desc">submitted_at:desc</option>
                      <option value="status:asc">status:asc</option>
                      <option value="status:desc">status:desc</option>
                      <option value="contractor_business_name:asc">contractor_business_name:asc</option>
                      <option value="contractor_business_name:desc">contractor_business_name:desc</option>
                    </Select>

                    <Select
                      size="sm"
                      value={status}
                      onChange={(e) => setParams(navigate, location, { status: e.target.value, page: '1' })}
                      width="220px"
                    >
                      <option value="">status: (any)</option>
                      <option value="OPENBUTNOTSUBMITTED">OPENBUTNOTSUBMITTED</option>
                      <option value="OPENANDSUBMITTED">OPENANDSUBMITTED</option>
                      <option value="CLOSED">CLOSED</option>
                    </Select>

                    <Button size="sm" onClick={fetchSessions} isLoading={gridLoading}>
                      Refresh
                    </Button>
                  </HStack>
                </Flex>

                <Flex gap={2} mb={3} wrap="wrap">
                  <Input
                    value={qDraft}
                    onChange={(e) => setQDraft(e.target.value)}
                    placeholder="Search (contractor name/number/email/city/postal, ids)…"
                    maxW="640px"
                  />
                  <Button
                    onClick={() => setParams(navigate, location, { q: qDraft.trim(), page: '1' })}
                    isDisabled={qDraft.trim() === q.trim()}
                  >
                    Apply
                  </Button>
                  <Button
                    variant="outline"
                    onClick={() => {
                      setQDraft('');
                      setParams(navigate, location, { q: '', page: '1' });
                    }}
                    isDisabled={!q.trim() && !qDraft.trim()}
                  >
                    Clear
                  </Button>
                </Flex>

                {gridError && (
                  <Box mb={3} p={3} bg="red.50" borderWidth="1px" borderColor="red.200" borderRadius="md">
                    <Text as="div" fontSize="sm" color="red.700">
                      {gridError}
                    </Text>
                  </Box>
                )}

                <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="md" overflow="hidden">
                  <Box bg="gray.50" px={3} py={2}>
                    <Flex justify="space-between" align="center">
                      <Flex align="center" gap={2}>
                        <Text as="div" fontSize="sm" fontWeight="bold">
                          Rows
                        </Text>
                        {gridLoading ? <Spinner size="sm" /> : null}
                      </Flex>

                      <Text as="div" fontSize="xs" opacity={0.7}>
                        total: {total}
                      </Text>
                    </Flex>
                  </Box>

                  <Box bg="white" p={0}>
                    <Table size="sm">
                      <Thead>
                        <Tr>
                          <Th>contractor</Th>
                          <Th>session status</Th>
                          <Th>updated</Th>
                          <Th>submitted</Th>
                          <Th>session_id</Th>
                        </Tr>
                      </Thead>
                      <Tbody>
                        {rows.map((r) => {
                          const isSelected = r.id === sessionIdFromUrl;
                          return (
                            <Tr
                              key={r.id}
                              cursor="pointer"
                              bg={isSelected ? 'blue.50' : 'transparent'}
                              _hover={{ bg: isSelected ? 'blue.100' : 'gray.50' }}
                              onClick={() => handleSelectSession(r)}
                            >
                              <Td fontSize="sm">
                                <Text as="div" fontWeight="bold">
                                  {r.contractor_business_name ?? '—'}
                                </Text>
                                <Text as="div" fontSize="xs" opacity={0.75}>
                                  {r.contractor_number ? `#${r.contractor_number}` : '—'}{' '}
                                  {r.contractor_city ? `• ${r.contractor_city}` : ''}
                                </Text>
                              </Td>

                              <Td fontFamily="mono" fontSize="xs">
                                {r.status ?? '—'}
                              </Td>

                              <Td fontFamily="mono" fontSize="xs">
                                {fmtTs(r.updated_at)}
                              </Td>

                              <Td fontFamily="mono" fontSize="xs">
                                {fmtTs(r.submitted_at)}
                              </Td>

                              <Td fontFamily="mono" fontSize="xs">
                                {r.id}
                              </Td>
                            </Tr>
                          );
                        })}

                        {!gridLoading && rows.length === 0 && (
                          <Tr>
                            <Td colSpan={5}>
                              <Text as="div" fontSize="sm" opacity={0.7} p={3}>
                                No sessions found.
                              </Text>
                            </Td>
                          </Tr>
                        )}
                      </Tbody>
                    </Table>
                  </Box>
                </Box>

                <Flex mt={3} justify="space-between" align="center" wrap="wrap" gap={2}>
                  <Text as="div" fontSize="xs" opacity={0.7}>
                    page {page} of {totalPages}
                  </Text>

                  <HStack>
                    <Button
                      size="sm"
                      variant="outline"
                      onClick={() => setParams(navigate, location, { page: String(Math.max(1, page - 1)) })}
                      isDisabled={page <= 1}
                    >
                      Prev
                    </Button>
                    <Button
                      size="sm"
                      variant="outline"
                      onClick={() => setParams(navigate, location, { page: String(Math.min(totalPages, page + 1)) })}
                      isDisabled={page >= totalPages}
                    >
                      Next
                    </Button>
                  </HStack>
                </Flex>
              </TabPanel>

              {/* ============================================================
                  TAB 2 — UPLOAD INVOICE
              ============================================================ */}
              <TabPanel px={0}>
                <Heading size="sm" mb={2}>
                  Upload invoice PDF
                </Heading>

                <Text as="div" fontSize="xs" opacity={0.7} mb={3}>
                  This screen only uploads a PDF to the selected session (moves PDF to Azure). No OCR/GenAI here.
                </Text>

                <Box mb={3} p={3} borderWidth="1px" borderColor="greys.grey20" borderRadius="md" bg="gray.50">
                  <Text as="div" fontSize="xs" opacity={0.7}>
                    Selected session
                  </Text>

                  <Text as="div" fontSize="sm" fontWeight="bold">
                    {selectedSession?.contractor_business_name ?? '(none selected)'}
                  </Text>

                  <Text as="div" fontSize="xs" fontFamily="mono" opacity={0.9}>
                    session_id: {sessionIdFromUrl || '—'}
                  </Text>

                  {selectedSession?.status && (
                    <Text as="div" fontSize="xs" opacity={0.8}>
                      status:{' '}
                      <Box as="span" fontFamily="mono">
                        {selectedSession.status}
                      </Box>
                    </Text>
                  )}
                </Box>

                <HStack spacing={2} wrap="wrap">
                  <Button
                    colorScheme="blue"
                    onClick={openFileChooser}
                    isLoading={isUploading}
                    loadingText="Uploading..."
                    isDisabled={!sessionIdFromUrl.trim()}
                  >
                    Upload PDF (single)
                  </Button>

                  <Button
                    variant="outline"
                    onClick={() => {
                      clearUploadOutputs();
                    }}
                  >
                    Clear
                  </Button>
                </HStack>

                {selectedFile && (
                  <Box mt={3}>
                    <Text as="div" fontSize="xs" opacity={0.7}>
                      Selected file
                    </Text>
                    <Text as="div" fontFamily="mono" fontSize="sm">
                      {selectedFile.name} ({Math.round(selectedFile.size / 1024)} KB)
                    </Text>
                  </Box>
                )}

                {uploadError && (
                  <Box mt={3} p={3} bg="red.50" borderWidth="1px" borderColor="red.200" borderRadius="md">
                    <Text as="div" fontSize="sm" color="red.700">
                      {uploadError}
                    </Text>
                  </Box>
                )}

                {uploadOkMsg && (
                  <Box mt={3} p={3} bg="green.50" borderWidth="1px" borderColor="green.200" borderRadius="md">
                    <Text as="div" fontSize="sm" color="green.800" fontWeight="bold">
                      Upload complete
                    </Text>
                    <Text as="div" fontSize="sm" color="green.800">
                      {uploadOkMsg}
                    </Text>

                    <Box mt={2}>
                      <Text as="div" fontSize="xs" fontFamily="mono" color="green.900">
                        invoice_id: {invoiceId || '—'}
                      </Text>
                      <Text as="div" fontSize="xs" fontFamily="mono" color="green.900">
                        invoice_version_id: {invoiceVersionId || '—'}
                      </Text>
                    </Box>

                    <HStack mt={2} spacing={2} wrap="wrap">
                      <Button
                        size="sm"
                        variant="outline"
                        onClick={() => navigator.clipboard.writeText(sessionIdFromUrl || '')}
                        isDisabled={!sessionIdFromUrl.trim()}
                      >
                        Copy session_id
                      </Button>

                      <Button
                        size="sm"
                        variant="outline"
                        onClick={() => navigator.clipboard.writeText(invoiceId || '')}
                        isDisabled={!invoiceId.trim()}
                      >
                        Copy invoice_id
                      </Button>

                      <Button
                        size="sm"
                        variant="outline"
                        onClick={() => navigator.clipboard.writeText(invoiceVersionId || '')}
                        isDisabled={!invoiceVersionId.trim()}
                      >
                        Copy invoice_version_id
                      </Button>

                      <Button size="sm" onClick={openJobAdmin} isDisabled={!sessionIdFromUrl.trim() || !invoiceVersionId.trim()}>
                        Open Job Admin
                      </Button>

<Button
  size="sm"
  variant="outline"
  onClick={() => {
    if (!sessionIdFromUrl.trim()) return;
    window.open(`/invoices-admin?session_id=${encodeURIComponent(sessionIdFromUrl.trim())}`, '_blank');
  }}
  isDisabled={!sessionIdFromUrl.trim()}
>
  Open Invoice Grid
</Button>


                    </HStack>
                  </Box>
                )}

                
                {/* hidden file input (single file only) */}
                <input
                  ref={fileInputRef}
                  type="file"
                  accept="application/pdf,.pdf"
                  style={{ display: 'none' }}
                  onChange={handleFilesChosen}
                />
              </TabPanel>
            </TabPanels>
          </Tabs>
        </Box>
      </Container>
    </Flex>
  );
});