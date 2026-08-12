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
import {
  ArrowCounterClockwise,
  CaretDown,
  CaretRight,
  CheckCircle,
  FloppyDiskBack,
  PaperPlaneTilt,
  Trash,
} from '@phosphor-icons/react';
import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { RevisionIssue, RevisionIssueComment, RevisionSourceIdentity, RevisionTrackerData } from './revision-tracker';

type AdminDraft = { remedy: string; text: string };
type CloseDraft = { status: string; text: string };

const EMPTY_ADMIN_DRAFT: AdminDraft = { remedy: '', text: '' };
const EMPTY_CLOSE_DRAFT: CloseDraft = { status: '', text: '' };

const ADMIN_REMEDIES = [
  ['correct_and_reupload_invoice', 'Correct and re-upload invoice'],
  ['upload_supporting_document', 'Upload supporting document'],
  ['provide_attestation', 'Provide attestation'],
  ['provide_explanation', 'Provide explanation'],
];

const CONTRACTOR_RESPONSE_METHODS = [
  ['corrected_invoice_uploaded', 'Corrected invoice uploaded'],
  ['supporting_document_uploaded', 'Supporting document uploaded'],
  ['attestation_provided', 'Attestation provided'],
  ['explanation_provided', 'Explanation provided'],
  ['unable_to_resolve', 'Unable to resolve'],
];

const INTERNAL_CLOSE_STATUSES = [['closed_no_contractor_action_required', 'Confirmed - no contractor action required']];
const CONTRACTOR_CLOSE_STATUSES = [
  ['closed_via_corrected_documentation', 'Corrected documentation accepted'],
  ['closed_via_attestation', 'Attestation accepted'],
  ['closed_via_exception', 'Exception granted'],
  ['closed_as_withdrawn', 'Issue withdrawn'],
];

const dispositionStatusLabel = (status: RevisionIssue['status']): string =>
  [...INTERNAL_CLOSE_STATUSES, ...CONTRACTOR_CLOSE_STATUSES].find(([value]) => value === status)?.[1] || pretty(status);

const adminRemedyLabel = (remedy?: string | null): string =>
  ADMIN_REMEDIES.find(([value]) => value === remedy)?.[1] || (remedy ? pretty(remedy) : '');

const pretty = (value: unknown): string =>
  String(value ?? '')
    .replace(/_/g, ' ')
    .replace(/^./, (letter) => letter.toUpperCase());

const sourceValue = (value: unknown): string => {
  if (value == null || value === '') return '';
  return typeof value === 'object' ? JSON.stringify(value) : String(value);
};

export const revisionIssueUnresolved = (issue: RevisionIssue): boolean =>
  issue.status === 'pending_admin_review' || issue.status === 'open';

const formatSentDate = (value?: string | null): string => {
  if (!value) return '';
  const date = new Date(value);
  return Number.isNaN(date.valueOf()) ? '' : date.toLocaleDateString();
};

const formatCommentDateTime = (value?: string | null): string => {
  if (!value) return 'Date unavailable';
  const date = new Date(value);
  if (Number.isNaN(date.valueOf())) return 'Date unavailable';

  return date.toLocaleString('en-CA', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  });
};

const commentChoice = (comment: RevisionIssueComment): { label: string; value: string } | null => {
  if (comment.author_type === 'admin' && comment.admin_recommended_remedy) {
    return {
      label: 'Requested response',
      value: adminRemedyLabel(comment.admin_recommended_remedy),
    };
  }

  if (comment.author_type === 'contractor' && comment.contractor_response_method) {
    return {
      label: 'Response method',
      value:
        CONTRACTOR_RESPONSE_METHODS.find(([value]) => value === comment.contractor_response_method)?.[1] ||
        pretty(comment.contractor_response_method),
    };
  }

  return null;
};

const currentAdminComment = (
  issue: RevisionIssue,
  data: RevisionTrackerData | null,
): RevisionIssueComment | undefined =>
  [...issue.comments]
    .reverse()
    .find((comment) => comment.author_type === 'admin' && comment.revision_round_id === data?.latest_round_id);

const latestRoundAwaitingContractor = (data: RevisionTrackerData | null): boolean =>
  data?.rounds.find((round) => round.id === data.latest_round_id)?.state === 'awaiting_contractor';

const draftBaseline = (issue: RevisionIssue, data: RevisionTrackerData | null): AdminDraft => {
  const editable = currentAdminComment(issue, data);
  if (editable?.can_edit) {
    return {
      remedy: editable.admin_recommended_remedy || '',
      text: editable.comment_text || '',
    };
  }
  return {
    remedy: issue.suggested_admin_comment?.admin_recommended_remedy || '',
    text: issue.suggested_admin_comment?.comment_text || '',
  };
};

const draftDiffers = (draft: AdminDraft, baseline: AdminDraft): boolean =>
  draft.remedy !== baseline.remedy || draft.text !== baseline.text;

