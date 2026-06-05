<template>
  <section class="page-stack">
    <section class="page-hero">
      <div>
        <p class="eyebrow">Module 9</p>
        <h2>Tax setup, VAT tracking, and BIR tax reports from completed POS sales.</h2>
        <p>
          Configure branch tax profiles, maintain tax codes, and review VATable,
          VAT-exempt, zero-rated, non-VAT, and percentage-tax summaries.
        </p>
      </div>

      <form class="filter-panel" @submit.prevent="loadTax">
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
        <PButton type="button" icon="pi pi-percentage" label="Add profile" outlined :disabled="!canManageTax" @click="openProfile" />
        <PButton type="button" icon="pi pi-tags" label="Add tax code" outlined :disabled="!canManageTax" @click="openCode" />
      </form>
    </section>

    <PMessage v-if="!canManageTax" severity="warn" :closable="false" class="setup-message">
      You can view tax reports with this role. Tax setup changes are admin-only.
    </PMessage>

    <PMessage v-if="error" severity="error" :closable="false" class="setup-message">
      {{ error }}
    </PMessage>

    <PMessage v-if="successMessage" severity="success" :closable="false" class="setup-message">
      {{ successMessage }}
    </PMessage>

    <section v-if="loading && !taxData" class="stats-grid">
      <PSkeleton v-for="item in 6" :key="item" height="8rem" border-radius="8px" />
    </section>

    <template v-else-if="taxData">
      <section class="stats-grid">
        <MetricCard label="Gross sales" :value="formatCurrency(taxData.summary.gross_sales)" :caption="periodLabel" icon="pi pi-wallet" />
        <MetricCard label="VATable sales" :value="formatCurrency(taxData.summary.vatable_sales)" caption="VAT base" icon="pi pi-check-circle" tone="blue" />
        <MetricCard label="Output VAT" :value="formatCurrency(taxData.summary.vat_output)" caption="From completed invoices" icon="pi pi-percentage" tone="purple" />
        <MetricCard label="Percentage tax" :value="formatCurrency(taxData.summary.percentage_tax_due)" caption="Configured branch estimate" icon="pi pi-receipt" tone="gold" />
        <MetricCard label="Total tax due" :value="formatCurrency(taxData.summary.total_tax_due)" caption="VAT plus percentage tax" icon="pi pi-file-check" tone="green" />
        <MetricCard label="Orders" :value="formatNumber(taxData.summary.order_count)" caption="Completed only" icon="pi pi-shopping-bag" tone="orange" />
      </section>

      <section class="analytics-grid">
        <BarChart
          title="Output VAT by branch"
          eyebrow="BIR tax reports"
          :rows="taxData.tax_by_branch"
          key-field="branch_id"
          label-field="branch_name"
          value-field="vat_output"
          caption="Completed invoices"
        />
        <BarChart
          title="Sales by tax class"
          eyebrow="Tax mix"
          :rows="taxData.tax_mix"
          key-field="tax_type"
          label-field="label"
          value-field="net_amount"
          caption="Net invoice value"
        />
      </section>

      <section class="panel">
        <div class="table-toolbar product-toolbar">
          <div>
            <p class="eyebrow">Branch tax setup</p>
            <h2>Branch profiles and tax defaults</h2>
          </div>
          <span class="search-field">
            <i class="pi pi-search" />
            <PInputText v-model.trim="search" placeholder="Search branch, profile, tax type" />
          </span>
        </div>

        <PDataTable
          :value="filteredBranchProfiles"
          data-key="branch_id"
          responsive-layout="stack"
          breakpoint="900px"
          size="small"
          striped-rows
          paginator
          :rows="8"
        >
          <PColumn field="branch_name" header="Branch">
            <template #body="{ data }">
              <div class="branch-cell">
                <strong>{{ data.branch_name }}</strong>
                <small>{{ data.branch_code }}</small>
              </div>
            </template>
          </PColumn>
          <PColumn field="tax_profile_name" header="Profile">
            <template #body="{ data }">
              <PTag :value="data.tax_profile_code" :severity="registrationSeverity(data.registration_type)" />
              <small class="muted-block">{{ data.tax_profile_name }}</small>
            </template>
          </PColumn>
          <PColumn field="registration_type" header="Registration">
            <template #body="{ data }">{{ registrationLabel(data.registration_type) }}</template>
          </PColumn>
          <PColumn field="vat_rate" header="VAT">
            <template #body="{ data }">{{ formatRate(data.vat_rate) }}</template>
          </PColumn>
          <PColumn field="percentage_tax_rate" header="Percentage">
            <template #body="{ data }">{{ formatRate(data.percentage_tax_rate) }}</template>
          </PColumn>
          <PColumn field="tax_inclusive_default" header="Pricing">
            <template #body="{ data }">{{ data.tax_inclusive_default ? 'Tax inclusive' : 'Tax exclusive' }}</template>
          </PColumn>
          <PColumn header="Actions">
            <template #body="{ data }">
              <PButton icon="pi pi-pencil" text rounded aria-label="Edit branch tax settings" :disabled="!canManageTax" @click="openBranchSettings(data)" />
            </template>
          </PColumn>
        </PDataTable>
      </section>

      <section class="analytics-grid">
        <section class="panel">
          <div class="panel__header">
            <div>
              <p class="eyebrow">BIR report lines</p>
              <h2>Tax summary for selected period</h2>
            </div>
          </div>

          <PDataTable :value="taxData.tax_report_lines" data-key="line_code" responsive-layout="stack" breakpoint="860px" size="small" striped-rows>
            <PColumn field="line_code" header="Line" />
            <PColumn field="label" header="Description">
              <template #body="{ data }">
                {{ data.label }}
                <small class="muted-block">{{ data.notes }}</small>
              </template>
            </PColumn>
            <PColumn field="amount" header="Amount">
              <template #body="{ data }">{{ formatCurrency(data.amount) }}</template>
            </PColumn>
          </PDataTable>
        </section>

        <section class="panel">
          <div class="panel__header">
            <div>
              <p class="eyebrow">Product tax mix</p>
              <h2>Catalog tax tagging</h2>
            </div>
          </div>

          <PDataTable :value="taxData.product_tax_mix" data-key="tax_type" responsive-layout="stack" breakpoint="860px" size="small" striped-rows>
            <PColumn field="label" header="Tax class" />
            <PColumn field="products" header="Products">
              <template #body="{ data }">{{ formatNumber(data.products) }}</template>
            </PColumn>
            <PColumn field="active_products" header="Active">
              <template #body="{ data }">{{ formatNumber(data.active_products) }}</template>
            </PColumn>
            <PColumn field="average_rate" header="Avg. rate">
              <template #body="{ data }">{{ formatRate(data.average_rate) }}</template>
            </PColumn>
          </PDataTable>
        </section>
      </section>

      <section class="analytics-grid">
        <section class="panel">
          <div class="panel__header">
            <div>
              <p class="eyebrow">Tax profiles</p>
              <h2>Registration and branch defaults</h2>
            </div>
          </div>

          <PDataTable :value="taxData.tax_profiles" data-key="id" responsive-layout="stack" breakpoint="860px" size="small" striped-rows paginator :rows="6">
            <PColumn field="code" header="Code">
              <template #body="{ data }">
                <strong>{{ data.code }}</strong>
                <small class="muted-block">{{ data.is_default ? 'Default profile' : data.is_active ? 'Active' : 'Inactive' }}</small>
              </template>
            </PColumn>
            <PColumn field="name" header="Name" />
            <PColumn field="registration_type" header="Registration">
              <template #body="{ data }">{{ registrationLabel(data.registration_type) }}</template>
            </PColumn>
            <PColumn field="vat_rate" header="VAT">
              <template #body="{ data }">{{ formatRate(data.vat_rate) }}</template>
            </PColumn>
            <PColumn field="percentage_tax_rate" header="Percentage">
              <template #body="{ data }">{{ formatRate(data.percentage_tax_rate) }}</template>
            </PColumn>
            <PColumn header="Actions">
              <template #body="{ data }">
                <PButton icon="pi pi-pencil" text rounded aria-label="Edit tax profile" :disabled="!canManageTax" @click="openProfile(data)" />
              </template>
            </PColumn>
          </PDataTable>
        </section>

        <section class="panel">
          <div class="panel__header">
            <div>
              <p class="eyebrow">Tax codes</p>
              <h2>Product tax classifications</h2>
            </div>
          </div>

          <PDataTable :value="taxData.tax_codes" data-key="id" responsive-layout="stack" breakpoint="860px" size="small" striped-rows paginator :rows="6">
            <PColumn field="code" header="Code">
              <template #body="{ data }">
                <strong>{{ data.code }}</strong>
                <small class="muted-block">{{ data.is_active ? 'Active' : 'Inactive' }}</small>
              </template>
            </PColumn>
            <PColumn field="name" header="Name" />
            <PColumn field="tax_type" header="Type">
              <template #body="{ data }">
                <PTag :value="taxTypeLabel(data.tax_type)" :severity="taxTypeSeverity(data.tax_type)" />
              </template>
            </PColumn>
            <PColumn field="rate" header="Rate">
              <template #body="{ data }">{{ formatRate(data.rate) }}</template>
            </PColumn>
            <PColumn field="bir_report_group" header="Report group">
              <template #body="{ data }">{{ reportGroupLabel(data.bir_report_group) }}</template>
            </PColumn>
            <PColumn header="Actions">
              <template #body="{ data }">
                <PButton icon="pi pi-pencil" text rounded aria-label="Edit tax code" :disabled="!canManageTax" @click="openCode(data)" />
              </template>
            </PColumn>
          </PDataTable>
        </section>
      </section>
    </template>

    <PDialog v-model:visible="profileVisible" modal :header="editingProfileId ? 'Edit tax profile' : 'Add tax profile'" class="branch-dialog" :style="{ width: 'min(760px, 96vw)' }">
      <form class="branch-form" @submit.prevent="saveProfile">
        <PMessage v-if="formError" severity="error" :closable="false" class="dialog-message">{{ formError }}</PMessage>

        <div class="form-grid">
          <label>
            Code
            <PInputText v-model.trim="profileForm.code" placeholder="VAT12" fluid />
          </label>
          <label>
            Name
            <PInputText v-model.trim="profileForm.name" placeholder="VAT Registered - 12%" fluid />
          </label>
          <label>
            Registration type
            <PSelect v-model="profileForm.registration_type" :options="registrationOptions" option-label="label" option-value="value" fluid />
          </label>
          <label>
            VAT rate
            <PInputNumber v-model="profileForm.vat_rate" suffix="%" :min="0" :max="100" :min-fraction-digits="2" fluid />
          </label>
          <label>
            Percentage tax rate
            <PInputNumber v-model="profileForm.percentage_tax_rate" suffix="%" :min="0" :max="100" :min-fraction-digits="2" fluid />
          </label>
        </div>

        <label>
          Notes
          <PTextarea v-model.trim="profileForm.notes" rows="3" auto-resize fluid />
        </label>

        <div class="switch-row">
          <label>
            <PCheckbox v-model="profileForm.tax_inclusive_default" binary />
            Tax inclusive by default
          </label>
          <label>
            <PCheckbox v-model="profileForm.is_default" binary />
            Default profile
          </label>
          <label>
            <PCheckbox v-model="profileForm.is_active" binary />
            Active
          </label>
        </div>

        <div class="dialog-actions">
          <PButton type="button" label="Cancel" severity="secondary" outlined @click="profileVisible = false" />
          <PButton type="submit" icon="pi pi-save" label="Save profile" :loading="saving" />
        </div>
      </form>
    </PDialog>

    <PDialog v-model:visible="codeVisible" modal :header="editingCodeId ? 'Edit tax code' : 'Add tax code'" class="branch-dialog" :style="{ width: 'min(760px, 96vw)' }">
      <form class="branch-form" @submit.prevent="saveCode">
        <PMessage v-if="formError" severity="error" :closable="false" class="dialog-message">{{ formError }}</PMessage>

        <div class="form-grid">
          <label>
            Code
            <PInputText v-model.trim="codeForm.code" placeholder="VAT12" fluid />
          </label>
          <label>
            Name
            <PInputText v-model.trim="codeForm.name" placeholder="VATable Sales - 12%" fluid />
          </label>
          <label>
            Tax type
            <PSelect v-model="codeForm.tax_type" :options="taxTypeOptions" option-label="label" option-value="value" fluid />
          </label>
          <label>
            Rate
            <PInputNumber v-model="codeForm.rate" suffix="%" :min="0" :max="100" :min-fraction-digits="2" fluid />
          </label>
          <label>
            BIR report group
            <PSelect v-model="codeForm.bir_report_group" :options="reportGroupOptions" option-label="label" option-value="value" fluid />
          </label>
        </div>

        <label>
          Notes
          <PTextarea v-model.trim="codeForm.notes" rows="3" auto-resize fluid />
        </label>

        <div class="switch-row">
          <label>
            <PCheckbox v-model="codeForm.affects_output_vat" binary />
            Affects output VAT
          </label>
          <label>
            <PCheckbox v-model="codeForm.is_active" binary />
            Active
          </label>
        </div>

        <div class="dialog-actions">
          <PButton type="button" label="Cancel" severity="secondary" outlined @click="codeVisible = false" />
          <PButton type="submit" icon="pi pi-save" label="Save tax code" :loading="saving" />
        </div>
      </form>
    </PDialog>

    <PDialog v-model:visible="branchVisible" modal header="Branch tax settings" class="branch-dialog" :style="{ width: 'min(680px, 96vw)' }">
      <form class="branch-form" @submit.prevent="saveBranchSettings">
        <PMessage v-if="formError" severity="error" :closable="false" class="dialog-message">{{ formError }}</PMessage>

        <div class="form-grid">
          <label>
            Tax profile
            <PSelect v-model="branchForm.tax_profile_id" :options="profileOptions" option-label="label" option-value="value" fluid />
          </label>
          <label>
            VAT rate
            <PInputNumber v-model="branchForm.vat_rate" suffix="%" :min="0" :max="100" :min-fraction-digits="2" fluid />
          </label>
          <label>
            Percentage tax rate
            <PInputNumber v-model="branchForm.percentage_tax_rate" suffix="%" :min="0" :max="100" :min-fraction-digits="2" fluid />
          </label>
        </div>

        <div class="switch-row">
          <label>
            <PCheckbox v-model="branchForm.tax_inclusive_default" binary />
            Tax inclusive by default
          </label>
        </div>

        <div class="dialog-actions">
          <PButton type="button" label="Cancel" severity="secondary" outlined @click="branchVisible = false" />
          <PButton type="submit" icon="pi pi-save" label="Save branch tax" :loading="saving" />
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
import { fetchTaxManagement, saveBranchTaxSettings, saveTaxCode, saveTaxProfile } from '../services/taxService'
import { useAuthStore } from '../stores/authStore'

