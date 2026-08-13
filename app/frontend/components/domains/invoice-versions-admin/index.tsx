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

  created_at?: string;
  updated_at?: string;
};

type InvoiceMeta = {
  id: string;
  updated_at?: string | null;
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
  changedRules: Array<{ key: string; before: any; after: any; beforeRule?: any; afterRule?: any }>;
  unchangedFailingRules: Array<{ key: string; before: any; after: any; beforeRule?: any; afterRule?: any }>;
};

type SimpleDiffRow = { label: string; before: string; after: string };
type SimpleDiffSection = {
  title: string;
  rows: SimpleDiffRow[];
  upgradeTypeKey?: string | null;
  beforePass?: boolean | null;
  afterPass?: boolean | null;
  beforeResult?: string | null;
  afterResult?: string | null;
  beforeRule?: any | null;
  afterRule?: any | null;
};

type PdfChangeRow = {
  id: string;
  category: string;
  title: string;
  before: string;
  after: string;
  rows: SimpleDiffRow[];
};

type PdfChangeGroup = {
  upgradeTypeKey: string;
  rows: PdfChangeRow[];
};

type RuleDiffGroup = {
  upgradeTypeKey: string;
  sections: SimpleDiffSection[];
};

const fmtTs = (s?: string | null) => (s ? String(s).replace('T', ' ').replace('Z', '') : '');
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
  { key: 'result', label: 'Rule result' },
];

