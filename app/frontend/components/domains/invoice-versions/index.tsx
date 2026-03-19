// /app/frontend/components/domains/invoice-versions/index.tsx
import { fmtDate, fmtMoney, fmtText } from "./display";

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
} from '@chakra-ui/react';
import { ThinBlueTitleBar } from '../../shared/base/thin-blue-title-bar';
import { Question } from '@phosphor-icons/react';


// ============================================================
// SECTION 00 — FILE OVERVIEW
// PURPOSE: Invoice read screen with left fields + PDF viewer + DI polygon highlight
// ============================================================

import React, { useEffect, useMemo, useRef, useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { Document, Page, pdfjs } from "react-pdf";
import "react-pdf/dist/Page/AnnotationLayer.css";
import "react-pdf/dist/Page/TextLayer.css";
import { useMst } from '../../../setup/root';

//import workerSrc from "pdfjs-dist/build/pdf.worker.min.mjs?url";
//pdfjs.GlobalWorkerOptions.workerSrc = workerSrc;
pdfjs.GlobalWorkerOptions.workerSrc = `https://unpkg.com/pdfjs-dist@${pdfjs.version}/build/pdf.worker.min.mjs`;

// ============================================================
// SECTION 01.01 — UI COMPONENTS
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
      role={disabled ? undefined : "button"}
      onClick={disabled ? undefined : onClick}
      px="10px"
      py="8px"
      mb="6px"
      borderRadius="md"
      borderWidth="1px"
      borderColor={active ? "blue.400" : "transparent"}
      bg={active ? "blue.50" : "transparent"}
      cursor={disabled ? "not-allowed" : "pointer"}
      opacity={disabled ? 0.6 : 1}
      _hover={
        disabled
          ? {}
          : {
              bg: active ? "blue.50" : "gray.50",
              borderColor: active ? "blue.400" : "gray.200",
            }
      }
      display="flex"
      flexDirection="column"
      gap="2px"
    >
      <Text fontSize="xs" opacity={0.7}>
        {label}
      </Text>
      <Text fontSize="sm" fontWeight={active ? "semibold" : "normal"} noOfLines={2}>
        {String(value)}
      </Text>
    </Box>
  );
};

const displayLocatedFieldValue = (row: any): string => {
  if (row?.value_text != null && row.value_text !== "") return String(row.value_text);
  if (row?.value_json != null) return JSON.stringify(row.value_json);
  if (row?.normalized_value != null && row.normalized_value !== "") return String(row.normalized_value);
  return "-";
};

// ============================================================
// SECTION 01.02 — UI COMPONENTS (STATUS DOT)
// PURPOSE: Small red/green/gray dot for pass/fail/unknown
// ============================================================

type StatusDotProps = { pass: boolean | null | undefined };

const StatusDot = ({ pass }: StatusDotProps) => {
  const bg =
    pass === true ? "green.400" :
    pass === false ? "red.400" :
    "red.400";

  return (
    <Box
      as="span"
      w="10px"
      h="10px"
      borderRadius="full"
      display="inline-block"
      bg={bg}
      flexShrink={0}
    />
  );
};

// ============================================================
// SECTION 02.02 — FIELD CATALOG
// PURPOSE: Single source of truth for left-panel rows + highlight mapping
// ============================================================

type FieldCatalogItem = {
  key: string;                    // unique key used in UI + highlight selector
  label: string;                  // left-panel label
  valueKey: string;               // readData field holding the value
  formatter?: (v: any) => string; // display formatter
  pageKey?: string;               // readData field holding page number
  polygonKey?: string;            // readData field holding polygon array/json
  disabled?: boolean;             // allow showing row but not clickable
};

const DI_FIELDS: FieldCatalogItem[] = [

  // ----------------------------
  // DI first class fields
  // ----------------------------
  {
    key: "invoice_id",    label: "Invoice #",    valueKey: "di_ocr_invoice_id",   formatter: fmtText,    pageKey: "di_ocr_invoice_id_page",    polygonKey: "di_ocr_invoice_id_polygon",
  },
  {
    key: "invoice_date",    label: "Invoice date",    valueKey: "di_ocr_invoice_date",    formatter: fmtDate,    pageKey: "di_ocr_invoice_date_page",    polygonKey: "di_ocr_invoice_date_polygon",
  },
  {
    key: "vendor_name",    label: "BUSINESS NAME",    valueKey: "di_ocr_vendor_name",    formatter: fmtText,
    pageKey: "di_ocr_vendor_name_page",    polygonKey: "di_ocr_vendor_name_polygon",
  },
  {
    key: "vendor_address",    label: "Vendor address",    valueKey: "di_ocr_vendor_address",    formatter: fmtText,
    pageKey: "di_ocr_vendor_address_page",    polygonKey: "di_ocr_vendor_address_polygon",
  },
  {
    key: "customer_name",    label: "Customer name",    valueKey: "di_ocr_customer_name",    formatter: fmtText,
    pageKey: "di_ocr_customer_name_page",    polygonKey: "di_ocr_customer_name_polygon",
  },
  {
    key: "billing_address",    label: "Billing address",    valueKey: "di_ocr_billing_address",    formatter: fmtText,
    pageKey: "di_ocr_billing_address_page",    polygonKey: "di_ocr_billing_address_polygon",
  },
  {
    key: "sub_total",    label: "Sub-total",    valueKey: "di_ocr_sub_total",    formatter: fmtMoney,
    pageKey: "di_ocr_sub_total_page",    polygonKey: "di_ocr_sub_total_polygon",
  },
  {
    key: "total_tax",    label: "Total tax",    valueKey: "di_ocr_total_tax",    formatter: fmtMoney,
    pageKey: "di_ocr_total_tax_page",    polygonKey: "di_ocr_total_tax_polygon",
  },
  {
    key: "invoice_total",    label: "Invoice total",    valueKey: "di_ocr_invoice_total",    formatter: fmtMoney,
    pageKey: "di_ocr_invoice_total_page",    polygonKey: "di_ocr_invoice_total_polygon",
  },
  {
    key: "amount_due",    label: "Amount due",    valueKey: "di_ocr_amount_due",    formatter: fmtMoney,
    pageKey: "di_ocr_amount_due_page",    polygonKey: "di_ocr_amount_due_polygon",
  },

];





