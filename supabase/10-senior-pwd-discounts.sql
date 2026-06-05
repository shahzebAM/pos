-- MODULE 10: SENIOR CITIZEN & PWD DISCOUNT MODULE
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
--
-- Scope:
-- - Senior Citizen and PWD checkout capture
-- - OSCA/PWD ID number, name, booklet/reference capture
-- - 20% discount with VAT exemption for regular eligible items
-- - 5% special discount for basic necessities / prime commodities where tagged
-- - Separate claim ledger and Senior/PWD sales report
-- - Product eligibility setup

create extension if not exists pgcrypto;

alter table public.products
  add column if not exists senior_pwd_discount_category text not null default 'regular_20';

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'products_senior_pwd_discount_category_check'
      and conrelid = 'public.products'::regclass
  ) then
    alter table public.products
      add constraint products_senior_pwd_discount_category_check
      check (senior_pwd_discount_category in ('regular_20', 'basic_necessity_5', 'not_eligible'));
  end if;
end;
$$;

alter table public.sales_orders
  add column if not exists statutory_discount_type text not null default 'none',
  add column if not exists statutory_discount_amount numeric(14, 2) not null default 0,
  add column if not exists statutory_vat_exempt_amount numeric(14, 2) not null default 0,
  add column if not exists statutory_special_discount_amount numeric(14, 2) not null default 0,
  add column if not exists beneficiary_name text,
  add column if not exists beneficiary_id_number text,
  add column if not exists beneficiary_id_type text,
  add column if not exists beneficiary_booklet_number text;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'sales_orders_statutory_discount_type_check'
      and conrelid = 'public.sales_orders'::regclass
  ) then
    alter table public.sales_orders
      add constraint sales_orders_statutory_discount_type_check
      check (statutory_discount_type in ('none', 'senior', 'pwd'));
  end if;
end;
$$;

alter table public.sales_order_items
  add column if not exists senior_pwd_discount_category text not null default 'not_eligible',
  add column if not exists statutory_discount_amount numeric(14, 2) not null default 0,
  add column if not exists statutory_vat_exempt_amount numeric(14, 2) not null default 0,
  add column if not exists statutory_special_discount_amount numeric(14, 2) not null default 0;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'sales_order_items_senior_pwd_discount_category_check'
      and conrelid = 'public.sales_order_items'::regclass
  ) then
    alter table public.sales_order_items
      add constraint sales_order_items_senior_pwd_discount_category_check
      check (senior_pwd_discount_category in ('regular_20', 'basic_necessity_5', 'not_eligible'));
  end if;
end;
$$;

