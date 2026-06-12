# GenAI Upgrade Context Window Refactor Plan

Status: draft plan

Purpose: define the target context-window shape for `genai_common` and `genai_upgrade` rule calls. The goal is to make each user record have one clear job instead of packing all case facts into one large blob.

## 1. Problem

The current rule-call context window is understandable, but `user_record2` is doing too much. It contains a mixed case-facts blob with supporting-document configuration, attached-document evidence, database facts, and classifier-derived facts.

That makes it harder to answer simple questions:

- Which supporting documents were possible for this upgrade type?
- Which supporting documents were actually attached?
- Which facts came from trusted pre-existing database rows?
- Which facts came from AI/classifier extraction?
- Where should future product enrichment appear?
- Are visual findings from supporting documents available to rules?

The refactor should keep the runtime behavior auditable while making the context window easier for humans and models to reason over.

## 2. Target Stack

The target context window for `genai_common` and `genai_upgrade` calls is:

| Record         | Short description                      | Long description                                                                                                                                                                                           |
| -------------- | -------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `system`       | JSON/rule behavior                     | `claims.validationgenai_config.system_record`. Defines the strict assistant JSON response shape, rule result vocabulary, evidence expectations, pass/info/warn/fail guidance, and overall advice behavior. |
| `user_record0` | DI invoice explanation                 | `claims.validationgenai_config.user_record0`. Explains how to read Document Intelligence invoice JSON, page evidence, polygons, line items, content, words, and tables.                                    |
| `user_record1` | Fields to locate and rules to evaluate | Compiled runtime text from `claims.genai_located_fields`, `claims.genai_located_field_upgrade_types`, `claims.genai_rules`, and `claims.genai_rule_upgrade_types` for the current upgrade type.            |
| `user_record2` | Supporting documents possible          | Configured supporting-document types that are relevant to this upgrade type. This answers "what document categories could matter here?"                                                                    |
| `user_record3` | Supporting documents actually attached | Evidence from promoted `claims.supporting_documents`, including document type, routing quality, classification reason, located fields, and visual findings.                                                |
| `user_record4` | Pre-existing database values           | Trusted database facts that existed before invoice processing, such as contractor facts, participant/user facts, eligibility-code lookup rows, and invoice DB facts.                                       |
| `user_record5` | Classifier-located key fields          | AI/classifier-derived facts found during invoice triage, such as detected upgrade types and invoice-visible eligibility code. These are not trusted DB facts.                                              |
| `user_record6` | Download product enrichment            | Product-list match context from AHRI, NEEA, AWHP, or OHPA. This should be populated after `product_lookup_enrichment` moves before GenAI rule calls.                                                       |
| `user_record7` | Raw DI invoice JSON                    | `claims.invoice_versions.di_raw_json`, the raw invoice-model Document Intelligence payload for the resolved invoice version.                                                                               |
| `user_record8` | One-line ask                           | Runtime instruction telling the model to perform the rule/field tasks and reply using the strict JSON schema from the system record.                                                                       |
| `assistant`    | Model reply                            | Strict JSON response. Stored first in `claims.ingest_step_runs.genai_results_json`, then applied into located fields, rulechecks, upgrade-type result rows, and invoice-version summary fields.            |

## 3. Key Design Decisions

Keep `user_record4` and `user_record5` separate.

`user_record4` is trusted pre-existing database state. It is suitable for deterministic comparison and code-owned located fields.

`user_record5` is AI/classifier-derived evidence from the uploaded package. It is useful context, but it should not be confused with database truth.

Split supporting-document context into possible vs attached.

`user_record2` should describe configured possibilities for the current upgrade type. `user_record3` should describe actual uploaded evidence. This lets a rule distinguish "this document type is expected/relevant" from "this document was actually attached and contained these facts."

Include visual findings in attached supporting-document evidence.

Visual findings should be available in `user_record3` beside supporting-document located fields. A GenAI rule should be able to evaluate photo/label/WETT evidence from persisted visual findings without reopening the source PDF during the rule call.

