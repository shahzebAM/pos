<template>
  <section class="page-stack">
    <section class="page-hero page-hero--compact">
      <div>
        <p class="eyebrow">Module 7</p>
        <h1>POS Sales / Checkout</h1>
        <p>
          Scan barcodes, search products, apply approved discounts, split
          payments, print invoices, and complete sales with FEFO stock reduction.
        </p>
      </div>

      <div class="action-panel">
        <span class="scan-field">
          <i class="pi pi-barcode" />
          <PInputText
            ref="scanInput"
            v-model.trim="scanCode"
            placeholder="Scan barcode or SKU"
            @keydown.enter.prevent="handleScan"
          />
        </span>
        <PButton icon="pi pi-barcode" label="Add scan" outlined @click="handleScan" />
        <PButton icon="pi pi-refresh" label="Refresh" outlined :loading="loading" @click="loadPos" />
      </div>
    </section>

    <PMessage v-if="error" severity="error" :closable="false" class="setup-message">
      {{ error }}
    </PMessage>

    <PMessage v-if="successMessage" severity="success" :closable="false" class="setup-message">
      {{ successMessage }}
    </PMessage>

    <PMessage v-if="offlineQueue.length" severity="warn" :closable="false" class="setup-message">
      {{ offlineQueue.length }} offline sale{{ offlineQueue.length === 1 ? '' : 's' }} waiting to sync.
      <PButton label="Sync now" icon="pi pi-cloud-upload" text :loading="syncing" @click="syncOfflineQueue" />
    </PMessage>

    <PMessage v-if="shiftValidationMessage" severity="warn" :closable="false" class="setup-message">
      {{ shiftValidationMessage }}
    </PMessage>

    <section v-if="loading && !posData" class="stats-grid stats-grid--four">
      <PSkeleton v-for="item in 4" :key="item" height="8rem" border-radius="8px" />
    </section>

    <template v-else-if="posData">
      <section class="stats-grid">
        <MetricCard label="Today's sales" :value="formatCurrency(posData.summary.today_sales)" icon="pi pi-wallet" />
        <MetricCard label="Orders today" :value="formatNumber(posData.summary.today_orders)" icon="pi pi-shopping-bag" tone="blue" />
        <MetricCard label="VAT today" :value="formatCurrency(posData.summary.today_tax)" icon="pi pi-percentage" tone="purple" />
        <MetricCard label="Senior/PWD benefit" :value="formatCurrency(posData.summary.today_senior_pwd_discounts)" icon="pi pi-id-card" tone="orange" />
        <MetricCard label="Available items" :value="formatNumber(posData.summary.items_available)" icon="pi pi-box" tone="gold" />
        <MetricCard
          v-if="posData.shift_installed"
          label="Open shift"
          :value="posData.current_shift?.shift_number || 'Required'"
          :caption="posData.current_shift ? `${posData.current_shift.register_code} - ${formatCurrency(posData.current_shift.expected_cash)} expected` : 'Go to Shifts to open drawer'"
          icon="pi pi-clock"
          :tone="posData.current_shift ? 'green' : 'red'"
        />
      </section>

      <section class="pos-layout">
        <section class="panel pos-catalog-panel">
          <div class="table-toolbar product-toolbar">
            <div>
              <p class="eyebrow">Product search</p>
              <h2>{{ posData.branch?.name || 'POS branch' }}</h2>
            </div>
            <div class="toolbar-controls">
              <span class="search-field">
                <i class="pi pi-search" />
                <PInputText v-model.trim="search" placeholder="Search name, barcode, SKU" />
              </span>
              <PSelect
                v-model="selectedBranchId"
                :options="branchOptions"
                option-label="label"
                option-value="value"
                class="compact-select"
                :disabled="!canSelectBranch"
              />
            </div>
          </div>

          <div class="product-tile-grid">
            <article v-for="product in filteredProducts" :key="product.id" class="product-tile">
              <div class="product-tile__body">
                <div>
                  <strong>{{ product.name }}</strong>
                  <small>{{ product.sku }} - {{ product.barcode }}</small>
                </div>
                <span class="product-tile__tags">
                  <PTag :value="stockLabel(product.quantity_on_hand)" :severity="product.quantity_on_hand > 0 ? 'success' : 'danger'" />
                  <PTag
                    :value="seniorPwdCategoryShortLabel(product.senior_pwd_discount_category)"
                    :severity="seniorPwdCategorySeverity(product.senior_pwd_discount_category)"
                  />
                </span>
              </div>

              <div class="product-tile__meta">
                <span>{{ product.category_name || product.category || 'General' }}</span>
                <strong>{{ formatCurrency(product.selling_price) }}</strong>
              </div>

              <div v-if="product.variants.length" class="variant-button-grid">
                <PButton
                  v-for="variant in product.variants"
                  :key="variant.id"
                  :label="`${variant.variant_name} (${formatNumber(variant.quantity_on_hand)})`"
                  size="small"
                  outlined
                  :disabled="variant.quantity_on_hand <= 0"
                  @click="addProduct(product, variant)"
                />
              </div>

              <PButton
                icon="pi pi-plus"
                label="Add"
                :disabled="product.quantity_on_hand <= 0"
                @click="addProduct(product)"
              />
            </article>
          </div>

          <div v-if="!filteredProducts.length" class="empty-state empty-state--small">
            <i class="pi pi-search" />
            <p>No products match the current search.</p>
          </div>
        </section>

        <aside class="panel pos-cart-panel">
          <div class="panel__header">
            <div>
              <p class="eyebrow">Checkout cart</p>
              <h2>{{ formatNumber(cart.length) }} line{{ cart.length === 1 ? '' : 's' }}</h2>
            </div>
            <PButton icon="pi pi-trash" label="Clear" outlined severity="danger" :disabled="!cart.length" @click="clearCart" />
          </div>

          <div class="pos-cart-list">
            <article v-for="item in cart" :key="item.local_key" class="pos-cart-item">
              <div class="pos-cart-item__header">
                <div>
                  <strong>{{ item.product_name }}</strong>
                  <small>{{ item.variant_name || 'Base product' }} - {{ item.sku }}</small>
                </div>
                <PButton icon="pi pi-times" text rounded severity="danger" aria-label="Remove item" @click="removeCartItem(item.local_key)" />
              </div>

              <div class="pos-cart-item__controls">
                <PButton icon="pi pi-minus" text rounded :disabled="item.quantity <= 1" @click="changeQuantity(item, -1)" />
                <PInputNumber v-model="item.quantity" :min="1" :max="item.available" :use-grouping="false" fluid />
                <PButton icon="pi pi-plus" text rounded :disabled="item.quantity >= item.available" @click="changeQuantity(item, 1)" />
              </div>

              <div class="pos-cart-item__footer">
                <span>
                  {{ formatCurrency(item.unit_price) }} each
                  <small>{{ seniorPwdCategoryLabel(item.senior_pwd_discount_category) }}</small>
                </span>
                <strong>{{ formatCurrency(lineGross(item)) }}</strong>
              </div>
            </article>

            <div v-if="!cart.length" class="empty-state empty-state--small">
              <i class="pi pi-shopping-cart" />
              <p>Scan or add products to start a sale.</p>
            </div>
          </div>

          <div class="pos-checkout-form">
            <div class="form-grid">
              <label>
                Customer profile
                <PSelect
                  v-model="selectedCustomerId"
                  :options="customerOptions"
                  option-label="label"
                  option-value="value"
                  placeholder="Walk-in customer"
                  filter
                  fluid
                />
              </label>
              <label>
                Customer name
                <PInputText v-model.trim="customerName" placeholder="Walk-in customer" fluid @input="clearSelectedCustomerOnNameEdit" />
              </label>
            </div>

            <div class="form-grid">
              <label>
                Discount type
                <PSelect
                  v-model="discountType"
                  :options="discountTypeOptions"
                  option-label="label"
                  option-value="value"
                  fluid
                  :disabled="!canUseDiscount"
                />
              </label>
              <label>
                Discount value
                <PInputNumber
                  v-model="discountValue"
                  :min="0"
                  :max="discountType === 'percent' ? maxDiscountPercent : subtotal"
                  :suffix="discountType === 'percent' ? '%' : ''"
                  :disabled="discountType === 'none' || !canUseDiscount"
                  fluid
                />
              </label>
            </div>

            <section class="mini-section">
              <div class="mini-section__header">
                <div>
                  <h3>Senior Citizen / PWD</h3>
                  <small class="muted-block">Capture OSCA/PWD details for statutory discount claims.</small>
                </div>
                <PTag
                  :value="seniorPwdModuleReady ? (seniorPwdSettings.is_active ? 'Active' : 'Disabled') : 'Not installed'"
                  :severity="seniorPwdModuleReady && seniorPwdSettings.is_active ? 'success' : 'danger'"
                />
              </div>

              <PMessage v-if="!seniorPwdModuleReady" severity="warn" :closable="false" class="dialog-message">
                Run supabase/10-senior-pwd-discounts.sql to enable this checkout module.
              </PMessage>

              <PMessage v-else-if="!seniorPwdSettings.is_active" severity="warn" :closable="false" class="dialog-message">
                Senior/PWD discounts are disabled for this branch.
              </PMessage>

              <div class="form-grid">
                <label>
                  Discount category
                  <PSelect
                    v-model="seniorPwdType"
                    :options="seniorPwdDiscountOptions"
                    option-label="label"
                    option-value="value"
                    fluid
                    :disabled="!seniorPwdModuleReady || !seniorPwdSettings.is_active"
                  />
                </label>
                <label>
                  Benefit preview
                  <PInputText :model-value="formatCurrency(totalSeniorPwdBenefit)" readonly fluid />
                </label>
              </div>

              <div v-if="seniorPwdActive" class="form-grid">
                <label>
                  Beneficiary name
                  <PInputText v-model.trim="seniorPwdName" placeholder="Name on OSCA/PWD ID" fluid />
                </label>
                <label>
                  ID type
                  <PSelect v-model="seniorPwdIdType" :options="seniorPwdIdTypeOptions" option-label="label" option-value="value" fluid />
                </label>
                <label>
                  ID number
                  <PInputText v-model.trim="seniorPwdIdNumber" placeholder="OSCA/PWD ID number" fluid />
                </label>
                <label>
                  Booklet / reference
                  <PInputText
                    v-model.trim="seniorPwdBookletNumber"
                    placeholder="Required for basic necessities when enabled"
                    fluid
                  />
                </label>
              </div>

              <PMessage v-if="seniorPwdValidationMessage" severity="warn" :closable="false" class="dialog-message">
                {{ seniorPwdValidationMessage }}
              </PMessage>
            </section>

            <section class="mini-section">
              <div class="mini-section__header">
                <div>
                  <h3>Payments</h3>
                  <small class="muted-block">Use multiple rows for split payments.</small>
                </div>
                <PButton type="button" icon="pi pi-plus" label="Add" outlined @click="addPayment" />
              </div>

              <PMessage v-if="!paymentMethodOptions.length" severity="warn" :closable="false" class="dialog-message">
                No payment methods are enabled for this branch.
              </PMessage>

              <div class="payment-list">
                <article v-for="(payment, index) in payments" :key="payment.local_key" class="payment-row">
                  <PSelect
                    v-model="payment.method"
                    :options="paymentMethodOptions"
                    option-label="label"
                    option-value="value"
                    fluid
                  />
                  <PInputNumber v-model="payment.amount" mode="currency" :currency="currencyCode" locale="en-PH" :min="0" fluid />
                  <PInputText
                    v-model.trim="payment.reference_number"
                    :placeholder="paymentReferencePlaceholder(payment.method)"
                    fluid
                  />
                  <PButton
                    icon="pi pi-trash"
                    text
                    rounded
                    severity="danger"
                    aria-label="Remove payment"
                    :disabled="payments.length === 1"
                    @click="removePayment(index)"
                  />
                </article>
              </div>

              <PMessage v-if="paymentValidationMessage" severity="warn" :closable="false" class="dialog-message">
                {{ paymentValidationMessage }}
              </PMessage>
            </section>

            <label>
              Notes
              <PTextarea v-model.trim="notes" rows="2" auto-resize fluid placeholder="Optional checkout note" />
            </label>

            <div class="checkout-totals">
              <span>Subtotal <strong>{{ formatCurrency(subtotal) }}</strong></span>
              <span>Generic discount <strong>{{ formatCurrency(discountTotal) }}</strong></span>
              <span v-if="seniorPwdActive">Senior/PWD discount <strong>{{ formatCurrency(statutoryDiscountTotal) }}</strong></span>
              <span v-if="seniorPwdActive">Basic goods 5% <strong>{{ formatCurrency(statutorySpecialDiscountTotal) }}</strong></span>
              <span v-if="seniorPwdActive">VAT exemption <strong>{{ formatCurrency(statutoryVatExemptTotal) }}</strong></span>
              <span>Total discounts <strong>{{ formatCurrency(totalDiscount) }}</strong></span>
              <span>VAT <strong>{{ formatCurrency(taxTotal) }}</strong></span>
              <span class="checkout-totals__grand">Total <strong>{{ formatCurrency(total) }}</strong></span>
              <span>Tendered <strong>{{ formatCurrency(paymentTotal) }}</strong></span>
              <span :class="{ 'negative-text': balanceDue > 0 }">Balance <strong>{{ formatCurrency(balanceDue) }}</strong></span>
              <span>Change <strong>{{ formatCurrency(changeDue) }}</strong></span>
            </div>

            <div class="dialog-actions pos-checkout-actions">
              <PButton type="button" label="Exact cash" outlined :disabled="!cart.length" @click="setExactCash" />
              <PButton type="button" label="Save offline" outlined :disabled="!cart.length || !shiftReady" @click="saveOffline" />
              <PButton icon="pi pi-check" label="Checkout" :loading="saving" :disabled="!canCheckout" @click="completeCheckout" />
            </div>
          </div>
        </aside>
      </section>

      <section class="panel">
        <div class="panel__header">
          <div>
            <p class="eyebrow">Sales detail</p>
            <h2>Recent invoices and receipts</h2>
          </div>
        </div>

        <PDataTable
          :value="posData.recent_orders"
          data-key="id"
          responsive-layout="stack"
          breakpoint="860px"
          size="small"
          striped-rows
          paginator
          :rows="8"
        >
          <PColumn field="invoice_number" header="Invoice">
            <template #body="{ data }">
              <div class="branch-cell">
                <strong>{{ data.invoice_number }}</strong>
                <small>{{ data.order_number }} - {{ formatDateTime(data.created_at) }}</small>
              </div>
            </template>
          </PColumn>
          <PColumn field="cashier_name" header="Cashier" />
          <PColumn field="payment_method_summary" header="Payment" />
          <PColumn field="statutory_discount_type" header="Senior/PWD">
            <template #body="{ data }">
              <PTag
                :value="seniorPwdTypeLabel(data.statutory_discount_type)"
                :severity="data.statutory_discount_type === 'none' ? 'secondary' : 'success'"
              />
              <small v-if="data.statutory_discount_type !== 'none'" class="muted-block">
                {{ formatCurrency((data.statutory_discount_amount || 0) + (data.statutory_special_discount_amount || 0)) }}
              </small>
            </template>
          </PColumn>
          <PColumn field="total" header="Total">
            <template #body="{ data }">{{ formatCurrency(data.total) }}</template>
          </PColumn>
          <PColumn field="source" header="Source">
            <template #body="{ data }">
              <PTag :value="data.source" :severity="data.source === 'offline' ? 'warn' : 'success'" />
            </template>
          </PColumn>
          <PColumn header="Receipt">
            <template #body="{ data }">
              <div class="table-actions">
                <PButton icon="pi pi-print" text rounded aria-label="View receipt" @click="openReceipt(data)" />
                <PButton
                  icon="pi pi-undo"
                  text
                  rounded
                  aria-label="Return or refund"
                  :disabled="data.status !== 'completed'"
                  @click="openReturn(data)"
                />
              </div>
            </template>
          </PColumn>
        </PDataTable>
      </section>
    </template>

    <PDialog
      v-model:visible="receiptVisible"
      modal
      header="Invoice receipt"
      class="branch-dialog receipt-dialog"
      :style="{ width: 'min(520px, 96vw)' }"
    >
      <section v-if="receiptOrder" class="receipt-paper">
        <div class="receipt-paper__header">
          <strong>{{ posData?.branch?.name || 'POS Branch' }}</strong>
          <span>{{ posData?.branch?.address || 'Branch invoice' }}</span>
          <span>Invoice {{ receiptOrder.invoice_number }}</span>
          <span>{{ formatDateTime(receiptOrder.created_at) }}</span>
        </div>

        <div class="receipt-paper__meta">
          <span>Cashier</span>
          <strong>{{ receiptOrder.cashier_name || auth.state.profile?.full_name }}</strong>
          <span>Customer</span>
          <strong>{{ receiptOrder.customer_name || 'Walk-in' }}</strong>
          <template v-if="receiptOrder.statutory_discount_type !== 'none'">
            <span>Senior/PWD</span>
            <strong>{{ seniorPwdTypeLabel(receiptOrder.statutory_discount_type) }}</strong>
            <span>Name</span>
            <strong>{{ receiptOrder.beneficiary_name }}</strong>
            <span>ID</span>
            <strong>{{ receiptOrder.beneficiary_id_type }} {{ receiptOrder.beneficiary_id_number }}</strong>
          </template>
        </div>

        <div class="receipt-lines">
          <article v-for="item in receiptOrder.items" :key="item.id">
            <div>
              <strong>{{ item.product_name }}</strong>
              <small>{{ item.variant_name || item.sku }}</small>
            </div>
            <span>{{ formatNumber(item.quantity) }} x {{ formatCurrency(item.unit_price) }}</span>
            <strong>{{ formatCurrency(item.net_amount) }}</strong>
          </article>
        </div>

        <div class="receipt-paper__totals">
          <span>Subtotal <strong>{{ formatCurrency(receiptOrder.subtotal) }}</strong></span>
          <span>Discount <strong>{{ formatCurrency(receiptOrder.discount_total) }}</strong></span>
          <span v-if="receiptOrder.statutory_discount_type !== 'none'">
            Senior/PWD discount <strong>{{ formatCurrency(receiptOrder.statutory_discount_amount) }}</strong>
          </span>
          <span v-if="receiptOrder.statutory_discount_type !== 'none'">
            Basic goods 5% <strong>{{ formatCurrency(receiptOrder.statutory_special_discount_amount) }}</strong>
          </span>
          <span v-if="receiptOrder.statutory_discount_type !== 'none'">
            VAT exemption <strong>{{ formatCurrency(receiptOrder.statutory_vat_exempt_amount) }}</strong>
          </span>
          <span>VAT <strong>{{ formatCurrency(receiptOrder.tax_total) }}</strong></span>
          <span>Total <strong>{{ formatCurrency(receiptOrder.total) }}</strong></span>
          <span>Paid <strong>{{ formatCurrency(receiptOrder.amount_tendered) }}</strong></span>
          <span>Change <strong>{{ formatCurrency(receiptOrder.change_due) }}</strong></span>
        </div>

        <div class="receipt-paper__footer">
          <span>{{ receiptOrder.payment_method_summary }}</span>
          <span>{{ posData?.branch?.receipt_footer || 'Thank you for your purchase.' }}</span>
        </div>
      </section>

      <div class="dialog-actions">
        <PButton label="Close" severity="secondary" outlined @click="receiptVisible = false" />
        <PButton icon="pi pi-print" label="Print / Save PDF" @click="printReceipt" />
      </div>
    </PDialog>
  </section>
