<template>
  <section class="page-stack">
    <section class="page-hero">
      <div>
        <p class="eyebrow">Module 18</p>
        <h2>Accounting, journals, ledgers, receivables, payables, VAT, and profit reports.</h2>
        <p>
          Review branch profitability, cash movement, sales journals, customer balances,
          supplier payables, VAT payable, and balanced accounting adjustments.
        </p>
      </div>

      <form class="filter-panel" @submit.prevent="loadAccounting">
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
          Search
          <PInputText v-model.trim="filters.search" placeholder="Invoice, order, cashier, journal" fluid />
        </label>
        <div class="dialog-actions">
          <PButton type="submit" icon="pi pi-refresh" label="Refresh" :loading="loading" />
          <PButton type="button" icon="pi pi-book" label="Manual journal" outlined :disabled="!canManageAccounting" @click="openJournal()" />
        </div>
      </form>
    </section>

    <PMessage v-if="error" severity="error" :closable="false" class="setup-message">
      {{ error }}
    </PMessage>

    <PMessage v-if="successMessage" severity="success" :closable="false" class="setup-message">
      {{ successMessage }}
    </PMessage>

    <section v-if="loading && !accountingData" class="stats-grid">
      <PSkeleton v-for="item in 8" :key="item" height="8rem" border-radius="8px" />
    </section>

    <template v-else-if="accountingData">
      <section class="stats-grid">
        <MetricCard label="Sales revenue" :value="formatCurrency(accountingData.summary.sales_revenue)" :caption="periodLabel" icon="pi pi-chart-line" />
        <MetricCard label="COGS" :value="formatCurrency(accountingData.summary.cogs)" icon="pi pi-box" tone="gold" />
        <MetricCard label="Gross profit" :value="formatCurrency(accountingData.summary.gross_profit)" icon="pi pi-sparkles" tone="green" />
        <MetricCard label="Expenses" :value="formatCurrency(accountingData.summary.operating_expenses)" icon="pi pi-wallet" tone="red" />
        <MetricCard label="Net profit" :value="formatCurrency(accountingData.summary.net_profit)" icon="pi pi-trophy" :tone="accountingData.summary.net_profit >= 0 ? 'green' : 'red'" />
        <MetricCard label="Cash net" :value="formatCurrency(accountingData.summary.cash_net)" icon="pi pi-money-bill" tone="blue" />
        <MetricCard label="Receivable" :value="formatCurrency(accountingData.summary.accounts_receivable)" icon="pi pi-users" tone="purple" />
        <MetricCard label="VAT payable" :value="formatCurrency(accountingData.summary.vat_payable)" icon="pi pi-percentage" :tone="accountingData.summary.vat_payable >= 0 ? 'gold' : 'green'" />
      </section>

      <section class="analytics-grid">
        <BarChart
          title="Daily net profit"
          eyebrow="Profit and loss"
          :rows="accountingData.daily_summary"
          key-field="business_date"
          label-field="label"
          value-field="net_profit"
          caption="Sales less COGS and expenses"
        />
        <BarChart
          title="Branch performance"
          eyebrow="Branch comparison"
          :rows="accountingData.branch_summary"
          key-field="branch_id"
          label-field="branch_name"
          value-field="net_profit"
          caption="Net profit by branch"
        />
      </section>

      <section class="analytics-grid">
        <section class="panel">
          <div class="panel__header">
            <div>
              <p class="eyebrow">Profit and loss</p>
              <h2>Period income statement</h2>
            </div>
          </div>

          <PDataTable :value="accountingData.profit_loss" data-key="sort_order" responsive-layout="stack" breakpoint="760px" size="small" striped-rows>
            <PColumn field="line" header="Line">
              <template #body="{ data }">
                <strong>{{ data.line }}</strong>
                <small class="muted-block">{{ lineTypeLabel(data.line_type) }}</small>
              </template>
            </PColumn>
            <PColumn field="amount" header="Amount">
              <template #body="{ data }">
                <strong :class="{ 'text-danger': data.amount < 0 }">{{ formatCurrency(data.amount) }}</strong>
              </template>
            </PColumn>
          </PDataTable>
        </section>

        <section class="panel">
          <div class="panel__header">
            <div>
              <p class="eyebrow">VAT payable</p>
              <h2>Output VAT less input VAT</h2>
            </div>
          </div>

          <div class="accounting-balance-strip">
            <article>
              <span>Output VAT</span>
              <strong>{{ formatCurrency(accountingData.vat_report.output_vat) }}</strong>
            </article>
            <article>
              <span>Purchase input VAT</span>
              <strong>{{ formatCurrency(accountingData.vat_report.purchase_input_vat) }}</strong>
            </article>
            <article>
              <span>Expense input VAT</span>
              <strong>{{ formatCurrency(accountingData.vat_report.expense_input_vat) }}</strong>
            </article>
            <article>
              <span>Net VAT payable</span>
              <strong>{{ formatCurrency(accountingData.vat_report.vat_payable) }}</strong>
            </article>
          </div>
        </section>
      </section>

      <section class="panel">
        <div class="table-toolbar product-toolbar">
          <div>
            <p class="eyebrow">Sales journal</p>
            <h2>Completed invoices and FEFO cost</h2>
          </div>
          <span class="search-field">
            <i class="pi pi-search" />
            <PInputText v-model.trim="salesSearch" placeholder="Search sales journal" />
          </span>
        </div>

        <PDataTable
          :value="filteredSalesJournal"
          data-key="id"
          responsive-layout="stack"
          breakpoint="920px"
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
            <template #body="{ data }">
              {{ data.payment_method_summary || data.payment_status }}
              <small class="muted-block">{{ statusLabel(data.payment_status) }}</small>
            </template>
          </PColumn>
          <PColumn field="net_sales" header="Revenue">
            <template #body="{ data }">{{ formatCurrency(data.net_sales) }}</template>
          </PColumn>
          <PColumn field="tax_total" header="VAT">
            <template #body="{ data }">{{ formatCurrency(data.tax_total) }}</template>
          </PColumn>
          <PColumn field="cogs_amount" header="COGS">
            <template #body="{ data }">{{ formatCurrency(data.cogs_amount) }}</template>
          </PColumn>
          <PColumn field="total" header="Total">
            <template #body="{ data }">
              <strong>{{ formatCurrency(data.total) }}</strong>
            </template>
          </PColumn>
        </PDataTable>
      </section>

      <section class="analytics-grid">
        <section class="panel">
          <div class="table-toolbar product-toolbar">
            <div>
              <p class="eyebrow">Cash ledger</p>
              <h2>Collections and cash-equivalent outflows</h2>
            </div>
            <span class="search-field">
              <i class="pi pi-search" />
              <PInputText v-model.trim="cashSearch" placeholder="Search cash ledger" />
            </span>
          </div>

          <PDataTable
            :value="filteredCashLedger"
            data-key="id"
            responsive-layout="stack"
            breakpoint="860px"
            size="small"
            striped-rows
            paginator
            :rows="8"
          >
            <PColumn field="entry_date" header="Date">
              <template #body="{ data }">{{ formatDate(data.entry_date) }}</template>
            </PColumn>
            <PColumn field="reference_number" header="Reference">
              <template #body="{ data }">
                <div class="branch-cell">
                  <strong>{{ data.reference_number || '-' }}</strong>
                  <small>{{ data.description }}</small>
                </div>
              </template>
            </PColumn>
            <PColumn field="branch_name" header="Branch">
              <template #body="{ data }">{{ data.branch_code }} - {{ data.branch_name }}</template>
            </PColumn>
            <PColumn field="method" header="Method">
              <template #body="{ data }">{{ methodLabel(data.method) }}</template>
            </PColumn>
            <PColumn field="direction" header="Flow">
              <template #body="{ data }">
                <PTag :value="data.direction === 'inflow' ? 'In' : 'Out'" :severity="data.direction === 'inflow' ? 'success' : 'danger'" />
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
              <p class="eyebrow">Trial balance</p>
              <h2>Account balances from operations and journals</h2>
            </div>
          </div>

          <PDataTable
            :value="accountingData.trial_balance"
            data-key="account_id"
            responsive-layout="stack"
            breakpoint="820px"
            size="small"
            striped-rows
            paginator
            :rows="10"
          >
            <PColumn field="account_code" header="Account">
              <template #body="{ data }">
                <div class="branch-cell">
                  <strong>{{ data.account_code }} - {{ data.account_name }}</strong>
                  <small>{{ accountTypeLabel(data.account_type) }} - {{ data.normal_balance }}</small>
                </div>
              </template>
            </PColumn>
            <PColumn field="balance" header="Balance">
              <template #body="{ data }">
                <strong>{{ formatSignedBalance(data) }}</strong>
              </template>
            </PColumn>
          </PDataTable>
        </section>
      </section>

      <section class="analytics-grid">
        <section class="panel">
          <div class="panel__header">
            <div>
              <p class="eyebrow">Accounts receivable</p>
              <h2>Open customer balances</h2>
            </div>
            <span class="panel__caption">{{ formatCurrency(accountingData.summary.accounts_receivable) }}</span>
          </div>

          <PDataTable
            :value="accountingData.receivables"
            data-key="id"
            responsive-layout="stack"
            breakpoint="820px"
            size="small"
            striped-rows
            paginator
            :rows="8"
          >
            <PColumn field="full_name" header="Customer">
              <template #body="{ data }">
                <div class="branch-cell">
                  <strong>{{ data.full_name }}</strong>
                  <small>{{ data.customer_code }} - {{ data.branch_code }}</small>
                </div>
              </template>
            </PColumn>
            <PColumn field="receivable_balance" header="Receivable">
              <template #body="{ data }">{{ formatCurrency(data.receivable_balance) }}</template>
            </PColumn>
            <PColumn field="store_credit_balance" header="Store credit">
              <template #body="{ data }">{{ formatCurrency(data.store_credit_balance) }}</template>
            </PColumn>
          </PDataTable>
        </section>

        <section class="panel">
          <div class="panel__header">
            <div>
              <p class="eyebrow">Accounts payable</p>
              <h2>Open supplier invoices</h2>
            </div>
            <span class="panel__caption">{{ formatCurrency(accountingData.summary.accounts_payable) }}</span>
          </div>

          <PDataTable
            :value="accountingData.payables"
            data-key="id"
            responsive-layout="stack"
            breakpoint="820px"
            size="small"
            striped-rows
            paginator
            :rows="8"
          >
            <PColumn field="supplier_name" header="Supplier">
              <template #body="{ data }">
                <div class="branch-cell">
                  <strong>{{ data.supplier_name }}</strong>
                  <small>{{ data.supplier_code }} - {{ data.invoice_number }}</small>
                </div>
              </template>
            </PColumn>
            <PColumn field="due_date" header="Due">
              <template #body="{ data }">
                {{ formatDate(data.due_date) || '-' }}
                <small v-if="data.days_overdue > 0" class="muted-block text-danger">{{ formatNumber(data.days_overdue) }} day(s) overdue</small>
              </template>
            </PColumn>
            <PColumn field="balance_amount" header="Balance">
              <template #body="{ data }">{{ formatCurrency(data.balance_amount) }}</template>
            </PColumn>
          </PDataTable>
        </section>
      </section>

      <section class="panel">
        <div class="table-toolbar product-toolbar">
          <div>
            <p class="eyebrow">Manual journals</p>
            <h2>Balanced adjustments and closing entries</h2>
          </div>
          <PButton type="button" icon="pi pi-book" label="Manual journal" :disabled="!canManageAccounting" @click="openJournal()" />
        </div>

        <PDataTable
          :value="accountingData.manual_journals"
          data-key="id"
          responsive-layout="stack"
          breakpoint="900px"
          size="small"
          striped-rows
          paginator
          :rows="8"
        >
          <PColumn field="journal_number" header="Journal">
            <template #body="{ data }">
              <div class="branch-cell">
                <strong>{{ data.journal_number }}</strong>
                <small>{{ formatDate(data.journal_date) }} - {{ data.description }}</small>
              </div>
            </template>
          </PColumn>
          <PColumn field="branch_name" header="Branch">
            <template #body="{ data }">{{ data.branch_code }} - {{ data.branch_name }}</template>
          </PColumn>
          <PColumn field="posted_by_name" header="Posted by">
            <template #body="{ data }">{{ data.posted_by_name }}</template>
          </PColumn>
          <PColumn field="debit_total" header="Debits">
            <template #body="{ data }">{{ formatCurrency(data.debit_total) }}</template>
          </PColumn>
          <PColumn field="credit_total" header="Credits">
            <template #body="{ data }">{{ formatCurrency(data.credit_total) }}</template>
          </PColumn>
          <PColumn field="status" header="Status">
            <template #body="{ data }">
              <PTag :value="statusLabel(data.status)" :severity="data.status === 'posted' ? 'success' : 'danger'" />
            </template>
          </PColumn>
          <PColumn header="Actions">
            <template #body="{ data }">
              <PButton icon="pi pi-list" text rounded aria-label="View lines" @click="openJournalLines(data)" />
              <PButton icon="pi pi-ban" text rounded severity="danger" aria-label="Void journal" :disabled="!canCloseAccounting || data.status !== 'posted'" @click="openVoidDialog(data)" />
            </template>
          </PColumn>
        </PDataTable>
      </section>
    </template>

    <PDialog
      v-model:visible="journalDialogVisible"
      modal
      header="Post manual journal"
      class="branch-dialog"
      :style="{ width: 'min(1080px, 96vw)' }"
    >
      <form class="dialog-form" @submit.prevent="submitJournal">
        <PMessage v-if="formError" severity="error" :closable="false" class="dialog-message">
          {{ formError }}
        </PMessage>

        <div class="form-grid">
          <label>
            Branch
            <PSelect
              v-model="journalForm.branch_id"
              :options="branchOptions"
              option-label="name"
              option-value="id"
              placeholder="Select branch"
              :disabled="isBranchLocked"
              fluid
            />
          </label>
          <label>
            Journal date
            <PDatePicker v-model="journalForm.journal_date" date-format="yy-mm-dd" show-icon fluid />
          </label>
          <label>
            Entry type
            <PSelect v-model="journalForm.source_type" :options="journalTypeOptions" option-label="label" option-value="value" fluid />
          </label>
        </div>

        <label>
          Description
          <PTextarea v-model.trim="journalForm.description" rows="3" placeholder="Reason for the accounting entry" fluid />
        </label>

        <div class="journal-lines">
          <div class="table-toolbar product-toolbar">
            <div>
              <p class="eyebrow">Journal lines</p>
              <h2>Debits must equal credits</h2>
            </div>
            <PButton type="button" icon="pi pi-plus" label="Add line" outlined @click="addJournalLine" />
          </div>

          <article v-for="(line, index) in journalForm.lines" :key="line.key" class="journal-line-grid">
            <label>
              Account
              <PSelect
                v-model="line.account_id"
                :options="accountOptions"
                option-label="label"
                option-value="id"
                placeholder="Select account"
                filter
                fluid
              />
            </label>
            <label>
              Line note
              <PInputText v-model.trim="line.description" placeholder="Optional line description" fluid />
            </label>
            <label>
              Debit
              <PInputNumber v-model="line.debit" mode="currency" :currency="currencyCode" locale="en-PH" :min="0" fluid @update:model-value="line.credit = Number($event || 0) > 0 ? 0 : line.credit" />
            </label>
            <label>
              Credit
              <PInputNumber v-model="line.credit" mode="currency" :currency="currencyCode" locale="en-PH" :min="0" fluid @update:model-value="line.debit = Number($event || 0) > 0 ? 0 : line.debit" />
            </label>
            <PButton type="button" icon="pi pi-trash" text rounded severity="danger" :aria-label="`Remove line ${index + 1}`" :disabled="journalForm.lines.length <= 2" @click="removeJournalLine(index)" />
          </article>
        </div>

        <div class="accounting-balance-strip">
          <article>
            <span>Total debits</span>
            <strong>{{ formatCurrency(journalDebitTotal) }}</strong>
          </article>
          <article>
            <span>Total credits</span>
            <strong>{{ formatCurrency(journalCreditTotal) }}</strong>
          </article>
          <article>
            <span>Difference</span>
            <strong :class="{ 'text-danger': journalDifference !== 0 }">{{ formatCurrency(journalDifference) }}</strong>
          </article>
        </div>

        <div class="dialog-actions">
          <PButton type="button" label="Cancel" severity="secondary" outlined @click="journalDialogVisible = false" />
          <PButton type="submit" icon="pi pi-save" label="Post journal" :loading="saving" :disabled="journalDifference !== 0" />
        </div>
      </form>
    </PDialog>

    <PDialog
      v-model:visible="lineDialogVisible"
      modal
      :header="selectedJournal ? selectedJournal.journal_number : 'Journal lines'"
      class="branch-dialog"
      :style="{ width: 'min(860px, 96vw)' }"
    >
      <PDataTable :value="selectedJournalLines" data-key="id" responsive-layout="stack" breakpoint="760px" size="small" striped-rows>
        <PColumn field="account_code" header="Account">
          <template #body="{ data }">
            <div class="branch-cell">
              <strong>{{ data.account_code }} - {{ data.account_name }}</strong>
              <small>{{ data.description || data.account_type }}</small>
            </div>
          </template>
        </PColumn>
        <PColumn field="debit" header="Debit">
          <template #body="{ data }">{{ data.debit > 0 ? formatCurrency(data.debit) : '-' }}</template>
        </PColumn>
        <PColumn field="credit" header="Credit">
          <template #body="{ data }">{{ data.credit > 0 ? formatCurrency(data.credit) : '-' }}</template>
        </PColumn>
      </PDataTable>
    </PDialog>

    <PDialog
      v-model:visible="voidDialogVisible"
      modal
      header="Void journal"
      class="branch-dialog"
      :style="{ width: 'min(560px, 94vw)' }"
    >
      <form class="dialog-form" @submit.prevent="submitVoidJournal">
        <PMessage v-if="formError" severity="error" :closable="false" class="dialog-message">
          {{ formError }}
        </PMessage>
        <PMessage severity="warn" :closable="false" class="dialog-message">
          Voiding keeps the journal for audit history and removes it from active balances.
        </PMessage>
        <label>
          Reason
          <PTextarea v-model.trim="voidReason" rows="4" placeholder="Enter the void reason" fluid />
        </label>
        <div class="dialog-actions">
          <PButton type="button" label="Cancel" severity="secondary" outlined @click="voidDialogVisible = false" />
          <PButton type="submit" icon="pi pi-ban" label="Void journal" severity="danger" :loading="saving" />
        </div>
      </form>
    </PDialog>
  </section>
