<template>
  <section class="page-stack">
    <section class="page-hero">
      <div>
        <p class="eyebrow">Module 16</p>
        <h2>Customer profiles, purchase history, loyalty, store credit, and receivables.</h2>
        <p>
          Keep customer records connected to POS invoices, track credit sales and payments,
          monitor store-credit balances, and award loyalty points from completed purchases.
        </p>
      </div>

      <form class="filter-panel" @submit.prevent="loadCustomers">
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
          Customer
          <PSelect
            v-model="filters.customerId"
            :options="customerFilterOptions"
            option-label="label"
            option-value="value"
            placeholder="All customers"
            filter
            fluid
          />
        </label>
        <label>
          Search
          <PInputText v-model.trim="filters.search" placeholder="Customer, invoice, phone, email" fluid />
        </label>
        <div class="dialog-actions">
          <PButton type="submit" icon="pi pi-refresh" label="Refresh" :loading="loading" />
          <PButton type="button" icon="pi pi-user-plus" label="Customer" :disabled="!canManageCustomers" @click="openCustomer" />
          <PButton type="button" icon="pi pi-wallet" label="Credit / payment" outlined :disabled="!canCreditCustomers" @click="openAccountEntry" />
        </div>
      </form>
    </section>

    <PMessage v-if="error" severity="error" :closable="false" class="setup-message">
      {{ error }}
    </PMessage>

    <PMessage v-if="successMessage" severity="success" :closable="false" class="setup-message">
      {{ successMessage }}
    </PMessage>

    <section v-if="loading && !customerData" class="stats-grid">
      <PSkeleton v-for="item in 6" :key="item" height="8rem" border-radius="8px" />
    </section>

    <template v-else-if="customerData">
      <section class="stats-grid">
        <MetricCard label="Customers" :value="formatNumber(customerData.summary.customer_count)" :caption="periodLabel" icon="pi pi-users" />
        <MetricCard label="Customer sales" :value="formatCurrency(customerData.summary.sales_value)" :caption="`${formatNumber(customerData.summary.order_count)} order(s)`" icon="pi pi-shopping-bag" tone="blue" />
        <MetricCard label="Receivables" :value="formatCurrency(customerData.summary.receivable_balance)" icon="pi pi-wallet" tone="red" />
        <MetricCard label="Store credit" :value="formatCurrency(customerData.summary.store_credit_balance)" icon="pi pi-ticket" tone="green" />
        <MetricCard label="Loyalty points" :value="formatNumber(customerData.summary.loyalty_points)" icon="pi pi-star" tone="gold" />
        <MetricCard label="Collected" :value="formatCurrency(customerData.summary.payments_collected)" icon="pi pi-check-circle" tone="purple" />
      </section>

      <section class="analytics-grid">
        <BarChart
          title="Customer sales by day"
          eyebrow="Purchase trend"
          :rows="customerData.daily_sales"
          key-field="business_date"
          label-field="label"
          value-field="sales"
          caption="Completed invoices"
        />
        <BarChart
          title="Top customers"
          eyebrow="Customer performance"
          :rows="customerData.top_customers"
          key-field="id"
          label-field="full_name"
          value-field="period_sales"
          caption="Period sales"
        />
      </section>

      <section class="panel">
        <div class="table-toolbar product-toolbar">
          <div>
            <p class="eyebrow">Customer directory</p>
            <h2>Profiles, balances, and loyalty</h2>
          </div>
          <span class="search-field">
            <i class="pi pi-search" />
            <PInputText v-model.trim="customerSearch" placeholder="Search customers" />
          </span>
        </div>

        <PDataTable
          :value="filteredCustomers"
          data-key="id"
          responsive-layout="stack"
          breakpoint="920px"
          size="small"
          striped-rows
          paginator
          :rows="10"
        >
          <PColumn field="full_name" header="Customer">
            <template #body="{ data }">
              <div class="branch-cell">
                <strong>{{ data.full_name }}</strong>
                <small>{{ data.customer_code }} - {{ data.phone || data.email || 'No contact' }}</small>
              </div>
            </template>
          </PColumn>
          <PColumn field="customer_type" header="Type">
            <template #body="{ data }">
              <PTag :value="customerTypeLabel(data.customer_type)" :severity="customerTypeSeverity(data.customer_type)" />
              <small class="muted-block">{{ data.is_active ? 'Active' : 'Inactive' }}</small>
            </template>
          </PColumn>
          <PColumn field="branch_name" header="Branch">
            <template #body="{ data }">{{ data.branch_name || 'All branches' }}</template>
          </PColumn>
          <PColumn field="receivable_balance" header="Receivable">
            <template #body="{ data }">
              {{ formatCurrency(data.receivable_balance) }}
              <small class="muted-block">Limit {{ formatCurrency(data.credit_limit) }}</small>
            </template>
          </PColumn>
          <PColumn field="store_credit_balance" header="Store credit">
            <template #body="{ data }">{{ formatCurrency(data.store_credit_balance) }}</template>
          </PColumn>
          <PColumn field="loyalty_points" header="Points">
            <template #body="{ data }">
              {{ formatNumber(data.loyalty_points) }}
              <small class="muted-block">{{ formatCurrency(data.total_spent) }} lifetime</small>
            </template>
          </PColumn>
          <PColumn header="Actions">
            <template #body="{ data }">
              <div class="table-actions">
                <PButton icon="pi pi-pencil" text rounded aria-label="Edit customer" :disabled="!canManageCustomers" @click="openCustomer(data)" />
                <PButton icon="pi pi-wallet" text rounded aria-label="Post credit or payment" :disabled="!canCreditCustomers" @click="openAccountEntry(data)" />
                <PButton icon="pi pi-star" text rounded aria-label="Adjust loyalty" :disabled="!canCreditCustomers" @click="openLoyalty(data)" />
              </div>
            </template>
          </PColumn>
        </PDataTable>
      </section>

      <section class="analytics-grid">
        <section class="panel">
          <div class="table-toolbar product-toolbar">
            <div>
              <p class="eyebrow">Purchase history</p>
              <h2>Linked POS invoices</h2>
            </div>
            <span class="search-field">
              <i class="pi pi-search" />
              <PInputText v-model.trim="orderSearch" placeholder="Search invoices" />
            </span>
          </div>

          <PDataTable
            :value="filteredOrders"
            data-key="id"
            responsive-layout="stack"
            breakpoint="860px"
            size="small"
            striped-rows
            paginator
            :rows="8"
          >
            <PColumn field="invoice_number" header="Invoice">
              <template #body="{ data }">
                <div class="branch-cell">
                  <strong>{{ data.invoice_number || data.order_number }}</strong>
                  <small>{{ formatDateTime(data.created_at) }}</small>
                </div>
              </template>
            </PColumn>
            <PColumn field="customer_name" header="Customer">
              <template #body="{ data }">{{ data.customer_full_name || data.customer_name || 'Walk-in' }}</template>
            </PColumn>
            <PColumn field="branch_name" header="Branch" />
            <PColumn field="payment_method_summary" header="Payment" />
            <PColumn field="status" header="Status">
              <template #body="{ data }">
                <PTag :value="statusLabel(data.status)" :severity="statusSeverity(data.status)" />
              </template>
            </PColumn>
            <PColumn field="total" header="Total">
              <template #body="{ data }">{{ formatCurrency(data.total) }}</template>
            </PColumn>
          </PDataTable>
        </section>

        <section class="panel">
          <div class="table-toolbar product-toolbar">
            <div>
              <p class="eyebrow">Account ledger</p>
              <h2>Receivables and store credit</h2>
            </div>
            <span class="search-field">
              <i class="pi pi-search" />
              <PInputText v-model.trim="ledgerSearch" placeholder="Search ledger" />
            </span>
          </div>

          <PDataTable
            :value="filteredAccountEntries"
            data-key="id"
            responsive-layout="stack"
            breakpoint="860px"
            size="small"
            striped-rows
            paginator
            :rows="8"
          >
            <PColumn field="entry_type" header="Entry">
              <template #body="{ data }">
                <div class="branch-cell">
                  <strong>{{ entryTypeLabel(data.entry_type) }}</strong>
                  <small>{{ data.reference_number || data.invoice_number || 'Manual entry' }}</small>
                </div>
              </template>
            </PColumn>
            <PColumn field="customer_full_name" header="Customer" />
            <PColumn field="receivable_delta" header="Receivable">
              <template #body="{ data }">{{ signedCurrency(data.receivable_delta) }}</template>
            </PColumn>
            <PColumn field="store_credit_delta" header="Store credit">
              <template #body="{ data }">{{ signedCurrency(data.store_credit_delta) }}</template>
            </PColumn>
            <PColumn field="status" header="Status">
              <template #body="{ data }">
                <PTag :value="data.status" :severity="data.status === 'posted' ? 'success' : 'danger'" />
              </template>
            </PColumn>
            <PColumn header="Actions">
              <template #body="{ data }">
                <PButton
                  icon="pi pi-ban"
                  text
                  rounded
                  severity="danger"
                  aria-label="Void customer ledger entry"
                  :disabled="!canCreditCustomers || data.status !== 'posted'"
                  @click="voidEntry(data)"
                />
              </template>
            </PColumn>
          </PDataTable>
        </section>
      </section>

      <section class="analytics-grid">
        <section class="panel">
          <div class="panel__header">
            <div>
              <p class="eyebrow">Loyalty ledger</p>
              <h2>Earned and adjusted points</h2>
            </div>
          </div>

          <PDataTable
            :value="customerData.loyalty_ledger"
            data-key="id"
            responsive-layout="stack"
            breakpoint="760px"
            size="small"
            striped-rows
            paginator
            :rows="8"
          >
            <PColumn field="customer_full_name" header="Customer" />
            <PColumn field="entry_type" header="Type">
              <template #body="{ data }">{{ loyaltyTypeLabel(data.entry_type) }}</template>
            </PColumn>
            <PColumn field="points_delta" header="Points">
              <template #body="{ data }">{{ signedNumber(data.points_delta) }}</template>
            </PColumn>
            <PColumn field="invoice_number" header="Invoice">
              <template #body="{ data }">{{ data.invoice_number || '-' }}</template>
            </PColumn>
            <PColumn field="created_at" header="Date">
              <template #body="{ data }">{{ formatDateTime(data.created_at) }}</template>
            </PColumn>
          </PDataTable>
        </section>

        <section class="panel">
          <div class="panel__header">
            <div>
              <p class="eyebrow">Branch summary</p>
              <h2>Customer sales and balances</h2>
            </div>
          </div>

          <PDataTable
            :value="customerData.branch_summary"
            data-key="branch_id"
            responsive-layout="stack"
            breakpoint="760px"
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
            <PColumn field="sales" header="Sales">
              <template #body="{ data }">{{ formatCurrency(data.sales) }}</template>
            </PColumn>
            <PColumn field="receivable_balance" header="Receivable">
              <template #body="{ data }">{{ formatCurrency(data.receivable_balance) }}</template>
            </PColumn>
            <PColumn field="store_credit_balance" header="Store credit">
              <template #body="{ data }">{{ formatCurrency(data.store_credit_balance) }}</template>
            </PColumn>
          </PDataTable>
        </section>
      </section>
    </template>

    <PDialog
      v-model:visible="customerDialogVisible"
      modal
      :header="editingCustomer ? 'Edit customer' : 'Add customer'"
      class="branch-dialog"
      :style="{ width: 'min(880px, 96vw)' }"
    >
      <form class="dialog-form" @submit.prevent="submitCustomer">
        <PMessage v-if="formError" severity="error" :closable="false" class="dialog-message">
          {{ formError }}
        </PMessage>

        <div class="form-grid">
          <label>
            Full name
            <PInputText v-model.trim="customerForm.full_name" fluid />
          </label>
          <label>
            Customer code
            <PInputText v-model.trim="customerForm.customer_code" placeholder="Auto-generated if blank" fluid />
          </label>
          <label>
            Branch
            <PSelect v-model="customerForm.branch_id" :options="branchOptions" option-label="name" option-value="id" :disabled="isBranchLocked" fluid />
          </label>
          <label>
            Customer type
            <PSelect v-model="customerForm.customer_type" :options="customerTypeOptions" option-label="label" option-value="value" fluid />
          </label>
          <label>
            Phone
            <PInputText v-model.trim="customerForm.phone" fluid />
          </label>
          <label>
            Email
            <PInputText v-model.trim="customerForm.email" fluid />
          </label>
          <label>
            TIN
            <PInputText v-model.trim="customerForm.tin" fluid />
          </label>
          <label>
            Birth date
            <PDatePicker v-model="customerForm.birth_date" date-format="yy-mm-dd" show-icon fluid />
          </label>
          <label>
            Credit limit
            <PInputNumber v-model="customerForm.credit_limit" mode="currency" :currency="currencyCode" fluid />
          </label>
          <label>
            Status
            <PSelect v-model="customerForm.is_active" :options="statusOptions" option-label="label" option-value="value" fluid />
          </label>
        </div>

        <label>
          Address
          <PTextarea v-model.trim="customerForm.address" rows="2" fluid />
        </label>
        <label>
          Notes
          <PTextarea v-model.trim="customerForm.notes" rows="3" fluid />
        </label>

        <div class="dialog-actions">
          <PButton type="button" label="Cancel" severity="secondary" outlined @click="customerDialogVisible = false" />
          <PButton type="submit" icon="pi pi-save" label="Save customer" :loading="saving" />
        </div>
      </form>
    </PDialog>

    <PDialog
      v-model:visible="accountDialogVisible"
      modal
      header="Post customer credit / payment"
      class="branch-dialog"
      :style="{ width: 'min(760px, 96vw)' }"
    >
      <form class="dialog-form" @submit.prevent="submitAccountEntry">
        <PMessage v-if="formError" severity="error" :closable="false" class="dialog-message">
          {{ formError }}
        </PMessage>

        <div class="form-grid">
          <label>
            Branch
            <PSelect v-model="accountForm.branch_id" :options="branchOptions" option-label="name" option-value="id" :disabled="isBranchLocked" fluid />
          </label>
          <label>
            Customer
            <PSelect v-model="accountForm.customer_id" :options="customerOptions" option-label="label" option-value="value" filter fluid />
          </label>
          <label>
            Entry type
            <PSelect v-model="accountForm.entry_type" :options="accountEntryOptions" option-label="label" option-value="value" fluid />
          </label>
          <label>
            Amount
            <PInputNumber v-model="accountForm.amount" mode="currency" :currency="currencyCode" fluid />
          </label>
          <label>
            Reference
            <PInputText v-model.trim="accountForm.reference_number" fluid />
          </label>
          <label>
            Current balance
            <PInputText :model-value="selectedAccountCustomerBalance" disabled fluid />
          </label>
        </div>

        <label>
          Description
          <PTextarea v-model.trim="accountForm.description" rows="3" fluid />
        </label>

        <div class="dialog-actions">
          <PButton type="button" label="Cancel" severity="secondary" outlined @click="accountDialogVisible = false" />
          <PButton type="submit" icon="pi pi-check" label="Post entry" :loading="saving" />
        </div>
      </form>
    </PDialog>

    <PDialog
      v-model:visible="loyaltyDialogVisible"
      modal
      header="Adjust loyalty points"
      class="branch-dialog"
      :style="{ width: 'min(640px, 96vw)' }"
    >
      <form class="dialog-form" @submit.prevent="submitLoyalty">
        <PMessage v-if="formError" severity="error" :closable="false" class="dialog-message">
          {{ formError }}
        </PMessage>

        <div class="form-grid">
          <label>
            Branch
            <PSelect v-model="loyaltyForm.branch_id" :options="branchOptions" option-label="name" option-value="id" :disabled="isBranchLocked" fluid />
          </label>
          <label>
            Customer
            <PSelect v-model="loyaltyForm.customer_id" :options="customerOptions" option-label="label" option-value="value" filter fluid />
          </label>
          <label>
            Points change
            <PInputNumber v-model="loyaltyForm.points_delta" :use-grouping="false" fluid />
          </label>
          <label>
            Current points
            <PInputText :model-value="selectedLoyaltyCustomer ? formatNumber(selectedLoyaltyCustomer.loyalty_points) : '-'" disabled fluid />
          </label>
        </div>

        <label>
          Description
          <PTextarea v-model.trim="loyaltyForm.description" rows="3" fluid />
        </label>

        <div class="dialog-actions">
          <PButton type="button" label="Cancel" severity="secondary" outlined @click="loyaltyDialogVisible = false" />
          <PButton type="submit" icon="pi pi-star" label="Save adjustment" :loading="saving" />
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
  adjustCustomerLoyalty,
  fetchCustomerManagement,
  postCustomerAccountEntry,
  saveCustomerProfile,
  voidCustomerAccountEntry,
} from '../services/customerService'
import { useAuthStore } from '../stores/authStore'

