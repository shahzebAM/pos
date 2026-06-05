import { requireSupabaseConfig } from '../lib/supabase'

const emptyInventoryData = {
  summary: {
    stock_units: 0,
    inventory_value: 0,
    low_stock_items: 0,
    out_of_stock_items: 0,
    active_batches: 0,
    expiring_soon_batches: 0,
    expired_batches: 0,
    movements: 0,
  },
  branches: [],
  products: [],
  inventory: [],
  batches: [],
  expiry_alerts: [],
  movements: [],
  stock_counts: [],
  generated_at: null,
}

function moduleInstallMessage(error) {
  const message = error?.message || ''

  if (
    message.includes('inventory_management_get') ||
    message.includes('inventory_adjust') ||
    message.includes('inventory_post_stock_count') ||
    message.includes('schema cache') ||
    message.includes('Could not find the function')
  ) {
    return 'Inventory Management module is not installed yet. Run supabase/05-inventory-management.sql after Module 4.'
  }

  return message || 'Unable to load inventory management data.'
}

function numberValue(value) {
  return Number(value || 0)
}

function arrayValue(value) {
  return Array.isArray(value) ? value : []
}

function normalizeInventoryData(payload) {
  const data = payload || emptyInventoryData

  return {
    ...emptyInventoryData,
    ...data,
    summary: {
      stock_units: numberValue(data.summary?.stock_units),
      inventory_value: numberValue(data.summary?.inventory_value),
      low_stock_items: numberValue(data.summary?.low_stock_items),
      out_of_stock_items: numberValue(data.summary?.out_of_stock_items),
      active_batches: numberValue(data.summary?.active_batches),
      expiring_soon_batches: numberValue(data.summary?.expiring_soon_batches),
      expired_batches: numberValue(data.summary?.expired_batches),
      movements: numberValue(data.summary?.movements),
    },
    branches: arrayValue(data.branches),
    products: arrayValue(data.products).map((product) => ({
      ...product,
      cost_price: numberValue(product.cost_price),
      selling_price: numberValue(product.selling_price),
      reorder_level: numberValue(product.reorder_level),
      variants: arrayValue(product.variants).map((variant) => ({
        ...variant,
        cost_price: numberValue(variant.cost_price),
        selling_price: numberValue(variant.selling_price),
      })),
    })),
    inventory: arrayValue(data.inventory).map((row) => ({
      ...row,
      quantity_on_hand: numberValue(row.quantity_on_hand),
      reorder_level: numberValue(row.reorder_level),
      cost_price: numberValue(row.cost_price),
      selling_price: numberValue(row.selling_price),
      inventory_value: numberValue(row.inventory_value),
      batch_count: numberValue(row.batch_count),
      expiring_soon_batches: numberValue(row.expiring_soon_batches),
      expired_batches: numberValue(row.expired_batches),
    })),
    batches: arrayValue(data.batches).map((batch) => ({
      ...batch,
      quantity_on_hand: numberValue(batch.quantity_on_hand),
      unit_cost: numberValue(batch.unit_cost),
    })),
    expiry_alerts: arrayValue(data.expiry_alerts).map((batch) => ({
      ...batch,
      quantity_on_hand: numberValue(batch.quantity_on_hand),
      unit_cost: numberValue(batch.unit_cost),
    })),
    movements: arrayValue(data.movements).map((movement) => ({
      ...movement,
      quantity_delta: numberValue(movement.quantity_delta),
      quantity_before: numberValue(movement.quantity_before),
      quantity_after: numberValue(movement.quantity_after),
      unit_cost: numberValue(movement.unit_cost),
    })),
    stock_counts: arrayValue(data.stock_counts).map((count) => ({
      ...count,
      item_count: numberValue(count.item_count),
      total_variance: numberValue(count.total_variance),
    })),
  }
}

async function callInventoryRpc(name, args = {}) {
  const client = requireSupabaseConfig()
  const { data, error } = await client.rpc(name, args)

  if (error) {
    throw new Error(moduleInstallMessage(error))
  }

  return normalizeInventoryData(data)
}

export function fetchInventoryManagement(branchId = null) {
  return callInventoryRpc('inventory_management_get', {
    p_branch_id: branchId || null,
  })
}

export function adjustInventory(payload) {
  return callInventoryRpc('inventory_adjust', {
    p_payload: payload,
  })
}

export function postStockCount(payload) {
  return callInventoryRpc('inventory_post_stock_count', {
    p_payload: payload,
  })
}
