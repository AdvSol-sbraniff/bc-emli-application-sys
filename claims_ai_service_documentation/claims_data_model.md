# Claims AI Service Data Model

Status: draft in progress

Purpose: provide a readable, stable reference for the claims AI database model. This document is intentionally being built in stages. The first pass defines the numbered table of contents, table inventory, and writing plan only.

## 1. Purpose And Audience

### 1.1 Document Purpose

This document explains the data model for the claims AI service. Its goal is to make the database understandable to people who need to maintain, test, review, or extend the claims AI pipeline.

The model is not just a list of tables. It represents a workflow: uploaded PDF packages are staged, read by Document Intelligence, triaged into invoice and supporting-document records, enriched with located fields, evaluated by GenAI and code rules, and summarized for claim review. The document should help a reader understand both the tables and the runtime story those tables support.

The core mental model is that the schema has three connected worlds: an evidence world that stores what happened for a specific invoice package, a registry world that defines what the system should look for, compare, extract, and validate, and a download/import world that snapshots external reference lists for deterministic comparison. The pipeline uses registry and download/import data to produce evidence-world rows.

The document is also intended to reduce future ambiguity around recurring terms such as invoice, invoice version, ingest document, supporting document, upgrade type, common rules, located fields, rulechecks, and product-list matches.

### 1.2 Intended Readers

The primary audience is technical and semi-technical staff who need to understand how claims AI data is stored and how records relate to each other.

Intended readers include:

- Developers maintaining the Rails, Sidekiq, and React claims AI features.
- Database administrators or analysts inspecting claims AI records directly.
- Product owners and business analysts validating that the data model supports ESP review requirements.
- QA testers designing repeatable test cases for invoice bundles, supporting documents, reruns, and rule outcomes.
- Future AI assistants or developers onboarding into the project.

This document assumes the reader understands basic database concepts such as tables, primary keys, foreign keys, parent/child relationships, and JSON columns. It does not assume deep familiarity with the Claims AI codebase.

### 1.3 What This Document Covers

This document covers the `claims` schema created by `claims_ai_service_ddl/2_create_schema.sql` and the closely related seed files that define upgrade types, supporting document types, rules, located fields, and GenAI prompt configuration.

The main topics are:

- The claim/invoice lifecycle from upload through final AI advice.
- How raw uploaded PDFs are staged in ingest tables before becoming processed invoice or supporting-document records.
- How invoice versions preserve reruns and OCR/GenAI outputs over time.
- How supporting documents are classified, promoted, and given extracted located fields.
- How GenAI rules and deterministic code rules are configured and mapped to upgrade types.
- How rule outputs are stored as invoice version rulechecks.
- How external reference lists such as AHRI, NEEA, AWHP, and OHPA support product-list validation.
- How eligibility-code facts are brought into the claims AI case context.
- How history tables support auditability for rule and located-field configuration.

The table catalog in section 12 is intended to become a practical reference for every table in the claims schema.

### 1.4 What This Document Does Not Cover

This document does not attempt to document every application table in the broader application database. It focuses on the claims AI service data model and only mentions non-claims tables when they are needed to explain a relationship, such as contractors, users, or uploaded file storage.

This document also does not replace:

- The ESP requirements tracker.
- The seed SQL files.
- The Rails models and services.
- The React admin screens.
- The OpenShift or deployment runbooks.
- The PDF test-file library.

Where those artifacts matter, this document should link or refer to them, but it should not duplicate them in full.

This document is also not the final legal or program-policy interpretation of ESP rules. It describes how the system stores and evaluates data. Business interpretation remains with the program, product owner, and review process.

### 1.5 Reading Conventions

Table names are written with their schema-qualified names, such as `claims.invoices` or `claims.invoice_versions`.

Column names are written in code formatting, such as `invoice_id`, `invoice_version_id`, `source_engine`, or `rule_result`.

Rule keys, upgrade type keys, supporting document type keys, and located field keys are also written in code formatting, such as `air_source_heat_pump_electric`, `utility_bill`, `hp_ahri_reference`, or `ashp_electric_existing_heat_context_present`.

The word invoice can mean different things depending on context. In this document:

- `claims.invoices` means the claim-level invoice record, which owns the overall invoice review state.
- `claims.invoice_versions` means a processed invoice PDF/version, including OCR, DI invoice output, located fields, and validation results.
- `claims.ingest_documents` means raw staged PDFs before the pipeline has definitively promoted them into invoice or supporting-document records.
- `claims.supporting_documents` means processed supporting documents that have been classified, promoted, and attached to the claim invoice.

The word common refers to claim-level checks that are not specific to one upgrade type. The current schema represents common checks through an `invoice_upgrade_types` row with key `common`. Conceptually, this behaves more like claim-level validation scope than a physical upgrade installed in a home.

Examples in later sections should use realistic but safe sample values. They should illustrate relationships and lifecycle states, not expose real homeowner data.

## 2. Big Picture Model

### 2.1 One-page conceptual model

At the highest level, the claims AI model separates the claim being processed from the registry of rules and field definitions used to evaluate that claim, plus the downloaded external reference data used for deterministic comparisons.

The shortest useful mental model is:

```text
Registry world: what should the system look for, compare, extract, or validate?
Download/import world: which external reference files were loaded, and what rows did they contain?
Evidence world: what did the system find, decide, store, or show for this invoice?
```

The pipeline sits between these worlds. It reads registry tables, download/import tables, source documents, and database facts, then writes evidence tables.

The central runtime chain is:

```text
claims.sessions
  -> claims.invoices
       -> claims.invoice_versions
            -> claims.lineitems
            -> claims.invoice_version_located_fields
            -> claims.invoice_version_rulechecks
            -> claims.invoice_version_upgrade_types
       -> claims.supporting_documents
            -> claims.supporting_document_located_fields
       -> claims.ingest_documents

claims.ingest_runs
  -> claims.ingest_documents
  -> claims.ingest_step_runs
```

The main registry/configuration tables sit beside that runtime chain:

```text
claims.invoice_upgrade_types
claims.supporting_document_types
claims.supporting_document_type_upgrade_types
claims.supporting_document_type_located_fields
claims.code_rules
claims.code_rule_upgrade_types
claims.code_located_fields
claims.genai_rules
claims.genai_rule_upgrade_types
claims.genai_located_fields
claims.genai_located_field_upgrade_types
claims.validationgenai_config
claims.users_eligibilitycodes
```

The main download/import reference families follow a separate source/import-run/product pattern:

```text
claims.ahri_sources / claims.ahri_import_runs / claims.ahri_products
claims.neea_sources / claims.neea_import_runs / claims.neea_products
claims.awhp_sources / claims.awhp_import_runs / claims.awhp_products
claims.ohpa_sources / claims.ohpa_import_runs / claims.ohpa_products
```

`claims.invoices` is the claim-level record. It owns the overall processing and review status. `claims.invoice_versions` is the processed invoice PDF/version under that claim. `claims.ingest_documents` is the staging table for raw uploaded package files before the system knows whether each file is the invoice, a supporting document, or an unknown document. `claims.supporting_documents` stores promoted supporting documents after classification.

Most AI and code outputs are stored against an `invoice_version_id`, not directly against `claims.invoices`. This matters because a claim can be reprocessed, and each reprocessing attempt can create a new invoice version with its own OCR output, GenAI output, rulechecks, located fields, line items, and product-list matches.

### 2.2 The three worlds: evidence, registry, and downloads

The claims AI schema is easiest to understand as three connected worlds.

The evidence world stores the invoice-specific record of what happened. It includes staged uploaded files, processed invoice versions, supporting documents, extracted values, rule outcomes, product-list matches, GenAI context windows, and review messages. Evidence-world rows answer questions such as:

- Which PDFs did the contractor upload?
- Which file was promoted as the invoice?
- Which supporting documents were attached?
- Which upgrade types were classified for this invoice version?
- Which facts were located in the invoice or supporting documents?
- Which rulechecks passed, warned, or failed?
- Which product-list row was matched?
- What exact GenAI context and raw response were used for this run?

The registry world stores reusable definitions and lookup data. It includes upgrade types, supporting-document types, rule definitions, located-field definitions, prompt configuration, rule/field-to-upgrade mappings, supporting-document mappings, and eligibility-code records. Registry-world rows answer questions such as:

- Which upgrade types does the system recognize?
- Which supporting-document types can be classified?
- Which facts should be extracted for this upgrade or document type?
- Which GenAI or code rules apply to this upgrade type?
- Which database facts should be supplied to GenAI as case context?

The download/import world stores external reference material that has been brought into the claims AI database. It includes source definitions, import runs, source-file storage metadata, import status, and normalized product rows. Download/import-world rows answer questions such as:

- Which external product list did this data come from?
- When did the import run?
- Did the import succeed or fail?
- Which source file was used?
- How many rows were imported?
- Which product rows are current for deterministic matching?

The relationship is directional: registry rows guide runtime processing, download/import rows supply reference comparison material, and evidence rows record the result of processing one invoice package. The system should not treat registry rows as proof that something happened on a claim. It should not treat download rows as invoice evidence until a product match is stored on an invoice version. It should not treat evidence rows as reusable definitions for future claims.

The diagrams below show this split visually. They are intentionally simplified; they show the mental model rather than every column or every supporting table.

![Evidence schema](<evidence schema.png>)

![Registry schema](<registry schema.png>)

![Download schema](<download schema.png>)

### 2.3 Main claim-processing lifecycle

The normal package-processing lifecycle starts when a contractor uploads one or more PDF files for a claim. The system creates a claim-level `claims.invoices` row early so the UI can show a stable invoice row and status while the package is still being interpreted.

The upload package is tracked by `claims.ingest_runs`. Each uploaded file is represented by one `claims.ingest_documents` row. During the first pass, staged documents are read by OCR and triaged. Triage classifies each file as an `invoice`, `supplement`, or `unknown` using `document_kind`, confidence, and reason fields.

If the package contains exactly one resolved invoice PDF, the system promotes that staged file into a `claims.invoice_versions` row. Document Intelligence output is stored on the invoice version in `di_raw_json`, `di_page_map`, first-class OCR fields, and `claims.lineitems`. The classifier's detected upgrade types are stored in `claims.invoice_version_upgrade_types`.

Supporting files are promoted into `claims.supporting_documents`, typed with `supporting_document_type_id`, and enriched with `claims.supporting_document_located_fields` when the system can extract typed facts from them.

GenAI and code-rule processing then evaluates the invoice version. GenAI produces located fields and rulechecks. Deterministic code produces code-owned facts, product-list matches, and rulechecks. The combined result is summarized on the invoice version through fields such as `genai_result`, `genai_overall_confidence`, and `genai_admin_advice`, while detailed evidence remains in located-field, rulecheck, step-run, line-item, supporting-document, and product-list rows.

The claim-level invoice status moves through processing states such as `upload_in_progress`, `ocr_in_progress`, `genai_in_progress`, `genai_complete`, and failure states such as `ocr_failed` or `genai_failed`. After AI processing, business workflow statuses such as `admin_review_inbox`, `contractor_revision_inbox`, `in_review`, `approved_pending`, `approved_paid`, and `ineligible` describe review outcomes rather than OCR or GenAI execution.

### 2.4 Evidence, registry, and download data

Evidence data is created while a contractor, admin, job, or external service is processing a real claim. Evidence tables include `claims.sessions`, `claims.invoices`, `claims.invoice_versions`, `claims.lineitems`, `claims.ingest_runs`, `claims.ingest_documents`, `claims.ingest_step_runs`, `claims.supporting_documents`, `claims.supporting_document_located_fields`, `claims.invoice_version_located_fields`, `claims.invoice_version_rulechecks`, and `claims.invoice_version_upgrade_types`.

Registry data defines what the runtime should look for and how outputs should be organized. Registry tables include `claims.invoice_upgrade_types`, `claims.supporting_document_types`, `claims.supporting_document_type_upgrade_types`, `claims.supporting_document_type_located_fields`, `claims.code_rules`, `claims.code_rule_upgrade_types`, `claims.code_located_fields`, `claims.genai_rules`, `claims.genai_rule_upgrade_types`, `claims.genai_located_fields`, `claims.genai_located_field_upgrade_types`, and `claims.validationgenai_config`.

Download/import data is external reference material that has been brought into the claims AI database. Product-list source, import-run, and product tables are download/import data: `claims.ahri_sources`, `claims.ahri_import_runs`, `claims.ahri_products`, `claims.neea_sources`, `claims.neea_import_runs`, `claims.neea_products`, `claims.awhp_sources`, `claims.awhp_import_runs`, `claims.awhp_products`, `claims.ohpa_sources`, `claims.ohpa_import_runs`, and `claims.ohpa_products`.

`claims.users_eligibilitycodes` is reference-like from the claims AI perspective: the GenAI and code-rule pipeline uses it as participant eligibility context, but it is not produced by invoice OCR. Unlike the downloaded product lists, it is not modeled as source/import/product data.

This separation keeps the model understandable. Evidence rows answer "what happened for this claim?" Registry rows answer "what should the system evaluate?" Download/import rows answer "what external reference data was loaded and made available for comparison?"

### 2.5 Registry tables, download tables, and evidence tables

A useful way to read the model is to distinguish registry tables, download/import tables, and evidence tables.

Registry tables define reusable concepts. `claims.invoice_upgrade_types` defines normalized AI upgrade types such as `common`, `air_source_heat_pump_electric`, `heat_pump_water_heater`, and `electrical_service_upgrade`. `claims.supporting_document_types` defines reusable supporting-document categories such as `utility_bill`, `manufacturer_label_photo`, or `permit_document`. Rule and located-field definition tables define the keys, prompts, and upgrade-type mappings used by GenAI and deterministic code.

Download/import tables define external comparison snapshots. Source tables say where a product list comes from. Import-run tables say which file was loaded, when, and whether it succeeded. Product tables store the imported rows that deterministic code can search.

Evidence tables store what happened for one invoice version, supporting document, or ingest attempt. `claims.invoice_version_rulechecks` stores rule outcomes. `claims.invoice_version_located_fields` stores invoice facts found by GenAI or code. `claims.supporting_document_located_fields` stores extracted facts from a promoted supporting document. `claims.ingest_step_runs` stores individual job attempts, raw responses, errors, timings, token usage, and the GenAI `context_window_json` used for audit.

Evidence tables should be read as point-in-time records. If registry configuration or downloaded reference data changes later, historical evidence rows still describe the output produced during that run. This is why the runtime model stores keys, values, confidence, evidence text, product match foreign keys, and raw JSON outputs rather than relying only on current registry or current-product rows.

### 2.6 Invoice versions, reruns, and reprocessing

`claims.invoices` represents the durable claim-level invoice record. `claims.invoice_versions` represents a particular processed invoice PDF under that claim. The version number is stored in `invoice_versionno`, and the schema requires version numbers to start at `1` and be unique within an invoice.

This version layer is what makes reruns and replacements possible. A claim can keep its stable `claims.invoices.id` while a new invoice version is created for a replacement PDF or reprocessing pass. The new version gets its own storage key, OCR JSON, first-class OCR fields, line items, GenAI output, located fields, rulechecks, upgrade-type classifications, and product-list match foreign keys.

The application can then show the current invoice version while preserving previous versions for comparison or audit. The `claims.v_current_invoice_versions` view supports that current-version read path.

Not every rerun means the same thing. A full OCR rerun refreshes Document Intelligence output and downstream GenAI/code outputs. A GenAI rerun can reuse existing OCR/classifier data while producing new GenAI step runs, located fields, and rulechecks. A package redo can stage a new bundle of files, resolve the invoice again, and promote new supporting documents. Sections 3 and 4 describe those paths in more detail.

### 2.7 Supporting documents and extracted facts

Supporting documents are handled in two phases. During package intake, each uploaded file is first a `claims.ingest_documents` row. At that point, the system may only know the file's storage location, OCR-read output, and classifier result. After triage, supplement files can be promoted into `claims.supporting_documents`.

`claims.supporting_document_types` defines the categories the system recognizes. `claims.supporting_document_type_upgrade_types` maps each supporting-document type to the upgrade types where it is applicable. That mapping is about applicability; it does not by itself decide every required-versus-optional business rule.

`claims.supporting_document_type_located_fields` defines which facts should be extracted for a given supporting-document type. For example, a utility account document and a manufacturer label photo may need different extracted fields. Runtime values are stored in `claims.supporting_document_located_fields`, with source engine, value type, confidence, page, polygon, and evidence text.

Supporting-document facts can be summarized into the GenAI case context for the relevant upgrade type. This lets an invoice validation rule use evidence from both the invoice PDF and the attached supporting documents without flattening all documents into one ambiguous blob.

### 2.8 GenAI validation vs deterministic code validation

The model deliberately keeps GenAI validation and deterministic code validation separate while storing their outputs in parallel shapes.

GenAI validation is configured through `claims.validationgenai_config`, `claims.genai_rules`, `claims.genai_rule_upgrade_types`, `claims.genai_located_fields`, and `claims.genai_located_field_upgrade_types`. At runtime, GenAI uses OCR output, database facts, supporting-document summaries, and configured rule/field prompts to produce located fields and rulechecks. The actual context sent to GenAI is auditable through `claims.ingest_step_runs.context_window_json`.

Deterministic code validation is configured through `claims.code_rules`, `claims.code_rule_upgrade_types`, and `claims.code_located_fields`. Code validation is used where the system can make a repeatable database or algorithmic determination, such as matching a product-list reference, applying an eligibility-code fact, or checking a calculated condition.

Both engines write to `claims.invoice_version_rulechecks` using `source_engine` values of `genai` or `code`. Both can also write located facts to `claims.invoice_version_located_fields`. Keeping the output shapes parallel makes the admin review UI simpler while still preserving which engine produced each result.

Rule outcomes use the shared result vocabulary `pass`, `info`, `warn`, and `fail`. GenAI and code do not need to agree on every detail; they provide separate evidence streams that the review experience can present together.

### 2.9 External product-list matching

Some ESP checks depend on external qualified-product lists. The claims AI schema stores these lists as source/import/product families:

- AHRI: `claims.ahri_sources`, `claims.ahri_import_runs`, and `claims.ahri_products`.
- NEEA: `claims.neea_sources`, `claims.neea_import_runs`, and `claims.neea_products`.
- AWHP: `claims.awhp_sources`, `claims.awhp_import_runs`, and `claims.awhp_products`.
- OHPA: `claims.ohpa_sources`, `claims.ohpa_import_runs`, and `claims.ohpa_products`.

Each product-list family separates the stable source definition from individual import runs and imported product rows. This allows the system to know which source was imported, when the import ran, whether it succeeded, and which product rows came from that import.

When code finds a product-list match for an invoice version, the match is stored as a point-in-time foreign key on `claims.invoice_versions`, such as `ahri_product_id`, `neea_product_id`, `awhp_product_id`, or `ohpa_product_id`. Code rulechecks can then explain whether the product-list evidence passed, warned, or failed.

This design keeps product-list imports reusable across claims while keeping the invoice version's match stable for the processed run.

## 3. Core Claim Lifecycle

### 3.1 `claims.sessions`

`claims.sessions` is the claims AI grouping record. It gives the AI subsystem a claims-owned parent for one or more `claims.invoices` rows.

The table is intentionally small:

- `id`
- `created_at`
- `updated_at`

Most business meaning appears in child records. An invoice belongs to a session through `claims.invoices.session_id`. Ingest package runs also carry `session_id`, so the system can connect package processing activity back to the same claims AI grouping.

This table should not be confused with login/session infrastructure from the legacy application. It is part of the `claims` schema and exists so the AI invoice workflow can group claim activity without reshaping old `public.*` tables.

### 3.2 `claims.invoices`

`claims.invoices` is the durable claim-level invoice review record. It is the main row the UI can show while upload, OCR, GenAI, contractor submission, and admin review are moving forward.

This table represents the AI review case for an invoice. It is not just a copy of the old contractor webform. In the old flow, the contractor retyped values from a PDF into a form and admin staff manually compared the form against the PDF. In the claims AI flow, the invoice record anchors the uploaded PDF package, OCR output, AI/code review results, supporting documents, and admin workflow status.

Important columns include:

- `session_id`: links the invoice to `claims.sessions`.
- `contractor_id`: links to the legacy `public.contractors` table so the AI invoice stays connected to the existing contractor account/company.
- `submitter_id`: links to the legacy `public.users` table when the contractor submits the invoice to admin review.
- `system_help_notes`: stores optional system/admin context for review.
- `status`: tracks both processing state and business review state.
- `status_updated_at`: records when the current status was set.
- `submitted_at`: records when the invoice was submitted to admin review.

`claims.invoices` does not store the AI upgrade classification. Upgrade classification is version-specific because it belongs to the processed invoice PDF. The claims AI upgrade lookup is `claims.invoice_upgrade_types`, and the detected/evaluated upgrade types for a specific invoice version are stored in `claims.invoice_version_upgrade_types`.

