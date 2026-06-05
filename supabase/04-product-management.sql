-- MODULE 4: PRODUCT MANAGEMENT
-- Run after:
-- 1. supabase/00-reset-public-schema.sql
-- 2. supabase/01-dashboard-module.sql
-- 3. supabase/02-auth-and-branch-management.sql
-- 4. supabase/03-user-role-management.sql
--
-- Scope:
-- - Products, categories, brands
-- - SKU/barcode
-- - Units
-- - Product variants
-- - VATable, VAT-exempt, zero-rated, non-VAT item tagging

create extension if not exists pgcrypto;

create table if not exists public.product_categories (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null unique,
  description text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.product_brands (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null unique,
  description text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.product_units (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null unique,
  abbreviation text not null,
  unit_type text not null default 'piece' check (unit_type in ('piece', 'pack', 'box', 'weight', 'volume', 'service')),
  allows_decimal boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.products
  add column if not exists description text,
  add column if not exists category_id uuid references public.product_categories(id) on delete set null,
  add column if not exists brand_id uuid references public.product_brands(id) on delete set null,
  add column if not exists unit_id uuid references public.product_units(id) on delete set null,
  add column if not exists cost_price numeric(14, 2) not null default 0 check (cost_price >= 0),
  add column if not exists selling_price numeric(14, 2) not null default 0 check (selling_price >= 0),
  add column if not exists tax_type text not null default 'vatable',
  add column if not exists vat_rate numeric(5, 2) not null default 12.00 check (vat_rate >= 0 and vat_rate <= 100),
  add column if not exists tax_inclusive boolean not null default true,
  add column if not exists has_variants boolean not null default false,
  add column if not exists deleted_at timestamptz,
  add column if not exists updated_at timestamptz not null default now();

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'products_tax_type_check'
      and conrelid = 'public.products'::regclass
  ) then
    alter table public.products
      add constraint products_tax_type_check
      check (tax_type in ('vatable', 'vat_exempt', 'zero_rated', 'non_vat'));
  end if;
end;
$$;

create table if not exists public.product_variants (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete cascade,
  variant_name text not null,
  sku text not null unique,
  barcode text unique,
  unit_id uuid references public.product_units(id) on delete set null,
  cost_price numeric(14, 2) not null default 0 check (cost_price >= 0),
  selling_price numeric(14, 2) not null default 0 check (selling_price >= 0),
  is_active boolean not null default true,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_product_categories_active on public.product_categories(is_active, name);
create index if not exists idx_product_brands_active on public.product_brands(is_active, name);
create index if not exists idx_product_units_active on public.product_units(is_active, name);
create index if not exists idx_products_category on public.products(category_id);
create index if not exists idx_products_brand on public.products(brand_id);
create index if not exists idx_products_unit on public.products(unit_id);
create index if not exists idx_products_tax_type on public.products(tax_type);
create index if not exists idx_products_active on public.products(is_active, deleted_at);
create index if not exists idx_product_variants_product on public.product_variants(product_id, is_active);

drop trigger if exists set_product_categories_updated_at on public.product_categories;
create trigger set_product_categories_updated_at
before update on public.product_categories
for each row execute function public.set_updated_at();

drop trigger if exists set_product_brands_updated_at on public.product_brands;
create trigger set_product_brands_updated_at
before update on public.product_brands
for each row execute function public.set_updated_at();

drop trigger if exists set_product_units_updated_at on public.product_units;
create trigger set_product_units_updated_at
before update on public.product_units
for each row execute function public.set_updated_at();

drop trigger if exists set_products_updated_at on public.products;
create trigger set_products_updated_at
before update on public.products
for each row execute function public.set_updated_at();

drop trigger if exists set_product_variants_updated_at on public.product_variants;
create trigger set_product_variants_updated_at
before update on public.product_variants
for each row execute function public.set_updated_at();

alter table public.product_categories enable row level security;
alter table public.product_brands enable row level security;
alter table public.product_units enable row level security;
alter table public.product_variants enable row level security;

drop policy if exists product_categories_select_by_role on public.product_categories;
create policy product_categories_select_by_role
on public.product_categories
for select
to authenticated
using (public.current_user_role() in ('admin', 'manager', 'cashier', 'auditor'));

drop policy if exists product_categories_admin_write on public.product_categories;
create policy product_categories_admin_write
on public.product_categories
for all
to authenticated
using (public.current_user_is_admin())
with check (public.current_user_is_admin());

drop policy if exists product_brands_select_by_role on public.product_brands;
create policy product_brands_select_by_role
on public.product_brands
for select
to authenticated
using (public.current_user_role() in ('admin', 'manager', 'cashier', 'auditor'));

drop policy if exists product_brands_admin_write on public.product_brands;
create policy product_brands_admin_write
on public.product_brands
for all
to authenticated
using (public.current_user_is_admin())
with check (public.current_user_is_admin());

drop policy if exists product_units_select_by_role on public.product_units;
create policy product_units_select_by_role
on public.product_units
for select
to authenticated
using (public.current_user_role() in ('admin', 'manager', 'cashier', 'auditor'));

drop policy if exists product_units_admin_write on public.product_units;
create policy product_units_admin_write
on public.product_units
for all
to authenticated
using (public.current_user_is_admin())
with check (public.current_user_is_admin());

drop policy if exists products_select_by_role on public.products;
create policy products_select_by_role
on public.products
for select
to authenticated
using (public.current_user_role() in ('admin', 'manager', 'cashier', 'auditor') and deleted_at is null);

drop policy if exists products_admin_write on public.products;
create policy products_admin_write
on public.products
for all
to authenticated
using (public.current_user_is_admin())
with check (public.current_user_is_admin());

drop policy if exists product_variants_select_by_role on public.product_variants;
create policy product_variants_select_by_role
on public.product_variants
for select
to authenticated
using (public.current_user_role() in ('admin', 'manager', 'cashier', 'auditor') and deleted_at is null);

drop policy if exists product_variants_admin_write on public.product_variants;
create policy product_variants_admin_write
on public.product_variants
for all
to authenticated
using (public.current_user_is_admin())
with check (public.current_user_is_admin());

insert into public.product_categories (code, name, description)
select
  upper(left(regexp_replace(category, '[^A-Za-z0-9]+', '-', 'g'), 24)),
  category,
  'Migrated from Module 1 product category'
from (
  select distinct coalesce(nullif(trim(category), ''), 'General') as category
  from public.products
) existing_categories
on conflict (name) do nothing;

insert into public.product_categories (code, name, description)
values
  ('GENERAL', 'General', 'Default product category'),
  ('GROCERY', 'Grocery', 'Grocery and dry goods'),
  ('HEALTH', 'Health', 'Health and personal care'),
  ('DAIRY', 'Dairy', 'Dairy products'),
  ('BAKERY', 'Bakery', 'Bakery items')
on conflict (name) do nothing;

insert into public.product_brands (code, name, description)
values
  ('UNBRANDED', 'Unbranded', 'Default brand'),
  ('HOUSE', 'House Brand', 'Company-owned private label')
on conflict (name) do nothing;

insert into public.product_units (code, name, abbreviation, unit_type, allows_decimal)
values
  ('PCS', 'Piece', 'pc', 'piece', false),
  ('PACK', 'Pack', 'pack', 'pack', false),
  ('BOX', 'Box', 'box', 'box', false),
  ('KG', 'Kilogram', 'kg', 'weight', true),
  ('L', 'Liter', 'L', 'volume', true)
on conflict (name) do nothing;

update public.products p
set category_id = pc.id,
    category = pc.name
from public.product_categories pc
where p.category_id is null
  and lower(pc.name) = lower(coalesce(nullif(p.category, ''), 'General'));

update public.products p
set category_id = pc.id,
    category = pc.name
from public.product_categories pc
where p.category_id is null
  and pc.name = 'General';

update public.products p
set brand_id = pb.id
from public.product_brands pb
where p.brand_id is null
  and pb.name = 'Unbranded';

update public.products p
set unit_id = pu.id
from public.product_units pu
where p.unit_id is null
  and pu.code = 'PCS';

update public.products
set selling_price = case sku
    when 'SKU-COFFEE-250' then 245.00
    when 'SKU-RICE-5KG' then 425.00
    when 'SKU-ALCOHOL-500' then 89.00
    when 'SKU-MILK-1L' then 115.00
    when 'SKU-BREAD' then 72.00
    else selling_price
  end,
  cost_price = case sku
    when 'SKU-COFFEE-250' then 180.00
    when 'SKU-RICE-5KG' then 340.00
    when 'SKU-ALCOHOL-500' then 55.00
    when 'SKU-MILK-1L' then 82.00
    when 'SKU-BREAD' then 48.00
    else cost_price
  end
where selling_price = 0;

create or replace function public.product_admin_required()
returns public.user_profiles
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_profile public.user_profiles;
begin
  v_profile := public.ensure_active_user();

  if v_profile.role <> 'admin' then
    raise exception 'Only admins can manage products' using errcode = '42501';
  end if;

  return v_profile;
end;
$$;

create or replace function public.product_management_get()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.user_profiles;
  v_result jsonb;
begin
  v_profile := public.ensure_active_user();

  if v_profile.role not in ('admin', 'manager', 'cashier', 'auditor') then
    raise exception 'Product management is not available for this role' using errcode = '42501';
  end if;

  with product_rows as (
    select
      p.id,
      p.sku,
      p.barcode,
      p.name,
      p.description,
      p.category,
      p.category_id,
      pc.name as category_name,
      p.brand_id,
      pb.name as brand_name,
      p.unit_id,
      pu.name as unit_name,
      pu.abbreviation as unit_abbreviation,
      p.cost_price,
      p.selling_price,
      p.tax_type,
      p.vat_rate,
      p.tax_inclusive,
      p.reorder_level,
      p.has_variants,
      p.is_active,
      p.created_at,
      p.updated_at,
      coalesce(stock.stock_units, 0)::integer as stock_units,
      coalesce(variant_totals.variant_count, 0)::integer as variant_count,
      coalesce(variants.variants, '[]'::jsonb) as variants
    from public.products p
    left join public.product_categories pc on pc.id = p.category_id
    left join public.product_brands pb on pb.id = p.brand_id
    left join public.product_units pu on pu.id = p.unit_id
    left join lateral (
      select coalesce(sum(quantity_on_hand), 0)::integer as stock_units
      from public.branch_inventory bi
      where bi.product_id = p.id
    ) stock on true
    left join lateral (
      select count(*)::integer as variant_count
      from public.product_variants pv
      where pv.product_id = p.id
        and pv.deleted_at is null
    ) variant_totals on true
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
  )
  select jsonb_build_object(
    'summary', jsonb_build_object(
      'total_products', coalesce((select count(*) from product_rows), 0),
      'active_products', coalesce((select count(*) from product_rows where is_active = true), 0),
      'categories', coalesce((select count(*) from public.product_categories where is_active = true), 0),
      'brands', coalesce((select count(*) from public.product_brands where is_active = true), 0),
      'units', coalesce((select count(*) from public.product_units where is_active = true), 0),
      'vatable_items', coalesce((select count(*) from product_rows where tax_type = 'vatable'), 0),
      'vat_exempt_items', coalesce((select count(*) from product_rows where tax_type = 'vat_exempt'), 0),
      'zero_rated_items', coalesce((select count(*) from product_rows where tax_type = 'zero_rated'), 0),
      'non_vat_items', coalesce((select count(*) from product_rows where tax_type = 'non_vat'), 0)
    ),
    'products', coalesce((
      select jsonb_agg(to_jsonb(product_rows) order by is_active desc, name asc)
      from product_rows
    ), '[]'::jsonb),
    'categories', coalesce((
      select jsonb_agg(to_jsonb(pc) order by is_active desc, name asc)
      from public.product_categories pc
    ), '[]'::jsonb),
    'brands', coalesce((
      select jsonb_agg(to_jsonb(pb) order by is_active desc, name asc)
      from public.product_brands pb
    ), '[]'::jsonb),
    'units', coalesce((
      select jsonb_agg(to_jsonb(pu) order by is_active desc, name asc)
      from public.product_units pu
    ), '[]'::jsonb),
    'generated_at', now()
  )
  into v_result;

  return v_result;
end;
$$;

create or replace function public.product_replace_variants(p_product_id uuid, p_variants jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_variant jsonb;
  v_variants jsonb := p_variants;
  v_variant_id uuid;
  v_unit_id uuid;
  v_seen uuid[] := array[]::uuid[];
  v_sku text;
  v_name text;
begin
  if v_variants is null or jsonb_typeof(v_variants) <> 'array' then
    v_variants := '[]'::jsonb;
  end if;

  for v_variant in select value from jsonb_array_elements(v_variants)
  loop
    v_name := trim(coalesce(v_variant->>'variant_name', ''));
    v_sku := upper(trim(coalesce(v_variant->>'sku', '')));
    v_variant_id := nullif(v_variant->>'id', '')::uuid;
    v_unit_id := nullif(v_variant->>'unit_id', '')::uuid;

    if v_name = '' and v_sku = '' then
      continue;
    end if;

    if v_name = '' or v_sku = '' then
      raise exception 'Variant name and SKU are required' using errcode = '23502';
    end if;

    if v_variant_id is null then
      insert into public.product_variants (
        product_id,
        variant_name,
        sku,
        barcode,
        unit_id,
        cost_price,
        selling_price,
        is_active,
        deleted_at
      )
      values (
        p_product_id,
        v_name,
        v_sku,
        nullif(trim(coalesce(v_variant->>'barcode', '')), ''),
        v_unit_id,
        coalesce(nullif(v_variant->>'cost_price', '')::numeric, 0),
        coalesce(nullif(v_variant->>'selling_price', '')::numeric, 0),
        coalesce((v_variant->>'is_active')::boolean, true),
        null
      )
      returning id into v_variant_id;
    else
      update public.product_variants
      set variant_name = v_name,
          sku = v_sku,
          barcode = nullif(trim(coalesce(v_variant->>'barcode', '')), ''),
          unit_id = v_unit_id,
          cost_price = coalesce(nullif(v_variant->>'cost_price', '')::numeric, 0),
          selling_price = coalesce(nullif(v_variant->>'selling_price', '')::numeric, 0),
          is_active = coalesce((v_variant->>'is_active')::boolean, true),
          deleted_at = null
      where id = v_variant_id
        and product_id = p_product_id;

      if not found then
        insert into public.product_variants (
          id,
          product_id,
          variant_name,
          sku,
          barcode,
          unit_id,
          cost_price,
          selling_price,
          is_active,
          deleted_at
        )
        values (
          v_variant_id,
          p_product_id,
          v_name,
          v_sku,
          nullif(trim(coalesce(v_variant->>'barcode', '')), ''),
          v_unit_id,
          coalesce(nullif(v_variant->>'cost_price', '')::numeric, 0),
          coalesce(nullif(v_variant->>'selling_price', '')::numeric, 0),
          coalesce((v_variant->>'is_active')::boolean, true),
          null
        );
      end if;
    end if;

    v_seen := array_append(v_seen, v_variant_id);
  end loop;

  update public.product_variants
  set is_active = false,
      deleted_at = now()
  where product_id = p_product_id
    and deleted_at is null
    and (
      array_length(v_seen, 1) is null
      or id <> all(v_seen)
    );

  update public.products
  set has_variants = exists (
    select 1
    from public.product_variants pv
    where pv.product_id = p_product_id
      and pv.deleted_at is null
  )
  where id = p_product_id;
end;
$$;

create or replace function public.product_create(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor public.user_profiles;
  v_product_id uuid;
  v_category_id uuid := nullif(p_payload->>'category_id', '')::uuid;
  v_brand_id uuid := nullif(p_payload->>'brand_id', '')::uuid;
  v_unit_id uuid := nullif(p_payload->>'unit_id', '')::uuid;
  v_category_name text;
  v_name text := trim(coalesce(p_payload->>'name', ''));
  v_sku text := upper(trim(coalesce(p_payload->>'sku', '')));
  v_barcode text := trim(coalesce(p_payload->>'barcode', ''));
  v_tax_type text := coalesce(nullif(p_payload->>'tax_type', ''), 'vatable');
begin
  v_actor := public.product_admin_required();

  if v_name = '' or v_sku = '' or v_barcode = '' then
    raise exception 'Product name, SKU, and barcode are required' using errcode = '23502';
  end if;

  if v_category_id is null or v_brand_id is null or v_unit_id is null then
    raise exception 'Category, brand, and unit are required' using errcode = '23502';
  end if;

  if v_tax_type not in ('vatable', 'vat_exempt', 'zero_rated', 'non_vat') then
    raise exception 'Invalid tax type' using errcode = '22023';
  end if;

  select name
  into v_category_name
  from public.product_categories
  where id = v_category_id
  limit 1;

  if v_category_name is null then
    raise exception 'Category not found' using errcode = '02000';
  end if;

  insert into public.products (
    sku,
    barcode,
    name,
    description,
    category,
    category_id,
    brand_id,
    unit_id,
    cost_price,
    selling_price,
    tax_type,
    vat_rate,
    tax_inclusive,
    reorder_level,
    is_active,
    deleted_at
  )
  values (
    v_sku,
    v_barcode,
    v_name,
    nullif(trim(coalesce(p_payload->>'description', '')), ''),
    v_category_name,
    v_category_id,
    v_brand_id,
    v_unit_id,
    coalesce(nullif(p_payload->>'cost_price', '')::numeric, 0),
    coalesce(nullif(p_payload->>'selling_price', '')::numeric, 0),
    v_tax_type,
    coalesce(nullif(p_payload->>'vat_rate', '')::numeric, case when v_tax_type = 'vatable' then 12 else 0 end),
    coalesce((p_payload->>'tax_inclusive')::boolean, true),
    coalesce(nullif(p_payload->>'reorder_level', '')::integer, 0),
    coalesce((p_payload->>'is_active')::boolean, true),
    null
  )
  returning id into v_product_id;

  perform public.product_replace_variants(v_product_id, p_payload->'variants');

  perform public.log_activity(
    'product.created',
    'product',
    v_product_id::text,
    jsonb_build_object('sku', v_sku, 'barcode', v_barcode, 'name', v_name),
    v_actor.id
  );

  return public.product_management_get();
end;
$$;

create or replace function public.product_update(p_product_id uuid, p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor public.user_profiles;
  v_category_id uuid := nullif(p_payload->>'category_id', '')::uuid;
  v_brand_id uuid := nullif(p_payload->>'brand_id', '')::uuid;
  v_unit_id uuid := nullif(p_payload->>'unit_id', '')::uuid;
  v_category_name text;
  v_name text := trim(coalesce(p_payload->>'name', ''));
  v_sku text := upper(trim(coalesce(p_payload->>'sku', '')));
  v_barcode text := trim(coalesce(p_payload->>'barcode', ''));
  v_tax_type text := coalesce(nullif(p_payload->>'tax_type', ''), 'vatable');
begin
  v_actor := public.product_admin_required();

  if p_product_id is null then
    raise exception 'Product id is required' using errcode = '23502';
  end if;

  if v_name = '' or v_sku = '' or v_barcode = '' then
    raise exception 'Product name, SKU, and barcode are required' using errcode = '23502';
  end if;

  if v_category_id is null or v_brand_id is null or v_unit_id is null then
    raise exception 'Category, brand, and unit are required' using errcode = '23502';
  end if;

  if v_tax_type not in ('vatable', 'vat_exempt', 'zero_rated', 'non_vat') then
    raise exception 'Invalid tax type' using errcode = '22023';
  end if;

  select name
  into v_category_name
  from public.product_categories
  where id = v_category_id
  limit 1;

  if v_category_name is null then
    raise exception 'Category not found' using errcode = '02000';
  end if;

  update public.products
  set sku = v_sku,
      barcode = v_barcode,
      name = v_name,
      description = nullif(trim(coalesce(p_payload->>'description', '')), ''),
      category = v_category_name,
      category_id = v_category_id,
      brand_id = v_brand_id,
      unit_id = v_unit_id,
      cost_price = coalesce(nullif(p_payload->>'cost_price', '')::numeric, 0),
      selling_price = coalesce(nullif(p_payload->>'selling_price', '')::numeric, 0),
      tax_type = v_tax_type,
      vat_rate = coalesce(nullif(p_payload->>'vat_rate', '')::numeric, case when v_tax_type = 'vatable' then 12 else 0 end),
      tax_inclusive = coalesce((p_payload->>'tax_inclusive')::boolean, true),
      reorder_level = coalesce(nullif(p_payload->>'reorder_level', '')::integer, 0),
      is_active = coalesce((p_payload->>'is_active')::boolean, true),
      deleted_at = null
  where id = p_product_id;

  if not found then
    raise exception 'Product not found' using errcode = '02000';
  end if;

  perform public.product_replace_variants(p_product_id, p_payload->'variants');

  perform public.log_activity(
    'product.updated',
    'product',
    p_product_id::text,
    jsonb_build_object('sku', v_sku, 'barcode', v_barcode, 'name', v_name),
    v_actor.id
  );

  return public.product_management_get();
end;
$$;

create or replace function public.product_delete(p_product_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor public.user_profiles;
  v_product public.products;
begin
  v_actor := public.product_admin_required();

  select *
  into v_product
  from public.products
  where id = p_product_id
  limit 1;

  if v_product.id is null then
    raise exception 'Product not found' using errcode = '02000';
  end if;

  update public.products
  set is_active = false,
      deleted_at = now()
  where id = p_product_id;

  update public.product_variants
  set is_active = false,
      deleted_at = now()
  where product_id = p_product_id
    and deleted_at is null;

  perform public.log_activity(
    'product.deleted',
    'product',
    p_product_id::text,
    jsonb_build_object('sku', v_product.sku, 'barcode', v_product.barcode, 'name', v_product.name),
    v_actor.id
  );

  return public.product_management_get();
end;
$$;

create or replace function public.product_category_save(p_category_id uuid, p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor public.user_profiles;
  v_name text := trim(coalesce(p_payload->>'name', ''));
  v_code text := upper(trim(coalesce(p_payload->>'code', '')));
begin
  v_actor := public.product_admin_required();

  if v_name = '' then
    raise exception 'Category name is required' using errcode = '23502';
  end if;

  if v_code = '' then
    v_code := upper(left(regexp_replace(v_name, '[^A-Za-z0-9]+', '-', 'g'), 24));
  end if;

  if p_category_id is null then
    insert into public.product_categories (code, name, description, is_active)
    values (
      v_code,
      v_name,
      nullif(trim(coalesce(p_payload->>'description', '')), ''),
      coalesce((p_payload->>'is_active')::boolean, true)
    );
  else
    update public.product_categories
    set code = v_code,
        name = v_name,
        description = nullif(trim(coalesce(p_payload->>'description', '')), ''),
        is_active = coalesce((p_payload->>'is_active')::boolean, true)
    where id = p_category_id;

    if not found then
      raise exception 'Category not found' using errcode = '02000';
    end if;

    update public.products
    set category = v_name
    where category_id = p_category_id;
  end if;

  perform public.log_activity('product.category_saved', 'product_category', coalesce(p_category_id::text, v_code), jsonb_build_object('name', v_name), v_actor.id);

  return public.product_management_get();
end;
$$;

create or replace function public.product_brand_save(p_brand_id uuid, p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor public.user_profiles;
  v_name text := trim(coalesce(p_payload->>'name', ''));
  v_code text := upper(trim(coalesce(p_payload->>'code', '')));
begin
  v_actor := public.product_admin_required();

  if v_name = '' then
    raise exception 'Brand name is required' using errcode = '23502';
  end if;

  if v_code = '' then
    v_code := upper(left(regexp_replace(v_name, '[^A-Za-z0-9]+', '-', 'g'), 24));
  end if;

  if p_brand_id is null then
    insert into public.product_brands (code, name, description, is_active)
    values (
      v_code,
      v_name,
      nullif(trim(coalesce(p_payload->>'description', '')), ''),
      coalesce((p_payload->>'is_active')::boolean, true)
    );
  else
    update public.product_brands
    set code = v_code,
        name = v_name,
        description = nullif(trim(coalesce(p_payload->>'description', '')), ''),
        is_active = coalesce((p_payload->>'is_active')::boolean, true)
    where id = p_brand_id;

    if not found then
      raise exception 'Brand not found' using errcode = '02000';
    end if;
  end if;

  perform public.log_activity('product.brand_saved', 'product_brand', coalesce(p_brand_id::text, v_code), jsonb_build_object('name', v_name), v_actor.id);

  return public.product_management_get();
end;
$$;

create or replace function public.product_unit_save(p_unit_id uuid, p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor public.user_profiles;
  v_name text := trim(coalesce(p_payload->>'name', ''));
  v_code text := upper(trim(coalesce(p_payload->>'code', '')));
  v_abbreviation text := trim(coalesce(p_payload->>'abbreviation', ''));
  v_unit_type text := coalesce(nullif(p_payload->>'unit_type', ''), 'piece');
begin
  v_actor := public.product_admin_required();

  if v_name = '' or v_abbreviation = '' then
    raise exception 'Unit name and abbreviation are required' using errcode = '23502';
  end if;

  if v_code = '' then
    v_code := upper(left(regexp_replace(v_name, '[^A-Za-z0-9]+', '-', 'g'), 24));
  end if;

  if v_unit_type not in ('piece', 'pack', 'box', 'weight', 'volume', 'service') then
    raise exception 'Invalid unit type' using errcode = '22023';
  end if;

  if p_unit_id is null then
    insert into public.product_units (code, name, abbreviation, unit_type, allows_decimal, is_active)
    values (
      v_code,
      v_name,
      v_abbreviation,
      v_unit_type,
      coalesce((p_payload->>'allows_decimal')::boolean, false),
      coalesce((p_payload->>'is_active')::boolean, true)
    );
  else
    update public.product_units
    set code = v_code,
        name = v_name,
        abbreviation = v_abbreviation,
        unit_type = v_unit_type,
        allows_decimal = coalesce((p_payload->>'allows_decimal')::boolean, false),
        is_active = coalesce((p_payload->>'is_active')::boolean, true)
    where id = p_unit_id;

    if not found then
      raise exception 'Unit not found' using errcode = '02000';
    end if;
  end if;

  perform public.log_activity('product.unit_saved', 'product_unit', coalesce(p_unit_id::text, v_code), jsonb_build_object('name', v_name), v_actor.id);

  return public.product_management_get();
end;
$$;

revoke all on function public.product_admin_required() from public;
revoke all on function public.product_management_get() from public;
revoke all on function public.product_replace_variants(uuid, jsonb) from public;
revoke all on function public.product_create(jsonb) from public;
revoke all on function public.product_update(uuid, jsonb) from public;
revoke all on function public.product_delete(uuid) from public;
revoke all on function public.product_category_save(uuid, jsonb) from public;
revoke all on function public.product_brand_save(uuid, jsonb) from public;
revoke all on function public.product_unit_save(uuid, jsonb) from public;
grant execute on function public.product_management_get() to authenticated;
grant execute on function public.product_create(jsonb) to authenticated;
grant execute on function public.product_update(uuid, jsonb) to authenticated;
grant execute on function public.product_delete(uuid) to authenticated;
grant execute on function public.product_category_save(uuid, jsonb) to authenticated;
grant execute on function public.product_brand_save(uuid, jsonb) to authenticated;
grant execute on function public.product_unit_save(uuid, jsonb) to authenticated;

notify pgrst, 'reload schema';