export const revisionSourceIdentityKey = (identity?: RevisionSourceIdentity | null): string => {
  if (!identity?.kind) return '';
  if (identity.kind === 'rule') {
    return ['rule', identity.rule_key || '', identity.invoice_upgrade_type_id || ''].join('|');
  }
  if (identity.kind === 'invoice_field') {
    return ['invoice_field', identity.field_key || '', identity.invoice_upgrade_type_id || ''].join('|');
  }
  if (identity.kind === 'supporting_document_field') {
    return ['supporting_document_field', identity.supporting_document_type_key || '', identity.field_key || ''].join(
      '|',
    );
  }
  return ['di_field', identity.field_key || ''].join('|');
};

export const rulecheckRevisionIdentityKey = (row: any): string =>
  revisionSourceIdentityKey({
    kind: 'rule',
    rule_key: String(row?.rule_key || ''),
    invoice_upgrade_type_id: String(row?.invoice_upgrade_type_id || ''),
  });

export const invoiceFieldRevisionIdentityKey = (row: any): string =>
  revisionSourceIdentityKey({
    kind: 'invoice_field',
    field_key: String(row?.field_key || ''),
    invoice_upgrade_type_id: String(row?.invoice_upgrade_type_id || ''),
  });

export const supportingFieldRevisionIdentityKey = (documentTypeKey: unknown, fieldKey: unknown): string =>
  revisionSourceIdentityKey({
    kind: 'supporting_document_field',
    supporting_document_type_key: String(documentTypeKey || ''),
    field_key: String(fieldKey || ''),
  });

export const diFieldRevisionIdentityKey = (fieldKey: unknown): string =>
  revisionSourceIdentityKey({ kind: 'di_field', field_key: String(fieldKey || '') });

export type AdminInlineRevisionWorkspace = {
  data: RevisionTrackerData | null;
  issues: RevisionIssue[];
  loading: boolean;
  busy: boolean;
  error: string;
  errorDetails: string[];
  expandedIssueIds: Set<string>;
  unsavedIssueIds: string[];
  sendConfirmationOpen: boolean;
  adoptData: (next: RevisionTrackerData, resetIssueId?: string) => void;
  draftFor: (issue: RevisionIssue) => AdminDraft;
  closeDraftFor: (issue: RevisionIssue) => CloseDraft;
  setDraft: (issueId: string, patch: Partial<AdminDraft>) => void;
  setCloseDraft: (issueId: string, patch: Partial<CloseDraft>) => void;
  toggleIssue: (issueId: string) => void;
  focusIssue: (issueId: string) => void;
  focusSource: (issueId: string) => void;
  saveIssue: (issue: RevisionIssue) => Promise<boolean>;
  resetIssue: (issue: RevisionIssue) => Promise<void>;
  deleteIssue: (issue: RevisionIssue) => Promise<void>;
  closeIssue: (issue: RevisionIssue) => Promise<boolean>;
  requestSend: () => void;
  confirmSend: () => Promise<void>;
  cancelSend: () => void;
};

const revisionIssueElementId = (issueId: string): string => `admin-revision-issue-${issueId}`;

const revealTarget = (target: HTMLElement | null) => {
  if (!target) return;
  const ancestorIds: string[] = [];
  let ancestor = target.parentElement;
  while (ancestor) {
    if (ancestor.id) ancestorIds.push(ancestor.id);
    ancestor = ancestor.parentElement;
  }
  const accordionButtons = Array.from(
    document.querySelectorAll<HTMLButtonElement>('button[aria-controls][aria-expanded="false"]'),
  );
  ancestorIds.reverse().forEach((ancestorId) => {
    accordionButtons.find((button) => button.getAttribute('aria-controls') === ancestorId)?.click();
  });
  requestAnimationFrame(() => {
    requestAnimationFrame(() => {
      target.scrollIntoView({ behavior: 'smooth', block: 'center' });
      target.focus({ preventScroll: true });
    });
  });
};

const revealElement = (elementId: string) => revealTarget(document.getElementById(elementId));

const revealRevisionSource = (issueId: string) =>
  revealTarget(document.querySelector<HTMLElement>(`[data-admin-revision-source-issue-id="${issueId}"]`));

export const AdminRevisionSourceAnchor = ({ issueId }: { issueId: string }) => (
  <Box data-admin-revision-source-issue-id={issueId} tabIndex={-1} h={0} gridColumn="1 / -1" scrollMarginTop="16px" />
);

type WorkspaceArgs = {
  invoiceId: string;
  enabled?: boolean;
  onTrackerChange?: (data: RevisionTrackerData) => void;
};

