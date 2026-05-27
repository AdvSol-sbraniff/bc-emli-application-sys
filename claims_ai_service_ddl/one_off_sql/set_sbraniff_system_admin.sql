begin;

-- Rerunnable role switch for the local sbraniff staff user.

do $$
declare
  v_target_username text := 'SBRANIFF';
  v_user_id uuid;
begin
  select u.id
    into v_user_id
  from public.users u
  where upper(coalesce(u.omniauth_username, '')) = upper(v_target_username)
     or lower(coalesce(u.email, '')) = lower(v_target_username)
  order by u.created_at asc
  limit 1;

  if v_user_id is null then
    raise exception 'No user found for target "%" (checked omniauth_username/email).', v_target_username;
  end if;

  update public.users
  set role = 3,
      updated_at = clock_timestamp()
  where id = v_user_id;

  raise notice 'User % is now role=3 (system_admin).', v_user_id;
end $$;

commit;
