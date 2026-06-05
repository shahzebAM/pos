-- MODULE 11: PAYMENTS
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
--
-- Scope:
-- - Cash, card, GCash, Maya, bank transfer, store credit, and COD setup
-- - Branch-level payment method enablement
-- - Reference-number enforcement for non-cash methods
-- - Split-payment reporting and tendered/change/applied tracking
-- - Processor fee and settlement status tracking
-- - POS payment dropdown fed from branch-enabled settings

create extension if not exists pgcrypto;

create table if not exists public.payment_methods (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  payment_type text not null check (payment_type in ('cash', 'card', 'e_wallet', 'bank', 'credit', 'delivery')),
  requires_reference boolean not null default false,
  allow_overpayment boolean not null default false,
  allow_change boolean not null default false,
  settlement_days integer not null default 0 check (settlement_days >= 0 and settlement_days <= 365),
  fee_rate numeric(5, 2) not null default 0 check (fee_rate >= 0 and fee_rate <= 100),
  sort_order integer not null default 100,
  is_active boolean not null default true,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.branch_payment_methods (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches(id) on delete cascade,
  payment_method_id uuid not null references public.payment_methods(id) on delete cascade,
  is_enabled boolean not null default true,
  reference_required_override boolean,
  fee_rate_override numeric(5, 2) check (fee_rate_override is null or (fee_rate_override >= 0 and fee_rate_override <= 100)),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (branch_id, payment_method_id)
);

drop trigger if exists set_payment_methods_updated_at on public.payment_methods;
create trigger set_payment_methods_updated_at
before update on public.payment_methods
for each row execute function public.set_updated_at();

drop trigger if exists set_branch_payment_methods_updated_at on public.branch_payment_methods;
create trigger set_branch_payment_methods_updated_at
before update on public.branch_payment_methods
for each row execute function public.set_updated_at();

insert into public.payment_methods (
  code,
  name,
  payment_type,
  requires_reference,
  allow_overpayment,
  allow_change,
  settlement_days,
  fee_rate,
  sort_order,
  notes
)
values
  ('cash', 'Cash', 'cash', false, true, true, 0, 0.00, 10, 'Physical cash tendered at checkout.'),
  ('card', 'Credit/debit card', 'card', true, false, false, 2, 2.50, 20, 'Card terminal, bank card, or processor reference required.'),
  ('gcash', 'GCash', 'e_wallet', true, false, false, 1, 1.50, 30, 'GCash mobile wallet payment reference required.'),
  ('maya', 'Maya', 'e_wallet', true, false, false, 1, 1.50, 40, 'Maya mobile wallet payment reference required.'),
  ('bank_transfer', 'Bank transfer', 'bank', true, false, false, 1, 0.00, 50, 'Bank transfer or deposit reference required.'),
  ('store_credit', 'Store credit', 'credit', true, false, false, 0, 0.00, 60, 'Store credit, voucher, or customer balance reference required.'),
  ('cod', 'COD', 'delivery', true, false, false, 0, 0.00, 70, 'Cash on delivery reference required when delivery is supported.')
on conflict (code) do update
set name = excluded.name,
    payment_type = excluded.payment_type,
    requires_reference = excluded.requires_reference,
    allow_overpayment = excluded.allow_overpayment,
    allow_change = excluded.allow_change,
    settlement_days = excluded.settlement_days,
    fee_rate = excluded.fee_rate,
    sort_order = excluded.sort_order,
    notes = excluded.notes,
    updated_at = now();

insert into public.branch_payment_methods (branch_id, payment_method_id, is_enabled)
select b.id, pm.id, true
from public.branches b
cross join public.payment_methods pm
where b.is_active = true
on conflict (branch_id, payment_method_id) do nothing;

alter table public.sales_order_payments
  drop constraint if exists sales_order_payments_method_check,
  drop constraint if exists sales_order_payments_amount_check;

alter table public.sales_order_payments
  add column if not exists payment_method_id uuid references public.payment_methods(id) on delete set null,
  add column if not exists method_label text,
  add column if not exists tendered_amount numeric(14, 2),
  add column if not exists change_amount numeric(14, 2) not null default 0,
  add column if not exists reference_required boolean not null default false,
  add column if not exists processor_fee_amount numeric(14, 2) not null default 0,
  add column if not exists net_amount numeric(14, 2) not null default 0,
  add column if not exists status text not null default 'captured',
  add column if not exists settled_at timestamptz,
  add column if not exists notes text;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'sales_order_payments_amount_nonnegative_check'
      and conrelid = 'public.sales_order_payments'::regclass
  ) then
    alter table public.sales_order_payments
      add constraint sales_order_payments_amount_nonnegative_check
      check (amount >= 0);
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'sales_order_payments_tendered_positive_check'
      and conrelid = 'public.sales_order_payments'::regclass
  ) then
    alter table public.sales_order_payments
      add constraint sales_order_payments_tendered_positive_check
      check (tendered_amount is null or tendered_amount > 0);
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'sales_order_payments_change_nonnegative_check'
      and conrelid = 'public.sales_order_payments'::regclass
  ) then
    alter table public.sales_order_payments
      add constraint sales_order_payments_change_nonnegative_check
      check (change_amount >= 0);
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'sales_order_payments_fee_nonnegative_check'
      and conrelid = 'public.sales_order_payments'::regclass
  ) then
    alter table public.sales_order_payments
      add constraint sales_order_payments_fee_nonnegative_check
      check (processor_fee_amount >= 0);
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'sales_order_payments_status_check'
      and conrelid = 'public.sales_order_payments'::regclass
  ) then
    alter table public.sales_order_payments
      add constraint sales_order_payments_status_check
      check (status in ('captured', 'pending', 'settled', 'failed', 'refunded', 'void'));
  end if;