const auth = useAuthStore()
const loading = ref(false)
const saving = ref(false)
const error = ref('')
const successMessage = ref('')
const formError = ref('')
const taxData = ref(null)
const search = ref('')
const profileVisible = ref(false)
const codeVisible = ref(false)
const branchVisible = ref(false)
const editingProfileId = ref(null)
const editingCodeId = ref(null)
const editingBranchId = ref(null)

const filters = reactive({
  from: new Date(`${addDaysISO(-29)}T00:00:00`),
  to: new Date(`${todayISO()}T00:00:00`),
  branchId: null,
})

const profileForm = reactive(createProfileForm())
const codeForm = reactive(createCodeForm())
const branchForm = reactive(createBranchForm())

const registrationOptions = [
  { label: 'VAT registered', value: 'vat_registered' },
  { label: 'Non-VAT / percentage tax', value: 'non_vat_percentage' },
  { label: 'Mixed tax profile', value: 'mixed' },
]

const taxTypeOptions = [
  { label: 'VATable', value: 'vatable' },
  { label: 'VAT-exempt', value: 'vat_exempt' },
  { label: 'Zero-rated', value: 'zero_rated' },
  { label: 'Non-VAT', value: 'non_vat' },
]

const reportGroupOptions = [
  { label: 'VATable sales', value: 'vatable_sales' },
  { label: 'VAT-exempt sales', value: 'vat_exempt_sales' },
  { label: 'Zero-rated sales', value: 'zero_rated_sales' },
  { label: 'Non-VAT sales', value: 'non_vat_sales' },
  { label: 'Percentage tax', value: 'percentage_tax' },
]

