<template>
  <section class="page-stack">
    <section class="page-hero page-hero--compact">
      <div>
        <p class="eyebrow">Module 4</p>
        <h1>Product Management</h1>
        <p>
          Maintain products, categories, brands, units, variants, SKU/barcode
          records, and Philippine VAT tagging before inventory and POS checkout.
        </p>
      </div>

      <div class="action-panel">
        <PButton icon="pi pi-plus" label="Add product" :disabled="!auth.isAdmin.value" @click="openProductCreate" />
        <PButton icon="pi pi-tags" label="Category" outlined :disabled="!auth.isAdmin.value" @click="openReferenceCreate('category')" />
        <PButton icon="pi pi-bookmark" label="Brand" outlined :disabled="!auth.isAdmin.value" @click="openReferenceCreate('brand')" />
        <PButton icon="pi pi-box" label="Unit" outlined :disabled="!auth.isAdmin.value" @click="openReferenceCreate('unit')" />
        <PButton icon="pi pi-refresh" label="Refresh" outlined :loading="loading" @click="loadProducts" />
      </div>
    </section>

    <PMessage v-if="!auth.isAdmin.value" severity="warn" :closable="false" class="setup-message">
      You can view products with this role. Creating, editing, and deleting products is admin-only.
    </PMessage>

    <PMessage v-if="error" severity="error" :closable="false" class="setup-message">
      {{ error }}
    </PMessage>

    <PMessage v-if="successMessage" severity="success" :closable="false" class="setup-message">
      {{ successMessage }}
    </PMessage>

    <section v-if="loading && !productData" class="stats-grid">
      <PSkeleton v-for="item in 6" :key="item" height="8rem" border-radius="8px" />
    </section>

    <template v-else-if="productData">
      <section class="stats-grid">
        <MetricCard label="Total products" :value="formatNumber(productData.summary.total_products)" icon="pi pi-box" />
        <MetricCard label="Active products" :value="formatNumber(productData.summary.active_products)" icon="pi pi-check-circle" tone="blue" />
        <MetricCard label="Categories" :value="formatNumber(productData.summary.categories)" icon="pi pi-tags" tone="gold" />
        <MetricCard label="Brands" :value="formatNumber(productData.summary.brands)" icon="pi pi-bookmark" tone="purple" />
        <MetricCard label="Units" :value="formatNumber(productData.summary.units)" icon="pi pi-th-large" tone="orange" />
        <MetricCard label="VATable items" :value="formatNumber(productData.summary.vatable_items)" icon="pi pi-percentage" tone="green" />
      </section>

      <section class="panel">
        <div class="table-toolbar product-toolbar">
          <div>
            <p class="eyebrow">Catalog</p>
            <h2>Products and variants</h2>
          </div>

          <div class="toolbar-controls">
            <span class="search-field">
              <i class="pi pi-search" />
              <PInputText v-model.trim="search" placeholder="Search name, SKU, barcode, brand" />
            </span>
            <PSelect
              v-model="categoryFilter"
              :options="categoryFilterOptions"
              option-label="label"
              option-value="value"
              class="compact-select"
            />
            <PSelect
              v-model="taxFilter"
              :options="taxFilterOptions"
              option-label="label"
              option-value="value"
              class="compact-select"
            />
          </div>
        </div>

        <PDataTable
          :value="filteredProducts"
          data-key="id"
          responsive-layout="stack"
          breakpoint="980px"
          size="small"
          striped-rows
          paginator
          :rows="10"
        >
          <PColumn field="name" header="Product">
            <template #body="{ data }">
              <div class="branch-cell">
                <strong>{{ data.name }}</strong>
                <small>SKU {{ data.sku }} - Barcode {{ data.barcode }}</small>
              </div>
            </template>
          </PColumn>
          <PColumn field="category_name" header="Category">
            <template #body="{ data }">
              {{ data.category_name || data.category || '-' }}
              <small class="muted-block">{{ data.brand_name || 'Unbranded' }}</small>
            </template>
          </PColumn>
          <PColumn field="unit_name" header="Unit">
            <template #body="{ data }">
              {{ data.unit_name || '-' }}
              <small class="muted-block">{{ data.unit_abbreviation || '' }}</small>
            </template>
          </PColumn>
          <PColumn field="selling_price" header="Price">
            <template #body="{ data }">
              <strong>{{ formatCurrency(data.selling_price) }}</strong>
              <small class="muted-block">Cost {{ formatCurrency(data.cost_price) }}</small>
            </template>
          </PColumn>
          <PColumn field="tax_type" header="Tax">
            <template #body="{ data }">
              <PTag :value="taxLabel(data.tax_type)" :severity="taxSeverity(data.tax_type)" />
              <small class="muted-block">{{ data.tax_inclusive ? 'Tax inclusive' : 'Tax exclusive' }} - {{ data.vat_rate }}%</small>
            </template>
          </PColumn>
          <PColumn field="stock_units" header="Stock">
            <template #body="{ data }">
              {{ formatNumber(data.stock_units) }}
              <small class="muted-block">Reorder at {{ formatNumber(data.reorder_level) }}</small>
            </template>
          </PColumn>
          <PColumn field="variant_count" header="Variants">
            <template #body="{ data }">
              <PTag :value="`${formatNumber(data.variant_count)} variants`" :severity="data.variant_count ? 'info' : 'secondary'" />
            </template>
          </PColumn>
          <PColumn field="is_active" header="Status">
            <template #body="{ data }">
              <PTag :value="data.is_active ? 'Active' : 'Inactive'" :severity="data.is_active ? 'success' : 'danger'" />
            </template>
          </PColumn>
          <PColumn header="Actions">
            <template #body="{ data }">
              <div class="table-actions">
                <PButton
                  icon="pi pi-pencil"
                  text
                  rounded
                  aria-label="Edit product"
                  :disabled="!auth.isAdmin.value"
                  @click="openProductEdit(data)"
                />
                <PButton
                  icon="pi pi-trash"
                  text
                  rounded
                  severity="danger"
                  aria-label="Delete product"
                  :disabled="!auth.isAdmin.value"
                  @click="deleteProductRow(data)"
                />
              </div>
            </template>
          </PColumn>
        </PDataTable>
      </section>

      <section class="panel">
        <div class="panel__header">
          <div>
            <p class="eyebrow">Catalog setup</p>
            <h2>Categories, brands, and units</h2>
          </div>
        </div>

        <div class="reference-grid">
          <section class="reference-column">
            <div class="reference-column__header">
              <h3>Categories</h3>
              <PButton icon="pi pi-plus" text rounded aria-label="Add category" :disabled="!auth.isAdmin.value" @click="openReferenceCreate('category')" />
            </div>
            <div class="stack-list">
              <article v-for="category in productData.categories" :key="category.id" class="stack-list__item">
                <div>
                  <strong>{{ category.name }}</strong>
                  <small>{{ category.code }}{{ category.description ? ` - ${category.description}` : '' }}</small>
                </div>
                <div class="table-actions">
                  <PTag :value="category.is_active ? 'Active' : 'Inactive'" :severity="category.is_active ? 'success' : 'danger'" />
                  <PButton icon="pi pi-pencil" text rounded aria-label="Edit category" :disabled="!auth.isAdmin.value" @click="openReferenceEdit('category', category)" />
                </div>
              </article>
            </div>
          </section>

          <section class="reference-column">
            <div class="reference-column__header">
              <h3>Brands</h3>
              <PButton icon="pi pi-plus" text rounded aria-label="Add brand" :disabled="!auth.isAdmin.value" @click="openReferenceCreate('brand')" />
            </div>
            <div class="stack-list">
              <article v-for="brand in productData.brands" :key="brand.id" class="stack-list__item">
                <div>
                  <strong>{{ brand.name }}</strong>
                  <small>{{ brand.code }}{{ brand.description ? ` - ${brand.description}` : '' }}</small>
                </div>
                <div class="table-actions">
                  <PTag :value="brand.is_active ? 'Active' : 'Inactive'" :severity="brand.is_active ? 'success' : 'danger'" />
                  <PButton icon="pi pi-pencil" text rounded aria-label="Edit brand" :disabled="!auth.isAdmin.value" @click="openReferenceEdit('brand', brand)" />
                </div>
              </article>
            </div>
          </section>

          <section class="reference-column">
            <div class="reference-column__header">
              <h3>Units</h3>
              <PButton icon="pi pi-plus" text rounded aria-label="Add unit" :disabled="!auth.isAdmin.value" @click="openReferenceCreate('unit')" />
            </div>
            <div class="stack-list">
              <article v-for="unit in productData.units" :key="unit.id" class="stack-list__item">
                <div>
                  <strong>{{ unit.name }}</strong>
                  <small>{{ unit.code }} - {{ unit.abbreviation }} - {{ unit.unit_type }}</small>
                </div>
                <div class="table-actions">
                  <PTag :value="unit.allows_decimal ? 'Decimal' : 'Whole'" severity="info" />
                  <PButton icon="pi pi-pencil" text rounded aria-label="Edit unit" :disabled="!auth.isAdmin.value" @click="openReferenceEdit('unit', unit)" />
                </div>
              </article>
            </div>
          </section>
        </div>
      </section>
    </template>

    <PDialog
      v-model:visible="productDialogVisible"
      modal
      :header="editingProduct ? 'Edit product' : 'Add product'"
      class="branch-dialog"
      :style="{ width: 'min(1080px, 96vw)' }"
    >
      <form class="branch-form" @submit.prevent="saveProduct">
        <PMessage v-if="productFormError" severity="error" :closable="false" class="dialog-message">
          {{ productFormError }}
        </PMessage>

        <div class="form-grid">
          <label>
            SKU
            <PInputText v-model.trim="productForm.sku" placeholder="SKU-ITEM-001" fluid @input="clearProductField('sku')" />
            <span v-if="productErrors.sku" class="field-error">{{ productErrors.sku }}</span>
          </label>
          <label>
            Barcode
            <PInputText v-model.trim="productForm.barcode" placeholder="4801234567890" fluid @input="clearProductField('barcode')" />
            <span v-if="productErrors.barcode" class="field-error">{{ productErrors.barcode }}</span>
          </label>
          <label>
            Product name
            <PInputText v-model.trim="productForm.name" placeholder="Product name" fluid @input="clearProductField('name')" />
            <span v-if="productErrors.name" class="field-error">{{ productErrors.name }}</span>
          </label>
          <label>
            Category
            <PSelect
              v-model="productForm.category_id"
              :options="categoryOptions"
              option-label="label"
              option-value="value"
              placeholder="Select category"
              fluid
              @change="clearProductField('category_id')"
            />
            <span v-if="productErrors.category_id" class="field-error">{{ productErrors.category_id }}</span>
          </label>
          <label>
            Brand
            <PSelect
              v-model="productForm.brand_id"
              :options="brandOptions"
              option-label="label"
              option-value="value"
              placeholder="Select brand"
              fluid
              @change="clearProductField('brand_id')"
            />
            <span v-if="productErrors.brand_id" class="field-error">{{ productErrors.brand_id }}</span>
          </label>
          <label>
            Unit
            <PSelect
              v-model="productForm.unit_id"
              :options="unitOptions"
              option-label="label"
              option-value="value"
              placeholder="Select unit"
              fluid
              @change="clearProductField('unit_id')"
            />
            <span v-if="productErrors.unit_id" class="field-error">{{ productErrors.unit_id }}</span>
          </label>
          <label>
            Cost price
            <PInputNumber v-model="productForm.cost_price" mode="currency" :currency="currencyCode" locale="en-PH" :min="0" fluid />
          </label>
          <label>
            Selling price
            <PInputNumber
              v-model="productForm.selling_price"
              mode="currency"
              :currency="currencyCode"
              locale="en-PH"
              :min="0"
              fluid
              @update:model-value="clearProductField('selling_price')"
            />
            <span v-if="productErrors.selling_price" class="field-error">{{ productErrors.selling_price }}</span>
          </label>
          <label>
            Tax type
            <PSelect v-model="productForm.tax_type" :options="taxTypeOptions" option-label="label" option-value="value" fluid />
          </label>
          <label>
            VAT rate
            <PInputNumber v-model="productForm.vat_rate" suffix="%" :min="0" :max="100" :min-fraction-digits="2" fluid />
          </label>
          <label>
            Reorder level
            <PInputNumber v-model="productForm.reorder_level" :min="0" :use-grouping="false" fluid />
          </label>
        </div>

        <label>
          Description
          <PTextarea v-model.trim="productForm.description" rows="3" auto-resize fluid />
        </label>

        <div class="switch-row">
          <label>
            <PCheckbox v-model="productForm.tax_inclusive" binary />
            Tax inclusive price
          </label>
          <label>
            <PCheckbox v-model="productForm.is_active" binary />
            Active product
          </label>
        </div>

        <section class="mini-section">
          <div class="mini-section__header">
            <div>
              <h3>Variants</h3>
              <small class="muted-block">Use variants for sizes, packs, box quantities, or alternate barcodes.</small>
            </div>
            <PButton type="button" icon="pi pi-plus" label="Add variant" outlined @click="addVariant" />
          </div>

          <span v-if="productErrors.variants" class="field-error">{{ productErrors.variants }}</span>

          <div v-if="productForm.variants.length" class="variant-list">
            <article v-for="(variant, index) in productForm.variants" :key="variant.local_key" class="variant-row">
              <div class="variant-row__header">
                <strong>{{ variant.variant_name || `Variant ${index + 1}` }}</strong>
                <PButton type="button" icon="pi pi-trash" text rounded severity="danger" aria-label="Remove variant" @click="removeVariant(index)" />
              </div>
              <div class="form-grid">
                <label>
                  Variant name
                  <PInputText v-model.trim="variant.variant_name" placeholder="Small / Box / 500ml" fluid @input="clearProductField('variants')" />
                </label>
                <label>
                  Variant SKU
                  <PInputText v-model.trim="variant.sku" placeholder="SKU-ITEM-001-S" fluid @input="clearProductField('variants')" />
                </label>
                <label>
                  Variant barcode
                  <PInputText v-model.trim="variant.barcode" placeholder="Optional barcode" fluid />
                </label>
                <label>
                  Unit
                  <PSelect v-model="variant.unit_id" :options="unitOptions" option-label="label" option-value="value" fluid />
                </label>
                <label>
                  Cost price
                  <PInputNumber v-model="variant.cost_price" mode="currency" :currency="currencyCode" locale="en-PH" :min="0" fluid />
                </label>
                <label>
                  Selling price
                  <PInputNumber v-model="variant.selling_price" mode="currency" :currency="currencyCode" locale="en-PH" :min="0" fluid />
                </label>
              </div>
              <div class="switch-row">
                <label>
                  <PCheckbox v-model="variant.is_active" binary />
                  Active variant
                </label>
              </div>
            </article>
          </div>

          <div v-else class="empty-state empty-state--small">
            <i class="pi pi-box" />
            <p>No variants added.</p>
          </div>
        </section>

        <div class="dialog-actions">
          <PButton type="button" label="Cancel" severity="secondary" outlined @click="productDialogVisible = false" />
          <PButton type="submit" icon="pi pi-save" label="Save product" :loading="saving" />
        </div>
      </form>
    </PDialog>

    <PDialog
      v-model:visible="referenceDialogVisible"
      modal
      :header="referenceDialogTitle"
      class="branch-dialog"
      :style="{ width: 'min(720px, 96vw)' }"
    >
      <form class="branch-form" @submit.prevent="saveReference">
        <PMessage v-if="referenceFormError" severity="error" :closable="false" class="dialog-message">
          {{ referenceFormError }}
        </PMessage>

        <div class="form-grid">
          <label>
            Code
            <PInputText v-model.trim="referenceForm.code" placeholder="AUTO IF BLANK" fluid />
          </label>
          <label>
            Name
            <PInputText v-model.trim="referenceForm.name" placeholder="Name" fluid @input="clearReferenceField('name')" />
            <span v-if="referenceErrors.name" class="field-error">{{ referenceErrors.name }}</span>
          </label>
          <label v-if="referenceMode === 'unit'">
            Abbreviation
            <PInputText v-model.trim="referenceForm.abbreviation" placeholder="pc" fluid @input="clearReferenceField('abbreviation')" />
            <span v-if="referenceErrors.abbreviation" class="field-error">{{ referenceErrors.abbreviation }}</span>
          </label>
          <label v-if="referenceMode === 'unit'">
            Unit type
            <PSelect v-model="referenceForm.unit_type" :options="unitTypeOptions" option-label="label" option-value="value" fluid />
          </label>
        </div>

        <label v-if="referenceMode !== 'unit'">
          Description
          <PTextarea v-model.trim="referenceForm.description" rows="3" auto-resize fluid />
        </label>

        <div class="switch-row">
          <label v-if="referenceMode === 'unit'">
            <PCheckbox v-model="referenceForm.allows_decimal" binary />
            Allows decimal quantities
          </label>
          <label>
            <PCheckbox v-model="referenceForm.is_active" binary />
            Active
          </label>
        </div>

        <div class="dialog-actions">
          <PButton type="button" label="Cancel" severity="secondary" outlined @click="referenceDialogVisible = false" />
          <PButton type="submit" icon="pi pi-save" label="Save" :loading="saving" />
        </div>
      </form>
    </PDialog>
  </section>