end;
$$;

create index if not exists idx_payment_methods_code on public.payment_methods(code);
create index if not exists idx_branch_payment_methods_branch on public.branch_payment_methods(branch_id);
create index if not exists idx_branch_payment_methods_method on public.branch_payment_methods(payment_method_id);
create index if not exists idx_sales_order_payments_method on public.sales_order_payments(method);
create index if not exists idx_sales_order_payments_status on public.sales_order_payments(status);
create index if not exists idx_sales_order_payments_method_id on public.sales_order_payments(payment_method_id);

alter table public.payment_methods enable row level security;
alter table public.branch_payment_methods enable row level security;

drop policy if exists payment_methods_select_by_role on public.payment_methods;
create policy payment_methods_select_by_role
on public.payment_methods
for select
to authenticated
using (
  public.current_user_is_admin()
  or public.current_user_role() in ('manager', 'auditor', 'cashier')
);

drop policy if exists payment_methods_admin_write on public.payment_methods;
create policy payment_methods_admin_write
on public.payment_methods
for all
to authenticated
using (public.current_user_is_admin())
with check (public.current_user_is_admin());

drop policy if exists branch_payment_methods_select_by_role on public.branch_payment_methods;
create policy branch_payment_methods_select_by_role
on public.branch_payment_methods
for select
to authenticated
using (
  public.current_user_is_admin()
  or public.current_user_role() = 'auditor'
  or branch_id = public.current_user_branch_id()
);

drop policy if exists branch_payment_methods_admin_write on public.branch_payment_methods;
create policy branch_payment_methods_admin_write
on public.branch_payment_methods
for all
to authenticated
using (public.current_user_is_admin())
with check (public.current_user_is_admin());

create or replace function public.payment_method_options(p_branch_id uuid)
returns jsonb
language sql
security definer
set search_path = public
as $$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', pm.id,
        'label', pm.name,
        'value', pm.code,
        'code', pm.code,
        'payment_type', pm.payment_type,
        'requires_reference', coalesce(bpm.reference_required_override, pm.requires_reference),
        'allow_overpayment', pm.allow_overpayment,
        'allow_change', pm.allow_change,
        'fee_rate', coalesce(bpm.fee_rate_override, pm.fee_rate),
        'settlement_days', pm.settlement_days
      )
      order by pm.sort_order, pm.name
    ),
    '[]'::jsonb
  )
  from public.payment_methods pm
  join public.branch_payment_methods bpm on bpm.payment_method_id = pm.id
  where bpm.branch_id = p_branch_id
    and pm.is_active = true
    and bpm.is_enabled = true
$$;

create or replace function public.payment_prepare_order_payment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.sales_orders;
  v_method record;
  v_effective_reference_required boolean;
  v_effective_fee_rate numeric(5, 2);
begin
  select *
  into v_order
  from public.sales_orders
  where id = new.order_id
  limit 1;

  if not found then
    raise exception 'Payment order was not found' using errcode = '23503';
  end if;

  new.method := lower(trim(new.method));
  new.tendered_amount := coalesce(new.tendered_amount, new.amount);

  if new.tendered_amount <= 0 then
    raise exception 'Payment tendered amount must be greater than zero' using errcode = '23514';
  end if;

  select
    pm.id,
    pm.name,
    pm.payment_type,
    pm.requires_reference,
    pm.fee_rate,
    pm.is_active,
    bpm.is_enabled,
    bpm.reference_required_override,
    bpm.fee_rate_override
  into v_method
  from public.payment_methods pm
  join public.branch_payment_methods bpm on bpm.payment_method_id = pm.id
  where pm.code = new.method
    and bpm.branch_id = v_order.branch_id
  limit 1;

  if not found then
    raise exception 'Payment method is not configured for this branch' using errcode = '23514';
  end if;

  if v_method.is_active = false or v_method.is_enabled = false then
    raise exception 'Payment method is disabled for this branch' using errcode = '23514';
  end if;

  v_effective_reference_required := coalesce(v_method.reference_required_override, v_method.requires_reference);
  v_effective_fee_rate := coalesce(v_method.fee_rate_override, v_method.fee_rate, 0);

  if v_effective_reference_required and nullif(trim(coalesce(new.reference_number, '')), '') is null then
    raise exception '% reference number is required', v_method.name using errcode = '23502';
  end if;

  new.payment_method_id := v_method.id;
  new.method_label := v_method.name;
  new.reference_required := v_effective_reference_required;
  new.reference_number := nullif(trim(coalesce(new.reference_number, '')), '');
  new.status := coalesce(new.status, case when v_method.payment_type in ('cash', 'credit') then 'captured' else 'pending' end);
  new.amount := new.tendered_amount;
  new.change_amount := coalesce(new.change_amount, 0);
  new.processor_fee_amount := round(new.amount * (v_effective_fee_rate / 100), 2);
  new.net_amount := greatest(new.amount - new.processor_fee_amount, 0);

  return new;
