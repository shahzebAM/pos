import { requireSupabaseConfig } from '../lib/supabase'

const offlineQueueKey = 'module7_pos_offline_queue_v1'

const emptyPosData = {
  branch: null,
  branches: [],
  customers: [],
  products: [],
  recent_orders: [],
  payment_methods: [],
  payment_methods_installed: false,
  shift_installed: false,
  current_shift: null,
  registers: [],
  can_open_shift: false,
  senior_pwd_settings: {
    standard_discount_rate: 20,
    basic_necessity_rate: 5,
    require_id_capture: true,
    require_booklet_for_basic: true,
    is_active: true,
  },
  senior_pwd_installed: false,
  senior_pwd_discount_options: [
    { label: 'No Senior/PWD discount', value: 'none' },
    { label: 'Senior Citizen', value: 'senior' },
    { label: 'PWD', value: 'pwd' },
  ],
  summary: {
    today_orders: 0,
    today_sales: 0,
    today_tax: 0,
    today_discounts: 0,
    today_senior_pwd_discounts: 0,
    items_available: 0,
  },
  generated_at: null,
}

function moduleInstallMessage(error) {
  const message = error?.message || ''

  if (
    message.includes('pos_management_get') ||
    message.includes('pos_checkout') ||
    message.includes('sales_order_items') ||
    message.includes('schema cache') ||
    message.includes('Could not find the function')
  ) {
    return 'POS Sales / Checkout module is not installed yet. Run supabase/07-pos-sales-checkout.sql after Module 6.'
  }

  return message || 'Unable to load POS checkout data.'
}

function numberValue(value) {
  return Number(value || 0)
}

function arrayValue(value) {
  return Array.isArray(value) ? value : []
}

function shiftModuleMissing(error) {
  const message = error?.message || ''

  return (
    message.includes('shift_pos_status_get') ||
    message.includes('cashier_shifts') ||
    message.includes('cash_registers') ||
    message.includes('schema cache') ||
    message.includes('Could not find the function')
  )
}

function customerModuleMissing(error) {
  const message = error?.message || ''

  return (
    message.includes('customer_pos_options_get') ||
    message.includes('customers') ||
    message.includes('schema cache') ||
    message.includes('Could not find the function')
  )
}

function normalizeShiftStatus(payload) {
  const data = payload || {}
  const shift = data.current_shift

  return {
    shift_installed: Boolean(data.shift_installed),
    can_open_shift: Boolean(data.can_open_shift),
    registers: arrayValue(data.registers),
    current_shift: shift
      ? {
          ...shift,
          opening_cash: numberValue(shift.opening_cash),
          cash_sales: numberValue(shift.cash_sales),
          cash_in_total: numberValue(shift.cash_in_total),
          cash_out_total: numberValue(shift.cash_out_total),
          expected_cash: numberValue(shift.expected_cash),
        }
      : null,
  }
}

function normalizeOrder(order) {
  if (!order) return null

  return {
    ...order,
    subtotal: numberValue(order.subtotal),
    discount_total: numberValue(order.discount_total),
    statutory_discount_amount: numberValue(order.statutory_discount_amount),
    statutory_vat_exempt_amount: numberValue(order.statutory_vat_exempt_amount),
    statutory_special_discount_amount: numberValue(order.statutory_special_discount_amount),
    tax_total: numberValue(order.tax_total),
    total: numberValue(order.total),
    amount_tendered: numberValue(order.amount_tendered),
    change_due: numberValue(order.change_due),
    items: arrayValue(order.items).map((item) => ({
      ...item,
      quantity: numberValue(item.quantity),
      unit_price: numberValue(item.unit_price),
      gross_amount: numberValue(item.gross_amount),
      discount_amount: numberValue(item.discount_amount),
      statutory_discount_amount: numberValue(item.statutory_discount_amount),
      statutory_vat_exempt_amount: numberValue(item.statutory_vat_exempt_amount),
      statutory_special_discount_amount: numberValue(item.statutory_special_discount_amount),
      tax_rate: numberValue(item.tax_rate),
      tax_amount: numberValue(item.tax_amount),
      net_amount: numberValue(item.net_amount),
    })),
    payments: arrayValue(order.payments).map((payment) => ({
      ...payment,
      amount: numberValue(payment.amount),
      tendered_amount: numberValue(payment.tendered_amount || payment.amount),
      change_amount: numberValue(payment.change_amount),
      processor_fee_amount: numberValue(payment.processor_fee_amount),
      net_amount: numberValue(payment.net_amount || payment.amount),
    })),
  }
}

