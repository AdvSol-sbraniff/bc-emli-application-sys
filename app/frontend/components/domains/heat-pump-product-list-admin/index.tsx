import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  Badge,
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
  Modal,
  ModalBody,
  ModalCloseButton,
  ModalContent,
  ModalFooter,
  ModalHeader,
  ModalOverlay,
  Select,
  Spinner,
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
import { ArrowsClockwise, CaretLeft, CaretRight, Info, MagnifyingGlass, UploadSimple, XCircle } from '@phosphor-icons/react';
import { useLocation, useNavigate } from 'react-router-dom';
import { ThinBlueTitleBar } from '../../shared/base/thin-blue-title-bar';

type ImportRun = {
  id: string;
  ahri_source_id: string;
  storage_provider?: string | null;
  storage_key?: string | null;
  content_type?: string | null;
  byte_size?: number | null;
  status: 'queued' | 'running' | 'succeeded' | 'failed' | string;
  started_at?: string | null;
  completed_at?: string | null;
  records_imported?: number | null;
  publishing_notes?: string | null;
  publishing_date?: string | null;
  file_sha256?: string | null;
  error_text?: string | null;
};

type ProductRow = {
  id: string;
  ahri_reference_number: string;
  ahri_source_id?: string | null;
  source_description?: string | null;
  heat_pump_type?: string | null;
  make?: string | null;
  outdoor_model?: string | null;
  indoor_model_or_air_handler?: string | null;
  furnace_model?: string | null;
  rated_capacity_btu_at_minus_5c?: string | number | null;
  seer?: string | number | null;
  seer2?: string | number | null;
  hspf?: string | number | null;
  hspf2?: string | number | null;
  cop?: string | number | null;
  capacity_maintenance_percent?: string | number | null;
  cold_climate_rated?: boolean | null;
  eligibility_notes?: string | null;
};

type ProductsResp = {
  rows: ProductRow[];
  meta?: {
    total?: number;
    page?: number;
    per?: number;
    sort?: string;
  };
};

type StatusResp = {
  sources?: SourceStatus[];
  latest?: ImportRun | null;
  latest_success?: ImportRun | null;
};

type SourceStatus = {
  id: string;
  description: string;
  source_url: string;
  latest?: ImportRun | null;
  latest_success?: ImportRun | null;
};

const fmtDateTime = (s?: string | null) => {
  if (!s) return '-';
  return String(s).replace('T', ' ').replace(/\.\d+Z?$/, '').slice(0, 19);
};

const fmtDate = (s?: string | null) => {
  if (!s) return '-';
  return String(s).slice(0, 10);
};

const fmtValue = (v?: string | number | boolean | null) => {
  if (v === null || v === undefined || v === '') return '-';
  if (typeof v === 'boolean') return v ? 'Yes' : 'No';
  return String(v);
};

function buildSearchParams(obj: Record<string, string | undefined>) {
  const p = new URLSearchParams();
  Object.entries(obj).forEach(([k, v]) => {
    const value = v?.toString().trim();
    if (value) p.set(k, value);
  });
  return p;
}

function statusColor(status?: string | null) {
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
}

