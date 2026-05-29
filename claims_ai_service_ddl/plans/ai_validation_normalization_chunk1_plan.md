# AI Validation Normalization Chunk 1 Plan

Date: 2026-05-27

Status: largely implemented locally. Schema, seed, API, UI, runtime cleanup, and plan reconciliation now exist. The remaining work has mostly moved into publish/runtime-composer follow-on slices and optional shared-row UX polish.

## Purpose

Define the first implementation chunk for the validation-admin refactor in a way that is:

- testable
- low-risk to existing runtime adjudication
- small enough to ship before supplement/session redesign
- aligned with the newer decisions made after the broader refactor plans

This chunk is the normalization-and-admin-screen slice.

## Role Of This Document

Use this document as:

- the authoritative plan for the chunk-1 admin/config slice
- the place to track what is done versus still open for that slice

Do not use this document as the runtime-execution refactor plan.

That work is now split into:

- `claims_ai_service_ddl/plans/ai_validation_runtime_refactor_plan.md`

## Current Status Snapshot

Done locally:

- normalized GenAI active tables created
- `code_located_fields` table created
- history tables created
- normalized GenAI seed/backfill generated and loaded
- taxonomy-first validation admin screen created
- portal -> taxonomy editor UX created
- typed record editors split by record kind
- `Validation Prompt Config` portal entry restored
- `Supporting Document Types` portal entry and CRUD screen created
- `code_located_fields.enabled` runtime omission behavior implemented
- `classifier.eligibility_code` removed from the code-located-field concept/runtime path
- older active plan docs reconciled to the implemented UX shape

Still optional / follow-up from chunk 1:

- decide whether the shared-row warning before save should be implemented now or deferred

## Required Companion Artifacts

- `claims_ai_service_ddl/plans/ai_validation_admin_refactor_plan.md`
- `claims_ai_service_ddl/plans/ai_validation_taxonomy_detail_screen_spec.md`
- `claims_ai_service_ddl/plans/draft_validation_admin_refactor_ddl.sql`
- `claims_ai_service_documentation/esp_requirements_impl_tracker_2026.md`

This document is the narrowed execution slice. The broader plans still hold background context.

## Scope of Chunk 1

Chunk 1 includes:

- normalize GenAI rule definitions into active tables
- normalize GenAI located-field definitions into active tables
- add a registry for code-located-field definitions
- add history tables for both code and GenAI config
- add one taxonomy-first admin screen
- add the minimal APIs needed for that screen

Chunk 1 does not include:

- supplement OCR/classifier pipeline as a required dependency for admin normalization
- `supporting_document_located_fields`
- session removal or session redesign
- replacement of current GenAI runtime blob execution
- composing runtime prompts from normalized rows
- claims adjudication behavior changes

## Important Design Decisions

### 1. Runtime behavior stays stable

During chunk 1:

- current invoice adjudication keeps using existing runtime behavior
- current GenAI execution continues to use `claims.validationgenai_rulesets`
- normalized tables are admin/config tables first

This is a refactor of authoring/admin structure, not a behavior rewrite.

### 2. Admins can edit and add new

The earlier duplicate-only concept is no longer in scope.

For chunk 1:

- admins may edit active records
- admins may add new active records
- history tables are internal audit only
- history tables are not part of the main end-user UX

### 3. History model is pre-change snapshot only

Each `*_history` table starts empty.

On edit:

1. app snapshots the active row as it exists immediately before save
2. app writes that snapshot into the matching history table
3. app updates the active row

Implications:

- new records have no history rows until first edit
- unchanged records may never have history rows
- history stores prior states, not the current state

### 4. Code-located fields are now in scope

Chunk 1 will add a table-backed registry for code-located-field definitions.

Reason:

- behind-the-scenes DB/code facts should be visible to admins
- they should be enable/disable configurable
- they should have readonly human descriptions

Disabling a code-located field means:

- omit it from the context window payload
- omit it from persisted runtime code-located-field output
- allow downstream rules to warn/fail naturally if they depend on it

That behavior should be accompanied by strong admin warning text.

### 5. Classifier-found facts are not code-located fields

`classifier.eligibility_code` is conceptually GenAI/classifier-found, not code-found.

Chunk 1 should not preserve the current conceptual muddiness as a target state.

## Tables to Create in Chunk 1

### Active tables

- `claims.genai_rules`
- `claims.genai_rule_upgrade_types`
- `claims.genai_located_fields`
- `claims.genai_located_field_upgrade_types`
- `claims.code_located_fields`

### History tables

- `claims.code_rule_history`
- `claims.code_rule_upgrade_type_history`
- `claims.code_located_field_history`
- `claims.genai_rule_history`
- `claims.genai_rule_upgrade_type_history`
- `claims.genai_located_field_history`
- `claims.genai_located_field_upgrade_type_history`

### Existing tables intentionally retained

