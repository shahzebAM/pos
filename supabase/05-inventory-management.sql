-- MODULE 5: INVENTORY MANAGEMENT
-- Run after:
-- 1. supabase/00-reset-public-schema.sql
-- 2. supabase/01-dashboard-module.sql
-- 3. supabase/02-auth-and-branch-management.sql
-- 4. supabase/03-user-role-management.sql
-- 5. supabase/04-product-management.sql
--
-- Scope:
-- - Branch-wise stock
-- - Batch numbers and expiry dates
-- - Stock in / stock out
-- - Stock adjustments
-- - Damaged and expired stock removal
-- - Reorder and low-stock visibility
-- - Physical stock count posting

create extension if not exists pgcrypto;

alter table public.branch_inventory
  add column if not exists last_counted_at timestamptz;

create table if not exists public.inventory_batches (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict,
  product_variant_id uuid references public.product_variants(id) on delete set null,
  batch_number text,
  expiry_date date,
  quantity_on_hand integer not null default 0 check (quantity_on_hand >= 0),
  unit_cost numeric(14, 2) not null default 0 check (unit_cost >= 0),
  received_at date not null default current_date,
  status text not null default 'active' check (status in ('active', 'depleted', 'damaged', 'expired')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.inventory_movements (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches(id) on delete restrict,
  product_id uuid not null references public.products(id) on delete restrict,
  product_variant_id uuid references public.product_variants(id) on delete set null,
  batch_id uuid references public.inventory_batches(id) on delete set null,
  movement_type text not null check (
    movement_type in (
      'stock_in',
      'stock_out',
      'adjustment_plus',
      'adjustment_minus',
      'damaged',
      'expired'
    )
  ),
  quantity_delta integer not null check (quantity_delta <> 0),
  quantity_before integer not null default 0 check (quantity_before >= 0),
  quantity_after integer not null default 0 check (quantity_after >= 0),
  unit_cost numeric(14, 2) not null default 0 check (unit_cost >= 0),
  batch_number text,
  expiry_date date,
  reference_number text,
  reason text,
  created_by uuid references public.user_profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.stock_counts (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches(id) on delete restrict,
  count_number text not null unique,
  status text not null default 'posted' check (status in ('draft', 'posted', 'voided')),
  notes text,
  created_by uuid references public.user_profiles(id) on delete set null,
  posted_by uuid references public.user_profiles(id) on delete set null,
  started_at timestamptz not null default now(),
  posted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.stock_count_items (
  id uuid primary key default gen_random_uuid(),
  stock_count_id uuid not null references public.stock_counts(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict,
  product_variant_id uuid references public.product_variants(id) on delete set null,
  system_quantity integer not null default 0 check (system_quantity >= 0),
  counted_quantity integer not null default 0 check (counted_quantity >= 0),
  variance_quantity integer not null default 0,
  created_at timestamptz not null default now(),
  unique (stock_count_id, product_id, product_variant_id)
);

create index if not exists idx_inventory_batches_branch_product on public.inventory_batches(branch_id, product_id, product_variant_id);
create index if not exists idx_inventory_batches_expiry on public.inventory_batches(expiry_date, quantity_on_hand);
create index if not exists idx_inventory_batches_status on public.inventory_batches(status, quantity_on_hand);
create index if not exists idx_inventory_movements_branch_created on public.inventory_movements(branch_id, created_at desc);
create index if not exists idx_inventory_movements_product_created on public.inventory_movements(product_id, created_at desc);
create index if not exists idx_stock_counts_branch_created on public.stock_counts(branch_id, created_at desc);
create index if not exists idx_stock_count_items_count on public.stock_count_items(stock_count_id);

drop trigger if exists set_inventory_batches_updated_at on public.inventory_batches;
create trigger set_inventory_batches_updated_at
before update on public.inventory_batches
for each row execute function public.set_updated_at();

drop trigger if exists set_stock_counts_updated_at on public.stock_counts;
create trigger set_stock_counts_updated_at
before update on public.stock_counts
for each row execute function public.set_updated_at();

alter table public.inventory_batches enable row level security;
alter table public.inventory_movements enable row level security;
alter table public.stock_counts enable row level security;
alter table public.stock_count_items enable row level security;

drop policy if exists inventory_batches_select_by_role on public.inventory_batches;
create policy inventory_batches_select_by_role
on public.inventory_batches
for select
to authenticated
using (
  public.current_user_is_admin()
  or public.current_user_role() = 'auditor'
  or branch_id = public.current_user_branch_id()
);

drop policy if exists inventory_batches_admin_manager_write on public.inventory_batches;
create policy inventory_batches_admin_manager_write
on public.inventory_batches
for all
to authenticated
using (
  public.current_user_is_admin()
  or (public.current_user_role() = 'manager' and branch_id = public.current_user_branch_id())
)
with check (
  public.current_user_is_admin()
  or (public.current_user_role() = 'manager' and branch_id = public.current_user_branch_id())
);

drop policy if exists inventory_movements_select_by_role on public.inventory_movements;
create policy inventory_movements_select_by_role
on public.inventory_movements
for select
to authenticated
using (
  public.current_user_is_admin()
  or public.current_user_role() = 'auditor'
  or branch_id = public.current_user_branch_id()
);

drop policy if exists inventory_movements_admin_manager_insert on public.inventory_movements;
create policy inventory_movements_admin_manager_insert
on public.inventory_movements
for insert
to authenticated
with check (
  public.current_user_is_admin()
  or (public.current_user_role() = 'manager' and branch_id = public.current_user_branch_id())
);

drop policy if exists stock_counts_select_by_role on public.stock_counts;
create policy stock_counts_select_by_role
on public.stock_counts
for select
to authenticated
using (
  public.current_user_is_admin()
  or public.current_user_role() = 'auditor'
  or branch_id = public.current_user_branch_id()
);

drop policy if exists stock_counts_admin_manager_write on public.stock_counts;
create policy stock_counts_admin_manager_write
on public.stock_counts
for all
to authenticated
using (
  public.current_user_is_admin()
  or (public.current_user_role() = 'manager' and branch_id = public.current_user_branch_id())
)
with check (
  public.current_user_is_admin()
  or (public.current_user_role() = 'manager' and branch_id = public.current_user_branch_id())
);

drop policy if exists stock_count_items_select_by_role on public.stock_count_items;
create policy stock_count_items_select_by_role
on public.stock_count_items
for select
to authenticated
using (
  exists (
    select 1
    from public.stock_counts sc
    where sc.id = stock_count_id
      and (
        public.current_user_is_admin()
        or public.current_user_role() = 'auditor'
        or sc.branch_id = public.current_user_branch_id()
      )
  )
);

drop policy if exists stock_count_items_admin_manager_write on public.stock_count_items;
create policy stock_count_items_admin_manager_write
on public.stock_count_items
for all
to authenticated
using (
  exists (
    select 1
    from public.stock_counts sc
    where sc.id = stock_count_id
      and (
        public.current_user_is_admin()
        or (public.current_user_role() = 'manager' and sc.branch_id = public.current_user_branch_id())
      )
  )
)
with check (
  exists (
    select 1
    from public.stock_counts sc
    where sc.id = stock_count_id
      and (
        public.current_user_is_admin()
        or (public.current_user_role() = 'manager' and sc.branch_id = public.current_user_branch_id())
      )
  )
);

drop policy if exists branch_inventory_select_by_role on public.branch_inventory;
create policy branch_inventory_select_by_role
on public.branch_inventory
for select
to authenticated
using (
  public.current_user_is_admin()
  or public.current_user_role() = 'auditor'
  or branch_id = public.current_user_branch_id()
);

drop policy if exists branch_inventory_admin_manager_write on public.branch_inventory;
create policy branch_inventory_admin_manager_write
on public.branch_inventory
for all
to authenticated
using (
  public.current_user_is_admin()
  or (public.current_user_role() = 'manager' and branch_id = public.current_user_branch_id())
)
with check (
  public.current_user_is_admin()
  or (public.current_user_role() = 'manager' and branch_id = public.current_user_branch_id())
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

insert into public.inventory_batches (
  branch_id,
  product_id,
  batch_number,
  expiry_date,
  quantity_on_hand,
  unit_cost,
  received_at,
  status
)
select
  bi.branch_id,
  bi.product_id,
  'OPENING-' || b.branch_code || '-' || p.sku,
  case
    when lower(p.category) = 'bakery' then current_date + 5
    when lower(p.category) = 'dairy' then current_date + 12
    when lower(p.category) = 'grocery' then current_date + 120
    when lower(p.category) = 'health' then current_date + 300
    else null
  end,
  bi.quantity_on_hand,
  coalesce(p.cost_price, 0),
  current_date,
  case when bi.quantity_on_hand > 0 then 'active' else 'depleted' end
from public.branch_inventory bi
join public.branches b on b.id = bi.branch_id
join public.products p on p.id = bi.product_id
where bi.quantity_on_hand > 0
  and not exists (
    select 1
    from public.inventory_batches ib
    where ib.branch_id = bi.branch_id
      and ib.product_id = bi.product_id
  );

create or replace function public.inventory_sync_product_stock(p_branch_id uuid, p_product_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_quantity integer;
begin
  select coalesce(sum(quantity_on_hand), 0)::integer
  into v_quantity
  from public.inventory_batches
  where branch_id = p_branch_id
    and product_id = p_product_id
    and status = 'active';

  insert into public.branch_inventory (branch_id, product_id, quantity_on_hand, updated_at)
  values (p_branch_id, p_product_id, coalesce(v_quantity, 0), now())
  on conflict (branch_id, product_id) do update
  set quantity_on_hand = excluded.quantity_on_hand,
      updated_at = now();
end;
$$;

create or replace function public.inventory_can_manage_branch(p_branch_id uuid)
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

create or replace function public.inventory_management_get(p_branch_id uuid default null)
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
    raise exception 'Inventory management is not available for this role' using errcode = '42501';
  end if;

  if v_profile.role in ('admin', 'auditor') then
    v_effective_branch_id := p_branch_id;
  else
    v_effective_branch_id := v_profile.branch_id;
  end if;

  with visible_branches as (
    select b.*
    from public.branches b
    where b.is_active = true
      and (v_effective_branch_id is null or b.id = v_effective_branch_id)
  ),
  inventory_rows as (
    select
      bi.id,
      bi.branch_id,
      b.branch_code,
      b.name as branch_name,
      p.id as product_id,
      p.sku,
      p.barcode,
      p.name as product_name,
      p.category,
      pc.name as category_name,
      pb.name as brand_name,
      pu.name as unit_name,
      pu.abbreviation as unit_abbreviation,
      p.reorder_level,
      p.cost_price,
      p.selling_price,
      bi.quantity_on_hand,
      bi.last_counted_at,
      coalesce(batch_value.inventory_value, bi.quantity_on_hand * coalesce(p.cost_price, 0))::numeric(14, 2) as inventory_value,
      batch_value.earliest_expiry,
      coalesce(batch_value.batch_count, 0)::integer as batch_count,
      coalesce(batch_value.expiring_soon_batches, 0)::integer as expiring_soon_batches,
      coalesce(batch_value.expired_batches, 0)::integer as expired_batches,
      case
        when bi.quantity_on_hand = 0 then 'out_of_stock'
        when bi.quantity_on_hand <= p.reorder_level then 'low_stock'
        else 'in_stock'
      end as stock_status
    from public.branch_inventory bi
    join visible_branches b on b.id = bi.branch_id
    join public.products p on p.id = bi.product_id
    left join public.product_categories pc on pc.id = p.category_id
    left join public.product_brands pb on pb.id = p.brand_id
    left join public.product_units pu on pu.id = p.unit_id
    left join lateral (
      select
        count(*) filter (where ib.quantity_on_hand > 0 and ib.status = 'active')::integer as batch_count,
        min(ib.expiry_date) filter (where ib.quantity_on_hand > 0 and ib.status = 'active' and ib.expiry_date is not null) as earliest_expiry,
        count(*) filter (
          where ib.quantity_on_hand > 0
            and ib.status = 'active'
            and ib.expiry_date between current_date and current_date + 30
        )::integer as expiring_soon_batches,
        count(*) filter (
          where ib.quantity_on_hand > 0
            and ib.status = 'active'
            and ib.expiry_date < current_date
        )::integer as expired_batches,
        coalesce(sum(ib.quantity_on_hand * ib.unit_cost), 0)::numeric(14, 2) as inventory_value
      from public.inventory_batches ib
      where ib.branch_id = bi.branch_id
        and ib.product_id = bi.product_id
    ) batch_value on true
    where p.deleted_at is null
  ),
  batch_rows as (
    select
      ib.id,
      ib.branch_id,
      b.branch_code,
      b.name as branch_name,
      ib.product_id,
      p.sku,
      p.barcode,
      p.name as product_name,
      ib.product_variant_id,
      pv.variant_name,
      ib.batch_number,
      ib.expiry_date,
      ib.quantity_on_hand,
      ib.unit_cost,
      ib.received_at,
      ib.status,
      case
        when ib.quantity_on_hand = 0 then 'depleted'
        when ib.expiry_date is not null and ib.expiry_date < current_date then 'expired'
        when ib.expiry_date is not null and ib.expiry_date <= current_date + 7 then 'expires_7'
        when ib.expiry_date is not null and ib.expiry_date <= current_date + 14 then 'expires_14'
        when ib.expiry_date is not null and ib.expiry_date <= current_date + 30 then 'expires_30'
        else 'ok'
      end as expiry_status
    from public.inventory_batches ib
    join visible_branches b on b.id = ib.branch_id
    join public.products p on p.id = ib.product_id
    left join public.product_variants pv on pv.id = ib.product_variant_id
    where p.deleted_at is null
    order by
      case when ib.quantity_on_hand > 0 then 0 else 1 end,
      ib.expiry_date asc nulls last,
      p.name asc
  ),
  movement_rows as (
    select
      im.id,
      im.branch_id,
      b.branch_code,
      b.name as branch_name,
      im.product_id,
      p.sku,
      p.name as product_name,
      im.product_variant_id,
      pv.variant_name,
      im.batch_id,
      im.movement_type,
      im.quantity_delta,
      im.quantity_before,
      im.quantity_after,
      im.unit_cost,
      im.batch_number,
      im.expiry_date,
      im.reference_number,
      im.reason,
      im.created_at,
      up.full_name as created_by_name,
      up.username as created_by_username
    from public.inventory_movements im
    join visible_branches b on b.id = im.branch_id
    join public.products p on p.id = im.product_id
    left join public.product_variants pv on pv.id = im.product_variant_id
    left join public.user_profiles up on up.id = im.created_by
    order by im.created_at desc
    limit 100
  ),
  stock_count_rows as (
    select
      sc.id,
      sc.branch_id,
      b.branch_code,
      b.name as branch_name,
      sc.count_number,
      sc.status,
      sc.notes,
      sc.started_at,
      sc.posted_at,
      sc.created_at,
      creator.full_name as created_by_name,
      poster.full_name as posted_by_name,
      coalesce(items.item_count, 0)::integer as item_count,
      coalesce(items.total_variance, 0)::integer as total_variance
    from public.stock_counts sc
    join visible_branches b on b.id = sc.branch_id
    left join public.user_profiles creator on creator.id = sc.created_by
    left join public.user_profiles poster on poster.id = sc.posted_by
    left join lateral (
      select
        count(*)::integer as item_count,
        coalesce(sum(abs(sci.variance_quantity)), 0)::integer as total_variance
      from public.stock_count_items sci
      where sci.stock_count_id = sc.id
    ) items on true
    order by sc.created_at desc
    limit 50
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
      p.reorder_level,
      p.is_active,
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
    ) variants on true
    where p.deleted_at is null
      and p.is_active = true
  )
  select jsonb_build_object(
    'summary', jsonb_build_object(
      'stock_units', coalesce((select sum(quantity_on_hand) from inventory_rows), 0),
      'inventory_value', coalesce((select sum(inventory_value) from inventory_rows), 0),
      'low_stock_items', coalesce((select count(*) from inventory_rows where stock_status = 'low_stock'), 0),
      'out_of_stock_items', coalesce((select count(*) from inventory_rows where stock_status = 'out_of_stock'), 0),
      'active_batches', coalesce((select count(*) from batch_rows where quantity_on_hand > 0 and status = 'active'), 0),
      'expiring_soon_batches', coalesce((select count(*) from batch_rows where quantity_on_hand > 0 and expiry_status in ('expires_7', 'expires_14', 'expires_30')), 0),
      'expired_batches', coalesce((select count(*) from batch_rows where quantity_on_hand > 0 and expiry_status = 'expired'), 0),
      'movements', coalesce((
        select count(*)
        from public.inventory_movements im
        join visible_branches b on b.id = im.branch_id
      ), 0)
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
      from visible_branches b
    ), '[]'::jsonb),
    'products', coalesce((
      select jsonb_agg(to_jsonb(product_rows) order by name asc)
      from product_rows
    ), '[]'::jsonb),
    'inventory', coalesce((
      select jsonb_agg(to_jsonb(inventory_rows) order by branch_name asc, product_name asc)
      from inventory_rows
    ), '[]'::jsonb),
    'batches', coalesce((
      select jsonb_agg(to_jsonb(batch_rows))
      from batch_rows
    ), '[]'::jsonb),
    'expiry_alerts', coalesce((
      select jsonb_agg(to_jsonb(batch_rows) order by expiry_date asc nulls last, product_name asc)
      from batch_rows
      where quantity_on_hand > 0
        and expiry_status in ('expired', 'expires_7', 'expires_14', 'expires_30')
    ), '[]'::jsonb),
    'movements', coalesce((
      select jsonb_agg(to_jsonb(movement_rows) order by created_at desc)
      from movement_rows
    ), '[]'::jsonb),
    'stock_counts', coalesce((
      select jsonb_agg(to_jsonb(stock_count_rows) order by created_at desc)
      from stock_count_rows
    ), '[]'::jsonb),
    'generated_at', now()
  )
  into v_result;

  return v_result;
end;
$$;

create or replace function public.inventory_adjust(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor public.user_profiles;
  v_branch_id uuid := nullif(p_payload->>'branch_id', '')::uuid;
  v_product_id uuid := nullif(p_payload->>'product_id', '')::uuid;
  v_variant_id uuid := nullif(p_payload->>'product_variant_id', '')::uuid;
  v_batch_id uuid := nullif(p_payload->>'batch_id', '')::uuid;
  v_type text := coalesce(nullif(p_payload->>'movement_type', ''), 'stock_in');
  v_quantity integer := coalesce(nullif(p_payload->>'quantity', '')::integer, 0);
  v_unit_cost numeric(14, 2) := coalesce(nullif(p_payload->>'unit_cost', '')::numeric, 0);
  v_batch_number text := nullif(trim(coalesce(p_payload->>'batch_number', '')), '');
  v_expiry_date date := nullif(p_payload->>'expiry_date', '')::date;
  v_reference text := nullif(trim(coalesce(p_payload->>'reference_number', '')), '');
  v_reason text := nullif(trim(coalesce(p_payload->>'reason', '')), '');
  v_before_total integer;
  v_available integer;
  v_after_total integer;
  v_remaining integer;
  v_take integer;
  v_batch record;
  v_product public.products;
  v_branch public.branches;
begin
  v_actor := public.ensure_active_user();

  if v_branch_id is null or v_product_id is null then
    raise exception 'Branch and product are required' using errcode = '23502';
  end if;

  if public.inventory_can_manage_branch(v_branch_id) = false then
    raise exception 'You cannot adjust inventory for this branch' using errcode = '42501';
  end if;

  if v_type not in ('stock_in', 'stock_out', 'adjustment_plus', 'adjustment_minus', 'damaged', 'expired') then
    raise exception 'Invalid inventory movement type' using errcode = '22023';
  end if;

  if v_quantity <= 0 then
    raise exception 'Quantity must be greater than zero' using errcode = '23514';
  end if;

  select *
  into v_branch
  from public.branches
  where id = v_branch_id
    and is_active = true
  limit 1;

  if v_branch.id is null then
    raise exception 'Branch not found or inactive' using errcode = '02000';
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

  if v_variant_id is not null and not exists (
    select 1
    from public.product_variants pv
    where pv.id = v_variant_id
      and pv.product_id = v_product_id
      and pv.deleted_at is null
  ) then
    raise exception 'Variant does not belong to this product' using errcode = '23514';
  end if;

  select coalesce(sum(quantity_on_hand), 0)::integer
  into v_before_total
  from public.inventory_batches
  where branch_id = v_branch_id
    and product_id = v_product_id
    and status = 'active';

  select coalesce(sum(quantity_on_hand), 0)::integer
  into v_available
  from public.inventory_batches
  where branch_id = v_branch_id
    and product_id = v_product_id
    and (v_variant_id is null or product_variant_id = v_variant_id)
    and status = 'active';

  if v_type in ('stock_in', 'adjustment_plus') then
    if v_unit_cost = 0 then
      v_unit_cost := coalesce(v_product.cost_price, 0);
    end if;

    if v_batch_number is null then
      v_batch_number := case
        when v_type = 'stock_in' then 'IN-'
        else 'ADJ-'
      end || to_char(now(), 'YYYYMMDDHH24MISS');
    end if;

    if v_batch_id is not null then
      update public.inventory_batches
      set quantity_on_hand = quantity_on_hand + v_quantity,
          unit_cost = v_unit_cost,
          batch_number = coalesce(v_batch_number, batch_number),
          expiry_date = coalesce(v_expiry_date, expiry_date),
          status = 'active'
      where id = v_batch_id
        and branch_id = v_branch_id
        and product_id = v_product_id
      returning id into v_batch_id;

      if not found then
        raise exception 'Batch not found for this branch and product' using errcode = '02000';
      end if;
    else
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
        v_product_id,
        v_variant_id,
        v_batch_number,
        v_expiry_date,
        v_quantity,
        v_unit_cost,
        coalesce(nullif(p_payload->>'received_at', '')::date, current_date),
        'active'
      )
      returning id into v_batch_id;
    end if;

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
      v_product_id,
      v_variant_id,
      v_batch_id,
      v_type,
      v_quantity,
      v_before_total,
      v_after_total,
      v_unit_cost,
      v_batch_number,
      v_expiry_date,
      v_reference,
      v_reason,
      v_actor.id
    );
  else
    if v_available < v_quantity then
      raise exception 'Insufficient stock for this adjustment' using errcode = '23514';
    end if;

    v_remaining := v_quantity;

    if v_batch_id is not null then
      select *
      into v_batch
      from public.inventory_batches
      where id = v_batch_id
        and branch_id = v_branch_id
        and product_id = v_product_id
        and (v_variant_id is null or product_variant_id = v_variant_id)
        and status = 'active'
      for update;

      if not found then
        raise exception 'Batch not found for this branch and product' using errcode = '02000';
      end if;

      if v_batch.quantity_on_hand < v_quantity then
        raise exception 'Selected batch does not have enough stock' using errcode = '23514';
      end if;

      update public.inventory_batches
      set quantity_on_hand = quantity_on_hand - v_quantity,
          status = case
            when quantity_on_hand - v_quantity = 0 then
              case when v_type = 'damaged' then 'damaged' when v_type = 'expired' then 'expired' else 'depleted' end
            else 'active'
          end
      where id = v_batch.id;

      v_after_total := v_before_total - v_quantity;

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
        v_product_id,
        v_batch.product_variant_id,
        v_batch.id,
        v_type,
        -v_quantity,
        v_before_total,
        v_after_total,
        v_batch.unit_cost,
        v_batch.batch_number,
        v_batch.expiry_date,
        v_reference,
        v_reason,
        v_actor.id
      );
    else
      for v_batch in
        select *
        from public.inventory_batches
        where branch_id = v_branch_id
          and product_id = v_product_id
          and (v_variant_id is null or product_variant_id = v_variant_id)
          and status = 'active'
          and quantity_on_hand > 0
        order by expiry_date asc nulls last, received_at asc, created_at asc
        for update
      loop
        exit when v_remaining <= 0;

        v_take := least(v_remaining, v_batch.quantity_on_hand);
        v_after_total := v_before_total - v_take;

        update public.inventory_batches
        set quantity_on_hand = quantity_on_hand - v_take,
            status = case
              when quantity_on_hand - v_take = 0 then
                case when v_type = 'damaged' then 'damaged' when v_type = 'expired' then 'expired' else 'depleted' end
              else 'active'
            end
        where id = v_batch.id;

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
          v_product_id,
          v_batch.product_variant_id,
          v_batch.id,
          v_type,
          -v_take,
          v_before_total,
          v_after_total,
          v_batch.unit_cost,
          v_batch.batch_number,
          v_batch.expiry_date,
          v_reference,
          v_reason,
          v_actor.id
        );

        v_before_total := v_after_total;
        v_remaining := v_remaining - v_take;
      end loop;

      if v_remaining > 0 then
        raise exception 'Insufficient stock for this adjustment' using errcode = '23514';
      end if;
    end if;
  end if;

  perform public.inventory_sync_product_stock(v_branch_id, v_product_id);

  perform public.log_activity(
    'inventory.adjusted',
    'inventory',
    v_branch_id::text,
    jsonb_build_object(
      'branch_id', v_branch_id,
      'product_id', v_product_id,
      'movement_type', v_type,
      'quantity', v_quantity,
      'reference_number', v_reference
    ),
    v_actor.id
  );

  return public.inventory_management_get(null);
end;
$$;

create or replace function public.inventory_post_stock_count(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor public.user_profiles;
  v_branch_id uuid := nullif(p_payload->>'branch_id', '')::uuid;
  v_notes text := nullif(trim(coalesce(p_payload->>'notes', '')), '');
  v_items jsonb := p_payload->'items';
  v_item jsonb;
  v_stock_count_id uuid;
  v_count_number text;
  v_product_id uuid;
  v_variant_id uuid;
  v_counted integer;
  v_system integer;
  v_variance integer;
begin
  v_actor := public.ensure_active_user();

  if v_branch_id is null then
    raise exception 'Branch is required' using errcode = '23502';
  end if;

  if public.inventory_can_manage_branch(v_branch_id) = false then
    raise exception 'You cannot post stock counts for this branch' using errcode = '42501';
  end if;

  if v_items is null or jsonb_typeof(v_items) <> 'array' or jsonb_array_length(v_items) = 0 then
    raise exception 'At least one counted item is required' using errcode = '23502';
  end if;

  v_count_number := 'SC-' || to_char(now(), 'YYYYMMDD-HH24MISS-') || upper(left(replace(gen_random_uuid()::text, '-', ''), 6));

  insert into public.stock_counts (
    branch_id,
    count_number,
    status,
    notes,
    created_by,
    posted_by,
    posted_at
  )
  values (
    v_branch_id,
    v_count_number,
    'posted',
    v_notes,
    v_actor.id,
    v_actor.id,
    now()
  )
  returning id into v_stock_count_id;

  for v_item in select value from jsonb_array_elements(v_items)
  loop
    v_product_id := nullif(v_item->>'product_id', '')::uuid;
    v_variant_id := nullif(v_item->>'product_variant_id', '')::uuid;
    v_counted := coalesce(nullif(v_item->>'counted_quantity', '')::integer, 0);

    if v_product_id is null then
      raise exception 'Every count row must have a product' using errcode = '23502';
    end if;

    if v_counted < 0 then
      raise exception 'Counted quantity cannot be negative' using errcode = '23514';
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

    select coalesce(sum(quantity_on_hand), 0)::integer
    into v_system
    from public.inventory_batches
    where branch_id = v_branch_id
      and product_id = v_product_id
      and (v_variant_id is null or product_variant_id = v_variant_id)
      and status = 'active';

    v_variance := v_counted - v_system;

    insert into public.stock_count_items (
      stock_count_id,
      product_id,
      product_variant_id,
      system_quantity,
      counted_quantity,
      variance_quantity
    )
    values (
      v_stock_count_id,
      v_product_id,
      v_variant_id,
      v_system,
      v_counted,
      v_variance
    );

    if v_variance > 0 then
      perform public.inventory_adjust(jsonb_build_object(
        'branch_id', v_branch_id,
        'product_id', v_product_id,
        'product_variant_id', v_variant_id,
        'movement_type', 'adjustment_plus',
        'quantity', v_variance,
        'batch_number', 'COUNT-' || v_count_number,
        'reference_number', v_count_number,
        'reason', 'Physical stock count gain'
      ));
    elsif v_variance < 0 then
      perform public.inventory_adjust(jsonb_build_object(
        'branch_id', v_branch_id,
        'product_id', v_product_id,
        'product_variant_id', v_variant_id,
        'movement_type', 'adjustment_minus',
        'quantity', abs(v_variance),
        'reference_number', v_count_number,
        'reason', 'Physical stock count loss'
      ));
    end if;

    update public.branch_inventory
    set last_counted_at = now()
    where branch_id = v_branch_id
      and product_id = v_product_id;
  end loop;

  perform public.log_activity(
    'inventory.stock_count_posted',
    'stock_count',
    v_stock_count_id::text,
    jsonb_build_object('branch_id', v_branch_id, 'count_number', v_count_number),
    v_actor.id
  );

  return public.inventory_management_get(null);
end;
$$;

revoke all on function public.inventory_sync_product_stock(uuid, uuid) from public;
revoke all on function public.inventory_can_manage_branch(uuid) from public;
revoke all on function public.inventory_management_get(uuid) from public;
revoke all on function public.inventory_adjust(jsonb) from public;
revoke all on function public.inventory_post_stock_count(jsonb) from public;
grant execute on function public.inventory_management_get(uuid) to authenticated;
grant execute on function public.inventory_adjust(jsonb) to authenticated;
grant execute on function public.inventory_post_stock_count(jsonb) to authenticated;

notify pgrst, 'reload schema';
