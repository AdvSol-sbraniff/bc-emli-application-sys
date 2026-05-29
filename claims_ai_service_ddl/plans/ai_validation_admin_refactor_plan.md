# AI Validation Admin Refactor Plan

Date: 2026-05-27

Status: partially implemented at the admin/config layer. Use this as the broader strategy document, not the exact current UI contract.

Note:

- the current implementation-slice authority is `claims_ai_service_ddl/plans/ai_validation_normalization_chunk1_plan.md`
- this broader plan has been reconciled to match that chunk-1 direction

## Role Of This Document

Use this document for:

- broad architecture
- sequencing across admin, history, and runtime concerns
- explaining why the refactor exists
- understanding how the validation-admin portal now relates to adjacent support-doc registries

For the current chunk-1 implementation slice, use:

- `claims_ai_service_ddl/plans/ai_validation_normalization_chunk1_plan.md`

For the current screen-level UX contract, use:

- `claims_ai_service_ddl/plans/ai_validation_taxonomy_detail_screen_spec.md`

For the runtime blob-composition and execution refactor, use:

- `claims_ai_service_ddl/plans/ai_validation_runtime_refactor_plan.md`

## Required Companion Artifact

This plan now depends on the maintained traceability tracker:

- `claims_ai_service_documentation/esp_requirements_impl_tracker_2026.md`

That tracker is now a required working artifact for this refactor because it records, requirement by requirement:

- source quote and PDF page
- evidence sources required
- intended check style: `genai` | `code` | `manual_review` | `not a claims rule`
- likely located fields required
- current traceability keys
- missing coverage and priority

When this plan says a taxonomy, rule family, supplement path, or located-field family should exist, the markdown tracker should be treated as the audit source for completeness and sequencing. The older DOCX is now only a legacy snapshot.

## Purpose

Plan the refactor of the validation-admin area so that:

- admin UX is taxonomy-first, not engine-first
- GenAI rules and code rules can be viewed together under one upgrade type
- GenAI located fields become first-class records instead of living inside one large blob
- code located fields become first-class admin-visible records
- shared records clearly show cross-upgrade impact
- code and GenAI config both gain proper config-history support
- invoice and supplement evidence can both participate in one coherent rule-review surface
- executed runs still retain one bundled snapshot artifact for audit/repro
- document intake can evolve toward a single mixed upload experience while keeping invoice and supplement classification responsibilities cleanly separated

Current local admin note:

- the portal now also includes adjacent entry points for `Validation Prompt Config` and `Supporting Document Types`
- `Supporting Document Types` is intentionally a separate registry screen, not a tab inside the taxonomy editor

## Core Decisions

### 1. Admin navigation should be taxonomy-first

Top-level admin navigation should group by upgrade type, for example:

- `common`
- `windows_doors`
- `insulation`
- `air_source_heat_pump_electric`
- `heat_pump_water_heater`

The current split between separate GenAI and code screens is implementation-driven and does not match how admins think.

### 2. Taxonomy detail should show a unified grid

Inside one taxonomy detail screen, admins should see one grid that combines:

- code rules
- code located fields
- GenAI rules
- GenAI located fields

Recommended grid columns:

- `type`
- `key`
- `upgrade_types`
- `updated_at`
- `actions`

Recommended actions:

- `info` icon opens read-only detail
- `edit` action opens record edit screen
- `audit` icon opens read-only audit/history detail
- `add new` lives at the screen or section level

No direct inline cell editing should exist on the row.

### 3. Active rows can be edited; history rows remain immutable

Updated design decision:

- active/config rows may be edited
- new rows may be added
- history rows are created automatically from the pre-change state on edit
- history rows are not part of the normal editing flow

This applies to:

- code rules
- code located fields
- GenAI rules
- GenAI located fields

Why:

- matches the separate active-table plus history-table model
- keeps admin UX practical once records become small and atomic
- preserves auditability without forcing blob-era duplicate workflows

### 4. Cross-upgrade sharing must be explicit

If a rule or located field is shared by multiple upgrade types, the UI must make that obvious.

Required visibility:

- show sharedness clearly in read-only detail
- show a stronger warning during edit if the selected record is shared by multiple upgrade types

### 5. Executed-run audit should stay bundled

Even after normalization, executed GenAI runs should still point to one bundled snapshot artifact, like today.

That means:

- normalized tables are for active authoring/admining
- published/composed snapshot rows remain the runtime artifact for reproducibility

