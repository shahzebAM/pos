-- MODULE 7: POS SALES / CHECKOUT
-- Run after:
-- 1. supabase/00-reset-public-schema.sql
-- 2. supabase/01-dashboard-module.sql
-- 3. supabase/02-auth-and-branch-management.sql
-- 4. supabase/03-user-role-management.sql
-- 5. supabase/04-product-management.sql
-- 6. supabase/05-inventory-management.sql
-- 7. supabase/06-stock-transfer.sql
--
-- Scope:
-- - Barcode/product search checkout
-- - Discounts with permission/max-percent checks
-- - VAT calculation using product tax tagging
-- - Multiple and split payment methods
-- - Invoice/receipt detail persistence
-- - FEFO stock reduction from inventory batches
-- - Recent sales detail for reprint/history

create extension if not exists pgcrypto;

alter table public.cashiers
  add column if not exists user_id uuid references public.user_profiles(id) on delete set null;

create unique index if not exists idx_cashiers_user_id
on public.cashiers(user_id)
where user_id is not null;

alter table public.sales_orders
  add column if not exists user_id uuid references public.user_profiles(id) on delete set null,
  add column if not exists customer_name text,
  add column if not exists invoice_number text,
  add column if not exists payment_status text not null default 'paid',
  add column if not exists payment_method_summary text,
  add column if not exists vatable_sales numeric(14, 2) not null default 0,
  add column if not exists vat_exempt_sales numeric(14, 2) not null default 0,
  add column if not exists zero_rated_sales numeric(14, 2) not null default 0,
  add column if not exists non_vat_sales numeric(14, 2) not null default 0,
  add column if not exists net_sales numeric(14, 2) not null default 0,
  add column if not exists amount_tendered numeric(14, 2) not null default 0,
  add column if not exists change_due numeric(14, 2) not null default 0,
  add column if not exists source text not null default 'online',
  add column if not exists offline_reference text,
  add column if not exists notes text;

create unique index if not exists idx_sales_orders_invoice_number
on public.sales_orders(invoice_number)
where invoice_number is not null;

create unique index if not exists idx_sales_orders_offline_reference
on public.sales_orders(offline_reference)
where offline_reference is not null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'sales_orders_payment_status_check'
      and conrelid = 'public.sales_orders'::regclass
  ) then
    alter table public.sales_orders
      add constraint sales_orders_payment_status_check
      check (payment_status in ('paid', 'partial', 'unpaid', 'refunded'));
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'sales_orders_source_check'
      and conrelid = 'public.sales_orders'::regclass
  ) then
    alter table public.sales_orders
      add constraint sales_orders_source_check
      check (source in ('online', 'offline'));
  end if;
end;
$$;

create table if not exists public.sales_order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.sales_orders(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict,
  product_variant_id uuid references public.product_variants(id) on delete set null,
  product_name text not null,
  sku text,
  barcode text,
  variant_name text,
  quantity integer not null check (quantity > 0),
  unit_price numeric(14, 2) not null check (unit_price >= 0),
  gross_amount numeric(14, 2) not null default 0 check (gross_amount >= 0),
  discount_amount numeric(14, 2) not null default 0 check (discount_amount >= 0),
  tax_type text not null default 'vatable' check (tax_type in ('vatable', 'vat_exempt', 'zero_rated', 'non_vat')),
  tax_rate numeric(5, 2) not null default 0 check (tax_rate >= 0 and tax_rate <= 100),
  tax_inclusive boolean not null default true,
  tax_amount numeric(14, 2) not null default 0 check (tax_amount >= 0),
  net_amount numeric(14, 2) not null default 0 check (net_amount >= 0),
  created_at timestamptz not null default now()
);

create table if not exists public.sales_order_payments (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.sales_orders(id) on delete cascade,
  method text not null check (method in ('cash', 'card', 'gcash', 'maya', 'bank_transfer', 'store_credit', 'cod')),
  amount numeric(14, 2) not null check (amount > 0),
  reference_number text,
  created_at timestamptz not null default now()
);

create table if not exists public.sales_order_batch_allocations (
  id uuid primary key default gen_random_uuid(),
  order_item_id uuid not null references public.sales_order_items(id) on delete cascade,
  inventory_batch_id uuid references public.inventory_batches(id) on delete set null,
  batch_number text,
  expiry_date date,
  quantity integer not null check (quantity > 0),
  unit_cost numeric(14, 2) not null default 0 check (unit_cost >= 0),
  created_at timestamptz not null default now()
);

