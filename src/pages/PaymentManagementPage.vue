<template>
  <section class="page-stack">
    <section class="page-hero">
      <div>
        <p class="eyebrow">Module 11</p>
        <h2>Payments, split tenders, references, and settlement tracking.</h2>
        <p>
          Manage branch-enabled payment methods, enforce reference numbers for digital payments,
          monitor split payments, and track collected, tendered, fee, change, and net amounts.
        </p>
      </div>

      <form class="filter-panel" @submit.prevent="loadPayments">
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
            :options="branchOptions"
            option-label="name"
            option-value="id"
            placeholder="All branches"
            fluid
          />
        </label>
        <PButton type="submit" icon="pi pi-refresh" label="Refresh report" :loading="loading" />
      </form>
    </section>

    <PMessage v-if="!canManagePayments" severity="warn" :closable="false" class="setup-message">
      You can view payment reports with this role. Payment method and branch setup changes are admin-only.
    </PMessage>

    <PMessage v-if="error" severity="error" :closable="false" class="setup-message">
      {{ error }}
    </PMessage>

    <PMessage v-if="successMessage" severity="success" :closable="false" class="setup-message">
      {{ successMessage }}
    </PMessage>

    <section v-if="loading && !paymentData" class="stats-grid">
      <PSkeleton v-for="item in 6" :key="item" height="8rem" border-radius="8px" />
    </section>

    <template v-else-if="paymentData">
      <section class="stats-grid">
        <MetricCard label="Collected" :value="formatCurrency(paymentData.summary.collected_amount)" :caption="periodLabel" icon="pi pi-wallet" />
        <MetricCard label="Tendered" :value="formatCurrency(paymentData.summary.tendered_amount)" icon="pi pi-money-bill" tone="blue" />
        <MetricCard label="Change" :value="formatCurrency(paymentData.summary.change_amount)" icon="pi pi-replay" tone="gold" />
        <MetricCard label="Processor fees" :value="formatCurrency(paymentData.summary.processor_fee_amount)" icon="pi pi-percentage" tone="orange" />
        <MetricCard label="Net payments" :value="formatCurrency(paymentData.summary.net_amount)" icon="pi pi-check-circle" tone="green" />
        <MetricCard label="Split orders" :value="formatNumber(paymentData.summary.split_order_count)" icon="pi pi-share-alt" tone="purple" />
      </section>

      <section class="analytics-grid">
        <BarChart
          title="Payments by method"
          eyebrow="Tender mix"
          :rows="paymentData.payment_methods"
          key-field="id"
          label-field="name"
          value-field="collected_amount"
          caption="Applied sale amount"
        />
        <BarChart
          title="Payments by branch"
          eyebrow="Branch collection"
          :rows="paymentData.payments_by_branch"
          key-field="branch_id"
          label-field="branch_name"
          value-field="collected_amount"
          caption="Completed invoices"
        />
      </section>

      <section class="panel">
        <div class="table-toolbar product-toolbar">
          <div>
            <p class="eyebrow">Payment methods</p>
            <h2>Standard tender setup</h2>
          </div>
          <span class="search-field">
            <i class="pi pi-search" />
            <PInputText v-model.trim="methodSearch" placeholder="Search method, type, notes" />
          </span>
        </div>

        <PDataTable
          :value="filteredMethods"
          data-key="id"
          responsive-layout="stack"
          breakpoint="900px"
          size="small"
          striped-rows
          paginator
          :rows="8"
        >
          <PColumn field="name" header="Method">
            <template #body="{ data }">
              <div class="branch-cell">
                <strong>{{ data.name }}</strong>
                <small>{{ data.code }}</small>
              </div>
            </template>
          </PColumn>
          <PColumn field="payment_type" header="Type">
            <template #body="{ data }">
              <PTag :value="paymentTypeLabel(data.payment_type)" :severity="paymentTypeSeverity(data.payment_type)" />
            </template>
          </PColumn>
          <PColumn field="requires_reference" header="Reference">
            <template #body="{ data }">
              <PTag :value="data.requires_reference ? 'Required' : 'Optional'" :severity="data.requires_reference ? 'warn' : 'success'" />
            </template>
          </PColumn>
          <PColumn field="fee_rate" header="Fee">
            <template #body="{ data }">{{ formatRate(data.fee_rate) }}</template>
          </PColumn>
          <PColumn field="settlement_days" header="Settlement">
            <template #body="{ data }">{{ formatNumber(data.settlement_days) }} day{{ data.settlement_days === 1 ? '' : 's' }}</template>
          </PColumn>
          <PColumn field="collected_amount" header="Collected">
            <template #body="{ data }">{{ formatCurrency(data.collected_amount) }}</template>
          </PColumn>
          <PColumn field="is_active" header="Status">
            <template #body="{ data }">
              <PTag :value="data.is_active ? 'Active' : 'Inactive'" :severity="data.is_active ? 'success' : 'danger'" />
            </template>
          </PColumn>
          <PColumn header="Actions">
            <template #body="{ data }">
              <PButton icon="pi pi-pencil" text rounded aria-label="Edit payment method" :disabled="!canManagePayments" @click="openMethod(data)" />
            </template>
          </PColumn>
        </PDataTable>
      </section>

      <section class="panel">
        <div class="table-toolbar product-toolbar">
          <div>
            <p class="eyebrow">Branch payment access</p>
            <h2>Enabled methods by branch</h2>
          </div>
          <span class="search-field">
            <i class="pi pi-search" />
            <PInputText v-model.trim="branchMethodSearch" placeholder="Search branch or method" />
          </span>
        </div>

        <PDataTable
          :value="filteredBranchMethods"
          data-key="row_key"
          responsive-layout="stack"
          breakpoint="900px"
          size="small"
          striped-rows
          paginator
          :rows="10"
        >
          <PColumn field="branch_name" header="Branch">
            <template #body="{ data }">
              <div class="branch-cell">
                <strong>{{ data.branch_name }}</strong>
                <small>{{ data.branch_code }}</small>
              </div>
            </template>
          </PColumn>
          <PColumn field="method_name" header="Method">
            <template #body="{ data }">
              <div class="branch-cell">
                <strong>{{ data.method_name }}</strong>
                <small>{{ paymentTypeLabel(data.payment_type) }}</small>
              </div>
            </template>
          </PColumn>
          <PColumn field="is_enabled" header="Enabled">
            <template #body="{ data }">
              <PTag :value="data.is_enabled ? 'Enabled' : 'Disabled'" :severity="data.is_enabled ? 'success' : 'danger'" />
            </template>
          </PColumn>
          <PColumn field="requires_reference" header="Reference">
            <template #body="{ data }">{{ data.requires_reference ? 'Required' : 'Optional' }}</template>
          </PColumn>
          <PColumn field="effective_fee_rate" header="Fee">
            <template #body="{ data }">{{ formatRate(data.effective_fee_rate) }}</template>
          </PColumn>
          <PColumn field="collected_amount" header="Collected">
            <template #body="{ data }">{{ formatCurrency(data.collected_amount) }}</template>
          </PColumn>
          <PColumn header="Actions">
            <template #body="{ data }">
              <PButton icon="pi pi-pencil" text rounded aria-label="Edit branch method" :disabled="!canManagePayments" @click="openBranchMethod(data)" />
            </template>
          </PColumn>
        </PDataTable>
      </section>

      <section class="analytics-grid">
        <BarChart
          title="Daily net payments"
          eyebrow="Settlement view"
          :rows="paymentData.daily_payments"
          key-field="business_date"
          label-field="label"
          value-field="net_amount"
          caption="Collected less processor fees"
        />

        <section class="panel">
          <div class="panel__header">
            <div>
              <p class="eyebrow">Open controls</p>
              <h2>Reference and settlement watch</h2>
            </div>
          </div>

          <div class="stack-list">
            <article class="stack-list__item">
              <div>
                <strong>{{ formatNumber(paymentData.summary.pending_settlement_count) }} pending settlement</strong>
                <small>Digital, card, bank, delivery, and wallet payments still captured or pending.</small>
              </div>
              <PTag value="Review" severity="warn" />
            </article>
            <article class="stack-list__item">
              <div>
                <strong>{{ formatNumber(paymentData.summary.reference_missing_count) }} missing references</strong>
                <small>Payments marked reference-required but missing a transaction number.</small>
              </div>
              <PTag :value="paymentData.summary.reference_missing_count ? 'Fix' : 'Clean'" :severity="paymentData.summary.reference_missing_count ? 'danger' : 'success'" />
            </article>
          </div>
        </section>
      </section>

      <section class="panel">
        <div class="table-toolbar product-toolbar">
          <div>
            <p class="eyebrow">Payment transactions</p>
            <h2>Recent payment records</h2>
          </div>
          <span class="search-field">
            <i class="pi pi-search" />
            <PInputText v-model.trim="paymentSearch" placeholder="Search invoice, method, cashier, reference" />
          </span>
        </div>

        <PDataTable
          :value="filteredPayments"
          data-key="id"
          responsive-layout="stack"
          breakpoint="900px"
          size="small"
          striped-rows
          paginator
          :rows="10"
        >
          <PColumn field="invoice_number" header="Invoice">
            <template #body="{ data }">
              <div class="branch-cell">
                <strong>{{ data.invoice_number }}</strong>
                <small>{{ data.order_number }} - {{ formatDate(data.business_date) }}</small>
              </div>
            </template>
          </PColumn>
          <PColumn field="branch_name" header="Branch" />
          <PColumn field="method_label" header="Method">
            <template #body="{ data }">
              <PTag :value="data.method_label" :severity="paymentTypeSeverity(data.payment_type)" />
              <small class="muted-block">{{ data.reference_number || 'No reference' }}</small>
            </template>
          </PColumn>
          <PColumn field="amount" header="Applied">
            <template #body="{ data }">{{ formatCurrency(data.amount) }}</template>
          </PColumn>
          <PColumn field="tendered_amount" header="Tendered">
            <template #body="{ data }">{{ formatCurrency(data.tendered_amount) }}</template>
          </PColumn>
          <PColumn field="change_amount" header="Change">
            <template #body="{ data }">{{ formatCurrency(data.change_amount) }}</template>
          </PColumn>
          <PColumn field="status" header="Status">
            <template #body="{ data }">
              <PTag :value="statusLabel(data.status)" :severity="statusSeverity(data.status)" />
            </template>
          </PColumn>
          <PColumn header="Actions">
            <template #body="{ data }">
              <PButton icon="pi pi-check-circle" text rounded aria-label="Update settlement" :disabled="!canSettlePayments" @click="openSettlement(data)" />
            </template>
          </PColumn>
        </PDataTable>
      </section>
    </template>

    <PDialog v-model:visible="methodVisible" modal header="Payment method setup" class="branch-dialog" :style="{ width: 'min(760px, 96vw)' }">
      <form class="branch-form" @submit.prevent="saveMethod">
        <PMessage v-if="formError" severity="error" :closable="false" class="dialog-message">{{ formError }}</PMessage>

        <div class="form-grid">
          <label>
            Code
            <PInputText v-model.trim="methodForm.code" disabled fluid />
          </label>
          <label>
            Name
            <PInputText v-model.trim="methodForm.name" placeholder="Payment method name" fluid />
          </label>
          <label>
            Fee rate
            <PInputNumber v-model="methodForm.fee_rate" suffix="%" :min="0" :max="100" :min-fraction-digits="2" fluid />
          </label>
          <label>
            Settlement days
            <PInputNumber v-model="methodForm.settlement_days" :min="0" :max="365" :use-grouping="false" fluid />
          </label>
          <label>
            Sort order
            <PInputNumber v-model="methodForm.sort_order" :min="1" :max="999" :use-grouping="false" fluid />
          </label>
        </div>

        <div class="switch-row">
          <label>
            <PCheckbox v-model="methodForm.requires_reference" binary />
            Require reference
          </label>
          <label>
            <PCheckbox v-model="methodForm.allow_overpayment" binary />
            Allow overpayment
          </label>
          <label>
            <PCheckbox v-model="methodForm.allow_change" binary />
            Give change
          </label>
          <label>
            <PCheckbox v-model="methodForm.is_active" binary />
            Active globally
          </label>
        </div>

        <label>
          Notes
          <PTextarea v-model.trim="methodForm.notes" rows="3" auto-resize fluid />
        </label>

        <div class="dialog-actions">
          <PButton type="button" label="Cancel" severity="secondary" outlined @click="methodVisible = false" />
          <PButton type="submit" icon="pi pi-save" label="Save method" :loading="saving" />
        </div>
      </form>
    </PDialog>

    <PDialog v-model:visible="branchMethodVisible" modal header="Branch payment method" class="branch-dialog" :style="{ width: 'min(680px, 96vw)' }">
      <form class="branch-form" @submit.prevent="saveBranchMethod">
        <PMessage v-if="formError" severity="error" :closable="false" class="dialog-message">{{ formError }}</PMessage>

        <div class="copy-panel">
          <div>
            <h2>{{ branchMethodForm.branch_name }}</h2>
            <p>{{ branchMethodForm.method_name }}</p>
          </div>
          <PTag :value="branchMethodForm.is_enabled ? 'Enabled' : 'Disabled'" :severity="branchMethodForm.is_enabled ? 'success' : 'danger'" />
        </div>

        <div class="form-grid">
          <label>
            Fee override
            <PInputNumber v-model="branchMethodForm.fee_rate_override" suffix="%" :min="0" :max="100" :min-fraction-digits="2" fluid />
          </label>
        </div>

        <div class="switch-row">
          <label>
            <PCheckbox v-model="branchMethodForm.is_enabled" binary />
            Enabled for branch
          </label>
          <label>
            <PCheckbox v-model="branchMethodForm.reference_required_override" binary />
            Require reference
          </label>
        </div>

        <label>
          Notes
          <PTextarea v-model.trim="branchMethodForm.notes" rows="3" auto-resize fluid />
        </label>

        <div class="dialog-actions">
          <PButton type="button" label="Cancel" severity="secondary" outlined @click="branchMethodVisible = false" />
          <PButton type="submit" icon="pi pi-save" label="Save branch method" :loading="saving" />
        </div>
      </form>
    </PDialog>

    <PDialog v-model:visible="settlementVisible" modal header="Payment settlement" class="branch-dialog" :style="{ width: 'min(620px, 96vw)' }">
      <form class="branch-form" @submit.prevent="saveSettlement">
        <PMessage v-if="formError" severity="error" :closable="false" class="dialog-message">{{ formError }}</PMessage>

        <div class="copy-panel">
          <div>
            <h2>{{ settlementPayment?.invoice_number }}</h2>
            <p>{{ settlementPayment?.method_label }} - {{ formatCurrency(settlementPayment?.amount) }}</p>
          </div>
          <PTag :value="statusLabel(settlementForm.status)" :severity="statusSeverity(settlementForm.status)" />
        </div>

        <div class="form-grid">
          <label>
            Status
            <PSelect v-model="settlementForm.status" :options="statusOptions" option-label="label" option-value="value" fluid />
          </label>
          <label>
            Settled date
            <PDatePicker v-model="settlementForm.settled_at" date-format="yy-mm-dd" show-icon fluid />
          </label>
        </div>

        <label>
          Notes
          <PTextarea v-model.trim="settlementForm.notes" rows="3" auto-resize fluid />
        </label>

        <div class="dialog-actions">
          <PButton type="button" label="Cancel" severity="secondary" outlined @click="settlementVisible = false" />
          <PButton type="submit" icon="pi pi-save" label="Save settlement" :loading="saving" />
        </div>
      </form>
    </PDialog>
  </section>
