<template>
  <section class="page-stack">
    <section class="page-hero page-hero--compact">
      <div>
        <p class="eyebrow">Module 3</p>
        <h1>User & Role Management</h1>
        <p>
          Create staff with username and password, assign roles, control branch
          access, set shift permissions, and review admin activity.
        </p>
      </div>

      <div class="action-panel">
        <PButton icon="pi pi-user-plus" label="Add staff" :disabled="!auth.isAdmin.value" @click="openCreate" />
        <PButton icon="pi pi-refresh" label="Refresh" outlined :loading="loading" @click="loadUsers" />
      </div>
    </section>

    <PMessage v-if="!auth.isAdmin.value" severity="warn" :closable="false" class="setup-message">
      You can view users with this role. Creating, editing, and deleting users is admin-only.
    </PMessage>

    <PMessage v-if="error" severity="error" :closable="false" class="setup-message">
      {{ error }}
    </PMessage>

    <PMessage v-if="successMessage" severity="success" :closable="false" class="setup-message">
      {{ successMessage }}
    </PMessage>

    <section v-if="loading && !userData" class="stats-grid">
      <PSkeleton v-for="item in 5" :key="item" height="8rem" border-radius="8px" />
    </section>

    <template v-else-if="userData">
      <section class="stats-grid">
        <MetricCard label="Total users" :value="formatNumber(userData.summary.total_users)" icon="pi pi-users" />
        <MetricCard label="Active users" :value="formatNumber(userData.summary.active_users)" icon="pi pi-check-circle" tone="blue" />
        <MetricCard label="Admins" :value="formatNumber(userData.summary.admins)" icon="pi pi-shield" tone="purple" />
        <MetricCard label="Managers" :value="formatNumber(userData.summary.managers)" icon="pi pi-briefcase" tone="gold" />
        <MetricCard label="Cashiers" :value="formatNumber(userData.summary.cashiers)" icon="pi pi-id-card" tone="green" />
      </section>

      <section class="panel">
        <div class="table-toolbar">
          <div>
            <p class="eyebrow">Staff directory</p>
            <h2>Users and permissions</h2>
          </div>
          <span class="search-field">
            <i class="pi pi-search" />
            <PInputText v-model.trim="search" placeholder="Search name, username, role, branch" />
          </span>
        </div>

        <PDataTable
          :value="filteredUsers"
          data-key="id"
          responsive-layout="stack"
          breakpoint="900px"
          size="small"
          striped-rows
          paginator
          :rows="8"
        >
          <PColumn field="full_name" header="User">
            <template #body="{ data }">
              <div class="branch-cell">
                <strong>{{ data.full_name }}</strong>
                <small>@{{ data.username }}</small>
              </div>
            </template>
          </PColumn>
          <PColumn field="role" header="Role">
            <template #body="{ data }">
              <PTag :value="roleLabel(data.role)" :severity="roleSeverity(data.role)" />
            </template>
          </PColumn>
          <PColumn field="branch_name" header="Branch">
            <template #body="{ data }">{{ data.can_access_all_branches ? 'All branches' : data.branch_name || '-' }}</template>
          </PColumn>
          <PColumn field="permissions" header="Permissions">
            <template #body="{ data }">
              {{ formatNumber(data.permissions.length) }}
              <small class="muted-block">Max discount {{ data.max_discount_percent }}%</small>
            </template>
          </PColumn>
          <PColumn field="shift_start" header="Shift">
            <template #body="{ data }">
              {{ shortTime(data.shift_start) }}-{{ shortTime(data.shift_end) }}
              <small class="muted-block">{{ data.shift_days.length }} days</small>
            </template>
          </PColumn>
          <PColumn field="is_active" header="Status">
            <template #body="{ data }">
              <PTag :value="data.is_active ? 'Active' : 'Inactive'" :severity="data.is_active ? 'success' : 'danger'" />
            </template>
          </PColumn>
          <PColumn header="Actions">
            <template #body="{ data }">
              <div class="table-actions">
                <PButton
                  icon="pi pi-pencil"
                  text
                  rounded
                  aria-label="Edit user"
                  :disabled="!auth.isAdmin.value"
                  @click="openEdit(data)"
                />
                <PButton
                  icon="pi pi-trash"
                  text
                  rounded
                  severity="danger"
                  aria-label="Permanently delete user"
                  :disabled="!auth.isAdmin.value || data.id === auth.state.profile?.id"
                  @click="hardDeleteUser(data)"
                />
              </div>
            </template>
          </PColumn>
        </PDataTable>
      </section>

      <section class="panel">
        <div class="panel__header">
          <div>
            <p class="eyebrow">Activity logs</p>
            <h2>Recent security actions</h2>
          </div>
        </div>

        <div v-if="userData.activity_logs.length" class="activity-list">
          <article v-for="log in userData.activity_logs" :key="log.id">
            <i class="pi pi-history" />
            <div>
              <strong>{{ actionLabel(log.action) }}</strong>
              <small>{{ actorLabel(log) }} - {{ formatDateTime(log.created_at) }}</small>
            </div>
          </article>
        </div>

        <div v-else class="empty-state empty-state--small">
          <i class="pi pi-history" />
          <p>No activity logs yet.</p>
        </div>
      </section>
    </template>

    <PDialog
      v-model:visible="createVisible"
      modal
      header="Add staff"
      class="branch-dialog"
      :style="{ width: 'min(940px, 96vw)' }"
    >
      <form class="branch-form" @submit.prevent="saveCreate">
        <PMessage v-if="formError" severity="error" :closable="false" class="dialog-message">
          {{ formError }}
        </PMessage>
        <StaffFormFields
          :model-value="form"
          :branches="userData?.branches || []"
          :permissions="userData?.permission_catalog || []"
          mode="create"
          :errors="formErrors"
          @update:model-value="patchForm"
          @field-change="clearFieldError"
        />
        <div class="dialog-actions">
          <PButton type="button" label="Cancel" severity="secondary" outlined @click="createVisible = false" />
          <PButton type="submit" icon="pi pi-save" label="Create staff" :loading="saving" />
        </div>
      </form>
    </PDialog>

    <PDialog
      v-model:visible="editVisible"
      modal
      header="Edit user access"
      class="branch-dialog"
      :style="{ width: 'min(940px, 96vw)' }"
    >
      <form class="branch-form" @submit.prevent="saveUser">
        <PMessage v-if="formError" severity="error" :closable="false" class="dialog-message">
          {{ formError }}
        </PMessage>
        <StaffFormFields
          :model-value="form"
          :branches="userData?.branches || []"
          :permissions="userData?.permission_catalog || []"
          mode="edit"
          :errors="formErrors"
          @update:model-value="patchForm"
          @field-change="clearFieldError"
        />
        <div class="dialog-actions">
          <PButton type="button" label="Cancel" severity="secondary" outlined @click="editVisible = false" />
          <PButton type="submit" icon="pi pi-save" label="Save user" :loading="saving" />
        </div>
      </form>
    </PDialog>
  </section>
