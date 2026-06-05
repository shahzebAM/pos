-- MODULE 20: AUDIT LOGS
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
-- 20. supabase/19-reports.sql
--
-- Scope:
-- - Audit trail dashboard
-- - Login/logout history
-- - Deleted record logs
-- - Void/reprint/activity logs
-- - Product price-change audit trigger
-- - Inventory adjustment history
-- - Discount audit records from sales

create extension if not exists pgcrypto;

alter table public.activity_logs
  add column if not exists branch_id uuid references public.branches(id) on delete set null,
  add column if not exists category text not null default 'system',
  add column if not exists severity text not null default 'low',
  add column if not exists user_agent text,
  add column if not exists ip_address text,
  add column if not exists request_id text;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'activity_logs_severity_check'
      and conrelid = 'public.activity_logs'::regclass
  ) then
    alter table public.activity_logs
      add constraint activity_logs_severity_check
      check (severity in ('low', 'medium', 'high', 'critical'));
  end if;
end;
$$;

create index if not exists idx_activity_logs_branch_created on public.activity_logs(branch_id, created_at desc);
create index if not exists idx_activity_logs_category_created on public.activity_logs(category, created_at desc);
create index if not exists idx_activity_logs_severity_created on public.activity_logs(severity, created_at desc);

create or replace function public.audit_uuid_from_text(p_value text)
returns uuid
language plpgsql
immutable
as $$
begin
  if nullif(trim(coalesce(p_value, '')), '') is null then
    return null;
  end if;

  return trim(p_value)::uuid;
exception
  when others then
    return null;
end;
$$;

create or replace function public.audit_classify_category(p_action text, p_entity_type text, p_metadata jsonb default '{}'::jsonb)
returns text
language plpgsql
immutable
as $$
declare
  v_action text := lower(coalesce(p_action, ''));
  v_entity text := lower(coalesce(p_entity_type, ''));
  v_return_type text := lower(coalesce(p_metadata->>'return_type', ''));
  v_senior_pwd_type text := lower(coalesce(p_metadata->>'senior_pwd_type', ''));
begin
  if v_action like 'auth.%' or v_action like '%login%' or v_action like '%logout%' then
    return 'auth';
  end if;

  if v_action like '%hard_deleted%' or v_action like '%.deleted%' or v_action like '%delete%' then
    return 'delete';
  end if;

  if v_action like '%void%' or v_return_type = 'void' then
    return 'void';
  end if;

  if v_action like '%price%' then
    return 'price_change';
  end if;

  if v_action like '%discount%' or v_senior_pwd_type in ('senior', 'pwd') then
    return 'discount';
  end if;

  if v_action like 'inventory.%'
    or v_action like '%stock%'
    or v_entity in ('inventory_movement', 'inventory_batch', 'stock_count', 'stock_transfer') then
    return 'stock';
  end if;

  if v_action like 'transfer.%' then
    return 'transfer';
  end if;

  if v_action like 'staff.%' or v_action like 'user.%' or v_entity in ('user_profile', 'user_access') then
    return 'user';
  end if;

  if v_action like 'branch.%' then
    return 'branch';
  end if;

  if v_action like 'product.%' or v_entity like 'product%' then
    return 'product';
  end if;

  if v_action like 'purchase.%' then
    return 'purchase';
  end if;

  if v_action like 'supplier.%' then
    return 'supplier';
  end if;

  if v_action like 'customer.%' then
    return 'customer';
  end if;

  if v_action like 'expense.%' then
    return 'expense';
  end if;

  if v_action like 'accounting.%' then
    return 'accounting';
  end if;

  if v_action like 'pos.%' or v_entity = 'sales_order' then
    return 'sale';
  end if;

  if v_action like 'bir.%' then
    return 'bir';
  end if;

  return 'system';
end;
$$;

create or replace function public.audit_classify_severity(p_action text, p_entity_type text, p_metadata jsonb default '{}'::jsonb)
returns text
language plpgsql
immutable
as $$
declare
  v_action text := lower(coalesce(p_action, ''));
  v_category text := public.audit_classify_category(p_action, p_entity_type, p_metadata);
begin
  if v_action like '%hard_deleted%' or v_action = 'branch.hard_deleted' then
    return 'critical';
  end if;

  if v_category in ('void', 'delete') then
    return 'high';
  end if;

  if v_category in ('price_change', 'stock', 'user', 'accounting', 'discount') then
    return 'medium';
  end if;

  return 'low';
