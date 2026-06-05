<template>
  <section class="page-stack">
    <section class="page-hero">
      <div>
        <p class="eyebrow">Module 15</p>
        <h2>Supplier profiles, payables, purchase history, and supplier payments.</h2>
        <p>
          Manage supplier records, monitor overdue payables by branch, post supplier payments against invoices,
          and review supplier purchase activity from goods received notes.
        </p>
      </div>

      <form class="filter-panel" @submit.prevent="loadSuppliers">
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
          Supplier
          <PSelect
            v-model="filters.supplierId"
            :options="supplierFilterOptions"
            option-label="label"
            option-value="value"
            placeholder="All suppliers"
            fluid
          />
        </label>
        <label>
          Search
          <PInputText v-model.trim="filters.search" placeholder="Supplier, invoice, PO, payment" fluid />
        </label>
        <div class="dialog-actions">
          <PButton type="submit" icon="pi pi-refresh" label="Refresh" :loading="loading" />
          <PButton type="button" icon="pi pi-plus" label="Supplier" :disabled="!canManageSuppliers" @click="openSupplier" />
          <PButton type="button" icon="pi pi-wallet" label="Payment" outlined :disabled="!canPaySuppliers" @click="openPayment" />
        </div>
      </form>
    </section>

    <PMessage v-if="error" severity="error" :closable="false" class="setup-message">
      {{ error }}
    </PMessage>

    <PMessage v-if="successMessage" severity="success" :closable="false" class="setup-message">
      {{ successMessage }}
    </PMessage>

    <section v-if="loading && !supplierData" class="stats-grid">
      <PSkeleton v-for="item in 6" :key="item" height="8rem" border-radius="8px" />
    </section>

    <template v-else-if="supplierData">
      <section class="stats-grid">
        <MetricCard label="Suppliers" :value="formatNumber(supplierData.summary.supplier_count)" :caption="periodLabel" icon="pi pi-address-book" />
        <MetricCard label="Payables" :value="formatCurrency(supplierData.summary.payable_amount)" icon="pi pi-wallet" tone="gold" />
        <MetricCard label="Overdue" :value="formatCurrency(supplierData.summary.overdue_amount)" :caption="`${formatNumber(supplierData.summary.overdue_invoices)} bill(s)`" icon="pi pi-clock" tone="red" />
        <MetricCard label="Purchases" :value="formatCurrency(supplierData.summary.purchase_value)" icon="pi pi-shopping-bag" tone="blue" />
        <MetricCard label="Payments" :value="formatCurrency(supplierData.summary.paid_amount)" :caption="`${formatNumber(supplierData.summary.payment_count)} posted`" icon="pi pi-credit-card" tone="green" />
        <MetricCard label="Open POs" :value="formatNumber(supplierData.summary.open_purchase_orders)" icon="pi pi-file-edit" tone="purple" />
      </section>

      <section class="analytics-grid">
        <BarChart
          title="Supplier payments by day"
          eyebrow="Payment trend"
          :rows="supplierData.daily_payments"
          key-field="business_date"
          label-field="label"
          value-field="paid_amount"
          caption="Posted payments"
        />
        <BarChart
          title="Top suppliers by purchases"
          eyebrow="Supplier performance"
          :rows="supplierData.top_suppliers"
          key-field="id"
          label-field="name"
          value-field="received_value"
          caption="Received value"
        />
      </section>

      <section class="panel">
        <div class="table-toolbar product-toolbar">
          <div>
            <p class="eyebrow">Supplier directory</p>
            <h2>Profiles, terms, and balances</h2>
          </div>
          <span class="search-field">
            <i class="pi pi-search" />
            <PInputText v-model.trim="supplierSearch" placeholder="Search suppliers" />
          </span>
        </div>

        <PDataTable
          :value="filteredSuppliers"
          data-key="id"
          responsive-layout="stack"
          breakpoint="920px"
          size="small"
          striped-rows
          paginator
          :rows="10"
        >
          <PColumn field="name" header="Supplier">
            <template #body="{ data }">
              <div class="branch-cell">
                <strong>{{ data.name }}</strong>
                <small>{{ data.supplier_code }} - {{ data.tin || 'No TIN' }}</small>
              </div>
            </template>
          </PColumn>
          <PColumn field="status" header="Status">
            <template #body="{ data }">
              <PTag :value="supplierStatusLabel(data)" :severity="supplierStatusSeverity(data)" />
              <small class="muted-block">{{ methodLabel(data.default_payment_method) }} default</small>
            </template>
          </PColumn>
          <PColumn field="contact_person" header="Contact">
            <template #body="{ data }">
              {{ data.contact_person || '-' }}
              <small class="muted-block">{{ data.phone || data.email || 'No contact details' }}</small>
            </template>
          </PColumn>
          <PColumn field="payment_terms_days" header="Terms">
            <template #body="{ data }">
              {{ formatNumber(data.payment_terms_days) }} days
              <small class="muted-block">Lead {{ formatNumber(data.lead_time_days) }} days</small>
            </template>
          </PColumn>
          <PColumn field="payable_amount" header="Payable">
            <template #body="{ data }">
              {{ formatCurrency(data.payable_amount) }}
              <small class="muted-block">Overdue {{ formatCurrency(data.overdue_amount) }}</small>
            </template>
          </PColumn>
          <PColumn field="received_value" header="Purchases">
            <template #body="{ data }">
              {{ formatCurrency(data.received_value) }}
              <small class="muted-block">{{ formatNumber(data.receipt_count) }} GRN(s)</small>
            </template>
          </PColumn>
          <PColumn header="Actions">
            <template #body="{ data }">
              <div class="table-actions">
                <PButton
                  icon="pi pi-pencil"
                  text
                  rounded
                  aria-label="Edit supplier"
                  :disabled="!canManageSuppliers"
                  @click="openSupplier(data)"
                />
                <PButton
                  icon="pi pi-wallet"
                  text
                  rounded
                  aria-label="Pay supplier"
                  :disabled="!canPaySuppliers"
                  @click="openPayment(data)"
                />
              </div>
            </template>
          </PColumn>
        </PDataTable>
      </section>

      <section class="analytics-grid">
        <section class="panel">
          <div class="table-toolbar product-toolbar">
            <div>
              <p class="eyebrow">Payables</p>
              <h2>Supplier invoices and balances</h2>
            </div>
            <span class="search-field">
              <i class="pi pi-search" />
              <PInputText v-model.trim="invoiceSearch" placeholder="Search invoices" />
            </span>
          </div>

          <PDataTable
            :value="filteredInvoices"
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
                  <strong>{{ data.invoice_number }}</strong>
                  <small>{{ data.receipt_number || data.po_number || 'Direct invoice' }}</small>
                </div>
              </template>
            </PColumn>
            <PColumn field="supplier_name" header="Supplier" />
            <PColumn field="branch_name" header="Branch">
              <template #body="{ data }">{{ data.branch_code }} - {{ data.branch_name }}</template>
            </PColumn>
            <PColumn field="due_date" header="Due">
              <template #body="{ data }">
                {{ data.due_date ? formatDate(data.due_date) : '-' }}
                <small v-if="data.days_overdue" class="muted-block">{{ formatNumber(data.days_overdue) }} days overdue</small>
              </template>
            </PColumn>
            <PColumn field="balance_amount" header="Balance">
              <template #body="{ data }">
                {{ formatCurrency(data.balance_amount) }}
                <small class="muted-block">Paid {{ formatCurrency(data.paid_amount) }}</small>
              </template>
            </PColumn>
            <PColumn field="status" header="Status">
              <template #body="{ data }">
                <PTag :value="invoiceStatusLabel(data.status)" :severity="invoiceStatusSeverity(data)" />
              </template>
            </PColumn>
            <PColumn header="Actions">
              <template #body="{ data }">
                <PButton
                  icon="pi pi-wallet"
                  text
                  rounded
                  aria-label="Pay invoice"
                  :disabled="!canPaySuppliers || Number(data.balance_amount || 0) <= 0"
                  @click="openPayment(data)"
                />
              </template>
            </PColumn>
          </PDataTable>
        </section>

        <section class="panel">
          <div class="table-toolbar product-toolbar">
            <div>
              <p class="eyebrow">Payment ledger</p>
              <h2>Posted supplier payments</h2>
            </div>
            <span class="search-field">
              <i class="pi pi-search" />
              <PInputText v-model.trim="paymentSearch" placeholder="Search payments" />
            </span>
          </div>

          <PDataTable
            :value="filteredPayments"
            data-key="id"
            responsive-layout="stack"
            breakpoint="860px"
            size="small"
            striped-rows
            paginator
            :rows="8"
          >
            <PColumn field="payment_number" header="Payment">
              <template #body="{ data }">
                <div class="branch-cell">
                  <strong>{{ data.payment_number }}</strong>
                  <small>{{ formatDate(data.payment_date) }} - {{ data.invoice_number || 'Advance payment' }}</small>
                </div>
              </template>
            </PColumn>
            <PColumn field="supplier_name" header="Supplier" />
            <PColumn field="payment_method" header="Method">
              <template #body="{ data }">
                {{ methodLabel(data.payment_method) }}
                <small class="muted-block">{{ data.reference_number || 'No reference' }}</small>
              </template>
            </PColumn>
            <PColumn field="amount" header="Amount">
              <template #body="{ data }">{{ formatCurrency(data.amount) }}</template>
            </PColumn>
            <PColumn field="status" header="Status">
              <template #body="{ data }">
                <PTag :value="paymentStatusLabel(data.status)" :severity="paymentStatusSeverity(data.status)" />
              </template>
            </PColumn>
            <PColumn header="Actions">
              <template #body="{ data }">
                <PButton
                  icon="pi pi-ban"
                  text
                  rounded
                  severity="danger"
                  aria-label="Void supplier payment"
                  :disabled="!canPaySuppliers || data.status !== 'posted'"
                  @click="voidPayment(data)"
                />
              </template>
            </PColumn>
          </PDataTable>
        </section>
      </section>

      <section class="analytics-grid">
        <section class="panel">
          <div class="table-toolbar product-toolbar">
            <div>
              <p class="eyebrow">Purchase history</p>
              <h2>Goods received by supplier</h2>
            </div>
            <span class="search-field">
              <i class="pi pi-search" />
              <PInputText v-model.trim="historySearch" placeholder="Search GRN or supplier" />
            </span>
          </div>

          <PDataTable
            :value="filteredPurchaseHistory"
            data-key="id"
            responsive-layout="stack"
            breakpoint="860px"
            size="small"
            striped-rows
            paginator
            :rows="8"
          >
            <PColumn field="receipt_number" header="GRN">
              <template #body="{ data }">
                <div class="branch-cell">
                  <strong>{{ data.receipt_number }}</strong>
                  <small>{{ formatDate(data.receipt_date) }} - {{ data.po_number || 'Direct receiving' }}</small>
                </div>
              </template>
            </PColumn>
            <PColumn field="supplier_name" header="Supplier" />
            <PColumn field="branch_name" header="Branch" />
            <PColumn field="received_quantity" header="Qty">
              <template #body="{ data }">
                {{ formatNumber(data.received_quantity) }}
                <small class="muted-block">{{ formatNumber(data.item_count) }} item(s)</small>
              </template>
            </PColumn>
            <PColumn field="total_cost" header="Cost">
              <template #body="{ data }">{{ formatCurrency(data.total_cost) }}</template>
            </PColumn>
          </PDataTable>
        </section>

        <section class="panel">
          <div class="panel__header">
            <div>
              <p class="eyebrow">Branch payables</p>
              <h2>Supplier balances by branch</h2>
            </div>
          </div>

          <PDataTable
            :value="supplierData.branch_summary"
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
            <PColumn field="payable_amount" header="Payable">
              <template #body="{ data }">{{ formatCurrency(data.payable_amount) }}</template>
            </PColumn>
            <PColumn field="overdue_amount" header="Overdue">
              <template #body="{ data }">{{ formatCurrency(data.overdue_amount) }}</template>
            </PColumn>
            <PColumn field="paid_amount" header="Paid">
              <template #body="{ data }">{{ formatCurrency(data.paid_amount) }}</template>
            </PColumn>
          </PDataTable>
        </section>
      </section>
    </template>

    <PDialog
      v-model:visible="supplierDialogVisible"
      modal
      :header="editingSupplier ? 'Edit supplier' : 'Add supplier'"
      class="branch-dialog"
      :style="{ width: 'min(900px, 96vw)' }"
    >
      <form class="dialog-form" @submit.prevent="submitSupplier">
        <PMessage v-if="formError" severity="error" :closable="false" class="dialog-message">
          {{ formError }}
        </PMessage>

        <div class="form-grid">
          <label>
            Supplier name
            <PInputText v-model.trim="supplierForm.name" fluid />
          </label>
          <label>
            Supplier code
            <PInputText v-model.trim="supplierForm.supplier_code" placeholder="Auto-generated if blank" fluid />
          </label>
          <label>
            Branch context
            <PSelect
              v-model="supplierForm.branch_id"
              :options="branchOptions"
              option-label="name"
              option-value="id"
              :disabled="isBranchLocked"
              fluid
            />
          </label>
          <label>
            Status
            <PSelect v-model="supplierForm.status" :options="supplierStatusOptions" option-label="label" option-value="value" fluid />
          </label>
          <label>
            Contact person
            <PInputText v-model.trim="supplierForm.contact_person" fluid />
          </label>
          <label>
            Phone
            <PInputText v-model.trim="supplierForm.phone" fluid />
          </label>
          <label>
            Email
            <PInputText v-model.trim="supplierForm.email" fluid />
          </label>
          <label>
            TIN
            <PInputText v-model.trim="supplierForm.tin" fluid />
          </label>
          <label>
            Account number
            <PInputText v-model.trim="supplierForm.account_number" fluid />
          </label>
          <label>
            Default payment method
            <PSelect v-model="supplierForm.default_payment_method" :options="paymentMethodOptions" option-label="label" option-value="value" fluid />
          </label>
          <label>
            Payment terms
            <PInputNumber v-model="supplierForm.payment_terms_days" :min="0" :max="365" suffix=" days" fluid />
          </label>
          <label>
            Lead time
            <PInputNumber v-model="supplierForm.lead_time_days" :min="0" :max="365" suffix=" days" fluid />
          </label>
          <label>
            Credit limit
            <PInputNumber v-model="supplierForm.credit_limit" mode="currency" :currency="currencyCode" fluid />
          </label>
          <label>
            Withholding tax
            <PInputNumber v-model="supplierForm.withholding_tax_rate" :min="0" :max="100" suffix="%" fluid />
          </label>
          <label>
            Rating
            <PInputNumber v-model="supplierForm.rating" :min="1" :max="5" :use-grouping="false" fluid />
          </label>
          <label>
            Website
            <PInputText v-model.trim="supplierForm.website" fluid />
          </label>
        </div>

        <label>
          Address
          <PTextarea v-model.trim="supplierForm.address" rows="2" fluid />
        </label>
        <label>
          Notes
          <PTextarea v-model.trim="supplierForm.notes" rows="3" fluid />
        </label>

        <div class="dialog-actions">
          <PButton type="button" label="Cancel" severity="secondary" outlined @click="supplierDialogVisible = false" />
          <PButton type="submit" icon="pi pi-save" label="Save supplier" :loading="saving" />
        </div>
      </form>
    </PDialog>

    <PDialog
      v-model:visible="paymentDialogVisible"
      modal
      header="Post supplier payment"
      class="branch-dialog"
      :style="{ width: 'min(820px, 96vw)' }"
    >
      <form class="dialog-form" @submit.prevent="submitPayment">
        <PMessage v-if="formError" severity="error" :closable="false" class="dialog-message">
          {{ formError }}
        </PMessage>

        <div class="form-grid">
          <label>
            Branch
            <PSelect
              v-model="paymentForm.branch_id"
              :options="branchOptions"
              option-label="name"
              option-value="id"
              :disabled="isBranchLocked || Boolean(paymentForm.supplier_invoice_id)"
              fluid
            />
          </label>
          <label>
            Supplier
            <PSelect
              v-model="paymentForm.supplier_id"
              :options="supplierOptions"
              option-label="label"
              option-value="value"
              :disabled="Boolean(paymentForm.supplier_invoice_id)"
              fluid
            />
          </label>
          <label>
            Invoice
            <PSelect
              v-model="paymentForm.supplier_invoice_id"
              :options="paymentInvoiceOptions"
              option-label="label"
              option-value="value"
              placeholder="Optional"
              fluid
            />
          </label>
          <label>
            Payment date
            <PDatePicker v-model="paymentForm.payment_date" date-format="yy-mm-dd" show-icon fluid />
          </label>
          <label>
            Method
            <PSelect v-model="paymentForm.payment_method" :options="paymentMethodOptions" option-label="label" option-value="value" fluid />
          </label>
          <label>
            Amount
            <PInputNumber v-model="paymentForm.amount" mode="currency" :currency="currencyCode" fluid />
          </label>
          <label>
            Reference number
            <PInputText v-model.trim="paymentForm.reference_number" fluid />
          </label>
          <label>
            Invoice balance
            <PInputText :model-value="selectedPaymentInvoice ? formatCurrency(selectedPaymentInvoice.balance_amount) : 'No invoice selected'" disabled fluid />
          </label>
        </div>

        <label>
          Notes
          <PTextarea v-model.trim="paymentForm.notes" rows="3" fluid />
        </label>

        <div class="dialog-actions">
          <PButton type="button" label="Cancel" severity="secondary" outlined @click="paymentDialogVisible = false" />
          <PButton type="submit" icon="pi pi-check" label="Post payment" :loading="saving" />
        </div>
      </form>
    </PDialog>
  </section>
