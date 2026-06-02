begin;
DELETE FROM claims.users_eligibilitycodes;



-- ============================================================
-- INSERT USERS_ELIGIBILITYCODES (claims)
-- ============================================================

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
  'aaaaaaaa-0011-aaaa-aaaa-aaaaaaaaaaaa', -- fixed ID for repeatability
  'aaaaaaaa-0001-aaaa-aaaa-aaaaaaaaaaaa', -- participant user
  'ESP1-7a1899b2',
  1,
  now() - interval '10 days',
  now() - interval '7 days',
  now() + interval '173 days', -- > applied_at (passes CHECK)
  now(),
  now()
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
  'aaaaaaaa-0012-aaaa-aaaa-aaaaaaaaaaaa', -- fixed ID for repeatability
  'aaaaaaaa-0002-aaaa-aaaa-aaaaaaaaaaaa', -- participant user
  'ESP1-136a31ba',
  1,
  now() - interval '10 days',
  now() - interval '7 days',
  now() + interval '173 days', -- > applied_at (passes CHECK)
  now(),
  now()
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
  'aaaaaaaa-0013-aaaa-aaaa-aaaaaaaaaaaa', -- fixed ID for repeatability
  'aaaaaaaa-0003-aaaa-aaaa-aaaaaaaaaaaa', -- participant user
  'ESP2-7f5e4588',
  2,
  now() - interval '10 days',
  now() - interval '7 days',
  now() + interval '173 days', -- > applied_at (passes CHECK)
  now(),
  now()
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
  'aaaaaaaa-0014-aaaa-aaaa-aaaaaaaaaaaa', -- fixed ID for repeatability
  'aaaaaaaa-0004-aaaa-aaaa-aaaaaaaaaaaa', -- participant user
  'ESP2-170deadc',
  2,
  now() - interval '10 days',
  now() - interval '7 days',
  now() + interval '173 days', -- > applied_at (passes CHECK)
  now(),
  now()
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
  'aaaaaaaa-0015-aaaa-aaaa-aaaaaaaaaaaa', -- fixed ID for repeatability
  'aaaaaaaa-0005-aaaa-aaaa-aaaaaaaaaaaa', -- participant user
  'ESP1-32ac2f4b',
  1,
  now() - interval '10 days',
  now() - interval '7 days',
  now() + interval '173 days', -- > applied_at (passes CHECK)
  now(),
  now()
);

COMMIT;
