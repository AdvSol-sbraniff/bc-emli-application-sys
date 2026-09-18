import {
  Accordion,
  AccordionButton,
  AccordionIcon,
  AccordionItem,
  AccordionPanel,
  Alert,
  AlertIcon,
  Box,
  Button,
  Flex,
  FormControl,
  FormLabel,
  Input,
  Link,
  ListItem,
  Select,
  Spinner,
  Table,
  Tbody,
  Td,
  Text,
  Textarea,
  Th,
  Thead,
  Tr,
  UnorderedList,
  VisuallyHidden,
} from '@chakra-ui/react';
import React, { useEffect, useMemo, useRef, useState } from 'react';
import { Link as RouterLink } from 'react-router-dom';
import { formatClaimsReferenceNumber } from '../../../utils/format-claims-reference-number';
import { REVISION_CLOSURE_LABELS } from '../../shared/claims/revision-closure-guidance';
import { AuditPackage, AuditResponse, loadAuditPackages } from './package-audit-data';
import { RuleRow, shortDate, titleize } from './types';

const PAGE_SIZE = 25;
const OUTCOME_LABELS: Record<string, string> = {
  ...REVISION_CLOSURE_LABELS,
  open: 'Open',
  pending_admin_review: 'Pending admin review',
  unknown: 'Outcome not recorded',
};

function invoiceLabel(invoice: AuditPackage) {
  const reference = invoice.latestCheck.invoice_reference_number;
  return reference === null || reference === undefined ? invoice.invoiceId : formatClaimsReferenceNumber(reference);
}

