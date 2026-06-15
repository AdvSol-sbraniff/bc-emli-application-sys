import React, { useEffect, useMemo, useState } from 'react';
import {
  Box,
  Container,
  Flex,
  IconButton,
  Spinner,
  Tab,
  TabList,
  TabPanel,
  TabPanels,
  Tabs,
  Text,
  Textarea,
  Tooltip,
  useToast,
} from '@chakra-ui/react';
import { ArrowsClockwise, FloppyDiskBack, PaperPlaneTilt } from '@phosphor-icons/react';
import { useLocation } from 'react-router-dom';
import { ThinBlueTitleBar } from '../../shared/base/thin-blue-title-bar';
import { useMst } from '../../../setup/root';

type RevisionRequestGridRow = {
  session_created_at?: string | null;
  invoice_id?: string | null;
  invoice_status?: string | null;
  contractor_business_name?: string | null;
  invoice_version_id?: string | null;
  invoice_version_created_at?: string | null;
  invoice_versionno?: number | null;
  di_ocr_invoice_id?: string | null;
  revision_request_id?: string | null;
  revision_request_seqno?: number | null;
  revision_request_message_type?: string | null;
  revision_request_text?: string | null;
  revision_request_created_at?: string | null;
  revision_request_updated_at?: string | null;
};

type RevisionRequestGridResponse = {
  rows: RevisionRequestGridRow[];
  meta?: { total?: number; page?: number; per?: number; sort?: string; filters?: any };
};

type InternalNoteRow = {
  id: string;
  invoice_id: string;
  admin_user_id: string;
  admin_user_name?: string | null;
  note_text: string;
  created_at?: string | null;
  updated_at?: string | null;
};

type InternalNotesResponse = {
  rows: InternalNoteRow[];
};

function getParam(search: string, key: string): string {
  return new URLSearchParams(search).get(key) ?? '';
}

function fmtDate(s?: string | null) {
  if (!s) return '-';
  const raw = String(s);
  if (raw.includes('T')) return raw.split('T')[0];
  return raw.slice(0, 10);
}

function fmtDateTime(s?: string | null) {
  if (!s) return '-';
  const raw = String(s);
  if (!raw.includes('T')) return raw;
  return raw.replace('T', ' ').slice(0, 16);
}

function isAdminMessage(type?: string | null) {
  return String(type || '').trim() !== 'contractor_note';
}

function messageAuthor(type?: string | null) {
  return isAdminMessage(type) ? 'Admin' : 'Contractor';
}

