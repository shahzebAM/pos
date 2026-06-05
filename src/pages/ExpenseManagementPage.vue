<template>
  <section class="page-stack">
    <section class="page-hero">
      <div>
        <p class="eyebrow">Module 17</p>
        <h2>Branch expenses, categories, approvals, and paid tracking.</h2>
        <p>
          Record rent, utilities, salaries, supplies, repairs, and other branch expenses,
          then approve, reject, mark paid, or void entries with branch-scoped reporting.
        </p>
      </div>

      <form class="filter-panel" @submit.prevent="loadExpenses">
        <label>
          From
          <PDatePicker v-model="filters.from" date-format="yy-mm-dd" show-icon fluid />
        </label>
        <label>
          To
          <PDatePicker v-model="filters.to" date-format="yy-mm-dd" show-icon fluid />
        </label>
        <label>
          Branch
          <PSelect
            v-model="filters.branchId"
            :options="branchFilterOptions"
            option-label="name"
            option-value="id"
            placeholder="All branches"
            :disabled="isBranchLocked"
            fluid
          />
        </label>
        <label>
          Search
          <PInputText v-model.trim="filters.search" placeholder="Expense, category, payee, reference" fluid />
        </label>
        <div class="dialog-actions">
          <PButton type="submit" icon="pi pi-refresh" label="Refresh" :loading="loading" />
          <PButton type="button" icon="pi pi-plus" label="Expense" :disabled="!canManageExpenses" @click="openExpense()" />
          <PButton type="button" icon="pi pi-tags" label="Category" outlined :disabled="!canManageCategories" @click="openCategory()" />
        </div>
      </form>
    </section>

    <PMessage v-if="error" severity="error" :closable="false" class="setup-message">
      {{ error }}
    </PMessage>

    <PMessage v-if="successMessage" severity="success" :closable="false" class="setup-message">
      {{ successMessage }}
    </PMessage>

    <section v-if="loading && !expenseData" class="stats-grid">
      <PSkeleton v-for="item in 6" :key="item" height="8rem" border-radius="8px" />
    </section>

    <template v-else-if="expenseData">
      <section class="stats-grid">
        <MetricCard label="Total expenses" :value="formatCurrency(expenseData.summary.total_expenses)" :caption="periodLabel" icon="pi pi-wallet" />
        <MetricCard label="Paid" :value="formatCurrency(expenseData.summary.paid_expenses)" icon="pi pi-check-circle" tone="green" />
        <MetricCard label="Pending" :value="formatNumber(expenseData.summary.pending_approval)" icon="pi pi-clock" tone="gold" />
        <MetricCard label="Drafts" :value="formatNumber(expenseData.summary.draft_expenses)" icon="pi pi-file-edit" tone="blue" />
        <MetricCard label="Rejected" :value="formatNumber(expenseData.summary.rejected_expenses)" icon="pi pi-times-circle" tone="red" />
        <MetricCard label="Categories" :value="formatNumber(expenseData.summary.category_count)" icon="pi pi-tags" tone="purple" />
      </section>

      <section class="analytics-grid">
        <BarChart
          title="Daily expense trend"
          eyebrow="Expense analytics"
          :rows="expenseData.daily_expenses"
          key-field="business_date"
          label-field="label"
          value-field="total_amount"
          caption="Approved and paid expenses"
        />
        <BarChart
          title="Expenses by category"
          eyebrow="Category mix"
          :rows="expenseData.category_summary"
          key-field="category_id"
          label-field="category_name"
          value-field="total_amount"
          caption="Approved and paid expenses"
        />
      </section>

      <section class="panel">
        <div class="table-toolbar product-toolbar">
          <div>
            <p class="eyebrow">Expense register</p>
            <h2>Branch expenses and approval status</h2>
          </div>
          <span class="search-field">
            <i class="pi pi-search" />
            <PInputText v-model.trim="expenseSearch" placeholder="Search expenses" />
          </span>
        </div>

        <PDataTable
          :value="filteredExpenses"
          data-key="id"
          responsive-layout="stack"
          breakpoint="920px"
          size="small"
          striped-rows
          paginator
          :rows="10"
        >
          <PColumn field="expense_number" header="Expense">
            <template #body="{ data }">
              <div class="branch-cell">
                <strong>{{ data.expense_number }}</strong>
                <small>{{ formatDate(data.expense_date) }} - {{ data.description }}</small>
              </div>
            </template>
          </PColumn>
          <PColumn field="category_name" header="Category">
            <template #body="{ data }">
              {{ data.category_name }}
              <small class="muted-block">{{ data.category_code }}</small>
            </template>
          </PColumn>
          <PColumn field="branch_name" header="Branch">
            <template #body="{ data }">{{ data.branch_code }} - {{ data.branch_name }}</template>
          </PColumn>
          <PColumn field="payee" header="Payee">
            <template #body="{ data }">
              {{ data.payee || '-' }}
              <small class="muted-block">{{ methodLabel(data.payment_method) }}</small>
            </template>
          </PColumn>
          <PColumn field="total_amount" header="Amount">
            <template #body="{ data }">
              {{ formatCurrency(data.total_amount) }}
              <small class="muted-block">Tax {{ formatCurrency(data.tax_amount) }}</small>
            </template>
          </PColumn>
          <PColumn field="status" header="Status">
            <template #body="{ data }">
              <PTag :value="statusLabel(data.status)" :severity="statusSeverity(data.status)" />
              <small v-if="data.requested_by_name" class="muted-block">By {{ data.requested_by_name }}</small>
            </template>
          </PColumn>
          <PColumn header="Actions">
            <template #body="{ data }">
              <div class="table-actions">
                <PButton icon="pi pi-pencil" text rounded aria-label="Edit expense" :disabled="!canEditExpense(data)" @click="openExpense(data)" />
                <PButton icon="pi pi-send" text rounded aria-label="Submit expense" :disabled="!canSubmitExpense(data)" @click="changeExpenseStatus(data, 'submitted')" />
                <PButton icon="pi pi-check" text rounded aria-label="Approve expense" :disabled="!canApproveExpense(data)" @click="changeExpenseStatus(data, 'approved')" />
                <PButton icon="pi pi-credit-card" text rounded aria-label="Mark paid" :disabled="!canPayExpense(data)" @click="changeExpenseStatus(data, 'paid')" />
                <PButton icon="pi pi-times" text rounded severity="danger" aria-label="Reject expense" :disabled="!canRejectExpense(data)" @click="openReasonDialog(data, 'rejected')" />
                <PButton icon="pi pi-ban" text rounded severity="danger" aria-label="Void expense" :disabled="!canVoidExpense(data)" @click="openReasonDialog(data, 'voided')" />
              </div>
            </template>
          </PColumn>
        </PDataTable>
      </section>

      <section class="analytics-grid">
        <section class="panel">
          <div class="table-toolbar product-toolbar">
            <div>
              <p class="eyebrow">Expense categories</p>
              <h2>Rent, utilities, salaries, and more</h2>
            </div>
            <span class="search-field">
              <i class="pi pi-search" />
              <PInputText v-model.trim="categorySearch" placeholder="Search categories" />
            </span>
          </div>

          <PDataTable
            :value="filteredCategories"
            data-key="id"
            responsive-layout="stack"
            breakpoint="820px"
            size="small"
            striped-rows
            paginator
            :rows="8"
          >
            <PColumn field="name" header="Category">
              <template #body="{ data }">
                <div class="branch-cell">
                  <strong>{{ data.name }}</strong>
                  <small>{{ data.category_code }} - Sort {{ formatNumber(data.sort_order) }}</small>
                </div>
              </template>
            </PColumn>
            <PColumn field="total_amount" header="Period amount">
              <template #body="{ data }">
                {{ formatCurrency(data.total_amount) }}
                <small class="muted-block">{{ formatNumber(data.expense_count) }} entry(s)</small>
              </template>
            </PColumn>
            <PColumn field="is_active" header="Status">
              <template #body="{ data }">
                <PTag :value="data.is_active ? 'Active' : 'Inactive'" :severity="data.is_active ? 'success' : 'danger'" />
              </template>
            </PColumn>
            <PColumn header="Actions">
              <template #body="{ data }">
                <PButton icon="pi pi-pencil" text rounded aria-label="Edit category" :disabled="!canManageCategories" @click="openCategory(data)" />
              </template>
            </PColumn>
          </PDataTable>
        </section>

        <section class="panel">
          <div class="panel__header">
            <div>
              <p class="eyebrow">Branch summary</p>
              <h2>Expense performance by branch</h2>
            </div>
          </div>

          <PDataTable
            :value="expenseData.branch_summary"
            data-key="branch_id"
            responsive-layout="stack"
            breakpoint="820px"
            size="small"
            striped-rows
          >
            <PColumn field="branch_name" header="Branch">
              <template #body="{ data }">
                <div class="branch-cell">
                  <strong>{{ data.branch_name }}</strong>
                  <small>{{ data.branch_code }}</small>
                </div>
              </template>
            </PColumn>
            <PColumn field="approved_amount" header="Approved">
              <template #body="{ data }">{{ formatCurrency(data.approved_amount) }}</template>
            </PColumn>
            <PColumn field="paid_amount" header="Paid">
              <template #body="{ data }">{{ formatCurrency(data.paid_amount) }}</template>
            </PColumn>
            <PColumn field="pending_count" header="Pending">
              <template #body="{ data }">{{ formatNumber(data.pending_count) }}</template>
            </PColumn>
          </PDataTable>
        </section>
      </section>
    </template>

    <PDialog
      v-model:visible="expenseDialogVisible"
      modal
      :header="editingExpense ? 'Edit expense' : 'Add expense'"
      class="branch-dialog"
      :style="{ width: 'min(900px, 96vw)' }"
    >
      <form class="dialog-form" @submit.prevent="submitExpense">
        <PMessage v-if="formError" severity="error" :closable="false" class="dialog-message">
          {{ formError }}
        </PMessage>

        <div class="form-grid">
          <label>
            Branch
            <PSelect
              v-model="expenseForm.branch_id"
              :options="branchOptions"
              option-label="name"
              option-value="id"
              placeholder="Select branch"
              :disabled="isBranchLocked"
              fluid
            />
          </label>
          <label>
            Category
            <PSelect
              v-model="expenseForm.category_id"
              :options="activeCategoryOptions"
              option-label="name"
              option-value="id"
              placeholder="Select category"
              filter
              fluid
            />
          </label>
          <label>
            Expense date
            <PDatePicker v-model="expenseForm.expense_date" date-format="yy-mm-dd" show-icon fluid />
          </label>
          <label>
            Payee
            <PInputText v-model.trim="expenseForm.payee" placeholder="Landlord, utility provider, staff" fluid />
          </label>
          <label>
            Amount
            <PInputNumber v-model="expenseForm.amount" mode="currency" :currency="currencyCode" locale="en-PH" fluid />
          </label>
          <label>
            Tax amount
            <PInputNumber v-model="expenseForm.tax_amount" mode="currency" :currency="currencyCode" locale="en-PH" fluid />
          </label>
          <label>
            Payment method
            <PSelect
              v-model="expenseForm.payment_method"
              :options="paymentMethodOptions"
              option-label="label"
              option-value="value"
              fluid
            />
          </label>
          <label>
            Status
            <PSelect
              v-model="expenseForm.status"
              :options="expenseStatusOptions"
              option-label="label"
              option-value="value"
              fluid
            />
          </label>
          <label>
            Reference number
            <PInputText v-model.trim="expenseForm.reference_number" placeholder="Check, card, bank, or voucher reference" fluid />
          </label>
          <label>
            Total preview
            <PInputText :model-value="formatCurrency(expenseTotalPreview)" disabled fluid />
          </label>
        </div>

        <label>
          Description
          <PTextarea v-model.trim="expenseForm.description" rows="3" placeholder="What this expense is for" fluid />
        </label>

        <label>
          Notes
          <PTextarea v-model.trim="expenseForm.notes" rows="3" fluid />
        </label>

        <div class="dialog-actions">
          <PButton type="button" label="Cancel" severity="secondary" outlined @click="expenseDialogVisible = false" />
          <PButton type="submit" icon="pi pi-save" label="Save expense" :loading="saving" />
        </div>
      </form>
    </PDialog>

    <PDialog
      v-model:visible="categoryDialogVisible"
      modal
      :header="editingCategory ? 'Edit expense category' : 'Add expense category'"
      class="branch-dialog"
      :style="{ width: 'min(720px, 96vw)' }"
    >
      <form class="dialog-form" @submit.prevent="submitCategory">
        <PMessage v-if="formError" severity="error" :closable="false" class="dialog-message">
          {{ formError }}
        </PMessage>

        <div class="form-grid">
          <label>
            Code
            <PInputText v-model.trim="categoryForm.category_code" placeholder="RENT" fluid />
          </label>
          <label>
            Name
            <PInputText v-model.trim="categoryForm.name" placeholder="Rent" fluid />
          </label>
          <label>
            Sort order
            <PInputNumber v-model="categoryForm.sort_order" :min="1" :max="999" fluid />
          </label>
          <label>
            Status
            <PSelect
              v-model="categoryForm.is_active"
              :options="activeOptions"
              option-label="label"
              option-value="value"
              fluid
            />
          </label>
        </div>

        <label>
          Description
          <PTextarea v-model.trim="categoryForm.description" rows="3" fluid />
        </label>

        <div class="dialog-actions">
          <PButton type="button" label="Cancel" severity="secondary" outlined @click="categoryDialogVisible = false" />
          <PButton type="submit" icon="pi pi-save" label="Save category" :loading="saving" />
        </div>
      </form>
    </PDialog>

    <PDialog
      v-model:visible="reasonDialogVisible"
      modal
      :header="reasonAction.status === 'voided' ? 'Void expense' : 'Reject expense'"
      class="branch-dialog"
      :style="{ width: 'min(560px, 94vw)' }"
    >
      <form class="dialog-form" @submit.prevent="submitReasonAction">
        <PMessage v-if="formError" severity="error" :closable="false" class="dialog-message">
          {{ formError }}
        </PMessage>
        <PMessage severity="warn" :closable="false" class="dialog-message">
          {{ reasonAction.status === 'voided' ? 'Voiding keeps the audit trail but removes this expense from active reporting.' : 'Rejecting sends this expense back for correction.' }}
        </PMessage>

        <label>
          Reason
          <PTextarea v-model.trim="reasonAction.reason" rows="4" placeholder="Enter the reason" fluid />
        </label>

        <div class="dialog-actions">
          <PButton type="button" label="Cancel" severity="secondary" outlined @click="reasonDialogVisible = false" />
          <PButton type="submit" icon="pi pi-check" :label="reasonAction.status === 'voided' ? 'Void expense' : 'Reject expense'" severity="danger" :loading="saving" />
        </div>
      </form>
    </PDialog>
  </section>