end;
$$;

create or replace function public.payment_recalculate_order_payments(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.sales_orders;
  v_total_tendered numeric(14, 2);
  v_invalid_non_change integer;
begin
  select *
  into v_order
  from public.sales_orders
  where id = p_order_id
  limit 1;

  if not found then
    return;
  end if;

  select coalesce(sum(coalesce(tendered_amount, amount)), 0)::numeric(14, 2)
  into v_total_tendered
  from public.sales_order_payments
  where order_id = p_order_id;

  if v_total_tendered >= (v_order.amount_tendered - 0.01) then
    if v_total_tendered < (v_order.total - 0.01) then
      raise exception 'Payment total is less than sale total' using errcode = '23514';
    end if;

    with ordered as (
      select
        sop.id,
        sop.tendered_amount,
        pm.allow_change,
        coalesce(
          sum(sop.tendered_amount) over (
            order by sop.created_at, sop.id
            rows between unbounded preceding and 1 preceding
          ),
          0
        ) as prior_tendered
      from public.sales_order_payments sop
      left join public.payment_methods pm on pm.id = sop.payment_method_id
      where sop.order_id = p_order_id
    )
    select count(*)::integer
    into v_invalid_non_change
    from ordered
    where coalesce(allow_change, false) = false
      and tendered_amount > greatest(v_order.total - prior_tendered, 0) + 0.01;

    if v_invalid_non_change > 0 then
      raise exception 'Overpayment must be tendered through a cash/change-enabled method' using errcode = '23514';
    end if;
  end if;

  with ordered as (
    select
      sop.id,
      sop.tendered_amount,
      coalesce(
        sum(sop.tendered_amount) over (
          order by sop.created_at, sop.id
          rows between unbounded preceding and 1 preceding
        ),
        0
      ) as prior_tendered,
      coalesce(pm.allow_change, false) as allow_change,
      coalesce(bpm.fee_rate_override, pm.fee_rate, 0) as fee_rate
    from public.sales_order_payments sop
    left join public.payment_methods pm on pm.id = sop.payment_method_id
    left join public.branch_payment_methods bpm on bpm.payment_method_id = pm.id and bpm.branch_id = v_order.branch_id
    where sop.order_id = p_order_id
  ),
  calculated as (
    select
      id,
      greatest(least(tendered_amount, greatest(v_order.total - prior_tendered, 0)), 0)::numeric(14, 2) as applied_amount,
      case
        when allow_change then greatest(tendered_amount - greatest(least(tendered_amount, greatest(v_order.total - prior_tendered, 0)), 0), 0)
        else 0
      end::numeric(14, 2) as change_amount,
      fee_rate
    from ordered
  )
  update public.sales_order_payments sop
  set amount = c.applied_amount,
      change_amount = c.change_amount,
      processor_fee_amount = round(c.applied_amount * (c.fee_rate / 100), 2),
      net_amount = greatest(c.applied_amount - round(c.applied_amount * (c.fee_rate / 100), 2), 0)
  from calculated c
  where c.id = sop.id;
end;
$$;

create or replace function public.payment_after_order_payment_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.payment_recalculate_order_payments(new.order_id);
  return new;
end;
$$;

drop trigger if exists prepare_sales_order_payment on public.sales_order_payments;
create trigger prepare_sales_order_payment
before insert on public.sales_order_payments
for each row execute function public.payment_prepare_order_payment();

drop trigger if exists recalculate_sales_order_payment on public.sales_order_payments;
create trigger recalculate_sales_order_payment
after insert on public.sales_order_payments
for each row execute function public.payment_after_order_payment_insert();

update public.sales_order_payments sop
set payment_method_id = pm.id,
    method_label = pm.name,
    tendered_amount = coalesce(sop.tendered_amount, sop.amount),
    reference_required = pm.requires_reference,
    status = coalesce(nullif(sop.status, ''), case when pm.payment_type in ('cash', 'credit') then 'captured' else 'pending' end)
from public.payment_methods pm
where sop.method = pm.code
  and sop.payment_method_id is null;

do $$
declare
  v_order record;
begin
  for v_order in select distinct order_id from public.sales_order_payments
  loop
    perform public.payment_recalculate_order_payments(v_order.order_id);
  end loop;
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
      'products.view',
      'products.manage',
      'inventory.view',
      'inventory.manage',
      'inventory.count',
      'transfers.view',
      'transfers.manage',
      'bir.view',
      'bir.manage',
      'tax.view',
      'tax.manage',
      'senior_pwd.view',
      'senior_pwd.manage',
      'senior_pwd.apply',
      'payments.view',
      'payments.manage',
      'payments.settle',
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
      'products.view',
      'inventory.view',
      'inventory.manage',
      'inventory.count',
      'transfers.view',
      'transfers.manage',
      'bir.view',
      'bir.manage',
      'tax.view',
      'senior_pwd.view',
      'senior_pwd.apply',
      'payments.view',
      'payments.settle',
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
      'products.view',
      'inventory.view',
      'transfers.view',
      'bir.view',
      'tax.view',
      'senior_pwd.view',
      'payments.view',
      'activity.view',
      'reports.view'
    ]::text[]
    else array[
      'dashboard.view',
      'products.view',
      'pos.sell',
      'senior_pwd.apply',
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
    jsonb_build_object('key', 'products.view', 'label', 'View products'),
    jsonb_build_object('key', 'products.manage', 'label', 'Manage products'),
    jsonb_build_object('key', 'inventory.view', 'label', 'View inventory'),
    jsonb_build_object('key', 'inventory.manage', 'label', 'Adjust inventory'),
    jsonb_build_object('key', 'inventory.count', 'label', 'Post stock counts'),
    jsonb_build_object('key', 'transfers.view', 'label', 'View stock transfers'),
    jsonb_build_object('key', 'transfers.manage', 'label', 'Manage stock transfers'),
    jsonb_build_object('key', 'bir.view', 'label', 'View BIR compliance'),
    jsonb_build_object('key', 'bir.manage', 'label', 'Manage BIR compliance'),
    jsonb_build_object('key', 'tax.view', 'label', 'View tax reports'),
    jsonb_build_object('key', 'tax.manage', 'label', 'Manage tax setup'),
    jsonb_build_object('key', 'senior_pwd.view', 'label', 'View Senior/PWD reports'),
    jsonb_build_object('key', 'senior_pwd.manage', 'label', 'Manage Senior/PWD setup'),
    jsonb_build_object('key', 'senior_pwd.apply', 'label', 'Apply Senior/PWD discounts'),
    jsonb_build_object('key', 'payments.view', 'label', 'View payment reports'),
    jsonb_build_object('key', 'payments.manage', 'label', 'Manage payment setup'),
    jsonb_build_object('key', 'payments.settle', 'label', 'Update payment settlement'),
    jsonb_build_object('key', 'shifts.view', 'label', 'View shifts'),
    jsonb_build_object('key', 'shifts.manage', 'label', 'Open/close shifts'),
    jsonb_build_object('key', 'activity.view', 'label', 'View activity logs'),
    jsonb_build_object('key', 'pos.sell', 'label', 'Use POS checkout'),
    jsonb_build_object('key', 'pos.discount', 'label', 'Apply discounts'),
    jsonb_build_object('key', 'pos.void', 'label', 'Void transactions'),
    jsonb_build_object('key', 'reports.view', 'label', 'View reports')
  )
