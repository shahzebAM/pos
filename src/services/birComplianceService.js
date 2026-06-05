import { requireSupabaseConfig } from '../lib/supabase'

const emptyBirData = {
  summary: {
    machines: 0,
    active_machines: 0,
    active_series: 0,
    readings: 0,
    reprinted_invoices: 0,
    voided_invoices: 0,
  },
  document_types: [],
  branches: [],
  machines: [],
  series: [],
  readings: [],
  orders: [],
  generated_at: null,
}

function moduleInstallMessage(error) {
  const message = error?.message || ''

  if (
    message.includes('bir_compliance_management_get') ||
    message.includes('bir_pos_machines') ||
    message.includes('bir_invoice_series') ||
    message.includes('schema cache') ||
    message.includes('Could not find the function')
  ) {
    return 'BIR Compliance module is not installed yet. Run supabase/08-bir-compliance.sql after Module 7.'
  }

  return message || 'Unable to load BIR compliance data.'
}

function numberValue(value) {
  return Number(value || 0)
}

function arrayValue(value) {
  return Array.isArray(value) ? value : []
}

function normalizeBirData(payload) {
  const data = payload || emptyBirData

  return {
    ...emptyBirData,
    ...data,
    summary: {
      machines: numberValue(data.summary?.machines),
      active_machines: numberValue(data.summary?.active_machines),
      active_series: numberValue(data.summary?.active_series),
      readings: numberValue(data.summary?.readings),
      reprinted_invoices: numberValue(data.summary?.reprinted_invoices),
      voided_invoices: numberValue(data.summary?.voided_invoices),
    },
    document_types: arrayValue(data.document_types),
    branches: arrayValue(data.branches),
    machines: arrayValue(data.machines),
    series: arrayValue(data.series).map((series) => ({
      ...series,
      start_number: numberValue(series.start_number),
      current_number: numberValue(series.current_number),
      end_number: numberValue(series.end_number),
      digits: numberValue(series.digits),
      remaining_numbers: numberValue(series.remaining_numbers),
    })),
    readings: arrayValue(data.readings).map((reading) => ({
      ...reading,
      gross_sales: numberValue(reading.gross_sales),
      discount_total: numberValue(reading.discount_total),
      vat_total: numberValue(reading.vat_total),
      net_sales: numberValue(reading.net_sales),
      vatable_sales: numberValue(reading.vatable_sales),
      vat_exempt_sales: numberValue(reading.vat_exempt_sales),
      zero_rated_sales: numberValue(reading.zero_rated_sales),
      non_vat_sales: numberValue(reading.non_vat_sales),
      completed_order_count: numberValue(reading.completed_order_count),
      voided_order_count: numberValue(reading.voided_order_count),
      voided_amount: numberValue(reading.voided_amount),
    })),
    orders: arrayValue(data.orders).map((order) => ({
      ...order,
      bir_sequence_number: numberValue(order.bir_sequence_number),
      bir_reprint_count: numberValue(order.bir_reprint_count),
      total: numberValue(order.total),
      tax_total: numberValue(order.tax_total),
      discount_total: numberValue(order.discount_total),
    })),
  }
}

async function callBirRpc(name, args = {}) {
  const client = requireSupabaseConfig()
  const { data, error } = await client.rpc(name, args)

  if (error) {
    throw new Error(moduleInstallMessage(error))
  }

  return normalizeBirData(data)
}

export function fetchBirCompliance(branchId = null) {
  return callBirRpc('bir_compliance_management_get', {
    p_branch_id: branchId || null,
  })
}

export function saveBirMachine(machineId, payload) {
  return callBirRpc('bir_machine_save', {
    p_machine_id: machineId || null,
    p_payload: payload,
  })
}

export function saveBirSeries(seriesId, payload) {
  return callBirRpc('bir_series_save', {
    p_series_id: seriesId || null,
    p_payload: payload,
  })
}

export function logInvoiceReprint(orderId, reason) {
  return callBirRpc('bir_log_invoice_reprint', {
    p_order_id: orderId,
    p_reason: reason || 'Customer copy',
  })
}

export function voidInvoice(orderId, reason) {
  return callBirRpc('bir_void_invoice', {
    p_order_id: orderId,
    p_reason: reason,
  })
}

export function generateBirReading(payload) {
  return callBirRpc('bir_generate_reading', {
    p_payload: payload,
  })
}
