import { requireSupabaseConfig } from '../lib/supabase'

const emptyBranchData = {
  summary: {
    total_branches: 0,
    active_branches: 0,
    head_offices: 0,
    users_assigned: 0,
    stock_units: 0,
  },
  branches: [],
  generated_at: null,
}

function moduleInstallMessage(error) {
  const message = error?.message || ''

  if (
    message.includes('branch_management_get') ||
    message.includes('branch_hard_delete') ||
    message.includes('schema cache') ||
    message.includes('Could not find the function')
  ) {
    return 'Branch Management module is not installed yet. Run supabase/02-auth-and-branch-management.sql after Module 1.'
  }

  return message || 'Unable to load branch management data.'
}

function numberValue(value) {
  return Number(value || 0)
}

function normalizeBranchData(payload) {
  const data = payload || emptyBranchData

  return {
    ...emptyBranchData,
    ...data,
    summary: {
      total_branches: numberValue(data.summary?.total_branches),
      active_branches: numberValue(data.summary?.active_branches),
      head_offices: numberValue(data.summary?.head_offices),
      users_assigned: numberValue(data.summary?.users_assigned),
      stock_units: numberValue(data.summary?.stock_units),
    },
    branches: (Array.isArray(data.branches) ? data.branches : []).map((branch) => ({
      ...branch,
      vat_rate: numberValue(branch.vat_rate),
      users_count: numberValue(branch.users_count),
      stock_items: numberValue(branch.stock_items),
      stock_units: numberValue(branch.stock_units),
      total_sales: numberValue(branch.total_sales),
    })),
  }
}

async function callBranchRpc(name, args = {}) {
  const client = requireSupabaseConfig()
  const { data, error } = await client.rpc(name, args)

  if (error) {
    throw new Error(moduleInstallMessage(error))
  }

  return normalizeBranchData(data)
}

export function fetchBranchManagement() {
  return callBranchRpc('branch_management_get')
}

export function createBranch(payload) {
  return callBranchRpc('branch_create', {
    p_payload: payload,
  })
}

export function updateBranch(branchId, payload) {
  return callBranchRpc('branch_update', {
    p_branch_id: branchId,
    p_payload: payload,
  })
}

export function setBranchActive(branchId, isActive) {
  return callBranchRpc('branch_set_active', {
    p_branch_id: branchId,
    p_is_active: isActive,
  })
}

export function hardDeleteBranch(branchId) {
  return callBranchRpc('branch_hard_delete', {
    p_branch_id: branchId,
  })
}