const auth = useAuthStore()
const loading = ref(false)
const saving = ref(false)
const error = ref('')
const successMessage = ref('')
const formError = ref('')
const customerData = ref(null)
const customerSearch = ref('')
const orderSearch = ref('')
const ledgerSearch = ref('')
const customerDialogVisible = ref(false)
const accountDialogVisible = ref(false)
const loyaltyDialogVisible = ref(false)
const editingCustomer = ref(null)

const filters = reactive({
  from: new Date(`${addDaysISO(-89)}T00:00:00`),
  to: new Date(`${todayISO()}T00:00:00`),
  branchId: null,
  customerId: null,
  search: '',
})

const customerForm = reactive(createCustomerForm())
const accountForm = reactive(createAccountForm())
const loyaltyForm = reactive(createLoyaltyForm())

const customerTypeOptions = [
  { label: 'Regular', value: 'regular' },
  { label: 'Senior Citizen', value: 'senior' },
  { label: 'PWD', value: 'pwd' },
  { label: 'Company', value: 'company' },
]

const statusOptions = [
  { label: 'Active', value: true },
  { label: 'Inactive', value: false },
]

const accountEntryOptions = [
  { label: 'Credit sale / charge', value: 'credit_sale' },
  { label: 'Customer payment', value: 'payment' },
  { label: 'Issue store credit', value: 'store_credit_issue' },
  { label: 'Use store credit', value: 'store_credit_use' },
  { label: 'Write off receivable', value: 'write_off' },
  { label: 'Return credit', value: 'return_credit' },
]

