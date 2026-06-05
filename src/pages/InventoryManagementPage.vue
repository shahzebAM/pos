<template>
  <section class="page-stack">
    <section class="page-hero page-hero--compact">
      <div>
        <p class="eyebrow">Module 5</p>
        <h1>Inventory Management</h1>
        <p>
          Track branch-wise stock, batches, expiry dates, damaged stock,
          adjustments, reorder levels, movement history, and physical counts.
        </p>
      </div>

      <div class="action-panel">
        <PButton icon="pi pi-plus" label="Stock in" :disabled="!canManageInventory" @click="openAdjustment('stock_in')" />
        <PButton icon="pi pi-minus" label="Stock out" outlined :disabled="!canManageInventory" @click="openAdjustment('stock_out')" />
        <PButton icon="pi pi-exclamation-triangle" label="Damaged/expired" outlined :disabled="!canManageInventory" @click="openAdjustment('damaged')" />
        <PButton icon="pi pi-clipboard" label="Stock count" outlined :disabled="!canManageInventory" @click="openStockCount" />
        <PButton icon="pi pi-refresh" label="Refresh" outlined :loading="loading" @click="loadInventory" />
      </div>
    </section>

    <PMessage v-if="!canManageInventory" severity="warn" :closable="false" class="setup-message">
      You can view inventory with this role. Stock movements and stock counts are admin/manager actions.
    </PMessage>

    <PMessage v-if="error" severity="error" :closable="false" class="setup-message">
      {{ error }}
    </PMessage>

    <PMessage v-if="successMessage" severity="success" :closable="false" class="setup-message">
      {{ successMessage }}
    </PMessage>

    <section v-if="loading && !inventoryData" class="stats-grid">
      <PSkeleton v-for="item in 6" :key="item" height="8rem" border-radius="8px" />
    </section>

    <template v-else-if="inventoryData">
      <section class="stats-grid">
        <MetricCard label="Stock units" :value="formatNumber(inventoryData.summary.stock_units)" icon="pi pi-box" />
        <MetricCard label="Inventory value" :value="formatCurrency(inventoryData.summary.inventory_value)" icon="pi pi-wallet" tone="blue" />
        <MetricCard label="Low stock" :value="formatNumber(inventoryData.summary.low_stock_items)" icon="pi pi-arrow-down" tone="gold" />
        <MetricCard label="Out of stock" :value="formatNumber(inventoryData.summary.out_of_stock_items)" icon="pi pi-times-circle" tone="red" />
        <MetricCard label="Expiring soon" :value="formatNumber(inventoryData.summary.expiring_soon_batches)" icon="pi pi-clock" tone="orange" />
        <MetricCard label="Expired" :value="formatNumber(inventoryData.summary.expired_batches)" icon="pi pi-ban" tone="red" />
      </section>

      <section class="panel">
        <div class="table-toolbar product-toolbar">
          <div>
            <p class="eyebrow">Branch stock</p>
            <h2>Inventory by product</h2>
          </div>

          <div class="toolbar-controls">
            <span class="search-field">
              <i class="pi pi-search" />
              <PInputText v-model.trim="search" placeholder="Search product, SKU, branch, batch" />
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
          :value="filteredInventory"
          data-key="id"
          responsive-layout="stack"
          breakpoint="980px"
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
          <PColumn field="product_name" header="Product">
            <template #body="{ data }">
              <div class="branch-cell">
                <strong>{{ data.product_name }}</strong>
                <small>SKU {{ data.sku }} - Barcode {{ data.barcode }}</small>
              </div>
            </template>
          </PColumn>
          <PColumn field="category_name" header="Category">
            <template #body="{ data }">
              {{ data.category_name || data.category || '-' }}
              <small class="muted-block">{{ data.brand_name || 'Unbranded' }}</small>
            </template>
          </PColumn>
          <PColumn field="quantity_on_hand" header="Stock">
            <template #body="{ data }">
              <strong>{{ formatNumber(data.quantity_on_hand) }}</strong>
              <small class="muted-block">Reorder at {{ formatNumber(data.reorder_level) }}</small>
            </template>
          </PColumn>
          <PColumn field="inventory_value" header="Value">
            <template #body="{ data }">
              {{ formatCurrency(data.inventory_value) }}
              <small class="muted-block">{{ formatNumber(data.batch_count) }} active batches</small>
            </template>
          </PColumn>
          <PColumn field="earliest_expiry" header="Expiry">
            <template #body="{ data }">
              {{ data.earliest_expiry ? formatDate(data.earliest_expiry) : '-' }}
              <small class="muted-block">
                {{ formatNumber(data.expiring_soon_batches) }} soon, {{ formatNumber(data.expired_batches) }} expired
              </small>
            </template>
          </PColumn>
          <PColumn field="stock_status" header="Status">
            <template #body="{ data }">
              <PTag :value="stockStatusLabel(data.stock_status)" :severity="stockStatusSeverity(data.stock_status)" />
            </template>
          </PColumn>
          <PColumn header="Actions">
            <template #body="{ data }">
              <div class="table-actions">
                <PButton
                  icon="pi pi-plus"
                  text
                  rounded
                  aria-label="Stock in"
                  :disabled="!canManageInventory"
                  @click="openAdjustment('stock_in', data)"
                />
                <PButton
                  icon="pi pi-minus"
                  text
                  rounded
                  aria-label="Stock out"
                  :disabled="!canManageInventory || data.quantity_on_hand <= 0"
                  @click="openAdjustment('stock_out', data)"
                />
                <PButton
                  icon="pi pi-clipboard"
                  text
                  rounded
                  aria-label="Count product"
                  :disabled="!canManageInventory"
                  @click="openStockCount(data)"
                />
              </div>
            </template>
          </PColumn>
        </PDataTable>
      </section>

      <section class="analytics-grid inventory-detail-grid">
        <section class="panel">
          <div class="panel__header">
            <div>
              <p class="eyebrow">Expiry watch</p>
              <h2>Expiring and expired batches</h2>
            </div>
            <span class="panel__caption">30-day expiry window</span>
          </div>

          <div v-if="inventoryData.expiry_alerts.length" class="stack-list">
            <article v-for="batch in inventoryData.expiry_alerts" :key="batch.id" class="stack-list__item">
              <div>
                <strong>{{ batch.product_name }}</strong>
                <small>
                  {{ batch.branch_name }} - Batch {{ batch.batch_number || '-' }} - Qty {{ formatNumber(batch.quantity_on_hand) }}
                </small>
              </div>
              <div class="table-actions">
                <PTag :value="expiryStatusLabel(batch.expiry_status)" :severity="expiryStatusSeverity(batch.expiry_status)" />
                <span class="muted-block">{{ batch.expiry_date ? formatDate(batch.expiry_date) : '-' }}</span>
              </div>
            </article>
          </div>

          <div v-else class="empty-state empty-state--small">
            <i class="pi pi-check-circle" />
            <p>No expiring batches in the 30-day window.</p>
          </div>
        </section>

        <section class="panel">
          <div class="panel__header">
            <div>
              <p class="eyebrow">Batches</p>
              <h2>Batch stock ledger</h2>
            </div>
          </div>

          <PDataTable
            :value="filteredBatches"
            data-key="id"
            responsive-layout="stack"
            breakpoint="760px"
            size="small"
            striped-rows
            paginator
            :rows="6"
          >
            <PColumn field="product_name" header="Product">
              <template #body="{ data }">
                <div class="branch-cell">
                  <strong>{{ data.product_name }}</strong>
                  <small>{{ data.variant_name || data.branch_name }}</small>
                </div>
              </template>
            </PColumn>
            <PColumn field="batch_number" header="Batch">
              <template #body="{ data }">{{ data.batch_number || '-' }}</template>
            </PColumn>
            <PColumn field="quantity_on_hand" header="Qty">
              <template #body="{ data }">{{ formatNumber(data.quantity_on_hand) }}</template>
            </PColumn>
            <PColumn field="expiry_status" header="Expiry">
              <template #body="{ data }">
                <PTag :value="expiryStatusLabel(data.expiry_status)" :severity="expiryStatusSeverity(data.expiry_status)" />
                <small class="muted-block">{{ data.expiry_date ? formatDate(data.expiry_date) : 'No expiry' }}</small>
              </template>
            </PColumn>
          </PDataTable>
        </section>
      </section>

      <section class="panel">
        <div class="panel__header">
          <div>
            <p class="eyebrow">Inventory history</p>
            <h2>Movements and stock counts</h2>
          </div>
        </div>

        <div class="inventory-history-grid">
          <PDataTable
            :value="inventoryData.movements"
            data-key="id"
            responsive-layout="stack"
            breakpoint="880px"
            size="small"
            striped-rows
            paginator
            :rows="8"
          >
            <PColumn field="created_at" header="Date">
              <template #body="{ data }">{{ formatDateTime(data.created_at) }}</template>
            </PColumn>
            <PColumn field="movement_type" header="Type">
              <template #body="{ data }">
                <PTag :value="movementLabel(data.movement_type)" :severity="movementSeverity(data.movement_type)" />
              </template>
            </PColumn>
            <PColumn field="product_name" header="Product">
              <template #body="{ data }">
                <div class="branch-cell">
                  <strong>{{ data.product_name }}</strong>
                  <small>{{ data.branch_name }}{{ data.batch_number ? ` - ${data.batch_number}` : '' }}</small>
                </div>
              </template>
            </PColumn>
            <PColumn field="quantity_delta" header="Qty">
              <template #body="{ data }">
                <strong :class="{ 'negative-text': data.quantity_delta < 0 }">
                  {{ signedNumber(data.quantity_delta) }}
                </strong>
                <small class="muted-block">{{ formatNumber(data.quantity_before) }} to {{ formatNumber(data.quantity_after) }}</small>
              </template>
            </PColumn>
            <PColumn field="reason" header="Reason">
              <template #body="{ data }">{{ data.reason || data.reference_number || '-' }}</template>
            </PColumn>
          </PDataTable>

          <div class="stock-count-list">
            <article v-for="count in inventoryData.stock_counts" :key="count.id" class="stock-count-card">
              <div>
                <strong>{{ count.count_number }}</strong>
                <small>{{ count.branch_name }} - {{ formatDateTime(count.posted_at || count.created_at) }}</small>
              </div>
              <div class="stock-count-card__meta">
                <PTag :value="count.status" severity="info" />
                <span>{{ formatNumber(count.item_count) }} items</span>
                <span>{{ formatNumber(count.total_variance) }} variance</span>
              </div>
            </article>

            <div v-if="!inventoryData.stock_counts.length" class="empty-state empty-state--small">
              <i class="pi pi-clipboard" />
              <p>No posted stock counts yet.</p>
            </div>
          </div>
        </div>
      </section>
    </template>

    <PDialog
      v-model:visible="adjustDialogVisible"
      modal
      :header="adjustDialogTitle"
      class="branch-dialog"
      :style="{ width: 'min(920px, 96vw)' }"
    >
      <form class="branch-form" @submit.prevent="saveAdjustment">
        <PMessage v-if="adjustFormError" severity="error" :closable="false" class="dialog-message">
          {{ adjustFormError }}
        </PMessage>

        <div class="form-grid">
          <label>
            Branch
            <PSelect
              v-model="adjustForm.branch_id"
              :options="branchOptions"
              option-label="label"
              option-value="value"
              placeholder="Select branch"
              fluid
              :disabled="!canFilterBranches"
              @change="onAdjustBranchChange"
            />
            <span v-if="adjustErrors.branch_id" class="field-error">{{ adjustErrors.branch_id }}</span>
          </label>
          <label>
            Product
            <PSelect
              v-model="adjustForm.product_id"
              :options="productOptions"
              option-label="label"
              option-value="value"
              placeholder="Select product"
              fluid
              @change="onAdjustProductChange"
            />
            <span v-if="adjustErrors.product_id" class="field-error">{{ adjustErrors.product_id }}</span>
          </label>
          <label>
            Variant
            <PSelect
              v-model="adjustForm.product_variant_id"
              :options="variantOptions"
              option-label="label"
              option-value="value"
              placeholder="No variant"
              fluid
              show-clear
            />
          </label>
          <label>
            Movement type
            <PSelect
              v-model="adjustForm.movement_type"
              :options="movementTypeOptions"
              option-label="label"
              option-value="value"
              fluid
              @change="clearAdjustField('movement_type')"
            />
          </label>
          <label>
            Quantity
            <PInputNumber
              v-model="adjustForm.quantity"
              :min="1"
              :use-grouping="false"
              fluid
              @update:model-value="clearAdjustField('quantity')"
            />
            <span v-if="adjustErrors.quantity" class="field-error">{{ adjustErrors.quantity }}</span>
          </label>
          <label>
            Batch
            <PSelect
              v-model="adjustForm.batch_id"
              :options="batchOptions"
              option-label="label"
              option-value="value"
              placeholder="Auto / FEFO"
              show-clear
              fluid
            />
          </label>
          <label>
            Batch number
            <PInputText v-model.trim="adjustForm.batch_number" placeholder="Optional for stock in" fluid />
          </label>
          <label>
            Expiry date
            <PDatePicker v-model="adjustForm.expiry_date" date-format="yy-mm-dd" show-icon fluid />
          </label>
          <label>
            Unit cost
            <PInputNumber v-model="adjustForm.unit_cost" mode="currency" :currency="currencyCode" locale="en-PH" :min="0" fluid />
          </label>
          <label>
            Reference number
            <PInputText v-model.trim="adjustForm.reference_number" placeholder="DR, PO, memo, count no." fluid />
          </label>
        </div>

        <label>
          Reason
          <PTextarea v-model.trim="adjustForm.reason" rows="3" auto-resize fluid />
        </label>

        <div class="dialog-actions">
          <PButton type="button" label="Cancel" severity="secondary" outlined @click="adjustDialogVisible = false" />
          <PButton type="submit" icon="pi pi-save" label="Post movement" :loading="saving" />
        </div>
      </form>
    </PDialog>

    <PDialog
      v-model:visible="countDialogVisible"
      modal
      header="Post stock count"
      class="branch-dialog"
      :style="{ width: 'min(980px, 96vw)' }"
    >
      <form class="branch-form" @submit.prevent="saveStockCount">
        <PMessage v-if="countFormError" severity="error" :closable="false" class="dialog-message">
          {{ countFormError }}
        </PMessage>

        <div class="form-grid">
          <label>
            Branch
            <PSelect
              v-model="countForm.branch_id"
              :options="branchOptions"
              option-label="label"
              option-value="value"
              placeholder="Select branch"
              fluid
              :disabled="!canFilterBranches"
              @change="clearCountField('branch_id')"
            />
            <span v-if="countErrors.branch_id" class="field-error">{{ countErrors.branch_id }}</span>
          </label>
          <label>
            Notes
            <PInputText v-model.trim="countForm.notes" placeholder="Physical count notes" fluid />
          </label>
        </div>

        <section class="mini-section">
          <div class="mini-section__header">
            <div>
              <h3>Counted items</h3>
              <small class="muted-block">Variance is posted immediately as an inventory adjustment.</small>
            </div>
            <PButton type="button" icon="pi pi-plus" label="Add item" outlined @click="addCountRow" />
          </div>

          <span v-if="countErrors.items" class="field-error">{{ countErrors.items }}</span>

          <div class="count-list">
            <article v-for="(item, index) in countForm.items" :key="item.local_key" class="count-row">
              <div class="form-grid">
                <label>
                  Product
                  <PSelect
                    v-model="item.product_id"
                    :options="productOptions"
                    option-label="label"
                    option-value="value"
                    placeholder="Select product"
                    fluid
                    @change="onCountProductChange(item)"
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
                  System quantity
                  <PInputText :model-value="formatNumber(systemQuantityFor(item))" disabled fluid />
                </label>
                <label>
                  Counted quantity
                  <PInputNumber v-model="item.counted_quantity" :min="0" :use-grouping="false" fluid />
                </label>
              </div>
              <div class="count-row__footer">
                <span :class="{ 'negative-text': countVariance(item) < 0 }">
                  Variance {{ signedNumber(countVariance(item)) }}
                </span>
                <PButton type="button" icon="pi pi-trash" text rounded severity="danger" aria-label="Remove count row" @click="removeCountRow(index)" />
              </div>
            </article>
          </div>
        </section>

        <div class="dialog-actions">
          <PButton type="button" label="Cancel" severity="secondary" outlined @click="countDialogVisible = false" />
          <PButton type="submit" icon="pi pi-check" label="Post count" :loading="saving" />
        </div>
      </form>
    </PDialog>
  </section>
