import { createClient } from '@supabase/supabase-js'

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL
const supabaseKey =
  import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY ||
  import.meta.env.VITE_SUPABASE_ANON_KEY
const rpcCache = new Map()
const rpcInflight = new Map()

function stableStringify(value) {
  if (value === null || typeof value !== 'object') {
    return JSON.stringify(value)
  }

  if (Array.isArray(value)) {
    return `[${value.map(stableStringify).join(',')}]`
  }

  return `{${Object.keys(value)
    .sort()
    .map((key) => `${JSON.stringify(key)}:${stableStringify(value[key])}`)
    .join(',')}}`
}

function isCacheableRpc(functionName) {
  return (
    functionName === 'dashboard_get_metrics' ||
    functionName === 'shift_pos_status_get' ||
    functionName === 'customer_pos_options_get' ||
    functionName.endsWith('_management_get')
  )
}

function isReadOnlyRpc(functionName) {
  return functionName.startsWith('auth_') || functionName.endsWith('_get') || functionName === 'dashboard_get_metrics'
}

function cacheTtl(functionName) {
  if (functionName === 'pos_management_get' || functionName === 'shift_pos_status_get') return 5000
  if (functionName === 'reports_management_get' || functionName === 'audit_management_get') return 15000
  return 10000
}

function rpcCacheKey(functionName, args = {}, options = {}) {
  return `${functionName}:${stableStringify(args)}:${stableStringify(options)}`
}

export function clearSupabaseRpcCache() {
  rpcCache.clear()
  rpcInflight.clear()
}

function withRpcCache(client) {
  const rawRpc = client.rpc.bind(client)

  client.rpc = (functionName, args = {}, options = {}) => {
    if (!isCacheableRpc(functionName)) {
      return Promise.resolve(rawRpc(functionName, args, options)).then((result) => {
        if (!result?.error && !isReadOnlyRpc(functionName)) {
          clearSupabaseRpcCache()
        }

        return result
      })
    }

    const key = rpcCacheKey(functionName, args, options)
    const now = Date.now()
    const cached = rpcCache.get(key)

    if (cached && cached.expiresAt > now) {
      return Promise.resolve(cached.result)
    }

    const inflight = rpcInflight.get(key)
    if (inflight) {
      return inflight
    }

    const request = Promise.resolve(rawRpc(functionName, args, options))
      .then((result) => {
        if (!result?.error) {
          rpcCache.set(key, {
            result,
            expiresAt: Date.now() + cacheTtl(functionName),
          })
        }

        return result
      })
      .finally(() => {
        rpcInflight.delete(key)
      })

    rpcInflight.set(key, request)
    return request
  }

  return client
}

export const isSupabaseConfigured = Boolean(
  supabaseUrl &&
    supabaseKey &&
    !supabaseUrl.includes('your-project') &&
    !supabaseKey.includes('your-public-anon-key'),
)

export const supabase = isSupabaseConfigured
  ? withRpcCache(
      createClient(supabaseUrl, supabaseKey, {
        auth: {
          persistSession: true,
          autoRefreshToken: true,
          detectSessionInUrl: true,
        },
      }),
    )
  : null

export function requireSupabaseConfig() {
  if (!isSupabaseConfigured || !supabase) {
    throw new Error(
      'Supabase environment variables are missing. Add VITE_SUPABASE_URL and VITE_SUPABASE_PUBLISHABLE_KEY or VITE_SUPABASE_ANON_KEY.',
    )
  }

  return supabase
}
