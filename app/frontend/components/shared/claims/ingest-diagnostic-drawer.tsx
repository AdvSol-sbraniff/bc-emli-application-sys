import React, { useEffect, useState } from 'react';
import {
  Badge,
  Box,
  Button,
  Code,
  Divider,
  Drawer,
  DrawerBody,
  DrawerCloseButton,
  DrawerContent,
  DrawerHeader,
  DrawerOverlay,
  Flex,
  HStack,
  SimpleGrid,
  Spinner,
  Text,
  useToast,
  VStack,
} from '@chakra-ui/react';
import { CopySimple } from '@phosphor-icons/react';

export type IngestAttemptSummary = {
  total_attempts?: number;
  failed_attempts?: number;
  recovered_attempts?: number;
  retried_targets?: number;
  retrying_targets?: number;
  failed_targets?: number;
};

export type IngestStepDiagnostics = {
  failure_category?: string | null;
  failure_code?: string | null;
  error_code?: string | null;
  error_category?: string | null;
  error_phase?: string | null;
  retryable?: boolean | null;
  diagnostic_id?: string | null;
  provider_status?: number | null;
  provider_code?: string | null;
  provider_attempt_count?: number | null;
};

export type IngestRunDiagnostic = {
  id: string;
  session_id?: string | null;
  run_kind?: string | null;
  invoice_id?: string | null;
  contractor_id?: string | null;
  contractor_business_name?: string | null;
  contractor_number?: string | null;
  resolved_invoice_version_id?: string | null;
  status?: string | null;
  cleanup_failed_invoice_artifacts?: boolean;
  total_files?: number;
  completed_files?: number;
  failed_files?: number;
  pipeline_error_code?: string | null;
  pipeline_error_description?: string | null;
  failure_category?: string | null;
  failure_code?: string | null;
  attempt_summary?: IngestAttemptSummary | null;
  terminal_failure?:
    | (IngestStepDiagnostics & { step_id?: string | null; step_type?: string | null; error_text?: string | null })
    | null;
  created_at?: string | null;
  updated_at?: string | null;
  completed_at?: string | null;
  duration_seconds?: number | null;
};

export type IngestStepDiagnostic = IngestStepDiagnostics & {
  id: string;
  ingest_run_id?: string | null;
  session_id?: string | null;
  invoice_id?: string | null;
  invoice_version_id?: string | null;
  ingest_document_id?: string | null;
  ingest_document_original_filename?: string | null;
  original_filename?: string | null;
  invoice_upgrade_type_id?: string | null;
  invoice_upgrade_type_key?: string | null;
  invoice_upgrade_type_description?: string | null;
  supporting_document_type_id?: string | null;
  supporting_document_type_key?: string | null;
  supporting_document_type_description?: string | null;
  step_type?: string | null;
  status?: string | null;
  display_status?: string | null;
  logical_state?: string | null;
  attempt_number?: number | null;
  attempt_count?: number | null;
  attempt_limit?: number | null;
  effective_attempt?: boolean;
  error_text?: string | null;
  step_note?: string | null;
  created_at?: string | null;
  updated_at?: string | null;
  completed_at?: string | null;
  duration_seconds?: number | null;
  [key: string]: unknown;
};

export type IngestInvoiceDiagnostic = {
  invoice_id?: string | null;
  invoice_version_id?: string | null;
  invoice_versionno?: number | null;
  original_filename?: string | null;
  invoice_status?: string | null;
  invoice_status_updated_at?: string | null;
  created_at?: string | null;
  updated_at?: string | null;
  [key: string]: unknown;
};

export type IngestDiagnosticSelection =
  | { kind: 'run'; title: string; value: IngestRunDiagnostic }
  | { kind: 'step'; title: string; value: IngestStepDiagnostic }
  | { kind: 'invoice'; title: string; value: IngestInvoiceDiagnostic };

type Props = {
  isOpen: boolean;
  onClose: () => void;
  selection: IngestDiagnosticSelection | null;
};

export function formatIngestTimestamp(value?: string | null) {
  if (!value) return '—';
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? String(value) : parsed.toLocaleString();
}