</template>

<script setup>
import { computed, onMounted, reactive, ref, watch } from 'vue'
import MetricCard from '../components/MetricCard.vue'
import { currencyCode, formatCurrency, formatDate, formatNumber, toISODate } from '../lib/formatters'
import { adjustInventory, fetchInventoryManagement, postStockCount } from '../services/inventoryService'
import { useAuthStore } from '../stores/authStore'

const auth = useAuthStore()
const loading = ref(false)
const saving = ref(false)
const error = ref('')
const successMessage = ref('')
const search = ref('')
const statusFilter = ref('')
const selectedBranchId = ref(null)
const inventoryData = ref(null)
const adjustDialogVisible = ref(false)
const countDialogVisible = ref(false)
const adjustFormError = ref('')
const countFormError = ref('')
const adjustErrors = reactive({})
const countErrors = reactive({})
const adjustForm = reactive(createDefaultAdjustForm())
const countForm = reactive(createDefaultCountForm())

const movementTypeOptions = [
  { label: 'Stock in', value: 'stock_in' },
  { label: 'Stock out', value: 'stock_out' },
  { label: 'Adjustment plus', value: 'adjustment_plus' },
  { label: 'Adjustment minus', value: 'adjustment_minus' },
  { label: 'Damaged stock', value: 'damaged' },
  { label: 'Expired stock', value: 'expired' },
]

