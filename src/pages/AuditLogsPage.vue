<template>
  <section class="page-stack">
    <section class="page-hero">
      <div>
        <p class="eyebrow">Module 20</p>
        <h2>Audit logs for security, voids, deletions, discounts, stock, and price changes.</h2>
        <p>
          Track who changed what, when it happened, which branch was affected,
          and where higher-risk activity needs review.
        </p>
      </div>

      <form class="filter-panel" @submit.prevent="loadAudit">
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
          Actor
          <PSelect
            v-model="filters.actorId"
            :options="actorFilterOptions"
            option-label="label"
            option-value="id"
            placeholder="All staff"
            filter
            fluid
          />
        </label>
        <label>
          Category
          <PSelect v-model="filters.category" :options="categoryOptions" option-label="label" option-value="value" fluid />
        </label>
        <label>
          Severity
          <PSelect v-model="filters.severity" :options="severityOptions" option-label="label" option-value="value" fluid />
        </label>
        <label>
          Search
          <PInputText v-model.trim="filters.search" placeholder="Action, invoice, user, reason" fluid />
        </label>
        <div class="dialog-actions">
          <PButton type="submit" icon="pi pi-refresh" label="Refresh" :loading="loading" />
          <PButton type="button" icon="pi pi-download" label="Export CSV" outlined :disabled="!activeExportRows.length" @click="downloadCsv" />
        </div>
      </form>
    </section>

    <PMessage v-if="error" severity="error" :closable="false" class="setup-message">
      {{ error }}
    </PMessage>

    <section v-if="loading && !auditData" class="stats-grid">
      <PSkeleton v-for="item in 8" :key="item" height="8rem" border-radius="8px" />
    </section>

    <template v-else-if="auditData">
      <section class="report-mode-bar">
        <PButton
          v-for="option in modeOptions"
          :key="option.value"
          type="button"
          :icon="option.icon"
          :label="option.label"
          :outlined="activeMode !== option.value"
          @click="activeMode = option.value"
        />
      </section>

      <section class="stats-grid">
        <MetricCard label="Audit events" :value="formatNumber(auditData.summary.total_events)" :caption="periodLabel" icon="pi pi-history" />
        <MetricCard label="Critical" :value="formatNumber(auditData.summary.critical_events)" icon="pi pi-shield" :tone="auditData.summary.critical_events ? 'red' : 'green'" />
        <MetricCard label="High risk" :value="formatNumber(auditData.summary.high_events)" icon="pi pi-exclamation-triangle" :tone="auditData.summary.high_events ? 'red' : 'green'" />
        <MetricCard label="Login history" :value="formatNumber(auditData.summary.login_events)" icon="pi pi-sign-in" tone="blue" />
        <MetricCard label="Voids" :value="formatNumber(auditData.summary.void_events)" icon="pi pi-ban" tone="red" />
        <MetricCard label="Deleted records" :value="formatNumber(auditData.summary.deleted_events)" icon="pi pi-trash" tone="red" />
        <MetricCard label="Price changes" :value="formatNumber(auditData.summary.price_changes)" icon="pi pi-tag" tone="gold" />
        <MetricCard label="Stock adjustments" :value="formatNumber(auditData.summary.stock_adjustments)" icon="pi pi-sliders-h" tone="purple" />
      </section>

      <section v-if="showMode('overview', 'activity')" class="analytics-grid">
        <BarChart
          title="Daily audit events"
          eyebrow="Audit activity"
          :rows="auditData.daily_events"
          key-field="event_date"
          label-field="label"
          value-field="events"
          :money="false"
          caption="Only days with records"
        />
        <BarChart
          title="Events by category"
          eyebrow="Risk areas"
          :rows="auditData.category_summary"
          key-field="category"
          label-field="label"
          value-field="events"
          :money="false"
          caption="Grouped activity logs"
        />
      </section>

      <section v-if="showMode('overview', 'activity')" class="panel">
        <div class="table-toolbar product-toolbar">
          <div>
            <p class="eyebrow">Audit trail</p>
            <h2>Latest filtered events</h2>
          </div>
          <span class="panel__caption">{{ formatNumber(auditData.summary.unique_actors) }} actor(s)</span>
        </div>

        <PDataTable
          :value="auditData.activity_logs"
          data-key="id"
          responsive-layout="stack"
          breakpoint="980px"
          size="small"
          striped-rows
          paginator
          :rows="12"
        >
          <PColumn field="created_at" header="Time">
            <template #body="{ data }">{{ formatDateTime(data.created_at) }}</template>
          </PColumn>
          <PColumn field="action" header="Action">
            <template #body="{ data }">
              <div class="branch-cell">
                <strong>{{ actionLabel(data.action) }}</strong>
                <small>{{ data.entity_type }} {{ data.entity_id || '' }}</small>
              </div>
            </template>
          </PColumn>
          <PColumn field="actor_name" header="Actor">
            <template #body="{ data }">
              <div class="branch-cell">
                <strong>{{ data.actor_name || 'System' }}</strong>
                <small>{{ data.actor_username ? `@${data.actor_username}` : data.actor_role || 'system' }}</small>
              </div>
            </template>
          </PColumn>
          <PColumn field="branch_name" header="Branch">
            <template #body="{ data }">{{ data.branch_code }} - {{ data.branch_name }}</template>
          </PColumn>
          <PColumn field="category" header="Category">
            <template #body="{ data }">
              <PTag :value="categoryLabel(data.category)" :severity="categorySeverity(data.category)" />
            </template>
          </PColumn>
          <PColumn field="severity" header="Severity">
            <template #body="{ data }">
              <PTag :value="severityLabel(data.severity)" :severity="severityTone(data.severity)" />
            </template>
          </PColumn>
          <PColumn field="metadata" header="Details">
            <template #body="{ data }">
              <small class="muted-block">{{ metadataSummary(data.metadata) }}</small>
            </template>
          </PColumn>
        </PDataTable>
      </section>

      <section v-if="showMode('overview', 'access')" class="panel">
        <div class="table-toolbar product-toolbar">
          <div>
            <p class="eyebrow">Login history</p>
            <h2>Authenticated login and logout events</h2>
          </div>
          <span class="panel__caption">{{ formatNumber(auditData.summary.login_events) }} event(s)</span>
        </div>

        <PDataTable :value="auditData.login_history" data-key="id" responsive-layout="stack" breakpoint="900px" size="small" striped-rows paginator :rows="10">
          <PColumn field="created_at" header="Time">
            <template #body="{ data }">{{ formatDateTime(data.created_at) }}</template>
          </PColumn>
          <PColumn field="actor_name" header="User">
            <template #body="{ data }">
              <div class="branch-cell">
                <strong>{{ data.actor_name || 'User' }}</strong>
                <small>{{ data.actor_username ? `@${data.actor_username}` : '-' }}</small>
              </div>
            </template>
          </PColumn>
          <PColumn field="branch_name" header="Branch">
            <template #body="{ data }">{{ data.branch_code }} - {{ data.branch_name }}</template>
          </PColumn>
          <PColumn field="action" header="Event">
            <template #body="{ data }">{{ actionLabel(data.action) }}</template>
          </PColumn>
          <PColumn field="user_agent" header="Device">
            <template #body="{ data }">
              <small class="muted-block">{{ data.user_agent || '-' }}</small>
            </template>
          </PColumn>
        </PDataTable>
      </section>

      <section v-if="showMode('overview', 'controls')" class="analytics-grid">
        <section class="panel">
          <div class="panel__header">
            <div>
              <p class="eyebrow">Voids</p>
              <h2>Voided transactions and entries</h2>
            </div>
          </div>

          <PDataTable :value="auditData.void_events" data-key="id" responsive-layout="stack" breakpoint="860px" size="small" striped-rows paginator :rows="8">
            <PColumn field="created_at" header="Time">
              <template #body="{ data }">{{ formatDateTime(data.created_at) }}</template>
            </PColumn>
            <PColumn field="action" header="Action">
              <template #body="{ data }">
                <div class="branch-cell">
                  <strong>{{ actionLabel(data.action) }}</strong>
                  <small>{{ metadataSummary(data.metadata) }}</small>
                </div>
              </template>
            </PColumn>
            <PColumn field="actor_name" header="Actor">
              <template #body="{ data }">{{ data.actor_name || 'System' }}</template>
            </PColumn>
            <PColumn field="branch_name" header="Branch">
              <template #body="{ data }">{{ data.branch_code }} - {{ data.branch_name }}</template>
            </PColumn>
          </PDataTable>
        </section>

        <section class="panel">
          <div class="panel__header">
            <div>
              <p class="eyebrow">Deleted records</p>
              <h2>Hard and soft delete events</h2>
            </div>
          </div>

          <PDataTable :value="auditData.deleted_events" data-key="id" responsive-layout="stack" breakpoint="860px" size="small" striped-rows paginator :rows="8">
            <PColumn field="created_at" header="Time">
              <template #body="{ data }">{{ formatDateTime(data.created_at) }}</template>
            </PColumn>
            <PColumn field="action" header="Action">
              <template #body="{ data }">
                <div class="branch-cell">
                  <strong>{{ actionLabel(data.action) }}</strong>
                  <small>{{ data.entity_type }} {{ data.entity_id || '' }}</small>
                </div>
              </template>
            </PColumn>
            <PColumn field="actor_name" header="Actor">
              <template #body="{ data }">{{ data.actor_name || 'System' }}</template>
            </PColumn>
            <PColumn field="severity" header="Severity">
              <template #body="{ data }">
                <PTag :value="severityLabel(data.severity)" :severity="severityTone(data.severity)" />
              </template>
            </PColumn>
          </PDataTable>
        </section>
      </section>

      <section v-if="showMode('overview', 'controls')" class="panel">
        <div class="table-toolbar product-toolbar">
          <div>
            <p class="eyebrow">Price changes</p>
            <h2>Product and variant price-change audit</h2>
          </div>
          <span class="panel__caption">{{ formatNumber(auditData.summary.price_changes) }} change(s)</span>
        </div>

        <PDataTable :value="auditData.price_change_events" data-key="id" responsive-layout="stack" breakpoint="960px" size="small" striped-rows paginator :rows="10">
          <PColumn field="created_at" header="Time">
            <template #body="{ data }">{{ formatDateTime(data.created_at) }}</template>
          </PColumn>
          <PColumn field="metadata" header="Item">
            <template #body="{ data }">
              <div class="branch-cell">
                <strong>{{ data.metadata?.name || data.metadata?.variant_name || data.metadata?.sku || data.entity_id }}</strong>
                <small>{{ data.metadata?.sku || '-' }}</small>
              </div>
            </template>
          </PColumn>
          <PColumn field="actor_name" header="Actor">
            <template #body="{ data }">{{ data.actor_name || 'System' }}</template>
          </PColumn>
          <PColumn field="metadata" header="Old price">
            <template #body="{ data }">{{ formatPriceChange(data.metadata, 'old') }}</template>
          </PColumn>
          <PColumn field="metadata" header="New price">
            <template #body="{ data }">
              <strong>{{ formatPriceChange(data.metadata, 'new') }}</strong>
            </template>
          </PColumn>
        </PDataTable>
      </section>

      <section v-if="showMode('overview', 'discounts')" class="panel">
        <div class="table-toolbar product-toolbar">
          <div>
            <p class="eyebrow">Discount audit</p>
            <h2>Sales invoices with discounts</h2>
          </div>
          <span class="panel__caption">{{ formatNumber(auditData.summary.discount_events) }} invoice(s)</span>
        </div>

        <PDataTable :value="auditData.discount_events" data-key="id" responsive-layout="stack" breakpoint="980px" size="small" striped-rows paginator :rows="10">
          <PColumn field="invoice_number" header="Invoice">
            <template #body="{ data }">
              <div class="branch-cell">
                <strong>{{ data.invoice_number || data.order_number }}</strong>
                <small>{{ formatDate(data.business_date) }} - {{ data.customer_name || 'Walk-in' }}</small>
              </div>
            </template>
          </PColumn>
          <PColumn field="actor_name" header="Cashier">
            <template #body="{ data }">{{ data.actor_name || 'Unassigned' }}</template>
          </PColumn>
          <PColumn field="branch_name" header="Branch">
            <template #body="{ data }">{{ data.branch_code }} - {{ data.branch_name }}</template>
          </PColumn>
          <PColumn field="discount_total" header="Discount">
            <template #body="{ data }"><strong>{{ formatCurrency(data.discount_total) }}</strong></template>
          </PColumn>
          <PColumn field="statutory_discount_type" header="Type">
            <template #body="{ data }">{{ discountTypeLabel(data.statutory_discount_type) }}</template>
          </PColumn>
          <PColumn field="total" header="Sale total">
            <template #body="{ data }">{{ formatCurrency(data.total) }}</template>
          </PColumn>
        </PDataTable>
      </section>

      <section v-if="showMode('overview', 'inventory')" class="panel">
        <div class="table-toolbar product-toolbar">
          <div>
            <p class="eyebrow">Stock adjustments</p>
            <h2>Inventory adjustment, damaged, and expired stock history</h2>
          </div>
          <span class="panel__caption">{{ formatNumber(auditData.summary.stock_adjustments) }} movement(s)</span>
        </div>

        <PDataTable :value="auditData.stock_adjustment_events" data-key="id" responsive-layout="stack" breakpoint="980px" size="small" striped-rows paginator :rows="10">
          <PColumn field="created_at" header="Time">
            <template #body="{ data }">{{ formatDateTime(data.created_at) }}</template>
          </PColumn>
          <PColumn field="product_name" header="Product">
            <template #body="{ data }">
              <div class="branch-cell">
                <strong>{{ data.product_name }}</strong>
                <small>{{ data.sku }} {{ data.variant_name ? `- ${data.variant_name}` : '' }}</small>
              </div>
            </template>
          </PColumn>
          <PColumn field="branch_name" header="Branch">
            <template #body="{ data }">{{ data.branch_code }} - {{ data.branch_name }}</template>
          </PColumn>
          <PColumn field="movement_type" header="Movement">
            <template #body="{ data }">{{ movementLabel(data.movement_type) }}</template>
          </PColumn>
          <PColumn field="quantity_delta" header="Qty">
            <template #body="{ data }">
              <strong :class="{ 'text-danger': data.quantity_delta < 0 }">{{ formatSignedNumber(data.quantity_delta) }}</strong>
            </template>
          </PColumn>
          <PColumn field="reason" header="Reason">
            <template #body="{ data }">
              <small class="muted-block">{{ data.reason || data.reference_number || '-' }}</small>
            </template>
          </PColumn>
        </PDataTable>
      </section>
    </template>
  </section>
