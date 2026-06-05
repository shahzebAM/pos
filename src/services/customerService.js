import { requireSupabaseConfig } from '../lib/supabase'

const emptyCustomerData = {
  period: {
    from: null,
    to: null,
  },
  summary: {
    customer_count: 0,
    active_customers: 0,
    sales_value: 0,
    order_count: 0,
    receivable_balance: 0,
    store_credit_balance: 0,
    loyalty_points: 0,
    credit_sales: 0,
    payments_collected: 0,
  },
  branches: [],
  customers: [],
  orders: [],
  account_entries: [],
  loyalty_ledger: [],
  daily_sales: [],
  branch_summary: [],
  top_customers: [],
  loyalty_settings: [],
  can_manage_customers: false,
  can_credit_customers: false,
  generated_at: null,
}

function moduleInstallMessage(error) {
  const message = error?.message || ''

  if (
    message.includes('customer_management_get') ||
    message.includes('customers') ||
    message.includes('customer_account_entries') ||
    message.includes('customer_loyalty_ledger') ||
    message.includes('schema cache') ||
    message.includes('Could not find the function')
  ) {
    return 'Customer Management module is not installed yet. Run supabase/16-customer-management.sql after Module 15.'
  }

  return message || 'Unable to load customer management data.'
}

function numberValue(value) {
  return Number(value || 0)
}

function arrayValue(value) {
  return Array.isArray(value) ? value : []
}

function normalizeCustomer(customer) {
  return {
    ...customer,
    credit_limit: numberValue(customer.credit_limit),
    receivable_balance: numberValue(customer.receivable_balance),
    store_credit_balance: numberValue(customer.store_credit_balance),
    loyalty_points: numberValue(customer.loyalty_points),
    total_orders: numberValue(customer.total_orders),
    total_spent: numberValue(customer.total_spent),
    period_orders: numberValue(customer.period_orders),
    period_sales: numberValue(customer.period_sales),
  }
}

function normalizeOrder(order) {
  return {
    ...order,
    subtotal: numberValue(order.subtotal),
    discount_total: numberValue(order.discount_total),
    tax_total: numberValue(order.tax_total),
    total: numberValue(order.total),
    amount_tendered: numberValue(order.amount_tendered),
    change_due: numberValue(order.change_due),
    payments: arrayValue(order.payments).map((payment) => ({
      ...payment,
      amount: numberValue(payment.amount),
      tendered_amount: numberValue(payment.tendered_amount || payment.amount),
      change_amount: numberValue(payment.change_amount),
      net_amount: numberValue(payment.net_amount || payment.amount),
    })),
  }
}

function normalizeCustomerData(payload) {
  const data = payload || emptyCustomerData

  return {
    ...emptyCustomerData,
    ...data,
    period: {
      from: data.period?.from || null,
      to: data.period?.to || null,
    },
    summary: {
      customer_count: numberValue(data.summary?.customer_count),
      active_customers: numberValue(data.summary?.active_customers),
      sales_value: numberValue(data.summary?.sales_value),
      order_count: numberValue(data.summary?.order_count),
      receivable_balance: numberValue(data.summary?.receivable_balance),
      store_credit_balance: numberValue(data.summary?.store_credit_balance),
      loyalty_points: numberValue(data.summary?.loyalty_points),
      credit_sales: numberValue(data.summary?.credit_sales),
      payments_collected: numberValue(data.summary?.payments_collected),
    },
    branches: arrayValue(data.branches),
    customers: arrayValue(data.customers).map(normalizeCustomer),
    orders: arrayValue(data.orders).map(normalizeOrder),
    account_entries: arrayValue(data.account_entries).map((entry) => ({
      ...entry,
      receivable_delta: numberValue(entry.receivable_delta),
      store_credit_delta: numberValue(entry.store_credit_delta),
    })),
    loyalty_ledger: arrayValue(data.loyalty_ledger).map((entry) => ({
      ...entry,
      points_delta: numberValue(entry.points_delta),
    })),
    daily_sales: arrayValue(data.daily_sales).map((row) => ({
      ...row,
      orders: numberValue(row.orders),
      sales: numberValue(row.sales),
    })),
    branch_summary: arrayValue(data.branch_summary).map((row) => ({
      ...row,
      orders: numberValue(row.orders),
      sales: numberValue(row.sales),
      receivable_balance: numberValue(row.receivable_balance),
      store_credit_balance: numberValue(row.store_credit_balance),
    })),
    top_customers: arrayValue(data.top_customers).map(normalizeCustomer),
    loyalty_settings: arrayValue(data.loyalty_settings).map((row) => ({
      ...row,
      peso_per_point: numberValue(row.peso_per_point),
      point_value: numberValue(row.point_value),
      is_active: Boolean(row.is_active),
    })),
    can_manage_customers: Boolean(data.can_manage_customers),
    can_credit_customers: Boolean(data.can_credit_customers),
  }
}

async function callCustomerRpc(name, args = {}) {
  const client = requireSupabaseConfig()
  const { data, error } = await client.rpc(name, args)

  if (error) {
    throw new Error(moduleInstallMessage(error))
  }

  return normalizeCustomerData(data)
}

export function fetchCustomerManagement({ from = null, to = null, branchId = null, customerId = null, search = '' } = {}) {
  return callCustomerRpc('customer_management_get', {
    p_from: from,
    p_to: to,
    p_branch_id: branchId || null,
    p_customer_id: customerId || null,
    p_search: search || null,
  })
}

export function saveCustomerProfile(customerId, payload) {
  return callCustomerRpc('customer_profile_save', {
    p_customer_id: customerId || null,
    p_payload: payload,
  })
}

export function postCustomerAccountEntry(payload) {
  return callCustomerRpc('customer_account_entry_post', {
    p_payload: payload,
  })
}

export function voidCustomerAccountEntry(entryId, reason) {
  return callCustomerRpc('customer_account_entry_void', {
    p_entry_id: entryId,
    p_reason: reason,
  })
}

export function adjustCustomerLoyalty(payload) {
  return callCustomerRpc('customer_loyalty_adjust', {
    p_payload: payload,
  })
}