</template>

<script setup>
import { computed, onMounted, reactive, ref, watch } from 'vue'
import BarChart from '../components/BarChart.vue'
import MetricCard from '../components/MetricCard.vue'
import { addDaysISO, currencyCode, formatCurrency, formatDate, formatNumber, toISODate, todayISO } from '../lib/formatters'
import {
  fetchSupplierManagement,
  postSupplierPayment,
  saveSupplierProfile,
  voidSupplierPayment,
} from '../services/supplierService'
import { useAuthStore } from '../stores/authStore'

const auth = useAuthStore()
const loading = ref(false)
const saving = ref(false)
const error = ref('')
const successMessage = ref('')
const formError = ref('')
const supplierData = ref(null)
const supplierSearch = ref('')
const invoiceSearch = ref('')
const paymentSearch = ref('')
const historySearch = ref('')
const supplierDialogVisible = ref(false)
const paymentDialogVisible = ref(false)
const editingSupplier = ref(null)

const filters = reactive({
  from: new Date(`${addDaysISO(-89)}T00:00:00`),
  to: new Date(`${todayISO()}T00:00:00`),
  branchId: null,
  supplierId: null,
  search: '',
})

const supplierForm = reactive(createSupplierForm())
const paymentForm = reactive(createPaymentForm())

