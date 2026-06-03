# Claims AI Service Data Model

Status: draft in progress

Purpose: provide a readable, stable reference for the claims AI database model. This document is intentionally being built in stages. The first pass defines the numbered table of contents, table inventory, and writing plan only.

## 1. Purpose And Audience

### 1.1 Document Purpose

This document explains the data model for the claims AI service. Its goal is to make the database understandable to people who need to maintain, test, review, or extend the claims AI pipeline.

The model is not just a list of tables. It represents a workflow: uploaded PDF packages are staged, read by Document Intelligence, triaged into invoice and supporting-document records, enriched with located fields, evaluated by GenAI and code rules, and summarized for claim review. The document should help a reader understand both the tables and the runtime story those tables support.

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

This document covers the `claims` schema created by `claims_ai_service_ddl/2_create_schema.sql` and the closely related seed files that define upgrade types, supporting document types, rules, located fields, and rulesets.

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

Rule keys, upgrade type keys, supporting document type keys, and located field keys are also written in code formatting, such as `air_source_heat_pump_electric`, `utility_bill_or_account_document`, `hp_ahri_reference`, or `ashp_electric_existing_heat_context_present`.

The word invoice can mean different things depending on context. In this document:

- `claims.invoices` means the claim-level invoice record, which owns the overall invoice review state.
- `claims.invoice_versions` means a processed invoice PDF/version, including OCR, DI invoice output, located fields, and validation results.
- `claims.ingest_documents` means raw staged PDFs before the pipeline has definitively promoted them into invoice or supporting-document records.
- `claims.supporting_documents` means processed supporting documents that have been classified, promoted, and attached to the claim invoice.

The word common refers to claim-level checks that are not specific to one upgrade type. The current schema represents common checks through an `invoice_upgrade_types` row with key `common`. Conceptually, this behaves more like claim-level validation scope than a physical upgrade installed in a home.

Examples in later sections should use realistic but safe sample values. They should illustrate relationships and lifecycle states, not expose real homeowner data.

## 2. Big Picture Model

2.1 One-page conceptual model

2.2 Main claim-processing lifecycle

2.3 Runtime data vs configuration data

2.4 Definition tables vs result tables

2.5 Invoice versions, reruns, and reprocessing

2.6 Supporting documents and extracted facts

2.7 GenAI validation vs deterministic code validation

2.8 External product-list matching

## 3. Core Claim Lifecycle

3.1 `claims.sessions`

3.2 `claims.invoices`

3.3 `claims.invoice_versions`

3.4 `claims.lineitems`

3.5 `claims.invoice_upgrade_types`

3.6 `claims.invoice_version_upgrade_types`

3.7 Example: first invoice submission

3.8 Example: invoice version rerun or replacement

3.9 Example: invoice with multiple detected upgrade types

## 4. Package Ingest And Processing

4.1 `claims.ingest_runs`

4.2 `claims.ingest_documents`

4.3 `claims.ingest_step_runs`

4.4 Upload package staging

4.5 OCR read phase

4.6 Triage classifier phase

4.7 Supporting-document extraction phase

4.8 Final invoice OCR phase

4.9 Example: normal package upload

4.10 Example: redo invoice package

## 5. Supporting Documents

5.1 `claims.supporting_document_types`

5.2 `claims.supporting_document_type_upgrade_types`

5.3 `claims.supporting_document_type_located_fields`

5.4 `claims.supporting_documents`

5.5 `claims.supporting_document_located_fields`

5.6 Supporting-document routing quality

5.7 Required vs optional supporting documents

5.8 Example: utility account document

5.9 Example: manufacturer label photo

5.10 Example: proof of fossil fuel removal

## 6. Located Fields And Evidence

6.1 Invoice located fields

6.2 Supporting-document located fields

6.3 Code located fields

6.4 GenAI located fields

6.5 `claims.invoice_version_located_fields`

6.6 `claims.code_located_fields`

6.7 `claims.genai_located_fields`

6.8 `claims.genai_located_field_upgrade_types`

6.9 Example: invoice AHRI reference

6.10 Example: supporting-document AHRI reference

6.11 Example: database-derived eligibility facts

## 7. Validation Rules And Outputs

7.1 Validation architecture

7.2 `claims.code_rules`

7.3 `claims.code_rule_upgrade_types`

7.4 `claims.genai_rules`

7.5 `claims.genai_rule_upgrade_types`

7.6 `claims.invoice_version_rulechecks`

7.7 Common claim-level checks

7.8 Upgrade-specific checks

7.9 Attachment checks

7.10 External-list code checks

7.11 Example: missing mandatory supporting document

7.12 Example: GenAI warning vs failure

## 8. Prompt And Ruleset Configuration

8.1 `claims.validationgenai_config`

8.2 `claims.validationgenai_rulesets`

8.3 System record

8.4 Shared user records

8.5 Upgrade-type ruleset records

8.6 How ruleset prompts are compiled

8.7 Example: common ruleset call

8.8 Example: upgrade-type ruleset call

## 9. External Product Reference Lists

9.1 Product-list architecture

9.2 AHRI tables

9.3 NEEA tables

9.4 AWHP tables

9.5 OHPA tables

9.6 `claims.ahri_sources`

9.7 `claims.ahri_import_runs`

9.8 `claims.ahri_products`

9.9 `claims.neea_sources`

9.10 `claims.neea_import_runs`

