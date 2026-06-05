-- PATCH: DAILY REPORTS SHOW ONLY DAYS WITH RECORDS
--
-- Use this on an existing Supabase project after the modules are installed.
-- It does not drop tables and does not change business data.
--
-- What it does:
-- - Keeps your existing report RPC logic.
-- - Renames each installed report RPC to *_with_zero_days once.
-- - Recreates the original RPC name as a wrapper that filters daily chart arrays.
-- - Removes dates where the daily row has no records and all tracked values are 0.
--
-- Safe to run more than once.

create or replace function public.filter_daily_records_only(
  p_payload jsonb,
  p_key text,
  p_numeric_fields text[]
)
returns jsonb
language plpgsql
immutable
as $$
declare
  v_filtered jsonb;
begin
  if p_payload is null or jsonb_typeof(p_payload->p_key) <> 'array' then
    return p_payload;
  end if;

  select coalesce(jsonb_agg(item.row_value order by item.ordinality), '[]'::jsonb)
  into v_filtered
  from jsonb_array_elements(p_payload->p_key) with ordinality as item(row_value, ordinality)
  where exists (
    select 1
    from unnest(p_numeric_fields) as field(field_name)
    where coalesce(nullif(item.row_value->>field.field_name, '')::numeric, 0) <> 0
  );

  return jsonb_set(p_payload, array[p_key], v_filtered, true);
end;
$$;

do $$
begin
  if to_regprocedure('public.dashboard_get_metrics(date,date,uuid)') is not null
     and to_regprocedure('public.dashboard_get_metrics_with_zero_days(date,date,uuid)') is null then
    alter function public.dashboard_get_metrics(date, date, uuid) rename to dashboard_get_metrics_with_zero_days;
  end if;

  if to_regprocedure('public.dashboard_get_metrics_with_zero_days(date,date,uuid)') is not null then
    execute $sql$
      create or replace function public.dashboard_get_metrics(
        p_from date default current_date - 6,
        p_to date default current_date,
        p_branch_id uuid default null
      )
      returns jsonb
      language sql
      security definer
      set search_path = public
      as $fn$
        select public.filter_daily_records_only(
          public.dashboard_get_metrics_with_zero_days(p_from, p_to, p_branch_id),
          'daily_sales',
          array['orders', 'sales']
        );
      $fn$;
    $sql$;
  end if;
end;
$$;

do $$
begin
  if to_regprocedure('public.tax_management_get(date,date,uuid)') is not null
     and to_regprocedure('public.tax_management_get_with_zero_days(date,date,uuid)') is null then
    alter function public.tax_management_get(date, date, uuid) rename to tax_management_get_with_zero_days;
  end if;

  if to_regprocedure('public.tax_management_get_with_zero_days(date,date,uuid)') is not null then
    execute $sql$
      create or replace function public.tax_management_get(
        p_from date default current_date - 29,
        p_to date default current_date,
        p_branch_id uuid default null
      )
      returns jsonb
      language sql
      security definer
      set search_path = public
      as $fn$
        select public.filter_daily_records_only(
          public.tax_management_get_with_zero_days(p_from, p_to, p_branch_id),
          'daily_tax',
          array['orders', 'gross_sales', 'vat_output', 'percentage_tax_due']
        );
      $fn$;
    $sql$;
  end if;
end;
$$;

do $$
begin
  if to_regprocedure('public.senior_pwd_management_get(date,date,uuid)') is not null
     and to_regprocedure('public.senior_pwd_management_get_with_zero_days(date,date,uuid)') is null then
    alter function public.senior_pwd_management_get(date, date, uuid) rename to senior_pwd_management_get_with_zero_days;
  end if;

  if to_regprocedure('public.senior_pwd_management_get_with_zero_days(date,date,uuid)') is not null then
    execute $sql$
      create or replace function public.senior_pwd_management_get(
        p_from date default current_date - 29,
        p_to date default current_date,
        p_branch_id uuid default null
      )
      returns jsonb
      language sql
      security definer
      set search_path = public
      as $fn$
        select public.filter_daily_records_only(
          public.senior_pwd_management_get_with_zero_days(p_from, p_to, p_branch_id),
          'daily_claims',
          array['claims', 'regular_discount_amount', 'special_discount_amount', 'vat_exempt_amount', 'total_discount_amount']
        );
      $fn$;
    $sql$;
  end if;
end;
$$;

do $$
begin
  if to_regprocedure('public.payment_management_get(date,date,uuid)') is not null
     and to_regprocedure('public.payment_management_get_with_zero_days(date,date,uuid)') is null then
    alter function public.payment_management_get(date, date, uuid) rename to payment_management_get_with_zero_days;
  end if;

  if to_regprocedure('public.payment_management_get_with_zero_days(date,date,uuid)') is not null then
    execute $sql$
      create or replace function public.payment_management_get(
        p_from date default current_date - 29,
        p_to date default current_date,
        p_branch_id uuid default null
      )
      returns jsonb
      language sql
      security definer
      set search_path = public
      as $fn$
        select public.filter_daily_records_only(
          public.payment_management_get_with_zero_days(p_from, p_to, p_branch_id),
          'daily_payments',
          array['payment_count', 'collected_amount', 'processor_fee_amount', 'net_amount']
        );
      $fn$;
    $sql$;
  end if;
