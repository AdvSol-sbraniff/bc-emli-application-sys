# Rule Improvement Reporting Plan

Date: 2026-09-08

Status: implemented locally; ready for admin user acceptance

## 1. Product purpose

The feature gives administrators two deliberately different screens:

1. **Rule Improvement Report** answers: **Which GenAI or code rule should I investigate next?**
2. **Rule Improvement Detail** answers: **What does the evidence say, and is the likely action rule tuning, clearer contractor guidance/training, or continued observation?**

The screens are investigation aids, not an automated verdict system. Complaints and candidate signals identify records worth reviewing. They do not prove that a rule was wrong or that a contractor needs training.

## 2. Scope decisions

- Report both GenAI and code rules.
- Show the engine type explicitly; never imply that a database edit versions executable source code.
- Do not divide, group, or filter the report by upgrade type.
- Measure the current effective prompt version for GenAI rules.
- Measure a code rule from the creation of its distinct code-rule key and record.
- Use GenAI history to reconstruct prompt/configuration periods. Use code-rule history only to show database configuration changes.
- Add no rule-improvement action table for the MVP.
- Keep rule editing in the existing validation-rule editor.
- Keep the complaint interaction beside the exact rulecheck reason in the Admin PDF Viewer, outside Workflow Management.

## 3. Persisted reason feedback

Add two nullable fields directly to the canonical `claims.invoice_version_rulechecks` table definition:

- `reason_complaint_code`
- `reason_complaint_text`

Do not put an `ALTER TABLE` statement in a create-schema file. An interactive local database alteration may be used to update the already-running local database, while the clean Friday rebuild obtains the fields from the canonical `CREATE TABLE` definition.

The complaint belongs to one immutable invoice-version rulecheck. Saving it must not rerun analysis, replace a version, create a workflow issue, or change the rule result or generated reason.

Allowed complaint categories:

| Stored value                      | Admin label                              |
| --------------------------------- | ---------------------------------------- |
| `unclear_or_confusing`            | Difficult to understand                  |
| `too_vague`                       | Not specific enough                      |
| `missing_evidence_explanation`    | Does not identify the relevant evidence  |
| `incorrect_evidence_or_reasoning` | Contains incorrect evidence or reasoning |
| `likely_causes_unhelpful`         | Likely causes are not useful             |
| `required_action_unclear`         | Does not explain the next step           |
| `irrelevant_or_duplicative`       | Irrelevant or duplicates another finding |
| `too_verbose_or_repetitive`       | Too long or repetitive                   |
| `other`                           | Other                                    |

These categories concern reason quality. False positive and false negative are derived investigation signals and are not complaint values.

## 4. Effective rule-period boundary

For a GenAI rule, define the current period start as:

```text
latest genai_rule_history.history_created_at for the rule
or
genai_rules.created_at when no history record exists
```

Only rulechecks with `created_at >= current period start` feed the overview and the current-version tabs. This prevents evidence produced under an earlier prompt or rule definition from being attributed to the current one.

The MVP infers the logical rule through the immutable `source_engine = genai` and `rule_key`; rulechecks do not store a physical rule-revision UUID. Upgrade-mapping changes are ignored when defining reporting periods.

For a code rule, define the measurement start as `code_rules.created_at`. The database record contains registry and administrative configuration; executable rule logic remains in source code. A behaviour-changing code release must therefore create a new immutable `code_rule_key` and `code_rules` record, and the code must emit that new key. The prior record and rulechecks remain available for historical investigation. The application enforces key uniqueness and immutability but does not detect source-code changes or enforce this release practice.

## 5. Metric meanings

- **Invoice versions assessed:** distinct invoice-version IDs checked during the rule's measurement period. This is the sample-size context for every other count.
- **Complaints:** current-period rulechecks with a complaint category.
- **False-positive candidate:** current-period `warn` or `fail` whose rule workflow issue closed as `closed_no_contractor_action_required`.
- **False-negative candidate:** current-period `pass` or `info` followed by a rule workflow issue that was not closed as no-action-required or withdrawn.
- **Total contractor rounds:** sum of distinct sent revision rounds linked to this rule's workflow issues.
- **Invoice versions with follow-up:** distinct current-period invoice versions linked to at least one rule workflow issue.
- **Workflow issues:** distinct rule workflow issues linked to the current-period rulechecks.
- **Closure outcome:** current issue state or terminal close type, used to interpret why follow-up occurred and how it ended.

All candidates remain directional. The administrator must inspect the exact invoice, reason, later workflow, and disposition comment.

## 6. Screen 1 — Rule Improvement Report

Route:

```text
/reports-rule-improvement
```

### Purpose

This is a triage queue, not a dashboard. It should let an administrator quickly choose one rule for investigation without processing multiple cards, charts, or competing sections.

### Layout

- Page question: `Which rule should I investigate next?`
- One bordered, server-paginated grid.
- Search by rule display name or stable key.
- One sort selector.
- Refresh action.
- No summary cards, metric lens, chart, upgrade filter, source-engine filter, or generic `Open` column.

