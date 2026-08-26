# JPEG Responses Transport Investigation and Correction Plan

## Status

Active. Investigation is complete enough to reject the theory that the July 30 demo JPEGs are malformed. The temporary provider-file workaround was surgically rolled back in the working tree on July 30. The rollback is not committed, and the restored inline path is still known to fail against the currently configured Foundry project endpoint.

This plan records the state required to resume after a Codex restart.

## Executive conclusion

The July 30 JPEG failure was not caused by the newly generated JPEGs. The files are normal baseline JPEGs. An older repository JPEG that previously appeared to work also fails today when sent through the current Foundry project Responses endpoint using an inline Base64 `input_image`.

The material change was the GenAI endpoint/API path:

- Before June 8, 2026, the service used a direct Azure OpenAI endpoint with `chat_completions`.
- On June 8, the local configuration changed to the Foundry project endpoint and `responses`.
- On June 11, commit `3a769ef9` changed JPEG/PNG attachments to actual Responses `input_image` parts.
- The older Chat Completions branch ignored the `attachments` argument. A JPEG could pass through the application, Document Intelligence could read it, and the classifier could use textual/OCR context, but the JPEG pixels were not attached to the GenAI call.
- The current Foundry project endpoint returns HTTP 400 `invalid_payload` for the officially documented inline Base64 image shape.

Therefore, the July 30 files exposed an endpoint/transport incompatibility that was already present. They did not introduce a new JPEG encoding problem.

## Important accountability note

The July 30 change that uploads each JPEG/PNG temporarily to the provider Files API, passes its `file_id`, and deletes it afterward was implemented too quickly. A successful workaround was treated as if it established the correct root-cause fix. It did not.

The file-ID path uses API concepts that exist in the Microsoft schemas, but in this application it is a compatibility workaround. It adds a provider-side copy, lifecycle handling, an additional failure surface, and avoidable privacy/governance questions. It must not be accepted as the permanent design merely because the live experiment succeeded.

## Current repository state

The working tree currently contains the deliberate, uncommitted surgical rollback in:

- `claims_ai_service/src/services/inv.service.ts`
- `claims_ai_service/src/services/inv.service.spec.ts`

It also contains this new untracked plan file. `git diff --check` passes. The targeted test command could not be started because the local shell tool exited immediately with Windows status `-1073741205`; tests remain required after restart.

The temporary provider-file implementation is committed in:

- Commit: `ca12cc85` (`My changes`, July 30, 2026, 18:37 PDT)
- File: `claims_ai_service/src/services/inv.service.ts`
- Current relevant lines are approximately 848-854:
  - `files.create(...)`
  - `purpose: 'assistants'`
  - `type: 'input_image'`
  - `file_id: providerFile.id`
- Associated tests are in `claims_ai_service/src/services/inv.service.spec.ts`.

Do **not** revert commit `ca12cc85` wholesale. It also contains the valuable structured upload-error work, retained-run handling, contractor upload/fix improvements, and related tests. Any rollback must be surgical and limited to the JPEG/PNG provider-file staging behavior and its directly associated tests.

## Evidence collected

### 1. The generated JPEGs are ordinary valid JPEGs

Files:

- `claims_ai_service_documentation/Test Data/demo_20260730/02_Before_Wood_Heating_System.jpg`
- `claims_ai_service_documentation/Test Data/demo_20260730/03_After_Heat_Pump_Installation.jpg`

Both were identified as:

- JPEG/JFIF 1.01
- Baseline JPEG
- 8-bit precision
- Three color components
- 1536 x 1024
- Standard JFIF/Exif metadata
- Approximately 296-301 KB

These characteristics are unexceptional and supported.

### 2. Older repository JPEGs have comparable valid formats

Examples inspected:

- `claims_ai_service_documentation/Test Data/Heat Pump/test014/Insulation before photo.jpg`
  - Baseline JPEG, 810 x 1080, three components
- `claims_ai_service_documentation/Test Data/Heat Pump/test014/Insulation after photo.jpg`
  - Baseline JPEG, 810 x 1080, three components
- `claims_ai_service_documentation/Test Data/windows doors/test006/Fenestration energy tag (1).jpeg`
  - Progressive JPEG, 1200 x 1600, three components
- `claims_ai_service_documentation/Test Data/PI-tests/invoicefinebutbadjpegofchildren/Fenestration energy tag (2).jpeg`
  - Baseline JPEG, 1600 x 1200, three components