The allowed invoice statuses can be grouped conceptually:

- Upload/OCR/GenAI processing: `upload_queued`, `upload_in_progress`, `upload_failed`, `upload_complete`, `ocr_queued`, `ocr_in_progress`, `ocr_failed`, `ocr_complete`, `genai_queued`, `genai_in_progress`, `genai_failed`, `genai_complete`.
- Contractor/admin review: `admin_review_inbox`, `contractor_revision_inbox`, `in_review`.
- Terminal or near-terminal business outcomes: `approved_pending`, `approved_paid`, `ineligible`.

The common current path is that AI processing completes with `genai_complete`. The contractor can then submit the invoice, which moves it to `admin_review_inbox`. Admin staff can screen it into `in_review`, request revision back to `contractor_revision_inbox`, approve it to `approved_pending`, and later mark it `approved_paid`.

### 3.3 `claims.invoice_versions`

`claims.invoice_versions` stores a processed invoice PDF version under a claim-level `claims.invoices` row.

An invoice can have more than one version. The stable parent `claims.invoices.id` stays the same, while each processed PDF version gets a separate `claims.invoice_versions` row with its own `invoice_versionno`. The schema requires `invoice_versionno >= 1` and enforces uniqueness on `(invoice_id, invoice_versionno)`.

Important column groups include:

- Parent/version identity: `invoice_id`, `invoice_versionno`.
- PDF storage metadata: `storage_provider`, `storage_key`, `original_filename`, `content_type`, `byte_size`, `sha256`.
- Document Intelligence output: `di_raw_json`, `di_page_map`, first-class OCR fields such as `di_ocr_invoice_id`, `di_ocr_invoice_date`, `di_ocr_vendor_name`, `di_ocr_customer_name`, `di_ocr_invoice_total`, and their page/polygon evidence columns.
- GenAI summary output: `genai_raw_json`, `genai_overall_confidence`, `genai_result`, `genai_admin_advice`.
- Product-list match links: `ahri_product_id`, `neea_product_id`, `awhp_product_id`, `ohpa_product_id`.

`storage_key` is the canonical blob path inside the storage container, not a full signed URL. For example, a key might look like `sessions/11111111-1111-1111-1111-111111111111/pdfs/22222222-2222-2222-2222-222222222222/original.pdf`. The account host, container name, and temporary SAS query string are not stored in this column.

The model keeps both relational extracted values and raw provider JSON. Typed columns and child tables support review, reporting, validation, and UI highlighting. Raw JSON supports audit, debugging, and future re-extraction if the provider output shape matters.

The current version for an invoice is resolved by `claims.v_current_invoice_versions`, which picks the highest `invoice_versionno` and then uses `updated_at` and `id` as tie-breakers.

### 3.4 `claims.lineitems`

`claims.lineitems` stores OCR-extracted invoice line items for one invoice version.

Each row belongs to `claims.invoice_versions` through `invoice_version_id`. The row number within the invoice version is stored as `lineitem_seqno`, and the schema requires it to be unique per invoice version.

The line-item fields are intentionally OCR-shaped:

- `ocr_description`
- `ocr_quantity`
- `ocr_unit_price`
- `ocr_amount`
- page and polygon columns for each of those values

This lets the review UI show what Document Intelligence found and where it found it on the invoice PDF. The row is not meant to replace the original PDF; it is a structured, reviewable extraction from that PDF.

`invoice_upgrade_type_id` links a line item to `claims.invoice_upgrade_types`. When line items are first extracted from Document Intelligence, they may default to `common`. After classifier results are applied, the system can stamp line items with detected upgrade types where the classifier can match a line item to an upgrade domain.

For example, a multi-upgrade invoice might have one line item for a heat pump and another line item for electrical service work. Both line items belong to the same `invoice_version_id`, but each can point at a different `invoice_upgrade_type_id`.

### 3.5 `claims.invoice_upgrade_types`

`claims.invoice_upgrade_types` is the claims AI lookup table for upgrade domains. It is the normalized list used by rules, located fields, supporting-document mappings, line items, and invoice-version upgrade classifications.

Important columns are:

- `id`
- `upgrade_type_key`
- `description`
- `created_at`
- `updated_at`

The key column is `upgrade_type_key`. Example keys include:

- `common`
- `windows_doors`
- `air_source_heat_pump_electric`
- `air_source_heat_pump_wood`
- `air_source_heat_pump_gas_propane`
- `air_source_heat_pump_oil`
- `dual_fuel_ducted_heat_pump`
- `air_to_water_heat_pump`
- `combined_space_water_heat_pump`
- `heat_pump_water_heater`
- `electrical_service_upgrade`

The `common` row is special. It represents claim-level/common invoice evidence and checks that are not tied to one physical upgrade. It is still stored in the same lookup table so registry and evidence tables can use one consistent foreign key shape.

This table is separate from legacy `public.*` classification tables. For the claims AI data model, `claims.invoice_upgrade_types` is the source of truth for AI upgrade domains.

### 3.6 `claims.invoice_version_upgrade_types`

`claims.invoice_version_upgrade_types` records which claims AI upgrade types were detected or evaluated for a specific invoice version.

Important columns include:

- `invoice_version_id`: the processed invoice PDF version being classified or evaluated.
- `invoice_upgrade_type_id`: the claims AI upgrade type.
- `source_engine`: either `classifier` or `genai`.
- `call_status`: one of `classified`, `queued`, `in_progress`, `succeeded`, `failed`, or `skipped`.
- `confidence`: a 0 to 100 confidence score.
- `result`: optional summary outcome using `pass`, `info`, `warn`, or `fail`.
- `admin_advice`: optional human-facing guidance.
- `raw_json`: raw engine output for that upgrade-type classification or evaluation.

The schema enforces uniqueness on `(invoice_version_id, invoice_upgrade_type_id, source_engine)`. This means one invoice version can have a classifier row and a GenAI row for the same upgrade type, but it cannot have duplicate classifier rows for the same upgrade type.

Classifier rows answer "which upgrade types appear to be present in this invoice?" GenAI rows can answer "what was the result/advice for this upgrade type?" Detailed validation outputs still live in `claims.invoice_version_rulechecks` and `claims.invoice_version_located_fields`.

### 3.7 Example: first invoice submission

Consider a contractor uploading a heat pump invoice package.

The claims AI flow creates a `claims.sessions` row and a `claims.invoices` row. The invoice initially acts as the stable review case while files are still being staged and interpreted. The invoice status moves through processing states such as `upload_in_progress`, `ocr_in_progress`, and `genai_in_progress`.

The package ingest flow stages each uploaded file in `claims.ingest_documents`. Once the system resolves the single invoice PDF, it creates `claims.invoice_versions` row `1` for the invoice. A realistic storage key might be:

```text
sessions/11111111-1111-1111-1111-111111111111/pdfs/22222222-2222-2222-2222-222222222222/original.pdf
```

Document Intelligence output is stored on the invoice version in `di_raw_json`, `di_page_map`, first-class OCR fields, and `claims.lineitems`. For example, the invoice version might have OCR fields for invoice number `HP-1007`, vendor name `Example Heat Pump Co`, and invoice total `$14,250.00`.

The classifier detects `air_source_heat_pump_electric` and writes a `claims.invoice_version_upgrade_types` row with `source_engine = 'classifier'`, `call_status = 'classified'`, and a confidence score. GenAI and code rules then write located fields and rulechecks against the same invoice version.

When AI processing completes, `claims.invoices.status` becomes `genai_complete`. The contractor can submit the invoice to admin review, which sets `submitter_id`, `submitted_at`, and moves the invoice to `admin_review_inbox`.

### 3.8 Example: invoice version rerun or replacement

Suppose the first uploaded invoice PDF was blurry, or the contractor was asked to upload a corrected invoice. The claim-level `claims.invoices` row should remain stable, because it is the review case being worked on. The new processed PDF becomes a new `claims.invoice_versions` row.

The original version might be:

```text
invoice_id = aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa
invoice_versionno = 1
original_filename = Heat Pump invoice.pdf
genai_result = warn
```

The replacement version might be:

```text
invoice_id = aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa
invoice_versionno = 2
original_filename = Heat Pump invoice corrected.pdf
genai_result = pass
```

Both versions belong to the same invoice. Each version has its own OCR JSON, line items, located fields, rulechecks, upgrade-type rows, GenAI summary, and product-list matches.

The current read path uses `claims.v_current_invoice_versions`, so version `2` becomes the current version because it has the highest `invoice_versionno`. Version `1` remains useful for audit and comparison, but it should not be mixed with version `2` results.

### 3.9 Example: invoice with multiple detected upgrade types

Some invoices contain more than one upgrade type. The test data includes examples such as "Heat Pump and Electric Service Upgrade" and "Heat Pump, Ventilation, Electrical Service Upgrade." In the claims AI model, that is represented by one claim-level invoice, one current invoice version, and multiple upgrade-type rows.

For example, one `claims.invoice_versions` row could have classifier rows in `claims.invoice_version_upgrade_types` for:

- `air_source_heat_pump_electric`
- `electrical_service_upgrade`

The same invoice version could also have `claims.lineitems` rows assigned to different upgrade types:

- line item 1: `air_source_heat_pump_electric`, description `Cold climate heat pump installation`
- line item 2: `electrical_service_upgrade`, description `Panel upgrade and service connection`

Common checks still use the `common` upgrade type. For example, invoice contractor name, GST number, eligibility code, customer name, total amount, and overall rebate evidence can be evaluated once at the common scope while upgrade-specific checks run separately for each detected upgrade type.

This is why the model does not store a single AI upgrade type directly on `claims.invoices`. The AI result is versioned and can be plural. It belongs under `claims.invoice_versions` through `claims.invoice_version_upgrade_types`, with line items, located fields, rulechecks, and supporting-document context all able to point at the relevant upgrade type.

## 4. Package Ingest And Processing

### 4.1 `claims.ingest_runs`

`claims.ingest_runs` is the parent record for a package-processing attempt. A run usually represents one contractor upload bundle or one redo package. It tracks the overall state of the bundle while individual files and processing steps move forward.

Important columns include:

- `session_id`: links the run to `claims.sessions`.
- `status`: one of `queued`, `running`, `succeeded`, `failed`, or `partial`.
- `total_files`: number of files expected in the bundle.
- `completed_files`: number of files successfully processed for the bundle.
- `failed_files`: number of files that failed bundle processing.
- `messages`: JSON messages for bundle-level errors, warnings, or informational notes.
- `completed_at`: set when the run reaches a terminal state.

In the current mixed-package intake flow, a new run starts as `queued`, then becomes `running` while staged documents are being OCR-read, classified, promoted, and validated. The run becomes `succeeded` only after the bundle resolves to exactly one invoice, any usable supporting documents are promoted, invoice OCR completes, and downstream validation finishes successfully.

Failure is bundle-level, not just file-level. For example, if two uploaded files are classified as invoices, each individual OCR/classifier step may have succeeded, but the bundle is still invalid because the system requires exactly one invoice candidate.

### 4.2 `claims.ingest_documents`

`claims.ingest_documents` stores one staged uploaded file before the system has fully resolved its role in the claim.

This table is the heart of package staging. A row starts as "this uploaded file exists at this storage key." Later, OCR and triage add meaning: the file may become the invoice, a supporting document, or an unknown document that stops the bundle.

Important column groups include:

- Batch and ownership: `ingest_run_id`, `session_id`, `contractor_id`.
- Claim links: `invoice_id`, `resolved_invoice_id`, `resolved_invoice_version_id`, `promoted_supporting_document_id`.
- Storage metadata: `storage_provider`, `storage_key`, `original_filename`, `content_type`, `byte_size`, `sha256`.
- OCR and classifier payloads: `di_read_raw_json`, `classifier_raw_json`.
- Document-kind classification: `document_kind`, `document_kind_confidence`, `document_kind_reason`.
- Supporting-document classification: `supporting_document_type_id`, `classification_status`, `classification_confidence`, `classification_reason`.
- Supporting-document routing quality: `supplement_routing_quality`, `supplement_routing_quality_reason`, `classified_at`.

`document_kind` can be `invoice`, `supplement`, or `unknown`. `classification_status` can be `pending`, `classified`, `needs_review`, `failed`, or `superseded`.

The distinction between `invoice_id` and `resolved_invoice_id` is subtle but important. During draft batch intake, the system creates a shell `claims.invoices` row immediately and links staged documents to it. Once triage resolves the bundle, the staged invoice document records the final claim invoice through `resolved_invoice_id` and the created/selected `claims.invoice_versions` row through `resolved_invoice_version_id`.

Supporting documents remain staged until the resolved invoice is known. After promotion, `promoted_supporting_document_id` points to the created or reused `claims.supporting_documents` row.

### 4.3 `claims.ingest_step_runs`

`claims.ingest_step_runs` stores individual processing attempts. It is the audit and troubleshooting table for the package pipeline.

An ingest step can target either:

- a staged document through `ingest_document_id`, before the invoice version exists; or
- an invoice version through `invoice_version_id`, after the invoice PDF has been resolved.

The schema enforces that normal steps target one side or the other. Staging-level steps such as `upload_package_stage` and `reprocess_package_stage` are bundle-level and do not target a specific staged document or invoice version.

Important columns include:

- `ingest_run_id`: optional parent run.
- `session_id`: required for filtering and audit.
- `invoice_version_id`: target for resolved-invoice work.
- `ingest_document_id`: target for staged-document work.
- `invoice_upgrade_type_id`: target upgrade type for typed GenAI/code calls.
- `step_type`: the kind of processing attempt.
- `status`: one of `queued`, `in_progress`, `succeeded`, or `failed`.
- `error_text`: required when a step fails.
- `di_results_json`: raw per-step Document Intelligence response payload.
- `genai_results_json`: raw per-step GenAI response payload.
- `context_window_json`: the actual GenAI message array used for audit.

Current step types include:

- Bundle/staging: `upload`, `upload_package_stage`, `reprocess_package_stage`.
- Staged document processing: `ocr_read`, `triage_classifier`, `supporting_document_extraction`.
- Resolved invoice OCR: `ocr_invoice`.
- Validation runtime: `case_facts`, `product_lookup_enrichment`, `genai_common`, `genai_upgrade`, `code_common`, `code_upgrade`, `aggregate_advice`.
- Older/general step names still allowed by the schema: `ocr`, `classifier`, `genai`.

The most important audit pattern is that GenAI calls store both `genai_results_json` and `context_window_json`. This lets reviewers and developers inspect not only the output but also the prompt/context that produced it.

### 4.4 Upload package staging

Upload package staging starts when a contractor uploads one or more files.

The current draft-batch flow does four important things at the beginning:

- Creates a `claims.sessions` row.
- Creates a `claims.ingest_runs` row with `total_files` set to the number of uploaded files.
- Creates one shell `claims.invoices` row with status `upload_in_progress`.
- Creates one `claims.ingest_documents` row per uploaded file.

This shell invoice is intentional. It gives the UI a stable claim-level invoice row immediately, before OCR has finished and before the system knows which uploaded file is the real invoice.

Each staged document gets storage metadata and starts with classification fields such as `classification_status = 'pending'` and zero confidence. The file is uploaded through the thin Node service, which returns the canonical `storage_key`. After staging succeeds for a file, the system creates an `ocr_read` step and queues the OCR-read job for that staged document.

The `upload_package_stage` step records the overall package-staging attempt. Individual file OCR and classification work is tracked separately through `ocr_read` and `triage_classifier` steps.

### 4.5 OCR read phase

The OCR read phase runs against each staged `claims.ingest_documents` row. It uses the Document Intelligence read model, not the invoice model.

The read phase stores:

- `claims.ingest_documents.di_read_raw_json`: the raw read/OCR payload for the staged file.
- `claims.ingest_step_runs.di_results_json`: the per-step response payload.
- `claims.ingest_step_runs.status`: `queued`, `in_progress`, `succeeded`, or `failed`.

This first OCR pass is intentionally broad. Its job is to produce enough machine-readable text for triage. It does not yet create line items or first-class invoice fields on `claims.invoice_versions`, because the system may not know which staged file is the actual invoice.

After all staged files have successful `ocr_read` steps, the bundle advancement service queues `triage_classifier` jobs for the staged documents.

If any staged file fails the read phase, the bundle run fails, the shell invoice moves to `ocr_failed`, and the run messages record a bundle-level read failure.

### 4.6 Triage classifier phase

The triage classifier phase runs GenAI against each staged document's read/OCR output. Its job is to answer:

- Is this file the invoice, a supporting document, or unknown?
- If it is a supporting document, which `claims.supporting_document_types` row does it match?
- Is its routing quality usable, questionable, visually dependent, or unusable?

The classifier writes its output to:

- `claims.ingest_documents.classifier_raw_json`
- `document_kind`
- `document_kind_confidence`
- `document_kind_reason`
- `supporting_document_type_id`
- `classification_status`
- `classification_confidence`
- `classification_reason`
- `supplement_routing_quality`
- `supplement_routing_quality_reason`
- `classified_at`

The corresponding `claims.ingest_step_runs` row stores `genai_results_json` and `context_window_json` for audit.

Unknown documents fail the bundle. This is deliberately conservative: if the system cannot classify a file as either the invoice or a supporting document, the package is not safe to continue automatically.

After every staged document is classified, the advancement service validates the bundle shape. The current bundle rule is exactly one invoice document. Zero invoice candidates and multiple invoice candidates both fail the run.

### 4.7 Supporting-document extraction phase

Supporting-document extraction happens after triage and before final invoice OCR.

Only staged documents with `document_kind = 'supplement'` and a known `supporting_document_type_id` are candidates for this step. The system checks whether that supporting-document type has enabled field definitions in `claims.supporting_document_type_located_fields`. If there are no configured fields for that type, no extraction step is required.

For supporting documents that do require extraction, the system queues `supporting_document_extraction` steps. The GenAI prompt is narrowed to the selected supporting-document type, and the output is stored in `claims.ingest_step_runs.genai_results_json` with the audited `context_window_json`.

After the bundle has exactly one resolved invoice, supplement staged documents are promoted into `claims.supporting_documents`. Promotion copies storage metadata, OCR read JSON, classifier JSON, classification status, routing quality, and classified timestamp from the staged document. It also applies the successful supporting-document extraction payload into `claims.supporting_document_located_fields`.

The staged row remains useful after promotion because `promoted_supporting_document_id` links the ingest document to the promoted supporting document.

### 4.8 Final invoice OCR phase

The final invoice OCR phase starts only after triage has identified exactly one staged invoice document.

At that point, the system ensures there is a `claims.invoice_versions` row for the resolved invoice file. If a version with the same invoice and storage key already exists, it reuses and updates that row. Otherwise it creates the next `invoice_versionno`.

The final OCR phase then queues an `ocr_invoice` step against the `claims.invoice_versions` row. This step uses the Document Intelligence invoice model. Its output is written to the invoice version, not just to the staged ingest document.

The final invoice OCR phase stores:

- `claims.invoice_versions.di_raw_json`
- `claims.invoice_versions.di_page_map`
- first-class invoice OCR fields such as invoice number, invoice date, vendor name, customer name, totals, and their page/polygon evidence
- `claims.lineitems`
- `claims.ingest_step_runs.di_results_json` for the `ocr_invoice` step

If the final invoice OCR succeeds, the invoice status moves through `ocr_complete` and then `genai_queued` / `genai_in_progress` as validation begins. GenAI and code validation then write their own `ingest_step_runs`, located fields, rulechecks, product-list matches, and aggregate advice.

The ingest run is complete only when the resolved invoice reaches `genai_complete` and all required validation step rows have succeeded.

### 4.9 Example: normal package upload

Consider a contractor uploading a package with:

- `Heat Pump invoice.pdf`
- `Heat Pump WETT report.pdf`

The system creates one `claims.ingest_runs` row with `total_files = 2`, one shell `claims.invoices` row, and two `claims.ingest_documents` rows.

The staged rows first receive `ocr_read` steps:

```text
Heat Pump invoice.pdf      -> ocr_read succeeded
Heat Pump WETT report.pdf  -> ocr_read succeeded
```

Then triage classifies the files:

```text
Heat Pump invoice.pdf      -> document_kind = invoice
Heat Pump WETT report.pdf  -> document_kind = supplement, supporting document type = wett_report
```

Because exactly one invoice was found, the system creates invoice version `1` for `Heat Pump invoice.pdf`. It promotes `Heat Pump WETT report.pdf` into `claims.supporting_documents` and links the staged row through `promoted_supporting_document_id`.

The invoice file then receives an `ocr_invoice` step. That step fills `claims.invoice_versions` and `claims.lineitems`. GenAI/code validation runs after invoice OCR, using the invoice data and the supporting-document summary as case context.

When all required validation steps succeed, the shell invoice reaches `genai_complete`, and the ingest run becomes `succeeded`.

