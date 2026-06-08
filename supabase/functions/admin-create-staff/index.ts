import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0?target=deno'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const roleDefaults = {
  admin: [
    'dashboard.view',
    'branches.view',
    'branches.manage',
    'users.view',
    'users.manage',
    'shifts.view',
    'shifts.manage',
    'activity.view',
    'pos.sell',
    'pos.discount',
    'pos.void',
    'reports.view',
  ],
  manager: ['dashboard.view', 'branches.view', 'users.view', 'shifts.view', 'shifts.manage', 'activity.view', 'pos.sell', 'pos.discount', 'reports.view'],
  cashier: ['dashboard.view', 'pos.sell', 'shifts.view'],
  auditor: ['dashboard.view', 'branches.view', 'users.view', 'activity.view', 'reports.view'],
}

function jsonResponse(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      'Content-Type': 'application/json',
    },
  })
}

function cleanString(value) {
  return typeof value === 'string' ? value.trim() : ''
}

function normalizeUsername(value) {
  return cleanString(value).toLowerCase()
}

function internalEmail(username) {
  return `${username}@staff.pos.test`
}

function arrayValue(value, fallback = []) {
  return Array.isArray(value) ? value : fallback
}

async function findAuthUserByEmail(adminClient, email) {
  const normalizedEmail = email.toLowerCase()
  const perPage = 1000

  for (let page = 1; page <= 20; page += 1) {
    const { data, error } = await adminClient.auth.admin.listUsers({
      page,
      perPage,
    })

    if (error) throw error

    const user = data.users.find((candidate) => candidate.email?.toLowerCase() === normalizedEmail)
    if (user) return user

    if (data.users.length < perPage) break
  }

  return null
}

