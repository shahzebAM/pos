<template>
  <section class="page-stack">
    <section class="page-hero page-hero--compact">
      <div>
        <p class="eyebrow">Module 8</p>
        <h1>Philippines Invoice / BIR Compliance</h1>
        <p>
          Manage POS/CRM machine registration details, branch and machine serial
          numbering, invoice reprint/void controls, and X-reading/Z-reading summaries.
        </p>
      </div>

      <div class="action-panel">
        <PButton icon="pi pi-desktop" label="Add machine" :disabled="!canManageBir" @click="openMachine" />
        <PButton icon="pi pi-hashtag" label="Add series" outlined :disabled="!canManageBir" @click="openSeries" />
        <PButton icon="pi pi-file-export" label="Generate reading" outlined :disabled="!canManageBir && !canAudit" @click="openReading" />
        <PButton icon="pi pi-refresh" label="Refresh" outlined :loading="loading" @click="loadBir" />
      </div>
    </section>

    <PMessage v-if="!canManageBir" severity="warn" :closable="false" class="setup-message">
      You can view BIR compliance records with this role. Machine, series, void, and final reading actions are admin/manager controls.
    </PMessage>

    <PMessage v-if="error" severity="error" :closable="false" class="setup-message">
      {{ error }}
    </PMessage>

    <PMessage v-if="successMessage" severity="success" :closable="false" class="setup-message">
      {{ successMessage }}
    </PMessage>

    <section v-if="loading && !birData" class="stats-grid">
      <PSkeleton v-for="item in 6" :key="item" height="8rem" border-radius="8px" />
    </section>

    <template v-else-if="birData">
      <section class="stats-grid">
        <MetricCard label="Machines" :value="formatNumber(birData.summary.machines)" icon="pi pi-desktop" />
        <MetricCard label="Active machines" :value="formatNumber(birData.summary.active_machines)" icon="pi pi-check-circle" tone="blue" />
        <MetricCard label="Active series" :value="formatNumber(birData.summary.active_series)" icon="pi pi-hashtag" tone="gold" />
        <MetricCard label="Readings" :value="formatNumber(birData.summary.readings)" icon="pi pi-file-export" tone="purple" />
        <MetricCard label="Reprints" :value="formatNumber(birData.summary.reprinted_invoices)" icon="pi pi-print" tone="orange" />
        <MetricCard label="Voids" :value="formatNumber(birData.summary.voided_invoices)" icon="pi pi-ban" tone="red" />
      </section>

      <section class="panel">
        <div class="table-toolbar product-toolbar">
          <div>
            <p class="eyebrow">POS/CRM machines</p>
            <h2>Registered machine details</h2>
          </div>
          <div class="toolbar-controls">
            <span class="search-field">
              <i class="pi pi-search" />
              <PInputText v-model.trim="search" placeholder="Search machine, permit, invoice" />
            </span>
            <PSelect
              v-model="selectedBranchId"
              :options="branchFilterOptions"
              option-label="label"
              option-value="value"
              class="compact-select"
              :disabled="!canFilterBranches"
            />
          </div>
        </div>

        <PDataTable
          :value="filteredMachines"
          data-key="id"
          responsive-layout="stack"
          breakpoint="900px"
          size="small"
          striped-rows
          paginator
          :rows="6"
        >
          <PColumn field="machine_code" header="Machine">
            <template #body="{ data }">
              <div class="branch-cell">
                <strong>{{ data.machine_code }}</strong>
                <small>{{ data.machine_name }} - {{ data.branch_name }}</small>
              </div>
            </template>
          </PColumn>
          <PColumn field="machine_serial_number" header="Serial / MIN">
            <template #body="{ data }">
              {{ data.machine_serial_number || '-' }}
              <small class="muted-block">MIN {{ data.min_number || '-' }}</small>
            </template>
          </PColumn>
          <PColumn field="permit_number" header="Permit">
            <template #body="{ data }">
              {{ data.permit_number || '-' }}
              <small class="muted-block">Accreditation {{ data.accreditation_number || '-' }}</small>
            </template>
          </PColumn>
          <PColumn field="permit_valid_until" header="Validity">
            <template #body="{ data }">
              {{ data.permit_issued_at ? formatDate(data.permit_issued_at) : '-' }}
              <small class="muted-block">Until {{ data.permit_valid_until ? formatDate(data.permit_valid_until) : '-' }}</small>
            </template>
          </PColumn>
          <PColumn field="is_active" header="Status">
            <template #body="{ data }">
              <PTag :value="data.is_active ? (data.is_default ? 'Default' : 'Active') : 'Inactive'" :severity="data.is_active ? 'success' : 'danger'" />
            </template>
          </PColumn>
          <PColumn header="Actions">
            <template #body="{ data }">
              <PButton icon="pi pi-pencil" text rounded aria-label="Edit machine" :disabled="!canManageBir" @click="openMachine(data)" />
            </template>
          </PColumn>
        </PDataTable>
      </section>

      <section class="analytics-grid bir-detail-grid">
        <section class="panel">
          <div class="panel__header">
            <div>
              <p class="eyebrow">Serial control</p>
              <h2>Invoice series by branch and machine</h2>
            </div>
          </div>

          <PDataTable
            :value="filteredSeries"
            data-key="id"
            responsive-layout="stack"
            breakpoint="860px"
            size="small"
            striped-rows
            paginator
            :rows="6"
          >
            <PColumn field="document_title" header="Type">
              <template #body="{ data }">
                <div class="branch-cell">
                  <strong>{{ data.document_title }}</strong>
                  <small>{{ data.machine_code || 'Branch series' }}</small>
                </div>
              </template>
            </PColumn>
            <PColumn field="prefix" header="Prefix" />
            <PColumn field="current_number" header="Next">
              <template #body="{ data }">
                {{ formatNumber(data.current_number) }}
                <small class="muted-block">End {{ formatNumber(data.end_number) }}</small>
              </template>
            </PColumn>
            <PColumn field="remaining_numbers" header="Remaining">
              <template #body="{ data }">
                <PTag :value="formatNumber(data.remaining_numbers)" :severity="data.remaining_numbers < 100 ? 'danger' : 'success'" />
              </template>
            </PColumn>
            <PColumn header="Actions">
              <template #body="{ data }">
                <PButton icon="pi pi-pencil" text rounded aria-label="Edit series" :disabled="!canManageBir" @click="openSeries(data)" />
              </template>
            </PColumn>
          </PDataTable>
        </section>

        <section class="panel">
          <div class="panel__header">
            <div>
              <p class="eyebrow">X/Z readings</p>
              <h2>Reading history</h2>
            </div>
          </div>

          <PDataTable
            :value="filteredReadings"
            data-key="id"
            responsive-layout="stack"
            breakpoint="860px"
            size="small"
            striped-rows
            paginator
            :rows="6"
          >
            <PColumn field="reading_number" header="Reading">
              <template #body="{ data }">
                <div class="branch-cell">
                  <strong>{{ data.reading_number }}</strong>
                  <small>{{ data.machine_code || data.branch_name }} - {{ formatDate(data.business_date) }}</small>
                </div>
              </template>
            </PColumn>
            <PColumn field="reading_type" header="Type">
              <template #body="{ data }">
                <PTag :value="data.reading_type.toUpperCase()" :severity="data.reading_type === 'z' ? 'danger' : 'info'" />
              </template>
            </PColumn>
            <PColumn field="gross_sales" header="Gross">
              <template #body="{ data }">{{ formatCurrency(data.gross_sales) }}</template>
            </PColumn>
            <PColumn field="completed_order_count" header="Orders">
              <template #body="{ data }">
                {{ formatNumber(data.completed_order_count) }}
                <small class="muted-block">{{ formatNumber(data.voided_order_count) }} voids</small>
              </template>
            </PColumn>
          </PDataTable>
        </section>
      </section>

      <section class="panel">
        <div class="panel__header">
          <div>
            <p class="eyebrow">Invoice controls</p>
            <h2>Recent invoices, reprints, and voids</h2>
          </div>
        </div>

        <PDataTable
          :value="filteredOrders"
          data-key="id"
          responsive-layout="stack"
          breakpoint="940px"
          size="small"
          striped-rows
          paginator
          :rows="8"
        >
          <PColumn field="invoice_number" header="Invoice">
            <template #body="{ data }">
              <div class="branch-cell">
                <strong>{{ data.invoice_number || data.order_number }}</strong>
                <small>{{ data.bir_invoice_title || 'Sales Invoice' }} - {{ formatDateTime(data.created_at) }}</small>
              </div>
            </template>
          </PColumn>
          <PColumn field="branch_name" header="Branch" />
          <PColumn field="machine_code" header="Machine">
            <template #body="{ data }">{{ data.machine_code || '-' }}</template>
          </PColumn>
          <PColumn field="total" header="Total">
            <template #body="{ data }">{{ formatCurrency(data.total) }}</template>
          </PColumn>
          <PColumn field="status" header="Status">
            <template #body="{ data }">
              <PTag :value="data.status" :severity="data.status === 'completed' ? 'success' : 'danger'" />
              <small class="muted-block">{{ formatNumber(data.bir_reprint_count) }} reprints</small>
            </template>
          </PColumn>
          <PColumn header="Actions">
            <template #body="{ data }">
              <div class="table-actions">
                <PButton icon="pi pi-print" text rounded aria-label="Log reprint" @click="openReprint(data)" />
                <PButton
                  icon="pi pi-ban"
                  text
                  rounded
                  severity="danger"
                  aria-label="Void invoice"
                  :disabled="!canManageBir || data.status !== 'completed'"
                  @click="openVoid(data)"
                />
              </div>
            </template>
          </PColumn>
        </PDataTable>
      </section>
    </template>

    <PDialog v-model:visible="machineVisible" modal header="POS/CRM machine" class="branch-dialog" :style="{ width: 'min(920px, 96vw)' }">
      <form class="branch-form" @submit.prevent="saveMachine">
        <PMessage v-if="formError" severity="error" :closable="false" class="dialog-message">{{ formError }}</PMessage>

        <div class="form-grid">
          <label>
            Branch
            <PSelect v-model="machineForm.branch_id" :options="branchOptions" option-label="label" option-value="value" fluid :disabled="!canFilterBranches" />
          </label>
          <label>
            Machine code
            <PInputText v-model.trim="machineForm.machine_code" placeholder="HO-POS-01" fluid />
          </label>
          <label>
            Machine name
            <PInputText v-model.trim="machineForm.machine_name" placeholder="Main cashier terminal" fluid />
          </label>
          <label>
            Machine serial number
            <PInputText v-model.trim="machineForm.machine_serial_number" fluid />
          </label>
          <label>
            MIN
            <PInputText v-model.trim="machineForm.min_number" fluid />
          </label>
          <label>
            Accreditation number
            <PInputText v-model.trim="machineForm.accreditation_number" fluid />
          </label>
          <label>
            Permit number
            <PInputText v-model.trim="machineForm.permit_number" fluid />
          </label>
          <label>
            Permit issued
            <PDatePicker v-model="machineForm.permit_issued_at" date-format="yy-mm-dd" show-icon fluid />
          </label>
          <label>
            Permit valid until
            <PDatePicker v-model="machineForm.permit_valid_until" date-format="yy-mm-dd" show-icon fluid />
          </label>
          <label>
            Software version
            <PInputText v-model.trim="machineForm.software_version" fluid />
          </label>
        </div>

        <div class="switch-row">
          <label class="inline-check">
            <PCheckbox v-model="machineForm.is_default" binary />
            Default machine
          </label>
          <label class="inline-check">
            <PCheckbox v-model="machineForm.is_active" binary />
            Active
          </label>
        </div>

        <div class="dialog-actions">
          <PButton type="button" label="Cancel" severity="secondary" outlined @click="machineVisible = false" />
          <PButton type="submit" icon="pi pi-save" label="Save machine" :loading="saving" />
        </div>
      </form>
    </PDialog>

    <PDialog v-model:visible="seriesVisible" modal header="Invoice serial series" class="branch-dialog" :style="{ width: 'min(920px, 96vw)' }">
      <form class="branch-form" @submit.prevent="saveSeries">
        <PMessage v-if="formError" severity="error" :closable="false" class="dialog-message">{{ formError }}</PMessage>

        <div class="form-grid">
          <label>
            Branch
            <PSelect v-model="seriesForm.branch_id" :options="branchOptions" option-label="label" option-value="value" fluid :disabled="!canFilterBranches" />
          </label>
          <label>
            Machine
            <PSelect v-model="seriesForm.machine_id" :options="machineOptionsForBranch(seriesForm.branch_id)" option-label="label" option-value="value" show-clear fluid />
          </label>
          <label>
            Document type
            <PSelect v-model="seriesForm.document_type" :options="birData?.document_types || []" option-label="label" option-value="value" fluid />
          </label>
          <label>
            Prefix
            <PInputText v-model.trim="seriesForm.prefix" placeholder="HO-POS-01-" fluid />
          </label>
          <label>
            Start number
            <PInputNumber v-model="seriesForm.start_number" :min="1" :use-grouping="false" fluid />
          </label>
          <label>
            Current / next number
            <PInputNumber v-model="seriesForm.current_number" :min="1" :use-grouping="false" fluid />
          </label>
          <label>
            End number
            <PInputNumber v-model="seriesForm.end_number" :min="1" :use-grouping="false" fluid />
          </label>
          <label>
            Digits
            <PInputNumber v-model="seriesForm.digits" :min="4" :max="12" :use-grouping="false" fluid />
          </label>
          <label>
            Authority to print
            <PInputText v-model.trim="seriesForm.authority_to_print" fluid />
          </label>
          <label>
            ATP issued
            <PDatePicker v-model="seriesForm.atp_issued_at" date-format="yy-mm-dd" show-icon fluid />
          </label>
          <label>
            ATP valid until
            <PDatePicker v-model="seriesForm.atp_valid_until" date-format="yy-mm-dd" show-icon fluid />
          </label>
        </div>

        <div class="switch-row">
          <label class="inline-check">
            <PCheckbox v-model="seriesForm.is_default" binary />
            Default series
          </label>
          <label class="inline-check">
            <PCheckbox v-model="seriesForm.is_active" binary />
            Active
          </label>
        </div>

        <div class="dialog-actions">
          <PButton type="button" label="Cancel" severity="secondary" outlined @click="seriesVisible = false" />
          <PButton type="submit" icon="pi pi-save" label="Save series" :loading="saving" />
        </div>
      </form>
    </PDialog>

    <PDialog v-model:visible="readingVisible" modal header="Generate X/Z reading" class="branch-dialog" :style="{ width: 'min(680px, 96vw)' }">
      <form class="branch-form" @submit.prevent="saveReading">
        <PMessage v-if="formError" severity="error" :closable="false" class="dialog-message">{{ formError }}</PMessage>

        <div class="form-grid">
          <label>
            Branch
            <PSelect v-model="readingForm.branch_id" :options="branchOptions" option-label="label" option-value="value" fluid :disabled="!canFilterBranches" />
          </label>
          <label>
            Machine
            <PSelect v-model="readingForm.machine_id" :options="machineOptionsForBranch(readingForm.branch_id)" option-label="label" option-value="value" show-clear fluid />
          </label>
          <label>
            Reading type
            <PSelect v-model="readingForm.reading_type" :options="readingTypeOptions" option-label="label" option-value="value" fluid />
          </label>
          <label>
            Business date
            <PDatePicker v-model="readingForm.business_date" date-format="yy-mm-dd" show-icon fluid />
          </label>
        </div>

        <div class="dialog-actions">
          <PButton type="button" label="Cancel" severity="secondary" outlined @click="readingVisible = false" />
          <PButton type="submit" icon="pi pi-file-export" label="Generate" :loading="saving" />
        </div>
      </form>
    </PDialog>

    <PDialog v-model:visible="reasonVisible" modal :header="reasonMode === 'void' ? 'Void invoice' : 'Log invoice reprint'" class="branch-dialog" :style="{ width: 'min(620px, 96vw)' }">
      <form class="branch-form" @submit.prevent="saveReasonAction">
        <PMessage v-if="formError" severity="error" :closable="false" class="dialog-message">{{ formError }}</PMessage>

        <label>
          Reason
          <PTextarea v-model.trim="reasonText" rows="3" auto-resize fluid />
        </label>

        <div class="dialog-actions">
          <PButton type="button" label="Cancel" severity="secondary" outlined @click="reasonVisible = false" />
          <PButton type="submit" :icon="reasonMode === 'void' ? 'pi pi-ban' : 'pi pi-print'" :label="reasonMode === 'void' ? 'Void invoice' : 'Log reprint'" :severity="reasonMode === 'void' ? 'danger' : undefined" :loading="saving" />
        </div>
      </form>
    </PDialog>
  </section>