</template>

<script setup>
import { computed, onMounted, reactive, ref } from 'vue'
import BarChart from '../components/BarChart.vue'
import MetricCard from '../components/MetricCard.vue'
import { addDaysISO, formatCurrency, formatDate, formatNumber, toISODate, todayISO } from '../lib/formatters'
import { fetchAuditManagement } from '../services/auditService'
import { useAuthStore } from '../stores/authStore'

const auth = useAuthStore()
const loading = ref(false)
const error = ref('')
const auditData = ref(null)
const activeMode = ref('overview')

const filters = reactive({
  from: new Date(`${addDaysISO(-29)}T00:00:00`),
  to: new Date(`${todayISO()}T00:00:00`),
  branchId: null,
  actorId: null,
  category: null,
  severity: null,
  search: '',
})

const modeOptions = [
  { label: 'Overview', value: 'overview', icon: 'pi pi-chart-bar' },
  { label: 'Activity', value: 'activity', icon: 'pi pi-history' },
  { label: 'Access', value: 'access', icon: 'pi pi-sign-in' },
  { label: 'Controls', value: 'controls', icon: 'pi pi-shield' },
  { label: 'Discounts', value: 'discounts', icon: 'pi pi-percentage' },
  { label: 'Inventory', value: 'inventory', icon: 'pi pi-warehouse' },
]

