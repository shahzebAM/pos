-- MODULE 12: CASH REGISTER / SHIFT MANAGEMENT
-- Run after:
-- 1. supabase/00-reset-public-schema.sql
-- 2. supabase/01-dashboard-module.sql
-- 3. supabase/02-auth-and-branch-management.sql
-- 4. supabase/03-user-role-management.sql
-- 5. supabase/04-product-management.sql
-- 6. supabase/05-inventory-management.sql
-- 7. supabase/06-stock-transfer.sql
-- 8. supabase/07-pos-sales-checkout.sql
-- 9. supabase/08-bir-compliance.sql
-- 10. supabase/09-tax-management.sql
-- 11. supabase/10-senior-pwd-discounts.sql
-- 12. supabase/11-payments.sql
--
-- Scope:
-- - Cash register setup per branch
-- - Opening cash
-- - Cash in / cash out
-- - Cashier shift closing
-- - Short/over tracking
-- - End-of-day shift report
-- - POS sales automatically linked to the cashier's open shift

create extension if not exists pgcrypto;

create table if not exists public.cash_registers (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches(id) on delete cascade,
  register_code text not null,
  name text not null,
  is_default boolean not null default false,
  is_active boolean not null default true,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (branch_id, register_code)
);

create unique index if not exists idx_cash_registers_default
on public.cash_registers(branch_id)
where is_default = true;

drop trigger if exists set_cash_registers_updated_at on public.cash_registers;
create trigger set_cash_registers_updated_at
before update on public.cash_registers
for each row execute function public.set_updated_at();

create table if not exists public.cashier_shifts (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches(id) on delete restrict,
  cash_register_id uuid not null references public.cash_registers(id) on delete restrict,
  user_id uuid not null references public.user_profiles(id) on delete restrict,
  cashier_id uuid references public.cashiers(id) on delete set null,
  shift_number text not null unique,
  business_date date not null default current_date,
  status text not null default 'open',
  opened_at timestamptz not null default now(),
  closed_at timestamptz,
  opening_cash numeric(14, 2) not null default 0,
  cash_sales numeric(14, 2) not null default 0,
  non_cash_sales numeric(14, 2) not null default 0,
  total_sales numeric(14, 2) not null default 0,
  cash_in_total numeric(14, 2) not null default 0,
  cash_out_total numeric(14, 2) not null default 0,
  change_given_total numeric(14, 2) not null default 0,
  expected_cash numeric(14, 2) not null default 0,
  counted_cash numeric(14, 2),
  short_over numeric(14, 2),
  opening_notes text,
  closing_notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint cashier_shifts_status_check check (status in ('open', 'closing', 'closed', 'void')),
  constraint cashier_shifts_amounts_check check (
    opening_cash >= 0
    and cash_sales >= 0
    and non_cash_sales >= 0
    and total_sales >= 0
    and cash_in_total >= 0
    and cash_out_total >= 0
    and change_given_total >= 0
    and expected_cash >= 0
    and (counted_cash is null or counted_cash >= 0)
  )
);

create unique index if not exists idx_cashier_shifts_one_open_user
on public.cashier_shifts(user_id)
where status = 'open';

create index if not exists idx_cashier_shifts_branch_date
on public.cashier_shifts(branch_id, business_date desc);

create index if not exists idx_cashier_shifts_register_status
on public.cashier_shifts(cash_register_id, status);

drop trigger if exists set_cashier_shifts_updated_at on public.cashier_shifts;
create trigger set_cashier_shifts_updated_at
before update on public.cashier_shifts
for each row execute function public.set_updated_at();

