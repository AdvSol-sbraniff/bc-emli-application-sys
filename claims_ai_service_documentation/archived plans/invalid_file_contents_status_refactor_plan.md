# Package Correction And Technical Failure Status Refactor Plan

## Goal

Keep `claims.invoices.status` short enough to be useful in grids and filters, while preserving enough structured diagnostic detail to troubleshoot failures without digging through raw logs first.

This replaces the earlier idea of adding many `invalid_file_contents_*` invoice statuses.

## Agreed Direction

Add two broad workflow statuses:

- `package_needs_correction`
- `technical_failure`

Add one shared subtype column:

- `status_subtype`

The top-level status tells the UI and workflow who needs to act. The subtype tells admins and support staff why.

## Definitions

### package_needs_correction

`package_needs_correction` means the contractor uploaded something the app cannot treat as a coherent review package.

The system worked correctly. The package is the problem.

Who fixes it:

- contractor
- business user helping the contractor

Examples:

- no invoice PDF
- two invoice PDFs
- invoice candidate is not a PDF
- +1 replacement upload has no file
- +1 replacement upload has multiple files
- unsupported file type
- zero-byte or unreadable uploaded file

### technical_failure

`technical_failure` means the system tried to process a package, but the app, worker, Node service, Azure OCR, Azure GenAI, storage, database, or another runtime dependency failed.

The package may be fine. The system is the problem.

Who fixes it:

- admin
- technical support
- developer/operator

Examples:

- Azure OCR did not respond
- GenAI returned malformed JSON
- Node upload service returned HTTP 500
- storage write failed
- database persistence failed
- Sidekiq retries were exhausted

## Boundary Rules

Use this simple rule:

```text
package_needs_correction = user input/package problem
technical_failure = system processing/runtime problem
```

Use `package_needs_correction` only for hard package-shape blockers that prevent the app from forming or continuing a coherent review package.

Do not use `package_needs_correction` for normal Advice/rule failures.

Examples that should remain Advice/check failures:

- missing manufacturer label evidence
- wrong efficiency rating
- product not on eligible list
- invoice missing a required program field
- supporting evidence does not prove the measure
- rebate requirement not met

Clean test:

```text
Can the system create a coherent package and run Advice?
```

If no, use `package_needs_correction`.

```text
Can the system run Advice, but Advice says the claim has problems?
```

Then keep it as an Advice/check failure, not a workflow status failure.

One nuance:

If a package/content issue is discoverable only during Advice and does not block the pipeline from running, keep it as Advice. `package_needs_correction` is reserved for hard blockers.

## Why This Is Better

The older direction made `claims.invoices.status` too long. A giant status list starts acting like a log table.

A single generic failed status is also too abstract because admins cannot troubleshoot.

This model gives us:

- a short status list for filters and grids
- clear ownership of the next action
- structured diagnostics through `status_subtype`
- detailed low-level evidence still preserved in step-run errors and Node logs
- normal business/rule failures kept in Advice where they belong

## Data Model

Update `claims_ai_service_ddl/2_create_schema.sql`.

Do not create stored alter scripts.

Local testing may use realtime `ALTER TABLE`, but the canonical schema change belongs only in `2_create_schema.sql`.

### invoices.status

Add:

- `package_needs_correction`
- `technical_failure`

Keep existing failure statuses temporarily until compatibility is proven:

- `upload_failed`
- `ocr_failed`
- `genai_failed`

Preferred end state:

- contractor/package hard blockers use `package_needs_correction`
- runtime/system failures use `technical_failure`
- old failed statuses are either migrated or become legacy aliases only

### invoices.status_subtype

Add:

```sql
status_subtype character varying NULL
```

Do not add a database check constraint initially. Validate subtype names in Ruby so the list can evolve without repeated DDL changes.

Clear `status_subtype` when moving back into normal non-failure workflow statuses.

## Status Subtype Registry

Create one Ruby registry for allowed status subtypes.

Recommended location:

`app/services/claims/invoices/status_subtypes.rb`

The registry should know:

- valid top-level statuses that can have subtypes
- allowed subtypes for each status
- plain-language labels/hints for UI/API use

## package_needs_correction Subtypes