export const useAdminInlineRevisionWorkspace = ({
  invoiceId,
  enabled = true,
  onTrackerChange,
}: WorkspaceArgs): AdminInlineRevisionWorkspace => {
  const toast = useToast();
  const [data, setData] = useState<RevisionTrackerData | null>(null);
  const dataRef = useRef<RevisionTrackerData | null>(null);
  const [drafts, setDrafts] = useState<Record<string, AdminDraft>>({});
  const [closeDrafts, setCloseDrafts] = useState<Record<string, CloseDraft>>({});
  const [expandedIssueIds, setExpandedIssueIds] = useState<Set<string>>(() => new Set());
  const [loading, setLoading] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [errorDetails, setErrorDetails] = useState<string[]>([]);
  const [sendConfirmationOpen, setSendConfirmationOpen] = useState(false);
  const endpoint = `/api/claims/admin/invoices/${encodeURIComponent(invoiceId)}/revision_issues`;

  const adoptData = useCallback(
    (next: RevisionTrackerData, resetIssueId?: string) => {
      const previous = dataRef.current;
      setDrafts((current) => {
        const replacement: Record<string, AdminDraft> = {};
        next.issues.forEach((issue) => {
          const nextBaseline = draftBaseline(issue, next);
          const priorIssue = previous?.issues.find((candidate) => candidate.id === issue.id);
          const priorBaseline = priorIssue ? draftBaseline(priorIssue, previous) : undefined;
          const currentDraft = current[issue.id];
          const preserve =
            issue.id !== resetIssueId && currentDraft && priorBaseline && draftDiffers(currentDraft, priorBaseline);
          replacement[issue.id] = preserve ? currentDraft : nextBaseline;
        });
        return replacement;
      });
      dataRef.current = next;
      setData(next);
      setError('');
      setErrorDetails([]);
      onTrackerChange?.(next);
    },
    [onTrackerChange],
  );

  const request = useCallback(
    async (url: string, init?: RequestInit, resetIssueId?: string): Promise<RevisionTrackerData> => {
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
          const decisions = Array.isArray(details.missing_decisions)
            ? details.missing_decisions.map((decision: any) => decision?.friendly_label || decision?.source_id)
            : [];
          const ids = details.issue_ids || details.missing_issue_ids || [];
          setErrorDetails([...decisions, ...ids].filter(Boolean).map(String));
          const failure: any = new Error(json?.error || `Revision workflow request failed (${response.status}).`);
          failure.details = details;
          throw failure;
        }
        adoptData(json as RevisionTrackerData, resetIssueId);
        return json as RevisionTrackerData;
      } finally {
        setBusy(false);
      }
    },
    [adoptData],
  );

  useEffect(() => {
    setData(null);
    dataRef.current = null;
    setDrafts({});
    setCloseDrafts({});
    setExpandedIssueIds(new Set());
    if (!enabled || !invoiceId) return;

    let cancelled = false;
    const load = async () => {
      setLoading(true);
      try {
        const response = await fetch(endpoint, {
          credentials: 'include',
          headers: { Accept: 'application/json' },
        });
        let json = await response.json().catch(() => ({}));
        if (!response.ok) throw new Error(json?.error || 'Could not load revision issues.');
        if (json?.invoice_status === 'admin_review_inbox') {
          const ensureResponse = await fetch(`${endpoint}/ensure_managed`, {
            method: 'POST',
            credentials: 'include',
            headers: { Accept: 'application/json', 'Content-Type': 'application/json' },
          });
          const ensured = await ensureResponse.json().catch(() => ({}));
          if (!ensureResponse.ok) throw new Error(ensured?.error || 'Could not ensure required rule issues.');
          json = ensured;
        }
        if (!cancelled) adoptData(json as RevisionTrackerData);
      } catch (reason: any) {
        if (!cancelled) setError(reason?.message || 'Could not load revision issues.');
      } finally {
        if (!cancelled) setLoading(false);
      }
    };
    void load();
    return () => {
      cancelled = true;
    };
  }, [adoptData, enabled, endpoint, invoiceId]);

  const issues = useMemo(() => data?.issues || [], [data?.issues]);
  const draftFor = useCallback(
    (issue: RevisionIssue) => drafts[issue.id] || draftBaseline(issue, data),
    [data, drafts],
  );
  const closeDraftFor = useCallback(
    (issue: RevisionIssue) => closeDrafts[issue.id] || EMPTY_CLOSE_DRAFT,
    [closeDrafts],
  );
  const unsavedIssueIds = useMemo(
    () =>
      issues
        .filter((issue) => issue.can_admin_comment && draftDiffers(draftFor(issue), draftBaseline(issue, data)))
        .map((issue) => issue.id),
    [data, draftFor, issues],
  );

  useEffect(() => {
    if (!unsavedIssueIds.length) return;
    const warn = (event: BeforeUnloadEvent) => {
      event.preventDefault();
      event.returnValue = '';
    };
    window.addEventListener('beforeunload', warn);
    return () => window.removeEventListener('beforeunload', warn);
  }, [unsavedIssueIds.length]);

  const setDraft = useCallback((issueId: string, patch: Partial<AdminDraft>) => {
    setDrafts((current) => ({
      ...current,
      [issueId]: { ...(current[issueId] || EMPTY_ADMIN_DRAFT), ...patch },
    }));
  }, []);

  const setCloseDraft = useCallback((issueId: string, patch: Partial<CloseDraft>) => {
    setCloseDrafts((current) => ({
      ...current,
      [issueId]: { ...(current[issueId] || EMPTY_CLOSE_DRAFT), ...patch },
    }));
  }, []);

  const toggleIssue = useCallback((issueId: string) => {
    setExpandedIssueIds((current) => {
      const next = new Set(current);
      next.has(issueId) ? next.delete(issueId) : next.add(issueId);
      return next;
    });
  }, []);

  const focusIssue = useCallback((issueId: string) => {
    setExpandedIssueIds((current) => new Set(current).add(issueId));
    window.setTimeout(() => revealElement(revisionIssueElementId(issueId)), 60);
  }, []);

  const focusSource = useCallback((issueId: string) => {
    window.setTimeout(() => revealRevisionSource(issueId), 60);
  }, []);

  const fail = useCallback(
    (reason: any, title = 'Revision workspace could not save') => {
      const message = reason?.message || 'Please try again.';
      setError(message);
      toast({ title, description: message, status: 'error', duration: 6000 });
    },
    [toast],
  );

  const saveIssue = useCallback(
    async (issue: RevisionIssue): Promise<boolean> => {
      const draft = drafts[issue.id] || draftBaseline(issue, data);
      if (!draft.remedy || !draft.text.trim()) {
        setError('Choose a recommended fix and enter the contractor-facing comment.');
        focusIssue(issue.id);
        return false;
      }
      const comment = currentAdminComment(issue, data);
      const url = comment?.can_edit
        ? `${endpoint.replace('/revision_issues', '')}/revision_issue_comments/${encodeURIComponent(comment.id)}`
        : `${endpoint}/${encodeURIComponent(issue.id)}/comment`;
      try {
        await request(
          url,
          {
            method: comment?.can_edit ? 'PATCH' : 'POST',
            body: JSON.stringify({
              admin_recommended_remedy: draft.remedy,
              comment_text: draft.text.trim(),
            }),
          },
          issue.id,
        );
        toast({ title: 'Recommendation saved', status: 'success', duration: 2200 });
        return true;
      } catch (reason: any) {
        fail(reason);
        return false;
      }
    },
    [data, drafts, endpoint, fail, focusIssue, request, toast],
  );

  const resetIssue = useCallback(
    async (issue: RevisionIssue) => {
      const comment = currentAdminComment(issue, data);
      if (!comment?.can_edit) {
        setDrafts((current) => ({ ...current, [issue.id]: draftBaseline(issue, data) }));
        return;
      }
      try {
        await request(
          `${endpoint.replace('/revision_issues', '')}/revision_issue_comments/${encodeURIComponent(comment.id)}/reset`,
          { method: 'POST' },
          issue.id,
        );
      } catch (reason: any) {
        fail(reason, 'Could not reset recommendation');
      }
    },
    [data, endpoint, fail, request],
  );

  const deleteIssue = useCallback(
    async (issue: RevisionIssue) => {
      try {
        await request(`${endpoint}/${encodeURIComponent(issue.id)}`, { method: 'DELETE' }, issue.id);
        toast({ title: 'Unsent issue deleted', status: 'success', duration: 2200 });
      } catch (reason: any) {
        fail(reason, 'Could not delete issue');
      }
    },
    [endpoint, fail, request, toast],
  );

  const closeIssue = useCallback(
    async (issue: RevisionIssue): Promise<boolean> => {
      const draft = closeDrafts[issue.id] || EMPTY_CLOSE_DRAFT;
      if (!draft.status || !draft.text.trim()) {
        setError('Choose a final disposition and enter the required disposition comment.');
        focusIssue(issue.id);
        return false;
      }
      try {
        await request(
          `${endpoint}/${encodeURIComponent(issue.id)}/close`,
          {
            method: 'POST',
            body: JSON.stringify({ status: draft.status, disposition_comment: draft.text.trim() }),
          },
          issue.id,
        );
        setCloseDrafts((current) => ({ ...current, [issue.id]: EMPTY_CLOSE_DRAFT }));
        toast({ title: 'Issue closed', status: 'success', duration: 2200 });
        return true;
      } catch (reason: any) {
        fail(reason, 'Could not close issue');
        return false;
      }
    },
    [closeDrafts, endpoint, fail, focusIssue, request, toast],
  );

  const requestSend = useCallback(() => {
    const firstUnsaved = unsavedIssueIds[0];
    if (firstUnsaved) {
      setError('Save every changed recommendation before sending.');
      focusIssue(firstUnsaved);
      return;
    }
    if (!data?.capabilities?.can_send_issues) {
      const firstIncomplete = data?.capabilities?.missing_admin_comment_issue_ids?.[0];
      setError('Complete and save a recommendation for every unresolved issue before sending.');
      if (firstIncomplete) focusIssue(firstIncomplete);
      return;
    }
    setSendConfirmationOpen(true);
  }, [data?.capabilities, focusIssue, unsavedIssueIds]);

  const confirmSend = useCallback(async () => {
    try {
      await request(`${endpoint}/send`, { method: 'POST' });
      setSendConfirmationOpen(false);
      toast({ title: 'Revision issues sent to contractor', status: 'success', duration: 3000 });
    } catch (reason: any) {
      setSendConfirmationOpen(false);
      const firstIncomplete = reason?.details?.issue_ids?.[0];
      if (firstIncomplete) focusIssue(String(firstIncomplete));
      fail(reason, 'Could not send revision issues');
    }
  }, [endpoint, fail, focusIssue, request, toast]);

  return {
    data,
    issues,
    loading,
    busy,
    error,
    errorDetails,
    expandedIssueIds,
    unsavedIssueIds,
    sendConfirmationOpen,
    adoptData,
    draftFor,
    closeDraftFor,
    setDraft,
    setCloseDraft,
    toggleIssue,
    focusIssue,
    focusSource,
    saveIssue,
    resetIssue,
    deleteIssue,
    closeIssue,
    requestSend,
    confirmSend,
    cancelSend: () => setSendConfirmationOpen(false),
  };
};