</template>

<script setup>
import { computed, onMounted, reactive, ref, watch } from 'vue'
import MetricCard from '../components/MetricCard.vue'
import StaffFormFields from '../components/StaffFormFields.vue'
import { formatNumber } from '../lib/formatters'
import {
  createStaffDirect,
  fetchUserManagement,
  hardDeleteStaffUser,
  updateStaffUser,
} from '../services/userService'
import { useAuthStore } from '../stores/authStore'

const roleOptions = [
  { label: 'Admin', value: 'admin' },
  { label: 'Manager', value: 'manager' },
  { label: 'Cashier', value: 'cashier' },
  { label: 'Auditor', value: 'auditor' },
]

const defaultPermissionsByRole = {
  admin: [
    'dashboard.view',
    'branches.view',
    'branches.manage',
    'users.view',
    'users.manage',
    'products.view',
    'products.manage',
    'inventory.view',
    'inventory.manage',
    'inventory.count',
    'transfers.view',
    'transfers.manage',
    'bir.view',
    'bir.manage',
    'tax.view',
    'tax.manage',
    'senior_pwd.view',
    'senior_pwd.manage',
    'senior_pwd.apply',
    'payments.view',
    'payments.manage',
    'payments.settle',
    'shifts.view',
    'shifts.manage',
    'returns.view',
    'returns.manage',
    'returns.approve',
    'purchases.view',
    'purchases.manage',
    'purchases.approve',
    'purchases.receive',
    'suppliers.view',
    'suppliers.manage',
    'suppliers.pay',
    'customers.view',
    'customers.manage',
    'customers.credit',
    'customers.loyalty',
    'activity.view',
    'pos.sell',
    'pos.discount',
    'pos.void',
    'reports.view',
  ],
  manager: [
    'dashboard.view',
    'branches.view',
    'users.view',
    'products.view',
    'inventory.view',
    'inventory.manage',
    'inventory.count',
    'transfers.view',
    'transfers.manage',
    'bir.view',
    'bir.manage',
    'tax.view',
    'senior_pwd.view',
    'senior_pwd.apply',
    'payments.view',
    'payments.settle',
    'shifts.view',
    'shifts.manage',
    'returns.view',
    'returns.manage',
    'returns.approve',
    'purchases.view',
    'purchases.manage',
    'purchases.approve',
    'purchases.receive',
    'suppliers.view',
    'suppliers.manage',
    'suppliers.pay',
    'customers.view',
    'customers.manage',
    'customers.credit',
    'customers.loyalty',
    'pos.sell',
    'pos.discount',
    'reports.view',
  ],
  cashier: ['dashboard.view', 'products.view', 'customers.view', 'pos.sell', 'senior_pwd.apply', 'shifts.view', 'returns.view', 'returns.manage'],
  auditor: [
    'dashboard.view',
    'branches.view',
    'users.view',
    'products.view',
    'inventory.view',
    'transfers.view',
    'bir.view',
    'tax.view',
    'senior_pwd.view',
    'payments.view',
    'shifts.view',
    'returns.view',
    'purchases.view',
    'suppliers.view',
    'customers.view',
    'activity.view',
    'reports.view',
  ],
}

