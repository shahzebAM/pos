<template>
  <section class="panel chart-panel">
    <div class="panel__header">
      <div>
        <p class="eyebrow">{{ eyebrow }}</p>
        <h2>{{ title }}</h2>
      </div>
      <span v-if="caption" class="panel__caption">{{ caption }}</span>
    </div>

    <div v-if="rows.length" class="bar-chart">
      <article v-for="row in chartRows" :key="row[keyField] || row[labelField]" class="bar-chart__row">
        <div class="bar-chart__meta">
          <span>{{ row[labelField] }}</span>
          <strong>{{ money ? formatCurrency(row[valueField]) : formatNumber(row[valueField]) }}</strong>
        </div>
        <div class="bar-chart__track" aria-hidden="true">
          <span :style="{ width: `${row.percent}%`, background: row.color }" />
        </div>
      </article>
    </div>

    <div v-else class="empty-state">
      <i class="pi pi-chart-bar" />
      <p>No data for this period.</p>
    </div>
  </section>
</template>

<script setup>
import { computed } from 'vue'
import { formatCurrency, formatNumber } from '../lib/formatters'

const palette = ['#0f8f6f', '#1f6f8b', '#c48a18', '#7c5cc4', '#d45d4f', '#2f8c54']

const props = defineProps({
  eyebrow: {
    type: String,
    default: 'Analytics',
  },
  title: {
    type: String,
    required: true,
  },
  caption: {
    type: String,
    default: '',
  },
  rows: {
    type: Array,
    default: () => [],
  },
  labelField: {
    type: String,
    default: 'label',
  },
  valueField: {
    type: String,
    default: 'sales',
  },
  keyField: {
    type: String,
    default: 'id',
  },
  money: {
    type: Boolean,
    default: true,
  },
})

const chartRows = computed(() => {
  const max = Math.max(...props.rows.map((row) => Number(row[props.valueField] || 0)), 1)

  return props.rows.map((row, index) => ({
    ...row,
    percent: Math.max(4, (Number(row[props.valueField] || 0) / max) * 100),
    color: palette[index % palette.length],
  }))
})
</script>
