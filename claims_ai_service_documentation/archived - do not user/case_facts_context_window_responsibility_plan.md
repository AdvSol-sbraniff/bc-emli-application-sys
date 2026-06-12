# Case Facts And Context Window Responsibility Plan

Status: implemented locally

Purpose: separate three responsibilities that are currently too easy to confuse in the claims AI validation runtime: pre-existing database fact snapshotting, evidence persistence by pipeline step, and context-window assembly for GenAI calls.

## 1. Problem

The current runtime uses the term `case_facts` for more than one concept.

This creates confusion because three separate responsibilities are being discussed as if they were one thing:

```text
1. Snapshot pre-existing database facts into evidence tables.
2. Persist evidence produced by each pipeline step.
3. Assemble the actual context_window_json used by each GenAI call.
```

The current code does not call GenAI inside the `case_facts` step. However, the `case_facts` step currently builds a broad case-facts object that includes supporting-document summaries and then later GenAI steps include that object in their context windows.

That makes `case_facts` feel like a context-window assembly step, even though the final `context_window_json` is still created inside the GenAI call step.

## 2. Target Responsibility Boundaries

### 2.1 Pre-Existing DB Fact Snapshot

This is the original intended role of `case_facts`.

It should read stable application/database context such as:

- Contractor business name and address.
- Participant/user facts.
- Eligibility-code database row.
- Eligibility approval/expiry window.
- Invoice/session metadata that exists outside AI extraction.
- Classifier-located eligibility code if needed for DB lookup.

It should persist those facts into evidence rows such as:

```text
claims.invoice_version_located_fields
  source_engine = 'code'
```

This step should not build the final context window for GenAI.

Possible clearer step name:

```text
case_database_facts
```

or:

```text
pre_existing_case_facts
```

### 2.2 Step-Owned Evidence Persistence

Each pipeline step should persist the evidence it creates.

Examples:

```text
triage_classifier
  persists document_kind, supporting_document_type_id, classifier payload,
  invoice_version_upgrade_types, classifier located fields/product references

supporting_document_extraction
  persists supporting_document_located_fields and supporting_document_visual_findings

supporting_document_group_extraction
  persists supporting_document_group_located_fields and optional group visual findings

product_lookup_enrichment
  persists product-list match IDs and product-match located fields

genai_common / genai_upgrade
  persists GenAI located fields, rulechecks, upgrade-type results, and raw model output

code_common / code_upgrade
  persists deterministic rulechecks and any deterministic located fields
```

Rule:

```text
The step that creates evidence owns writing that evidence.
```

### 2.3 Just-In-Time Context Window Assembly

The actual `context_window_json` should be created inside the step that calls GenAI.

Examples:

```text
triage_classifier
  builds classifier context_window_json

supporting_document_extraction
  builds supporting-document extraction context_window_json

supporting_document_group_extraction
  builds group extraction context_window_json

genai_common
  builds common validation context_window_json

genai_upgrade
  builds upgrade validation context_window_json
```

Each GenAI step should:

1. Read already-persisted evidence and registry/configuration rows.
2. Build its own `context_window_json` just in time.
3. Store that exact context window on its own `claims.ingest_step_runs.context_window_json`.
4. Call GenAI.
5. Persist the output evidence it owns.

Rule:

```text
No non-GenAI step should create the final context window for a later GenAI step.
```

## 3. Current State Summary

Current `case_facts` behavior is mixed.

It currently:

- Builds `esp_database_values`.
- Persists DB-derived located fields with `source_engine = 'code'`.
- Persists classifier-derived located fields with `source_engine = 'classifier'`.
- Builds a supporting-document summary from existing supporting-document rows.
- Stores the resulting broad `case_facts` object on the `case_facts` step row.

It does not:

- Call GenAI.
- Persist supporting-document extraction evidence.
- Persist GenAI rulecheck evidence.
- Persist product-list lookup evidence.

The issue is not that `case_facts` is calling GenAI. It is not.

The issue is that `case_facts` currently acts as both:

```text
pre-existing DB fact snapshotter
shared validation context packet builder
```

Those should be separated.

## 4. Proposed Refactor

### 4.1 Rename Or Narrow The Existing Step

Option A: Keep step type `case_facts`, but narrow it.

```text
case_facts
  only snapshots pre-existing DB facts and classifier-derived lookup facts
```

Option B: Add a clearer step type and retire old meaning over time.

```text
pre_existing_case_facts
```

Recommendation: keep `case_facts` for now to reduce churn, but rewrite its description and implementation so it only snapshots pre-existing case facts.

### 4.2 Move Supporting-Document Context Assembly Out Of Case Facts

The supporting-document summary should not be built and snapshotted by `case_facts`.

Instead, `genai_common` and `genai_upgrade` should build their context windows just in time by reading:

- `claims.supporting_documents`
- `claims.supporting_document_located_fields`
- `claims.supporting_document_visual_findings`
- future `claims.supporting_document_groups`
- future `claims.supporting_document_group_located_fields`

