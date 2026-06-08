<template>
  <RouterView v-slot="{ Component, route }">
    <component :is="Component" v-if="route.meta.public" />
    <AppLayout v-else>
      <KeepAlive :max="10">
        <component :is="Component" :key="route.name" />
      </KeepAlive>
    </AppLayout>
  </RouterView>
</template>

<script setup>
import { defineAsyncComponent } from 'vue'
import { RouterView } from 'vue-router'

const AppLayout = defineAsyncComponent(() => import('./components/AppLayout.vue'))
</script>
