# GenAI Provider Diagnostics Plan

## Purpose

Add enough diagnostics around Claims AI GenAI provider calls to explain failures like provider timeouts without polluting Rails evidence tables with low-level transport details.

The goal is not to change retry behavior, reduce parallelism, or shrink prompts in this phase. The goal is to make the next failure explainable.

## Problem

The current failure path collapses provider details too aggressively:

1. Rails calls the Node service endpoint `/inv/genai`.
2. Node calls the configured GenAI provider through the OpenAI SDK.
3. If the provider call fails in a low-level way, Nest returns a generic `500`.
4. Rails stores a steprun error like `Node GenAI failed 500: {"statusCode":500,"message":"Internal server error"}`.

That is not enough to distinguish:

- provider timeout
- gateway timeout
- provider throttling
- quota/capacity issue
- model/content rejection
- client/network abort
- invalid provider response
- app-side timeout

## Design Principle

Keep the detailed provider diagnostics in Node structured logs.

Rails should receive only a readable failure summary and a diagnostic id that can be used to find the matching Node log event.

## Diagnostic Id

For every GenAI provider call, Node should generate a diagnostic id before calling the provider.

Suggested format:

```text
genai_<timestamp>_<short-random-id>
```

Example:

```text
genai_20260615T201648Z_a1b2c3d4
```

This id should be included in:

- Node start log
- Node success log
- Node failure log
- Rails-facing error response when the provider call fails
- Rails `ingest_step_runs.error_text` through the existing raised error path

## Node Structured Logs

### Start Event

Before the provider call, log one structured JSON event.

Suggested event name:

```text
claims.genai.request.started
```

Fields:

- `diagnostic_id`
- `api_style`
- `deployment`
- `endpoint_host`
- `attachment_count`
- `attachment_mime_types`
- `attachment_byte_sizes`
- `context_chars`
- `instructions_chars`
- `input_chars`
- `started_at`

If Rails passes diagnostic context, also include:

- `step_type`
- `ingest_run_id`
- `ingest_document_id`
- `invoice_version_id`
- `original_filename`

Do not log secrets, SAS tokens, full file contents, full prompts, or full DI JSON.

### Success Event

After a successful provider response, log:

```text
claims.genai.request.succeeded
```

Fields:

- all correlation fields from the start event
- `elapsed_ms`
- `provider_response_id` if available
- `usage_input_tokens` if available
- `usage_output_tokens` if available
- `usage_total_tokens` if available
- `output_chars`

### Failure Event

If the provider call fails, log:

```text
claims.genai.request.failed
```

Fields:

- all correlation fields from the start event
- `elapsed_ms`
- `error_name`
- `error_constructor`
- `error_message`
- `error_code`
- `error_type`
- `error_status`
- `error_cause_name`
- `error_cause_message`
- `provider_request_id` if available
- `response_headers` if available and safe
- `response_body_snippet` if available and safe

The failure event should be JSON so Docker/OpenShift log search can filter by `diagnostic_id`.

## Rails-Facing Error Response

When Node catches a provider failure, it should return a bounded error response instead of the generic Nest `Internal server error`.

Example:

```json
{
  "message": "GenAI provider request failed",
  "diagnostic_id": "genai_20260615T201648Z_a1b2c3d4",
  "category": "provider_timeout",
  "elapsed_ms": 32742
}
```

Suggested categories:

- `provider_timeout`
- `provider_throttled`
- `provider_gateway_error`
- `provider_auth_error`
- `provider_bad_request`
- `provider_content_filter`
- `provider_connection_error`
- `provider_unknown_error`

Rails should keep storing the raised error in `ingest_step_runs.error_text`, but the message should now include the diagnostic id and category.

## Rails Diagnostic Context

Update Rails callers of `/inv/genai` to pass a small optional `diagnostic_context` object.

Suggested fields:

- `step_type`
- `ingest_run_id`
- `ingest_document_id`
- `invoice_version_id`
- `invoice_upgrade_type_id`
- `supporting_document_group_id`
- `original_filename`

Node should treat this as optional metadata only. It should not affect the model input.

## Files Likely Touched

Node:

- `claims_ai_service/src/services/inv.service.ts`
- possibly `claims_ai_service/src/controllers/inv.controller.ts` if DTO shape needs explicit typing

Rails GenAI callers:

- `app/jobs/claims/run_ingest_triage_job.rb`
- `app/jobs/claims/run_invoice_version_classifier_job.rb`
- `app/jobs/claims/run_supporting_document_extraction_job.rb`
- `app/jobs/claims/run_supporting_document_group_extraction_job.rb`
- `app/jobs/claims/run_genai_job.rb`
- `app/jobs/claims/run_genai_ruleset_job.rb`

## What This Phase Does Not Do

This phase does not:

- change retry count
- change Sidekiq retry behavior
- throttle parallel calls
- reduce prompt or DI payload size
- change model deployment
- write provider internals into evidence tables
- add a new database table
- rebuild Gold schema
- deploy or rebuild Gold images

Those decisions should come after the diagnostic logs show what kind of provider failure is actually occurring.

## Local Test Plan

1. Run a small successful GenAI smoke test.
2. Confirm Node logs contain `claims.genai.request.started`.
3. Confirm Node logs contain `claims.genai.request.succeeded`.
4. Confirm logs include diagnostic id, elapsed time, deployment, API style, input size, and attachment summary.
5. Confirm logs do not include secrets, SAS URLs, full prompts, full DI JSON, or file contents.
6. Run local test014 with the latest invoice PDF.
7. Confirm every classifier/extraction/validation GenAI call has matching start and success/failure events.
8. If a GenAI call fails, confirm Rails steprun error includes diagnostic id and category.
9. Search Docker logs by diagnostic id and confirm the low-level provider error details are findable.

## Optional Gold Verification

Gold rebuild/deploy is intentionally out of scope for this plan. If the user has already rebuilt/deployed Gold separately, use these verification-only checks:

1. Run a Gold GenAI smoke test.
2. Run test014 or a known package that exercises image classifier calls.
3. Use `oc logs` to search for a diagnostic id.
4. Confirm failed stepruns, if any, point to the exact Node diagnostic event.

## Success Criteria

The next GenAI failure should answer:

- which file/step failed
- which provider call failed
- how long it ran before failing
- whether the provider returned a status code
- whether it was timeout, throttling, gateway, auth, bad request, content filter, or unknown
- which provider request id/header can be used for Azure-side investigation

If the next failure still only says "Internal server error", this plan failed.
