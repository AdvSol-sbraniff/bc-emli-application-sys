import { Box, Button, Heading, Text } from '@chakra-ui/react';
import React, { useEffect, useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { Document, Page, pdfjs } from "react-pdf";
import "react-pdf/dist/Page/AnnotationLayer.css";
import "react-pdf/dist/Page/TextLayer.css";

import workerSrc from "pdfjs-dist/build/pdf.worker.min.mjs?url";

pdfjs.GlobalWorkerOptions.workerSrc = workerSrc;


export const InvoiceVersionShowScreen = () => {

  // ============================
  // SECTION 1 — ROUTE PARAMS + NAVIGATE
  // - sessionId/invoiceId come from the page URL
  // - navigate() changes the URL when user clicks arrows
  // ============================

  const { sessionId, invoiceId, id } = useParams();
  const navigate = useNavigate();


  // ============================
  // SECTION 2 — STATE
  // - invoiceIds: list of current invoice IDs for session (drives nav bar)
  // - readData: payload for the selected invoice (header fields, pdf pointer, etc.)
  // ============================

const [invoiceIds, setInvoiceIds] = useState<string[]>([]);
const [readData, setReadData] = useState<any>(null);
const [readError, setReadError] = useState<string | null>(null);
const [numPages, setNumPages] = useState<number>(0);


useEffect(() => {


  // ============================
  // SECTION 3 — LOAD NAV LIST (invoiceIds)
  // - Calls Rails: /api/invoice_versions/sessions/:sessionId/current_invoices
  // - Result drives prev/next + "Invoice X of Y"
  // ============================

  const run = async () => {
    if (!sessionId) return;
    const resp = await fetch(`/api/sessions/${sessionId}/current_invoices`, {
      headers: { Accept: 'application/json' },
      credentials: 'include',
    });
    const json = await resp.json();
    setInvoiceIds(json.invoice_ids ?? []);
  };
  run();
}, [sessionId]);


// ============================
// SECTION 3B — LOAD READ PAYLOAD (readData)
// - Calls Rails: /api/invoice_versions/sessions/:sessionId/invoices/:invoiceId/read
// - Result drives header fields (and later PDF + lineitems)
// ============================
useEffect(() => {
  const run = async () => {
    if (!sessionId || !invoiceId) return;
    const resp = await fetch(
      `/api/sessions/${sessionId}/invoices/${invoiceId}/read`,
      { headers: { Accept: 'application/json' }, credentials: 'include' }
    );
    const json = await resp.json();
    setReadData(json.read ?? null);
  };
  run();
}, [sessionId, invoiceId]);


// ============================
// SECTION 3C — URL SANITY
// - If URL invoiceId is not in invoiceIds list, auto-redirect to the first real invoiceId
// ============================

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


  // ============================
  // SECTION 4 — NAV ACTIONS
  // - goPrev/goNext update the URL based on invoiceIds array + current invoiceId
  // ============================

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

  return (


    <Box p="16px" height="calc(100vh - 120px)" overflow="hidden">

    {/* ============================
        SECTION 5 — PAGE LAYOUT
        - outer height uses calc(100vh - headerPx) to avoid page scroll
        - column layout: title, navbar, then main split view
        ============================ */}

      <Box display="flex" flexDirection="column" height="100%">
        <Heading size="lg" mb="8px">
          Invoice Version (POC)
        </Heading>

        {/* Nav bar (stub) */}
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

          {/* optional tiny debug so you know routing is right */}
          <Text fontSize="xs" opacity={0.6} ml="12px">
            sessionId: {sessionId} | invoiceId: {invoiceId} | legacy id: {id}
          </Text>
        </Box>

        {/* Main area: left fields + right PDF */}

        {/* ============================
            SECTION 6 — MAIN SPLIT VIEW
            LEFT: header fields (and soon lineitems)
            RIGHT: pdf viewer (soon from storage_key)
            ============================ */}


        <Box display="flex" gap="16px" flex="1" minH={0}>

{/* ============================
    SECTION 6A — LEFT PANEL CONTAINER
    - Everything left-side MUST be inside a left <Box width="360px"...>
    - Right-side PDF stays in the flex="1" box
    ============================ */}

<Box
  width="360px"
  borderWidth="1px"
  borderRadius="md"
  p="12px"
  overflow="auto"
>
  <Text fontSize="sm">
    <b>Vendor:</b> {readData?.di_ocr_vendor_name ?? '-'}
  </Text>
  <Text fontSize="sm">
    <b>Invoice #:</b> {readData?.di_ocr_invoice_id ?? '-'}
  </Text>
  <Text fontSize="sm">
    <b>Invoice date:</b> {readData?.di_ocr_invoice_date ?? '-'}
  </Text>
  <Text fontSize="sm">
    <b>Total:</b> {readData?.di_ocr_invoice_total ?? '-'}
  </Text>
</Box>


{/* ============================
    SECTION 6B — RIGHT PANEL the pdf
    ============================ */}

<Box flex="1" minH={0} borderWidth="1px" borderRadius="md" overflow="auto">
  <Document
    file="https://stsbraniffvi128678601575.blob.core.windows.net/inv-pdfs-dev/sessions/1/pdfs/2/original.PDF?sp=r&st=2026-01-09T18:09:08Z&se=2026-04-01T01:24:08Z&spr=https&sv=2024-11-04&sr=b&sig=As6UnrCq86KEHqJHuFYJQfqUaOGyck4XrMvKk1u8yUw%3D"
    onLoadSuccess={({ numPages }) => console.log("PDF loaded, pages:", numPages)}
    onLoadError={(err) => console.error("PDF load error:", err)}
  >
    <Page pageNumber={1} />
  </Document>
</Box>




        </Box>
      </Box>
    </Box>
  );
};
