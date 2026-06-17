# Remove local product-reference fallback plan

## Problem

`Claims::ExternalReferences::ImportBcHydroHeatPumpProducts` currently has a local fallback PDF:

`claims_ai_service_ddl/reference_data/Ductless mini-split heat pump List.pdf`

That is not acceptable runtime behavior. If the admin asks the app to download/import a current external reference list, the app should use the configured remote source URL. If the remote site is unreachable, returns a non-PDF response, times out, or otherwise fails, the system admin should see an explicit failed import with the reason.

The codebase should not silently import stale repo data as a fallback.

## Desired Behavior

- Product-list imports use the configured `claims.ahri_sources.source_url`.
- No runtime code falls back to a committed local file.
- If the remote download fails, the admin import request returns a clear error.
- A failed `claims.ahri_import_runs` row is persisted with `status = 'failed'` and useful `error_text`.
- The admin product-list screen can show the failed run in import status.
- Local/reference files that are no longer used by runtime code are moved to archive.

## Implementation Steps

1. Update `app/services/claims/external_references/import_bc_hydro_heat_pump_products.rb`.

   - Remove `LOCAL_DEFAULT_PDF_PATHS`.
   - Remove the default-path branch in `ensure_pdf_file!`.
   - If `pdf_path` is not explicitly provided, always download from `source_url`.

2. Persist failures that happen during download.

   - Currently `ensure_pdf_file!` runs before `Claims::AhriImportRun.create!`, so a download failure can happen before there is a failed import row.
   - Move import-run creation before the download step.
   - Store source metadata on the run, including `source_url`, parser name, and whether the input was remote or explicit file path.
   - On any failure, update the run to `status = 'failed'`, `completed_at`, and `error_text`.

3. Make remote-download errors admin-readable.

   - Preserve specific errors such as:
     - source URL missing or invalid
     - DNS/connect/timeout failure
     - non-2xx HTTP response
     - response is not a PDF
     - PDF parsed zero product rows
     - Node upload failed
   - Return those messages through `AhriProductsAdminController#import_downloaded_pdf` as `422` JSON.

4. Keep explicit `pdf_path` only if still needed for tests/dev tooling.

   - Do not use an implicit repo fallback.
   - If `pdf_path` remains, it should be caller-supplied and visible in metadata.
   - The admin endpoint should not pass `pdf_path`.

5. Clean up reference-data files after runtime code no longer depends on them.
   - Move `claims_ai_service_ddl/reference_data/Ductless mini-split heat pump List.pdf` into archive.
   - Move `claims_ai_service_ddl/reference_data/Copy of window_contractors.xlsx` into archive.
   - Move `claims_ai_service_ddl/reference_data/silver_templates/` into archive unless the optional Silver importer is still intentionally retained.
   - Update or archive `claims_ai_service_ddl/dev_tools/import_silver_invoice_templates.rb` if it is the only remaining reason for `silver_templates/`.
   - Update `claims_ai_service_ddl/README_REBUILD_ORDER.txt` so `reference_data/` is no longer described as active DDL-adjacent material.

## Test Plan

1. Successful remote import smoke test.

   - Run the AHRI import from the admin endpoint against the real configured BC Hydro source URL.
   - Confirm a succeeded `claims.ahri_import_runs` row is created.
   - Confirm products are inserted and the uploaded source PDF metadata is stored.

2. Remote failure test.

   - Temporarily point an AHRI source at an unreachable or invalid URL in local only.
   - Run the admin import endpoint.
   - Confirm response is `422`.
   - Confirm a failed `claims.ahri_import_runs` row exists with useful `error_text`.
   - Confirm the admin import status endpoint returns that failed run.

3. Non-PDF response test.

   - Temporarily point an AHRI source at a URL that returns HTML/text.
   - Confirm the import fails with a clear non-PDF message and persists the failed run.

4. Zero parsed rows test.

   - If keeping explicit `pdf_path` for dev/test, invoke the service with a small dummy PDF that parses zero rows.
   - Confirm failed run and clear message.

5. Regression checks.
   - Ruby syntax check for the importer and controller.
   - Frontend check only if admin screen behavior is changed.
   - Search repo for `reference_data/Ductless mini-split heat pump List.pdf` and `LOCAL_DEFAULT_PDF_PATHS`; both should be gone from runtime code.

## Non-Goals

- Do not add a new local fallback file.
- Do not silently reuse stale imported rows when a new import fails.
- Do not hide remote-source failures in logs only; the admin import status must show the failed run.