const categoryOptions = [
  { label: 'All categories', value: null },
  { label: 'Auth', value: 'auth' },
  { label: 'User', value: 'user' },
  { label: 'Branch', value: 'branch' },
  { label: 'Product', value: 'product' },
  { label: 'Price change', value: 'price_change' },
  { label: 'Stock', value: 'stock' },
  { label: 'Sale', value: 'sale' },
  { label: 'Discount', value: 'discount' },
  { label: 'Void', value: 'void' },
  { label: 'Delete', value: 'delete' },
  { label: 'Accounting', value: 'accounting' },
  { label: 'Expense', value: 'expense' },
  { label: 'Purchase', value: 'purchase' },
  { label: 'Supplier', value: 'supplier' },
  { label: 'Customer', value: 'customer' },
  { label: 'BIR', value: 'bir' },
  { label: 'System', value: 'system' },
]

const severityOptions = [
  { label: 'All severity', value: null },
  { label: 'Low', value: 'low' },
  { label: 'Medium', value: 'medium' },
  { label: 'High', value: 'high' },
  { label: 'Critical', value: 'critical' },
]

const isBranchLocked = computed(() => auth.state.profile?.role === 'manager')
const branchFilterOptions = computed(() => [{ id: null, name: 'All branches' }, ...(auditData.value?.branches || [])])
const actorFilterOptions = computed(() => [
  { id: null, label: 'All staff' },
  ...(auditData.value?.actors || []).map((actor) => ({
    ...actor,
    label: `${actor.full_name} @${actor.username || 'staff'}`,
  })),
])
const periodLabel = computed(() => {
  const from = auditData.value?.period?.from || toISODate(filters.from)
  const to = auditData.value?.period?.to || toISODate(filters.to)

  return `${formatDate(from)} to ${formatDate(to)}`
})
const activeExportRows = computed(() => {
  if (!auditData.value) return []

  return {
    overview: auditData.value.activity_logs,
    activity: auditData.value.activity_logs,
    access: auditData.value.login_history,
    controls: [...auditData.value.void_events, ...auditData.value.deleted_events, ...auditData.value.price_change_events],
    discounts: auditData.value.discount_events,
    inventory: auditData.value.stock_adjustment_events,
  }[activeMode.value] || []
})

