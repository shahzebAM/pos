import { requireSupabaseConfig } from '../lib/supabase'

const emptyReportsData = {
  period: {
    from: null,
    to: null,
  },
  active_report_key: 'overview',
  summary: {
    orders: 0,
    sales: 0,
    net_sales: 0,
    discounts: 0,
    vat: 0,
    returns: 0,
    cogs: 0,
    gross_profit: 0,
    expenses: 0,
    net_profit: 0,
    inventory_value: 0,
    low_stock_count: 0,
    out_of_stock_count: 0,
    senior_pwd_discount: 0,
    z_reading_count: 0,
    payment_amount: 0,
    payment_fees: 0,
  },
  branches: [],
  daily_sales: [],
  branch_sales: [],
  cashier_sales: [],
  payment_mix: [],
  sales_detail: [],
  inventory_report: [],
  stock_movement_report: [],
  vat_sales_report: [],
  senior_pwd_report: [],
  z_reading_report: [],
  profit_report: [],
  top_products: [],
  slow_moving_products: [],
  generated_at: null,
}

function moduleInstallMessage(error) {
  const message = error?.message || ''

  if (
    message.includes('reports_management_get') ||
    message.includes('reports_effective_permissions') ||
    message.includes('schema cache') ||
    message.includes('Could not find the function')
  ) {
    return 'Reports module is not installed yet. Run supabase/19-reports.sql after Module 18.'
  }

  return message || 'Unable to load reports.'
}

function numberValue(value) {
  return Number(value || 0)
}

function arrayValue(value) {
  return Array.isArray(value) ? value : []
}

function normalizeMoneyRow(row, fields) {
  return {
    ...row,
    ...fields.reduce(
      (values, field) => ({
        ...values,
        [field]: numberValue(row[field]),
      }),
      {},
    ),
  }
}

function normalizeReportsData(payload) {
  const data = payload || emptyReportsData

  return {
    ...emptyReportsData,
    ...data,
    period: {
      from: data.period?.from || null,
      to: data.period?.to || null,
    },
    summary: {
      orders: numberValue(data.summary?.orders),
      sales: numberValue(data.summary?.sales),
      net_sales: numberValue(data.summary?.net_sales),
      discounts: numberValue(data.summary?.discounts),
      vat: numberValue(data.summary?.vat),
      returns: numberValue(data.summary?.returns),
      cogs: numberValue(data.summary?.cogs),
      gross_profit: numberValue(data.summary?.gross_profit),
      expenses: numberValue(data.summary?.expenses),
      net_profit: numberValue(data.summary?.net_profit),
      inventory_value: numberValue(data.summary?.inventory_value),
      low_stock_count: numberValue(data.summary?.low_stock_count),
      out_of_stock_count: numberValue(data.summary?.out_of_stock_count),
      senior_pwd_discount: numberValue(data.summary?.senior_pwd_discount),
      z_reading_count: numberValue(data.summary?.z_reading_count),
      payment_amount: numberValue(data.summary?.payment_amount),
      payment_fees: numberValue(data.summary?.payment_fees),
    },
    branches: arrayValue(data.branches),
    daily_sales: arrayValue(data.daily_sales).map((row) =>
      normalizeMoneyRow(row, ['sales', 'net_sales', 'discounts', 'vat', 'returns']),
    ),
    branch_sales: arrayValue(data.branch_sales).map((row) =>
      normalizeMoneyRow(row, ['sales', 'net_sales', 'discounts', 'vat', 'average_order']),
    ),
    cashier_sales: arrayValue(data.cashier_sales).map((row) =>
      normalizeMoneyRow(row, ['sales', 'net_sales', 'average_order', 'discounts']),
    ),
    payment_mix: arrayValue(data.payment_mix).map((row) =>
      normalizeMoneyRow(row, ['amount', 'fees', 'net_amount']),
    ),
    sales_detail: arrayValue(data.sales_detail).map((row) =>
      normalizeMoneyRow(row, [
        'subtotal',
        'discount_total',
        'tax_total',
        'net_sales',
        'total',
        'return_total',
        'statutory_discount_amount',
        'cogs_amount',
        'gross_profit',
      ]),
    ),
    inventory_report: arrayValue(data.inventory_report).map((row) =>
      normalizeMoneyRow(row, ['inventory_value']),
    ),
    stock_movement_report: arrayValue(data.stock_movement_report).map((row) =>
      normalizeMoneyRow(row, ['unit_cost']),
    ),
    vat_sales_report: arrayValue(data.vat_sales_report).map((row) =>
      normalizeMoneyRow(row, ['gross_amount', 'discount_amount', 'net_amount', 'tax_amount']),
    ),
    senior_pwd_report: arrayValue(data.senior_pwd_report).map((row) =>
      normalizeMoneyRow(row, [
        'gross_amount',
        'regular_discount_amount',
        'special_discount_amount',
        'vat_exempt_amount',
        'total_discount_amount',
        'total',
      ]),
    ),
    z_reading_report: arrayValue(data.z_reading_report).map((row) =>
      normalizeMoneyRow(row, ['gross_sales', 'discount_total', 'vat_total', 'net_sales', 'voided_amount']),
    ),
    profit_report: arrayValue(data.profit_report).map((row) =>
      normalizeMoneyRow(row, ['revenue', 'cogs', 'gross_profit', 'expenses', 'net_profit', 'output_vat', 'input_vat']),
    ),
    top_products: arrayValue(data.top_products).map((row) =>
      normalizeMoneyRow(row, ['net_sales', 'cogs_amount', 'gross_profit']),
    ),
    slow_moving_products: arrayValue(data.slow_moving_products).map((row) =>
      normalizeMoneyRow(row, ['inventory_value']),
    ),
  }
}

export async function fetchReportsManagement({ from = null, to = null, branchId = null, reportKey = 'overview', search = '' } = {}) {
  const client = requireSupabaseConfig()
  const { data, error } = await client.rpc('reports_management_get', {
    p_from: from,
    p_to: to,
    p_branch_id: branchId || null,
    p_report_key: reportKey || 'overview',
    p_search: search || null,
  })

  if (error) {
    throw new Error(moduleInstallMessage(error))
  }

  return normalizeReportsData(data)
}
