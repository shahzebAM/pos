<template>
  <section class="page-stack">
    <section class="page-hero page-hero--compact">
      <div>
        <p class="eyebrow">Module 2</p>
        <h1>Branch Management</h1>
        <p>
          Set up head office and branches with branch codes, BIR RDO details,
          pricing mode, tax profile, stock control, and assigned-user visibility.
        </p>
      </div>

      <div class="action-panel">
        <PButton icon="pi pi-plus" label="Add branch" :disabled="!auth.isAdmin.value" @click="openCreate" />
        <PButton icon="pi pi-refresh" label="Refresh" outlined :loading="loading" @click="loadBranches" />
      </div>
    </section>

    <PMessage v-if="!auth.isAdmin.value" severity="warn" :closable="false" class="setup-message">
      You can view branches with this role. Creating and editing branches is admin-only.
    </PMessage>

    <PMessage v-if="error" severity="error" :closable="false" class="setup-message">
      {{ error }}
    </PMessage>

    <PMessage v-if="successMessage" severity="success" :closable="false" class="setup-message">
      {{ successMessage }}
    </PMessage>

    <section v-if="loading && !branchData" class="stats-grid stats-grid--four">
      <PSkeleton v-for="item in 4" :key="item" height="8rem" border-radius="8px" />
    </section>

    <template v-else-if="branchData">
      <section class="stats-grid stats-grid--four">
        <MetricCard
          label="Total branches"
          :value="formatNumber(branchData.summary.total_branches)"
          caption="Head office included"
          icon="pi pi-building"
        />
        <MetricCard
          label="Active branches"
          :value="formatNumber(branchData.summary.active_branches)"
          caption="Available for operations"
          icon="pi pi-check-circle"
          tone="blue"
        />
        <MetricCard
          label="Assigned users"
          :value="formatNumber(branchData.summary.users_assigned)"
          caption="Branch-linked profiles"
          icon="pi pi-users"
          tone="purple"
        />
        <MetricCard
          label="Stock units"
          :value="formatNumber(branchData.summary.stock_units)"
          caption="Across visible branches"
          icon="pi pi-box"
          tone="gold"
        />
      </section>

      <section class="panel">
        <div class="table-toolbar">
          <div>
            <p class="eyebrow">Branch setup</p>
            <h2>Operating locations</h2>
          </div>
          <span class="search-field">
            <i class="pi pi-search" />
            <PInputText v-model.trim="search" placeholder="Search branch, code, RDO, TIN" />
          </span>
        </div>

        <PDataTable
          :value="filteredBranches"
          data-key="id"
          responsive-layout="stack"
          breakpoint="900px"
          size="small"
          striped-rows
          paginator
          :rows="8"
        >
          <PColumn field="branch_code" header="Code" />
          <PColumn field="name" header="Branch">
            <template #body="{ data }">
              <div class="branch-cell">
                <strong>{{ data.name }}</strong>
                <small>{{ data.legal_name || data.address || 'No legal/address details yet' }}</small>
              </div>
            </template>
          </PColumn>
          <PColumn field="bir_rdo_code" header="BIR RDO">
            <template #body="{ data }">
              <span>{{ data.bir_rdo_code || '-' }}</span>
              <small v-if="data.bir_rdo_name" class="muted-block">{{ data.bir_rdo_name }}</small>
            </template>
          </PColumn>
          <PColumn field="tax_profile" header="Tax">
            <template #body="{ data }">
              <PTag :value="taxProfileLabel(data.tax_profile)" severity="info" />
              <small class="muted-block">{{ data.vat_rate }}% VAT</small>
            </template>
          </PColumn>
          <PColumn field="pricing_mode" header="Pricing">
            <template #body="{ data }">{{ pricingModeLabel(data.pricing_mode) }}</template>
          </PColumn>
          <PColumn field="stock_units" header="Stock">
            <template #body="{ data }">
              {{ formatNumber(data.stock_units) }}
              <small class="muted-block">{{ formatNumber(data.stock_items) }} items</small>
            </template>
          </PColumn>
          <PColumn field="users_count" header="Users">
            <template #body="{ data }">{{ formatNumber(data.users_count) }}</template>
          </PColumn>
          <PColumn field="is_active" header="Status">
            <template #body="{ data }">
              <PTag
                :value="data.is_head_office ? 'Head office' : data.is_active ? 'Active' : 'Inactive'"
                :severity="data.is_active ? 'success' : 'danger'"
              />
            </template>
          </PColumn>
          <PColumn header="Actions">
            <template #body="{ data }">
              <div class="table-actions">
                <PButton
                  icon="pi pi-pencil"
                  text
                  rounded
                  aria-label="Edit branch"
                  :disabled="!auth.isAdmin.value"
                  @click="openEdit(data)"
                />
                <PButton
                  :icon="data.is_active ? 'pi pi-ban' : 'pi pi-check'"
                  text
                  rounded
                  :severity="data.is_active ? 'danger' : 'success'"
                  :aria-label="data.is_active ? 'Disable branch' : 'Enable branch'"
                  :disabled="!auth.isAdmin.value || data.is_head_office"
                  @click="toggleStatus(data)"
                />
                <PButton
                  icon="pi pi-trash"
                  text
                  rounded
                  severity="danger"
                  aria-label="Hard delete branch"
                  :disabled="!auth.isAdmin.value || data.is_head_office"
                  @click="hardDeleteBranchRow(data)"
                />
              </div>
            </template>
          </PColumn>
        </PDataTable>
      </section>
    </template>

    <PDialog
      v-model:visible="dialogVisible"
      modal
      :header="editingBranch ? 'Edit branch' : 'Add branch'"
      class="branch-dialog"
      :style="{ width: 'min(900px, 96vw)' }"
    >
      <form class="branch-form" @submit.prevent="saveBranch">
        <div class="form-grid">
          <label>
            Branch code
            <PInputText v-model.trim="form.branch_code" placeholder="BR-MNL" fluid />
          </label>
          <label>
            Branch name
            <PInputText v-model.trim="form.name" placeholder="Manila Branch" fluid />
          </label>
          <label>
            Legal name
            <PInputText v-model.trim="form.legal_name" placeholder="Registered business name" fluid />
          </label>
          <label>
            TIN
            <PInputText v-model.trim="form.tin" placeholder="000-000-000-000" fluid />
          </label>
          <label>
            Business style
            <PInputText v-model.trim="form.business_style" placeholder="Retail" fluid />
          </label>
          <label>
            BIR RDO code
            <PInputText v-model.trim="form.bir_rdo_code" placeholder="043" fluid />
          </label>
          <label>
            BIR RDO name
            <PInputText v-model.trim="form.bir_rdo_name" placeholder="Pasig City" fluid />
          </label>
          <label>
            Contact person
            <PInputText v-model.trim="form.contact_person" fluid />
          </label>
          <label>
            Phone
            <PInputText v-model.trim="form.contact_phone" fluid />
          </label>
          <label>
            Email
            <PInputText v-model.trim="form.contact_email" type="email" fluid />
          </label>
          <label>
            Pricing mode
            <PSelect
              v-model="form.pricing_mode"
              :options="pricingOptions"
              option-label="label"
              option-value="value"
              fluid
            />
          </label>
          <label>
            Tax profile
            <PSelect
              v-model="form.tax_profile"
              :options="taxOptions"
              option-label="label"
              option-value="value"
              fluid
            />
          </label>
          <label>
            VAT rate
            <PInputNumber v-model="form.vat_rate" suffix="%" :min="0" :max="100" :min-fraction-digits="2" fluid />
          </label>
          <label>
            Inventory control
            <PSelect
              v-model="form.inventory_control"
              :options="inventoryOptions"
              option-label="label"
              option-value="value"
              fluid
            />
          </label>
        </div>

        <label>
          Address
          <PTextarea v-model.trim="form.address" rows="3" auto-resize fluid />
        </label>

        <label>
          Receipt footer
          <PTextarea v-model.trim="form.receipt_footer" rows="2" auto-resize fluid />
        </label>

        <div class="switch-row">
          <label>
            <PCheckbox v-model="form.is_head_office" binary />
            Head office
          </label>
          <label>
            <PCheckbox v-model="form.is_active" binary />
            Active branch
          </label>
          <label>
            <PCheckbox v-model="form.allow_negative_stock" binary />
            Allow negative stock
          </label>
        </div>

        <div class="dialog-actions">
          <PButton type="button" label="Cancel" severity="secondary" outlined @click="dialogVisible = false" />
          <PButton type="submit" icon="pi pi-save" label="Save branch" :loading="saving" />
        </div>
      </form>
    </PDialog>
  </section>