create index if not exists idx_sales_orders_user_created on public.sales_orders(user_id, created_at desc);
create index if not exists idx_sales_orders_branch_created on public.sales_orders(branch_id, created_at desc);
create index if not exists idx_sales_order_items_order on public.sales_order_items(order_id);
create index if not exists idx_sales_order_items_product on public.sales_order_items(product_id);
create index if not exists idx_sales_order_payments_order on public.sales_order_payments(order_id);
create index if not exists idx_sales_order_batch_allocations_item on public.sales_order_batch_allocations(order_item_id);

alter table public.sales_order_items enable row level security;
alter table public.sales_order_payments enable row level security;
alter table public.sales_order_batch_allocations enable row level security;

drop policy if exists sales_orders_select_by_role on public.sales_orders;
create policy sales_orders_select_by_role
on public.sales_orders
for select
to authenticated
using (
  public.current_user_is_admin()
  or public.current_user_role() = 'auditor'
  or (public.current_user_role() = 'manager' and branch_id = public.current_user_branch_id())
  or (public.current_user_role() = 'cashier' and user_id = auth.uid())
);

drop policy if exists sales_order_items_select_by_role on public.sales_order_items;
create policy sales_order_items_select_by_role
on public.sales_order_items
for select
to authenticated
using (
  exists (
    select 1
    from public.sales_orders so
    where so.id = order_id
      and (
        public.current_user_is_admin()
        or public.current_user_role() = 'auditor'
        or (public.current_user_role() = 'manager' and so.branch_id = public.current_user_branch_id())
        or (public.current_user_role() = 'cashier' and so.user_id = auth.uid())
      )
  )
);

drop policy if exists sales_order_payments_select_by_role on public.sales_order_payments;
create policy sales_order_payments_select_by_role
on public.sales_order_payments
for select
to authenticated
using (
  exists (
    select 1
    from public.sales_orders so
    where so.id = order_id
      and (
        public.current_user_is_admin()
        or public.current_user_role() = 'auditor'
        or (public.current_user_role() = 'manager' and so.branch_id = public.current_user_branch_id())
        or (public.current_user_role() = 'cashier' and so.user_id = auth.uid())
      )
  )
);

drop policy if exists sales_order_batch_allocations_select_by_role on public.sales_order_batch_allocations;
create policy sales_order_batch_allocations_select_by_role
on public.sales_order_batch_allocations
for select
to authenticated
using (
  exists (
    select 1
    from public.sales_order_items soi
    join public.sales_orders so on so.id = soi.order_id
    where soi.id = order_item_id
      and (
        public.current_user_is_admin()
        or public.current_user_role() = 'auditor'
        or (public.current_user_role() = 'manager' and so.branch_id = public.current_user_branch_id())
        or (public.current_user_role() = 'cashier' and so.user_id = auth.uid())
      )
  )
);

create or replace function public.pos_user_can_sell(p_branch_id uuid)
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

  select permissions
  into v_permissions
  from public.user_access_settings
  where user_id = v_profile.id;

  if not coalesce('pos.sell' = any(v_permissions), false) and v_profile.role <> 'admin' then
    return false;
  end if;

  if v_profile.role = 'admin' then
    return true;
  end if;

  if v_profile.role in ('manager', 'cashier') and v_profile.branch_id = p_branch_id then
    return true;
  end if;

  return false;
end;
$$;

create or replace function public.pos_user_can_discount(p_discount_percent numeric)
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

  if coalesce(p_discount_percent, 0) <= 0 then
    return true;
  end if;

  if v_profile.role = 'admin' then
    return true;
  end if;

  select *
  into v_access
  from public.user_access_settings
  where user_id = v_profile.id;

  if not coalesce('pos.discount' = any(v_access.permissions), false) then
    return false;
  end if;

  return p_discount_percent <= coalesce(v_access.max_discount_percent, 0);
end;
$$;

