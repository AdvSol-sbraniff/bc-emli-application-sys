// /app/frontend/components/domains/invoice-versions/index.tsx
import { fmtDate, fmtMoney, fmtText } from './display';
import {
  InvoiceReviewAuxiliaryPanel,
  INVOICE_REVIEW_PANEL_GAP,
  InvoiceReviewLayout,
  InvoiceReviewMainPanel,
  InvoiceReviewRightRegion,
  MIN_DOCUMENT_PANEL_WIDTH,
} from './invoice-review-layout';
import { useInvoiceReviewLayout } from './use-invoice-review-layout';

import {
  Box,
  Text,
  Flex,
  Container,
  Accordion,
  AccordionItem,
  Badge,
  Button,
  Checkbox,
  Drawer,
  DrawerBody,
  DrawerCloseButton,
  DrawerContent,
  DrawerHeader,
  DrawerOverlay,
  AccordionButton,
  AccordionPanel,
  AccordionIcon,
  IconButton,
  Menu,
  MenuButton,
  MenuItem,
  MenuList,
  Modal,
  ModalBody,
  ModalCloseButton,
  ModalContent,
  ModalHeader,
  ModalOverlay,
  Tab,
  TabList,
  TabPanel,
  TabPanels,
  Tabs,
  Switch,
  Tooltip,
  useToast,
} from '@chakra-ui/react';
import { ThinBlueTitleBar } from '../../shared/base/thin-blue-title-bar';
import { formatClaimsReferenceNumber } from '../../../utils/format-claims-reference-number';
import {
  getInvoiceUpgradeTypeMeta,
  INVOICE_UPGRADE_TYPE_FILTER_ORDER,
  InvoiceUpgradeTypeTile,
} from '../../shared/claims/invoice-upgrade-type-visual';
import { invoiceStatusCopy } from '../../shared/claims/invoice-status-copy';
import {
  AdminConversationPanel,
  AdminInternalNotesPanel,
} from '../../shared/claims/admin-invoice-communication-panels';
import { ComplianceSpectrum } from '../../shared/claims/compliance-spectrum';
import { normalizeAdminPdfViewerUxMode } from '../../shared/claims/admin-pdf-viewer-ux';
import {
  PossibleSupportingDocumentsButton,
  PossibleSupportingDocumentsModal,
} from '../../shared/claims/possible-supporting-documents';
import {
  adminRevisionIssueListStatus,
  AdminRevisionDecisionMode,
  AdminRevisionIssueEditor,
  AdminRevisionSummary,
  AdminRevisionListStatus,
  AdminRevisionSourceAnchor,
  AdminRevisionWorkspace,
  diFieldRevisionIdentityKey,
  invoiceFieldRevisionIdentityKey,
  revisionSourceIdentityKey,
  rulecheckRevisionIdentityKey,
  supportingFieldRevisionIdentityKey,
  useAdminInlineRevisionWorkspace,
} from '../../shared/claims/admin-inline-revision-issues';
import { RevisionIssue, RevisionTrackerData } from '../../shared/claims/revision-tracker';
import {
  ArrowClockwise,
  ArrowSquareOut,
  CaretDown,
  CaretLeft,
  CaretRight,
  CheckCircle,
  CornersOut,
  FrameCorners,
  Info,
  MagnifyingGlassMinus,
  MagnifyingGlassPlus,
  NotePencil,
  PaperPlaneTilt,
  PlusCircle,
  XCircle,
} from '@phosphor-icons/react';

// ============================================================
// SECTION 00 - FILE OVERVIEW
// PURPOSE: Invoice read screen with left fields + PDF viewer + DI polygon highlight
// ============================================================

import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import ReactMarkdown from 'react-markdown';
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
  labelHint?: string;
  value: any;
  hint?: string;
  active?: boolean;
  disabled?: boolean;
  onClick?: () => void;
  inline?: boolean;
  textFontSize?: string | number;
  revisionChecked?: boolean;
  revisionStatus?: AdminRevisionListStatus;
  revisionIssue?: RevisionIssue;
  onOpenRevision?: () => void;
  onSelectRevisionAction?: (mode: AdminRevisionDecisionMode) => void;
  onAddToRevision?: () => void;
  revisionAddDisabledReason?: string;
};

type ProductMatchDetail = {
  key: string;
  title: string;
  appliesTo: (upgradeTypeKey: string) => boolean;
  rows: Array<[string, unknown]>;
};

const ProductMatchModal = ({ match, onClose }: { match: ProductMatchDetail | null; onClose: () => void }) => (
  <Modal isOpen={match != null} onClose={onClose} size="2xl" isCentered>
    <ModalOverlay bg="rgba(15, 23, 42, 0.34)" backdropFilter="blur(8px)" />
    <ModalContent
      mx={4}
      borderRadius="xl"
      boxShadow="0 28px 90px rgba(15, 23, 42, 0.28)"
      maxH="calc(100vh - 48px)"
      overflowY="auto"
    >
      <ModalHeader>{match?.title}</ModalHeader>
      <ModalCloseButton />
      <ModalBody pb={6} fontSize="sm">
        <Box display="grid" gridTemplateColumns="1fr 1fr" columnGap="8px" rowGap="0">
          {(match?.rows || [])
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
                <Text fontSize="sm" color="#2D2D2D" flexShrink={0}>
                  {label}
                </Text>
                <Text fontSize="sm" noOfLines={2} textAlign="right">
                  {fmtText(value)}
                </Text>
              </Box>
            ))}
        </Box>
        <Flex justify="flex-end" mt={6}>
          <Button variant="primary" onClick={onClose}>
            Close
          </Button>
        </Flex>
      </ModalBody>
    </ModalContent>
  </Modal>
);

type RevisionAddIconButtonProps = {
  label: string;
  included?: boolean;
  onAdd?: () => void;
  disabledReason?: string;
};

const RevisionAddIconButton = ({ label, included = false, onAdd, disabledReason }: RevisionAddIconButtonProps) => {
  if (!included && !onAdd && !disabledReason) return null;

  const actionLabel = included
    ? `Open the existing revision issue for ${label}`
    : disabledReason || `Add ${label} to revision`;
  const disabled = !included && (!!disabledReason || !onAdd);

  return (
    <Box as="span" display="inline-flex" title={actionLabel}>
      <IconButton
        aria-label={actionLabel}
        aria-pressed={included}
        icon={<PlusCircle size={19} weight={included ? 'fill' : 'bold'} />}
        size="xs"
        minW="26px"
        h="26px"
        borderRadius="full"
        colorScheme={included ? 'green' : 'blue'}
        variant={included ? 'outline' : 'solid'}
        color={included ? 'green.600' : 'theme.blue'}
        bg={included ? 'green.50' : 'white'}
        boxShadow={included ? 'none' : '0 2px 6px rgba(37, 99, 235, 0.35)'}
        isDisabled={disabled}
        opacity={1}
        _hover={
          disabled
            ? undefined
            : included
              ? { bg: 'green.100', transform: 'translateY(-1px)' }
              : { bg: 'theme.blueLight', transform: 'translateY(-1px)' }
        }
        _disabled={{
          opacity: 1,
          color: included ? 'green.600' : 'gray.500',
          bg: included ? 'green.50' : 'gray.100',
          cursor: 'not-allowed',
        }}
        onMouseDown={(event) => event.stopPropagation()}
        onClick={(event) => {
          event.stopPropagation();
          onAdd?.();
        }}
      />
    </Box>
  );
};

const RevisionStatusBadge = ({ status, onOpen }: { status?: AdminRevisionListStatus; onOpen?: () => void }) =>
  status ? (
    <Badge
      as={onOpen ? 'button' : 'span'}
      bg={status.badgeBackground}
      color={status.badgeColor}
      fontSize="9px"
      lineHeight="16px"
      px="5px"
      borderRadius="full"
      textTransform="none"
      whiteSpace="nowrap"
      flexShrink={0}
      cursor={onOpen ? 'pointer' : 'default'}
      _hover={{ bg: status.badgeBackground }}
      title={onOpen ? `Open ${status.label.toLowerCase()} in Revision Issues` : undefined}
      onMouseDown={onOpen ? (event) => event.stopPropagation() : undefined}
      onClick={
        onOpen
          ? (event) => {
              event.stopPropagation();
              onOpen();
            }
          : undefined
      }
    >
      Revision · {status.label}
    </Badge>
  ) : null;

const RevisionSourceActions = ({
  issue,
  onSelect,
}: {
  issue?: RevisionIssue;
  onSelect?: (mode: AdminRevisionDecisionMode) => void;
}) => {
  if (!issue?.can_close || !onSelect) return null;

  return (
    <Flex width="100%" gap="6px" mt="4px" wrap="wrap">
      <Button
        size="xs"
        h="24px"
        colorScheme="purple"
        variant="outline"
        fontWeight="600"
        onMouseDown={(event) => event.stopPropagation()}
        onClick={(event) => {
          event.stopPropagation();
          onSelect('close_issue');
        }}
      >
        Close issue
      </Button>
    </Flex>
  );
};

const FieldRow = ({
  label,
  labelHint,
  value,
  hint,
  active,
  disabled,
  onClick,
  inline,
  textFontSize = 'sm',
  revisionChecked,
  revisionStatus,
  revisionIssue,
  onOpenRevision,
  onSelectRevisionAction,
  onAddToRevision,
  revisionAddDisabledReason,
}: FieldRowProps) => {
  const valueText = String(value);
  const valueNode = (
    <Text
      fontSize={textFontSize}
      fontWeight={active ? 'semibold' : 'normal'}
      noOfLines={inline ? 1 : 2}
      textAlign={inline ? 'right' : undefined}
      cursor={hint ? 'help' : undefined}
    >
      {valueText}
    </Text>
  );

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
      flexWrap={revisionIssue ? 'wrap' : undefined}
      position="relative"
      pr={onAddToRevision || revisionChecked || revisionAddDisabledReason ? '38px' : '10px'}
    >
      {onAddToRevision || revisionChecked || revisionAddDisabledReason ? (
        <Box position="absolute" right="6px" top={inline ? '1px' : '6px'}>
          <RevisionAddIconButton
            label={label}
            included={!!revisionChecked}
            onAdd={onAddToRevision}
            disabledReason={revisionAddDisabledReason}
          />
        </Box>
      ) : null}
      <Flex align="center" gap="5px" minW={0} flexShrink={inline ? 1 : undefined} wrap="wrap">
        {labelHint ? (
          <Tooltip label={labelHint} hasArrow placement="top">
            <Text fontSize={textFontSize} opacity={0.7} minW={0} noOfLines={1} cursor="help">
              {label}
            </Text>
          </Tooltip>
        ) : (
          <Text fontSize={textFontSize} opacity={0.7} minW={0} noOfLines={1}>
            {label}
          </Text>
        )}
        <RevisionStatusBadge status={revisionStatus} onOpen={onOpenRevision} />
      </Flex>
      {hint ? (
        <Tooltip label={hint} hasArrow placement="top">
          {valueNode}
        </Tooltip>
      ) : (
        valueNode
      )}
      <RevisionSourceActions issue={revisionIssue} onSelect={onSelectRevisionAction} />
    </Box>
  );
};

const ruleDisplayTitle = (rulecheck: any) => {
  const contractorDisplayName = String(rulecheck.contractor_display_name ?? '').trim();
  if (contractorDisplayName) return contractorDisplayName;

  const ruleKey = String(rulecheck.rule_key ?? '').trim();
  if (ruleKey) return ruleKey;

  return 'advice';
};

const ruleSourceLabel = (rulecheck: any) => {
  const sourceEngine = String(rulecheck.source_engine ?? '').toLowerCase();
  if (sourceEngine === 'code') return 'code';
  if (sourceEngine === 'genai') return 'genai';
  return sourceEngine || '';
};

const ruleDefinitionLabel = (rulecheck: any) => {
  const sourceEngine = String(rulecheck?.source_engine ?? '').toLowerCase();
  return sourceEngine === 'code' ? 'Code description' : 'GenAI prompt';
};

const hasComplianceSpectrum = (rulecheck: any) => {
  if (String(rulecheck?.source_engine ?? '').toLowerCase() !== 'genai') return false;
  if (rulecheck?.compliance_score == null || rulecheck.compliance_score === '') return false;
  return Number.isFinite(Number(rulecheck.compliance_score));
};

const contractorVisibilityLabel = (value: unknown): string => {
  if (value === 'hidden') return 'Hidden / non-impacting';
  if (value === 'fail_only') return 'Visible for errors only';
  if (value === 'warn_and_fail') return 'Visible for warnings and errors';
  return fmtText(value);
};

const contractorBlockingPolicyLabel = (value: unknown): string =>
  value === 'block_on_fail' ? 'Blocks submission on error' : 'Does not block submission';

