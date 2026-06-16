# AI Contractor Portal Test Harness Plan

Purpose: focused test strategy for the AI contractor invoice flow. The master map is `ai_contractor_portal_plan.md`.

Gate 0 update:

- Tests must cover hybrid validation, not just GenAI responses.
- Add deterministic-code fixtures for date math, U-factor thresholds, rebate caps, and rebate arithmetic.
- Add GenAI evidence-location fixtures for U-factor, skylights, certification identifiers, rebate lines, and rough-opening language.
- Add `unknown` cases where evidence is missing but the system must not pretend the rule failed.

## Principle

Manual testing is not enough. The flow has file uploads, OCR, GenAI, contractor permissions, admin transitions, revision loops, retry behavior, feature flags, and local/Gold differences.

Build tests before or alongside implementation so we do not find every broken edge by clicking around with cold coffee and vibes.

User guides and UAT scripts should align with this harness. If a guide says users can do something, tests should eventually cover it.

## Test Personas

Contractor:

- MiniMe-style BCeID contractor/employee user.
- Must be associated to an approved contractor.

Admin:

- sbraniff as regular admin.
- Mandy as UX/BA/admin tester.

System admin:

- sbraniff as system admin when setup/config screens are needed.

## DDL/Seed Smoke Tests

Validate local DB has:

- Program seed data.
- Contractor seed data.
- Contractor/user relationships.
- Seven invoice upgrade types from `public.permit_classifications`.
- Windows and doors ruleset with `upgrade_type_id`.
- Ruleset enabled flag.
- AI invoice statuses.
- Views compile.
- No meaningful session status dependency remains.

Potential artifact:

- `claims_ai_service_ddl/check_ai_contractor_seed.sql`

## API Smoke Tests

Contractor endpoints:

- List own AI invoices.
- Cannot list another contractor's AI invoices.
- Create session.
- Upload PDF.
- Reject non-PDF invoice upload.
- Submit blocks when tracked first-class fields are null.
- Submit succeeds when tracked first-class fields exist.
- Delete pre-submit invoice.
- Cannot delete after submit.
- Upload fix +1 creates new version.
- Retry starts from failed step.
- Add supplement.

Admin endpoints:

- List AI invoices.
- Assign invoice.
- Screen in / move to `in_review`.
- Request revision.
- Approve pending.
- Approve paid.
- Mark ineligible.
- Regular admin/system admin visibility and permissions.

## Browser/E2E Happy Path

Path:

1. Contractor logs in.
2. Contractor opens `Invoice upload assistant`.
3. Contractor starts Windows and doors upload.
4. Contractor uploads one PDF.
5. OCR/GenAI completes.
6. Contractor sees invoice as `Draft`.
7. Contractor opens viewer and sees PDF, extracted fields, highlights, confidence, and rule findings.
8. Contractor submits.
9. Admin logs in.
10. Admin sees invoice in admin queue.
11. Admin screens in.
12. Admin approves pending.
13. Admin approves paid.

## Browser/E2E Failure Paths

Paths:

- Upload fails and retry starts at upload.
- OCR fails and retry starts at OCR.
- GenAI fails and retry starts at GenAI.
- Missing tracked first-class fields block submit.
- Contractor uploads fix +1 and OCR/GenAI reruns.
- Contractor adds supplement.
- Feature flag off hides contractor tab.

## Tooling Choice

First choice:

- Use the repo's existing test conventions if present.

If no established E2E tooling:

- Start with SQL and Rails/API smoke scripts because they are faster and less brittle.
- Add browser E2E after the contractor screens exist.

## Gold Readiness Gate

Gold migration should wait until:

- DDL/seed smoke passes locally.
- API smoke passes locally.
- Browser happy path passes locally.
- At least one failure path has been tested.
- Stephen and Mandy have manually tested the local flow.
