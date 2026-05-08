begin;

-- Minimal local bootstrap for the pre-AI app flow.
-- This script is intentionally rerunnable:
-- - permit classifications are upserted by unique code
-- - the program is found by slug/name and normalized
-- - requirement templates are found by program + classifications
-- - a published template version is created or refreshed for each template
--
-- Suggested run command from WSL:
--   PGPASSWORD=password psql -h 127.0.0.1 -U postgres -d app_development -f claims_ai_service_ddl/3_seed_old_app_minimal.sql

merge into public.permit_classifications as target
using (
  values
    ('bbb00000-0000-0000-0000-000000000000'::uuid, 'Low residential', 'PermitType', '', true, 0, null::uuid),
    ('bbb00000-0000-0000-0000-000000000004'::uuid, 'Addition / alteration / renovation', 'Activity', '', true, 4, null::uuid),
    ('bbb00000-0000-0000-0000-000000000007'::uuid, 'Internal', 'AudienceType', '', true, 7, null::uuid),
    ('bbb00000-0000-0000-0000-000000000008'::uuid, 'External', 'AudienceType', '', true, 8, null::uuid),
    ('bbb00000-0000-0000-0000-000000000009'::uuid, 'Participant', 'UserGroupType', '', true, 9, null::uuid),
    ('bbb00000-0000-0000-0000-000000000010'::uuid, 'Contractor', 'UserGroupType', '', true, 10, null::uuid),
    ('bbb00000-0000-0000-0000-000000000011'::uuid, 'Application', 'SubmissionType', '', true, 11, null::uuid),
    ('bbb00000-0000-0000-0000-000000000012'::uuid, 'Onboarding', 'SubmissionType', '', true, 12, null::uuid),
    ('bbb00000-0000-0000-0000-000000000013'::uuid, 'Support Request', 'SubmissionType', '', true, 13, null::uuid),
    ('bbb00000-0000-0000-0000-000000000014'::uuid, 'Invoice', 'SubmissionType', '', true, 14, null::uuid)
) as source(id, name, type, description, enabled, code, parent_id)
on target.code = source.code
when matched then update set
  name = source.name,
  type = source.type,
  description = source.description,
  enabled = source.enabled,
  parent_id = source.parent_id,
  updated_at = clock_timestamp()
when not matched then insert (
  id,
  name,
  type,
  created_at,
  updated_at,
  description,
  enabled,
  code,
  parent_id
) values (
  source.id,
  source.name,
  source.type,
  clock_timestamp(),
  clock_timestamp(),
  source.description,
  source.enabled,
  source.code,
  source.parent_id
);

with invoice_parent as (
  select id
  from public.permit_classifications
  where code = 14
),
source_rows as (
  select
    v.id,
    v.name,
    'SubmissionVariant'::varchar as type,
    ''::varchar as description,
    true as enabled,
    v.code,
    invoice_parent.id as parent_id
  from invoice_parent
  cross join (
    values
      ('bbb00000-0000-0000-0000-000000000015'::uuid, 'Heat pump (space heating)', 15),
      ('bbb00000-0000-0000-0000-000000000016'::uuid, 'Heat pump water heater (including combined)', 16),
      ('bbb00000-0000-0000-0000-000000000017'::uuid, 'Insulation', 17),
      ('bbb00000-0000-0000-0000-000000000018'::uuid, 'Windows and doors', 18),
      ('bbb00000-0000-0000-0000-000000000019'::uuid, 'Ventilation', 19),
      ('bbb00000-0000-0000-0000-000000000020'::uuid, 'Electrical service upgrade', 20),
      ('bbb00000-0000-0000-0000-000000000021'::uuid, 'Health and safety remediation', 21)
  ) as v(id, name, code)
)
merge into public.permit_classifications as target
using source_rows as source
on target.code = source.code
when matched then update set
  name = source.name,
  type = source.type,
  description = source.description,
  enabled = source.enabled,
  parent_id = source.parent_id,
  updated_at = clock_timestamp()
when not matched then insert (
  id,
  name,
  type,
  created_at,
  updated_at,
  description,
  enabled,
  code,
  parent_id
) values (
  source.id,
  source.name,
  source.type,
  clock_timestamp(),
  clock_timestamp(),
  source.description,
  source.enabled,
  source.code,
  source.parent_id
);