</template>

<script setup>
import { computed, onMounted, reactive, ref, watch } from 'vue'
import MetricCard from '../components/MetricCard.vue'
import { currencyCode, formatCurrency, formatNumber } from '../lib/formatters'
import {
  createProduct,
  deleteProduct,
  fetchProductManagement,
  saveProductBrand,
  saveProductCategory,
  saveProductUnit,
  updateProduct,
} from '../services/productService'
import { useAuthStore } from '../stores/authStore'

const auth = useAuthStore()
const loading = ref(false)
const saving = ref(false)
const error = ref('')
const successMessage = ref('')
const search = ref('')
const categoryFilter = ref('')
const taxFilter = ref('')
const productData = ref(null)
const productDialogVisible = ref(false)
const referenceDialogVisible = ref(false)
const editingProduct = ref(null)
const editingReference = ref(null)
const referenceMode = ref('category')
const productFormError = ref('')
const referenceFormError = ref('')
const productErrors = reactive({})
const referenceErrors = reactive({})
const productForm = reactive(createDefaultProductForm())
const referenceForm = reactive(createDefaultReferenceForm())

const taxTypeOptions = [
  { label: 'VATable 12%', value: 'vatable' },
  { label: 'VAT-exempt', value: 'vat_exempt' },
  { label: 'Zero-rated', value: 'zero_rated' },
  { label: 'Non-VAT', value: 'non_vat' },
]