There is no meaningful encoding distinction that explains why only the newly generated images would fail.

### 3. An older JPEG also fails through the current inline transport

A live diagnostic sent this old image through the current configured model and endpoint:

- `claims_ai_service_documentation/Test Data/Heat Pump/test014/Insulation before photo.jpg`

Request shape:

- Responses API
- `input_image`
- `image_url: data:image/jpeg;base64,...`

Result:

- HTTP 400
- Provider code: `invalid_payload`
- Provider type: `invalid_request_error`
- The error echoed the Base64 data URI

This is decisive evidence that the new demo JPEG is not the cause.

### 4. The exact new JPEG bytes work when referenced by provider file ID

The retained July 30 JPEG was uploaded to the provider Files API and then referenced as:

- `type: input_image`
- `file_id: <temporary provider file ID>`

The same model successfully returned a response. This proves that:

- The model can process the image.
- The JPEG bytes are valid.
- The failure occurs in the inline image transport or the current project endpoint's handling of that transport, before normal inference.

The provider initially rejected `purpose: vision` as an invalid purpose on this endpoint. It accepted `purpose: assistants`. This inconsistency was another reason not to treat temporary file staging as the final design without a deliberate decision.

### 5. Retained database failures

The retained ingest records for both demo images consistently show:

- Step: `classifier_files`
- Status: `failed`
- Application error code: `genai_input_image_invalid`
- Provider status: `400`
- Provider code: `invalid_payload`

The same failures occurred over multiple upload attempts.

Historical run evidence is incomplete because failed ingest/run records were previously cleaned up. The database cannot reliably prove which JPEG uploads occurred before retention was fixed. Git history and the current live comparison provide the stronger evidence.

## Configuration and code timeline

### Before May/June 2026

The retained `.env` backups show:

- Direct Azure OpenAI endpoint: `*.openai.azure.com/openai/v1/`
- `GENAI_API_STYLE=chat_completions`
- Earlier deployments such as `gpt-5.2-chat` or `gpt-5-4-chat`

In the Chat Completions branch, `genai(contextwindowjson, attachments)` converted only `contextwindowjson` into chat messages. It did not process `attachments`. Consequently, historical JPEG success did not prove that GenAI vision received the JPEG bytes.

### June 8, 2026

The active `.env` changed to:

- Base URL: `https://sbx-ai-foundry-prototype.services.ai.azure.com/api/projects/proj-default/openai/v1/`
- Deployment: `gpt-5.4`
- `GENAI_API_STYLE=responses`

The same `.env` still contains commented direct Azure OpenAI examples, including:

- `https://aoai-esp-dev.openai.azure.com/openai/v1/`
- Deployment `gpt-5-4-chat`
- `GENAI_API_STYLE=chat_completions`

These commented values are not proof that the required current direct deployment exists or is network-accessible. Azure deployment, private endpoint, DNS, authentication, and model capability must be verified before changing configuration.

### June 11, 2026

Commit `3a769ef9` changed attachment construction:

- JPEG/PNG became `input_image` with an inline Base64 data URL.
- Other documents remained `input_file` with inline Base64 file data.

Before that commit, the Responses branch labelled every attachment as a supporting-document PDF and sent every attachment as `input_file`, even when the MIME type was JPEG.

### July 30, 2026

The new demo upload was the first preserved, clearly diagnosed reproduction:

- The project endpoint rejected inline JPEGs with HTTP 400 `invalid_payload`.
- Error propagation and retained run records now made the actual provider failure visible.
- The provider-file workaround in commit `ca12cc85` bypassed the rejected inline data-URI path.

## Official Microsoft documentation findings

Use these sources again after restart; they were current on July 30, 2026:

1. Azure OpenAI Responses image inputs:

   - https://learn.microsoft.com/en-gb/azure/foundry/openai/how-to/responses
   - Microsoft explicitly documents JPEG inline as:
     - `type: input_image`
     - `image_url: data:image/jpeg;base64,...`

2. Azure OpenAI Responses guide:

   - https://learn.microsoft.com/en-us/azure/foundry/openai/how-to/responses
   - Also shows Base64 image input through a direct Azure OpenAI endpoint.

3. Foundry project Responses REST surface:

   - https://learn.microsoft.com/en-us/rest/api/microsoft-foundry/aiproject
   - The project endpoint accepts Responses inputs containing text, images, and files.

