import { Box, Button, Container, Flex, Heading, Input, Text } from '@chakra-ui/react';
import { Table, Thead, Tbody, Tr, Th, Td, Spinner } from '@chakra-ui/react';
import { Tabs, TabList, TabPanels, Tab, TabPanel } from '@chakra-ui/react';
import { BlueTitleBar } from '../../shared/base/blue-title-bar';
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
  di_raw_json: any | null;
  genai_raw_json: any | null;
  di_page_map: any | null;
};

const fmtTs = (s?: string | null) => (s ? String(s).replace('T', ' ').replace('Z', '') : '');

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
  const [loading, setLoading] = useState<boolean>(false);
  const [loadingJson, setLoadingJson] = useState<boolean>(false);
  const [error, setError] = useState<string>('');

  const [rows, setRows] = useState<InvoiceVersionRow[]>([]);
  const [selectedVersionId, setSelectedVersionId] = useState<string>('');

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

  const handleRefresh = async () => {
    setLoading(true);
    setError('');
    setRows([]);
    setSelectedVersionId('');
    setDiJson(null);
    setGenaiJson(null);

    try {
      if (!invoiceId.trim()) throw new Error('Please enter an invoice_id.');

      const url = `/api/claims/admin/invoices/${encodeURIComponent(invoiceId.trim())}/invoice_versions`;

      const res = await fetch(url, {
        method: 'GET',
        headers: { Accept: 'application/json' },
        credentials: 'include',
      });

      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data?.error || data?.message || `HTTP ${res.status}`);

      setRows(Array.isArray(data?.invoice_versions) ? data.invoice_versions : []);
    } catch (e: any) {
      setError(e?.message || 'Failed to load invoice_versions.');
    } finally {
      setLoading(false);
    }
  };

  const handleShowJson = async (invoiceVersionId: string) => {
    setLoadingJson(true);
    setError('');
    setSelectedVersionId(invoiceVersionId);
    setDiJson(null);
    setGenaiJson(null);

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

      setDiJson(iv.di_raw_json ?? null);
      setGenaiJson(iv.genai_raw_json ?? null);
    } catch (e: any) {
      setError(e?.message || 'Failed to load JSON blobs.');
      setSelectedVersionId('');
    } finally {
      setLoadingJson(false);
    }
  };

  return (
    <Flex as="main" direction="column" w="full" bg="greys.white" pb="24" minH="100vh">
      <BlueTitleBar title="Invoice Versions Admin" />

      <Container maxW="container.xl" pb={4} flex="1" pt={6}>
        <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="lg" p={5} bg="white">
          <Heading size="md" mb={2}>
            Invoice versions by invoice
          </Heading>

          <Text fontSize="sm" opacity={0.8} mb={4}>
            Shows <code>claims.invoice_versions</code> rows for a single invoice (ALL versions).
          </Text>

          {/* invoice_id + refresh */}
          <Flex gap={3} align="end" wrap="wrap" mb={4}>
            <Box flex="1" minW="360px">
              <Text fontSize="xs" opacity={0.7} mb={1}>
                invoice_id
              </Text>
              <Input
                value={invoiceId}
                onChange={(e) => setInvoiceId(e.target.value)}
                placeholder="paste invoice UUID"
                bg="white"
                fontFamily="mono"
              />
            </Box>

            <Button onClick={handleRefresh} isLoading={loading} loadingText="Refreshing...">
              Refresh
            </Button>
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
                  <Th>invoice_version_id</Th>
                  <Th>di_invoice_id</Th>
                  <Th>vendor</Th>
                  <Th isNumeric>total</Th>
                  <Th></Th>
                </Tr>
              </Thead>

              <Tbody>
                {rows.map((r) => (
                  <Tr key={r.id} bg={r.id === selectedVersionId ? 'gray.50' : undefined}>
                    <Td fontFamily="mono" fontSize="xs">
                      {fmtTs(r.updated_at)}
                    </Td>
                    <Td fontFamily="mono" fontSize="xs">
                      {r.invoice_versionno}
                    </Td>
                    <Td fontFamily="mono" fontSize="xs">
                      {r.id}
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
                      <Button
                        size="xs"
                        variant="outline"
                        onClick={() => handleShowJson(r.id)}
                        isLoading={loadingJson && selectedVersionId === r.id}
                        loadingText="Loading..."
                      >
                        Show JSON
                      </Button>
                    </Td>
                  </Tr>
                ))}

                {!loading && rows.length === 0 && (
                  <Tr>
                    <Td colSpan={7}>
                      <Text fontSize="sm" opacity={0.7}>
                        Enter an invoice_id and click Refresh.
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
              {loadingJson && <Spinner size="sm" />}
            </Flex>

            <Tabs variant="enclosed" isFitted>
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
                    {selectedVersionId ? prettyJson(diJson) : 'Select a row and click “Show JSON”.'}
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
                    {selectedVersionId ? prettyJson(genaiJson) : 'Select a row and click “Show JSON”.'}
                  </Box>
                </TabPanel>
              </TabPanels>
            </Tabs>
          </Box>
        </Box>
      </Container>
    </Flex>
  );
}