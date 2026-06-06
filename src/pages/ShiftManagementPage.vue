<template>
  <section class="page-stack">
    <section class="page-hero">
      <div>
        <p class="eyebrow">Module 12</p>
        <h2>Cash register shifts, cash drawer movement, and end-of-day balancing.</h2>
        <p>
          Open cashier shifts with beginning cash, record cash in/out, connect POS
          sales to the active drawer, close shifts, and track short or over amounts
          by branch, cashier, and register.
        </p>
      </div>

      <form class="filter-panel" @submit.prevent="loadShifts">
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
        <PButton type="submit" icon="pi pi-refresh" label="Refresh report" :loading="loading" />
        <PButton type="button" icon="pi pi-play" label="Open shift" outlined :disabled="!canOpenShift" @click="openOpenDialog" />
        <PButton type="button" icon="pi pi-plus-circle" label="Cash in/out" outlined :disabled="!shiftData?.current_shift" @click="openMovementDialog" />
        <PButton type="button" icon="pi pi-stop-circle" label="Close shift" outlined severity="danger" :disabled="!canCloseCurrentShift" @click="openCloseDialog" />
      </form>
    </section>

    <PMessage v-if="error" severity="error" :closable="false" class="setup-message">
      {{ error }}
    </PMessage>

    <PMessage v-if="successMessage" severity="success" :closable="false" class="setup-message">
      {{ successMessage }}
    </PMessage>

    <PMessage v-if="shiftData && !shiftData.current_shift" severity="warn" :closable="false" class="setup-message">
      No open shift is assigned to you. Open a shift before completing POS checkout.
    </PMessage>

    <section v-if="loading && !shiftData" class="stats-grid">
      <PSkeleton v-for="item in 6" :key="item" height="8rem" border-radius="8px" />
    </section>

    <template v-else-if="shiftData">
      <section class="stats-grid">
        <MetricCard label="Open shifts" :value="formatNumber(shiftData.summary.open_shifts)" icon="pi pi-clock" />
        <MetricCard label="Cash sales" :value="formatCurrency(shiftData.summary.cash_sales)" :caption="periodLabel" icon="pi pi-money-bill" tone="green" />
        <MetricCard label="Non-cash sales" :value="formatCurrency(shiftData.summary.non_cash_sales)" icon="pi pi-credit-card" tone="blue" />
        <MetricCard label="Cash in" :value="formatCurrency(shiftData.summary.cash_in_total)" icon="pi pi-arrow-down-left" tone="gold" />
        <MetricCard label="Cash out" :value="formatCurrency(shiftData.summary.cash_out_total)" icon="pi pi-arrow-up-right" tone="orange" />
        <MetricCard label="Short / over" :value="formatCurrency(shiftData.summary.short_over)" icon="pi pi-scale" :tone="shortOverTone(shiftData.summary.short_over)" />
      </section>

      <section class="analytics-grid">
        <BarChart
          title="Daily cash sales"
          eyebrow="End-of-day"
          :rows="shiftData.daily_shifts"
          key-field="business_date"
          label-field="label"
          value-field="cash_sales"
          caption="Cash payments by shift"
        />
        <BarChart
          title="Cash sales by branch"
          eyebrow="Branch drawer"
          :rows="shiftData.branch_summary"
          key-field="branch_id"
          label-field="branch_name"
          value-field="cash_sales"
          caption="Completed shift period"
        />
      </section>

      <section v-if="shiftData.current_shift" class="panel">
        <div class="panel__header">
          <div>
            <p class="eyebrow">Current drawer</p>
            <h2>{{ shiftData.current_shift.shift_number }}</h2>
          </div>
          <PTag value="Open" severity="success" />
        </div>

        <div class="drawer-summary-grid">
          <article>
            <span>Branch</span>
            <strong>{{ shiftData.current_shift.branch_name }}</strong>
            <small>{{ shiftData.current_shift.register_code }} - {{ shiftData.current_shift.register_name }}</small>
          </article>
          <article>
            <span>Opening cash</span>
            <strong>{{ formatCurrency(shiftData.current_shift.opening_cash) }}</strong>
            <small>{{ formatDateTime(shiftData.current_shift.opened_at) }}</small>
          </article>
          <article>
            <span>Expected cash</span>
            <strong>{{ formatCurrency(shiftData.current_shift.expected_cash) }}</strong>
            <small>Opening + cash sales + cash in - cash out</small>
          </article>
          <article>
            <span>Cash movements</span>
            <strong>{{ formatCurrency(shiftData.current_shift.cash_in_total - shiftData.current_shift.cash_out_total) }}</strong>
            <small>{{ formatCurrency(shiftData.current_shift.cash_in_total) }} in / {{ formatCurrency(shiftData.current_shift.cash_out_total) }} out</small>
          </article>
        </div>
      </section>

      <section class="panel">
        <div class="table-toolbar product-toolbar">
          <div>
            <p class="eyebrow">Shift register</p>
            <h2>Cashier shift history</h2>
          </div>
          <span class="search-field">
            <i class="pi pi-search" />
            <PInputText v-model.trim="shiftSearch" placeholder="Search shift, branch, cashier, register" />
          </span>
        </div>

        <PDataTable
          :value="filteredShifts"
          data-key="id"
          responsive-layout="stack"
          breakpoint="900px"
          size="small"
          striped-rows
          paginator
          :rows="10"
        >
          <PColumn field="shift_number" header="Shift">
            <template #body="{ data }">
              <div class="branch-cell">
                <strong>{{ data.shift_number }}</strong>
                <small>{{ formatDate(data.business_date) }} - {{ data.register_code }}</small>
              </div>
            </template>
          </PColumn>
          <PColumn field="branch_name" header="Branch" />
          <PColumn field="cashier_name" header="Cashier">
            <template #body="{ data }">
              <div class="branch-cell">
                <strong>{{ data.cashier_name }}</strong>
                <small>@{{ data.cashier_username }}</small>
              </div>
            </template>
          </PColumn>
          <PColumn field="status" header="Status">
            <template #body="{ data }">
              <PTag :value="statusLabel(data.status)" :severity="statusSeverity(data.status)" />
            </template>
          </PColumn>
          <PColumn field="cash_sales" header="Cash sales">
            <template #body="{ data }">{{ formatCurrency(data.cash_sales) }}</template>
          </PColumn>
          <PColumn field="expected_cash" header="Expected">
            <template #body="{ data }">{{ formatCurrency(data.expected_cash) }}</template>
          </PColumn>
          <PColumn field="counted_cash" header="Counted">
            <template #body="{ data }">{{ data.counted_cash === null ? '-' : formatCurrency(data.counted_cash) }}</template>
          </PColumn>
          <PColumn field="short_over" header="Short/Over">
            <template #body="{ data }">
              <PTag
                :value="data.short_over === null ? '-' : formatCurrency(data.short_over)"
                :severity="shortOverSeverity(data.short_over)"
              />
            </template>
          </PColumn>
          <PColumn header="Actions">
            <template #body="{ data }">
              <div class="table-actions">
                <PButton
                  icon="pi pi-plus-circle"
                  text
                  rounded
                  aria-label="Cash movement"
                  :disabled="data.status !== 'open'"
                  @click="openMovementDialog(data)"
                />
                <PButton
                  icon="pi pi-stop-circle"
                  text
                  rounded
                  severity="danger"
                  aria-label="Close shift"
                  :disabled="data.status !== 'open' || !canCloseShift(data)"
                  @click="openCloseDialog(data)"
                />
              </div>
            </template>
          </PColumn>
        </PDataTable>
      </section>

      <section class="analytics-grid">
        <section class="panel">
          <div class="panel__header">
            <div>
              <p class="eyebrow">Branch balancing</p>
              <h2>Drawer results by branch</h2>
            </div>
          </div>

          <PDataTable
            :value="shiftData.branch_summary"
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
            <PColumn field="open_shifts" header="Open" />
            <PColumn field="cash_sales" header="Cash sales">
              <template #body="{ data }">{{ formatCurrency(data.cash_sales) }}</template>
            </PColumn>
            <PColumn field="cash_in_total" header="Cash in">
              <template #body="{ data }">{{ formatCurrency(data.cash_in_total) }}</template>
            </PColumn>
            <PColumn field="cash_out_total" header="Cash out">
              <template #body="{ data }">{{ formatCurrency(data.cash_out_total) }}</template>
            </PColumn>
            <PColumn field="short_over" header="Short/Over">
              <template #body="{ data }">
                <PTag :value="formatCurrency(data.short_over)" :severity="shortOverSeverity(data.short_over)" />
              </template>
            </PColumn>
          </PDataTable>
        </section>

        <section class="panel">
          <div class="table-toolbar product-toolbar">
            <div>
              <p class="eyebrow">Cash drawer log</p>
              <h2>Latest movements</h2>
            </div>
            <span class="search-field">
              <i class="pi pi-search" />
              <PInputText v-model.trim="movementSearch" placeholder="Search movement, user, reason" />
            </span>
          </div>

          <PDataTable
            :value="filteredMovements"
            data-key="id"
            responsive-layout="stack"
            breakpoint="860px"
            size="small"
            striped-rows
            paginator
            :rows="8"
          >
            <PColumn field="movement_type" header="Type">
              <template #body="{ data }">
                <PTag :value="movementTypeLabel(data.movement_type)" :severity="movementSeverity(data.movement_type)" />
              </template>
            </PColumn>
            <PColumn field="amount" header="Amount">
              <template #body="{ data }">{{ formatCurrency(data.amount) }}</template>
            </PColumn>
            <PColumn field="shift_number" header="Shift" />
            <PColumn field="actor_name" header="User" />
            <PColumn field="reason" header="Reason">
              <template #body="{ data }">{{ data.reason || '-' }}</template>
            </PColumn>
            <PColumn field="created_at" header="Created">
              <template #body="{ data }">{{ formatDateTime(data.created_at) }}</template>
            </PColumn>
          </PDataTable>
        </section>
      </section>
    </template>

    <PDialog
      v-model:visible="openDialogVisible"
      modal
      header="Open cashier shift"
      class="branch-dialog"
      :style="{ width: 'min(520px, 96vw)' }"
    >
      <form class="dialog-form" @submit.prevent="submitOpenShift">
        <label>
          Branch
          <PSelect
            v-model="openForm.branch_id"
            :options="branchOptions"
            option-label="name"
            option-value="id"
            :disabled="isBranchLocked"
            fluid
          />
        </label>
        <label>
          Register
          <PSelect
            v-model="openForm.cash_register_id"
            :options="openRegisterOptions"
            option-label="label"
            option-value="value"
            fluid
          />
        </label>
        <label>
          Opening cash
          <PInputNumber v-model="openForm.opening_cash" mode="currency" :currency="currencyCode" locale="en-PH" :min="0" fluid />
        </label>
        <label>
          Notes
          <PTextarea v-model.trim="openForm.notes" rows="3" auto-resize fluid placeholder="Optional opening note" />
        </label>

        <div class="dialog-actions">
          <PButton type="button" label="Cancel" severity="secondary" outlined @click="openDialogVisible = false" />
          <PButton type="submit" icon="pi pi-play" label="Open shift" :loading="saving" />
        </div>
      </form>
    </PDialog>

    <PDialog
      v-model:visible="movementDialogVisible"
      modal
      header="Cash in / cash out"
      class="branch-dialog"
      :style="{ width: 'min(520px, 96vw)' }"
    >
      <form class="dialog-form" @submit.prevent="submitCashMovement">
        <PMessage v-if="selectedShift" severity="info" :closable="false" class="dialog-message">
          {{ selectedShift.shift_number }} - expected drawer cash {{ formatCurrency(selectedShift.expected_cash) }}
        </PMessage>

        <label>
          Movement
          <PSelect v-model="movementForm.movement_type" :options="movementOptions" option-label="label" option-value="value" fluid />
        </label>
        <label>
          Amount
          <PInputNumber v-model="movementForm.amount" mode="currency" :currency="currencyCode" locale="en-PH" :min="0" fluid />
        </label>
        <label>
          Reason
          <PTextarea v-model.trim="movementForm.reason" rows="3" auto-resize fluid placeholder="Reason for drawer movement" />
        </label>

        <div class="dialog-actions">
          <PButton type="button" label="Cancel" severity="secondary" outlined @click="movementDialogVisible = false" />
          <PButton type="submit" icon="pi pi-check" label="Save movement" :loading="saving" />
        </div>
      </form>
    </PDialog>

    <PDialog
      v-model:visible="closeDialogVisible"
      modal
      header="Close cashier shift"
      class="branch-dialog"
      :style="{ width: 'min(520px, 96vw)' }"
    >
      <form class="dialog-form" @submit.prevent="submitCloseShift">
        <PMessage v-if="selectedShift" severity="warn" :closable="false" class="dialog-message">
          Expected cash is {{ formatCurrency(selectedShift.expected_cash) }}. Count the drawer before closing.
        </PMessage>

        <label>
          Counted cash
          <PInputNumber v-model="closeForm.counted_cash" mode="currency" :currency="currencyCode" locale="en-PH" :min="0" fluid />
        </label>
        <label>
          Short / over preview
          <PInputText :model-value="formatCurrency(closeShortOver)" readonly fluid />
        </label>
        <label>
          Closing notes
          <PTextarea v-model.trim="closeForm.notes" rows="3" auto-resize fluid placeholder="Optional closing note" />
        </label>

        <div class="dialog-actions">
          <PButton type="button" label="Cancel" severity="secondary" outlined @click="closeDialogVisible = false" />
          <PButton type="submit" icon="pi pi-stop-circle" label="Close shift" severity="danger" :loading="saving" />
        </div>
      </form>
    </PDialog>
  </section>
