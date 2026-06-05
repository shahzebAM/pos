-- MODULE 15: SUPPLIER MANAGEMENT
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
--
-- Scope:
-- - Supplier profile management
-- - Payables dashboard
-- - Purchase history by supplier
-- - Supplier payment posting and voiding

create extension if not exists pgcrypto;

alter table public.suppliers
  add column if not exists account_number text,
  add column if not exists website text,
  add column if not exists default_payment_method text not null default 'bank_transfer',
  add column if not exists withholding_tax_rate numeric(5, 2) not null default 0 check (withholding_tax_rate >= 0 and withholding_tax_rate <= 100),
  add column if not exists lead_time_days integer not null default 0 check (lead_time_days >= 0 and lead_time_days <= 365),
  add column if not exists rating integer not null default 3 check (rating >= 1 and rating <= 5),
  add column if not exists status text not null default 'active' check (status in ('active', 'on_hold', 'inactive'));

alter table public.suppliers
  drop constraint if exists suppliers_default_payment_method_check;

alter table public.suppliers
  add constraint suppliers_default_payment_method_check
  check (default_payment_method in ('cash', 'check', 'bank_transfer', 'card', 'gcash', 'maya', 'other'));

update public.suppliers
set status = case when is_active then 'active' else 'inactive' end
where status is null;

create table if not exists public.supplier_payments (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches(id) on delete restrict,
  supplier_id uuid not null references public.suppliers(id) on delete restrict,
  supplier_invoice_id uuid references public.supplier_invoices(id) on delete set null,
  payment_number text not null unique,
  payment_date date not null default current_date,
  payment_method text not null default 'bank_transfer',
  amount numeric(14, 2) not null check (amount > 0),
  reference_number text,
  notes text,
  created_by uuid references public.user_profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  status text not null default 'posted',
  voided_by uuid references public.user_profiles(id) on delete set null,
  voided_at timestamptz,
  void_reason text,
  constraint supplier_payments_method_check check (payment_method in ('cash', 'check', 'bank_transfer', 'card', 'gcash', 'maya', 'other')),
  constraint supplier_payments_status_check check (status in ('posted', 'voided'))
);

create index if not exists idx_supplier_payments_branch_date on public.supplier_payments(branch_id, payment_date desc, created_at desc);
create index if not exists idx_supplier_payments_supplier_date on public.supplier_payments(supplier_id, payment_date desc, created_at desc);
create index if not exists idx_supplier_payments_invoice on public.supplier_payments(supplier_invoice_id);

alter table public.supplier_payments enable row level security;

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
      'activity.view',
      'reports.view'
    ]::text[]
    else array[
      'dashboard.view',
      'products.view',
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
    jsonb_build_object('key', 'activity.view', 'label', 'View activity logs'),
    jsonb_build_object('key', 'pos.sell', 'label', 'Use POS checkout'),
    jsonb_build_object('key', 'pos.discount', 'label', 'Apply discounts'),
    jsonb_build_object('key', 'pos.void', 'label', 'Void transactions'),
    jsonb_build_object('key', 'reports.view', 'label', 'View reports')
  )
$$;

create or replace function public.supplier_effective_permissions(p_user_id uuid, p_role text)
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

create or replace function public.supplier_visible_branch_ids(p_profile public.user_profiles)
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

create or replace function public.supplier_user_can_view(p_branch_id uuid)
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
  v_permissions := public.supplier_effective_permissions(v_profile.id, v_profile.role);

  if not coalesce('suppliers.view' = any(v_permissions), false) and v_profile.role <> 'admin' then
    return false;
  end if;

  if v_profile.role in ('admin', 'auditor') then
    return true;
  end if;

  return p_branch_id is not null and v_profile.branch_id = p_branch_id;
end;
$$;

create or replace function public.supplier_user_can_manage(p_branch_id uuid)
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
  v_permissions := public.supplier_effective_permissions(v_profile.id, v_profile.role);

  if v_profile.role = 'admin' then
    return true;
  end if;

  return v_profile.role = 'manager'
    and (p_branch_id is null or v_profile.branch_id = p_branch_id)
    and coalesce('suppliers.manage' = any(v_permissions), false);