const isBranchLocked = computed(() => auth.state.profile?.role === 'manager')
const canManageCustomers = computed(() => customerData.value?.can_manage_customers && ['admin', 'manager'].includes(auth.state.profile?.role))
const canCreditCustomers = computed(() => customerData.value?.can_credit_customers && ['admin', 'manager'].includes(auth.state.profile?.role))
const branchFilterOptions = computed(() => [{ id: null, name: 'All branches' }, ...(customerData.value?.branches || [])])
const branchOptions = computed(() => customerData.value?.branches || [])
const customerOptions = computed(() =>
  (customerData.value?.customers || []).map((customer) => ({
    label: `${customer.customer_code} - ${customer.full_name}`,
    value: customer.id,
  })),
)
const customerFilterOptions = computed(() => [{ label: 'All customers', value: null }, ...customerOptions.value])
const selectedAccountCustomer = computed(() => (customerData.value?.customers || []).find((customer) => customer.id === accountForm.customer_id))
const selectedLoyaltyCustomer = computed(() => (customerData.value?.customers || []).find((customer) => customer.id === loyaltyForm.customer_id))
const selectedAccountCustomerBalance = computed(() => {
  const customer = selectedAccountCustomer.value
  if (!customer) return '-'

  return `Receivable ${formatCurrency(customer.receivable_balance)} / Store credit ${formatCurrency(customer.store_credit_balance)}`
})
const periodLabel = computed(() => {
  const from = customerData.value?.period?.from || toISODate(filters.from)
  const to = customerData.value?.period?.to || toISODate(filters.to)

  return `${formatDate(from)} to ${formatDate(to)}`
})

