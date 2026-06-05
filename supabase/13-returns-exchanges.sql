-- MODULE 13: RETURNS & EXCHANGES
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
--
-- Scope:
-- - Sales return
-- - Refund
-- - Exchange credit
-- - Void transaction support through the BIR void routine
-- - Credit memo issuance
-- - Return reason tracking
-- - Returned-stock restoration with original batch traceability

create extension if not exists pgcrypto;

alter table public.sales_orders
  add column if not exists return_total numeric(14, 2) not null default 0,
  add column if not exists returned_item_count integer not null default 0,
  add column if not exists return_status text not null default 'none';

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'sales_orders_return_status_check'
      and conrelid = 'public.sales_orders'::regclass
  ) then
    alter table public.sales_orders
      add constraint sales_orders_return_status_check
      check (return_status in ('none', 'partial', 'full', 'voided'));
  end if;
end;
$$;

create table if not exists public.return_reasons (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  requires_note boolean not null default false,
  is_active boolean not null default true,
  sort_order integer not null default 100,
  created_at timestamptz not null default now()
);

create table if not exists public.sales_returns (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches(id) on delete restrict,
  original_order_id uuid not null references public.sales_orders(id) on delete restrict,
  return_number text not null unique,
  return_type text not null,
  status text not null default 'processing',
  customer_name text,
  reason_id uuid references public.return_reasons(id) on delete set null,
  reason_name text,
  reason_note text,
  refund_method text,
  refund_reference text,
  total_return_amount numeric(14, 2) not null default 0,
  refund_amount numeric(14, 2) not null default 0,
  credit_memo_amount numeric(14, 2) not null default 0,
  exchange_order_id uuid references public.sales_orders(id) on delete set null,
  notes text,
  requested_by uuid references public.user_profiles(id) on delete set null,
  approved_by uuid references public.user_profiles(id) on delete set null,
  completed_by uuid references public.user_profiles(id) on delete set null,
  completed_at timestamptz,
  voided_by uuid references public.user_profiles(id) on delete set null,
  voided_at timestamptz,
  void_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint sales_returns_type_check check (return_type in ('refund', 'exchange', 'credit_memo', 'void')),
  constraint sales_returns_status_check check (status in ('processing', 'completed', 'voided', 'rejected')),
  constraint sales_returns_refund_method_check check (
    refund_method is null
    or refund_method in ('cash', 'card', 'gcash', 'maya', 'bank_transfer', 'store_credit', 'cod')
  ),
  constraint sales_returns_amounts_check check (
    total_return_amount >= 0
    and refund_amount >= 0
    and credit_memo_amount >= 0
  )
);

drop trigger if exists set_sales_returns_updated_at on public.sales_returns;
create trigger set_sales_returns_updated_at
before update on public.sales_returns
for each row execute function public.set_updated_at();

create table if not exists public.sales_return_items (
  id uuid primary key default gen_random_uuid(),
  return_id uuid not null references public.sales_returns(id) on delete cascade,
  order_item_id uuid not null references public.sales_order_items(id) on delete restrict,
  product_id uuid not null references public.products(id) on delete restrict,
  product_variant_id uuid references public.product_variants(id) on delete set null,
  product_name text not null,
  sku text,
  barcode text,
  variant_name text,
  quantity integer not null check (quantity > 0),
  unit_price numeric(14, 2) not null default 0,
  gross_amount numeric(14, 2) not null default 0,
  discount_amount numeric(14, 2) not null default 0,
  tax_amount numeric(14, 2) not null default 0,
  net_amount numeric(14, 2) not null default 0,
  condition text not null default 'good',
  disposition text not null default 'return_to_stock',
  created_at timestamptz not null default now(),
  constraint sales_return_items_condition_check check (condition in ('good', 'damaged', 'expired', 'wrong_item', 'not_returnable')),
  constraint sales_return_items_disposition_check check (disposition in ('return_to_stock', 'damaged', 'expired', 'write_off'))
);

