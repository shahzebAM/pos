<template>
  <section class="metric-card" :class="`metric-card--${tone}`">
    <div class="metric-card__icon">
      <i :class="icon" />
    </div>
    <div class="metric-card__body">
      <span class="metric-card__label">{{ label }}</span>
      <strong :class="valueSizeClass" :title="value">{{ value }}</strong>
      <small v-if="caption">{{ caption }}</small>
    </div>
  </section>
</template>

<script setup>
import { computed } from 'vue'

const props = defineProps({
  label: {
    type: String,
    required: true,
  },
  value: {
    type: String,
    required: true,
  },
  caption: {
    type: String,
    default: '',
  },
  icon: {
    type: String,
    default: 'pi pi-chart-line',
  },
  tone: {
    type: String,
    default: 'green',
  },
})

const valueSizeClass = computed(() => {
  const length = String(props.value || '').replace(/\s/g, '').length

  if (length >= 18) return 'metric-card__value--very-long'
  if (length >= 13) return 'metric-card__value--long'
  return ''
})
</script>