const filteredCustomers = computed(() => {
  const query = customerSearch.value.toLowerCase()
  const rows = customerData.value?.customers || []
  if (!query) return rows

  return rows.filter((row) =>
    [row.customer_code, row.full_name, row.phone, row.email, row.tin, row.customer_type, row.branch_name]
      .filter(Boolean)
      .some((value) => String(value).toLowerCase().includes(query)),
  )
})

const filteredOrders = computed(() => {
  const query = orderSearch.value.toLowerCase()
  const rows = customerData.value?.orders || []
  if (!query) return rows

  return rows.filter((row) =>
    [row.invoice_number, row.order_number, row.customer_name, row.customer_full_name, row.branch_name, row.payment_method_summary, row.status]
      .filter(Boolean)
      .some((value) => String(value).toLowerCase().includes(query)),
  )
})

const filteredAccountEntries = computed(() => {
  const query = ledgerSearch.value.toLowerCase()
  const rows = customerData.value?.account_entries || []
  if (!query) return rows

  return rows.filter((row) =>
    [row.entry_type, row.customer_full_name, row.reference_number, row.description, row.invoice_number, row.status]
      .filter(Boolean)
      .some((value) => String(value).toLowerCase().includes(query)),
  )
})

function createCustomerForm() {
  return {
    customer_code: '',
    full_name: '',
    phone: '',
    email: '',
    tin: '',
    address: '',
    birth_date: null,
    customer_type: 'regular',
    branch_id: null,
    credit_limit: 0,
    is_active: true,
    notes: '',
  }
}

