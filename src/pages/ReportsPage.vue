<template>
  <section class="page-stack">
    <section class="page-hero">
      <div>
        <p class="eyebrow">Module 19</p>
        <h2>Reports for sales, inventory, VAT, Senior/PWD, Z-reading, and profit.</h2>
        <p>
          Review only periods with actual records, compare branch and cashier results,
          track low stock, export report rows, and validate compliance totals.
        </p>
      </div>

      <form class="filter-panel" @submit.prevent="loadReports">
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
          Report
          <PSelect
            v-model="filters.reportKey"
            :options="reportOptions"
            option-label="label"
            option-value="value"
            fluid
          />
        </label>
        <label>
          Search
          <PInputText v-model.trim="filters.search" placeholder="Invoice, SKU, cashier, branch" fluid />
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

    <section v-if="loading && !reportsData" class="stats-grid">
      <PSkeleton v-for="item in 8" :key="item" height="8rem" border-radius="8px" />
    </section>

    <template v-else-if="reportsData">
      <section class="report-mode-bar">
        <PButton
          v-for="option in reportOptions"
          :key="option.value"
          type="button"
          :icon="option.icon"
          :label="option.label"
          :outlined="filters.reportKey !== option.value"
          @click="selectReport(option.value)"
        />
      </section>

      <section class="stats-grid">
        <MetricCard label="Net sales" :value="formatCurrency(reportsData.summary.net_sales)" :caption="periodLabel" icon="pi pi-chart-line" />
        <MetricCard label="Orders" :value="formatNumber(reportsData.summary.orders)" icon="pi pi-receipt" tone="blue" />
        <MetricCard label="Gross profit" :value="formatCurrency(reportsData.summary.gross_profit)" icon="pi pi-sparkles" :tone="reportsData.summary.gross_profit >= 0 ? 'green' : 'red'" />
        <MetricCard label="Net profit" :value="formatCurrency(reportsData.summary.net_profit)" icon="pi pi-trophy" :tone="reportsData.summary.net_profit >= 0 ? 'green' : 'red'" />
        <MetricCard label="VAT" :value="formatCurrency(reportsData.summary.vat)" icon="pi pi-percentage" tone="gold" />
        <MetricCard label="Inventory value" :value="formatCurrency(reportsData.summary.inventory_value)" icon="pi pi-warehouse" tone="purple" />
        <MetricCard label="Low stock" :value="formatNumber(reportsData.summary.low_stock_count)" icon="pi pi-exclamation-triangle" :tone="reportsData.summary.low_stock_count ? 'red' : 'green'" />
        <MetricCard label="Senior/PWD discount" :value="formatCurrency(reportsData.summary.senior_pwd_discount)" icon="pi pi-id-card" tone="blue" />
      </section>

      <section v-if="showSection('overview', 'sales', 'profit')" class="analytics-grid">
        <BarChart
          title="Daily sales"
          eyebrow="Sales report"
          :rows="reportsData.daily_sales"
          key-field="business_date"
          label-field="label"
          value-field="net_sales"
          caption="Only dates with completed sales"
        />
        <BarChart
          title="Branch sales"
          eyebrow="Branch report"
          :rows="reportsData.branch_sales"
          key-field="branch_id"
          label-field="branch_name"
          value-field="net_sales"
          caption="Completed sales by branch"
        />
      </section>

      <section v-if="showSection('overview', 'sales', 'profit')" class="analytics-grid">
        <BarChart
          title="Cashier performance"
          eyebrow="Cashier report"
          :rows="reportsData.cashier_sales"
          key-field="cashier_key"
          label-field="cashier_name"
          value-field="net_sales"
          caption="Net sales by cashier"
        />
        <BarChart
          title="Profit by branch"
          eyebrow="Profit report"
          :rows="reportsData.profit_report"
          key-field="branch_id"
          label-field="branch_name"
          value-field="net_profit"
          caption="Sales less FEFO COGS and expenses"
        />
      </section>

      <section v-if="showSection('overview', 'sales')" class="panel">
        <div class="table-toolbar product-toolbar">
          <div>
            <p class="eyebrow">Daily sales</p>
            <h2>Dates with actual completed sales</h2>
          </div>
          <span class="panel__caption">{{ formatCurrency(reportsData.summary.net_sales) }}</span>
        </div>

        <PDataTable
          :value="reportsData.daily_sales"
          data-key="business_date"
          responsive-layout="stack"
          breakpoint="860px"
          size="small"
          striped-rows
          paginator
          :rows="8"
        >
          <PColumn field="business_date" header="Date">
            <template #body="{ data }">{{ formatDate(data.business_date) }}</template>
          </PColumn>
          <PColumn field="orders" header="Orders">
            <template #body="{ data }">{{ formatNumber(data.orders) }}</template>
          </PColumn>
          <PColumn field="net_sales" header="Net sales">
            <template #body="{ data }"><strong>{{ formatCurrency(data.net_sales) }}</strong></template>
          </PColumn>
          <PColumn field="discounts" header="Discounts">
            <template #body="{ data }">{{ formatCurrency(data.discounts) }}</template>
          </PColumn>
          <PColumn field="vat" header="VAT">
            <template #body="{ data }">{{ formatCurrency(data.vat) }}</template>
          </PColumn>
          <PColumn field="returns" header="Returns">
            <template #body="{ data }">{{ formatCurrency(data.returns) }}</template>
          </PColumn>
        </PDataTable>
      </section>

      <section v-if="showSection('overview', 'sales')" class="analytics-grid">
        <section class="panel">
          <div class="panel__header">
            <div>
              <p class="eyebrow">Branch sales</p>
              <h2>Branch performance summary</h2>
            </div>
          </div>

          <PDataTable :value="reportsData.branch_sales" data-key="branch_id" responsive-layout="stack" breakpoint="820px" size="small" striped-rows paginator :rows="8">
            <PColumn field="branch_name" header="Branch">
              <template #body="{ data }">
                <div class="branch-cell">
                  <strong>{{ data.branch_name }}</strong>
                  <small>{{ data.branch_code }}</small>
                </div>
              </template>
            </PColumn>
            <PColumn field="orders" header="Orders">
              <template #body="{ data }">{{ formatNumber(data.orders) }}</template>
            </PColumn>
            <PColumn field="net_sales" header="Net sales">
              <template #body="{ data }"><strong>{{ formatCurrency(data.net_sales) }}</strong></template>
            </PColumn>
            <PColumn field="average_order" header="Average">
              <template #body="{ data }">{{ formatCurrency(data.average_order) }}</template>
            </PColumn>
          </PDataTable>
        </section>

        <section class="panel">
          <div class="panel__header">
            <div>
              <p class="eyebrow">Cashier sales</p>
              <h2>Cashier performance summary</h2>
            </div>
          </div>

          <PDataTable :value="reportsData.cashier_sales" responsive-layout="stack" breakpoint="820px" size="small" striped-rows paginator :rows="8">
            <PColumn field="cashier_name" header="Cashier">
              <template #body="{ data }">
                <div class="branch-cell">
                  <strong>{{ data.cashier_name }}</strong>
                  <small>{{ data.branch_name }}</small>
                </div>
              </template>
            </PColumn>
            <PColumn field="orders" header="Orders">
              <template #body="{ data }">{{ formatNumber(data.orders) }}</template>
            </PColumn>
            <PColumn field="net_sales" header="Net sales">
              <template #body="{ data }"><strong>{{ formatCurrency(data.net_sales) }}</strong></template>
            </PColumn>
            <PColumn field="average_order" header="Average">
              <template #body="{ data }">{{ formatCurrency(data.average_order) }}</template>
            </PColumn>
          </PDataTable>
        </section>
      </section>

      <section v-if="showSection('overview', 'sales')" class="panel">
        <div class="table-toolbar product-toolbar">
          <div>
            <p class="eyebrow">Sales detail</p>
            <h2>Invoices, receipts, payment summary, and FEFO cost</h2>
          </div>
          <span class="panel__caption">Latest 300 rows</span>
        </div>

        <PDataTable
          :value="reportsData.sales_detail"
          data-key="id"
          responsive-layout="stack"
          breakpoint="980px"
          size="small"
          striped-rows
          paginator
          :rows="10"
        >
          <PColumn field="invoice_number" header="Invoice">
            <template #body="{ data }">
              <div class="branch-cell">
                <strong>{{ data.invoice_number || data.order_number }}</strong>
                <small>{{ formatDate(data.business_date) }} - {{ data.cashier_name }}</small>
              </div>
            </template>
          </PColumn>
          <PColumn field="branch_name" header="Branch">
            <template #body="{ data }">{{ data.branch_code }} - {{ data.branch_name }}</template>
          </PColumn>
          <PColumn field="payment_method_summary" header="Payment">
            <template #body="{ data }">{{ data.payment_method_summary || data.payment_status }}</template>
          </PColumn>
          <PColumn field="quantity" header="Qty">
            <template #body="{ data }">{{ formatNumber(data.quantity) }}</template>
          </PColumn>
          <PColumn field="net_sales" header="Net sales">
            <template #body="{ data }">{{ formatCurrency(data.net_sales) }}</template>
          </PColumn>
          <PColumn field="cogs_amount" header="COGS">
            <template #body="{ data }">{{ formatCurrency(data.cogs_amount) }}</template>
          </PColumn>
          <PColumn field="gross_profit" header="Profit">
            <template #body="{ data }">
              <strong :class="{ 'text-danger': data.gross_profit < 0 }">{{ formatCurrency(data.gross_profit) }}</strong>
            </template>
          </PColumn>
        </PDataTable>
      </section>

      <section v-if="showSection('overview', 'sales')" class="analytics-grid">
        <section class="panel">
          <div class="panel__header">
            <div>
              <p class="eyebrow">Top products</p>
              <h2>Best-selling products</h2>
            </div>
          </div>

          <PDataTable :value="reportsData.top_products" responsive-layout="stack" breakpoint="820px" size="small" striped-rows paginator :rows="8">
            <PColumn field="product_name" header="Product">
              <template #body="{ data }">
                <div class="branch-cell">
                  <strong>{{ data.product_name }}</strong>
                  <small>{{ data.variant_name || data.sku || 'Base item' }}</small>
                </div>
              </template>
            </PColumn>
            <PColumn field="quantity_sold" header="Sold">
              <template #body="{ data }">{{ formatNumber(data.quantity_sold) }}</template>
            </PColumn>
            <PColumn field="net_sales" header="Net sales">
              <template #body="{ data }">{{ formatCurrency(data.net_sales) }}</template>
            </PColumn>
            <PColumn field="gross_profit" header="Profit">
              <template #body="{ data }">{{ formatCurrency(data.gross_profit) }}</template>
            </PColumn>
          </PDataTable>
        </section>

        <section class="panel">
          <div class="panel__header">
            <div>
              <p class="eyebrow">Payment mix</p>
              <h2>Collections by payment method</h2>
            </div>
          </div>

          <PDataTable :value="reportsData.payment_mix" data-key="method_code" responsive-layout="stack" breakpoint="820px" size="small" striped-rows paginator :rows="8">
            <PColumn field="method_label" header="Method" />
            <PColumn field="payments" header="Payments">
              <template #body="{ data }">{{ formatNumber(data.payments) }}</template>
            </PColumn>
            <PColumn field="amount" header="Amount">
              <template #body="{ data }">{{ formatCurrency(data.amount) }}</template>
            </PColumn>
            <PColumn field="fees" header="Fees">
              <template #body="{ data }">{{ formatCurrency(data.fees) }}</template>
            </PColumn>
          </PDataTable>
        </section>
      </section>

      <section v-if="showSection('overview', 'inventory')" class="panel">
        <div class="table-toolbar product-toolbar">
          <div>
            <p class="eyebrow">Inventory report</p>
            <h2>Branch stock, value, reorder, and expiry status</h2>
          </div>
          <span class="panel__caption">{{ formatCurrency(reportsData.summary.inventory_value) }}</span>
        </div>

        <PDataTable
          :value="reportsData.inventory_report"
          data-key="id"
          responsive-layout="stack"
          breakpoint="980px"
          size="small"
          striped-rows
          paginator
          :rows="10"
        >
          <PColumn field="product_name" header="Product">
            <template #body="{ data }">
              <div class="branch-cell">
                <strong>{{ data.product_name }}</strong>
                <small>{{ data.sku }} - {{ data.category_name }}</small>
              </div>
            </template>
          </PColumn>
          <PColumn field="branch_name" header="Branch">
            <template #body="{ data }">{{ data.branch_code }} - {{ data.branch_name }}</template>
          </PColumn>
          <PColumn field="quantity_on_hand" header="On hand">
            <template #body="{ data }">{{ formatNumber(data.quantity_on_hand) }}</template>
          </PColumn>
          <PColumn field="reorder_level" header="Reorder">
            <template #body="{ data }">{{ formatNumber(data.reorder_level) }}</template>
          </PColumn>
          <PColumn field="inventory_value" header="Value">
            <template #body="{ data }">{{ formatCurrency(data.inventory_value) }}</template>
          </PColumn>
          <PColumn field="stock_status" header="Status">
            <template #body="{ data }">
              <PTag :value="stockStatusLabel(data.stock_status)" :severity="stockStatusSeverity(data.stock_status)" />
            </template>
          </PColumn>
          <PColumn field="earliest_expiry" header="Expiry">
            <template #body="{ data }">
              {{ formatDate(data.earliest_expiry) || '-' }}
              <small v-if="data.expiring_soon_batches" class="muted-block text-danger">{{ formatNumber(data.expiring_soon_batches) }} expiring batch(es)</small>
            </template>
          </PColumn>
        </PDataTable>
      </section>

      <section v-if="showSection('overview', 'inventory')" class="analytics-grid">
        <section class="panel">
          <div class="panel__header">
            <div>
              <p class="eyebrow">Stock movement</p>
              <h2>Inventory movement history</h2>
            </div>
          </div>

          <PDataTable :value="reportsData.stock_movement_report" data-key="id" responsive-layout="stack" breakpoint="900px" size="small" striped-rows paginator :rows="8">
            <PColumn field="created_at" header="Date">
              <template #body="{ data }">{{ formatDateTime(data.created_at) }}</template>
            </PColumn>
            <PColumn field="product_name" header="Product">
              <template #body="{ data }">
                <div class="branch-cell">
                  <strong>{{ data.product_name }}</strong>
                  <small>{{ data.sku }} - {{ movementLabel(data.movement_type) }}</small>
                </div>
              </template>
            </PColumn>
            <PColumn field="branch_name" header="Branch">
              <template #body="{ data }">{{ data.branch_code }} - {{ data.branch_name }}</template>
            </PColumn>
            <PColumn field="quantity_delta" header="Qty">
              <template #body="{ data }">
                <strong :class="{ 'text-danger': data.quantity_delta < 0 }">{{ formatSignedNumber(data.quantity_delta) }}</strong>
              </template>
            </PColumn>
          </PDataTable>
        </section>

        <section class="panel">
          <div class="panel__header">
            <div>
              <p class="eyebrow">Slow-moving products</p>
              <h2>Stock with little movement in the period</h2>
            </div>
          </div>

          <PDataTable :value="reportsData.slow_moving_products" responsive-layout="stack" breakpoint="860px" size="small" striped-rows paginator :rows="8">
            <PColumn field="product_name" header="Product">
              <template #body="{ data }">
                <div class="branch-cell">
                  <strong>{{ data.product_name }}</strong>
                  <small>{{ data.branch_code }} - {{ data.sku }}</small>
                </div>
              </template>
            </PColumn>
            <PColumn field="quantity_on_hand" header="On hand">
              <template #body="{ data }">{{ formatNumber(data.quantity_on_hand) }}</template>
            </PColumn>
            <PColumn field="quantity_sold" header="Sold">
              <template #body="{ data }">{{ formatNumber(data.quantity_sold) }}</template>
            </PColumn>
            <PColumn field="inventory_value" header="Value">
              <template #body="{ data }">{{ formatCurrency(data.inventory_value) }}</template>
            </PColumn>
          </PDataTable>
        </section>
      </section>

      <section v-if="showSection('overview', 'tax')" class="panel">
        <div class="table-toolbar product-toolbar">
          <div>
            <p class="eyebrow">VAT sales report</p>
            <h2>VATable, exempt, zero-rated, and non-VAT sales</h2>
          </div>
          <span class="panel__caption">{{ formatCurrency(reportsData.summary.vat) }}</span>
        </div>

        <PDataTable :value="reportsData.vat_sales_report" data-key="tax_type" responsive-layout="stack" breakpoint="820px" size="small" striped-rows>
          <PColumn field="tax_label" header="Tax type" />
          <PColumn field="line_count" header="Lines">
            <template #body="{ data }">{{ formatNumber(data.line_count) }}</template>
          </PColumn>
          <PColumn field="gross_amount" header="Gross">
            <template #body="{ data }">{{ formatCurrency(data.gross_amount) }}</template>
          </PColumn>
          <PColumn field="net_amount" header="Net">
            <template #body="{ data }"><strong>{{ formatCurrency(data.net_amount) }}</strong></template>
          </PColumn>
          <PColumn field="tax_amount" header="VAT">
            <template #body="{ data }">{{ formatCurrency(data.tax_amount) }}</template>
          </PColumn>
        </PDataTable>
      </section>

      <section v-if="showSection('overview', 'senior_pwd')" class="panel">
        <div class="table-toolbar product-toolbar">
          <div>
            <p class="eyebrow">Senior/PWD discount report</p>
            <h2>Beneficiary, ID, invoice, discount, and VAT exemption records</h2>
          </div>
          <span class="panel__caption">{{ formatCurrency(reportsData.summary.senior_pwd_discount) }}</span>
        </div>

        <PDataTable :value="reportsData.senior_pwd_report" data-key="id" responsive-layout="stack" breakpoint="980px" size="small" striped-rows paginator :rows="10">
          <PColumn field="invoice_number" header="Invoice">
            <template #body="{ data }">
              <div class="branch-cell">
                <strong>{{ data.invoice_number || data.order_number }}</strong>
                <small>{{ formatDate(data.business_date) }} - {{ discountTypeLabel(data.customer_type) }}</small>
              </div>
            </template>
          </PColumn>
          <PColumn field="beneficiary_name" header="Beneficiary">
            <template #body="{ data }">
              <div class="branch-cell">
                <strong>{{ data.beneficiary_name }}</strong>
                <small>{{ data.beneficiary_id_type || 'ID' }} {{ data.beneficiary_id_number || '-' }}</small>
              </div>
            </template>
          </PColumn>
          <PColumn field="branch_name" header="Branch">
            <template #body="{ data }">{{ data.branch_code }} - {{ data.branch_name }}</template>
          </PColumn>
          <PColumn field="total_discount_amount" header="Discount">
            <template #body="{ data }">{{ formatCurrency(data.total_discount_amount) }}</template>
          </PColumn>
          <PColumn field="vat_exempt_amount" header="VAT exempt">
            <template #body="{ data }">{{ formatCurrency(data.vat_exempt_amount) }}</template>
          </PColumn>
        </PDataTable>
      </section>

      <section v-if="showSection('overview', 'z_reading')" class="panel">
        <div class="table-toolbar product-toolbar">
          <div>
            <p class="eyebrow">Z-reading report</p>
            <h2>Posted end-of-day machine readings</h2>
          </div>
          <span class="panel__caption">{{ formatNumber(reportsData.summary.z_reading_count) }} posted</span>
        </div>

        <PDataTable :value="reportsData.z_reading_report" data-key="id" responsive-layout="stack" breakpoint="980px" size="small" striped-rows paginator :rows="10">
          <PColumn field="reading_number" header="Reading">
            <template #body="{ data }">
              <div class="branch-cell">
                <strong>{{ data.reading_number }}</strong>
                <small>{{ formatDate(data.business_date) }} - {{ data.machine_name }}</small>
              </div>
            </template>
          </PColumn>
          <PColumn field="branch_name" header="Branch">
            <template #body="{ data }">{{ data.branch_code }} - {{ data.branch_name }}</template>
          </PColumn>
          <PColumn field="completed_order_count" header="Orders">
            <template #body="{ data }">{{ formatNumber(data.completed_order_count) }}</template>
          </PColumn>
          <PColumn field="gross_sales" header="Gross">
            <template #body="{ data }">{{ formatCurrency(data.gross_sales) }}</template>
          </PColumn>
          <PColumn field="vat_total" header="VAT">
            <template #body="{ data }">{{ formatCurrency(data.vat_total) }}</template>
          </PColumn>
          <PColumn field="net_sales" header="Net">
            <template #body="{ data }"><strong>{{ formatCurrency(data.net_sales) }}</strong></template>
          </PColumn>
        </PDataTable>
      </section>

      <section v-if="showSection('overview', 'profit')" class="panel">
        <div class="table-toolbar product-toolbar">
          <div>
            <p class="eyebrow">Profit report</p>
            <h2>Branch revenue, FEFO COGS, expenses, and net profit</h2>
          </div>
          <span class="panel__caption">{{ formatCurrency(reportsData.summary.net_profit) }}</span>
        </div>

        <PDataTable :value="reportsData.profit_report" data-key="branch_id" responsive-layout="stack" breakpoint="960px" size="small" striped-rows paginator :rows="10">
          <PColumn field="branch_name" header="Branch">
            <template #body="{ data }">
              <div class="branch-cell">
                <strong>{{ data.branch_name }}</strong>
                <small>{{ data.branch_code }} - {{ formatNumber(data.orders) }} order(s)</small>
              </div>
            </template>
          </PColumn>
          <PColumn field="revenue" header="Revenue">
            <template #body="{ data }">{{ formatCurrency(data.revenue) }}</template>
          </PColumn>
          <PColumn field="cogs" header="COGS">
            <template #body="{ data }">{{ formatCurrency(data.cogs) }}</template>
          </PColumn>
          <PColumn field="gross_profit" header="Gross profit">
            <template #body="{ data }">{{ formatCurrency(data.gross_profit) }}</template>
          </PColumn>
          <PColumn field="expenses" header="Expenses">
            <template #body="{ data }">{{ formatCurrency(data.expenses) }}</template>
          </PColumn>
          <PColumn field="net_profit" header="Net profit">
            <template #body="{ data }">
              <strong :class="{ 'text-danger': data.net_profit < 0 }">{{ formatCurrency(data.net_profit) }}</strong>
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
import { fetchReportsManagement } from '../services/reportService'
import { useAuthStore } from '../stores/authStore'

