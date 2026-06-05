-- MODULE 3: USER & ROLE MANAGEMENT
-- Run after:
-- 1. supabase/00-reset-public-schema.sql
-- 2. supabase/01-dashboard-module.sql
-- 3. supabase/02-auth-and-branch-management.sql
--
-- This is the clean username/password version of Module 3.
-- It removes the old invite-code module and installs:
-- - username-based login mapping for Supabase Auth
-- - admin, manager, cashier, auditor roles
-- - branch-level access settings
-- - shift access settings
-- - permission catalog
-- - activity logs
-- - user update/deactivate RPCs

create extension if not exists pgcrypto;

drop function if exists public.auth_accept_staff_invite(text);
drop function if exists public.apply_staff_invite_for_user(uuid, text, text);
drop function if exists public.staff_invite_create(jsonb);
drop function if exists public.staff_invite_revoke(uuid);
drop table if exists public.staff_invitations cascade;

alter table public.user_profiles
  add column if not exists username text,
  add column if not exists phone text,
  add column if not exists job_title text,
  add column if not exists last_seen_at timestamptz,
  add column if not exists deleted_at timestamptz;

drop index if exists public.idx_user_profiles_employee_code;

with prepared as (
  select
    id,
    lower(regexp_replace(coalesce(nullif(username, ''), split_part(email, '@', 1), 'user' || left(id::text, 8)), '[^a-z0-9._-]', '', 'g')) as raw_base
  from public.user_profiles
  where username is null or trim(username) = ''
),
base_names as (
  select
    id,
    case
      when length(raw_base) >= 3 and raw_base ~ '^[a-z0-9]' then left(raw_base, 28)
      else 'user' || replace(left(id::text, 8), '-', '')
    end as base_username
  from prepared
),
ranked_names as (
  select
    id,
    base_username,
    row_number() over (partition by base_username order by id) as row_number
  from base_names
)
update public.user_profiles up
set username = case
    when ranked_names.row_number = 1 then ranked_names.base_username
    else left(ranked_names.base_username, 25) || ranked_names.row_number::text
  end
from ranked_names
where up.id = ranked_names.id;

alter table public.user_profiles
  alter column username set not null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'user_profiles_username_format'
      and conrelid = 'public.user_profiles'::regclass
  ) then
    alter table public.user_profiles
      add constraint user_profiles_username_format
      check (username ~ '^[a-z0-9][a-z0-9._-]{2,31}$');
  end if;
end;
$$;

create unique index if not exists idx_user_profiles_username_lower
on public.user_profiles (lower(username));