</template>

<script setup>
import { computed, onMounted, reactive, ref } from 'vue'
import BarChart from '../components/BarChart.vue'
import MetricCard from '../components/MetricCard.vue'
import { addDaysISO, formatCurrency, formatDate, formatNumber, toISODate, todayISO } from '../lib/formatters'
import {
  fetchPaymentManagement,
  saveBranchPaymentMethod,
  savePaymentMethod,
  updatePaymentSettlement,
} from '../services/paymentService'
import { useAuthStore } from '../stores/authStore'

const auth = useAuthStore()
const loading = ref(false)
const saving = ref(false)
const error = ref('')
const successMessage = ref('')
const formError = ref('')
const paymentData = ref(null)
const methodSearch = ref('')
const branchMethodSearch = ref('')
const paymentSearch = ref('')
const methodVisible = ref(false)
const branchMethodVisible = ref(false)
const settlementVisible = ref(false)
const editingMethodId = ref(null)
const editingBranchId = ref(null)
const editingBranchMethodId = ref(null)
const settlementPayment = ref(null)

const filters = reactive({
  from: new Date(`${addDaysISO(-29)}T00:00:00`),
  to: new Date(`${todayISO()}T00:00:00`),
  branchId: null,
})

const methodForm = reactive(createMethodForm())
const branchMethodForm = reactive(createBranchMethodForm())
const settlementForm = reactive(createSettlementForm())

