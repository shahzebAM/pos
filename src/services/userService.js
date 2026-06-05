import { requireSupabaseConfig } from '../lib/supabase'

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL?.replace(/\/$/, '')
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY

const emptyUserManagement = {
  summary: {
    total_users: 0,
    active_users: 0,
    admins: 0,
    managers: 0,
    cashiers: 0,
    auditors: 0,
    pending_invites: 0,
  },
  branches: [],
  users: [],
  invitations: [],
  activity_logs: [],
  permission_catalog: [],
  generated_at: null,
}

function moduleInstallMessage(error) {
  const message = error?.message || ''

  if (
    message.includes('user_management_get') ||
    message.includes('auth_resolve_login_identifier') ||
    message.includes('schema cache') ||
    message.includes('Could not find the function')
  ) {
    return 'User & Role Management module is not installed yet. Run supabase/03-user-role-management.sql after Module 2.'
  }

  return message || 'Unable to load user management data.'
}

function numberValue(value) {
  return Number(value || 0)
}

function arrayValue(value) {
  return Array.isArray(value) ? value : []
}

function normalizeUserData(payload) {
  const data = payload || emptyUserManagement

  return {
    ...emptyUserManagement,
    ...data,
    summary: {
      total_users: numberValue(data.summary?.total_users),
      active_users: numberValue(data.summary?.active_users),
      admins: numberValue(data.summary?.admins),
      managers: numberValue(data.summary?.managers),
      cashiers: numberValue(data.summary?.cashiers),
      auditors: numberValue(data.summary?.auditors),
      pending_invites: numberValue(data.summary?.pending_invites),
    },
    branches: arrayValue(data.branches),
    users: arrayValue(data.users).map((user) => ({
      ...user,
      permissions: arrayValue(user.permissions),
      allowed_branch_ids: arrayValue(user.allowed_branch_ids),
      shift_days: arrayValue(user.shift_days).map(Number),
      max_discount_percent: numberValue(user.max_discount_percent),
    })),
    invitations: [],
    activity_logs: arrayValue(data.activity_logs),
    permission_catalog: arrayValue(data.permission_catalog),
  }
}

async function callUserRpc(name, args = {}) {
  const client = requireSupabaseConfig()
  const { data, error } = await client.rpc(name, args)

  if (error) {
    throw new Error(moduleInstallMessage(error))
  }

  return normalizeUserData(data)
}

async function callAdminFunction(name, body) {
  const client = requireSupabaseConfig()
  const { data: sessionData, error: sessionError } = await client.auth.getSession()

  if (sessionError) {
    throw new Error(sessionError.message)
  }

  if (!sessionData.session?.access_token) {
    throw new Error('You must be logged in as admin before calling this staff action.')
  }

  if (!supabaseUrl || !supabaseAnonKey) {
    throw new Error('Supabase environment variables are missing.')
  }

  const functionUrl = `${supabaseUrl}/functions/v1/${name}`

  let response
  try {
    response = await fetch(functionUrl, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${sessionData.session.access_token}`,
        apikey: supabaseAnonKey,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(body),
    })
  } catch (_networkError) {
    throw new Error(
      `Could not reach ${functionUrl}. Make sure VITE_SUPABASE_URL points to the same Supabase project where you deployed the Edge Functions.`,
    )
  }

  const text = await response.text()
  let payload = {}

  if (text) {
    try {
      payload = JSON.parse(text)
    } catch (_parseError) {
      payload = { error: text }
    }
  }

  if (!response.ok) {
    throw new Error(payload?.error || payload?.message || `${name} returned HTTP ${response.status}.`)
  }

  return payload
}

export function fetchUserManagement() {
  return callUserRpc('user_management_get')
}

export async function createStaffDirect(payload) {
  const data = await callAdminFunction('admin-create-staff', payload)
  const management = await fetchUserManagement()

  return {
    ...management,
    direct_staff_username: data?.username,
    direct_staff_created: data?.created,
  }
}

export function updateStaffUser(userId, payload) {
  return callUserRpc('staff_user_update', {
    p_user_id: userId,
    p_payload: payload,
  })
}

export async function hardDeleteStaffUser(userId) {
  await callAdminFunction('admin-delete-staff', {
    user_id: userId,
  })

  return fetchUserManagement()
}
