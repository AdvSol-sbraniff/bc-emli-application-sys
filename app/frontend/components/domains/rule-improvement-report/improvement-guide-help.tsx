import {
  Accordion,
  AccordionButton,
  AccordionIcon,
  AccordionItem,
  AccordionPanel,
  Box,
  ListItem,
  OrderedList,
  Text,
  UnorderedList,
} from '@chakra-ui/react';
import React from 'react';
import { REVISION_CLOSURE_LABELS } from '../../shared/claims/revision-closure-guidance';
import { ImprovementAction } from './action-signals';
import { RuleRow } from './types';

function HelpSection({
  title,
  children,
  headingAs = 'h4',
}: React.PropsWithChildren<{ title: string; headingAs?: 'h4' | 'h5' }>) {
  return (
    <AccordionItem borderWidth="1px" borderColor="gray.200" borderRadius="md" mb={3} overflow="hidden">
      <Box as={headingAs}>
        <AccordionButton py={3} _expanded={{ bg: 'blue.50', color: 'blue.900' }}>
          <Text flex="1" textAlign="left" fontWeight="bold">
            {title}
          </Text>
          <AccordionIcon />
        </AccordionButton>
      </Box>
      <AccordionPanel pb={5} fontSize="sm" color="gray.700">
        {children}
      </AccordionPanel>
    </AccordionItem>
  );
}

const ACTION_ASSESSMENTS: Record<ImprovementAction['id'], { primary: string; supporting: string; record: string }> = {
  decision: {
    primary:
      'Start with false-positives, false-negatives and Incorrect decision complaints. The closure row immediately after False-positives counts issues resolved internally before sending to the contractor. Its Warn/Fail records are already included in False-positives; it is not an independent signal. The counts are identical unless Pass/Info issues also received that closure. For Incorrect decision complaints, read which Pass/Info/Warn/Fail result the admin expected and why. Read the original evidence and closure notes to distinguish findings that should not have been raised from problems the rule missed. These counts identify possible decision errors; they do not confirm them.',
    supporting:
      'Look at the remaining closure outcomes, contractor responses and other complaints to consider competing explanations. An approved exception can leave the original finding correct, while an unclear explanation can make a correct decision look wrong. Compare the decision expected under realworld-checks, published RER policy wording and the rule prompt or code logic. A disagreement may expose drift in any of the three; the current admin practice and current prompt both need checking against the intended policy.',
    record:
      'Name the suspected decision error and the signal that raised it. Note what the rule would need to decide differently, and what document or policy evidence must be checked before treating this as a rule-logic problem.',
  },
  explanation: {
    primary:
      'Start with Complaint: All outcomes related to explanation quality. The total includes the explanation complaint types listed in the signal, plus Other. Read each Other complaint’s free-form text to decide whether explanation quality, decision accuracy, corrective instructions or another improvement option is the right fit. Use explanation complaints to identify what made the reason difficult to understand or reuse.',
    supporting:
      'Use the Complaints evidence tab to see which categories contribute to the total. First confirm that the decision was correct and the complaint concerns how it was explained. Read the free-form text for reasons that are too brief, omit useful detail or are difficult to reuse in the pre-populated workflow issue. The aim is contractor-ready wording that admins can review and reuse with minimal editing. If the concern is what the contractor should do next, assess the corrective-instructions option separately.',
    record:
      'Record whether the decision was correct, what the complaint says about the explanation and what wording would make the reason usable in the workflow issue with minimal editing. Confirm that clearer language preserves the same intended requirement across realworld-checks, published RER policy and the rule prompt or code logic. If they disagree about compliance, record the alignment problem and assess decision accuracy or policy clarification as well.',
  },
  correction: {
    primary:
      'Start with unclear-required-action complaints, issues needing multiple sent rounds, unable-to-resolve responses and Issue withdrawn closures. Read the admin’s withdrawal reason and request-and-response history to establish whether the request was unnecessary, superseded or unclear. Investigate whether clearer next-action instructions could have prevented the exchange or extra rounds; assess decision accuracy as well if the original finding was incorrect.',
    supporting:
      'Read the requests alongside responses, complaints and closure comments in the evidence tabs to understand what kind of correction was difficult. Consider whether the instructions omit what to correct, upload, explain or attest. A successful closure records how the issue ended, not whether the first request was clear. Read the full back-and-forth to identify what clarification finally helped and whether a clearer sentence in the original reason could have avoided another round. Training gaps and policy uncertainty can produce similar signals; aggregate request and response counts are not matched exchanges.',
    record:
      'Write down the suspected gap in the next-action instructions and the alternative explanations. The reason serves both the admin assessing the finding and the contractor acting on it. Carry this question into the package audit: could the reason pre-populate the contractor-facing WFM issue with clear instructions and minimal rewriting by the admin? Check that the requested correction or evidence satisfies the same requirement in realworld-checks, published RER policy and the rule prompt or code logic. Resolve conflicting expectations before making them easier to follow.',
  },
  precheck: {
    primary:
      'Start with contractor-visible findings still unresolved at first submission. A remaining warning or failure is a weak clue that the pre-check instructions may need work. It does not prove the contractor ignored the advice or made no attempt to fix the problem. Investigate why the finding remained and whether clearer wording could have helped.',
    supporting:
      'Check the submission and visibility history in example packages before judging the proportions; missing history can leave outcomes unknown. Read the current Pre-check Contractor Action below and ask whether it describes a practical response. Check it against the same requirement in realworld-checks, published RER policy and the rule prompt or code logic; simpler instructions cannot fix disagreement about what is eligible. Consider an incorrect finding, policy uncertainty or a preparation gap as alternatives. Reason complaints concern a separate field and are only indirect clues about pre-check wording.',
    record:
      'State why unclear pre-check instructions are plausible, or why another improvement option looks more relevant. Note the historical wording, visibility and contractor behaviour that an example package must establish; the current wording alone cannot explain older submissions.',
  },
  training: {
    primary:
      'Start with findings cleared before submission and responses reporting a corrected invoice, supporting document, explanation or attestation. A correction made using the generic pre-check message may have been straightforward enough for website guidance or training to prevent upfront. Inspect what changed and what instruction or example could have helped the contractor prepare the package correctly the first time. Compare responses with the Corrected documentation accepted and Explanation or attestation accepted closures to see what was ultimately accepted. Exception granted instead means the requirement was not met but acceptance was authorised.',
    supporting:
      'Use the evidence tabs to read the requests behind the responses, repeated rounds and complaints. They provide context for investigating a possible knowledge or preparation gap. Distinguish that gap from a wrong finding, unclear pre-check wording or missing next-action instructions. Check whether the same preventable mistake affects several packages; a high total alone does not establish a training need. Match requests, responses and closures within individual packages rather than assuming their aggregate totals describe the same exchanges.',
    record:
      'Name the preparation task that might need clearer guidance or training. Record which signals suggest avoidable rework and what examples would show whether contractors could reasonably prepare the package correctly before reaching the pre-check. For exceptions, check whether eligibility guidance before equipment selection or installation could have prevented an ineligible submission. Contractor guidance should teach the agreed requirement across realworld-checks, published RER policy and the rule prompt or code logic; resolve drift between those three before copying it into training.',
  },
  policy: {
    primary:
      'Start with closures recorded as Exception granted. They show acceptance despite an unmet requirement, not proof that the policy is wrong. A contractor may have selected ineligible equipment or submitted an ineligible claim because the upfront guidance was incomplete or unclear. Check the guidance available before selection, installation and submission. Recurring cases may call for better contractor guidance, consistent use of an existing exception process, or policy clarification; the count alone cannot choose between them.',
    supporting:
      'Use attestation and explanation requests, responses, complaints and repeated rounds as context. The same response type can establish compliance or support an exception request; read the closure comment to identify which occurred. Compare realworld-checks (the working policies admins actually apply), the published RER policy wording and the rule prompt or code logic. Different wording is expected, but all three should agree on eligibility, acceptable evidence and exception boundaries. Policy clarification often means resolving drift between these three, not changing which work the program intends to accept.',
    record:
      'Record each interpretation, the mismatch and representative packages. Ask the policy owner to confirm the intended requirement, when an exception is allowed and what evidence or approval it requires. Identify whether admin practice, published policy wording, the prompt or code logic, or several of them need changing. Where those already agree and the problem is preventable contractor misunderstanding, choose better contractor guidance. A recurring exception is not by itself permission to relax the rule.',
  },
  observe: {
    primary:
      'Use the same signals and package findings you assessed under Options 1 through 6. Consider whether any of those options offers a worthwhile improvement. This choice has no separate primary metric.',
    supporting:
      'Low percentages can support lower priority, but consider the seriousness of individual cases as well. Separate a lack of evidence from positive evidence that the current approach is appropriate. Missing history, small samples and unresolved issues may justify waiting for more evidence; they do not establish that no problem exists.',
    record:
      'Distinguish waiting for more evidence from retaining an approach supported by prior package inspection. Record the reason, what evidence is still needed, and when or under what conditions you will reassess.',
  },
};

