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

const historicalCommentChoice = (comment: RevisionIssueComment): { label: string; value: string } | null => {
  if (comment.author_type === 'admin' && comment.admin_recommended_remedy) {
    return {
      label: 'Requested response',
      value: ADMIN_REMEDY_LABELS[comment.admin_recommended_remedy] || pretty(comment.admin_recommended_remedy),
    };
  }

  if (comment.author_type === 'contractor' && comment.contractor_response_method) {
    return {
      label: 'Response method',
      value:
        CONTRACTOR_METHODS.find(([value]) => value === comment.contractor_response_method)?.[1] ||
        pretty(comment.contractor_response_method),
    };
  }

  return null;
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
          ? 'Complete the response you started before continuing.'
          : 'Complete the responses you started before continuing.';
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
  integratedConversation?: boolean;
  recommendation?: string | null;
  recommendationAt?: string | null;
  recommendationSource?: React.ReactNode;
};

export const ContractorInlineRevisionIssueCard = ({
  issue,
  workspace,
  attention = false,
  compactHeading = false,
  integratedConversation = false,
  recommendation,
  recommendationAt,
  recommendationSource,
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
  const historicalRounds = Array.from(
    priorComments
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
  const needsAction = presentation.key === 'action_required' || presentation.key === 'upload_required';
  const savedResponseMethod = displayedResponse?.contractor_response_method
    ? CONTRACTOR_METHODS.find(([value]) => value === displayedResponse.contractor_response_method)?.[1] ||
      pretty(displayedResponse.contractor_response_method)
    : '';

  return (
    <Box
      mt={3}
      p={integratedConversation ? 0 : { base: 3, md: 4 }}
      borderWidth={integratedConversation ? 0 : '1px'}
      borderColor={attention ? 'red.300' : needsAction ? 'orange.200' : 'gray.200'}
      borderRadius={integratedConversation ? 0 : 'lg'}
      bg={integratedConversation ? 'transparent' : attention ? 'red.50' : 'white'}
      boxShadow={integratedConversation ? 'none' : 'sm'}
    >
      {!compactHeading ? (
        <Text fontWeight="bold" color="blue.800" mb={3}>
          {issue.source.friendly_label || 'Requested change'}
        </Text>
      ) : null}

      {issue.disposition_comment ? (
        <Box
          mb={4}
          p={integratedConversation ? 0 : 3}
          bg={integratedConversation ? 'transparent' : 'green.50'}
          borderLeftWidth={integratedConversation ? 0 : '4px'}
          borderLeftColor="green.400"
          borderRadius={integratedConversation ? 0 : 'md'}
        >
          <Text fontSize="md" fontWeight="bold" color="green.800" mb={1}>
            Resolution
          </Text>
          <Text fontSize="md" whiteSpace="pre-wrap">
            {issue.disposition_comment}
          </Text>
        </Box>
      ) : null}

      {integratedConversation && (recommendation || historicalRounds.length > 0) ? (
        <Box ml={{ base: 6, md: 12 }} mb={4} py={2}>
          {recommendation ? (
            <Flex
              direction="column"
              ml={1}
              mb={historicalRounds.length > 0 ? 5 : 0}
              borderLeftWidth="4px"
              borderLeftColor="orange.200"
            >
              <Box position="relative" pl={5} pb={1}>
                <Box
                  aria-hidden="true"
                  position="absolute"
                  top="2px"
                  left="-7px"
                  w="10px"
                  h="10px"
                  bg="orange.200"
                  borderRadius="full"
                />
                <Flex align="center" gap={2} wrap="wrap" mb={1}>
                  <Badge bg="#F7F9FC" borderWidth="1px" borderColor="#053662" color="#2D2D2D" fontSize="md">
                    System
                  </Badge>
                  <Text fontSize="md" opacity={0.7}>
                    {formatCommentDateTime(recommendationAt)}
                  </Text>
                </Flex>
                <Text fontSize="md" whiteSpace="pre-wrap">
                  Recommendation: {recommendation} {recommendationSource}
                </Text>
              </Box>
            </Flex>
          ) : null}
          {historicalRounds.map((round) => (
            <Box key={round.id} mb={5}>
              <Text fontSize="md" fontWeight="bold" color="#2D2D2D" mb={2}>
                Round {round.number}
              </Text>
              <Flex direction="column" ml={1} borderLeftWidth="4px" borderLeftColor="orange.200">
                {round.comments.map((comment) => {
                  const choice = historicalCommentChoice(comment);

                  return (
                    <Box key={comment.id} position="relative" pl={5} pb={5} _last={{ pb: 1 }}>
                      <Box
                        aria-hidden="true"
                        position="absolute"
                        top="2px"
                        left="-7px"
                        w="10px"
                        h="10px"
                        bg="orange.200"
                        borderRadius="full"
                      />
                      <Flex align="center" gap={2} wrap="wrap" mb={1}>
                        <Badge bg="#F7F9FC" borderWidth="1px" borderColor="#053662" color="#2D2D2D" fontSize="md">
                          {comment.author_type === 'admin' ? 'Admin' : 'You'}
                        </Badge>
                        <Text fontSize="md" opacity={0.7}>
                          {formatCommentDateTime(comment.created_at)}
                        </Text>
                      </Flex>
                      {choice ? (
                        <Text fontSize="md" fontWeight="semibold" color="#2D2D2D" mb={1}>
                          {choice.label}: {choice.value}
                        </Text>
                      ) : null}
                      <Text fontSize="md" whiteSpace="pre-wrap">
                        {comment.comment_text}
                      </Text>
                      {comment.contractor_asserted_value ? (
                        <Text fontSize="md" mt={1}>
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

      {!integratedConversation ? (
        <Box>
          <Text fontSize="md" fontWeight="bold" color="blue.800" textTransform="uppercase" letterSpacing="wide">
            Admin request
          </Text>
          {latestAdminRequest?.admin_recommended_remedy ? (
            <Text fontSize="md" fontWeight="semibold" color="#2D2D2D" mt={1}>
              Requested response:{' '}
              {ADMIN_REMEDY_LABELS[latestAdminRequest.admin_recommended_remedy] ||
                pretty(latestAdminRequest.admin_recommended_remedy)}
            </Text>
          ) : null}
          {latestAdminRequest ? (
            <Text fontSize="md" whiteSpace="pre-wrap" mt={2}>
              {latestAdminRequest.comment_text}
            </Text>
          ) : (
            <Text fontSize="md" opacity={0.7} mt={2}>
              No admin request is available for this item.
            </Text>
          )}
        </Box>
      ) : null}

      {(integratedConversation && latestAdminRequest) || (displayedResponse && !editing) || showResponseForm ? (
        <Box
          p={integratedConversation ? 3 : 0}
          bg={integratedConversation ? 'white' : 'transparent'}
          borderWidth={integratedConversation ? '1px' : 0}
          borderColor={integratedConversation ? '#D8D8D8' : 'transparent'}
          borderRadius={integratedConversation ? 'md' : 0}
        >
          {integratedConversation && latestAdminRequest ? (
            <Box
              pb={(displayedResponse && !editing) || showResponseForm ? 4 : 0}
              mb={(displayedResponse && !editing) || showResponseForm ? 4 : 0}
              borderBottomWidth={(displayedResponse && !editing) || showResponseForm ? '1px' : 0}
              borderColor="gray.200"
            >
              <Text fontSize="md" fontWeight="bold" color="#2D2D2D" mb={2}>
                Round {latestAdminRequest.round_number}
              </Text>
              <Flex align="center" gap={2} wrap="wrap" mb={1}>
                <Badge bg="#F7F9FC" borderWidth="1px" borderColor="#053662" color="#2D2D2D" fontSize="md">
                  Admin
                </Badge>
                <Text fontSize="md" opacity={0.7}>
                  {formatCommentDateTime(latestAdminRequest.created_at)}
                </Text>
              </Flex>
              {latestAdminRequest.admin_recommended_remedy ? (
                <Text fontSize="md" fontWeight="semibold" color="#2D2D2D" mb={1}>
                  Requested response:{' '}
                  {ADMIN_REMEDY_LABELS[latestAdminRequest.admin_recommended_remedy] ||
                    pretty(latestAdminRequest.admin_recommended_remedy)}
                </Text>
              ) : null}
              <Text fontSize="md" whiteSpace="pre-wrap">
                {latestAdminRequest.comment_text}
              </Text>
            </Box>
          ) : null}

          {displayedResponse && !editing ? (
            <Box
              mt={integratedConversation ? 0 : 4}
              pt={integratedConversation ? 0 : 4}
              borderTopWidth={integratedConversation ? 0 : '1px'}
              borderColor="gray.200"
            >
              <Flex align="center" gap={2} wrap="wrap">
                {integratedConversation ? (
                  <>
                    <Badge bg="#F7F9FC" borderWidth="1px" borderColor="#053662" color="#2D2D2D" fontSize="md">
                      You
                    </Badge>
                    <Text fontSize="md" opacity={0.7}>
                      {formatCommentDateTime(displayedResponse.created_at)}
                    </Text>
                  </>
                ) : (
                  <Text fontSize="md" fontWeight="bold" color="blue.800" textTransform="uppercase" letterSpacing="wide">
                    Your response
                  </Text>
                )}
                {savedResponseMethod ? (
                  <Text fontSize="md" fontWeight="semibold" color="blue.700">
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
              <Text fontSize="md" whiteSpace="pre-wrap" mt={2}>
                {displayedResponse.comment_text}
              </Text>
              {displayedResponse.contractor_asserted_value ? (
                <Text fontSize="md" mt={2}>
                  Attested value: <strong>{displayedResponse.contractor_asserted_value}</strong>
                </Text>
              ) : null}
            </Box>
          ) : null}

          {showResponseForm ? (
            <Box
              mt={displayedResponse && !editing ? 4 : integratedConversation ? 0 : 4}
              pt={displayedResponse && !editing ? 4 : integratedConversation ? 0 : 4}
              borderTopWidth={displayedResponse && !editing ? '1px' : integratedConversation ? 0 : '1px'}
              borderColor="gray.200"
            >
              <Text
                fontSize="md"
                fontWeight="bold"
                color="blue.800"
                textTransform="uppercase"
                letterSpacing="wide"
                mb={2}
              >
                Your response
              </Text>
              <Text fontSize="md" fontWeight="semibold" mb={1}>
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
                  <Text fontSize="md" fontWeight="semibold" mb={1}>
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
                <Text fontSize="md" fontWeight="semibold" mb={1}>
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
              <Flex justify="flex-start" gap={2} mt={3}>
                {savedResponse ? (
                  <Button size="sm" variant="ghost" onClick={() => workspace.cancelEditing(issue)}>
                    Cancel
                  </Button>
                ) : null}
                <Button
                  size="sm"
                  variant="primary"
                  isLoading={workspace.busy}
                  onClick={() => void workspace.save(issue)}
                >
                  Save response
                </Button>
              </Flex>
            </Box>
          ) : null}
        </Box>
      ) : null}

      {!integratedConversation && priorComments.length > 0 ? (
        <Accordion allowToggle mt={4}>
          <AccordionItem border="0" borderTopWidth="1px" borderColor="gray.200">
            <h3>
              <AccordionButton px={0} py={3} _hover={{ bg: 'transparent' }}>
                <Text flex="1" textAlign="left" fontSize="lg" fontWeight="semibold" color="gray.700">
                  Conversation history ({priorComments.length})
                </Text>
                <AccordionIcon />
              </AccordionButton>
            </h3>
            <AccordionPanel px={0} pt={0} pb={0}>
              <Flex direction="column" gap={2}>
                {priorComments.map((comment) => {
                  const choice = historicalCommentChoice(comment);

                  return (
                    <Box key={comment.id} bg="gray.50" borderRadius="md" p={3}>
                      <Flex align="center" gap={2} wrap="wrap" mb={1}>
                        <Badge colorScheme={comment.author_type === 'admin' ? 'purple' : 'blue'} fontSize="md">
                          {comment.author_type === 'admin' ? 'Admin' : 'You'}
                        </Badge>
                        <Text fontSize="md" opacity={0.7}>
                          {formatCommentDateTime(comment.created_at)}
                        </Text>
                      </Flex>
                      {choice ? (
                        <Text fontSize="md" fontWeight="semibold" color="#2D2D2D" mb={1}>
                          {choice.label}: {choice.value}
                        </Text>
                      ) : null}
                      <Text fontSize="md" whiteSpace="pre-wrap">
                        {comment.comment_text}
                      </Text>
                      {comment.contractor_asserted_value ? (
                        <Text fontSize="md" mt={1}>
                          Attested value: <strong>{comment.contractor_asserted_value}</strong>
                        </Text>
                      ) : null}
                    </Box>
                  );
                })}
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
      <Badge colorScheme="gray" display="inline-flex" alignItems="center" gap={1} fontSize="md">
        <Spinner size="xs" />
        Loading responses
      </Badge>
    );
  }
  if (workspace.error) {
    return (
      <Badge colorScheme="red" fontSize="md">
        Response status unavailable
      </Badge>
    );
  }

  const editable = workspace.issues.filter((issue) => issue.can_contractor_respond);
  if (!editable.length) return null;
  const saved = editable.filter((issue) => {
    const draft = workspace.draftFor(issue);
    const response = workspace.savedResponseFor(issue);
    return !!response && draftComplete(issue, draft) && !draftDiffers(draft, response);
  }).length;
  const unsaved = editable.filter((issue) => {
    const response = workspace.savedResponseFor(issue);
    return draftDiffers(workspace.draftFor(issue), response);
  }).length;

  return (
    <Badge colorScheme={unsaved ? 'yellow' : saved === editable.length ? 'green' : 'blue'} fontSize="md">
      {saved} of {editable.length} responses saved
    </Badge>
  );
};