create table if not exists public.user_access_settings (
  user_id uuid primary key references public.user_profiles(id) on delete cascade,
  can_access_all_branches boolean not null default false,
  allowed_branch_ids uuid[] not null default array[]::uuid[],
  permissions text[] not null default array[]::text[],
  shift_days smallint[] not null default array[1, 2, 3, 4, 5, 6, 7]::smallint[],
  shift_start time not null default time '00:00',
  shift_end time not null default time '23:59',
  max_discount_percent numeric(5, 2) not null default 0 check (max_discount_percent >= 0 and max_discount_percent <= 100),
  can_open_shift boolean not null default true,
  can_close_shift boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

drop trigger if exists set_user_access_settings_updated_at on public.user_access_settings;
create trigger set_user_access_settings_updated_at
before update on public.user_access_settings
for each row execute function public.set_updated_at();

create table if not exists public.activity_logs (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid references public.user_profiles(id) on delete set null,
  action text not null,
  entity_type text not null,
  entity_id text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists idx_activity_logs_created_at on public.activity_logs(created_at desc);
create index if not exists idx_activity_logs_actor on public.activity_logs(actor_id, created_at desc);
create index if not exists idx_activity_logs_entity on public.activity_logs(entity_type, entity_id);

alter table public.user_access_settings enable row level security;
alter table public.activity_logs enable row level security;

create or replace function public.pos_internal_auth_email(p_username text)
returns text
language sql
immutable
as $$
  select lower(trim(coalesce(p_username, ''))) || '@staff.pos.test'
$$;

create or replace function public.current_user_role()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select role
  from public.user_profiles
  where id = auth.uid()
    and is_active = true
    and deleted_at is null
  limit 1
$$;

create or replace function public.current_user_branch_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select branch_id
  from public.user_profiles
  where id = auth.uid()
    and is_active = true
    and deleted_at is null
  limit 1
$$;

create or replace function public.current_user_is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.user_profiles
    where id = auth.uid()
      and role = 'admin'
      and is_active = true
      and deleted_at is null
  )
$$;

create or replace function public.ensure_active_user()
returns public.user_profiles
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_profile public.user_profiles;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated' using errcode = '28000';
  end if;

  select *
  into v_profile
  from public.user_profiles
  where id = auth.uid()
  limit 1;

  if v_profile.id is null or v_profile.is_active = false or v_profile.deleted_at is not null then
    raise exception 'User profile is not active' using errcode = '42501';
  end if;

  return v_profile;
end;
$$;

create or replace function public.role_default_permissions(p_role text)
returns text[]
language sql
immutable
as $$
  select case p_role
    when 'admin' then array[
      'dashboard.view',
      'branches.view',
      'branches.manage',
      'users.view',
      'users.manage',
      'shifts.view',
      'shifts.manage',
      'activity.view',
      'pos.sell',
      'pos.discount',
      'pos.void',
      'reports.view'
    ]::text[]
    when 'manager' then array[
      'dashboard.view',
      'branches.view',
      'users.view',
      'shifts.view',
      'shifts.manage',
      'pos.sell',
      'pos.discount',
      'reports.view'
    ]::text[]
    when 'auditor' then array[
      'dashboard.view',
      'branches.view',
      'users.view',
      'activity.view',
      'reports.view'
    ]::text[]
    else array[
      'dashboard.view',
      'pos.sell',
      'shifts.view'
    ]::text[]
  end
$$;

create or replace function public.permission_catalog()
returns jsonb
language sql
immutable
as $$
  select jsonb_build_array(
    jsonb_build_object('key', 'dashboard.view', 'label', 'View dashboard'),
    jsonb_build_object('key', 'branches.view', 'label', 'View branches'),
    jsonb_build_object('key', 'branches.manage', 'label', 'Manage branches'),
    jsonb_build_object('key', 'users.view', 'label', 'View users'),
    jsonb_build_object('key', 'users.manage', 'label', 'Manage users'),
    jsonb_build_object('key', 'shifts.view', 'label', 'View shifts'),
    jsonb_build_object('key', 'shifts.manage', 'label', 'Open/close shifts'),
    jsonb_build_object('key', 'activity.view', 'label', 'View activity logs'),
    jsonb_build_object('key', 'pos.sell', 'label', 'Use POS checkout'),
    jsonb_build_object('key', 'pos.discount', 'label', 'Apply discounts'),
    jsonb_build_object('key', 'pos.void', 'label', 'Void transactions'),
    jsonb_build_object('key', 'reports.view', 'label', 'View reports')
  )
$$;

create or replace function public.log_activity(
  p_action text,
  p_entity_type text,
  p_entity_id text default null,
  p_metadata jsonb default '{}'::jsonb,
  p_actor_id uuid default auth.uid()
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.activity_logs (actor_id, action, entity_type, entity_id, metadata)
  values (p_actor_id, p_action, p_entity_type, p_entity_id, coalesce(p_metadata, '{}'::jsonb));
end;
$$;

drop policy if exists user_access_settings_self_or_admin_select on public.user_access_settings;
create policy user_access_settings_self_or_admin_select
on public.user_access_settings
for select
to authenticated
using (user_id = auth.uid() or public.current_user_is_admin());

drop policy if exists user_access_settings_admin_write on public.user_access_settings;
create policy user_access_settings_admin_write
on public.user_access_settings
for all
to authenticated
using (public.current_user_is_admin())
with check (public.current_user_is_admin());

drop policy if exists activity_logs_admin_auditor_select on public.activity_logs;
create policy activity_logs_admin_auditor_select
on public.activity_logs
for select
to authenticated
using (public.current_user_role() in ('admin', 'auditor'));

create or replace function public.jsonb_text_array(p_payload jsonb, p_key text, p_default text[] default array[]::text[])
returns text[]
language sql
immutable
as $$
  select case
    when p_payload ? p_key and jsonb_typeof(p_payload->p_key) = 'array'
      then coalesce((select array_agg(value) from jsonb_array_elements_text(p_payload->p_key)), array[]::text[])
    else p_default
  end
$$;

create or replace function public.jsonb_uuid_array(p_payload jsonb, p_key text, p_default uuid[] default array[]::uuid[])
returns uuid[]
language sql
immutable
as $$
  select case
    when p_payload ? p_key and jsonb_typeof(p_payload->p_key) = 'array'
      then coalesce((select array_agg(value::uuid) from jsonb_array_elements_text(p_payload->p_key)), array[]::uuid[])
    else p_default
  end
$$;

create or replace function public.jsonb_smallint_array(p_payload jsonb, p_key text, p_default smallint[] default array[1, 2, 3, 4, 5, 6, 7]::smallint[])
returns smallint[]
language sql
immutable
as $$
  select case
    when p_payload ? p_key and jsonb_typeof(p_payload->p_key) = 'array'
      then coalesce((select array_agg(value::smallint) from jsonb_array_elements_text(p_payload->p_key)), array[]::smallint[])
    else p_default
  end
$$;

insert into public.user_access_settings (
  user_id,
  can_access_all_branches,
  allowed_branch_ids,
  permissions,
  can_open_shift,
  can_close_shift,
  max_discount_percent
)
select
  up.id,
  up.role in ('admin', 'auditor'),
  case when up.branch_id is null then array[]::uuid[] else array[up.branch_id]::uuid[] end,
  public.role_default_permissions(up.role),
  true,
  up.role in ('admin', 'manager'),
  case when up.role = 'admin' then 100 when up.role = 'manager' then 20 when up.role = 'cashier' then 5 else 0 end
from public.user_profiles up
left join public.user_access_settings uas on uas.user_id = up.id
where uas.user_id is null;

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_username text := lower(trim(coalesce(new.raw_user_meta_data->>'username', split_part(coalesce(new.email, ''), '@', 1))));
  v_full_name text := coalesce(nullif(trim(new.raw_user_meta_data->>'full_name'), ''), v_username, 'Staff User');
begin
  if v_username = '' then
    v_username := 'user' || replace(left(new.id::text, 8), '-', '');
  end if;

  insert into public.user_profiles (id, username, email, full_name, role, is_active, deleted_at)
  values (
    new.id,
    v_username,
    lower(coalesce(new.email, public.pos_internal_auth_email(v_username))),
    v_full_name,
    'cashier',
    false,
    null
  )
  on conflict (id) do nothing;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_auth_user();

create or replace function public.auth_resolve_login_identifier(p_identifier text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_identifier text := lower(trim(coalesce(p_identifier, '')));
  v_email text;
begin
  if v_identifier = '' then
    raise exception 'Username is required' using errcode = '23502';
  end if;

  if position('@' in v_identifier) > 0 then
    return jsonb_build_object('email', v_identifier);
  end if;

  select email
  into v_email
  from public.user_profiles
  where lower(username) = v_identifier
    and deleted_at is null
  limit 1;

  if v_email is null then
    raise exception 'Invalid username or password' using errcode = '28000';
  end if;

  return jsonb_build_object('email', v_email);
end;
$$;

create or replace function public.auth_get_current_profile()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.user_profiles;
  v_access public.user_access_settings;
  v_branch public.branches;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated' using errcode = '28000';
  end if;

  select *
  into v_profile
  from public.user_profiles
  where id = auth.uid()
  limit 1;

  if v_profile.id is not null then
    update public.user_profiles
    set last_seen_at = now()
    where id = auth.uid();

    select *
    into v_access
    from public.user_access_settings
    where user_id = auth.uid()
    limit 1;

    select *
    into v_branch
    from public.branches
    where id = v_profile.branch_id
    limit 1;
  end if;

  return jsonb_build_object(
    'profile',
    case
      when v_profile.id is null then null
      else jsonb_build_object(
        'id', v_profile.id,
        'username', v_profile.username,
        'full_name', v_profile.full_name,
        'email', v_profile.email,
        'phone', v_profile.phone,
        'job_title', v_profile.job_title,
        'role', v_profile.role,
        'branch_id', v_profile.branch_id,
        'branch_name', v_branch.name,
        'is_active', v_profile.is_active,
        'last_seen_at', v_profile.last_seen_at,
        'can_access_all_branches', coalesce(v_access.can_access_all_branches, false),
        'allowed_branch_ids', coalesce(to_jsonb(v_access.allowed_branch_ids), '[]'::jsonb),
        'permissions', coalesce(to_jsonb(v_access.permissions), '[]'::jsonb),
        'shift_days', coalesce(to_jsonb(v_access.shift_days), '[]'::jsonb),
        'shift_start', v_access.shift_start,
        'shift_end', v_access.shift_end,
        'max_discount_percent', coalesce(v_access.max_discount_percent, 0),
        'can_open_shift', coalesce(v_access.can_open_shift, false),
        'can_close_shift', coalesce(v_access.can_close_shift, false)
      )
    end,
    'has_admin', exists (
      select 1
      from public.user_profiles
      where role = 'admin'
        and is_active = true
        and deleted_at is null
    )
  );
end;
$$;

create or replace function public.auth_bootstrap_first_admin(p_full_name text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.user_profiles;
  v_username text := lower(trim(coalesce(auth.jwt()->'user_metadata'->>'username', split_part(coalesce(auth.jwt()->>'email', ''), '@', 1))));
  v_email text := lower(coalesce(auth.jwt()->>'email', public.pos_internal_auth_email(v_username)));
  v_name text := coalesce(nullif(trim(p_full_name), ''), nullif(auth.jwt()->'user_metadata'->>'full_name', ''), v_username, 'Admin');
begin
  if auth.uid() is null then
    raise exception 'Not authenticated' using errcode = '28000';
  end if;

  if exists (select 1 from public.user_profiles where role = 'admin' and is_active = true and deleted_at is null) then
    raise exception 'First admin already exists' using errcode = '23505';
  end if;

  insert into public.user_profiles (id, username, email, full_name, role, branch_id, is_active, deleted_at)
  values (auth.uid(), v_username, v_email, v_name, 'admin', null, true, null)
  on conflict (id) do update
  set username = excluded.username,
      email = excluded.email,
      full_name = excluded.full_name,
      role = 'admin',
      branch_id = null,
      is_active = true,
      deleted_at = null,
      updated_at = now()
  returning * into v_profile;

  insert into public.user_access_settings (
    user_id,
    can_access_all_branches,
    permissions,
    can_open_shift,
    can_close_shift,
    max_discount_percent
  )
  values (
    auth.uid(),
    true,
    public.role_default_permissions('admin'),
    true,
    true,
    100
  )
  on conflict (user_id) do update
  set can_access_all_branches = true,
      allowed_branch_ids = array[]::uuid[],
      permissions = public.role_default_permissions('admin'),
      can_open_shift = true,
      can_close_shift = true,
      max_discount_percent = 100,
      updated_at = now();

  perform public.log_activity(
    'auth.first_admin_bootstrap',
    'user',
    auth.uid()::text,
    jsonb_build_object('username', v_profile.username),
    auth.uid()
  );

  return public.auth_get_current_profile();
end;
$$;

create or replace function public.user_management_get()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.user_profiles;
  v_result jsonb;
begin
  v_profile := public.ensure_active_user();

  if v_profile.role not in ('admin', 'auditor', 'manager') then
    raise exception 'User management is not available for this role' using errcode = '42501';
  end if;

  with visible_users as (
    select up.*
    from public.user_profiles up
    where up.deleted_at is null
      and (
        v_profile.role in ('admin', 'auditor')
        or up.branch_id = v_profile.branch_id
        or up.id = v_profile.id
      )
  ),
  user_rows as (
    select
      up.id,
      up.username,
      up.full_name,
      up.email,
      up.phone,
      up.job_title,
      up.role,
      up.branch_id,
      b.name as branch_name,
      up.is_active,
      up.created_at,
      up.updated_at,
      up.last_seen_at,
      coalesce(uas.can_access_all_branches, false) as can_access_all_branches,
      coalesce(uas.allowed_branch_ids, array[]::uuid[]) as allowed_branch_ids,
      coalesce(uas.permissions, array[]::text[]) as permissions,
      coalesce(uas.shift_days, array[]::smallint[]) as shift_days,
      uas.shift_start,
      uas.shift_end,
      coalesce(uas.max_discount_percent, 0) as max_discount_percent,
      coalesce(uas.can_open_shift, false) as can_open_shift,
      coalesce(uas.can_close_shift, false) as can_close_shift
    from visible_users up
    left join public.branches b on b.id = up.branch_id
    left join public.user_access_settings uas on uas.user_id = up.id
  ),
  activity_rows as (
    select
      al.id,
      al.action,
      al.entity_type,
      al.entity_id,
      al.metadata,
      al.created_at,
      actor.full_name as actor_name,
      actor.username as actor_username
    from public.activity_logs al
    left join public.user_profiles actor on actor.id = al.actor_id
    where v_profile.role in ('admin', 'auditor')
       or al.actor_id = v_profile.id
    order by al.created_at desc
    limit 80
  )
  select jsonb_build_object(
    'summary', jsonb_build_object(
      'total_users', coalesce((select count(*) from visible_users), 0),
      'active_users', coalesce((select count(*) from visible_users where is_active = true), 0),
      'admins', coalesce((select count(*) from visible_users where role = 'admin'), 0),
      'managers', coalesce((select count(*) from visible_users where role = 'manager'), 0),
      'cashiers', coalesce((select count(*) from visible_users where role = 'cashier'), 0),
      'auditors', coalesce((select count(*) from visible_users where role = 'auditor'), 0),
      'pending_invites', 0
    ),
    'branches', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', b.id,
          'branch_code', b.branch_code,
          'name', b.name,
          'is_head_office', b.is_head_office,
          'is_active', b.is_active
        )
        order by b.is_head_office desc, b.name
      )
      from public.branches b
      where b.is_active = true
        and (v_profile.role in ('admin', 'auditor') or b.id = v_profile.branch_id)
    ), '[]'::jsonb),
    'users', coalesce((
      select jsonb_agg(to_jsonb(user_rows) order by role asc, full_name asc)
      from user_rows
    ), '[]'::jsonb),
    'invitations', '[]'::jsonb,
    'activity_logs', coalesce((
      select jsonb_agg(to_jsonb(activity_rows) order by created_at desc)
      from activity_rows
    ), '[]'::jsonb),
    'permission_catalog', public.permission_catalog(),
    'generated_at', now()
  )
  into v_result;

  return v_result;