</template>

<script setup>
import { computed, onMounted, reactive, ref, watch } from 'vue'
import MetricCard from '../components/MetricCard.vue'
import { formatCurrency, formatDate, formatNumber, toISODate, todayISO } from '../lib/formatters'
import {
  fetchBirCompliance,
  generateBirReading,
  logInvoiceReprint,
  saveBirMachine,
  saveBirSeries,
  voidInvoice,
} from '../services/birComplianceService'
import { useAuthStore } from '../stores/authStore'

const auth = useAuthStore()
const loading = ref(false)
const saving = ref(false)
const error = ref('')
const successMessage = ref('')
const formError = ref('')
const search = ref('')
const selectedBranchId = ref(null)
const birData = ref(null)
const machineVisible = ref(false)
const seriesVisible = ref(false)
const readingVisible = ref(false)
const reasonVisible = ref(false)
const editingMachineId = ref(null)
const editingSeriesId = ref(null)
const selectedOrder = ref(null)
const reasonMode = ref('reprint')
const reasonText = ref('')

const machineForm = reactive(createMachineForm())
const seriesForm = reactive(createSeriesForm())
const readingForm = reactive(createReadingForm())

const readingTypeOptions = [
  { label: 'X-reading', value: 'x' },
  { label: 'Z-reading', value: 'z' },
]

