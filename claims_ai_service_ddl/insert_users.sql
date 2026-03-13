begin;
DELETE FROM public.preferences;
DELETE FROM public.contractors;
DELETE FROM public.users;

-- ============================================================
-- INSERT participant USERS
-- ============================================================

/*
users.role integer ? 
0 = participant (also the default)
1 = admin_manager
2 = admin
3 = system_admin
4 = regional_review_manager (comment says unused / legacy tests)
5 = participant_support_rep
6 = contractor
7 = unassigned
*/

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
  ('aaaaaaaa-0001-aaaa-aaaa-aaaaaaaaaaaa', 'brown@example.com', 'na', 0,
   'Doreen', 'Visia', '', false, false, now(), now()),

  ('aaaaaaaa-0002-aaaa-aaaa-aaaaaaaaaaaa', 'centra@example.com', 'na', 0,
   'Jesse', 'Eby', '', true, false, now(), now()),

  ('aaaaaaaa-0003-aaaa-aaaa-aaaaaaaaaaaa', 'htr@example.com', 'na', 0,
   'Maria', 'Zumurraga', '', true, false, now(), now()),
   
  ('aaaaaaaa-0004-aaaa-aaaa-aaaaaaaaaaaa', 'nagy@example.com', 'na', 0,
   'Craig', 'Somers', '', true, false, now(), now()),

  ('aaaaaaaa-0005-aaaa-aaaa-aaaaaaaaaaaa', 'van@example.com', 'na', 0,
   'Lori', 'Nakashima', '', false, false, now(), now());


-- ============================================================
-- INSERT preferences
-- ============================================================

INSERT INTO public.preferences (
  user_id,

  enable_in_app_new_template_version_publish_notification,
  enable_email_new_template_version_publish_notification,
  enable_in_app_customization_update_notification,
  enable_email_customization_update_notification,

  enable_email_application_submission_notification,
  enable_in_app_application_submission_notification,
  enable_email_application_view_notification,
  enable_in_app_application_view_notification,
  enable_email_application_revisions_request_notification,
  enable_in_app_application_revisions_request_notification,

  enable_in_app_collaboration_notification,
  enable_email_collaboration_notification,
  enable_in_app_integration_mapping_notification,
  enable_email_integration_mapping_notification,

  created_at,
  updated_at
) VALUES (
  'aaaaaaaa-0001-aaaa-aaaa-aaaaaaaaaaaa',

  true,
  true,
  true,
  true,

  true,
  true,
  true,
  true,
  true,
  true,

  true,
  true,
  true,
  true,

  now(),
  now()
);



INSERT INTO public.preferences (
  user_id,

  enable_in_app_new_template_version_publish_notification,
  enable_email_new_template_version_publish_notification,
  enable_in_app_customization_update_notification,
  enable_email_customization_update_notification,

  enable_email_application_submission_notification,
  enable_in_app_application_submission_notification,
  enable_email_application_view_notification,
  enable_in_app_application_view_notification,
  enable_email_application_revisions_request_notification,
  enable_in_app_application_revisions_request_notification,

  enable_in_app_collaboration_notification,
  enable_email_collaboration_notification,
  enable_in_app_integration_mapping_notification,
  enable_email_integration_mapping_notification,

  created_at,
  updated_at
) VALUES (
  'aaaaaaaa-0002-aaaa-aaaa-aaaaaaaaaaaa',

  true,
  true,
  true,
  true,

  true,
  true,
  true,
  true,
  true,
  true,

  true,
  true,
  true,
  true,

  now(),
  now()
);



INSERT INTO public.preferences (
  user_id,

  enable_in_app_new_template_version_publish_notification,
  enable_email_new_template_version_publish_notification,
  enable_in_app_customization_update_notification,
  enable_email_customization_update_notification,

  enable_email_application_submission_notification,
  enable_in_app_application_submission_notification,
  enable_email_application_view_notification,
  enable_in_app_application_view_notification,
  enable_email_application_revisions_request_notification,
  enable_in_app_application_revisions_request_notification,

  enable_in_app_collaboration_notification,
  enable_email_collaboration_notification,
  enable_in_app_integration_mapping_notification,
  enable_email_integration_mapping_notification,

  created_at,
  updated_at
) VALUES (
  'aaaaaaaa-0003-aaaa-aaaa-aaaaaaaaaaaa',

  true,
  true,
  true,
  true,

  true,
  true,
  true,
  true,
  true,
  true,

  true,
  true,
  true,
  true,

  now(),
  now()
);