create table if not exists public.sales_return_batch_allocations (
  id uuid primary key default gen_random_uuid(),
  return_item_id uuid not null references public.sales_return_items(id) on delete cascade,
  original_allocation_id uuid references public.sales_order_batch_allocations(id) on delete set null,
  inventory_batch_id uuid references public.inventory_batches(id) on delete set null,
  batch_number text,
  expiry_date date,
  quantity integer not null check (quantity > 0),
  unit_cost numeric(14, 2) not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.credit_memos (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches(id) on delete restrict,
  return_id uuid not null unique references public.sales_returns(id) on delete cascade,
  original_order_id uuid not null references public.sales_orders(id) on delete restrict,
  credit_memo_number text not null unique,
  customer_name text,
  amount numeric(14, 2) not null check (amount >= 0),
  available_amount numeric(14, 2) not null check (available_amount >= 0),
  status text not null default 'open',
  issued_by uuid references public.user_profiles(id) on delete set null,
  issued_at timestamptz not null default now(),
  expires_at date,
  notes text,
  constraint credit_memos_status_check check (status in ('open', 'used', 'voided', 'expired'))
);

create table if not exists public.sales_refunds (
  id uuid primary key default gen_random_uuid(),
  return_id uuid not null references public.sales_returns(id) on delete cascade,
  branch_id uuid not null references public.branches(id) on delete restrict,
  original_order_id uuid not null references public.sales_orders(id) on delete restrict,
  refund_method text not null check (refund_method in ('cash', 'card', 'gcash', 'maya', 'bank_transfer', 'store_credit', 'cod')),
  amount numeric(14, 2) not null check (amount > 0),
  reference_number text,
  status text not null default 'processed' check (status in ('processed', 'pending', 'voided')),
  processed_by uuid references public.user_profiles(id) on delete set null,
  processed_at timestamptz not null default now(),
  notes text
);

create index if not exists idx_sales_returns_branch_created on public.sales_returns(branch_id, created_at desc);
create index if not exists idx_sales_returns_order on public.sales_returns(original_order_id);
create index if not exists idx_sales_return_items_return on public.sales_return_items(return_id);
create index if not exists idx_sales_return_items_order_item on public.sales_return_items(order_item_id);
create index if not exists idx_sales_return_batches_item on public.sales_return_batch_allocations(return_item_id);
create index if not exists idx_credit_memos_branch_status on public.credit_memos(branch_id, status, issued_at desc);
create index if not exists idx_sales_refunds_branch_created on public.sales_refunds(branch_id, processed_at desc);
create index if not exists idx_sales_orders_return_status on public.sales_orders(return_status, business_date desc);

alter table public.return_reasons enable row level security;
alter table public.sales_returns enable row level security;
alter table public.sales_return_items enable row level security;
alter table public.sales_return_batch_allocations enable row level security;
alter table public.credit_memos enable row level security;
alter table public.sales_refunds enable row level security;

insert into public.return_reasons (code, name, requires_note, sort_order)
values
  ('damaged_item', 'Damaged item', false, 10),
  ('expired_item', 'Expired item', false, 20),
  ('wrong_item', 'Wrong item sold', false, 30),
  ('customer_request', 'Customer request', false, 40),
  ('duplicate_sale', 'Duplicate sale', true, 50),
  ('price_error', 'Price or discount error', true, 60),
  ('exchange', 'Exchange request', false, 70),
  ('other', 'Other reason', true, 100)
on conflict (code) do update
set name = excluded.name,
    requires_note = excluded.requires_note,
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
    jsonb_build_object('key', 'activity.view', 'label', 'View activity logs'),
    jsonb_build_object('key', 'pos.sell', 'label', 'Use POS checkout'),
    jsonb_build_object('key', 'pos.discount', 'label', 'Apply discounts'),
    jsonb_build_object('key', 'pos.void', 'label', 'Void transactions'),
    jsonb_build_object('key', 'reports.view', 'label', 'View reports')
  )
$$;

create or replace function public.returns_effective_permissions(p_user_id uuid, p_role text)
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

create or replace function public.returns_user_can_view(p_branch_id uuid)
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
  v_permissions := public.returns_effective_permissions(v_profile.id, v_profile.role);

  if not coalesce('returns.view' = any(v_permissions), false) and v_profile.role <> 'admin' then
    return false;
  end if;

  if v_profile.role in ('admin', 'auditor') then
    return true;
  end if;

  return v_profile.branch_id = p_branch_id;
end;
$$;

create or replace function public.returns_user_can_manage(p_branch_id uuid)
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
  v_permissions := public.returns_effective_permissions(v_profile.id, v_profile.role);

  if v_profile.role = 'admin' then
    return true;
  end if;

  if not coalesce('returns.manage' = any(v_permissions), false) then
    return false;
  end if;

  return v_profile.role in ('manager', 'cashier')
    and v_profile.branch_id = p_branch_id;
end;
$$;

create or replace function public.returns_user_can_void(p_branch_id uuid)
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
  v_permissions := public.returns_effective_permissions(v_profile.id, v_profile.role);

  if v_profile.role = 'admin' then
    return true;
  end if;

  return v_profile.role = 'manager'
    and v_profile.branch_id = p_branch_id
    and coalesce('returns.approve' = any(v_permissions), false)
    and coalesce('pos.void' = any(v_permissions), false);
end;
$$;

drop policy if exists return_reasons_select_by_role on public.return_reasons;
create policy return_reasons_select_by_role
on public.return_reasons
for select
to authenticated
using (true);

drop policy if exists sales_returns_select_by_role on public.sales_returns;
create policy sales_returns_select_by_role
on public.sales_returns
for select
to authenticated
using (public.returns_user_can_view(branch_id));

drop policy if exists sales_return_items_select_by_role on public.sales_return_items;
create policy sales_return_items_select_by_role
on public.sales_return_items
for select
to authenticated
using (
  exists (
    select 1
    from public.sales_returns sr
    where sr.id = return_id
      and public.returns_user_can_view(sr.branch_id)
  )
);

drop policy if exists sales_return_batches_select_by_role on public.sales_return_batch_allocations;
create policy sales_return_batches_select_by_role
on public.sales_return_batch_allocations
for select
to authenticated
using (
  exists (
    select 1
    from public.sales_return_items sri
    join public.sales_returns sr on sr.id = sri.return_id
    where sri.id = return_item_id
      and public.returns_user_can_view(sr.branch_id)
  )
);

drop policy if exists credit_memos_select_by_role on public.credit_memos;
create policy credit_memos_select_by_role
on public.credit_memos
for select
to authenticated
using (public.returns_user_can_view(branch_id));

