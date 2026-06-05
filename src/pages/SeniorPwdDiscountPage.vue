<template>
  <section class="page-stack">
    <section class="page-hero">
      <div>
        <p class="eyebrow">Module 10</p>
        <h2>Senior Citizen and PWD discount control center.</h2>
        <p>
          Configure statutory discount rates, tag product eligibility, capture OSCA/PWD claim details,
          and review branch-wise Senior/PWD benefit reports from completed invoices.
        </p>
      </div>

      <form class="filter-panel" @submit.prevent="loadSeniorPwd">
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

    <PMessage v-if="!canManageSeniorPwd" severity="warn" :closable="false" class="setup-message">
      You can view Senior/PWD reports with this role. Rate and product eligibility changes are admin-only.
    </PMessage>

    <PMessage v-if="error" severity="error" :closable="false" class="setup-message">
      {{ error }}
    </PMessage>

    <PMessage v-if="successMessage" severity="success" :closable="false" class="setup-message">
      {{ successMessage }}
    </PMessage>

    <section v-if="loading && !seniorPwdData" class="stats-grid">
      <PSkeleton v-for="item in 6" :key="item" height="8rem" border-radius="8px" />
    </section>

    <template v-else-if="seniorPwdData">
      <section class="stats-grid">
        <MetricCard label="Total claims" :value="formatNumber(seniorPwdData.summary.claims)" :caption="periodLabel" icon="pi pi-id-card" />
        <MetricCard label="Senior claims" :value="formatNumber(seniorPwdData.summary.senior_claims)" icon="pi pi-users" tone="blue" />
        <MetricCard label="PWD claims" :value="formatNumber(seniorPwdData.summary.pwd_claims)" icon="pi pi-heart" tone="purple" />
        <MetricCard label="20% discounts" :value="formatCurrency(seniorPwdData.summary.regular_discount_amount)" icon="pi pi-percentage" tone="green" />
        <MetricCard label="5% special" :value="formatCurrency(seniorPwdData.summary.special_discount_amount)" icon="pi pi-tags" tone="gold" />
        <MetricCard label="VAT exemption" :value="formatCurrency(seniorPwdData.summary.vat_exempt_amount)" icon="pi pi-receipt" tone="orange" />
      </section>

      <section class="analytics-grid">
        <BarChart
          title="Daily Senior/PWD benefits"
          eyebrow="Discount claims"
          :rows="seniorPwdData.daily_claims"
          key-field="business_date"
          label-field="label"
          value-field="total_discount_amount"
          caption="Discount plus VAT exemption"
        />
        <BarChart
          title="Branch benefit comparison"
          eyebrow="Branch performance"
          :rows="seniorPwdData.branch_settings"
          key-field="branch_id"
          label-field="branch_name"
          value-field="total_benefit"
          caption="Completed invoices only"
        />
      </section>

      <section class="panel">
        <div class="table-toolbar product-toolbar">
          <div>
            <p class="eyebrow">Branch setup</p>
            <h2>Senior/PWD rates and capture rules</h2>
          </div>
          <span class="search-field">
            <i class="pi pi-search" />
            <PInputText v-model.trim="settingsSearch" placeholder="Search branch or RDO code" />
          </span>
        </div>

        <PDataTable
          :value="filteredBranchSettings"
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
          <PColumn field="standard_discount_rate" header="Standard">
            <template #body="{ data }">{{ formatRate(data.standard_discount_rate || 20) }}</template>
          </PColumn>
          <PColumn field="basic_necessity_rate" header="Basic goods">
            <template #body="{ data }">{{ formatRate(data.basic_necessity_rate || 5) }}</template>
          </PColumn>
          <PColumn field="require_id_capture" header="ID capture">
            <template #body="{ data }">
              <PTag :value="data.require_id_capture === false ? 'Optional' : 'Required'" :severity="data.require_id_capture === false ? 'warn' : 'success'" />
            </template>
          </PColumn>
          <PColumn field="is_active" header="Status">
            <template #body="{ data }">
              <PTag :value="data.is_active === false ? 'Disabled' : 'Active'" :severity="data.is_active === false ? 'danger' : 'success'" />
            </template>
          </PColumn>
          <PColumn field="claims" header="Claims">
            <template #body="{ data }">{{ formatNumber(data.claims) }}</template>
          </PColumn>
          <PColumn field="total_benefit" header="Benefit">
            <template #body="{ data }">{{ formatCurrency(data.total_benefit) }}</template>
          </PColumn>
          <PColumn header="Actions">
            <template #body="{ data }">
              <PButton icon="pi pi-pencil" text rounded aria-label="Edit Senior/PWD settings" :disabled="!canManageSeniorPwd" @click="openSettings(data)" />
            </template>
          </PColumn>
        </PDataTable>
      </section>

      <section class="panel">
        <div class="table-toolbar product-toolbar">
          <div>
            <p class="eyebrow">Product eligibility</p>
            <h2>Discount classification by item</h2>
          </div>
          <span class="search-field">
            <i class="pi pi-search" />
            <PInputText v-model.trim="productSearch" placeholder="Search product, SKU, barcode, category" />
          </span>
        </div>

        <PDataTable
          :value="filteredProducts"
          data-key="id"
          responsive-layout="stack"
          breakpoint="900px"
          size="small"
          striped-rows
          paginator
          :rows="10"
        >
          <PColumn field="name" header="Product">
            <template #body="{ data }">
              <div class="branch-cell">
                <strong>{{ data.name }}</strong>
                <small>{{ data.sku }} - {{ data.barcode || 'No barcode' }}</small>
              </div>
            </template>
          </PColumn>
          <PColumn field="category_name" header="Category">
            <template #body="{ data }">{{ data.category_name || data.category || 'General' }}</template>
          </PColumn>
          <PColumn field="selling_price" header="Price">
            <template #body="{ data }">{{ formatCurrency(data.selling_price) }}</template>
          </PColumn>
          <PColumn field="tax_type" header="Tax">
            <template #body="{ data }">
              <PTag :value="taxTypeLabel(data.tax_type)" severity="info" />
              <small class="muted-block">{{ formatRate(data.vat_rate) }}</small>
            </template>
          </PColumn>
          <PColumn field="senior_pwd_discount_category" header="Senior/PWD">
            <template #body="{ data }">
              <PTag
                :value="eligibilityLabel(data.senior_pwd_discount_category)"
                :severity="eligibilitySeverity(data.senior_pwd_discount_category)"
              />
            </template>
          </PColumn>
          <PColumn header="Actions">
            <template #body="{ data }">
              <PButton icon="pi pi-pencil" text rounded aria-label="Edit product eligibility" :disabled="!canManageSeniorPwd" @click="openEligibility(data)" />
            </template>
          </PColumn>
        </PDataTable>
      </section>

      <section class="panel">
        <div class="panel__header">
          <div>
            <p class="eyebrow">Saved claims</p>
            <h2>Senior/PWD invoice records</h2>
          </div>
          <span class="panel__caption">Total benefit {{ formatCurrency(seniorPwdData.summary.total_discount_amount) }}</span>
        </div>

        <PDataTable
          :value="seniorPwdData.claims"
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
                <small>{{ formatDate(data.business_date) }} - {{ data.branch_name }}</small>
              </div>
            </template>
          </PColumn>
          <PColumn field="beneficiary_name" header="Beneficiary">
            <template #body="{ data }">
              <div class="branch-cell">
                <strong>{{ data.beneficiary_name }}</strong>
                <small>{{ data.beneficiary_id_type }} {{ data.beneficiary_id_number }}</small>
              </div>
            </template>
          </PColumn>
          <PColumn field="customer_type" header="Type">
            <template #body="{ data }">
              <PTag :value="customerTypeLabel(data.customer_type)" :severity="data.customer_type === 'senior' ? 'success' : 'info'" />
            </template>
          </PColumn>
          <PColumn field="regular_discount_amount" header="20%">
            <template #body="{ data }">{{ formatCurrency(data.regular_discount_amount) }}</template>
          </PColumn>
          <PColumn field="special_discount_amount" header="5%">
            <template #body="{ data }">{{ formatCurrency(data.special_discount_amount) }}</template>
          </PColumn>
          <PColumn field="vat_exempt_amount" header="VAT exempt">
            <template #body="{ data }">{{ formatCurrency(data.vat_exempt_amount) }}</template>
          </PColumn>
          <PColumn field="total_discount_amount" header="Benefit">
            <template #body="{ data }">{{ formatCurrency(data.total_discount_amount) }}</template>
          </PColumn>
        </PDataTable>
      </section>
    </template>

    <PDialog v-model:visible="settingsVisible" modal header="Branch Senior/PWD settings" class="branch-dialog" :style="{ width: 'min(720px, 96vw)' }">
      <form class="branch-form" @submit.prevent="saveSettings">
        <PMessage v-if="formError" severity="error" :closable="false" class="dialog-message">{{ formError }}</PMessage>

        <div class="form-grid">
          <label>
            Standard discount
            <PInputNumber v-model="settingsForm.standard_discount_rate" suffix="%" :min="0" :max="100" :min-fraction-digits="2" fluid />
          </label>
          <label>
            Basic necessity discount
            <PInputNumber v-model="settingsForm.basic_necessity_rate" suffix="%" :min="0" :max="100" :min-fraction-digits="2" fluid />
          </label>
        </div>

        <div class="switch-row">
          <label>
            <PCheckbox v-model="settingsForm.require_id_capture" binary />
            Require OSCA/PWD ID capture
          </label>
          <label>
            <PCheckbox v-model="settingsForm.require_booklet_for_basic" binary />
            Require booklet for basic goods
          </label>
          <label>
            <PCheckbox v-model="settingsForm.is_active" binary />
            Active for this branch
          </label>
        </div>

        <label>
          Notes
          <PTextarea v-model.trim="settingsForm.notes" rows="3" auto-resize fluid />
        </label>

        <div class="dialog-actions">
          <PButton type="button" label="Cancel" severity="secondary" outlined @click="settingsVisible = false" />
          <PButton type="submit" icon="pi pi-save" label="Save settings" :loading="saving" />
        </div>
      </form>
    </PDialog>

    <PDialog v-model:visible="eligibilityVisible" modal header="Product Senior/PWD eligibility" class="branch-dialog" :style="{ width: 'min(620px, 96vw)' }">
      <form class="branch-form" @submit.prevent="saveEligibility">
        <PMessage v-if="formError" severity="error" :closable="false" class="dialog-message">{{ formError }}</PMessage>

        <div class="copy-panel">
          <div>
            <h2>{{ eligibilityProduct?.name }}</h2>
            <p>{{ eligibilityProduct?.sku }} - {{ eligibilityProduct?.barcode || 'No barcode' }}</p>
          </div>
          <PTag
            :value="eligibilityLabel(eligibilityForm.category)"
            :severity="eligibilitySeverity(eligibilityForm.category)"
          />
        </div>

        <label>
          Eligibility
          <PSelect v-model="eligibilityForm.category" :options="eligibilityOptions" option-label="label" option-value="value" fluid />
        </label>

        <div class="dialog-actions">
          <PButton type="button" label="Cancel" severity="secondary" outlined @click="eligibilityVisible = false" />
          <PButton type="submit" icon="pi pi-save" label="Save eligibility" :loading="saving" />
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
import { fetchSeniorPwdManagement, saveProductEligibility, saveSeniorPwdSettings } from '../services/seniorPwdService'
import { useAuthStore } from '../stores/authStore'

