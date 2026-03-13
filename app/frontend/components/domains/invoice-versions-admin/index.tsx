import { Box, Container, Drawer, DrawerBody, DrawerCloseButton, DrawerContent, DrawerHeader, DrawerOverlay, Flex, IconButton, Input, Text, Tooltip } from '@chakra-ui/react';
import { Table, Thead, Tbody, Tr, Th, Td, Spinner } from '@chakra-ui/react';
import { Tabs, TabList, TabPanels, Tab, TabPanel } from '@chakra-ui/react';
import { Info } from '@phosphor-icons/react';
import { ThinBlueTitleBar } from '../../shared/base/thin-blue-title-bar';
import React, { useEffect, useState } from 'react';
import { useLocation } from 'react-router-dom';


type InvoiceVersionRow = {
  id: string;
  invoice_id: string;
  invoice_versionno: number;

  storage_provider?: string | null;
  storage_key?: string | null;
  original_filename?: string | null;

  di_ocr_invoice_id?: string | null;
  di_ocr_invoice_date?: string | null;
  di_ocr_vendor_name?: string | null;
  di_ocr_invoice_total?: string | number | null;

  created_at?: string;
  updated_at?: string;
};

type InvoiceVersionDetail = {
  id: string;
  invoice_id: string;
  invoice_versionno: number;
  di_raw_json?: any | null;
  genai_raw_json?: any | null;
  [key: string]: any;
};

type InvoiceMeta = {
  id: string;
  status?: string | null;
  created_at?: string | null;
  updated_at?: string | null;
  status_updated_at?: string | null;
};

const fmtTs = (s?: string | null) => (s ? String(s).replace('T', ' ').replace('Z', '') : '');
const fmtDate = (s?: string | null) => {
  if (!s) return '—';
  const raw = String(s);
  if (raw.includes('T')) return raw.split('T')[0];
  return raw.slice(0, 10);
};

function prettyJson(v: any): string {
  if (v === null || v === undefined) return '';
  try {
    return JSON.stringify(v, null, 2);
  } catch {
    return String(v);
  }
}

