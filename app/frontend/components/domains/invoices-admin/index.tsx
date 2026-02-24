import { Box, Button, Container, Flex, Heading, Input, Text } from '@chakra-ui/react';
import { Table, Thead, Tbody, Tr, Th, Td, Spinner } from '@chakra-ui/react';
import React, { useState } from 'react';
import { BlueTitleBar } from '../../shared/base/blue-title-bar';
import { useNavigate } from 'react-router-dom';

type InvoiceRow = {
  id: string;
  session_id: string;
  status: string;
  status_updated_at?: string | null;
  system_help_notes?: string | null;
  created_at?: string;
  updated_at?: string;
};

const fmtTs = (s?: string | null) => (s ? String(s).replace('T', ' ').replace('Z', '') : '');

export function InvoicesAdminScreen() {
  const [sessionId, setSessionId] = useState<string>('');
  const [loading, setLoading] = useState<boolean>(false);
  const [error, setError] = useState<string>('');
  const [invoices, setInvoices] = useState<InvoiceRow[]>([]);

const navigate = useNavigate();

const handleOpenVersions = (invoiceId: string) => {
  const url = `/invoice-versions-admin?invoice_id=${encodeURIComponent(invoiceId)}`;
  window.open(url, '_blank', 'noopener,noreferrer');
};

  const handleRefresh = async () => {
    setLoading(true);
    setError('');
    setInvoices([]);

    try {
      if (!sessionId.trim()) throw new Error('Please enter a session_id.');

      const url = `/api/claims/sessions/${encodeURIComponent(sessionId.trim())}/invoices`;

      const res = await fetch(url, {
        method: 'GET',
        headers: { Accept: 'application/json' },
        credentials: 'include',
      });

      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data?.error || data?.message || `HTTP ${res.status}`);

      setInvoices(Array.isArray(data?.invoices) ? data.invoices : []);
    } catch (e: any) {
      setError(e?.message || 'Failed to load invoices.');
    } finally {
      setLoading(false);
    }
  };

  return (
    <Flex as="main" direction="column" w="full" bg="greys.white" pb="24" minH="100vh">
      <BlueTitleBar title="Invoices Admin" />

      <Container maxW="container.xl" pb={4} flex="1" pt={6}>
        <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="lg" p={5} bg="white">
          <Heading size="md" mb={2}>
            Invoices by session
          </Heading>

          <Text fontSize="sm" opacity={0.8} mb={4}>
            Shows <code>claims.invoices</code> rows for a session (invoice-level status lives here).
          </Text>

          {/* session_id + refresh */}
          <Flex gap={3} align="end" wrap="wrap" mb={4}>
            <Box flex="1" minW="360px">
              <Text fontSize="xs" opacity={0.7} mb={1}>
                session_id
              </Text>
              <Input
                value={sessionId}
                onChange={(e) => setSessionId(e.target.value)}
                placeholder="paste session UUID"
                bg="white"
                fontFamily="mono"
              />
            </Box>

            <Button onClick={handleRefresh} isLoading={loading} loadingText="Refreshing...">
              Refresh
            </Button>
          </Flex>

          {error && (
            <Box mb={4} p={3} bg="red.50" borderWidth="1px" borderColor="red.200" borderRadius="md">
              <Text fontSize="sm" color="red.700">
                {error}
              </Text>
            </Box>
          )}

          {/* grid */}
          <Box bg="white" borderWidth="1px" borderColor="greys.grey20" borderRadius="md" p={3}>
            <Flex align="center" justify="space-between" mb={2}>
              <Text fontSize="sm" fontWeight="bold">
                Invoices
              </Text>
              {loading && <Spinner size="sm" />}
            </Flex>

            <Table size="sm">
              <Thead>
                <Tr>
                  <Th>created</Th>
                  <Th>invoice_id</Th>
                  <Th>status</Th>
                  <Th>status_updated</Th>
                  <Th>help_notes</Th>
                  <Th></Th>
                </Tr>
              </Thead>

              <Tbody>
                {invoices.map((i) => (
                  <Tr key={i.id}>
                    <Td fontFamily="mono" fontSize="xs">
                      {fmtTs(i.created_at)}
                    </Td>
                    <Td fontFamily="mono" fontSize="xs">
                      {i.id}
                    </Td>
                    <Td fontFamily="mono" fontSize="xs">
                      {i.status}
                    </Td>
                    <Td fontFamily="mono" fontSize="xs">
                      {fmtTs(i.status_updated_at)}
                    </Td>
                    <Td fontSize="xs" maxW="380px">
                      {i.system_help_notes ?? ''}
                    </Td>
                    <Td>
                      <Button size="xs" variant="outline" onClick={() => handleOpenVersions(i.id)}>
                        Open versions
                      </Button>
                    </Td>
                  </Tr>
                ))}

                {!loading && invoices.length === 0 && (
                  <Tr>
                    <Td colSpan={6}>
                      <Text fontSize="sm" opacity={0.7}>
                        Enter a session_id and click Refresh.
                      </Text>
                    </Td>
                  </Tr>
                )}
              </Tbody>
            </Table>
          </Box>
        </Box>
      </Container>
    </Flex>
  );
}