### 6. Upload intake and classification should branch early

The final system should support a single mixed upload experience for invoices and supporting PDFs.

Preferred intake/classification model:

- run Azure Document Intelligence `read` on every uploaded PDF
- run one per-file triage classifier on the `read` output
- classifier returns:
  - `document_kind = invoice | supplement | unknown`
  - invoice upgrade types when the file is an invoice
  - supplement type when the file is a supplement
- bundle auto-continues only if exactly one file is classified as invoice
- after that gate passes, run one follow-up Azure Document Intelligence `prebuilt-invoice` pass for the resolved invoice only

This keeps the intake path simple and lets the current invoice validation path stay intact once the invoice file is identified.

Current local state:

- this early-branching intake path is now implemented with shell-invoice staging and per-file `ingest_documents`
- the validation-admin screens are no longer blocked on that intake design

## Current Problems

### UX problems

- the legacy admin split was engine-first: `/rulesets-admin` vs `/code-rulesets-admin`
- admins do not think in terms of `genai` vs `code`
- GenAI config is blob-based, so there is no clean row-level management experience
- shared-record impact is not clearly visible

### Data-model problems

- GenAI rules and located fields are denormalized inside `claims.validationgenai_rulesets.user_record1`
- code-located-field definitions are currently implicit in Ruby rather than registered in a table
- HP families contain substantial duplicated GenAI rule logic
- located-field sections also contain substantial duplication
- code rules currently have current-state config only and no config-history table
- current GenAI blob model does preserve history, but in a different pattern than code rules

### Traceability/admin-control problems

- objective checks can drift if ownership between code and GenAI is unclear
- code-found DB facts are not clearly visible/configurable in admin UX
- admins cannot manage all validation records from one conceptual place
- shared records are easy to misunderstand

## Target UX

## 1. Taxonomy List Screen

Purpose:

- entry point into validation admin by upgrade type

Recommended row shape:

- upgrade type icon/tile
- upgrade type key
- counts:
  - active code rules
  - active code located fields
  - active GenAI rules
  - active GenAI located fields
- last updated timestamp

Recommended actions:

- open taxonomy detail screen

## 2. Taxonomy Detail Screen

Purpose:

- primary day-to-day admin screen

Display:

- one unified grid containing rows from multiple tables

Grid columns:

- `type`
- `key`
- `upgrade_types`
- `updated_at`
- `actions`

`type` values:

- `code_rule`
- `code_located_field`
- `genai_rule`
- `genai_located_field`

Actions:

- `info`
- `edit`
- `audit`

Behavior:

- `info` opens a typed read-only drawer
- `edit` opens a typed edit screen or modal
- `audit` opens read-only audit/history display

Important:

- no inline grid editing

## 3. Info Drawer

Purpose:

- read-only display of the selected record

For `code_rule` show:

- `code_rule_key`
- enabled state
- admin messages
- admin notes
- mapped upgrade types
- latest audit metadata

For `code_located_field` show:

- `code_field_key`
- `description`
- enabled state
- latest audit metadata

For `genai_rule` show:

- `genai_rule_key`
- `prompt_text`
- enabled state
- mapped upgrade types
- prompt order within each mapped upgrade type
- latest audit metadata

For `genai_located_field` show:

- `genai_field_key`
- `prompt_text`
- enabled state
- mapped upgrade types
- field order within each mapped upgrade type
- latest audit metadata

## 4. Edit Flow

Purpose:

- update the active row while preserving the prior state in history

Expected flow:

1. Admin clicks edit.
2. App loads the active row into an edit form.
3. Admin changes the record.
4. App snapshots the pre-change row into the matching history table.
5. App saves the updated active row.

This flow is especially important for shared heat-pump-family records.

If the record is shared by multiple upgrade types:

- show a prominent warning before save
- explain that editing the shared row affects all mapped upgrade types

## 5. Audit Drawer

Purpose:

- show immutable audit/history rows for that record

Display:

- snapshot timestamp
- created timestamp
- actor if available later
- prior/new values summary

Read-only only.

## Target Data Model

## 1. Active Tables

Keep active/current rows in dedicated tables.

Code:

- `claims.code_rules`
- `claims.code_rule_upgrade_types`
- `claims.code_located_fields`

GenAI:

- `claims.genai_rules`
- `claims.genai_rule_upgrade_types`
- `claims.genai_located_fields`
- `claims.genai_located_field_upgrade_types`