create table if not exists public.cash_drawer_movements (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches(id) on delete restrict,
  cash_register_id uuid not null references public.cash_registers(id) on delete restrict,
  shift_id uuid not null references public.cashier_shifts(id) on delete cascade,
  user_id uuid not null references public.user_profiles(id) on delete restrict,
  movement_type text not null,
  direction text not null,
  amount numeric(14, 2) not null check (amount >= 0),
  reference_type text,
  reference_id uuid,
  reason text,
  created_at timestamptz not null default now(),
  constraint cash_drawer_movements_type_check check (
    movement_type in ('opening', 'cash_in', 'cash_out', 'sale_cash', 'change_given', 'closing_adjustment')
  ),
  constraint cash_drawer_movements_direction_check check (direction in ('in', 'out', 'neutral'))
);

create index if not exists idx_cash_drawer_movements_shift
on public.cash_drawer_movements(shift_id, created_at desc);

create index if not exists idx_cash_drawer_movements_branch
on public.cash_drawer_movements(branch_id, created_at desc);

alter table public.sales_orders
  add column if not exists shift_id uuid references public.cashier_shifts(id) on delete set null;

create index if not exists idx_sales_orders_shift
on public.sales_orders(shift_id, business_date desc);

alter table public.cash_registers enable row level security;
alter table public.cashier_shifts enable row level security;
alter table public.cash_drawer_movements enable row level security;

insert into public.cash_registers (branch_id, register_code, name, is_default, is_active)
select b.id, 'REG-01', 'Main Register', true, true
from public.branches b
where not exists (
  select 1
  from public.cash_registers cr
  where cr.branch_id = b.id
)
on conflict (branch_id, register_code) do nothing;

create or replace function public.shift_user_can_view(p_branch_id uuid, p_user_id uuid default null)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_profile public.user_profiles;
  v_permissions text[] := array[]::text[];
begin
  v_profile := public.ensure_active_user();

  select coalesce(permissions, array[]::text[])
  into v_permissions
  from public.user_access_settings
  where user_id = v_profile.id;

  if v_profile.role = 'admin' then
    return true;
  end if;

  if not coalesce('shifts.view' = any(v_permissions), false) then
    return false;
  end if;

  if v_profile.role = 'auditor' then
    return true;
  end if;

  if v_profile.role = 'manager' and v_profile.branch_id = p_branch_id then
    return true;
  end if;

  if v_profile.role = 'cashier'
    and v_profile.branch_id = p_branch_id
    and coalesce(p_user_id, v_profile.id) = v_profile.id then
    return true;
  end if;

  return false;
end;
$$;

