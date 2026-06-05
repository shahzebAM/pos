<template>
  <section class="page-stack">
    <section class="page-hero page-hero--compact">
      <div>
        <p class="eyebrow">Module 6</p>
        <h1>Stock Transfer</h1>
        <p>
          Request branch-to-branch transfers, approve source dispatch, receive
          stock into the destination branch, and track shortage or overage
          variance by product batch.
        </p>
      </div>

      <div class="action-panel">
        <PButton icon="pi pi-send" label="New transfer" :disabled="!canManageTransfers" @click="openCreate" />
        <PButton icon="pi pi-refresh" label="Refresh" outlined :loading="loading" @click="loadTransfers" />
      </div>
    </section>

    <PMessage v-if="!canManageTransfers" severity="warn" :closable="false" class="setup-message">
      You can view transfer activity with this role. Creating, approving, dispatching, and receiving transfers are admin/manager actions.
    </PMessage>

    <PMessage v-if="error" severity="error" :closable="false" class="setup-message">
      {{ error }}
    </PMessage>

    <PMessage v-if="successMessage" severity="success" :closable="false" class="setup-message">
      {{ successMessage }}
    </PMessage>

    <section v-if="loading && !transferData" class="stats-grid">
      <PSkeleton v-for="item in 6" :key="item" height="8rem" border-radius="8px" />
    </section>

    <template v-else-if="transferData">
      <section class="stats-grid">
        <MetricCard label="Transfers" :value="formatNumber(transferData.summary.total_transfers)" icon="pi pi-send" />
        <MetricCard label="Requested" :value="formatNumber(transferData.summary.requested)" icon="pi pi-clock" tone="blue" />
        <MetricCard label="Approved" :value="formatNumber(transferData.summary.approved)" icon="pi pi-check-circle" tone="gold" />
        <MetricCard label="Dispatched" :value="formatNumber(transferData.summary.dispatched)" icon="pi pi-truck" tone="purple" />
        <MetricCard label="Received" :value="formatNumber(transferData.summary.received)" icon="pi pi-inbox" tone="green" />
        <MetricCard label="Variance units" :value="formatNumber(transferData.summary.variance_units)" icon="pi pi-exclamation-circle" tone="red" />
      </section>

      <section class="panel">
        <div class="table-toolbar product-toolbar">
          <div>
            <p class="eyebrow">Transfer ledger</p>
            <h2>Requests, approvals, dispatch, and receiving</h2>
          </div>

          <div class="toolbar-controls">
            <span class="search-field">
              <i class="pi pi-search" />
              <PInputText v-model.trim="search" placeholder="Search transfer, branch, product" />
            </span>
            <PSelect
              v-model="selectedBranchId"
              :options="branchFilterOptions"
              option-label="label"
              option-value="value"
              class="compact-select"
              :disabled="!canFilterBranches"
            />
            <PSelect
              v-model="statusFilter"
              :options="statusFilterOptions"
              option-label="label"
              option-value="value"
              class="compact-select"
            />
          </div>
        </div>

        <PDataTable
          :value="filteredTransfers"
          data-key="id"
          responsive-layout="stack"
          breakpoint="980px"
          size="small"
          striped-rows
          paginator
          :rows="8"
        >
          <PColumn field="transfer_number" header="Transfer">
            <template #body="{ data }">
              <div class="branch-cell">
                <strong>{{ data.transfer_number }}</strong>
                <small>{{ formatDateTime(data.created_at) }}</small>
              </div>
            </template>
          </PColumn>
          <PColumn header="Route">
            <template #body="{ data }">
              <div class="transfer-route">
                <span>{{ data.from_branch_code }}</span>
                <i class="pi pi-arrow-right" />
                <span>{{ data.to_branch_code }}</span>
              </div>
              <small class="muted-block">{{ data.from_branch_name }} to {{ data.to_branch_name }}</small>
            </template>
          </PColumn>
          <PColumn field="status" header="Status">
            <template #body="{ data }">
              <PTag :value="statusLabel(data.status)" :severity="statusSeverity(data.status)" />
              <small class="muted-block">{{ formatNumber(data.item_count) }} item lines</small>
            </template>
          </PColumn>
          <PColumn header="Quantity">
            <template #body="{ data }">
              <strong>{{ formatNumber(quantityPrimary(data)) }}</strong>
              <small class="muted-block">{{ quantityLabel(data) }}</small>
            </template>
          </PColumn>
          <PColumn field="total_variance" header="Variance">
            <template #body="{ data }">
              <strong :class="{ 'negative-text': data.total_variance > 0 }">
                {{ formatNumber(data.total_variance) }}
              </strong>
              <small class="muted-block">absolute unit difference</small>
            </template>
          </PColumn>
          <PColumn field="requested_by_name" header="Requested by">
            <template #body="{ data }">
              {{ data.requested_by_name || data.requested_by_username || '-' }}
              <small class="muted-block">{{ data.notes || 'No notes' }}</small>
            </template>
          </PColumn>
          <PColumn header="Actions">
            <template #body="{ data }">
              <div class="table-actions transfer-actions">
                <PButton icon="pi pi-eye" text rounded aria-label="View transfer" @click="selectTransfer(data)" />
                <PButton
                  icon="pi pi-check"
                  text
                  rounded
                  aria-label="Approve transfer"
                  :disabled="!canApprove(data)"
                  @click="approveTransfer(data)"
                />
                <PButton
                  icon="pi pi-truck"
                  text
                  rounded
                  aria-label="Dispatch transfer"
                  :disabled="!canDispatch(data)"
                  @click="dispatchTransfer(data)"
                />
                <PButton
                  icon="pi pi-inbox"
                  text
                  rounded
                  aria-label="Receive transfer"
                  :disabled="!canReceive(data)"
                  @click="openReceive(data)"
                />
                <PButton
                  icon="pi pi-times"
                  text
                  rounded
                  severity="danger"
                  aria-label="Cancel transfer"
                  :disabled="!canCancel(data)"
                  @click="openCancel(data)"
                />
              </div>
            </template>
          </PColumn>
        </PDataTable>
      </section>

      <section v-if="selectedTransfer" class="analytics-grid transfer-detail-grid">
        <section class="panel">
          <div class="panel__header">
            <div>
              <p class="eyebrow">Selected transfer</p>
              <h2>{{ selectedTransfer.transfer_number }}</h2>
            </div>
            <PTag :value="statusLabel(selectedTransfer.status)" :severity="statusSeverity(selectedTransfer.status)" />
          </div>

          <div class="transfer-flow">
            <article
              v-for="stage in transferStages"
              :key="stage.value"
              :class="['transfer-stage', { 'transfer-stage--active': isStageComplete(selectedTransfer, stage.value) }]"
            >
              <i :class="stage.icon" />
              <div>
                <strong>{{ stage.label }}</strong>
                <small>{{ stageTimestamp(selectedTransfer, stage.value) || 'Pending' }}</small>
              </div>
            </article>
          </div>

          <div class="transfer-route-card">
            <div>
              <span>Source branch</span>
              <strong>{{ selectedTransfer.from_branch_name }}</strong>
              <small>{{ selectedTransfer.from_branch_code }}</small>
            </div>
            <i class="pi pi-arrow-right" />
            <div>
              <span>Destination branch</span>
              <strong>{{ selectedTransfer.to_branch_name }}</strong>
              <small>{{ selectedTransfer.to_branch_code }}</small>
            </div>
          </div>

          <div class="transfer-total-grid">
            <span>Requested <strong>{{ formatNumber(selectedTransfer.total_requested) }}</strong></span>
            <span>Approved <strong>{{ formatNumber(selectedTransfer.total_approved) }}</strong></span>
            <span>Dispatched <strong>{{ formatNumber(selectedTransfer.total_dispatched) }}</strong></span>
            <span>Received <strong>{{ formatNumber(selectedTransfer.total_received) }}</strong></span>
          </div>
        </section>

        <section class="panel">
          <div class="panel__header">
            <div>
              <p class="eyebrow">Items and FEFO batches</p>
              <h2>Dispatch and receive detail</h2>
            </div>
          </div>

          <div class="transfer-item-list">
            <article v-for="item in selectedTransfer.items" :key="item.id" class="transfer-item-card">
              <div class="transfer-item-card__header">
                <div>
                  <strong>{{ item.product_name }}</strong>
                  <small>{{ item.variant_name || 'Base product' }} - SKU {{ item.sku || '-' }}</small>
                </div>
                <PTag :value="varianceLabel(item.variance_quantity)" :severity="item.variance_quantity === 0 ? 'success' : 'danger'" />
              </div>

              <div class="transfer-total-grid transfer-total-grid--compact">
                <span>Requested <strong>{{ formatNumber(item.quantity_requested) }}</strong></span>
                <span>Approved <strong>{{ formatNumber(item.quantity_approved) }}</strong></span>
                <span>Dispatched <strong>{{ formatNumber(item.quantity_dispatched) }}</strong></span>
                <span>Received <strong>{{ formatNumber(item.quantity_received) }}</strong></span>
              </div>

              <div v-if="item.batches.length" class="batch-chip-list">
                <span v-for="batch in item.batches" :key="batch.id" class="batch-chip">
                  Batch {{ batch.batch_number || '-' }}
                  <small>
                    {{ formatNumber(batch.quantity_received) }}/{{ formatNumber(batch.quantity_dispatched) }}
                    received
                    {{ batch.expiry_date ? `- exp ${formatDate(batch.expiry_date)}` : '' }}
                  </small>
                </span>
              </div>

              <small v-else class="muted-block">Batches will appear after dispatch.</small>
            </article>
          </div>
        </section>
      </section>
    </template>

    <PDialog
      v-model:visible="createVisible"
      modal
      header="New stock transfer"
      class="branch-dialog"
      :style="{ width: 'min(1040px, 96vw)' }"
    >
      <form class="branch-form" @submit.prevent="saveTransfer">
        <PMessage v-if="createFormError" severity="error" :closable="false" class="dialog-message">
          {{ createFormError }}
        </PMessage>

        <div class="form-grid">
          <label>
            Source branch
            <PSelect
              v-model="transferForm.from_branch_id"
              :options="branchOptions"
              option-label="label"
              option-value="value"
              placeholder="Select source"
              fluid
              @change="clearTransferField('from_branch_id')"
            />
            <span v-if="transferErrors.from_branch_id" class="field-error">{{ transferErrors.from_branch_id }}</span>
          </label>
          <label>
            Destination branch
            <PSelect
              v-model="transferForm.to_branch_id"
              :options="branchOptions"
              option-label="label"
              option-value="value"
              placeholder="Select destination"
              fluid
              @change="clearTransferField('to_branch_id')"
            />
            <span v-if="transferErrors.to_branch_id" class="field-error">{{ transferErrors.to_branch_id }}</span>
          </label>
        </div>

        <label>
          Notes
          <PTextarea v-model.trim="transferForm.notes" rows="2" auto-resize fluid placeholder="Reason, DR number, or internal reference" />
        </label>

        <section class="mini-section">
          <div class="mini-section__header">
            <div>
              <h3>Transfer items</h3>
              <small class="muted-block">Dispatch later uses FEFO batches from the source branch.</small>
            </div>
            <PButton type="button" icon="pi pi-plus" label="Add item" outlined @click="addTransferRow" />
          </div>

          <span v-if="transferErrors.items" class="field-error">{{ transferErrors.items }}</span>

          <div class="count-list">
            <article v-for="(item, index) in transferForm.items" :key="item.local_key" class="count-row transfer-form-row">
              <div class="form-grid">
                <label>
                  Product
                  <PSelect
                    v-model="item.product_id"
                    :options="productOptions"
                    option-label="label"
                    option-value="value"
                    placeholder="Select product"
                    filter
                    fluid
                    @change="onTransferProductChange(item)"
                  />
                </label>
                <label>
                  Variant
                  <PSelect
                    v-model="item.product_variant_id"
                    :options="variantOptionsForProduct(item.product_id)"
                    option-label="label"
                    option-value="value"
                    placeholder="No variant"
                    show-clear
                    fluid
                  />
                </label>
                <label>
                  Available at source
                  <PInputText :model-value="formatNumber(availableStockForRow(item))" disabled fluid />
                </label>
                <label>
                  Quantity requested
                  <PInputNumber v-model="item.quantity_requested" :min="1" :use-grouping="false" fluid />
                </label>
              </div>

              <label>
                Item notes
                <PInputText v-model.trim="item.notes" placeholder="Optional" fluid />
              </label>

              <div class="count-row__footer">
                <span :class="{ 'negative-text': item.quantity_requested > availableStockForRow(item) }">
                  {{ formatNumber(availableStockForRow(item)) }} units currently available
                </span>
                <PButton
                  type="button"
                  icon="pi pi-trash"
                  text
                  rounded
                  severity="danger"
                  aria-label="Remove item"
                  :disabled="transferForm.items.length === 1"
                  @click="removeTransferRow(index)"
                />
              </div>
            </article>
          </div>
        </section>

        <div class="dialog-actions">
          <PButton type="button" label="Cancel" severity="secondary" outlined @click="createVisible = false" />
          <PButton type="submit" icon="pi pi-save" label="Create request" :loading="saving" />
        </div>
      </form>
    </PDialog>

    <PDialog
      v-model:visible="receiveVisible"
      modal
      header="Receive dispatched transfer"
      class="branch-dialog"
      :style="{ width: 'min(900px, 96vw)' }"
    >
      <form class="branch-form" @submit.prevent="saveReceive">
        <PMessage v-if="receiveFormError" severity="error" :closable="false" class="dialog-message">
          {{ receiveFormError }}
        </PMessage>

        <section class="mini-section">
          <div class="mini-section__header">
            <div>
              <h3>{{ receivingTransfer?.transfer_number || 'Transfer' }}</h3>
              <small class="muted-block">Enter actual received quantity to record receiving variance.</small>
            </div>
          </div>

          <div class="count-list">
            <article v-for="row in receiveRows" :key="row.item_id" class="count-row">
              <div class="form-grid">
                <label>
                  Product
                  <PInputText :model-value="row.product_label" disabled fluid />
                </label>
                <label>
                  Dispatched quantity
                  <PInputText :model-value="formatNumber(row.quantity_dispatched)" disabled fluid />
                </label>
                <label>
                  Received quantity
                  <PInputNumber v-model="row.quantity_received" :min="0" :max="row.quantity_dispatched" :use-grouping="false" fluid />
                </label>
                <label>
                  Variance
                  <PInputText :model-value="signedNumber(Number(row.quantity_received || 0) - row.quantity_dispatched)" disabled fluid />
                </label>
              </div>
            </article>
          </div>
        </section>

        <div class="dialog-actions">
          <PButton type="button" label="Cancel" severity="secondary" outlined @click="receiveVisible = false" />
          <PButton type="submit" icon="pi pi-inbox" label="Post receiving" :loading="saving" />
        </div>
      </form>
    </PDialog>

    <PDialog
      v-model:visible="cancelVisible"
      modal
      header="Cancel transfer"
      class="branch-dialog"
      :style="{ width: 'min(640px, 96vw)' }"
    >
      <form class="branch-form" @submit.prevent="saveCancel">
        <PMessage v-if="cancelFormError" severity="error" :closable="false" class="dialog-message">
          {{ cancelFormError }}
        </PMessage>

        <label>
          Reason
          <PTextarea v-model.trim="cancelReason" rows="3" auto-resize fluid placeholder="Reason for cancellation" />
        </label>

        <div class="dialog-actions">
          <PButton type="button" label="Close" severity="secondary" outlined @click="cancelVisible = false" />
          <PButton type="submit" icon="pi pi-times" label="Cancel transfer" severity="danger" :loading="saving" />
        </div>
      </form>
    </PDialog>
  </section>
