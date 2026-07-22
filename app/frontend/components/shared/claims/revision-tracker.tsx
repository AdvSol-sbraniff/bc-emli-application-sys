import {
  Accordion,
  AccordionButton,
  AccordionIcon,
  AccordionItem,
  AccordionPanel,
  AlertDialog,
  AlertDialogBody,
  AlertDialogContent,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogOverlay,
  Badge,
  Box,
  Button,
  Drawer,
  DrawerBody,
  DrawerCloseButton,
  DrawerContent,
  DrawerHeader,
  DrawerOverlay,
  Flex,
  FormControl,
  FormLabel,
  IconButton,
  Select,
  Spinner,
  Text,
  Textarea,
  useToast,
} from '@chakra-ui/react';
import { ArrowCounterClockwise, CheckCircle, FloppyDiskBack, Info, PaperPlaneTilt, Trash } from '@phosphor-icons/react';
import React, { useCallback, useEffect, useRef, useState } from 'react';

export type RevisionSource = {
  source_key?: string | null;
  source_engine?: string | null;
  friendly_label?: string | null;
  rule_result?: string | null;
  reason?: string | null;
  evidence_text?: string | null;
  expected_text?: string | null;
  source_quote?: string | null;
  page?: number | null;
  polygon?: unknown;
  value?: unknown;
  value_type?: string | null;
  document?: {
    kind?: 'invoice' | 'supporting_document';
    id?: string | null;
    invoice_version_id?: string | null;
    invoice_versionno?: number | null;
    filename?: string | null;
  } | null;
};

export type RevisionRound = {
  id: string;
  invoice_version_id: string;
  invoice_versionno?: number | null;
  original_filename?: string | null;
  round_number: number;
  state: 'draft' | 'awaiting_contractor' | 'response_submitted';
  admin_sent_at?: string | null;
  contractor_response_submitted_at?: string | null;
  created_at?: string | null;
};

export type RevisionIssueComment = {
  id: string;
  revision_issue_id: string;
  revision_round_id: string;
  round_number: number;
  author_type: 'admin' | 'contractor';
  admin_recommended_remedy?: string | null;
  contractor_response_method?: string | null;
  comment_text?: string | null;
  contractor_asserted_value?: string | null;
  can_edit?: boolean;
};

export type RevisionSourceIdentity = {
  kind?: 'rule' | 'invoice_field' | 'supporting_document_field' | 'di_field';
  rule_key?: string | null;
  field_key?: string | null;
  invoice_upgrade_type_id?: string | null;
  supporting_document_type_key?: string | null;
};

export type RevisionIssue = {
  id: string;
  issue_type: 'rule' | 'invoice_field' | 'supporting_document_field' | 'di_field';
  status:
    | 'pending_admin_review'
    | 'open'
    | 'closed_no_contractor_action_required'
    | 'closed_via_corrected_documentation'
    | 'closed_via_attestation'
    | 'closed_via_exception'
    | 'closed_as_withdrawn';
  disposition_comment?: string | null;
  in_latest_round?: boolean;
  can_delete?: boolean;
  can_close?: boolean;
  can_admin_comment?: boolean;
  can_contractor_respond?: boolean;
  suggested_admin_comment?: {
    admin_recommended_remedy?: string | null;
    comment_text?: string | null;
  } | null;
  source_reference?: Record<string, string>;
  source_identity?: RevisionSourceIdentity;
  source: RevisionSource;
  comments: RevisionIssueComment[];
};

export type RevisionTrackerData = {
  invoice_id: string;
  invoice_status?: string | null;
  invoice_status_subtype?: string | null;
  latest_round_id?: string | null;
  rounds: RevisionRound[];
  issues: RevisionIssue[];
  suppressed_source_identities?: RevisionSourceIdentity[];
  capabilities?: {
    can_send_issues?: boolean;
    can_add_issue?: boolean;
    missing_admin_comment_issue_ids?: string[];
    can_submit_response?: boolean;
    incomplete_issue_ids?: string[];
    document_upload_required_issue_ids?: string[];
  };
};

type Props = {
  invoiceId: string;
  viewerRole: 'admin' | 'contractor';
  refreshToken?: number;
  onTrackerChange?: (data: RevisionTrackerData) => void;
  attentionIssueIds?: string[];
  onContractorDraftStateChange?: (state: ContractorDraftState) => void;
};

type AdminDraft = { remedy: string; text: string };
type ContractorDraft = { method: string; text: string; assertedValue: string };
type CloseDraft = { status: string; text: string };
type ContractorResponseState = {
  label: string;
  colorScheme: string;
};
type AdminIssueState = {
  label: string;
  colorScheme: string;
};

