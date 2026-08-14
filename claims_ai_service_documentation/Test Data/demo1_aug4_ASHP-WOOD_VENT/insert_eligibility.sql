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
  WHERE lower(trim(first_name)) = 'john'
    AND lower(trim(last_name)) = 'maschak';

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
    'de4f0001-0000-4000-8000-000000000001',
    participant_id,
    'ESP1-NatGas7b23011e',
    1,
    TIMESTAMP '2026-05-01 00:00:00',
    TIMESTAMP '2026-05-14 00:00:00',
    TIMESTAMP '2026-11-25 23:59:59',
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

  RAISE NOTICE 'Eligibility ESP1-NatGas7b23011e is ready for John Maschak.';
EXCEPTION
  WHEN no_data_found THEN
    RAISE EXCEPTION 'Expected participant John Maschak was not found in public.users.';
  WHEN too_many_rows THEN
    RAISE EXCEPTION 'More than one John Maschak exists in public.users; eligibility was not changed.';
END
$insert$;