</template>

<script setup>
import { computed, onMounted, reactive, ref } from 'vue'
import BarChart from '../components/BarChart.vue'
import MetricCard from '../components/MetricCard.vue'
import { addDaysISO, currencyCode, formatCurrency, formatDate, formatNumber, toISODate, todayISO } from '../lib/formatters'
import {
  fetchExpenseManagement,
  saveExpense,
  saveExpenseCategory,
  updateExpenseStatus,
} from '../services/expenseService'
import { useAuthStore } from '../stores/authStore'

const auth = useAuthStore()
const loading = ref(false)
const saving = ref(false)
const error = ref('')
const successMessage = ref('')
const formError = ref('')
const expenseData = ref(null)
const expenseSearch = ref('')
const categorySearch = ref('')
const expenseDialogVisible = ref(false)
const categoryDialogVisible = ref(false)
const reasonDialogVisible = ref(false)
const editingExpense = ref(null)
const editingCategory = ref(null)

const filters = reactive({
  from: new Date(`${addDaysISO(-89)}T00:00:00`),
  to: new Date(`${todayISO()}T00:00:00`),
  branchId: null,
  search: '',
})

const expenseForm = reactive(createExpenseForm())
const categoryForm = reactive(createCategoryForm())
const reasonAction = reactive({
  expense: null,
  status: '',
  reason: '',
})

