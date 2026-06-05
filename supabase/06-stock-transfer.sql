-- MODULE 6: STOCK TRANSFER
-- Run after:
-- 1. supabase/00-reset-public-schema.sql
-- 2. supabase/01-dashboard-module.sql
-- 3. supabase/02-auth-and-branch-management.sql
-- 4. supabase/03-user-role-management.sql
-- 5. supabase/04-product-management.sql
-- 6. supabase/05-inventory-management.sql
--
-- Scope:
-- - Branch-to-branch stock transfer requests
-- - Approval
-- - FEFO dispatch from source batches
-- - Receiving into destination branch
-- - Variance tracking

create extension if not exists pgcrypto;

do $$
begin
  if exists (
    select 1
    from pg_constraint
    where conname = 'inventory_movements_movement_type_check'
      and conrelid = 'public.inventory_movements'::regclass
  ) then
    alter table public.inventory_movements
      drop constraint inventory_movements_movement_type_check;
  end if;

  alter table public.inventory_movements
    add constraint inventory_movements_movement_type_check
    check (
      movement_type in (
        'stock_in',
        'stock_out',
        'adjustment_plus',
        'adjustment_minus',
        'damaged',
        'expired',
        'transfer_in',
        'transfer_out'
      )
    );
end;
$$;

create table if not exists public.stock_transfers (
  id uuid primary key default gen_random_uuid(),
  transfer_number text not null unique,
  from_branch_id uuid not null references public.branches(id) on delete restrict,
  to_branch_id uuid not null references public.branches(id) on delete restrict,
  status text not null default 'requested' check (status in ('requested', 'approved', 'dispatched', 'received', 'cancelled', 'rejected')),
  notes text,
  rejection_reason text,
  requested_by uuid references public.user_profiles(id) on delete set null,
  approved_by uuid references public.user_profiles(id) on delete set null,
  dispatched_by uuid references public.user_profiles(id) on delete set null,
  received_by uuid references public.user_profiles(id) on delete set null,
  requested_at timestamptz not null default now(),
  approved_at timestamptz,
  dispatched_at timestamptz,
  received_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (from_branch_id <> to_branch_id)
);