const ruleDetailFields = [
  { key: 'source_engine', label: 'Source' },
  { key: 'upgrade_type_key', label: 'Upgrade type' },
  { key: 'rule_key', label: 'Rule key' },
  { key: 'rule_result', label: 'Rule result' },
  { key: 'confidence', label: 'Confidence' },
  { key: 'expected_text', label: 'Expected' },
  { key: 'observed_text', label: 'Observed' },
  { key: 'calculation', label: 'Calculation' },
  { key: 'evidence_text', label: 'Evidence' },
  { key: 'reason_and_likely_causes', label: 'Reason' },
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

type StatusDotProps = { result?: string | null; pass?: boolean | null | undefined; label?: string };

function formatRuleResult(result?: string | null): string {
  const normalized = String(result ?? '').trim();
  return normalized || 'missing';
}

function StatusDot({ result, pass, label }: StatusDotProps) {
  const normalized = String(result ?? '').toLowerCase();
  const bg =
    normalized === 'pass'
      ? 'green.400'
      : normalized === 'info'
        ? 'blue.400'
        : normalized === 'warn'
          ? 'orange.400'
          : normalized === 'fail'
            ? 'red.400'
            : pass === true
              ? 'green.400'
              : pass === false
                ? 'red.400'
                : 'gray.300';

  const tooltip = label || `Rule result: ${formatRuleResult(result)}`;

  return (
    <Tooltip label={tooltip} hasArrow placement="top">
      <Box
        as="span"
        w="10px"
        h="10px"
        borderRadius="full"
        display="inline-block"
        bg={bg}
        flexShrink={0}
        aria-label={tooltip}
      />
    </Tooltip>
  );
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
  const overallDefs = [{ key: 'validation_result', label: 'Validation result' }];

  const overallChanges = overallDefs
    .filter((f) => norm(a.read?.[f.key]) !== norm(b.read?.[f.key]))
    .map((f) => ({
      label: f.label,
      before: norm(a.read?.[f.key]) || '—',
      after: norm(b.read?.[f.key]) || '—',
    }));

  const fieldKey = (r: any) =>
    [r?.source_engine ?? '', r?.upgrade_type_key ?? r?.invoice_upgrade_type_id ?? '', r?.field_key ?? ''].join('|');
  const baseFieldKey = (k: string) =>
    String(k || '')
      .split('|')
      .pop() || k;
  const genaiLocatedFieldsA = a.locatedFields.filter((r) => String(r?.source_engine ?? '').toLowerCase() === 'genai');
  const genaiLocatedFieldsB = b.locatedFields.filter((r) => String(r?.source_engine ?? '').toLowerCase() === 'genai');
  const locatedMeaningfulChanged = (x: any, y: any): boolean => {
    const xValue = norm(x?.value);
    const yValue = norm(y?.value);
    return xValue !== yValue;
  };
  const mapFieldA = new Map(
    genaiLocatedFieldsA.map((r) => [
      fieldKey(r),
      {
        field_key: r?.field_key ?? '',
        source_engine: r?.source_engine ?? '',
        upgrade_type_key: r?.upgrade_type_key ?? null,
        value: r?.value_text ?? null,
        confidence: r?.confidence ?? null,
      },
    ]),
  );
  const mapFieldB = new Map(
    genaiLocatedFieldsB.map((r) => [
      fieldKey(r),
      {
        field_key: r?.field_key ?? '',
        source_engine: r?.source_engine ?? '',
        upgrade_type_key: r?.upgrade_type_key ?? null,
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

  const ruleKey = (r: any) => [r?.source_engine ?? '', r?.upgrade_type_key ?? '', r?.rule_key ?? r?.id ?? ''].join('|');
  const toRuleComparable = (r: any) => ({
    rule_key: r?.rule_key ?? null,
    result: r?.rule_result ?? null,
  });
  const toRuleEntry = (r: any) => ({
    comparable: toRuleComparable(r),
    raw: r,
  });
  const mapRuleA = new Map(a.rulechecks.map((r) => [ruleKey(r), toRuleEntry(r)]));
  const mapRuleB = new Map(b.rulechecks.map((r) => [ruleKey(r), toRuleEntry(r)]));

  const addedRules: any[] = [];
  const removedRules: any[] = [];
  const changedRules: Array<{ key: string; before: any; after: any; beforeRule?: any; afterRule?: any }> = [];
  const unchangedFailingRules: Array<{ key: string; before: any; after: any; beforeRule?: any; afterRule?: any }> = [];

  mapRuleB.forEach((v, k) => {
    if (!mapRuleA.has(k)) addedRules.push({ key: k, ...v.comparable, rawRule: v.raw });
  });
  mapRuleA.forEach((v, k) => {
    if (!mapRuleB.has(k)) removedRules.push({ key: k, ...v.comparable, rawRule: v.raw });
  });
  mapRuleA.forEach((vA, k) => {
    if (!mapRuleB.has(k)) return;
    const vB = mapRuleB.get(k);
    if (norm(vA?.comparable?.result) !== norm(vB?.comparable?.result)) {
      changedRules.push({
        key: k,
        before: vA?.comparable,
        after: vB?.comparable,
        beforeRule: vA?.raw,
        afterRule: vB?.raw,
      });
    } else if (String(vB?.comparable?.result ?? '').toLowerCase() === 'fail') {
      unchangedFailingRules.push({
        key: k,
        before: vA?.comparable,
        after: vB?.comparable,
        beforeRule: vA?.raw,
        afterRule: vB?.raw,
      });
    }
  });

  return {
    overallChanges,
    addedFields,
    removedFields,
    changedFields,
    addedRules,
    removedRules,
    changedRules,
    unchangedFailingRules,
  };
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
  const upgradeType = entry.before?.upgrade_type_key || entry.after?.upgrade_type_key;
  return upgradeType ? `Field ${fieldKey} (${upgradeType})` : `Field ${fieldKey}`;
}

function locatedFieldUpgradeType(before?: any | null, after?: any | null): string {
  return String(after?.upgrade_type_key || before?.upgrade_type_key || 'common');
}

function locatedFieldDiffSections(diff: AiDiff): SimpleDiffSection[] {
  const changed = sortedByKey(diff.changedFields, (item) => item.key).map((item) => ({
    title: locatedFieldTitle(item),
    rows: buildDiffRows(locatedFieldDisplayFields, item.before, item.after, diffFieldVal),
    upgradeTypeKey: locatedFieldUpgradeType(item.before, item.after),
  }));

  const added = sortedByKey(diff.addedFields, (item) => String(item.key)).map((item) => ({
    title: locatedFieldTitle({ key: String(item.key), after: item }),
    rows: buildDiffRows(locatedFieldDisplayFields, {}, item, diffFieldVal),
    upgradeTypeKey: locatedFieldUpgradeType(null, item),
  }));

  const removed = sortedByKey(diff.removedFields, (item) => String(item.key)).map((item) => ({
    title: locatedFieldTitle({ key: String(item.key), before: item }),
    rows: buildDiffRows(locatedFieldDisplayFields, item, {}, diffFieldVal),
    upgradeTypeKey: locatedFieldUpgradeType(item, null),
  }));

  return [...changed, ...added, ...removed].filter((section) => section.rows.length > 0);
}

function firstChangedValue(rows: SimpleDiffRow[], side: 'before' | 'after'): string {
  const row = rows.find((r) => norm(r[side]));
  return row?.[side] || '—';
}

function invoicePdfChangeRows(
  contractorDiff: ContractorDiff | null,
  lineSections: SimpleDiffSection[],
): PdfChangeRow[] {
  if (!contractorDiff) return [];

  const headerRows = contractorDiff.changedFields.map((field) => ({
    id: `header-${field.label}`,
    category: 'Header',
    title: field.label,
    before: field.before || '—',
    after: field.after || '—',
    rows: [{ label: field.label, before: field.before || '—', after: field.after || '—' }],
  }));

  const lineRows = lineSections.map((section) => ({
    id: `line-${section.title}`,
    category: 'Line item',
    title: section.title,
    before: firstChangedValue(section.rows, 'before'),
    after: firstChangedValue(section.rows, 'after'),
    rows: section.rows,
  }));

  return [...headerRows, ...lineRows];
}

function locatedFieldPdfChangeGroups(locatedSections: SimpleDiffSection[]): PdfChangeGroup[] {
  const groups = new Map<string, PdfChangeRow[]>();

  sortedByKey(locatedSections, (section) => `${section.upgradeTypeKey || 'common'}|${section.title}`).forEach(
    (section) => {
      const upgradeTypeKey = section.upgradeTypeKey || 'common';
      const groupRows = groups.get(upgradeTypeKey) || [];

      groupRows.push({
        id: `genai-field-${upgradeTypeKey}-${section.title}`,
        category: 'GenAI field',
        title: section.title,
        before: firstChangedValue(section.rows, 'before'),
        after: firstChangedValue(section.rows, 'after'),
        rows: section.rows,
      });

      groups.set(upgradeTypeKey, groupRows);
    },
  );

  return Array.from(groups.entries()).map(([upgradeTypeKey, groupRows]) => ({
    upgradeTypeKey,
    rows: groupRows,
  }));
}

function ruleSectionTitle(ruleNumber: string, record?: any): string {
  const key = String(record?.rule_key ?? '').trim();
  return key || `rule_${ruleNumber}`;
}

function ruleUpgradeType(beforeRule?: any | null, afterRule?: any | null): string {
  return String(afterRule?.upgrade_type_key || beforeRule?.upgrade_type_key || 'unknown_upgrade_type');
}

function ruleDiffSections(diff: AiDiff): SimpleDiffSection[] {
  const changed = sortedByKey(diff.changedRules, (item) => item.key).map((item) => ({
    title: ruleSectionTitle(item.key, item.after || item.before),
    rows: buildDiffRows(ruleDisplayFields, item.before, item.after, diffFieldVal),
    upgradeTypeKey: ruleUpgradeType(item.beforeRule, item.afterRule),
    beforeResult: item.before?.result,
    afterResult: item.after?.result,
    beforeRule: item.beforeRule,
    afterRule: item.afterRule,
  }));

  const added = sortedByKey(diff.addedRules, (item) => String(item.key)).map((item) => ({
    title: ruleSectionTitle(String(item.key), item),
    rows: buildDiffRows(ruleDisplayFields, {}, item, diffFieldVal),
    upgradeTypeKey: ruleUpgradeType(null, item.rawRule),
    beforeResult: null,
    afterResult: item.result,
    beforeRule: null,
    afterRule: item.rawRule,
  }));

  const removed = sortedByKey(diff.removedRules, (item) => String(item.key)).map((item) => ({
    title: ruleSectionTitle(String(item.key), item),
    rows: buildDiffRows(ruleDisplayFields, item, {}, diffFieldVal),
    upgradeTypeKey: ruleUpgradeType(item.rawRule, null),
    beforeResult: item.result,
    afterResult: null,
    beforeRule: item.rawRule,
    afterRule: null,
  }));

  return [...changed, ...added, ...removed].filter((section) => section.rows.length > 0);
}

function ruleDiffGroups(sections: SimpleDiffSection[]): RuleDiffGroup[] {
  const groups = new Map<string, SimpleDiffSection[]>();

  sortedByKey(sections, (section) => `${section.upgradeTypeKey || 'unknown_upgrade_type'}|${section.title}`).forEach(
    (section) => {
      const key = section.upgradeTypeKey || 'unknown_upgrade_type';
      const group = groups.get(key) || [];
      group.push(section);
      groups.set(key, group);
    },
  );

  return Array.from(groups.entries()).map(([upgradeTypeKey, groupSections]) => ({
    upgradeTypeKey,
    sections: groupSections,
  }));
}

function unchangedFailingRuleSections(diff: AiDiff): SimpleDiffSection[] {
  return sortedByKey(diff.unchangedFailingRules, (item) => item.key).map((item) => ({
    title: ruleSectionTitle(item.key, item.afterRule || item.beforeRule || item.after || item.before),
    rows: buildDiffRows(ruleDisplayFields, item.before, item.after, diffFieldVal),
    upgradeTypeKey: ruleUpgradeType(item.beforeRule, item.afterRule),
    beforeResult: item.before?.result,
    afterResult: item.after?.result,
    beforeRule: item.beforeRule,
    afterRule: item.afterRule,
  }));
}

export function InvoiceVersionsAdminScreen() {
  const [invoiceId, setInvoiceId] = useState<string>('');
  const [invoiceMeta, setInvoiceMeta] = useState<InvoiceMeta | null>(null);
  const [loading, setLoading] = useState<boolean>(false);
  const [error, setError] = useState<string>('');

  const [rows, setRows] = useState<InvoiceVersionRow[]>([]);
  const [selectedVersionId, setSelectedVersionId] = useState<string>('');
  const [isHelpOpen, setIsHelpOpen] = useState<boolean>(false);

  const [diffAId, setDiffAId] = useState<string>('');
  const [diffBId, setDiffBId] = useState<string>('');
  const [diffLoading, setDiffLoading] = useState<boolean>(false);
  const [diffError, setDiffError] = useState<string>('');
  const [contractorDiff, setContractorDiff] = useState<ContractorDiff | null>(null);
  const [aiDiff, setAiDiff] = useState<AiDiff | null>(null);
  const [selectedPdfDiff, setSelectedPdfDiff] = useState<PdfChangeRow | null>(null);
  const [selectedRuleDiff, setSelectedRuleDiff] = useState<SimpleDiffSection | null>(null);

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
    setDiffAId('');
    setDiffBId('');
    setDiffError('');
    setContractorDiff(null);
    setAiDiff(null);

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

  useEffect(() => {
    if (!invoiceId.trim()) return;
    fetchRows(invoiceId.trim());
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [invoiceId]);

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
    setSelectedPdfDiff(null);
    setSelectedRuleDiff(null);

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
    } catch (e: any) {
      setContractorDiff(null);
      setAiDiff(null);
      setSelectedPdfDiff(null);
      setSelectedRuleDiff(null);
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

  const contractorLineSections = contractorDiff ? lineitemDiffSections(contractorDiff) : [];
  const aiLocatedSections = aiDiff ? locatedFieldDiffSections(aiDiff) : [];
  const pdfChangeRows = invoicePdfChangeRows(contractorDiff, contractorLineSections);
  const pdfLocatedGroups = locatedFieldPdfChangeGroups(aiLocatedSections);
  const aiRuleSections = aiDiff ? ruleDiffSections(aiDiff) : [];
  const aiRuleGroups = ruleDiffGroups(aiRuleSections);
  const stillFailingRuleGroups = aiDiff ? ruleDiffGroups(unchangedFailingRuleSections(aiDiff)) : [];
  const selectedVersion = rows.find((row) => row.id === selectedVersionId) || rows[0] || null;
  const contextInvoiceNumber = selectedVersion?.di_ocr_invoice_id || '';

  return (
    <Flex as="main" direction="column" w="full" bg="greys.white" pb="24" minH="100vh">
      <ThinBlueTitleBar title="Versions History Inspection" />

      <Container maxW="full" px={6} pb={4} flex="1" pt={6}>
        <Box p={5} bg="white">
          <Flex align="flex-start" justify="space-between" gap={6} mb={5} wrap="wrap">
            <Flex wrap="wrap" gap={6}>
              <Box>
                <Text fontSize="xs" opacity={0.7}>
                  contractor_name
                </Text>
                <Text fontSize="sm">{invoiceMeta?.contractor_business_name || '—'}</Text>
              </Box>
              <Box>
                <Text fontSize="xs" opacity={0.7}>
                  invoice #
                </Text>
                <Text fontSize="sm">{contextInvoiceNumber || '—'}</Text>
              </Box>
            </Flex>

            <Tooltip label="Help for this screen">
              <IconButton
                aria-label="Open versions history help"
                icon={<Question size={18} />}
                size="sm"
                variant="outline"
                onClick={() => setIsHelpOpen(true)}
              />
            </Tooltip>
          </Flex>

          {error && (
            <Box mb={4} p={3} bg="red.50" borderWidth="1px" borderColor="red.200" borderRadius="md">
              <Text fontSize="sm" color="red.700">
                {error}
              </Text>
            </Box>
          )}

          {/* grid */}
          <Box bg="white" mb={4}>
            <Flex align="center" justify="flex-end" mb={2}>
              {loading && <Spinner size="sm" />}
            </Flex>

            <Table size="sm">
              <Thead
                sx={{
                  th: {
                    bg: 'linear-gradient(180deg, rgba(49, 130, 206, 0.12) 0%, rgba(255, 255, 255, 0) 88%)',
                    color: 'blue.900',
                    borderBottomColor: 'blue.100',
                  },
                }}
              >
                <Tr>
                  <Th w="120px">Diff Select</Th>
                  <Th w="210px">Updated</Th>
                  <Th w="100px">Version</Th>
                  <Th textAlign="right"></Th>
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
                    onClick={() => setSelectedVersionId(r.id)}
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
          <Box bg="white">
            <Flex align="center" justify="flex-end" mb={2}>
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
              </Flex>
            </Flex>

            {diffError && (
              <Box mb={3} p={2} bg="red.50" borderWidth="1px" borderColor="red.200" borderRadius="md">
                <Text fontSize="xs" color="red.700">
                  {diffError}
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
                <Tab>Invoice PDF Changes</Tab>
                <Tab>Rule Status Changes</Tab>
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
                        {pdfChangeRows.length === 0 && pdfLocatedGroups.length === 0 ? (
                          <Text fontSize="xs" opacity={0.8}>
                            No invoice PDF changes.
                          </Text>
                        ) : (
                          <Box borderWidth="1px" borderColor="gray.200" borderRadius="md" overflowX="auto" bg="white">
                            <Table
                              size="sm"
                              variant="simple"
                              sx={{
                                'th, td': {
                                  py: 1,
                                },
                              }}
                            >
                              <Thead>
                                <Tr>
                                  <Th>Type</Th>
                                  <Th>Change</Th>
                                  <Th>A</Th>
                                  <Th>B</Th>
                                  <Th w="56px">Info</Th>
                                </Tr>
                              </Thead>
                              <Tbody>
                                {pdfChangeRows.map((row) => (
                                  <Tr key={row.id}>
                                    <Td>
                                      <Text fontSize="xs" noOfLines={1}>
                                        {row.category}
                                      </Text>
                                    </Td>
                                    <Td>
                                      <Text fontSize="xs" fontWeight="bold" fontFamily="mono" noOfLines={1}>
                                        {row.title}
                                      </Text>
                                    </Td>
                                    <Td maxW="260px">
                                      <Text fontSize="xs" noOfLines={1}>
                                        {row.before}
                                      </Text>
                                    </Td>
                                    <Td maxW="260px">
                                      <Text fontSize="xs" noOfLines={1}>
                                        {row.after}
                                      </Text>
                                    </Td>
                                    <Td>
                                      <Tooltip label="Show old and new values" hasArrow>
                                        <IconButton
                                          aria-label={`Show invoice PDF change for ${row.title}`}
                                          icon={<Info />}
                                          size="xs"
                                          variant="ghost"
                                          onClick={() => setSelectedPdfDiff(row)}
                                        />
                                      </Tooltip>
                                    </Td>
                                  </Tr>
                                ))}
                                {pdfLocatedGroups.map((group) => (
                                  <React.Fragment key={group.upgradeTypeKey}>
                                    <Tr>
                                      <Td colSpan={5} bg="gray.50">
                                        <Text fontSize="xs" fontWeight="bold" fontFamily="mono">
                                          {group.upgradeTypeKey}
                                        </Text>
                                      </Td>
                                    </Tr>
                                    {group.rows.map((row) => (
                                      <Tr key={row.id}>
                                        <Td>
                                          <Text fontSize="xs" noOfLines={1}>
                                            {row.category}
                                          </Text>
                                        </Td>
                                        <Td>
                                          <Text fontSize="xs" fontWeight="bold" fontFamily="mono" noOfLines={1}>
                                            {row.title}
                                          </Text>
                                        </Td>
                                        <Td maxW="260px">
                                          <Text fontSize="xs" noOfLines={1}>
                                            {row.before}
                                          </Text>
                                        </Td>
                                        <Td maxW="260px">
                                          <Text fontSize="xs" noOfLines={1}>
                                            {row.after}
                                          </Text>
                                        </Td>
                                        <Td>
                                          <Tooltip label="Show old and new values" hasArrow>
                                            <IconButton
                                              aria-label={`Show invoice PDF change for ${row.title}`}
                                              icon={<Info />}
                                              size="xs"
                                              variant="ghost"
                                              onClick={() => setSelectedPdfDiff(row)}
                                            />
                                          </Tooltip>
                                        </Td>
                                      </Tr>
                                    ))}
                                  </React.Fragment>
                                ))}
                              </Tbody>
                            </Table>
                          </Box>
                        )}
                      </Box>

                      <Box
                        display="none"
                        borderWidth="1px"
                        borderColor="greys.grey20"
                        borderRadius="md"
                        p={3}
                        bg="gray.50"
                      >
                        <Text fontSize="sm" fontWeight="bold" mb={2}>
                          Legacy hidden header diff
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

                      <Box
                        display="none"
                        borderWidth="1px"
                        borderColor="greys.grey20"
                        borderRadius="md"
                        p={3}
                        bg="gray.50"
                      >
                        <Text fontSize="sm" fontWeight="bold" mb={2}>
                          Legacy hidden line diff
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
                      <Box
                        display="none"
                        borderWidth="1px"
                        borderColor="greys.grey20"
                        borderRadius="md"
                        p={3}
                        bg="gray.50"
                      >
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

                      <Box
                        display="none"
                        borderWidth="1px"
                        borderColor="greys.grey20"
                        borderRadius="md"
                        p={3}
                        bg="gray.50"
                      >
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
                        <Text fontSize="sm" fontWeight="semibold" mb={2}>
                          Rule Status Changes
                        </Text>
                        {aiRuleGroups.length === 0 ? (
                          <Text fontSize="xs" opacity={0.8}>
                            No rule status changes.
                          </Text>
                        ) : (
                          <Box borderWidth="1px" borderColor="gray.200" borderRadius="md" overflowX="auto" bg="white">
                            <Table size="sm" variant="simple">
                              <Thead>
                                <Tr>
                                  <Th>Rule</Th>
                                  <Th w="64px">A</Th>
                                  <Th w="28px"></Th>
                                  <Th w="64px">B</Th>
                                  <Th w="56px">Info</Th>
                                </Tr>
                              </Thead>
                              <Tbody>
                                {aiRuleGroups.map((group) => (
                                  <React.Fragment key={group.upgradeTypeKey}>
                                    <Tr>
                                      <Td colSpan={5} bg="gray.50">
                                        <Text fontSize="xs" fontWeight="bold" fontFamily="mono">
                                          {group.upgradeTypeKey}
                                        </Text>
                                      </Td>
                                    </Tr>
                                    {group.sections.map((section) => (
                                      <Tr key={section.title}>
                                        <Td>
                                          <Text fontSize="xs" fontWeight="bold" fontFamily="mono">
                                            {section.title}
                                          </Text>
                                        </Td>
                                        <Td>
                                          <StatusDot
                                            result={section.beforeResult}
                                            label={`A: ${formatRuleResult(section.beforeResult)}`}
                                          />
                                        </Td>
                                        <Td>
                                          <Text fontSize="10px" opacity={0.5}>
                                            →
                                          </Text>
                                        </Td>
                                        <Td>
                                          <StatusDot
                                            result={section.afterResult}
                                            label={`B: ${formatRuleResult(section.afterResult)}`}
                                          />
                                        </Td>
                                        <Td>
                                          <Tooltip label="Show old and new rule text" hasArrow>
                                            <IconButton
                                              aria-label={`Show rule text for ${section.title}`}
                                              icon={<Info />}
                                              size="xs"
                                              variant="ghost"
                                              onClick={() => setSelectedRuleDiff(section)}
                                            />
                                          </Tooltip>
                                        </Td>
                                      </Tr>
                                    ))}
                                  </React.Fragment>
                                ))}
                              </Tbody>
                            </Table>
                          </Box>
                        )}
                      </Box>

                      {stillFailingRuleGroups.length > 0 && (
                        <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="md" p={3} bg="gray.50">
                          <Text fontSize="sm" fontWeight="semibold" mb={1}>
                            Still Failing in B
                          </Text>
                          <Text fontSize="xs" opacity={0.75} mb={3}>
                            These rules are still hard failures in the selected B version, even though their status did
                            not change from A.
                          </Text>
                          <Box borderWidth="1px" borderColor="gray.200" borderRadius="md" overflowX="auto" bg="white">
                            <Table size="sm" variant="simple">
                              <Thead>
                                <Tr>
                                  <Th>Rule</Th>
                                  <Th w="64px">A</Th>
                                  <Th w="28px"></Th>
                                  <Th w="64px">B</Th>
                                  <Th w="56px">Info</Th>
                                </Tr>
                              </Thead>
                              <Tbody>
                                {stillFailingRuleGroups.map((group) => (
                                  <React.Fragment key={`still-failing-${group.upgradeTypeKey}`}>
                                    <Tr>
                                      <Td colSpan={5} bg="gray.50">
                                        <Text fontSize="xs" fontWeight="bold" fontFamily="mono">
                                          {group.upgradeTypeKey}
                                        </Text>
                                      </Td>
                                    </Tr>
                                    {group.sections.map((section) => (
                                      <Tr key={`still-failing-${section.title}`}>
                                        <Td>
                                          <Text fontSize="xs" fontWeight="bold" fontFamily="mono">
                                            {section.title}
                                          </Text>
                                        </Td>
                                        <Td>
                                          <StatusDot
                                            result={section.beforeResult}
                                            label={`A: ${formatRuleResult(section.beforeResult)}`}
                                          />
                                        </Td>
                                        <Td>
                                          <Text fontSize="10px" opacity={0.5}>
                                            →
                                          </Text>
                                        </Td>
                                        <Td>
                                          <StatusDot
                                            result={section.afterResult}
                                            label={`B: ${formatRuleResult(section.afterResult)}`}
                                          />
                                        </Td>
                                        <Td>
                                          <Tooltip label="Show old and new rule text" hasArrow>
                                            <IconButton
                                              aria-label={`Show still failing rule text for ${section.title}`}
                                              icon={<Info />}
                                              size="xs"
                                              variant="ghost"
                                              onClick={() => setSelectedRuleDiff(section)}
                                            />
                                          </Tooltip>
                                        </Td>
                                      </Tr>
                                    ))}
                                  </React.Fragment>
                                ))}
                              </Tbody>
                            </Table>
                          </Box>
                        </Box>
                      )}
                    </Flex>
                  )}
                </TabPanel>
              </TabPanels>
            </Tabs>
          </Box>
        </Box>
      </Container>

      <Drawer isOpen={!!selectedPdfDiff} placement="right" onClose={() => setSelectedPdfDiff(null)} size="xl">
        <DrawerOverlay />
        <DrawerContent>
          <DrawerCloseButton />
          <DrawerHeader>Invoice PDF Change</DrawerHeader>
          <DrawerBody>
            {!selectedPdfDiff ? (
              <Text fontSize="sm" opacity={0.7}>
                No change selected.
              </Text>
            ) : (
              <Flex direction="column" gap={4}>
                <Box>
                  <Text fontSize="xs" opacity={0.7} mb={1}>
                    {selectedPdfDiff.category}
                  </Text>
                  <Text fontSize="sm" fontWeight="bold" fontFamily="mono">
                    {selectedPdfDiff.title}
                  </Text>
                </Box>

                <Box borderWidth="1px" borderColor="gray.200" borderRadius="md" overflowX="auto">
                  <Table size="sm" variant="simple">
                    <Thead>
                      <Tr>
                        <Th>Value</Th>
                        <Th>A</Th>
                        <Th>B</Th>
                      </Tr>
                    </Thead>
                    <Tbody>
                      {selectedPdfDiff.rows.map((row) => (
                        <Tr key={row.label}>
                          <Td>
                            <Text fontSize="xs" fontWeight="bold">
                              {row.label}
                            </Text>
                          </Td>
                          <Td>
                            <Text fontSize="xs" whiteSpace="pre-wrap">
                              {row.before || '—'}
                            </Text>
                          </Td>
                          <Td>
                            <Text fontSize="xs" whiteSpace="pre-wrap">
                              {row.after || '—'}
                            </Text>
                          </Td>
                        </Tr>
                      ))}
                    </Tbody>
                  </Table>
                </Box>
              </Flex>
            )}
          </DrawerBody>
        </DrawerContent>
      </Drawer>

      <Drawer isOpen={!!selectedRuleDiff} placement="right" onClose={() => setSelectedRuleDiff(null)} size="xl">
        <DrawerOverlay />
        <DrawerContent>
          <DrawerCloseButton />
          <DrawerHeader>Rule Text Change</DrawerHeader>
          <DrawerBody>
            {!selectedRuleDiff ? (
              <Text fontSize="sm" opacity={0.7}>
                No rule selected.
              </Text>
            ) : (
              <Flex direction="column" gap={4}>
                <Box>
                  <Text fontSize="xs" opacity={0.7} mb={1}>
                    Rule
                  </Text>
                  <Text fontSize="sm" fontWeight="bold" fontFamily="mono">
                    {selectedRuleDiff.title}
                  </Text>
                </Box>

                <Flex gap={3} align="stretch" direction={{ base: 'column', md: 'row' }}>
                  {[
                    {
                      label: `A: ${formatRuleResult(selectedRuleDiff.beforeResult)}`,
                      record: selectedRuleDiff.beforeRule,
                    },
                    {
                      label: `B: ${formatRuleResult(selectedRuleDiff.afterResult)}`,
                      record: selectedRuleDiff.afterRule,
                    },
                  ].map((column) => (
                    <Box
                      key={column.label}
                      flex="1"
                      borderWidth="1px"
                      borderColor="gray.200"
                      borderRadius="md"
                      bg="gray.50"
                      p={3}
                    >
                      <Text fontSize="sm" fontWeight="bold" mb={3}>
                        {column.label}
                      </Text>

                      {!column.record ? (
                        <Text fontSize="sm" opacity={0.7}>
                          No rulecheck record in this version.
                        </Text>
                      ) : (
                        <Flex direction="column" gap={3}>
                          {ruleDetailFields.map((field) => (
                            <Box key={field.key}>
                              <Text fontSize="10px" opacity={0.7} mb={1}>
                                {field.label}
                              </Text>
                              <Box
                                as="pre"
                                fontFamily="mono"
                                fontSize="xs"
                                whiteSpace="pre-wrap"
                                borderWidth="1px"
                                borderColor="gray.200"
                                borderRadius="md"
                                p={2}
                                bg="white"
                                minH="28px"
                              >
                                {diffFieldVal(column.record?.[field.key])}
                              </Box>
                            </Box>
                          ))}
                        </Flex>
                      )}
                    </Box>
                  ))}
                </Flex>
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
                  focused on two diff tabs: invoice PDF changes and rule status changes.
                </Text>
              </Box>

              <Box>
                <Text fontWeight="bold" mb={1}>
                  Top context area
                </Text>
                <Text fontSize="sm">This gives you quick context before you compare:</Text>
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
                  - Invoice PDF Changes: OCR/header fields, line items, and GenAI located fields when the values
                  changed.
                </Text>
                <Text fontSize="sm">
                  - Rule Status Changes: rulechecks when status changed, when a rule was added or removed, plus rules
                  that are still failing in B.
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
