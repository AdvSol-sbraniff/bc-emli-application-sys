# AI Validation Taxonomy Detail Screen Spec

Date: 2026-05-27

Status: partially implemented UX contract. This doc should match the current portal -> editor -> typed-edit flow used in the codebase.

Note:

- the current implementation-slice authority is `claims_ai_service_ddl/plans/ai_validation_normalization_chunk1_plan.md`
- this screen spec has been reconciled to that chunk-1 direction

## Required Companion Artifact

This screen spec depends on:

- `claims_ai_service_documentation/esp_requirements_impl_tracker_2026.md`

That tracker is the working audit source for deciding:

- which record families must exist
- which evidence-source patterns the UI must eventually explain
- which rules are `code`, `genai`, `manual_review`, or `not a claims rule`
- which located fields are likely required

This screen spec should therefore be read together with the tracker and not in isolation.

## Role Of This Document

Use this document for:

- the current validation-admin UX contract
- route and screen expectations for chunk 1
- the intended interaction model for portal, editor, detail, audit, and edit flows

Do not use this document as the runtime execution plan.

For that use:

- `claims_ai_service_ddl/plans/ai_validation_runtime_refactor_plan.md`

## Purpose

Define the primary admin screen for validation configuration after the refactor.

This screen family is the main answer to:

- "What validation records currently apply to this upgrade type?"
- "Is this row shared with other upgrade types?"
- "How do I inspect a row without editing it?"
- "How do I edit a row while preserving the prior state in history?"

## Primary Design Rules

1. The screen is taxonomy-first, not engine-first.
2. The portal is taxonomy-first; the editor is tab-first within a taxonomy.
3. Active rows are editable.
4. History rows are immutable.
5. There is no inline grid editing.
6. Shared cross-upgrade impact must be obvious.

## Route Shape

Current local route shape:

- `/validation-rules-admin`
- `/validation-rules-admin?invoice_upgrade_type_id=:id`
- `/validation-rules-admin?invoice_upgrade_type_id=:id&mode=edit&record_type=:type&record_id=:id`

## Screen Layout

The current chunk-1 screen family has 3 primary surfaces:

1. portal screen
2. taxonomy editor screen
3. typed add/edit screen

Supporting read-only detail surfaces:

4. info detail
5. audit detail

## 1. Header

Portal header content:

- `Validation Rules Portal`
- upgrade-type entry tiles
- `Validation Prompt Config` button
- `Supporting Document Types` button
- optional publish/rebuild controls later

Important:

- `Supporting Document Types` is an adjacent registry screen, not a tab inside the taxonomy editor

## 2. Current taxonomy editor header

Current chunk-1 editor behavior is intentionally light:

- no free-text search
- no sharedness filter
- no enabled filter
- no explicit sort controls

Reason:

- the screen is now intentionally simpler and tab-driven
- the current scope is to make the admin surface understandable first

## 3. Current editor grid

Each tab grid shows one row per active record for that tab.

The rows may come from:

- `claims.code_rules`
- `claims.code_located_fields`
- `claims.genai_rules`
- `claims.genai_located_fields`

### Grid columns

Current implemented shape:

- `Key`
- `Updated`
- `Actions`

### Key column

Displays:

- `code_rule_key`
- `code_field_key`
- `genai_rule_key`
- `genai_field_key`

Important:

- key must be treated as both identifier and compact human summary

Sharedness rule:

- the grid no longer shows mapped upgrade types inline
- sharedness must instead be made obvious in read-only detail and edit flows

### Updated column

Displays:

- active row `updated_at`

Format:

- short date first
- time optional in drawer only

### Actions column

Required actions:

- `Info`
- `Edit`
- `Audit`

Recommended icons:

- `Info`: info/question/eye
- `Edit`: pen/pencil
- `Audit`: history/clock/file-search

## Row Interaction Rules

### Clicking the row

Current behavior:

- no implicit row click navigation
- actions remain explicit

### `Info` action

Opens read-only detail.

### `Edit` action

