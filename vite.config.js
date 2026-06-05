import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

export default defineConfig({
  plugins: [vue()],
  build: {
    sourcemap: true,
    chunkSizeWarningLimit: 1000,
    rollupOptions: {
      output: {
        manualChunks(id) {
          if (!id.includes('node_modules')) {
            return undefined
          }

          if (id.includes('primevue') || id.includes('@primeuix') || id.includes('primeicons')) {
            return 'vendor-primevue'
          }

          if (id.includes('@supabase')) {
            return 'vendor-supabase'
          }

          if (id.includes('vue') || id.includes('@vue')) {
            return 'vendor-vue'
          }

          return 'vendor'
        },
      },
    },
  },
})