### Grid columns

1. Rule display name and stable key.
2. Type (`GenAI` or `Code`).
3. Metrics-since date: latest prompt/configuration version for GenAI; record creation for code.
4. Invoice versions assessed.
5. Complaints.
6. False-positive candidates.
7. False-negative candidates.
8. Contractor rounds, with the average shown beneath.
9. Row-navigation chevron.

The default sort is most complaints. Other sorts rank false-positive candidates, false-negative candidates, contractor rounds, sample size, recently changed rules, or rule name.

Selecting a row opens the full detail screen. There is no detail drawer.

## 7. Screen 2 — Rule Improvement Detail

Route:

```text
/reports-rule-improvement/:sourceEngine/:ruleKey
```

### Persistent header

- Back to rules.
- Rule display name and stable key.
- GenAI/Code and enabled/disabled badges.
- Measurement start date and invoice-version sample size.
- For code rules, a prominent explanation that executable logic is source-controlled, configuration history is not code history, and behaviour changes require a new key and record.
- Top-level `How to use this report` help action.
- Link to edit the current rule in the existing editor.
- Full-width content area so evidence tables and charts can use the available screen.
- No enclosing card or border around the complete tab system.
- Fitted line tabs matching `Versions History Inspection`: a two-pixel grey baseline and a four-pixel dark underline on the selected tab.

### Seven tabs

#### 1. Rule history

Purpose: determine what changed and whether an observed pattern belongs to the current definition.

- One row per reconstructed effective period.
- Effective start/end dates.
- Invoice versions, complaints, candidate counts, and rounds for each period.
- Saved milestones with before/after field values.
- Causation warning: a count changing after a rule edit may reflect the edit or a different case mix.
- A code rule has one implementation period per key/record. Its saved milestones are labelled as database configuration changes and do not reset or version executable-code metrics.

#### 2. Complaints

Purpose: identify whether the result may be accurate but the written reason is unhelpful.

- Vertical complaint-category chart in a fixed order, always showing all categories including zeroes.
- Exact count above every column and a total complaint count in the chart header.
- Short wrapped chart labels, with the complete accessible label retained for each column.
- Current-period complaint records only.
- Exact generated reason, complaint category, free text, invoice/version link, and workflow outcome.

#### 3. False-positive candidates

Purpose: inspect warnings or failures that apparently required no contractor action.

- Explanatory notice that the signal is not proof.
- Current-period candidate record grid.
- Exact reason and disposition comment.

A candidate may be fine when acceptable evidence existed elsewhere, the admin had a legitimate case-specific reason for requiring no action, or the closure type was used imprecisely. It is more concerning when the same rule repeatedly fails records where its evidence is present or the rule does not apply.

#### 4. False-negative candidates

Purpose: inspect passing or informational checks followed by substantive rule workflow.

- Explanatory notice that later workflow may be unrelated.
- Current-period candidate record grid.
- Exact reason, workflow outcome, and disposition comment.

A candidate may be fine when the later issue concerned another requirement or was precautionary. It is more concerning when admins repeatedly open issues for the exact defect the rule was designed to catch.

#### 5. Contractor follow-up

Purpose: identify opportunities for clearer contractor-facing documentation or training and distinguish them from difficult or overly broad rules.

- A prominent information notice explains that rounds measure effort rather than proving poor contractor performance.
- Invoice versions with follow-up.
- Total rounds.
- Average rounds among issues with a sent round.
- Current-period workflow evidence grid.

Examples of contractor guidance/training opportunities include repeatedly uploading the correct document under the wrong name, omitting the same page, putting a model number in the wrong field, or requiring several exchanges to correct the same otherwise-valid problem.

#### 6. Requests and responses

Purpose: show how administrators and contractors actually used the controlled workflow choices before an issue closed.

- Two vertical charts appear together: `Admin requests` and `Contractor responses`.
- Every allowed pull-down value remains visible, including zero-count values.
- Admin choices count only sent rounds; unsent draft requests are excluded.
- Contractor choices count submitted responses belonging to sent rounds.
- Each pull-down selection is a usage event. An issue with several rounds can therefore contribute several selections.
- The request and response totals need not match, and bars in the two charts are not treated as one-to-one pairs.

The patterns help distinguish a valid recurring omission from unclear guidance, an impractical evidence requirement, or a communication mismatch. For example, repeated supporting-document requests followed by matching uploads suggest a preventable submission omission; repeated explanation requests followed by `Unable to resolve` require investigation of the requirement, evidence availability, and rule design.

#### 7. Closure outcomes

Purpose: explain how rule-related follow-up ended and help distinguish contractor guidance opportunities from rule, policy, and edge-case problems.

