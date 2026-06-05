-- MODULE 17: EXPENSES
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
-- 17. supabase/16-customer-management.sql
--
-- Scope:
-- - Branch expenses
-- - Expense categories
-- - Expense approval
-- - Paid expense tracking
-- - Branch, category, and daily expense reporting

create extension if not exists pgcrypto;

create table if not exists public.expense_categories (
  id uuid primary key default gen_random_uuid(),
  category_code text not null unique,
  name text not null,
  description text,
  is_active boolean not null default true,
  sort_order integer not null default 100,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

drop trigger if exists set_expense_categories_updated_at on public.expense_categories;
create trigger set_expense_categories_updated_at
before update on public.expense_categories
for each row execute function public.set_updated_at();

create table if not exists public.expenses (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches(id) on delete restrict,
  category_id uuid not null references public.expense_categories(id) on delete restrict,
  expense_number text not null unique,
  expense_date date not null default current_date,
  payee text,
  description text not null,
  amount numeric(14, 2) not null check (amount > 0),
  tax_amount numeric(14, 2) not null default 0 check (tax_amount >= 0),
  total_amount numeric(14, 2) not null default 0 check (total_amount >= 0),
  payment_method text not null default 'cash',
  reference_number text,
  status text not null default 'submitted',
  notes text,
  requested_by uuid references public.user_profiles(id) on delete set null,
  approved_by uuid references public.user_profiles(id) on delete set null,
  approved_at timestamptz,
  rejected_by uuid references public.user_profiles(id) on delete set null,
  rejected_at timestamptz,
  reject_reason text,
  paid_by uuid references public.user_profiles(id) on delete set null,
  paid_at timestamptz,
  voided_by uuid references public.user_profiles(id) on delete set null,
  voided_at timestamptz,
  void_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint expenses_status_check check (status in ('draft', 'submitted', 'approved', 'rejected', 'paid', 'voided')),
  constraint expenses_payment_method_check check (payment_method in ('cash', 'card', 'gcash', 'maya', 'bank_transfer', 'check', 'other'))
);

drop trigger if exists set_expenses_updated_at on public.expenses;
create trigger set_expenses_updated_at
before update on public.expenses
for each row execute function public.set_updated_at();

create index if not exists idx_expenses_branch_date on public.expenses(branch_id, expense_date desc, created_at desc);
create index if not exists idx_expenses_category_date on public.expenses(category_id, expense_date desc);
create index if not exists idx_expenses_status_date on public.expenses(status, expense_date desc);

alter table public.expense_categories enable row level security;
alter table public.expenses enable row level security;

insert into public.expense_categories (category_code, name, description, sort_order)
values
  ('RENT', 'Rent', 'Branch rent and lease payments.', 10),
  ('UTIL', 'Utilities', 'Electricity, water, internet, and communication expenses.', 20),
  ('SAL', 'Salaries', 'Payroll and staff-related expense entries.', 30),
  ('SUPP', 'Supplies', 'Store supplies and consumables.', 40),
  ('MAINT', 'Maintenance', 'Repairs, equipment maintenance, and service costs.', 50),
  ('TRANS', 'Transportation', 'Delivery, fuel, freight, and travel expenses.', 60),
  ('MKTG', 'Marketing', 'Promotions, ads, signage, and marketing expenses.', 70),
  ('MISC', 'Miscellaneous', 'Other approved branch expenses.', 100)
on conflict (category_code) do update
set name = excluded.name,
    description = excluded.description,
    sort_order = excluded.sort_order,
    is_active = true;

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
      'expenses.view',
      'expenses.manage',
      'expenses.approve',
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
      'expenses.view',
      'expenses.manage',
      'expenses.approve',
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
      'expenses.view',
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
    jsonb_build_object('key', 'expenses.view', 'label', 'View expenses'),
    jsonb_build_object('key', 'expenses.manage', 'label', 'Create and edit expenses'),
    jsonb_build_object('key', 'expenses.approve', 'label', 'Approve, reject, pay, or void expenses'),
    jsonb_build_object('key', 'activity.view', 'label', 'View activity logs'),
    jsonb_build_object('key', 'pos.sell', 'label', 'Use POS checkout'),
    jsonb_build_object('key', 'pos.discount', 'label', 'Apply discounts'),
    jsonb_build_object('key', 'pos.void', 'label', 'Void transactions'),
    jsonb_build_object('key', 'reports.view', 'label', 'View reports')
  )
$$;

create or replace function public.expense_effective_permissions(p_user_id uuid, p_role text)
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