const adminWorkflowPolicyLabel = (value: unknown): string => {
  if (value === 'not_managed') return 'Not workflow-managed';
  if (value === 'fail_only') return 'Workflow-managed for errors only';
  if (value === 'warn_and_fail') return 'Workflow-managed for warnings and errors';
  if (value === 'all_results') return 'Workflow-managed for all results';
  return fmtText(value);
};

const ContractorAdviceMarkdown = ({ value }: { value?: unknown }) => {
  const text = String(value ?? '').trim();
  if (!text) {
    return (
      <Text fontSize="sm" opacity={0.7}>
        No contractor advice found for this invoice version.
      </Text>
    );
  }

  return (
    <Box
      fontSize="sm"
      bg="orange.50"
      borderWidth="1px"
      borderColor="orange.200"
      borderLeftWidth="5px"
      borderLeftColor="orange.400"
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
          border: '1px solid var(--chakra-colors-orange-100)',
          boxShadow: '0 1px 2px rgba(15, 23, 42, 0.05)',
        },
        'li:last-child': { marginBottom: 0 },
        em: { fontStyle: 'italic', color: 'var(--chakra-colors-gray-800)' },
        a: { color: 'var(--chakra-colors-orange-700)', cursor: 'help', textDecoration: 'none' },
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
              <Text as="span" color="orange.700" cursor="help">
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

const SourceQuoteMarkdown = ({ value }: { value?: unknown }) => {
  const text = String(value ?? '').trim();
  if (!text) return null;

  return (
    <Box
      fontSize="sm"
      sx={{
        p: { marginBottom: '0.25rem' },
        'p:last-child': { marginBottom: 0 },
        em: { fontStyle: 'italic' },
        strong: { color: 'var(--chakra-colors-orange-700)' },
      }}
    >
      <ReactMarkdown
        components={{
          p: ({ children }: any) => (
            <Text as="p" fontSize="sm" whiteSpace="pre-wrap">
              {children}
            </Text>
          ),
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
        }}
      >
        {text}
      </ReactMarkdown>
    </Box>
  );
};

const RuleDetailDrawerSection = ({ label, children }: { label: string; children: React.ReactNode }) => (
  <Box mb="18px">
    <Text fontSize="xs" fontWeight="bold" textTransform="uppercase" letterSpacing="0.06em" opacity={0.65} mb="6px">
      {label}
    </Text>
    {children}
  </Box>
);

const RuleDetailText = ({ value }: { value?: unknown }) => {
  const text = String(value ?? '').trim();
  if (!text) {
    return (
      <Text fontSize="sm" opacity={0.6}>
        Not provided.
      </Text>
    );
  }

  return (
    <Text fontSize="sm" whiteSpace="pre-wrap">
      {text}
    </Text>
  );
};

const displayLocatedFieldValue = (row: any): string => {
  if (row?.value_text != null && row.value_text !== '') return String(row.value_text);
  if (row?.value_json != null) return JSON.stringify(row.value_json);
  return '-';
};

const displayLocatedFieldLabel = (row: any): string =>
  String(row?.contractor_display_name || row?.field_key || 'Field').trim();

const locatedFieldKeyHint = (row: any): string => `Field key: ${String(row?.field_key || 'unknown')}`;

const displayVisualFindingLabel = (value: unknown): string => {
  const label = String(value || 'visual finding')
    .trim()
    .replace(/before_after/g, 'before/after')
    .replace(/_/g, ' ');
  return label ? `${label.charAt(0).toUpperCase()}${label.slice(1)}` : 'Visual finding';
};

const isClassifierEligibilityField = (row: any) =>
  String(row?.source_engine ?? '').toLowerCase() === 'classifier' &&
  String(row?.field_key ?? '').toLowerCase() === 'classifier.eligibility_code';

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

const ClassifiedUpgradeTypesModal = ({
  isOpen,
  onClose,
  rows,
  onFocus,
}: {
  isOpen: boolean;
  onClose: () => void;
  rows: any[];
  onFocus: (row: any) => void;
}) => (
  <Modal isOpen={isOpen} onClose={onClose} size="2xl" isCentered>
    <ModalOverlay bg="rgba(15, 23, 42, 0.34)" backdropFilter="blur(8px)" />
    <ModalContent
      mx={4}
      borderRadius="xl"
      boxShadow="0 28px 90px rgba(15, 23, 42, 0.28)"
      maxH="calc(100vh - 48px)"
      overflowY="auto"
    >
      <ModalHeader>Classified Upgrade Types</ModalHeader>
      <ModalCloseButton />
      <ModalBody pb={6} fontSize="md">
        {rows.length === 0 ? (
          <Text fontSize="md" opacity={0.7}>
            No upgrade types classified for this invoice.
          </Text>
        ) : (
          <Box display="flex" flexDirection="column" gap="8px">
            {rows.map((row: any) => {
              const meta = getInvoiceUpgradeTypeMeta(upgradeTypeKeyFor(row), row.upgrade_type_description);
              const explanation = String(row.classification_explanation || '').trim();
              const evidenceText = String(row.evidence_text || '').trim();
              const confidence = row.confidence != null ? `Confidence: ${Number(row.confidence).toFixed(0)}` : '';
              const clickable = row.page != null;

              return (
                <Box
                  key={row.id}
                  role={clickable ? 'button' : undefined}
                  tabIndex={clickable ? 0 : undefined}
                  cursor={clickable ? 'pointer' : 'default'}
                  px="12px"
                  py="9px"
                  borderWidth="1px"
                  borderColor="gray.200"
                  borderRadius="md"
                  _hover={clickable ? { bg: 'blue.50', borderColor: 'blue.200' } : undefined}
                  onClick={clickable ? () => onFocus(row) : undefined}
                  onKeyDown={
                    clickable
                      ? (event) => {
                          if (event.key !== 'Enter' && event.key !== ' ') return;
                          event.preventDefault();
                          onFocus(row);
                        }
                      : undefined
                  }
                >
                  <Flex align="center" gap="8px" wrap="wrap">
                    <Text fontSize="md" fontWeight="bold">
                      {meta.label}
                    </Text>
                    <InvoiceUpgradeTypeTile
                      upgradeTypeKey={upgradeTypeKeyFor(row)}
                      description={row.upgrade_type_description}
                      size={24}
                    />
                    {confidence ? (
                      <Badge colorScheme="blue" textTransform="none" fontSize="md">
                        {confidence}
                      </Badge>
                    ) : null}
                  </Flex>
                  {explanation ? (
                    <Text fontSize="md" mt="5px">
                      <Text as="span" fontWeight="bold">
                        Why classified:{' '}
                      </Text>
                      {explanation}
                    </Text>
                  ) : null}
                  {evidenceText ? (
                    <Text fontSize="md" mt="3px">
                      <Text as="span" fontWeight="bold">
                        Evidence:{' '}
                      </Text>
                      {evidenceText}
                    </Text>
                  ) : null}
                </Box>
              );
            })}
          </Box>
        )}
        <Flex justify="flex-end" mt={6}>
          <Button variant="primary" onClick={onClose}>
            Close
          </Button>
        </Flex>
      </ModalBody>
    </ModalContent>
  </Modal>
);

const LineItemsModal = ({
  isOpen,
  onClose,
  rows,
  error,
  activeHighlightKey,
  onFocus,
}: {
  isOpen: boolean;
  onClose: () => void;
  rows: any[];
  error?: string | null;
  activeHighlightKey: string | null;
  onFocus: (row: any, highlightKey: string) => void;
}) => (
  <Modal isOpen={isOpen} onClose={onClose} size="4xl" isCentered>
    <ModalOverlay bg="rgba(15, 23, 42, 0.34)" backdropFilter="blur(8px)" />
    <ModalContent
      mx={4}
      borderRadius="xl"
      boxShadow="0 28px 90px rgba(15, 23, 42, 0.28)"
      maxH="calc(100vh - 48px)"
      overflowY="auto"
    >
      <ModalHeader>Invoice Line Items</ModalHeader>
      <ModalCloseButton />
      <ModalBody pb={6}>
        {error ? (
          <Text fontSize="sm" color="red.500">
            {error}
          </Text>
        ) : rows.length === 0 ? (
          <Text fontSize="sm" opacity={0.7}>
            No line items found.
          </Text>
        ) : (
          <Box overflowX="auto">
            <Box minW="560px" display="flex" flexDirection="column" gap="2px">
              <Box display="grid" gridTemplateColumns="minmax(220px, 1fr) 72px 96px 96px" gap="8px" px="10px">
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
              {rows.map((row: any) => {
                const seq = row.lineitem_seqno ?? row.seqno ?? '-';
                const lineitemKey = row.id ?? seq;
                const highlightKey = `lineitem_${lineitemKey}_desc`;
                const clickable = row.ocr_description_page != null && row.ocr_description_polygon != null;
                const active = activeHighlightKey === highlightKey;

                return (
                  <Box
                    key={String(lineitemKey)}
                    borderWidth="1px"
                    borderColor={active ? 'blue.400' : 'transparent'}
                    borderRadius="md"
                    bg={active ? 'blue.50' : 'transparent'}
                    px="10px"
                    py="5px"
                    role={clickable ? 'button' : undefined}
                    tabIndex={clickable ? 0 : undefined}
                    cursor={clickable ? 'pointer' : 'default'}
                    _hover={
                      clickable
                        ? {
                            bg: active ? 'blue.50' : 'gray.50',
                            borderColor: active ? 'blue.400' : 'gray.200',
                          }
                        : undefined
                    }
                    onClick={clickable ? () => onFocus(row, highlightKey) : undefined}
                    onKeyDown={
                      clickable
                        ? (event) => {
                            if (event.key !== 'Enter' && event.key !== ' ') return;
                            event.preventDefault();
                            onFocus(row, highlightKey);
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
                      <Text fontSize="sm" fontWeight={active ? 'semibold' : 'normal'} noOfLines={1}>
                        {String(row.ocr_description ?? '-')}
                      </Text>
                      <Text fontSize="sm" textAlign="right" noOfLines={1}>
                        {row.ocr_quantity != null ? String(row.ocr_quantity) : '-'}
                      </Text>
                      <Text fontSize="sm" textAlign="right" noOfLines={1}>
                        {row.ocr_unit_price != null ? fmtMoney(row.ocr_unit_price) : '-'}
                      </Text>
                      <Text fontSize="sm" textAlign="right" noOfLines={1}>
                        {row.ocr_amount != null ? fmtMoney(row.ocr_amount) : '-'}
                      </Text>
                    </Box>
                  </Box>
                );
              })}
            </Box>
          </Box>
        )}
        <Flex justify="flex-end" mt={6}>
          <Button variant="primary" onClick={onClose}>
            Close
          </Button>
        </Flex>
      </ModalBody>
    </ModalContent>
  </Modal>
);

const upgradeTypeDescriptionFor = (row: any) => {
  const upgradeTypeKey = upgradeTypeKeyFor(row);
  return row?.upgrade_type_description || getInvoiceUpgradeTypeMeta(upgradeTypeKey).label;
};

// ============================================================
// SECTION 01.02 - UI COMPONENTS (STATUS DOT)
// PURPOSE: Color and written status indicators for rule results
// ============================================================

type RuleResult = 'pass' | 'info' | 'warn' | 'fail' | null | undefined;
type RuleResultFilter = 'fail' | 'warn' | 'info' | 'pass';

const RULE_RESULT_FILTER_OPTIONS: Array<{ result: RuleResultFilter; label: string }> = [
  { result: 'fail', label: 'red' },
  { result: 'warn', label: 'yellow' },
  { result: 'info', label: 'blue' },
  { result: 'pass', label: 'green' },
];

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
  if (normalized === 'pass') return 'pass: do not show in advice; admin can skim or ignore.';
  if (normalized === 'info') return 'info: may show in advice as helpful context, not a requested fix.';
  if (normalized === 'warn') return 'warn: always show, framed for contractor pre-check or admin attention.';
  if (normalized === 'fail') return 'fail: always show, framed as a correction needed.';
  return 'unknown: advice result was not recognized.';
};

const resultLabel = (result: unknown): string => {
  const normalized = normalizeResult(result);
  if (normalized === 'pass') return 'Pass';
  if (normalized === 'info') return 'Info';
  if (normalized === 'warn') return 'Warning';
  if (normalized === 'fail') return 'Fail';
  return 'Unknown';
};

const StatusDot = ({ result }: { result: unknown }) => {
  const bg = resultDotColor(result);

  return (
    <Tooltip label={resultTooltip(result)} hasArrow placement="top">
      <Box as="span" w="10px" h="10px" borderRadius="full" display="inline-block" bg={bg} flexShrink={0} />
    </Tooltip>
  );
};

const RuleResultIndicator = ({ result }: { result: unknown }) => (
  <Flex align="center" gap="5px" minW={0}>
    <StatusDot result={result} />
    <Text as="span" fontSize="xs" fontWeight="semibold" color="gray.700" whiteSpace="nowrap">
      {resultLabel(result)}
    </Text>
  </Flex>
);

const ruleMatchesResultFilter = (rulecheck: any, filters: RuleResultFilter[]) => {
  if (filters.length === 0) return true;
  const normalized = normalizeResult(rulecheck?.rule_result);
  return normalized != null && filters.includes(normalized);
};

type InvoiceStatusTransition = 'screen_in' | 'approve_pending' | 'mark_ineligible';

const invoiceStatusLabel = (status: unknown): string => invoiceStatusCopy(String(status ?? '')).label;

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
    label: 'Send to second level',
    validFrom: ['admin_review_inbox'],
    targetStatus: 'in_review',
    colorScheme: 'blue',
    tooltip:
      'First approval level. Regular admins use this after reviewing an invoice in admin_review_inbox. Moves status to in_review for second-level approval.',
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
  if (key === 'screen_in') return <PaperPlaneTilt size={18} weight="bold" />;
  if (key === 'approve_pending') return <CheckCircle size={18} weight="bold" />;
  return <XCircle size={18} weight="bold" />;
};

const PersonalInformationReviewFlag = ({ record }: { record: any }) => {
  const status = String(record?.personal_information_review_status || '').trim();
  if (!status || status === 'not_flagged') return null;

  const isHighRisk = status === 'high_risk';
  const isUnavailable = status === 'unable_to_assess';
  const label = isHighRisk
    ? 'High-risk personal information'
    : isUnavailable
      ? 'PI assessment unavailable'
      : 'PI review recommended';
  const typeLabel = String(record?.personal_information_type?.display_name || '').trim();
  const reason = String(record?.personal_information_review_reason || '').trim();
  const borderColor = isHighRisk ? 'red.300' : isUnavailable ? 'gray.300' : 'orange.300';
  const background = isHighRisk ? 'red.50' : isUnavailable ? 'gray.50' : 'orange.50';
  const colorScheme = isHighRisk ? 'red' : isUnavailable ? 'gray' : 'orange';

  return (
    <Box
      aria-label="Personal information review"
      borderWidth="1px"
      borderColor={borderColor}
      borderRadius="md"
      bg={background}
      px="12px"
      py="10px"
      mb="10px"
    >
      <Flex align="center" gap="8px" wrap="wrap">
        <Badge colorScheme={colorScheme}>{label}</Badge>
        {typeLabel && (
          <Text fontSize="sm" fontWeight="semibold">
            {typeLabel}
          </Text>
        )}
      </Flex>
      {reason && (
        <Text fontSize="sm" mt="5px">
          {reason}
        </Text>
      )}
    </Box>
  );
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
  const titleText = isVersionSnapshotRoute ? 'Invoice Version Snapshot' : '';

  // ============================================================
  // SECTION 05.01 - STATE
  // PURPOSE: invoiceIds + readData + pdf viewer state + highlight state
  // ============================================================

  const [bannerHidden, setBannerHidden] = useState<boolean>(false);
  const [adminChatPanelOpen, setAdminChatPanelOpen] = useState<boolean>(false);
  const [simpleRevisionSummaryVisible, setSimpleRevisionSummaryVisible] = useState<boolean>(true);
  const [possibleSupportingDocumentsOpen, setPossibleSupportingDocumentsOpen] = useState<boolean>(false);
  const [productMatchModal, setProductMatchModal] = useState<ProductMatchDetail | null>(null);
  const [classifiedUpgradeTypesOpen, setClassifiedUpgradeTypesOpen] = useState<boolean>(false);
  const [lineItemsOpen, setLineItemsOpen] = useState<boolean>(false);

  useEffect(() => {
    if (!adminChatPanelOpen) return;
    const closeOnEscape = (event: KeyboardEvent) => {
      if (event.key === 'Escape') setAdminChatPanelOpen(false);
    };
    window.addEventListener('keydown', closeOnEscape);
    return () => window.removeEventListener('keydown', closeOnEscape);
  }, [adminChatPanelOpen]);
  const {
    documentVisible,
    toggleDocument,
    showDocument,
    revisionPlacement,
    toggleRevisionPlacement,
    communicationPanel: auxiliaryPanel,
    toggleCommunicationPanel: toggleAuxiliaryPanel,
    closeCommunicationPanel,
    mountedCommunicationPanels: mountedAuxiliaryPanels,
    showRevisionWorkspace: exposeRevisionWorkspace,
    effectiveAuxiliaryPanel,
    mainPanelWidth,
    setMainPanelWidth,
    auxiliaryPanelWidth,
    setAuxiliaryPanelWidth,
  } = useInvoiceReviewLayout();

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
  const [ruleResultFilters, setRuleResultFilters] = useState<RuleResultFilter[]>([]);
  const [ruleDetailsDrawerRulecheck, setRuleDetailsDrawerRulecheck] = useState<any | null>(null);

  const toggleRuleResultFilter = (result: RuleResultFilter) => {
    setRuleResultFilters((current) =>
      current.includes(result) ? current.filter((item) => item !== result) : [...current, result],
    );
  };

  const ruleFilterLabel =
    ruleResultFilters.length === 0
      ? 'all'
      : RULE_RESULT_FILTER_OPTIONS.filter((option) => ruleResultFilters.includes(option.result))
          .map((option) => option.label)
          .join(', ');

  const ruleFilterMenu = (
    <Menu closeOnSelect={false} placement="bottom-end">
      <MenuButton
        as={Button}
        size="sm"
        minW="190px"
        variant="secondary"
        rightIcon={<CaretDown size={16} weight="bold" />}
        onClick={(event) => event.stopPropagation()}
      >
        Rule filter: {ruleFilterLabel}
      </MenuButton>
      <MenuList minW="190px" onClick={(event) => event.stopPropagation()}>
        <MenuItem onClick={() => setRuleResultFilters([])}>
          <Checkbox size="sm" isChecked={ruleResultFilters.length === 0} pointerEvents="none" mr="8px" />
          <Text fontSize="sm">all</Text>
        </MenuItem>
        {RULE_RESULT_FILTER_OPTIONS.map((option) => (
          <MenuItem key={option.result} onClick={() => toggleRuleResultFilter(option.result)}>
            <Checkbox size="sm" isChecked={ruleResultFilters.includes(option.result)} pointerEvents="none" mr="8px" />
            <StatusDot result={option.result} />
            <Text fontSize="sm" ml="8px">
              {option.label}
            </Text>
          </MenuItem>
        ))}
      </MenuList>
    </Menu>
  );

  // ============================================================
  // SECTION 05.04 - LINEITEMS STATE
  // PURPOSE: Store OCR lineitems (from /read response)
  // ============================================================
  const [lineitems, setLineitems] = useState<any[]>([]);
  const [lineitemsError] = useState<string | null>(null);
  const [statusActionLoading, setStatusActionLoading] = useState<InvoiceStatusTransition | null>(null);
  const [statusActionError, setStatusActionError] = useState<string | null>(null);

  const handleRevisionTrackerChange = useCallback((next: RevisionTrackerData) => {
    setReadData((current: any) =>
      current
        ? {
            ...current,
            invoice_status: next.invoice_status ?? current.invoice_status,
          }
        : current,
    );
  }, []);

  const revisionInvoiceId = String(readData?.invoice_id || invoiceId || '').trim();
  const revisionInvoiceStatus = String(readData?.invoice_status || '').trim();
  const adminPdfViewerUxMode = normalizeAdminPdfViewerUxMode(readData?.admin_pdf_viewer_ux_mode);
  const usesEnterpriseRevisionWorkspace = adminPdfViewerUxMode === 'enterprise';
  const canLoadRevisionWorkspace = canRunWorkflowActions && !!revisionInvoiceId;
  const revisionWorkspace = useAdminInlineRevisionWorkspace({
    invoiceId: revisionInvoiceId,
    enabled: canLoadRevisionWorkspace,
    onTrackerChange: handleRevisionTrackerChange,
  });
  const focusRevisionIssue = (issueId: string, mode?: AdminRevisionDecisionMode) => {
    if (usesEnterpriseRevisionWorkspace) exposeRevisionWorkspace();
    revisionWorkspace.focusIssue(issueId, mode);
  };
  const revisionTrackerData = revisionWorkspace.data;
  const hasRevisionHistory =
    !!revisionTrackerData && (revisionTrackerData.rounds.length > 0 || revisionTrackerData.issues.length > 0);
  const showRevisionWorkspace =
    canLoadRevisionWorkspace &&
    (hasRevisionHistory || ['admin_review_inbox', 'contractor_revision_inbox'].includes(revisionInvoiceStatus));
  const revisionIssueByIdentity = useMemo(() => {
    const index = new Map<string, RevisionIssue>();
    revisionWorkspace.issues.forEach((issue) => {
      const key = revisionSourceIdentityKey(issue.source_identity);
      if (key) index.set(key, issue);
    });
    return index;
  }, [revisionWorkspace.issues]);
  const canAddRevisionIssue = !!revisionTrackerData?.capabilities?.can_add_issue;
  const revisionAddDisabledReason = !revisionTrackerData
    ? 'Revision Issues are still loading.'
    : !canAddRevisionIssue
      ? 'Revision issues can be added while the invoice is in the first-level admin inbox.'
      : undefined;
  const showAdminFieldRevisionPlus = readData?.show_admin_field_revision_plus === true;

  const revisionIssueForRulecheck = (row: any) => revisionIssueByIdentity.get(rulecheckRevisionIdentityKey(row));
  const revisionIssueForInvoiceField = (row: any) => revisionIssueByIdentity.get(invoiceFieldRevisionIdentityKey(row));
  const revisionIssueForDiField = (fieldKey: string) =>
    revisionIssueByIdentity.get(diFieldRevisionIdentityKey(fieldKey));
  const revisionStatusForIssue = (issue?: RevisionIssue) =>
    usesEnterpriseRevisionWorkspace && issue ? adminRevisionIssueListStatus(issue, revisionWorkspace) : undefined;
  const revisionSourceActionProps = (issue?: RevisionIssue) => ({
    revisionIssue: issue,
    onOpenRevision: issue ? () => focusRevisionIssue(issue.id) : undefined,
    onSelectRevisionAction:
      issue && usesEnterpriseRevisionWorkspace
        ? (mode: AdminRevisionDecisionMode) => focusRevisionIssue(issue.id, mode)
        : undefined,
  });

  const addToRevision = async (entryType: string, sourceAttribute: string, sourceValue: string) => {
    const invoiceRecordId = String(readData?.invoice_id || invoiceId || '').trim();
    if (!canRunWorkflowActions || !invoiceRecordId || !sourceValue) return;
    const existingIssueIds = new Set(revisionWorkspace.issues.map((issue) => issue.id));

    try {
      const response = await fetch(
        `/api/claims/admin/invoices/${encodeURIComponent(invoiceRecordId)}/revision_issues`,
        {
          method: 'POST',
          credentials: 'include',
          headers: { Accept: 'application/json', 'Content-Type': 'application/json' },
          body: JSON.stringify({ issue_type: entryType, [sourceAttribute]: sourceValue }),
        },
      );
      const json = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(json?.error || `Could not add revision item (${response.status}).`);
      const nextData = json as RevisionTrackerData;
      const addedIssue =
        nextData.issues.find(
          (issue) => String(issue.source_reference?.[sourceAttribute] || '') === String(sourceValue),
        ) || nextData.issues.find((issue) => !existingIssueIds.has(issue.id));
      revisionWorkspace.adoptData(nextData);
      if (addedIssue) focusRevisionIssue(addedIssue.id);
      toast({ title: 'Revision issue added', status: 'success', duration: 2500 });
    } catch (reason: any) {
      toast({
        title: 'Could not add revision item',
        description: reason?.message || 'Please try again.',
        status: 'error',
        duration: 5000,
      });
    }
  };

  const invoiceFieldRevisionProps = (row: any) => {
    const issue = revisionIssueForInvoiceField(row);
    if (!showAdminFieldRevisionPlus) {
      return {
        revisionChecked: undefined,
        revisionStatus: revisionStatusForIssue(issue),
        ...revisionSourceActionProps(issue),
        onAddToRevision: undefined,
        revisionAddDisabledReason: undefined,
      };
    }

    const sourceId = String(row?.id || '').trim();
    return {
      revisionChecked: undefined,
      revisionStatus: revisionStatusForIssue(issue),
      ...revisionSourceActionProps(issue),
      onAddToRevision:
        !issue && canRunWorkflowActions && canAddRevisionIssue && sourceId
          ? () => addToRevision('invoice_field', 'invoice_version_located_field_id', sourceId)
          : undefined,
      revisionAddDisabledReason: !issue && canRunWorkflowActions && sourceId ? revisionAddDisabledReason : undefined,
    };
  };

  const diFieldRevisionProps = (fieldKey: string) => {
    const issue = revisionIssueForDiField(fieldKey);
    if (!showAdminFieldRevisionPlus) {
      return {
        revisionChecked: undefined,
        revisionStatus: revisionStatusForIssue(issue),
        ...revisionSourceActionProps(issue),
        onAddToRevision: undefined,
        revisionAddDisabledReason: undefined,
      };
    }

    return {
      revisionChecked: undefined,
      revisionStatus: revisionStatusForIssue(issue),
      ...revisionSourceActionProps(issue),
      onAddToRevision:
        !issue && canRunWorkflowActions && canAddRevisionIssue
          ? () => addToRevision('di_field', 'di_field_key', fieldKey)
          : undefined,
      revisionAddDisabledReason: !issue && canRunWorkflowActions ? revisionAddDisabledReason : undefined,
    };
  };

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
              reference_number: read.reference_number ?? invoice?.reference_number ?? null,
              contractor_business_name: read.contractor_business_name ?? invoice?.contractor_business_name ?? null,
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
        setUpgradeTypeResults(Array.isArray(json?.detected_upgrade_types) ? json.detected_upgrade_types : []);

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
    if (!documentVisible) return;

    const el = pdfWrapRef.current;
    if (!el) return;

    const PDF_HORIZONTAL_GUTTER = 24;

    const measurePdfPane = () => {
      const bounds = el.getBoundingClientRect();
      if (bounds.width <= 0 || bounds.height <= 0) return;

      // Border-box dimensions stay stable when this pane gains or loses its
      // own scrollbars. clientWidth/clientHeight do not, and allowed the PDF
      // render to feed a progressively smaller size back into the layout.
      const w = Math.max(300, Math.floor(bounds.width - PDF_HORIZONTAL_GUTTER));
      const h = Math.max(300, Math.floor(bounds.height));
      setPageWidthPx((current) => (current === w ? current : w));
      setPdfPaneHeightPx((current) => (current === h ? current : h));
    };

    let resizeSettleTimer: number | null = null;

    const ro = new ResizeObserver(() => {
      // Resizing the split view can emit dozens of measurements per second.
      // Let the panels move live, but render the expensive PDF canvas once the
      // divider settles instead of restarting PDF.js for every changed pixel.
      if (resizeSettleTimer !== null) window.clearTimeout(resizeSettleTimer);
      resizeSettleTimer = window.setTimeout(() => {
        resizeSettleTimer = null;
        measurePdfPane();
      }, 200);
    });

    ro.observe(el);

    // Also do one immediate measurement right after attach
    measurePdfPane();

    return () => {
      ro.disconnect();
      if (resizeSettleTimer !== null) window.clearTimeout(resizeSettleTimer);
    };
  }, [documentVisible]);

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
      showDocument();
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
      showDocument();
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
    if (revisionWorkspace.unsavedIssueIds.length) {
      focusRevisionIssue(revisionWorkspace.unsavedIssueIds[0]);
      setStatusActionError('Save all changed revision recommendations before changing the invoice status.');
      return;
    }

    const invoiceRecordId = String(readData?.invoice_id || invoiceId || '').trim();
    const action = INVOICE_STATUS_ACTIONS.find((candidate) => candidate.key === transition);
    if (!invoiceRecordId || !action) return;

    const currentStatus = String(readData?.invoice_status || '').trim();
    if (!action.validFrom.includes(currentStatus)) {
      setStatusActionError(`${action.label} is not valid while this invoice is ${invoiceStatusLabel(currentStatus)}.`);
      return;
    }

    const confirmed = window.confirm(
      `${action.label}?\n\nCurrent status: ${invoiceStatusLabel(currentStatus)}\nNew status: ${invoiceStatusLabel(
        action.targetStatus,
      )}`,
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

  const classifierEligibilityFields = useMemo(
    () => classifierFields.filter((row) => isClassifierEligibilityField(row)),
    [classifierFields],
  );

  const classifierDisplayFields = useMemo(
    () => classifierFields.filter((row) => !isClassifierEligibilityField(row)),
    [classifierFields],
  );

  const upgradeTypeGroups = useMemo(() => {
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
      const upgradeTypeKey = upgradeTypeKeyFor(row);
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

    ensureGroup({ upgrade_type_key: 'common', upgrade_type_description: 'Common invoice evidence' });
    genAiFields.forEach((row) => ensureGroup(row).fields.push(row));
    classifierEligibilityFields.forEach((row) =>
      ensureGroup({
        ...row,
        upgrade_type_key: 'common',
        upgrade_type_description: 'Common invoice evidence',
      }).fields.push({
        ...row,
        upgrade_type_key: 'common',
        upgrade_type_description: 'Common invoice evidence',
      }),
    );
    genAiRulechecks.forEach((row) => ensureGroup(row).rulechecks.push(row));

    return Array.from(groups.values()).sort((a, b) => {
      const sortA = upgradeTypeSortValue(a.upgradeTypeKey);
      const sortB = upgradeTypeSortValue(b.upgradeTypeKey);
      if (sortA !== sortB) return sortA - sortB;
      return a.description.localeCompare(b.description);
    });
  }, [classifierEligibilityFields, genAiFields, genAiRulechecks]);

  const filteredGenAiRulechecks = useMemo(
    () => genAiRulechecks.filter((row) => ruleMatchesResultFilter(row, ruleResultFilters)),
    [genAiRulechecks, ruleResultFilters],
  );

  const classifierUpgradeTypeRows = useMemo(
    () =>
      [...upgradeTypeResults].sort((a, b) => {
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
  const currentInvoiceReferenceNumber = readData?.reference_number;
  const currentInvoiceReferenceLabel =
    currentInvoiceReferenceNumber !== null && currentInvoiceReferenceNumber !== undefined
      ? formatClaimsReferenceNumber(currentInvoiceReferenceNumber)
      : '—';
  const invoiceVersionNo = Number(readData?.invoice_versionno);
  const invoiceVersionLabel = Number.isFinite(invoiceVersionNo)
    ? invoiceVersionCount
      ? `Version ${invoiceVersionNo} of ${invoiceVersionCount}`
      : `Version ${invoiceVersionNo}`
    : null;
  const ahriProduct = readData?.ahri_product_match?.product;
  const neeaProduct = readData?.neea_product_match?.product;
  const awhpProduct = readData?.awhp_product_match?.product;
  const ohpaProduct = readData?.ohpa_product_match?.product;
  const hervProduct = readData?.herv_product_match?.product;
  const ventFanProduct = readData?.vent_fan_product_match?.product;
  const productMatchDetails = useMemo(() => {
    const matches: ProductMatchDetail[] = [];
    const appliesToAirSourceHeatPump = (upgradeTypeKey: string) =>
      upgradeTypeKey.startsWith('air_source_heat_pump_') || upgradeTypeKey === 'dual_fuel_ducted_heat_pump';

    if (ahriProduct) {
      matches.push({
        key: 'ahri',
        title: 'AHRI product registry match',
        appliesTo: appliesToAirSourceHeatPump,
        rows: [
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
        ],
      });
    }

    if (neeaProduct) {
      matches.push({
        key: 'neea',
        title: 'NEEA product registry match',
        appliesTo: (upgradeTypeKey) => upgradeTypeKey === 'heat_pump_water_heater',
        rows: [
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
        ],
      });
    }

    if (awhpProduct) {
      matches.push({
        key: 'awhp',
        title: 'Air-to-water product registry match',
        appliesTo: (upgradeTypeKey) =>
          upgradeTypeKey === 'air_to_water_heat_pump' || upgradeTypeKey === 'combined_space_water_heat_pump',
        rows: [
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
        ],
      });
    }

    if (ohpaProduct) {
      matches.push({
        key: 'ohpa',
        title: 'OHPA BC product registry match',
        appliesTo: appliesToAirSourceHeatPump,
        rows: [
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
        ],
      });
    }

    if (hervProduct) {
      matches.push({
        key: 'herv',
        title: 'ENERGY STAR H/ERV registry match',
        appliesTo: (upgradeTypeKey) => upgradeTypeKey === 'ventilation',
        rows: [
          ['Brand', hervProduct.brand],
          ['Model number', hervProduct.model_number],
          ['Model type', hervProduct.model_type],
          ['SRE at 0 C', hervProduct.sensible_heat_recovery_efficiency_sre_at_0c],
          ['SRE at -25 C', hervProduct.sensible_heat_recovery_efficiency_sre_at_minus_25c],
          ['Associated net supply airflow at 0 C CFM', hervProduct.associated_net_supply_airflow_at_0c_cfm],
          ['Associated net supply airflow at -25 C CFM', hervProduct.associated_net_supply_airflow_at_minus_25c_cfm],
          ['Associated power consumption at 0 C W', hervProduct.associated_power_consumption_at_0c_w],
          ['Associated power consumption at -25 C W', hervProduct.associated_power_consumption_at_minus_25c_w],
          ['Max rated airflow at 0 C CFM', hervProduct.max_rated_airflow_at_0c_cfm],
          ['Power consumption at 0 C W', hervProduct.power_consumption_at_0c_w],
          ['Eligibility notes', hervProduct.eligibility_notes],
        ],
      });
    }

    if (ventFanProduct) {
      matches.push({
        key: 'vent-fan',
        title: 'ENERGY STAR fan registry match',
        appliesTo: (upgradeTypeKey) => upgradeTypeKey === 'ventilation',
        rows: [
          ['Brand', ventFanProduct.brand],
          ['Model number', ventFanProduct.model_number],
          ['Product model name', ventFanProduct.product_model_name],
          ['Fan type', ventFanProduct.fan_type],
          ['Airflow 1 CFM', ventFanProduct.airflow_1_cfm],
          ['Efficacy 1 CFM/Watt', ventFanProduct.efficacy_1_cfm_watt],
          ['Sound level sones', ventFanProduct.sound_level_sones],
          ['Bathroom/utility airflow at 0.25 in. w.g.', ventFanProduct.bathroom_utility_airflow_at_0_25_in_wg],
          ['Markets', ventFanProduct.markets],
          ['ENERGY STAR Unique ID', ventFanProduct.energy_star_unique_id],
          ['CB model identifier', ventFanProduct.cb_model_identifier],
          ['Most Efficient criteria', ventFanProduct.meets_most_efficient_criteria],
        ],
      });
    }

    return matches;
  }, [ahriProduct, awhpProduct, hervProduct, neeaProduct, ohpaProduct, ventFanProduct]);
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
      const hasKnownType =
        String(doc?.supporting_document_type_key || '').trim() ||
        String(doc?.supporting_document_type_description || '').trim();
      ensureSection(
        hasKnownType
          ? doc?.supporting_document_type_key || doc?.supporting_document_type_description
          : 'other-unclassified-supporting-document',
        hasKnownType
          ? doc?.supporting_document_type_description || doc?.supporting_document_type_key
          : 'Other / unclassified supporting document',
      ).documents.push(doc);
    });

    return Array.from(sectionMap.values()).sort((a, b) => a.title.localeCompare(b.title));
  }, [uploadedSupportingDocuments]);
  const supportingFieldIdentityCounts = useMemo(() => {
    const counts = new Map<string, number>();
    uploadedSupportingDocuments.forEach((document: any) => {
      const typeKey = document?.supporting_document_type_key;
      const fields = Array.isArray(document?.located_fields) ? document.located_fields : [];
      fields.forEach((field: any) => {
        const key = supportingFieldRevisionIdentityKey(typeKey, field?.field_key);
        counts.set(key, (counts.get(key) || 0) + 1);
      });
    });
    return counts;
  }, [uploadedSupportingDocuments]);
  const revisionIssueForSupportingField = (document: any, field: any) => {
    const key = supportingFieldRevisionIdentityKey(document?.supporting_document_type_key, field?.field_key);
    return supportingFieldIdentityCounts.get(key) ? revisionIssueByIdentity.get(key) : undefined;
  };
  const renderedRevisionIdentityKeys = useMemo(() => {
    const keys = new Set<string>();
    DI_FIELDS.forEach((field) => keys.add(diFieldRevisionIdentityKey(field.key)));
    [...genAiFields, ...codeFields, ...classifierFields].forEach((field) =>
      keys.add(invoiceFieldRevisionIdentityKey(field)),
    );
    filteredGenAiRulechecks.forEach((rulecheck) => keys.add(rulecheckRevisionIdentityKey(rulecheck)));
    supportingFieldIdentityCounts.forEach((count, key) => {
      if (count > 0) keys.add(key);
    });
    return keys;
  }, [classifierFields, codeFields, filteredGenAiRulechecks, genAiFields, supportingFieldIdentityCounts]);
  const matchedRevisionIssueIds = useMemo(() => {
    const ids = new Set<string>();
    revisionWorkspace.issues.forEach((issue) => {
      const key = revisionSourceIdentityKey(issue.source_identity);
      if (key && renderedRevisionIdentityKeys.has(key)) ids.add(issue.id);
    });
    return ids;
  }, [renderedRevisionIdentityKeys, revisionWorkspace.issues]);
  const canOpenCommunicationPanels = canRunWorkflowActions && !!readData?.invoice_id;
  const activeAuxiliaryPanel = effectiveAuxiliaryPanel({
    revisionWorkspaceAvailable: usesEnterpriseRevisionWorkspace && showRevisionWorkspace,
  });
  const permittedAuxiliaryPanel = usesEnterpriseRevisionWorkspace
    ? activeAuxiliaryPanel === 'revision_issues' || canOpenCommunicationPanels
      ? activeAuxiliaryPanel
      : null
    : activeAuxiliaryPanel === 'conversation' && canOpenCommunicationPanels
      ? activeAuxiliaryPanel
      : null;
  const visibleAuxiliaryPanel =
    !usesEnterpriseRevisionWorkspace && showRevisionWorkspace && simpleRevisionSummaryVisible
      ? 'revision_summary'
      : permittedAuxiliaryPanel;
  const rightRegionMinimumWidth = documentVisible
    ? MIN_DOCUMENT_PANEL_WIDTH + (visibleAuxiliaryPanel ? INVOICE_REVIEW_PANEL_GAP + auxiliaryPanelWidth : 0)
    : visibleAuxiliaryPanel
      ? auxiliaryPanelWidth
      : 0;
  const simpleContextGridColumns =
    mainPanelWidth === null
      ? 'repeat(2, minmax(0, 1fr))'
      : `clamp(480px, ${mainPanelWidth}px, calc(100% - 296px)) minmax(280px, 1fr)`;
  const viewerPanelControls = (
    <Flex align="center" gap="14px" mb="12px" flexWrap="wrap" px="0" py="2px">
      <Tooltip label={documentVisible ? 'Hide the PDF document panel.' : 'Show the PDF document panel.'}>
        <Flex as="label" align="center" gap={2} cursor="pointer">
          <Switch
            aria-label="Show document"
            colorScheme="blue"
            isChecked={documentVisible}
            sx={{
              '--switch-track-width': '58px',
              '--switch-track-height': '24px',
              '.chakra-switch__track': { position: 'relative' },
              '.chakra-switch__track[data-checked]': { bg: 'theme.blue' },
              '.chakra-switch__track::after': {
                content: documentVisible ? '"ON"' : '"OFF"',
                position: 'absolute',
                top: '50%',
                left: documentVisible ? '7px' : 'auto',
                right: documentVisible ? 'auto' : '6px',
                transform: 'translateY(-50%)',
                color: documentVisible ? 'white' : 'gray.700',
                fontSize: '9px',
                fontWeight: 700,
                lineHeight: 1,
                pointerEvents: 'none',
              },
            }}
            onChange={(event) => {
              if (event.target.checked !== documentVisible) toggleDocument();
            }}
          />
          <Text fontSize="sm" fontWeight="semibold">
            Document
          </Text>
        </Flex>
      </Tooltip>
      {showRevisionWorkspace && !usesEnterpriseRevisionWorkspace ? (
        <Tooltip
          label={
            simpleRevisionSummaryVisible
              ? 'Hide the read-only Revision Summary side panel.'
              : 'Show the read-only Revision Summary side panel.'
          }
          hasArrow
        >
          <Flex as="label" align="center" gap={2} cursor="pointer">
            <Switch
              aria-label="Show revision summary"
              colorScheme="blue"
              isChecked={simpleRevisionSummaryVisible}
              sx={{
                '--switch-track-width': '58px',
                '--switch-track-height': '24px',
                '.chakra-switch__track': { position: 'relative' },
                '.chakra-switch__track[data-checked]': { bg: 'theme.blue' },
                '.chakra-switch__track::after': {
                  content: simpleRevisionSummaryVisible ? '"ON"' : '"OFF"',
                  position: 'absolute',
                  top: '50%',
                  left: simpleRevisionSummaryVisible ? '7px' : 'auto',
                  right: simpleRevisionSummaryVisible ? 'auto' : '6px',
                  transform: 'translateY(-50%)',
                  color: simpleRevisionSummaryVisible ? 'white' : 'gray.700',
                  fontSize: '9px',
                  fontWeight: 700,
                  lineHeight: 1,
                  pointerEvents: 'none',
                },
              }}
              onChange={(event) => {
                if (event.target.checked) closeCommunicationPanel();
                setSimpleRevisionSummaryVisible(event.target.checked);
              }}
            />
            <Text fontSize="sm" fontWeight="semibold">
              Revision Summary
            </Text>
          </Flex>
        </Tooltip>
      ) : null}
      <Box ml="auto" mr="8px">
        {ruleFilterMenu}
      </Box>
    </Flex>
  );
  const enterpriseRevisionWorkspaceContent = showRevisionWorkspace ? (
    <AdminRevisionWorkspace workspace={revisionWorkspace} sourceIssueIds={matchedRevisionIssueIds} />
  ) : null;
  const simpleRevisionSummaryContent = showRevisionWorkspace ? (
    <AdminRevisionSummary workspace={revisionWorkspace} sourceIssueIds={matchedRevisionIssueIds} />
  ) : null;
  // A stable source can appear in more than one evidence view. Mount its inline editor only at the first match.
  const renderedSimpleRevisionIssueIds = new Set<string>();
  const revisionIssueSourceContent = (issue?: RevisionIssue) => {
    if (!issue) return null;
    if (usesEnterpriseRevisionWorkspace) return <AdminRevisionSourceAnchor issueId={issue.id} />;
    if (renderedSimpleRevisionIssueIds.has(issue.id)) return null;
    renderedSimpleRevisionIssueIds.add(issue.id);
    return (
      <AdminRevisionIssueEditor
        issue={issue}
        workspace={revisionWorkspace}
        listStatus={adminRevisionIssueListStatus(issue, revisionWorkspace)}
        heading="Revision Request"
        showRecommendationInHeader={false}
      />
    );
  };
  const existingCaseFactsContent = (
    <>
      {genAiError ? (
        <Text fontSize="xs" color="red.500" mb="8px">
          {genAiError}
        </Text>
      ) : null}
      {!genAiError && codeFields.length === 0 ? (
        <Text fontSize="sm" opacity={0.7}>
          No participant information found.
        </Text>
      ) : (
        <Box display="grid" gridTemplateColumns="1fr 1fr" columnGap="8px" rowGap="0">
          {codeFields.map((row: any) => {
            const label = displayLocatedFieldLabel(row);
            const value = displayLocatedFieldValue(row);
            const issue = revisionIssueForInvoiceField(row);

            return (
              <React.Fragment key={row.id}>
                <FieldRow
                  label={label}
                  labelHint={locatedFieldKeyHint(row)}
                  value={value}
                  disabled
                  inline
                  textFontSize="16px"
                  {...invoiceFieldRevisionProps(row)}
                />
                {issue ? <Box gridColumn="1 / -1">{revisionIssueSourceContent(issue)}</Box> : null}
              </React.Fragment>
            );
          })}
        </Box>
      )}
    </>
  );
  const generalInvoiceFieldsContent = (
    <Box borderTopWidth="1px" borderColor="gray.200">
      <Text px="10px" py="5px" fontSize="sm" fontWeight="bold">
        Fields
      </Text>
      <Box px="10px" pt="3px" pb="6px">
        <PersonalInformationReviewFlag record={readData} />
        <Box display="grid" gridTemplateColumns="1fr 1fr" columnGap="8px" rowGap="0">
          {DI_FIELDS.map((field) => {
            const raw = readData?.[field.valueKey];
            if (field.hideWhenBlank && (raw == null || raw === '')) return null;

            const display = field.formatter ? field.formatter(raw) : String(raw ?? '-');
            const clickable = !field.disabled && !!field.pageKey && !!field.polygonKey;
            const issue = revisionIssueForDiField(field.key);

            return (
              <React.Fragment key={field.key}>
                <FieldRow
                  label={field.label}
                  value={display}
                  active={activeHighlightKey === field.key}
                  disabled={!clickable}
                  inline
                  {...diFieldRevisionProps(field.key)}
                  onClick={
                    clickable
                      ? () => {
                          showDocument();
                          setActiveHighlightKey(field.key);
                        }
                      : undefined
                  }
                />
                {issue ? <Box gridColumn="1 / -1">{revisionIssueSourceContent(issue)}</Box> : null}
              </React.Fragment>
            );
          })}
        </Box>
      </Box>
    </Box>
  );
  // ============================================================
  // SECTION 07.01 - MAIN RETURN
  // PURPOSE: JSX layout tree (header + nav + split panes)
  // ============================================================

  return (
    <Flex as="main" direction="column" w="full" bg="greys.white" pb="24" minH="100vh">
      {!bannerHidden && (
        <ThinBlueTitleBar
          title={titleText}
          contentMaxW="full"
          position="sticky"
          top={0}
          zIndex="sticky"
          boxShadow="0 4px 12px rgba(0, 0, 0, 0.16)"
          onDoubleClick={() => setBannerHidden(true)}
          leftElement={
            readData ? (
              <Flex direction="column" align="flex-start" gap={1}>
                <Tooltip
                  label={`${invoiceStatusCopy(currentInvoiceStatus).hint} Technical status: ${
                    currentInvoiceStatus || 'unknown'
                  }.`}
                  hasArrow
                >
                  <Badge
                    p={1}
                    fontSize="md"
                    color="greys.anotherGrey"
                    bg="theme.orangeLight02"
                    borderWidth="1px"
                    borderColor="theme.orange"
                    borderRadius="md"
                    fontWeight="bold"
                    textTransform="uppercase"
                    whiteSpace="nowrap"
                    aria-label={`Invoice status: ${invoiceStatusCopy(currentInvoiceStatus).label}`}
                  >
                    {invoiceStatusCopy(currentInvoiceStatus).label}
                  </Badge>
                </Tooltip>
                <Flex align="center" gap={3} flexWrap="wrap">
                  <Text color="white" fontSize="sm" fontWeight="semibold" whiteSpace="nowrap">
                    Reference #: {currentInvoiceReferenceLabel}
                  </Text>
                  {invoiceVersionLabel ? (
                    <Text color="white" fontSize="sm" fontWeight="semibold" whiteSpace="nowrap">
                      {invoiceVersionLabel}
                    </Text>
                  ) : null}
                </Flex>
              </Flex>
            ) : null
          }
          rightElement={
            readData ? (
              <Flex align="center" justify="flex-end" gap={{ base: 3, md: 6 }} flexWrap="wrap">
                {canRunWorkflowActions ? (
                  <Flex align="center" gap={2} flexWrap="wrap" justify="flex-end">
                    {INVOICE_STATUS_ACTIONS.map((action) => {
                      const isValidNow = action.validFrom.includes(currentInvoiceStatus);
                      if (action.key === 'approve_pending' && !isValidNow) return null;

                      const isSecondLevelAction = action.key === 'screen_in';
                      const disabledReason = ' This action is not available for this invoice status.';
                      return (
                        <Tooltip
                          key={action.key}
                          label={`${action.label}. ${action.tooltip}${isValidNow ? '' : disabledReason}`}
                          hasArrow
                        >
                          <Button
                            leftIcon={invoiceStatusActionIcon(action.key)}
                            size="sm"
                            colorScheme={action.colorScheme}
                            variant={isSecondLevelAction ? 'secondary' : isValidNow ? 'solid' : 'outline'}
                            bg={isSecondLevelAction || !isValidNow ? 'whiteAlpha.900' : undefined}
                            onClick={() => runStatusTransition(action.key)}
                            isDisabled={!isValidNow || !!statusActionLoading || !readData?.invoice_id}
                            isLoading={statusActionLoading === action.key}
                          >
                            {action.label}
                          </Button>
                        </Tooltip>
                      );
                    })}
                  </Flex>
                ) : (
                  <Tooltip label="Workflow buttons are hidden because this bookmark is for a fixed historical invoice version. Open the invoice-level review bookmark to act on the latest version.">
                    <Badge colorScheme="gray">Workflow actions hidden</Badge>
                  </Tooltip>
                )}
              </Flex>
            ) : null
          }
        />
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
              {usesEnterpriseRevisionWorkspace ? (
                <Tooltip
                  label={
                    canOpenCommunicationPanels
                      ? 'Show or hide admin-only internal notes.'
                      : 'Internal notes are available from the current invoice review bookmark.'
                  }
                  shouldWrapChildren
                >
                  <Button
                    aria-pressed={auxiliaryPanel === 'internal_notes'}
                    leftIcon={<NotePencil size={18} weight="bold" />}
                    size="sm"
                    colorScheme="gray"
                    variant={auxiliaryPanel === 'internal_notes' ? 'solid' : 'outline'}
                    onClick={() => toggleAuxiliaryPanel('internal_notes')}
                    isDisabled={!canOpenCommunicationPanels}
                  >
                    Internal Notes
                  </Button>
                </Tooltip>
              ) : null}
              {showRevisionWorkspace && usesEnterpriseRevisionWorkspace ? (
                <Tooltip
                  label={
                    revisionPlacement === 'top'
                      ? 'Move Revision Issues from above the evidence to the side panel.'
                      : 'Move Revision Issues from the side panel back above the evidence.'
                  }
                  hasArrow
                >
                  <Button size="sm" colorScheme="orange" variant="outline" onClick={toggleRevisionPlacement}>
                    {revisionPlacement === 'top' ? 'Move Revision Issues to Side' : 'Move Revision Issues to Top'}
                  </Button>
                </Tooltip>
              ) : null}
            </Box>
            {statusActionError && (
              <Box mb="8px">
                <Text fontSize="xs" color="red.700">
                  {statusActionError}
                </Text>
              </Box>
            )}
            {!usesEnterpriseRevisionWorkspace && revisionInvoiceId ? (
              <Box
                display="grid"
                gridTemplateColumns={{ base: '1fr', lg: simpleContextGridColumns }}
                gap="16px"
                alignItems="stretch"
                mb="16px"
              >
                <Box borderWidth="1px" borderColor="#D8D8D8" borderRadius="xl" overflow="hidden" bg="white">
                  <AdminInternalNotesPanel
                    invoiceId={revisionInvoiceId}
                    contractorBusinessName={String(readData?.contractor_business_name || '')}
                    diOcrInvoiceId={String(readData?.di_ocr_invoice_id || '')}
                    showContext={false}
                    notesViewportHeight="130px"
                  />
                </Box>
                <Box borderWidth="1px" borderColor="#D8D8D8" borderRadius="xl" bg="white" p="16px" minW={0}>
                  <Text fontSize="md" fontWeight="bold" mb="12px">
                    Participant Information
                  </Text>
                  {existingCaseFactsContent}
                </Box>
              </Box>
            ) : null}
            {/* ============================================================
        SECTION 07.04 - MAIN SPLIT VIEW
        PURPOSE: Left fields + Right PDF viewer
        ============================================================ */}
            <InvoiceReviewLayout>
              {/* ============================================================
    SECTION 07.05 - LEFT PANEL (ACCORDION WRAPPER)
    PURPOSE: Put header fields inside a collapsible accordion
    ============================================================ */}

              <InvoiceReviewMainPanel
                hasRightRegion={documentVisible || !!visibleAuxiliaryPanel}
                rightRegionMinimumWidth={rightRegionMinimumWidth}
                width={mainPanelWidth}
                onWidthChange={setMainPanelWidth}
              >
                {usesEnterpriseRevisionWorkspace && revisionPlacement === 'top'
                  ? enterpriseRevisionWorkspaceContent
                  : null}
                {viewerPanelControls}
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
                    '.chakra-accordion__button .chakra-text': {
                      fontSize: '20px',
                      fontWeight: 700,
                    },
                    '.chakra-accordion__panel .chakra-text': {
                      fontSize: '16px',
                    },
                    '.chakra-accordion__button': {
                      color: 'text.primary',
                      fontWeight: 700,
                      paddingLeft: '8px',
                      paddingTop: '10px',
                      paddingBottom: '10px',
                      borderRadius: '6px',
                      borderLeftWidth: '2px',
                      borderLeftStyle: 'solid',
                      borderLeftColor: 'transparent',
                      transition: 'background 180ms ease, border-color 180ms ease, color 180ms ease',
                    },
                    '.chakra-accordion__button:hover': {
                      color: 'text.primary',
                    },
                    '.chakra-accordion__icon': {
                      marginRight: '8px',
                    },
                    '.chakra-accordion__button[aria-expanded="true"]': {
                      background: '#F3F2F1',
                      borderLeftColor: '#898785',
                      color: 'text.primary',
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
                  <Box px="8px" pt="4px" pb="6px">
                    <Text fontSize="md" fontWeight="bold" color="gray.600">
                      Invoice Fields and Advice
                    </Text>
                  </Box>

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

                      <AccordionPanel px="0" pt="3px">
                        {genAiError && (
                          <Text fontSize="xs" color="red.500" mb="8px">
                            {genAiError}
                          </Text>
                        )}

                        <Box display="grid" gridTemplateColumns="1fr 1fr" columnGap="8px" rowGap="0">
                          {classifierDisplayFields.map((r: any) => {
                            const label = displayLocatedFieldLabel(r);
                            const value = displayLocatedFieldValue(r);
                            const confidence =
                              r.confidence != null ? `Confidence: ${Number(r.confidence).toFixed(2)}` : '';
                            const clickable = r.page != null;
                            const issue = revisionIssueForInvoiceField(r);
                            const revisionProps = invoiceFieldRevisionProps(r);

                            return (
                              <React.Fragment key={r.id}>
                                <Box
                                  role={clickable ? 'button' : undefined}
                                  cursor={clickable ? 'pointer' : 'default'}
                                  px="10px"
                                  py="2px"
                                  borderRadius="md"
                                  display="flex"
                                  alignItems="baseline"
                                  justifyContent="space-between"
                                  flexWrap={issue ? 'wrap' : undefined}
                                  gap="6px"
                                  position="relative"
                                  pr="38px"
                                  bg={
                                    activeHighlight?.source === 'classifier' &&
                                    activeHighlight?.genaiId === Number(r.id)
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
                                          showDocument();
                                        }
                                      : undefined
                                  }
                                >
                                  <Box position="absolute" right="6px" top="1px">
                                    <RevisionAddIconButton
                                      label={label}
                                      included={revisionProps.revisionChecked}
                                      onAdd={revisionProps.onAddToRevision}
                                      disabledReason={revisionProps.revisionAddDisabledReason}
                                    />
                                  </Box>
                                  <Flex align="center" gap="5px" minW={0} wrap="wrap">
                                    <Tooltip label={locatedFieldKeyHint(r)} hasArrow placement="top">
                                      <Text fontSize="sm" opacity={0.7} minW={0} noOfLines={1} cursor="help">
                                        {label}
                                      </Text>
                                    </Tooltip>
                                    <RevisionStatusBadge
                                      status={revisionProps.revisionStatus}
                                      onOpen={revisionProps.onOpenRevision}
                                    />
                                  </Flex>
                                  {confidence ? (
                                    <Tooltip label={confidence} hasArrow placement="top">
                                      <Text fontSize="sm" noOfLines={2} textAlign="right" cursor="help">
                                        {value}
                                      </Text>
                                    </Tooltip>
                                  ) : (
                                    <Text fontSize="sm" noOfLines={2} textAlign="right">
                                      {value}
                                    </Text>
                                  )}
                                  <RevisionSourceActions
                                    issue={revisionProps.revisionIssue}
                                    onSelect={revisionProps.onSelectRevisionAction}
                                  />
                                </Box>
                                {issue ? <Box gridColumn="1 / -1">{revisionIssueSourceContent(issue)}</Box> : null}
                              </React.Fragment>
                            );
                          })}
                        </Box>
                      </AccordionPanel>
                    </AccordionItem>
                  )}

                  {usesEnterpriseRevisionWorkspace ? (
                    <AccordionItem borderTopWidth="1px" borderColor="gray.200">
                      <h2>
                        <AccordionButton px="0" py="6px" _hover={{ bg: 'transparent' }}>
                          <Box flex="1" textAlign="left">
                            <Text size="sm" fontWeight="bold">
                              Participant Information
                            </Text>
                          </Box>
                          <AccordionIcon />
                        </AccordionButton>
                      </h2>

                      <AccordionPanel px="0" pt="3px">
                        {existingCaseFactsContent}
                      </AccordionPanel>
                    </AccordionItem>
                  ) : null}

                  {upgradeTypeGroups.length === 0 ? (
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
                          No upgrade-type advice rows found.
                        </Text>
                      </AccordionPanel>
                    </AccordionItem>
                  ) : (
                    <>
                      {upgradeTypeGroups.map((group) => {
                        const meta = getInvoiceUpgradeTypeMeta(group.upgradeTypeKey, group.description);
                        const registryMatches = productMatchDetails.filter((match) =>
                          match.appliesTo(group.upgradeTypeKey),
                        );
                        const visibleRulechecks = group.rulechecks.filter((row) =>
                          ruleMatchesResultFilter(row, ruleResultFilters),
                        );

                        return (
                          <AccordionItem key={group.upgradeTypeKey} borderTopWidth="1px" borderColor="gray.200">
                            <h2>
                              <AccordionButton px="0" py="8px" _hover={{ bg: 'transparent' }}>
                                <Flex flex="1" align="center" gap="8px" textAlign="left" minW={0}>
                                  <Box minW={0}>
                                    <Text fontSize="20px" lineHeight="1.25" fontWeight="bold" noOfLines={1}>
                                      {group.upgradeTypeKey === 'common' ? 'Common' : meta.label}
                                    </Text>
                                  </Box>
                                </Flex>
                                <AccordionIcon />
                              </AccordionButton>
                            </h2>

                            <AccordionPanel px="0" pt="4px">
                              {group.upgradeTypeKey === 'common' || registryMatches.length > 0 ? (
                                <Flex justify="flex-end" gap="8px" px="10px" pb="6px" wrap="wrap">
                                  {group.upgradeTypeKey === 'common' ? (
                                    <>
                                      <Button
                                        size="sm"
                                        variant="secondary"
                                        onClick={() => setClassifiedUpgradeTypesOpen(true)}
                                      >
                                        Classified Upgrade Types
                                      </Button>
                                      <Button size="sm" variant="outline" onClick={() => setLineItemsOpen(true)}>
                                        Line Items
                                      </Button>
                                    </>
                                  ) : null}
                                  {registryMatches.map((match) => (
                                    <Button
                                      key={match.key}
                                      size="sm"
                                      variant="secondary"
                                      onClick={() => setProductMatchModal(match)}
                                    >
                                      {match.title}
                                    </Button>
                                  ))}
                                </Flex>
                              ) : null}
                              {group.upgradeTypeKey === 'common' ? generalInvoiceFieldsContent : null}
                              <Box borderTopWidth="1px" borderColor="gray.200">
                                {group.upgradeTypeKey !== 'common' ? (
                                  <Box px="10px" py="5px">
                                    <Text fontSize="sm" fontWeight="bold">
                                      Fields
                                    </Text>
                                  </Box>
                                ) : null}

                                <Box px="10px" pt="3px" pb="6px">
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
                                        const label = displayLocatedFieldLabel(r);
                                        const value = displayLocatedFieldValue(r);
                                        const sourceEngine = String(r?.source_engine ?? 'genai').toLowerCase();
                                        const highlightSource = sourceEngine === 'classifier' ? 'classifier' : 'genai';
                                        const highlightKey = `${highlightSource}_${r.id}`;
                                        const confidence =
                                          r.confidence != null ? `Confidence: ${Number(r.confidence).toFixed(0)}` : '';
                                        const clickable = r.page != null;
                                        const issue = revisionIssueForInvoiceField(r);

                                        return (
                                          <React.Fragment key={r.id}>
                                            <FieldRow
                                              label={label}
                                              labelHint={locatedFieldKeyHint(r)}
                                              value={value}
                                              hint={confidence}
                                              active={activeHighlightKey === highlightKey}
                                              disabled={!clickable}
                                              inline
                                              {...invoiceFieldRevisionProps(r)}
                                              onClick={
                                                clickable
                                                  ? () => {
                                                      setActiveHighlight({
                                                        source: highlightSource,
                                                        genaiId: Number(r.id),
                                                        pageNumber: Number(r.page),
                                                        polygon: r.polygon ?? null,
                                                      });
                                                      showDocument();
                                                      setActiveHighlightKey(highlightKey);
                                                    }
                                                  : undefined
                                              }
                                            />
                                            {issue ? (
                                              <Box gridColumn="1 / -1">{revisionIssueSourceContent(issue)}</Box>
                                            ) : null}
                                          </React.Fragment>
                                        );
                                      })}
                                    </Box>
                                  )}
                                </Box>
                              </Box>

                              <Box borderTopWidth="1px" borderColor="gray.200">
                                <Box px="10px" py="5px">
                                  <Text fontSize="sm" fontWeight="bold">
                                    Advice
                                  </Text>
                                </Box>

                                <Box px="10px" pt="3px" pb="6px">
                                  {genAiRulechecksError && (
                                    <Text fontSize="xs" color="red.500" mb="8px">
                                      {genAiRulechecksError}
                                    </Text>
                                  )}
                                  {group.rulechecks.length === 0 ? (
                                    <Text fontSize="sm" opacity={0.7}>
                                      No advice for this upgrade type.
                                    </Text>
                                  ) : visibleRulechecks.length === 0 ? (
                                    <Text fontSize="sm" opacity={0.7}>
                                      No advice matching the selected rule filter.
                                    </Text>
                                  ) : (
                                    <Box display="flex" flexDirection="column" gap="10px">
                                      {visibleRulechecks.map((r: any) => {
                                        const title = ruleDisplayTitle(r);
                                        const reason = r.reason_and_likely_causes ?? '';
                                        const issue = revisionIssueForRulecheck(r);

                                        return (
                                          <Box
                                            key={r.id ?? `${r.source_engine}-${r.rule_key}`}
                                            pl="10px"
                                            pr="10px"
                                            py="4px"
                                            borderLeftWidth="4px"
                                            borderLeftStyle="solid"
                                            borderLeftColor="#D8EAFD"
                                            borderRadius="md"
                                          >
                                            <Box
                                              display="grid"
                                              gridTemplateColumns="76px 28px minmax(180px, 1fr) 26px"
                                              gap="8px"
                                              alignItems="center"
                                            >
                                              <RuleResultIndicator result={r.rule_result} />
                                              <Tooltip label="Rule details" hasArrow placement="top">
                                                <IconButton
                                                  aria-label={`Rule details for ${title}`}
                                                  icon={<Info size={16} />}
                                                  size="xs"
                                                  variant="ghost"
                                                  onClick={(event) => {
                                                    event.stopPropagation();
                                                    setRuleDetailsDrawerRulecheck(r);
                                                  }}
                                                />
                                              </Tooltip>
                                              <Flex align="center" gap="6px" minW={0} wrap="wrap">
                                                <Tooltip
                                                  label={`Rule key: ${String(r.rule_key || '')}`}
                                                  isDisabled={!String(r.rule_key || '').trim()}
                                                  hasArrow
                                                  placement="top"
                                                >
                                                  <Text fontSize="sm" fontWeight="semibold" minW={0} noOfLines={1}>
                                                    {title}
                                                  </Text>
                                                </Tooltip>
                                                <RevisionStatusBadge
                                                  status={revisionStatusForIssue(issue)}
                                                  onOpen={issue ? () => focusRevisionIssue(issue.id) : undefined}
                                                />
                                              </Flex>
                                              <RevisionAddIconButton
                                                label={title}
                                                included={false}
                                                onAdd={
                                                  !issue && canRunWorkflowActions && canAddRevisionIssue
                                                    ? () =>
                                                        void addToRevision(
                                                          'rule',
                                                          'invoice_version_rulecheck_id',
                                                          String(r.id),
                                                        )
                                                    : undefined
                                                }
                                                disabledReason={
                                                  !issue && canRunWorkflowActions
                                                    ? revisionAddDisabledReason
                                                    : undefined
                                                }
                                              />
                                            </Box>

                                            {reason && (
                                              <Box mt="2px">
                                                <Text as="span" fontSize="sm" fontWeight="bold">
                                                  Reason:{' '}
                                                </Text>
                                                <Text as="span" fontSize="sm">
                                                  {String(reason)}
                                                </Text>
                                              </Box>
                                            )}
                                            {usesEnterpriseRevisionWorkspace ? (
                                              <RevisionSourceActions
                                                issue={issue}
                                                onSelect={
                                                  issue ? (mode) => focusRevisionIssue(issue.id, mode) : undefined
                                                }
                                              />
                                            ) : null}
                                            {revisionIssueSourceContent(issue)}
                                          </Box>
                                        );
                                      })}
                                    </Box>
                                  )}
                                </Box>
                              </Box>
                            </AccordionPanel>
                          </AccordionItem>
                        );
                      })}
                    </>
                  )}

                  <Box px="8px" pt="24px" pb="6px">
                    <Text fontSize="md" fontWeight="bold" color="gray.600">
                      Supporting Documents
                    </Text>
                  </Box>

                  {supportingDocumentEvidenceSections.length === 0 ? (
                    <Box borderTopWidth="1px" borderColor="gray.200" px="12px" py="12px">
                      <Flex align="center" justify="space-between" gap="12px" wrap="wrap">
                        <Text fontSize="sm" opacity={0.7}>
                          No supporting-document evidence stored for this invoice.
                        </Text>
                        <PossibleSupportingDocumentsButton onClick={() => setPossibleSupportingDocumentsOpen(true)} />
                      </Flex>
                    </Box>
                  ) : (
                    supportingDocumentEvidenceSections.flatMap((section) =>
                      section.documents.map((doc: any, documentIndex: number) => {
                        const fields = Array.isArray(doc?.located_fields) ? doc.located_fields : [];
                        const findings = Array.isArray(doc?.visual_findings) ? doc.visual_findings : [];
                        const filename = String(doc?.original_filename || 'Unnamed file');
                        const documentCount = section.documents.length;
                        const documentOrdinal = documentCount > 1 ? ` ${documentIndex + 1} of ${documentCount}` : '';

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
                                    {`${section.title}${documentOrdinal}`}
                                  </Text>
                                </Box>
                                <AccordionIcon />
                              </AccordionButton>
                            </h2>
                            <AccordionPanel px="0" pt="8px">
                              <Box px="10px" py="3px">
                                <PersonalInformationReviewFlag record={doc} />
                                <Flex justify="flex-end" gap="8px" mb="6px">
                                  <PossibleSupportingDocumentsButton
                                    onClick={() => setPossibleSupportingDocumentsOpen(true)}
                                  />
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
                                    Original file name
                                  </Text>
                                  <Text fontSize="sm" noOfLines={1} title={filename}>
                                    {filename}
                                  </Text>
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
                                    gridTemplateColumns={
                                      showAdminFieldRevisionPlus ? '160px minmax(0, 1fr) 26px' : '160px minmax(0, 1fr)'
                                    }
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
                                      const issue = revisionIssueForSupportingField(doc, field);

                                      return (
                                        <React.Fragment key={String(field?.id || field?.field_key)}>
                                          <Flex align="center" gap="5px" minW={0} wrap="wrap">
                                            <Tooltip label={locatedFieldKeyHint(field)} hasArrow placement="top">
                                              <Text
                                                fontSize="sm"
                                                opacity={0.7}
                                                minW={0}
                                                noOfLines={1}
                                                cursor="help"
                                                bg={isActive ? 'red.50' : 'transparent'}
                                                borderRadius="sm"
                                                onClick={handleClick}
                                              >
                                                {displayLocatedFieldLabel(field)}
                                              </Text>
                                            </Tooltip>
                                            <RevisionStatusBadge
                                              status={revisionStatusForIssue(issue)}
                                              onOpen={issue ? () => focusRevisionIssue(issue.id) : undefined}
                                            />
                                          </Flex>
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
                                          {showAdminFieldRevisionPlus ? (
                                            <RevisionAddIconButton
                                              label={displayLocatedFieldLabel(field)}
                                              included={false}
                                              onAdd={
                                                !issue && canRunWorkflowActions && canAddRevisionIssue
                                                  ? () =>
                                                      void addToRevision(
                                                        'supporting_document_field',
                                                        'supporting_document_located_field_id',
                                                        String(field?.id),
                                                      )
                                                  : undefined
                                              }
                                              disabledReason={
                                                !issue && canRunWorkflowActions ? revisionAddDisabledReason : undefined
                                              }
                                            />
                                          ) : null}
                                          {issue ? (
                                            <Box gridColumn="1 / -1">
                                              {usesEnterpriseRevisionWorkspace ? (
                                                <RevisionSourceActions
                                                  issue={issue}
                                                  onSelect={(mode) => focusRevisionIssue(issue.id, mode)}
                                                />
                                              ) : null}
                                              {revisionIssueSourceContent(issue)}
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
                                            showDocument();
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
                              const label = displayLocatedFieldLabel(r);
                              const value = displayLocatedFieldValue(r);

                              const confidence =
                                r.confidence != null ? `Confidence: ${Number(r.confidence).toFixed(2)}` : '';

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
                                    showDocument();
                                  }}
                                >
                                  <Tooltip label={locatedFieldKeyHint(r)} hasArrow placement="top">
                                    <Text fontSize="xs" opacity={0.7} cursor="help">
                                      {label}
                                    </Text>
                                  </Tooltip>
                                  {confidence ? (
                                    <Tooltip label={confidence} hasArrow placement="top">
                                      <Text fontSize="sm" noOfLines={3} cursor="help">
                                        {value}
                                      </Text>
                                    </Tooltip>
                                  ) : (
                                    <Text fontSize="sm" noOfLines={3}>
                                      {value}
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
                              const label = displayLocatedFieldLabel(r);
                              const value = displayLocatedFieldValue(r);
                              const confidence =
                                r.confidence != null ? `Confidence: ${Number(r.confidence).toFixed(2)}` : '';
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
                                          showDocument();
                                        }
                                      : undefined
                                  }
                                >
                                  <Tooltip label={locatedFieldKeyHint(r)} hasArrow placement="top">
                                    <Text fontSize="xs" opacity={0.7} cursor="help">
                                      {label}
                                    </Text>
                                  </Tooltip>
                                  {confidence ? (
                                    <Tooltip label={confidence} hasArrow placement="top">
                                      <Text fontSize="sm" noOfLines={3} cursor="help">
                                        {value}
                                      </Text>
                                    </Tooltip>
                                  ) : (
                                    <Text fontSize="sm" noOfLines={3}>
                                      {value}
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
                              <Text size="sm">Participant Information</Text>
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
                              No participant information found.
                            </Text>
                          )}

                          <Box display="grid" gridTemplateColumns="1fr 1fr" gap="8px">
                            {/* list */}
                            {codeFields.map((r: any) => {
                              const label = displayLocatedFieldLabel(r);
                              const value = displayLocatedFieldValue(r);

                              const confidence =
                                r.confidence != null ? `Confidence: ${Number(r.confidence).toFixed(2)}` : '';

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
                                    showDocument();
                                  }}
                                >
                                  <Tooltip label={locatedFieldKeyHint(r)} hasArrow placement="top">
                                    <Text fontSize="xs" opacity={0.7} cursor="help">
                                      {label}
                                    </Text>
                                  </Tooltip>
                                  {confidence ? (
                                    <Tooltip label={confidence} hasArrow placement="top">
                                      <Text fontSize="sm" noOfLines={3} cursor="help">
                                        {value}
                                      </Text>
                                    </Tooltip>
                                  ) : (
                                    <Text fontSize="sm" noOfLines={3}>
                                      {value}
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
                              <Text size="sm">Advice Checks</Text>
                            </Box>
                            <AccordionIcon />
                          </AccordionButton>
                        </h2>

                        <AccordionPanel px="0" pt="8px">
                          {/* ============================================================
    SECTION 07.05.30.05 - GENAI OVERALL SUMMARY (from /read)
    PURPOSE: Quiet summary at top of Rule Checks panel
    REQUIRES: readData includes these invoice_versions columns:
      ? validation_result
      ? contractor_advice
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
                            <ContractorAdviceMarkdown value={readData?.contractor_advice} />
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
                              No advice checks found.
                            </Text>
                          )}
                          {!genAiRulechecksError &&
                            genAiRulechecks.length > 0 &&
                            filteredGenAiRulechecks.length === 0 && (
                              <Text fontSize="sm" opacity={0.7}>
                                No advice checks matching the selected rule filter.
                              </Text>
                            )}

                          {/* list */}
                          {filteredGenAiRulechecks.map((r: any) => {
                            const title = ruleDisplayTitle(r);
                            // Keep rule explanations compact but readable in the admin viewer.
                            const reason = r.reason_and_likely_causes ?? '';

                            return (
                              <Box
                                key={r.id ?? `${r.source_engine}-${r.rule_key}`}
                                px="10px"
                                py="8px"
                                mb="8px"
                                borderRadius="md"
                                borderWidth="1px"
                                borderColor="gray.200"
                                bg="white"
                              >
                                <Flex align="center" gap="8px">
                                  <RuleResultIndicator result={r.rule_result} />
                                  <Tooltip label="Rule details" hasArrow placement="top">
                                    <IconButton
                                      aria-label={`Rule details for ${title}`}
                                      icon={<Info size={16} />}
                                      size="xs"
                                      variant="ghost"
                                      onClick={(event) => {
                                        event.stopPropagation();
                                        setRuleDetailsDrawerRulecheck(r);
                                      }}
                                    />
                                  </Tooltip>
                                  <Tooltip
                                    label={`Rule key: ${String(r.rule_key || '')}`}
                                    isDisabled={!String(r.rule_key || '').trim()}
                                    hasArrow
                                    placement="top"
                                  >
                                    <Text fontSize="xs" opacity={0.7}>
                                      {title}
                                    </Text>
                                  </Tooltip>
                                </Flex>

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
                              </Box>
                            );
                          })}
                        </AccordionPanel>
                      </AccordionItem>
                    </>
                  )}
                </Accordion>
              </InvoiceReviewMainPanel>

              {documentVisible || visibleAuxiliaryPanel ? (
                <InvoiceReviewRightRegion minimumWidth={rightRegionMinimumWidth}>
                  {/* ============================================================
        SECTION 07.06 - RIGHT PANEL (PDF)
        PURPOSE: PDF viewer + overlay highlight + toolbar
        ============================================================ */}

                  {documentVisible ? (
                    <Box
                      ref={pdfWrapRef}
                      flex="1 1 640px"
                      w="auto"
                      minW={`${MIN_DOCUMENT_PANEL_WIDTH}px`}
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
                                <polygon
                                  points={svgPolygonPoints}
                                  fill="rgba(255,0,0,0.20)"
                                  stroke="red"
                                  strokeWidth={2}
                                />
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
                  {visibleAuxiliaryPanel ? (
                    <InvoiceReviewAuxiliaryPanel
                      width={auxiliaryPanelWidth}
                      onWidthChange={setAuxiliaryPanelWidth}
                      fillAvailableWidth={!documentVisible}
                      chromeless={visibleAuxiliaryPanel === 'revision_summary'}
                    >
                      {visibleAuxiliaryPanel === 'revision_summary' ? simpleRevisionSummaryContent : null}
                      {visibleAuxiliaryPanel === 'revision_issues' ? enterpriseRevisionWorkspaceContent : null}
                      {usesEnterpriseRevisionWorkspace && mountedAuxiliaryPanels.internal_notes ? (
                        <Box display={visibleAuxiliaryPanel === 'internal_notes' ? 'block' : 'none'}>
                          <AdminInternalNotesPanel
                            invoiceId={revisionInvoiceId}
                            contractorBusinessName={String(readData?.contractor_business_name || '')}
                            diOcrInvoiceId={String(readData?.di_ocr_invoice_id || '')}
                            onClose={closeCommunicationPanel}
                          />
                        </Box>
                      ) : null}
                    </InvoiceReviewAuxiliaryPanel>
                  ) : null}
                </InvoiceReviewRightRegion>
              ) : null}
            </InvoiceReviewLayout>{' '}
            {/* closes SECTION 07.04 main split view */}
          </Box>{' '}
          {/*  ADD: closes SECTION 07.02 page layout <Box display="flex" flexDirection="column" ...> */}
        </Box>{' '}
        {/*  ADD THIS: closes the first Box inside Container (Box A) */}
      </Container>{' '}
      {/*  THIS is the closecontainer line */}
      <Box
        id="admin-contractor-chat-dialog"
        role="dialog"
        aria-modal="false"
        aria-label="Chat with Contractor"
        display={adminChatPanelOpen && canOpenCommunicationPanels ? 'flex' : 'none'}
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
        overflowY="auto"
      >
        {adminChatPanelOpen && canOpenCommunicationPanels ? (
          <AdminConversationPanel
            invoiceId={revisionInvoiceId}
            latestInvoiceVersionId={String(readData?.id || '')}
            contractorBusinessName={String(readData?.contractor_business_name || '')}
            diOcrInvoiceId={String(readData?.di_ocr_invoice_id || '')}
            onClose={() => setAdminChatPanelOpen(false)}
          />
        ) : null}
      </Box>
      <Box position="fixed" right={{ base: '12px', md: '24px' }} bottom={{ base: '12px', md: '24px' }} zIndex={1600}>
        <Tooltip label="View and send messages about this invoice." hasArrow shouldWrapChildren>
          <Button
            size="md"
            bg="theme.blueGradient"
            color="white"
            borderRadius="md"
            boxShadow={canOpenCommunicationPanels ? '0 10px 24px rgba(5, 66, 119, 0.28)' : 'none'}
            _hover={{ bg: 'theme.blueAltGradient' }}
            _disabled={{ opacity: 0.5, cursor: 'not-allowed' }}
            isDisabled={!canOpenCommunicationPanels}
            aria-label="Chat with Contractor"
            aria-expanded={adminChatPanelOpen}
            aria-controls="admin-contractor-chat-dialog"
            onClick={() => {
              if (!canOpenCommunicationPanels) return;
              setAdminChatPanelOpen((open) => !open);
            }}
          >
            Chat with Contractor
          </Button>
        </Tooltip>
      </Box>
      <PossibleSupportingDocumentsModal
        isOpen={possibleSupportingDocumentsOpen}
        onClose={() => setPossibleSupportingDocumentsOpen(false)}
        groups={supportingDocumentTypeGroups}
      />
      <ProductMatchModal match={productMatchModal} onClose={() => setProductMatchModal(null)} />
      <ClassifiedUpgradeTypesModal
        isOpen={classifiedUpgradeTypesOpen}
        onClose={() => setClassifiedUpgradeTypesOpen(false)}
        rows={classifierUpgradeTypeRows}
        onFocus={(row) => {
          setActiveHighlight({
            source: 'classifier',
            key: `classifier_upgrade_${row.id}`,
            pageNumber: Number(row.page),
            polygon: row.polygon ?? null,
          });
          showDocument();
          setClassifiedUpgradeTypesOpen(false);
        }}
      />
      <LineItemsModal
        isOpen={lineItemsOpen}
        onClose={() => setLineItemsOpen(false)}
        rows={sortedLineitems}
        error={lineitemsError}
        activeHighlightKey={activeHighlightKey}
        onFocus={(row, highlightKey) => {
          setActiveHighlight({
            source: 'di',
            key: highlightKey,
            pageNumber: Number(row.ocr_description_page),
            polygon: row.ocr_description_polygon,
          });
          showDocument();
          setActiveHighlightKey(highlightKey);
          setLineItemsOpen(false);
        }}
      />
      <Drawer
        isOpen={!!ruleDetailsDrawerRulecheck}
        placement="right"
        onClose={() => setRuleDetailsDrawerRulecheck(null)}
        size="xl"
      >
        <DrawerOverlay />
        <DrawerContent>
          <DrawerCloseButton />
          <DrawerHeader>
            <Flex direction="column" gap="4px" pr="32px">
              <Flex align="center" gap="8px" wrap="wrap">
                <StatusDot result={ruleDetailsDrawerRulecheck?.rule_result} />
                <Tooltip
                  label={`Rule key: ${String(ruleDetailsDrawerRulecheck?.rule_key || '')}`}
                  isDisabled={!String(ruleDetailsDrawerRulecheck?.rule_key || '').trim()}
                  hasArrow
                  placement="top"
                >
                  <Text fontSize="md" fontWeight="bold" noOfLines={2}>
                    {ruleDetailsDrawerRulecheck ? ruleDisplayTitle(ruleDetailsDrawerRulecheck) : 'Rule details'}
                  </Text>
                </Tooltip>
              </Flex>
              <Flex align="center" gap="8px" wrap="wrap">
                {ruleDetailsDrawerRulecheck?.source_engine && (
                  <Badge colorScheme="gray" variant="subtle" textTransform="lowercase">
                    {ruleSourceLabel(ruleDetailsDrawerRulecheck)}
                  </Badge>
                )}
              </Flex>
            </Flex>
          </DrawerHeader>
          <DrawerBody>
            <Tabs
              key={String(
                ruleDetailsDrawerRulecheck?.id ||
                  `${ruleDetailsDrawerRulecheck?.invoice_upgrade_type_id || ''}:${ruleDetailsDrawerRulecheck?.source_engine || ''}:${ruleDetailsDrawerRulecheck?.rule_key || ''}`,
              )}
              variant="unstyled"
              defaultIndex={0}
            >
              <TabList mb="20px" p="4px" borderRadius="xl" bg="gray.100" border="1px solid" borderColor="gray.200">
                {['Assessment', 'Rule setup'].map((label) => (
                  <Tab
                    key={label}
                    flex="1"
                    minH="38px"
                    borderRadius="lg"
                    fontSize="sm"
                    fontWeight="700"
                    color="gray.600"
                    transition="background 160ms ease, color 160ms ease, box-shadow 160ms ease"
                    _selected={{
                      bg: 'white',
                      color: 'blue.700',
                      boxShadow: '0 5px 14px -8px rgba(15, 42, 67, 0.65)',
                    }}
                    _focusVisible={{ boxShadow: 'outline' }}
                  >
                    {label}
                  </Tab>
                ))}
              </TabList>

              <TabPanels>
                <TabPanel p={0}>
                  {hasComplianceSpectrum(ruleDetailsDrawerRulecheck) ? (
                    <ComplianceSpectrum
                      compact
                      complianceScore={ruleDetailsDrawerRulecheck?.compliance_score}
                      result={ruleDetailsDrawerRulecheck?.rule_result}
                      sourceEngine={ruleDetailsDrawerRulecheck?.source_engine}
                      assessmentContent={
                        <Box minW={0}>
                          <RuleDetailDrawerSection label="Expected">
                            <RuleDetailText
                              value={ruleDetailsDrawerRulecheck?.expected_text ?? ruleDetailsDrawerRulecheck?.expected}
                            />
                          </RuleDetailDrawerSection>

                          <RuleDetailDrawerSection label="Calculation">
                            <RuleDetailText value={ruleDetailsDrawerRulecheck?.calculation} />
                          </RuleDetailDrawerSection>

                          <RuleDetailDrawerSection label="Evidence">
                            <RuleDetailText value={ruleDetailsDrawerRulecheck?.evidence_text} />
                          </RuleDetailDrawerSection>
                        </Box>
                      }
                    />
                  ) : (
                    <Box minW={0}>
                      <RuleDetailDrawerSection label="Expected">
                        <RuleDetailText
                          value={ruleDetailsDrawerRulecheck?.expected_text ?? ruleDetailsDrawerRulecheck?.expected}
                        />
                      </RuleDetailDrawerSection>

                      <RuleDetailDrawerSection label="Calculation">
                        <RuleDetailText value={ruleDetailsDrawerRulecheck?.calculation} />
                      </RuleDetailDrawerSection>

                      <RuleDetailDrawerSection label="Evidence">
                        <RuleDetailText value={ruleDetailsDrawerRulecheck?.evidence_text} />
                      </RuleDetailDrawerSection>
                    </Box>
                  )}
                </TabPanel>

                <TabPanel p={0}>
                  {ruleDetailsDrawerRulecheck?.upgrade_type_description && (
                    <RuleDetailDrawerSection label="Applies to">
                      <RuleDetailText value={ruleDetailsDrawerRulecheck.upgrade_type_description} />
                    </RuleDetailDrawerSection>
                  )}

                  <RuleDetailDrawerSection label="Rule Key">
                    <RuleDetailText value={ruleDetailsDrawerRulecheck?.rule_key} />
                  </RuleDetailDrawerSection>

                  <RuleDetailDrawerSection label="Rule policies">
                    <Box
                      display="grid"
                      gridTemplateColumns={{ base: '1fr', md: 'repeat(3, minmax(0, 1fr))' }}
                      gap="10px"
                    >
                      {[
                        [
                          'Contractor visibility',
                          contractorVisibilityLabel(ruleDetailsDrawerRulecheck?.contractor_visibility),
                        ],
                        [
                          'Submission blocking',
                          contractorBlockingPolicyLabel(ruleDetailsDrawerRulecheck?.contractor_blocking_policy),
                        ],
                        [
                          'Admin workflow management',
                          adminWorkflowPolicyLabel(ruleDetailsDrawerRulecheck?.admin_workflow_policy),
                        ],
                      ].map(([label, value]) => (
                        <Box
                          key={label}
                          borderWidth="1px"
                          borderColor="gray.200"
                          borderRadius="md"
                          p="10px"
                          bg="gray.50"
                        >
                          <Text fontSize="xs" fontWeight="700" color="gray.600" mb="3px">
                            {label}
                          </Text>
                          <Text fontSize="sm">{value}</Text>
                        </Box>
                      ))}
                    </Box>
                  </RuleDetailDrawerSection>

                  <RuleDetailDrawerSection label="Source Quote">
                    {String(ruleDetailsDrawerRulecheck?.source_quote ?? '').trim() ? (
                      <SourceQuoteMarkdown value={ruleDetailsDrawerRulecheck?.source_quote} />
                    ) : (
                      <RuleDetailText value="" />
                    )}
                  </RuleDetailDrawerSection>

                  <RuleDetailDrawerSection label="Pre-check Contractor Action">
                    <RuleDetailText value={ruleDetailsDrawerRulecheck?.contractor_action} />
                  </RuleDetailDrawerSection>

                  <RuleDetailDrawerSection label={ruleDefinitionLabel(ruleDetailsDrawerRulecheck)}>
                    <RuleDetailText value={ruleDetailsDrawerRulecheck?.rule_definition_text} />
                  </RuleDetailDrawerSection>
                </TabPanel>
              </TabPanels>
            </Tabs>
          </DrawerBody>
        </DrawerContent>
      </Drawer>
    </Flex>
  );
};
