# Supporting Document Located Fields Runtime Plan

## Goal

Add a supporting-document extraction slice that keeps final ESP pass/warn/fail decisions in the common/upgrade GenAI rulechecks, while a dedicated support-document extraction call extracts reusable facts from each uploaded supporting document.

## Runtime Shape

1. Every uploaded file still receives DI read OCR first.
2. The triage/classifier call decides `document_kind`, `supplement_type_key`, routing quality, invoice upgrade detection, and visible eligibility code only.
3. The bundle then runs a `supporting_document_extraction` step for typed supporting documents with configured located fields.
4. The app persists extracted rows to `claims.supporting_document_located_fields` once the staged document is promoted into `claims.supporting_documents`.
5. Case facts for common/upgrade GenAI include the supporting-document summary plus extracted supporting-document located fields.
6. Common/upgrade GenAI rules use those facts for final rulechecks.

## Tables

- `claims.supporting_document_type_located_fields`
  - Config rows: for each `supporting_document_type`, which fields should be located and in what order.
- `claims.supporting_document_located_fields`
  - Runtime rows: values extracted from one uploaded `claims.supporting_documents` row.
- `claims.validationgenai_config`
  - Stores `classifier_system_record` and `supporting_document_extraction_system_record`.

## Initial Field Seed Scope

Start with fields that the 2026 ESP tracker identifies as true supplement-extracted-field candidates or high-value quality checks:

- `utility_bill_or_account_document`
- `income_verification_document`
- `landlord_consent_form`
- `wett_report`
- `fossil_fuel_removal_proof`
- `oil_removal_proof`
- `fossil_removal_proof`
- `utility_invoice`
- `utility_upgrade_document`
- `energy_performance_label`
- `certification_sheet`
- `manufacturer_label_photo`
- `product_spec_sheet`
- `energy_star_label`
- `f280_heat_load_calculation`
- `commissioning_or_control_document`
- `permit_document`
- `before_after_photo_set`

## Test Strategy

- Unit/smoke test persistence with synthetic supporting-document extraction payloads for multiple support document types.
- Run local DB patch/seed and verify rows exist.
- Run Rails syntax checks for touched Ruby files.
- Run a local synthetic triage persistence test that creates a staged support document, applies classifier output, promotes it, and verifies located fields are copied into `claims.supporting_document_located_fields`.
- Use existing or generated mock PDFs as UI test assets for user retest; the hard extraction validation is done against DI-shaped JSON because the model consumes DI output, not the PDF bytes directly.

## Implementation Status

- Implemented a dedicated supporting-document extraction runtime persistence path.
- Removed the old split-mode config so the classifier is always routing-only.
- Added `supporting_document_extraction` ingest step orchestration for typed supporting documents with configured fields.
- Seeded 82 supporting-document located-field definitions locally.
- Smoke-tested staged triage and promotion for `utility_bill_or_account_document`, `landlord_consent_form`, `wett_report`, and `manufacturer_label_photo`.
- Verified the generated case facts include persisted supporting-document located fields.
- Created local smoke invoice `f40e1b8e-b746-4976-a456-2f6604c94210` for second-pass UI inspection.
- Ran real PDF batches from `claims_ai_service_documentation/pdf test files`:
  - `CENTRA_1.PDF` succeeded through OCR, classifier, common GenAI, upgrade GenAI, and code rules.
  - `Invoice 1 - Heat Pump and Electric Service Upgrade.pdf` succeeded through OCR, classifier, common GenAI, upgrade GenAI, and code rules.
  - `Invoice 9 - Heat Pump, Ventilation, Electrical Service Upgrade.pdf` succeeded through OCR, classifier, common GenAI, upgrade GenAI, and code rules.
  - A mixed bundle with `Invoice 1`, `Fake Supplement - Utility Bill.pdf`, and `Fake Supplement - Landlord Consent.pdf` classified and persisted supporting-document located fields from real PDF/DI output. The ingest run hit one transient invalid-JSON model response during upgrade GenAI, then a direct rerun with the stored classifier payload completed the invoice GenAI successfully.
  - Separate-extraction real PDF run `3f5ee3ca-8307-4498-8dcf-1333b562d262` completed with two `supporting_document_extraction` steps, invoice `2a0a5f02-969e-4588-9f27-13257f89e39d` reached `genai_complete`, and 9 supporting-document located fields were persisted.

## Follow-Up

- Add vision input for photo/label-heavy supporting documents. Until then, text-only DI extraction should set `supplement_routing_quality = requires_visual_review` when image semantics matter.
- Add real end-to-end PDF/DI/model regression fixtures once representative supporting-document samples are stable enough to keep in the repo.