const issueState = (issue: RevisionIssue, workspace: AdminInlineRevisionWorkspace) => {
  if (!revisionIssueUnresolved(issue)) return null;
  if (latestRoundAwaitingContractor(workspace.data)) {
    return { label: 'With contractor', colour: 'orange' };
  }
  const draft = workspace.draftFor(issue);
  const baseline = draftBaseline(issue, workspace.data);
  if (draftDiffers(draft, baseline)) return { label: 'Unsaved changes', colour: 'yellow' };
  const comment = currentAdminComment(issue, workspace.data);
  if (comment?.can_edit && draft.remedy && draft.text.trim()) return { label: 'Ready to send', colour: 'blue' };
  if (issue.status === 'open' && issue.comments.some((candidate) => candidate.author_type === 'contractor')) {
    return { label: 'Contractor response received', colour: 'purple' };
  }
  return { label: 'Recommendation required', colour: 'orange' };
};

const sentHistoryLabel = (issue: RevisionIssue, data: RevisionTrackerData | null): string => {
  if (!issue.was_sent_to_contractor) return 'Never sent to contractor';
  const date = formatSentDate(issue.last_sent_to_contractor_at);
  const sentRoundIds = new Set((data?.rounds || []).filter((round) => !!round.admin_sent_at).map((round) => round.id));
  const rounds = Array.from(
    new Set(
      issue.comments
        .filter((comment) => sentRoundIds.has(comment.revision_round_id))
        .map((comment) => comment.round_number),
    ),
  ).filter(Boolean);
  const round = rounds.length ? `Exchange ${Math.max(...rounds)}` : 'Sent to contractor';
  return date ? `${round} • ${date}` : round;
};

