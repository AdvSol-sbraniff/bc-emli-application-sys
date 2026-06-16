# AI Validation Runtime Refactor Plan

Date: 2026-05-27

Status: partially implemented. Code-located-field cleanup and supplement typed-presence runtime facts now exist locally. Compiler/publish/runtime-snapshot work is still the next major slice.

## Purpose

Plan the refactor of runtime validation execution now that the admin/config side has moved toward:

- `claims.genai_rules`
- `claims.genai_rule_upgrade_types`
- `claims.genai_located_fields`
- `claims.genai_located_field_upgrade_types`
- `claims.code_located_fields`

This plan answers:

- how the GenAI blob should be composed from normalized records
- where publish fits
- how Sidekiq/jobs should switch over safely
- how code-located-field runtime behavior should align with the new registry

## Required Companion Artifacts

- `claims_ai_service_ddl/plans/ai_validation_normalization_chunk1_plan.md`
- `claims_ai_service_ddl/plans/ai_validation_admin_refactor_plan.md`
- `claims_ai_service_ddl/plans/ai_supporting_documents_supplement_plan.md`
- `claims_ai_service_documentation/esp_requirements_impl_tracker_2026.md`

## Role Of This Document

Use this document for:

- runtime composition sequencing
- publish behavior
- job/service refactor sequencing
- explicit done/next tracking after the admin-side normalization work

Do not use this document as the primary UX contract.

## Current Confirmed State

### Already done

1. Admin/config tables exist locally:

- `claims.genai_rules`
- `claims.genai_rule_upgrade_types`
- `claims.genai_located_fields`
- `claims.genai_located_field_upgrade_types`
- `claims.code_located_fields`

2. History tables exist locally:

- `claims.code_rule_history`
- `claims.code_rule_upgrade_type_history`
- `claims.code_located_field_history`
- `claims.genai_rule_history`
- `claims.genai_rule_upgrade_type_history`
- `claims.genai_located_field_history`
- `claims.genai_located_field_upgrade_type_history`

3. Normalized GenAI seed/backfill exists locally:

- duplicate prompt groups collapsed into shared canonical records
- normalized seed file generated and loaded

4. Admin UI/API exists locally:

- portal screen
- taxonomy editor screen
- typed add/edit screens
- read-only info and audit flows
- `Validation Prompt Config` portal entry
- `Supporting Document Types` portal entry

5. Current runtime is intentionally still blob-driven:

- upgrade/common execution continues to use `claims.validationgenai_rulesets`
- `run_genai_job` still injects `validationgenai_rulesets.user_record1`

6. Code-located-field runtime cleanup now exists locally:

- `claims.code_located_fields.enabled` controls runtime inclusion/omission
- classifier-found `eligibility_code` is no longer treated as a code-located field

7. Supplement typed-presence runtime facts now exist locally:

- mixed-bundle intake resolves invoice vs supplement before final invoice runtime
- `Claims::GenaiCaseFacts::Build` now emits supporting-document summary facts
- each upgrade-type call receives supplement facts narrowed by `claims.supporting_document_type_upgrade_types`

### Not done yet

1. There is no runtime composer that builds the blob from normalized GenAI tables.
2. There is no publish flow that inserts new composed snapshot rows into `claims.validationgenai_rulesets`.
3. Published snapshots are not yet the sole source-of-truth for runtime selection.
4. Supplement adequacy/quality rules are not yet part of runtime.

## Guiding Principles

1. Keep runtime reproducibility.

- executed runs should still point to one bundled snapshot artifact

2. Keep rollout low risk.

- do not switch composition, publish, and execution all at once

3. Keep normalized config as the authoring source.

- active editing belongs in normalized tables
- blob rows become published runtime artifacts

4. Keep code and GenAI semantics clean.

- DB/code facts come from the code-located-field registry
- classifier-found facts are not code-located fields

## Target End State

### Admin/config layer

Admins edit:

- `claims.genai_rules`
- `claims.genai_rule_upgrade_types`
- `claims.genai_located_fields`
- `claims.genai_located_field_upgrade_types`
- `claims.code_located_fields`

### Publish layer

A publish step composes:

- common + taxonomy-specific GenAI located fields
- common + taxonomy-specific GenAI rules

into one runtime blob and inserts a new row into:

- `claims.validationgenai_rulesets`

### Execution layer

Runtime execution reads:

- the published `validationgenai_rulesets` row
- invoice OCR/raw JSON
- code-located facts that are currently enabled

and continues to persist:

- `validationgenai_ruleset_id` on execution/run tables for auditability

## Stepwise Plan

### Step 0. Lock the admin/config slice

Status:

- done locally

Goals:

- ensure normalized tables are seeded
- ensure admin screen can manage normalized rows
- ensure history is working before runtime changes begin

### Step 1. Clean up code-located-field runtime semantics

Status:

- done locally

Goals:

1. Make `claims.code_located_fields` the runtime registry for DB/code facts.
2. Make `enabled=false` actually omit the fact from:

- the context window payload
- persisted `source_engine='code'` located-field rows

3. Remove `classifier.eligibility_code` from the code-located-field runtime path.

Expected code changes:

