BEGIN;

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
  'aaaaaaaa-0011-aaaa-aaaa-aaaaaaaaaaaa',
  'aaaaaaaa-0001-aaaa-aaaa-aaaaaaaaaaaa',
  'ESP1-7a1899b2',
  1,
  TIMESTAMP '2026-07-24 00:00:00',
  TIMESTAMP '2026-07-29 00:00:00',
  TIMESTAMP '2027-01-25 23:59:59',
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

COMMIT;
