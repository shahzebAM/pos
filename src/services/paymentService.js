import { requireSupabaseConfig } from '../lib/supabase'

const emptyPaymentData = {
  period: {
    from: null,
    to: null,
  },
  summary: {
    payment_count: 0,
    order_count: 0,
    split_order_count: 0,
    collected_amount: 0,
    tendered_amount: 0,
    change_amount: 0,
    processor_fee_amount: 0,
    net_amount: 0,
    pending_settlement_count: 0,
    reference_missing_count: 0,
  },
  branches: [],
  payment_methods: [],
  branch_payment_methods: [],
  payments_by_branch: [],
  daily_payments: [],
  recent_payments: [],
  generated_at: null,
}

function moduleInstallMessage(error) {
  const message = error?.message || ''

  if (
    message.includes('payment_management_get') ||
    message.includes('payment_methods') ||
    message.includes('branch_payment_methods') ||
    message.includes('schema cache') ||
    message.includes('Could not find the function')
  ) {
    return 'Payments module is not installed yet. Run supabase/11-payments.sql after Module 10.'
  }

  return message || 'Unable to load payment data.'
}

function numberValue(value) {
  return Number(value || 0)
}

function arrayValue(value) {
  return Array.isArray(value) ? value : []
}

function normalizePaymentData(payload) {
  const data = payload || emptyPaymentData

  return {
    ...emptyPaymentData,
    ...data,
    period: {
      from: data.period?.from || null,
      to: data.period?.to || null,
    },
    summary: {
      payment_count: numberValue(data.summary?.payment_count),
      order_count: numberValue(data.summary?.order_count),
      split_order_count: numberValue(data.summary?.split_order_count),
      collected_amount: numberValue(data.summary?.collected_amount),
      tendered_amount: numberValue(data.summary?.tendered_amount),
      change_amount: numberValue(data.summary?.change_amount),
      processor_fee_amount: numberValue(data.summary?.processor_fee_amount),
      net_amount: numberValue(data.summary?.net_amount),
      pending_settlement_count: numberValue(data.summary?.pending_settlement_count),
      reference_missing_count: numberValue(data.summary?.reference_missing_count),
    },
    branches: arrayValue(data.branches),
    payment_methods: arrayValue(data.payment_methods).map((method) => ({
      ...method,
      settlement_days: numberValue(method.settlement_days),
      fee_rate: numberValue(method.fee_rate),
      sort_order: numberValue(method.sort_order),
      payment_count: numberValue(method.payment_count),
      collected_amount: numberValue(method.collected_amount),
      tendered_amount: numberValue(method.tendered_amount),
      change_amount: numberValue(method.change_amount),
      processor_fee_amount: numberValue(method.processor_fee_amount),
      net_amount: numberValue(method.net_amount),
    })),
    branch_payment_methods: arrayValue(data.branch_payment_methods).map((row) => ({
      ...row,
      settlement_days: numberValue(row.settlement_days),
      effective_fee_rate: numberValue(row.effective_fee_rate),
      fee_rate_override: row.fee_rate_override === null || row.fee_rate_override === undefined ? null : numberValue(row.fee_rate_override),
      payment_count: numberValue(row.payment_count),
      collected_amount: numberValue(row.collected_amount),
    })),
    payments_by_branch: arrayValue(data.payments_by_branch).map((row) => ({
      ...row,
      payment_count: numberValue(row.payment_count),
      order_count: numberValue(row.order_count),
      collected_amount: numberValue(row.collected_amount),
      tendered_amount: numberValue(row.tendered_amount),
      change_amount: numberValue(row.change_amount),
      processor_fee_amount: numberValue(row.processor_fee_amount),
      net_amount: numberValue(row.net_amount),
    })),
    daily_payments: arrayValue(data.daily_payments).map((row) => ({
      ...row,
      payment_count: numberValue(row.payment_count),
      collected_amount: numberValue(row.collected_amount),
      processor_fee_amount: numberValue(row.processor_fee_amount),
      net_amount: numberValue(row.net_amount),
    })),
    recent_payments: arrayValue(data.recent_payments).map((payment) => ({
      ...payment,
      amount: numberValue(payment.amount),
      tendered_amount: numberValue(payment.tendered_amount),
      change_amount: numberValue(payment.change_amount),
      processor_fee_amount: numberValue(payment.processor_fee_amount),
      net_amount: numberValue(payment.net_amount),
      order_total: numberValue(payment.order_total),
    })),
  }
}

async function callPaymentRpc(name, args = {}) {
  const client = requireSupabaseConfig()
  const { data, error } = await client.rpc(name, args)

  if (error) {
    throw new Error(moduleInstallMessage(error))
  }

  return normalizePaymentData(data)
}

export function fetchPaymentManagement({ from = null, to = null, branchId = null } = {}) {
  return callPaymentRpc('payment_management_get', {
    p_from: from,
    p_to: to,
    p_branch_id: branchId || null,
  })
}

export function savePaymentMethod(methodId, payload) {
  return callPaymentRpc('payment_method_save', {
    p_method_id: methodId || null,
    p_payload: payload,
  })
}

export function saveBranchPaymentMethod(branchId, paymentMethodId, payload) {
  return callPaymentRpc('branch_payment_method_save', {
    p_branch_id: branchId,
    p_payment_method_id: paymentMethodId,
    p_payload: payload,
  })
}

export function updatePaymentSettlement(paymentId, status, settledAt = null, notes = '') {
  return callPaymentRpc('payment_settlement_update', {
    p_payment_id: paymentId,
    p_status: status,
    p_settled_at: settledAt,
    p_notes: notes,
  })
}
