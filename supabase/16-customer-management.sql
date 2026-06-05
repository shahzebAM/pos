-- MODULE 16: CUSTOMER MANAGEMENT
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
-- 13. supabase/12-cash-register-shifts.sql
-- 14. supabase/13-returns-exchanges.sql
-- 15. supabase/14-purchase-management.sql
-- 16. supabase/15-supplier-management.sql
--
-- Scope:
-- - Customer profiles
-- - Purchase history
-- - Credit sales / receivables
-- - Store credit balance
-- - Loyalty points
-- - POS customer selection support

create extension if not exists pgcrypto;

create table if not exists public.customers (
  id uuid primary key default gen_random_uuid(),
  customer_code text not null unique,
  full_name text not null,
  phone text,
  email text,
  tin text,
  address text,
  birth_date date,
  customer_type text not null default 'regular',
  branch_id uuid references public.branches(id) on delete set null,
  credit_limit numeric(14, 2) not null default 0 check (credit_limit >= 0),
  receivable_balance numeric(14, 2) not null default 0,
  store_credit_balance numeric(14, 2) not null default 0,
  loyalty_points integer not null default 0,
  total_orders integer not null default 0,
  total_spent numeric(14, 2) not null default 0,
  last_purchase_at timestamptz,
  is_active boolean not null default true,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint customers_type_check check (customer_type in ('regular', 'senior', 'pwd', 'company'))
);

drop trigger if exists set_customers_updated_at on public.customers;
create trigger set_customers_updated_at
before update on public.customers
for each row execute function public.set_updated_at();

create unique index if not exists idx_customers_email_lower
on public.customers (lower(email))
where email is not null and trim(email) <> '';

create index if not exists idx_customers_branch_active on public.customers(branch_id, is_active, full_name);
create index if not exists idx_customers_name_search on public.customers(lower(full_name));

alter table public.sales_orders
  add column if not exists customer_id uuid references public.customers(id) on delete set null;

create index if not exists idx_sales_orders_customer
on public.sales_orders(customer_id, business_date desc, created_at desc);

create table if not exists public.customer_account_entries (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches(id) on delete restrict,
  customer_id uuid not null references public.customers(id) on delete restrict,
  order_id uuid references public.sales_orders(id) on delete set null,
  entry_type text not null,
  receivable_delta numeric(14, 2) not null default 0,
  store_credit_delta numeric(14, 2) not null default 0,
  reference_number text,
  description text,
  source text not null default 'manual',
  created_by uuid references public.user_profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  status text not null default 'posted',
  voided_by uuid references public.user_profiles(id) on delete set null,
  voided_at timestamptz,
  void_reason text,
  constraint customer_account_entries_type_check check (
    entry_type in ('credit_sale', 'payment', 'store_credit_issue', 'store_credit_use', 'adjustment', 'write_off', 'return_credit')
  ),
  constraint customer_account_entries_status_check check (status in ('posted', 'voided')),
  constraint customer_account_entries_amount_check check (receivable_delta <> 0 or store_credit_delta <> 0)
);

create index if not exists idx_customer_account_customer_date on public.customer_account_entries(customer_id, created_at desc);
create index if not exists idx_customer_account_branch_date on public.customer_account_entries(branch_id, created_at desc);
create unique index if not exists idx_customer_account_order_credit_sale
on public.customer_account_entries(order_id)
where entry_type = 'credit_sale' and order_id is not null;

create table if not exists public.customer_loyalty_ledger (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches(id) on delete restrict,
  customer_id uuid not null references public.customers(id) on delete restrict,
  order_id uuid references public.sales_orders(id) on delete set null,
  entry_type text not null,
  points_delta integer not null check (points_delta <> 0),
  description text,
  created_by uuid references public.user_profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  status text not null default 'posted',
  voided_by uuid references public.user_profiles(id) on delete set null,
  voided_at timestamptz,
  void_reason text,
  constraint customer_loyalty_type_check check (entry_type in ('earn', 'redeem', 'adjust', 'void')),
  constraint customer_loyalty_status_check check (status in ('posted', 'voided'))
);

create index if not exists idx_customer_loyalty_customer_date on public.customer_loyalty_ledger(customer_id, created_at desc);
create index if not exists idx_customer_loyalty_branch_date on public.customer_loyalty_ledger(branch_id, created_at desc);
create unique index if not exists idx_customer_loyalty_order_earn
on public.customer_loyalty_ledger(order_id)
where entry_type = 'earn' and order_id is not null;