const canManageBir = computed(() => auth.isAdmin.value || auth.state.profile?.role === 'manager')
const canAudit = computed(() => auth.state.profile?.role === 'auditor')
const canFilterBranches = computed(() => ['admin', 'auditor'].includes(auth.state.profile?.role))

const branchOptions = computed(() =>
  (birData.value?.branches || []).map((branch) => ({
    label: `${branch.branch_code} - ${branch.name}`,
    value: branch.id,
  })),
)

const branchFilterOptions = computed(() => [{ label: 'All branches', value: null }, ...branchOptions.value])

const filteredMachines = computed(() => filterBySearch(birData.value?.machines || [], ['branch_name', 'machine_code', 'machine_name', 'permit_number', 'min_number']))
const filteredSeries = computed(() => filterBySearch(birData.value?.series || [], ['branch_name', 'machine_code', 'document_title', 'prefix', 'authority_to_print']))
const filteredReadings = computed(() => filterBySearch(birData.value?.readings || [], ['reading_number', 'branch_name', 'machine_code', 'first_invoice_number', 'last_invoice_number']))
const filteredOrders = computed(() => filterBySearch(birData.value?.orders || [], ['invoice_number', 'order_number', 'branch_name', 'machine_code', 'cashier_name', 'bir_invoice_title']))