end;
$$;

create or replace function public.audit_log_branch_id(p_actor_id uuid, p_metadata jsonb default '{}'::jsonb)
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_branch_id uuid;
begin
  v_branch_id := public.audit_uuid_from_text(p_metadata->>'branch_id');

  if v_branch_id is not null then
    return v_branch_id;
  end if;

  select branch_id
  into v_branch_id
  from public.user_profiles
  where id = p_actor_id
  limit 1;

  return v_branch_id;
end;
$$;

create or replace function public.log_activity(
  p_action text,
  p_entity_type text,
  p_entity_id text default null,
  p_metadata jsonb default '{}'::jsonb,
  p_actor_id uuid default auth.uid()
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_metadata jsonb := coalesce(p_metadata, '{}'::jsonb);
begin
  insert into public.activity_logs (
    actor_id,
    action,
    entity_type,
    entity_id,
    metadata,
    branch_id,
    category,
    severity,
    user_agent,
    ip_address,
    request_id
  )
  values (
    p_actor_id,
    p_action,
    p_entity_type,
    p_entity_id,
    v_metadata,
    public.audit_log_branch_id(p_actor_id, v_metadata),
    public.audit_classify_category(p_action, p_entity_type, v_metadata),
    public.audit_classify_severity(p_action, p_entity_type, v_metadata),
    nullif(v_metadata->>'user_agent', ''),
    nullif(v_metadata->>'ip_address', ''),
    nullif(v_metadata->>'request_id', '')
  );
end;
$$;

update public.activity_logs al
set branch_id = coalesce(al.branch_id, public.audit_log_branch_id(al.actor_id, al.metadata)),
    category = public.audit_classify_category(al.action, al.entity_type, al.metadata),
    severity = public.audit_classify_severity(al.action, al.entity_type, al.metadata),
    user_agent = coalesce(al.user_agent, nullif(al.metadata->>'user_agent', '')),
    ip_address = coalesce(al.ip_address, nullif(al.metadata->>'ip_address', '')),
    request_id = coalesce(al.request_id, nullif(al.metadata->>'request_id', ''));

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
      'purchases.view',
      'purchases.manage',
      'purchases.approve',
      'purchases.receive',
      'suppliers.view',
      'suppliers.manage',
      'suppliers.pay',
      'customers.view',
      'customers.manage',
      'customers.credit',
      'customers.loyalty',
      'expenses.view',
      'expenses.manage',
      'expenses.approve',
      'accounting.view',
      'accounting.manage',
      'accounting.close',
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
      'purchases.view',
      'purchases.manage',
      'purchases.approve',
      'purchases.receive',
      'suppliers.view',
      'suppliers.manage',
      'suppliers.pay',
      'customers.view',
      'customers.manage',
      'customers.credit',
      'customers.loyalty',
      'expenses.view',
      'expenses.manage',
      'expenses.approve',
      'accounting.view',
      'activity.view',
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
      'purchases.view',
      'suppliers.view',
      'customers.view',
      'expenses.view',
      'accounting.view',
      'activity.view',
      'reports.view'
    ]::text[]
    else array[
      'dashboard.view',
      'products.view',
      'customers.view',
      'pos.sell',
      'senior_pwd.apply',
      'shifts.view',
      'returns.view',
      'returns.manage'
    ]::text[]
  end
$$;

drop policy if exists activity_logs_admin_auditor_select on public.activity_logs;
drop policy if exists activity_logs_audit_select on public.activity_logs;
create policy activity_logs_audit_select
on public.activity_logs
for select
to authenticated
using (
  public.current_user_is_admin()
  or public.current_user_role() = 'auditor'
  or (
    public.current_user_role() = 'manager'
    and (
      branch_id = public.current_user_branch_id()
      or actor_id = auth.uid()
    )
  )
);

create or replace function public.audit_product_price_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.log_activity(
    'product.price_changed',
    'product',
    new.id::text,
    jsonb_build_object(
      'sku', new.sku,
      'barcode', new.barcode,
      'name', new.name,
      'old_cost_price', old.cost_price,
      'new_cost_price', new.cost_price,
      'old_selling_price', old.selling_price,
      'new_selling_price', new.selling_price
    ),
    auth.uid()
  );

  return new;
end;
$$;

drop trigger if exists audit_products_price_change on public.products;
create trigger audit_products_price_change
after update of cost_price, selling_price on public.products
for each row
when (
  old.cost_price is distinct from new.cost_price
  or old.selling_price is distinct from new.selling_price
)
execute function public.audit_product_price_change();