const taxFilterOptions = [{ label: 'All tax types', value: '' }, ...taxTypeOptions]

const unitTypeOptions = [
  { label: 'Piece', value: 'piece' },
  { label: 'Pack', value: 'pack' },
  { label: 'Box', value: 'box' },
  { label: 'Weight', value: 'weight' },
  { label: 'Volume', value: 'volume' },
  { label: 'Service', value: 'service' },
]

const categoryOptions = computed(() => optionRows(productData.value?.categories || []))
const brandOptions = computed(() => optionRows(productData.value?.brands || []))
const unitOptions = computed(() =>
  (productData.value?.units || []).map((unit) => ({
    label: `${unit.name} (${unit.abbreviation})${unit.is_active ? '' : ' - inactive'}`,
    value: unit.id,
  })),
)

const categoryFilterOptions = computed(() => [
  { label: 'All categories', value: '' },
  ...(productData.value?.categories || []).map((category) => ({
    label: category.name,
    value: category.id,
  })),
])

const filteredProducts = computed(() => {
  const query = search.value.toLowerCase()
  const rows = productData.value?.products || []

  return rows.filter((product) => {
    const matchesSearch =
      !query ||
      [
        product.name,
        product.sku,
        product.barcode,
        product.category_name,
        product.category,
        product.brand_name,
        product.unit_name,
        ...(product.variants || []).flatMap((variant) => [variant.variant_name, variant.sku, variant.barcode]),
      ]
        .filter(Boolean)
        .some((value) => value.toLowerCase().includes(query))

    const matchesCategory = !categoryFilter.value || product.category_id === categoryFilter.value
    const matchesTax = !taxFilter.value || product.tax_type === taxFilter.value

    return matchesSearch && matchesCategory && matchesTax
  })
})