const statusFilterOptions = [
  { label: 'All stock', value: '' },
  { label: 'In stock', value: 'in_stock' },
  { label: 'Low stock', value: 'low_stock' },
  { label: 'Out of stock', value: 'out_of_stock' },
]

const canManageInventory = computed(() => auth.isAdmin.value || auth.state.profile?.role === 'manager')
const canFilterBranches = computed(() => ['admin', 'auditor'].includes(auth.state.profile?.role))

const branchOptions = computed(() =>
  (inventoryData.value?.branches || []).map((branch) => ({
    label: `${branch.branch_code} - ${branch.name}`,
    value: branch.id,
  })),
)

const branchFilterOptions = computed(() => [{ label: 'All branches', value: null }, ...branchOptions.value])

const productOptions = computed(() =>
  (inventoryData.value?.products || []).map((product) => ({
    label: `${product.sku} - ${product.name}`,
    value: product.id,
  })),
)

const selectedAdjustProduct = computed(() =>
  (inventoryData.value?.products || []).find((product) => product.id === adjustForm.product_id),
)

const variantOptions = computed(() => variantOptionsForProduct(adjustForm.product_id))

const batchOptions = computed(() =>
  (inventoryData.value?.batches || [])
    .filter((batch) => {
      if (!adjustForm.branch_id || !adjustForm.product_id) return false
      if (batch.branch_id !== adjustForm.branch_id || batch.product_id !== adjustForm.product_id) return false
      if (adjustForm.product_variant_id && batch.product_variant_id !== adjustForm.product_variant_id) return false
      return batch.quantity_on_hand > 0 && batch.status === 'active'
    })
    .map((batch) => ({
      label: `${batch.batch_number || 'No batch'} - Qty ${formatNumber(batch.quantity_on_hand)}${batch.expiry_date ? ` - Exp ${formatDate(batch.expiry_date)}` : ''}`,
      value: batch.id,
    })),
)

