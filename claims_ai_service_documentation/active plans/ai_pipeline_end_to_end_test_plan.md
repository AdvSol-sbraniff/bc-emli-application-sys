# AI Pipeline End-to-End Test Plan

## Purpose

Verify that the local claims AI pipeline matches the current spreadsheet contract for all supported entry paths:

- Contractor new package upload.
- Contractor/admin fix package upload with cloned current-version evidence.
- Rule-change-only advice refresh using existing file evidence.

The test intentionally checks database state, step names, invoice status, and supporting-document parentage. This is not a UI smoke test.

## Test Data

- Use existing local seeded contractor `506f4e39-a648-4f2f-b5b3-a0efee9c9695` (`Mini Windows and Heatpumps`).
- Use `claims_ai_service_documentation/Test Data/Heat Pump/test006` for the primary new-upload success path because it is not test014 and includes one invoice plus one supporting document.
- Use `claims_ai_service_documentation/Test Data/Heat Pump/test014/Heat Pump invoice - version 2.pdf` as the replacement invoice for the fix path.
- Use existing invoice PDFs from Heat Pump test folders for package-validation negative tests.

## Assertions

For every run:

- No legacy step names are emitted: `plus1fix_ocr_read`, `plus1fix_classifier`, `classifier_pdfs`, `classifier_imagefiles`, `triage_classifier`, `supporting_document_type_extraction`, `reanalysis_clone_existing_evidence`.
- `claims.supporting_documents` is parented through `invoice_version_id`.
- Terminal runs have coherent `ingest_runs.status`, `completed_files`, `failed_files`, and invoice business status.

## Test Cases

1. New package success

- Entry: `Claims::Ingest::CreateDraftBatch.call`.
- Files: `test006/Heat Pump invoice.pdf`, `test006/Heat Pump WETT report.pdf`.
- Expected steps: `upload_package_stage`, `ocr_read`, `classifier_files`, `supporting_document_extraction`, `ocr_invoice`, `case_facts`, `product_lookup_enrichment`, `genai_common`, `genai_upgrade`, `code_common`, `code_upgrade`, `aggregate_advice`.
- Expected result: run succeeds, invoice reaches `genai_complete`, at least one supporting document exists under the current invoice version.

2. Fix package success

- Entry: `Claims::Ingest::UploadFixPackage.call`.
- Source invoice: the invoice created by test case 1.
- Files: `test014/Heat Pump invoice - version 2.pdf` as the new invoice.
- Clone mode: `clone_all_current_supporting_documents: true`.
- Expected steps: `fix_upload_package_stage`, `fix_ocr_read`, `fix_classifier_files`, `fix_clone_existing_evidence`, `fix_supporting_document_extraction`, `fix_ocr_invoice`, then the shared advice steps.
- Expected result: run succeeds, a new invoice version is created, and supporting docs are cloned under the new `invoice_version_id`.

3. Rule-change-only success

- Entry: create a `ruleclone_clone_existing_evidence` run and enqueue `Claims::RunGenaiJob` in `use_existing_classifier` mode.
- Source invoice version: latest successful version from test case 2.
- Expected steps: `ruleclone_clone_existing_evidence`, then shared advice steps only.
- Expected result: run succeeds, no OCR/classifier/supporting-document extraction steps are created for this run.

4. No-invoice package rejection

- Entry: `Claims::Ingest::CreateDraftBatch.call`.
- Files: only `test006/Heat Pump WETT report.pdf`.
- Expected result: run fails with invoice status `package_needs_correction` and subtype `package_no_invoice_pdf`.

5. Multiple-invoice package rejection

- Entry: `Claims::Ingest::CreateDraftBatch.call`.
- Files: two invoice PDFs from separate heat-pump tests.
- Expected result: run fails with invoice status `package_needs_correction` and subtype `package_multiple_invoice_pdfs`.

## Implementation Notes

- Run in local only.
- Keep failed artifacts during the test harness so failed package rows can be inspected.
- Do not create stored alter scripts.
- If a provider outage or transient GenAI failure occurs, capture the failure details separately from pipeline logic failures.

## Local Execution Results - 2026-06-19