const referenceDialogTitle = computed(() => {
  const action = editingReference.value ? 'Edit' : 'Add'
  const label = referenceLabels[referenceMode.value] || 'reference'

  return `${action} ${label}`
})

watch(
  () => productForm.tax_type,
  (taxType) => {
    if (taxType === 'vatable' && Number(productForm.vat_rate || 0) === 0) {
      productForm.vat_rate = 12
    }

    if (taxType !== 'vatable') {
      productForm.vat_rate = 0
    }
  },
)

const referenceLabels = {
  category: 'category',
  brand: 'brand',
  unit: 'unit',
}

function optionRows(rows) {
  return rows.map((row) => ({
    label: `${row.name}${row.is_active ? '' : ' - inactive'}`,
    value: row.id,
  }))
}

function createDefaultProductForm() {
  return {
    sku: '',
    barcode: '',
    name: '',
    description: '',
    category_id: null,
    brand_id: null,
    unit_id: null,
    cost_price: 0,
    selling_price: 0,
    tax_type: 'vatable',
    vat_rate: 12,
    tax_inclusive: true,
    reorder_level: 0,
    is_active: true,
    variants: [],
  }
}

function createDefaultReferenceForm() {
  return {
    code: '',
    name: '',
    description: '',
    abbreviation: '',
    unit_type: 'piece',
    allows_decimal: false,
    is_active: true,
  }
}

