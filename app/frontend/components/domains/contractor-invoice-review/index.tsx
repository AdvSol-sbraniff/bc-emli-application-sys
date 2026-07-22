import {
  Accordion,
  AccordionButton,
  AccordionIcon,
  AccordionItem,
  AccordionPanel,
  Badge,
  Box,
  Button,
  CloseButton,
  Container,
  Flex,
  IconButton,
  Modal,
  ModalBody,
  ModalCloseButton,
  ModalContent,
  ModalHeader,
  ModalOverlay,
  Spinner,
  Text,
  Tooltip,
  useDisclosure,
  useToast,
} from '@chakra-ui/react';
import {
  ArrowClockwise,
  ArrowSquareOut,
  CaretLeft,
  CaretRight,
  CornersOut,
  FrameCorners,
  MagnifyingGlassMinus,
  MagnifyingGlassPlus,
} from '@phosphor-icons/react';
import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import ReactMarkdown from 'react-markdown';
import { Document, Page, pdfjs } from 'react-pdf';
import 'react-pdf/dist/Page/AnnotationLayer.css';
import 'react-pdf/dist/Page/TextLayer.css';
import { useNavigate, useParams } from 'react-router-dom';
import { ThinBlueTitleBar } from '../../shared/base/thin-blue-title-bar';
import { ContractorConversationPanel } from '../../shared/claims/contractor-conversation-panel';
import {
  contractorRevisionPresentationState,
  ContractorInlineRevisionIssueCard,
  ContractorInlineRevisionStatus,
  useContractorInlineRevisionWorkspace,
} from '../../shared/claims/contractor-inline-revision-issues';
import { invoiceStatusCopy } from '../../shared/claims/invoice-status-copy';
import {
  ContractorDraftState,
  RevisionIssue,
  RevisionSourceIdentity,
  RevisionTrackerData,
} from '../../shared/claims/revision-tracker';
import { ViewerPanelMode, ViewerPanelModeSelector } from '../../shared/claims/viewer-panel-mode-selector';
import {
  getInvoiceUpgradeTypeMeta,
  INVOICE_UPGRADE_TYPE_FILTER_ORDER,
  InvoiceUpgradeTypeTile,
} from '../../shared/claims/invoice-upgrade-type-visual';
import { fmtDate, fmtMoney, fmtText } from '../invoice-versions/display';

pdfjs.GlobalWorkerOptions.workerSrc = `https://unpkg.com/pdfjs-dist@${pdfjs.version}/build/pdf.worker.min.mjs`;

type FieldRowProps = {
  label: string;
  labelHint?: string;
  value: unknown;
  active?: boolean;
  disabled?: boolean;
  onClick?: () => void;
  inline?: boolean;
};

type RuleResult = 'pass' | 'info' | 'warn' | 'fail' | null | undefined;
type FitMode = 'width' | 'page';

const CONTRACTOR_WITHDRAWABLE_INVOICE_STATUSES = new Set([
  'upload_failed',
  'ocr_failed',
  'genai_failed',
  'genai_complete',
  'package_needs_correction',
  'technical_failure',
  'admin_review_inbox',
  'contractor_revision_inbox',
  'in_review',
]);