export const AdminInlineRevisionIssue = ({
  issue,
  workspace,
  sourceAvailable = false,
}: {
  issue?: RevisionIssue;
  workspace: AdminInlineRevisionWorkspace;
  sourceAvailable?: boolean;
}) => {
  if (!issue) return null;
  const expanded = workspace.expandedIssueIds.has(issue.id);
  const draft = workspace.draftFor(issue);
  const closeDraft = workspace.closeDraftFor(issue);
  const state = issueState(issue, workspace);
  const showStateBadge =
    state && state.label !== 'Ready to send' && state.label !== 'Recommendation required' ? state : null;
  const selectedRecommendation = adminRemedyLabel(draft.remedy);
  const hasUnsavedChanges = workspace.unsavedIssueIds.includes(issue.id);
  const editableComment = currentAdminComment(issue, workspace.data);
  const visibleComments = editableComment?.can_edit
    ? issue.comments.filter((comment) => comment.id !== editableComment.id)
    : issue.comments;
  const conversationRounds = Array.from(
    visibleComments
      .reduce((rounds, comment) => {
        const existing = rounds.get(comment.revision_round_id);
        if (existing) {
          existing.comments.push(comment);
        } else {
          rounds.set(comment.revision_round_id, {
            id: comment.revision_round_id,
            number: comment.round_number,
            comments: [comment],
          });
        }
        return rounds;
      }, new Map<string, { id: string; number: number; comments: RevisionIssueComment[] }>())
      .values(),
  ).sort((left, right) => left.number - right.number);
  const value = sourceValue(issue.source.value);

  return (
    <Box
      id={revisionIssueElementId(issue.id)}
      tabIndex={-1}
      mt="6px"
      mb="8px"
      borderWidth="1px"
      borderLeftWidth={hasUnsavedChanges ? '4px' : '1px'}
      borderColor={expanded ? 'blue.300' : 'gray.200'}
      borderLeftColor={hasUnsavedChanges ? 'yellow.400' : undefined}
      borderRadius="md"
      bg={revisionIssueUnresolved(issue) ? 'blue.50' : 'gray.50'}
      boxShadow={expanded ? '0 0 0 2px rgba(49, 130, 206, 0.10)' : undefined}
      _focus={{ outline: 'none', borderColor: 'blue.400' }}
    >
      <Flex align="center" gap="4px">
        <Button
          variant="ghost"
          flex="1"
          h="auto"
          minH="38px"
          px="9px"
          py="6px"
          justifyContent="flex-start"
          textAlign="left"
          whiteSpace="normal"
          onClick={() => workspace.toggleIssue(issue.id)}
        >
          <Flex w="100%" align="center" gap="7px" wrap="wrap">
            {expanded ? <CaretDown size={15} /> : <CaretRight size={15} />}
            <Text fontSize="sm" fontWeight="700" flex="1" minW="160px">
              {issue.source.friendly_label || pretty(issue.issue_type)}
            </Text>
            {selectedRecommendation ? (
              <Text fontSize="xs" color="gray.700">
                Recommendation: {selectedRecommendation}
              </Text>
            ) : null}
            {showStateBadge ? <Badge colorScheme={showStateBadge.colour}>{showStateBadge.label}</Badge> : null}
            {issue.was_sent_to_contractor ? (
              <Text fontSize="xs" color="gray.600">
                {sentHistoryLabel(issue, workspace.data)}
              </Text>
            ) : null}
          </Flex>
        </Button>
        {sourceAvailable ? (
          <Button size="xs" variant="outline" mr="7px" onClick={() => workspace.focusSource(issue.id)}>
            Focus
          </Button>
        ) : null}
      </Flex>

      {expanded ? (
        <Box px="10px" pb="10px">
          {value ? (
            <Text fontSize="sm" mb="8px">
              <Text as="span" fontWeight="600">
                Document value:{' '}
              </Text>
              {value}
            </Text>
          ) : null}

          {conversationRounds.length ? (
            <Box ml={{ base: 2, md: 4 }} mb="12px" py="4px">
              {conversationRounds.map((round) => (
                <Box key={round.id} mb="14px" _last={{ mb: 0 }}>
                  <Flex align="center" gap="7px" mb="7px">
                    <Text fontSize="sm" fontWeight="700" color="gray.800">
                      Round {round.number}
                    </Text>
                    {round.id === workspace.data?.latest_round_id ? (
                      <Badge colorScheme="blue" variant="subtle">
                        Current
                      </Badge>
                    ) : null}
                  </Flex>
                  <Flex direction="column" ml="4px" borderLeftWidth="4px" borderLeftColor="orange.200">
                    {round.comments.map((comment) => {
                      const choice = commentChoice(comment);

                      return (
                        <Box key={comment.id} position="relative" pl="18px" pb="14px" _last={{ pb: '2px' }}>
                          <Box
                            aria-hidden="true"
                            position="absolute"
                            top="3px"
                            left="-7px"
                            w="10px"
                            h="10px"
                            bg="orange.200"
                            borderRadius="full"
                          />
                          <Flex gap="7px" align="center" mb="3px" wrap="wrap">
                            <Badge bg="#F7F9FC" borderWidth="1px" borderColor="#053662" color="#2D2D2D">
                              {comment.author_type === 'admin' ? 'Admin' : 'Contractor'}
                            </Badge>
                            <Text fontSize="xs" color="gray.600">
                              {formatCommentDateTime(comment.created_at)}
                            </Text>
                          </Flex>
                          {choice ? (
                            <Text fontSize="sm" fontWeight="600" color="gray.800" mb="2px">
                              {choice.label}: {choice.value}
                            </Text>
                          ) : null}
                          <Text fontSize="sm" whiteSpace="pre-wrap">
                            {comment.comment_text}
                          </Text>
                          {comment.contractor_asserted_value ? (
                            <Text fontSize="sm" mt="2px">
                              Attested value: <strong>{comment.contractor_asserted_value}</strong>
                            </Text>
                          ) : null}
                        </Box>
                      );
                    })}
                  </Flex>
                </Box>
              ))}
            </Box>
          ) : null}

          {issue.disposition_comment ? (
            <Box
              bg={issue.was_sent_to_contractor ? 'green.50' : 'gray.100'}
              borderWidth="1px"
              borderColor={issue.was_sent_to_contractor ? 'green.200' : 'gray.300'}
              borderRadius="md"
              p="8px"
              mb="10px"
            >
              <Flex gap="6px" align="center" mb="3px" wrap="wrap">
                <Badge colorScheme={issue.was_sent_to_contractor ? 'green' : 'gray'}>Final disposition</Badge>
                {!issue.was_sent_to_contractor ? (
                  <Badge colorScheme="gray">Closed internally — never sent</Badge>
                ) : null}
              </Flex>
              <Text fontSize="sm" mb="3px">
                <Text as="span" fontWeight="700">
                  Outcome:{' '}
                </Text>
                {dispositionStatusLabel(issue.status)}
              </Text>
              <Text fontSize="sm" whiteSpace="pre-wrap">
                <Text as="span" fontWeight="700">
                  Admin note:{' '}
                </Text>
                {issue.disposition_comment}
              </Text>
            </Box>
          ) : null}

          {issue.can_admin_comment ? (
            <Box bg="white" borderWidth="1px" borderColor="blue.100" borderRadius="md" p="9px" mb="10px">
              <Text fontSize="sm" fontWeight="700">
                Your decision
              </Text>
              <Text fontSize="xs" color="gray.600" mb="7px">
                Send another request to the contractor, or close the issue below.
              </Text>
              <FormControl mb="7px">
                <FormLabel fontSize="xs" mb="2px">
                  Recommended fix
                </FormLabel>
                <Select
                  size="sm"
                  value={draft.remedy}
                  onChange={(event) => workspace.setDraft(issue.id, { remedy: event.target.value })}
                >
                  <option value="">Select a recommendation</option>
                  {ADMIN_REMEDIES.map(([valueOption, label]) => (
                    <option key={valueOption} value={valueOption}>
                      {label}
                    </option>
                  ))}
                </Select>
              </FormControl>
              <FormControl>
                <FormLabel fontSize="xs" mb="2px">
                  Contractor-facing comment
                </FormLabel>
                <Textarea
                  minH="115px"
                  size="sm"
                  value={draft.text}
                  onChange={(event) => workspace.setDraft(issue.id, { text: event.target.value })}
                />
              </FormControl>
              <Flex gap="6px" mt="7px" wrap="wrap">
                <Button
                  size="xs"
                  colorScheme="blue"
                  leftIcon={<FloppyDiskBack size={16} />}
                  isLoading={workspace.busy}
                  onClick={() => void workspace.saveIssue(issue)}
                >
                  Save recommendation
                </Button>
                <IconButton
                  aria-label="Reset recommendation"
                  icon={<ArrowCounterClockwise size={17} />}
                  size="xs"
                  variant="outline"
                  title="Reset from rule or field evidence"
                  isDisabled={workspace.busy}
                  onClick={() => void workspace.resetIssue(issue)}
                />
                {issue.can_delete ? (
                  <IconButton
                    aria-label="Delete unsent issue"
                    icon={<Trash size={17} />}
                    size="xs"
                    variant="outline"
                    colorScheme="red"
                    title="Delete this new issue before it is sent"
                    isDisabled={workspace.busy}
                    onClick={() => void workspace.deleteIssue(issue)}
                  />
                ) : null}
              </Flex>
            </Box>
          ) : null}

          {issue.can_close ? (
            <Box bg="purple.50" borderWidth="1px" borderColor="purple.100" borderRadius="md" p="9px">
              <Text fontSize="xs" fontWeight="700" mb="7px">
                Close issue
              </Text>
              <FormControl mb="7px">
                <FormLabel fontSize="xs" mb="2px">
                  Final disposition
                </FormLabel>
                <Select
                  size="sm"
                  value={closeDraft.status}
                  onChange={(event) => workspace.setCloseDraft(issue.id, { status: event.target.value })}
                >
                  <option value="">Select closing outcome</option>
                  {(issue.status === 'pending_admin_review' ? INTERNAL_CLOSE_STATUSES : CONTRACTOR_CLOSE_STATUSES).map(
                    ([valueOption, label]) => (
                      <option key={valueOption} value={valueOption}>
                        {label}
                      </option>
                    ),
                  )}
                </Select>
              </FormControl>
              <Textarea
                minH="80px"
                size="sm"
                placeholder="Required disposition comment"
                value={closeDraft.text}
                onChange={(event) => workspace.setCloseDraft(issue.id, { text: event.target.value })}
              />
              <Button
                size="xs"
                mt="7px"
                leftIcon={<CheckCircle size={16} />}
                isLoading={workspace.busy}
                onClick={() => void workspace.closeIssue(issue)}
              >
                Close issue
              </Button>
            </Box>
          ) : null}
        </Box>
      ) : null}
    </Box>
  );
};