### 4.10 Example: redo invoice package

A redo package follows the same staging model but starts from an existing claim-level invoice rather than creating a brand-new review case.

For example, suppose invoice `aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa` already has invoice version `1`, but the contractor uploads a corrected package. The redo flow creates a new `claims.ingest_runs` row and stages the new files as `claims.ingest_documents`.

The staged redo files are still OCR-read, triaged, checked for exactly one invoice, and optionally promoted as supporting documents. When the corrected invoice file is resolved, the system creates invoice version `2` under the same `claims.invoices` row.

The old version and the new version stay separate:

```text
version 1: original invoice OCR, line items, rulechecks, located fields
version 2: corrected invoice OCR, line items, rulechecks, located fields
```

The current-version view will prefer version `2`, but version `1` remains available for audit or comparison.

Supporting documents in the redo package are promoted to the same claim-level invoice. Staged redo rows retain their ingest history, so reviewers can see what files came in, how they were classified, whether supporting-document extraction ran, and which promoted records they created.

## 5. Supporting Documents

Supporting documents are the non-invoice files that come in with a claim package. They are not invoice versions. They are claim-level evidence attached to `claims.invoices`, such as utility account documents, product spec sheets, permit documents, manufacturer label photos, WETT reports, preapproval notices, or proof that fossil-fuel equipment was removed.

The important lifecycle distinction is:

- `claims.ingest_documents` stores staged uploaded files while the package is still being classified.
- `claims.supporting_documents` stores promoted supporting documents after package triage has resolved exactly one invoice for the bundle.
- `claims.supporting_document_located_fields` stores typed evidence extracted from a promoted supporting document.

This lets the system preserve the full ingest audit trail while giving claim review, GenAI case facts, and admin screens a stable claim-level supporting-document model.

### 5.1 `claims.supporting_document_types`

`claims.supporting_document_types` is the lookup table for recognized supporting-document categories. Each row has a stable `type_key`, a human description, and an `enabled` flag.

Examples include:

- `utility_bill`
- `utility_account_document`
- `manufacturer_label_photo`
- `product_spec_sheet`
- `permit_document`
- `fossil_fuel_removal_proof`
- `oil_removal_proof`
- `wett_report`
- `electrical_utility_upgrade_document`
- `fenestration_energy_performance_label`

The document type is assigned during package triage. For staged files, the classifier writes `supporting_document_type_id` onto `claims.ingest_documents`. During promotion, that type is copied to `claims.supporting_documents`.

Admins can maintain this reference data through the supporting-document type admin screen. Disabling a type prevents it from being used as an enabled configuration option without deleting historical documents that already used it.

### 5.2 `claims.supporting_document_type_upgrade_types`

`claims.supporting_document_type_upgrade_types` maps supporting-document types to the invoice upgrade types where that document category is applicable.

For example:

- `utility_account_document` is applicable to common eligibility evidence and several heat-pump upgrade paths.
- `manufacturer_label_photo` is applicable to windows and doors, heat pumps, heat-pump water heaters, and other upgrades where installed equipment identity matters.
- `fossil_fuel_removal_proof` is applicable to upgrade paths that need evidence of fossil-fuel system removal or conversion.
- `electrical_utility_upgrade_document` is applicable to `electrical_service_upgrade`.

This table does not mean "required." It means "this supporting-document type is relevant for this upgrade type and may be included in the case-facts packet for that upgrade review." Required-versus-optional logic belongs in validation rules, program policy, tracker/admin rule layers, and reviewer guidance.

The GenAI case-facts builder uses this mapping to prepare an upgrade-specific supporting-document summary. For a given upgrade type, it can report configured document types, which of those types are present on the claim, and which configured types are missing.

### 5.3 `claims.supporting_document_type_located_fields`

`claims.supporting_document_type_located_fields` defines the facts the system should try to extract from a supporting document of a given type. Each row belongs to one supporting-document type and has:

- A stable `field_key`.
- A required `contractor_display_name` used by contractor and admin review screens.
- A `prompt_text` used to instruct extraction.
- A `field_number` for ordering.
- An `enabled` flag.

The field definitions are type-specific. A utility document asks for utility provider and account evidence. A manufacturer label photo asks for model, serial number, brand, certification references, and legibility concerns. A fossil-fuel removal proof asks for removed equipment type, removal date or permit reference, address, authority, and removal scope.

During package processing, the system checks whether the classified supporting-document type has enabled located-field definitions. If it does, a `supporting_document_extraction` step can run and store the extraction payload on `claims.ingest_step_runs` before promotion.

### 5.4 `claims.supporting_documents`

`claims.supporting_documents` is the promoted, claim-level record for a supporting document. It belongs to `claims.invoices`, not to a specific `claims.invoice_versions` row.

Key groups of columns are:

- Claim link: `invoice_id`.
- Type: `supporting_document_type_id`.
- Storage metadata: `storage_key`, `container_name`, `original_filename`, `content_type`, `file_size_bytes`.
- OCR and classifier audit: `di_read_raw_json`, `classifier_raw_json`.
- Classification result: `classification_status`, `classification_confidence`, `classification_reason`, `classified_at`.
- Routing quality: `supplement_routing_quality`, `supplement_routing_quality_reason`.
- Timestamps: `created_at`, `updated_at`.

The uniqueness constraint on `(invoice_id, storage_key)` prevents the same blob from being promoted more than once for the same claim invoice.

Promotion copies the staged-file metadata from `claims.ingest_documents`. If a successful supporting-document extraction step exists for that staged file, promotion also applies the extracted fields into `claims.supporting_document_located_fields`.

The per-invoice supporting-documents admin screen reads from this table, lists the promoted documents for a claim, can request a short-lived PDF URL from `storage_key`, and displays any extracted located fields.

### 5.5 `claims.supporting_document_located_fields`

`claims.supporting_document_located_fields` stores the runtime extracted values for promoted supporting documents.

Each row records:

- The promoted document through `supporting_document_id`.
- The configured field definition through `supporting_document_type_located_field_id`, when available.
- The stable runtime `field_key`.
- The `source_engine`, such as `genai`, `vision`, `code`, or `manual`.
- The `value_type`, such as `text`, `currency`, `number`, `date`, `bool`, or `json`.
- The extracted value in `value_text` or `value_json`.
- Confidence, page number, polygon coordinates, and evidence text when available.

The application service that applies GenAI extraction results only inserts fields whose `field_key` matches an enabled field definition for the document's type. That keeps ad hoc model output from silently becoming trusted structured data.

These rows are included in the GenAI case-facts packet. They are also displayed in the supporting-documents admin UI so a reviewer can see both the document classification and the evidence the system extracted from the document.

### 5.6 Supporting-document routing quality

`supplement_routing_quality` captures whether the classifier thinks a supporting document can be used cleanly by the automated workflow.

Allowed values are:

- `usable`: the document is typed and likely usable for automated review.
- `needs_review`: the document is typed, but something about the classification or evidence needs reviewer attention.
- `requires_visual_review`: the document may need human visual inspection, often because image evidence, photo quality, or label legibility matters.
- `unusable`: the file is not usable as supporting evidence for the automated package.

This value is separate from `classification_status`. A document can be classified as a manufacturer label photo but still require visual review if the OCR or GenAI output cannot confidently read the label.

### 5.7 Required vs optional supporting documents

Supporting-document configuration is intentionally split from business requiredness.

`claims.supporting_document_type_upgrade_types` answers:

"Could this kind of document be relevant to this upgrade type?"

It does not answer:

"Must this claim include this document before approval?"

Requiredness can vary by program rules, upgrade scenario, eligibility path, admin policy, and future rule configuration. Keeping applicability separate lets the system reuse document classification and extraction without baking every business decision into the supporting-document lookup tables.

### 5.8 Example: utility account document

A contractor uploads an invoice package that includes a utility account document. During package triage, the staged file is classified as `utility_account_document` and gets a routing quality of `usable`.

Because `utility_account_document` has configured located fields, the system can extract facts such as:

- Utility provider.
- Account holder name.
- Service address.
- Account number or reference.
- Utility service type or fuel evidence.
- Residential, strata, or landlord account evidence.

After the bundle resolves to exactly one invoice, the staged file is promoted into `claims.supporting_documents`. The extracted values are applied into `claims.supporting_document_located_fields` and become available to common eligibility review and any upgrade-specific GenAI review where this document type is applicable.

### 5.9 Example: manufacturer label photo

A contractor uploads a photo of an installed equipment label. Triage classifies it as `manufacturer_label_photo`.

Configured fields for this type can include:

- Brand and model.
- Model number.
- Serial number.
- Equipment type or product category.
- Certification or listing reference.
- AHRI, NRCan, CPD, or performance-reference evidence where applicable.
- Label legibility concern.

If the label text is clear enough, extraction may populate structured located fields. If the label is blurry or the key evidence is visual rather than textual, `supplement_routing_quality` may be `requires_visual_review`, which gives the reviewer a clear reason to inspect the file directly.

### 5.10 Example: proof of fossil fuel removal

A contractor uploads a document showing that fossil-fuel equipment was removed or decommissioned. Triage classifies it as `fossil_fuel_removal_proof`.

Configured fields can include:

- Removed equipment type.
- Removal date or permit reference.
- Site address.
- Contractor or authority name.
- Removal scope or description.

The promoted document can then support review of upgrade paths where removal or conversion evidence matters, such as some fossil-fuel-to-heat-pump scenarios. The mapping table tells the system which upgrade reviews should see this document in their supporting-document summary; the validation rules decide how that evidence affects the final advice.

## 6. Located Fields And Evidence

Located fields are structured facts that the system found, derived, or intentionally recorded for review. They are the bridge between raw OCR/GenAI/provider output and the UI or rule engine.

In the three-world model, runtime located-field rows are evidence-world records. Located-field definition tables are registry-world records.

A located field should answer:

- What fact was found?
- Which engine produced it?
- What value was found?
- How confident is the system?
- Where is the evidence, if it came from a document?
- Which invoice version, supporting document, or upgrade type does it belong to?

The claims AI model has two runtime located-field tables:

- `claims.invoice_version_located_fields` stores facts for one processed invoice PDF version.
- `claims.supporting_document_located_fields` stores facts for one promoted supporting document.

It also has configuration tables that define which facts should be located:

- `claims.code_located_fields` defines code/database facts that can be carried into the GenAI context and persisted for review.
- `claims.genai_located_fields` defines invoice facts GenAI should locate.
- `claims.genai_located_field_upgrade_types` maps GenAI invoice fields to the upgrade types where they should run.
- `claims.supporting_document_type_located_fields` defines supporting-document facts by supporting-document type.

### 6.1 Invoice located fields

Invoice located fields are facts associated with a specific `claims.invoice_versions` row. They are stored in `claims.invoice_version_located_fields`.

These rows can come from:

- GenAI invoice review, with `source_engine = 'genai'`.
- Deterministic code or database enrichment, with `source_engine = 'code'`.

GenAI invoice fields usually describe things visible in or inferable from the invoice PDF, such as invoice contractor name, homeowner name, rebate line amount, heat-pump model evidence, AHRI reference, U-factor, or upgrade-specific line amount.

Code invoice fields usually describe trusted database facts that should be visible to the reviewer and carried into GenAI context, such as contractor business name, contractor address, submitted date, eligibility code, income level, and eligibility-code dates.

These rows are separate from the first-class OCR columns on `claims.invoice_versions`. For example, `di_ocr_invoice_total` is a Document Intelligence extracted invoice total stored directly on the invoice version. A GenAI located field such as `overall_rebate_line_amount` is stored as a runtime evidence row because it is part of the validation evidence model, not the generic invoice OCR model.

### 6.2 Supporting-document located fields

Supporting-document located fields are facts associated with a specific promoted `claims.supporting_documents` row. They are stored in `claims.supporting_document_located_fields`.

These fields are configured by supporting-document type through `claims.supporting_document_type_located_fields`. A `utility_account_document` can ask for utility provider, account holder, service address, and account evidence. A `manufacturer_label_photo` can ask for brand/model, model number, serial number, certification references, AHRI reference, or label legibility concerns.

Supporting-document extraction runs during package ingest, before final invoice OCR, after the staged document has been classified as a supplement and assigned a supporting-document type. The extraction result is first stored on the `supporting_document_extraction` step run. When the staged file is promoted, the extracted fields are applied to the promoted supporting document.

The apply service deletes and replaces existing GenAI supporting-document located fields for that document. It only inserts fields whose `field_key` matches an enabled definition for the document's type. This prevents unexpected model output from becoming accepted structured evidence.

### 6.3 Code located fields

`claims.code_located_fields` is the admin-visible registry for code/database located-field definitions.

The seed data currently defines database facts such as:

- `invoices.submitted_at`
- `contractors.business_name`
- `contractors.address`
- `users_eligibilitycodes.eligibility_code`
- `users_eligibilitycodes.income_level`
- `users_eligibilitycodes.approved_at`
- `users_eligibilitycodes.expires_at`
- `users.participant_name`

These definitions do not store runtime values. They define the code field keys that are enabled for runtime inclusion. At runtime, the case-facts builder assembles the database values, prunes disabled code fields, and persists enabled values into `claims.invoice_version_located_fields` with `source_engine = 'code'`.

Code located fields are high-confidence snapshots from the application database. They use `confidence = 100`, no page or polygon, and `evidence_text = 'ESP database'`.

Because the current code persistence does not set an explicit `invoice_upgrade_type_id`, these rows use the table default, which is the `common` invoice upgrade type. That is a good fit for shared database facts that apply across the whole invoice review.

### 6.4 GenAI located fields

`claims.genai_located_fields` is the admin-visible registry for GenAI invoice-field definitions. Each row has a stable `genai_field_key`, a required `contractor_display_name`, prompt text, and an enabled flag.

Examples include:

- `eligibility_code`
- `invoice_contractor_name`
- `invoice_homeowner_name`
- `overall_rebate_line_amount`
- `hp_ahri_reference`
- `hp_make_model`
- `hp_product_list_reference`
- `hpwh_model_number`
- `metric_u_factor`
- `window_or_door_quantity`
- `esu_service_size`

The GenAI prompt compiler uses enabled GenAI located-field mappings for the upgrade type being evaluated. It emits an ordered located-fields section in the GenAI prompt. The GenAI response is expected to return `located_fields`, and those values are persisted into `claims.invoice_version_located_fields`.

GenAI located fields are intentionally separate from GenAI rules. A located field says "find this fact." A rule says "evaluate this condition." The same located field can support several rules, UI display, and debugging.

### 6.5 `claims.invoice_version_located_fields`

`claims.invoice_version_located_fields` is the runtime table for invoice-version evidence rows.

Important columns are:

- `invoice_version_id`: the processed invoice PDF version the fact belongs to.
- `invoice_upgrade_type_id`: the upgrade type context for the fact.
- `source_engine`: currently `code` or `genai`.
- `field_key`: stable key for the fact.
- `value_type`: `text`, `currency`, `number`, `date`, `bool`, or `json`.
- `value_text` and `value_json`: the stored value.
- `confidence`: integer from 0 to 100.
- `page`: source page when document evidence exists.
- `polygon`: source polygon when document evidence exists.
- `evidence_text`: short supporting text or source explanation.

The value storage rule is:

- JSON values use `value_json` and leave `value_text` null.
- Non-JSON values use `value_text` and leave `value_json` null.
- Both value columns may be null when the system intentionally records that a configured field was not found.

GenAI persistence replaces existing GenAI rows for the same invoice version, upgrade type, and source engine before inserting the latest response. Code persistence replaces existing code rows for the invoice version before inserting the latest database snapshot.

The invoice review APIs serialize GenAI fields and code fields separately as `located_fields` and `code_located_fields`, while preserving the same row shape for the UI. They resolve `contractor_display_name` dynamically from the matching definition registry, so label edits apply to existing runtime evidence without reprocessing the invoice. The technical `field_key` remains available to the UI for troubleshooting tooltips.

### 6.6 `claims.code_located_fields`

`claims.code_located_fields` is a definition table, not a runtime result table.

Important columns are:

- `code_field_key`: stable key used by code.
- `contractor_display_name`: required contractor-friendly label used in review screens.
- `description`: admin-facing explanation of what the field carries.
- `enabled`: controls whether the case-facts builder includes and persists the field.

The validation admin UI can update these rows. Updates snapshot history into `claims.code_located_field_history`, so changes to field descriptions or enabled flags are auditable.

Unlike GenAI located fields, code located fields are not mapped per upgrade type in the current schema. They are shared database facts that can be used by common rules and passed into upgrade-specific GenAI context.

### 6.7 `claims.genai_located_fields`

`claims.genai_located_fields` is a GenAI field-definition table, not a runtime value table.

Important columns are:

- `genai_field_key`: stable key the model should return in `located_fields`.
- `contractor_display_name`: required contractor-friendly label used in review screens.
- `prompt_text`: instruction telling GenAI what to locate and how to represent it.
- `enabled`: controls whether the field is compiled into GenAI prompts.

The validation admin UI can create and update GenAI located fields. Updates snapshot history into `claims.genai_located_field_history`.

This table is intentionally reusable. A field such as `hp_make_model` can be defined once and mapped to several heat-pump upgrade types through `claims.genai_located_field_upgrade_types`.

### 6.8 `claims.genai_located_field_upgrade_types`

`claims.genai_located_field_upgrade_types` maps GenAI located-field definitions to invoice upgrade types.

Important columns are:

- `genai_field_id`: points to the reusable field definition.
- `invoice_upgrade_type_id`: points to the upgrade type where the field applies.
- `field_number`: controls ordering in the compiled GenAI prompt.

The schema enforces one mapping per field and upgrade type, and one field number per upgrade type. This gives the compiled prompt a predictable order.

When GenAI runs for `common`, it gets the enabled common field mappings. When GenAI runs for an upgrade type such as `air_source_heat_pump_electric`, it gets the enabled mappings for that upgrade type. The resulting runtime rows are tagged with that same `invoice_upgrade_type_id`.

### 6.9 Example: invoice AHRI reference

An invoice PDF includes the text:

```text
AHRI Certificate: 213617706
```

For a heat-pump upgrade type, the GenAI prompt includes the configured field `hp_ahri_reference`. The prompt asks GenAI to store only the numeric AHRI reference number in the value and put the full visible phrase in evidence text.

The runtime row in `claims.invoice_version_located_fields` would look conceptually like:

```text
invoice_version_id: version 1
invoice_upgrade_type_id: air_source_heat_pump_electric
source_engine: genai
field_key: hp_ahri_reference
value_type: text
value_text: 213617706
confidence: 92
page: 2
polygon: [source coordinates if available]
evidence_text: AHRI Certificate: 213617706
```

Code product-list matching can then use the located AHRI reference, OCR text, line items, or related context to find a matching `claims.ahri_products` row. The product-list match itself is stored separately on `claims.invoice_versions` and explained through code rulechecks.

### 6.10 Example: supporting-document AHRI reference

A contractor uploads a manufacturer label photo or product spec sheet that includes an AHRI reference. That reference is supporting-document evidence, not invoice-PDF evidence.

The staged file is classified as a supporting document, extracted using the configured fields for that supporting-document type, promoted into `claims.supporting_documents`, and then receives a row in `claims.supporting_document_located_fields` such as:

```text
supporting_document_id: promoted label photo
source_engine: genai
field_key: ahri_reference
value_type: text
value_text: 213617706
confidence: 84
page: 1
evidence_text: AHRI 213617706
```

That value is included in the supporting-document summary used by GenAI case facts. It does not automatically become an invoice located field unless an invoice-version GenAI or code step chooses to record its own invoice-version-level field.

Keeping these rows separate matters. It lets reviewers tell whether the AHRI evidence came from the invoice PDF itself or from an attached supporting document.

### 6.11 Example: database-derived eligibility facts

The classifier or OCR text locates an eligibility code on the invoice package, such as `ESP2-123456`. The case-facts builder looks up the matching row in `claims.users_eligibilitycodes` and may also load the participant from legacy `public.users`.

The runtime code-located-field output can include:

```text
source_engine: code
field_key: users_eligibilitycodes.eligibility_code
value_type: text
value_text: ESP2-123456
confidence: 100
page: null
polygon: null
evidence_text: ESP database
```

Related code fields can also carry the income level, approval date, expiry date, participant name, invoice submitted date, and contractor information.

These fields are not OCR guesses. They are database snapshots captured into the invoice-version evidence model so the reviewer and GenAI validation context can see which database facts were used during the run.

## 7. Validation Rules And Outputs

Validation rules are the checks that turn extracted evidence into review outcomes.

In the three-world model, rule definition and mapping tables live in the registry world. `claims.invoice_version_rulechecks` lives in the evidence world.

The model supports two validation engines:

- GenAI validation, for evidence that requires language understanding, document interpretation, or judgement over ambiguous invoice and supporting-document text.
- Code validation, for deterministic checks that should be repeatable from database values, structured located fields, product-list rows, or date/math calculations.