create table if not exists public.senior_pwd_discount_settings (
  branch_id uuid primary key references public.branches(id) on delete cascade,
  standard_discount_rate numeric(5, 2) not null default 20.00 check (standard_discount_rate >= 0 and standard_discount_rate <= 100),
  basic_necessity_rate numeric(5, 2) not null default 5.00 check (basic_necessity_rate >= 0 and basic_necessity_rate <= 100),
  require_id_capture boolean not null default true,
  require_booklet_for_basic boolean not null default true,
  is_active boolean not null default true,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.senior_pwd_discount_claims (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null unique references public.sales_orders(id) on delete cascade,
  branch_id uuid not null references public.branches(id) on delete restrict,
  customer_type text not null check (customer_type in ('senior', 'pwd')),
  beneficiary_name text not null,
  beneficiary_id_type text not null,
  beneficiary_id_number text not null,
  beneficiary_booklet_number text,
  invoice_number text,
  gross_amount numeric(14, 2) not null default 0,
  regular_discount_amount numeric(14, 2) not null default 0,
  special_discount_amount numeric(14, 2) not null default 0,
  vat_exempt_amount numeric(14, 2) not null default 0,
  total_discount_amount numeric(14, 2) not null default 0,
  created_by uuid references public.user_profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists idx_senior_pwd_claims_branch_created on public.senior_pwd_discount_claims(branch_id, created_at desc);
create index if not exists idx_senior_pwd_claims_type_created on public.senior_pwd_discount_claims(customer_type, created_at desc);
create index if not exists idx_products_senior_pwd_category on public.products(senior_pwd_discount_category);

drop trigger if exists set_senior_pwd_settings_updated_at on public.senior_pwd_discount_settings;
create trigger set_senior_pwd_settings_updated_at
before update on public.senior_pwd_discount_settings
for each row execute function public.set_updated_at();

insert into public.senior_pwd_discount_settings (branch_id)
select b.id
from public.branches b
left join public.senior_pwd_discount_settings s on s.branch_id = b.id
where s.branch_id is null;

alter table public.senior_pwd_discount_settings enable row level security;
alter table public.senior_pwd_discount_claims enable row level security;

drop policy if exists senior_pwd_settings_select_by_role on public.senior_pwd_discount_settings;
create policy senior_pwd_settings_select_by_role
on public.senior_pwd_discount_settings
for select
to authenticated
using (
  public.current_user_is_admin()
  or public.current_user_role() = 'auditor'
  or branch_id = public.current_user_branch_id()
);

drop policy if exists senior_pwd_settings_admin_write on public.senior_pwd_discount_settings;
create policy senior_pwd_settings_admin_write
on public.senior_pwd_discount_settings
for all
to authenticated
using (public.current_user_is_admin())
with check (public.current_user_is_admin());

drop policy if exists senior_pwd_claims_select_by_role on public.senior_pwd_discount_claims;
create policy senior_pwd_claims_select_by_role
on public.senior_pwd_discount_claims
for select
to authenticated
using (
  public.current_user_is_admin()
  or public.current_user_role() = 'auditor'
  or branch_id = public.current_user_branch_id()
);

create or replace function public.senior_pwd_user_can_apply()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.user_profiles up
    left join public.user_access_settings uas on uas.user_id = up.id
    where up.id = auth.uid()
      and up.is_active = true
      and up.deleted_at is null
      and (
        up.role in ('admin', 'manager')
        or 'senior_pwd.apply' = any(coalesce(uas.permissions, public.role_default_permissions(up.role)))
      )
  )
$$;

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
      'bir.view',
      'bir.manage',
      'tax.view',
      'senior_pwd.view',
      'senior_pwd.apply',
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
      'bir.view',
      'tax.view',
      'senior_pwd.view',
      'activity.view',
      'reports.view'
    ]::text[]
    else array[
      'dashboard.view',
      'products.view',
      'pos.sell',
      'senior_pwd.apply',
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
    jsonb_build_object('key', 'bir.view', 'label', 'View BIR compliance'),
    jsonb_build_object('key', 'bir.manage', 'label', 'Manage BIR compliance'),
    jsonb_build_object('key', 'tax.view', 'label', 'View tax reports'),
    jsonb_build_object('key', 'tax.manage', 'label', 'Manage tax setup'),
    jsonb_build_object('key', 'senior_pwd.view', 'label', 'View Senior/PWD reports'),
    jsonb_build_object('key', 'senior_pwd.manage', 'label', 'Manage Senior/PWD setup'),
    jsonb_build_object('key', 'senior_pwd.apply', 'label', 'Apply Senior/PWD discounts'),
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

create or replace function public.senior_pwd_management_get(
  p_from date default current_date - 29,
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
  v_from date := coalesce(p_from, current_date - 29);
  v_to date := coalesce(p_to, current_date);
  v_effective_branch_id uuid;
  v_result jsonb;
begin
  v_profile := public.ensure_active_user();

  if v_profile.role not in ('admin', 'manager', 'auditor') then
    raise exception 'Senior/PWD module is not available for this role' using errcode = '42501';
  end if;

  if v_to < v_from then
    raise exception 'To date must be after from date' using errcode = '22007';
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
  scoped_claims as (
    select
      c.*,
      b.branch_code,
      b.name as branch_name,
      so.status as order_status,
      so.business_date,
      so.total as invoice_total,
      up.full_name as cashier_name
    from public.senior_pwd_discount_claims c
    join visible_branches b on b.id = c.branch_id
    join public.sales_orders so on so.id = c.order_id
    left join public.user_profiles up on up.id = c.created_by
    where so.business_date >= v_from
      and so.business_date <= v_to
      and so.status = 'completed'
  ),
  branch_rows as (
    select
      b.id as branch_id,
      b.branch_code,
      b.name as branch_name,
      s.standard_discount_rate,
      s.basic_necessity_rate,
      s.require_id_capture,
      s.require_booklet_for_basic,
      s.is_active,
      s.notes,
      count(c.id)::integer as claims,
      coalesce(sum(c.total_discount_amount), 0)::numeric(14, 2) as total_benefit
    from visible_branches b
    left join public.senior_pwd_discount_settings s on s.branch_id = b.id
    left join scoped_claims c on c.branch_id = b.id
    group by b.id, b.branch_code, b.name, s.standard_discount_rate, s.basic_necessity_rate, s.require_id_capture, s.require_booklet_for_basic, s.is_active, s.notes
    order by b.name
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
      p.selling_price,
      p.tax_type,
      p.vat_rate,
      p.senior_pwd_discount_category,
      p.is_active
    from public.products p
    left join public.product_categories pc on pc.id = p.category_id
    left join public.product_brands pb on pb.id = p.brand_id
    where p.deleted_at is null
    order by p.name
  ),
  daily_rows as (
    select
      d.day::date as business_date,
      to_char(d.day, 'Mon DD') as label,
      count(c.id)::integer as claims,
      coalesce(sum(c.regular_discount_amount), 0)::numeric(14, 2) as regular_discount_amount,
      coalesce(sum(c.special_discount_amount), 0)::numeric(14, 2) as special_discount_amount,
      coalesce(sum(c.vat_exempt_amount), 0)::numeric(14, 2) as vat_exempt_amount,
      coalesce(sum(c.total_discount_amount), 0)::numeric(14, 2) as total_discount_amount
    from generate_series(v_from, v_to, interval '1 day') d(day)
    left join scoped_claims c on c.business_date = d.day::date
    group by d.day
    order by d.day
  )
  select jsonb_build_object(
    'period', jsonb_build_object('from', v_from, 'to', v_to),
    'summary', jsonb_build_object(
      'claims', coalesce((select count(*) from scoped_claims), 0),
      'senior_claims', coalesce((select count(*) from scoped_claims where customer_type = 'senior'), 0),
      'pwd_claims', coalesce((select count(*) from scoped_claims where customer_type = 'pwd'), 0),
      'regular_discount_amount', coalesce((select sum(regular_discount_amount) from scoped_claims), 0),
      'special_discount_amount', coalesce((select sum(special_discount_amount) from scoped_claims), 0),
      'vat_exempt_amount', coalesce((select sum(vat_exempt_amount) from scoped_claims), 0),
      'total_discount_amount', coalesce((select sum(total_discount_amount) from scoped_claims), 0)
    ),
    'branches', coalesce((
      select jsonb_agg(jsonb_build_object('id', b.id, 'branch_code', b.branch_code, 'name', b.name) order by b.name)
      from visible_branches b
    ), '[]'::jsonb),
    'branch_settings', coalesce((select jsonb_agg(to_jsonb(branch_rows) order by branch_name) from branch_rows), '[]'::jsonb),
    'products', coalesce((select jsonb_agg(to_jsonb(product_rows) order by name) from product_rows), '[]'::jsonb),
    'claims', coalesce((select jsonb_agg(to_jsonb(scoped_claims) order by created_at desc) from scoped_claims), '[]'::jsonb),
    'daily_claims', coalesce((select jsonb_agg(to_jsonb(daily_rows) order by business_date) from daily_rows), '[]'::jsonb),
    'eligibility_summary', jsonb_build_object(
      'regular_20', coalesce((select count(*) from product_rows where senior_pwd_discount_category = 'regular_20'), 0),
      'basic_necessity_5', coalesce((select count(*) from product_rows where senior_pwd_discount_category = 'basic_necessity_5'), 0),
      'not_eligible', coalesce((select count(*) from product_rows where senior_pwd_discount_category = 'not_eligible'), 0)
    ),
    'generated_at', now()
  )
  into v_result;

  return v_result;
end;
$$;

create or replace function public.senior_pwd_settings_save(p_branch_id uuid, p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor public.user_profiles;
begin
  v_actor := public.ensure_active_user();

  if v_actor.role <> 'admin' then
    raise exception 'Only admins can manage Senior/PWD settings' using errcode = '42501';
  end if;

  if p_branch_id is null then
    raise exception 'Branch is required' using errcode = '23502';
  end if;

  insert into public.senior_pwd_discount_settings (
    branch_id,
    standard_discount_rate,
    basic_necessity_rate,
    require_id_capture,
    require_booklet_for_basic,
    is_active,
    notes
  )
  values (
    p_branch_id,
    coalesce(nullif(p_payload->>'standard_discount_rate', '')::numeric, 20),
    coalesce(nullif(p_payload->>'basic_necessity_rate', '')::numeric, 5),
    coalesce((p_payload->>'require_id_capture')::boolean, true),
    coalesce((p_payload->>'require_booklet_for_basic')::boolean, true),
    coalesce((p_payload->>'is_active')::boolean, true),
    nullif(trim(coalesce(p_payload->>'notes', '')), '')
  )
  on conflict (branch_id) do update
  set standard_discount_rate = excluded.standard_discount_rate,
      basic_necessity_rate = excluded.basic_necessity_rate,
      require_id_capture = excluded.require_id_capture,
      require_booklet_for_basic = excluded.require_booklet_for_basic,
      is_active = excluded.is_active,
      notes = excluded.notes,
      updated_at = now();

  perform public.log_activity(
    'senior_pwd.settings_saved',
    'senior_pwd_discount_settings',
    p_branch_id::text,
    jsonb_build_object('branch_id', p_branch_id),
    v_actor.id
  );

  return public.senior_pwd_management_get(null, null, null);
end;
$$;

create or replace function public.senior_pwd_product_eligibility_save(p_product_id uuid, p_category text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor public.user_profiles;
  v_category text := coalesce(nullif(p_category, ''), 'regular_20');
begin
  v_actor := public.ensure_active_user();

  if v_actor.role <> 'admin' then
    raise exception 'Only admins can manage product Senior/PWD eligibility' using errcode = '42501';
  end if;

  if v_category not in ('regular_20', 'basic_necessity_5', 'not_eligible') then
    raise exception 'Invalid Senior/PWD product eligibility' using errcode = '22023';
  end if;

  update public.products
  set senior_pwd_discount_category = v_category
  where id = p_product_id
    and deleted_at is null;

  if not found then
    raise exception 'Product not found' using errcode = '02000';
  end if;

  perform public.log_activity(
    'senior_pwd.product_eligibility_saved',
    'product',
    p_product_id::text,
    jsonb_build_object('senior_pwd_discount_category', v_category),
    v_actor.id
  );

  return public.senior_pwd_management_get(null, null, null);
end;
$$;

-- Replace POS data loader with Senior/PWD product and branch settings included.
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
  senior_pwd_settings as (
    select
      s.branch_id,
      s.standard_discount_rate,
      s.basic_necessity_rate,
      s.require_id_capture,
      s.require_booklet_for_basic,
      s.is_active,
      s.notes
    from public.senior_pwd_discount_settings s
    where s.branch_id = v_effective_branch_id
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
      p.senior_pwd_discount_category,
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
      so.statutory_discount_type,
      so.statutory_discount_amount,
      so.statutory_vat_exempt_amount,
      so.statutory_special_discount_amount,
      so.beneficiary_name,
      so.beneficiary_id_type,
      so.beneficiary_id_number,
      so.beneficiary_booklet_number,
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
          'senior_pwd_discount_category', soi.senior_pwd_discount_category,
          'statutory_discount_amount', soi.statutory_discount_amount,
          'statutory_vat_exempt_amount', soi.statutory_vat_exempt_amount,
          'statutory_special_discount_amount', soi.statutory_special_discount_amount,
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
    'senior_pwd_settings', coalesce(
      (select to_jsonb(senior_pwd_settings) from senior_pwd_settings limit 1),
      jsonb_build_object(
        'branch_id', v_effective_branch_id,
        'standard_discount_rate', 20,
        'basic_necessity_rate', 5,
        'require_id_capture', true,
        'require_booklet_for_basic', true,
        'is_active', true
      )
    ),
    'branches', coalesce((select jsonb_agg(to_jsonb(branch_options)) from branch_options), '[]'::jsonb),
    'products', coalesce((select jsonb_agg(to_jsonb(product_rows)) from product_rows), '[]'::jsonb),
    'recent_orders', coalesce((select jsonb_agg(to_jsonb(recent_order_rows)) from recent_order_rows), '[]'::jsonb),
    'summary', jsonb_build_object(
      'today_orders', coalesce((select count(*) from todays_orders), 0),
      'today_sales', coalesce((select sum(total) from todays_orders), 0),
      'today_tax', coalesce((select sum(tax_total) from todays_orders), 0),
      'today_discounts', coalesce((select sum(discount_total) from todays_orders), 0),
      'today_senior_pwd_discounts', coalesce((select sum(statutory_discount_amount + statutory_special_discount_amount) from todays_orders), 0),
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
    'senior_pwd_discount_options', jsonb_build_array(
      jsonb_build_object('label', 'No Senior/PWD discount', 'value', 'none'),
      jsonb_build_object('label', 'Senior Citizen', 'value', 'senior'),
      jsonb_build_object('label', 'PWD', 'value', 'pwd')
    ),
    'generated_at', now()
  )
  into v_result;

  return v_result;
end;
$$;

-- Replace checkout with Senior/PWD statutory discount handling.
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
  v_statutory jsonb := coalesce(p_payload->'senior_pwd_discount', '{}'::jsonb);
  v_statutory_type text := coalesce(nullif(v_statutory->>'type', ''), 'none');
  v_beneficiary_name text := nullif(trim(coalesce(v_statutory->>'beneficiary_name', '')), '');
  v_beneficiary_id_type text := coalesce(nullif(trim(v_statutory->>'id_type'), ''), case when v_statutory_type = 'senior' then 'OSCA ID' when v_statutory_type = 'pwd' then 'PWD ID' else null end);
  v_beneficiary_id_number text := nullif(trim(coalesce(v_statutory->>'id_number', '')), '');
  v_beneficiary_booklet_number text := nullif(trim(coalesce(v_statutory->>'booklet_number', '')), '');
  v_senior_pwd_settings public.senior_pwd_discount_settings;
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
  v_generic_discount_total numeric(14, 2) := 0;
  v_total_discount numeric(14, 2) := 0;
  v_discount_percent numeric(8, 4) := 0;
  v_tax_total numeric(14, 2) := 0;
  v_total numeric(14, 2) := 0;
  v_vatable_sales numeric(14, 2) := 0;
  v_vat_exempt_sales numeric(14, 2) := 0;
  v_zero_rated_sales numeric(14, 2) := 0;
  v_non_vat_sales numeric(14, 2) := 0;
  v_net_sales numeric(14, 2) := 0;
  v_statutory_discount_total numeric(14, 2) := 0;
  v_statutory_special_discount_total numeric(14, 2) := 0;
  v_statutory_vat_exempt_total numeric(14, 2) := 0;
  v_basic_special_total numeric(14, 2) := 0;
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

  if v_statutory_type not in ('none', 'senior', 'pwd') then
    raise exception 'Invalid Senior/PWD discount type' using errcode = '22023';
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

  select *
  into v_senior_pwd_settings
  from public.senior_pwd_discount_settings
  where branch_id = v_branch_id
  limit 1;

  if v_senior_pwd_settings.branch_id is null then
    insert into public.senior_pwd_discount_settings (branch_id)
    values (v_branch_id)
    returning * into v_senior_pwd_settings;
  end if;

  if v_statutory_type <> 'none' then
    if v_senior_pwd_settings.is_active = false then
      raise exception 'Senior/PWD discounts are disabled for this branch' using errcode = '23514';
    end if;

    if public.senior_pwd_user_can_apply() = false then
      raise exception 'You do not have permission to apply Senior/PWD discounts' using errcode = '42501';
    end if;

    if v_senior_pwd_settings.require_id_capture and (v_beneficiary_name is null or v_beneficiary_id_number is null) then
      raise exception 'Beneficiary name and OSCA/PWD ID number are required' using errcode = '23502';
    end if;
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
            so.statutory_discount_type,
            so.statutory_discount_amount,
            so.statutory_vat_exempt_amount,
            so.statutory_special_discount_amount,
            so.beneficiary_name,
            so.beneficiary_id_type,
            so.beneficiary_id_number,
            so.beneficiary_booklet_number,
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
            coalesce((select jsonb_agg(to_jsonb(soi) order by soi.created_at asc) from public.sales_order_items soi where soi.order_id = so.id), '[]'::jsonb) as items,
            coalesce((select jsonb_agg(to_jsonb(sop) order by sop.created_at asc) from public.sales_order_payments sop where sop.order_id = so.id), '[]'::jsonb) as payments
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
    senior_pwd_discount_category text not null default 'not_eligible',
    statutory_discount_amount numeric(14, 2) not null default 0,
    statutory_vat_exempt_amount numeric(14, 2) not null default 0,
    statutory_special_discount_amount numeric(14, 2) not null default 0,
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
        senior_pwd_discount_category,
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
        v_product.senior_pwd_discount_category,
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

    v_generic_discount_total := round(v_subtotal * (v_discount_value / 100), 2);
    v_discount_percent := v_discount_value;
  elsif v_discount_type = 'amount' then
    if v_discount_value < 0 or v_discount_value > v_subtotal then
      raise exception 'Discount amount cannot exceed subtotal' using errcode = '23514';
    end if;

    v_generic_discount_total := round(v_discount_value, 2);
    v_discount_percent := case when v_subtotal = 0 then 0 else round((v_generic_discount_total / v_subtotal) * 100, 4) end;
  end if;

  if public.pos_user_can_discount(v_discount_percent) = false then
    raise exception 'Discount exceeds this user''s permission limit' using errcode = '42501';
  end if;

  with rounded as (
    select
      line_no,
      round((gross_amount / v_subtotal) * v_generic_discount_total, 2) as line_discount
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
      when p.is_last then greatest(0, p.line_discount + (v_generic_discount_total - p.rounded_total))
      else greatest(0, p.line_discount)
    end
  from prepared p
  where p.line_no = l.line_no;

  with calc as (
    select
      line_no,
      greatest(gross_amount - discount_amount, 0)::numeric(14, 2) as sale_amount,
      senior_pwd_discount_category,
      tax_type,
      tax_rate,
      tax_inclusive
    from pg_temp.pos_checkout_lines
  ),
  statutory as (
    select
      line_no,
      sale_amount,
      senior_pwd_discount_category,
      tax_type,
      tax_rate,
      tax_inclusive,
      v_statutory_type <> 'none' and senior_pwd_discount_category = 'regular_20' as uses_regular_discount,
      v_statutory_type <> 'none' and senior_pwd_discount_category = 'basic_necessity_5' as uses_basic_discount,
      case
        when v_statutory_type <> 'none' and senior_pwd_discount_category = 'regular_20' and tax_type = 'vatable' and tax_inclusive
          then round(sale_amount / (1 + (tax_rate / 100)), 2)
        else sale_amount
      end as discount_base
    from calc
  ),
  taxes as (
    select
      line_no,
      sale_amount,
      senior_pwd_discount_category,
      tax_type,
      tax_rate,
      tax_inclusive,
      uses_regular_discount,
      uses_basic_discount,
      case
        when uses_regular_discount then round(discount_base * (v_senior_pwd_settings.standard_discount_rate / 100), 2)
        else 0
      end as regular_discount,
      case
        when uses_basic_discount then round(sale_amount * (v_senior_pwd_settings.basic_necessity_rate / 100), 2)
        else 0
      end as special_discount,
      case
        when uses_regular_discount and tax_type = 'vatable' and tax_inclusive then greatest(sale_amount - discount_base, 0)
        when uses_regular_discount and tax_type = 'vatable' and tax_inclusive = false then round(sale_amount * (tax_rate / 100), 2)
        else 0
      end as vat_exempt_amount,
      discount_base
    from statutory
  ),
  final_calc as (
    select
      line_no,
      sale_amount,
      senior_pwd_discount_category,
      tax_type,
      tax_rate,
      tax_inclusive,
      uses_regular_discount,
      uses_basic_discount,
      regular_discount,
      special_discount,
      vat_exempt_amount,
      case
        when uses_regular_discount then greatest(discount_base - regular_discount, 0)
        else greatest(sale_amount - special_discount, 0)
      end as taxable_or_exempt_amount
    from taxes
  ),
  final_taxes as (
    select
      line_no,
      senior_pwd_discount_category,
      regular_discount,
      special_discount,
      vat_exempt_amount,
      case
        when uses_regular_discount and tax_type = 'vatable' then 0
        when tax_type = 'vatable' and tax_inclusive then round(taxable_or_exempt_amount - (taxable_or_exempt_amount / (1 + (tax_rate / 100))), 2)
        when tax_type = 'vatable' and tax_inclusive = false then round(taxable_or_exempt_amount * (tax_rate / 100), 2)
        else 0
      end as tax_amount,
      case
        when uses_regular_discount and tax_type = 'vatable' then taxable_or_exempt_amount
        when tax_type = 'vatable' and tax_inclusive = false then round(taxable_or_exempt_amount + (taxable_or_exempt_amount * (tax_rate / 100)), 2)
        else taxable_or_exempt_amount
      end as net_amount,
      case
        when uses_regular_discount and tax_type = 'vatable' then 0
        when tax_type = 'vatable' and tax_inclusive then round(taxable_or_exempt_amount / (1 + (tax_rate / 100)), 2)
        when tax_type = 'vatable' and tax_inclusive = false then taxable_or_exempt_amount
        else 0
      end as vatable_sales,
      case
        when uses_regular_discount and tax_type = 'vatable' then taxable_or_exempt_amount
        when tax_type = 'vat_exempt' then taxable_or_exempt_amount
        else 0
      end as vat_exempt_sales,
      case when tax_type = 'zero_rated' then taxable_or_exempt_amount else 0 end as zero_rated_sales,
      case when tax_type = 'non_vat' then taxable_or_exempt_amount else 0 end as non_vat_sales
    from final_calc
  )
  update pg_temp.pos_checkout_lines l
  set senior_pwd_discount_category = f.senior_pwd_discount_category,
      statutory_discount_amount = f.regular_discount,
      statutory_special_discount_amount = f.special_discount,
      statutory_vat_exempt_amount = f.vat_exempt_amount,
      tax_amount = f.tax_amount,
      net_amount = f.net_amount,
      vatable_sales = f.vatable_sales,
      vat_exempt_sales = f.vat_exempt_sales,
      zero_rated_sales = f.zero_rated_sales,
      non_vat_sales = f.non_vat_sales
  from final_taxes f
  where f.line_no = l.line_no;

  select
    coalesce(sum(tax_amount), 0),
    coalesce(sum(net_amount), 0),
    coalesce(sum(vatable_sales), 0),
    coalesce(sum(vat_exempt_sales), 0),
    coalesce(sum(zero_rated_sales), 0),
    coalesce(sum(non_vat_sales), 0),
    coalesce(sum(statutory_discount_amount), 0),
    coalesce(sum(statutory_special_discount_amount), 0),
    coalesce(sum(statutory_vat_exempt_amount), 0)
  into
    v_tax_total,
    v_total,
    v_vatable_sales,
    v_vat_exempt_sales,
    v_zero_rated_sales,
    v_non_vat_sales,
    v_statutory_discount_total,
    v_statutory_special_discount_total,
    v_statutory_vat_exempt_total
  from pg_temp.pos_checkout_lines;

  if v_statutory_type <> 'none' then
    if (v_statutory_discount_total + v_statutory_special_discount_total + v_statutory_vat_exempt_total) <= 0 then
      raise exception 'Cart has no Senior/PWD eligible items' using errcode = '23514';
    end if;

    select coalesce(sum(statutory_special_discount_amount), 0)
    into v_basic_special_total
    from pg_temp.pos_checkout_lines
    where senior_pwd_discount_category = 'basic_necessity_5';

    if v_basic_special_total > 0 and v_senior_pwd_settings.require_booklet_for_basic and v_beneficiary_booklet_number is null then
      raise exception 'Purchase booklet/reference number is required for basic necessities or prime commodities' using errcode = '23502';
    end if;
  end if;

  v_total_discount := v_generic_discount_total + v_statutory_discount_total + v_statutory_special_discount_total;
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
    statutory_discount_type,
    statutory_discount_amount,
    statutory_vat_exempt_amount,
    statutory_special_discount_amount,
    beneficiary_name,
    beneficiary_id_type,
    beneficiary_id_number,
    beneficiary_booklet_number,
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
    v_total_discount,
    v_statutory_type,
    v_statutory_discount_total,
    v_statutory_vat_exempt_total,
    v_statutory_special_discount_total,
    v_beneficiary_name,
    v_beneficiary_id_type,
    v_beneficiary_id_number,
    v_beneficiary_booklet_number,
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
      senior_pwd_discount_category,
      statutory_discount_amount,
      statutory_vat_exempt_amount,
      statutory_special_discount_amount,
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
      v_line.senior_pwd_discount_category,
      v_line.statutory_discount_amount,
      v_line.statutory_vat_exempt_amount,
      v_line.statutory_special_discount_amount,
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

  if v_statutory_type <> 'none' then
    insert into public.senior_pwd_discount_claims (
      order_id,
      branch_id,
      customer_type,
      beneficiary_name,
      beneficiary_id_type,
      beneficiary_id_number,
      beneficiary_booklet_number,
      invoice_number,
      gross_amount,
      regular_discount_amount,
      special_discount_amount,
      vat_exempt_amount,
      total_discount_amount,
      created_by
    )
    select
      v_order_id,
      v_branch_id,
      v_statutory_type,
      coalesce(v_beneficiary_name, v_customer_name, 'Beneficiary'),
      coalesce(v_beneficiary_id_type, case when v_statutory_type = 'senior' then 'OSCA ID' else 'PWD ID' end),
      coalesce(v_beneficiary_id_number, 'NOT PROVIDED'),
      v_beneficiary_booklet_number,
      so.invoice_number,
      v_subtotal,
      v_statutory_discount_total,
      v_statutory_special_discount_total,
      v_statutory_vat_exempt_total,
      v_statutory_discount_total + v_statutory_special_discount_total + v_statutory_vat_exempt_total,
      v_actor.id
    from public.sales_orders so
    where so.id = v_order_id;
  end if;

  perform public.log_activity(
    'pos.sale_completed',
    'sales_order',
    v_order_id::text,
    jsonb_build_object(
      'order_number', v_order_number,
      'invoice_number', v_invoice_number,
      'total', v_total,
      'source', v_source,
      'senior_pwd_type', v_statutory_type
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
          so.statutory_discount_type,
          so.statutory_discount_amount,
          so.statutory_vat_exempt_amount,
          so.statutory_special_discount_amount,
          so.beneficiary_name,
          so.beneficiary_id_type,
          so.beneficiary_id_number,
          so.beneficiary_booklet_number,
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
          coalesce((select jsonb_agg(to_jsonb(soi) order by soi.created_at asc) from public.sales_order_items soi where soi.order_id = so.id), '[]'::jsonb) as items,
          coalesce((select jsonb_agg(to_jsonb(sop) order by sop.created_at asc) from public.sales_order_payments sop where sop.order_id = so.id), '[]'::jsonb) as payments
        from public.sales_orders so
        where so.id = v_order_id
      ) row
    )
  );
end;
$$;

revoke all on function public.senior_pwd_user_can_apply() from public;
revoke all on function public.senior_pwd_management_get(date, date, uuid) from public;
revoke all on function public.senior_pwd_settings_save(uuid, jsonb) from public;
revoke all on function public.senior_pwd_product_eligibility_save(uuid, text) from public;
grant execute on function public.senior_pwd_user_can_apply() to authenticated;
grant execute on function public.senior_pwd_management_get(date, date, uuid) to authenticated;
grant execute on function public.senior_pwd_settings_save(uuid, jsonb) to authenticated;
grant execute on function public.senior_pwd_product_eligibility_save(uuid, text) to authenticated;

notify pgrst, 'reload schema';