</template>

<script setup>
import { computed, nextTick, onMounted, reactive, ref, watch } from 'vue'
import { useRouter } from 'vue-router'
import MetricCard from '../components/MetricCard.vue'
import { currencyCode, formatCurrency, formatNumber } from '../lib/formatters'
import {
  checkoutSale,
  enqueueOfflineSale,
  fetchPosManagement,
  getOfflineSalesQueue,
  syncOfflineSales,
} from '../services/posService'
import { useAuthStore } from '../stores/authStore'

const auth = useAuthStore()
const router = useRouter()
const loading = ref(false)
const saving = ref(false)
const syncing = ref(false)
const error = ref('')
const successMessage = ref('')
const posData = ref(null)
const selectedBranchId = ref(null)
const selectedCustomerId = ref(null)
const search = ref('')
const scanCode = ref('')
const customerName = ref('')
const notes = ref('')
const discountType = ref('none')
const discountValue = ref(0)
const seniorPwdType = ref('none')
const seniorPwdName = ref('')
const seniorPwdIdType = ref('OSCA ID')
const seniorPwdIdNumber = ref('')
const seniorPwdBookletNumber = ref('')
const cart = ref([])
const payments = ref([createPaymentRow()])
const offlineQueue = ref([])
const receiptVisible = ref(false)
const receiptOrder = ref(null)
const scanInput = ref(null)