Both engines write their detailed outputs into `claims.invoice_version_rulechecks`. This gives the admin UI one consistent result shape while still preserving which engine produced each check.

### 7.1 Validation architecture

Validation is scoped to a specific `claims.invoice_versions` row. A processed invoice version can have common claim-level checks plus one or more upgrade-specific check groups.

The upgrade scope comes from `claims.invoice_upgrade_types`. The special `common` upgrade type is used for claim-level checks that are not tied to one physical upgrade. Other upgrade types, such as `air_source_heat_pump_gas_propane`, `heat_pump_water_heater`, or `windows_doors`, are used for upgrade-specific checks.

The normal validation flow is:

1. Classifier rows in `claims.invoice_version_upgrade_types` identify detected upgrade types for the invoice version.
2. Code/database facts are gathered and persisted as code located fields.
3. Common GenAI checks run for the `common` upgrade type.
4. GenAI checks run for each detected upgrade type.
5. Upgrade-specific code checks run where the enabled code rule has an executor implementation.
6. Outputs are persisted as rulechecks and summarized on `claims.invoice_versions` and `claims.invoice_version_upgrade_types`.

The detailed evidence remains in `claims.invoice_version_rulechecks`. Summary fields such as `claims.invoice_versions.genai_result`, `genai_overall_confidence`, and `genai_admin_advice` are convenience fields for the current processed version; they do not replace the rulecheck rows.

### 7.2 `claims.code_rules`

`claims.code_rules` is the admin-visible registry for deterministic validation rules.

The actual rule logic lives in Rails service classes. The table stores the stable rule key, description, enabled flag, and optional admin guidance messages for each possible result.

Important columns are:

- `code_rule_key`: stable key used by the code executor and persisted into rulecheck output.
- `description`: human-readable explanation of what the rule checks.
- `enabled`: controls whether the rule is active.
- `pass_admin_message`, `info_admin_message`, `warn_admin_message`, and `fail_admin_message`: optional review guidance by result.
- `admin_notes`: internal notes for maintainers or admins.

Examples of seeded code rules include:

- `source_vintage_applies`
- `submission_within_six_months`
- `eligibility_code_valid_for_invoice_date`
- `eligibility_code_found_in_database`
- `income_level_1_or_2_required`
- `hp_ahri_found_in_product_list`
- `hp_product_minimum_capacity_at_minus_5c`
- `hp_product_efficiency_threshold`
- `hpwh_neea_found_in_product_list`
- `hpwh_neea_tier_2_or_higher`
- `wd_u_factor_threshold`
- `hydronic_product_found_in_qualifying_list`
- `ashp_oil_ohpa_bc_product_found_in_list`

A disabled code rule remains in the registry for audit and admin visibility, but it should not be applied as a runtime validation check.

### 7.3 `claims.code_rule_upgrade_types`

`claims.code_rule_upgrade_types` maps code rules to the upgrade types where they apply.

Important columns are:

- `code_rule_id`: points to `claims.code_rules`.
- `invoice_upgrade_type_id`: points to `claims.invoice_upgrade_types`.
- `created_at`: records when the mapping was created.

The schema enforces one mapping per code rule and upgrade type. This means a rule such as `income_level_1_or_2_required` can be shared across several upgrade types, while product-list checks can be limited to the upgrade paths where that list is relevant.

Runtime code checks use this mapping as an applicability gate. If a code rule is enabled for an upgrade type but there is no executor implementation for that rule key, the upgrade code-check orchestration raises a coverage error rather than silently skipping the rule. That makes missing code-rule implementation a system issue, not a hidden review gap.

### 7.4 `claims.genai_rules`

`claims.genai_rules` is the admin-visible registry for GenAI validation rule definitions.

Each row defines one reusable rule prompt. The prompt tells GenAI what to evaluate, what evidence to use, and when to return `pass`, `info`, `warn`, or `fail`.

Important columns are:

- `genai_rule_key`: stable key the prompt compiler sends to GenAI and the runtime output stores in `rule_key`.
- `prompt_text`: the validation instruction.
- `enabled`: controls whether the rule can be compiled into a GenAI validation call.
- `created_at` and `updated_at`: support admin/history workflows.

Examples of seeded GenAI rules include:

- `contractor_identity_matches_record`
- `ashp_gas_propane_existing_heat_context_present`
- `ashp_fossil_fuel_removal_supporting_document_attached`
- `ashp_oil_consumption_baseline_proof_present`
- `hpwh_product_reference_present`
- `wd_certification_reference_present`

GenAI rule definitions are separate from GenAI located-field definitions. Located fields ask the model to find facts. Rules ask the model to evaluate conditions using those facts, OCR evidence, database context, and supporting-document summaries.

### 7.5 `claims.genai_rule_upgrade_types`

`claims.genai_rule_upgrade_types` maps GenAI rules to invoice upgrade types.

Important columns are:

- `genai_rule_id`: points to `claims.genai_rules`.
- `invoice_upgrade_type_id`: points to `claims.invoice_upgrade_types`.
- `created_at` and `updated_at`: support admin/history workflows.

The schema enforces:

- One mapping per GenAI rule and upgrade type.

The prompt compiler loads enabled GenAI rules through this mapping, orders them alphabetically by `genai_rule_key`, and emits each task by stable `rule_key`. The GenAI response is expected to copy `rule_key` back into `rulechecks`.

### 7.6 `claims.invoice_version_rulechecks`

`claims.invoice_version_rulechecks` is the runtime result table for validation outcomes.

Each row is one rule outcome for one invoice version, one upgrade-type context, and one source engine.

Important columns are:

- `invoice_version_id`: the processed invoice PDF version being evaluated.
- `invoice_upgrade_type_id`: the `common` or upgrade-specific validation context.
- `source_engine`: `genai` or `code`.
- `rule_key`: stable rule identity.
- `rule_result`: `pass`, `info`, `warn`, or `fail`.
- `confidence`: integer from 0 to 100.
- `expected_text`: expected condition or requirement text.
- `calculation`: date math, product-list comparison, rebate calculation, or other structured explanation.
- `evidence_text`: short evidence summary.
- `reason_and_likely_causes`: fuller explanation for review and advice.

The unique key is `(invoice_version_id, invoice_upgrade_type_id, source_engine, rule_key)`. This lets a GenAI rule and a code rule with the same key remain distinct by engine while preventing duplicate rows from the same engine for the same rule.

GenAI persistence replaces existing GenAI rulechecks for the same invoice version and upgrade type before inserting the latest response. Code-rule services similarly replace their own code outputs for the scoped check they own. This keeps reruns readable: the current invoice version shows the latest output for each engine/scope, while previous invoice versions preserve their older outputs.

### 7.7 Common claim-level checks

Common checks use the `common` invoice upgrade type. They evaluate evidence that applies to the whole invoice package rather than a specific rebate path.

Common checks can include:

- Whether the invoice appears to fall under the current source vintage.
- Whether first-class invoice fields were extracted.
- Whether the invoice was submitted within the allowed timing window.
- Whether the eligibility code was found in the database.
- Whether the invoice date falls inside the eligibility-code approval/expiry period.
- Whether the visible invoice contractor matches the contractor database record.

Common checks are important because later upgrade-specific analysis may rely on their evidence. For example, rebate-cap checks need the invoice date, eligibility code, contractor context, and submitted date to be reliable.

### 7.8 Upgrade-specific checks

Upgrade-specific checks use the detected upgrade type's `invoice_upgrade_type_id`.

These checks evaluate requirements that only make sense for a particular upgrade path. Examples include:

- Existing heat context for air-source heat-pump conversions.
- Rebate math and cap checks for the specific upgrade category.
- Whether a heat pump water heater has enough product identity evidence.
- Whether windows and doors include certification and U-factor evidence.
- Whether hydronic or combined heat-pump scope is present.
- Whether dual-fuel controls or backup system context requires review.

The same invoice version can have multiple upgrade-specific groups. For example, one invoice can produce rulechecks under both `air_source_heat_pump_gas_propane` and `electrical_service_upgrade`. The upgrade-type id on each rulecheck keeps those results separate even though they belong to the same processed invoice PDF.

### 7.9 Attachment checks

Attachment checks are validation rules that inspect promoted supporting documents and their located fields.

The supporting-document mapping tables describe which document types are applicable to which upgrade types and which fields should be extracted from those documents. The rule layer decides whether a document is required, optional, corroborating, missing, unusable, or merely something an admin should verify.

Attachment-oriented GenAI rules use `supporting_document_summary_for_upgrade_type`, including configured document types, located fields, routing quality, and missing configured type keys.

The intended result pattern is:

- `pass`: the required or useful document is present, usable, and has enough readable located-field evidence.
- `warn`: the document is present but incomplete, ambiguous, visually limited, low-confidence, or needs admin verification.
- `fail`: a mandatory document is missing, listed as missing for that upgrade type, or present only as unusable.
- `info`: the document is not a blocker, but there is helpful context worth surfacing.

This separation matters. A supporting-document type mapping alone does not mean the document is mandatory in every situation. The validation rule owns that business decision.

### 7.10 External-list code checks

External product-list checks are code-owned because they should be deterministic.

The product-list import tables store current AHRI, NEEA, AWHP, and OHPA product rows. GenAI and OCR can locate product evidence such as AHRI references, NEEA references, model numbers, or manufacturer names, but code performs the final database match and threshold comparison.

Examples include:

- `hp_ahri_found_in_product_list`: checks invoice AHRI evidence against current AHRI product-list rows and supporting-document AHRI evidence when present.
- `hp_product_minimum_capacity_at_minus_5c`: checks matched heat-pump product capacity at -5C.
- `hp_product_efficiency_threshold`: checks SEER/HSPF or SEER2/HSPF2 thresholds.
- `hpwh_neea_found_in_product_list`: checks heat pump water heater manufacturer/model evidence against the imported NEEA list.
- `hpwh_neea_tier_2_or_higher`: checks the matched NEEA tier.
- `hydronic_product_found_in_qualifying_list`: checks air-to-water or combined heat-pump evidence against the imported AWHP list.
- `ashp_oil_ohpa_bc_product_found_in_list`: checks corroborated oil-to-heat-pump AHRI evidence against imported OHPA BC qualified products.
- `wd_u_factor_threshold`: checks extracted windows/doors U-factor values against the configured threshold.

Product-list matches are also stored as foreign keys on `claims.invoice_versions` where applicable, such as `ahri_product_id`, `neea_product_id`, `awhp_product_id`, and `ohpa_product_id`. The rulecheck row explains the result; the invoice-version foreign key preserves the matched product row for the processed version.

### 7.11 Example: missing mandatory supporting document

An invoice is classified as `air_source_heat_pump_gas_propane` or `air_source_heat_pump_oil`. The upgrade-specific GenAI validation includes the rule `ashp_fossil_fuel_removal_supporting_document_attached`.

If no `fossil_fuel_removal_proof` or `permit_document` was promoted for that upgrade type, the runtime rulecheck could look conceptually like:

```text
invoice_version_id: version 1
invoice_upgrade_type_id: air_source_heat_pump_gas_propane
source_engine: genai
rule_key: ashp_fossil_fuel_removal_supporting_document_attached
rule_result: fail
confidence: 94
expected_text: fossil_fuel_removal_proof or permit_document attached
calculation: null
evidence_text: supporting_document_summary_for_upgrade_type has no acceptable removal or permit document
reason_and_likely_causes: The package does not include a usable fossil-fuel removal proof or permit document for this fossil-fuel conversion path. The contractor may need to upload removal proof, permit evidence, or another acceptable document before the claim can move forward.
```

If a document was present but blurry or visually limited, the same rule would more likely be `warn` so the admin knows to inspect that attachment rather than immediately request a corrected package.

### 7.12 Example: GenAI warning vs failure

Warnings and failures are intentionally different.

A `warn` means the system found an ambiguity, missing detail, visual limitation, or review question that an admin should verify. A `fail` means the available evidence clearly contradicts the requirement or a mandatory requirement is missing.

For example, `contractor_identity_matches_record` might return:

```text
rule_result: warn
evidence_text: The invoice shows "Example Heating Ltd."; the database contractor name is "Example Heating and Cooling Ltd."
reason_and_likely_causes: The names appear related, but the invoice address is missing. Admin should verify the contractor identity from the contractor record before approval.
```

That warning does not say the contractor is wrong. It says the match is plausible but needs review.

The same rule could return:

```text
rule_result: fail
evidence_text: The invoice vendor is "Different Company Ltd."; the database contractor is "Example Heating and Cooling Ltd."
reason_and_likely_causes: The visible invoice vendor appears to be a different contractor than the record associated with this claim. This may be the wrong invoice or a contractor account mismatch.
```

That failure describes a material contradiction. The distinction helps the admin UI separate "please verify this" from "this appears not to meet the requirement."

## 8. Prompt And Validation Configuration

Prompt configuration controls what the AI services are asked to do. It is related to validation output, but it is not the output itself.

In the three-world model, prompt configuration is registry-world data. The prompt and response actually used for a specific run are evidence-world data through `claims.ingest_step_runs.context_window_json` and `genai_results_json`.

The current model uses:

- A singleton-style global configuration row in `claims.validationgenai_config`.
- Normalized GenAI rule and located-field tables for reusable task definitions.
- Mapping tables that choose which tasks apply to each invoice upgrade type.
- Runtime `context_window_json` snapshots on `claims.ingest_step_runs` so the exact GenAI input can be audited later.

### 8.1 `claims.validationgenai_config`

`claims.validationgenai_config` stores global GenAI prompt/configuration text. It behaves like editable application configuration stored in the database.

The table is expected to have one active row. The API loads the oldest row or creates an empty one if none exists. Seed data provides the production-style default row.

Important columns are:

- `system_record`: system message for invoice validation GenAI calls. It defines the JSON output schema, result vocabulary, advice rules, evidence rules, and strict response requirements.
- `classifier_system_record`: system message for OCR triage/classifier calls. It defines `document_kind`, allowed upgrade types, allowed supporting-document types, and classifier output shape.
- `supporting_document_extraction_system_record`: system message for supporting-document located-field extraction calls.
- `user_record0`: shared Document Intelligence/OCR reading guidance used by invoice validation and classifier calls.
- `admin_advice_intro`: wrapper text used when presenting combined advice to a contractor or admin.
- `admin_advice_closing`: closing text used with combined advice.

This table should not be treated as a library of upgrade-specific validation tasks. Upgrade-specific GenAI rules and fields live in the normalized GenAI rule/field tables described in sections 6 and 7.

### 8.2 Normalized GenAI rule and field mappings

The invoice validation prompt is partly global and partly composed from normalized task definitions.

The normalized GenAI configuration tables are:

- `claims.genai_located_fields`: reusable invoice located-field tasks.
- `claims.genai_located_field_upgrade_types`: maps located-field tasks to upgrade types and field order.
- `claims.genai_rules`: reusable GenAI rulecheck tasks.
- `claims.genai_rule_upgrade_types`: maps rulecheck tasks to upgrade types.

This design avoids storing one large, duplicated prompt per upgrade type. A shared rule such as contractor identity matching can be defined once and mapped where needed. A highly specific rule such as a gas/propane removal-document check can be mapped only to the relevant upgrade type.

The located-field mapping table keeps `field_number` for prompt order. Rulechecks do not use numeric identity; runtime output is connected back to rule definitions by stable `rule_key`, and display order is alphabetical by key.

### 8.3 System record

The `system_record` column is the top-level instruction for invoice validation GenAI calls.

It defines:

- The purpose of the invoice pre-review.
- The strict JSON shape for `overall`, `located_fields`, and `rulechecks`.
- Allowed `rule_result` values: `pass`, `info`, `warn`, and `fail`.
- When advice may mention a rule.
- How to distinguish warning from failure.
- How to write evidence text, calculations, and reason text.
- How to use supporting-document summaries and located fields.
- How to avoid inventing missing facts or querying external systems.

This record is shared by common and upgrade-specific validation calls. The per-upgrade task list is not stored in `system_record`; it is supplied later as a compiled user record.

Classifier and supporting-document extraction calls use separate system records because they are different jobs. The classifier decides whether a staged document is an invoice, supplement, or unknown, and identifies detected upgrade types. Supporting-document extraction locates configured fields from a known supporting-document type. Neither of those calls is supposed to make final eligibility decisions.

### 8.4 Shared user records

`user_record0` is shared OCR/Document Intelligence guidance.

It tells the model how to read the DI JSON, including:

- When to use `documents[0].fields`.
- When to cross-check values against raw content, words, lines, and tables.
- How to choose page and polygon evidence.
- Why invoice `Items[*]` may be incomplete for contractor invoices.
- How to prefer exact evidence text over paraphrase.

This shared guidance is included in invoice validation calls and classifier calls when present.

Other runtime user records are assembled by code rather than stored as standalone columns:

- User record 1: compiled located-field and rulecheck tasks for the current upgrade type.
- User record 2: case facts from database and supporting-document summaries.
- User record 3: raw Document Intelligence invoice JSON.
- User record 4: the actual ask to perform location tasks and rulecheck tasks.

The supporting-document extraction job has its own smaller context: the extraction system record, the selected supporting-document type plus configured field tasks, and the supporting document's DI read JSON.

### 8.5 Upgrade-type prompt inputs

Upgrade-type prompt inputs are composed at runtime by `Claims::GenaiRulesetCompiler::Compile`.

For a given `claims.invoice_upgrade_types` row, the compiler creates a text block containing:

- A header describing whether the call is for `common` checks or an upgrade-specific review.
- Enabled GenAI located-field tasks mapped to that upgrade type.
- Enabled GenAI rulecheck tasks mapped to that upgrade type.
- Field numbers, field keys, rule numbers, and rule keys copied from the normalized mapping tables.

For `common`, the compiled prompt starts as common invoice evidence tasks. For an upgrade type, it names the upgrade and uses the current source vintage wording for invoice requirements dated on or after `2026-04-01`.

The compiler intentionally fails the run if the compiled task block is empty. An empty validation task list would make the model call misleading, so the system treats it as a configuration problem.

### 8.6 How GenAI context is compiled

Invoice validation context is compiled in the GenAI job.

The message array sent to the Node GenAI endpoint is stored as `claims.ingest_step_runs.context_window_json`. It contains:

1. System message from `claims.validationgenai_config.system_record`.
2. Optional shared OCR guidance from `user_record0`.
3. Compiled task text from normalized GenAI fields and rules for the current upgrade type.
4. Case facts JSON.
5. Raw DI invoice JSON.
6. The final instruction to perform the located-field and rulecheck tasks and return strict JSON.

The context window is deliberately assembled as a sequence of records. This makes it easier to inspect a past run and understand which part of the prompt came from configuration, which part came from normalized rule/field tables, which part came from runtime case facts, and which part came from raw OCR evidence.

### 8.7 Context-window record map

The invoice validation context window maps to the database like this:

```text
Record: system
Short:  JSON schema and validation behavior
Source: claims.validationgenai_config.system_record
DB map: Registry-world configuration. Defines the required assistant
        response shape, pass/info/warn/fail guidance, overall advice
        rules, evidence rules, and strict JSON requirements.

Record: user_record0
Short:  DI invoice explanation
Source: claims.validationgenai_config.user_record0
DB map: Registry-world configuration. Explains how to read Document
        Intelligence JSON, invoice fields, page evidence, polygons,
        line items, content, words, and tables.

Record: user_record1
Short:  Fields to locate and rules to evaluate
Source: Compiled from claims.genai_located_fields,
        claims.genai_located_field_upgrade_types,
        claims.genai_rules, and claims.genai_rule_upgrade_types
DB map: Registry-world definitions compiled for the current
        invoice_upgrade_type_id. This record is runtime text, but the
        source tasks are normalized database rows.

Record: user_record2
Short:  Supporting documents, attached-document facts, and DB facts
Source: Built by Claims::GenaiCaseFacts::Build
DB map: Evidence and database context. Includes supporting-document
        summaries, configured supporting-document applicability,
        extracted supporting-document located fields, eligibility-code
        facts, contractor/session/invoice facts, and other DB values.

Record: user_record3
Short:  Raw DI invoice JSON
Source: claims.invoice_versions.di_raw_json
DB map: Evidence-world OCR payload from the resolved invoice version.
        This is the raw invoice-model Document Intelligence response
        used by GenAI.

Record: user_record4
Short:  One-line actual ask
Source: Hard-coded in the GenAI job
DB map: Runtime instruction telling the model to perform the location
        tasks and rulecheck tasks and reply using the strict JSON schema
        from the system record.

Record: assistant
Short:  Model reply
Source: Node GenAI response
DB map: Evidence-world output. Stored first on
        claims.ingest_step_runs.genai_results_json, then inspected and
        applied into located-field, rulecheck, upgrade-type result, and
        invoice-version summary tables.
```

