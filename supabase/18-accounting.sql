-- MODULE 18: ACCOUNTING
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
-- 18. supabase/17-expenses.sql
--
-- Scope:
-- - Chart of accounts
-- - Sales journal
-- - Cash ledger
-- - Accounts receivable
-- - Accounts payable
-- - Profit/loss
-- - VAT payable reports
-- - Balanced manual journals

create extension if not exists pgcrypto;

create table if not exists public.accounting_accounts (
  id uuid primary key default gen_random_uuid(),
  account_code text not null unique,
  name text not null,
  account_type text not null,
  normal_balance text not null,
  description text,
  is_system boolean not null default true,
  is_active boolean not null default true,
  sort_order integer not null default 100,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint accounting_accounts_type_check check (account_type in ('asset', 'liability', 'equity', 'revenue', 'cogs', 'expense')),
  constraint accounting_accounts_normal_check check (normal_balance in ('debit', 'credit'))
);

drop trigger if exists set_accounting_accounts_updated_at on public.accounting_accounts;
create trigger set_accounting_accounts_updated_at
before update on public.accounting_accounts
for each row execute function public.set_updated_at();

create table if not exists public.accounting_journal_entries (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches(id) on delete restrict,
  journal_number text not null unique,
  journal_date date not null default current_date,
  description text not null,
  source_type text not null default 'manual',
  source_id uuid,
  status text not null default 'posted',
  posted_by uuid references public.user_profiles(id) on delete set null,
  voided_by uuid references public.user_profiles(id) on delete set null,
  voided_at timestamptz,
  void_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint accounting_journal_entries_status_check check (status in ('posted', 'voided')),
  constraint accounting_journal_entries_source_check check (source_type in ('manual', 'adjustment', 'closing'))
);

drop trigger if exists set_accounting_journal_entries_updated_at on public.accounting_journal_entries;
create trigger set_accounting_journal_entries_updated_at
before update on public.accounting_journal_entries
for each row execute function public.set_updated_at();

create table if not exists public.accounting_journal_lines (
  id uuid primary key default gen_random_uuid(),
  journal_entry_id uuid not null references public.accounting_journal_entries(id) on delete cascade,
  account_id uuid not null references public.accounting_accounts(id) on delete restrict,
  description text,
  debit numeric(14, 2) not null default 0 check (debit >= 0),
  credit numeric(14, 2) not null default 0 check (credit >= 0),
  created_at timestamptz not null default now(),
  constraint accounting_journal_lines_amount_check check ((debit > 0 and credit = 0) or (credit > 0 and debit = 0))
);

create index if not exists idx_accounting_journal_entries_branch_date on public.accounting_journal_entries(branch_id, journal_date desc, created_at desc);
create index if not exists idx_accounting_journal_entries_status on public.accounting_journal_entries(status, journal_date desc);
create index if not exists idx_accounting_journal_lines_entry on public.accounting_journal_lines(journal_entry_id);
create index if not exists idx_accounting_journal_lines_account on public.accounting_journal_lines(account_id);

alter table public.accounting_accounts enable row level security;
alter table public.accounting_journal_entries enable row level security;
alter table public.accounting_journal_lines enable row level security;

