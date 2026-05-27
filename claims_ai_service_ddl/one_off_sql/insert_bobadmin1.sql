begin;

-- Rerunnable bootstrap for BobAdmin1 as a regular ESP admin using Business BCeID.
--
-- IMPORTANT:
-- - v_target_omniauth_uid must be the real Keycloak/BCeID user GUID for BobAdmin1.
-- - Do not guess this value. Rails logs it indirectly as the auth uid/provider during
--   callback attempts, and Keycloak/BCeID profile data should also expose it.
-- - If the uid is wrong, the user row will exist but login still will not match it.
--
-- What this script guarantees:
-- - BobAdmin1 exists as an active, confirmed, reviewed regular admin
-- - BobAdmin1 uses Business BCeID authentication
-- - BobAdmin1 has a preferences row
-- - BobAdmin1 has active membership in the Energy Savings Program

do $$
declare
  v_target_email text := 'bobadmin1@gmail.com';
  v_target_username text := 'BobAdmin1';
  v_target_omniauth_uid text := '15208A7CA6FE43C6A78C5053C1E888B8';
  v_default_user_id uuid := 'b0bad001-0000-4000-8000-000000000001'::uuid;
  v_user_id uuid;
  v_program_id uuid;
begin
  if v_target_omniauth_uid = 'REPLACE_WITH_BOBADMIN1_BCEID_USER_GUID' then
    raise exception 'Set v_target_omniauth_uid to BobAdmin1''s real BCeID user GUID before running insert_bobadmin1.sql.';
  end if;

  select p.id
    into v_program_id
  from public.programs p
  where p.slug = 'energy-savings-program'
     or lower(p.program_name) = lower('Energy Savings Program')
  order by p.created_at asc
  limit 1;

  if v_program_id is null then
    raise exception 'Energy Savings Program was not found. Run 3_seed_old_app_minimal.sql first.';
  end if;

  select u.id
    into v_user_id
  from public.users u
  where lower(coalesce(u.email, '')) = lower(v_target_email)
     or lower(coalesce(u.omniauth_username, '')) = lower(v_target_username)
     or (
       coalesce(u.omniauth_provider, '') = 'bceidbusiness'
       and coalesce(u.omniauth_uid, '') = v_target_omniauth_uid
     )
  order by u.created_at asc
  limit 1;

  if v_user_id is null then
    v_user_id := v_default_user_id;

    insert into public.users (
      id,
      email,
      organization,
      certified,
      encrypted_password,
      reset_password_token,
      reset_password_sent_at,
      remember_created_at,
      confirmation_token,
      confirmed_at,
      confirmation_sent_at,
      created_at,
      updated_at,
      role,
      first_name,
      last_name,
      invitation_token,
      invitation_created_at,
      invitation_sent_at,
      invitation_accepted_at,
      invitation_limit,
      invited_by_type,
      invited_by_id,
      invitations_count,
      omniauth_provider,
      omniauth_uid,
      discarded_at,
      sign_in_count,
      current_sign_in_at,
      last_sign_in_at,
      unconfirmed_email,
      omniauth_email,
      omniauth_username,
      reviewed
    ) values (
      v_user_id,
      v_target_email,
      null,
      false,
      '$2a$12$BjkLgl5W0ard7ilDWd0Kw.oGJd.bI73uoB6Jx6hO2UtQXCA1gCji.',
      null,
      null,
      null,
      null,
      clock_timestamp(),
      null,
      clock_timestamp(),
      clock_timestamp(),
      2,
      'Bob',
      'Admin1',
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      0,
      'bceidbusiness',
      v_target_omniauth_uid,
      null,
      0,
      null,
      null,
      null,
      v_target_email,
      v_target_username,
      true
    );
  else
    update public.users
    set email = v_target_email,
        first_name = 'Bob',
        last_name = 'Admin1',
        role = 2,
        reviewed = true,
        confirmed_at = coalesce(confirmed_at, clock_timestamp()),
        omniauth_provider = 'bceidbusiness',
        omniauth_uid = v_target_omniauth_uid,
        omniauth_email = v_target_email,
        omniauth_username = v_target_username,
        discarded_at = null,
        updated_at = clock_timestamp()
    where id = v_user_id;
  end if;

  insert into public.preferences (
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
  )
  select
    v_user_id,
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
    clock_timestamp(),
    clock_timestamp()
  where not exists (
    select 1
    from public.preferences p
    where p.user_id = v_user_id
  );

  update public.program_memberships
  set deactivated_at = null,
      updated_at = clock_timestamp()
  where user_id = v_user_id
    and program_id = v_program_id;

  insert into public.program_memberships (
    user_id,
    program_id,
    deactivated_at,
    created_at,
    updated_at
  )
  select
    v_user_id,
    v_program_id,
    null,
    clock_timestamp(),
    clock_timestamp()
  where not exists (
    select 1
    from public.program_memberships pm
    where pm.user_id = v_user_id
      and pm.program_id = v_program_id
  );
end $$;

commit;