The important boundary is that records `system`, `user_record0`, and the source definitions behind `user_record1` are registry-world inputs. Records `user_record2` and `user_record3` are evidence/context inputs for this specific invoice version. The assistant response is not configuration; it is runtime evidence produced for the invoice version.

The full message array is retained in `claims.ingest_step_runs.context_window_json`. That snapshot matters because registry configuration can change later. A historical step run should still show exactly what was sent to the model at the time of that run.

### 8.8 Context-window output mapping

Case facts are built by `Claims::GenaiCaseFacts::Build`. They include:

- Database values such as invoice submitted date, contractor name/address, eligibility-code facts, income level, eligibility-code approval/expiry dates, and participant name.
- A full supporting-document summary for the invoice.
- For upgrade-specific calls, a filtered `supporting_document_summary_for_upgrade_type` showing configured, present, missing, and relevant supporting documents for that upgrade type.

The same case-facts step also persists enabled code/database fields into `claims.invoice_version_located_fields` with `source_engine = 'code'`.

After GenAI returns JSON, runtime services persist:

- Rulechecks into `claims.invoice_version_rulechecks`.
- Located fields into `claims.invoice_version_located_fields`.
- Per-call status, confidence, result, advice, and raw JSON into `claims.invoice_version_upgrade_types`.
- Step status, raw GenAI result, and exact context window into `claims.ingest_step_runs`.

The assistant response maps back into the evidence world in layers:

- `claims.ingest_step_runs.genai_results_json` keeps the raw reply payload for the individual GenAI step.
- `claims.invoice_version_located_fields` stores located values returned by the assistant, scoped to `invoice_version_id`, `invoice_upgrade_type_id`, and `source_engine = 'genai'`.
- `claims.invoice_version_rulechecks` stores rule outcomes returned by the assistant, scoped to the same invoice version and upgrade type.
- `claims.invoice_version_upgrade_types` stores per-upgrade GenAI call status, confidence, result, advice, and raw JSON.
- `claims.invoice_versions` stores aggregate summary fields after `aggregate_advice` combines the detailed outputs.

This is the bridge from context window to database: the context window is the audited input, the assistant JSON is the audited raw output, and the located-field/rulecheck/summary tables are the structured evidence used by the UI and reports.

### 8.9 Example: common GenAI call

A common GenAI validation call uses the `common` upgrade type.

The compiled task block might include common located fields and rules such as contractor identity, invoice date, eligibility code visibility, rebate evidence, and general invoice completeness. The case facts include database values and the full supporting-document summary, because common checks may need to know whether utility, income, landlord, or other shared documents are present.

Conceptually, the context contains:

```text
system: validation JSON schema and result rules
user: shared DI/OCR reading guidance
user: common located fields and common GenAI rulecheck tasks
user: case facts with ESP database values and supporting_document_summary
user: raw DI invoice JSON
user: perform the location tasks and rulecheck tasks
```

The output is persisted under the `common` `invoice_upgrade_type_id`. The rulechecks are common claim-level outputs, not evidence that a physical upgrade named "common" was installed.

### 8.10 Example: upgrade-type GenAI call

An invoice is classified as `air_source_heat_pump_gas_propane` and `electrical_service_upgrade`.

The GenAI job runs a separate upgrade-specific call for each detected upgrade type. The gas/propane heat-pump call receives the task block mapped to `air_source_heat_pump_gas_propane`, while the electrical service upgrade call receives the task block mapped to `electrical_service_upgrade`.

For the gas/propane call, `case_facts` includes `supporting_document_summary_for_upgrade_type` filtered to supporting-document types configured for that heat-pump path. The model can then evaluate rules such as source-fuel context, rebate-cap math, and required removal or permit evidence without being distracted by unrelated supporting documents.

For the electrical service upgrade call, the same invoice DI JSON is supplied, but the compiled tasks and filtered supporting-document context are different. The outputs are stored under the electrical service upgrade type id.

This is why the model stores validation outputs on `invoice_version_id` plus `invoice_upgrade_type_id`. One invoice PDF can produce multiple independent validation conversations, each with its own prompt tasks, supporting-document context, rulechecks, located fields, result, and advice.

## 9. External Product Reference Lists

External product reference lists are cached copies of qualified-product data used by deterministic code checks.

In the three-world model, product-list source, import-run, and product rows are download/import-world comparison material. A product match stored on an invoice version is evidence-world data.

The claims AI model uses these lists when a rule should be answered by a repeatable lookup rather than by GenAI judgement. GenAI may locate product evidence from an invoice or supporting document, but code performs the final product-list search and threshold comparison.

The current product-list families are:

- AHRI heat-pump rows for BC Hydro / qualified heat-pump checks.
- NEEA heat pump water heater rows.
- AWHP air-to-water / combined heat pump rows.
- OHPA oil-to-heat-pump affordability rows.

### 9.1 Product-list architecture

Each product-list family follows the same download/import-world three-table shape:

- A source table defines the stable source or list being imported.
- An import-run table records each refresh attempt and the source file metadata.
- A product table stores imported searchable rows from that run.

This pattern is deliberately separate from both registry and evidence. The source row is not a validation rule. The imported product row is not evidence for a claim by itself. It becomes claim evidence only when product lookup enrichment or a code rule matches it to an invoice version.

The source tables are:

- `claims.ahri_sources`
- `claims.neea_sources`
- `claims.awhp_sources`
- `claims.ohpa_sources`

The import-run tables are:

- `claims.ahri_import_runs`
- `claims.neea_import_runs`
- `claims.awhp_import_runs`
- `claims.ohpa_import_runs`

The product tables are:

- `claims.ahri_products`
- `claims.neea_products`
- `claims.awhp_products`
- `claims.ohpa_products`

The current-product views are:

- `claims.v_current_ahri_products`
- `claims.v_current_neea_products`
- `claims.v_current_awhp_products`
- `claims.v_current_ohpa_products`

Each current-product view selects product rows from the latest succeeded import run for each source. Code rules and admin product-list screens use these current views so failed or older imports do not silently become the active reference set.

When a product match is found for a processed invoice version, the matched row can be stored on `claims.invoice_versions`:

- `ahri_product_id`
- `neea_product_id`
- `awhp_product_id`
- `ohpa_product_id`

Those foreign keys are point-in-time match snapshots for the invoice version. Rulecheck rows explain whether the lookup passed, warned, or failed.

### 9.2 AHRI tables

The AHRI family supports air-source heat-pump and dual-fuel heat-pump checks where AHRI reference evidence is available.

The tables are:

- `claims.ahri_sources`: stable source definitions.
- `claims.ahri_import_runs`: import attempts for each source.
- `claims.ahri_products`: imported heat-pump product rows.

AHRI product rows include:

- `ahri_reference_number`
- `heat_pump_type`
- `make`
- `outdoor_model`
- `indoor_model_or_air_handler`
- `furnace_model`
- `rated_capacity_btu_at_minus_5c`
- `seer`, `seer2`, `hspf`, `hspf2`, and `cop`
- `capacity_maintenance_percent`
- `cold_climate_rated`
- `eligibility_notes`
- `raw_row_json`

The AHRI code checks can evaluate whether a located AHRI reference exists in the current imported products and whether the matched product satisfies capacity or efficiency thresholds.

### 9.3 NEEA tables

The NEEA family supports heat pump water heater product-list and tier checks.

The tables are:

- `claims.neea_sources`: stable NEEA source definitions.
- `claims.neea_import_runs`: import attempts for NEEA product-list PDFs.
- `claims.neea_products`: imported heat pump water heater rows.

NEEA product rows include:

- `brand` and `brand_normalized`
- `model_number`, `model_number_normalized`, `model_number_regex`, and `model_components`
- `storage_volume_gallons`
- `indoor_tier` and `indoor_cce`
- `outdoor_tier` and `outdoor_scop`
- `configuration`
- `flex_load_connectivity`
- `plug_in_endorsement`
- `qualified_date`
- `specification_version`
- `eligibility_notes`
- `raw_row_json`

The NEEA code checks use invoice located fields such as `hpwh_manufacturer`, `hpwh_model_number`, `hpwh_model_components`, and `hpwh_make_model`. The matching code normalizes manufacturer and model values before searching current NEEA rows.

### 9.4 AWHP tables

The AWHP family supports Better Homes BC air-to-water and combined space/water heat pump qualifying-product-list checks.

The tables are:

- `claims.awhp_sources`: stable air-to-water / combined heat-pump source definitions.
- `claims.awhp_import_runs`: import attempts for AWHP product-list PDFs.
- `claims.awhp_products`: imported qualifying-product rows.

AWHP product rows include:

- `brand` and `brand_normalized`
- `model_number`, `model_number_normalized`, `model_number_regex`, and `model_components`
- `system_type`
- `eligibility_notes`
- `raw_row_json`

AWHP matching uses invoice and supporting-document product evidence. For `air_to_water_heat_pump`, relevant invoice fields include `hp_make_model` and `atw_product_list_reference`. For `combined_space_water_heat_pump`, relevant invoice fields include `hp_make_model` and `cshp_product_list_reference`.

### 9.5 OHPA tables

The OHPA family supports NRCan Oil to Heat Pump Affordability BC product-list checks.

The tables are:

- `claims.ohpa_sources`: stable OHPA source definitions.
- `claims.ohpa_import_runs`: import attempts for OHPA CSV data.
- `claims.ohpa_products`: imported OHPA qualified-product rows.

OHPA product rows include:

- `ahri_reference_number`
- `brand` and `brand_normalized`
- `model_number`, `model_number_normalized`, `model_number_regex`, and `model_components`
- `indoor_model_numbers`
- `furnace_model_number`
- `product_group`
- `ahri_type`
- `ducting_configuration`
- `model_status`
- `series_name`
- `rated_capacity_47f`
- `rated_capacity_95f`
- `capacity_maintenance_percent`
- `cop_5f`
- `hspf2_region_iv`
- `hspf2_region_v`
- `seer2`
- `eligibility_notes`
- `raw_row_json`

OHPA matching is stricter than generic AHRI heat-pump matching because oil-to-heat-pump validation uses the invoice AHRI check, the supporting-document AHRI match check, and then the OHPA BC product-list lookup before treating the product-list match as strong.

### 9.6 `claims.ahri_sources`

`claims.ahri_sources` defines AHRI-related source lists.

Important columns are:

- `description`: human-readable source name.
- `source_url`: where the source list is obtained.
- `created_at` and `updated_at`: source-row audit timestamps.

Source rows are stable parents for import runs. They let the system track multiple sources independently if more than one AHRI-related list is used.

### 9.7 `claims.ahri_import_runs`

`claims.ahri_import_runs` records each AHRI import attempt.

Important columns are:

- `ahri_source_id`: parent source row.
- `storage_provider`, `storage_key`, `content_type`, and `byte_size`: imported source-file storage metadata.
- `status`: `queued`, `running`, `succeeded`, or `failed`.
- `started_at` and `completed_at`: import timing.
- `records_imported`: number of product rows inserted for the run.
- `publishing_notes` and `publishing_date`: source-publication context.
- `file_sha256`: source file hash.
- `error_text`: failure details.
- `metadata_json`: importer-specific metadata.

Only succeeded runs are eligible for current-product views.

### 9.8 `claims.ahri_products`

`claims.ahri_products` stores imported AHRI product rows for one import run.

Each product belongs to `claims.ahri_import_runs` through `import_run_id`. The most important lookup key is `ahri_reference_number`. Capacity, efficiency, and cold-climate columns support deterministic code checks after a row is matched.

The model stores `raw_row_json` so the exact imported source row remains available for troubleshooting even when normalized columns are enough for normal matching.

### 9.9 `claims.neea_sources`

`claims.neea_sources` defines NEEA heat pump water heater product-list sources.

The shape is the same as `claims.ahri_sources`: `description`, `source_url`, `created_at`, and `updated_at`.

### 9.10 `claims.neea_import_runs`

`claims.neea_import_runs` records each NEEA import attempt.

It has the same lifecycle columns as the AHRI import-run table: source id, source-file storage metadata, status, timing, record count, publishing metadata, hash, error text, and `metadata_json`.

The current NEEA product view selects rows from the latest succeeded import per NEEA source.

### 9.11 `claims.neea_products`

`claims.neea_products` stores imported heat pump water heater rows.

The important matching columns are `brand_normalized`, `model_number_normalized`, `model_number_regex`, and `model_components`. The important eligibility columns include indoor/outdoor tier, efficiency values, configuration, qualified date, and specification version.

Code can use these rows for both "found in product list" and "Tier 2 or higher" rulechecks.

### 9.12 `claims.awhp_sources`

`claims.awhp_sources` defines Better Homes BC air-to-water / combined heat pump source lists.

Like the other source tables, it stores `description`, `source_url`, and timestamps. Import runs are children of this table.

### 9.13 `claims.awhp_import_runs`

`claims.awhp_import_runs` records each AWHP source import attempt.

It uses the standard import-run lifecycle: `queued`, `running`, `succeeded`, or `failed`, plus source-file storage metadata, publishing metadata, row counts, hash, error text, and metadata JSON.

### 9.14 `claims.awhp_products`

`claims.awhp_products` stores imported air-to-water and combined heat-pump qualifying-product rows.

The key matching columns are normalized brand/model values, optional model regex/components, and `system_type`. The product-list code can compare invoice model evidence and supporting-document product evidence against the current AWHP rows.

### 9.15 `claims.ohpa_sources`

`claims.ohpa_sources` defines NRCan Oil to Heat Pump Affordability source lists.

It follows the same source-table pattern as the other product families.

### 9.16 `claims.ohpa_import_runs`

`claims.ohpa_import_runs` records each OHPA import attempt.

OHPA imports currently describe CSV data rather than PDF data, but the lifecycle is the same: source, source-file metadata, status, timing, row counts, publishing metadata, hash, errors, and importer metadata.

### 9.17 `claims.ohpa_products`

`claims.ohpa_products` stores imported OHPA BC qualified-product rows.

The important lookup column is `ahri_reference_number`. The table also stores brand/model fields, indoor/furnace model evidence, product group, AHRI type, ducting configuration, model status, series name, and performance fields.

These rows support oil-to-heat-pump checks where invoice AHRI evidence and supporting-document AHRI evidence need to agree and appear in the current OHPA list.

### 9.18 Example: AHRI match

An air-source heat-pump invoice version has a GenAI located field:

```text
field_key: hp_ahri_reference
value_text: 213617706
source_engine: genai
invoice_upgrade_type_id: air_source_heat_pump_gas_propane
```

The product lookup enrichment step normalizes the AHRI value and searches `claims.v_current_ahri_products`. If a row is found, the invoice version can store:

```text
ahri_product_id: matched claims.ahri_products.id
```

The AHRI code rules can then create rulechecks such as:

- `hp_ahri_found_in_product_list`
- `hp_product_minimum_capacity_at_minus_5c`
- `hp_product_efficiency_threshold`

The matched product row provides the product-list evidence; the rulecheck rows explain the lookup and threshold results.

### 9.19 Example: NEEA heat pump water heater match

A heat pump water heater invoice version has located fields such as:

```text
field_key: hpwh_manufacturer
value_text: Example Brand

field_key: hpwh_model_number
value_text: HPWH-50X
```

The product lookup enrichment step searches `claims.v_current_neea_products` using normalized manufacturer and model evidence. If matched, `claims.invoice_versions.neea_product_id` stores the matched `claims.neea_products.id`.

The code checks can then produce:

- `hpwh_neea_found_in_product_list`
- `hpwh_neea_tier_2_or_higher`

The first rule explains whether the model was found. The second rule explains whether the matched NEEA row satisfies the tier requirement.

### 9.20 Example: AWHP hydronic product match

An air-to-water or combined heat-pump invoice version includes invoice model evidence and supporting-document product evidence.

The AWHP product lookup uses fields such as:

- `hp_make_model`
- `atw_product_list_reference`
- `cshp_product_list_reference`
- Supporting-document `brand_and_model`
- Supporting-document `model_number`
- Supporting-document `product_list_reference`

If the invoice/supporting-document product evidence matches a current AWHP row, the invoice version can store `awhp_product_id`.

The `hydronic_product_found_in_qualifying_list` code rule then records whether product evidence was found, conflicting, unavailable, or successfully matched to the Better Homes BC qualifying list.

### 9.21 Example: OHPA oil-to-heat-pump match

An oil-to-heat-pump invoice version has invoice AHRI evidence, and a supporting product document also has AHRI evidence.

The oil AHRI checks compare:

```text
invoice hp_ahri_reference
supporting-document ahri_reference
```

The strongest pass path is:

1. Invoice AHRI is present.
2. Supporting-document AHRI is present.
3. The invoice and supporting-document AHRI values agree.
4. The AHRI value exists in `claims.v_current_ohpa_products`.

When that happens, the invoice version can store `ohpa_product_id`, `hp_invoice_ahri_reference_present` and `hp_supporting_document_ahri_matches_invoice` explain the AHRI evidence, and `ashp_oil_ohpa_bc_product_found_in_list` explains the OHPA BC product-list lookup.

If invoice and supporting-document AHRI values conflict, `hp_supporting_document_ahri_matches_invoice` owns the conflict result and the OHPA BC product-list lookup warns that it cannot be evaluated until the AHRI evidence is corrected.

## 10. Eligibility And Applicant Facts

Eligibility facts connect an invoice package to the participant/application context that already exists outside the invoice PDF.

The invoice may visibly contain an ESP eligibility code. The claims AI pipeline uses that visible code to look up `claims.users_eligibilitycodes`, load the participant from legacy `public.users`, and snapshot the relevant database facts into invoice-version evidence.

These facts support both GenAI review and deterministic code checks.

### 10.1 `claims.users_eligibilitycodes`

`claims.users_eligibilitycodes` stores ESP eligibility-code records owned by legacy `public.users` participants.

Important columns are:

- `user_id`: links to `public.users`.
- `eligibility_code`: visible/program code such as an `ESP1`, `ESP2`, `ESP3`, or `ESPI` code.
- `income_level`: normalized income level, currently `1`, `2`, or `3`.
- `applied_at`: when the participant applied.
- `approved_at`: when the eligibility code was approved.
- `expires_at`: when the eligibility code expires.
- `created_at` and `updated_at`: record timestamps.

Important constraints are:

- `eligibility_code` is globally unique.
- `(user_id, eligibility_code)` is unique as a defensive duplicate guard.
- `expires_at` must be after `applied_at`.
- `income_level` must be `1`, `2`, or `3`.
- The eligibility-code prefix must align with income level: `ESP1` or `ESPI` means level 1, `ESP2` means level 2, and `ESP3` means level 3.

The Rails model also derives `income_level` from the code prefix before validation. That keeps the database record consistent with the visible eligibility-code family.

### 10.2 Eligibility code lookup

Eligibility-code lookup starts with OCR/classification, not with a first-class Document Intelligence invoice field.

During triage, the classifier looks through the OCR/DI content and returns `eligibility_code` when it sees one. The GenAI case-facts builder normalizes that token and performs a case-insensitive lookup against `claims.users_eligibilitycodes.eligibility_code`.

If a matching row is found, the case-facts builder loads:

- The matched eligibility code.
- Income level.
- Approval date.
- Expiry date.
- Participant name from `public.users`.

These values are placed in `case_facts.esp_database_values` for GenAI and also persisted into `claims.invoice_version_located_fields` with `source_engine = 'code'`.

The persisted code located-field keys include:

- `users_eligibilitycodes.eligibility_code`
- `users_eligibilitycodes.income_level`
- `users_eligibilitycodes.approved_at`
- `users_eligibilitycodes.expires_at`
- `users.participant_name`

If the classifier found a code but the database lookup does not resolve, those database-derived fields remain empty or missing. The code rule `eligibility_code_found_in_database` then records that as a deterministic failure.

### 10.3 Income level

Income level is a database fact, not an OCR guess.

`claims.users_eligibilitycodes.income_level` is constrained to `1`, `2`, or `3`, and the model derives it from the eligibility-code prefix. The case-facts builder snapshots that value into `claims.invoice_version_located_fields` as:

```text
source_engine: code
field_key: users_eligibilitycodes.income_level
value_type: number
value_text: 1, 2, or 3
confidence: 100
evidence_text: ESP database
```

Some upgrade types are limited to participants registered and approved as Income Level 1 or 2. The code rule `income_level_1_or_2_required` reads the code located field and writes an upgrade-specific rulecheck.

The result pattern is:

- `pass`: income level is `1` or `2`.
- `fail`: income level is `3`.
- `warn`: the income-level field is missing or not parseable.

Because income level can affect eligibility, this check is deterministic and should not depend on GenAI interpretation.

### 10.4 Eligibility approval date window

The matched eligibility-code approval date is used to decide whether the invoice date falls inside the six-month completion window.

The case-facts builder snapshots:

