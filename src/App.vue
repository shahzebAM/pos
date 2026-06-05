<template>
  <RouterView v-slot="{ Component, route }">
    <component :is="Component" v-if="route.meta.public" />
    <AppLayout v-else>
      <component :is="Component" />
    </AppLayout>
  </RouterView>
</template>

<script setup>
import { RouterView } from 'vue-router'
import AppLayout from './components/AppLayout.vue'
</script>
