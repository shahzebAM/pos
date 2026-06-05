import { requireSupabaseConfig } from '../lib/supabase'

const emptyExpenseData = {
  period: {
    from: null,
    to: null,
  },
  summary: {
    total_expenses: 0,
    paid_expenses: 0,
    pending_approval: 0,
    draft_expenses: 0,
    rejected_expenses: 0,
    expense_count: 0,
    category_count: 0,
  },
  branches: [],
  categories: [],
  expenses: [],
  daily_expenses: [],
  category_summary: [],
  branch_summary: [],
  can_manage_expenses: false,
  can_approve_expenses: false,
  generated_at: null,
}

function moduleInstallMessage(error) {
  const message = error?.message || ''

  if (
    message.includes('expense_management_get') ||
    message.includes('expense_category_save') ||
    message.includes('expense_save') ||
    message.includes('expense_status_update') ||
    message.includes('expense_categories') ||
    message.includes('public.expenses') ||
    message.includes('schema cache') ||
    message.includes('Could not find the function')
  ) {
    return 'Expenses module is not installed yet. Run supabase/17-expenses.sql after Module 16.'
  }

  return message || 'Unable to load expenses data.'
}

function numberValue(value) {
  return Number(value || 0)
}

function arrayValue(value) {
  return Array.isArray(value) ? value : []
}

function normalizeExpense(expense) {
  return {
    ...expense,
    amount: numberValue(expense.amount),
    tax_amount: numberValue(expense.tax_amount),
    total_amount: numberValue(expense.total_amount),
  }
}

function normalizeCategory(category) {
  return {
    ...category,
    sort_order: numberValue(category.sort_order),
    expense_count: numberValue(category.expense_count),
    total_amount: numberValue(category.total_amount),
  }
}

function normalizeExpenseData(payload) {
  const data = payload || emptyExpenseData

  return {
    ...emptyExpenseData,
    ...data,
    period: {
      from: data.period?.from || null,
      to: data.period?.to || null,
    },
    summary: {
      total_expenses: numberValue(data.summary?.total_expenses),
      paid_expenses: numberValue(data.summary?.paid_expenses),
      pending_approval: numberValue(data.summary?.pending_approval),
      draft_expenses: numberValue(data.summary?.draft_expenses),
      rejected_expenses: numberValue(data.summary?.rejected_expenses),
      expense_count: numberValue(data.summary?.expense_count),
      category_count: numberValue(data.summary?.category_count),
    },
    branches: arrayValue(data.branches),
    categories: arrayValue(data.categories).map(normalizeCategory),
    expenses: arrayValue(data.expenses).map(normalizeExpense),
    daily_expenses: arrayValue(data.daily_expenses).map((row) => ({
      ...row,
      expenses: numberValue(row.expenses),
      total_amount: numberValue(row.total_amount),
    })),
    category_summary: arrayValue(data.category_summary).map((row) => ({
      ...row,
      expenses: numberValue(row.expenses),
      total_amount: numberValue(row.total_amount),
    })),
    branch_summary: arrayValue(data.branch_summary).map((row) => ({
      ...row,
      expense_count: numberValue(row.expense_count),
      pending_count: numberValue(row.pending_count),
      approved_amount: numberValue(row.approved_amount),
      paid_amount: numberValue(row.paid_amount),
    })),
    can_manage_expenses: Boolean(data.can_manage_expenses),
    can_approve_expenses: Boolean(data.can_approve_expenses),
  }
}

async function callExpenseRpc(name, args = {}) {
  const client = requireSupabaseConfig()
  const { data, error } = await client.rpc(name, args)

  if (error) {
    throw new Error(moduleInstallMessage(error))
  }

  return normalizeExpenseData(data)
}

export function fetchExpenseManagement({ from = null, to = null, branchId = null, search = '' } = {}) {
  return callExpenseRpc('expense_management_get', {
    p_from: from,
    p_to: to,
    p_branch_id: branchId || null,
    p_search: search || null,
  })
}

export function saveExpenseCategory(categoryId, payload) {
  return callExpenseRpc('expense_category_save', {
    p_category_id: categoryId || null,
    p_payload: payload,
  })
}

export function saveExpense(expenseId, payload) {
  return callExpenseRpc('expense_save', {
    p_expense_id: expenseId || null,
    p_payload: payload,
  })
}

export function updateExpenseStatus(expenseId, status, reason = null) {
  return callExpenseRpc('expense_status_update', {
    p_expense_id: expenseId,
    p_status: status,
    p_reason: reason || null,
  })
}