</template>

<script setup>
import { computed, onMounted, reactive, ref, watch } from 'vue'
import BarChart from '../components/BarChart.vue'
import MetricCard from '../components/MetricCard.vue'
import { addDaysISO, currencyCode, formatCurrency, formatDate, formatNumber, todayISO, toISODate } from '../lib/formatters'
import { closeShift, fetchShiftManagement, openShift, saveCashMovement } from '../services/shiftService'
import { useAuthStore } from '../stores/authStore'

const auth = useAuthStore()
const loading = ref(false)
const saving = ref(false)
const error = ref('')
const successMessage = ref('')
const shiftData = ref(null)
const shiftSearch = ref('')
const movementSearch = ref('')
const selectedShift = ref(null)
const openDialogVisible = ref(false)
const movementDialogVisible = ref(false)
const closeDialogVisible = ref(false)

const filters = reactive({
  from: addDaysISO(-6),
  to: todayISO(),
  branchId: null,
})

const openForm = reactive({
  branch_id: null,
  cash_register_id: null,
  opening_cash: 0,
  notes: '',
})

const movementForm = reactive({
  shift_id: null,
  movement_type: 'cash_in',
  amount: 0,
  reason: '',
})

const closeForm = reactive({
  shift_id: null,
  counted_cash: 0,
  notes: '',
})

