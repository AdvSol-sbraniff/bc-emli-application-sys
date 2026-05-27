# AI Supporting Documents Supplement Plan

Date: 2026-05-25

Status: planning only. No schema, OCR, GenAI, or UI changes are made by this document.

## Required Companion Artifact

This plan now depends on:

- `claims_ai_service_documentation/esp_requirements_impl_tracker_2026.md`

That markdown tracker should be treated as the working audit ledger for supplement design. The older DOCX is only a legacy snapshot. It now records, per requirement:

- evidence sources required
- intended check style
- likely located fields required
- missing supplement-path coverage

This supplement plan should not drift away from that tracker.

## Purpose

Capture the current agreed direction for handling supporting-document PDFs as first-class evidence in the invoice validation system.

This plan exists because the current invoice path is already structured, but supplement/supporting-document processing is not.

## Current Confirmed State

### Invoice path today

Current invoice flow already does the following:

1. OCR the invoice PDF with Azure Document Intelligence `prebuilt-invoice`.
2. Store raw OCR output in `claims.invoice_versions.di_raw_json`.
3. Populate first-class invoice fields and line items from that raw DI payload.
4. Inject invoice `di_raw_json` into the GenAI context window for classifier and upgrade-type rule evaluation.

Relevant current files:

- `app/jobs/claims/run_ocr_job.rb`
- `app/jobs/claims/run_genai_job.rb`
- `claims.invoice_versions.di_raw_json`

### Supporting-document path today

Current supporting-document handling is much more limited.

Today:

- `claims.supporting_documents` exists
- it stores document storage metadata
- it does not currently store OCR/raw-read JSON for each supporting document
- there is currently no parallel OCR/evidence pipeline for supporting PDFs comparable to the invoice pipeline

## Requirements Interpretation

The current ESP requirements imply a real family of supplement-dependent checks.

Examples include:

- manufacturer label photos for windows/doors
- before/after photos
- WETT reports
- heat-load calculations
- fossil-fuel removal proof
- permit / utility / AHJ proof
- floor plans and similar supporting materials

These are not well modeled as invoice-only checks.

They are better understood as:

1. supporting document existence checks
2. supporting document classification/content checks
3. supporting document extraction/value/table checks

## Core Agreed Direction

### 1. Supporting documents should get their own DI pass

Supporting PDFs should not rely on invoice OCR artifacts.

They do need their own Azure Document Intelligence pass during intake so the classifier can reason over each file independently.

Important v1 refinement:

- own DI pass: yes
- guaranteed persisted raw OCR/read artifact model: not yet
- v1 only requires enough DI output to support per-file triage classification

### 1a. Final upload UX should be single-drop, not separate contractor upload steps

Current admin/application flows are split between invoice upload and supporting-document upload, but the target product direction is:

- one drag-and-drop upload experience
- invoices and supporting PDFs can be uploaded together
- backend classification decides what each file is

This means the contractor should not have to choose a separate "invoice upload" step and then a second "supporting document upload" step in the final workflow unless a later business requirement forces that split.

### 2. Use Azure Document Intelligence, but keep the v1 persistence light

For uploaded mixed bundles, the agreed direction is:

- run Azure Document Intelligence `read` on each uploaded file first
- let the classifier decide whether the document is an invoice or a supplement based on that `read` output
- if exactly one file is classified as invoice, run one follow-up Azure Document Intelligence `prebuilt-invoice` pass for that resolved invoice only
- revisit supplement-specific DI model selection later only if sample supplement accuracy is poor

Reason:

- v1 optimization is higher-quality document-kind triage without forcing every supplement through an invoice-shaped interpretation model
- `read` is a better neutral substrate for invoice-vs-supplement classification
- `prebuilt-invoice` remains available for the one real invoice where first-class invoice fields and line items matter
- DI-model specialization for supplement families is a later tuning step, not a day-one requirement

### 3. Do not concatenate all supplement raw OCR into one giant blob

We specifically do **not** want:

- every supporting document OCR payload concatenated together
- then injected wholesale into one large upgrade-type LLM call

Problems with that approach:

- too much token noise
- poor relevance filtering
- harder reasoning
- more pressure toward full-size model usage
- weaker path to later `mini` model evaluation

### 4. Extend the existing classifier into one document-triage classifier

The current invoice classifier should become the single per-file triage classifier for mixed upload bundles.

Preferred classification architecture:

For each uploaded PDF:

1. run Azure Document Intelligence `read` first
2. pass the `read` output into one classifier call
3. classifier decides:
   - `document_kind = invoice | supplement | unknown`
4. if `document_kind = invoice`
   - return the current invoice upgrade-type classification result
5. if `document_kind = supplement`
   - return the supplement type classification result

So the intended model is:

- one DI pass per uploaded file
- one classifier call per uploaded file
- not a code heuristic pass followed by separate invoice-vs-supplement logic

Document-triage classifier purpose:

- decide whether the PDF is an `invoice`, `supplement`, or `unknown`
- if invoice, identify the upgrade type(s)
- if supplement, identify the supplement type

Important scope limit:

- this classifier is still a classification/triage call
- it is not the place for final rule adjudication
- final invoice rule evaluation remains in the existing common + per-upgrade-type validation calls

Examples of supplement classes:

- manufacturer_label_photo
- before_after_photo_set
- wett_report
- heat_load_calculation
- permit_document
- utility_service_upgrade_proof
- fossil_fuel_removal_proof
- floor_plan
- unknown_other

### 5. Build a curated supplement evidence pack only after v1 supplement typing works

The main upgrade-type GenAI rulecheck should receive curated supplement evidence, not the raw union of everything.

That means:

- keep raw OCR JSON persisted
- but build a compact evidence pack for the actual GenAI call

Likely later evidence-pack contents:

- supporting document id
- filename
- supplement classifier result
- relevant page numbers
- relevant extracted text snippets
- relevant extracted table snippets
- maybe selected raw JSON fragments where needed

### 6. Keep final upgrade-type reasoning cohesive

The current preferred direction is:

- one main upgrade-type GenAI evaluation call
- that call sees:
  - invoice OCR evidence
  - database facts
  - curated supplement evidence

This is preferred over many independent final supplement adjudication calls.

Reason:

- invoice and supplement evidence often need to be reasoned about together
- cohesion matters

Important refinement:

- v1 supplement work does **not** require raw supplement OCR to be injected into upgrade-type calls
- v1 only needs typed supplement presence on the parent invoice
- curated supplement evidence injection becomes a later stage if real sample documents prove it is necessary

### 7. Allow targeted supplement subcalls only when needed, and not in v1

We may still introduce additional supplement-specific LLM calls when a supplement type is particularly complex.

Examples:

- dense heat-load calculation reports
- complicated structured spec sheets
- large tabular supporting documents

If this happens, the preferred pattern is:

1. supplement subcall extracts structured evidence
2. main upgrade-type call consumes that structured evidence

Not:

- several independent final pass/fail calls that later need reconciliation

## Recommended Architecture

## Stage 0. Mixed-file upload intake

For each uploaded PDF in the same drag-and-drop batch:

1. store the file
2. run Azure Document Intelligence `read`
3. run the document-triage classifier on the `read` output
4. branch into invoice or supplement processing

The system should not assume every uploaded PDF is an invoice.

Bundle gate:

- the bundle must contain exactly one file classified as `invoice`
- if zero invoices are found, fail intake and require correction
- if more than one invoice is found, fail intake and require correction
- only the exactly-one-invoice path auto-continues
- after that gate passes, run one follow-up `prebuilt-invoice` pass for the resolved invoice only

## Stage 1. Supporting document storage

Keep `claims.supporting_documents` as the uploaded-file table.

We do need supplement-processing persistence beyond storage metadata, but the current v1 target is narrow.

Recommended v1 additions:

- add `supporting_document_type_id`
- add classification status/confidence/reason fields
- keep OCR artifact persistence minimal and implementation-friendly

Current leaning:

- start by extending `claims.supporting_documents`
- do not add `claims.supporting_document_located_fields` in v1
- do not commit to a supplement OCR child-results table until we prove we need persisted supplement OCR beyond typing/classification

Related runtime-evidence note:

- invoice-PDF runtime located values stay in `claims.invoice_version_located_fields`
- v1 supplement work does not require a parallel supplement-located-fields table
- if a future supplement-field table ever becomes justified, it should still be invoice-level rather than invoice-version-level

## Stage 2. Per-file document triage classifier

For each uploaded PDF after DI `read`:

1. call the existing classifier family with an expanded schema
2. get back:
   - `document_kind`
   - `document_kind_confidence`
   - if invoice: upgrade-type classification
   - if supplement: supplement type classification

Recommended output shape:

- `document_kind`
- `document_kind_confidence`
- `document_kind_reason`
- `invoice_upgrade_types[]` only when `document_kind = invoice`
- `supplement_type_key` only when `document_kind = supplement`
- `needs_review` flag for low-confidence edge cases

This replaces the older idea of:

- a universal first-pass classifier
- then a separate invoice classifier
- then a separate supplement classifier

For v1, one classifier call per file is the preferred simplification.

## Stage 3. Invoice path after triage

For the one file classified as invoice:

1. run one follow-up Azure Document Intelligence `prebuilt-invoice` call for that resolved invoice
2. persist that invoice-model artifact on `claims.invoice_versions.di_raw_json`
3. continue with the current invoice path unchanged after that point
4. current invoice classifier result feeds the current common + upgrade-type validation flow
5. current code rules and current per-upgrade-type GenAI calls remain the main adjudication path