function clearProductFeedback() {
  productFormError.value = ''
  Object.keys(productErrors).forEach((key) => {
    delete productErrors[key]
  })
}

function clearReferenceFeedback() {
  referenceFormError.value = ''
  Object.keys(referenceErrors).forEach((key) => {
    delete referenceErrors[key]
  })
}

function clearProductField(key) {
  if (productErrors[key]) {
    delete productErrors[key]
  }

  if (Object.keys(productErrors).length === 0) {
    productFormError.value = ''
  }
}

function clearReferenceField(key) {
  if (referenceErrors[key]) {
    delete referenceErrors[key]
  }

  if (Object.keys(referenceErrors).length === 0) {
    referenceFormError.value = ''
  }
}

function resetProductForm(payload = {}) {
  const nextForm = createDefaultProductForm()
  Object.assign(productForm, nextForm, payload)
  productForm.variants = (payload.variants || []).map((variant) => normalizeVariant(variant))
}

function resetReferenceForm(payload = {}) {
  Object.assign(referenceForm, createDefaultReferenceForm(), payload)
}

function normalizeVariant(variant = {}) {
  return {
    id: variant.id || null,
    local_key: variant.id || crypto.randomUUID(),
    variant_name: variant.variant_name || '',
    sku: variant.sku || '',
    barcode: variant.barcode || '',
    unit_id: variant.unit_id || productForm.unit_id || null,
    cost_price: Number(variant.cost_price || 0),
    selling_price: Number(variant.selling_price || 0),
    is_active: variant.is_active !== false,
  }
}