create or replace function public.expense_visible_branch_ids(p_profile public.user_profiles)
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

create or replace function public.expense_user_can_view(p_branch_id uuid)
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
  v_permissions := public.expense_effective_permissions(v_profile.id, v_profile.role);

  if not coalesce('expenses.view' = any(v_permissions), false) and v_profile.role <> 'admin' then
    return false;
  end if;

  if v_profile.role in ('admin', 'auditor') then
    return true;
  end if;

  return p_branch_id is not null and v_profile.branch_id = p_branch_id;
end;
$$;

create or replace function public.expense_user_can_manage(p_branch_id uuid)
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
  v_permissions := public.expense_effective_permissions(v_profile.id, v_profile.role);

  if v_profile.role = 'admin' then
    return true;
  end if;

  return v_profile.role = 'manager'
    and (p_branch_id is null or v_profile.branch_id = p_branch_id)
    and coalesce('expenses.manage' = any(v_permissions), false);
end;
$$;

create or replace function public.expense_user_can_approve(p_branch_id uuid)
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
  v_permissions := public.expense_effective_permissions(v_profile.id, v_profile.role);

  if v_profile.role = 'admin' then
    return true;
  end if;

  return v_profile.role = 'manager'
    and (p_branch_id is null or v_profile.branch_id = p_branch_id)
    and coalesce('expenses.approve' = any(v_permissions), false);
end;
$$;

drop policy if exists expense_categories_select_by_role on public.expense_categories;
create policy expense_categories_select_by_role
on public.expense_categories
for select
to authenticated
using (public.current_user_role() is not null);

drop policy if exists expenses_select_by_role on public.expenses;
create policy expenses_select_by_role
on public.expenses
for select
to authenticated
using (public.expense_user_can_view(branch_id));

