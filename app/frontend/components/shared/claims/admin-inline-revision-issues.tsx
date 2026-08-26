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
  Tooltip,
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
export type AdminRevisionDecisionMode = 'recommend_action' | 'close_issue';

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

const revisionRoundHeading = (roundNumber: number): string => `Conversation round ${roundNumber}`;

const openingRuleResult = (value: unknown): 'pass' | 'info' | 'warn' | 'fail' | null => {
  const normalized = String(value ?? '')
    .trim()
    .toLowerCase();
  return normalized === 'pass' || normalized === 'info' || normalized === 'warn' || normalized === 'fail'
    ? normalized
    : null;
};

const openingRuleResultColor = (result: 'pass' | 'info' | 'warn' | 'fail'): string => {
  if (result === 'pass') return 'green.400';
  if (result === 'info') return 'blue.400';
  if (result === 'warn') return 'yellow.400';
  return 'red.400';
};

const openingRuleResultLabel = (result: 'pass' | 'info' | 'warn' | 'fail'): string =>
  result === 'warn' ? 'Warning' : `${result.charAt(0).toUpperCase()}${result.slice(1)}`;

const openingComplianceScore = (value: unknown): string => {
  if (value == null || value === '') return '';
  const score = Number(value);
  if (!Number.isFinite(score)) return '';
  return score.toLocaleString('en-CA', { maximumFractionDigits: 1 });
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
  focusedIssueId: string;
  unsavedIssueIds: string[];
  sendConfirmationOpen: boolean;
  adoptData: (next: RevisionTrackerData, resetIssueId?: string) => void;
  draftFor: (issue: RevisionIssue) => AdminDraft;
  closeDraftFor: (issue: RevisionIssue) => CloseDraft;
  setDraft: (issueId: string, patch: Partial<AdminDraft>) => void;
  setCloseDraft: (issueId: string, patch: Partial<CloseDraft>) => void;
  decisionModeFor: (issue: RevisionIssue) => AdminRevisionDecisionMode;
  setDecisionMode: (issueId: string, mode: AdminRevisionDecisionMode) => void;
  toggleIssue: (issueId: string) => void;
  focusIssue: (issueId: string, mode?: AdminRevisionDecisionMode) => void;
  focusSource: (issueId: string) => void;
  saveIssue: (issue: RevisionIssue) => Promise<boolean>;
  resetIssue: (issue: RevisionIssue) => Promise<void>;
  deleteIssue: (issue: RevisionIssue) => Promise<void>;
  closeIssue: (issue: RevisionIssue) => Promise<boolean>;
  requestSend: () => void;
  confirmSend: () => Promise<void>;
  cancelSend: () => void;
};