watch(selectedBranchId, async () => {
  if (!birData.value || !canFilterBranches.value) return
  await loadBir()
})

function filterBySearch(rows, keys) {
  const query = search.value.toLowerCase()

  return rows.filter((row) => {
    const matchesBranch = !selectedBranchId.value || row.branch_id === selectedBranchId.value
    const matchesSearch =
      !query ||
      keys
        .map((key) => row[key])
        .filter(Boolean)
        .some((value) => String(value).toLowerCase().includes(query))

    return matchesBranch && matchesSearch
  })
}

function defaultBranchId() {
  return selectedBranchId.value || auth.state.profile?.branch_id || birData.value?.branches?.[0]?.id || null
}

function createMachineForm() {
  return {
    branch_id: null,
    machine_code: '',
    machine_name: '',
    machine_serial_number: '',
    min_number: '',
    accreditation_number: '',
    permit_number: '',
    permit_issued_at: null,
    permit_valid_until: null,
    software_name: 'Clean Build POS',
    software_version: '',
    is_default: false,
    is_active: true,
  }
}

function createSeriesForm() {
  return {
    branch_id: null,
    machine_id: null,
    document_type: 'sales_invoice',
    prefix: 'INV-',
    start_number: 1,
    current_number: 1,
    end_number: 9999999,
    digits: 7,
    authority_to_print: '',
    atp_issued_at: null,
    atp_valid_until: null,
    is_default: false,
    is_active: true,
  }
}