const paymentMethodOptions = [
  { label: 'Cash', value: 'cash' },
  { label: 'Card', value: 'card' },
  { label: 'GCash', value: 'gcash' },
  { label: 'Maya', value: 'maya' },
  { label: 'Bank transfer', value: 'bank_transfer' },
  { label: 'Check', value: 'check' },
  { label: 'Other', value: 'other' },
]

const expenseStatusOptions = [
  { label: 'Draft', value: 'draft' },
  { label: 'Submit for approval', value: 'submitted' },
]

const activeOptions = [
  { label: 'Active', value: true },
  { label: 'Inactive', value: false },
]

const isBranchLocked = computed(() => auth.state.profile?.role === 'manager')
const canManageExpenses = computed(() => expenseData.value?.can_manage_expenses && ['admin', 'manager'].includes(auth.state.profile?.role))
const canApproveExpenses = computed(() => expenseData.value?.can_approve_expenses && ['admin', 'manager'].includes(auth.state.profile?.role))
const canManageCategories = computed(() => auth.isAdmin.value)
const branchFilterOptions = computed(() => [{ id: null, name: 'All branches' }, ...(expenseData.value?.branches || [])])
const branchOptions = computed(() => expenseData.value?.branches || [])
const activeCategoryOptions = computed(() => (expenseData.value?.categories || []).filter((category) => category.is_active !== false))
const expenseTotalPreview = computed(() => Number(expenseForm.amount || 0) + Number(expenseForm.tax_amount || 0))
const periodLabel = computed(() => {
  const from = expenseData.value?.period?.from || toISODate(filters.from)
  const to = expenseData.value?.period?.to || toISODate(filters.to)

  return `${formatDate(from)} to ${formatDate(to)}`
})