Recommended GenAI active-table philosophy:

- lean rows
- no extra admin-message columns
- keys should be human-usable
- prompt text is the real content

Located-field scope note:

- `genai_located_fields` is the reusable config registry for GenAI field definitions
- `code_located_fields` is the reusable config registry for code/DB field definitions
- runtime invoice located values should continue to converge into `claims.invoice_version_located_fields`
- supplement located values will likely need their own table later because supplement evidence is invoice-level, not invoice-version-level

Recommended key columns:

- `code_rule_key`
- `genai_rule_key`
- `genai_field_key`

## 2. Separate History Tables

History should be pulled out of active tables.

Recommended history-table suite:

- `claims.code_rule_history`
- `claims.code_rule_upgrade_type_history`
- `claims.code_located_field_history`
- `claims.genai_rule_history`
- `claims.genai_rule_upgrade_type_history`
- `claims.genai_located_field_history`
- `claims.genai_located_field_upgrade_type_history`

Recommended history-table purpose:

- pre-change audit snapshots
- not part of day-to-day active config reads

Recommended common history fields:

- `id`
- parent active-table id
- business key snapshot
- full relevant config snapshot
- `history_created_at`
- `history_created_by` later if/when available

History-table philosophy:

- each row is just a point-in-time snapshot
- no explicit `history_action` column is required
- if the active row changes, a new snapshot row is written

## 3. Published Runtime Snapshot Table

Keep `claims.validationgenai_rulesets` as the published/composed snapshot table used for:

- runtime selection
- executed-run reproducibility
- historical review of exact prompt blobs used

Meaning:

- normalized GenAI records are authoring/admin records
- `validationgenai_rulesets` remains the bundled runtime artifact

## 4. Current-State Storage vs History Storage

Two important concepts must coexist:

- active/current tables used by the app
- immutable history rows used for audit

That means:

- admins may edit active rows
- the app snapshots the prior active row before save
- mapping rows may be edited directly, with prior state preserved in history
- history tables preserve the prior active state transitions

## API Refactor

## 1. Replace engine-first admin endpoints

Current admin endpoints are split by implementation:

- GenAI rulesets controller
- code rules admin controller

Target is taxonomy-first APIs.

Recommended new API families:

- `GET /api/claims/admin/validation_taxonomies`
- `GET /api/claims/admin/validation_taxonomies/:upgrade_type_id`
- `GET /api/claims/admin/validation_records/:type/:id`
- `POST /api/claims/admin/validation_records/:type`
- `PATCH /api/claims/admin/validation_records/:type/:id`
- `GET /api/claims/admin/validation_records/:type/:id/audit`

Optional later:

- `POST /api/claims/admin/validation_taxonomies/:upgrade_type_id/publish_genai_snapshot`

## 2. Unified taxonomy-detail payload

The taxonomy detail API should return one grid-ready list, for example:

- `record_type`
- `record_id`
- `record_key`
- `upgrade_types`
- `updated_at`
- `enabled`

This is a view-model API, not a raw table dump.

## 3. Typed detail payloads

Typed detail endpoints can branch by record type.

Examples:

- code rule detail
- GenAI rule detail
- GenAI located field detail

This keeps the grid simple while allowing richer typed detail views.

## 4. Mutation APIs

Mutation APIs should:

- create new active-table rows when admin chooses `add new`
- snapshot pre-change rows into history tables on edit
- mutate active rows directly only after snapshotting prior state

## Frontend Refactor

## 1. Navigation

Replace the current mental split:

- `/rulesets-admin`
- `/code-rulesets-admin`

with a validation-admin flow centered on taxonomy.

Current local route shape:

- `/validation-rules-admin`
- `/validation-rules-admin?invoice_upgrade_type_id=:id`
- `/validation-rules-admin?invoice_upgrade_type_id=:id&mode=edit&record_type=:type&record_id=:id`

## 2. Shared row model

Introduce one frontend row type family for taxonomy detail:

- `record_type`
- `record_id`
- `record_key`
- `upgrade_types[]`
- `updated_at`
- `enabled`

The editor is tabbed by record family, so this shared row model is mainly a read-model normalization, not a promise that every property is shown in the visible grid.

Current visible grid shape is intentionally minimal:

- `Key`
- `Updated`
- `Actions`

Read-only detail handles type-specific content.

## 3. Current chunk-1 UX direction

