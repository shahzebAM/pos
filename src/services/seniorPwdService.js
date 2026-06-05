import { requireSupabaseConfig } from '../lib/supabase'

const emptySeniorPwdData = {
  period: {
    from: null,
    to: null,
  },
  summary: {
    claims: 0,
    senior_claims: 0,
    pwd_claims: 0,
    regular_discount_amount: 0,
    special_discount_amount: 0,
    vat_exempt_amount: 0,
    total_discount_amount: 0,
  },
  branches: [],
  branch_settings: [],
  products: [],
  claims: [],
  daily_claims: [],
  eligibility_summary: {
    regular_20: 0,
    basic_necessity_5: 0,
    not_eligible: 0,
  },
  generated_at: null,
}

function moduleInstallMessage(error) {
  const message = error?.message || ''

  if (
    message.includes('senior_pwd_management_get') ||
    message.includes('senior_pwd_discount_claims') ||
    message.includes('senior_pwd_discount_settings') ||
    message.includes('schema cache') ||
    message.includes('Could not find the function')
  ) {
    return 'Senior/PWD Discount module is not installed yet. Run supabase/10-senior-pwd-discounts.sql after Module 9.'
  }

  return message || 'Unable to load Senior/PWD data.'
}

function numberValue(value) {
  return Number(value || 0)
}

function arrayValue(value) {
  return Array.isArray(value) ? value : []
}

function normalizeSeniorPwdData(payload) {
  const data = payload || emptySeniorPwdData

  return {
    ...emptySeniorPwdData,
    ...data,
    period: {
      from: data.period?.from || null,
      to: data.period?.to || null,
    },
    summary: {
      claims: numberValue(data.summary?.claims),
      senior_claims: numberValue(data.summary?.senior_claims),
      pwd_claims: numberValue(data.summary?.pwd_claims),
      regular_discount_amount: numberValue(data.summary?.regular_discount_amount),
      special_discount_amount: numberValue(data.summary?.special_discount_amount),
      vat_exempt_amount: numberValue(data.summary?.vat_exempt_amount),
      total_discount_amount: numberValue(data.summary?.total_discount_amount),
    },
    branches: arrayValue(data.branches),
    branch_settings: arrayValue(data.branch_settings).map((branch) => ({
      ...branch,
      standard_discount_rate: numberValue(branch.standard_discount_rate),
      basic_necessity_rate: numberValue(branch.basic_necessity_rate),
      claims: numberValue(branch.claims),
      total_benefit: numberValue(branch.total_benefit),
    })),
    products: arrayValue(data.products).map((product) => ({
      ...product,
      selling_price: numberValue(product.selling_price),
      vat_rate: numberValue(product.vat_rate),
    })),
    claims: arrayValue(data.claims).map((claim) => ({
      ...claim,
      gross_amount: numberValue(claim.gross_amount),
      regular_discount_amount: numberValue(claim.regular_discount_amount),
      special_discount_amount: numberValue(claim.special_discount_amount),
      vat_exempt_amount: numberValue(claim.vat_exempt_amount),
      total_discount_amount: numberValue(claim.total_discount_amount),
      invoice_total: numberValue(claim.invoice_total),
    })),
    daily_claims: arrayValue(data.daily_claims).map((row) => ({
      ...row,
      claims: numberValue(row.claims),
      regular_discount_amount: numberValue(row.regular_discount_amount),
      special_discount_amount: numberValue(row.special_discount_amount),
      vat_exempt_amount: numberValue(row.vat_exempt_amount),
      total_discount_amount: numberValue(row.total_discount_amount),
    })),
    eligibility_summary: {
      regular_20: numberValue(data.eligibility_summary?.regular_20),
      basic_necessity_5: numberValue(data.eligibility_summary?.basic_necessity_5),
      not_eligible: numberValue(data.eligibility_summary?.not_eligible),
    },
  }
}

async function callSeniorPwdRpc(name, args = {}) {
  const client = requireSupabaseConfig()
  const { data, error } = await client.rpc(name, args)

  if (error) {
    throw new Error(moduleInstallMessage(error))
  }

  return normalizeSeniorPwdData(data)
}

export function fetchSeniorPwdManagement({ from = null, to = null, branchId = null } = {}) {
  return callSeniorPwdRpc('senior_pwd_management_get', {
    p_from: from,
    p_to: to,
    p_branch_id: branchId || null,
  })
}

export function saveSeniorPwdSettings(branchId, payload) {
  return callSeniorPwdRpc('senior_pwd_settings_save', {
    p_branch_id: branchId,
    p_payload: payload,
  })
}

export function saveProductEligibility(productId, category) {
  return callSeniorPwdRpc('senior_pwd_product_eligibility_save', {
    p_product_id: productId,
    p_category: category,
  })
}
