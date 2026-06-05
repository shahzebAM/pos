<template>
  <section class="panel chart-panel">
    <div class="panel__header">
      <div>
        <p class="eyebrow">Daily sales summary</p>
        <h2>Sales trend</h2>
      </div>
      <span class="panel__caption">{{ rows.length }} day view</span>
    </div>

    <div v-if="rows.length" class="line-chart">
      <svg viewBox="0 0 720 260" role="img" aria-label="Daily sales line chart">
        <defs>
          <linearGradient id="salesArea" x1="0" x2="0" y1="0" y2="1">
            <stop offset="0%" stop-color="#0f8f6f" stop-opacity="0.28" />
            <stop offset="100%" stop-color="#0f8f6f" stop-opacity="0.02" />
          </linearGradient>
        </defs>
        <path class="line-chart__grid" d="M48 40 H690 M48 94 H690 M48 148 H690 M48 202 H690" />
        <path class="line-chart__area" :d="areaPath" />
        <path class="line-chart__line" :d="linePath" />
        <g v-for="point in points" :key="point.label">
          <circle :cx="point.x" :cy="point.y" r="5" />
        </g>
      </svg>

      <div class="line-chart__footer">
        <span>{{ firstLabel }}</span>
        <strong>{{ formatCurrency(totalSales) }}</strong>
        <span>{{ lastLabel }}</span>
      </div>
    </div>

    <div v-else class="empty-state">
      <i class="pi pi-chart-line" />
      <p>No sales trend yet.</p>
    </div>
  </section>
</template>

<script setup>
import { computed } from 'vue'
import { formatCurrency } from '../lib/formatters'

const props = defineProps({
  rows: {
    type: Array,
    default: () => [],
  },
})

const points = computed(() => {
  const max = Math.max(...props.rows.map((row) => Number(row.sales || 0)), 1)
  const width = 642
  const height = 176
  const startX = 48
  const startY = 40
  const denominator = Math.max(props.rows.length - 1, 1)

  return props.rows.map((row, index) => {
    const x = startX + (index / denominator) * width
    const y = startY + height - (Number(row.sales || 0) / max) * height

    return {
      x,
      y,
      label: row.label,
      sales: Number(row.sales || 0),
    }
  })
})

const linePath = computed(() => {
  if (!points.value.length) return ''

  return points.value.map((point, index) => `${index === 0 ? 'M' : 'L'} ${point.x} ${point.y}`).join(' ')
})

const areaPath = computed(() => {
  if (!points.value.length) return ''

  const first = points.value[0]
  const last = points.value[points.value.length - 1]

  return `${linePath.value} L ${last.x} 216 L ${first.x} 216 Z`
})

const totalSales = computed(() => props.rows.reduce((total, row) => total + Number(row.sales || 0), 0))
const firstLabel = computed(() => props.rows[0]?.label || '')
const lastLabel = computed(() => props.rows[props.rows.length - 1]?.label || '')
</script>
