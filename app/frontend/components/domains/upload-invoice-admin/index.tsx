// /app/frontend/components/domains/upload-invoice-admin/index.tsx
import {
  Box,
  Button,
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
  Input,
  Select,
  SimpleGrid,
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

import React, { useEffect, useMemo, useRef, useState } from 'react';
import { ArrowsClockwise, CaretLeft, CaretRight, Question, XCircle } from '@phosphor-icons/react';
import { observer } from 'mobx-react-lite';
import { ThinBlueTitleBar } from '../../shared/base/thin-blue-title-bar';
import { useLocation, useNavigate } from 'react-router-dom';

// ============================================================
// SECTION 00 — FILE OVERVIEW
// PURPOSE: Upload Invoice (Admin)
// - Session chooser grid (bookmarkable) via:
//     GET /api/claims/admin/sessions_with_contractors?q=&status=&sort=&page=&per=
// - Upload a single PDF to the selected session via:
//     POST /api/claims/sessions/:session_id/upload  (multipart/form-data)
// - Stores selection in URL as session_id
// - After upload, shows invoice_id + invoice_version_id with copy buttons
// - Optional: buttons to copy IDs and open the invoice grid
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

function fmtTs(s?: string | null) {
  return s ? String(s).replace('T', ' ').replace('Z', '') : '—';
}

function fmtDate(s?: string | null) {
  if (!s) return '—';
  const raw = String(s);
  if (raw.includes('T')) return raw.split('T')[0];
  return raw.slice(0, 10);
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

  const { isOpen: isHelpOpen, onOpen: onHelpOpen, onClose: onHelpClose } = useDisclosure();

  const openFileChooser = () => {
    setUploadError('');
    setUploadOkMsg('');

    if (!sessionIdFromUrl.trim()) {
      setUploadError('Select a session first.');
      return;
    }

    fileInputRef.current?.click();
  };

  const handleFilesChosen = async (e: React.ChangeEvent<HTMLInputElement>) => {
    setUploadError('');
    setUploadOkMsg('');

    const files = Array.from(e.target.files || []) as File[];
    const firstFile = files[0] ?? null;

    // allow selecting same file again
    e.target.value = '';

    if (!firstFile) return;

    setSelectedFile(firstFile);

    if (!sessionIdFromUrl.trim()) {
      setUploadError('Select a session first.');
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

      const msg = data?.message || data?.summary || `Upload accepted for session ${sid} (1 file).`;

      setUploadOkMsg(String(msg));
    } catch (err: any) {
      setUploadError(err?.message || 'Upload failed.');
    } finally {
      setIsUploading(false);
    }
  };

  // ============================================================
  // SECTION 04 — RENDER
  // ============================================================

  return (
    <Flex as="main" direction="column" w="full" bg="greys.white" pb="24" minH="100vh">
      <ThinBlueTitleBar title="Upload Invoice Admin" />

      <Container maxW="container.xl" pb={4} flex="1" pt={6}>
        <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="lg" p={5} bg="white">
          <Flex justify="flex-end" mb={2}>
            <Tooltip label="Help: sessions and upload behavior">
              <IconButton
                aria-label="Open upload invoice help"
                icon={<Question size={18} />}
                variant="outline"
                onClick={onHelpOpen}
              />
            </Tooltip>
          </Flex>

          <Text as="div" fontSize="xs" opacity={0.7} mb={3}>
            Confirm session context, upload a PDF, then continue processing from the next admin screen.
          </Text>

          <Box mb={3} p={3} borderWidth="1px" borderColor="greys.grey20" borderRadius="md" bg="white">
            <Text as="div" fontSize="sm" fontWeight="bold" mb={2}>
              Session context (from invoices admin)
            </Text>

            <Box>
              <Text as="div" fontSize="xs" opacity={0.7}>
                Session ID
              </Text>
              <Text as="div" fontSize="xs" fontFamily="mono">
                {sessionIdFromUrl || '—'}
              </Text>
            </Box>

            <SimpleGrid columns={{ base: 1, md: 2 }} spacing={3} mt={2}>
              <Box>
                <Text as="div" fontSize="xs" opacity={0.7}>
                  Contractor name
                </Text>
                <Text as="div" fontSize="sm">
                  {selectedSession?.contractor_business_name ?? '—'}
                </Text>
              </Box>

              <Box>
                <Text as="div" fontSize="xs" opacity={0.7}>
                  Contractor number
                </Text>
                <Text as="div" fontSize="sm" fontFamily="mono">
                  {selectedSession?.contractor_number ?? '—'}
                </Text>
              </Box>

              <Box>
                <Text as="div" fontSize="xs" opacity={0.7}>
                  Representative invoice submitted at
                </Text>
                <Text as="div" fontSize="sm" fontFamily="mono">
                  {fmtTs(selectedSession?.submitted_at)}
                </Text>
              </Box>

              <Box>
                <Text as="div" fontSize="xs" opacity={0.7}>
                  Created at
                </Text>
                <Text as="div" fontSize="sm" fontFamily="mono">
                  {fmtTs(selectedSession?.created_at)}
                </Text>
              </Box>

              <Box>
                <Text as="div" fontSize="xs" opacity={0.7}>
                  Updated at
                </Text>
                <Text as="div" fontSize="sm" fontFamily="mono">
                  {fmtTs(selectedSession?.updated_at)}
                </Text>
              </Box>

              <Box>
                <Text as="div" fontSize="xs" opacity={0.7}>
                  Contractor email
                </Text>
                <Text as="div" fontSize="sm">
                  {selectedSession?.contractor_email ?? '—'}
                </Text>
              </Box>

              <Box>
                <Text as="div" fontSize="xs" opacity={0.7}>
                  Contractor city
                </Text>
                <Text as="div" fontSize="sm">
                  {selectedSession?.contractor_city ?? '—'}
                </Text>
              </Box>
            </SimpleGrid>
          </Box>

          <HStack spacing={2} wrap="wrap" mb={3}>
            <Button
              colorScheme="blue"
              onClick={openFileChooser}
              isLoading={isUploading}
              loadingText="Uploading..."
              isDisabled={!sessionIdFromUrl.trim()}
            >
              Upload PDF (single)
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

          <Box mt={6}>
            <Text fontSize="sm" fontWeight="bold" mb={2}>
              Change session (optional)
            </Text>

            <Flex gap={3} align="end" wrap="wrap" mb={3}>
              <Box flex="1" minW="280px">
                <Text fontSize="xs" opacity={0.7} mb={1}>
                  Search (contractor name/number/email/city/postal, ids)
                </Text>
                <Input
                  value={q}
                  onChange={(e) => setParams(navigate, location, { q: e.target.value, page: '1' })}
                  placeholder="Search sessions..."
                  bg="white"
                />
              </Box>

              <Box w="220px">
                <Text fontSize="xs" opacity={0.7} mb={1}>
                  Status
                </Text>
                <Select
                  value={status}
                  onChange={(e) => setParams(navigate, location, { status: e.target.value, page: '1' })}
                  bg="white"
                >
                  <option value="">(any)</option>
                  <option value="OPENBUTNOTSUBMITTED">OPENBUTNOTSUBMITTED</option>
                  <option value="OPENANDSUBMITTED">OPENANDSUBMITTED</option>
                  <option value="CLOSED">CLOSED</option>
                </Select>
              </Box>

              <Box w="240px">
                <Text fontSize="xs" opacity={0.7} mb={1}>
                  Sort
                </Text>
                <Select
                  value={sort}
                  onChange={(e) => setParams(navigate, location, { sort: e.target.value, page: '1' })}
                  bg="white"
                >
                  <option value="updated_at:desc">updated_at desc</option>
                  <option value="created_at:desc">created_at desc</option>
                  <option value="submitted_at:desc">submitted_at desc</option>
                  <option value="status:asc">status asc</option>
                  <option value="status:desc">status desc</option>
                  <option value="contractor_business_name:asc">contractor name asc</option>
                  <option value="contractor_business_name:desc">contractor name desc</option>
                </Select>
              </Box>

              <Box w="120px">
                <Text fontSize="xs" opacity={0.7} mb={1}>
                  Per page
                </Text>
                <Select
                  value={String(per)}
                  onChange={(e) => setParams(navigate, location, { per: e.target.value, page: '1' })}
                  bg="white"
                >
                  <option value="25">25</option>
                  <option value="50">50</option>
                  <option value="100">100</option>
                </Select>
              </Box>

              <HStack spacing={2} pb={1}>
                <Tooltip label="Clear filters">
                  <IconButton
                    aria-label="Clear filters"
                    icon={<XCircle size={18} />}
                    variant="outline"
                    onClick={() => {
                      setParams(navigate, location, {
                        q: '',
                        status: '',
                        sort: 'updated_at:desc',
                        per: '25',
                        page: '1',
                      });
                    }}
                    isDisabled={!q.trim() && !status.trim() && sort === 'updated_at:desc' && per === 25}
                  />
                </Tooltip>

                <Tooltip label="Refresh grid">
                  <IconButton
                    aria-label="Refresh grid"
                    icon={<ArrowsClockwise size={18} />}
                    variant="outline"
                    onClick={fetchSessions}
                    isLoading={gridLoading}
                  />
                </Tooltip>
              </HStack>
            </Flex>

            {gridError && (
              <Box mb={3} p={3} bg="red.50" borderWidth="1px" borderColor="red.200" borderRadius="md">
                <Text as="div" fontSize="sm" color="red.700">
                  {gridError}
                </Text>
              </Box>
            )}

            <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="md" overflow="hidden" bg="white">
              <Table size="sm">
                <Thead bg="gray.50">
                  <Tr>
                    <Th>created</Th>
                    <Th>contractor</Th>
                    <Th>contractor #</Th>
                    <Th>city</Th>
                    <Th>session status</Th>
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
                        <Td fontFamily="mono" fontSize="xs" whiteSpace="nowrap">
                          {fmtDate(r.created_at)}
                        </Td>

                        <Td fontSize="sm" whiteSpace="nowrap">
                          {r.contractor_business_name ?? '—'}
                        </Td>

                        <Td fontFamily="mono" fontSize="xs" whiteSpace="nowrap">
                          {r.contractor_number ?? '—'}
                        </Td>

                        <Td fontSize="sm" whiteSpace="nowrap">
                          {r.contractor_city ?? '—'}
                        </Td>

                        <Td fontFamily="mono" fontSize="xs">
                          {r.status ?? '—'}
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
                      <Td colSpan={7}>
                        <Text as="div" fontSize="sm" opacity={0.7} p={3}>
                          No sessions found.
                        </Text>
                      </Td>
                    </Tr>
                  )}
                </Tbody>
              </Table>
            </Box>

            <Flex mt={4} justify="space-between" align="center" wrap="wrap" gap={3}>
              <Text as="div" fontSize="sm" opacity={0.8}>
                Total: {total}
              </Text>

              <HStack>
                <Tooltip label="Previous page">
                  <IconButton
                    aria-label="Previous page"
                    size="sm"
                    variant="outline"
                    icon={<CaretLeft size={16} />}
                    onClick={() => setParams(navigate, location, { page: String(Math.max(1, page - 1)) })}
                    isDisabled={page <= 1}
                  />
                </Tooltip>
                <Text fontSize="sm">
                  Page {page} of {totalPages}
                </Text>
                <Tooltip label="Next page">
                  <IconButton
                    aria-label="Next page"
                    size="sm"
                    variant="outline"
                    icon={<CaretRight size={16} />}
                    onClick={() => setParams(navigate, location, { page: String(Math.min(totalPages, page + 1)) })}
                    isDisabled={page >= totalPages}
                  />
                </Tooltip>
              </HStack>
            </Flex>
          </Box>

          {/* hidden file input (single file only) */}
          <input
            ref={fileInputRef}
            type="file"
            accept="application/pdf,.pdf"
            style={{ display: 'none' }}
            onChange={handleFilesChosen}
          />
        </Box>
      </Container>

      <Drawer isOpen={isHelpOpen} placement="left" onClose={onHelpClose} size="xl">
        <DrawerOverlay />
        <DrawerContent>
          <DrawerCloseButton />
          <DrawerHeader>Upload Invoice Admin Help</DrawerHeader>
          <DrawerBody>
            <Text fontSize="sm" mb={3}>
              This screen has a single flow: confirm session, upload invoice, then continue to processing/admin
              follow-up.
            </Text>

            <Text fontSize="sm" fontWeight="bold" mb={1}>
              Confirm session
            </Text>
            <Text fontSize="sm" mb={3}>
              Confirm the session populated from Invoices Admin before uploading. If needed, you can change it from the
              optional session grid at the bottom.
            </Text>

            <Text fontSize="sm" fontWeight="bold" mb={1}>
              Contractor relationship
            </Text>
            <Text fontSize="sm" mb={3}>
              One contractor belongs to the whole session. That means all invoices inside that session share the same
              contractor context.
            </Text>

            <Text fontSize="sm" fontWeight="bold" mb={1}>
              Upload invoice
            </Text>
            <Text fontSize="sm" mb={3}>
              Upload only stores the PDF file and creates upload records. It does not run OCR and it does not run GenAI
              checks.
            </Text>

            <Text fontSize="sm" fontWeight="bold" mb={1}>
              What happens next
            </Text>
            <Text fontSize="sm" mb={3}>
              After upload, run OCR and GenAI from the appropriate admin workflow when you are ready. Keeping upload
              separate from processing makes retries and troubleshooting easier.
            </Text>

            <Text fontSize="sm" fontWeight="bold" mb={1}>
              Simple example
            </Text>
            <Text fontSize="sm">
              If a session has 5 invoices, all 5 are tied to the same contractor through that session. Upload here only
              places files in storage; OCR/GenAI are separate processing steps.
            </Text>
          </DrawerBody>
        </DrawerContent>
      </Drawer>
    </Flex>
  );
});