-- Keep the singleton site configuration and revision reasons reasonably close to
-- the richer Silver environment, while preserving the local onboarding-specific
-- extra revision reason added by newer migrations.
do $$
declare
  v_site_configuration_id uuid;
begin
  select sc.id
    into v_site_configuration_id
  from public.site_configurations sc
  order by sc.created_at asc
  limit 1;

  if v_site_configuration_id is null then
    v_site_configuration_id := 'bbb50000-0000-0000-0000-000000000001'::uuid;

    insert into public.site_configurations (
      id,
      display_sitewide_message,
      sitewide_message,
      created_at,
      updated_at,
      help_link_items,
      revision_reason_options,
      small_scale_requirement_template_id,
      sitewide_message_color
    ) values (
      v_site_configuration_id,
      false,
      null,
      clock_timestamp(),
      clock_timestamp(),
      null,
      null,
      null,
      'theme.softRose'
    );
  else
    update public.site_configurations
    set
      display_sitewide_message = false,
      sitewide_message_color = coalesce(sitewide_message_color, 'theme.softRose'),
      updated_at = clock_timestamp()
    where id = v_site_configuration_id;
  end if;

  merge into public.revision_reasons as target
  using (
    values
      ('bbb60000-0000-0000-0000-000000000001'::uuid, 'zoning_non_compliance', 'Zoning non-compliance'),
      ('bbb60000-0000-0000-0000-000000000002'::uuid, 'inaccurate_documentation', 'Inaccurate documentation'),
      ('bbb60000-0000-0000-0000-000000000003'::uuid, 'failure_to_meet_building_code', 'Failure to meet building code requirements'),
      ('bbb60000-0000-0000-0000-000000000004'::uuid, 'other', 'Other'),
      ('bbb60000-0000-0000-0000-000000000005'::uuid, 'contractor_onboarding_form', 'Contractor Onboarding Form')
  ) as source(id, reason_code, description)
  on target.reason_code = source.reason_code
  when matched then update set
    description = source.description,
    site_configuration_id = v_site_configuration_id,
    discarded_at = null,
    _discard = false,
    updated_at = clock_timestamp()
  when not matched then insert (
    id,
    reason_code,
    description,
    site_configuration_id,
    discarded_at,
    created_at,
    updated_at,
    _discard
  ) values (
    source.id,
    source.reason_code,
    source.description,
    v_site_configuration_id,
    null,
    clock_timestamp(),
    clock_timestamp(),
    false
  );
end $$;

create or replace function pg_temp.ensure_minimal_template(
  p_program_id uuid,
  p_permit_type_id uuid,
  p_activity_id uuid,
  p_user_group_type_id uuid,
  p_audience_type_id uuid,
  p_submission_type_id uuid,
  p_submission_variant_id uuid,
  p_nickname text,
  p_field_key text,
  p_field_label text,
  p_template_id uuid,
  p_version_id uuid
) returns void
language plpgsql
as $$
declare
  v_template_id uuid;
  v_version_id uuid;
  v_existing_form_json jsonb;
  v_form_json jsonb;
  v_section_id text;
  v_section_key text;
  v_block_id text;
  v_block_key text;
  v_requirement_key text;
  v_notes_key text;
  v_should_apply_bootstrap boolean;
  v_version_exists boolean;
