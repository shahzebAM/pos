<template>
  <section class="page-stack">
    <section class="page-hero">
      <div>
        <p class="eyebrow">Module 13</p>
        <h2>Returns, refunds, exchanges, voids, and credit memos.</h2>
        <p>
          Process sales returns from saved invoices, restore sellable stock by
          original batch, issue refunds or store-credit memos, track exchange
          credits, and keep voids aligned with BIR controls.
        </p>
      </div>

      <form class="filter-panel" @submit.prevent="loadReturns">
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
            :disabled="isBranchLocked"
            fluid
          />
        </label>
        <label>
          Search
          <PInputText v-model.trim="filters.search" placeholder="Invoice, return, customer" fluid />
        </label>
        <PButton type="submit" icon="pi pi-refresh" label="Refresh" :loading="loading" />
      </form>
    </section>

    <PMessage v-if="error" severity="error" :closable="false" class="setup-message">
      {{ error }}
    </PMessage>

    <PMessage v-if="successMessage" severity="success" :closable="false" class="setup-message">
      {{ successMessage }}
    </PMessage>

    <section v-if="loading && !returnData" class="stats-grid">
      <PSkeleton v-for="item in 6" :key="item" height="8rem" border-radius="8px" />
    </section>

    <template v-else-if="returnData">
      <section class="stats-grid">
        <MetricCard label="Returns" :value="formatNumber(returnData.summary.return_count)" :caption="periodLabel" icon="pi pi-undo" />
        <MetricCard label="Returned value" :value="formatCurrency(returnData.summary.total_return_amount)" icon="pi pi-replay" tone="blue" />
        <MetricCard label="Refunded" :value="formatCurrency(returnData.summary.refund_amount)" icon="pi pi-wallet" tone="gold" />
        <MetricCard label="Credit memos" :value="formatCurrency(returnData.summary.credit_memo_amount)" icon="pi pi-file-edit" tone="purple" />
        <MetricCard label="Open credit" :value="formatCurrency(returnData.summary.open_credit_memo_amount)" icon="pi pi-ticket" tone="green" />
        <MetricCard label="Voids" :value="formatNumber(returnData.summary.void_count)" icon="pi pi-ban" tone="red" />
      </section>

      <section class="analytics-grid">
        <BarChart
          title="Daily returned value"
          eyebrow="Return trend"
          :rows="returnData.daily_returns"
          key-field="business_date"
          label-field="label"
          value-field="return_amount"
          caption="Completed returns"
        />
        <BarChart
          title="Returns by branch"
          eyebrow="Branch comparison"
          :rows="returnData.branch_summary"
          key-field="branch_id"
          label-field="branch_name"
          value-field="return_amount"
          caption="Return value"
        />
      </section>

      <section class="panel">
        <div class="table-toolbar product-toolbar">
          <div>
            <p class="eyebrow">Eligible invoices</p>
            <h2>Sales available for return</h2>
          </div>
          <span class="search-field">
            <i class="pi pi-search" />
            <PInputText v-model.trim="orderSearch" placeholder="Search invoice, customer, cashier" />
          </span>
        </div>

        <PDataTable
          :value="filteredOrders"
          data-key="id"
          responsive-layout="stack"
          breakpoint="900px"
          size="small"
          striped-rows
          paginator
          :rows="8"
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
          <PColumn field="customer_name" header="Customer">
            <template #body="{ data }">{{ data.customer_name || 'Walk-in' }}</template>
          </PColumn>
          <PColumn field="cashier_name" header="Cashier" />
          <PColumn field="total" header="Invoice total">
            <template #body="{ data }">{{ formatCurrency(data.total) }}</template>
          </PColumn>
          <PColumn field="returnable_quantity" header="Returnable">
            <template #body="{ data }">
              <PTag :value="`${formatNumber(data.returnable_quantity)} item(s)`" severity="success" />
            </template>
          </PColumn>
          <PColumn header="Actions">
            <template #body="{ data }">
              <div class="table-actions">
                <PButton
                  icon="pi pi-undo"
                  text
                  rounded
                  aria-label="Process return"
                  :disabled="!returnData.can_manage_returns"
                  @click="openReturnDialog(data)"
                />
                <PButton
                  icon="pi pi-ban"
                  text
                  rounded
                  severity="danger"
                  aria-label="Void invoice"
                  :disabled="!returnData.can_void_returns"
                  @click="openReturnDialog(data, 'void')"
                />
              </div>
            </template>
          </PColumn>
        </PDataTable>
      </section>

      <section class="panel">
        <div class="table-toolbar product-toolbar">
          <div>
            <p class="eyebrow">Return ledger</p>
            <h2>Refunds, exchanges, voids, and credit memos</h2>
          </div>
          <span class="search-field">
            <i class="pi pi-search" />
            <PInputText v-model.trim="returnSearch" placeholder="Search return, invoice, reason" />
          </span>
        </div>

        <PDataTable
          :value="filteredReturns"
          data-key="id"
          responsive-layout="stack"
          breakpoint="900px"
          size="small"
          striped-rows
          paginator
          :rows="10"
        >
          <PColumn field="return_number" header="Return">
            <template #body="{ data }">
              <div class="branch-cell">
                <strong>{{ data.return_number }}</strong>
                <small>{{ formatDateTime(data.created_at) }}</small>
              </div>
            </template>
          </PColumn>
          <PColumn field="return_type" header="Type">
            <template #body="{ data }">
              <PTag :value="returnTypeLabel(data.return_type)" :severity="returnTypeSeverity(data.return_type)" />
            </template>
          </PColumn>
          <PColumn field="invoice_number" header="Invoice" />
          <PColumn field="branch_name" header="Branch" />
          <PColumn field="reason_name" header="Reason">
            <template #body="{ data }">
              {{ data.reason_name }}
              <small v-if="data.reason_note" class="muted-block">{{ data.reason_note }}</small>
            </template>
          </PColumn>
          <PColumn field="total_return_amount" header="Returned">
            <template #body="{ data }">{{ formatCurrency(data.total_return_amount) }}</template>
          </PColumn>
          <PColumn field="refund_amount" header="Refund">
            <template #body="{ data }">{{ formatCurrency(data.refund_amount) }}</template>
          </PColumn>
          <PColumn field="credit_memo_number" header="Credit memo">
            <template #body="{ data }">
              <span>{{ data.credit_memo_number || '-' }}</span>
              <small v-if="data.credit_memo_number" class="muted-block">{{ formatCurrency(data.credit_memo_amount) }}</small>
            </template>
          </PColumn>
        </PDataTable>
      </section>

      <section class="analytics-grid">
        <section class="panel">
          <div class="panel__header">
            <div>
              <p class="eyebrow">Credit memos</p>
              <h2>Store-credit balance ledger</h2>
            </div>
          </div>

          <PDataTable
            :value="returnData.credit_memos"
            data-key="id"
            responsive-layout="stack"
            breakpoint="860px"
            size="small"
            striped-rows
            paginator
            :rows="8"
          >
            <PColumn field="credit_memo_number" header="Memo">
              <template #body="{ data }">
                <div class="branch-cell">
                  <strong>{{ data.credit_memo_number }}</strong>
                  <small>{{ data.return_number }} - {{ data.invoice_number }}</small>
                </div>
              </template>
            </PColumn>
            <PColumn field="branch_name" header="Branch" />
            <PColumn field="customer_name" header="Customer" />
            <PColumn field="available_amount" header="Available">
              <template #body="{ data }">{{ formatCurrency(data.available_amount) }}</template>
            </PColumn>
            <PColumn field="status" header="Status">
              <template #body="{ data }">
                <PTag :value="statusLabel(data.status)" :severity="statusSeverity(data.status)" />
              </template>
            </PColumn>
          </PDataTable>
        </section>

        <section class="panel">
          <div class="panel__header">
            <div>
              <p class="eyebrow">Branch results</p>
              <h2>Return value by branch</h2>
            </div>
          </div>

          <PDataTable
            :value="returnData.branch_summary"
            data-key="branch_id"
            responsive-layout="stack"
            breakpoint="860px"
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
            <PColumn field="returns" header="Returns" />
            <PColumn field="return_amount" header="Returned">
              <template #body="{ data }">{{ formatCurrency(data.return_amount) }}</template>
            </PColumn>
            <PColumn field="refund_amount" header="Refunded">
              <template #body="{ data }">{{ formatCurrency(data.refund_amount) }}</template>
            </PColumn>
            <PColumn field="void_count" header="Voids" />
          </PDataTable>
        </section>
      </section>
    </template>

    <PDialog
      v-model:visible="returnDialogVisible"
      modal
      header="Process return"
      class="branch-dialog"
      :style="{ width: 'min(980px, 96vw)' }"
    >
      <form v-if="selectedOrder" class="dialog-form" @submit.prevent="submitReturn">
        <PMessage v-if="formError" severity="error" :closable="false" class="dialog-message">
          {{ formError }}
        </PMessage>

        <div class="copy-panel">
          <div>
            <h2>{{ selectedOrder.invoice_number }}</h2>
            <p>{{ selectedOrder.branch_name }} - {{ selectedOrder.customer_name || 'Walk-in' }}</p>
          </div>
          <PTag :value="formatCurrency(returnTotal)" severity="info" />
        </div>

        <div class="form-grid">
          <label>
            Return type
            <PSelect v-model="returnForm.return_type" :options="availableReturnTypes" option-label="label" option-value="value" fluid />
          </label>
          <label>
            Reason
            <PSelect v-model="returnForm.reason_id" :options="returnData?.reasons || []" option-label="name" option-value="id" fluid />
          </label>
          <label>
            Refund method
            <PSelect
              v-model="returnForm.refund_method"
              :options="refundMethodOptions"
              option-label="label"
              option-value="value"
              :disabled="returnForm.return_type === 'exchange' || returnForm.return_type === 'credit_memo'"
              fluid
            />
          </label>
          <label>
            Reference
            <PInputText v-model.trim="returnForm.refund_reference" placeholder="Refund, card, wallet, or approval reference" fluid />
          </label>
        </div>

        <label>
          Reason note
          <PTextarea v-model.trim="returnForm.reason_note" rows="2" auto-resize fluid placeholder="Required for some reasons" />
        </label>

        <div class="dialog-actions">
          <PButton type="button" icon="pi pi-check-square" label="Full return" outlined @click="setAllReturnQuantities" />
          <PButton type="button" icon="pi pi-times" label="Clear items" outlined @click="clearReturnQuantities" />
        </div>

        <PDataTable
          :value="returnItems"
          data-key="id"
          responsive-layout="stack"
          breakpoint="860px"
          size="small"
          striped-rows
        >
          <PColumn field="product_name" header="Item">
            <template #body="{ data }">
              <div class="branch-cell">
                <strong>{{ data.product_name }}</strong>
                <small>{{ data.variant_name || data.sku }} - {{ formatCurrency(data.unit_price) }}</small>
              </div>
            </template>
          </PColumn>
          <PColumn field="returnable_quantity" header="Available">
            <template #body="{ data }">{{ formatNumber(data.returnable_quantity) }}</template>
          </PColumn>
          <PColumn header="Return qty">
            <template #body="{ data }">
              <PInputNumber
                v-model="data.requested_quantity"
                :min="0"
                :max="data.returnable_quantity"
                :use-grouping="false"
                :disabled="returnForm.return_type === 'void'"
                fluid
              />
            </template>
          </PColumn>
          <PColumn header="Condition">
            <template #body="{ data }">
              <PSelect v-model="data.condition" :options="conditionOptions" option-label="label" option-value="value" fluid />
            </template>
          </PColumn>
          <PColumn header="Disposition">
            <template #body="{ data }">
              <PSelect
                v-model="data.disposition"
                :options="dispositionOptions"
                option-label="label"
                option-value="value"
                :disabled="returnForm.return_type === 'void'"
                fluid
              />
            </template>
          </PColumn>
          <PColumn header="Line value">
            <template #body="{ data }">{{ formatCurrency(lineReturnAmount(data)) }}</template>
          </PColumn>
        </PDataTable>

        <label>
          Notes
          <PTextarea v-model.trim="returnForm.notes" rows="3" auto-resize fluid placeholder="Optional internal note" />
        </label>

        <div class="checkout-totals">
          <span>Return value <strong>{{ formatCurrency(returnTotal) }}</strong></span>
          <span>Refund amount <strong>{{ formatCurrency(refundPreview) }}</strong></span>
          <span>Credit memo <strong>{{ formatCurrency(creditMemoPreview) }}</strong></span>
        </div>

        <div class="dialog-actions">
          <PButton type="button" label="Cancel" severity="secondary" outlined @click="returnDialogVisible = false" />
          <PButton type="submit" icon="pi pi-save" label="Complete return" :loading="saving" :disabled="!canSubmitReturn" />
        </div>
      </form>
    </PDialog>
  </section>
