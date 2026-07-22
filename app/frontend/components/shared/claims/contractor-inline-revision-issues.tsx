import {
  Accordion,
  AccordionButton,
  AccordionIcon,
  AccordionItem,
  AccordionPanel,
  Badge,
  Box,
  Button,
  Flex,
  Select,
  Spinner,
  Text,
  Textarea,
  useToast,
} from '@chakra-ui/react';
import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { ContractorDraftState, RevisionIssue, RevisionIssueComment, RevisionTrackerData } from './revision-tracker';

type ContractorDraft = { method: string; text: string; assertedValue: string };

const EMPTY_DRAFT: ContractorDraft = { method: '', text: '', assertedValue: '' };

const CONTRACTOR_METHODS = [
  ['corrected_invoice_uploaded', 'Corrected invoice uploaded'],
  ['supporting_document_uploaded', 'Supporting document uploaded'],
  ['attestation_provided', 'Attestation provided'],
  ['explanation_provided', 'Explanation provided'],
  ['unable_to_resolve', 'Unable to resolve'],
];

const ADMIN_REMEDY_LABELS: Record<string, string> = {
  correct_and_reupload_invoice: 'Correct and re-upload the invoice',
  upload_supporting_document: 'Upload a supporting document',
  provide_attestation: 'Provide an attestation',
  provide_explanation: 'Provide an explanation',
};

const pretty = (value: unknown): string =>
  String(value ?? '')
    .replace(/_/g, ' ')
    .replace(/^./, (letter) => letter.toUpperCase());

const draftComplete = (issue: RevisionIssue, draft: ContractorDraft): boolean => {
  if (!draft.method || !draft.text.trim()) return false;
  return !(draft.method === 'attestation_provided' && issue.issue_type !== 'rule' && !draft.assertedValue.trim());
};

const draftDiffers = (draft: ContractorDraft, saved?: RevisionIssueComment): boolean =>
  draft.method !== (saved?.contractor_response_method || '') ||
  draft.text !== (saved?.comment_text || '') ||
  draft.assertedValue !== (saved?.contractor_asserted_value || '');

const responseDraft = (saved?: RevisionIssueComment): ContractorDraft =>
  saved
    ? {
        method: saved.contractor_response_method || '',
        text: saved.comment_text || '',
        assertedValue: saved.contractor_asserted_value || '',
      }
    : { ...EMPTY_DRAFT };

const currentComment = (
  issue: RevisionIssue,
  data: RevisionTrackerData | null,
  authorType: 'admin' | 'contractor',
): RevisionIssueComment | undefined =>
  [...issue.comments]
    .reverse()
    .find((comment) => comment.author_type === authorType && comment.revision_round_id === data?.latest_round_id);

export type ContractorRevisionPresentationState = {
  key: 'upload_required' | 'resolved' | 'response_saved' | 'response_submitted' | 'action_required' | 'under_review';
  label: string;
  colorScheme: string;
};

export const contractorRevisionPresentationState = (
  issue: RevisionIssue,
  data: RevisionTrackerData | null,
): ContractorRevisionPresentationState => {
  if (data?.capabilities?.document_upload_required_issue_ids?.includes(issue.id)) {
    return { key: 'upload_required', label: 'Upload required', colorScheme: 'red' };
  }
  if (!['pending_admin_review', 'open'].includes(issue.status)) {
    return { key: 'resolved', label: 'Resolved', colorScheme: 'green' };
  }
  if (currentComment(issue, data, 'contractor')) {
    return issue.can_contractor_respond
      ? { key: 'response_saved', label: 'Response saved', colorScheme: 'blue' }
      : { key: 'response_submitted', label: 'Response submitted', colorScheme: 'blue' };
  }
  if (issue.can_contractor_respond) {
    return { key: 'action_required', label: 'Action required', colorScheme: 'orange' };
  }
  return { key: 'under_review', label: 'Under review', colorScheme: 'purple' };
};

export type ContractorInlineRevisionWorkspace = {
  data: RevisionTrackerData | null;
  issues: RevisionIssue[];
  loading: boolean;
  error: string;
  busy: boolean;
  draftFor: (issue: RevisionIssue) => ContractorDraft;
  setDraft: (issueId: string, patch: Partial<ContractorDraft>) => void;
  savedResponseFor: (issue: RevisionIssue) => RevisionIssueComment | undefined;
  isEditing: (issue: RevisionIssue) => boolean;
  beginEditing: (issue: RevisionIssue) => void;
  cancelEditing: (issue: RevisionIssue) => void;
  save: (issue: RevisionIssue) => Promise<void>;
  saveAll: () => Promise<boolean>;
};