const statusOptions = [
  { label: 'Captured', value: 'captured' },
  { label: 'Pending', value: 'pending' },
  { label: 'Settled', value: 'settled' },
  { label: 'Failed', value: 'failed' },
  { label: 'Refunded', value: 'refunded' },
  { label: 'Void', value: 'void' },
]

const paymentTypeOptions = [
  { label: 'Cash', value: 'cash' },
  { label: 'Card', value: 'card' },
  { label: 'E-wallet', value: 'e_wallet' },
  { label: 'Bank', value: 'bank' },
  { label: 'Credit', value: 'credit' },
  { label: 'Delivery', value: 'delivery' },
]

const canManagePayments = computed(() => auth.isAdmin.value)
const canSettlePayments = computed(() => auth.isAdmin.value || auth.state.profile?.role === 'manager')

const branchOptions = computed(() => [
  { id: null, name: 'All branches' },
  ...(paymentData.value?.branches || []),
])

const filteredMethods = computed(() => {
  const query = methodSearch.value.toLowerCase()
  const rows = paymentData.value?.payment_methods || []
  if (!query) return rows

  return rows.filter((method) =>
    [method.code, method.name, paymentTypeLabel(method.payment_type), method.notes]
      .filter(Boolean)
      .some((value) => String(value).toLowerCase().includes(query)),
  )
})

