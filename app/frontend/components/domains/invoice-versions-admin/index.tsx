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
  IconButton,
  Input,
  Text,
  Tooltip,
} from '@chakra-ui/react';
import { Table, Thead, Tbody, Tr, Th, Td, Spinner } from '@chakra-ui/react';
import { Tabs, TabList, TabPanels, Tab, TabPanel } from '@chakra-ui/react';
import { ArrowsClockwise, FilePdf, Info, Question } from '@phosphor-icons/react';
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

type DrawerView = 'details' | 'diJson' | 'genaiJson' | 'genaiAdvice';
type SimpleDiffRow = { label: string; before: string; after: string };
type SimpleDiffSection = {
  title: string;
  rows: SimpleDiffRow[];
  beforePass?: boolean | null;
  afterPass?: boolean | null;
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
  { key: 'value', label: 'Value' },
  { key: 'confidence', label: 'Confidence' },
];

const ruleDisplayFields = [
  { key: 'rule_key', label: 'Rule key' },
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

type StatusDotProps = { pass: boolean | null | undefined };

function StatusDot({ pass }: StatusDotProps) {
  const bg = pass === true ? 'green.400' : pass === false ? 'red.400' : 'red.400';

  return <Box as="span" w="10px" h="10px" borderRadius="full" display="inline-block" bg={bg} flexShrink={0} />;
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
    { key: 'genai_result', label: 'Overall result' },
    { key: 'genai_admin_advice', label: 'Admin advice' },
  ];

  const overallChanges = overallDefs
    .filter((f) => norm(a.read?.[f.key]) !== norm(b.read?.[f.key]))
    .map((f) => ({
      label: f.label,
      before: norm(a.read?.[f.key]) || '—',
      after: norm(b.read?.[f.key]) || '—',
    }));

  const fieldKey = (r: any) => String(r?.field_key ?? '');
  const baseFieldKey = (k: string) => String(k || '').split('|')[0] || k;
  const locatedMeaningfulChanged = (x: any, y: any): boolean => {
    const xValue = norm(x?.value);
    const yValue = norm(y?.value);
    return xValue !== yValue;
  };
  const mapFieldA = new Map(
    a.locatedFields.map((r) => [
      fieldKey(r),
      {
        field_key: r?.field_key ?? '',
        value: r?.value_text ?? null,
        confidence: r?.confidence ?? null,
      },
    ]),
  );
  const mapFieldB = new Map(
    b.locatedFields.map((r) => [
      fieldKey(r),
      {
        field_key: r?.field_key ?? '',
        value: r?.value_text ?? null,
        confidence: r?.confidence ?? null,
      },
    ]),
  );

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
  const mapRuleA = new Map(
    a.rulechecks.map((r) => [
      ruleKey(r),
      {
        rule_key: r?.rule_key ?? null,
        result: r?.rule_result ?? null,
        confidence: r?.confidence ?? null,
        expected: r?.expected_text ?? null,
        observed: r?.observed_text ?? null,
        reason: r?.reason_and_likely_causes ?? null,
      },
    ]),
  );
  const mapRuleB = new Map(
    b.rulechecks.map((r) => [
      ruleKey(r),
      {
        rule_key: r?.rule_key ?? null,
        result: r?.rule_result ?? null,
        confidence: r?.confidence ?? null,
        expected: r?.expected_text ?? null,
        observed: r?.observed_text ?? null,
        reason: r?.reason_and_likely_causes ?? null,
      },
    ]),
  );

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

function buildDiffRows(
  defs: Array<{ key: string; label: string }>,
  beforeObj: any,
  afterObj: any,
  valueFormatter: (value: any) => string,
): SimpleDiffRow[] {
  return defs
    .map((def) => ({
      label: def.label,
      beforeRaw: beforeObj?.[def.key],
      afterRaw: afterObj?.[def.key],
    }))
    .filter((row) => norm(row.beforeRaw) !== norm(row.afterRaw))
    .map((row) => ({
      label: row.label,
      before: valueFormatter(row.beforeRaw),
      after: valueFormatter(row.afterRaw),
    }));
}

function lineitemDiffSections(diff: ContractorDiff): SimpleDiffSection[] {
  const changed = sortedByKey(diff.changedLineitems, (item) => item.key).map((item) => ({
    title: `Line ${item.key}`,
    rows: buildDiffRows(lineitemFields, item.before, item.after, lineitemFieldVal),
  }));

  const added = sortedByKey(diff.addedLineitems, (item) => String(item.key)).map((item) => ({
    title: `Line ${item.key}`,
    rows: buildDiffRows(lineitemFields, {}, item, lineitemFieldVal),
  }));

  const removed = sortedByKey(diff.removedLineitems, (item) => String(item.key)).map((item) => ({
    title: `Line ${item.key}`,
    rows: buildDiffRows(lineitemFields, item, {}, lineitemFieldVal),
  }));

  return [...changed, ...added, ...removed].filter((section) => section.rows.length > 0);
}

function locatedFieldTitle(entry: { key: string; before?: any; after?: any }): string {
  const fieldKey = entry.before?.field_key || entry.after?.field_key || entry.key;
  return `Field ${fieldKey}`;
}

function locatedFieldDiffSections(diff: AiDiff): SimpleDiffSection[] {
  const changed = sortedByKey(diff.changedFields, (item) => item.key).map((item) => ({
    title: locatedFieldTitle(item),
    rows: buildDiffRows(locatedFieldDisplayFields, item.before, item.after, diffFieldVal),
  }));

  const added = sortedByKey(diff.addedFields, (item) => String(item.key)).map((item) => ({
    title: locatedFieldTitle({ key: String(item.key), after: item }),
    rows: buildDiffRows(locatedFieldDisplayFields, {}, item, diffFieldVal),
  }));

  const removed = sortedByKey(diff.removedFields, (item) => String(item.key)).map((item) => ({
    title: locatedFieldTitle({ key: String(item.key), before: item }),
    rows: buildDiffRows(locatedFieldDisplayFields, item, {}, diffFieldVal),
  }));

  return [...changed, ...added, ...removed].filter((section) => section.rows.length > 0);
}

function ruleSectionTitle(ruleNumber: string, record?: any): string {
  const key = String(record?.rule_key ?? '').trim();
  return key || `rule_${ruleNumber}`;
}

function ruleDiffSections(diff: AiDiff): SimpleDiffSection[] {
  const changed = sortedByKey(diff.changedRules, (item) => item.key).map((item) => ({
    title: ruleSectionTitle(item.key, item.after || item.before),
    rows: buildDiffRows(ruleDisplayFields, item.before, item.after, diffFieldVal),
    beforePass: item.before?.pass,
    afterPass: item.after?.pass,
  }));

  const added = sortedByKey(diff.addedRules, (item) => String(item.key)).map((item) => ({
    title: ruleSectionTitle(String(item.key), item),
    rows: buildDiffRows(ruleDisplayFields, {}, item, diffFieldVal),
    beforePass: null,
    afterPass: item.pass,
  }));

  const removed = sortedByKey(diff.removedRules, (item) => String(item.key)).map((item) => ({
    title: ruleSectionTitle(String(item.key), item),
    rows: buildDiffRows(ruleDisplayFields, item, {}, diffFieldVal),
    beforePass: item.pass,
    afterPass: null,
  }));

  return [...changed, ...added, ...removed].filter((section) => section.rows.length > 0);
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
  const [drawerView, setDrawerView] = useState<DrawerView>('details');

  const [diJson, setDiJson] = useState<any | null>(null);
  const [genaiJson, setGenaiJson] = useState<any | null>(null);

  const [diffAId, setDiffAId] = useState<string>('');
  const [diffBId, setDiffBId] = useState<string>('');
  const [diffLoading, setDiffLoading] = useState<boolean>(false);
  const [diffError, setDiffError] = useState<string>('');
  const [contractorDiff, setContractorDiff] = useState<ContractorDiff | null>(null);
  const [aiDiff, setAiDiff] = useState<AiDiff | null>(null);
  const [lastDiffPair, setLastDiffPair] = useState<{ a: string; b: string } | null>(null);

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
      setDrawerView('details');
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
      setDrawerView('details');
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
    if (!genaiRes.ok)
      throw new Error(genaiJson?.error || genaiJson?.message || `GenAI read failed (${genaiRes.status}).`);

    return {
      invoiceVersionId,
      read: readJson?.read || null,
      lineitems: Array.isArray(readJson?.lineitems) ? readJson.lineitems : [],
      locatedFields: Array.isArray(genaiJson?.located_fields) ? genaiJson.located_fields : [],
      rulechecks: [
        ...(Array.isArray(genaiJson?.code_rulechecks) ? genaiJson.code_rulechecks : []),
        ...(Array.isArray(genaiJson?.rulechecks) ? genaiJson.rulechecks : []),
      ],
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

  const contractorLineSections = contractorDiff ? lineitemDiffSections(contractorDiff) : [];
  const aiLocatedSections = aiDiff ? locatedFieldDiffSections(aiDiff) : [];
  const aiRuleSections = aiDiff ? ruleDiffSections(aiDiff) : [];

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
                <Input value={invoiceId} isReadOnly bg="white" fontFamily="mono" />
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
              <Text fontSize="xs">
                A:{' '}
                <Box as="span" fontFamily="mono">
                  {diffAId || '—'}
                </Box>
              </Text>
              <Text fontSize="xs">
                B:{' '}
                <Box as="span" fontFamily="mono">
                  {diffBId || '—'}
                </Box>
              </Text>
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
                            const url = `/invoice-versions/${encodeURIComponent(r.id)}/review`;
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

          {/* diff panels */}
          <Box bg="white" borderWidth="1px" borderColor="greys.grey20" borderRadius="md" p={3}>
            <Flex align="center" justify="space-between" mb={2}>
              <Text fontSize="sm" fontWeight="bold">
                Version diffs
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
                <Text fontSize="xs" color="red.700">
                  {diffError}
                </Text>
              </Box>
            )}

            {lastDiffPair && (
              <Box mb={3} p={2} bg="blue.50" borderWidth="1px" borderColor="blue.200" borderRadius="md">
                <Text fontSize="xs">
                  Diff loaded for A:{' '}
                  <Box as="span" fontFamily="mono">
                    {lastDiffPair.a}
                  </Box>{' '}
                  and B:{' '}
                  <Box as="span" fontFamily="mono">
                    {lastDiffPair.b}
                  </Box>
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
                '.chakra-tabs__tablist': {
                  borderBottomWidth: '2px',
                  borderColor: 'gray.300',
                },

                // the active tab underline
                '.chakra-tabs__tab[aria-selected=true]': {
                  borderBottomWidth: '4px',
                  borderColor: 'gray.800',
                },
              }}
            >
              <TabList>
                <Tab>Diff Contractor Changes</Tab>
                <Tab>Diff AI Changes</Tab>
              </TabList>

              <TabPanels>
                <TabPanel p={3}>
                  {!contractorDiff ? (
                    <Text fontSize="sm" opacity={0.75}>
                      Pick A and B, then click diff refresh.
                    </Text>
                  ) : (
                    <Flex direction="column" gap={3}>
                      <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="md" p={3} bg="gray.50">
                        <Text fontSize="sm" fontWeight="bold" mb={2}>
                          Header field changes
                        </Text>
                        {contractorDiff.changedFields.length === 0 ? (
                          <Text fontSize="xs" opacity={0.8}>
                            No header field changes.
                          </Text>
                        ) : (
                          <Flex direction="column" gap={2}>
                            {contractorDiff.changedFields.map((f) => (
                              <Box
                                key={f.label}
                                borderWidth="1px"
                                borderColor="gray.200"
                                borderRadius="md"
                                p={2}
                                bg="white"
                              >
                                <Text fontSize="xs" fontWeight="bold" mb={1}>
                                  {f.label}
                                </Text>
                                <Flex gap={3}>
                                  <Box flex="1">
                                    <Text fontSize="10px" opacity={0.7}>
                                      A (before)
                                    </Text>
                                    <Text fontSize="xs" fontFamily="mono" whiteSpace="pre-wrap">
                                      {f.before || '—'}
                                    </Text>
                                  </Box>
                                  <Box flex="1">
                                    <Text fontSize="10px" opacity={0.7}>
                                      B (after)
                                    </Text>
                                    <Text fontSize="xs" fontFamily="mono" whiteSpace="pre-wrap">
                                      {f.after || '—'}
                                    </Text>
                                  </Box>
                                </Flex>
                              </Box>
                            ))}
                          </Flex>
                        )}
                      </Box>

                      <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="md" p={3} bg="gray.50">
                        <Text fontSize="sm" fontWeight="bold" mb={2}>
                          Line item changes
                        </Text>
                        <Flex direction="column" gap={2}>
                          {contractorLineSections.length === 0 ? (
                            <Text fontSize="xs" opacity={0.8}>
                              No line item changes.
                            </Text>
                          ) : (
                            contractorLineSections.map((section) => (
                              <Box
                                key={section.title}
                                borderWidth="1px"
                                borderColor="gray.200"
                                borderRadius="md"
                                p={2}
                                bg="white"
                              >
                                <Text fontSize="xs" fontWeight="bold" mb={1}>
                                  {section.title}
                                </Text>
                                <Flex direction="column" gap={1}>
                                  {section.rows.map((row) => (
                                    <Box
                                      key={`${section.title}-${row.label}`}
                                      borderTopWidth="1px"
                                      borderColor="gray.100"
                                      pt={1}
                                    >
                                      <Text fontSize="10px" opacity={0.7}>
                                        {row.label}
                                      </Text>
                                      <Flex gap={3}>
                                        <Box flex="1">
                                          <Text fontSize="10px" opacity={0.7}>
                                            A (before)
                                          </Text>
                                          <Text fontSize="xs" fontFamily="mono" whiteSpace="pre-wrap">
                                            {row.before || '-'}
                                          </Text>
                                        </Box>
                                        <Box flex="1">
                                          <Text fontSize="10px" opacity={0.7}>
                                            B (after)
                                          </Text>
                                          <Text fontSize="xs" fontFamily="mono" whiteSpace="pre-wrap">
                                            {row.after || '-'}
                                          </Text>
                                        </Box>
                                      </Flex>
                                    </Box>
                                  ))}
                                </Flex>
                              </Box>
                            ))
                          )}
                        </Flex>
                      </Box>
                    </Flex>
                  )}
                </TabPanel>

                <TabPanel p={3}>
                  {!aiDiff ? (
                    <Text fontSize="sm" opacity={0.75}>
                      Pick A and B, then click diff refresh.
                    </Text>
                  ) : (
                    <Flex direction="column" gap={3}>
                      <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="md" p={3} bg="gray.50">
                        <Text fontSize="sm" fontWeight="bold" mb={2}>
                          Overall AI changes
                        </Text>
                        {aiDiff.overallChanges.length === 0 ? (
                          <Text fontSize="xs" opacity={0.8}>
                            No overall AI field changes.
                          </Text>
                        ) : (
                          <Flex direction="column" gap={2}>
                            {aiDiff.overallChanges.map((f) => (
                              <Box
                                key={f.label}
                                borderWidth="1px"
                                borderColor="gray.200"
                                borderRadius="md"
                                p={2}
                                bg="white"
                              >
                                <Text fontSize="xs" fontWeight="bold" mb={1}>
                                  {f.label}
                                </Text>
                                <Flex gap={3}>
                                  <Box flex="1">
                                    <Text fontSize="10px" opacity={0.7}>
                                      A (before)
                                    </Text>
                                    <Text fontSize="xs" fontFamily="mono" whiteSpace="pre-wrap">
                                      {f.before || '—'}
                                    </Text>
                                  </Box>
                                  <Box flex="1">
                                    <Text fontSize="10px" opacity={0.7}>
                                      B (after)
                                    </Text>
                                    <Text fontSize="xs" fontFamily="mono" whiteSpace="pre-wrap">
                                      {f.after || '—'}
                                    </Text>
                                  </Box>
                                </Flex>
                              </Box>
                            ))}
                          </Flex>
                        )}
                      </Box>

                      <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="md" p={3} bg="gray.50">
                        <Text fontSize="sm" fontWeight="bold" mb={2}>
                          Located field changes
                        </Text>
                        {aiLocatedSections.length === 0 ? (
                          <Text fontSize="xs" opacity={0.8}>
                            No located field changes.
                          </Text>
                        ) : (
                          <Flex direction="column" gap={2}>
                            {aiLocatedSections.map((section) => (
                              <Box
                                key={section.title}
                                borderWidth="1px"
                                borderColor="gray.200"
                                borderRadius="md"
                                p={2}
                                bg="white"
                              >
                                <Text fontSize="xs" fontWeight="bold" mb={1}>
                                  {section.title}
                                </Text>
                                <Flex direction="column" gap={1}>
                                  {section.rows.map((row) => (
                                    <Box
                                      key={`${section.title}-${row.label}`}
                                      borderTopWidth="1px"
                                      borderColor="gray.100"
                                      pt={1}
                                    >
                                      <Text fontSize="10px" opacity={0.7}>
                                        {row.label}
                                      </Text>
                                      <Flex gap={3}>
                                        <Box flex="1">
                                          <Text fontSize="10px" opacity={0.7}>
                                            A (before)
                                          </Text>
                                          <Text fontSize="xs" fontFamily="mono" whiteSpace="pre-wrap">
                                            {row.before || '-'}
                                          </Text>
                                        </Box>
                                        <Box flex="1">
                                          <Text fontSize="10px" opacity={0.7}>
                                            B (after)
                                          </Text>
                                          <Text fontSize="xs" fontFamily="mono" whiteSpace="pre-wrap">
                                            {row.after || '-'}
                                          </Text>
                                        </Box>
                                      </Flex>
                                    </Box>
                                  ))}
                                </Flex>
                              </Box>
                            ))}
                          </Flex>
                        )}
                      </Box>

                      <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="md" p={3} bg="gray.50">
                        <Text fontSize="sm" fontWeight="bold" mb={2}>
                          Rulecheck changes
                        </Text>
                        {aiRuleSections.length === 0 ? (
                          <Text fontSize="xs" opacity={0.8}>
                            No rulecheck changes.
                          </Text>
                        ) : (
                          <Flex direction="column" gap={2}>
                            {aiRuleSections.map((section) => (
                              <Box
                                key={section.title}
                                borderWidth="1px"
                                borderColor="gray.200"
                                borderRadius="md"
                                p={2}
                                bg="white"
                              >
                                <Flex align="center" justify="space-between" gap={3} mb={1} wrap="wrap">
                                  <Text fontSize="xs" fontWeight="bold">
                                    {section.title}
                                  </Text>
                                  <Flex align="center" gap={3}>
                                    <Flex align="center" gap={2}>
                                      <Text fontSize="10px" opacity={0.7}>
                                        A
                                      </Text>
                                      <StatusDot pass={section.beforePass} />
                                    </Flex>
                                    <Text fontSize="10px" opacity={0.5}>
                                      →
                                    </Text>
                                    <Flex align="center" gap={2}>
                                      <Text fontSize="10px" opacity={0.7}>
                                        B
                                      </Text>
                                      <StatusDot pass={section.afterPass} />
                                    </Flex>
                                  </Flex>
                                </Flex>
                                <Flex direction="column" gap={1}>
                                  {section.rows.map((row) => (
                                    <Box
                                      key={`${section.title}-${row.label}`}
                                      borderTopWidth="1px"
                                      borderColor="gray.100"
                                      pt={1}
                                    >
                                      <Text fontSize="10px" opacity={0.7}>
                                        {row.label}
                                      </Text>
                                      <Flex gap={3}>
                                        <Box flex="1">
                                          <Text fontSize="10px" opacity={0.7}>
                                            A (before)
                                          </Text>
                                          <Text fontSize="xs" fontFamily="mono" whiteSpace="pre-wrap">
                                            {row.before || '-'}
                                          </Text>
                                        </Box>
                                        <Box flex="1">
                                          <Text fontSize="10px" opacity={0.7}>
                                            B (after)
                                          </Text>
                                          <Text fontSize="xs" fontFamily="mono" whiteSpace="pre-wrap">
                                            {row.after || '-'}
                                          </Text>
                                        </Box>
                                      </Flex>
                                    </Box>
                                  ))}
                                </Flex>
                              </Box>
                            ))}
                          </Flex>
                        )}
                      </Box>
                    </Flex>
                  )}
                </TabPanel>
              </TabPanels>
            </Tabs>
          </Box>
        </Box>
      </Container>

      <Drawer isOpen={isDrawerOpen} placement="right" onClose={() => setIsDrawerOpen(false)} size="xl">
        <DrawerOverlay />
        <DrawerContent>
          <DrawerCloseButton />
          <DrawerHeader>Invoice Version Inspection Details</DrawerHeader>
          <DrawerBody>
            {!selectedDetail ? (
              <Text fontSize="sm" opacity={0.7}>
                No row selected.
              </Text>
            ) : (
              <Flex direction="column" gap={3}>
                <Flex gap={2} wrap="wrap">
                  <Button
                    size="sm"
                    variant={drawerView === 'details' ? 'solid' : 'outline'}
                    colorScheme="blue"
                    onClick={() => setDrawerView('details')}
                  >
                    Details
                  </Button>
                  <Button
                    size="sm"
                    variant={drawerView === 'diJson' ? 'solid' : 'outline'}
                    colorScheme="blue"
                    onClick={() => setDrawerView('diJson')}
                  >
                    DI JSON
                  </Button>
                  <Button
                    size="sm"
                    variant={drawerView === 'genaiJson' ? 'solid' : 'outline'}
                    colorScheme="blue"
                    onClick={() => setDrawerView('genaiJson')}
                  >
                    GenAI JSON
                  </Button>
                  <Button
                    size="sm"
                    variant={drawerView === 'genaiAdvice' ? 'solid' : 'outline'}
                    colorScheme="blue"
                    onClick={() => setDrawerView('genaiAdvice')}
                  >
                    GenAI Advice
                  </Button>
                </Flex>

                {drawerView === 'details' && (
                  <Flex direction="column" gap={3}>
                    {detailEntries.map(([k, v]) => (
                      <Box key={k}>
                        <Text fontSize="xs" opacity={0.7} mb={1}>
                          {k}
                        </Text>
                        {typeof v === 'object' && v !== null ? (
                          <Box
                            as="pre"
                            fontFamily="mono"
                            fontSize="xs"
                            whiteSpace="pre-wrap"
                            borderWidth="1px"
                            borderColor="greys.grey20"
                            borderRadius="md"
                            p={3}
                            bg="gray.50"
                            maxH="260px"
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

                {drawerView === 'diJson' && (
                  <Box>
                    <Text fontSize="xs" opacity={0.7} mb={1}>
                      di_raw_json
                    </Text>
                    <Box
                      as="pre"
                      fontFamily="mono"
                      fontSize="xs"
                      whiteSpace="pre-wrap"
                      borderWidth="1px"
                      borderColor="greys.grey20"
                      borderRadius="md"
                      p={3}
                      bg="gray.50"
                      minH="420px"
                      maxH="70vh"
                      overflow="auto"
                    >
                      {diJson ? prettyJson(diJson) : 'No DI JSON found for this version.'}
                    </Box>
                  </Box>
                )}

                {drawerView === 'genaiJson' && (
                  <Box>
                    <Text fontSize="xs" opacity={0.7} mb={1}>
                      genai_raw_json
                    </Text>
                    <Box
                      as="pre"
                      fontFamily="mono"
                      fontSize="xs"
                      whiteSpace="pre-wrap"
                      borderWidth="1px"
                      borderColor="greys.grey20"
                      borderRadius="md"
                      p={3}
                      bg="gray.50"
                      minH="420px"
                      maxH="70vh"
                      overflow="auto"
                    >
                      {genaiJson ? prettyJson(genaiJson) : 'No GenAI JSON found for this version.'}
                    </Box>
                  </Box>
                )}

                {drawerView === 'genaiAdvice' && (
                  <Box>
                    <Text fontSize="xs" opacity={0.7} mb={1}>
                      genai_admin_advice
                    </Text>
                    <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="md" p={3} bg="gray.50" minH="220px">
                      <Text fontSize="sm" whiteSpace="pre-wrap">
                        {selectedDetail?.genai_admin_advice
                          ? String(selectedDetail.genai_admin_advice)
                          : 'No GenAI advice found for this version.'}
                      </Text>
                    </Box>
                  </Box>
                )}
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
                <Text fontWeight="bold" mb={1}>
                  What this page is for
                </Text>
                <Text fontSize="sm">
                  Use this page to compare two invoice versions and quickly see what changed. The main view is now
                  focused on just the two diff tabs: contractor changes and AI changes.
                </Text>
              </Box>

              <Box>
                <Text fontWeight="bold" mb={1}>
                  Top context area
                </Text>
                <Text fontSize="sm">This gives you quick context before you compare:</Text>
                <Text fontSize="sm">- invoice_id: which invoice you are reviewing.</Text>
                <Text fontSize="sm">- invoices.status: current invoice status.</Text>
                <Text fontSize="sm">- invoices.created_at: when the invoice record was created.</Text>
                <Text fontSize="sm">- session_created_at: when this invoice session started.</Text>
                <Text fontSize="sm">- contractor: the contractor business name tied to the invoice session.</Text>
              </Box>

              <Box>
                <Text fontWeight="bold" mb={1}>
                  How to compare versions
                </Text>
                <Text fontSize="sm">1. Pick one row as A and one row as B.</Text>
                <Text fontSize="sm">2. Click the diff refresh icon.</Text>
                <Text fontSize="sm">3. Read the two diff tabs:</Text>
                <Text fontSize="sm">
                  - Diff Contractor Changes: invoice/header fields and line item changes only when the values actually
                  changed.
                </Text>
                <Text fontSize="sm">
                  - Diff AI Changes: AI extracted fields and AI rule check changes only when the values actually
                  changed.
                </Text>
              </Box>

              <Box>
                <Text fontWeight="bold" mb={1}>
                  How to read A vs B
                </Text>
                <Text fontSize="sm">- A is the older/original side you selected.</Text>
                <Text fontSize="sm">- B is the newer/target side you selected.</Text>
                <Text fontSize="sm">- In each card, left = A (before), right = B (after).</Text>
              </Box>

              <Box>
                <Text fontWeight="bold" mb={1}>
                  Drawer contents
                </Text>
                <Text fontSize="sm">Use the row details icon to open the drawer.</Text>
                <Text fontSize="sm">Inside the drawer you can switch between:</Text>
                <Text fontSize="sm">- Details</Text>
                <Text fontSize="sm">- DI JSON</Text>
                <Text fontSize="sm">- GenAI JSON</Text>
                <Text fontSize="sm">- GenAI Advice</Text>
              </Box>

              <Box>
                <Text fontWeight="bold" mb={1}>
                  Tips
                </Text>
                <Text fontSize="sm">- Only changed values are shown in the diff tabs.</Text>
                <Text fontSize="sm">
                  - Added or removed values are shown as a before/after change rather than with badges.
                </Text>
                <Text fontSize="sm">
                  - Use the row PDF icon to open the version PDF in a separate tab if you need visual confirmation.
                </Text>
                <Text fontSize="sm">
                  - If nothing appears in changed sections, the two versions are effectively the same for that section.
                </Text>
              </Box>
            </Flex>
          </DrawerBody>
        </DrawerContent>
      </Drawer>
    </Flex>
  );
}
