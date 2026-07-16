import { Box, Button, Container, Flex, Spinner, Text, Textarea, useToast } from '@chakra-ui/react';
import React, { useEffect, useMemo, useState } from 'react';
import { useParams } from 'react-router-dom';
import { ThinBlueTitleBar } from '../../shared/base/thin-blue-title-bar';
import { fmtDate } from '../invoice-versions/display';

type MessageRow = {
  id: string;
  invoice_versionno?: number | null;
  revreq_seqno?: number | null;
  message_type?: string | null;
  request_text?: string | null;
  created_at?: string | null;
  updated_at?: string | null;
};

const isContractorMessage = (type: unknown): boolean => String(type || '').trim() === 'contractor_note';

const messageTypeLabel = (type: unknown): string => {
  const value = String(type || '').trim();
  if (value === 'contractor_note') return 'You';
  return 'Admin';
};

export default function ContractorInvoiceMessagesScreen() {
  const { invoiceId } = useParams();
  const toast = useToast();
  const [rows, setRows] = useState<MessageRow[]>([]);
  const [loading, setLoading] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [messageText, setMessageText] = useState('');

  const chatRows = useMemo(
    () =>
      [...rows].sort((a, b) =>
        String(a.created_at || a.updated_at || '').localeCompare(String(b.created_at || b.updated_at || '')),
      ),
    [rows],
  );

  const loadRows = async () => {
    if (!invoiceId) return;
    setLoading(true);
    setError('');
    try {
      const resp = await fetch(
        `/api/claims/contractor/invoices/${encodeURIComponent(invoiceId)}/conversation_messages`,
        {
          headers: { Accept: 'application/json' },
          credentials: 'include',
        },
      );
      const json = await resp.json().catch(() => ({}));
      if (!resp.ok) throw new Error(json?.error || `Could not load messages (${resp.status}).`);
      setRows(Array.isArray(json?.rows) ? json.rows : []);
    } catch (e: any) {
      setError(e?.message || 'Could not load messages.');
      setRows([]);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    void loadRows();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [invoiceId]);

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
      const resp = await fetch(
        `/api/claims/contractor/invoices/${encodeURIComponent(invoiceId)}/conversation_messages`,
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
          credentials: 'include',
          body: JSON.stringify({ request_text: text }),
        },
      );
      const json = await resp.json().catch(() => ({}));
      if (!resp.ok) throw new Error(json?.error || `Could not send message (${resp.status}).`);
      setMessageText('');
      toast({
        title: 'Message sent',
        description: 'Admins will see this message when they review the invoice.',
        status: 'success',
        duration: 5000,
        isClosable: true,
      });
      await loadRows();
    } catch (e: any) {
      setError(e?.message || 'Could not send message.');
    } finally {
      setSaving(false);
    }
  };

  return (
    <Flex as="main" direction="column" w="full" bg="greys.white" pb="24" minH="100vh">
      <ThinBlueTitleBar title="Messages & Requested Changes" />
      <Container maxW="5xl" py={6}>
        <Box borderWidth="1px" borderRadius="lg" bg="white" p={5}>
          {error ? (
            <Box mb={4} p={3} borderWidth="1px" borderColor="red.200" bg="red.50" borderRadius="md">
              <Text color="red.700" fontSize="sm">
                {error}
              </Text>
            </Box>
          ) : null}

          <Flex justify="space-between" align="center" mb={3}>
            <Text fontWeight="bold">Conversation</Text>
          </Flex>

          {loading ? (
            <Flex align="center" gap={3} p={4}>
              <Spinner size="sm" />
              <Text>Loading messages...</Text>
            </Flex>
          ) : rows.length === 0 ? (
            <Box p={6} borderWidth="1px" borderRadius="xl" bg="gray.50" textAlign="center">
              <Text fontSize="sm" opacity={0.7}>
                No messages yet. If there is something admins should know, send the first message below.
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
                    maxW={{ base: '92%', md: '72%' }}
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
          )}

          <Box mt={5} p={4} borderWidth="1px" borderRadius="xl" bg="white" borderColor="gray.200">
            <Text fontWeight="bold" mb={1}>
              Send a message to admins
            </Text>
            <Text fontSize="sm" opacity={0.75} mb={3}>
              Use this if you want to explain something before submitting, or if an admin asked for clarification. If
              the invoice itself is wrong, upload a corrected invoice instead of only sending a note.
            </Text>
            <Textarea
              value={messageText}
              onChange={(event) => setMessageText(event.target.value)}
              placeholder="Type your message..."
              rows={4}
              bg="gray.50"
              borderRadius="xl"
            />
            <Flex justify="flex-end" mt={3}>
              <Button colorScheme="blue" onClick={() => void sendMessage()} isLoading={saving}>
                Send
              </Button>
            </Flex>
          </Box>
        </Box>
      </Container>
    </Flex>
  );
}