// ============================================================
// SECTION 03.01 — SCREEN COMPONENT
// PURPOSE: Main screen component + hooks + render
// ============================================================
export const InvoiceVersionShowScreen = () => {

// ============================================================
// SECTION 04.01 — ROUTE PARAMS
// PURPOSE: Read sessionId/invoiceId from URL + create navigate() helper
// ============================================================


const { sessionId, invoiceId, id } = useParams();
const navigate = useNavigate();
const { userStore } = useMst();
const currentUserId = (userStore as any)?.currentUser?.id ? String((userStore as any).currentUser.id) : '';


// ============================================================
// SECTION 05.01 — STATE
// PURPOSE: invoiceIds + readData + pdf viewer state + highlight state
// ============================================================

const [showPdf, setShowPdf] = useState<boolean>(true);

const [invoiceIds, setInvoiceIds] = useState<string[]>([]);
const [readData, setReadData] = useState<any>(null);
const [readError, setReadError] = useState<string | null>(null);
const [numPages, setNumPages] = useState<number>(0);

const [activeHighlightKey, setActiveHighlightKey] = useState<string>('invoice_id');
const [activePageNumber, setActivePageNumber] = useState<number>(1);

// We’ll render Page at an explicit width (in px) so we can map coords accurately
const pdfWrapRef = useRef<HTMLDivElement | null>(null);
const [pageWidthPx, setPageWidthPx] = useState<number>(900); // default fallback
const [pdfPaneHeightPx, setPdfPaneHeightPx] = useState<number>(700);

type FitMode = "width" | "page";

const [zoom, setZoom] = useState<number>(1.0);         // 1.0 = 100%
const [fitMode, setFitMode] = useState<FitMode>("width");
const [rotate, setRotate] = useState<number>(0);       // degrees: 0, 90, 180, 270
const [pageInput, setPageInput] = useState<string>("1");

const [pdfUrl, setPdfUrl] = useState<string | null>(null);
const [pdfUrlError, setPdfUrlError] = useState<string | null>(null);

const [codeFields, setCodeFields] = useState<any[]>([]);
const [codeFieldsError, setCodeFieldsError] = useState<string | null>(null);

const {
  isOpen: isHelpOpen,
  onOpen: onHelpOpen,
  onClose: onHelpClose,
} = useDisclosure();

// ============================================================
// SECTION 05.01.01 — ACTIVE HIGHLIGHT (SINGLE SOURCE OF TRUTH)
// PURPOSE: BOTH header fields and GenAI rows set this (page + polygon)
// ============================================================

const [activeHighlight, setActiveHighlight] = useState<{
  source: "di" | "genai";
  key?: string;              // for DI: which field key
  genaiId?: number;          // for GenAI: which row id (optional)
  pageNumber: number | null; // 1-based
  polygon: any | null;       // DI-style 8-number polygon (or json string)
} | null>(null);


// ============================================================
// SECTION 05.02 — GENAI STATE
// PURPOSE: Store GenAI located fields (from /read_genai endpoint)
// ============================================================

const [genAiFields, setGenAiFields] = useState<any[]>([]);
const [genAiError, setGenAiError] = useState<string | null>(null);



// ============================================================
// SECTION 05.03 — GENAI RULECHECKS STATE
// PURPOSE: Store GenAI rulechecks (from /read_genai_rulechecks endpoint)
// ============================================================

const [genAiRulechecks, setGenAiRulechecks] = useState<any[]>([]);
const [genAiRulechecksError, setGenAiRulechecksError] = useState<string | null>(null);

// ============================================================
// SECTION 05.04 — LINEITEMS STATE
// PURPOSE: Store OCR lineitems (from /read response)
// ============================================================
const [lineitems, setLineitems] = useState<any[]>([]);
const [lineitemsError, setLineitemsError] = useState<string | null>(null);
const [isCreatingRevision, setIsCreatingRevision] = useState<boolean>(false);
const [revisionError, setRevisionError] = useState<string | null>(null);

// ============================================================
// SECTION 06.01 — LOAD INVOICE NAV LIST
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
// SECTION 06.01.02 — LOAD PDF SAS URL (STRICT + DEBUG)
// PURPOSE: Fetch signed SAS URL for current invoice PDF
// ============================================================
useEffect(() => {
  const run = async () => {
    if (!sessionId || !invoiceId) return;

    try {
      setPdfUrlError(null);

      const resp = await fetch(
        `/api/claims/sessions/${sessionId}/invoices/${invoiceId}/pdf_url`,
        { headers: { Accept: "application/json" }, credentials: "include" }
      );

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

      const url = String(json?.sas_url ?? "").trim();
      if (!url) {
        setPdfUrl(null);
        setPdfUrlError(`pdf_url returned empty sas_url. full response: ${bodyText}`);
        return;
      }

      setPdfUrl(url);
    } catch (e: any) {
      setPdfUrl(null);
      setPdfUrlError(String(e?.message ?? e));
    }
  };

  run();
}, [sessionId, invoiceId]);


// ============================================================
// SECTION 06.02 — LOAD INVOICE READ DATA
// PURPOSE: Fetch invoice header fields + DI metadata used by viewer/highlights
// ============================================================

useEffect(() => {
  const run = async () => {
    if (!sessionId || !invoiceId) return;
    const resp = await fetch(
      `/api/claims/sessions/${sessionId}/invoices/${invoiceId}/read`,
      { headers: { Accept: 'application/json' }, credentials: 'include' }
    );
    const json = await resp.json();

setReadData(json.read ?? null);
setLineitems(Array.isArray(json.lineitems) ? json.lineitems : []);

  };
  run();
}, [sessionId, invoiceId]);


// ============================================================
// SECTION 06.02.01 — LOAD GENAI LOCATED FIELDS (+ optional rulechecks)
// PURPOSE: Fetch GenAI located fields for the current invoice_version
// ============================================================

useEffect(() => {
  const run = async () => {
    if (!sessionId || !invoiceId) return;

    try {
      setGenAiError(null);

      const resp = await fetch(
        `/api/claims/sessions/${sessionId}/invoices/${invoiceId}/read_genai`,
        { headers: { Accept: "application/json" }, credentials: "include" }
      );

      if (!resp.ok) {
        const txt = await resp.text();
        setGenAiFields([]);
        setGenAiError(`read_genai failed (${resp.status}): ${txt}`);
        return;
      }

      const json = await resp.json();

      // ============================================================
      // SECTION 06.02.01.01 — LOCATED FIELDS
      // ============================================================
setGenAiFields(Array.isArray(json?.located_fields) ? json.located_fields : []);
setCodeFields(Array.isArray(json?.code_located_fields) ? json.code_located_fields : []);

      // ============================================================
      // SECTION 06.02.01.10 — RULECHECKS (ONLY IF PRESENT)
      // ============================================================
      if ("rulechecks" in (json ?? {})) {
        setGenAiRulechecks(Array.isArray(json?.rulechecks) ? json.rulechecks : []);
        setGenAiRulechecksError(null);
      }

    } catch (e: any) {
      setGenAiFields([]);
      setGenAiError(`read_genai error: ${String(e?.message ?? e)}`);
    }
  };

  run();
}, [sessionId, invoiceId]);


// ============================================================
// SECTION 06.03 — URL SANITY / AUTO-REDIRECT
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


const idxRaw = invoiceIds.indexOf(invoiceId ?? '');
const idx = idxRaw >= 0 ? idxRaw : 0;


// ============================================================
// SECTION 06.04 — PDF PANE SIZE OBSERVER
// PURPOSE: Measure PDF container width/height so fit/zoom math stays correct
// ============================================================
useEffect(() => {
  // If PDF is hidden, do nothing (and importantly: detach any prior observer).
  if (!showPdf) return;

  const el = pdfWrapRef.current;
  if (!el) return;

  const MAX_PDF_WIDTH = 750;

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

// ============================================================
// SECTION 06.05 — NAV ACTIONS
// PURPOSE: Prev/Next invoice navigation (updates URL)
// ============================================================


  const goPrev = () => {
    if (!sessionId) return;
    if (idx <= 0) return;
    navigate(`/sessions/${sessionId}/invoices/${invoiceIds[idx - 1]}/read`);
  };

  const goNext = () => {
    if (!sessionId) return;
    if (idx >= invoiceIds.length - 1) return;
    navigate(`/sessions/${sessionId}/invoices/${invoiceIds[idx + 1]}/read`);
  };

  const openRevisionEditor = (revisionRequestId: string, invoiceVersionId: string) => {
    const params = new URLSearchParams();
    params.set('id', revisionRequestId);
    params.set('invoice_version_id', invoiceVersionId);
    if (invoiceId) params.set('invoice_id', String(invoiceId));
    if (sessionId) params.set('session_id', String(sessionId));
    if (readData?.session_created_at) params.set('session_created_at', String(readData.session_created_at));
    if (readData?.contractor_business_name) params.set('contractor_business_name', String(readData.contractor_business_name));
    if (readData?.created_at) params.set('invoice_version_created_at', String(readData.created_at));
    if (readData?.invoice_versionno !== null && readData?.invoice_versionno !== undefined) {
      params.set('invoice_versionno', String(readData.invoice_versionno));
    }
    if (readData?.di_ocr_invoice_id) params.set('di_ocr_invoice_id', String(readData.di_ocr_invoice_id));
    const url = `/revision-request-editor?${params.toString()}`;
    window.open(url, '_blank', 'noopener,noreferrer');
  };

  const openDraftRevision = async () => {
    setRevisionError(null);

    const invoiceVersionId = String(readData?.id || id || '').trim();
    if (!invoiceVersionId) {
      setRevisionError('Could not determine invoice_version_id for this screen.');
      return;
    }

    if (!currentUserId) {
      setRevisionError('Could not determine current user for requester_id.');
      return;
    }

    const genAiAdvice = String(readData?.genai_admin_advice ?? '').trim();
    const passFail = readData?.genai_all_rulechecks_pass_flag === true ? 'PASS' : 'FAIL';
    const conf = readData?.genai_overall_confidence;

    const draftText = genAiAdvice
      ? `Overall (GenAI)\n\n${passFail} • conf ${conf ?? 0}\n\n${genAiAdvice}`
      : [
          `Draft revision request for invoice version ${readData?.invoice_versionno ?? '—'}.`,
          'Please review OCR/AI findings and update this request before sending.',
          'Expected contractor action: upload corrected invoice details and respond to this request.',
        ].join('\n');

    setIsCreatingRevision(true);
    try {
      // Reuse existing OPEN revision request for this invoice_version if present.
      if (invoiceId) {
        const lookupParams = new URLSearchParams();
        lookupParams.set('invoice_id', String(invoiceId));
        lookupParams.set('sort', 'revision_request_updated_at:desc');
        lookupParams.set('page', '1');
        lookupParams.set('per', '200');

        const lookupResp = await fetch(`/api/claims/admin/revision_requests?${lookupParams.toString()}`, {
          method: 'GET',
          headers: { Accept: 'application/json' },
          credentials: 'include',
        });

        if (lookupResp.ok) {
          const lookupJson = await lookupResp.json().catch(() => ({}));
          const rows = Array.isArray(lookupJson?.rows) ? lookupJson.rows : [];
          const existing = rows.find((r: any) =>
            String(r?.invoice_version_id || '') === invoiceVersionId &&
            String(r?.revision_request_status || '').toUpperCase() === 'OPEN' &&
            !!r?.revision_request_id
          );

          if (existing?.revision_request_id) {
            openRevisionEditor(String(existing.revision_request_id), invoiceVersionId);
            return;
          }
        }
      }

      const resp = await fetch('/api/claims/admin/revision_requests', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
        credentials: 'include',
        body: JSON.stringify({
          invoice_version_id: invoiceVersionId,
          requester_id: currentUserId,
          status: 'OPEN',
          request_text: draftText,
          response_text: '',
          closed_at: null,
        }),
      });

      const data = await resp.json().catch(() => ({}));
      if (!resp.ok) {
        throw new Error(data?.error || data?.message || `Create failed (${resp.status}).`);
      }

      const createdId = String(data?.id || '').trim();
      if (!createdId) throw new Error('Create succeeded but no revision request id returned.');
      openRevisionEditor(createdId, invoiceVersionId);
    } catch (e: any) {
      setRevisionError(e?.message || 'Failed to create revision request.');
    } finally {
      setIsCreatingRevision(false);
    }
  };

// ============================================================
// SECTION 06.06 — ACTIVE HIGHLIGHT RESOLVER
// PURPOSE: Lookup active field config → (pageNumber + polygon)
// ============================================================

const activeField = useMemo(() => {
  return DI_FIELDS.find(f => f.key === activeHighlightKey) ?? null;
}, [activeHighlightKey]);

// ============================================================
// SECTION 06.06.01 — DEFAULT ACTIVE HIGHLIGHT (DI)
// PURPOSE: When DI field changes, set the *state* activeHighlight
// ============================================================

useEffect(() => {
  if (!readData || !activeField) return;
  if (!activeField.pageKey || !activeField.polygonKey) return;

  setActiveHighlight({
    source: "di",
    key: activeField.key,
    pageNumber: readData[activeField.pageKey],
    polygon: readData[activeField.polygonKey],
  });
}, [readData, activeField]);



// ============================================================
// SECTION 06.07 — SYNC ACTIVE PAGE TO HIGHLIGHT
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
// SECTION 06.07.01 — PDF RENDER GEOMETRY aka the renderWidthPx block
// PURPOSE: Compute render width/height for zoom + fit modes
// ============================================================
const renderWidthPx = useMemo(() => {
  if (!activePageMeta) return Math.floor(pageWidthPx * zoom);

  if (fitMode === "width") {
    return Math.floor(pageWidthPx * zoom);
  }

  // fitMode === "page": choose width based on available height
  // width = height * (pageAspectWidth/pageAspectHeight)
  const widthByHeight = pdfPaneHeightPx * (activePageMeta.width / activePageMeta.height);
  return Math.floor(Math.min(pageWidthPx, widthByHeight) * zoom);
}, [activePageMeta, fitMode, pageWidthPx, pdfPaneHeightPx, zoom]);


// ============================================================
// SECTION 06.07.02 — SVG POLYGON (INCHES → PIXELS)
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
    console.warn("Unexpected DI unit:", meta.unit);
    return null;
  }

  // poly could be jsonb coming as array or string; normalize:
  const arr = Array.isArray(poly) ? poly : (typeof poly === 'string' ? JSON.parse(poly) : null);
  if (!arr || arr.length !== 8) return null;

  const [x1,y1,x2,y2,x3,y3,x4,y4] = arr.map((n: any) => Number(n));

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

  return pts.map(([x,y]) => `${x.toFixed(2)},${y.toFixed(2)}`).join(' ');
}, [activeHighlight?.polygon, activePageMeta, renderWidthPx]);