const filteredExpenses = computed(() => {
  const query = expenseSearch.value.toLowerCase()
  const rows = expenseData.value?.expenses || []
  if (!query) return rows

  return rows.filter((row) =>
    [row.expense_number, row.category_name, row.branch_name, row.payee, row.description, row.reference_number, row.status, row.payment_method]
      .filter(Boolean)
      .some((value) => String(value).toLowerCase().includes(query)),
  )
})

const filteredCategories = computed(() => {
  const query = categorySearch.value.toLowerCase()
  const rows = expenseData.value?.categories || []
  if (!query) return rows

  return rows.filter((row) =>
    [row.category_code, row.name, row.description]
      .filter(Boolean)
      .some((value) => String(value).toLowerCase().includes(query)),
  )
})

function createExpenseForm() {
  return {
    branch_id: null,
    category_id: null,
    expense_date: new Date(`${todayISO()}T00:00:00`),
    payee: '',
    description: '',
    amount: 0,
    tax_amount: 0,
    payment_method: 'cash',
    reference_number: '',
    status: 'submitted',
    notes: '',
  }
}

function createCategoryForm() {
  return {
    category_code: '',
    name: '',
    description: '',
    sort_order: 100,
    is_active: true,
  }
}

function resetObject(target, source) {
  Object.keys(target).forEach((key) => {
    delete target[key]
  })
  Object.assign(target, source)
}