export type AdminRevisionIssueStage = {
  key: 'needs_decision' | 'unsaved_changes' | 'decision_saved' | 'with_contractor' | 'closed';
  label: string;
  colour: string;
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

const revealAfterRender = (findTarget: () => HTMLElement | null) => {
  requestAnimationFrame(() => {
    requestAnimationFrame(() => revealTarget(findTarget()));
  });
};

const revealElement = (elementId: string) => revealAfterRender(() => document.getElementById(elementId));

const revealRevisionSource = (issueId: string) =>
  revealAfterRender(() => document.querySelector<HTMLElement>(`[data-admin-revision-source-issue-id="${issueId}"]`));

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
  const [decisionModes, setDecisionModes] = useState<Record<string, AdminRevisionDecisionMode>>({});
  const [expandedIssueIds, setExpandedIssueIds] = useState<Set<string>>(() => new Set());
  const [focusedIssueId, setFocusedIssueId] = useState('');
  const focusHighlightTimerRef = useRef<number | null>(null);
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

  const setDecisionMode = useCallback((issueId: string, mode: AdminRevisionDecisionMode) => {
    setDecisionModes((current) => ({ ...current, [issueId]: mode }));
  }, []);

  const decisionModeFor = useCallback(
    (issue: RevisionIssue): AdminRevisionDecisionMode => {
      const selected = decisionModes[issue.id];
      if (selected === 'recommend_action' && issue.can_admin_comment) return selected;
      if (selected === 'close_issue' && issue.can_close) return selected;
      return issue.can_admin_comment ? 'recommend_action' : 'close_issue';
    },
    [decisionModes],
  );

  const toggleIssue = useCallback((issueId: string) => {
    setExpandedIssueIds((current) => (current.has(issueId) ? new Set() : new Set([issueId])));
  }, []);

  const focusIssue = useCallback((issueId: string, mode?: AdminRevisionDecisionMode) => {
    if (mode) setDecisionModes((current) => ({ ...current, [issueId]: mode }));
    setExpandedIssueIds(new Set([issueId]));
    setFocusedIssueId(issueId);
    if (focusHighlightTimerRef.current != null) window.clearTimeout(focusHighlightTimerRef.current);
    focusHighlightTimerRef.current = window.setTimeout(() => {
      setFocusedIssueId((current) => (current === issueId ? '' : current));
      focusHighlightTimerRef.current = null;
    }, 1600);
    revealElement(revisionIssueElementId(issueId));
  }, []);

  useEffect(
    () => () => {
      if (focusHighlightTimerRef.current != null) window.clearTimeout(focusHighlightTimerRef.current);
    },
    [],
  );

  const focusSource = useCallback((issueId: string) => {
    revealRevisionSource(issueId);
  }, []);

  const fail = useCallback(
    (reason: any, title = 'Revision issue could not be saved') => {
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
    focusedIssueId,
    unsavedIssueIds,
    sendConfirmationOpen,
    adoptData,
    draftFor,
    closeDraftFor,
    setDraft,
    setCloseDraft,
    decisionModeFor,
    setDecisionMode,
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

export const adminRevisionIssueStage = (
  issue: RevisionIssue,
  workspace: AdminInlineRevisionWorkspace,
): AdminRevisionIssueStage => {
  if (!revisionIssueUnresolved(issue)) return { key: 'closed', label: 'Closed', colour: 'green' };
  if (latestRoundAwaitingContractor(workspace.data)) {
    return { key: 'with_contractor', label: 'Awaiting contractor response', colour: 'orange' };
  }
  if (workspace.unsavedIssueIds.includes(issue.id)) {
    return { key: 'unsaved_changes', label: 'Unsaved Action Needed', colour: 'yellow' };
  }

  const comment = currentAdminComment(issue, workspace.data);
  if (comment?.can_edit && comment.admin_recommended_remedy && comment.comment_text.trim()) {
    return { key: 'decision_saved', label: 'Decision saved - pending send', colour: 'blue' };
  }

  return { key: 'needs_decision', label: 'Needs decision', colour: 'yellow' };
};

export type AdminRevisionListStatus = {
  key: 'in_development' | 'saved' | 'with_contractor' | 'closed';
  label: 'Action Needed' | 'Unsaved Action Needed' | 'Ready to Send' | 'Awaiting Contractor' | 'Closed';
  colour: 'yellow' | 'blue' | 'orange' | 'green';
};

export const adminRevisionIssueListStatus = (
  issue: RevisionIssue,
  workspace: AdminInlineRevisionWorkspace,
): AdminRevisionListStatus => {
  const stage = adminRevisionIssueStage(issue, workspace);
  if (stage.key === 'closed') return { key: 'closed', label: 'Closed', colour: 'green' };
  if (stage.key === 'with_contractor') {
    return { key: 'with_contractor', label: 'Awaiting Contractor', colour: 'orange' };
  }
  if (stage.key === 'unsaved_changes') {
    return { key: 'in_development', label: 'Unsaved Action Needed', colour: 'yellow' };
  }
  if (stage.key === 'needs_decision') {
    return { key: 'in_development', label: 'Action Needed', colour: 'yellow' };
  }
  return { key: 'saved', label: 'Ready to Send', colour: 'blue' };
};

const AdminRevisionOpenedTimelineEvent = ({
  issue,
  fontSize,
  lineColor,
}: {
  issue: RevisionIssue;
  fontSize: string;
  lineColor: string;
}) => {
  const reason = String(issue.source.reason || '').trim();
  const value = sourceValue(issue.source.value);
  const ruleResult = openingRuleResult(issue.source.rule_result);
  const complianceScore = openingComplianceScore(issue.source.compliance_score);

  return (
    <Flex direction="column" ml="4px" borderLeftWidth="3px" borderLeftColor={lineColor} mb="14px">
      <Box position="relative" pl="18px" pb="2px">
        <Box
          aria-hidden="true"
          position="absolute"
          top="5px"
          left="-7px"
          w="10px"
          h="10px"
          bg={lineColor}
          borderRadius="full"
        />
        <Flex gap="7px" align="center" mb="3px" wrap="wrap">
          <Badge bg="#F7F9FC" borderWidth="1px" borderColor="#053662" color="#2D2D2D">
            Opened
          </Badge>
          {ruleResult ? (
            <Tooltip label={`${openingRuleResultLabel(ruleResult)} when opened`} hasArrow placement="top">
              <Box
                as="span"
                aria-label={`${openingRuleResultLabel(ruleResult)} when opened`}
                w="10px"
                h="10px"
                borderRadius="full"
                display="inline-block"
                bg={openingRuleResultColor(ruleResult)}
                flexShrink={0}
              />
            </Tooltip>
          ) : null}
          {complianceScore ? (
            <Text fontSize={fontSize} fontWeight="600" color="gray.700">
              Compliance score {complianceScore}
            </Text>
          ) : null}
          <Text fontSize={fontSize} color="gray.600">
            {formatCommentDateTime(issue.created_at)}
          </Text>
        </Flex>
        {reason ? (
          <>
            <Text fontSize={fontSize} fontWeight="700" color="gray.800" mb="2px">
              Reason this issue was opened
            </Text>
            <Text fontSize={fontSize} whiteSpace="pre-wrap">
              {reason}
            </Text>
          </>
        ) : null}
        {value ? (
          <Text fontSize={fontSize} mt="3px">
            <Text as="span" fontWeight="600">
              Document value:{' '}
            </Text>
            {value}
          </Text>
        ) : null}
      </Box>
    </Flex>
  );
};

export const AdminRevisionIssueEditor = ({
  issue,
  workspace,
  listStatus,
  sourceAvailable = false,
  heading,
}: {
  issue: RevisionIssue;
  workspace: AdminInlineRevisionWorkspace;
  listStatus: AdminRevisionListStatus;
  sourceAvailable?: boolean;
  heading?: string;
}) => {
  const decisionMode = workspace.decisionModeFor(issue);
  const expanded = workspace.expandedIssueIds.has(issue.id);
  const focused = workspace.focusedIssueId === issue.id;
  const draft = workspace.draftFor(issue);
  const closeDraft = workspace.closeDraftFor(issue);
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

  return (
    <Box
      id={revisionIssueElementId(issue.id)}
      tabIndex={-1}
      mt="6px"
      mb="8px"
      borderWidth="1px"
      borderLeftWidth={hasUnsavedChanges ? '4px' : '1px'}
      borderColor={focused ? 'blue.500' : expanded ? 'blue.300' : 'gray.200'}
      borderLeftColor={hasUnsavedChanges ? 'yellow.400' : undefined}
      borderRadius="md"
      bg={focused ? 'gray.100' : '#FAF9F8'}
      boxShadow={
        focused
          ? '0 0 0 3px rgba(49, 130, 206, 0.24), 0 8px 20px rgba(49, 130, 206, 0.16)'
          : expanded
            ? '0 0 0 2px rgba(49, 130, 206, 0.10)'
            : undefined
      }
      transition="background-color 220ms ease, border-color 220ms ease, box-shadow 220ms ease"
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
              {heading || issue.source.friendly_label || pretty(issue.issue_type)}
            </Text>
            {selectedRecommendation ? (
              <Text fontSize="xs" color="gray.700">
                Recommendation: {selectedRecommendation}
              </Text>
            ) : null}
            <Badge colorScheme={listStatus.colour}>{listStatus.label}</Badge>
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
          <Box ml={{ base: 2, md: 4 }} mb="12px" py="4px">
            <AdminRevisionOpenedTimelineEvent issue={issue} fontSize="sm" lineColor="orange.200" />
            {conversationRounds.length ? (
              <>
                {conversationRounds.map((round) => (
                  <Box key={round.id} mb="14px" _last={{ mb: 0 }}>
                    <Flex align="center" gap="7px" mb="7px">
                      <Text fontSize="sm" fontWeight="700" color="gray.800">
                        {revisionRoundHeading(round.number)}
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
              </>
            ) : null}
          </Box>

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

          {issue.can_admin_comment && issue.can_close ? (
            <Flex mb="10px" gap="6px" role="group" aria-label="Choose how to handle this revision issue">
              <Button
                size="sm"
                flex="1"
                colorScheme="blue"
                variant={decisionMode === 'recommend_action' ? 'solid' : 'outline'}
                fontWeight={decisionMode === 'recommend_action' ? '700' : '500'}
                opacity={decisionMode === 'recommend_action' ? 1 : 0.7}
                aria-pressed={decisionMode === 'recommend_action'}
                onClick={() => workspace.setDecisionMode(issue.id, 'recommend_action')}
              >
                Recommend action
              </Button>
              <Button
                size="sm"
                flex="1"
                colorScheme="purple"
                variant={decisionMode === 'close_issue' ? 'solid' : 'outline'}
                fontWeight={decisionMode === 'close_issue' ? '700' : '500'}
                opacity={decisionMode === 'close_issue' ? 1 : 0.7}
                aria-pressed={decisionMode === 'close_issue'}
                onClick={() => workspace.setDecisionMode(issue.id, 'close_issue')}
              >
                Close issue
              </Button>
            </Flex>
          ) : null}

          {issue.can_admin_comment && (!issue.can_close || decisionMode === 'recommend_action') ? (
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
                  Save decision
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

          {issue.can_close && (!issue.can_admin_comment || decisionMode === 'close_issue') ? (
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

const adminRevisionIssueLabel = (issue: RevisionIssue): string =>
  issue.source.friendly_label || pretty(issue.issue_type);

const ADMIN_REVISION_STATUS_ORDER = { in_development: 0, saved: 1, with_contractor: 2, closed: 3 } as const;

const sortedAdminRevisionIssues = (issues: RevisionIssue[], workspace: AdminInlineRevisionWorkspace): RevisionIssue[] =>
  [...issues].sort((left, right) => {
    const statusComparison =
      ADMIN_REVISION_STATUS_ORDER[adminRevisionIssueListStatus(left, workspace).key] -
      ADMIN_REVISION_STATUS_ORDER[adminRevisionIssueListStatus(right, workspace).key];
    if (statusComparison !== 0) return statusComparison;
    return adminRevisionIssueLabel(left).localeCompare(adminRevisionIssueLabel(right));
  });

export const AdminRevisionSendControl = ({ workspace }: { workspace: AdminInlineRevisionWorkspace }) => {
  const cancelRef = useRef<HTMLButtonElement>(null);
  const sendIssues = workspace.issues.filter((issue) => {
    if (!revisionIssueUnresolved(issue)) return false;
    const draft = workspace.draftFor(issue);
    const comment = currentAdminComment(issue, workspace.data);
    return comment?.can_edit && draft.remedy && draft.text.trim();
  });

  if (workspace.data?.invoice_status !== 'admin_review_inbox') return null;

  return (
    <>
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
                    {adminRevisionIssueLabel(issue)}
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

const AdminRevisionReadOnlyHistory = ({
  issue,
  workspace,
}: {
  issue: RevisionIssue;
  workspace: AdminInlineRevisionWorkspace;
}) => {
  const rounds = Array.from(
    issue.comments
      .reduce((history, comment) => {
        const existing = history.get(comment.revision_round_id);
        if (existing) {
          existing.comments.push(comment);
        } else {
          history.set(comment.revision_round_id, {
            id: comment.revision_round_id,
            number: comment.round_number,
            comments: [comment],
          });
        }
        return history;
      }, new Map<string, { id: string; number: number; comments: RevisionIssueComment[] }>())
      .values(),
  ).sort((left, right) => left.number - right.number);

  return (
    <Box>
      <AdminRevisionOpenedTimelineEvent issue={issue} fontSize="16px" lineColor="#D8D8D8" />
      {rounds.map((round) => (
        <Box key={round.id} mb="14px" _last={{ mb: issue.disposition_comment ? '14px' : 0 }}>
          <Flex align="center" gap="7px" mb="7px">
            <Text fontSize="16px" fontWeight="700" color="gray.800">
              {revisionRoundHeading(round.number)}
            </Text>
            {round.id === workspace.data?.latest_round_id ? (
              <Badge colorScheme="blue" variant="subtle">
                Current
              </Badge>
            ) : null}
          </Flex>
          <Flex direction="column" ml="4px" borderLeftWidth="3px" borderLeftColor="#D8D8D8">
            {round.comments.map((comment) => {
              const choice = commentChoice(comment);

              return (
                <Box key={comment.id} position="relative" pl="18px" pb="14px" _last={{ pb: '2px' }}>
                  <Box
                    aria-hidden="true"
                    position="absolute"
                    top="5px"
                    left="-7px"
                    w="10px"
                    h="10px"
                    bg="#D8D8D8"
                    borderRadius="full"
                  />
                  <Flex gap="7px" align="center" mb="3px" wrap="wrap">
                    <Badge bg="#F7F9FC" borderWidth="1px" borderColor="#053662" color="#2D2D2D">
                      {comment.author_type === 'admin' ? 'Admin' : 'Contractor'}
                    </Badge>
                    <Text fontSize="16px" color="gray.600">
                      {formatCommentDateTime(comment.created_at)}
                    </Text>
                  </Flex>
                  {choice ? (
                    <Text fontSize="16px" fontWeight="600" color="gray.800" mb="2px">
                      {choice.label}: {choice.value}
                    </Text>
                  ) : null}
                  <Text fontSize="16px" whiteSpace="pre-wrap">
                    {comment.comment_text}
                  </Text>
                  {comment.contractor_asserted_value ? (
                    <Text fontSize="16px" mt="2px">
                      Attested value: <strong>{comment.contractor_asserted_value}</strong>
                    </Text>
                  ) : null}
                </Box>
              );
            })}
          </Flex>
        </Box>
      ))}

      {issue.disposition_comment ? (
        <Box bg="gray.50" borderWidth="1px" borderColor="#D8D8D8" borderRadius="md" p="8px">
          <Flex gap="6px" align="center" mb="3px" wrap="wrap">
            <Badge colorScheme={issue.was_sent_to_contractor ? 'green' : 'gray'}>Final disposition</Badge>
          </Flex>
          <Text fontSize="16px" mb="3px">
            <Text as="span" fontWeight="700">
              Outcome:{' '}
            </Text>
            {dispositionStatusLabel(issue.status)}
          </Text>
          <Text fontSize="16px" whiteSpace="pre-wrap">
            <Text as="span" fontWeight="700">
              Admin note:{' '}
            </Text>
            {issue.disposition_comment}
          </Text>
        </Box>
      ) : null}
    </Box>
  );
};

export const AdminRevisionSummary = ({
  workspace,
  sourceIssueIds,
}: {
  workspace: AdminInlineRevisionWorkspace;
  sourceIssueIds: Set<string>;
}) => {
  const issues = sortedAdminRevisionIssues(workspace.issues, workspace);

  return (
    <Box bg="#FAF9F8" borderWidth="1px" borderColor="#D8D8D8" borderRadius="md" p="10px">
      <Flex align="center" gap="7px" wrap="wrap">
        <Text fontWeight="700">Revision Summary</Text>
        {workspace.unsavedIssueIds.length ? (
          <Badge colorScheme="orange">
            {workspace.unsavedIssueIds.length}{' '}
            {workspace.unsavedIssueIds.length === 1 ? 'unsaved change' : 'unsaved changes'}
          </Badge>
        ) : null}
      </Flex>

      {workspace.loading ? (
        <Flex align="center" gap="7px" mt="8px">
          <Spinner size="sm" />
          <Text fontSize="sm">Loading revision summary...</Text>
        </Flex>
      ) : null}
      {workspace.error ? (
        <Box bg="red.50" borderWidth="1px" borderColor="red.200" borderRadius="md" p="7px" mt="8px">
          <Text color="red.700" fontSize="sm" fontWeight="600">
            {workspace.error}
          </Text>
        </Box>
      ) : null}

      {!workspace.loading ? (
        issues.length ? (
          <Accordion mt="9px" allowMultiple display="flex" flexDirection="column" gap="7px">
            {issues.map((issue) => {
              const status = adminRevisionIssueListStatus(issue, workspace);
              const recommendation = adminRemedyLabel(workspace.draftFor(issue).remedy);
              const sourceAvailable = sourceIssueIds.has(issue.id);

              return (
                <AccordionItem
                  key={issue.id}
                  bg="white"
                  borderWidth="1px"
                  borderColor="#D8D8D8"
                  borderRadius="md"
                  overflow="hidden"
                >
                  <h3>
                    <AccordionButton px="9px" py="8px" _hover={{ bg: '#FAF9F8' }} _expanded={{ bg: '#FAF9F8' }}>
                      <Flex align="center" gap="7px" wrap="wrap" flex="1" minW={0} textAlign="left">
                        <AccordionIcon flexShrink={0} />
                        <Text fontSize="16px" fontWeight="600" flex="1" minW="180px">
                          {adminRevisionIssueLabel(issue)}
                        </Text>
                        {recommendation ? (
                          <Text fontSize="16px" color="gray.600">
                            {recommendation}
                          </Text>
                        ) : null}
                        <Badge colorScheme={status.colour}>{status.label}</Badge>
                      </Flex>
                    </AccordionButton>
                  </h3>
                  <AccordionPanel px="10px" pt="9px" pb="10px" borderTopWidth="1px" borderColor="#D8D8D8">
                    <Flex align="center" justify="space-between" gap="8px" mb="10px" wrap="wrap">
                      <Text fontSize="16px" fontWeight="700">
                        History
                      </Text>
                      <Button
                        size="sm"
                        variant="outline"
                        onClick={() => workspace.focusIssue(issue.id)}
                        isDisabled={!sourceAvailable}
                        title={sourceAvailable ? 'Focus this item in the invoice evidence' : 'Source is not available'}
                      >
                        Focus
                      </Button>
                    </Flex>
                    <AdminRevisionReadOnlyHistory issue={issue} workspace={workspace} />
                  </AccordionPanel>
                </AccordionItem>
              );
            })}
          </Accordion>
        ) : (
          <Text fontSize="sm" color="gray.600" mt="8px">
            No revision issues.
          </Text>
        )
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
  const [statusFilter, setStatusFilter] = useState<'all' | 'in_development' | 'saved' | 'with_contractor' | 'closed'>(
    'all',
  );
  const visibleIssues = sortedAdminRevisionIssues(
    workspace.issues.filter(
      (issue) => statusFilter === 'all' || adminRevisionIssueListStatus(issue, workspace).key === statusFilter,
    ),
    workspace,
  );

  return (
    <>
      <Box bg="#FAF9F8" borderWidth="1px" borderColor="#D8D8D8" borderRadius="md" p="10px" mb="12px">
        <Flex align="center" justify="space-between" gap="8px" wrap="wrap">
          <Flex align="center" gap="7px" wrap="wrap" flex="1">
            <Text fontWeight="700">Revision Issues</Text>
            {workspace.unsavedIssueIds.length ? (
              <Badge colorScheme="yellow">
                {workspace.unsavedIssueIds.length}{' '}
                {workspace.unsavedIssueIds.length === 1 ? 'unsaved change' : 'unsaved changes'}
              </Badge>
            ) : null}
            <Flex align="center" gap="6px">
              <Text
                as="label"
                htmlFor="revision-issue-status-filter"
                fontSize="xs"
                fontWeight="600"
                whiteSpace="nowrap"
              >
                Filter by
              </Text>
              <Select
                id="revision-issue-status-filter"
                size="sm"
                w="150px"
                aria-label="Filter revision issues by status"
                value={statusFilter}
                onChange={(event) =>
                  setStatusFilter(
                    event.target.value as 'all' | 'in_development' | 'saved' | 'with_contractor' | 'closed',
                  )
                }
              >
                <option value="all">All statuses</option>
                <option value="in_development">Action Needed</option>
                <option value="saved">Ready to Send</option>
                <option value="with_contractor">Awaiting Contractor</option>
                <option value="closed">Closed</option>
              </Select>
            </Flex>
          </Flex>
          <AdminRevisionSendControl workspace={workspace} />
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

        <Box mt="10px">
          {visibleIssues.length ? (
            visibleIssues.map((issue) => (
              <AdminRevisionIssueEditor
                key={issue.id}
                issue={issue}
                workspace={workspace}
                listStatus={adminRevisionIssueListStatus(issue, workspace)}
                sourceAvailable={sourceIssueIds.has(issue.id)}
              />
            ))
          ) : (
            <Box bg="white" borderWidth="1px" borderColor="#D8D8D8" borderRadius="md" px="10px" py="12px">
              <Text fontSize="sm" color="gray.600">
                No revision issues match this status.
              </Text>
            </Box>
          )}
        </Box>
      </Box>
    </>
  );
};