</template>

<script setup>
import { computed, onMounted, reactive, ref, watch } from 'vue'
import { useRoute } from 'vue-router'
import BarChart from '../components/BarChart.vue'
import MetricCard from '../components/MetricCard.vue'
import { addDaysISO, formatCurrency, formatDate, formatNumber, toISODate, todayISO } from '../lib/formatters'
import { fetchReturnManagement, processReturn } from '../services/returnService'
import { useAuthStore } from '../stores/authStore'

const auth = useAuthStore()
const route = useRoute()
const loading = ref(false)
const saving = ref(false)
const error = ref('')
const successMessage = ref('')
const formError = ref('')
const returnData = ref(null)
const orderSearch = ref('')
const returnSearch = ref('')
const selectedOrder = ref(null)
const returnItems = ref([])
const returnDialogVisible = ref(false)

const filters = reactive({
  from: new Date(`${addDaysISO(-29)}T00:00:00`),
  to: new Date(`${todayISO()}T00:00:00`),
  branchId: null,
  search: '',
})

const returnForm = reactive(createReturnForm())

const returnTypeOptions = [
  { label: 'Refund / return', value: 'refund' },
  { label: 'Exchange credit', value: 'exchange' },
  { label: 'Credit memo', value: 'credit_memo' },
  { label: 'Void invoice', value: 'void' },
]