Use these for hard package blockers only:

- `package_no_invoice_pdf`
- `package_multiple_invoice_pdfs`
- `package_invoice_not_pdf`
- `package_replacement_not_invoice`
- `package_replacement_multiple_files`
- `package_unsupported_file_type`
- `package_unreadable_file`
- `package_duplicate_file_conflict`
- `package_no_processable_files`
- `package_invoice_classification_conflict`
- `package_missing_required_fix_file`
- `package_file_too_large`

Do not add subtypes for ordinary Advice/rule failures such as missing evidence or ineligible equipment.

## technical_failure Subtypes

Use these for system/runtime failures only:

- `upload_service_no_response`
- `upload_service_error`
- `upload_service_malformed_response`
- `upload_storage_key_missing`
- `upload_storage_write_failure`
- `upload_unexpected_exception`
- `ocr_service_no_response`
- `ocr_service_error`
- `ocr_service_malformed_response`
- `ocr_storage_read_failure`
- `ocr_provider_timeout`
- `ocr_unexpected_exception`
- `genai_service_no_response`
- `genai_service_error`
- `genai_service_malformed_response`
- `genai_provider_timeout`
- `genai_unexpected_exception`
- `configuration_missing`
- `db_persistence_failure`
- `worker_retry_exhausted`
- `unknown_runtime_failure`

Naming rule:

- Use `*_service_no_response` when the local app/worker did not get a usable HTTP response from the service.
- Use `*_service_error` when the service replied with an error status/body.
- Use `*_service_malformed_response` when the service replied but the response shape/JSON was unusable.
- Use `*_provider_timeout` when Node or the response tells us the upstream provider timed out.
- Use `*_unexpected_exception` as a fallback only when the code cannot classify the failure more specifically.

## UI Mapping

Update shared frontend status copy:

`app/frontend/components/shared/claims/invoice-status-copy.ts`

Add labels:

- `package_needs_correction`: `Package Needs Correction`
- `technical_failure`: `Needs Technical Help`

Suggested hints:

- `package_needs_correction`: `The uploaded package cannot be reviewed yet. The contractor needs to correct the upload.`
- `technical_failure`: `A system or service error stopped processing. Admin troubleshooting is required.`

If `status_subtype` is available, show subtype-specific hint text in hover/help text, but keep the main grid label broad.

Do not show raw subtype as the primary label.

## API Changes

Expose `status_subtype` anywhere invoice status is returned:

- invoice admin grid
- admin invoice review current version invoice accordion
- contractor portal invoice list
- contractor upload package status
- contractor invoice review
- ingest run invoice/step detail endpoints where useful

For admin views, include subtype labels/hints if practical.

For contractor views, keep wording plain and action-oriented.

## Pipeline Changes

### Upload / Package Staging

Set `package_needs_correction` when the uploaded files cannot form a coherent package before downstream processing.

Examples:

- no files received
- no processable files
- unsupported file type
- zero-byte or unreadable file
- duplicate file conflict that prevents safe routing
- file too large

Set `technical_failure` when upload infrastructure fails.

Examples:

- Node upload service does not respond
- Node upload service returns an error
- Node upload response is malformed
- Node upload response is missing `storage_key`
- storage write fails
- database persistence fails

### Classifier / Package Gate

Set `package_needs_correction` when classifier results prove the package cannot be routed.

Examples:

- no invoice PDF
- multiple invoice PDFs
- invoice-like file is not a PDF
- classifier cannot safely distinguish invoice vs supporting documents

Do not run downstream invoice OCR/Advice after a hard package blocker.

### OCR

Set `technical_failure` for runtime OCR failures.

Examples:

- Node OCR service does not respond
- Node OCR service returns an error
- OCR response JSON is malformed
- OCR provider timeout/error
- storage read failure
- unexpected OCR job exception

### GenAI

Set `technical_failure` for runtime GenAI failures.

Examples:

- Node GenAI service does not respond
- Node GenAI service returns an error
- GenAI response JSON is malformed
- provider timeout/error
- unexpected GenAI job exception

### +1 Fix Flow

Use `package_needs_correction` when the replacement upload itself is not a valid single invoice replacement.

Examples:

- no replacement file
- multiple replacement files
- replacement file classifies as not invoice

Use `technical_failure` when the +1 OCR/classifier/runtime path fails.

## Advice / Check Direction

Normal program failures remain Advice/check failures.

Candidate Advice/check improvements:

- required supporting evidence is attached and usable
- supporting document evidence satisfies the detected upgrade type
- invoice first-class fields are present enough for downstream review
- replacement invoice still supports the original claim context

These should not become workflow statuses unless they are hard blockers before the app can create a coherent package.

## Test Plan

### Schema / Compatibility Tests

Verify:

- `package_needs_correction` is allowed by `claims.invoices.status`.
- `technical_failure` is allowed by `claims.invoices.status`.
- `status_subtype` can be null.
- old statuses still work during transition.
- setting a normal status clears or ignores stale `status_subtype` according to implementation rules.

### Package Correction Tests

Create local packages or manual upload cases for:

- no files received
- no invoice PDF
- multiple invoice PDFs
- invoice image instead of PDF
- unsupported file type
- zero-byte/unreadable file
- duplicate file conflict
- no processable files
- classifier cannot safely route package
- +1 fix with no replacement file
- +1 fix with multiple replacement files
- +1 fix replacement not classified as invoice
- file too large if size limits are configured

Expected:

- invoice status becomes `package_needs_correction`
- `status_subtype` is populated with the matching `package_*` subtype
- pipeline stops before downstream work that requires a coherent invoice version
- step-run or ingest-run message explains the package problem
- UI displays `Package Needs Correction`
- contractor-facing copy explains what to fix

### Technical Failure Tests

Create local tests, mocks, or manual cases for:

- upload service no response
- upload service error response
- upload service malformed JSON
- missing upload storage key
- OCR service no response
- OCR service error response
- OCR malformed JSON
- OCR provider timeout/error if distinguishable
- GenAI service no response
- GenAI service error response
- GenAI malformed JSON
- GenAI provider timeout/error if distinguishable
- unexpected exception path
- worker retry exhausted path if available

Expected:

- invoice status becomes `technical_failure`
- `status_subtype` is populated with the matching runtime subtype
- step-run error contains detailed low-level message
- Node logs still retain provider payload/diagnostic detail
- UI displays `Needs Technical Help`
- subtype-specific hint/details are visible to admins

### Advice Boundary Tests

Use normal packages that can run Advice but fail business/program checks.

Examples:

- missing manufacturer label evidence
- product not on eligible list
- invoice date/field issue
- insufficient supporting evidence

Expected:

- invoice does not become `package_needs_correction`
- invoice does not become `technical_failure`
- Advice/check output shows the failure
- admin and contractor can see what evidence or eligibility issue needs attention

## Implementation Order

1. Add `package_needs_correction`, `technical_failure`, and nullable `status_subtype` to `2_create_schema.sql`.
2. Apply local realtime `ALTER TABLE` for testing only.
3. Add Ruby status subtype registry.
4. Add helper for setting failure status/subtype and clearing subtype on normal workflow transitions.
5. Update upload/package staging to set `package_needs_correction` or `technical_failure` as appropriate.
6. Update classifier/package gate to set `package_needs_correction` for hard package blockers.
7. Update OCR and GenAI job failure paths to set `technical_failure`.
8. Update +1 fix flow for both package correction and technical failure paths.
9. Expose `status_subtype` in invoice APIs.
10. Update frontend labels/hints/details for both statuses and subtype hints.
11. Add or adjust Advice checks for non-blocking package/content findings.
12. Run schema, package correction, technical failure, and Advice boundary tests.
13. Only after compatibility is proven, decide whether to retire `upload_failed`, `ocr_failed`, and `genai_failed`.

## Open Decisions

- Should `upload_failed`, `ocr_failed`, and `genai_failed` remain as legacy statuses or be migrated to `technical_failure`?
- Should `status_subtype` also exist on `claims.ingest_runs`, or is invoice-level enough?
- Where should package-level diagnostic detail live when no invoice version can be created?
- Should contractor portal default filters include `package_needs_correction`, or should it be selectable but not default?
- Should admin invoice default filters include `technical_failure` and `package_needs_correction`, or only active review queues?
