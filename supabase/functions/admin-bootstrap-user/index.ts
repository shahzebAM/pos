import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0?target=deno'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const adminPermissions = [
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
]

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

function validateUsername(username) {
  return /^[a-z0-9][a-z0-9._-]{2,31}$/.test(username)
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

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  if (req.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed' }, 405)
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL')
  const supabaseServiceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')

  if (!supabaseUrl || !supabaseServiceRoleKey) {
    return jsonResponse({ error: 'Supabase Edge Function environment variables are missing.' }, 500)
  }

  const adminClient = createClient(supabaseUrl, supabaseServiceRoleKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  })

  const { count, error: countError } = await adminClient
    .from('user_profiles')
    .select('id', { count: 'exact', head: true })
    .eq('role', 'admin')
    .eq('is_active', true)
    .is('deleted_at', null)

  if (countError) {
    return jsonResponse({ error: countError.message }, 400)
  }

  if ((count || 0) > 0) {
    return jsonResponse({ error: 'First admin already exists. Login as admin to create more users.' }, 409)
  }

  let payload
  try {
    payload = await req.json()
  } catch (_error) {
    return jsonResponse({ error: 'Invalid JSON body.' }, 400)
  }

  const username = normalizeUsername(payload.username)
  const password = cleanString(payload.password)
  const fullName = cleanString(payload.full_name) || 'Admin'
  const email = internalEmail(username)

  if (!validateUsername(username)) {
    return jsonResponse({ error: 'Username must be 3-32 characters and use lowercase letters, numbers, dot, underscore, or dash.' }, 400)
  }

  if (!password || password.length < 6) {
    return jsonResponse({ error: 'Password must be at least 6 characters.' }, 400)
  }

  let userId = null
  let createdNewUser = false

  const { data: createdUser, error: createError } = await adminClient.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: {
      username,
      full_name: fullName,
      first_admin_bootstrap: true,
    },
  })

  userId = createdUser.user?.id || null
  createdNewUser = Boolean(userId)

  if (createError || !userId) {
    const alreadyRegistered = createError?.message?.toLowerCase().includes('already')

    if (!alreadyRegistered) {
      return jsonResponse({ error: createError?.message || 'Unable to create first admin.' }, 400)
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

    const { error: updateAuthError } = await adminClient.auth.admin.updateUserById(userId, {
      password,
      email_confirm: true,
      user_metadata: {
        username,
        full_name: fullName,
        first_admin_bootstrap: true,
      },
    })

    if (updateAuthError) {
      return jsonResponse({ error: updateAuthError.message }, 400)
    }
  }

  const { error: profileUpsertError } = await adminClient.from('user_profiles').upsert({
    id: userId,
    username,
    email,
    full_name: fullName,
    role: 'admin',
    branch_id: null,
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
    can_access_all_branches: true,
    allowed_branch_ids: [],
    permissions: adminPermissions,
    shift_days: [1, 2, 3, 4, 5, 6, 7],
    shift_start: '00:00',
    shift_end: '23:59',
    max_discount_percent: 100,
    can_open_shift: true,
    can_close_shift: true,
    updated_at: new Date().toISOString(),
  })

  if (accessUpsertError) {
    if (createdNewUser) {
      await adminClient.auth.admin.deleteUser(userId)
    }

    return jsonResponse({ error: accessUpsertError.message }, 400)
  }

  await adminClient.from('activity_logs').insert({
    actor_id: userId,
    action: 'auth.first_admin_bootstrap',
    entity_type: 'user',
    entity_id: userId,
    metadata: {
      username,
      created_directly: true,
    },
  })

  return jsonResponse({
    user_id: userId,
    username,
    full_name: fullName,
  })
})