4. Foundry/OpenAI Responses schemas:

   - https://learn.microsoft.com/en-us/rest/api/aifoundry/azureopenai/conversations
   - `input_image` exposes both `image_url` and `file_id`.

5. Azure OpenAI Files REST API:

   - https://learn.microsoft.com/en-us/rest/api/aifoundry/azureopenai/files
   - The current file-purpose enum includes `assistants`, `batch`, `fine-tune`, and `evals`.

6. Microsoft guidance on endpoint selection:
   - https://learn.microsoft.com/en-us/azure/foundry/agents/quickstarts/responses-api
   - Microsoft says the Foundry project endpoint supplies Foundry platform features.
   - Microsoft says the direct Azure OpenAI endpoint provides best latency and maximum compatibility with OpenAI clients when only OpenAI models and standard tools are needed.

The application currently uses a Foundry project endpoint but does not appear to use Foundry agents, memory, file search, web search, MCP, or other project-specific tools. That makes the direct Azure OpenAI endpoint the leading design candidate, subject to Azure verification.

## Root-cause statement

High-confidence conclusion:

> The JPEGs did not suddenly become invalid. The application moved from a Chat Completions path that did not send image attachments to a Foundry project Responses path that sends actual inline `input_image` data. The current project endpoint rejects the documented Base64 data-URI form with HTTP 400, including for an older known JPEG. Temporary file-ID staging bypasses that endpoint behavior but does not establish that staging is the preferred permanent architecture.

Remaining uncertainty:

- Whether the Foundry project endpoint's rejection is a documented project-endpoint limitation, a deployment/model limitation, or a Microsoft service defect.
- Whether a direct Azure OpenAI endpoint for the selected current deployment already exists and is reachable through the intended private networking.
- Whether Microsoft support would recommend file-ID staging specifically for this project endpoint and model.

## Recommended correction

### Preferred target

Use the direct Azure OpenAI `/openai/v1/` endpoint for the model call and restore the documented inline image form:

- JPEG/PNG: `input_image.image_url = data:<mime>;base64,...`
- PDF: retain the existing documented `input_file.file_data` path
- No temporary provider file creation
- No provider file deletion lifecycle

This matches the official image example and the application's actual need: model inference without Foundry-specific agent/platform tools.

This is not a configuration-only change until the following are verified:

- A direct Azure OpenAI endpoint/resource exists for the intended environment.
- The intended GPT deployment is available on that resource.
- The model/deployment supports image inputs.
- Private endpoint, DNS, firewall, and Equinix-routed connectivity permit access.
- The API credential/authentication approach is correct.
- Existing PDF Responses calls and structured outputs remain compatible.

### Acceptable fallback only after a deliberate decision

Keep the Foundry project endpoint and use temporary Files API staging only if:

- Microsoft documentation/support confirms that file-ID input is the supported route for this endpoint/model.
- Security/privacy accepts transient provider file storage.
- Expiration and deletion guarantees are defined.
- Deletion failures are monitored and recoverable.
- The additional latency and API operations are accepted.
- End-to-end tests cover cleanup after success, model failure, timeout, and deletion failure.

The fact that the workaround succeeds is insufficient by itself.

## Surgical rollback plan

Do not roll back the structured error, retained-run, or contractor UI improvements from commit `ca12cc85`.

1. Inspect the exact `ca12cc85` diff for:

   - `claims_ai_service/src/services/inv.service.ts`
   - `claims_ai_service/src/services/inv.service.spec.ts`

2. Remove only the JPEG/PNG provider-file staging behavior:

   - Remove `files.create(...)` for image attachments.
   - Remove `purpose: 'assistants'`.
   - Remove `input_image.file_id`.
   - Remove provider file-ID collection used solely for this image path.
   - Remove image-specific provider-file deletion that becomes unused.
   - Preserve diagnostic IDs, structured error mapping, retry classification, and bounded private logging.

3. Restore the documented inline image payload:

   - `type: 'input_image'`
   - `image_url: data:image/jpeg;base64,...` or `data:image/png;base64,...`
   - `detail: 'auto'` may remain if supported.

4. Update only directly affected tests:

   - Assert inline Base64 `input_image`.
   - Assert the Files API is not called for JPEG/PNG.
   - Delete tests that exist solely to verify temporary provider-file creation/deletion.
   - Preserve tests for structured provider errors and retry behavior.

