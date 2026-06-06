import { requireSupabaseConfig } from '../lib/supabase'

const emptyShiftData = {
  period: {
    from: null,
    to: null,
  },
  summary: {
    open_shifts: 0,
    closed_shifts: 0,
    cash_sales: 0,
    non_cash_sales: 0,
    cash_in_total: 0,
    cash_out_total: 0,
    expected_cash: 0,
    counted_cash: 0,
    short_over: 0,
  },
  branches: [],
  registers: [],
  current_shift: null,
  branch_summary: [],
  daily_shifts: [],
  shifts: [],
  movements: [],
  can_open_shift: false,
  can_manage_shifts: false,
  generated_at: null,
}

function moduleInstallMessage(error) {
  const message = error?.message || ''

  if (
    message.includes('shift_management_get') ||
    message.includes('cashier_shifts') ||
    message.includes('cash_registers') ||
    message.includes('cash_drawer_movements') ||
    message.includes('schema cache') ||
    message.includes('Could not find the function')
  ) {
    return 'Cash Register / Shift Management module is not installed yet. Run supabase/12-cash-register-shifts.sql after Module 11.'
  }

  return message || 'Unable to load shift management data.'
}

function numberValue(value) {
  return Number(value || 0)
}

function arrayValue(value) {
  return Array.isArray(value) ? value : []
}

function normalizeShift(row) {
  if (!row) return null

  return {
    ...row,
    opening_cash: numberValue(row.opening_cash),
    cash_sales: numberValue(row.cash_sales),
    non_cash_sales: numberValue(row.non_cash_sales),
    total_sales: numberValue(row.total_sales),
    cash_in_total: numberValue(row.cash_in_total),
    cash_out_total: numberValue(row.cash_out_total),
    change_given_total: numberValue(row.change_given_total),
    expected_cash: numberValue(row.expected_cash),
    counted_cash: row.counted_cash === null || row.counted_cash === undefined ? null : numberValue(row.counted_cash),
    short_over: row.short_over === null || row.short_over === undefined ? null : numberValue(row.short_over),
  }
}

function normalizeShiftData(payload) {
  const data = payload || emptyShiftData

  return {
    ...emptyShiftData,
    ...data,
    period: {
      from: data.period?.from || null,
      to: data.period?.to || null,
    },
    summary: {
      open_shifts: numberValue(data.summary?.open_shifts),
      closed_shifts: numberValue(data.summary?.closed_shifts),
      cash_sales: numberValue(data.summary?.cash_sales),
      non_cash_sales: numberValue(data.summary?.non_cash_sales),
      cash_in_total: numberValue(data.summary?.cash_in_total),
      cash_out_total: numberValue(data.summary?.cash_out_total),
      expected_cash: numberValue(data.summary?.expected_cash),
      counted_cash: numberValue(data.summary?.counted_cash),
      short_over: numberValue(data.summary?.short_over),
    },
    branches: arrayValue(data.branches),
    registers: arrayValue(data.registers),
    current_shift: normalizeShift(data.current_shift),
    branch_summary: arrayValue(data.branch_summary).map((row) => ({
      ...row,
      open_shifts: numberValue(row.open_shifts),
      closed_shifts: numberValue(row.closed_shifts),
      cash_sales: numberValue(row.cash_sales),
      non_cash_sales: numberValue(row.non_cash_sales),
      cash_in_total: numberValue(row.cash_in_total),
      cash_out_total: numberValue(row.cash_out_total),
      short_over: numberValue(row.short_over),
    })),
    daily_shifts: arrayValue(data.daily_shifts).map((row) => ({
      ...row,
      shifts: numberValue(row.shifts),
      cash_sales: numberValue(row.cash_sales),
      total_sales: numberValue(row.total_sales),
      short_over: numberValue(row.short_over),
    })),
    shifts: arrayValue(data.shifts).map(normalizeShift),
    movements: arrayValue(data.movements).map((movement) => ({
      ...movement,
      amount: numberValue(movement.amount),
    })),
    can_open_shift: Boolean(data.can_open_shift),
    can_manage_shifts: Boolean(data.can_manage_shifts),
  }
}

function requireShiftId(payload, actionLabel) {
  const shiftId = payload?.shift_id || payload?.id || null

  if (!shiftId) {
    throw new Error(
      `${actionLabel} needs a valid open shift. Refresh the Shifts page and try again. If this keeps happening, rerun the latest Module 12 SQL so shift records include their ID.`,
    )
  }

  return shiftId
}

async function callShiftRpc(name, args = {}) {
  const client = requireSupabaseConfig()
  const { data, error } = await client.rpc(name, args)

  if (error) {
    throw new Error(moduleInstallMessage(error))
  }

  return normalizeShiftData(data)
}

export function fetchShiftManagement({ from = null, to = null, branchId = null } = {}) {
  return callShiftRpc('shift_management_get', {
    p_from: from,
    p_to: to,
    p_branch_id: branchId || null,
  })
}

export function openShift(payload) {
  return callShiftRpc('shift_open', {
    p_branch_id: payload.branch_id,
    p_cash_register_id: payload.cash_register_id || null,
    p_opening_cash: Number(payload.opening_cash || 0),
    p_notes: payload.notes || null,
  })
}

export function saveCashMovement(payload) {
  return callShiftRpc('shift_cash_movement_save', {
    p_shift_id: requireShiftId(payload, 'Cash movement'),
    p_movement_type: payload.movement_type,
    p_amount: Number(payload.amount || 0),
    p_reason: payload.reason || null,
  })
}

export function closeShift(payload) {
  return callShiftRpc('shift_close', {
    p_shift_id: requireShiftId(payload, 'Shift closing'),
    p_counted_cash: Number(payload.counted_cash || 0),
    p_notes: payload.notes || null,
  })
}
