import {
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
import {
  ArrowCounterClockwise,
  CaretDown,
  CaretRight,
  CheckCircle,
  FloppyDiskBack,
  Info,
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

const INTERNAL_CLOSE_STATUSES = [['closed_no_contractor_action_required', 'Confirmed - no contractor action required']];
const CONTRACTOR_CLOSE_STATUSES = [
  ['closed_via_corrected_documentation', 'Corrected documentation accepted'],
  ['closed_via_attestation', 'Attestation accepted'],
  ['closed_via_exception', 'Exception granted'],
  ['closed_as_withdrawn', 'Issue withdrawn'],
];

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

export const revisionIssueStatusLabel = (status: RevisionIssue['status']): string => {
  if (status === 'pending_admin_review') return 'Awaiting admin decision';
  if (status === 'open') return 'Open';
  if (status === 'closed_no_contractor_action_required') return 'Closed internally';
  if (status === 'closed_via_corrected_documentation') return 'Corrected documentation accepted';
  if (status === 'closed_via_attestation') return 'Attestation accepted';
  if (status === 'closed_via_exception') return 'Exception granted';
  if (status === 'closed_as_withdrawn') return 'Withdrawn';
  return pretty(status);
};

const statusColour = (issue: RevisionIssue): string => {
  if (issue.status === 'pending_admin_review') return 'yellow';
  if (issue.status === 'open') return 'orange';
  if (issue.status === 'closed_via_exception') return 'purple';
  return issue.was_sent_to_contractor ? 'green' : 'gray';
};

const formatSentDate = (value?: string | null): string => {
  if (!value) return '';
  const date = new Date(value);
  return Number.isNaN(date.valueOf()) ? '' : date.toLocaleDateString();
};

const currentAdminComment = (
  issue: RevisionIssue,
  data: RevisionTrackerData | null,
): RevisionIssueComment | undefined =>
  [...issue.comments]
    .reverse()
    .find((comment) => comment.author_type === 'admin' && comment.revision_round_id === data?.latest_round_id);

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
  saveIssue: (issue: RevisionIssue) => Promise<boolean>;
  resetIssue: (issue: RevisionIssue) => Promise<void>;
  deleteIssue: (issue: RevisionIssue) => Promise<void>;
  closeIssue: (issue: RevisionIssue) => Promise<boolean>;
  requestSend: () => void;
  confirmSend: () => Promise<void>;
  cancelSend: () => void;
};

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
    window.setTimeout(() => {
      const target = document.getElementById(`admin-revision-issue-${issueId}`);
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
      target?.scrollIntoView({ behavior: 'smooth', block: 'center' });
      target?.focus({ preventScroll: true });
    }, 60);
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
  if (workspace.data?.invoice_status === 'contractor_revision_inbox') {
    return { label: 'With contractor', colour: 'orange' };
  }
  const draft = workspace.draftFor(issue);
  const baseline = draftBaseline(issue, workspace.data);
  if (draftDiffers(draft, baseline)) return { label: 'Unsaved changes', colour: 'yellow' };
  const comment = currentAdminComment(issue, workspace.data);
  if (comment?.can_edit && draft.remedy && draft.text.trim()) return { label: 'Ready to send', colour: 'blue' };
  if (issue.status === 'open' && issue.comments.some((candidate) => candidate.author_type === 'contractor')) {
    return { label: 'Contractor replied', colour: 'purple' };
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
}: {
  issue?: RevisionIssue;
  workspace: AdminInlineRevisionWorkspace;
}) => {
  if (!issue) return null;
  const expanded = workspace.expandedIssueIds.has(issue.id);
  const draft = workspace.draftFor(issue);
  const closeDraft = workspace.closeDraftFor(issue);
  const state = issueState(issue, workspace);
  const editableComment = currentAdminComment(issue, workspace.data);
  const visibleComments = editableComment?.can_edit
    ? issue.comments.filter((comment) => comment.id !== editableComment.id)
    : issue.comments;
  const value = sourceValue(issue.source.value);

  return (
    <Box
      id={`admin-revision-issue-${issue.id}`}
      tabIndex={-1}
      mt="6px"
      mb="8px"
      borderWidth="1px"
      borderColor={expanded ? 'blue.300' : 'gray.200'}
      borderRadius="md"
      bg={revisionIssueUnresolved(issue) ? 'blue.50' : 'gray.50'}
      boxShadow={expanded ? '0 0 0 2px rgba(49, 130, 206, 0.10)' : undefined}
      _focus={{ outline: 'none', borderColor: 'blue.400' }}
    >
      <Button
        variant="ghost"
        w="100%"
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
          <Badge colorScheme={statusColour(issue)}>{revisionIssueStatusLabel(issue.status)}</Badge>
          {state ? <Badge colorScheme={state.colour}>{state.label}</Badge> : null}
          <Text fontSize="xs" color="gray.600">
            {sentHistoryLabel(issue, workspace.data)}
          </Text>
        </Flex>
      </Button>

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

          {visibleComments.length ? (
            <Box borderLeftWidth="2px" borderColor="gray.200" pl="10px" mb="10px">
              {visibleComments.map((comment) => (
                <Box key={comment.id} mb="9px">
                  <Flex gap="6px" align="center" mb="2px" wrap="wrap">
                    <Badge colorScheme={comment.author_type === 'admin' ? 'blue' : 'green'}>
                      {comment.author_type === 'admin' ? 'Admin' : 'Contractor'}
                    </Badge>
                    <Text fontSize="xs" color="gray.600">
                      Exchange {comment.round_number}
                    </Text>
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
                    <Text fontSize="sm">Asserted value: {comment.contractor_asserted_value}</Text>
                  ) : null}
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
              <Text fontSize="sm" whiteSpace="pre-wrap">
                {issue.disposition_comment}
              </Text>
            </Box>
          ) : null}

          {issue.can_admin_comment ? (
            <Box bg="white" borderWidth="1px" borderColor="blue.100" borderRadius="md" p="9px" mb="10px">
              <Text fontSize="xs" fontWeight="700" mb="7px">
                Contractor request
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

export const AdminRevisionWorkspaceToolbar = ({ workspace }: { workspace: AdminInlineRevisionWorkspace }) => {
  const cancelRef = useRef<HTMLButtonElement>(null);
  const unresolved = workspace.issues.filter(revisionIssueUnresolved);
  const pending = unresolved.filter((issue) => issue.status === 'pending_admin_review').length;
  const open = unresolved.length - pending;
  const sendIssues = unresolved.filter((issue) => {
    const draft = workspace.draftFor(issue);
    const comment = currentAdminComment(issue, workspace.data);
    return comment?.can_edit && draft.remedy && draft.text.trim();
  });

  return (
    <>
      <Box bg="blue.50" borderWidth="1px" borderColor="blue.200" borderRadius="md" p="10px" mb="12px">
        <Flex align="center" justify="space-between" gap="8px" wrap="wrap">
          <Box>
            <Text fontWeight="700">Revision workspace</Text>
            <Flex gap="6px" mt="3px" wrap="wrap">
              <Badge colorScheme="yellow">{pending} awaiting decision</Badge>
              <Badge colorScheme="orange">{open} open</Badge>
              {workspace.unsavedIssueIds.length ? (
                <Badge colorScheme="yellow">{workspace.unsavedIssueIds.length} unsaved</Badge>
              ) : null}
            </Flex>
          </Box>
          <Button
            size="sm"
            colorScheme="blue"
            leftIcon={<PaperPlaneTilt size={17} />}
            isDisabled={!unresolved.length || workspace.busy}
            onClick={workspace.requestSend}
          >
            Send to contractor
          </Button>
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

type SnapshotProps = {
  workspace: AdminInlineRevisionWorkspace;
  matchedIssueIds: Set<string>;
};

export const AdminRevisionSnapshot = ({ workspace, matchedIssueIds }: SnapshotProps) => {
  const [historyIssueId, setHistoryIssueId] = useState<string | null>(null);
  const readyToSend = workspace.issues.filter((issue) => {
    if (issue.status !== 'pending_admin_review') return false;
    const comment = currentAdminComment(issue, workspace.data);
    return !!comment?.can_edit && !!comment.admin_recommended_remedy && !!comment.comment_text.trim();
  });
  const visible = workspace.issues.filter(
    (issue) =>
      readyToSend.some((candidate) => candidate.id === issue.id) ||
      issue.status === 'open' ||
      (!revisionIssueUnresolved(issue) && issue.was_sent_to_contractor),
  );
  const historyIssue = visible.find((issue) => issue.id === historyIssueId);
  const openIssues = visible.filter((issue) => issue.status === 'open');
  const withContractor = workspace.data?.invoice_status === 'contractor_revision_inbox' ? openIssues : [];
  const returnedForReview = workspace.data?.invoice_status === 'admin_review_inbox' ? openIssues : [];
  const otherOpen = openIssues.filter(
    (issue) =>
      !withContractor.some((candidate) => candidate.id === issue.id) &&
      !returnedForReview.some((candidate) => candidate.id === issue.id),
  );
  const resolved = visible.filter((issue) => !revisionIssueUnresolved(issue));
  const groups = [
    ['Ready to send', readyToSend, 'blue'],
    ['With contractor', withContractor, 'orange'],
    ['Returned for review', returnedForReview, 'purple'],
    ['Open issues', otherOpen, 'orange'],
    ['Resolved after contractor', resolved, 'green'],
  ] as const;

  return (
    <>
      <Box bg="gray.50" borderWidth="1px" borderColor="gray.200" borderRadius="md" p="12px">
        <Flex align="center" justify="space-between" mb="4px">
          <Text fontWeight="700">Revision snapshot</Text>
          <Badge colorScheme="blue">Read only</Badge>
        </Flex>
        <Text fontSize="xs" color="gray.600" mb="10px">
          Requests ready to send and issues that were previously sent to the contractor.
        </Text>
        {workspace.loading ? (
          <Flex minH="120px" align="center" justify="center">
            <Spinner />
          </Flex>
        ) : !visible.length ? (
          <Text fontSize="sm" color="gray.600" py="12px">
            No contractor-facing revisions are ready or have been sent.
          </Text>
        ) : (
          groups.map(([label, issues, colour]) =>
            issues.length ? (
              <Box key={label} mb="12px">
                <Flex align="center" gap="6px" mb="6px">
                  <Text fontSize="xs" fontWeight="700" textTransform="uppercase" color="gray.600">
                    {label}
                  </Text>
                  <Badge colorScheme={colour}>{issues.length}</Badge>
                </Flex>
                {issues.map((issue) => (
                  <Box
                    key={issue.id}
                    bg="white"
                    borderWidth="1px"
                    borderColor="gray.200"
                    borderRadius="md"
                    p="8px"
                    mb="6px"
                  >
                    <Flex align="start" gap="6px">
                      <Box flex="1" minW={0}>
                        <Text fontSize="sm" fontWeight="700" noOfLines={2}>
                          {issue.source.friendly_label || pretty(issue.issue_type)}
                        </Text>
                        <Flex gap="5px" mt="4px" wrap="wrap">
                          {issue.was_sent_to_contractor ? (
                            <Text fontSize="xs" color="gray.600">
                              {sentHistoryLabel(issue, workspace.data)}
                            </Text>
                          ) : null}
                        </Flex>
                      </Box>
                      {matchedIssueIds.has(issue.id) ? (
                        <Button size="xs" variant="outline" onClick={() => workspace.focusIssue(issue.id)}>
                          Focus
                        </Button>
                      ) : null}
                      <IconButton
                        aria-label="View revision history"
                        icon={<Info size={17} />}
                        size="xs"
                        variant="ghost"
                        onClick={() => setHistoryIssueId(issue.id)}
                      />
                    </Flex>
                  </Box>
                ))}
              </Box>
            ) : null,
          )
        )}
      </Box>

      <Drawer isOpen={!!historyIssue} placement="right" size="md" onClose={() => setHistoryIssueId(null)}>
        <DrawerOverlay />
        <DrawerContent>
          <DrawerCloseButton />
          <DrawerHeader>{historyIssue?.source.friendly_label || 'Revision issue history'}</DrawerHeader>
          <DrawerBody>
            {historyIssue?.comments.map((comment) => (
              <Box key={comment.id} borderBottomWidth="1px" borderColor="gray.200" py="10px">
                <Flex align="center" gap="6px" mb="4px" wrap="wrap">
                  <Badge colorScheme={comment.author_type === 'admin' ? 'blue' : 'green'}>
                    {comment.author_type === 'admin' ? 'Admin' : 'Contractor'}
                  </Badge>
                  <Text fontSize="xs" color="gray.600">
                    Exchange {comment.round_number}
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
            ))}
            {historyIssue?.disposition_comment ? (
              <Box py="10px">
                <Badge colorScheme="green" mb="4px">
                  Final disposition
                </Badge>
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

export const AdminUnmatchedRevisionIssues = ({
  issues,
  workspace,
}: {
  issues: RevisionIssue[];
  workspace: AdminInlineRevisionWorkspace;
}) => {
  if (!issues.length) return null;
  return (
    <Box mt="14px" borderTopWidth="2px" borderColor="orange.200" pt="10px">
      <Flex align="center" gap="7px" mb="6px">
        <Text fontWeight="700">Unmatched open revisions</Text>
        <Badge colorScheme="orange">{issues.length}</Badge>
      </Flex>
      <Text fontSize="xs" color="gray.600" mb="8px">
        These open issues no longer have one unambiguous source in the current package version. They remain editable.
      </Text>
      {issues.map((issue) => (
        <AdminInlineRevisionIssue key={issue.id} issue={issue} workspace={workspace} />
      ))}
    </Box>
  );
};