const filteredInventory = computed(() => {
  const query = search.value.toLowerCase()
  const rows = inventoryData.value?.inventory || []

  return rows.filter((row) => {
    const matchesSearch =
      !query ||
      [
        row.branch_code,
        row.branch_name,
        row.product_name,
        row.sku,
        row.barcode,
        row.category_name,
        row.brand_name,
        ...(inventoryData.value?.batches || [])
          .filter((batch) => batch.branch_id === row.branch_id && batch.product_id === row.product_id)
          .map((batch) => batch.batch_number),
      ]
        .filter(Boolean)
        .some((value) => value.toLowerCase().includes(query))

    const matchesStatus = !statusFilter.value || row.stock_status === statusFilter.value
    const matchesBranch = !selectedBranchId.value || row.branch_id === selectedBranchId.value

    return matchesSearch && matchesStatus && matchesBranch
  })
})

const filteredBatches = computed(() => {
  const query = search.value.toLowerCase()
  const rows = inventoryData.value?.batches || []

  return rows.filter((batch) => {
    const matchesBranch = !selectedBranchId.value || batch.branch_id === selectedBranchId.value
    const matchesSearch =
      !query ||
      [batch.branch_code, batch.branch_name, batch.product_name, batch.sku, batch.barcode, batch.variant_name, batch.batch_number]
        .filter(Boolean)
        .some((value) => value.toLowerCase().includes(query))

    return matchesBranch && matchesSearch
  })
})

