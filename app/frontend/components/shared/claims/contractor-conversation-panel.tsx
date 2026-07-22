import { Box, Button, Flex, IconButton, Spinner, Text, Textarea, Tooltip, useToast } from '@chakra-ui/react';
import { PaperPlaneTilt } from '@phosphor-icons/react';
import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { fmtDate } from '../../domains/invoice-versions/display';

type MessageRow = {
  id: string;
  invoice_versionno?: number | null;
  revreq_seqno?: number | null;
  message_type?: string | null;
  request_text?: string | null;
  created_at?: string | null;
  updated_at?: string | null;
};

type ContractorConversationPanelProps = {
  invoiceId?: string | null;
  messageListMaxHeight?: string;
  showConversationHeading?: boolean;
  showGuidance?: boolean;
  inlineComposerSend?: boolean;
  active?: boolean;
  onUnreadCountChange?: (count: number) => void;
  pollIntervalMs?: number;
};

type LoadRowsOptions = {
  silent?: boolean;
  markAsRead?: boolean;
};

const isContractorMessage = (type: unknown): boolean => String(type || '').trim() === 'contractor_note';

const messageTypeLabel = (type: unknown): string => {
  const value = String(type || '').trim();
  return value === 'contractor_note' ? 'You' : 'Admin';
};