const movementOptions = [
  { label: 'Cash in', value: 'cash_in' },
  { label: 'Cash out', value: 'cash_out' },
]

const branchOptions = computed(() => shiftData.value?.branches || [])
const isBranchLocked = computed(() => ['manager', 'cashier'].includes(auth.state.profile?.role))
const canOpenShift = computed(() => Boolean(shiftData.value?.can_open_shift && !shiftData.value?.current_shift))
const canCloseCurrentShift = computed(() => canCloseShift(shiftData.value?.current_shift))
const periodLabel = computed(() => {
  const from = shiftData.value?.period?.from
  const to = shiftData.value?.period?.to
  if (!from || !to) return ''
  return `${formatDate(from)} to ${formatDate(to)}`
})
const openRegisterOptions = computed(() =>
  (shiftData.value?.registers || [])
    .filter((register) => !openForm.branch_id || register.branch_id === openForm.branch_id)
    .map((register) => ({
      label: `${register.register_code} - ${register.name}`,
      value: register.id,
      is_default: register.is_default,
    })),
)
const closeShortOver = computed(() => Number(closeForm.counted_cash || 0) - Number(selectedShift.value?.expected_cash || 0))
const filteredShifts = computed(() =>
  filterRows(shiftData.value?.shifts || [], shiftSearch.value, [
    'shift_number',
    'branch_code',
    'branch_name',
    'register_code',
    'register_name',
    'cashier_name',
    'cashier_username',
    'status',
  ]),
)
const filteredMovements = computed(() =>
  filterRows(shiftData.value?.movements || [], movementSearch.value, [
    'movement_type',
    'shift_number',
    'branch_name',
    'register_code',
    'actor_name',
    'actor_username',
    'reason',
  ]),
)

