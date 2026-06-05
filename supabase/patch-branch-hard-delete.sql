-- PATCH: SAFE BRANCH HARD DELETE
-- Use this on an existing database if Module 2 was already installed before
-- branch hard delete was added.
--
-- This adds:
-- - branch_hard_delete(p_branch_id uuid)
--
-- Behavior:
-- - Admin-only
-- - Refuses to delete head office
-- - Refuses to delete branches with linked users, cashiers, sales, stock,
--   inventory movements, active batches, or stock counts
-- - Deletes only clean/test branches with no business history

create or replace function public.branch_hard_delete(p_branch_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor public.user_profiles;
  v_branch public.branches;
  v_blockers text[] := array[]::text[];
  v_count integer;
begin
  v_actor := public.ensure_active_user();

  if v_actor.role <> 'admin' then
    raise exception 'Only admins can hard delete branches' using errcode = '42501';
  end if;

  select *
  into v_branch
  from public.branches
  where id = p_branch_id
  limit 1;

  if v_branch.id is null then
    raise exception 'Branch not found' using errcode = '02000';
  end if;

  if v_branch.is_head_office then
    raise exception 'Head office cannot be hard deleted' using errcode = '23514';
  end if;

  select count(*)::integer
  into v_count
  from public.sales_orders
  where branch_id = p_branch_id;

  if v_count > 0 then
    v_blockers := array_append(v_blockers, v_count || ' sales order(s)');
  end if;

  select count(*)::integer
  into v_count
  from public.cashiers
  where branch_id = p_branch_id;

  if v_count > 0 then
    v_blockers := array_append(v_blockers, v_count || ' cashier record(s)');
  end if;

  select count(*)::integer
  into v_count
  from public.user_profiles
  where branch_id = p_branch_id;

  if v_count > 0 then
    v_blockers := array_append(v_blockers, v_count || ' assigned user(s)');
  end if;

  select count(*)::integer
  into v_count
  from public.branch_inventory
  where branch_id = p_branch_id
    and quantity_on_hand > 0;

  if v_count > 0 then
    v_blockers := array_append(v_blockers, v_count || ' stocked item(s)');
  end if;

  if to_regclass('public.inventory_batches') is not null then
    execute
      'select count(*)::integer from public.inventory_batches where branch_id = $1 and quantity_on_hand > 0'
    into v_count
    using p_branch_id;

    if v_count > 0 then
      v_blockers := array_append(v_blockers, v_count || ' active inventory batch(es)');
    end if;
  end if;

  if to_regclass('public.inventory_movements') is not null then
    execute
      'select count(*)::integer from public.inventory_movements where branch_id = $1'
    into v_count
    using p_branch_id;

    if v_count > 0 then
      v_blockers := array_append(v_blockers, v_count || ' inventory movement(s)');
    end if;
  end if;

  if to_regclass('public.stock_counts') is not null then
    execute
      'select count(*)::integer from public.stock_counts where branch_id = $1'
    into v_count
    using p_branch_id;

    if v_count > 0 then
      v_blockers := array_append(v_blockers, v_count || ' stock count(s)');
    end if;
  end if;

  if array_length(v_blockers, 1) is not null then
    raise exception
      'Branch cannot be hard deleted because it has linked %. Disable it instead.',
      array_to_string(v_blockers, ', ')
      using errcode = '23503';
  end if;

  delete from public.branch_inventory
  where branch_id = p_branch_id;

  delete from public.branches
  where id = p_branch_id;

  if to_regprocedure('public.log_activity(text,text,text,jsonb,uuid)') is not null then
    execute
      'select public.log_activity($1, $2, $3, $4, $5)'
    using
      'branch.hard_deleted',
      'branch',
      p_branch_id::text,
      jsonb_build_object('branch_code', v_branch.branch_code, 'name', v_branch.name),
      v_actor.id;
  end if;

  return public.branch_management_get();
end;
$$;

revoke all on function public.branch_hard_delete(uuid) from public;
grant execute on function public.branch_hard_delete(uuid) to authenticated;

notify pgrst, 'reload schema';