end;
$$;

do $$
begin
  if to_regprocedure('public.shift_management_get(date,date,uuid)') is not null
     and to_regprocedure('public.shift_management_get_with_zero_days(date,date,uuid)') is null then
    alter function public.shift_management_get(date, date, uuid) rename to shift_management_get_with_zero_days;
  end if;

  if to_regprocedure('public.shift_management_get_with_zero_days(date,date,uuid)') is not null then
    execute $sql$
      create or replace function public.shift_management_get(
        p_from date default current_date - 6,
        p_to date default current_date,
        p_branch_id uuid default null
      )
      returns jsonb
      language sql
      security definer
      set search_path = public
      as $fn$
        select public.filter_daily_records_only(
          public.shift_management_get_with_zero_days(p_from, p_to, p_branch_id),
          'daily_shifts',
          array['shifts', 'cash_sales', 'total_sales', 'short_over']
        );
      $fn$;
    $sql$;
  end if;
end;
$$;

do $$
begin
  if to_regprocedure('public.returns_management_get(date,date,uuid,text)') is not null
     and to_regprocedure('public.returns_management_get_with_zero_days(date,date,uuid,text)') is null then
    alter function public.returns_management_get(date, date, uuid, text) rename to returns_management_get_with_zero_days;
  end if;

  if to_regprocedure('public.returns_management_get_with_zero_days(date,date,uuid,text)') is not null then
    execute $sql$
      create or replace function public.returns_management_get(
        p_from date default current_date - 29,
        p_to date default current_date,
        p_branch_id uuid default null,
        p_search text default null
      )
      returns jsonb
      language sql
      security definer
      set search_path = public
      as $fn$
        select public.filter_daily_records_only(
          public.returns_management_get_with_zero_days(p_from, p_to, p_branch_id, p_search),
          'daily_returns',
          array['returns', 'return_amount', 'refund_amount', 'credit_memo_amount']
        );
      $fn$;
    $sql$;
  end if;
end;
$$;

do $$
begin
  if to_regprocedure('public.purchase_management_get(date,date,uuid,text)') is not null
     and to_regprocedure('public.purchase_management_get_with_zero_days(date,date,uuid,text)') is null then
    alter function public.purchase_management_get(date, date, uuid, text) rename to purchase_management_get_with_zero_days;
  end if;

  if to_regprocedure('public.purchase_management_get_with_zero_days(date,date,uuid,text)') is not null then
    execute $sql$
      create or replace function public.purchase_management_get(
        p_from date default current_date - 29,
        p_to date default current_date,
        p_branch_id uuid default null,
        p_search text default null
      )
      returns jsonb
      language sql
      security definer
      set search_path = public
      as $fn$
        select public.filter_daily_records_only(
          public.purchase_management_get_with_zero_days(p_from, p_to, p_branch_id, p_search),
          'daily_receipts',
          array['receipts', 'received_value']
        );
      $fn$;
    $sql$;
  end if;
end;
$$;

do $$
begin
  if to_regprocedure('public.supplier_management_get(date,date,uuid,uuid,text)') is not null
     and to_regprocedure('public.supplier_management_get_with_zero_days(date,date,uuid,uuid,text)') is null then
    alter function public.supplier_management_get(date, date, uuid, uuid, text) rename to supplier_management_get_with_zero_days;
  end if;

  if to_regprocedure('public.supplier_management_get_with_zero_days(date,date,uuid,uuid,text)') is not null then
    execute $sql$
      create or replace function public.supplier_management_get(
        p_from date default current_date - 89,
        p_to date default current_date,
        p_branch_id uuid default null,
        p_supplier_id uuid default null,
        p_search text default null
      )
      returns jsonb
      language sql
      security definer
      set search_path = public
      as $fn$
        select public.filter_daily_records_only(
          public.supplier_management_get_with_zero_days(p_from, p_to, p_branch_id, p_supplier_id, p_search),
          'daily_payments',
          array['payments', 'paid_amount']
        );
      $fn$;
    $sql$;
  end if;
end;
$$;

