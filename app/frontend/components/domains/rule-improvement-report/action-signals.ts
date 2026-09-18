import { REVISION_CLOSURE_LABELS } from '../../shared/claims/revision-closure-guidance';
import { COMPLAINT_LABELS, RuleBreakdowns, RuleRow, titleize } from './types';

export type EvidenceTarget = {
  tab: 'history' | 'complaints' | 'false_positives' | 'false_negatives' | 'rounds' | 'requests' | 'closures';
  complaintType?: string;
  minimumSentRounds?: string;
  closureOutcome?: string;
};

type ActionId = 'decision' | 'explanation' | 'correction' | 'precheck' | 'training' | 'policy' | 'observe';
type Strength = 'Direct complaint' | 'Candidate' | 'Weak / shared' | 'Context';

export type ActionSignal = {
  id: string;
  label: string;
  value: number | null;
  invoiceCount: number | null;
  totalInvoiceCount: number | null;
  detail: string;
  strength: Strength;
  interpretation: string;
  target?: EvidenceTarget;
};

export type ImprovementAction = {
  id: ActionId;
  title: string;
  purpose: string;
  summary: string;
  primarySignals: ActionSignal[];
  signals: ActionSignal[];
  investigation: string[];
  success: string;
};

// Exhaustive against COMPLAINT_LABELS: adding a complaint type requires deciding
// where it belongs. A complaint may support several investigations, not a diagnosis.
const COMPLAINT_ACTIONS: Record<
  keyof typeof COMPLAINT_LABELS,
  { direct: ActionId[]; supporting: ActionId[]; description: string; interpretation: string }
> = {
  unclear_or_confusing: {
    direct: ['explanation'],
    supporting: ['correction', 'precheck', 'training'],
    description: 'These complaints say the reason is difficult to understand.',
    interpretation: 'Read the comment to distinguish an unclear explanation from an unclear next action.',
  },
  too_vague: {
    direct: ['explanation'],
    supporting: ['decision', 'correction', 'precheck'],
    description: 'These complaints say the reason lacks specific details about the finding.',
    interpretation:
      'Check whether the reason omitted a specific finding, evidence reference or corrective instruction.',
  },
  missing_evidence_explanation: {
    direct: ['explanation'],
    supporting: ['decision', 'correction'],
    description: 'These complaints say the reason does not explain which evidence supports the finding.',
    interpretation: 'Inspect the documents to establish whether evidence was missing from the explanation or misread.',
  },
  incorrect_evidence_or_reasoning: {
    direct: ['decision'],
    supporting: ['explanation', 'policy'],
    description: 'These complaints report that the rule returned an incorrect Pass/Info/Warn/Fail result.',
    interpretation:
      'Read the complaint to establish which result the admin expected and why. Check the cited evidence against the original package. Make a three-way alignment check between realworld-checks, the applicable RER policy wording and the rule prompt (or code logic). Each serves a different need, so wording and detail will not match perfectly, but all three should apply the same intended requirement. Identify where any of the three makes compliance stricter, weaker or different; this drift is a major issue to resolve. Document the mismatch, confirm the intended requirement with the policy owner and bring all three into alignment through the appropriate changes to policy, the rule or realworld-checks. If the result was correct and only its explanation needs improvement, assess the explanation-quality option instead.',
  },
  likely_causes_unhelpful: {
    direct: ['explanation'],
    supporting: ['decision', 'correction'],
    description: 'These complaints say the suggested causes do not help explain the problem.',
    interpretation: 'Check whether speculative causes obscured the actual finding or the action needed to resolve it.',
  },
  required_action_unclear: {
    direct: ['correction'],
    supporting: ['explanation', 'precheck', 'training'],
    description: 'These complaints say the reason does not clearly explain what the contractor should do next.',
    interpretation:
      'Check whether the reason states exactly what the contractor must correct, upload, explain or attest, and why. It serves two audiences: the admin needs to understand and assess the finding, while the contractor needs clear instructions they can act on. The wording should be suitable for pre-populating the contractor-facing WFM issue, so the admin can review and use it with minimal rewriting. Check that the requested correction reflects the same requirement and acceptable evidence in realworld-checks, published RER policy wording and the rule prompt or code logic. If those disagree, resolve the underlying drift as well as the wording.',
  },
  irrelevant_or_duplicative: {
    direct: ['explanation'],
    supporting: ['decision', 'policy'],
    description: 'These complaints say the reason is irrelevant to the package or duplicates another finding.',
    interpretation: 'Distinguish irrelevant wording from a finding that should not have been raised for this package.',
  },
  too_verbose_or_repetitive: {
    direct: ['explanation'],
    supporting: ['correction', 'precheck'],
    description: 'These complaints say the reason is unnecessarily long or repeats the same information.',
    interpretation: 'Check whether repetition buried the finding, evidence or next action.',
  },
  other: {
    direct: [],
    supporting: ['decision', 'explanation', 'correction', 'precheck', 'training', 'policy'],
    description: 'These complaints were recorded as Other, with the concern explained in the accompanying comment.',
    interpretation:
      'Read the free-text complaint before assigning a cause. This category alone cannot identify the right improvement option.',
  },
};