function validateUsername(username) {
  return /^[a-z0-9][a-z0-9._-]{2,31}$/.test(username)
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  if (req.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed' }, 405)
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL')
  const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY')
  const supabaseServiceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  const authorization = req.headers.get('Authorization') || ''

  if (!supabaseUrl || !supabaseAnonKey || !supabaseServiceRoleKey) {
    return jsonResponse({ error: 'Supabase Edge Function environment variables are missing.' }, 500)
  }

  if (!authorization.startsWith('Bearer ')) {
    return jsonResponse({ error: 'Missing user session.' }, 401)
  }

  const userClient = createClient(supabaseUrl, supabaseAnonKey, {
    global: {
      headers: {
        Authorization: authorization,
      },
    },
  })

  const adminClient = createClient(supabaseUrl, supabaseServiceRoleKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  })

  const { data: profilePayload, error: profileError } = await userClient.rpc('auth_get_current_profile')

  if (profileError) {
    return jsonResponse({ error: profileError.message }, 401)
  }

  const adminProfile = profilePayload?.profile
  if (!adminProfile?.is_active || adminProfile.role !== 'admin') {
    return jsonResponse({ error: 'Only active admins can create staff users.' }, 403)
  }

  let payload
  try {
    payload = await req.json()
  } catch (_error) {
    return jsonResponse({ error: 'Invalid JSON body.' }, 400)
  }

  const username = normalizeUsername(payload.username)
  const password = cleanString(payload.password)
  const fullName = cleanString(payload.full_name) || username
  const phone = cleanString(payload.phone) || null
  const jobTitle = cleanString(payload.job_title) || null
  const role = cleanString(payload.role) || 'cashier'
  const branchId = cleanString(payload.branch_id) || null
  const email = internalEmail(username)
  const canAccessAllBranches = Boolean(payload.can_access_all_branches ?? ['admin', 'auditor'].includes(role))
  const allowedBranchIds = arrayValue(payload.allowed_branch_ids, branchId ? [branchId] : [])
  const permissions = arrayValue(payload.permissions, roleDefaults[role] || roleDefaults.cashier)
  const shiftDays = arrayValue(payload.shift_days, [1, 2, 3, 4, 5, 6, 7])
  const shiftStart = cleanString(payload.shift_start) || '00:00'
  const shiftEnd = cleanString(payload.shift_end) || '23:59'
  const maxDiscountPercent = Number(payload.max_discount_percent ?? (role === 'admin' ? 100 : role === 'manager' ? 20 : role === 'cashier' ? 5 : 0))
  const canOpenShift = Boolean(payload.can_open_shift ?? true)
  const canCloseShift = Boolean(payload.can_close_shift ?? ['admin', 'manager'].includes(role))

  if (!validateUsername(username)) {
    return jsonResponse({ error: 'Username must be 3-32 characters and use lowercase letters, numbers, dot, underscore, or dash.' }, 400)
  }

  if (!password || password.length < 6) {
    return jsonResponse({ error: 'Password must be at least 6 characters.' }, 400)
  }

  if (!['admin', 'manager', 'cashier', 'auditor'].includes(role)) {
    return jsonResponse({ error: 'Invalid role.' }, 400)
  }

  if (['manager', 'cashier'].includes(role) && !branchId) {
    return jsonResponse({ error: 'Branch is required for manager and cashier roles.' }, 400)
  }

  const { data: existingProfile, error: existingProfileError } = await adminClient
    .from('user_profiles')
    .select('id, username, role, is_active, deleted_at')
    .eq('username', username)
    .maybeSingle()

  if (existingProfileError) {
    return jsonResponse({ error: existingProfileError.message }, 400)
  }

  let userId = existingProfile?.id || null
  let createdNewUser = false

  if (userId === adminProfile.id) {
    return jsonResponse({ error: 'Use Edit user to change your own admin profile.' }, 400)
  }

  if (existingProfile?.role === 'admin' && role !== 'admin') {
    const { count, error: countError } = await adminClient
      .from('user_profiles')
      .select('id', { count: 'exact', head: true })
      .eq('role', 'admin')
      .eq('is_active', true)
      .is('deleted_at', null)

    if (countError) {
      return jsonResponse({ error: countError.message }, 400)
    }

    if ((count || 0) <= 1) {
      return jsonResponse({ error: 'Cannot change the last active admin into another role.' }, 400)
    }
  }

  if (userId) {
    const { error: updateAuthError } = await adminClient.auth.admin.updateUserById(userId, {
      password,
      email_confirm: true,
      user_metadata: {
        username,
        full_name: fullName,
        updated_by_admin: adminProfile.id,
      },
    })

    if (updateAuthError) {
      return jsonResponse({ error: updateAuthError.message }, 400)
    }
  } else {
    const { data: createdUser, error: createError } = await adminClient.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: {
        username,
        full_name: fullName,
        created_by_admin: adminProfile.id,
      },
    })

    userId = createdUser.user?.id || null
    createdNewUser = Boolean(userId)

    if (createError || !userId) {
      const createMessage = createError?.message || ''
      const normalizedCreateMessage = createMessage.toLowerCase()
      const alreadyRegistered = normalizedCreateMessage.includes('already')
      const databaseTriggerFailed = normalizedCreateMessage.includes('database error')

      if (!alreadyRegistered) {
        if (databaseTriggerFailed) {
          return jsonResponse(
            {
              error:
                'Staff login could not be created because the new-user trigger is outdated or broken. Run supabase/patch-auth-user-trigger.sql in SQL Editor, then try again.',
            },
            400,
          )
        }

        return jsonResponse({ error: createMessage || 'Unable to create staff user.' }, 400)
      }

      let existingAuthUser
      try {
        existingAuthUser = await findAuthUserByEmail(adminClient, email)
      } catch (findError) {
        return jsonResponse({ error: findError instanceof Error ? findError.message : 'Unable to find existing Auth user.' }, 400)
      }

      if (!existingAuthUser) {
        return jsonResponse({ error: 'Username already exists in Supabase Auth. Delete that Auth user first or choose another username.' }, 400)
      }

      userId = existingAuthUser.id
      createdNewUser = false

      const { error: updateExistingAuthError } = await adminClient.auth.admin.updateUserById(userId, {
        password,
        email_confirm: true,
        user_metadata: {
          username,
          full_name: fullName,
          updated_by_admin: adminProfile.id,
        },
      })

      if (updateExistingAuthError) {
        return jsonResponse({ error: updateExistingAuthError.message }, 400)
      }
    }
  }

  const { error: profileUpsertError } = await adminClient.from('user_profiles').upsert({
    id: userId,
    username,
    email,
    full_name: fullName,
    phone,
    job_title: jobTitle,
    role,
    branch_id: branchId,
    is_active: true,
    deleted_at: null,
    updated_at: new Date().toISOString(),
  })

  if (profileUpsertError) {
    if (createdNewUser) {
      await adminClient.auth.admin.deleteUser(userId)
    }

    return jsonResponse({ error: profileUpsertError.message }, 400)
  }

  const { error: accessUpsertError } = await adminClient.from('user_access_settings').upsert({
    user_id: userId,
    can_access_all_branches: canAccessAllBranches,
    allowed_branch_ids: allowedBranchIds,
    permissions,
    shift_days: shiftDays,
    shift_start: shiftStart,
    shift_end: shiftEnd,
    max_discount_percent: maxDiscountPercent,
    can_open_shift: canOpenShift,
    can_close_shift: canCloseShift,
    updated_at: new Date().toISOString(),
  })

  if (accessUpsertError) {
    if (createdNewUser) {
      await adminClient.auth.admin.deleteUser(userId)
    }

    return jsonResponse({ error: accessUpsertError.message }, 400)
  }

  await adminClient.from('activity_logs').insert({
    actor_id: adminProfile.id,
    action: createdNewUser ? 'staff.user_created' : 'staff.user_reactivated',
    entity_type: 'user',
    entity_id: userId,
    metadata: {
      username,
      role,
      branch_id: branchId,
      created_directly: true,
    },
  })

  return jsonResponse({
    user_id: userId,
    username,
    full_name: fullName,
    role,
    created: createdNewUser,
  })
})
