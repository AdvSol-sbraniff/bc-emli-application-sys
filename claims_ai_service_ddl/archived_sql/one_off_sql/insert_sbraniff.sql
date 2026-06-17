begin;

-- Rerunnable local bootstrap for the sbraniff staff account.
--
-- What this script guarantees:
-- - the Energy Savings Program exists
-- - the local sbraniff user exists and is normalized
-- - a preferences row exists for that user
-- - the user has an active ProgramMembership for Energy Savings Program
--
-- Notes:
-- - default role here is regular admin (2)
-- - use set_sbraniff_system_admin.sql afterwards if you want super-admin

do $$
declare
  v_target_email text := 'sbraniff@gov.bc.ca';
  v_target_username text := 'SBRANIFF';
  v_default_user_id uuid := '3e282c6c-56b6-469d-88c5-15c89e0f3e75'::uuid;
  v_default_program_id uuid := 'bbb10000-0000-0000-0000-000000000001'::uuid;
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
    v_program_id := v_default_program_id;

    insert into public.programs (
      id,
      program_name,
      funded_by,
      description_html,
      external_api_state,
      created_at,
      updated_at,
      slug,
      permit_applications_count
    ) values (
      v_program_id,
      'Energy Savings Program',
      'Local bootstrap',
      '<p>Locally bootstrapped program for exercising the legacy contractor and participant flows.</p>',
      'g_off',
      clock_timestamp(),
      clock_timestamp(),
      'energy-savings-program',
      0
    );
  else
    update public.programs
    set program_name = 'Energy Savings Program',
        funded_by = coalesce(funded_by, 'Local bootstrap'),
        description_html = coalesce(
          description_html,
          '<p>Locally bootstrapped program for exercising the legacy contractor and participant flows.</p>'
        ),
        external_api_state = coalesce(external_api_state, 'g_off'),
        slug = 'energy-savings-program',
        updated_at = clock_timestamp()
    where id = v_program_id;
  end if;

  select u.id
    into v_user_id
  from public.users u
  where lower(coalesce(u.email, '')) = lower(v_target_email)
     or upper(coalesce(u.omniauth_username, '')) = upper(v_target_username)
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
      'Stephen',
      'Braniff',
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      0,
      'azureidir',
      '3B9151615CCF4463855CDC7459B0EE6D',
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
        first_name = 'Stephen',
        last_name = 'Braniff',
        role = 2,
        reviewed = true,
        confirmed_at = coalesce(confirmed_at, clock_timestamp()),
        omniauth_provider = 'azureidir',
        omniauth_uid = '3B9151615CCF4463855CDC7459B0EE6D',
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

  update public.program_memberships
  set deactivated_at = null,
      updated_at = clock_timestamp()
  where user_id = v_user_id
    and program_id = v_program_id;

  raise notice 'sbraniff ready. user_id=%, program_id=%', v_user_id, v_program_id;
end $$;

commit;