</template>

<script setup>
import { computed, onMounted, reactive, ref, watch } from 'vue'
import MetricCard from '../components/MetricCard.vue'
import { formatDate, formatNumber } from '../lib/formatters'
import {
  approveStockTransfer,
  cancelStockTransfer,
  createStockTransfer,
  dispatchStockTransfer,
  fetchStockTransferManagement,
  receiveStockTransfer,
} from '../services/stockTransferService'
import { useAuthStore } from '../stores/authStore'

const auth = useAuthStore()
const loading = ref(false)
const saving = ref(false)
const error = ref('')
const successMessage = ref('')
const search = ref('')
const statusFilter = ref('')
const selectedBranchId = ref(null)
const selectedTransferId = ref(null)
const transferData = ref(null)
const createVisible = ref(false)
const receiveVisible = ref(false)
const cancelVisible = ref(false)
const createFormError = ref('')
const receiveFormError = ref('')
const cancelFormError = ref('')
const transferErrors = reactive({})
const transferForm = reactive(createDefaultTransferForm())
const receiveRows = ref([])
const receivingTransfer = ref(null)
const cancellingTransfer = ref(null)
const cancelReason = ref('')

const statusFilterOptions = [
  { label: 'All statuses', value: '' },
  { label: 'Requested', value: 'requested' },
  { label: 'Approved', value: 'approved' },
  { label: 'Dispatched', value: 'dispatched' },
  { label: 'Received', value: 'received' },
  { label: 'Cancelled', value: 'cancelled' },
]