INSERT INTO public.preferences (
  user_id,

  enable_in_app_new_template_version_publish_notification,
  enable_email_new_template_version_publish_notification,
  enable_in_app_customization_update_notification,
  enable_email_customization_update_notification,

  enable_email_application_submission_notification,
  enable_in_app_application_submission_notification,
  enable_email_application_view_notification,
  enable_in_app_application_view_notification,
  enable_email_application_revisions_request_notification,
  enable_in_app_application_revisions_request_notification,

  enable_in_app_collaboration_notification,
  enable_email_collaboration_notification,
  enable_in_app_integration_mapping_notification,
  enable_email_integration_mapping_notification,

  created_at,
  updated_at
) VALUES (
  'aaaaaaaa-0004-aaaa-aaaa-aaaaaaaaaaaa',

  true,
  true,
  true,
  true,

  true,
  true,
  true,
  true,
  true,
  true,

  true,
  true,
  true,
  true,

  now(),
  now()
);


INSERT INTO public.preferences (
  user_id,

  enable_in_app_new_template_version_publish_notification,
  enable_email_new_template_version_publish_notification,
  enable_in_app_customization_update_notification,
  enable_email_customization_update_notification,

  enable_email_application_submission_notification,
  enable_in_app_application_submission_notification,
  enable_email_application_view_notification,
  enable_in_app_application_view_notification,
  enable_email_application_revisions_request_notification,
  enable_in_app_application_revisions_request_notification,

  enable_in_app_collaboration_notification,
  enable_email_collaboration_notification,
  enable_in_app_integration_mapping_notification,
  enable_email_integration_mapping_notification,

  created_at,
  updated_at
) VALUES (
  'aaaaaaaa-0005-aaaa-aaaa-aaaaaaaaaaaa',

  true,
  true,
  true,
  true,

  true,
  true,
  true,
  true,
  true,
  true,

  true,
  true,
  true,
  true,

  now(),
  now()
);


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
  ('aaaaaaaa-0006-aaaa-aaaa-aaaaaaaaaaaa',
   null,
   'Brown',
   'https://windows.example',
   '250-555-0100',
   'brown@brown.com',
   true,
   'C-0001',
   '250-555-0199',
   '422 Walker Ave',
   'Ladysmith',
   'T2C 2X7',
   now(),
   now());

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
  ('aaaaaaaa-0007-aaaa-aaaa-aaaaaaaaaaaa',
   null,
   'Centra Windows Ltd',
   'https://centrawindows.example',
   '250-555-0100',
   'office@acmewindows.example',
   true,
   'C-0001',
   '250-555-0199',
   '4795 102 ave se',
   'Calgary',
   'T2C 2X7',
   now(),
   now());

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
  ('aaaaaaaa-0008-aaaa-aaaa-aaaaaaaaaaaa',
   null,
   'HTR',
   'https://htr.example',
   '250-555-0100',
   'office@htr.com',
   true,
   'C-0001',
   '250-555-0199',
   '202 balmoral place',
   'port moody',
   'T2C 2X7',
   now(),
   now());

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
  ('aaaaaaaa-0009-aaaa-aaaa-aaaaaaaaaaaa',
   null,
   'nagy@example Windows Ltd',
   'https://nagywindows.example',
   '250-555-0100',
   'nagy@acmewindows.example',
   true,
   'C-0001',
   '250-555-0199',
   '1718 Byland',
   'Kelowna',
   'T2C 2X7',
   now(),
   now());

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
  ('aaaaaaaa-0010-aaaa-aaaa-aaaaaaaaaaaa',
   null,
   'Van isl Windows Ltd',
   'https://vanwindows.example',
   '250-555-0100',
   'office@vanacmewindows.example',
   true,
   'C-0001',
   '250-555-0199',
   '404 hyillside',
   'victoria',
   'T2C 2X7',
   now(),
   now());



COMMIT;