const canManageTax = computed(() => auth.isAdmin.value)

const branchOptions = computed(() => [
  { id: null, name: 'All branches' },
  ...(taxData.value?.branches || []),
])

const profileOptions = computed(() =>
  (taxData.value?.tax_profiles || [])
    .filter((profile) => profile.is_active)
    .map((profile) => ({
      label: `${profile.code} - ${profile.name}`,
      value: profile.id,
    })),
)

const filteredBranchProfiles = computed(() => {
  const query = search.value.toLowerCase()
  const rows = taxData.value?.branch_profiles || []

  if (!query) return rows

  return rows.filter((row) =>
    [
      row.branch_code,
      row.branch_name,
      row.tax_profile_code,
      row.tax_profile_name,
      registrationLabel(row.registration_type),
    ]
      .filter(Boolean)
      .some((value) => String(value).toLowerCase().includes(query)),
  )
})

const periodLabel = computed(() => {
  const from = taxData.value?.period?.from || toISODate(filters.from)
  const to = taxData.value?.period?.to || toISODate(filters.to)

  return `${formatDate(from)} to ${formatDate(to)}`
})

function createProfileForm() {
  return {
    code: '',
    name: '',
    registration_type: 'vat_registered',
    vat_rate: 12,
    percentage_tax_rate: 0,
    tax_inclusive_default: true,
    is_default: false,
    is_active: true,
    notes: '',
  }
}