function ActionGuidance({ rule, action }: { rule: RuleRow; action: ImprovementAction }) {
  const assessment = ACTION_ASSESSMENTS[action.id];
  const isNoChange = action.id === 'observe';
  return (
    <>
      <Text mb={3}>{action.purpose}</Text>
      <OrderedList spacing={3} mb={4}>
        <ListItem>
          <strong>
            {isNoChange ? 'Bring together the other option assessments. ' : 'Read this option’s signal table. '}
          </strong>
          {assessment.primary}
        </ListItem>
        <ListItem>
          <strong>
            {isNoChange
              ? 'Check what could change your conclusion. '
              : 'Use evidence details when you need more context. '}
          </strong>
          {assessment.supporting}
        </ListItem>
        <ListItem>
          <strong>
            {isNoChange
              ? 'Record the reason and when to reassess. '
              : 'Record your assessment, then move to the next option. '}
          </strong>
          {assessment.record}
        </ListItem>
      </OrderedList>

      {action.id === 'precheck' && (
        <Box mb={4} borderLeftWidth="3px" borderColor="gray.300" pl={3}>
          <Text fontSize="sm" fontWeight="semibold" mb={1}>
            Current Pre-check Contractor Action
          </Text>
          <Text fontSize="sm" whiteSpace="pre-wrap">
            {rule.contractor_action?.trim() || 'No instructions are currently configured.'}
          </Text>
          <Text fontSize="sm" color="gray.600" mt={1}>
            Historical wording and visibility may differ. Reason complaints in the signal tables are indirect clues
            about this separate text.
          </Text>
        </Box>
      )}
      <Text as="h5" fontWeight="semibold" mb={2}>
        {isNoChange
          ? 'Questions to settle before deciding'
          : 'Questions to investigate in Step 4 before choosing an improvement'}
      </Text>
      <UnorderedList spacing={2} fontSize="sm" mb={4}>
        {action.investigation.map((question) => (
          <ListItem key={question}>{question}</ListItem>
        ))}
      </UnorderedList>
      <Text fontSize="sm">
        <strong>{isNoChange ? 'What to document: ' : 'What improvement would look like: '}</strong>
        {action.success}
      </Text>
      {rule.source_engine === 'code' && ['explanation', 'correction'].includes(action.id) && (
        <Text fontSize="sm" color="gray.600" mt={2}>
          This is a code rule. Review its configured messages and involve a developer if the generated reason needs a
          code change; it does not have a GenAI prompt to tune.
        </Text>
      )}
    </>
  );
}

