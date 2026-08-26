# Per-File Personal Information Flagging Plan

## Plan Status

Implemented and end-to-end tested on 2026-07-28.

## Goal

Add a simple, configurable privacy-review flag to every promoted invoice and supporting document.
The existing per-file GenAI classifier call will assess whether the file contains personal
information that is unnecessary, unexpectedly sensitive, or unrelated to the program purpose.

The implementation must:

- make no additional GenAI calls;
- evaluate every uploaded file independently;
- treat `invoice_versions` and `supporting_documents` as the authoritative evidence records;
- never use an ingest table as an evidence source;
- add one small lookup table for the configured kind of PI found;
- add three privacy-review fields to each of the two evidence tables;
- display flagged results in the corresponding invoice or supporting-document accordion in the
  admin PDF viewer;
- remain admin-only for this MVP;
- support initial uploads, upload fixes, and cloned supporting-document evidence;
- preserve existing contractor behavior.

## Settled Product Decisions

### Evaluation point

- Extend the existing document-classifier GenAI call.
- Do not add a new GenAI call.
- Do not add the PI rule to `genai_common` or an upgrade-type ruleset.
- The classifier is the correct responsibility boundary because it already:
  - runs once per uploaded file;
  - sees the attached file and its Document Intelligence result;
  - distinguishes invoices, supporting documents, and unknown files;
  - returns structured per-file JSON.
- The PI assessment runs for invoices, supporting documents, and unknown files.
- PI assessment is independent of document classification and supporting-document routing quality.

### Evidence ownership

- `claims.invoice_versions` is authoritative for the invoice-file PI result.
- `claims.supporting_documents` is authoritative for each supporting-file PI result.
- Classifier output may temporarily exist in ingest/audit JSON while the pipeline runs, but the
  admin API and UI must never treat an ingest row as evidence.
- Promotion copies the validated classifier result onto the appropriate evidence record.

### MVP result shape

Each evidence file stores:

- a hardcoded review status;
- one configured primary/highest-risk PI type;
- a concise free-form reason.

The MVP does not add a child findings table. Multiple concerns may be summarized in the reason, but
the codified type represents the primary concern selected by the configured priority order.

### Status values

The application and DDL use these exact status values:

```text
not_flagged
review_recommended
high_risk
unable_to_assess
```

Semantics:

- `not_flagged`: the classifier did not identify unnecessary or unexpectedly sensitive PI.
- `review_recommended`: possible unnecessary PI requires an administrator to review the file.
- `high_risk`: clearly sensitive or clearly unrelated PI requires administrator attention.
- `unable_to_assess`: the file was too unreadable, incomplete, or visually ambiguous for a
  reliable assessment.
- `NULL`: legacy evidence or evidence whose classifier has not completed.

Use `not_flagged`, not `clear`; the classifier cannot guarantee that no PI exists.

### PI types

Seed a small configured list in `claims.personal_information_types`:

```text
government_identifier
financial_or_payment_information
health_or_medical_information
authentication_secret
date_of_birth
signature_or_biometric_information
unrelated_third_party_information
other_unnecessary_personal_information
```

The lookup record supplies the stable key, admin display label, classifier description, enabled
state, and priority order. The enabled configured rows are the authoritative PI-type list injected
into the classifier context.

When more than one type appears in a file, the classifier returns the highest-priority applicable
type and mentions the secondary categories without reproducing sensitive values.

Initial deterministic priority:

1. `authentication_secret`
2. `government_identifier`
3. `health_or_medical_information`
4. `financial_or_payment_information`
5. `signature_or_biometric_information`
6. `date_of_birth`
7. `unrelated_third_party_information`
8. `other_unnecessary_personal_information`

The seeded priority can be changed through lookup configuration without changing application code.

## Schema Changes

### New lookup table

Add `claims.personal_information_types` with:

```sql
id uuid NOT NULL DEFAULT gen_random_uuid(),
type_key text NOT NULL,
display_name text NOT NULL,
description text NOT NULL,
enabled boolean NOT NULL DEFAULT true,
sort_order integer NOT NULL DEFAULT 0,
created_at timestamp(6) without time zone NOT NULL DEFAULT now(),
updated_at timestamp(6) without time zone NOT NULL DEFAULT now()
```

Constraints:

```sql
PRIMARY KEY (id),
UNIQUE (type_key),
CHECK (sort_order >= 0)
```

Do not delete referenced types. Disable obsolete types while retaining their historical rows.

### Invoice-version fields

Add to `claims.invoice_versions`:

```sql
personal_information_review_status text NULL,
personal_information_type_id uuid NULL,
personal_information_review_reason text NULL
```

Add:

- a status `CHECK` constraint;
- a foreign key to `claims.personal_information_types(id)` with `ON DELETE RESTRICT`;
- a valid-combination constraint;
- an index on `personal_information_type_id`.

### Supporting-document fields

Add the same fields to `claims.supporting_documents`:

```sql
personal_information_review_status text NULL,
personal_information_type_id uuid NULL,
personal_information_review_reason text NULL
```

Add the same status, foreign-key, valid-combination, and index rules.

### Valid field combinations

Enforce:

- all three fields may be `NULL` for legacy or not-yet-classified evidence;
- `not_flagged` requires a null type and null reason;
- `review_recommended` and `high_risk` require a type and a nonblank reason;
- `unable_to_assess` requires a null type and a nonblank reason.

Do not backfill legacy evidence as `not_flagged`; it was not evaluated by the new classifier.

## Classifier Configuration

### Structured JSON extension

Extend `document_triage_system_record` in the existing validation GenAI configuration:

```json
{
  "personal_information_review_status": "not_flagged|review_recommended|high_risk|unable_to_assess",
  "personal_information_type_key": null,
  "personal_information_review_reason": null
}
```

These properties are top-level classifier properties and are returned for every file regardless of
`document_kind`.

### Prompt policy

The classifier must distinguish expected PI from inappropriate PI in context.

Expected invoice/WETT/program PI normally includes:

- participant/customer and contractor names;
- ordinary contact details;
- service or installation address;
- invoice and program identifiers;
- costs, taxes, rebates, equipment, work scope, and inspection information;
- signatures when normally required by the document type.

Flag for review when visible information appears unnecessary or unrelated, including:

- unexpected dates of birth;
- unexpected signatures or biometric information;
- unrelated names, addresses, properties, household details, or third parties;
- personal information unrelated to validating the invoice or supporting evidence.

Flag as high risk when visible information includes:

- SIN, passport, driver's licence, health number, or similar government identifiers;
- medical or health details;
- bank accounts, routing information, or full payment-card details;
- passwords, credentials, authentication secrets, or password hints;
- clearly unrelated information about children or other third parties.

The reason must:

- identify the category and location when possible;
- explain why the information appears unnecessary for that document type;
- never reproduce the complete sensitive value;
- use masked or categorical wording;
- remain concise and suitable for an administrator.

Example:

```text
Possible banking information appears on page 2. Banking details are not normally required for
this document type.
```

### Configuration loading

- Load enabled PI types in `sort_order`.
- Include `type_key`, description, and priority in the classifier context.
- Require the classifier to return either one enabled key or `null`.
- Do not duplicate the PI-type list as a second hardcoded application list.
- Keep the status list hardcoded in the prompt schema, application parser, and DDL constraint.

## Classifier Result Processing

Extend the classifier response type/schema and parser with the three new properties.

Validation rules:

- reject an unknown or disabled `personal_information_type_key`;
- resolve a returned key to `personal_information_types.id`;
- require null type/reason for `not_flagged`;
- require a configured type and nonblank reason for `review_recommended` or `high_risk`;
- require null type and a nonblank reason for `unable_to_assess`;
- never silently downgrade malformed output to `not_flagged`;
- use the existing structured-output retry/error behavior when the response is invalid.

The normalized classifier result passed to the Rails pipeline should contain:

```text
personal_information_review_status
personal_information_type_id
personal_information_review_reason
```

## Evidence Promotion

### Initial invoice-package processing

- Copy the invoice-file PI result onto the newly created `invoice_version`.
- Copy each supporting-file PI result onto its promoted `supporting_document`.
- Perform lookup resolution and evidence writes within the existing promotion transaction.
- Do not read the ingest row later to populate the admin viewer.

### Upload-fix processing

- Evaluate every newly uploaded file through the extended classifier.
- Copy new invoice-file results to the new invoice version.
- Copy new supporting-file results to their promoted supporting-document evidence.
- When existing supporting documents are cloned forward to the new invoice version, clone all
  three PI fields unchanged.