function createCodeForm() {
  return {
    code: '',
    name: '',
    tax_type: 'vatable',
    rate: 12,
    bir_report_group: 'vatable_sales',
    affects_output_vat: true,
    is_active: true,
    notes: '',
  }
}

function createBranchForm() {
  return {
    tax_profile_id: null,
    vat_rate: 12,
    percentage_tax_rate: 0,
    tax_inclusive_default: true,
  }
}

function resetReactive(target, source) {
  Object.assign(target, source)
}

function formatRate(value) {
  return `${formatNumber(Number(value || 0).toFixed(2))}%`
}

function registrationLabel(value) {
  return registrationOptions.find((option) => option.value === value)?.label || value || '-'
}

function registrationSeverity(value) {
  if (value === 'vat_registered') return 'success'
  if (value === 'non_vat_percentage') return 'warn'
  return 'info'
}

function taxTypeLabel(value) {
  return taxTypeOptions.find((option) => option.value === value)?.label || value
}

function taxTypeSeverity(value) {
  if (value === 'vatable') return 'success'
  if (value === 'vat_exempt') return 'info'
  if (value === 'zero_rated') return 'warn'
  return 'secondary'
}

function reportGroupLabel(value) {
  return reportGroupOptions.find((option) => option.value === value)?.label || value
}

