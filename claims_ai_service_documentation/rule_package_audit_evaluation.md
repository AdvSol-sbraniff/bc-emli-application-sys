# Rule package audit: local evaluation protocol

This protocol was fixed before any live audit call on 2026-09-18. It evaluates advice about one rule and one package, not a full regression-harness comparison. The executable companion is `claims_ai_service_ddl/dev_tools/rule_package_audit_evaluation.rb`.

## Sources and isolation

Use the already processed Demo 1 wood-to-heat-pump package and Demo 4 heat-pump-water-heater package from `Test Data`. The runner locates authoritative invoice versions by filename and copies their evidence into separately identified local invoices. It reuses immutable document pointers and never changes the originals or uploads/deletes blobs. Demo 1's stored WETT report is the corrected-models variant; that exact stored version is authoritative for these tests, rather than the older differently worded repository PDF.

The WETT document records a homeowner declaration that the previous wood system heated at least half the home through the heating season to 21°C. This is not an independent heat-load certification. The registry's policy excerpt supplies the substantive requirement; recorded staff notes explain the fixture's working practice. They are not a substitute for policy-owner authority. An auditor may reasonably distinguish documented evidence from independently verified capacity.

Each scenario creates a disabled, dedicated copy of the rule with its own key and mapping. Changes apply only to those copies. Rule checks, complaints and discussions are deliberately constructed evaluation evidence, not claims about the original demo's actual processing. The source documents themselves remain unchanged. Scenario names and expected answers are stored in the evaluation manifest, not injected as instructions into the model.

Preparation records every created identifier in a recoverable manifest under `tmp/rule-package-audit-evaluation/`. Local guards require Rails development, database `app_development`, and a local PostgreSQL host. Cleanup checks the ownership marker, deletes only manifest-owned fixtures in dependency order, and does not delete source documents. Evaluation cleans up by default, including when calls fail; `--keep-fixtures` is an explicit exception for another evaluation stage. The source rule's attributes are fingerprinted and checked again after cleanup.

## Development scenarios

1. **Too strict.** Demo 1 has its invoice, photographs and real WETT declaration. The temporary rule accepts only literal historical 50%/21°C statements on the invoice and ignores supporting documents. The recorded result is Fail, with an incorrect-decision complaint and an internally resolved issue. Staff identify the supplied declaration and explain the usual whole-package check. Acceptable advice identifies the unsupported invoice-only restriction and considers the WETT statement without treating it as independent certification. A replacement prompt should retain the actual prior-primary-heating requirement, permit relevant evidence and distinguish insufficient from contradictory evidence. It must not automatically weaken substantive policy.

2. **Missed problem.** Demo 1's invoice and photographs remain, but the WETT declaration is absent. The temporary rule accepts the new heat pump being primary as proof of the previous wood system's capacity. Its recorded Pass is challenged by a complaint and an open issue. Acceptable advice identifies the old/new-system confusion, the unresolved historical requirement and a bounded prompt correction. It must not claim that missing evidence proves the installation was ineligible.

3. **Unclear corrective instruction.** The rule correctly requires the prior-heating evidence, but explicitly produces the vague corrective sentence “Provide more evidence.” Version 1 lacks the WETT declaration. Two rounds show the contractor asking what evidence is required, then receiving a specific request and supplying the real WETT document in version 2. The later Pass and corrected-documentation closure do not erase the avoidable first round. Acceptable advice preserves the substantive rule, improves a reason that can prepopulate contractor-facing WFM text, and cites the actual back-and-forth. The suggested wording must work for both the admin and contractor.

4. **Weak pre-check.** The decision prompt and later corrective reason are already specific. The temporary pre-check is merely “Check the invoice.” A contractor message explains that it did not reveal which prior-heating information was needed. The contractor submits without that evidence, then supplies the declaration after a precise request. Acceptable advice proposes actionable pre-check wording and distinguishes it from the later generated reason. It should not weaken the eligibility requirement or invent a decision defect.

5. **Contractor guidance.** The prompt, pre-check and first reason explicitly name the required prior-primary-heating evidence. The contractor says the package was prepared without reading that guidance and corrects it after one clear request. The closure is a normal successful documentation outcome. Acceptable advice improves preparation/training material so future packages arrive complete the first time, while recognising that the rule and correction process worked. Prompt/pre-check proposals should remain null unless a specific evidenced defect independently justifies one; generic “improvements” are insufficient.

## Held-out scenarios

Do not inspect held-out model outputs while tuning on the five development scenarios. Their facts and rubrics are defined here before calls.

6. **Multiple improvements.** The complete Demo 1 package contains the WETT statement, but both an invoice-only prompt and a pre-check saying “A supporting report is never accepted” reject it. Acceptable advice addresses both defects, explains their separate effects and proposes compatible changes. Contractor guidance may also be justified, but a policy change is not automatically required.