const refundMethodOptions = [
  { label: 'Cash', value: 'cash' },
  { label: 'Card', value: 'card' },
  { label: 'GCash', value: 'gcash' },
  { label: 'Maya', value: 'maya' },
  { label: 'Bank transfer', value: 'bank_transfer' },
  { label: 'Store credit', value: 'store_credit' },
  { label: 'COD', value: 'cod' },
]

const conditionOptions = [
  { label: 'Good', value: 'good' },
  { label: 'Damaged', value: 'damaged' },
  { label: 'Expired', value: 'expired' },
  { label: 'Wrong item', value: 'wrong_item' },
  { label: 'Not returnable', value: 'not_returnable' },
]

const dispositionOptions = [
  { label: 'Return to stock', value: 'return_to_stock' },
  { label: 'Damaged', value: 'damaged' },
  { label: 'Expired', value: 'expired' },
  { label: 'Write off', value: 'write_off' },
]

const branchOptions = computed(() => [
  { id: null, name: 'All branches' },
  ...(returnData.value?.branches || []),
])
const isBranchLocked = computed(() => ['manager', 'cashier'].includes(auth.state.profile?.role))
const availableReturnTypes = computed(() =>
  returnTypeOptions.filter((option) => option.value !== 'void' || returnData.value?.can_void_returns),
)
const selectedReason = computed(() => (returnData.value?.reasons || []).find((reason) => reason.id === returnForm.reason_id))
const periodLabel = computed(() => {
  const from = returnData.value?.period?.from || toISODate(filters.from)
  const to = returnData.value?.period?.to || toISODate(filters.to)
  return `${formatDate(from)} to ${formatDate(to)}`
})
const filteredOrders = computed(() => {
  const query = orderSearch.value.toLowerCase()
  const rows = returnData.value?.eligible_orders || []
  if (!query) return rows

  return rows.filter((order) =>
    [order.invoice_number, order.order_number, order.customer_name, order.branch_name, order.cashier_name]
      .filter(Boolean)
      .some((value) => String(value).toLowerCase().includes(query)),
  )
})
const filteredReturns = computed(() => {
  const query = returnSearch.value.toLowerCase()
  const rows = returnData.value?.returns || []
  if (!query) return rows

  return rows.filter((row) =>
    [row.return_number, row.return_type, row.invoice_number, row.order_number, row.branch_name, row.reason_name, row.customer_name]
      .filter(Boolean)
      .some((value) => String(value).toLowerCase().includes(query)),
  )
})
const returnTotal = computed(() => roundMoney(returnItems.value.reduce((sum, item) => sum + lineReturnAmount(item), 0)))
const creditMemoPreview = computed(() =>
  returnForm.return_type === 'exchange' || returnForm.return_type === 'credit_memo' || returnForm.refund_method === 'store_credit'
    ? returnTotal.value
    : 0,
)
const refundPreview = computed(() => (creditMemoPreview.value > 0 ? 0 : returnForm.return_type === 'void' ? selectedOrder.value?.total || 0 : returnTotal.value))
const canSubmitReturn = computed(() => {
  if (!selectedOrder.value || !returnForm.reason_id || saving.value) return false
  if (returnForm.return_type === 'void' && !returnData.value?.can_void_returns) return false
  if (returnForm.return_type !== 'void' && !returnData.value?.can_manage_returns) return false
  if (selectedReason.value?.requires_note && !returnForm.reason_note.trim()) return false
  return returnTotal.value > 0
})