create or replace function public.expense_management_get(
  p_from date default current_date - 89,
  p_to date default current_date,
  p_branch_id uuid default null,
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

  if public.expense_user_can_view(v_permission_branch) = false then
    raise exception 'You cannot view expenses' using errcode = '42501';
  end if;

  v_branch_ids := public.expense_visible_branch_ids(v_profile);

  with visible_branches as (
    select b.*
    from public.branches b
    where b.is_active = true
      and b.id = any(v_branch_ids)
      and (v_branch_filter is null or b.id = v_branch_filter)
  ),
  expense_rows as (
    select
      e.*,
      b.branch_code,
      b.name as branch_name,
      ec.category_code,
      ec.name as category_name,
      requester.full_name as requested_by_name,
      approver.full_name as approved_by_name,
      payer.full_name as paid_by_name
    from public.expenses e
    join visible_branches b on b.id = e.branch_id
    join public.expense_categories ec on ec.id = e.category_id
    left join public.user_profiles requester on requester.id = e.requested_by
    left join public.user_profiles approver on approver.id = e.approved_by
    left join public.user_profiles payer on payer.id = e.paid_by
    where e.expense_date >= v_from
      and e.expense_date <= v_to
      and (
        v_search = ''
        or lower(e.expense_number) like '%' || v_search || '%'
        or lower(ec.name) like '%' || v_search || '%'
        or lower(coalesce(e.payee, '')) like '%' || v_search || '%'
        or lower(e.description) like '%' || v_search || '%'
        or lower(coalesce(e.reference_number, '')) like '%' || v_search || '%'
      )
  ),
  category_rows as (
    select
      ec.*,
      coalesce(stats.expense_count, 0)::integer as expense_count,
      coalesce(stats.total_amount, 0)::numeric(14, 2) as total_amount
    from public.expense_categories ec
    left join lateral (
      select
        count(*)::integer as expense_count,
        coalesce(sum(er.total_amount) filter (where er.status in ('approved', 'paid')), 0)::numeric(14, 2) as total_amount
      from expense_rows er
      where er.category_id = ec.id
    ) stats on true
    order by ec.sort_order, ec.name
  ),
  daily_expenses as (
    select
      er.expense_date as business_date,
      to_char(er.expense_date, 'Mon DD') as label,
      count(er.id)::integer as expenses,
      coalesce(sum(er.total_amount), 0)::numeric(14, 2) as total_amount
    from expense_rows er
    where er.status in ('approved', 'paid')
    group by er.expense_date
  ),
  category_summary as (
    select
      cr.id as category_id,
      cr.category_code,
      cr.name as category_name,
      coalesce(count(er.id) filter (where er.status in ('approved', 'paid')), 0)::integer as expenses,
      coalesce(sum(er.total_amount) filter (where er.status in ('approved', 'paid')), 0)::numeric(14, 2) as total_amount
    from category_rows cr
    left join expense_rows er on er.category_id = cr.id
    group by cr.id, cr.category_code, cr.name
  ),
  branch_summary as (
    select
      vb.id as branch_id,
      vb.branch_code,
      vb.name as branch_name,
      coalesce(count(er.id), 0)::integer as expense_count,
      coalesce(count(er.id) filter (where er.status = 'submitted'), 0)::integer as pending_count,
      coalesce(sum(er.total_amount) filter (where er.status in ('approved', 'paid')), 0)::numeric(14, 2) as approved_amount,
      coalesce(sum(er.total_amount) filter (where er.status = 'paid'), 0)::numeric(14, 2) as paid_amount
    from visible_branches vb
    left join expense_rows er on er.branch_id = vb.id
    group by vb.id, vb.branch_code, vb.name
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
    'categories', coalesce((select jsonb_agg(to_jsonb(category_rows) order by sort_order, name) from category_rows), '[]'::jsonb),
    'expenses', coalesce((select jsonb_agg(to_jsonb(expense_rows) order by expense_date desc, created_at desc) from expense_rows), '[]'::jsonb),
    'daily_expenses', coalesce((select jsonb_agg(to_jsonb(daily_expenses) order by business_date) from daily_expenses), '[]'::jsonb),
    'category_summary', coalesce((select jsonb_agg(to_jsonb(category_summary) order by total_amount desc, category_name) from category_summary), '[]'::jsonb),
    'branch_summary', coalesce((select jsonb_agg(to_jsonb(branch_summary) order by approved_amount desc, branch_name) from branch_summary), '[]'::jsonb),
    'summary', jsonb_build_object(
      'total_expenses', coalesce((select sum(total_amount) from expense_rows where status in ('approved', 'paid')), 0),
      'paid_expenses', coalesce((select sum(total_amount) from expense_rows where status = 'paid'), 0),
      'pending_approval', coalesce((select count(*) from expense_rows where status = 'submitted'), 0),
      'draft_expenses', coalesce((select count(*) from expense_rows where status = 'draft'), 0),
      'rejected_expenses', coalesce((select count(*) from expense_rows where status = 'rejected'), 0),
      'expense_count', coalesce((select count(*) from expense_rows), 0),
      'category_count', coalesce((select count(*) from category_rows where is_active), 0)
    ),
    'can_manage_expenses', public.expense_user_can_manage(v_permission_branch),
    'can_approve_expenses', public.expense_user_can_approve(v_permission_branch),
    'generated_at', now()
  )
  into v_result;

  return v_result;
end;
$$;

create or replace function public.expense_category_save(p_category_id uuid, p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor public.user_profiles;
  v_category_id uuid;
  v_name text := trim(coalesce(p_payload->>'name', ''));
  v_code text := upper(trim(coalesce(p_payload->>'category_code', '')));
begin
  v_actor := public.ensure_active_user();

  if v_actor.role <> 'admin' then
    raise exception 'Only admins can manage expense categories' using errcode = '42501';
  end if;

  if v_name = '' then
    raise exception 'Expense category name is required' using errcode = '23502';
  end if;

  if v_code = '' then
    v_code := upper(left(regexp_replace(v_name, '[^A-Za-z0-9]+', '-', 'g'), 16));
  end if;

  if v_code = '' then
    v_code := 'EXP-' || upper(left(replace(gen_random_uuid()::text, '-', ''), 5));
  end if;

  if p_category_id is null then
    insert into public.expense_categories (
      category_code,
      name,
      description,
      is_active,
      sort_order
    )
    values (
      v_code,
      v_name,
      nullif(trim(coalesce(p_payload->>'description', '')), ''),
      coalesce((p_payload->>'is_active')::boolean, true),
      coalesce(nullif(p_payload->>'sort_order', '')::integer, 100)
    )
    returning id into v_category_id;
  else
    update public.expense_categories
    set category_code = v_code,
        name = v_name,
        description = nullif(trim(coalesce(p_payload->>'description', description, '')), ''),
        is_active = coalesce((p_payload->>'is_active')::boolean, is_active),
        sort_order = coalesce(nullif(p_payload->>'sort_order', '')::integer, sort_order)
    where id = p_category_id
    returning id into v_category_id;

    if v_category_id is null then
      raise exception 'Expense category not found' using errcode = '02000';
    end if;
  end if;

  perform public.log_activity('expense.category_saved', 'expense_category', v_category_id::text, jsonb_build_object('category_code', v_code, 'name', v_name), v_actor.id);

  return public.expense_management_get(current_date - 89, current_date, null, null);
end;
$$;

create or replace function public.expense_save(p_expense_id uuid, p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor public.user_profiles;
  v_expense_id uuid := p_expense_id;
  v_existing public.expenses;
  v_branch_id uuid := nullif(p_payload->>'branch_id', '')::uuid;
  v_category_id uuid := nullif(p_payload->>'category_id', '')::uuid;
  v_status text := lower(trim(coalesce(nullif(p_payload->>'status', ''), 'submitted')));
  v_amount numeric(14, 2) := coalesce(nullif(p_payload->>'amount', '')::numeric, 0);
  v_tax_amount numeric(14, 2) := coalesce(nullif(p_payload->>'tax_amount', '')::numeric, 0);
  v_expense_number text;
begin
  v_actor := public.ensure_active_user();
  v_branch_id := coalesce(v_branch_id, v_actor.branch_id);

  if v_branch_id is null or v_category_id is null then
    raise exception 'Branch and expense category are required' using errcode = '23502';
  end if;

  if public.expense_user_can_manage(v_branch_id) = false then
    raise exception 'You cannot manage expenses for this branch' using errcode = '42501';
  end if;

  if v_status not in ('draft', 'submitted') then
    raise exception 'Expenses can only be saved as draft or submitted' using errcode = '22023';
  end if;

  if v_amount <= 0 then
    raise exception 'Expense amount must be greater than zero' using errcode = '23514';
  end if;

  if trim(coalesce(p_payload->>'description', '')) = '' then
    raise exception 'Expense description is required' using errcode = '23502';
  end if;

  if v_tax_amount < 0 then
    raise exception 'Tax amount cannot be negative' using errcode = '23514';
  end if;

  if not exists (select 1 from public.branches where id = v_branch_id and is_active = true) then
    raise exception 'Branch not found or inactive' using errcode = '02000';
  end if;

  if not exists (select 1 from public.expense_categories where id = v_category_id and is_active = true) then
    raise exception 'Expense category not found or inactive' using errcode = '02000';
  end if;

  if v_expense_id is null then
    v_expense_number := 'EXP-' || to_char(now(), 'YYYYMMDD-HH24MISS-') || upper(left(replace(gen_random_uuid()::text, '-', ''), 5));

    insert into public.expenses (
      branch_id,
      category_id,
      expense_number,
      expense_date,
      payee,
      description,
      amount,
      tax_amount,
      total_amount,
      payment_method,
      reference_number,
      status,
      notes,
      requested_by
    )
    values (
      v_branch_id,
      v_category_id,
      v_expense_number,
      coalesce(nullif(p_payload->>'expense_date', '')::date, current_date),
      nullif(trim(coalesce(p_payload->>'payee', '')), ''),
      trim(coalesce(p_payload->>'description', '')),
      v_amount,
      v_tax_amount,
      v_amount + v_tax_amount,
      lower(trim(coalesce(nullif(p_payload->>'payment_method', ''), 'cash'))),
      nullif(trim(coalesce(p_payload->>'reference_number', '')), ''),
      v_status,
      nullif(trim(coalesce(p_payload->>'notes', '')), ''),
      v_actor.id
    )
    returning id into v_expense_id;
  else
    select *
    into v_existing
    from public.expenses
    where id = v_expense_id
    for update;

    if v_existing.id is null then
      raise exception 'Expense not found' using errcode = '02000';
    end if;

    if v_existing.status not in ('draft', 'submitted', 'rejected') then
      raise exception 'Only draft, submitted, or rejected expenses can be edited' using errcode = '23514';
    end if;

    update public.expenses
    set branch_id = v_branch_id,
        category_id = v_category_id,
        expense_date = coalesce(nullif(p_payload->>'expense_date', '')::date, expense_date),
        payee = nullif(trim(coalesce(p_payload->>'payee', payee, '')), ''),
        description = trim(coalesce(p_payload->>'description', description)),
        amount = v_amount,
        tax_amount = v_tax_amount,
        total_amount = v_amount + v_tax_amount,
        payment_method = lower(trim(coalesce(nullif(p_payload->>'payment_method', ''), payment_method))),
        reference_number = nullif(trim(coalesce(p_payload->>'reference_number', reference_number, '')), ''),
        status = v_status,
        notes = nullif(trim(coalesce(p_payload->>'notes', notes, '')), ''),
        rejected_by = null,
        rejected_at = null,
        reject_reason = null
    where id = v_expense_id;
  end if;

  perform public.log_activity('expense.saved', 'expense', v_expense_id::text, jsonb_build_object('branch_id', v_branch_id, 'status', v_status), v_actor.id);

  return public.expense_management_get(current_date - 89, current_date, v_branch_id, null);
end;
$$;

create or replace function public.expense_status_update(p_expense_id uuid, p_status text, p_reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor public.user_profiles;
  v_expense public.expenses;
  v_status text := lower(trim(coalesce(p_status, '')));
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
begin
  v_actor := public.ensure_active_user();

  select *
  into v_expense
  from public.expenses
  where id = p_expense_id
  for update;

  if v_expense.id is null then
    raise exception 'Expense not found' using errcode = '02000';
  end if;

  if v_status not in ('submitted', 'approved', 'rejected', 'paid', 'voided') then
    raise exception 'Invalid expense status update' using errcode = '22023';
  end if;

  if v_status = 'submitted' then
    if public.expense_user_can_manage(v_expense.branch_id) = false then
      raise exception 'You cannot submit expenses for this branch' using errcode = '42501';
    end if;

    if v_expense.status not in ('draft', 'rejected') then
      raise exception 'Only draft or rejected expenses can be submitted' using errcode = '23514';
    end if;
  elsif v_status = 'paid' then
    if public.expense_user_can_approve(v_expense.branch_id) = false then
      raise exception 'You cannot mark expenses paid for this branch' using errcode = '42501';
    end if;

    if v_expense.status <> 'approved' then
      raise exception 'Only approved expenses can be marked paid' using errcode = '23514';
    end if;
  else
    if public.expense_user_can_approve(v_expense.branch_id) = false then
      raise exception 'You cannot approve expenses for this branch' using errcode = '42501';
    end if;
  end if;

  if v_status in ('rejected', 'voided') and v_reason is null then
    raise exception 'Reason is required' using errcode = '23502';
  end if;

  if v_status = 'approved' and v_expense.status not in ('submitted', 'rejected') then
    raise exception 'Only submitted or rejected expenses can be approved' using errcode = '23514';
  end if;

  if v_status = 'rejected' and v_expense.status not in ('submitted', 'approved') then
    raise exception 'Only submitted or approved expenses can be rejected' using errcode = '23514';
  end if;

  if v_status = 'voided' and v_expense.status = 'voided' then
    raise exception 'Expense is already voided' using errcode = '23514';
  end if;

  update public.expenses
  set status = v_status,
      approved_by = case when v_status = 'approved' then v_actor.id else approved_by end,
      approved_at = case when v_status = 'approved' then now() else approved_at end,
      rejected_by = case when v_status = 'rejected' then v_actor.id else rejected_by end,
      rejected_at = case when v_status = 'rejected' then now() else rejected_at end,
      reject_reason = case when v_status = 'rejected' then v_reason else reject_reason end,
      paid_by = case when v_status = 'paid' then v_actor.id else paid_by end,
      paid_at = case when v_status = 'paid' then now() else paid_at end,
      voided_by = case when v_status = 'voided' then v_actor.id else voided_by end,
      voided_at = case when v_status = 'voided' then now() else voided_at end,
      void_reason = case when v_status = 'voided' then v_reason else void_reason end
  where id = p_expense_id;

  perform public.log_activity('expense.status_updated', 'expense', p_expense_id::text, jsonb_build_object('status', v_status, 'reason', v_reason), v_actor.id);

  return public.expense_management_get(current_date - 89, current_date, v_expense.branch_id, null);
end;
$$;

revoke all on function public.expense_effective_permissions(uuid, text) from public;
revoke all on function public.expense_visible_branch_ids(public.user_profiles) from public;
revoke all on function public.expense_user_can_view(uuid) from public;
revoke all on function public.expense_user_can_manage(uuid) from public;
revoke all on function public.expense_user_can_approve(uuid) from public;
revoke all on function public.expense_management_get(date, date, uuid, text) from public;
revoke all on function public.expense_category_save(uuid, jsonb) from public;
revoke all on function public.expense_save(uuid, jsonb) from public;
revoke all on function public.expense_status_update(uuid, text, text) from public;

grant execute on function public.expense_management_get(date, date, uuid, text) to authenticated;
grant execute on function public.expense_category_save(uuid, jsonb) to authenticated;
grant execute on function public.expense_save(uuid, jsonb) to authenticated;
grant execute on function public.expense_status_update(uuid, text, text) to authenticated;

notify pgrst, 'reload schema';
