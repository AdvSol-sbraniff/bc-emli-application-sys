export type RuleMetrics = {
  check_count: number;
  invoice_count: number;
  complaint_count: number;
  complaint_rate?: number | null;
  workflow_issue_count: number;
  follow_up_invoice_count: number;
  open_issue_count: number;
  closed_issue_count: number;
  no_action_count: number;
  no_action_rate?: number | null;
  corrected_documentation_count: number;
  corrected_documentation_rate?: number | null;
  sent_issue_count: number;
  total_round_count: number;
  repeat_round_count: number;
  average_rounds: number;
  median_rounds: number;
  maximum_rounds: number;
  multi_round_issue_count: number;
  candidate_false_positive_count: number;
  candidate_false_negative_count: number;
};

export type UpgradeType = { id: string; key: string; description: string };

export type RuleRow = RuleMetrics & {
  rule_id: string;
  record_type: 'genai_rule' | 'code_rule';
  source_engine: 'genai' | 'code';
  rule_key: string;
  contractor_display_name: string;
  enabled: boolean;
  created_at: string;
  updated_at: string;
  definition_text: string;
  source_quote?: string | null;
  contractor_action?: string | null;
  contractor_visibility: string;
  contractor_blocking_policy: string;
  admin_workflow_policy: string;
  upgrade_types: UpgradeType[];
  change_count: number;
  last_changed_at: string;
  current_effective_at: string;
  attention_signal: string;
  attention_label: string;
  attention_score: number;
  meets_minimum_sample: boolean;
};

export type EvidenceRow = {
  rulecheck_id: string;
  rulecheck_created_at: string;
  invoice_id: string;
  invoice_version_id: string;
  version_number: number;
  invoice_reference_number?: number | string | null;
  invoice_status: string;
  contractor_business_name: string;
  upgrade_type_key: string;
  rule_result: string;
  reason?: string | null;
  reason_complaint_code?: string | null;
  reason_complaint_text?: string | null;
  revision_issue_id?: string | null;
  revision_issue_status?: string | null;
  disposition_comment?: string | null;
  sent_round_count: number;
};

export const COMPLAINT_LABELS: Record<string, string> = {
  unclear_or_confusing: 'Unclear or confusing',
  too_vague: 'Too vague',
  missing_evidence_explanation: 'Missing evidence explanation',
  incorrect_evidence_or_reasoning: 'Incorrect evidence or reasoning',
  likely_causes_unhelpful: 'Likely causes are unhelpful',
  required_action_unclear: 'Required action is unclear',
  irrelevant_or_duplicative: 'Irrelevant or duplicative',
  too_verbose_or_repetitive: 'Too verbose or repetitive',
  other: 'Other',
};

export const SIGNAL_LABELS: Record<string, string> = {
  rule_review: 'Review rule applicability',
  contractor_guidance: 'Improve contractor guidance',
  explanation_tuning: 'Improve reason quality',
  candidate_missed: 'Review possible missed issues',
  awaiting_sample: 'Awaiting post-change sample',
  none: 'No strong signal',
};

export function percent(value?: number | null) {
  return value === null || value === undefined ? '—' : `${Math.round(value * 100)}%`;
}

export function shortDate(value?: string | null) {
  if (!value) return '—';
  return new Date(value).toLocaleDateString();
}

export function titleize(value?: string | null) {
  if (!value) return '—';
  return value
    .split('_')
    .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
    .join(' ');
}