watch(
  () => returnForm.return_type,
  (value) => {
    if (value === 'exchange' || value === 'credit_memo') {
      returnForm.refund_method = 'store_credit'
    }
    if (value === 'void') {
      returnForm.refund_method = 'cash'
      setAllReturnQuantities()
      returnItems.value.forEach((item) => {
        item.condition = 'good'
        item.disposition = 'return_to_stock'
      })
    }
  },
)

function createReturnForm() {
  return {
    return_type: 'refund',
    reason_id: null,
    reason_note: '',
    refund_method: 'cash',
    refund_reference: '',
    notes: '',
  }
}

function roundMoney(value) {
  return Math.round(Number(value || 0) * 100) / 100
}

function lineReturnAmount(item) {
  if (!item?.quantity) return 0
  const quantity = Math.min(Number(item.requested_quantity || 0), Number(item.returnable_quantity || 0))
  return roundMoney((Number(item.net_amount || 0) / Number(item.quantity || 1)) * quantity)
}

function resetReturnForm(type = 'refund') {
  Object.assign(returnForm, createReturnForm(), { return_type: type })
  if (type === 'exchange' || type === 'credit_memo') returnForm.refund_method = 'store_credit'
}

function setAllReturnQuantities() {
  returnItems.value.forEach((item) => {
    item.requested_quantity = item.returnable_quantity
  })
}

