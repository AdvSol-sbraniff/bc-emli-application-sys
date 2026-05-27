import {
  Accordion,
  AccordionButton,
  AccordionIcon,
  AccordionItem,
  AccordionPanel,
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
  Heading,
  IconButton,
  Modal,
  ModalBody,
  ModalCloseButton,
  ModalContent,
  ModalFooter,
  ModalHeader,
  ModalOverlay,
  Spinner,
  Text,
  Tooltip,
  useDisclosure,
  useToast,
} from '@chakra-ui/react';
import { Question } from '@phosphor-icons/react';
import React, { useEffect, useMemo, useRef, useState } from 'react';
import { Document, Page, pdfjs } from 'react-pdf';
import 'react-pdf/dist/Page/AnnotationLayer.css';
import 'react-pdf/dist/Page/TextLayer.css';
import { useLocation, useNavigate, useParams } from 'react-router-dom';
import { ThinBlueTitleBar } from '../../shared/base/thin-blue-title-bar';
import {
  getInvoiceUpgradeTypeMeta,
  INVOICE_UPGRADE_TYPE_FILTER_ORDER,
  InvoiceUpgradeTypeTile,
} from '../../shared/claims/invoice-upgrade-type-visual';
import { fmtDate, fmtMoney, fmtText } from '../invoice-versions/display';

pdfjs.GlobalWorkerOptions.workerSrc = `https://unpkg.com/pdfjs-dist@${pdfjs.version}/build/pdf.worker.min.mjs`;

type FieldRowProps = {
  label: string;
  value: unknown;
  active?: boolean;
  disabled?: boolean;
  onClick?: () => void;
};

type RuleResult = 'pass' | 'info' | 'warn' | 'fail' | null | undefined;
type FitMode = 'width' | 'page';

const FieldRow = ({ label, value, active, disabled, onClick }: FieldRowProps) => (
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
    <Text fontSize="sm" fontWeight={active ? 'semibold' : 'normal'} noOfLines={3}>
      {String(value ?? '-')}
    </Text>
  </Box>
);

const normalizeResult = (result: unknown): RuleResult => {
  const value = String(result ?? '')
    .trim()
    .toLowerCase();
  return value === 'pass' || value === 'info' || value === 'warn' || value === 'fail' ? value : null;
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
  if (normalized === 'pass') return 'pass: no requested action.';
  if (normalized === 'info') return 'info: helpful context, not a requested fix.';
  if (normalized === 'warn') return 'warn: verification may be needed.';
  if (normalized === 'fail') return 'fail: correction or follow-up is needed.';
  return 'unknown: rule result was not recognized.';
};

const StatusDot = ({ result }: { result: unknown }) => (
  <Tooltip label={resultTooltip(result)} hasArrow placement="top">
    <Box
      as="span"
      w="10px"
      h="10px"
      borderRadius="full"
      display="inline-block"
      bg={resultDotColor(result)}
      flexShrink={0}
    />
  </Tooltip>
);

const ruleDisplayTitle = (rulecheck: any) => {
  const num = rulecheck.rule_number != null ? Number(rulecheck.rule_number) : null;
  const sourceEngine = String(rulecheck.source_engine ?? '').toLowerCase();
  const prefix =
    sourceEngine === 'code'
      ? `Code Rule ${num ?? ''}`.trim()
      : `${num != null ? `Rule ${num}` : 'Rule'}`;

  return `${prefix} - ${String(rulecheck.rule_name ?? '')}`.trim();
};

const ruleSourceLabel = (rulecheck: any) => {
  const sourceEngine = String(rulecheck.source_engine ?? '').toLowerCase();
  if (sourceEngine === 'code') return 'code';
  if (sourceEngine === 'genai') return 'genai';
  return sourceEngine || '';
};

const DI_FIELDS = [
  {
    key: 'invoice_id',
    label: 'Invoice #',
    valueKey: 'di_ocr_invoice_id',
    pageKey: 'di_ocr_invoice_id_page',
    polygonKey: 'di_ocr_invoice_id_polygon',
    formatter: fmtText,
  },
  {
    key: 'invoice_date',
    label: 'Invoice date',
    valueKey: 'di_ocr_invoice_date',
    pageKey: 'di_ocr_invoice_date_page',
    polygonKey: 'di_ocr_invoice_date_polygon',
    formatter: fmtDate,
  },
  {
    key: 'vendor_name',
    label: 'Vendor',
    valueKey: 'di_ocr_vendor_name',
    pageKey: 'di_ocr_vendor_name_page',
    polygonKey: 'di_ocr_vendor_name_polygon',
    formatter: fmtText,
  },
  {
    key: 'customer_name',
    label: 'Customer',
    valueKey: 'di_ocr_customer_name',
    pageKey: 'di_ocr_customer_name_page',
    polygonKey: 'di_ocr_customer_name_polygon',
    formatter: fmtText,
  },
  {
    key: 'invoice_total',
    label: 'Invoice total',
    valueKey: 'di_ocr_invoice_total',
    pageKey: 'di_ocr_invoice_total_page',
    polygonKey: 'di_ocr_invoice_total_polygon',
    formatter: fmtMoney,
  },
  {
    key: 'amount_due',
    label: 'Amount due',
    valueKey: 'di_ocr_amount_due',
    pageKey: 'di_ocr_amount_due_page',
    polygonKey: 'di_ocr_amount_due_polygon',
    formatter: fmtMoney,
  },
];

