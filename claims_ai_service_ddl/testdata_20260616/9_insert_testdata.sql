BEGIN;

-- Optional local test data for exercising real source PDFs after a claims
-- schema rebuild. This script is intentionally rerunnable and should be run
-- after the normal claims rebuild sequence.
--
-- Source PDF:
-- claims_ai_service_documentation/pdf test files/real_source_pdfs/Invoice 2 - Insulation and Health & Safety.pdf
--
-- Visible invoice facts used here:
-- - homeowner: Sue McManus
-- - installation address: 529 Asteria Place, Nanaimo, BC V9R 7C3
-- - eligibility code: ESP1-Electric9eae3783

DO $$
DECLARE
  v_user_id uuid;
  v_default_user_id uuid := '9d4b8c64-2f15-42f8-9f20-2a8f1c0a0002'::uuid;
  v_email text := 'sue.mcmanus.invoice2@example.test';
BEGIN
  SELECT u.id
    INTO v_user_id
  FROM public.users u
  WHERE u.id = v_default_user_id
     OR lower(coalesce(u.email, '')) = lower(v_email)
  ORDER BY
    CASE WHEN u.id = v_default_user_id THEN 0 ELSE 1 END,
    u.created_at ASC
  LIMIT 1;

  IF v_user_id IS NULL THEN
    v_user_id := v_default_user_id;

    INSERT INTO public.users (
      id,
      email,
      organization,
      certified,
      encrypted_password,
      confirmed_at,
      created_at,
      updated_at,
      role,
      first_name,
      last_name,
      invitations_count,
      sign_in_count,
      omniauth_email,
      reviewed
    ) VALUES (
      v_user_id,
      v_email,
      'Local claims AI test data',
      false,
      '',
      clock_timestamp(),
      clock_timestamp(),
      clock_timestamp(),
      0,
      'Sue',
      'McManus',
      0,
      0,
      v_email,
      true
    );
  ELSE
    UPDATE public.users
    SET email = v_email,
        organization = 'Local claims AI test data',
        first_name = 'Sue',
        last_name = 'McManus',
        role = 0,
        reviewed = true,
        confirmed_at = COALESCE(confirmed_at, clock_timestamp()),
        discarded_at = NULL,
        updated_at = clock_timestamp()
    WHERE id = v_user_id;
  END IF;

  INSERT INTO public.preferences (
    user_id,
    created_at,
    updated_at
  )
  SELECT
    v_user_id,
    clock_timestamp(),
    clock_timestamp()
  WHERE NOT EXISTS (
    SELECT 1
    FROM public.preferences p
    WHERE p.user_id = v_user_id
  );

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
    '4a7b3f7a-8d20-4fb2-b7ad-000000000002'::uuid,
    v_user_id,
    'ESP1-Electric9eae3783',
    1,
    TIMESTAMP '2025-01-15 00:00:00',
    TIMESTAMP '2025-01-20 00:00:00',
    TIMESTAMP '2026-02-04 23:59:59',
    clock_timestamp(),
    clock_timestamp()
  )
  ON CONFLICT (eligibility_code) DO UPDATE SET
    user_id = EXCLUDED.user_id,
    income_level = EXCLUDED.income_level,
    applied_at = EXCLUDED.applied_at,
    approved_at = EXCLUDED.approved_at,
    expires_at = EXCLUDED.expires_at,
    updated_at = clock_timestamp();
END $$;

COMMIT;
