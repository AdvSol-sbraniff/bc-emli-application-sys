# AI Ruleset Editor Refactor Plan

Purpose: plan how the admin ruleset editor should evolve from one large prompt editor into a safer hybrid validation package editor.

Status: planning only. No UI/code changes yet.

## Current Shape

Current admin editor is centered around:

- `ruleset_shortname`
- `system_record`
- `user_record1`

This works for a prototype, but it creates problems:

- Common rules get duplicated across upgrade types.
- Deterministic rules are written as prose and sent to GenAI.
- Admins cannot easily tell what is common versus Windows-specific.
- There is no obvious place for code-engine rules.
- There is no obvious place for manual/admin-review-only rules.
- Versioning/history depends on humans not accidentally editing a used prompt.

## Target Concept

The editor should manage a **validation package**, not just a GenAI prompt.

Validation package sections:

- Package metadata.
- Common rules.
- Upgrade-specific rules.
- GenAI evidence-location instructions.
- Deterministic code rules.
- External lookup/manual review placeholders.
- Output schema / strict response instructions.
- Test fixtures / expected outcomes.

## V1 UI Shape

Keep it simple, but separate meaning:

- Tab 1: Metadata
- Tab 2: Common rules
- Tab 3: Upgrade-specific GenAI evidence instructions
- Tab 4: Code-engine rules
- Tab 5: Manual/external-review rules
- Tab 6: Preview composed prompt/package
- Tab 7: Test results / sample run notes

Do not overbuild the UI before the Windows/doors ruleset is stable.

## Metadata Fields

Suggested metadata:

- `ruleset_shortname`
- `upgrade_type`
- `source_effective_date`
- `source_url`
- `enabled`
- `draft/published`
- `created_by`
- `published_at`
- `supersedes_ruleset_id`
- `notes`

V1 can keep many as plan-only if DDL is not ready.

## Common Rules Editing

Common rules should be edited centrally.

Examples:

- six-month submission deadline
- eligibility code timing
- contractor registration
- rebate itemization/deduction
- duplicate rebate history
- invoice field presence

UI warning:

- "Changes to common rules affect every upgrade type that uses this common block."

## Upgrade-Specific Editing

Each upgrade type should have its own domain section.

Windows and doors examples:

- U-factor threshold evidence.
- skylight exclusion.
- rough opening count.
- per-unit and per-home caps.
- manufacturer/certification references.
- manufacturer label photos.

Heat pump examples should remain disabled/draft until subtype analysis is ready.

## Code-Engine Rules Editing

Do not ask admins to write executable Ruby.

Instead, expose declarative controls later:

- rule key
- source requirement ID
- evaluator: `code_engine`
- required inputs
- threshold/cap/percentage
- comparison operator
- missing evidence behavior
- contractor/admin text

For v1, keep code rules in source-controlled Ruby and document them in the ruleset package.

## Manual / External Rules

These should not be hidden inside GenAI prose.

Examples:

- product-list validation
- City of Vancouver property check
- quote pre-approval
- label photo count
- contractor domain approval
- AHJ/bylaw compliance

UI should display them as:

- `Requires DB check`
- `Requires external lookup`
- `Requires admin review`
- `Not checked by AI`

## Composed Preview

The editor should show the final composed package/prompt that will be sent to GenAI.

Important:

- The composed preview is a generated artifact.
- Admins should edit the source sections, not the generated preview.
- Publishing should snapshot the composed output for audit/history.

## Immutability

Used/published validation packages should not be edited in place.

Recommended behavior:

- Drafts are editable.
- Published rulesets are clone-only.
- Used rulesets are clone-only.
- Disabling a ruleset does not alter historical invoice versions.

V1 may enforce this by UI convention only, but the plan should aim for API hardening later.

## First Practical Step

Before coding UI:

1. Finish Gate 0 matrix.
2. Draft Windows/doors validation package.
3. Identify which package fields must be stored in DDL.
4. Only then change the ruleset editor.

## Risk To Avoid

Do not create a fancy editor that still stores one giant magical text blob with hidden meaning.

The point of the refactor is not prettier textareas.

The point is safer ownership:

- common rules maintained once
- domain rules maintained separately
- deterministic rules not left to GenAI
- missing evidence handled honestly
- historical rulesets explainable later
