\set ON_ERROR_STOP on

-- Recreates the eligibility record required by this demo after the claims
-- schema is rebuilt. Safe to run repeatedly.
DO $insert$
DECLARE
  participant_id uuid;
BEGIN
  SELECT id
  INTO STRICT participant_id
  FROM public.users
  WHERE lower(trim(first_name)) = 'xie'
    AND lower(trim(last_name)) = 'yi';

  INSERT INTO claims.users_eligibilitycodes (
    id,
    user_id,
    eligibility_code,
    income_level,
    applied_at,
    approved_at,
    expires_at,
    created_at,
    updated_at
  ) VALUES (
    'de4f0003-0000-4000-8000-000000000003',
    participant_id,
    'ESP3-725eb221',
    3,
    TIMESTAMP '2026-05-01 00:00:00',
    TIMESTAMP '2026-05-21 00:00:00',
    TIMESTAMP '2026-12-30 23:59:59',
    NOW(),
    NOW()
  )
  ON CONFLICT (eligibility_code) DO UPDATE SET
    user_id = EXCLUDED.user_id,
    income_level = EXCLUDED.income_level,
    applied_at = EXCLUDED.applied_at,
    approved_at = EXCLUDED.approved_at,
    expires_at = EXCLUDED.expires_at,
    updated_at = NOW();

  RAISE NOTICE 'Eligibility ESP3-725eb221 is ready for XIE YI.';
EXCEPTION
  WHEN no_data_found THEN
    RAISE EXCEPTION 'Expected participant XIE YI was not found in public.users.';
  WHEN too_many_rows THEN
    RAISE EXCEPTION 'More than one XIE YI exists in public.users; eligibility was not changed.';
END
$insert$;