</template>

<script setup>
import { computed, onMounted, reactive, ref } from 'vue'
import BarChart from '../components/BarChart.vue'
import MetricCard from '../components/MetricCard.vue'
import { addDaysISO, currencyCode, formatCurrency, formatDate, formatNumber, toISODate, todayISO } from '../lib/formatters'
import {
  fetchAccountingManagement,
  postAccountingJournal,
  voidAccountingJournal,
} from '../services/accountingService'
import { useAuthStore } from '../stores/authStore'

const auth = useAuthStore()
const loading = ref(false)
const saving = ref(false)
const error = ref('')
const successMessage = ref('')
const formError = ref('')
const accountingData = ref(null)
const salesSearch = ref('')
const cashSearch = ref('')
const journalDialogVisible = ref(false)
const lineDialogVisible = ref(false)
const voidDialogVisible = ref(false)
const selectedJournal = ref(null)
const voidReason = ref('')

const filters = reactive({
  from: new Date(`${addDaysISO(-89)}T00:00:00`),
  to: new Date(`${todayISO()}T00:00:00`),
  branchId: null,
  search: '',
})

const journalForm = reactive(createJournalForm())

const journalTypeOptions = [
  { label: 'Manual', value: 'manual' },
  { label: 'Adjustment', value: 'adjustment' },
  { label: 'Closing', value: 'closing' },
]

