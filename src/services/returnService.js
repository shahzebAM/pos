import { requireSupabaseConfig } from '../lib/supabase'

const emptyReturnData = {
  period: {
    from: null,
    to: null,
  },
  summary: {
    return_count: 0,
    void_count: 0,
    refund_count: 0,
    credit_memo_count: 0,
    total_return_amount: 0,
    refund_amount: 0,
    credit_memo_amount: 0,
    open_credit_memo_amount: 0,
    returned_quantity: 0,
  },
  branches: [],
  reasons: [],
  eligible_orders: [],
  returns: [],
  credit_memos: [],
  daily_returns: [],
  branch_summary: [],
  can_manage_returns: false,
  can_void_returns: false,
  generated_at: null,
}

function moduleInstallMessage(error) {
  const message = error?.message || ''

  if (
    message.includes('returns_management_get') ||
    message.includes('sales_returns') ||
    message.includes('sales_return_items') ||
    message.includes('credit_memos') ||
    message.includes('schema cache') ||
    message.includes('Could not find the function')
  ) {
    return 'Returns & Exchanges module is not installed yet. Run supabase/13-returns-exchanges.sql after Module 12.'
  }

  return message || 'Unable to load returns and exchanges data.'
}

function numberValue(value) {
  return Number(value || 0)
}

function arrayValue(value) {
  return Array.isArray(value) ? value : []
}

function normalizeOrderItem(item) {
  return {
    ...item,
    quantity: numberValue(item.quantity),
    unit_price: numberValue(item.unit_price),
    gross_amount: numberValue(item.gross_amount),
    discount_amount: numberValue(item.discount_amount),
    tax_amount: numberValue(item.tax_amount),
    net_amount: numberValue(item.net_amount),
    returned_quantity: numberValue(item.returned_quantity),
    returnable_quantity: numberValue(item.returnable_quantity),
    requested_quantity: 0,
    condition: 'good',
    disposition: 'return_to_stock',
  }
}

function normalizeEligibleOrder(order) {
  return {
    ...order,
    total: numberValue(order.total),
    return_total: numberValue(order.return_total),
    returnable_quantity: numberValue(order.returnable_quantity),
    items: arrayValue(order.items).map(normalizeOrderItem),
    payments: arrayValue(order.payments).map((payment) => ({
      ...payment,
      amount: numberValue(payment.amount),
    })),
  }
}

function normalizeReturnRow(row) {
  return {
    ...row,
    total_return_amount: numberValue(row.total_return_amount),
    refund_amount: numberValue(row.refund_amount),
    credit_memo_amount: numberValue(row.credit_memo_amount),
    items: arrayValue(row.items).map((item) => ({
      ...item,
      quantity: numberValue(item.quantity),
      unit_price: numberValue(item.unit_price),
      gross_amount: numberValue(item.gross_amount),
      discount_amount: numberValue(item.discount_amount),
      tax_amount: numberValue(item.tax_amount),
      net_amount: numberValue(item.net_amount),
    })),
    refunds: arrayValue(row.refunds).map((refund) => ({
      ...refund,
      amount: numberValue(refund.amount),
    })),
  }
}

function normalizeReturnData(payload) {
  const data = payload || emptyReturnData

  return {
    ...emptyReturnData,
    ...data,
    period: {
      from: data.period?.from || null,
      to: data.period?.to || null,
    },
    summary: {
      return_count: numberValue(data.summary?.return_count),
      void_count: numberValue(data.summary?.void_count),
      refund_count: numberValue(data.summary?.refund_count),
      credit_memo_count: numberValue(data.summary?.credit_memo_count),
      total_return_amount: numberValue(data.summary?.total_return_amount),
      refund_amount: numberValue(data.summary?.refund_amount),
      credit_memo_amount: numberValue(data.summary?.credit_memo_amount),
      open_credit_memo_amount: numberValue(data.summary?.open_credit_memo_amount),
      returned_quantity: numberValue(data.summary?.returned_quantity),
    },
    branches: arrayValue(data.branches),
    reasons: arrayValue(data.reasons),
    eligible_orders: arrayValue(data.eligible_orders).map(normalizeEligibleOrder),
    returns: arrayValue(data.returns).map(normalizeReturnRow),
    credit_memos: arrayValue(data.credit_memos).map((memo) => ({
      ...memo,
      amount: numberValue(memo.amount),
      available_amount: numberValue(memo.available_amount),
    })),
    daily_returns: arrayValue(data.daily_returns).map((row) => ({
      ...row,
      returns: numberValue(row.returns),
      return_amount: numberValue(row.return_amount),
      refund_amount: numberValue(row.refund_amount),
      credit_memo_amount: numberValue(row.credit_memo_amount),
    })),
    branch_summary: arrayValue(data.branch_summary).map((row) => ({
      ...row,
      returns: numberValue(row.returns),
      return_amount: numberValue(row.return_amount),
      refund_amount: numberValue(row.refund_amount),
      credit_memo_amount: numberValue(row.credit_memo_amount),
      void_count: numberValue(row.void_count),
    })),
    can_manage_returns: Boolean(data.can_manage_returns),
    can_void_returns: Boolean(data.can_void_returns),
  }
}

async function callReturnRpc(name, args = {}) {
  const client = requireSupabaseConfig()
  const { data, error } = await client.rpc(name, args)

  if (error) {
    throw new Error(moduleInstallMessage(error))
  }

  return normalizeReturnData(data)
}

export function fetchReturnManagement({ from = null, to = null, branchId = null, search = '' } = {}) {
  return callReturnRpc('returns_management_get', {
    p_from: from,
    p_to: to,
    p_branch_id: branchId || null,
    p_search: search || null,
  })
}

export function processReturn(payload) {
  return callReturnRpc('returns_process', {
    p_payload: payload,
  })
}