export type ContractorDraftState = {
  allEditableDraftsComplete: boolean;
  hasUnsavedChanges: boolean;
};

const ADMIN_REMEDIES = [
  ['correct_and_reupload_invoice', 'Correct and re-upload invoice'],
  ['upload_supporting_document', 'Upload supporting document'],
  ['provide_attestation', 'Provide attestation'],
  ['provide_explanation', 'Provide explanation'],
];
const CONTRACTOR_METHODS = [
  ['corrected_invoice_uploaded', 'Corrected invoice uploaded'],
  ['supporting_document_uploaded', 'Supporting document uploaded'],
  ['attestation_provided', 'Attestation provided'],
  ['explanation_provided', 'Explanation provided'],
  ['unable_to_resolve', 'Unable to resolve'],
];
const INTERNAL_CLOSE_STATUSES = [['closed_no_contractor_action_required', 'Confirmed - no contractor action required']];
const CONTRACTOR_CLOSE_STATUSES = [
  ['closed_via_corrected_documentation', 'Close: corrected documentation accepted'],
  ['closed_via_attestation', 'Close: attestation accepted'],
  ['closed_via_exception', 'Close: exception granted'],
  ['closed_as_withdrawn', 'Close: issue withdrawn'],
];

const pretty = (value: unknown): string =>
  String(value ?? '')
    .replaceAll('_', ' ')
    .replace(/^./, (letter) => letter.toUpperCase());

const sourceValue = (value: unknown): string => {
  if (value == null || value === '') return '';
  return typeof value === 'object' ? JSON.stringify(value) : String(value);
};

const issueStatusColour = (status: RevisionIssue['status']): string =>
  status === 'pending_admin_review'
    ? 'yellow'
    : status === 'open'
      ? 'orange'
      : status === 'closed_via_exception'
        ? 'purple'
        : 'green';

const issueStatusLabel = (status: RevisionIssue['status']): string => {
  if (status === 'pending_admin_review') return 'Awaiting admin decision';
  if (status === 'closed_no_contractor_action_required') return 'No contractor action required';
  return pretty(status);
};

const issueUnresolved = (issue: RevisionIssue): boolean => ['pending_admin_review', 'open'].includes(issue.status);

const contractorDraftComplete = (issue: RevisionIssue, draft: ContractorDraft): boolean => {
  if (!draft.method || !draft.text.trim()) return false;
  return !(draft.method === 'attestation_provided' && issue.issue_type !== 'rule' && !draft.assertedValue.trim());
};

const contractorDraftDiffers = (draft: ContractorDraft, saved: RevisionIssueComment | undefined): boolean =>
  draft.method !== (saved?.contractor_response_method || '') ||
  draft.text !== (saved?.comment_text || '') ||
  draft.assertedValue !== (saved?.contractor_asserted_value || '');

const adminDraftDiffers = (draft: AdminDraft, baseline: AdminDraft): boolean =>
  draft.remedy !== baseline.remedy || draft.text !== baseline.text;

const dispositionMismatchNotice = (status: string, response: RevisionIssueComment | undefined): string => {
  const responseLabel = response?.contractor_response_method
    ? pretty(response.contractor_response_method)
    : 'No contractor response is recorded';
  if (status === 'closed_via_attestation' && response?.contractor_response_method !== 'attestation_provided') {
    return `${responseLabel}. You selected attestation accepted; this will not prevent closing the issue.`;
  }
  if (
    status === 'closed_via_corrected_documentation' &&
    !['corrected_invoice_uploaded', 'supporting_document_uploaded'].includes(response?.contractor_response_method || '')
  ) {
    return `${responseLabel}. You selected corrected documentation accepted; this will not prevent closing the issue.`;
  }
  return '';
};