function createAccountForm() {
  return {
    branch_id: null,
    customer_id: null,
    entry_type: 'payment',
    amount: 0,
    reference_number: '',
    description: '',
  }
}

function createLoyaltyForm() {
  return {
    branch_id: null,
    customer_id: null,
    points_delta: 0,
    description: '',
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
  return filters.branchId || auth.state.profile?.branch_id || customerData.value?.branches?.[0]?.id || null
}

function clearFeedback() {
  formError.value = ''
  error.value = ''
  successMessage.value = ''
}

async function loadCustomers() {
  loading.value = true
  error.value = ''
  successMessage.value = ''

  try {
    customerData.value = await fetchCustomerManagement({
      from: normalizeDate(filters.from),
      to: normalizeDate(filters.to),
      branchId: filters.branchId,
      customerId: filters.customerId,
      search: filters.search,
    })

    if (isBranchLocked.value && !filters.branchId) {
      filters.branchId = customerData.value.branches[0]?.id || auth.state.profile?.branch_id || null
    }
  } catch (loadError) {
    error.value = loadError.message
  } finally {
    loading.value = false
  }
}

function openCustomer(customer = null) {
  editingCustomer.value = customer
  resetObject(customerForm, {
    ...createCustomerForm(),
    ...(customer || {}),
    branch_id: customer?.branch_id || defaultBranchId(),
    birth_date: dateValue(customer?.birth_date),
    is_active: customer?.is_active !== false,
  })
  formError.value = ''
  customerDialogVisible.value = true
}

function openAccountEntry(customer = null) {
  resetObject(accountForm, {
    ...createAccountForm(),
    branch_id: customer?.branch_id || defaultBranchId(),
    customer_id: customer?.id || null,
  })
  formError.value = ''
  accountDialogVisible.value = true
}

function openLoyalty(customer = null) {
  resetObject(loyaltyForm, {
    ...createLoyaltyForm(),
    branch_id: customer?.branch_id || defaultBranchId(),
    customer_id: customer?.id || null,
  })
  formError.value = ''
  loyaltyDialogVisible.value = true
}

function validateCustomer() {
  if (!customerForm.full_name.trim()) {
    formError.value = 'Customer full name is required.'
    return false
  }

  if (!customerForm.branch_id) {
    formError.value = 'Customer branch is required.'
    return false
  }

  return true
}

function validateAccountEntry() {
  if (!accountForm.branch_id || !accountForm.customer_id) {
    formError.value = 'Branch and customer are required.'
    return false
  }

  if (Number(accountForm.amount || 0) <= 0) {
    formError.value = 'Amount must be greater than zero.'
    return false
  }

  return true
}

function validateLoyalty() {
  if (!loyaltyForm.branch_id || !loyaltyForm.customer_id) {
    formError.value = 'Branch and customer are required.'
    return false
  }

  if (Number(loyaltyForm.points_delta || 0) === 0) {
    formError.value = 'Points change cannot be zero.'
    return false
  }

  return true
}

async function submitCustomer() {
  clearFeedback()
  saving.value = true

  try {
    if (!validateCustomer()) return
    customerData.value = await saveCustomerProfile(editingCustomer.value?.id, {
      ...customerForm,
      birth_date: normalizeDate(customerForm.birth_date),
    })
    customerDialogVisible.value = false
    successMessage.value = 'Customer profile was saved.'
  } catch (saveError) {
    formError.value = saveError.message
  } finally {
    saving.value = false
  }
}

async function submitAccountEntry() {
  clearFeedback()
  saving.value = true

  try {
    if (!validateAccountEntry()) return
    customerData.value = await postCustomerAccountEntry({
      ...accountForm,
      amount: Number(accountForm.amount || 0),
    })
    accountDialogVisible.value = false
    successMessage.value = 'Customer account entry was posted.'
  } catch (saveError) {
    formError.value = saveError.message
  } finally {
    saving.value = false
  }
}

async function submitLoyalty() {
  clearFeedback()
  saving.value = true

  try {
    if (!validateLoyalty()) return
    customerData.value = await adjustCustomerLoyalty({
      ...loyaltyForm,
      points_delta: Number(loyaltyForm.points_delta || 0),
    })
    loyaltyDialogVisible.value = false
    successMessage.value = 'Customer loyalty points were adjusted.'
  } catch (saveError) {
    formError.value = saveError.message
  } finally {
    saving.value = false
  }
}

async function voidEntry(entry) {
  const reason = window.prompt(`Reason for voiding ${entryTypeLabel(entry.entry_type)}?`) || ''
  if (!reason.trim()) return

  loading.value = true
  error.value = ''
  successMessage.value = ''

  try {
    customerData.value = await voidCustomerAccountEntry(entry.id, reason)
    successMessage.value = 'Customer account entry was voided.'
  } catch (voidError) {
    error.value = voidError.message
  } finally {
    loading.value = false
  }
}

function signedCurrency(value) {
  const amount = Number(value || 0)
  if (amount === 0) return '-'
  return `${amount > 0 ? '+' : '-'}${formatCurrency(Math.abs(amount))}`
}

function signedNumber(value) {
  const amount = Number(value || 0)
  return `${amount > 0 ? '+' : ''}${formatNumber(amount)}`
}

function customerTypeLabel(value) {
  if (value === 'senior') return 'Senior'
  if (value === 'pwd') return 'PWD'
  if (value === 'company') return 'Company'
  return 'Regular'
}

function customerTypeSeverity(value) {
  if (value === 'senior' || value === 'pwd') return 'success'
  if (value === 'company') return 'info'
  return 'secondary'
}

function entryTypeLabel(value) {
  const labels = {
    credit_sale: 'Credit sale',
    payment: 'Payment',
    store_credit_issue: 'Store credit issued',
    store_credit_use: 'Store credit used',
    adjustment: 'Adjustment',
    write_off: 'Write off',
    return_credit: 'Return credit',
  }

  return labels[value] || value || '-'
}

function loyaltyTypeLabel(value) {
  const labels = {
    earn: 'Earned',
    redeem: 'Redeemed',
    adjust: 'Adjustment',
    void: 'Voided',
  }

  return labels[value] || value || '-'
}

function statusLabel(value) {
  if (value === 'completed') return 'Completed'
  if (value === 'voided') return 'Voided'
  if (value === 'refunded') return 'Refunded'
  return value || '-'
}

function statusSeverity(value) {
  if (value === 'completed') return 'success'
  if (value === 'voided') return 'danger'
  if (value === 'refunded') return 'warn'
  return 'secondary'
}

function formatDateTime(value) {
  if (!value) return '-'

  return new Intl.DateTimeFormat('en-PH', {
    month: 'short',
    day: '2-digit',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  }).format(new Date(value))
}

onMounted(loadCustomers)
</script>
