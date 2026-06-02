import React, { useCallback, useEffect, useMemo, useState } from 'react';
import {
  Badge,
  Box,
  Container,
  Flex,
  HStack,
  IconButton,
  Input,
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
import { ArrowsClockwise, CaretLeft, CaretRight, MagnifyingGlass, UploadSimple, XCircle } from '@phosphor-icons/react';
import { ThinBlueTitleBar } from '../../shared/base/thin-blue-title-bar';

type ImportRun = {
  id: string;
  ohpa_source_id: string;
  status: string;
  completed_at?: string | null;
  records_imported?: number | null;
  publishing_date?: string | null;
  publishing_notes?: string | null;
  error_text?: string | null;
};

type SourceStatus = {
  id: string;
  description: string;
  source_url: string;
  latest?: ImportRun | null;
  latest_success?: ImportRun | null;
};

type ProductRow = {
  id: string;
  ahri_reference_number: string;
  brand?: string | null;
  model_number?: string | null;
  indoor_model_numbers?: string | null;
  furnace_model_number?: string | null;
  product_group?: string | null;
  model_status?: string | null;
  rated_capacity_47f?: string | number | null;
  capacity_maintenance_percent?: string | number | null;
  cop_5f?: string | number | null;
  hspf2_region_iv?: string | number | null;
  seer2?: string | number | null;
  source_description?: string | null;
};

type ProductsResp = {
  rows: ProductRow[];
  meta?: {
    total?: number;
    page?: number;
    per?: number;
  };
};

type StatusResp = {
  sources?: SourceStatus[];
  latest?: ImportRun | null;
  latest_success?: ImportRun | null;
};

const fmtValue = (v?: string | number | null) => {
  if (v === null || v === undefined || v === '') return '-';
  return String(v);
};

const fmtDateTime = (s?: string | null) => {
  if (!s) return '-';
  return String(s)
    .replace('T', ' ')
    .replace(/\.\d+Z?$/, '')
    .slice(0, 19);
};

const statusColor = (status?: string | null) => {
  switch ((status || '').toLowerCase()) {
    case 'succeeded':
      return 'green';
    case 'failed':
      return 'red';
    case 'running':
    case 'queued':
      return 'yellow';
    default:
      return 'gray';
  }
};

const buildSearchParams = (obj: Record<string, string | undefined>) => {
  const params = new URLSearchParams();
  Object.entries(obj).forEach(([key, value]) => {
    const cleanValue = value?.trim();
    if (cleanValue) params.set(key, cleanValue);
  });
  return params;
};

export default function OhpaProductListAdminScreen() {
  const [q, setQ] = useState('');
  const [page, setPage] = useState(1);
  const [rows, setRows] = useState<ProductRow[]>([]);
  const [total, setTotal] = useState(0);
  const [status, setStatus] = useState<StatusResp>({});
  const [loadingRows, setLoadingRows] = useState(false);
  const [loadingStatus, setLoadingStatus] = useState(false);
  const [importingSourceId, setImportingSourceId] = useState('');
  const [error, setError] = useState('');

  const fetchStatus = useCallback(async () => {
    setLoadingStatus(true);
    try {
      const res = await fetch('/api/claims/admin/ohpa_products/import_status', {
        method: 'GET',
        headers: { Accept: 'application/json' },
        credentials: 'include',
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data?.error || `HTTP ${res.status}`);
      setStatus(data);
    } catch (e: any) {
      setError(e?.message || 'Failed to load OHPA import status.');
    } finally {
      setLoadingStatus(false);
    }
  }, []);

  const fetchRows = useCallback(async () => {
    setLoadingRows(true);
    setError('');
    try {
      const params = buildSearchParams({
        q: q || undefined,
        page: String(page || 1),
        per: '25',
        sort: 'ahri_reference_number:asc',
      });

      const res = await fetch(`/api/claims/admin/ohpa_products?${params.toString()}`, {
        method: 'GET',
        headers: { Accept: 'application/json' },
        credentials: 'include',
      });
      const data: ProductsResp = await res.json().catch(() => ({ rows: [] }) as ProductsResp);
      if (!res.ok) throw new Error((data as any)?.error || `HTTP ${res.status}`);

      setRows(Array.isArray(data.rows) ? data.rows : []);
      setTotal(Number(data.meta?.total || 0));
    } catch (e: any) {
      setRows([]);
      setTotal(0);
      setError(e?.message || 'Failed to load OHPA products.');
    } finally {
      setLoadingRows(false);
    }
  }, [page, q]);

  const importSource = async (source: SourceStatus) => {
    setImportingSourceId(source.id);
    setError('');

    try {
      const res = await fetch('/api/claims/admin/ohpa_products/import_downloaded_csv', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
        credentials: 'include',
        body: JSON.stringify({
          ohpa_source_id: source.id,
          publishing_notes: 'NRCan OHPA BC CSV import',
        }),
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok || data?.ok === false) throw new Error(data?.error || `HTTP ${res.status}`);

      await fetchStatus();
      await fetchRows();
    } catch (e: any) {
      setError(e?.message || 'OHPA import failed.');
      await fetchStatus();
    } finally {
      setImportingSourceId('');
    }
  };

  useEffect(() => {
    fetchStatus();
  }, [fetchStatus]);

  useEffect(() => {
    fetchRows();
  }, [fetchRows]);

  const totalPages = useMemo(() => Math.max(1, Math.ceil((total || 0) / 25)), [total]);
  const sourceStatuses = status.sources || [];

  return (
    <Flex as="main" direction="column" w="full" bg="greys.white" pb="24" minH="100vh">
      <ThinBlueTitleBar title="OHPA Product List Config" />

      <Container maxW="container.xl" pb={4} flex="1" pt={6}>
        <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="lg" p={5} bg="white" mb={4}>
          <Flex justify="space-between" gap={4} wrap="wrap" align="start">
            <Box>
              <Text fontSize="lg" fontWeight="bold">
                NRCan OHPA BC product list
              </Text>
              <Text fontSize="sm" opacity={0.75} mt={1} maxW="840px">
                This is the cached Oil to Heat Pump Affordability qualified product list for British Columbia used by
                code-owned oil heat-pump product-list checks.
              </Text>
            </Box>

            <Tooltip label="Reload status and grid">
              <IconButton
                aria-label="Reload status and grid"
                icon={<ArrowsClockwise size={18} />}
                variant="outline"
                onClick={() => {
                  fetchStatus();
                  fetchRows();
                }}
                isLoading={loadingStatus || loadingRows}
              />
            </Tooltip>
          </Flex>

          <Box mt={5} borderWidth="1px" borderRadius="md" overflow="auto">
            <Table size="sm" minW="900px">
              <Thead bg="gray.50">
                <Tr>
                  <Th>Description</Th>
                  <Th>Status</Th>
                  <Th>Latest success</Th>
                  <Th isNumeric>Rows</Th>
                  <Th>Actions</Th>
                </Tr>
              </Thead>
              <Tbody>
                {sourceStatuses.length === 0 ? (
                  <Tr>
                    <Td colSpan={5}>
                      <Flex align="center" gap={2} py={3}>
                        <Spinner size="sm" />
                        <Text>Loading OHPA source list...</Text>
                      </Flex>
                    </Td>
                  </Tr>
                ) : (
                  sourceStatuses.map((source) => (
                    <Tr key={source.id}>
                      <Td>
                        <Text fontWeight="semibold">{source.description}</Text>
                        <Text fontSize="xs" opacity={0.7} wordBreak="break-all">
                          {source.source_url}
                        </Text>
                        {source.latest?.error_text && (
                          <Text fontSize="xs" color="red.700" mt={1} whiteSpace="pre-wrap">
                            {source.latest.error_text}
                          </Text>
                        )}
                      </Td>
                      <Td>
                        <Badge colorScheme={statusColor(source.latest?.status)}>
                          {source.latest?.status || 'none'}
                        </Badge>
                      </Td>
                      <Td>{fmtDateTime(source.latest_success?.completed_at)}</Td>
                      <Td isNumeric>{fmtValue(source.latest_success?.records_imported)}</Td>
                      <Td>
                        <Tooltip label={`Download and import ${source.description}`}>
                          <IconButton
                            aria-label={`Download and import ${source.description}`}
                            icon={<UploadSimple size={16} />}
                            size="sm"
                            colorScheme="blue"
                            variant="outline"
                            onClick={() => importSource(source)}
                            isLoading={importingSourceId === source.id}
                          />
                        </Tooltip>
                      </Td>
                    </Tr>
                  ))
                )}
              </Tbody>
            </Table>
          </Box>
        </Box>

        <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="lg" p={5} bg="white">
          <Flex gap={3} align="end" wrap="wrap" mb={4}>
            <Box flex="1" minW="300px">
              <Text fontSize="xs" opacity={0.7} mb={1}>
                Search AHRI, brand, model, or series
              </Text>
              <Input
                value={q}
                onChange={(e) => {
                  setQ(e.target.value);
                  setPage(1);
                }}
                onKeyDown={(e) => {
                  if (e.key === 'Enter') fetchRows();
                }}
                placeholder="Example: 216032261 or Mitsubishi"
                bg="white"
              />
            </Box>

            <HStack spacing={2} pb={1}>
              <Tooltip label="Search now">
                <IconButton aria-label="Search now" icon={<MagnifyingGlass size={18} />} onClick={fetchRows} />
              </Tooltip>
              <Tooltip label="Clear search">
                <IconButton
                  aria-label="Clear search"
                  icon={<XCircle size={18} />}
                  variant="outline"
                  onClick={() => {
                    setQ('');
                    setPage(1);
                  }}
                  isDisabled={!q.trim()}
                />
              </Tooltip>
            </HStack>
          </Flex>

          {error && (
            <Box mb={4} p={3} borderWidth="1px" borderRadius="md" borderColor="red.300" bg="red.50">
              <Text color="red.800" fontSize="sm" whiteSpace="pre-wrap">
                {error}
              </Text>
            </Box>
          )}

          <Box borderWidth="1px" borderRadius="md" overflow="auto">
            <Table size="sm" minW="1200px">
              <Thead bg="gray.50">
                <Tr>
                  <Th>AHRI</Th>
                  <Th>Brand</Th>
                  <Th>Outdoor model</Th>
                  <Th>Indoor model(s)</Th>
                  <Th>Furnace</Th>
                  <Th>Group</Th>
                  <Th>Status</Th>
                  <Th isNumeric>47F BTU</Th>
                  <Th isNumeric>5F %</Th>
                  <Th isNumeric>COP 5F</Th>
                  <Th isNumeric>HSPF2 IV</Th>
                  <Th isNumeric>SEER2</Th>
                </Tr>
              </Thead>
              <Tbody>
                {loadingRows ? (
                  <Tr>
                    <Td colSpan={12}>
                      <Flex align="center" gap={2} py={3}>
                        <Spinner size="sm" />
                        <Text>Loading OHPA rows...</Text>
                      </Flex>
                    </Td>
                  </Tr>
                ) : rows.length === 0 ? (
                  <Tr>
                    <Td colSpan={12}>
                      <Text py={3} opacity={0.8}>
                        No OHPA product rows found. Import the NRCan CSV first, or adjust your search.
                      </Text>
                    </Td>
                  </Tr>
                ) : (
                  rows.map((row) => (
                    <Tr key={row.id}>
                      <Td fontWeight="semibold">{fmtValue(row.ahri_reference_number)}</Td>
                      <Td>{fmtValue(row.brand)}</Td>
                      <Td>
                        <Text fontWeight="semibold">{fmtValue(row.model_number)}</Text>
                        {row.series_name && (
                          <Text fontSize="xs" opacity={0.7}>
                            {row.series_name}
                          </Text>
                        )}
                      </Td>
                      <Td>{fmtValue(row.indoor_model_numbers)}</Td>
                      <Td>{fmtValue(row.furnace_model_number)}</Td>
                      <Td>{fmtValue(row.product_group)}</Td>
                      <Td>{fmtValue(row.model_status)}</Td>
                      <Td isNumeric>{fmtValue(row.rated_capacity_47f)}</Td>
                      <Td isNumeric>{fmtValue(row.capacity_maintenance_percent)}</Td>
                      <Td isNumeric>{fmtValue(row.cop_5f)}</Td>
                      <Td isNumeric>{fmtValue(row.hspf2_region_iv)}</Td>
                      <Td isNumeric>{fmtValue(row.seer2)}</Td>
                    </Tr>
                  ))
                )}
              </Tbody>
            </Table>
          </Box>

          <Flex mt={4} justify="space-between" align="center" wrap="wrap" gap={3}>
            <Text fontSize="sm" opacity={0.8}>
              Total: {total}
            </Text>

            <Flex gap={2} align="center">
              <Tooltip label="Previous page">
                <IconButton
                  aria-label="Previous page"
                  size="sm"
                  variant="outline"
                  icon={<CaretLeft size={16} />}
                  isDisabled={page <= 1 || loadingRows}
                  onClick={() => setPage((current) => Math.max(1, current - 1))}
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
                  isDisabled={page >= totalPages || loadingRows}
                  onClick={() => setPage((current) => Math.min(totalPages, current + 1))}
                />
              </Tooltip>
            </Flex>
          </Flex>
        </Box>
      </Container>
    </Flex>
  );
}