- refactor `app/services/claims/genai_case_facts/build.rb`
- replace the hardcoded persisted-field list with registry-backed behavior

Implemented outcome:

- disabling a seeded code-located field removes it from runtime output
- classifier eligibility code is no longer persisted as a code-located field

### Step 2. Introduce a GenAI blob composer service

Status:

- not done

Goals:

Build a service that can compose one `user_record1` blob from:

- common GenAI fields/rules
- taxonomy-specific GenAI fields/rules

Suggested service shape:

- `app/services/claims/genai_ruleset_compiler/compile.rb`

Inputs:

- `invoice_upgrade_type_id` or `upgrade_type_key`

Outputs:

- compiled located-fields section
- compiled rules section
- full `user_record1` text

Important rules:

- include shared canonical records only once
- preserve deterministic ordering
- compose common + taxonomy-specific content together
- do not read from old blob authoring rows during compile

Acceptance checks:

- compiler output is deterministic
- compiled output is logically equivalent to the current seeded blob for at least a few sample upgrade types

### Step 3. Add a publish service

Status:

- not done

Goals:

Add an explicit publish path that:

1. calls the compiler
2. creates a new `claims.validationgenai_rulesets` row
3. stores the compiled `user_record1`
4. keeps the old runtime snapshot history pattern intact

Suggested service shape:

- `app/services/claims/genai_ruleset_publisher/publish.rb`

Inputs:

- `invoice_upgrade_type_id`
- optional `published_by` later

Outputs:

- new `validationgenai_rulesets.id`

Acceptance checks:

- repeated publish creates new historical snapshot rows
- published rows can be tied back to the normalized active config that produced them

### Step 4. Add admin/API publish controls

Status:

- not done

Goals:

Add the minimum admin-side publish behavior:

- a publish action from the validation-admin flow
- clear publish success/failure response
- clear indication of last published timestamp later if useful

Important:

- publishing should be explicit, not automatic on every edit

### Step 5. Switch runtime read path to published snapshots produced from normalized config

Status:

- not done

Goals:

Keep runtime still reading `claims.validationgenai_rulesets`, but ensure those rows now come from the publish service rather than manual blob authoring.

This is the safe bridge state:

- authoring source = normalized tables
- runtime source = published snapshot table

Expected changes:

- minimal or no changes to the deepest `run_genai_job` prompt assembly, if it already reads `validationgenai_rulesets`
- changes mainly in how the correct published row is chosen or refreshed

Acceptance checks:

- current jobs still run
- `validationgenai_ruleset_id` audit links remain intact
- published normalized config is what runtime actually uses

### Step 6. Retire old blob authoring as an admin workflow

Status:

- not done

Goals:

- stop treating old blob editing as the primary admin path
- retain `claims.validationgenai_rulesets` only as published runtime snapshots/history

Important:

- do not remove historical blob rows
- do not remove execution FK behavior

### Step 7. Runtime extension for supplement evidence later

Status:

- partially implemented locally for typed presence; deferred for adequacy/quality and extracted evidence

Implemented now:

- v1 supplement runtime should read supplement type inventory/presence only
- each upgrade-type call now receives configured/present/missing supplement type facts

Still later:

- upgrade-type execution should continue to read invoice evidence + enabled code facts
- later runtime may optionally read curated supplement evidence if real sample documents prove it is needed

This step belongs after:

- the mixed-bundle supplement typing architecture is implemented
- the `read -> triage classifier -> single invoice-model loopback` intake path is implemented

Important refinement:

- `claims.supporting_document_located_fields` is no longer assumed for the first supplement slice
- the first supplement slice only requires typed supplement persistence on `claims.supporting_documents`

## Recommended Sequence

1. Build the compiler in Step 2 next.
2. Add publish in Step 3 after that.
3. Expose publish controls in Step 4 next.
4. Switch runtime sourcing in Step 5 after publish is proven.
5. Retire old blob authoring in Step 6 last.
6. Extend supplement runtime beyond typed presence only if real document samples justify it.

## Risks

### 1. Compiler drift from historical blob behavior

If the compiler output differs materially from the current seeded blobs, runtime outcomes may change unexpectedly.

### 2. Hidden code-fact dependency risk

If `code_located_fields.enabled` starts being honored, some rules may unexpectedly lose facts they currently assume always exist.

### 3. Shared-record ordering regressions

Even if admins no longer see ordering, the compiler still needs deterministic internal ordering or the composed blob may become unstable.

### 4. Mixed source-of-truth confusion

During rollout, the team must be clear about:

- normalized tables = authoring source
- `validationgenai_rulesets` = published runtime source

## Success Criteria

This refactor is successful when:

1. Admins author GenAI config only through normalized tables.
2. Runtime blobs are composed from normalized records rather than manually authored blobs.
3. Publishing produces historical snapshot rows in `claims.validationgenai_rulesets`.
4. Existing run-audit links still work unchanged.
5. `code_located_fields.enabled` actually controls runtime inclusion.
6. `classifier.eligibility_code` is no longer modeled as a code-located field.
7. Attached supplement types are visible to upgrade-type runtime calls through persisted DB facts.
