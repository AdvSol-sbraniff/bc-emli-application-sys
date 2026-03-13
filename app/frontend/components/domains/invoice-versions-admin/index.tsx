import { Accordion, AccordionButton, AccordionIcon, AccordionItem, AccordionPanel, Badge, Box, Button, Container, Drawer, DrawerBody, DrawerCloseButton, DrawerContent, DrawerHeader, DrawerOverlay, Flex, IconButton, Input, Text, Tooltip } from '@chakra-ui/react';
import { Table, Thead, Tbody, Tr, Th, Td, Spinner } from '@chakra-ui/react';
import { Tabs, TabList, TabPanels, Tab, TabPanel } from '@chakra-ui/react';
import { ArrowsClockwise, FilePdf, Info, Question } from '@phosphor-icons/react';
import { ThinBlueTitleBar } from '../../shared/base/thin-blue-title-bar';
import React, { useEffect, useRef, useState } from 'react';
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
  session_created_at?: string | null;
  contractor_business_name?: string | null;
};

type DiffSnapshot = {
  invoiceVersionId: string;
  read: any;
  lineitems: any[];
  locatedFields: any[];
  rulechecks: any[];
};

type ContractorDiff = {
  changedFields: Array<{ label: string; before: string; after: string }>;
  addedLineitems: any[];
  removedLineitems: any[];
  changedLineitems: Array<{ key: string; before: any; after: any }>;
};

