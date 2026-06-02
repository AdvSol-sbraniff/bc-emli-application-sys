// /app/frontend/components/domains/invoice-versions/index.tsx
import { fmtDate, fmtMoney, fmtText } from './display';

import {
  Box,
  Button,
  Heading,
  Text,
  Flex,
  Container,
  Accordion,
  AccordionItem,
  Badge,
  AccordionButton,
  AccordionPanel,
  AccordionIcon,
  Drawer,
  DrawerBody,
  DrawerCloseButton,
  DrawerContent,
  DrawerHeader,
  DrawerOverlay,
  IconButton,
  Tooltip,
  useDisclosure,
  useToast,
} from '@chakra-ui/react';
import { ThinBlueTitleBar } from '../../shared/base/thin-blue-title-bar';
import {
  getInvoiceUpgradeTypeMeta,
  INVOICE_UPGRADE_TYPE_FILTER_ORDER,
  InvoiceUpgradeTypeTile,
} from '../../shared/claims/invoice-upgrade-type-visual';
import { Question } from '@phosphor-icons/react';

// ============================================================
// SECTION 00 - FILE OVERVIEW
// PURPOSE: Invoice read screen with left fields + PDF viewer + DI polygon highlight
// ============================================================

import React, { useEffect, useMemo, useRef, useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { Document, Page, pdfjs } from 'react-pdf';
import 'react-pdf/dist/Page/AnnotationLayer.css';
import 'react-pdf/dist/Page/TextLayer.css';

//import workerSrc from "pdfjs-dist/build/pdf.worker.min.mjs-url";
//pdfjs.GlobalWorkerOptions.workerSrc = workerSrc;
pdfjs.GlobalWorkerOptions.workerSrc = `https://unpkg.com/pdfjs-dist@${pdfjs.version}/build/pdf.worker.min.mjs`;

// ============================================================
// SECTION 01.01 - UI COMPONENTS
// PURPOSE: Small reusable row widgets for left-hand field list
// ============================================================

type FieldRowProps = {
  label: string;
  value: any;
  active?: boolean;
  disabled?: boolean;
  onClick?: () => void;
};

const FieldRow = ({ label, value, active, disabled, onClick }: FieldRowProps) => {
  return (
    <Box
      role={disabled ? undefined : 'button'}
      onClick={disabled ? undefined : onClick}
      px="10px"
      py="8px"
      mb="6px"
      borderRadius="md"
      borderWidth="1px"
      borderColor={active ? 'blue.400' : 'transparent'}
      bg={active ? 'blue.50' : 'transparent'}
      cursor={disabled ? 'not-allowed' : 'pointer'}
      opacity={disabled ? 0.6 : 1}
      _hover={
        disabled
          ? {}
          : {
              bg: active ? 'blue.50' : 'gray.50',
              borderColor: active ? 'blue.400' : 'gray.200',
            }
      }
      display="flex"
      flexDirection="column"
      gap="2px"
    >
      <Text fontSize="xs" opacity={0.7}>
        {label}
      </Text>
      <Text fontSize="sm" fontWeight={active ? 'semibold' : 'normal'} noOfLines={2}>
        {String(value)}
      </Text>
    </Box>
  );
};

const ruleDisplayTitle = (rulecheck: any) => {
  const num = rulecheck.rule_number != null ? Number(rulecheck.rule_number) : null;
  const sourceEngine = String(rulecheck.source_engine ?? '').toLowerCase();
  const prefix = sourceEngine === 'code' ? `Code Rule ${num ?? ''}`.trim() : `${num != null ? `Rule ${num}` : 'Rule'}`;

  return `${prefix} - ${String(rulecheck.rule_name ?? '')}`.trim();
};

const ruleSourceLabel = (rulecheck: any) => {
  const sourceEngine = String(rulecheck.source_engine ?? '').toLowerCase();
  if (sourceEngine === 'code') return 'code';
  if (sourceEngine === 'genai') return 'genai';
  return sourceEngine || '';
};

const displayLocatedFieldValue = (row: any): string => {
  if (row?.value_text != null && row.value_text !== '') return String(row.value_text);
  if (row?.value_json != null) return JSON.stringify(row.value_json);
  return '-';
};

const fmtBytes = (value: any): string => {
  const n = Number(value);
  if (!Number.isFinite(n) || n <= 0) return '-';
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`;
  return `${(n / (1024 * 1024)).toFixed(1)} MB`;
};

const upgradeTypeSortValue = (upgradeTypeKey: string) => {
  if (upgradeTypeKey === 'common') return -1;
  const index = INVOICE_UPGRADE_TYPE_FILTER_ORDER.indexOf(upgradeTypeKey as any);
  return index === -1 ? Number.MAX_SAFE_INTEGER : index;
};

const upgradeTypeKeyFor = (row: any) => String(row?.upgrade_type_key || 'common');

const upgradeTypeDescriptionFor = (row: any) => {
  const upgradeTypeKey = upgradeTypeKeyFor(row);
  return row?.upgrade_type_description || getInvoiceUpgradeTypeMeta(upgradeTypeKey).label;
};

const classifierRawJsonFor = (row: any): Record<string, any> => {
  const raw = row?.raw_json;
  if (!raw) return {};
  if (typeof raw === 'string') {
    try {
      const parsed = JSON.parse(raw);
      return parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? parsed : {};
    } catch {
      return {};
    }
  }
  return typeof raw === 'object' && !Array.isArray(raw) ? raw : {};
};

const classifierExplanationFor = (row: any): string => {
  const raw = classifierRawJsonFor(row);
  return String(raw.classification_explanation || '').trim();
};

const uniqueClassifierEvidenceFor = (row: any): string[] => {
  const raw = classifierRawJsonFor(row);
  const seen = new Set<string>();
  return [raw.evidence_text]
    .map((value) => String(value ?? '').trim())
    .filter((value) => {
      if (!value || seen.has(value)) return false;
      seen.add(value);
      return true;
    });
};

// ============================================================
// SECTION 01.02 - UI COMPONENTS (STATUS DOT)
// PURPOSE: Small green/yellow/red/gray dot for rule result
// ============================================================

type RuleResult = 'pass' | 'info' | 'warn' | 'fail' | null | undefined;

const normalizeResult = (result: unknown): RuleResult => {
  const value = String(result ?? '')
    .trim()
    .toLowerCase();
  return value === 'pass' || value === 'info' || value === 'warn' || value === 'fail' ? value : null;
};

const resultLabel = (result: unknown): string => normalizeResult(result)?.toUpperCase() ?? 'UNKNOWN';

const resultColorScheme = (result: unknown): string => {
  const normalized = normalizeResult(result);
  if (normalized === 'pass') return 'green';
  if (normalized === 'info') return 'blue';
  if (normalized === 'warn') return 'yellow';
  if (normalized === 'fail') return 'red';
  return 'gray';
};

const resultDotColor = (result: unknown): string => {
  const normalized = normalizeResult(result);
  if (normalized === 'pass') return 'green.400';
  if (normalized === 'info') return 'blue.400';
  if (normalized === 'warn') return 'yellow.400';
  if (normalized === 'fail') return 'red.400';
  return 'gray.400';
};

const resultTooltip = (result: unknown): string => {
  const normalized = normalizeResult(result);
  if (normalized === 'pass') return 'pass: do not show in advice; admin can skim or ignore.';
  if (normalized === 'info') return 'info: may show in advice as helpful context, not a requested fix.';
  if (normalized === 'warn') return 'warn: always show, framed as admin/contractor verification.';
  if (normalized === 'fail') return 'fail: always show, framed as correction needed.';
  return 'unknown: rule result was not recognized.';
};

const StatusDot = ({ result }: { result: unknown }) => {
  const bg = resultDotColor(result);

  return (
    <Tooltip label={resultTooltip(result)} hasArrow placement="top">
      <Box as="span" w="10px" h="10px" borderRadius="full" display="inline-block" bg={bg} flexShrink={0} />
    </Tooltip>
  );
};

type InvoiceStatusTransition = 'screen_in' | 'request_revision' | 'approve_pending' | 'mark_paid';

const invoiceStatusLabel = (status: unknown): string => {
  const value = String(status ?? '').trim();
  if (!value) return 'unknown';
  if (value === 'genai_complete') return 'genai_complete - contractor reviewing';
  return value;
};

const INVOICE_STATUS_ACTIONS: Array<{
  key: InvoiceStatusTransition;
  label: string;
  validFrom: string[];
  targetStatus: string;
  colorScheme: string;
  tooltip: string;
}> = [
  {
    key: 'screen_in',
    label: 'Send to Supervisor',
    validFrom: ['admin_review_inbox'],
    targetStatus: 'in_review',
    colorScheme: 'blue',
    tooltip:
      'First approval level. Regular admins use this after reviewing an invoice in admin_review_inbox. Moves status to in_review for supervisor approval.',
  },
  {
    key: 'request_revision',
    label: 'Send to Contractor for Revision',
    validFrom: ['admin_review_inbox', 'in_review'],
    targetStatus: 'contractor_revision_inbox',
    colorScheme: 'orange',
    tooltip:
      'Use when an invoice in admin_review_inbox or in_review needs contractor fixes or supporting information. Moves status to contractor_revision_inbox. The actual message to the contractor is handled as a separate revision request record.',
  },
  {
    key: 'approve_pending',
    label: 'Approve Pending',
    validFrom: ['in_review'],
    targetStatus: 'approved_pending',
    colorScheme: 'green',
    tooltip:
      'Second approval level. Supervisors use this after reviewing an invoice in in_review. Moves status to approved_pending.',
  },
  {
    key: 'mark_paid',
    label: 'Mark Paid',
    validFrom: ['approved_pending'],
    targetStatus: 'approved_paid',
    colorScheme: 'green',
    tooltip:
      'Third approval level. Use after payment has been issued or confirmed for an invoice in approved_pending. Moves status to approved_paid.',
  },
];

// ============================================================
// SECTION 02.02 - FIELD CATALOG
// PURPOSE: Single source of truth for left-panel rows + highlight mapping
// ============================================================

type FieldCatalogItem = {
  key: string; // unique key used in UI + highlight selector
  label: string; // left-panel label
  valueKey: string; // readData field holding the value
  formatter?: (v: any) => string; // display formatter
  pageKey?: string; // readData field holding page number
  polygonKey?: string; // readData field holding polygon array/json
  disabled?: boolean; // allow showing row but not clickable
};

const DI_FIELDS: FieldCatalogItem[] = [
  // ----------------------------
  // DI first class fields
  // ----------------------------
  {
    key: 'invoice_id',
    label: 'Invoice #',
    valueKey: 'di_ocr_invoice_id',
    formatter: fmtText,
    pageKey: 'di_ocr_invoice_id_page',
    polygonKey: 'di_ocr_invoice_id_polygon',
  },
  {
    key: 'invoice_date',
    label: 'Invoice date',
    valueKey: 'di_ocr_invoice_date',
    formatter: fmtDate,
    pageKey: 'di_ocr_invoice_date_page',
    polygonKey: 'di_ocr_invoice_date_polygon',
  },
  {
    key: 'vendor_name',
    label: 'BUSINESS NAME',
    valueKey: 'di_ocr_vendor_name',
    formatter: fmtText,
    pageKey: 'di_ocr_vendor_name_page',
    polygonKey: 'di_ocr_vendor_name_polygon',
  },
  {
    key: 'vendor_address',
    label: 'Vendor address',
    valueKey: 'di_ocr_vendor_address',
    formatter: fmtText,
    pageKey: 'di_ocr_vendor_address_page',
    polygonKey: 'di_ocr_vendor_address_polygon',
  },
  {
    key: 'customer_name',
    label: 'Customer name',
    valueKey: 'di_ocr_customer_name',
    formatter: fmtText,
    pageKey: 'di_ocr_customer_name_page',
    polygonKey: 'di_ocr_customer_name_polygon',
  },
  {
    key: 'billing_address',
    label: 'Billing address',
    valueKey: 'di_ocr_billing_address',
    formatter: fmtText,
    pageKey: 'di_ocr_billing_address_page',
    polygonKey: 'di_ocr_billing_address_polygon',
  },
  {
    key: 'sub_total',
    label: 'Sub-total',
    valueKey: 'di_ocr_sub_total',
    formatter: fmtMoney,
    pageKey: 'di_ocr_sub_total_page',
    polygonKey: 'di_ocr_sub_total_polygon',
  },
  {
    key: 'total_tax',
    label: 'Total tax',
    valueKey: 'di_ocr_total_tax',
    formatter: fmtMoney,
    pageKey: 'di_ocr_total_tax_page',
    polygonKey: 'di_ocr_total_tax_polygon',
  },
  {
    key: 'invoice_total',
    label: 'Invoice total',
    valueKey: 'di_ocr_invoice_total',
    formatter: fmtMoney,
    pageKey: 'di_ocr_invoice_total_page',
    polygonKey: 'di_ocr_invoice_total_polygon',
  },
  {
    key: 'amount_due',
    label: 'Amount due',
    valueKey: 'di_ocr_amount_due',
    formatter: fmtMoney,
    pageKey: 'di_ocr_amount_due_page',
    polygonKey: 'di_ocr_amount_due_polygon',
  },
];

// ============================================================
// SECTION 03.01 - SCREEN COMPONENT
// PURPOSE: Main screen component + hooks + render
// ============================================================
export const InvoiceVersionShowScreen = () => {
  // ============================================================
  // SECTION 04.01 - ROUTE PARAMS
  // PURPOSE: Read sessionId/invoiceId from URL + create navigate() helper
  // ============================================================

  const { sessionId, invoiceId, id, invoiceVersionId } = useParams();
  const navigate = useNavigate();
  const toast = useToast();
  const routeInvoiceVersionId = String(id || invoiceVersionId || '').trim();
  const routeInvoiceId = String(invoiceId || '').trim();
  const isVersionSnapshotRoute = !!routeInvoiceVersionId;
  const isInvoiceCurrentRoute = !!routeInvoiceId && !sessionId && !isVersionSnapshotRoute;
  const isLegacySessionCurrentRoute = !!routeInvoiceId && !!sessionId && !isVersionSnapshotRoute;
  const canRunWorkflowActions = isInvoiceCurrentRoute;
  const titleText = isVersionSnapshotRoute ? 'Invoice Version Snapshot' : 'Invoice Review - Current Version';
  const bookmarkHelpText = isVersionSnapshotRoute
    ? 'This bookmark shows one fixed invoice version. It will not move when newer fixes are uploaded.'
    : 'This bookmark follows the invoice and always shows the latest uploaded invoice version.';

  // ============================================================
  // SECTION 05.01 - STATE
  // PURPOSE: invoiceIds + readData + pdf viewer state + highlight state
  // ============================================================

  const [showPdf, setShowPdf] = useState<boolean>(true);

  const [invoiceIds, setInvoiceIds] = useState<string[]>([]);
  const [readData, setReadData] = useState<any>(null);
  const [invoiceVersionCount, setInvoiceVersionCount] = useState<number | null>(null);
  const [numPages, setNumPages] = useState<number>(0);

  const [activeHighlightKey, setActiveHighlightKey] = useState<string>('invoice_id');
  const [activePageNumber, setActivePageNumber] = useState<number>(1);

  // We'll render Page at an explicit width (in px) so we can map coords accurately
  const pdfWrapRef = useRef<HTMLDivElement | null>(null);
  const [pageWidthPx, setPageWidthPx] = useState<number>(560); // default fallback
  const [pdfPaneHeightPx, setPdfPaneHeightPx] = useState<number>(700);

  type FitMode = 'width' | 'page';

  const [zoom, setZoom] = useState<number>(1.0); // 1.0 = 100%
  const [fitMode, setFitMode] = useState<FitMode>('width');
  const [rotate, setRotate] = useState<number>(0); // degrees: 0, 90, 180, 270
  const [pageInput, setPageInput] = useState<string>('1');

  const [pdfUrl, setPdfUrl] = useState<string | null>(null);
  const [pdfUrlError, setPdfUrlError] = useState<string | null>(null);

  const [codeFields, setCodeFields] = useState<any[]>([]);

  const { isOpen: isHelpOpen, onOpen: onHelpOpen, onClose: onHelpClose } = useDisclosure();

  // ============================================================
  // SECTION 05.01.01 - ACTIVE HIGHLIGHT (SINGLE SOURCE OF TRUTH)
  // PURPOSE: BOTH header fields and GenAI rows set this (page + polygon)
  // ============================================================

  const [activeHighlight, setActiveHighlight] = useState<{
    source: 'di' | 'genai' | 'code';
    key?: string; // for DI: which field key
    genaiId?: number; // for GenAI: which row id (optional)
    pageNumber: number | null; // 1-based
    polygon: any | null; // DI-style 8-number polygon (or json string)
  } | null>(null);

  // ============================================================
  // SECTION 05.02 - GENAI STATE
  // PURPOSE: Store GenAI located fields (from /read_genai endpoint)
  // ============================================================

  const [genAiFields, setGenAiFields] = useState<any[]>([]);
  const [genAiError, setGenAiError] = useState<string | null>(null);
  const [upgradeTypeResults, setUpgradeTypeResults] = useState<any[]>([]);

  // ============================================================
  // SECTION 05.03 - GENAI RULECHECKS STATE
  // PURPOSE: Store GenAI rulechecks (from /read_genai_rulechecks endpoint)
  // ============================================================

  const [genAiRulechecks, setGenAiRulechecks] = useState<any[]>([]);
  const [genAiRulechecksError, setGenAiRulechecksError] = useState<string | null>(null);

  // ============================================================
  // SECTION 05.04 - LINEITEMS STATE
  // PURPOSE: Store OCR lineitems (from /read response)
  // ============================================================
  const [lineitems, setLineitems] = useState<any[]>([]);
  const [lineitemsError] = useState<string | null>(null);
  const [statusActionLoading, setStatusActionLoading] = useState<InvoiceStatusTransition | null>(null);
  const [statusActionError, setStatusActionError] = useState<string | null>(null);

  // ============================================================
  // SECTION 06.01 - LOAD INVOICE NAV LIST
  // PURPOSE: Fetch ordered invoice_ids for Prev/Next navigation
  // ============================================================

  useEffect(() => {
    const run = async () => {
      if (!sessionId) return;
      const resp = await fetch(`/api/claims/sessions/${sessionId}/current_invoices`, {
        headers: { Accept: 'application/json' },
        credentials: 'include',
      });
      const json = await resp.json();
      setInvoiceIds(json.invoice_ids ?? []);
    };
    run();
  }, [sessionId]);

  // ============================================================
  // SECTION 06.01.02 - LOAD PDF SAS URL (STRICT + DEBUG)
  // PURPOSE: Fetch signed SAS URL for current invoice PDF
  // ============================================================
  useEffect(() => {
    const run = async () => {
      if (!routeInvoiceVersionId && !routeInvoiceId) return;

      try {
        setPdfUrlError(null);

        let pdfEndpoint = '';
        if (routeInvoiceVersionId) {
          pdfEndpoint = `/api/claims/admin/invoice_versions/${encodeURIComponent(routeInvoiceVersionId)}/pdf_url`;
        } else if (isInvoiceCurrentRoute) {
          pdfEndpoint = `/api/claims/admin/invoices/${encodeURIComponent(routeInvoiceId)}/current_version/pdf_url`;
        } else if (isLegacySessionCurrentRoute) {
          pdfEndpoint = `/api/claims/sessions/${sessionId}/invoices/${routeInvoiceId}/pdf_url`;
        }
        if (!pdfEndpoint) return;

        const resp = await fetch(pdfEndpoint, {
          headers: { Accept: 'application/json' },
          credentials: 'include',
        });

        const bodyText = await resp.text();

        if (!resp.ok) {
          setPdfUrl(null);
          setPdfUrlError(`pdf_url failed (${resp.status}): ${bodyText}`);
          return;
        }

        let json: any;
        try {
          json = JSON.parse(bodyText);
        } catch {
          setPdfUrl(null);
          setPdfUrlError(`pdf_url returned non-JSON: ${bodyText}`);
          return;
        }

        const sasUrl = String(json?.sas_url ?? '').trim();
        if (!sasUrl) {
          setPdfUrl(null);
          setPdfUrlError(`pdf_url returned empty sas_url. full response: ${bodyText}`);
          return;
        }

        setPdfUrl(sasUrl);
      } catch (e: any) {
        setPdfUrl(null);
        setPdfUrlError(String(e?.message ?? e));
      }
    };

    run();
  }, [isInvoiceCurrentRoute, isLegacySessionCurrentRoute, routeInvoiceId, routeInvoiceVersionId, sessionId]);

  // ============================================================
  // SECTION 06.02 - LOAD INVOICE READ DATA
  // PURPOSE: Fetch invoice header fields + DI metadata used by viewer/highlights
  // ============================================================

  useEffect(() => {
    const run = async () => {
      if (!routeInvoiceVersionId && !routeInvoiceId) return;

      let readEndpoint = '';
      if (routeInvoiceVersionId) {
        readEndpoint = `/api/claims/admin/invoice_versions/${encodeURIComponent(routeInvoiceVersionId)}/read`;
      } else if (isInvoiceCurrentRoute) {
        readEndpoint = `/api/claims/admin/invoices/${encodeURIComponent(routeInvoiceId)}/current_version/read`;
      } else if (isLegacySessionCurrentRoute) {
        readEndpoint = `/api/claims/sessions/${sessionId}/invoices/${routeInvoiceId}/read`;
      }
      if (!readEndpoint) return;

      const resp = await fetch(readEndpoint, {
        headers: { Accept: 'application/json' },
        credentials: 'include',
      });
      const json = await resp.json();

      const read = json.read ?? null;
      const invoice = json.invoice ?? null;
      const versionCount = Number(json.invoice_version_count);
      setInvoiceVersionCount(Number.isFinite(versionCount) && versionCount > 0 ? versionCount : null);
      setReadData(
        read
          ? {
              ...read,
              invoice_status: read.invoice_status ?? invoice?.status ?? null,
              session_id: read.session_id ?? invoice?.session_id ?? null,
            }
          : null,
      );
      setLineitems(Array.isArray(json.lineitems) ? json.lineitems : []);
    };
    run();
  }, [isInvoiceCurrentRoute, isLegacySessionCurrentRoute, routeInvoiceId, routeInvoiceVersionId, sessionId]);

  // ============================================================
  // SECTION 06.02.01 - LOAD GENAI LOCATED FIELDS (+ optional rulechecks)
  // PURPOSE: Fetch GenAI located fields for the current invoice_version
  // ============================================================

  useEffect(() => {
    const run = async () => {
      if (!routeInvoiceVersionId && !routeInvoiceId) return;

      try {
        setGenAiError(null);

        let genaiEndpoint = '';
        if (routeInvoiceVersionId) {
          genaiEndpoint = `/api/claims/admin/invoice_versions/${encodeURIComponent(routeInvoiceVersionId)}/read_genai`;
        } else if (isInvoiceCurrentRoute) {
          genaiEndpoint = `/api/claims/admin/invoices/${encodeURIComponent(routeInvoiceId)}/current_version/read_genai`;
        } else if (isLegacySessionCurrentRoute) {
          genaiEndpoint = `/api/claims/sessions/${sessionId}/invoices/${routeInvoiceId}/read_genai`;
        }
        if (!genaiEndpoint) return;

        const resp = await fetch(genaiEndpoint, {
          headers: { Accept: 'application/json' },
          credentials: 'include',
        });

        if (!resp.ok) {
          const txt = await resp.text();
          setGenAiFields([]);
          setUpgradeTypeResults([]);
          setGenAiError(`read_genai failed (${resp.status}): ${txt}`);
          return;
        }

        const json = await resp.json();

        // ============================================================
        // SECTION 06.02.01.01 - LOCATED FIELDS
        // ============================================================
        setGenAiFields(Array.isArray(json?.located_fields) ? json.located_fields : []);
        setCodeFields(Array.isArray(json?.code_located_fields) ? json.code_located_fields : []);
        setUpgradeTypeResults(Array.isArray(json?.upgrade_type_results) ? json.upgrade_type_results : []);

        // ============================================================
        // SECTION 06.02.01.10 - RULECHECKS (ONLY IF PRESENT)
        // ============================================================
        if ('rulechecks' in (json ?? {})) {
          setGenAiRulechecks([
            ...(Array.isArray(json?.code_rulechecks) ? json.code_rulechecks : []),
            ...(Array.isArray(json?.rulechecks) ? json.rulechecks : []),
          ]);
          setGenAiRulechecksError(null);
        }
      } catch (e: any) {
        setGenAiFields([]);
        setUpgradeTypeResults([]);
        setGenAiError(`read_genai error: ${String(e?.message ?? e)}`);
      }
    };

    run();
  }, [isInvoiceCurrentRoute, isLegacySessionCurrentRoute, routeInvoiceId, routeInvoiceVersionId, sessionId]);

  // ============================================================
  // SECTION 06.03 - URL SANITY / AUTO-REDIRECT
  // PURPOSE: If invoiceId missing/invalid, redirect to first invoice in session
  // ============================================================

  useEffect(() => {
    if (!sessionId) return;
    if (invoiceIds.length === 0) return;

    // If URL has no invoiceId OR it's not one of the session's current invoices,
    // jump to the first real invoiceId.
    if (!invoiceId || !invoiceIds.includes(invoiceId)) {
      navigate(`/sessions/${sessionId}/invoices/${invoiceIds[0]}/read`, { replace: true });
    }
  }, [sessionId, invoiceId, invoiceIds, navigate]);

  // ============================================================
  // SECTION 06.04 - PDF PANE SIZE OBSERVER
  // PURPOSE: Measure PDF container width/height so fit/zoom math stays correct
  // ============================================================
  useEffect(() => {
    // If PDF is hidden, do nothing (and importantly: detach any prior observer).
    if (!showPdf) return;

    const el = pdfWrapRef.current;
    if (!el) return;

    const MAX_PDF_WIDTH = 560;

    const ro = new ResizeObserver(() => {
      // Ignore "collapse to 0" measurements during hide/unmount transitions
      if (el.clientWidth <= 0 || el.clientHeight <= 0) return;

      const w = Math.max(300, Math.floor(el.clientWidth));
      const h = Math.max(300, Math.floor(el.clientHeight));
      setPageWidthPx(Math.min(w, MAX_PDF_WIDTH));
      setPdfPaneHeightPx(h);
    });

    ro.observe(el);

    // Also do one immediate measurement right after attach
    if (el.clientWidth > 0 && el.clientHeight > 0) {
      const w = Math.max(300, Math.floor(el.clientWidth));
      const h = Math.max(300, Math.floor(el.clientHeight));
      setPageWidthPx(Math.min(w, MAX_PDF_WIDTH));
      setPdfPaneHeightPx(h);
    }

    return () => ro.disconnect();
  }, [showPdf]);

  const openRevisionMessages = () => {
    const params = new URLSearchParams();
    const invoiceRecordId = String(readData?.invoice_id || invoiceId || '').trim();
    if (!invoiceRecordId) {
      setStatusActionError('Could not determine invoice_id for messages.');
      return;
    }

    params.set('invoice_id', invoiceRecordId);
    if (sessionId || readData?.session_id) params.set('context_session_id', String(sessionId || readData.session_id));
    if (readData?.session_created_at) params.set('context_session_created_at', String(readData.session_created_at));
    if (readData?.invoice_status) params.set('context_invoice_status', String(readData.invoice_status));
    if (readData?.contractor_business_name)
      params.set('context_contractor_business_name', String(readData.contractor_business_name));
    if (readData?.di_ocr_invoice_id) params.set('context_di_ocr_invoice_id', String(readData.di_ocr_invoice_id));
    if (readData?.id) params.set('latest_invoice_version_id', String(readData.id));
    if (readData?.invoice_versionno !== null && readData?.invoice_versionno !== undefined) {
      params.set('latest_invoice_versionno', String(readData.invoice_versionno));
    }
    window.open(`/revision-requests-admin?${params.toString()}`, '_blank', 'noopener,noreferrer');
  };

  const runStatusTransition = async (transition: InvoiceStatusTransition) => {
    if (!canRunWorkflowActions) return;

    const invoiceRecordId = String(readData?.invoice_id || invoiceId || '').trim();
    const action = INVOICE_STATUS_ACTIONS.find((candidate) => candidate.key === transition);
    if (!invoiceRecordId || !action) return;

    const currentStatus = String(readData?.invoice_status || '').trim();
    if (!action.validFrom.includes(currentStatus)) {
      setStatusActionError(`${action.label} is not valid while this invoice is ${invoiceStatusLabel(currentStatus)}.`);
      return;
    }

    const revisionReminder =
      transition === 'request_revision'
        ? '\n\nReminder: this status move sends the invoice back to the contractor workflow, but the message itself is a separate revision request step. Use the revision request record to tell the contractor what needs to change or what supporting information is needed.'
        : '';
    const confirmed = window.confirm(
      `${action.label}?\n\nCurrent status: ${invoiceStatusLabel(currentStatus)}\nNew status: ${invoiceStatusLabel(
        action.targetStatus,
      )}${revisionReminder}`,
    );
    if (!confirmed) return;

    setStatusActionError(null);
    setStatusActionLoading(transition);
    try {
      const resp = await fetch(`/api/claims/admin/invoices/${encodeURIComponent(invoiceRecordId)}/status_transition`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
        credentials: 'include',
        body: JSON.stringify({ transition }),
      });
      const data = await resp.json().catch(() => ({}));
      if (!resp.ok) throw new Error(data?.error || data?.message || `Status update failed (${resp.status}).`);

      const nextStatus = String(data?.status || data?.invoice?.status || action.targetStatus);
      setReadData((prev: any) =>
        prev
          ? {
              ...prev,
              invoice_status: nextStatus,
            }
          : prev,
      );

      toast({
        title: 'Invoice status updated',
        description: `${invoiceStatusLabel(currentStatus)} -> ${invoiceStatusLabel(nextStatus)}`,
        status: 'success',
        duration: 4000,
        isClosable: true,
      });

      if (transition === 'request_revision') {
        openRevisionMessages();
      }
    } catch (e: any) {
      const message = e?.message || 'Failed to update invoice status.';
      setStatusActionError(message);
      toast({
        title: 'Status update failed',
        description: message,
        status: 'error',
        duration: 6000,
        isClosable: true,
      });
    } finally {
      setStatusActionLoading(null);
    }
  };

  // ============================================================
  // SECTION 06.06 - ACTIVE HIGHLIGHT RESOLVER
  // PURPOSE: Lookup active field config > (pageNumber + polygon)
  // ============================================================

  const activeField = useMemo(() => {
    return DI_FIELDS.find((f) => f.key === activeHighlightKey) ?? null;
  }, [activeHighlightKey]);

  // ============================================================
  // SECTION 06.06.01 - DEFAULT ACTIVE HIGHLIGHT (DI)
  // PURPOSE: When DI field changes, set the *state* activeHighlight
  // ============================================================

  useEffect(() => {
    if (!readData || !activeField) return;
    if (!activeField.pageKey || !activeField.polygonKey) return;

    setActiveHighlight({
      source: 'di',
      key: activeField.key,
      pageNumber: readData[activeField.pageKey],
      polygon: readData[activeField.polygonKey],
    });
  }, [readData, activeField]);

  // ============================================================
  // SECTION 06.07 - SYNC ACTIVE PAGE TO HIGHLIGHT
  // PURPOSE: When active highlight changes, jump PDF to that page
  // ============================================================

  useEffect(() => {
    const p = activeHighlight?.pageNumber;
    if (typeof p === 'number' && p >= 1) setActivePageNumber(p);
  }, [activeHighlight?.pageNumber]);

  const activePageMeta = useMemo(() => {
    const pages = readData?.di_page_map;
    const pnum = activeHighlight?.pageNumber;
    if (!pages || !pnum) return null;

    // Your JSON uses "pageNumber", "width", "height", "unit"
    const found = pages.find((p: any) => Number(p.pageNumber) === Number(pnum));
    if (!found) return null;

    return {
      width: Number(found.width),
      height: Number(found.height),
      unit: String(found.unit || ''),
    };
  }, [readData?.di_page_map, activeHighlight?.pageNumber]);

  // ============================================================
  // SECTION 06.07.01 - PDF RENDER GEOMETRY aka the renderWidthPx block
  // PURPOSE: Compute render width/height for zoom + fit modes
  // ============================================================
  const renderWidthPx = useMemo(() => {
    if (!activePageMeta) return Math.floor(pageWidthPx * zoom);

    if (fitMode === 'width') {
      return Math.floor(pageWidthPx * zoom);
    }

    // fitMode === "page": choose width based on available height
    // width = height * (pageAspectWidth/pageAspectHeight)
    const widthByHeight = pdfPaneHeightPx * (activePageMeta.width / activePageMeta.height);
    return Math.floor(Math.min(pageWidthPx, widthByHeight) * zoom);
  }, [activePageMeta, fitMode, pageWidthPx, pdfPaneHeightPx, zoom]);

  // ============================================================
  // SECTION 06.07.02 - SVG POLYGON (INCHES > PIXELS)
  // PURPOSE: Convert DI polygon coords (inches) into SVG points that
  //          match the *current rendered PDF width* (overlayWidthPx),
  //          so zoom/fit keeps the red highlight aligned.
  // ============================================================

  const svgPolygonPoints = useMemo(() => {
    const poly = activeHighlight?.polygon;
    const meta = activePageMeta;

    if (!poly || !meta) return null;
    if (meta.unit !== 'inch') {
      // You can expand later to handle 'pixel' for images.
      console.warn('Unexpected DI unit:', meta.unit);
      return null;
    }

    let parsedPoly: any = poly;
    if (typeof poly === 'string') {
      try {
        parsedPoly = JSON.parse(poly);
      } catch {
        return null;
      }
    }

    const arr = Array.isArray(parsedPoly)
      ? parsedPoly.flatMap((point: any) => (Array.isArray(point) ? point : [point]))
      : null;
    if (!arr || (arr.length !== 4 && arr.length !== 8)) return null;

    const coords = arr.map((n: any) => Number(n));
    if (coords.some((n: number) => !Number.isFinite(n))) return null;

    const [x1, y1, x2, y2, x3, y3, x4, y4] =
      coords.length === 4
        ? [coords[0], coords[1], coords[2], coords[1], coords[2], coords[3], coords[0], coords[3]]
        : coords;

    // ------------------------------------------------------------
    // SCALE CONVERSION (SOURCE OF TRUTH = overlayWidthPx)
    // If you use pageWidthPx here, zoom will break alignment.
    // ------------------------------------------------------------

    //const xToPx = (xIn: number) => (xIn / meta.width) * pageWidthPx;
    //const yToPx = (yIn: number) => (yIn / meta.height) * (pageWidthPx * (meta.height / meta.width));

    const xToPx = (xIn: number) => (xIn / meta.width) * renderWidthPx;
    const yToPx = (yIn: number) => (yIn / meta.height) * (renderWidthPx * (meta.height / meta.width));

    // NOTE: this assumes page aspect ratio equals DI width/height.
    // We'll compute overlay height from this same ratio.

    const pts = [
      [xToPx(x1), yToPx(y1)],
      [xToPx(x2), yToPx(y2)],
      [xToPx(x3), yToPx(y3)],
      [xToPx(x4), yToPx(y4)],
    ];

    return pts.map(([x, y]) => `${x.toFixed(2)},${y.toFixed(2)}`).join(' ');
  }, [activeHighlight?.polygon, activePageMeta, renderWidthPx]);

  // ============================================================
  // SECTION 06.07.03 - OVERLAY HEIGHT SOURCE OF TRUTH
  // PURPOSE: Compute overlay height to match rendered PDF height
  // ============================================================

  const overlayHeightPx = useMemo(() => {
    if (!activePageMeta) return 1200;
    return renderWidthPx * (activePageMeta.height / activePageMeta.width);
  }, [activePageMeta, renderWidthPx]);

  // ============================================================
  // SECTION 06.07.10 - SYNC PAGE INPUT TO ACTIVE PAGE
  // PURPOSE: Keep the page textbox updated when page changes via
  //          highlights, Prev/Next, or manual nav
  // ============================================================
  useEffect(() => {
    setPageInput(String(activePageNumber));
  }, [activePageNumber]);

  // ------------------------------------------------------------
  // SECTION 06.08.01 - OVERLAY WIDTH SOURCE OF TRUTH
  // PURPOSE: Keep SVG overlay width locked to the rendered PDF width
  // ------------------------------------------------------------

  const overlayWidthPx = renderWidthPx;

  const upgradeTypeGroups = useMemo(() => {
    const groups = new Map<
      string,
      {
        description: string;
        fields: any[];
        results: any[];
        rulechecks: any[];
        upgradeTypeKey: string;
      }
    >();

    const ensureGroup = (row: any) => {
      const upgradeTypeKey = upgradeTypeKeyFor(row);
      const existing = groups.get(upgradeTypeKey);
      if (existing) return existing;

      const group = {
        description: upgradeTypeDescriptionFor(row),
        fields: [],
        results: [],
        rulechecks: [],
        upgradeTypeKey,
      };
      groups.set(upgradeTypeKey, group);
      return group;
    };

    genAiFields.forEach((row) => ensureGroup(row).fields.push(row));
    upgradeTypeResults.forEach((row) => ensureGroup(row).results.push(row));
    genAiRulechecks.forEach((row) => ensureGroup(row).rulechecks.push(row));

    return Array.from(groups.values()).sort((a, b) => {
      const sortA = upgradeTypeSortValue(a.upgradeTypeKey);
      const sortB = upgradeTypeSortValue(b.upgradeTypeKey);
      if (sortA !== sortB) return sortA - sortB;
      return a.description.localeCompare(b.description);
    });
  }, [genAiFields, genAiRulechecks, upgradeTypeResults]);

  const sortedLineitems = useMemo(
    () =>
      [...lineitems].sort((a: any, b: any) => {
        const seqA = Number(a.lineitem_seqno ?? a.seqno ?? 0);
        const seqB = Number(b.lineitem_seqno ?? b.seqno ?? 0);
        return seqA - seqB;
      }),
    [lineitems],
  );

  const currentInvoiceStatus = String(readData?.invoice_status || '').trim();
  const invoiceVersionNo = Number(readData?.invoice_versionno);
  const invoiceVersionLabel = Number.isFinite(invoiceVersionNo)
    ? invoiceVersionCount
      ? `Version ${invoiceVersionNo} of ${invoiceVersionCount}`
      : `Version ${invoiceVersionNo}`
    : null;
  const ahriProductMatch = readData?.ahri_product_match;
  const ahriProduct = ahriProductMatch?.product;
  const ahriSource = ahriProductMatch?.source;
  const neeaProductMatch = readData?.neea_product_match;
  const neeaProduct = neeaProductMatch?.product;
  const neeaSource = neeaProductMatch?.source;
  const awhpProductMatch = readData?.awhp_product_match;
  const awhpProduct = awhpProductMatch?.product;
  const awhpSource = awhpProductMatch?.source;
  const supportingDocumentTypeGroups = Array.isArray(readData?.supporting_document_types_by_upgrade_type)
    ? readData.supporting_document_types_by_upgrade_type
    : [];
  const uploadedSupportingDocuments = Array.isArray(readData?.uploaded_supporting_documents)
    ? readData.uploaded_supporting_documents
    : [];
  const canOpenRevisionMessages = canRunWorkflowActions && !!readData?.invoice_id;

  // ============================================================
  // SECTION 07.01 - MAIN RETURN
  // PURPOSE: JSX layout tree (header + nav + split panes)
  // ============================================================

  return (
    <Flex as="main" direction="column" w="full" bg="greys.white" pb="24" minH="100vh">
      <ThinBlueTitleBar title={titleText} />
      <Container maxW="full" px={6} pb={4} flex="1" pt={6}>
        <Box display="flex" flexDirection="column" height="100%">
          {/* keep your existing content, but REMOVE your old <Heading ...>Admin Full Details</Heading>
            (BlueTitleBar replaces it) */}
          {/* ============================================================
        SECTION 07.02 - PAGE LAYOUT
        PURPOSE: Outer column layout: title, nav bar, main split view
        ============================================================ */}
          <Box display="flex" flexDirection="column" height="100%">
            {/* ============================================================
        SECTION 07.03 - NAV BAR
        PURPOSE: Prev/Next invoice navigation + position indicator
        ============================================================ */}
            <Box display="flex" alignItems="center" gap="8px" mb="12px" flexWrap="wrap">
              <Text fontSize="xs" opacity={0.75} flexBasis="100%">
                {bookmarkHelpText}
              </Text>
              <Badge colorScheme="gray">Status: {invoiceStatusLabel(currentInvoiceStatus)}</Badge>
              {invoiceVersionLabel && <Badge colorScheme="teal">{invoiceVersionLabel}</Badge>}
              {isVersionSnapshotRoute && <Badge colorScheme="purple">Fixed version bookmark</Badge>}
              {!isVersionSnapshotRoute && <Badge colorScheme="blue">Latest version bookmark</Badge>}
              <Button size="xs" variant="outline" onClick={() => setShowPdf((v) => !v)}>
                {showPdf ? 'Hide PDF' : 'Show PDF'}
              </Button>

              {canRunWorkflowActions ? (
                INVOICE_STATUS_ACTIONS.map((action) => {
                  const isValidNow = action.validFrom.includes(currentInvoiceStatus);
                  const disabledReason = ' This action is not available for this invoice status.';
                  return (
                    <Tooltip key={action.key} label={`${action.tooltip} ${isValidNow ? '' : disabledReason}`} hasArrow>
                      <Button
                        size="xs"
                        colorScheme={action.colorScheme}
                        variant={isValidNow ? 'solid' : 'outline'}
                        onClick={() => runStatusTransition(action.key)}
                        isDisabled={!isValidNow || !!statusActionLoading || !readData?.invoice_id}
                        isLoading={statusActionLoading === action.key}
                      >
                        {action.label}
                      </Button>
                    </Tooltip>
                  );
                })
              ) : (
                <Tooltip label="Workflow buttons are hidden because this bookmark is for a fixed historical invoice version. Open the invoice-level review bookmark to act on the latest version.">
                  <Badge colorScheme="gray">Workflow actions hidden</Badge>
                </Tooltip>
              )}

              <Tooltip
                label={
                  canOpenRevisionMessages
                    ? 'Open the admin/contractor message thread. Sending a new admin message is available from admin_review_inbox or in_review.'
                    : isVersionSnapshotRoute
                      ? 'Revision actions are disabled for fixed invoice-version snapshots. Open the invoice-level current review bookmark to act on the latest version.'
                      : 'Messages are only available on the invoice-level current review bookmark.'
                }
              >
                <Button
                  size="xs"
                  variant="outline"
                  onClick={openRevisionMessages}
                  isDisabled={!canOpenRevisionMessages}
                >
                  Messages & Requested Changes
                </Button>
              </Tooltip>

              <Box ml="auto">
                <Tooltip label="Help: how this viewer is grouped and what each section means">
                  <IconButton
                    aria-label="Open PDF viewer help"
                    icon={<Question size={18} />}
                    size="sm"
                    variant="outline"
                    onClick={onHelpOpen}
                  />
                </Tooltip>
              </Box>
            </Box>
            {statusActionError && (
              <Box mb="8px">
                <Text fontSize="xs" color="red.700">
                  {statusActionError}
                </Text>
              </Box>
            )}
            {/* ============================================================
        SECTION 07.04 - MAIN SPLIT VIEW
        PURPOSE: Left fields + Right PDF viewer
        ============================================================ */}
            <Box display="flex" gap="16px" flex="1" minH={0}>
              {/* ============================================================
    SECTION 07.05 - LEFT PANEL (ACCORDION WRAPPER)
    PURPOSE: Put header fields inside a collapsible accordion
    ============================================================ */}

              <Box
                borderWidth="1px"
                borderRadius="md"
                p="12px"
                // IMPORTANT: overflow must NOT be "visible" for resize to show
                sx={{
                  resize: 'horizontal',
                  overflow: 'auto',
                }}
                minW="480px"
                maxW="100%"
                w={showPdf ? 'auto' : '100%'}
                flex="1 1 auto"
              >
                {/* ============================================================
      SECTION 07.05.01 - FIELDS ACCORDION
      PURPOSE: Collapsible container for the DI header fields list
      NOTES:
      ? allowToggle lets user collapse the open section
      ? defaultIndex={[0]} keeps it open by default
      ============================================================ */}

                <Accordion allowMultiple defaultIndex={[0]}>
                  {/* ============================================================
      SECTION 07.05.10 - ACCORDION ITEM: INVOICE HEADER FIELDS
      PURPOSE: Existing DI header FieldRows (clickable for polygon)
      ============================================================ */}
                  <AccordionItem border="none">
                    <h2>
                      <AccordionButton px="0" py="6px" _hover={{ bg: 'transparent' }}>
                        <Box flex="1" textAlign="left">
                          <Text size="sm" fontWeight="bold">
                            Invoice
                          </Text>
                        </Box>
                        <AccordionIcon />
                      </AccordionButton>
                    </h2>

                    <AccordionPanel px="0" pt="8px">
                      <Box display="grid" gridTemplateColumns="1fr 1fr" gap="8px">
                        {DI_FIELDS.map((f) => {
                          const raw = readData?.[f.valueKey];
                          const display = f.formatter ? f.formatter(raw) : String(raw ?? '-');
                          const clickable = !f.disabled && !!f.pageKey && !!f.polygonKey;

                          return (
                            <FieldRow
                              key={f.key}
                              label={f.label}
                              value={display}
                              active={activeHighlightKey === f.key}
                              disabled={!clickable}
                              onClick={clickable ? () => setActiveHighlightKey(f.key) : undefined}
                            />
                          );
                        })}
                      </Box>
                    </AccordionPanel>
                  </AccordionItem>

                  <AccordionItem borderTopWidth="1px" borderColor="gray.200">
                    <h2>
                      <AccordionButton px="0" py="6px" _hover={{ bg: 'transparent' }}>
                        <Box flex="1" textAlign="left">
                          <Text size="sm" fontWeight="bold">
                            Line items
                          </Text>
                          <Text fontSize="xs" opacity={0.65}>
                            OCR line rows from the invoice, with classifier-assigned likely upgrade type.
                          </Text>
                        </Box>
                        <AccordionIcon />
                      </AccordionButton>
                    </h2>

                    <AccordionPanel px="0" pt="8px">
                      {lineitemsError && (
                        <Text fontSize="xs" color="red.500" mb="8px">
                          {lineitemsError}
                        </Text>
                      )}

                      {!lineitemsError && sortedLineitems.length === 0 ? (
                        <Text fontSize="sm" opacity={0.7}>
                          No line items found.
                        </Text>
                      ) : (
                        <Box display="flex" flexDirection="column" gap="10px">
                          {sortedLineitems.map((li: any) => {
                            const seq = li.lineitem_seqno ?? li.seqno ?? '-';
                            const lineitemKey = li.id ?? seq;
                            const upgradeTypeKey = li.upgrade_type_key || 'common';
                            const meta = getInvoiceUpgradeTypeMeta(upgradeTypeKey, li.upgrade_type_description);
                            const rows = [
                              {
                                subKey: 'desc',
                                label: 'Description',
                                value: li.ocr_description ?? '-',
                                page: li.ocr_description_page,
                                polygon: li.ocr_description_polygon,
                              },
                              {
                                subKey: 'qty',
                                label: 'Quantity',
                                value: li.ocr_quantity != null ? String(li.ocr_quantity) : '-',
                                page: li.ocr_quantity_page,
                                polygon: li.ocr_quantity_polygon,
                              },
                              {
                                subKey: 'unit',
                                label: 'Unit price',
                                value: li.ocr_unit_price != null ? fmtMoney(li.ocr_unit_price) : '-',
                                page: li.ocr_unit_price_page,
                                polygon: li.ocr_unit_price_polygon,
                              },
                              {
                                subKey: 'amt',
                                label: 'Amount',
                                value: li.ocr_amount != null ? fmtMoney(li.ocr_amount) : '-',
                                page: li.ocr_amount_page,
                                polygon: li.ocr_amount_polygon,
                              },
                            ];

                            return (
                              <Box
                                key={String(lineitemKey)}
                                borderWidth="1px"
                                borderColor="gray.200"
                                borderRadius="md"
                                bg="white"
                                p="10px"
                              >
                                <Flex align="center" gap="8px" mb="8px" wrap="wrap">
                                  <InvoiceUpgradeTypeTile
                                    upgradeTypeKey={upgradeTypeKey}
                                    description={li.upgrade_type_description}
                                    size={28}
                                  />
                                  <Text fontSize="sm" fontWeight="bold">
                                    Line {seq}
                                  </Text>
                                  <Badge colorScheme="orange" variant="subtle" textTransform="none">
                                    Likely upgrade type: {meta.label}
                                  </Badge>
                                  <Badge colorScheme="gray" variant="subtle" textTransform="none">
                                    classifier guess
                                  </Badge>
                                </Flex>
                                <Text fontSize="xs" opacity={0.65} mb="8px">
                                  This grouping is a classifier hint only. Verify it if the upgrade type affects the
                                  rule outcome.
                                </Text>
                                <Box display="grid" gridTemplateColumns="1fr 1fr" gap="8px">
                                  {rows.map((row) => {
                                    const clickable = row.page != null && row.polygon != null;
                                    const highlightKey = `lineitem_${lineitemKey}_${row.subKey}`;

                                    return (
                                      <FieldRow
                                        key={`${lineitemKey}-${row.subKey}`}
                                        label={row.label}
                                        value={row.value}
                                        active={activeHighlightKey === highlightKey}
                                        disabled={!clickable}
                                        onClick={
                                          clickable
                                            ? () => {
                                                setActiveHighlight({
                                                  source: 'di',
                                                  key: highlightKey,
                                                  pageNumber: Number(row.page),
                                                  polygon: row.polygon,
                                                });
                                                setActiveHighlightKey(highlightKey);
                                              }
                                            : undefined
                                        }
                                      />
                                    );
                                  })}
                                </Box>
                              </Box>
                            );
                          })}
                        </Box>
                      )}
                    </AccordionPanel>
                  </AccordionItem>

                  <AccordionItem borderTopWidth="1px" borderColor="gray.200">
                    <h2>
                      <AccordionButton px="0" py="6px" _hover={{ bg: 'transparent' }}>
                        <Box flex="1" textAlign="left">
                          <Text size="sm" fontWeight="bold">
                            Supplement docs
                          </Text>
                          <Text fontSize="xs" opacity={0.65}>
                            Configured supplement types for the detected upgrade types, plus the actual uploaded
                            supporting documents attached to this invoice.
                          </Text>
                        </Box>
                        <AccordionIcon />
                      </AccordionButton>
                    </h2>

                    <AccordionPanel px="0" pt="8px">
                      <Box display="flex" flexDirection="column" gap="12px">
                        <Box>
                          <Text fontSize="xs" fontWeight="bold" textTransform="uppercase" opacity={0.7} mb="6px">
                            Possible document types for this invoice&apos;s upgrade types
                          </Text>
                          {supportingDocumentTypeGroups.length === 0 ? (
                            <Text fontSize="sm" opacity={0.7}>
                              No supplement-type mappings are configured for the detected upgrade types.
                            </Text>
                          ) : (
                            <Box display="flex" flexDirection="column" gap="10px">
                              {supportingDocumentTypeGroups.map((group: any) => {
                                const types = Array.isArray(group?.supporting_document_types)
                                  ? group.supporting_document_types
                                  : [];

                                return (
                                  <Box
                                    key={String(group?.invoice_upgrade_type_id || group?.upgrade_type_key || 'group')}
                                    borderWidth="1px"
                                    borderColor="gray.200"
                                    borderRadius="md"
                                    bg="white"
                                    p="10px"
                                  >
                                    <Flex align="center" gap="8px" mb="8px" wrap="wrap">
                                      <InvoiceUpgradeTypeTile
                                        upgradeTypeKey={String(group?.upgrade_type_key || 'common')}
                                        description={group?.upgrade_type_description}
                                        size={28}
                                      />
                                      <Text fontSize="sm" fontWeight="bold">
                                        {String(
                                          group?.upgrade_type_description ||
                                            getInvoiceUpgradeTypeMeta(String(group?.upgrade_type_key || 'common'))
                                              .label,
                                        )}
                                      </Text>
                                      <Badge colorScheme="gray" variant="subtle">
                                        {types.length} configured
                                      </Badge>
                                    </Flex>

                                    {types.length === 0 ? (
                                      <Text fontSize="sm" opacity={0.7}>
                                        No supplement document types mapped to this upgrade type.
                                      </Text>
                                    ) : (
                                      <Flex gap="6px" wrap="wrap">
                                        {types.map((typeRow: any) => (
                                          <Badge
                                            key={String(
                                              typeRow?.supporting_document_type_id || typeRow?.type_key || 'type',
                                            )}
                                            colorScheme="purple"
                                            variant="subtle"
                                            textTransform="none"
                                          >
                                            {String(typeRow?.description || typeRow?.type_key || 'Unknown type')}
                                          </Badge>
                                        ))}
                                      </Flex>
                                    )}
                                  </Box>
                                );
                              })}
                            </Box>
                          )}
                        </Box>

                        <Box>
                          <Text fontSize="xs" fontWeight="bold" textTransform="uppercase" opacity={0.7} mb="6px">
                            Uploaded supporting documents
                          </Text>
                          {uploadedSupportingDocuments.length === 0 ? (
                            <Text fontSize="sm" opacity={0.7}>
                              No supporting documents uploaded for this invoice.
                            </Text>
                          ) : (
                            <Box display="flex" flexDirection="column" gap="10px">
                              {uploadedSupportingDocuments.map((doc: any) => (
                                <Box
                                  key={String(doc?.id || doc?.storage_key || 'supporting-doc')}
                                  borderWidth="1px"
                                  borderColor="gray.200"
                                  borderRadius="md"
                                  bg="white"
                                  p="10px"
                                >
                                  <Flex align="center" gap="8px" mb="6px" wrap="wrap">
                                    <Badge colorScheme="blue" variant="subtle" textTransform="none">
                                      {String(
                                        doc?.supporting_document_type_description ||
                                          doc?.supporting_document_type_key ||
                                          doc?.content_type ||
                                          'Unclassified document',
                                      )}
                                    </Badge>
                                    <Badge colorScheme={doc?.classification_status === 'classified' ? 'green' : 'gray'}>
                                      {String(doc?.classification_status || 'pending')}
                                    </Badge>
                                    {doc?.classification_confidence != null && (
                                      <Text fontSize="xs" opacity={0.75}>
                                        confidence: {String(doc.classification_confidence)}
                                      </Text>
                                    )}
                                  </Flex>

                                  <Text fontSize="sm" fontWeight="bold" mb="2px">
                                    {String(doc?.original_filename || 'Unnamed file')}
                                  </Text>

                                  <Text fontSize="xs" opacity={0.7}>
                                    Uploaded {fmtDate(doc?.created_at)} • size {fmtBytes(doc?.byte_size)}
                                  </Text>

                                  {String(doc?.classification_reason || '').trim() && (
                                    <Text fontSize="xs" opacity={0.8} mt="4px">
                                      {String(doc.classification_reason)}
                                    </Text>
                                  )}

                                  {String(doc?.supplement_routing_quality || '').trim() && (
                                    <Box mt="6px">
                                      <Badge colorScheme="teal" variant="subtle" textTransform="none">
                                        routing: {String(doc.supplement_routing_quality)}
                                      </Badge>
                                      {String(doc?.supplement_routing_quality_reason || '').trim() && (
                                        <Text fontSize="xs" opacity={0.8} mt="4px">
                                          {String(doc.supplement_routing_quality_reason)}
                                        </Text>
                                      )}
                                    </Box>
                                  )}

                                  {Array.isArray(doc?.located_fields) && doc.located_fields.length > 0 && (
                                    <Box mt="8px" display="flex" flexDirection="column" gap="4px">
                                      {doc.located_fields.map((field: any) => (
                                        <Flex
                                          key={String(field?.id || field?.field_key)}
                                          gap="8px"
                                          align="baseline"
                                          wrap="wrap"
                                          fontSize="xs"
                                        >
                                          <Text fontWeight="bold">{String(field?.field_key || 'field')}</Text>
                                          <Text opacity={0.8}>
                                            {field?.value_text != null
                                              ? String(field.value_text)
                                              : field?.value_json != null
                                                ? JSON.stringify(field.value_json)
                                                : 'not found'}
                                          </Text>
                                          <Text opacity={0.6}>confidence: {String(field?.confidence ?? 0)}</Text>
                                        </Flex>
                                      ))}
                                    </Box>
                                  )}
                                </Box>
                              ))}
                            </Box>
                          )}
                        </Box>
                      </Box>
                    </AccordionPanel>
                  </AccordionItem>

                  <AccordionItem borderTopWidth="1px" borderColor="gray.200">
                    <h2>
                      <AccordionButton px="0" py="6px" _hover={{ bg: 'transparent' }}>
                        <Box flex="1" textAlign="left">
                          <Text size="sm" fontWeight="bold">
                            Overall advice
                          </Text>
                          <Text fontSize="xs" opacity={0.65}>
                            Combined GenAI admin advice for this invoice version.
                          </Text>
                        </Box>
                        <AccordionIcon />
                      </AccordionButton>
                    </h2>

                    <AccordionPanel px="0" pt="8px">
                      <Box borderWidth="1px" borderColor="gray.200" borderRadius="md" p="10px" bg="gray.50">
                        <Flex align="center" gap="8px" mb="6px" wrap="wrap">
                          <StatusDot result={readData?.genai_result} />
                          <Badge colorScheme={resultColorScheme(readData?.genai_result)}>
                            {resultLabel(readData?.genai_result)}
                          </Badge>
                          <Text fontSize="xs" opacity={0.75}>
                            confidence: {readData?.genai_overall_confidence ?? '-'}
                          </Text>
                        </Flex>
                        <Text fontSize="sm" whiteSpace="pre-wrap">
                          {readData?.genai_admin_advice || 'No overall advice found for this invoice version.'}
                        </Text>
                      </Box>
                    </AccordionPanel>
                  </AccordionItem>

                  {ahriProduct && (
                    <AccordionItem borderTopWidth="1px" borderColor="gray.200">
                      <h2>
                        <AccordionButton px="0" py="6px" _hover={{ bg: 'transparent' }}>
                          <Box flex="1" textAlign="left">
                            <Text size="sm" fontWeight="bold">
                              AHRI product-list match
                            </Text>
                            <Text fontSize="xs" opacity={0.65}>
                              Code-owned match to the imported BC Hydro heat-pump product list.
                            </Text>
                          </Box>
                          <AccordionIcon />
                        </AccordionButton>
                      </h2>

                      <AccordionPanel px="0" pt="8px">
                        <Box borderWidth="1px" borderColor="blue.100" borderRadius="md" p="10px" bg="blue.50">
                          <Flex align="center" gap="8px" mb="8px" wrap="wrap">
                            <StatusDot result="pass" />
                            <Badge colorScheme="blue">Information on record</Badge>
                            {ahriSource?.source_description && (
                              <Badge colorScheme="gray" variant="subtle" textTransform="none">
                                {String(ahriSource.source_description)}
                              </Badge>
                            )}
                            <Text fontSize="xs" opacity={0.75}>
                              AHRI {fmtText(ahriProduct.ahri_reference_number)}
                            </Text>
                          </Flex>

                          <Box display="grid" gridTemplateColumns="1fr 1fr" gap="8px">
                            {[
                              ['Make', ahriProduct.make],
                              ['Outdoor model', ahriProduct.outdoor_model],
                              ['Indoor / air handler', ahriProduct.indoor_model_or_air_handler],
                              ['Furnace model', ahriProduct.furnace_model],
                              ['Heat pump type', ahriProduct.heat_pump_type],
                              ['Rated capacity at -5 C', ahriProduct.rated_capacity_btu_at_minus_5c],
                              ['SEER2', ahriProduct.seer2],
                              ['HSPF2', ahriProduct.hspf2],
                              ['COP', ahriProduct.cop],
                              ['Capacity maintenance %', ahriProduct.capacity_maintenance_percent],
                              [
                                'Cold climate rated',
                                ahriProduct.cold_climate_rated == null
                                  ? null
                                  : ahriProduct.cold_climate_rated
                                    ? 'Yes'
                                    : 'No',
                              ],
                              ['Eligibility notes', ahriProduct.eligibility_notes],
                            ].map(([label, value]) => (
                              <Box
                                key={String(label)}
                                px="10px"
                                py="8px"
                                borderRadius="md"
                                borderWidth="1px"
                                borderColor="blue.100"
                                bg="white"
                              >
                                <Text fontSize="xs" opacity={0.7}>
                                  {String(label)}
                                </Text>
                                <Text fontSize="sm" noOfLines={3}>
                                  {fmtText(value)}
                                </Text>
                              </Box>
                            ))}
                          </Box>

                          <Box mt="10px" pt="8px" borderTopWidth="1px" borderColor="blue.100">
                            <Text fontSize="xs" fontWeight="bold" textTransform="uppercase" opacity={0.7} mb="4px">
                              Source
                            </Text>
                            <Text fontSize="sm">
                              {fmtText(ahriSource?.source_description)}{' '}
                              {ahriSource?.publishing_date ? `(published ${fmtDate(ahriSource.publishing_date)})` : ''}
                            </Text>
                            <Text fontSize="xs" opacity={0.75} wordBreak="break-all">
                              AHRI source id: {fmtText(ahriSource?.ahri_source_id)}
                            </Text>
                            <Text fontSize="xs" opacity={0.75}>
                              Imported {fmtDate(ahriSource?.completed_at)} with {fmtText(ahriSource?.records_imported)}{' '}
                              rows.
                            </Text>
                            {ahriSource?.source_url && (
                              <Text
                                as="a"
                                href={String(ahriSource.source_url)}
                                target="_blank"
                                rel="noreferrer"
                                fontSize="xs"
                                color="blue.700"
                                textDecoration="underline"
                              >
                                Open source list
                              </Text>
                            )}
                          </Box>
                        </Box>
                      </AccordionPanel>
                    </AccordionItem>
                  )}

                  {neeaProduct && (
                    <AccordionItem borderTopWidth="1px" borderColor="gray.200">
                      <h2>
                        <AccordionButton px="0" py="6px" _hover={{ bg: 'transparent' }}>
                          <Box flex="1" textAlign="left">
                            <Text size="sm" fontWeight="bold">
                              NEEA HPWH product-list match
                            </Text>
                            <Text fontSize="xs" opacity={0.65}>
                              Code-owned match to the imported Residential HPWH Qualified Products List.
                            </Text>
                          </Box>
                          <AccordionIcon />
                        </AccordionButton>
                      </h2>

                      <AccordionPanel px="0" pt="8px">
                        <Box borderWidth="1px" borderColor="green.100" borderRadius="md" p="10px" bg="green.50">
                          <Flex align="center" gap="8px" mb="8px" wrap="wrap">
                            <StatusDot result="pass" />
                            <Badge colorScheme="green">Information on record</Badge>
                            {neeaSource?.source_description && (
                              <Badge colorScheme="gray" variant="subtle" textTransform="none">
                                {String(neeaSource.source_description)}
                              </Badge>
                            )}
                            <Text fontSize="xs" opacity={0.75}>
                              {fmtText(neeaProduct.brand)} {fmtText(neeaProduct.model_number)}
                            </Text>
                          </Flex>

                          <Box display="grid" gridTemplateColumns="1fr 1fr" gap="8px">
                            {[
                              ['Brand', neeaProduct.brand],
                              ['Model number', neeaProduct.model_number],
                              ['Storage volume gallons', neeaProduct.storage_volume_gallons],
                              ['Configuration', neeaProduct.configuration],
                              ['Indoor tier', neeaProduct.indoor_tier],
                              ['Indoor CCE', neeaProduct.indoor_cce],
                              ['Outdoor tier', neeaProduct.outdoor_tier],
                              ['Outdoor SCOP', neeaProduct.outdoor_scop],
                              ['Flex-load connectivity', neeaProduct.flex_load_connectivity],
                              [
                                'Plug-in endorsement',
                                neeaProduct.plug_in_endorsement == null
                                  ? null
                                  : neeaProduct.plug_in_endorsement
                                    ? 'Yes'
                                    : 'No',
                              ],
                              [
                                'Qualified date',
                                neeaProduct.qualified_date ? fmtDate(neeaProduct.qualified_date) : null,
                              ],
                              ['Specification version', neeaProduct.specification_version],
                              ['Eligibility notes', neeaProduct.eligibility_notes],
                            ].map(([label, value]) => (
                              <Box
                                key={String(label)}
                                px="10px"
                                py="8px"
                                borderRadius="md"
                                borderWidth="1px"
                                borderColor="green.100"
                                bg="white"
                              >
                                <Text fontSize="xs" opacity={0.7}>
                                  {String(label)}
                                </Text>
                                <Text fontSize="sm" noOfLines={3}>
                                  {fmtText(value)}
                                </Text>
                              </Box>
                            ))}
                          </Box>

                          <Box mt="10px" pt="8px" borderTopWidth="1px" borderColor="green.100">
                            <Text fontSize="xs" fontWeight="bold" textTransform="uppercase" opacity={0.7} mb="4px">
                              Source
                            </Text>
                            <Text fontSize="sm">
                              {fmtText(neeaSource?.source_description)}{' '}
                              {neeaSource?.publishing_date ? `(published ${fmtDate(neeaSource.publishing_date)})` : ''}
                            </Text>
                            <Text fontSize="xs" opacity={0.75} wordBreak="break-all">
                              NEEA source id: {fmtText(neeaSource?.neea_source_id)}
                            </Text>
                            <Text fontSize="xs" opacity={0.75}>
                              Imported {fmtDate(neeaSource?.completed_at)} with {fmtText(neeaSource?.records_imported)}{' '}
                              rows.
                            </Text>
                            {neeaSource?.source_url && (
                              <Text
                                as="a"
                                href={String(neeaSource.source_url)}
                                target="_blank"
                                rel="noreferrer"
                                fontSize="xs"
                                color="green.700"
                                textDecoration="underline"
                              >
                                Open source list
                              </Text>
                            )}
                          </Box>
                        </Box>
                      </AccordionPanel>
                    </AccordionItem>
                  )}

                  {awhpProduct && (
                    <AccordionItem borderTopWidth="1px" borderColor="gray.200">
                      <h2>
                        <AccordionButton px="0" py="6px" _hover={{ bg: 'transparent' }}>
                          <Box flex="1" textAlign="left">
                            <Text size="sm" fontWeight="bold">
                              Air-to-water product-list match
                            </Text>
                            <Text fontSize="xs" opacity={0.65}>
                              Code-owned match to the imported Better Homes BC qualifying product list.
                            </Text>
                          </Box>
                          <AccordionIcon />
                        </AccordionButton>
                      </h2>

                      <AccordionPanel px="0" pt="8px">
                        <Box borderWidth="1px" borderColor="cyan.100" borderRadius="md" p="10px" bg="cyan.50">
                          <Flex align="center" gap="8px" mb="8px" wrap="wrap">
                            <StatusDot result="pass" />
                            <Badge colorScheme="cyan">Information on record</Badge>
                            {awhpSource?.source_description && (
                              <Badge colorScheme="gray" variant="subtle" textTransform="none">
                                {String(awhpSource.source_description)}
                              </Badge>
                            )}
                            <Text fontSize="xs" opacity={0.75}>
                              {fmtText(awhpProduct.brand)} {fmtText(awhpProduct.model_number)}
                            </Text>
                          </Flex>

                          <Box display="grid" gridTemplateColumns="1fr 1fr" gap="8px">
                            {[
                              ['Brand', awhpProduct.brand],
                              ['Model number', awhpProduct.model_number],
                              [
                                'Model components',
                                Array.isArray(awhpProduct.model_components)
                                  ? awhpProduct.model_components.join(' / ')
                                  : awhpProduct.model_components,
                              ],
                              ['System type', awhpProduct.system_type],
                              ['Eligibility notes', awhpProduct.eligibility_notes],
                            ].map(([label, value]) => (
                              <Box
                                key={String(label)}
                                px="10px"
                                py="8px"
                                borderRadius="md"
                                borderWidth="1px"
                                borderColor="cyan.100"
                                bg="white"
                              >
                                <Text fontSize="xs" opacity={0.7}>
                                  {String(label)}
                                </Text>
                                <Text fontSize="sm" noOfLines={3}>
                                  {fmtText(value)}
                                </Text>
                              </Box>
                            ))}
                          </Box>

                          <Box mt="10px" pt="8px" borderTopWidth="1px" borderColor="cyan.100">
                            <Text fontSize="xs" fontWeight="bold" textTransform="uppercase" opacity={0.7} mb="4px">
                              Source
                            </Text>
                            <Text fontSize="sm">
                              {fmtText(awhpSource?.source_description)}{' '}
                              {awhpSource?.publishing_date ? `(published ${fmtDate(awhpSource.publishing_date)})` : ''}
                            </Text>
                            <Text fontSize="xs" opacity={0.75} wordBreak="break-all">
                              AWHP source id: {fmtText(awhpSource?.awhp_source_id)}
                            </Text>
                            <Text fontSize="xs" opacity={0.75}>
                              Imported {fmtDate(awhpSource?.completed_at)} with {fmtText(awhpSource?.records_imported)}{' '}
                              rows.
                            </Text>
                            {awhpSource?.source_url && (
                              <Text
                                as="a"
                                href={String(awhpSource.source_url)}
                                target="_blank"
                                rel="noreferrer"
                                fontSize="xs"
                                color="cyan.700"
                                textDecoration="underline"
                              >
                                Open source list
                              </Text>
                            )}
                          </Box>
                        </Box>
                      </AccordionPanel>
                    </AccordionItem>
                  )}

                  <AccordionItem borderTopWidth="1px" borderColor="gray.200">
                    <h2>
                      <AccordionButton px="0" py="6px" _hover={{ bg: 'transparent' }}>
                        <Box flex="1" textAlign="left">
                          <Text size="sm" fontWeight="bold">
                            Information on record
                          </Text>
                          <Text fontSize="xs" opacity={0.65}>
                            Local case facts used by the rules, separate from PDF evidence found by GenAI.
                          </Text>
                        </Box>
                        <AccordionIcon />
                      </AccordionButton>
                    </h2>

                    <AccordionPanel px="0" pt="8px">
                      {genAiError && (
                        <Text fontSize="xs" color="red.500" mb="8px">
                          {genAiError}
                        </Text>
                      )}

                      {!genAiError && codeFields.length === 0 ? (
                        <Text fontSize="sm" opacity={0.7}>
                          No local case facts found.
                        </Text>
                      ) : (
                        <Box display="grid" gridTemplateColumns="1fr 1fr" gap="8px">
                          {codeFields.map((r: any) => {
                            const label = r.field_key || 'field';
                            const value = displayLocatedFieldValue(r);

                            return (
                              <Box
                                key={r.id}
                                px="10px"
                                py="8px"
                                mb="6px"
                                borderRadius="md"
                                borderWidth="1px"
                                borderColor="gray.200"
                                bg="white"
                              >
                                <Flex align="center" gap="6px" mb="2px" wrap="wrap">
                                  <Text fontSize="xs" opacity={0.7}>
                                    {label}
                                  </Text>
                                </Flex>
                                <Text fontSize="sm" noOfLines={3}>
                                  {value}
                                </Text>
                              </Box>
                            );
                          })}
                        </Box>
                      )}
                    </AccordionPanel>
                  </AccordionItem>

                  {upgradeTypeGroups.length === 0 ? (
                    <AccordionItem borderTopWidth="1px" borderColor="gray.200">
                      <h2>
                        <AccordionButton px="0" py="6px" _hover={{ bg: 'transparent' }}>
                          <Box flex="1" textAlign="left">
                            <Text size="sm">Energy Savings Program Review</Text>
                          </Box>
                          <AccordionIcon />
                        </AccordionButton>
                      </h2>
                      <AccordionPanel px="0" pt="8px">
                        <Text fontSize="sm" opacity={0.7}>
                          No upgrade-type review rows found.
                        </Text>
                      </AccordionPanel>
                    </AccordionItem>
                  ) : (
                    upgradeTypeGroups.map((group) => {
                      const meta = getInvoiceUpgradeTypeMeta(group.upgradeTypeKey, group.description);
                      const foundFieldCount = group.fields.length;
                      const rulecheckCount = group.rulechecks.length;
                      const classifierResults = group.results.filter((r: any) => r.source_engine === 'classifier');

                      return (
                        <AccordionItem key={group.upgradeTypeKey} borderTopWidth="1px" borderColor="gray.200">
                          <h2>
                            <AccordionButton px="0" py="8px" _hover={{ bg: 'transparent' }}>
                              <Flex flex="1" align="center" gap="8px" textAlign="left" minW={0}>
                                <InvoiceUpgradeTypeTile
                                  upgradeTypeKey={group.upgradeTypeKey}
                                  description={group.description}
                                  size={30}
                                />
                                <Box minW={0}>
                                  <Text fontSize="sm" fontWeight="bold" noOfLines={1}>
                                    {meta.label}
                                  </Text>
                                  <Text fontSize="xs" opacity={0.65}>
                                    {foundFieldCount} fields - {rulecheckCount} rules
                                  </Text>
                                </Box>
                              </Flex>
                              <AccordionIcon />
                            </AccordionButton>
                          </h2>

                          <AccordionPanel px="0" pt="8px">
                            <Box mb="14px">
                              <Text fontSize="xs" fontWeight="bold" textTransform="uppercase" opacity={0.7} mb="6px">
                                Classification
                              </Text>
                              {classifierResults.length === 0 ? (
                                <Text fontSize="sm" opacity={0.7}>
                                  No classifier explanation for this upgrade type.
                                </Text>
                              ) : (
                                <Box display="flex" flexDirection="column" gap="8px">
                                  {classifierResults.map((r: any) => {
                                    const explanation = classifierExplanationFor(r);
                                    const evidenceRows = uniqueClassifierEvidenceFor(r);

                                    return (
                                      <Box
                                        key={r.id}
                                        px="10px"
                                        py="8px"
                                        borderRadius="md"
                                        borderWidth="1px"
                                        borderColor="blue.100"
                                        bg="blue.50"
                                      >
                                        <Text fontSize="xs" opacity={0.75} mb="4px">
                                          confidence: {r.confidence ?? '-'}
                                        </Text>

                                        {explanation && (
                                          <Text fontSize="sm" whiteSpace="pre-wrap" mb="6px">
                                            {explanation}
                                          </Text>
                                        )}

                                        {evidenceRows.length > 0 && (
                                          <Text fontSize="xs" whiteSpace="pre-wrap">
                                            <Box as="span" opacity={0.65}>
                                              evidence:{' '}
                                            </Box>
                                            {evidenceRows.join('\n')}
                                          </Text>
                                        )}
                                      </Box>
                                    );
                                  })}
                                </Box>
                              )}
                            </Box>

                            <Box mb="14px">
                              <Text fontSize="xs" fontWeight="bold" textTransform="uppercase" opacity={0.7} mb="6px">
                                Found fields
                              </Text>
                              {genAiError && (
                                <Text fontSize="xs" color="red.500" mb="8px">
                                  {genAiError}
                                </Text>
                              )}
                              {group.fields.length === 0 ? (
                                <Text fontSize="sm" opacity={0.7}>
                                  No found fields for this upgrade type.
                                </Text>
                              ) : (
                                <Box display="grid" gridTemplateColumns="1fr 1fr" gap="8px">
                                  {group.fields.map((r: any) => {
                                    const label = r.field_key || 'field';
                                    const value = displayLocatedFieldValue(r);
                                    const highlightKey = `found_${r.id}`;
                                    const metaText = [
                                      r.confidence != null ? `conf ${Number(r.confidence).toFixed(0)}` : null,
                                    ]
                                      .filter(Boolean)
                                      .join(' - ');
                                    const clickable = r.page != null;

                                    return (
                                      <FieldRow
                                        key={r.id}
                                        label={`${label}${metaText ? ` - ${metaText}` : ''}`}
                                        value={value}
                                        active={activeHighlightKey === highlightKey}
                                        disabled={!clickable}
                                        onClick={
                                          clickable
                                            ? () => {
                                                setActiveHighlight({
                                                  source: 'genai',
                                                  genaiId: Number(r.id),
                                                  pageNumber: Number(r.page),
                                                  polygon: r.polygon ?? null,
                                                });
                                                setActiveHighlightKey(highlightKey);
                                              }
                                            : undefined
                                        }
                                      />
                                    );
                                  })}
                                </Box>
                              )}
                            </Box>

                            <Box mb="14px">
                              <Text fontSize="xs" fontWeight="bold" textTransform="uppercase" opacity={0.7} mb="6px">
                                Rules
                              </Text>
                              {genAiRulechecksError && (
                                <Text fontSize="xs" color="red.500" mb="8px">
                                  {genAiRulechecksError}
                                </Text>
                              )}
                              {group.rulechecks.length === 0 ? (
                                <Text fontSize="sm" opacity={0.7}>
                                  No rules for this upgrade type.
                                </Text>
                              ) : (
                                <Box display="flex" flexDirection="column" gap="8px">
                                  {group.rulechecks.map((r: any) => {
                                    const title = ruleDisplayTitle(r);
                                    const sourceLabel = ruleSourceLabel(r);
                                    const expected = r.expected_text ?? r.expected ?? '';
                                    const calc = r.calculation ?? '';
                                    const reason = r.reason_and_likely_causes ?? '';
                                    const evText = r.evidence_text ?? '';
                                    const sourceRequirement = r.source_requirement_id ?? '';

                                    return (
                                      <Box
                                        key={r.id ?? `${r.source_engine}-${r.rule_number}-${r.rule_name}`}
                                        px="10px"
                                        py="8px"
                                        borderRadius="md"
                                        borderWidth="1px"
                                        borderColor="gray.200"
                                        bg="white"
                                      >
                                        <Flex align="center" gap="8px" mb="4px">
                                          <StatusDot result={r.rule_result} />
                                          <Text fontSize="xs" opacity={0.75}>
                                            {title}
                                          </Text>
                                          {sourceLabel && (
                                            <Badge colorScheme="gray" variant="subtle" textTransform="lowercase">
                                              {sourceLabel}
                                            </Badge>
                                          )}
                                        </Flex>
                                        {sourceRequirement && (
                                          <Text fontSize="xs" opacity={0.65} mb="6px">
                                            {sourceRequirement}
                                          </Text>
                                        )}
                                        {expected && (
                                          <Text fontSize="xs" whiteSpace="pre-wrap">
                                            <Box as="span" opacity={0.65}>
                                              expected:{' '}
                                            </Box>
                                            {String(expected)}
                                          </Text>
                                        )}
                                        {calc && (
                                          <Text fontSize="xs" whiteSpace="pre-wrap">
                                            <Box as="span" opacity={0.65}>
                                              calculation:{' '}
                                            </Box>
                                            {String(calc)}
                                          </Text>
                                        )}
                                        {reason && (
                                          <Text fontSize="xs" whiteSpace="pre-wrap">
                                            <Box as="span" opacity={0.65}>
                                              reason:{' '}
                                            </Box>
                                            {String(reason)}
                                          </Text>
                                        )}
                                        {evText && (
                                          <Text fontSize="xs" whiteSpace="pre-wrap">
                                            <Box as="span" opacity={0.65}>
                                              evidence:{' '}
                                            </Box>
                                            {String(evText)}
                                          </Text>
                                        )}
                                      </Box>
                                    );
                                  })}
                                </Box>
                              )}
                            </Box>
                          </AccordionPanel>
                        </AccordionItem>
                      );
                    })
                  )}

                  {false && (
                    <>
                      {/* ============================================================
    SECTION 07.05.15 - ACCORDION ITEM: LINE ITEMS (OCR)
    PURPOSE: Show claims.lineitems + click to highlight polygon
    ============================================================ */}
                      <AccordionItem borderTopWidth="1px" borderColor="gray.200">
                        <h2>
                          <AccordionButton px="0" py="6px" _hover={{ bg: 'transparent' }}>
                            <Box flex="1" textAlign="left">
                              <Text size="sm">Line Items</Text>
                            </Box>
                            <AccordionIcon />
                          </AccordionButton>
                        </h2>

                        <AccordionPanel px="0" pt="8px">
                          {lineitemsError && (
                            <Text fontSize="xs" color="red.500" mb="8px">
                              {lineitemsError}
                            </Text>
                          )}

                          {!lineitemsError && lineitems.length === 0 && (
                            <Text fontSize="sm" opacity={0.7}>
                              No line items found.
                            </Text>
                          )}

                          <Box display="grid" gridTemplateColumns="1fr 1fr" gap="8px">
                            {lineitems.map((li: any) => {
                              const seq = li.lineitem_seqno ?? li.seqno ?? '-';

                              // helper to build a FieldRow-like entry
                              const makeRow = (opts: {
                                subKey: string;
                                label: string;
                                value: any;
                                page: any;
                                polygon: any;
                              }) => {
                                const clickable = opts.page != null && opts.polygon != null;

                                const isActive =
                                  activeHighlight?.source === 'di' &&
                                  activeHighlight?.key === `lineitem_${seq}_${opts.subKey}`;

                                return (
                                  <FieldRow
                                    key={`${li.id ?? `li-${seq}`}-${opts.subKey}`}
                                    label={`Line ${seq} - ${opts.label}`}
                                    value={opts.value}
                                    active={isActive}
                                    disabled={!clickable}
                                    onClick={
                                      clickable
                                        ? () => {
                                            setActiveHighlight({
                                              source: 'di',
                                              key: `lineitem_${seq}_${opts.subKey}`,
                                              pageNumber: Number(opts.page),
                                              polygon: opts.polygon,
                                            });
                                            setActiveHighlightKey(`lineitem_${seq}_${opts.subKey}`);
                                          }
                                        : undefined
                                    }
                                  />
                                );
                              };

                              return (
                                <Box key={li.id ?? `li-${seq}`} mb="10px">
                                  {makeRow({
                                    subKey: 'desc',
                                    label: 'Description',
                                    value: li.ocr_description ?? '-',
                                    page: li.ocr_description_page,
                                    polygon: li.ocr_description_polygon,
                                  })}

                                  {makeRow({
                                    subKey: 'qty',
                                    label: 'Quantity',
                                    value: li.ocr_quantity != null ? String(li.ocr_quantity) : '-',
                                    page: li.ocr_quantity_page,
                                    polygon: li.ocr_quantity_polygon,
                                  })}

                                  {makeRow({
                                    subKey: 'unit',
                                    label: 'Unit price',
                                    value: li.ocr_unit_price != null ? fmtMoney(li.ocr_unit_price) : '-',
                                    page: li.ocr_unit_price_page,
                                    polygon: li.ocr_unit_price_polygon,
                                  })}

                                  {makeRow({
                                    subKey: 'amt',
                                    label: 'Amount',
                                    value: li.ocr_amount != null ? fmtMoney(li.ocr_amount) : '-',
                                    page: li.ocr_amount_page,
                                    polygon: li.ocr_amount_polygon,
                                  })}
                                </Box>
                              );
                            })}
                          </Box>
                        </AccordionPanel>
                      </AccordionItem>

                      {/* ============================================================
      SECTION 07.05.20 - ACCORDION ITEM: GENAI LOCATED FIELDS
      PURPOSE: Simple display of /read_genai results (not clickable yet)
      ============================================================ */}
                      <AccordionItem borderTopWidth="1px" borderColor="gray.200">
                        <h2>
                          <AccordionButton px="0" py="6px" _hover={{ bg: 'transparent' }}>
                            <Box flex="1" textAlign="left">
                              <Text size="sm">Energy Savings Program</Text>
                            </Box>
                            <AccordionIcon />
                          </AccordionButton>
                        </h2>

                        <AccordionPanel px="0" pt="8px">
                          {/* ============================================================
          SECTION 07.05.21 - GENAI ERROR
          PURPOSE: show fetch error if endpoint fails
          ============================================================ */}
                          {genAiError && (
                            <Text fontSize="xs" color="red.500" mb="8px">
                              {genAiError}
                            </Text>
                          )}

                          {/* ============================================================
          SECTION 07.05.22 - GENAI EMPTY
          PURPOSE: show message when no rows returned
          ============================================================ */}
                          {!genAiError && genAiFields.length === 0 && (
                            <Text fontSize="sm" opacity={0.7}>
                              No GenAI located fields found.
                            </Text>
                          )}

                          {/* ============================================================
          SECTION 07.05.23 - GENAI LIST
          PURPOSE: minimal list: field_key + value + (page/confidence)
          ============================================================ */}
                          <Box display="grid" gridTemplateColumns="1fr 1fr" gap="8px">
                            {genAiFields.map((r: any) => {
                              const label = r.field_key || 'field';
                              const value = displayLocatedFieldValue(r);

                              const meta = [r.confidence != null ? `conf ${Number(r.confidence).toFixed(2)}` : null]
                                .filter(Boolean)
                                .join(' - ');

                              return (
                                <Box
                                  key={r.id}
                                  role="button"
                                  cursor="pointer"
                                  px="10px"
                                  py="8px"
                                  mb="6px"
                                  borderRadius="md"
                                  borderWidth="1px"
                                  borderColor={
                                    activeHighlight?.source === 'genai' && activeHighlight?.genaiId === Number(r.id)
                                      ? 'blue.400'
                                      : 'gray.200'
                                  }
                                  bg={
                                    activeHighlight?.source === 'genai' && activeHighlight?.genaiId === Number(r.id)
                                      ? 'blue.50'
                                      : 'white'
                                  }
                                  _hover={{ bg: 'gray.50', borderColor: 'gray.300' }}
                                  onClick={() => {
                                    // ============================================================
                                    // SECTION 07.05.23.01 - GENAI CLICK > SET ACTIVE HIGHLIGHT
                                    // PURPOSE: Move PDF to page + draw polygon using same overlay code
                                    // ============================================================
                                    setActiveHighlight({
                                      source: 'genai',
                                      genaiId: Number(r.id),
                                      pageNumber: r.page != null ? Number(r.page) : null,
                                      polygon: r.polygon ?? null,
                                    });
                                  }}
                                >
                                  <Text fontSize="xs" opacity={0.7}>
                                    {label}
                                  </Text>
                                  <Text fontSize="sm" noOfLines={3}>
                                    {value}
                                  </Text>
                                  {meta && (
                                    <Text fontSize="xs" opacity={0.6}>
                                      {meta}
                                    </Text>
                                  )}
                                </Box>
                              );
                            })}
                          </Box>
                        </AccordionPanel>
                      </AccordionItem>

                      <AccordionItem borderTopWidth="1px" borderColor="gray.200">
                        <h2>
                          <AccordionButton px="0" py="6px" _hover={{ bg: 'transparent' }}>
                            <Box flex="1" textAlign="left">
                              <Text size="sm">Pre-existing info on file</Text>
                            </Box>
                            <AccordionIcon />
                          </AccordionButton>
                        </h2>

                        <AccordionPanel px="0" pt="8px">
                          {/* error (reuse genAiError because same endpoint) */}
                          {genAiError && (
                            <Text fontSize="xs" color="red.500" mb="8px">
                              {genAiError}
                            </Text>
                          )}

                          {/* empty */}
                          {!genAiError && codeFields.length === 0 && (
                            <Text fontSize="sm" opacity={0.7}>
                              No pre-existing fields on file.
                            </Text>
                          )}

                          <Box display="grid" gridTemplateColumns="1fr 1fr" gap="8px">
                            {/* list */}
                            {codeFields.map((r: any) => {
                              const label = r.field_key || 'field';
                              const value = displayLocatedFieldValue(r);

                              const meta = [r.confidence != null ? `conf ${Number(r.confidence).toFixed(2)}` : null]
                                .filter(Boolean)
                                .join(' - ');

                              return (
                                <Box
                                  key={r.id}
                                  role="button"
                                  cursor="pointer"
                                  px="10px"
                                  py="8px"
                                  mb="6px"
                                  borderRadius="md"
                                  borderWidth="1px"
                                  borderColor={
                                    activeHighlight?.source === 'code' && activeHighlight?.genaiId === Number(r.id)
                                      ? 'blue.400'
                                      : 'gray.200'
                                  }
                                  bg={
                                    activeHighlight?.source === 'code' && activeHighlight?.genaiId === Number(r.id)
                                      ? 'blue.50'
                                      : 'white'
                                  }
                                  _hover={{ bg: 'gray.50', borderColor: 'gray.300' }}
                                  onClick={() => {
                                    setActiveHighlight({
                                      source: 'code' as any, // <-- see note below
                                      genaiId: Number(r.id),
                                      pageNumber: r.page != null ? Number(r.page) : null,
                                      polygon: r.polygon ?? null,
                                    });
                                  }}
                                >
                                  <Text fontSize="xs" opacity={0.7}>
                                    {label}
                                  </Text>
                                  <Text fontSize="sm" noOfLines={3}>
                                    {value}
                                  </Text>
                                  {meta && (
                                    <Text fontSize="xs" opacity={0.6}>
                                      {meta}
                                    </Text>
                                  )}
                                </Box>
                              );
                            })}
                          </Box>
                        </AccordionPanel>
                      </AccordionItem>

                      {/* ============================================================
      SECTION 07.05.30 - ACCORDION ITEM: GENAI RULECHECKS
      PURPOSE: Display rules from claims.invoice_version_rulechecks
      ============================================================ */}
                      <AccordionItem borderTopWidth="1px" borderColor="gray.200">
                        <h2>
                          <AccordionButton px="0" py="6px" _hover={{ bg: 'transparent' }}>
                            <Box flex="1" textAlign="left">
                              <Text size="sm">Rule Checks</Text>
                            </Box>
                            <AccordionIcon />
                          </AccordionButton>
                        </h2>

                        <AccordionPanel px="0" pt="8px">
                          {/* ============================================================
    SECTION 07.05.30.05 - GENAI OVERALL SUMMARY (from /read)
    PURPOSE: Quiet summary at top of Rule Checks panel
    REQUIRES: readData includes these invoice_versions columns:
      ? genai_overall_confidence
      ? genai_result
      ? genai_admin_advice
   ============================================================ */}
                          <Box
                            mb="10px"
                            px="10px"
                            py="10px"
                            borderWidth="1px"
                            borderRadius="md"
                            borderColor="gray.200"
                            bg="gray.50"
                          >
                            <Flex direction="column" align="flex-start" gap="4px" mb="6px">
                              <Text fontSize="xs" opacity={0.7}>
                                Overall (GenAI)
                              </Text>

                              <Flex align="center" gap="8px">
                                <Box
                                  as="span"
                                  w="10px"
                                  h="10px"
                                  borderRadius="full"
                                  display="inline-block"
                                  bg={resultDotColor(readData?.genai_result)}
                                />

                                <Text fontSize="xs" opacity={0.6}>
                                  {resultLabel(readData?.genai_result)} - conf {readData?.genai_overall_confidence ?? 0}
                                </Text>
                              </Flex>
                            </Flex>

                            {String(readData?.genai_admin_advice ?? '').trim() ? (
                              <Text fontSize="sm" whiteSpace="pre-wrap">
                                {String(readData.genai_admin_advice)}
                              </Text>
                            ) : (
                              <Text fontSize="sm" opacity={0.7}>
                                No admin advice.
                              </Text>
                            )}
                          </Box>

                          {/* error */}
                          {genAiRulechecksError && (
                            <Text fontSize="xs" color="red.500" mb="8px">
                              {genAiRulechecksError}
                            </Text>
                          )}

                          {/* empty */}
                          {!genAiRulechecksError && genAiRulechecks.length === 0 && (
                            <Text fontSize="sm" opacity={0.7}>
                              No rulechecks found.
                            </Text>
                          )}

                          {/* list */}
                          {genAiRulechecks.map((r: any) => {
                            const title = ruleDisplayTitle(r);
                            const sourceLabel = ruleSourceLabel(r);

                            const conf =
                              r.confidence != null && r.confidence !== ''
                                ? `conf ${Number(r.confidence).toFixed(0)}`
                                : '';

                            const meta = conf;

                            // Keep rule explanations compact but readable in the admin viewer.
                            const expected = r.expected_text ?? r.expected ?? '';
                            const calc = r.calculation ?? '';
                            const reason = r.reason_and_likely_causes ?? '';
                            const evText = r.evidence_text ?? '';
                            const sourceRequirement = r.source_requirement_id ?? '';

                            return (
                              <Box
                                key={r.id ?? `${r.source_engine}-${r.rule_number}-${r.rule_name}`}
                                px="10px"
                                py="8px"
                                mb="8px"
                                borderRadius="md"
                                borderWidth="1px"
                                borderColor="gray.200"
                                bg="white"
                              >
                                <Flex align="center" gap="8px">
                                  <StatusDot result={r.rule_result} />
                                  <Text fontSize="xs" opacity={0.7}>
                                    {title}
                                  </Text>
                                  {sourceLabel && (
                                    <Badge colorScheme="gray" variant="subtle" textTransform="lowercase">
                                      {sourceLabel}
                                    </Badge>
                                  )}
                                </Flex>

                                {meta && (
                                  <Text fontSize="xs" opacity={0.6} mb="6px">
                                    {meta}
                                  </Text>
                                )}

                                {sourceRequirement && (
                                  <Text fontSize="xs" opacity={0.65} mb="6px">
                                    {sourceRequirement}
                                  </Text>
                                )}

                                {expected && (
                                  <Box mb="6px">
                                    <Text fontSize="xs" opacity={0.7}>
                                      expected
                                    </Text>
                                    <Text fontSize="sm" whiteSpace="pre-wrap">
                                      {String(expected)}
                                    </Text>
                                  </Box>
                                )}

                                {calc && (
                                  <Box mb="6px">
                                    <Text fontSize="xs" opacity={0.7}>
                                      calculation
                                    </Text>
                                    <Text fontSize="sm" whiteSpace="pre-wrap">
                                      {String(calc)}
                                    </Text>
                                  </Box>
                                )}

                                {reason && (
                                  <Box mb="6px">
                                    <Text fontSize="xs" opacity={0.7}>
                                      reason
                                    </Text>
                                    <Text fontSize="sm" whiteSpace="pre-wrap">
                                      {String(reason)}
                                    </Text>
                                  </Box>
                                )}

                                {evText && (
                                  <Box>
                                    <Text fontSize="xs" opacity={0.7}>
                                      evidence
                                    </Text>
                                    <Text fontSize="sm" whiteSpace="pre-wrap">
                                      {String(evText)}
                                    </Text>
                                  </Box>
                                )}
                              </Box>
                            );
                          })}
                        </AccordionPanel>
                      </AccordionItem>
                    </>
                  )}
                </Accordion>
              </Box>

              {/* ============================================================
        SECTION 07.06 - RIGHT PANEL (PDF)
        PURPOSE: PDF viewer + overlay highlight + toolbar
        ============================================================ */}

              {showPdf ? (
                <Box
                  ref={pdfWrapRef}
                  flex="0 0 640px"
                  w="640px"
                  maxW="640px"
                  minW="640px"
                  minH={0}
                  borderWidth="1px"
                  borderRadius="md"
                  overflow="auto"
                  p="8px"
                  bg="gray.50"
                >
                  <Box position="relative" width="100%">
                    {/* ============================================================
        SECTION 07.07 - PDF TOOLBAR
        PURPOSE: Page nav + zoom/fit/rotate + open
        ============================================================ */}

                    <Box
                      display="flex"
                      flexDirection="column"
                      alignItems="stretch"
                      gap="8px"
                      mb="8px"
                      p="8px"
                      borderWidth="1px"
                      borderRadius="md"
                    >
                      {/* Left: page navigation */}
                      <Box display="flex" alignItems="center" gap="6px" flexWrap="wrap">
                        <Button
                          size="sm"
                          onClick={() => setActivePageNumber((p) => Math.max(1, p - 1))}
                          isDisabled={activePageNumber <= 1}
                        >
                          Prev
                        </Button>

                        <Text fontSize="sm" opacity={0.8}>
                          Page
                        </Text>

                        <Box
                          as="input"
                          value={pageInput}
                          onChange={(e: any) => setPageInput(e.target.value)}
                          onBlur={() => {
                            const n = Number(pageInput);
                            if (!Number.isFinite(n)) {
                              setPageInput(String(activePageNumber));
                              return;
                            }
                            const clamped = Math.min(Math.max(1, Math.floor(n)), numPages || 1);
                            setActivePageNumber(clamped);
                          }}
                          onKeyDown={(e: any) => {
                            if (e.key === 'Enter') (e.target as HTMLInputElement).blur();
                          }}
                          style={{
                            width: 60,
                            padding: '6px 8px',
                            border: '1px solid #E2E8F0',
                            borderRadius: 6,
                          }}
                        />

                        <Text fontSize="sm" opacity={0.8}>
                          / {numPages || '-'}
                        </Text>

                        <Button
                          size="sm"
                          onClick={() => setActivePageNumber((p) => Math.min(numPages || p + 1, p + 1))}
                          isDisabled={!!numPages && activePageNumber >= numPages}
                        >
                          Next
                        </Button>
                      </Box>

                      {/* Right: zoom/fit/rotate/actions */}
                      <Box display="flex" alignItems="center" gap="6px" flexWrap="wrap">
                        <Button size="sm" onClick={() => setZoom((z) => Math.max(0.5, +(z - 0.1).toFixed(2)))}>
                          -
                        </Button>

                        <Text fontSize="sm" minW="56px" textAlign="center">
                          {Math.round(zoom * 100)}%
                        </Text>

                        <Button size="sm" onClick={() => setZoom((z) => Math.min(3.0, +(z + 0.1).toFixed(2)))}>
                          +
                        </Button>

                        <Button
                          size="sm"
                          variant={fitMode === 'width' ? 'solid' : 'outline'}
                          onClick={() => {
                            setFitMode('width');
                            setZoom(1.0);
                          }}
                        >
                          Fit width
                        </Button>

                        <Button
                          size="sm"
                          variant={fitMode === 'page' ? 'solid' : 'outline'}
                          onClick={() => {
                            setFitMode('page');
                            setZoom(1.0);
                          }}
                        >
                          Fit page
                        </Button>

                        <Button size="sm" onClick={() => setRotate((r) => (r + 90) % 360)}>
                          Rotate
                        </Button>

                        <Button
                          size="sm"
                          variant="outline"
                          onClick={() => {
                            if (!pdfUrl) return;
                            window.open(pdfUrl, '_blank', 'noopener,noreferrer');
                          }}
                        >
                          Open
                        </Button>
                      </Box>
                    </Box>

                    {/* ============================================================
    SECTION 07.08 - PDF DOCUMENT + OVERLAY RENDER (DYNAMIC)
    PURPOSE: Render the PDF page + draw polygon overlay
    NOTES:
    ? ONLY ONE Document should exist in this pane
    ? We render Document only when pdfUrl is present
    ============================================================ */}

                    {pdfUrlError && (
                      <Text fontSize="sm" color="red.500" mb="8px">
                        PDF URL error: {pdfUrlError}
                      </Text>
                    )}

                    {/* 2) loading state */}
                    {!pdfUrl && !pdfUrlError && (
                      <Text fontSize="sm" opacity={0.7} mb="8px">
                        Loading PDF URL...
                      </Text>
                    )}

                    {/* 3) render PDF only when url exists */}
                    {pdfUrl && (
                      <Document
                        key={pdfUrl} // force reload when url changes
                        file={pdfUrl} // IMPORTANT: dynamic URL here
                        onLoadSuccess={({ numPages }) => setNumPages(numPages)}
                        onLoadError={(err) => console.error('PDF load error:', err)}
                      >
                        {/* Wrapper so SVG and Page share identical geometry */}
                        <Box
                          position="relative"
                          width={`${overlayWidthPx}px`}
                          height={`${overlayHeightPx}px`}
                          mx="auto"
                        >
                          {/* SVG overlay */}
                          <svg
                            width={overlayWidthPx}
                            height={overlayHeightPx}
                            style={{ position: 'absolute', top: 0, left: 0, zIndex: 10, pointerEvents: 'none' }}
                          >
                            {svgPolygonPoints && (
                              <polygon
                                points={svgPolygonPoints}
                                fill="rgba(255,0,0,0.20)"
                                stroke="red"
                                strokeWidth={2}
                              />
                            )}
                          </svg>

                          {/* Actual PDF page */}
                          <Box style={{ position: 'absolute', top: 0, left: 0 }}>
                            <Page
                              key={`p${activePageNumber}-w${renderWidthPx}-r${rotate}`} // force remount on zoom/rotate/page
                              pageNumber={activePageNumber}
                              width={renderWidthPx}
                              rotate={rotate}
                            />
                          </Box>
                        </Box>
                      </Document>
                    )}

                    <Text fontSize="xs" opacity={0.6} mt="8px">
                      Active highlight: {activeHighlight?.source ?? '-'}{' '}
                      {activeHighlight?.source === 'di'
                        ? activeHighlight?.key ?? '-'
                        : `genai ${activeHighlight?.genaiId ?? '-'}`}{' '}
                      | page {activePageNumber} / {numPages || '-'} | unit {activePageMeta?.unit ?? '-'}
                    </Text>
                  </Box>{' '}
                  {/* closes SECTION 07.06 inner <Box position="relative" width="100%"> */}
                </Box>
              ) : null}
            </Box>{' '}
            {/*  ADD: closes SECTION 07.04 main split view <Box display="flex" ...> */}
          </Box>{' '}
          {/*  ADD: closes SECTION 07.02 page layout <Box display="flex" flexDirection="column" ...> */}
        </Box>{' '}
        {/*  ADD THIS: closes the first Box inside Container (Box A) */}
      </Container>{' '}
      {/*  THIS is the closecontainer line */}
      <Drawer isOpen={isHelpOpen} placement="left" onClose={onHelpClose} size="xl">
        <DrawerOverlay />
        <DrawerContent>
          <DrawerCloseButton />
          <DrawerHeader>PDF Viewer Help</DrawerHeader>
          <DrawerBody>
            <Flex direction="column" gap={4}>
              <Box>
                <Heading size="sm" mb={2}>
                  What This Screen Shows
                </Heading>
                <Text as="div" fontSize="sm">
                  This screen shows the current invoice version and the PDF evidence used during admin review.
                </Text>
                <Text as="div" fontSize="sm" mt={1}>
                  Older invoice versions are review history. Workflow status buttons belong on the current invoice only.
                </Text>
                <Text as="div" fontSize="sm" mt={1}>
                  Use the action buttons at the top to screen in, send to contractor for revision, approve pending, or
                  mark paid.
                </Text>
              </Box>

              <Box>
                <Heading size="sm" mb={2}>
                  Status Actions
                </Heading>
                <Text as="div" fontSize="sm">
                  Screen In moves a submitted invoice from admin_review_inbox to in_review.
                </Text>
                <Text as="div" fontSize="sm" mt={1}>
                  Send to Contractor for Revision moves the invoice to contractor_revision_inbox. The message to the
                  contractor is a separate revision request record so admins can clearly state what must be fixed or
                  provided.
                </Text>
                <Text as="div" fontSize="sm" mt={1}>
                  Approve Pending moves an in-review invoice to approved_pending after admin/supervisor review.
                </Text>
                <Text as="div" fontSize="sm" mt={1}>
                  Mark Paid moves an approved_pending invoice to approved_paid after payment is handled elsewhere.
                </Text>
              </Box>

              <Box>
                <Heading size="sm" mb={2}>
                  Accordion Sections
                </Heading>
                <Text as="div" fontSize="sm">
                  Invoice: OCR header fields like invoice number, date, vendor, customer, and totals.
                </Text>
                <Text as="div" fontSize="sm" mt={1}>
                  Line Items: OCR line rows like description, quantity, unit price, and amount. The likely upgrade type
                  shown beside each line is a classifier guess and may need human review.
                </Text>
                <Text as="div" fontSize="sm" mt={1}>
                  GenAI Located Fields: values found by AI with evidence and document location details.
                </Text>
                <Text as="div" fontSize="sm" mt={1}>
                  Pre-existing info on file: known case data already in the system.
                </Text>
                <Text as="div" fontSize="sm" mt={1}>
                  GenAI Rulechecks: rule-by-rule pass or fail, confidence, evidence, and the overall AI summary/advice.
                </Text>
              </Box>

              <Box>
                <Heading size="sm" mb={2}>
                  How This Relates To Rulesets
                </Heading>
                <Text as="div" fontSize="sm">
                  The ruleset tells AI what to check and what output shape to return.
                </Text>
                <Text as="div" fontSize="sm" mt={1}>
                  Because of that, ruleset changes directly affect what appears in GenAI Located Fields and GenAI
                  Rulechecks.
                </Text>
                <Text as="div" fontSize="sm" mt={1}>
                  Invoice and Line Items are OCR-driven sections, while the GenAI sections are ruleset-driven review
                  sections.
                </Text>
              </Box>
            </Flex>
          </DrawerBody>
        </DrawerContent>
      </Drawer>
    </Flex>
  );
};
