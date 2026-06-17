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
  Switch,
  Text,
  Tooltip,
  useDisclosure,
  useToast,
} from '@chakra-ui/react';
import { keyframes } from '@emotion/react';
import {
  ArrowClockwise,
  ArrowSquareOut,
  CaretLeft,
  CaretRight,
  ChatDots,
  CheckCircle,
  CornersOut,
  FrameCorners,
  MagnifyingGlassMinus,
  MagnifyingGlassPlus,
  PaperPlaneTilt,
  Question,
  UploadSimple,
  WarningCircle,
} from '@phosphor-icons/react';
import React, { useEffect, useMemo, useRef, useState } from 'react';
import { Document, Page, pdfjs } from 'react-pdf';
import 'react-pdf/dist/Page/AnnotationLayer.css';
import 'react-pdf/dist/Page/TextLayer.css';
import { useNavigate, useParams } from 'react-router-dom';
import { ThinBlueTitleBar } from '../../shared/base/thin-blue-title-bar';
import { invoiceStatusCopy } from '../../shared/claims/invoice-status-copy';
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
  inline?: boolean;
};

type RuleResult = 'pass' | 'info' | 'warn' | 'fail' | null | undefined;
type FitMode = 'width' | 'page';
type UploadFixModalState = 'idle' | 'uploading' | 'processing' | 'succeeded' | 'failed';

const orbitSpin = keyframes`
  from { transform: rotate(0deg); }
  to { transform: rotate(360deg); }
`;

const pulseGlow = keyframes`
  0%, 100% { opacity: 0.55; transform: scale(0.95); }
  50% { opacity: 0.95; transform: scale(1.04); }
`;

const storyFade = keyframes`
  0% { opacity: 0; transform: translateY(8px) scale(0.98); filter: blur(3px); }
  18% { opacity: 1; transform: translateY(0) scale(1); filter: blur(0); }
  82% { opacity: 1; transform: translateY(0) scale(1); filter: blur(0); }
  100% { opacity: 0; transform: translateY(-7px) scale(0.99); filter: blur(2px); }
`;

const sleep = (ms: number) => new Promise((resolve) => window.setTimeout(resolve, ms));

const UploadFixProcessingGraphic = ({ label }: { label: string }) => (
  <Flex direction="column" align="center" gap={4} py={8}>
    <Box position="relative" w="168px" h="168px">
      <Box
        position="absolute"
        inset="10px"
        borderRadius="full"
        bg="radial-gradient(circle at 35% 30%, rgba(255,255,255,0.98), rgba(188,229,255,0.42) 42%, rgba(0,104,183,0.08) 72%)"
        boxShadow="0 22px 55px rgba(0, 85, 140, 0.22), inset 0 1px 18px rgba(255,255,255,0.9)"
        animation={`${pulseGlow} 2.7s ease-in-out infinite`}
        sx={{
          '@media (prefers-reduced-motion: reduce)': {
            animation: 'none',
          },
        }}
      />
      <Flex
        position="absolute"
        inset="0"
        align="center"
        justify="center"
        borderRadius="full"
        bg="conic-gradient(from 120deg, rgba(10,132,207,0), rgba(61,177,255,0.82), rgba(214,244,255,0.95), rgba(10,132,207,0.08), rgba(10,132,207,0))"
        sx={{
          mask: 'radial-gradient(circle, transparent 53%, black 55%)',
          WebkitMask: 'radial-gradient(circle, transparent 53%, black 55%)',
          animation: `${orbitSpin} 1.45s linear infinite`,
          '@media (prefers-reduced-motion: reduce)': {
            animation: `${orbitSpin} 5s linear infinite`,
          },
        }}
      />
      <Flex
        position="absolute"
        inset="0"
        align="center"
        justify="center"
        color="#0068b7"
        filter="drop-shadow(0 12px 20px rgba(0, 104, 183, 0.22))"
        sx={{
          animation: `${orbitSpin} 2.3s cubic-bezier(.62,.02,.32,1) infinite`,
          '@media (prefers-reduced-motion: reduce)': {
            animation: 'none',
          },
        }}
      >
        <ArrowClockwise size={104} weight="duotone" />
      </Flex>
      <Box
        position="absolute"
        right="22px"
        top="30px"
        w="16px"
        h="16px"
        borderRadius="full"
        bg="linear-gradient(135deg, #ffffff, #42c7ff)"
        boxShadow="0 0 24px rgba(66, 199, 255, 0.9)"
      />
    </Box>
    <Text
      key={label}
      fontSize="xl"
      fontWeight="700"
      letterSpacing="0.02em"
      color="rgba(15, 42, 67, 0.92)"
      minH="32px"
      textAlign="center"
      animation={`${storyFade} 3s ease-in-out infinite`}
      sx={{
        '@media (prefers-reduced-motion: reduce)': {
          animation: 'none',
        },
      }}
    >
      {label}
    </Text>
  </Flex>
);