const auth = useAuthStore()
const loading = ref(false)
const saving = ref(false)
const error = ref('')
const successMessage = ref('')
const formError = ref('')
const seniorPwdData = ref(null)
const settingsSearch = ref('')
const productSearch = ref('')
const settingsVisible = ref(false)
const eligibilityVisible = ref(false)
const editingBranchId = ref(null)
const eligibilityProduct = ref(null)

const filters = reactive({
  from: new Date(`${addDaysISO(-29)}T00:00:00`),
  to: new Date(`${todayISO()}T00:00:00`),
  branchId: null,
})

const settingsForm = reactive(createSettingsForm())
const eligibilityForm = reactive({
  category: 'regular_20',
})

const eligibilityOptions = [
  { label: '20% discount + VAT exemption', value: 'regular_20' },
  { label: '5% basic necessities / prime goods', value: 'basic_necessity_5' },
  { label: 'Not eligible', value: 'not_eligible' },
]

const taxTypeOptions = [
  { label: 'VATable', value: 'vatable' },
  { label: 'VAT-exempt', value: 'vat_exempt' },
  { label: 'Zero-rated', value: 'zero_rated' },
  { label: 'Non-VAT', value: 'non_vat' },
]

const canManageSeniorPwd = computed(() => auth.isAdmin.value)