Use:

- portal screen for upgrade-type entry
- taxonomy editor screen for the active grid
- dedicated typed add/edit screens
- read-only info detail
- read-only audit/history detail

## 4. Sharedness warnings

Every place that can lead to save/update must warn if the selected record is shared by multiple upgrade types.

## Migration Strategy

## Phase 1. Normalize without changing runtime behavior

Goals:

- add new GenAI normalized active tables
- add `code_located_fields`
- add new history tables for both code and GenAI
- keep current runtime still using `validationgenai_rulesets`

Do not remove existing GenAI blob usage yet.

Current status:

- done locally

## Phase 2. Backfill current active records

Goals:

- parse current GenAI blob content
- seed canonical GenAI rules
- seed canonical GenAI located fields
- seed upgrade-type mappings and ordering

Important:

- this phase needs careful deduplication, especially across HP families
- some rows that look shared today may need to remain distinct if wording is meaningfully different
- the tracker document should be used as the audit checklist while backfilling, not just the old blob contents alone

Current status:

- done locally for the normalized GenAI seed, including canonical prompt-group sharing

## Phase 3. Add taxonomy-first read APIs

Goals:

- build unified taxonomy list endpoint
- build unified taxonomy detail endpoint
- build typed detail endpoints
- build audit endpoints

Current status:

- done locally, although the actual endpoint naming follows `/api/claims/admin/validation_rules/...`

## Phase 4. Build taxonomy-first admin UX

Goals:

- taxonomy list screen
- taxonomy detail grid
- read-only info detail
- read-only audit detail
- edit flow
- add-new flow

During this phase, old engine-first admin screens can remain available.

Current status:

- mostly done locally
- remaining work is selected UX polish, regression coverage, and supplement-phase follow-on design

## Phase 5. Add publish flow for GenAI

Goals:

- compose normalized GenAI records into runtime blob
- insert new `validationgenai_rulesets` row on publish
- keep `invoice_version_upgrade_types.validationgenai_ruleset_id` and `ingest_step_runs.validationgenai_ruleset_id` behavior unchanged

Current status:

- not started

## Phase 6. Retire old GenAI blob authoring screen

Goals:

- stop using direct blob authoring as the primary admin experience
- keep historical blob rows only as published runtime snapshots

## Risks

## 1. Shared-record confusion

If the UI does not clearly show sharing, admins will accidentally assume taxonomy-local edits when they are actually changing shared config.

## 2. Over-deduplication

Some apparently similar HP rules may need separate records. Forced sharing where wording is truly different will create bad abstractions.

## 3. Shared-row edit complexity

Editing shared rows requires strong warnings and clear mental models so admins understand multi-taxonomy impact.

## 4. Blob parser quality

Backfilling normalized GenAI rows from current blobs will require careful manual review. This should not be treated as a fully automatic migration.

## 5. History design drift

If code-rule history and GenAI history are implemented differently, the original consistency problem will just reappear in a new form.

## Recommended Sequence

1. Finalize the taxonomy-detail UX contract first.
2. Finalize the normalized active-table shape second.
3. Finalize the separate history-table suite third.
4. Build read-only taxonomy APIs before mutation flows.
5. Build edit/add mutation flows after the read model is stable.
6. Add GenAI publish composition after normalized data is trustworthy.
7. Remove the old blob-editing UX last.

## Open Questions

- Should active tables allow physical row updates by backend internals, or should all admin-driven changes always create successor rows?
- Should code located fields ever need upgrade-type mapping, or is a global registry enough?
- Should publish be manual only, or should some edit flows optionally offer immediate publish for GenAI taxonomy packages?
- Should the unified taxonomy grid sort by `type` then `key`, or purely by `updated_at` by default?
- Should supplement-origin runtime located values live in a dedicated supplement table rather than overloading invoice-version located fields?

## Success Criteria

The refactor is successful when:

- admins enter validation config through taxonomy, not engine
- one taxonomy screen shows code rules, code located fields, GenAI rules, and GenAI located fields together
- shared records visibly show cross-upgrade impact
- admins can edit active rows and add new ones
- both code and GenAI config have proper history tables
- code located fields have a proper admin-visible registry
- supplement-driven rules and their required evidence/located-fields can be expressed cleanly in the same admin model
- GenAI runtime still uses one composed snapshot artifact per published suite
- old blob authoring is no longer required for day-to-day admin work
