-- MODULE 2: AUTH FOUNDATION + BRANCH MANAGEMENT
-- Run after:
-- 1. supabase/00-reset-public-schema.sql
-- 2. supabase/01-dashboard-module.sql
--
-- Scope:
-- - Email/password login foundation through Supabase Auth
-- - First admin bootstrap
-- - Protected dashboard RPC
-- - Branch management CRUD through RPCs
-- - Head office and branch setup
-- - Branch code, BIR RDO details, tax/pricing/inventory settings

create extension if not exists pgcrypto;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

alter table public.branches
  add column if not exists legal_name text,
  add column if not exists tin text,
  add column if not exists business_style text,
  add column if not exists contact_person text,
  add column if not exists contact_phone text,
  add column if not exists contact_email text;

drop trigger if exists set_branches_updated_at on public.branches;
create trigger set_branches_updated_at
before update on public.branches
for each row execute function public.set_updated_at();

create table if not exists public.user_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  email text not null unique,
  role text not null default 'cashier' check (role in ('admin', 'manager', 'cashier', 'auditor')),
  branch_id uuid references public.branches(id) on delete set null,
  is_active boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_user_profiles_role on public.user_profiles(role);
create index if not exists idx_user_profiles_branch on public.user_profiles(branch_id);

drop trigger if exists set_user_profiles_updated_at on public.user_profiles;
create trigger set_user_profiles_updated_at
before update on public.user_profiles
for each row execute function public.set_updated_at();