create table if not exists public.customer_loyalty_settings (
  branch_id uuid primary key references public.branches(id) on delete cascade,
  peso_per_point numeric(14, 2) not null default 100 check (peso_per_point > 0),
  point_value numeric(14, 2) not null default 1 check (point_value >= 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

drop trigger if exists set_customer_loyalty_settings_updated_at on public.customer_loyalty_settings;
create trigger set_customer_loyalty_settings_updated_at
before update on public.customer_loyalty_settings
for each row execute function public.set_updated_at();

insert into public.customer_loyalty_settings (branch_id)
select b.id
from public.branches b
left join public.customer_loyalty_settings cls on cls.branch_id = b.id
where cls.branch_id is null;

alter table public.customers enable row level security;
alter table public.customer_account_entries enable row level security;
alter table public.customer_loyalty_ledger enable row level security;
alter table public.customer_loyalty_settings enable row level security;

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
      'returns.view',
      'returns.manage',
      'returns.approve',
      'purchases.view',
      'purchases.manage',
      'purchases.approve',
      'purchases.receive',
      'suppliers.view',
      'suppliers.manage',
      'suppliers.pay',
      'customers.view',
      'customers.manage',
      'customers.credit',
      'customers.loyalty',
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
      'returns.view',
      'returns.manage',
      'returns.approve',
      'purchases.view',
      'purchases.manage',
      'purchases.approve',
      'purchases.receive',
      'suppliers.view',
      'suppliers.manage',
      'suppliers.pay',
      'customers.view',
      'customers.manage',
      'customers.credit',
      'customers.loyalty',
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
      'shifts.view',
      'returns.view',
      'purchases.view',
      'suppliers.view',
      'customers.view',
      'activity.view',
      'reports.view'
    ]::text[]
    else array[
      'dashboard.view',
      'products.view',
      'customers.view',
      'pos.sell',
      'senior_pwd.apply',
      'shifts.view',
      'returns.view',
      'returns.manage'
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
    jsonb_build_object('key', 'returns.view', 'label', 'View returns'),
    jsonb_build_object('key', 'returns.manage', 'label', 'Process returns/refunds'),
    jsonb_build_object('key', 'returns.approve', 'label', 'Approve returns and voids'),
    jsonb_build_object('key', 'purchases.view', 'label', 'View purchase management'),
    jsonb_build_object('key', 'purchases.manage', 'label', 'Create purchase orders'),
    jsonb_build_object('key', 'purchases.approve', 'label', 'Approve purchase orders'),
    jsonb_build_object('key', 'purchases.receive', 'label', 'Receive purchase orders'),
    jsonb_build_object('key', 'suppliers.view', 'label', 'View supplier management'),
    jsonb_build_object('key', 'suppliers.manage', 'label', 'Manage supplier profiles'),
    jsonb_build_object('key', 'suppliers.pay', 'label', 'Post supplier payments'),
    jsonb_build_object('key', 'customers.view', 'label', 'View customer management'),
    jsonb_build_object('key', 'customers.manage', 'label', 'Manage customer profiles'),
    jsonb_build_object('key', 'customers.credit', 'label', 'Post customer credit and payments'),
    jsonb_build_object('key', 'customers.loyalty', 'label', 'Adjust customer loyalty'),
    jsonb_build_object('key', 'activity.view', 'label', 'View activity logs'),
    jsonb_build_object('key', 'pos.sell', 'label', 'Use POS checkout'),
    jsonb_build_object('key', 'pos.discount', 'label', 'Apply discounts'),
    jsonb_build_object('key', 'pos.void', 'label', 'Void transactions'),
    jsonb_build_object('key', 'reports.view', 'label', 'View reports')
  )
$$;

create or replace function public.customer_effective_permissions(p_user_id uuid, p_role text)
returns text[]
language sql
stable
security definer
set search_path = public
as $$
  select array(
    select distinct permission
    from unnest(coalesce((
      select permissions
      from public.user_access_settings
      where user_id = p_user_id
    ), array[]::text[]) || public.role_default_permissions(p_role)) as permission
  )
$$;

create or replace function public.customer_visible_branch_ids(p_profile public.user_profiles)
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

create or replace function public.customer_user_can_view(p_branch_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_profile public.user_profiles;
  v_permissions text[];
begin
  v_profile := public.ensure_active_user();
  v_permissions := public.customer_effective_permissions(v_profile.id, v_profile.role);

  if not coalesce('customers.view' = any(v_permissions), false) and v_profile.role <> 'admin' then
    return false;
  end if;

  if v_profile.role in ('admin', 'auditor') then
    return true;
  end if;

  return p_branch_id is not null and v_profile.branch_id = p_branch_id;
end;
$$;

create or replace function public.customer_user_can_manage(p_branch_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_profile public.user_profiles;
  v_permissions text[];
begin
  v_profile := public.ensure_active_user();
  v_permissions := public.customer_effective_permissions(v_profile.id, v_profile.role);

  if v_profile.role = 'admin' then
    return true;
  end if;

  return v_profile.role = 'manager'
    and (p_branch_id is null or v_profile.branch_id = p_branch_id)
    and coalesce('customers.manage' = any(v_permissions), false);
end;
$$;

create or replace function public.customer_user_can_credit(p_branch_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_profile public.user_profiles;
  v_permissions text[];
begin
  v_profile := public.ensure_active_user();
  v_permissions := public.customer_effective_permissions(v_profile.id, v_profile.role);

  if v_profile.role = 'admin' then
    return true;
  end if;

  return v_profile.role = 'manager'
    and (p_branch_id is null or v_profile.branch_id = p_branch_id)
    and coalesce('customers.credit' = any(v_permissions), false);
end;
$$;

drop policy if exists customers_select_by_role on public.customers;
create policy customers_select_by_role
on public.customers
for select
to authenticated
using (
  public.current_user_is_admin()
  or public.current_user_role() = 'auditor'
  or branch_id = public.current_user_branch_id()
  or (branch_id is null and public.current_user_role() in ('manager', 'cashier'))
);

drop policy if exists customer_account_entries_select_by_role on public.customer_account_entries;
create policy customer_account_entries_select_by_role
on public.customer_account_entries
for select
to authenticated
using (public.customer_user_can_view(branch_id));

drop policy if exists customer_loyalty_ledger_select_by_role on public.customer_loyalty_ledger;
create policy customer_loyalty_ledger_select_by_role
on public.customer_loyalty_ledger
for select
to authenticated
using (public.customer_user_can_view(branch_id));

drop policy if exists customer_loyalty_settings_select_by_role on public.customer_loyalty_settings;
create policy customer_loyalty_settings_select_by_role
on public.customer_loyalty_settings
for select
to authenticated
using (public.customer_user_can_view(branch_id));

create or replace function public.customer_next_code(p_name text default null)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_prefix text;
  v_code text;
begin
  v_prefix := upper(left(regexp_replace(coalesce(nullif(p_name, ''), 'CUSTOMER'), '[^A-Za-z0-9]+', '', 'g'), 3));
  if length(v_prefix) < 3 then
    v_prefix := 'CUS';
  end if;

  loop
    v_code := 'CUS-' || v_prefix || '-' || upper(left(replace(gen_random_uuid()::text, '-', ''), 6));
    exit when not exists (select 1 from public.customers where customer_code = v_code);
  end loop;

  return v_code;
end;
$$;

create or replace function public.customer_sync_balances(p_customer_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_receivable numeric(14, 2) := 0;
  v_store_credit numeric(14, 2) := 0;
  v_points integer := 0;
begin
  select
    coalesce(sum(receivable_delta) filter (where status = 'posted'), 0)::numeric(14, 2),
    coalesce(sum(store_credit_delta) filter (where status = 'posted'), 0)::numeric(14, 2)
  into v_receivable, v_store_credit
  from public.customer_account_entries
  where customer_id = p_customer_id;

  select coalesce(sum(points_delta) filter (where status = 'posted'), 0)::integer
  into v_points
  from public.customer_loyalty_ledger
  where customer_id = p_customer_id;

  update public.customers
  set receivable_balance = v_receivable,
      store_credit_balance = v_store_credit,
      loyalty_points = v_points
  where id = p_customer_id;
end;
$$;

create or replace function public.customer_recalculate_stats(p_customer_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.customers c
  set total_orders = coalesce(stats.total_orders, 0),
      total_spent = coalesce(stats.total_spent, 0),
      last_purchase_at = stats.last_purchase_at
  from (
    select
      count(*)::integer as total_orders,
      coalesce(sum(total), 0)::numeric(14, 2) as total_spent,
      max(created_at) as last_purchase_at
    from public.sales_orders
    where customer_id = p_customer_id
      and status = 'completed'
  ) stats
  where c.id = p_customer_id;
end;
$$;

create or replace function public.customer_resolve_order_customer()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_customer public.customers;
  v_name text := trim(coalesce(new.customer_name, ''));
begin
  if new.customer_id is not null then
    select *
    into v_customer
    from public.customers
    where id = new.customer_id
      and is_active = true
    limit 1;

    if v_customer.id is not null then
      new.customer_name := v_customer.full_name;
    end if;

    return new;
  end if;

  if v_name = '' or lower(v_name) in ('walk-in', 'walk in', 'walkin') then
    return new;
  end if;

  select *
  into v_customer
  from public.customers
  where is_active = true
    and lower(full_name) = lower(v_name)
    and (branch_id = new.branch_id or branch_id is null)
  order by case when branch_id = new.branch_id then 0 else 1 end, created_at desc
  limit 1;

  if v_customer.id is null then
    insert into public.customers (customer_code, full_name, branch_id, notes)
    values (public.customer_next_code(v_name), v_name, new.branch_id, 'Auto-created from POS checkout.')
    returning * into v_customer;
  end if;

  new.customer_id := v_customer.id;
  new.customer_name := v_customer.full_name;

  return new;
end;
$$;

drop trigger if exists customer_resolve_order_before_insert on public.sales_orders;
create trigger customer_resolve_order_before_insert
before insert or update of customer_id, customer_name, branch_id on public.sales_orders
for each row execute function public.customer_resolve_order_customer();

create or replace function public.customer_sync_order_loyalty(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.sales_orders;
  v_settings public.customer_loyalty_settings;
  v_points integer := 0;
begin
  select *
  into v_order
  from public.sales_orders
  where id = p_order_id;

  if v_order.id is null or v_order.customer_id is null then
    return;
  end if;

  select *
  into v_settings
  from public.customer_loyalty_settings
  where branch_id = v_order.branch_id;

  if v_order.status <> 'completed' or coalesce(v_settings.is_active, true) = false then
    update public.customer_loyalty_ledger
    set status = 'voided',
        voided_at = coalesce(voided_at, now()),
        void_reason = coalesce(void_reason, 'Order no longer completed')
    where order_id = v_order.id
      and entry_type = 'earn'
      and status = 'posted';

    perform public.customer_sync_balances(v_order.customer_id);
    return;
  end if;

  v_points := floor(v_order.total / coalesce(nullif(v_settings.peso_per_point, 0), 100))::integer;

  if v_points <= 0 then
    return;
  end if;

  insert into public.customer_loyalty_ledger (
    branch_id,
    customer_id,
    order_id,
    entry_type,
    points_delta,
    description
  )
  values (
    v_order.branch_id,
    v_order.customer_id,
    v_order.id,
    'earn',
    v_points,
    'Loyalty points earned from invoice ' || coalesce(v_order.invoice_number, v_order.order_number)
  )
  on conflict (order_id) where entry_type = 'earn' and order_id is not null do update
  set customer_id = excluded.customer_id,
      branch_id = excluded.branch_id,
      points_delta = excluded.points_delta,
      description = excluded.description,
      status = 'posted',
      voided_by = null,
      voided_at = null,
      void_reason = null;

  perform public.customer_sync_balances(v_order.customer_id);
end;
$$;

create or replace function public.customer_sync_order_receivable(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.sales_orders;
  v_cod_amount numeric(14, 2) := 0;
begin
  select *
  into v_order
  from public.sales_orders
  where id = p_order_id;

  if v_order.id is null or v_order.customer_id is null then
    return;
  end if;

  select coalesce(sum(amount) filter (where method = 'cod' and status in ('paid', 'pending', 'settled')), 0)::numeric(14, 2)
  into v_cod_amount
  from public.sales_order_payments
  where order_id = v_order.id;

  if v_order.status <> 'completed' or v_cod_amount <= 0 then
    update public.customer_account_entries
    set status = 'voided',
        voided_at = coalesce(voided_at, now()),
        void_reason = coalesce(void_reason, 'Order receivable reversed')
    where order_id = v_order.id
      and entry_type = 'credit_sale'
      and source = 'pos_cod'
      and status = 'posted';
  else
    insert into public.customer_account_entries (
      branch_id,
      customer_id,
      order_id,
      entry_type,
      receivable_delta,
      reference_number,
      description,
      source
    )
    values (
      v_order.branch_id,
      v_order.customer_id,
      v_order.id,
      'credit_sale',
      v_cod_amount,
      coalesce(v_order.invoice_number, v_order.order_number),
      'COD / customer receivable from POS invoice ' || coalesce(v_order.invoice_number, v_order.order_number),
      'pos_cod'
    )
    on conflict (order_id) where entry_type = 'credit_sale' and order_id is not null do update
    set customer_id = excluded.customer_id,
        branch_id = excluded.branch_id,
        receivable_delta = excluded.receivable_delta,
        reference_number = excluded.reference_number,
        description = excluded.description,
        source = 'pos_cod',
        status = 'posted',
        voided_by = null,
        voided_at = null,
        void_reason = null;
  end if;

  perform public.customer_sync_balances(v_order.customer_id);
end;
$$;

create or replace function public.customer_after_order_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if TG_OP = 'UPDATE' and old.customer_id is not null and old.customer_id <> coalesce(new.customer_id, old.customer_id) then
    perform public.customer_recalculate_stats(old.customer_id);
    perform public.customer_sync_balances(old.customer_id);
  end if;

  if new.customer_id is not null then
    perform public.customer_recalculate_stats(new.customer_id);
    perform public.customer_sync_order_loyalty(new.id);
    perform public.customer_sync_order_receivable(new.id);
  end if;

  return new;
end;
$$;

drop trigger if exists customer_after_order_insert_update on public.sales_orders;
create trigger customer_after_order_insert_update
after insert or update of customer_id, status, total, invoice_number, customer_name on public.sales_orders
for each row execute function public.customer_after_order_change();

create or replace function public.customer_after_payment_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order_id uuid;
begin
  if TG_OP = 'DELETE' then
    v_order_id := old.order_id;
  else
    v_order_id := new.order_id;
  end if;

  if v_order_id is not null then
    perform public.customer_sync_order_receivable(v_order_id);
  end if;

  if TG_OP = 'DELETE' then
    return old;
  end if;

  return new;
end;
$$;

drop trigger if exists customer_after_payment_insert on public.sales_order_payments;
create trigger customer_after_payment_insert
after insert on public.sales_order_payments
for each row execute function public.customer_after_payment_change();

drop trigger if exists customer_after_payment_update on public.sales_order_payments;
create trigger customer_after_payment_update
after update of amount, method, status on public.sales_order_payments
for each row execute function public.customer_after_payment_change();

drop trigger if exists customer_after_payment_delete on public.sales_order_payments;
create trigger customer_after_payment_delete
after delete on public.sales_order_payments
for each row execute function public.customer_after_payment_change();

create or replace function public.customer_management_get(
  p_from date default current_date - 89,
  p_to date default current_date,
  p_branch_id uuid default null,
  p_customer_id uuid default null,
  p_search text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.user_profiles;
  v_from date := coalesce(p_from, current_date - 89);
  v_to date := coalesce(p_to, current_date);
  v_branch_filter uuid := p_branch_id;
  v_customer_filter uuid := p_customer_id;
  v_branch_ids uuid[];
  v_search text := lower(trim(coalesce(p_search, '')));
  v_permission_branch uuid;
  v_result jsonb;
begin
  v_profile := public.ensure_active_user();

  if v_to < v_from then
    raise exception 'To date must be after from date' using errcode = '22007';
  end if;

  if v_profile.role not in ('admin', 'auditor') then
    v_branch_filter := v_profile.branch_id;
  end if;

  v_permission_branch := coalesce(v_branch_filter, v_profile.branch_id);

  if public.customer_user_can_view(v_permission_branch) = false then
    raise exception 'You cannot view customer management' using errcode = '42501';
  end if;

  v_branch_ids := public.customer_visible_branch_ids(v_profile);

  with visible_branches as (
    select b.*
    from public.branches b
    where b.is_active = true
      and b.id = any(v_branch_ids)
      and (v_branch_filter is null or b.id = v_branch_filter)
  ),
  customer_rows as (
    select
      c.*,
      b.branch_code,
      b.name as branch_name,
      coalesce(period_sales.order_count, 0)::integer as period_orders,
      coalesce(period_sales.sales_value, 0)::numeric(14, 2) as period_sales,
      coalesce(period_sales.last_order_at, c.last_purchase_at) as period_last_order_at
    from public.customers c
    left join public.branches b on b.id = c.branch_id
    left join lateral (
      select
        count(*)::integer as order_count,
        coalesce(sum(so.total), 0)::numeric(14, 2) as sales_value,
        max(so.created_at) as last_order_at
      from public.sales_orders so
      join visible_branches vb on vb.id = so.branch_id
      where so.customer_id = c.id
        and so.status = 'completed'
        and so.business_date >= v_from
        and so.business_date <= v_to
    ) period_sales on true
    where (v_customer_filter is null or c.id = v_customer_filter)
      and (c.branch_id is null or c.branch_id in (select id from visible_branches))
      and (
        v_search = ''
        or lower(c.customer_code) like '%' || v_search || '%'
        or lower(c.full_name) like '%' || v_search || '%'
        or lower(coalesce(c.phone, '')) like '%' || v_search || '%'
        or lower(coalesce(c.email, '')) like '%' || v_search || '%'
        or lower(coalesce(c.tin, '')) like '%' || v_search || '%'
      )
  ),
  order_rows as (
    select
      so.*,
      b.branch_code,
      b.name as branch_name,
      c.customer_code,
      c.full_name as customer_full_name,
      up.full_name as cashier_name,
      coalesce(payments.payments, '[]'::jsonb) as payments
    from public.sales_orders so
    join visible_branches b on b.id = so.branch_id
    left join public.customers c on c.id = so.customer_id
    left join public.user_profiles up on up.id = so.user_id
    left join lateral (
      select jsonb_agg(to_jsonb(sop) order by sop.created_at asc) as payments
      from public.sales_order_payments sop
      where sop.order_id = so.id
    ) payments on true
    where so.business_date >= v_from
      and so.business_date <= v_to
      and (v_customer_filter is null or so.customer_id = v_customer_filter)
      and (
        v_search = ''
        or lower(coalesce(so.invoice_number, '')) like '%' || v_search || '%'
        or lower(so.order_number) like '%' || v_search || '%'
        or lower(coalesce(so.customer_name, '')) like '%' || v_search || '%'
        or lower(coalesce(c.full_name, '')) like '%' || v_search || '%'
      )
  ),
  account_rows as (
    select
      cae.*,
      b.branch_code,
      b.name as branch_name,
      c.customer_code,
      c.full_name as customer_full_name,
      so.invoice_number,
      so.order_number,
      creator.full_name as created_by_name,
      voider.full_name as voided_by_name
    from public.customer_account_entries cae
    join visible_branches b on b.id = cae.branch_id
    join public.customers c on c.id = cae.customer_id
    left join public.sales_orders so on so.id = cae.order_id
    left join public.user_profiles creator on creator.id = cae.created_by
    left join public.user_profiles voider on voider.id = cae.voided_by
    where cae.created_at::date >= v_from
      and cae.created_at::date <= v_to
      and (v_customer_filter is null or cae.customer_id = v_customer_filter)
      and (
        v_search = ''
        or lower(cae.entry_type) like '%' || v_search || '%'
        or lower(c.full_name) like '%' || v_search || '%'
        or lower(coalesce(cae.reference_number, '')) like '%' || v_search || '%'
        or lower(coalesce(so.invoice_number, '')) like '%' || v_search || '%'
      )
  ),
  loyalty_rows as (
    select
      cll.*,
      b.branch_code,
      b.name as branch_name,
      c.customer_code,
      c.full_name as customer_full_name,
      so.invoice_number,
      so.order_number,
      creator.full_name as created_by_name
    from public.customer_loyalty_ledger cll
    join visible_branches b on b.id = cll.branch_id
    join public.customers c on c.id = cll.customer_id
    left join public.sales_orders so on so.id = cll.order_id
    left join public.user_profiles creator on creator.id = cll.created_by
    where cll.created_at::date >= v_from
      and cll.created_at::date <= v_to
      and (v_customer_filter is null or cll.customer_id = v_customer_filter)
  ),
  daily_sales as (
    select
      orow.business_date,
      to_char(orow.business_date, 'Mon DD') as label,
      count(orow.id)::integer as orders,
      coalesce(sum(orow.total), 0)::numeric(14, 2) as sales
    from order_rows orow
    where orow.status = 'completed'
    group by orow.business_date
  ),
  branch_summary as (
    select
      vb.id as branch_id,
      vb.branch_code,
      vb.name as branch_name,
      coalesce(order_stats.orders, 0)::integer as orders,
      coalesce(order_stats.sales, 0)::numeric(14, 2) as sales,
      coalesce(account_stats.receivable_balance, 0)::numeric(14, 2) as receivable_balance,
      coalesce(account_stats.store_credit_balance, 0)::numeric(14, 2) as store_credit_balance
    from visible_branches vb
    left join lateral (
      select
        count(*)::integer as orders,
        coalesce(sum(total), 0)::numeric(14, 2) as sales
      from order_rows orow
      where orow.branch_id = vb.id
        and orow.status = 'completed'
    ) order_stats on true
    left join lateral (
      select
        coalesce(sum(receivable_delta) filter (where status = 'posted'), 0)::numeric(14, 2) as receivable_balance,
        coalesce(sum(store_credit_delta) filter (where status = 'posted'), 0)::numeric(14, 2) as store_credit_balance
      from account_rows ar
      where ar.branch_id = vb.id
    ) account_stats on true
  )
  select jsonb_build_object(
    'period', jsonb_build_object('from', v_from, 'to', v_to),
    'branches', coalesce((
      select jsonb_agg(
        jsonb_build_object('id', id, 'branch_code', branch_code, 'name', name, 'is_head_office', is_head_office)
        order by is_head_office desc, name
      )
      from visible_branches
    ), '[]'::jsonb),
    'customers', coalesce((select jsonb_agg(to_jsonb(customer_rows) order by receivable_balance desc, full_name) from customer_rows), '[]'::jsonb),
    'orders', coalesce((select jsonb_agg(to_jsonb(order_rows) order by created_at desc) from (select * from order_rows order by created_at desc limit 150) order_rows), '[]'::jsonb),
    'account_entries', coalesce((select jsonb_agg(to_jsonb(account_rows) order by created_at desc) from (select * from account_rows order by created_at desc limit 150) account_rows), '[]'::jsonb),
    'loyalty_ledger', coalesce((select jsonb_agg(to_jsonb(loyalty_rows) order by created_at desc) from (select * from loyalty_rows order by created_at desc limit 150) loyalty_rows), '[]'::jsonb),
    'daily_sales', coalesce((select jsonb_agg(to_jsonb(daily_sales) order by business_date) from daily_sales), '[]'::jsonb),
    'branch_summary', coalesce((select jsonb_agg(to_jsonb(branch_summary) order by sales desc, branch_name) from branch_summary), '[]'::jsonb),
    'top_customers', coalesce((
      select jsonb_agg(to_jsonb(top_rows) order by top_rows.period_sales desc)
      from (
        select *
        from customer_rows
        where period_sales > 0
        order by period_sales desc, full_name
        limit 8
      ) top_rows
    ), '[]'::jsonb),
    'loyalty_settings', coalesce((
      select jsonb_agg(to_jsonb(cls) order by b.name)
      from public.customer_loyalty_settings cls
      join visible_branches b on b.id = cls.branch_id
    ), '[]'::jsonb),
    'summary', jsonb_build_object(
      'customer_count', coalesce((select count(*) from customer_rows), 0),
      'active_customers', coalesce((select count(*) from customer_rows where is_active), 0),
      'sales_value', coalesce((select sum(total) from order_rows where status = 'completed'), 0),
      'order_count', coalesce((select count(*) from order_rows where status = 'completed'), 0),
      'receivable_balance', coalesce((select sum(receivable_balance) from customer_rows), 0),
      'store_credit_balance', coalesce((select sum(store_credit_balance) from customer_rows), 0),
      'loyalty_points', coalesce((select sum(loyalty_points) from customer_rows), 0),
      'credit_sales', coalesce((select sum(receivable_delta) from account_rows where entry_type = 'credit_sale' and status = 'posted'), 0),
      'payments_collected', abs(coalesce((select sum(receivable_delta) from account_rows where entry_type in ('payment', 'write_off') and status = 'posted'), 0))
    ),
    'can_manage_customers', public.customer_user_can_manage(v_permission_branch),
    'can_credit_customers', public.customer_user_can_credit(v_permission_branch),
    'generated_at', now()
  )
  into v_result;

  return v_result;
end;
$$;

create or replace function public.customer_profile_save(p_customer_id uuid, p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor public.user_profiles;
  v_customer_id uuid;
  v_branch_id uuid := nullif(p_payload->>'branch_id', '')::uuid;
  v_name text := trim(coalesce(p_payload->>'full_name', ''));
  v_code text := upper(trim(coalesce(p_payload->>'customer_code', '')));
  v_type text := lower(trim(coalesce(nullif(p_payload->>'customer_type', ''), 'regular')));
begin
  v_actor := public.ensure_active_user();
  v_branch_id := coalesce(v_branch_id, v_actor.branch_id);

  if public.customer_user_can_manage(v_branch_id) = false then
    raise exception 'You cannot save customers for this branch' using errcode = '42501';
  end if;

  if v_name = '' then
    raise exception 'Customer full name is required' using errcode = '23502';
  end if;

  if v_type not in ('regular', 'senior', 'pwd', 'company') then
    raise exception 'Invalid customer type' using errcode = '22023';
  end if;

  if v_code = '' then
    v_code := public.customer_next_code(v_name);
  end if;

  if p_customer_id is null then
    insert into public.customers (
      customer_code,
      full_name,
      phone,
      email,
      tin,
      address,
      birth_date,
      customer_type,
      branch_id,
      credit_limit,
      is_active,
      notes
    )
    values (
      v_code,
      v_name,
      nullif(trim(coalesce(p_payload->>'phone', '')), ''),
      nullif(trim(coalesce(p_payload->>'email', '')), ''),
      nullif(trim(coalesce(p_payload->>'tin', '')), ''),
      nullif(trim(coalesce(p_payload->>'address', '')), ''),
      nullif(p_payload->>'birth_date', '')::date,
      v_type,
      v_branch_id,
      coalesce(nullif(p_payload->>'credit_limit', '')::numeric, 0),
      coalesce((p_payload->>'is_active')::boolean, true),
      nullif(trim(coalesce(p_payload->>'notes', '')), '')
    )
    returning id into v_customer_id;
  else
    update public.customers
    set customer_code = v_code,
        full_name = v_name,
        phone = nullif(trim(coalesce(p_payload->>'phone', phone, '')), ''),
        email = nullif(trim(coalesce(p_payload->>'email', email, '')), ''),
        tin = nullif(trim(coalesce(p_payload->>'tin', tin, '')), ''),
        address = nullif(trim(coalesce(p_payload->>'address', address, '')), ''),
        birth_date = nullif(coalesce(p_payload->>'birth_date', birth_date::text, ''), '')::date,
        customer_type = v_type,
        branch_id = v_branch_id,
        credit_limit = coalesce(nullif(p_payload->>'credit_limit', '')::numeric, credit_limit),
        is_active = coalesce((p_payload->>'is_active')::boolean, is_active),
        notes = nullif(trim(coalesce(p_payload->>'notes', notes, '')), '')
    where id = p_customer_id
    returning id into v_customer_id;

    if v_customer_id is null then
      raise exception 'Customer not found' using errcode = '02000';
    end if;
  end if;

  perform public.log_activity('customer.profile_saved', 'customer', v_customer_id::text, jsonb_build_object('customer_code', v_code, 'name', v_name), v_actor.id);

  return public.customer_management_get(current_date - 89, current_date, v_branch_id, null, null);
end;
$$;

create or replace function public.customer_account_entry_post(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor public.user_profiles;
  v_branch_id uuid := nullif(p_payload->>'branch_id', '')::uuid;
  v_customer_id uuid := nullif(p_payload->>'customer_id', '')::uuid;
  v_customer public.customers;
  v_type text := lower(trim(coalesce(p_payload->>'entry_type', '')));
  v_amount numeric(14, 2) := abs(coalesce(nullif(p_payload->>'amount', '')::numeric, 0));
  v_receivable_delta numeric(14, 2) := 0;
  v_store_credit_delta numeric(14, 2) := 0;
  v_entry_id uuid;
begin
  v_actor := public.ensure_active_user();

  if v_customer_id is null then
    raise exception 'Customer is required' using errcode = '23502';
  end if;

  select *
  into v_customer
  from public.customers
  where id = v_customer_id
  for update;

  if v_customer.id is null then
    raise exception 'Customer not found' using errcode = '02000';
  end if;

  v_branch_id := coalesce(v_branch_id, v_customer.branch_id, v_actor.branch_id);

  if v_branch_id is null then
    raise exception 'Branch is required' using errcode = '23502';
  end if;

  if public.customer_user_can_credit(v_branch_id) = false then
    raise exception 'You cannot post customer credit entries for this branch' using errcode = '42501';
  end if;

  if v_type not in ('credit_sale', 'payment', 'store_credit_issue', 'store_credit_use', 'adjustment', 'write_off', 'return_credit') then
    raise exception 'Invalid customer account entry type' using errcode = '22023';
  end if;

  if v_type = 'adjustment' then
    v_receivable_delta := coalesce(nullif(p_payload->>'receivable_delta', '')::numeric, 0);
    v_store_credit_delta := coalesce(nullif(p_payload->>'store_credit_delta', '')::numeric, 0);
  elsif v_amount <= 0 then
    raise exception 'Amount must be greater than zero' using errcode = '23514';
  elsif v_type = 'credit_sale' then
    v_receivable_delta := v_amount;
  elsif v_type in ('payment', 'write_off') then
    if v_amount > v_customer.receivable_balance + 0.01 then
      raise exception 'Amount cannot exceed customer receivable balance' using errcode = '23514';
    end if;
    v_receivable_delta := -v_amount;
  elsif v_type in ('store_credit_issue', 'return_credit') then
    v_store_credit_delta := v_amount;
  elsif v_type = 'store_credit_use' then
    if v_amount > v_customer.store_credit_balance + 0.01 then
      raise exception 'Amount cannot exceed customer store credit balance' using errcode = '23514';
    end if;
    v_store_credit_delta := -v_amount;
  end if;

  if v_receivable_delta = 0 and v_store_credit_delta = 0 then
    raise exception 'Entry amount cannot be zero' using errcode = '23514';
  end if;

  insert into public.customer_account_entries (
    branch_id,
    customer_id,
    entry_type,
    receivable_delta,
    store_credit_delta,
    reference_number,
    description,
    source,
    created_by
  )
  values (
    v_branch_id,
    v_customer_id,
    v_type,
    v_receivable_delta,
    v_store_credit_delta,
    nullif(trim(coalesce(p_payload->>'reference_number', '')), ''),
    nullif(trim(coalesce(p_payload->>'description', '')), ''),
    'manual',
    v_actor.id
  )
  returning id into v_entry_id;

  perform public.customer_sync_balances(v_customer_id);
  perform public.log_activity('customer.account_entry_posted', 'customer_account_entry', v_entry_id::text, jsonb_build_object('customer_id', v_customer_id, 'entry_type', v_type), v_actor.id);

  return public.customer_management_get(current_date - 89, current_date, v_branch_id, null, null);
end;
$$;

create or replace function public.customer_account_entry_void(p_entry_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor public.user_profiles;
  v_entry public.customer_account_entries;
  v_reason text := trim(coalesce(p_reason, ''));
begin
  v_actor := public.ensure_active_user();

  select *
  into v_entry
  from public.customer_account_entries
  where id = p_entry_id
  for update;

  if v_entry.id is null then
    raise exception 'Customer account entry not found' using errcode = '02000';
  end if;

  if v_entry.status <> 'posted' then
    raise exception 'Only posted customer entries can be voided' using errcode = '23514';
  end if;

  if v_reason = '' then
    raise exception 'Void reason is required' using errcode = '23502';
  end if;

  if public.customer_user_can_credit(v_entry.branch_id) = false then
    raise exception 'You cannot void customer credit entries for this branch' using errcode = '42501';
  end if;

  update public.customer_account_entries
  set status = 'voided',
      voided_by = v_actor.id,
      voided_at = now(),
      void_reason = v_reason
  where id = p_entry_id;

  perform public.customer_sync_balances(v_entry.customer_id);
  perform public.log_activity('customer.account_entry_voided', 'customer_account_entry', p_entry_id::text, jsonb_build_object('reason', v_reason), v_actor.id);

  return public.customer_management_get(current_date - 89, current_date, v_entry.branch_id, null, null);
end;
$$;

create or replace function public.customer_loyalty_adjust(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor public.user_profiles;
  v_branch_id uuid := nullif(p_payload->>'branch_id', '')::uuid;
  v_customer_id uuid := nullif(p_payload->>'customer_id', '')::uuid;
  v_points integer := coalesce(nullif(p_payload->>'points_delta', '')::integer, 0);
  v_entry_id uuid;
begin
  v_actor := public.ensure_active_user();

  if v_customer_id is null or v_points = 0 then
    raise exception 'Customer and non-zero points are required' using errcode = '23502';
  end if;

  select coalesce(v_branch_id, branch_id, v_actor.branch_id)
  into v_branch_id
  from public.customers
  where id = v_customer_id;

  if v_branch_id is null then
    raise exception 'Branch is required' using errcode = '23502';
  end if;

  if public.customer_user_can_credit(v_branch_id) = false then
    raise exception 'You cannot adjust customer loyalty for this branch' using errcode = '42501';
  end if;

  insert into public.customer_loyalty_ledger (
    branch_id,
    customer_id,
    entry_type,
    points_delta,
    description,
    created_by
  )
  values (
    v_branch_id,
    v_customer_id,
    'adjust',
    v_points,
    nullif(trim(coalesce(p_payload->>'description', '')), ''),
    v_actor.id
  )
  returning id into v_entry_id;

  perform public.customer_sync_balances(v_customer_id);
  perform public.log_activity('customer.loyalty_adjusted', 'customer_loyalty_entry', v_entry_id::text, jsonb_build_object('customer_id', v_customer_id, 'points_delta', v_points), v_actor.id);

  return public.customer_management_get(current_date - 89, current_date, v_branch_id, null, null);
end;
$$;

create or replace function public.customer_pos_options_get(p_branch_id uuid default null, p_search text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.user_profiles;
  v_branch_id uuid := p_branch_id;
  v_search text := lower(trim(coalesce(p_search, '')));
  v_branch_ids uuid[];
  v_result jsonb;
begin
  v_profile := public.ensure_active_user();

  if v_profile.role not in ('admin', 'auditor') then
    v_branch_id := v_profile.branch_id;
  end if;

  if public.customer_user_can_view(coalesce(v_branch_id, v_profile.branch_id)) = false then
    return '[]'::jsonb;
  end if;

  v_branch_ids := public.customer_visible_branch_ids(v_profile);

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', c.id,
      'customer_code', c.customer_code,
      'full_name', c.full_name,
      'phone', c.phone,
      'email', c.email,
      'customer_type', c.customer_type,
      'branch_id', c.branch_id,
      'receivable_balance', c.receivable_balance,
      'store_credit_balance', c.store_credit_balance,
      'loyalty_points', c.loyalty_points
    )
    order by c.full_name
  ), '[]'::jsonb)
  into v_result
  from public.customers c
  where c.is_active = true
    and (c.branch_id is null or c.branch_id = any(v_branch_ids))
    and (v_branch_id is null or c.branch_id is null or c.branch_id = v_branch_id)
    and (
      v_search = ''
      or lower(c.full_name) like '%' || v_search || '%'
      or lower(c.customer_code) like '%' || v_search || '%'
      or lower(coalesce(c.phone, '')) like '%' || v_search || '%'
      or lower(coalesce(c.email, '')) like '%' || v_search || '%'
    )
  limit 80;

  return coalesce(v_result, '[]'::jsonb);
end;
$$;

revoke all on function public.customer_effective_permissions(uuid, text) from public;
revoke all on function public.customer_visible_branch_ids(public.user_profiles) from public;
revoke all on function public.customer_user_can_view(uuid) from public;
revoke all on function public.customer_user_can_manage(uuid) from public;
revoke all on function public.customer_user_can_credit(uuid) from public;
revoke all on function public.customer_next_code(text) from public;
revoke all on function public.customer_sync_balances(uuid) from public;
revoke all on function public.customer_recalculate_stats(uuid) from public;
revoke all on function public.customer_management_get(date, date, uuid, uuid, text) from public;
revoke all on function public.customer_profile_save(uuid, jsonb) from public;
revoke all on function public.customer_account_entry_post(jsonb) from public;
revoke all on function public.customer_account_entry_void(uuid, text) from public;
revoke all on function public.customer_loyalty_adjust(jsonb) from public;
revoke all on function public.customer_pos_options_get(uuid, text) from public;

grant execute on function public.customer_management_get(date, date, uuid, uuid, text) to authenticated;
grant execute on function public.customer_profile_save(uuid, jsonb) to authenticated;
grant execute on function public.customer_account_entry_post(jsonb) to authenticated;
grant execute on function public.customer_account_entry_void(uuid, text) to authenticated;
grant execute on function public.customer_loyalty_adjust(jsonb) to authenticated;
grant execute on function public.customer_pos_options_get(uuid, text) to authenticated;

notify pgrst, 'reload schema';