do $$
begin
  if to_regprocedure('public.customer_management_get(date,date,uuid,uuid,text)') is not null
     and to_regprocedure('public.customer_management_get_with_zero_days(date,date,uuid,uuid,text)') is null then
    alter function public.customer_management_get(date, date, uuid, uuid, text) rename to customer_management_get_with_zero_days;
  end if;

  if to_regprocedure('public.customer_management_get_with_zero_days(date,date,uuid,uuid,text)') is not null then
    execute $sql$
      create or replace function public.customer_management_get(
        p_from date default current_date - 89,
        p_to date default current_date,
        p_branch_id uuid default null,
        p_customer_id uuid default null,
        p_search text default null
      )
      returns jsonb
      language sql
      security definer
      set search_path = public
      as $fn$
        select public.filter_daily_records_only(
          public.customer_management_get_with_zero_days(p_from, p_to, p_branch_id, p_customer_id, p_search),
          'daily_sales',
          array['orders', 'sales']
        );
      $fn$;
    $sql$;
  end if;
end;
$$;

do $$
begin
  if to_regprocedure('public.expense_management_get(date,date,uuid,text)') is not null
     and to_regprocedure('public.expense_management_get_with_zero_days(date,date,uuid,text)') is null then
    alter function public.expense_management_get(date, date, uuid, text) rename to expense_management_get_with_zero_days;
  end if;

  if to_regprocedure('public.expense_management_get_with_zero_days(date,date,uuid,text)') is not null then
    execute $sql$
      create or replace function public.expense_management_get(
        p_from date default current_date - 89,
        p_to date default current_date,
        p_branch_id uuid default null,
        p_search text default null
      )
      returns jsonb
      language sql
      security definer
      set search_path = public
      as $fn$
        select public.filter_daily_records_only(
          public.expense_management_get_with_zero_days(p_from, p_to, p_branch_id, p_search),
          'daily_expenses',
          array['expenses', 'total_amount']
        );
      $fn$;
    $sql$;
  end if;
end;
$$;

do $$
begin
  if to_regprocedure('public.accounting_management_get(date,date,uuid,text)') is not null
     and to_regprocedure('public.accounting_management_get_with_zero_days(date,date,uuid,text)') is null then
    alter function public.accounting_management_get(date, date, uuid, text) rename to accounting_management_get_with_zero_days;
  end if;

  if to_regprocedure('public.accounting_management_get_with_zero_days(date,date,uuid,text)') is not null then
    execute $sql$
      create or replace function public.accounting_management_get(
        p_from date default current_date - 29,
        p_to date default current_date,
        p_branch_id uuid default null,
        p_search text default null
      )
      returns jsonb
      language sql
      security definer
      set search_path = public
      as $fn$
        select public.filter_daily_records_only(
          public.accounting_management_get_with_zero_days(p_from, p_to, p_branch_id, p_search),
          'daily_summary',
          array['revenue', 'cogs', 'expenses', 'net_profit']
        );
      $fn$;
    $sql$;
  end if;
end;
$$;

revoke all on function public.filter_daily_records_only(jsonb, text, text[]) from public;

do $$
begin
  if to_regprocedure('public.dashboard_get_metrics(date,date,uuid)') is not null then
    grant execute on function public.dashboard_get_metrics(date, date, uuid) to authenticated;
  end if;

  if to_regprocedure('public.tax_management_get(date,date,uuid)') is not null then
    grant execute on function public.tax_management_get(date, date, uuid) to authenticated;
  end if;

  if to_regprocedure('public.senior_pwd_management_get(date,date,uuid)') is not null then
    grant execute on function public.senior_pwd_management_get(date, date, uuid) to authenticated;
  end if;

  if to_regprocedure('public.payment_management_get(date,date,uuid)') is not null then
    grant execute on function public.payment_management_get(date, date, uuid) to authenticated;
  end if;

  if to_regprocedure('public.shift_management_get(date,date,uuid)') is not null then
    grant execute on function public.shift_management_get(date, date, uuid) to authenticated;
  end if;

  if to_regprocedure('public.returns_management_get(date,date,uuid,text)') is not null then
    grant execute on function public.returns_management_get(date, date, uuid, text) to authenticated;
  end if;

  if to_regprocedure('public.purchase_management_get(date,date,uuid,text)') is not null then
    grant execute on function public.purchase_management_get(date, date, uuid, text) to authenticated;
  end if;

  if to_regprocedure('public.supplier_management_get(date,date,uuid,uuid,text)') is not null then
    grant execute on function public.supplier_management_get(date, date, uuid, uuid, text) to authenticated;
  end if;

  if to_regprocedure('public.customer_management_get(date,date,uuid,uuid,text)') is not null then
    grant execute on function public.customer_management_get(date, date, uuid, uuid, text) to authenticated;
  end if;

  if to_regprocedure('public.expense_management_get(date,date,uuid,text)') is not null then
    grant execute on function public.expense_management_get(date, date, uuid, text) to authenticated;
  end if;

  if to_regprocedure('public.accounting_management_get(date,date,uuid,text)') is not null then
    grant execute on function public.accounting_management_get(date, date, uuid, text) to authenticated;
  end if;
end;
$$;

notify pgrst, 'reload schema';