</template>

<script setup>
import { computed, onMounted, reactive, ref } from 'vue'
import MetricCard from '../components/MetricCard.vue'
import { formatNumber } from '../lib/formatters'
import { createBranch, fetchBranchManagement, hardDeleteBranch, setBranchActive, updateBranch } from '../services/branchService'
import { useAuthStore } from '../stores/authStore'

const auth = useAuthStore()
const loading = ref(false)
const saving = ref(false)
const error = ref('')
const successMessage = ref('')
const branchData = ref(null)
const search = ref('')
const dialogVisible = ref(false)
const editingBranch = ref(null)

const defaultForm = {
  branch_code: '',
  name: '',
  legal_name: '',
  tin: '',
  business_style: '',
  is_head_office: false,
  bir_rdo_code: '',
  bir_rdo_name: '',
  address: '',
  contact_person: '',
  contact_phone: '',
  contact_email: '',
  pricing_mode: 'standard',
  tax_profile: 'vat_12',
  vat_rate: 12,
  inventory_control: 'branch_stock',
  allow_negative_stock: false,
  receipt_footer: '',
  is_active: true,
}

const form = reactive({ ...defaultForm })

const pricingOptions = [
  { label: 'Standard company pricing', value: 'standard' },
  { label: 'Branch override pricing', value: 'branch_override' },
]

