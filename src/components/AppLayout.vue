<template>
  <main class="app-layout" :class="{ 'app-layout--menu-open': menuOpen }">
    <aside class="app-sidebar" aria-label="Primary navigation">
      <div class="sidebar-brand-row">
        <RouterLink class="brand-lockup" to="/dashboard" @click="closeMenu">
          <span class="brand-mark">POS</span>
          <span>
            <small>Multi-Branch POS</small>
            <strong>RetailLedger</strong>
          </span>
        </RouterLink>

        <PButton icon="pi pi-times" text rounded class="sidebar-close" aria-label="Close menu" @click="closeMenu" />
      </div>

      <nav class="sidebar-nav">
        <section v-for="group in visibleNavGroups" :key="group.label" class="sidebar-nav__section">
          <span class="sidebar-nav__section-label">{{ group.label }}</span>
          <RouterLink
            v-for="item in group.items"
            :key="item.to"
            :to="item.to"
            class="sidebar-nav__link"
            @click="closeMenu"
          >
            <i :class="item.icon" />
            <span>{{ item.label }}</span>
          </RouterLink>
        </section>
      </nav>

      <div class="sidebar-user">
        <div>
          <strong>{{ profileName }}</strong>
          <small>{{ usernameLabel }} - {{ roleLabel }}</small>
        </div>
        <PButton icon="pi pi-sign-out" text rounded aria-label="Sign out" @click="signOut" />
      </div>
    </aside>

    <button class="sidebar-backdrop" type="button" aria-label="Close menu" @click="closeMenu" />

    <section class="app-content">
      <header class="content-topbar">
        <div class="content-topbar__left">
          <PButton icon="pi pi-bars" text rounded class="menu-toggle" aria-label="Open menu" @click="openMenu" />
          <div>
            <small>{{ roleLabel }}</small>
            <strong>{{ activePageLabel }}</strong>
          </div>
        </div>

        <div class="content-user-chip">
          <span>
            <strong>{{ profileName }}</strong>
            <small>{{ usernameLabel }}</small>
          </span>
          <PButton icon="pi pi-sign-out" text rounded aria-label="Sign out" @click="signOut" />
        </div>
      </header>

      <div class="app-content__body">
        <slot />
      </div>
    </section>
  </main>
</template>

<script setup>
import { computed, ref, watch } from 'vue'
import { RouterLink, useRoute, useRouter } from 'vue-router'
import { useAuthStore } from '../stores/authStore'

const router = useRouter()
const route = useRoute()
const auth = useAuthStore()
const menuOpen = ref(false)

const navGroups = [
  {
    label: 'Home',
    items: [
      { label: 'Dashboard', to: '/dashboard', icon: 'pi pi-chart-bar', roles: ['admin', 'manager', 'cashier', 'auditor'] },
    ],
  },
  {
    label: 'Sales',
    items: [
      { label: 'POS', to: '/pos', icon: 'pi pi-shopping-cart', roles: ['admin', 'manager', 'cashier'] },
      { label: 'Customers', to: '/customers', icon: 'pi pi-id-card', roles: ['admin', 'manager', 'cashier', 'auditor'] },
      { label: 'Returns', to: '/returns', icon: 'pi pi-undo', roles: ['admin', 'manager', 'cashier', 'auditor'] },
      { label: 'Payments', to: '/payments', icon: 'pi pi-credit-card', roles: ['admin', 'manager', 'auditor'] },
    ],
  },
  {
    label: 'Operations',
    items: [
      { label: 'Shifts', to: '/shifts', icon: 'pi pi-clock', roles: ['admin', 'manager', 'cashier', 'auditor'] },
      { label: 'Products', to: '/products', icon: 'pi pi-box', roles: ['admin', 'manager', 'auditor'] },
      { label: 'Inventory', to: '/inventory', icon: 'pi pi-warehouse', roles: ['admin', 'manager', 'auditor'] },
      { label: 'Transfers', to: '/transfers', icon: 'pi pi-send', roles: ['admin', 'manager', 'auditor'] },
    ],
  },
  {
    label: 'Purchasing',
    items: [
      { label: 'Purchases', to: '/purchases', icon: 'pi pi-shopping-bag', roles: ['admin', 'manager', 'auditor'] },
      { label: 'Suppliers', to: '/suppliers', icon: 'pi pi-address-book', roles: ['admin', 'manager', 'auditor'] },
    ],
  },
  {
    label: 'Finance',
    items: [
      { label: 'Reports', to: '/reports', icon: 'pi pi-chart-bar', roles: ['admin', 'manager', 'auditor'] },
      { label: 'Accounting', to: '/accounting', icon: 'pi pi-book', roles: ['admin', 'manager', 'auditor'] },
      { label: 'Expenses', to: '/expenses', icon: 'pi pi-wallet', roles: ['admin', 'manager', 'auditor'] },
      { label: 'Tax', to: '/tax-management', icon: 'pi pi-percentage', roles: ['admin', 'manager', 'auditor'] },
      { label: 'Senior/PWD', to: '/senior-pwd', icon: 'pi pi-id-card', roles: ['admin', 'manager', 'auditor'] },
      { label: 'BIR', to: '/bir-compliance', icon: 'pi pi-receipt', roles: ['admin', 'manager', 'auditor'] },
    ],
  },
  {
    label: 'Company',
    items: [
      { label: 'Branches', to: '/branches', icon: 'pi pi-building', roles: ['admin', 'manager', 'auditor'] },
      { label: 'Users', to: '/users', icon: 'pi pi-users', roles: ['admin', 'manager', 'auditor'] },
      { label: 'Audit Logs', to: '/audit-logs', icon: 'pi pi-history', roles: ['admin', 'manager', 'auditor'] },
    ],
  },
]

const profileName = computed(() => auth.state.profile?.full_name || 'Signed in')
const usernameLabel = computed(() => (auth.state.profile?.username ? `@${auth.state.profile.username}` : 'staff'))
const roleLabel = computed(() => (auth.state.profile?.role || 'user').replace('_', ' '))
const visibleNavGroups = computed(() => {
  const role = auth.state.profile?.role
  return navGroups
    .map((group) => ({
      ...group,
      items: group.items.filter((item) => item.roles.includes(role)),
    }))
    .filter((group) => group.items.length)
})
const visibleNavItems = computed(() => visibleNavGroups.value.flatMap((group) => group.items))
const activePageLabel = computed(() => {
  const active = visibleNavItems.value.find((item) => route.path === item.to || route.path.startsWith(`${item.to}/`))
  return active?.label || 'Dashboard'
})

watch(
  () => route.fullPath,
  () => {
    closeMenu()
  },
)

function openMenu() {
  menuOpen.value = true
}

function closeMenu() {
  menuOpen.value = false
}

async function signOut() {
  await auth.signOut()
  closeMenu()
  await router.push('/login')
}
</script>
