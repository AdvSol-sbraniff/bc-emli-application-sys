// /app/frontend/components/domains/invoice-versions/index.tsx
import { fmtDate, fmtMoney, fmtText } from './display';

import {
  Box,
  Text,
  Flex,
  Container,
  Accordion,
  AccordionItem,
  Badge,
  Switch,
  AccordionButton,
  AccordionPanel,
  AccordionIcon,
  IconButton,
  Tooltip,
  useToast,
} from '@chakra-ui/react';
import { ThinBlueTitleBar } from '../../shared/base/thin-blue-title-bar';
import {
  getInvoiceUpgradeTypeMeta,
  INVOICE_UPGRADE_TYPE_FILTER_ORDER,
  InvoiceUpgradeTypeTile,
} from '../../shared/claims/invoice-upgrade-type-visual';
import {
  ArrowClockwise,
  ArrowSquareOut,
  ArrowUUpLeft,
  CaretLeft,
  CaretRight,
  ChatDots,
  CheckCircle,
  CornersOut,
  FrameCorners,
  MagnifyingGlassMinus,
  MagnifyingGlassPlus,
  PaperPlaneTilt,
  XCircle,
} from '@phosphor-icons/react';

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
  inline?: boolean;
};

const FieldRow = ({ label, value, active, disabled, onClick, inline }: FieldRowProps) => {
  return (
    <Box
      role={disabled ? undefined : 'button'}
      onClick={disabled ? undefined : onClick}
      px="10px"
      py={inline ? '2px' : '8px'}
      mb={inline ? '0' : '6px'}
      borderRadius="md"
      borderWidth="1px"
      borderColor={active ? 'blue.400' : 'transparent'}
      bg={active ? 'blue.50' : 'transparent'}
      cursor={disabled ? 'default' : 'pointer'}
      opacity={1}
      _hover={
        disabled
          ? {}
          : {
              bg: active ? 'blue.50' : 'gray.50',
              borderColor: active ? 'blue.400' : 'gray.200',
            }
      }
      display="flex"
      flexDirection={inline ? 'row' : 'column'}
      alignItems={inline ? 'baseline' : undefined}
      justifyContent={inline ? 'space-between' : undefined}
      gap={inline ? '6px' : '2px'}
    >
      <Text fontSize="sm" opacity={0.7} flexShrink={0}>
        {label}
      </Text>
      <Text
        fontSize="sm"
        fontWeight={active ? 'semibold' : 'normal'}
        noOfLines={inline ? 1 : 2}
        textAlign={inline ? 'right' : undefined}
      >
        {String(value)}
      </Text>
    </Box>
  );
};

const ruleDisplayTitle = (rulecheck: any) => {
  const ruleKey = String(rulecheck.rule_key ?? '').trim();
  if (ruleKey) return ruleKey;

  const num = rulecheck.rule_number != null ? Number(rulecheck.rule_number) : null;
  return num != null ? `rule_${num}` : 'rule';
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
  if (normalized === 'warn') return 'warn: always show, framed for contractor pre-check or admin attention.';
  if (normalized === 'fail') return 'fail: always show, framed as a correction needed.';
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

type InvoiceStatusTransition = 'screen_in' | 'request_revision' | 'approve_pending' | 'mark_ineligible';

const INVOICE_STATUS_COPY: Record<string, { label: string; hint: string }> = {
  upload_in_progress: {
    label: 'Uploading Package',
    hint: 'The uploaded package is being staged before evidence preparation starts.',
  },
  ocr_in_progress: {
    label: 'Preparing Evidence',
    hint: 'OCR, document classification, invoice extraction, and supporting-document extraction are running.',
  },
  evidence_prep: {
    label: 'Preparing Evidence',
    hint: 'OCR, document classification, invoice extraction, and supporting-document extraction are running.',
  },
  genai_in_progress: {
    label: 'Building AI Rule Advice',
    hint: 'AI rule advice is being built: case facts, product lookup, GenAI rule advice, code rules, and final advice.',
  },
  validation_advice: {
    label: 'Building AI Rule Advice',
    hint: 'AI rule advice is being built: case facts, product lookup, GenAI rule advice, code rules, and final advice.',
  },
  genai_complete: {
    label: 'AI Rule Advice Complete',
    hint: 'AI rule advice is complete. The contractor can pre-check the advice, revise if needed, and submit when ready.',
  },
  admin_review_inbox: {
    label: 'Waiting for Admin Review',
    hint: 'The claim is waiting for an admin to review it.',
  },
  in_review: {
    label: 'Admin Reviewing',
    hint: 'An admin review is underway.',
  },
  contractor_revision_inbox: {
    label: 'Waiting for Contractor Revision',
    hint: 'Admin review sent the claim back to the contractor to revise the package or provide supporting information.',
  },
  approved_pending: {
    label: 'Approved, Pending Payment',
    hint: 'The claim is approved, but payment or final closeout is not complete yet.',
  },
  approved_paid: {
    label: 'Approved and Paid',
    hint: 'The claim has been approved and paid or closed.',
  },
  ineligible: {
    label: 'Ineligible',
    hint: 'The claim has been marked ineligible.',
  },
  failed: {
    label: 'Processing Failed',
    hint: 'Processing failed and needs troubleshooting.',
  },
  upload_failed: {
    label: 'Processing Failed',
    hint: 'Upload or package staging failed and needs troubleshooting.',
  },
  ocr_failed: {
    label: 'Processing Failed',
    hint: 'Evidence preparation failed and needs troubleshooting.',
  },
  genai_failed: {
    label: 'Processing Failed',
    hint: 'AI rule advice failed and needs troubleshooting.',
  },
};

const humanizeStatus = (status: string) =>
  status
    .split('_')
    .filter(Boolean)
    .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
    .join(' ');

const invoiceStatusCopy = (status: unknown): { label: string; hint: string } => {
  const value = String(status ?? '').trim();
  if (!value) {
    return {
      label: 'Unknown',
      hint: 'This invoice does not have a workflow status.',
    };
  }
  return (
    INVOICE_STATUS_COPY[value] ?? {
      label: humanizeStatus(value),
      hint: 'This invoice is in a workflow status that does not have custom help text yet.',
    }
  );
};

const invoiceStatusLabel = (status: unknown): string => invoiceStatusCopy(status).label;

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
    key: 'mark_ineligible',
    label: 'Mark Ineligible',
    validFrom: ['admin_review_inbox', 'in_review'],
    targetStatus: 'ineligible',
    colorScheme: 'red',
    tooltip: 'Use when admin review determines the claim is not eligible. Moves status to ineligible.',
  },
];

