BEGIN;

-- ============================================================
-- SEED IDs (fixed, so script is repeatable)
-- ============================================================

-- Users
--  1111... = admin
--  2222... = contractor contact
--  3333... = participant
-- Contractor
--  aaaa... = Acme Windows

-- ============================================================
-- DELETE ONLY WHAT WE'RE ABOUT TO INSERT (NO CASCADE)
-- Delete dependents first, limited to these user IDs.
-- ============================================================

-- Preferences references users(id)
DELETE FROM public.preferences
WHERE user_id IN (
  '11111111-1111-1111-1111-111111111111',
  '22222222-2222-2222-2222-222222222222',
  '33333333-3333-3333-3333-333333333333'
);

-- Contractors references users(id) via contact_id, and we also delete by contractor id.
DELETE FROM public.contractors
WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
   OR contact_id IN (
     '11111111-1111-1111-1111-111111111111',
     '22222222-2222-2222-2222-222222222222',
     '33333333-3333-3333-3333-333333333333'
   );

-- Finally, delete just the seed users
DELETE FROM public.users
WHERE id IN (
  '11111111-1111-1111-1111-111111111111',
  '22222222-2222-2222-2222-222222222222',
  '33333333-3333-3333-3333-333333333333'
);

-- ============================================================
-- INSERT USERS
-- ============================================================

INSERT INTO public.users (
  id,
  email,
  organization,
  role,
  first_name,
  last_name,
  encrypted_password,
  certified,
  reviewed,
  created_at,
  updated_at
) VALUES
  ('11111111-1111-1111-1111-111111111111', 'admin@example.com', 'Program Admin', 0,
   'Admin', 'User', '', false, false, now(), now()),

  ('22222222-2222-2222-2222-222222222222', 'contractor.contact@example.com', 'Acme Windows Ltd', 0,
   'Casey', 'Contractor', '', true, false, now(), now()),

  ('33333333-3333-3333-3333-333333333333', 'participant@example.com', 'Homeowner', 0,
   'Pat', 'Participant', '', false, false, now(), now());

-- ============================================================
-- INSERT CONTRACTORS
-- ============================================================

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
) VALUES
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
   '22222222-2222-2222-2222-222222222222',
   'Centra Windows Ltd',
   'https://centrawindows.example',
   '250-555-0100',
   'office@acmewindows.example',
   true,
   'C-0001',
   '250-555-0199',
   '123 Main St',
   'Calgary',
   'T2C 2X7',
   now(),
   now());

-- ============================================================
-- INSERT USERS_ELIGIBILITYCODES (claims)
-- ============================================================

-- cleanup (repeatable)
DELETE FROM claims.users_eligibilitycodes
WHERE eligibility_code IN ('ESP1-136a31ba')
   OR user_id = '33333333-3333-3333-3333-333333333333';

INSERT INTO claims.users_eligibilitycodes (
  id,
  user_id,
  eligibility_code,
  applied_at,
  approved_at,
  expires_at,
  created_at,
  updated_at
) VALUES (
  'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', -- fixed ID for repeatability
  '33333333-3333-3333-3333-333333333333', -- participant user
  'ESP1-136a31ba',
  now() - interval '10 days',
  now() - interval '7 days',
  now() + interval '173 days', -- > applied_at (passes CHECK)
  now(),
  now()
);


COMMIT;

