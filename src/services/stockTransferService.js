import { requireSupabaseConfig } from '../lib/supabase'

const emptyStockTransferData = {
  summary: {
    total_transfers: 0,
    requested: 0,
    approved: 0,
    dispatched: 0,
    received: 0,
    variance_units: 0,
  },
  branches: [],
  products: [],
  inventory: [],
  batches: [],
  transfers: [],
  generated_at: null,
}

function moduleInstallMessage(error) {
  const message = error?.message || ''

  if (
    message.includes('stock_transfer_management_get') ||
    message.includes('stock_transfer_create') ||
    message.includes('stock_transfers') ||
    message.includes('schema cache') ||
    message.includes('Could not find the function')
  ) {
    return 'Stock Transfer module is not installed yet. Run supabase/06-stock-transfer.sql after Module 5.'
  }

  return message || 'Unable to load stock transfer data.'
}

function numberValue(value) {
  return Number(value || 0)
}

function arrayValue(value) {
  return Array.isArray(value) ? value : []
}

function normalizeStockTransferData(payload) {
  const data = payload || emptyStockTransferData

  return {
    ...emptyStockTransferData,
    ...data,
    summary: {
      total_transfers: numberValue(data.summary?.total_transfers),
      requested: numberValue(data.summary?.requested),
      approved: numberValue(data.summary?.approved),
      dispatched: numberValue(data.summary?.dispatched),
      received: numberValue(data.summary?.received),
      variance_units: numberValue(data.summary?.variance_units),
    },
    branches: arrayValue(data.branches),
    products: arrayValue(data.products).map((product) => ({
      ...product,
      cost_price: numberValue(product.cost_price),
      selling_price: numberValue(product.selling_price),
      variants: arrayValue(product.variants).map((variant) => ({
        ...variant,
        cost_price: numberValue(variant.cost_price),
        selling_price: numberValue(variant.selling_price),
      })),
    })),
    inventory: arrayValue(data.inventory).map((row) => ({
      ...row,
      quantity_on_hand: numberValue(row.quantity_on_hand),
    })),
    batches: arrayValue(data.batches).map((batch) => ({
      ...batch,
      quantity_on_hand: numberValue(batch.quantity_on_hand),
      unit_cost: numberValue(batch.unit_cost),
    })),
    transfers: arrayValue(data.transfers).map((transfer) => ({
      ...transfer,
      total_requested: numberValue(transfer.total_requested),
      total_approved: numberValue(transfer.total_approved),
      total_dispatched: numberValue(transfer.total_dispatched),
      total_received: numberValue(transfer.total_received),
      total_variance: numberValue(transfer.total_variance),
      item_count: numberValue(transfer.item_count),
      items: arrayValue(transfer.items).map((item) => ({
        ...item,
        quantity_requested: numberValue(item.quantity_requested),
        quantity_approved: numberValue(item.quantity_approved),
        quantity_dispatched: numberValue(item.quantity_dispatched),
        quantity_received: numberValue(item.quantity_received),
        variance_quantity: numberValue(item.variance_quantity),
        available_stock: numberValue(item.available_stock),
        batches: arrayValue(item.batches).map((batch) => ({
          ...batch,
          quantity_dispatched: numberValue(batch.quantity_dispatched),
          quantity_received: numberValue(batch.quantity_received),
          unit_cost: numberValue(batch.unit_cost),
        })),
      })),
    })),
  }
}

async function callStockTransferRpc(name, args = {}) {
  const client = requireSupabaseConfig()
  const { data, error } = await client.rpc(name, args)

  if (error) {
    throw new Error(moduleInstallMessage(error))
  }

  return normalizeStockTransferData(data)
}

export function fetchStockTransferManagement(branchId = null) {
  return callStockTransferRpc('stock_transfer_management_get', {
    p_branch_id: branchId || null,
  })
}

export function createStockTransfer(payload) {
  return callStockTransferRpc('stock_transfer_create', {
    p_payload: payload,
  })
}

export function approveStockTransfer(transferId) {
  return callStockTransferRpc('stock_transfer_approve', {
    p_transfer_id: transferId,
  })
}

export function cancelStockTransfer(transferId, reason = '') {
  return callStockTransferRpc('stock_transfer_cancel', {
    p_transfer_id: transferId,
    p_reason: reason || null,
  })
}

export function dispatchStockTransfer(transferId) {
  return callStockTransferRpc('stock_transfer_dispatch', {
    p_transfer_id: transferId,
  })
}

export function receiveStockTransfer(transferId, payload) {
  return callStockTransferRpc('stock_transfer_receive', {
    p_transfer_id: transferId,
    p_payload: payload || {},
  })
}