create table if not exists public.stock_transfer_items (
  id uuid primary key default gen_random_uuid(),
  transfer_id uuid not null references public.stock_transfers(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict,
  product_variant_id uuid references public.product_variants(id) on delete set null,
  quantity_requested integer not null check (quantity_requested > 0),
  quantity_approved integer not null default 0 check (quantity_approved >= 0),
  quantity_dispatched integer not null default 0 check (quantity_dispatched >= 0),
  quantity_received integer not null default 0 check (quantity_received >= 0),
  variance_quantity integer not null default 0,
  notes text,
  created_at timestamptz not null default now()
);

create table if not exists public.stock_transfer_batches (
  id uuid primary key default gen_random_uuid(),
  transfer_item_id uuid not null references public.stock_transfer_items(id) on delete cascade,
  source_batch_id uuid references public.inventory_batches(id) on delete set null,
  product_variant_id uuid references public.product_variants(id) on delete set null,
  batch_number text,
  expiry_date date,
  unit_cost numeric(14, 2) not null default 0 check (unit_cost >= 0),
  quantity_dispatched integer not null check (quantity_dispatched > 0),
  quantity_received integer not null default 0 check (quantity_received >= 0),
  created_at timestamptz not null default now()
);

alter table public.stock_transfer_batches
  add column if not exists product_variant_id uuid references public.product_variants(id) on delete set null;

create index if not exists idx_stock_transfers_from_branch on public.stock_transfers(from_branch_id, status, created_at desc);
create index if not exists idx_stock_transfers_to_branch on public.stock_transfers(to_branch_id, status, created_at desc);
create index if not exists idx_stock_transfer_items_transfer on public.stock_transfer_items(transfer_id);
create index if not exists idx_stock_transfer_batches_item on public.stock_transfer_batches(transfer_item_id);

drop trigger if exists set_stock_transfers_updated_at on public.stock_transfers;
create trigger set_stock_transfers_updated_at
before update on public.stock_transfers
for each row execute function public.set_updated_at();

alter table public.stock_transfers enable row level security;
alter table public.stock_transfer_items enable row level security;
alter table public.stock_transfer_batches enable row level security;

drop policy if exists stock_transfers_select_by_role on public.stock_transfers;
create policy stock_transfers_select_by_role
on public.stock_transfers
for select
to authenticated
using (
  public.current_user_is_admin()
  or public.current_user_role() = 'auditor'
  or from_branch_id = public.current_user_branch_id()
  or to_branch_id = public.current_user_branch_id()
);

drop policy if exists stock_transfers_admin_manager_write on public.stock_transfers;
create policy stock_transfers_admin_manager_write
on public.stock_transfers
for all
to authenticated
using (
  public.current_user_is_admin()
  or (
    public.current_user_role() = 'manager'
    and (from_branch_id = public.current_user_branch_id() or to_branch_id = public.current_user_branch_id())
  )
)
with check (
  public.current_user_is_admin()
  or (
    public.current_user_role() = 'manager'
    and (from_branch_id = public.current_user_branch_id() or to_branch_id = public.current_user_branch_id())
  )
);

drop policy if exists stock_transfer_items_select_by_role on public.stock_transfer_items;
create policy stock_transfer_items_select_by_role
on public.stock_transfer_items
for select
to authenticated
using (
  exists (
    select 1
    from public.stock_transfers st
    where st.id = transfer_id
      and (
        public.current_user_is_admin()
        or public.current_user_role() = 'auditor'
        or st.from_branch_id = public.current_user_branch_id()
        or st.to_branch_id = public.current_user_branch_id()
      )
  )
);

drop policy if exists stock_transfer_items_admin_manager_write on public.stock_transfer_items;
create policy stock_transfer_items_admin_manager_write
on public.stock_transfer_items
for all
to authenticated
using (
  exists (
    select 1
    from public.stock_transfers st
    where st.id = transfer_id
      and (
        public.current_user_is_admin()
        or (
          public.current_user_role() = 'manager'
          and (st.from_branch_id = public.current_user_branch_id() or st.to_branch_id = public.current_user_branch_id())
        )
      )
  )
)
with check (
  exists (
    select 1
    from public.stock_transfers st
    where st.id = transfer_id
      and (
        public.current_user_is_admin()
        or (
          public.current_user_role() = 'manager'
          and (st.from_branch_id = public.current_user_branch_id() or st.to_branch_id = public.current_user_branch_id())
        )
      )
  )
);

drop policy if exists stock_transfer_batches_select_by_role on public.stock_transfer_batches;
create policy stock_transfer_batches_select_by_role
on public.stock_transfer_batches
for select
to authenticated
using (
  exists (
    select 1
    from public.stock_transfer_items sti
    join public.stock_transfers st on st.id = sti.transfer_id
    where sti.id = transfer_item_id
      and (
        public.current_user_is_admin()
        or public.current_user_role() = 'auditor'
        or st.from_branch_id = public.current_user_branch_id()
        or st.to_branch_id = public.current_user_branch_id()
      )
  )
);

drop policy if exists stock_transfer_batches_admin_manager_write on public.stock_transfer_batches;
create policy stock_transfer_batches_admin_manager_write
on public.stock_transfer_batches
for all
to authenticated
using (
  exists (
    select 1
    from public.stock_transfer_items sti
    join public.stock_transfers st on st.id = sti.transfer_id
    where sti.id = transfer_item_id
      and (
        public.current_user_is_admin()
        or (
          public.current_user_role() = 'manager'
          and (st.from_branch_id = public.current_user_branch_id() or st.to_branch_id = public.current_user_branch_id())
        )
      )
  )
)
with check (
  exists (
    select 1
    from public.stock_transfer_items sti
    join public.stock_transfers st on st.id = sti.transfer_id
    where sti.id = transfer_item_id
      and (
        public.current_user_is_admin()
        or (
          public.current_user_role() = 'manager'
          and (st.from_branch_id = public.current_user_branch_id() or st.to_branch_id = public.current_user_branch_id())
        )
      )
  )
);

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
      'activity.view',
      'reports.view'
    ]::text[]
    else array[
      'dashboard.view',
      'products.view',
      'pos.sell',
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

create or replace function public.stock_transfer_can_manage(p_branch_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_profile public.user_profiles;
begin
  v_profile := public.ensure_active_user();

  if v_profile.role = 'admin' then
    return true;
  end if;

  if v_profile.role = 'manager' and v_profile.branch_id = p_branch_id then
    return true;
  end if;

  return false;
end;
$$;

create or replace function public.stock_transfer_management_get(p_branch_id uuid default null)
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

  if v_profile.role not in ('admin', 'manager', 'auditor') then
    raise exception 'Stock transfers are not available for this role' using errcode = '42501';
  end if;

  if v_profile.role in ('admin', 'auditor') then
    v_effective_branch_id := p_branch_id;
  else
    v_effective_branch_id := v_profile.branch_id;
  end if;

  with active_branches as (
    select b.*
    from public.branches b
    where b.is_active = true
  ),
  visible_transfers as (
    select st.*
    from public.stock_transfers st
    where
      (
        v_profile.role in ('admin', 'auditor')
        or st.from_branch_id = v_profile.branch_id
        or st.to_branch_id = v_profile.branch_id
      )
      and (
        v_effective_branch_id is null
        or st.from_branch_id = v_effective_branch_id
        or st.to_branch_id = v_effective_branch_id
      )
  ),
  transfer_rows as (
    select
      st.id,
      st.transfer_number,
      st.from_branch_id,
      fb.branch_code as from_branch_code,
      fb.name as from_branch_name,
      st.to_branch_id,
      tb.branch_code as to_branch_code,
      tb.name as to_branch_name,
      st.status,
      st.notes,
      st.rejection_reason,
      st.requested_by,
      req.full_name as requested_by_name,
      req.username as requested_by_username,
      st.approved_by,
      appr.full_name as approved_by_name,
      st.dispatched_by,
      disp.full_name as dispatched_by_name,
      st.received_by,
      recv.full_name as received_by_name,
      st.requested_at,
      st.approved_at,
      st.dispatched_at,
      st.received_at,
      st.created_at,
      st.updated_at,
      coalesce(item_totals.total_requested, 0)::integer as total_requested,
      coalesce(item_totals.total_approved, 0)::integer as total_approved,
      coalesce(item_totals.total_dispatched, 0)::integer as total_dispatched,
      coalesce(item_totals.total_received, 0)::integer as total_received,
      coalesce(item_totals.total_variance, 0)::integer as total_variance,
      coalesce(item_totals.item_count, 0)::integer as item_count,
      coalesce(items.items, '[]'::jsonb) as items
    from visible_transfers st
    join public.branches fb on fb.id = st.from_branch_id
    join public.branches tb on tb.id = st.to_branch_id
    left join public.user_profiles req on req.id = st.requested_by
    left join public.user_profiles appr on appr.id = st.approved_by
    left join public.user_profiles disp on disp.id = st.dispatched_by
    left join public.user_profiles recv on recv.id = st.received_by
    left join lateral (
      select
        count(*)::integer as item_count,
        coalesce(sum(quantity_requested), 0)::integer as total_requested,
        coalesce(sum(quantity_approved), 0)::integer as total_approved,
        coalesce(sum(quantity_dispatched), 0)::integer as total_dispatched,
        coalesce(sum(quantity_received), 0)::integer as total_received,
        coalesce(sum(abs(variance_quantity)), 0)::integer as total_variance
      from public.stock_transfer_items sti
      where sti.transfer_id = st.id
    ) item_totals on true
    left join lateral (
      select jsonb_agg(
        jsonb_build_object(
          'id', sti.id,
          'product_id', sti.product_id,
          'product_name', p.name,
          'sku', p.sku,
          'barcode', p.barcode,
          'product_variant_id', sti.product_variant_id,
          'variant_name', pv.variant_name,
          'quantity_requested', sti.quantity_requested,
          'quantity_approved', sti.quantity_approved,
          'quantity_dispatched', sti.quantity_dispatched,
          'quantity_received', sti.quantity_received,
          'variance_quantity', sti.variance_quantity,
          'notes', sti.notes,
          'available_stock', coalesce(stock.available_stock, 0),
          'batches', coalesce(batches.batches, '[]'::jsonb)
        )
        order by p.name, pv.variant_name
      ) as items
      from public.stock_transfer_items sti
      join public.products p on p.id = sti.product_id
      left join public.product_variants pv on pv.id = sti.product_variant_id
      left join lateral (
        select coalesce(sum(ib.quantity_on_hand), 0)::integer as available_stock
        from public.inventory_batches ib
        where ib.branch_id = st.from_branch_id
          and ib.product_id = sti.product_id
          and (sti.product_variant_id is null or ib.product_variant_id = sti.product_variant_id)
          and ib.status = 'active'
      ) stock on true
      left join lateral (
        select jsonb_agg(
          jsonb_build_object(
            'id', stb.id,
            'source_batch_id', stb.source_batch_id,
            'product_variant_id', stb.product_variant_id,
            'batch_number', stb.batch_number,
            'expiry_date', stb.expiry_date,
            'unit_cost', stb.unit_cost,
            'quantity_dispatched', stb.quantity_dispatched,
            'quantity_received', stb.quantity_received
          )
          order by stb.expiry_date asc nulls last, stb.created_at asc
        ) as batches
        from public.stock_transfer_batches stb
        where stb.transfer_item_id = sti.id
      ) batches on true
      where sti.transfer_id = st.id
    ) items on true
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
      p.cost_price,
      p.selling_price,
      coalesce(variants.variants, '[]'::jsonb) as variants
    from public.products p
    left join public.product_categories pc on pc.id = p.category_id
    left join public.product_brands pb on pb.id = p.brand_id
    left join lateral (
      select jsonb_agg(
        jsonb_build_object(
          'id', pv.id,
          'variant_name', pv.variant_name,
          'sku', pv.sku,
          'barcode', pv.barcode,
          'cost_price', pv.cost_price,
          'selling_price', pv.selling_price,
          'is_active', pv.is_active
        )
        order by pv.variant_name
      ) as variants
      from public.product_variants pv
      where pv.product_id = p.id
        and pv.deleted_at is null
        and pv.is_active = true
    ) variants on true
    where p.deleted_at is null
      and p.is_active = true
  ),
  inventory_rows as (
    select
      bi.branch_id,
      bi.product_id,
      bi.quantity_on_hand,
      p.name as product_name,
      p.sku,
      p.barcode
    from public.branch_inventory bi
    join public.products p on p.id = bi.product_id
    join active_branches b on b.id = bi.branch_id
    where p.deleted_at is null
      and p.is_active = true
  ),
  batch_rows as (
    select
      ib.id,
      ib.branch_id,
      b.branch_code,
      b.name as branch_name,
      ib.product_id,
      p.sku,
      p.name as product_name,
      ib.product_variant_id,
      pv.variant_name,
      ib.batch_number,
      ib.expiry_date,
      ib.quantity_on_hand,
      ib.unit_cost,
      ib.status
    from public.inventory_batches ib
    join active_branches b on b.id = ib.branch_id
    join public.products p on p.id = ib.product_id
    left join public.product_variants pv on pv.id = ib.product_variant_id
    where ib.status = 'active'
      and ib.quantity_on_hand > 0
    order by b.name, p.name, ib.expiry_date asc nulls last
  )
  select jsonb_build_object(
    'summary', jsonb_build_object(
      'total_transfers', coalesce((select count(*) from transfer_rows), 0),
      'requested', coalesce((select count(*) from transfer_rows where status = 'requested'), 0),
      'approved', coalesce((select count(*) from transfer_rows where status = 'approved'), 0),
      'dispatched', coalesce((select count(*) from transfer_rows where status = 'dispatched'), 0),
      'received', coalesce((select count(*) from transfer_rows where status = 'received'), 0),
      'variance_units', coalesce((select sum(total_variance) from transfer_rows), 0)
    ),
    'branches', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', b.id,
          'branch_code', b.branch_code,
          'name', b.name,
          'is_head_office', b.is_head_office
        )
        order by b.is_head_office desc, b.name
      )
      from active_branches b
    ), '[]'::jsonb),
    'products', coalesce((select jsonb_agg(to_jsonb(product_rows) order by name asc) from product_rows), '[]'::jsonb),
    'inventory', coalesce((select jsonb_agg(to_jsonb(inventory_rows) order by product_name asc) from inventory_rows), '[]'::jsonb),
    'batches', coalesce((select jsonb_agg(to_jsonb(batch_rows)) from batch_rows), '[]'::jsonb),
    'transfers', coalesce((
      select jsonb_agg(to_jsonb(transfer_rows) order by created_at desc)
      from transfer_rows
    ), '[]'::jsonb),
    'generated_at', now()
  )
  into v_result;

  return v_result;