const adjustDialogTitle = computed(() => movementLabel(adjustForm.movement_type))

watch(selectedBranchId, async () => {
  if (!inventoryData.value || !canFilterBranches.value) return
  await loadInventory()
})

function createDefaultAdjustForm() {
  return {
    branch_id: null,
    product_id: null,
    product_variant_id: null,
    batch_id: null,
    movement_type: 'stock_in',
    quantity: 1,
    batch_number: '',
    expiry_date: null,
    unit_cost: 0,
    reference_number: '',
    reason: '',
  }
}

function createDefaultCountForm() {
  return {
    branch_id: null,
    notes: '',
    items: [],
  }
}

function newCountRow(payload = {}) {
  return {
    local_key: `${Date.now()}-${Math.random()}`,
    product_id: payload.product_id || null,
    product_variant_id: payload.product_variant_id || null,
    counted_quantity: Number(payload.counted_quantity || 0),
  }
}

function clearObject(object) {
  Object.keys(object).forEach((key) => {
    delete object[key]
  })
}

function clearAdjustFeedback() {
  adjustFormError.value = ''
  clearObject(adjustErrors)
}

function clearCountFeedback() {
  countFormError.value = ''
  clearObject(countErrors)
}

function clearAdjustField(key) {
  if (adjustErrors[key]) delete adjustErrors[key]
  if (Object.keys(adjustErrors).length === 0) adjustFormError.value = ''
}