begin
  select rt.id
    into v_template_id
  from public.requirement_templates rt
  where rt.program_id = p_program_id
    and rt.user_group_type_id = p_user_group_type_id
    and rt.audience_type_id = p_audience_type_id
    and rt.submission_type_id = p_submission_type_id
    and (
      (rt.submission_variant_id is null and p_submission_variant_id is null)
      or rt.submission_variant_id = p_submission_variant_id
    )
  order by rt.created_at asc
  limit 1;

  if v_template_id is null then
    v_template_id := p_template_id;

    insert into public.requirement_templates (
      id,
      activity_id,
      permit_type_id,
      created_at,
      updated_at,
      description,
      discarded_at,
      first_nations,
      type,
      nickname,
      fetched_at,
      copied_from_id,
      assignee_id,
      public,
      program_id,
      user_group_type_id,
      audience_type_id,
      submission_type_id,
      submission_variant_id
    ) values (
      v_template_id,
      p_activity_id,
      p_permit_type_id,
      clock_timestamp(),
      clock_timestamp(),
      'Local bootstrap template for old app flow',
      null,
      false,
      null,
      p_nickname,
      null,
      null,
      null,
      false,
      p_program_id,
      p_user_group_type_id,
      p_audience_type_id,
      p_submission_type_id,
      p_submission_variant_id
    );
  else
    update public.requirement_templates
    set
      nickname = p_nickname,
      description = 'Local bootstrap template for old app flow',
      discarded_at = null,
      updated_at = clock_timestamp(),
      activity_id = p_activity_id,
      permit_type_id = p_permit_type_id,
      submission_variant_id = p_submission_variant_id
    where id = v_template_id;
  end if;

  select tv.id
    into v_version_id
  from public.template_versions tv
  where tv.requirement_template_id = v_template_id
    and tv.status = 1
  order by tv.version_date desc, tv.created_at desc
  limit 1;

  if v_version_id is null then
    select tv.id
      into v_version_id
    from public.template_versions tv
    where tv.requirement_template_id = v_template_id
    order by tv.version_date desc, tv.created_at desc
    limit 1;
  end if;

  if v_version_id is null then
    v_version_id := p_version_id;
  end if;

  select exists (
    select 1
    from public.template_versions tv
    where tv.id = v_version_id
  )
    into v_version_exists;

  if v_version_exists then
    select tv.form_json
      into v_existing_form_json
    from public.template_versions tv
    where tv.id = v_version_id;
  end if;

  v_section_id := replace(v_template_id::text, '-', '');
  v_section_key := 'section' || v_section_id;
  v_block_id := replace(v_version_id::text, '-', '');
  v_block_key := 'formSubmissionDataRST' || v_section_key || '|RB' || v_block_id;
  v_requirement_key := v_block_key || '|' || p_field_key;
  v_notes_key := v_block_key || '|' || p_field_key || '_notes';

  v_form_json := jsonb_build_object(
    'display', 'form',
    'components', jsonb_build_array(
      jsonb_build_object(
        'id', v_section_id,
        'type', 'container',
        'key', v_section_key,
        'title', p_nickname,
        'label', p_nickname,
        'custom_class', 'formio-section-container',
        'hide_label', false,
        'collapsible', false,
        'initially_collapsed', false,
        'input', false,
        'tableView', false,
        'components', jsonb_build_array(
          jsonb_build_object(
            'id', v_block_id,
            'type', 'panel',
            'key', v_block_key,
            'title', p_field_label,
            'label', p_field_label,
            'description', 'Local bootstrap block',
            'collapsible', true,
            'collapsed', false,
            'input', false,
            'tableView', false,
            'components', jsonb_build_array(
              jsonb_build_object(
                'type', 'textfield',
                'key', v_requirement_key,
                'label', p_field_label,
                'input', true,
                'tableView', true
              ),
              jsonb_build_object(
                'type', 'textarea',
                'key', v_notes_key,
                'label', 'Notes',
                'input', true,
                'tableView', false
              )
            )
          )
        )
      ),
      jsonb_build_object(
        'id', 'section-completion-id',
        'key', 'section-completion-key',
        'type', 'container',
        'title', 'Complete and submit',
        'label', 'Complete and submit',
        'custom_class', 'formio-section-container',
        'hide_label', false,
        'collapsible', false,
        'initially_collapsed', false,
        'components', jsonb_build_array(
          jsonb_build_object(
            'id', 'section-signoff-id',
            'key', 'section-signoff-key',
            'type', 'panel',
            'title', 'Sign off and submit',
            'collapsible', true,
            'collapsed', false,
            'components', jsonb_build_array(
              jsonb_build_object(
                'type', 'checkbox',
                'key', 'signed',
                'title', 'I confirm the information in this submission is correct.',
                'label', 'I confirm the information in this submission is correct.',
                'inputType', 'checkbox',
                'validate', jsonb_build_object('required', true),
                'input', true,
                'defaultValue', false
              ),
              jsonb_build_object(
                'key', 'submit',
                'size', 'md',
                'type', 'button',
                'block', false,
                'input', true,
                'title', 'Submit',
                'label', 'Submit',
                'theme', 'primary',
                'action', 'submit',
                'widget', jsonb_build_object('type', 'input'),
                'disabled', false,
                'show', false,
                'conditional', jsonb_build_object(
                  'show', true,
                  'when', 'signed',
                  'eq', 'true'
                )
              )
            )
          )
        )
      )
    )
  );

  v_should_apply_bootstrap :=
    v_existing_form_json is null
    or v_existing_form_json = '{}'::jsonb
    or v_existing_form_json::text like '%Local bootstrap block%';

  if not v_version_exists then
    insert into public.template_versions (
      id,
      denormalized_template_json,
      form_json,
      requirement_blocks_json,
      version_diff,
      version_date,
      status,
      requirement_template_id,
      created_at,
      updated_at,
      deprecation_reason,
      deprecated_by_id
    ) values (
      v_version_id,
      v_form_json,
      v_form_json,
      '{}'::jsonb,
      '{}'::json,
      current_date,
      1,
      v_template_id,
      clock_timestamp(),
      clock_timestamp(),
      null,
      null
    );
  elsif v_should_apply_bootstrap then
    update public.template_versions
    set
      denormalized_template_json = v_form_json,
      form_json = v_form_json,
      requirement_blocks_json = '{}'::jsonb,
      version_diff = '{}'::json,
      version_date = current_date,
      status = 1,
      deprecation_reason = null,
      deprecated_by_id = null,
      updated_at = clock_timestamp()
    where id = v_version_id;
  end if;

  update public.template_versions
  set
    status = 2,
    deprecation_reason = 0,
    deprecated_by_id = null,
    updated_at = clock_timestamp()
  where requirement_template_id = v_template_id
    and id <> v_version_id
    and status = 1;
