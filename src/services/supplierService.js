import { requireSupabaseConfig } from '../lib/supabase'

const emptySupplierData = {
  period: {
    from: null,
    to: null,
  },
  summary: {
    supplier_count: 0,
    active_suppliers: 0,
    on_hold_suppliers: 0,
    payable_amount: 0,
    overdue_amount: 0,
    overdue_invoices: 0,
    purchase_value: 0,
    paid_amount: 0,
    payment_count: 0,
    open_purchase_orders: 0,
  },
  branches: [],
  suppliers: [],
  supplier_invoices: [],
  supplier_payments: [],
  purchase_history: [],
  purchase_orders: [],
  daily_payments: [],
  branch_summary: [],
  top_suppliers: [],
  can_manage_suppliers: false,
  can_pay_suppliers: false,
  generated_at: null,
}

function moduleInstallMessage(error) {
  const message = error?.message || ''

  if (
    message.includes('supplier_management_get') ||
    message.includes('supplier_payments') ||
    message.includes('supplier_profile_save') ||
    message.includes('supplier_payment_post') ||
    message.includes('schema cache') ||
    message.includes('Could not find the function')
  ) {
    return 'Supplier Management module is not installed yet. Run supabase/15-supplier-management.sql after Module 14.'
  }

  return message || 'Unable to load supplier management data.'
}

function numberValue(value) {
  return Number(value || 0)
}

function arrayValue(value) {
  return Array.isArray(value) ? value : []
}

function normalizeSupplier(supplier) {
  return {
    ...supplier,
    payment_terms_days: numberValue(supplier.payment_terms_days),
    credit_limit: numberValue(supplier.credit_limit),
    withholding_tax_rate: numberValue(supplier.withholding_tax_rate),
    lead_time_days: numberValue(supplier.lead_time_days),
    rating: numberValue(supplier.rating),
    open_orders: numberValue(supplier.open_orders),
    purchase_orders: numberValue(supplier.purchase_orders),
    receipt_count: numberValue(supplier.receipt_count),
    received_value: numberValue(supplier.received_value),
    invoice_count: numberValue(supplier.invoice_count),
    pending_invoice_count: numberValue(supplier.pending_invoice_count),
    overdue_invoice_count: numberValue(supplier.overdue_invoice_count),
    payable_amount: numberValue(supplier.payable_amount),
    overdue_amount: numberValue(supplier.overdue_amount),
    paid_amount: numberValue(supplier.paid_amount),
  }
}

function normalizeInvoice(invoice) {
  return {
    ...invoice,
    amount: numberValue(invoice.amount),
    tax_amount: numberValue(invoice.tax_amount),
    paid_amount: numberValue(invoice.paid_amount),
    balance_amount: numberValue(invoice.balance_amount ?? Number(invoice.amount || 0) - Number(invoice.paid_amount || 0)),
    days_overdue: numberValue(invoice.days_overdue),
  }
}

function normalizeSupplierData(payload) {
  const data = payload || emptySupplierData

  return {
    ...emptySupplierData,
    ...data,
    period: {
      from: data.period?.from || null,
      to: data.period?.to || null,
    },
    summary: {
      supplier_count: numberValue(data.summary?.supplier_count),
      active_suppliers: numberValue(data.summary?.active_suppliers),
      on_hold_suppliers: numberValue(data.summary?.on_hold_suppliers),
      payable_amount: numberValue(data.summary?.payable_amount),
      overdue_amount: numberValue(data.summary?.overdue_amount),
      overdue_invoices: numberValue(data.summary?.overdue_invoices),
      purchase_value: numberValue(data.summary?.purchase_value),
      paid_amount: numberValue(data.summary?.paid_amount),
      payment_count: numberValue(data.summary?.payment_count),
      open_purchase_orders: numberValue(data.summary?.open_purchase_orders),
    },
    branches: arrayValue(data.branches),
    suppliers: arrayValue(data.suppliers).map(normalizeSupplier),
    supplier_invoices: arrayValue(data.supplier_invoices).map(normalizeInvoice),
    supplier_payments: arrayValue(data.supplier_payments).map((payment) => ({
      ...payment,
      amount: numberValue(payment.amount),
    })),
    purchase_history: arrayValue(data.purchase_history).map((row) => ({
      ...row,
      total_cost: numberValue(row.total_cost),
      tax_total: numberValue(row.tax_total),
      item_count: numberValue(row.item_count),
      received_quantity: numberValue(row.received_quantity),
    })),
    purchase_orders: arrayValue(data.purchase_orders).map((row) => ({
      ...row,
      subtotal: numberValue(row.subtotal),
      tax_total: numberValue(row.tax_total),
      total: numberValue(row.total),
      item_count: numberValue(row.item_count),
      ordered_quantity: numberValue(row.ordered_quantity),
      received_quantity: numberValue(row.received_quantity),
    })),
    daily_payments: arrayValue(data.daily_payments).map((row) => ({
      ...row,
      payments: numberValue(row.payments),
      paid_amount: numberValue(row.paid_amount),
    })),
    branch_summary: arrayValue(data.branch_summary).map((row) => ({
      ...row,
      payable_amount: numberValue(row.payable_amount),
      overdue_amount: numberValue(row.overdue_amount),
      paid_amount: numberValue(row.paid_amount),
      received_value: numberValue(row.received_value),
    })),
    top_suppliers: arrayValue(data.top_suppliers).map(normalizeSupplier),
    can_manage_suppliers: Boolean(data.can_manage_suppliers),
    can_pay_suppliers: Boolean(data.can_pay_suppliers),
  }
}

async function callSupplierRpc(name, args = {}) {
  const client = requireSupabaseConfig()
  const { data, error } = await client.rpc(name, args)

  if (error) {
    throw new Error(moduleInstallMessage(error))
  }

  return normalizeSupplierData(data)
}

export function fetchSupplierManagement({ from = null, to = null, branchId = null, supplierId = null, search = '' } = {}) {
  return callSupplierRpc('supplier_management_get', {
    p_from: from,
    p_to: to,
    p_branch_id: branchId || null,
    p_supplier_id: supplierId || null,
    p_search: search || null,
  })
}

export function saveSupplierProfile(supplierId, payload) {
  return callSupplierRpc('supplier_profile_save', {
    p_supplier_id: supplierId || null,
    p_payload: payload,
  })
}

export function postSupplierPayment(payload) {
  return callSupplierRpc('supplier_payment_post', {
    p_payload: payload,
  })
}

export function voidSupplierPayment(paymentId, reason) {
  return callSupplierRpc('supplier_payment_void', {
    p_payment_id: paymentId,
    p_reason: reason,
  })
}