const discountTypeOptions = [
  { label: 'No discount', value: 'none' },
  { label: 'Percent', value: 'percent' },
  { label: 'Amount', value: 'amount' },
]

const seniorPwdIdTypeOptions = [
  { label: 'OSCA ID', value: 'OSCA ID' },
  { label: 'PWD ID', value: 'PWD ID' },
  { label: 'Government ID', value: 'Government ID' },
]

const canSelectBranch = computed(() => auth.isAdmin.value)
const maxDiscountPercent = computed(() => Number(auth.state.profile?.max_discount_percent || 0))
const canUseDiscount = computed(() => auth.isAdmin.value || (auth.state.profile?.permissions || []).includes('pos.discount'))
const seniorPwdSettings = computed(() => ({
  standard_discount_rate: 20,
  basic_necessity_rate: 5,
  require_id_capture: true,
  require_booklet_for_basic: true,
  is_active: true,
  ...(posData.value?.senior_pwd_settings || {}),
}))
const seniorPwdModuleReady = computed(() => Boolean(posData.value?.senior_pwd_installed))
const seniorPwdDiscountOptions = computed(() => posData.value?.senior_pwd_discount_options || [])
const seniorPwdActive = computed(() => seniorPwdType.value !== 'none' && seniorPwdModuleReady.value && seniorPwdSettings.value.is_active)