const auth = useAuthStore()
const loading = ref(false)
const saving = ref(false)
const error = ref('')
const successMessage = ref('')
const formError = ref('')
const userData = ref(null)
const search = ref('')
const createVisible = ref(false)
const editVisible = ref(false)
const editingUser = ref(null)

const form = reactive(createDefaultForm())
const formErrors = reactive({})

const filteredUsers = computed(() => {
  const query = search.value.toLowerCase()
  const rows = userData.value?.users || []

  if (!query) return rows

  return rows.filter((user) =>
    [user.full_name, user.username, user.role, user.branch_name, user.job_title]
      .filter(Boolean)
      .some((value) => value.toLowerCase().includes(query)),
  )
})

watch(
  () => form.role,
  (role) => {
    if (!editingUser.value) {
      form.permissions = [...(defaultPermissionsByRole[role] || defaultPermissionsByRole.cashier)]
      form.can_access_all_branches = role === 'admin' || role === 'auditor'
      form.can_close_shift = role === 'admin' || role === 'manager'
      form.max_discount_percent = role === 'admin' ? 100 : role === 'manager' ? 20 : role === 'cashier' ? 5 : 0
    }
  },
)

function createDefaultForm() {
  return {
    full_name: '',
    username: '',
    password: '',
    phone: '',
    job_title: '',
    role: 'cashier',
    branch_id: null,
    can_access_all_branches: false,
    allowed_branch_ids: [],
    permissions: [...defaultPermissionsByRole.cashier],
    shift_days: [1, 2, 3, 4, 5, 6, 7],
    shift_start: '00:00',
    shift_end: '23:59',
    max_discount_percent: 5,
    can_open_shift: true,
    can_close_shift: false,
    is_active: true,
  }
}

function resetForm(payload = {}) {
  Object.assign(form, createDefaultForm(), payload)
}

function patchForm(nextForm) {
  Object.assign(form, nextForm)
}

function clearFormFeedback() {
  formError.value = ''
  Object.keys(formErrors).forEach((key) => {
    delete formErrors[key]
  })
}

function setFormErrors(errors) {
  clearFormFeedback()
  Object.assign(formErrors, errors)
  formError.value = 'Please fix the highlighted fields in this form.'
}

function clearFieldError(key) {
  if (formErrors[key]) {
    delete formErrors[key]
  }

  if (key === 'role' && formErrors.branch_id) {
    delete formErrors.branch_id
  }

  if (Object.keys(formErrors).length === 0) {
    formError.value = ''
  }
}

