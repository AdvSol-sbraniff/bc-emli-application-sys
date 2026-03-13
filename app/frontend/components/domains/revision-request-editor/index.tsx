import React, { useEffect, useMemo, useState } from 'react';
import { Box, Button, Container, Flex, Heading, Input, Select, Spinner, Text, Textarea } from '@chakra-ui/react';
import { useLocation, useNavigate } from 'react-router-dom';
import { ThinBlueTitleBar } from '../../shared/base/thin-blue-title-bar';
import { useMst } from '../../../setup/root';

type RevisionRequestDto = {
  id: string;
  invoice_version_id: string;
  session_id?: string | null;
  session_created_at?: string | null;
  invoice_id?: string | null;
  contractor_business_name?: string | null;
  invoice_version_created_at?: string | null;
  invoice_versionno?: number | null;
  di_ocr_invoice_id?: string | null;
  revreq_seqno?: number | null;
  requester_id: string;
  status: string;
  request_text?: string | null;
  response_text?: string | null;
  closed_at?: string | null;
  created_at?: string | null;
  updated_at?: string | null;
};

function fmtDate(s: string | null): string {
  if (!s) return '—';
  const raw = String(s);
  if (raw.includes('T')) return raw.split('T')[0];
  return raw.slice(0, 10);
}

function useQueryParam(name: string): string | null {
  const { search } = useLocation();
  return useMemo(() => new URLSearchParams(search).get(name), [search, name]);
}