const branchOptions = computed(() =>
  (posData.value?.branches || []).map((branch) => ({
    label: `${branch.branch_code} - ${branch.name}`,
    value: branch.id,
  })),
)

const paymentMethodOptions = computed(() => posData.value?.payment_methods || [])
const customerOptions = computed(() => [
  { label: 'Walk-in customer', value: null },
  ...(posData.value?.customers || []).map((customer) => ({
    label: `${customer.customer_code} - ${customer.full_name}`,
    value: customer.id,
  })),
])
const selectedCustomer = computed(() => (posData.value?.customers || []).find((customer) => customer.id === selectedCustomerId.value))

const filteredProducts = computed(() => {
  const query = search.value.toLowerCase()

  return (posData.value?.products || []).filter((product) => {
    if (!query) return true

    return [
      product.name,
      product.sku,
      product.barcode,
      product.category,
      product.category_name,
      product.brand_name,
      ...product.variants.flatMap((variant) => [variant.variant_name, variant.sku, variant.barcode]),
    ]
      .filter(Boolean)
      .some((value) => String(value).toLowerCase().includes(query))
  })
})

const subtotal = computed(() => cart.value.reduce((total, item) => total + lineGross(item), 0))

const discountTotal = computed(() => {
  if (!canUseDiscount.value || discountType.value === 'none') return 0
  if (discountType.value === 'percent') {
    const percent = Math.min(Number(discountValue.value || 0), maxDiscountPercent.value || 100)
    return roundMoney(subtotal.value * (percent / 100))
  }

  return roundMoney(Math.min(Number(discountValue.value || 0), subtotal.value))
})