const invoiceStatusActionIcon = (key: InvoiceStatusTransition) => {
  if (key === 'screen_in') return <PaperPlaneTilt size={25} weight="bold" />;
  if (key === 'request_revision') return <ArrowUUpLeft size={25} weight="bold" />;
  if (key === 'approve_pending') return <CheckCircle size={25} weight="bold" />;
  return <XCircle size={25} weight="bold" />;
};

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
  hideWhenBlank?: boolean; // omit optional evidence rows when DI did not return a value
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
    label: 'Business name',
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
    key: 'customer_address',
    label: 'Customer address',
    valueKey: 'di_ocr_customer_address',
    formatter: fmtText,
    pageKey: 'di_ocr_customer_address_page',
    polygonKey: 'di_ocr_customer_address_polygon',
    hideWhenBlank: true,
  },
  {
    key: 'customer_address_recipient',
    label: 'Customer address recipient',
    valueKey: 'di_ocr_customer_address_recipient',
    formatter: fmtText,
    pageKey: 'di_ocr_customer_address_recipient_page',
    polygonKey: 'di_ocr_customer_address_recipient_polygon',
    hideWhenBlank: true,
  },
  {
    key: 'service_address',
    label: 'Service address',
    valueKey: 'di_ocr_service_address',
    formatter: fmtText,
    pageKey: 'di_ocr_service_address_page',
    polygonKey: 'di_ocr_service_address_polygon',
    hideWhenBlank: true,
  },
  {
    key: 'service_address_recipient',
    label: 'Service address recipient',
    valueKey: 'di_ocr_service_address_recipient',
    formatter: fmtText,
    pageKey: 'di_ocr_service_address_recipient_page',
    polygonKey: 'di_ocr_service_address_recipient_polygon',
    hideWhenBlank: true,
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
    key: 'billing_address_recipient',
    label: 'Billing address recipient',
    valueKey: 'di_ocr_billing_address_recipient',
    formatter: fmtText,
    pageKey: 'di_ocr_billing_address_recipient_page',
    polygonKey: 'di_ocr_billing_address_recipient_polygon',
    hideWhenBlank: true,
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

  // ============================================================
  // SECTION 05.01 - STATE
  // PURPOSE: invoiceIds + readData + pdf viewer state + highlight state
  // ============================================================

  const [bannerHidden, setBannerHidden] = useState<boolean>(false);
  const [showPdf, setShowPdf] = useState<boolean>(false);

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
  const [viewerFile, setViewerFile] = useState<{
    source: 'invoice' | 'supporting_document';
    url: string;
    filename?: string;
    mimeType?: string;
    documentId?: string;
  } | null>(null);
  const [viewerPageMetaByPage, setViewerPageMetaByPage] = useState<
    Record<number, { width: number; height: number; unit: string }>
  >({});

  const [codeFields, setCodeFields] = useState<any[]>([]);
  const [classifierFields, setClassifierFields] = useState<any[]>([]);

  // ============================================================
  // SECTION 05.01.01 - ACTIVE HIGHLIGHT (SINGLE SOURCE OF TRUTH)
  // PURPOSE: BOTH header fields and GenAI rows set this (page + polygon)
  // ============================================================

  const [activeHighlight, setActiveHighlight] = useState<{
    source: 'di' | 'genai' | 'code' | 'classifier' | 'supporting_document';
    key?: string; // for DI: which field key
    genaiId?: number; // for GenAI: which row id (optional)
    supportingDocumentId?: string;
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

  useEffect(() => {
    if (bannerHidden) {
      document.body.dataset.claimsAiPdfViewerChromeHidden = 'true';
    } else {
      delete document.body.dataset.claimsAiPdfViewerChromeHidden;
    }

    window.dispatchEvent(new Event('claims-ai-pdf-viewer-chrome-change'));

    return () => {
      delete document.body.dataset.claimsAiPdfViewerChromeHidden;
      window.dispatchEvent(new Event('claims-ai-pdf-viewer-chrome-change'));
    };
  }, [bannerHidden]);

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
        setViewerFile((current) => {
          if (current && current.source !== 'invoice') return current;
          return {
            source: 'invoice',
            url: sasUrl,
            filename: 'Invoice',
            mimeType: 'application/pdf',
          };
        });
      } catch (e: any) {
        setPdfUrl(null);
        setPdfUrlError(String(e?.message ?? e));
      }
    };

    run();
  }, [isInvoiceCurrentRoute, isLegacySessionCurrentRoute, routeInvoiceId, routeInvoiceVersionId, sessionId]);

  useEffect(() => {
    setViewerFile(null);
    setViewerPageMetaByPage({});
    setActivePageNumber(1);
    setNumPages(0);
  }, [routeInvoiceId, routeInvoiceVersionId, sessionId]);

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
          setCodeFields([]);
          setClassifierFields([]);
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
        setClassifierFields(Array.isArray(json?.classifier_located_fields) ? json.classifier_located_fields : []);
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
        setCodeFields([]);
        setClassifierFields([]);
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

  const openSupportingDocumentFile = async (doc: any) => {
    const docId = String(doc?.id || '').trim();
    if (!docId) {
      toast({
        title: 'Cannot open file',
        description: 'This supporting document is missing its file identifier.',
        status: 'error',
        duration: 3500,
        isClosable: true,
      });
      return;
    }

    try {
      const resp = await fetch(`/api/claims/admin/supporting_documents/${encodeURIComponent(docId)}/pdf_url`, {
        headers: { Accept: 'application/json' },
        credentials: 'include',
      });
      const json = await resp.json().catch(() => ({}));
      const fileUrl = String(json?.sas_url || '').trim();

      if (!resp.ok || !fileUrl) {
        throw new Error(json?.error || `File URL request failed (${resp.status})`);
      }

      window.open(fileUrl, '_blank', 'noopener,noreferrer');
    } catch (e: any) {
      toast({
        title: 'Could not open supporting document',
        description: String(e?.message || e),
        status: 'error',
        duration: 5000,
        isClosable: true,
      });
    }
  };

  const showSupportingDocumentInViewer = async (doc: any, field?: any) => {
    const docId = String(doc?.id || '').trim();
    const filename = String(doc?.original_filename || 'Supporting document').trim();
    const mimeType = String(doc?.mime_content_type || doc?.content_type || '').trim();

    const setSupportingDocumentHighlight = () => {
      if (field) {
        setActiveHighlight({
          source: 'supporting_document',
          key: `supporting_field_${String(field?.id || field?.field_key || 'unknown')}`,
          supportingDocumentId: docId,
          pageNumber: field?.page != null ? Number(field.page) : 1,
          polygon: field?.polygon ?? null,
        });
      } else {
        setActiveHighlight(null);
        setActivePageNumber(1);
      }
    };

    if (!docId) {
      toast({
        title: 'Cannot show file',
        description: 'This supporting document is missing its file identifier.',
        status: 'error',
        duration: 3500,
        isClosable: true,
      });
      return;
    }

    if (viewerFile?.source === 'supporting_document' && viewerFile.documentId === docId && viewerFile.url) {
      setSupportingDocumentHighlight();
      setShowPdf(true);
      return;
    }

    try {
      const resp = await fetch(`/api/claims/admin/supporting_documents/${encodeURIComponent(docId)}/pdf_url`, {
        headers: { Accept: 'application/json' },
        credentials: 'include',
      });
      const json = await resp.json().catch(() => ({}));
      const fileUrl = String(json?.sas_url || '').trim();

      if (!resp.ok || !fileUrl) {
        throw new Error(json?.error || `File URL request failed (${resp.status})`);
      }

      setViewerPageMetaByPage({});
      setViewerFile({
        source: 'supporting_document',
        url: fileUrl,
        filename,
        mimeType,
        documentId: docId,
      });

      setSupportingDocumentHighlight();
      setShowPdf(true);
    } catch (e: any) {
      toast({
        title: 'Could not show supporting document',
        description: String(e?.message || e),
        status: 'error',
        duration: 5000,
        isClosable: true,
      });
    }
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

  useEffect(() => {
    if (!activeHighlight || activeHighlight.source === 'supporting_document' || !pdfUrl) return;
    setViewerFile({
      source: 'invoice',
      url: pdfUrl,
      filename: 'Invoice',
      mimeType: 'application/pdf',
    });
  }, [activeHighlight, pdfUrl]);

  const viewerUrl = viewerFile?.url || pdfUrl;
  const viewerFilename = String(viewerFile?.filename || 'Invoice').trim();
  const viewerMimeType = String(viewerFile?.mimeType || '').toLowerCase();
  const viewerIsImage =
    viewerMimeType.startsWith('image/') || /\.(png|jpe?g|gif|webp|bmp|tiff?)($|\?)/i.test(viewerUrl || viewerFilename);
  const viewerIsPdf = !viewerIsImage;

  const activePageMeta = useMemo(() => {
    const pnum = activeHighlight?.pageNumber;

    if (viewerFile?.source === 'supporting_document') {
      if (!pnum) return null;
      return viewerPageMetaByPage[Number(pnum)] ?? null;
    }

    const pages = readData?.di_page_map;
    if (!pages || !pnum) return null;

    // Your JSON uses "pageNumber", "width", "height", "unit"
    const found = pages.find((p: any) => Number(p.pageNumber) === Number(pnum));
    if (!found) return null;

    return {
      width: Number(found.width),
      height: Number(found.height),
      unit: String(found.unit || ''),
    };
  }, [activeHighlight?.pageNumber, readData?.di_page_map, viewerFile?.source, viewerPageMetaByPage]);

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
    if (meta.unit !== 'inch' && meta.unit !== 'pixel') {
      console.warn('Unexpected document coordinate unit:', meta.unit);
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

  const shouldShowActivePolygon =
    !!svgPolygonPoints &&
    activeHighlight?.pageNumber != null &&
    Number(activeHighlight.pageNumber) === Number(activePageNumber);

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
    upgradeTypeResults
      .filter((row) => row?.source_engine !== 'classifier')
      .forEach((row) => ensureGroup(row).results.push(row));
    genAiRulechecks.forEach((row) => ensureGroup(row).rulechecks.push(row));

    return Array.from(groups.values()).sort((a, b) => {
      const sortA = upgradeTypeSortValue(a.upgradeTypeKey);
      const sortB = upgradeTypeSortValue(b.upgradeTypeKey);
      if (sortA !== sortB) return sortA - sortB;
      return a.description.localeCompare(b.description);
    });
  }, [genAiFields, genAiRulechecks, upgradeTypeResults]);

  const classifierUpgradeTypeRows = useMemo(
    () =>
      upgradeTypeResults
        .filter((row) => row?.source_engine === 'classifier')
        .sort((a, b) => {
          const sortA = upgradeTypeSortValue(upgradeTypeKeyFor(a));
          const sortB = upgradeTypeSortValue(upgradeTypeKeyFor(b));
          if (sortA !== sortB) return sortA - sortB;
          return upgradeTypeDescriptionFor(a).localeCompare(upgradeTypeDescriptionFor(b));
        }),
    [upgradeTypeResults],
  );

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
  const neeaProductMatch = readData?.neea_product_match;
  const neeaProduct = neeaProductMatch?.product;
  const neeaSource = neeaProductMatch?.source;
  const awhpProductMatch = readData?.awhp_product_match;
  const awhpProduct = awhpProductMatch?.product;
  const awhpSource = awhpProductMatch?.source;
  const ohpaProductMatch = readData?.ohpa_product_match;
  const ohpaProduct = ohpaProductMatch?.product;
  const ohpaSource = ohpaProductMatch?.source;
  const supportingDocumentTypeGroups = useMemo(
    () =>
      Array.isArray(readData?.supporting_document_types_by_upgrade_type)
        ? readData.supporting_document_types_by_upgrade_type
        : [],
    [readData?.supporting_document_types_by_upgrade_type],
  );
  const uploadedSupportingDocuments = useMemo(
    () => (Array.isArray(readData?.uploaded_supporting_documents) ? readData.uploaded_supporting_documents : []),
    [readData?.uploaded_supporting_documents],
  );
  const uploadedSupportingDocumentGroups = useMemo(
    () =>
      Array.isArray(readData?.uploaded_supporting_document_groups) ? readData.uploaded_supporting_document_groups : [],
    [readData?.uploaded_supporting_document_groups],
  );
  const supportingDocumentEvidenceSections = useMemo(() => {
    const sectionMap = new Map<string, { key: string; title: string; groups: any[]; documents: any[] }>();
    const ensureSection = (rawKey: unknown, rawTitle: unknown) => {
      const title = String(rawTitle || rawKey || 'Unclassified document').trim() || 'Unclassified document';
      const key =
        String(rawKey || title)
          .trim()
          .toLowerCase() || 'unclassified-document';
      const existing = sectionMap.get(key);
      if (existing) return existing;
      const section = { key, title, groups: [] as any[], documents: [] as any[] };
      sectionMap.set(key, section);
      return section;
    };

    uploadedSupportingDocumentGroups.forEach((group: any) => {
      ensureSection(
        group?.supporting_document_type_key || group?.supporting_document_type_description || group?.group_label,
        group?.supporting_document_type_description || group?.supporting_document_type_key || group?.group_label,
      ).groups.push(group);
    });

    uploadedSupportingDocuments.forEach((doc: any) => {
      ensureSection(
        doc?.supporting_document_type_key || doc?.supporting_document_type_description || doc?.content_type,
        doc?.supporting_document_type_description || doc?.supporting_document_type_key || doc?.content_type,
      ).documents.push(doc);
    });

    return Array.from(sectionMap.values()).sort((a, b) => a.title.localeCompare(b.title));
  }, [uploadedSupportingDocumentGroups, uploadedSupportingDocuments]);
  const canOpenRevisionMessages = canRunWorkflowActions && !!readData?.invoice_id;

  // ============================================================
  // SECTION 07.01 - MAIN RETURN
  // PURPOSE: JSX layout tree (header + nav + split panes)
  // ============================================================

  return (
    <Flex as="main" direction="column" w="full" bg="greys.white" pb="24" minH="100vh">
      {!bannerHidden && (
        <Box onDoubleClick={() => setBannerHidden(true)}>
          <ThinBlueTitleBar title={titleText} />
        </Box>
      )}
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
            <Box display="flex" alignItems="center" gap="10px" mb="12px" flexWrap="wrap" px="0" py="2px">
              {isVersionSnapshotRoute && <Badge colorScheme="purple">Fixed version bookmark</Badge>}
              <Flex align="center" gap="7px" px="0" py="0">
                <Text fontSize="xs" fontWeight="semibold">
                  Image
                </Text>
                <Switch size="sm" isChecked={showPdf} onChange={(event) => setShowPdf(event.target.checked)} />
              </Flex>

              {canRunWorkflowActions ? (
                INVOICE_STATUS_ACTIONS.map((action) => {
                  const isValidNow = action.validFrom.includes(currentInvoiceStatus);
                  const disabledReason = ' This action is not available for this invoice status.';
                  return (
                    <Tooltip
                      key={action.key}
                      label={`${action.label}. ${action.tooltip}${isValidNow ? '' : disabledReason}`}
                      hasArrow
                    >
                      <IconButton
                        aria-label={action.label}
                        icon={invoiceStatusActionIcon(action.key)}
                        size="md"
                        colorScheme={action.colorScheme}
                        variant={isValidNow ? 'solid' : 'outline'}
                        borderRadius="full"
                        boxShadow={isValidNow ? '0 8px 18px rgba(15, 23, 42, 0.14)' : 'none'}
                        transition="transform 140ms ease, box-shadow 140ms ease"
                        _hover={
                          isValidNow
                            ? {
                                transform: 'translateY(-1px)',
                                boxShadow: '0 12px 24px rgba(15, 23, 42, 0.18)',
                              }
                            : undefined
                        }
                        onClick={() => runStatusTransition(action.key)}
                        isDisabled={!isValidNow || !!statusActionLoading || !readData?.invoice_id}
                        isLoading={statusActionLoading === action.key}
                      />
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
                    ? 'Open invoice messages and internal notes. Use messages for the back-and-forth with the contractor about requested changes; use internal notes for admin-only context.'
                    : isVersionSnapshotRoute
                      ? 'Messages and internal notes are disabled for fixed invoice-version snapshots. Open the invoice-level current PDF viewer to act on the latest version.'
                      : 'Messages and internal notes are only available on the invoice-level current PDF viewer.'
                }
              >
                <IconButton
                  aria-label="Open invoice messages and internal notes"
                  size="md"
                  colorScheme="cyan"
                  variant={canOpenRevisionMessages ? 'solid' : 'outline'}
                  borderRadius="full"
                  boxShadow={canOpenRevisionMessages ? '0 8px 18px rgba(8, 145, 178, 0.18)' : 'none'}
                  icon={<ChatDots size={25} weight="bold" />}
                  onClick={openRevisionMessages}
                  isDisabled={!canOpenRevisionMessages}
                />
              </Tooltip>
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
                p="0"
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
      ? allowMultiple lets admins open only the sections they need
      ? no defaultIndex keeps all sections closed on first load
      ============================================================ */}

                <Accordion
                  allowMultiple
                  sx={{
                    '.chakra-accordion__button': {
                      color: 'blue.800',
                      fontWeight: 700,
                      borderRadius: '6px',
                      borderLeftWidth: '2px',
                      borderLeftStyle: 'solid',
                      borderLeftColor: 'transparent',
                      transition: 'background 180ms ease, border-color 180ms ease, color 180ms ease',
                    },
                    '.chakra-accordion__button:hover': {
                      color: 'blue.900',
                    },
                    '.chakra-accordion__button[aria-expanded="true"]': {
                      background: 'linear-gradient(180deg, rgba(49, 130, 206, 0.12) 0%, rgba(255, 255, 255, 0) 88%)',
                      borderLeftColor: 'blue.300',
                      color: 'blue.900',
                    },
                    '.chakra-accordion__panel': {
                      marginLeft: '12px',
                      paddingLeft: '12px',
                      borderLeftWidth: '2px',
                      borderLeftStyle: 'solid',
                      borderLeftColor: 'gray.100',
                    },
                  }}
                >
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

                    <AccordionPanel px="0" pt="3px">
                      <Flex gap="18px" align="center" wrap="wrap" mb="8px">
                        {(() => {
                          const statusCopy = invoiceStatusCopy(currentInvoiceStatus);
                          const technicalStatus = String(currentInvoiceStatus || '').trim() || 'unknown';
                          return (
                            <Tooltip label={`${statusCopy.hint} Technical status: ${technicalStatus}.`} hasArrow>
                              <Text fontSize="xs" fontWeight="bold" textTransform="uppercase">
                                Status: {statusCopy.label}
                              </Text>
                            </Tooltip>
                          );
                        })()}
                        {invoiceVersionLabel && (
                          <Text fontSize="xs" fontWeight="bold" textTransform="uppercase">
                            {invoiceVersionLabel}
                          </Text>
                        )}
                      </Flex>
                      <Box display="grid" gridTemplateColumns="1fr 1fr" columnGap="8px" rowGap="0">
                        {DI_FIELDS.map((f) => {
                          const raw = readData?.[f.valueKey];
                          if (f.hideWhenBlank && (raw == null || raw === '')) return null;

                          const display = f.formatter ? f.formatter(raw) : String(raw ?? '-');
                          const clickable = !f.disabled && !!f.pageKey && !!f.polygonKey;

                          return (
                            <FieldRow
                              key={f.key}
                              label={f.label}
                              value={display}
                              active={activeHighlightKey === f.key}
                              disabled={!clickable}
                              inline
                              onClick={
                                clickable
                                  ? () => {
                                      setShowPdf(true);
                                      setActiveHighlightKey(f.key);
                                    }
                                  : undefined
                              }
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
                        </Box>
                        <AccordionIcon />
                      </AccordionButton>
                    </h2>

                    <AccordionPanel px="0" pt="3px">
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
                        <Box display="flex" flexDirection="column" gap="1px">
                          <Box
                            display="grid"
                            gridTemplateColumns="minmax(220px, 1fr) 72px 96px 96px"
                            gap="8px"
                            px="10px"
                            py="0"
                          >
                            <Text fontSize="sm" opacity={0.6}>
                              description
                            </Text>
                            <Text fontSize="sm" opacity={0.6} textAlign="right">
                              qty
                            </Text>
                            <Text fontSize="sm" opacity={0.6} textAlign="right">
                              unit
                            </Text>
                            <Text fontSize="sm" opacity={0.6} textAlign="right">
                              amount
                            </Text>
                          </Box>
                          {sortedLineitems.map((li: any) => {
                            const seq = li.lineitem_seqno ?? li.seqno ?? '-';
                            const lineitemKey = li.id ?? seq;
                            const highlightKey = `lineitem_${lineitemKey}_desc`;
                            const clickable = li.ocr_description_page != null && li.ocr_description_polygon != null;

                            return (
                              <Box
                                key={String(lineitemKey)}
                                borderWidth="1px"
                                borderColor={activeHighlightKey === highlightKey ? 'blue.400' : 'transparent'}
                                borderRadius="md"
                                bg={activeHighlightKey === highlightKey ? 'blue.50' : 'transparent'}
                                px="10px"
                                py="3px"
                                role={clickable ? 'button' : undefined}
                                cursor={clickable ? 'pointer' : 'default'}
                                _hover={
                                  clickable
                                    ? {
                                        bg: activeHighlightKey === highlightKey ? 'blue.50' : 'gray.50',
                                        borderColor: activeHighlightKey === highlightKey ? 'blue.400' : 'gray.200',
                                      }
                                    : {}
                                }
                                onClick={
                                  clickable
                                    ? () => {
                                        setActiveHighlight({
                                          source: 'di',
                                          key: highlightKey,
                                          pageNumber: Number(li.ocr_description_page),
                                          polygon: li.ocr_description_polygon,
                                        });
                                        setShowPdf(true);
                                        setActiveHighlightKey(highlightKey);
                                      }
                                    : undefined
                                }
                              >
                                <Box
                                  display="grid"
                                  gridTemplateColumns="minmax(220px, 1fr) 72px 96px 96px"
                                  gap="8px"
                                  alignItems="baseline"
                                >
                                  <Text
                                    fontSize="sm"
                                    fontWeight={activeHighlightKey === highlightKey ? 'semibold' : 'normal'}
                                    noOfLines={1}
                                  >
                                    {String(li.ocr_description ?? '-')}
                                  </Text>
                                  <Text fontSize="sm" textAlign="right" noOfLines={1}>
                                    {li.ocr_quantity != null ? String(li.ocr_quantity) : '-'}
                                  </Text>
                                  <Text fontSize="sm" textAlign="right" noOfLines={1}>
                                    {li.ocr_unit_price != null ? fmtMoney(li.ocr_unit_price) : '-'}
                                  </Text>
                                  <Text fontSize="sm" textAlign="right" noOfLines={1}>
                                    {li.ocr_amount != null ? fmtMoney(li.ocr_amount) : '-'}
                                  </Text>
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
                            Product & Eligibility Codes
                          </Text>
                        </Box>
                        <AccordionIcon />
                      </AccordionButton>
                    </h2>

                    <AccordionPanel px="0" pt="3px">
                      {genAiError && (
                        <Text fontSize="xs" color="red.500" mb="8px">
                          {genAiError}
                        </Text>
                      )}

                      {!genAiError && classifierFields.length === 0 ? (
                        <Text fontSize="sm" opacity={0.7}>
                          No product or eligibility codes found.
                        </Text>
                      ) : (
                        <Box display="grid" gridTemplateColumns="1fr 1fr" columnGap="8px" rowGap="0">
                          {classifierFields.map((r: any) => {
                            const label = r.field_key || 'field';
                            const value = displayLocatedFieldValue(r);
                            const confidence =
                              r.confidence != null ? `confidence ${Number(r.confidence).toFixed(2)}` : '';
                            const clickable = r.page != null;

                            return (
                              <Box
                                key={r.id}
                                role={clickable ? 'button' : undefined}
                                cursor={clickable ? 'pointer' : 'default'}
                                px="10px"
                                py="2px"
                                borderRadius="md"
                                display="flex"
                                alignItems="baseline"
                                justifyContent="space-between"
                                gap="6px"
                                bg={
                                  activeHighlight?.source === 'classifier' && activeHighlight?.genaiId === Number(r.id)
                                    ? 'blue.50'
                                    : 'transparent'
                                }
                                _hover={clickable ? { bg: 'gray.50' } : undefined}
                                onClick={
                                  clickable
                                    ? () => {
                                        setActiveHighlight({
                                          source: 'classifier',
                                          genaiId: Number(r.id),
                                          pageNumber: Number(r.page),
                                          polygon: r.polygon ?? null,
                                        });
                                        setShowPdf(true);
                                      }
                                    : undefined
                                }
                              >
                                <Text fontSize="sm" opacity={0.7} flexShrink={0} noOfLines={1}>
                                  {label}
                                </Text>
                                <Text fontSize="sm" noOfLines={2} textAlign="right">
                                  {[value, confidence].filter(Boolean).join('  ')}
                                </Text>
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
                            Classified Upgrade Types
                          </Text>
                        </Box>
                        <AccordionIcon />
                      </AccordionButton>
                    </h2>

                    <AccordionPanel px="0" pt="3px">
                      {classifierUpgradeTypeRows.length === 0 ? (
                        <Text fontSize="sm" opacity={0.7}>
                          No upgrade types classified for this invoice.
                        </Text>
                      ) : (
                        <Box display="flex" flexDirection="column" gap="6px">
                          {classifierUpgradeTypeRows.map((r: any) => {
                            const meta = getInvoiceUpgradeTypeMeta(upgradeTypeKeyFor(r), r.upgrade_type_description);
                            const explanation = String(r.classification_explanation || '').trim();
                            const evidenceText = String(r.evidence_text || '').trim();
                            const confidence =
                              r.confidence != null ? `confidence ${Number(r.confidence).toFixed(0)}` : '';
                            const clickable = r.page != null;
                            const highlightKey = `classifier_upgrade_${r.id}`;
                            const isActive =
                              activeHighlight?.source === 'classifier' && activeHighlight?.key === highlightKey;

                            return (
                              <Box
                                key={r.id}
                                role={clickable ? 'button' : undefined}
                                cursor={clickable ? 'pointer' : 'default'}
                                px="10px"
                                py="6px"
                                borderRadius="md"
                                bg={isActive ? 'blue.50' : 'transparent'}
                                _hover={clickable ? { bg: isActive ? 'blue.50' : 'gray.50' } : undefined}
                                onClick={
                                  clickable
                                    ? () => {
                                        setActiveHighlight({
                                          source: 'classifier',
                                          key: highlightKey,
                                          pageNumber: Number(r.page),
                                          polygon: r.polygon ?? null,
                                        });
                                        setShowPdf(true);
                                      }
                                    : undefined
                                }
                              >
                                <Box
                                  display="grid"
                                  gridTemplateColumns="minmax(210px, 0.75fr) minmax(260px, 1.25fr) 100px"
                                  gap="8px"
                                  alignItems="baseline"
                                >
                                  <Text fontSize="sm" fontWeight={isActive ? 'semibold' : 'normal'} noOfLines={1}>
                                    {meta.label}
                                  </Text>
                                  <Text fontSize="sm" noOfLines={1}>
                                    {evidenceText || '-'}
                                  </Text>
                                  <Text fontSize="sm" textAlign="right" opacity={0.7} noOfLines={1}>
                                    {confidence}
                                  </Text>
                                </Box>
                                {explanation && (
                                  <Box mt="4px" pl="12px">
                                    <Text as="span" fontSize="sm" fontWeight="bold">
                                      Why classified:{' '}
                                    </Text>
                                    <Text as="span" fontSize="sm">
                                      {explanation}
                                    </Text>
                                  </Box>
                                )}
                                {evidenceText && (
                                  <Box mt="2px" pl="12px">
                                    <Text as="span" fontSize="sm" fontWeight="bold">
                                      Evidence:{' '}
                                    </Text>
                                    <Text as="span" fontSize="sm">
                                      {evidenceText}
                                    </Text>
                                  </Box>
                                )}
                              </Box>
                            );
                          })}
                        </Box>
                      )}
                    </AccordionPanel>
                  </AccordionItem>

                  {supportingDocumentEvidenceSections.length === 0 ? (
                    <AccordionItem borderTopWidth="1px" borderColor="gray.200">
                      <h2>
                        <AccordionButton px="0" py="6px" _hover={{ bg: 'transparent' }}>
                          <Box flex="1" textAlign="left">
                            <Text size="sm" fontWeight="bold">
                              Supporting documents
                            </Text>
                          </Box>
                          <AccordionIcon />
                        </AccordionButton>
                      </h2>

                      <AccordionPanel px="0" pt="8px">
                        <Text fontSize="sm" opacity={0.7}>
                          No supporting-document evidence stored for this invoice.
                        </Text>
                      </AccordionPanel>
                    </AccordionItem>
                  ) : (
                    supportingDocumentEvidenceSections.map((section) => {
                      return (
                        <AccordionItem key={section.key} borderTopWidth="1px" borderColor="gray.200">
                          <h2>
                            <AccordionButton px="0" py="6px" _hover={{ bg: 'transparent' }}>
                              <Box flex="1" textAlign="left" minW={0}>
                                <Flex align="center" gap="8px" wrap="wrap">
                                  <Text size="sm" fontWeight="bold" noOfLines={1}>
                                    Supporting document - {section.title}
                                  </Text>
                                </Flex>
                              </Box>
                              <AccordionIcon />
                            </AccordionButton>
                          </h2>

                          <AccordionPanel px="0" pt="8px">
                            <Accordion
                              allowMultiple
                              defaultIndex={[0, 1]}
                              sx={{
                                '& .chakra-accordion__button': {
                                  pl: '10px',
                                  pr: '8px',
                                },
                                '& .chakra-accordion__panel': {
                                  ml: '8px',
                                  pl: '10px',
                                },
                              }}
                            >
                              {section.groups.length > 0 && (
                                <AccordionItem borderTopWidth="1px" borderColor="gray.200">
                                  <h3>
                                    <AccordionButton py="6px" _hover={{ bg: 'transparent' }}>
                                      <Box flex="1" textAlign="left" minW={0}>
                                        <Flex align="center" gap="8px" wrap="wrap">
                                          <Text fontSize="sm" fontWeight="bold">
                                            Group
                                          </Text>
                                        </Flex>
                                      </Box>
                                      <AccordionIcon />
                                    </AccordionButton>
                                  </h3>
                                  <AccordionPanel px="0" pt="6px">
                                    <Box display="flex" flexDirection="column" gap="3px">
                                      {section.groups.map((group: any) => {
                                        const filenames = Array.isArray(group?.original_filenames)
                                          ? group.original_filenames.filter(Boolean).map(String)
                                          : [];
                                        const fields = Array.isArray(group?.located_fields) ? group.located_fields : [];
                                        const title = String(group?.group_label || '').trim();

                                        return (
                                          <Box
                                            key={String(group?.id || group?.group_label || 'supporting-doc-group')}
                                            px="10px"
                                            py="3px"
                                          >
                                            {(title && title !== section.title) || filenames.length > 0 ? (
                                              <Box
                                                display="grid"
                                                gridTemplateColumns="160px minmax(0, 1fr)"
                                                columnGap="8px"
                                                rowGap="2px"
                                                alignItems="baseline"
                                              >
                                                {title && title !== section.title && (
                                                  <>
                                                    <Text fontSize="sm" opacity={0.7} noOfLines={1}>
                                                      group
                                                    </Text>
                                                    <Text fontSize="sm" noOfLines={1}>
                                                      {title}
                                                    </Text>
                                                  </>
                                                )}
                                                {filenames.length > 0 && (
                                                  <>
                                                    <Text fontSize="sm" opacity={0.7} noOfLines={1}>
                                                      files
                                                    </Text>
                                                    <Text fontSize="sm" noOfLines={1}>
                                                      {filenames.join(', ')}
                                                    </Text>
                                                  </>
                                                )}
                                              </Box>
                                            ) : null}

                                            {fields.length > 0 && (
                                              <Box
                                                mt={
                                                  (title && title !== section.title) || filenames.length > 0
                                                    ? '3px'
                                                    : '0'
                                                }
                                                display="grid"
                                                gridTemplateColumns="160px minmax(0, 1fr)"
                                                columnGap="8px"
                                                rowGap="2px"
                                                alignItems="baseline"
                                              >
                                                {fields.map((field: any) => (
                                                  <React.Fragment
                                                    key={String(field?.id || `${group?.id}:${field?.field_key}`)}
                                                  >
                                                    <Text fontSize="sm" opacity={0.7} noOfLines={1}>
                                                      {String(field?.field_key || 'field')}
                                                    </Text>
                                                    <Text fontSize="sm" noOfLines={1}>
                                                      {field?.value_text != null
                                                        ? String(field.value_text)
                                                        : field?.value_json != null
                                                          ? JSON.stringify(field.value_json)
                                                          : 'not found'}
                                                    </Text>
                                                  </React.Fragment>
                                                ))}
                                              </Box>
                                            )}
                                          </Box>
                                        );
                                      })}
                                    </Box>
                                  </AccordionPanel>
                                </AccordionItem>
                              )}

                              {section.documents.map((doc: any) => {
                                const fields = Array.isArray(doc?.located_fields) ? doc.located_fields : [];
                                const findings = Array.isArray(doc?.visual_findings) ? doc.visual_findings : [];
                                const filename = String(doc?.original_filename || 'Unnamed file');

                                return (
                                  <AccordionItem
                                    key={String(doc?.id || doc?.storage_key || 'supporting-doc')}
                                    borderTopWidth="1px"
                                    borderColor="gray.200"
                                  >
                                    <h3>
                                      <AccordionButton py="6px" _hover={{ bg: 'transparent' }}>
                                        <Box flex="1" textAlign="left" minW={0}>
                                          <Text fontSize="sm" fontWeight="bold" noOfLines={1}>
                                            Uploaded file - {filename}
                                          </Text>
                                        </Box>
                                        <AccordionIcon />
                                      </AccordionButton>
                                    </h3>
                                    <AccordionPanel px="0" pt="6px">
                                      <Box px="10px" py="3px">
                                        <Flex justify="flex-end" gap="8px" mb="6px">
                                          <Tooltip label={`Show ${filename} in application`}>
                                            <IconButton
                                              aria-label={`Show ${filename} in application`}
                                              icon={<FrameCorners size={24} weight="bold" />}
                                              size="lg"
                                              variant="outline"
                                              colorScheme="green"
                                              onClick={() => showSupportingDocumentInViewer(doc)}
                                            />
                                          </Tooltip>
                                          <Tooltip label={`Open ${filename} in browser`}>
                                            <IconButton
                                              aria-label={`Open ${filename} in browser`}
                                              icon={<ArrowSquareOut size={24} weight="bold" />}
                                              size="lg"
                                              variant="outline"
                                              colorScheme="blue"
                                              onClick={() => openSupportingDocumentFile(doc)}
                                            />
                                          </Tooltip>
                                        </Flex>

                                        <Text fontSize="sm" fontWeight="bold" opacity={0.78} noOfLines={1}>
                                          File details
                                        </Text>
                                        <Box
                                          display="grid"
                                          gridTemplateColumns="160px minmax(0, 1fr)"
                                          columnGap="8px"
                                          rowGap="2px"
                                          alignItems="baseline"
                                          pl="12px"
                                          mt="2px"
                                        >
                                          <Text fontSize="sm" opacity={0.7} noOfLines={1}>
                                            details
                                          </Text>
                                          <Text fontSize="sm" noOfLines={1}>
                                            {[
                                              `size ${fmtBytes(doc?.byte_size)}`,
                                              doc?.classification_confidence != null
                                                ? `confidence ${String(doc.classification_confidence)}`
                                                : '',
                                              String(doc?.supporting_document_routing_quality || '').trim()
                                                ? `routing ${String(doc.supporting_document_routing_quality)}`
                                                : '',
                                            ]
                                              .filter(Boolean)
                                              .join('  ')}
                                          </Text>
                                        </Box>

                                        {fields.length > 0 && (
                                          <Box
                                            mt="3px"
                                            display="grid"
                                            gridTemplateColumns="160px minmax(0, 1fr)"
                                            columnGap="8px"
                                            rowGap="2px"
                                            alignItems="baseline"
                                            pl="12px"
                                          >
                                            {fields.map((field: any) => {
                                              const clickable = field?.page != null && field?.polygon != null;
                                              const isActive =
                                                activeHighlight?.source === 'supporting_document' &&
                                                activeHighlight?.supportingDocumentId === String(doc?.id) &&
                                                activeHighlight?.key ===
                                                  `supporting_field_${String(field?.id || field?.field_key || 'unknown')}`;
                                              const fieldValue =
                                                field?.value_text != null
                                                  ? String(field.value_text)
                                                  : field?.value_json != null
                                                    ? JSON.stringify(field.value_json)
                                                    : 'not found';
                                              const handleClick = clickable
                                                ? () => showSupportingDocumentInViewer(doc, field)
                                                : undefined;

                                              return (
                                                <React.Fragment key={String(field?.id || field?.field_key)}>
                                                  <Text
                                                    fontSize="sm"
                                                    opacity={0.7}
                                                    noOfLines={1}
                                                    cursor={clickable ? 'pointer' : 'default'}
                                                    bg={isActive ? 'red.50' : 'transparent'}
                                                    borderRadius="sm"
                                                    onClick={handleClick}
                                                  >
                                                    {String(field?.field_key || 'field')}
                                                  </Text>
                                                  <Text
                                                    fontSize="sm"
                                                    noOfLines={1}
                                                    cursor={clickable ? 'pointer' : 'default'}
                                                    bg={isActive ? 'red.50' : 'transparent'}
                                                    borderRadius="sm"
                                                    onClick={handleClick}
                                                    _hover={clickable ? { bg: 'gray.50' } : undefined}
                                                  >
                                                    {fieldValue}
                                                  </Text>
                                                </React.Fragment>
                                              );
                                            })}
                                          </Box>
                                        )}

                                        {findings.length > 0 && (
                                          <Box mt="10px" display="flex" flexDirection="column" gap="6px">
                                            {findings.map((finding: any) => {
                                              const rawRelevantText = finding?.relevant_text_seen;
                                              const relevantText = Array.isArray(rawRelevantText)
                                                ? rawRelevantText.filter(Boolean).join(', ')
                                                : rawRelevantText != null && rawRelevantText !== ''
                                                  ? typeof rawRelevantText === 'string'
                                                    ? rawRelevantText
                                                    : JSON.stringify(rawRelevantText)
                                                  : '';
                                              const findingType = String(finding?.finding_type || 'visual finding');
                                              const findingMeta = [
                                                finding?.page != null ? `page ${String(finding.page)}` : '',
                                                finding?.confidence != null
                                                  ? `confidence ${String(finding.confidence)}`
                                                  : '',
                                                String(finding?.legibility || '').trim()
                                                  ? `legibility ${String(finding.legibility)}`
                                                  : '',
                                              ]
                                                .filter(Boolean)
                                                .join('  ');

                                              return (
                                                <Box
                                                  key={String(
                                                    finding?.id || finding?.finding_seqno || finding?.summary,
                                                  )}
                                                  pb="6px"
                                                  _first={{ pt: 0 }}
                                                  _last={{ pb: 0 }}
                                                >
                                                  <Flex align="baseline" justify="space-between" gap="16px">
                                                    <Text fontSize="sm" fontWeight="bold" opacity={0.78} noOfLines={1}>
                                                      Visual findings - {findingType}
                                                    </Text>
                                                    {findingMeta && (
                                                      <Text fontSize="sm" opacity={0.7} noOfLines={1} textAlign="right">
                                                        {findingMeta}
                                                      </Text>
                                                    )}
                                                  </Flex>
                                                  <Box
                                                    display="grid"
                                                    gridTemplateColumns="160px minmax(0, 1fr)"
                                                    columnGap="8px"
                                                    rowGap="2px"
                                                    alignItems="baseline"
                                                    mt="2px"
                                                    pl="12px"
                                                  >
                                                    <Text fontSize="sm" opacity={0.7} noOfLines={1}>
                                                      summary
                                                    </Text>
                                                    <Text fontSize="sm" noOfLines={2}>
                                                      {String(finding?.summary || '')}
                                                    </Text>
                                                  </Box>
                                                  {relevantText && (
                                                    <Box
                                                      display="grid"
                                                      gridTemplateColumns="160px minmax(0, 1fr)"
                                                      columnGap="8px"
                                                      rowGap="2px"
                                                      alignItems="baseline"
                                                      mt="2px"
                                                      pl="12px"
                                                    >
                                                      <Text fontSize="sm" opacity={0.7} noOfLines={1}>
                                                        text seen
                                                      </Text>
                                                      <Text fontSize="sm" noOfLines={2}>
                                                        {relevantText}
                                                      </Text>
                                                    </Box>
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
                              })}
                            </Accordion>
                          </AccordionPanel>
                        </AccordionItem>
                      );
                    })
                  )}

                  <AccordionItem borderTopWidth="1px" borderColor="gray.200">
                    <h2>
                      <AccordionButton px="0" py="6px" _hover={{ bg: 'transparent' }}>
                        <Box flex="1" textAlign="left">
                          <Text size="sm" fontWeight="bold">
                            Overall advice
                          </Text>
                        </Box>
                        <AccordionIcon />
                      </AccordionButton>
                    </h2>

                    <AccordionPanel px="0" pt="6px">
                      <Box px="10px" py="3px">
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
                          </Box>
                          <AccordionIcon />
                        </AccordionButton>
                      </h2>

                      <AccordionPanel px="0" pt="3px">
                        <Box px="10px" py="3px">
                          <Box display="grid" gridTemplateColumns="1fr 1fr" columnGap="8px" rowGap="0">
                            {[
                              ['Product reference', `AHRI ${fmtText(ahriProduct.ahri_reference_number)}`],
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
                                py="2px"
                                borderRadius="md"
                                display="flex"
                                alignItems="baseline"
                                justifyContent="space-between"
                                gap="6px"
                              >
                                <Text fontSize="sm" opacity={0.7} flexShrink={0}>
                                  {String(label)}
                                </Text>
                                <Text fontSize="sm" noOfLines={2} textAlign="right">
                                  {fmtText(value)}
                                </Text>
                              </Box>
                            ))}
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
                          </Box>
                          <AccordionIcon />
                        </AccordionButton>
                      </h2>

                      <AccordionPanel px="0" pt="8px">
                        <Box borderWidth="1px" borderColor="green.100" borderRadius="md" p="10px" bg="green.50">
                          <Flex align="center" gap="8px" mb="8px" wrap="wrap">
                            <StatusDot result="pass" />
                            <Badge colorScheme="green">Product reference</Badge>
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
                          </Box>
                          <AccordionIcon />
                        </AccordionButton>
                      </h2>

                      <AccordionPanel px="0" pt="8px">
                        <Box borderWidth="1px" borderColor="cyan.100" borderRadius="md" p="10px" bg="cyan.50">
                          <Flex align="center" gap="8px" mb="8px" wrap="wrap">
                            <StatusDot result="pass" />
                            <Badge colorScheme="cyan">Product reference</Badge>
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

                  {ohpaProduct && (
                    <AccordionItem borderTopWidth="1px" borderColor="gray.200">
                      <h2>
                        <AccordionButton px="0" py="6px" _hover={{ bg: 'transparent' }}>
                          <Box flex="1" textAlign="left">
                            <Text size="sm" fontWeight="bold">
                              OHPA BC product-list match
                            </Text>
                          </Box>
                          <AccordionIcon />
                        </AccordionButton>
                      </h2>

                      <AccordionPanel px="0" pt="8px">
                        <Box borderWidth="1px" borderColor="orange.100" borderRadius="md" p="10px" bg="orange.50">
                          <Flex align="center" gap="8px" mb="8px" wrap="wrap">
                            <StatusDot result="pass" />
                            <Badge colorScheme="orange">Product reference</Badge>
                            {ohpaSource?.source_description && (
                              <Badge colorScheme="gray" variant="subtle" textTransform="none">
                                {String(ohpaSource.source_description)}
                              </Badge>
                            )}
                            <Text fontSize="xs" opacity={0.75}>
                              AHRI {fmtText(ohpaProduct.ahri_reference_number)}
                            </Text>
                          </Flex>

                          <Box display="grid" gridTemplateColumns="1fr 1fr" gap="8px">
                            {[
                              ['AHRI reference', ohpaProduct.ahri_reference_number],
                              ['Brand', ohpaProduct.brand],
                              ['Outdoor model', ohpaProduct.model_number],
                              ['Indoor model(s)', ohpaProduct.indoor_model_numbers],
                              ['Furnace model', ohpaProduct.furnace_model_number],
                              ['Product group', ohpaProduct.product_group],
                              ['AHRI type', ohpaProduct.ahri_type],
                              ['Ducting / configuration', ohpaProduct.ducting_configuration],
                              ['Model status', ohpaProduct.model_status],
                              ['Series name', ohpaProduct.series_name],
                              ['Rated capacity 47 F', ohpaProduct.rated_capacity_47f],
                              ['Rated capacity 95 F', ohpaProduct.rated_capacity_95f],
                              ['Capacity maintenance %', ohpaProduct.capacity_maintenance_percent],
                              ['COP 5 F', ohpaProduct.cop_5f],
                              ['HSPF2 Region IV', ohpaProduct.hspf2_region_iv],
                              ['HSPF2 Region V', ohpaProduct.hspf2_region_v],
                              ['SEER2', ohpaProduct.seer2],
                            ].map(([label, value]) => (
                              <Box
                                key={String(label)}
                                px="10px"
                                py="8px"
                                borderRadius="md"
                                borderWidth="1px"
                                borderColor="orange.100"
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

                          <Box mt="10px" pt="8px" borderTopWidth="1px" borderColor="orange.100">
                            <Text fontSize="xs" fontWeight="bold" textTransform="uppercase" opacity={0.7} mb="4px">
                              Source
                            </Text>
                            <Text fontSize="sm">
                              {fmtText(ohpaSource?.source_description)}{' '}
                              {ohpaSource?.publishing_date ? `(published ${fmtDate(ohpaSource.publishing_date)})` : ''}
                            </Text>
                            <Text fontSize="xs" opacity={0.75} wordBreak="break-all">
                              OHPA source id: {fmtText(ohpaSource?.ohpa_source_id)}
                            </Text>
                            <Text fontSize="xs" opacity={0.75}>
                              Imported {fmtDate(ohpaSource?.completed_at)} with {fmtText(ohpaSource?.records_imported)}{' '}
                              rows.
                            </Text>
                            {ohpaSource?.source_url && (
                              <Text
                                as="a"
                                href={String(ohpaSource.source_url)}
                                target="_blank"
                                rel="noreferrer"
                                fontSize="xs"
                                color="orange.700"
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
                            Pre-existing case facts
                          </Text>
                        </Box>
                        <AccordionIcon />
                      </AccordionButton>
                    </h2>

                    <AccordionPanel px="0" pt="3px">
                      {genAiError && (
                        <Text fontSize="xs" color="red.500" mb="8px">
                          {genAiError}
                        </Text>
                      )}

                      {!genAiError && codeFields.length === 0 ? (
                        <Text fontSize="sm" opacity={0.7}>
                          No pre-existing case facts found.
                        </Text>
                      ) : (
                        <Box display="grid" gridTemplateColumns="1fr 1fr" columnGap="8px" rowGap="0">
                          {codeFields.map((r: any) => {
                            const label = r.field_key || 'field';
                            const value = displayLocatedFieldValue(r);

                            return <FieldRow key={r.id} label={label} value={value} disabled inline />;
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
                            <Text size="sm">Energy Savings Program Rule Advice</Text>
                          </Box>
                          <AccordionIcon />
                        </AccordionButton>
                      </h2>
                      <AccordionPanel px="0" pt="8px">
                        <Text fontSize="sm" opacity={0.7}>
                          No upgrade-type advice rows found.
                        </Text>
                      </AccordionPanel>
                    </AccordionItem>
                  ) : (
                    upgradeTypeGroups.map((group) => {
                      const meta = getInvoiceUpgradeTypeMeta(group.upgradeTypeKey, group.description);

                      return (
                        <AccordionItem key={group.upgradeTypeKey} borderTopWidth="1px" borderColor="gray.200">
                          <h2>
                            <AccordionButton px="0" py="8px" _hover={{ bg: 'transparent' }}>
                              <Flex flex="1" align="center" gap="8px" textAlign="left" minW={0}>
                                <Box minW={0}>
                                  <Text fontSize="md" lineHeight="1.25" fontWeight="bold" noOfLines={1}>
                                    {meta.label} - Fields & Rules
                                  </Text>
                                </Box>
                                <InvoiceUpgradeTypeTile
                                  upgradeTypeKey={group.upgradeTypeKey}
                                  description={group.description}
                                  size={30}
                                />
                              </Flex>
                              <AccordionIcon />
                            </AccordionButton>
                          </h2>

                          <AccordionPanel px="0" pt="4px">
                            <Accordion allowMultiple defaultIndex={[0, 1]}>
                              <AccordionItem borderTopWidth="1px" borderColor="gray.200">
                                <h3>
                                  <AccordionButton px="10px" py="5px" _hover={{ bg: 'transparent' }}>
                                    <Box flex="1" textAlign="left">
                                      <Text fontSize="sm" fontWeight="bold">
                                        Located fields
                                      </Text>
                                    </Box>
                                    <AccordionIcon />
                                  </AccordionButton>
                                </h3>

                                <AccordionPanel px="10px" pt="3px" pb="6px">
                                  {genAiError && (
                                    <Text fontSize="xs" color="red.500" mb="8px">
                                      {genAiError}
                                    </Text>
                                  )}
                                  {group.fields.length === 0 ? (
                                    <Text fontSize="sm" opacity={0.7}>
                                      No located fields for this upgrade type.
                                    </Text>
                                  ) : (
                                    <Box display="grid" gridTemplateColumns="1fr 1fr" columnGap="8px" rowGap="0">
                                      {group.fields.map((r: any) => {
                                        const label = r.field_key || 'field';
                                        const value = displayLocatedFieldValue(r);
                                        const highlightKey = `found_${r.id}`;
                                        const confidence =
                                          r.confidence != null ? `confidence ${Number(r.confidence).toFixed(0)}` : '';
                                        const clickable = r.page != null;

                                        return (
                                          <FieldRow
                                            key={r.id}
                                            label={label}
                                            value={[value, confidence].filter(Boolean).join('  ')}
                                            active={activeHighlightKey === highlightKey}
                                            disabled={!clickable}
                                            inline
                                            onClick={
                                              clickable
                                                ? () => {
                                                    setActiveHighlight({
                                                      source: 'genai',
                                                      genaiId: Number(r.id),
                                                      pageNumber: Number(r.page),
                                                      polygon: r.polygon ?? null,
                                                    });
                                                    setShowPdf(true);
                                                    setActiveHighlightKey(highlightKey);
                                                  }
                                                : undefined
                                            }
                                          />
                                        );
                                      })}
                                    </Box>
                                  )}
                                </AccordionPanel>
                              </AccordionItem>

                              <AccordionItem borderTopWidth="1px" borderColor="gray.200">
                                <h3>
                                  <AccordionButton px="10px" py="5px" _hover={{ bg: 'transparent' }}>
                                    <Box flex="1" textAlign="left">
                                      <Text fontSize="sm" fontWeight="bold">
                                        Rules
                                      </Text>
                                    </Box>
                                    <AccordionIcon />
                                  </AccordionButton>
                                </h3>

                                <AccordionPanel px="10px" pt="3px" pb="6px">
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
                                    <Box display="flex" flexDirection="column" gap="6px">
                                      {group.rulechecks.map((r: any) => {
                                        const title = ruleDisplayTitle(r);
                                        const sourceLabel = ruleSourceLabel(r);
                                        const expected = r.expected_text ?? r.expected ?? '';
                                        const calc = r.calculation ?? '';
                                        const reason = r.reason_and_likely_causes ?? '';
                                        const evText = r.evidence_text ?? '';
                                        const confidence =
                                          r.confidence != null ? `confidence ${Number(r.confidence).toFixed(0)}` : '';

                                        return (
                                          <Box
                                            key={r.id ?? `${r.source_engine}-${r.rule_number}-${r.rule_key}`}
                                            px="10px"
                                            py="2px"
                                            borderRadius="md"
                                          >
                                            <Box
                                              display="grid"
                                              gridTemplateColumns="18px minmax(180px, 1fr) 160px"
                                              gap="8px"
                                              alignItems="baseline"
                                            >
                                              <StatusDot result={r.rule_result} />
                                              <Text fontSize="sm" fontWeight="semibold" noOfLines={1}>
                                                {title}
                                              </Text>
                                              <Text fontSize="sm" opacity={0.7} textAlign="right" noOfLines={1}>
                                                {[sourceLabel, confidence].filter(Boolean).join('  ')}
                                              </Text>
                                            </Box>

                                            {expected && (
                                              <Box mt="2px" pl="26px">
                                                <Text as="span" fontSize="sm" fontWeight="bold">
                                                  Expected:{' '}
                                                </Text>
                                                <Text as="span" fontSize="sm">
                                                  {String(expected)}
                                                </Text>
                                              </Box>
                                            )}
                                            {calc && (
                                              <Box mt="2px" pl="26px">
                                                <Text as="span" fontSize="sm" fontWeight="bold">
                                                  Calculation:{' '}
                                                </Text>
                                                <Text as="span" fontSize="sm">
                                                  {String(calc)}
                                                </Text>
                                              </Box>
                                            )}
                                            {reason && (
                                              <Box mt="2px" pl="26px">
                                                <Text as="span" fontSize="sm" fontWeight="bold">
                                                  Reason:{' '}
                                                </Text>
                                                <Text as="span" fontSize="sm">
                                                  {String(reason)}
                                                </Text>
                                              </Box>
                                            )}
                                            {evText && (
                                              <Box mt="2px" pl="26px">
                                                <Text as="span" fontSize="sm" fontWeight="bold">
                                                  Evidence:{' '}
                                                </Text>
                                                <Text as="span" fontSize="sm">
                                                  {String(evText)}
                                                </Text>
                                              </Box>
                                            )}
                                          </Box>
                                        );
                                      })}
                                    </Box>
                                  )}
                                </AccordionPanel>
                              </AccordionItem>
                            </Accordion>
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
                                            setShowPdf(true);
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
                                    setShowPdf(true);
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
                              <Text size="sm">Product & Eligibility Codes</Text>
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

                          {!genAiError && classifierFields.length === 0 && (
                            <Text fontSize="sm" opacity={0.7}>
                              No product or eligibility codes found.
                            </Text>
                          )}

                          <Box display="grid" gridTemplateColumns="1fr 1fr" gap="8px">
                            {classifierFields.map((r: any) => {
                              const label = r.field_key || 'field';
                              const value = displayLocatedFieldValue(r);
                              const meta = [r.confidence != null ? `conf ${Number(r.confidence).toFixed(2)}` : null]
                                .filter(Boolean)
                                .join(' - ');
                              const clickable = r.page != null;

                              return (
                                <Box
                                  key={r.id}
                                  role={clickable ? 'button' : undefined}
                                  cursor={clickable ? 'pointer' : 'default'}
                                  px="10px"
                                  py="8px"
                                  mb="6px"
                                  borderRadius="md"
                                  borderWidth="1px"
                                  borderColor={
                                    activeHighlight?.source === 'classifier' &&
                                    activeHighlight?.genaiId === Number(r.id)
                                      ? 'blue.400'
                                      : 'orange.200'
                                  }
                                  bg={
                                    activeHighlight?.source === 'classifier' &&
                                    activeHighlight?.genaiId === Number(r.id)
                                      ? 'blue.50'
                                      : 'orange.50'
                                  }
                                  _hover={clickable ? { bg: 'gray.50', borderColor: 'gray.300' } : undefined}
                                  onClick={
                                    clickable
                                      ? () => {
                                          setActiveHighlight({
                                            source: 'classifier',
                                            genaiId: Number(r.id),
                                            pageNumber: Number(r.page),
                                            polygon: r.polygon ?? null,
                                          });
                                          setShowPdf(true);
                                        }
                                      : undefined
                                  }
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
                              <Text size="sm">Pre-existing case facts</Text>
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
                              No pre-existing case facts found.
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
                                    setShowPdf(true);
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

                            return (
                              <Box
                                key={r.id ?? `${r.source_engine}-${r.rule_number}-${r.rule_key}`}
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

                  <AccordionItem borderTopWidth="1px" borderColor="gray.200">
                    <h2>
                      <AccordionButton px="0" py="6px" _hover={{ bg: 'transparent' }}>
                        <Box flex="1" textAlign="left">
                          <Text size="sm" fontWeight="bold">
                            Possible Supporting Documents
                          </Text>
                        </Box>
                        <AccordionIcon />
                      </AccordionButton>
                    </h2>

                    <AccordionPanel px="0" pt="3px">
                      {supportingDocumentTypeGroups.length === 0 ? (
                        <Text fontSize="sm" opacity={0.7}>
                          No supporting-document type mappings are configured for the detected upgrade types.
                        </Text>
                      ) : (
                        <Box display="flex" flexDirection="column" gap="6px">
                          {supportingDocumentTypeGroups.map((group: any) => {
                            const types = Array.isArray(group?.supporting_document_types)
                              ? group.supporting_document_types
                              : [];
                            const title = String(
                              group?.upgrade_type_description ||
                                getInvoiceUpgradeTypeMeta(String(group?.upgrade_type_key || 'common')).label,
                            );

                            return (
                              <Box
                                key={String(group?.invoice_upgrade_type_id || group?.upgrade_type_key || 'group')}
                                borderRadius="md"
                                px="10px"
                                py="2px"
                              >
                                <Flex align="center" gap="8px" mb="2px" wrap="wrap">
                                  <Text fontSize="sm" fontWeight="bold" noOfLines={1}>
                                    {title}
                                  </Text>
                                  <InvoiceUpgradeTypeTile
                                    upgradeTypeKey={String(group?.upgrade_type_key || 'common')}
                                    description={group?.upgrade_type_description}
                                    size={24}
                                  />
                                  <Text fontSize="sm" opacity={0.7}>
                                    {types.length} configured
                                  </Text>
                                </Flex>

                                {types.length === 0 ? (
                                  <Text fontSize="sm" opacity={0.7}>
                                    No supporting document types mapped to this upgrade type.
                                  </Text>
                                ) : (
                                  <Box pl="12px">
                                    {types.map((typeRow: any) => (
                                      <Text
                                        key={String(
                                          typeRow?.supporting_document_type_id || typeRow?.type_key || 'type',
                                        )}
                                        fontSize="sm"
                                        noOfLines={1}
                                      >
                                        {String(typeRow?.description || typeRow?.type_key || 'Unknown type')}
                                      </Text>
                                    ))}
                                  </Box>
                                )}
                              </Box>
                            );
                          })}
                        </Box>
                      )}
                    </AccordionPanel>
                  </AccordionItem>
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
                  overflow="auto"
                  p="0"
                  bg="transparent"
                >
                  <Box position="relative" width="100%">
                    {/* ============================================================
        SECTION 07.07 - PDF TOOLBAR
        PURPOSE: Page nav + zoom/fit/rotate + open
        ============================================================ */}

                    <Box
                      display="flex"
                      alignItems="center"
                      justifyContent="space-between"
                      gap="10px"
                      mb="10px"
                      p="0"
                      bg="transparent"
                      flexWrap="wrap"
                    >
                      <Flex align="center" gap="5px" flexWrap="wrap">
                        <Tooltip label="Previous page" hasArrow>
                          <IconButton
                            aria-label="Previous page"
                            icon={<CaretLeft size={18} weight="bold" />}
                            size="sm"
                            variant="ghost"
                            borderRadius="full"
                            onClick={() => setActivePageNumber((p) => Math.max(1, p - 1))}
                            isDisabled={activePageNumber <= 1}
                          />
                        </Tooltip>

                        <Text fontSize="xs" opacity={0.7} fontWeight="semibold">
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
                            width: 46,
                            padding: '4px 6px',
                            border: '1px solid #E2E8F0',
                            borderRadius: 999,
                            background: 'white',
                            fontSize: 12,
                            textAlign: 'center',
                          }}
                        />

                        <Text fontSize="xs" opacity={0.7}>
                          / {numPages || '-'}
                        </Text>

                        <Tooltip label="Next page" hasArrow>
                          <IconButton
                            aria-label="Next page"
                            icon={<CaretRight size={18} weight="bold" />}
                            size="sm"
                            variant="ghost"
                            borderRadius="full"
                            onClick={() => setActivePageNumber((p) => Math.min(numPages || p + 1, p + 1))}
                            isDisabled={!!numPages && activePageNumber >= numPages}
                          />
                        </Tooltip>
                      </Flex>

                      <Flex align="center" gap="5px" flexWrap="wrap">
                        <Tooltip label="Zoom out" hasArrow>
                          <IconButton
                            aria-label="Zoom out"
                            icon={<MagnifyingGlassMinus size={18} weight="bold" />}
                            size="sm"
                            variant="ghost"
                            borderRadius="full"
                            onClick={() => setZoom((z) => Math.max(0.5, +(z - 0.1).toFixed(2)))}
                          />
                        </Tooltip>

                        <Text fontSize="xs" minW="44px" textAlign="center" fontWeight="semibold" opacity={0.75}>
                          {Math.round(zoom * 100)}%
                        </Text>

                        <Tooltip label="Zoom in" hasArrow>
                          <IconButton
                            aria-label="Zoom in"
                            icon={<MagnifyingGlassPlus size={18} weight="bold" />}
                            size="sm"
                            variant="ghost"
                            borderRadius="full"
                            onClick={() => setZoom((z) => Math.min(3.0, +(z + 0.1).toFixed(2)))}
                          />
                        </Tooltip>

                        <Tooltip label="Fit width" hasArrow>
                          <IconButton
                            aria-label="Fit width"
                            icon={<CornersOut size={18} weight="bold" />}
                            size="sm"
                            colorScheme={fitMode === 'width' ? 'blue' : 'gray'}
                            variant={fitMode === 'width' ? 'solid' : 'ghost'}
                            borderRadius="full"
                            onClick={() => {
                              setFitMode('width');
                              setZoom(1.0);
                            }}
                          />
                        </Tooltip>

                        <Tooltip label="Fit page" hasArrow>
                          <IconButton
                            aria-label="Fit page"
                            icon={<FrameCorners size={18} weight="bold" />}
                            size="sm"
                            colorScheme={fitMode === 'page' ? 'blue' : 'gray'}
                            variant={fitMode === 'page' ? 'solid' : 'ghost'}
                            borderRadius="full"
                            onClick={() => {
                              setFitMode('page');
                              setZoom(1.0);
                            }}
                          />
                        </Tooltip>

                        <Tooltip label="Rotate clockwise" hasArrow>
                          <IconButton
                            aria-label="Rotate clockwise"
                            icon={<ArrowClockwise size={18} weight="bold" />}
                            size="sm"
                            variant="ghost"
                            borderRadius="full"
                            onClick={() => setRotate((r) => (r + 90) % 360)}
                          />
                        </Tooltip>

                        <Tooltip label={`Open ${viewerFilename} in browser`} hasArrow>
                          <IconButton
                            aria-label={`Open ${viewerFilename} in browser`}
                            icon={<ArrowSquareOut size={18} weight="bold" />}
                            size="sm"
                            variant="ghost"
                            borderRadius="full"
                            onClick={() => {
                              if (!viewerUrl) return;
                              window.open(viewerUrl, '_blank', 'noopener,noreferrer');
                            }}
                            isDisabled={!viewerUrl}
                          />
                        </Tooltip>
                      </Flex>
                    </Box>

                    {/* ============================================================
    SECTION 07.08 - PDF DOCUMENT + OVERLAY RENDER (DYNAMIC)
    PURPOSE: Render the PDF page + draw polygon overlay
    NOTES:
    ? ONLY ONE Document should exist in this pane
    ? We render Document only when pdfUrl is present
    ============================================================ */}

                    {pdfUrlError && !viewerUrl && (
                      <Text fontSize="sm" color="red.500" mb="8px">
                        Image URL error: {pdfUrlError}
                      </Text>
                    )}

                    {/* 2) loading state */}
                    {!viewerUrl && !pdfUrlError && (
                      <Text fontSize="sm" opacity={0.7} mb="8px">
                        Loading image URL...
                      </Text>
                    )}

                    {viewerUrl && viewerIsImage && (
                      <Box
                        position="relative"
                        width={`${overlayWidthPx}px`}
                        height={`${overlayHeightPx}px`}
                        mx="auto"
                        bg="white"
                        boxShadow="0 10px 26px rgba(15, 23, 42, 0.18)"
                        borderRadius="sm"
                        overflow="hidden"
                      >
                        <svg
                          width={overlayWidthPx}
                          height={overlayHeightPx}
                          style={{ position: 'absolute', top: 0, left: 0, zIndex: 10, pointerEvents: 'none' }}
                        >
                          {shouldShowActivePolygon && (
                            <polygon points={svgPolygonPoints} fill="rgba(255,0,0,0.20)" stroke="red" strokeWidth={2} />
                          )}
                        </svg>
                        <Box
                          as="img"
                          src={viewerUrl}
                          alt={viewerFilename}
                          width={`${renderWidthPx}px`}
                          height="auto"
                          display="block"
                          onLoad={(event: any) => {
                            const img = event.currentTarget as HTMLImageElement;
                            if (!img?.naturalWidth || !img?.naturalHeight) return;
                            setNumPages(1);
                            setViewerPageMetaByPage({
                              1: {
                                width: img.naturalWidth,
                                height: img.naturalHeight,
                                unit: 'pixel',
                              },
                            });
                          }}
                        />
                      </Box>
                    )}

                    {/* 3) render PDF only when url exists */}
                    {viewerUrl && viewerIsPdf && (
                      <Document
                        key={viewerUrl} // force reload when url changes
                        file={viewerUrl} // IMPORTANT: dynamic URL here
                        onLoadSuccess={({ numPages }) => setNumPages(numPages)}
                        onLoadError={(err) => console.error('PDF load error:', err)}
                      >
                        {/* Wrapper so SVG and Page share identical geometry */}
                        <Box
                          position="relative"
                          width={`${overlayWidthPx}px`}
                          height={`${overlayHeightPx}px`}
                          mx="auto"
                          bg="white"
                          boxShadow="0 10px 26px rgba(15, 23, 42, 0.18)"
                          borderRadius="sm"
                        >
                          {/* SVG overlay */}
                          <svg
                            width={overlayWidthPx}
                            height={overlayHeightPx}
                            style={{ position: 'absolute', top: 0, left: 0, zIndex: 10, pointerEvents: 'none' }}
                          >
                            {shouldShowActivePolygon && (
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
                              onLoadSuccess={(page: any) => {
                                if (!page?.getViewport) return;
                                const viewport = page.getViewport({ scale: 1 });
                                if (!viewport?.width || !viewport?.height) return;
                                setViewerPageMetaByPage((current) => ({
                                  ...current,
                                  [activePageNumber]: {
                                    width: Number(viewport.width) / 72,
                                    height: Number(viewport.height) / 72,
                                    unit: 'inch',
                                  },
                                }));
                              }}
                            />
                          </Box>
                        </Box>
                      </Document>
                    )}

                    <Text fontSize="xs" opacity={0.6} mt="8px">
                      Active highlight: {activeHighlight?.source ?? '-'}{' '}
                      {activeHighlight?.source === 'di'
                        ? activeHighlight?.key ?? '-'
                        : `${activeHighlight?.source ?? 'row'} ${activeHighlight?.genaiId ?? '-'}`}{' '}
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
    </Flex>
  );
};
