-- MODULE 8: PHILIPPINES INVOICE / BIR COMPLIANCE
-- Run after:
-- 1. supabase/00-reset-public-schema.sql
-- 2. supabase/01-dashboard-module.sql
-- 3. supabase/02-auth-and-branch-management.sql
-- 4. supabase/03-user-role-management.sql
-- 5. supabase/04-product-management.sql
-- 6. supabase/05-inventory-management.sql
-- 7. supabase/06-stock-transfer.sql
-- 8. supabase/07-pos-sales-checkout.sql
--
-- Scope:
-- - Invoice document type controls
-- - Branch/machine-wise serial numbering
-- - BIR POS/CRM machine registration details
-- - Invoice reprint and void controls
-- - X-reading and Z-reading summaries

create extension if not exists pgcrypto;

alter table public.sales_orders
  add column if not exists bir_document_type text not null default 'sales_invoice',
  add column if not exists bir_invoice_title text,
  add column if not exists bir_machine_id uuid,
  add column if not exists bir_series_id uuid,
  add column if not exists bir_sequence_number bigint,
  add column if not exists bir_reprint_count integer not null default 0 check (bir_reprint_count >= 0),
  add column if not exists bir_last_reprinted_at timestamptz,
  add column if not exists bir_voided_by uuid references public.user_profiles(id) on delete set null,
  add column if not exists bir_voided_at timestamptz,
  add column if not exists bir_void_reason text;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'sales_orders_bir_document_type_check'
      and conrelid = 'public.sales_orders'::regclass
  ) then
    alter table public.sales_orders
      add constraint sales_orders_bir_document_type_check
      check (bir_document_type in ('sales_invoice', 'cash_invoice', 'charge_invoice', 'credit_invoice', 'service_invoice', 'billing_invoice'));
  end if;
end;
$$;

create table if not exists public.bir_pos_machines (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches(id) on delete restrict,
  machine_code text not null,
  machine_name text not null,
  machine_serial_number text,
  min_number text,
  accreditation_number text,
  permit_number text,
  permit_issued_at date,
  permit_valid_until date,
  software_name text not null default 'Clean Build POS',
  software_version text,
  is_default boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (branch_id, machine_code)
);

create table if not exists public.bir_invoice_series (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches(id) on delete restrict,
  machine_id uuid references public.bir_pos_machines(id) on delete restrict,
  document_type text not null check (document_type in ('sales_invoice', 'cash_invoice', 'charge_invoice', 'credit_invoice', 'service_invoice', 'billing_invoice')),
  prefix text not null default 'INV-',
  start_number bigint not null default 1 check (start_number > 0),
  current_number bigint not null default 1 check (current_number > 0),
  end_number bigint not null default 9999999 check (end_number > 0),
  digits integer not null default 7 check (digits between 4 and 12),
  authority_to_print text,
  atp_issued_at date,
  atp_valid_until date,
  is_default boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (end_number >= start_number),
  check (current_number >= start_number and current_number <= end_number + 1)
);

