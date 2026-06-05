import { requireSupabaseConfig } from '../lib/supabase'

const emptyTaxData = {
  period: {
    from: null,
    to: null,
  },
  summary: {
    order_count: 0,
    gross_sales: 0,
    net_sales: 0,
    discounts: 0,
    vat_output: 0,
    vatable_sales: 0,
    vat_exempt_sales: 0,
    zero_rated_sales: 0,
    non_vat_sales: 0,
    percentage_tax_due: 0,
    total_tax_due: 0,
  },
  branches: [],
  branch_profiles: [],
  tax_profiles: [],
  tax_codes: [],
  tax_by_branch: [],
  daily_tax: [],
  tax_mix: [],
  product_tax_mix: [],
  tax_report_lines: [],
  generated_at: null,
}

function moduleInstallMessage(error) {
  const message = error?.message || ''

  if (
    message.includes('tax_management_get') ||
    message.includes('tax_profiles') ||
    message.includes('tax_codes') ||
    message.includes('schema cache') ||
    message.includes('Could not find the function')
  ) {
    return 'Tax Management module is not installed yet. Run supabase/09-tax-management.sql after Module 8.'
  }

  return message || 'Unable to load tax management data.'
}

function numberValue(value) {
  return Number(value || 0)
}

function arrayValue(value) {
  return Array.isArray(value) ? value : []
}

function normalizeTaxData(payload) {
  const data = payload || emptyTaxData

  return {
    ...emptyTaxData,
    ...data,
    period: {
      from: data.period?.from || null,
      to: data.period?.to || null,
    },
    summary: {
      order_count: numberValue(data.summary?.order_count),
      gross_sales: numberValue(data.summary?.gross_sales),
      net_sales: numberValue(data.summary?.net_sales),
      discounts: numberValue(data.summary?.discounts),
      vat_output: numberValue(data.summary?.vat_output),
      vatable_sales: numberValue(data.summary?.vatable_sales),
      vat_exempt_sales: numberValue(data.summary?.vat_exempt_sales),
      zero_rated_sales: numberValue(data.summary?.zero_rated_sales),
      non_vat_sales: numberValue(data.summary?.non_vat_sales),
      percentage_tax_due: numberValue(data.summary?.percentage_tax_due),
      total_tax_due: numberValue(data.summary?.total_tax_due),
    },
    branches: arrayValue(data.branches),
    branch_profiles: arrayValue(data.branch_profiles).map((branch) => ({
      ...branch,
      vat_rate: numberValue(branch.vat_rate),
      percentage_tax_rate: numberValue(branch.percentage_tax_rate),
    })),
    tax_profiles: arrayValue(data.tax_profiles).map((profile) => ({
      ...profile,
      vat_rate: numberValue(profile.vat_rate),
      percentage_tax_rate: numberValue(profile.percentage_tax_rate),
    })),
    tax_codes: arrayValue(data.tax_codes).map((code) => ({
      ...code,
      rate: numberValue(code.rate),
    })),
    tax_by_branch: arrayValue(data.tax_by_branch).map((row) => ({
      ...row,
      orders: numberValue(row.orders),
      gross_sales: numberValue(row.gross_sales),
      net_sales: numberValue(row.net_sales),
      vat_output: numberValue(row.vat_output),
      vatable_sales: numberValue(row.vatable_sales),
      vat_exempt_sales: numberValue(row.vat_exempt_sales),
      zero_rated_sales: numberValue(row.zero_rated_sales),
      non_vat_sales: numberValue(row.non_vat_sales),
      percentage_tax_due: numberValue(row.percentage_tax_due),
    })),
    daily_tax: arrayValue(data.daily_tax).map((row) => ({
      ...row,
      orders: numberValue(row.orders),
      gross_sales: numberValue(row.gross_sales),
      vat_output: numberValue(row.vat_output),
      percentage_tax_due: numberValue(row.percentage_tax_due),
    })),
    tax_mix: arrayValue(data.tax_mix).map((row) => ({
      ...row,
      lines: numberValue(row.lines),
      gross_amount: numberValue(row.gross_amount),
      discount_amount: numberValue(row.discount_amount),
      tax_amount: numberValue(row.tax_amount),
      net_amount: numberValue(row.net_amount),
      taxable_base: numberValue(row.taxable_base),
    })),
    product_tax_mix: arrayValue(data.product_tax_mix).map((row) => ({
      ...row,
      products: numberValue(row.products),
      active_products: numberValue(row.active_products),
      average_rate: numberValue(row.average_rate),
    })),
    tax_report_lines: arrayValue(data.tax_report_lines).map((line) => ({
      ...line,
      amount: numberValue(line.amount),
    })),
  }
}

async function callTaxRpc(name, args = {}) {
  const client = requireSupabaseConfig()
  const { data, error } = await client.rpc(name, args)

  if (error) {
    throw new Error(moduleInstallMessage(error))
  }

  return normalizeTaxData(data)
}

export function fetchTaxManagement({ from = null, to = null, branchId = null } = {}) {
  return callTaxRpc('tax_management_get', {
    p_from: from,
    p_to: to,
    p_branch_id: branchId || null,
  })
}

export function saveTaxProfile(profileId, payload) {
  return callTaxRpc('tax_profile_save', {
    p_profile_id: profileId || null,
    p_payload: payload,
  })
}

export function saveTaxCode(codeId, payload) {
  return callTaxRpc('tax_code_save', {
    p_code_id: codeId || null,
    p_payload: payload,
  })
}

export function saveBranchTaxSettings(branchId, payload) {
  return callTaxRpc('tax_branch_settings_save', {
    p_branch_id: branchId,
    p_payload: payload,
  })
}
