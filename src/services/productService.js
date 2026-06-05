import { requireSupabaseConfig } from '../lib/supabase'

const emptyProductData = {
  summary: {
    total_products: 0,
    active_products: 0,
    categories: 0,
    brands: 0,
    units: 0,
    vatable_items: 0,
    vat_exempt_items: 0,
    zero_rated_items: 0,
    non_vat_items: 0,
  },
  products: [],
  categories: [],
  brands: [],
  units: [],
  generated_at: null,
}

function moduleInstallMessage(error) {
  const message = error?.message || ''

  if (
    message.includes('product_management_get') ||
    message.includes('product_create') ||
    message.includes('schema cache') ||
    message.includes('Could not find the function')
  ) {
    return 'Product Management module is not installed yet. Run supabase/04-product-management.sql after Module 3.'
  }

  return message || 'Unable to load product management data.'
}

function numberValue(value) {
  return Number(value || 0)
}

function arrayValue(value) {
  return Array.isArray(value) ? value : []
}

function normalizeProductData(payload) {
  const data = payload || emptyProductData

  return {
    ...emptyProductData,
    ...data,
    summary: {
      total_products: numberValue(data.summary?.total_products),
      active_products: numberValue(data.summary?.active_products),
      categories: numberValue(data.summary?.categories),
      brands: numberValue(data.summary?.brands),
      units: numberValue(data.summary?.units),
      vatable_items: numberValue(data.summary?.vatable_items),
      vat_exempt_items: numberValue(data.summary?.vat_exempt_items),
      zero_rated_items: numberValue(data.summary?.zero_rated_items),
      non_vat_items: numberValue(data.summary?.non_vat_items),
    },
    products: arrayValue(data.products).map((product) => ({
      ...product,
      cost_price: numberValue(product.cost_price),
      selling_price: numberValue(product.selling_price),
      vat_rate: numberValue(product.vat_rate),
      reorder_level: numberValue(product.reorder_level),
      stock_units: numberValue(product.stock_units),
      variant_count: numberValue(product.variant_count),
      variants: arrayValue(product.variants).map((variant) => ({
        ...variant,
        cost_price: numberValue(variant.cost_price),
        selling_price: numberValue(variant.selling_price),
      })),
    })),
    categories: arrayValue(data.categories),
    brands: arrayValue(data.brands),
    units: arrayValue(data.units),
  }
}

async function callProductRpc(name, args = {}) {
  const client = requireSupabaseConfig()
  const { data, error } = await client.rpc(name, args)

  if (error) {
    throw new Error(moduleInstallMessage(error))
  }

  return normalizeProductData(data)
}

export function fetchProductManagement() {
  return callProductRpc('product_management_get')
}

export function createProduct(payload) {
  return callProductRpc('product_create', {
    p_payload: payload,
  })
}

export function updateProduct(productId, payload) {
  return callProductRpc('product_update', {
    p_product_id: productId,
    p_payload: payload,
  })
}

export function deleteProduct(productId) {
  return callProductRpc('product_delete', {
    p_product_id: productId,
  })
}

export function saveProductCategory(categoryId, payload) {
  return callProductRpc('product_category_save', {
    p_category_id: categoryId,
    p_payload: payload,
  })
}

export function saveProductBrand(brandId, payload) {
  return callProductRpc('product_brand_save', {
    p_brand_id: brandId,
    p_payload: payload,
  })
}

export function saveProductUnit(unitId, payload) {
  return callProductRpc('product_unit_save', {
    p_unit_id: unitId,
    p_payload: payload,
  })
}