const transferStages = [
  { value: 'requested', label: 'Requested', icon: 'pi pi-clock' },
  { value: 'approved', label: 'Approved', icon: 'pi pi-check-circle' },
  { value: 'dispatched', label: 'Dispatched', icon: 'pi pi-truck' },
  { value: 'received', label: 'Received', icon: 'pi pi-inbox' },
]

const canManageTransfers = computed(() => auth.isAdmin.value || auth.state.profile?.role === 'manager')
const canFilterBranches = computed(() => ['admin', 'auditor'].includes(auth.state.profile?.role))
const currentBranchId = computed(() => auth.state.profile?.branch_id || null)

const branchOptions = computed(() =>
  (transferData.value?.branches || []).map((branch) => ({
    label: `${branch.branch_code} - ${branch.name}`,
    value: branch.id,
  })),
)

const branchFilterOptions = computed(() => [{ label: 'All branches', value: null }, ...branchOptions.value])

const productOptions = computed(() =>
  (transferData.value?.products || []).map((product) => ({
    label: `${product.sku} - ${product.name}`,
    value: product.id,
  })),
)

const filteredTransfers = computed(() => {
  const query = search.value.toLowerCase()
  const rows = transferData.value?.transfers || []

  return rows.filter((transfer) => {
    const matchesStatus = !statusFilter.value || transfer.status === statusFilter.value
    const matchesBranch =
      !selectedBranchId.value ||
      transfer.from_branch_id === selectedBranchId.value ||
      transfer.to_branch_id === selectedBranchId.value
    const matchesSearch =
      !query ||
      [
        transfer.transfer_number,
        transfer.from_branch_code,
        transfer.from_branch_name,
        transfer.to_branch_code,
        transfer.to_branch_name,
        transfer.requested_by_name,
        transfer.notes,
        ...transfer.items.flatMap((item) => [item.product_name, item.sku, item.barcode, item.variant_name]),
      ]
        .filter(Boolean)
        .some((value) => String(value).toLowerCase().includes(query))

    return matchesStatus && matchesBranch && matchesSearch
  })
})

