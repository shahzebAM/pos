-- MODULE 14: PURCHASE MANAGEMENT
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
--
-- Scope:
-- - Purchase orders
-- - Receiving / Goods Received Notes
-- - Supplier invoice tracking
-- - Purchase returns
-- - Cost tracking
-- - Inventory posting from purchases

create extension if not exists pgcrypto;

create table if not exists public.suppliers (
  id uuid primary key default gen_random_uuid(),
  supplier_code text not null unique,
  name text not null,
  contact_person text,
  phone text,
  email text,
  tin text,
  address text,
  payment_terms_days integer not null default 30 check (payment_terms_days >= 0 and payment_terms_days <= 365),
  credit_limit numeric(14, 2) not null default 0 check (credit_limit >= 0),
  is_active boolean not null default true,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

drop trigger if exists set_suppliers_updated_at on public.suppliers;
create trigger set_suppliers_updated_at
before update on public.suppliers
for each row execute function public.set_updated_at();

create table if not exists public.purchase_orders (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches(id) on delete restrict,
  supplier_id uuid not null references public.suppliers(id) on delete restrict,
  po_number text not null unique,
  status text not null default 'draft',
  order_date date not null default current_date,
  expected_date date,
  subtotal numeric(14, 2) not null default 0 check (subtotal >= 0),
  tax_total numeric(14, 2) not null default 0 check (tax_total >= 0),
  total numeric(14, 2) not null default 0 check (total >= 0),
  notes text,
  requested_by uuid references public.user_profiles(id) on delete set null,
  approved_by uuid references public.user_profiles(id) on delete set null,
  approved_at timestamptz,
  cancelled_by uuid references public.user_profiles(id) on delete set null,
  cancelled_at timestamptz,
  cancel_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint purchase_orders_status_check check (
    status in ('draft', 'submitted', 'approved', 'partially_received', 'received', 'cancelled', 'closed')
  )
);

drop trigger if exists set_purchase_orders_updated_at on public.purchase_orders;
create trigger set_purchase_orders_updated_at
before update on public.purchase_orders
for each row execute function public.set_updated_at();

create table if not exists public.purchase_order_items (
  id uuid primary key default gen_random_uuid(),
  purchase_order_id uuid not null references public.purchase_orders(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict,
  product_variant_id uuid references public.product_variants(id) on delete set null,
  product_name text not null,
  sku text,
  barcode text,
  variant_name text,
  quantity_ordered integer not null check (quantity_ordered > 0),
  quantity_received integer not null default 0 check (quantity_received >= 0),
  unit_cost numeric(14, 2) not null default 0 check (unit_cost >= 0),
  tax_rate numeric(5, 2) not null default 0 check (tax_rate >= 0 and tax_rate <= 100),
  tax_amount numeric(14, 2) not null default 0 check (tax_amount >= 0),
  line_total numeric(14, 2) not null default 0 check (line_total >= 0),
  created_at timestamptz not null default now()
);

create table if not exists public.purchase_receipts (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches(id) on delete restrict,
  supplier_id uuid not null references public.suppliers(id) on delete restrict,
  purchase_order_id uuid references public.purchase_orders(id) on delete set null,
  receipt_number text not null unique,
  supplier_invoice_number text,
  receipt_date date not null default current_date,
  status text not null default 'posted',
  total_cost numeric(14, 2) not null default 0 check (total_cost >= 0),
  tax_total numeric(14, 2) not null default 0 check (tax_total >= 0),
  notes text,
  received_by uuid references public.user_profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint purchase_receipts_status_check check (status in ('posted', 'voided'))
);

create table if not exists public.purchase_receipt_items (
  id uuid primary key default gen_random_uuid(),
  receipt_id uuid not null references public.purchase_receipts(id) on delete cascade,
  purchase_order_item_id uuid references public.purchase_order_items(id) on delete set null,
  product_id uuid not null references public.products(id) on delete restrict,
  product_variant_id uuid references public.product_variants(id) on delete set null,
  inventory_batch_id uuid references public.inventory_batches(id) on delete set null,
  product_name text not null,
  sku text,
  barcode text,
  variant_name text,
  quantity_received integer not null check (quantity_received > 0),
  quantity_returned integer not null default 0 check (quantity_returned >= 0),
  unit_cost numeric(14, 2) not null default 0 check (unit_cost >= 0),
  tax_rate numeric(5, 2) not null default 0 check (tax_rate >= 0 and tax_rate <= 100),
  tax_amount numeric(14, 2) not null default 0 check (tax_amount >= 0),
  line_total numeric(14, 2) not null default 0 check (line_total >= 0),
  batch_number text,
  expiry_date date,
  created_at timestamptz not null default now()
);

create table if not exists public.supplier_invoices (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches(id) on delete restrict,
  supplier_id uuid not null references public.suppliers(id) on delete restrict,
  purchase_order_id uuid references public.purchase_orders(id) on delete set null,
  receipt_id uuid references public.purchase_receipts(id) on delete set null,
  invoice_number text not null,
  invoice_date date not null default current_date,
  due_date date,
  amount numeric(14, 2) not null default 0 check (amount >= 0),
  tax_amount numeric(14, 2) not null default 0 check (tax_amount >= 0),
  paid_amount numeric(14, 2) not null default 0 check (paid_amount >= 0),
  status text not null default 'pending',
  notes text,
  created_by uuid references public.user_profiles(id) on delete set null,
  paid_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (supplier_id, invoice_number),
  constraint supplier_invoices_status_check check (status in ('pending', 'partial', 'paid', 'voided'))
);

drop trigger if exists set_supplier_invoices_updated_at on public.supplier_invoices;
create trigger set_supplier_invoices_updated_at
before update on public.supplier_invoices
for each row execute function public.set_updated_at();

create table if not exists public.purchase_returns (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches(id) on delete restrict,
  supplier_id uuid not null references public.suppliers(id) on delete restrict,
  purchase_order_id uuid references public.purchase_orders(id) on delete set null,
  receipt_id uuid references public.purchase_receipts(id) on delete set null,
  return_number text not null unique,
  status text not null default 'posted',
  reason text not null,
  total_amount numeric(14, 2) not null default 0 check (total_amount >= 0),
  notes text,
  created_by uuid references public.user_profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint purchase_returns_status_check check (status in ('posted', 'voided'))
);

create table if not exists public.purchase_return_items (
  id uuid primary key default gen_random_uuid(),
  purchase_return_id uuid not null references public.purchase_returns(id) on delete cascade,
  receipt_item_id uuid not null references public.purchase_receipt_items(id) on delete restrict,
  inventory_batch_id uuid references public.inventory_batches(id) on delete set null,
  product_id uuid not null references public.products(id) on delete restrict,
  product_variant_id uuid references public.product_variants(id) on delete set null,
  product_name text not null,
  sku text,
  quantity_returned integer not null check (quantity_returned > 0),
  unit_cost numeric(14, 2) not null default 0 check (unit_cost >= 0),
  line_total numeric(14, 2) not null default 0 check (line_total >= 0),
  created_at timestamptz not null default now()
);

create table if not exists public.product_cost_history (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches(id) on delete restrict,
  supplier_id uuid references public.suppliers(id) on delete set null,
  purchase_order_id uuid references public.purchase_orders(id) on delete set null,
  receipt_id uuid references public.purchase_receipts(id) on delete set null,
  product_id uuid not null references public.products(id) on delete restrict,
  product_variant_id uuid references public.product_variants(id) on delete set null,
  quantity integer not null check (quantity > 0),
  unit_cost numeric(14, 2) not null check (unit_cost >= 0),
  received_at date not null default current_date,
  created_by uuid references public.user_profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists idx_purchase_orders_branch_status on public.purchase_orders(branch_id, status, order_date desc);
create index if not exists idx_purchase_orders_supplier on public.purchase_orders(supplier_id, order_date desc);
create index if not exists idx_purchase_order_items_order on public.purchase_order_items(purchase_order_id);
create index if not exists idx_purchase_receipts_branch_date on public.purchase_receipts(branch_id, receipt_date desc);
create index if not exists idx_purchase_receipts_order on public.purchase_receipts(purchase_order_id);
create index if not exists idx_purchase_receipt_items_receipt on public.purchase_receipt_items(receipt_id);
create index if not exists idx_supplier_invoices_branch_status on public.supplier_invoices(branch_id, status, due_date);
create index if not exists idx_purchase_returns_branch_date on public.purchase_returns(branch_id, created_at desc);
create index if not exists idx_purchase_return_items_return on public.purchase_return_items(purchase_return_id);
create index if not exists idx_product_cost_history_product on public.product_cost_history(product_id, received_at desc);

alter table public.suppliers enable row level security;
alter table public.purchase_orders enable row level security;
alter table public.purchase_order_items enable row level security;
alter table public.purchase_receipts enable row level security;
alter table public.purchase_receipt_items enable row level security;
alter table public.supplier_invoices enable row level security;
alter table public.purchase_returns enable row level security;
alter table public.purchase_return_items enable row level security;
alter table public.product_cost_history enable row level security;

insert into public.suppliers (supplier_code, name, contact_person, phone, email, payment_terms_days, notes)
values
  ('SUP-GEN', 'General Supplier', 'Purchasing Desk', null, null, 30, 'Seed supplier for purchase management setup.'),
  ('SUP-LOCAL', 'Local Distributor', 'Sales Desk', null, null, 15, 'Seed distributor for receiving tests.')
on conflict (supplier_code) do update
set name = excluded.name,
    payment_terms_days = excluded.payment_terms_days,
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
    jsonb_build_object('key', 'activity.view', 'label', 'View activity logs'),
    jsonb_build_object('key', 'pos.sell', 'label', 'Use POS checkout'),
    jsonb_build_object('key', 'pos.discount', 'label', 'Apply discounts'),
    jsonb_build_object('key', 'pos.void', 'label', 'Void transactions'),
    jsonb_build_object('key', 'reports.view', 'label', 'View reports')
  )
$$;

create or replace function public.purchase_effective_permissions(p_user_id uuid, p_role text)
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

create or replace function public.purchase_user_can_view(p_branch_id uuid)
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
  v_permissions := public.purchase_effective_permissions(v_profile.id, v_profile.role);

  if not coalesce('purchases.view' = any(v_permissions), false) and v_profile.role <> 'admin' then
    return false;
  end if;

  if v_profile.role in ('admin', 'auditor') then
    return true;
  end if;

  return v_profile.branch_id = p_branch_id;
end;
$$;

create or replace function public.purchase_user_can_manage(p_branch_id uuid)
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
  v_permissions := public.purchase_effective_permissions(v_profile.id, v_profile.role);

  if v_profile.role = 'admin' then
    return true;
  end if;

  return v_profile.role = 'manager'
    and v_profile.branch_id = p_branch_id
    and coalesce('purchases.manage' = any(v_permissions), false);
end;
$$;

create or replace function public.purchase_user_can_approve(p_branch_id uuid)
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
  v_permissions := public.purchase_effective_permissions(v_profile.id, v_profile.role);

  if v_profile.role = 'admin' then
    return true;
  end if;

  return v_profile.role = 'manager'
    and v_profile.branch_id = p_branch_id
    and coalesce('purchases.approve' = any(v_permissions), false);
end;
$$;

create or replace function public.purchase_user_can_receive(p_branch_id uuid)
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
  v_permissions := public.purchase_effective_permissions(v_profile.id, v_profile.role);

  if v_profile.role = 'admin' then
    return true;
  end if;

  return v_profile.role = 'manager'
    and v_profile.branch_id = p_branch_id
    and coalesce('purchases.receive' = any(v_permissions), false);
end;
$$;

create or replace function public.purchase_visible_branch_ids(p_profile public.user_profiles)
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

drop policy if exists suppliers_select_by_purchase_role on public.suppliers;
create policy suppliers_select_by_purchase_role
on public.suppliers
for select
to authenticated
using (public.current_user_is_admin() or public.current_user_role() in ('manager', 'auditor'));

drop policy if exists purchase_orders_select_by_role on public.purchase_orders;
create policy purchase_orders_select_by_role
on public.purchase_orders
for select
to authenticated
using (public.purchase_user_can_view(branch_id));

drop policy if exists purchase_order_items_select_by_role on public.purchase_order_items;
create policy purchase_order_items_select_by_role
on public.purchase_order_items
for select
to authenticated
using (
  exists (
    select 1
    from public.purchase_orders po
    where po.id = purchase_order_id
      and public.purchase_user_can_view(po.branch_id)
  )
);

drop policy if exists purchase_receipts_select_by_role on public.purchase_receipts;
create policy purchase_receipts_select_by_role
on public.purchase_receipts
for select
to authenticated
using (public.purchase_user_can_view(branch_id));

drop policy if exists purchase_receipt_items_select_by_role on public.purchase_receipt_items;
create policy purchase_receipt_items_select_by_role
on public.purchase_receipt_items
for select
to authenticated
using (
  exists (
    select 1
    from public.purchase_receipts pr
    where pr.id = receipt_id
      and public.purchase_user_can_view(pr.branch_id)
  )
);

drop policy if exists supplier_invoices_select_by_role on public.supplier_invoices;
create policy supplier_invoices_select_by_role
on public.supplier_invoices
for select
to authenticated
using (public.purchase_user_can_view(branch_id));

drop policy if exists purchase_returns_select_by_role on public.purchase_returns;
create policy purchase_returns_select_by_role
on public.purchase_returns
for select
to authenticated
using (public.purchase_user_can_view(branch_id));

drop policy if exists purchase_return_items_select_by_role on public.purchase_return_items;
create policy purchase_return_items_select_by_role
on public.purchase_return_items
for select
to authenticated
using (
  exists (
    select 1
    from public.purchase_returns pr
    where pr.id = purchase_return_id
      and public.purchase_user_can_view(pr.branch_id)
  )
);

drop policy if exists product_cost_history_select_by_role on public.product_cost_history;
create policy product_cost_history_select_by_role
on public.product_cost_history
for select
to authenticated
using (public.purchase_user_can_view(branch_id));

create or replace function public.purchase_management_get(
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
  v_result jsonb;
begin
  v_profile := public.ensure_active_user();

  if v_to < v_from then
    raise exception 'To date must be after from date' using errcode = '22007';
  end if;

  if v_profile.role not in ('admin', 'auditor') then
    v_branch_filter := v_profile.branch_id;
  end if;

  v_branch_ids := public.purchase_visible_branch_ids(v_profile);

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
      coalesce(invoice_stats.pending_amount, 0)::numeric(14, 2) as pending_amount
    from public.suppliers s
    left join lateral (
      select count(*)::integer as open_orders
      from public.purchase_orders po
      join visible_branches vb on vb.id = po.branch_id
      where po.supplier_id = s.id
        and po.status in ('draft', 'submitted', 'approved', 'partially_received')
    ) po_stats on true
    left join lateral (
      select coalesce(sum(si.amount - si.paid_amount), 0)::numeric(14, 2) as pending_amount
      from public.supplier_invoices si
      join visible_branches vb on vb.id = si.branch_id
      where si.supplier_id = s.id
        and si.status in ('pending', 'partial')
    ) invoice_stats on true
    where s.is_active = true
    order by s.name
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
      pu.abbreviation as unit_abbreviation,
      p.cost_price,
      p.selling_price,
      p.is_active,
      coalesce(variants.variants, '[]'::jsonb) as variants
    from public.products p
    left join public.product_categories pc on pc.id = p.category_id
    left join public.product_brands pb on pb.id = p.brand_id
    left join public.product_units pu on pu.id = p.unit_id
    left join lateral (
      select jsonb_agg(
        jsonb_build_object(
          'id', pv.id,
          'variant_name', pv.variant_name,
          'sku', pv.sku,
          'barcode', pv.barcode,
          'unit_id', pv.unit_id,
          'unit_name', vu.name,
          'unit_abbreviation', vu.abbreviation,
          'cost_price', pv.cost_price,
          'selling_price', pv.selling_price,
          'is_active', pv.is_active
        )
        order by pv.variant_name
      ) as variants
      from public.product_variants pv
      left join public.product_units vu on vu.id = pv.unit_id
      where pv.product_id = p.id
        and pv.deleted_at is null
        and pv.is_active = true
    ) variants on true
    where p.deleted_at is null
      and p.is_active = true
    order by p.name
  ),
  order_rows as (
    select
      po.*,
      b.branch_code,
      b.name as branch_name,
      s.supplier_code,
      s.name as supplier_name,
      requester.full_name as requested_by_name,
      approver.full_name as approved_by_name,
      coalesce(items.items, '[]'::jsonb) as items,
      coalesce(items.item_count, 0)::integer as item_count,
      coalesce(items.ordered_quantity, 0)::integer as ordered_quantity,
      coalesce(items.received_quantity, 0)::integer as received_quantity,
      coalesce(receipts.receipts, '[]'::jsonb) as receipts
    from public.purchase_orders po
    join visible_branches b on b.id = po.branch_id
    join public.suppliers s on s.id = po.supplier_id
    left join public.user_profiles requester on requester.id = po.requested_by
    left join public.user_profiles approver on approver.id = po.approved_by
    left join lateral (
      select
        count(*)::integer as item_count,
        coalesce(sum(poi.quantity_ordered), 0)::integer as ordered_quantity,
        coalesce(sum(poi.quantity_received), 0)::integer as received_quantity,
        jsonb_agg(to_jsonb(poi) order by poi.created_at asc) as items
      from public.purchase_order_items poi
      where poi.purchase_order_id = po.id
    ) items on true
    left join lateral (
      select jsonb_agg(
        jsonb_build_object(
          'id', pr.id,
          'receipt_number', pr.receipt_number,
          'receipt_date', pr.receipt_date,
          'supplier_invoice_number', pr.supplier_invoice_number,
          'total_cost', pr.total_cost,
          'status', pr.status
        )
        order by pr.created_at desc
      ) as receipts
      from public.purchase_receipts pr
      where pr.purchase_order_id = po.id
    ) receipts on true
    where po.order_date >= v_from
      and po.order_date <= v_to
      and (
        v_search = ''
        or lower(po.po_number) like '%' || v_search || '%'
        or lower(s.name) like '%' || v_search || '%'
        or lower(coalesce(po.notes, '')) like '%' || v_search || '%'
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
      receiver.full_name as received_by_name,
      coalesce(items.items, '[]'::jsonb) as items,
      coalesce(items.item_count, 0)::integer as item_count,
      coalesce(items.received_quantity, 0)::integer as received_quantity
    from public.purchase_receipts pr
    join visible_branches b on b.id = pr.branch_id
    join public.suppliers s on s.id = pr.supplier_id
    left join public.purchase_orders po on po.id = pr.purchase_order_id
    left join public.user_profiles receiver on receiver.id = pr.received_by
    left join lateral (
      select
        count(*)::integer as item_count,
        coalesce(sum(pri.quantity_received), 0)::integer as received_quantity,
        jsonb_agg(to_jsonb(pri) order by pri.created_at asc) as items
      from public.purchase_receipt_items pri
      where pri.receipt_id = pr.id
    ) items on true
    where pr.receipt_date >= v_from
      and pr.receipt_date <= v_to
      and (
        v_search = ''
        or lower(pr.receipt_number) like '%' || v_search || '%'
        or lower(coalesce(pr.supplier_invoice_number, '')) like '%' || v_search || '%'
        or lower(s.name) like '%' || v_search || '%'
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
      pr.receipt_number
    from public.supplier_invoices si
    join visible_branches b on b.id = si.branch_id
    join public.suppliers s on s.id = si.supplier_id
    left join public.purchase_orders po on po.id = si.purchase_order_id
    left join public.purchase_receipts pr on pr.id = si.receipt_id
    where si.invoice_date >= v_from
      and si.invoice_date <= v_to
      and (
        v_search = ''
        or lower(si.invoice_number) like '%' || v_search || '%'
        or lower(s.name) like '%' || v_search || '%'
      )
  ),
  return_rows as (
    select
      prt.*,
      b.branch_code,
      b.name as branch_name,
      s.supplier_code,
      s.name as supplier_name,
      po.po_number,
      rec.receipt_number,
      creator.full_name as created_by_name,
      coalesce(items.items, '[]'::jsonb) as items,
      coalesce(items.item_count, 0)::integer as item_count
    from public.purchase_returns prt
    join visible_branches b on b.id = prt.branch_id
    join public.suppliers s on s.id = prt.supplier_id
    left join public.purchase_orders po on po.id = prt.purchase_order_id
    left join public.purchase_receipts rec on rec.id = prt.receipt_id
    left join public.user_profiles creator on creator.id = prt.created_by
    left join lateral (
      select count(*)::integer as item_count, jsonb_agg(to_jsonb(pri) order by pri.created_at asc) as items
      from public.purchase_return_items pri
      where pri.purchase_return_id = prt.id
    ) items on true
    where prt.created_at::date >= v_from
      and prt.created_at::date <= v_to
  ),
  cost_rows as (
    select
      pch.*,
      b.branch_code,
      b.name as branch_name,
      s.name as supplier_name,
      p.name as product_name,
      p.sku,
      pv.variant_name
    from public.product_cost_history pch
    join visible_branches b on b.id = pch.branch_id
    left join public.suppliers s on s.id = pch.supplier_id
    join public.products p on p.id = pch.product_id
    left join public.product_variants pv on pv.id = pch.product_variant_id
    order by pch.created_at desc
    limit 80
  ),
  daily_receipts as (
    select
      rr.receipt_date as business_date,
      to_char(rr.receipt_date, 'Mon DD') as label,
      count(rr.id)::integer as receipts,
      coalesce(sum(rr.total_cost), 0)::numeric(14, 2) as received_value
    from receipt_rows rr
    group by rr.receipt_date
  ),
  branch_summary as (
    select
      vb.id as branch_id,
      vb.branch_code,
      vb.name as branch_name,
      coalesce(order_stats.open_orders, 0)::integer as open_orders,
      coalesce(receipt_stats.receipts, 0)::integer as receipts,
      coalesce(receipt_stats.received_value, 0)::numeric(14, 2) as received_value,
      coalesce(invoice_stats.payable_amount, 0)::numeric(14, 2) as payable_amount
    from visible_branches vb
    left join lateral (
      select count(*)::integer as open_orders
      from order_rows orow
      where orow.branch_id = vb.id
        and orow.status in ('draft', 'submitted', 'approved', 'partially_received')
    ) order_stats on true
    left join lateral (
      select
        count(*)::integer as receipts,
        coalesce(sum(rr.total_cost), 0)::numeric(14, 2) as received_value
      from receipt_rows rr
      where rr.branch_id = vb.id
    ) receipt_stats on true
    left join lateral (
      select coalesce(sum(ir.amount - ir.paid_amount), 0)::numeric(14, 2) as payable_amount
      from invoice_rows ir
      where ir.branch_id = vb.id
        and ir.status in ('pending', 'partial')
    ) invoice_stats on true
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
    'suppliers', coalesce((select jsonb_agg(to_jsonb(supplier_rows) order by name) from supplier_rows), '[]'::jsonb),
    'products', coalesce((select jsonb_agg(to_jsonb(product_rows) order by name) from product_rows), '[]'::jsonb),
    'purchase_orders', coalesce((select jsonb_agg(to_jsonb(order_rows) order by created_at desc) from order_rows), '[]'::jsonb),
    'receipts', coalesce((select jsonb_agg(to_jsonb(receipt_rows) order by created_at desc) from receipt_rows), '[]'::jsonb),
    'supplier_invoices', coalesce((select jsonb_agg(to_jsonb(invoice_rows) order by due_date nulls last, created_at desc) from invoice_rows), '[]'::jsonb),
    'purchase_returns', coalesce((select jsonb_agg(to_jsonb(return_rows) order by created_at desc) from return_rows), '[]'::jsonb),
    'cost_history', coalesce((select jsonb_agg(to_jsonb(cost_rows) order by created_at desc) from cost_rows), '[]'::jsonb),
    'daily_receipts', coalesce((select jsonb_agg(to_jsonb(daily_receipts) order by business_date) from daily_receipts), '[]'::jsonb),
    'branch_summary', coalesce((select jsonb_agg(to_jsonb(branch_summary) order by received_value desc, branch_name) from branch_summary), '[]'::jsonb),
    'summary', jsonb_build_object(
      'open_orders', coalesce((select count(*) from order_rows where status in ('draft', 'submitted', 'approved', 'partially_received')), 0),
      'approved_orders', coalesce((select count(*) from order_rows where status = 'approved'), 0),
      'received_orders', coalesce((select count(*) from order_rows where status = 'received'), 0),
      'receipt_count', coalesce((select count(*) from receipt_rows), 0),
      'received_value', coalesce((select sum(total_cost) from receipt_rows), 0),
      'payable_amount', coalesce((select sum(amount - paid_amount) from invoice_rows where status in ('pending', 'partial')), 0),
      'overdue_invoices', coalesce((select count(*) from invoice_rows where status in ('pending', 'partial') and due_date < current_date), 0),
      'purchase_return_amount', coalesce((select sum(total_amount) from return_rows), 0),
      'supplier_count', coalesce((select count(*) from supplier_rows), 0)
    ),
    'can_manage_purchases', case
      when v_branch_filter is not null then public.purchase_user_can_manage(v_branch_filter)
      when v_profile.role in ('admin', 'manager') then true
      else false
    end,
    'can_approve_purchases', case
      when v_branch_filter is not null then public.purchase_user_can_approve(v_branch_filter)
      when v_profile.role = 'admin' then true
      else false
    end,
    'can_receive_purchases', case
      when v_branch_filter is not null then public.purchase_user_can_receive(v_branch_filter)
      when v_profile.role in ('admin', 'manager') then true
      else false
    end,
    'generated_at', now()
  )
  into v_result;

  return v_result;
end;
$$;

create or replace function public.purchase_supplier_save(p_supplier_id uuid, p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor public.user_profiles;
  v_supplier_id uuid;
  v_name text := trim(coalesce(p_payload->>'name', ''));
  v_code text := upper(trim(coalesce(p_payload->>'supplier_code', '')));
begin
  v_actor := public.ensure_active_user();

  if v_actor.role <> 'admin' and v_actor.role <> 'manager' then
    raise exception 'You cannot save suppliers' using errcode = '42501';
  end if;

  if v_name = '' then
    raise exception 'Supplier name is required' using errcode = '23502';
  end if;

  if v_code = '' then
    v_code := upper(left(regexp_replace(v_name, '[^A-Za-z0-9]+', '-', 'g'), 24));
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
      payment_terms_days,
      credit_limit,
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
      coalesce(nullif(p_payload->>'payment_terms_days', '')::integer, 30),
      coalesce(nullif(p_payload->>'credit_limit', '')::numeric, 0),
      coalesce((p_payload->>'is_active')::boolean, true),
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
        payment_terms_days = coalesce(nullif(p_payload->>'payment_terms_days', '')::integer, payment_terms_days),
        credit_limit = coalesce(nullif(p_payload->>'credit_limit', '')::numeric, credit_limit),
        is_active = coalesce((p_payload->>'is_active')::boolean, is_active),
        notes = nullif(trim(coalesce(p_payload->>'notes', notes, '')), '')
    where id = p_supplier_id
    returning id into v_supplier_id;

    if v_supplier_id is null then
      raise exception 'Supplier not found' using errcode = '02000';
    end if;
  end if;

  perform public.log_activity('purchase.supplier_saved', 'supplier', v_supplier_id::text, jsonb_build_object('supplier_code', v_code, 'name', v_name), v_actor.id);

  return public.purchase_management_get(null, null, null, null);
end;
$$;

create or replace function public.purchase_recalculate_order(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_subtotal numeric(14, 2) := 0;
  v_tax_total numeric(14, 2) := 0;
begin
  select
    coalesce(sum(quantity_ordered * unit_cost), 0)::numeric(14, 2),
    coalesce(sum(tax_amount), 0)::numeric(14, 2)
  into v_subtotal, v_tax_total
  from public.purchase_order_items
  where purchase_order_id = p_order_id;

  update public.purchase_orders
  set subtotal = v_subtotal,
      tax_total = v_tax_total,
      total = v_subtotal + v_tax_total
  where id = p_order_id;
end;
$$;

create or replace function public.purchase_order_save(p_order_id uuid, p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor public.user_profiles;
  v_branch_id uuid := nullif(p_payload->>'branch_id', '')::uuid;
  v_supplier_id uuid := nullif(p_payload->>'supplier_id', '')::uuid;
  v_order_id uuid := p_order_id;
  v_order public.purchase_orders;
  v_po_number text;
  v_item jsonb;
  v_product record;
  v_variant record;
  v_quantity integer;
  v_unit_cost numeric(14, 2);
  v_tax_rate numeric(5, 2);
  v_tax_amount numeric(14, 2);
  v_line_total numeric(14, 2);
begin
  v_actor := public.ensure_active_user();

  if v_branch_id is null or v_supplier_id is null then
    raise exception 'Branch and supplier are required' using errcode = '23502';
  end if;

  if public.purchase_user_can_manage(v_branch_id) = false then
    raise exception 'You cannot manage purchase orders for this branch' using errcode = '42501';
  end if;

  if not exists (select 1 from public.branches where id = v_branch_id and is_active = true) then
    raise exception 'Branch not found or inactive' using errcode = '02000';
  end if;

  if not exists (select 1 from public.suppliers where id = v_supplier_id and is_active = true) then
    raise exception 'Supplier not found or inactive' using errcode = '02000';
  end if;

  if jsonb_array_length(coalesce(p_payload->'items', '[]'::jsonb)) = 0 then
    raise exception 'At least one purchase item is required' using errcode = '23502';
  end if;

  if v_order_id is null then
    v_po_number := 'PO-' || to_char(now(), 'YYYYMMDD-HH24MISS-') || upper(left(replace(gen_random_uuid()::text, '-', ''), 5));

    insert into public.purchase_orders (
      branch_id,
      supplier_id,
      po_number,
      status,
      order_date,
      expected_date,
      notes,
      requested_by
    )
    values (
      v_branch_id,
      v_supplier_id,
      v_po_number,
      coalesce(nullif(p_payload->>'status', ''), 'draft'),
      coalesce(nullif(p_payload->>'order_date', '')::date, current_date),
      nullif(p_payload->>'expected_date', '')::date,
      nullif(trim(coalesce(p_payload->>'notes', '')), ''),
      v_actor.id
    )
    returning id into v_order_id;
  else
    select *
    into v_order
    from public.purchase_orders
    where id = v_order_id
    for update;

    if v_order.id is null then
      raise exception 'Purchase order not found' using errcode = '02000';
    end if;

    if v_order.status not in ('draft', 'submitted', 'approved') then
      raise exception 'Only draft, submitted, or approved purchase orders can be edited before receiving' using errcode = '23514';
    end if;

    if exists (select 1 from public.purchase_order_items where purchase_order_id = v_order_id and quantity_received > 0) then
      raise exception 'Purchase order with received items cannot be edited' using errcode = '23514';
    end if;

    update public.purchase_orders
    set branch_id = v_branch_id,
        supplier_id = v_supplier_id,
        order_date = coalesce(nullif(p_payload->>'order_date', '')::date, order_date),
        expected_date = nullif(p_payload->>'expected_date', '')::date,
        notes = nullif(trim(coalesce(p_payload->>'notes', notes, '')), '')
    where id = v_order_id;

    delete from public.purchase_order_items
    where purchase_order_id = v_order_id;
  end if;

  for v_item in select value from jsonb_array_elements(coalesce(p_payload->'items', '[]'::jsonb))
  loop
    v_quantity := coalesce(nullif(v_item->>'quantity_ordered', '')::integer, 0);
    v_unit_cost := coalesce(nullif(v_item->>'unit_cost', '')::numeric, 0);
    v_tax_rate := coalesce(nullif(v_item->>'tax_rate', '')::numeric, 0);

    if v_quantity <= 0 then
      raise exception 'Purchase item quantity must be greater than zero' using errcode = '23514';
    end if;

    select
      p.id,
      p.name,
      p.sku,
      p.barcode,
      p.cost_price
    into v_product
    from public.products p
    where p.id = nullif(v_item->>'product_id', '')::uuid
      and p.deleted_at is null
      and p.is_active = true;

    if v_product.id is null then
      raise exception 'Purchase item product is required' using errcode = '23502';
    end if;

    select null::uuid as id, null::text as variant_name, null::text as sku, null::text as barcode, null::numeric as cost_price
    into v_variant;
    if nullif(v_item->>'product_variant_id', '') is not null then
      select
        pv.id,
        pv.variant_name,
        pv.sku,
        pv.barcode,
        pv.cost_price
      into v_variant
      from public.product_variants pv
      where pv.id = nullif(v_item->>'product_variant_id', '')::uuid
        and pv.product_id = v_product.id
        and pv.deleted_at is null
        and pv.is_active = true;

      if v_variant.id is null then
        raise exception 'Selected variant does not belong to this product' using errcode = '23514';
      end if;
    end if;

    if v_unit_cost = 0 then
      v_unit_cost := coalesce(v_variant.cost_price, v_product.cost_price, 0);
    end if;

    v_tax_amount := round((v_quantity * v_unit_cost) * (v_tax_rate / 100), 2);
    v_line_total := round((v_quantity * v_unit_cost) + v_tax_amount, 2);

    insert into public.purchase_order_items (
      purchase_order_id,
      product_id,
      product_variant_id,
      product_name,
      sku,
      barcode,
      variant_name,
      quantity_ordered,
      unit_cost,
      tax_rate,
      tax_amount,
      line_total
    )
    values (
      v_order_id,
      v_product.id,
      v_variant.id,
      v_product.name,
      coalesce(v_variant.sku, v_product.sku),
      coalesce(v_variant.barcode, v_product.barcode),
      v_variant.variant_name,
      v_quantity,
      v_unit_cost,
      v_tax_rate,
      v_tax_amount,
      v_line_total
    );
  end loop;

  perform public.purchase_recalculate_order(v_order_id);
  perform public.log_activity('purchase.order_saved', 'purchase_order', v_order_id::text, jsonb_build_object('branch_id', v_branch_id, 'supplier_id', v_supplier_id), v_actor.id);

  return public.purchase_management_get(current_date - 29, current_date, v_branch_id, null);
end;
$$;

create or replace function public.purchase_order_status_update(p_order_id uuid, p_status text, p_reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor public.user_profiles;
  v_order public.purchase_orders;
  v_status text := lower(trim(coalesce(p_status, '')));
begin
  v_actor := public.ensure_active_user();

  select *
  into v_order
  from public.purchase_orders
  where id = p_order_id
  for update;

  if v_order.id is null then
    raise exception 'Purchase order not found' using errcode = '02000';
  end if;

  if v_status not in ('submitted', 'approved', 'cancelled', 'closed') then
    raise exception 'Invalid purchase order status update' using errcode = '22023';
  end if;

  if v_status = 'approved' and public.purchase_user_can_approve(v_order.branch_id) = false then
    raise exception 'You cannot approve purchase orders for this branch' using errcode = '42501';
  elsif v_status <> 'approved' and public.purchase_user_can_manage(v_order.branch_id) = false then
    raise exception 'You cannot update purchase orders for this branch' using errcode = '42501';
  end if;

  if v_status = 'submitted' and v_order.status <> 'draft' then
    raise exception 'Only draft purchase orders can be submitted' using errcode = '23514';
  end if;

  if v_status = 'approved' and v_order.status not in ('draft', 'submitted') then
    raise exception 'Only draft or submitted purchase orders can be approved' using errcode = '23514';
  end if;

  if v_status = 'cancelled' and v_order.status in ('received', 'closed') then
    raise exception 'Received or closed purchase orders cannot be cancelled' using errcode = '23514';
  end if;

  if v_status = 'closed' and v_order.status not in ('received', 'partially_received') then
    raise exception 'Only received or partially received purchase orders can be closed' using errcode = '23514';
  end if;

  update public.purchase_orders
  set status = v_status,
      approved_by = case when v_status = 'approved' then v_actor.id else approved_by end,
      approved_at = case when v_status = 'approved' then now() else approved_at end,
      cancelled_by = case when v_status = 'cancelled' then v_actor.id else cancelled_by end,
      cancelled_at = case when v_status = 'cancelled' then now() else cancelled_at end,
      cancel_reason = case when v_status = 'cancelled' then nullif(trim(coalesce(p_reason, '')), '') else cancel_reason end
  where id = p_order_id;

  perform public.log_activity('purchase.order_status_updated', 'purchase_order', p_order_id::text, jsonb_build_object('status', v_status, 'reason', p_reason), v_actor.id);

  return public.purchase_management_get(current_date - 29, current_date, v_order.branch_id, null);
end;
$$;

create or replace function public.purchase_receive(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor public.user_profiles;
  v_order public.purchase_orders;
  v_supplier public.suppliers;
  v_branch_id uuid := nullif(p_payload->>'branch_id', '')::uuid;
  v_supplier_id uuid := nullif(p_payload->>'supplier_id', '')::uuid;
  v_order_id uuid := nullif(p_payload->>'purchase_order_id', '')::uuid;
  v_receipt_id uuid;
  v_receipt_number text;
  v_supplier_invoice_number text := nullif(trim(coalesce(p_payload->>'supplier_invoice_number', '')), '');
  v_receipt_date date := coalesce(nullif(p_payload->>'receipt_date', '')::date, current_date);
  v_invoice_date date := coalesce(nullif(p_payload->>'invoice_date', '')::date, v_receipt_date);
  v_due_date date;
  v_notes text := nullif(trim(coalesce(p_payload->>'notes', '')), '');
  v_items jsonb := coalesce(p_payload->'items', '[]'::jsonb);
  v_item jsonb;
  v_po_item public.purchase_order_items;
  v_product record;
  v_variant record;
  v_quantity integer;
  v_unit_cost numeric(14, 2);
  v_tax_rate numeric(5, 2);
  v_tax_amount numeric(14, 2);
  v_line_total numeric(14, 2);
  v_batch_number text;
  v_expiry_date date;
  v_batch_id uuid;
  v_receipt_item_id uuid;
  v_before_total integer;
  v_after_total integer;
  v_total_cost numeric(14, 2) := 0;
  v_total_tax numeric(14, 2) := 0;
  v_all_received boolean;
begin
  v_actor := public.ensure_active_user();

  if v_order_id is not null then
    select *
    into v_order
    from public.purchase_orders
    where id = v_order_id
    for update;

    if v_order.id is null then
      raise exception 'Purchase order not found' using errcode = '02000';
    end if;

    if v_order.status not in ('submitted', 'approved', 'partially_received') then
      raise exception 'Only submitted, approved, or partially received purchase orders can be received' using errcode = '23514';
    end if;

    v_branch_id := v_order.branch_id;
    v_supplier_id := v_order.supplier_id;
  end if;

  if v_branch_id is null or v_supplier_id is null then
    raise exception 'Branch and supplier are required for receiving' using errcode = '23502';
  end if;

  if public.purchase_user_can_receive(v_branch_id) = false then
    raise exception 'You cannot receive purchases for this branch' using errcode = '42501';
  end if;

  select *
  into v_supplier
  from public.suppliers
  where id = v_supplier_id
    and is_active = true;

  if v_supplier.id is null then
    raise exception 'Supplier not found or inactive' using errcode = '02000';
  end if;

  if jsonb_array_length(v_items) = 0 then
    raise exception 'At least one receiving item is required' using errcode = '23502';
  end if;

  v_receipt_number := 'GRN-' || to_char(now(), 'YYYYMMDD-HH24MISS-') || upper(left(replace(gen_random_uuid()::text, '-', ''), 5));

  insert into public.purchase_receipts (
    branch_id,
    supplier_id,
    purchase_order_id,
    receipt_number,
    supplier_invoice_number,
    receipt_date,
    notes,
    received_by
  )
  values (
    v_branch_id,
    v_supplier_id,
    v_order_id,
    v_receipt_number,
    v_supplier_invoice_number,
    v_receipt_date,
    v_notes,
    v_actor.id
  )
  returning id into v_receipt_id;

  for v_item in select value from jsonb_array_elements(v_items)
  loop
    v_po_item := null;
    if nullif(v_item->>'purchase_order_item_id', '') is not null then
      select *
      into v_po_item
      from public.purchase_order_items
      where id = nullif(v_item->>'purchase_order_item_id', '')::uuid
        and (v_order_id is null or purchase_order_id = v_order_id)
      for update;

      if v_po_item.id is null then
        raise exception 'Purchase order item not found' using errcode = '02000';
      end if;
    end if;

    v_quantity := coalesce(nullif(v_item->>'quantity_received', '')::integer, 0);
    v_unit_cost := coalesce(nullif(v_item->>'unit_cost', '')::numeric, coalesce(v_po_item.unit_cost, 0));
    v_tax_rate := coalesce(nullif(v_item->>'tax_rate', '')::numeric, coalesce(v_po_item.tax_rate, 0));
    v_batch_number := nullif(trim(coalesce(v_item->>'batch_number', '')), '');
    v_expiry_date := nullif(v_item->>'expiry_date', '')::date;

    if v_quantity <= 0 then
      continue;
    end if;

    if v_po_item.id is not null and v_quantity > (v_po_item.quantity_ordered - v_po_item.quantity_received) then
      raise exception 'Received quantity exceeds remaining purchase order quantity' using errcode = '23514';
    end if;

    select
      p.id,
      p.name,
      p.sku,
      p.barcode,
      p.cost_price
    into v_product
    from public.products p
    where p.id = coalesce(v_po_item.product_id, nullif(v_item->>'product_id', '')::uuid)
      and p.deleted_at is null
      and p.is_active = true;

    if v_product.id is null then
      raise exception 'Receiving product is required' using errcode = '23502';
    end if;

    select null::uuid as id, null::text as variant_name, null::text as sku, null::text as barcode, null::numeric as cost_price
    into v_variant;
    if coalesce(v_po_item.product_variant_id, nullif(v_item->>'product_variant_id', '')::uuid) is not null then
      select
        pv.id,
        pv.variant_name,
        pv.sku,
        pv.barcode,
        pv.cost_price
      into v_variant
      from public.product_variants pv
      where pv.id = coalesce(v_po_item.product_variant_id, nullif(v_item->>'product_variant_id', '')::uuid)
        and pv.product_id = v_product.id
        and pv.deleted_at is null;
    end if;

    if v_unit_cost = 0 then
      v_unit_cost := coalesce(v_variant.cost_price, v_product.cost_price, 0);
    end if;

    if v_batch_number is null then
      v_batch_number := 'PO-' || to_char(now(), 'YYYYMMDDHH24MISS');
    end if;

    v_tax_amount := round((v_quantity * v_unit_cost) * (v_tax_rate / 100), 2);
    v_line_total := round((v_quantity * v_unit_cost) + v_tax_amount, 2);

    select coalesce(sum(quantity_on_hand), 0)::integer
    into v_before_total
    from public.inventory_batches
    where branch_id = v_branch_id
      and product_id = v_product.id
      and status = 'active';

    insert into public.inventory_batches (
      branch_id,
      product_id,
      product_variant_id,
      batch_number,
      expiry_date,
      quantity_on_hand,
      unit_cost,
      received_at,
      status
    )
    values (
      v_branch_id,
      v_product.id,
      v_variant.id,
      v_batch_number,
      v_expiry_date,
      v_quantity,
      v_unit_cost,
      v_receipt_date,
      'active'
    )
    returning id into v_batch_id;

    v_after_total := v_before_total + v_quantity;

    insert into public.inventory_movements (
      branch_id,
      product_id,
      product_variant_id,
      batch_id,
      movement_type,
      quantity_delta,
      quantity_before,
      quantity_after,
      unit_cost,
      batch_number,
      expiry_date,
      reference_number,
      reason,
      created_by
    )
    values (
      v_branch_id,
      v_product.id,
      v_variant.id,
      v_batch_id,
      'stock_in',
      v_quantity,
      v_before_total,
      v_after_total,
      v_unit_cost,
      v_batch_number,
      v_expiry_date,
      v_receipt_number,
      'Purchase receiving',
      v_actor.id
    );

    insert into public.purchase_receipt_items (
      receipt_id,
      purchase_order_item_id,
      product_id,
      product_variant_id,
      inventory_batch_id,
      product_name,
      sku,
      barcode,
      variant_name,
      quantity_received,
      unit_cost,
      tax_rate,
      tax_amount,
      line_total,
      batch_number,
      expiry_date
    )
    values (
      v_receipt_id,
      v_po_item.id,
      v_product.id,
      v_variant.id,
      v_batch_id,
      v_product.name,
      coalesce(v_variant.sku, v_product.sku),
      coalesce(v_variant.barcode, v_product.barcode),
      v_variant.variant_name,
      v_quantity,
      v_unit_cost,
      v_tax_rate,
      v_tax_amount,
      v_line_total,
      v_batch_number,
      v_expiry_date
    )
    returning id into v_receipt_item_id;

    insert into public.product_cost_history (
      branch_id,
      supplier_id,
      purchase_order_id,
      receipt_id,
      product_id,
      product_variant_id,
      quantity,
      unit_cost,
      received_at,
      created_by
    )
    values (
      v_branch_id,
      v_supplier_id,
      v_order_id,
      v_receipt_id,
      v_product.id,
      v_variant.id,
      v_quantity,
      v_unit_cost,
      v_receipt_date,
      v_actor.id
    );

    if v_variant.id is not null then
      update public.product_variants
      set cost_price = v_unit_cost
      where id = v_variant.id;
    else
      update public.products
      set cost_price = v_unit_cost
      where id = v_product.id;
    end if;

    if v_po_item.id is not null then
      update public.purchase_order_items
      set quantity_received = quantity_received + v_quantity
      where id = v_po_item.id;
    end if;

    perform public.inventory_sync_product_stock(v_branch_id, v_product.id);

    v_total_cost := v_total_cost + v_line_total;
    v_total_tax := v_total_tax + v_tax_amount;
  end loop;

  if v_total_cost <= 0 then
    raise exception 'At least one receiving item must have quantity greater than zero' using errcode = '23514';
  end if;

  update public.purchase_receipts
  set total_cost = v_total_cost,
      tax_total = v_total_tax
  where id = v_receipt_id;

  if v_order_id is not null then
    select not exists (
      select 1
      from public.purchase_order_items
      where purchase_order_id = v_order_id
        and quantity_received < quantity_ordered
    )
    into v_all_received;

    update public.purchase_orders
    set status = case when v_all_received then 'received' else 'partially_received' end
    where id = v_order_id;
  end if;

  v_due_date := coalesce(nullif(p_payload->>'due_date', '')::date, v_invoice_date + coalesce(v_supplier.payment_terms_days, 30));

  insert into public.supplier_invoices (
    branch_id,
    supplier_id,
    purchase_order_id,
    receipt_id,
    invoice_number,
    invoice_date,
    due_date,
    amount,
    tax_amount,
    status,
    notes,
    created_by
  )
  values (
    v_branch_id,
    v_supplier_id,
    v_order_id,
    v_receipt_id,
    coalesce(v_supplier_invoice_number, v_receipt_number),
    v_invoice_date,
    v_due_date,
    v_total_cost,
    v_total_tax,
    'pending',
    v_notes,
    v_actor.id
  )
  on conflict (supplier_id, invoice_number) do update
  set receipt_id = excluded.receipt_id,
      amount = excluded.amount,
      tax_amount = excluded.tax_amount,
      due_date = excluded.due_date,
      status = case when public.supplier_invoices.status = 'voided' then 'pending' else public.supplier_invoices.status end;

  perform public.log_activity('purchase.received', 'purchase_receipt', v_receipt_id::text, jsonb_build_object('receipt_number', v_receipt_number, 'total_cost', v_total_cost), v_actor.id);

  return public.purchase_management_get(current_date - 29, current_date, v_branch_id, null);
end;
$$;

create or replace function public.purchase_invoice_status_update(
  p_invoice_id uuid,
  p_status text,
  p_paid_amount numeric default null,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor public.user_profiles;
  v_invoice public.supplier_invoices;
  v_status text := lower(trim(coalesce(p_status, '')));
  v_paid numeric(14, 2);
begin
  v_actor := public.ensure_active_user();

  select *
  into v_invoice
  from public.supplier_invoices
  where id = p_invoice_id
  for update;

  if v_invoice.id is null then
    raise exception 'Supplier invoice not found' using errcode = '02000';
  end if;

  if public.purchase_user_can_manage(v_invoice.branch_id) = false then
    raise exception 'You cannot update supplier invoices for this branch' using errcode = '42501';
  end if;

  if v_status not in ('pending', 'partial', 'paid', 'voided') then
    raise exception 'Invalid supplier invoice status' using errcode = '22023';
  end if;

  v_paid := coalesce(p_paid_amount, case when v_status = 'paid' then v_invoice.amount else v_invoice.paid_amount end);

  if v_paid < 0 or v_paid > v_invoice.amount then
    raise exception 'Paid amount must be between zero and invoice amount' using errcode = '23514';
  end if;

  if v_status = 'paid' then
    v_paid := v_invoice.amount;
  elsif v_paid > 0 and v_paid < v_invoice.amount and v_status = 'pending' then
    v_status := 'partial';
  end if;

  update public.supplier_invoices
  set status = v_status,
      paid_amount = v_paid,
      paid_at = case when v_status = 'paid' then now() else paid_at end,
      notes = nullif(trim(coalesce(p_notes, notes, '')), '')
  where id = p_invoice_id;

  perform public.log_activity('purchase.invoice_status_updated', 'supplier_invoice', p_invoice_id::text, jsonb_build_object('status', v_status, 'paid_amount', v_paid), v_actor.id);

  return public.purchase_management_get(current_date - 29, current_date, v_invoice.branch_id, null);
end;
$$;

create or replace function public.purchase_return_process(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor public.user_profiles;
  v_receipt public.purchase_receipts;
  v_receipt_id uuid := nullif(p_payload->>'receipt_id', '')::uuid;
  v_reason text := trim(coalesce(p_payload->>'reason', ''));
  v_notes text := nullif(trim(coalesce(p_payload->>'notes', '')), '');
  v_items jsonb := coalesce(p_payload->'items', '[]'::jsonb);
  v_item jsonb;
  v_receipt_item public.purchase_receipt_items;
  v_return_id uuid;
  v_return_number text;
  v_quantity integer;
  v_previous_returned integer;
  v_batch public.inventory_batches;
  v_before_total integer;
  v_after_total integer;
  v_line_total numeric(14, 2);
  v_total_amount numeric(14, 2) := 0;
begin
  v_actor := public.ensure_active_user();

  if v_receipt_id is null then
    raise exception 'Receipt is required for a purchase return' using errcode = '23502';
  end if;

  select *
  into v_receipt
  from public.purchase_receipts
  where id = v_receipt_id
  for update;

  if v_receipt.id is null then
    raise exception 'Purchase receipt not found' using errcode = '02000';
  end if;

  if public.purchase_user_can_manage(v_receipt.branch_id) = false then
    raise exception 'You cannot process purchase returns for this branch' using errcode = '42501';
  end if;

  if v_reason = '' then
    raise exception 'Purchase return reason is required' using errcode = '23502';
  end if;

  if jsonb_array_length(v_items) = 0 then
    raise exception 'At least one purchase return item is required' using errcode = '23502';
  end if;

  v_return_number := 'PR-' || to_char(now(), 'YYYYMMDD-HH24MISS-') || upper(left(replace(gen_random_uuid()::text, '-', ''), 5));

  insert into public.purchase_returns (
    branch_id,
    supplier_id,
    purchase_order_id,
    receipt_id,
    return_number,
    reason,
    notes,
    created_by
  )
  values (
    v_receipt.branch_id,
    v_receipt.supplier_id,
    v_receipt.purchase_order_id,
    v_receipt.id,
    v_return_number,
    v_reason,
    v_notes,
    v_actor.id
  )
  returning id into v_return_id;

  for v_item in select value from jsonb_array_elements(v_items)
  loop
    v_quantity := coalesce(nullif(v_item->>'quantity_returned', '')::integer, 0);
    if v_quantity <= 0 then
      continue;
    end if;

    select *
    into v_receipt_item
    from public.purchase_receipt_items
    where id = nullif(v_item->>'receipt_item_id', '')::uuid
      and receipt_id = v_receipt.id
    for update;

    if v_receipt_item.id is null then
      raise exception 'Purchase return item does not belong to this receipt' using errcode = '23514';
    end if;

    select coalesce(sum(pri.quantity_returned), 0)::integer
    into v_previous_returned
    from public.purchase_return_items pri
    join public.purchase_returns pr on pr.id = pri.purchase_return_id
    where pr.status = 'posted'
      and pri.receipt_item_id = v_receipt_item.id;

    if v_quantity > (v_receipt_item.quantity_received - v_previous_returned) then
      raise exception 'Purchase return quantity exceeds received quantity' using errcode = '23514';
    end if;

    select *
    into v_batch
    from public.inventory_batches
    where id = v_receipt_item.inventory_batch_id
      and branch_id = v_receipt.branch_id
      and product_id = v_receipt_item.product_id
    for update;

    if v_batch.id is null or v_batch.quantity_on_hand < v_quantity then
      raise exception 'Purchase return batch does not have enough stock' using errcode = '23514';
    end if;

    select coalesce(sum(quantity_on_hand), 0)::integer
    into v_before_total
    from public.inventory_batches
    where branch_id = v_receipt.branch_id
      and product_id = v_receipt_item.product_id
      and status = 'active';

    update public.inventory_batches
    set quantity_on_hand = quantity_on_hand - v_quantity,
        status = case when quantity_on_hand - v_quantity = 0 then 'depleted' else status end
    where id = v_batch.id;

    v_after_total := v_before_total - v_quantity;
    v_line_total := round(v_quantity * v_receipt_item.unit_cost, 2);

    insert into public.inventory_movements (
      branch_id,
      product_id,
      product_variant_id,
      batch_id,
      movement_type,
      quantity_delta,
      quantity_before,
      quantity_after,
      unit_cost,
      batch_number,
      expiry_date,
      reference_number,
      reason,
      created_by
    )
    values (
      v_receipt.branch_id,
      v_receipt_item.product_id,
      v_receipt_item.product_variant_id,
      v_batch.id,
      'stock_out',
      -v_quantity,
      v_before_total,
      greatest(v_after_total, 0),
      v_receipt_item.unit_cost,
      v_receipt_item.batch_number,
      v_receipt_item.expiry_date,
      v_return_number,
      'Purchase return to supplier: ' || v_reason,
      v_actor.id
    );

    insert into public.purchase_return_items (
      purchase_return_id,
      receipt_item_id,
      inventory_batch_id,
      product_id,
      product_variant_id,
      product_name,
      sku,
      quantity_returned,
      unit_cost,
      line_total
    )
    values (
      v_return_id,
      v_receipt_item.id,
      v_batch.id,
      v_receipt_item.product_id,
      v_receipt_item.product_variant_id,
      v_receipt_item.product_name,
      v_receipt_item.sku,
      v_quantity,
      v_receipt_item.unit_cost,
      v_line_total
    );

    update public.purchase_receipt_items
    set quantity_returned = quantity_returned + v_quantity
    where id = v_receipt_item.id;

    perform public.inventory_sync_product_stock(v_receipt.branch_id, v_receipt_item.product_id);

    v_total_amount := v_total_amount + v_line_total;
  end loop;

  if v_total_amount <= 0 then
    raise exception 'At least one purchase return item must have quantity greater than zero' using errcode = '23514';
  end if;

  update public.purchase_returns
  set total_amount = v_total_amount
  where id = v_return_id;

  perform public.log_activity('purchase.return_posted', 'purchase_return', v_return_id::text, jsonb_build_object('return_number', v_return_number, 'total_amount', v_total_amount), v_actor.id);

  return public.purchase_management_get(current_date - 29, current_date, v_receipt.branch_id, null);
end;
$$;

revoke all on function public.purchase_effective_permissions(uuid, text) from public;
revoke all on function public.purchase_user_can_view(uuid) from public;
revoke all on function public.purchase_user_can_manage(uuid) from public;
revoke all on function public.purchase_user_can_approve(uuid) from public;
revoke all on function public.purchase_user_can_receive(uuid) from public;
revoke all on function public.purchase_visible_branch_ids(public.user_profiles) from public;
revoke all on function public.purchase_management_get(date, date, uuid, text) from public;
revoke all on function public.purchase_supplier_save(uuid, jsonb) from public;
revoke all on function public.purchase_recalculate_order(uuid) from public;
revoke all on function public.purchase_order_save(uuid, jsonb) from public;
revoke all on function public.purchase_order_status_update(uuid, text, text) from public;
revoke all on function public.purchase_receive(jsonb) from public;
revoke all on function public.purchase_invoice_status_update(uuid, text, numeric, text) from public;
revoke all on function public.purchase_return_process(jsonb) from public;

grant execute on function public.purchase_management_get(date, date, uuid, text) to authenticated;
grant execute on function public.purchase_supplier_save(uuid, jsonb) to authenticated;
grant execute on function public.purchase_order_save(uuid, jsonb) to authenticated;
grant execute on function public.purchase_order_status_update(uuid, text, text) to authenticated;
grant execute on function public.purchase_receive(jsonb) to authenticated;
grant execute on function public.purchase_invoice_status_update(uuid, text, numeric, text) to authenticated;
grant execute on function public.purchase_return_process(jsonb) to authenticated;

notify pgrst, 'reload schema';
