# AI Contractor Portal DDL Plan

Purpose: focused schema/data-model plan for the AI contractor invoice flow. The master map is `ai_contractor_portal_plan.md`.

## Decisions

- Local development can be destructive/rebuild-oriented.
- Gold changes wait until local is tested by harness and manual testing.
- Avoid duplicate sources of truth unless the duplicate is a historical snapshot.
- Invoice workflow status belongs on `claims.invoices`.
- Session workflow status should go away.
- Invoice upgrade type belongs on `claims.invoices`, not on sessions.
- Ruleset used belongs on `claims.invoice_versions` as historical explainability.
- AI assignment should reuse the legacy concept, but not the legacy physical table.

## Invoice Changes

`claims.invoices` should include:

- `upgrade_type_id uuid NULL`
- FK to `public.permit_classifications(id)`
- status check updated for final v1 statuses

Status direction:

- Keep pipeline states for upload/OCR/GenAI.
- Use `admin_review_inbox` after contractor submit.
- Use `revisions_requested` for contractor revision inbox.
- Use `in_review`, `approved_pending`, `approved_paid`, and `ineligible` for business/admin flow.
- Remove `closed_success` and `closed_reject`.
- Do not add submit-blocked status for v1.

## Invoice Version Changes

`claims.invoice_versions` should include:

- `validationgenai_ruleset_id uuid NULL`
- FK to `claims.validationgenai_rulesets(id)`

Rationale:

- This is a historical snapshot, not undesirable duplication.
- Old invoice versions must remain explainable even if a ruleset is later disabled, renamed, or replaced.

First-class field submit blockers:

- Contractor submit blocks if any tracked first-class OCR field on the latest invoice version is null.
- The tracked first-class values currently include:
- `di_ocr_invoice_id`
- `di_ocr_invoice_date`
- `di_ocr_vendor_name`
- `di_ocr_vendor_address`
- `di_ocr_customer_name`
- `di_ocr_billing_address`
- `di_ocr_sub_total`
- `di_ocr_total_tax`
- `di_ocr_invoice_total`
- `di_ocr_amount_due`

## Ruleset Changes

`claims.validationgenai_rulesets` should include:

- `upgrade_type_id uuid NULL` during local transition, eventually required for enabled rulesets.
- FK to `public.permit_classifications(id)`.
- `enabled boolean NOT NULL DEFAULT true`.
- Index on `(upgrade_type_id, enabled, created_at DESC)`.

Selection:

- Choose newest enabled ruleset for the invoice upgrade type.
- No fallback/default ruleset behavior.
- Multiple enabled rulesets per upgrade type are allowed; newest wins.
- Rename/re-seed `esp_default_v1` as an explicit Windows and doors ruleset.

Common/domain composition:

- The current prototype mixes common rules and Windows/doors rules in one `user_record1` text block.
- That is acceptable for discovery, but not ideal for seven upgrade types.
- Plan for centrally maintained common rules plus upgrade-specific rules.
- The ruleset editor should eventually make this separation visible:
- Common cross-upgrade rules.
- Upgrade-specific rules.
- Shared output schema/instructions.
- Located fields for the selected upgrade type.

Possible physical model:

- Keep `claims.validationgenai_rulesets` as the published/composed ruleset snapshot.
- Add a future fragment/source table only if needed, such as `claims.validationgenai_rule_blocks`.
- Rule block types could be `common`, `upgrade_specific`, `output_schema`, and `located_fields`.
- Publishing a ruleset composes the blocks into a final snapshot.

Rationale:

- Admins should not edit the same common rule seven times.
- Old invoice versions still need to know the exact composed ruleset used.
- A composed snapshot keeps audit/history stable even after common rules are later changed.

Hybrid validation engine:

- The current schema already supports `source_engine = 'code'` and `source_engine = 'genai'` for located fields and rulechecks.
- Preserve that distinction.
- GenAI should not be responsible for deterministic math/date/threshold checks.
- Add a planned code-engine service that writes `claims.invoice_version_rulechecks` rows with `source_engine = 'code'`.
- The ruleset editor should eventually distinguish:
- GenAI evidence-location instructions.
- Deterministic code rule definitions.
- Manual/admin review rules.
- External lookup rules.

Candidate deterministic code checks:

- first-class OCR field presence
- six-month submission deadline
- eligibility code approval/expiry date checks
- U-factor numeric threshold
- rebate percent/cap/tax math
- amount due equals invoice total minus rebate/deposits/payments where applicable
- contractor/customer/address comparisons after normalization

Immutability:

- UI convention is enough for v1.
- Used rulesets should be cloned/new-versioned rather than edited in place.
- API-level rejection of edits to used rulesets is a possible v2 hardening item.

## Session Changes

`claims.sessions` should stop carrying workflow meaning:

- Remove/comment `status`.
- Remove/comment `submitted_at`.
- Keep `submitter_id` as actual acting user.
- Keep session as the upload batch/navigation container.

Compatibility:

- During transition, views may expose `NULL AS session_status` if old AI admin widgets still expect a field.

## Assignment Changes

Create a new AI assignment table rather than forcing AI invoices into `application_assignments`.

Proposed table:

```sql
claims.invoice_assignments
```

Suggested columns:

- `id uuid primary key default gen_random_uuid()`
- `invoice_id uuid not null references claims.invoices(id) on delete cascade`
- `user_id uuid not null references public.users(id)`
- `created_at timestamp(6) without time zone not null default now()`
- `updated_at timestamp(6) without time zone not null default now()`

Constraint:

- One active assignment per invoice for v1.
- Simplest physical model: unique index on `invoice_id`.

## Views

Update AI views to expose:

- Upgrade type id/code/name.
- Latest invoice version ruleset id/shortname.
- Assigned user id/name if assignment is added.
- No meaningful session status.

## V2/Future

- GenAI invoice-type autodetection can replace the explicit Windows and doors choice later.
- DB is ready because upgrade type is invoice-level.
- Future mixed-type upload batches can store different upgrade types on different invoice rows in the same session.

## V2/Future: One Invoice With Multiple Upgrade Types

If business confirms that one commercial invoice PDF can contain multiple rebate upgrade types, invoice-level `upgrade_type_id` is not enough as the final model.

Recommended future shape:

- `claims.invoices` represents the uploaded invoice document.
- Add child rows, likely `claims.invoice_upgrade_claims`.
- Each child claim owns:
- `invoice_id`
- `upgrade_type_id`
- claim/review status
- selected ruleset/version
- located fields and rulechecks scoped to that upgrade type
- rebate/admin outcome

Processing model:

- OCR once for the invoice PDF.
- Classify/segment upgrade-type evidence from the OCR output.
- Run one domain validation per detected/claimed upgrade type.
- Store common invoice fields once, then store claim-specific fields/checks under each child claim.

V1 stance:

- Do not implement this until Gate 0 confirms whether it is required for the first release.
- Keep v1 focused on one invoice reviewed as Windows and doors only.
