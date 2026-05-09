import {
  Badge,
  Box,
  Button,
  Container,
  Drawer,
  DrawerBody,
  DrawerCloseButton,
  DrawerContent,
  DrawerHeader,
  DrawerOverlay,
  Flex,
  Heading,
  IconButton,
  SimpleGrid,
  Spinner,
  Table,
  Tbody,
  Td,
  Text,
  Th,
  Thead,
  Tooltip,
  Tr,
  useDisclosure,
} from '@chakra-ui/react';
import { observer } from 'mobx-react-lite';
import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { ArrowsClockwise, Question } from '@phosphor-icons/react';
import { useLocation } from 'react-router-dom';
import { ThinBlueTitleBar } from '../../shared/base/thin-blue-title-bar';

type IngestStepRow = {
  id: string;
  ingest_run_id?: string | null;
  invoice_version_id?: string | null;
  step_type?: string | null;
  status?: string | null;
  error_text?: string | null;
  validationgenai_ruleset_id?: string | null;
  created_at?: string | null;
  updated_at?: string | null;
};

type InvoiceGridRow = {
  invoice_id: string;
  session_id: string;
  invoice_status?: string | null;
  invoice_status_updated_at?: string | null;
  session_status?: string | null;
  session_submitted_at?: string | null;
  contractor_id?: string | null;
  contractor_business_name?: string | null;
  contractor_number?: string | null;
  contractor_email?: string | null;
  contractor_phone_number?: string | null;
  contractor_city?: string | null;
  latest_invoice_version_id?: string | null;
  latest_invoice_versionno?: number | null;
  latest_original_filename?: string | null;
  latest_di_ocr_invoice_total?: string | null;
  latest_di_ocr_invoice_date?: string | null;
  latest_di_ocr_vendor_name?: string | null;
  latest_di_ocr_invoice_id?: string | null;
  latest_genai_result?: 'pass' | 'warn' | 'fail' | string | null;
  latest_genai_overall_confidence?: number | null;
};

type InvoiceGridResponse = {
  rows: InvoiceGridRow[];
  meta?: unknown;
};

function getParam(search: string, key: string): string {
  return new URLSearchParams(search).get(key) ?? '';
}

function sanitizeDisplayTs(s?: string | null) {
  if (!s) return '';
  return String(s).replace('T', ' ').replace('Z', '');
}