$$;

update public.user_access_settings uas
set permissions = (
  select array_agg(distinct permission order by permission)
  from unnest(uas.permissions || public.role_default_permissions(up.role)) as permission
)
from public.user_profiles up
where up.id = uas.user_id
  and up.deleted_at is null;

create or replace function public.payment_management_get(
  p_from date default current_date - 29,
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
  v_from date := coalesce(p_from, current_date - 29);
  v_to date := coalesce(p_to, current_date);
  v_effective_branch_id uuid;
  v_result jsonb;
begin
  v_profile := public.ensure_active_user();

  if v_profile.role not in ('admin', 'manager', 'auditor') then
    raise exception 'Payments module is not available for this role' using errcode = '42501';
  end if;

  if v_to < v_from then
    raise exception 'To date must be after from date' using errcode = '22007';
  end if;

  if v_profile.role in ('admin', 'auditor') then
    v_effective_branch_id := p_branch_id;
  else
    v_effective_branch_id := v_profile.branch_id;
  end if;

  insert into public.branch_payment_methods (branch_id, payment_method_id, is_enabled)
  select b.id, pm.id, true
  from public.branches b
  cross join public.payment_methods pm
  where b.is_active = true
  on conflict (branch_id, payment_method_id) do nothing;

  with visible_branches as (
    select b.*
    from public.branches b
    where b.is_active = true
      and (v_effective_branch_id is null or b.id = v_effective_branch_id)
  ),
  scoped_orders as (
    select so.*
    from public.sales_orders so
    join visible_branches b on b.id = so.branch_id
    where so.status = 'completed'
      and so.business_date >= v_from
      and so.business_date <= v_to
  ),
  split_orders as (
    select sop.order_id
    from public.sales_order_payments sop
    join scoped_orders so on so.id = sop.order_id
    group by sop.order_id
    having count(*) > 1
  ),
  payment_rows as (
    select
      sop.id,
      sop.order_id,
      sop.payment_method_id,
      sop.method,
      coalesce(sop.method_label, pm.name, initcap(replace(sop.method, '_', ' '))) as method_label,
      coalesce(pm.payment_type, sop.method) as payment_type,
      sop.amount,
      coalesce(sop.tendered_amount, sop.amount) as tendered_amount,
      sop.change_amount,
      sop.processor_fee_amount,
      sop.net_amount,
      sop.reference_required,
      sop.reference_number,
      sop.status,
      sop.settled_at,
      sop.notes,
      sop.created_at,
      so.branch_id,
      b.branch_code,
      b.name as branch_name,
      so.order_number,
      so.invoice_number,
      so.business_date,
      so.total as order_total,
      so.payment_method_summary,
      up.full_name as cashier_name,
      up.username as cashier_username
    from public.sales_order_payments sop
    join scoped_orders so on so.id = sop.order_id
    join visible_branches b on b.id = so.branch_id
    left join public.payment_methods pm on pm.id = sop.payment_method_id or pm.code = sop.method
    left join public.user_profiles up on up.id = so.user_id
  ),
  method_rows as (
    select
      pm.id,
      pm.code,
      pm.name,
      pm.payment_type,
      pm.requires_reference,
      pm.allow_overpayment,
      pm.allow_change,
      pm.settlement_days,
      pm.fee_rate,
      pm.sort_order,
      pm.is_active,
      pm.notes,
      count(pr.id)::integer as payment_count,
      coalesce(sum(pr.amount), 0)::numeric(14, 2) as collected_amount,
      coalesce(sum(pr.tendered_amount), 0)::numeric(14, 2) as tendered_amount,
      coalesce(sum(pr.change_amount), 0)::numeric(14, 2) as change_amount,
      coalesce(sum(pr.processor_fee_amount), 0)::numeric(14, 2) as processor_fee_amount,
      coalesce(sum(pr.net_amount), 0)::numeric(14, 2) as net_amount
    from public.payment_methods pm
    left join payment_rows pr on pr.method = pm.code
    group by pm.id, pm.code, pm.name, pm.payment_type, pm.requires_reference, pm.allow_overpayment, pm.allow_change, pm.settlement_days, pm.fee_rate, pm.sort_order, pm.is_active, pm.notes
    order by pm.sort_order, pm.name
  ),
  branch_rows as (
    select
      b.id as branch_id,
      b.branch_code,
      b.name as branch_name,
      count(pr.id)::integer as payment_count,
      count(distinct pr.order_id)::integer as order_count,
      coalesce(sum(pr.amount), 0)::numeric(14, 2) as collected_amount,
      coalesce(sum(pr.tendered_amount), 0)::numeric(14, 2) as tendered_amount,
      coalesce(sum(pr.change_amount), 0)::numeric(14, 2) as change_amount,
      coalesce(sum(pr.processor_fee_amount), 0)::numeric(14, 2) as processor_fee_amount,
      coalesce(sum(pr.net_amount), 0)::numeric(14, 2) as net_amount
    from visible_branches b
    left join payment_rows pr on pr.branch_id = b.id
    group by b.id, b.branch_code, b.name
    order by b.name
  ),
  branch_method_rows as (
    select
      b.id as branch_id,
      b.branch_code,
      b.name as branch_name,
      pm.id as payment_method_id,
      pm.code,
      pm.name as method_name,
      pm.payment_type,
      coalesce(bpm.is_enabled, false) as is_enabled,
      coalesce(bpm.reference_required_override, pm.requires_reference) as requires_reference,
      bpm.reference_required_override,
      coalesce(bpm.fee_rate_override, pm.fee_rate) as effective_fee_rate,
      bpm.fee_rate_override,
      pm.settlement_days,
      count(pr.id)::integer as payment_count,
      coalesce(sum(pr.amount), 0)::numeric(14, 2) as collected_amount
    from visible_branches b
    cross join public.payment_methods pm
    left join public.branch_payment_methods bpm on bpm.branch_id = b.id and bpm.payment_method_id = pm.id
    left join payment_rows pr on pr.branch_id = b.id and pr.method = pm.code
    group by b.id, b.branch_code, b.name, pm.id, pm.code, pm.name, pm.payment_type, bpm.is_enabled, bpm.reference_required_override, bpm.fee_rate_override, pm.requires_reference, pm.fee_rate, pm.settlement_days, pm.sort_order
    order by b.name, pm.sort_order, pm.name
  ),
  daily_rows as (
    select
      d.day::date as business_date,
      to_char(d.day, 'Mon DD') as label,
      count(pr.id)::integer as payment_count,
      coalesce(sum(pr.amount), 0)::numeric(14, 2) as collected_amount,
      coalesce(sum(pr.processor_fee_amount), 0)::numeric(14, 2) as processor_fee_amount,
      coalesce(sum(pr.net_amount), 0)::numeric(14, 2) as net_amount
    from generate_series(v_from, v_to, interval '1 day') d(day)
    left join payment_rows pr on pr.business_date = d.day::date
    group by d.day
    order by d.day
  ),
  recent_payment_rows as (
    select *
    from payment_rows
    order by created_at desc
    limit 120
  )
  select jsonb_build_object(
    'period', jsonb_build_object('from', v_from, 'to', v_to),
    'summary', jsonb_build_object(
      'payment_count', coalesce((select count(*) from payment_rows), 0),
      'order_count', coalesce((select count(distinct order_id) from payment_rows), 0),
      'split_order_count', coalesce((select count(*) from split_orders), 0),
      'collected_amount', coalesce((select sum(amount) from payment_rows), 0),
      'tendered_amount', coalesce((select sum(tendered_amount) from payment_rows), 0),
      'change_amount', coalesce((select sum(change_amount) from payment_rows), 0),
      'processor_fee_amount', coalesce((select sum(processor_fee_amount) from payment_rows), 0),
      'net_amount', coalesce((select sum(net_amount) from payment_rows), 0),
      'pending_settlement_count', coalesce((select count(*) from payment_rows where payment_type not in ('cash', 'credit') and status in ('captured', 'pending')), 0),
      'reference_missing_count', coalesce((select count(*) from payment_rows where reference_required and reference_number is null), 0)
    ),
    'branches', coalesce((
      select jsonb_agg(jsonb_build_object('id', b.id, 'branch_code', b.branch_code, 'name', b.name) order by b.name)
      from visible_branches b
    ), '[]'::jsonb),
    'payment_methods', coalesce((select jsonb_agg(to_jsonb(method_rows) order by sort_order, name) from method_rows), '[]'::jsonb),
    'branch_payment_methods', coalesce((select jsonb_agg(to_jsonb(branch_method_rows) order by branch_name, code) from branch_method_rows), '[]'::jsonb),
    'payments_by_branch', coalesce((select jsonb_agg(to_jsonb(branch_rows) order by branch_name) from branch_rows), '[]'::jsonb),
    'daily_payments', coalesce((select jsonb_agg(to_jsonb(daily_rows) order by business_date) from daily_rows), '[]'::jsonb),
    'recent_payments', coalesce((select jsonb_agg(to_jsonb(recent_payment_rows) order by created_at desc) from recent_payment_rows), '[]'::jsonb),
    'generated_at', now()
  )
  into v_result;

  return v_result;
end;
$$;

create or replace function public.payment_method_save(p_method_id uuid, p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.user_profiles;
  v_method_id uuid := p_method_id;
  v_code text := lower(trim(coalesce(p_payload->>'code', '')));
begin
  v_profile := public.ensure_active_user();

  if v_profile.role <> 'admin' then
    raise exception 'Only admins can manage payment methods' using errcode = '42501';
  end if;

  if v_code not in ('cash', 'card', 'gcash', 'maya', 'bank_transfer', 'store_credit', 'cod') then
    raise exception 'Payment method code must be one of the standard Module 11 methods' using errcode = '22023';
  end if;

  if v_method_id is null then
    select id into v_method_id from public.payment_methods where code = v_code limit 1;
  end if;

  update public.payment_methods
  set name = nullif(trim(coalesce(p_payload->>'name', name)), ''),
      requires_reference = coalesce((p_payload->>'requires_reference')::boolean, requires_reference),
      allow_overpayment = coalesce((p_payload->>'allow_overpayment')::boolean, allow_overpayment),
      allow_change = coalesce((p_payload->>'allow_change')::boolean, allow_change),
      settlement_days = coalesce(nullif(p_payload->>'settlement_days', '')::integer, settlement_days),
      fee_rate = coalesce(nullif(p_payload->>'fee_rate', '')::numeric, fee_rate),
      sort_order = coalesce(nullif(p_payload->>'sort_order', '')::integer, sort_order),
      is_active = coalesce((p_payload->>'is_active')::boolean, is_active),
      notes = nullif(trim(coalesce(p_payload->>'notes', '')), ''),
      updated_at = now()
  where id = v_method_id;

  if not found then
    raise exception 'Payment method not found' using errcode = '02000';
  end if;

  insert into public.branch_payment_methods (branch_id, payment_method_id, is_enabled)
  select b.id, v_method_id, true
  from public.branches b
  where b.is_active = true
  on conflict (branch_id, payment_method_id) do nothing;

  perform public.log_activity(
    'payments.method_saved',
    'payment_methods',
    v_method_id::text,
    jsonb_build_object('code', v_code),
    v_profile.id
  );

  return public.payment_management_get(null, null, null);
end;
$$;

create or replace function public.branch_payment_method_save(p_branch_id uuid, p_payment_method_id uuid, p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.user_profiles;
  v_reference_override boolean;
  v_fee_override numeric(5, 2);
begin
  v_profile := public.ensure_active_user();

  if v_profile.role <> 'admin' then
    raise exception 'Only admins can manage branch payment methods' using errcode = '42501';
  end if;

  if p_branch_id is null or p_payment_method_id is null then
    raise exception 'Branch and payment method are required' using errcode = '23502';
  end if;

  v_reference_override := case
    when p_payload ? 'reference_required_override' then (p_payload->>'reference_required_override')::boolean
    else null
  end;
  v_fee_override := case
    when p_payload ? 'fee_rate_override' and nullif(p_payload->>'fee_rate_override', '') is not null then (p_payload->>'fee_rate_override')::numeric
    else null
  end;

  insert into public.branch_payment_methods (
    branch_id,
    payment_method_id,
    is_enabled,
    reference_required_override,
    fee_rate_override,
    notes
  )
  values (
    p_branch_id,
    p_payment_method_id,
    coalesce((p_payload->>'is_enabled')::boolean, true),
    v_reference_override,
    v_fee_override,
    nullif(trim(coalesce(p_payload->>'notes', '')), '')
  )
  on conflict (branch_id, payment_method_id) do update
  set is_enabled = excluded.is_enabled,
      reference_required_override = excluded.reference_required_override,
      fee_rate_override = excluded.fee_rate_override,
      notes = excluded.notes,
      updated_at = now();

  perform public.log_activity(
    'payments.branch_method_saved',
    'branch_payment_methods',
    p_branch_id::text || ':' || p_payment_method_id::text,
    jsonb_build_object('branch_id', p_branch_id, 'payment_method_id', p_payment_method_id),
    v_profile.id
  );

  return public.payment_management_get(null, null, p_branch_id);
end;
$$;

create or replace function public.payment_settlement_update(p_payment_id uuid, p_status text, p_settled_at timestamptz default null, p_notes text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.user_profiles;
  v_payment record;
begin
  v_profile := public.ensure_active_user();

  if p_status not in ('captured', 'pending', 'settled', 'failed', 'refunded', 'void') then
    raise exception 'Invalid payment status' using errcode = '22023';
  end if;

  select
    sop.id,
    so.branch_id
  into v_payment
  from public.sales_order_payments sop
  join public.sales_orders so on so.id = sop.order_id
  where sop.id = p_payment_id
  limit 1;

  if not found then
    raise exception 'Payment not found' using errcode = '02000';
  end if;

  if v_profile.role <> 'admin' and not (
    v_profile.role = 'manager'
    and v_profile.branch_id = v_payment.branch_id
    and 'payments.settle' = any(public.role_default_permissions(v_profile.role))
  ) then
    raise exception 'You cannot update settlement for this payment' using errcode = '42501';
  end if;

  update public.sales_order_payments
  set status = p_status,
      settled_at = case when p_status = 'settled' then coalesce(p_settled_at, now()) else p_settled_at end,
      notes = nullif(trim(coalesce(p_notes, '')), '')
  where id = p_payment_id;

  perform public.log_activity(
    'payments.settlement_updated',
    'sales_order_payments',
    p_payment_id::text,
    jsonb_build_object('status', p_status),
    v_profile.id
  );

  return public.payment_management_get(null, null, case when v_profile.role = 'manager' then v_profile.branch_id else null end);
end;
$$;

create or replace function public.pos_management_get(p_branch_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.user_profiles;
  v_effective_branch_id uuid;
  v_result jsonb;
begin
  v_profile := public.ensure_active_user();

  if v_profile.role not in ('admin', 'manager', 'cashier') then
    raise exception 'POS checkout is not available for this role' using errcode = '42501';
  end if;

  if v_profile.role = 'admin' then
    v_effective_branch_id := p_branch_id;
  else
    v_effective_branch_id := v_profile.branch_id;
  end if;

  if v_effective_branch_id is null then
    select id
    into v_effective_branch_id
    from public.branches
    where is_active = true
    order by is_head_office desc, name asc
    limit 1;
  end if;

  if v_effective_branch_id is null then
    raise exception 'No active branch is available for POS' using errcode = '02000';
  end if;

  if public.pos_user_can_sell(v_effective_branch_id) = false then
    raise exception 'You cannot use POS checkout for this branch' using errcode = '42501';
  end if;

  insert into public.branch_payment_methods (branch_id, payment_method_id, is_enabled)
  select v_effective_branch_id, pm.id, true
  from public.payment_methods pm
  on conflict (branch_id, payment_method_id) do nothing;

  with active_branch as (
    select
      b.id,
      b.branch_code,
      b.name,
      b.address,
      bs.tax_profile,
      bs.vat_rate,
      bs.receipt_footer
    from public.branches b
    left join public.branch_settings bs on bs.branch_id = b.id
    where b.id = v_effective_branch_id
      and b.is_active = true
  ),
  senior_pwd_settings as (
    select
      s.branch_id,
      s.standard_discount_rate,
      s.basic_necessity_rate,
      s.require_id_capture,
      s.require_booklet_for_basic,
      s.is_active,
      s.notes
    from public.senior_pwd_discount_settings s
    where s.branch_id = v_effective_branch_id
  ),
  branch_options as (
    select b.id, b.branch_code, b.name, b.is_head_office
    from public.branches b
    where b.is_active = true
    order by b.is_head_office desc, b.name
  ),
  product_rows as (
    select
      p.id,
      p.sku,
      p.barcode,
      p.name,
      p.category,
      pc.name as category_name,
      pb.name as brand_name,
      pu.name as unit_name,
      p.selling_price,
      p.cost_price,
      p.tax_type,
      p.vat_rate,
      p.tax_inclusive,
      p.senior_pwd_discount_category,
      p.reorder_level,
      coalesce((
        select sum(ib.quantity_on_hand)
        from public.inventory_batches ib
        where ib.branch_id = v_effective_branch_id
          and ib.product_id = p.id
          and ib.status = 'active'
      ), 0)::integer as quantity_on_hand,
      coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'id', pv.id,
            'variant_name', pv.variant_name,
            'sku', pv.sku,
            'barcode', pv.barcode,
            'selling_price', pv.selling_price,
            'cost_price', pv.cost_price,
            'quantity_on_hand', coalesce((
              select sum(ib.quantity_on_hand)
              from public.inventory_batches ib
              where ib.branch_id = v_effective_branch_id
                and ib.product_id = p.id
                and ib.product_variant_id = pv.id
                and ib.status = 'active'
            ), 0)
          )
          order by pv.variant_name
        )
        from public.product_variants pv
        where pv.product_id = p.id
          and pv.deleted_at is null
          and pv.is_active = true
      ), '[]'::jsonb) as variants
    from public.products p
    left join public.product_categories pc on pc.id = p.category_id
    left join public.product_brands pb on pb.id = p.brand_id
    left join public.product_units pu on pu.id = p.unit_id
    where p.deleted_at is null
      and p.is_active = true
    order by p.name
  ),
  todays_orders as (
    select *
    from public.sales_orders so
    where so.branch_id = v_effective_branch_id
      and so.business_date = current_date
      and so.status = 'completed'
  ),
  recent_orders as (
    select so.*
    from public.sales_orders so
    where so.branch_id = v_effective_branch_id
    order by so.created_at desc
    limit 25
  ),
  recent_order_rows as (
    select
      so.id,
      so.order_number,
      so.invoice_number,
      so.business_date,
      so.customer_name,
      so.subtotal,
      so.discount_total,
      so.statutory_discount_type,
      so.statutory_discount_amount,
      so.statutory_vat_exempt_amount,
      so.statutory_special_discount_amount,
      so.beneficiary_name,
      so.beneficiary_id_type,
      so.beneficiary_id_number,
      so.beneficiary_booklet_number,
      so.tax_total,
      so.total,
      so.amount_tendered,
      so.change_due,
      so.payment_method_summary,
      so.status,
      so.source,
      so.created_at,
      up.full_name as cashier_name,
      up.username as cashier_username,
      coalesce(items.items, '[]'::jsonb) as items,
      coalesce(payments.payments, '[]'::jsonb) as payments
    from recent_orders so
    left join public.user_profiles up on up.id = so.user_id
    left join lateral (
      select jsonb_agg(
        jsonb_build_object(
          'id', soi.id,
          'product_name', soi.product_name,
          'variant_name', soi.variant_name,
          'sku', soi.sku,
          'barcode', soi.barcode,
          'quantity', soi.quantity,
          'unit_price', soi.unit_price,
          'gross_amount', soi.gross_amount,
          'discount_amount', soi.discount_amount,
          'senior_pwd_discount_category', soi.senior_pwd_discount_category,
          'statutory_discount_amount', soi.statutory_discount_amount,
          'statutory_vat_exempt_amount', soi.statutory_vat_exempt_amount,
          'statutory_special_discount_amount', soi.statutory_special_discount_amount,
          'tax_type', soi.tax_type,
          'tax_rate', soi.tax_rate,
          'tax_amount', soi.tax_amount,
          'net_amount', soi.net_amount
        )
        order by soi.created_at asc
      ) as items
      from public.sales_order_items soi
      where soi.order_id = so.id
    ) items on true
    left join lateral (
      select jsonb_agg(
        jsonb_build_object(
          'id', sop.id,
          'method', sop.method,
          'method_label', coalesce(sop.method_label, initcap(replace(sop.method, '_', ' '))),
          'amount', sop.amount,
          'tendered_amount', coalesce(sop.tendered_amount, sop.amount),
          'change_amount', sop.change_amount,
          'processor_fee_amount', sop.processor_fee_amount,
          'net_amount', sop.net_amount,
          'reference_number', sop.reference_number,
          'reference_required', sop.reference_required,
          'status', sop.status
        )
        order by sop.created_at asc
      ) as payments
      from public.sales_order_payments sop
      where sop.order_id = so.id
    ) payments on true
  )
  select jsonb_build_object(
    'branch', (select to_jsonb(active_branch) from active_branch limit 1),
    'senior_pwd_settings', coalesce(
      (select to_jsonb(senior_pwd_settings) from senior_pwd_settings limit 1),
      jsonb_build_object(
        'branch_id', v_effective_branch_id,
        'standard_discount_rate', 20,
        'basic_necessity_rate', 5,
        'require_id_capture', true,
        'require_booklet_for_basic', true,
        'is_active', true
      )
    ),
    'branches', coalesce((select jsonb_agg(to_jsonb(branch_options)) from branch_options), '[]'::jsonb),
    'products', coalesce((select jsonb_agg(to_jsonb(product_rows)) from product_rows), '[]'::jsonb),
    'recent_orders', coalesce((select jsonb_agg(to_jsonb(recent_order_rows)) from recent_order_rows), '[]'::jsonb),
    'summary', jsonb_build_object(
      'today_orders', coalesce((select count(*) from todays_orders), 0),
      'today_sales', coalesce((select sum(total) from todays_orders), 0),
      'today_tax', coalesce((select sum(tax_total) from todays_orders), 0),
      'today_discounts', coalesce((select sum(discount_total) from todays_orders), 0),
      'today_senior_pwd_discounts', coalesce((select sum(statutory_discount_amount + statutory_special_discount_amount) from todays_orders), 0),
      'items_available', coalesce((select count(*) from product_rows where quantity_on_hand > 0), 0)
    ),
    'payment_methods', public.payment_method_options(v_effective_branch_id),
    'payment_methods_installed', true,
    'senior_pwd_discount_options', jsonb_build_array(
      jsonb_build_object('label', 'No Senior/PWD discount', 'value', 'none'),
      jsonb_build_object('label', 'Senior Citizen', 'value', 'senior'),
      jsonb_build_object('label', 'PWD', 'value', 'pwd')
    ),
    'generated_at', now()
  )
  into v_result;

  return v_result;
end;
$$;

revoke all on function public.payment_method_options(uuid) from public;
revoke all on function public.payment_management_get(date, date, uuid) from public;
revoke all on function public.payment_method_save(uuid, jsonb) from public;
revoke all on function public.branch_payment_method_save(uuid, uuid, jsonb) from public;
revoke all on function public.payment_settlement_update(uuid, text, timestamptz, text) from public;
grant execute on function public.payment_method_options(uuid) to authenticated;
grant execute on function public.payment_management_get(date, date, uuid) to authenticated;
grant execute on function public.payment_method_save(uuid, jsonb) to authenticated;
grant execute on function public.branch_payment_method_save(uuid, uuid, jsonb) to authenticated;
grant execute on function public.payment_settlement_update(uuid, text, timestamptz, text) to authenticated;

notify pgrst, 'reload schema';
