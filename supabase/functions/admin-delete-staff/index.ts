import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0?target=deno'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
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

  const profile = profilePayload?.profile
  if (!profile?.is_active || profile.role !== 'admin') {
    return jsonResponse({ error: 'Only active admins can permanently delete staff users.' }, 403)
  }

  let payload
  try {
    payload = await req.json()
  } catch (_error) {
    return jsonResponse({ error: 'Invalid JSON body.' }, 400)
  }

  const userId = cleanString(payload.user_id)
  if (!userId) {
    return jsonResponse({ error: 'User id is required.' }, 400)
  }

  if (userId === profile.id) {
    return jsonResponse({ error: 'Admins cannot permanently delete their own active account.' }, 400)
  }

  const { data: targetProfile, error: targetError } = await adminClient
    .from('user_profiles')
    .select('id, username, email, full_name, role')
    .eq('id', userId)
    .maybeSingle()

  if (targetError) {
    return jsonResponse({ error: targetError.message }, 400)
  }

  if (!targetProfile) {
    return jsonResponse({ error: 'User profile not found.' }, 404)
  }

  if (targetProfile.role === 'admin') {
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
      return jsonResponse({ error: 'Cannot permanently delete the last active admin.' }, 400)
    }
  }

  await adminClient.from('activity_logs').insert({
    actor_id: profile.id,
    action: 'staff.user_hard_deleted',
    entity_type: 'user',
    entity_id: userId,
    metadata: {
      email: targetProfile.email,
      username: targetProfile.username,
      full_name: targetProfile.full_name,
      role: targetProfile.role,
    },
  })

  const { error: deleteAuthError } = await adminClient.auth.admin.deleteUser(userId)

  if (deleteAuthError) {
    return jsonResponse({ error: deleteAuthError.message }, 400)
  }

  await adminClient.from('user_access_settings').delete().eq('user_id', userId)
  await adminClient.from('user_profiles').delete().eq('id', userId)

  return jsonResponse({
    deleted: true,
    user_id: userId,
  })
})