7. **No change.** Demo 4's actual invoice explicitly describes replacing the home's primary electric-resistance water heater with its sole primary heat-pump water heater. The copied rule has clear decision and pre-check wording; its Pass has no complaint, revision round or unresolved issue. Acceptable advice finds no material improvement justified by this package, keeps all proposal fields null, and acknowledges that one clean package does not prove population-wide perfection.

8. **Uncertainty.** Demo 1 lacks the WETT declaration. A contractor says the old wood stove heated about 40% of the home, while a staff note reports an unverified telephone estimate above 50%. The issue remains open; there is no approved exception or independent source resolving the conflict. Acceptable advice identifies the conflicting accounts, seeks specific historical evidence and, where needed, authorised policy clarification. It must not confidently declare compliance/noncompliance, misdescribe missing material as inspected, or automatically relax the threshold.

## Evaluation rules fixed before calls

- Evaluate the substantive finding, source support, chronology, proportionality and uncertainty. Exact wording and one predetermined replacement prompt are not answer keys.
- Each significant claim should be traceable to a supplied document, check, comment or discussion record. Unsupported claims, invented conversations, treating later evidence as originally available, or claiming a policy decision was approved when it was not are failures.
- Guidance-only and no-change are positive controls against proposing changes merely to fill output fields. Multiple-improvement is a positive control against forcing one option.
- A complaint or issue closure is evidence to investigate, not automatic proof of an incorrect decision. Staff's working practice, the policy excerpt and the prompt must be considered together.
- Save the actual outbound context, attachment descriptors, provider transport coverage and returned advice under ignored `tmp`; preserve a concise non-sensitive result summary separately.
- Deterministic checks confirm shape, nullability, source coverage and fixture integrity. Any keyword/field checks are triage only; the agent reviews the complete advice against this rubric and records the judgment independently.
- Repeat the too-strict development case and no-change holdout to observe variability. Limited repetitions are not a reliability estimate.
- After initial evaluation, permit no more than three refinement cycles. Diagnose context, code, instructions, variability or mistaken expectations before changing anything. Do not tune to the exact demo wording or weaken the rubric to force a pass.

## Candidate-prompt experiment

Where an audit proposes a prompt, compare the fixture's original prompt and the proposed prompt against source-backed complete Demo 1 and a copy without the WETT historical declaration. These calls include only the rule task and original package evidence/attachments, not historical results, complaints, expected answers or audit advice. The complete case supports prior-primary heating through the documented declaration; the incomplete case does not establish the old system's 50%/21°C capacity merely by describing the replacement heat pump. Depending on evidence-sufficiency interpretation, Pass or cautious Warn can be reasonable for the complete case, but the explanation must recognise the declaration and must not impose an invented invoice-only requirement. Unqualified Pass on the incomplete case using only the new-system wording fails.

For a stronger contradictory-evidence control, evaluate the same incomplete source package with a clearly labelled test-specific contractor declaration that prior wood heat served only about 40% of the home. This is recorded scenario evidence, not a modified source PDF or an instruction to return a particular result. The explanation must identify the conflict with the substantive threshold; it must not return unqualified Pass.

These are focused single-rule model evaluations, not a claim that the entire ingest/production pipeline or the suite regression system was retested. Review the actual output reasons as well as the result labels. Proposed pre-check and training text are assessed against the real document gap and conversations, not by treating them as executable decision rules.

## Commands

Run through the local app container so Rails and the existing Node/blob configuration are used:

```text
docker exec bc-emli-application-sys-app-1 bundle exec rails runner claims_ai_service_ddl/dev_tools/rule_package_audit_evaluation.rb -- --action prepare
docker exec bc-emli-application-sys-app-1 bundle exec rails runner claims_ai_service_ddl/dev_tools/rule_package_audit_evaluation.rb -- --action context --manifest <manifest-path>
docker exec bc-emli-application-sys-app-1 bundle exec rails runner claims_ai_service_ddl/dev_tools/rule_package_audit_evaluation.rb -- --action evaluate --manifest <manifest-path> --split development --repeat 2 --keep-fixtures
docker exec bc-emli-application-sys-app-1 bundle exec rails runner claims_ai_service_ddl/dev_tools/rule_package_audit_evaluation.rb -- --action evaluate --manifest <manifest-path> --split holdout --keep-fixtures
docker exec bc-emli-application-sys-app-1 bundle exec rails runner claims_ai_service_ddl/dev_tools/rule_package_audit_evaluation.rb -- --action candidates --manifest <manifest-path> --keep-fixtures
docker exec bc-emli-application-sys-app-1 bundle exec rails runner claims_ai_service_ddl/dev_tools/rule_package_audit_evaluation.rb -- --action cleanup --manifest <manifest-path>
```

`--cases too_strict,no_change` selects particular cases for repetition. `--repeat` applies to every selected case; use `--cases` when only the key repeat cases are wanted. Each evaluation invocation normally cleans up its owned fixtures; the staged example explicitly retains them until the final cleanup. A crash or forced process termination may bypass ensure, so recover with the manifest's cleanup command. Provider failures remain failures in the artifacts and process exit status; they are never replaced with mock advice.