watch(
  () => openForm.branch_id,
  () => {
    if (!openRegisterOptions.value.some((register) => register.value === openForm.cash_register_id)) {
      openForm.cash_register_id = openRegisterOptions.value.find((register) => register.is_default)?.value || openRegisterOptions.value[0]?.value || null
    }
  },
)

function filterRows(rows, query, fields) {
  const normalized = String(query || '').trim().toLowerCase()
  if (!normalized) return rows

  return rows.filter((row) =>
    fields.some((field) =>
      String(row[field] || '')
        .toLowerCase()
        .includes(normalized),
    ),
  )
}

function shortOverTone(value) {
  if (Number(value || 0) === 0) return 'green'
  return Number(value || 0) > 0 ? 'gold' : 'red'
}

function shortOverSeverity(value) {
  if (value === null || value === undefined || Number(value || 0) === 0) return 'success'
  return Number(value || 0) > 0 ? 'warn' : 'danger'
}

function statusLabel(value) {
  if (value === 'closed') return 'Closed'
  if (value === 'void') return 'Void'
  if (value === 'closing') return 'Closing'
  return 'Open'
}

function statusSeverity(value) {
  if (value === 'closed') return 'info'
  if (value === 'void') return 'danger'
  if (value === 'closing') return 'warn'
  return 'success'
}