create or replace function public.pos_ensure_cashier(p_user_id uuid, p_branch_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.user_profiles;
  v_cashier_id uuid;
  v_employee_code text;
begin
  select *
  into v_profile
  from public.user_profiles
  where id = p_user_id
  limit 1;

  if v_profile.id is null then
    return null;
  end if;

  select id
  into v_cashier_id
  from public.cashiers
  where user_id = p_user_id
  limit 1;

  if v_cashier_id is not null then
    update public.cashiers
    set branch_id = p_branch_id,
        name = v_profile.full_name,
        is_active = true
    where id = v_cashier_id;

    return v_cashier_id;
  end if;

  v_employee_code := 'U-' || upper(left(replace(p_user_id::text, '-', ''), 10));

  insert into public.cashiers (branch_id, employee_code, name, is_active, user_id)
  values (p_branch_id, v_employee_code, v_profile.full_name, true, p_user_id)
  returning id into v_cashier_id;

  return v_cashier_id;
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
      p.tax_type,
      p.vat_rate,
      p.tax_inclusive,
      p.selling_price,
      p.cost_price,
      coalesce(bi.quantity_on_hand, 0)::integer as quantity_on_hand,
      coalesce(variants.variants, '[]'::jsonb) as variants
    from public.products p
    left join public.product_categories pc on pc.id = p.category_id
    left join public.product_brands pb on pb.id = p.brand_id
    left join public.branch_inventory bi on bi.product_id = p.id and bi.branch_id = v_effective_branch_id
    left join lateral (
      select jsonb_agg(
        jsonb_build_object(
          'id', pv.id,
          'variant_name', pv.variant_name,
          'sku', pv.sku,
          'barcode', pv.barcode,
          'selling_price', pv.selling_price,
          'cost_price', pv.cost_price,
          'quantity_on_hand', coalesce(stock.quantity_on_hand, 0)
        )
        order by pv.variant_name
      ) as variants
      from public.product_variants pv
      left join lateral (
        select coalesce(sum(ib.quantity_on_hand), 0)::integer as quantity_on_hand
        from public.inventory_batches ib
        where ib.branch_id = v_effective_branch_id
          and ib.product_id = p.id
          and ib.product_variant_id = pv.id
          and ib.status = 'active'
      ) stock on true
      where pv.product_id = p.id
        and pv.deleted_at is null
        and pv.is_active = true
    ) variants on true
    where p.deleted_at is null
      and p.is_active = true
    order by p.name asc
  ),
  todays_orders as (
    select so.*
    from public.sales_orders so
    where so.branch_id = v_effective_branch_id
      and so.business_date = current_date
      and so.status = 'completed'
  ),
  visible_recent_orders as (
    select so.*
    from public.sales_orders so
    where so.branch_id = v_effective_branch_id
      and (
        v_profile.role in ('admin', 'manager')
        or so.user_id = v_profile.id
      )
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
    from visible_recent_orders so
    left join public.user_profiles up on up.id = so.user_id
    left join lateral (
      select jsonb_agg(
        jsonb_build_object(
          'id', soi.id,
          'product_id', soi.product_id,
          'product_variant_id', soi.product_variant_id,
          'product_name', soi.product_name,
          'variant_name', soi.variant_name,
          'sku', soi.sku,
          'barcode', soi.barcode,
          'quantity', soi.quantity,
          'unit_price', soi.unit_price,
          'gross_amount', soi.gross_amount,
          'discount_amount', soi.discount_amount,
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
          'amount', sop.amount,
          'reference_number', sop.reference_number
        )
        order by sop.created_at asc
      ) as payments
      from public.sales_order_payments sop
      where sop.order_id = so.id
    ) payments on true
  )
  select jsonb_build_object(
    'branch', (select to_jsonb(active_branch) from active_branch limit 1),
    'branches', coalesce((select jsonb_agg(to_jsonb(branch_options)) from branch_options), '[]'::jsonb),
    'products', coalesce((select jsonb_agg(to_jsonb(product_rows)) from product_rows), '[]'::jsonb),
    'recent_orders', coalesce((select jsonb_agg(to_jsonb(recent_order_rows)) from recent_order_rows), '[]'::jsonb),
    'summary', jsonb_build_object(
      'today_orders', coalesce((select count(*) from todays_orders), 0),
      'today_sales', coalesce((select sum(total) from todays_orders), 0),
      'today_tax', coalesce((select sum(tax_total) from todays_orders), 0),
      'today_discounts', coalesce((select sum(discount_total) from todays_orders), 0),
      'items_available', coalesce((select count(*) from product_rows where quantity_on_hand > 0), 0)
    ),
    'payment_methods', jsonb_build_array(
      jsonb_build_object('label', 'Cash', 'value', 'cash'),
      jsonb_build_object('label', 'Credit/debit card', 'value', 'card'),
      jsonb_build_object('label', 'GCash', 'value', 'gcash'),
      jsonb_build_object('label', 'Maya', 'value', 'maya'),
      jsonb_build_object('label', 'Bank transfer', 'value', 'bank_transfer'),
      jsonb_build_object('label', 'Store credit', 'value', 'store_credit'),
      jsonb_build_object('label', 'COD', 'value', 'cod')
    ),
    'generated_at', now()
  )
  into v_result;

  return v_result;
end;
$$;