const displayLocatedFieldValue = (row: any): string => {
  if (row?.value_text != null && row.value_text !== '') return String(row.value_text);
  if (row?.value_json != null) return JSON.stringify(row.value_json);
  return '-';
};

const fieldUpgradeTypeKey = (row: any) => String(row?.upgrade_type_key || 'common');

const upgradeTypeSortValue = (upgradeTypeKey: string) => {
  if (upgradeTypeKey === 'common') return -1;
  const index = INVOICE_UPGRADE_TYPE_FILTER_ORDER.indexOf(upgradeTypeKey as any);
  return index === -1 ? Number.MAX_SAFE_INTEGER : index;
};

const upgradeTypeDescriptionFor = (row: any) => {
  const upgradeTypeKey = fieldUpgradeTypeKey(row);
  return row?.upgrade_type_description || getInvoiceUpgradeTypeMeta(upgradeTypeKey).label;
};

const invoiceStatusLabel = (status: unknown): string => {
  const value = String(status ?? '').trim();
  if (!value) return 'unknown';
  if (value === 'genai_complete') return 'genai_complete - contractor reviewing';
  return value;
};

const statusColor = (status: unknown): string => {
  const value = String(status || '').toLowerCase();
  if (value === 'genai_complete') return 'blue';
  if (value === 'admin_review_inbox' || value === 'in_review') return 'yellow';
  if (value === 'contractor_revision_inbox') return 'orange';
  if (value === 'approved_pending' || value === 'approved_paid') return 'green';
  if (value === 'ineligible' || value.endsWith('_failed')) return 'red';
  return 'gray';
};