9.11 `claims.neea_products`

9.12 `claims.awhp_sources`

9.13 `claims.awhp_import_runs`

9.14 `claims.awhp_products`

9.15 `claims.ohpa_sources`

9.16 `claims.ohpa_import_runs`

9.17 `claims.ohpa_products`

9.18 Example: AHRI match

9.19 Example: NEEA heat pump water heater match

9.20 Example: AWHP hydronic product match

9.21 Example: OHPA oil-to-heat-pump match

## 10. Eligibility And Applicant Facts

10.1 `claims.users_eligibilitycodes`

10.2 Eligibility code lookup

10.3 Income level

10.4 Approval and expiry dates

10.5 Participant identity facts

10.6 Example: eligibility code found on invoice

10.7 Example: eligibility code missing or expired

## 11. Admin, Revision, And History Tables

11.1 `claims.admin_revision_requests`

11.2 Rule history tables

11.3 Located-field history tables

11.4 `claims.code_rule_history`

11.5 `claims.code_rule_upgrade_type_history`

11.6 `claims.code_located_field_history`

11.7 `claims.genai_rule_history`

11.8 `claims.genai_rule_upgrade_type_history`

11.9 `claims.genai_located_field_history`

11.10 `claims.genai_located_field_upgrade_type_history`

11.11 Example: prompt/rule audit history

## 12. Alphabetical Table Catalog

Each table entry should eventually include:

- Purpose
- Table category
- Parent tables
- Child tables
- Key columns
- Important statuses or enums
- Lifecycle notes
- Example rows where helpful

  12.1 `claims.admin_revision_requests`

  12.2 `claims.ahri_import_runs`

  12.3 `claims.ahri_products`

  12.4 `claims.ahri_sources`

  12.5 `claims.awhp_import_runs`

  12.6 `claims.awhp_products`

  12.7 `claims.awhp_sources`

  12.8 `claims.code_located_field_history`

  12.9 `claims.code_located_fields`

  12.10 `claims.code_rule_history`

  12.11 `claims.code_rule_upgrade_type_history`

  12.12 `claims.code_rule_upgrade_types`

  12.13 `claims.code_rules`

  12.14 `claims.genai_located_field_history`

  12.15 `claims.genai_located_field_upgrade_type_history`

  12.16 `claims.genai_located_field_upgrade_types`

  12.17 `claims.genai_located_fields`

  12.18 `claims.genai_rule_history`

  12.19 `claims.genai_rule_upgrade_type_history`

  12.20 `claims.genai_rule_upgrade_types`

  12.21 `claims.genai_rules`

  12.22 `claims.ingest_documents`

  12.23 `claims.ingest_runs`

  12.24 `claims.ingest_step_runs`

  12.25 `claims.invoice_upgrade_types`

  12.26 `claims.invoice_version_located_fields`

  12.27 `claims.invoice_version_rulechecks`

  12.28 `claims.invoice_version_upgrade_types`

  12.29 `claims.invoice_versions`

  12.30 `claims.invoices`

  12.31 `claims.lineitems`

  12.32 `claims.neea_import_runs`

  12.33 `claims.neea_products`

  12.34 `claims.neea_sources`

  12.35 `claims.ohpa_import_runs`

  12.36 `claims.ohpa_products`

  12.37 `claims.ohpa_sources`

  12.38 `claims.sessions`

  12.39 `claims.supporting_document_located_fields`

  12.40 `claims.supporting_document_type_located_fields`

  12.41 `claims.supporting_document_type_upgrade_types`

  12.42 `claims.supporting_document_types`

  12.43 `claims.supporting_documents`

  12.44 `claims.users_eligibilitycodes`

  12.45 `claims.validationgenai_config`

  12.46 `claims.validationgenai_rulesets`

## 13. Scenario Examples

13.1 Scenario: one invoice, one upgrade type, no supporting docs

13.2 Scenario: one invoice, one upgrade type, required supporting doc attached

13.3 Scenario: one invoice, multiple upgrade types

13.4 Scenario: redo package with previous processed outputs cleared

13.5 Scenario: supporting document added before redo package

13.6 Scenario: missing mandatory supporting document

13.7 Scenario: external product-list match

13.8 Scenario: product-list mismatch between invoice and supporting document

13.9 Scenario: GenAI warning that requires admin review

13.10 Scenario: code rule failure

## 14. Appendices

14.1 Full table list

14.2 Status and enum glossary

14.3 Rule key naming conventions

14.4 Supporting-document type key glossary

14.5 Upgrade type key glossary

14.6 Rebuild and seed script order

14.7 Known documentation gaps

## 15. Writing Plan

15.1 First pass: write sections 1 through 2 to establish purpose, vocabulary, and the big-picture lifecycle.

15.2 Second pass: write sections 3 through 5 for the core runtime model: invoices, ingest, and supporting documents.

15.3 Third pass: write sections 6 through 8 for located fields, validation rules, and prompt/ruleset configuration.

15.4 Fourth pass: write sections 9 through 11 for product lists, eligibility facts, admin requests, and history tables.

15.5 Fifth pass: write section 12 in chunks, grouped by table family rather than strictly one table at a time.

15.6 Sixth pass: write section 13 scenario examples using concrete sample rows.

15.7 Final pass: edit for consistency, remove repetition, and ensure the alphabetical catalog aligns with the conceptual sections.