create or replace function public.shift_user_can_manage_branch(p_branch_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_profile public.user_profiles;
  v_permissions text[] := array[]::text[];
begin
  v_profile := public.ensure_active_user();

  select coalesce(permissions, array[]::text[])
  into v_permissions
  from public.user_access_settings
  where user_id = v_profile.id;

  if v_profile.role = 'admin' then
    return true;
  end if;

  return v_profile.role = 'manager'
    and v_profile.branch_id = p_branch_id
    and coalesce('shifts.manage' = any(v_permissions), false);
end;
$$;

create or replace function public.shift_user_can_open(p_branch_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_profile public.user_profiles;
  v_access public.user_access_settings;
begin
  v_profile := public.ensure_active_user();

  select *
  into v_access
  from public.user_access_settings
  where user_id = v_profile.id;

  if coalesce(v_access.can_open_shift, true) = false then
    return false;
  end if;

  if v_profile.role = 'admin' then
    return true;
  end if;

  return v_profile.role in ('manager', 'cashier')
    and v_profile.branch_id = p_branch_id;
end;
$$;

create or replace function public.shift_user_can_close(p_shift_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_profile public.user_profiles;
  v_access public.user_access_settings;
  v_shift public.cashier_shifts;
begin
  v_profile := public.ensure_active_user();

  select *
  into v_shift
  from public.cashier_shifts
  where id = p_shift_id;

  if v_shift.id is null then
    return false;
  end if;

  if public.shift_user_can_manage_branch(v_shift.branch_id) then
    return true;
  end if;

  select *
  into v_access
  from public.user_access_settings
  where user_id = v_profile.id;

  return v_shift.user_id = v_profile.id
    and coalesce(v_access.can_close_shift, false) = true;
end;
$$;

drop policy if exists cash_registers_select_by_role on public.cash_registers;
create policy cash_registers_select_by_role
on public.cash_registers
for select
to authenticated
using (public.shift_user_can_view(branch_id, null));

drop policy if exists cashier_shifts_select_by_role on public.cashier_shifts;
create policy cashier_shifts_select_by_role
on public.cashier_shifts
for select
to authenticated
using (public.shift_user_can_view(branch_id, user_id));

drop policy if exists cash_drawer_movements_select_by_role on public.cash_drawer_movements;
create policy cash_drawer_movements_select_by_role
on public.cash_drawer_movements
for select
to authenticated
using (public.shift_user_can_view(branch_id, user_id));

create or replace function public.shift_recalculate(p_shift_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_shift public.cashier_shifts;
  v_cash_sales numeric(14, 2) := 0;
  v_non_cash_sales numeric(14, 2) := 0;
  v_total_sales numeric(14, 2) := 0;
  v_cash_in_total numeric(14, 2) := 0;
  v_cash_out_total numeric(14, 2) := 0;
  v_change_given_total numeric(14, 2) := 0;
  v_expected_cash numeric(14, 2) := 0;
begin
  select *
  into v_shift
  from public.cashier_shifts
  where id = p_shift_id
  for update;

  if v_shift.id is null then
    return;
  end if;

  select
    coalesce(sum(case when sop.method = 'cash' then sop.amount else 0 end), 0)::numeric(14, 2),
    coalesce(sum(case when sop.method <> 'cash' then sop.amount else 0 end), 0)::numeric(14, 2),
    coalesce(sum(case when sop.method = 'cash' then coalesce(sop.change_amount, 0) else 0 end), 0)::numeric(14, 2)
  into v_cash_sales, v_non_cash_sales, v_change_given_total
  from public.sales_order_payments sop
  join public.sales_orders so on so.id = sop.order_id
  where so.shift_id = p_shift_id
    and so.status = 'completed';

  select coalesce(sum(total), 0)::numeric(14, 2)
  into v_total_sales
  from public.sales_orders
  where shift_id = p_shift_id
    and status = 'completed';

  select
    coalesce(sum(case when movement_type = 'cash_in' then amount else 0 end), 0)::numeric(14, 2),
    coalesce(sum(case when movement_type = 'cash_out' then amount else 0 end), 0)::numeric(14, 2)
  into v_cash_in_total, v_cash_out_total
  from public.cash_drawer_movements
  where shift_id = p_shift_id;

  v_expected_cash := greatest(round(v_shift.opening_cash + v_cash_sales + v_cash_in_total - v_cash_out_total, 2), 0);

  update public.cashier_shifts
  set cash_sales = v_cash_sales,
      non_cash_sales = v_non_cash_sales,
      total_sales = v_total_sales,
      cash_in_total = v_cash_in_total,
      cash_out_total = v_cash_out_total,
      change_given_total = v_change_given_total,
      expected_cash = v_expected_cash,
      short_over = case
        when counted_cash is null then null
        else round(counted_cash - v_expected_cash, 2)
      end
  where id = p_shift_id;
end;
$$;

create or replace function public.shift_visible_branch_ids(p_profile public.user_profiles)
returns uuid[]
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_branch_ids uuid[];
begin
  if p_profile.role in ('admin', 'auditor') then
    select array_agg(id order by is_head_office desc, name)
    into v_branch_ids
    from public.branches
    where is_active = true;
  else
    v_branch_ids := array[p_profile.branch_id];
  end if;

  return coalesce(v_branch_ids, array[]::uuid[]);
end;
$$;

create or replace function public.shift_pos_status_get(p_branch_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.user_profiles;
  v_branch_id uuid;
  v_result jsonb;
begin
  v_profile := public.ensure_active_user();

  if v_profile.role = 'admin' then
    v_branch_id := p_branch_id;
  else
    v_branch_id := v_profile.branch_id;
  end if;

  if v_branch_id is null then
    select id
    into v_branch_id
    from public.branches
    where is_active = true
    order by is_head_office desc, name
    limit 1;
  end if;

  select jsonb_build_object(
    'shift_installed', true,
    'can_open_shift', public.shift_user_can_open(v_branch_id),
    'current_shift', (
      select jsonb_build_object(
        'id', cs.id,
        'shift_number', cs.shift_number,
        'business_date', cs.business_date,
        'status', cs.status,
        'opened_at', cs.opened_at,
        'opening_cash', cs.opening_cash,
        'cash_sales', cs.cash_sales,
        'cash_in_total', cs.cash_in_total,
        'cash_out_total', cs.cash_out_total,
        'expected_cash', cs.expected_cash,
        'register_id', cr.id,
        'register_code', cr.register_code,
        'register_name', cr.name
      )
      from public.cashier_shifts cs
      join public.cash_registers cr on cr.id = cs.cash_register_id
      where cs.branch_id = v_branch_id
        and cs.user_id = v_profile.id
        and cs.status = 'open'
      order by cs.opened_at desc
      limit 1
    ),
    'registers', (
      select coalesce(jsonb_agg(
        jsonb_build_object(
          'id', cr.id,
          'branch_id', cr.branch_id,
          'register_code', cr.register_code,
          'name', cr.name,
          'is_default', cr.is_default,
          'is_active', cr.is_active
        )
        order by cr.is_default desc, cr.name
      ), '[]'::jsonb)
      from public.cash_registers cr
      where cr.branch_id = v_branch_id
        and cr.is_active = true
    )
  )
  into v_result;

  return v_result;
end;
$$;

create or replace function public.shift_management_get(
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
  v_profile public.user_profiles;
  v_from date := coalesce(p_from, current_date - 6);
  v_to date := coalesce(p_to, current_date);
  v_branch_filter uuid;
  v_branch_ids uuid[];
  v_result jsonb;
begin
  v_profile := public.ensure_active_user();

  if v_to < v_from then
    raise exception 'To date must be after from date' using errcode = '22007';
  end if;

  if v_profile.role = 'cashier' then
    v_branch_filter := v_profile.branch_id;
  elsif v_profile.role = 'manager' then
    v_branch_filter := coalesce(p_branch_id, v_profile.branch_id);
    if v_branch_filter <> v_profile.branch_id then
      raise exception 'Managers can only view their assigned branch shifts' using errcode = '42501';
    end if;
  else
    v_branch_filter := p_branch_id;
  end if;

  v_branch_ids := public.shift_visible_branch_ids(v_profile);

  with visible_branches as (
    select b.*
    from public.branches b
    where b.is_active = true
      and b.id = any(v_branch_ids)
      and (v_branch_filter is null or b.id = v_branch_filter)
  ),
  scoped_shifts as (
    select
      cs.*,
      b.branch_code,
      b.name as branch_name,
      cr.register_code,
      cr.name as register_name,
      up.full_name as cashier_name,
      up.username as cashier_username
    from public.cashier_shifts cs
    join visible_branches b on b.id = cs.branch_id
    join public.cash_registers cr on cr.id = cs.cash_register_id
    join public.user_profiles up on up.id = cs.user_id
    where cs.business_date >= v_from
      and cs.business_date <= v_to
      and (v_profile.role <> 'cashier' or cs.user_id = v_profile.id)
  ),
  scoped_movements as (
    select
      cdm.*,
      ss.shift_number,
      ss.branch_code,
      ss.branch_name,
      ss.register_code,
      ss.register_name,
      up.full_name as actor_name,
      up.username as actor_username
    from public.cash_drawer_movements cdm
    join scoped_shifts ss on ss.id = cdm.shift_id
    join public.user_profiles up on up.id = cdm.user_id
  ),
  branch_summary as (
    select
      vb.id as branch_id,
      vb.branch_code,
      vb.name as branch_name,
      coalesce(count(ss.id) filter (where ss.status = 'open'), 0)::integer as open_shifts,
      coalesce(count(ss.id) filter (where ss.status = 'closed'), 0)::integer as closed_shifts,
      coalesce(sum(ss.cash_sales), 0)::numeric(14, 2) as cash_sales,
      coalesce(sum(ss.non_cash_sales), 0)::numeric(14, 2) as non_cash_sales,
      coalesce(sum(ss.cash_in_total), 0)::numeric(14, 2) as cash_in_total,
      coalesce(sum(ss.cash_out_total), 0)::numeric(14, 2) as cash_out_total,
      coalesce(sum(ss.short_over), 0)::numeric(14, 2) as short_over
    from visible_branches vb
    left join scoped_shifts ss on ss.branch_id = vb.id
    group by vb.id, vb.branch_code, vb.name
  ),
  daily_shifts as (
    select
      ss.business_date,
      to_char(ss.business_date, 'Mon DD') as label,
      count(ss.id)::integer as shifts,
      coalesce(sum(ss.cash_sales), 0)::numeric(14, 2) as cash_sales,
      coalesce(sum(ss.total_sales), 0)::numeric(14, 2) as total_sales,
      coalesce(sum(ss.short_over), 0)::numeric(14, 2) as short_over
    from scoped_shifts ss
    group by ss.business_date
  )
  select jsonb_build_object(
    'period', jsonb_build_object('from', v_from, 'to', v_to),
    'branches', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', id,
          'branch_code', branch_code,
          'name', name,
          'is_head_office', is_head_office
        )
        order by is_head_office desc, name
      )
      from visible_branches
    ), '[]'::jsonb),
    'registers', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', cr.id,
          'branch_id', cr.branch_id,
          'branch_code', vb.branch_code,
          'branch_name', vb.name,
          'register_code', cr.register_code,
          'name', cr.name,
          'is_default', cr.is_default,
          'is_active', cr.is_active,
          'notes', cr.notes
        )
        order by vb.name, cr.is_default desc, cr.name
      )
      from public.cash_registers cr
      join visible_branches vb on vb.id = cr.branch_id
    ), '[]'::jsonb),
    'current_shift', (
      select to_jsonb(x)
      from (
        select *
        from scoped_shifts
        where status = 'open'
          and user_id = v_profile.id
        order by opened_at desc
        limit 1
      ) x
    ),
    'summary', jsonb_build_object(
      'open_shifts', coalesce((select count(*) from scoped_shifts where status = 'open'), 0),
      'closed_shifts', coalesce((select count(*) from scoped_shifts where status = 'closed'), 0),
      'cash_sales', coalesce((select sum(cash_sales) from scoped_shifts), 0),
      'non_cash_sales', coalesce((select sum(non_cash_sales) from scoped_shifts), 0),
      'cash_in_total', coalesce((select sum(cash_in_total) from scoped_shifts), 0),
      'cash_out_total', coalesce((select sum(cash_out_total) from scoped_shifts), 0),
      'expected_cash', coalesce((select sum(expected_cash) from scoped_shifts where status = 'open'), 0),
      'counted_cash', coalesce((select sum(counted_cash) from scoped_shifts where status = 'closed'), 0),
      'short_over', coalesce((select sum(short_over) from scoped_shifts where status = 'closed'), 0)
    ),
    'branch_summary', coalesce((select jsonb_agg(to_jsonb(branch_summary) order by cash_sales desc, branch_name) from branch_summary), '[]'::jsonb),
    'daily_shifts', coalesce((select jsonb_agg(to_jsonb(daily_shifts) order by business_date) from daily_shifts), '[]'::jsonb),
    'shifts', coalesce((select jsonb_agg(to_jsonb(scoped_shifts) order by opened_at desc) from scoped_shifts), '[]'::jsonb),
    'movements', coalesce((select jsonb_agg(to_jsonb(scoped_movements) order by created_at desc) from scoped_movements limit 80), '[]'::jsonb),
    'can_open_shift', case
      when v_branch_filter is not null then public.shift_user_can_open(v_branch_filter)
      when v_profile.role in ('admin', 'manager', 'cashier') then true
      else false
    end,
    'can_manage_shifts', case
      when v_profile.role = 'admin' then true
      when v_branch_filter is not null then public.shift_user_can_manage_branch(v_branch_filter)
      else false
    end,
    'generated_at', now()
  )
  into v_result;

  return v_result;