function normalizeDate(value) {
  return toISODate(value) || null
}

async function loadAudit() {
  loading.value = true
  error.value = ''

  try {
    auditData.value = await fetchAuditManagement({
      from: normalizeDate(filters.from),
      to: normalizeDate(filters.to),
      branchId: filters.branchId,
      actorId: filters.actorId,
      category: filters.category,
      severity: filters.severity,
      search: filters.search,
    })

    if (isBranchLocked.value && !filters.branchId) {
      filters.branchId = auditData.value.branches[0]?.id || auth.state.profile?.branch_id || null
    }
  } catch (loadError) {
    error.value = loadError.message
  } finally {
    loading.value = false
  }
}

function showMode(...modes) {
  return modes.includes(activeMode.value)
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

function formatSignedNumber(value) {
  const number = Number(value || 0)
  return `${number > 0 ? '+' : ''}${formatNumber(number)}`
}

function actionLabel(action) {
  return String(action || '-')
    .replace(/\./g, ' ')
    .replace(/_/g, ' ')
    .replace(/\b\w/g, (letter) => letter.toUpperCase())
}

function categoryLabel(category) {
  return {
    auth: 'Auth',
    user: 'User',
    branch: 'Branch',
    product: 'Product',
    price_change: 'Price',
    stock: 'Stock',
    transfer: 'Transfer',
    sale: 'Sale',
    discount: 'Discount',
    void: 'Void',
    delete: 'Delete',
    accounting: 'Accounting',
    expense: 'Expense',
    purchase: 'Purchase',
    supplier: 'Supplier',
    customer: 'Customer',
    bir: 'BIR',
    system: 'System',
  }[category] || actionLabel(category)
}

function categorySeverity(category) {
  if (category === 'void' || category === 'delete') return 'danger'
  if (category === 'price_change' || category === 'stock' || category === 'discount') return 'warn'
  if (category === 'auth' || category === 'sale') return 'info'
  return 'secondary'
}

function severityLabel(severity) {
  return actionLabel(severity || 'low')
}

function severityTone(severity) {
  if (severity === 'critical' || severity === 'high') return 'danger'
  if (severity === 'medium') return 'warn'
  return 'success'
}

function metadataSummary(metadata) {
  if (!metadata || typeof metadata !== 'object') return '-'

  const values = [
    metadata.invoice_number,
    metadata.order_number,
    metadata.return_number,
    metadata.journal_number,
    metadata.reason,
    metadata.status,
    metadata.name,
    metadata.sku,
    metadata.username,
    metadata.role,
  ].filter(Boolean)

  if (values.length) return values.slice(0, 3).join(' - ')

  return Object.keys(metadata)
    .slice(0, 3)
    .map((key) => `${key}: ${metadata[key]}`)
    .join(', ') || '-'
}

function formatPriceChange(metadata, side) {
  if (!metadata) return '-'

  const cost = metadata[`${side}_cost_price`]
  const selling = metadata[`${side}_selling_price`]

  return `Cost ${formatCurrency(cost)} / Sell ${formatCurrency(selling)}`
}

function discountTypeLabel(value) {
  return {
    none: 'Standard',
    senior: 'Senior Citizen',
    pwd: 'PWD',
  }[value] || value || '-'
}

function movementLabel(type) {
  return {
    adjustment_plus: 'Adjustment +',
    adjustment_minus: 'Adjustment -',
    damaged: 'Damaged',
    expired: 'Expired',
  }[type] || type || '-'
}

function csvValue(value) {
  if (value === null || value === undefined) return ''
  const stringValue = typeof value === 'object' ? JSON.stringify(value) : String(value)
  if (!/[",\n]/.test(stringValue)) return stringValue

  return `"${stringValue.replace(/"/g, '""')}"`
}

function downloadCsv() {
  const rows = activeExportRows.value
  if (!rows.length) return

  const columns = Object.keys(rows[0])
  const csv = [
    columns.join(','),
    ...rows.map((row) => columns.map((column) => csvValue(row[column])).join(',')),
  ].join('\n')
  const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' })
  const link = document.createElement('a')
  const url = URL.createObjectURL(blob)
  link.href = url
  link.download = `pos-audit-${activeMode.value}-${normalizeDate(filters.from)}-${normalizeDate(filters.to)}.csv`
  link.click()
  URL.revokeObjectURL(url)
}

onMounted(loadAudit)
</script>