const supplierStatusOptions = [
  { label: 'Active', value: 'active' },
  { label: 'On hold', value: 'on_hold' },
  { label: 'Inactive', value: 'inactive' },
]

const paymentMethodOptions = [
  { label: 'Cash', value: 'cash' },
  { label: 'Check', value: 'check' },
  { label: 'Bank transfer', value: 'bank_transfer' },
  { label: 'Card', value: 'card' },
  { label: 'GCash', value: 'gcash' },
  { label: 'Maya', value: 'maya' },
  { label: 'Other', value: 'other' },
]

const isBranchLocked = computed(() => auth.state.profile?.role === 'manager')
const canManageSuppliers = computed(() => supplierData.value?.can_manage_suppliers && ['admin', 'manager'].includes(auth.state.profile?.role))
const canPaySuppliers = computed(() => supplierData.value?.can_pay_suppliers && ['admin', 'manager'].includes(auth.state.profile?.role))
const branchFilterOptions = computed(() => [{ id: null, name: 'All branches' }, ...(supplierData.value?.branches || [])])
const branchOptions = computed(() => supplierData.value?.branches || [])
const supplierFilterOptions = computed(() => [{ label: 'All suppliers', value: null }, ...supplierOptions.value])
const supplierOptions = computed(() =>
  (supplierData.value?.suppliers || []).map((supplier) => ({
    label: `${supplier.supplier_code} - ${supplier.name}`,
    value: supplier.id,
  })),
)
const selectedPaymentInvoice = computed(() =>
  (supplierData.value?.supplier_invoices || []).find((invoice) => invoice.id === paymentForm.supplier_invoice_id),
)
const paymentInvoiceOptions = computed(() => {
  const invoices = (supplierData.value?.supplier_invoices || [])
    .filter((invoice) => Number(invoice.balance_amount || 0) > 0)
    .filter((invoice) => !paymentForm.branch_id || invoice.branch_id === paymentForm.branch_id)
    .filter((invoice) => !paymentForm.supplier_id || invoice.supplier_id === paymentForm.supplier_id)
    .map((invoice) => ({
      label: `${invoice.invoice_number} - ${invoice.supplier_name} - ${formatCurrency(invoice.balance_amount)}`,
      value: invoice.id,
    }))

  return [{ label: 'No invoice / advance payment', value: null }, ...invoices]
})
const periodLabel = computed(() => {
  const from = supplierData.value?.period?.from || toISODate(filters.from)
  const to = supplierData.value?.period?.to || toISODate(filters.to)

  return `${formatDate(from)} to ${formatDate(to)}`
})