type WorkspaceArgs = {
  invoiceId: string;
  refreshToken?: number;
  onTrackerChange?: (data: RevisionTrackerData) => void;
  onDraftStateChange?: (state: ContractorDraftState) => void;
};

export const useContractorInlineRevisionWorkspace = ({
  invoiceId,
  refreshToken = 0,
  onTrackerChange,
  onDraftStateChange,
}: WorkspaceArgs): ContractorInlineRevisionWorkspace => {
  const toast = useToast();
  const [data, setData] = useState<RevisionTrackerData | null>(null);
  const [drafts, setDrafts] = useState<Record<string, ContractorDraft>>({});
  const [editingIssueIds, setEditingIssueIds] = useState<Set<string>>(() => new Set());
  const [loading, setLoading] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const endpoint = `/api/claims/contractor/invoices/${encodeURIComponent(invoiceId)}/revision_issues`;

  const adoptData = useCallback(
    (next: RevisionTrackerData, preserveDraftsExceptIssueId?: string) => {
      setDrafts((current) => {
        const nextDrafts: Record<string, ContractorDraft> = {};
        next.issues.forEach((issue) => {
          const saved = [...issue.comments]
            .reverse()
            .find(
              (comment) => comment.author_type === 'contractor' && comment.revision_round_id === next.latest_round_id,
            );
          nextDrafts[issue.id] = responseDraft(saved);
          if (preserveDraftsExceptIssueId && issue.id !== preserveDraftsExceptIssueId && current[issue.id]) {
            nextDrafts[issue.id] = current[issue.id];
          }
        });
        return nextDrafts;
      });
      setData(next);
      setError('');
      onTrackerChange?.(next);
    },
    [onTrackerChange],
  );

  const load = useCallback(async () => {
    if (!invoiceId) {
      setData(null);
      return;
    }
    setLoading(true);
    try {
      const response = await fetch(endpoint, { credentials: 'include', headers: { Accept: 'application/json' } });
      const json = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(json?.error || 'Could not load requested changes.');
      adoptData(json as RevisionTrackerData);
    } catch (reason: any) {
      setError(reason?.message || 'Could not load requested changes.');
      setData(null);
    } finally {
      setLoading(false);
    }
  }, [adoptData, endpoint, invoiceId]);

  useEffect(() => {
    void load();
  }, [load, refreshToken]);

  const currentContractorComment = useCallback(
    (issue: RevisionIssue) =>
      [...issue.comments]
        .reverse()
        .find((comment) => comment.author_type === 'contractor' && comment.revision_round_id === data?.latest_round_id),
    [data?.latest_round_id],
  );

  useEffect(() => {
    if (!data || !onDraftStateChange) return;
    const editable = data.issues.filter((issue) => issue.can_contractor_respond);
    onDraftStateChange({
      allEditableDraftsComplete: editable.every((issue) => draftComplete(issue, drafts[issue.id] || EMPTY_DRAFT)),
      hasUnsavedChanges: editable.some((issue) =>
        draftDiffers(drafts[issue.id] || EMPTY_DRAFT, currentContractorComment(issue)),
      ),
    });
  }, [currentContractorComment, data, drafts, onDraftStateChange]);

  const setDraft = useCallback((issueId: string, patch: Partial<ContractorDraft>) => {
    setDrafts((current) => ({
      ...current,
      [issueId]: { ...(current[issueId] || EMPTY_DRAFT), ...patch },
    }));
  }, []);

  const savedResponseFor = useCallback((issue: RevisionIssue) => currentComment(issue, data, 'contractor'), [data]);

  const beginEditing = useCallback((issue: RevisionIssue) => {
    setEditingIssueIds((current) => new Set(current).add(issue.id));
  }, []);

  const cancelEditing = useCallback(
    (issue: RevisionIssue) => {
      setDrafts((current) => ({ ...current, [issue.id]: responseDraft(savedResponseFor(issue)) }));
      setEditingIssueIds((current) => {
        const next = new Set(current);
        next.delete(issue.id);
        return next;
      });
      setError('');
    },
    [savedResponseFor],
  );

  const save = useCallback(
    async (issue: RevisionIssue) => {
      const draft = drafts[issue.id] || EMPTY_DRAFT;
      if (!draftComplete(issue, draft)) {
        const message =
          draft.method === 'attestation_provided' && issue.issue_type !== 'rule' && !draft.assertedValue.trim()
            ? 'Enter the value you are attesting to.'
            : 'Choose how you responded and enter a response comment.';
        setError(message);
        return;
      }

      setBusy(true);
      try {
        const response = await fetch(`${endpoint}/${encodeURIComponent(issue.id)}/comment`, {
          method: 'PATCH',
          credentials: 'include',
          headers: { Accept: 'application/json', 'Content-Type': 'application/json' },
          body: JSON.stringify({
            contractor_response_method: draft.method,
            comment_text: draft.text.trim(),
            contractor_asserted_value: draft.assertedValue.trim() || null,
          }),
        });
        const json = await response.json().catch(() => ({}));
        if (!response.ok) throw new Error(json?.error || 'Could not save the response.');
        adoptData(json as RevisionTrackerData, issue.id);
        setEditingIssueIds((current) => {
          const next = new Set(current);
          next.delete(issue.id);
          return next;
        });
        toast({ title: 'Response saved', status: 'success', duration: 3000, isClosable: true });
      } catch (reason: any) {
        const message = reason?.message || 'Could not save the response.';
        setError(message);
        toast({ title: 'Response not saved', description: message, status: 'error', duration: 5000, isClosable: true });
      } finally {
        setBusy(false);
      }
    },
    [adoptData, drafts, endpoint, toast],
  );

  const saveAll = useCallback(async (): Promise<boolean> => {
    if (!data) return true;

    const changedIssues = data.issues.filter(
      (issue) =>
        issue.can_contractor_respond && draftDiffers(drafts[issue.id] || EMPTY_DRAFT, currentContractorComment(issue)),
    );
    if (changedIssues.length === 0) return true;

    const incompleteIssues = changedIssues.filter((issue) => !draftComplete(issue, drafts[issue.id] || EMPTY_DRAFT));
    if (incompleteIssues.length > 0) {
      const message =
        incompleteIssues.length === 1
          ? 'Complete the response you started before finishing later.'
          : 'Complete the responses you started before finishing later.';
      setError(message);
      toast({ title: 'Responses not saved', description: message, status: 'error', duration: 5000, isClosable: true });
      return false;
    }

    setBusy(true);
    try {
      for (const issue of changedIssues) {
        const draft = drafts[issue.id] || EMPTY_DRAFT;
        const response = await fetch(`${endpoint}/${encodeURIComponent(issue.id)}/comment`, {
          method: 'PATCH',
          credentials: 'include',
          headers: { Accept: 'application/json', 'Content-Type': 'application/json' },
          body: JSON.stringify({
            contractor_response_method: draft.method,
            comment_text: draft.text.trim(),
            contractor_asserted_value: draft.assertedValue.trim() || null,
          }),
        });
        const json = await response.json().catch(() => ({}));
        if (!response.ok) throw new Error(json?.error || 'Could not save all responses.');
        adoptData(json as RevisionTrackerData, issue.id);
        setEditingIssueIds((current) => {
          const next = new Set(current);
          next.delete(issue.id);
          return next;
        });
      }
      toast({
        title: changedIssues.length === 1 ? 'Response saved' : 'Responses saved',
        status: 'success',
        duration: 3000,
        isClosable: true,
      });
      return true;
    } catch (reason: any) {
      const message = reason?.message || 'Could not save all responses.';
      setError(message);
      toast({ title: 'Responses not saved', description: message, status: 'error', duration: 5000, isClosable: true });
      return false;
    } finally {
      setBusy(false);
    }
  }, [adoptData, currentContractorComment, data, drafts, endpoint, toast]);

  return useMemo(
    () => ({
      data,
      issues: data?.issues || [],
      loading,
      error,
      busy,
      draftFor: (issue: RevisionIssue) => drafts[issue.id] || EMPTY_DRAFT,
      setDraft,
      savedResponseFor,
      isEditing: (issue: RevisionIssue) => editingIssueIds.has(issue.id),
      beginEditing,
      cancelEditing,
      save,
      saveAll,
    }),
    [
      beginEditing,
      busy,
      cancelEditing,
      data,
      drafts,
      editingIssueIds,
      error,
      loading,
      save,
      saveAll,
      savedResponseFor,
      setDraft,
    ],
  );
};