create table if not exists public.bir_invoice_reprint_logs (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.sales_orders(id) on delete restrict,
  branch_id uuid not null references public.branches(id) on delete restrict,
  invoice_number text not null,
  copy_number integer not null check (copy_number > 0),
  reason text not null,
  reprinted_by uuid references public.user_profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.bir_readings (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches(id) on delete restrict,
  machine_id uuid references public.bir_pos_machines(id) on delete set null,
  reading_type text not null check (reading_type in ('x', 'z')),
  reading_number text not null unique,
  business_date date not null default current_date,
  period_start timestamptz,
  period_end timestamptz,
  first_invoice_number text,
  last_invoice_number text,
  gross_sales numeric(14, 2) not null default 0,
  discount_total numeric(14, 2) not null default 0,
  vat_total numeric(14, 2) not null default 0,
  net_sales numeric(14, 2) not null default 0,
  vatable_sales numeric(14, 2) not null default 0,
  vat_exempt_sales numeric(14, 2) not null default 0,
  zero_rated_sales numeric(14, 2) not null default 0,
  non_vat_sales numeric(14, 2) not null default 0,
  completed_order_count integer not null default 0,
  voided_order_count integer not null default 0,
  voided_amount numeric(14, 2) not null default 0,
  generated_by uuid references public.user_profiles(id) on delete set null,
  status text not null default 'posted' check (status in ('posted', 'voided')),
  created_at timestamptz not null default now()
);

create unique index if not exists idx_bir_z_readings_once
on public.bir_readings(branch_id, coalesce(machine_id, '00000000-0000-0000-0000-000000000000'::uuid), business_date)
where reading_type = 'z' and status = 'posted';

create index if not exists idx_bir_machines_branch on public.bir_pos_machines(branch_id, is_active);
create index if not exists idx_bir_series_branch_machine on public.bir_invoice_series(branch_id, machine_id, document_type, is_active);
create index if not exists idx_bir_reprints_order on public.bir_invoice_reprint_logs(order_id, created_at desc);
create index if not exists idx_bir_readings_branch_date on public.bir_readings(branch_id, business_date desc);
create index if not exists idx_sales_orders_bir_machine on public.sales_orders(bir_machine_id, business_date);

drop trigger if exists set_bir_pos_machines_updated_at on public.bir_pos_machines;
create trigger set_bir_pos_machines_updated_at
before update on public.bir_pos_machines
for each row execute function public.set_updated_at();

drop trigger if exists set_bir_invoice_series_updated_at on public.bir_invoice_series;
create trigger set_bir_invoice_series_updated_at
before update on public.bir_invoice_series
for each row execute function public.set_updated_at();

alter table public.bir_pos_machines enable row level security;
alter table public.bir_invoice_series enable row level security;
alter table public.bir_invoice_reprint_logs enable row level security;
alter table public.bir_readings enable row level security;

drop policy if exists bir_machines_select_by_role on public.bir_pos_machines;
create policy bir_machines_select_by_role
on public.bir_pos_machines
for select
to authenticated
using (
  public.current_user_is_admin()
  or public.current_user_role() = 'auditor'
  or branch_id = public.current_user_branch_id()
);

drop policy if exists bir_machines_admin_manager_write on public.bir_pos_machines;
create policy bir_machines_admin_manager_write
on public.bir_pos_machines
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

drop policy if exists bir_series_select_by_role on public.bir_invoice_series;
create policy bir_series_select_by_role
on public.bir_invoice_series
for select
to authenticated
using (
  public.current_user_is_admin()
  or public.current_user_role() = 'auditor'
  or branch_id = public.current_user_branch_id()
);

drop policy if exists bir_series_admin_manager_write on public.bir_invoice_series;
create policy bir_series_admin_manager_write
on public.bir_invoice_series
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

drop policy if exists bir_reprints_select_by_role on public.bir_invoice_reprint_logs;
create policy bir_reprints_select_by_role
on public.bir_invoice_reprint_logs
for select
to authenticated
using (
  public.current_user_is_admin()
  or public.current_user_role() = 'auditor'
  or branch_id = public.current_user_branch_id()
);

drop policy if exists bir_readings_select_by_role on public.bir_readings;
create policy bir_readings_select_by_role
on public.bir_readings
for select
to authenticated
using (
  public.current_user_is_admin()
  or public.current_user_role() = 'auditor'
  or branch_id = public.current_user_branch_id()
);

create or replace function public.bir_invoice_title(p_document_type text)
returns text
language sql
immutable
as $$
  select case p_document_type
    when 'cash_invoice' then 'Cash Invoice'
    when 'charge_invoice' then 'Charge Invoice'
    when 'credit_invoice' then 'Credit Invoice'
    when 'service_invoice' then 'Service Invoice'
    when 'billing_invoice' then 'Billing Invoice'
    else 'Sales Invoice'
  end
$$;

create or replace function public.bir_can_manage_branch(p_branch_id uuid)
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

create or replace function public.bir_assign_invoice_before_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_machine public.bir_pos_machines;
  v_series public.bir_invoice_series;
  v_document_type text := coalesce(nullif(new.bir_document_type, ''), 'sales_invoice');
begin
  if new.status <> 'completed' then
    return new;
  end if;

  new.bir_document_type := v_document_type;
  new.bir_invoice_title := public.bir_invoice_title(v_document_type);

  select *
  into v_machine
  from public.bir_pos_machines
  where branch_id = new.branch_id
    and is_active = true
    and (new.bir_machine_id is null or id = new.bir_machine_id)
  order by case when id = new.bir_machine_id then 0 when is_default then 1 else 2 end, created_at asc
  limit 1;

  if v_machine.id is not null then
    new.bir_machine_id := v_machine.id;
  end if;

  select *
  into v_series
  from public.bir_invoice_series
  where branch_id = new.branch_id
    and is_active = true
    and document_type = v_document_type
    and (v_machine.id is null or machine_id = v_machine.id or machine_id is null)
    and current_number <= end_number
  order by case when machine_id = v_machine.id then 0 when is_default then 1 else 2 end, created_at asc
  limit 1
  for update;

  if v_series.id is null then
    return new;
  end if;

  new.bir_series_id := v_series.id;
  new.bir_sequence_number := v_series.current_number;
  new.invoice_number := v_series.prefix || lpad(v_series.current_number::text, v_series.digits, '0');

  update public.bir_invoice_series
  set current_number = current_number + 1
  where id = v_series.id;

  return new;
end;
$$;

drop trigger if exists bir_assign_invoice_before_insert on public.sales_orders;
create trigger bir_assign_invoice_before_insert
before insert on public.sales_orders
for each row execute function public.bir_assign_invoice_before_insert();

insert into public.bir_pos_machines (
  branch_id,
  machine_code,
  machine_name,
  is_default,
  is_active,
  software_version
)
select
  b.id,
  b.branch_code || '-POS-01',
  b.name || ' POS 01',
  true,
  true,
  'module-8'
from public.branches b
where b.is_active = true
  and not exists (
    select 1
    from public.bir_pos_machines bpm
    where bpm.branch_id = b.id
  );

insert into public.bir_invoice_series (
  branch_id,
  machine_id,
  document_type,
  prefix,
  start_number,
  current_number,
  end_number,
  digits,
  is_default,
  is_active
)
select
  m.branch_id,
  m.id,
  'sales_invoice',
  m.machine_code || '-',
  1,
  1,
  9999999,
  7,
  true,
  true
from public.bir_pos_machines m
where m.is_active = true
  and not exists (
    select 1
    from public.bir_invoice_series s
    where s.branch_id = m.branch_id
      and s.machine_id = m.id
      and s.document_type = 'sales_invoice'
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
      'bir.view',
      'bir.manage',
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

create or replace function public.bir_compliance_management_get(p_branch_id uuid default null)
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
    raise exception 'BIR compliance module is not available for this role' using errcode = '42501';
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
  machine_rows as (
    select
      m.*,
      b.branch_code,
      b.name as branch_name
    from public.bir_pos_machines m
    join visible_branches b on b.id = m.branch_id
    order by b.name, m.is_default desc, m.machine_code
  ),
  series_rows as (
    select
      s.*,
      b.branch_code,
      b.name as branch_name,
      m.machine_code,
      m.machine_name,
      public.bir_invoice_title(s.document_type) as document_title,
      greatest(s.end_number - s.current_number + 1, 0) as remaining_numbers
    from public.bir_invoice_series s
    join visible_branches b on b.id = s.branch_id
    left join public.bir_pos_machines m on m.id = s.machine_id
    order by b.name, s.document_type, s.is_default desc, s.created_at desc
  ),
  reading_rows as (
    select
      r.*,
      b.branch_code,
      b.name as branch_name,
      m.machine_code
    from public.bir_readings r
    join visible_branches b on b.id = r.branch_id
    left join public.bir_pos_machines m on m.id = r.machine_id
    order by r.created_at desc
    limit 50
  ),
  order_rows as (
    select
      so.id,
      so.branch_id,
      b.branch_code,
      b.name as branch_name,
      so.order_number,
      so.invoice_number,
      so.bir_document_type,
      coalesce(so.bir_invoice_title, public.bir_invoice_title(so.bir_document_type)) as bir_invoice_title,
      so.bir_sequence_number,
      so.bir_reprint_count,
      so.bir_last_reprinted_at,
      so.bir_voided_at,
      so.bir_void_reason,
      so.status,
      so.business_date,
      so.total,
      so.tax_total,
      so.discount_total,
      so.created_at,
      up.full_name as cashier_name,
      m.machine_code
    from public.sales_orders so
    join visible_branches b on b.id = so.branch_id
    left join public.user_profiles up on up.id = so.user_id
    left join public.bir_pos_machines m on m.id = so.bir_machine_id
    order by so.created_at desc
    limit 50
  )
  select jsonb_build_object(
    'summary', jsonb_build_object(
      'machines', coalesce((select count(*) from machine_rows), 0),
      'active_machines', coalesce((select count(*) from machine_rows where is_active), 0),
      'active_series', coalesce((select count(*) from series_rows where is_active), 0),
      'readings', coalesce((select count(*) from reading_rows), 0),
      'reprinted_invoices', coalesce((select count(*) from order_rows where bir_reprint_count > 0), 0),
      'voided_invoices', coalesce((select count(*) from order_rows where status = 'voided'), 0)
    ),
    'document_types', jsonb_build_array(
      jsonb_build_object('label', 'Sales Invoice', 'value', 'sales_invoice'),
      jsonb_build_object('label', 'Cash Invoice', 'value', 'cash_invoice'),
      jsonb_build_object('label', 'Charge Invoice', 'value', 'charge_invoice'),
      jsonb_build_object('label', 'Credit Invoice', 'value', 'credit_invoice'),
      jsonb_build_object('label', 'Service Invoice', 'value', 'service_invoice'),
      jsonb_build_object('label', 'Billing Invoice', 'value', 'billing_invoice')
    ),
    'branches', coalesce((
      select jsonb_agg(
        jsonb_build_object('id', b.id, 'branch_code', b.branch_code, 'name', b.name)
        order by b.name
      )
      from visible_branches b
    ), '[]'::jsonb),
    'machines', coalesce((select jsonb_agg(to_jsonb(machine_rows)) from machine_rows), '[]'::jsonb),
    'series', coalesce((select jsonb_agg(to_jsonb(series_rows)) from series_rows), '[]'::jsonb),
    'readings', coalesce((select jsonb_agg(to_jsonb(reading_rows)) from reading_rows), '[]'::jsonb),
    'orders', coalesce((select jsonb_agg(to_jsonb(order_rows)) from order_rows), '[]'::jsonb),
    'generated_at', now()
  )
  into v_result;

  return v_result;
end;
$$;

create or replace function public.bir_machine_save(p_machine_id uuid, p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor public.user_profiles;
  v_branch_id uuid := nullif(p_payload->>'branch_id', '')::uuid;
  v_machine_id uuid;
begin
  v_actor := public.ensure_active_user();

  if v_branch_id is null then
    raise exception 'Branch is required' using errcode = '23502';
  end if;

  if public.bir_can_manage_branch(v_branch_id) = false then
    raise exception 'You cannot manage BIR machines for this branch' using errcode = '42501';
  end if;

  if coalesce((p_payload->>'is_default')::boolean, false) then
    update public.bir_pos_machines
    set is_default = false
    where branch_id = v_branch_id;
  end if;

  if p_machine_id is null then
    insert into public.bir_pos_machines (
      branch_id,
      machine_code,
      machine_name,
      machine_serial_number,
      min_number,
      accreditation_number,
      permit_number,
      permit_issued_at,
      permit_valid_until,
      software_name,
      software_version,
      is_default,
      is_active
    )
    values (
      v_branch_id,
      upper(trim(coalesce(p_payload->>'machine_code', ''))),
      trim(coalesce(p_payload->>'machine_name', '')),
      nullif(trim(coalesce(p_payload->>'machine_serial_number', '')), ''),
      nullif(trim(coalesce(p_payload->>'min_number', '')), ''),
      nullif(trim(coalesce(p_payload->>'accreditation_number', '')), ''),
      nullif(trim(coalesce(p_payload->>'permit_number', '')), ''),
      nullif(p_payload->>'permit_issued_at', '')::date,
      nullif(p_payload->>'permit_valid_until', '')::date,
      coalesce(nullif(trim(p_payload->>'software_name'), ''), 'Clean Build POS'),
      nullif(trim(coalesce(p_payload->>'software_version', '')), ''),
      coalesce((p_payload->>'is_default')::boolean, false),
      coalesce((p_payload->>'is_active')::boolean, true)
    )
    returning id into v_machine_id;
  else
    update public.bir_pos_machines
    set machine_code = upper(trim(coalesce(p_payload->>'machine_code', machine_code))),
        machine_name = trim(coalesce(p_payload->>'machine_name', machine_name)),
        machine_serial_number = nullif(trim(coalesce(p_payload->>'machine_serial_number', machine_serial_number, '')), ''),
        min_number = nullif(trim(coalesce(p_payload->>'min_number', min_number, '')), ''),
        accreditation_number = nullif(trim(coalesce(p_payload->>'accreditation_number', accreditation_number, '')), ''),
        permit_number = nullif(trim(coalesce(p_payload->>'permit_number', permit_number, '')), ''),
        permit_issued_at = nullif(p_payload->>'permit_issued_at', '')::date,
        permit_valid_until = nullif(p_payload->>'permit_valid_until', '')::date,
        software_name = coalesce(nullif(trim(p_payload->>'software_name'), ''), software_name),
        software_version = nullif(trim(coalesce(p_payload->>'software_version', software_version, '')), ''),
        is_default = coalesce((p_payload->>'is_default')::boolean, is_default),
        is_active = coalesce((p_payload->>'is_active')::boolean, is_active)
    where id = p_machine_id
      and branch_id = v_branch_id
    returning id into v_machine_id;

    if v_machine_id is null then
      raise exception 'Machine not found' using errcode = '02000';
    end if;
  end if;

  perform public.log_activity(
    'bir.machine_saved',
    'bir_pos_machine',
    v_machine_id::text,
    jsonb_build_object('branch_id', v_branch_id),
    v_actor.id
  );

  return public.bir_compliance_management_get(null);
end;
$$;

create or replace function public.bir_series_save(p_series_id uuid, p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor public.user_profiles;
  v_branch_id uuid := nullif(p_payload->>'branch_id', '')::uuid;
  v_machine_id uuid := nullif(p_payload->>'machine_id', '')::uuid;
  v_series_id uuid;
begin
  v_actor := public.ensure_active_user();

  if v_branch_id is null then
    raise exception 'Branch is required' using errcode = '23502';
  end if;

  if public.bir_can_manage_branch(v_branch_id) = false then
    raise exception 'You cannot manage invoice series for this branch' using errcode = '42501';
  end if;

  if coalesce((p_payload->>'is_default')::boolean, false) then
    update public.bir_invoice_series
    set is_default = false
    where branch_id = v_branch_id
      and document_type = coalesce(nullif(p_payload->>'document_type', ''), 'sales_invoice');
  end if;

  if p_series_id is null then
    insert into public.bir_invoice_series (
      branch_id,
      machine_id,
      document_type,
      prefix,
      start_number,
      current_number,
      end_number,
      digits,
      authority_to_print,
      atp_issued_at,
      atp_valid_until,
      is_default,
      is_active
    )
    values (
      v_branch_id,
      v_machine_id,
      coalesce(nullif(p_payload->>'document_type', ''), 'sales_invoice'),
      upper(trim(coalesce(p_payload->>'prefix', 'INV-'))),
      coalesce(nullif(p_payload->>'start_number', '')::bigint, 1),
      coalesce(nullif(p_payload->>'current_number', '')::bigint, coalesce(nullif(p_payload->>'start_number', '')::bigint, 1)),
      coalesce(nullif(p_payload->>'end_number', '')::bigint, 9999999),
      coalesce(nullif(p_payload->>'digits', '')::integer, 7),
      nullif(trim(coalesce(p_payload->>'authority_to_print', '')), ''),
      nullif(p_payload->>'atp_issued_at', '')::date,
      nullif(p_payload->>'atp_valid_until', '')::date,
      coalesce((p_payload->>'is_default')::boolean, false),
      coalesce((p_payload->>'is_active')::boolean, true)
    )
    returning id into v_series_id;
  else
    update public.bir_invoice_series
    set machine_id = v_machine_id,
        document_type = coalesce(nullif(p_payload->>'document_type', ''), document_type),
        prefix = upper(trim(coalesce(p_payload->>'prefix', prefix))),
        start_number = coalesce(nullif(p_payload->>'start_number', '')::bigint, start_number),
        current_number = coalesce(nullif(p_payload->>'current_number', '')::bigint, current_number),
        end_number = coalesce(nullif(p_payload->>'end_number', '')::bigint, end_number),
        digits = coalesce(nullif(p_payload->>'digits', '')::integer, digits),
        authority_to_print = nullif(trim(coalesce(p_payload->>'authority_to_print', authority_to_print, '')), ''),
        atp_issued_at = nullif(p_payload->>'atp_issued_at', '')::date,
        atp_valid_until = nullif(p_payload->>'atp_valid_until', '')::date,
        is_default = coalesce((p_payload->>'is_default')::boolean, is_default),
        is_active = coalesce((p_payload->>'is_active')::boolean, is_active)
    where id = p_series_id
      and branch_id = v_branch_id
    returning id into v_series_id;

    if v_series_id is null then
      raise exception 'Series not found' using errcode = '02000';
    end if;
  end if;

  perform public.log_activity(
    'bir.series_saved',
    'bir_invoice_series',
    v_series_id::text,
    jsonb_build_object('branch_id', v_branch_id),
    v_actor.id
  );

  return public.bir_compliance_management_get(null);
end;
$$;

create or replace function public.bir_log_invoice_reprint(p_order_id uuid, p_reason text default 'Customer copy')
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor public.user_profiles;
  v_order public.sales_orders;
  v_copy_number integer;
begin
  v_actor := public.ensure_active_user();

  select *
  into v_order
  from public.sales_orders
  where id = p_order_id
  for update;

  if v_order.id is null then
    raise exception 'Invoice not found' using errcode = '02000';
  end if;

  if v_actor.role not in ('admin', 'manager', 'cashier') then
    raise exception 'You cannot reprint invoices' using errcode = '42501';
  end if;

  if v_actor.role <> 'admin' and v_actor.branch_id <> v_order.branch_id then
    raise exception 'You cannot reprint invoices for another branch' using errcode = '42501';
  end if;

  v_copy_number := v_order.bir_reprint_count + 1;

  insert into public.bir_invoice_reprint_logs (
    order_id,
    branch_id,
    invoice_number,
    copy_number,
    reason,
    reprinted_by
  )
  values (
    p_order_id,
    v_order.branch_id,
    coalesce(v_order.invoice_number, v_order.order_number),
    v_copy_number,
    coalesce(nullif(trim(p_reason), ''), 'Customer copy'),
    v_actor.id
  );

  update public.sales_orders
  set bir_reprint_count = v_copy_number,
      bir_last_reprinted_at = now()
  where id = p_order_id;

  perform public.log_activity(
    'bir.invoice_reprinted',
    'sales_order',
    p_order_id::text,
    jsonb_build_object('invoice_number', v_order.invoice_number, 'copy_number', v_copy_number),
    v_actor.id
  );

  return public.bir_compliance_management_get(null);
end;
$$;

create or replace function public.bir_void_invoice(p_order_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor public.user_profiles;
  v_order public.sales_orders;
  v_allocation record;
  v_before_total integer;
  v_after_total integer;
begin
  v_actor := public.ensure_active_user();

  select *
  into v_order
  from public.sales_orders
  where id = p_order_id
  for update;

  if v_order.id is null then
    raise exception 'Invoice not found' using errcode = '02000';
  end if;

  if v_order.status <> 'completed' then
    raise exception 'Only completed invoices can be voided' using errcode = '23514';
  end if;

  if nullif(trim(coalesce(p_reason, '')), '') is null then
    raise exception 'Void reason is required' using errcode = '23502';
  end if;

  if v_actor.role <> 'admin' and not (v_actor.role = 'manager' and v_actor.branch_id = v_order.branch_id) then
    raise exception 'Only admin or branch manager can void invoices' using errcode = '42501';
  end if;

  if exists (
    select 1
    from public.bir_readings r
    where r.branch_id = v_order.branch_id
      and r.reading_type = 'z'
      and r.status = 'posted'
      and r.business_date = v_order.business_date
      and (v_order.bir_machine_id is null or r.machine_id is null or r.machine_id = v_order.bir_machine_id)
  ) then
    raise exception 'Invoice cannot be voided after a posted Z-reading for the same business date' using errcode = '23514';
  end if;

  for v_allocation in
    select
      alloc.*,
      soi.product_id,
      soi.product_variant_id
    from public.sales_order_batch_allocations alloc
    join public.sales_order_items soi on soi.id = alloc.order_item_id
    where soi.order_id = p_order_id
  loop
    select coalesce(sum(quantity_on_hand), 0)::integer
    into v_before_total
    from public.inventory_batches
    where branch_id = v_order.branch_id
      and product_id = v_allocation.product_id
      and status = 'active';

    if v_allocation.inventory_batch_id is null then
      raise exception 'Invoice cannot be voided because a saved stock allocation no longer has a batch reference' using errcode = '23514';
    end if;

    update public.inventory_batches
    set quantity_on_hand = quantity_on_hand + v_allocation.quantity,
        status = 'active'
    where id = v_allocation.inventory_batch_id;

    if not found then
      raise exception 'Invoice cannot be voided because the allocated stock batch no longer exists' using errcode = '23514';
    end if;

    v_after_total := v_before_total + v_allocation.quantity;

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
      v_order.branch_id,
      v_allocation.product_id,
      v_allocation.product_variant_id,
      v_allocation.inventory_batch_id,
      'adjustment_plus',
      v_allocation.quantity,
      v_before_total,
      v_after_total,
      v_allocation.unit_cost,
      v_allocation.batch_number,
      v_allocation.expiry_date,
      v_order.invoice_number,
      'Invoice void stock reversal',
      v_actor.id
    );

    perform public.inventory_sync_product_stock(v_order.branch_id, v_allocation.product_id);
  end loop;

  update public.sales_orders
  set status = 'voided',
      bir_voided_by = v_actor.id,
      bir_voided_at = now(),
      bir_void_reason = trim(p_reason)
  where id = p_order_id;

  perform public.log_activity(
    'bir.invoice_voided',
    'sales_order',
    p_order_id::text,
    jsonb_build_object('invoice_number', v_order.invoice_number, 'reason', p_reason),
    v_actor.id
  );

  return public.bir_compliance_management_get(null);
end;
$$;

create or replace function public.bir_generate_reading(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor public.user_profiles;
  v_branch_id uuid := nullif(p_payload->>'branch_id', '')::uuid;
  v_machine_id uuid := nullif(p_payload->>'machine_id', '')::uuid;
  v_type text := coalesce(nullif(p_payload->>'reading_type', ''), 'x');
  v_business_date date := coalesce(nullif(p_payload->>'business_date', '')::date, current_date);
  v_reading_number text;
begin
  v_actor := public.ensure_active_user();

  if v_branch_id is null then
    raise exception 'Branch is required' using errcode = '23502';
  end if;

  if v_type not in ('x', 'z') then
    raise exception 'Invalid reading type' using errcode = '22023';
  end if;

  if public.bir_can_manage_branch(v_branch_id) = false and v_actor.role <> 'auditor' then
    raise exception 'You cannot generate readings for this branch' using errcode = '42501';
  end if;

  if v_type = 'z' and exists (
    select 1
    from public.bir_readings
    where branch_id = v_branch_id
      and coalesce(machine_id, '00000000-0000-0000-0000-000000000000'::uuid) =
          coalesce(v_machine_id, '00000000-0000-0000-0000-000000000000'::uuid)
      and business_date = v_business_date
      and reading_type = 'z'
      and status = 'posted'
  ) then
    raise exception 'Z-reading already exists for this branch, machine, and business date' using errcode = '23505';
  end if;

  v_reading_number := upper(v_type) || '-' || to_char(now(), 'YYYYMMDD-HH24MISS-') || upper(left(replace(gen_random_uuid()::text, '-', ''), 5));

  insert into public.bir_readings (
    branch_id,
    machine_id,
    reading_type,
    reading_number,
    business_date,
    period_start,
    period_end,
    first_invoice_number,
    last_invoice_number,
    gross_sales,
    discount_total,
    vat_total,
    net_sales,
    vatable_sales,
    vat_exempt_sales,
    zero_rated_sales,
    non_vat_sales,
    completed_order_count,
    voided_order_count,
    voided_amount,
    generated_by
  )
  select
    v_branch_id,
    v_machine_id,
    v_type,
    v_reading_number,
    v_business_date,
    min(created_at),
    max(created_at),
    min(invoice_number),
    max(invoice_number),
    coalesce(sum(total) filter (where status = 'completed'), 0),
    coalesce(sum(discount_total) filter (where status = 'completed'), 0),
    coalesce(sum(tax_total) filter (where status = 'completed'), 0),
    coalesce(sum(net_sales) filter (where status = 'completed'), 0),
    coalesce(sum(vatable_sales) filter (where status = 'completed'), 0),
    coalesce(sum(vat_exempt_sales) filter (where status = 'completed'), 0),
    coalesce(sum(zero_rated_sales) filter (where status = 'completed'), 0),
    coalesce(sum(non_vat_sales) filter (where status = 'completed'), 0),
    coalesce(count(*) filter (where status = 'completed'), 0)::integer,
    coalesce(count(*) filter (where status = 'voided'), 0)::integer,
    coalesce(sum(total) filter (where status = 'voided'), 0),
    v_actor.id
  from public.sales_orders
  where branch_id = v_branch_id
    and business_date = v_business_date
    and (v_machine_id is null or bir_machine_id = v_machine_id);

  perform public.log_activity(
    'bir.reading_generated',
    'bir_reading',
    v_reading_number,
    jsonb_build_object('branch_id', v_branch_id, 'machine_id', v_machine_id, 'reading_type', v_type, 'business_date', v_business_date),
    v_actor.id
  );

  return public.bir_compliance_management_get(null);
end;
$$;

revoke all on function public.bir_can_manage_branch(uuid) from public;
revoke all on function public.bir_compliance_management_get(uuid) from public;
revoke all on function public.bir_machine_save(uuid, jsonb) from public;
revoke all on function public.bir_series_save(uuid, jsonb) from public;
revoke all on function public.bir_log_invoice_reprint(uuid, text) from public;
revoke all on function public.bir_void_invoice(uuid, text) from public;
revoke all on function public.bir_generate_reading(jsonb) from public;
grant execute on function public.bir_compliance_management_get(uuid) to authenticated;
grant execute on function public.bir_machine_save(uuid, jsonb) to authenticated;
grant execute on function public.bir_series_save(uuid, jsonb) to authenticated;
grant execute on function public.bir_log_invoice_reprint(uuid, text) to authenticated;
grant execute on function public.bir_void_invoice(uuid, text) to authenticated;
grant execute on function public.bir_generate_reading(jsonb) to authenticated;

notify pgrst, 'reload schema';