end;
$$;

create or replace function public.stock_transfer_create(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor public.user_profiles;
  v_transfer_id uuid;
  v_transfer_number text;
  v_from_branch_id uuid := nullif(p_payload->>'from_branch_id', '')::uuid;
  v_to_branch_id uuid := nullif(p_payload->>'to_branch_id', '')::uuid;
  v_items jsonb := p_payload->'items';
  v_item jsonb;
  v_product_id uuid;
  v_variant_id uuid;
  v_quantity integer;
begin
  v_actor := public.ensure_active_user();

  if v_actor.role not in ('admin', 'manager') then
    raise exception 'Only admins and managers can create transfer requests' using errcode = '42501';
  end if;

  if v_from_branch_id is null or v_to_branch_id is null then
    raise exception 'Source and destination branches are required' using errcode = '23502';
  end if;

  if v_from_branch_id = v_to_branch_id then
    raise exception 'Source and destination branches must be different' using errcode = '23514';
  end if;

  if v_actor.role = 'manager' and v_actor.branch_id not in (v_from_branch_id, v_to_branch_id) then
    raise exception 'Managers can create transfers only for their own branch' using errcode = '42501';
  end if;

  if not exists (select 1 from public.branches where id = v_from_branch_id and is_active = true) then
    raise exception 'Source branch not found or inactive' using errcode = '02000';
  end if;

  if not exists (select 1 from public.branches where id = v_to_branch_id and is_active = true) then
    raise exception 'Destination branch not found or inactive' using errcode = '02000';
  end if;

  if v_items is null or jsonb_typeof(v_items) <> 'array' or jsonb_array_length(v_items) = 0 then
    raise exception 'At least one transfer item is required' using errcode = '23502';
  end if;

  v_transfer_number := 'TR-' || to_char(now(), 'YYYYMMDD-HH24MISS-') || upper(left(replace(gen_random_uuid()::text, '-', ''), 6));

  insert into public.stock_transfers (
    transfer_number,
    from_branch_id,
    to_branch_id,
    status,
    notes,
    requested_by
  )
  values (
    v_transfer_number,
    v_from_branch_id,
    v_to_branch_id,
    'requested',
    nullif(trim(coalesce(p_payload->>'notes', '')), ''),
    v_actor.id
  )
  returning id into v_transfer_id;

  for v_item in select value from jsonb_array_elements(v_items)
  loop
    v_product_id := nullif(v_item->>'product_id', '')::uuid;
    v_variant_id := nullif(v_item->>'product_variant_id', '')::uuid;
    v_quantity := coalesce(nullif(v_item->>'quantity_requested', '')::integer, 0);

    if v_product_id is null then
      raise exception 'Every transfer row must have a product' using errcode = '23502';
    end if;

    if v_quantity <= 0 then
      raise exception 'Transfer quantity must be greater than zero' using errcode = '23514';
    end if;

    if not exists (
      select 1
      from public.products p
      where p.id = v_product_id
        and p.deleted_at is null
        and p.is_active = true
    ) then
      raise exception 'Product not found or inactive' using errcode = '02000';
    end if;

    if v_variant_id is not null and not exists (
      select 1
      from public.product_variants pv
      where pv.id = v_variant_id
        and pv.product_id = v_product_id
        and pv.deleted_at is null
        and pv.is_active = true
    ) then
      raise exception 'Variant does not belong to this product' using errcode = '23514';
    end if;

    insert into public.stock_transfer_items (
      transfer_id,
      product_id,
      product_variant_id,
      quantity_requested,
      notes
    )
    values (
      v_transfer_id,
      v_product_id,
      v_variant_id,
      v_quantity,
      nullif(trim(coalesce(v_item->>'notes', '')), '')
    );
  end loop;

  perform public.log_activity(
    'stock_transfer.created',
    'stock_transfer',
    v_transfer_id::text,
    jsonb_build_object('transfer_number', v_transfer_number, 'from_branch_id', v_from_branch_id, 'to_branch_id', v_to_branch_id),
    v_actor.id
  );

  return public.stock_transfer_management_get(null);
end;
$$;

create or replace function public.stock_transfer_approve(p_transfer_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor public.user_profiles;
  v_transfer public.stock_transfers;
begin
  v_actor := public.ensure_active_user();

  select *
  into v_transfer
  from public.stock_transfers
  where id = p_transfer_id
  for update;

  if not found then
    raise exception 'Transfer not found' using errcode = '02000';
  end if;

  if v_transfer.status <> 'requested' then
    raise exception 'Only requested transfers can be approved' using errcode = '23514';
  end if;

  if v_actor.role <> 'admin' and not (v_actor.role = 'manager' and v_actor.branch_id = v_transfer.from_branch_id) then
    raise exception 'Only admin or the source branch manager can approve this transfer' using errcode = '42501';
  end if;

  update public.stock_transfer_items
  set quantity_approved = quantity_requested
  where transfer_id = p_transfer_id;

  update public.stock_transfers
  set status = 'approved',
      approved_by = v_actor.id,
      approved_at = now()
  where id = p_transfer_id;

  perform public.log_activity(
    'stock_transfer.approved',
    'stock_transfer',
    p_transfer_id::text,
    jsonb_build_object('transfer_number', v_transfer.transfer_number),
    v_actor.id
  );

  return public.stock_transfer_management_get(null);
end;
$$;

create or replace function public.stock_transfer_cancel(p_transfer_id uuid, p_reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor public.user_profiles;
  v_transfer public.stock_transfers;
begin
  v_actor := public.ensure_active_user();

  select *
  into v_transfer
  from public.stock_transfers
  where id = p_transfer_id
  for update;

  if not found then
    raise exception 'Transfer not found' using errcode = '02000';
  end if;

  if v_transfer.status not in ('requested', 'approved') then
    raise exception 'Only requested or approved transfers can be cancelled' using errcode = '23514';
  end if;

  if v_actor.role <> 'admin' and not (
    v_actor.role = 'manager'
    and v_actor.branch_id in (v_transfer.from_branch_id, v_transfer.to_branch_id)
  ) then
    raise exception 'You cannot cancel this transfer' using errcode = '42501';
  end if;

  update public.stock_transfers
  set status = 'cancelled',
      rejection_reason = nullif(trim(coalesce(p_reason, '')), '')
  where id = p_transfer_id;

  perform public.log_activity(
    'stock_transfer.cancelled',
    'stock_transfer',
    p_transfer_id::text,
    jsonb_build_object('transfer_number', v_transfer.transfer_number, 'reason', p_reason),
    v_actor.id
  );

  return public.stock_transfer_management_get(null);
end;
$$;

create or replace function public.stock_transfer_dispatch(p_transfer_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor public.user_profiles;
  v_transfer public.stock_transfers;
  v_item record;
  v_batch record;
  v_remaining integer;
  v_take integer;
  v_before_total integer;
  v_after_total integer;
  v_available integer;
begin
  v_actor := public.ensure_active_user();

  select *
  into v_transfer
  from public.stock_transfers
  where id = p_transfer_id
  for update;

  if not found then
    raise exception 'Transfer not found' using errcode = '02000';
  end if;

  if v_transfer.status <> 'approved' then
    raise exception 'Only approved transfers can be dispatched' using errcode = '23514';
  end if;

  if v_actor.role <> 'admin' and not (v_actor.role = 'manager' and v_actor.branch_id = v_transfer.from_branch_id) then
    raise exception 'Only admin or the source branch manager can dispatch this transfer' using errcode = '42501';
  end if;

  for v_item in
    select *
    from public.stock_transfer_items
    where transfer_id = p_transfer_id
    order by created_at asc
    for update
  loop
    if v_item.quantity_approved <= 0 then
      raise exception 'Every approved transfer item must have approved quantity' using errcode = '23514';
    end if;

    select coalesce(sum(quantity_on_hand), 0)::integer
    into v_available
    from public.inventory_batches
    where branch_id = v_transfer.from_branch_id
      and product_id = v_item.product_id
      and (v_item.product_variant_id is null or product_variant_id = v_item.product_variant_id)
      and status = 'active';

    if v_available < v_item.quantity_approved then
      raise exception 'Insufficient stock to dispatch transfer %. Available %, required %',
        v_transfer.transfer_number, v_available, v_item.quantity_approved
        using errcode = '23514';
    end if;
  end loop;

  for v_item in
    select *
    from public.stock_transfer_items
    where transfer_id = p_transfer_id
    order by created_at asc
    for update
  loop
    v_remaining := v_item.quantity_approved;

    for v_batch in
      select *
      from public.inventory_batches
      where branch_id = v_transfer.from_branch_id
        and product_id = v_item.product_id
        and (v_item.product_variant_id is null or product_variant_id = v_item.product_variant_id)
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
      where branch_id = v_transfer.from_branch_id
        and product_id = v_item.product_id
        and status = 'active';

      v_after_total := v_before_total - v_take;

      update public.inventory_batches
      set quantity_on_hand = quantity_on_hand - v_take,
          status = case when quantity_on_hand - v_take = 0 then 'depleted' else 'active' end
      where id = v_batch.id;

      insert into public.stock_transfer_batches (
        transfer_item_id,
        source_batch_id,
        product_variant_id,
        batch_number,
        expiry_date,
        unit_cost,
        quantity_dispatched
      )
      values (
        v_item.id,
        v_batch.id,
        v_batch.product_variant_id,
        v_batch.batch_number,
        v_batch.expiry_date,
        v_batch.unit_cost,
        v_take
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
        v_transfer.from_branch_id,
        v_item.product_id,
        v_batch.product_variant_id,
        v_batch.id,
        'transfer_out',
        -v_take,
        v_before_total,
        v_after_total,
        v_batch.unit_cost,
        v_batch.batch_number,
        v_batch.expiry_date,
        v_transfer.transfer_number,
        'Stock transfer dispatch',
        v_actor.id
      );

      v_remaining := v_remaining - v_take;
    end loop;

    if v_remaining > 0 then
      raise exception 'Insufficient stock while dispatching transfer' using errcode = '23514';
    end if;

    update public.stock_transfer_items
    set quantity_dispatched = quantity_approved
    where id = v_item.id;

    perform public.inventory_sync_product_stock(v_transfer.from_branch_id, v_item.product_id);
  end loop;

  update public.stock_transfers
  set status = 'dispatched',
      dispatched_by = v_actor.id,
      dispatched_at = now()
  where id = p_transfer_id;

  perform public.log_activity(
    'stock_transfer.dispatched',
    'stock_transfer',
    p_transfer_id::text,
    jsonb_build_object('transfer_number', v_transfer.transfer_number),
    v_actor.id
  );

  return public.stock_transfer_management_get(null);
end;
$$;

create or replace function public.stock_transfer_receive(p_transfer_id uuid, p_payload jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor public.user_profiles;
  v_transfer public.stock_transfers;
  v_item record;
  v_batch record;
  v_payload_item jsonb;
  v_payload_items jsonb := coalesce(p_payload->'items', '[]'::jsonb);
  v_receive_quantity integer;
  v_remaining integer;
  v_take integer;
  v_before_total integer;
  v_after_total integer;
  v_new_batch_id uuid;
begin
  v_actor := public.ensure_active_user();

  select *
  into v_transfer
  from public.stock_transfers
  where id = p_transfer_id
  for update;

  if not found then
    raise exception 'Transfer not found' using errcode = '02000';
  end if;

  if v_transfer.status <> 'dispatched' then
    raise exception 'Only dispatched transfers can be received' using errcode = '23514';
  end if;

  if v_actor.role <> 'admin' and not (v_actor.role = 'manager' and v_actor.branch_id = v_transfer.to_branch_id) then
    raise exception 'Only admin or the destination branch manager can receive this transfer' using errcode = '42501';
  end if;

  for v_item in
    select *
    from public.stock_transfer_items
    where transfer_id = p_transfer_id
    order by created_at asc
    for update
  loop
    v_receive_quantity := v_item.quantity_dispatched;
    v_payload_item := null;

    if jsonb_typeof(v_payload_items) = 'array' then
      select value
      into v_payload_item
      from jsonb_array_elements(v_payload_items)
      where value->>'item_id' = v_item.id::text
      limit 1;

      if v_payload_item is not null then
        v_receive_quantity := coalesce(nullif(v_payload_item->>'quantity_received', '')::integer, v_item.quantity_dispatched);
      end if;
    end if;

    if v_receive_quantity < 0 or v_receive_quantity > v_item.quantity_dispatched then
      raise exception 'Received quantity must be between zero and dispatched quantity' using errcode = '23514';
    end if;

    v_remaining := v_receive_quantity;

    for v_batch in
      select *
      from public.stock_transfer_batches
      where transfer_item_id = v_item.id
      order by expiry_date asc nulls last, created_at asc
      for update
    loop
      exit when v_remaining <= 0;

      v_take := least(v_remaining, v_batch.quantity_dispatched - v_batch.quantity_received);

      if v_take <= 0 then
        continue;
      end if;

      select coalesce(sum(quantity_on_hand), 0)::integer
      into v_before_total
      from public.inventory_batches
      where branch_id = v_transfer.to_branch_id
        and product_id = v_item.product_id
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
        v_transfer.to_branch_id,
        v_item.product_id,
        coalesce(v_item.product_variant_id, v_batch.product_variant_id),
        coalesce(v_batch.batch_number, v_transfer.transfer_number),
        v_batch.expiry_date,
        v_take,
        v_batch.unit_cost,
        current_date,
        'active'
      )
      returning id into v_new_batch_id;

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
        v_transfer.to_branch_id,
        v_item.product_id,
        coalesce(v_item.product_variant_id, v_batch.product_variant_id),
        v_new_batch_id,
        'transfer_in',
        v_take,
        v_before_total,
        v_after_total,
        v_batch.unit_cost,
        coalesce(v_batch.batch_number, v_transfer.transfer_number),
        v_batch.expiry_date,
        v_transfer.transfer_number,
        'Stock transfer receiving',
        v_actor.id
      );

      update public.stock_transfer_batches
      set quantity_received = quantity_received + v_take
      where id = v_batch.id;

      v_remaining := v_remaining - v_take;
    end loop;

    if v_remaining > 0 then
      raise exception 'Received quantity exceeds remaining dispatched batch quantity' using errcode = '23514';
    end if;

    update public.stock_transfer_items
    set quantity_received = v_receive_quantity,
        variance_quantity = v_receive_quantity - quantity_dispatched
    where id = v_item.id;

    perform public.inventory_sync_product_stock(v_transfer.to_branch_id, v_item.product_id);
  end loop;

  update public.stock_transfers
  set status = 'received',
      received_by = v_actor.id,
      received_at = now()
  where id = p_transfer_id;

  perform public.log_activity(
    'stock_transfer.received',
    'stock_transfer',
    p_transfer_id::text,
    jsonb_build_object('transfer_number', v_transfer.transfer_number),
    v_actor.id
  );

  return public.stock_transfer_management_get(null);
end;
$$;

revoke all on function public.stock_transfer_can_manage(uuid) from public;
revoke all on function public.stock_transfer_management_get(uuid) from public;
revoke all on function public.stock_transfer_create(jsonb) from public;
revoke all on function public.stock_transfer_approve(uuid) from public;
revoke all on function public.stock_transfer_cancel(uuid, text) from public;
revoke all on function public.stock_transfer_dispatch(uuid) from public;
revoke all on function public.stock_transfer_receive(uuid, jsonb) from public;
grant execute on function public.stock_transfer_management_get(uuid) to authenticated;
grant execute on function public.stock_transfer_create(jsonb) to authenticated;
grant execute on function public.stock_transfer_approve(uuid) to authenticated;
grant execute on function public.stock_transfer_cancel(uuid, text) to authenticated;
grant execute on function public.stock_transfer_dispatch(uuid) to authenticated;
grant execute on function public.stock_transfer_receive(uuid, jsonb) to authenticated;

notify pgrst, 'reload schema';