const FieldRow = ({ label, value, active, disabled, onClick, inline }: FieldRowProps) => (
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
      {String(value ?? '-')}
    </Text>
  </Box>
);

const ValueGrid = ({ rows }: { rows: Array<[string, unknown]> }) => (
  <Box display="grid" gridTemplateColumns="1fr 1fr" columnGap="8px" rowGap="0">
    {rows
      .filter(([, value]) => value != null && value !== '')
      .map(([label, value]) => (
        <Box
          key={label}
          px="10px"
          py="2px"
          borderRadius="md"
          display="flex"
          alignItems="baseline"
          justifyContent="space-between"
          gap="6px"
        >
          <Text fontSize="sm" opacity={0.7} flexShrink={0}>
            {label}
          </Text>
          <Text fontSize="sm" noOfLines={1} textAlign="right">
            {fmtText(value)}
          </Text>
        </Box>
      ))}
  </Box>
);

const ProductMatchAccordion = ({ title, rows }: { title: string; rows: Array<[string, unknown]> }) => (
  <AccordionItem borderTopWidth="1px" borderColor="gray.200">
    <h2>
      <AccordionButton px="0" py="6px" _hover={{ bg: 'transparent' }}>
        <Box flex="1" textAlign="left">
          <Text size="sm" fontWeight="bold">
            {title}
          </Text>
        </Box>
        <AccordionIcon />
      </AccordionButton>
    </h2>
    <AccordionPanel px="0" pt="8px">
      <ValueGrid rows={rows} />
    </AccordionPanel>
  </AccordionItem>
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
  return 'unknown: advice result was not recognized.';
};

const resultColorScheme = (result: unknown): string => {
  const normalized = normalizeResult(result);
  if (normalized === 'pass') return 'green';
  if (normalized === 'info') return 'blue';
  if (normalized === 'warn') return 'yellow';
  if (normalized === 'fail') return 'red';
  return 'gray';
};