const branchOptions = computed(() => [
  { id: null, name: 'All branches' },
  ...(seniorPwdData.value?.branches || []),
])

const filteredBranchSettings = computed(() => {
  const query = settingsSearch.value.toLowerCase()
  const rows = seniorPwdData.value?.branch_settings || []
  if (!query) return rows

  return rows.filter((row) =>
    [row.branch_code, row.branch_name, row.notes]
      .filter(Boolean)
      .some((value) => String(value).toLowerCase().includes(query)),
  )
})

const filteredProducts = computed(() => {
  const query = productSearch.value.toLowerCase()
  const rows = seniorPwdData.value?.products || []
  if (!query) return rows

  return rows.filter((product) =>
    [
      product.name,
      product.sku,
      product.barcode,
      product.category,
      product.category_name,
      product.brand_name,
      eligibilityLabel(product.senior_pwd_discount_category),
    ]
      .filter(Boolean)
      .some((value) => String(value).toLowerCase().includes(query)),
  )
})

const periodLabel = computed(() => {
  const from = seniorPwdData.value?.period?.from || toISODate(filters.from)
  const to = seniorPwdData.value?.period?.to || toISODate(filters.to)

  return `${formatDate(from)} to ${formatDate(to)}`
})

function createSettingsForm() {
  return {
    standard_discount_rate: 20,
    basic_necessity_rate: 5,
    require_id_capture: true,
    require_booklet_for_basic: true,
    is_active: true,
    notes: '',
  }
}