drop policy if exists sales_refunds_select_by_role on public.sales_refunds;
create policy sales_refunds_select_by_role
on public.sales_refunds
for select
to authenticated
using (public.returns_user_can_view(branch_id));

create or replace function public.returns_visible_branch_ids(p_profile public.user_profiles)
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

create or replace function public.returns_add_item(
  p_return_id uuid,
  p_order_item_id uuid,
  p_quantity integer,
  p_condition text default 'good',
  p_disposition text default 'return_to_stock',
  p_skip_stock_restore boolean default false,
  p_actor_id uuid default auth.uid()
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_return public.sales_returns;
  v_order_item public.sales_order_items;
  v_quantity integer := coalesce(p_quantity, 0);
  v_condition text := coalesce(nullif(p_condition, ''), 'good');
  v_disposition text := coalesce(nullif(p_disposition, ''), 'return_to_stock');
  v_previous_quantity integer := 0;
  v_returnable_quantity integer := 0;
  v_return_item_id uuid;
  v_remaining integer;
  v_take integer;
  v_allocation record;
  v_batch_id uuid;
  v_before_total integer;
  v_after_total integer;
  v_line_gross numeric(14, 2);
  v_line_discount numeric(14, 2);
  v_line_tax numeric(14, 2);
  v_line_net numeric(14, 2);
  v_unit_cost numeric(14, 2);
  v_generated_batch text;
begin
  select *
  into v_return
  from public.sales_returns
  where id = p_return_id;

  if v_return.id is null then
    raise exception 'Return record not found' using errcode = '02000';
  end if;

  select *
  into v_order_item
  from public.sales_order_items
  where id = p_order_item_id;

  if v_order_item.id is null or v_order_item.order_id <> v_return.original_order_id then
    raise exception 'Return item does not belong to the selected invoice' using errcode = '23514';
  end if;

  if v_condition not in ('good', 'damaged', 'expired', 'wrong_item', 'not_returnable') then
    raise exception 'Invalid return condition' using errcode = '22023';
  end if;

  if v_disposition not in ('return_to_stock', 'damaged', 'expired', 'write_off') then
    raise exception 'Invalid return disposition' using errcode = '22023';
  end if;

  select coalesce(sum(sri.quantity), 0)::integer
  into v_previous_quantity
  from public.sales_return_items sri
  join public.sales_returns sr on sr.id = sri.return_id
  where (sr.status = 'completed' or sr.id = p_return_id)
    and sri.order_item_id = p_order_item_id;

  v_returnable_quantity := v_order_item.quantity - v_previous_quantity;

  if v_quantity <= 0 then
    raise exception 'Return quantity must be greater than zero' using errcode = '23514';
  end if;

  if v_quantity > v_returnable_quantity then
    raise exception 'Return quantity exceeds remaining invoice quantity' using errcode = '23514';
  end if;

  v_line_gross := round(v_order_item.gross_amount * v_quantity / v_order_item.quantity, 2);
  v_line_discount := round(v_order_item.discount_amount * v_quantity / v_order_item.quantity, 2);
  v_line_tax := round(v_order_item.tax_amount * v_quantity / v_order_item.quantity, 2);
  v_line_net := round(v_order_item.net_amount * v_quantity / v_order_item.quantity, 2);

  insert into public.sales_return_items (
    return_id,
    order_item_id,
    product_id,
    product_variant_id,
    product_name,
    sku,
    barcode,
    variant_name,
    quantity,
    unit_price,
    gross_amount,
    discount_amount,
    tax_amount,
    net_amount,
    condition,
    disposition
  )
  values (
    p_return_id,
    p_order_item_id,
    v_order_item.product_id,
    v_order_item.product_variant_id,
    v_order_item.product_name,
    v_order_item.sku,
    v_order_item.barcode,
    v_order_item.variant_name,
    v_quantity,
    v_order_item.unit_price,
    v_line_gross,
    v_line_discount,
    v_line_tax,
    v_line_net,
    v_condition,
    v_disposition
  )
  returning id into v_return_item_id;

  v_remaining := v_quantity;

  for v_allocation in
    select
      alloc.*,
      coalesce((
        select sum(srba.quantity)
        from public.sales_return_batch_allocations srba
        join public.sales_return_items previous_item on previous_item.id = srba.return_item_id
        join public.sales_returns previous_return on previous_return.id = previous_item.return_id
        where (previous_return.status = 'completed' or previous_return.id = p_return_id)
          and srba.original_allocation_id = alloc.id
      ), 0)::integer as already_returned
    from public.sales_order_batch_allocations alloc
    where alloc.order_item_id = p_order_item_id
    order by alloc.expiry_date asc nulls last, alloc.created_at asc
  loop
    exit when v_remaining <= 0;

    v_take := least(v_remaining, greatest(v_allocation.quantity - v_allocation.already_returned, 0));
    if v_take <= 0 then
      continue;
    end if;

    v_batch_id := v_allocation.inventory_batch_id;
    v_unit_cost := coalesce(v_allocation.unit_cost, 0);

    insert into public.sales_return_batch_allocations (
      return_item_id,
      original_allocation_id,
      inventory_batch_id,
      batch_number,
      expiry_date,
      quantity,
      unit_cost
    )
    values (
      v_return_item_id,
      v_allocation.id,
      v_batch_id,
      v_allocation.batch_number,
      v_allocation.expiry_date,
      v_take,
      v_unit_cost
    );

    if v_disposition = 'return_to_stock' and p_skip_stock_restore = false then
      select coalesce(sum(quantity_on_hand), 0)::integer
      into v_before_total
      from public.inventory_batches
      where branch_id = v_return.branch_id
        and product_id = v_order_item.product_id
        and status = 'active';

      if v_batch_id is not null then
        update public.inventory_batches
        set quantity_on_hand = quantity_on_hand + v_take,
            status = 'active'
        where id = v_batch_id;
      end if;

      if v_batch_id is null or not found then
        v_generated_batch := coalesce(v_allocation.batch_number, 'RETURN-' || v_return.return_number);

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
          v_return.branch_id,
          v_order_item.product_id,
          v_order_item.product_variant_id,
          v_generated_batch,
          v_allocation.expiry_date,
          v_take,
          v_unit_cost,
          current_date,
          'active'
        )
        returning id into v_batch_id;

        update public.sales_return_batch_allocations
        set inventory_batch_id = v_batch_id
        where return_item_id = v_return_item_id
          and original_allocation_id = v_allocation.id;
      end if;

      v_after_total := v_before_total + v_take;

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
        v_return.branch_id,
        v_order_item.product_id,
        v_order_item.product_variant_id,
        v_batch_id,
        'adjustment_plus',
        v_take,
        v_before_total,
        v_after_total,
        v_unit_cost,
        v_allocation.batch_number,
        v_allocation.expiry_date,
        v_return.return_number,
        'Returned item restored to stock',
        p_actor_id
      );
    end if;

    v_remaining := v_remaining - v_take;
  end loop;

  if v_remaining > 0 then
    v_unit_cost := 0;
    v_batch_id := null;

    if v_disposition = 'return_to_stock' and p_skip_stock_restore = false then
      select coalesce(sum(quantity_on_hand), 0)::integer
      into v_before_total
      from public.inventory_batches
      where branch_id = v_return.branch_id
        and product_id = v_order_item.product_id
        and status = 'active';

      v_generated_batch := 'RETURN-' || v_return.return_number;

      insert into public.inventory_batches (
        branch_id,
        product_id,
        product_variant_id,
        batch_number,
        quantity_on_hand,
        unit_cost,
        received_at,
        status
      )
      values (
        v_return.branch_id,
        v_order_item.product_id,
        v_order_item.product_variant_id,
        v_generated_batch,
        v_remaining,
        v_unit_cost,
        current_date,
        'active'
      )
      returning id into v_batch_id;

      v_after_total := v_before_total + v_remaining;

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
        reference_number,
        reason,
        created_by
      )
      values (
        v_return.branch_id,
        v_order_item.product_id,
        v_order_item.product_variant_id,
        v_batch_id,
        'adjustment_plus',
        v_remaining,
        v_before_total,
        v_after_total,
        v_unit_cost,
        v_generated_batch,
        v_return.return_number,
        'Returned item restored to stock without original allocation',
        p_actor_id
      );
    end if;

    insert into public.sales_return_batch_allocations (
      return_item_id,
      inventory_batch_id,
      batch_number,
      quantity,
      unit_cost
    )
    values (
      v_return_item_id,
      v_batch_id,
      coalesce(v_generated_batch, 'UNALLOCATED'),
      v_remaining,
      v_unit_cost
    );
  end if;

  if v_disposition = 'return_to_stock' and p_skip_stock_restore = false then
    perform public.inventory_sync_product_stock(v_return.branch_id, v_order_item.product_id);
  end if;

  return jsonb_build_object(
    'return_item_id', v_return_item_id,
    'quantity', v_quantity,
    'gross_amount', v_line_gross,
    'discount_amount', v_line_discount,
    'tax_amount', v_line_tax,
    'net_amount', v_line_net
  );