function clearCountField(key) {
  if (countErrors[key]) delete countErrors[key]
  if (Object.keys(countErrors).length === 0) countFormError.value = ''
}

function defaultBranchId() {
  return selectedBranchId.value || inventoryData.value?.branches?.[0]?.id || auth.state.profile?.branch_id || null
}

function resetAdjustForm(payload = {}) {
  Object.assign(adjustForm, createDefaultAdjustForm(), payload)
}

function resetCountForm(payload = {}) {
  Object.assign(countForm, createDefaultCountForm(), payload)
  countForm.items = payload.items || []
}

function variantOptionsForProduct(productId) {
  const product = (inventoryData.value?.products || []).find((row) => row.id === productId)
  const variants = product?.variants || []

  return variants.map((variant) => ({
    label: `${variant.variant_name} - ${variant.sku}`,
    value: variant.id,
  }))
}

function inventoryRowFor(branchId, productId) {
  return (inventoryData.value?.inventory || []).find((row) => row.branch_id === branchId && row.product_id === productId)
}

function systemQuantityFor(item) {
  if (!countForm.branch_id || !item.product_id) return 0

  if (item.product_variant_id) {
    return (inventoryData.value?.batches || [])
      .filter(
        (batch) =>
          batch.branch_id === countForm.branch_id &&
          batch.product_id === item.product_id &&
          batch.product_variant_id === item.product_variant_id &&
          batch.status === 'active',
      )
      .reduce((total, batch) => total + Number(batch.quantity_on_hand || 0), 0)
  }

  return Number(inventoryRowFor(countForm.branch_id, item.product_id)?.quantity_on_hand || 0)
}

