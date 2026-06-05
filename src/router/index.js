import { createRouter, createWebHistory } from 'vue-router'
import AccountingPage from '../pages/AccountingPage.vue'
import AuditLogsPage from '../pages/AuditLogsPage.vue'
import BirCompliancePage from '../pages/BirCompliancePage.vue'
import DashboardPage from '../pages/DashboardPage.vue'
import BranchManagementPage from '../pages/BranchManagementPage.vue'
import CustomerManagementPage from '../pages/CustomerManagementPage.vue'
import ExpenseManagementPage from '../pages/ExpenseManagementPage.vue'
import InventoryManagementPage from '../pages/InventoryManagementPage.vue'
import LoginPage from '../pages/LoginPage.vue'
import PaymentManagementPage from '../pages/PaymentManagementPage.vue'
import PosCheckoutPage from '../pages/PosCheckoutPage.vue'
import ProductManagementPage from '../pages/ProductManagementPage.vue'
import PurchaseManagementPage from '../pages/PurchaseManagementPage.vue'
import ReportsPage from '../pages/ReportsPage.vue'
import ReturnsManagementPage from '../pages/ReturnsManagementPage.vue'
import SeniorPwdDiscountPage from '../pages/SeniorPwdDiscountPage.vue'
import ShiftManagementPage from '../pages/ShiftManagementPage.vue'
import StockTransferPage from '../pages/StockTransferPage.vue'
import SupplierManagementPage from '../pages/SupplierManagementPage.vue'
import TaxManagementPage from '../pages/TaxManagementPage.vue'
import UserRoleManagementPage from '../pages/UserRoleManagementPage.vue'
import { useAuthStore } from '../stores/authStore'

const routes = [
  {
    path: '/',
    redirect: '/dashboard',
  },
  {
    path: '/login',
    name: 'login',
    component: LoginPage,
    meta: {
      public: true,
    },
  },
  {
    path: '/dashboard',
    name: 'dashboard',
    component: DashboardPage,
    meta: {
      requiresAuth: true,
    },
  },
  {
    path: '/pos',
    name: 'pos',
    component: PosCheckoutPage,
    meta: {
      requiresAuth: true,
      roles: ['admin', 'manager', 'cashier'],
    },
  },
  {
    path: '/branches',
    name: 'branches',
    component: BranchManagementPage,
    meta: {
      requiresAuth: true,
      roles: ['admin', 'manager', 'auditor'],
    },
  },
  {
    path: '/users',
    name: 'users',
    component: UserRoleManagementPage,
    meta: {
      requiresAuth: true,
      roles: ['admin', 'manager', 'auditor'],
    },
  },
  {
    path: '/products',
    name: 'products',
    component: ProductManagementPage,
    meta: {
      requiresAuth: true,
      roles: ['admin', 'manager', 'auditor'],
    },
  },
  {
    path: '/inventory',
    name: 'inventory',
    component: InventoryManagementPage,
    meta: {
      requiresAuth: true,
      roles: ['admin', 'manager', 'auditor'],
    },
  },
  {
    path: '/transfers',
    name: 'transfers',
    component: StockTransferPage,
    meta: {
      requiresAuth: true,
      roles: ['admin', 'manager', 'auditor'],
    },
  },
  {
    path: '/bir-compliance',
    name: 'bir-compliance',
    component: BirCompliancePage,
    meta: {
      requiresAuth: true,
      roles: ['admin', 'manager', 'auditor'],
    },
  },
  {
    path: '/tax-management',
    name: 'tax-management',
    component: TaxManagementPage,
    meta: {
      requiresAuth: true,
      roles: ['admin', 'manager', 'auditor'],
    },
  },
  {
    path: '/senior-pwd',
    name: 'senior-pwd',
    component: SeniorPwdDiscountPage,
    meta: {
      requiresAuth: true,
      roles: ['admin', 'manager', 'auditor'],
    },
  },
  {
    path: '/payments',
    name: 'payments',
    component: PaymentManagementPage,
    meta: {
      requiresAuth: true,
      roles: ['admin', 'manager', 'auditor'],
    },
  },
  {
    path: '/shifts',
    name: 'shifts',
    component: ShiftManagementPage,
    meta: {
      requiresAuth: true,
      roles: ['admin', 'manager', 'cashier', 'auditor'],
    },
  },
  {
    path: '/returns',
    name: 'returns',
    component: ReturnsManagementPage,
    meta: {
      requiresAuth: true,
      roles: ['admin', 'manager', 'cashier', 'auditor'],
    },
  },
  {
    path: '/purchases',
    name: 'purchases',
    component: PurchaseManagementPage,
    meta: {
      requiresAuth: true,
      roles: ['admin', 'manager', 'auditor'],
    },
  },
  {
    path: '/suppliers',
    name: 'suppliers',
    component: SupplierManagementPage,
    meta: {
      requiresAuth: true,
      roles: ['admin', 'manager', 'auditor'],
    },
  },
  {
    path: '/customers',
    name: 'customers',
    component: CustomerManagementPage,
    meta: {
      requiresAuth: true,
      roles: ['admin', 'manager', 'cashier', 'auditor'],
    },
  },
  {
    path: '/accounting',
    name: 'accounting',
    component: AccountingPage,
    meta: {
      requiresAuth: true,
      roles: ['admin', 'manager', 'auditor'],
    },
  },
  {
    path: '/expenses',
    name: 'expenses',
    component: ExpenseManagementPage,
    meta: {
      requiresAuth: true,
      roles: ['admin', 'manager', 'auditor'],
    },
  },
  {
    path: '/reports',
    name: 'reports',
    component: ReportsPage,
    meta: {
      requiresAuth: true,
      roles: ['admin', 'manager', 'auditor'],
    },
  },
  {
    path: '/audit-logs',
    name: 'audit-logs',
    component: AuditLogsPage,
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

export default router