- Ensure superseded evidence retains its historical PI result.

### Failure behavior

- A classifier call that cannot produce structurally valid privacy output follows the existing
  classifier failure/retry path.
- A readable but ambiguous file may explicitly return `unable_to_assess`.
- Do not promote `not_flagged` as a fallback for failed parsing or missing configuration.

## API Changes

Extend the admin PDF-viewer serialization for both the invoice version and every supporting
document with:

```json
{
  "personal_information_review_status": "high_risk",
  "personal_information_type": {
    "type_key": "government_identifier",
    "display_name": "Government identifier"
  },
  "personal_information_review_reason": "Possible government identification appears on page 2."
}
```

Requirements:

- source the values only from `invoice_versions` or `supporting_documents`;
- eager-load the lookup row and avoid per-document queries;
- return a null type when status is null, `not_flagged`, or `unable_to_assess`;
- do not add the fields to contractor responses for this MVP;
- do not return raw PI from classifier/audit JSON.

## Admin PDF Viewer

### Invoice accordion

- Add the privacy result to the existing invoice accordion.
- Show nothing when status is `not_flagged` or legacy `NULL`.
- Show a neutral review message for `unable_to_assess`.
- Show an amber badge for `review_recommended`.
- Show a red/high-attention badge for `high_risk`.
- Display the configured PI-type label and safe reason.

### Supporting-document accordions

- Add the same display to each individual supporting-document accordion.
- Keep the result attached to the file that produced it.
- Do not aggregate one supporting document's flag into another document.
- Do not expose raw values, classifier prompts, confidence internals, or ingest records.

### MVP behavior

- Read-only flagging only.
- No automatic deletion, redaction, rejection, revision creation, or contractor notification.
- No individual-finding resolution workflow.
- An administrator decides outside this MVP whether a replacement document is required.

## Automated Testing

### DDL and seed tests

- Schema rebuild succeeds in documented rebuild order.
- Lookup seeds are idempotent and stable.
- Duplicate `type_key` values are rejected.
- Negative `sort_order` values are rejected.
- Status constraints reject unknown values.
- Foreign keys reject unknown PI-type IDs.
- Valid-combination constraints cover every allowed status.
- Legacy all-null evidence remains valid.

### Classifier configuration tests

- Output schema contains all three properties.
- Every document kind returns privacy properties.
- Enabled lookup types are injected in configured order.
- Disabled types are not offered to the model.
- Expected invoice PI does not automatically trigger a flag.
- High-risk and unrelated examples produce the correct status/type shape.
- Reasons do not echo complete sensitive values.

### Classifier parser tests

- Accept each valid status combination.
- Resolve valid `type_key` values to UUIDs.
- Reject unknown and disabled keys.
- Reject flagged statuses without a type or reason.
- Reject `not_flagged` with a type or reason.
- Reject `unable_to_assess` with a type.
- Preserve the reason exactly after validation.

### Promotion tests

- Initial invoice classifier results persist to `invoice_versions`.
- Initial supporting-file results persist to `supporting_documents`.
- Multiple supporting files retain independent results.
- Upload-fix invoice results persist to the new invoice version.
- Newly uploaded supporting evidence receives its new classifier result.
- Cloned supporting evidence retains all three existing PI fields.
- Superseded evidence remains historically unchanged.
- No admin serializer reads ingest rows as evidence.

### API tests

- Admin invoice response includes the invoice privacy result.
- Admin supporting-document response includes each file's privacy result.
- Lookup label and key serialize correctly.
- Null/not-flagged behavior is stable.
- Contractor responses do not expose the fields.
- Query-count coverage prevents an N+1 lookup regression.

### Frontend tests

- Invoice flag renders in the invoice accordion.
- Supporting-document flags render only in their corresponding accordions.
- Amber and red treatments map to the correct statuses.
- `not_flagged` and legacy null values add no visual noise.
- `unable_to_assess` renders as review-needed, not as high risk.
- Long safe reasons wrap without breaking the accordion layout.
- No raw classifier JSON or ingest data appears.

## End-to-End Testing

Use the synthetic packages under:

```text
claims_ai_service_documentation/Test Data/PI-tests
```

### Case 1: PI added to the invoice

Upload:

```text
PI-tests/invoiceproblem/ALLIAN~1.PDF
```