create or replace function public.pos_checkout(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor public.user_profiles;
  v_branch_id uuid := nullif(p_payload->>'branch_id', '')::uuid;
  v_customer_name text := nullif(trim(coalesce(p_payload->>'customer_name', '')), '');
  v_source text := coalesce(nullif(p_payload->>'source', ''), 'online');
  v_offline_reference text := nullif(trim(coalesce(p_payload->>'offline_reference', '')), '');
  v_notes text := nullif(trim(coalesce(p_payload->>'notes', '')), '');
  v_items jsonb := p_payload->'items';
  v_payments jsonb := p_payload->'payments';
  v_item jsonb;
  v_payment jsonb;
  v_product public.products;
  v_variant public.product_variants;
  v_product_id uuid;
  v_variant_id uuid;
  v_quantity integer;
  v_unit_price numeric(14, 2);
  v_available integer;
  v_line_no integer := 0;
  v_subtotal numeric(14, 2) := 0;
  v_discount_type text := coalesce(nullif(p_payload->>'discount_type', ''), 'none');
  v_discount_value numeric(14, 2) := coalesce(nullif(p_payload->>'discount_value', '')::numeric, 0);
  v_discount_total numeric(14, 2) := 0;
  v_discount_percent numeric(8, 4) := 0;
  v_tax_total numeric(14, 2) := 0;
  v_total numeric(14, 2) := 0;
  v_vatable_sales numeric(14, 2) := 0;
  v_vat_exempt_sales numeric(14, 2) := 0;
  v_zero_rated_sales numeric(14, 2) := 0;
  v_non_vat_sales numeric(14, 2) := 0;
  v_net_sales numeric(14, 2) := 0;
  v_payment_total numeric(14, 2) := 0;
  v_change_due numeric(14, 2) := 0;
  v_has_cash boolean := false;
  v_order_id uuid;
  v_order_number text;
  v_invoice_number text;
  v_cashier_id uuid;
  v_order_item_id uuid;
  v_line record;
  v_batch record;
  v_remaining integer;
  v_take integer;
  v_before_total integer;
  v_after_total integer;
  v_method text;
  v_payment_summary text;
begin
  v_actor := public.ensure_active_user();

  if v_source not in ('online', 'offline') then
    raise exception 'Invalid sale source' using errcode = '22023';
  end if;

  if v_branch_id is null then
    v_branch_id := v_actor.branch_id;
  end if;

  if v_branch_id is null then
    raise exception 'Branch is required for POS checkout' using errcode = '23502';
  end if;

  if public.pos_user_can_sell(v_branch_id) = false then
    raise exception 'You cannot complete sales for this branch' using errcode = '42501';
  end if;

  if not exists (select 1 from public.branches where id = v_branch_id and is_active = true) then
    raise exception 'Branch not found or inactive' using errcode = '02000';
  end if;

  if v_items is null or jsonb_typeof(v_items) <> 'array' or jsonb_array_length(v_items) = 0 then
    raise exception 'Cart is empty' using errcode = '23502';
  end if;

  if v_payments is null or jsonb_typeof(v_payments) <> 'array' or jsonb_array_length(v_payments) = 0 then
    raise exception 'At least one payment is required' using errcode = '23502';
  end if;

  if v_offline_reference is not null and exists (
    select 1 from public.sales_orders where offline_reference = v_offline_reference
  ) then
    select id
    into v_order_id
    from public.sales_orders
    where offline_reference = v_offline_reference
    limit 1;

    return jsonb_build_object(
      'pos', public.pos_management_get(v_branch_id),
      'order', (
        select to_jsonb(row)
        from (
          select
            so.id,
            so.order_number,
            so.invoice_number,
            so.business_date,
            so.customer_name,
            so.subtotal,
            so.discount_total,
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
            coalesce((
              select jsonb_agg(to_jsonb(soi) order by soi.created_at asc)
              from public.sales_order_items soi
              where soi.order_id = so.id
            ), '[]'::jsonb) as items,
            coalesce((
              select jsonb_agg(to_jsonb(sop) order by sop.created_at asc)
              from public.sales_order_payments sop
              where sop.order_id = so.id
            ), '[]'::jsonb) as payments
          from public.sales_orders so
          left join public.user_profiles up on up.id = so.user_id
          where so.id = v_order_id
        ) row
      )
    );
  end if;

  drop table if exists pg_temp.pos_checkout_lines;
  create temporary table pos_checkout_lines (
    line_no integer primary key,
    product_id uuid not null,
    product_variant_id uuid,
    product_name text not null,
    sku text,
    barcode text,
    variant_name text,
    quantity integer not null,
    unit_price numeric(14, 2) not null,
    gross_amount numeric(14, 2) not null,
    discount_amount numeric(14, 2) not null default 0,
    tax_type text not null,
    tax_rate numeric(5, 2) not null,
    tax_inclusive boolean not null,
    tax_amount numeric(14, 2) not null default 0,
    net_amount numeric(14, 2) not null default 0,
    vatable_sales numeric(14, 2) not null default 0,
    vat_exempt_sales numeric(14, 2) not null default 0,
    zero_rated_sales numeric(14, 2) not null default 0,
    non_vat_sales numeric(14, 2) not null default 0,
    order_item_id uuid
  ) on commit drop;

  for v_item in select value from jsonb_array_elements(v_items)
  loop
    v_product_id := nullif(v_item->>'product_id', '')::uuid;
    v_variant_id := nullif(v_item->>'product_variant_id', '')::uuid;
    v_quantity := coalesce(nullif(v_item->>'quantity', '')::integer, 0);

    if v_product_id is null or v_quantity <= 0 then
      raise exception 'Each cart item must have product and quantity' using errcode = '23502';
    end if;

    select *
    into v_product
    from public.products
    where id = v_product_id
      and deleted_at is null
      and is_active = true
    limit 1;

    if v_product.id is null then
      raise exception 'Product not found or inactive' using errcode = '02000';
    end if;

    v_variant := null::public.product_variants;
    v_unit_price := v_product.selling_price;

    if v_variant_id is not null then
      select *
      into v_variant
      from public.product_variants
      where id = v_variant_id
        and product_id = v_product_id
        and deleted_at is null
        and is_active = true
      limit 1;

      if v_variant.id is null then
        raise exception 'Variant does not belong to this product' using errcode = '23514';
      end if;

      v_unit_price := v_variant.selling_price;
    end if;

    if exists (
      select 1
      from pg_temp.pos_checkout_lines
      where product_id = v_product_id
        and coalesce(product_variant_id, '00000000-0000-0000-0000-000000000000'::uuid) =
            coalesce(v_variant_id, '00000000-0000-0000-0000-000000000000'::uuid)
    ) then
      update pg_temp.pos_checkout_lines
      set quantity = quantity + v_quantity,
          gross_amount = round((quantity + v_quantity) * unit_price, 2)
      where product_id = v_product_id
        and coalesce(product_variant_id, '00000000-0000-0000-0000-000000000000'::uuid) =
            coalesce(v_variant_id, '00000000-0000-0000-0000-000000000000'::uuid);
    else
      v_line_no := v_line_no + 1;

      insert into pg_temp.pos_checkout_lines (
        line_no,
        product_id,
        product_variant_id,
        product_name,
        sku,
        barcode,
        variant_name,
        quantity,
        unit_price,
        gross_amount,
        tax_type,
        tax_rate,
        tax_inclusive
      )
      values (
        v_line_no,
        v_product_id,
        v_variant_id,
        v_product.name,
        coalesce(v_variant.sku, v_product.sku),
        coalesce(v_variant.barcode, v_product.barcode),
        v_variant.variant_name,
        v_quantity,
        v_unit_price,
        round(v_quantity * v_unit_price, 2),
        v_product.tax_type,
        case when v_product.tax_type = 'vatable' then coalesce(v_product.vat_rate, 12) else 0 end,
        coalesce(v_product.tax_inclusive, true)
      );
    end if;
  end loop;

  for v_line in select * from pg_temp.pos_checkout_lines
  loop
    select coalesce(sum(quantity_on_hand), 0)::integer
    into v_available
    from public.inventory_batches
    where branch_id = v_branch_id
      and product_id = v_line.product_id
      and (v_line.product_variant_id is null or product_variant_id = v_line.product_variant_id)
      and status = 'active';

    if v_available < v_line.quantity then
      raise exception 'Insufficient stock for %. Available %, required %',
        v_line.product_name, v_available, v_line.quantity
        using errcode = '23514';
    end if;
  end loop;

  select coalesce(sum(gross_amount), 0)::numeric(14, 2)
  into v_subtotal
  from pg_temp.pos_checkout_lines;

  if v_subtotal <= 0 then
    raise exception 'Sale total must be greater than zero' using errcode = '23514';
  end if;

  if v_discount_type not in ('none', 'percent', 'amount') then
    raise exception 'Invalid discount type' using errcode = '22023';
  end if;

  if v_discount_type = 'percent' then
    if v_discount_value < 0 or v_discount_value > 100 then
      raise exception 'Discount percent must be between 0 and 100' using errcode = '23514';
    end if;

    v_discount_total := round(v_subtotal * (v_discount_value / 100), 2);
    v_discount_percent := v_discount_value;
  elsif v_discount_type = 'amount' then
    if v_discount_value < 0 or v_discount_value > v_subtotal then
      raise exception 'Discount amount cannot exceed subtotal' using errcode = '23514';
    end if;

    v_discount_total := round(v_discount_value, 2);
    v_discount_percent := case when v_subtotal = 0 then 0 else round((v_discount_total / v_subtotal) * 100, 4) end;
  end if;

  if public.pos_user_can_discount(v_discount_percent) = false then
    raise exception 'Discount exceeds this user''s permission limit' using errcode = '42501';
  end if;

  with rounded as (
    select
      line_no,
      round((gross_amount / v_subtotal) * v_discount_total, 2) as line_discount
    from pg_temp.pos_checkout_lines
  ),
  prepared as (
    select
      r.*,
      row_number() over (order by r.line_no desc) = 1 as is_last,
      sum(r.line_discount) over () as rounded_total
    from rounded r
  )
  update pg_temp.pos_checkout_lines l
  set discount_amount = case
      when p.is_last then greatest(0, p.line_discount + (v_discount_total - p.rounded_total))
      else greatest(0, p.line_discount)
    end
  from prepared p
  where p.line_no = l.line_no;

  with calc as (
    select
      line_no,
      greatest(gross_amount - discount_amount, 0)::numeric(14, 2) as sale_amount,
      tax_type,
      tax_rate,
      tax_inclusive
    from pg_temp.pos_checkout_lines
  ),
  taxes as (
    select
      line_no,
      sale_amount,
      case
        when tax_type = 'vatable' and tax_inclusive then round(sale_amount - (sale_amount / (1 + (tax_rate / 100))), 2)
        when tax_type = 'vatable' and tax_inclusive = false then round(sale_amount * (tax_rate / 100), 2)
        else 0
      end as tax_amount,
      case
        when tax_type = 'vatable' and tax_inclusive then sale_amount
        when tax_type = 'vatable' and tax_inclusive = false then round(sale_amount + (sale_amount * (tax_rate / 100)), 2)
        else sale_amount
      end as net_amount,
      case
        when tax_type = 'vatable' and tax_inclusive then round(sale_amount / (1 + (tax_rate / 100)), 2)
        when tax_type = 'vatable' and tax_inclusive = false then sale_amount
        else 0
      end as vatable_sales,
      case when tax_type = 'vat_exempt' then sale_amount else 0 end as vat_exempt_sales,
      case when tax_type = 'zero_rated' then sale_amount else 0 end as zero_rated_sales,
      case when tax_type = 'non_vat' then sale_amount else 0 end as non_vat_sales
    from calc
  )
  update pg_temp.pos_checkout_lines l
  set tax_amount = t.tax_amount,
      net_amount = t.net_amount,
      vatable_sales = t.vatable_sales,
      vat_exempt_sales = t.vat_exempt_sales,
      zero_rated_sales = t.zero_rated_sales,
      non_vat_sales = t.non_vat_sales
  from taxes t
  where t.line_no = l.line_no;

  select
    coalesce(sum(tax_amount), 0),
    coalesce(sum(net_amount), 0),
    coalesce(sum(vatable_sales), 0),
    coalesce(sum(vat_exempt_sales), 0),
    coalesce(sum(zero_rated_sales), 0),
    coalesce(sum(non_vat_sales), 0)
  into
    v_tax_total,
    v_total,
    v_vatable_sales,
    v_vat_exempt_sales,
    v_zero_rated_sales,
    v_non_vat_sales
  from pg_temp.pos_checkout_lines;

  v_net_sales := greatest(v_total - v_tax_total, 0);

  for v_payment in select value from jsonb_array_elements(v_payments)
  loop
    v_method := coalesce(nullif(v_payment->>'method', ''), 'cash');

    if v_method not in ('cash', 'card', 'gcash', 'maya', 'bank_transfer', 'store_credit', 'cod') then
      raise exception 'Invalid payment method' using errcode = '22023';
    end if;

    if coalesce(nullif(v_payment->>'amount', '')::numeric, 0) <= 0 then
      raise exception 'Payment amount must be greater than zero' using errcode = '23514';
    end if;

    v_payment_total := v_payment_total + round((v_payment->>'amount')::numeric, 2);
    v_has_cash := v_has_cash or v_method = 'cash';
  end loop;

  if v_payment_total < v_total then
    raise exception 'Payment total is less than sale total' using errcode = '23514';
  end if;

  v_change_due := case when v_has_cash then greatest(v_payment_total - v_total, 0) else 0 end;

  select string_agg(distinct initcap(replace(value->>'method', '_', ' ')), ', ' order by initcap(replace(value->>'method', '_', ' ')))
  into v_payment_summary
  from jsonb_array_elements(v_payments);

  v_order_number := 'POS-' || to_char(now(), 'YYYYMMDD-HH24MISS-') || upper(left(replace(gen_random_uuid()::text, '-', ''), 5));
  v_invoice_number := 'INV-' || to_char(now(), 'YYYYMMDD-HH24MISS-') || upper(left(replace(gen_random_uuid()::text, '-', ''), 5));
  v_cashier_id := public.pos_ensure_cashier(v_actor.id, v_branch_id);

  insert into public.sales_orders (
    branch_id,
    cashier_id,
    user_id,
    order_number,
    invoice_number,
    business_date,
    customer_name,
    subtotal,
    discount_total,
    tax_total,
    total,
    status,
    payment_status,
    payment_method_summary,
    vatable_sales,
    vat_exempt_sales,
    zero_rated_sales,
    non_vat_sales,
    net_sales,
    amount_tendered,
    change_due,
    source,
    offline_reference,
    notes
  )
  values (
    v_branch_id,
    v_cashier_id,
    v_actor.id,
    v_order_number,
    v_invoice_number,
    current_date,
    v_customer_name,
    v_subtotal,
    v_discount_total,
    v_tax_total,
    v_total,
    'completed',
    'paid',
    v_payment_summary,
    v_vatable_sales,
    v_vat_exempt_sales,
    v_zero_rated_sales,
    v_non_vat_sales,
    v_net_sales,
    v_payment_total,
    v_change_due,
    v_source,
    v_offline_reference,
    v_notes
  )
  returning id into v_order_id;

  for v_line in select * from pg_temp.pos_checkout_lines order by line_no
  loop
    insert into public.sales_order_items (
      order_id,
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
      tax_type,
      tax_rate,
      tax_inclusive,
      tax_amount,
      net_amount
    )
    values (
      v_order_id,
      v_line.product_id,
      v_line.product_variant_id,
      v_line.product_name,
      v_line.sku,
      v_line.barcode,
      v_line.variant_name,
      v_line.quantity,
      v_line.unit_price,
      v_line.gross_amount,
      v_line.discount_amount,
      v_line.tax_type,
      v_line.tax_rate,
      v_line.tax_inclusive,
      v_line.tax_amount,
      v_line.net_amount
    )
    returning id into v_order_item_id;

    v_remaining := v_line.quantity;

    for v_batch in
      select *
      from public.inventory_batches
      where branch_id = v_branch_id
        and product_id = v_line.product_id
        and (v_line.product_variant_id is null or product_variant_id = v_line.product_variant_id)
        and status = 'active'
        and quantity_on_hand > 0
      order by expiry_date asc nulls last, received_at asc, created_at asc
      for update
    loop
      exit when v_remaining <= 0;

      v_take := least(v_remaining, v_batch.quantity_on_hand);

      select coalesce(sum(quantity_on_hand), 0)::integer
      into v_before_total
      from public.inventory_batches
      where branch_id = v_branch_id
        and product_id = v_line.product_id
        and status = 'active';

      v_after_total := v_before_total - v_take;

      update public.inventory_batches
      set quantity_on_hand = quantity_on_hand - v_take,
          status = case when quantity_on_hand - v_take = 0 then 'depleted' else 'active' end
      where id = v_batch.id;

      insert into public.sales_order_batch_allocations (
        order_item_id,
        inventory_batch_id,
        batch_number,
        expiry_date,
        quantity,
        unit_cost
      )
      values (
        v_order_item_id,
        v_batch.id,
        v_batch.batch_number,
        v_batch.expiry_date,
        v_take,
        v_batch.unit_cost
      );

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
        v_line.product_id,
        v_batch.product_variant_id,
        v_batch.id,
        'stock_out',
        -v_take,
        v_before_total,
        v_after_total,
        v_batch.unit_cost,
        v_batch.batch_number,
        v_batch.expiry_date,
        v_order_number,
        'POS sale checkout',
        v_actor.id
      );

      v_remaining := v_remaining - v_take;
    end loop;

    if v_remaining > 0 then
      raise exception 'Insufficient stock while completing POS sale' using errcode = '23514';
    end if;

    perform public.inventory_sync_product_stock(v_branch_id, v_line.product_id);
  end loop;

  for v_payment in select value from jsonb_array_elements(v_payments)
  loop
    insert into public.sales_order_payments (
      order_id,
      method,
      amount,
      reference_number
    )
    values (
      v_order_id,
      v_payment->>'method',
      round((v_payment->>'amount')::numeric, 2),
      nullif(trim(coalesce(v_payment->>'reference_number', '')), '')
    );
  end loop;

  perform public.log_activity(
    'pos.sale_completed',
    'sales_order',
    v_order_id::text,
    jsonb_build_object(
      'order_number', v_order_number,
      'invoice_number', v_invoice_number,
      'branch_id', v_branch_id,
      'total', v_total,
      'source', v_source
    ),
    v_actor.id
  );

  return jsonb_build_object(
    'pos', public.pos_management_get(v_branch_id),
    'order', (
      select to_jsonb(row)
      from (
        select
          so.id,
          so.order_number,
          so.invoice_number,
          so.business_date,
          so.customer_name,
          so.subtotal,
          so.discount_total,
          so.tax_total,
          so.total,
          so.amount_tendered,
          so.change_due,
          so.payment_method_summary,
          so.status,
          so.source,
          so.created_at,
          v_actor.full_name as cashier_name,
          v_actor.username as cashier_username,
          coalesce((
            select jsonb_agg(to_jsonb(soi) order by soi.created_at asc)
            from public.sales_order_items soi
            where soi.order_id = so.id
          ), '[]'::jsonb) as items,
          coalesce((
            select jsonb_agg(to_jsonb(sop) order by sop.created_at asc)
            from public.sales_order_payments sop
            where sop.order_id = so.id
          ), '[]'::jsonb) as payments
        from public.sales_orders so
        where so.id = v_order_id
      ) row
    )
  );
