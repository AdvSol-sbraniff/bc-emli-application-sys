# Real rule package AI audit — active implementation and evaluation plan

Status: implementation, local verification, real AI evaluation and cleanup completed on 2026-09-18. Remaining proposal-quality and policy-authority limitations are documented below and in the evaluation report. No proposed business rule has been applied.

Follow-up planning: [Background execution with Sidekiq](rule_package_audit_sidekiq_plan.md) proposes durable audit-run tracking and polling independently of the ingest pipeline. That follow-up is planned, not implemented; the completed synchronous implementation below remains the historical record.

## Objective and boundaries

Replace the Rule Improvement Detail / Step 4 mock audit with an authenticated real AI audit of one selected rule against one processed invoice package and its history. Finish planning, implementation, automated checks, actual local AI evaluation and up to three evidence-driven refinement cycles. The user is away and has authorised continuing without phase approvals.

All database experiments are local. Do not change Gold/production, permanent rule seeds, unrelated invoices, or implement an audit-history subsystem. Audit proposals never change a rule. Preserve the existing dirty workspace. Do not rebuild any database: the main claims DDL starts with a destructive schema drop. Automated Rails tests must explicitly use BOTH `RAILS_ENV=test` and `DATABASE_URL=postgres://postgres:password@postgres:5432/app_test`.

## Findings and decisions

- Rails owns authoritative invoice evidence and authenticated admin access. Node owns Azure/OpenAI transport and blob reading. Reuse that boundary.
- Reuse `comparison_deployment_name` per call. It describes an evaluation model already suitable for this work; do not add another model field or change existing comparison behavior.
- Add one editable `rule_audit_system_record` field to `claims.validationgenai_config`, expose it in System Config, and provide a reviewed default. Update rebuild DDL/config seed and a separate additive local patch; execute only the additive patch locally.
- Add `POST /api/claims/admin/reports/rule_improvement/:source_engine/:rule_key/audit` with an invoice ID (and selected version reference if needed), protected by the existing `claims.configuration` admin permission. The server loads all evidence itself; the browser does not submit trusted context or prompts.
- Use a dedicated `/inv/rule-audit` Node endpoint and Rails NodeClient method, preserving `/inv/genai` behavior. Calls are synchronous with bounded provider/request timeouts; the existing app route timeout is 600 seconds. Disable duplicate UI submissions while a request is active and show actionable failures.
- Return four LLM fields: `advice` (required nonempty string), `proposed_rule_prompt`, `proposed_precheck_action`, `proposed_contractor_guidance` (each string or null). Advice can support zero, one or several improvement options. Do not add brittle analytical subfields or force a prompt change. Code rules cannot receive a replacement GenAI prompt.
- Return separate server-generated provenance: selected rule/invoice, evidence coverage/limitations, context digest, attachment manifest/digests, model, diagnostic ID and completion time. This is not AI-authored and must not imply a saved audit history.
- Keep React as the maintained guidance source. Generate a versioned, readable AI guidance reference from the actual process/option/help definitions, with source digests. Rails checks freshness rather than serving silently stale guidance. Include the generated reference as a labelled faux record, separate from the editable system instruction. Document a reproducible export/check command.
- Do not truncate a large package silently. Apply explicit context, attachment-count and attachment-byte limits before inference; reject oversized or inaccessible source files clearly. Record missing evidence where it was never stored. Do not treat unreadable attachments as if they were inspected.

## Evidence contract and provenance

Each faux record is a synthetic user-message container for real data, with a record type, source table(s), identifiers and temporal meaning. It is not a fabricated participant message. Package content is untrusted evidence, never an instruction overriding the task.

1. **Scope and limitations:** selected rule, package/version references, evidence coverage and known gaps.
2. **Human workflow reference:** process steps, seven improvement options, signal interpretation and detailed guidance exported from React.
3. **Rule definitions:** current `genai_rules` or `code_rules`, relevant history, upgrade mappings, pre-check wording, and registry policy source quote. Label the current rule separately from historical snapshots.
4. **Package history:** `invoices` and `invoice_status_transitions`, with actor IDs and timestamps where recorded.
5. **Invoice versions:** all relevant `invoice_versions`, authoritative source identity, raw DI/OCR/page maps, first-class fields, lineitems, located fields, upgrade classifications and complete rulechecks. Mark the selected rule and retain other checks as context. Include complaint codes and free-form comments.
6. **Supporting documents:** `supporting_documents`, source identity, raw OCR/classifier data, located fields and visual findings, with version associations.
7. **Workflow:** package `revision_issues` and original source snapshots, all rounds, requests, responses, role-labelled comments, closure dispositions and comments. Mark selected-rule relevance instead of attributing unrelated issues to it.
8. **Conversations:** `conversation_messages` with requester ID, type, text and version association.
9. **Internal discussion:** `internal_notes` with admin user ID, text and timestamps.
10. **Source attachments:** actual PDF/image bytes resolved from invoice_versions/supporting_documents storage keys. Deduplicate identical source pointers while preserving every document/version occurrence in the manifest. Never depend on ingest log tables as the evidence source.