const auth = useAuthStore()
const loading = ref(false)
const error = ref('')
const reportsData = ref(null)

const filters = reactive({
  from: new Date(`${addDaysISO(-29)}T00:00:00`),
  to: new Date(`${todayISO()}T00:00:00`),
  branchId: null,
  reportKey: 'overview',
  search: '',
})

const reportOptions = [
  { label: 'Overview', value: 'overview', icon: 'pi pi-chart-bar' },
  { label: 'Sales', value: 'sales', icon: 'pi pi-receipt' },
  { label: 'Inventory', value: 'inventory', icon: 'pi pi-warehouse' },
  { label: 'VAT', value: 'tax', icon: 'pi pi-percentage' },
  { label: 'Senior/PWD', value: 'senior_pwd', icon: 'pi pi-id-card' },
  { label: 'Z-reading', value: 'z_reading', icon: 'pi pi-file-check' },
  { label: 'Profit', value: 'profit', icon: 'pi pi-trophy' },
]

const isBranchLocked = computed(() => auth.state.profile?.role === 'manager')
const branchFilterOptions = computed(() => [{ id: null, name: 'All branches' }, ...(reportsData.value?.branches || [])])
const periodLabel = computed(() => {
  const from = reportsData.value?.period?.from || toISODate(filters.from)
  const to = reportsData.value?.period?.to || toISODate(filters.to)

  return `${formatDate(from)} to ${formatDate(to)}`
})
const activeExportRows = computed(() => {
  if (!reportsData.value) return []

  return {
    overview: reportsData.value.sales_detail,
    sales: reportsData.value.sales_detail,
    inventory: reportsData.value.inventory_report,
    tax: reportsData.value.vat_sales_report,
    senior_pwd: reportsData.value.senior_pwd_report,
    z_reading: reportsData.value.z_reading_report,
    profit: reportsData.value.profit_report,
  }[filters.reportKey] || []
})