export function RuleImprovementStepHelp({
  step,
  isCodeRule,
  rule,
  actions,
}: {
  step: number;
  isCodeRule: boolean;
  rule: RuleRow | null;
  actions: ImprovementAction[];
}) {
  if (step === 5)
    return (
      <Accordion allowMultiple mt={4}>
        <HelpSection title="What to document for the chosen option">
          <Text mb={2}>
            Record the rationale in your usual work notes so another administrator can understand the choice and pick up
            the work. Use the following checklist after assessing the seven options in Step 2, exploring the aggregate
            evidence in Step 3 and inspecting 3–5 packages in Step 4.
          </Text>
          <UnorderedList spacing={2} mb={3}>
            <ListItem>
              <strong>Chosen option and intended improvement:</strong> name one option for this cycle and describe the
              problem it should address. Explain why it is the priority among the options you assessed.
            </ListItem>
            <ListItem>
              <strong>Supporting evidence:</strong> record the rule, evidence period, signal names, counts and
              denominators. Include invoice and version references and relevant complaint or workflow comments, so the
              rationale can be checked later even if the report changes.
            </ListItem>
            <ListItem>
              <strong>Uncertainty and alternatives:</strong> distinguish observations from suspected causes. Record
              conflicting evidence, missing information and other options that might address the same signals.
            </ListItem>
            <ListItem>
              <strong>Three-way alignment:</strong> record what realworld-checks require, what the applicable published
              RER policy says and what the rule prompt or code logic requires for the same case. Identify any drift, the
              policy question to resolve and who will confirm the intended requirement. Note which parts need to change
              together, including the contractor guidance that communicates the agreed requirement.
            </ListItem>
            <ListItem>
              <strong>Package audit findings:</strong> record the 3–5 package references, repeated causes and
              contrasting cases from Step 4. Explain which observations you verified against the documents and
              conversations, including any AI suggestions that were supported or contradicted by that evidence.
            </ListItem>
            <ListItem>
              <strong>Owner and success measure:</strong> name who will investigate and implement any resulting change,
              what evidence would demonstrate improvement, and when to reassess. Rule changes require regression checks;
              guidance, training and policy changes need validation suited to the chosen option.
            </ListItem>
            <ListItem>
              <strong>If making no change:</strong> explain whether you are waiting for more evidence or retaining an
              approach supported by package inspection. Record what would cause you to reconsider.
            </ListItem>
          </UnorderedList>
          <Text>
            This choice should be supported by the completed package inspections. Return to Step 4 if important
            questions remain unresolved before trying the change in Step 6.
          </Text>
        </HelpSection>
      </Accordion>
    );
  if (step === 3)
    return (
      <Box mt={5}>
        <Text as="h4" fontWeight="semibold" mb={2}>
          Evidence tab reference
        </Text>
        <Text fontSize="sm" mb={3}>
          Open the relevant evidence tab when an improvement option raises a question about a grouped total or pattern.
          Filtering a tab does not change the Step 2 signal counts. The existing invoice grids can provide a direct
          route to examples; use Step 4 to bring the package inspections and audits together before choosing an
          improvement. There is no requirement to visit every tab.
        </Text>
        <EvidenceTabReference isCodeRule={isCodeRule} />
      </Box>
    );
  if (step !== 2) return null;
  return (
    <Accordion allowMultiple mt={4}>
      <HelpSection title="Keep realworld-checks, published policy and rule prompts aligned">
        <Text mb={3}>
          This is a recurring check throughout rule improvement. The three versions of a requirement serve different
          audiences and will not use identical wording, but they should lead to the same intended compliance decision.
        </Text>
        <UnorderedList spacing={3}>
          <ListItem>
            <strong>Realworld-checks:</strong> the working policies, interpretations and evidence standards admins
            actually use when deciding whether an invoice is acceptable. These may have drifted from the published
            policy, even where the practice is familiar and consistently applied.
          </ListItem>
          <ListItem>
            <strong>Published RER policy wording:</strong> the approved requirement in the policy document, expressed in
            formal legal language. Identify the wording applicable to the case and ask the policy owner to clarify
            ambiguities or a difference between that wording and the intended policy.
          </ListItem>
          <ListItem>
            <strong>Rule prompt or code logic:</strong> the operational interpretation used to assess the package. It
            may restate the policy for an LLM or implement it in code, but should not make the requirement stricter,
            weaker or different without an agreed policy change.
          </ListItem>
          <ListItem>
            <strong>Compare the same case across all three:</strong> record the expected result, required evidence and
            any exception under each interpretation. Distinguish a genuine mismatch from different wording that leads to
            the same decision. Confirm the intended requirement with the policy owner and correct whichever parts have
            drifted; matching current admin practice alone is not enough.
          </ListItem>
          <ListItem>
            <strong>Carry the agreed requirement into guidance and testing:</strong> contractor instructions, pre-check
            messages and workflow reasons should communicate the same expectation. Test against that agreed meaning,
            implement the related changes together and watch for renewed drift. The aim is consistent decisions and
            complete, correct submissions from the outset.
          </ListItem>
        </UnorderedList>
      </HelpSection>
      {rule &&
        actions.map((action, index) => (
          <HelpSection key={action.id} title={'Option ' + (index + 1) + '. ' + action.title}>
            <ActionGuidance rule={rule} action={action} />
          </HelpSection>
        ))}
      <HelpSection title="How to read the signal numbers">
        <UnorderedList spacing={3}>
          <ListItem>
            <strong>Signals are a starting point.</strong> Open an option to see its signal table directly. The signals
            are not an automatic recommendation or proof of a cause. Use the evidence tabs for category breakdowns and
            individual examples when needed. All complaint categories remain included in the displayed complaint
            signals, individually or in a grouped total. Make no change for now is a conclusion from these assessments
            and has no separate signal table.
          </ListItem>
          <ListItem>
            <strong>Responses and closures are used as signals; requests provide context.</strong> Request counts are
            not used as signals under any improvement option. A request records what the admin asked the contractor to
            do. A response records what the contractor supplied or reported, and a closure records the admin’s final
            decision. Responses and closures therefore provide more direct evidence of what happened. Requests remain
            available in the evidence tabs and package conversations to help explain those outcomes and assess whether
            the instructions were clear.
          </ListItem>
          <ListItem>
            <strong>Read What to investigate.</strong> It explains what each signal measures and what to investigate;
            Value shows the count or round statistic. Checks, invoice versions, distinct packages, complaints and
            contractor responses are different units. Consider the sample size and limitations before interpreting a
            value. A large count alone does not make an improvement option the right choice.
          </ListItem>
          <ListItem>
            <strong>% of invoices uses distinct packages.</strong> It shows the invoices with that signal as a
            percentage of all invoices assessed by this rule in the current report period and filters. Each invoice
            counts once per signal, even if it has several versions, checks or workflow rounds. Grouped signals also
            count each invoice once. The percentage therefore may not equal Value divided by the invoice total. Hover
            over a percentage to see its invoice counts. A dash means no invoices, unavailable data or a round statistic
            such as an average, median or maximum. Signal percentages overlap and must not be added together.
          </ListItem>
          <ListItem>
            <strong>Use 25% as an initial prompt to investigate.</strong> A problem signal affecting 25% or more of
            invoices is a suggested starting point for closer review, not an automatic reason to change the rule.
            Consider the underlying count, sample size and seriousness of individual cases; a lower percentage does not
            make an important problem safe to ignore. Successful corrections, supplied attestations and cleared
            pre-check findings can show that the process works. High percentages for these may point to opportunities
            for better preparation or training, rather than a defect in the rule.
          </ListItem>
          <ListItem>
            <strong>Grouped complaint values still have a breakdown.</strong> Use the Complaints evidence tab to see the
            individual categories included in a grouped signal. A complaint count is not a count of distinct packages;
            several rule checks or versions of the same package can have complaints.
          </ListItem>
          <ListItem>
            <strong>Shared signals can support different options.</strong> A difficult workflow round might relate to
            decision accuracy, explanation, corrective instructions, training or policy. Record these alternatives.
            Counts overlap between options and must not be added into a total problem score. Aggregate request and
            response counts do not establish who answered which request.
          </ListItem>
          <ListItem>
            <strong>Zero and missing information are different.</strong> Zero is a measured count; Not available means
            the metric is unavailable. Check unknown outcomes, missing history and sample size. Neither absent
            complaints nor absent evidence proves that the rule works well.
          </ListItem>
          <ListItem>
            <strong>Pre-check outcomes describe the first recorded submission.</strong> Unresolved means a
            contractor-visible warn/fail remains on the submitted version. Cleared means an earlier visible finding
            became pass/info for the same rule and upgrade without an intervening recorded rule revision. Each package
            counts once: an unresolved finding takes precedence, and all observed findings must have matching clear
            results to count as cleared. Later resubmissions and refreshed advice do not replace that outcome.
          </ListItem>
          <ListItem>
            <strong>Pre-check coverage limits the interpretation.</strong> Unknown outcomes remain in the denominator;
            packages without usable submission or visibility history are excluded and counted separately. Unsubmitted
            packages and checks produced only after first submission are excluded. Historical visibility is inferred
            from recorded settings, not a record of someone reading the advice. A cleared finding is an observed result,
            not proof of a contractor correction; missing checks, hidden findings and rule changes are not successful
            corrections.
          </ListItem>
        </UnorderedList>
      </HelpSection>
    </Accordion>
  );
}