const isBranchLocked = computed(() => auth.state.profile?.role === 'manager')
const canManageAccounting = computed(() => accountingData.value?.can_manage_accounting && ['admin', 'manager'].includes(auth.state.profile?.role))
const canCloseAccounting = computed(() => accountingData.value?.can_close_accounting && ['admin', 'manager'].includes(auth.state.profile?.role))
const branchFilterOptions = computed(() => [{ id: null, name: 'All branches' }, ...(accountingData.value?.branches || [])])
const branchOptions = computed(() => accountingData.value?.branches || [])
const accountOptions = computed(() =>
  (accountingData.value?.accounts || []).map((account) => ({
    ...account,
    label: `${account.account_code} - ${account.name}`,
  })),
)
const periodLabel = computed(() => {
  const from = accountingData.value?.period?.from || toISODate(filters.from)
  const to = accountingData.value?.period?.to || toISODate(filters.to)

  return `${formatDate(from)} to ${formatDate(to)}`
})
const filteredSalesJournal = computed(() => {
  const query = salesSearch.value.toLowerCase()
  const rows = accountingData.value?.sales_journal || []
  if (!query) return rows

  return rows.filter((row) =>
    [row.invoice_number, row.order_number, row.branch_name, row.branch_code, row.cashier_name, row.payment_method_summary, row.payment_status]
      .filter(Boolean)
      .some((value) => String(value).toLowerCase().includes(query)),
  )
})
const filteredCashLedger = computed(() => {
  const query = cashSearch.value.toLowerCase()
  const rows = accountingData.value?.cash_ledger || []
  if (!query) return rows

  return rows.filter((row) =>
    [row.reference_number, row.description, row.branch_name, row.branch_code, row.method, row.entry_type, row.direction]
      .filter(Boolean)
      .some((value) => String(value).toLowerCase().includes(query)),
  )
})
const selectedJournalLines = computed(() => {
  if (!selectedJournal.value) return []

  return (accountingData.value?.manual_journal_lines || []).filter((line) => line.journal_entry_id === selectedJournal.value.id)
})
const journalDebitTotal = computed(() => roundMoney(journalForm.lines.reduce((sum, line) => sum + Number(line.debit || 0), 0)))
const journalCreditTotal = computed(() => roundMoney(journalForm.lines.reduce((sum, line) => sum + Number(line.credit || 0), 0)))
const journalDifference = computed(() => roundMoney(Math.abs(journalDebitTotal.value - journalCreditTotal.value)))