const cartLines = computed(() => {
  const lines = cart.value.map((item) => {
    const gross = lineGross(item)
    const lineDiscount = subtotal.value > 0 ? roundMoney((gross / subtotal.value) * discountTotal.value) : 0

    return {
      ...item,
      gross_amount: gross,
      discount_amount: lineDiscount,
    }
  })

  const roundedDiscountTotal = roundMoney(lines.reduce((sum, item) => sum + item.discount_amount, 0))
  const discountRoundingDifference = roundMoney(discountTotal.value - roundedDiscountTotal)
  if (lines.length && discountRoundingDifference !== 0) {
    lines[lines.length - 1].discount_amount = Math.max(0, roundMoney(lines[lines.length - 1].discount_amount + discountRoundingDifference))
  }

  return lines.map((item) => {
    const saleAmount = Math.max(roundMoney(item.gross_amount - item.discount_amount), 0)
    const category = item.senior_pwd_discount_category || 'regular_20'
    const taxRate = item.tax_type === 'vatable' ? Number(item.vat_rate || 12) : 0
    const usesRegularDiscount = seniorPwdActive.value && category === 'regular_20'
    const usesBasicDiscount = seniorPwdActive.value && category === 'basic_necessity_5'
    const discountBase =
      usesRegularDiscount && item.tax_type === 'vatable' && item.tax_inclusive
        ? roundMoney(saleAmount / (1 + taxRate / 100))
        : saleAmount
    const statutoryDiscountAmount = usesRegularDiscount
      ? roundMoney(discountBase * (Number(seniorPwdSettings.value.standard_discount_rate || 20) / 100))
      : 0
    const statutorySpecialDiscountAmount = usesBasicDiscount
      ? roundMoney(saleAmount * (Number(seniorPwdSettings.value.basic_necessity_rate || 5) / 100))
      : 0
    const statutoryVatExemptAmount =
      usesRegularDiscount && item.tax_type === 'vatable'
        ? item.tax_inclusive
          ? roundMoney(Math.max(saleAmount - discountBase, 0))
          : roundMoney(saleAmount * (taxRate / 100))
        : 0
    const taxableOrExemptAmount = usesRegularDiscount
      ? Math.max(roundMoney(discountBase - statutoryDiscountAmount), 0)
      : Math.max(roundMoney(saleAmount - statutorySpecialDiscountAmount), 0)
    const taxAmount =
      usesRegularDiscount && item.tax_type === 'vatable'
        ? 0
        : item.tax_type === 'vatable'
          ? item.tax_inclusive
            ? roundMoney(taxableOrExemptAmount - taxableOrExemptAmount / (1 + taxRate / 100))
            : roundMoney(taxableOrExemptAmount * (taxRate / 100))
          : 0
    const netAmount =
      usesRegularDiscount && item.tax_type === 'vatable'
        ? taxableOrExemptAmount
        : item.tax_type === 'vatable' && !item.tax_inclusive
          ? roundMoney(taxableOrExemptAmount + taxAmount)
          : taxableOrExemptAmount

    return {
      ...item,
      sale_amount: saleAmount,
      senior_pwd_discount_category: category,
      statutory_discount_amount: statutoryDiscountAmount,
      statutory_vat_exempt_amount: statutoryVatExemptAmount,
      statutory_special_discount_amount: statutorySpecialDiscountAmount,
      tax_amount: taxAmount,
      net_amount: netAmount,
    }
  })
})