insert into public.accounting_accounts (account_code, name, account_type, normal_balance, description, sort_order)
values
  ('1000', 'Cash and cash equivalents', 'asset', 'debit', 'Cash, card, wallet, and bank collections.', 10),
  ('1100', 'Accounts receivable', 'asset', 'debit', 'Customer receivables from credit/COD sales.', 20),
  ('1200', 'Inventory', 'asset', 'debit', 'Inventory value placeholder for purchase and stock accounting.', 30),
  ('1300', 'Input VAT', 'asset', 'debit', 'VAT paid on purchases and operating expenses.', 40),
  ('2000', 'Accounts payable', 'liability', 'credit', 'Supplier payable balances.', 50),
  ('2100', 'Output VAT', 'liability', 'credit', 'VAT collected from completed sales.', 60),
  ('2200', 'Store credit liability', 'liability', 'credit', 'Customer store-credit balances.', 70),
  ('3000', 'Owner equity', 'equity', 'credit', 'Owner capital and retained earnings.', 80),
  ('4000', 'Sales revenue', 'revenue', 'credit', 'Net sales before output VAT.', 90),
  ('5000', 'Cost of goods sold', 'cogs', 'debit', 'Cost of stock sold using FEFO batch allocations.', 100),
  ('6000', 'Operating expenses', 'expense', 'debit', 'Approved branch operating expenses before input VAT.', 110),
  ('6100', 'Payroll expense', 'expense', 'debit', 'Salary and payroll-related expense adjustments.', 120),
  ('6200', 'Rent expense', 'expense', 'debit', 'Rent and lease expense adjustments.', 130),
  ('6300', 'Utilities expense', 'expense', 'debit', 'Power, water, internet, and branch utilities.', 140),
  ('6400', 'Repairs and maintenance expense', 'expense', 'debit', 'Repairs, maintenance, and upkeep adjustments.', 150),
  ('6500', 'Marketing expense', 'expense', 'debit', 'Promotions, ads, and marketing adjustments.', 160),
  ('6900', 'Miscellaneous expense', 'expense', 'debit', 'Other operating expense adjustments.', 170),
  ('9000', 'Suspense / adjustment', 'asset', 'debit', 'Temporary balancing account for manual corrections.', 900)
on conflict (account_code) do update
set name = excluded.name,
    account_type = excluded.account_type,
    normal_balance = excluded.normal_balance,
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
      'accounting.view',
      'accounting.manage',
      'accounting.close',
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
      'accounting.view',
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
      'accounting.view',
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
    jsonb_build_object('key', 'accounting.view', 'label', 'View accounting reports'),
    jsonb_build_object('key', 'accounting.manage', 'label', 'Post manual journals'),
    jsonb_build_object('key', 'accounting.close', 'label', 'Void or close accounting journals'),
    jsonb_build_object('key', 'activity.view', 'label', 'View activity logs'),
    jsonb_build_object('key', 'pos.sell', 'label', 'Use POS checkout'),
    jsonb_build_object('key', 'pos.discount', 'label', 'Apply discounts'),
    jsonb_build_object('key', 'pos.void', 'label', 'Void transactions'),
    jsonb_build_object('key', 'reports.view', 'label', 'View reports')
  )
$$;

create or replace function public.accounting_effective_permissions(p_user_id uuid, p_role text)
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

create or replace function public.accounting_visible_branch_ids(p_profile public.user_profiles)
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

create or replace function public.accounting_user_can_view(p_branch_id uuid)
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
  v_permissions := public.accounting_effective_permissions(v_profile.id, v_profile.role);

  if not coalesce('accounting.view' = any(v_permissions), false) and v_profile.role <> 'admin' then
    return false;
  end if;

  if v_profile.role in ('admin', 'auditor') then
    return true;
  end if;

  return p_branch_id is not null and v_profile.branch_id = p_branch_id;
end;
$$;

create or replace function public.accounting_user_can_manage(p_branch_id uuid)
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
  v_permissions := public.accounting_effective_permissions(v_profile.id, v_profile.role);

  if v_profile.role = 'admin' then
    return true;
  end if;

  return v_profile.role = 'manager'
    and (p_branch_id is null or v_profile.branch_id = p_branch_id)
    and coalesce('accounting.manage' = any(v_permissions), false);
end;
$$;

create or replace function public.accounting_user_can_close(p_branch_id uuid)
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
  v_permissions := public.accounting_effective_permissions(v_profile.id, v_profile.role);

  if v_profile.role = 'admin' then
    return true;
  end if;

  return v_profile.role = 'manager'
    and (p_branch_id is null or v_profile.branch_id = p_branch_id)
    and coalesce('accounting.close' = any(v_permissions), false);
end;
$$;

drop policy if exists accounting_accounts_select_by_role on public.accounting_accounts;
create policy accounting_accounts_select_by_role
on public.accounting_accounts
for select
to authenticated
using (public.current_user_role() is not null);

drop policy if exists accounting_journal_entries_select_by_role on public.accounting_journal_entries;
create policy accounting_journal_entries_select_by_role
on public.accounting_journal_entries
for select
to authenticated
using (public.accounting_user_can_view(branch_id));

drop policy if exists accounting_journal_lines_select_by_role on public.accounting_journal_lines;
create policy accounting_journal_lines_select_by_role
on public.accounting_journal_lines
for select
to authenticated
using (
  exists (
    select 1
    from public.accounting_journal_entries aje
    where aje.id = journal_entry_id
      and public.accounting_user_can_view(aje.branch_id)
  )
);