function createJournalLine() {
  return {
    key: crypto.randomUUID(),
    account_id: null,
    description: '',
    debit: 0,
    credit: 0,
  }
}

function createJournalForm() {
  return {
    branch_id: null,
    journal_date: new Date(`${todayISO()}T00:00:00`),
    source_type: 'manual',
    description: '',
    lines: [createJournalLine(), createJournalLine()],
  }
}

function resetObject(target, source) {
  Object.keys(target).forEach((key) => {
    delete target[key]
  })
  Object.assign(target, source)
}

function normalizeDate(value) {
  return toISODate(value) || null
}

function defaultBranchId() {
  return filters.branchId || auth.state.profile?.branch_id || accountingData.value?.branches?.[0]?.id || null
}

function roundMoney(value) {
  return Math.round(Number(value || 0) * 100) / 100
}

function clearFeedback() {
  error.value = ''
  successMessage.value = ''
  formError.value = ''
}

async function loadAccounting() {
  loading.value = true
  error.value = ''
  successMessage.value = ''

  try {
    accountingData.value = await fetchAccountingManagement({
      from: normalizeDate(filters.from),
      to: normalizeDate(filters.to),
      branchId: filters.branchId,
      search: filters.search,
    })

    if (isBranchLocked.value && !filters.branchId) {
      filters.branchId = accountingData.value.branches[0]?.id || auth.state.profile?.branch_id || null
    }
  } catch (loadError) {
    error.value = loadError.message
  } finally {
    loading.value = false
  }
}