type CardProps = {
  issue: RevisionIssue;
  workspace: ContractorInlineRevisionWorkspace;
  attention?: boolean;
  compactHeading?: boolean;
};

export const ContractorInlineRevisionIssueCard = ({
  issue,
  workspace,
  attention = false,
  compactHeading = false,
}: CardProps) => {
  const draft = workspace.draftFor(issue);
  const presentation = contractorRevisionPresentationState(issue, workspace.data);
  const latestAdminRequest =
    currentComment(issue, workspace.data, 'admin') ||
    [...issue.comments].reverse().find((comment) => comment.author_type === 'admin');
  const savedResponse = workspace.savedResponseFor(issue);
  const displayedResponse =
    savedResponse ||
    (!issue.can_contractor_respond
      ? [...issue.comments].reverse().find((comment) => comment.author_type === 'contractor')
      : undefined);
  const editing = workspace.isEditing(issue);
  const showResponseForm = issue.can_contractor_respond && (!savedResponse || editing);
  const priorComments = issue.comments.filter(
    (comment) => comment.id !== latestAdminRequest?.id && comment.id !== displayedResponse?.id,
  );
  const needsAction = presentation.key === 'action_required' || presentation.key === 'upload_required';
  const requestedResponse = latestAdminRequest?.admin_recommended_remedy
    ? ADMIN_REMEDY_LABELS[latestAdminRequest.admin_recommended_remedy] ||
      pretty(latestAdminRequest.admin_recommended_remedy)
    : '';
  const savedResponseMethod = displayedResponse?.contractor_response_method
    ? CONTRACTOR_METHODS.find(([value]) => value === displayedResponse.contractor_response_method)?.[1] ||
      pretty(displayedResponse.contractor_response_method)
    : '';

  return (
    <Box
      mt={3}
      p={{ base: 3, md: 4 }}
      borderWidth="1px"
      borderColor={attention ? 'red.300' : needsAction ? 'orange.200' : 'gray.200'}
      borderRadius="lg"
      bg={attention ? 'red.50' : 'white'}
      boxShadow="sm"
    >
      {!compactHeading ? (
        <Text fontWeight="bold" color="blue.800" mb={3}>
          {issue.source.friendly_label || 'Requested change'}
        </Text>
      ) : null}

      {issue.disposition_comment ? (
        <Box mb={4} p={3} bg="green.50" borderLeftWidth="4px" borderLeftColor="green.400" borderRadius="md">
          <Text fontSize="xs" fontWeight="bold" color="green.800" mb={1}>
            Resolution
          </Text>
          <Text fontSize="sm" whiteSpace="pre-wrap">
            {issue.disposition_comment}
          </Text>
        </Box>
      ) : null}

      <Box>
        <Text fontSize="xs" fontWeight="bold" color="blue.800" textTransform="uppercase" letterSpacing="wide">
          Program team request
        </Text>
        {requestedResponse ? (
          <Text fontSize="xs" fontWeight="semibold" color="purple.700" mt={1}>
            Requested response: {requestedResponse}
          </Text>
        ) : null}
        {latestAdminRequest ? (
          <Text fontSize="sm" whiteSpace="pre-wrap" mt={2}>
            {latestAdminRequest.comment_text}
          </Text>
        ) : (
          <Text fontSize="sm" opacity={0.7} mt={2}>
            No program team request is available for this item.
          </Text>
        )}
      </Box>

      {displayedResponse && !editing ? (
        <Box mt={4} pt={4} borderTopWidth="1px" borderColor="gray.200">
          <Flex align="center" gap={2} wrap="wrap">
            <Text fontSize="xs" fontWeight="bold" color="blue.800" textTransform="uppercase" letterSpacing="wide">
              Your response
            </Text>
            {savedResponseMethod ? (
              <Text fontSize="xs" fontWeight="semibold" color="blue.700">
                {savedResponseMethod}
              </Text>
            ) : null}
            {issue.can_contractor_respond ? (
              <Button
                size="xs"
                variant="ghost"
                colorScheme="blue"
                ml="auto"
                onClick={() => workspace.beginEditing(issue)}
              >
                Edit response
              </Button>
            ) : null}
          </Flex>
          <Text fontSize="sm" whiteSpace="pre-wrap" mt={2}>
            {displayedResponse.comment_text}
          </Text>
          {displayedResponse.contractor_asserted_value ? (
            <Text fontSize="sm" mt={2}>
              Attested value: <strong>{displayedResponse.contractor_asserted_value}</strong>
            </Text>
          ) : null}
        </Box>
      ) : null}

      {showResponseForm ? (
        <Box mt={4} pt={4} borderTopWidth="1px" borderColor="gray.200">
          <Text fontSize="xs" fontWeight="bold" color="blue.800" textTransform="uppercase" letterSpacing="wide" mb={2}>
            Your response
          </Text>
          <Text fontSize="xs" fontWeight="semibold" mb={1}>
            How did you respond?
          </Text>
          <Select
            size="sm"
            value={draft.method}
            onChange={(event) => workspace.setDraft(issue.id, { method: event.target.value })}
          >
            <option value="" disabled>
              Choose how you responded
            </option>
            {CONTRACTOR_METHODS.map(([value, label]) => (
              <option key={value} value={value}>
                {label}
              </option>
            ))}
          </Select>
          {draft.method === 'attestation_provided' && issue.issue_type !== 'rule' ? (
            <Box mt={3}>
              <Text fontSize="xs" fontWeight="semibold" mb={1}>
                Attested value
              </Text>
              <Textarea
                size="sm"
                rows={2}
                placeholder="Value you are attesting to"
                value={draft.assertedValue}
                onChange={(event) => workspace.setDraft(issue.id, { assertedValue: event.target.value })}
              />
            </Box>
          ) : null}
          <Box mt={3}>
            <Text fontSize="xs" fontWeight="semibold" mb={1}>
              Response details
            </Text>
            <Textarea
              size="sm"
              rows={3}
              placeholder="Explain your response"
              value={draft.text}
              onChange={(event) => workspace.setDraft(issue.id, { text: event.target.value })}
            />
          </Box>
          <Flex justify="flex-end" gap={2} mt={3}>
            {savedResponse ? (
              <Button size="sm" variant="ghost" onClick={() => workspace.cancelEditing(issue)}>
                Cancel
              </Button>
            ) : null}
            <Button size="sm" colorScheme="blue" isLoading={workspace.busy} onClick={() => void workspace.save(issue)}>
              Save response
            </Button>
          </Flex>
        </Box>
      ) : null}

      {priorComments.length > 0 ? (
        <Accordion allowToggle mt={4}>
          <AccordionItem border="0" borderTopWidth="1px" borderColor="gray.200">
            <h3>
              <AccordionButton px={0} py={3} _hover={{ bg: 'transparent' }}>
                <Text flex="1" textAlign="left" fontSize="xs" fontWeight="semibold" color="gray.700">
                  Previous exchanges ({priorComments.length})
                </Text>
                <AccordionIcon />
              </AccordionButton>
            </h3>
            <AccordionPanel px={0} pt={0} pb={0}>
              <Flex direction="column" gap={2}>
                {priorComments.map((comment) => (
                  <Box key={comment.id} bg="gray.50" borderRadius="md" p={3}>
                    <Flex align="center" gap={2} wrap="wrap" mb={1}>
                      <Badge colorScheme={comment.author_type === 'admin' ? 'purple' : 'blue'}>
                        {comment.author_type === 'admin' ? 'Program team' : 'You'}
                      </Badge>
                      <Text fontSize="xs" opacity={0.7}>
                        Exchange {comment.round_number}
                      </Text>
                    </Flex>
                    <Text fontSize="sm" whiteSpace="pre-wrap">
                      {comment.comment_text}
                    </Text>
                    {comment.contractor_asserted_value ? (
                      <Text fontSize="sm" mt={1}>
                        Attested value: <strong>{comment.contractor_asserted_value}</strong>
                      </Text>
                    ) : null}
                  </Box>
                ))}
              </Flex>
            </AccordionPanel>
          </AccordionItem>
        </Accordion>
      ) : null}
    </Box>
  );
};

export const ContractorInlineRevisionStatus = ({ workspace }: { workspace: ContractorInlineRevisionWorkspace }) => {
  if (workspace.loading) {
    return (
      <Flex align="center" gap={2} py={2}>
        <Spinner size="sm" />
        <Text fontSize="sm">Loading requested changes...</Text>
      </Flex>
    );
  }
  if (!workspace.error) return null;
  return (
    <Box p={3} borderWidth="1px" borderColor="red.200" bg="red.50" borderRadius="md">
      <Text color="red.700" fontSize="sm">
        {workspace.error}
      </Text>
    </Box>
  );
};