const selectedTransfer = computed(() => {
  const transfers = transferData.value?.transfers || []
  return transfers.find((transfer) => transfer.id === selectedTransferId.value) || filteredTransfers.value[0] || null
})

watch(selectedBranchId, async () => {
  if (!transferData.value || !canFilterBranches.value) return
  await loadTransfers()
})

function localKey() {
  return `${Date.now()}-${Math.random()}`
}

function createTransferRow(payload = {}) {
  return {
    local_key: localKey(),
    product_id: payload.product_id || null,
    product_variant_id: payload.product_variant_id || null,
    quantity_requested: Number(payload.quantity_requested || 1),
    notes: payload.notes || '',
  }
}

function createDefaultTransferForm() {
  return {
    from_branch_id: null,
    to_branch_id: null,
    notes: '',
    items: [createTransferRow()],
  }
}

function clearObject(object) {
  Object.keys(object).forEach((key) => {
    delete object[key]
  })
}

function resetTransferForm(payload = {}) {
  Object.assign(transferForm, createDefaultTransferForm(), payload)
  transferForm.items = payload.items || [createTransferRow()]
}

function clearTransferFeedback() {
  createFormError.value = ''
  clearObject(transferErrors)
}

function clearTransferField(key) {
  if (transferErrors[key]) delete transferErrors[key]
  if (Object.keys(transferErrors).length === 0) createFormError.value = ''
}