function productToForm(product) {
  return {
    sku: product.sku,
    barcode: product.barcode,
    name: product.name,
    description: product.description || '',
    category_id: product.category_id,
    brand_id: product.brand_id,
    unit_id: product.unit_id,
    cost_price: Number(product.cost_price || 0),
    selling_price: Number(product.selling_price || 0),
    tax_type: product.tax_type || 'vatable',
    vat_rate: Number(product.vat_rate || 0),
    tax_inclusive: product.tax_inclusive !== false,
    reorder_level: Number(product.reorder_level || 0),
    is_active: product.is_active !== false,
    variants: product.variants || [],
  }
}

function defaultReferenceIds() {
  return {
    category_id: activeFirst(productData.value?.categories)?.id || null,
    brand_id: activeFirst(productData.value?.brands)?.id || null,
    unit_id: activeFirst(productData.value?.units)?.id || null,
  }
}

function activeFirst(rows = []) {
  return rows.find((row) => row.is_active) || rows[0]
}

function validateProductForm() {
  const errors = {}

  if (!productForm.sku?.trim()) errors.sku = 'SKU is required.'
  if (!productForm.barcode?.trim()) errors.barcode = 'Barcode is required.'
  if (!productForm.name?.trim()) errors.name = 'Product name is required.'
  if (!productForm.category_id) errors.category_id = 'Category is required.'
  if (!productForm.brand_id) errors.brand_id = 'Brand is required.'
  if (!productForm.unit_id) errors.unit_id = 'Unit is required.'
  if (Number(productForm.selling_price || 0) < 0) errors.selling_price = 'Selling price cannot be negative.'

  const invalidVariant = productForm.variants.some((variant) => {
    const hasAnyValue = [variant.variant_name, variant.sku, variant.barcode].some((value) => String(value || '').trim())

    return hasAnyValue && (!variant.variant_name?.trim() || !variant.sku?.trim())
  })

  if (invalidVariant) {
    errors.variants = 'Each variant row must have both a variant name and SKU.'
  }

  if (Object.keys(errors).length) {
    clearProductFeedback()
    Object.assign(productErrors, errors)
    productFormError.value = 'Please fix the highlighted product fields.'
    return false
  }

  clearProductFeedback()
  return true
}