This is a major design constraint:

- do not fork a brand-new invoice validation path just because mixed-file bundle intake is added
- the only loopback is the single invoice-model DI pass on the one resolved invoice
- the bundle resolver should hand the invoice back into today’s proven pipeline

## Stage 4. Supplement typing

For every non-invoice file in the bundle:

1. create a `claims.supporting_documents` row under the resolved invoice
2. map `supplement_type_key` to `claims.supporting_document_types`
3. persist:
   - `supporting_document_type_id`
   - classification status
   - classification confidence
   - classification reason
4. allow manual override if classifier confidence is low or the type is wrong

Important:

- supplement files stop at `read` + type classification in v1
- they do not get a second invoice-model DI pass

Examples of target supplement types:

- `manufacturer_label_photo`
- `preapproval_notice`
- `preapproval_quote`
- `wett_report`
- `f280_heat_load_calculation`
- `utility_invoice`
- `product_spec_sheet`
- `before_after_photo_set`

## Stage 5. V1 runtime use of supplements

For v1, runtime supplement use should stay narrow.

The current preferred direction is:

1. invoice validation runs primarily from invoice evidence, code facts, and existing upgrade-type logic
2. supplement docs contribute typed presence/inventory only
3. upgrade-type rules may later ask whether specific supplement families are present

Do not, in v1:

- inject raw supplement OCR into the upgrade-type call by default
- add a `claims.supporting_document_located_fields` table
- add supplement extraction subcalls
- duplicate invoice-side located fields onto the supplement side

## Rulecheck Implications

Supplement-dependent checks should likely become a real rule family.

Conceptual buckets:

### 1. Supplement existence rules

Examples:

- supporting document uploaded
- required photo set present
- required report present

### 2. Supplement classification/content rules

Examples:

- document appears to be a WETT report
- document appears to be a manufacturer label photo
- document appears to be a heat-load calculation

### 3. Supplement extraction/value rules

Examples:

- U-factor/spec appears in a supplement table
- heat-load report contains required values
- permit/supporting document contains required project or equipment details

Current design refinement:

- these supplement extraction/value rules are explicitly later-stage candidates
- they are not required for the first supplement-typing slice

### 4. Hybrid invoice-plus-supplement rules

Examples:

- invoice identifies product line, supplement confirms label/spec
- invoice shows replacement work, supplement confirms removal proof
- invoice suggests upgrade, supplement confirms mandatory supporting evidence

## Model-Choice Implications

If we dump all supplement OCR raw JSON into one large call:

- token load rises
- reasoning noise rises
- `mini` becomes less plausible

If we classify and curate:

- context becomes tighter
- relevance improves
- future `mini` evaluation becomes more realistic

So the current architecture direction supports:

- DI `read` first on every file
- one triage classifier per file second
- one follow-up `prebuilt-invoice` pass for the resolved invoice third
- current invoice adjudication path fourth
- later curated supplement evidence only if needed

## Open Questions

- Should supplement OCR artifacts live directly on `claims.supporting_documents` or in a child results table if we later want persisted raw OCR?
- Should the triage classifier return only one supplement type or also a small ranked candidate list?
- Should supplement docs also be linked to specific upgrade types explicitly after classification, or is invoice parentage plus supplement type enough?
- Which supplement types deserve later extraction subcalls versus staying subtype-only?
- How should supplement evidence be shown in the admin UI so admins can see type, confidence, and any manual override?
- For which requirement families do we only need `supporting_documents.supplement_type`, and for which do we later need true extracted supplement fields?
- Which of those later extracted supplement fields are strong enough to justify `claims.supporting_document_located_fields` rather than staying at supplement-subtype / evidence-presence level?

## Near-Term Next Questions

The next design conversations should likely focus on:

1. supplement-side schema shape
2. triage-classifier output shape
3. mixed-bundle exactly-one-invoice error handling
4. which requirement families become first supplement-type-only candidates

## Working Conclusion

So far, the agreed direction is:

- uploaded bundles should allow one invoice PDF plus many supplement PDFs together
- Azure Document Intelligence `read` should run on every uploaded file first
- the existing classifier should be extended into a per-file document-triage classifier
- the bundle should auto-continue only when exactly one file is classified as `invoice`
- the resolved invoice should get one follow-up `prebuilt-invoice` pass and then continue through today's current invoice pipeline
- each non-invoice file should become a `claims.supporting_documents` row and receive a classified supplement type
- v1 supplement work should stop at supplement typing plus persistence of that type on `claims.supporting_documents`
- raw supplement OCR, curated evidence packs, supplement extraction subcalls, and `claims.supporting_document_located_fields` are all later-stage additions only if real sample documents justify them