export function buildImprovementActions(rule: RuleRow, breakdowns: RuleBreakdowns): ImprovementAction[] {
  const invoiceCounts: Record<string, number | undefined> = {
    ...rule.invoice_coverage?.signal_invoice_counts,
    precheck_unresolved: rule.precheck_metrics?.unresolved_package_count,
    precheck_corrected: rule.precheck_metrics?.cleared_package_count,
    precheck_unknown_outcome: rule.precheck_metrics?.unknown_outcome_package_count,
    precheck_unknown_history: rule.precheck_metrics?.unknown_history_package_count,
  };
  const count = (group: 'complaint_types' | 'closure_types' | 'admin_requests' | 'contractor_responses', key: string) =>
    breakdowns[group].find((row) => row.value === key)?.count ?? 0;
  const signal = (
    id: string,
    label: string,
    value: number | undefined,
    detail: string,
    interpretation: string,
    target?: EvidenceTarget,
    strength: Strength = 'Weak / shared',
  ): ActionSignal => ({
    id,
    label,
    value: value ?? null,
    invoiceCount: invoiceCounts[id] ?? null,
    totalInvoiceCount: rule.invoice_coverage?.total_invoice_count ?? null,
    detail,
    interpretation,
    target,
    strength,
  });

  const complaints = (action: ActionId): ActionSignal[] => {
    const known = Object.entries(COMPLAINT_ACTIONS)
      .filter(([, mapping]) => mapping.direct.includes(action) || mapping.supporting.includes(action))
      .map(([code, mapping]) =>
        signal(
          `complaint:${code}`,
          `Complaint: ${COMPLAINT_LABELS[code]}`,
          count('complaint_types', code),
          mapping.description,
          mapping.interpretation,
          { tab: 'complaints', complaintType: code },
          mapping.direct.includes(action) ? 'Direct complaint' : 'Weak / shared',
        ),
      );
    // Preserve evidence if a newer server returns a category this UI does not know.
    const unclassified = breakdowns.complaint_types
      .filter((row) => !Object.prototype.hasOwnProperty.call(COMPLAINT_ACTIONS, row.value))
      .map((row) =>
        signal(
          `complaint:${row.value}`,
          `Complaint: ${titleize(row.value)}`,
          row.count,
          'These complaints use a category not yet described by this screen.',
          'Read these complaints individually; this category has not yet been mapped to a specific improvement option.',
          { tab: 'complaints', complaintType: row.value },
        ),
      );
    return [...known, ...unclassified];
  };

  const outcome = (key: string, description: string, interpretation: string, strength: Strength = 'Weak / shared') =>
    signal(
      `closure:${key}`,
      `Closure: ${REVISION_CLOSURE_LABELS[key]}`,
      count('closure_types', key),
      description,
      interpretation,
      { tab: 'closures', closureOutcome: key },
      strength,
    );
  const noAction = outcome(
    'closed_no_contractor_action_required',
    'These workflow issues were closed internally before being sent to the contractor because no response or correction was required.',
    'For Warn/Fail results, this is redundant with the False-positives row in Option 1: the same records are already counted there and are not additional problems. The counts are identical unless this closure also includes Pass/Info issues, which the False-positives count excludes. Read the admin’s closure explanation, the original package and any complaint to establish why the issue was resolved without sending it. This outcome does not record acceptance of a contractor’s explanation after a sent round.',
  );
  const corrected = outcome(
    'closed_via_corrected_documentation',
    'These workflow issues were resolved when corrected or additional documentation was accepted.',
    'This is a normal, successful outcome when the rule identifies a genuine problem and the contractor corrects it. It belongs here because even successful corrections can reveal preparation mistakes that clearer website guidance, examples or contractor training could prevent. Review what needed correcting and how to teach that requirement upfront. The aim is for more invoice packages to pass review the first time, without document changes or any contractor follow-up rounds.',
  );
  const attestation = outcome(
    'closed_via_attestation',
    'These workflow issues were resolved by accepting an explanation or attestation that established the requirement was met.',
    'Read the response, the back-and-forth and the closure comment to identify what was misunderstood or missing from the original package. Could clearer upfront guidance have helped the contractor provide that context or assurance initially? For example, clarification may identify an eligible equipment model obscured by poor invoice formatting. Equipment below the required efficiency would instead need an authorised exception to be accepted, if one is permitted. Check that realworld-checks, published RER policy wording and the rule prompt or code logic agree on what evidence establishes compliance; a routinely accepted explanation may expose drift between them. The combined closure count does not distinguish explanations from attestations; inspect the response types and comments.',
  );
  const exception = outcome(
    'closed_via_exception',
    'These workflow issues were accepted through an authorised exception even though the requirement was not met.',
    'Read the package, contractor explanation and admin’s closure decision to establish which requirement was unmet and why an exception was authorised. This does not by itself mean the policy is wrong. Unclear upfront guidance may have led the contractor to choose ineligible equipment or submit an ineligible claim; for example, equipment below the required efficiency. Check what guidance was available before selection, installation and submission, and whether clearer eligibility instructions could have prevented the problem. Repeated exceptions may justify better contractor guidance, an existing exception process, or policy clarification. Make a three-way alignment check between realworld-checks (the working policies and interpretations admins actually apply), published RER policy wording and the rule prompt or code logic. Different wording is expected, but eligibility requirements, acceptable evidence and exception boundaries should agree. Policy work often means resolving drift between these three, rather than changing the underlying requirement. Document the mismatch and ask the policy owner which changes are needed; do not automatically weaken the prompt or turn individual exceptions into general eligibility.',
    'Candidate',
  );
  const withdrawn = outcome(
    'closed_as_withdrawn',
    'These workflow issues were withdrawn after being sent to the contractor.',
    'Read the admin’s withdrawal reason and the full request-and-response conversation. Establish whether the request was unnecessary, superseded or unclear, and whether clearer corrective instructions could have prevented the exchange. If the original finding was incorrect, investigate decision accuracy as well.',
  );

  const responseDefinitions = [
    [
      'corrected_invoice_uploaded',
      'Corrected invoice uploaded',
      'These submitted responses state that the contractor uploaded a corrected invoice.',
      'This is a normal step on the happy path: the contractor corrects the invoice in response to a genuine finding. If the correction is accepted, the same issue also appears under Closure: Corrected documentation accepted. Both signals are useful because the response records what was supplied and the closure confirms acceptance; do not add their counts as separate problems. Compare the original and corrected invoice, confirm the closure, and identify whether clearer upfront guidance or examples could have prevented the mistake. Successful correction is a good outcome; over time, the aim is for every invoice package to arrive complete and correct, with no corrections or follow-up rounds needed.',
    ],
    [
      'supporting_document_uploaded',
      'Supporting document uploaded',
      'These submitted responses state that the contractor uploaded a supporting document.',
      'This is a normal step on the happy path: the contractor supplies a document needed to resolve the finding. If the document is accepted and resolves the issue, the same issue also appears under Closure: Corrected documentation accepted. Both signals are useful because the response records what was supplied and the closure confirms acceptance; do not add their counts as separate problems. Check which document was supplied, confirm the closure, and consider whether clearer upfront guidance or a checklist could have prompted its inclusion in the original package. Successful resolution is a good outcome; over time, the aim is for every invoice package to arrive complete and correct, with all required documents included and no follow-up rounds needed.',
    ],
    [
      'attestation_provided',
      'Attestation provided',
      'These submitted responses state that the contractor provided an attestation.',
      'Think of this as the more formal counterpart of Response: Explanation provided: the contractor gives a formal statement or assurance about the work or evidence. When that assurance establishes compliance and is accepted, this is a normal resolution on the happy path. Read what they confirmed and why it was needed. Contractors select response types, while trained admins record the closure after assessing the evidence, so the closure is generally more useful for distinguishing established compliance from an authorised exception. Keep this response as a signal of where clearer upfront guidance could explain when an assurance is needed and what it should cover. Over time, the aim is for every invoice package to arrive complete and correct, with the necessary assurance already included and no follow-up rounds needed.',
    ],
    [
      'explanation_provided',
      'Explanation provided',
      'These submitted responses state that the contractor provided an explanation.',
      "Resolving an issue by clarifying compliance is a normal outcome on the happy path. An explanation may clarify poor invoice formatting that obscures an eligible equipment model, or it may describe a genuine failure such as installed equipment below the required efficiency, which would need an authorised exception to be accepted, if one is permitted. Contractors select response types; the closure records the trained admin's assessment. Use Explanation or attestation accepted versus Exception granted to distinguish these outcomes. Read the explanation, conversation and closure together. We retain this response as a signal of misunderstandings or missing information that better upfront guidance could prevent. Over time, the aim is for every invoice package to arrive complete, correct and clear enough to assess without follow-up rounds. Investigate decision accuracy if the original evidence was already sufficient and the rule judged it incorrectly.",
    ],
    [
      'unable_to_resolve',
      'Unable to resolve',
      'These submitted responses state that the contractor could not complete the requested action.',
      'Read the initial request, the contractor’s free-form response and the full back-and-forth through to closure. A successful closure may follow several clarifications, so it does not establish that the initial instructions were clear. Identify what finally helped the contractor resolve the issue and whether putting that explanation into the original reason and pre-populated WFM issue could have avoided another round.',
    ],
  ];
  const responses = responseDefinitions.map(([key, label, description, interpretation]) =>
    signal(
      `contractor_responses:${key}`,
      `Response: ${label}`,
      count('contractor_responses', key),
      description,
      interpretation,
      { tab: 'requests' },
    ),
  );
  const policyResponses = responses.slice(2);

  const roundsTarget: EvidenceTarget = { tab: 'rounds' };
  const rounds = [
    signal(
      'follow_up',
      'Invoice versions with a linked workflow issue',
      rule.follow_up_invoice_count,
      'These invoice versions have a workflow issue linked to this rule, including issues not yet sent to the contractor.',
      'Inspect the issue status before treating it as contractor effort.',
      roundsTarget,
    ),
    signal(
      'sent_issues',
      'Issues with at least one sent round',
      rule.sent_issue_count,
      'These workflow issues were included in at least one round sent to the contractor.',
      'Review why follow-up was necessary and whether the request helped resolve the issue.',
      roundsTarget,
    ),
    signal(
      'multi_round',
      'Issues with more than one sent round',
      rule.multi_round_issue_count,
      'These workflow issues were sent to the contractor again after the initial request.',
      'Several rounds can reflect unclear instructions, a disputed decision or a policy exception. Review the requests, responses and recorded conversation to see what changed between rounds, even when the issue was eventually resolved. Check whether a clearer sentence in the original reason and pre-populated WFM issue could have avoided an extra round.',
      { tab: 'rounds', minimumSentRounds: '2' },
    ),
    signal(
      'total_rounds',
      'Total sent rounds',
      rule.total_round_count,
      'This workload measure counts sent rounds separately for each linked issue, so a package can contribute several.',
      'Review the exchanges to understand what drove the follow-up effort.',
      roundsTarget,
    ),
    signal(
      'repeat_rounds',
      'Sent rounds beyond the first for each issue',
      rule.repeat_round_count,
      'This counts the additional sent rounds after the initial round for each linked issue.',
      'Inspect the sequence to see what remained unresolved after the first request.',
      { tab: 'rounds', minimumSentRounds: '2' },
    ),
    signal(
      'average_rounds',
      'Average sent rounds per sent issue',
      rule.sent_issue_count > 0 ? rule.average_rounds : undefined,
      'This is the average number of sent rounds per linked issue, excluding issues never sent to the contractor.',
      'Compare with the median and maximum: a few difficult cases may account for much of the effort.',
      roundsTarget,
    ),
    signal(
      'median_rounds',
      'Median sent rounds per sent issue',
      rule.sent_issue_count > 0 ? rule.median_rounds : undefined,
      'This is the middle sent-round count when sent issues are ordered from fewest to most rounds.',
      'Review typical cases to understand whether the instructions helped resolve the issue.',
      roundsTarget,
    ),
    signal(
      'maximum_rounds',
      'Maximum sent rounds for an issue',
      rule.sent_issue_count > 0 ? rule.maximum_rounds : undefined,
      'This is the highest number of sent rounds recorded for any linked issue.',
      'Start with an unusually long case, then inspect contrasting cases before generalising.',
      roundsTarget,
    ),
    signal(
      'workflow_issues',
      'All linked workflow issues',
      rule.workflow_issue_count,
      'This counts distinct workflow issues linked to this rule, including issues never sent to the contractor.',
      'Check whether an issue was sent, remains open or has a recorded outcome. Creating an issue alone does not establish a problem with the instructions.',
      roundsTarget,
    ),
  ];
  const candidates = [
    signal(
      'false_positive',
      'False-positives',
      rule.candidate_false_positive_count,
      'The rule returned Warn/Fail, but the workflow issue was closed internally before being sent to the contractor, with no response or correction required.',
      'Review why the issue was closed without contractor action and determine whether the rule should have returned Pass/Info. Check whether the prompt or code logic is too strict, or whether the rule’s underlying concept is out of alignment with realworld-checks and the RER policy wording. Resolve any drift with the policy owner so all three apply the same intended requirement before deciding how to change the rule. Read the recorded complaint category and especially the free-form text to understand the admin’s concern. If an admin identified an incorrect result without recording a complaint and explanation, address the training gap so these are captured at the same time.',
      { tab: 'false_positives' },
      'Candidate',
    ),
    signal(
      'false_negative',
      'False-negatives',
      rule.candidate_false_negative_count,
      'The rule returned Pass/Info, but a workflow issue was still opened against that result.',
      'Review why the issue was opened, its outcome and determine whether the rule should have returned Warn/Fail. Check whether the prompt or code logic is too lenient, or whether the rule’s underlying concept is out of alignment with realworld-checks and the RER policy wording. Resolve any drift with the policy owner so all three apply the same intended requirement before deciding how to change the rule. Read the recorded complaint category and especially the free-form text to understand the admin’s concern. If an admin identified an incorrect result without recording a complaint and explanation, address the training gap so these are captured at the same time.',
      { tab: 'false_negatives' },
      'Candidate',
    ),
  ];
  const precheck = rule.precheck_metrics;
  const precheckUnresolved = signal(
    'precheck_unresolved',
    'Submitted despite still having an unresolved contractor-visible pre-check finding',
    precheck?.unresolved_package_count,
    'These packages still had a contractor-visible Warn/Fail for this rule when first submitted.',
    'Inspect why the finding remained: unclear instructions, training, an incorrect finding or policy may explain it. Compare what the pre-check asks for with realworld-checks, published RER policy wording and the rule prompt or code logic. Conflicting expectations need alignment, not just clearer wording. This does not prove the contractor read it or did nothing.',
  );
  const precheckCorrected = signal(
    'precheck_corrected',
    'Pre-check findings cleared before first submission',
    precheck?.cleared_package_count,
    'For these packages, all observed visible Warn/Fail findings became Pass/Info for the same rule and upgrade by first submission, with no intervening rule revision.',
    'The pre-check message provides generic, configured instructions rather than the invoice-specific AI reason. If the contractor resolved the finding using that message, the correction may have been straightforward enough for website guidance, training or a submission checklist to explain upfront. Review what changed in the package and identify the instruction or example that could have helped the contractor prepare it correctly the first time.',
  );
  const precheckCoverage = [
    signal(
      'precheck_unknown_outcome',
      'Packages with a visible pre-check finding but an unknown outcome',
      precheck?.unknown_outcome_package_count,
      'These packages had a visible pre-check finding, but its outcome at first submission could not be established.',
      'A matching submitted check may be missing, the finding may have become hidden, or the rule may have changed. These packages remain in the denominator and are not counted as cleared.',
      undefined,
      'Context',
    ),
    signal(
      'precheck_unknown_history',
      'Packages without usable submission or visibility history',
      precheck?.unknown_history_package_count,
      'These packages are excluded from pre-check outcome counts because submission or visibility history is insufficient.',
      'Check which part of the history is missing: the first submission, its invoice version or the visibility of the finding. Missing evidence is not a successful correction.',
      undefined,
      'Context',
    ),
  ];
  const results = (['pass', 'info', 'warn', 'fail'] as const).map((result) =>
    signal(
      `result:${result}`,
      `${titleize(result)} results`,
      rule[`${result}_count`],
      `The rule returned ${titleize(result)} in these evaluations.`,
      'Result volume provides context, not an accuracy score. A frequent warning can be a correct and useful finding.',
      { tab: 'history' },
      'Context',
    ),
  );
  const number = (value: number) => value.toLocaleString();
  const directComplaintCodes = (action: ActionId) =>
    Object.entries(COMPLAINT_ACTIONS)
      .filter(([, mapping]) => mapping.direct.includes(action))
      .map(([code]) => code);
  const directComplaintSignals = (action: ActionId) =>
    complaints(action).filter((row) => row.strength === 'Direct complaint');
  // Other is included for triage, not classified as an explanation problem.
  const explanationComplaintCodes = [...directComplaintCodes('explanation'), 'other'];
  const explanationComplaintCount = explanationComplaintCodes.reduce(
    (sum, code) => sum + count('complaint_types', code),
    0,
  );
  // Complaint types are exclusive on each check; this total counts complaints,
  // not distinct invoice packages.
  const explanationComplaints = signal(
    'explanation_complaints',
    'Complaint: All outcomes related to explanation quality',
    explanationComplaintCount,
    `This total sums the following complaint types: ${explanationComplaintCodes
      .map((code) => COMPLAINT_LABELS[code])
      .join('; ')}.`,
    'Read the complaint category and especially the free-form text to understand the concern. For Other, use that text to decide whether explanation quality, decision accuracy, corrective instructions or another improvement option is appropriate. For explanation complaints, check the package evidence and confirm that the decision was correct and the admin was complaining about how it was explained. Look for explanations that are too brief, omit useful detail or use wording that needs substantial rewriting in the pre-populated workflow issue. Aim for clear, contractor-ready wording that admins can review and reuse with minimal editing. The explanation should express the same requirement as realworld-checks, published RER policy wording and the rule prompt or code logic. If these disagree about what compliance means, resolve that drift rather than treating it as a writing problem. If the complaint reveals an incorrect decision, investigate decision accuracy as well.',
    { tab: 'complaints' },
    'Direct complaint',
  );
  const isCode = rule.source_engine === 'code';

  return [
    {
      id: 'decision',
      title: isCode ? 'Improve rule logic for decision accuracy' : 'Improve rule prompt for decision accuracy',
      purpose:
        'Make the rule reach the correct result from the evidence, with realworld-checks, published RER policy wording and the rule prompt or code logic applying the same intended requirement.',
      summary: `${number(rule.candidate_false_positive_count)} false-positives · ${number(rule.candidate_false_negative_count)} false-negatives`,
      primarySignals: [candidates[0], noAction, candidates[1], ...directComplaintSignals('decision')],
      signals: [
        ...candidates,
        ...complaints('decision'),
        noAction,
        exception,
        attestation,
        withdrawn,
        responses[2],
        responses[4],
        rounds[2],
        precheckUnresolved,
        ...results,
      ],
      investigation: [
        'Open the actual invoice and supporting documents for candidates. Establish the expected result and the evidence available at that processing time.',
        'Compare the reason with the evidence: distinguish an incorrect decision from correct reasoning expressed badly, an extraction problem or an approved exception.',
        'Compare the actual admin interpretation, the applicable published RER policy wording and the rule prompt or code logic for the same case. Document stricter, weaker or conflicting requirements and confirm the intended interpretation with the policy owner before changing any of the three.',
        isCode
          ? 'If the logic is wrong, involve a developer. Editing the code-rule description does not change the executable rule.'
          : 'Draft a prompt change only after identifying a repeatable error. Try representative packages in quality, inspect versions, then run a broader rule comparison suite.',
      ],
      success:
        'Audited decisions match the package evidence and the agreed requirement across realworld-checks, published RER policy and the rule; regression checks retain previously correct results. Fewer candidates alone does not prove improved accuracy.',
    },
    {
      id: 'explanation',
      title: isCode
        ? 'Improve the explanation in the rule’s reason'
        : 'Improve rule prompt for a clearer explanation in the reason',
      purpose:
        'Explain what was found, why it matters and which evidence supports it, using wording admins can reuse in the pre-populated workflow issue with minimal editing.',
      summary: `${number(explanationComplaintCount)} explanation quality and other complaints`,
      primarySignals: [explanationComplaints],
      signals: [
        ...complaints('explanation'),
        ...rounds.filter((row) => row.id !== 'multi_round'),
        responses[3],
        responses[4],
        noAction,
        withdrawn,
      ],
      investigation: [
        'For complaints recorded as Other, read the free-form text and decide whether explanation quality, decision accuracy, corrective instructions or another improvement option is the right fit.',
        'Read the complaint alongside the complete reason and package evidence. First confirm that the decision was correct and the complaint concerns the explanation. Investigate decision accuracy as well if the result itself was wrong.',
        'Read the free-form complaint and compare the reason with the wording needed for the workflow issue. Look for explanations that are too brief, omit useful evidence or need substantial rewriting before they are suitable for the contractor.',
        'Keep this distinct from corrective instructions: a reason may explain a problem accurately while still failing to tell the contractor what to do next.',
      ],
      success:
        'Reasons explain the correct decision with enough specific, supported detail for the contractor to understand it. Admins can review and reuse the pre-populated wording with minimal editing. Track the relevant complaint categories after the change.',
    },
    {
      id: 'correction',
      title: isCode
        ? 'Improve corrective instructions in the rule’s reason'
        : 'Improve rule prompt for clearer corrective instructions in the reason',
      purpose:
        'Give the admin a clear basis for reviewing the finding and the contractor an exact next action, in wording suitable for pre-populating the contractor-facing WFM issue.',
      summary: `${number(count('complaint_types', 'required_action_unclear'))} complaints that the required action is unclear`,
      primarySignals: [...directComplaintSignals('correction'), rounds[2], responses[4], withdrawn],
      signals: [...complaints('correction'), ...rounds, ...responses, corrected, attestation, noAction, withdrawn],
      investigation: [
        'Check whether the original reason specifies what must be corrected, which document to supply, or what explanation or attestation is acceptable.',
        'Review the reason from both audiences’ perspectives: can the admin assess the finding, and can the contractor act on the pre-populated WFM issue? Follow the request and response sequence to identify wording that would reduce the need for rewriting or further explanation.',
        'Do not infer a mismatch by pairing aggregate request and response totals. Open the same package’s rounds to see whether the action was understood and resolved the problem.',
      ],
      success:
        'Admins can review and reuse the reason in the contractor-facing WFM issue with minimal rewriting, and contractors can identify the required next action. Confirm this against packages, then watch required-action complaints and repeat rounds without sacrificing correct decisions.',
    },
    {
      id: 'precheck',
      title: 'Improve pre-check instructions',
      purpose: 'Make the Pre-check Contractor Action instructions easier to understand and act on before submission.',
      summary: precheck
        ? `${number(precheck.unresolved_package_count)} submitted unresolved`
        : 'Pre-check metrics unavailable',
      primarySignals: [precheckUnresolved],
      signals: [
        precheckUnresolved,
        ...precheckCoverage,
        ...complaints('precheck'),
        ...rounds,
        responses[4],
        corrected,
        noAction,
        exception,
      ],
      investigation: [
        'Inspect the Pre-check Contractor Action wording and which findings were visible before submission. Current settings do not prove what was displayed historically.',
        'Reason complaints concern the generated reason, not the pre-check instructions. They are only indirect clues here; inspect the two texts separately.',
        'For a finding still present at submission, distinguish unclear instructions from attempted but unsuccessful correction, missing documents, disagreement or an exception. Successful pre-check corrections may instead support better training.',
      ],
      success:
        'Contractors can identify and complete the required pre-check action. Inspect packages alongside the unresolved findings at first submission, accounting for unknown outcomes and changes in the package mix.',
    },
    {
      id: 'training',
      title: 'Improve contractor submission guidance and training',
      purpose: 'Help contractors prepare the right invoice and supporting evidence before they reach pre-check.',
      summary: `${number(count('closure_types', 'closed_via_corrected_documentation'))} corrected-documentation closures`,
      primarySignals: [precheckCorrected, corrected, ...responses.slice(0, 4), attestation],
      signals: [
        precheckCorrected,
        precheckUnresolved,
        ...precheckCoverage,
        corrected,
        attestation,
        withdrawn,
        ...responses,
        ...rounds,
        ...complaints('training'),
      ],
      investigation: [
        'Review successful corrections for recurring preparation mistakes that website guidance, checklists or examples could prevent. Establish what contractors need to know upfront to submit a complete, correct package without document changes or follow-up rounds.',
        'When a contractor can resolve a finding using the generic pre-check message, investigate whether the correction was straightforward enough to explain earlier through website guidance, training, a checklist or a worked example. Confirm what changed in the package and what guidance could have prevented the initial mistake.',
        'For an Exception granted closure, check whether clearer eligibility guidance before equipment selection or installation could have prevented an ineligible submission. An exception does not automatically mean the policy needs changing. Make sure contractor guidance teaches the agreed requirement across realworld-checks, published RER policy and the rule prompt or code logic, rather than perpetuating a mismatch.',
        'If the finding was wrong, the instructions were unclear, or policy prevented resolution, investigate those improvement options before assuming a training gap.',
      ],
      success:
        'An increasing proportion of invoice packages pass review the first time, without document changes or contractor follow-up rounds, while the rule continues detecting genuine problems.',
    },
    {
      id: 'policy',
      title: 'Clarify policy for recurring approved exceptions',
      purpose:
        'Establish whether recurring exceptions call for clearer contractor guidance or policy clarification, and work with the policy owner to align realworld-checks, published RER policy wording and rule prompts or code logic.',
      summary: `${number(count('closure_types', 'closed_via_exception'))} approved-exception closures`,
      primarySignals: [exception],
      signals: [
        exception,
        attestation,
        noAction,
        withdrawn,
        ...policyResponses,
        ...rounds,
        ...complaints('policy'),
        precheckUnresolved,
      ],
      investigation: [
        'Read the exception dispositions and package evidence. Establish whether several exceptions share the same circumstances or are unrelated individual decisions.',
        'Check whether missing or unclear contractor guidance led to ineligible equipment, work or submissions. Identify what contractors could have been told before choosing equipment or doing the work. If the requirement is clear and appropriate, improve that guidance instead of assuming the policy is wrong.',
        'Set out the three interpretations side by side: the realworld-checks admins actually apply, the published RER policy wording and the rule prompt or code logic. Identify any mismatch in eligibility, evidence or exception handling. Ask the policy owner to confirm the intended requirement and decide which of the three needs correcting or clarifying.',
        'Identify the policy question: when is the exception allowed, what evidence is acceptable, and who can approve it? Attestations and explanations may be normal resolutions rather than exceptions.',
        'The appropriate change may be to admin practice, published wording, the rule or more than one of these. If the agreed policy is clear but the rule applies it incorrectly, improve decision accuracy. Do not turn individual exceptions into a blanket rule without a policy decision.',
      ],
      success:
        'The policy owner confirms clear criteria and examples that align realworld-checks, published RER policy and rule prompts or code logic. Contractor guidance communicates the same requirement, comparable packages are treated consistently and resulting rule changes pass regression checks. Fewer exceptions alone does not demonstrate better policy.',
    },
    {
      id: 'observe',
      title: 'Make no change for now',
      purpose:
        'Choose this when assessing the other improvement options has revealed no worthwhile change. Consider the signal percentages, the seriousness of individual cases and what the package investigations established. Record why no change is justified and when to reassess.',
      summary: 'No worthwhile change identified from assessing the other improvement options',
      primarySignals: [],
      signals: [],
      investigation: [
        rule.check_count === 0
          ? 'There are no checks in the current period. Treat this as insufficient evidence, not confirmation that the rule works.'
          : 'Consider the sample size, range of packages and age of the current rule. There is no automatic count threshold that makes the rule safe to leave unchanged.',
        'If evidence is insufficient or outcomes are still open, identify the missing examples or outcomes and when to revisit them.',
        'If representative package inspection supports the rule and its guidance, retain it and monitor. A high pass rate or zero complaints alone is not enough.',
      ],
      success:
        'Record why no change is appropriate, what remains uncertain and what evidence would trigger another investigation.',
    },
  ];
}