export function formatIngestDuration(value?: number | null) {
  const seconds = Number(value);
  if (!Number.isFinite(seconds) || seconds < 0) return '—';
  if (seconds < 1) return `${Math.round(seconds * 1000)} ms`;
  if (seconds < 60) return `${seconds.toFixed(1)} s`;
  const minutes = Math.floor(seconds / 60);
  const remainingSeconds = seconds - minutes * 60;
  if (minutes < 60) return `${minutes}m ${remainingSeconds.toFixed(1)}s`;
  return `${Math.floor(minutes / 60)}h ${minutes % 60}m`;
}

export function ingestStatusColor(status?: string | null) {
  const value = String(status || '').toLowerCase();
  if (value === 'succeeded') return 'green';
  if (value === 'recovered') return 'gray';
  if (value === 'failed') return 'red';
  if (value === 'retrying') return 'orange';
  if (value === 'running' || value === 'in_progress') return 'blue';
  if (value === 'queued') return 'yellow';
  return 'gray';
}

export function IngestDiagnosticDrawer({ isOpen, onClose, selection }: Props) {
  const toast = useToast();
  const [record, setRecord] = useState<IngestDiagnosticSelection['value'] | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const [showRaw, setShowRaw] = useState(false);

  useEffect(() => {
    setRecord(selection?.value || null);
    setError('');
    setShowRaw(false);
    if (!isOpen || selection?.kind !== 'step') {
      setLoading(false);
      return;
    }

    const controller = new AbortController();
    setLoading(true);
    void fetch(`/api/claims/admin/ingest_step_runs/${encodeURIComponent(selection.value.id)}`, {
      method: 'GET',
      headers: { Accept: 'application/json' },
      credentials: 'include',
      cache: 'no-store',
      signal: controller.signal,
    })
      .then(async (response) => {
        const payload = await response.json().catch(() => ({}));
        if (!response.ok) throw new Error(payload?.error || payload?.message || `HTTP ${response.status}`);
        setRecord(payload as IngestStepDiagnostic);
      })
      .catch((caught: unknown) => {
        if (controller.signal.aborted) return;
        setError(caught instanceof Error ? caught.message : 'Failed to load full step details.');
      })
      .finally(() => {
        if (!controller.signal.aborted) setLoading(false);
      });

    return () => controller.abort();
  }, [isOpen, selection]);

  const copyValue = async (label: string, value?: string | null) => {
    if (!value) return;
    try {
      await navigator.clipboard.writeText(value);
      toast({ title: `${label} copied`, status: 'success', duration: 1500 });
    } catch {
      toast({ title: `Could not copy ${label}`, status: 'error', duration: 2500 });
    }
  };

  return (
    <Drawer isOpen={isOpen} placement="right" size="xl" onClose={onClose}>
      <DrawerOverlay />
      <DrawerContent>
        <DrawerCloseButton />
        <DrawerHeader>{selection?.title || 'Ingest details'}</DrawerHeader>
        <DrawerBody pb={8}>
          {loading ? (
            <HStack mb={4}>
              <Spinner size="sm" />
              <Text>Loading full step details…</Text>
            </HStack>
          ) : null}
          {error ? (
            <Box mb={4} p={3} bg="red.50" borderWidth="1px" borderColor="red.200" borderRadius="md">
              <Text color="red.700">Showing retained summary. Full details could not be refreshed: {error}</Text>
            </Box>
          ) : null}

          {selection?.kind === 'run' && record ? (
            <RunSummary run={record as IngestRunDiagnostic} copyValue={copyValue} />
          ) : null}
          {selection?.kind === 'step' && record ? (
            <StepSummary step={record as IngestStepDiagnostic} copyValue={copyValue} />
          ) : null}
          {selection?.kind === 'invoice' && record ? (
            <InvoiceSummary invoice={record as IngestInvoiceDiagnostic} copyValue={copyValue} />
          ) : null}

          {record ? (
            <Box mt={6}>
              <Button size="sm" variant="outline" onClick={() => setShowRaw((current) => !current)}>
                {showRaw ? 'Hide raw record' : 'Show raw record and payloads'}
              </Button>
              {showRaw ? <JsonDetail value={record} /> : null}
            </Box>
          ) : null}
        </DrawerBody>
      </DrawerContent>
    </Drawer>
  );
}

type CopyValue = (label: string, value?: string | null) => Promise<void>;

