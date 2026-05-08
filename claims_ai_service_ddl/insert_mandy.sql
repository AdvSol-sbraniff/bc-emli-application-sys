begin;

-- Rerunnable local bootstrap for Mandy Leung as a regular ESP admin.
--
-- Source reference from Silver dev:
-- - email: mandy.2.leung@gov.bc.ca
-- - role there was system_admin (3), but this local helper intentionally
--   normalizes Mandy to regular admin (2).
--
-- What this script guarantees:
-- - Mandy exists as an active, confirmed, reviewed user
-- - Mandy has the Azure IDIR omniauth identity from Silver
-- - Mandy has a preferences row
-- - Mandy has active membership in the local Energy Savings Program

do $$
declare
  v_target_email text := 'mandy.2.leung@gov.bc.ca';
  v_target_username text := 'MALEUNG2';
  v_target_omniauth_uid text := '6433326627A1417B8F77D93F5ECA5316';
  v_default_user_id uuid := 'df37da88-3f53-44f7-94af-5d194a7282ee'::uuid;
  v_user_id uuid;
  v_program_id uuid;
begin
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
     or upper(coalesce(u.omniauth_username, '')) = upper(v_target_username)
     or (
       coalesce(u.omniauth_provider, '') = 'azureidir'
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
      '$2a$12$j3EuZ3rPi4Los7s2YC4AW.B4TvIrl46btWRZ9ytgPJL8YPXhKwz.2',
      null,
      null,
      null,
      null,
      clock_timestamp(),
      null,
      clock_timestamp(),
      clock_timestamp(),
      2,
      'Mandy',
      'Leung',
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      0,
      'azureidir',
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
        first_name = 'Mandy',
        last_name = 'Leung',
        role = 2,
        reviewed = true,
        confirmed_at = coalesce(confirmed_at, clock_timestamp()),
        omniauth_provider = 'azureidir',
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