const statutoryDiscountTotal = computed(() => roundMoney(cartLines.value.reduce((total, item) => total + item.statutory_discount_amount, 0)))
const statutoryVatExemptTotal = computed(() => roundMoney(cartLines.value.reduce((total, item) => total + item.statutory_vat_exempt_amount, 0)))
const statutorySpecialDiscountTotal = computed(() =>
  roundMoney(cartLines.value.reduce((total, item) => total + item.statutory_special_discount_amount, 0)),
)
const totalSeniorPwdBenefit = computed(() => roundMoney(statutoryDiscountTotal.value + statutorySpecialDiscountTotal.value + statutoryVatExemptTotal.value))
const totalDiscount = computed(() => roundMoney(discountTotal.value + statutoryDiscountTotal.value + statutorySpecialDiscountTotal.value))
const taxTotal = computed(() => roundMoney(cartLines.value.reduce((total, item) => total + item.tax_amount, 0)))
const total = computed(() => roundMoney(cartLines.value.reduce((sum, item) => sum + item.net_amount, 0)))
const paymentTotal = computed(() => roundMoney(payments.value.reduce((sum, payment) => sum + Number(payment.amount || 0), 0)))
const balanceDue = computed(() => Math.max(roundMoney(total.value - paymentTotal.value), 0))
const hasChangePayment = computed(() => payments.value.some((payment) => paymentCanGiveChange(payment.method)))
const changeDue = computed(() => (hasChangePayment.value ? Math.max(roundMoney(paymentTotal.value - total.value), 0) : 0))
const seniorPwdValidationMessage = computed(() => {
  if (seniorPwdType.value !== 'none' && !seniorPwdModuleReady.value) {
    return 'Senior/PWD checkout is not installed yet. Run the Module 10 SQL first.'
  }
  if (seniorPwdType.value !== 'none' && !seniorPwdSettings.value.is_active) {
    return 'Senior/PWD discounts are disabled for this branch.'
  }
  if (!seniorPwdActive.value) return ''
  if (seniorPwdSettings.value.require_id_capture && (!seniorPwdName.value || !seniorPwdIdNumber.value)) {
    return 'Beneficiary name and ID number are required for Senior/PWD discounts.'
  }
  if (seniorPwdSettings.value.require_booklet_for_basic && statutorySpecialDiscountTotal.value > 0 && !seniorPwdBookletNumber.value) {
    return 'Booklet or reference number is required because the cart includes basic necessities.'
  }
  if (totalSeniorPwdBenefit.value <= 0) {
    return 'No cart item is eligible for the selected Senior/PWD discount.'
  }

  return ''
})
const paymentValidationMessage = computed(() => {
  if (!cart.value.length) return ''
  if (!paymentMethodOptions.value.length) return 'No payment methods are enabled for this branch.'

  let runningTendered = 0

  for (const payment of payments.value) {
    const option = paymentOption(payment.method)
    const amount = Number(payment.amount || 0)

    if (!option) return 'One selected payment method is disabled for this branch.'
    if (amount <= 0) return 'Each payment row must have an amount greater than zero.'
    if (paymentRequiresReference(payment.method) && !payment.reference_number?.trim()) {
      return `${option.label} reference number is required.`
    }

    const remaining = Math.max(roundMoney(total.value - runningTendered), 0)
    if (amount > remaining + 0.01 && !paymentCanGiveChange(payment.method)) {
      return 'Only cash or change-enabled payment methods can exceed the remaining balance.'
    }

    runningTendered = roundMoney(runningTendered + amount)
  }

  if (paymentTotal.value > total.value && !hasChangePayment.value) {
    return 'Overpayment requires a cash or change-enabled payment row.'
  }

  return ''
})
const shiftReady = computed(() => !posData.value?.shift_installed || Boolean(posData.value?.current_shift))
const shiftValidationMessage = computed(() => {
  if (!posData.value?.shift_installed || posData.value?.current_shift) return ''

  return 'Open a cashier shift before checkout. POS sales are attached to the active cash drawer.'
})
const canCheckout = computed(
  () =>
    cart.value.length > 0 &&
    total.value > 0 &&
    paymentTotal.value >= total.value &&
    shiftReady.value &&
    !saving.value &&
    !seniorPwdValidationMessage.value &&
    !paymentValidationMessage.value,
)