function movementTypeLabel(value) {
  if (value === 'cash_in') return 'Cash in'
  if (value === 'cash_out') return 'Cash out'
  if (value === 'opening') return 'Opening'
  if (value === 'closing_adjustment') return 'Closing'
  if (value === 'sale_cash') return 'Cash sale'
  if (value === 'change_given') return 'Change'
  return value
}

function movementSeverity(value) {
  if (value === 'cash_out' || value === 'change_given') return 'warn'
  if (value === 'closing_adjustment') return 'info'
  return 'success'
}

function canCloseShift(shift) {
  if (!shift || shift.status !== 'open') return false
  if (['admin', 'manager'].includes(auth.state.profile?.role)) return true
  return Boolean(auth.state.profile?.can_close_shift && shift.user_id === auth.state.profile?.id)
}

function resolveShift(shift = null) {
  const candidate = shift || shiftData.value?.current_shift || null
  if (!candidate) return null
  if (candidate.id) return candidate

  return (
    (shiftData.value?.shifts || []).find((item) => item.id && item.shift_number === candidate.shift_number) ||
    candidate
  )
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

function normalizeFilterDate(value) {
  return toISODate(value) || null
}

async function loadShifts() {
  loading.value = true
  error.value = ''
  successMessage.value = ''

  try {
    const data = await fetchShiftManagement({
      from: normalizeFilterDate(filters.from),
      to: normalizeFilterDate(filters.to),
      branchId: filters.branchId,
    })

    shiftData.value = data
    if (isBranchLocked.value && !filters.branchId) {
      filters.branchId = data.branches[0]?.id || null
    }
  } catch (loadError) {
    error.value = loadError.message
  } finally {
    loading.value = false
  }
}

function openOpenDialog() {
  const firstBranchId = filters.branchId || shiftData.value?.current_shift?.branch_id || shiftData.value?.branches?.[0]?.id || null

  Object.assign(openForm, {
    branch_id: firstBranchId,
    cash_register_id: null,
    opening_cash: 0,
    notes: '',
  })

  openForm.cash_register_id = openRegisterOptions.value.find((register) => register.is_default)?.value || openRegisterOptions.value[0]?.value || null
  openDialogVisible.value = true
}

function openMovementDialog(shift = null) {
  selectedShift.value = resolveShift(shift)
  if (!selectedShift.value?.id) {
    error.value = 'This shift cannot accept cash movement because its ID is missing. Refresh the Shifts page. If it still happens, rerun the latest Module 12 SQL.'
    return
  }

  Object.assign(movementForm, {
    shift_id: selectedShift.value.id,
    movement_type: 'cash_in',
    amount: 0,
    reason: '',
  })
  movementDialogVisible.value = Boolean(selectedShift.value)
}

function openCloseDialog(shift = null) {
  selectedShift.value = resolveShift(shift)
  if (!selectedShift.value?.id) {
    error.value = 'This shift cannot be closed because its ID is missing. Refresh the Shifts page. If it still happens, rerun the latest Module 12 SQL.'
    return
  }

  Object.assign(closeForm, {
    shift_id: selectedShift.value.id,
    counted_cash: selectedShift.value?.expected_cash || 0,
    notes: '',
  })
  closeDialogVisible.value = Boolean(selectedShift.value)
}

async function submitOpenShift() {
  saving.value = true
  error.value = ''
  successMessage.value = ''

  try {
    shiftData.value = await openShift(openForm)
    filters.branchId = openForm.branch_id || filters.branchId
    openDialogVisible.value = false
    successMessage.value = 'Shift opened. POS checkout can now complete sales for this drawer.'
  } catch (saveError) {
    error.value = saveError.message
  } finally {
    saving.value = false
  }
}

async function submitCashMovement() {
  saving.value = true
  error.value = ''
  successMessage.value = ''

  try {
    if (!movementForm.shift_id) {
      throw new Error('Cash movement needs a valid open shift. Refresh the Shifts page and try again.')
    }
    shiftData.value = await saveCashMovement(movementForm)
    movementDialogVisible.value = false
    successMessage.value = 'Cash drawer movement saved.'
  } catch (saveError) {
    error.value = saveError.message
  } finally {
    saving.value = false
  }
}

async function submitCloseShift() {
  saving.value = true
  error.value = ''
  successMessage.value = ''

  try {
    if (!closeForm.shift_id) {
      throw new Error('Shift closing needs a valid open shift. Refresh the Shifts page and try again.')
    }
    shiftData.value = await closeShift(closeForm)
    closeDialogVisible.value = false
    successMessage.value = `Shift closed with ${formatCurrency(closeShortOver.value)} short/over.`
  } catch (saveError) {
    error.value = saveError.message
  } finally {
    saving.value = false
  }
}

onMounted(loadShifts)
</script>