Known limits: rulechecks lack immutable rule-revision UUIDs, so key/time history matching is inferred; code history does not preserve executable Ruby; complaints lack independent author/time; workflow comments have role but not actor UUID; closure lacks dedicated actor/closed-at; edited notes/messages have no previous-text snapshots. A registry `source_quote` is not an independently fetched full policy PDF. Realworld-checks are represented only where actually documented. Later evidence must not be attributed to an earlier decision.

## Implementation work and ownership

| Work                                                               | Expected files                                                                                       | Owner/status                                 |
| ------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------- | -------------------------------------------- |
| Context builder and evidence/provenance tests                      | `app/services/claims/rule_audits/context_builder.rb`, focused service specs                          | audit_context; implemented and verified      |
| Node strict audit endpoint, transport metadata, limits and tests   | `claims_ai_service/src/**/inv*`, audit helper/spec files; `app/services/claims/genai/node_client.rb` | audit_ai_transport; implemented and verified |
| Audit orchestration, route, authorization/request tests            | `app/services/claims/rule_audits/audit.rb`, reporting controller, routes, request specs              | root                                         |
| Editable system instruction/configuration                          | validation config model/controller/editor, main DDL, config seed, additive dev-tools SQL             | root                                         |
| Shared guidance export and freshness checks                        | guidance exporter, generated reference, Rails guidance loader; existing React process guidance       | root                                         |
| Real audit UI with four output fields                              | package-audits/data, existing Step 4 guide                                                           | root                                         |
| Isolated demo fixtures, evaluation rubrics/scripts and actual runs | `claims_ai_service_ddl/dev_tools/` audit tools, scenario manifest, local output files                | audit_evaluation + root review               |

## Phase gates

- [x] Read bootstrap and inspect repository conventions; no AGENTS.md found in the repository.
- [x] Identify authoritative evidence, existing AI transport, UI, configuration and local demo availability.
- [x] Save this plan before feature implementation or test-data mutation.
- [x] Agree exact builder/transport contracts, size limits and generated-guidance path between implementers.
- [x] Implement backend, configuration, generated guidance and UI; preserve existing behaviors.
- [x] Pass meaningful context, contract, permission, error, regression and browser checks.
- [x] Freeze facts/acceptable findings and the holdout split before the first live audit.
- [x] Prepare reversible local fixtures, verify attachments/history in outbound context, run actual AI calls.
- [x] Independently assess advice and test suggested prompts on problem and correct comparison cases.
- [x] Run held-out and repeated cases; perform at most three refinement cycles if needed.
- [x] Restore temporary state; finish evidence report with results, limitations and runnable commands.

## Detailed testing and evaluation plan

### Automated implementation checks

- Context includes all required source tables, complete reasons/complaints/conversations and original workflow snapshots; selected-rule flags and timestamps prevent cross-rule/temporal confusion.
- Differentiate genuinely absent history/OCR from lookup failures. An unrelated or nonexistent invoice/rule is rejected. Context construction is read-only.
- Attachments originate only from authoritative evidence tables, are deduplicated with occurrences preserved, and fail clearly on unsupported, missing or oversized content.
- Node requires the attachment-capable Responses path, applies strict JSON Schema, checks runtime types/lengths, and rejects refusals/incomplete/invalid output. Check all-null proposal fields and correct provider error mapping. Preserve existing comparison/genai tests.
- Verify source digests and rendered guidance reference are current. Human guidance and AI reference share the same definitions.
- Request tests cover the admin permission boundary, malformed parameters, server-selected context/configuration and safe error responses. No action mutates rule or invoice evidence.
- React checks cover loading, retry, error output, four always-visible output fields, null proposals, code-rule handling, metadata, switching steps and preservation of existing selections.

### Local scenarios: expected findings fixed before calls

