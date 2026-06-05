import { requireSupabaseConfig } from '../lib/supabase'

const emptyAccountingData = {
  period: {
    from: null,
    to: null,
  },
  summary: {
    sales_revenue: 0,
    sales_total: 0,
    cogs: 0,
    gross_profit: 0,
    operating_expenses: 0,
    net_profit: 0,
    cash_in: 0,
    cash_out: 0,
    cash_net: 0,
    accounts_receivable: 0,
    inventory_value: 0,
    store_credit_liability: 0,
    accounts_payable: 0,
    output_vat: 0,
    input_vat: 0,
    vat_payable: 0,
    manual_journal_count: 0,
  },
  branches: [],
  accounts: [],
  sales_journal: [],
  cash_ledger: [],
  receivables: [],
  payables: [],
  profit_loss: [],
  vat_report: {
    output_vat: 0,
    purchase_input_vat: 0,
    expense_input_vat: 0,
    vat_payable: 0,
  },
  daily_summary: [],
  branch_summary: [],
  trial_balance: [],
  manual_journals: [],
  manual_journal_lines: [],
  can_manage_accounting: false,
  can_close_accounting: false,
  generated_at: null,
}

function moduleInstallMessage(error) {
  const message = error?.message || ''

  if (
    message.includes('accounting_management_get') ||
    message.includes('accounting_journal_post') ||
    message.includes('accounting_journal_void') ||
    message.includes('accounting_accounts') ||
    message.includes('accounting_journal_entries') ||
    message.includes('accounting_journal_lines') ||
    message.includes('schema cache') ||
    message.includes('Could not find the function')
  ) {
    return 'Accounting module is not installed yet. Run supabase/18-accounting.sql after Module 17.'
  }

  return message || 'Unable to load accounting data.'
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

function normalizeAccountingData(payload) {
  const data = payload || emptyAccountingData

  return {
    ...emptyAccountingData,
    ...data,
    period: {
      from: data.period?.from || null,
      to: data.period?.to || null,
    },
    summary: {
      sales_revenue: numberValue(data.summary?.sales_revenue),
      sales_total: numberValue(data.summary?.sales_total),
      cogs: numberValue(data.summary?.cogs),
      gross_profit: numberValue(data.summary?.gross_profit),
      operating_expenses: numberValue(data.summary?.operating_expenses),
      net_profit: numberValue(data.summary?.net_profit),
      cash_in: numberValue(data.summary?.cash_in),
      cash_out: numberValue(data.summary?.cash_out),
      cash_net: numberValue(data.summary?.cash_net),
      accounts_receivable: numberValue(data.summary?.accounts_receivable),
      inventory_value: numberValue(data.summary?.inventory_value),
      store_credit_liability: numberValue(data.summary?.store_credit_liability),
      accounts_payable: numberValue(data.summary?.accounts_payable),
      output_vat: numberValue(data.summary?.output_vat),
      input_vat: numberValue(data.summary?.input_vat),
      vat_payable: numberValue(data.summary?.vat_payable),
      manual_journal_count: numberValue(data.summary?.manual_journal_count),
    },
    branches: arrayValue(data.branches),
    accounts: arrayValue(data.accounts).map((account) => ({
      ...account,
      sort_order: numberValue(account.sort_order),
    })),
    sales_journal: arrayValue(data.sales_journal).map((row) =>
      normalizeMoneyRow(row, ['subtotal', 'discount_total', 'tax_total', 'net_sales', 'total', 'cogs_amount']),
    ),
    cash_ledger: arrayValue(data.cash_ledger).map((row) => normalizeMoneyRow(row, ['amount'])),
    receivables: arrayValue(data.receivables).map((row) =>
      normalizeMoneyRow(row, ['credit_limit', 'receivable_balance', 'store_credit_balance', 'total_spent']),
    ),
    payables: arrayValue(data.payables).map((row) =>
      normalizeMoneyRow(row, ['amount', 'tax_amount', 'paid_amount', 'balance_amount']),
    ),
    profit_loss: arrayValue(data.profit_loss).map((row) => normalizeMoneyRow(row, ['amount'])),
    vat_report: {
      output_vat: numberValue(data.vat_report?.output_vat),
      purchase_input_vat: numberValue(data.vat_report?.purchase_input_vat),
      expense_input_vat: numberValue(data.vat_report?.expense_input_vat),
      vat_payable: numberValue(data.vat_report?.vat_payable),
    },
    daily_summary: arrayValue(data.daily_summary).map((row) =>
      normalizeMoneyRow(row, ['revenue', 'cogs', 'expenses', 'net_profit']),
    ),
    branch_summary: arrayValue(data.branch_summary).map((row) =>
      normalizeMoneyRow(row, ['revenue', 'cogs', 'expenses', 'net_profit']),
    ),
    trial_balance: arrayValue(data.trial_balance).map((row) => normalizeMoneyRow(row, ['balance'])),
    manual_journals: arrayValue(data.manual_journals).map((row) =>
      normalizeMoneyRow(row, ['debit_total', 'credit_total']),
    ),
    manual_journal_lines: arrayValue(data.manual_journal_lines).map((row) =>
      normalizeMoneyRow(row, ['debit', 'credit']),
    ),
    can_manage_accounting: Boolean(data.can_manage_accounting),
    can_close_accounting: Boolean(data.can_close_accounting),
  }
}

async function callAccountingRpc(name, args = {}) {
  const client = requireSupabaseConfig()
  const { data, error } = await client.rpc(name, args)

  if (error) {
    throw new Error(moduleInstallMessage(error))
  }

  return normalizeAccountingData(data)
}

export function fetchAccountingManagement({ from = null, to = null, branchId = null, search = '' } = {}) {
  return callAccountingRpc('accounting_management_get', {
    p_from: from,
    p_to: to,
    p_branch_id: branchId || null,
    p_search: search || null,
  })
}

export function postAccountingJournal(payload) {
  return callAccountingRpc('accounting_journal_post', {
    p_payload: payload,
  })
}

export function voidAccountingJournal(journalId, reason) {
  return callAccountingRpc('accounting_journal_void', {
    p_journal_id: journalId,
    p_reason: reason,
  })
}