5. Change the endpoint only after Azure verification.

6. The rollback and endpoint correction must be deployed/tested together. Restoring inline images while leaving the current project endpoint unchanged will reproduce the HTTP 400 failure.

## Verification plan

### A. Azure/configuration verification

- Identify the direct Azure OpenAI resource and endpoint intended for development, Gold, and production.
- Confirm the current model deployment name on each resource.
- Confirm image input support for that deployment.
- Confirm private endpoint IP, private DNS resolution, firewall route, and HTTPS connectivity from Claims AI.
- Confirm whether the project endpoint is needed for any feature in the current codebase.
- If retaining the project endpoint is considered, open a Microsoft support case with a minimal reproduction showing:
  - documented inline Base64 request
  - old baseline JPEG
  - HTTP 400 `invalid_payload`
  - same bytes succeeding through `file_id`

### B. Node unit tests

- JPEG becomes inline `input_image.image_url`.
- PNG becomes inline `input_image.image_url`.
- Correct MIME prefix is retained.
- PDF remains inline `input_file.file_data`.
- Mixed PDF/JPEG/PNG request preserves all attachments.
- Files API is never called for normal classifier attachments.
- HTTP 400 `invalid_payload` remains non-retryable.
- Provider status, provider code, diagnostic ID, phase, and safe error category are retained.
- Private provider detail remains bounded in Node logs and is not leaked to contractors.

### C. Live integration tests

Test against the proposed direct endpoint:

- The July 30 before photo.
- The July 30 after photo.
- The older `Insulation before photo.jpg`.
- An older progressive JPEG.
- A PNG.
- A deliberately corrupt image.
- A PDF invoice.
- A mixed invoice plus JPEG package.

Expected results:

- All valid images reach inference through inline data URLs.
- Corrupt files receive the correct safe user error and detailed retained diagnostic.
- Non-retryable 400s are not retried.
- No provider Files objects are created.

### D. End-to-end application tests

Run through both initial upload and upload-fix flows:

- Contractor invoice-only upload.
- Contractor invoice plus one valid JPEG.
- Contractor invoice plus before/after JPEGs.
- Contractor invoice plus PDF supporting document and JPEGs.
- Admin upload equivalent.
- Admin upload-fix equivalent.
- Contractor upload-fix equivalent.
- Failure followed by replacement of the invalid file.

Verify:

- One stable standard error display.
- Error does not flash and disappear.
- Header/status polling does not duplicate errors.
- No abandoned invoice/evidence rows on failed initial upload.
- Ingest run, ingest document, and step-run diagnostics remain retained.
- Successful files are promoted correctly.
- Classifier sees actual image content, not merely OCR text.
- PI flagging still records per-file results.

### E. Regression and observability checks

- PDF classification remains unchanged.
- Document Intelligence Read and Invoice calls remain unchanged.
- Supporting-document extraction remains unchanged.
- Retry policy remains conditional.
- Duration/start/completion fields remain populated.
- Ingest Runs admin screen shows the filename and full structured failure fields.
- No secrets, Base64 payloads, or unnecessary PI appear in Rails responses or contractor-visible errors.

## Decision required after restart

Before changing runtime code, answer:

1. Does the intended Azure environment already have a direct Azure OpenAI endpoint containing the current image-capable model deployment?
2. Is there any current feature that genuinely requires the Foundry project endpoint rather than direct Azure OpenAI?
3. Should the next change be:
   - the recommended paired direct-endpoint correction plus surgical removal of temporary file staging, or
   - a temporary restoration of the failing inline path solely to preserve architectural correctness while Azure is fixed?

The recommended answer is the paired correction. Do not knowingly restore a path that remains broken in the active environment.

## Useful resume commands

```bash
git status --short
git show --stat ca12cc85
git show ca12cc85 -- claims_ai_service/src/services/inv.service.ts
git show ca12cc85 -- claims_ai_service/src/services/inv.service.spec.ts
git show 3a769ef9^:claims_ai_service/src/services/inv.service.ts
git show 3a769ef9:claims_ai_service/src/services/inv.service.ts
```

## Scope boundary

Creating this plan did not authorize or perform a runtime-code rollback. The next session should read this plan first, verify Azure endpoint availability, and then make a surgical correction without reverting the other July 30 error-handling and ingest-retention improvements.