All planned local tests completed.

### Test Case Results

| Test case                          | Run ID                                 | Result | Notes                                                                                                                                                                       |
| ---------------------------------- | -------------------------------------- | ------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| New package success                | `4453890c-fc8b-448d-91df-0e158ed75c6c` | Passed | Run `succeeded`; invoice `93fa9b66-bd01-44d1-a57d-9e48810f299c` reached `genai_complete`; current version `1f5d317b-67c7-4daf-812f-5f88d6cadf9c` has 1 supporting document. |
| Fix package success                | `528796cd-7e78-4203-8780-6d95fa2a06fd` | Passed | Run `succeeded`; new version `4b027a0f-b28f-4f38-ba3e-a458d99fc895` is version 2 and has 1 cloned supporting document.                                                      |
| Rule-change-only success           | `65d76a2a-1f97-422d-b31a-99e44c4fcb7c` | Passed | Run `succeeded`; emitted `ruleclone_clone_existing_evidence` plus shared advice steps only.                                                                                 |
| No-invoice package rejection       | `be65f2dd-1aa2-42c4-827c-bf4358b28ed7` | Passed | Run `failed`; invoice status `package_needs_correction`; subtype `package_no_invoice_pdf`.                                                                                  |
| Multiple-invoice package rejection | `47bb4e94-fbb0-4fca-b4df-860429565e71` | Passed | Run `failed`; invoice status `package_needs_correction`; subtype `package_multiple_invoice_pdfs`.                                                                           |

### Final Invariants

- No tested run emitted legacy step names.
- `claims.supporting_documents` has `invoice_version_id` and no `invoice_id` parent column.
- Success paths used the current step names in the spreadsheet.
- Failure paths stopped before invoice OCR/advice, as expected for package-shape failures.

### Harness Note

The first long-running Rails runner poll saw a stale cached `ingest_runs` row even though the database run completed successfully in under two minutes. The runner was corrected to clear/disable query cache before polling subsequent runs.

## Local Execution Results - 2026-06-19 Post-Cleanup Rerun

Reran the full plan after replacing the broad `ReconcileRun` service with the narrower `FinalizeInvoiceVersionRun` finalizer and adding the `AdvanceRun` router.

| Test case                          | Run ID                                 | Result | Notes                                                                                                                                                                       |
| ---------------------------------- | -------------------------------------- | ------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| New package success                | `c6294ec1-9f66-4ed2-bdf4-a4e161cdc2ae` | Passed | Run `succeeded`; invoice `61e819bc-8ab5-4f19-96e4-624c11a27835` reached `genai_complete`; current version `1b5197e2-ba32-4208-afd6-0c8cf53f1d4e` has 1 supporting document. |
| Fix package success                | `2137bc19-0d66-419e-927b-6a8527a9f77e` | Passed | Run `succeeded`; new version `b67360c1-9d90-43df-a6ff-79e49ec39dcb` is version 2 and has 1 cloned supporting document.                                                      |
| Rule-change-only success           | `84225e0e-66dc-490b-b64d-2a5fff6d2ca6` | Passed | Run `succeeded`; emitted `ruleclone_clone_existing_evidence` plus shared advice steps only.                                                                                 |
| No-invoice package rejection       | `5d9bd317-4849-47d1-8c22-49ad001a112b` | Passed | Run `failed`; invoice status `package_needs_correction`; subtype `package_no_invoice_pdf`.                                                                                  |
| Multiple-invoice package rejection | `e7062aaa-ed88-4ae7-ac05-702d4e86a834` | Passed | Run `failed`; invoice status `package_needs_correction`; subtype `package_multiple_invoice_pdfs`.                                                                           |

Final invariant checks passed:

- Fresh rerun legacy step count: `0`.
- `claims.supporting_documents` parent column check: `invoice_version_id` only.
- All five runs reached expected terminal states.

## Local Execution Results - 2026-06-19 Dead-Code Cleanup Rerun

Reran targeted local pipeline tests after removing the obsolete one-file admin `UploadPdfs` endpoint/screen, deleting unused invoice-version supporting-document promotion code, and simplifying document triage application to the live `ingest_documents` path.

