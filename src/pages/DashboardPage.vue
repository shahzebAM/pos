<template>
  <section class="page-stack">
    <section class="page-hero">
      <div>
        <p class="eyebrow">Module 1</p>
        <h2>Sales, cashier performance, and low-stock alerts in one command center.</h2>
        <p>
          Admin and branch-level users see the right sales, cashier, and inventory alerts
          for their role.
        </p>
      </div>

      <form class="filter-panel" @submit.prevent="loadDashboard">
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
        <PButton type="submit" icon="pi pi-refresh" label="Refresh" :loading="loading" />
      </form>
    </section>

    <PMessage v-if="error" severity="error" :closable="false" class="setup-message">
      {{ error }}
    </PMessage>

    <section v-if="loading && !metrics" class="stats-grid">
      <PSkeleton v-for="item in 6" :key="item" height="9rem" border-radius="8px" />
    </section>

    <template v-else-if="metrics">
      <section class="stats-grid">
        <MetricCard
          label="Total sales"
          :value="formatCurrency(metrics.totals.sales)"
          :caption="periodLabel"
          icon="pi pi-wallet"
          tone="green"
        />
        <MetricCard
          label="Completed orders"
          :value="formatNumber(metrics.totals.orders)"
          caption="Excludes voided/refunded orders"
          icon="pi pi-shopping-cart"
          tone="blue"
        />
        <MetricCard
          label="Average order"
          :value="formatCurrency(metrics.totals.average_order)"
          caption="Basket value"
          icon="pi pi-chart-line"
          tone="gold"
        />
        <MetricCard
          label="VAT tracked"
          :value="formatCurrency(metrics.totals.vat)"
          caption="Dashboard estimate"
          icon="pi pi-percentage"
          tone="purple"
        />
        <MetricCard
          label="Discounts"
          :value="formatCurrency(metrics.totals.discounts)"
          caption="Approved sales discounts"
          icon="pi pi-ticket"
          tone="red"
        />
        <MetricCard
          label="Low stock"
          :value="formatNumber(metrics.totals.low_stock_count)"
          caption="At or below reorder level"
          icon="pi pi-exclamation-triangle"
          tone="orange"
        />
      </section>

      <section class="analytics-grid">
        <BarChart
          title="Sales by branch"
          eyebrow="Branch performance"
          :rows="metrics.sales_by_branch"
          key-field="branch_id"
          caption="Completed sales only"
        />
        <DailySalesChart :rows="metrics.daily_sales" />
      </section>

      <section class="dashboard-grid">
        <section class="panel">
          <div class="panel__header">
            <div>
              <p class="eyebrow">Cashier performance</p>
              <h2>Sales contribution</h2>
            </div>
            <span class="panel__caption">{{ metrics.cashier_performance.length }} active cashiers</span>
          </div>

          <PDataTable
            :value="metrics.cashier_performance"
            data-key="cashier_id"
            responsive-layout="stack"
            breakpoint="860px"
            size="small"
            striped-rows
          >
            <PColumn field="cashier_name" header="Cashier" />
            <PColumn field="branch_name" header="Branch" />
            <PColumn field="orders" header="Orders">
              <template #body="{ data }">{{ formatNumber(data.orders) }}</template>
            </PColumn>
            <PColumn field="sales" header="Sales">
              <template #body="{ data }">{{ formatCurrency(data.sales) }}</template>
            </PColumn>
            <PColumn field="average_order" header="Avg. order">
              <template #body="{ data }">{{ formatCurrency(data.average_order) }}</template>
            </PColumn>
          </PDataTable>
        </section>

        <section class="panel">
          <div class="panel__header">
            <div>
              <p class="eyebrow">Low stock alerts</p>
              <h2>Reorder watchlist</h2>
            </div>
            <span class="panel__caption">Top 25 alerts</span>
          </div>

          <PDataTable
            :value="metrics.low_stock_alerts"
            data-key="id"
            responsive-layout="stack"
            breakpoint="860px"
            size="small"
            striped-rows
          >
            <PColumn field="product_name" header="Product" />
            <PColumn field="branch_name" header="Branch" />
            <PColumn field="quantity_on_hand" header="On hand">
              <template #body="{ data }">{{ formatNumber(data.quantity_on_hand) }}</template>
            </PColumn>
            <PColumn field="reorder_level" header="Reorder">
              <template #body="{ data }">{{ formatNumber(data.reorder_level) }}</template>
            </PColumn>
            <PColumn field="severity" header="Status">
              <template #body="{ data }">
                <PTag :value="data.severity" :severity="severityTag(data.severity)" />
              </template>
            </PColumn>
          </PDataTable>
        </section>
      </section>
    </template>
  </section>
</template>

<script setup>
import { computed, onMounted, reactive, ref } from 'vue'
import BarChart from '../components/BarChart.vue'
import DailySalesChart from '../components/DailySalesChart.vue'
import MetricCard from '../components/MetricCard.vue'
import { addDaysISO, formatCurrency, formatDate, formatNumber, toISODate, todayISO } from '../lib/formatters'
import { fetchDashboardMetrics } from '../services/dashboardService'

const loading = ref(false)
const error = ref('')
const metrics = ref(null)

const filters = reactive({
  from: new Date(`${addDaysISO(-6)}T00:00:00`),
  to: new Date(`${todayISO()}T00:00:00`),
  branchId: null,
})

const branchOptions = computed(() => [
  { id: null, name: 'All branches' },
  ...(metrics.value?.branches || []),
])

const periodLabel = computed(() => {
  const from = toISODate(filters.from)
  const to = toISODate(filters.to)

  return `${formatDate(from)} to ${formatDate(to)}`
})

function severityTag(severity) {
  if (severity === 'critical') return 'danger'
  if (severity === 'high') return 'warn'

  return 'info'
}

async function loadDashboard() {
  loading.value = true
  error.value = ''

  try {
    metrics.value = await fetchDashboardMetrics({
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

onMounted(loadDashboard)
</script>