function normalizeDate(value) {
  return toISODate(value) || null
}

async function loadReports() {
  loading.value = true
  error.value = ''

  try {
    reportsData.value = await fetchReportsManagement({
      from: normalizeDate(filters.from),
      to: normalizeDate(filters.to),
      branchId: filters.branchId,
      reportKey: filters.reportKey,
      search: filters.search,
    })

    if (isBranchLocked.value && !filters.branchId) {
      filters.branchId = reportsData.value.branches[0]?.id || auth.state.profile?.branch_id || null
    }
  } catch (loadError) {
    error.value = loadError.message
  } finally {
    loading.value = false
  }
}

function selectReport(reportKey) {
  filters.reportKey = reportKey
}

function showSection(...keys) {
  return keys.includes(filters.reportKey)
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

function stockStatusLabel(status) {
  return {
    ok: 'OK',
    low_stock: 'Low stock',
    out_of_stock: 'Out of stock',
  }[status] || status || '-'
}

function stockStatusSeverity(status) {
  return {
    ok: 'success',
    low_stock: 'warn',
    out_of_stock: 'danger',
  }[status] || 'secondary'
}

function movementLabel(type) {
  return {
    stock_in: 'Stock in',
    stock_out: 'Stock out',
    adjustment_plus: 'Adjustment +',
    adjustment_minus: 'Adjustment -',
    damaged: 'Damaged',
    expired: 'Expired',
  }[type] || type || '-'
}

function discountTypeLabel(type) {
  return {
    senior: 'Senior Citizen',
    pwd: 'PWD',
  }[type] || type || '-'
}

function csvValue(value) {
  if (value === null || value === undefined) return ''
  const stringValue = String(value)
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
  link.download = `pos-${filters.reportKey}-report-${normalizeDate(filters.from)}-${normalizeDate(filters.to)}.csv`
  link.click()
  URL.revokeObjectURL(url)
}

onMounted(loadReports)
</script>