- `users_eligibilitycodes.approved_at`

The common code rule `eligibility_code_valid_for_invoice_date` compares `claims.users_eligibilitycodes.approved_at` with `claims.invoice_versions.di_ocr_invoice_date`. The invoice date is currently used as the system proxy for upgrade completed date.

The core calculation is:

```text
approved_at <= invoice_date <= approved_at + 6 months
```

This rule intentionally does not use `claims.users_eligibilitycodes.expires_at`; the six-month deadline is calculated from the approval date.

The rule returns:

- `pass` when the invoice date is on or after the approval date and on or before six months after approval.
- `fail` when the invoice date falls outside that six-month approval window.
- `warn` when the invoice date, matched eligibility-code record, or approval date is missing or not parseable.

This rule is separate from visible invoice-code matching. A code can be visible and found in the database but still fail the date-window check.

### 10.5 Participant identity facts

The participant identity used by claims AI comes from the matched eligibility-code row and legacy `public.users`.

The case-facts builder loads the matched `public.users` row through `claims.users_eligibilitycodes.user_id`. It currently derives participant name from `first_name` and `last_name`, falling back to email if needed. Participant address is intentionally not populated yet because there is not a reliable participant-address column in the current model.

The participant name is included in:

```text
case_facts.esp_database_values.users.participant_name
```

It is also persisted as:

```text
source_engine: code
field_key: users.participant_name
value_type: text
evidence_text: ESP database
```

GenAI common rules can compare this database participant name to invoice-visible homeowner or customer evidence. For example, a common rule can warn when invoice homeowner evidence is missing or ambiguous, and fail when the invoice visibly belongs to a different participant.

### 10.6 Example: eligibility code found on invoice

An invoice contains the visible code:

```text
ESP2-123456
```

The classifier returns:

```text
eligibility_code: ESP2-123456
```

The case-facts builder finds a matching `claims.users_eligibilitycodes` row:

```text
eligibility_code: ESP2-123456
income_level: 2
approved_at: 2026-04-15
user_id: matched public.users.id
```

The invoice version then receives code located fields such as:

```text
field_key: users_eligibilitycodes.eligibility_code
value_text: ESP2-123456

field_key: users_eligibilitycodes.income_level
value_text: 2

field_key: users_eligibilitycodes.approved_at
value_text: 2026-04-15
```

If the invoice date is `2026-06-01`, the common eligibility date rule can pass because the invoice date falls within six months of the approval date. If the upgrade type requires Income Level 1 or 2, the income-level rule can also pass.

### 10.7 Example: eligibility code missing or expired

If the invoice does not visibly contain an eligibility code, the classifier returns `eligibility_code = null`. The case-facts builder cannot look up a `claims.users_eligibilitycodes` row, so database-derived eligibility fields are not populated.

The resulting checks can behave differently:

- `eligibility_code_found_in_database` fails when no code-located `users_eligibilitycodes.eligibility_code` value exists.
- `eligibility_code_valid_for_invoice_date` warns when it cannot evaluate the date window because the approval date is missing.
- GenAI identity rules may warn when they cannot compare invoice homeowner evidence to a matched participant record.

If the code is found but the invoice date is outside the six-month approval window, the database fields are populated, but the date-window calculation fails. For example:

```text
approved_at: 2026-01-01
invoice_date: 2026-08-01
```

The eligibility-code lookup succeeds, but `eligibility_code_valid_for_invoice_date` fails because `2026-08-01` is after six months from `2026-01-01`.

## 11. Admin, Revision, And History Tables

This section covers two different kinds of administrative data:

- Runtime review messages between admin staff and contractors.
- Configuration history snapshots for validation rules and located-field definitions.

Runtime review messages belong to invoice versions. Configuration history belongs to rule and field definition records.

### 11.1 `claims.admin_revision_requests`

`claims.admin_revision_requests` stores review-thread messages for one invoice version.

Despite the table name, it currently stores two message types:

- `admin_revision_request`: an admin-authored request asking the contractor to correct or provide something.
- `contractor_note`: a contractor-authored note or response.

Important columns are:

- `invoice_version_id`: the invoice version the message belongs to.
- `revreq_seqno`: sequence number within that invoice version.
- `requester_id`: author, linked to `public.users`.
- `message_type`: `admin_revision_request` or `contractor_note`.
- `request_text`: message body.
- `created_at` and `updated_at`: message timestamps.

The model auto-assigns `revreq_seqno` on create by taking the current maximum sequence number for that invoice version and adding one. The schema enforces uniqueness on `(invoice_version_id, revreq_seqno)`.

Admin revision requests can be created while the invoice is in `admin_review_inbox`, `in_review`, or `contractor_revision_inbox`. Contractor notes are created through the contractor portal against the latest invoice version for the invoice.

The `claims.v_revision_request_grid` view joins revision messages to sessions, invoices, and invoice versions so admin and contractor screens can show message context without manually joining every table.

### 11.2 Rule history tables

Rule history tables store pre-change snapshots of validation configuration records.

The rule history tables are:

- `claims.code_rule_history`
- `claims.code_rule_upgrade_type_history`
- `claims.genai_rule_history`
- `claims.genai_rule_upgrade_type_history`

These tables are not runtime rulecheck outputs. Runtime outputs live in `claims.invoice_version_rulechecks`. History rows answer a different question: "What did this rule definition or mapping look like before it was changed?"

For rule definition rows, history is created before update. For rule mapping rows, history is created before update and before destroy. This matters because deleting a mapping would otherwise erase evidence that the rule used to apply to an upgrade type.

### 11.3 Located-field history tables

Located-field history tables store pre-change snapshots of located-field configuration records.

The located-field history tables are:

- `claims.code_located_field_history`
- `claims.genai_located_field_history`
- `claims.genai_located_field_upgrade_type_history`

These tables are not runtime located-field values. Runtime values live in `claims.invoice_version_located_fields` and `claims.supporting_document_located_fields`. History rows preserve definition and mapping changes, such as prompt edits, enabled-flag changes, or field-order changes.

Code located-field definitions snapshot before update. GenAI located-field definitions snapshot before update. GenAI located-field upgrade-type mappings snapshot before update and before destroy.

### 11.4 `claims.code_rule_history`

`claims.code_rule_history` stores pre-change snapshots for `claims.code_rules`.

Important columns are:

- `source_id`: id of the `claims.code_rules` row being changed.
- `code_rule_key`: copied rule key.
- `description`: copied description.
- `enabled`: copied enabled flag.
- `pass_admin_message`, `info_admin_message`, `warn_admin_message`, and `fail_admin_message`: copied admin guidance.
- `admin_notes`: copied internal notes.
- `source_created_at` and `source_updated_at`: timestamps from the source row before the change.
- `history_created_at`: when the history row was created.

This table lets admins or developers see previous wording, enabled state, and guidance for deterministic code rules.

### 11.5 `claims.code_rule_upgrade_type_history`

`claims.code_rule_upgrade_type_history` stores pre-change snapshots for `claims.code_rule_upgrade_types`.

Important columns are:

- `source_id`: id of the mapping row being changed or deleted.
- `code_rule_id`: code rule that was mapped.
- `invoice_upgrade_type_id`: upgrade type that the rule applied to.
- `source_created_at` and `source_updated_at`: timestamps from the mapping row.
- `history_created_at`: when the history row was created.

The table keeps an audit trail when a code rule is remapped, reordered through replacement, or removed from an upgrade type.

### 11.6 `claims.code_located_field_history`

`claims.code_located_field_history` stores pre-change snapshots for `claims.code_located_fields`.

Important columns are:

- `source_id`: id of the `claims.code_located_fields` row.
- `code_field_key`: copied field key.
- `contractor_display_name`: copied contractor-friendly label.
- `description`: copied description.
- `enabled`: copied enabled flag.
- `source_created_at` and `source_updated_at`: source timestamps before the change.
- `history_created_at`: when the history row was created.

This table is useful when a database/code fact is disabled, renamed in description, or otherwise changed. Runtime values already written to invoice versions remain as evidence rows; this history table explains how the definition changed over time.

### 11.7 `claims.genai_rule_history`

`claims.genai_rule_history` stores pre-change snapshots for `claims.genai_rules`.

Important columns are:

- `source_id`: id of the `claims.genai_rules` row.
- `genai_rule_key`: copied rule key.
- `prompt_text`: copied prompt text.
- `enabled`: copied enabled flag.
- `source_created_at` and `source_updated_at`: source timestamps before the change.
- `history_created_at`: when the history row was created.

This table is especially important because prompt wording can materially change model behavior. A history row preserves the previous instruction before the current row is updated.

### 11.8 `claims.genai_rule_upgrade_type_history`

`claims.genai_rule_upgrade_type_history` stores pre-change snapshots for `claims.genai_rule_upgrade_types`.

Important columns are:

- `source_id`: id of the mapping row.
- `genai_rule_id`: GenAI rule that was mapped.
- `invoice_upgrade_type_id`: upgrade type the rule applied to.
- `source_created_at` and `source_updated_at`: source timestamps before the change.
- `history_created_at`: when the history row was created.

This table preserves previous GenAI rule upgrade-type applicability when mappings are changed or deleted.

### 11.9 `claims.genai_located_field_history`

`claims.genai_located_field_history` stores pre-change snapshots for `claims.genai_located_fields`.

Important columns are:

- `source_id`: id of the `claims.genai_located_fields` row.
- `genai_field_key`: copied field key.
- `contractor_display_name`: copied contractor-friendly label.
- `prompt_text`: copied field-location prompt.
- `enabled`: copied enabled flag.
- `source_created_at` and `source_updated_at`: source timestamps before the change.
- `history_created_at`: when the history row was created.

This table preserves previous field-location instructions before prompt text or enabled status changes.

### 11.10 `claims.genai_located_field_upgrade_type_history`

`claims.genai_located_field_upgrade_type_history` stores pre-change snapshots for `claims.genai_located_field_upgrade_types`.

Important columns are:

- `source_id`: id of the mapping row.
- `genai_field_id`: GenAI located-field definition that was mapped.
- `invoice_upgrade_type_id`: upgrade type the field applied to.
- `field_number`: ordered field number within that upgrade type.
- `source_created_at` and `source_updated_at`: source timestamps before the change.
- `history_created_at`: when the history row was created.

This table preserves previous GenAI located-field ordering and upgrade-type applicability when mappings are changed or deleted.

### 11.11 Example: prompt/rule audit history

An admin edits the GenAI rule `contractor_identity_matches_record` to clarify how DBA names should be handled.

Before the update is saved, the model callback writes a row to `claims.genai_rule_history` containing the old:

- `genai_rule_key`
- `prompt_text`
- `enabled` value
- source row timestamps

The current `claims.genai_rules` row then receives the new prompt text.

Later, if an invoice version has surprising GenAI output, a developer can inspect:

- `claims.ingest_step_runs.context_window_json` to see the exact prompt context used for that runtime call.
- `claims.genai_rule_history` to see previous prompt text values.
- `claims.invoice_version_rulechecks` to see the rulecheck result that was actually stored.

Those three records answer different audit questions: what was sent to the model, how the configured prompt changed over time, and what result was persisted for the invoice version.

## 12. Pipeline Step Runs And Invoice Status

This section explains how `claims.ingest_step_runs.step_type` lines up with `claims.invoices.status`.

The main thing to remember is that invoice status is a coarse user-facing lifecycle state, while step runs are detailed job/audit rows. Many step runs can happen while the invoice is in one status. For example, `ocr_read`, `triage_classifier`, `supporting_document_extraction`, and `ocr_invoice` all normally happen while the claim-level invoice is in `ocr_in_progress`.

The ingest schema diagram shows why the model looks a little unusual:

![Ingest schema](<ingest schema.png>)

`claims.ingest_runs` represents a package-processing attempt. `claims.ingest_documents` represents the uploaded files while they are still being interpreted. `claims.ingest_step_runs` records the individual work attempts performed against the package, staged documents, or resolved invoice version.

### 12.1 Why ingest documents are temp-like

`claims.ingest_documents` is best understood as a durable staging/workbench table.

It is temp-like because it is not the final business home for invoice evidence. At upload time, each PDF is just a staged file. The system does not yet know whether the PDF is the invoice, a supporting document, or an unknown file that should stop the package.

The staged row accumulates temporary interpretation state:

- Storage metadata for the uploaded PDF.
- OCR/read output from the broad Document Intelligence read model.
- Triage classifier output.
- Supporting-document type classification, if applicable.
- Routing quality and classification reasons.
- Links to the final promoted rows once resolution is complete.

It is not a literal SQL temporary table. The rows are retained because they are operational evidence. They explain which files were uploaded, what OCR saw, how classification behaved, why a package failed, and which durable row a staged file eventually became.

The bridge columns show the handoff:

- `invoice_id`: the shell or claim-level invoice used while the package is being staged.
- `resolved_invoice_id`: the final claim-level invoice after package resolution.
- `resolved_invoice_version_id`: set when the staged file becomes the invoice PDF/version.
- `promoted_supporting_document_id`: set when the staged file becomes a supporting document.

Once a staged invoice is resolved, first-class invoice OCR fields, line items, validation outputs, product matches, and final advice belong under `claims.invoice_versions` and its child tables. Once a staged supplement is promoted, supporting-document facts belong under `claims.supporting_documents` and `claims.supporting_document_located_fields`.

### 12.2 Why ingest runs are not children of invoice versions

`claims.ingest_runs` starts before an invoice version exists.

A package can contain zero invoice candidates, exactly one invoice candidate, multiple invoice candidates, supporting documents, or unknown files. The system must OCR-read and classify the staged files before it can safely create or reuse a `claims.invoice_versions` row.

That is why the model is:

```text
claims.sessions
  -> claims.ingest_runs
       -> claims.ingest_documents
            -> resolved_invoice_version_id after triage
```

and not:

```text
claims.invoice_versions
  -> claims.ingest_runs
```

If `ingest_runs` were a child of `invoice_versions`, failed or ambiguous packages would need fake invoice-version rows even when no resolved invoice exists. The current model keeps the run as the package attempt, then links the staged invoice document to the invoice version only after resolution.

In theory, `claims.ingest_runs` could also carry an `invoice_id` convenience pointer. That would make invoice-level reporting easier, but it would duplicate facts already present on `claims.ingest_documents.invoice_id` and `resolved_invoice_id`. The current design keeps the run as the neutral batch container and stores resolution facts on the staged documents.

### 12.3 Step phases

The pipeline has three broad operational phases.

Upload/package staging creates the session, ingest run, shell invoice, and staged document rows. The invoice status is `upload_in_progress`. Staging steps such as `upload_package_stage` or `reprocess_package_stage` are package-level steps and are not normal per-document Sidekiq OCR/GenAI work.

OCR and triage interpret the staged PDFs. The invoice status is `ocr_in_progress`. The system reads each staged file, classifies each file, optionally extracts facts from supporting documents, requires exactly one resolved invoice candidate, and then runs the invoice-model OCR against the resolved invoice version.

Validation and advice evaluate the resolved invoice version. The invoice status is `genai_in_progress`. The system builds case facts, runs GenAI common checks once, runs GenAI upgrade checks once per detected upgrade type, enriches product-list matches, runs deterministic code rules, and aggregates the final advice/result.

### 12.4 Step run reference

| Step type                        | Invoice status while running | Target                                          | Data model support                                                                                                                                                                                                                                                    |
| -------------------------------- | ---------------------------- | ----------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `upload_package_stage`           | `upload_in_progress`         | Package/run                                     | Creates or records the initial upload package. The run is `claims.ingest_runs`; uploaded files become `claims.ingest_documents`.                                                                                                                                      |
| `reprocess_package_stage`        | `upload_in_progress`         | Package/run                                     | Records redo/reprocess package staging for an existing claim-level invoice. New or reused PDFs are staged as `claims.ingest_documents`.                                                                                                                               |
| `ocr_read`                       | `ocr_in_progress`            | `ingest_document_id`                            | Runs broad Document Intelligence read OCR for each staged PDF. Results are stored on `claims.ingest_documents.di_read_raw_json` and `claims.ingest_step_runs.di_results_json`.                                                                                        |
| `triage_classifier`              | `ocr_in_progress`            | `ingest_document_id`                            | Classifies each staged PDF as `invoice`, `supplement`, or `unknown`. For invoice candidates it can also detect upgrade types and eligibility code. For supplements it sets supporting-document type and routing quality.                                              |
| `supporting_document_extraction` | `ocr_in_progress`            | `ingest_document_id`                            | Runs the supporting-document located-field GenAI prompt for each classified supplement that has configured fields. Output is later applied to `claims.supporting_document_located_fields` when the document is promoted.                                              |
| `ocr_invoice`                    | `ocr_in_progress`            | `invoice_version_id`                            | Requires exactly one invoice candidate. Creates or reuses `claims.invoice_versions`, calls the Document Intelligence invoice model, and populates invoice first-class OCR fields and `claims.lineitems`.                                                              |
| `case_facts`                     | `genai_in_progress`          | `invoice_version_id`                            | Builds database and document context for validation. This includes eligibility-code lookup, participant facts, invoice OCR fields, supporting-document summaries, line items, and detected upgrade types.                                                             |
| `genai_common`                   | `genai_in_progress`          | `invoice_version_id` plus `common` upgrade type | Runs the common GenAI validation call once for the invoice version. Outputs are stored in located fields, rulechecks, step-run JSON, and common-scope upgrade-type result rows.                                                                                       |
| `genai_upgrade`                  | `genai_in_progress`          | `invoice_version_id` plus detected upgrade type | Runs once per detected upgrade type. Each call receives upgrade-specific prompt tasks and filtered supporting-document context.                                                                                                                                       |
| `product_lookup_enrichment`      | `genai_in_progress`          | `invoice_version_id`                            | Searches downloaded product lists and writes product match foreign keys such as `ahri_product_id`, `neea_product_id`, `awhp_product_id`, or `ohpa_product_id` on `claims.invoice_versions`. These IDs support deterministic checks and PDF-viewer product accordions. |
| `code_common`                    | `genai_in_progress`          | `invoice_version_id` plus `common` upgrade type | Runs deterministic common rules, such as eligibility-code and invoice-date checks. Results are stored in `claims.invoice_version_rulechecks` with `source_engine = 'code'`.                                                                                           |
| `code_upgrade`                   | `genai_in_progress`          | `invoice_version_id` plus detected upgrade type | Runs deterministic rules for each detected upgrade type with enabled code rules. This includes product-list and upgrade-specific database/document comparisons.                                                                                                       |
| `aggregate_advice`               | `genai_in_progress`          | `invoice_version_id`                            | Combines GenAI and code outputs into final invoice-version summary fields such as `genai_result`, `genai_overall_confidence`, and `genai_admin_advice`.                                                                                                               |

Some step types are plural by nature. `ocr_read`, `triage_classifier`, and `supporting_document_extraction` can run once per staged document. `genai_upgrade` and `code_upgrade` can run once per detected upgrade type. `genai_common`, `code_common`, `product_lookup_enrichment`, and `aggregate_advice` are normally one row per validation pass.

### 12.5 Status interpretation

The `claims.invoices.status` value is intentionally broader than the individual step status.

During `upload_in_progress`, the package shell is being created and files are being staged. The durable invoice evidence does not exist yet, but the shell invoice lets the UI show a stable claim-level row.

During `ocr_in_progress`, the system is still moving from ambiguous staged files into durable evidence rows. This phase ends only after the package has exactly one resolved invoice candidate, supporting documents have been handled, invoice-model OCR has populated the invoice version, and the invoice is ready for validation.

During `genai_in_progress`, the target is a resolved `claims.invoice_versions` row. This is where the runtime moves from "what PDFs were uploaded?" to "what did the system decide about this invoice?"

Successful validation moves the invoice to `genai_complete`. OCR/package failures move it to `ocr_failed`. Validation failures move it to `genai_failed`. Admin workflow statuses such as `admin_review_inbox`, `contractor_revision_inbox`, `in_review`, `approved_pending`, `approved_paid`, and `ineligible` happen after the processing pipeline and describe human review state rather than Sidekiq processing state.

### 12.6 Processing entry points

There are multiple entry points into the same data model.

The normal invoice upload path creates a new package: session, shell invoice, ingest run, staged ingest documents, OCR/triage, resolved invoice version, validation, and final advice.

The redo package path starts from an existing `claims.invoices` row but still uses the staging model. It creates a new ingest run, stages the replacement or supplemented package, reruns OCR/triage, and creates a new invoice version when the corrected invoice PDF is resolved.

A GenAI-only rerun does not need to rebuild the package staging layer. It can start at the validation phase for an existing `claims.invoice_versions` row. In data terms, that means the first important step is `case_facts`, followed by GenAI, product lookup, code rules, and aggregate advice. This path reuses the existing invoice OCR, line items, supporting-document context, and detected upgrade types.

## 13. Alphabetical Table Catalog