type AiDiff = {
  overallChanges: Array<{ label: string; before: string; after: string }>;
  addedFields: any[];
  removedFields: any[];
  changedFields: Array<{ key: string; before: any; after: any }>;
  addedRules: any[];
  removedRules: any[];
  changedRules: Array<{ key: string; before: any; after: any }>;
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

function norm(v: any): string {
  if (v === null || v === undefined) return '';
  return String(v).trim();
}

function displayVal(v: any): string {
  if (v === null || v === undefined || v === '') return '—';
  if (typeof v === 'object') return prettyJson(v);
  return String(v);
}

function sortedByKey(items: any[], keyOf: (item: any) => string): any[] {
  return [...items].sort((a, b) => keyOf(a).localeCompare(keyOf(b)));
}

const lineitemFields = [
  { key: 'description', label: 'Description' },
  { key: 'quantity', label: 'Quantity' },
  { key: 'unit_price', label: 'Unit price' },
  { key: 'amount', label: 'Amount' },
];

const locatedFieldDisplayFields = [
  { key: 'line_number', label: 'Line' },
  { key: 'value', label: 'Value' },
  { key: 'confidence', label: 'Confidence' },
];

const ruleDisplayFields = [
  { key: 'rule_name', label: 'Rule name' },
  { key: 'pass', label: 'Pass' },
  { key: 'confidence', label: 'Confidence' },
  { key: 'expected', label: 'Expected' },
  { key: 'observed', label: 'Observed' },
  { key: 'reason', label: 'Reason' },
];

function lineitemFieldVal(v: any): string {
  if (v === null || v === undefined || v === '') return '—';
  return String(v);
}

function diffFieldVal(v: any): string {
  if (v === null || v === undefined || v === '') return '—';
  if (typeof v === 'boolean') return v ? 'true' : 'false';
  return String(v);
}

function lineitemKey(li: any): string {
  return String(li?.lineitem_seqno ?? li?.seqno ?? li?.id ?? '');
}

function toLineitemComparable(li: any) {
  return {
    description: li?.ocr_description ?? null,
    quantity: li?.ocr_quantity ?? null,
    unit_price: li?.ocr_unit_price ?? null,
    amount: li?.ocr_amount ?? null,
  };
}

function deepEqualSimple(a: any, b: any): boolean {
  return JSON.stringify(a) === JSON.stringify(b);
}

function diffContractor(a: DiffSnapshot, b: DiffSnapshot): ContractorDiff {
  const fieldDefs = [
    { key: 'original_filename', label: 'File name' },
    { key: 'di_ocr_invoice_id', label: 'OCR invoice #' },
    { key: 'di_ocr_invoice_date', label: 'OCR invoice date' },
    { key: 'di_ocr_vendor_name', label: 'OCR vendor' },
    { key: 'di_ocr_vendor_address', label: 'OCR vendor address' },
    { key: 'di_ocr_customer_name', label: 'OCR customer name' },
    { key: 'di_ocr_billing_address', label: 'OCR billing address' },
    { key: 'di_ocr_sub_total', label: 'OCR sub-total' },
    { key: 'di_ocr_total_tax', label: 'OCR total tax' },
    { key: 'di_ocr_invoice_total', label: 'OCR invoice total' },
    { key: 'di_ocr_amount_due', label: 'OCR amount due' },
  ];

  const changedFields = fieldDefs
    .filter((f) => norm(a.read?.[f.key]) !== norm(b.read?.[f.key]))
    .map((f) => ({
      label: f.label,
      before: norm(a.read?.[f.key]) || '—',
      after: norm(b.read?.[f.key]) || '—',
    }));

  const mapA = new Map(a.lineitems.map((li) => [lineitemKey(li), toLineitemComparable(li)]));
  const mapB = new Map(b.lineitems.map((li) => [lineitemKey(li), toLineitemComparable(li)]));

  const addedLineitems: any[] = [];
  const removedLineitems: any[] = [];
  const changedLineitems: Array<{ key: string; before: any; after: any }> = [];

  mapB.forEach((valB, key) => {
    if (!mapA.has(key)) addedLineitems.push({ key, ...valB });
  });

  mapA.forEach((valA, key) => {
    if (!mapB.has(key)) removedLineitems.push({ key, ...valA });
  });

  mapA.forEach((valA, key) => {
    if (!mapB.has(key)) return;
    const valB = mapB.get(key);
    if (!deepEqualSimple(valA, valB)) changedLineitems.push({ key, before: valA, after: valB });
  });

  return { changedFields, addedLineitems, removedLineitems, changedLineitems };
}

function diffAi(a: DiffSnapshot, b: DiffSnapshot): AiDiff {
  const overallDefs = [
    { key: 'genai_overall_confidence', label: 'Overall confidence' },
    { key: 'genai_all_rulechecks_pass_flag', label: 'All checks pass' },
    { key: 'genai_admin_advice', label: 'Admin advice' },
  ];

  const overallChanges = overallDefs
    .filter((f) => norm(a.read?.[f.key]) !== norm(b.read?.[f.key]))
    .map((f) => ({
      label: f.label,
      before: norm(a.read?.[f.key]) || '—',
      after: norm(b.read?.[f.key]) || '—',
    }));

  const fieldKey = (r: any) => `${String(r?.field_key ?? '')}|${String(r?.line_number ?? '')}`;
  const baseFieldKey = (k: string) => String(k || '').split('|')[0] || k;
  const locatedMeaningfulChanged = (x: any, y: any): boolean => {
    const xValue = norm(x?.value);
    const yValue = norm(y?.value);
    return xValue !== yValue;
  };
  const mapFieldA = new Map(a.locatedFields.map((r) => [fieldKey(r), {
    field_key: r?.field_key ?? '',
    line_number: r?.line_number ?? null,
    value: r?.value_text ?? null,
    confidence: r?.confidence ?? null,
  }]));
  const mapFieldB = new Map(b.locatedFields.map((r) => [fieldKey(r), {
    field_key: r?.field_key ?? '',
    line_number: r?.line_number ?? null,
    value: r?.value_text ?? null,
    confidence: r?.confidence ?? null,
  }]));

  const addedFields: any[] = [];
  const removedFields: any[] = [];
  const changedFields: Array<{ key: string; before: any; after: any }> = [];

  mapFieldB.forEach((v, k) => {
    if (!mapFieldA.has(k)) addedFields.push({ key: k, ...v });
  });
  mapFieldA.forEach((v, k) => {
    if (!mapFieldB.has(k)) removedFields.push({ key: k, ...v });
  });
  mapFieldA.forEach((vA, k) => {
    if (!mapFieldB.has(k)) return;
    const vB = mapFieldB.get(k);
    if (locatedMeaningfulChanged(vA, vB)) changedFields.push({ key: k, before: vA, after: vB });
  });

  // If same field_key appears on a different line, show it as changed instead of added+removed.
  const unmatchedAdded = [...addedFields];
  const unmatchedRemoved: any[] = [];

  removedFields.forEach((rm) => {
    const rmBase = rm.field_key || baseFieldKey(String(rm.key));
    const addIdx = unmatchedAdded.findIndex((ad) => {
      const adBase = ad.field_key || baseFieldKey(String(ad.key));
      return adBase === rmBase;
    });

    if (addIdx >= 0) {
      const ad = unmatchedAdded[addIdx];
      if (locatedMeaningfulChanged(rm, ad)) {
        changedFields.push({
          key: rmBase,
          before: rm,
          after: ad,
        });
      }
      unmatchedAdded.splice(addIdx, 1);
    } else {
      unmatchedRemoved.push(rm);
    }
  });

  addedFields.length = 0;
  removedFields.length = 0;
  unmatchedAdded.forEach((x) => addedFields.push(x));
  unmatchedRemoved.forEach((x) => removedFields.push(x));

  const ruleKey = (r: any) => String(r?.rule_number ?? r?.id ?? '');
  const mapRuleA = new Map(a.rulechecks.map((r) => [ruleKey(r), {
    rule_name: r?.rule_name ?? null,
    pass: r?.rule_pass_flag ?? null,
    confidence: r?.confidence ?? null,
    expected: r?.expected_text ?? null,
    observed: r?.observed_text ?? null,
    reason: r?.reason_and_likely_causes ?? null,
  }]));
  const mapRuleB = new Map(b.rulechecks.map((r) => [ruleKey(r), {
    rule_name: r?.rule_name ?? null,
    pass: r?.rule_pass_flag ?? null,
    confidence: r?.confidence ?? null,
    expected: r?.expected_text ?? null,
    observed: r?.observed_text ?? null,
    reason: r?.reason_and_likely_causes ?? null,
  }]));

  const addedRules: any[] = [];
  const removedRules: any[] = [];
  const changedRules: Array<{ key: string; before: any; after: any }> = [];

  mapRuleB.forEach((v, k) => {
    if (!mapRuleA.has(k)) addedRules.push({ key: k, ...v });
  });
  mapRuleA.forEach((v, k) => {
    if (!mapRuleB.has(k)) removedRules.push({ key: k, ...v });
  });
  mapRuleA.forEach((vA, k) => {
    if (!mapRuleB.has(k)) return;
    const vB = mapRuleB.get(k);
    if (!deepEqualSimple(vA, vB)) changedRules.push({ key: k, before: vA, after: vB });
  });

  return { overallChanges, addedFields, removedFields, changedFields, addedRules, removedRules, changedRules };
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
  const [isHelpOpen, setIsHelpOpen] = useState<boolean>(false);

  const [diJson, setDiJson] = useState<any | null>(null);
  const [genaiJson, setGenaiJson] = useState<any | null>(null);

  const [diffAId, setDiffAId] = useState<string>('');
  const [diffBId, setDiffBId] = useState<string>('');
  const [diffLoading, setDiffLoading] = useState<boolean>(false);
  const [diffError, setDiffError] = useState<string>('');
  const [contractorDiff, setContractorDiff] = useState<ContractorDiff | null>(null);
  const [aiDiff, setAiDiff] = useState<AiDiff | null>(null);
  const [lastDiffPair, setLastDiffPair] = useState<{ a: string; b: string } | null>(null);

  const contractorHeaderRef = useRef<HTMLDivElement | null>(null);
  const contractorLineitemsRef = useRef<HTMLDivElement | null>(null);
  const aiOverallRef = useRef<HTMLDivElement | null>(null);
  const aiLocatedRef = useRef<HTMLDivElement | null>(null);
  const aiRulesRef = useRef<HTMLDivElement | null>(null);

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
    setDiffAId('');
    setDiffBId('');
    setDiffError('');
    setContractorDiff(null);
    setAiDiff(null);
    setLastDiffPair(null);

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

  const fetchDiffSnapshot = async (invoiceVersionId: string): Promise<DiffSnapshot> => {
    const [readRes, genaiRes] = await Promise.all([
      fetch(`/api/claims/admin/invoice_versions/${encodeURIComponent(invoiceVersionId)}/read`, {
        method: 'GET',
        headers: { Accept: 'application/json' },
        credentials: 'include',
      }),
      fetch(`/api/claims/admin/invoice_versions/${encodeURIComponent(invoiceVersionId)}/read_genai`, {
        method: 'GET',
        headers: { Accept: 'application/json' },
        credentials: 'include',
      }),
    ]);

    const readJson = await readRes.json().catch(() => ({}));
    if (!readRes.ok) throw new Error(readJson?.error || readJson?.message || `Read failed (${readRes.status}).`);

    const genaiJson = await genaiRes.json().catch(() => ({}));
    if (!genaiRes.ok) throw new Error(genaiJson?.error || genaiJson?.message || `GenAI read failed (${genaiRes.status}).`);

    return {
      invoiceVersionId,
      read: readJson?.read || null,
      lineitems: Array.isArray(readJson?.lineitems) ? readJson.lineitems : [],
      locatedFields: Array.isArray(genaiJson?.located_fields) ? genaiJson.located_fields : [],
      rulechecks: Array.isArray(genaiJson?.rulechecks) ? genaiJson.rulechecks : [],
    };
  };

  const runDiffRefresh = async () => {
    setDiffError('');

    if (!diffAId || !diffBId) {
      setDiffError('Pick two versions: one A and one B.');
      return;
    }

    if (diffAId === diffBId) {
      setDiffError('A and B must be different versions.');
      return;
    }

    setDiffLoading(true);
    try {
      const [snapA, snapB] = await Promise.all([fetchDiffSnapshot(diffAId), fetchDiffSnapshot(diffBId)]);
      setContractorDiff(diffContractor(snapA, snapB));
      setAiDiff(diffAi(snapA, snapB));
      setLastDiffPair({ a: diffAId, b: diffBId });
    } catch (e: any) {
      setContractorDiff(null);
      setAiDiff(null);
      setLastDiffPair(null);
      setDiffError(e?.message || 'Failed to refresh diff.');
    } finally {
      setDiffLoading(false);
    }
  };

  const selectAsA = (id: string) => {
    setDiffAId(id);
    if (id === diffBId) setDiffBId('');
  };

  const selectAsB = (id: string) => {
    setDiffBId(id);
    if (id === diffAId) setDiffAId('');
  };

  const jumpTo = (target: React.RefObject<HTMLDivElement | null>) => {
    target.current?.scrollIntoView({ behavior: 'smooth', block: 'start' });
  };

  const detailEntries = selectedDetail
    ? Object.entries(selectedDetail)
        .filter(([k]) => {
          if (k === 'di_raw_json' || k === 'genai_raw_json') return false;
          if (k === 'genai_admin_advice' || k === 'di_page_map') return false;
          if (k.toLowerCase().includes('polygon')) return false;
          return true;
        })
        .sort(([a], [b]) => a.localeCompare(b))
    : [];

  return (
    <Flex as="main" direction="column" w="full" bg="greys.white" pb="24" minH="100vh">
      <ThinBlueTitleBar title="Versions History Inspection" />

      <Container maxW="container.xl" pb={4} flex="1" pt={6}>
        <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="lg" p={5} bg="white">
          {/* invoice context */}
          <Flex direction="column" gap={3} mb={4}>
            <Flex gap={3} align="end" wrap="wrap">
              <Box minW="220px">
                <Text fontSize="xs" opacity={0.7} mb={1}>
                  session_created_at
                </Text>
                <Input value={fmtDate(invoiceMeta?.session_created_at)} isReadOnly bg="white" />
              </Box>

              <Box flex="1" minW="280px">
                <Text fontSize="xs" opacity={0.7} mb={1}>
                  contractor
                </Text>
                <Input value={invoiceMeta?.contractor_business_name || '—'} isReadOnly bg="white" />
              </Box>

              <Box ml="auto">
                <Tooltip label="Help for this screen">
                  <IconButton
                    aria-label="Open versions history help"
                    icon={<Question size={18} />}
                    size="sm"
                    variant="outline"
                    onClick={() => setIsHelpOpen(true)}
                  />
                </Tooltip>
              </Box>
            </Flex>

            <Flex gap={3} align="end" wrap="wrap">
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

            <Flex mb={2} gap={4} align="center" wrap="wrap">
              <Text fontSize="xs">A: <Box as="span" fontFamily="mono">{diffAId || '—'}</Box></Text>
              <Text fontSize="xs">B: <Box as="span" fontFamily="mono">{diffBId || '—'}</Box></Text>
            </Flex>

            <Table size="sm">
              <Thead>
                <Tr>
                  <Th>diff select</Th>
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
                    <Td>
                      <Flex gap={1}>
                        <Button
                          size="xs"
                          variant={diffAId === r.id ? 'solid' : 'outline'}
                          colorScheme={diffAId === r.id ? 'blue' : 'gray'}
                          onClick={(e) => {
                            e.stopPropagation();
                            selectAsA(r.id);
                          }}
                        >
                          A
                        </Button>
                        <Button
                          size="xs"
                          variant={diffBId === r.id ? 'solid' : 'outline'}
                          colorScheme={diffBId === r.id ? 'green' : 'gray'}
                          onClick={(e) => {
                            e.stopPropagation();
                            selectAsB(r.id);
                          }}
                        >
                          B
                        </Button>
                      </Flex>
                    </Td>
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
                      <Tooltip label="Open version-specific PDF viewer">
                        <IconButton
                          aria-label="Open version PDF viewer"
                          icon={<FilePdf size={16} />}
                          size="xs"
                          variant="outline"
                          mr={2}
                          onClick={(e) => {
                            e.stopPropagation();
                            const url = `/invoice-versions-by-version/${encodeURIComponent(r.id)}/read`;
                            window.open(url, '_blank', 'noopener,noreferrer');
                          }}
                        />
                      </Tooltip>

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
                    <Td colSpan={7}>
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
              <Flex align="center" gap={2}>
                <Tooltip label="Refresh A vs B diff tabs">
                  <IconButton
                    aria-label="Refresh diff"
                    icon={<ArrowsClockwise size={16} />}
                    size="xs"
                    variant="outline"
                    onClick={runDiffRefresh}
                    isDisabled={!diffAId || !diffBId || diffLoading}
                    isLoading={diffLoading}
                  />
                </Tooltip>
                {loadingDetail && <Spinner size="sm" />}
              </Flex>
            </Flex>

            {diffError && (
              <Box mb={3} p={2} bg="red.50" borderWidth="1px" borderColor="red.200" borderRadius="md">
                <Text fontSize="xs" color="red.700">{diffError}</Text>
              </Box>
            )}

            {lastDiffPair && (
              <Box mb={3} p={2} bg="blue.50" borderWidth="1px" borderColor="blue.200" borderRadius="md">
                <Text fontSize="xs">
                  Diff loaded for A: <Box as="span" fontFamily="mono">{lastDiffPair.a}</Box> and B: <Box as="span" fontFamily="mono">{lastDiffPair.b}</Box>
                </Text>
              </Box>
            )}

 
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
                <Tab>GenAI Advice</Tab>
                <Tab>Diff Contractor Changes</Tab>
                <Tab>Diff AI Changes</Tab>
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

                <TabPanel p={3}>
                  <Box
                    fontSize="sm"
                    whiteSpace="pre-wrap"
                    overflow="auto"
                    maxH="520px"
                    borderWidth="1px"
                    borderColor="greys.grey20"
                    borderRadius="md"
                    p={3}
                    bg="gray.50"
                  >
                    {selectedVersionId
                      ? selectedDetail?.genai_admin_advice || 'No admin advice found for this version.'
                      : 'Select a row to load admin advice.'}
                  </Box>
                </TabPanel>

                <TabPanel p={3}>
                  {!contractorDiff ? (
                    <Text fontSize="sm" opacity={0.75}>Pick A and B, then click diff refresh.</Text>
                  ) : (
                    <Flex direction="column" gap={3}>
                      <Box
                        position="sticky"
                        top="0"
                        zIndex={2}
                        bg="white"
                        borderWidth="1px"
                        borderColor="greys.grey20"
                        borderRadius="md"
                        p={2}
                      >
                        <Flex align="center" gap={2} wrap="wrap">
                          <Text fontSize="xs" fontWeight="bold">Contractor diff summary</Text>
                          <Badge colorScheme="blue">
                            Total {contractorDiff.changedFields.length + contractorDiff.changedLineitems.length + contractorDiff.addedLineitems.length + contractorDiff.removedLineitems.length}
                          </Badge>
                          <Badge
                            colorScheme={contractorDiff.changedFields.length > 0 ? 'orange' : 'gray'}
                            cursor="pointer"
                            onClick={() => jumpTo(contractorHeaderRef)}
                          >
                            Header {contractorDiff.changedFields.length}
                          </Badge>
                          <Badge
                            colorScheme={contractorDiff.changedLineitems.length > 0 ? 'orange' : 'gray'}
                            cursor="pointer"
                            onClick={() => jumpTo(contractorLineitemsRef)}
                          >
                            Changed lines {contractorDiff.changedLineitems.length}
                          </Badge>
                          <Badge
                            colorScheme={contractorDiff.addedLineitems.length > 0 ? 'green' : 'gray'}
                            cursor="pointer"
                            onClick={() => jumpTo(contractorLineitemsRef)}
                          >
                            Added lines {contractorDiff.addedLineitems.length}
                          </Badge>
                          <Badge
                            colorScheme={contractorDiff.removedLineitems.length > 0 ? 'red' : 'gray'}
                            cursor="pointer"
                            onClick={() => jumpTo(contractorLineitemsRef)}
                          >
                            Removed lines {contractorDiff.removedLineitems.length}
                          </Badge>
                        </Flex>
                      </Box>

                      <Box ref={contractorHeaderRef} borderWidth="1px" borderColor="greys.grey20" borderRadius="md" p={3} bg="gray.50">
                        <Flex align="center" gap={2} mb={2} wrap="wrap">
                          <Text fontSize="sm" fontWeight="bold">Header field changes</Text>
                          <Badge colorScheme={contractorDiff.changedFields.length > 0 ? 'orange' : 'gray'}>
                            Changed {contractorDiff.changedFields.length}
                          </Badge>
                        </Flex>
                        {contractorDiff.changedFields.length === 0 ? (
                          <Text fontSize="xs" opacity={0.8}>No header field changes.</Text>
                        ) : (
                          <Flex direction="column" gap={2} maxH="320px" overflow="auto">
                            {contractorDiff.changedFields.map((f) => (
                              <Box key={f.label} borderWidth="1px" borderColor="gray.200" borderRadius="md" p={2} bg="white">
                                <Text fontSize="xs" fontWeight="bold" mb={1}>{f.label}</Text>
                                <Flex gap={3}>
                                  <Box flex="1">
                                    <Text fontSize="10px" opacity={0.7}>A (before)</Text>
                                    <Text fontSize="xs" fontFamily="mono" whiteSpace="pre-wrap">{f.before || '—'}</Text>
                                  </Box>
                                  <Box flex="1">
                                    <Text fontSize="10px" opacity={0.7}>B (after)</Text>
                                    <Text fontSize="xs" fontFamily="mono" whiteSpace="pre-wrap">{f.after || '—'}</Text>
                                  </Box>
                                </Flex>
                              </Box>
                            ))}
                          </Flex>
                        )}
                      </Box>

                      <Box ref={contractorLineitemsRef} borderWidth="1px" borderColor="greys.grey20" borderRadius="md" p={3} bg="gray.50">
                        <Flex align="center" gap={2} mb={2} wrap="wrap">
                          <Text fontSize="sm" fontWeight="bold">Line item changes</Text>
                          <Badge colorScheme={contractorDiff.changedLineitems.length > 0 ? 'orange' : 'gray'}>Changed {contractorDiff.changedLineitems.length}</Badge>
                          <Badge colorScheme={contractorDiff.addedLineitems.length > 0 ? 'green' : 'gray'}>Added {contractorDiff.addedLineitems.length}</Badge>
                          <Badge colorScheme={contractorDiff.removedLineitems.length > 0 ? 'red' : 'gray'}>Removed {contractorDiff.removedLineitems.length}</Badge>
                        </Flex>
                        <Flex direction="column" gap={2} maxH="380px" overflow="auto">
                          {sortedByKey(contractorDiff.changedLineitems, (li) => li.key).map((li) => (
                            <Box key={`chg-${li.key}`} borderWidth="1px" borderColor="orange.200" borderRadius="md" p={2} bg="orange.50">
                              <Text fontSize="xs" fontWeight="bold" mb={1}>Changed line {li.key}</Text>
                              <Flex gap={3}>
                                <Box flex="1">
                                  <Text fontSize="10px" opacity={0.7}>A (before)</Text>
                                  <Flex direction="column" gap={1}>
                                    {lineitemFields.map((f) => (
                                      <Flex key={`before-${li.key}-${f.key}`} justify="space-between" gap={2}>
                                        <Text fontSize="10px" opacity={0.7}>{f.label}</Text>
                                        <Text fontSize="xs" fontFamily="mono">{lineitemFieldVal(li.before?.[f.key])}</Text>
                                      </Flex>
                                    ))}
                                  </Flex>
                                </Box>
                                <Box flex="1">
                                  <Text fontSize="10px" opacity={0.7}>B (after)</Text>
                                  <Flex direction="column" gap={1}>
                                    {lineitemFields.map((f) => (
                                      <Flex key={`after-${li.key}-${f.key}`} justify="space-between" gap={2}>
                                        <Text fontSize="10px" opacity={0.7}>{f.label}</Text>
                                        <Text fontSize="xs" fontFamily="mono">{lineitemFieldVal(li.after?.[f.key])}</Text>
                                      </Flex>
                                    ))}
                                  </Flex>
                                </Box>
                              </Flex>
                            </Box>
                          ))}

                          <Accordion
                            allowMultiple
                            defaultIndex={
                              contractorDiff.addedLineitems.length > 0
                                ? [0]
                                : contractorDiff.removedLineitems.length > 0
                                  ? [1]
                                  : []
                            }
                          >
                            <AccordionItem border="1px solid" borderColor="green.200" borderRadius="md" bg="green.50">
                              <AccordionButton>
                                <Flex flex="1" align="center" justify="space-between" pr={2}>
                                  <Text fontSize="xs" fontWeight="bold">Added lines</Text>
                                  <Badge colorScheme={contractorDiff.addedLineitems.length > 0 ? 'green' : 'gray'}>{contractorDiff.addedLineitems.length}</Badge>
                                </Flex>
                                <AccordionIcon />
                              </AccordionButton>
                              <AccordionPanel pt={0}>
                                <Flex direction="column" gap={2}>
                                  {sortedByKey(contractorDiff.addedLineitems, (li) => String(li.key)).map((li) => (
                                    <Box key={`add-${li.key}`} borderWidth="1px" borderColor="green.200" borderRadius="md" p={2} bg="white">
                                      <Text fontSize="xs" fontWeight="bold" mb={1}>Added line {li.key}</Text>
                                      <Flex direction="column" gap={1}>
                                        {lineitemFields.map((f) => (
                                          <Flex key={`add-${li.key}-${f.key}`} justify="space-between" gap={2}>
                                            <Text fontSize="10px" opacity={0.7}>{f.label}</Text>
                                            <Text fontSize="xs" fontFamily="mono">{lineitemFieldVal(li[f.key])}</Text>
                                          </Flex>
                                        ))}
                                      </Flex>
                                    </Box>
                                  ))}
                                  {contractorDiff.addedLineitems.length === 0 && <Text fontSize="xs" opacity={0.8}>No added lines.</Text>}
                                </Flex>
                              </AccordionPanel>
                            </AccordionItem>

                            <AccordionItem border="1px solid" borderColor="red.200" borderRadius="md" bg="red.50" mt={2}>
                              <AccordionButton>
                                <Flex flex="1" align="center" justify="space-between" pr={2}>
                                  <Text fontSize="xs" fontWeight="bold">Removed lines</Text>
                                  <Badge colorScheme={contractorDiff.removedLineitems.length > 0 ? 'red' : 'gray'}>{contractorDiff.removedLineitems.length}</Badge>
                                </Flex>
                                <AccordionIcon />
                              </AccordionButton>
                              <AccordionPanel pt={0}>
                                <Flex direction="column" gap={2}>
                                  {sortedByKey(contractorDiff.removedLineitems, (li) => String(li.key)).map((li) => (
                                    <Box key={`remove-${li.key}`} borderWidth="1px" borderColor="red.200" borderRadius="md" p={2} bg="white">
                                      <Text fontSize="xs" fontWeight="bold" mb={1}>Removed line {li.key}</Text>
                                      <Flex direction="column" gap={1}>
                                        {lineitemFields.map((f) => (
                                          <Flex key={`remove-${li.key}-${f.key}`} justify="space-between" gap={2}>
                                            <Text fontSize="10px" opacity={0.7}>{f.label}</Text>
                                            <Text fontSize="xs" fontFamily="mono">{lineitemFieldVal(li[f.key])}</Text>
                                          </Flex>
                                        ))}
                                      </Flex>
                                    </Box>
                                  ))}
                                  {contractorDiff.removedLineitems.length === 0 && <Text fontSize="xs" opacity={0.8}>No removed lines.</Text>}
                                </Flex>
                              </AccordionPanel>
                            </AccordionItem>
                          </Accordion>

                          {contractorDiff.addedLineitems.length === 0 &&
                            contractorDiff.removedLineitems.length === 0 &&
                            contractorDiff.changedLineitems.length === 0 && (
                              <Text fontSize="xs" opacity={0.8}>No line item changes.</Text>
                            )}
                        </Flex>
                      </Box>
                    </Flex>
                  )}
                </TabPanel>

                <TabPanel p={3}>
                  {!aiDiff ? (
                    <Text fontSize="sm" opacity={0.75}>Pick A and B, then click diff refresh.</Text>
                  ) : (
                    <Flex direction="column" gap={3}>
                      <Box
                        position="sticky"
                        top="0"
                        zIndex={2}
                        bg="white"
                        borderWidth="1px"
                        borderColor="greys.grey20"
                        borderRadius="md"
                        p={2}
                      >
                        <Flex align="center" gap={2} wrap="wrap">
                          <Text fontSize="xs" fontWeight="bold">AI diff summary</Text>
                          <Badge colorScheme="blue">
                            Total {aiDiff.overallChanges.length + aiDiff.changedFields.length + aiDiff.addedFields.length + aiDiff.removedFields.length + aiDiff.changedRules.length + aiDiff.addedRules.length + aiDiff.removedRules.length}
                          </Badge>
                          <Badge
                            colorScheme={aiDiff.overallChanges.length > 0 ? 'orange' : 'gray'}
                            cursor="pointer"
                            onClick={() => jumpTo(aiOverallRef)}
                          >
                            Overall {aiDiff.overallChanges.length}
                          </Badge>
                          <Badge
                            colorScheme={aiDiff.changedFields.length > 0 ? 'orange' : 'gray'}
                            cursor="pointer"
                            onClick={() => jumpTo(aiLocatedRef)}
                          >
                            Changed fields {aiDiff.changedFields.length}
                          </Badge>
                          <Badge
                            colorScheme={aiDiff.addedFields.length > 0 ? 'green' : 'gray'}
                            cursor="pointer"
                            onClick={() => jumpTo(aiLocatedRef)}
                          >
                            Added fields {aiDiff.addedFields.length}
                          </Badge>
                          <Badge
                            colorScheme={aiDiff.removedFields.length > 0 ? 'red' : 'gray'}
                            cursor="pointer"
                            onClick={() => jumpTo(aiLocatedRef)}
                          >
                            Removed fields {aiDiff.removedFields.length}
                          </Badge>
                          <Badge
                            colorScheme={aiDiff.changedRules.length > 0 ? 'orange' : 'gray'}
                            cursor="pointer"
                            onClick={() => jumpTo(aiRulesRef)}
                          >
                            Changed rules {aiDiff.changedRules.length}
                          </Badge>
                          <Badge
                            colorScheme={aiDiff.addedRules.length > 0 ? 'green' : 'gray'}
                            cursor="pointer"
                            onClick={() => jumpTo(aiRulesRef)}
                          >
                            Added rules {aiDiff.addedRules.length}
                          </Badge>
                          <Badge
                            colorScheme={aiDiff.removedRules.length > 0 ? 'red' : 'gray'}
                            cursor="pointer"
                            onClick={() => jumpTo(aiRulesRef)}
                          >
                            Removed rules {aiDiff.removedRules.length}
                          </Badge>
                        </Flex>
                      </Box>

                      <Box ref={aiOverallRef} borderWidth="1px" borderColor="greys.grey20" borderRadius="md" p={3} bg="gray.50">
                        <Flex align="center" gap={2} mb={2} wrap="wrap">
                          <Text fontSize="sm" fontWeight="bold">Overall AI field changes ({aiDiff.overallChanges.length})</Text>
                        </Flex>
                        {aiDiff.overallChanges.length === 0 ? (
                          <Text fontSize="xs" opacity={0.8}>No overall AI field changes.</Text>
                        ) : (
                          <Flex direction="column" gap={2} maxH="260px" overflow="auto">
                            {aiDiff.overallChanges.map((f) => (
                              <Box key={f.label} borderWidth="1px" borderColor="gray.200" borderRadius="md" p={2} bg="white">
                                <Text fontSize="xs" fontWeight="bold" mb={1}>{f.label}</Text>
                                <Flex gap={3}>
                                  <Box flex="1">
                                    <Text fontSize="10px" opacity={0.7}>A (before)</Text>
                                    <Text fontSize="xs" fontFamily="mono" whiteSpace="pre-wrap">{f.before || '—'}</Text>
                                  </Box>
                                  <Box flex="1">
                                    <Text fontSize="10px" opacity={0.7}>B (after)</Text>
                                    <Text fontSize="xs" fontFamily="mono" whiteSpace="pre-wrap">{f.after || '—'}</Text>
                                  </Box>
                                </Flex>
                              </Box>
                            ))}
                          </Flex>
                        )}
                      </Box>

                      <Box ref={aiLocatedRef} borderWidth="1px" borderColor="greys.grey20" borderRadius="md" p={3} bg="gray.50">
                        <Flex align="center" gap={2} mb={2} wrap="wrap">
                          <Text fontSize="sm" fontWeight="bold">Located field changes</Text>
                          <Badge colorScheme={aiDiff.changedFields.length > 0 ? 'orange' : 'gray'}>Changed {aiDiff.changedFields.length}</Badge>
                          <Badge colorScheme={aiDiff.addedFields.length > 0 ? 'green' : 'gray'}>Added {aiDiff.addedFields.length}</Badge>
                          <Badge colorScheme={aiDiff.removedFields.length > 0 ? 'red' : 'gray'}>Removed {aiDiff.removedFields.length}</Badge>
                        </Flex>
                        <Flex direction="column" gap={2} maxH="300px" overflow="auto">
                          {sortedByKey(aiDiff.changedFields, (f) => f.key).map((f, idx) => (
                            <Box key={`chgf-${f.key}-${idx}`} borderWidth="1px" borderColor="orange.200" borderRadius="md" p={2} bg="orange.50">
                              <Text fontSize="xs" fontWeight="bold" mb={1}>Changed field {f.before?.field_key || f.after?.field_key || f.key}</Text>
                              <Flex gap={3}>
                                <Box flex="1">
                                  <Text fontSize="10px" opacity={0.7}>A (before)</Text>
                                  <Flex direction="column" gap={1}>
                                    {locatedFieldDisplayFields.map((df) => (
                                      <Flex key={`loc-before-${f.key}-${df.key}-${idx}`} justify="space-between" gap={2}>
                                        <Text fontSize="10px" opacity={0.7}>{df.label}</Text>
                                        <Text fontSize="xs" fontFamily="mono">{diffFieldVal(f.before?.[df.key])}</Text>
                                      </Flex>
                                    ))}
                                  </Flex>
                                </Box>
                                <Box flex="1">
                                  <Text fontSize="10px" opacity={0.7}>B (after)</Text>
                                  <Flex direction="column" gap={1}>
                                    {locatedFieldDisplayFields.map((df) => (
                                      <Flex key={`loc-after-${f.key}-${df.key}-${idx}`} justify="space-between" gap={2}>
                                        <Text fontSize="10px" opacity={0.7}>{df.label}</Text>
                                        <Text fontSize="xs" fontFamily="mono">{diffFieldVal(f.after?.[df.key])}</Text>
                                      </Flex>
                                    ))}
                                  </Flex>
                                </Box>
                              </Flex>
                            </Box>
                          ))}

                          <Accordion
                            allowMultiple
                            defaultIndex={
                              aiDiff.addedFields.length > 0
                                ? [0]
                                : aiDiff.removedFields.length > 0
                                  ? [1]
                                  : []
                            }
                          >
                            <AccordionItem border="1px solid" borderColor="green.200" borderRadius="md" bg="green.50">
                              <AccordionButton>
                                <Flex flex="1" align="center" justify="space-between" pr={2}>
                                  <Text fontSize="xs" fontWeight="bold">Added fields</Text>
                                  <Badge colorScheme={aiDiff.addedFields.length > 0 ? 'green' : 'gray'}>{aiDiff.addedFields.length}</Badge>
                                </Flex>
                                <AccordionIcon />
                              </AccordionButton>
                              <AccordionPanel pt={0}>
                                <Flex direction="column" gap={2}>
                                  {sortedByKey(aiDiff.addedFields, (f) => String(f.key)).map((f, idx) => (
                                    <Box key={`addf-${f.key}`} borderWidth="1px" borderColor="green.200" borderRadius="md" p={2} bg="white">
                                      <Text fontSize="xs" fontWeight="bold" mb={1}>Added field {f.field_key || f.key}</Text>
                                      <Flex direction="column" gap={1}>
                                        {locatedFieldDisplayFields.map((df) => (
                                          <Flex key={`loc-add-${f.key}-${df.key}-${idx}`} justify="space-between" gap={2}>
                                            <Text fontSize="10px" opacity={0.7}>{df.label}</Text>
                                            <Text fontSize="xs" fontFamily="mono">{diffFieldVal(f[df.key])}</Text>
                                          </Flex>
                                        ))}
                                      </Flex>
                                    </Box>
                                  ))}
                                  {aiDiff.addedFields.length === 0 && <Text fontSize="xs" opacity={0.8}>No added fields.</Text>}
                                </Flex>
                              </AccordionPanel>
                            </AccordionItem>

                            <AccordionItem border="1px solid" borderColor="red.200" borderRadius="md" bg="red.50" mt={2}>
                              <AccordionButton>
                                <Flex flex="1" align="center" justify="space-between" pr={2}>
                                  <Text fontSize="xs" fontWeight="bold">Removed fields</Text>
                                  <Badge colorScheme={aiDiff.removedFields.length > 0 ? 'red' : 'gray'}>{aiDiff.removedFields.length}</Badge>
                                </Flex>
                                <AccordionIcon />
                              </AccordionButton>
                              <AccordionPanel pt={0}>
                                <Flex direction="column" gap={2}>
                                  {sortedByKey(aiDiff.removedFields, (f) => String(f.key)).map((f, idx) => (
                                    <Box key={`rmf-${f.key}`} borderWidth="1px" borderColor="red.200" borderRadius="md" p={2} bg="white">
                                      <Text fontSize="xs" fontWeight="bold" mb={1}>Removed field {f.field_key || f.key}</Text>
                                      <Flex direction="column" gap={1}>
                                        {locatedFieldDisplayFields.map((df) => (
                                          <Flex key={`loc-remove-${f.key}-${df.key}-${idx}`} justify="space-between" gap={2}>
                                            <Text fontSize="10px" opacity={0.7}>{df.label}</Text>
                                            <Text fontSize="xs" fontFamily="mono">{diffFieldVal(f[df.key])}</Text>
                                          </Flex>
                                        ))}
                                      </Flex>
                                    </Box>
                                  ))}
                                  {aiDiff.removedFields.length === 0 && <Text fontSize="xs" opacity={0.8}>No removed fields.</Text>}
                                </Flex>
                              </AccordionPanel>
                            </AccordionItem>
                          </Accordion>

                          {aiDiff.addedFields.length === 0 && aiDiff.removedFields.length === 0 && aiDiff.changedFields.length === 0 && (
                            <Text fontSize="xs" opacity={0.8}>No located field changes.</Text>
                          )}
                        </Flex>
                      </Box>

                      <Box ref={aiRulesRef} borderWidth="1px" borderColor="greys.grey20" borderRadius="md" p={3} bg="gray.50">
                        <Flex align="center" gap={2} mb={2} wrap="wrap">
                          <Text fontSize="sm" fontWeight="bold">Rulecheck changes</Text>
                          <Badge colorScheme={aiDiff.changedRules.length > 0 ? 'orange' : 'gray'}>Changed {aiDiff.changedRules.length}</Badge>
                          <Badge colorScheme={aiDiff.addedRules.length > 0 ? 'green' : 'gray'}>Added {aiDiff.addedRules.length}</Badge>
                          <Badge colorScheme={aiDiff.removedRules.length > 0 ? 'red' : 'gray'}>Removed {aiDiff.removedRules.length}</Badge>
                        </Flex>
                        <Flex direction="column" gap={2} maxH="300px" overflow="auto">
                          {sortedByKey(aiDiff.changedRules, (r) => r.key).map((r) => (
                            <Box key={`chgr-${r.key}`} borderWidth="1px" borderColor="orange.200" borderRadius="md" p={2} bg="orange.50">
                              <Text fontSize="xs" fontWeight="bold" mb={1}>Changed rule {r.key}</Text>
                              <Flex gap={3}>
                                <Box flex="1">
                                  <Text fontSize="10px" opacity={0.7}>A (before)</Text>
                                  <Flex direction="column" gap={1}>
                                    {ruleDisplayFields.map((df) => (
                                      <Flex key={`rule-before-${r.key}-${df.key}`} justify="space-between" gap={2}>
                                        <Text fontSize="10px" opacity={0.7}>{df.label}</Text>
                                        <Text fontSize="xs" fontFamily="mono">{diffFieldVal(r.before?.[df.key])}</Text>
                                      </Flex>
                                    ))}
                                  </Flex>
                                </Box>
                                <Box flex="1">
                                  <Text fontSize="10px" opacity={0.7}>B (after)</Text>
                                  <Flex direction="column" gap={1}>
                                    {ruleDisplayFields.map((df) => (
                                      <Flex key={`rule-after-${r.key}-${df.key}`} justify="space-between" gap={2}>
                                        <Text fontSize="10px" opacity={0.7}>{df.label}</Text>
                                        <Text fontSize="xs" fontFamily="mono">{diffFieldVal(r.after?.[df.key])}</Text>
                                      </Flex>
                                    ))}
                                  </Flex>
                                </Box>
                              </Flex>
                            </Box>
                          ))}

                          <Accordion
                            allowMultiple
                            defaultIndex={
                              aiDiff.addedRules.length > 0
                                ? [0]
                                : aiDiff.removedRules.length > 0
                                  ? [1]
                                  : []
                            }
                          >
                            <AccordionItem border="1px solid" borderColor="green.200" borderRadius="md" bg="green.50">
                              <AccordionButton>
                                <Flex flex="1" align="center" justify="space-between" pr={2}>
                                  <Text fontSize="xs" fontWeight="bold">Added rules</Text>
                                  <Badge colorScheme={aiDiff.addedRules.length > 0 ? 'green' : 'gray'}>{aiDiff.addedRules.length}</Badge>
                                </Flex>
                                <AccordionIcon />
                              </AccordionButton>
                              <AccordionPanel pt={0}>
                                <Flex direction="column" gap={2}>
                                  {sortedByKey(aiDiff.addedRules, (r) => String(r.key)).map((r) => (
                                    <Box key={`addr-${r.key}`} borderWidth="1px" borderColor="green.200" borderRadius="md" p={2} bg="white">
                                      <Text fontSize="xs" fontWeight="bold" mb={1}>Added rule {r.key}</Text>
                                      <Flex direction="column" gap={1}>
                                        {ruleDisplayFields.map((df) => (
                                          <Flex key={`rule-add-${r.key}-${df.key}`} justify="space-between" gap={2}>
                                            <Text fontSize="10px" opacity={0.7}>{df.label}</Text>
                                            <Text fontSize="xs" fontFamily="mono">{diffFieldVal(r[df.key])}</Text>
                                          </Flex>
                                        ))}
                                      </Flex>
                                    </Box>
                                  ))}
                                  {aiDiff.addedRules.length === 0 && <Text fontSize="xs" opacity={0.8}>No added rules.</Text>}
                                </Flex>
                              </AccordionPanel>
                            </AccordionItem>

                            <AccordionItem border="1px solid" borderColor="red.200" borderRadius="md" bg="red.50" mt={2}>
                              <AccordionButton>
                                <Flex flex="1" align="center" justify="space-between" pr={2}>
                                  <Text fontSize="xs" fontWeight="bold">Removed rules</Text>
                                  <Badge colorScheme={aiDiff.removedRules.length > 0 ? 'red' : 'gray'}>{aiDiff.removedRules.length}</Badge>
                                </Flex>
                                <AccordionIcon />
                              </AccordionButton>
                              <AccordionPanel pt={0}>
                                <Flex direction="column" gap={2}>
                                  {sortedByKey(aiDiff.removedRules, (r) => String(r.key)).map((r) => (
                                    <Box key={`rmr-${r.key}`} borderWidth="1px" borderColor="red.200" borderRadius="md" p={2} bg="white">
                                      <Text fontSize="xs" fontWeight="bold" mb={1}>Removed rule {r.key}</Text>
                                      <Flex direction="column" gap={1}>
                                        {ruleDisplayFields.map((df) => (
                                          <Flex key={`rule-remove-${r.key}-${df.key}`} justify="space-between" gap={2}>
                                            <Text fontSize="10px" opacity={0.7}>{df.label}</Text>
                                            <Text fontSize="xs" fontFamily="mono">{diffFieldVal(r[df.key])}</Text>
                                          </Flex>
                                        ))}
                                      </Flex>
                                    </Box>
                                  ))}
                                  {aiDiff.removedRules.length === 0 && <Text fontSize="xs" opacity={0.8}>No removed rules.</Text>}
                                </Flex>
                              </AccordionPanel>
                            </AccordionItem>
                          </Accordion>

                          {aiDiff.addedRules.length === 0 && aiDiff.removedRules.length === 0 && aiDiff.changedRules.length === 0 && (
                            <Text fontSize="xs" opacity={0.8}>No rulecheck changes.</Text>
                          )}
                        </Flex>
                      </Box>
                    </Flex>
                  )}
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

      <Drawer isOpen={isHelpOpen} placement="left" onClose={() => setIsHelpOpen(false)} size="md">
        <DrawerOverlay />
        <DrawerContent>
          <DrawerCloseButton />
          <DrawerHeader>Help - Versions History Inspection</DrawerHeader>
          <DrawerBody>
            <Flex direction="column" gap={4}>
              <Box>
                <Text fontWeight="bold" mb={1}>What this page is for</Text>
                <Text fontSize="sm">
                  Use this page to compare two invoice versions and quickly see what changed.
                  You can compare contractor-side extracted data and AI-side extracted/check data.
                </Text>
              </Box>

              <Box>
                <Text fontWeight="bold" mb={1}>Top context area</Text>
                <Text fontSize="sm">This gives you quick context before you compare:</Text>
                <Text fontSize="sm">- invoice_id: which invoice you are reviewing.</Text>
                <Text fontSize="sm">- invoices.status: current invoice status.</Text>
                <Text fontSize="sm">- invoices.created_at: when the invoice record was created.</Text>
                <Text fontSize="sm">- session_created_at: when this invoice session started.</Text>
                <Text fontSize="sm">- contractor: the contractor business name tied to the invoice session.</Text>
              </Box>

              <Box>
                <Text fontWeight="bold" mb={1}>How to compare versions</Text>
                <Text fontSize="sm">1. Pick one row as A and one row as B.</Text>
                <Text fontSize="sm">2. Click the diff refresh icon.</Text>
                <Text fontSize="sm">3. Read the two diff tabs:</Text>
                <Text fontSize="sm">- Diff Contractor Changes: invoice/header fields and line item changes.</Text>
                <Text fontSize="sm">- Diff AI Changes: AI extracted fields and AI rule check changes.</Text>
              </Box>

              <Box>
                <Text fontWeight="bold" mb={1}>How to read A vs B</Text>
                <Text fontSize="sm">- A is the older/original side you selected.</Text>
                <Text fontSize="sm">- B is the newer/target side you selected.</Text>
                <Text fontSize="sm">- In each card, left = A (before), right = B (after).</Text>
              </Box>

              <Box>
                <Text fontWeight="bold" mb={1}>Examples</Text>
                <Text fontSize="sm">Example 1: Contractor line item quantity changed from 2 to 3. This appears under Changed line in contractor diff.</Text>
                <Text fontSize="sm">Example 2: AI rule changed from pass=true to pass=false. This appears under Changed rule in AI diff.</Text>
                <Text fontSize="sm">Example 3: A located field moved line but value stayed the same. This is not treated as a content change.</Text>
              </Box>

              <Box>
                <Text fontWeight="bold" mb={1}>Tips</Text>
                <Text fontSize="sm">- Start with the summary badges to see where changes exist.</Text>
                <Text fontSize="sm">- Use the row PDF icon to open the version PDF in a separate tab if you need visual confirmation.</Text>
                <Text fontSize="sm">- If nothing appears in changed sections, the two versions are effectively the same for that section.</Text>
              </Box>
            </Flex>
          </DrawerBody>
        </DrawerContent>
      </Drawer>
    </Flex>
  );
}