Move product enrichment before GenAI rule calls.

`user_record6` is part of the target stack. To populate it correctly, `product_lookup_enrichment` must run before `genai_common` and `genai_upgrade`.

The dependency chain should be:

```text
triage_classifier finds eligibility/product references
case_facts persists classifier facts into invoice_version_located_fields
product_lookup_enrichment uses classifier facts to match download product rows
genai_common/genai_upgrade receive product enrichment in user_record6
```

Persist classifier-located key fields as evidence.

Add `source_engine = 'classifier'` to `claims.invoice_version_located_fields`. This gives the early triage/classifier facts a durable evidence-world home instead of leaving them only inside `claims.ingest_documents.classifier_raw_json`.

These rows should be distinct from:

- `source_engine = 'code'`: trusted database/code snapshots.
- `source_engine = 'genai'`: fields located during GenAI rule calls.
- `source_engine = 'classifier'`: invoice/package facts found by the triage classifier before rule calls.

Use `classifier`, not `classifer`.

## 4. Proposed Data Shape

### 4.1 `user_record2`: Supporting Documents Possible

Suggested JSON-ish shape:

```json
{
  "record_name": "supporting_documents_possible",
  "invoice_upgrade_type": {
    "id": "...",
    "upgrade_type_key": "air_source_heat_pump_wood"
  },
  "configured_supporting_document_types": [
    {
      "supporting_document_type_id": "...",
      "type_key": "wett_report",
      "description": "WETT report",
      "required": null
    }
  ]
}
```

Notes:

- `required` should only be populated if the data model truly supports requiredness.
- Do not infer requiredness from rule text in this record.

### 4.2 `user_record3`: Supporting Documents Actually Attached

Suggested JSON-ish shape:

```json
{
  "record_name": "supporting_documents_attached",
  "documents": [
    {
      "supporting_document_id": "...",
      "original_filename": "Heat Pump WETT report.pdf",
      "type_key": "wett_report",
      "type_description": "WETT report",
      "classification_status": "classified",
      "classification_confidence": 96,
      "classification_reason": "...",
      "supplement_routing_quality": "usable",
      "supplement_routing_quality_reason": "...",
      "located_fields": [
        {
          "field_key": "wett_report_present",
          "value_type": "bool",
          "value_text": "true",
          "confidence": 95,
          "page": 1,
          "evidence_text": "..."
        }
      ],
      "visual_findings": [
        {
          "finding_type": "fireplace_chimney_photo",
          "page": 7,
          "summary": "Roof-level photo shows the chimney top with a metal cap/liner termination visible.",
          "legibility": "not_applicable",
          "relevant_text_seen": [],
          "confidence": 93
        }
      ]
    }
  ]
}
```

### 4.3 `user_record4`: Pre-existing Database Values

Suggested JSON-ish shape:

```json
{
  "record_name": "pre_existing_database_values",
  "invoices": {
    "submitted_at": null
  },
  "contractors": {
    "business_name": "Example Contractor Ltd",
    "address": "..."
  },
  "users_eligibilitycodes": {
    "eligibility_code": "ESP2-123456",
    "income_level": 2,
    "approved_at": "2026-04-15",
    "expires_at": "2026-10-15"
  },
  "users": {
    "participant_name": "Example Participant",
    "participant_address": null
  }
}
```

### 4.4 `user_record5`: Classifier-located Key Fields

Suggested JSON-ish shape:

```json
{
  "record_name": "classifier_located_key_fields",
  "document_kind": "invoice",
  "detected_upgrade_types": ["air_source_heat_pump_wood"],
  "eligibility_code": "ESP2-123456",
  "confidence": 92,
  "raw_classifier_summary": {}
}
```

These values should be backed by `claims.invoice_version_located_fields` rows with `source_engine = 'classifier'` where possible.

Candidate field keys:

- `classifier.eligibility_code`
- `classifier.detected_upgrade_types`
- `classifier.ahri_reference`
- `classifier.neea_reference`
- `classifier.awhp_reference`
- `classifier.ohpa_reference`
- `classifier.product_model_number`

Important naming distinction:

- A classifier-located product reference is text/evidence found on the invoice, such as an AHRI reference number.
- A downloaded product match is a matched row from AHRI, NEEA, AWHP, or OHPA product tables.
- Do not call classifier-located references "download product keys" unless they are actual matched product-list row IDs.

### 4.5 `user_record6`: Download Product Enrichment

Suggested placeholder shape:

```json
{
  "record_name": "download_product_enrichment",
  "available": false,
  "reason": "No product enrichment match was available for this run."
}
```

Future shape can include matched product IDs plus selected comparison fields from AHRI, NEEA, AWHP, or OHPA.

After `product_lookup_enrichment` moves before GenAI rule calls, this record should normally be populated when classifier-located product references are present and a product-list match is found.

Suggested future populated shape:

```json
{
  "record_name": "download_product_enrichment",
  "available": true,
  "matches": [
    {
      "source": "AHRI",
      "invoice_version_column": "ahri_product_id",
      "product_id": "...",
      "reference": "1234567",
      "manufacturer": "Example Manufacturer",
      "model_number": "EXAMPLE-123",
      "selected_comparison_fields": {
        "capacity": "...",
        "efficiency": "...",
        "cold_climate_qualified": true
      }
    }
  ]
}
```

## 5. Target Pipeline Order

The target pipeline should use clearer phase labels than the old `ocr_in_progress` / `genai_in_progress` mental model.

Use these conceptual phases:

- `evidence_prep`: gather, classify, OCR, promote, and extract evidence before rule calls.
- `validation_advice`: build context, enrich references, run rules, and aggregate final advice.

Target step order:

| Step | Step run type                    | Phase                | Description                                                                                                                                                                                                                                                                                   |
| ---- | -------------------------------- | -------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1    | `upload_package_stage`           | `upload_in_progress` | Stage a new upload package or redo package. Create session/invoice context and upload PDFs to Azure.                                                                                                                                                                                          |
| 2    | `ocr_read`                       | `evidence_prep`      | Run DI-read OCR for each staged PDF.                                                                                                                                                                                                                                                          |
| 3    | `triage_classifier`              | `evidence_prep`      | Classify each DI-read PDF as invoice, supporting document, or unknown. If invoice, detect upgrade types plus AHRI/product references and eligibility code. These classifier-located facts are later persisted in `claims.invoice_version_located_fields` with `source_engine = 'classifier'`. |
| 4    | `ocr_invoice`                    | `evidence_prep`      | Require exactly one invoice candidate. Promote that PDF into `claims.invoice_versions`, run DI-invoice OCR, and populate first-class invoice fields and line items. Promote supporting documents with type, classifier payload, DI-read JSON, and located fields.                             |
| 5    | `supporting_document_extraction` | `evidence_prep`      | Run supporting-document extraction for each DI-read supporting document type. Send the full PDF when visual findings may matter, and store located fields plus visual findings.                                                                                                               |
| 6    | `case_facts`                     | `validation_advice`  | Use the classifier-located eligibility code to build case facts JSON from DB. Persist DB facts in `claims.invoice_version_located_fields` with `source_engine = 'code'`, and persist classifier facts with `source_engine = 'classifier'`.                                                    |
| 7    | `product_lookup_enrichment`      | `validation_advice`  | Use product references extracted by the classifier to build product enrichment context from the download tables.                                                                                                                                                                              |
| 8    | `genai_common`                   | `validation_advice`  | Build the context window just in time and call GenAI once for common rules.                                                                                                                                                                                                                   |
| 9    | `genai_upgrade`                  | `validation_advice`  | Build the context window just in time and call GenAI once per classified upgrade type.                                                                                                                                                                                                        |
| 10   | `code_common`                    | `validation_advice`  | Run deterministic common rules.                                                                                                                                                                                                                                                               |
| 11   | `code_upgrade`                   | `validation_advice`  | Run deterministic rules for each detected upgrade type.                                                                                                                                                                                                                                       |
| 12   | `aggregate_advice`               | `validation_advice`  | Aggregate GenAI and code outputs into final advice/result.                                                                                                                                                                                                                                    |