function validateReferenceForm() {
  const errors = {}

  if (!referenceForm.name?.trim()) {
    errors.name = 'Name is required.'
  }

  if (referenceMode.value === 'unit' && !referenceForm.abbreviation?.trim()) {
    errors.abbreviation = 'Abbreviation is required.'
  }

  if (Object.keys(errors).length) {
    clearReferenceFeedback()
    Object.assign(referenceErrors, errors)
    referenceFormError.value = 'Please fix the highlighted fields.'
    return false
  }

  clearReferenceFeedback()
  return true
}

function productPayload() {
  return {
    sku: productForm.sku.trim().toUpperCase(),
    barcode: productForm.barcode.trim(),
    name: productForm.name.trim(),
    description: productForm.description?.trim() || '',
    category_id: productForm.category_id,
    brand_id: productForm.brand_id,
    unit_id: productForm.unit_id,
    cost_price: Number(productForm.cost_price || 0),
    selling_price: Number(productForm.selling_price || 0),
    tax_type: productForm.tax_type,
    vat_rate: Number(productForm.vat_rate || 0),
    tax_inclusive: Boolean(productForm.tax_inclusive),
    reorder_level: Number(productForm.reorder_level || 0),
    is_active: Boolean(productForm.is_active),
    variants: productForm.variants
      .filter((variant) => [variant.variant_name, variant.sku, variant.barcode].some((value) => String(value || '').trim()))
      .map((variant) => ({
        id: variant.id,
        variant_name: variant.variant_name.trim(),
        sku: variant.sku.trim().toUpperCase(),
        barcode: variant.barcode?.trim() || '',
        unit_id: variant.unit_id || productForm.unit_id,
        cost_price: Number(variant.cost_price || 0),
        selling_price: Number(variant.selling_price || 0),
        is_active: Boolean(variant.is_active),
      })),
  }
}