create or replace function public.accounting_management_get(
  p_from date default current_date - 29,
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
  v_from date := coalesce(p_from, current_date - 29);
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

  if public.accounting_user_can_view(v_permission_branch) = false then
    raise exception 'You cannot view accounting reports' using errcode = '42501';
  end if;

  v_branch_ids := public.accounting_visible_branch_ids(v_profile);

  with visible_branches as (
    select b.*
    from public.branches b
    where b.is_active = true
      and b.id = any(v_branch_ids)
      and (v_branch_filter is null or b.id = v_branch_filter)
  ),
  sales_rows as (
    select
      so.id,
      so.branch_id,
      vb.branch_code,
      vb.name as branch_name,
      so.order_number,
      so.invoice_number,
      so.business_date,
      so.created_at,
      so.subtotal,
      so.discount_total,
      so.tax_total,
      case when coalesce(so.net_sales, 0) > 0 then so.net_sales else greatest(so.total - so.tax_total, 0) end as net_sales,
      so.total,
      so.payment_status,
      so.payment_method_summary,
      coalesce(up.full_name, c.name, 'Unassigned') as cashier_name,
      coalesce(cogs.amount, 0)::numeric(14, 2) as cogs_amount
    from public.sales_orders so
    join visible_branches vb on vb.id = so.branch_id
    left join public.user_profiles up on up.id = so.user_id
    left join public.cashiers c on c.id = so.cashier_id
    left join lateral (
      select coalesce(sum(soiba.quantity * soiba.unit_cost), 0)::numeric(14, 2) as amount
      from public.sales_order_items soi
      join public.sales_order_batch_allocations soiba on soiba.order_item_id = soi.id
      where soi.order_id = so.id
    ) cogs on true
    where so.business_date >= v_from
      and so.business_date <= v_to
      and so.status = 'completed'
      and (
        v_search = ''
        or lower(coalesce(so.invoice_number, '')) like '%' || v_search || '%'
        or lower(so.order_number) like '%' || v_search || '%'
        or lower(coalesce(so.payment_method_summary, '')) like '%' || v_search || '%'
        or lower(coalesce(up.full_name, c.name, '')) like '%' || v_search || '%'
      )
  ),
  payment_rows as (
    select
      sop.id,
      so.branch_id,
      vb.branch_code,
      vb.name as branch_name,
      coalesce(so.business_date, sop.created_at::date) as entry_date,
      sop.created_at,
      'sale_payment'::text as entry_type,
      'inflow'::text as direction,
      coalesce(sop.method_label, sop.method) as method,
      coalesce(so.invoice_number, so.order_number) as reference_number,
      'Sale payment - ' || coalesce(so.invoice_number, so.order_number) as description,
      coalesce(sop.amount, 0)::numeric(14, 2) as amount,
      coalesce(sop.status, 'captured') as status
    from public.sales_order_payments sop
    join public.sales_orders so on so.id = sop.order_id
    join visible_branches vb on vb.id = so.branch_id
    where so.business_date >= v_from
      and so.business_date <= v_to
      and so.status = 'completed'
      and coalesce(sop.status, 'captured') not in ('failed', 'refunded', 'void')
      and coalesce(sop.method, '') not in ('store_credit', 'cod')
  ),
  customer_payment_rows as (
    select
      cae.id,
      cae.branch_id,
      vb.branch_code,
      vb.name as branch_name,
      cae.created_at::date as entry_date,
      cae.created_at,
      'customer_payment'::text as entry_type,
      'inflow'::text as direction,
      'customer payment'::text as method,
      cae.reference_number,
      'Customer payment - ' || c.full_name as description,
      abs(coalesce(cae.receivable_delta, 0))::numeric(14, 2) as amount,
      cae.status
    from public.customer_account_entries cae
    join public.customers c on c.id = cae.customer_id
    join visible_branches vb on vb.id = cae.branch_id
    where cae.created_at::date >= v_from
      and cae.created_at::date <= v_to
      and cae.status = 'posted'
      and cae.entry_type = 'payment'
      and cae.receivable_delta < 0
  ),
  supplier_payment_rows as (
    select
      sp.id,
      sp.branch_id,
      vb.branch_code,
      vb.name as branch_name,
      sp.payment_date as entry_date,
      sp.created_at,
      'supplier_payment'::text as entry_type,
      'outflow'::text as direction,
      sp.payment_method as method,
      sp.payment_number as reference_number,
      'Supplier payment - ' || s.name as description,
      sp.amount::numeric(14, 2) as amount,
      sp.status
    from public.supplier_payments sp
    join public.suppliers s on s.id = sp.supplier_id
    join visible_branches vb on vb.id = sp.branch_id
    where sp.payment_date >= v_from
      and sp.payment_date <= v_to
      and sp.status = 'posted'
  ),
  expense_payment_rows as (
    select
      e.id,
      e.branch_id,
      vb.branch_code,
      vb.name as branch_name,
      e.expense_date as entry_date,
      e.created_at,
      'expense_payment'::text as entry_type,
      'outflow'::text as direction,
      e.payment_method as method,
      e.expense_number as reference_number,
      e.description,
      e.total_amount::numeric(14, 2) as amount,
      e.status
    from public.expenses e
    join visible_branches vb on vb.id = e.branch_id
    where e.expense_date >= v_from
      and e.expense_date <= v_to
      and e.status = 'paid'
  ),
  cash_ledger as (
    select * from payment_rows
    union all
    select * from customer_payment_rows
    union all
    select * from supplier_payment_rows
    union all
    select * from expense_payment_rows
  ),
  receivable_rows as (
    select
      c.id,
      c.branch_id,
      vb.branch_code,
      vb.name as branch_name,
      c.customer_code,
      c.full_name,
      c.phone,
      c.email,
      c.customer_type,
      c.credit_limit,
      c.receivable_balance,
      c.store_credit_balance,
      c.total_orders,
      c.total_spent,
      c.last_purchase_at
    from public.customers c
    join visible_branches vb on vb.id = c.branch_id
    where c.is_active = true
      and c.receivable_balance <> 0
  ),
  payable_rows as (
    select
      si.id,
      si.branch_id,
      vb.branch_code,
      vb.name as branch_name,
      s.supplier_code,
      s.name as supplier_name,
      si.invoice_number,
      si.invoice_date,
      si.due_date,
      si.amount,
      si.tax_amount,
      si.paid_amount,
      greatest(si.amount - si.paid_amount, 0)::numeric(14, 2) as balance_amount,
      si.status,
      case when si.status in ('pending', 'partial') and si.due_date < current_date then current_date - si.due_date else 0 end::integer as days_overdue
    from public.supplier_invoices si
    join public.suppliers s on s.id = si.supplier_id
    join visible_branches vb on vb.id = si.branch_id
    where si.status in ('pending', 'partial')
  ),
  inventory_value as (
    select
      ib.branch_id,
      coalesce(sum(ib.quantity_on_hand * ib.unit_cost), 0)::numeric(14, 2) as amount
    from public.inventory_batches ib
    join visible_branches vb on vb.id = ib.branch_id
    where ib.status = 'active'
      and ib.quantity_on_hand > 0
    group by ib.branch_id
  ),
  expense_rows as (
    select
      e.*,
      vb.branch_code,
      vb.name as branch_name,
      ec.name as category_name
    from public.expenses e
    join visible_branches vb on vb.id = e.branch_id
    join public.expense_categories ec on ec.id = e.category_id
    where e.expense_date >= v_from
      and e.expense_date <= v_to
      and e.status in ('approved', 'paid')
  ),
  supplier_invoice_rows as (
    select si.*
    from public.supplier_invoices si
    join visible_branches vb on vb.id = si.branch_id
    where si.invoice_date >= v_from
      and si.invoice_date <= v_to
      and si.status <> 'voided'
  ),
  manual_journal_rows as (
    select
      aje.*,
      vb.branch_code,
      vb.name as branch_name,
      coalesce(up.full_name, 'System') as posted_by_name,
      coalesce(line_stats.line_count, 0)::integer as line_count,
      coalesce(line_stats.debit_total, 0)::numeric(14, 2) as debit_total,
      coalesce(line_stats.credit_total, 0)::numeric(14, 2) as credit_total
    from public.accounting_journal_entries aje
    join visible_branches vb on vb.id = aje.branch_id
    left join public.user_profiles up on up.id = aje.posted_by
    left join lateral (
      select
        count(*)::integer as line_count,
        coalesce(sum(ajl.debit), 0)::numeric(14, 2) as debit_total,
        coalesce(sum(ajl.credit), 0)::numeric(14, 2) as credit_total
      from public.accounting_journal_lines ajl
      where ajl.journal_entry_id = aje.id
    ) line_stats on true
    where aje.journal_date >= v_from
      and aje.journal_date <= v_to
      and (
        v_search = ''
        or lower(aje.journal_number) like '%' || v_search || '%'
        or lower(aje.description) like '%' || v_search || '%'
      )
  ),
  manual_journal_line_rows as (
    select
      ajl.*,
      aa.account_code,
      aa.name as account_name,
      aa.account_type,
      aje.journal_number,
      aje.journal_date,
      aje.branch_id,
      vb.branch_code,
      vb.name as branch_name
    from public.accounting_journal_lines ajl
    join public.accounting_journal_entries aje on aje.id = ajl.journal_entry_id
    join public.accounting_accounts aa on aa.id = ajl.account_id
    join visible_branches vb on vb.id = aje.branch_id
    where aje.journal_date >= v_from
      and aje.journal_date <= v_to
  ),
  activity_days as (
    select business_date
    from sales_rows
    union
    select expense_date as business_date
    from expense_rows
  ),
  daily_summary as (
    select
      ad.business_date,
      to_char(ad.business_date, 'Mon DD') as label,
      coalesce(sales_by_day.revenue, 0)::numeric(14, 2) as revenue,
      coalesce(sales_by_day.cogs, 0)::numeric(14, 2) as cogs,
      coalesce(expenses_by_day.expenses, 0)::numeric(14, 2) as expenses,
      coalesce(sales_by_day.revenue, 0)::numeric(14, 2)
        - coalesce(sales_by_day.cogs, 0)::numeric(14, 2)
        - coalesce(expenses_by_day.expenses, 0)::numeric(14, 2) as net_profit
    from activity_days ad
    left join lateral (
      select
        coalesce(sum(sr.net_sales), 0)::numeric(14, 2) as revenue,
        coalesce(sum(sr.cogs_amount), 0)::numeric(14, 2) as cogs
      from sales_rows sr
      where sr.business_date = ad.business_date
    ) sales_by_day on true
    left join lateral (
      select coalesce(sum(er.total_amount - er.tax_amount), 0)::numeric(14, 2) as expenses
      from expense_rows er
      where er.expense_date = ad.business_date
    ) expenses_by_day on true
  ),
  branch_summary as (
    select
      vb.id as branch_id,
      vb.branch_code,
      vb.name as branch_name,
      coalesce(sum(sr.net_sales), 0)::numeric(14, 2) as revenue,
      coalesce(sum(sr.cogs_amount), 0)::numeric(14, 2) as cogs,
      coalesce(expense_stats.expenses, 0)::numeric(14, 2) as expenses,
      coalesce(sum(sr.net_sales), 0)::numeric(14, 2) - coalesce(sum(sr.cogs_amount), 0)::numeric(14, 2) - coalesce(expense_stats.expenses, 0)::numeric(14, 2) as net_profit
    from visible_branches vb
    left join sales_rows sr on sr.branch_id = vb.id
    left join lateral (
      select coalesce(sum(er.total_amount - er.tax_amount), 0)::numeric(14, 2) as expenses
      from expense_rows er
      where er.branch_id = vb.id
    ) expense_stats on true
    group by vb.id, vb.branch_code, vb.name, expense_stats.expenses
  ),
  profit_loss_lines as (
    select 10 as sort_order, 'Sales revenue'::text as line, 'revenue'::text as line_type, coalesce(sum(net_sales), 0)::numeric(14, 2) as amount from sales_rows
    union all
    select 20, 'Cost of goods sold', 'cogs', -coalesce(sum(cogs_amount), 0)::numeric(14, 2) from sales_rows
    union all
    select 30, 'Gross profit', 'subtotal', coalesce(sum(net_sales), 0)::numeric(14, 2) - coalesce(sum(cogs_amount), 0)::numeric(14, 2) from sales_rows
    union all
    select 40, 'Operating expenses', 'expense', -coalesce(sum(total_amount - tax_amount), 0)::numeric(14, 2) from expense_rows
    union all
    select 50, 'Net profit', 'net', coalesce((select sum(net_sales - cogs_amount) from sales_rows), 0)::numeric(14, 2) - coalesce((select sum(total_amount - tax_amount) from expense_rows), 0)::numeric(14, 2)
  ),
  vat_report as (
    select
      coalesce((select sum(tax_total) from sales_rows), 0)::numeric(14, 2) as output_vat,
      coalesce((select sum(tax_amount) from supplier_invoice_rows), 0)::numeric(14, 2) as purchase_input_vat,
      coalesce((select sum(tax_amount) from expense_rows), 0)::numeric(14, 2) as expense_input_vat
  ),
  trial_balance as (
    select
      aa.id as account_id,
      aa.account_code,
      aa.name as account_name,
      aa.account_type,
      aa.normal_balance,
      aa.sort_order,
      case aa.account_code
        when '1000' then coalesce((select sum(case when direction = 'inflow' then amount else -amount end) from cash_ledger), 0)
        when '1100' then coalesce((select sum(receivable_balance) from receivable_rows), 0)
        when '1200' then coalesce((select sum(amount) from inventory_value), 0)
        when '1300' then coalesce((select purchase_input_vat + expense_input_vat from vat_report), 0)
        when '2000' then -coalesce((select sum(balance_amount) from payable_rows), 0)
        when '2100' then -coalesce((select output_vat from vat_report), 0)
        when '2200' then -coalesce((select sum(store_credit_balance) from receivable_rows), 0)
        when '4000' then -coalesce((select sum(net_sales) from sales_rows), 0)
        when '5000' then coalesce((select sum(cogs_amount) from sales_rows), 0)
        when '6000' then coalesce((select sum(total_amount - tax_amount) from expense_rows), 0)
        else 0
      end
      + coalesce(manual_stats.debit_total - manual_stats.credit_total, 0)::numeric(14, 2) as balance
    from public.accounting_accounts aa
    left join lateral (
      select
        coalesce(sum(mjl.debit), 0)::numeric(14, 2) as debit_total,
        coalesce(sum(mjl.credit), 0)::numeric(14, 2) as credit_total
      from manual_journal_line_rows mjl
      join manual_journal_rows mjr on mjr.id = mjl.journal_entry_id
      where mjl.account_id = aa.id
        and mjr.status = 'posted'
    ) manual_stats on true
    where aa.is_active = true
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
    'accounts', coalesce((select jsonb_agg(to_jsonb(aa) order by sort_order, account_code) from public.accounting_accounts aa where aa.is_active = true), '[]'::jsonb),
    'sales_journal', coalesce((select jsonb_agg(to_jsonb(sales_rows) order by business_date desc, created_at desc) from sales_rows), '[]'::jsonb),
    'cash_ledger', coalesce((select jsonb_agg(to_jsonb(cash_ledger) order by entry_date desc, created_at desc) from cash_ledger), '[]'::jsonb),
    'receivables', coalesce((select jsonb_agg(to_jsonb(receivable_rows) order by receivable_balance desc, full_name) from receivable_rows), '[]'::jsonb),
    'payables', coalesce((select jsonb_agg(to_jsonb(payable_rows) order by due_date nulls last, balance_amount desc) from payable_rows), '[]'::jsonb),
    'profit_loss', coalesce((select jsonb_agg(to_jsonb(profit_loss_lines) order by sort_order) from profit_loss_lines), '[]'::jsonb),
    'vat_report', coalesce((
      select jsonb_build_object(
        'output_vat', output_vat,
        'purchase_input_vat', purchase_input_vat,
        'expense_input_vat', expense_input_vat,
        'vat_payable', output_vat - purchase_input_vat - expense_input_vat
      )
      from vat_report
    ), '{}'::jsonb),
    'daily_summary', coalesce((select jsonb_agg(to_jsonb(daily_summary) order by business_date) from daily_summary), '[]'::jsonb),
    'branch_summary', coalesce((select jsonb_agg(to_jsonb(branch_summary) order by net_profit desc, branch_name) from branch_summary), '[]'::jsonb),
    'trial_balance', coalesce((select jsonb_agg(to_jsonb(trial_balance) order by sort_order, account_code) from trial_balance), '[]'::jsonb),
    'manual_journals', coalesce((select jsonb_agg(to_jsonb(manual_journal_rows) order by journal_date desc, created_at desc) from manual_journal_rows), '[]'::jsonb),
    'manual_journal_lines', coalesce((select jsonb_agg(to_jsonb(manual_journal_line_rows) order by journal_date desc, journal_number, account_code) from manual_journal_line_rows), '[]'::jsonb),
    'summary', jsonb_build_object(
      'sales_revenue', coalesce((select sum(net_sales) from sales_rows), 0),
      'sales_total', coalesce((select sum(total) from sales_rows), 0),
      'cogs', coalesce((select sum(cogs_amount) from sales_rows), 0),
      'gross_profit', coalesce((select sum(net_sales - cogs_amount) from sales_rows), 0),
      'operating_expenses', coalesce((select sum(total_amount - tax_amount) from expense_rows), 0),
      'net_profit', coalesce((select sum(net_sales - cogs_amount) from sales_rows), 0) - coalesce((select sum(total_amount - tax_amount) from expense_rows), 0),
      'cash_in', coalesce((select sum(amount) from cash_ledger where direction = 'inflow'), 0),
      'cash_out', coalesce((select sum(amount) from cash_ledger where direction = 'outflow'), 0),
      'cash_net', coalesce((select sum(case when direction = 'inflow' then amount else -amount end) from cash_ledger), 0),
      'accounts_receivable', coalesce((select sum(receivable_balance) from receivable_rows), 0),
      'inventory_value', coalesce((select sum(amount) from inventory_value), 0),
      'store_credit_liability', coalesce((select sum(store_credit_balance) from receivable_rows), 0),
      'accounts_payable', coalesce((select sum(balance_amount) from payable_rows), 0),
      'output_vat', coalesce((select output_vat from vat_report), 0),
      'input_vat', coalesce((select purchase_input_vat + expense_input_vat from vat_report), 0),
      'vat_payable', coalesce((select output_vat - purchase_input_vat - expense_input_vat from vat_report), 0),
      'manual_journal_count', coalesce((select count(*) from manual_journal_rows), 0)
    ),
    'can_manage_accounting', public.accounting_user_can_manage(v_permission_branch),
    'can_close_accounting', public.accounting_user_can_close(v_permission_branch),
    'generated_at', now()
  )
  into v_result;

  return v_result;
end;
$$;

create or replace function public.accounting_journal_post(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor public.user_profiles;
  v_branch_id uuid := nullif(p_payload->>'branch_id', '')::uuid;
  v_journal_id uuid;
  v_journal_number text;
  v_description text := trim(coalesce(p_payload->>'description', ''));
  v_journal_date date := coalesce(nullif(p_payload->>'journal_date', '')::date, current_date);
  v_lines jsonb := coalesce(p_payload->'lines', '[]'::jsonb);
  v_line jsonb;
  v_account_id uuid;
  v_debit numeric(14, 2);
  v_credit numeric(14, 2);
  v_debit_total numeric(14, 2) := 0;
  v_credit_total numeric(14, 2) := 0;
  v_line_count integer := 0;
begin
  v_actor := public.ensure_active_user();
  v_branch_id := coalesce(v_branch_id, v_actor.branch_id);

  if v_branch_id is null then
    raise exception 'Branch is required for manual journal entries' using errcode = '23502';
  end if;

  if public.accounting_user_can_manage(v_branch_id) = false then
    raise exception 'You cannot post accounting journals for this branch' using errcode = '42501';
  end if;

  if v_description = '' then
    raise exception 'Journal description is required' using errcode = '23502';
  end if;

  if jsonb_typeof(v_lines) <> 'array' or jsonb_array_length(v_lines) < 2 then
    raise exception 'At least two journal lines are required' using errcode = '23502';
  end if;

  for v_line in select * from jsonb_array_elements(v_lines)
  loop
    v_account_id := nullif(v_line->>'account_id', '')::uuid;
    v_debit := coalesce(nullif(v_line->>'debit', '')::numeric, 0);
    v_credit := coalesce(nullif(v_line->>'credit', '')::numeric, 0);

    if v_account_id is null or not exists (select 1 from public.accounting_accounts where id = v_account_id and is_active = true) then
      raise exception 'Each journal line must use an active account' using errcode = '23502';
    end if;

    if v_debit < 0 or v_credit < 0 or (v_debit = 0 and v_credit = 0) or (v_debit > 0 and v_credit > 0) then
      raise exception 'Each journal line must have either a debit or a credit amount' using errcode = '23514';
    end if;

    v_debit_total := v_debit_total + v_debit;
    v_credit_total := v_credit_total + v_credit;
    v_line_count := v_line_count + 1;
  end loop;

  if abs(v_debit_total - v_credit_total) > 0.01 then
    raise exception 'Journal is not balanced. Debits and credits must match' using errcode = '23514';
  end if;

  v_journal_number := 'JE-' || to_char(now(), 'YYYYMMDD-HH24MISS-') || upper(left(replace(gen_random_uuid()::text, '-', ''), 5));

  insert into public.accounting_journal_entries (
    branch_id,
    journal_number,
    journal_date,
    description,
    source_type,
    posted_by
  )
  values (
    v_branch_id,
    v_journal_number,
    v_journal_date,
    v_description,
    coalesce(nullif(p_payload->>'source_type', ''), 'manual'),
    v_actor.id
  )
  returning id into v_journal_id;

  for v_line in select * from jsonb_array_elements(v_lines)
  loop
    insert into public.accounting_journal_lines (
      journal_entry_id,
      account_id,
      description,
      debit,
      credit
    )
    values (
      v_journal_id,
      (v_line->>'account_id')::uuid,
      nullif(trim(coalesce(v_line->>'description', '')), ''),
      coalesce(nullif(v_line->>'debit', '')::numeric, 0),
      coalesce(nullif(v_line->>'credit', '')::numeric, 0)
    );
  end loop;

  perform public.log_activity(
    'accounting.journal_posted',
    'accounting_journal_entry',
    v_journal_id::text,
    jsonb_build_object('journal_number', v_journal_number, 'debit_total', v_debit_total, 'credit_total', v_credit_total, 'line_count', v_line_count),
    v_actor.id
  );

  return public.accounting_management_get(current_date - 29, current_date, v_branch_id, null);
end;
$$;

create or replace function public.accounting_journal_void(p_journal_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor public.user_profiles;
  v_journal public.accounting_journal_entries;
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
begin
  v_actor := public.ensure_active_user();

  select *
  into v_journal
  from public.accounting_journal_entries
  where id = p_journal_id
  for update;

  if v_journal.id is null then
    raise exception 'Journal entry not found' using errcode = '02000';
  end if;

  if public.accounting_user_can_close(v_journal.branch_id) = false then
    raise exception 'You cannot void accounting journals for this branch' using errcode = '42501';
  end if;

  if v_journal.status <> 'posted' then
    raise exception 'Only posted journals can be voided' using errcode = '23514';
  end if;

  if v_reason is null then
    raise exception 'Void reason is required' using errcode = '23502';
  end if;

  update public.accounting_journal_entries
  set status = 'voided',
      voided_by = v_actor.id,
      voided_at = now(),
      void_reason = v_reason
  where id = p_journal_id;

  perform public.log_activity(
    'accounting.journal_voided',
    'accounting_journal_entry',
    p_journal_id::text,
    jsonb_build_object('journal_number', v_journal.journal_number, 'reason', v_reason),
    v_actor.id
  );

  return public.accounting_management_get(current_date - 29, current_date, v_journal.branch_id, null);
end;
$$;

revoke all on function public.accounting_effective_permissions(uuid, text) from public;
revoke all on function public.accounting_visible_branch_ids(public.user_profiles) from public;
revoke all on function public.accounting_user_can_view(uuid) from public;
revoke all on function public.accounting_user_can_manage(uuid) from public;
revoke all on function public.accounting_user_can_close(uuid) from public;
revoke all on function public.accounting_management_get(date, date, uuid, text) from public;
revoke all on function public.accounting_journal_post(jsonb) from public;
revoke all on function public.accounting_journal_void(uuid, text) from public;

grant execute on function public.accounting_management_get(date, date, uuid, text) to authenticated;
grant execute on function public.accounting_journal_post(jsonb) to authenticated;
grant execute on function public.accounting_journal_void(uuid, text) to authenticated;

notify pgrst, 'reload schema';