Expected:

- package resolves to one invoice;
- no additional GenAI call is introduced;
- invoice classification still identifies the invoice and upgrade type;
- the invoice version receives `high_risk`;
- primary type resolves to `government_identifier` under the configured priority;
- the reason identifies the added PI page without reproducing the identifier;
- the admin invoice accordion displays the red privacy flag;
- no supporting-document flag is created.

### Case 2: Children and names in a supporting JPEG

Upload both files from:

```text
PI-tests/invoicefinebutbadjpegofchildren
```

Expected:

- the PDF resolves as the invoice and is not flagged;
- the JPEG resolves as a supporting document;
- the JPEG receives `high_risk`;
- primary type resolves to `unrelated_third_party_information`;
- the reason identifies visible children with names/ages as unrelated to the supporting evidence;
- the flag appears only in the JPEG supporting-document accordion;
- the underlying energy-label routing behavior continues to work.

### Case 3: PI added to the WETT report

Upload both files from:

```text
PI-tests/invoicefinebutwettproblem
```

Expected:

- the invoice is not flagged;
- the WETT PDF remains classified and routed as `wett_report`;
- the WETT supporting document receives `high_risk`;
- primary type resolves to `authentication_secret` under the configured priority;
- the reason mentions the synthetic PI page without copying the password hint;
- WETT extraction and later rule evaluation continue normally;
- the flag appears only in the WETT supporting-document accordion.

### Clean regression case

Run a known clean invoice package and a known clean invoice-plus-supporting-document package.

Expected:

- promoted evidence receives `not_flagged`;
- no privacy badge is shown;
- classification, routing, extraction, common rules, and upgrade rules are unchanged;
- no additional GenAI request is present in step-run history;
- existing processing cost and call-count formulas remain unchanged except for the small classifier
  prompt/output token increase.

### Upload-fix regression

- Submit a flagged package.
- Upload a corrected replacement file.
- Confirm the new evidence receives its own PI assessment.
- Confirm retained/cloned supporting evidence preserves its prior assessment.
- Confirm the admin viewer displays only the current invoice version's evidence while historical
  versions retain their audit values.

### Browser acceptance

- Open each processed package in the admin PDF viewer.
- Expand the invoice and every supporting-document accordion.
- Confirm the badge, type label, reason, colour, wrapping, and per-file placement.
- Confirm unflagged files remain visually unchanged.
- Confirm the contractor PDF viewer remains unchanged.
- Confirm direct document retrieval and existing viewer controls still work.

## Operational Validation

- Compare GenAI step counts before and after implementation; they must be identical for the same
  package shape.
- Compare classifier latency and token usage to quantify the small prompt/output increase.
- Review false positives on normal participant names, addresses, emails, phone numbers, and
  signatures expected for the document type.
- Review false negatives across the three synthetic test packages.
- Record the classifier model deployment and reasoning setting used for acceptance.
- Require product/privacy-owner approval of the PI-type descriptions and status semantics before
  production enablement.

## Acceptance Criteria

- Exactly one new lookup table exists.
- Exactly three new fields exist on each evidence table.
- No new GenAI call exists.
- The classifier produces one validated per-file PI result.
- Evidence promotion persists the result to the correct evidence table.
- Ingest tables are never used as evidence by the API or UI.
- Initial upload and upload-fix paths behave consistently.
- Admin invoice and supporting-document accordions display the correct per-file result.
- Contractor behavior is unchanged.
- All automated and end-to-end cases above pass.

## Implementation Verification

- The documented claims-schema rebuild completed successfully in the local Docker database.
- The focused Rails suite completed with 9 examples and 0 failures, covering result validation,
  evidence promotion, admin-only API serialization, contractor non-exposure, and upload-fix
  cloning.
- The Vite production build completed successfully.
- The modified invoice completed the full pipeline with `high_risk` and
  `government_identifier`.
- The clean invoices in both mixed-file packages completed with `not_flagged`.
- The children JPEG completed with `high_risk` and
  `unrelated_third_party_information` after tightening the child/minor severity instruction.
- The modified WETT report completed with `high_risk` and `authentication_secret`.
- Every live package completed with zero failed files.
- Step-run inspection confirmed exactly one classifier step per uploaded file and no additional
  PI-specific GenAI step.