async function loadTax(clearMessages = true) {
  loading.value = true
  if (clearMessages) {
    error.value = ''
    successMessage.value = ''
  }

  try {
    taxData.value = await fetchTaxManagement({
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

function openProfile(profile = null) {
  formError.value = ''
  editingProfileId.value = profile?.id || null
  resetReactive(profileForm, {
    ...createProfileForm(),
    ...profile,
    vat_rate: Number(profile?.vat_rate ?? 12),
    percentage_tax_rate: Number(profile?.percentage_tax_rate ?? 0),
    tax_inclusive_default: profile?.tax_inclusive_default ?? true,
    is_default: profile?.is_default ?? false,
    is_active: profile?.is_active ?? true,
  })
  profileVisible.value = true
}

function openCode(code = null) {
  formError.value = ''
  editingCodeId.value = code?.id || null
  resetReactive(codeForm, {
    ...createCodeForm(),
    ...code,
    rate: Number(code?.rate ?? 0),
    affects_output_vat: code ? code.affects_output_vat ?? code.tax_type === 'vatable' : true,
    is_active: code?.is_active ?? true,
  })
  codeVisible.value = true
}

function openBranchSettings(branch) {
  formError.value = ''
  editingBranchId.value = branch.branch_id
  resetReactive(branchForm, {
    ...createBranchForm(),
    tax_profile_id: branch.tax_profile_id,
    vat_rate: Number(branch.vat_rate || 0),
    percentage_tax_rate: Number(branch.percentage_tax_rate || 0),
    tax_inclusive_default: Boolean(branch.tax_inclusive_default),
  })
  branchVisible.value = true
}

function validateProfile() {
  if (!profileForm.code || !profileForm.name) {
    formError.value = 'Tax profile code and name are required.'
    return false
  }

  return true
}

function validateCode() {
  if (!codeForm.code || !codeForm.name) {
    formError.value = 'Tax code and name are required.'
    return false
  }

  return true
}

async function saveProfile() {
  if (!validateProfile()) return

  saving.value = true
  formError.value = ''
  error.value = ''

  try {
    await saveTaxProfile(editingProfileId.value, { ...profileForm })
    profileVisible.value = false
    successMessage.value = 'Tax profile saved.'
    await loadTax(false)
  } catch (saveError) {
    formError.value = saveError.message
  } finally {
    saving.value = false
  }
}

async function saveCode() {
  if (!validateCode()) return

  saving.value = true
  formError.value = ''
  error.value = ''

  try {
    await saveTaxCode(editingCodeId.value, { ...codeForm })
    codeVisible.value = false
    successMessage.value = 'Tax code saved.'
    await loadTax(false)
  } catch (saveError) {
    formError.value = saveError.message
  } finally {
    saving.value = false
  }
}

async function saveBranchSettings() {
  if (!editingBranchId.value) {
    formError.value = 'Branch is required.'
    return
  }

  saving.value = true
  formError.value = ''
  error.value = ''

  try {
    await saveBranchTaxSettings(editingBranchId.value, { ...branchForm })
    branchVisible.value = false
    successMessage.value = 'Branch tax settings saved.'
    await loadTax(false)
  } catch (saveError) {
    formError.value = saveError.message
  } finally {
    saving.value = false
  }
}

onMounted(loadTax)
</script>