// ============================================================
// SECTION 06.07.03 — OVERLAY HEIGHT SOURCE OF TRUTH  
// PURPOSE: Compute overlay height to match rendered PDF height
// ============================================================

const overlayHeightPx = useMemo(() => {
  if (!activePageMeta) return 1200;
  return renderWidthPx * (activePageMeta.height / activePageMeta.width);
}, [activePageMeta, renderWidthPx]);

// ============================================================
// SECTION 06.07.10 — SYNC PAGE INPUT TO ACTIVE PAGE
// PURPOSE: Keep the page textbox updated when page changes via
//          highlights, Prev/Next, or manual nav
// ============================================================
useEffect(() => {
  setPageInput(String(activePageNumber));
}, [activePageNumber]);

// ------------------------------------------------------------
// SECTION 06.08.01 — OVERLAY WIDTH SOURCE OF TRUTH
// PURPOSE: Keep SVG overlay width locked to the rendered PDF width
// ------------------------------------------------------------

const overlayWidthPx = renderWidthPx;


const renderHeightPx = useMemo(() => {
  if (!activePageMeta) return 1200;
  return renderWidthPx * (activePageMeta.height / activePageMeta.width);
}, [activePageMeta, renderWidthPx]);



// ============================================================
// SECTION 07.01 — MAIN RETURN
// PURPOSE: JSX layout tree (header + nav + split panes)
// ============================================================