function defaultBranchId() {
  return selectedBranchId.value || currentBranchId.value || transferData.value?.branches?.[0]?.id || null
}

function managerDefaultRoute() {
  if (auth.state.profile?.role === 'manager') {
    return {
      from_branch_id: currentBranchId.value,
      to_branch_id: null,
    }
  }

  return {
    from_branch_id: defaultBranchId(),
    to_branch_id: null,
  }
}

function variantOptionsForProduct(productId) {
  const product = (transferData.value?.products || []).find((row) => row.id === productId)
  const variants = product?.variants || []

  return variants.map((variant) => ({
    label: `${variant.variant_name} - ${variant.sku}`,
    value: variant.id,
  }))
}

function availableStockFor(branchId, productId, variantId = null) {
  if (!branchId || !productId) return 0

  if (variantId) {
    return (transferData.value?.batches || [])
      .filter(
        (batch) =>
          batch.branch_id === branchId &&
          batch.product_id === productId &&
          batch.product_variant_id === variantId &&
          batch.status === 'active',
      )
      .reduce((total, batch) => total + Number(batch.quantity_on_hand || 0), 0)
  }

  const row = (transferData.value?.inventory || []).find((item) => item.branch_id === branchId && item.product_id === productId)
  return Number(row?.quantity_on_hand || 0)
}

