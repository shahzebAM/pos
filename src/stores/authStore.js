import { computed, reactive } from 'vue'
import { requireSupabaseConfig, supabase } from '../lib/supabase'

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL?.replace(/\/$/, '')
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY

const state = reactive({
  initialized: false,
  loading: false,
  session: null,
  profile: null,
  hasAdmin: false,
  error: '',
})

let initPromise = null
let authSubscription = null

function authInstallMessage(error) {
  const message = error?.message || ''

  if (
    message.includes('auth_get_current_profile') ||
    message.includes('auth_resolve_login_identifier') ||
    message.includes('schema cache') ||
    message.includes('Could not find the function')
  ) {
    return 'Login module is not installed yet. Run supabase/02-auth-and-branch-management.sql, then supabase/03-user-role-management.sql.'
  }

  return message || 'Authentication request failed.'
}

function cleanUsername(value) {
  return String(value || '').trim().toLowerCase()
}

async function loadProfile() {
  const client = requireSupabaseConfig()
  const { data, error } = await client.rpc('auth_get_current_profile')

  if (error) {
    throw new Error(authInstallMessage(error))
  }

  state.profile = data?.profile || null
  state.hasAdmin = Boolean(data?.has_admin)

  return data
}

async function initAuth() {
  if (state.initialized) return
  if (initPromise) return initPromise

  initPromise = (async () => {
    state.loading = true
    state.error = ''

    try {
      const client = requireSupabaseConfig()
      const { data, error } = await client.auth.getSession()

      if (error) throw error

      state.session = data.session

      if (state.session) {
        await loadProfile()
      }

      if (!authSubscription) {
        const { data: subscriptionData } = client.auth.onAuthStateChange(async (_event, session) => {
          state.session = session

          if (session) {
            try {
              await loadProfile()
            } catch (profileError) {
              state.error = authInstallMessage(profileError)
              state.profile = null
            }
          } else {
            state.profile = null
            state.hasAdmin = false
          }
        })

        authSubscription = subscriptionData.subscription
      }
    } catch (error) {
      state.error = authInstallMessage(error)
    } finally {
      state.loading = false
      state.initialized = true
    }
  })()

  return initPromise
}

async function resolveLoginEmail(username) {
  const client = requireSupabaseConfig()
  const { data, error } = await client.rpc('auth_resolve_login_identifier', {
    p_identifier: cleanUsername(username),
  })

  if (error) {
    throw new Error(authInstallMessage(error))
  }

  if (!data?.email) {
    throw new Error('Invalid username or password.')
  }

  return data.email
}

async function callPublicFunction(name, body) {
  if (!supabaseUrl || !supabaseAnonKey) {
    throw new Error('Supabase environment variables are missing.')
  }

  const response = await fetch(`${supabaseUrl}/functions/v1/${name}`, {
    method: 'POST',
    headers: {
      apikey: supabaseAnonKey,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  })

  const text = await response.text()
  let payload = {}

  if (text) {
    try {
      payload = JSON.parse(text)
    } catch (_error) {
      payload = { error: text }
    }
  }

  if (!response.ok) {
    throw new Error(payload.error || payload.message || `${name} returned HTTP ${response.status}.`)
  }

  return payload
}

async function signIn({ username, password }) {
  const client = requireSupabaseConfig()
  state.loading = true
  state.error = ''

  try {
    const email = await resolveLoginEmail(username)
    const { data, error } = await client.auth.signInWithPassword({
      email,
      password,
    })

    if (error) throw error

    state.session = data.session
    await loadProfile()

    return data
  } catch (error) {
    state.error = authInstallMessage(error)
    throw new Error(state.error)
  } finally {
    state.loading = false
  }
}

async function createFirstAdmin({ fullName, username, password }) {
  state.loading = true
  state.error = ''

  try {
    await callPublicFunction('admin-bootstrap-user', {
      full_name: fullName,
      username: cleanUsername(username),
      password,
    })

    return await signIn({
      username,
      password,
    })
  } catch (error) {
    state.error = authInstallMessage(error)
    throw new Error(state.error)
  } finally {
    state.loading = false
  }
}

async function signOut() {
  if (!supabase) return

  await supabase.auth.signOut()
  state.session = null
  state.profile = null
  state.hasAdmin = false
}

export function useAuthStore() {
  return {
    state,
    isAuthenticated: computed(() => Boolean(state.session && state.profile?.is_active)),
    isAdmin: computed(() => state.profile?.role === 'admin' && state.profile?.is_active),
    initAuth,
    loadProfile,
    signIn,
    createFirstAdmin,
    signOut,
  }
}
