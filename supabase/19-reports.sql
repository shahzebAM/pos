-- MODULE 19: REPORTS
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
-- 15. supabase/14-purchase-management.sql
-- 16. supabase/15-supplier-management.sql
-- 17. supabase/16-customer-management.sql
-- 18. supabase/17-expenses.sql
-- 19. supabase/18-accounting.sql
--
-- Scope:
-- - Daily sales report
-- - Branch sales report
-- - Cashier sales report
-- - Inventory report
-- - Stock movement report
-- - VAT sales report
-- - Senior/PWD discount report
-- - Z-reading report
-- - Profit report

create extension if not exists pgcrypto;

create or replace function public.reports_effective_permissions(p_user_id uuid, p_role text)
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

create or replace function public.reports_visible_branch_ids(p_profile public.user_profiles)
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

create or replace function public.reports_user_can_view(p_branch_id uuid)
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
  v_permissions := public.reports_effective_permissions(v_profile.id, v_profile.role);

  if not coalesce('reports.view' = any(v_permissions), false) and v_profile.role <> 'admin' then
    return false;
  end if;

  if v_profile.role in ('admin', 'auditor') then
    return true;
  end if;

  return p_branch_id is not null and v_profile.branch_id = p_branch_id;
end;
$$;

create or replace function public.reports_management_get(
  p_from date default current_date - 29,
  p_to date default current_date,
  p_branch_id uuid default null,
  p_report_key text default 'overview',
  p_search text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_profile public.user_profiles;
  v_from date := coalesce(p_from, current_date - 29);
  v_to date := coalesce(p_to, current_date);
  v_branch_filter uuid;
  v_branch_ids uuid[];
  v_search text := nullif(lower(trim(coalesce(p_search, ''))), '');
  v_report_key text := coalesce(nullif(trim(p_report_key), ''), 'overview');
  v_result jsonb;
begin
  v_profile := public.ensure_active_user();

  if v_to < v_from then
    raise exception 'To date must be after from date' using errcode = '22007';
  end if;

  v_branch_ids := public.reports_visible_branch_ids(v_profile);

  if v_profile.role in ('admin', 'auditor') then
    v_branch_filter := p_branch_id;
  else
    v_branch_filter := v_profile.branch_id;
  end if;

  if not public.reports_user_can_view(coalesce(v_branch_filter, v_profile.branch_id)) then
    raise exception 'You do not have permission to view reports.' using errcode = '42501';
  end if;

  with visible_branches as (
    select
      b.id,
      b.branch_code,
      b.name,
      b.is_head_office
    from public.branches b
    where b.id = any(v_branch_ids)
      and b.is_active = true
      and (v_branch_filter is null or b.id = v_branch_filter)
  ),
  sales_rows as (
    select
      so.id,
      so.branch_id,
      vb.branch_code,
      vb.name as branch_name,
      so.cashier_id,
      so.user_id,
      coalesce(up.full_name, c.name, 'Unassigned') as cashier_name,
      so.order_number,
      so.invoice_number,
      so.customer_name,
      so.business_date,
      so.created_at,
      so.payment_status,
      so.payment_method_summary,
      so.subtotal,
      so.discount_total,
      so.tax_total,
      case
        when coalesce(so.net_sales, 0) > 0 then so.net_sales
        else greatest(coalesce(so.total, 0) - coalesce(so.tax_total, 0), 0)
      end as net_sales,
      so.total,
      so.vatable_sales,
      so.vat_exempt_sales,
      so.zero_rated_sales,
      so.non_vat_sales,
      coalesce(so.return_total, 0) as return_total,
      coalesce(so.returned_item_count, 0) as returned_item_count,
      so.statutory_discount_type,
      so.statutory_discount_amount,
      so.statutory_vat_exempt_amount,
      so.statutory_special_discount_amount,
      so.beneficiary_name,
      so.beneficiary_id_number,
      so.beneficiary_id_type,
      so.bir_document_type,
      so.bir_invoice_title,
      so.bir_sequence_number
    from public.sales_orders so
    join visible_branches vb on vb.id = so.branch_id
    left join public.user_profiles up on up.id = so.user_id
    left join public.cashiers c on c.id = so.cashier_id
    where so.status = 'completed'
      and so.business_date >= v_from
      and so.business_date <= v_to
      and (
        v_search is null
        or lower(coalesce(so.invoice_number, '')) like '%' || v_search || '%'
        or lower(coalesce(so.order_number, '')) like '%' || v_search || '%'
        or lower(coalesce(so.customer_name, '')) like '%' || v_search || '%'
        or lower(coalesce(up.full_name, c.name, '')) like '%' || v_search || '%'
        or lower(coalesce(so.payment_method_summary, '')) like '%' || v_search || '%'
      )
  ),
  item_rows as (
    select
      soi.id,
      soi.order_id,
      sr.branch_id,
      sr.branch_code,
      sr.branch_name,
      sr.business_date,
      soi.product_id,
      soi.product_variant_id,
      soi.product_name,
      soi.sku,
      soi.barcode,
      soi.variant_name,
      soi.quantity,
      soi.unit_price,
      soi.gross_amount,
      soi.discount_amount,
      soi.tax_type,
      soi.tax_rate,
      soi.tax_amount,
      soi.net_amount,
      coalesce(
        nullif(cogs.cogs_amount, 0),
        soi.quantity * coalesce(pv.cost_price, p.cost_price, 0),
        0
      )::numeric(14, 2) as cogs_amount
    from public.sales_order_items soi
    join sales_rows sr on sr.id = soi.order_id
    left join public.products p on p.id = soi.product_id
    left join public.product_variants pv on pv.id = soi.product_variant_id
    left join lateral (
      select coalesce(sum(alloc.quantity * alloc.unit_cost), 0)::numeric(14, 2) as cogs_amount
      from public.sales_order_batch_allocations alloc
      where alloc.order_item_id = soi.id
    ) cogs on true
    where (
      v_search is null
      or lower(coalesce(soi.product_name, '')) like '%' || v_search || '%'
      or lower(coalesce(soi.sku, '')) like '%' || v_search || '%'
      or lower(coalesce(soi.barcode, '')) like '%' || v_search || '%'
      or lower(coalesce(soi.variant_name, '')) like '%' || v_search || '%'
    )
  ),
  payment_rows as (
    select
      sop.id,
      sr.branch_id,
      sr.branch_code,
      sr.branch_name,
      sr.business_date,
      sr.invoice_number,
      sr.order_number,
      coalesce(pm.name, sop.method_label, sop.method, 'Payment') as method_label,
      coalesce(pm.code, sop.method, 'other') as method_code,
      sop.amount,
      coalesce(sop.processor_fee_amount, 0) as processor_fee_amount,
      coalesce(nullif(sop.net_amount, 0), sop.amount - coalesce(sop.processor_fee_amount, 0), sop.amount) as net_amount,
      sop.status,
      sop.reference_number
    from public.sales_order_payments sop
    join sales_rows sr on sr.id = sop.order_id
    left join public.payment_methods pm on pm.id = sop.payment_method_id
    where (
      v_search is null
      or lower(coalesce(sop.reference_number, '')) like '%' || v_search || '%'
      or lower(coalesce(pm.name, sop.method_label, sop.method, '')) like '%' || v_search || '%'
    )
  ),
  expense_rows as (
    select
      e.id,
      e.branch_id,
      vb.branch_code,
      vb.name as branch_name,
      e.expense_number,
      e.expense_date,
      e.description,
      ec.name as category_name,
      e.amount,
      e.tax_amount,
      e.total_amount,
      e.payment_method,
      e.status
    from public.expenses e
    join visible_branches vb on vb.id = e.branch_id
    left join public.expense_categories ec on ec.id = e.category_id
    where e.status in ('approved', 'paid')
      and e.expense_date >= v_from
      and e.expense_date <= v_to
      and (
        v_search is null
        or lower(coalesce(e.expense_number, '')) like '%' || v_search || '%'
        or lower(coalesce(e.description, '')) like '%' || v_search || '%'
        or lower(coalesce(e.payee, '')) like '%' || v_search || '%'
        or lower(coalesce(ec.name, '')) like '%' || v_search || '%'
      )
  ),
  batch_stats as (
    select
      ib.branch_id,
      ib.product_id,
      min(ib.expiry_date) filter (where ib.quantity_on_hand > 0 and ib.expiry_date is not null) as earliest_expiry,
      count(*) filter (where ib.quantity_on_hand > 0 and ib.status = 'active')::integer as active_batches,
      count(*) filter (where ib.quantity_on_hand > 0 and ib.expiry_date < current_date)::integer as expired_batches,
      count(*) filter (where ib.quantity_on_hand > 0 and ib.expiry_date >= current_date and ib.expiry_date <= current_date + 30)::integer as expiring_soon_batches,
      coalesce(sum(ib.quantity_on_hand * ib.unit_cost), 0)::numeric(14, 2) as inventory_value,
      coalesce(sum(ib.quantity_on_hand), 0)::integer as batch_quantity
    from public.inventory_batches ib
    join visible_branches vb on vb.id = ib.branch_id
    where ib.status = 'active'
    group by ib.branch_id, ib.product_id
  ),
  inventory_rows as (
    select
      bi.id,
      bi.branch_id,
      vb.branch_code,
      vb.name as branch_name,
      p.id as product_id,
      p.sku,
      p.barcode,
      p.name as product_name,
      p.category,
      coalesce(pc.name, p.category, 'General') as category_name,
      bi.quantity_on_hand,
      p.reorder_level,
      coalesce(bs.inventory_value, bi.quantity_on_hand * coalesce(p.cost_price, 0), 0)::numeric(14, 2) as inventory_value,
      bs.earliest_expiry,
      coalesce(bs.active_batches, 0) as active_batches,
      coalesce(bs.expired_batches, 0) as expired_batches,
      coalesce(bs.expiring_soon_batches, 0) as expiring_soon_batches,
      case
        when bi.quantity_on_hand = 0 then 'out_of_stock'
        when bi.quantity_on_hand <= p.reorder_level then 'low_stock'
        else 'ok'
      end as stock_status
    from public.branch_inventory bi
    join visible_branches vb on vb.id = bi.branch_id
    join public.products p on p.id = bi.product_id
    left join public.product_categories pc on pc.id = p.category_id
    left join batch_stats bs on bs.branch_id = bi.branch_id and bs.product_id = bi.product_id
    where p.deleted_at is null
      and p.is_active = true
      and (
        v_search is null
        or lower(coalesce(p.name, '')) like '%' || v_search || '%'
        or lower(coalesce(p.sku, '')) like '%' || v_search || '%'
        or lower(coalesce(p.barcode, '')) like '%' || v_search || '%'
        or lower(coalesce(pc.name, p.category, '')) like '%' || v_search || '%'
      )
  ),
  movement_rows as (
    select
      im.id,
      im.branch_id,
      vb.branch_code,
      vb.name as branch_name,
      im.created_at,
      im.movement_type,
      im.quantity_delta,
      im.quantity_before,
      im.quantity_after,
      im.unit_cost,
      im.batch_number,
      im.expiry_date,
      im.reference_number,
      im.reason,
      p.sku,
      p.barcode,
      p.name as product_name,
      pv.variant_name,
      up.full_name as created_by_name
    from public.inventory_movements im
    join visible_branches vb on vb.id = im.branch_id
    join public.products p on p.id = im.product_id
    left join public.product_variants pv on pv.id = im.product_variant_id
    left join public.user_profiles up on up.id = im.created_by
    where im.created_at::date >= v_from
      and im.created_at::date <= v_to
      and (
        v_search is null
        or lower(coalesce(im.reference_number, '')) like '%' || v_search || '%'
        or lower(coalesce(im.reason, '')) like '%' || v_search || '%'
        or lower(coalesce(p.name, '')) like '%' || v_search || '%'
        or lower(coalesce(p.sku, '')) like '%' || v_search || '%'
        or lower(coalesce(pv.variant_name, '')) like '%' || v_search || '%'
      )
  ),
  z_rows as (
    select
      br.id,
      br.branch_id,
      vb.branch_code,
      vb.name as branch_name,
      br.reading_number,
      br.business_date,
      coalesce(bpm.machine_name, 'Default machine') as machine_name,
      br.first_invoice_number,
      br.last_invoice_number,
      br.gross_sales,
      br.discount_total,
      br.vat_total,
      br.net_sales,
      br.completed_order_count,
      br.voided_order_count,
      br.voided_amount,
      up.full_name as generated_by_name,
      br.created_at
    from public.bir_readings br
    join visible_branches vb on vb.id = br.branch_id
    left join public.bir_pos_machines bpm on bpm.id = br.machine_id
    left join public.user_profiles up on up.id = br.generated_by
    where br.reading_type = 'z'
      and br.status = 'posted'
      and br.business_date >= v_from
      and br.business_date <= v_to
      and (
        v_search is null
        or lower(coalesce(br.reading_number, '')) like '%' || v_search || '%'
        or lower(coalesce(br.first_invoice_number, '')) like '%' || v_search || '%'
        or lower(coalesce(br.last_invoice_number, '')) like '%' || v_search || '%'
        or lower(coalesce(bpm.machine_name, '')) like '%' || v_search || '%'
      )
  ),
  senior_pwd_rows as (
    select
      sr.id,
      sr.branch_id,
      sr.branch_code,
      sr.branch_name,
      sr.business_date,
      sr.invoice_number,
      sr.order_number,
      coalesce(spc.customer_type, sr.statutory_discount_type) as customer_type,
      coalesce(spc.beneficiary_name, sr.beneficiary_name, sr.customer_name, 'Beneficiary') as beneficiary_name,
      coalesce(spc.beneficiary_id_type, sr.beneficiary_id_type) as beneficiary_id_type,
      coalesce(spc.beneficiary_id_number, sr.beneficiary_id_number) as beneficiary_id_number,
      coalesce(spc.gross_amount, sr.subtotal) as gross_amount,
      coalesce(spc.regular_discount_amount, sr.statutory_discount_amount, 0) as regular_discount_amount,
      coalesce(spc.special_discount_amount, sr.statutory_special_discount_amount, 0) as special_discount_amount,
      coalesce(spc.vat_exempt_amount, sr.statutory_vat_exempt_amount, 0) as vat_exempt_amount,
      coalesce(spc.total_discount_amount, sr.statutory_discount_amount, 0) as total_discount_amount,
      sr.total
    from sales_rows sr
    left join public.senior_pwd_discount_claims spc on spc.order_id = sr.id
    where sr.statutory_discount_type in ('senior', 'pwd')
      or coalesce(sr.statutory_discount_amount, 0) > 0
      or spc.id is not null
  ),
  sales_detail as (
    select
      sr.*,
      coalesce(item_totals.item_count, 0)::integer as item_count,
      coalesce(item_totals.quantity, 0)::integer as quantity,
      coalesce(item_totals.cogs_amount, 0)::numeric(14, 2) as cogs_amount,
      (sr.net_sales - coalesce(item_totals.cogs_amount, 0))::numeric(14, 2) as gross_profit
    from sales_rows sr
    left join (
      select
        order_id,
        count(*) as item_count,
        sum(quantity) as quantity,
        sum(cogs_amount) as cogs_amount
      from item_rows
      group by order_id
    ) item_totals on item_totals.order_id = sr.id
  ),
  daily_sales as (
    select
      sr.business_date,
      to_char(sr.business_date, 'Mon DD') as label,
      count(*)::integer as orders,
      coalesce(sum(sr.total), 0)::numeric(14, 2) as sales,
      coalesce(sum(sr.net_sales), 0)::numeric(14, 2) as net_sales,
      coalesce(sum(sr.discount_total), 0)::numeric(14, 2) as discounts,
      coalesce(sum(sr.tax_total), 0)::numeric(14, 2) as vat,
      coalesce(sum(sr.return_total), 0)::numeric(14, 2) as returns
    from sales_rows sr
    group by sr.business_date
  ),
  branch_sales as (
    select
      sr.branch_id,
      sr.branch_code,
      sr.branch_name,
      count(*)::integer as orders,
      coalesce(sum(sr.total), 0)::numeric(14, 2) as sales,
      coalesce(sum(sr.net_sales), 0)::numeric(14, 2) as net_sales,
      coalesce(sum(sr.discount_total), 0)::numeric(14, 2) as discounts,
      coalesce(sum(sr.tax_total), 0)::numeric(14, 2) as vat,
      coalesce(avg(sr.total), 0)::numeric(14, 2) as average_order
    from sales_rows sr
    group by sr.branch_id, sr.branch_code, sr.branch_name
  ),
  cashier_sales as (
    select
      coalesce(sr.user_id, sr.cashier_id) as cashier_key,
      sr.cashier_name,
      sr.branch_name,
      count(*)::integer as orders,
      coalesce(sum(sr.total), 0)::numeric(14, 2) as sales,
      coalesce(sum(sr.net_sales), 0)::numeric(14, 2) as net_sales,
      coalesce(avg(sr.total), 0)::numeric(14, 2) as average_order,
      coalesce(sum(sr.discount_total), 0)::numeric(14, 2) as discounts
    from sales_rows sr
    group by coalesce(sr.user_id, sr.cashier_id), sr.cashier_name, sr.branch_name
  ),
  payment_mix as (
    select
      pr.method_code,
      pr.method_label,
      count(*)::integer as payments,
      coalesce(sum(pr.amount), 0)::numeric(14, 2) as amount,
      coalesce(sum(pr.processor_fee_amount), 0)::numeric(14, 2) as fees,
      coalesce(sum(pr.net_amount), 0)::numeric(14, 2) as net_amount
    from payment_rows pr
    group by pr.method_code, pr.method_label
  ),
  vat_sales_report as (
    select
      ir.tax_type,
      case ir.tax_type
        when 'vatable' then 'VATable sales'
        when 'vat_exempt' then 'VAT-exempt sales'
        when 'zero_rated' then 'Zero-rated sales'
        when 'non_vat' then 'Non-VAT sales'
        else ir.tax_type
      end as tax_label,
      count(*)::integer as line_count,
      coalesce(sum(ir.gross_amount), 0)::numeric(14, 2) as gross_amount,
      coalesce(sum(ir.discount_amount), 0)::numeric(14, 2) as discount_amount,
      coalesce(sum(ir.net_amount), 0)::numeric(14, 2) as net_amount,
      coalesce(sum(ir.tax_amount), 0)::numeric(14, 2) as tax_amount
    from item_rows ir
    group by ir.tax_type
  ),
  top_products as (
    select
      ir.product_id,
      ir.product_name,
      coalesce(ir.variant_name, '') as variant_name,
      coalesce(ir.sku, '') as sku,
      coalesce(sum(ir.quantity), 0)::integer as quantity_sold,
      coalesce(sum(ir.net_amount), 0)::numeric(14, 2) as net_sales,
      coalesce(sum(ir.cogs_amount), 0)::numeric(14, 2) as cogs_amount,
      (coalesce(sum(ir.net_amount), 0) - coalesce(sum(ir.cogs_amount), 0))::numeric(14, 2) as gross_profit
    from item_rows ir
    group by ir.product_id, ir.product_name, coalesce(ir.variant_name, ''), coalesce(ir.sku, '')
  ),
  product_sales_quantity as (
    select product_id, coalesce(sum(quantity), 0)::integer as quantity_sold
    from item_rows
    group by product_id
  ),
  slow_moving_products as (
    select
      inv.branch_id,
      inv.branch_code,
      inv.branch_name,
      inv.product_id,
      inv.product_name,
      inv.sku,
      inv.quantity_on_hand,
      coalesce(psq.quantity_sold, 0)::integer as quantity_sold,
      inv.inventory_value,
      inv.earliest_expiry
    from inventory_rows inv
    left join product_sales_quantity psq on psq.product_id = inv.product_id
    where inv.quantity_on_hand > 0
  ),
  profit_report as (
    select
      vb.id as branch_id,
      vb.branch_code,
      vb.name as branch_name,
      coalesce(s.orders, 0)::integer as orders,
      coalesce(s.revenue, 0)::numeric(14, 2) as revenue,
      coalesce(c.cogs, 0)::numeric(14, 2) as cogs,
      (coalesce(s.revenue, 0) - coalesce(c.cogs, 0))::numeric(14, 2) as gross_profit,
      coalesce(e.expenses, 0)::numeric(14, 2) as expenses,
      (coalesce(s.revenue, 0) - coalesce(c.cogs, 0) - coalesce(e.expenses, 0))::numeric(14, 2) as net_profit,
      coalesce(s.vat, 0)::numeric(14, 2) as output_vat,
      coalesce(e.input_vat, 0)::numeric(14, 2) as input_vat
    from visible_branches vb
    left join (
      select branch_id, count(*) as orders, sum(net_sales) as revenue, sum(tax_total) as vat
      from sales_rows
      group by branch_id
    ) s on s.branch_id = vb.id
    left join (
      select branch_id, sum(cogs_amount) as cogs
      from item_rows
      group by branch_id
    ) c on c.branch_id = vb.id
    left join (
      select branch_id, sum(amount) as expenses, sum(tax_amount) as input_vat
      from expense_rows
      group by branch_id
    ) e on e.branch_id = vb.id
    where coalesce(s.orders, 0) > 0 or coalesce(e.expenses, 0) > 0
  )
  select jsonb_build_object(
    'period', jsonb_build_object('from', v_from, 'to', v_to),
    'active_report_key', v_report_key,
    'generated_at', now(),
    'branches', (
      select coalesce(jsonb_agg(
        jsonb_build_object(
          'id', vb.id,
          'branch_code', vb.branch_code,
          'name', vb.name,
          'is_head_office', vb.is_head_office
        )
        order by vb.is_head_office desc, vb.name
      ), '[]'::jsonb)
      from visible_branches vb
    ),
    'summary', jsonb_build_object(
      'orders', coalesce((select count(*) from sales_rows), 0),
      'sales', coalesce((select sum(total) from sales_rows), 0),
      'net_sales', coalesce((select sum(net_sales) from sales_rows), 0),
      'discounts', coalesce((select sum(discount_total) from sales_rows), 0),
      'vat', coalesce((select sum(tax_total) from sales_rows), 0),
      'returns', coalesce((select sum(return_total) from sales_rows), 0),
      'cogs', coalesce((select sum(cogs_amount) from item_rows), 0),
      'gross_profit', coalesce((select sum(net_sales) from sales_rows), 0) - coalesce((select sum(cogs_amount) from item_rows), 0),
      'expenses', coalesce((select sum(amount) from expense_rows), 0),
      'net_profit', coalesce((select sum(net_sales) from sales_rows), 0) - coalesce((select sum(cogs_amount) from item_rows), 0) - coalesce((select sum(amount) from expense_rows), 0),
      'inventory_value', coalesce((select sum(inventory_value) from inventory_rows), 0),
      'low_stock_count', coalesce((select count(*) from inventory_rows where stock_status in ('low_stock', 'out_of_stock')), 0),
      'out_of_stock_count', coalesce((select count(*) from inventory_rows where stock_status = 'out_of_stock'), 0),
      'senior_pwd_discount', coalesce((select sum(total_discount_amount) from senior_pwd_rows), 0),
      'z_reading_count', coalesce((select count(*) from z_rows), 0),
      'payment_amount', coalesce((select sum(amount) from payment_rows), 0),
      'payment_fees', coalesce((select sum(processor_fee_amount) from payment_rows), 0)
    ),
    'daily_sales', coalesce((select jsonb_agg(to_jsonb(ds) order by ds.business_date) from daily_sales ds), '[]'::jsonb),
    'branch_sales', coalesce((select jsonb_agg(to_jsonb(bs) order by bs.sales desc, bs.branch_name) from branch_sales bs), '[]'::jsonb),
    'cashier_sales', coalesce((select jsonb_agg(to_jsonb(cs) order by cs.sales desc, cs.cashier_name) from cashier_sales cs), '[]'::jsonb),
    'payment_mix', coalesce((select jsonb_agg(to_jsonb(pm) order by pm.amount desc, pm.method_label) from payment_mix pm), '[]'::jsonb),
    'sales_detail', coalesce((
      select jsonb_agg(to_jsonb(sd) order by sd.business_date desc, sd.created_at desc)
      from (
        select *
        from sales_detail
        order by business_date desc, created_at desc
        limit 300
      ) sd
    ), '[]'::jsonb),
    'inventory_report', coalesce((
      select jsonb_agg(to_jsonb(inv) order by inv.stock_status desc, inv.branch_name, inv.product_name)
      from (
        select *
        from inventory_rows
        order by
          case stock_status when 'out_of_stock' then 1 when 'low_stock' then 2 else 3 end,
          branch_name,
          product_name
        limit 600
      ) inv
    ), '[]'::jsonb),
    'stock_movement_report', coalesce((
      select jsonb_agg(to_jsonb(mv) order by mv.created_at desc)
      from (
        select *
        from movement_rows
        order by created_at desc
        limit 300
      ) mv
    ), '[]'::jsonb),
    'vat_sales_report', coalesce((select jsonb_agg(to_jsonb(vat) order by vat.tax_type) from vat_sales_report vat), '[]'::jsonb),
    'senior_pwd_report', coalesce((
      select jsonb_agg(to_jsonb(sp) order by sp.business_date desc)
      from (
        select *
        from senior_pwd_rows
        order by business_date desc, invoice_number desc
        limit 300
      ) sp
    ), '[]'::jsonb),
    'z_reading_report', coalesce((
      select jsonb_agg(to_jsonb(zr) order by zr.business_date desc)
      from (
        select *
        from z_rows
        order by business_date desc, created_at desc
        limit 300
      ) zr
    ), '[]'::jsonb),
    'profit_report', coalesce((select jsonb_agg(to_jsonb(pr) order by pr.net_profit desc, pr.branch_name) from profit_report pr), '[]'::jsonb),
    'top_products', coalesce((
      select jsonb_agg(to_jsonb(tp) order by tp.net_sales desc, tp.product_name)
      from (
        select *
        from top_products
        order by net_sales desc, quantity_sold desc
        limit 30
      ) tp
    ), '[]'::jsonb),
    'slow_moving_products', coalesce((
      select jsonb_agg(to_jsonb(sm) order by sm.quantity_sold asc, sm.inventory_value desc)
      from (
        select *
        from slow_moving_products
        order by quantity_sold asc, inventory_value desc, product_name
        limit 30
      ) sm
    ), '[]'::jsonb)
  )
  into v_result;

  return v_result;
end;
$$;

revoke all on function public.reports_management_get(date, date, uuid, text, text) from public;
grant execute on function public.reports_management_get(date, date, uuid, text, text) to authenticated;

notify pgrst, 'reload schema';