end;
$$;

create or replace function public.returns_update_order_totals(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.sales_orders;
  v_returned_quantity integer := 0;
  v_order_quantity integer := 0;
  v_return_total numeric(14, 2) := 0;
begin
  select *
  into v_order
  from public.sales_orders
  where id = p_order_id
  for update;

  if v_order.id is null then
    return;
  end if;

  select coalesce(sum(quantity), 0)::integer
  into v_order_quantity
  from public.sales_order_items
  where order_id = p_order_id;

  select
    coalesce(sum(sri.quantity), 0)::integer,
    coalesce(sum(sri.net_amount), 0)::numeric(14, 2)
  into v_returned_quantity, v_return_total
  from public.sales_return_items sri
  join public.sales_returns sr on sr.id = sri.return_id
  where sr.original_order_id = p_order_id
    and sr.status = 'completed';

  update public.sales_orders
  set return_total = v_return_total,
      returned_item_count = v_returned_quantity,
      return_status = case
        when status = 'voided' then 'voided'
        when v_returned_quantity <= 0 then 'none'
        when v_order_quantity > 0 and v_returned_quantity >= v_order_quantity then 'full'
        else 'partial'
      end,
      payment_status = case
        when status = 'voided' then payment_status
        when v_order_quantity > 0 and v_returned_quantity >= v_order_quantity then 'refunded'
        when v_returned_quantity > 0 then 'partial'
        else payment_status
      end,
      status = case
        when status = 'voided' then status
        when v_order_quantity > 0 and v_returned_quantity >= v_order_quantity then 'refunded'
        else status
      end
  where id = p_order_id;

  if v_order_quantity > 0 and v_returned_quantity >= v_order_quantity then
    update public.sales_order_payments
    set status = 'refunded'
    where order_id = p_order_id;
  end if;
end;
$$;

create or replace function public.returns_process(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor public.user_profiles;
  v_order public.sales_orders;
  v_reason public.return_reasons;
  v_type text := coalesce(nullif(p_payload->>'return_type', ''), 'refund');
  v_reason_id uuid := nullif(p_payload->>'reason_id', '')::uuid;
  v_reason_note text := nullif(trim(coalesce(p_payload->>'reason_note', '')), '');
  v_refund_method text := nullif(trim(coalesce(p_payload->>'refund_method', '')), '');
  v_refund_reference text := nullif(trim(coalesce(p_payload->>'refund_reference', '')), '');
  v_notes text := nullif(trim(coalesce(p_payload->>'notes', '')), '');
  v_items jsonb := coalesce(p_payload->'items', '[]'::jsonb);
  v_item jsonb;
  v_item_result jsonb;
  v_return_id uuid;
  v_return_number text;
  v_credit_memo_number text;
  v_credit_memo_amount numeric(14, 2) := 0;
  v_refund_amount numeric(14, 2) := 0;
  v_total_return_amount numeric(14, 2) := 0;
  v_total_quantity integer := 0;
  v_order_item record;
  v_completed jsonb;
  v_branch_filter uuid;
  v_shift_id uuid;
  v_cash_register_id uuid;
begin
  v_actor := public.ensure_active_user();

  if v_type not in ('refund', 'exchange', 'credit_memo', 'void') then
    raise exception 'Invalid return type' using errcode = '22023';
  end if;

  select *
  into v_order
  from public.sales_orders
  where id = nullif(p_payload->>'original_order_id', '')::uuid
  for update;

  if v_order.id is null then
    raise exception 'Original invoice is required' using errcode = '23502';
  end if;

  if v_type = 'void' then
    if public.returns_user_can_void(v_order.branch_id) = false then
      raise exception 'Only admin or authorized branch manager can void invoices' using errcode = '42501';
    end if;
  elsif public.returns_user_can_manage(v_order.branch_id) = false then
    raise exception 'You cannot process returns for this branch' using errcode = '42501';
  end if;

  if v_order.status <> 'completed' then
    raise exception 'Only completed invoices can be returned, refunded, exchanged, or voided' using errcode = '23514';
  end if;

  if v_reason_id is not null then
    select *
    into v_reason
    from public.return_reasons
    where id = v_reason_id
      and is_active = true;
  end if;

  if v_reason.id is null then
    raise exception 'Return reason is required' using errcode = '23502';
  end if;

  if v_reason.requires_note and v_reason_note is null then
    raise exception 'Reason note is required for this return reason' using errcode = '23502';
  end if;

  if v_type = 'void' and exists (
    select 1
    from public.sales_returns
    where original_order_id = v_order.id
      and status = 'completed'
  ) then
    raise exception 'Invoice with existing returns cannot be voided' using errcode = '23514';
  end if;

  if v_type <> 'void' and jsonb_array_length(v_items) = 0 then
    raise exception 'At least one returned item is required' using errcode = '23502';
  end if;

  if v_type = 'refund' then
    v_refund_method := coalesce(v_refund_method, 'cash');
  elsif v_type in ('exchange', 'credit_memo') then
    v_refund_method := 'store_credit';
  else
    v_refund_method := coalesce(v_refund_method, 'cash');
  end if;

  if v_refund_method not in ('cash', 'card', 'gcash', 'maya', 'bank_transfer', 'store_credit', 'cod') then
    raise exception 'Invalid refund method' using errcode = '22023';
  end if;

  v_return_number := 'RET-' || to_char(now(), 'YYYYMMDD-HH24MISS-') || upper(left(replace(gen_random_uuid()::text, '-', ''), 5));

  insert into public.sales_returns (
    branch_id,
    original_order_id,
    return_number,
    return_type,
    customer_name,
    reason_id,
    reason_name,
    reason_note,
    refund_method,
    refund_reference,
    notes,
    requested_by,
    approved_by
  )
  values (
    v_order.branch_id,
    v_order.id,
    v_return_number,
    v_type,
    coalesce(nullif(p_payload->>'customer_name', ''), v_order.customer_name),
    v_reason.id,
    v_reason.name,
    v_reason_note,
    v_refund_method,
    v_refund_reference,
    v_notes,
    v_actor.id,
    case when v_actor.role in ('admin', 'manager') then v_actor.id else null end
  )
  returning id into v_return_id;

  if v_type = 'void' then
    for v_order_item in
      select
        soi.id,
        soi.quantity - coalesce((
          select sum(sri.quantity)
          from public.sales_return_items sri
          join public.sales_returns sr on sr.id = sri.return_id
          where sr.status = 'completed'
            and sri.order_item_id = soi.id
        ), 0)::integer as returnable_quantity
      from public.sales_order_items soi
      where soi.order_id = v_order.id
    loop
      if v_order_item.returnable_quantity > 0 then
        v_item_result := public.returns_add_item(
          v_return_id,
          v_order_item.id,
          v_order_item.returnable_quantity,
          'good',
          'return_to_stock',
          true,
          v_actor.id
        );
        v_total_return_amount := v_total_return_amount + (v_item_result->>'net_amount')::numeric;
        v_total_quantity := v_total_quantity + (v_item_result->>'quantity')::integer;
      end if;
    end loop;

    perform public.bir_void_invoice(v_order.id, coalesce(v_reason.name || ': ' || v_reason_note, v_reason.name));

    update public.sales_order_payments
    set status = 'void'
    where order_id = v_order.id;
  else
    for v_item in select value from jsonb_array_elements(v_items)
    loop
      v_item_result := public.returns_add_item(
        v_return_id,
        nullif(v_item->>'order_item_id', '')::uuid,
        coalesce(nullif(v_item->>'quantity', '')::integer, 0),
        coalesce(nullif(v_item->>'condition', ''), 'good'),
        coalesce(nullif(v_item->>'disposition', ''), 'return_to_stock'),
        false,
        v_actor.id
      );
      v_total_return_amount := v_total_return_amount + (v_item_result->>'net_amount')::numeric;
      v_total_quantity := v_total_quantity + (v_item_result->>'quantity')::integer;
    end loop;
  end if;

  if v_total_quantity <= 0 then
    raise exception 'No returnable items were selected' using errcode = '23514';
  end if;

  if v_type in ('exchange', 'credit_memo') or v_refund_method = 'store_credit' then
    v_credit_memo_amount := v_total_return_amount;
  elsif v_type = 'void' then
    v_refund_amount := v_order.total;
  else
    v_refund_amount := v_total_return_amount;
  end if;

  update public.sales_returns
  set status = 'completed',
      total_return_amount = v_total_return_amount,
      refund_amount = v_refund_amount,
      credit_memo_amount = v_credit_memo_amount,
      completed_by = v_actor.id,
      completed_at = now()
  where id = v_return_id;

  if v_refund_amount > 0 then
    insert into public.sales_refunds (
      return_id,
      branch_id,
      original_order_id,
      refund_method,
      amount,
      reference_number,
      processed_by,
      notes
    )
    values (
      v_return_id,
      v_order.branch_id,
      v_order.id,
      v_refund_method,
      v_refund_amount,
      v_refund_reference,
      v_actor.id,
      v_notes
    );

    if v_type <> 'void' and v_refund_method = 'cash' then
      select id, cash_register_id
      into v_shift_id, v_cash_register_id
      from public.cashier_shifts
      where branch_id = v_order.branch_id
        and user_id = v_actor.id
        and status = 'open'
      order by opened_at desc
      limit 1;

      if v_shift_id is null then
        raise exception 'Open a cashier shift before processing a cash refund' using errcode = '23514';
      end if;

      insert into public.cash_drawer_movements (
        branch_id,
        cash_register_id,
        shift_id,
        user_id,
        movement_type,
        direction,
        amount,
        reference_type,
        reference_id,
        reason
      )
      values (
        v_order.branch_id,
        v_cash_register_id,
        v_shift_id,
        v_actor.id,
        'cash_out',
        'out',
        v_refund_amount,
        'sales_return',
        v_return_id,
        'Cash refund for ' || v_return_number
      );

      perform public.shift_recalculate(v_shift_id);
    end if;
  end if;

  if v_credit_memo_amount > 0 then
    v_credit_memo_number := 'CM-' || to_char(now(), 'YYYYMMDD-HH24MISS-') || upper(left(replace(gen_random_uuid()::text, '-', ''), 5));

    insert into public.credit_memos (
      branch_id,
      return_id,
      original_order_id,
      credit_memo_number,
      customer_name,
      amount,
      available_amount,
      issued_by,
      expires_at,
      notes
    )
    values (
      v_order.branch_id,
      v_return_id,
      v_order.id,
      v_credit_memo_number,
      coalesce(nullif(p_payload->>'customer_name', ''), v_order.customer_name),
      v_credit_memo_amount,
      v_credit_memo_amount,
      v_actor.id,
      current_date + 365,
      v_notes
    );
  end if;

  perform public.returns_update_order_totals(v_order.id);

  perform public.log_activity(
    'returns.processed',
    'sales_return',
    v_return_id::text,
    jsonb_build_object(
      'return_number', v_return_number,
      'return_type', v_type,
      'original_order_id', v_order.id,
      'invoice_number', v_order.invoice_number,
      'total_return_amount', v_total_return_amount,
      'refund_amount', v_refund_amount,
      'credit_memo_amount', v_credit_memo_amount
    ),
    v_actor.id
  );

  v_branch_filter := case when v_actor.role in ('admin', 'auditor') then null else v_order.branch_id end;
  v_completed := public.returns_management_get(current_date - 29, current_date, coalesce(v_branch_filter, v_order.branch_id), null);

  return v_completed || jsonb_build_object('processed_return_id', v_return_id, 'processed_return_number', v_return_number);
end;
$$;

create or replace function public.returns_management_get(
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

  v_branch_ids := public.returns_visible_branch_ids(v_profile);

  with visible_branches as (
    select b.*
    from public.branches b
    where b.is_active = true
      and b.id = any(v_branch_ids)
      and (v_branch_filter is null or b.id = v_branch_filter)
  ),
  order_return_totals as (
    select
      sri.order_item_id,
      sum(sri.quantity)::integer as returned_quantity
    from public.sales_return_items sri
    join public.sales_returns sr on sr.id = sri.return_id
    where sr.status = 'completed'
    group by sri.order_item_id
  ),
  eligible_order_rows as (
    select
      so.id,
      so.order_number,
      so.invoice_number,
      so.business_date,
      so.created_at,
      so.customer_name,
      so.total,
      so.return_total,
      so.return_status,
      so.status,
      so.payment_method_summary,
      b.branch_code,
      b.name as branch_name,
      up.full_name as cashier_name,
      up.username as cashier_username,
      coalesce(items.returnable_quantity, 0)::integer as returnable_quantity,
      coalesce(items.items, '[]'::jsonb) as items,
      coalesce(payments.payments, '[]'::jsonb) as payments
    from public.sales_orders so
    join visible_branches b on b.id = so.branch_id
    left join public.user_profiles up on up.id = so.user_id
    left join lateral (
      select
        coalesce(sum(greatest(soi.quantity - coalesce(ort.returned_quantity, 0), 0)), 0)::integer as returnable_quantity,
        coalesce(jsonb_agg(
          jsonb_build_object(
            'id', soi.id,
            'product_id', soi.product_id,
            'product_variant_id', soi.product_variant_id,
            'product_name', soi.product_name,
            'sku', soi.sku,
            'barcode', soi.barcode,
            'variant_name', soi.variant_name,
            'quantity', soi.quantity,
            'unit_price', soi.unit_price,
            'gross_amount', soi.gross_amount,
            'discount_amount', soi.discount_amount,
            'tax_amount', soi.tax_amount,
            'net_amount', soi.net_amount,
            'returned_quantity', coalesce(ort.returned_quantity, 0),
            'returnable_quantity', greatest(soi.quantity - coalesce(ort.returned_quantity, 0), 0)
          )
          order by soi.created_at asc
        ) filter (where greatest(soi.quantity - coalesce(ort.returned_quantity, 0), 0) > 0), '[]'::jsonb) as items
      from public.sales_order_items soi
      left join order_return_totals ort on ort.order_item_id = soi.id
      where soi.order_id = so.id
    ) items on true
    left join lateral (
      select jsonb_agg(
        jsonb_build_object(
          'id', sop.id,
          'method', sop.method,
          'method_label', coalesce(sop.method_label, initcap(replace(sop.method, '_', ' '))),
          'amount', sop.amount,
          'status', sop.status,
          'reference_number', sop.reference_number
        )
        order by sop.created_at asc
      ) as payments
      from public.sales_order_payments sop
      where sop.order_id = so.id
    ) payments on true
    where so.status = 'completed'
      and coalesce(items.returnable_quantity, 0) > 0
      and (
        v_search = ''
        or lower(coalesce(so.invoice_number, '')) like '%' || v_search || '%'
        or lower(coalesce(so.order_number, '')) like '%' || v_search || '%'
        or lower(coalesce(so.customer_name, '')) like '%' || v_search || '%'
      )
    order by so.created_at desc
    limit 80
  ),
  return_rows as (
    select
      sr.id,
      sr.return_number,
      sr.return_type,
      sr.status,
      sr.customer_name,
      sr.reason_name,
      sr.reason_note,
      sr.refund_method,
      sr.refund_reference,
      sr.total_return_amount,
      sr.refund_amount,
      sr.credit_memo_amount,
      sr.notes,
      sr.completed_at,
      sr.created_at,
      so.id as original_order_id,
      so.order_number,
      so.invoice_number,
      so.business_date,
      b.branch_code,
      b.name as branch_name,
      requester.full_name as requested_by_name,
      completer.full_name as completed_by_name,
      cm.credit_memo_number,
      cm.status as credit_memo_status,
      coalesce(items.items, '[]'::jsonb) as items,
      coalesce(refunds.refunds, '[]'::jsonb) as refunds
    from public.sales_returns sr
    join visible_branches b on b.id = sr.branch_id
    join public.sales_orders so on so.id = sr.original_order_id
    left join public.user_profiles requester on requester.id = sr.requested_by
    left join public.user_profiles completer on completer.id = sr.completed_by
    left join public.credit_memos cm on cm.return_id = sr.id
    left join lateral (
      select jsonb_agg(to_jsonb(sri) order by sri.created_at asc) as items
      from public.sales_return_items sri
      where sri.return_id = sr.id
    ) items on true
    left join lateral (
      select jsonb_agg(to_jsonb(sf) order by sf.processed_at asc) as refunds
      from public.sales_refunds sf
      where sf.return_id = sr.id
    ) refunds on true
    where sr.created_at::date >= v_from
      and sr.created_at::date <= v_to
      and (
        v_search = ''
        or lower(sr.return_number) like '%' || v_search || '%'
        or lower(coalesce(so.invoice_number, '')) like '%' || v_search || '%'
        or lower(coalesce(so.order_number, '')) like '%' || v_search || '%'
        or lower(coalesce(sr.customer_name, '')) like '%' || v_search || '%'
      )
  ),
  credit_memo_rows as (
    select
      cm.*,
      b.branch_code,
      b.name as branch_name,
      so.invoice_number,
      sr.return_number,
      issuer.full_name as issued_by_name
    from public.credit_memos cm
    join visible_branches b on b.id = cm.branch_id
    join public.sales_orders so on so.id = cm.original_order_id
    join public.sales_returns sr on sr.id = cm.return_id
    left join public.user_profiles issuer on issuer.id = cm.issued_by
    where cm.issued_at::date >= v_from
      and cm.issued_at::date <= v_to
  ),
  daily_returns as (
    select
      d.day::date as business_date,
      to_char(d.day::date, 'Mon DD') as label,
      coalesce(count(rr.id), 0)::integer as returns,
      coalesce(sum(rr.total_return_amount), 0)::numeric(14, 2) as return_amount,
      coalesce(sum(rr.refund_amount), 0)::numeric(14, 2) as refund_amount,
      coalesce(sum(rr.credit_memo_amount), 0)::numeric(14, 2) as credit_memo_amount
    from generate_series(v_from, v_to, interval '1 day') d(day)
    left join return_rows rr on rr.created_at::date = d.day::date
    group by d.day
  ),
  branch_summary as (
    select
      vb.id as branch_id,
      vb.branch_code,
      vb.name as branch_name,
      coalesce(count(rr.id), 0)::integer as returns,
      coalesce(sum(rr.total_return_amount), 0)::numeric(14, 2) as return_amount,
      coalesce(sum(rr.refund_amount), 0)::numeric(14, 2) as refund_amount,
      coalesce(sum(rr.credit_memo_amount), 0)::numeric(14, 2) as credit_memo_amount,
      coalesce(count(rr.id) filter (where rr.return_type = 'void'), 0)::integer as void_count
    from visible_branches vb
    left join return_rows rr on rr.branch_code = vb.branch_code
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
    'reasons', coalesce((
      select jsonb_agg(to_jsonb(rr) order by rr.sort_order, rr.name)
      from public.return_reasons rr
      where rr.is_active = true
    ), '[]'::jsonb),
    'summary', jsonb_build_object(
      'return_count', coalesce((select count(*) from return_rows), 0),
      'void_count', coalesce((select count(*) from return_rows where return_type = 'void'), 0),
      'refund_count', coalesce((select count(*) from return_rows where refund_amount > 0), 0),
      'credit_memo_count', coalesce((select count(*) from credit_memo_rows), 0),
      'total_return_amount', coalesce((select sum(total_return_amount) from return_rows), 0),
      'refund_amount', coalesce((select sum(refund_amount) from return_rows), 0),
      'credit_memo_amount', coalesce((select sum(credit_memo_amount) from return_rows), 0),
      'open_credit_memo_amount', coalesce((select sum(available_amount) from credit_memo_rows where status = 'open'), 0),
      'returned_quantity', coalesce((
        select sum((item->>'quantity')::integer)
        from return_rows rr,
        lateral jsonb_array_elements(rr.items) item
      ), 0)
    ),
    'eligible_orders', coalesce((select jsonb_agg(to_jsonb(eligible_order_rows) order by created_at desc) from eligible_order_rows), '[]'::jsonb),
    'returns', coalesce((select jsonb_agg(to_jsonb(return_rows) order by created_at desc) from return_rows), '[]'::jsonb),
    'credit_memos', coalesce((select jsonb_agg(to_jsonb(credit_memo_rows) order by issued_at desc) from credit_memo_rows), '[]'::jsonb),
    'daily_returns', coalesce((select jsonb_agg(to_jsonb(daily_returns) order by business_date) from daily_returns), '[]'::jsonb),
    'branch_summary', coalesce((select jsonb_agg(to_jsonb(branch_summary) order by return_amount desc, branch_name) from branch_summary), '[]'::jsonb),
    'can_manage_returns', case
      when v_branch_filter is not null then public.returns_user_can_manage(v_branch_filter)
      when v_profile.role in ('admin', 'manager', 'cashier') then true
      else false
    end,
    'can_void_returns', case
      when v_branch_filter is not null then public.returns_user_can_void(v_branch_filter)
      when v_profile.role = 'admin' then true
      else false
    end,
    'generated_at', now()
  )
  into v_result;

  return v_result;
end;
$$;

revoke all on function public.returns_effective_permissions(uuid, text) from public;
revoke all on function public.returns_user_can_view(uuid) from public;
revoke all on function public.returns_user_can_manage(uuid) from public;
revoke all on function public.returns_user_can_void(uuid) from public;
revoke all on function public.returns_visible_branch_ids(public.user_profiles) from public;
revoke all on function public.returns_add_item(uuid, uuid, integer, text, text, boolean, uuid) from public;
revoke all on function public.returns_update_order_totals(uuid) from public;
revoke all on function public.returns_process(jsonb) from public;
revoke all on function public.returns_management_get(date, date, uuid, text) from public;

grant execute on function public.returns_process(jsonb) to authenticated;
grant execute on function public.returns_management_get(date, date, uuid, text) to authenticated;

notify pgrst, 'reload schema';
