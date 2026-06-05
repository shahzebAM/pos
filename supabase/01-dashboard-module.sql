-- MODULE 1: DASHBOARD
-- Run after supabase/00-reset-public-schema.sql.
--
-- Scope:
-- - Sales by branch
-- - Daily sales summary
-- - Cashier performance
-- - Low stock alerts
--
-- This module creates only the minimum clean tables needed for dashboard data.
-- Later modules will extend this schema one module at a time.

create extension if not exists pgcrypto;

create table public.branches (
  id uuid primary key default gen_random_uuid(),
  branch_code text not null unique,
  name text not null,
  is_head_office boolean not null default false,
  bir_rdo_code text,
  bir_rdo_name text,
  address text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.cashiers (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches(id) on delete restrict,
  employee_code text not null unique,
  name text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.products (
  id uuid primary key default gen_random_uuid(),
  sku text not null unique,
  barcode text not null unique,
  name text not null,
  category text not null default 'General',
  reorder_level integer not null default 5 check (reorder_level >= 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.branch_inventory (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict,
  quantity_on_hand integer not null default 0 check (quantity_on_hand >= 0),
  updated_at timestamptz not null default now(),
  unique (branch_id, product_id)
);

create table public.sales_orders (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches(id) on delete restrict,
  cashier_id uuid references public.cashiers(id) on delete set null,
  order_number text not null unique,
  business_date date not null default current_date,
  subtotal numeric(14, 2) not null default 0 check (subtotal >= 0),
  discount_total numeric(14, 2) not null default 0 check (discount_total >= 0),
  tax_total numeric(14, 2) not null default 0 check (tax_total >= 0),
  total numeric(14, 2) not null check (total >= 0),
  status text not null default 'completed' check (status in ('completed', 'voided', 'refunded')),
  created_at timestamptz not null default now()
);

create index idx_dashboard_orders_date on public.sales_orders(business_date, created_at);
create index idx_dashboard_orders_branch on public.sales_orders(branch_id, business_date);
create index idx_dashboard_orders_cashier on public.sales_orders(cashier_id, business_date);
create index idx_dashboard_inventory_branch on public.branch_inventory(branch_id);

alter table public.branches enable row level security;
alter table public.cashiers enable row level security;
alter table public.products enable row level security;
alter table public.branch_inventory enable row level security;
alter table public.sales_orders enable row level security;

-- Module 1 is dashboard-only and exposes aggregated data through an RPC.
-- Raw tables stay protected until the User & Role Management module is installed.

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
  v_from date := coalesce(p_from, current_date - 6);
  v_to date := coalesce(p_to, current_date);
  v_result jsonb;
begin
  if v_to < v_from then
    raise exception 'To date must be after from date' using errcode = '22007';
  end if;

  with scoped_orders as (
    select o.*
    from public.sales_orders o
    where o.status = 'completed'
      and o.business_date >= v_from
      and o.business_date <= v_to
      and (p_branch_id is null or o.branch_id = p_branch_id)
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
      and (p_branch_id is null or b.id = p_branch_id)
    group by b.id, b.branch_code, b.name
  ),
  cashier_sales as (
    select
      c.id as cashier_id,
      c.employee_code,
      c.name as cashier_name,
      b.name as branch_name,
      count(o.id)::integer as orders,
      coalesce(sum(o.total), 0)::numeric(14, 2) as sales,
      coalesce(avg(o.total), 0)::numeric(14, 2) as average_order
    from public.cashiers c
    join public.branches b on b.id = c.branch_id
    left join scoped_orders o on o.cashier_id = c.id
    where c.is_active = true
      and (p_branch_id is null or c.branch_id = p_branch_id)
    group by c.id, c.employee_code, c.name, b.name
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
      and (p_branch_id is null or bi.branch_id = p_branch_id)
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
      select coalesce(jsonb_agg(
        jsonb_build_object(
          'id', b.id,
          'branch_code', b.branch_code,
          'name', b.name,
          'is_head_office', b.is_head_office
        )
        order by b.is_head_office desc, b.name
      ), '[]'::jsonb)
      from public.branches b
      where b.is_active = true
    ),
    'sales_by_branch', (
      select coalesce(jsonb_agg(
        jsonb_build_object(
          'branch_id', bs.branch_id,
          'branch_code', bs.branch_code,
          'label', bs.branch_name,
          'branch_name', bs.branch_name,
          'orders', bs.orders,
          'sales', bs.sales,
          'discounts', bs.discounts,
          'vat', bs.vat
        )
        order by bs.sales desc, bs.branch_name
      ), '[]'::jsonb)
      from branch_sales bs
    ),
    'daily_sales', (
      select coalesce(jsonb_agg(
        jsonb_build_object(
          'date', s.business_date,
          'label', to_char(s.business_date, 'Mon DD'),
          'orders', s.orders,
          'sales', s.sales
        )
        order by s.business_date
      ), '[]'::jsonb)
      from (
        select
          o.business_date,
          count(*)::integer as orders,
          coalesce(sum(o.total), 0)::numeric(14, 2) as sales
        from scoped_orders o
        group by o.business_date
      ) s
    ),
    'cashier_performance', (
      select coalesce(jsonb_agg(
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
      ), '[]'::jsonb)
      from cashier_sales cs
    ),
    'low_stock_alerts', (
      select coalesce(jsonb_agg(to_jsonb(ls) order by ls.quantity_on_hand asc, ls.product_name), '[]'::jsonb)
      from low_stock ls
    ),
    'generated_at', now()
  )
  into v_result;

  return v_result;
end;
$$;

revoke all on function public.dashboard_get_metrics(date, date, uuid) from public;
grant execute on function public.dashboard_get_metrics(date, date, uuid) to anon, authenticated;

-- Seed data for immediate dashboard testing.
insert into public.branches (branch_code, name, is_head_office, bir_rdo_code, bir_rdo_name, address)
values
  ('HO-001', 'Head Office', true, '043', 'Pasig City', 'Ortigas Center, Pasig City'),
  ('BR-CEB', 'Cebu Branch', false, '081', 'Cebu City North', 'Cebu Business Park, Cebu City'),
  ('BR-DVO', 'Davao Branch', false, '113', 'Davao City', 'Lanang, Davao City')
on conflict (branch_code) do nothing;

insert into public.cashiers (branch_id, employee_code, name)
select b.id, x.employee_code, x.name
from (
  values
    ('HO-001', 'CASH-HO-01', 'Mika Santos'),
    ('HO-001', 'CASH-HO-02', 'Paolo Reyes'),
    ('BR-CEB', 'CASH-CEB-01', 'Lara Cruz'),
    ('BR-DVO', 'CASH-DVO-01', 'Nico Lim')
) as x(branch_code, employee_code, name)
join public.branches b on b.branch_code = x.branch_code
on conflict (employee_code) do nothing;

insert into public.products (sku, barcode, name, category, reorder_level)
values
  ('SKU-COFFEE-250', '4800000000011', 'Premium Coffee 250g', 'Grocery', 12),
  ('SKU-RICE-5KG', '4800000000028', 'Jasmine Rice 5kg', 'Grocery', 10),
  ('SKU-ALCOHOL-500', '4800000000035', 'Isopropyl Alcohol 500ml', 'Health', 15),
  ('SKU-MILK-1L', '4800000000042', 'Fresh Milk 1L', 'Dairy', 8),
  ('SKU-BREAD', '4800000000059', 'Whole Wheat Bread', 'Bakery', 6)
on conflict (sku) do nothing;

insert into public.branch_inventory (branch_id, product_id, quantity_on_hand)
select b.id, p.id, x.quantity_on_hand
from (
  values
    ('HO-001', 'SKU-COFFEE-250', 7),
    ('HO-001', 'SKU-RICE-5KG', 25),
    ('HO-001', 'SKU-ALCOHOL-500', 3),
    ('BR-CEB', 'SKU-COFFEE-250', 2),
    ('BR-CEB', 'SKU-MILK-1L', 5),
    ('BR-CEB', 'SKU-BREAD', 0),
    ('BR-DVO', 'SKU-RICE-5KG', 8),
    ('BR-DVO', 'SKU-ALCOHOL-500', 18),
    ('BR-DVO', 'SKU-BREAD', 4)
) as x(branch_code, sku, quantity_on_hand)
join public.branches b on b.branch_code = x.branch_code
join public.products p on p.sku = x.sku
on conflict (branch_id, product_id) do update
set quantity_on_hand = excluded.quantity_on_hand,
    updated_at = now();

insert into public.sales_orders (
  branch_id,
  cashier_id,
  order_number,
  business_date,
  subtotal,
  discount_total,
  tax_total,
  total,
  created_at
)
select
  b.id,
  c.id,
  x.order_number,
  current_date - x.days_ago,
  x.subtotal,
  x.discount_total,
  x.tax_total,
  x.total,
  (current_date - x.days_ago) + x.sale_time::time
from (
  values
    ('HO-001', 'CASH-HO-01', 'SI-HO-0001', 0, '09:12', 8200.00, 250.00, 852.86, 7950.00),
    ('HO-001', 'CASH-HO-02', 'SI-HO-0002', 0, '13:44', 12450.00, 0.00, 1333.93, 12450.00),
    ('BR-CEB', 'CASH-CEB-01', 'SI-CEB-0001', 0, '10:22', 6320.00, 320.00, 642.86, 6000.00),
    ('BR-DVO', 'CASH-DVO-01', 'SI-DVO-0001', 0, '16:05', 5100.00, 100.00, 535.71, 5000.00),
    ('HO-001', 'CASH-HO-01', 'SI-HO-0003', 1, '11:30', 9450.00, 450.00, 964.29, 9000.00),
    ('BR-CEB', 'CASH-CEB-01', 'SI-CEB-0002', 1, '15:18', 7300.00, 0.00, 782.14, 7300.00),
    ('BR-DVO', 'CASH-DVO-01', 'SI-DVO-0002', 2, '12:45', 11100.00, 600.00, 1125.00, 10500.00),
    ('HO-001', 'CASH-HO-02', 'SI-HO-0004', 2, '14:20', 13200.00, 0.00, 1414.29, 13200.00),
    ('BR-CEB', 'CASH-CEB-01', 'SI-CEB-0003', 3, '10:15', 6800.00, 200.00, 707.14, 6600.00),
    ('BR-DVO', 'CASH-DVO-01', 'SI-DVO-0003', 3, '17:40', 8900.00, 300.00, 921.43, 8600.00),
    ('HO-001', 'CASH-HO-01', 'SI-HO-0005', 4, '09:50', 10400.00, 0.00, 1114.29, 10400.00),
    ('BR-CEB', 'CASH-CEB-01', 'SI-CEB-0004', 5, '18:02', 5800.00, 0.00, 621.43, 5800.00),
    ('BR-DVO', 'CASH-DVO-01', 'SI-DVO-0004', 6, '11:08', 7600.00, 100.00, 803.57, 7500.00)
) as x(branch_code, employee_code, order_number, days_ago, sale_time, subtotal, discount_total, tax_total, total)
join public.branches b on b.branch_code = x.branch_code
left join public.cashiers c on c.employee_code = x.employee_code
on conflict (order_number) do nothing;

notify pgrst, 'reload schema';