async function loadProducts() {
  loading.value = true
  error.value = ''
  successMessage.value = ''

  try {
    productData.value = await fetchProductManagement()
  } catch (loadError) {
    error.value = loadError.message
  } finally {
    loading.value = false
  }
}

function openProductCreate() {
  editingProduct.value = null
  clearProductFeedback()
  resetProductForm(defaultReferenceIds())
  productDialogVisible.value = true
}

function openProductEdit(product) {
  editingProduct.value = product
  clearProductFeedback()
  resetProductForm(productToForm(product))
  productDialogVisible.value = true
}

function addVariant() {
  productForm.variants.push(
    normalizeVariant({
      unit_id: productForm.unit_id,
      cost_price: productForm.cost_price,
      selling_price: productForm.selling_price,
      is_active: true,
    }),
  )
}

function removeVariant(index) {
  productForm.variants.splice(index, 1)
  clearProductField('variants')
}

async function saveProduct() {
  saving.value = true
  error.value = ''
  successMessage.value = ''

  try {
    if (!validateProductForm()) return

    if (editingProduct.value) {
      productData.value = await updateProduct(editingProduct.value.id, productPayload())
      successMessage.value = 'Product was updated.'
    } else {
      productData.value = await createProduct(productPayload())
      successMessage.value = 'Product was created.'
    }

    productDialogVisible.value = false
  } catch (saveError) {
    productFormError.value = saveError.message
  } finally {
    saving.value = false
  }
}

async function deleteProductRow(product) {
  const confirmed = window.confirm(`Delete ${product.name}? Existing sales and inventory history stay linked, but the product is hidden from active catalog lists.`)
  if (!confirmed) return

  loading.value = true
  error.value = ''
  successMessage.value = ''

  try {
    productData.value = await deleteProduct(product.id)
    successMessage.value = `${product.name} was deleted from the active catalog.`
  } catch (deleteError) {
    error.value = deleteError.message
  } finally {
    loading.value = false
  }
}

function openReferenceCreate(mode) {
  referenceMode.value = mode
  editingReference.value = null
  clearReferenceFeedback()
  resetReferenceForm()
  referenceDialogVisible.value = true
}

function openReferenceEdit(mode, row) {
  referenceMode.value = mode
  editingReference.value = row
  clearReferenceFeedback()
  resetReferenceForm({
    code: row.code,
    name: row.name,
    description: row.description || '',
    abbreviation: row.abbreviation || '',
    unit_type: row.unit_type || 'piece',
    allows_decimal: Boolean(row.allows_decimal),
    is_active: row.is_active !== false,
  })
  referenceDialogVisible.value = true
}

async function saveReference() {
  saving.value = true
  error.value = ''
  successMessage.value = ''

  try {
    if (!validateReferenceForm()) return

    const payload = {
      code: referenceForm.code.trim().toUpperCase(),
      name: referenceForm.name.trim(),
      description: referenceForm.description?.trim() || '',
      abbreviation: referenceForm.abbreviation?.trim() || '',
      unit_type: referenceForm.unit_type,
      allows_decimal: Boolean(referenceForm.allows_decimal),
      is_active: Boolean(referenceForm.is_active),
    }

    if (referenceMode.value === 'category') {
      productData.value = await saveProductCategory(editingReference.value?.id || null, payload)
    } else if (referenceMode.value === 'brand') {
      productData.value = await saveProductBrand(editingReference.value?.id || null, payload)
    } else {
      productData.value = await saveProductUnit(editingReference.value?.id || null, payload)
    }

    successMessage.value = `${referenceLabels[referenceMode.value]} was saved.`
    referenceDialogVisible.value = false
  } catch (saveError) {
    referenceFormError.value = saveError.message
  } finally {
    saving.value = false
  }
}

function taxLabel(value) {
  return taxTypeOptions.find((option) => option.value === value)?.label || value
}

function taxSeverity(value) {
  if (value === 'vatable') return 'success'
  if (value === 'vat_exempt') return 'info'
  if (value === 'zero_rated') return 'warn'

  return 'secondary'
}

onMounted(loadProducts)
</script>