function RunSummary({ run, copyValue }: { run: IngestRunDiagnostic; copyValue: CopyValue }) {
  const attempts = run.attempt_summary;
  return (
    <VStack align="stretch" spacing={5}>
      <HStack spacing={2} wrap="wrap">
        <Badge colorScheme={ingestStatusColor(run.status)}>{run.status || 'unknown'}</Badge>
        {attempts?.recovered_attempts ? (
          <Badge colorScheme="gray">{attempts.recovered_attempts} recovered</Badge>
        ) : null}
        {attempts?.retrying_targets ? <Badge colorScheme="orange">{attempts.retrying_targets} retrying</Badge> : null}
        {attempts?.failed_targets ? <Badge colorScheme="red">{attempts.failed_targets} failed targets</Badge> : null}
      </HStack>
      <SimpleGrid columns={{ base: 1, md: 2 }} spacing={4}>
        <Field label="Contractor" value={run.contractor_business_name || 'System / no contractor'} />
        <Field label="Contractor number" value={run.contractor_number} />
        <Field label="Run kind" value={run.run_kind} />
        <Field label="Started" value={formatIngestTimestamp(run.created_at)} />
        <Field label="Completed" value={formatIngestTimestamp(run.completed_at)} />
        <Field label="Duration" value={formatIngestDuration(run.duration_seconds)} />
        <Field label="Files" value={`${run.completed_files || 0}/${run.total_files || 0}`} />
      </SimpleGrid>
      {run.terminal_failure || run.pipeline_error_code ? (
        <Box p={4} bg="red.50" borderWidth="1px" borderColor="red.200" borderRadius="md">
          <Text fontWeight="bold">Terminal failure</Text>
          <Text fontSize="sm">{run.terminal_failure?.error_code || run.pipeline_error_code}</Text>
          <Text fontSize="sm" mt={1}>
            {run.terminal_failure?.error_text || run.pipeline_error_description}
          </Text>
        </Box>
      ) : null}
      <Divider />
      <IdentifierList
        rows={[
          ['Run ID', run.id],
          ['Session ID', run.session_id],
          ['Invoice ID', run.invoice_id],
          ['Contractor ID', run.contractor_id],
          ['Resolved invoice version ID', run.resolved_invoice_version_id],
          ['Terminal step ID', run.terminal_failure?.step_id],
          ['Diagnostic ID', run.terminal_failure?.diagnostic_id],
        ]}
        copyValue={copyValue}
      />
    </VStack>
  );
}

function StepSummary({ step, copyValue }: { step: IngestStepDiagnostic; copyValue: CopyValue }) {
  const displayStatus = step.display_status || step.status;
  const attempt = step.attempt_number && step.attempt_count ? `${step.attempt_number} of ${step.attempt_count}` : '—';
  return (
    <VStack align="stretch" spacing={5}>
      <HStack spacing={2} wrap="wrap">
        <Badge colorScheme={ingestStatusColor(displayStatus)}>{displayStatus || 'unknown'}</Badge>
        <Badge colorScheme="gray">{step.step_type || 'unknown step'}</Badge>
        <Badge colorScheme={step.effective_attempt ? 'blue' : 'gray'}>
          {step.effective_attempt ? 'effective attempt' : 'retained history'}
        </Badge>
      </HStack>
      <SimpleGrid columns={{ base: 1, md: 2 }} spacing={4}>
        <Field label="Attempt" value={attempt} />
        <Field label="Logical outcome" value={step.logical_state} />
        <Field label="Started" value={formatIngestTimestamp(step.created_at)} />
        <Field label="Completed" value={formatIngestTimestamp(step.completed_at)} />
        <Field label="Duration" value={formatIngestDuration(step.duration_seconds)} />
        <Field label="File" value={step.ingest_document_original_filename || step.original_filename} />
        <Field label="Upgrade type" value={step.invoice_upgrade_type_description || step.invoice_upgrade_type_key} />
        <Field
          label="Supporting type"
          value={step.supporting_document_type_description || step.supporting_document_type_key}
        />
      </SimpleGrid>
      {step.error_code || step.error_text ? (
        <Box p={4} bg={displayStatus === 'recovered' ? 'gray.50' : 'red.50'} borderWidth="1px" borderRadius="md">
          <Text fontWeight="bold">{displayStatus === 'recovered' ? 'Recovered failure' : 'Failure details'}</Text>
          <SimpleGrid columns={{ base: 1, md: 2 }} spacing={3} mt={2}>
            <Field label="Error code" value={step.error_code} />
            <Field
              label="Category / phase"
              value={[step.error_category, step.error_phase].filter(Boolean).join(' / ')}
            />
            <Field label="Provider" value={providerLabel(step)} />
            <Field label="Retryable" value={step.retryable == null ? '—' : step.retryable ? 'Yes' : 'No'} />
          </SimpleGrid>
          <Text fontSize="sm" mt={3} whiteSpace="pre-wrap">
            {step.error_text}
          </Text>
        </Box>
      ) : null}
      <Divider />
      <IdentifierList
        rows={[
          ['Step ID', step.id],
          ['Run ID', step.ingest_run_id],
          ['Session ID', step.session_id],
          ['Invoice ID', step.invoice_id],
          ['Invoice version ID', step.invoice_version_id],
          ['Ingest document ID', step.ingest_document_id],
          ['Upgrade type ID', step.invoice_upgrade_type_id],
          ['Supporting type ID', step.supporting_document_type_id],
          ['Diagnostic ID', step.diagnostic_id],
        ]}
        copyValue={copyValue}
      />
    </VStack>
  );
}