export const AdminRevisionWorkspace = ({
  workspace,
  sourceIssueIds,
}: {
  workspace: AdminInlineRevisionWorkspace;
  sourceIssueIds: Set<string>;
}) => {
  const cancelRef = useRef<HTMLButtonElement>(null);
  const [decisionSavedSort, setDecisionSavedSort] = useState<'alphabetic' | 'recommendation_type'>('alphabetic');
  const unresolved = workspace.issues.filter(revisionIssueUnresolved);
  const isWithContractor = latestRoundAwaitingContractor(workspace.data);
  const readyToSendIssueIds = new Set(
    isWithContractor
      ? []
      : unresolved
          .filter((issue) => {
            const comment = currentAdminComment(issue, workspace.data);
            return !!comment?.can_edit && !!comment.admin_recommended_remedy && !!comment.comment_text.trim();
          })
          .map((issue) => issue.id),
  );
  const needsDecision = isWithContractor ? [] : unresolved.filter((issue) => !readyToSendIssueIds.has(issue.id));
  const decisionComplete = isWithContractor
    ? []
    : unresolved
        .filter((issue) => readyToSendIssueIds.has(issue.id))
        .sort((left, right) => {
          const leftIssueLabel = left.source.friendly_label || pretty(left.issue_type);
          const rightIssueLabel = right.source.friendly_label || pretty(right.issue_type);
          if (decisionSavedSort === 'recommendation_type') {
            const recommendationComparison = adminRemedyLabel(workspace.draftFor(left).remedy).localeCompare(
              adminRemedyLabel(workspace.draftFor(right).remedy),
            );
            if (recommendationComparison !== 0) return recommendationComparison;
          }
          return leftIssueLabel.localeCompare(rightIssueLabel);
        });
  const withContractor = isWithContractor ? unresolved : [];
  const closed = workspace.issues.filter((issue) => !revisionIssueUnresolved(issue));
  const categories = isWithContractor
    ? [
        { label: 'Awaiting contractor response', issues: withContractor, colour: 'orange' },
        { label: 'Closed', issues: closed, colour: 'green' },
      ]
    : [
        { label: 'Needs decision', issues: needsDecision, colour: 'yellow' },
        {
          label: 'Decision saved - pending send',
          issues: decisionComplete,
          colour: 'blue',
          showDecisionSort: true,
        },
        { label: 'Closed', issues: closed, colour: 'green' },
      ];
  const sendIssues = unresolved.filter((issue) => {
    const draft = workspace.draftFor(issue);
    const comment = currentAdminComment(issue, workspace.data);
    return comment?.can_edit && draft.remedy && draft.text.trim();
  });

  return (
    <>
      <Box bg="blue.50" borderWidth="1px" borderColor="blue.200" borderRadius="md" p="10px" mb="12px">
        <Flex align="center" justify="space-between" gap="8px" wrap="wrap">
          <Flex align="center" gap="7px" wrap="wrap">
            <Text fontWeight="700">Revision workspace</Text>
            {workspace.unsavedIssueIds.length ? (
              <Badge colorScheme="yellow">
                {workspace.unsavedIssueIds.length}{' '}
                {workspace.unsavedIssueIds.length === 1 ? 'unsaved change' : 'unsaved changes'}
              </Badge>
            ) : null}
          </Flex>
          {workspace.data?.invoice_status === 'admin_review_inbox' ? (
            <Button
              size="sm"
              colorScheme="blue"
              leftIcon={<PaperPlaneTilt size={17} />}
              isDisabled={
                !workspace.data?.capabilities?.can_send_issues || !!workspace.unsavedIssueIds.length || workspace.busy
              }
              onClick={workspace.requestSend}
            >
              Send to contractor
            </Button>
          ) : null}
        </Flex>
        {workspace.loading ? (
          <Flex align="center" gap="7px" mt="8px">
            <Spinner size="sm" />
            <Text fontSize="sm">Loading required rule issues…</Text>
          </Flex>
        ) : null}
        {workspace.error ? (
          <Box bg="red.50" borderWidth="1px" borderColor="red.200" borderRadius="md" p="7px" mt="8px">
            <Text color="red.700" fontSize="sm" fontWeight="600">
              {workspace.error}
            </Text>
            {workspace.errorDetails.map((detail) => (
              <Text key={detail} color="red.700" fontSize="xs">
                • {detail}
              </Text>
            ))}
          </Box>
        ) : null}

        <Accordion allowMultiple defaultIndex={categories.map((_, index) => index)} mt="10px">
          {categories.map((category) => (
            <AccordionItem key={category.label} borderColor="blue.200">
              {category.issues.length ? (
                <>
                  <h3>
                    <AccordionButton px="4px" py="8px" _hover={{ bg: 'blue.100' }}>
                      <Text flex="1" textAlign="left" fontSize="sm" fontWeight="700">
                        {category.label}
                      </Text>
                      <Badge colorScheme={category.colour} mr="8px">
                        {category.issues.length}
                      </Badge>
                      <AccordionIcon />
                    </AccordionButton>
                  </h3>
                  <AccordionPanel px="4px" pt="4px" pb="8px">
                    {'showDecisionSort' in category && category.showDecisionSort ? (
                      <Flex justify="flex-end" mb="8px">
                        <FormControl w={{ base: 'full', sm: '240px' }}>
                          <FormLabel fontSize="xs" mb="2px">
                            Sort issues
                          </FormLabel>
                          <Select
                            size="sm"
                            value={decisionSavedSort}
                            onChange={(event) =>
                              setDecisionSavedSort(event.target.value as 'alphabetic' | 'recommendation_type')
                            }
                          >
                            <option value="alphabetic">Alphabetic</option>
                            <option value="recommendation_type">Recommendation type</option>
                          </Select>
                        </FormControl>
                      </Flex>
                    ) : null}
                    {category.issues.map((issue) => (
                      <AdminInlineRevisionIssue
                        key={issue.id}
                        issue={issue}
                        workspace={workspace}
                        sourceAvailable={sourceIssueIds.has(issue.id)}
                      />
                    ))}
                  </AccordionPanel>
                </>
              ) : (
                <Flex as="h3" align="center" px="4px" py="8px">
                  <Text flex="1" textAlign="left" fontSize="sm" fontWeight="700">
                    {category.label}
                  </Text>
                  <Badge colorScheme={category.colour}>0</Badge>
                </Flex>
              )}
            </AccordionItem>
          ))}
        </Accordion>
      </Box>

      <AlertDialog
        isOpen={workspace.sendConfirmationOpen}
        leastDestructiveRef={cancelRef}
        onClose={workspace.cancelSend}
        isCentered
      >
        <AlertDialogOverlay>
          <AlertDialogContent>
            <AlertDialogHeader fontSize="lg" fontWeight="700">
              Send revision issues to contractor?
            </AlertDialogHeader>
            <AlertDialogBody>
              <Text mb="8px">
                The contractor will receive {sendIssues.length} {sendIssues.length === 1 ? 'request' : 'requests'}:
              </Text>
              {sendIssues.map((issue) => (
                <Box key={issue.id} borderLeftWidth="2px" borderColor="blue.300" pl="8px" mb="7px">
                  <Text fontSize="sm" fontWeight="700">
                    {issue.source.friendly_label || pretty(issue.issue_type)}
                  </Text>
                  <Text fontSize="xs">{pretty(workspace.draftFor(issue).remedy)}</Text>
                </Box>
              ))}
            </AlertDialogBody>
            <AlertDialogFooter>
              <Button ref={cancelRef} onClick={workspace.cancelSend}>
                Cancel
              </Button>
              <Button colorScheme="blue" ml={3} isLoading={workspace.busy} onClick={() => void workspace.confirmSend()}>
                Send to contractor
              </Button>
            </AlertDialogFooter>
          </AlertDialogContent>
        </AlertDialogOverlay>
      </AlertDialog>
    </>
  );
};