const filteredSuppliers = computed(() => {
  const query = supplierSearch.value.toLowerCase()
  const rows = supplierData.value?.suppliers || []
  if (!query) return rows

  return rows.filter((row) =>
    [row.supplier_code, row.name, row.contact_person, row.phone, row.email, row.tin, row.status]
      .filter(Boolean)
      .some((value) => String(value).toLowerCase().includes(query)),
  )
})

const filteredInvoices = computed(() => {
  const query = invoiceSearch.value.toLowerCase()
  const rows = supplierData.value?.supplier_invoices || []
  if (!query) return rows

  return rows.filter((row) =>
    [row.invoice_number, row.receipt_number, row.po_number, row.supplier_name, row.branch_name, row.status]
      .filter(Boolean)
      .some((value) => String(value).toLowerCase().includes(query)),
  )
})

const filteredPayments = computed(() => {
  const query = paymentSearch.value.toLowerCase()
  const rows = supplierData.value?.supplier_payments || []
  if (!query) return rows

  return rows.filter((row) =>
    [row.payment_number, row.invoice_number, row.supplier_name, row.branch_name, row.payment_method, row.reference_number, row.status]
      .filter(Boolean)
      .some((value) => String(value).toLowerCase().includes(query)),
  )
})

const filteredPurchaseHistory = computed(() => {
  const query = historySearch.value.toLowerCase()
  const rows = supplierData.value?.purchase_history || []
  if (!query) return rows

  return rows.filter((row) =>
    [row.receipt_number, row.supplier_invoice_number, row.po_number, row.supplier_name, row.branch_name]
      .filter(Boolean)
      .some((value) => String(value).toLowerCase().includes(query)),
  )
})