const FieldRow = ({ label, labelHint, value, active, disabled, onClick, inline }: FieldRowProps) => (
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
    {labelHint ? (
      <Tooltip label={labelHint} hasArrow placement="top">
        <Text fontSize="sm" opacity={0.7} flexShrink={0} cursor="help">
          {label}
        </Text>
      </Tooltip>
    ) : (
      <Text fontSize="sm" opacity={0.7} flexShrink={0}>
        {label}
      </Text>
    )}
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

const fmtBytes = (n?: number | null) => {
  if (n === null || n === undefined) return '-';
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`;
  return `${(n / (1024 * 1024)).toFixed(2)} MB`;
};

const normalizeResult = (result: unknown): RuleResult => {
  const value = String(result ?? '')
    .trim()
    .toLowerCase();
  return value === 'pass' || value === 'info' || value === 'warn' || value === 'fail' ? value : null;
};

const ContractorAdviceMarkdown = ({ value, tone = 'advice' }: { value?: unknown; tone?: 'advice' | 'context' }) => {
  const text = String(value ?? '').trim();
  const contextual = tone === 'context';
  if (!text) {
    return (
      <Text fontSize="sm" opacity={0.7}>
        No program requirement found for this invoice version.
      </Text>
    );
  }

  return (
    <Box
      fontSize="sm"
      bg={contextual ? 'gray.50' : 'orange.50'}
      borderWidth="1px"
      borderColor={contextual ? 'gray.200' : 'orange.200'}
      borderLeftWidth={contextual ? '1px' : '5px'}
      borderLeftColor={contextual ? 'gray.200' : 'orange.400'}
      borderRadius="lg"
      px="4"
      py="3"
      boxShadow="sm"
      sx={{
        p: { marginBottom: '0.7rem' },
        'p:last-child': { marginBottom: 0 },
        ul: { paddingLeft: '0', marginTop: '0.7rem', marginBottom: '0.7rem', listStyleType: 'none' },
        li: {
          marginBottom: '0.75rem',
          padding: '0.85rem',
          borderRadius: '0.75rem',
          background: 'white',
          border: `1px solid var(--chakra-colors-${contextual ? 'gray-200' : 'orange-100'})`,
          boxShadow: '0 1px 2px rgba(15, 23, 42, 0.05)',
        },
        'li:last-child': { marginBottom: 0 },
        em: { fontStyle: 'italic', color: 'var(--chakra-colors-gray-800)' },
        a: {
          color: `var(--chakra-colors-${contextual ? 'blue-700' : 'orange-700'})`,
          cursor: 'help',
          textDecoration: 'none',
        },
        strong: { color: 'inherit' },
      }}
    >
      <ReactMarkdown
        components={{
          p: ({ children }: any) => (
            <Text as="p" fontSize="sm" whiteSpace="pre-wrap">
              {children}
            </Text>
          ),
          ul: ({ children }: any) => (
            <Box as="ul" pl="0" mt="2" mb="3">
              {children}
            </Box>
          ),
          li: ({ children }: any) => <Box as="li">{children}</Box>,
          em: ({ children }: any) => (
            <Text as="em" fontStyle="italic">
              {children}
            </Text>
          ),
          strong: ({ children }: any) => (
            <Text as="strong" fontWeight="bold">
              {children}
            </Text>
          ),
          a: ({ children, title }: any) => (
            <Tooltip label={title} hasArrow placement="top">
              <Text as="span" color={contextual ? 'blue.700' : 'orange.700'} cursor="help">
                {children}
              </Text>
            </Tooltip>
          ),
        }}
      >
        {text}
      </ReactMarkdown>
    </Box>
  );
};

const programRequirementWithoutPrecheckAction = (value: unknown): string => {
  const text = String(value ?? '').trim();
  const actionMarker = /\n+\*\*Action:\*\*/i;
  const markerIndex = text.search(actionMarker);
  return markerIndex >= 0 ? text.slice(0, markerIndex).trim() : text;
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

const hasLocatedFieldValue = (row: any): boolean => {
  if (row?.value_text != null && String(row.value_text).trim() !== '') return true;
  if (row?.value_json == null) return false;
  if (typeof row.value_json === 'string') return row.value_json.trim() !== '';
  if (Array.isArray(row.value_json)) return row.value_json.length > 0;
  if (typeof row.value_json === 'object') return Object.keys(row.value_json).length > 0;
  return true;
};

const displayLocatedFieldLabel = (row: any): string => {
  const configuredName = String(row?.contractor_display_name || '').trim();
  if (configuredName) return configuredName;

  const raw = String(row?.field_key || 'field')
    .trim()
    .replace(/^classifier\./i, '');
  if (!raw) return 'Field';
  return raw
    .replace(/_/g, ' ')
    .replace(/\b\w/g, (char) => char.toUpperCase())
    .replace(/\bAhri\b/g, 'AHRI')
    .replace(/\bHpwh\b/g, 'HPWH')
    .replace(/\bHrv\b/g, 'HRV')
    .replace(/\bErv\b/g, 'ERV')
    .replace(/\bNrcan\b/g, 'NRCan')
    .replace(/\bNeaa\b/g, 'NEAA')
    .replace(/\bNeea\b/g, 'NEEA')
    .replace(/\bEsp\b/g, 'ESP')
    .replace(/\bBc\b/g, 'BC')
    .replace(/\bDi\b/g, 'DI');
};

const locatedFieldKeyHint = (row: any): string => `Field key: ${String(row?.field_key || 'unknown')}`;

const displayVisualFindingLabel = (value: unknown): string => {
  const label = String(value || 'visual finding')
    .trim()
    .replace(/before_after/g, 'before/after')
    .replace(/_/g, ' ');
  return label ? `${label.charAt(0).toUpperCase()}${label.slice(1)}` : 'Visual finding';
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

const revisionSourceIdentityKey = (identity: RevisionSourceIdentity | undefined): string => {
  if (!identity?.kind) return '';
  if (identity.kind === 'rule') {
    return `rule:${String(identity.rule_key || '')}:${String(identity.invoice_upgrade_type_id || '')}`;
  }
  if (identity.kind === 'invoice_field') {
    return `invoice_field:${String(identity.field_key || '')}:${String(identity.invoice_upgrade_type_id || '')}`;
  }
  if (identity.kind === 'supporting_document_field') {
    return `supporting_document_field:${String(identity.supporting_document_type_key || '')}:${String(
      identity.field_key || '',
    )}`;
  }
  return `di_field:${String(identity.field_key || '')}`;
};

const revisionIssueIdentityKey = (issue: RevisionIssue): string => revisionSourceIdentityKey(issue.source_identity);

const rulecheckIdentityKey = (row: any): string =>
  `rule:${String(row?.rule_key || '')}:${String(row?.invoice_upgrade_type_id || '')}`;

const locatedFieldIdentityKey = (row: any): string =>
  `invoice_field:${String(row?.field_key || '')}:${String(row?.invoice_upgrade_type_id || '')}`;

const supportingFieldIdentityKey = (typeKey: unknown, fieldKey: unknown): string =>
  `supporting_document_field:${String(typeKey || '')}:${String(fieldKey || '')}`;

const diFieldIdentityKey = (fieldKey: unknown): string => `di_field:${String(fieldKey || '')}`;

export default function ContractorInvoiceReviewScreen() {
  const { sessionId, invoiceId } = useParams();
  const navigate = useNavigate();
  const toast = useToast();
  const pdfWrapRef = useRef<HTMLDivElement | null>(null);
  const { isOpen: isSubmitWarningOpen, onOpen: onSubmitWarningOpen, onClose: onSubmitWarningClose } = useDisclosure();
  const { isOpen: isWithdrawOpen, onOpen: onWithdrawOpen, onClose: onWithdrawClose } = useDisclosure();

  const [rightPanelMode, setRightPanelMode] = useState<ViewerPanelMode>('document');
  const [readData, setReadData] = useState<any>(null);
  const [genAiFields, setGenAiFields] = useState<any[]>([]);
  const [classifierFields, setClassifierFields] = useState<any[]>([]);
  const [genAiRulechecks, setGenAiRulechecks] = useState<any[]>([]);
  const [genAiError, setGenAiError] = useState<string | null>(null);
  const [upgradeTypeResults, setUpgradeTypeResults] = useState<any[]>([]);
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
  const [numPages, setNumPages] = useState<number>(0);
  const [activeHighlightKey, setActiveHighlightKey] = useState<string>('invoice_id');
  const [activePageNumber, setActivePageNumber] = useState<number>(1);
  const [activeHighlight, setActiveHighlight] = useState<{
    source: 'di' | 'genai' | 'code' | 'classifier' | 'supporting_document';
    key?: string;
    genaiId?: number;
    supportingDocumentId?: string;
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
  const [finishLaterLoading, setFinishLaterLoading] = useState(false);
  const [withdrawalLoading, setWithdrawalLoading] = useState(false);
  const [revisionRefreshToken, setRevisionRefreshToken] = useState(0);
  const [revisionAttentionIssueIds, setRevisionAttentionIssueIds] = useState<string[]>([]);
  const [contractorDraftState, setContractorDraftState] = useState<ContractorDraftState | null>(null);
  const [chatPanelOpen, setChatPanelOpen] = useState(false);
  const [chatUnreadCount, setChatUnreadCount] = useState(0);

  useEffect(() => {
    if (!chatPanelOpen) return;
    const closeOnEscape = (event: KeyboardEvent) => {
      if (event.key === 'Escape') setChatPanelOpen(false);
    };
    window.addEventListener('keydown', closeOnEscape);
    return () => window.removeEventListener('keydown', closeOnEscape);
  }, [chatPanelOpen]);

  const currentStatus = String(readData?.invoice_status || '').trim();
  const currentStatusSubtype = String(readData?.invoice_status_subtype || '').trim();
  const currentInvoiceId = String(readData?.invoice_id || invoiceId || '').trim();
  const adoptRevisionTrackerData = useCallback((next: RevisionTrackerData) => {
    setRevisionAttentionIssueIds(next.capabilities?.document_upload_required_issue_ids || []);
  }, []);
  const revisionWorkspace = useContractorInlineRevisionWorkspace({
    invoiceId: currentInvoiceId,
    refreshToken: revisionRefreshToken,
    onTrackerChange: adoptRevisionTrackerData,
    onDraftStateChange: setContractorDraftState,
  });
  const revisionTrackerData = revisionWorkspace.data;
  const savedRevisionResponsesComplete = revisionTrackerData?.capabilities?.can_submit_response === true;
  const documentUploadRequiredIssueIds = revisionTrackerData?.capabilities?.document_upload_required_issue_ids || [];
  const visibleRevisionDraftsComplete =
    contractorDraftState == null ||
    (contractorDraftState.allEditableDraftsComplete && !contractorDraftState.hasUnsavedChanges);
  const revisionResponsesComplete = savedRevisionResponsesComplete && visibleRevisionDraftsComplete;
  const canSubmit =
    currentStatus === 'genai_complete' || (currentStatus === 'contractor_revision_inbox' && revisionResponsesComplete);
  const canUploadFix = currentStatus === 'genai_complete' || currentStatus === 'contractor_revision_inbox';
  const canWithdraw = CONTRACTOR_WITHDRAWABLE_INVOICE_STATUSES.has(currentStatus);
  const submitTooltip =
    currentStatus === 'contractor_revision_inbox' && contractorDraftState?.hasUnsavedChanges
      ? 'Save every changed revision response before sending it to the program team.'
      : currentStatus === 'contractor_revision_inbox' && documentUploadRequiredIssueIds.length > 0
        ? 'Upload and process the corrected documentation before sending it to the program team.'
        : currentStatus === 'contractor_revision_inbox' && !revisionResponsesComplete
          ? 'Complete and save a response for every open revision issue before sending it to the program team.'
          : canSubmit
            ? 'Send this invoice to the program team for first-level review.'
            : 'Submission is available after the pre-check finishes, or when the program team has requested a revision.';
  const currentStatusCopy = invoiceStatusCopy(currentStatus, currentStatusSubtype);
  const contractorActionableRulechecks = useMemo(
    () =>
      genAiRulechecks.filter((row: any) => {
        const result = normalizeResult(row?.rule_result);
        const visibility = String(row?.contractor_visibility || 'hidden');
        if (visibility === 'warn_and_fail') return result === 'warn' || result === 'fail';
        return visibility === 'fail_only' && result === 'fail';
      }),
    [genAiRulechecks],
  );
  const blockingRulechecks = useMemo(
    () =>
      contractorActionableRulechecks.filter(
        (row: any) =>
          normalizeResult(row?.rule_result) === 'fail' && row?.contractor_blocking_policy === 'block_on_fail',
      ),
    [contractorActionableRulechecks],
  );

  const loadReviewData = useCallback(async () => {
    if (!sessionId || !invoiceId) return;

    const [readResp, pdfResp, genaiResp] = await Promise.all([
      fetch(`/api/claims/sessions/${encodeURIComponent(sessionId)}/invoices/${encodeURIComponent(invoiceId)}/read`, {
        headers: { Accept: 'application/json' },
        credentials: 'include',
      }),
      fetch(`/api/claims/sessions/${encodeURIComponent(sessionId)}/invoices/${encodeURIComponent(invoiceId)}/pdf_url`, {
        headers: { Accept: 'application/json' },
        credentials: 'include',
      }),
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
    const pdfJson = await pdfResp.json().catch(() => ({}));
    if (!pdfResp.ok || !pdfJson?.sas_url) {
      setPdfUrl(null);
      setPdfUrlError(pdfJson?.error || `Could not load PDF URL (${pdfResp.status}).`);
    } else {
      setPdfUrl(String(pdfJson.sas_url));
      setPdfUrlError(null);
      setViewerFile({
        source: 'invoice',
        url: String(pdfJson.sas_url),
        filename: read?.original_filename || 'Invoice',
        mimeType: read?.content_type || 'application/pdf',
      });
      setViewerPageMetaByPage({});
    }

    if (!genaiResp.ok) {
      const txt = await genaiResp.text();
      setGenAiFields([]);
      setClassifierFields([]);
      setUpgradeTypeResults([]);
      setGenAiRulechecks([]);
      setGenAiError(`read_genai failed (${genaiResp.status}): ${txt}`);
      return;
    }

    const genaiJson = await genaiResp.json().catch(() => ({}));
    setGenAiFields(Array.isArray(genaiJson?.located_fields) ? genaiJson.located_fields : []);
    setClassifierFields(Array.isArray(genaiJson?.classifier_located_fields) ? genaiJson.classifier_located_fields : []);
    setUpgradeTypeResults(Array.isArray(genaiJson?.upgrade_type_results) ? genaiJson.upgrade_type_results : []);
    setGenAiRulechecks([
      ...(Array.isArray(genaiJson?.code_rulechecks) ? genaiJson.code_rulechecks : []),
      ...(Array.isArray(genaiJson?.rulechecks) ? genaiJson.rulechecks : []),
    ]);
    setGenAiError(null);
  }, [invoiceId, sessionId]);

  useEffect(() => {
    void loadReviewData();
  }, [loadReviewData]);

  useEffect(() => {
    if (rightPanelMode !== 'document') return;
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
  }, [rightPanelMode]);

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
    if (!activeHighlight || activeHighlight.source === 'supporting_document' || !pdfUrl) return;
    setViewerFile({
      source: 'invoice',
      url: pdfUrl,
      filename: readData?.original_filename || 'Invoice',
      mimeType: readData?.content_type || 'application/pdf',
    });
  }, [activeHighlight, pdfUrl, readData?.content_type, readData?.original_filename]);

  useEffect(() => {
    setPageInput(String(activePageNumber));
  }, [activePageNumber]);

  const activePageMeta = useMemo(() => {
    if (viewerFile?.source === 'supporting_document') {
      const pageNumber = activeHighlight?.pageNumber || activePageNumber || 1;
      return viewerPageMetaByPage[Number(pageNumber)] ?? null;
    }

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
  }, [activeHighlight?.pageNumber, activePageNumber, readData?.di_page_map, viewerFile?.source, viewerPageMetaByPage]);

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
    if (!poly || !meta) return null;
    if (meta.unit !== 'inch' && meta.unit !== 'pixel') return null;

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

  const shouldShowActivePolygon =
    !!svgPolygonPoints &&
    activeHighlight?.pageNumber != null &&
    Number(activeHighlight.pageNumber) === Number(activePageNumber);

  const overlayWidthPx = renderWidthPx;
  const viewerUrl = viewerFile?.url || pdfUrl;
  const viewerFilename = String(viewerFile?.filename || 'Invoice').trim();
  const viewerMimeType = String(viewerFile?.mimeType || '').toLowerCase();
  const viewerIsImage =
    viewerMimeType.startsWith('image/') || /\.(png|jpe?g|gif|webp|bmp|tiff?)($|\?)/i.test(viewerUrl || viewerFilename);

  const classifierDisplayFields = useMemo(
    () =>
      classifierFields.filter((row) => {
        const fieldKey = String(row?.field_key ?? '').toLowerCase();
        return (
          fieldKey !== 'classifier.eligibility' &&
          fieldKey !== 'classifier.eligibility_code' &&
          hasLocatedFieldValue(row)
        );
      }),
    [classifierFields],
  );

  const commonInvoiceFields = useMemo(
    () => genAiFields.filter((row) => hasLocatedFieldValue(row) && fieldUpgradeTypeKey(row) === 'common'),
    [genAiFields],
  );

  const detailsGroups = useMemo(() => {
    const groups = new Map<
      string,
      {
        description: string;
        fields: any[];
        upgradeTypeKey: string;
      }
    >();

    const ensureGroup = (row: any, fallbackKey?: string, fallbackDescription?: string) => {
      const upgradeTypeKey = fallbackKey || fieldUpgradeTypeKey(row);
      const existing = groups.get(upgradeTypeKey);
      if (existing) return existing;

      const group = {
        description: fallbackDescription || upgradeTypeDescriptionFor(row),
        fields: [],
        upgradeTypeKey,
      };
      groups.set(upgradeTypeKey, group);
      return group;
    };

    genAiFields
      .filter((row) => hasLocatedFieldValue(row) && fieldUpgradeTypeKey(row) !== 'common')
      .forEach((row) => ensureGroup(row).fields.push(row));

    return Array.from(groups.values()).sort((a, b) => {
      const sortA = upgradeTypeSortValue(a.upgradeTypeKey);
      const sortB = upgradeTypeSortValue(b.upgradeTypeKey);
      if (sortA !== sortB) return sortA - sortB;
      return a.description.localeCompare(b.description);
    });
  }, [genAiFields]);

  const ahriProduct = readData?.ahri_product_match?.product;
  const neeaProduct = readData?.neea_product_match?.product;
  const awhpProduct = readData?.awhp_product_match?.product;
  const ohpaProduct = readData?.ohpa_product_match?.product;
  const hervProduct = readData?.herv_product_match?.product;
  const ventFanProduct = readData?.vent_fan_product_match?.product;
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
  const supportingDocumentEvidenceSections = useMemo(() => {
    const sectionMap = new Map<string, { key: string; title: string; documents: any[] }>();
    const ensureSection = (rawKey: unknown, rawTitle: unknown) => {
      const title = String(rawTitle || rawKey || 'Unclassified document').trim() || 'Unclassified document';
      const key =
        String(rawKey || title)
          .trim()
          .toLowerCase() || 'unclassified-document';
      const existing = sectionMap.get(key);
      if (existing) return existing;
      const section = { key, title, documents: [] as any[] };
      sectionMap.set(key, section);
      return section;
    };

    uploadedSupportingDocuments.forEach((doc: any) => {
      ensureSection(
        doc?.supporting_document_type_key || doc?.supporting_document_type_description || doc?.content_type,
        doc?.supporting_document_type_description || doc?.supporting_document_type_key || doc?.content_type,
      ).documents.push(doc);
    });

    return Array.from(sectionMap.values()).sort((a, b) => a.title.localeCompare(b.title));
  }, [uploadedSupportingDocuments]);
  const visibleRevisionIssues = useMemo(
    () => revisionWorkspace.issues.filter((issue) => issue.status !== 'closed_no_contractor_action_required'),
    [revisionWorkspace.issues],
  );
  const revisionIssueByIdentity = useMemo(() => {
    const index = new Map<string, RevisionIssue>();
    visibleRevisionIssues.forEach((issue) => {
      const key = revisionIssueIdentityKey(issue);
      if (key) index.set(key, issue);
    });
    return index;
  }, [visibleRevisionIssues]);
  const suppressedRuleIdentityKeys = useMemo(
    () =>
      new Set(
        (revisionWorkspace.data?.suppressed_source_identities || [])
          .filter((identity) => identity.kind === 'rule')
          .map(revisionSourceIdentityKey)
          .filter(Boolean),
      ),
    [revisionWorkspace.data?.suppressed_source_identities],
  );
  const supportingFieldIdentityCounts = useMemo(() => {
    const counts = new Map<string, number>();
    uploadedSupportingDocuments.forEach((doc: any) => {
      const typeKey = String(doc?.supporting_document_type_key || '');
      const fields = Array.isArray(doc?.located_fields) ? doc.located_fields : [];
      fields.forEach((field: any) => {
        const key = supportingFieldIdentityKey(typeKey, field?.field_key);
        counts.set(key, (counts.get(key) || 0) + 1);
      });
    });
    return counts;
  }, [uploadedSupportingDocuments]);
  const programRequirementRulechecks = useMemo(() => {
    const rows = genAiRulechecks.filter(
      (row: any) =>
        !suppressedRuleIdentityKeys.has(rulecheckIdentityKey(row)) &&
        (contractorActionableRulechecks.includes(row) || revisionIssueByIdentity.has(rulecheckIdentityKey(row))),
    );
    const seen = new Set<string>();
    return rows.filter((row: any) => {
      const key = rulecheckIdentityKey(row);
      if (seen.has(key)) return false;
      seen.add(key);
      return true;
    });
  }, [contractorActionableRulechecks, genAiRulechecks, revisionIssueByIdentity, suppressedRuleIdentityKeys]);
  const renderedRevisionIdentityKeys = useMemo(() => {
    const keys = new Set<string>();
    programRequirementRulechecks.forEach((row: any) => keys.add(rulecheckIdentityKey(row)));
    DI_FIELDS.forEach((field) => keys.add(diFieldIdentityKey(field.key)));
    [...genAiFields, ...classifierFields]
      .filter(hasLocatedFieldValue)
      .forEach((row: any) => keys.add(locatedFieldIdentityKey(row)));
    supportingFieldIdentityCounts.forEach((count, key) => {
      if (count === 1) keys.add(key);
    });
    return keys;
  }, [classifierFields, genAiFields, programRequirementRulechecks, supportingFieldIdentityCounts]);
  const unmatchedRevisionIssues = useMemo(
    () =>
      visibleRevisionIssues.filter((issue) => {
        const key = revisionIssueIdentityKey(issue);
        return !key || !renderedRevisionIdentityKeys.has(key);
      }),
    [renderedRevisionIdentityKeys, visibleRevisionIssues],
  );

  const revisionIssueForRulecheck = (row: any) => revisionIssueByIdentity.get(rulecheckIdentityKey(row));
  const revisionIssueForLocatedField = (row: any) => revisionIssueByIdentity.get(locatedFieldIdentityKey(row));
  const revisionIssueForDiField = (fieldKey: string) => revisionIssueByIdentity.get(diFieldIdentityKey(fieldKey));
  const revisionIssueForSupportingField = (typeKey: unknown, fieldKey: unknown) => {
    const key = supportingFieldIdentityKey(typeKey, fieldKey);
    return supportingFieldIdentityCounts.get(key) === 1 ? revisionIssueByIdentity.get(key) : undefined;
  };
  const programRequirementDefaultIndices = programRequirementRulechecks.flatMap((row: any, index: number) => {
    const issue = revisionIssueForRulecheck(row);
    if (!issue) return [];
    const state = contractorRevisionPresentationState(issue, revisionWorkspace.data);
    return state.key === 'action_required' || state.key === 'upload_required' ? [index] : [];
  });

  const supportingDocumentUrl = (docId: string) =>
    `/api/claims/sessions/${encodeURIComponent(String(sessionId || ''))}/invoices/${encodeURIComponent(
      String(invoiceId || ''),
    )}/supporting_documents/${encodeURIComponent(docId)}/pdf_url`;

  const openSupportingDocumentFile = async (doc: any) => {
    const docId = String(doc?.id || '').trim();
    if (!docId || !sessionId || !invoiceId) {
      toast({
        title: 'Cannot open file',
        description: 'This supporting document is missing its file context.',
        status: 'error',
        duration: 3500,
        isClosable: true,
      });
      return;
    }

    try {
      const resp = await fetch(supportingDocumentUrl(docId), {
        headers: { Accept: 'application/json' },
        credentials: 'include',
      });
      const json = await resp.json().catch(() => ({}));
      const fileUrl = String(json?.sas_url || '').trim();
      if (!resp.ok || !fileUrl) throw new Error(json?.error || `File URL request failed (${resp.status})`);
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
        const highlightKey = `supporting_field_${String(field?.id || field?.field_key || 'unknown')}`;
        setActiveHighlight({
          source: 'supporting_document',
          key: highlightKey,
          supportingDocumentId: docId,
          pageNumber: field?.page != null ? Number(field.page) : 1,
          polygon: field?.polygon ?? null,
        });
        setActiveHighlightKey(highlightKey);
      } else {
        setActiveHighlight({
          source: 'supporting_document',
          key: `supporting_document_${docId}`,
          supportingDocumentId: docId,
          pageNumber: 1,
          polygon: null,
        });
        setActiveHighlightKey(`supporting_document_${docId}`);
        setActivePageNumber(1);
      }
    };

    if (!docId || !sessionId || !invoiceId) {
      toast({
        title: 'Cannot show file',
        description: 'This supporting document is missing its file context.',
        status: 'error',
        duration: 3500,
        isClosable: true,
      });
      return;
    }

    if (viewerFile?.source === 'supporting_document' && viewerFile.documentId === docId && viewerFile.url) {
      setSupportingDocumentHighlight();
      setRightPanelMode('document');
      return;
    }

    try {
      const resp = await fetch(supportingDocumentUrl(docId), {
        headers: { Accept: 'application/json' },
        credentials: 'include',
      });
      const json = await resp.json().catch(() => ({}));
      const fileUrl = String(json?.sas_url || '').trim();
      if (!resp.ok || !fileUrl) throw new Error(json?.error || `File URL request failed (${resp.status})`);

      setViewerPageMetaByPage({});
      setViewerFile({
        source: 'supporting_document',
        url: fileUrl,
        filename,
        mimeType,
        documentId: docId,
      });
      setSupportingDocumentHighlight();
      setRightPanelMode('document');
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
      if (!resp.ok) {
        const incompleteEntryIds = Array.isArray(json?.issue_ids)
          ? json.issue_ids.map((id: unknown) => String(id)).filter(Boolean)
          : [];
        const revisionResponseError =
          json?.error_code === 'revision_response_incomplete' ||
          json?.error_code === 'revision_document_upload_required';
        if (revisionResponseError && incompleteEntryIds.length) {
          setRevisionAttentionIssueIds(incompleteEntryIds);
          window.scrollTo({ top: 0, behavior: 'smooth' });
        }
        const suffix =
          json?.error_code === 'revision_document_upload_required'
            ? ' Upload the corrected documentation and wait for processing to finish.'
            : incompleteEntryIds.length
              ? ' Complete the highlighted revision response and save it.'
              : '';
        throw new Error(`${json?.error || `Submit failed (${resp.status}).`}${suffix}`);
      }
      setRevisionAttentionIssueIds([]);
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
      setRevisionRefreshToken((value) => value + 1);
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
    if (currentStatus === 'contractor_revision_inbox') {
      void submitToAdmin();
      return;
    }
    if (contractorActionableRulechecks.length > 0) {
      onSubmitWarningOpen();
      return;
    }
    void submitToAdmin();
  };

  const submitToAdminAfterReview = () => {
    onSubmitWarningClose();
    void submitToAdmin();
  };

  const saveAndFinishLater = async () => {
    if (finishLaterLoading) return;
    setFinishLaterLoading(true);
    try {
      const saved = await revisionWorkspace.saveAll();
      if (!saved) {
        window.scrollTo({ top: 0, behavior: 'smooth' });
        return;
      }
      navigate('/ai-contractor-dashboard');
    } finally {
      setFinishLaterLoading(false);
    }
  };

  const withdrawInvoice = async () => {
    if (!currentInvoiceId || !canWithdraw || withdrawalLoading) return;
    setWithdrawalLoading(true);
    try {
      const response = await fetch(`/api/claims/contractor/invoices/${encodeURIComponent(currentInvoiceId)}/withdraw`, {
        method: 'POST',
        headers: { Accept: 'application/json' },
        credentials: 'include',
      });
      const json = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(json?.error || 'Could not withdraw this invoice.');

      onWithdrawClose();
      toast({
        title: 'Invoice withdrawn',
        description: 'The invoice has been withdrawn and will not continue through review.',
        status: 'success',
        duration: 5000,
        isClosable: true,
      });
      navigate('/ai-contractor-dashboard');
    } catch (reason: any) {
      toast({
        title: 'Invoice not withdrawn',
        description: reason?.message || 'Please try again.',
        status: 'error',
        duration: 6000,
        isClosable: true,
      });
    } finally {
      setWithdrawalLoading(false);
    }
  };

  const openFixUpload = () => {
    if (!sessionId || !currentInvoiceId) return;
    window.open(
      `/contractor/sessions/${encodeURIComponent(sessionId)}/invoices/${encodeURIComponent(currentInvoiceId)}/fix`,
      '_blank',
      'noopener,noreferrer',
    );
  };

  const renderLocatedFieldRow = (row: any, key: React.Key) => {
    const highlightKey = `found_${row.source_engine || 'field'}_${row.id}`;
    const clickable = row.page != null;
    const issue = revisionIssueForLocatedField(row);

    return (
      <Box key={key} minW={0} gridColumn={issue ? '1 / -1' : undefined}>
        <FieldRow
          label={displayLocatedFieldLabel(row)}
          labelHint={locatedFieldKeyHint(row)}
          value={displayLocatedFieldValue(row)}
          active={activeHighlightKey === highlightKey}
          disabled={!clickable}
          inline
          onClick={
            clickable
              ? () => {
                  const sourceEngine = String(row.source_engine || '').toLowerCase();
                  setActiveHighlight({
                    source: sourceEngine === 'classifier' ? 'classifier' : sourceEngine === 'code' ? 'code' : 'genai',
                    genaiId: Number(row.id),
                    pageNumber: Number(row.page),
                    polygon: row.polygon ?? null,
                  });
                  setActiveHighlightKey(highlightKey);
                  setRightPanelMode('document');
                }
              : undefined
          }
        />
        {issue ? (
          <ContractorInlineRevisionIssueCard
            issue={issue}
            workspace={revisionWorkspace}
            compactHeading
            attention={revisionAttentionIssueIds.includes(issue.id)}
          />
        ) : null}
      </Box>
    );
  };

  return (
    <Flex as="main" direction="column" w="full" bg="greys.white" pb="24" minH="100vh">
      <ThinBlueTitleBar
        title="Contractor Invoice Review"
        position="sticky"
        top={0}
        zIndex="sticky"
        boxShadow="0 4px 12px rgba(0, 0, 0, 0.16)"
        rightElement={
          <Flex align="center" gap="10px">
            <Button
              size="md"
              variant="outline"
              color="white"
              borderColor="whiteAlpha.800"
              borderRadius="md"
              px={6}
              _hover={{ bg: 'whiteAlpha.200' }}
              _active={{ bg: 'whiteAlpha.300' }}
              isDisabled={revisionWorkspace.loading || submitLoading}
              isLoading={finishLaterLoading}
              loadingText="Saving"
              onClick={() => void saveAndFinishLater()}
            >
              Save and finish later
            </Button>
            <Tooltip label={submitTooltip} hasArrow shouldWrapChildren>
              <Button
                size="md"
                bg="#FFFFFF"
                color="blue.800"
                borderRadius="md"
                px={7}
                boxShadow={canSubmit ? '0 6px 16px rgba(0, 0, 0, 0.2)' : 'none'}
                _hover={{ bg: 'gray.100' }}
                _active={{ bg: 'gray.200' }}
                _disabled={{ bg: '#FFFFFF', color: 'blue.800', opacity: 0.55, cursor: 'not-allowed' }}
                isDisabled={!canSubmit}
                isLoading={submitLoading}
                onClick={requestSubmitToAdmin}
              >
                Submit
              </Button>
            </Tooltip>
            <Tooltip
              label={
                canUploadFix
                  ? 'Open the fix upload screen in a new tab.'
                  : 'Fix upload is available after the pre-check finishes, or when the program team has requested a revision.'
              }
              hasArrow
              shouldWrapChildren
            >
              <Button
                size="md"
                colorScheme="orange"
                variant={canUploadFix ? 'solid' : 'outline'}
                borderRadius="md"
                boxShadow={canUploadFix ? '0 8px 18px rgba(221, 107, 32, 0.18)' : 'none'}
                isDisabled={!canUploadFix || !sessionId || !currentInvoiceId}
                onClick={openFixUpload}
              >
                Upload
              </Button>
            </Tooltip>
            <Tooltip
              label={
                canWithdraw ? 'Withdraw this invoice from the program.' : 'This invoice can no longer be withdrawn.'
              }
              hasArrow
              shouldWrapChildren
            >
              <Button
                size="md"
                colorScheme="red"
                variant="solid"
                borderRadius="md"
                isDisabled={!canWithdraw || submitLoading || finishLaterLoading}
                isLoading={withdrawalLoading}
                onClick={onWithdrawOpen}
              >
                Withdraw
              </Button>
            </Tooltip>
          </Flex>
        }
      />
      <Container maxW="full" px={6} pb={4} flex="1" pt={6}>
        <Box display="flex" flexDirection="column" height="100%">
          <Box w="full" mb="16px" pb="14px" borderBottomWidth="1px" borderBottomColor="gray.200">
            <Text fontSize="sm" fontWeight="bold" color="blue.800" mb="8px">
              Attention Required
            </Text>
            <ContractorInlineRevisionStatus workspace={revisionWorkspace} />
            {revisionWorkspace.loading ? null : programRequirementRulechecks.length > 0 ? (
              <Accordion allowMultiple defaultIndex={programRequirementDefaultIndices}>
                {programRequirementRulechecks.map((row: any) => {
                  const issue = revisionIssueForRulecheck(row);
                  const title = String(row?.contractor_display_name || row?.rule_key || 'Program requirement');
                  const revisionStatus = issue
                    ? contractorRevisionPresentationState(issue, revisionWorkspace.data)
                    : null;

                  return (
                    <AccordionItem key={rulecheckIdentityKey(row)} borderColor="gray.200">
                      <h2>
                        <AccordionButton px="10px" py="8px">
                          <Flex flex="1" minW={0} align="center" gap="8px" wrap="wrap" textAlign="left">
                            <Text fontSize="sm" fontWeight="bold" noOfLines={2}>
                              {title}
                            </Text>
                            {revisionStatus ? (
                              <Badge colorScheme={revisionStatus.colorScheme} flexShrink={0}>
                                {revisionStatus.label}
                              </Badge>
                            ) : null}
                          </Flex>
                          <AccordionIcon />
                        </AccordionButton>
                      </h2>
                      <AccordionPanel px="10px" pt="8px" pb="12px">
                        {issue ? (
                          <>
                            <ContractorInlineRevisionIssueCard
                              issue={issue}
                              workspace={revisionWorkspace}
                              compactHeading
                              attention={revisionAttentionIssueIds.includes(issue.id)}
                            />
                            <Accordion allowToggle mt={3}>
                              <AccordionItem border="0" borderTopWidth="1px" borderColor="gray.200">
                                <h3>
                                  <AccordionButton px={0} py={3} _hover={{ bg: 'transparent' }}>
                                    <Text
                                      flex="1"
                                      textAlign="left"
                                      fontSize="xs"
                                      fontWeight="semibold"
                                      color="gray.700"
                                    >
                                      Program requirements — why this was flagged
                                    </Text>
                                    <AccordionIcon />
                                  </AccordionButton>
                                </h3>
                                <AccordionPanel px={0} pt={0} pb={0}>
                                  <ContractorAdviceMarkdown
                                    value={programRequirementWithoutPrecheckAction(row?.source_quote)}
                                    tone="context"
                                  />
                                </AccordionPanel>
                              </AccordionItem>
                            </Accordion>
                          </>
                        ) : (
                          <>
                            <Text fontSize="xs" fontWeight="bold" color="blue.800" mb="6px">
                              Program Requirements
                            </Text>
                            <ContractorAdviceMarkdown value={row?.source_quote} />
                          </>
                        )}
                      </AccordionPanel>
                    </AccordionItem>
                  );
                })}
              </Accordion>
            ) : (
              <Box px="10px" py="3px">
                {genAiError && readData?.contractor_advice ? (
                  <>
                    <Text fontSize="xs" fontWeight="bold" color="blue.800" mb="6px">
                      Program Requirements
                    </Text>
                    <ContractorAdviceMarkdown value={readData.contractor_advice} />
                  </>
                ) : (
                  <Text fontSize="sm" opacity={0.7}>
                    No program requirements currently require action.
                  </Text>
                )}
              </Box>
            )}
          </Box>

          <Box display="flex" alignItems="center" gap="10px" mb="12px" flexWrap="wrap">
            <ViewerPanelModeSelector value={rightPanelMode} onChange={setRightPanelMode} includeRevision={false} />
          </Box>

          <Box display="flex" gap="16px" flex="1" minH={0}>
            <Box
              p="0"
              sx={{ resize: 'horizontal', overflow: 'auto' }}
              minW="480px"
              maxW="100%"
              w="auto"
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
                        const issue = revisionIssueForDiField(field.key);
                        return (
                          <Box key={field.key} minW={0} gridColumn={issue ? '1 / -1' : undefined}>
                            <FieldRow
                              label={field.label}
                              value={display}
                              active={activeHighlightKey === field.key}
                              disabled={!clickable}
                              inline
                              onClick={clickable ? () => setActiveHighlightKey(field.key) : undefined}
                            />
                            {issue ? (
                              <ContractorInlineRevisionIssueCard
                                issue={issue}
                                workspace={revisionWorkspace}
                                compactHeading
                                attention={revisionAttentionIssueIds.includes(issue.id)}
                              />
                            ) : null}
                          </Box>
                        );
                      })}
                    </Box>
                    {commonInvoiceFields.length > 0 && (
                      <Box mt="10px" pt="10px" borderTopWidth="1px" borderColor="gray.200">
                        <Text fontSize="xs" fontWeight="bold" textTransform="uppercase" mb="4px">
                          Additional details found
                        </Text>
                        <Box display="grid" gridTemplateColumns="1fr 1fr" columnGap="8px" rowGap="0">
                          {commonInvoiceFields.map((row: any) =>
                            renderLocatedFieldRow(row, `common-${row.id ?? row.field_key}`),
                          )}
                        </Box>
                      </Box>
                    )}
                  </AccordionPanel>
                </AccordionItem>

                <AccordionItem borderTopWidth="1px" borderColor="gray.200">
                  <h2>
                    <AccordionButton px="0" py="6px" _hover={{ bg: 'transparent' }}>
                      <Box flex="1" textAlign="left">
                        <Text size="sm" fontWeight="bold">
                          Details We Found
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
                    {!genAiError && detailsGroups.length === 0 ? (
                      <Text fontSize="sm" opacity={0.7}>
                        No upgrade-specific details found.
                      </Text>
                    ) : (
                      <Box display="flex" flexDirection="column" gap="14px">
                        {detailsGroups.map((group) => {
                          const meta = getInvoiceUpgradeTypeMeta(group.upgradeTypeKey, group.description);

                          return (
                            <Box key={group.upgradeTypeKey}>
                              <Flex align="center" gap="8px" mb="6px">
                                <Text fontSize="sm" fontWeight="bold">
                                  {meta.label}
                                </Text>
                                <InvoiceUpgradeTypeTile
                                  upgradeTypeKey={group.upgradeTypeKey}
                                  description={group.description}
                                  size={24}
                                />
                              </Flex>
                              <Box display="grid" gridTemplateColumns="1fr 1fr" columnGap="8px" rowGap="0">
                                {group.fields.map((row: any) =>
                                  renderLocatedFieldRow(row, `${group.upgradeTypeKey}-${row.id ?? row.field_key}`),
                                )}
                              </Box>
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
                  supportingDocumentEvidenceSections.flatMap((section) =>
                    section.documents.map((doc: any) => {
                      const fields = Array.isArray(doc?.located_fields) ? doc.located_fields : [];
                      const findings = Array.isArray(doc?.visual_findings) ? doc.visual_findings : [];
                      const filename = String(doc?.original_filename || 'Unnamed file');
                      const showFilename = section.documents.length > 1;

                      return (
                        <AccordionItem
                          key={String(doc?.id || doc?.storage_key || 'supporting-doc')}
                          borderTopWidth="1px"
                          borderColor="gray.200"
                        >
                          <h2>
                            <AccordionButton px="0" py="6px" _hover={{ bg: 'transparent' }}>
                              <Box flex="1" textAlign="left" minW={0}>
                                <Text size="sm" fontWeight="bold" noOfLines={1}>
                                  {`Supporting document - ${section.title}${showFilename ? ` - ${filename}` : ''}`}
                                </Text>
                              </Box>
                              <AccordionIcon />
                            </AccordionButton>
                          </h2>
                          <AccordionPanel px="0" pt="8px">
                            <Box px="10px" py="3px">
                              <Flex justify="flex-end" gap="8px" mb="6px">
                                <Tooltip label={`Show ${filename} in application`}>
                                  <IconButton
                                    aria-label={`Show ${filename} in application`}
                                    icon={<FrameCorners size={24} weight="bold" />}
                                    size="lg"
                                    variant="outline"
                                    colorScheme="green"
                                    onClick={() => void showSupportingDocumentInViewer(doc)}
                                  />
                                </Tooltip>
                                <Tooltip label={`Open ${filename} in browser`}>
                                  <IconButton
                                    aria-label={`Open ${filename} in browser`}
                                    icon={<ArrowSquareOut size={24} weight="bold" />}
                                    size="lg"
                                    variant="outline"
                                    colorScheme="blue"
                                    onClick={() => void openSupportingDocumentFile(doc)}
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
                                    const fieldKey = `supporting_field_${String(
                                      field?.id || field?.field_key || 'unknown',
                                    )}`;
                                    const isActive =
                                      activeHighlight?.source === 'supporting_document' &&
                                      activeHighlight?.supportingDocumentId === String(doc?.id) &&
                                      activeHighlight?.key === fieldKey;
                                    const fieldValue =
                                      field?.value_text != null
                                        ? String(field.value_text)
                                        : field?.value_json != null
                                          ? JSON.stringify(field.value_json)
                                          : 'not found';
                                    const handleClick = clickable
                                      ? () => void showSupportingDocumentInViewer(doc, field)
                                      : undefined;
                                    const issue = revisionIssueForSupportingField(
                                      doc?.supporting_document_type_key,
                                      field?.field_key,
                                    );

                                    return (
                                      <React.Fragment key={String(field?.id || field?.field_key)}>
                                        <Tooltip label={locatedFieldKeyHint(field)} hasArrow placement="top">
                                          <Text
                                            fontSize="sm"
                                            opacity={0.7}
                                            noOfLines={1}
                                            cursor="help"
                                            bg={isActive ? 'red.50' : 'transparent'}
                                            borderRadius="sm"
                                            onClick={handleClick}
                                          >
                                            {displayLocatedFieldLabel(field)}
                                          </Text>
                                        </Tooltip>
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
                                        {issue ? (
                                          <Box gridColumn="1 / -1" mb="6px">
                                            <ContractorInlineRevisionIssueCard
                                              issue={issue}
                                              workspace={revisionWorkspace}
                                              compactHeading
                                              attention={revisionAttentionIssueIds.includes(issue.id)}
                                            />
                                          </Box>
                                        ) : null}
                                      </React.Fragment>
                                    );
                                  })}
                                </Box>
                              )}

                              {findings.length > 0 && (
                                <Box mt="10px">
                                  <Text fontSize="sm" fontWeight="bold" opacity={0.78}>
                                    Visual findings
                                  </Text>
                                  <Box
                                    mt="4px"
                                    display="grid"
                                    gridTemplateColumns="160px minmax(0, 1fr)"
                                    columnGap="8px"
                                    rowGap="6px"
                                    alignItems="start"
                                    pl="12px"
                                  >
                                    {findings.map((finding: any) => {
                                      const findingMeta = [
                                        finding?.page != null ? `page ${String(finding.page)}` : '',
                                        finding?.confidence != null ? `confidence ${String(finding.confidence)}` : '',
                                        String(finding?.legibility || '').trim()
                                          ? `legibility ${String(finding.legibility)}`
                                          : '',
                                      ]
                                        .filter(Boolean)
                                        .join('  ');

                                      return (
                                        <React.Fragment
                                          key={String(finding?.id || finding?.finding_seqno || finding?.summary)}
                                        >
                                          <Text fontSize="sm" opacity={0.7} noOfLines={1}>
                                            {displayVisualFindingLabel(finding?.finding_type)}
                                          </Text>
                                          <Box>
                                            <Text fontSize="sm" noOfLines={2}>
                                              {String(finding?.summary || '')}
                                            </Text>
                                            {findingMeta && (
                                              <Text fontSize="xs" opacity={0.65} noOfLines={1} mt="1px">
                                                {findingMeta}
                                              </Text>
                                            )}
                                          </Box>
                                        </React.Fragment>
                                      );
                                    })}
                                  </Box>
                                </Box>
                              )}
                            </Box>
                          </AccordionPanel>
                        </AccordionItem>
                      );
                    }),
                  )
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
                              </Flex>

                              {types.length === 0 ? (
                                <Text fontSize="sm" opacity={0.7}>
                                  No supporting document types mapped to this upgrade type.
                                </Text>
                              ) : (
                                <Box pl="12px">
                                  {types.map((typeRow: any) => (
                                    <Text
                                      key={String(typeRow?.supporting_document_type_id || typeRow?.type_key || 'type')}
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

                {classifierDisplayFields.length > 0 && (
                  <AccordionItem borderTopWidth="1px" borderColor="gray.200">
                    <h2>
                      <AccordionButton px="0" py="6px" _hover={{ bg: 'transparent' }}>
                        <Box flex="1" textAlign="left">
                          <Text size="sm" fontWeight="bold">
                            Product Codes
                          </Text>
                        </Box>
                        <AccordionIcon />
                      </AccordionButton>
                    </h2>
                    <AccordionPanel px="0" pt="8px">
                      <Box display="grid" gridTemplateColumns="1fr 1fr" columnGap="8px" rowGap="0">
                        {classifierDisplayFields.map((row: any) => {
                          const highlightKey = `classifier_${row.id}`;
                          const confidence =
                            row.confidence != null ? `confidence ${Number(row.confidence).toFixed(2)}` : '';
                          const clickable = row.page != null;
                          const issue = revisionIssueForLocatedField(row);
                          return (
                            <Box key={row.id} minW={0} gridColumn={issue ? '1 / -1' : undefined}>
                              <FieldRow
                                label={displayLocatedFieldLabel(row)}
                                labelHint={locatedFieldKeyHint(row)}
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
                                        setRightPanelMode('document');
                                      }
                                    : undefined
                                }
                              />
                              {issue ? (
                                <ContractorInlineRevisionIssueCard
                                  issue={issue}
                                  workspace={revisionWorkspace}
                                  compactHeading
                                  attention={revisionAttentionIssueIds.includes(issue.id)}
                                />
                              ) : null}
                            </Box>
                          );
                        })}
                      </Box>
                    </AccordionPanel>
                  </AccordionItem>
                )}

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

                {hervProduct && (
                  <ProductMatchAccordion
                    title="HERV ENERGY STAR product-list match"
                    rows={[
                      ['Brand', hervProduct.brand],
                      ['Model number', hervProduct.model_number],
                      ['Model type', hervProduct.model_type],
                      ['SRE at 0 C', hervProduct.sensible_heat_recovery_efficiency_sre_at_0c],
                      ['SRE at -25 C', hervProduct.sensible_heat_recovery_efficiency_sre_at_minus_25c],
                      ['Associated net supply airflow at 0 C CFM', hervProduct.associated_net_supply_airflow_at_0c_cfm],
                      [
                        'Associated net supply airflow at -25 C CFM',
                        hervProduct.associated_net_supply_airflow_at_minus_25c_cfm,
                      ],
                      ['Associated power consumption at 0 C W', hervProduct.associated_power_consumption_at_0c_w],
                      [
                        'Associated power consumption at -25 C W',
                        hervProduct.associated_power_consumption_at_minus_25c_w,
                      ],
                      ['Max rated airflow at 0 C CFM', hervProduct.max_rated_airflow_at_0c_cfm],
                      ['Power consumption at 0 C W', hervProduct.power_consumption_at_0c_w],
                      ['Eligibility notes', hervProduct.eligibility_notes],
                    ]}
                  />
                )}

                {ventFanProduct && (
                  <ProductMatchAccordion
                    title="ENERGY STAR fan product-list match"
                    rows={[
                      ['Brand', ventFanProduct.brand],
                      ['Model number', ventFanProduct.model_number],
                      ['Product model name', ventFanProduct.product_model_name],
                      ['Fan type', ventFanProduct.fan_type],
                      ['Airflow 1 CFM', ventFanProduct.airflow_1_cfm],
                      ['Efficacy 1 CFM/Watt', ventFanProduct.efficacy_1_cfm_watt],
                      ['Sound level sones', ventFanProduct.sound_level_sones],
                      [
                        'Bathroom/utility airflow at 0.25 in. w.g.',
                        ventFanProduct.bathroom_utility_airflow_at_0_25_in_wg,
                      ],
                      ['Markets', ventFanProduct.markets],
                      ['ENERGY STAR Unique ID', ventFanProduct.energy_star_unique_id],
                      ['CB model identifier', ventFanProduct.cb_model_identifier],
                      ['Most Efficient criteria', ventFanProduct.meets_most_efficient_criteria],
                    ]}
                  />
                )}

                {unmatchedRevisionIssues.filter((issue) => ['pending_admin_review', 'open'].includes(issue.status))
                  .length > 0 && (
                  <AccordionItem borderTopWidth="1px" borderColor="gray.200">
                    <h2>
                      <AccordionButton px="0" py="6px" _hover={{ bg: 'transparent' }}>
                        <Box flex="1" textAlign="left">
                          <Text size="sm" fontWeight="bold">
                            Other outstanding requested changes
                          </Text>
                        </Box>
                        <AccordionIcon />
                      </AccordionButton>
                    </h2>
                    <AccordionPanel px="0" pt="8px">
                      {unmatchedRevisionIssues
                        .filter((issue) => ['pending_admin_review', 'open'].includes(issue.status))
                        .map((issue) => (
                          <ContractorInlineRevisionIssueCard
                            key={issue.id}
                            issue={issue}
                            workspace={revisionWorkspace}
                            attention={revisionAttentionIssueIds.includes(issue.id)}
                          />
                        ))}
                    </AccordionPanel>
                  </AccordionItem>
                )}

                {unmatchedRevisionIssues.filter((issue) => !['pending_admin_review', 'open'].includes(issue.status))
                  .length > 0 && (
                  <AccordionItem borderTopWidth="1px" borderColor="gray.200">
                    <h2>
                      <AccordionButton px="0" py="6px" _hover={{ bg: 'transparent' }}>
                        <Box flex="1" textAlign="left">
                          <Text size="sm" fontWeight="bold">
                            Other resolved requested changes
                          </Text>
                        </Box>
                        <AccordionIcon />
                      </AccordionButton>
                    </h2>
                    <AccordionPanel px="0" pt="8px">
                      {unmatchedRevisionIssues
                        .filter((issue) => !['pending_admin_review', 'open'].includes(issue.status))
                        .map((issue) => (
                          <ContractorInlineRevisionIssueCard
                            key={issue.id}
                            issue={issue}
                            workspace={revisionWorkspace}
                          />
                        ))}
                    </AccordionPanel>
                  </AccordionItem>
                )}
              </Accordion>
            </Box>

            {rightPanelMode === 'document' ? (
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

                  {pdfUrlError && !viewerUrl ? (
                    <Text color="red.700">PDF URL error: {pdfUrlError}</Text>
                  ) : !viewerUrl ? (
                    <Flex align="center" justify="center" minH="300px">
                      <Spinner />
                    </Flex>
                  ) : viewerIsImage ? (
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
                        style={{ position: 'absolute', left: 0, top: 0, zIndex: 10, pointerEvents: 'none' }}
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
                  ) : (
                    <Document
                      key={viewerUrl}
                      file={viewerUrl}
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
                          width={overlayWidthPx}
                          height={overlayHeightPx}
                          style={{ position: 'absolute', left: 0, top: 0, zIndex: 10, pointerEvents: 'none' }}
                        >
                          {shouldShowActivePolygon && (
                            <polygon points={svgPolygonPoints} fill="rgba(255,0,0,0.20)" stroke="red" strokeWidth={2} />
                          )}
                        </svg>

                        <Box style={{ position: 'absolute', top: 0, left: 0 }}>
                          <Page
                            key={`p${activePageNumber}-w${renderWidthPx}-r${rotate}`}
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
                    active file {viewerFilename} | active page {activePageNumber} / {numPages || '-'} | unit{' '}
                    {activePageMeta?.unit ?? '-'}
                  </Text>
                </Box>
              </Box>
            ) : null}
          </Box>
        </Box>
      </Container>

      <Box
        id="contractor-admin-chat-dialog"
        role="dialog"
        aria-modal="false"
        aria-label="Chat with Admin"
        display={chatPanelOpen ? 'flex' : 'none'}
        position="fixed"
        right={{ base: '12px', md: '24px' }}
        bottom={{ base: '76px', md: '88px' }}
        zIndex={1500}
        w={{ base: 'calc(100vw - 24px)', md: '430px' }}
        maxW="430px"
        maxH="calc(100vh - 112px)"
        flexDirection="column"
        bg="white"
        borderWidth="1px"
        borderColor="gray.200"
        borderRadius="xl"
        boxShadow="2xl"
        overflow="hidden"
      >
        <Flex align="center" justify="space-between" px={4} py={3} borderBottomWidth="1px" borderColor="gray.200">
          <Text fontWeight="bold" color="blue.800">
            Chat with Admin
          </Text>
          <CloseButton aria-label="Close Chat with Admin" onClick={() => setChatPanelOpen(false)} />
        </Flex>
        <Box p={4} overflowY="auto">
          <ContractorConversationPanel
            invoiceId={currentInvoiceId}
            messageListMaxHeight="280px"
            showConversationHeading={false}
            showGuidance={false}
            inlineComposerSend
            active={chatPanelOpen}
            onUnreadCountChange={setChatUnreadCount}
          />
        </Box>
      </Box>

      <Box position="fixed" right={{ base: '12px', md: '24px' }} bottom={{ base: '12px', md: '24px' }} zIndex={1600}>
        <Tooltip label="View admin requested changes and send messages about this invoice." hasArrow shouldWrapChildren>
          <Button
            size="md"
            bg="theme.blueGradient"
            color="white"
            borderRadius="md"
            boxShadow={currentInvoiceId ? '0 10px 24px rgba(5, 66, 119, 0.28)' : 'none'}
            _hover={{ bg: 'theme.blueAltGradient' }}
            _disabled={{ opacity: 0.5, cursor: 'not-allowed' }}
            isDisabled={!currentInvoiceId}
            aria-label={
              chatUnreadCount > 0
                ? `Chat with Admin, ${chatUnreadCount} unread ${chatUnreadCount === 1 ? 'message' : 'messages'}`
                : 'Chat with Admin'
            }
            aria-expanded={chatPanelOpen}
            aria-controls="contractor-admin-chat-dialog"
            onClick={() => {
              if (!currentInvoiceId) return;
              setChatPanelOpen((open) => !open);
            }}
          >
            Chat with Admin
          </Button>
        </Tooltip>
        {chatUnreadCount > 0 ? (
          <Flex
            aria-hidden="true"
            position="absolute"
            top="-8px"
            right="-8px"
            w="22px"
            h="22px"
            align="center"
            justify="center"
            borderRadius="full"
            borderWidth="2px"
            borderColor="white"
            bg="red.500"
            color="white"
            fontSize="xs"
            fontWeight="black"
            lineHeight="1"
            pointerEvents="none"
            sx={{
              '@keyframes contractorChatUnreadPulse': {
                '0%, 100%': { transform: 'scale(1)', boxShadow: '0 0 0 0 rgba(229, 62, 62, 0.5)' },
                '50%': { transform: 'scale(1.14)', boxShadow: '0 0 0 7px rgba(229, 62, 62, 0)' },
              },
              animation: 'contractorChatUnreadPulse 1.6s ease-in-out infinite',
              '@media (prefers-reduced-motion: reduce)': { animation: 'none' },
            }}
          >
            !
          </Flex>
        ) : null}
      </Box>

      <Modal isOpen={isSubmitWarningOpen} onClose={onSubmitWarningClose} size="2xl" isCentered>
        <ModalOverlay />
        <ModalContent>
          <ModalHeader>
            {blockingRulechecks.length > 0 ? 'Submission blocked by failed checks' : 'Submit with outstanding checks?'}
          </ModalHeader>
          <ModalCloseButton />
          <ModalBody>
            <Flex direction="column" gap={4}>
              <Text fontSize="sm">
                {blockingRulechecks.length > 0
                  ? 'This invoice has one or more failed checks configured to block submission. Correct those items or provide the required supporting information, then rerun the review before submitting.'
                  : 'This invoice has contractor-visible warnings or errors. You can submit it to admin review, but admins may ask for corrections or supporting details. If an item is explainable, you can also use Messages & Requested Changes before submitting.'}
              </Text>
              <Flex gap={3} flexWrap="wrap">
                <Button variant="outline" onClick={onSubmitWarningClose}>
                  Keep reviewing
                </Button>
                {blockingRulechecks.length === 0 && (
                  <Button colorScheme="orange" onClick={submitToAdminAfterReview} isLoading={submitLoading}>
                    Submit Anyway
                  </Button>
                )}
              </Flex>

              <Box
                borderWidth="1px"
                borderRadius="md"
                p={4}
                bg={blockingRulechecks.length > 0 ? 'red.50' : 'orange.50'}
                borderColor={blockingRulechecks.length > 0 ? 'red.100' : 'orange.100'}
              >
                <Text fontSize="sm" fontWeight="bold" mb={3}>
                  Outstanding checks
                </Text>
                <Flex direction="column" gap={3}>
                  {contractorActionableRulechecks.slice(0, 6).map((row: any) => {
                    const name = String(row.contractor_display_name || row.rule_key || 'Invoice review check');

                    return (
                      <Box key={row.id ?? row.rule_key} bg="white" borderRadius="md" p={3}>
                        <Flex align="center" gap={2}>
                          <Text fontSize="sm" fontWeight="semibold">
                            {name}
                          </Text>
                        </Flex>
                      </Box>
                    );
                  })}
                </Flex>
                {contractorActionableRulechecks.length > 6 ? (
                  <Text fontSize="xs" mt={3} opacity={0.75}>
                    Plus {contractorActionableRulechecks.length - 6} more outstanding check(s) on this invoice.
                  </Text>
                ) : null}
              </Box>
            </Flex>
          </ModalBody>
        </ModalContent>
      </Modal>

      <Modal
        isOpen={isWithdrawOpen}
        onClose={withdrawalLoading ? () => undefined : onWithdrawClose}
        closeOnEsc={!withdrawalLoading}
        closeOnOverlayClick={!withdrawalLoading}
        isCentered
      >
        <ModalOverlay />
        <ModalContent>
          <ModalHeader>Withdraw this invoice?</ModalHeader>
          <ModalCloseButton isDisabled={withdrawalLoading} />
          <ModalBody pb={6}>
            <Flex direction="column" gap={5}>
              <Text fontSize="sm">
                This permanently withdraws the invoice from the program review process. Any unsaved contractor responses
                will not be saved, and the invoice cannot be submitted afterward.
              </Text>
              <Flex gap={3} flexWrap="wrap">
                <Button variant="outline" isDisabled={withdrawalLoading} onClick={onWithdrawClose}>
                  Keep invoice
                </Button>
                <Button colorScheme="red" isLoading={withdrawalLoading} onClick={() => void withdrawInvoice()}>
                  Withdraw invoice
                </Button>
              </Flex>
            </Flex>
          </ModalBody>
        </ModalContent>
      </Modal>
    </Flex>
  );
}