- Prominent guidance explaining how to interpret the closure types without treating them as proof.
- Vertical chart in a fixed order that always shows the five terminal outcomes—no action required, corrected documentation, attestation, exception, and withdrawn—including zero values.
- Exact count above every column and total closed-issue count in the chart header.
- Pending-review and open issue counts are explicitly excluded from the chart and reported separately because they do not have outcomes yet.

Closure outcomes make the round count interpretable:

- **Corrected documentation:** the request was actionable; recurrence may justify clearer examples or training.
- **Attestation:** required information may be difficult to document.
- **Exception:** a recurring edge case may not be handled well by the current rule or policy.
- **No action required:** possible over-triggering or inconsistent administration.
- **Withdrawn:** useful operational context, but not proof that the rule was wrong.
- **Open/pending:** excluded from the closure graph because the outcome is not known yet.

## 8. Help content and decision guidance

The help drawer must stay optional so the main screen remains calm. It explains the current seven-tab design, defines the main counts, provides a practical investigation sequence, and includes worked examples. It starts with four possible admin decisions:

1. **Tune the rule** when several records expose the same incorrect trigger, missed defect, or applicability problem.
2. **Tune the written reason** when the result is correct but the evidence citation, explanation, likely cause, or required action is unhelpful.
3. **Improve contractor instructions or training** when the rule is accurate but contractors repeatedly make the same correctable error or need several exchanges.
4. **Keep observing** when the sample is small, examples conflict, or later workflow is unrelated.

The help must repeat that a complaint or candidate is evidence, not an automatic verdict. Administrators should review several exact invoice records before editing a rule.

## 9. Reporting read model and services

`claims.v_rule_improvement_reporting` remains a flattened, read-only view with one row per rulecheck. It joins the exact invoice version, contractor, reason complaint, optional rule issue, disposition, and pre-aggregated sent rounds without multiplying rulechecks through issue-comment joins.

The reporting service layer owns:

- GenAI prompt-period and code-implementation-record scoping;
- rule-grid rollups and sorting;
- complaint, false-positive, false-negative, and contractor-follow-up evidence queries;
- complaint, workflow request/response, closure, and round breakdowns;
- reconstruction of rule-history periods and saved-change diffs.

The controller only validates parameters, authorizes `claims.configuration`, paginates, and serializes.

## 10. API surface

```text
GET /api/claims/admin/reports/rule_improvement
GET /api/claims/admin/reports/rule_improvement/:sourceEngine/:ruleKey
GET /api/claims/admin/reports/rule_improvement/:sourceEngine/:ruleKey/timeline
GET /api/claims/admin/reports/rule_improvement/:sourceEngine/:ruleKey/evidence
PATCH /api/claims/admin/invoice_version_rulechecks/:id/reason_complaint
```

Evidence types used by the detail tabs:

- `complaints`
- `false_positives`
- `false_negatives`
- `contractor_follow_up`

## 11. Verification requirements

- Complaint save, replace, validation, and clear behavior.
- Complaint saving changes no invoice version, issue, or rule result.
- Current-period rollups exclude rulechecks before the latest history milestone.
- Overview returns both GenAI and code rules with explicit engine types.
- GenAI metrics reset at the latest history milestone; code metrics begin at the code-rule record creation time and are not reset by database configuration edits.
- A code-rule warning/failure closed with no contractor action appears as a false-positive candidate.
- Counts are not split by upgrade type.
- Invoice sample, follow-up invoice count, complaints, both candidate types, total rounds, and average rounds are correct.
- Detail breakdowns and all four evidence endpoints use the same current-period boundary.
- History tab retains prior-period metrics.
- Multiple comments in one sent round do not multiply the round count.
- Frontend ESLint and production build pass.
- Browser verification covers the reports menu, overview columns, help drawer, complaint persistence, all seven detail tabs, and exact evidence links.
- No Gold, shared environment, or external service is changed.

## 12. Local acceptance walkthrough

1. Sign in locally as an administrator.
2. Open `Menu > Reports > Rule Improvement Report`.
3. Confirm the overview contains GenAI and Code rows and the nine decision/navigation columns.
4. Sort by complaints, candidate counts, and contractor rounds.
5. Open a rule and confirm the page states the current effective date and sample size.
6. Open Help and review the tune/train/observe guidance and examples.
7. Inspect all seven tabs.
8. Follow an evidence link to the exact invoice version.
9. Confirm the reason complaint in the Admin PDF Viewer matches the complaint tab.
10. Return to the report and confirm the prior search, sort, and page are restored.

## 13. Implementation record

Implemented locally on 2026-09-08/09:

- reason complaint columns, validation, narrow PATCH API, and Admin PDF Viewer modal;
- read-only reporting view with GenAI prompt-period and code implementation-record scope;
- simplified overview grid;
- seven-tab detail page;
- optional help drawer with candidate, training, closure, and decision examples;
- existing history reconstruction without a new history/action table;
- reports navigation and exact invoice/rule-editor links;
- four local demo packages with representative complaint data;
- focused request/service regression tests, frontend lint/build, and browser acceptance automation.

Interactive admin review remains the final acceptance step.