export function RulePackageAudits({
  rule,
  evidenceUrl,
  auditUrl,
}: {
  rule: RuleRow;
  evidenceUrl: string;
  auditUrl: string;
}) {
  const [packages, setPackages] = useState<AuditPackage[]>([]);
  const [loading, setLoading] = useState(true);
  const [progress, setProgress] = useState({ loaded: 0, total: 0 });
  const [error, setError] = useState('');
  const [retry, setRetry] = useState(0);
  const [search, setSearch] = useState('');
  const [sort, setSort] = useState('signals');
  const [page, setPage] = useState(1);
  const [audit, setAudit] = useState<{ invoice: AuditPackage; response: AuditResponse } | null>(null);
  const [auditingInvoice, setAuditingInvoice] = useState<AuditPackage | null>(null);
  const [auditError, setAuditError] = useState('');
  const [failedInvoice, setFailedInvoice] = useState<AuditPackage | null>(null);
  const auditRequest = useRef<AbortController | null>(null);
  const outputRef = useRef<HTMLDivElement>(null);

  useEffect(() => () => auditRequest.current?.abort(), []);

  async function runAudit(invoice: AuditPackage) {
    if (auditRequest.current) return;
    const controller = new AbortController();
    auditRequest.current = controller;
    setAuditingInvoice(invoice);
    setAudit(null);
    setAuditError('');
    setFailedInvoice(null);
    const timeout = window.setTimeout(() => controller.abort(), 310_000);
    try {
      const response = await fetch(auditUrl, {
        method: 'POST',
        credentials: 'include',
        headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
        signal: controller.signal,
        body: JSON.stringify({
          invoice_id: invoice.invoiceId,
          selected_invoice_version_id: invoice.latestCheck.invoice_version_id,
        }),
      });
      const data = await response.json().catch(() => {
        throw new Error(`The AI audit service returned an unreadable response (${response.status}). Please try again.`);
      });
      if (!response.ok) throw new Error(data.error || `The AI audit could not complete (${response.status}).`);
      if (
        typeof data.advice !== 'string' ||
        !data.advice.trim() ||
        ['proposed_rule_prompt', 'proposed_precheck_action', 'proposed_contractor_guidance'].some(
          (key) => data[key] !== null && typeof data[key] !== 'string',
        )
      )
        throw new Error('The AI audit returned an incomplete response. Please try again.');
      if (!controller.signal.aborted) setAudit({ invoice, response: data });
    } catch (failure: unknown) {
      setAuditError(
        controller.signal.aborted
          ? 'The AI audit timed out or was cancelled. Please try again.'
          : failure instanceof Error
            ? failure.message
            : 'The AI audit could not complete.',
      );
      setFailedInvoice(invoice);
    } finally {
      window.clearTimeout(timeout);
      auditRequest.current = null;
      setAuditingInvoice(null);
    }
  }

  useEffect(() => {
    const controller = new AbortController();
    setLoading(true);
    setError('');
    setProgress({ loaded: 0, total: 0 });
    void loadAuditPackages(evidenceUrl, controller.signal, (loaded, total) => {
      if (!controller.signal.aborted) setProgress({ loaded, total });
    })
      .then((rows) => {
        if (!controller.signal.aborted) setPackages(rows);
      })
      .catch((loadError: unknown) => {
        if (!controller.signal.aborted) {
          setError(loadError instanceof Error ? loadError.message : 'Unable to load invoice packages.');
        }
      })
      .finally(() => {
        if (!controller.signal.aborted) setLoading(false);
      });
    return () => controller.abort();
  }, [evidenceUrl, retry]);

  useEffect(() => {
    if (audit || auditingInvoice || auditError) {
      outputRef.current?.scrollIntoView({ behavior: 'smooth', block: 'start' });
      outputRef.current?.focus({ preventScroll: true });
    }
  }, [audit, auditingInvoice, auditError]);

  const filtered = useMemo(() => {
    const query = search.trim().toLowerCase();
    const rows = packages.filter((invoice) =>
      [
        invoiceLabel(invoice),
        String(invoice.latestCheck.invoice_reference_number ?? ''),
        invoice.invoiceId,
        invoice.latestCheck.contractor_business_name,
      ]
        .join(' ')
        .toLowerCase()
        .includes(query),
    );
    return rows.sort((a, b) => {
      let comparison = 0;
      if (sort === 'signals') comparison = b.complaintCount - a.complaintCount || b.sentRoundCount - a.sentRoundCount;
      if (sort === 'rounds') comparison = b.sentRoundCount - a.sentRoundCount;
      if (sort === 'invoice') comparison = invoiceLabel(a).localeCompare(invoiceLabel(b), undefined, { numeric: true });
      if (sort === 'contractor')
        comparison = a.latestCheck.contractor_business_name.localeCompare(b.latestCheck.contractor_business_name);
      return (
        comparison ||
        b.latestCheck.rulecheck_created_at.localeCompare(a.latestCheck.rulecheck_created_at) ||
        invoiceLabel(a).localeCompare(invoiceLabel(b), undefined, { numeric: true }) ||
        a.invoiceId.localeCompare(b.invoiceId)
      );
    });
  }, [packages, search, sort]);
  const pages = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE));
  const currentPage = Math.min(page, pages);
  const visible = filtered.slice((currentPage - 1) * PAGE_SIZE, currentPage * PAGE_SIZE);

  return (
    <Box>
      <Alert status="info" mb={4}>
        <AlertIcon />
        <Text fontSize="sm">
          Run AI audit reviews this rule against the package documents and recorded history. Review its advice against
          the evidence before using any suggested wording. Results are not saved; copy any advice you need before
          leaving or reloading. Suggested changes are not applied automatically.
        </Text>
      </Alert>
      <Text fontSize="sm" color="gray.600" mb={4}>
        One row per invoice package checked by this rule in the current reporting period, from{' '}
        {shortDate(rule.current_effective_at)}. Counts cover this rule only.
      </Text>
      {loading ? (
        <Flex py={10} align="center" justify="center" gap={3} role="status">
          <Spinner />
          <Text>
            {progress.total
              ? `Loading rule checks: ${progress.loaded.toLocaleString()} of ${progress.total.toLocaleString()}`
              : 'Loading invoice packages…'}
          </Text>
        </Flex>
      ) : error ? (
        <Alert status="error">
          <AlertIcon />
          <Text flex="1">{error}</Text>
          <Button ml={3} size="sm" onClick={() => setRetry((value) => value + 1)}>
            Try again
          </Button>
        </Alert>
      ) : (
        <>
          <Flex gap={4} mb={4} wrap="wrap" align="end">
            <FormControl flex="1" minW="240px">
              <FormLabel htmlFor="audit-package-search" fontSize="sm">
                Find an invoice or contractor
              </FormLabel>
              <Input
                id="audit-package-search"
                value={search}
                onChange={(event) => {
                  setSearch(event.target.value);
                  setPage(1);
                }}
                placeholder="Invoice reference or contractor name"
              />
            </FormControl>
            <FormControl maxW="300px">
              <FormLabel htmlFor="audit-package-sort" fontSize="sm">
                Sort by
              </FormLabel>
              <Select
                id="audit-package-sort"
                value={sort}
                onChange={(event) => {
                  setSort(event.target.value);
                  setPage(1);
                }}
              >
                <option value="signals">Most complaints, then rounds</option>
                <option value="rounds">Most sent rounds</option>
                <option value="recent">Most recently checked</option>
                <option value="invoice">Invoice reference</option>
                <option value="contractor">Contractor</option>
              </Select>
            </FormControl>
          </Flex>
          <Text fontSize="sm" mb={3}>
            {filtered.length.toLocaleString()} of {packages.length.toLocaleString()} invoice packages
          </Text>
          <Box overflowX="auto" position="relative">
            <Table size="sm" minW="1000px" aria-label="Invoice packages for this rule">
              <Thead>
                <Tr>
                  <Th>Invoice</Th>
                  <Th>Contractor</Th>
                  <Th>Last checked</Th>
                  <Th title="Results for this rule on the latest checked version. Multiple upgrade checks can have different results.">
                    Latest rule result
                  </Th>
                  <Th isNumeric title="Distinct rule checks with a complaint in the current reporting period.">
                    Complaints
                  </Th>
                  <Th
                    isNumeric
                    title="Sum of sent rounds across distinct issues linked to this rule. A round containing several issues may contribute more than once."
                  >
                    Sent rounds
                  </Th>
                  <Th>Workflow outcomes</Th>
                  <Th>
                    <VisuallyHidden>Audit</VisuallyHidden>
                  </Th>
                </Tr>
              </Thead>
              <Tbody>
                {visible.map((invoice) => (
                  <Tr
                    key={invoice.invoiceId}
                    bg={audit?.invoice.invoiceId === invoice.invoiceId ? 'blue.50' : undefined}
                  >
                    <Td whiteSpace="nowrap">
                      <Link
                        as={RouterLink}
                        to={`/invoice-versions-by-version/${invoice.latestCheck.invoice_version_id}/read`}
                        target="_blank"
                        rel="noopener noreferrer"
                        color="blue.600"
                      >
                        {invoiceLabel(invoice)}
                      </Link>
                    </Td>
                    <Td>{invoice.latestCheck.contractor_business_name || 'Not recorded'}</Td>
                    <Td whiteSpace="nowrap">{shortDate(invoice.latestCheck.rulecheck_created_at)}</Td>
                    <Td>{invoice.results.map(titleize).join(' / ')}</Td>
                    <Td isNumeric>{invoice.complaintCount}</Td>
                    <Td isNumeric>{invoice.sentRoundCount}</Td>
                    <Td maxW="270px">
                      {invoice.outcomes.length
                        ? invoice.outcomes.map((outcome) => OUTCOME_LABELS[outcome] || titleize(outcome)).join('; ')
                        : 'No linked issue'}
                    </Td>
                    <Td>
                      <Button
                        size="sm"
                        variant="outline"
                        colorScheme="blue"
                        aria-label={`Run AI audit for ${invoiceLabel(invoice)}`}
                        onClick={() => void runAudit(invoice)}
                        isLoading={auditingInvoice?.invoiceId === invoice.invoiceId}
                        isDisabled={Boolean(auditingInvoice)}
                      >
                        Run AI audit
                      </Button>
                    </Td>
                  </Tr>
                ))}
                {!visible.length && (
                  <Tr>
                    <Td colSpan={8} py={8} textAlign="center" color="gray.600">
                      {packages.length
                        ? 'No invoice packages match your search.'
                        : 'No invoice packages have been checked by this rule in the current reporting period.'}
                    </Td>
                  </Tr>
                )}
              </Tbody>
            </Table>
          </Box>
          {pages > 1 && (
            <Flex justify="end" align="center" gap={3} mt={4}>
              <Button
                size="sm"
                variant="outline"
                isDisabled={currentPage === 1}
                onClick={() => setPage(currentPage - 1)}
              >
                Previous
              </Button>
              <Text fontSize="sm">
                Page {currentPage} of {pages}
              </Text>
              <Button
                size="sm"
                variant="outline"
                isDisabled={currentPage === pages}
                onClick={() => setPage(currentPage + 1)}
              >
                Next
              </Button>
            </Flex>
          )}
          <Box
            ref={outputRef}
            tabIndex={-1}
            role="region"
            aria-label="Package audit output"
            _focus={{ outline: 'none' }}
            mt={8}
            pt={5}
            borderTopWidth="2px"
            scrollMarginTop="24px"
          >
            <Text as="h2" fontSize="xl" fontWeight="bold" mb={2}>
              AI audit advice
            </Text>
            {auditingInvoice && (
              <Flex align="center" gap={3} mb={4} role="status">
                <Spinner size="sm" />
                <Text>
                  Auditing {invoiceLabel(auditingInvoice)} and its package history. This may take a few minutes.
                </Text>
              </Flex>
            )}
            {auditError && (
              <Alert status="error" mb={4}>
                <AlertIcon />
                <Text flex="1">{auditError}</Text>
                {failedInvoice && (
                  <Button ml={3} size="sm" onClick={() => void runAudit(failedInvoice)}>
                    Retry audit
                  </Button>
                )}
              </Alert>
            )}
            {!audit && !auditingInvoice && !auditError ? (
              <Text color="gray.600" mb={4}>
                Choose Run AI audit beside an invoice to see the advice and any suggested wording here.
              </Text>
            ) : audit ? (
              <>
                <Flex justify="space-between" align="start" gap={3} wrap="wrap" mb={4}>
                  <Box>
                    <Text fontWeight="semibold">
                      {invoiceLabel(audit.invoice)} · {rule.contractor_display_name}
                    </Text>
                    <Text fontSize="sm" color="gray.600">
                      {audit.response.completed_at
                        ? new Date(audit.response.completed_at).toLocaleString()
                        : 'Audit complete'}
                      {audit.response.transport?.deployment ? ` · ${audit.response.transport.deployment}` : ''}
                    </Text>
                  </Box>
                  <Link
                    as={RouterLink}
                    to={`/invoice-versions-by-version/${audit.invoice.latestCheck.invoice_version_id}/read`}
                    target="_blank"
                    rel="noopener noreferrer"
                    color="blue.600"
                  >
                    Open invoice package
                  </Link>
                </Flex>
              </>
            ) : null}
            {audit && (
              <Accordion allowToggle mb={5}>
                <AccordionItem>
                  <h3>
                    <AccordionButton>
                      <Text flex="1" textAlign="left">
                        Evidence included and limitations
                      </Text>
                      <AccordionIcon />
                    </AccordionButton>
                  </h3>
                  <AccordionPanel fontSize="sm">
                    <Text mb={2}>
                      {audit.response.evidence?.version_count ?? 'Unknown'} invoice versions;{' '}
                      {audit.response.transport?.attachment_count ?? 'unknown'} source files supplied to the model.
                      Earlier and later evidence is identified separately in the audit context.
                    </Text>
                    <UnorderedList spacing={2}>
                      {(audit.response.evidence?.limitations || []).map((limitation, index) => (
                        <ListItem key={index}>{limitation}</ListItem>
                      ))}
                    </UnorderedList>
                  </AccordionPanel>
                </AccordionItem>
              </Accordion>
            )}
            <AuditOutputField
              id="audit-advice"
              label="Audit advice"
              value={audit?.response.advice ?? null}
              placeholder="The audit findings, supporting evidence and advice on what to improve will appear here."
              rows={8}
            />
            <AuditOutputField
              id="audit-rule-prompt"
              label="Suggested rule prompt"
              value={audit?.response.proposed_rule_prompt ?? null}
              placeholder={
                rule.source_engine === 'code'
                  ? 'Not applicable: this rule uses code rather than a GenAI prompt.'
                  : audit
                    ? 'No rule prompt change suggested.'
                    : 'A suggested replacement rule prompt will appear here if the audit recommends a prompt change.'
              }
            />
            <AuditOutputField
              id="audit-precheck-action"
              label="Suggested Pre-check Contractor Action"
              value={audit?.response.proposed_precheck_action ?? null}
              placeholder={
                audit
                  ? 'No pre-check wording change suggested.'
                  : 'Suggested replacement pre-check instructions will appear here if the audit recommends a wording change.'
              }
            />
            <AuditOutputField
              id="audit-contractor-guidance"
              label="Suggested contractor guidance or training wording"
              value={audit?.response.proposed_contractor_guidance ?? null}
              placeholder={
                audit
                  ? 'No contractor guidance change suggested.'
                  : 'Suggested contractor instructions or training wording will appear here if the audit identifies a preparation gap.'
              }
            />
          </Box>
        </>
      )}
    </Box>
  );
}

function AuditOutputField({
  id,
  label,
  value,
  placeholder,
  rows = 6,
}: {
  id: string;
  label: string;
  value: string | null;
  placeholder: string;
  rows?: number;
}) {
  return (
    <FormControl mb={5}>
      <FormLabel htmlFor={id} fontWeight="semibold">
        {label}
      </FormLabel>
      <Textarea
        id={id}
        isReadOnly
        value={value ?? ''}
        placeholder={placeholder}
        rows={rows}
        fontSize="sm"
        bg="gray.50"
        _placeholder={{ color: 'gray.600' }}
      />
    </FormControl>
  );
}