function normalizePosData(payload) {
  const data = payload || emptyPosData

  return {
    ...emptyPosData,
    ...data,
    branch: data.branch || null,
    branches: arrayValue(data.branches),
    customers: arrayValue(data.customers).map((customer) => ({
      ...customer,
      receivable_balance: numberValue(customer.receivable_balance),
      store_credit_balance: numberValue(customer.store_credit_balance),
      loyalty_points: numberValue(customer.loyalty_points),
    })),
    products: arrayValue(data.products).map((product) => ({
      ...product,
      selling_price: numberValue(product.selling_price),
      cost_price: numberValue(product.cost_price),
      vat_rate: numberValue(product.vat_rate),
      quantity_on_hand: numberValue(product.quantity_on_hand),
      senior_pwd_discount_category: product.senior_pwd_discount_category || 'regular_20',
      variants: arrayValue(product.variants).map((variant) => ({
        ...variant,
        selling_price: numberValue(variant.selling_price),
        cost_price: numberValue(variant.cost_price),
        quantity_on_hand: numberValue(variant.quantity_on_hand),
      })),
    })),
    recent_orders: arrayValue(data.recent_orders).map(normalizeOrder),
    payment_methods: arrayValue(data.payment_methods).map((method) => ({
      ...method,
      requires_reference: Boolean(method.requires_reference),
      allow_overpayment: Boolean(method.allow_overpayment),
      allow_change: Boolean(method.allow_change),
      fee_rate: numberValue(method.fee_rate),
      settlement_days: numberValue(method.settlement_days),
    })),
    payment_methods_installed: Boolean(data.payment_methods_installed),
    shift_installed: Boolean(data.shift_installed),
    can_open_shift: Boolean(data.can_open_shift),
    registers: arrayValue(data.registers),
    current_shift: data.current_shift
      ? {
          ...data.current_shift,
          opening_cash: numberValue(data.current_shift.opening_cash),
          cash_sales: numberValue(data.current_shift.cash_sales),
          cash_in_total: numberValue(data.current_shift.cash_in_total),
          cash_out_total: numberValue(data.current_shift.cash_out_total),
          expected_cash: numberValue(data.current_shift.expected_cash),
        }
      : null,
    senior_pwd_settings: {
      ...emptyPosData.senior_pwd_settings,
      ...(data.senior_pwd_settings || {}),
      standard_discount_rate: numberValue(data.senior_pwd_settings?.standard_discount_rate || 20),
      basic_necessity_rate: numberValue(data.senior_pwd_settings?.basic_necessity_rate || 5),
      require_id_capture: data.senior_pwd_settings?.require_id_capture ?? true,
      require_booklet_for_basic: data.senior_pwd_settings?.require_booklet_for_basic ?? true,
      is_active: data.senior_pwd_settings?.is_active ?? true,
    },
    senior_pwd_installed: Boolean(data.senior_pwd_settings),
    senior_pwd_discount_options: arrayValue(data.senior_pwd_discount_options).length
      ? arrayValue(data.senior_pwd_discount_options)
      : emptyPosData.senior_pwd_discount_options,
    summary: {
      today_orders: numberValue(data.summary?.today_orders),
      today_sales: numberValue(data.summary?.today_sales),
      today_tax: numberValue(data.summary?.today_tax),
      today_discounts: numberValue(data.summary?.today_discounts),
      today_senior_pwd_discounts: numberValue(data.summary?.today_senior_pwd_discounts),
      items_available: numberValue(data.summary?.items_available),
    },
  }
}

