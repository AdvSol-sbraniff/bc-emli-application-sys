# AI Rules Analysis Prerequisite Plan

Purpose: standalone plan for analyzing Better Homes BC Energy Savings Program requirements before redesigning contractor/admin AI screens or changing implementation code.

Status: prerequisite gate before AI contractor portal redesign.

Source:

Better Homes BC, `Energy Savings Program requirements`
URL: https://betterhomesbc.ca/learn about programs/energy savings program/energy savings program requirements/
Current working source vintage: requirements for invoices dated on or after April 1, 2026

## Why This Comes First

The contractor portal redesign depends on what the AI rules are actually allowed and able to check.

If we redesign the upload/review flow first, we may accidentally build the wrong product:

Too much confidence: implying AI can decide full eligibility from an invoice PDF.
Too little support: missing supporting documents that public requirements actually require.
Wrong workflow: asking contractors/admins for information at the wrong time.
Wrong statuses: treating a failed AI check like a final business rejection.
Wrong data model: storing fields without enough source/evidence traceability.

Therefore, the rules analysis must be completed before the larger redesign begins.

## Gate 0 Deliverables

Gate 0 is complete when these artifacts exist and have been reviewed:

`ai_ruleset_requirements_matrix.md` has one row per meaningful source requirement.
Each row is mapped to an app upgrade type or marked as common/all.
Each row has an evidence source: invoice PDF, supporting document, database, external list, or admin review.
Each row has an automatable level: invoice only, invoice plus DB, supporting doc required, external validation required, or manual review.
Each row has an evaluator choice: deterministic code engine, GenAI, DB query, external lookup, or manual/admin review.
Each row has a v1 decision: enforce, warn, show unknown, manual only, or out of scope.
Windows and doors has enough detail to draft a real v1 ruleset.
Other upgrade types have at least enough detail to know whether the current architecture still makes sense.
We have a short "architecture sanity check" saying whether the proposed AI contractor portal flow still makes sense.

No contractor portal implementation work should begin until Gate 0 is done.

## Analysis Passes

### Pass 1: Source Inventory

Read the public requirements page section by section.

Capture:

General eligibility requirements.
Common invoice requirements.
Common supporting documentation requirements.
Windows and doors requirements.
Insulation requirements.
Heat pump space heating requirements.
Heat pump water heater requirements.
Electrical service upgrade requirements.
Health and safety remediation requirements.
Ventilation requirements.
Links to external product lists, sample invoices, terms, installation guides, and supporting pages.

Do not paste long source text into the repo. Use short paraphrases plus source URL.

### Pass 2: Requirement Matrix

Populate `ai_ruleset_requirements_matrix.md`.

For each requirement, classify:

Is this common to all upgrades or upgrade specific?
Is it checkable from the invoice PDF?
Does it require supporting documents?
Does it require local/Gold database facts?
Does it require an external product list or guide?
Does it require admin judgment?
Should it be evaluated by code instead of GenAI?
Should v1 enforce, warn, show unknown, or defer it?

Evaluator guidance:

V1 direction update: use GenAI for rulechecks, fuzzy extraction, text interpretation, line item interpretation, and evidence location.
Deterministic code for date math, numeric caps, percentage calculations, equality/threshold comparisons, and DB vs OCR comparisons is a future option, not the v1 runtime path.
Use DB queries for program facts such as eligibility code, contractor registration, user/program relationship, prior rebate history, and submitted date.
Use external lookup services/tables for product lists, qualified model lists, AHRI/NRCan/CPD validation, or certification bodies.
Use manual/admin review when the public requirement depends on judgment, incomplete evidence, or policy context that is not safely encoded.

Important existing design hook:

The AI schema already supports `source_engine = 'code' | 'genai'` on `claims.invoice_version_located_fields`.
The AI schema already supports `source_engine = 'code' | 'genai'` on `claims.invoice_version_rulechecks`.
`Claims::GenaiCaseFacts::Build` already persists some DB/code derived located fields.
Gate 0 should therefore design a hybrid validation engine, not an all LLM ruleset.

### Pass 3: Upgrade Type Fit Check

Compare the public requirement structure to the app's seven current upgrade types:

Heat pump (space heating)
Heat pump water heater (including combined)
Insulation
Windows and doors
Ventilation
Electrical service upgrade
Health and safety remediation

Output:

Which public sections map cleanly to the seven app types.
Which public sections are more granular than the app.
Whether heat pump subtypes should stay inside a ruleset for now.
Whether any future UI will need a richer subtype model.

### Pass 4: V1 Scope Decision

Decide what v1 can safely do.

Current expected answer:

Enable Windows and doors only.
Build a source traced Windows and doors ruleset.
Let non Windows and doors invoices stop clearly rather than using a generic fallback.
Treat AI output as pre review.
Do not claim full eligibility.

This pass should explicitly confirm or overturn that expected answer.

### Pass 5: Workflow Impact

Use the matrix to decide what the contractor/admin flow must support.

Questions to answer from the analysis:

Which supporting documents must contractors upload in v1?
Can supplements remain generic, or do they need document type labels?
Which missing fields block submit?
Which missing evidence should be an admin warning only?
Which rules require DB comparisons before admin review?
Which rules should appear to contractors versus only admins?
Which statuses are needed for AI load failure, contractor draft, submitted, revision requested, in review, approved pending, approved paid, and ineligible?

### Pass 6: Ruleset Draft Plan

Only after the matrix is reviewed:

Draft `esp_windows_doors_2026_04_v1`.
Retire/replace `esp_default_v1`.
Add source requirement IDs to each rulecheck.
Use boolean pass/fail only; missing or unclear evidence fails with explanation.
Add fixture expectations before running against Gold.

## Stop/Go Criteria

Proceed to contractor portal redesign only if:

The Windows and doors v1 path is coherent.
Required supporting documents for Windows and doors are known.
The ruleset output shape supports `unknown` and source traceability.
Deterministic/code engine rulechecks are supported by the schema, but v1 should create GenAI rulechecks only.
The DB model can store upgrade type, ruleset ID, first class fields, located fields, rulechecks, supplements, and invoice status without fighting the requirements.
The UI plan can explain AI results without implying final eligibility.
The team has decided whether v1 assumes one upgrade type per uploaded invoice, or must support one invoice with multiple upgrade type claims.

Pause and re plan if:

Public requirements require documents we cannot upload/display.
The current invoice model cannot represent core evidence.
The rules are too dependent on external lists for v1.
Business stakeholders expect AI to perform final eligibility decisions.
Windows and doors turns out not to be a safe/simple first domain.
Business requires one uploaded invoice to support multiple upgrade types in v1; that requires a child claim model and is not just a UX tweak.

## Working Rule

Until Gate 0 is complete:

Do not change contractor portal code.
Do not change admin AI screens.
Do not change API workflow.
Do not migrate new rulesets to Gold.
Do not add more DDL beyond planning notes unless needed to inspect existing data.

Documentation and local analysis are allowed.