end;
$$;

create or replace function public.staff_user_update(p_user_id uuid, p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor public.user_profiles;
  v_target public.user_profiles;
  v_role text := coalesce(nullif(p_payload->>'role', ''), 'cashier');
  v_username text := lower(trim(coalesce(p_payload->>'username', '')));
  v_full_name text := trim(coalesce(p_payload->>'full_name', ''));
  v_branch_id uuid := nullif(p_payload->>'branch_id', '')::uuid;
  v_is_active boolean := coalesce((p_payload->>'is_active')::boolean, true);
  v_permissions text[] := public.jsonb_text_array(p_payload, 'permissions', public.role_default_permissions(v_role));
  v_allowed_branches uuid[] := public.jsonb_uuid_array(p_payload, 'allowed_branch_ids', case when v_branch_id is null then array[]::uuid[] else array[v_branch_id]::uuid[] end);
  v_other_active_admins integer;
begin
  v_actor := public.ensure_active_user();

  if v_actor.role <> 'admin' then
    raise exception 'Only admins can update staff users' using errcode = '42501';
  end if;

  select *
  into v_target
  from public.user_profiles
  where id = p_user_id
  limit 1;

  if v_target.id is null then
    raise exception 'User not found' using errcode = '02000';
  end if;

  if v_username !~ '^[a-z0-9][a-z0-9._-]{2,31}$' then
    raise exception 'Username must be 3-32 characters and use lowercase letters, numbers, dot, underscore, or dash' using errcode = '23514';
  end if;

  if v_full_name = '' then
    raise exception 'Full name is required' using errcode = '23502';
  end if;

  if v_role not in ('admin', 'manager', 'cashier', 'auditor') then
    raise exception 'Invalid role' using errcode = '22023';
  end if;

  if v_role in ('manager', 'cashier') and v_branch_id is null then
    raise exception 'Branch is required for manager and cashier roles' using errcode = '23502';
  end if;

  if p_user_id = v_actor.id and (v_role <> 'admin' or v_is_active = false) then
    raise exception 'Admins cannot demote or deactivate their own active session' using errcode = '23514';
  end if;

  if v_target.role = 'admin' and (v_role <> 'admin' or v_is_active = false) then
    select count(*)::integer
    into v_other_active_admins
    from public.user_profiles
    where role = 'admin'
      and is_active = true
      and deleted_at is null
      and id <> p_user_id;

    if v_other_active_admins = 0 then
      raise exception 'Cannot remove the last active admin' using errcode = '23514';
    end if;
  end if;

  update public.user_profiles
  set username = v_username,
      full_name = v_full_name,
      phone = nullif(trim(coalesce(p_payload->>'phone', '')), ''),
      job_title = nullif(trim(coalesce(p_payload->>'job_title', '')), ''),
      role = v_role,
      branch_id = v_branch_id,
      is_active = v_is_active,
      deleted_at = case when v_is_active then null else now() end,
      updated_at = now()
  where id = p_user_id;

  insert into public.user_access_settings (
    user_id,
    can_access_all_branches,
    allowed_branch_ids,
    permissions,
    shift_days,
    shift_start,
    shift_end,
    max_discount_percent,
    can_open_shift,
    can_close_shift
  )
  values (
    p_user_id,
    coalesce((p_payload->>'can_access_all_branches')::boolean, v_role in ('admin', 'auditor')),
    v_allowed_branches,
    v_permissions,
    public.jsonb_smallint_array(p_payload, 'shift_days', array[1, 2, 3, 4, 5, 6, 7]::smallint[]),
    coalesce(nullif(p_payload->>'shift_start', '')::time, time '00:00'),
    coalesce(nullif(p_payload->>'shift_end', '')::time, time '23:59'),
    coalesce((p_payload->>'max_discount_percent')::numeric, 0),
    coalesce((p_payload->>'can_open_shift')::boolean, true),
    coalesce((p_payload->>'can_close_shift')::boolean, v_role in ('admin', 'manager'))
  )
  on conflict (user_id) do update
  set can_access_all_branches = excluded.can_access_all_branches,
      allowed_branch_ids = excluded.allowed_branch_ids,
      permissions = excluded.permissions,
      shift_days = excluded.shift_days,
      shift_start = excluded.shift_start,
      shift_end = excluded.shift_end,
      max_discount_percent = excluded.max_discount_percent,
      can_open_shift = excluded.can_open_shift,
      can_close_shift = excluded.can_close_shift,
      updated_at = now();

  perform public.log_activity(
    'staff.user_updated',
    'user',
    p_user_id::text,
    jsonb_build_object('username', v_username, 'role', v_role, 'branch_id', v_branch_id),
    v_actor.id
  );

  return public.user_management_get();
end;
$$;

create or replace function public.staff_user_deactivate(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor public.user_profiles;
  v_target public.user_profiles;
  v_other_active_admins integer;
begin
  v_actor := public.ensure_active_user();

  if v_actor.role <> 'admin' then
    raise exception 'Only admins can deactivate users' using errcode = '42501';
  end if;

  if p_user_id = v_actor.id then
    raise exception 'Admins cannot deactivate their own active session' using errcode = '23514';
  end if;

  select *
  into v_target
  from public.user_profiles
  where id = p_user_id
  limit 1;

  if v_target.id is null then
    raise exception 'User not found' using errcode = '02000';
  end if;

  if v_target.role = 'admin' then
    select count(*)::integer
    into v_other_active_admins
    from public.user_profiles
    where role = 'admin'
      and is_active = true
      and deleted_at is null
      and id <> p_user_id;

    if v_other_active_admins = 0 then
      raise exception 'Cannot deactivate the last active admin' using errcode = '23514';
    end if;
  end if;

  update public.user_profiles
  set is_active = false,
      deleted_at = now(),
      updated_at = now()
  where id = p_user_id;

  perform public.log_activity(
    'staff.user_deactivated',
    'user',
    p_user_id::text,
    jsonb_build_object('username', v_target.username),
    v_actor.id
  );

  return public.user_management_get();
end;
$$;

revoke all on function public.pos_internal_auth_email(text) from public;
revoke all on function public.auth_resolve_login_identifier(text) from public;
revoke all on function public.auth_get_current_profile() from public;
revoke all on function public.auth_bootstrap_first_admin(text) from public;
revoke all on function public.user_management_get() from public;
revoke all on function public.staff_user_update(uuid, jsonb) from public;
revoke all on function public.staff_user_deactivate(uuid) from public;
grant execute on function public.auth_resolve_login_identifier(text) to anon, authenticated;
grant execute on function public.auth_get_current_profile() to authenticated;
grant execute on function public.auth_bootstrap_first_admin(text) to authenticated;
grant execute on function public.user_management_get() to authenticated;
grant execute on function public.staff_user_update(uuid, jsonb) to authenticated;
grant execute on function public.staff_user_deactivate(uuid) to authenticated;

notify pgrst, 'reload schema';