function availableStockForRow(row) {
  return availableStockFor(transferForm.from_branch_id, row.product_id, row.product_variant_id)
}

function onTransferProductChange(item) {
  item.product_variant_id = null
  clearTransferField('items')
}

function addTransferRow() {
  transferForm.items.push(createTransferRow())
  clearTransferField('items')
}

function removeTransferRow(index) {
  if (transferForm.items.length <= 1) return
  transferForm.items.splice(index, 1)
}

function validateTransferForm() {
  clearTransferFeedback()

  if (!transferForm.from_branch_id) {
    transferErrors.from_branch_id = 'Source branch is required.'
  }

  if (!transferForm.to_branch_id) {
    transferErrors.to_branch_id = 'Destination branch is required.'
  }

  if (transferForm.from_branch_id && transferForm.to_branch_id && transferForm.from_branch_id === transferForm.to_branch_id) {
    transferErrors.to_branch_id = 'Destination must be different from source.'
  }

  const seen = new Set()
  const validItems = transferForm.items.filter((item) => item.product_id && Number(item.quantity_requested || 0) > 0)

  if (!validItems.length) {
    transferErrors.items = 'Add at least one product with quantity greater than zero.'
  }

  for (const item of transferForm.items) {
    if (!item.product_id || Number(item.quantity_requested || 0) <= 0) continue

    const duplicateKey = `${item.product_id}:${item.product_variant_id || 'base'}`
    if (seen.has(duplicateKey)) {
      transferErrors.items = 'Duplicate product lines are not allowed. Increase the quantity on the existing line.'
      break
    }
    seen.add(duplicateKey)

    const available = availableStockForRow(item)
    if (Number(item.quantity_requested || 0) > available) {
      transferErrors.items = 'Requested quantity cannot be higher than current source stock.'
      break
    }
  }

  if (Object.keys(transferErrors).length > 0) {
    createFormError.value = 'Please fix the highlighted fields inside the form.'
    return false
  }

  return true
}