function normalizeCheckoutResult(payload) {
  return {
    pos: normalizePosData(payload?.pos),
    order: normalizeOrder(payload?.order),
  }
}

async function callPosRpc(name, args = {}) {
  const client = requireSupabaseConfig()
  const { data, error } = await client.rpc(name, args)

  if (error) {
    throw new Error(moduleInstallMessage(error))
  }

  return data
}

async function fetchShiftStatusForPos(branchId = null) {
  const client = requireSupabaseConfig()
  const { data, error } = await client.rpc('shift_pos_status_get', {
    p_branch_id: branchId || null,
  })

  if (error) {
    if (shiftModuleMissing(error)) return normalizeShiftStatus(null)
    throw new Error(error.message || 'Unable to load shift status.')
  }

  return normalizeShiftStatus(data)
}

async function fetchCustomersForPos(branchId = null) {
  const client = requireSupabaseConfig()
  const { data, error } = await client.rpc('customer_pos_options_get', {
    p_branch_id: branchId || null,
    p_search: null,
  })

  if (error) {
    if (customerModuleMissing(error)) return []
    throw new Error(error.message || 'Unable to load POS customer options.')
  }

  return arrayValue(data).map((customer) => ({
    ...customer,
    receivable_balance: numberValue(customer.receivable_balance),
    store_credit_balance: numberValue(customer.store_credit_balance),
    loyalty_points: numberValue(customer.loyalty_points),
  }))
}

export async function fetchPosManagement(branchId = null) {
  const data = await callPosRpc('pos_management_get', {
    p_branch_id: branchId || null,
  })

  const posData = normalizePosData(data)
  const shiftStatus = await fetchShiftStatusForPos(posData.branch?.id || branchId)
  const customers = await fetchCustomersForPos(posData.branch?.id || branchId)

  return normalizePosData({
    ...posData,
    ...shiftStatus,
    customers,
  })
}

export async function checkoutSale(payload) {
  const data = await callPosRpc('pos_checkout', {
    p_payload: payload,
  })

  const result = normalizeCheckoutResult(data)
  const shiftStatus = await fetchShiftStatusForPos(result.pos.branch?.id || payload.branch_id)
  const customers = await fetchCustomersForPos(result.pos.branch?.id || payload.branch_id)

  return {
    ...result,
    pos: normalizePosData({
      ...result.pos,
      ...shiftStatus,
      customers,
    }),
  }
}

function storageAvailable() {
  return typeof window !== 'undefined' && Boolean(window.localStorage)
}

export function getOfflineSalesQueue() {
  if (!storageAvailable()) return []

  try {
    return JSON.parse(window.localStorage.getItem(offlineQueueKey) || '[]')
  } catch (_error) {
    return []
  }
}

export function saveOfflineSalesQueue(queue) {
  if (!storageAvailable()) return
  window.localStorage.setItem(offlineQueueKey, JSON.stringify(arrayValue(queue)))
}

export function enqueueOfflineSale(payload, totals) {
  const queue = getOfflineSalesQueue()
  const offlineReference = payload.offline_reference || `offline-${Date.now()}-${Math.random().toString(16).slice(2)}`
  const queuedSale = {
    id: offlineReference,
    created_at: new Date().toISOString(),
    payload: {
      ...payload,
      source: 'offline',
      offline_reference: offlineReference,
    },
    totals,
  }

  queue.push(queuedSale)
  saveOfflineSalesQueue(queue)

  return queuedSale
}

export function removeOfflineSale(offlineReference) {
  const queue = getOfflineSalesQueue().filter((sale) => sale.id !== offlineReference)
  saveOfflineSalesQueue(queue)
  return queue
}

export async function syncOfflineSales() {
  const queue = getOfflineSalesQueue()
  const synced = []
  const failed = []

  for (const sale of queue) {
    try {
      const result = await checkoutSale(sale.payload)
      synced.push({ sale, result })
    } catch (error) {
      failed.push({ sale, error: error.message })
    }
  }

  saveOfflineSalesQueue(failed.map((entry) => entry.sale))

  return { synced, failed }
}