function resetReactive(target, source) {
  Object.assign(target, source)
}

function formatRate(value) {
  return `${formatNumber(Number(value || 0).toFixed(2))}%`
}

function eligibilityLabel(value) {
  return eligibilityOptions.find((option) => option.value === value)?.label || '20% discount + VAT exemption'
}

function eligibilitySeverity(value) {
  if (value === 'basic_necessity_5') return 'warn'
  if (value === 'not_eligible') return 'secondary'

  return 'success'
}

function taxTypeLabel(value) {
  return taxTypeOptions.find((option) => option.value === value)?.label || value || '-'
}

function customerTypeLabel(value) {
  if (value === 'senior') return 'Senior Citizen'
  if (value === 'pwd') return 'PWD'

  return value || '-'
}

async function loadSeniorPwd(clearMessages = true) {
  loading.value = true
  if (clearMessages) {
    error.value = ''
    successMessage.value = ''
  }

  try {
    seniorPwdData.value = await fetchSeniorPwdManagement({
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

function openSettings(branch) {
  formError.value = ''
  editingBranchId.value = branch.branch_id
  resetReactive(settingsForm, {
    ...createSettingsForm(),
    ...branch,
    standard_discount_rate: Number(branch.standard_discount_rate || 20),
    basic_necessity_rate: Number(branch.basic_necessity_rate || 5),
    require_id_capture: branch.require_id_capture ?? true,
    require_booklet_for_basic: branch.require_booklet_for_basic ?? true,
    is_active: branch.is_active ?? true,
  })
  settingsVisible.value = true
}

function openEligibility(product) {
  formError.value = ''
  eligibilityProduct.value = product
  eligibilityForm.category = product.senior_pwd_discount_category || 'regular_20'
  eligibilityVisible.value = true
}

async function saveSettings() {
  if (!editingBranchId.value) {
    formError.value = 'Branch is required.'
    return
  }

  saving.value = true
  formError.value = ''
  error.value = ''

  try {
    await saveSeniorPwdSettings(editingBranchId.value, { ...settingsForm })
    settingsVisible.value = false
    successMessage.value = 'Senior/PWD branch settings saved.'
    await loadSeniorPwd(false)
  } catch (saveError) {
    formError.value = saveError.message
  } finally {
    saving.value = false
  }
}

async function saveEligibility() {
  if (!eligibilityProduct.value?.id) {
    formError.value = 'Product is required.'
    return
  }

  saving.value = true
  formError.value = ''
  error.value = ''

  try {
    await saveProductEligibility(eligibilityProduct.value.id, eligibilityForm.category)
    eligibilityVisible.value = false
    successMessage.value = 'Product Senior/PWD eligibility saved.'
    await loadSeniorPwd(false)
  } catch (saveError) {
    formError.value = saveError.message
  } finally {
    saving.value = false
  }
}

onMounted(loadSeniorPwd)
</script>
