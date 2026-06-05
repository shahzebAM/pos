import { requireSupabaseConfig } from '../lib/supabase'

const emptyMetrics = {
  period: null,
  totals: {
    sales: 0,
    orders: 0,
    discounts: 0,
    vat: 0,
    average_order: 0,
    low_stock_count: 0,
  },
  branches: [],
  sales_by_branch: [],
  daily_sales: [],
  cashier_performance: [],
  low_stock_alerts: [],
  generated_at: null,
}

function numberValue(value) {
  return Number(value || 0)
}

function normalizeMetricRows(rows, moneyFields = []) {
  return (Array.isArray(rows) ? rows : []).map((row) => {
    const normalized = { ...row }

    moneyFields.forEach((field) => {
      normalized[field] = numberValue(row[field])
    })

    if ('orders' in normalized) normalized.orders = numberValue(normalized.orders)
    if ('quantity_on_hand' in normalized) normalized.quantity_on_hand = numberValue(normalized.quantity_on_hand)
    if ('reorder_level' in normalized) normalized.reorder_level = numberValue(normalized.reorder_level)

    return normalized
  })
}

function normalizeMetrics(payload) {
  const data = payload || emptyMetrics

  return {
    ...emptyMetrics,
    ...data,
    totals: {
      sales: numberValue(data.totals?.sales),
      orders: numberValue(data.totals?.orders),
      discounts: numberValue(data.totals?.discounts),
      vat: numberValue(data.totals?.vat),
      average_order: numberValue(data.totals?.average_order),
      low_stock_count: numberValue(data.totals?.low_stock_count),
    },
    branches: Array.isArray(data.branches) ? data.branches : [],
    sales_by_branch: normalizeMetricRows(data.sales_by_branch, ['sales', 'discounts', 'vat']),
    daily_sales: normalizeMetricRows(data.daily_sales, ['sales']),
    cashier_performance: normalizeMetricRows(data.cashier_performance, ['sales', 'average_order']),
    low_stock_alerts: normalizeMetricRows(data.low_stock_alerts),
  }
}

function dashboardInstallMessage(error) {
  const message = error?.message || ''

  if (
    message.includes('dashboard_get_metrics') ||
    message.includes('schema cache') ||
    message.includes('Could not find the function')
  ) {
    return 'Dashboard module is not installed yet. In Supabase SQL Editor, run supabase/00-reset-public-schema.sql first, then run supabase/01-dashboard-module.sql.'
  }

  return message || 'Unable to load dashboard metrics.'
}

export async function fetchDashboardMetrics({ from, to, branchId } = {}) {
  const client = requireSupabaseConfig()
  const { data, error } = await client.rpc('dashboard_get_metrics', {
    p_from: from || null,
    p_to: to || null,
    p_branch_id: branchId || null,
  })

  if (error) {
    throw new Error(dashboardInstallMessage(error))
  }

  return normalizeMetrics(data)
}