function openJournal() {
  resetObject(journalForm, {
    ...createJournalForm(),
    branch_id: defaultBranchId(),
  })
  formError.value = ''
  journalDialogVisible.value = true
}

function addJournalLine() {
  journalForm.lines.push(createJournalLine())
}

function removeJournalLine(index) {
  if (journalForm.lines.length <= 2) return
  journalForm.lines.splice(index, 1)
}

function validateJournal() {
  if (!journalForm.branch_id) {
    formError.value = 'Branch is required.'
    return false
  }

  if (!journalForm.description.trim()) {
    formError.value = 'Journal description is required.'
    return false
  }

  const validLines = journalForm.lines.filter((line) => line.account_id && (Number(line.debit || 0) > 0 || Number(line.credit || 0) > 0))

  if (validLines.length < 2) {
    formError.value = 'At least two journal lines are required.'
    return false
  }

  if (journalDifference.value !== 0) {
    formError.value = 'Debits and credits must match.'
    return false
  }

  return true
}

async function submitJournal() {
  clearFeedback()
  saving.value = true

  try {
    if (!validateJournal()) return
    accountingData.value = await postAccountingJournal({
      branch_id: journalForm.branch_id,
      journal_date: normalizeDate(journalForm.journal_date),
      source_type: journalForm.source_type,
      description: journalForm.description.trim(),
      lines: journalForm.lines
        .filter((line) => line.account_id && (Number(line.debit || 0) > 0 || Number(line.credit || 0) > 0))
        .map((line) => ({
          account_id: line.account_id,
          description: line.description.trim(),
          debit: Number(line.debit || 0),
          credit: Number(line.credit || 0),
        })),
    })
    journalDialogVisible.value = false
    successMessage.value = 'Manual journal was posted.'
  } catch (saveError) {
    formError.value = saveError.message
  } finally {
    saving.value = false
  }
}

