import React, { useEffect, useMemo, useState } from 'react';
import { Badge, Box, Flex, IconButton, Spinner, Text, Textarea, Tooltip, useToast } from '@chakra-ui/react';
import { ArrowsClockwise, FloppyDiskBack, PaperPlaneTilt, X } from '@phosphor-icons/react';
import { useMst } from '../../../setup/root';

type ConversationMessageGridRow = {
  contractor_business_name?: string | null;
  invoice_versionno?: number | null;
  di_ocr_invoice_id?: string | null;
  conversation_message_id?: string | null;
  conversation_message_seqno?: number | null;
  conversation_message_type?: string | null;
  conversation_message_text?: string | null;
  conversation_message_created_at?: string | null;
  conversation_message_updated_at?: string | null;
};

type ConversationMessageGridResponse = {
  rows: ConversationMessageGridRow[];
};

type InternalNoteRow = {
  id: string;
  admin_user_id: string;
  admin_user_name?: string | null;
  note_text: string;
  created_at?: string | null;
};

type InternalNotesResponse = {
  rows: InternalNoteRow[];
};

type AdminInvoicePanelProps = {
  invoiceId: string;
  latestInvoiceVersionId?: string;
  contractorBusinessName?: string;
  diOcrInvoiceId?: string;
  onClose?: () => void;
  showContext?: boolean;
};

const fmtDate = (value?: string | null) => {
  if (!value) return '-';
  const raw = String(value);
  return raw.includes('T') ? raw.split('T')[0] : raw.slice(0, 10);
};

const fmtDateTime = (value?: string | null) => {
  if (!value) return '-';
  const raw = String(value);
  return raw.includes('T') ? raw.replace('T', ' ').slice(0, 16) : raw;
};

const isAdminMessage = (type?: string | null) => String(type || '').trim() !== 'contractor_note';

const PanelHeader = ({
  title,
  audience,
  audienceColor,
  refreshing,
  onRefresh,
  onClose,
}: {
  title: string;
  audience: string;
  audienceColor: string;
  refreshing: boolean;
  onRefresh: () => void;
  onClose?: () => void;
}) => (
  <Flex align="center" justify="space-between" gap={3} mb={4}>
    <Box minW={0}>
      <Text fontSize="md" fontWeight="bold">
        {title}
      </Text>
      <Badge colorScheme={audienceColor} textTransform="none" mt={1}>
        {audience}
      </Badge>
    </Box>
    <Flex align="center" gap={1}>
      <Tooltip label={`Refresh ${title.toLowerCase()}`}>
        <IconButton
          aria-label={`Refresh ${title.toLowerCase()}`}
          icon={<ArrowsClockwise size={18} />}
          size="sm"
          variant="ghost"
          onClick={onRefresh}
          isLoading={refreshing}
        />
      </Tooltip>
      {onClose ? (
        <Tooltip label={`Close ${title.toLowerCase()}`}>
          <IconButton
            aria-label={`Close ${title.toLowerCase()}`}
            icon={<X size={18} weight="bold" />}
            size="sm"
            variant="ghost"
            onClick={onClose}
          />
        </Tooltip>
      ) : null}
    </Flex>
  </Flex>
);

const InvoiceContext = ({ contractorBusinessName, diOcrInvoiceId }: AdminInvoicePanelProps) => {
  if (!contractorBusinessName && !diOcrInvoiceId) return null;

  return (
    <Box borderWidth="1px" borderColor="gray.200" borderRadius="md" bg="gray.50" p={3} mb={4}>
      <Text fontSize="xs" color="gray.500">
        {contractorBusinessName || 'Unknown contractor'}
      </Text>
      <Text fontSize="sm" fontWeight="semibold">
        Invoice {diOcrInvoiceId || '-'}
      </Text>
    </Box>
  );
};