Opens dedicated typed edit screen.

### `Audit` action

Opens read-only audit detail.

## Info Detail

The read-only detail is typed by record kind.

It is never editable.

### Common detail header fields

- `Type`
- `Key`
- `Updated`
- `Shared by N upgrade types`

If shared:

- show warning banner:
  - `This record is shared. Editing it will affect multiple upgrade types.`

### Code rule detail body

Display:

- `code_rule_key`
- `description`
- `enabled`
- `pass_admin_message`
- `warn_admin_message`
- `fail_admin_message`
- `info_admin_message`
- `admin_notes`
- mapped upgrade types

### Code field detail body

Display:

- `code_field_key`
- `description`
- `enabled`

### GenAI rule detail body

Display:

- `genai_rule_key`
- `prompt_text`
- `enabled`
- mapped upgrade types

### GenAI field detail body

Display:

- `genai_field_key`
- `prompt_text`
- `enabled`
- mapped upgrade types

## Edit Flow

This is the normal mutation path for existing rows.

### Edit flow goals

- keep the active row editable
- preserve the pre-change state in history
- make shared-row impact obvious before save

### Edit flow steps

1. Admin clicks `Edit`.
2. App opens a typed edit screen for that record kind.
3. Admin edits the values.
4. If the row is shared, app shows a strong warning before save.
5. App writes a pre-change snapshot into the matching history table.
6. App updates the active row.

### Add-new flow

`Add new` is separate from edit.

Expected behavior:

1. Admin clicks `Add new`.
2. App opens a blank or lightly prefixed creation form.
3. App inserts a new active row.
4. No history row is created at creation time.

## Audit Detail

Purpose:

- show immutable audit rows for the selected active record

### Audit drawer sections

1. Record history
2. Upgrade-type mapping history

### Record history row fields

- history timestamp
- source key snapshot
- summary of changed fields

### Mapping history row fields

- history timestamp
- upgrade type

Read-only only.

## API Contract Shape

This screen family should not call separate engine-specific list endpoints.

It should use one taxonomy-focused read model plus typed detail/history endpoints.

### Current chunk-1 endpoints

- `GET /api/claims/admin/validation_rules/upgrade_types`
- `GET /api/claims/admin/validation_rules?invoice_upgrade_type_id=:id`

Suggested response row shape:

```json
{
  "record_type": "genai_rule",
  "record_id": "uuid",
  "record_key": "overall_invoice_arithmetic_consistent",
  "upgrade_types": [
    { "id": "uuid", "upgrade_type_key": "common" },
    { "id": "uuid", "upgrade_type_key": "windows_doors" }
  ],
  "shared_count": 2,
  "enabled": true,
  "updated_at": "2026-05-25T14:12:13Z"
}
```

### Current detail/history endpoints

- `GET /api/claims/admin/validation_rules/:record_type/:id/history`

Where `record_type` is one of:

- `code_rule`
- `code_field`
- `genai_rule`
- `genai_field`

### Current mutation endpoints

- `POST /api/claims/admin/validation_rules/:record_type`
- `PATCH /api/claims/admin/validation_rules/:record_type/:id`

## Empty States

If the taxonomy has no rows:

- show an empty-state message
- provide actions:
  - `Create GenAI Rule`
  - `Create GenAI Field`

Current chunk-1 policy:

- do not expose `Create Code Rule`
- do not expose `Create Code Field`

## Non-Goals

This screen should not:

- show raw GenAI blob text as the primary authoring surface
- allow in-place patch editing of active rows
- hide cross-upgrade sharing
- force admins to think in terms of `code` vs `genai` first
- decide contractor upload intake behavior; mixed invoice/supporting-document upload classification is handled upstream of this admin screen

## Success Criteria

This screen is successful if an admin can:

1. open one taxonomy page
2. see all relevant validation records in one grid
3. immediately tell which rows are shared
4. inspect any row without risk
5. edit an active row while preserving the prior state in history
6. understand which upgrade types will be affected by editing a shared row