async function loadTransfers() {
  loading.value = true
  error.value = ''
  successMessage.value = ''

  try {
    transferData.value = await fetchStockTransferManagement(canFilterBranches.value ? selectedBranchId.value : null)

    if (!selectedBranchId.value && !canFilterBranches.value) {
      selectedBranchId.value = currentBranchId.value || transferData.value.branches?.[0]?.id || null
    }

    if (selectedTransferId.value && !transferData.value.transfers.some((transfer) => transfer.id === selectedTransferId.value)) {
      selectedTransferId.value = transferData.value.transfers[0]?.id || null
    }
  } catch (loadError) {
    error.value = loadError.message
  } finally {
    loading.value = false
  }
}

function openCreate() {
  clearTransferFeedback()
  resetTransferForm(managerDefaultRoute())
  createVisible.value = true
}

async function saveTransfer() {
  if (!validateTransferForm()) return

  saving.value = true
  error.value = ''
  successMessage.value = ''

  try {
    const payload = {
      from_branch_id: transferForm.from_branch_id,
      to_branch_id: transferForm.to_branch_id,
      notes: transferForm.notes,
      items: transferForm.items.map((item) => ({
        product_id: item.product_id,
        product_variant_id: item.product_variant_id || null,
        quantity_requested: Number(item.quantity_requested || 0),
        notes: item.notes,
      })),
    }

    transferData.value = await createStockTransfer(payload)
    createVisible.value = false
    selectedTransferId.value = transferData.value.transfers[0]?.id || null
    successMessage.value = 'Transfer request created.'
  } catch (saveError) {
    createFormError.value = saveError.message
  } finally {
    saving.value = false
  }
}

function selectTransfer(transfer) {
  selectedTransferId.value = transfer.id
}

async function approveTransfer(transfer) {
  if (!window.confirm(`Approve transfer ${transfer.transfer_number}?`)) return

  await runTransferAction(() => approveStockTransfer(transfer.id), 'Transfer approved.')
}

async function dispatchTransfer(transfer) {
  if (!window.confirm(`Dispatch transfer ${transfer.transfer_number}? Stock will decrease from the source branch immediately.`)) return

  await runTransferAction(() => dispatchStockTransfer(transfer.id), 'Transfer dispatched and source stock reduced.')
}

function openReceive(transfer) {
  receiveFormError.value = ''
  receivingTransfer.value = transfer
  receiveRows.value = transfer.items.map((item) => ({
    item_id: item.id,
    product_label: `${item.product_name}${item.variant_name ? ` - ${item.variant_name}` : ''}`,
    quantity_dispatched: Number(item.quantity_dispatched || 0),
    quantity_received: Number(item.quantity_dispatched || 0),
  }))
  receiveVisible.value = true
}

async function saveReceive() {
  receiveFormError.value = ''

  for (const row of receiveRows.value) {
    if (Number(row.quantity_received || 0) < 0 || Number(row.quantity_received || 0) > row.quantity_dispatched) {
      receiveFormError.value = 'Received quantity must be between zero and dispatched quantity.'
      return
    }
  }

  saving.value = true
  error.value = ''
  successMessage.value = ''

  try {
    transferData.value = await receiveStockTransfer(receivingTransfer.value.id, {
      items: receiveRows.value.map((row) => ({
        item_id: row.item_id,
        quantity_received: Number(row.quantity_received || 0),
      })),
    })
    receiveVisible.value = false
    selectedTransferId.value = receivingTransfer.value.id
    successMessage.value = 'Transfer received and destination stock updated.'
  } catch (saveError) {
    receiveFormError.value = saveError.message
  } finally {
    saving.value = false
  }
}

