import { createRouter, createWebHistory } from 'vue-router'
import { useAuthStore } from '../stores/authStore'

const routeComponents = {
  accounting: () => import('../pages/AccountingPage.vue'),
  'audit-logs': () => import('../pages/AuditLogsPage.vue'),
  'bir-compliance': () => import('../pages/BirCompliancePage.vue'),
  branches: () => import('../pages/BranchManagementPage.vue'),
  customers: () => import('../pages/CustomerManagementPage.vue'),
  dashboard: () => import('../pages/DashboardPage.vue'),
  expenses: () => import('../pages/ExpenseManagementPage.vue'),
  inventory: () => import('../pages/InventoryManagementPage.vue'),
  login: () => import('../pages/LoginPage.vue'),
  payments: () => import('../pages/PaymentManagementPage.vue'),
  pos: () => import('../pages/PosCheckoutPage.vue'),
  products: () => import('../pages/ProductManagementPage.vue'),
  purchases: () => import('../pages/PurchaseManagementPage.vue'),
  reports: () => import('../pages/ReportsPage.vue'),
  returns: () => import('../pages/ReturnsManagementPage.vue'),
  'senior-pwd': () => import('../pages/SeniorPwdDiscountPage.vue'),
  shifts: () => import('../pages/ShiftManagementPage.vue'),
  suppliers: () => import('../pages/SupplierManagementPage.vue'),
  'tax-management': () => import('../pages/TaxManagementPage.vue'),
  transfers: () => import('../pages/StockTransferPage.vue'),
  users: () => import('../pages/UserRoleManagementPage.vue'),
}

const preloadedRoutes = new Set()
const preloadQueueByRole = {
  admin: ['dashboard', 'pos', 'reports', 'products', 'inventory', 'shifts', 'branches', 'users', 'payments', 'customers'],
  manager: ['dashboard', 'pos', 'inventory', 'shifts', 'reports', 'products', 'customers', 'returns', 'payments'],
  cashier: ['pos', 'shifts', 'customers', 'returns', 'dashboard'],
  auditor: ['dashboard', 'reports', 'audit-logs', 'inventory', 'accounting', 'bir-compliance'],
}

const routes = [
  {
    path: '/',
    redirect: '/dashboard',
  },
  {
    path: '/login',
    name: 'login',
    component: routeComponents.login,
    meta: {
      public: true,
    },
  },
  {
    path: '/dashboard',
    name: 'dashboard',
    component: routeComponents.dashboard,
    meta: {
      requiresAuth: true,
    },
  },
  {
    path: '/pos',
    name: 'pos',
    component: routeComponents.pos,
    meta: {
      requiresAuth: true,
      roles: ['admin', 'manager', 'cashier'],
    },
  },
  {
    path: '/branches',
    name: 'branches',
    component: routeComponents.branches,
    meta: {
      requiresAuth: true,
      roles: ['admin', 'manager', 'auditor'],
    },
  },
  {
    path: '/users',
    name: 'users',
    component: routeComponents.users,
    meta: {
      requiresAuth: true,
      roles: ['admin', 'manager', 'auditor'],
    },
  },
  {
    path: '/products',
    name: 'products',
    component: routeComponents.products,
    meta: {
      requiresAuth: true,
      roles: ['admin', 'manager', 'auditor'],
    },
  },
  {
    path: '/inventory',
    name: 'inventory',
    component: routeComponents.inventory,
    meta: {
      requiresAuth: true,
      roles: ['admin', 'manager', 'auditor'],
    },
  },
  {
    path: '/transfers',
    name: 'transfers',
    component: routeComponents.transfers,
    meta: {
      requiresAuth: true,
      roles: ['admin', 'manager', 'auditor'],
    },
  },
  {
    path: '/bir-compliance',
    name: 'bir-compliance',
    component: routeComponents['bir-compliance'],
    meta: {
      requiresAuth: true,
      roles: ['admin', 'manager', 'auditor'],
    },
  },
  {
    path: '/tax-management',
    name: 'tax-management',
    component: routeComponents['tax-management'],
    meta: {
      requiresAuth: true,
      roles: ['admin', 'manager', 'auditor'],
    },
  },
  {
    path: '/senior-pwd',
    name: 'senior-pwd',
    component: routeComponents['senior-pwd'],
    meta: {
      requiresAuth: true,
      roles: ['admin', 'manager', 'auditor'],
    },
  },
  {
    path: '/payments',
    name: 'payments',
    component: routeComponents.payments,
    meta: {
      requiresAuth: true,
      roles: ['admin', 'manager', 'auditor'],
    },
  },
  {
    path: '/shifts',
    name: 'shifts',
    component: routeComponents.shifts,
    meta: {
      requiresAuth: true,
      roles: ['admin', 'manager', 'cashier', 'auditor'],
    },
  },
  {
    path: '/returns',
    name: 'returns',
    component: routeComponents.returns,
    meta: {
      requiresAuth: true,
      roles: ['admin', 'manager', 'cashier', 'auditor'],
    },
  },
  {
    path: '/purchases',
    name: 'purchases',
    component: routeComponents.purchases,
    meta: {
      requiresAuth: true,
      roles: ['admin', 'manager', 'auditor'],
    },
  },
  {
    path: '/suppliers',
    name: 'suppliers',
    component: routeComponents.suppliers,
    meta: {
      requiresAuth: true,
      roles: ['admin', 'manager', 'auditor'],
    },
  },
  {
    path: '/customers',
    name: 'customers',
    component: routeComponents.customers,
    meta: {
      requiresAuth: true,
      roles: ['admin', 'manager', 'cashier', 'auditor'],
    },
  },
  {
    path: '/accounting',
    name: 'accounting',
    component: routeComponents.accounting,
    meta: {
      requiresAuth: true,
      roles: ['admin', 'manager', 'auditor'],
    },
  },
  {
    path: '/expenses',
    name: 'expenses',
    component: routeComponents.expenses,
    meta: {
      requiresAuth: true,
      roles: ['admin', 'manager', 'auditor'],
    },
  },
  {
    path: '/reports',
    name: 'reports',
    component: routeComponents.reports,
    meta: {
      requiresAuth: true,
      roles: ['admin', 'manager', 'auditor'],
    },
  },
  {
    path: '/audit-logs',
    name: 'audit-logs',
    component: routeComponents['audit-logs'],
    meta: {
      requiresAuth: true,
      roles: ['admin', 'manager', 'auditor'],
    },
  },
]