create or replace function public.audit_product_variant_price_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.log_activity(
    'product_variant.price_changed',
    'product_variant',
    new.id::text,
    jsonb_build_object(
      'product_id', new.product_id,
      'variant_name', new.variant_name,
      'sku', new.sku,
      'barcode', new.barcode,
      'old_cost_price', old.cost_price,
      'new_cost_price', new.cost_price,
      'old_selling_price', old.selling_price,
      'new_selling_price', new.selling_price
    ),
    auth.uid()
  );

  return new;
end;
$$;

drop trigger if exists audit_product_variants_price_change on public.product_variants;
create trigger audit_product_variants_price_change
after update of cost_price, selling_price on public.product_variants
for each row
when (
  old.cost_price is distinct from new.cost_price
  or old.selling_price is distinct from new.selling_price
)
execute function public.audit_product_variant_price_change();

create or replace function public.audit_effective_permissions(p_user_id uuid, p_role text)
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

create or replace function public.audit_visible_branch_ids(p_profile public.user_profiles)
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

create or replace function public.audit_user_can_view(p_branch_id uuid)
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
  v_permissions := public.audit_effective_permissions(v_profile.id, v_profile.role);

  if not coalesce('activity.view' = any(v_permissions), false) and v_profile.role <> 'admin' then
    return false;
  end if;

  if v_profile.role in ('admin', 'auditor') then
    return true;
  end if;

  return p_branch_id is not null and v_profile.branch_id = p_branch_id;
end;
$$;