function createReadingForm() {
  return {
    branch_id: null,
    machine_id: null,
    reading_type: 'x',
    business_date: new Date(`${todayISO()}T00:00:00`),
  }
}

function resetReactive(target, source) {
  Object.assign(target, source)
}

function asDate(value) {
  return value ? new Date(`${value}T00:00:00`) : null
}

function machineOptionsForBranch(branchId) {
  return (birData.value?.machines || [])
    .filter((machine) => !branchId || machine.branch_id === branchId)
    .map((machine) => ({
      label: `${machine.machine_code} - ${machine.machine_name}`,
      value: machine.id,
    }))
}

async function loadBir() {
  loading.value = true
  error.value = ''
  successMessage.value = ''

  try {
    birData.value = await fetchBirCompliance(canFilterBranches.value ? selectedBranchId.value : null)
    if (!selectedBranchId.value && !canFilterBranches.value) {
      selectedBranchId.value = defaultBranchId()
    }
  } catch (loadError) {
    error.value = loadError.message
  } finally {
    loading.value = false
  }
}

function openMachine(machine = null) {
  formError.value = ''
  editingMachineId.value = machine?.id || null
  resetReactive(machineForm, {
    ...createMachineForm(),
    ...machine,
    branch_id: machine?.branch_id || defaultBranchId(),
    permit_issued_at: asDate(machine?.permit_issued_at),
    permit_valid_until: asDate(machine?.permit_valid_until),
  })
  machineVisible.value = true
}