function dateValue(value) {
  return value ? new Date(`${value}T00:00:00`) : null
}

function normalizeDate(value) {
  return toISODate(value) || null
}

function defaultBranchId() {
  return filters.branchId || auth.state.profile?.branch_id || expenseData.value?.branches?.[0]?.id || null
}

function clearFeedback() {
  formError.value = ''
  error.value = ''
  successMessage.value = ''
}

async function loadExpenses() {
  loading.value = true
  error.value = ''
  successMessage.value = ''

  try {
    expenseData.value = await fetchExpenseManagement({
      from: normalizeDate(filters.from),
      to: normalizeDate(filters.to),
      branchId: filters.branchId,
      search: filters.search,
    })

    if (isBranchLocked.value && !filters.branchId) {
      filters.branchId = expenseData.value.branches[0]?.id || auth.state.profile?.branch_id || null
    }
  } catch (loadError) {
    error.value = loadError.message
  } finally {
    loading.value = false
  }
}

function openExpense(expense = null) {
  editingExpense.value = expense
  resetObject(expenseForm, {
    ...createExpenseForm(),
    ...(expense || {}),
    branch_id: expense?.branch_id || defaultBranchId(),
    category_id: expense?.category_id || activeCategoryOptions.value[0]?.id || null,
    expense_date: dateValue(expense?.expense_date) || new Date(`${todayISO()}T00:00:00`),
    status: expense?.status === 'draft' ? 'draft' : 'submitted',
  })
  formError.value = ''
  expenseDialogVisible.value = true
}

function openCategory(category = null) {
  editingCategory.value = category
  resetObject(categoryForm, {
    ...createCategoryForm(),
    ...(category || {}),
    is_active: category?.is_active !== false,
  })
  formError.value = ''
  categoryDialogVisible.value = true
}