export function InvoiceVersionsAdminScreen() {
  const [invoiceId, setInvoiceId] = useState<string>('');
  const [invoiceMeta, setInvoiceMeta] = useState<InvoiceMeta | null>(null);
  const [loading, setLoading] = useState<boolean>(false);
  const [loadingDetail, setLoadingDetail] = useState<boolean>(false);
  const [error, setError] = useState<string>('');

  const [rows, setRows] = useState<InvoiceVersionRow[]>([]);
  const [selectedVersionId, setSelectedVersionId] = useState<string>('');
  const [selectedDetail, setSelectedDetail] = useState<InvoiceVersionDetail | null>(null);
  const [isDrawerOpen, setIsDrawerOpen] = useState<boolean>(false);

  const [diJson, setDiJson] = useState<any | null>(null);
  const [genaiJson, setGenaiJson] = useState<any | null>(null);

  // ============================================================
  // SECTION 01 — ROUTE QUERYSTRING (prefill invoice_id)
  // PURPOSE: allow /invoice-versions-admin?invoice_id=... to auto-fill the input
  // ============================================================

  const location = useLocation();

  useEffect(() => {
    const params = new URLSearchParams(location.search);
    const q = params.get('invoice_id');
    if (q && q.trim()) setInvoiceId(q.trim());
  }, [location.search]);

  const fetchRows = async (id: string) => {
    setLoading(true);
    setError('');
    setRows([]);
    setInvoiceMeta(null);
    setSelectedVersionId('');
    setSelectedDetail(null);
    setDiJson(null);
    setGenaiJson(null);

    try {
      if (!id.trim()) throw new Error('Missing invoice_id.');

      const url = `/api/claims/admin/invoices/${encodeURIComponent(id.trim())}/invoice_versions`;

      const res = await fetch(url, {
        method: 'GET',
        headers: { Accept: 'application/json' },
        credentials: 'include',
      });

      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data?.error || data?.message || `HTTP ${res.status}`);

      setRows(Array.isArray(data?.invoice_versions) ? data.invoice_versions : []);
      setInvoiceMeta(data?.invoice || null);
    } catch (e: any) {
      setError(e?.message || 'Failed to load invoice_versions.');
    } finally {
      setLoading(false);
    }
  };

  const fetchVersionDetail = async (invoiceVersionId: string) => {
    setLoadingDetail(true);
    setError('');
    setSelectedVersionId(invoiceVersionId);

    try {

const url = `/api/claims/admin/invoice_versions/${encodeURIComponent(invoiceVersionId)}`;

      const res = await fetch(url, {
        method: 'GET',
        headers: { Accept: 'application/json' },
        credentials: 'include',
      });

      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data?.error || data?.message || `HTTP ${res.status}`);

      const iv: InvoiceVersionDetail | undefined = data?.invoice_version;
      if (!iv) throw new Error('Missing invoice_version in response.');

      setSelectedDetail(iv);
      setDiJson(iv.di_raw_json ?? null);
      setGenaiJson(iv.genai_raw_json ?? null);
    } catch (e: any) {
      setError(e?.message || 'Failed to load JSON blobs.');
      setSelectedVersionId('');
    } finally {
      setLoadingDetail(false);
    }
  };

  useEffect(() => {
    if (!invoiceId.trim()) return;
    fetchRows(invoiceId.trim());
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [invoiceId]);

  const openDetailsDrawer = async (invoiceVersionId: string) => {
    await fetchVersionDetail(invoiceVersionId);
    setIsDrawerOpen(true);
  };

  const detailEntries = selectedDetail
    ? Object.entries(selectedDetail).sort(([a], [b]) => a.localeCompare(b))
    : [];

  return (
    <Flex as="main" direction="column" w="full" bg="greys.white" pb="24" minH="100vh">
      <ThinBlueTitleBar title="Versions History Inspection" />

      <Container maxW="container.xl" pb={4} flex="1" pt={6}>
        <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="lg" p={5} bg="white">
          {/* invoice context */}
          <Flex gap={3} align="end" wrap="wrap" mb={4}>
            <Box flex="1" minW="360px">
              <Text fontSize="xs" opacity={0.7} mb={1}>
                invoice_id
              </Text>
              <Input
                value={invoiceId}
                isReadOnly
                bg="white"
                fontFamily="mono"
              />
            </Box>

            <Box minW="220px">
              <Text fontSize="xs" opacity={0.7} mb={1}>
                invoices.status
              </Text>
              <Input value={invoiceMeta?.status || '—'} isReadOnly bg="white" />
            </Box>

            <Box minW="220px">
              <Text fontSize="xs" opacity={0.7} mb={1}>
                invoices.created_at
              </Text>
              <Input value={fmtDate(invoiceMeta?.created_at)} isReadOnly bg="white" />
            </Box>
          </Flex>

          {error && (
            <Box mb={4} p={3} bg="red.50" borderWidth="1px" borderColor="red.200" borderRadius="md">
              <Text fontSize="sm" color="red.700">
                {error}
              </Text>
            </Box>
          )}

          {/* grid */}
          <Box bg="white" borderWidth="1px" borderColor="greys.grey20" borderRadius="md" p={3} mb={4}>
            <Flex align="center" justify="space-between" mb={2}>
              <Text fontSize="sm" fontWeight="bold">
                Invoice versions
              </Text>
              {loading && <Spinner size="sm" />}
            </Flex>

            <Table size="sm">
              <Thead>
                <Tr>
                  <Th>updated</Th>
                  <Th>version</Th>
                  <Th>di_invoice_id</Th>
                  <Th>vendor</Th>
                  <Th isNumeric>total</Th>
                  <Th></Th>
                </Tr>
              </Thead>

              <Tbody>
                {rows.map((r) => (
                  <Tr
                    key={r.id}
                    bg={r.id === selectedVersionId ? 'gray.50' : undefined}
                    borderLeftWidth={r.id === selectedVersionId ? '4px' : '0'}
                    borderLeftColor={r.id === selectedVersionId ? 'blue.500' : 'transparent'}
                    cursor="pointer"
                    onClick={() => fetchVersionDetail(r.id)}
                  >
                    <Td fontFamily="mono" fontSize="xs">
                      {fmtTs(r.updated_at)}
                    </Td>
                    <Td fontFamily="mono" fontSize="xs">
                      {r.invoice_versionno}
                    </Td>
                    <Td fontFamily="mono" fontSize="xs">
                      {r.di_ocr_invoice_id ?? ''}
                    </Td>
                    <Td fontSize="xs" maxW="280px">
                      {r.di_ocr_vendor_name ?? ''}
                    </Td>
                    <Td fontFamily="mono" fontSize="xs" isNumeric>
                      {r.di_ocr_invoice_total ?? ''}
                    </Td>
                    <Td>
                      <Tooltip label="Open all invoice_version fields">
                        <IconButton
                          aria-label="Open invoice version details"
                          icon={<Info size={16} />}
                          size="xs"
                          variant="outline"
                          onClick={(e) => {
                            e.stopPropagation();
                            openDetailsDrawer(r.id);
                          }}
                          isLoading={loadingDetail && selectedVersionId === r.id}
                        />
                      </Tooltip>
                    </Td>
                  </Tr>
                ))}

                {!loading && rows.length === 0 && (
                  <Tr>
                    <Td colSpan={6}>
                      <Text fontSize="sm" opacity={0.7}>
                        No versions found for this invoice.
                      </Text>
                    </Td>
                  </Tr>
                )}
              </Tbody>
            </Table>
          </Box>

          {/* json panels */}
          <Box bg="white" borderWidth="1px" borderColor="greys.grey20" borderRadius="md" p={3}>
            <Flex align="center" justify="space-between" mb={2}>
              <Text fontSize="sm" fontWeight="bold">
                JSON displays {selectedVersionId ? `(invoice_version_id: ${selectedVersionId})` : ''}
              </Text>
              {loadingDetail && <Spinner size="sm" />}
            </Flex>

 
<Tabs
  variant="line"
  isFitted
  colorScheme="gray"
  sx={{
    // ============================================================
    // SECTION 04.02.01.01 — BOLDER LINE TAB STYLE
    // PURPOSE: Make the underline + baseline thicker/darker
    // ============================================================

    // the baseline under all tabs
    ".chakra-tabs__tablist": {
      borderBottomWidth: "2px",
      borderColor: "gray.300",
    },

    // the active tab underline
    ".chakra-tabs__tab[aria-selected=true]": {
      borderBottomWidth: "4px",
      borderColor: "gray.800",
    },
  }}
>

              <TabList>
                <Tab>DI JSON</Tab>
                <Tab>GenAI JSON</Tab>
              </TabList>

              <TabPanels>
                <TabPanel p={3}>
                  <Box
                    as="pre"
                    fontFamily="mono"
                    fontSize="xs"
                    whiteSpace="pre-wrap"
                    overflow="auto"
                    maxH="520px"
                    borderWidth="1px"
                    borderColor="greys.grey20"
                    borderRadius="md"
                    p={3}
                    bg="gray.50"
                  >
                    {selectedVersionId ? prettyJson(diJson) : 'Select a row to load JSON.'}
                  </Box>
                </TabPanel>

                <TabPanel p={3}>
                  <Box
                    as="pre"
                    fontFamily="mono"
                    fontSize="xs"
                    whiteSpace="pre-wrap"
                    overflow="auto"
                    maxH="520px"
                    borderWidth="1px"
                    borderColor="greys.grey20"
                    borderRadius="md"
                    p={3}
                    bg="gray.50"
                  >
                    {selectedVersionId ? prettyJson(genaiJson) : 'Select a row to load JSON.'}
                  </Box>
                </TabPanel>
              </TabPanels>
            </Tabs>
          </Box>
        </Box>
      </Container>

      <Drawer isOpen={isDrawerOpen} placement="right" onClose={() => setIsDrawerOpen(false)} size="md">
        <DrawerOverlay />
        <DrawerContent>
          <DrawerCloseButton />
          <DrawerHeader>Invoice Version Full Details</DrawerHeader>
          <DrawerBody>
            {!selectedDetail ? (
              <Text fontSize="sm" opacity={0.7}>No row selected.</Text>
            ) : (
              <Flex direction="column" gap={3}>
                {detailEntries.map(([k, v]) => (
                  <Box key={k}>
                    <Text fontSize="xs" opacity={0.7} mb={1}>{k}</Text>
                    {typeof v === 'object' && v !== null ? (
                      <Box
                        as="pre"
                        fontFamily="mono"
                        fontSize="xs"
                        whiteSpace="pre-wrap"
                        borderWidth="1px"
                        borderColor="greys.grey20"
                        borderRadius="md"
                        p={2}
                        bg="gray.50"
                        maxH="220px"
                        overflow="auto"
                      >
                        {prettyJson(v)}
                      </Box>
                    ) : (
                      <Text fontSize="sm" fontFamily={k.endsWith('_id') ? 'mono' : undefined} whiteSpace="pre-wrap">
                        {v === null || v === undefined || v === '' ? '—' : String(v)}
                      </Text>
                    )}
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