-- MODULE 9: TAX MANAGEMENT
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
--
-- Scope:
-- - 12% VAT profile setup
-- - Non-VAT / percentage tax setup
-- - VAT-exempt, zero-rated, non-VAT tax code management
-- - Branch tax profile assignment
-- - Tax-inclusive / tax-exclusive branch defaults
-- - BIR tax report summaries from completed POS sales

create extension if not exists pgcrypto;

create table if not exists public.tax_profiles (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  registration_type text not null default 'vat_registered'
    check (registration_type in ('vat_registered', 'non_vat_percentage', 'mixed')),
  vat_rate numeric(5, 2) not null default 12.00 check (vat_rate >= 0 and vat_rate <= 100),
  percentage_tax_rate numeric(5, 2) not null default 0.00 check (percentage_tax_rate >= 0 and percentage_tax_rate <= 100),
  tax_inclusive_default boolean not null default true,
  is_default boolean not null default false,
  is_active boolean not null default true,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists idx_tax_profiles_one_default
on public.tax_profiles(is_default)
where is_default = true;

create table if not exists public.tax_codes (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  tax_type text not null check (tax_type in ('vatable', 'vat_exempt', 'zero_rated', 'non_vat')),
  rate numeric(5, 2) not null default 0.00 check (rate >= 0 and rate <= 100),
  bir_report_group text not null default 'non_vat_sales'
    check (bir_report_group in ('vatable_sales', 'vat_exempt_sales', 'zero_rated_sales', 'non_vat_sales', 'percentage_tax')),
  affects_output_vat boolean not null default false,
  is_active boolean not null default true,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public.tax_profiles (
  code,
  name,
  registration_type,
  vat_rate,
  percentage_tax_rate,
  tax_inclusive_default,
  is_default,
  notes
)
values
  ('VAT12', 'VAT Registered - 12%', 'vat_registered', 12.00, 0.00, true, false, 'Default VAT-registered branch profile.'),
  ('NONVAT', 'Non-VAT / Percentage Tax', 'non_vat_percentage', 0.00, 3.00, true, false, 'Configurable percentage tax profile for non-VAT branches.'),
  ('MIXED', 'Mixed Tax Profile', 'mixed', 12.00, 0.00, true, false, 'Use when a branch sells VATable, exempt, zero-rated, and non-VAT items.')
on conflict (code) do update
set name = excluded.name,
    registration_type = excluded.registration_type,
    vat_rate = excluded.vat_rate,
    percentage_tax_rate = excluded.percentage_tax_rate,
    tax_inclusive_default = excluded.tax_inclusive_default,
    is_active = true,
    notes = excluded.notes,
    updated_at = now();

update public.tax_profiles
set is_default = true
where code = 'VAT12'
  and not exists (
    select 1
    from public.tax_profiles
    where is_default = true
  );

insert into public.tax_codes (
  code,
  name,
  tax_type,
  rate,
  bir_report_group,
  affects_output_vat,
  notes
)
values
  ('VAT12', 'VATable Sales - 12%', 'vatable', 12.00, 'vatable_sales', true, 'Standard output VAT code for VATable products.'),
  ('VATEXEMPT', 'VAT-Exempt Sales', 'vat_exempt', 0.00, 'vat_exempt_sales', false, 'Sales tagged as VAT-exempt at product level.'),
  ('ZERORATED', 'Zero-Rated Sales', 'zero_rated', 0.00, 'zero_rated_sales', false, 'Sales tagged as zero-rated at product level.'),
  ('NONVAT', 'Non-VAT Sales', 'non_vat', 0.00, 'non_vat_sales', false, 'Sales outside VAT output calculation.'),
  ('PERCENTAGE3', 'Percentage Tax - 3%', 'non_vat', 3.00, 'percentage_tax', false, 'Configurable percentage tax reporting code.')
on conflict (code) do update
set name = excluded.name,
    tax_type = excluded.tax_type,
    rate = excluded.rate,
    bir_report_group = excluded.bir_report_group,
    affects_output_vat = excluded.affects_output_vat,
    is_active = true,
    notes = excluded.notes,
    updated_at = now();

alter table public.branch_settings
  add column if not exists tax_profile_id uuid references public.tax_profiles(id) on delete set null,
  add column if not exists percentage_tax_rate numeric(5, 2) not null default 0.00 check (percentage_tax_rate >= 0 and percentage_tax_rate <= 100),
  add column if not exists tax_inclusive_default boolean not null default true;

update public.branch_settings bs
set tax_profile_id = tp.id,
    vat_rate = coalesce(bs.vat_rate, tp.vat_rate),
    percentage_tax_rate = case
      when bs.tax_profile = 'non_vat' and bs.percentage_tax_rate = 0 then tp.percentage_tax_rate
      else bs.percentage_tax_rate
    end,
    tax_inclusive_default = tp.tax_inclusive_default
from public.tax_profiles tp
where bs.tax_profile_id is null
  and tp.code = case
    when bs.tax_profile = 'non_vat' then 'NONVAT'
    when bs.tax_profile = 'mixed' then 'MIXED'
    else 'VAT12'
  end;

drop trigger if exists set_tax_profiles_updated_at on public.tax_profiles;
create trigger set_tax_profiles_updated_at
before update on public.tax_profiles
for each row execute function public.set_updated_at();

drop trigger if exists set_tax_codes_updated_at on public.tax_codes;
create trigger set_tax_codes_updated_at
before update on public.tax_codes
for each row execute function public.set_updated_at();

alter table public.tax_profiles enable row level security;
alter table public.tax_codes enable row level security;

drop policy if exists tax_profiles_select_by_role on public.tax_profiles;
create policy tax_profiles_select_by_role
on public.tax_profiles
for select
to authenticated
using (public.current_user_role() in ('admin', 'manager', 'auditor'));

drop policy if exists tax_profiles_admin_write on public.tax_profiles;
create policy tax_profiles_admin_write
on public.tax_profiles
for all
to authenticated
using (public.current_user_is_admin())
with check (public.current_user_is_admin());

drop policy if exists tax_codes_select_by_role on public.tax_codes;
create policy tax_codes_select_by_role
on public.tax_codes
for select
to authenticated
using (public.current_user_role() in ('admin', 'manager', 'auditor'));

drop policy if exists tax_codes_admin_write on public.tax_codes;
create policy tax_codes_admin_write
on public.tax_codes
for all
to authenticated
using (public.current_user_is_admin())
with check (public.current_user_is_admin());

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
      'tax.view',
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
    jsonb_build_object('key', 'bir.view', 'label', 'View BIR compliance'),
    jsonb_build_object('key', 'bir.manage', 'label', 'Manage BIR compliance'),
    jsonb_build_object('key', 'tax.view', 'label', 'View tax reports'),
    jsonb_build_object('key', 'tax.manage', 'label', 'Manage tax setup'),
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

create or replace function public.tax_management_get(
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
    raise exception 'Tax management is not available for this role' using errcode = '42501';
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
  branch_profile_rows as (
    select
      b.id as branch_id,
      b.branch_code,
      b.name as branch_name,
      bs.tax_profile as legacy_tax_profile,
      bs.tax_profile_id,
      coalesce(tp.code, case bs.tax_profile when 'non_vat' then 'NONVAT' when 'mixed' then 'MIXED' else 'VAT12' end) as tax_profile_code,
      coalesce(tp.name, case bs.tax_profile when 'non_vat' then 'Non-VAT / Percentage Tax' when 'mixed' then 'Mixed Tax Profile' else 'VAT Registered - 12%' end) as tax_profile_name,
      coalesce(tp.registration_type, case bs.tax_profile when 'non_vat' then 'non_vat_percentage' when 'mixed' then 'mixed' else 'vat_registered' end) as registration_type,
      coalesce(tp.vat_rate, bs.vat_rate, 12) as vat_rate,
      coalesce(tp.percentage_tax_rate, bs.percentage_tax_rate, case when bs.tax_profile = 'non_vat' then 3 else 0 end) as percentage_tax_rate,
      coalesce(bs.tax_inclusive_default, tp.tax_inclusive_default, true) as tax_inclusive_default
    from visible_branches b
    left join public.branch_settings bs on bs.branch_id = b.id
    left join public.tax_profiles tp on tp.id = bs.tax_profile_id
    order by b.name
  ),
  scoped_orders as (
    select
      so.*,
      b.branch_code,
      b.name as branch_name,
      bpr.registration_type,
      bpr.percentage_tax_rate as branch_percentage_tax_rate
    from public.sales_orders so
    join visible_branches b on b.id = so.branch_id
    left join branch_profile_rows bpr on bpr.branch_id = so.branch_id
    where so.status = 'completed'
      and so.business_date >= v_from
      and so.business_date <= v_to
  ),
  summary as (
    select
      count(*)::integer as order_count,
      round(coalesce(sum(total), 0), 2) as gross_sales,
      round(coalesce(sum(net_sales), 0), 2) as net_sales,
      round(coalesce(sum(discount_total), 0), 2) as discounts,
      round(coalesce(sum(tax_total), 0), 2) as vat_output,
      round(coalesce(sum(vatable_sales), 0), 2) as vatable_sales,
      round(coalesce(sum(vat_exempt_sales), 0), 2) as vat_exempt_sales,
      round(coalesce(sum(zero_rated_sales), 0), 2) as zero_rated_sales,
      round(coalesce(sum(non_vat_sales), 0), 2) as non_vat_sales,
      round(coalesce(sum(
        case
          when registration_type = 'non_vat_percentage'
            then net_sales * (branch_percentage_tax_rate / 100)
          else 0
        end
      ), 0), 2) as percentage_tax_due
    from scoped_orders
  ),
  branch_tax_rows as (
    select
      b.id as branch_id,
      b.branch_code,
      b.name as branch_name,
      count(so.id)::integer as orders,
      round(coalesce(sum(so.total), 0), 2) as gross_sales,
      round(coalesce(sum(so.net_sales), 0), 2) as net_sales,
      round(coalesce(sum(so.tax_total), 0), 2) as vat_output,
      round(coalesce(sum(so.vatable_sales), 0), 2) as vatable_sales,
      round(coalesce(sum(so.vat_exempt_sales), 0), 2) as vat_exempt_sales,
      round(coalesce(sum(so.zero_rated_sales), 0), 2) as zero_rated_sales,
      round(coalesce(sum(so.non_vat_sales), 0), 2) as non_vat_sales,
      round(coalesce(sum(
        case
          when so.registration_type = 'non_vat_percentage'
            then so.net_sales * (so.branch_percentage_tax_rate / 100)
          else 0
        end
      ), 0), 2) as percentage_tax_due
    from visible_branches b
    left join scoped_orders so on so.branch_id = b.id
    group by b.id, b.branch_code, b.name
    order by gross_sales desc, b.name
  ),
  daily_tax_rows as (
    select
      so.business_date,
      to_char(so.business_date, 'Mon DD') as label,
      count(so.id)::integer as orders,
      round(coalesce(sum(so.total), 0), 2) as gross_sales,
      round(coalesce(sum(so.tax_total), 0), 2) as vat_output,
      round(coalesce(sum(
        case
          when so.registration_type = 'non_vat_percentage'
            then so.net_sales * (so.branch_percentage_tax_rate / 100)
          else 0
        end
      ), 0), 2) as percentage_tax_due
    from scoped_orders so
    group by so.business_date
    order by so.business_date
  ),
  tax_classes as (
    select *
    from (
      values
        ('vatable'::text, 'VATable sales'::text, 1),
        ('vat_exempt'::text, 'VAT-exempt sales'::text, 2),
        ('zero_rated'::text, 'Zero-rated sales'::text, 3),
        ('non_vat'::text, 'Non-VAT sales'::text, 4)
    ) as c(tax_type, label, sort_order)
  ),
  line_sums as (
    select
      soi.tax_type,
      count(soi.id)::integer as lines,
      round(coalesce(sum(soi.gross_amount), 0), 2) as gross_amount,
      round(coalesce(sum(soi.discount_amount), 0), 2) as discount_amount,
      round(coalesce(sum(soi.tax_amount), 0), 2) as tax_amount,
      round(coalesce(sum(soi.net_amount), 0), 2) as net_amount,
      round(coalesce(sum(
        case
          when soi.tax_type = 'vatable' then greatest(soi.net_amount - soi.tax_amount, 0)
          else soi.net_amount
        end
      ), 0), 2) as taxable_base
    from public.sales_order_items soi
    join scoped_orders so on so.id = soi.order_id
    group by soi.tax_type
  ),
  tax_mix_rows as (
    select
      tc.tax_type,
      tc.label,
      tc.sort_order,
      coalesce(ls.lines, 0) as lines,
      coalesce(ls.gross_amount, 0) as gross_amount,
      coalesce(ls.discount_amount, 0) as discount_amount,
      coalesce(ls.tax_amount, 0) as tax_amount,
      coalesce(ls.net_amount, 0) as net_amount,
      coalesce(ls.taxable_base, 0) as taxable_base
    from tax_classes tc
    left join line_sums ls on ls.tax_type = tc.tax_type
    order by tc.sort_order
  ),
  product_tax_rows as (
    select
      tc.tax_type,
      tc.label,
      tc.sort_order,
      count(p.id)::integer as products,
      count(p.id) filter (where p.is_active = true)::integer as active_products,
      round(coalesce(avg(nullif(p.vat_rate, 0)), 0), 2) as average_rate
    from tax_classes tc
    left join public.products p on p.tax_type = tc.tax_type and p.deleted_at is null
    group by tc.tax_type, tc.label, tc.sort_order
    order by tc.sort_order
  )
  select jsonb_build_object(
    'period', jsonb_build_object('from', v_from, 'to', v_to),
    'summary', (
      select jsonb_build_object(
        'order_count', order_count,
        'gross_sales', gross_sales,
        'net_sales', net_sales,
        'discounts', discounts,
        'vat_output', vat_output,
        'vatable_sales', vatable_sales,
        'vat_exempt_sales', vat_exempt_sales,
        'zero_rated_sales', zero_rated_sales,
        'non_vat_sales', non_vat_sales,
        'percentage_tax_due', percentage_tax_due,
        'total_tax_due', round(vat_output + percentage_tax_due, 2)
      )
      from summary
    ),
    'branches', coalesce((
      select jsonb_agg(
        jsonb_build_object('id', b.id, 'branch_code', b.branch_code, 'name', b.name)
        order by b.name
      )
      from visible_branches b
    ), '[]'::jsonb),
    'branch_profiles', coalesce((select jsonb_agg(to_jsonb(branch_profile_rows) order by branch_name) from branch_profile_rows), '[]'::jsonb),
    'tax_profiles', coalesce((select jsonb_agg(to_jsonb(tp) order by tp.is_default desc, tp.code) from public.tax_profiles tp), '[]'::jsonb),
    'tax_codes', coalesce((select jsonb_agg(to_jsonb(tc) order by tc.tax_type, tc.code) from public.tax_codes tc), '[]'::jsonb),
    'tax_by_branch', coalesce((select jsonb_agg(to_jsonb(branch_tax_rows)) from branch_tax_rows), '[]'::jsonb),
    'daily_tax', coalesce((select jsonb_agg(to_jsonb(daily_tax_rows)) from daily_tax_rows), '[]'::jsonb),
    'tax_mix', coalesce((select jsonb_agg(to_jsonb(tax_mix_rows) order by sort_order) from tax_mix_rows), '[]'::jsonb),
    'product_tax_mix', coalesce((select jsonb_agg(to_jsonb(product_tax_rows) order by sort_order) from product_tax_rows), '[]'::jsonb),
    'tax_report_lines', (
      select jsonb_build_array(
        jsonb_build_object('line_code', 'GROSS', 'label', 'Gross sales', 'amount', gross_sales, 'notes', 'Completed invoices before excluding VAT output.'),
        jsonb_build_object('line_code', 'VATABLE', 'label', 'VATable sales', 'amount', vatable_sales, 'notes', 'VATable base from saved POS line calculations.'),
        jsonb_build_object('line_code', 'OUTPUT_VAT', 'label', 'Output VAT', 'amount', vat_output, 'notes', 'VAT collected from VATable completed sales.'),
        jsonb_build_object('line_code', 'VAT_EXEMPT', 'label', 'VAT-exempt sales', 'amount', vat_exempt_sales, 'notes', 'Product lines tagged VAT-exempt.'),
        jsonb_build_object('line_code', 'ZERO_RATED', 'label', 'Zero-rated sales', 'amount', zero_rated_sales, 'notes', 'Product lines tagged zero-rated.'),
        jsonb_build_object('line_code', 'NON_VAT', 'label', 'Non-VAT sales', 'amount', non_vat_sales, 'notes', 'Product lines tagged non-VAT.'),
        jsonb_build_object('line_code', 'PERCENTAGE_TAX', 'label', 'Percentage tax due', 'amount', percentage_tax_due, 'notes', 'Estimated from non-VAT branch profile rate.'),
        jsonb_build_object('line_code', 'TOTAL_TAX', 'label', 'Total tax due', 'amount', round(vat_output + percentage_tax_due, 2), 'notes', 'Output VAT plus configured percentage tax estimate.')
      )
      from summary
    ),
    'generated_at', now()
  )
  into v_result;

  return v_result;
end;
$$;

create or replace function public.tax_profile_save(p_profile_id uuid, p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor public.user_profiles;
  v_profile_id uuid;
  v_code text := upper(trim(coalesce(p_payload->>'code', '')));
  v_name text := trim(coalesce(p_payload->>'name', ''));
  v_registration_type text := coalesce(nullif(p_payload->>'registration_type', ''), 'vat_registered');
begin
  v_actor := public.ensure_active_user();

  if v_actor.role <> 'admin' then
    raise exception 'Only admins can manage tax profiles' using errcode = '42501';
  end if;

  if v_code = '' or v_name = '' then
    raise exception 'Tax profile code and name are required' using errcode = '23502';
  end if;

  if v_registration_type not in ('vat_registered', 'non_vat_percentage', 'mixed') then
    raise exception 'Invalid registration type' using errcode = '22023';
  end if;

  if coalesce((p_payload->>'is_default')::boolean, false) then
    update public.tax_profiles
    set is_default = false
    where p_profile_id is null or id <> p_profile_id;
  end if;

  if p_profile_id is null then
    insert into public.tax_profiles (
      code,
      name,
      registration_type,
      vat_rate,
      percentage_tax_rate,
      tax_inclusive_default,
      is_default,
      is_active,
      notes
    )
    values (
      v_code,
      v_name,
      v_registration_type,
      coalesce(nullif(p_payload->>'vat_rate', '')::numeric, case when v_registration_type in ('vat_registered', 'mixed') then 12 else 0 end),
      coalesce(nullif(p_payload->>'percentage_tax_rate', '')::numeric, case when v_registration_type = 'non_vat_percentage' then 3 else 0 end),
      coalesce((p_payload->>'tax_inclusive_default')::boolean, true),
      coalesce((p_payload->>'is_default')::boolean, false),
      coalesce((p_payload->>'is_active')::boolean, true),
      nullif(trim(coalesce(p_payload->>'notes', '')), '')
    )
    returning id into v_profile_id;
  else
    update public.tax_profiles
    set code = v_code,
        name = v_name,
        registration_type = v_registration_type,
        vat_rate = coalesce(nullif(p_payload->>'vat_rate', '')::numeric, vat_rate),
        percentage_tax_rate = coalesce(nullif(p_payload->>'percentage_tax_rate', '')::numeric, percentage_tax_rate),
        tax_inclusive_default = coalesce((p_payload->>'tax_inclusive_default')::boolean, tax_inclusive_default),
        is_default = coalesce((p_payload->>'is_default')::boolean, is_default),
        is_active = coalesce((p_payload->>'is_active')::boolean, is_active),
        notes = nullif(trim(coalesce(p_payload->>'notes', notes, '')), '')
    where id = p_profile_id
    returning id into v_profile_id;

    if v_profile_id is null then
      raise exception 'Tax profile not found' using errcode = '02000';
    end if;
  end if;

  perform public.log_activity(
    'tax.profile_saved',
    'tax_profile',
    v_profile_id::text,
    jsonb_build_object('code', v_code, 'name', v_name),
    v_actor.id
  );

  return public.tax_management_get(null, null, null);
end;
$$;

create or replace function public.tax_code_save(p_code_id uuid, p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor public.user_profiles;
  v_code_id uuid;
  v_code text := upper(trim(coalesce(p_payload->>'code', '')));
  v_name text := trim(coalesce(p_payload->>'name', ''));
  v_tax_type text := coalesce(nullif(p_payload->>'tax_type', ''), 'non_vat');
  v_report_group text := coalesce(nullif(p_payload->>'bir_report_group', ''), 'non_vat_sales');
begin
  v_actor := public.ensure_active_user();

  if v_actor.role <> 'admin' then
    raise exception 'Only admins can manage tax codes' using errcode = '42501';
  end if;

  if v_code = '' or v_name = '' then
    raise exception 'Tax code and name are required' using errcode = '23502';
  end if;

  if v_tax_type not in ('vatable', 'vat_exempt', 'zero_rated', 'non_vat') then
    raise exception 'Invalid tax type' using errcode = '22023';
  end if;

  if v_report_group not in ('vatable_sales', 'vat_exempt_sales', 'zero_rated_sales', 'non_vat_sales', 'percentage_tax') then
    raise exception 'Invalid BIR report group' using errcode = '22023';
  end if;

  if p_code_id is null then
    insert into public.tax_codes (
      code,
      name,
      tax_type,
      rate,
      bir_report_group,
      affects_output_vat,
      is_active,
      notes
    )
    values (
      v_code,
      v_name,
      v_tax_type,
      coalesce(nullif(p_payload->>'rate', '')::numeric, 0),
      v_report_group,
      coalesce((p_payload->>'affects_output_vat')::boolean, v_tax_type = 'vatable'),
      coalesce((p_payload->>'is_active')::boolean, true),
      nullif(trim(coalesce(p_payload->>'notes', '')), '')
    )
    returning id into v_code_id;
  else
    update public.tax_codes
    set code = v_code,
        name = v_name,
        tax_type = v_tax_type,
        rate = coalesce(nullif(p_payload->>'rate', '')::numeric, rate),
        bir_report_group = v_report_group,
        affects_output_vat = coalesce((p_payload->>'affects_output_vat')::boolean, affects_output_vat),
        is_active = coalesce((p_payload->>'is_active')::boolean, is_active),
        notes = nullif(trim(coalesce(p_payload->>'notes', notes, '')), '')
    where id = p_code_id
    returning id into v_code_id;

    if v_code_id is null then
      raise exception 'Tax code not found' using errcode = '02000';
    end if;
  end if;

  perform public.log_activity(
    'tax.code_saved',
    'tax_code',
    v_code_id::text,
    jsonb_build_object('code', v_code, 'name', v_name),
    v_actor.id
  );

  return public.tax_management_get(null, null, null);
end;
$$;

create or replace function public.tax_branch_settings_save(p_branch_id uuid, p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor public.user_profiles;
  v_profile public.tax_profiles;
  v_profile_id uuid := nullif(p_payload->>'tax_profile_id', '')::uuid;
  v_legacy_profile text;
begin
  v_actor := public.ensure_active_user();

  if v_actor.role <> 'admin' then
    raise exception 'Only admins can manage branch tax settings' using errcode = '42501';
  end if;

  if p_branch_id is null then
    raise exception 'Branch is required' using errcode = '23502';
  end if;

  if not exists (select 1 from public.branches where id = p_branch_id) then
    raise exception 'Branch not found' using errcode = '02000';
  end if;

  if v_profile_id is null then
    select *
    into v_profile
    from public.tax_profiles
    where is_default = true
    limit 1;
  else
    select *
    into v_profile
    from public.tax_profiles
    where id = v_profile_id
    limit 1;
  end if;

  if v_profile.id is null then
    raise exception 'Tax profile not found' using errcode = '02000';
  end if;

  v_legacy_profile := case v_profile.registration_type
    when 'non_vat_percentage' then 'non_vat'
    when 'mixed' then 'mixed'
    else 'vat_12'
  end;

  insert into public.branch_settings (
    branch_id,
    tax_profile,
    vat_rate,
    percentage_tax_rate,
    tax_profile_id,
    tax_inclusive_default
  )
  values (
    p_branch_id,
    v_legacy_profile,
    coalesce(nullif(p_payload->>'vat_rate', '')::numeric, v_profile.vat_rate),
    coalesce(nullif(p_payload->>'percentage_tax_rate', '')::numeric, v_profile.percentage_tax_rate),
    v_profile.id,
    coalesce((p_payload->>'tax_inclusive_default')::boolean, v_profile.tax_inclusive_default)
  )
  on conflict (branch_id) do update
  set tax_profile = excluded.tax_profile,
      vat_rate = excluded.vat_rate,
      percentage_tax_rate = excluded.percentage_tax_rate,
      tax_profile_id = excluded.tax_profile_id,
      tax_inclusive_default = excluded.tax_inclusive_default,
      updated_at = now();

  perform public.log_activity(
    'tax.branch_settings_saved',
    'branch_settings',
    p_branch_id::text,
    jsonb_build_object('tax_profile_id', v_profile.id, 'tax_profile_code', v_profile.code),
    v_actor.id
  );

  return public.tax_management_get(null, null, null);
end;
$$;

revoke all on function public.tax_management_get(date, date, uuid) from public;
revoke all on function public.tax_profile_save(uuid, jsonb) from public;
revoke all on function public.tax_code_save(uuid, jsonb) from public;
revoke all on function public.tax_branch_settings_save(uuid, jsonb) from public;
grant execute on function public.tax_management_get(date, date, uuid) to authenticated;
grant execute on function public.tax_profile_save(uuid, jsonb) to authenticated;
grant execute on function public.tax_code_save(uuid, jsonb) to authenticated;
grant execute on function public.tax_branch_settings_save(uuid, jsonb) to authenticated;

notify pgrst, 'reload schema';