function validateExpense() {
  if (!expenseForm.branch_id || !expenseForm.category_id) {
    formError.value = 'Branch and expense category are required.'
    return false
  }

  if (!expenseForm.description.trim()) {
    formError.value = 'Expense description is required.'
    return false
  }

  if (Number(expenseForm.amount || 0) <= 0) {
    formError.value = 'Expense amount must be greater than zero.'
    return false
  }

  if (Number(expenseForm.tax_amount || 0) < 0) {
    formError.value = 'Tax amount cannot be negative.'
    return false
  }

  return true
}

function validateCategory() {
  if (!categoryForm.name.trim()) {
    formError.value = 'Expense category name is required.'
    return false
  }

  return true
}

async function submitExpense() {
  clearFeedback()
  saving.value = true

  try {
    if (!validateExpense()) return
    expenseData.value = await saveExpense(editingExpense.value?.id, {
      ...expenseForm,
      expense_date: normalizeDate(expenseForm.expense_date),
      amount: Number(expenseForm.amount || 0),
      tax_amount: Number(expenseForm.tax_amount || 0),
    })
    expenseDialogVisible.value = false
    successMessage.value = 'Expense was saved.'
  } catch (saveError) {
    formError.value = saveError.message
  } finally {
    saving.value = false
  }
}

async function submitCategory() {
  clearFeedback()
  saving.value = true

  try {
    if (!validateCategory()) return
    expenseData.value = await saveExpenseCategory(editingCategory.value?.id, {
      ...categoryForm,
      sort_order: Number(categoryForm.sort_order || 100),
      category_code: categoryForm.category_code.trim().toUpperCase(),
    })
    categoryDialogVisible.value = false
    successMessage.value = 'Expense category was saved.'
  } catch (saveError) {
    formError.value = saveError.message
  } finally {
    saving.value = false
  }
}

async function changeExpenseStatus(expense, status) {
  const label = statusLabel(status).toLowerCase()
  if (!window.confirm(`Mark ${expense.expense_number} as ${label}?`)) return

  clearFeedback()
  saving.value = true

  try {
    expenseData.value = await updateExpenseStatus(expense.id, status)
    successMessage.value = `Expense was marked as ${label}.`
  } catch (statusError) {
    error.value = statusError.message
  } finally {
    saving.value = false
  }
}

function openReasonDialog(expense, status) {
  reasonAction.expense = expense
  reasonAction.status = status
  reasonAction.reason = ''
  formError.value = ''
  reasonDialogVisible.value = true
}

async function submitReasonAction() {
  clearFeedback()

  if (!reasonAction.reason.trim()) {
    formError.value = 'Reason is required.'
    return
  }

  saving.value = true

  try {
    expenseData.value = await updateExpenseStatus(reasonAction.expense.id, reasonAction.status, reasonAction.reason)
    reasonDialogVisible.value = false
    successMessage.value = `Expense was ${reasonAction.status === 'voided' ? 'voided' : 'rejected'}.`
  } catch (statusError) {
    formError.value = statusError.message
  } finally {
    saving.value = false
  }
}

function canEditExpense(expense) {
  return canManageExpenses.value && ['draft', 'submitted', 'rejected'].includes(expense.status)
}

function canSubmitExpense(expense) {
  return canManageExpenses.value && ['draft', 'rejected'].includes(expense.status)
}

function canApproveExpense(expense) {
  return canApproveExpenses.value && ['submitted', 'rejected'].includes(expense.status)
}

function canRejectExpense(expense) {
  return canApproveExpenses.value && ['submitted', 'approved'].includes(expense.status)
}

function canPayExpense(expense) {
  return canApproveExpenses.value && expense.status === 'approved'
}

function canVoidExpense(expense) {
  return canApproveExpenses.value && expense.status !== 'voided'
}

function methodLabel(method) {
  return paymentMethodOptions.find((option) => option.value === method)?.label || method || '-'
}

function statusLabel(status) {
  return {
    draft: 'Draft',
    submitted: 'Pending',
    approved: 'Approved',
    rejected: 'Rejected',
    paid: 'Paid',
    voided: 'Voided',
  }[status] || status
}

function statusSeverity(status) {
  return {
    draft: 'info',
    submitted: 'warn',
    approved: 'success',
    rejected: 'danger',
    paid: 'success',
    voided: 'secondary',
  }[status] || 'secondary'
}

onMounted(loadExpenses)
</script>