This catalog is the quick lookup version of the earlier narrative sections. The categories use the three-world model:

- Evidence: rows created for a real claim, package, invoice version, supporting document, or processing attempt.
- Registry: reusable rules, fields, prompt configuration, lookup concepts, and mappings.
- Download/import: external product-list sources, import runs, and imported rows.
- History: pre-change snapshots of registry rows.

### 13.1 `claims.admin_revision_requests`

Category: evidence, admin workflow.

Parent/child shape: belongs to `claims.invoice_versions`; author is `public.users` through `requester_id`.

Key columns: `invoice_version_id`, `revreq_seqno`, `requester_id`, `message_type`, `request_text`.

Lifecycle notes: stores admin revision requests and contractor notes in a sequenced thread for one invoice version. It is review communication evidence, not validation output.

### 13.2 `claims.ahri_import_runs`

Category: download/import.

Parent/child shape: belongs to `claims.ahri_sources`; parent of imported `claims.ahri_products`.

Key columns: `ahri_source_id`, `status`, `source_filename`, `source_storage_key`, `downloaded_at`, `imported_at`, `row_count`, `error_text`.

Lifecycle notes: one row records one AHRI list refresh attempt. Successful runs make imported AHRI product rows available to current-product views and deterministic product matching.

### 13.3 `claims.ahri_products`

Category: download/import.

Parent/child shape: belongs to `claims.ahri_import_runs`; may be referenced by `claims.invoice_versions.ahri_product_id`.

Key columns: `import_run_id`, `ahri_reference_number`, manufacturer/model fields, capacity and efficiency fields, cold-climate qualification fields.

Lifecycle notes: imported AHRI heat-pump rows are comparison material. They become invoice evidence only when a processed invoice version stores a match to one row.

### 13.4 `claims.ahri_sources`

Category: download/import.

Parent/child shape: parent of `claims.ahri_import_runs`.

Key columns: `description`, `source_url`, timestamps.

Lifecycle notes: stable source definition for AHRI-related product lists. The source row identifies where imports come from; it is not itself claim evidence.

### 13.5 `claims.awhp_import_runs`

Category: download/import.

Parent/child shape: belongs to `claims.awhp_sources`; parent of `claims.awhp_products`.

Key columns: `awhp_source_id`, `status`, source-file metadata, row counts, error text, import timestamps.

Lifecycle notes: one row per AWHP product-list import attempt. Successful imports refresh the searchable hydronic/air-to-water product snapshot used by code rules.

### 13.6 `claims.awhp_products`

Category: download/import.

Parent/child shape: belongs to `claims.awhp_import_runs`; may be referenced by `claims.invoice_versions.awhp_product_id`.

Key columns: `import_run_id`, manufacturer/model fields, product-family fields, eligibility or qualifying-list attributes.

Lifecycle notes: imported AWHP qualifying-product rows support deterministic air-to-water and combined heat-pump checks.

### 13.7 `claims.awhp_sources`

Category: download/import.

Parent/child shape: parent of `claims.awhp_import_runs`.

Key columns: `description`, `source_url`, timestamps.

Lifecycle notes: stable source definition for AWHP product-list imports.

### 13.8 `claims.code_located_field_history`

Category: history.

Parent/child shape: snapshot of `claims.code_located_fields`; no runtime child rows.

Key columns: `source_id`, `code_field_key`, `contractor_display_name`, `description`, `enabled`, source timestamps, `history_created_at`.

Lifecycle notes: preserves the previous code-located-field definition before edits. Runtime values remain in `claims.invoice_version_located_fields`.

### 13.9 `claims.code_located_fields`

Category: registry.

Parent/child shape: read by the case-facts builder; history is stored in `claims.code_located_field_history`.

Key columns: `code_field_key`, `contractor_display_name`, `description`, `enabled`.

Lifecycle notes: defines database/code facts that may be snapshotted into invoice-version located fields with `source_engine = 'code'`, such as eligibility-code and participant facts.

### 13.10 `claims.code_rule_history`

Category: history.

Parent/child shape: snapshot of `claims.code_rules`.

Key columns: `source_id`, `code_rule_key`, `description`, enabled flag, admin-message fields, source timestamps, `history_created_at`.

Lifecycle notes: preserves code-rule wording and guidance before configuration edits.

### 13.11 `claims.code_rule_upgrade_type_history`

Category: history.

Parent/child shape: snapshot of `claims.code_rule_upgrade_types`.

Key columns: `source_id`, `code_rule_id`, `invoice_upgrade_type_id`, source timestamps, `history_created_at`.

Lifecycle notes: records previous deterministic-rule applicability when code rules are remapped or removed from upgrade types.

### 13.12 `claims.code_rule_upgrade_types`

Category: registry.

Parent/child shape: joins `claims.code_rules` to `claims.invoice_upgrade_types`.

Key columns: `code_rule_id`, `invoice_upgrade_type_id`.

Lifecycle notes: controls which deterministic code rules apply to each upgrade type. Runtime outputs are stored in `claims.invoice_version_rulechecks`.

### 13.13 `claims.code_rules`

Category: registry.

Parent/child shape: parent of `claims.code_rule_upgrade_types`; history parent for `claims.code_rule_history`.

Key columns: `code_rule_key`, `description`, `enabled`, admin-message fields, `admin_notes`.

Lifecycle notes: defines deterministic validation checks. A code rule is reusable configuration; it is not evidence until code writes a rulecheck for an invoice version.

### 13.14 `claims.genai_located_field_history`

Category: history.

Parent/child shape: snapshot of `claims.genai_located_fields`.

Key columns: `source_id`, `genai_field_key`, `contractor_display_name`, `prompt_text`, `enabled`, source timestamps, `history_created_at`.

Lifecycle notes: preserves previous GenAI located-field prompt wording before edits.

### 13.15 `claims.genai_located_field_upgrade_type_history`

Category: history.

Parent/child shape: snapshot of `claims.genai_located_field_upgrade_types`.

Key columns: `source_id`, `genai_field_id`, `invoice_upgrade_type_id`, `field_number`, source timestamps, `history_created_at`.

Lifecycle notes: preserves previous located-field applicability and ordering when mappings change.

### 13.16 `claims.genai_located_field_upgrade_types`

Category: registry.

Parent/child shape: joins `claims.genai_located_fields` to `claims.invoice_upgrade_types`.

Key columns: `genai_field_id`, `invoice_upgrade_type_id`, `field_number`.

Lifecycle notes: controls which GenAI located-field tasks are compiled into the context window for each upgrade type and in what order.

### 13.17 `claims.genai_located_fields`

Category: registry.

Parent/child shape: parent of `claims.genai_located_field_upgrade_types`; history parent for `claims.genai_located_field_history`.

Key columns: `genai_field_key`, `contractor_display_name`, `prompt_text`, `enabled`.

Lifecycle notes: defines reusable GenAI field-location tasks. Runtime extracted values are stored in `claims.invoice_version_located_fields`.

### 13.18 `claims.genai_rule_history`

Category: history.

Parent/child shape: snapshot of `claims.genai_rules`.

Key columns: `source_id`, `genai_rule_key`, `prompt_text`, `enabled`, source timestamps, `history_created_at`.

Lifecycle notes: preserves previous rule prompt wording before edits. This is especially important because prompt changes can change model behavior.

### 13.19 `claims.genai_rule_upgrade_type_history`

Category: history.

Parent/child shape: snapshot of `claims.genai_rule_upgrade_types`.

Key columns: `source_id`, `genai_rule_id`, `invoice_upgrade_type_id`, source timestamps, `history_created_at`.

Lifecycle notes: preserves previous GenAI rule applicability when mappings change.

### 13.20 `claims.genai_rule_upgrade_types`

Category: registry.

Parent/child shape: joins `claims.genai_rules` to `claims.invoice_upgrade_types`.

Key columns: `genai_rule_id`, `invoice_upgrade_type_id`.

Lifecycle notes: controls which GenAI rulecheck tasks are compiled into each common or upgrade-specific context window.

### 13.21 `claims.genai_rules`

Category: registry.

Parent/child shape: parent of `claims.genai_rule_upgrade_types`; history parent for `claims.genai_rule_history`.

Key columns: `genai_rule_key`, `prompt_text`, `enabled`.

Lifecycle notes: defines reusable GenAI rulecheck tasks. Runtime rule outcomes are stored in `claims.invoice_version_rulechecks`.

### 13.22 `claims.ingest_documents`

Category: evidence, staging.

Parent/child shape: belongs to `claims.ingest_runs`, `claims.sessions`, and `public.contractors`; may link to `claims.invoices`, `claims.invoice_versions`, and `claims.supporting_documents` after resolution.

Key columns: `ingest_run_id`, `invoice_id`, `resolved_invoice_id`, `resolved_invoice_version_id`, `promoted_supporting_document_id`, storage metadata, `di_read_raw_json`, `classifier_raw_json`, `document_kind`, `supporting_document_type_id`, classification fields.

Lifecycle notes: durable staging/workbench table for uploaded PDFs before the system knows whether each file is an invoice, supplement, or unknown. It remains as an audit trail after promotion.

### 13.23 `claims.ingest_runs`

Category: evidence, package processing.

Parent/child shape: belongs to `claims.sessions`; parent of `claims.ingest_documents`; may be linked from `claims.ingest_step_runs`.

Key columns: `session_id`, `status`, `total_files`, `completed_files`, `failed_files`, `messages`, `completed_at`.

Lifecycle notes: one row per package-processing attempt or redo package. It starts before an invoice version exists and completes only after the package resolves and downstream processing succeeds or fails.

### 13.24 `claims.ingest_step_runs`

Category: evidence, job audit.

Parent/child shape: optionally belongs to `claims.ingest_runs`; targets either `claims.ingest_documents` or `claims.invoice_versions`; typed GenAI/code calls may also reference `claims.invoice_upgrade_types`.

Key columns: `step_type`, `status`, `error_text`, `ingest_run_id`, `ingest_document_id`, `invoice_version_id`, `invoice_upgrade_type_id`, `di_results_json`, `genai_results_json`, `context_window_json`.

Lifecycle notes: audit table for individual processing attempts. It stores raw OCR/GenAI responses and the exact GenAI context window for review and troubleshooting.

### 13.25 `claims.invoice_upgrade_types`

Category: registry.

Parent/child shape: parent lookup for line items, supporting-document mappings, GenAI/code mappings, located fields, rulechecks, and invoice-version upgrade classifications.

Key columns: `upgrade_type_key`, `name`, timestamps.

Lifecycle notes: source of truth for claims AI upgrade domains, including the special `common` scope for claim-level checks.

### 13.26 `claims.invoice_version_located_fields`

Category: evidence.

Parent/child shape: belongs to `claims.invoice_versions`; may reference `claims.invoice_upgrade_types`.

Key columns: `invoice_version_id`, `invoice_upgrade_type_id`, `source_engine`, `field_key`, `value_type`, value columns, `confidence`, `evidence_text`, page/polygon fields.

Lifecycle notes: stores runtime facts located from invoice OCR, GenAI, deterministic code, or database context for a specific invoice version.

### 13.27 `claims.invoice_version_rulechecks`

Category: evidence.

Parent/child shape: belongs to `claims.invoice_versions` and `claims.invoice_upgrade_types`.

Key columns: `invoice_version_id`, `invoice_upgrade_type_id`, `source_engine`, `rule_key`, `rule_result`, `confidence`, `expected_text`, `calculation`, `evidence_text`, `reason_and_likely_causes`.

Lifecycle notes: stores validation outcomes from GenAI and deterministic code. It is the detailed source behind pass/warn/fail review evidence.

### 13.28 `claims.invoice_version_upgrade_types`

Category: evidence.

Parent/child shape: joins `claims.invoice_versions` to `claims.invoice_upgrade_types`.

Key columns: `invoice_version_id`, `invoice_upgrade_type_id`, `source_engine`, `call_status`, confidence/result/advice fields, raw JSON fields.

Lifecycle notes: records detected or evaluated upgrade types for one invoice version. Classifier rows answer what upgrades were found; GenAI rows summarize per-upgrade validation call status and advice.

### 13.29 `claims.invoice_versions`

Category: evidence.

Parent/child shape: belongs to `claims.invoices`; parent of line items, located fields, rulechecks, revision messages, upgrade-type rows, and invoice-targeted step runs.

Key columns: `invoice_id`, `invoice_versionno`, storage metadata, DI/OCR raw JSON and first-class invoice fields, aggregate GenAI result/advice fields, product match foreign keys.

Lifecycle notes: represents one processed invoice PDF under a stable claim-level invoice. Replacements and reruns create new versions rather than overwriting the claim-level invoice record.

### 13.30 `claims.invoices`

Category: evidence, claim workflow.

Parent/child shape: belongs to `claims.sessions`, `public.contractors`, and optionally `public.users` as submitter; parent of `claims.invoice_versions`, supporting documents, and staged ingest documents.

Key columns: `session_id`, `contractor_id`, `submitter_id`, `status`, `status_updated_at`, `submitted_at`, `system_help_notes`.

Lifecycle notes: stable claim-level invoice review row shown by the UI. It owns broad processing and business workflow status, while most AI outputs belong to invoice versions.

### 13.31 `claims.lineitems`

Category: evidence.

Parent/child shape: belongs to `claims.invoice_versions`; may reference `claims.invoice_upgrade_types`.

Key columns: `invoice_version_id`, `invoice_upgrade_type_id`, `lineitem_seqno`, OCR description, quantity, unit price, amount, page/polygon fields.

Lifecycle notes: stores invoice line items extracted by the Document Intelligence invoice model. Line items are version-specific and can be associated with upgrade types.

### 13.32 `claims.neea_import_runs`

Category: download/import.

Parent/child shape: belongs to `claims.neea_sources`; parent of `claims.neea_products`.

Key columns: `neea_source_id`, `status`, source-file metadata, row counts, error text, import timestamps.

Lifecycle notes: one row per NEEA product-list import attempt.

### 13.33 `claims.neea_products`

Category: download/import.

Parent/child shape: belongs to `claims.neea_import_runs`; may be referenced by `claims.invoice_versions.neea_product_id`.

Key columns: `import_run_id`, manufacturer/model/product fields and normalized lookup fields.

Lifecycle notes: imported heat pump water heater rows used for deterministic NEEA product matching.

### 13.34 `claims.neea_sources`

Category: download/import.

Parent/child shape: parent of `claims.neea_import_runs`.

Key columns: `description`, `source_url`, timestamps.

Lifecycle notes: stable source definition for NEEA heat pump water heater product-list imports.

### 13.35 `claims.ohpa_import_runs`

Category: download/import.

Parent/child shape: belongs to `claims.ohpa_sources`; parent of `claims.ohpa_products`.

Key columns: `ohpa_source_id`, `status`, source-file metadata, row counts, error text, import timestamps.

Lifecycle notes: one row per OHPA product-list import attempt.

### 13.36 `claims.ohpa_products`

Category: download/import.

Parent/child shape: belongs to `claims.ohpa_import_runs`; may be referenced by `claims.invoice_versions.ohpa_product_id`.

Key columns: `import_run_id`, AHRI/manufacturer/model fields, heat-pump type fields, qualifying attributes.

Lifecycle notes: imported OHPA BC qualified-product rows used by oil-to-heat-pump deterministic checks.

### 13.37 `claims.ohpa_sources`

Category: download/import.

Parent/child shape: parent of `claims.ohpa_import_runs`.

Key columns: `description`, `source_url`, timestamps.

Lifecycle notes: stable source definition for OHPA product-list imports.

### 13.38 `claims.sessions`

Category: evidence.

Parent/child shape: parent of `claims.invoices`, `claims.ingest_runs`, `claims.ingest_documents`, and `claims.ingest_step_runs`.

Key columns: `id`, `created_at`, `updated_at`.

Lifecycle notes: claims-owned grouping record for the AI subsystem. Most business meaning lives in child rows.

### 13.39 `claims.supporting_document_located_fields`

Category: evidence.

Parent/child shape: belongs to `claims.supporting_documents` and `claims.supporting_document_type_located_fields`.

Key columns: `supporting_document_id`, `supporting_document_type_located_field_id`, `field_key`, `source_engine`, `value_type`, value columns, `confidence`, `evidence_text`, page/polygon fields.

Lifecycle notes: stores extracted facts from promoted supporting documents, such as utility account numbers, manufacturer label values, or permit facts.

### 13.40 `claims.supporting_document_type_located_fields`

Category: registry.

Parent/child shape: belongs to `claims.supporting_document_types`; parent definition for `claims.supporting_document_located_fields`.

Key columns: `supporting_document_type_id`, `field_key`, `contractor_display_name`, `prompt_text`, `field_number`, `enabled`.

Lifecycle notes: defines which facts should be extracted from each supporting-document type.

### 13.41 `claims.supporting_document_type_upgrade_types`

Category: registry.

Parent/child shape: joins `claims.supporting_document_types` to `claims.invoice_upgrade_types`.

Key columns: `supporting_document_type_id`, `invoice_upgrade_type_id`, `required`.

Lifecycle notes: describes which supporting-document types apply to which upgrade types and whether they are expected for that upgrade context.

### 13.42 `claims.supporting_document_types`

Category: registry.

Parent/child shape: parent of supporting-document mappings, located-field definitions, staged document classifications, and promoted supporting documents.

Key columns: `type_key`, `display_name`, `description`, `enabled`.

Lifecycle notes: defines reusable supporting-document categories such as utility bills, permit documents, manufacturer labels, or removal evidence.

### 13.43 `claims.supporting_documents`

Category: evidence.

Parent/child shape: belongs to `claims.invoices` and `claims.supporting_document_types`; parent of `claims.supporting_document_located_fields`; may be linked from `claims.ingest_documents.promoted_supporting_document_id`.

Key columns: `invoice_id`, `supporting_document_type_id`, storage metadata, DI/read JSON, classifier JSON, classification status/confidence/reason, routing quality fields.

Lifecycle notes: durable promoted supporting-document row after a staged supplement has been classified and attached to a claim-level invoice.

### 13.44 `claims.users_eligibilitycodes`

Category: registry/reference.

Parent/child shape: belongs to legacy `public.users`; read by the claims AI case-facts builder.

Key columns: `user_id`, `eligibility_code`, `income_level`, `applied_at`, `approved_at`, `expires_at`.

Lifecycle notes: stores ESP eligibility-code records used as database context for GenAI and deterministic code checks. Runtime snapshots are written as code located fields on invoice versions.

### 13.45 `claims.validationgenai_config`

Category: registry.

Parent/child shape: singleton-style configuration row read by classifier, supporting-document extraction, and invoice-validation prompt builders.

Key columns: `system_record`, `classifier_system_record`, `supporting_document_extraction_system_record`, `user_record0`, `admin_advice_intro`, `admin_advice_closing`.

Lifecycle notes: stores global prompt/configuration text. The exact prompt used for a runtime call is snapshotted into `claims.ingest_step_runs.context_window_json`.

## 14. Scenario Examples

This section walks through common data-model scenarios. The examples are intentionally compact. Their purpose is to show which tables participate and where evidence lands.

### 14.1 Scenario: one invoice, one upgrade type, no supporting docs

A contractor uploads one invoice PDF for an electric air-source heat pump. The package contains no supporting documents.

The package creates:

- One `claims.sessions` row.
- One shell `claims.invoices` row with status `upload_in_progress`, then `ocr_in_progress`.
- One `claims.ingest_runs` row.
- One `claims.ingest_documents` row for the uploaded invoice PDF.

The staged file receives `ocr_read` and `triage_classifier` step runs. The classifier sets `document_kind = 'invoice'` and detects `air_source_heat_pump_electric`.

Because there is exactly one invoice candidate, the system creates `claims.invoice_versions` version `1`, runs `ocr_invoice`, writes first-class DI invoice fields and `claims.lineitems`, then runs GenAI and code validation.

The evidence world now contains:

- `claims.invoice_version_upgrade_types` for `common` and `air_source_heat_pump_electric`.
- `claims.invoice_version_located_fields` for invoice and database facts.
- `claims.invoice_version_rulechecks` for common and heat-pump checks.
- `claims.ingest_step_runs` for OCR, classifier, case facts, GenAI, code, product lookup, and aggregate advice.

No `claims.supporting_documents` rows are created. If no mandatory supporting-document rule applies for this upgrade path, the invoice can still reach `genai_complete`.

### 14.2 Scenario: one invoice, one upgrade type, required supporting doc attached

A contractor uploads an invoice PDF and a fossil-fuel removal proof PDF for a gas/propane-to-heat-pump claim.

The package creates one ingest run and two staged ingest documents. Both files receive `ocr_read` and `triage_classifier` steps.

The classifier results are:

```text
Invoice.pdf              -> document_kind = invoice
Removal proof.pdf        -> document_kind = supplement
Removal proof.pdf        -> supporting_document_type = fossil_fuel_removal_proof
```