function EvidenceTabReference({ isCodeRule }: { isCodeRule: boolean }) {
  return (
    <Accordion allowMultiple>
      <HelpSection headingAs="h5" title="Rule history">
        <Text mb={2}>
          Use this tab for more than identifying what changed. It connects each rule definition or implementation period
          to the results produced while it was effective, so you can judge whether a change actually improved the rule.
          Compare invoice volume, complaints, false-positives and false-negatives, follow-up and rounds between periods.
        </Text>
        <Text mb={2}>
          Check whether realworld-checks or published RER policy also changed during the period. Compare the prompt or
          code logic with the policy and admin interpretation applicable at the time; a change in results may reflect
          drift between them. A favourable pass rate alone does not establish alignment.
        </Text>
        {isCodeRule ? (
          <>
            <Text mb={2}>
              This table represents one executable-code implementation identified by its code-rule key. The row
              information icon shows the complete database configuration—labels, messages, visibility and workflow
              policy—but not the executable source code.
            </Text>
            <Text mb={2}>
              When a code release changes the rule’s behaviour, development practice must create a new code-rule key and
              database record. The application keeps keys unique and immutable, but cannot inspect source code and
              enforce that release practice itself. A new record creates a clean measurement boundary so the old and new
              implementations are not evaluated as if they were one rule.
            </Text>
          </>
        ) : (
          <Text mb={2}>
            Every saved GenAI rule change creates a new effective period. Use a row’s information icon to inspect the
            complete rule values that applied during that period, including the prompt, messages, evidence instructions
            and workflow settings. The other report tabs deliberately use only the current period; this history table is
            where you compare it with earlier periods.
          </Text>
        )}
        <UnorderedList spacing={2}>
          <ListItem>
            <strong>Check sample size first:</strong> zero candidates across six assessed invoice versions is much
            weaker evidence than zero across sixty comparable versions.
          </ListItem>
          <ListItem>
            <strong>Compare rates as well as counts:</strong> five complaints after 200 checks may be an improvement
            over four complaints after 20 checks. The table supplies counts and volume so you can make that judgement
            rather than reading a raw total alone.
          </ListItem>
          <ListItem>
            <strong>Check what changed:</strong> if false positives fall after narrowing applicability, that is a
            plausible effect. If only contractor-facing wording changed, improved complaint and round patterns are more
            meaningful than a change in detection accuracy.
          </ListItem>
          <ListItem>
            <strong>Example:</strong> a prior period produced 12 false-positives across 80 assessed versions. The
            current period has none across only six. That is encouraging, but too early to conclude that the change
            worked; keep observing until the current period has a credible sample and case mix.
          </ListItem>
          <ListItem>
            <strong>Act on the comparison:</strong> retain a change when the intended measure improves without a new
            adverse pattern. Investigate or reverse it when results worsen. Keep observing when volume is too small or
            the invoice mix is not comparable.
          </ListItem>
        </UnorderedList>
      </HelpSection>

      <HelpSection headingAs="h5" title="Complaints">
        <Text mb={2}>
          Incorrect decision complaints concern the rule’s Pass/Info/Warn/Fail result. The other specific complaint
          categories concern the explanation or corrective instructions: a finding can be accurate while its reason
          still needs improvement. Read Other complaints individually to establish the concern. The vertical chart
          always shows the full complaint vocabulary, including zeroes. The grid beneath it contains the exact reasons
          and comments behind the counts. Select a chart bar or use the complaint-type filter to narrow the grid while
          keeping the full distribution visible.
        </Text>
        <UnorderedList spacing={2}>
          <ListItem>
            <strong>Start with the distribution:</strong> one dominant complaint type usually gives a clearer next step
            than an even mix. Then filter to that type and read several comments to confirm that administrators used the
            pull-down consistently.
          </ListItem>
          <ListItem>
            <strong>Separate decision accuracy from explanation quality:</strong> use Incorrect decision when the
            Pass/Info/Warn/Fail result should have been different, and read the expected result and justification in the
            complaint text. If the result was correct but poorly explained, investigate Option 2. If the reason does not
            make the contractor’s next step clear, investigate the corrective-instructions option.
          </ListItem>
          <ListItem>
            <strong>Possibly fine:</strong> an administrator prefers shorter wording, but the reason cites the correct
            evidence and required action. A single stylistic complaint does not establish a pattern.
          </ListItem>
          <ListItem>
            <strong>Likely needs improvement:</strong> repeated complaints say that the reason cites the wrong document
            or never explains what the contractor must provide.
          </ListItem>
          <ListItem>
            <strong>Useful interpretation:</strong> repeated <strong>Too verbose</strong> complaints usually suggest a
            reason-writing change, while repeated <strong>Incorrect decision</strong> complaints call for checking the
            expected result against the package evidence, realworld-checks, RER policy wording and prompt or code logic.
            <strong>Irrelevant or duplicate</strong> can expose an applicability or overlapping-rule problem.
          </ListItem>
          <ListItem>
            <strong>Check concentration:</strong> complaints from one administrator may reflect a usage difference; the
            same complaint across several administrators and contractors is stronger evidence of a systemic problem.
          </ListItem>
          <ListItem>
            <strong>Example improvement:</strong> when results are usually correct but administrators repeatedly select
            <strong>Required action is unclear</strong>, rewrite the contractor-facing action and examples while leaving
            the pass/fail logic alone. Review later periods to see whether that complaint declines.
          </ListItem>
        </UnorderedList>
      </HelpSection>

      <HelpSection headingAs="h5" title="False-positives">
        <Text mb={2}>
          These began as warnings or failures and their rule issue closed internally before being sent to the
          contractor, with no contractor action required. Review the issue and complaint to determine whether the rule
          should have returned Pass/Info.
        </Text>
        <UnorderedList spacing={2}>
          <ListItem>
            <strong>The internal-closure row overlaps:</strong> every record counted here is also counted under Resolved
            internally before sending to contractor. Those Warn/Fail records are repeated for context, not additional
            problems. The closure count is larger only when it also includes Pass/Info issues closed internally. For
            example, an all-results workflow policy can create issues for Pass/Info results too.
          </ListItem>
          <ListItem>
            <strong>Check strictness and the underlying requirement:</strong> the prompt or code logic may be too
            strict, or the entire concept of the rule may differ from realworld-checks and the RER policy wording.
            Compare all three and resolve any drift with the policy owner before deciding how to change the rule.
            Different wording can serve different needs, but all three should apply the same intended requirement.
          </ListItem>
          <ListItem>
            <strong>Read the complaint and check that it was recorded:</strong> read the category and especially the
            free-form text to understand the admin&apos;s concern. Admins should record a complaint and explanation when
            they identify an incorrect result. If these are missing, address the admin training gap so the concern is
            documented at the same time as the workflow decision.
          </ListItem>
          <ListItem>
            <strong>Review the complete chain:</strong> open the invoice version, read the original rule result and
            evidence, then compare the workflow discussion and disposition comment. The closure label alone cannot tell
            you why no contractor action was required.
          </ListItem>
          <ListItem>
            <strong>Possibly fine:</strong> an administrator found acceptable evidence elsewhere, decided that no action
            was needed for a legitimate case-specific reason, or used the no-action close type imprecisely.
          </ListItem>
          <ListItem>
            <strong>Likely a rule problem:</strong> the same rule repeatedly fails invoices where the required evidence
            is visibly present or the rule does not apply.
          </ListItem>
          <ListItem>
            <strong>Example:</strong> 9 of 14 failures close with no action, and reviewers repeatedly state that the
            model number was present on page two. That pattern supports narrowing the rule or improving how it locates
            the evidence.
          </ListItem>
          <ListItem>
            <strong>Use the denominator:</strong> three candidates across five assessed versions is a different signal
            from three across five hundred. Confirm that the affected invoices were actually eligible for the rule
            before treating the ratio as meaningful.
          </ListItem>
          <ListItem>
            <strong>Look for a shared cause:</strong> repeated acceptable evidence in the same document location
            suggests an evidence-search change; repeated inapplicability suggests a scope condition; inconsistent
            no-action closures may instead require administrator guidance.
          </ListItem>
          <ListItem>
            <strong>Choose the smallest change:</strong> tune rule logic only when the records show a repeatable
            incorrect trigger. Improve the reason if detection is correct but the explanation caused confusion, or keep
            observing when the cases do not share a cause.
          </ListItem>
        </UnorderedList>
      </HelpSection>

      <HelpSection headingAs="h5" title="False-negatives">
        <Text mb={2}>
          These checks passed or returned information, but a workflow issue was opened from that exact rulecheck. Review
          the issue and complaint to determine whether the rule should have returned Warn/Fail.
        </Text>
        <UnorderedList spacing={2}>
          <ListItem>
            <strong>Check strictness and the underlying requirement:</strong> the prompt or code logic may be too
            lenient, or the entire concept of the rule may differ from realworld-checks and the RER policy wording.
            Compare all three and resolve any drift with the policy owner before deciding how to change the rule.
            Different wording can serve different needs, but all three should apply the same intended requirement.
          </ListItem>
          <ListItem>
            <strong>Read the complaint and check that it was recorded:</strong> read the category and especially the
            free-form text to understand the admin&apos;s concern. Admins should record a complaint and explanation when
            they identify an incorrect result. If these are missing, address the admin training gap so the concern is
            documented at the same time as the workflow decision.
          </ListItem>
          <ListItem>
            <strong>Confirm the issue matches the rule:</strong> read the passing or informational result and the linked
            workflow record. Treat it as a miss only when the later corrective request concerns the same requirement
            this rule was meant to assess.
          </ListItem>
          <ListItem>
            <strong>Possibly fine:</strong> the issue was created automatically by an all-results workflow policy,
            remained pending without human follow-up, was opened as a precaution, or was linked to the wrong source by
            an administrator.
          </ListItem>
          <ListItem>
            <strong>Likely a rule problem:</strong> administrators repeatedly open issues for the exact defect that the
            rule was designed to catch.
          </ListItem>
          <ListItem>
            <strong>Example:</strong> the rule passes because an invoice mentions a permit, but administrators
            repeatedly request the missing permit document itself. That suggests the rule is checking for the word
            rather than the required evidence.
          </ListItem>
          <ListItem>
            <strong>Distinguish severity from frequency:</strong> a rare miss involving a high-value or mandatory
            requirement may still justify action. Several low-impact candidates may first warrant closer monitoring or a
            targeted test case.
          </ListItem>
          <ListItem>
            <strong>Look for what was missed:</strong> recurring missing attachments may require evidence-presence
            logic; recurring wrong values may require a validation change; issues unrelated to the rule should be
            corrected in workflow linkage or administrator practice instead.
          </ListItem>
          <ListItem>
            <strong>After a change:</strong> add the confirmed examples to rule testing, then monitor the new period for
            fewer equivalent misses without creating new false positives.
          </ListItem>
        </UnorderedList>
      </HelpSection>

      <HelpSection headingAs="h5" title="Workflow management rounds">
        <Text mb={2}>
          This tab measures follow-up effort. Several rounds alone do not establish a contractor training need. Compare
          how many invoice versions required follow-up with the total and average sent rounds, then inspect the grid to
          see what contractors were asked to correct. Use the minimum-round filter to start with the cases that required
          the most exchanges.
        </Text>
        <UnorderedList spacing={2}>
          <ListItem>
            <strong>Review how resolution was reached:</strong> read the initial request, contractor responses and
            recorded conversation across the rounds. An issue may close successfully after avoidable back-and-forth.
            Identify what finally clarified the request and whether including that wording in the original reason and
            pre-populated WFM issue could have prevented an extra round.
          </ListItem>
          <ListItem>
            <strong>Read the measures correctly:</strong> invoice versions with follow-up are distinct assessed versions
            that produced a rule issue. Total rounds count sent administrator-to-contractor exchanges; internal drafts
            do not count. Average rounds is calculated across issues with at least one sent round.
          </ListItem>
          <ListItem>
            <strong>Start with the outliers:</strong> raise the minimum-round filter to find the invoices requiring the
            most back-and-forth. Read their requests, responses and final disposition before assuming that the
            contractor misunderstood the rule.
          </ListItem>
          <ListItem>
            <strong>Likely straightforward:</strong> 30 invoice versions require follow-up, with 32 total rounds and a
            1.1 average. Most requests appear to be understood and resolved in one exchange.
          </ListItem>
          <ListItem>
            <strong>Possible guidance or training problem:</strong> 8 versions require 21 rounds, and the records show
            repeated omissions of the same equipment-specification page. Add a submission example or train contractors
            on that requirement.
          </ListItem>
          <ListItem>
            <strong>Target the response:</strong> if one contractor accounts for most repeated rounds, targeted coaching
            may be appropriate. If many contractors make the same mistake, the program’s written instructions or form
            design may be the real problem.
          </ListItem>
          <ListItem>
            <strong>Do not equate rounds with rule accuracy:</strong> a correct rule can generate many rounds when
            submission instructions are poor, and an incorrect rule can close in one round through an exception. Use
            Complaints, Requests and responses, and Closure outcomes to identify the cause. Repeated corrections of the
            same mistake can support guidance or training; no-action or exception closures can raise rule or policy
            questions. Open or pending cases do not yet have a final outcome.
          </ListItem>
          <ListItem>
            <strong>Example improvement:</strong> if many contractors repeatedly omit the same specification page, add a
            checklist example or pre-submission instruction. If the same rule request itself changes from round to
            round, improve administrator guidance or the rule’s required-action text.
          </ListItem>
        </UnorderedList>
      </HelpSection>

      <HelpSection headingAs="h5" title="Requests and responses">
        <Text mb={2}>
          These charts count pull-down selections in sent workflow rounds: the action administrators asked contractors
          to take and the response method contractors selected when replying, before closure. Every selection is counted
          during the current measurement period, so an issue with several exchanges can contribute several selections.
          The two totals need not match and the columns are not one-to-one pairings.
        </Text>
        <Text fontWeight="bold" mb={2}>
          What a recurring pattern can suggest
        </Text>
        <UnorderedList spacing={2}>
          <ListItem>
            <strong>Use the charts as a workflow map:</strong> first identify the most common administrator request,
            then compare the response distribution and closure outcomes. Because the charts are aggregates, open
            representative workflow records on the rounds or closure tabs before concluding that two selections belonged
            to the same exchange.
          </ListItem>
          <ListItem>
            <strong>Normal correction path:</strong> Corrected invoice uploaded and Supporting document uploaded are
            normal steps on the happy path. When the supplied documents resolve the issue, it also appears under
            Corrected documentation accepted. These signals can describe the same resolution: retain both to see what
            was supplied and what was accepted, but do not add their counts as separate problems. Check whether clearer
            upfront guidance or a checklist could have helped the contractor submit a complete, correct package the
            first time. Successful resolution is a good outcome; over time, the aim is for every invoice package to
            arrive complete and correct, with no corrections or follow-up rounds needed.
          </ListItem>
          <ListItem>
            <strong>Possible requirement or rule problem:</strong> admins repeatedly request explanations, but
            contractors frequently select <strong>Unable to resolve</strong>. Inspect the comments to learn whether the
            evidence is unavailable, the requirement is unclear, or the rule is asking for something unreasonable.
          </ListItem>
          <ListItem>
            <strong>Possible communication mismatch:</strong> admins usually request a corrected invoice, while
            contractors usually provide an explanation. The admin request wording, contractor instructions, or workflow
            choices may not be expressing the intended next step clearly.
          </ListItem>
          <ListItem>
            <strong>Healthy expected path:</strong> an explanation or attestation supplies the context or assurance
            needed to establish compliance, and the admin closes the issue as Explanation or attestation accepted. The
            rule may be working correctly: this is a normal resolution on the happy path. Use these successful exchanges
            to improve upfront guidance so contractors include the necessary context or assurance initially. Over time,
            the aim is for every invoice package to arrive complete, correct and clear enough to assess without
            follow-up rounds.
          </ListItem>
          <ListItem>
            <strong>Interpret explanations and attestations together:</strong> an attestation is the more formal
            counterpart of an explanation. Contractors select these response types, while trained admins record the
            closure after assessing the evidence. The closure is generally more useful for distinguishing clarification
            of compliance from an authorised exception for an unmet requirement. Retain both responses as signals of
            what contractors needed to explain or confirm, and whether better upfront guidance could have avoided the
            exchange. Read the response, conversation and closure together to establish what happened.
          </ListItem>
          <ListItem>
            <strong>Watch for pull-down misuse:</strong> broad or inconsistent selections can obscure the real pattern.
            If comments describe document requests while administrators select explanation, clarify the pull-down
            definitions or train users before changing the rule.
          </ListItem>
          <ListItem>
            <strong>Separate local and systemic patterns:</strong> one contractor repeatedly choosing Unable to resolve
            may need direct support. The same response across contractors may mean that required evidence is
            unavailable, the instruction is unclear, or the rule demands something the program cannot reasonably
            substantiate.
          </ListItem>
        </UnorderedList>
      </HelpSection>

      <HelpSection headingAs="h5" title="Closure outcomes">
        <Text mb={2}>
          This chart contains only terminal closure outcomes. <strong>Pending admin review</strong> and{' '}
          <strong>Open</strong> are workflow states, not outcomes, so they are excluded from the chart and evidence
          total. Each bar counts closed issues, not invoices or rounds. Select a chart bar or choose an outcome to
          inspect the underlying invoice records and disposition comments.
        </Text>
        <UnorderedList spacing={2}>
          <ListItem>
            <strong>Start with the dominant outcome:</strong> select its bar or filter, then sample the disposition
            comments. Confirm that administrators are using the closure type consistently before treating the chart as
            evidence about the rule.
          </ListItem>
          <ListItem>
            <strong>{REVISION_CLOSURE_LABELS.closed_via_corrected_documentation}:</strong> this is a normal, successful
            resolution when the rule identifies a genuine problem and the contractor corrects it. Even this successful
            outcome can reveal an opportunity for better upfront training. For example, recurring missing signatures may
            be prevented by clearer website guidance or a submission checklist. The goal is for an increasing proportion
            of packages to pass review the first time, without document changes or contractor follow-up rounds, while
            the rule continues detecting genuine problems.
          </ListItem>
          <ListItem>
            <strong>{REVISION_CLOSURE_LABELS.closed_via_attestation}:</strong> clarification or a formal assurance
            establishes that the requirement is met. Example: an ambiguous invoice is clarified to establish that the
            fan meets the size requirement. Inspect the responses and conversation for context or assurance that better
            submission guidance could have prompted upfront. This combined outcome does not count explanations and
            attestations separately; their response types and comments show what was supplied.
          </ListItem>
          <ListItem>
            <strong>{REVISION_CLOSURE_LABELS.closed_via_exception}:</strong> the requirement is not met, but an
            authorised exception permits acceptance. For example, equipment below the required efficiency may be
            accepted through an authorised exception. The contractor may have chosen it because upfront eligibility
            guidance was unclear; this can call for better guidance rather than a different policy. Read the
            explanation, closure and guidance available before the work was done. Compare realworld-checks, published
            RER policy wording and the rule prompt or code logic to establish whether they agree on the requirement and
            exception boundaries. Recurring exceptions may expose drift that needs the policy owner to resolve, or
            circumstances already handled appropriately by the exception process. The count alone does not establish
            which applies.
          </ListItem>
          <ListItem>
            <strong>{REVISION_CLOSURE_LABELS.closed_no_contractor_action_required}:</strong> the admin closes the issue
            before sending it to the contractor. This outcome is unavailable after a sent round and does not describe an
            accepted contractor explanation. Read the original evidence and internal closure comment to determine
            whether the finding was justified. Its Warn/Fail records are already included in False-positives and must
            not be counted as additional problems. The two counts are identical unless Pass/Info issues also received
            this closure.
          </ListItem>
          <ListItem>
            <strong>{REVISION_CLOSURE_LABELS.closed_as_withdrawn}:</strong> the admin withdrew the workflow issue after
            it was sent to the contractor. Read the disposition comment and conversation to establish why the request
            was withdrawn and whether the original finding or corrective instructions need improvement.
          </ListItem>
          <ListItem>
            <strong>Compare with other tabs:</strong> internal closures on Warn/Fail results are the records used for
            the false-positive signal, not independent confirmation of it; Corrected documentation accepted or
            Explanation or attestation accepted closures can reveal opportunities for clearer submission guidance;
            approved exceptions concentrated around one scenario may point to contractor guidance gaps, a legitimate
            exception pattern or misalignment between realworld-checks, published policy and rule prompts. Investigate
            which explanation fits before choosing a change.
          </ListItem>
          <ListItem>
            <strong>Do not force a change from a small sample:</strong> one unusual closure can be legitimate. Look for
            repeated reasoning across several invoices, then decide whether to tune the rule, clarify policy, improve
            training or keep observing.
          </ListItem>
        </UnorderedList>
      </HelpSection>
    </Accordion>
  );
}