function countVariance(item) {
  return Number(item.counted_quantity || 0) - systemQuantityFor(item)
}

async function loadInventory() {
  loading.value = true
  error.value = ''
  successMessage.value = ''

  try {
    inventoryData.value = await fetchInventoryManagement(canFilterBranches.value ? selectedBranchId.value : null)

    if (!selectedBranchId.value && !canFilterBranches.value) {
      selectedBranchId.value = inventoryData.value.branches?.[0]?.id || null
    }
  } catch (loadError) {
    error.value = loadError.message
  } finally {
    loading.value = false
  }
}

function openAdjustment(type = 'stock_in', row = null) {
  clearAdjustFeedback()
  resetAdjustForm({
    movement_type: type,
    branch_id: row?.branch_id || defaultBranchId(),
    product_id: row?.product_id || null,
    unit_cost: Number(row?.cost_price || 0),
    quantity: 1,
    reason: type === 'damaged' ? 'Damaged stock removal' : type === 'expired' ? 'Expired stock removal' : '',
  })
  adjustDialogVisible.value = true
}

function openStockCount(row = null) {
  clearCountFeedback()
  resetCountForm({
    branch_id: row?.branch_id || defaultBranchId(),
    notes: '',
    items: [newCountRow(row ? { product_id: row.product_id, counted_quantity: row.quantity_on_hand } : {})],
  })
  countDialogVisible.value = true
}

function onAdjustBranchChange() {
  adjustForm.batch_id = null
  clearAdjustField('branch_id')
}

function onAdjustProductChange() {
  const product = selectedAdjustProduct.value
  adjustForm.product_variant_id = null
  adjustForm.batch_id = null
  adjustForm.unit_cost = Number(product?.cost_price || 0)
  clearAdjustField('product_id')
}

function onCountProductChange(item) {
  item.product_variant_id = null
}

function addCountRow() {
  countForm.items.push(newCountRow())
  clearCountField('items')
}

function removeCountRow(index) {
  countForm.items.splice(index, 1)
}

function validateAdjustment() {
  const errors = {}

  if (!adjustForm.branch_id) errors.branch_id = 'Branch is required.'
  if (!adjustForm.product_id) errors.product_id = 'Product is required.'
  if (!Number(adjustForm.quantity || 0) || Number(adjustForm.quantity || 0) <= 0) {
    errors.quantity = 'Quantity must be greater than zero.'
  }

  if (Object.keys(errors).length) {
    clearAdjustFeedback()
    Object.assign(adjustErrors, errors)
    adjustFormError.value = 'Please fix the highlighted inventory fields.'
    return false
  }

  clearAdjustFeedback()
  return true
}

