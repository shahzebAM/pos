-- PATCH: FIX AUTH USER CREATION TRIGGER
-- Use this if staff creation shows: "Database error creating new user".
-- It recreates the auth.users trigger function so it always writes a valid staff profile.

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_has_username boolean := false;
  v_has_deleted_at boolean := false;
  v_username text := lower(regexp_replace(trim(coalesce(new.raw_user_meta_data->>'username', split_part(coalesce(new.email, ''), '@', 1))), '[^a-z0-9._-]', '', 'g'));
  v_email text;
  v_full_name text;
begin
  select exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'user_profiles'
      and column_name = 'username'
  )
  into v_has_username;

  select exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'user_profiles'
      and column_name = 'deleted_at'
  )
  into v_has_deleted_at;

  if v_username = '' or length(v_username) < 3 or v_username !~ '^[a-z0-9]' then
    v_username := 'user' || replace(left(new.id::text, 8), '-', '');
  end if;

  v_username := left(v_username, 32);

  v_email := lower(coalesce(new.email, v_username || '@staff.pos.test'));
  v_full_name := coalesce(nullif(trim(new.raw_user_meta_data->>'full_name'), ''), v_username, split_part(coalesce(new.email, 'New User'), '@', 1));

  if v_has_username then
    if exists (
      select 1
      from public.user_profiles
      where lower(username) = v_username
        and id <> new.id
    ) then
      v_username := left(v_username, 23) || '-' || left(replace(new.id::text, '-', ''), 8);
    end if;

    if v_has_deleted_at then
      insert into public.user_profiles (id, username, email, full_name, role, is_active, deleted_at)
      values (new.id, v_username, v_email, v_full_name, 'cashier', false, null)
      on conflict (id) do nothing;
    else
      insert into public.user_profiles (id, username, email, full_name, role, is_active)
      values (new.id, v_username, v_email, v_full_name, 'cashier', false)
      on conflict (id) do nothing;
    end if;
  else
    insert into public.user_profiles (id, email, full_name, role, is_active)
    values (new.id, v_email, v_full_name, 'cashier', false)
    on conflict (id) do nothing;
  end if;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_auth_user();