create table if not exists public.branch_settings (
  branch_id uuid primary key references public.branches(id) on delete cascade,
  pricing_mode text not null default 'standard' check (pricing_mode in ('standard', 'branch_override')),
  tax_profile text not null default 'vat_12' check (tax_profile in ('vat_12', 'non_vat', 'mixed')),
  vat_rate numeric(5, 2) not null default 12.00 check (vat_rate >= 0 and vat_rate <= 100),
  inventory_control text not null default 'branch_stock' check (inventory_control in ('branch_stock', 'centralized_view')),
  allow_negative_stock boolean not null default false,
  receipt_footer text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

drop trigger if exists set_branch_settings_updated_at on public.branch_settings;
create trigger set_branch_settings_updated_at
before update on public.branch_settings
for each row execute function public.set_updated_at();

insert into public.branch_settings (branch_id)
select b.id
from public.branches b
left join public.branch_settings bs on bs.branch_id = b.id
where bs.branch_id is null;

alter table public.user_profiles enable row level security;
alter table public.branch_settings enable row level security;

create or replace function public.current_user_profile()
returns public.user_profiles
language sql
stable
security definer
set search_path = public
as $$
  select *
  from public.user_profiles
  where id = auth.uid()
  limit 1
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
  select *
  into v_profile
  from public.user_profiles
  where id = auth.uid()
  limit 1;

  if auth.uid() is null then
    raise exception 'Not authenticated' using errcode = '28000';
  end if;

  if v_profile.id is null or v_profile.is_active = false then
    raise exception 'User profile is not active' using errcode = '42501';
  end if;

  return v_profile;
end;
$$;

drop policy if exists user_profiles_self_select on public.user_profiles;
create policy user_profiles_self_select
on public.user_profiles
for select
to authenticated
using (id = auth.uid() or public.current_user_is_admin());

drop policy if exists user_profiles_admin_update on public.user_profiles;
create policy user_profiles_admin_update
on public.user_profiles
for update
to authenticated
using (public.current_user_is_admin())
with check (public.current_user_is_admin());

drop policy if exists branches_select_by_role on public.branches;
create policy branches_select_by_role
on public.branches
for select
to authenticated
using (
  public.current_user_is_admin()
  or id = public.current_user_branch_id()
  or public.current_user_role() = 'auditor'
);

drop policy if exists branches_admin_insert on public.branches;
create policy branches_admin_insert
on public.branches
for insert
to authenticated
with check (public.current_user_is_admin());

drop policy if exists branches_admin_update on public.branches;
create policy branches_admin_update
on public.branches
for update
to authenticated
using (public.current_user_is_admin())
with check (public.current_user_is_admin());

drop policy if exists branch_settings_select_by_role on public.branch_settings;
create policy branch_settings_select_by_role
on public.branch_settings
for select
to authenticated
using (
  public.current_user_is_admin()
  or branch_id = public.current_user_branch_id()
  or public.current_user_role() = 'auditor'
);

drop policy if exists branch_settings_admin_write on public.branch_settings;
create policy branch_settings_admin_write
on public.branch_settings
for all
to authenticated
using (public.current_user_is_admin())
with check (public.current_user_is_admin());

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.user_profiles (id, email, full_name, role, is_active)
  values (
    new.id,
    coalesce(new.email, ''),
    coalesce(nullif(new.raw_user_meta_data->>'full_name', ''), split_part(coalesce(new.email, 'New User'), '@', 1)),
    'cashier',
    false
  )
  on conflict (id) do nothing;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_auth_user();

create or replace function public.auth_get_current_profile()
returns jsonb
language plpgsql
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

  return jsonb_build_object(
    'profile',
    case
      when v_profile.id is null then null
      else jsonb_build_object(
        'id', v_profile.id,
        'full_name', v_profile.full_name,
        'email', v_profile.email,
        'role', v_profile.role,
        'branch_id', v_profile.branch_id,
        'is_active', v_profile.is_active
      )
    end,
    'has_admin', exists (
      select 1
      from public.user_profiles
      where role = 'admin'
        and is_active = true
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
  v_email text := coalesce(auth.jwt()->>'email', '');
  v_name text := coalesce(nullif(trim(p_full_name), ''), split_part(v_email, '@', 1), 'Admin');
begin
  if auth.uid() is null then
    raise exception 'Not authenticated' using errcode = '28000';
  end if;

  if exists (select 1 from public.user_profiles where role = 'admin' and is_active = true) then
    raise exception 'First admin already exists' using errcode = '23505';
  end if;

  insert into public.user_profiles (id, email, full_name, role, is_active)
  values (auth.uid(), v_email, v_name, 'admin', true)
  on conflict (id) do update
  set email = excluded.email,
      full_name = excluded.full_name,
      role = 'admin',
      branch_id = null,
      is_active = true,
      updated_at = now();

  return public.auth_get_current_profile();
end;
$$;

revoke all on function public.auth_get_current_profile() from public;
revoke all on function public.auth_bootstrap_first_admin(text) from public;
grant execute on function public.auth_get_current_profile() to authenticated;
grant execute on function public.auth_bootstrap_first_admin(text) to authenticated;

create or replace function public.branch_management_get()
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

  with scoped_branches as (
    select b.*
    from public.branches b
    where
      v_profile.role in ('admin', 'auditor')
      or b.id = v_profile.branch_id
  ),
  branch_rows as (
    select
      b.id,
      b.branch_code,
      b.name,
      b.legal_name,
      b.tin,
      b.business_style,
      b.is_head_office,
      b.bir_rdo_code,
      b.bir_rdo_name,
      b.address,
      b.contact_person,
      b.contact_phone,
      b.contact_email,
      b.is_active,
      b.created_at,
      b.updated_at,
      bs.pricing_mode,
      bs.tax_profile,
      bs.vat_rate,
      bs.inventory_control,
      bs.allow_negative_stock,
      bs.receipt_footer,
      coalesce(up.users_count, 0)::integer as users_count,
      coalesce(inv.stock_items, 0)::integer as stock_items,
      coalesce(inv.stock_units, 0)::integer as stock_units,
      coalesce(sales.total_sales, 0)::numeric(14, 2) as total_sales,
      sales.last_sale_at
    from scoped_branches b
    left join public.branch_settings bs on bs.branch_id = b.id
    left join lateral (
      select count(*)::integer as users_count
      from public.user_profiles up
      where up.branch_id = b.id
    ) up on true
    left join lateral (
      select
        count(*)::integer as stock_items,
        coalesce(sum(quantity_on_hand), 0)::integer as stock_units
      from public.branch_inventory bi
      where bi.branch_id = b.id
    ) inv on true
    left join lateral (
      select
        coalesce(sum(total), 0)::numeric(14, 2) as total_sales,
        max(created_at) as last_sale_at
      from public.sales_orders so
      where so.branch_id = b.id
        and so.status = 'completed'
    ) sales on true
  )
  select jsonb_build_object(
    'summary', jsonb_build_object(
      'total_branches', coalesce((select count(*) from scoped_branches), 0),
      'active_branches', coalesce((select count(*) from scoped_branches where is_active = true), 0),
      'head_offices', coalesce((select count(*) from scoped_branches where is_head_office = true), 0),
      'users_assigned', coalesce((select count(*) from public.user_profiles up join scoped_branches b on b.id = up.branch_id), 0),
      'stock_units', coalesce((select sum(quantity_on_hand) from public.branch_inventory bi join scoped_branches b on b.id = bi.branch_id), 0)
    ),
    'branches', coalesce((
      select jsonb_agg(to_jsonb(branch_rows) order by is_head_office desc, is_active desc, name asc)
      from branch_rows
    ), '[]'::jsonb),
    'generated_at', now()
  )
  into v_result;

  return v_result;
end;
$$;

create or replace function public.branch_create(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_branch_id uuid;
  v_branch_code text := upper(trim(coalesce(p_payload->>'branch_code', '')));
  v_name text := trim(coalesce(p_payload->>'name', ''));
  v_is_head_office boolean := coalesce((p_payload->>'is_head_office')::boolean, false);
begin
  if public.current_user_is_admin() = false then
    raise exception 'Only admins can create branches' using errcode = '42501';
  end if;

  if v_branch_code = '' or v_name = '' then
    raise exception 'Branch code and name are required' using errcode = '23502';
  end if;

  if v_is_head_office then
    update public.branches set is_head_office = false where is_head_office = true;
  end if;

  insert into public.branches (
    branch_code,
    name,
    legal_name,
    tin,
    business_style,
    is_head_office,
    bir_rdo_code,
    bir_rdo_name,
    address,
    contact_person,
    contact_phone,
    contact_email,
    is_active
  )
  values (
    v_branch_code,
    v_name,
    nullif(trim(coalesce(p_payload->>'legal_name', '')), ''),
    nullif(trim(coalesce(p_payload->>'tin', '')), ''),
    nullif(trim(coalesce(p_payload->>'business_style', '')), ''),
    v_is_head_office,
    nullif(trim(coalesce(p_payload->>'bir_rdo_code', '')), ''),
    nullif(trim(coalesce(p_payload->>'bir_rdo_name', '')), ''),
    nullif(trim(coalesce(p_payload->>'address', '')), ''),
    nullif(trim(coalesce(p_payload->>'contact_person', '')), ''),
    nullif(trim(coalesce(p_payload->>'contact_phone', '')), ''),
    nullif(trim(coalesce(p_payload->>'contact_email', '')), ''),
    coalesce((p_payload->>'is_active')::boolean, true)
  )
  returning id into v_branch_id;

  insert into public.branch_settings (
    branch_id,
    pricing_mode,
    tax_profile,
    vat_rate,
    inventory_control,
    allow_negative_stock,
    receipt_footer
  )
  values (
    v_branch_id,
    coalesce(nullif(p_payload->>'pricing_mode', ''), 'standard'),
    coalesce(nullif(p_payload->>'tax_profile', ''), 'vat_12'),
    coalesce((p_payload->>'vat_rate')::numeric, 12.00),
    coalesce(nullif(p_payload->>'inventory_control', ''), 'branch_stock'),
    coalesce((p_payload->>'allow_negative_stock')::boolean, false),
    nullif(trim(coalesce(p_payload->>'receipt_footer', '')), '')
  );

  return public.branch_management_get();
end;
$$;

create or replace function public.branch_update(p_branch_id uuid, p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_branch_code text := upper(trim(coalesce(p_payload->>'branch_code', '')));
  v_name text := trim(coalesce(p_payload->>'name', ''));
  v_is_head_office boolean := coalesce((p_payload->>'is_head_office')::boolean, false);
begin
  if public.current_user_is_admin() = false then
    raise exception 'Only admins can update branches' using errcode = '42501';
  end if;

  if v_branch_code = '' or v_name = '' then
    raise exception 'Branch code and name are required' using errcode = '23502';
  end if;

  if v_is_head_office then
    update public.branches
    set is_head_office = false
    where is_head_office = true
      and id <> p_branch_id;
  end if;

  update public.branches
  set branch_code = v_branch_code,
      name = v_name,
      legal_name = nullif(trim(coalesce(p_payload->>'legal_name', '')), ''),
      tin = nullif(trim(coalesce(p_payload->>'tin', '')), ''),
      business_style = nullif(trim(coalesce(p_payload->>'business_style', '')), ''),
      is_head_office = v_is_head_office,
      bir_rdo_code = nullif(trim(coalesce(p_payload->>'bir_rdo_code', '')), ''),
      bir_rdo_name = nullif(trim(coalesce(p_payload->>'bir_rdo_name', '')), ''),
      address = nullif(trim(coalesce(p_payload->>'address', '')), ''),
      contact_person = nullif(trim(coalesce(p_payload->>'contact_person', '')), ''),
      contact_phone = nullif(trim(coalesce(p_payload->>'contact_phone', '')), ''),
      contact_email = nullif(trim(coalesce(p_payload->>'contact_email', '')), ''),
      is_active = coalesce((p_payload->>'is_active')::boolean, true)
  where id = p_branch_id;

  if not found then
    raise exception 'Branch not found' using errcode = '02000';
  end if;

  insert into public.branch_settings (
    branch_id,
    pricing_mode,
    tax_profile,
    vat_rate,
    inventory_control,
    allow_negative_stock,
    receipt_footer
  )
  values (
    p_branch_id,
    coalesce(nullif(p_payload->>'pricing_mode', ''), 'standard'),
    coalesce(nullif(p_payload->>'tax_profile', ''), 'vat_12'),
    coalesce((p_payload->>'vat_rate')::numeric, 12.00),
    coalesce(nullif(p_payload->>'inventory_control', ''), 'branch_stock'),
    coalesce((p_payload->>'allow_negative_stock')::boolean, false),
    nullif(trim(coalesce(p_payload->>'receipt_footer', '')), '')
  )
  on conflict (branch_id) do update
  set pricing_mode = excluded.pricing_mode,
      tax_profile = excluded.tax_profile,
      vat_rate = excluded.vat_rate,
      inventory_control = excluded.inventory_control,
      allow_negative_stock = excluded.allow_negative_stock,
      receipt_footer = excluded.receipt_footer,
      updated_at = now();

  return public.branch_management_get();
end;
$$;

create or replace function public.branch_set_active(p_branch_id uuid, p_is_active boolean)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_is_head_office boolean;
begin
  if public.current_user_is_admin() = false then
    raise exception 'Only admins can change branch status' using errcode = '42501';
  end if;

  select is_head_office
  into v_is_head_office
  from public.branches
  where id = p_branch_id;

  if not found then
    raise exception 'Branch not found' using errcode = '02000';
  end if;

  if v_is_head_office and p_is_active = false then
    raise exception 'Head office cannot be disabled' using errcode = '23514';
  end if;

  update public.branches
  set is_active = p_is_active
  where id = p_branch_id;

  return public.branch_management_get();
end;
$$;

create or replace function public.branch_hard_delete(p_branch_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor public.user_profiles;
  v_branch public.branches;
  v_blockers text[] := array[]::text[];
  v_count integer;
begin
  v_actor := public.ensure_active_user();

  if v_actor.role <> 'admin' then
    raise exception 'Only admins can hard delete branches' using errcode = '42501';
  end if;

  select *
  into v_branch
  from public.branches
  where id = p_branch_id
  limit 1;

  if v_branch.id is null then
    raise exception 'Branch not found' using errcode = '02000';
  end if;

  if v_branch.is_head_office then
    raise exception 'Head office cannot be hard deleted' using errcode = '23514';
  end if;

  select count(*)::integer
  into v_count
  from public.sales_orders
  where branch_id = p_branch_id;

  if v_count > 0 then
    v_blockers := array_append(v_blockers, v_count || ' sales order(s)');
  end if;

  select count(*)::integer
  into v_count
  from public.cashiers
  where branch_id = p_branch_id;

  if v_count > 0 then
    v_blockers := array_append(v_blockers, v_count || ' cashier record(s)');
  end if;

  select count(*)::integer
  into v_count
  from public.user_profiles
  where branch_id = p_branch_id;

  if v_count > 0 then
    v_blockers := array_append(v_blockers, v_count || ' assigned user(s)');
  end if;

  select count(*)::integer
  into v_count
  from public.branch_inventory
  where branch_id = p_branch_id
    and quantity_on_hand > 0;

  if v_count > 0 then
    v_blockers := array_append(v_blockers, v_count || ' stocked item(s)');
  end if;

  if to_regclass('public.inventory_batches') is not null then
    execute
      'select count(*)::integer from public.inventory_batches where branch_id = $1 and quantity_on_hand > 0'
    into v_count
    using p_branch_id;

    if v_count > 0 then
      v_blockers := array_append(v_blockers, v_count || ' active inventory batch(es)');
    end if;
  end if;

  if to_regclass('public.inventory_movements') is not null then
    execute
      'select count(*)::integer from public.inventory_movements where branch_id = $1'
    into v_count
    using p_branch_id;

    if v_count > 0 then
      v_blockers := array_append(v_blockers, v_count || ' inventory movement(s)');
    end if;
  end if;

  if to_regclass('public.stock_counts') is not null then
    execute
      'select count(*)::integer from public.stock_counts where branch_id = $1'
    into v_count
    using p_branch_id;

    if v_count > 0 then
      v_blockers := array_append(v_blockers, v_count || ' stock count(s)');
    end if;
  end if;

  if array_length(v_blockers, 1) is not null then
    raise exception
      'Branch cannot be hard deleted because it has linked %. Disable it instead.',
      array_to_string(v_blockers, ', ')
      using errcode = '23503';
  end if;

  delete from public.branch_inventory
  where branch_id = p_branch_id;

  delete from public.branches
  where id = p_branch_id;

  if to_regprocedure('public.log_activity(text,text,text,jsonb,uuid)') is not null then
    execute
      'select public.log_activity($1, $2, $3, $4, $5)'
    using
      'branch.hard_deleted',
      'branch',
      p_branch_id::text,
      jsonb_build_object('branch_code', v_branch.branch_code, 'name', v_branch.name),
      v_actor.id;
  end if;

  return public.branch_management_get();
end;
$$;

revoke all on function public.branch_management_get() from public;
revoke all on function public.branch_create(jsonb) from public;
revoke all on function public.branch_update(uuid, jsonb) from public;
revoke all on function public.branch_set_active(uuid, boolean) from public;
revoke all on function public.branch_hard_delete(uuid) from public;
grant execute on function public.branch_management_get() to authenticated;
grant execute on function public.branch_create(jsonb) to authenticated;
grant execute on function public.branch_update(uuid, jsonb) to authenticated;
grant execute on function public.branch_set_active(uuid, boolean) to authenticated;
grant execute on function public.branch_hard_delete(uuid) to authenticated;

-- Replace the Module 1 dashboard RPC with role-aware access.
create or replace function public.dashboard_get_metrics(
  p_from date default current_date - 6,
  p_to date default current_date,
  p_branch_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_from date := coalesce(p_from, current_date - 6);
  v_to date := coalesce(p_to, current_date);
  v_profile public.user_profiles;
  v_effective_branch_id uuid;
  v_result jsonb;
begin
  v_profile := public.ensure_active_user();

  if v_to < v_from then
    raise exception 'To date must be after from date' using errcode = '22007';
  end if;

  if v_profile.role in ('admin', 'auditor') then
    v_effective_branch_id := p_branch_id;
  else
    v_effective_branch_id := v_profile.branch_id;
  end if;

  with scoped_orders as (
    select o.*
    from public.sales_orders o
    where o.status = 'completed'
      and o.business_date >= v_from
      and o.business_date <= v_to
      and (v_effective_branch_id is null or o.branch_id = v_effective_branch_id)
  ),
  branch_sales as (
    select
      b.id as branch_id,
      b.branch_code,
      b.name as branch_name,
      count(o.id)::integer as orders,
      coalesce(sum(o.total), 0)::numeric(14, 2) as sales,
      coalesce(sum(o.discount_total), 0)::numeric(14, 2) as discounts,
      coalesce(sum(o.tax_total), 0)::numeric(14, 2) as vat
    from public.branches b
    left join scoped_orders o on o.branch_id = b.id
    where b.is_active = true
      and (v_effective_branch_id is null or b.id = v_effective_branch_id)
    group by b.id, b.branch_code, b.name
  ),
  cashier_sales as (
    select
      c.id as cashier_id,
      c.employee_code,
      c.name as cashier_name,
      b.name as branch_name,
      count(o.id)::integer as orders,
      coalesce(sum(o.total), 0)::numeric(14, 2) as sales,
      coalesce(avg(o.total), 0)::numeric(14, 2) as average_order
    from public.cashiers c
    join public.branches b on b.id = c.branch_id
    left join scoped_orders o on o.cashier_id = c.id
    where c.is_active = true
      and (v_effective_branch_id is null or c.branch_id = v_effective_branch_id)
    group by c.id, c.employee_code, c.name, b.name
  ),
  low_stock as (
    select
      bi.id,
      b.branch_code,
      b.name as branch_name,
      p.sku,
      p.barcode,
      p.name as product_name,
      p.category,
      bi.quantity_on_hand,
      p.reorder_level,
      case
        when bi.quantity_on_hand = 0 then 'critical'
        when bi.quantity_on_hand <= greatest(1, floor(p.reorder_level * 0.5)) then 'high'
        else 'medium'
      end as severity
    from public.branch_inventory bi
    join public.branches b on b.id = bi.branch_id
    join public.products p on p.id = bi.product_id
    where p.is_active = true
      and b.is_active = true
      and bi.quantity_on_hand <= p.reorder_level
      and (v_effective_branch_id is null or bi.branch_id = v_effective_branch_id)
    order by bi.quantity_on_hand asc, p.name asc
    limit 25
  )
  select jsonb_build_object(
    'period', jsonb_build_object('from', v_from, 'to', v_to),
    'totals', jsonb_build_object(
      'sales', coalesce((select sum(total) from scoped_orders), 0),
      'orders', coalesce((select count(*) from scoped_orders), 0),
      'discounts', coalesce((select sum(discount_total) from scoped_orders), 0),
      'vat', coalesce((select sum(tax_total) from scoped_orders), 0),
      'average_order', case
        when coalesce((select count(*) from scoped_orders), 0) = 0 then 0
        else coalesce((select sum(total) from scoped_orders), 0) / (select count(*) from scoped_orders)
      end,
      'low_stock_count', (select count(*) from low_stock)
    ),
    'branches', (
      select coalesce(jsonb_agg(
        jsonb_build_object(
          'id', b.id,
          'branch_code', b.branch_code,
          'name', b.name,
          'is_head_office', b.is_head_office
        )
        order by b.is_head_office desc, b.name
      ), '[]'::jsonb)
      from public.branches b
      where b.is_active = true
        and (v_effective_branch_id is null or b.id = v_effective_branch_id)
    ),
    'sales_by_branch', (
      select coalesce(jsonb_agg(
        jsonb_build_object(
          'branch_id', bs.branch_id,
          'branch_code', bs.branch_code,
          'label', bs.branch_name,
          'branch_name', bs.branch_name,
          'orders', bs.orders,
          'sales', bs.sales,
          'discounts', bs.discounts,
          'vat', bs.vat
        )
        order by bs.sales desc, bs.branch_name
      ), '[]'::jsonb)
      from branch_sales bs
    ),
    'daily_sales', (
      select coalesce(jsonb_agg(
        jsonb_build_object(
          'date', d.day,
          'label', to_char(d.day, 'Mon DD'),
          'orders', coalesce(s.orders, 0),
          'sales', coalesce(s.sales, 0)
        )
        order by d.day
      ), '[]'::jsonb)
      from generate_series(v_from, v_to, interval '1 day') as d(day)
      left join lateral (
        select count(*)::integer as orders, coalesce(sum(o.total), 0)::numeric(14, 2) as sales
        from scoped_orders o
        where o.business_date = d.day::date
      ) s on true
    ),
    'cashier_performance', (
      select coalesce(jsonb_agg(
        jsonb_build_object(
          'cashier_id', cs.cashier_id,
          'employee_code', cs.employee_code,
          'label', cs.cashier_name,
          'cashier_name', cs.cashier_name,
          'branch_name', cs.branch_name,
          'orders', cs.orders,
          'sales', cs.sales,
          'average_order', cs.average_order
        )
        order by cs.sales desc, cs.cashier_name
      ), '[]'::jsonb)
      from cashier_sales cs
    ),
    'low_stock_alerts', (
      select coalesce(jsonb_agg(to_jsonb(ls) order by ls.quantity_on_hand asc, ls.product_name), '[]'::jsonb)
      from low_stock ls
    ),
    'generated_at', now()
  )
  into v_result;

  return v_result;
end;
$$;

revoke all on function public.dashboard_get_metrics(date, date, uuid) from public;
grant execute on function public.dashboard_get_metrics(date, date, uuid) to authenticated;

notify pgrst, 'reload schema';