function openJournalLines(journal) {
  selectedJournal.value = journal
  lineDialogVisible.value = true
}

function openVoidDialog(journal) {
  selectedJournal.value = journal
  voidReason.value = ''
  formError.value = ''
  voidDialogVisible.value = true
}

async function submitVoidJournal() {
  clearFeedback()

  if (!voidReason.value.trim()) {
    formError.value = 'Void reason is required.'
    return
  }

  saving.value = true

  try {
    accountingData.value = await voidAccountingJournal(selectedJournal.value.id, voidReason.value.trim())
    voidDialogVisible.value = false
    successMessage.value = 'Journal was voided.'
  } catch (voidError) {
    formError.value = voidError.message
  } finally {
    saving.value = false
  }
}

function lineTypeLabel(type) {
  return {
    revenue: 'Revenue',
    cogs: 'Cost of sales',
    subtotal: 'Subtotal',
    expense: 'Expense',
    net: 'Net result',
  }[type] || type
}

function accountTypeLabel(type) {
  return {
    asset: 'Asset',
    liability: 'Liability',
    equity: 'Equity',
    revenue: 'Revenue',
    cogs: 'COGS',
    expense: 'Expense',
  }[type] || type
}

function methodLabel(method) {
  return {
    cash: 'Cash',
    card: 'Card',
    gcash: 'GCash',
    maya: 'Maya',
    bank_transfer: 'Bank transfer',
    check: 'Check',
    customer_payment: 'Customer payment',
  }[method] || method || '-'
}

function statusLabel(status) {
  return {
    paid: 'Paid',
    partial: 'Partial',
    unpaid: 'Unpaid',
    refunded: 'Refunded',
    posted: 'Posted',
    voided: 'Voided',
  }[status] || status || '-'
}

function formatSignedBalance(row) {
  const absolute = formatCurrency(Math.abs(row.balance))
  if (row.balance === 0) return formatCurrency(0)

  const side = row.balance > 0 ? 'Dr' : 'Cr'
  return `${absolute} ${side}`
}

onMounted(loadAccounting)
</script>
