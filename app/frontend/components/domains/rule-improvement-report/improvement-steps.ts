export type ImprovementStep = {
  number: number;
  label: string;
  workspace?: 'options' | 'evidence' | 'packages';
  purpose: string;
  instructions: string[];
  examples: Array<{ title: string; description: string }>;
  screens: string;
  links?: Array<{ label: string; to: string }>;
  outcome: string;
  note?: string;
};

export function improvementSteps(isCodeRule: boolean): ImprovementStep[] {
  return [
    {
      number: 1,
      label: 'Prepare and select a rule',
      purpose:
        'Start with a useful quality environment and a rule worth investigating. This step establishes the starting point for the work; selecting this arrow does not refresh a database or change a rule.',
      instructions: [
        'Arrange a quality refresh from production through the established process when needed. Confirm that it is appropriate before replacing quality data, because a refresh can overwrite experiments and test results already in progress. Keep a record of when the copy was taken.',
        'Open the Rule Improvement Report and compare rules using the available counts and percentages. Consider both how often a problem occurs and its practical impact: a small number of serious incorrect decisions can deserve attention alongside a large volume of avoidable follow-up.',
        'Select a rule and note its current definition or code implementation, effective date, invoice volume and any known recent changes. The detailed evidence is scoped to the current rule period, so a recent edit can leave only a small sample.',
        'Record why the rule was selected and what you hope to understand. Treat this as a starting question. The improvement option is chosen in Step 5 after reviewing aggregate evidence and inspecting 3–5 packages.',
        'Identify who can explain the realworld-checks admins apply and who owns the published RER policy. You will need to compare both with the rule prompt or code logic when the evidence suggests a mismatch.',
      ],
      examples: [
        {
          title: 'Example: a correct rule with avoidable follow-up',
          description:
            'A rule has few incorrect-decision complaints but many packages need an additional document before being accepted. Select it to investigate whether contractors could supply that document initially. The question is whether better preparation guidance could prevent the exchange; it is not yet a reason to weaken the rule.',
        },
        {
          title: 'Example: a small but important decision problem',
          description:
            'Another rule has only a few complaints, but they describe eligible invoices being rejected. That may warrant investigation even if its overall complaint percentage is low. Note the concern and check the relevant policy period rather than choosing solely by the largest count.',
        },
      ],
      screens: 'Rule Improvement Report and the established quality-environment refresh process.',
      links: [{ label: 'Open Rule Improvement Report', to: '/reports-rule-improvement' }],
      outcome: 'A selected rule, an understood evidence period and a clear question to investigate in quality.',
    },
    {
      number: 2,
      label: 'Assess improvement options',
      workspace: 'options',
      purpose:
        'Work through the seven improvement options and their signals to identify plausible causes. Build an investigation shortlist before choosing an improvement.',
      instructions: [
        'Open each option accordion. Read the signal value, percentage of invoices and What to investigate. Consider the size and seriousness of the pattern, not just the largest count.',
        'Mark each option in your work notes as plausible, lower priority or needing more evidence. Record the signal behind your assessment and the question a package inspection should answer.',
        'Several options can share the same signal. A contractor response or closure is a clue to investigate, not a diagnosis. Include Make no change for now when considering possible conclusions.',
        'Consider whether realworld-checks, published RER policy wording and the rule prompt or code logic apply the same requirement. Different wording is expected; conflicting eligibility or evidence requirements need investigation.',
        'Use Step 3 to understand aggregate patterns and Step 4 to inspect 3–5 representative packages. Choose and justify the improvement in Step 5 after those investigations.',
      ],
      examples: [
        {
          title: 'Example: two plausible explanations',
          description:
            'Repeated rounds and Required action is unclear complaints could point to weak corrective instructions. They could also accompany a disagreement about what evidence is acceptable. Keep both explanations open and identify what the package conversations should establish.',
        },
      ],
      screens: 'The improvement option accordions below, followed by the Step 3 and Step 4 working areas.',
      outcome:
        'A shortlist of plausible improvements and explicit questions to investigate, rather than a final choice.',
    },
    {
      number: 3,
      label: 'Explore aggregate evidence',
      workspace: 'evidence',
      purpose:
        'Use the charts and breakdowns to understand the patterns behind the option signals and decide which kinds of packages need inspection.',
      instructions: [
        'Use the relevant evidence tabs to unpack a grouped signal. For example, separate the complaint categories within explanation quality and compare contractor responses with final closure outcomes.',
        'Check the measurement period, sample size and units. A check, invoice version, contractor response and workflow issue are not interchangeable. Counts can overlap and should not be added into a total problem score.',
        'Look for competing explanations and successful outcomes as well as problems. Corrected documentation accepted can show the rule working correctly while revealing a preparation mistake that better guidance could prevent.',
        'Write down the patterns to investigate in Step 4. Include different problem patterns and at least one contrasting or successful case when selecting 3–5 packages.',
      ],
      examples: [
        {
          title: 'Example: a frequent response is not the final outcome',
          description:
            'Explanation provided might be followed by acceptance of an already compliant invoice or by an authorised exception for an unmet requirement. Compare the aggregate distributions, then inspect the same package’s response and closure in Step 4 before deciding which interpretation applies.',
        },
      ],
      screens: 'The evidence tabs below. Use Step 4 for the package inspection and audit workspace.',
      outcome: 'A clearer description of the recurring patterns and the package examples needed to explain them.',
    },
    {
      number: 4,
      label: 'Inspect and audit packages',
      workspace: 'packages',
      purpose:
        'Inspect 3–5 representative invoice packages to establish what actually happened. Use package evidence to test the suspected causes before selecting an improvement.',
      instructions: [
        'Choose packages covering the patterns identified in Steps 2 and 3, including a contrasting or successful case. Work through them one at a time and record their invoice and version references in your work notes.',
        'Open the original invoice and supporting documents. Compare the rule result and full reason with the evidence available at that processing time; a later correction cannot explain what the rule should have known earlier.',
        'Read complaint comments, workflow requests, contractor responses, conversations and closure decisions across versions and rounds. Establish what resolved the issue and whether clearer instructions or better preparation could have avoided the exchange.',
        'Compare realworld-checks, published RER policy and the prompt or code logic for the same case. For an exception, also ask whether clearer guidance before equipment selection, installation or submission could have prevented the problem.',
        'Use Run AI audit to read the source documents and recorded package history with the selected rule. Review the advice and any proposed prompt, pre-check or contractor guidance wording against that evidence. Several complementary improvements or no change may be appropriate. A proposed prompt from one case is a starting point to consider alongside the other cases, not a validated improvement.',
        'Check every suggested prompt, pre-check and contractor checklist for preserved evidence alternatives. A document that resolved this example must not become a mandatory extra document for every package. If the invoice or another accepted record already contains the required facts, do not ask for a separate statement or repeated upload. Confirm unresolved evidence standards and result severity with the policy owner before applying a proposal.',
        'Bring the findings from all 3–5 packages together. Record repeated causes, contradictions and open questions, then proceed to Step 5 to choose the improvement. Inspect more cases if the evidence remains conflicting.',
      ],
      examples: [
        {
          title: 'Example: the closure conceals an avoidable extra round',
          description:
            'An issue ends with Corrected documentation accepted. Reading the conversation shows the contractor first supplied the wrong page because the initial instruction was vague. Another package with a precise instruction closed in one round. These examples support investigating corrective instructions even though both closures were successful.',
        },
      ],
      screens: 'The package grid and audit area below; Open invoice package, Invoice Admin and version snapshots.',
      links: [{ label: 'Open Invoice Admin', to: '/invoice-versions-admin' }],
      outcome: 'Documented findings from 3–5 packages that explain which improvement options are supported.',
      note: 'The audit uses the stored package documents, extracted evidence, rule history, complaints, workflow rounds, conversations and internal notes that are available. Expand Evidence included and limitations after the call to see gaps in the records. The result remains in this screen and is not saved as an audit history record; copy useful findings into your work notes. No suggested change is applied automatically.',
    },
    {
      number: 5,
      label: 'Choose and justify the improvement',
      purpose:
        'Make the improvement decision after the package investigations. Combine the aggregate pattern with the detailed findings, then document what should change, who will do it and how success will be judged.',
      instructions: [
        'Review the findings from the 3–5 packages alongside the Step 2 signals and Step 3 breakdowns. Explain which cause recurs, which cases differ and how widespread the suspected problem appears to be. One unusual package does not automatically explain the whole aggregate.',
        'Choose one improvement option to pursue in this cycle, including Make no change for now where justified. Describe the specific change and why it takes priority over the alternatives. If the findings conflict, return to Step 4 with a more precise question.',
        'Check the three-way alignment between realworld-checks, published RER policy wording and the rule prompt or code logic. Document mismatches and confirm the intended requirement with the policy owner. The fix may belong in admin practice, policy wording, the rule, contractor guidance or several places together.',
        'Record the evidence in your usual work notes: the rule and effective period, signal values and denominators, invoice/version references, relevant quotations from the package history and the reasons competing options were set aside. This step does not save a decision record in the application.',
        'Assign a responsible person and define a success measure. For example, clearer next-action wording should preserve correct decisions while reducing avoidable clarification rounds. State how the change will be tried and validated in Steps 6 and 7.',
        'If no change is justified, record whether the evidence supports the current approach or is still insufficient. Set a review date or a specific trigger for reassessment. There is no need to edit a rule merely to complete the sequence.',
      ],
      examples: [
        {
          title: 'Example: choose clearer corrective instructions',
          description:
            'Three of four inspected packages had a correct finding but an initial reason saying only “provide supporting evidence.” The conversations show that naming the required document resolved the confusion. Choose the corrective-instructions option, assign the rule administrator to draft clearer wording, and require unchanged decisions plus a usable next action in the test cases.',
        },
        {
          title: 'Example: choose contractor guidance instead of changing policy',
          description:
            'Several exceptions concern equipment that does not meet a published eligibility requirement. The inspected packages show contractors relied on an incomplete checklist, while realworld-checks, policy and the rule agree on the requirement. The supported improvement is to explain eligibility before equipment selection, rather than automatically relaxing the policy or prompt.',
        },
      ],
      screens: 'Your usual work notes, supported by the Step 2, Step 3 and Step 4 working areas.',
      outcome:
        'One justified improvement with a defined change, owner and success measure, or a documented decision to make no change.',
    },
    {
      number: 6,
      label: 'Try the change',
      purpose:
        'Try a small, specific change in quality and inspect its effect on individual packages. This is the short feedback loop before broader validation.',
      instructions: [
        'Preserve the accepted baseline versions and record their identifiers before editing the current rule in quality. Keep the original prompt or configuration with your notes so the baseline and candidate remain distinguishable.',
        'Confirm the agreed requirement across realworld-checks, published RER policy and the rule. Change the wording or behaviour identified in Step 5, rather than trying to increase the pass rate without understanding why results change.',
        isCodeRule
          ? 'For this code rule, use Fields and Advice Editor for configurable messages and involve a developer for executable logic. Editing the description alone does not change the code that decides the result.'
          : 'Use Fields and Advice Editor to make the candidate prompt change in quality. Review any suggested AI wording against the existing rule and policy before using it; the audit does not apply changes automatically.',
        'In Invoice Admin, use Refresh AI Advice on an audited package. It creates another invoice version and evaluates applicable current rules using the existing extracted evidence. Open the before-and-after version snapshots and compare the target rule’s complete result and reason against the documents.',
        'Use Versions History Inspection to locate the relevant versions and major result changes. Open the individual snapshots to compare reason wording; the status-change view alone does not show every wording change.',
        'For an improvement to training or pre-check instructions, try the proposed guidance against the original preparation task. Ask whether the contractor would know what to supply before submitting. Use representative examples even if no rule prompt changes.',
      ],
      examples: [
        {
          title: 'Example: improve the reason without changing the decision',
          description:
            'The baseline correctly returns Warn but says only that evidence is missing. After the wording change, the refreshed version still returns Warn and identifies the specific missing document and the next action. Check that the named document is genuinely required and that an already complete package remains accepted.',
        },
        {
          title: 'Example: the first attempt goes too far',
          description:
            'A revised prompt explains the required document clearly but starts demanding it for packages where the policy allows another form of evidence. The instruction has become stricter than the agreed requirement. Revise the candidate and repeat the focused inspection before moving to a broader comparison.',
        },
      ],
      screens:
        'Fields and Advice Editor → Invoice Admin → Refresh AI Advice → Versions History Inspection and snapshots.',
      links: [
        { label: 'Open Fields and Advice Editor', to: '/validation-rules-admin' },
        { label: 'Open Invoice Admin', to: '/invoice-versions-admin' },
      ],
      outcome:
        'A candidate change that behaves as intended on the inspected examples and is ready for broader validation.',
      note: 'Refresh AI Advice is a focused inspection of individual packages. Rule Comparison Runs in Step 7 check a candidate across a saved suite. The two activities answer different questions and are both useful for a rule change.',
    },
    {
      number: 7,
      label: 'Validate the change',
      purpose:
        'Check that the improvement works beyond the examples used to develop it and preserves decisions that were already correct. The validation should match the kind of change chosen.',
      instructions: [
        'For a rule change, use Test Suites to assemble representative baseline versions relevant to this rule. Include ordinary compliant packages, known problems, edge cases and authorised exceptions where relevant. Record the expected result and reason for that expectation.',
        'Confirm those expectations against the agreed realworld-checks, published RER policy and rule interpretation. An old baseline may contain an error; matching it is not by itself proof that the candidate is correct.',
        'If baseline versions need rebuilding, use Regression Runs with the intended baseline rule definition. Review the resulting versions, record their identifiers and assemble the suite. Restore the candidate definition in quality before starting its rule comparison.',
        'Use Rule Comparison Runs to compare candidate outputs with the saved baseline outputs across the suite. Inspect significant changes against the actual package documents and your accepted expectations. Distinguish a corrected error from a new regression.',
        'For a guidance or policy clarification, review representative examples with the responsible owner and check that the intended audience can apply the revised requirement consistently. A rule comparison is useful only where rule behaviour or its output is being changed.',
        'Record the suite or examples used, the findings, remaining limitations and the reason to accept or reject the change. Return to Step 6 if it needs revision. Fewer warnings alone is not a success measure.',
      ],
      examples: [
        {
          title: 'Example: better wording, one new regression',
          description:
            'A suite of 20 packages shows clearer next actions in the problem cases, but a previously valid package now fails because its evidence is supplied in a different acceptable format. Inspect that package, correct the candidate and repeat the comparison before accepting the change.',
        },
        {
          title: 'Example: validate a contractor checklist',
          description:
            'Take the original packages that repeatedly omitted a supporting document. Ask a reviewer to use the revised checklist to identify what should be included before submission. If the checklist still leaves the document or acceptable alternatives unclear, improve it before release; no prompt change is required to test this wording.',
        },
      ],
      screens: 'Test Suites; Regression Runs for rebuilding baselines; Rule Comparison Runs for candidate validation.',
      links: [
        { label: 'Open Test Suites', to: '/test-harness/suites' },
        { label: 'Open Regression Runs', to: '/test-harness/regressions' },
        { label: 'Open Rule Comparison Runs', to: '/test-harness/rule-comparisons' },
      ],
      outcome: 'Documented validation with no unacceptable regressions, or a specific change to revisit in Step 6.',
      note: 'The suite picker currently depends on successful producing runs with source-upload records, so refresh-only versions may be unavailable. The AI comparison judges rule outputs; it does not replace the Step 4 inspection of documents, complaints or workflow history.',
    },
    {
      number: 8,
      label: 'Implement and monitor',
      purpose:
        'Put the validated improvement into normal operation through the responsible owners, then check whether it delivers the intended benefit on new invoices.',
      instructions: [
        'Have the responsible owner approve and implement the validated change through the established process. Record exactly what changed, who owns it and when it took effect, together with the validation evidence and the earlier baseline observations.',
        'Check that realworld-checks, published RER policy wording and the rule prompt or code logic still express the same intended requirement. Update related contractor guidance and admin instructions where needed so the improvement does not introduce fresh drift.',
        'Return to Steps 2 and 3 after enough new evidence has accumulated. Compare the chosen success measure with the recorded baseline, accounting for invoice volume, case mix and the new rule period. Inspect packages in Step 4 when a new pattern needs explaining.',
        'Look for unintended effects as well as the intended improvement. Fewer follow-up rounds is useful only if genuine problems are still identified and invoices are not being accepted without the required evidence or authorised exception.',
        'Record the outcome and a review date. If the benefit is unclear or a new problem appears, repeat the relevant steps. Successful corrections remain a normal outcome, while the longer-term aim is for packages to arrive complete and correct with no avoidable follow-up.',
      ],
      examples: [
        {
          title: 'Example: the improvement is helping',
          description:
            'After clearer submission guidance is introduced, a comparable set of new invoices more often includes the document on the first submission. Follow-up falls, and sampled decisions still apply the intended requirement correctly. Record both the reduction in rework and the evidence that decision quality was preserved.',
        },
        {
          title: 'Example: a reassuring number needs investigation',
          description:
            'Warnings fall sharply after a prompt edit, but new complaints say some incomplete invoices are passing. Inspect those packages and compare the prompt with policy and realworld-checks. The lower warning count may reflect weakened detection rather than cleaner submissions.',
        },
      ],
      screens: 'The responsible owner’s implementation process, then Steps 2–4 on this screen.',
      outcome: 'Evidence of operational improvement, or a documented reason to begin another improvement cycle.',
      note: 'The detailed evidence follows the current rule period. Keep the earlier baseline observations and dates in your work notes; the current-period tabs are not an arbitrary historical-date comparison tool.',
    },
  ];
}