The context-window builder can still be a helper service, but it should be invoked by the GenAI step that needs the context.

### 4.3 Keep Pre-Existing DB Located Fields In Case Facts

It is still reasonable for `case_facts` to write these rows:

```text
source_engine = 'code'
field_key = contractors.business_name
field_key = users_eligibilitycodes.eligibility_code
field_key = users_eligibilitycodes.approved_at
field_key = users_eligibilitycodes.expires_at
```

These are not AI outputs. They are deterministic case/database facts.

### 4.4 Move Classifier Located Fields To Classifier Step

Classifier-located values should ideally be persisted by `triage_classifier`, not by `case_facts`.

Examples:

```text
source_engine = 'classifier'
field_key = classifier.eligibility_code
field_key = classifier.ahri_reference
field_key = classifier.detected_upgrade_types
```

Current implementation persists these during the `case_facts` step because that is where invoice version context is available.

Refactor target:

- When invoice version is created/resolved, apply classifier located fields then.
- Or add a dedicated deterministic step after invoice resolution:

```text
classifier_fact_snapshot
```

Recommendation: add this to the future refactor, but do not block supporting-document grouping on it.

## 5. Proposed Pipeline Description

Cleaner conceptual pipeline:

```text
upload_package_stage
ocr_read(s)
triage_classifier(s)
ocr_invoice
supporting_document_extraction(s)
supporting_document_group_extraction(s)
case_facts
product_lookup_enrichment
genai_common
genai_upgrade(s)
code_common
code_upgrade
aggregate_advice
```

Responsibility notes:

```text
case_facts
  no GenAI
  snapshots pre-existing DB facts into invoice_version_located_fields
  does not build final validation context windows

genai_common / genai_upgrade
  build their own context_window_json just in time
  read all already-persisted evidence needed for validation
```

## 6. Context Window Builder Shape

The codebase can still have helper methods/services for building context-window sections.

The important boundary is where they are called.

Preferred:

```text
RunGenaiJob#run_genai_common_step!
  -> build_common_context_window!
  -> call GenAI
  -> persist common GenAI evidence

RunGenaiJob#run_genai_upgrade_step!
  -> build_upgrade_context_window!
  -> call GenAI
  -> persist upgrade GenAI evidence
```

Avoid:

```text
case_facts
  -> prebuilds one large reusable context packet for later GenAI steps
```

## 7. Data Model Impact

No immediate table change is required just to separate responsibilities.

The refactor mainly changes:

- Step meaning.
- Service boundaries.
- Where `context_window_json` is assembled.
- Where classifier located fields are persisted.

However, this plan should coordinate with the supporting-document grouping plan because future context windows should read group-level evidence from:

```text
claims.supporting_document_groups
claims.supporting_document_group_located_fields
```

## 8. Test Plan

Regression package:

```text
claims_ai_service_documentation/Test Data/Heath & Safety/test006
```

Test expectations after refactor:

- `case_facts` step succeeds without calling GenAI.
- `case_facts` persists only pre-existing DB/code facts.
- Supporting-document file-level facts are persisted by `supporting_document_extraction`.
- Supporting-document group-level facts are persisted by `supporting_document_group_extraction`.
- `genai_common` and `genai_upgrade` each store their own complete `context_window_json`.
- Context windows include supporting-document and group evidence by reading persisted evidence tables just in time.

## 9. Open Questions

- The existing step type `case_facts` is preserved for now, but its meaning is narrowed to pre-existing database/code facts.
- Classifier located fields are persisted when the classifier result is applied to the invoice version, through `Claims::InvoiceVersionUpgradeTypes::ApplyClassifierResult`.
- Product lookup remains after `case_facts` and before `genai_common` / `genai_upgrade`, so product enrichment is available in the validation context window.
- `case_facts` continues to store a small JSON audit payload, but that payload is now limited to `esp_database_values` and the classifier eligibility code used for DB lookup.
- Existing historical step rows may still contain `case_facts.genai_results_json.case_facts.supporting_document_summary`; new runs should not.

## 10. Local Implementation Notes

Implemented boundary changes:

- `Claims::GenaiCaseFacts::Build.build_shared_context` now returns only `esp_database_values`.
- `case_facts` no longer builds or snapshots supporting-document summaries.
- `case_facts` no longer persists classifier located fields.
- `Claims::InvoiceVersionUpgradeTypes::ApplyClassifierResult` persists classifier located fields with `source_engine = 'classifier'`.
- `RunGenaiJob#run_genai_ruleset!` passes the claim-level invoice into `build_contextwindowjson`.
- `build_contextwindowjson` builds supporting-document possible/attached records just in time from persisted supporting-document evidence.

The context-window record labels remain stable:

```text
User record 2: supporting documents possible
User record 3: supporting documents actually attached
User record 4: pre-existing database values
User record 5: classifier-located key fields
User record 6: download product enrichment
```