- `claims.code_rules`
- `claims.code_rule_upgrade_types`
- `claims.invoice_version_located_fields`
- `claims.validationgenai_rulesets`

## Proposed Active Table Roles

### `claims.genai_rules`

Canonical admin/config registry for GenAI rule definitions.

Suggested core fields:

- `id`
- `genai_rule_key`
- `prompt_text`
- `enabled`
- `created_at`
- `updated_at`

### `claims.genai_rule_upgrade_types`

Mapping table declaring:

- which upgrade types use each GenAI rule
- rule order within that upgrade type

Suggested core fields:

- `id`
- `genai_rule_id`
- `invoice_upgrade_type_id`
- `rule_number`
- `created_at`

### `claims.genai_located_fields`

Canonical admin/config registry for GenAI located-field definitions.

Suggested core fields:

- `id`
- `genai_field_key`
- `prompt_text`
- `enabled`
- `created_at`
- `updated_at`

### `claims.genai_located_field_upgrade_types`

Mapping table declaring:

- which upgrade types use each GenAI located field
- field order within that upgrade type

Suggested core fields:

- `id`
- `genai_field_id`
- `invoice_upgrade_type_id`
- `field_number`
- `created_at`

### `claims.code_located_fields`

Canonical admin/config registry for code-found located-field definitions.

Suggested core fields:

- `id`
- `code_field_key`
- `description`
- `enabled`
- `created_at`
- `updated_at`

Notes:

- this table is for definition/registry only
- runtime found values still go to `claims.invoice_version_located_fields`
- no upgrade-type mapping table is required in chunk 1 unless later needed

## Runtime Table Relationship

Important distinction:

- `genai_located_fields` = definitions of what GenAI should try to locate
- `code_located_fields` = definitions of what code/DB facts should be carried in
- `invoice_version_located_fields` = actual located values found/persisted at runtime

So:

- config lives in `genai_located_fields` and `code_located_fields`
- runtime outputs continue to live in `invoice_version_located_fields`

## APIs in Chunk 1

Chunk 1 should add the minimum API surface for the new screen:

- taxonomy list endpoint
- taxonomy detail unified-grid endpoint
- show-one-record endpoint
- update-one-record endpoint
- create-one-record endpoint
- read-history endpoint

The unified taxonomy grid should include:

- code rules
- GenAI rules
- GenAI located fields
- code located fields

## Single Screen in Chunk 1

Chunk 1 includes one new taxonomy-first screen.

Current implemented shape:

- `Validation Rules Portal`
- `Validation Rules Editor`
- typed `Add/Edit ...` screens
- read-only info detail
- read-only audit detail

The editor grid currently shows:

- `Key`
- `Updated`
- `Actions`

Row types for chunk 1:

- `code_rule`
- `code_located_field`
- `genai_rule`
- `genai_located_field`

Actions for chunk 1:

- `Info`
- `Edit`
- `Audit`

`Add new` is available only for:

- `genai_rule`
- `genai_located_field`

## Migration/Backfill Work in Chunk 1

### GenAI definitions

Backfill current GenAI blob content into:

- `claims.genai_rules`
- `claims.genai_rule_upgrade_types`
- `claims.genai_located_fields`
- `claims.genai_located_field_upgrade_types`

This should be treated as careful seed/backfill work, not naive parsing.

### Code located fields

Seed `claims.code_located_fields` from the currently known code-found field list, excluding classifier-found fields.

Current likely starter set:

- `invoices.submitted_at`
- `contractors.business_name`
- `contractors.address`
- `users_eligibilitycodes.eligibility_code`
- `users_eligibilitycodes.income_level`
- `users_eligibilitycodes.approved_at`
- `users_eligibilitycodes.expires_at`
- `users.participant_name`

`classifier.eligibility_code` should be removed from the code-located-field concept.

## Testing Goals

Chunk 1 is successful if we can verify:

1. New normalized/config tables exist and can be seeded.
2. History tables snapshot pre-change values on edit.
3. Existing runtime claims adjudication still works unchanged.
4. New taxonomy screen can list all four row types in one place.
5. Admins can inspect, edit, and add records through the new screen.
6. Disabling a code-located field causes it to be omitted from CW/runtime located-field output.

Note:

- item 6 is now complete locally

## Explicitly Deferred

These are not blockers for chunk 1 and should stay out:

- supplement document processing
- supplement located fields
- supplement rulechecks
- invoice-vs-session intake redesign
- mixed invoice/supplement upload redesign as a prerequisite for chunk 1
- runtime prompt publish/composition flow rewrite

## Recommendation

This should become the official first implementation chunk.

It was the right boundary because it:

- improves admin clarity immediately
- normalizes the worst GenAI blob problem
- adds history in a controlled way
- keeps runtime behavior stable
- avoided coupling this work to the then-unresolved session/supplement architecture fork