export default function RevisionRequestEditorScreen() {
  const navigate = useNavigate();
  const { userStore } = useMst();
  const currentUserId = (userStore as any)?.currentUser?.id ? String((userStore as any).currentUser.id) : '';

  const id = useQueryParam('id');
  const mode = useQueryParam('mode');
  const invoiceVersionIdFromQuery = useQueryParam('invoice_version_id');
  const invoiceIdFromQuery = useQueryParam('invoice_id');
  const sessionIdFromQuery = useQueryParam('session_id');
  const sessionCreatedAtFromQuery = useQueryParam('session_created_at');
  const contractorBusinessNameFromQuery = useQueryParam('contractor_business_name');
  const invoiceVersionCreatedAtFromQuery = useQueryParam('invoice_version_created_at');
  const invoiceVersionNoFromQuery = useQueryParam('invoice_versionno');
  const diOcrInvoiceIdFromQuery = useQueryParam('di_ocr_invoice_id');
  const isCreateMode = mode === 'create';

  const [isLoading, setIsLoading] = useState<boolean>(true);
  const [isSaving, setIsSaving] = useState<boolean>(false);
  const [error, setError] = useState<string | null>(null);

  const [record, setRecord] = useState<RevisionRequestDto | null>(null);

  const [invoiceVersionId, setInvoiceVersionId] = useState<string>('');
  const [requesterId, setRequesterId] = useState<string>('');
  const [status, setStatus] = useState<string>('OPEN');
  const [requestText, setRequestText] = useState<string>('');
  const [responseText, setResponseText] = useState<string>('');
  const [closedAt, setClosedAt] = useState<string>('');

  const [initialValues, setInitialValues] = useState({
    invoiceVersionId: '',
    requesterId: '',
    status: 'OPEN',
    requestText: '',
    responseText: '',
    closedAt: '',
  });

  const isDirty =
    status !== initialValues.status ||
    requestText !== initialValues.requestText ||
    responseText !== initialValues.responseText ||
    closedAt !== initialValues.closedAt;

  const contextSessionId = sessionIdFromQuery || record?.session_id || null;
  const contextSessionCreatedAt = sessionCreatedAtFromQuery || record?.session_created_at || null;
  const contextInvoiceId = invoiceIdFromQuery || record?.invoice_id || null;
  const contextContractorName = contractorBusinessNameFromQuery || record?.contractor_business_name || null;
  const contextInvoiceVersionCreatedAt = invoiceVersionCreatedAtFromQuery || record?.invoice_version_created_at || null;
  const contextInvoiceVersionNo = invoiceVersionNoFromQuery || (record?.invoice_versionno !== null && record?.invoice_versionno !== undefined ? String(record.invoice_versionno) : null);
  const contextDiOcrInvoiceId = diOcrInvoiceIdFromQuery || record?.di_ocr_invoice_id || null;

  async function load() {
    setIsLoading(true);
    setError(null);

    try {
      if (isCreateMode) {
        const nextInvoiceVersionId = invoiceVersionIdFromQuery || '';
        const nextRequesterId = currentUserId;
        setRecord(null);
        setInvoiceVersionId(nextInvoiceVersionId);
        setRequesterId(nextRequesterId);
        setStatus('OPEN');
        setRequestText('');
        setResponseText('');
        setClosedAt('');
        setInitialValues({
          invoiceVersionId: nextInvoiceVersionId,
          requesterId: nextRequesterId,
          status: 'OPEN',
          requestText: '',
          responseText: '',
          closedAt: '',
        });
        return;
      }

      if (!id) {
        setError('Missing query param: id');
        return;
      }

      const resp = await fetch(`/api/claims/admin/revision_requests/${id}`, {
        method: 'GET',
        headers: { Accept: 'application/json' },
        credentials: 'include',
      });

      if (!resp.ok) {
        const txt = await resp.text();
        throw new Error(`GET failed (${resp.status}): ${txt}`);
      }

      const data: RevisionRequestDto = await resp.json();
      setRecord(data);
      setInvoiceVersionId(data.invoice_version_id || '');
      setRequesterId(data.requester_id || '');
      setStatus(data.status || 'OPEN');
      setRequestText(data.request_text || '');
      setResponseText(data.response_text || '');
      setClosedAt(data.closed_at || '');
      setInitialValues({
        invoiceVersionId: data.invoice_version_id || '',
        requesterId: data.requester_id || '',
        status: data.status || 'OPEN',
        requestText: data.request_text || '',
        responseText: data.response_text || '',
        closedAt: data.closed_at || '',
      });
    } catch (e: any) {
      setError(e?.message || 'Load failed');
    } finally {
      setIsLoading(false);
    }
  }

  async function save() {
    if (!isCreateMode && !id) return;

    setIsSaving(true);
    setError(null);

    try {
      const endpoint = isCreateMode ? '/api/claims/admin/revision_requests' : `/api/claims/admin/revision_requests/${id}`;
      const method = isCreateMode ? 'POST' : 'PATCH';

      const body = isCreateMode
        ? {
            invoice_version_id: invoiceVersionId.trim(),
            requester_id: requesterId.trim(),
            status: status.trim(),
            request_text: requestText,
            response_text: responseText,
            closed_at: closedAt || null,
          }
        : {
            status: status.trim(),
            request_text: requestText,
            response_text: responseText,
            closed_at: closedAt || null,
          };

      const resp = await fetch(endpoint, {
        method,
        headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
        credentials: 'include',
        body: JSON.stringify(body),
      });

      if (!resp.ok) {
        const txt = await resp.text();
        throw new Error(`${method} failed (${resp.status}): ${txt}`);
      }

      const data: RevisionRequestDto = await resp.json();
      setRecord(data);
      setInvoiceVersionId(data.invoice_version_id || '');
      setRequesterId(data.requester_id || '');
      setStatus(data.status || 'OPEN');
      setRequestText(data.request_text || '');
      setResponseText(data.response_text || '');
      setClosedAt(data.closed_at || '');
      setInitialValues({
        invoiceVersionId: data.invoice_version_id || '',
        requesterId: data.requester_id || '',
        status: data.status || 'OPEN',
        requestText: data.request_text || '',
        responseText: data.response_text || '',
        closedAt: data.closed_at || '',
      });

      if (isCreateMode) {
        const params = new URLSearchParams();
        params.set('id', String(data.id));
        if (invoiceVersionIdFromQuery) params.set('invoice_version_id', String(invoiceVersionIdFromQuery));
        if (invoiceIdFromQuery) params.set('invoice_id', String(invoiceIdFromQuery));
        if (sessionIdFromQuery) params.set('session_id', String(sessionIdFromQuery));
        if (sessionCreatedAtFromQuery) params.set('session_created_at', String(sessionCreatedAtFromQuery));
        if (contractorBusinessNameFromQuery) params.set('contractor_business_name', String(contractorBusinessNameFromQuery));
        if (invoiceVersionCreatedAtFromQuery) params.set('invoice_version_created_at', String(invoiceVersionCreatedAtFromQuery));
        if (invoiceVersionNoFromQuery) params.set('invoice_versionno', String(invoiceVersionNoFromQuery));
        if (diOcrInvoiceIdFromQuery) params.set('di_ocr_invoice_id', String(diOcrInvoiceIdFromQuery));
        navigate(`/revision-request-editor?${params.toString()}`, { replace: true });
      }
    } catch (e: any) {
      setError(e?.message || 'Save failed');
    } finally {
      setIsSaving(false);
    }
  }

  useEffect(() => {
    load();
  }, [id, mode, invoiceVersionIdFromQuery, currentUserId]);

  return (
    <Box>
      <ThinBlueTitleBar title="Revision Request Editor" />

      <Container maxW="4xl" py={6}>
        {!id && !isCreateMode && (
          <Box p={4} borderWidth="1px" borderRadius="md">
            <Text fontWeight="bold">Missing id</Text>
            <Text>Use: /revision-request-editor?id=&lt;uuid&gt; or /revision-request-editor?mode=create&invoice_version_id=&lt;uuid&gt;</Text>
          </Box>
        )}

        {(id || isCreateMode) && (
          <Box borderWidth="1px" borderRadius="lg" p={5} bg="white">
            <Flex align="center" justify="space-between" mb={4}>
              <Heading size="md">{isCreateMode ? 'Insert Revision Request' : 'Update Revision Request'}</Heading>
              <Flex gap={2}>
                <Button onClick={load} variant="outline" isDisabled={isLoading || isSaving}>
                  Reload
                </Button>
                <Button onClick={save} colorScheme="blue" isLoading={isSaving} isDisabled={isLoading || !isDirty}>
                  Save
                </Button>
              </Flex>
            </Flex>

            {(contextSessionId || contextSessionCreatedAt || contextInvoiceId || contextContractorName || contextInvoiceVersionCreatedAt || contextInvoiceVersionNo || contextDiOcrInvoiceId) && (
              <Box mb={4} p={3} borderWidth="1px" borderRadius="md" bg="gray.50">
                <Text fontSize="sm" fontWeight="bold">Context (selected invoice version)</Text>
                <Text fontSize="sm">session_id: {contextSessionId || '—'}</Text>
                <Text fontSize="sm">session created: {fmtDate(contextSessionCreatedAt)}</Text>
                <Text fontSize="sm">invoice_id: {contextInvoiceId || '—'}</Text>
                <Text fontSize="sm">contractor name: {contextContractorName || '—'}</Text>
                <Text fontSize="sm">invoice version created: {fmtDate(contextInvoiceVersionCreatedAt)}</Text>
                <Text fontSize="sm">invoice version no: {contextInvoiceVersionNo || '—'}</Text>
                <Text fontSize="sm">invoice # (DI): {contextDiOcrInvoiceId || '—'}</Text>
              </Box>
            )}

            {isLoading && (
              <Flex align="center" gap={3} p={3}>
                <Spinner size="sm" />
                <Text>Loading...</Text>
              </Flex>
            )}

            {error && (
              <Box p={3} borderWidth="1px" borderRadius="md" mb={4} borderColor="red.300" bg="red.50">
                <Text color="red.800" fontSize="sm">{error}</Text>
              </Box>
            )}

            {!isLoading && !error && (
              <Flex direction="column" gap={4}>
                <Box>
                  <Text fontSize="xs" opacity={0.7} mb={1}>status</Text>
                  <Select value={status} onChange={(e) => setStatus(e.target.value)}>
                    <option value="OPEN">OPEN</option>
                    <option value="CLOSED">CLOSED</option>
                  </Select>
                </Box>

                <Box>
                  <Text fontSize="xs" opacity={0.7} mb={1}>request_text</Text>
                  <Textarea value={requestText} onChange={(e) => setRequestText(e.target.value)} rows={5} />
                </Box>

                <Box>
                  <Text fontSize="xs" opacity={0.7} mb={1}>response_text</Text>
                  <Textarea value={responseText} onChange={(e) => setResponseText(e.target.value)} rows={5} />
                </Box>

                <Box>
                  <Text fontSize="xs" opacity={0.7} mb={1}>closed_at</Text>
                  <Input value={closedAt} onChange={(e) => setClosedAt(e.target.value)} placeholder="YYYY-MM-DD or timestamp" />
                </Box>

                <Text fontSize="sm" opacity={0.8}>
                  {isDirty ? 'Unsaved changes' : 'Saved'}
                  {record?.updated_at ? ` • updated_at: ${record.updated_at}` : ''}
                </Text>
              </Flex>
            )}
          </Box>
        )}
      </Container>
    </Box>
  );
}