watch(selectedBranchId, async (newValue, oldValue) => {
  if (!posData.value || !canSelectBranch.value || newValue === oldValue) return
  clearCart()
  await loadPos()
})

watch(discountType, () => {
  if (discountType.value === 'none') discountValue.value = 0
})

watch(seniorPwdType, () => {
  seniorPwdIdType.value = seniorPwdType.value === 'pwd' ? 'PWD ID' : 'OSCA ID'
  if (seniorPwdType.value === 'none') clearSeniorPwdFields()
  setExactCashIfSinglePayment()
})

watch(total, () => {
  setExactCashIfSinglePayment()
})

watch(selectedCustomerId, (customerId) => {
  const customer = (posData.value?.customers || []).find((row) => row.id === customerId)
  if (customer) {
    customerName.value = customer.full_name
  } else if (!customerId) {
    customerName.value = ''
  }
})

function createPaymentRow(payload = {}) {
  return {
    local_key: `${Date.now()}-${Math.random()}`,
    method: payload.method || 'cash',
    amount: Number(payload.amount || 0),
    reference_number: payload.reference_number || '',
  }
}

function roundMoney(value) {
  return Math.round(Number(value || 0) * 100) / 100
}

function lineGross(item) {
  return roundMoney(Number(item.quantity || 0) * Number(item.unit_price || 0))
}

function stockLabel(value) {
  return Number(value || 0) > 0 ? `${formatNumber(value)} in stock` : 'Out'
}

function seniorPwdCategoryLabel(value) {
  if (value === 'basic_necessity_5') return 'Basic necessity / 5%'
  if (value === 'not_eligible') return 'Not Senior/PWD eligible'

  return '20% + VAT exemption'
}

function seniorPwdCategoryShortLabel(value) {
  if (value === 'basic_necessity_5') return '5%'
  if (value === 'not_eligible') return 'No SP/PWD'

  return '20% VAT-ex'
}

function seniorPwdCategorySeverity(value) {
  if (value === 'basic_necessity_5') return 'warn'
  if (value === 'not_eligible') return 'secondary'

  return 'info'
}

function seniorPwdTypeLabel(value) {
  if (value === 'senior') return 'Senior Citizen'
  if (value === 'pwd') return 'PWD'

  return 'None'
}

function paymentOption(method) {
  return paymentMethodOptions.value.find((option) => option.value === method)
}

function paymentRequiresReference(method) {
  return Boolean(paymentOption(method)?.requires_reference)
}

function paymentCanGiveChange(method) {
  const option = paymentOption(method)
  return method === 'cash' || Boolean(option?.allow_change)
}

function paymentReferencePlaceholder(method) {
  return paymentRequiresReference(method) ? `${paymentOption(method)?.label || 'Payment'} reference required` : 'Reference'
}

function productAvailable(product, variant = null) {
  return Number((variant || product).quantity_on_hand || 0)
}

function cartKey(product, variant = null) {
  return `${product.id}:${variant?.id || 'base'}`
}

function addProduct(product, variant = null) {
  const available = productAvailable(product, variant)
  if (available <= 0) return

  const key = cartKey(product, variant)
  const existing = cart.value.find((item) => item.key === key)

  if (existing) {
    if (existing.quantity < existing.available) existing.quantity += 1
    return
  }

  cart.value.push({
    local_key: `${Date.now()}-${Math.random()}`,
    key,
    product_id: product.id,
    product_variant_id: variant?.id || null,
    product_name: product.name,
    variant_name: variant?.variant_name || '',
    sku: variant?.sku || product.sku,
    barcode: variant?.barcode || product.barcode,
    quantity: 1,
    available,
    unit_price: Number(variant?.selling_price || product.selling_price || 0),
    tax_type: product.tax_type,
    vat_rate: Number(product.vat_rate || 0),
    tax_inclusive: Boolean(product.tax_inclusive),
    senior_pwd_discount_category: product.senior_pwd_discount_category || 'regular_20',
  })

  setExactCashIfSinglePayment()
}

function changeQuantity(item, delta) {
  item.quantity = Math.min(Math.max(Number(item.quantity || 1) + delta, 1), item.available)
  setExactCashIfSinglePayment()
}

function removeCartItem(localKey) {
  cart.value = cart.value.filter((item) => item.local_key !== localKey)
  setExactCashIfSinglePayment()
}

function clearCart() {
  cart.value = []
  selectedCustomerId.value = null
  customerName.value = ''
  notes.value = ''
  discountType.value = 'none'
  discountValue.value = 0
  seniorPwdType.value = 'none'
  clearSeniorPwdFields()
  payments.value = [createPaymentRow()]
}

function clearSelectedCustomerOnNameEdit() {
  if (selectedCustomer.value && customerName.value !== selectedCustomer.value.full_name) {
    selectedCustomerId.value = null
  }
}

function clearSeniorPwdFields() {
  seniorPwdName.value = ''
  seniorPwdIdType.value = 'OSCA ID'
  seniorPwdIdNumber.value = ''
  seniorPwdBookletNumber.value = ''
}

function addPayment() {
  payments.value.push(createPaymentRow())
}