end;
$$;

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
  v_profile public.user_profiles;
  v_from date := coalesce(p_from, current_date - 6);
  v_to date := coalesce(p_to, current_date);
  v_branch_filter uuid := p_branch_id;
  v_result jsonb;
begin
  v_profile := public.ensure_active_user();

  if v_to < v_from then
    raise exception 'To date must be after from date' using errcode = '22007';
  end if;

  if v_profile.role not in ('admin', 'auditor') then
    v_branch_filter := v_profile.branch_id;
  end if;

  with scoped_orders as (
    select o.*
    from public.sales_orders o
    where o.status = 'completed'
      and o.business_date >= v_from
      and o.business_date <= v_to
      and (v_branch_filter is null or o.branch_id = v_branch_filter)
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
      and (v_branch_filter is null or b.id = v_branch_filter)
    group by b.id, b.branch_code, b.name
  ),
  cashier_sales as (
    select
      coalesce(o.user_id::text, o.cashier_id::text, 'unassigned') as cashier_id,
      coalesce(up.username, c.employee_code, '-') as employee_code,
      coalesce(up.full_name, c.name, 'Unassigned') as cashier_name,
      b.name as branch_name,
      count(o.id)::integer as orders,
      coalesce(sum(o.total), 0)::numeric(14, 2) as sales,
      coalesce(avg(o.total), 0)::numeric(14, 2) as average_order
    from scoped_orders o
    join public.branches b on b.id = o.branch_id
    left join public.user_profiles up on up.id = o.user_id
    left join public.cashiers c on c.id = o.cashier_id
    group by coalesce(o.user_id::text, o.cashier_id::text, 'unassigned'), coalesce(up.username, c.employee_code, '-'), coalesce(up.full_name, c.name, 'Unassigned'), b.name
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
      and (v_branch_filter is null or bi.branch_id = v_branch_filter)
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
      select coalesce(jsonb_agg(jsonb_build_object('id', b.id, 'name', b.name, 'branch_code', b.branch_code) order by b.name), '[]'::jsonb)
      from public.branches b
      where b.is_active = true
        and (v_branch_filter is null or b.id = v_branch_filter)
    ),
    'sales_by_branch', (
      select coalesce(
        jsonb_agg(
          jsonb_build_object(
            'branch_id', bs.branch_id,
            'label', bs.branch_name,
            'branch_code', bs.branch_code,
            'orders', bs.orders,
            'sales', bs.sales,
            'discounts', bs.discounts,
            'vat', bs.vat
          )
          order by bs.sales desc, bs.branch_name
        ),
        '[]'::jsonb
      )
      from branch_sales bs
    ),
    'daily_sales', (
      select coalesce(
        jsonb_agg(
          jsonb_build_object(
            'business_date', d.day,
            'label', to_char(d.day, 'Mon DD'),
            'orders', coalesce(s.orders, 0),
            'sales', coalesce(s.sales, 0)
          )
          order by d.day
        ),
        '[]'::jsonb
      )
      from generate_series(v_from, v_to, interval '1 day') as d(day)
      left join lateral (
        select count(*)::integer as orders, coalesce(sum(o.total), 0)::numeric(14, 2) as sales
        from scoped_orders o
        where o.business_date = d.day::date
      ) s on true
    ),
    'cashier_performance', (
      select coalesce(
        jsonb_agg(
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
        ),
        '[]'::jsonb
      )
      from cashier_sales cs
    ),
    'low_stock_alerts', (
      select coalesce(
        jsonb_agg(to_jsonb(ls) order by ls.quantity_on_hand asc, ls.product_name asc),
        '[]'::jsonb
      )
      from low_stock ls
    ),
    'generated_at', now()
  )
  into v_result;

  return v_result;
end;
$$;

revoke all on function public.pos_user_can_sell(uuid) from public;
revoke all on function public.pos_user_can_discount(numeric) from public;
revoke all on function public.pos_ensure_cashier(uuid, uuid) from public;
revoke all on function public.pos_management_get(uuid) from public;
revoke all on function public.pos_checkout(jsonb) from public;
grant execute on function public.pos_management_get(uuid) to authenticated;
grant execute on function public.pos_checkout(jsonb) to authenticated;
grant execute on function public.dashboard_get_metrics(date, date, uuid) to authenticated;

notify pgrst, 'reload schema';