const filteredBranchMethods = computed(() => {
  const query = branchMethodSearch.value.toLowerCase()
  const rows = (paymentData.value?.branch_payment_methods || []).map((row) => ({
    ...row,
    row_key: `${row.branch_id}:${row.payment_method_id}`,
  }))
  if (!query) return rows

  return rows.filter((row) =>
    [row.branch_code, row.branch_name, row.code, row.method_name, paymentTypeLabel(row.payment_type)]
      .filter(Boolean)
      .some((value) => String(value).toLowerCase().includes(query)),
  )
})

const filteredPayments = computed(() => {
  const query = paymentSearch.value.toLowerCase()
  const rows = paymentData.value?.recent_payments || []
  if (!query) return rows

  return rows.filter((payment) =>
    [
      payment.invoice_number,
      payment.order_number,
      payment.branch_name,
      payment.method,
      payment.method_label,
      payment.reference_number,
      payment.cashier_name,
      payment.cashier_username,
      payment.status,
    ]
      .filter(Boolean)
      .some((value) => String(value).toLowerCase().includes(query)),
  )
})

const periodLabel = computed(() => {
  const from = paymentData.value?.period?.from || toISODate(filters.from)
  const to = paymentData.value?.period?.to || toISODate(filters.to)

  return `${formatDate(from)} to ${formatDate(to)}`
})