const resultLabel = (result: unknown): string => {
  const normalized = normalizeResult(result);
  return normalized || 'unknown';
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
  const ruleKey = String(rulecheck.rule_key ?? '').trim();
  if (ruleKey) return ruleKey;

  const num = rulecheck.rule_number != null ? Number(rulecheck.rule_number) : null;
  return num != null ? `advice_${num}` : 'advice';
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

export default function ContractorInvoiceReviewScreen() {
  const { sessionId, invoiceId } = useParams();
  const navigate = useNavigate();
  const toast = useToast();
  const fileInputRef = useRef<HTMLInputElement | null>(null);
  const pdfWrapRef = useRef<HTMLDivElement | null>(null);
  const isMountedRef = useRef(true);
  const { isOpen: isHelpOpen, onOpen: onHelpOpen, onClose: onHelpClose } = useDisclosure();
  const { isOpen: isSubmitWarningOpen, onOpen: onSubmitWarningOpen, onClose: onSubmitWarningClose } = useDisclosure();
  const { isOpen: isUploadFixOpen, onOpen: onUploadFixOpen, onClose: onUploadFixClose } = useDisclosure();

  const [showPdf, setShowPdf] = useState<boolean>(true);
  const [readData, setReadData] = useState<any>(null);
  const [lineitems, setLineitems] = useState<any[]>([]);
  const [codeFields, setCodeFields] = useState<any[]>([]);
  const [genAiFields, setGenAiFields] = useState<any[]>([]);
  const [classifierFields, setClassifierFields] = useState<any[]>([]);
  const [genAiRulechecks, setGenAiRulechecks] = useState<any[]>([]);
  const [genAiError, setGenAiError] = useState<string | null>(null);
  const [upgradeTypeResults, setUpgradeTypeResults] = useState<any[]>([]);
  const [pdfUrl, setPdfUrl] = useState<string | null>(null);
  const [pdfUrlError, setPdfUrlError] = useState<string | null>(null);
  const [numPages, setNumPages] = useState<number>(0);
  const [activeHighlightKey, setActiveHighlightKey] = useState<string>('invoice_id');
  const [activePageNumber, setActivePageNumber] = useState<number>(1);
  const [activeHighlight, setActiveHighlight] = useState<{
    source: 'di' | 'genai' | 'code' | 'classifier';
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
  const [uploadFixState, setUploadFixState] = useState<UploadFixModalState>('idle');
  const [uploadFixStory, setUploadFixStory] = useState('Uploading corrected invoice');
  const [uploadFixErrorTitle, setUploadFixErrorTitle] = useState('Upload needs attention');
  const [uploadFixErrorMessage, setUploadFixErrorMessage] = useState('');
  const [uploadFixSuccessVersion, setUploadFixSuccessVersion] = useState<number | null>(null);

  const currentStatus = String(readData?.invoice_status || '').trim();
  const currentStatusSubtype = String(readData?.invoice_status_subtype || '').trim();
  const currentInvoiceId = String(readData?.invoice_id || invoiceId || '').trim();
  const canSubmit = currentStatus === 'genai_complete' || currentStatus === 'contractor_revision_inbox';
  const canUploadFix = currentStatus === 'genai_complete' || currentStatus === 'contractor_revision_inbox';
  const currentStatusCopy = invoiceStatusCopy(currentStatus, currentStatusSubtype);
  const failingRulechecks = useMemo(
    () => genAiRulechecks.filter((row: any) => normalizeResult(row?.rule_result) === 'fail'),
    [genAiRulechecks],
  );

  useEffect(() => {
    isMountedRef.current = true;
    return () => {
      isMountedRef.current = false;
    };
  }, []);

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
              invoice_status_subtype: read.invoice_status_subtype ?? invoice?.status_subtype ?? null,
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
        setClassifierFields([]);
        setCodeFields([]);
        setUpgradeTypeResults([]);
        setGenAiRulechecks([]);
        setGenAiError(`read_genai failed (${genaiResp.status}): ${txt}`);
        return;
      }

      const genaiJson = await genaiResp.json().catch(() => ({}));
      setGenAiFields(Array.isArray(genaiJson?.located_fields) ? genaiJson.located_fields : []);
      setClassifierFields(
        Array.isArray(genaiJson?.classifier_located_fields) ? genaiJson.classifier_located_fields : [],
      );
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
        rulechecks: [],
        upgradeTypeKey,
      };
      groups.set(upgradeTypeKey, group);
      return group;
    };

    genAiFields.forEach((row) => ensureGroup(row).fields.push(row));
    genAiRulechecks.forEach((row) => ensureGroup(row).rulechecks.push(row));
    upgradeTypeResults.forEach((row) => ensureGroup(row));

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
          const sortA = upgradeTypeSortValue(fieldUpgradeTypeKey(a));
          const sortB = upgradeTypeSortValue(fieldUpgradeTypeKey(b));
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

  const ahriProduct = readData?.ahri_product_match?.product;
  const neeaProduct = readData?.neea_product_match?.product;
  const awhpProduct = readData?.awhp_product_match?.product;
  const ohpaProduct = readData?.ohpa_product_match?.product;

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
              invoice_status_subtype: json?.invoice?.status_subtype || null,
              submitted_at: json?.invoice?.submitted_at ?? prev.submitted_at,
            }
          : prev,
      );
      toast({
        title: 'Invoice submitted',
        description: 'Your invoice is now with the program team for first-level review.',
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

  return (
    <Flex as="main" direction="column" w="full" bg="greys.white" pb="24" minH="100vh">
      <ThinBlueTitleBar title="Contractor Invoice Review" />
      <Container maxW="full" px={6} pb={4} flex="1" pt={6}>
        <Box display="flex" flexDirection="column" height="100%">
          <Box display="flex" alignItems="center" gap="10px" mb="12px" flexWrap="wrap">
            <Flex align="center" gap="7px" px="0" py="0">
              <Text fontSize="xs" fontWeight="semibold">
                Image
              </Text>
              <Switch size="sm" isChecked={showPdf} onChange={(event) => setShowPdf(event.target.checked)} />
            </Flex>
            <Tooltip
              label={
                canSubmit
                  ? 'Send this invoice to the program team for first-level review.'
                  : 'Submission is available after the pre-check finishes, or when the program team has requested a revision.'
              }
              hasArrow
            >
              <IconButton
                aria-label="Submit to admin"
                icon={<PaperPlaneTilt size={25} weight="bold" />}
                size="md"
                colorScheme="blue"
                variant={canSubmit ? 'solid' : 'outline'}
                borderRadius="full"
                boxShadow={canSubmit ? '0 8px 18px rgba(49, 130, 206, 0.18)' : 'none'}
                isDisabled={!canSubmit}
                isLoading={submitLoading}
                onClick={requestSubmitToAdmin}
              />
            </Tooltip>
            <Tooltip label="View admin requested changes and send messages about this invoice." hasArrow>
              <IconButton
                aria-label="Messages and requested changes"
                icon={<ChatDots size={25} weight="bold" />}
                size="md"
                colorScheme="orange"
                variant={!sessionId || !currentInvoiceId ? 'outline' : 'solid'}
                borderRadius="full"
                boxShadow={!sessionId || !currentInvoiceId ? 'none' : '0 8px 18px rgba(221, 107, 32, 0.18)'}
                isDisabled={!sessionId || !currentInvoiceId}
                onClick={() => {
                  if (!sessionId || !currentInvoiceId) return;
                  navigate(
                    `/contractor/sessions/${encodeURIComponent(sessionId)}/invoices/${encodeURIComponent(currentInvoiceId)}/messages`,
                  );
                }}
              />
            </Tooltip>
            <Tooltip
              label={
                canUploadFix
                  ? 'Upload a corrected invoice PDF for this invoice.'
                  : 'Corrected upload is available after the pre-check finishes, or when the program team has requested a revision.'
              }
              hasArrow
            >
              <IconButton
                aria-label="Upload corrected invoice"
                icon={<UploadSimple size={25} weight="bold" />}
                size="md"
                colorScheme="orange"
                variant={canUploadFix ? 'solid' : 'outline'}
                borderRadius="full"
                boxShadow={canUploadFix ? '0 8px 18px rgba(221, 107, 32, 0.18)' : 'none'}
                isDisabled={!canUploadFix}
                isLoading={uploadLoading}
                onClick={() => fileInputRef.current?.click()}
              />
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
                  icon={<Question size={22} weight="bold" />}
                  size="md"
                  variant="outline"
                  borderRadius="full"
                  onClick={onHelpOpen}
                />
              </Tooltip>
            </Box>
          </Box>

          <Box display="flex" gap="16px" flex="1" minH={0}>
            <Box
              p="0"
              sx={{ resize: 'horizontal', overflow: 'auto' }}
              minW="480px"
              maxW="100%"
              w={showPdf ? 'auto' : '100%'}
              flex="1 1 auto"
            >
              <Accordion
                allowMultiple
                defaultIndex={[0]}
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
                    <Flex gap="18px" align="center" wrap="wrap" mb="8px">
                      <Tooltip
                        label={`${currentStatusCopy.hint} Technical status: ${currentStatus || 'unknown'}.`}
                        hasArrow
                      >
                        <Text fontSize="xs" fontWeight="bold" textTransform="uppercase">
                          Status: {currentStatusCopy.label}
                        </Text>
                      </Tooltip>
                      {readData?.invoice_versionno != null && (
                        <Text fontSize="xs" fontWeight="bold" textTransform="uppercase">
                          Version {String(readData.invoice_versionno)}
                        </Text>
                      )}
                    </Flex>
                    <Box display="grid" gridTemplateColumns="1fr 1fr" columnGap="8px" rowGap="0">
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
                            inline
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
                          Line items
                        </Text>
                      </Box>
                      <AccordionIcon />
                    </AccordionButton>
                  </h2>
                  <AccordionPanel px="0" pt="8px">
                    {sortedLineitems.length === 0 ? (
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
                              px="10px"
                              py="3px"
                              borderRadius="md"
                              bg={activeHighlightKey === highlightKey ? 'blue.50' : 'transparent'}
                              cursor={clickable ? 'pointer' : 'default'}
                              _hover={
                                clickable ? { bg: activeHighlightKey === highlightKey ? 'blue.50' : 'gray.50' } : {}
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
                                      setActiveHighlightKey(highlightKey);
                                      setShowPdf(true);
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
                                <Text fontSize="sm" noOfLines={1}>
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
                  <AccordionPanel px="0" pt="8px">
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
                        {classifierFields.map((row: any) => {
                          const highlightKey = `classifier_${row.id}`;
                          const confidence =
                            row.confidence != null ? `confidence ${Number(row.confidence).toFixed(2)}` : '';
                          const clickable = row.page != null;
                          return (
                            <FieldRow
                              key={row.id}
                              label={row.field_key || 'field'}
                              value={[displayLocatedFieldValue(row), confidence].filter(Boolean).join('  ')}
                              active={activeHighlightKey === highlightKey}
                              disabled={!clickable}
                              inline
                              onClick={
                                clickable
                                  ? () => {
                                      setActiveHighlight({
                                        source: 'classifier',
                                        key: highlightKey,
                                        genaiId: Number(row.id),
                                        pageNumber: Number(row.page),
                                        polygon: row.polygon ?? null,
                                      });
                                      setActiveHighlightKey(highlightKey);
                                      setShowPdf(true);
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
                  <AccordionPanel px="0" pt="8px">
                    {classifierUpgradeTypeRows.length === 0 ? (
                      <Text fontSize="sm" opacity={0.7}>
                        No upgrade types classified for this invoice.
                      </Text>
                    ) : (
                      <Box display="flex" flexDirection="column" gap="6px">
                        {classifierUpgradeTypeRows.map((row: any) => {
                          const meta = getInvoiceUpgradeTypeMeta(
                            fieldUpgradeTypeKey(row),
                            row.upgrade_type_description,
                          );
                          const explanation = String(row.classification_explanation || '').trim();
                          const evidenceText = String(row.evidence_text || '').trim();
                          const confidence =
                            row.confidence != null ? `confidence ${Number(row.confidence).toFixed(0)}` : '';
                          const clickable = row.page != null;
                          const highlightKey = `classifier_upgrade_${row.id}`;

                          return (
                            <Box
                              key={row.id}
                              px="10px"
                              py="6px"
                              borderRadius="md"
                              bg={activeHighlightKey === highlightKey ? 'blue.50' : 'transparent'}
                              cursor={clickable ? 'pointer' : 'default'}
                              _hover={
                                clickable ? { bg: activeHighlightKey === highlightKey ? 'blue.50' : 'gray.50' } : {}
                              }
                              onClick={
                                clickable
                                  ? () => {
                                      setActiveHighlight({
                                        source: 'classifier',
                                        key: highlightKey,
                                        pageNumber: Number(row.page),
                                        polygon: row.polygon ?? null,
                                      });
                                      setActiveHighlightKey(highlightKey);
                                      setShowPdf(true);
                                    }
                                  : undefined
                              }
                            >
                              <Flex align="center" gap="8px" mb="3px">
                                <Text fontSize="sm" fontWeight="bold">
                                  {meta.label}
                                </Text>
                                {confidence && (
                                  <Text fontSize="xs" opacity={0.7}>
                                    {confidence}
                                  </Text>
                                )}
                              </Flex>
                              {explanation && (
                                <Text fontSize="sm">
                                  <Box as="span" fontWeight="bold">
                                    Why classified:{' '}
                                  </Box>
                                  {explanation}
                                </Text>
                              )}
                              {evidenceText && (
                                <Text fontSize="sm">
                                  <Box as="span" fontWeight="bold">
                                    Evidence:{' '}
                                  </Box>
                                  {evidenceText}
                                </Text>
                              )}
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
                          Overall advice
                        </Text>
                      </Box>
                      <AccordionIcon />
                    </AccordionButton>
                  </h2>
                  <AccordionPanel px="0" pt="8px">
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
                  <ProductMatchAccordion
                    title="AHRI product-list match"
                    rows={[
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
                        ahriProduct.cold_climate_rated == null ? null : ahriProduct.cold_climate_rated ? 'Yes' : 'No',
                      ],
                      ['Eligibility notes', ahriProduct.eligibility_notes],
                    ]}
                  />
                )}

                {neeaProduct && (
                  <ProductMatchAccordion
                    title="NEEA HPWH product-list match"
                    rows={[
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
                        neeaProduct.plug_in_endorsement == null ? null : neeaProduct.plug_in_endorsement ? 'Yes' : 'No',
                      ],
                      ['Qualified date', neeaProduct.qualified_date ? fmtDate(neeaProduct.qualified_date) : null],
                      ['Specification version', neeaProduct.specification_version],
                      ['Eligibility notes', neeaProduct.eligibility_notes],
                    ]}
                  />
                )}

                {awhpProduct && (
                  <ProductMatchAccordion
                    title="Air-to-water product-list match"
                    rows={[
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
                    ]}
                  />
                )}

                {ohpaProduct && (
                  <ProductMatchAccordion
                    title="OHPA BC product-list match"
                    rows={[
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
                    ]}
                  />
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
                  <AccordionPanel px="0" pt="8px">
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
                        {codeFields.map((row: any) => (
                          <FieldRow
                            key={row.id}
                            label={row.field_key || 'field'}
                            value={displayLocatedFieldValue(row)}
                            disabled
                            inline
                          />
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
                          <Text size="sm">Energy Savings Program Advice</Text>
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
                              <Box minW={0}>
                                <Text fontSize="md" lineHeight="1.25" fontWeight="bold" noOfLines={1}>
                                  {meta.label} - Fields & Advice
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
                                {group.fields.length === 0 ? (
                                  <Text fontSize="sm" opacity={0.7}>
                                    No located fields for this upgrade type.
                                  </Text>
                                ) : (
                                  <Box display="grid" gridTemplateColumns="1fr 1fr" columnGap="8px" rowGap="0">
                                    {group.fields.map((row: any) => {
                                      const highlightKey = `found_${row.id}`;
                                      const confidence =
                                        row.confidence != null ? `confidence ${Number(row.confidence).toFixed(0)}` : '';
                                      const clickable = row.page != null;
                                      return (
                                        <FieldRow
                                          key={row.id}
                                          label={row.field_key || 'field'}
                                          value={[displayLocatedFieldValue(row), confidence].filter(Boolean).join('  ')}
                                          active={activeHighlightKey === highlightKey}
                                          disabled={!clickable}
                                          inline
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
                                                  setShowPdf(true);
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
                                      Advice
                                    </Text>
                                  </Box>
                                  <AccordionIcon />
                                </AccordionButton>
                              </h3>
                              <AccordionPanel px="10px" pt="3px" pb="6px">
                                {group.rulechecks.length === 0 ? (
                                  <Text fontSize="sm" opacity={0.7}>
                                    No advice for this upgrade type.
                                  </Text>
                                ) : (
                                  <Box display="flex" flexDirection="column" gap="6px">
                                    {group.rulechecks.map((row: any) => {
                                      const title = ruleDisplayTitle(row);
                                      const sourceLabel = ruleSourceLabel(row);
                                      const expected = row.expected_text ?? row.expected ?? '';
                                      const calc = row.calculation ?? '';
                                      const reason = row.reason_and_likely_causes ?? '';
                                      const evidence = row.evidence_text ?? '';
                                      const confidence =
                                        row.confidence != null ? `confidence ${Number(row.confidence).toFixed(0)}` : '';

                                      return (
                                        <Box key={row.id ?? `${row.rule_number}-${row.rule_key}`} px="10px" py="2px">
                                          <Box
                                            display="grid"
                                            gridTemplateColumns="18px minmax(180px, 1fr) 160px"
                                            gap="8px"
                                            alignItems="baseline"
                                          >
                                            <StatusDot result={row.rule_result} />
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
                                          {evidence && (
                                            <Box mt="2px" pl="26px">
                                              <Text as="span" fontSize="sm" fontWeight="bold">
                                                Evidence:{' '}
                                              </Text>
                                              <Text as="span" fontSize="sm">
                                                {String(evidence)}
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
                overflow="auto"
                p="0"
                bg="transparent"
              >
                <Box position="relative" width="100%">
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
                          onClick={() => setActivePageNumber((page) => Math.max(1, page - 1))}
                          isDisabled={activePageNumber <= 1}
                        />
                      </Tooltip>
                      <Text fontSize="xs" opacity={0.7} fontWeight="semibold">
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
                          onClick={() => setActivePageNumber((page) => Math.min(numPages || page + 1, page + 1))}
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
                          onClick={() => setZoom((value) => Math.max(0.5, +(value - 0.1).toFixed(2)))}
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
                          onClick={() => setZoom((value) => Math.min(3, +(value + 0.1).toFixed(2)))}
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
                            setZoom(1);
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
                            setZoom(1);
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
                          onClick={() => setRotate((value) => (value + 90) % 360)}
                        />
                      </Tooltip>
                      <Tooltip label="Open image in browser" hasArrow>
                        <IconButton
                          aria-label="Open image in browser"
                          icon={<ArrowSquareOut size={18} weight="bold" />}
                          size="sm"
                          variant="ghost"
                          borderRadius="full"
                          onClick={() => {
                            if (!pdfUrl) return;
                            window.open(pdfUrl, '_blank', 'noopener,noreferrer');
                          }}
                          isDisabled={!pdfUrl}
                        />
                      </Tooltip>
                    </Flex>
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
                      <Box
                        position="relative"
                        width={`${renderWidthPx}px`}
                        height={`${overlayHeightPx}px`}
                        mx="auto"
                        bg="white"
                        boxShadow="0 10px 26px rgba(15, 23, 42, 0.18)"
                        borderRadius="sm"
                      >
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
                for corrections or supporting details, which can slow down payment. If you believe the invoice is
                correct as-is, you can still submit it. If a failed check is explainable, close this warning and use
                Messages & Requested Changes before submitting.
              </Text>
              <Flex gap={3} flexWrap="wrap">
                <Button variant="outline" onClick={onSubmitWarningClose}>
                  Keep reviewing
                </Button>
                <Button colorScheme="red" onClick={submitToAdminDespiteFailures} isLoading={submitLoading}>
                  Submit Anyway
                </Button>
              </Flex>

              <Box borderWidth="1px" borderRadius="md" p={4} bg="red.50" borderColor="red.100">
                <Text fontSize="sm" fontWeight="bold" mb={3}>
                  Failed checks found
                </Text>
                <Flex direction="column" gap={3}>
                  {failingRulechecks.slice(0, 6).map((row: any) => {
                    const name = String(row.rule_key || 'invoice_review_check');
                    const groupName = String(row.upgrade_type_description || row.upgrade_type_key || 'Invoice');
                    const reason = row.reason_and_likely_causes || row.observed_text || row.evidence_text || '';

                    return (
                      <Box key={row.id ?? `${row.rule_number}-${row.rule_key}`} bg="white" borderRadius="md" p={3}>
                        <Flex align="center" gap={2} mb={1}>
                          <StatusDot result="fail" />
                          <Text fontSize="sm" fontWeight="semibold">
                            {name}
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
            </Flex>
          </ModalBody>
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
                  This screen shows invoice OCR fields, local information on record, review advice, line items, and the
                  PDF evidence used for review.
                </Text>
              </Box>
              <Box>
                <Heading size="sm" mb={2}>
                  Contractor Actions
                </Heading>
                <Text fontSize="sm">
                  Submit to Admin sends the invoice to the program team for first-level review. It is available after
                  the pre-check finishes, or when the program team has requested a revision.
                </Text>
              </Box>
            </Flex>
          </DrawerBody>
        </DrawerContent>
      </Drawer>
    </Flex>
  );
}
