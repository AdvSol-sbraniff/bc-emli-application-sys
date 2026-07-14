BEGIN;

WITH code_located_fields_seed (
  id,
  code_field_key,
  contractor_display_name,
  description,
  enabled,
  created_at,
  updated_at
) AS (
  VALUES
  (
    '590f2f3a-3e23-449a-a7d4-2f35c3d54001'::uuid,
    'invoices.submitted_at',
    'Invoice submission date',
    'Carries the invoice submission timestamp from claims.invoices into the runtime code-located-field output and GenAI context window.',
    true,
    TIMESTAMP '2026-05-26 00:00:00',
    NOW()
  ),
  (
    '590f2f3a-3e23-449a-a7d4-2f35c3d54002'::uuid,
    'contractors.business_name',
    'Contractor business name',
    'Carries the contractor business name from the contractor record into the runtime code-located-field output and GenAI context window.',
    true,
    TIMESTAMP '2026-05-26 00:00:00',
    NOW()
  ),
  (
    '590f2f3a-3e23-449a-a7d4-2f35c3d54003'::uuid,
    'contractors.address',
    'Contractor address',
    'Carries the contractor mailing/business address assembled from the contractor record into the runtime code-located-field output and GenAI context window.',
    true,
    TIMESTAMP '2026-05-26 00:00:00',
    NOW()
  ),
  (
    '590f2f3a-3e23-449a-a7d4-2f35c3d54004'::uuid,
    'users_eligibilitycodes.eligibility_code',
    'Eligibility code',
    'Carries the matched participant eligibility code from the legacy eligibility-code record into the runtime code-located-field output and GenAI context window.',
    true,
    TIMESTAMP '2026-05-26 00:00:00',
    NOW()
  ),
  (
    '590f2f3a-3e23-449a-a7d4-2f35c3d54005'::uuid,
    'users_eligibilitycodes.income_level',
    'Program income level',
    'Carries the stored program income-level value from the matched eligibility-code record into the runtime code-located-field output and GenAI context window.',
    true,
    TIMESTAMP '2026-05-26 00:00:00',
    NOW()
  ),
  (
    '590f2f3a-3e23-449a-a7d4-2f35c3d54006'::uuid,
    'users_eligibilitycodes.approved_at',
    'Eligibility approval date',
    'Carries the eligibility-code approval date from the matched eligibility-code record into the runtime code-located-field output and GenAI context window.',
    true,
    TIMESTAMP '2026-05-26 00:00:00',
    NOW()
  ),
  (
    '590f2f3a-3e23-449a-a7d4-2f35c3d54007'::uuid,
    'users_eligibilitycodes.expires_at',
    'Eligibility expiry date',
    'Carries the eligibility-code expiry date from the matched eligibility-code record into the runtime code-located-field output and GenAI context window.',
    true,
    TIMESTAMP '2026-05-26 00:00:00',
    NOW()
  ),
  (
    '590f2f3a-3e23-449a-a7d4-2f35c3d54008'::uuid,
    'users.participant_name',
    'Participant name',
    'Carries the participant display name assembled from the matched user record into the runtime code-located-field output and GenAI context window.',
    true,
    TIMESTAMP '2026-05-26 00:00:00',
    NOW()
  )
)
INSERT INTO claims.code_located_fields (
  id,
  code_field_key,
  contractor_display_name,
  description,
  enabled,
  created_at,
  updated_at
)
SELECT
  id,
  code_field_key,
  contractor_display_name,
  description,
  enabled,
  created_at,
  updated_at
FROM code_located_fields_seed
ON CONFLICT (code_field_key) DO UPDATE SET
  contractor_display_name = EXCLUDED.contractor_display_name,
  description = EXCLUDED.description,
  updated_at = NOW();

COMMIT;