end;
$$;

create or replace function public.shift_open(
  p_branch_id uuid,
  p_cash_register_id uuid default null,
  p_opening_cash numeric default 0,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.user_profiles;
  v_branch_id uuid;
  v_register_id uuid;
  v_cashier_id uuid;
  v_shift_id uuid;
  v_shift_number text;
begin
  v_profile := public.ensure_active_user();
  v_branch_id := case when v_profile.role = 'admin' then p_branch_id else v_profile.branch_id end;

  if v_branch_id is null then
    raise exception 'Branch is required to open a shift' using errcode = '23502';
  end if;

  if public.shift_user_can_open(v_branch_id) = false then
    raise exception 'You are not allowed to open a shift for this branch' using errcode = '42501';
  end if;

  if coalesce(p_opening_cash, 0) < 0 then
    raise exception 'Opening cash cannot be negative' using errcode = '23514';
  end if;

  if exists (
    select 1
    from public.cashier_shifts
    where user_id = v_profile.id
      and status = 'open'
  ) then
    raise exception 'Close your current open shift before opening another shift' using errcode = '23505';
  end if;

  if p_cash_register_id is not null then
    select id
    into v_register_id
    from public.cash_registers
    where id = p_cash_register_id
      and branch_id = v_branch_id
      and is_active = true;
  else
    select id
    into v_register_id
    from public.cash_registers
    where branch_id = v_branch_id
      and is_active = true
    order by is_default desc, name
    limit 1;
  end if;

  if v_register_id is null then
    insert into public.cash_registers (branch_id, register_code, name, is_default, is_active)
    values (v_branch_id, 'REG-01', 'Main Register', true, true)
    on conflict (branch_id, register_code) do update
    set is_active = true
    returning id into v_register_id;
  end if;

  v_cashier_id := public.pos_ensure_cashier(v_profile.id, v_branch_id);
  v_shift_number := 'SH-' || to_char(now(), 'YYYYMMDD-HH24MISS-') || upper(left(replace(gen_random_uuid()::text, '-', ''), 5));

  insert into public.cashier_shifts (
    branch_id,
    cash_register_id,
    user_id,
    cashier_id,
    shift_number,
    business_date,
    opening_cash,
    expected_cash,
    opening_notes
  )
  values (
    v_branch_id,
    v_register_id,
    v_profile.id,
    v_cashier_id,
    v_shift_number,
    current_date,
    round(coalesce(p_opening_cash, 0), 2),
    round(coalesce(p_opening_cash, 0), 2),
    nullif(trim(coalesce(p_notes, '')), '')
  )
  returning id into v_shift_id;

  insert into public.cash_drawer_movements (
    branch_id,
    cash_register_id,
    shift_id,
    user_id,
    movement_type,
    direction,
    amount,
    reason
  )
  values (
    v_branch_id,
    v_register_id,
    v_shift_id,
    v_profile.id,
    'opening',
    'in',
    round(coalesce(p_opening_cash, 0), 2),
    nullif(trim(coalesce(p_notes, 'Opening cash')), '')
  );

  perform public.shift_recalculate(v_shift_id);
  perform public.log_activity('shift.open', 'cashier_shift', v_shift_id::text, jsonb_build_object('branch_id', v_branch_id, 'opening_cash', p_opening_cash), v_profile.id);

  return public.shift_management_get(current_date - 6, current_date, v_branch_id);
end;
$$;

create or replace function public.shift_cash_movement_save(
  p_shift_id uuid,
  p_movement_type text,
  p_amount numeric,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.user_profiles;
  v_shift public.cashier_shifts;
  v_type text := lower(trim(coalesce(p_movement_type, '')));
  v_direction text;
begin
  v_profile := public.ensure_active_user();

  if v_type not in ('cash_in', 'cash_out') then
    raise exception 'Movement type must be cash_in or cash_out' using errcode = '22023';
  end if;

  if coalesce(p_amount, 0) <= 0 then
    raise exception 'Cash movement amount must be greater than zero' using errcode = '23514';
  end if;

  select *
  into v_shift
  from public.cashier_shifts
  where id = p_shift_id
  for update;

  if v_shift.id is null then
    raise exception 'Shift not found' using errcode = '02000';
  end if;

  if v_shift.status <> 'open' then
    raise exception 'Only open shifts can accept cash movements' using errcode = '23514';
  end if;

  if not (public.shift_user_can_manage_branch(v_shift.branch_id) or v_shift.user_id = v_profile.id) then
    raise exception 'You cannot add cash movements to this shift' using errcode = '42501';
  end if;

  v_direction := case when v_type = 'cash_in' then 'in' else 'out' end;

  insert into public.cash_drawer_movements (
    branch_id,
    cash_register_id,
    shift_id,
    user_id,
    movement_type,
    direction,
    amount,
    reason
  )
  values (
    v_shift.branch_id,
    v_shift.cash_register_id,
    v_shift.id,
    v_profile.id,
    v_type,
    v_direction,
    round(p_amount, 2),
    nullif(trim(coalesce(p_reason, '')), '')
  );

  perform public.shift_recalculate(v_shift.id);
  perform public.log_activity('shift.' || v_type, 'cashier_shift', v_shift.id::text, jsonb_build_object('amount', p_amount, 'reason', p_reason), v_profile.id);

  return public.shift_management_get(current_date - 6, current_date, v_shift.branch_id);
end;
$$;

create or replace function public.shift_close(
  p_shift_id uuid,
  p_counted_cash numeric,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.user_profiles;
  v_shift public.cashier_shifts;
  v_expected_cash numeric(14, 2);
  v_short_over numeric(14, 2);
begin
  v_profile := public.ensure_active_user();

  if coalesce(p_counted_cash, 0) < 0 then
    raise exception 'Counted cash cannot be negative' using errcode = '23514';
  end if;

  select *
  into v_shift
  from public.cashier_shifts
  where id = p_shift_id
  for update;

  if v_shift.id is null then
    raise exception 'Shift not found' using errcode = '02000';
  end if;

  if v_shift.status <> 'open' then
    raise exception 'Only open shifts can be closed' using errcode = '23514';
  end if;

  if public.shift_user_can_close(v_shift.id) = false then
    raise exception 'You cannot close this shift' using errcode = '42501';
  end if;

  perform public.shift_recalculate(v_shift.id);

  select expected_cash
  into v_expected_cash
  from public.cashier_shifts
  where id = v_shift.id;

  v_short_over := round(coalesce(p_counted_cash, 0) - v_expected_cash, 2);

  update public.cashier_shifts
  set counted_cash = round(coalesce(p_counted_cash, 0), 2),
      short_over = v_short_over,
      status = 'closed',
      closed_at = now(),
      closing_notes = nullif(trim(coalesce(p_notes, '')), '')
  where id = v_shift.id;

  insert into public.cash_drawer_movements (
    branch_id,
    cash_register_id,
    shift_id,
    user_id,
    movement_type,
    direction,
    amount,
    reason
  )
  values (
    v_shift.branch_id,
    v_shift.cash_register_id,
    v_shift.id,
    v_profile.id,
    'closing_adjustment',
    'neutral',
    abs(v_short_over),
    coalesce(nullif(trim(coalesce(p_notes, '')), ''), 'Shift closed')
  );

  perform public.log_activity(
    'shift.close',
    'cashier_shift',
    v_shift.id::text,
    jsonb_build_object('counted_cash', p_counted_cash, 'expected_cash', v_expected_cash, 'short_over', v_short_over),
    v_profile.id
  );

  return public.shift_management_get(current_date - 6, current_date, v_shift.branch_id);
end;
$$;

create or replace function public.shift_assign_order_before_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_shift_id uuid;
begin
  if new.status = 'completed' and new.shift_id is null and new.user_id is not null then
    select id
    into v_shift_id
    from public.cashier_shifts
    where branch_id = new.branch_id
      and user_id = new.user_id
      and status = 'open'
    order by opened_at desc
    limit 1;

    if v_shift_id is null then
      raise exception 'Open a cashier shift before checkout' using errcode = '23514';
    end if;

    new.shift_id := v_shift_id;
  end if;

  return new;
end;
$$;

drop trigger if exists shift_assign_order_before_insert on public.sales_orders;
create trigger shift_assign_order_before_insert
before insert on public.sales_orders
for each row execute function public.shift_assign_order_before_insert();

create or replace function public.shift_recalculate_from_order_trigger()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    if old.shift_id is not null then
      perform public.shift_recalculate(old.shift_id);
    end if;
    return old;
  end if;

  if new.shift_id is not null then
    perform public.shift_recalculate(new.shift_id);
  end if;

  if tg_op = 'UPDATE' and old.shift_id is not null and old.shift_id <> new.shift_id then
    perform public.shift_recalculate(old.shift_id);
  end if;

  return new;
end;
$$;

drop trigger if exists shift_recalculate_order_after_change on public.sales_orders;
create trigger shift_recalculate_order_after_change
after insert or update of shift_id, status, total on public.sales_orders
for each row execute function public.shift_recalculate_from_order_trigger();

create or replace function public.shift_recalculate_from_payment_trigger()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order_id uuid;
  v_shift_id uuid;
begin
  v_order_id := case when tg_op = 'DELETE' then old.order_id else new.order_id end;

  select shift_id
  into v_shift_id
  from public.sales_orders
  where id = v_order_id;

  if v_shift_id is not null then
    perform public.shift_recalculate(v_shift_id);
  end if;

  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

drop trigger if exists shift_recalculate_payment_after_insert on public.sales_order_payments;
create trigger shift_recalculate_payment_after_insert
after insert on public.sales_order_payments
for each row execute function public.shift_recalculate_from_payment_trigger();

drop trigger if exists shift_recalculate_payment_after_update on public.sales_order_payments;
create trigger shift_recalculate_payment_after_update
after update of amount, method, change_amount, status on public.sales_order_payments
for each row execute function public.shift_recalculate_from_payment_trigger();

drop trigger if exists shift_recalculate_payment_after_delete on public.sales_order_payments;
create trigger shift_recalculate_payment_after_delete
after delete on public.sales_order_payments
for each row execute function public.shift_recalculate_from_payment_trigger();

revoke all on function public.shift_user_can_view(uuid, uuid) from public;
revoke all on function public.shift_user_can_manage_branch(uuid) from public;
revoke all on function public.shift_user_can_open(uuid) from public;
revoke all on function public.shift_user_can_close(uuid) from public;
revoke all on function public.shift_recalculate(uuid) from public;
revoke all on function public.shift_visible_branch_ids(public.user_profiles) from public;
revoke all on function public.shift_pos_status_get(uuid) from public;
revoke all on function public.shift_management_get(date, date, uuid) from public;
revoke all on function public.shift_open(uuid, uuid, numeric, text) from public;
revoke all on function public.shift_cash_movement_save(uuid, text, numeric, text) from public;
revoke all on function public.shift_close(uuid, numeric, text) from public;

grant execute on function public.shift_pos_status_get(uuid) to authenticated;
grant execute on function public.shift_management_get(date, date, uuid) to authenticated;
grant execute on function public.shift_open(uuid, uuid, numeric, text) to authenticated;
grant execute on function public.shift_cash_movement_save(uuid, text, numeric, text) to authenticated;
grant execute on function public.shift_close(uuid, numeric, text) to authenticated;

notify pgrst, 'reload schema';