export const AIAdminScreen = observer(function AIAdminScreen() {
  const location = useLocation();

  const sessionIdFromUrl = getParam(location.search, 'session_id');
  const invoiceIdFromUrl = getParam(location.search, 'invoice_id');
  const invoiceVersionIdFromUrl = getParam(location.search, 'invoice_version_id');

  const [sessionId, setSessionId] = useState(sessionIdFromUrl || '');
  const [invoiceId, setInvoiceId] = useState(invoiceIdFromUrl || '');
  const [invoiceVersionId, setInvoiceVersionId] = useState(invoiceVersionIdFromUrl || '');

  useEffect(() => setSessionId(sessionIdFromUrl || ''), [sessionIdFromUrl]);
  useEffect(() => setInvoiceId(invoiceIdFromUrl || ''), [invoiceIdFromUrl]);
  useEffect(() => setInvoiceVersionId(invoiceVersionIdFromUrl || ''), [invoiceVersionIdFromUrl]);

  const [ctxLoading, setCtxLoading] = useState(false);
  const [ctxError, setCtxError] = useState('');
  const [ctxRow, setCtxRow] = useState<InvoiceGridRow | null>(null);

  const fetchBusinessContext = useCallback(async () => {
    setCtxLoading(true);
    setCtxError('');
    setCtxRow(null);

    try {
      const sid = sessionId.trim();
      const iid = invoiceId.trim();
      if (!sid) throw new Error('Missing session_id.');
      if (!iid) throw new Error('Missing invoice_id.');

      const params = new URLSearchParams();
      params.set('session_id', sid);
      params.set('per', '200');
      params.set('page', '1');
      params.set('sort', 'latest_invoice_version_updated_at:desc');

      const res = await fetch(`/api/claims/admin/invoices?${params.toString()}`, {
        method: 'GET',
        headers: { Accept: 'application/json' },
        credentials: 'include',
      });
      const data: InvoiceGridResponse = await res.json().catch(() => ({ rows: [] }));

      if (!res.ok) throw new Error((data as any)?.error || (data as any)?.message || `HTTP ${res.status}`);

      const rows = Array.isArray(data?.rows) ? data.rows : [];
      const row = rows.find((r) => String(r.invoice_id) === String(iid)) ?? null;
      if (!row) throw new Error(`Invoice not found in session. session_id=${sid} invoice_id=${iid}`);

      setCtxRow(row);

      if (!invoiceVersionId.trim() && row.latest_invoice_version_id) {
        setInvoiceVersionId(String(row.latest_invoice_version_id));
      }
    } catch (e: any) {
      setCtxError(e?.message || 'Failed to load business context.');
    } finally {
      setCtxLoading(false);
    }
  }, [invoiceId, invoiceVersionId, sessionId]);

  useEffect(() => {
    if (!sessionId.trim() || !invoiceId.trim()) return;
    void fetchBusinessContext();
  }, [sessionId, invoiceId, fetchBusinessContext]);

  const [stepsLoading, setStepsLoading] = useState(false);
  const [stepsError, setStepsError] = useState('');
  const [steps, setSteps] = useState<IngestStepRow[]>([]);

  const [autoPollEnabled, setAutoPollEnabled] = useState(false);
  const [pollTargetInvoiceVersionId, setPollTargetInvoiceVersionId] = useState('');
  const [pollGraceUntilMs, setPollGraceUntilMs] = useState(0);

  const fetchStepsBySession = useCallback(async () => {
    setStepsLoading(true);
    setStepsError('');

    try {
      const sid = sessionId.trim();
      if (!sid) throw new Error('Enter a session_id first.');

      const params = new URLSearchParams();
      params.set('session_id', sid);
      params.set('limit', '200');

      const res = await fetch(`/api/claims/ingest/steps?${params.toString()}`, {
        method: 'GET',
        headers: { Accept: 'application/json' },
        credentials: 'include',
      });
      const data = await res.json().catch(() => ({}));

      if (!res.ok) throw new Error(data?.error || data?.message || `HTTP ${res.status}`);

      setSteps(Array.isArray(data?.steps) ? data.steps : []);
    } catch (e: any) {
      setStepsError(e?.message || 'Failed to load steps.');
    } finally {
      setStepsLoading(false);
    }
  }, [sessionId]);

  const [isRunningOcr, setIsRunningOcr] = useState(false);
  const [ocrError, setOcrError] = useState('');
  const [ocrOkMsg, setOcrOkMsg] = useState('');

  const [isRunningGenai, setIsRunningGenai] = useState(false);
  const [genaiError, setGenaiError] = useState('');
  const [genaiOkMsg, setGenaiOkMsg] = useState('');

  const [isRunningClassifier, setIsRunningClassifier] = useState(false);
  const [classifierError, setClassifierError] = useState('');
  const [classifierOkMsg, setClassifierOkMsg] = useState('');

  const POLL_INTERVAL_MS = 2500;
  const POLL_GRACE_MS = 45000;

  const hasPendingTargetStep = useMemo(() => {
    const target = pollTargetInvoiceVersionId.trim();
    if (!target) return false;

    return steps.some(
      (s) =>
        String(s.invoice_version_id || '') === target &&
        ['queued', 'in_progress'].includes(String(s.status || '').toLowerCase()),
    );
  }, [steps, pollTargetInvoiceVersionId]);

  const shouldPollSteps =
    autoPollEnabled &&
    !!sessionId.trim() &&
    (isRunningOcr || isRunningGenai || isRunningClassifier || Date.now() < pollGraceUntilMs || hasPendingTargetStep);

  useEffect(() => {
    if (!shouldPollSteps) return;

    const intervalId = window.setInterval(() => {
      void fetchStepsBySession();
    }, POLL_INTERVAL_MS);

    return () => window.clearInterval(intervalId);
  }, [shouldPollSteps, fetchStepsBySession]);

  const { isOpen: isHelpOpen, onOpen: onHelpOpen, onClose: onHelpClose } = useDisclosure();

  const beginPollingFor = async (invoiceVersionIdValue: string) => {
    setAutoPollEnabled(true);
    setPollTargetInvoiceVersionId(invoiceVersionIdValue);
    setPollGraceUntilMs(Date.now() + POLL_GRACE_MS);
    await fetchStepsBySession();
  };

  const handleRunOcr = async () => {
    setIsRunningOcr(true);
    setOcrError('');
    setOcrOkMsg('');

    try {
      const sid = sessionId.trim();
      const ivid = invoiceVersionId.trim();

      if (!sid) throw new Error('Enter a session_id first.');
      if (!ivid) throw new Error('Enter an invoice_version_id first (or load context).');

      await beginPollingFor(ivid);

      const res = await fetch('/api/claims/ingest/run_ocr', {
        method: 'POST',
        headers: { Accept: 'application/json', 'Content-Type': 'application/json' },
        credentials: 'include',
        body: JSON.stringify({ session_id: sid, invoice_version_id: ivid }),
      });

      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data?.error || data?.message || `HTTP ${res.status}`);

      const stepRunId = data?.step_run_id ?? data?.ingest_step_run_id ?? data?.id ?? '';
      setOcrOkMsg(
        String(
          data?.message ||
            data?.summary ||
            `OCR queued/started for invoice_version_id=${ivid}${stepRunId ? ` step_run_id=${stepRunId}` : ''}`,
        ),
      );

      setPollGraceUntilMs(Date.now() + POLL_GRACE_MS);
      await fetchStepsBySession();
    } catch (e: any) {
      setOcrError(e?.message || 'Run OCR failed.');
    } finally {
      setIsRunningOcr(false);
    }
  };

  const handleRunGenai = async () => {
    setIsRunningGenai(true);
    setGenaiError('');
    setGenaiOkMsg('');

    try {
      const sid = sessionId.trim();
      const ivid = invoiceVersionId.trim();

      if (!sid) throw new Error('Enter a session_id first.');
      if (!ivid) throw new Error('Enter an invoice_version_id first (or load context).');

      await beginPollingFor(ivid);

      const res = await fetch('/api/claims/ingest/run_genai', {
        method: 'POST',
        headers: { Accept: 'application/json', 'Content-Type': 'application/json' },
        credentials: 'include',
        body: JSON.stringify({ session_id: sid, invoice_version_id: ivid, mode: 'normal' }),
      });

      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data?.error || data?.message || `HTTP ${res.status}`);

      const stepRunId = data?.step_run_id ?? data?.ingest_step_run_id ?? data?.id ?? '';
      setGenaiOkMsg(
        String(
          data?.message ||
            data?.summary ||
            `GenAI full queued/started for invoice_version_id=${ivid}${stepRunId ? ` step_run_id=${stepRunId}` : ''}`,
        ),
      );

      setPollGraceUntilMs(Date.now() + POLL_GRACE_MS);
      await fetchStepsBySession();
    } catch (e: any) {
      setGenaiError(e?.message || 'Run GenAI full failed.');
    } finally {
      setIsRunningGenai(false);
    }
  };

  const handleRunClassifierOnly = async () => {
    setIsRunningClassifier(true);
    setClassifierError('');
    setClassifierOkMsg('');

    try {
      const sid = sessionId.trim();
      const ivid = invoiceVersionId.trim();

      if (!sid) throw new Error('Enter a session_id first.');
      if (!ivid) throw new Error('Enter an invoice_version_id first (or load context).');

      await beginPollingFor(ivid);

      const res = await fetch('/api/claims/ingest/run_genai', {
        method: 'POST',
        headers: { Accept: 'application/json', 'Content-Type': 'application/json' },
        credentials: 'include',
        body: JSON.stringify({ session_id: sid, invoice_version_id: ivid, mode: 'classifier_only' }),
      });

      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data?.error || data?.message || `HTTP ${res.status}`);

      const stepRunId = data?.step_run_id ?? data?.ingest_step_run_id ?? data?.id ?? '';
      setClassifierOkMsg(
        String(
          data?.message ||
            data?.summary ||
            `Classifier-only queued/started for invoice_version_id=${ivid}${stepRunId ? ` step_run_id=${stepRunId}` : ''}`,
        ),
      );

      setPollGraceUntilMs(Date.now() + POLL_GRACE_MS);
      await fetchStepsBySession();
    } catch (e: any) {
      setClassifierError(e?.message || 'Run classifier failed.');
    } finally {
      setIsRunningClassifier(false);
    }
  };

  return (
    <Flex as="main" direction="column" w="full" bg="greys.white" pb="24" minH="100vh">
      <ThinBlueTitleBar title="Invoices Admin - OCR & GenAI" />

      <Container maxW="container.xl" pb={4} flex="1" pt={6}>
        <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="lg" p={5} bg="white">
          <Flex justify="flex-end" mb={3}>
            <Tooltip label="Help: buttons, statuses, and step runs">
              <IconButton
                aria-label="Open OCR and GenAI help"
                icon={<Question size={18} />}
                size="sm"
                variant="outline"
                onClick={onHelpOpen}
              />
            </Tooltip>
          </Flex>

          <Flex direction="column" gap={4}>
            <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="md" p={4} bg="white">
              <Text as="div" fontSize="sm" fontWeight="bold" mb={2}>
                Autodetect Flow
              </Text>
              <Text as="div" fontSize="sm" opacity={0.8}>
                This screen no longer asks you to choose a ruleset. Full GenAI now starts from the invoice context on
                the server, and the classifier-only path is available as its own button for targeted testing.
              </Text>

              {ctxError && (
                <Box mt={3} p={3} bg="red.50" borderWidth="1px" borderColor="red.200" borderRadius="md">
                  <Text as="div" fontSize="sm" color="red.700">
                    {ctxError}
                  </Text>
                </Box>
              )}

              <Box mt={3} p={3} borderWidth="1px" borderColor="greys.grey20" borderRadius="md" bg="gray.50">
                {ctxLoading ? (
                  <Spinner size="sm" />
                ) : ctxRow ? (
                  <>
                    <Text as="div" fontSize="sm" fontWeight="bold" mb={3}>
                      Populated from the Invoice Admin screen
                    </Text>

                    <SimpleGrid columns={{ base: 1, md: 2, xl: 3 }} spacing={4}>
                      <Box>
                        <Text as="div" fontSize="xs" opacity={0.7}>
                          session_id
                        </Text>
                        <Text as="div" fontFamily="mono" fontSize="xs">
                          {ctxRow.session_id || '-'}
                        </Text>
                      </Box>
                      <Box>
                        <Text as="div" fontSize="xs" opacity={0.7}>
                          invoice_id
                        </Text>
                        <Text as="div" fontFamily="mono" fontSize="xs">
                          {ctxRow.invoice_id || '-'}
                        </Text>
                      </Box>
                      <Box>
                        <Text as="div" fontSize="xs" opacity={0.7}>
                          invoice_version_id
                        </Text>
                        <Text as="div" fontFamily="mono" fontSize="xs">
                          {invoiceVersionId || ctxRow.latest_invoice_version_id || '-'}
                        </Text>
                      </Box>

                      <Box>
                        <Text as="div" fontSize="xs" opacity={0.7}>
                          Contractor name
                        </Text>
                        <Text as="div" fontSize="sm" fontWeight="bold">
                          {ctxRow.contractor_business_name || '-'}
                        </Text>
                      </Box>
                      <Box>
                        <Text as="div" fontSize="xs" opacity={0.7}>
                          Contractor number
                        </Text>
                        <Text as="div" fontSize="xs">
                          {ctxRow.contractor_number || '-'}
                        </Text>
                      </Box>
                      <Box>
                        <Text as="div" fontSize="xs" opacity={0.7}>
                          Contractor city
                        </Text>
                        <Text as="div" fontSize="xs">
                          {ctxRow.contractor_city || '-'}
                        </Text>
                      </Box>

                      <Box>
                        <Text as="div" fontSize="xs" opacity={0.7}>
                          Contractor email
                        </Text>
                        <Text as="div" fontSize="xs">
                          {ctxRow.contractor_email || '-'}
                        </Text>
                      </Box>
                      <Box>
                        <Text as="div" fontSize="xs" opacity={0.7}>
                          Invoice status
                        </Text>
                        <Text as="div" fontSize="xs">
                          {ctxRow.invoice_status || '-'}
                        </Text>
                      </Box>
                      <Box>
                        <Text as="div" fontSize="xs" opacity={0.7}>
                          Filename
                        </Text>
                        <Text as="div" fontSize="xs">
                          {ctxRow.latest_original_filename || '-'}
                        </Text>
                      </Box>

                      <Box>
                        <Text as="div" fontSize="xs" opacity={0.7}>
                          OCR invoice #
                        </Text>
                        <Text as="div" fontSize="xs">
                          {ctxRow.latest_di_ocr_invoice_id || '-'}
                        </Text>
                      </Box>
                      <Box>
                        <Text as="div" fontSize="xs" opacity={0.7}>
                          OCR invoice date
                        </Text>
                        <Text as="div" fontSize="xs">
                          {ctxRow.latest_di_ocr_invoice_date || '-'}
                        </Text>
                      </Box>
                      <Box>
                        <Text as="div" fontSize="xs" opacity={0.7}>
                          OCR vendor
                        </Text>
                        <Text as="div" fontSize="xs">
                          {ctxRow.latest_di_ocr_vendor_name || '-'}
                        </Text>
                      </Box>

                      <Box>
                        <Text as="div" fontSize="xs" opacity={0.7}>
                          OCR total
                        </Text>
                        <Text as="div" fontSize="xs">
                          {ctxRow.latest_di_ocr_invoice_total || '-'}
                        </Text>
                      </Box>
                      <Box>
                        <Text as="div" fontSize="xs" opacity={0.7}>
                          GenAI confidence
                        </Text>
                        <Text as="div" fontSize="xs">
                          {ctxRow.latest_genai_overall_confidence ?? '-'}
                        </Text>
                      </Box>
                      <Box>
                        <Text as="div" fontSize="xs" opacity={0.7}>
                          GenAI result
                        </Text>
                        <Text as="div" fontSize="xs">
                          {ctxRow.latest_genai_result ?? '-'}
                        </Text>
                      </Box>
                    </SimpleGrid>
                  </>
                ) : (
                  <Text as="div" fontSize="sm" opacity={0.7}>
                    No context loaded yet. Open this screen from Invoices Admin (OCR / AI action) to populate it.
                  </Text>
                )}
              </Box>

              <Box mt={3} p={3} borderWidth="1px" borderColor="greys.grey20" borderRadius="md" bg="gray.50">
                <Text as="div" fontSize="xs" opacity={0.7}>
                  Full GenAI behavior
                </Text>
                <Text as="div" fontSize="sm">
                  Server side full GenAI now auto-resolves the current default/common ruleset instead of requiring a
                  manual ruleset selection on this screen.
                </Text>
              </Box>
            </Box>

            <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="md" p={4} bg="white">
              <Text as="div" fontSize="sm" fontWeight="bold" mb={3}>
                Run Actions
              </Text>

              <Flex gap={3} wrap="wrap">
                <Button
                  colorScheme="blue"
                  onClick={handleRunOcr}
                  isLoading={isRunningOcr}
                  loadingText="Running..."
                  isDisabled={!sessionId.trim() || !invoiceVersionId.trim()}
                >
                  Run OCR
                </Button>

                <Button
                  colorScheme="blue"
                  variant="outline"
                  onClick={handleRunGenai}
                  isLoading={isRunningGenai}
                  loadingText="Running..."
                  isDisabled={!sessionId.trim() || !invoiceVersionId.trim()}
                >
                  Run GenAI Full
                </Button>

                <Button
                  colorScheme="teal"
                  variant="outline"
                  onClick={handleRunClassifierOnly}
                  isLoading={isRunningClassifier}
                  loadingText="Running..."
                  isDisabled={!sessionId.trim() || !invoiceVersionId.trim()}
                >
                  Run GenAI ClassifierOnly
                </Button>
              </Flex>

              {ocrError && (
                <Box mt={3} p={3} bg="red.50" borderWidth="1px" borderColor="red.200" borderRadius="md">
                  <Text as="div" fontSize="sm" color="red.700">
                    {ocrError}
                  </Text>
                </Box>
              )}
              {ocrOkMsg && (
                <Box mt={3} p={3} bg="green.50" borderWidth="1px" borderColor="green.200" borderRadius="md">
                  <Text as="div" fontSize="sm" color="green.800">
                    {ocrOkMsg}
                  </Text>
                </Box>
              )}
              {genaiError && (
                <Box mt={3} p={3} bg="red.50" borderWidth="1px" borderColor="red.200" borderRadius="md">
                  <Text as="div" fontSize="sm" color="red.700">
                    {genaiError}
                  </Text>
                </Box>
              )}
              {genaiOkMsg && (
                <Box mt={3} p={3} bg="green.50" borderWidth="1px" borderColor="green.200" borderRadius="md">
                  <Text as="div" fontSize="sm" color="green.800">
                    {genaiOkMsg}
                  </Text>
                </Box>
              )}
              {classifierError && (
                <Box mt={3} p={3} bg="red.50" borderWidth="1px" borderColor="red.200" borderRadius="md">
                  <Text as="div" fontSize="sm" color="red.700">
                    {classifierError}
                  </Text>
                </Box>
              )}
              {classifierOkMsg && (
                <Box mt={3} p={3} bg="green.50" borderWidth="1px" borderColor="green.200" borderRadius="md">
                  <Text as="div" fontSize="sm" color="green.800">
                    {classifierOkMsg}
                  </Text>
                </Box>
              )}
            </Box>

            <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="md" p={4} bg="gray.50">
              <Flex align="center" justify="space-between" mb={3} wrap="wrap" gap={3}>
                <Box>
                  <Heading size="sm">Step Run Tracker</Heading>
                  <Text as="div" fontSize="xs" opacity={0.7}>
                    ingest_step_runs filtered by <Box as="code">session_id</Box>
                  </Text>
                </Box>

                <Flex gap={2} wrap="wrap">
                  <Tooltip label="Refresh steps">
                    <IconButton
                      aria-label="Refresh steps"
                      icon={<ArrowsClockwise size={18} />}
                      size="sm"
                      variant="outline"
                      onClick={fetchStepsBySession}
                      isLoading={stepsLoading}
                      isDisabled={!sessionId.trim()}
                    />
                  </Tooltip>
                </Flex>
              </Flex>

              {stepsError && (
                <Box mb={3} p={3} bg="red.50" borderWidth="1px" borderColor="red.200" borderRadius="md">
                  <Text as="div" fontSize="sm" color="red.700">
                    {stepsError}
                  </Text>
                </Box>
              )}

              <Box bg="white" borderWidth="1px" borderColor="greys.grey20" borderRadius="md" p={3}>
                <Flex align="center" justify="space-between" mb={2}>
                  <Text as="div" fontSize="sm" fontWeight="bold">
                    Steps
                  </Text>
                  {stepsLoading ? <Spinner size="sm" /> : null}
                </Flex>

                <Table size="sm">
                  <Thead>
                    <Tr>
                      <Th>created</Th>
                      <Th>step_id</Th>
                      <Th>type</Th>
                      <Th>state</Th>
                      <Th>invoice_version_id</Th>
                      <Th>ruleset</Th>
                      <Th>error</Th>
                    </Tr>
                  </Thead>

                  <Tbody>
                    {steps.map((s) => (
                      <Tr key={s.id}>
                        <Td fontFamily="mono" fontSize="xs">
                          {sanitizeDisplayTs(s.created_at)}
                        </Td>
                        <Td fontFamily="mono" fontSize="xs">
                          {s.id}
                        </Td>
                        <Td fontFamily="mono" fontSize="xs">
                          {s.step_type ?? ''}
                        </Td>
                        <Td fontSize="xs">
                          {String(s.status || '').toLowerCase() === 'in_progress' ? (
                            <Spinner size="sm" />
                          ) : String(s.status || '').toLowerCase() === 'queued' ? (
                            <Badge colorScheme="yellow">QUEUED</Badge>
                          ) : String(s.status || '').toLowerCase() === 'succeeded' ? (
                            <Badge colorScheme="green">OK</Badge>
                          ) : String(s.status || '').toLowerCase() === 'failed' ? (
                            <Badge colorScheme="red">FAIL</Badge>
                          ) : (
                            <Badge colorScheme="gray">{String(s.status || 'unknown').toUpperCase()}</Badge>
                          )}
                        </Td>
                        <Td fontFamily="mono" fontSize="xs">
                          {s.invoice_version_id ?? ''}
                        </Td>
                        <Td fontFamily="mono" fontSize="xs">
                          {s.validationgenai_ruleset_id ?? ''}
                        </Td>
                        <Td fontFamily="mono" fontSize="xs" whiteSpace="pre-wrap">
                          {s.error_text ?? ''}
                        </Td>
                      </Tr>
                    ))}

                    {!stepsLoading && steps.length === 0 && (
                      <Tr>
                        <Td colSpan={7}>
                          <Text as="div" fontSize="sm" opacity={0.7}>
                            No steps found.
                          </Text>
                        </Td>
                      </Tr>
                    )}
                  </Tbody>
                </Table>
              </Box>
            </Box>
          </Flex>
        </Box>
      </Container>

      <Drawer isOpen={isHelpOpen} placement="left" onClose={onHelpClose} size="xl">
        <DrawerOverlay />
        <DrawerContent>
          <DrawerCloseButton />
          <DrawerHeader>Invoices Admin OCR and GenAI Help</DrawerHeader>
          <DrawerBody>
            <Flex direction="column" gap={4}>
              <Box>
                <Heading size="sm" mb={2}>
                  Three Buttons
                </Heading>
                <Text as="div" fontSize="sm">
                  Run OCR sends the invoice PDF through Document Intelligence and writes OCR results back to the invoice
                  version.
                </Text>
                <Text as="div" fontSize="sm" mt={1}>
                  Run GenAI Full starts the server-side full path without asking you to choose a ruleset on this screen.
                </Text>
                <Text as="div" fontSize="sm" mt={1}>
                  Run GenAI ClassifierOnly stops after the classifier step so you can test upgrade-type detection in
                  isolation.
                </Text>
              </Box>

              <Box>
                <Heading size="sm" mb={2}>
                  Autodetect Flow
                </Heading>
                <Text as="div" fontSize="sm">
                  This screen is now aligned with the newer autodetect direction, so the old manual ruleset chooser has
                  been removed.
                </Text>
                <Text as="div" fontSize="sm" mt={1}>
                  For the current bridge behavior, full GenAI auto-resolves the current default/common ruleset on the
                  server rather than asking the admin to pick one here.
                </Text>
              </Box>

              <Box>
                <Heading size="sm" mb={2}>
                  Invoice State Basics
                </Heading>
                <Text as="div" fontSize="sm">
                  The state is tracked on the invoice, not on each invoice version.
                </Text>
                <Text as="div" fontSize="sm" mt={1}>
                  This means a newer version can move the same invoice back to an earlier-looking state, like going back
                  to upload work.
                </Text>
              </Box>

              <Box>
                <Heading size="sm" mb={2}>
                  Step Tracker
                </Heading>
                <Text as="div" fontSize="sm">
                  The Step Run Tracker shows rows from <Box as="code">ingest_step_runs</Box> for the current session.
                </Text>
                <Text as="div" fontSize="sm" mt={1}>
                  QUEUED means waiting in line, the spinner means in progress, OK means succeeded, and FAIL means the
                  step ended with an error.
                </Text>
                <Text as="div" fontSize="sm" mt={1}>
                  The ruleset column is still useful for seeing what the backend recorded on full GenAI runs, even
                  though admins no longer choose that value from this screen.
                </Text>
              </Box>
            </Flex>
          </DrawerBody>
        </DrawerContent>
      </Drawer>
    </Flex>
  );
});