function removePayment(index) {
  if (payments.value.length <= 1) return
  payments.value.splice(index, 1)
}

function setExactCash() {
  const exactMethod = paymentMethodOptions.value.find((method) => method.value === 'cash') || paymentMethodOptions.value.find((method) => method.allow_change)
  payments.value = [createPaymentRow({ method: exactMethod?.value || 'cash', amount: total.value })]
}

function setExactCashIfSinglePayment() {
  if (payments.value.length === 1 && paymentCanGiveChange(payments.value[0].method)) {
    payments.value[0].amount = total.value
  }
}

function ensureEnabledPaymentRows() {
  const firstMethod = paymentMethodOptions.value[0]?.value || 'cash'
  payments.value.forEach((payment) => {
    if (!paymentOption(payment.method)) {
      payment.method = firstMethod
      payment.reference_number = ''
    }
  })
}

function buildCheckoutPayload(source = 'online') {
  return {
    branch_id: selectedBranchId.value || posData.value?.branch?.id,
    customer_id: selectedCustomerId.value,
    customer_name: customerName.value,
    discount_type: discountType.value,
    discount_value: Number(discountValue.value || 0),
    notes: notes.value,
    source,
    senior_pwd_discount: {
      type: seniorPwdType.value,
      beneficiary_name: seniorPwdName.value,
      id_type: seniorPwdIdType.value,
      id_number: seniorPwdIdNumber.value,
      booklet_number: seniorPwdBookletNumber.value,
    },
    items: cart.value.map((item) => ({
      product_id: item.product_id,
      product_variant_id: item.product_variant_id,
      quantity: Number(item.quantity || 0),
    })),
    payments: payments.value.map((payment) => ({
      method: payment.method,
      amount: Number(payment.amount || 0),
      reference_number: payment.reference_number,
    })),
  }
}

async function loadPos() {
  loading.value = true
  error.value = ''
  successMessage.value = ''

  try {
    const data = await fetchPosManagement(canSelectBranch.value ? selectedBranchId.value : null)
    posData.value = data
    selectedBranchId.value = data.branch?.id || selectedBranchId.value
    ensureEnabledPaymentRows()
  } catch (loadError) {
    error.value = loadError.message
  } finally {
    loading.value = false
  }
}

async function completeCheckout() {
  saving.value = true
  error.value = ''
  successMessage.value = ''

  try {
    const result = await checkoutSale(buildCheckoutPayload('online'))
    posData.value = result.pos
    selectedBranchId.value = result.pos.branch?.id || selectedBranchId.value
    receiptOrder.value = result.order
    receiptVisible.value = true
    clearCart()
    successMessage.value = 'Sale completed and receipt saved.'
  } catch (checkoutError) {
    error.value = checkoutError.message
  } finally {
    saving.value = false
  }
}

function saveOffline() {
  if (!cart.value.length) return

  const queued = enqueueOfflineSale(buildCheckoutPayload('offline'), {
    subtotal: subtotal.value,
    discount_total: discountTotal.value,
    statutory_discount_amount: statutoryDiscountTotal.value,
    statutory_vat_exempt_amount: statutoryVatExemptTotal.value,
    statutory_special_discount_amount: statutorySpecialDiscountTotal.value,
    tax_total: taxTotal.value,
    total: total.value,
  })

  offlineQueue.value = getOfflineSalesQueue()
  clearCart()
  successMessage.value = `Offline sale saved as ${queued.id}. Sync it when the connection is ready.`
}

async function syncOfflineQueue() {
  syncing.value = true
  error.value = ''
  successMessage.value = ''

  try {
    const result = await syncOfflineSales()
    offlineQueue.value = getOfflineSalesQueue()

    if (result.synced.length) {
      const last = result.synced[result.synced.length - 1].result
      posData.value = last.pos
      receiptOrder.value = last.order
      receiptVisible.value = true
    }

    successMessage.value = `${result.synced.length} offline sale${result.synced.length === 1 ? '' : 's'} synced.`
    if (result.failed.length) {
      error.value = `${result.failed.length} offline sale${result.failed.length === 1 ? '' : 's'} could not sync. Check stock and payment totals.`
    }
  } catch (syncError) {
    error.value = syncError.message
  } finally {
    syncing.value = false
  }
}

function handleScan() {
  const code = scanCode.value.trim().toLowerCase()
  if (!code) return

  for (const product of posData.value?.products || []) {
    if ([product.barcode, product.sku].filter(Boolean).some((value) => String(value).toLowerCase() === code)) {
      addProduct(product)
      scanCode.value = ''
      return
    }

    const variant = product.variants.find((row) =>
      [row.barcode, row.sku].filter(Boolean).some((value) => String(value).toLowerCase() === code),
    )

    if (variant) {
      addProduct(product, variant)
      scanCode.value = ''
      return
    }
  }

  error.value = `No product found for barcode/SKU "${scanCode.value}".`
}

function openReceipt(order) {
  receiptOrder.value = order
  receiptVisible.value = true
}

function openReturn(order) {
  router.push({ name: 'returns', query: { order: order.id } })
}

function printReceipt() {
  window.print()
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

onMounted(async () => {
  offlineQueue.value = getOfflineSalesQueue()
  await loadPos()
  await nextTick()
  scanInput.value?.$el?.querySelector?.('input')?.focus?.()
})
</script>