| Test case           | Run ID                                 | Result | Notes                                                                                                                                                                       |
| ------------------- | -------------------------------------- | ------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| New package success | `ad1ef1bf-9b28-4622-87a0-e0bd54b13b58` | Passed | Run `succeeded`; invoice `40c47227-977e-47cc-b78f-767be31ffddf` reached `genai_complete`; current version `93d18800-58cf-4a0f-a059-ce7ba4c353bc` has 1 supporting document. |
| Fix package success | `dd6b4b8e-a24d-495e-98f9-26a6711f6de3` | Passed | Run `succeeded`; new version `e2f12487-79e6-4a6e-b527-5a97fdd2ae65` is version 2 and has 1 cloned supporting document.                                                      |

Final invariant checks passed:

- Fresh rerun legacy step count: `0` for both runs.
- New package emitted `upload_package_stage`, `ocr_read`, `classifier_files`, `supporting_document_extraction`, `ocr_invoice`, and the shared advice steps.
- Fix package emitted `fix_upload_package_stage`, `fix_ocr_read`, `fix_classifier_files`, `fix_clone_existing_evidence`, `fix_supporting_document_extraction`, `fix_ocr_invoice`, and the shared advice steps.
- Vite build passed in the app container with `docker compose exec -T app npm run build`.

## Local Execution Results - 2026-06-19 Shared Upload Plumbing Rerun

Reran local pipeline tests after extracting shared file metadata/upload plumbing into `Claims::Ingest::EvidenceFile` and `Claims::Ingest::UploadEvidenceFileToNode`, and after renaming the supporting-document staging-to-version service to `CreateOrUpdateFromIngestDocument`.

| Test case                          | Run ID                                 | Result | Notes                                                                                                                                                                       |
| ---------------------------------- | -------------------------------------- | ------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| New package success                | `0e172b7a-7100-40ac-bd68-3b297776c076` | Passed | Run `succeeded`; invoice `7ba10826-592d-468c-807d-b8d55aec523b` reached `genai_complete`; current version `b15185c6-2fbd-4324-8c48-bf5bbed339f9` has 1 supporting document. |
| Fix package success                | `803ac294-c5eb-4860-9ad3-6c8705b7cb72` | Passed | Run `succeeded`; new version `99b9dca4-cf48-4df3-b502-15fec08d460f` is version 2 and has 1 cloned supporting document.                                                      |
| Rule-change-only success           | `7ffeacb9-7ee6-4571-bedf-5371ce4e2a01` | Passed | Run `succeeded`; reused existing version `99b9dca4-cf48-4df3-b502-15fec08d460f`; emitted `ruleclone_clone_existing_evidence` plus shared advice steps only.                 |
| No-invoice package rejection       | `2c7cef2d-751e-451b-b1eb-5d870e61c77c` | Passed | Run `failed`; invoice status `package_needs_correction`; subtype `package_no_invoice_pdf`; stopped after `classifier_files`.                                                |
| Multiple-invoice package rejection | `f4271d3c-88f7-48f1-aa09-836fea803927` | Passed | Run `failed`; invoice status `package_needs_correction`; subtype `package_multiple_invoice_pdfs`; stopped after `classifier_files`.                                         |

Final invariant checks passed:

- Fresh rerun legacy step count: `0` for all four runs.
- `claims.supporting_documents` still uses `invoice_version_id` as the parent and has no `invoice_id` parent column.
- New package emitted `upload_package_stage`, `ocr_read`, `classifier_files`, `supporting_document_extraction`, `ocr_invoice`, and the shared advice steps.
- Fix package emitted `fix_upload_package_stage`, `fix_ocr_read`, `fix_classifier_files`, `fix_clone_existing_evidence`, `fix_supporting_document_extraction`, `fix_ocr_invoice`, and the shared advice steps.
- Rule-change-only emitted `ruleclone_clone_existing_evidence` and shared advice steps only; no file-prep steps were created.
- Package-shape failures did not reach `ocr_invoice`, `case_facts`, product enrichment, GenAI advice, code rules, or aggregate advice.