Use clones of the four existing demo packages, preserving their original invoices and authoritative document storage references. The local DB currently contains four demo invoices/eight versions. Candidate core case is Demo 1 `ashp_wood_existing_heat_context_present`: distinguish the old wood system from the newly installed heat pump, and use permitted supporting evidence. Demo 4 HPWH is a smaller independent comparison/holdout source. Final scenario facts must be read from documents before fixture assertions are frozen.

| Scenario                       | Deliberate facts/flaw                                                                 | Acceptable substantive findings                                                                        |
| ------------------------------ | ------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| Too strict                     | Require invoice-only evidence despite an accepted supporting-document alternative     | Identify the excess restriction; propose a bounded prompt correction preserving the actual requirement |
| Missed genuine problem         | Weaken/omit a documented required condition and retain a misleading Pass              | Identify the missed condition using supplied evidence; propose restoring it without inventing policy   |
| Unclear corrective instruction | Correct finding but vague initial reason, confused response and avoidable extra round | Preserve decision; name the concrete next action suitable for WFM prepopulation                        |
| Pre-check wording              | Generic pre-check plus recorded confusion before submission                           | Propose useful upfront wording; distinguish it from the generated reason and decision logic            |
| Guidance only                  | Correct rule and ordinary successful correction due to preparation misunderstanding   | Keep valid rule behavior; propose contractor preparation/training wording                              |
| Multiple improvements          | Independent decision/presentation or pre-check/preparation defects with evidence      | Support complementary options, explain their separate evidence and relevant nullable proposals         |
| No change                      | Consistent correct rule, evidence and clear instructions                              | Explain why no material change is justified; do not invent a defect merely to fill proposal fields     |
| Uncertainty                    | Missing policy/old evidence or conflicting contemporaneous statements                 | Explicitly identify the gap, avoid confident causation and unsafe replacement wording                  |

Reserve at least two scenarios, including one different demo/rule, as holdouts before tuning; do not inspect their live results while refining initial instructions. Repeat important cases to assess variability. Rubrics judge factual support, attribution, temporal accuracy, appropriate option(s), completeness of replacement wording and absence of invented policy—not exact phrasing. A well-supported alternative is acceptable; explain any rubric correction openly.

### Real-call execution and candidate validation

Scripts must record a fixture manifest and original configuration before mutations, use only identifiable local records, and restore temporary rule/system configuration in an ensure/finally path. Prefer cloned rules over modifying existing demo rules. Preserve enough output locally to inspect inputs and results without committing credentials or unnecessary package content.

For every live audit record: scenario ID, rule/invoice/version references, model and system/guidance versions, context record types/digest, attached source filenames/bytes/digests, actual four-field response, timing/error, and rubric assessment. Context-level evidence plus transport instrumentation must establish that documents and conversations were sent.

Run proposed prompt wording through actual rule evaluation on the problem package and a correct/control package using the same evidence and explicit expected outcomes. A useful-sounding proposal does not count as verified improvement. Report unchanged/worsened results separately. For pre-check/guidance proposals, evaluate whether wording resolves the preparation task without changing eligibility or inventing requirements.

### Refinement rules

Diagnose failures as source/context problems, implementation defects, instruction ambiguity, provider variability, or wrong fixture expectations. Fix the cause, rerun affected checks and then the holdouts/repeats. Maximum three refinement cycles after initial evaluation; never weaken a rubric just to pass, and never change policy based on model preference. Update React guidance only for justified corrections, then regenerate the shared reference. Record remaining failures honestly.

## Execution log and final evidence