function validateStockCount() {
  const errors = {}

  if (!countForm.branch_id) errors.branch_id = 'Branch is required.'
  if (!countForm.items.length) errors.items = 'Add at least one counted item.'
  if (countForm.items.some((item) => !item.product_id)) errors.items = 'Every count row must have a product.'
  if (countForm.items.some((item) => Number(item.counted_quantity || 0) < 0)) errors.items = 'Counted quantity cannot be negative.'

  if (Object.keys(errors).length) {
    clearCountFeedback()
    Object.assign(countErrors, errors)
    countFormError.value = 'Please fix the highlighted stock count fields.'
    return false
  }

  clearCountFeedback()
  return true
}

function adjustmentPayload() {
  return {
    branch_id: adjustForm.branch_id,
    product_id: adjustForm.product_id,
    product_variant_id: adjustForm.product_variant_id,
    batch_id: adjustForm.batch_id,
    movement_type: adjustForm.movement_type,
    quantity: Number(adjustForm.quantity || 0),
    batch_number: adjustForm.batch_number?.trim() || '',
    expiry_date: toISODate(adjustForm.expiry_date),
    unit_cost: Number(adjustForm.unit_cost || 0),
    reference_number: adjustForm.reference_number?.trim() || '',
    reason: adjustForm.reason?.trim() || '',
  }
}

async function saveAdjustment() {
  saving.value = true
  error.value = ''
  successMessage.value = ''

  try {
    if (!validateAdjustment()) return

    inventoryData.value = await adjustInventory(adjustmentPayload())
    successMessage.value = `${movementLabel(adjustForm.movement_type)} was posted.`
    adjustDialogVisible.value = false
  } catch (saveError) {
    adjustFormError.value = saveError.message
  } finally {
    saving.value = false
  }
}

async function saveStockCount() {
  saving.value = true
  error.value = ''
  successMessage.value = ''

  try {
    if (!validateStockCount()) return

    inventoryData.value = await postStockCount({
      branch_id: countForm.branch_id,
      notes: countForm.notes?.trim() || '',
      items: countForm.items.map((item) => ({
        product_id: item.product_id,
        product_variant_id: item.product_variant_id,
        counted_quantity: Number(item.counted_quantity || 0),
      })),
    })
    successMessage.value = 'Stock count was posted and inventory variance was adjusted.'
    countDialogVisible.value = false
  } catch (saveError) {
    countFormError.value = saveError.message
  } finally {
    saving.value = false
  }
}

function stockStatusLabel(value) {
  if (value === 'out_of_stock') return 'Out of stock'
  if (value === 'low_stock') return 'Low stock'
  return 'In stock'
}

function stockStatusSeverity(value) {
  if (value === 'out_of_stock') return 'danger'
  if (value === 'low_stock') return 'warn'
  return 'success'
}

function expiryStatusLabel(value) {
  if (value === 'expired') return 'Expired'
  if (value === 'expires_7') return '7 days'
  if (value === 'expires_14') return '14 days'
  if (value === 'expires_30') return '30 days'
  if (value === 'depleted') return 'Depleted'
  return 'OK'
}

function expiryStatusSeverity(value) {
  if (value === 'expired' || value === 'expires_7') return 'danger'
  if (value === 'expires_14') return 'warn'
  if (value === 'expires_30') return 'info'
  if (value === 'depleted') return 'secondary'
  return 'success'
}

function movementLabel(value) {
  return movementTypeOptions.find((option) => option.value === value)?.label || value
}

function movementSeverity(value) {
  if (['stock_in', 'adjustment_plus'].includes(value)) return 'success'
  if (['damaged', 'expired'].includes(value)) return 'danger'
  if (value === 'stock_out') return 'info'
  return 'warn'
}

function signedNumber(value) {
  const number = Number(value || 0)
  return number > 0 ? `+${formatNumber(number)}` : formatNumber(number)
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

onMounted(loadInventory)
</script>
