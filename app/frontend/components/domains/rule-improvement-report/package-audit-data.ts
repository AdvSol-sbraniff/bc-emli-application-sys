import { EvidenceRow } from './types';

export type AuditPackage = {
  invoiceId: string;
  latestCheck: EvidenceRow;
  results: string[];
  complaintCount: number;
  sentRoundCount: number;
  outcomes: string[];
};

export type AuditResponse = {
  advice: string;
  proposed_rule_prompt: string | null;
  proposed_precheck_action: string | null;
  proposed_contractor_guidance: string | null;
  completed_at: string;
  saved: false;
  transport: { deployment?: string; attachment_count?: number; diagnostic_id?: string };
  evidence: {
    version_count?: number;
    record_count?: number;
    attachment_count?: number;
    limitations?: string[];
  };
};

const RESULT_ORDER = ['fail', 'warn', 'info', 'pass'];

export function groupAuditPackages(rows: EvidenceRow[]): AuditPackage[] {
  const invoices = new Map<string, Map<string, EvidenceRow>>();
  for (const row of rows) {
    if (!invoices.has(row.invoice_id)) invoices.set(row.invoice_id, new Map());
    invoices.get(row.invoice_id)!.set(row.rulecheck_id, row);
  }

  return Array.from(invoices.entries()).map(([invoiceId, checks]) => {
    const ordered = Array.from(checks.values()).sort(
      (a, b) =>
        b.version_number - a.version_number ||
        b.rulecheck_created_at.localeCompare(a.rulecheck_created_at) ||
        b.rulecheck_id.localeCompare(a.rulecheck_id),
    );
    const latestCheck = ordered[0];
    const issues = new Map<string, EvidenceRow>();
    for (const row of ordered) {
      if (row.revision_issue_id && !issues.has(row.revision_issue_id)) issues.set(row.revision_issue_id, row);
    }
    return {
      invoiceId,
      latestCheck,
      results: Array.from(
        new Set(
          ordered
            .filter((row) => row.invoice_version_id === latestCheck.invoice_version_id)
            .map((row) => row.rule_result),
        ),
      ).sort((a, b) => RESULT_ORDER.indexOf(a) - RESULT_ORDER.indexOf(b)),
      complaintCount: ordered.filter((row) => Boolean(row.reason_complaint_code)).length,
      sentRoundCount: Array.from(issues.values()).reduce((total, row) => total + row.sent_round_count, 0),
      outcomes: Array.from(new Set(Array.from(issues.values()).map((row) => row.revision_issue_status || 'unknown'))),
    };
  });
}

// Existing evidence pages contain rule checks, not packages. Load every page before
// grouping so counts and sorting cover the whole current reporting period.
export async function loadAuditPackages(
  evidenceUrl: string,
  signal: AbortSignal,
  onProgress: (loaded: number, total: number) => void,
): Promise<AuditPackage[]> {
  const rows: EvidenceRow[] = [];
  let total = 0;
  let page = 1;
  do {
    const params = new URLSearchParams({ evidence_type: 'all', per: '200', page: String(page) });
    const response = await fetch(`${evidenceUrl}?${params}`, { credentials: 'include', signal });
    const data = await response.json();
    if (!response.ok) throw new Error(data.error || 'Unable to load invoice packages.');
    if (!Array.isArray(data.rows) || !Number.isInteger(data.meta?.total) || data.meta.total < 0) {
      throw new Error('The invoice package response was incomplete. Please try again.');
    }
    total = data.meta.total;
    rows.push(...data.rows);
    onProgress(rows.length, total);
    if (data.rows.length === 0 && rows.length < total) {
      throw new Error('Invoice evidence changed while loading. Please try again.');
    }
    page += 1;
  } while (rows.length < total);
  return groupAuditPackages(rows);
}