- 2026-09-18: read bootstrap/rebuild instructions, found no repository AGENTS.md; preserved existing dirty files. All local app/Node/DB containers are running.
- 2026-09-18: three independent investigations completed/in progress. Confirmed authoritative PDF transport is already available; existing generic JSON parsing alone is insufficient for this endpoint. Existing Node comparison/general-call focused baseline: 9 passing tests.
- Implementation commands, scenario manifest, actual results, refinement decisions and restoration verification will be appended here as they occur.
- Added only `rule_audit_system_record` using `dev_tools/apply_rule_package_audit_local.sql` against local app_development/app_test. Rebuild DDL includes it; the config seed preserves overrides and documents the maintained application default rather than duplicating prompt text in SQL.
- Shared reference: `node scripts/export-rule-audit-guidance.cjs` writes `config/claims/rule_improvement_guidance.json` from actual React definitions/rendered help; `--check` and Rails source-digest checks detect stale guidance. No invented measured metric values are exported.
- Implemented exact transport limits: 1,500,000 context bytes, 24 source files, 20 MiB per file, 35 MiB total, 240-second default/270-second maximum provider budget, at most two provider attempts. Responses uses `store:false` and truncation disabled. Actual source bytes/digests are checked against stored historical identity when available, with ETag pinning; unknown stored identity is disclosed.
- Automated milestones: initial combined Rails audit/config/request/client suite 36 examples passed; builder subsequently gained four file-identity examples. Node audit plus existing focused behavior tests 50 passed; Node build/lint and focused frontend TypeScript/lint passed. A timestamp-sensitive test fixture was corrected to pin the PostgreSQL history boundary; production matching logic was unchanged.
- Fixed protocol and commands: `claims_ai_service_documentation/rule_package_audit_evaluation.md`. Evolving actual results: `claims_ai_service_documentation/rule_package_audit_evaluation_results.md`. Current isolated fixture manifest: `tmp/rule-package-audit-evaluation/20260918T200021_44ea3399/manifest.json` (recoverable until final cleanup).
- First three development live audits succeeded with actual source documents and stored history. Root independently read the advice/proposals; substantive findings matched the declared defects. First call supplied 7 files / 748,014 bytes and 17 context records, 139,620 input tokens, model gpt-5.6-terra. These are limited-sample observations, not a reliability claim.
- Two subsequent calls encountered Node watch reload during an integrity improvement (EOF/connection refused), not a model-quality failure. Calls paused; transport changes were frozen and health verified before retry. No system-record tuning yet. Candidate-test instructions were corrected before candidate calls to remove coaching of the known old/new-system flaw and use the configured upgrade-analysis model.
- All five development cases subsequently returned actual advice. Independent review found a material wording risk in the pre-check proposal: it could make a separate supporting record mandatory even when the invoice itself supplies acceptable evidence. **Refinement cycle 1** adds a general instruction preserving accepted evidence alternatives in every proposed field, and requiring explicit handling of unresolved missing-evidence versus violation severity. Matching human guidance was updated and regenerated. Original scenario rubrics are unchanged; held-out responses remain unseen during this refinement.
- Expanded Rails audit/configuration/reporting/client regression run: **61 examples, 0 failures** against explicit `app_test`. Focused frontend TypeScript and ESLint checks passed after the latest UI changes. Browser interaction verification and the candidate-prompt experiments remain in progress.
- Independent deployment review confirmed that the Rails image retains generated guidance plus its React/exporter source files, and current route/Node/Rails/browser timeouts are compatible. The disabled legacy CBC proxy has a shorter read timeout; enabling that proxy would require reviewing its timeout separately. No deployment settings were changed.
- Browser verification: **10 checks passed**, no JavaScript exceptions, using the actual React components with intercepted browser transport replaying a real audit response. Covered four readonly fields, exact POST identifiers/credentials, duplicate/loading protection, null proposals, stale-output clearing, failure/retry, malformed responses, preserved results when switching steps, configuration-save semantics and a 390px viewport. A real narrow-screen overflow was fixed by containing the visually hidden table heading in a positioned scrolling wrapper. Root visually inspected desktop/mobile screenshots. This browser replay is separate from the actual backend AI calls.
- Browser artifacts: `C:/Users/bstephen/AppData/Local/Temp/codex-rule-audit-preview/` contains `audit-real-ui-results.json`, the build/check scripts and desktop/mobile/error/config screenshots. The owned headless browser was closed after testing.
- The 3 untouched holdouts met the core rubrics: multiple complementary proposals, all-null no-change proposals, and explicit uncertainty for conflicting evidence. Repeated strict/no-change audits retained their main conclusions; proposed wording varied. Candidate execution checks are being run for every scenario that proposed a rule prompt, including the multiple-improvement holdout.

## Final outcome