function clearReturnQuantities() {
  if (returnForm.return_type === 'void') return
  returnItems.value.forEach((item) => {
    item.requested_quantity = 0
  })
}

function openReturnDialog(order, type = 'refund') {
  selectedOrder.value = order
  returnItems.value = order.items.map((item) => ({ ...item, requested_quantity: type === 'void' ? item.returnable_quantity : 0 }))
  resetReturnForm(type)
  if (type === 'void') setAllReturnQuantities()
  formError.value = ''
  returnDialogVisible.value = true
}

function returnTypeLabel(value) {
  return returnTypeOptions.find((option) => option.value === value)?.label || value || '-'
}

function returnTypeSeverity(value) {
  if (value === 'void') return 'danger'
  if (value === 'exchange') return 'warn'
  if (value === 'credit_memo') return 'info'
  return 'success'
}

function statusLabel(value) {
  if (value === 'open') return 'Open'
  if (value === 'used') return 'Used'
  if (value === 'voided') return 'Voided'
  if (value === 'expired') return 'Expired'
  return value || '-'
}

function statusSeverity(value) {
  if (value === 'open') return 'success'
  if (value === 'used') return 'info'
  if (value === 'expired') return 'warn'
  if (value === 'voided') return 'danger'
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

function normalizeDate(value) {
  return toISODate(value) || null
}

async function loadReturns() {
  loading.value = true
  error.value = ''
  successMessage.value = ''

  try {
    returnData.value = await fetchReturnManagement({
      from: normalizeDate(filters.from),
      to: normalizeDate(filters.to),
      branchId: filters.branchId,
      search: filters.search,
    })

    if (isBranchLocked.value && !filters.branchId) {
      filters.branchId = returnData.value.branches[0]?.id || null
    }

    openOrderFromRoute()
  } catch (loadError) {
    error.value = loadError.message
  } finally {
    loading.value = false
  }
}

function openOrderFromRoute() {
  const orderId = route.query.order
  if (!orderId || returnDialogVisible.value) return

  const order = returnData.value?.eligible_orders?.find((row) => row.id === orderId)
  if (order) {
    openReturnDialog(order)
  }
}

async function submitReturn() {
  formError.value = ''
  saving.value = true

  try {
    const payload = {
      original_order_id: selectedOrder.value.id,
      customer_name: selectedOrder.value.customer_name,
      return_type: returnForm.return_type,
      reason_id: returnForm.reason_id,
      reason_note: returnForm.reason_note,
      refund_method: returnForm.refund_method,
      refund_reference: returnForm.refund_reference,
      notes: returnForm.notes,
      items: returnItems.value
        .filter((item) => Number(item.requested_quantity || 0) > 0)
        .map((item) => ({
          order_item_id: item.id,
          quantity: Number(item.requested_quantity || 0),
          condition: item.condition,
          disposition: item.disposition,
        })),
    }

    returnData.value = await processReturn(payload)
    returnDialogVisible.value = false
    successMessage.value = `${returnData.value.processed_return_number || 'Return'} completed.`
  } catch (saveError) {
    formError.value = saveError.message
  } finally {
    saving.value = false
  }
}

onMounted(loadReturns)
</script>