create or replace function public.audit_log_auth_event(
  p_action text default 'auth.login',
  p_metadata jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor public.user_profiles;
  v_action text := coalesce(nullif(trim(p_action), ''), 'auth.login');
begin
  v_actor := public.ensure_active_user();

  if v_action not in ('auth.login', 'auth.logout', 'auth.session_refreshed') then
    raise exception 'Invalid audit auth action' using errcode = '22023';
  end if;

  perform public.log_activity(
    v_action,
    'user_profile',
    v_actor.id::text,
    coalesce(p_metadata, '{}'::jsonb) || jsonb_build_object(
      'username', v_actor.username,
      'role', v_actor.role,
      'branch_id', v_actor.branch_id
    ),
    v_actor.id
  );

  update public.user_profiles
  set last_seen_at = now()
  where id = v_actor.id;
end;
$$;

create or replace function public.audit_management_get(
  p_from date default current_date - 29,
  p_to date default current_date,
  p_branch_id uuid default null,
  p_actor_id uuid default null,
  p_category text default null,
  p_severity text default null,
  p_search text default null,
  p_limit integer default 200
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
  v_category text := nullif(lower(trim(coalesce(p_category, ''))), '');
  v_severity text := nullif(lower(trim(coalesce(p_severity, ''))), '');
  v_search text := nullif(lower(trim(coalesce(p_search, ''))), '');
  v_limit integer := least(greatest(coalesce(p_limit, 200), 25), 500);
  v_result jsonb;
begin
  v_profile := public.ensure_active_user();

  if v_to < v_from then
    raise exception 'To date must be after from date' using errcode = '22007';
  end if;

  v_branch_ids := public.audit_visible_branch_ids(v_profile);

  if v_profile.role in ('admin', 'auditor') then
    v_branch_filter := p_branch_id;
  else
    v_branch_filter := v_profile.branch_id;
  end if;

  if not public.audit_user_can_view(coalesce(v_branch_filter, v_profile.branch_id)) then
    raise exception 'You do not have permission to view audit logs.' using errcode = '42501';
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
  visible_actors as (
    select
      up.id,
      up.full_name,
      up.username,
      up.role,
      up.branch_id,
      b.branch_code,
      b.name as branch_name
    from public.user_profiles up
    left join public.branches b on b.id = up.branch_id
    where up.deleted_at is null
      and (
        v_profile.role in ('admin', 'auditor')
        or up.branch_id = v_profile.branch_id
        or up.id = v_profile.id
      )
  ),
  scoped_logs as (
    select
      al.id,
      al.actor_id,
      actor.full_name as actor_name,
      actor.username as actor_username,
      actor.role as actor_role,
      al.action,
      al.entity_type,
      al.entity_id,
      al.metadata,
      coalesce(al.branch_id, actor.branch_id) as branch_id,
      coalesce(b.branch_code, actor.branch_code, 'SYS') as branch_code,
      coalesce(b.name, actor.branch_name, 'System') as branch_name,
      al.category,
      al.severity,
      al.user_agent,
      al.ip_address,
      al.request_id,
      al.created_at
    from public.activity_logs al
    left join visible_actors actor on actor.id = al.actor_id
    left join public.branches b on b.id = coalesce(al.branch_id, actor.branch_id)
    where al.created_at::date >= v_from
      and al.created_at::date <= v_to
      and (p_actor_id is null or al.actor_id = p_actor_id)
      and (v_category is null or al.category = v_category)
      and (v_severity is null or al.severity = v_severity)
      and (
        v_profile.role in ('admin', 'auditor')
        or coalesce(al.branch_id, actor.branch_id) = v_profile.branch_id
        or al.actor_id = v_profile.id
      )
      and (v_branch_filter is null or coalesce(al.branch_id, actor.branch_id) = v_branch_filter)
      and (
        v_search is null
        or lower(coalesce(al.action, '')) like '%' || v_search || '%'
        or lower(coalesce(al.entity_type, '')) like '%' || v_search || '%'
        or lower(coalesce(al.entity_id, '')) like '%' || v_search || '%'
        or lower(coalesce(actor.full_name, '')) like '%' || v_search || '%'
        or lower(coalesce(actor.username, '')) like '%' || v_search || '%'
        or lower(coalesce(al.metadata::text, '')) like '%' || v_search || '%'
      )
  ),
  discount_events as (
    select
      so.id,
      so.branch_id,
      vb.branch_code,
      vb.name as branch_name,
      so.user_id as actor_id,
      coalesce(up.full_name, c.name, 'Unassigned') as actor_name,
      coalesce(up.username, c.employee_code, '-') as actor_username,
      so.order_number,
      so.invoice_number,
      so.customer_name,
      so.business_date,
      so.created_at,
      coalesce(so.discount_total, 0) as discount_total,
      coalesce(so.statutory_discount_type, 'none') as statutory_discount_type,
      coalesce(so.statutory_discount_amount, 0) as statutory_discount_amount,
      coalesce(so.statutory_special_discount_amount, 0) as statutory_special_discount_amount,
      so.total
    from public.sales_orders so
    join visible_branches vb on vb.id = so.branch_id
    left join public.user_profiles up on up.id = so.user_id
    left join public.cashiers c on c.id = so.cashier_id
    where so.business_date >= v_from
      and so.business_date <= v_to
      and so.status = 'completed'
      and coalesce(so.discount_total, 0) > 0
      and (p_actor_id is null or so.user_id = p_actor_id)
      and (
        v_search is null
        or lower(coalesce(so.invoice_number, '')) like '%' || v_search || '%'
        or lower(coalesce(so.order_number, '')) like '%' || v_search || '%'
        or lower(coalesce(so.customer_name, '')) like '%' || v_search || '%'
        or lower(coalesce(up.full_name, c.name, '')) like '%' || v_search || '%'
      )
  ),
  stock_adjustment_events as (
    select
      im.id,
      im.branch_id,
      vb.branch_code,
      vb.name as branch_name,
      im.created_by as actor_id,
      up.full_name as actor_name,
      up.username as actor_username,
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
      pv.variant_name
    from public.inventory_movements im
    join visible_branches vb on vb.id = im.branch_id
    join public.products p on p.id = im.product_id
    left join public.product_variants pv on pv.id = im.product_variant_id
    left join public.user_profiles up on up.id = im.created_by
    where im.created_at::date >= v_from
      and im.created_at::date <= v_to
      and im.movement_type in ('adjustment_plus', 'adjustment_minus', 'damaged', 'expired')
      and (p_actor_id is null or im.created_by = p_actor_id)
      and (
        v_search is null
        or lower(coalesce(im.reference_number, '')) like '%' || v_search || '%'
        or lower(coalesce(im.reason, '')) like '%' || v_search || '%'
        or lower(coalesce(p.name, '')) like '%' || v_search || '%'
        or lower(coalesce(p.sku, '')) like '%' || v_search || '%'
        or lower(coalesce(pv.variant_name, '')) like '%' || v_search || '%'
      )
  ),
  daily_events as (
    select
      created_at::date as event_date,
      to_char(created_at::date, 'Mon DD') as label,
      count(*)::integer as events,
      count(*) filter (where severity in ('high', 'critical'))::integer as risky_events
    from scoped_logs
    group by created_at::date
  ),
  category_summary as (
    select
      category,
      initcap(replace(category, '_', ' ')) as label,
      count(*)::integer as events
    from scoped_logs
    group by category
  ),
  severity_summary as (
    select
      severity,
      initcap(severity) as label,
      count(*)::integer as events
    from scoped_logs
    group by severity
  )
  select jsonb_build_object(
    'period', jsonb_build_object('from', v_from, 'to', v_to),
    'generated_at', now(),
    'branches', coalesce((
      select jsonb_agg(to_jsonb(vb) order by vb.is_head_office desc, vb.name)
      from visible_branches vb
    ), '[]'::jsonb),
    'actors', coalesce((
      select jsonb_agg(to_jsonb(va) order by va.full_name)
      from visible_actors va
    ), '[]'::jsonb),
    'summary', jsonb_build_object(
      'total_events', coalesce((select count(*) from scoped_logs), 0),
      'critical_events', coalesce((select count(*) from scoped_logs where severity = 'critical'), 0),
      'high_events', coalesce((select count(*) from scoped_logs where severity = 'high'), 0),
      'login_events', coalesce((select count(*) from scoped_logs where category = 'auth'), 0),
      'void_events', coalesce((select count(*) from scoped_logs where category = 'void'), 0),
      'deleted_events', coalesce((select count(*) from scoped_logs where category = 'delete'), 0),
      'price_changes', coalesce((select count(*) from scoped_logs where category = 'price_change'), 0),
      'discount_events', coalesce((select count(*) from discount_events), 0),
      'stock_adjustments', coalesce((select count(*) from stock_adjustment_events), 0),
      'unique_actors', coalesce((select count(distinct actor_id) from scoped_logs where actor_id is not null), 0)
    ),
    'daily_events', coalesce((select jsonb_agg(to_jsonb(de) order by de.event_date) from daily_events de), '[]'::jsonb),
    'category_summary', coalesce((select jsonb_agg(to_jsonb(cs) order by cs.events desc, cs.category) from category_summary cs), '[]'::jsonb),
    'severity_summary', coalesce((select jsonb_agg(to_jsonb(ss) order by ss.events desc, ss.severity) from severity_summary ss), '[]'::jsonb),
    'activity_logs', coalesce((
      select jsonb_agg(to_jsonb(row) order by row.created_at desc)
      from (
        select *
        from scoped_logs
        order by created_at desc
        limit v_limit
      ) row
    ), '[]'::jsonb),
    'login_history', coalesce((
      select jsonb_agg(to_jsonb(row) order by row.created_at desc)
      from (
        select *
        from scoped_logs
        where category = 'auth'
        order by created_at desc
        limit 250
      ) row
    ), '[]'::jsonb),
    'void_events', coalesce((
      select jsonb_agg(to_jsonb(row) order by row.created_at desc)
      from (
        select *
        from scoped_logs
        where category = 'void'
        order by created_at desc
        limit 250
      ) row
    ), '[]'::jsonb),
    'deleted_events', coalesce((
      select jsonb_agg(to_jsonb(row) order by row.created_at desc)
      from (
        select *
        from scoped_logs
        where category = 'delete'
        order by created_at desc
        limit 250
      ) row
    ), '[]'::jsonb),
    'price_change_events', coalesce((
      select jsonb_agg(to_jsonb(row) order by row.created_at desc)
      from (
        select *
        from scoped_logs
        where category = 'price_change'
        order by created_at desc
        limit 250
      ) row
    ), '[]'::jsonb),
    'discount_events', coalesce((
      select jsonb_agg(to_jsonb(row) order by row.created_at desc)
      from (
        select *
        from discount_events
        order by created_at desc
        limit 250
      ) row
    ), '[]'::jsonb),
    'stock_adjustment_events', coalesce((
      select jsonb_agg(to_jsonb(row) order by row.created_at desc)
      from (
        select *
        from stock_adjustment_events
        order by created_at desc
        limit 250
      ) row
    ), '[]'::jsonb)
  )
  into v_result;

  return v_result;
end;
$$;

revoke all on function public.audit_log_auth_event(text, jsonb) from public;
revoke all on function public.audit_management_get(date, date, uuid, uuid, text, text, text, integer) from public;

grant execute on function public.audit_log_auth_event(text, jsonb) to authenticated;
grant execute on function public.audit_management_get(date, date, uuid, uuid, text, text, text, integer) to authenticated;

notify pgrst, 'reload schema';