end;
$$;

do $$
declare
  v_program_id uuid;
  v_permit_type_id uuid;
  v_activity_id uuid;
  v_external_id uuid;
  v_participant_id uuid;
  v_contractor_id uuid;
  v_application_id uuid;
  v_onboarding_id uuid;
  v_invoice_id uuid;
  v_invoice_space_id uuid;
  v_invoice_water_id uuid;
  v_invoice_insulation_id uuid;
  v_invoice_windows_id uuid;
  v_invoice_ventilation_id uuid;
  v_invoice_electrical_id uuid;
  v_invoice_health_id uuid;
begin
  select id into v_permit_type_id from public.permit_classifications where code = 0;
  select id into v_activity_id from public.permit_classifications where code = 4;
  select id into v_external_id from public.permit_classifications where code = 8;
  select id into v_participant_id from public.permit_classifications where code = 9;
  select id into v_contractor_id from public.permit_classifications where code = 10;
  select id into v_application_id from public.permit_classifications where code = 11;
  select id into v_onboarding_id from public.permit_classifications where code = 12;
  select id into v_invoice_id from public.permit_classifications where code = 14;
  select id into v_invoice_space_id from public.permit_classifications where code = 15;
  select id into v_invoice_water_id from public.permit_classifications where code = 16;
  select id into v_invoice_insulation_id from public.permit_classifications where code = 17;
  select id into v_invoice_windows_id from public.permit_classifications where code = 18;
  select id into v_invoice_ventilation_id from public.permit_classifications where code = 19;
  select id into v_invoice_electrical_id from public.permit_classifications where code = 20;
  select id into v_invoice_health_id from public.permit_classifications where code = 21;

  select p.id
    into v_program_id
  from public.programs p
  where p.slug = 'energy-savings-program'
  order by p.created_at asc
  limit 1;

  if v_program_id is null then
    select p.id
      into v_program_id
    from public.programs p
    where lower(p.program_name) = lower('Energy Savings Program')
    order by p.created_at asc
    limit 1;
  end if;

  if v_program_id is null then
    v_program_id := 'bbb10000-0000-0000-0000-000000000001'::uuid;

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
    set
      program_name = 'Energy Savings Program',
      funded_by = 'Local bootstrap',
      description_html = '<p>Locally bootstrapped program for exercising the legacy contractor and participant flows.</p>',
      external_api_state = coalesce(external_api_state, 'g_off'),
      slug = 'energy-savings-program',
      updated_at = clock_timestamp()
    where id = v_program_id;
  end if;

  perform pg_temp.ensure_minimal_template(
    v_program_id,
    v_permit_type_id,
    v_activity_id,
    v_participant_id,
    v_external_id,
    v_application_id,
    null,
    'ESP Participant Application',
    'participant_application_name',
    'Applicant name',
    'bbb20000-0000-0000-0000-000000000001'::uuid,
    'bbb30000-0000-0000-0000-000000000001'::uuid
  );

  perform pg_temp.ensure_minimal_template(
    v_program_id,
    v_permit_type_id,
    v_activity_id,
    v_contractor_id,
    v_external_id,
    v_onboarding_id,
    null,
    'ESP Contractor Onboarding',
    'business_name',
    'Contractor business name',
    'bbb20000-0000-0000-0000-000000000002'::uuid,
    'bbb30000-0000-0000-0000-000000000002'::uuid
  );

  perform pg_temp.ensure_minimal_template(
    v_program_id,
    v_permit_type_id,
    v_activity_id,
    v_contractor_id,
    v_external_id,
    v_invoice_id,
    v_invoice_space_id,
    'Invoice - Heat pump (space heating)',
    'invoice_heat_pump_space_name',
    'Customer or project name',
    'bbb20000-0000-0000-0000-000000000101'::uuid,
    'bbb30000-0000-0000-0000-000000000101'::uuid
  );

  perform pg_temp.ensure_minimal_template(
    v_program_id,
    v_permit_type_id,
    v_activity_id,
    v_contractor_id,
    v_external_id,
    v_invoice_id,
    v_invoice_water_id,
    'Invoice - Heat pump water heater',
    'invoice_heat_pump_water_name',
    'Customer or project name',
    'bbb20000-0000-0000-0000-000000000102'::uuid,
    'bbb30000-0000-0000-0000-000000000102'::uuid
  );

  perform pg_temp.ensure_minimal_template(
    v_program_id,
    v_permit_type_id,
    v_activity_id,
    v_contractor_id,
    v_external_id,
    v_invoice_id,
    v_invoice_insulation_id,
    'Invoice - Insulation',
    'invoice_insulation_name',
    'Customer or project name',
    'bbb20000-0000-0000-0000-000000000103'::uuid,
    'bbb30000-0000-0000-0000-000000000103'::uuid
  );

  perform pg_temp.ensure_minimal_template(
    v_program_id,
    v_permit_type_id,
    v_activity_id,
    v_contractor_id,
    v_external_id,
    v_invoice_id,
    v_invoice_windows_id,
    'Invoice - Windows and doors',
    'invoice_windows_doors_name',
    'Customer or project name',
    'bbb20000-0000-0000-0000-000000000104'::uuid,
    'bbb30000-0000-0000-0000-000000000104'::uuid
  );

  perform pg_temp.ensure_minimal_template(
    v_program_id,
    v_permit_type_id,
    v_activity_id,
    v_contractor_id,
    v_external_id,
    v_invoice_id,
    v_invoice_ventilation_id,
    'Invoice - Ventilation',
    'invoice_ventilation_name',
    'Customer or project name',
    'bbb20000-0000-0000-0000-000000000105'::uuid,
    'bbb30000-0000-0000-0000-000000000105'::uuid
  );

  perform pg_temp.ensure_minimal_template(
    v_program_id,
    v_permit_type_id,
    v_activity_id,
    v_contractor_id,
    v_external_id,
    v_invoice_id,
    v_invoice_electrical_id,
    'Invoice - Electrical service upgrade',
    'invoice_electrical_upgrade_name',
    'Customer or project name',
    'bbb20000-0000-0000-0000-000000000106'::uuid,
    'bbb30000-0000-0000-0000-000000000106'::uuid
  );

  perform pg_temp.ensure_minimal_template(
    v_program_id,
    v_permit_type_id,
    v_activity_id,
    v_contractor_id,
    v_external_id,
    v_invoice_id,
    v_invoice_health_id,
    'Invoice - Health and safety remediation',
    'invoice_health_safety_name',
    'Customer or project name',
    'bbb20000-0000-0000-0000-000000000107'::uuid,
    'bbb30000-0000-0000-0000-000000000107'::uuid
  );

  update public.permit_applications pa
  set permit_type_id = rt.permit_type_id,
      activity_id = rt.activity_id,
      updated_at = clock_timestamp()
  from public.template_versions tv
  join public.requirement_templates rt
    on rt.id = tv.requirement_template_id
  where pa.template_version_id = tv.id
    and pa.program_id = v_program_id
    and (
      pa.permit_type_id is distinct from rt.permit_type_id
      or pa.activity_id is distinct from rt.activity_id
    );

  raise notice 'Legacy app bootstrap complete. Program id = %', v_program_id;
end $$;

commit;