export const AdminConversationPanel = ({
  invoiceId,
  latestInvoiceVersionId: suppliedLatestInvoiceVersionId = '',
  contractorBusinessName = '',
  diOcrInvoiceId = '',
  onClose,
  showContext = true,
}: AdminInvoicePanelProps) => {
  const toast = useToast();
  const { userStore } = useMst();
  const currentUserId = (userStore as any)?.currentUser?.id ? String((userStore as any).currentUser.id) : '';
  const [rows, setRows] = useState<ConversationMessageGridRow[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const [messageText, setMessageText] = useState('');
  const [saving, setSaving] = useState(false);
  const [latestInvoiceVersionId, setLatestInvoiceVersionId] = useState(suppliedLatestInvoiceVersionId);

  const markContractorMessagesRead = async (throughSeqno: number) => {
    if (!invoiceId.trim() || throughSeqno <= 0) return;
    const response = await fetch(
      `/api/claims/admin/invoices/${encodeURIComponent(invoiceId.trim())}/conversation_messages/read`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
        credentials: 'include',
        body: JSON.stringify({ through_seqno: throughSeqno }),
      },
    );
    const data = await response.json().catch(() => ({}));
    if (!response.ok) throw new Error(data?.error || `Could not mark contractor messages read (${response.status}).`);
  };

  const fetchRows = async () => {
    setLoading(true);
    setError('');
    try {
      const params = new URLSearchParams({
        sort: 'conversation_message_updated_at:desc',
        page: '1',
        per: '100',
      });
      if (invoiceId.trim()) params.set('invoice_id', invoiceId.trim());

      const response = await fetch(`/api/claims/admin/conversation_messages?${params.toString()}`, {
        headers: { Accept: 'application/json' },
        credentials: 'include',
      });
      const data: ConversationMessageGridResponse = await response.json().catch(() => ({ rows: [] }));
      if (!response.ok) throw new Error((data as any)?.error || (data as any)?.message || `HTTP ${response.status}`);
      const nextRows = Array.isArray(data?.rows) ? data.rows : [];
      setRows(nextRows);
      const latestContractorSeqno = nextRows.reduce(
        (latest, row) =>
          row.conversation_message_type === 'contractor_note'
            ? Math.max(latest, Number(row.conversation_message_seqno) || 0)
            : latest,
        0,
      );
      if (latestContractorSeqno > 0) {
        try {
          await markContractorMessagesRead(latestContractorSeqno);
        } catch (markReadError) {
          console.error('[Admin Conversation] Could not mark contractor messages read.', markReadError);
        }
      }
    } catch (requestError: any) {
      setError(requestError?.message || 'Failed to load messages.');
      setRows([]);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    setMessageText('');
    void fetchRows();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [invoiceId]);

  useEffect(() => {
    setLatestInvoiceVersionId(suppliedLatestInvoiceVersionId);
    if (!invoiceId.trim() || suppliedLatestInvoiceVersionId) return;

    const fetchLatestInvoiceVersion = async () => {
      try {
        const response = await fetch(
          `/api/claims/admin/invoices/${encodeURIComponent(invoiceId.trim())}/invoice_versions?limit=1`,
          { headers: { Accept: 'application/json' }, credentials: 'include' },
        );
        const data = await response.json().catch(() => ({}));
        if (!response.ok) throw new Error(data?.error || data?.message || `HTTP ${response.status}`);
        const latest = Array.isArray(data?.invoice_versions) ? data.invoice_versions[0] : null;
        setLatestInvoiceVersionId(latest?.id ? String(latest.id) : '');
      } catch {
        setLatestInvoiceVersionId('');
      }
    };

    void fetchLatestInvoiceVersion();
  }, [invoiceId, suppliedLatestInvoiceVersionId]);

  const chatRows = useMemo(
    () =>
      [...rows].sort((a, b) =>
        String(a.conversation_message_created_at || a.conversation_message_updated_at || '').localeCompare(
          String(b.conversation_message_created_at || b.conversation_message_updated_at || ''),
        ),
      ),
    [rows],
  );

  const contextRow = rows[0];
  const displayContractorBusinessName = contractorBusinessName || contextRow?.contractor_business_name || '';
  const displayDiOcrInvoiceId = diOcrInvoiceId || contextRow?.di_ocr_invoice_id || '';
  const canSend = !!invoiceId.trim() && !!currentUserId && !!latestInvoiceVersionId;

  const sendMessage = async () => {
    const text = messageText.trim();
    if (!text) {
      setError('Please enter a message before sending.');
      return;
    }
    if (!canSend) return;

    setSaving(true);
    setError('');
    try {
      const response = await fetch('/api/claims/admin/conversation_messages', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
        credentials: 'include',
        body: JSON.stringify({
          invoice_id: invoiceId.trim(),
          invoice_version_id: latestInvoiceVersionId,
          requester_id: currentUserId,
          message_type: 'admin_message',
          request_text: text,
        }),
      });
      const data = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(data?.error || data?.message || `Send failed (${response.status}).`);
      setMessageText('');
      toast({
        title: 'Message sent',
        description: 'The contractor will see it in Messages & Requested Changes.',
        status: 'success',
        duration: 5000,
        isClosable: true,
      });
      await fetchRows();
    } catch (requestError: any) {
      setError(requestError?.message || 'Failed to send message.');
    } finally {
      setSaving(false);
    }
  };

  return (
    <Box p={4} bg="white" minW={0}>
      <PanelHeader
        title="Contractor Conversation"
        audience="Visible to contractor"
        audienceColor="blue"
        refreshing={loading}
        onRefresh={() => void fetchRows()}
        onClose={onClose}
      />
      {showContext ? (
        <InvoiceContext
          invoiceId={invoiceId}
          contractorBusinessName={displayContractorBusinessName}
          diOcrInvoiceId={displayDiOcrInvoiceId}
        />
      ) : null}
      {error ? (
        <Box mb={4} p={3} bg="red.50" borderWidth="1px" borderColor="red.200" borderRadius="md">
          <Text fontSize="sm" color="red.700">
            {error}
          </Text>
        </Box>
      ) : null}

      {loading ? (
        <Flex align="center" gap={3} p={4}>
          <Spinner size="sm" />
          <Text fontSize="sm">Loading conversation...</Text>
        </Flex>
      ) : chatRows.length === 0 ? (
        <Box p={5} borderWidth="1px" borderRadius="xl" bg="gray.50" textAlign="center">
          <Text fontSize="sm" color="gray.600">
            No messages yet. Send the first contractor message below.
          </Text>
        </Box>
      ) : (
        <Flex
          direction="column"
          gap={3}
          p={3}
          borderWidth="1px"
          borderRadius="xl"
          bg="gray.50"
          maxH="440px"
          overflowY="auto"
        >
          {chatRows.map((row, index) => {
            const adminMessage = isAdminMessage(row.conversation_message_type);
            return (
              <Flex
                key={row.conversation_message_id || `${row.conversation_message_seqno || 'msg'}-${index}`}
                direction="column"
                align={adminMessage ? 'flex-end' : 'flex-start'}
              >
                <Text fontSize="xs" color="gray.500" mb={1} px={1}>
                  {adminMessage ? 'Admin' : 'Contractor'} | Version {row.invoice_versionno ?? '-'} |{' '}
                  {fmtDate(row.conversation_message_updated_at || row.conversation_message_created_at)}
                </Text>
                <Box
                  maxW="92%"
                  px={3}
                  py={2}
                  borderRadius="2xl"
                  borderTopRightRadius={adminMessage ? 'md' : '2xl'}
                  borderTopLeftRadius={adminMessage ? '2xl' : 'md'}
                  bg={adminMessage ? 'blue.500' : 'white'}
                  color={adminMessage ? 'white' : 'gray.800'}
                  borderWidth={adminMessage ? '0' : '1px'}
                  borderColor="gray.200"
                  boxShadow="sm"
                >
                  <Text whiteSpace="pre-wrap" fontSize="sm">
                    {row.conversation_message_text || 'No message text provided.'}
                  </Text>
                </Box>
              </Flex>
            );
          })}
        </Flex>
      )}

      <Box mt={5}>
        <Text fontWeight="bold" mb={1}>
          Send to contractor
        </Text>
        <Text fontSize="xs" color="gray.600" mb={3}>
          This message will be visible to the contractor.
        </Text>
        <Textarea
          value={messageText}
          onChange={(event) => setMessageText(event.target.value)}
          placeholder="Type the requested change or clarification..."
          rows={5}
          bg="gray.50"
          borderRadius="xl"
          isDisabled={!canSend}
        />
        <Flex justify="flex-end" mt={3}>
          <Tooltip
            label={
              canSend
                ? 'Send a new message to the contractor.'
                : 'Send is disabled because the invoice or latest invoice version is unavailable.'
            }
            shouldWrapChildren
          >
            <IconButton
              aria-label="Send message to contractor"
              icon={<PaperPlaneTilt size={22} weight="bold" />}
              colorScheme="blue"
              borderRadius="full"
              onClick={() => void sendMessage()}
              isLoading={saving}
              isDisabled={!canSend}
            />
          </Tooltip>
        </Flex>
      </Box>
    </Box>
  );
};

