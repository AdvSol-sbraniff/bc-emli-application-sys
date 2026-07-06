# Package / Document / Evidence Data Model Backlog Plan

## Purpose

This is a future cleanup plan for the claims AI data model. The current model can work for end users, but it has several internal concepts that are harder than necessary for humans and AI agents to reason about:

- `invoice_versions` is really acting as a package version.
- Invoice files and supporting documents are stored as separate concepts even though both are documents in a package.
- Invoice located fields and supporting-document located fields are separated even though both are extracted evidence from documents.
- Visual findings are attached only to supporting documents today; in the future model they should still be a distinct table, but should hang under the same package-document parent as other document-level data.

The cleaner long-term model is:

```text
package
  package_versions
    package_version_upgrade_types
      package_version_upgrade_type_rulechecks

    package_version_documents
      di_invoice
        di_invoice_line_items

      document_evidence
      document_visual_findings
```

## Design Direction

Use `package_versions` as the evaluated package snapshot. A package version contains documents and claimed/detected upgrade types.

Use one document table for every file in the package version:

```text
package_version_documents
```

The invoice PDF should be a document row with `document_kind = 'invoice'`. Supporting PDFs, photos, labels, WETT reports, quotes, and other attachments should be document rows with `document_kind = 'supporting_document'`.

Invoice-specific extracted facts should not live directly on `package_versions`. They should live below the invoice document:

```text
di_invoice
di_invoice_line_items
```

Generic extracted evidence should live below documents:

```text
document_evidence
```

This table should hold located fields, classifier evidence, OCR snippets, GenAI observations, page numbers, polygons, confidence, and source engine.

Visual observations should remain separate:

```text
document_visual_findings
```

This keeps visual findings easy to display and reason about without making `document_evidence` too broad.

## Proposed Table Responsibilities

### `packages`

Stable identity for the claim package across versions.

Likely owns:

- Package UUID.
- Contractor/company association.
- Created/updated timestamps.
- Any stable cross-version identifiers.

### `package_versions`

The evaluated version/snapshot of a package.

Likely owns:

- Current-version marker.
- Status and status subtype.
- Participant user UUID.
- Users eligibility code UUID.
- Aggregate advice and final outcome.
- Pipeline linkage such as ingest run UUID.
- Version number.

This replaces the current conceptual role of `invoice_versions`.

### `package_version_documents`

All files attached to a package version.

Likely owns:

- Package version UUID.
- Document UUID.
- File/blob reference.
- Original filename.
- MIME type.
- Document kind, such as `invoice` or `supporting_document`.
- Classifier document type.
- Clone/reuse metadata.
- Sort/display order.

Important rule: the model should require exactly one invoice document for normal invoice-processing package versions.

### `di_invoice`

Invoice-specific Document Intelligence / OCR result for the invoice document.

Likely owns:

- Invoice document UUID.
- Invoice number.
- Invoice date.
- Vendor/supplier name.
- Customer/participant name.
- Total/amount due fields from DI.
- Raw DI JSON or reference to raw OCR/DI output.

This should exist only for the document row where `document_kind = 'invoice'`.

### `di_invoice_line_items`

Line items extracted from the invoice.

Likely owns:

- DI invoice UUID.
- Description.
- Quantity.
- Unit price.
- Line amount.
- Page/polygon when available.
- Raw/source metadata.

### `document_evidence`

Generic extracted evidence from any package-version document.

Likely owns:

- Package version document UUID.
- Evidence kind, such as `field`, `classification`, `summary`, or `ocr_snippet`.
- Evidence key, such as `amount_due_after_rebate`, `eligibility_code`, `fenestration_energy_label_found`, etc.
- Value fields, such as text, number, date, boolean, and JSON.
- Evidence text.
- Page number.
- Polygon / bounding region.
- Confidence.
- Source engine, such as `di`, `ocr`, `genai`, `code`, or `clone`.
- Clone/reuse source metadata.

The table should be generic, but not vague. Rows should still have clear evidence keys and source engines.

### `document_visual_findings`

Useful visual observations from any package-version document.

Likely owns:

- Package version document UUID.
- Finding sequence number.
- Finding type, such as `manufacturer_label_photo`, `energy_label_visible`, or `before_after_photo`.
- Summary.
- Page number.
- Legibility.
- Relevant text seen.
- Confidence.
- Source engine, such as `genai`, `vision`, or `manual`.
- Raw JSON/source metadata.

This remains separate from `document_evidence` because visual findings are usually narrative observations rather than scalar located fields. Keeping them separate should make admin display and troubleshooting clearer.

### `package_version_upgrade_types`

Upgrade types detected or evaluated for the package version.

Likely owns:

- Package version UUID.
- Upgrade type UUID.
- Classifier source metadata.
- Product reference metadata if needed.
- Display label / sequence.

### `package_version_upgrade_type_rulechecks`

Rulecheck results for an upgrade type in a package version.

Likely owns:

- Package version upgrade type UUID.
- Rule UUID/key.
- Result: pass, fail, warn, info.
- Advice JSON/text.
- Calculation.
- Evidence references where useful.

## Why This Is Better

- A package version has two obvious child concepts: documents and upgrade types.
- Invoice files and supporting files are handled with one document model.
- Located fields and visual findings share the same document parent, but remain separate evidence tables.
- Fix/reuse/clone logic can work against documents consistently.
- Admin screens can show package documents with one query.
- Future AI agents can reason with fewer special cases.

## Why Not Do This Immediately

The current model can still work for end users. This refactor is primarily about maintainability, clarity, and future-proofing.

This should not be mixed into ongoing AI pipeline bug fixes unless the team deliberately decides to spend time on a structural refactor. Doing it casually would risk new pipeline bugs.

## Migration Strategy

Do this only in a dedicated branch.

Recommended sequence:

1. Create the new schema in DDL files.
2. Add compatibility views if needed so old names can be compared during migration.
3. Add model-level tests for the new relationships and constraints.
4. Migrate the new-invoice upload path first.
5. Migrate fix-package path second.
6. Migrate refresh-advice path third.
7. Update admin and contractor screens.
8. Remove or archive old tables only after all pipeline paths and tests pass.

## Required Test Scenarios

- New upload with one invoice only.
- New upload with invoice plus supporting documents.
- Fix adds supporting documents.
- Fix removes supporting documents.
- Fix with no file changes.
- Fix with changed invoice.
- Refresh AI advice without document changes.
- Unsupported invoice with no supported upgrade types.
- Package with no invoice PDF.
- Cloned evidence is inferred from DB evidence and does not create fake step-run rows.
- Visual findings display correctly from `document_visual_findings`.
- Located fields/classifier/OCR evidence display correctly from `document_evidence`.

## Open Design Questions

- Should `document_kind` be a simple text enum or backed by a registry table?
- Should invoice-specific DI fields live in one `di_invoice` row with columns, or as `document_evidence` rows plus raw JSON?
- Should `document_evidence` allow multiple typed value columns, or one JSON `value` plus typed helper columns?
- Should `document_visual_findings.finding_type` stay free text, or should it eventually be backed by a registry/constraint?
- How strict should the database constraint be for exactly one invoice document per package version?
- What is the cleanest compatibility path for existing admin screens and tests?

## Backlog Recommendation

This is a good long-term data model direction. It should be treated as a planned refactor, not a bug fix.

Estimated effort:

- Best case: 16 hours.
- Realistic: 24-32 hours.
- Risky shortcut: 8-12 hours, not recommended.

The refactor is worth considering after the current AI pipeline behavior is stable and covered by regression tests.
