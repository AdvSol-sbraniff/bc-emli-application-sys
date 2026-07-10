# GenAI Context Window Specification

This document is the source-of-truth context-window specification for claims `genai_upgrade` calls.

When changing, debugging, or reviewing this area, always ask:

> Is the actual `context_window_json` aligned to this spec?

The persisted outbound context window is stored on `claims.ingest_step_runs.context_window_json` for the `genai_upgrade` step. The assistant reply is not part of `context_window_json`; it is persisted separately in `claims.ingest_step_runs.genai_results_json` and then inspected/applied to the evidence tables.

## Upgrade GenAI Context Stack

The pipeline builds these layers as Ruby objects before the final upgrade-type GenAI call. The actual context window is assembled at the last moment in the upgrade-type call.

| Order | Short Description                      | Message Slot  | Required Content                                                                                                                                                                                                                        |
| ----- | -------------------------------------- | ------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1     | JSON of rules                          | system record | `claims.validationgenai_config.system_record`: JSON/schema instructions for the upgrade-call assistant reply, plus pass/fail overall guidance and overall guidance.                                                                     |
| 2     | DI-invoice explanation                 | user record 0 | `claims.validationgenai_config.user_record0`: Document Intelligence invoice schema explanation and OCR guidance.                                                                                                                        |
| 3     | Fields to locate and rules to evaluate | user record 1 | Runtime-applied blob of all rules and located fields to evaluate for the upgrade type.                                                                                                                                                  |
| 4     | Supporting docs possible               | user record 2 | Supporting document types that are known possibilities for this upgrade type.                                                                                                                                                           |
| 5     | Supporting docs attached               | user record 3 | Supporting documents actually attached. Includes the supporting-document table/routing quality plus located fields and visual findings.                                                                                                 |
| 6     | Case facts / pre-existing DB values    | user record 4 | Database facts about contractors, users, and eligibility that existed before the invoice being loaded.                                                                                                                                  |
| 7     | Classifier-located key fields          | user record 5 | Classifier output from the invoice, such as document kind, detected upgrade types, and eligibility code. Product identity extraction belongs to normal GenAI located fields and supporting-document extraction, not classifier context. |
| 8     | Raw DI invoice                         | user record 6 | Raw Document Intelligence invoice JSON.                                                                                                                                                                                                 |
| 9     | One-liner                              | user record 7 | The direct one-line ask instructing the model to perform location/rulecheck tasks and reply using the strict JSON schema.                                                                                                               |
| Reply | Assistant response                     | assistant     | The assistant response must comply with the JSON format defined in the system record. It is inspected and used to populate the evidence world of tables.                                                                                |

## Alignment Checks

Use these checks against the persisted `context_window_json` for a concrete `genai_upgrade` run:

- The outbound context should have one system message followed by user records 0 through 7, in order.
- User record 1 must be upgrade-specific and contain the runtime blob of located-field prompts and rules for that upgrade type.
- User record 2 should list configured supporting-document possibilities for the upgrade type, even when none were attached.
- User record 3 should list only actually attached supporting documents for the package and upgrade type. For an invoice-only run, it should show no attached documents.
- User record 4 should contain pre-existing database facts, not facts invented from the invoice.
- User record 5 should reflect classifier output from the invoice, including detected upgrade types and eligibility code when present.
- User record 6 should contain the raw DI invoice JSON used by the upgrade GenAI call.
- The assistant reply should be checked in `genai_results_json`, not in `context_window_json`.