function openCancel(transfer) {
  cancellingTransfer.value = transfer
  cancelReason.value = ''
  cancelFormError.value = ''
  cancelVisible.value = true
}

async function saveCancel() {
  saving.value = true
  cancelFormError.value = ''
  error.value = ''
  successMessage.value = ''

  try {
    transferData.value = await cancelStockTransfer(cancellingTransfer.value.id, cancelReason.value)
    cancelVisible.value = false
    selectedTransferId.value = cancellingTransfer.value.id
    successMessage.value = 'Transfer cancelled.'
  } catch (saveError) {
    cancelFormError.value = saveError.message
  } finally {
    saving.value = false
  }
}

async function runTransferAction(action, message) {
  saving.value = true
  error.value = ''
  successMessage.value = ''

  try {
    transferData.value = await action()
    successMessage.value = message
  } catch (actionError) {
    error.value = actionError.message
  } finally {
    saving.value = false
  }
}

function canApprove(transfer) {
  return (
    transfer.status === 'requested' &&
    (auth.isAdmin.value || (auth.state.profile?.role === 'manager' && currentBranchId.value === transfer.from_branch_id))
  )
}

function canDispatch(transfer) {
  return (
    transfer.status === 'approved' &&
    (auth.isAdmin.value || (auth.state.profile?.role === 'manager' && currentBranchId.value === transfer.from_branch_id))
  )
}

function canReceive(transfer) {
  return (
    transfer.status === 'dispatched' &&
    (auth.isAdmin.value || (auth.state.profile?.role === 'manager' && currentBranchId.value === transfer.to_branch_id))
  )
}

function canCancel(transfer) {
  return (
    ['requested', 'approved'].includes(transfer.status) &&
    (auth.isAdmin.value ||
      (auth.state.profile?.role === 'manager' &&
        [transfer.from_branch_id, transfer.to_branch_id].includes(currentBranchId.value)))
  )
}

function statusLabel(status) {
  return String(status || 'unknown')
    .replace('_', ' ')
    .replace(/\b\w/g, (letter) => letter.toUpperCase())
}

function statusSeverity(status) {
  const severity = {
    requested: 'info',
    approved: 'warn',
    dispatched: 'secondary',
    received: 'success',
    cancelled: 'danger',
    rejected: 'danger',
  }

  return severity[status] || 'secondary'
}

function quantityPrimary(transfer) {
  if (transfer.status === 'received') return transfer.total_received
  if (transfer.status === 'dispatched') return transfer.total_dispatched
  if (transfer.status === 'approved') return transfer.total_approved
  return transfer.total_requested
}

function quantityLabel(transfer) {
  if (transfer.status === 'received') return 'received units'
  if (transfer.status === 'dispatched') return 'dispatched units'
  if (transfer.status === 'approved') return 'approved units'
  return 'requested units'
}

function transferStageIndex(status) {
  return transferStages.findIndex((stage) => stage.value === status)
}

function isStageComplete(transfer, stage) {
  if (['cancelled', 'rejected'].includes(transfer.status)) return stage === 'requested'
  return transferStageIndex(stage) <= transferStageIndex(transfer.status)
}

function stageTimestamp(transfer, stage) {
  const value = {
    requested: transfer.requested_at,
    approved: transfer.approved_at,
    dispatched: transfer.dispatched_at,
    received: transfer.received_at,
  }[stage]

  return value ? formatDateTime(value) : ''
}

function varianceLabel(value) {
  const variance = Number(value || 0)
  if (variance === 0) return 'No variance'
  return `${signedNumber(variance)} variance`
}

function signedNumber(value) {
  const number = Number(value || 0)
  return `${number > 0 ? '+' : ''}${formatNumber(number)}`
}

function formatDateTime(value) {
  if (!value) return ''

  return new Intl.DateTimeFormat('en-PH', {
    month: 'short',
    day: '2-digit',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  }).format(new Date(value))
}

onMounted(loadTransfers)
</script>