function createMethodForm() {
  return {
    code: '',
    name: '',
    requires_reference: false,
    allow_overpayment: false,
    allow_change: false,
    settlement_days: 0,
    fee_rate: 0,
    sort_order: 100,
    is_active: true,
    notes: '',
  }
}

function createBranchMethodForm() {
  return {
    branch_name: '',
    method_name: '',
    is_enabled: true,
    reference_required_override: false,
    fee_rate_override: null,
    notes: '',
  }
}

function createSettlementForm() {
  return {
    status: 'captured',
    settled_at: new Date(),
    notes: '',
  }
}

function resetReactive(target, source) {
  Object.assign(target, source)
}

function formatRate(value) {
  return `${formatNumber(Number(value || 0).toFixed(2))}%`
}

function paymentTypeLabel(value) {
  return paymentTypeOptions.find((option) => option.value === value)?.label || value || '-'
}

function paymentTypeSeverity(value) {
  if (value === 'cash') return 'success'
  if (value === 'card') return 'info'
  if (value === 'e_wallet') return 'warn'
  if (value === 'bank') return 'info'
  if (value === 'delivery') return 'danger'

  return 'secondary'
}

function statusLabel(value) {
  return statusOptions.find((option) => option.value === value)?.label || value || '-'
}

function statusSeverity(value) {
  if (value === 'settled' || value === 'captured') return 'success'
  if (value === 'pending') return 'warn'
  if (value === 'failed' || value === 'void') return 'danger'
  if (value === 'refunded') return 'info'

  return 'secondary'
}