end;
$$;

create or replace function public.supplier_user_can_pay(p_branch_id uuid)
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
  v_permissions := public.supplier_effective_permissions(v_profile.id, v_profile.role);

  if v_profile.role = 'admin' then
    return true;
  end if;

  return v_profile.role = 'manager'
    and (p_branch_id is null or v_profile.branch_id = p_branch_id)
    and coalesce('suppliers.pay' = any(v_permissions), false);
end;
$$;

drop policy if exists supplier_payments_select_by_role on public.supplier_payments;
create policy supplier_payments_select_by_role
on public.supplier_payments
for select
to authenticated
using (public.supplier_user_can_view(branch_id));

create or replace function public.supplier_management_get(
  p_from date default current_date - 89,
  p_to date default current_date,
  p_branch_id uuid default null,
  p_supplier_id uuid default null,
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
  v_supplier_filter uuid := p_supplier_id;
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

  if public.supplier_user_can_view(v_permission_branch) = false then
    raise exception 'You cannot view supplier management' using errcode = '42501';
  end if;

  v_branch_ids := public.supplier_visible_branch_ids(v_profile);

  with visible_branches as (
    select b.*
    from public.branches b
    where b.is_active = true
      and b.id = any(v_branch_ids)
      and (v_branch_filter is null or b.id = v_branch_filter)
  ),
  supplier_rows as (
    select
      s.*,
      coalesce(po_stats.open_orders, 0)::integer as open_orders,
      coalesce(po_stats.purchase_orders, 0)::integer as purchase_orders,
      coalesce(receipt_stats.receipt_count, 0)::integer as receipt_count,
      coalesce(receipt_stats.received_value, 0)::numeric(14, 2) as received_value,
      receipt_stats.last_purchase_date,
      coalesce(invoice_stats.invoice_count, 0)::integer as invoice_count,
      coalesce(invoice_stats.pending_invoice_count, 0)::integer as pending_invoice_count,
      coalesce(invoice_stats.overdue_invoice_count, 0)::integer as overdue_invoice_count,
      coalesce(invoice_stats.payable_amount, 0)::numeric(14, 2) as payable_amount,
      coalesce(invoice_stats.overdue_amount, 0)::numeric(14, 2) as overdue_amount,
      coalesce(payment_stats.paid_amount, 0)::numeric(14, 2) as paid_amount,
      payment_stats.last_payment_date
    from public.suppliers s
    left join lateral (
      select
        count(*) filter (where po.order_date >= v_from and po.order_date <= v_to)::integer as purchase_orders,
        count(*) filter (where po.status in ('draft', 'submitted', 'approved', 'partially_received'))::integer as open_orders
      from public.purchase_orders po
      join visible_branches vb on vb.id = po.branch_id
      where po.supplier_id = s.id
    ) po_stats on true
    left join lateral (
      select
        count(*) filter (where pr.receipt_date >= v_from and pr.receipt_date <= v_to)::integer as receipt_count,
        coalesce(sum(pr.total_cost) filter (where pr.receipt_date >= v_from and pr.receipt_date <= v_to), 0)::numeric(14, 2) as received_value,
        max(pr.receipt_date) as last_purchase_date
      from public.purchase_receipts pr
      join visible_branches vb on vb.id = pr.branch_id
      where pr.supplier_id = s.id
        and pr.status = 'posted'
    ) receipt_stats on true
    left join lateral (
      select
        count(*) filter (where si.invoice_date >= v_from and si.invoice_date <= v_to)::integer as invoice_count,
        count(*) filter (where si.status in ('pending', 'partial'))::integer as pending_invoice_count,
        count(*) filter (where si.status in ('pending', 'partial') and si.due_date < current_date)::integer as overdue_invoice_count,
        coalesce(sum(si.amount - si.paid_amount) filter (where si.status in ('pending', 'partial')), 0)::numeric(14, 2) as payable_amount,
        coalesce(sum(si.amount - si.paid_amount) filter (where si.status in ('pending', 'partial') and si.due_date < current_date), 0)::numeric(14, 2) as overdue_amount
      from public.supplier_invoices si
      join visible_branches vb on vb.id = si.branch_id
      where si.supplier_id = s.id
    ) invoice_stats on true
    left join lateral (
      select
        coalesce(sum(sp.amount) filter (where sp.status = 'posted' and sp.payment_date >= v_from and sp.payment_date <= v_to), 0)::numeric(14, 2) as paid_amount,
        max(sp.payment_date) filter (where sp.status = 'posted') as last_payment_date
      from public.supplier_payments sp
      join visible_branches vb on vb.id = sp.branch_id
      where sp.supplier_id = s.id
    ) payment_stats on true
    where (v_supplier_filter is null or s.id = v_supplier_filter)
      and (
        v_search = ''
        or lower(s.supplier_code) like '%' || v_search || '%'
        or lower(s.name) like '%' || v_search || '%'
        or lower(coalesce(s.contact_person, '')) like '%' || v_search || '%'
        or lower(coalesce(s.phone, '')) like '%' || v_search || '%'
        or lower(coalesce(s.email, '')) like '%' || v_search || '%'
        or lower(coalesce(s.tin, '')) like '%' || v_search || '%'
      )
  ),
  invoice_rows as (
    select
      si.*,
      b.branch_code,
      b.name as branch_name,
      s.supplier_code,
      s.name as supplier_name,
      po.po_number,
      pr.receipt_number,
      greatest(si.amount - si.paid_amount, 0)::numeric(14, 2) as balance_amount,
      case
        when si.status in ('pending', 'partial') and si.due_date < current_date then current_date - si.due_date
        else 0
      end::integer as days_overdue
    from public.supplier_invoices si
    join visible_branches b on b.id = si.branch_id
    join public.suppliers s on s.id = si.supplier_id
    left join public.purchase_orders po on po.id = si.purchase_order_id
    left join public.purchase_receipts pr on pr.id = si.receipt_id
    where (v_supplier_filter is null or si.supplier_id = v_supplier_filter)
      and (
        si.status in ('pending', 'partial')
        or si.invoice_date between v_from and v_to
      )
      and (
        v_search = ''
        or lower(si.invoice_number) like '%' || v_search || '%'
        or lower(s.name) like '%' || v_search || '%'
        or lower(coalesce(po.po_number, '')) like '%' || v_search || '%'
        or lower(coalesce(pr.receipt_number, '')) like '%' || v_search || '%'
      )
  ),
  payment_rows as (
    select
      sp.*,
      b.branch_code,
      b.name as branch_name,
      s.supplier_code,
      s.name as supplier_name,
      si.invoice_number,
      creator.full_name as created_by_name,
      voider.full_name as voided_by_name
    from public.supplier_payments sp
    join visible_branches b on b.id = sp.branch_id
    join public.suppliers s on s.id = sp.supplier_id
    left join public.supplier_invoices si on si.id = sp.supplier_invoice_id
    left join public.user_profiles creator on creator.id = sp.created_by
    left join public.user_profiles voider on voider.id = sp.voided_by
    where sp.payment_date >= v_from
      and sp.payment_date <= v_to
      and (v_supplier_filter is null or sp.supplier_id = v_supplier_filter)
      and (
        v_search = ''
        or lower(sp.payment_number) like '%' || v_search || '%'
        or lower(s.name) like '%' || v_search || '%'
        or lower(coalesce(si.invoice_number, '')) like '%' || v_search || '%'
        or lower(coalesce(sp.reference_number, '')) like '%' || v_search || '%'
      )
  ),
  receipt_rows as (
    select
      pr.*,
      b.branch_code,
      b.name as branch_name,
      s.supplier_code,
      s.name as supplier_name,
      po.po_number,
      coalesce(item_stats.item_count, 0)::integer as item_count,
      coalesce(item_stats.received_quantity, 0)::integer as received_quantity
    from public.purchase_receipts pr
    join visible_branches b on b.id = pr.branch_id
    join public.suppliers s on s.id = pr.supplier_id
    left join public.purchase_orders po on po.id = pr.purchase_order_id
    left join lateral (
      select
        count(*)::integer as item_count,
        coalesce(sum(pri.quantity_received), 0)::integer as received_quantity
      from public.purchase_receipt_items pri
      where pri.receipt_id = pr.id
    ) item_stats on true
    where pr.status = 'posted'
      and pr.receipt_date >= v_from
      and pr.receipt_date <= v_to
      and (v_supplier_filter is null or pr.supplier_id = v_supplier_filter)
      and (
        v_search = ''
        or lower(pr.receipt_number) like '%' || v_search || '%'
        or lower(coalesce(pr.supplier_invoice_number, '')) like '%' || v_search || '%'
        or lower(s.name) like '%' || v_search || '%'
        or lower(coalesce(po.po_number, '')) like '%' || v_search || '%'
      )
  ),
  purchase_order_rows as (
    select
      po.*,
      b.branch_code,
      b.name as branch_name,
      s.supplier_code,
      s.name as supplier_name,
      coalesce(item_stats.item_count, 0)::integer as item_count,
      coalesce(item_stats.ordered_quantity, 0)::integer as ordered_quantity,
      coalesce(item_stats.received_quantity, 0)::integer as received_quantity
    from public.purchase_orders po
    join visible_branches b on b.id = po.branch_id
    join public.suppliers s on s.id = po.supplier_id
    left join lateral (
      select
        count(*)::integer as item_count,
        coalesce(sum(poi.quantity_ordered), 0)::integer as ordered_quantity,
        coalesce(sum(poi.quantity_received), 0)::integer as received_quantity
      from public.purchase_order_items poi
      where poi.purchase_order_id = po.id
    ) item_stats on true
    where po.order_date >= v_from
      and po.order_date <= v_to
      and (v_supplier_filter is null or po.supplier_id = v_supplier_filter)
      and (
        v_search = ''
        or lower(po.po_number) like '%' || v_search || '%'
        or lower(s.name) like '%' || v_search || '%'
        or lower(coalesce(po.notes, '')) like '%' || v_search || '%'
      )
  ),
  daily_payments as (
    select
      d.day::date as business_date,
      to_char(d.day::date, 'Mon DD') as label,
      coalesce(count(pr.id) filter (where pr.status = 'posted'), 0)::integer as payments,
      coalesce(sum(pr.amount) filter (where pr.status = 'posted'), 0)::numeric(14, 2) as paid_amount
    from generate_series(v_from, v_to, interval '1 day') d(day)
    left join payment_rows pr on pr.payment_date = d.day::date
    group by d.day
  ),
  branch_summary as (
    select
      vb.id as branch_id,
      vb.branch_code,
      vb.name as branch_name,
      coalesce(invoice_stats.payable_amount, 0)::numeric(14, 2) as payable_amount,
      coalesce(invoice_stats.overdue_amount, 0)::numeric(14, 2) as overdue_amount,
      coalesce(payment_stats.paid_amount, 0)::numeric(14, 2) as paid_amount,
      coalesce(receipt_stats.received_value, 0)::numeric(14, 2) as received_value
    from visible_branches vb
    left join lateral (
      select
        coalesce(sum(ir.amount - ir.paid_amount) filter (where ir.status in ('pending', 'partial')), 0)::numeric(14, 2) as payable_amount,
        coalesce(sum(ir.amount - ir.paid_amount) filter (where ir.status in ('pending', 'partial') and ir.due_date < current_date), 0)::numeric(14, 2) as overdue_amount
      from invoice_rows ir
      where ir.branch_id = vb.id
    ) invoice_stats on true
    left join lateral (
      select coalesce(sum(pr.amount) filter (where pr.status = 'posted'), 0)::numeric(14, 2) as paid_amount
      from payment_rows pr
      where pr.branch_id = vb.id
    ) payment_stats on true
    left join lateral (
      select coalesce(sum(rr.total_cost), 0)::numeric(14, 2) as received_value
      from receipt_rows rr
      where rr.branch_id = vb.id
    ) receipt_stats on true
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
    'suppliers', coalesce((select jsonb_agg(to_jsonb(supplier_rows) order by payable_amount desc, name) from supplier_rows), '[]'::jsonb),
    'supplier_invoices', coalesce((select jsonb_agg(to_jsonb(invoice_rows) order by status, due_date nulls last, created_at desc) from invoice_rows), '[]'::jsonb),
    'supplier_payments', coalesce((select jsonb_agg(to_jsonb(payment_rows) order by created_at desc) from (select * from payment_rows order by created_at desc limit 150) payment_rows), '[]'::jsonb),
    'purchase_history', coalesce((select jsonb_agg(to_jsonb(receipt_rows) order by receipt_date desc, created_at desc) from receipt_rows), '[]'::jsonb),
    'purchase_orders', coalesce((select jsonb_agg(to_jsonb(purchase_order_rows) order by order_date desc, created_at desc) from purchase_order_rows), '[]'::jsonb),
    'daily_payments', coalesce((select jsonb_agg(to_jsonb(daily_payments) order by business_date) from daily_payments), '[]'::jsonb),
    'branch_summary', coalesce((select jsonb_agg(to_jsonb(branch_summary) order by payable_amount desc, branch_name) from branch_summary), '[]'::jsonb),
    'top_suppliers', coalesce((
      select jsonb_agg(to_jsonb(top_rows) order by top_rows.received_value desc, top_rows.payable_amount desc)
      from (
        select *
        from supplier_rows
        where received_value > 0 or payable_amount > 0
        order by received_value desc, payable_amount desc, name
        limit 8
      ) top_rows
    ), '[]'::jsonb),
    'summary', jsonb_build_object(
      'supplier_count', coalesce((select count(*) from supplier_rows), 0),
      'active_suppliers', coalesce((select count(*) from supplier_rows where status = 'active' and is_active = true), 0),
      'on_hold_suppliers', coalesce((select count(*) from supplier_rows where status = 'on_hold'), 0),
      'payable_amount', coalesce((select sum(payable_amount) from supplier_rows), 0),
      'overdue_amount', coalesce((select sum(overdue_amount) from supplier_rows), 0),
      'overdue_invoices', coalesce((select count(*) from invoice_rows where status in ('pending', 'partial') and due_date < current_date), 0),
      'purchase_value', coalesce((select sum(total_cost) from receipt_rows), 0),
      'paid_amount', coalesce((select sum(amount) from payment_rows where status = 'posted'), 0),
      'payment_count', coalesce((select count(*) from payment_rows where status = 'posted'), 0),
      'open_purchase_orders', coalesce((select count(*) from purchase_order_rows where status in ('draft', 'submitted', 'approved', 'partially_received')), 0)
    ),
    'can_manage_suppliers', public.supplier_user_can_manage(v_permission_branch),
    'can_pay_suppliers', public.supplier_user_can_pay(v_permission_branch),
    'generated_at', now()
  )
  into v_result;

  return v_result;
end;
$$;

create or replace function public.supplier_profile_save(p_supplier_id uuid, p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor public.user_profiles;
  v_supplier_id uuid;
  v_branch_context uuid;
  v_name text := trim(coalesce(p_payload->>'name', ''));
  v_code text := upper(trim(coalesce(p_payload->>'supplier_code', '')));
  v_status text := lower(trim(coalesce(nullif(p_payload->>'status', ''), 'active')));
  v_method text := lower(trim(coalesce(nullif(p_payload->>'default_payment_method', ''), 'bank_transfer')));
  v_has_is_active boolean := p_payload ? 'is_active' and nullif(p_payload->>'is_active', '') is not null;
  v_is_active boolean := true;
begin
  v_actor := public.ensure_active_user();
  v_branch_context := coalesce(nullif(p_payload->>'branch_id', '')::uuid, v_actor.branch_id);

  if public.supplier_user_can_manage(v_branch_context) = false then
    raise exception 'You cannot save suppliers' using errcode = '42501';
  end if;

  if v_name = '' then
    raise exception 'Supplier name is required' using errcode = '23502';
  end if;

  if v_code = '' then
    v_code := upper(left(regexp_replace(v_name, '[^A-Za-z0-9]+', '-', 'g'), 24));
  end if;

  if v_code = '' then
    v_code := 'SUP-' || upper(left(replace(gen_random_uuid()::text, '-', ''), 8));
  end if;

  if p_supplier_id is null and exists (select 1 from public.suppliers where supplier_code = v_code) then
    v_code := left(v_code, 20) || '-' || upper(left(replace(gen_random_uuid()::text, '-', ''), 4));
  end if;

  if v_status not in ('active', 'on_hold', 'inactive') then
    raise exception 'Invalid supplier status' using errcode = '22023';
  end if;

  if v_method not in ('cash', 'check', 'bank_transfer', 'card', 'gcash', 'maya', 'other') then
    raise exception 'Invalid default payment method' using errcode = '22023';
  end if;

  if v_has_is_active then
    v_is_active := (p_payload->>'is_active')::boolean;
  else
    v_is_active := v_status <> 'inactive';
  end if;

  if p_supplier_id is null then
    insert into public.suppliers (
      supplier_code,
      name,
      contact_person,
      phone,
      email,
      tin,
      address,
      account_number,
      website,
      payment_terms_days,
      credit_limit,
      default_payment_method,
      withholding_tax_rate,
      lead_time_days,
      rating,
      status,
      is_active,
      notes
    )
    values (
      v_code,
      v_name,
      nullif(trim(coalesce(p_payload->>'contact_person', '')), ''),
      nullif(trim(coalesce(p_payload->>'phone', '')), ''),
      nullif(trim(coalesce(p_payload->>'email', '')), ''),
      nullif(trim(coalesce(p_payload->>'tin', '')), ''),
      nullif(trim(coalesce(p_payload->>'address', '')), ''),
      nullif(trim(coalesce(p_payload->>'account_number', '')), ''),
      nullif(trim(coalesce(p_payload->>'website', '')), ''),
      coalesce(nullif(p_payload->>'payment_terms_days', '')::integer, 30),
      coalesce(nullif(p_payload->>'credit_limit', '')::numeric, 0),
      v_method,
      coalesce(nullif(p_payload->>'withholding_tax_rate', '')::numeric, 0),
      coalesce(nullif(p_payload->>'lead_time_days', '')::integer, 0),
      coalesce(nullif(p_payload->>'rating', '')::integer, 3),
      v_status,
      v_is_active,
      nullif(trim(coalesce(p_payload->>'notes', '')), '')
    )
    returning id into v_supplier_id;
  else
    update public.suppliers
    set supplier_code = v_code,
        name = v_name,
        contact_person = nullif(trim(coalesce(p_payload->>'contact_person', contact_person, '')), ''),
        phone = nullif(trim(coalesce(p_payload->>'phone', phone, '')), ''),
        email = nullif(trim(coalesce(p_payload->>'email', email, '')), ''),
        tin = nullif(trim(coalesce(p_payload->>'tin', tin, '')), ''),
        address = nullif(trim(coalesce(p_payload->>'address', address, '')), ''),
        account_number = nullif(trim(coalesce(p_payload->>'account_number', account_number, '')), ''),
        website = nullif(trim(coalesce(p_payload->>'website', website, '')), ''),
        payment_terms_days = coalesce(nullif(p_payload->>'payment_terms_days', '')::integer, payment_terms_days),
        credit_limit = coalesce(nullif(p_payload->>'credit_limit', '')::numeric, credit_limit),
        default_payment_method = v_method,
        withholding_tax_rate = coalesce(nullif(p_payload->>'withholding_tax_rate', '')::numeric, withholding_tax_rate),
        lead_time_days = coalesce(nullif(p_payload->>'lead_time_days', '')::integer, lead_time_days),
        rating = coalesce(nullif(p_payload->>'rating', '')::integer, rating),
        status = case
          when p_payload ? 'status' then v_status
          when v_has_is_active then case when v_is_active then 'active' else 'inactive' end
          else status
        end,
        is_active = case
          when v_has_is_active then v_is_active
          when p_payload ? 'status' then v_status <> 'inactive'
          else is_active
        end,
        notes = nullif(trim(coalesce(p_payload->>'notes', notes, '')), '')
    where id = p_supplier_id
    returning id into v_supplier_id;

    if v_supplier_id is null then
      raise exception 'Supplier not found' using errcode = '02000';
    end if;
  end if;

  perform public.log_activity('supplier.profile_saved', 'supplier', v_supplier_id::text, jsonb_build_object('supplier_code', v_code, 'name', v_name), v_actor.id);

  return public.supplier_management_get(current_date - 89, current_date, v_branch_context, null, null);
end;
$$;

create or replace function public.supplier_payment_post(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor public.user_profiles;
  v_branch_id uuid := nullif(p_payload->>'branch_id', '')::uuid;
  v_supplier_id uuid := nullif(p_payload->>'supplier_id', '')::uuid;
  v_invoice_id uuid := nullif(p_payload->>'supplier_invoice_id', '')::uuid;
  v_invoice public.supplier_invoices;
  v_payment_id uuid;
  v_payment_number text;
  v_payment_date date := coalesce(nullif(p_payload->>'payment_date', '')::date, current_date);
  v_method text := lower(trim(coalesce(nullif(p_payload->>'payment_method', ''), 'bank_transfer')));
  v_amount numeric(14, 2) := coalesce(nullif(p_payload->>'amount', '')::numeric, 0);
  v_reference text := nullif(trim(coalesce(p_payload->>'reference_number', '')), '');
  v_notes text := nullif(trim(coalesce(p_payload->>'notes', '')), '');
  v_balance numeric(14, 2);
  v_new_paid numeric(14, 2);
begin
  v_actor := public.ensure_active_user();

  if v_method not in ('cash', 'check', 'bank_transfer', 'card', 'gcash', 'maya', 'other') then
    raise exception 'Invalid supplier payment method' using errcode = '22023';
  end if;

  if v_amount <= 0 then
    raise exception 'Supplier payment amount must be greater than zero' using errcode = '23514';
  end if;

  if v_invoice_id is not null then
    select *
    into v_invoice
    from public.supplier_invoices
    where id = v_invoice_id
    for update;

    if v_invoice.id is null then
      raise exception 'Supplier invoice not found' using errcode = '02000';
    end if;

    if v_invoice.status = 'voided' then
      raise exception 'Voided supplier invoices cannot be paid' using errcode = '23514';
    end if;

    if v_branch_id is not null and v_branch_id <> v_invoice.branch_id then
      raise exception 'Payment branch does not match supplier invoice branch' using errcode = '23514';
    end if;

    if v_supplier_id is not null and v_supplier_id <> v_invoice.supplier_id then
      raise exception 'Payment supplier does not match supplier invoice' using errcode = '23514';
    end if;

    v_branch_id := v_invoice.branch_id;
    v_supplier_id := v_invoice.supplier_id;
    v_balance := greatest(v_invoice.amount - v_invoice.paid_amount, 0);

    if v_amount > v_balance then
      raise exception 'Supplier payment exceeds invoice balance' using errcode = '23514';
    end if;
  end if;

  if v_branch_id is null then
    v_branch_id := v_actor.branch_id;
  end if;

  if v_branch_id is null or v_supplier_id is null then
    raise exception 'Branch and supplier are required for supplier payments' using errcode = '23502';
  end if;

  if public.supplier_user_can_pay(v_branch_id) = false then
    raise exception 'You cannot post supplier payments for this branch' using errcode = '42501';
  end if;

  if not exists (select 1 from public.branches where id = v_branch_id and is_active = true) then
    raise exception 'Branch not found or inactive' using errcode = '02000';
  end if;

  if not exists (select 1 from public.suppliers where id = v_supplier_id and is_active = true and status <> 'inactive') then
    raise exception 'Supplier not found or inactive' using errcode = '02000';
  end if;

  v_payment_number := 'SPAY-' || to_char(now(), 'YYYYMMDD-HH24MISS-') || upper(left(replace(gen_random_uuid()::text, '-', ''), 5));

  insert into public.supplier_payments (
    branch_id,
    supplier_id,
    supplier_invoice_id,
    payment_number,
    payment_date,
    payment_method,
    amount,
    reference_number,
    notes,
    created_by
  )
  values (
    v_branch_id,
    v_supplier_id,
    v_invoice_id,
    v_payment_number,
    v_payment_date,
    v_method,
    v_amount,
    v_reference,
    v_notes,
    v_actor.id
  )
  returning id into v_payment_id;

  if v_invoice_id is not null then
    select *
    into v_invoice
    from public.supplier_invoices
    where id = v_invoice_id
    for update;

    v_new_paid := least(v_invoice.amount, v_invoice.paid_amount + v_amount);

    update public.supplier_invoices
    set paid_amount = v_new_paid,
        status = case
          when v_new_paid >= amount then 'paid'
          when v_new_paid > 0 then 'partial'
          else 'pending'
        end,
        paid_at = case when v_new_paid >= amount then now() else paid_at end
    where id = v_invoice_id;
  end if;

  perform public.log_activity(
    'supplier.payment_posted',
    'supplier_payment',
    v_payment_id::text,
    jsonb_build_object('payment_number', v_payment_number, 'supplier_id', v_supplier_id, 'branch_id', v_branch_id, 'amount', v_amount),
    v_actor.id
  );

  return public.supplier_management_get(current_date - 89, current_date, v_branch_id, null, null);
end;
$$;

create or replace function public.supplier_payment_void(p_payment_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor public.user_profiles;
  v_payment public.supplier_payments;
  v_invoice public.supplier_invoices;
  v_reason text := trim(coalesce(p_reason, ''));
  v_new_paid numeric(14, 2);
begin
  v_actor := public.ensure_active_user();

  select *
  into v_payment
  from public.supplier_payments
  where id = p_payment_id
  for update;

  if v_payment.id is null then
    raise exception 'Supplier payment not found' using errcode = '02000';
  end if;

  if v_payment.status <> 'posted' then
    raise exception 'Only posted supplier payments can be voided' using errcode = '23514';
  end if;

  if v_reason = '' then
    raise exception 'Void reason is required' using errcode = '23502';
  end if;

  if public.supplier_user_can_pay(v_payment.branch_id) = false then
    raise exception 'You cannot void supplier payments for this branch' using errcode = '42501';
  end if;

  if v_payment.supplier_invoice_id is not null then
    select *
    into v_invoice
    from public.supplier_invoices
    where id = v_payment.supplier_invoice_id
    for update;

    if v_invoice.id is not null and v_invoice.status <> 'voided' then
      v_new_paid := greatest(v_invoice.paid_amount - v_payment.amount, 0);

      update public.supplier_invoices
      set paid_amount = v_new_paid,
          status = case
            when v_new_paid <= 0 then 'pending'
            when v_new_paid >= amount then 'paid'
            else 'partial'
          end,
          paid_at = case when v_new_paid >= amount then paid_at else null end
      where id = v_invoice.id;
    end if;
  end if;

  update public.supplier_payments
  set status = 'voided',
      voided_by = v_actor.id,
      voided_at = now(),
      void_reason = v_reason
  where id = p_payment_id;

  perform public.log_activity(
    'supplier.payment_voided',
    'supplier_payment',
    p_payment_id::text,
    jsonb_build_object('payment_number', v_payment.payment_number, 'reason', v_reason, 'amount', v_payment.amount),
    v_actor.id
  );

  return public.supplier_management_get(current_date - 89, current_date, v_payment.branch_id, null, null);
end;
$$;

revoke all on function public.supplier_effective_permissions(uuid, text) from public;
revoke all on function public.supplier_visible_branch_ids(public.user_profiles) from public;
revoke all on function public.supplier_user_can_view(uuid) from public;
revoke all on function public.supplier_user_can_manage(uuid) from public;
revoke all on function public.supplier_user_can_pay(uuid) from public;
revoke all on function public.supplier_management_get(date, date, uuid, uuid, text) from public;
revoke all on function public.supplier_profile_save(uuid, jsonb) from public;
revoke all on function public.supplier_payment_post(jsonb) from public;
revoke all on function public.supplier_payment_void(uuid, text) from public;

grant execute on function public.supplier_management_get(date, date, uuid, uuid, text) to authenticated;
grant execute on function public.supplier_profile_save(uuid, jsonb) to authenticated;
grant execute on function public.supplier_payment_post(jsonb) to authenticated;
grant execute on function public.supplier_payment_void(uuid, text) to authenticated;

notify pgrst, 'reload schema';
