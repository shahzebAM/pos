import { requireSupabaseConfig } from '../lib/supabase'

const emptyPurchaseData = {
  period: {
    from: null,
    to: null,
  },
  summary: {
    open_orders: 0,
    approved_orders: 0,
    received_orders: 0,
    receipt_count: 0,
    received_value: 0,
    payable_amount: 0,
    overdue_invoices: 0,
    purchase_return_amount: 0,
    supplier_count: 0,
  },
  branches: [],
  suppliers: [],
  products: [],
  purchase_orders: [],
  receipts: [],
  supplier_invoices: [],
  purchase_returns: [],
  cost_history: [],
  daily_receipts: [],
  branch_summary: [],
  can_manage_purchases: false,
  can_approve_purchases: false,
  can_receive_purchases: false,
  generated_at: null,
}

function moduleInstallMessage(error) {
  const message = error?.message || ''

  if (
    message.includes('purchase_management_get') ||
    message.includes('purchase_orders') ||
    message.includes('purchase_receipts') ||
    message.includes('supplier_invoices') ||
    message.includes('schema cache') ||
    message.includes('Could not find the function')
  ) {
    return 'Purchase Management module is not installed yet. Run supabase/14-purchase-management.sql after Module 13.'
  }

  return message || 'Unable to load purchase management data.'
}

function numberValue(value) {
  return Number(value || 0)
}

function arrayValue(value) {
  return Array.isArray(value) ? value : []
}

function normalizeProduct(product) {
  return {
    ...product,
    cost_price: numberValue(product.cost_price),
    selling_price: numberValue(product.selling_price),
    variants: arrayValue(product.variants).map((variant) => ({
      ...variant,
      cost_price: numberValue(variant.cost_price),
      selling_price: numberValue(variant.selling_price),
    })),
  }
}

function normalizePurchaseItem(item) {
  return {
    ...item,
    quantity_ordered: numberValue(item.quantity_ordered),
    quantity_received: numberValue(item.quantity_received),
    unit_cost: numberValue(item.unit_cost),
    tax_rate: numberValue(item.tax_rate),
    tax_amount: numberValue(item.tax_amount),
    line_total: numberValue(item.line_total),
  }
}

function normalizeReceiptItem(item) {
  return {
    ...item,
    quantity_received: numberValue(item.quantity_received),
    quantity_returned: numberValue(item.quantity_returned),
    unit_cost: numberValue(item.unit_cost),
    tax_rate: numberValue(item.tax_rate),
    tax_amount: numberValue(item.tax_amount),
    line_total: numberValue(item.line_total),
  }
}