const taxOptions = [
  { label: 'VAT 12%', value: 'vat_12' },
  { label: 'Non-VAT', value: 'non_vat' },
  { label: 'Mixed tax profile', value: 'mixed' },
]

const inventoryOptions = [
  { label: 'Branch-specific stock', value: 'branch_stock' },
  { label: 'Centralized inventory view', value: 'centralized_view' },
]

const filteredBranches = computed(() => {
  const query = search.value.toLowerCase()
  const rows = branchData.value?.branches || []

  if (!query) return rows

  return rows.filter((branch) =>
    [
      branch.branch_code,
      branch.name,
      branch.legal_name,
      branch.tin,
      branch.bir_rdo_code,
      branch.bir_rdo_name,
      branch.address,
    ]
      .filter(Boolean)
      .some((value) => value.toLowerCase().includes(query)),
  )
})

function pricingModeLabel(value) {
  return pricingOptions.find((option) => option.value === value)?.label || value
}

function taxProfileLabel(value) {
  return taxOptions.find((option) => option.value === value)?.label || value
}

function resetForm(payload = {}) {
  Object.assign(form, defaultForm, payload)
}

function payloadFromBranch(branch) {
  return {
    branch_code: branch.branch_code,
    name: branch.name,
    legal_name: branch.legal_name,
    tin: branch.tin,
    business_style: branch.business_style,
    is_head_office: branch.is_head_office,
    bir_rdo_code: branch.bir_rdo_code,
    bir_rdo_name: branch.bir_rdo_name,
    address: branch.address,
    contact_person: branch.contact_person,
    contact_phone: branch.contact_phone,
    contact_email: branch.contact_email,
    pricing_mode: branch.pricing_mode || 'standard',
    tax_profile: branch.tax_profile || 'vat_12',
    vat_rate: Number(branch.vat_rate || 12),
    inventory_control: branch.inventory_control || 'branch_stock',
    allow_negative_stock: Boolean(branch.allow_negative_stock),
    receipt_footer: branch.receipt_footer,
    is_active: Boolean(branch.is_active),
  }
}

async function loadBranches() {
  loading.value = true
  error.value = ''
  successMessage.value = ''

  try {
    branchData.value = await fetchBranchManagement()
  } catch (loadError) {
    error.value = loadError.message
  } finally {
    loading.value = false
  }
}

function openCreate() {
  editingBranch.value = null
  resetForm()
  dialogVisible.value = true
}

function openEdit(branch) {
  editingBranch.value = branch
  resetForm(payloadFromBranch(branch))
  dialogVisible.value = true
}

async function saveBranch() {
  saving.value = true
  error.value = ''
  successMessage.value = ''

  try {
    if (editingBranch.value) {
      branchData.value = await updateBranch(editingBranch.value.id, { ...form })
      successMessage.value = `${form.name} was updated.`
    } else {
      branchData.value = await createBranch({ ...form })
      successMessage.value = `${form.name} was created.`
    }

    dialogVisible.value = false
  } catch (saveError) {
    error.value = saveError.message
  } finally {
    saving.value = false
  }
}

async function toggleStatus(branch) {
  loading.value = true
  error.value = ''
  successMessage.value = ''

  try {
    branchData.value = await setBranchActive(branch.id, !branch.is_active)
    successMessage.value = `${branch.name} was ${branch.is_active ? 'disabled' : 'enabled'}.`
  } catch (statusError) {
    error.value = statusError.message
  } finally {
    loading.value = false
  }
}

async function hardDeleteBranchRow(branch) {
  const confirmed = window.confirm(
    `Permanently delete ${branch.name}? This only works for clean/test branches with no users, sales, stock, or inventory history. Branches with history should be disabled instead.`,
  )
  if (!confirmed) return

  loading.value = true
  error.value = ''
  successMessage.value = ''

  try {
    branchData.value = await hardDeleteBranch(branch.id)
    successMessage.value = `${branch.name} was permanently deleted.`
  } catch (deleteError) {
    error.value = deleteError.message
  } finally {
    loading.value = false
  }
}

onMounted(loadBranches)
</script>