export const RevisionTracker = ({
  invoiceId,
  viewerRole,
  refreshToken = 0,
  onTrackerChange,
  attentionIssueIds = [],
  onContractorDraftStateChange,
}: Props) => {
  const toast = useToast();
  const [data, setData] = useState<RevisionTrackerData | null>(null);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [errorDetails, setErrorDetails] = useState<string[]>([]);
  const [adminDrafts, setAdminDrafts] = useState<Record<string, AdminDraft>>({});
  const [contractorDrafts, setContractorDrafts] = useState<Record<string, ContractorDraft>>({});
  const [closeDrafts, setCloseDrafts] = useState<Record<string, CloseDraft>>({});
  const [historyIssueId, setHistoryIssueId] = useState<string | null>(null);
  const [closeValidationOpen, setCloseValidationOpen] = useState(false);
  const closeValidationButtonRef = useRef<HTMLButtonElement>(null);

  const endpoint = `/api/claims/${viewerRole === 'admin' ? 'admin' : 'contractor'}/invoices/${encodeURIComponent(
    invoiceId,
  )}/revision_issues`;

  const adoptData = useCallback(
    (next: RevisionTrackerData) => {
      setData(next);
      setError('');
      setErrorDetails([]);
      const nextAdmin: Record<string, AdminDraft> = {};
      const nextContractor: Record<string, ContractorDraft> = {};
      next.issues.forEach((issue) => {
        const editableAdminComment = issue.comments.find(
          (comment) => comment.author_type === 'admin' && comment.can_edit,
        );
        if (editableAdminComment) {
          nextAdmin[issue.id] = {
            remedy: editableAdminComment.admin_recommended_remedy || '',
            text: editableAdminComment.comment_text || '',
          };
        } else if (issue.suggested_admin_comment) {
          nextAdmin[issue.id] = {
            remedy: issue.suggested_admin_comment.admin_recommended_remedy || '',
            text: issue.suggested_admin_comment.comment_text || '',
          };
        }
        issue.comments.forEach((comment) => {
          if (comment.author_type === 'contractor' && comment.revision_round_id === next.latest_round_id) {
            nextContractor[issue.id] = {
              method: comment.contractor_response_method || '',
              text: comment.comment_text || '',
              assertedValue: comment.contractor_asserted_value || '',
            };
          }
        });
      });
      setAdminDrafts(nextAdmin);
      setContractorDrafts(nextContractor);
      onTrackerChange?.(next);
    },
    [onTrackerChange],
  );

  const request = useCallback(
    async (url: string, init?: RequestInit) => {
      setBusy(true);
      try {
        const response = await fetch(url, {
          credentials: 'include',
          headers: { Accept: 'application/json', 'Content-Type': 'application/json', ...(init?.headers || {}) },
          ...init,
        });
        const json = await response.json().catch(() => ({}));
        if (!response.ok) {
          const details = json?.details || {};
          const ids = details.issue_ids || details.missing_issue_ids || [];
          const rules = details.missing_rules || details.rule_names || [];
          const decisions = Array.isArray(details.missing_decisions)
            ? details.missing_decisions.map((decision: any) => decision?.friendly_label || decision?.source_id)
            : [];
          const visibleDetails = decisions.length ? [...decisions, ...rules] : [...rules, ...ids];
          setErrorDetails(visibleDetails.filter(Boolean).map(String));
          throw new Error(json?.error || `Revision workflow request failed (${response.status}).`);
        }
        adoptData(json as RevisionTrackerData);
        return json as RevisionTrackerData;
      } finally {
        setBusy(false);
      }
    },
    [adoptData],
  );

  const load = useCallback(async () => {
    if (!invoiceId) return;
    setLoading(true);
    try {
      const response = await fetch(endpoint, { credentials: 'include', headers: { Accept: 'application/json' } });
      const json = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(json?.error || 'Could not load revision issues.');
      adoptData(json as RevisionTrackerData);
    } catch (reason: any) {
      setError(reason?.message || 'Could not load revision issues.');
    } finally {
      setLoading(false);
    }
  }, [adoptData, endpoint, invoiceId]);

  useEffect(() => {
    void load();
  }, [load, refreshToken]);

  const latestRound = data?.rounds.find((round) => round.id === data.latest_round_id) || data?.rounds[0];
  const currentRoundComment = useCallback(
    (issue: RevisionIssue, author: 'admin' | 'contractor') =>
      [...issue.comments]
        .reverse()
        .find((comment) => comment.revision_round_id === latestRound?.id && comment.author_type === author),
    [latestRound?.id],
  );

  useEffect(() => {
    if (viewerRole !== 'contractor' || !data || !onContractorDraftStateChange) return;

    const editableIssues = data.issues.filter((issue) => issue.can_contractor_respond);
    const allEditableDraftsComplete = editableIssues.every((issue) => {
      const draft = contractorDrafts[issue.id] || { method: '', text: '', assertedValue: '' };
      return contractorDraftComplete(issue, draft);
    });
    const hasUnsavedChanges = editableIssues.some((issue) => {
      const draft = contractorDrafts[issue.id] || { method: '', text: '', assertedValue: '' };
      const saved = currentRoundComment(issue, 'contractor');
      return contractorDraftDiffers(draft, saved);
    });

    onContractorDraftStateChange({ allEditableDraftsComplete, hasUnsavedChanges });
  }, [contractorDrafts, currentRoundComment, data, onContractorDraftStateChange, viewerRole]);
  const mutate = async (url: string, method: string, body?: Record<string, unknown>) => {
    try {
      await request(url, { method, body: body ? JSON.stringify(body) : undefined });
    } catch (reason: any) {
      const message = reason?.message || 'Please try again.';
      setError(message);
      toast({ title: 'Revision tracker could not save', description: message, status: 'error', duration: 6000 });
    }
  };

  const sendIssues = () =>
    mutate(`/api/claims/admin/invoices/${encodeURIComponent(invoiceId)}/revision_issues/send`, 'POST');

  const saveAdmin = (issue: RevisionIssue, comment?: RevisionIssueComment) => {
    const draft = adminDrafts[issue.id];
    if (!draft?.remedy || !draft.text.trim()) {
      setError('Choose a recommended remedy and enter the contractor-facing comment.');
      return;
    }
    const base = `/api/claims/admin/invoices/${encodeURIComponent(invoiceId)}`;
    const url = comment
      ? `${base}/revision_issue_comments/${encodeURIComponent(comment.id)}`
      : `${base}/revision_issues/${encodeURIComponent(issue.id)}/comment`;
    void mutate(url, comment ? 'PATCH' : 'POST', {
      admin_recommended_remedy: draft.remedy,
      comment_text: draft.text.trim(),
    });
  };

  const saveContractor = async (issue: RevisionIssue) => {
    const draft = contractorDrafts[issue.id] || { method: '', text: '', assertedValue: '' };
    if (!draft.method || !draft.text.trim()) {
      setError('Choose how you responded and enter a response comment.');
      return;
    }
    if (draft.method === 'attestation_provided' && issue.issue_type !== 'rule' && !draft.assertedValue.trim()) {
      setError(`Enter the asserted value for ${issue.source.friendly_label || 'this field'}.`);
      return;
    }
    try {
      await request(`${endpoint}/${encodeURIComponent(issue.id)}/comment`, {
        method: 'PATCH',
        body: JSON.stringify({
          contractor_response_method: draft.method,
          comment_text: draft.text.trim(),
          contractor_asserted_value: draft.assertedValue.trim() || null,
        }),
      });
    } catch (reason: any) {
      setError(reason?.message || 'Could not save the contractor response.');
    }
  };

  const closeIssue = (issue: RevisionIssue) => {
    const draft = closeDrafts[issue.id] || { status: '', text: '' };
    if (!draft.status || !draft.text.trim()) {
      setError('');
      setErrorDetails([]);
      setCloseValidationOpen(true);
      return;
    }
    void mutate(
      `/api/claims/admin/invoices/${encodeURIComponent(invoiceId)}/revision_issues/${encodeURIComponent(
        issue.id,
      )}/close`,
      'POST',
      { status: draft.status, disposition_comment: draft.text.trim() },
    );
  };

  if (loading) {
    return (
      <Flex minH="180px" align="center" justify="center">
        <Spinner />
      </Flex>
    );
  }

  const isAdmin = viewerRole === 'admin';
  const sendTitle = data?.capabilities?.can_send_issues
    ? ''
    : 'Add or save an admin recommendation for every unresolved issue before sending.';
  const historyIssue = data?.issues.find((issue) => issue.id === historyIssueId);
  const contractorInvoiceWithProgram =
    !isAdmin && data?.invoice_status === 'admin_review_inbox' && latestRound?.state === 'response_submitted';
  const adminInvoiceWithContractor =
    isAdmin && data?.invoice_status === 'contractor_revision_inbox' && latestRound?.state === 'awaiting_contractor';
  const contractorResponseStateFor = (issue: RevisionIssue): ContractorResponseState | null => {
    if (isAdmin || issue.status !== 'open' || data?.invoice_status !== 'contractor_revision_inbox') return null;

    const draft = contractorDrafts[issue.id] || { method: '', text: '', assertedValue: '' };
    const saved = currentRoundComment(issue, 'contractor');
    if (contractorDraftDiffers(draft, saved)) {
      return { label: 'Unsaved changes', colorScheme: 'yellow' };
    }
    if (data?.capabilities?.document_upload_required_issue_ids?.includes(issue.id)) {
      return { label: 'Document upload required', colorScheme: 'red' };
    }
    if (saved && contractorDraftComplete(issue, draft)) {
      return { label: 'Response saved - submit invoice', colorScheme: 'blue' };
    }
    return { label: 'Action required', colorScheme: 'orange' };
  };
  const adminIssueStateFor = (issue: RevisionIssue): AdminIssueState | null => {
    if (!isAdmin || !issueUnresolved(issue) || data?.invoice_status !== 'admin_review_inbox') return null;

    const currentAdminComment = currentRoundComment(issue, 'admin');
    const editableAdminComment = currentAdminComment?.can_edit ? currentAdminComment : undefined;
    const baseline = editableAdminComment
      ? {
          remedy: editableAdminComment.admin_recommended_remedy || '',
          text: editableAdminComment.comment_text || '',
        }
      : {
          remedy: issue.suggested_admin_comment?.admin_recommended_remedy || '',
          text: issue.suggested_admin_comment?.comment_text || '',
        };
    const draft = adminDrafts[issue.id] || baseline;
    if (adminDraftDiffers(draft, baseline)) {
      return { label: 'Unsaved changes', colorScheme: 'yellow' };
    }
    if (editableAdminComment && draft.remedy && draft.text.trim()) {
      return { label: 'Ready to send', colorScheme: 'blue' };
    }
    return { label: 'Recommendation required', colorScheme: 'orange' };
  };
  return (
    <>
      <Box bg="blue.50" borderWidth="1px" borderColor="blue.200" borderRadius="md" p="12px">
        <Flex align="center" justify="space-between" gap="8px" mb="10px" wrap="wrap">
          <Text fontWeight="700">Revision issues</Text>
          {isAdmin ? (
            <Flex gap="6px">
              <Button
                size="xs"
                colorScheme="blue"
                leftIcon={<PaperPlaneTilt size={15} />}
                isDisabled={!data?.capabilities?.can_send_issues || busy}
                title={sendTitle}
                onClick={() => void sendIssues()}
              >
                Send to contractor
              </Button>
            </Flex>
          ) : null}
        </Flex>

        {error ? (
          <Box bg="red.50" borderWidth="1px" borderColor="red.200" borderRadius="md" p="8px" mb="10px">
            <Text color="red.700" fontSize="sm" fontWeight="600">
              {error}
            </Text>
            {errorDetails.map((detail) => (
              <Text key={detail} color="red.700" fontSize="xs">
                • {detail}
              </Text>
            ))}
          </Box>
        ) : null}

        {contractorInvoiceWithProgram ? (
          <Box bg="blue.100" borderWidth="1px" borderColor="blue.200" borderRadius="md" p="8px" mb="10px">
            <Text color="blue.800" fontSize="sm" fontWeight="600">
              Responses submitted - the invoice is with the program team.
            </Text>
            <Text color="blue.800" fontSize="xs">
              Revision responses are read-only while the program team reviews the invoice.
            </Text>
          </Box>
        ) : null}

        {adminInvoiceWithContractor ? (
          <Box bg="orange.50" borderWidth="1px" borderColor="orange.200" borderRadius="md" p="8px" mb="10px">
            <Text color="orange.800" fontSize="sm" fontWeight="600">
              Revision issues are with the contractor.
            </Text>
            <Text color="orange.800" fontSize="xs">
              Admin controls are read-only until the contractor returns the invoice.
            </Text>
          </Box>
        ) : null}

        {!data?.issues.length ? (
          <Text fontSize="sm" color="gray.600" py="12px">
            {isAdmin
              ? 'No revision issues yet. Use the plus icon beside a rule or field in the review panel.'
              : 'No revision issues have been sent to you.'}
          </Text>
        ) : (
          <Accordion allowMultiple defaultIndex={[]}>
            {data.issues.map((issue) => {
              const adminComment = currentRoundComment(issue, 'admin');
              const contractorComment = currentRoundComment(issue, 'contractor');
              const editableComment = isAdmin ? adminComment : contractorComment;
              const visibleComments = editableComment?.can_edit
                ? issue.comments.filter((comment) => comment.id !== editableComment.id)
                : issue.comments;
              const contractorDraft = contractorDrafts[issue.id] || { method: '', text: '', assertedValue: '' };
              const contractorResponseState = contractorResponseStateFor(issue);
              const adminIssueState = adminIssueStateFor(issue);
              const latestContractorResponse = [...issue.comments]
                .reverse()
                .find((comment) => comment.author_type === 'contractor');
              const dispositionNotice = dispositionMismatchNotice(
                closeDrafts[issue.id]?.status || '',
                latestContractorResponse,
              );
              const highlighted = attentionIssueIds.includes(issue.id);
              return (
                <AccordionItem
                  key={issue.id}
                  border="1px solid"
                  borderColor={highlighted ? 'red.400' : 'gray.200'}
                  borderRadius="md"
                  bg="white"
                  mb="8px"
                >
                  <Flex align="center">
                    <AccordionButton px="10px" py="8px" flex="1">
                      <Box flex="1" textAlign="left">
                        <Flex align="center" gap="7px" wrap="wrap">
                          <Text fontWeight="700" color={issueUnresolved(issue) ? 'blue.700' : 'gray.600'}>
                            {issue.source.friendly_label || pretty(issue.issue_type)}
                          </Text>
                          <Badge colorScheme={issueStatusColour(issue.status)}>{issueStatusLabel(issue.status)}</Badge>
                          {contractorResponseState ? (
                            <Badge colorScheme={contractorResponseState.colorScheme}>
                              {contractorResponseState.label}
                            </Badge>
                          ) : null}
                          {adminIssueState ? (
                            <Badge colorScheme={adminIssueState.colorScheme}>{adminIssueState.label}</Badge>
                          ) : null}
                        </Flex>
                      </Box>
                      <AccordionIcon />
                    </AccordionButton>
                    <IconButton
                      aria-label="View issue history"
                      icon={<Info size={18} />}
                      size="xs"
                      variant="ghost"
                      mr="6px"
                      title="View issue history and exchange audit"
                      onClick={() => setHistoryIssueId(issue.id)}
                    />
                  </Flex>
                  <AccordionPanel px="10px" pt="2px" pb="12px">
                    {sourceValue(issue.source.value) ? (
                      <Text fontSize="sm" mb="8px">
                        <Text as="span" fontWeight="600">
                          Document value:{' '}
                        </Text>
                        {sourceValue(issue.source.value)}
                      </Text>
                    ) : null}

                    {visibleComments.length ? (
                      <Box borderLeftWidth="2px" borderColor="gray.200" pl="10px" mb="10px">
                        {visibleComments.map((comment) => (
                          <Box key={comment.id} mb="9px">
                            <Flex gap="6px" align="center" mb="2px">
                              <Badge colorScheme={comment.author_type === 'admin' ? 'blue' : 'green'}>
                                {comment.author_type === 'admin' ? 'Admin' : 'Contractor'}
                              </Badge>
                              {comment.admin_recommended_remedy ? (
                                <Text fontSize="xs" fontWeight="600">
                                  {pretty(comment.admin_recommended_remedy)}
                                </Text>
                              ) : null}
                              {comment.contractor_response_method ? (
                                <Text fontSize="xs" fontWeight="600">
                                  {pretty(comment.contractor_response_method)}
                                </Text>
                              ) : null}
                            </Flex>
                            <Text fontSize="sm" whiteSpace="pre-wrap">
                              {comment.comment_text}
                            </Text>
                            {comment.contractor_asserted_value ? (
                              <Text fontSize="sm">
                                <Text as="span" fontWeight="600">
                                  Asserted value:{' '}
                                </Text>
                                {comment.contractor_asserted_value}
                              </Text>
                            ) : null}
                          </Box>
                        ))}
                      </Box>
                    ) : null}

                    {issue.disposition_comment ? (
                      <Box bg="green.50" borderWidth="1px" borderColor="green.200" borderRadius="md" p="9px" mb="10px">
                        <Flex align="center" gap="6px" mb="3px" wrap="wrap">
                          <Badge colorScheme="green">Final disposition</Badge>
                          <Text fontSize="xs" fontWeight="600">
                            {issueStatusLabel(issue.status)}
                          </Text>
                        </Flex>
                        <Text fontSize="sm" whiteSpace="pre-wrap">
                          {issue.disposition_comment}
                        </Text>
                      </Box>
                    ) : null}

                    {isAdmin && issue.can_admin_comment ? (
                      <Box bg="gray.50" borderRadius="md" p="9px" mb="10px">
                        <Text fontSize="xs" fontWeight="700" mb="7px">
                          Continue issue
                        </Text>
                        <FormControl mb="7px">
                          <Flex align="center" gap="8px">
                            <FormLabel fontSize="xs" mb="0" whiteSpace="nowrap">
                              Recommended fix
                            </FormLabel>
                            <Select
                              size="sm"
                              flex="1"
                              value={adminDrafts[issue.id]?.remedy || ''}
                              onChange={(event) =>
                                setAdminDrafts((current) => ({
                                  ...current,
                                  [issue.id]: {
                                    ...(current[issue.id] || { text: '' }),
                                    remedy: event.target.value,
                                  },
                                }))
                              }
                            >
                              <option value="">Select a recommendation</option>
                              {ADMIN_REMEDIES.map(([value, label]) => (
                                <option key={value} value={value}>
                                  {label}
                                </option>
                              ))}
                            </Select>
                          </Flex>
                        </FormControl>
                        <Textarea
                          minH="125px"
                          size="sm"
                          placeholder={adminComment?.can_edit ? undefined : 'Enter the next contractor-facing comment'}
                          value={adminDrafts[issue.id]?.text || ''}
                          onChange={(event) =>
                            setAdminDrafts((current) => ({
                              ...current,
                              [issue.id]: {
                                ...(current[issue.id] || { remedy: '' }),
                                text: event.target.value,
                              },
                            }))
                          }
                        />
                        <Flex gap="6px" mt="7px">
                          <IconButton
                            aria-label="Save recommendation"
                            icon={<FloppyDiskBack size={18} />}
                            size="sm"
                            title="Save recommendation"
                            onClick={() => saveAdmin(issue, adminComment?.can_edit ? adminComment : undefined)}
                          />
                          <IconButton
                            aria-label="Reset recommendation draft"
                            icon={<ArrowCounterClockwise size={18} />}
                            size="sm"
                            variant="outline"
                            title="Reset from the rule or field evidence"
                            onClick={() => {
                              if (adminComment?.can_edit) {
                                void mutate(
                                  `/api/claims/admin/invoices/${encodeURIComponent(
                                    invoiceId,
                                  )}/revision_issue_comments/${encodeURIComponent(adminComment.id)}/reset`,
                                  'POST',
                                );
                              } else {
                                setAdminDrafts((current) => ({
                                  ...current,
                                  [issue.id]: {
                                    remedy: issue.suggested_admin_comment?.admin_recommended_remedy || '',
                                    text: issue.suggested_admin_comment?.comment_text || '',
                                  },
                                }));
                              }
                            }}
                          />
                          {issue.can_delete ? (
                            <IconButton
                              aria-label="Delete new unsent issue"
                              icon={<Trash size={18} />}
                              size="sm"
                              variant="outline"
                              title="Delete this new issue before it is sent"
                              onClick={() =>
                                void mutate(
                                  `/api/claims/admin/invoices/${encodeURIComponent(
                                    invoiceId,
                                  )}/revision_issues/${encodeURIComponent(issue.id)}`,
                                  'DELETE',
                                )
                              }
                            />
                          ) : null}
                        </Flex>
                      </Box>
                    ) : null}

                    {!isAdmin && issue.can_contractor_respond ? (
                      <Box bg="green.50" borderRadius="md" p="9px" mb="10px">
                        <FormControl mb="7px">
                          <FormLabel fontSize="xs" mb="2px">
                            How did you respond?
                          </FormLabel>
                          <Select
                            size="sm"
                            value={contractorDraft.method}
                            onChange={(event) =>
                              setContractorDrafts((current) => ({
                                ...current,
                                [issue.id]: { ...contractorDraft, method: event.target.value },
                              }))
                            }
                          >
                            <option value="">Select a response</option>
                            {CONTRACTOR_METHODS.map(([value, label]) => (
                              <option key={value} value={value}>
                                {label}
                              </option>
                            ))}
                          </Select>
                        </FormControl>
                        {contractorDraft.method === 'attestation_provided' && issue.issue_type !== 'rule' ? (
                          <FormControl mb="7px">
                            <FormLabel fontSize="xs" mb="2px">
                              Correct value for {issue.source.friendly_label || 'this field'}
                            </FormLabel>
                            <Textarea
                              minH="60px"
                              size="sm"
                              value={contractorDraft.assertedValue}
                              onChange={(event) =>
                                setContractorDrafts((current) => ({
                                  ...current,
                                  [issue.id]: { ...contractorDraft, assertedValue: event.target.value },
                                }))
                              }
                            />
                          </FormControl>
                        ) : null}
                        <FormControl>
                          <FormLabel fontSize="xs" mb="2px">
                            Your response
                          </FormLabel>
                          <Textarea
                            minH="125px"
                            size="sm"
                            value={contractorDraft.text}
                            onChange={(event) =>
                              setContractorDrafts((current) => ({
                                ...current,
                                [issue.id]: { ...contractorDraft, text: event.target.value },
                              }))
                            }
                          />
                        </FormControl>
                        <IconButton
                          aria-label="Save response"
                          icon={<FloppyDiskBack size={18} />}
                          mt="7px"
                          size="sm"
                          title="Save this response"
                          onClick={() => void saveContractor(issue)}
                        />
                      </Box>
                    ) : null}

                    {isAdmin && issue.can_close ? (
                      <Box bg="purple.50" borderRadius="md" p="9px">
                        <Text fontSize="xs" fontWeight="700" mb="7px">
                          Close issue
                        </Text>
                        <FormControl mb="7px">
                          <Flex align="center" gap="8px">
                            <FormLabel fontSize="xs" mb="0" whiteSpace="nowrap">
                              Final disposition
                            </FormLabel>
                            <Select
                              size="sm"
                              flex="1"
                              value={closeDrafts[issue.id]?.status || ''}
                              onChange={(event) =>
                                setCloseDrafts((current) => ({
                                  ...current,
                                  [issue.id]: { ...(current[issue.id] || { text: '' }), status: event.target.value },
                                }))
                              }
                            >
                              <option value="" disabled>
                                Select closing outcome
                              </option>
                              {(issue.status === 'pending_admin_review'
                                ? INTERNAL_CLOSE_STATUSES
                                : CONTRACTOR_CLOSE_STATUSES
                              ).map(([value, label]) => (
                                <option key={value} value={value}>
                                  {label}
                                </option>
                              ))}
                            </Select>
                          </Flex>
                        </FormControl>
                        {dispositionNotice ? (
                          <Box
                            bg="yellow.50"
                            borderWidth="1px"
                            borderColor="yellow.200"
                            borderRadius="md"
                            p="7px"
                            mb="7px"
                          >
                            <Text color="yellow.900" fontSize="xs">
                              {dispositionNotice}
                            </Text>
                          </Box>
                        ) : null}
                        <Textarea
                          minH="85px"
                          size="sm"
                          placeholder="Required disposition comment"
                          value={closeDrafts[issue.id]?.text || ''}
                          onChange={(event) =>
                            setCloseDrafts((current) => ({
                              ...current,
                              [issue.id]: { ...(current[issue.id] || { status: '' }), text: event.target.value },
                            }))
                          }
                        />
                        <Button
                          size="xs"
                          mt="7px"
                          leftIcon={<CheckCircle size={16} />}
                          onClick={() => closeIssue(issue)}
                        >
                          Close issue
                        </Button>
                      </Box>
                    ) : null}
                  </AccordionPanel>
                </AccordionItem>
              );
            })}
          </Accordion>
        )}
      </Box>
      <AlertDialog
        isOpen={closeValidationOpen}
        leastDestructiveRef={closeValidationButtonRef}
        onClose={() => setCloseValidationOpen(false)}
        isCentered
      >
        <AlertDialogOverlay>
          <AlertDialogContent>
            <AlertDialogHeader fontSize="lg" fontWeight="700">
              Cannot close issue
            </AlertDialogHeader>
            <AlertDialogBody>Choose how the issue was closed and enter a disposition comment.</AlertDialogBody>
            <AlertDialogFooter>
              <Button ref={closeValidationButtonRef} onClick={() => setCloseValidationOpen(false)}>
                OK
              </Button>
            </AlertDialogFooter>
          </AlertDialogContent>
        </AlertDialogOverlay>
      </AlertDialog>
      <Drawer isOpen={!!historyIssue} placement="right" size="md" onClose={() => setHistoryIssueId(null)}>
        <DrawerOverlay />
        <DrawerContent>
          <DrawerCloseButton />
          <DrawerHeader>{historyIssue?.source.friendly_label || 'Revision issue history'}</DrawerHeader>
          <DrawerBody>
            {historyIssue?.comments.map((comment) => {
              const round = data?.rounds.find((candidate) => candidate.id === comment.revision_round_id);
              return (
                <Box key={comment.id} borderBottomWidth="1px" borderColor="gray.200" py="10px">
                  <Flex align="center" gap="6px" mb="4px" wrap="wrap">
                    <Badge colorScheme={comment.author_type === 'admin' ? 'blue' : 'green'}>
                      {comment.author_type === 'admin' ? 'Admin' : 'Contractor'}
                    </Badge>
                    <Text fontSize="xs" color="gray.600">
                      Exchange {comment.round_number}
                      {round?.invoice_versionno ? ` - invoice version ${round.invoice_versionno}` : ''}
                    </Text>
                  </Flex>
                  {comment.admin_recommended_remedy ? (
                    <Text fontSize="xs" fontWeight="600">
                      {pretty(comment.admin_recommended_remedy)}
                    </Text>
                  ) : null}
                  {comment.contractor_response_method ? (
                    <Text fontSize="xs" fontWeight="600">
                      {pretty(comment.contractor_response_method)}
                    </Text>
                  ) : null}
                  <Text fontSize="sm" whiteSpace="pre-wrap">
                    {comment.comment_text}
                  </Text>
                </Box>
              );
            })}
            {historyIssue?.disposition_comment ? (
              <Box borderBottomWidth="1px" borderColor="gray.200" py="10px">
                <Flex align="center" gap="6px" mb="4px" wrap="wrap">
                  <Badge colorScheme="green">Final disposition</Badge>
                  <Text fontSize="xs" fontWeight="600">
                    {issueStatusLabel(historyIssue.status)}
                  </Text>
                </Flex>
                <Text fontSize="sm" whiteSpace="pre-wrap">
                  {historyIssue.disposition_comment}
                </Text>
              </Box>
            ) : null}
          </DrawerBody>
        </DrawerContent>
      </Drawer>
    </>
  );
};
