# Create Test Data Menu And Contractors Screen Plan

Status: draft plan

Purpose: reorganize claims AI test-data utilities into one clear menu section and add a minimal contractor test-data screen. These screens exist to support local/admin test package creation. They are not intended to replace the legacy contractor onboarding or production contractor-management workflow.

## 1. Desired Menu Shape

Create a new AI menu section labelled:

```text
Create Test Data
```

Move or add these entries under it:

- `Create Test Contractors`
- `Create Test Users`
- `Create Test Eligibility Codes`
- `Manual Downloads`
- `Test AI Network Connectivity`

Keep the labels intentionally long. Clarity matters more than compactness for this section.

## 2. Existing Screens To Move Or Rename

Existing test-data screens:

- `/users-admin`
- `/eligibilitycodes-admin`
- `/downloads-admin`
- `/hello-ai-admin`

Rename display labels:

- `Users Admin` or current users menu label becomes `Create Test Users`.
- `Eligibility Codes Admin` or current eligibility menu label becomes `Create Test Eligibility Codes`.
- `Downloads` becomes `Manual Downloads`.
- `Hello AI` becomes `Test AI Network Connectivity`.

Prefer keeping the existing route paths for now unless there is a strong reason to change them. Renaming labels and title bars is lower risk than route churn.

## 3. New Screen: Create Test Contractors

Add a new React screen modelled after the existing users admin pattern:

- Grid screen similar to `app/frontend/components/domains/users-admin/index.tsx`.
- Separate editor screen similar to `app/frontend/components/domains/user-editor/index.tsx`.
- Same general look and feel: thin/blue title bar, searchable grid, details drawer, edit pencil, create button, delete button, pagination.

Suggested routes:

- `/contractors-admin`
- `/contractor-editor?id=<uuid>`
- `/contractor-editor?mode=create`

Suggested labels:

- Grid title: `Create Test Contractors`
- Editor title: `Contractor Editor`
- Create mode heading: `Add Contractor`
- Edit mode heading: `Update Contractor`

## 4. Contractor Fields

Keep the contractor test-data model intentionally minimal. Do not try to recreate full legacy onboarding.

Grid columns:

- `business_name`
- `contractor_number`
- `email`
- `phone_number`
- `city`
- `postal_code`
- actions

Editor fields:

- `business_name`
- `number`
- `email`
- `phone_number`
- `cellphone_number`
- `website`
- `street_address`
- `city`
- `postal_code`
- `onboarded`

Read-only/context fields:

- `id`
- `created_at`
- `updated_at`

Do not include employee invitation, onboarding applications, suspend/remove workflow, or legacy contractor lifecycle controls.

## 5. API Changes

Current claims contractor API:

- `GET /api/claims/admin/contractors`

It is currently read-only. Extend the existing controller rather than creating a separate duplicate controller.

Add routes:

- `GET /api/claims/admin/contractors/:id`
- `POST /api/claims/admin/contractors`
- `PATCH /api/claims/admin/contractors/:id`
- `DELETE /api/claims/admin/contractors/:id`

Controller to update:

- `app/controllers/api/claims/contractors_admin_controller.rb`

Implementation notes:

- Use `public.contractors` through the existing `Contractor` model.
- Allow local/test creation without requiring a legacy onboarding record.
- On create, set `onboarded` from the request, defaulting to `true` if omitted.
- Let the `Contractor` model assign `number` if blank, but allow explicit test numbers.
- Prefer soft restrictions over legacy complexity: deletion can hard-delete only if no claims/session references exist; otherwise return a clear validation error.
- Return JSON in the same `rows/meta` style as users admin for the grid.

## 6. React Wiring

Navigation files likely involved:

- `app/frontend/components/domains/navigation/nav-bar.tsx`
- `app/frontend/components/domains/navigation/index.tsx`
- `app/frontend/components/domains/navigation/sub-nav-bar.tsx`

New screen files:

- `app/frontend/components/domains/contractors-admin/index.tsx`
- `app/frontend/components/domains/contractor-editor/index.tsx`

Rename existing title text:

- `app/frontend/components/domains/hello-ai-admin/index.tsx`
- `app/frontend/components/domains/users-admin/index.tsx`
- `app/frontend/components/domains/eligibilitycodes-admin/index.tsx`
- `app/frontend/components/domains/downloads-admin/index.tsx`

Do not move file folders unless needed. A label-only rename is enough.

## 7. Testing Plan

Test locally first only.

1. API smoke tests:

- List contractors.
- Create a new test contractor.
- Fetch it by id.
- Update business name and address fields.
- Delete a contractor that is not referenced.
- Confirm deletion is blocked or safely handled for a contractor referenced by claims data.

2. React smoke tests:

- Open AI menu.
- Confirm `Create Test Data` section is visible.
- Confirm the four menu items appear under that section.
- Open `Create Test Users`.
- Open `Create Test Eligibility Codes`.
- Open `Manual Downloads`.
- Open `Test AI Network Connectivity`.
- Open `Create Test Contractors`.
- Create and edit a contractor from the new grid/editor.

3. Claims workflow check:

- Open Contractor Draft Simulator.
- Confirm the newly created contractor appears in contractor selection/search.
- Run a small invoice package using the new contractor if practical.
- Confirm invoice grid/reporting displays the contractor name.

## 8. Out Of Scope

- No DDL changes.
- No legacy contractor onboarding rewrite.
- No contractor employee invite flow.
- No production contractor lifecycle management.
- No Gold deployment in this plan.
- No route renames unless we explicitly decide the clarity benefit outweighs route churn.

## 9. Open Implementation Notes

- Decide whether delete should be hard delete, soft delete, or blocked whenever the contractor has any related rows. Recommendation: block delete if referenced by claims data, because test data should not break invoice history.
- Decide whether explicit duplicate `number` values should be blocked. Recommendation: allow the model/database to decide; if there is no uniqueness constraint today, do not invent one in this UI.
- Consider adding a small helper note on the contractor screen: `For local/admin claim test data only. Does not run legacy onboarding.`
