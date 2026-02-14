import { fmtDate, fmtMoney, fmtText } from "./display";

import { Box, Button, Heading, Text, Flex, Container, Accordion, AccordionItem, AccordionButton, AccordionPanel, AccordionIcon } from '@chakra-ui/react';
import { BlueTitleBar } from '../../shared/base/blue-title-bar'; // adjust path


// ============================================================
// SECTION 00 — FILE OVERVIEW
// PURPOSE: Invoice read screen with left fields + PDF viewer + DI polygon highlight
// ============================================================

/*
import {
  Box,
  Button,
  Heading,
  Text,

  Accordion,
  AccordionItem,
  AccordionButton,
  AccordionPanel,
  AccordionIcon,
} from '@chakra-ui/react';
*/

import React, { useEffect, useMemo, useRef, useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { Document, Page, pdfjs } from "react-pdf";
import "react-pdf/dist/Page/AnnotationLayer.css";
import "react-pdf/dist/Page/TextLayer.css";

import workerSrc from "pdfjs-dist/build/pdf.worker.min.mjs?url";

pdfjs.GlobalWorkerOptions.workerSrc = workerSrc;


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
    key: "vendor_name",    label: "Vendor",    valueKey: "di_ocr_vendor_name",    formatter: fmtText,
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


// ============================================================
// SECTION 05.01 — STATE
// PURPOSE: invoiceIds + readData + pdf viewer state + highlight state
// ============================================================

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
  };
  run();
}, [sessionId, invoiceId]);


// ============================================================
// SECTION 06.02.01 — LOAD GENAI LOCATED FIELDS
// PURPOSE: Fetch GenAI located fields for the current invoice_version
// ENDPOINT: /api/sessions/:session_id/invoices/:invoice_id/read_genai
// ============================================================

useEffect(() => {
  const run = async () => {
    if (!sessionId || !invoiceId) return;

    try {
      setGenAiError(null);

      const resp = await fetch(
        `/api/claims/sessions/${sessionId}/invoices/${invoiceId}/read_genai`,
        { headers: { Accept: 'application/json' }, credentials: 'include' }
      );

      if (!resp.ok) {
        const txt = await resp.text();
        setGenAiFields([]);
        setGenAiError(`read_genai failed (${resp.status}): ${txt}`);
        return;
      }

      const json = await resp.json();
      setGenAiFields(json.located_fields ?? []);
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
  const el = pdfWrapRef.current;
  if (!el) return;

  const MAX_PDF_WIDTH = 950;

  const ro = new ResizeObserver(() => {
    const w = Math.max(300, Math.floor(el.clientWidth));
    const h = Math.max(300, Math.floor(el.clientHeight));
    setPageWidthPx(Math.min(w, MAX_PDF_WIDTH));
    setPdfPaneHeightPx(h);
  });

  ro.observe(el);
  return () => ro.disconnect();
}, []);

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

    {/* ============================================================
        SECTION 07.02 — PAGE LAYOUT
        PURPOSE: Outer column layout: title, nav bar, main split view
        ============================================================ */}

      <Box display="flex" flexDirection="column" height="100%">
<Heading size="lg" color="theme.blueAlt" mb="12px">
  Confirm Your Details
</Heading>



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


        </Box>

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
  width="360px"
  borderWidth="1px"
  borderRadius="md"
  p="12px"
  overflow="auto"
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
          <Heading size="sm">General Invoice Fields</Heading>
        </Box>
        <AccordionIcon />
      </AccordionButton>
    </h2>

    <AccordionPanel px="0" pt="8px">
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
          <Heading size="sm">Energy Savings Program Fields</Heading>
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
      {genAiFields.map((r: any) => {
        const label = `${r.field_key}${r.line_number != null ? ` (line ${r.line_number})` : ""}`;

        const value =
          (r.normalized_value != null && r.normalized_value !== "")
            ? String(r.normalized_value)
            : (r.value_text != null && r.value_text !== "")
              ? String(r.value_text)
              : (r.value_json != null)
                ? JSON.stringify(r.value_json)
                : "-";

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

    </AccordionPanel>
  </AccordionItem>

  </Accordion>



</Box>




    {/* ============================================================
        SECTION 07.06 — RIGHT PANEL (PDF)
        PURPOSE: PDF viewer + overlay highlight + toolbar
        ============================================================ */}

<Box
  ref={pdfWrapRef}
  flex="1"
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
      onClick={() => window.open(
        "https://stsbraniffvi128678601575.blob.core.windows.net/inv-pdfs-dev/sessions/1/pdfs/2/original.PDF?sp=r&st=2026-01-09T18:09:08Z&se=2026-04-01T01:24:08Z&spr=https&sv=2024-11-04&sr=b&sig=As6UnrCq86KEHqJHuFYJQfqUaOGyck4XrMvKk1u8yUw%3D",
        "_blank",
        "noopener,noreferrer"
      )}
    >
      Open
    </Button>
  </Box>
</Box>

    {/* ============================================================
        SECTION 07.08 — PDF DOCUMENT + OVERLAY RENDER
        PURPOSE: Render the PDF page and draw the DI polygon overlay
        ============================================================ */}

    <Document
      file="https://stsbraniffvi128678601575.blob.core.windows.net/inv-pdfs-dev/sessions/1/pdfs/2/original.PDF?sp=r&st=2026-01-09T18:09:08Z&se=2026-04-01T01:24:08Z&spr=https&sv=2024-11-04&sr=b&sig=As6UnrCq86KEHqJHuFYJQfqUaOGyck4XrMvKk1u8yUw%3D"
      onLoadSuccess={({ numPages }) => setNumPages(numPages)}
      onLoadError={(err) => console.error("PDF load error:", err)}
    >

      {/* ============================================================
          SECTION 07.09 — PAGE WRAPPER GEOMETRY + SVG OVERLAY
          PURPOSE: Keep SVG overlay and react-pdf Page in identical coordinate space
          ============================================================ */}

      {/* Wrapper so SVG and Page share same geometry */}
<Box position="relative" width={`${overlayWidthPx}px`} height={`${overlayHeightPx}px`}>
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
{/*  ============================================================
   SECTION 07.09.01 — FORCE PAGE RERENDER ON ZOOM/ROTATE/PAGE
PURPOSE: react-pdf sometimes caches the canvas; key forces remount
 ============================================================ */}

<Page
  key={`p${activePageNumber}-w${renderWidthPx}-r${rotate}`}
  pageNumber={activePageNumber}
  width={renderWidthPx}
  rotate={rotate}
/>

        </Box>
      </Box>
    </Document>

    <Text fontSize="xs" opacity={0.6} mt="8px">
      Active highlight: {activeHighlightKey} | page {activePageNumber} / {numPages || "?"} | unit {activePageMeta?.unit ?? "-"}
    </Text>
  </Box>
</Box>





        </Box>
      </Box>
    </Flex>

  );
};