- The real Step 4 audit replaces the mock. It reads authoritative source documents and recorded package history, includes the shared human guidance, and displays flexible advice plus three nullable wording proposals. Nothing applies a proposal or stores audit history automatically.
- One new nullable configuration column was installed locally. Existing comparison model selection is reused unchanged. The editable system record remains null in the local DB and follows the maintained default; unrelated config saves do not freeze that default accidentally.
- Implementation checks: **61 Rails examples, 50 Node tests, 10 browser interaction checks passed**. Node build/focused lint, frontend TypeScript/ESLint/formatting, shared-guidance freshness and the evaluation runner's syntax check passed. The six audit request examples were rerun successfully after the final timeout-rescue cleanup. New audit services pass RuboCop; five existing reporting-controller style offenses outside this feature's additions remain. Browser checks replayed actual AI output through intercepted fetch; real backend AI evaluation was separate.
- Actual AI evidence: **13 successful package audits** across all eight planned scenarios, with held-out cases and repetitions; **24 actual original/proposed prompt checks** across complete, missing-proof and contradictory-evidence controls. Three service-reload interruptions were retained as failed/interrupted attempts and successfully retried; no fake responses replaced them.
- Strict and combined-defect prompts changed `Fail / Fail / Fail` to `Pass / Fail / Fail`; the missed-problem prompt changed `Pass / Pass / Pass` to `Pass / Warn / Fail`. Corrective-instruction changes preserved `Pass / Warn / Fail` while replacing a vague reason with a concrete next action. Root and an independent reviewer inspected reasons and source attribution as well as labels.
- One general refinement preserved alternative evidence routes and exposed unresolved result-severity dependencies. No held-out response was used to tune instructions. The frozen protocol was not weakened.
- Cleanup completed **2026-09-18 20:22:14 UTC**. The manifest records `original_rules_unchanged: true`; independent verification found four original invoices/eight versions and no owned invoice/version/rule/history remnants. Source blobs, original rules, permanent rule seeds, Gold and production were not changed. Detailed local artifacts remain under the ignored manifest directory for inspection.

### Remaining limitations and next investigation

This is a deliberately small two-demo-source evaluation, not proof of production reliability. Two-version contexts reached approximately 225,000 input tokens; explicit limits reject oversized packages without silent omissions. Historical rule identity is inferred, and missing historical actors/snapshots remain disclosed.

Proposals still need review. One intermediate prompt relied on an unspecified configured outcome; its later repeated draft was concrete. A pre-check sentence could blur declaration versus independent certification. The combined-defect candidate reason called a declaration "approved" without supplied approval evidence, and another reason expanded a selected-rule conclusion to overall eligibility. Those are unresolved wording/authority limitations, despite the useful control outcomes. The next investigation is to confirm the actual evidence standard and severity with the policy owner, make the selected candidate self-contained, and test it in the application's full rule/regression pipeline with a representative suite. Do not invent approval or change policy merely to make these examples pass.

Full scenario observations, exact candidate matrices, refinement rationale, limitations and cleanup evidence are recorded in `claims_ai_service_documentation/rule_package_audit_evaluation_results.md`. Preparation and test commands remain in `claims_ai_service_documentation/rule_package_audit_evaluation.md`.

### Follow-up: authorised Gold schema update

On 2026-09-18, after the local work above, the user explicitly requested the additive Gold change and instructed that testing and image deployment would be handled personally. Applied and committed `ALTER TABLE claims.validationgenai_config ADD COLUMN IF NOT EXISTS rule_audit_system_record text NULL` and its matching column comment to Gold namespace `ce8baa-dev`, database `hesp-crunchydb`. The transaction returned `ALTER TABLE`, `COMMENT`, and `COMMIT` successfully. No tests or image deployment were performed for this follow-up. The new nullable field uses the application default when the new image is deployed.

## Configuration and maintenance commands

- Local additive installation, already applied to development and test: `docker exec bc-emli-application-sys-postgres-1 psql -U postgres -d app_development -f /workspace/claims_ai_service_ddl/dev_tools/apply_rule_package_audit_local.sql` (repeat with `-d app_test` for tests). This helper deliberately rejects other database names. Do not run the destructive rebuild script to add this field.
- Deployments need the nullable `claims.validationgenai_config.rule_audit_system_record` column before enabling the feature. Refresh Rails schema caches/processes after installing a new column. No Gold or production migration has been performed.
- System Config → Rule Audit edits the system instruction. Blank/null follows `config/prompts/rule_package_audit_system.txt`. Unrelated config saves leave the audit override untouched. The Comparison and rule audit model remains the existing `comparison_deployment_name`; source-document audits require the service's Responses configuration.
- After changing process steps, improvement-option guidance or the shared help, run `npm run rule-audit:guidance`, then `npm run rule-audit:guidance:check`. Commit the generated `config/claims/rule_improvement_guidance.json` with its maintained sources. Stale references fail clearly instead of silently sending old guidance.
- Follow the preparation/evaluation/cleanup commands in `claims_ai_service_documentation/rule_package_audit_evaluation.md`. Preserve the ignored manifest until cleanup has completed; it owns the exact local fixture IDs and captures original rule fingerprints. Outputs contain detailed local evidence and remain under ignored `tmp`.