async function loadPayments(clearMessages = true) {
  loading.value = true
  if (clearMessages) {
    error.value = ''
    successMessage.value = ''
  }

  try {
    paymentData.value = await fetchPaymentManagement({
      from: toISODate(filters.from),
      to: toISODate(filters.to),
      branchId: filters.branchId,
    })
  } catch (loadError) {
    error.value = loadError.message
  } finally {
    loading.value = false
  }
}

function openMethod(method) {
  formError.value = ''
  editingMethodId.value = method.id
  resetReactive(methodForm, {
    ...createMethodForm(),
    ...method,
    fee_rate: Number(method.fee_rate || 0),
    settlement_days: Number(method.settlement_days || 0),
    sort_order: Number(method.sort_order || 100),
  })
  methodVisible.value = true
}

function openBranchMethod(row) {
  formError.value = ''
  editingBranchId.value = row.branch_id
  editingBranchMethodId.value = row.payment_method_id
  resetReactive(branchMethodForm, {
    ...createBranchMethodForm(),
    branch_name: row.branch_name,
    method_name: row.method_name,
    is_enabled: Boolean(row.is_enabled),
    reference_required_override: Boolean(row.requires_reference),
    fee_rate_override: row.fee_rate_override === null || row.fee_rate_override === undefined ? row.effective_fee_rate : row.fee_rate_override,
    notes: row.notes || '',
  })
  branchMethodVisible.value = true
}

function openSettlement(payment) {
  formError.value = ''
  settlementPayment.value = payment
  resetReactive(settlementForm, {
    ...createSettlementForm(),
    status: payment.status || 'captured',
    settled_at: payment.settled_at ? new Date(payment.settled_at) : new Date(),
    notes: payment.notes || '',
  })
  settlementVisible.value = true
}

function validateMethod() {
  if (!methodForm.name?.trim()) {
    formError.value = 'Payment method name is required.'
    return false
  }

  return true
}

async function saveMethod() {
  if (!validateMethod()) return

  saving.value = true
  formError.value = ''
  error.value = ''

  try {
    await savePaymentMethod(editingMethodId.value, { ...methodForm })
    methodVisible.value = false
    successMessage.value = 'Payment method saved.'
    await loadPayments(false)
  } catch (saveError) {
    formError.value = saveError.message
  } finally {
    saving.value = false
  }
}

async function saveBranchMethod() {
  if (!editingBranchId.value || !editingBranchMethodId.value) {
    formError.value = 'Branch and payment method are required.'
    return
  }

  saving.value = true
  formError.value = ''
  error.value = ''

  try {
    await saveBranchPaymentMethod(editingBranchId.value, editingBranchMethodId.value, {
      is_enabled: branchMethodForm.is_enabled,
      reference_required_override: branchMethodForm.reference_required_override,
      fee_rate_override: branchMethodForm.fee_rate_override,
      notes: branchMethodForm.notes,
    })
    branchMethodVisible.value = false
    successMessage.value = 'Branch payment method saved.'
    await loadPayments(false)
  } catch (saveError) {
    formError.value = saveError.message
  } finally {
    saving.value = false
  }
}

async function saveSettlement() {
  if (!settlementPayment.value?.id) {
    formError.value = 'Payment is required.'
    return
  }

  saving.value = true
  formError.value = ''
  error.value = ''

  try {
    await updatePaymentSettlement(
      settlementPayment.value.id,
      settlementForm.status,
      settlementForm.settled_at ? settlementForm.settled_at.toISOString() : null,
      settlementForm.notes,
    )
    settlementVisible.value = false
    successMessage.value = 'Payment settlement updated.'
    await loadPayments(false)
  } catch (saveError) {
    formError.value = saveError.message
  } finally {
    saving.value = false
  }
}

onMounted(loadPayments)
</script>