function openSeries(series = null) {
  formError.value = ''
  editingSeriesId.value = series?.id || null
  resetReactive(seriesForm, {
    ...createSeriesForm(),
    ...series,
    branch_id: series?.branch_id || defaultBranchId(),
    atp_issued_at: asDate(series?.atp_issued_at),
    atp_valid_until: asDate(series?.atp_valid_until),
  })
  seriesVisible.value = true
}

function openReading() {
  formError.value = ''
  resetReactive(readingForm, {
    ...createReadingForm(),
    branch_id: defaultBranchId(),
  })
  readingVisible.value = true
}

function openReprint(order) {
  selectedOrder.value = order
  reasonMode.value = 'reprint'
  reasonText.value = 'Customer copy'
  formError.value = ''
  reasonVisible.value = true
}

function openVoid(order) {
  selectedOrder.value = order
  reasonMode.value = 'void'
  reasonText.value = ''
  formError.value = ''
  reasonVisible.value = true
}

function validateMachine() {
  if (!machineForm.branch_id || !machineForm.machine_code || !machineForm.machine_name) {
    formError.value = 'Branch, machine code, and machine name are required.'
    return false
  }
  return true
}

function validateSeries() {
  if (!seriesForm.branch_id || !seriesForm.document_type || !seriesForm.prefix) {
    formError.value = 'Branch, document type, and prefix are required.'
    return false
  }
  if (Number(seriesForm.current_number || 0) > Number(seriesForm.end_number || 0)) {
    formError.value = 'Current number cannot be higher than end number.'
    return false
  }
  return true
}

async function saveMachine() {
  if (!validateMachine()) return

  saving.value = true
  formError.value = ''

  try {
    birData.value = await saveBirMachine(editingMachineId.value, {
      ...machineForm,
      permit_issued_at: toISODate(machineForm.permit_issued_at),
      permit_valid_until: toISODate(machineForm.permit_valid_until),
    })
    machineVisible.value = false
    successMessage.value = 'Machine saved.'
  } catch (saveError) {
    formError.value = saveError.message
  } finally {
    saving.value = false
  }
}

async function saveSeries() {
  if (!validateSeries()) return

  saving.value = true
  formError.value = ''

  try {
    birData.value = await saveBirSeries(editingSeriesId.value, {
      ...seriesForm,
      atp_issued_at: toISODate(seriesForm.atp_issued_at),
      atp_valid_until: toISODate(seriesForm.atp_valid_until),
    })
    seriesVisible.value = false
    successMessage.value = 'Invoice series saved.'
  } catch (saveError) {
    formError.value = saveError.message
  } finally {
    saving.value = false
  }
}

async function saveReading() {
  if (!readingForm.branch_id) {
    formError.value = 'Branch is required.'
    return
  }

  saving.value = true
  formError.value = ''

  try {
    birData.value = await generateBirReading({
      ...readingForm,
      business_date: toISODate(readingForm.business_date),
    })
    readingVisible.value = false
    successMessage.value = `${readingForm.reading_type.toUpperCase()}-reading generated.`
  } catch (saveError) {
    formError.value = saveError.message
  } finally {
    saving.value = false
  }
}

async function saveReasonAction() {
  if (!reasonText.value.trim()) {
    formError.value = 'Reason is required.'
    return
  }

  saving.value = true
  formError.value = ''

  try {
    birData.value =
      reasonMode.value === 'void'
        ? await voidInvoice(selectedOrder.value.id, reasonText.value)
        : await logInvoiceReprint(selectedOrder.value.id, reasonText.value)
    reasonVisible.value = false
    successMessage.value = reasonMode.value === 'void' ? 'Invoice voided and stock reversed.' : 'Invoice reprint logged.'
  } catch (saveError) {
    formError.value = saveError.message
  } finally {
    saving.value = false
  }
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

onMounted(loadBir)
</script>