const router = createRouter({
  history: createWebHistory(),
  routes,
})

function scheduleIdleWork(callback) {
  if (typeof window === 'undefined') return

  const run = () => callback()
  if ('requestIdleCallback' in window) {
    window.requestIdleCallback(run, { timeout: 2500 })
    return
  }

  window.setTimeout(run, 700)
}

function preloadRoute(name) {
  const loader = routeComponents[name]
  if (!loader || preloadedRoutes.has(name)) return

  preloadedRoutes.add(name)
  loader().catch(() => {
    preloadedRoutes.delete(name)
  })
}

function preloadAllowedRoutes(role, currentName) {
  if (!role) return

  const prioritized = preloadQueueByRole[role] || ['dashboard']
  const allowedNames = routes
    .filter((route) => route.name && !route.meta?.public)
    .filter((route) => !Array.isArray(route.meta?.roles) || route.meta.roles.includes(role))
    .map((route) => route.name)

  const queue = [...prioritized, ...allowedNames].filter((name, index, list) => name !== currentName && list.indexOf(name) === index)
  queue.slice(0, 12).forEach((name, index) => {
    window.setTimeout(() => preloadRoute(name), 180 * index)
  })
}

router.beforeEach(async (to) => {
  const auth = useAuthStore()
  await auth.initAuth()

  if (to.meta.public) {
    if (auth.isAuthenticated.value && to.name === 'login') {
      return { name: 'dashboard' }
    }

    return true
  }

  if (!auth.state.session) {
    return {
      name: 'login',
      query: {
        redirect: to.fullPath,
      },
    }
  }

  if (!auth.state.profile?.is_active) {
    return {
      name: 'login',
      query: {
        redirect: to.fullPath,
        setup: 'profile',
      },
    }
  }

  const allowedRoles = to.meta.roles
  if (Array.isArray(allowedRoles) && !allowedRoles.includes(auth.state.profile.role)) {
    return { name: 'dashboard' }
  }

  return true
})

router.afterEach((to) => {
  const auth = useAuthStore()
  if (!auth.state.session || to.meta.public) return

  scheduleIdleWork(() => {
    preloadAllowedRoutes(auth.state.profile?.role, to.name)
  })
})

export default router