The system resolves the invoice, creates `claims.invoice_versions` version `1`, and promotes the supplement into `claims.supporting_documents`. If the supporting-document type has configured fields, `supporting_document_extraction` output is applied into `claims.supporting_document_located_fields`.

During GenAI validation, `case_facts.supporting_document_summary_for_upgrade_type` shows that the removal proof is present for `air_source_heat_pump_gas_propane`. The GenAI rule for required removal evidence can then pass or evaluate the actual document content instead of failing for missing attachment.

The key data-model point is that the supporting document is attached to the claim-level invoice through `claims.supporting_documents.invoice_id`, while its extracted facts are available to invoice-version validation through the case-facts builder.

### 14.3 Scenario: one invoice, multiple upgrade types

One invoice PDF contains both heat-pump work and electrical service upgrade work.

The package still resolves to one `claims.invoices` row and one current `claims.invoice_versions` row. The plural part is below the invoice version:

- `claims.invoice_version_upgrade_types` has classifier rows for `air_source_heat_pump_electric` and `electrical_service_upgrade`.
- `claims.lineitems` can associate different line items with different `invoice_upgrade_type_id` values.
- GenAI runs one `genai_common` call and one `genai_upgrade` call per detected upgrade type.
- Code runs common checks and upgrade-specific code checks where enabled.
- Rulechecks and located fields are tagged with the relevant `invoice_upgrade_type_id`.

This keeps the outputs separate. A failed electrical-service rule does not automatically mean the heat-pump upgrade failed, and a heat-pump product-list match does not apply to electrical-service work.

### 14.4 Scenario: redo package with previous processed outputs preserved

A contractor uploaded an invoice package, processing completed, and the claim has invoice version `1`. Later, the contractor or admin decides a corrected package is needed.

The redo package creates a new `claims.ingest_runs` row and new staged `claims.ingest_documents` rows. The existing `claims.invoices` row remains the stable claim-level review case.

When the corrected invoice PDF is resolved, the system creates invoice version `2` under the same invoice:

```text
claims.invoices.id = same claim-level invoice
claims.invoice_versions.invoice_versionno = 1 for original PDF
claims.invoice_versions.invoice_versionno = 2 for corrected PDF
```

Version `2` receives its own OCR JSON, line items, located fields, rulechecks, upgrade-type rows, product matches, GenAI outputs, and step runs. Version `1` remains available for audit and comparison, but current-version views prefer version `2`.

The important distinction is preservation, not mutation. Reprocessing creates new versioned evidence rather than rewriting the old invoice-version evidence in place.

### 14.5 Scenario: supporting document added before redo package

An admin asks the contractor to attach a missing supporting document. The contractor adds the document, then the package is redone so the new supporting document can be included in validation context.

The added file is staged as `claims.ingest_documents` during the redo package. It is OCR-read, classified as a supplement, and promoted into `claims.supporting_documents` after the redo package resolves to exactly one invoice.

If the document has configured located fields, those extracted facts are stored in `claims.supporting_document_located_fields`. During the validation phase for the new invoice version, `case_facts` includes the newly promoted supporting document and its extracted facts.

The current invoice version can then produce different rulechecks from the previous version. For example, a previous `warn` or `fail` for missing utility-upgrade evidence may become `pass` after the supporting document is attached and promoted.

### 14.6 Scenario: missing mandatory supporting document

An invoice is classified as `air_source_heat_pump_gas_propane`, but the package does not contain a fossil-fuel removal proof or permit/removal document required by the configured rule.

The data model still records the detected upgrade and runs validation:

- `claims.invoice_version_upgrade_types` records the detected gas/propane heat-pump upgrade.
- `claims.supporting_documents` has no promoted document of the required type.
- `case_facts.supporting_document_summary_for_upgrade_type` marks the required supporting document as missing.
- `claims.invoice_version_rulechecks` stores the failing or warning rule outcome.

For rules that define the attachment as mandatory, the output should be `fail`, not merely `warn`. The missing document is not an OCR ambiguity; it is a missing required evidence record in the package context.

### 14.7 Scenario: external product-list match

An invoice shows an AHRI reference for a heat pump. The product lookup enrichment step searches the current AHRI product-list view.

If the AHRI reference matches a current imported row, the system can store:

```text
claims.invoice_versions.ahri_product_id = matched claims.ahri_products.id
```

The matched product row came from the download/import world. The invoice-version foreign key is what turns that imported product-list row into evidence for this processed invoice version.

Code rules can then write rulechecks such as:

- AHRI reference found in product list.
- Product capacity meets threshold.
- Product efficiency meets threshold.

The product-list row itself is not a validation result. The rulecheck rows explain why the match passed, warned, or failed.

### 14.8 Scenario: product-list mismatch between invoice and supporting document

An oil-to-heat-pump package has AHRI evidence on the invoice and AHRI evidence on a manufacturer label or product specification supporting document.

The invoice located field might say:

```text
hp_ahri_reference = 1234567
```

The supporting-document located field might say:

```text
ahri_reference = 7654321
```

Even if both AHRI values individually exist in a product list, code cannot safely link the invoice version to one product. The product-list code rule should write a `fail` or `warn` depending on the rule semantics, with calculation and reason text explaining the conflict.

The data-model point is that evidence disagreement is stored as rulecheck evidence. The system should not silently pick one product row and hide the mismatch.

### 14.9 Scenario: GenAI warning that requires admin review

An invoice contains a heat-pump model and rebate amount, but the existing heating context is vague. For example, the invoice says "replace old system" without clearly saying whether the old system was electric, gas, propane, oil, or wood.

GenAI may locate partial evidence:

```text
field_key = hp_existing_heat_context
value_text = replace old system
confidence = 55
```

The corresponding rulecheck may be:

```text
rule_result = warn
reason_and_likely_causes = Existing heating fuel context is ambiguous.
```

The invoice can still reach `genai_complete` because processing succeeded. The warning is review evidence, not a processing failure. Admin review can then decide whether the ambiguity is acceptable, needs contractor revision, or makes the claim ineligible.

### 14.10 Scenario: code rule failure

An invoice contains an ESP eligibility code, but the database lookup shows the invoice date is outside the approved eligibility window.

The case-facts builder snapshots the database values into code located fields:

```text
users_eligibilitycodes.eligibility_code = ESP2-123456
users_eligibilitycodes.approved_at = 2026-01-01
users_eligibilitycodes.expires_at = 2026-03-31
invoice_versions.di_ocr_invoice_date = 2026-05-10
```

The deterministic code rule compares:

```text
approved_at <= invoice_date <= expires_at
```

Because `2026-05-10` is after `2026-03-31`, code writes a failed `claims.invoice_version_rulechecks` row. This does not depend on GenAI judgement because the dates are database/OCR facts and the comparison is deterministic.

The invoice-version evidence now contains both the underlying located fields and the code-owned rulecheck explaining the failure.

## 15. Appendices

### 15.1 Full table list

The live claims schema currently contains 45 tables.

Evidence and workflow tables:

- `claims.admin_revision_requests`
- `claims.ingest_documents`
- `claims.ingest_runs`
- `claims.ingest_step_runs`
- `claims.invoice_version_located_fields`
- `claims.invoice_version_rulechecks`
- `claims.invoice_version_upgrade_types`
- `claims.invoice_versions`
- `claims.invoices`
- `claims.lineitems`
- `claims.sessions`
- `claims.supporting_document_located_fields`
- `claims.supporting_documents`

Registry and configuration tables:

- `claims.code_located_fields`
- `claims.code_rule_upgrade_types`
- `claims.code_rules`
- `claims.genai_located_field_upgrade_types`
- `claims.genai_located_fields`
- `claims.genai_rule_upgrade_types`
- `claims.genai_rules`
- `claims.invoice_upgrade_types`
- `claims.supporting_document_type_located_fields`
- `claims.supporting_document_type_upgrade_types`
- `claims.supporting_document_types`
- `claims.users_eligibilitycodes`
- `claims.validationgenai_config`

Download/import tables:

- `claims.ahri_import_runs`
- `claims.ahri_products`
- `claims.ahri_sources`
- `claims.awhp_import_runs`
- `claims.awhp_products`
- `claims.awhp_sources`
- `claims.neea_import_runs`
- `claims.neea_products`
- `claims.neea_sources`
- `claims.ohpa_import_runs`
- `claims.ohpa_products`
- `claims.ohpa_sources`

History tables:

- `claims.code_located_field_history`
- `claims.code_rule_history`
- `claims.code_rule_upgrade_type_history`
- `claims.genai_located_field_history`
- `claims.genai_located_field_upgrade_type_history`
- `claims.genai_rule_history`
- `claims.genai_rule_upgrade_type_history`

### 15.2 Status and enum glossary

`claims.invoices.status` values:

- `upload_queued`: reserved processing state before upload work starts.
- `upload_in_progress`: package shell and files are being staged.
- `upload_failed`: package upload/staging failed.
- `upload_complete`: reserved completed-upload state.
- `ocr_queued`: reserved processing state before OCR work starts.
- `ocr_in_progress`: staged PDFs are being read, classified, promoted, and invoice OCR is running.
- `ocr_failed`: OCR, triage, package-shape validation, or supporting-document extraction failed.
- `ocr_complete`: invoice OCR completed and validation can be queued.
- `genai_queued`: validation has been queued.
- `genai_in_progress`: case facts, GenAI, product lookup, code rules, or aggregate advice are running.
- `genai_failed`: validation runtime failed.
- `genai_complete`: AI/code processing completed; contractor can submit or admin can review depending on workflow.
- `admin_review_inbox`: contractor submitted the claim for admin review.
- `contractor_revision_inbox`: admin requested contractor revision.
- `in_review`: admin review is actively underway.
- `approved_pending`: approved but not yet paid.
- `approved_paid`: approved and paid.
- `ineligible`: review outcome determined the claim is not eligible.

`claims.ingest_runs.status` values:

- `queued`: package run exists but has not started.
- `running`: package work is underway.
- `succeeded`: package processing and downstream validation completed.
- `failed`: package processing failed.
- `partial`: some files or steps succeeded and some failed.

`claims.ingest_documents.document_kind` values:

- `invoice`: staged PDF is the resolved invoice candidate.
- `supplement`: staged PDF is a supporting document.
- `unknown`: staged PDF could not be safely classified.

`claims.ingest_documents.classification_status` and `claims.supporting_documents.classification_status` values:

- `pending`: classification has not completed.
- `classified`: classification succeeded.
- `needs_review`: classification produced an uncertain or review-needed result.
- `failed`: classification failed.
- `superseded`: ingest-document-only value for staged rows replaced by newer processing.

`claims.ingest_documents.supplement_routing_quality` values:

- `usable`: supporting document can be used in automated review.
- `needs_review`: document may be usable but needs admin attention.
- `requires_visual_review`: document likely requires human visual inspection.
- `unusable`: document should not satisfy automated supporting-document requirements.

`claims.ingest_step_runs.step_type` values:

- `upload`, `upload_package_stage`, `reprocess_package_stage`
- `ocr_read`, `triage_classifier`, `supporting_document_extraction`, `ocr_invoice`
- `case_facts`, `product_lookup_enrichment`, `genai_common`, `genai_upgrade`, `code_common`, `code_upgrade`, `aggregate_advice`
- `ocr`, `classifier`, `genai`

`claims.ingest_step_runs.status` values:

- `queued`
- `in_progress`
- `succeeded`
- `failed`

Validation result enums:

- `source_engine`: invoice located fields and rulechecks use `code` or `genai`.
- `source_engine`: supporting-document located fields use `genai`, `vision`, `code`, or `manual`.
- `rule_result`: `pass`, `info`, `warn`, or `fail`.
- `invoice_version_upgrade_types.source_engine`: `classifier` or `genai`.
- `invoice_version_upgrade_types.call_status`: `classified`, `queued`, `in_progress`, `succeeded`, `failed`, or `skipped`.

Review-message enum:

- `admin_revision_request`: admin-authored revision request.
- `contractor_note`: contractor-authored note or response.

### 15.3 Rule key naming conventions

Rule keys should be stable, lowercase, and underscore-separated.

Preferred pattern:

```text
<scope_or_upgrade_abbrev>_<condition_or_evidence>_<outcome_or_check>
```

Examples:

- `eligibility_code_found_in_database`
- `eligibility_code_valid_for_invoice_date`
- `income_level_1_or_2_required`
- `hp_ahri_found_in_product_list`
- `hp_product_minimum_capacity_at_minus_5c`
- `hp_product_efficiency_threshold`
- `hpwh_neea_found_in_product_list`
- `hpwh_neea_tier_2_or_higher`
- `ashp_oil_ohpa_bc_product_found_in_list`
- `ashp_fossil_fuel_removal_supporting_document_attached`
- `esu_utility_upgrade_supporting_document_attached`

Common prefixes:

- `hp`: heat-pump rules or fields shared by multiple air-source heat-pump paths.
- `ashp`: air-source heat-pump upgrade-specific rules.
- `hpwh`: heat pump water heater rules.
- `esu`: electrical service upgrade rules.
- `awhp`: air-to-water or combined heat-pump product-list checks.

The key should describe the business fact being checked, not the implementation class name. Code can move; rule keys are part of the audit trail.

### 15.4 Supporting-document type key glossary

Current supporting-document type keys:

- `before_after_photo_set`: before/after photo evidence.
- `certification_sheet`: certification or compliance sheet.
- `dual_fuel_control_document`: dual-fuel control evidence.
- `fenestration_energy_performance_label`: window/door energy performance label.
- `energy_star_label`: ENERGY STAR label.
- `f280_heat_load_calculation`: F280 heat-load calculation.
- `floor_plan_document`: floor plan evidence.
- `fossil_fuel_removal_proof`: fossil-fuel system removal proof.
- `fossil_backup_system_document`: fossil backup system document.
- `income_verification_document`: income verification document.
- `landlord_consent_form`: landlord consent form.
- `manufacturer_label_photo`: photo of manufacturer label/nameplate.
- `oil_removal_proof`: oil system removal proof.
- `permit_document`: permit, inspection, or authority-having-jurisdiction evidence.
- `preapproval_notice`: preapproval notice.
- `preapproval_quote`: preapproval quote.
- `product_spec_sheet`: manufacturer or product specification sheet.
- `utility_bill`: utility bill.
- `electrical_utility_upgrade_document`: electrical utility/service upgrade evidence.
- `utility_account_document`: utility account document.
- `wett_report`: WETT report.

These keys are registry-world definitions. A specific uploaded PDF becomes evidence only after it is classified and promoted into `claims.supporting_documents`.

### 15.5 Upgrade type key glossary

Current claims AI upgrade type keys:

- `common`: claim-level validation scope used for shared checks.
- `windows_doors`: windows and doors.
- `air_source_heat_pump_electric`: air-source heat pump conversion from electric.
- `air_source_heat_pump_wood`: air-source heat pump conversion from wood.
- `air_source_heat_pump_gas_propane`: air-source heat pump conversion from natural gas or propane.
- `air_source_heat_pump_oil`: air-source heat pump conversion from oil.
- `dual_fuel_ducted_heat_pump`: dual-fuel ducted heat pump.
- `air_to_water_heat_pump`: air-to-water heat pump.
- `combined_space_water_heat_pump`: combined space and water heat pump.
- `heat_pump_water_heater`: heat pump water heater.
- `electrical_service_upgrade`: electrical service upgrade.
- `insulation`: insulation.
- `ventilation`: ventilation.
- `health_and_safety_remediation`: health and safety remediation.

`common` is not a physical installed upgrade. It is a validation scope used so common located fields and rulechecks can share the same output tables as upgrade-specific checks.

### 15.6 Rebuild and seed script order

The active claims-only rebuild path is:

1. `claims_ai_service_ddl/2_create_schema.sql`
2. `claims_ai_service_ddl/3_insert_ahri_sources.sql`
3. `claims_ai_service_ddl/3_insert_neea_sources.sql`
4. `claims_ai_service_ddl/3_insert_awhp_sources.sql`
5. `claims_ai_service_ddl/3_insert_ohpa_sources.sql`
6. `claims_ai_service_ddl/3_insert_invoice_upgrade_types.sql`
7. `claims_ai_service_ddl/3_insert_supporting_document_types.sql`
8. `claims_ai_service_ddl/3_insert_supporting_document_type_upgrade_types.sql`
9. `claims_ai_service_ddl/3_insert_supporting_document_type_located_fields.sql`
10. `claims_ai_service_ddl/3_insert_code_rules.sql`
11. `claims_ai_service_ddl/3_insert_code_located_fields.sql`
12. `claims_ai_service_ddl/3_insert_validationgenai_config.sql`
13. `claims_ai_service_ddl/3_insert_genai_normalized.sql`
14. `claims_ai_service_ddl/4_create_views.sql`

Optional local test data:

- `claims_ai_service_ddl/testdata_20260616/9_insert_testdata.sql`
- `claims_ai_service_ddl/testdata_20260616/9_insert_test014_multi_upgrade_testdata.sql`

Archived existing-database patch scripts are not part of the active rebuild path. A clean rebuild from `2_create_schema.sql` already includes those changes.

Do not run `public_legacy_seed`, `archived_sql`, or other non-rebuild folders as part of the normal claims-schema rebuild unless the goal is explicitly to change legacy or local repair data.

### 15.7 Legacy DB

The legacy application model lives primarily in `public.*` tables. It is useful context because the claims AI model deliberately does not try to continue the old invoice-entry pattern.

![Legacy DB](<er legacy.jpg>)

In the legacy model, `public.permit_applications` is the flexible application/form record. Different business records are distinguished by classification/type rows rather than by purpose-built invoice-processing tables.

The important legacy tables in this diagram are:

- `public.users`: people who log in or participate in the system.
- `public.user_addresses`: address history for users; the current address is typically inferred from the most recent `created_at`.
- `public.contractors`: contractor companies.
- `public.contractor_employees`: join table connecting users to contractor companies.
- `public.contractor_onboards`: onboarding link between a contractor company and an onboarding permit application.
- `public.permit_applications`: the legacy form/submission record.
- `public.permit_classifications`: classification/type records used to describe submission type, audience, user group, variant, and related form categories.

The submitter relationship is the key idea. A legacy `permit_applications.submitter_id` can mean different business things depending on the submission type and submitter type:

- For onboarding, the submitter is associated with a contractor employee or contractor onboarding flow.
- For an application, the submitter represents the homeowner/participant applying for eligibility.
- For an invoice, the submitter often represents the contractor company submitting invoice information.

Contractor identity also has two layers:

- `contractors.contact_id` points to the primary contractor contact user.
- `contractor_employees.employee_id` links additional user accounts to the contractor company.

This means a user can work for multiple contractor companies, and a contractor can have many staff. For the invoice workflow, this made it important to distinguish the company (`public.contractors`) from the person submitting or acting on the record (`public.users`).

The old invoice workflow was form-centric. Contractors re-entered invoice PDF values into a webform. Admin staff then compared the webform values against the paper/PDF invoice. The database stored submitted form data and workflow state, but it did not preserve a rich OCR/AI evidence chain.

The claims AI model changes that pattern:

- The uploaded PDF package is first staged in `claims.ingest_documents`.
- The resolved invoice PDF becomes `claims.invoice_versions`.
- OCR outputs, line items, located fields, rulechecks, product matches, supporting-document facts, GenAI context windows, and raw model responses are stored as structured evidence.
- `claims.invoices.contractor_id` still references the legacy contractor company.
- `claims.invoices.submitter_id` still references the legacy user when a contractor/user submits the claim.
- `claims.users_eligibilitycodes.user_id` still references the legacy participant user.

So the new model does not replace all legacy identity tables. It reuses legacy users and contractors for identity and ownership, while moving invoice review evidence into purpose-built `claims.*` tables.

The practical difference is:

```text
Legacy invoice review:
contractor retypes PDF values into public.permit_applications form data
admin manually compares form values to the PDF

Claims AI review:
contractor uploads PDFs
OCR and GenAI/code create invoice-version evidence rows
admin reviews structured evidence, source snippets, rulechecks, and advice
```

`public.permit_classifications` remains useful for understanding how the old application platform categorized forms, but claims AI upgrade classification now comes from `claims.invoice_upgrade_types` and `claims.invoice_version_upgrade_types`.

### 15.8 Known documentation gaps

This document is now broad enough to explain the claims AI model, but a few areas may still deserve follow-up detail:

- The React screen-by-screen data dependencies could be documented separately from the database model.
- The exact admin status-transition rules could be expanded beyond the status glossary.
- Product-list importer internals could be documented in a runbook if import operations become frequent.
- More realistic sample rows could be added after stable anonymized test data exists.
- The alphabetical catalog is intentionally concise; it does not list every column or every index.
- This document only summarizes legacy `public.*` tables at the level needed to explain claims AI identity, ownership, and why the invoice model changed.
