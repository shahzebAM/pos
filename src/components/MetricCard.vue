<template>
  <section class="metric-card" :class="`metric-card--${tone}`">
    <div class="metric-card__icon">
      <i :class="icon" />
    </div>
    <div class="metric-card__body">
      <span class="metric-card__label">{{ label }}</span>
      <strong>{{ value }}</strong>
      <small v-if="caption">{{ caption }}</small>
    </div>
  </section>
</template>

<script setup>
defineProps({
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
</script>