function InvoiceSummary({ invoice, copyValue }: { invoice: IngestInvoiceDiagnostic; copyValue: CopyValue }) {
  return (
    <VStack align="stretch" spacing={5}>
      <HStack spacing={2} wrap="wrap">
        <Badge colorScheme={ingestStatusColor(invoice.invoice_status)}>{invoice.invoice_status || 'unknown'}</Badge>
      </HStack>
      <SimpleGrid columns={{ base: 1, md: 2 }} spacing={4}>
        <Field label="Filename" value={invoice.original_filename} />
        <Field label="Version" value={invoice.invoice_versionno == null ? '—' : `v${invoice.invoice_versionno}`} />
        <Field label="Status updated" value={formatIngestTimestamp(invoice.invoice_status_updated_at)} />
        <Field label="Created" value={formatIngestTimestamp(invoice.created_at)} />
      </SimpleGrid>
      <Divider />
      <IdentifierList
        rows={[
          ['Invoice ID', invoice.invoice_id],
          ['Invoice version ID', invoice.invoice_version_id],
        ]}
        copyValue={copyValue}
      />
    </VStack>
  );
}

function Field({ label, value }: { label: string; value?: React.ReactNode }) {
  return (
    <Box>
      <Text fontSize="xs" color="gray.600" textTransform="uppercase" fontWeight="bold">
        {label}
      </Text>
      <Text fontSize="sm" mt={1}>
        {value || '—'}
      </Text>
    </Box>
  );
}

function IdentifierList({
  rows,
  copyValue,
}: {
  rows: Array<[string, string | null | undefined]>;
  copyValue: CopyValue;
}) {
  const visibleRows = rows.filter(([, value]) => !!value);
  if (!visibleRows.length) return null;
  return (
    <VStack align="stretch" spacing={3}>
      <Text fontWeight="bold">Identifiers</Text>
      {visibleRows.map(([label, value]) => (
        <Flex key={label} justify="space-between" align="center" gap={3}>
          <Box minW={0}>
            <Text fontSize="xs" color="gray.600">
              {label}
            </Text>
            <Text fontFamily="mono" fontSize="xs" wordBreak="break-all">
              {value}
            </Text>
          </Box>
          <Button
            aria-label={`Copy ${label}`}
            leftIcon={<CopySimple size={15} />}
            size="xs"
            variant="outline"
            flexShrink={0}
            onClick={() => void copyValue(label, value)}
          >
            Copy
          </Button>
        </Flex>
      ))}
    </VStack>
  );
}

function providerLabel(step: IngestStepDiagnostics) {
  const parts = [step.provider_status ? `HTTP ${step.provider_status}` : '', step.provider_code || ''];
  if (step.provider_attempt_count) parts.push(`${step.provider_attempt_count} provider attempts`);
  return parts.filter(Boolean).join(' · ') || '—';
}

function JsonDetail({ value }: { value: unknown }) {
  return (
    <Code
      display="block"
      mt={3}
      p={4}
      w="full"
      overflowX="auto"
      whiteSpace="pre-wrap"
      wordBreak="break-word"
      fontSize="xs"
      bg="gray.50"
      borderWidth="1px"
      borderColor="gray.200"
      borderRadius="md"
    >
      {JSON.stringify(value, null, 2)}
    </Code>
  );
}