return (
  <Flex as="main" direction="column" w="full" bg="greys.white" pb="24" minH="100vh">
    <ThinBlueTitleBar title="Invoices Admin - PDF Viewer (By Session)" />

<Container maxW="full" px={6} pb={4} flex="1" pt={6}>
      <Box display="flex" flexDirection="column" height="100%">

        {/* keep your existing content, but REMOVE your old <Heading ...>Admin Full Details</Heading>
            (BlueTitleBar replaces it) */}

    {/* ============================================================
        SECTION 07.02 — PAGE LAYOUT
        PURPOSE: Outer column layout: title, nav bar, main split view
        ============================================================ */}

      <Box display="flex" flexDirection="column" height="100%">




    {/* ============================================================
        SECTION 07.03 — NAV BAR
        PURPOSE: Prev/Next invoice navigation + position indicator
        ============================================================ */}
        <Box display="flex" alignItems="center" gap="8px" mb="12px">
          <Button size="sm" isDisabled={!sessionId || idx <= 0} onClick={goPrev}>
            ←
          </Button>

          <Text fontSize="sm" opacity={0.8}>
            Invoice {invoiceIds.length === 0 ? 0 : idx + 1} of {invoiceIds.length}
          </Text>

          <Button
            size="sm"
            isDisabled={!sessionId || invoiceIds.length === 0 || idx >= invoiceIds.length - 1}
            onClick={goNext}
          >
            →
          </Button>

<Button
  size="xs"
  variant="outline"
  onClick={() => setShowPdf(v => !v)}
>
  {showPdf ? "Hide PDF" : "Show PDF"}
</Button>

          <Tooltip label="Create a draft revision request from this invoice version">
            <Button
              size="xs"
              variant="outline"
              onClick={openDraftRevision}
              isLoading={isCreatingRevision}
            >
              Revision
            </Button>
          </Tooltip>

          <Button
            size="xs"
            variant="outline"
            onClick={() => {
              console.log('[STUB] Draft revision request', { invoice_version_id: id ?? null });
            }}
          >
            Lets Chat
          </Button>

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

        {revisionError && (
          <Box mb="8px">
            <Text fontSize="xs" color="red.700">{revisionError}</Text>
          </Box>
        )}

    {/* ============================================================
        SECTION 07.04 — MAIN SPLIT VIEW
        PURPOSE: Left fields + Right PDF viewer
        ============================================================ */}

        <Box display="flex" gap="16px" flex="1" minH={0}>


{/* ============================================================
    SECTION 07.05 — LEFT PANEL (ACCORDION WRAPPER)
    PURPOSE: Put header fields inside a collapsible accordion
    ============================================================ */}

<Box
  borderWidth="1px"
  borderRadius="md"
  p="12px"

  // IMPORTANT: overflow must NOT be "visible" for resize to show
  sx={{
    resize: "horizontal",
    overflow: "auto",
  }}

minW="360px"
maxW={showPdf ? "820px" : "100%"}
w={showPdf ? "520px" : "100%"}
flexShrink={0}
>

  {/* ============================================================
      SECTION 07.05.01 — FIELDS ACCORDION
      PURPOSE: Collapsible container for the DI header fields list
      NOTES:
      - allowToggle lets user collapse the open section
      - defaultIndex={[0]} keeps it open by default
      ============================================================ */}

<Accordion allowMultiple defaultIndex={[0, 1]}>



 {/* ============================================================
      SECTION 07.05.10 — ACCORDION ITEM: INVOICE HEADER FIELDS
      PURPOSE: Existing DI header FieldRows (clickable for polygon)
      ============================================================ */}
  <AccordionItem border="none">
    <h2>
      <AccordionButton px="0" py="6px" _hover={{ bg: "transparent" }}>
        <Box flex="1" textAlign="left">
          <Text size="sm">Invoice</Text>
        </Box>
        <AccordionIcon />
      </AccordionButton>
    </h2>

    <AccordionPanel px="0" pt="8px">

<Box display="grid" gridTemplateColumns="1fr 1fr" gap="8px">

      {DI_FIELDS.map((f) => {
        const raw = readData?.[f.valueKey];
        const display = f.formatter ? f.formatter(raw) : String(raw ?? "-");
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


{/* ============================================================
    SECTION 07.05.15 — ACCORDION ITEM: LINE ITEMS (OCR)
    PURPOSE: Show claims.lineitems + click to highlight polygon
    ============================================================ */}
<AccordionItem borderTopWidth="1px" borderColor="gray.200">
  <h2>
    <AccordionButton px="0" py="6px" _hover={{ bg: "transparent" }}>
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
  const seq = li.lineitem_seqno ?? li.seqno ?? "?";

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
      activeHighlight?.source === "di" &&
      activeHighlight?.key === `lineitem_${seq}_${opts.subKey}`;

    return (
      <FieldRow
        key={`${li.id ?? `li-${seq}`}-${opts.subKey}`}
        label={`Line ${seq} — ${opts.label}`}
        value={opts.value}
        active={isActive}
        disabled={!clickable}
        onClick={
          clickable
            ? () => {
                setActiveHighlight({
                  source: "di",
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
        subKey: "desc",
        label: "Description",
        value: li.ocr_description ?? "-",
        page: li.ocr_description_page,
        polygon: li.ocr_description_polygon,
      })}

      {makeRow({
        subKey: "qty",
        label: "Quantity",
        value: li.ocr_quantity != null ? String(li.ocr_quantity) : "-",
        page: li.ocr_quantity_page,
        polygon: li.ocr_quantity_polygon,
      })}

      {makeRow({
        subKey: "unit",
        label: "Unit price",
        value: li.ocr_unit_price != null ? fmtMoney(li.ocr_unit_price) : "-",
        page: li.ocr_unit_price_page,
        polygon: li.ocr_unit_price_polygon,
      })}

      {makeRow({
        subKey: "amt",
        label: "Amount",
        value: li.ocr_amount != null ? fmtMoney(li.ocr_amount) : "-",
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
      SECTION 07.05.20 — ACCORDION ITEM: GENAI LOCATED FIELDS
      PURPOSE: Simple display of /read_genai results (not clickable yet)
      ============================================================ */}
  <AccordionItem borderTopWidth="1px" borderColor="gray.200">
    <h2>
      <AccordionButton px="0" py="6px" _hover={{ bg: "transparent" }}>
        <Box flex="1" textAlign="left">
          <Text size="sm">Energy Savings Program</Text>
        </Box>
        <AccordionIcon />
      </AccordionButton>
    </h2>

    <AccordionPanel px="0" pt="8px">

      {/* ============================================================
          SECTION 07.05.21 — GENAI ERROR
          PURPOSE: show fetch error if endpoint fails
          ============================================================ */}
      {genAiError && (
        <Text fontSize="xs" color="red.500" mb="8px">
          {genAiError}
        </Text>
      )}

      {/* ============================================================
          SECTION 07.05.22 — GENAI EMPTY
          PURPOSE: show message when no rows returned
          ============================================================ */}
      {!genAiError && genAiFields.length === 0 && (
        <Text fontSize="sm" opacity={0.7}>
          No GenAI located fields found.
        </Text>
      )}

      {/* ============================================================
          SECTION 07.05.23 — GENAI LIST
          PURPOSE: minimal list: field_key + value + (page/confidence)
          ============================================================ */}
  <Box display="grid" gridTemplateColumns="1fr 1fr" gap="8px">

      {genAiFields.map((r: any) => {
        const label = `${r.field_key}${r.line_number != null ? ` (line ${r.line_number})` : ""}`;
        const value = displayLocatedFieldValue(r);

        const meta = [
          r.page != null ? `p${r.page}` : null,
          r.confidence != null ? `conf ${Number(r.confidence).toFixed(2)}` : null,
        ].filter(Boolean).join(" • ");

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
  activeHighlight?.source === "genai" && activeHighlight?.genaiId === Number(r.id)
    ? "blue.400"
    : "gray.200"
}
bg={
  activeHighlight?.source === "genai" && activeHighlight?.genaiId === Number(r.id)
    ? "blue.50"
    : "white"
}
  _hover={{ bg: "gray.50", borderColor: "gray.300" }}
  onClick={() => {
    // ============================================================
    // SECTION 07.05.23.01 — GENAI CLICK → SET ACTIVE HIGHLIGHT
    // PURPOSE: Move PDF to page + draw polygon using same overlay code
    // ============================================================
    setActiveHighlight({
      source: "genai",
      genaiId: Number(r.id),
      pageNumber: r.page != null ? Number(r.page) : null,
      polygon: r.polygon ?? null,
    });
  }}
>



            <Text fontSize="xs" opacity={0.7}>{label}</Text>
            <Text fontSize="sm" noOfLines={3}>{value}</Text>
            {meta && <Text fontSize="xs" opacity={0.6}>{meta}</Text>}
          </Box>




        );
      })}
</Box>
    </AccordionPanel>
  </AccordionItem>




<AccordionItem borderTopWidth="1px" borderColor="gray.200">
  <h2>
    <AccordionButton px="0" py="6px" _hover={{ bg: "transparent" }}>
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
      const label = `${r.field_key}${r.line_number != null ? ` (line ${r.line_number})` : ""}`;
      const value = displayLocatedFieldValue(r);

      const meta = [
        r.page != null ? `p${r.page}` : null,
        r.confidence != null ? `conf ${Number(r.confidence).toFixed(2)}` : null,
      ].filter(Boolean).join(" • ");

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
            activeHighlight?.source === "code" && activeHighlight?.genaiId === Number(r.id)
              ? "blue.400"
              : "gray.200"
          }
          bg={
            activeHighlight?.source === "code" && activeHighlight?.genaiId === Number(r.id)
              ? "blue.50"
              : "white"
          }
          _hover={{ bg: "gray.50", borderColor: "gray.300" }}
          onClick={() => {
            setActiveHighlight({
              source: "code" as any, // <-- see note below
              genaiId: Number(r.id),
              pageNumber: r.page != null ? Number(r.page) : null,
              polygon: r.polygon ?? null,
            });
          }}
        >
          <Text fontSize="xs" opacity={0.7}>{label}</Text>
          <Text fontSize="sm" noOfLines={3}>{value}</Text>
          {meta && <Text fontSize="xs" opacity={0.6}>{meta}</Text>}
        </Box>
      );
    })}

</Box>

  </AccordionPanel>
</AccordionItem>


  {/* ============================================================
      SECTION 07.05.30 — ACCORDION ITEM: GENAI RULECHECKS
      PURPOSE: Display rules from claims.invoice_version_rulechecks
      ============================================================ */}
  <AccordionItem borderTopWidth="1px" borderColor="gray.200">
    <h2>
      <AccordionButton px="0" py="6px" _hover={{ bg: "transparent" }}>
        <Box flex="1" textAlign="left">
          <Text size="sm">Rule Checks</Text>
        </Box>
        <AccordionIcon />
      </AccordionButton>
    </h2>

    <AccordionPanel px="0" pt="8px">


{/* ============================================================
    SECTION 07.05.30.05 — GENAI OVERALL SUMMARY (from /read)
    PURPOSE: Quiet summary at top of Rule Checks panel
    REQUIRES: readData includes these invoice_versions columns:
      - genai_overall_confidence
      - genai_all_rulechecks_pass_flag
      - genai_admin_advice
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
      bg={readData?.genai_all_rulechecks_pass_flag === true ? "green.400" : "red.400"}
    />

    <Text fontSize="xs" opacity={0.6}>
      {(readData?.genai_all_rulechecks_pass_flag === true ? "PASS" : "FAIL")} • conf{" "}
      {readData?.genai_overall_confidence ?? 0}
    </Text>
  </Flex>
</Flex>

  {String(readData?.genai_admin_advice ?? "").trim() ? (
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
        const num = r.rule_number != null ? Number(r.rule_number) : null;
        const title = `${num != null ? `Rule ${num}` : "Rule"} — ${String(r.rule_name ?? "")}`.trim();

        const pass =
          r.rule_pass_flag === true ? "PASS" :
          r.rule_pass_flag === false ? "FAIL" :
          "FAIL";

        const conf =
          r.confidence != null && r.confidence !== ""
            ? `conf ${Number(r.confidence).toFixed(0)}`
            : "";

        const meta = [pass, conf].filter(Boolean).join(" • ");

        // you said you want strings: expected/observed/calculation etc.
        const expected = r.expected_text ?? r.expected ?? "";
        const observed = r.observed_text ?? r.observed ?? "";
        const calc = r.calculation ?? "";
        const tol = r.tolerance_notes ?? "";
        const reason = r.reason_and_likely_causes ?? "";
        const evText = r.evidence_text ?? "";
        const evHint = r.evidence_hint ?? "";

        return (
          <Box
            key={r.id ?? `${r.rule_number}-${r.rule_name}`}
            px="10px"
            py="8px"
            mb="8px"
            borderRadius="md"
            borderWidth="1px"
            borderColor="gray.200"
            bg="white"
          >
<Flex align="center" gap="8px">
  <StatusDot pass={r.rule_pass_flag} />
  <Text fontSize="xs" opacity={0.7}>
    {title}
  </Text>
</Flex>

            {meta && (
              <Text fontSize="xs" opacity={0.6} mb="6px">
                {meta}
              </Text>
            )}

            {expected && (
              <Box mb="6px">
                <Text fontSize="xs" opacity={0.7}>expected</Text>
                <Text fontSize="sm" whiteSpace="pre-wrap">{String(expected)}</Text>
              </Box>
            )}

            {observed && (
              <Box mb="6px">
                <Text fontSize="xs" opacity={0.7}>observed</Text>
                <Text fontSize="sm" whiteSpace="pre-wrap">{String(observed)}</Text>
              </Box>
            )}

            {calc && (
              <Box mb="6px">
                <Text fontSize="xs" opacity={0.7}>calculation</Text>
                <Text fontSize="sm" whiteSpace="pre-wrap">{String(calc)}</Text>
              </Box>
            )}

            {tol && (
              <Box mb="6px">
                <Text fontSize="xs" opacity={0.7}>tolerance</Text>
                <Text fontSize="sm" whiteSpace="pre-wrap">{String(tol)}</Text>
              </Box>
            )}

            {reason && (
              <Box mb="6px">
                <Text fontSize="xs" opacity={0.7}>reason</Text>
                <Text fontSize="sm" whiteSpace="pre-wrap">{String(reason)}</Text>
              </Box>
            )}

            {(evText || evHint) && (
              <Box>
                <Text fontSize="xs" opacity={0.7}>evidence</Text>
                {evText && <Text fontSize="sm" whiteSpace="pre-wrap">{String(evText)}</Text>}
                {evHint && <Text fontSize="xs" opacity={0.6} whiteSpace="pre-wrap">{String(evHint)}</Text>}
              </Box>
            )}
          </Box>
        );
      })}
    </AccordionPanel>
  </AccordionItem>

  </Accordion>



</Box>




    {/* ============================================================
        SECTION 07.06 — RIGHT PANEL (PDF)
        PURPOSE: PDF viewer + overlay highlight + toolbar
        ============================================================ */}

{showPdf ? (
<Box
  ref={pdfWrapRef}
  flex="1"
  minW={0}
  minH={0}
  borderWidth="1px"
  borderRadius="md"
  overflow="auto"
  p="8px"
  bg="gray.50"
>
  <Box position="relative" width="100%">

    {/* ============================================================
        SECTION 07.07 — PDF TOOLBAR
        PURPOSE: Page nav + zoom/fit/rotate + open
        ============================================================ */}

<Box
  display="flex"
  alignItems="center"
  justifyContent="space-between"
  gap="10px"
  mb="8px"
  p="8px"
  borderWidth="1px"
  borderRadius="md"
>
  {/* Left: page navigation */}
  <Box display="flex" alignItems="center" gap="8px">
    <Button
      size="sm"
      onClick={() => setActivePageNumber(p => Math.max(1, p - 1))}
      isDisabled={activePageNumber <= 1}
    >
      Prev
    </Button>

    <Text fontSize="sm" opacity={0.8}>Page</Text>

    <Box
      as="input"
      value={pageInput}
      onChange={(e: any) => setPageInput(e.target.value)}
      onBlur={() => {
        const n = Number(pageInput);
        if (!Number.isFinite(n)) { setPageInput(String(activePageNumber)); return; }
        const clamped = Math.min(Math.max(1, Math.floor(n)), numPages || 1);
        setActivePageNumber(clamped);
      }}
      onKeyDown={(e: any) => {
        if (e.key === "Enter") (e.target as HTMLInputElement).blur();
      }}
      style={{
        width: 60,
        padding: "6px 8px",
        border: "1px solid #E2E8F0",
        borderRadius: 6,
      }}
    />

    <Text fontSize="sm" opacity={0.8}>
      / {numPages || "?"}
    </Text>

    <Button
      size="sm"
      onClick={() => setActivePageNumber(p => Math.min((numPages || p + 1), p + 1))}
      isDisabled={!!numPages && activePageNumber >= numPages}
    >
      Next
    </Button>
  </Box>

  {/* Right: zoom/fit/rotate/actions */}
  <Box display="flex" alignItems="center" gap="8px" flexWrap="wrap" justifyContent="flex-end">
    <Button size="sm" onClick={() => setZoom(z => Math.max(0.5, +(z - 0.1).toFixed(2)))}>
      −
    </Button>

    <Text fontSize="sm" minW="56px" textAlign="center">
      {Math.round(zoom * 100)}%
    </Text>

    <Button size="sm" onClick={() => setZoom(z => Math.min(3.0, +(z + 0.1).toFixed(2)))}>
      +
    </Button>

    <Button
      size="sm"
      variant={fitMode === "width" ? "solid" : "outline"}
      onClick={() => { setFitMode("width"); setZoom(1.0); }}
    >
      Fit width
    </Button>

    <Button
      size="sm"
      variant={fitMode === "page" ? "solid" : "outline"}
      onClick={() => { setFitMode("page"); setZoom(1.0); }}
    >
      Fit page
    </Button>

    <Button
      size="sm"
      onClick={() => setRotate(r => (r + 90) % 360)}
    >
      Rotate
    </Button>

    <Button
      size="sm"
      variant="outline"
onClick={() => {
  if (!pdfUrl) return;
  window.open(pdfUrl, "_blank", "noopener,noreferrer");
}}
    >
      Open
    </Button>
  </Box>
</Box>

{/* ============================================================
    SECTION 07.08 — PDF DOCUMENT + OVERLAY RENDER (DYNAMIC)
    PURPOSE: Render the PDF page + draw polygon overlay
    NOTES:
    - ONLY ONE Document should exist in this pane
    - We render Document only when pdfUrl is present
    ============================================================ */}

{/* 1) pdf_url error */}
{/* ============================================================
    SECTION 07.08.10 — DEBUG PDF URL
    PURPOSE: show whether pdfUrl is actually being set
   ============================================================ */}
<Text fontSize="xs" opacity={0.6} mb="6px">
  pdfUrl: {pdfUrl ? pdfUrl.slice(0, 140) + "..." : "(null)"} 
</Text>

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
    key={pdfUrl}                 // force reload when url changes
    file={pdfUrl}                // IMPORTANT: dynamic URL here
    onLoadSuccess={({ numPages }) => setNumPages(numPages)}
    onLoadError={(err) => console.error("PDF load error:", err)}
  >
    {/* Wrapper so SVG and Page share identical geometry */}
    <Box position="relative" width={`${overlayWidthPx}px`} height={`${overlayHeightPx}px`}>

      {/* SVG overlay */}
      <svg
        width={overlayWidthPx}
        height={overlayHeightPx}
        style={{ position: "absolute", top: 0, left: 0, zIndex: 10, pointerEvents: "none" }}
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
      <Box style={{ position: "absolute", top: 0, left: 0 }}>
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
  Active highlight: {activeHighlight?.source ?? "-"}{" "}
  {activeHighlight?.source === "di"
    ? (activeHighlight?.key ?? "-")
    : `genai ${activeHighlight?.genaiId ?? "-"}`}
  {" "} | page {activePageNumber} / {numPages || "?"} | unit {activePageMeta?.unit ?? "-"}
</Text>






        </Box>  {/* closes SECTION 07.06 inner <Box position="relative" width="100%"> */}
      </Box>    
) : null}
    </Box>      {/* ✅ ADD: closes SECTION 07.04 main split view <Box display="flex" ...> */}
  </Box>        {/* ✅ ADD: closes SECTION 07.02 page layout <Box display="flex" flexDirection="column" ...> */}
</Box>          {/* ✅ ADD THIS: closes the first Box inside Container (Box A) */}

</Container>    {/* ✅ THIS is the closecontainer line */}

<Drawer isOpen={isHelpOpen} placement="left" onClose={onHelpClose} size="xl">
  <DrawerOverlay />
  <DrawerContent>
    <DrawerCloseButton />
    <DrawerHeader>PDF Viewer Help</DrawerHeader>
    <DrawerBody>
      <Flex direction="column" gap={4}>
        <Box>
          <Heading size="sm" mb={2}>What This Screen Shows</Heading>
          <Text as="div" fontSize="sm">
            This screen shows the current invoice version for invoices in one session.
          </Text>
          <Text as="div" fontSize="sm" mt={1}>
            The left and right arrows move through the current invoices in that same session.
          </Text>
          <Text as="div" fontSize="sm" mt={1}>
            So you are not leaving the session. You are moving invoice by invoice inside the same group.
          </Text>
        </Box>

        <Box>
          <Heading size="sm" mb={2}>Why Session Grouping Matters</Heading>
          <Text as="div" fontSize="sm">
            Contractors work in sessions. Their invoice work is grouped by session.
          </Text>
          <Text as="div" fontSize="sm" mt={1}>
            Admins should view the same grouping so both sides are looking at work in the same way.
          </Text>
          <Text as="div" fontSize="sm" mt={1}>
            This keeps the contractor mental map and admin mental map aligned and reduces confusion.
          </Text>
        </Box>

        <Box>
          <Heading size="sm" mb={2}>Small vs Large Sessions</Heading>
          <Text as="div" fontSize="sm">
            If a session has only one invoice, the left and right navigation can feel a little odd.
          </Text>
          <Text as="div" fontSize="sm" mt={1}>
            That is expected because there is nothing else to move to.
          </Text>
          <Text as="div" fontSize="sm" mt={1}>
            For larger contractor organizations with many invoices in a session, this navigation is very useful.
          </Text>
          <Text as="div" fontSize="sm" mt={1}>
            It lets you review many related invoices quickly without jumping between unrelated screens.
          </Text>
        </Box>

        <Box>
          <Heading size="sm" mb={2}>Accordion Sections</Heading>
          <Text as="div" fontSize="sm">
            Invoice: OCR header fields like invoice number, date, vendor, customer, and totals.
          </Text>
          <Text as="div" fontSize="sm" mt={1}>
            Line Items: OCR line rows like description, quantity, unit price, and amount.
          </Text>
          <Text as="div" fontSize="sm" mt={1}>
            GenAI Located Fields: values found by AI with evidence and document location details.
          </Text>
          <Text as="div" fontSize="sm" mt={1}>
            Pre-existing info on file: known case data already in the system.
          </Text>
          <Text as="div" fontSize="sm" mt={1}>
            GenAI Rulechecks: rule-by-rule pass or fail, confidence, notes, and the overall AI summary/advice.
          </Text>
        </Box>

        <Box>
          <Heading size="sm" mb={2}>How This Relates To Rulesets</Heading>
          <Text as="div" fontSize="sm">
            The ruleset tells AI what to check and what output shape to return.
          </Text>
          <Text as="div" fontSize="sm" mt={1}>
            Because of that, ruleset changes directly affect what appears in GenAI Located Fields and GenAI Rulechecks.
          </Text>
          <Text as="div" fontSize="sm" mt={1}>
            Invoice and Line Items are OCR-driven sections, while the GenAI sections are ruleset-driven review sections.
          </Text>
        </Box>
      </Flex>
    </DrawerBody>
  </DrawerContent>
</Drawer>
</Flex>

  );
};