## 6. Implementation Plan

1. Add a context-window builder layer for rule calls.

Create or refactor code so `RunGenaiJob#build_contextwindowjson` delegates record construction to a small builder with explicit methods for each record.

2. Split current case facts into named sections.

Refactor `Claims::GenaiCaseFacts::Build` output or add a presentation adapter that turns the existing case-facts hash into `user_record2` through `user_record5`.

3. Add visual findings to supporting-document attached evidence.

Update supporting-document serialization in the case-facts path to include `claims.supporting_document_visual_findings`.

4. Add classifier located-field persistence.

Update the schema check constraint for `claims.invoice_version_located_fields.source_engine` to allow `classifier`.

During the `case_facts` step, persist normalized classifier-derived facts into `claims.invoice_version_located_fields` with `source_engine = 'classifier'`.

This should happen after an `invoice_version_id` exists and before `genai_common` / `genai_upgrade` context windows are assembled.

5. Move product lookup enrichment before GenAI rule calls.

Change `RunGenaiJob` order so `product_lookup_enrichment` runs after `case_facts` and before `genai_common` / `genai_upgrade`.

The product lookup step should use classifier-located product references persisted in `claims.invoice_version_located_fields` where possible.

6. Build `user_record6` from product enrichment.

Add a product enrichment context presenter that reads matched product IDs and selected comparison fields from AHRI, NEEA, AWHP, and OHPA product tables.

If no product match is available, include an explicit unavailable/empty product enrichment record.

7. Keep compatibility during rollout.

Do not change the GenAI response schema as part of this refactor. The assistant reply should still populate the same evidence-world tables.

8. Preserve step-run auditability.

Store the final context window in `claims.ingest_step_runs.context_window_json` exactly as sent to the GenAI service.

9. Add tests using `test006`.

Use the WETT report package to confirm `user_record3` includes located fields and visual findings before `genai_common` and `genai_upgrade` calls run.

## 7. Testing Checklist

- `test006` full package reaches `genai_complete`.
- `supporting_document_extraction` stores visual findings for the WETT report.
- `product_lookup_enrichment` runs before `genai_common` and `genai_upgrade`.
- `genai_common.context_window_json` includes `user_record2` through `user_record8`.
- `genai_upgrade.context_window_json` includes `user_record3.documents[].visual_findings`.
- `genai_common.context_window_json` and `genai_upgrade.context_window_json` include `user_record6`.
- `claims.invoice_version_located_fields` includes classifier rows for classifier-located key fields when present.
- `user_record5` is built from normalized classifier-located fields, not only raw classifier JSON.
- Existing rulechecks still persist into `claims.invoice_version_rulechecks`.
- Existing invoice located fields still persist into `claims.invoice_version_located_fields`.
- Admin PDF viewer and Invoice Supporting Documents screen still show supporting-document located fields and visual findings.

## 8. Non-goals

- Do not remove existing evidence tables.
- Do not infer supporting-document requiredness from rule text.
- Do not change the strict assistant JSON response schema unless a separate response-schema plan is created.
- Do not add a second GenAI rule pass in this plan.

## 9. Open Questions

- Should `user_record6` be omitted entirely when unavailable, or included with an explicit unavailable placeholder? Current preference: include an explicit unavailable/empty record.
- Should common calls receive all supporting-document possible/attached context, while upgrade calls receive filtered context?
- Should classifier raw JSON be included in `user_record5`, or only normalized key facts?
- Should the context-window UI/debugger display these user records as named sections?