watch(
  () => paymentForm.supplier_invoice_id,
  (invoiceId) => {
    const invoice = (supplierData.value?.supplier_invoices || []).find((row) => row.id === invoiceId)
    if (!invoice) return

    paymentForm.branch_id = invoice.branch_id
    paymentForm.supplier_id = invoice.supplier_id
    paymentForm.amount = Number(invoice.balance_amount || 0)
  },
)

function createSupplierForm() {
  return {
    branch_id: null,
    supplier_code: '',
    name: '',
    contact_person: '',
    phone: '',
    email: '',
    tin: '',
    address: '',
    account_number: '',
    website: '',
    default_payment_method: 'bank_transfer',
    payment_terms_days: 30,
    credit_limit: 0,
    withholding_tax_rate: 0,
    lead_time_days: 0,
    rating: 3,
    status: 'active',
    is_active: true,
    notes: '',
  }
}

function createPaymentForm() {
  return {
    branch_id: null,
    supplier_id: null,
    supplier_invoice_id: null,
    payment_date: new Date(`${todayISO()}T00:00:00`),
    payment_method: 'bank_transfer',
    amount: 0,
    reference_number: '',
    notes: '',
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
  return filters.branchId || auth.state.profile?.branch_id || supplierData.value?.branches?.[0]?.id || null
}

function clearFeedback() {
  formError.value = ''
  error.value = ''
  successMessage.value = ''
}

async function loadSuppliers() {
  loading.value = true
  error.value = ''
  successMessage.value = ''

  try {
    supplierData.value = await fetchSupplierManagement({
      from: normalizeDate(filters.from),
      to: normalizeDate(filters.to),
      branchId: filters.branchId,
      supplierId: filters.supplierId,
      search: filters.search,
    })

    if (isBranchLocked.value && !filters.branchId) {
      filters.branchId = supplierData.value.branches[0]?.id || auth.state.profile?.branch_id || null
    }
  } catch (loadError) {
    error.value = loadError.message
  } finally {
    loading.value = false
  }
}

function openSupplier(supplier = null) {
  editingSupplier.value = supplier
  resetObject(supplierForm, {
    ...createSupplierForm(),
    ...(supplier || {}),
    branch_id: defaultBranchId(),
    status: supplier?.status || (supplier?.is_active === false ? 'inactive' : 'active'),
    is_active: supplier?.is_active !== false,
  })
  formError.value = ''
  supplierDialogVisible.value = true
}

function openPayment(row = null) {
  const invoiceLike = row?.invoice_number && row?.balance_amount !== undefined ? row : null
  const supplierLike = row?.supplier_code && !invoiceLike ? row : null

  resetObject(paymentForm, {
    ...createPaymentForm(),
    branch_id: invoiceLike?.branch_id || defaultBranchId(),
    supplier_id: invoiceLike?.supplier_id || supplierLike?.id || null,
    supplier_invoice_id: invoiceLike?.id || null,
    payment_method: supplierLike?.default_payment_method || invoiceLike?.default_payment_method || 'bank_transfer',
    amount: invoiceLike ? Number(invoiceLike.balance_amount || 0) : 0,
  })
  formError.value = ''
  paymentDialogVisible.value = true
}

function validateSupplier() {
  if (!supplierForm.name.trim()) {
    formError.value = 'Supplier name is required.'
    return false
  }

  if (!supplierForm.status) {
    formError.value = 'Supplier status is required.'
    return false
  }

  return true
}

function validatePayment() {
  if (!paymentForm.branch_id || !paymentForm.supplier_id) {
    formError.value = 'Branch and supplier are required for supplier payments.'
    return false
  }

  if (Number(paymentForm.amount || 0) <= 0) {
    formError.value = 'Payment amount must be greater than zero.'
    return false
  }

  if (selectedPaymentInvoice.value && Number(paymentForm.amount || 0) > Number(selectedPaymentInvoice.value.balance_amount || 0)) {
    formError.value = 'Payment amount cannot exceed the selected invoice balance.'
    return false
  }

  return true
}

async function submitSupplier() {
  clearFeedback()
  saving.value = true

  try {
    if (!validateSupplier()) return
    supplierData.value = await saveSupplierProfile(editingSupplier.value?.id, {
      ...supplierForm,
      branch_id: supplierForm.branch_id || defaultBranchId(),
      is_active: supplierForm.status !== 'inactive',
    })
    supplierDialogVisible.value = false
    successMessage.value = 'Supplier profile was saved.'
  } catch (saveError) {
    formError.value = saveError.message
  } finally {
    saving.value = false
  }
}

async function submitPayment() {
  clearFeedback()
  saving.value = true

  try {
    if (!validatePayment()) return
    supplierData.value = await postSupplierPayment({
      branch_id: paymentForm.branch_id,
      supplier_id: paymentForm.supplier_id,
      supplier_invoice_id: paymentForm.supplier_invoice_id,
      payment_date: normalizeDate(paymentForm.payment_date),
      payment_method: paymentForm.payment_method,
      amount: Number(paymentForm.amount || 0),
      reference_number: paymentForm.reference_number,
      notes: paymentForm.notes,
    })
    paymentDialogVisible.value = false
    successMessage.value = 'Supplier payment was posted.'
  } catch (saveError) {
    formError.value = saveError.message
  } finally {
    saving.value = false
  }
}

async function voidPayment(payment) {
  const reason = window.prompt(`Reason for voiding ${payment.payment_number}?`) || ''
  if (!reason.trim()) return

  loading.value = true
  error.value = ''
  successMessage.value = ''

  try {
    supplierData.value = await voidSupplierPayment(payment.id, reason)
    successMessage.value = `${payment.payment_number} was voided.`
  } catch (voidError) {
    error.value = voidError.message
  } finally {
    loading.value = false
  }
}

function supplierStatusLabel(supplier) {
  if (supplier.status === 'on_hold') return 'On hold'
  if (supplier.status === 'inactive' || supplier.is_active === false) return 'Inactive'
  return 'Active'
}

function supplierStatusSeverity(supplier) {
  if (supplier.status === 'on_hold') return 'warn'
  if (supplier.status === 'inactive' || supplier.is_active === false) return 'danger'
  return 'success'
}

function invoiceStatusLabel(value) {
  const labels = {
    pending: 'Pending',
    partial: 'Partial',
    paid: 'Paid',
    voided: 'Voided',
  }

  return labels[value] || value || '-'
}

function invoiceStatusSeverity(invoice) {
  if (invoice.status === 'paid') return 'success'
  if (invoice.status === 'voided') return 'danger'
  if (Number(invoice.days_overdue || 0) > 0) return 'danger'
  if (invoice.status === 'partial') return 'warn'
  return 'info'
}

function paymentStatusLabel(value) {
  return value === 'voided' ? 'Voided' : 'Posted'
}

function paymentStatusSeverity(value) {
  return value === 'voided' ? 'danger' : 'success'
}

function methodLabel(value) {
  const method = paymentMethodOptions.find((item) => item.value === value)
  return method?.label || value || '-'
}

onMounted(loadSuppliers)
</script>
