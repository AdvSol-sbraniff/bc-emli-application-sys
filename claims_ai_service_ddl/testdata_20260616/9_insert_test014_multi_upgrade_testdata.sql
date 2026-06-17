BEGIN;

-- Optional local test data for the synthetic Heat Pump test014 multi-upgrade
-- package. This script is intentionally rerunnable and should be run after
-- the normal claims rebuild sequence when testing:
--
-- claims_ai_service_documentation/Test Data/Heat Pump/test014/
--   Heat Pump invoice - fake multi upgrade.pdf
--
-- Visible invoice facts used here:
-- - contractor: Island Eco Energy Heating and Cooling
-- - participant: Lucy Hemphill
-- - eligibility code: ESP1-Wood5cbd76ab

DO $$
DECLARE
  v_participant_user_id uuid;
  v_participant_default_user_id uuid := 'fd8cee16-52de-41ec-aa89-60ea4fb39fd4'::uuid;
  v_participant_email text := 'lucyhemphill7@gmail.com';

  v_contractor_contact_user_id uuid;
  v_contractor_contact_default_user_id uuid := 'fd8cee16-52de-41ec-aa89-60ea4fb39014'::uuid;
  v_contractor_contact_email text := 'lhattor@live.com';

  v_contractor_id uuid;
  v_contractor_default_id uuid := 'fd8cee16-52de-41ec-aa89-60ea4fb3c014'::uuid;
  v_contractor_business_name text := 'Island Eco Energy Heating and Cooling';
BEGIN
  SELECT u.id
    INTO v_participant_user_id
  FROM public.users u
  WHERE u.id = v_participant_default_user_id
     OR lower(coalesce(u.email, '')) = lower(v_participant_email)
     OR (
       lower(coalesce(u.first_name, '')) = 'lucy'
       AND lower(coalesce(u.last_name, '')) = 'hemphill'
     )
  ORDER BY
    CASE WHEN u.id = v_participant_default_user_id THEN 0 ELSE 1 END,
    u.created_at ASC
  LIMIT 1;

  IF v_participant_user_id IS NULL THEN
    v_participant_user_id := v_participant_default_user_id;

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
      v_participant_user_id,
      v_participant_email,
      'Local claims AI test data',
      false,
      '',
      clock_timestamp(),
      clock_timestamp(),
      clock_timestamp(),
      0,
      'Lucy',
      'Hemphill',
      0,
      0,
      v_participant_email,
      true
    );
  ELSE
    UPDATE public.users
    SET email = v_participant_email,
        organization = 'Local claims AI test data',
        first_name = 'Lucy',
        last_name = 'Hemphill',
        role = 0,
        reviewed = true,
        confirmed_at = COALESCE(confirmed_at, clock_timestamp()),
        discarded_at = NULL,
        updated_at = clock_timestamp()
    WHERE id = v_participant_user_id;
  END IF;

  INSERT INTO public.preferences (
    user_id,
    created_at,
    updated_at
  )
  SELECT
    v_participant_user_id,
    clock_timestamp(),
    clock_timestamp()
  WHERE NOT EXISTS (
    SELECT 1
    FROM public.preferences p
    WHERE p.user_id = v_participant_user_id
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
    'fd8cee16-52de-41ec-aa89-60ea4fbe0014'::uuid,
    v_participant_user_id,
    'ESP1-Wood5cbd76ab',
    1,
    TIMESTAMP '2025-01-01 08:00:00',
    TIMESTAMP '2025-01-10 08:00:00',
    TIMESTAMP '2026-08-11 07:00:00',
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

  SELECT u.id
    INTO v_contractor_contact_user_id
  FROM public.users u
  WHERE u.id = v_contractor_contact_default_user_id
     OR lower(coalesce(u.email, '')) = lower(v_contractor_contact_email)
  ORDER BY
    CASE WHEN u.id = v_contractor_contact_default_user_id THEN 0 ELSE 1 END,
    u.created_at ASC
  LIMIT 1;

  IF v_contractor_contact_user_id IS NULL THEN
    v_contractor_contact_user_id := v_contractor_contact_default_user_id;

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
      v_contractor_contact_user_id,
      v_contractor_contact_email,
      'Island Eco Energy Heating and Cooling',
      false,
      '',
      clock_timestamp(),
      clock_timestamp(),
      clock_timestamp(),
      0,
      'Island Eco',
      'Contact',
      0,
      0,
      v_contractor_contact_email,
      true
    );
  ELSE
    UPDATE public.users
    SET email = v_contractor_contact_email,
        organization = 'Island Eco Energy Heating and Cooling',
        first_name = 'Island Eco',
        last_name = 'Contact',
        role = 0,
        reviewed = true,
        confirmed_at = COALESCE(confirmed_at, clock_timestamp()),
        discarded_at = NULL,
        updated_at = clock_timestamp()
    WHERE id = v_contractor_contact_user_id;
  END IF;

  INSERT INTO public.preferences (
    user_id,
    created_at,
    updated_at
  )
  SELECT
    v_contractor_contact_user_id,
    clock_timestamp(),
    clock_timestamp()
  WHERE NOT EXISTS (
    SELECT 1
    FROM public.preferences p
    WHERE p.user_id = v_contractor_contact_user_id
  );

  SELECT c.id
    INTO v_contractor_id
  FROM public.contractors c
  WHERE c.id = v_contractor_default_id
     OR lower(coalesce(c.business_name, '')) = lower(v_contractor_business_name)
  ORDER BY
    CASE WHEN c.id = v_contractor_default_id THEN 0 ELSE 1 END,
    c.created_at ASC
  LIMIT 1;

  IF v_contractor_id IS NULL THEN
    v_contractor_id := v_contractor_default_id;

    INSERT INTO public.contractors (
      id,
      contact_id,
      business_name,
      website,
      phone_number,
      email,
      onboarded,
      number,
      cellphone_number,
      street_address,
      city,
      postal_code,
      created_at,
      updated_at
    ) VALUES (
      v_contractor_id,
      v_contractor_contact_user_id,
      v_contractor_business_name,
      'https://www.islandecoenergy.com',
      '250-902-0111',
      v_contractor_contact_email,
      true,
      'TEST014-ISLAND-ECO',
      '250-902-8257',
      '5475 Hardy Bay Road PO Box 5248',
      'Port Hardy',
      'V0N 2P0',
      clock_timestamp(),
      clock_timestamp()
    );
  ELSE
    UPDATE public.contractors
    SET contact_id = v_contractor_contact_user_id,
        business_name = v_contractor_business_name,
        website = 'https://www.islandecoenergy.com',
        phone_number = '250-902-0111',
        email = v_contractor_contact_email,
        onboarded = true,
        number = 'TEST014-ISLAND-ECO',
        cellphone_number = '250-902-8257',
        street_address = '5475 Hardy Bay Road PO Box 5248',
        city = 'Port Hardy',
        postal_code = 'V0N 2P0',
        updated_at = clock_timestamp()
    WHERE id = v_contractor_id;
  END IF;
END $$;

COMMIT;