function validateStaffPayload({ requirePassword = false } = {}) {
  const username = form.username?.trim().toLowerCase()
  const errors = {}

  if (!form.full_name?.trim()) {
    errors.full_name = 'Full name is required.'
  }

  if (!username) {
    errors.username = 'Username is required.'
  } else if (!/^[a-z0-9][a-z0-9._-]{2,31}$/.test(username)) {
    errors.username = 'Use 3-32 lowercase letters, numbers, dot, underscore, or dash.'
  }

  if (requirePassword && !form.password?.trim()) {
    errors.password = 'Password is required.'
  } else if (requirePassword && form.password.trim().length < 6) {
    errors.password = 'Password must be at least 6 characters.'
  }

  if ((form.role === 'manager' || form.role === 'cashier') && !form.branch_id) {
    errors.branch_id = 'Branch is required for manager and cashier roles.'
  }

  if (Object.keys(errors).length > 0) {
    setFormErrors(errors)
    return false
  }

  clearFormFeedback()
  return true
}

function userToForm(user) {
  return {
    full_name: user.full_name,
    username: user.username,
    password: '',
    phone: user.phone || '',
    job_title: user.job_title || '',
    role: user.role,
    branch_id: user.branch_id,
    can_access_all_branches: Boolean(user.can_access_all_branches),
    allowed_branch_ids: [...(user.allowed_branch_ids || [])],
    permissions: [...(user.permissions || [])],
    shift_days: [...(user.shift_days || [])],
    shift_start: shortTime(user.shift_start),
    shift_end: shortTime(user.shift_end),
    max_discount_percent: Number(user.max_discount_percent || 0),
    can_open_shift: Boolean(user.can_open_shift),
    can_close_shift: Boolean(user.can_close_shift),
    is_active: Boolean(user.is_active),
  }
}

async function loadUsers() {
  loading.value = true
  error.value = ''
  successMessage.value = ''

  try {
    userData.value = await fetchUserManagement()
  } catch (loadError) {
    error.value = loadError.message
  } finally {
    loading.value = false
  }
}

function openCreate() {
  editingUser.value = null
  resetForm()
  clearFormFeedback()
  createVisible.value = true
}

function openEdit(user) {
  editingUser.value = user
  resetForm(userToForm(user))
  clearFormFeedback()
  editVisible.value = true
}

async function saveCreate() {
  saving.value = true
  error.value = ''
  successMessage.value = ''
  clearFormFeedback()

  try {
    const isValid = validateStaffPayload({ requirePassword: true })
    if (!isValid) {
      return
    }

    form.username = form.username.trim().toLowerCase()
    const result = await createStaffDirect({ ...form })
    userData.value = result
    successMessage.value = result.direct_staff_created
      ? `@${result.direct_staff_username} was created and can log in now.`
      : `@${result.direct_staff_username} already existed, so the password and access were updated.`
    createVisible.value = false
  } catch (saveError) {
    formError.value = saveError.message
  } finally {
    saving.value = false
  }
}

async function saveUser() {
  if (!editingUser.value) return

  saving.value = true
  error.value = ''
  clearFormFeedback()

  try {
    const isValid = validateStaffPayload()
    if (!isValid) {
      return
    }

    form.username = form.username.trim().toLowerCase()
    userData.value = await updateStaffUser(editingUser.value.id, { ...form })
    editVisible.value = false
  } catch (saveError) {
    formError.value = saveError.message
  } finally {
    saving.value = false
  }
}

async function hardDeleteUser(user) {
  const confirmed = window.confirm(`Permanently delete @${user.username}? This removes the staff Auth account and database profile.`)
  if (!confirmed) return

  loading.value = true
  error.value = ''

  try {
    userData.value = await hardDeleteStaffUser(user.id)
    successMessage.value = `@${user.username} was permanently deleted.`
  } catch (deleteError) {
    error.value = deleteError.message
  } finally {
    loading.value = false
  }
}

function roleLabel(role) {
  return roleOptions.find((option) => option.value === role)?.label || role
}

function roleSeverity(role) {
  if (role === 'admin') return 'danger'
  if (role === 'manager') return 'warn'
  if (role === 'auditor') return 'info'

  return 'success'
}

function shortTime(value) {
  return value ? value.toString().slice(0, 5) : '00:00'
}

function formatDateTime(value) {
  if (!value) return '-'

  return new Intl.DateTimeFormat('en-PH', {
    month: 'short',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  }).format(new Date(value))
}

function actionLabel(action) {
  return action.replaceAll('.', ' ').replace(/\b\w/g, (letter) => letter.toUpperCase())
}

function actorLabel(log) {
  if (log.actor_name) return log.actor_name
  if (log.actor_username) return `@${log.actor_username}`

  return 'System'
}

onMounted(loadUsers)
</script>