export default function HeatPumpProductListAdminScreen() {
  const location = useLocation();
  const navigate = useNavigate();
  const didInitFromUrl = useRef(false);
  const {
    isOpen: isImportDialogOpen,
    onOpen: onImportDialogOpen,
    onClose: onImportDialogClose,
  } = useDisclosure();
  const {
    isOpen: isSourceInfoOpen,
    onOpen: onSourceInfoOpen,
    onClose: onSourceInfoClose,
  } = useDisclosure();

  const [q, setQ] = useState('');
  const [ahriSourceId, setAhriSourceId] = useState('');
  const [sort, setSort] = useState('ahri_reference_number:asc');
  const [page, setPage] = useState(1);
  const [per, setPer] = useState(25);

  const [rows, setRows] = useState<ProductRow[]>([]);
  const [total, setTotal] = useState(0);
  const [status, setStatus] = useState<StatusResp>({});
  const [loadingRows, setLoadingRows] = useState(false);
  const [loadingStatus, setLoadingStatus] = useState(false);
  const [importingSourceId, setImportingSourceId] = useState('');
  const [importingPdf, setImportingPdf] = useState(false);
  const [editingSourceId, setEditingSourceId] = useState('');
  const [infoSourceId, setInfoSourceId] = useState('');
  const [publishingNotes, setPublishingNotes] = useState('');
  const [publishingDate, setPublishingDate] = useState('');
  const [error, setError] = useState('');

  useEffect(() => {
    const params = new URLSearchParams(location.search);
    const next = {
      q: params.get('q') || '',
      ahriSourceId: params.get('ahri_source_id') || '',
      sort: params.get('sort') || 'ahri_reference_number:asc',
      page: Number(params.get('page') || '1') || 1,
      per: Number(params.get('per') || '25') || 25,
    };

    didInitFromUrl.current = true;
    setQ(next.q);
    setAhriSourceId(next.ahriSourceId);
    setSort(next.sort);
    setPage(next.page);
    setPer(next.per);
  }, [location.search]);

  const pushUrl = (next: Partial<{ q: string; ahriSourceId: string; sort: string; page: number; per: number }>) => {
    const merged = { q, ahriSourceId, sort, page, per, ...next };
    const params = buildSearchParams({
      q: merged.q || undefined,
      ahri_source_id: merged.ahriSourceId || undefined,
      sort: merged.sort || undefined,
      page: String(merged.page || 1),
      per: String(merged.per || 25),
    });

    navigate({ pathname: location.pathname, search: `?${params.toString()}` }, { replace: true });
  };

  const fetchStatus = useCallback(async () => {
    setLoadingStatus(true);
    try {
      const res = await fetch('/api/claims/admin/ahri_products/import_status', {
        method: 'GET',
        headers: { Accept: 'application/json' },
        credentials: 'include',
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data?.error || `HTTP ${res.status}`);
      setStatus(data);
    } catch (e: any) {
      setError(e?.message || 'Failed to load import status.');
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
        ahri_source_id: ahriSourceId || undefined,
        sort: sort || undefined,
        page: String(page || 1),
        per: String(per || 25),
      });

      const res = await fetch(`/api/claims/admin/ahri_products?${params.toString()}`, {
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
      setError(e?.message || 'Failed to load heat pump products.');
    } finally {
      setLoadingRows(false);
    }
  }, [page, per, q, ahriSourceId, sort]);

  const openImportDialog = (source: SourceStatus) => {
    setEditingSourceId(source.id);
    setPublishingDate('');
    setPublishingNotes('');
    onImportDialogOpen();
  };

  const importDownloadedPdf = async () => {
    setImportingSourceId(editingSourceId);
    setImportingPdf(true);
    setError('');

    try {
      const res = await fetch('/api/claims/admin/ahri_products/import_downloaded_pdf', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
        credentials: 'include',
        body: JSON.stringify({
          ahri_source_id: editingSourceId,
          publishing_date: publishingDate,
          publishing_notes: publishingNotes,
        }),
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok || data?.ok === false) throw new Error(data?.error || `HTTP ${res.status}`);

      await fetchStatus();
      await fetchRows();
      onImportDialogClose();
    } catch (e: any) {
      setError(e?.message || 'Import failed.');
      await fetchStatus();
    } finally {
      setImportingSourceId('');
      setImportingPdf(false);
    }
  };

  const openSourceInfo = (source: SourceStatus) => {
    setInfoSourceId(source.id);
    onSourceInfoOpen();
  };

  useEffect(() => {
    fetchStatus();
  }, [fetchStatus]);

  useEffect(() => {
    if (didInitFromUrl.current) fetchRows();
  }, [fetchRows]);

  const totalPages = useMemo(() => Math.max(1, Math.ceil((total || 0) / Math.max(1, per))), [total, per]);
  const sourceStatuses = status.sources || [];
  const editingSource = sourceStatuses.find((row) => row.id === editingSourceId);
  const infoSource = sourceStatuses.find((row) => row.id === infoSourceId);

  return (
    <Flex as="main" direction="column" w="full" bg="greys.white" pb="24" minH="100vh">
      <ThinBlueTitleBar title="AHRI Heat Pump Product List Config" />

      <Container maxW="container.xl" pb={4} flex="1" pt={6}>
        <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="lg" p={5} bg="white" mb={4}>
          <Flex justify="space-between" gap={4} wrap="wrap" align="start">
            <Box>
              <Text fontSize="lg" fontWeight="bold">
                BC Hydro AHRI Heat Pump Product Lists
              </Text>
              <Text fontSize="sm" opacity={0.75} mt={1} maxW="760px">
                This is the cached reference data used by future code-owned AHRI and heat-pump performance checks. For
                AHRI matching, code searches the current rows from each successful source-list import.
              </Text>
            </Box>

            <HStack spacing={2}>
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
            </HStack>
          </Flex>

          <Box mt={5} borderWidth="1px" borderRadius="md" overflow="auto">
            <Table size="sm" minW="1180px">
              <Thead bg="gray.50">
                <Tr>
                  <Th>description</Th>
                  <Th>Status</Th>
                  <Th>Latest success</Th>
                  <Th isNumeric>Rows</Th>
                  <Th>Published</Th>
                  <Th>Actions</Th>
                </Tr>
              </Thead>
              <Tbody>
                {sourceStatuses.length === 0 ? (
                  <Tr>
                    <Td colSpan={6}>
                      <Flex align="center" gap={2} py={3}>
                        <Spinner size="sm" />
                        <Text>Loading source lists...</Text>
                      </Flex>
                    </Td>
                  </Tr>
                ) : (
                  sourceStatuses.map((source) => (
                    <Tr key={source.id}>
                      <Td>
                        <Text fontWeight="semibold">
                          {source.description}
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
                      <Td>{fmtDate(source.latest_success?.publishing_date)}</Td>
                      <Td>
                        <HStack spacing={1}>
                          <Tooltip label={`Show source details for ${source.description}`}>
                            <IconButton
                              aria-label={`Show source details for ${source.description}`}
                              icon={<Info size={16} />}
                              size="sm"
                              variant="outline"
                              onClick={() => openSourceInfo(source)}
                            />
                          </Tooltip>
                          <Tooltip label={`Import ${source.description}`}>
                            <IconButton
                              aria-label={`Import ${source.description}`}
                              icon={<UploadSimple size={16} />}
                              size="sm"
                              colorScheme="blue"
                              variant="outline"
                              onClick={() => openImportDialog(source)}
                              isLoading={importingSourceId === source.id}
                            />
                          </Tooltip>
                        </HStack>
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
                Search AHRI, make, model, or type
              </Text>
              <Input
                value={q}
                onChange={(e) => {
                  setQ(e.target.value);
                  setPage(1);
                }}
                onBlur={() => pushUrl({ q, page: 1 })}
                placeholder="Example: 213617706 or Mitsubishi"
                bg="white"
              />
            </Box>

            <Box w="230px">
              <Text fontSize="xs" opacity={0.7} mb={1}>
                AHRI source
              </Text>
              <Select
                value={ahriSourceId}
                onChange={(e) => {
                  const v = e.target.value;
                  setAhriSourceId(v);
                  setPage(1);
                  pushUrl({ ahriSourceId: v, page: 1 });
                }}
              >
                <option value="">All current product lists</option>
                {sourceStatuses.map((source) => (
                  <option key={source.id} value={source.id}>
                    {source.description}
                  </option>
                ))}
              </Select>
            </Box>

            <Box w="230px">
              <Text fontSize="xs" opacity={0.7} mb={1}>
                Sort
              </Text>
              <Select
                value={sort}
                onChange={(e) => {
                  const v = e.target.value;
                  setSort(v);
                  setPage(1);
                  pushUrl({ sort: v, page: 1 });
                }}
              >
                <option value="ahri_reference_number:asc">AHRI asc</option>
                <option value="ahri_reference_number:desc">AHRI desc</option>
                <option value="make:asc">make asc</option>
                <option value="make:desc">make desc</option>
                <option value="outdoor_model:asc">outdoor model asc</option>
                <option value="seer2:desc">SEER2 desc</option>
                <option value="hspf2:desc">HSPF2 desc</option>
              </Select>
            </Box>

            <Box w="120px">
              <Text fontSize="xs" opacity={0.7} mb={1}>
                Per page
              </Text>
              <Select
                value={String(per)}
                onChange={(e) => {
                  const v = Number(e.target.value) || 25;
                  setPer(v);
                  setPage(1);
                  pushUrl({ per: v, page: 1 });
                }}
              >
                <option value="25">25</option>
                <option value="50">50</option>
                <option value="100">100</option>
              </Select>
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
                    setAhriSourceId('');
                    setSort('ahri_reference_number:asc');
                    setPage(1);
                    setPer(25);
                    pushUrl({ q: '', ahriSourceId: '', sort: 'ahri_reference_number:asc', page: 1, per: 25 });
                  }}
                  isDisabled={
                    !q.trim() &&
                    !ahriSourceId &&
                    sort === 'ahri_reference_number:asc' &&
                    per === 25 &&
                    page === 1
                  }
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
            <Table size="sm" minW="1300px">
              <Thead bg="gray.50">
                <Tr>
                  <Th>AHRI</Th>
                  <Th>Source</Th>
                  <Th>Type</Th>
                  <Th>Make</Th>
                  <Th>Outdoor model</Th>
                  <Th>Indoor / air handler</Th>
                  <Th isNumeric>Capacity @ -5C</Th>
                  <Th isNumeric>SEER2</Th>
                  <Th isNumeric>HSPF2</Th>
                  <Th isNumeric>COP</Th>
                  <Th isNumeric>Capacity maint.</Th>
                  <Th>Cold climate</Th>
                </Tr>
              </Thead>
              <Tbody>
                {loadingRows ? (
                  <Tr>
                    <Td colSpan={12}>
                      <Flex align="center" gap={2} py={3}>
                        <Spinner size="sm" />
                        <Text>Loading product rows...</Text>
                      </Flex>
                    </Td>
                  </Tr>
                ) : rows.length === 0 ? (
                  <Tr>
                    <Td colSpan={12}>
                      <Text py={3} opacity={0.8}>
                        No product rows found. Import one or more BC Hydro PDFs first, or adjust your search.
                      </Text>
                    </Td>
                  </Tr>
                ) : (
                  rows.map((row) => (
                    <Tr key={row.id}>
                      <Td fontWeight="semibold">{row.ahri_reference_number}</Td>
                      <Td fontSize="xs">{fmtValue(row.source_description)}</Td>
                      <Td>{fmtValue(row.heat_pump_type)}</Td>
                      <Td>{fmtValue(row.make)}</Td>
                      <Td>{fmtValue(row.outdoor_model)}</Td>
                      <Td>{fmtValue(row.indoor_model_or_air_handler)}</Td>
                      <Td isNumeric>{fmtValue(row.rated_capacity_btu_at_minus_5c)}</Td>
                      <Td isNumeric>{fmtValue(row.seer2)}</Td>
                      <Td isNumeric>{fmtValue(row.hspf2)}</Td>
                      <Td isNumeric>{fmtValue(row.cop)}</Td>
                      <Td isNumeric>{fmtValue(row.capacity_maintenance_percent)}</Td>
                      <Td>{fmtValue(row.cold_climate_rated)}</Td>
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
                  onClick={() => {
                    const next = Math.max(1, page - 1);
                    setPage(next);
                    pushUrl({ page: next });
                  }}
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
                  onClick={() => {
                    const next = Math.min(totalPages, page + 1);
                    setPage(next);
                    pushUrl({ page: next });
                  }}
                />
              </Tooltip>
            </Flex>
          </Flex>
        </Box>
      </Container>

      <Modal isOpen={isImportDialogOpen} onClose={onImportDialogClose} size="lg">
        <ModalOverlay />
        <ModalContent>
          <ModalHeader>Import AHRI Source PDF</ModalHeader>
          <ModalCloseButton />
          <ModalBody>
            <Text fontSize="sm" fontWeight="semibold">
              {editingSource?.description || 'Source list'}
            </Text>
            <Text fontSize="xs" opacity={0.75} mb={4} wordBreak="break-all">
              {editingSource?.source_url}
            </Text>

            <Box mb={4}>
              <Text fontSize="xs" opacity={0.7} mb={1}>
                publishing_notes
              </Text>
              <Input
                value={publishingNotes}
                onChange={(e) => setPublishingNotes(e.target.value)}
                placeholder="Example: downloaded from BC Hydro current qualified product list"
                isDisabled={importingPdf}
              />
            </Box>

            <Box>
              <Text fontSize="xs" opacity={0.7} mb={1}>
                publishing_date
              </Text>
              <Input
                type="date"
                value={publishingDate}
                onChange={(e) => setPublishingDate(e.target.value)}
                isDisabled={importingPdf}
              />
            </Box>

            <Text fontSize="xs" opacity={0.7} mt={3}>
              These fields are stored on the new `ahri_import_runs` row created by this download.
            </Text>
          </ModalBody>
          <ModalFooter>
            <Button variant="ghost" mr={3} onClick={onImportDialogClose} isDisabled={importingPdf}>
              Cancel
            </Button>
            <Button colorScheme="blue" onClick={importDownloadedPdf} isLoading={importingPdf || Boolean(importingSourceId)}>
              Download and import
            </Button>
          </ModalFooter>
        </ModalContent>
      </Modal>

      <Drawer isOpen={isSourceInfoOpen} placement="right" onClose={onSourceInfoClose} size="md">
        <DrawerOverlay />
        <DrawerContent>
          <DrawerCloseButton />
          <DrawerHeader>Heat Pump Source Details</DrawerHeader>
          <DrawerBody>
            {[
              ['ahri_source_id', infoSource?.id],
              ['description', infoSource?.description],
              ['source_url', infoSource?.source_url],
              ['publishing_notes', infoSource?.latest_success?.publishing_notes],
              ['publishing_date', infoSource?.latest_success?.publishing_date],
              ['latest_status', infoSource?.latest?.status],
              ['latest_started_at', infoSource?.latest?.started_at],
              ['latest_completed_at', infoSource?.latest?.completed_at],
              ['latest_success_id', infoSource?.latest_success?.id],
              ['records_imported', infoSource?.latest_success?.records_imported],
              ['storage_provider', infoSource?.latest_success?.storage_provider],
              ['storage_key', infoSource?.latest_success?.storage_key],
              ['content_type', infoSource?.latest_success?.content_type],
              ['byte_size', infoSource?.latest_success?.byte_size],
              ['file_sha256', infoSource?.latest_success?.file_sha256],
              ['error_text', infoSource?.latest?.error_text],
            ].map(([label, value]) => (
              <Box key={String(label)} mb={3}>
                <Text fontSize="xs" fontWeight="bold" opacity={0.65}>
                  {String(label)}
                </Text>
                <Text fontSize="sm" whiteSpace="pre-wrap" wordBreak="break-word">
                  {fmtValue(value as any)}
                </Text>
              </Box>
            ))}
          </DrawerBody>
        </DrawerContent>
      </Drawer>
    </Flex>
  );
}
