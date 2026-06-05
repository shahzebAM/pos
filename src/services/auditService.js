import { requireSupabaseConfig } from '../lib/supabase'

const emptyAuditData = {
  period: {
    from: null,
    to: null,
  },
  summary: {
    total_events: 0,
    critical_events: 0,
    high_events: 0,
    login_events: 0,
    void_events: 0,
    deleted_events: 0,
    price_changes: 0,
    discount_events: 0,
    stock_adjustments: 0,
    unique_actors: 0,
  },
  branches: [],
  actors: [],
  daily_events: [],
  category_summary: [],
  severity_summary: [],
  activity_logs: [],
  login_history: [],
  void_events: [],
  deleted_events: [],
  price_change_events: [],
  discount_events: [],
  stock_adjustment_events: [],
  generated_at: null,
}

function moduleInstallMessage(error) {
  const message = error?.message || ''

  if (
    message.includes('audit_management_get') ||
    message.includes('audit_log_auth_event') ||
    message.includes('schema cache') ||
    message.includes('Could not find the function')
  ) {
    return 'Audit Logs module is not installed yet. Run supabase/20-audit-logs.sql after Module 19.'
  }

  return message || 'Unable to load audit logs.'
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

function normalizeAuditData(payload) {
  const data = payload || emptyAuditData

  return {
    ...emptyAuditData,
    ...data,
    period: {
      from: data.period?.from || null,
      to: data.period?.to || null,
    },
    summary: {
      total_events: numberValue(data.summary?.total_events),
      critical_events: numberValue(data.summary?.critical_events),
      high_events: numberValue(data.summary?.high_events),
      login_events: numberValue(data.summary?.login_events),
      void_events: numberValue(data.summary?.void_events),
      deleted_events: numberValue(data.summary?.deleted_events),
      price_changes: numberValue(data.summary?.price_changes),
      discount_events: numberValue(data.summary?.discount_events),
      stock_adjustments: numberValue(data.summary?.stock_adjustments),
      unique_actors: numberValue(data.summary?.unique_actors),
    },
    branches: arrayValue(data.branches),
    actors: arrayValue(data.actors),
    daily_events: arrayValue(data.daily_events).map((row) => ({
      ...row,
      events: numberValue(row.events),
      risky_events: numberValue(row.risky_events),
    })),
    category_summary: arrayValue(data.category_summary).map((row) => ({
      ...row,
      events: numberValue(row.events),
    })),
    severity_summary: arrayValue(data.severity_summary).map((row) => ({
      ...row,
      events: numberValue(row.events),
    })),
    activity_logs: arrayValue(data.activity_logs),
    login_history: arrayValue(data.login_history),
    void_events: arrayValue(data.void_events),
    deleted_events: arrayValue(data.deleted_events),
    price_change_events: arrayValue(data.price_change_events),
    discount_events: arrayValue(data.discount_events).map((row) =>
      normalizeMoneyRow(row, [
        'discount_total',
        'statutory_discount_amount',
        'statutory_special_discount_amount',
        'total',
      ]),
    ),
    stock_adjustment_events: arrayValue(data.stock_adjustment_events).map((row) =>
      normalizeMoneyRow(row, ['unit_cost']),
    ),
  }
}

export async function fetchAuditManagement({
  from = null,
  to = null,
  branchId = null,
  actorId = null,
  category = null,
  severity = null,
  search = '',
  limit = 200,
} = {}) {
  const client = requireSupabaseConfig()
  const { data, error } = await client.rpc('audit_management_get', {
    p_from: from,
    p_to: to,
    p_branch_id: branchId || null,
    p_actor_id: actorId || null,
    p_category: category || null,
    p_severity: severity || null,
    p_search: search || null,
    p_limit: limit,
  })

  if (error) {
    throw new Error(moduleInstallMessage(error))
  }

  return normalizeAuditData(data)
}

export async function recordAuditAuthEvent(action, metadata = {}) {
  try {
    const client = requireSupabaseConfig()
    await client.rpc('audit_log_auth_event', {
      p_action: action,
      p_metadata: metadata,
    })
  } catch (_error) {
    // Auth should never fail because the optional audit module is missing.
  }
}