export const AdminInternalNotesPanel = ({
  invoiceId,
  contractorBusinessName = '',
  diOcrInvoiceId = '',
  onClose,
  showContext = true,
}: AdminInvoicePanelProps) => {
  const toast = useToast();
  const { userStore } = useMst();
  const currentUserId = (userStore as any)?.currentUser?.id ? String((userStore as any).currentUser.id) : '';
  const [notes, setNotes] = useState<InternalNoteRow[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const [noteText, setNoteText] = useState('');
  const [saving, setSaving] = useState(false);

  const fetchNotes = async () => {
    if (!invoiceId.trim()) {
      setNotes([]);
      return;
    }
    setLoading(true);
    setError('');
    try {
      const params = new URLSearchParams({ invoice_id: invoiceId.trim() });
      const response = await fetch(`/api/claims/admin/internal_notes?${params.toString()}`, {
        headers: { Accept: 'application/json' },
        credentials: 'include',
      });
      const data: InternalNotesResponse = await response.json().catch(() => ({ rows: [] }));
      if (!response.ok) throw new Error((data as any)?.error || (data as any)?.message || `HTTP ${response.status}`);
      setNotes(Array.isArray(data?.rows) ? data.rows : []);
    } catch (requestError: any) {
      setError(requestError?.message || 'Failed to load internal notes.');
      setNotes([]);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    setNoteText('');
    void fetchNotes();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [invoiceId]);

  const canSave = !!invoiceId.trim() && !!currentUserId;

  const saveNote = async () => {
    const text = noteText.trim();
    if (!text) {
      setError('Please enter an internal note before saving.');
      return;
    }
    if (!canSave) return;

    setSaving(true);
    setError('');
    try {
      const response = await fetch('/api/claims/admin/internal_notes', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
        credentials: 'include',
        body: JSON.stringify({
          invoice_id: invoiceId.trim(),
          admin_user_id: currentUserId,
          note_text: text,
        }),
      });
      const data = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(data?.error || data?.message || `Save failed (${response.status}).`);
      setNoteText('');
      toast({
        title: 'Internal note saved',
        description: 'The note is stored for admin review only.',
        status: 'success',
        duration: 5000,
        isClosable: true,
      });
      await fetchNotes();
    } catch (requestError: any) {
      setError(requestError?.message || 'Failed to save internal note.');
    } finally {
      setSaving(false);
    }
  };

  return (
    <Box p={4} bg="white" minW={0}>
      <PanelHeader
        title="Internal Notes"
        audience="Admins only"
        audienceColor="purple"
        refreshing={loading}
        onRefresh={() => void fetchNotes()}
        onClose={onClose}
      />
      {showContext ? (
        <InvoiceContext
          invoiceId={invoiceId}
          contractorBusinessName={contractorBusinessName}
          diOcrInvoiceId={diOcrInvoiceId}
        />
      ) : null}
      {error ? (
        <Box mb={4} p={3} bg="red.50" borderWidth="1px" borderColor="red.200" borderRadius="md">
          <Text fontSize="sm" color="red.700">
            {error}
          </Text>
        </Box>
      ) : null}

      {loading ? (
        <Flex align="center" gap={3} p={4}>
          <Spinner size="sm" />
          <Text fontSize="sm">Loading internal notes...</Text>
        </Flex>
      ) : notes.length === 0 ? (
        <Box p={5} borderWidth="1px" borderRadius="xl" bg="purple.50" textAlign="center">
          <Text fontSize="sm" color="gray.600">
            No internal notes yet. Add the first admin-only note below.
          </Text>
        </Box>
      ) : (
        <Flex direction="column" gap={3} maxH="440px" overflowY="auto">
          {notes.map((note) => (
            <Box key={note.id} p={4} borderWidth="1px" borderRadius="xl" bg="purple.50" borderColor="purple.100">
              <Flex justify="space-between" gap={3} mb={2} flexWrap="wrap">
                <Text fontSize="xs" color="gray.500">
                  {note.admin_user_name || note.admin_user_id}
                </Text>
                <Text fontSize="xs" color="gray.500">
                  {fmtDateTime(note.created_at)}
                </Text>
              </Flex>
              <Text whiteSpace="pre-wrap" fontSize="sm">
                {note.note_text}
              </Text>
            </Box>
          ))}
        </Flex>
      )}

      <Box mt={5}>
        <Text fontWeight="bold" mb={1}>
          Add internal note
        </Text>
        <Text fontSize="xs" color="purple.700" mb={3} fontWeight="semibold">
          Admins only. Contractors cannot see this note.
        </Text>
        <Textarea
          value={noteText}
          onChange={(event) => setNoteText(event.target.value)}
          placeholder="Type an internal admin note..."
          rows={5}
          bg="purple.50"
          borderColor="purple.200"
          borderRadius="xl"
          isDisabled={!canSave}
        />
        <Flex justify="flex-end" mt={3}>
          <Tooltip
            label={canSave ? 'Save an admin-only note.' : 'Save is disabled because the invoice is unavailable.'}
            shouldWrapChildren
          >
            <IconButton
              aria-label="Save internal note"
              icon={<FloppyDiskBack size={22} weight="bold" />}
              colorScheme="purple"
              borderRadius="full"
              onClick={() => void saveNote()}
              isLoading={saving}
              isDisabled={!canSave}
            />
          </Tooltip>
        </Flex>
      </Box>
    </Box>
  );
};