export default function ContractorInvoiceReviewScreen() {
  const { sessionId, invoiceId } = useParams();
  const navigate = useNavigate();
  const location = useLocation();
  const toast = useToast();
  const fileInputRef = useRef<HTMLInputElement | null>(null);
  const pdfWrapRef = useRef<HTMLDivElement | null>(null);
  const { isOpen: isHelpOpen, onOpen: onHelpOpen, onClose: onHelpClose } = useDisclosure();
  const { isOpen: isSubmitWarningOpen, onOpen: onSubmitWarningOpen, onClose: onSubmitWarningClose } = useDisclosure();

  const [showPdf, setShowPdf] = useState<boolean>(true);
  const [invoiceIds, setInvoiceIds] = useState<string[]>([]);
  const [readData, setReadData] = useState<any>(null);
  const [lineitems, setLineitems] = useState<any[]>([]);
  const [codeFields, setCodeFields] = useState<any[]>([]);
  const [genAiFields, setGenAiFields] = useState<any[]>([]);
  const [genAiRulechecks, setGenAiRulechecks] = useState<any[]>([]);
  const [genAiError, setGenAiError] = useState<string | null>(null);
  const [upgradeTypeResults, setUpgradeTypeResults] = useState<any[]>([]);
  const [pdfUrl, setPdfUrl] = useState<string | null>(null);
  const [pdfUrlError, setPdfUrlError] = useState<string | null>(null);
  const [numPages, setNumPages] = useState<number>(0);
  const [activeHighlightKey, setActiveHighlightKey] = useState<string>('invoice_id');
  const [activePageNumber, setActivePageNumber] = useState<number>(1);
  const [activeHighlight, setActiveHighlight] = useState<{
    source: 'di' | 'genai' | 'code';
    key?: string;
    genaiId?: number;
    pageNumber: number | null;
    polygon: any | null;
  } | null>(null);
  const [pageWidthPx, setPageWidthPx] = useState<number>(560);
  const [pdfPaneHeightPx, setPdfPaneHeightPx] = useState<number>(700);
  const [zoom, setZoom] = useState<number>(1.0);
  const [fitMode, setFitMode] = useState<FitMode>('width');
  const [rotate, setRotate] = useState<number>(0);
  const [pageInput, setPageInput] = useState<string>('1');
  const [submitLoading, setSubmitLoading] = useState(false);
  const [uploadLoading, setUploadLoading] = useState(false);

  const currentStatus = String(readData?.invoice_status || '').trim();
  const currentInvoiceId = String(readData?.invoice_id || invoiceId || '').trim();
  const showSessionControls = new URLSearchParams(location.search).get('source') === 'upload';
  const currentIndex = invoiceIds.indexOf(String(invoiceId || ''));
  const canGoPrev = currentIndex > 0;
  const canGoNext = currentIndex >= 0 && currentIndex < invoiceIds.length - 1;
  const canSubmit = currentStatus === 'genai_complete' || currentStatus === 'contractor_revision_inbox';
  const canUploadFix = currentStatus === 'genai_complete' || currentStatus === 'contractor_revision_inbox';
  const failingRulechecks = useMemo(
    () => genAiRulechecks.filter((row: any) => normalizeResult(row?.rule_result) === 'fail'),
    [genAiRulechecks],
  );

  useEffect(() => {
    const run = async () => {
      if (!sessionId || !showSessionControls) return;
      const resp = await fetch(`/api/claims/sessions/${encodeURIComponent(sessionId)}/current_invoices`, {
        headers: { Accept: 'application/json' },
        credentials: 'include',
      });
      const json = await resp.json().catch(() => ({}));
      const ids = Array.isArray(json?.invoice_ids) ? json.invoice_ids : [];
      setInvoiceIds(ids);
      if (ids.length > 0 && (!invoiceId || !ids.includes(invoiceId))) {
        navigate(
          `/contractor/sessions/${encodeURIComponent(sessionId)}/invoices/${encodeURIComponent(ids[0])}/review?source=upload`,
          {
            replace: true,
          },
        );
      }
    };
    run();
  }, [invoiceId, navigate, sessionId, showSessionControls]);

  useEffect(() => {
    const run = async () => {
      if (!sessionId || !invoiceId) return;

      const [readResp, pdfResp, genaiResp] = await Promise.all([
        fetch(`/api/claims/sessions/${encodeURIComponent(sessionId)}/invoices/${encodeURIComponent(invoiceId)}/read`, {
          headers: { Accept: 'application/json' },
          credentials: 'include',
        }),
        fetch(
          `/api/claims/sessions/${encodeURIComponent(sessionId)}/invoices/${encodeURIComponent(invoiceId)}/pdf_url`,
          {
            headers: { Accept: 'application/json' },
            credentials: 'include',
          },
        ),
        fetch(
          `/api/claims/sessions/${encodeURIComponent(sessionId)}/invoices/${encodeURIComponent(invoiceId)}/read_genai`,
          {
            headers: { Accept: 'application/json' },
            credentials: 'include',
          },
        ),
      ]);

      const readJson = await readResp.json().catch(() => ({}));
      const read = readJson?.read ?? null;
      const invoice = readJson?.invoice ?? null;
      setReadData(
        read
          ? {
              ...read,
              invoice_status: read.invoice_status ?? invoice?.status ?? null,
              session_id: read.session_id ?? invoice?.session_id ?? null,
            }
          : null,
      );
      setLineitems(Array.isArray(readJson?.lineitems) ? readJson.lineitems : []);

      const pdfJson = await pdfResp.json().catch(() => ({}));
      if (!pdfResp.ok || !pdfJson?.sas_url) {
        setPdfUrl(null);
        setPdfUrlError(pdfJson?.error || `Could not load PDF URL (${pdfResp.status}).`);
      } else {
        setPdfUrl(String(pdfJson.sas_url));
        setPdfUrlError(null);
      }

      if (!genaiResp.ok) {
        const txt = await genaiResp.text();
        setGenAiFields([]);
        setCodeFields([]);
        setUpgradeTypeResults([]);
        setGenAiRulechecks([]);
        setGenAiError(`read_genai failed (${genaiResp.status}): ${txt}`);
        return;
      }

      const genaiJson = await genaiResp.json().catch(() => ({}));
      setGenAiFields(Array.isArray(genaiJson?.located_fields) ? genaiJson.located_fields : []);
      setCodeFields(Array.isArray(genaiJson?.code_located_fields) ? genaiJson.code_located_fields : []);
      setUpgradeTypeResults(Array.isArray(genaiJson?.upgrade_type_results) ? genaiJson.upgrade_type_results : []);
      setGenAiRulechecks([
        ...(Array.isArray(genaiJson?.code_rulechecks) ? genaiJson.code_rulechecks : []),
        ...(Array.isArray(genaiJson?.rulechecks) ? genaiJson.rulechecks : []),
      ]);
      setGenAiError(null);
    };
    run();
  }, [invoiceId, sessionId]);

  useEffect(() => {
    if (!showPdf) return;
    const el = pdfWrapRef.current;
    if (!el) return;

    const ro = new ResizeObserver(() => {
      if (el.clientWidth <= 0 || el.clientHeight <= 0) return;
      setPageWidthPx(Math.min(Math.max(300, Math.floor(el.clientWidth)), 560));
      setPdfPaneHeightPx(Math.max(300, Math.floor(el.clientHeight)));
    });
    ro.observe(el);

    if (el.clientWidth > 0 && el.clientHeight > 0) {
      setPageWidthPx(Math.min(Math.max(300, Math.floor(el.clientWidth)), 560));
      setPdfPaneHeightPx(Math.max(300, Math.floor(el.clientHeight)));
    }

    return () => ro.disconnect();
  }, [showPdf]);

  const activeField = useMemo(
    () => DI_FIELDS.find((field) => field.key === activeHighlightKey) ?? null,
    [activeHighlightKey],
  );

  useEffect(() => {
    if (!readData || !activeField) return;
    if (!activeField.pageKey || !activeField.polygonKey) return;
    setActiveHighlight({
      source: 'di',
      key: activeField.key,
      pageNumber: readData[activeField.pageKey],
      polygon: readData[activeField.polygonKey],
    });
  }, [activeField, readData]);

  useEffect(() => {
    const page = activeHighlight?.pageNumber;
    if (typeof page === 'number' && page >= 1) setActivePageNumber(page);
  }, [activeHighlight?.pageNumber]);

  useEffect(() => {
    setPageInput(String(activePageNumber));
  }, [activePageNumber]);

  const activePageMeta = useMemo(() => {
    const pages = readData?.di_page_map;
    const pageNumber = activeHighlight?.pageNumber;
    if (!pages || !pageNumber) return null;
    const found = pages.find((page: any) => Number(page.pageNumber) === Number(pageNumber));
    if (!found) return null;
    return {
      width: Number(found.width),
      height: Number(found.height),
      unit: String(found.unit || ''),
    };
  }, [activeHighlight?.pageNumber, readData?.di_page_map]);

  const renderWidthPx = useMemo(() => {
    if (!activePageMeta) return Math.floor(pageWidthPx * zoom);
    if (fitMode === 'width') return Math.floor(pageWidthPx * zoom);
    const widthByHeight = pdfPaneHeightPx * (activePageMeta.width / activePageMeta.height);
    return Math.floor(Math.min(pageWidthPx, widthByHeight) * zoom);
  }, [activePageMeta, fitMode, pageWidthPx, pdfPaneHeightPx, zoom]);

  const overlayHeightPx = useMemo(() => {
    if (!activePageMeta) return 1200;
    return renderWidthPx * (activePageMeta.height / activePageMeta.width);
  }, [activePageMeta, renderWidthPx]);

  const svgPolygonPoints = useMemo(() => {
    const poly = activeHighlight?.polygon;
    const meta = activePageMeta;
    if (!poly || !meta || meta.unit !== 'inch') return null;

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

    const xToPx = (xIn: number) => (xIn / meta.width) * renderWidthPx;
    const yToPx = (yIn: number) => (yIn / meta.height) * (renderWidthPx * (meta.height / meta.width));
    return [
      [xToPx(x1), yToPx(y1)],
      [xToPx(x2), yToPx(y2)],
      [xToPx(x3), yToPx(y3)],
      [xToPx(x4), yToPx(y4)],
    ]
      .map(([x, y]) => `${x.toFixed(2)},${y.toFixed(2)}`)
      .join(' ');
  }, [activeHighlight?.polygon, activePageMeta, renderWidthPx]);

  const reviewGroups = useMemo(() => {
    const groups = new Map<
      string,
      {
        description: string;
        fields: any[];
        lineitems: any[];
        rulechecks: any[];
        upgradeTypeKey: string;
      }
    >();

    const ensureGroup = (row: any) => {
      const upgradeTypeKey = fieldUpgradeTypeKey(row);
      const existing = groups.get(upgradeTypeKey);
      if (existing) return existing;

      const group = {
        description: upgradeTypeDescriptionFor(row),
        fields: [],
        lineitems: [],
        rulechecks: [],
        upgradeTypeKey,
      };
      groups.set(upgradeTypeKey, group);
      return group;
    };

    genAiFields.forEach((row) => ensureGroup(row).fields.push(row));
    lineitems.forEach((row) => ensureGroup(row).lineitems.push(row));
    genAiRulechecks.forEach((row) => ensureGroup(row).rulechecks.push(row));
    upgradeTypeResults.forEach((row) => ensureGroup(row));

    return Array.from(groups.values()).sort((a, b) => {
      const sortA = upgradeTypeSortValue(a.upgradeTypeKey);
      const sortB = upgradeTypeSortValue(b.upgradeTypeKey);
      if (sortA !== sortB) return sortA - sortB;
      return a.description.localeCompare(b.description);
    });
  }, [genAiFields, genAiRulechecks, lineitems, upgradeTypeResults]);

  const submitToAdmin = async () => {
    if (!currentInvoiceId || !canSubmit) return;
    setSubmitLoading(true);
    try {
      const resp = await fetch(
        `/api/claims/contractor/invoices/${encodeURIComponent(currentInvoiceId)}/submit_to_admin`,
        {
          method: 'POST',
          headers: { Accept: 'application/json' },
          credentials: 'include',
        },
      );
      const json = await resp.json().catch(() => ({}));
      if (!resp.ok) throw new Error(json?.error || `Submit failed (${resp.status}).`);
      setReadData((prev: any) =>
        prev
          ? {
              ...prev,
              invoice_status: json?.invoice?.status || 'admin_review_inbox',
              submitted_at: json?.invoice?.submitted_at ?? prev.submitted_at,
            }
          : prev,
      );
      toast({
        title: 'Invoice submitted',
        description: 'Status moved to admin_review_inbox.',
        status: 'success',
        duration: 5000,
        isClosable: true,
      });
    } catch (e: any) {
      toast({
        title: 'Submit failed',
        description: e?.message || 'Please try again.',
        status: 'error',
        duration: 6000,
        isClosable: true,
      });
    } finally {
      setSubmitLoading(false);
    }
  };

  const requestSubmitToAdmin = () => {
    if (!canSubmit) return;
    if (failingRulechecks.length > 0) {
      onSubmitWarningOpen();
      return;
    }
    void submitToAdmin();
  };

  const submitToAdminDespiteFailures = () => {
    onSubmitWarningClose();
    void submitToAdmin();
  };

  const uploadCorrectionFromWarning = () => {
    onSubmitWarningClose();
    fileInputRef.current?.click();
  };

  const uploadCorrectedInvoice = async (file?: File) => {
    if (!file || !currentInvoiceId) return;
    setUploadLoading(true);
    try {
      const form = new FormData();
      form.append('pdfs[]', file);
      const resp = await fetch(`/api/claims/invoices/${encodeURIComponent(currentInvoiceId)}/upload_fix`, {
        method: 'POST',
        body: form,
        credentials: 'include',
      });
      const json = await resp.json().catch(() => ({}));
      if (!resp.ok || json?.ok === false) throw new Error(json?.error || `Upload failed (${resp.status}).`);
      toast({
        title: 'Corrected invoice uploaded',
        description: 'The corrected invoice was uploaded. OCR and AI processing may still need to run before resubmit.',
        status: 'success',
        duration: 7000,
        isClosable: true,
      });
    } catch (e: any) {
      toast({
        title: 'Upload failed',
        description: e?.message || 'Please try again.',
        status: 'error',
        duration: 6000,
        isClosable: true,
      });
    } finally {
      setUploadLoading(false);
      if (fileInputRef.current) fileInputRef.current.value = '';
    }
  };

  const goToInvoice = (nextInvoiceId: string) => {
    if (!sessionId) return;
    navigate(
      `/contractor/sessions/${encodeURIComponent(sessionId)}/invoices/${encodeURIComponent(nextInvoiceId)}/review?source=upload`,
    );
  };

  return (
    <Flex as="main" direction="column" w="full" bg="greys.white" pb="24" minH="100vh">
      <ThinBlueTitleBar title="Contractor Invoice Review" />
      <Container maxW="full" px={6} pb={4} flex="1" pt={6}>
        <Box display="flex" flexDirection="column" height="100%">
          <Box display="flex" alignItems="center" gap="8px" mb="12px" flexWrap="wrap">
            {showSessionControls ? (
              <>
                <Text fontSize="xs" opacity={0.75} flexBasis="100%">
                  Review each invoice you just uploaded. Submit only when the invoice is ready for admin review.
                </Text>
                <Button
                  size="xs"
                  variant="outline"
                  isDisabled={!canGoPrev}
                  onClick={() => goToInvoice(invoiceIds[currentIndex - 1])}
                >
                  Previous invoice
                </Button>
                <Text fontSize="xs" opacity={0.75}>
                  Invoice {currentIndex >= 0 ? currentIndex + 1 : '-'} of {invoiceIds.length || '-'}
                </Text>
                <Button
                  size="xs"
                  variant="outline"
                  isDisabled={!canGoNext}
                  onClick={() => goToInvoice(invoiceIds[currentIndex + 1])}
                >
                  Next invoice
                </Button>
              </>
            ) : null}
            <Badge colorScheme={statusColor(currentStatus)}>Status: {invoiceStatusLabel(currentStatus)}</Badge>
            <Button size="xs" variant="outline" onClick={() => setShowPdf((visible) => !visible)}>
              {showPdf ? 'Hide PDF' : 'Show PDF'}
            </Button>
            <Tooltip
              label={
                canSubmit
                  ? 'Submit this invoice back to admin review. Moves status to admin_review_inbox.'
                  : 'Submit to Admin is only available while the invoice status is genai_complete or contractor_revision_inbox.'
              }
              hasArrow
            >
              <Button
                size="xs"
                colorScheme="blue"
                isDisabled={!canSubmit}
                isLoading={submitLoading}
                onClick={requestSubmitToAdmin}
              >
                Submit to Admin
              </Button>
            </Tooltip>
            <Tooltip label="View admin requested changes and add notes for admins." hasArrow>
              <Button
                size="xs"
                variant="outline"
                colorScheme="orange"
                isDisabled={!sessionId || !currentInvoiceId}
                onClick={() => {
                  if (!sessionId || !currentInvoiceId) return;
                  navigate(
                    `/contractor/sessions/${encodeURIComponent(sessionId)}/invoices/${encodeURIComponent(currentInvoiceId)}/messages`,
                  );
                }}
              >
                Messages & Requested Changes
              </Button>
            </Tooltip>
            <Tooltip
              label={
                canUploadFix
                  ? 'Upload a corrected invoice PDF for this invoice.'
                  : 'Corrected upload is available while the invoice is genai_complete or contractor_revision_inbox.'
              }
              hasArrow
            >
              <Button
                size="xs"
                variant="outline"
                colorScheme="orange"
                isDisabled={!canUploadFix}
                isLoading={uploadLoading}
                onClick={() => fileInputRef.current?.click()}
              >
                Upload Corrected Invoice
              </Button>
            </Tooltip>
            <input
              ref={fileInputRef}
              type="file"
              accept="application/pdf"
              style={{ display: 'none' }}
              onChange={(event) => void uploadCorrectedInvoice(event.target.files?.[0])}
            />
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

          <Box display="flex" gap="16px" flex="1" minH={0}>
            <Box
              borderWidth="1px"
              borderRadius="md"
              p="12px"
              sx={{ resize: 'horizontal', overflow: 'auto' }}
              minW="480px"
              maxW="100%"
              w={showPdf ? 'auto' : '100%'}
              flex="1 1 auto"
            >
              <Accordion allowMultiple defaultIndex={[0]}>
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
                      {DI_FIELDS.map((field) => {
                        const raw = readData?.[field.valueKey];
                        const display = field.formatter ? field.formatter(raw) : String(raw ?? '-');
                        const clickable = !!field.pageKey && !!field.polygonKey;
                        return (
                          <FieldRow
                            key={field.key}
                            label={field.label}
                            value={display}
                            active={activeHighlightKey === field.key}
                            disabled={!clickable}
                            onClick={clickable ? () => setActiveHighlightKey(field.key) : undefined}
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
                          Information on record
                        </Text>
                        <Text fontSize="xs" opacity={0.65}>
                          Local case facts used by the review, separate from PDF evidence.
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
                        {codeFields.map((row: any) => (
                          <Box
                            key={row.id}
                            px="10px"
                            py="8px"
                            mb="6px"
                            borderRadius="md"
                            borderWidth="1px"
                            borderColor="gray.200"
                            bg="white"
                          >
                            <Text fontSize="xs" opacity={0.7}>
                              {row.field_key || 'field'}
                            </Text>
                            <Text fontSize="sm" noOfLines={3}>
                              {displayLocatedFieldValue(row)}
                            </Text>
                          </Box>
                        ))}
                      </Box>
                    )}
                  </AccordionPanel>
                </AccordionItem>

                {reviewGroups.length === 0 ? (
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
                        No review rows found.
                      </Text>
                    </AccordionPanel>
                  </AccordionItem>
                ) : (
                  reviewGroups.map((group) => {
                    const meta = getInvoiceUpgradeTypeMeta(group.upgradeTypeKey, group.description);
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
                                  {group.fields.length} fields - {group.rulechecks.length} rules -{' '}
                                  {group.lineitems.length} line items
                                </Text>
                              </Box>
                            </Flex>
                            <AccordionIcon />
                          </AccordionButton>
                        </h2>
                        <AccordionPanel px="0" pt="8px">
                          <Box mb="14px">
                            <Text fontSize="xs" fontWeight="bold" textTransform="uppercase" opacity={0.7} mb="6px">
                              Found fields
                            </Text>
                            {group.fields.length === 0 ? (
                              <Text fontSize="sm" opacity={0.7}>
                                No found fields for this upgrade type.
                              </Text>
                            ) : (
                              <Box display="grid" gridTemplateColumns="1fr 1fr" gap="8px">
                                {group.fields.map((row: any) => {
                                  const highlightKey = `found_${row.id}`;
                                  const metaText =
                                    row.confidence != null ? ` - conf ${Number(row.confidence).toFixed(0)}` : '';
                                  const clickable = row.page != null;
                                  return (
                                    <FieldRow
                                      key={row.id}
                                      label={`${row.field_key || 'field'}${metaText}`}
                                      value={displayLocatedFieldValue(row)}
                                      active={activeHighlightKey === highlightKey}
                                      disabled={!clickable}
                                      onClick={
                                        clickable
                                          ? () => {
                                              setActiveHighlight({
                                                source: 'genai',
                                                genaiId: Number(row.id),
                                                pageNumber: Number(row.page),
                                                polygon: row.polygon ?? null,
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
                            {group.rulechecks.length === 0 ? (
                              <Text fontSize="sm" opacity={0.7}>
                                No rules for this upgrade type.
                              </Text>
                            ) : (
                              <Box display="flex" flexDirection="column" gap="8px">
                                {group.rulechecks.map((row: any) => {
                                  const title = ruleDisplayTitle(row);
                                  const sourceLabel = ruleSourceLabel(row);
                                  const sourceRequirement = row.source_requirement_id ?? '';
                                  const expected = row.expected_text ?? row.expected ?? '';
                                  const calc = row.calculation ?? '';
                                  const reason = row.reason_and_likely_causes ?? '';
                                  const evidence = row.evidence_text ?? '';

                                  return (
                                    <Box
                                      key={row.id ?? `${row.rule_number}-${row.rule_name}`}
                                      px="10px"
                                      py="8px"
                                      borderRadius="md"
                                      borderWidth="1px"
                                      borderColor="gray.200"
                                      bg="white"
                                    >
                                      <Flex align="center" gap="8px" mb="4px">
                                        <StatusDot result={row.rule_result} />
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
                                      {evidence && (
                                        <Text fontSize="xs" whiteSpace="pre-wrap">
                                          <Box as="span" opacity={0.65}>
                                            evidence:{' '}
                                          </Box>
                                          {String(evidence)}
                                        </Text>
                                      )}
                                    </Box>
                                  );
                                })}
                              </Box>
                            )}
                          </Box>

                          <Box>
                            <Text fontSize="xs" fontWeight="bold" textTransform="uppercase" opacity={0.7} mb="6px">
                              Line items
                            </Text>
                            {group.lineitems.length === 0 ? (
                              <Text fontSize="sm" opacity={0.7}>
                                No line items for this upgrade type.
                              </Text>
                            ) : (
                              <Box display="grid" gridTemplateColumns="1fr 1fr" gap="8px">
                                {group.lineitems.map((lineitem: any) => {
                                  const seq = lineitem.lineitem_seqno ?? lineitem.seqno ?? '-';
                                  const rows = [
                                    {
                                      subKey: 'desc',
                                      label: 'Description',
                                      value: lineitem.ocr_description ?? '-',
                                      page: lineitem.ocr_description_page,
                                      polygon: lineitem.ocr_description_polygon,
                                    },
                                    {
                                      subKey: 'qty',
                                      label: 'Quantity',
                                      value: lineitem.ocr_quantity != null ? String(lineitem.ocr_quantity) : '-',
                                      page: lineitem.ocr_quantity_page,
                                      polygon: lineitem.ocr_quantity_polygon,
                                    },
                                    {
                                      subKey: 'unit',
                                      label: 'Unit price',
                                      value: lineitem.ocr_unit_price != null ? fmtMoney(lineitem.ocr_unit_price) : '-',
                                      page: lineitem.ocr_unit_price_page,
                                      polygon: lineitem.ocr_unit_price_polygon,
                                    },
                                    {
                                      subKey: 'amt',
                                      label: 'Amount',
                                      value: lineitem.ocr_amount != null ? fmtMoney(lineitem.ocr_amount) : '-',
                                      page: lineitem.ocr_amount_page,
                                      polygon: lineitem.ocr_amount_polygon,
                                    },
                                  ];

                                  return rows.map((row) => {
                                    const clickable = row.page != null && row.polygon != null;
                                    const highlightKey = `lineitem_${seq}_${row.subKey}`;
                                    return (
                                      <FieldRow
                                        key={`${lineitem.id ?? `li-${seq}`}-${row.subKey}`}
                                        label={`Line ${seq} - ${row.label}`}
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
                                  });
                                })}
                              </Box>
                            )}
                          </Box>
                        </AccordionPanel>
                      </AccordionItem>
                    );
                  })
                )}
              </Accordion>
            </Box>

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
                    <Box display="flex" alignItems="center" gap="8px">
                      <Button
                        size="sm"
                        onClick={() => setActivePageNumber((page) => Math.max(1, page - 1))}
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
                        onChange={(event: any) => setPageInput(event.target.value)}
                        onBlur={() => {
                          const next = Number(pageInput);
                          if (!Number.isFinite(next)) {
                            setPageInput(String(activePageNumber));
                            return;
                          }
                          setActivePageNumber(Math.min(Math.max(1, Math.floor(next)), numPages || 1));
                        }}
                        onKeyDown={(event: any) => {
                          if (event.key === 'Enter') (event.target as HTMLInputElement).blur();
                        }}
                        style={{ width: 60, padding: '6px 8px', border: '1px solid #E2E8F0', borderRadius: 6 }}
                      />
                      <Text fontSize="sm" opacity={0.8}>
                        / {numPages || '-'}
                      </Text>
                      <Button
                        size="sm"
                        onClick={() => setActivePageNumber((page) => Math.min(numPages || page + 1, page + 1))}
                        isDisabled={!!numPages && activePageNumber >= numPages}
                      >
                        Next
                      </Button>
                    </Box>

                    <Box display="flex" alignItems="center" gap="8px" flexWrap="wrap" justifyContent="flex-end">
                      <Button size="sm" onClick={() => setZoom((value) => Math.max(0.5, +(value - 0.1).toFixed(2)))}>
                        -
                      </Button>
                      <Text fontSize="sm" minW="56px" textAlign="center">
                        {Math.round(zoom * 100)}%
                      </Text>
                      <Button size="sm" onClick={() => setZoom((value) => Math.min(3, +(value + 0.1).toFixed(2)))}>
                        +
                      </Button>
                      <Button
                        size="sm"
                        variant={fitMode === 'width' ? 'solid' : 'outline'}
                        onClick={() => {
                          setFitMode('width');
                          setZoom(1);
                        }}
                      >
                        Fit width
                      </Button>
                      <Button
                        size="sm"
                        variant={fitMode === 'page' ? 'solid' : 'outline'}
                        onClick={() => {
                          setFitMode('page');
                          setZoom(1);
                        }}
                      >
                        Fit page
                      </Button>
                      <Button size="sm" onClick={() => setRotate((value) => (value + 90) % 360)}>
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

                  {pdfUrlError ? (
                    <Text color="red.700">PDF URL error: {pdfUrlError}</Text>
                  ) : !pdfUrl ? (
                    <Flex align="center" justify="center" minH="300px">
                      <Spinner />
                    </Flex>
                  ) : (
                    <Document
                      file={pdfUrl}
                      onLoadSuccess={({ numPages: pages }) => {
                        setNumPages(pages);
                        setActivePageNumber((page) => Math.min(Math.max(1, page), pages));
                      }}
                      onLoadError={(err) => console.error('PDF load error:', err)}
                    >
                      <Box position="relative" width={`${renderWidthPx}px`} height={`${overlayHeightPx}px`}>
                        <svg
                          width={renderWidthPx}
                          height={overlayHeightPx}
                          style={{ position: 'absolute', left: 0, top: 0, zIndex: 10, pointerEvents: 'none' }}
                        >
                          {svgPolygonPoints && (
                            <polygon points={svgPolygonPoints} fill="rgba(255,0,0,0.20)" stroke="red" strokeWidth={2} />
                          )}
                        </svg>

                        <Box style={{ position: 'absolute', top: 0, left: 0 }}>
                          <Page
                            key={`p${activePageNumber}-w${renderWidthPx}-r${rotate}`}
                            pageNumber={activePageNumber}
                            width={renderWidthPx}
                            rotate={rotate}
                          />
                        </Box>
                      </Box>
                      <Text fontSize="xs" opacity={0.6} mt="8px">
                        active page {activePageNumber} / {numPages || '-'} | unit {activePageMeta?.unit ?? '-'}
                      </Text>
                    </Document>
                  )}
                </Box>
              </Box>
            ) : null}
          </Box>
        </Box>
      </Container>

      <Modal isOpen={isSubmitWarningOpen} onClose={onSubmitWarningClose} size="2xl" isCentered>
        <ModalOverlay />
        <ModalContent>
          <ModalHeader>Submit with failed checks?</ModalHeader>
          <ModalCloseButton />
          <ModalBody>
            <Flex direction="column" gap={4}>
              <Text fontSize="sm">
                This invoice still has red failed checks. You can submit it to admin review, but admins will likely ask
                for corrections or supporting details, which can slow down payment.
              </Text>
              <Text fontSize="sm">
                The faster path may be to correct the invoice in your own invoicing system, confirm the change with the
                homeowner if needed, then upload the corrected PDF here before submitting.
              </Text>

              <Box borderWidth="1px" borderRadius="md" p={4} bg="red.50" borderColor="red.100">
                <Text fontSize="sm" fontWeight="bold" mb={3}>
                  Failed checks found
                </Text>
                <Flex direction="column" gap={3}>
                  {failingRulechecks.slice(0, 6).map((row: any) => {
                    const num = row.rule_number != null ? Number(row.rule_number) : null;
                    const name = String(row.rule_name || 'Invoice review check');
                    const groupName = String(row.upgrade_type_description || row.upgrade_type_key || 'Invoice');
                    const reason = row.reason_and_likely_causes || row.observed_text || row.evidence_text || '';

                    return (
                      <Box key={row.id ?? `${row.rule_number}-${row.rule_name}`} bg="white" borderRadius="md" p={3}>
                        <Flex align="center" gap={2} mb={1}>
                          <StatusDot result="fail" />
                          <Text fontSize="sm" fontWeight="semibold">
                            {num != null ? `Rule ${num} - ${name}` : name}
                          </Text>
                        </Flex>
                        <Text fontSize="xs" opacity={0.7} mb={reason ? 1 : 0}>
                          {groupName}
                        </Text>
                        {reason ? (
                          <Text fontSize="xs" whiteSpace="pre-wrap">
                            {String(reason)}
                          </Text>
                        ) : null}
                      </Box>
                    );
                  })}
                </Flex>
                {failingRulechecks.length > 6 ? (
                  <Text fontSize="xs" mt={3} opacity={0.75}>
                    Plus {failingRulechecks.length - 6} more failed check(s) on this invoice.
                  </Text>
                ) : null}
              </Box>

              <Text fontSize="sm">
                If you believe the invoice is correct as-is, you can still submit it. Just know the admin team may send
                it back for revision. If a failed check is explainable, use Messages & Requested Changes to add a note
                for admins before submitting.
              </Text>
            </Flex>
          </ModalBody>
          <ModalFooter gap={3} flexWrap="wrap">
            <Button variant="outline" onClick={onSubmitWarningClose}>
              Keep reviewing
            </Button>
            <Button
              variant="outline"
              colorScheme="blue"
              onClick={() => {
                onSubmitWarningClose();
                if (!sessionId || !currentInvoiceId) return;
                navigate(
                  `/contractor/sessions/${encodeURIComponent(sessionId)}/invoices/${encodeURIComponent(currentInvoiceId)}/messages`,
                );
              }}
            >
              Add Message for Admins
            </Button>
            <Button
              variant="outline"
              colorScheme="orange"
              onClick={uploadCorrectionFromWarning}
              isDisabled={!canUploadFix}
            >
              Upload Corrected Invoice
            </Button>
            <Button colorScheme="red" onClick={submitToAdminDespiteFailures} isLoading={submitLoading}>
              Submit Anyway
            </Button>
          </ModalFooter>
        </ModalContent>
      </Modal>

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
                <Text fontSize="sm">
                  This screen shows invoice OCR fields, local information on record, review rules, line items, and the
                  PDF evidence used for review.
                </Text>
              </Box>
              <Box>
                <Heading size="sm" mb={2}>
                  Contractor Actions
                </Heading>
                <Text fontSize="sm">
                  Submit to Admin moves the invoice into admin_review_inbox. It is available after AI review is
                  complete, and again when an admin has sent the invoice back to contractor_revision_inbox.
                </Text>
              </Box>
            </Flex>
          </DrawerBody>
        </DrawerContent>
      </Drawer>
    </Flex>
  );
}