function normalizePurchaseData(payload) {
  const data = payload || emptyPurchaseData

  return {
    ...emptyPurchaseData,
    ...data,
    period: {
      from: data.period?.from || null,
      to: data.period?.to || null,
    },
    summary: {
      open_orders: numberValue(data.summary?.open_orders),
      approved_orders: numberValue(data.summary?.approved_orders),
      received_orders: numberValue(data.summary?.received_orders),
      receipt_count: numberValue(data.summary?.receipt_count),
      received_value: numberValue(data.summary?.received_value),
      payable_amount: numberValue(data.summary?.payable_amount),
      overdue_invoices: numberValue(data.summary?.overdue_invoices),
      purchase_return_amount: numberValue(data.summary?.purchase_return_amount),
      supplier_count: numberValue(data.summary?.supplier_count),
    },
    branches: arrayValue(data.branches),
    suppliers: arrayValue(data.suppliers).map((supplier) => ({
      ...supplier,
      payment_terms_days: numberValue(supplier.payment_terms_days),
      credit_limit: numberValue(supplier.credit_limit),
      open_orders: numberValue(supplier.open_orders),
      pending_amount: numberValue(supplier.pending_amount),
    })),
    products: arrayValue(data.products).map(normalizeProduct),
    purchase_orders: arrayValue(data.purchase_orders).map((order) => ({
      ...order,
      subtotal: numberValue(order.subtotal),
      tax_total: numberValue(order.tax_total),
      total: numberValue(order.total),
      item_count: numberValue(order.item_count),
      ordered_quantity: numberValue(order.ordered_quantity),
      received_quantity: numberValue(order.received_quantity),
      items: arrayValue(order.items).map(normalizePurchaseItem),
      receipts: arrayValue(order.receipts).map((receipt) => ({
        ...receipt,
        total_cost: numberValue(receipt.total_cost),
      })),
    })),
    receipts: arrayValue(data.receipts).map((receipt) => ({
      ...receipt,
      total_cost: numberValue(receipt.total_cost),
      tax_total: numberValue(receipt.tax_total),
      item_count: numberValue(receipt.item_count),
      received_quantity: numberValue(receipt.received_quantity),
      items: arrayValue(receipt.items).map(normalizeReceiptItem),
    })),
    supplier_invoices: arrayValue(data.supplier_invoices).map((invoice) => ({
      ...invoice,
      amount: numberValue(invoice.amount),
      tax_amount: numberValue(invoice.tax_amount),
      paid_amount: numberValue(invoice.paid_amount),
      balance_amount: Math.max(numberValue(invoice.amount) - numberValue(invoice.paid_amount), 0),
    })),
    purchase_returns: arrayValue(data.purchase_returns).map((row) => ({
      ...row,
      total_amount: numberValue(row.total_amount),
      item_count: numberValue(row.item_count),
      items: arrayValue(row.items).map((item) => ({
        ...item,
        quantity_returned: numberValue(item.quantity_returned),
        unit_cost: numberValue(item.unit_cost),
        line_total: numberValue(item.line_total),
      })),
    })),
    cost_history: arrayValue(data.cost_history).map((row) => ({
      ...row,
      quantity: numberValue(row.quantity),
      unit_cost: numberValue(row.unit_cost),
    })),
    daily_receipts: arrayValue(data.daily_receipts).map((row) => ({
      ...row,
      receipts: numberValue(row.receipts),
      received_value: numberValue(row.received_value),
    })),
    branch_summary: arrayValue(data.branch_summary).map((row) => ({
      ...row,
      open_orders: numberValue(row.open_orders),
      receipts: numberValue(row.receipts),
      received_value: numberValue(row.received_value),
      payable_amount: numberValue(row.payable_amount),
    })),
    can_manage_purchases: Boolean(data.can_manage_purchases),
    can_approve_purchases: Boolean(data.can_approve_purchases),
    can_receive_purchases: Boolean(data.can_receive_purchases),
  }
}

async function callPurchaseRpc(name, args = {}) {
  const client = requireSupabaseConfig()
  const { data, error } = await client.rpc(name, args)

  if (error) {
    throw new Error(moduleInstallMessage(error))
  }

  return normalizePurchaseData(data)
}

export function fetchPurchaseManagement({ from = null, to = null, branchId = null, search = '' } = {}) {
  return callPurchaseRpc('purchase_management_get', {
    p_from: from,
    p_to: to,
    p_branch_id: branchId || null,
    p_search: search || null,
  })
}

export function saveSupplier(supplierId, payload) {
  return callPurchaseRpc('purchase_supplier_save', {
    p_supplier_id: supplierId || null,
    p_payload: payload,
  })
}

export function savePurchaseOrder(orderId, payload) {
  return callPurchaseRpc('purchase_order_save', {
    p_order_id: orderId || null,
    p_payload: payload,
  })
}

export function updatePurchaseOrderStatus(orderId, status, reason = '') {
  return callPurchaseRpc('purchase_order_status_update', {
    p_order_id: orderId,
    p_status: status,
    p_reason: reason || null,
  })
}

export function receivePurchase(payload) {
  return callPurchaseRpc('purchase_receive', {
    p_payload: payload,
  })
}

export function updateSupplierInvoiceStatus(invoiceId, status, paidAmount = null, notes = '') {
  return callPurchaseRpc('purchase_invoice_status_update', {
    p_invoice_id: invoiceId,
    p_status: status,
    p_paid_amount: paidAmount,
    p_notes: notes || null,
  })
}

export function processPurchaseReturn(payload) {
  return callPurchaseRpc('purchase_return_process', {
    p_payload: payload,
  })
}