export default function RevisionRequestsAdminScreen() {
  const location = useLocation();
  const toast = useToast();
  const { userStore } = useMst();
  const currentUserId = (userStore as any)?.currentUser?.id ? String((userStore as any).currentUser.id) : '';

  const invoiceId = getParam(location.search, 'invoice_id');
  const contextContractorBusinessName = getParam(location.search, 'context_contractor_business_name');
  const contextDiOcrInvoiceId = getParam(location.search, 'context_di_ocr_invoice_id');
  const latestInvoiceVersionIdFromUrl = getParam(location.search, 'latest_invoice_version_id');

  const [gridLoading, setGridLoading] = useState(false);
  const [notesLoading, setNotesLoading] = useState(false);
  const [gridError, setGridError] = useState('');
  const [notesError, setNotesError] = useState('');
  const [rows, setRows] = useState<RevisionRequestGridRow[]>([]);
  const [internalNotes, setInternalNotes] = useState<InternalNoteRow[]>([]);
  const [latestInvoiceVersionId, setLatestInvoiceVersionId] = useState<string>(latestInvoiceVersionIdFromUrl);
  const [messageText, setMessageText] = useState('');
  const [noteText, setNoteText] = useState('');
  const [savingMessage, setSavingMessage] = useState(false);
  const [savingNote, setSavingNote] = useState(false);

  const fetchRows = async () => {
    setGridLoading(true);
    setGridError('');

    try {
      const params = new URLSearchParams();
      if (invoiceId.trim()) params.set('invoice_id', invoiceId.trim());
      params.set('sort', 'revision_request_updated_at:desc');
      params.set('page', '1');
      params.set('per', '100');

      const res = await fetch(`/api/claims/admin/revision_requests?${params.toString()}`, {
        method: 'GET',
        headers: { Accept: 'application/json' },
        credentials: 'include',
      });

      const data: RevisionRequestGridResponse = await res.json().catch(() => ({ rows: [] }));
      if (!res.ok) throw new Error((data as any)?.error || (data as any)?.message || `HTTP ${res.status}`);
      setRows(Array.isArray(data?.rows) ? data.rows : []);
    } catch (e: any) {
      setGridError(e?.message || 'Failed to load messages.');
      setRows([]);
    } finally {
      setGridLoading(false);
    }
  };

  const fetchInternalNotes = async () => {
    if (!invoiceId.trim()) {
      setInternalNotes([]);
      return;
    }

    setNotesLoading(true);
    setNotesError('');

    try {
      const params = new URLSearchParams();
      params.set('invoice_id', invoiceId.trim());

      const res = await fetch(`/api/claims/admin/internal_notes?${params.toString()}`, {
        method: 'GET',
        headers: { Accept: 'application/json' },
        credentials: 'include',
      });

      const data: InternalNotesResponse = await res.json().catch(() => ({ rows: [] }));
      if (!res.ok) throw new Error((data as any)?.error || (data as any)?.message || `HTTP ${res.status}`);
      setInternalNotes(Array.isArray(data?.rows) ? data.rows : []);
    } catch (e: any) {
      setNotesError(e?.message || 'Failed to load internal notes.');
      setInternalNotes([]);
    } finally {
      setNotesLoading(false);
    }
  };

  const refreshAll = async () => {
    await Promise.all([fetchRows(), fetchInternalNotes()]);
  };

  useEffect(() => {
    void refreshAll();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [invoiceId]);

  const fetchLatestInvoiceVersion = async () => {
    if (!invoiceId.trim() || latestInvoiceVersionIdFromUrl) return;

    try {
      const res = await fetch(
        `/api/claims/admin/invoices/${encodeURIComponent(invoiceId.trim())}/invoice_versions?limit=1`,
        {
          method: 'GET',
          headers: { Accept: 'application/json' },
          credentials: 'include',
        },
      );
      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data?.error || data?.message || `HTTP ${res.status}`);

      const latest = Array.isArray(data?.invoice_versions) ? data.invoice_versions[0] : null;
      setLatestInvoiceVersionId(latest?.id ? String(latest.id) : '');
    } catch {
      setLatestInvoiceVersionId('');
    }
  };

  useEffect(() => {
    void fetchLatestInvoiceVersion();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [invoiceId, latestInvoiceVersionIdFromUrl]);

  const contextRow = rows[0] || null;
  const displayContractorBusinessName = contextContractorBusinessName || contextRow?.contractor_business_name || '';
  const displayDiOcrInvoiceId = contextDiOcrInvoiceId || contextRow?.di_ocr_invoice_id || '';
  const hasInvoiceContext = !!displayContractorBusinessName || !!displayDiOcrInvoiceId;

  const canSendAdminMessage = !!latestInvoiceVersionId;
  const sendHint = !latestInvoiceVersionId
    ? 'Send is disabled because no latest invoice version is available.'
    : 'Send a new admin message to the contractor. Admin conversations stay open regardless of invoice status.';

  const canSaveInternalNote = !!invoiceId.trim() && !!currentUserId;
  const noteHint = !invoiceId.trim()
    ? 'Save is disabled because no invoice id is available.'
    : 'Save an internal admin-only note. Contractors do not see these notes.';

  const chatRows = useMemo(
    () =>
      [...rows].sort((a, b) =>
        String(a.revision_request_created_at || a.revision_request_updated_at || '').localeCompare(
          String(b.revision_request_created_at || b.revision_request_updated_at || ''),
        ),
      ),
    [rows],
  );

  const sendMessage = async () => {
    const text = messageText.trim();
    if (!text) {
      setGridError('Please enter a message before sending.');
      return;
    }
    if (!currentUserId || !latestInvoiceVersionId || !canSendAdminMessage) return;

    setSavingMessage(true);
    setGridError('');
    try {
      const res = await fetch('/api/claims/admin/revision_requests', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
        credentials: 'include',
        body: JSON.stringify({
          invoice_id: invoiceId.trim(),
          invoice_version_id: latestInvoiceVersionId,
          requester_id: currentUserId,
          message_type: 'admin_revision_request',
          request_text: text,
        }),
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data?.error || data?.message || `Send failed (${res.status}).`);
      setMessageText('');
      toast({
        title: 'Message sent',
        description: 'The contractor will see it in Messages & Requested Changes.',
        status: 'success',
        duration: 5000,
        isClosable: true,
      });
      await fetchRows();
    } catch (e: any) {
      setGridError(e?.message || 'Failed to send message.');
    } finally {
      setSavingMessage(false);
    }
  };

  const saveInternalNote = async () => {
    const text = noteText.trim();
    if (!text) {
      setNotesError('Please enter an internal note before saving.');
      return;
    }
    if (!canSaveInternalNote) return;

    setSavingNote(true);
    setNotesError('');
    try {
      const res = await fetch('/api/claims/admin/internal_notes', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
        credentials: 'include',
        body: JSON.stringify({
          invoice_id: invoiceId.trim(),
          admin_user_id: currentUserId,
          note_text: text,
        }),
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data?.error || data?.message || `Save failed (${res.status}).`);
      setNoteText('');
      toast({
        title: 'Internal note saved',
        description: 'The note is stored for admin review only.',
        status: 'success',
        duration: 5000,
        isClosable: true,
      });
      await fetchInternalNotes();
    } catch (e: any) {
      setNotesError(e?.message || 'Failed to save internal note.');
    } finally {
      setSavingNote(false);
    }
  };

  return (
    <Flex as="main" direction="column" w="full" bg="greys.white" pb="24" minH="100vh">
      <ThinBlueTitleBar title="Invoice Messages & Notes" />

      <Container maxW="full" px={6} pb={4} flex="1" pt={6}>
        <Box p={5} bg="white">
          <Flex justify="flex-end" align="center" gap={3} mb={5} flexWrap="wrap">
            <Tooltip label="Refresh messages and notes">
              <IconButton
                aria-label="Refresh messages and notes"
                icon={<ArrowsClockwise size={18} />}
                variant="outline"
                onClick={() => void refreshAll()}
                isLoading={gridLoading || notesLoading}
              />
            </Tooltip>
          </Flex>

          {(hasInvoiceContext || gridLoading) && (
            <Box mb={5}>
              {!hasInvoiceContext ? (
                <Text fontSize="sm" opacity={0.7}>
                  Loading invoice context...
                </Text>
              ) : (
                <Flex direction="column" gap={3}>
                  <Flex wrap="wrap" gap={6}>
                    <Box>
                      <Text fontSize="xs" opacity={0.7}>
                        contractor_name
                      </Text>
                      <Text fontSize="sm">{displayContractorBusinessName || '-'}</Text>
                    </Box>
                    <Box>
                      <Text fontSize="xs" opacity={0.7}>
                        invoice # (DI)
                      </Text>
                      <Text fontSize="sm">{displayDiOcrInvoiceId || '-'}</Text>
                    </Box>
                  </Flex>
                </Flex>
              )}
            </Box>
          )}

          <Tabs variant="line" isFitted colorScheme="gray" isLazy>
            <TabList>
              <Tab>Contractor</Tab>
              <Tab>Internal Notes</Tab>
            </TabList>

            <TabPanels>
              <TabPanel px={0} pt={3}>
                {gridError && (
                  <Box mb={4} p={3} bg="red.50" borderWidth="1px" borderColor="red.200" borderRadius="md">
                    <Text as="div" fontSize="sm" color="red.700">
                      {gridError}
                    </Text>
                  </Box>
                )}

                <Text fontWeight="bold" mb={3}>
                  Conversation
                </Text>
                {gridLoading ? (
                  <Flex align="center" gap={3} p={4}>
                    <Spinner size="sm" />
                    <Text>Loading messages...</Text>
                  </Flex>
                ) : chatRows.length === 0 ? (
                  <Box p={6} borderWidth="1px" borderRadius="xl" bg="gray.50" textAlign="center">
                    <Text fontSize="sm" opacity={0.7}>
                      No messages yet. Send the first contractor message below.
                    </Text>
                  </Box>
                ) : (
                  <Flex
                    direction="column"
                    gap={3}
                    p={4}
                    borderWidth="1px"
                    borderRadius="xl"
                    bg="gray.50"
                    maxH="520px"
                    overflowY="auto"
                  >
                    {chatRows.map((row, index) => {
                      const adminMessage = isAdminMessage(row.revision_request_message_type);
                      return (
                        <Flex
                          key={row.revision_request_id || `${row.revision_request_seqno || 'msg'}-${index}`}
                          direction="column"
                          align={adminMessage ? 'flex-end' : 'flex-start'}
                        >
                          <Text fontSize="xs" color="gray.500" mb={1} px={1}>
                            {messageAuthor(row.revision_request_message_type)} | Version {row.invoice_versionno ?? '-'}{' '}
                            | {fmtDate(row.revision_request_updated_at || row.revision_request_created_at)}
                          </Text>
                          <Box
                            maxW={{ base: '92%', md: '72%' }}
                            px={4}
                            py={3}
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
                              {row.revision_request_text || 'No message text provided.'}
                            </Text>
                          </Box>
                        </Flex>
                      );
                    })}
                  </Flex>
                )}

                <Box mt={5}>
                  <Text fontWeight="bold" mb={1}>
                    Send a message to contractor
                  </Text>
                  <Text fontSize="sm" opacity={0.75} mb={3}>
                    Write the message once and send it. If more context is needed later, send a new message instead of
                    editing history.
                  </Text>
                  <Textarea
                    value={messageText}
                    onChange={(event) => setMessageText(event.target.value)}
                    placeholder="Type the requested change or clarification..."
                    rows={5}
                    bg="gray.50"
                    borderRadius="xl"
                    isDisabled={!canSendAdminMessage || !latestInvoiceVersionId}
                  />
                  <Flex justify="flex-end" mt={3}>
                    <Tooltip label={sendHint} shouldWrapChildren>
                      <IconButton
                        aria-label="Send message to contractor"
                        icon={<PaperPlaneTilt size={22} weight="bold" />}
                        size="md"
                        colorScheme="blue"
                        borderRadius="full"
                        onClick={() => void sendMessage()}
                        isLoading={savingMessage}
                        isDisabled={!latestInvoiceVersionId || !canSendAdminMessage}
                      />
                    </Tooltip>
                  </Flex>
                </Box>
              </TabPanel>

              <TabPanel px={0} pt={3}>
                {notesError && (
                  <Box mb={4} p={3} bg="red.50" borderWidth="1px" borderColor="red.200" borderRadius="md">
                    <Text as="div" fontSize="sm" color="red.700">
                      {notesError}
                    </Text>
                  </Box>
                )}

                <Text fontWeight="bold" mb={3}>
                  Notes
                </Text>

                {notesLoading ? (
                  <Flex align="center" gap={3} p={4}>
                    <Spinner size="sm" />
                    <Text>Loading internal notes...</Text>
                  </Flex>
                ) : internalNotes.length === 0 ? (
                  <Box p={6} borderWidth="1px" borderRadius="xl" bg="gray.50" textAlign="center">
                    <Text fontSize="sm" opacity={0.7}>
                      No internal notes yet. Add the first admin-only note below.
                    </Text>
                  </Box>
                ) : (
                  <Flex direction="column" gap={3}>
                    {internalNotes.map((note) => (
                      <Box key={note.id} p={4} borderWidth="1px" borderRadius="xl" bg="gray.50" borderColor="gray.200">
                        <Flex justify="space-between" gap={3} mb={2} flexWrap="wrap">
                          <Text fontSize="xs" color="gray.500">
                            Admin user: {note.admin_user_name || note.admin_user_id}
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
                  <Text fontSize="sm" opacity={0.75} mb={3}>
                    This note is for admins only. It is not shown in the contractor conversation. Admin-only notes are
                    for documenting review decisions, context, or why an AI warning was accepted.
                  </Text>
                  <Textarea
                    value={noteText}
                    onChange={(event) => setNoteText(event.target.value)}
                    placeholder="Type an internal admin note..."
                    rows={5}
                    bg="gray.50"
                    borderRadius="xl"
                    isDisabled={!canSaveInternalNote}
                  />
                  <Flex justify="flex-end" mt={3}>
                    <Tooltip label={noteHint} shouldWrapChildren>
                      <IconButton
                        aria-label="Save internal note"
                        icon={<FloppyDiskBack size={22} weight="bold" />}
                        size="md"
                        colorScheme="blue"
                        borderRadius="full"
                        onClick={() => void saveInternalNote()}
                        isLoading={savingNote}
                        isDisabled={!canSaveInternalNote}
                      />
                    </Tooltip>
                  </Flex>
                </Box>
              </TabPanel>
            </TabPanels>
          </Tabs>
        </Box>
      </Container>
    </Flex>
  );
}