export const ContractorConversationPanel = ({
  invoiceId,
  messageListMaxHeight = '320px',
  showConversationHeading = true,
  showGuidance = true,
  inlineComposerSend = false,
  active = true,
  onUnreadCountChange,
  pollIntervalMs = 15000,
}: ContractorConversationPanelProps) => {
  const toast = useToast();
  const [rows, setRows] = useState<MessageRow[]>([]);
  const [loading, setLoading] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [messageText, setMessageText] = useState('');
  const activeRef = useRef(active);
  const onUnreadCountChangeRef = useRef(onUnreadCountChange);
  const loadInFlightRef = useRef(false);
  const messageListRef = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    activeRef.current = active;
  }, [active]);

  useEffect(() => {
    onUnreadCountChangeRef.current = onUnreadCountChange;
  }, [onUnreadCountChange]);

  const chatRows = useMemo(
    () =>
      [...rows].sort((a, b) =>
        String(a.created_at || a.updated_at || '').localeCompare(String(b.created_at || b.updated_at || '')),
      ),
    [rows],
  );

  useEffect(() => {
    if (!active || chatRows.length === 0) return;

    const frameId = window.requestAnimationFrame(() => {
      const messageList = messageListRef.current;
      if (messageList) messageList.scrollTop = messageList.scrollHeight;
    });

    return () => window.cancelAnimationFrame(frameId);
  }, [active, chatRows.length]);

  const markMessagesRead = useCallback(
    async (throughSeqno: number) => {
      if (!invoiceId || throughSeqno <= 0) return;
      const response = await fetch(
        `/api/claims/contractor/invoices/${encodeURIComponent(invoiceId)}/conversation_messages/read`,
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
          credentials: 'include',
          body: JSON.stringify({ through_seqno: throughSeqno }),
        },
      );
      const json = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(json?.error || `Could not mark messages read (${response.status}).`);
      onUnreadCountChangeRef.current?.(Math.max(0, Number(json?.unread_count) || 0));
    },
    [invoiceId],
  );

  const loadRows = useCallback(
    async ({ silent = false, markAsRead = activeRef.current }: LoadRowsOptions = {}) => {
      if (!invoiceId || loadInFlightRef.current) return;
      loadInFlightRef.current = true;
      if (!silent) setLoading(true);
      try {
        const response = await fetch(
          `/api/claims/contractor/invoices/${encodeURIComponent(invoiceId)}/conversation_messages`,
          {
            headers: { Accept: 'application/json' },
            credentials: 'include',
          },
        );
        const json = await response.json().catch(() => ({}));
        if (!response.ok) throw new Error(json?.error || `Could not load messages (${response.status}).`);
        setRows(Array.isArray(json?.rows) ? json.rows : []);
        setError('');
        const unreadCount = Math.max(0, Number(json?.unread_count) || 0);
        const latestAdminSeqno = Math.max(0, Number(json?.latest_admin_seqno) || 0);
        onUnreadCountChangeRef.current?.(unreadCount);
        // Re-check the live panel state after the request completes. This covers
        // the small race where the contractor opens chat while a background poll
        // is already in flight.
        if ((markAsRead || activeRef.current) && unreadCount > 0 && latestAdminSeqno > 0) {
          try {
            await markMessagesRead(latestAdminSeqno);
          } catch (caught) {
            console.error('[Contractor Chat] Could not mark messages read.', caught);
          }
        }
      } catch (caught: any) {
        if (!silent) {
          setError(caught?.message || 'Could not load messages.');
          setRows([]);
        }
      } finally {
        loadInFlightRef.current = false;
        if (!silent) setLoading(false);
      }
    },
    [invoiceId, markMessagesRead],
  );

  useEffect(() => {
    setRows([]);
    setMessageText('');
    void loadRows();
  }, [loadRows]);

  useEffect(() => {
    if (!active || !invoiceId) return;
    void loadRows({ silent: true, markAsRead: true });
  }, [active, invoiceId, loadRows]);

  useEffect(() => {
    if (!invoiceId || pollIntervalMs <= 0) return;
    const refreshIfVisible = () => {
      if (document.visibilityState !== 'visible') return;
      void loadRows({ silent: true, markAsRead: activeRef.current });
    };
    const refreshWhenVisible = () => {
      if (document.visibilityState === 'visible') refreshIfVisible();
    };
    const intervalId = window.setInterval(refreshIfVisible, pollIntervalMs);
    window.addEventListener('focus', refreshIfVisible);
    document.addEventListener('visibilitychange', refreshWhenVisible);
    return () => {
      window.clearInterval(intervalId);
      window.removeEventListener('focus', refreshIfVisible);
      document.removeEventListener('visibilitychange', refreshWhenVisible);
    };
  }, [invoiceId, loadRows, pollIntervalMs]);

  const sendMessage = async () => {
    if (!invoiceId) return;
    const text = messageText.trim();
    if (!text) {
      setError('Please enter a message before sending.');
      return;
    }

    setSaving(true);
    setError('');
    try {
      const response = await fetch(
        `/api/claims/contractor/invoices/${encodeURIComponent(invoiceId)}/conversation_messages`,
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
          credentials: 'include',
          body: JSON.stringify({ request_text: text }),
        },
      );
      const json = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(json?.error || `Could not send message (${response.status}).`);
      setMessageText('');
      toast({
        title: 'Message sent',
        description: 'Admins will see this message when they review the invoice.',
        status: 'success',
        duration: 5000,
        isClosable: true,
      });
      await loadRows({ silent: true, markAsRead: activeRef.current });
    } catch (caught: any) {
      setError(caught?.message || 'Could not send message.');
    } finally {
      setSaving(false);
    }
  };

  return (
    <Box>
      {error ? (
        <Box mb={4} p={3} borderWidth="1px" borderColor="red.200" bg="red.50" borderRadius="md">
          <Text color="red.700" fontSize="sm">
            {error}
          </Text>
        </Box>
      ) : null}

      {showConversationHeading ? (
        <Text fontWeight="bold" mb={3}>
          Conversation
        </Text>
      ) : null}

      {loading ? (
        <Flex align="center" gap={3} p={4}>
          <Spinner size="sm" />
          <Text>Loading messages...</Text>
        </Flex>
      ) : rows.length > 0 ? (
        <Flex
          ref={messageListRef}
          direction="column"
          gap={3}
          p={4}
          borderWidth="1px"
          borderRadius="xl"
          bg="gray.50"
          maxH={messageListMaxHeight}
          overflowY="auto"
        >
          {chatRows.map((row) => (
            <Flex
              key={row.id}
              direction="column"
              align={isContractorMessage(row.message_type) ? 'flex-end' : 'flex-start'}
            >
              <Text fontSize="xs" color="gray.500" mb={1} px={1}>
                {messageTypeLabel(row.message_type)} | Version {row.invoice_versionno ?? '-'} |{' '}
                {fmtDate(row.updated_at || row.created_at)}
              </Text>
              <Box
                maxW="92%"
                px={4}
                py={3}
                borderRadius="2xl"
                borderTopRightRadius={isContractorMessage(row.message_type) ? 'md' : '2xl'}
                borderTopLeftRadius={isContractorMessage(row.message_type) ? '2xl' : 'md'}
                bg={isContractorMessage(row.message_type) ? 'blue.500' : 'white'}
                color={isContractorMessage(row.message_type) ? 'white' : 'gray.800'}
                borderWidth={isContractorMessage(row.message_type) ? '0' : '1px'}
                borderColor="gray.200"
                boxShadow="sm"
              >
                <Text whiteSpace="pre-wrap" fontSize="sm">
                  {row.request_text || 'No message text provided.'}
                </Text>
              </Box>
            </Flex>
          ))}
        </Flex>
      ) : showGuidance ? (
        <Box p={6} borderWidth="1px" borderRadius="xl" bg="gray.50" textAlign="center">
          <Text fontSize="sm" opacity={0.7}>
            No messages yet. If there is something admins should know, send the first message below.
          </Text>
        </Box>
      ) : null}

      <Box
        mt={rows.length > 0 || showGuidance ? 5 : 0}
        p={4}
        borderWidth="1px"
        borderRadius="xl"
        bg="white"
        borderColor="gray.200"
      >
        {showGuidance ? (
          <>
            <Text fontWeight="bold" mb={1}>
              Send a message to admins
            </Text>
            <Text fontSize="sm" opacity={0.75} mb={3}>
              Use this if you want to explain something before submitting, or if an admin asked for clarification. If
              the invoice itself is wrong, upload a corrected invoice instead of only sending a note.
            </Text>
          </>
        ) : null}
        <Box position="relative">
          <Textarea
            value={messageText}
            onChange={(event) => setMessageText(event.target.value)}
            onKeyDown={(event) => {
              if (!inlineComposerSend || event.key !== 'Enter' || event.shiftKey || event.nativeEvent.isComposing)
                return;
              event.preventDefault();
              if (!saving) void sendMessage();
            }}
            placeholder="Type your message..."
            rows={4}
            bg="gray.50"
            borderRadius="xl"
            pr={inlineComposerSend ? 12 : undefined}
            pb={inlineComposerSend ? 10 : undefined}
          />
          {inlineComposerSend ? (
            <Tooltip label="Send message" hasArrow>
              <IconButton
                aria-label="Send message"
                icon={<PaperPlaneTilt size={14} weight="fill" />}
                size="xs"
                colorScheme="blue"
                borderRadius="full"
                position="absolute"
                right="8px"
                bottom="8px"
                zIndex={2}
                isLoading={saving}
                isDisabled={!messageText.trim()}
                onClick={() => void sendMessage()}
              />
            </Tooltip>
          ) : null}
        </Box>
        {!inlineComposerSend ? (
          <Flex justify="flex-end" mt={3}>
            <Button colorScheme="blue" onClick={() => void sendMessage()} isLoading={saving}>
              Send
            </Button>
          </Flex>
        ) : null}
      </Box>
    </Box>
  );
};
