import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import { VitePWA } from 'vite-plugin-pwa'

export default defineConfig({
  plugins: [
    vue(),
    VitePWA({
      registerType: 'autoUpdate',
      injectRegister: false,
      includeAssets: ['pwa-192x192.png', 'pwa-512x512.png', 'pwa-maskable-512x512.png'],
      manifest: {
        name: 'Multi-Branch POS',
        short_name: 'POS',
        description: 'Retail sales, inventory, branches, cash drawer, reports, and audit control.',
        id: '/',
        theme_color: '#0f8f6f',
        background_color: '#f5faf7',
        display: 'standalone',
        display_override: ['standalone', 'minimal-ui'],
        orientation: 'portrait-primary',
        scope: '/',
        start_url: '/',
        categories: ['business', 'finance', 'productivity'],
        icons: [
          {
            src: '/pwa-192x192.png',
            sizes: '192x192',
            type: 'image/png',
          },
          {
            src: '/pwa-512x512.png',
            sizes: '512x512',
            type: 'image/png',
          },
          {
            src: '/pwa-maskable-512x512.png',
            sizes: '512x512',
            type: 'image/png',
            purpose: 'maskable',
          },
        ],
      },
      workbox: {
        cleanupOutdatedCaches: true,
        navigateFallback: '/index.html',
        globPatterns: ['**/*.{js,css,html,ico,png,svg,woff,woff2,ttf,eot}'],
        runtimeCaching: [
          {
            urlPattern: ({ request, sameOrigin }) => sameOrigin && request.destination === 'font',
            handler: 'CacheFirst',
            options: {
              cacheName: 'pos-fonts',
              expiration: {
                maxEntries: 20,
                maxAgeSeconds: 60 * 60 * 24 * 365,
              },
            },
          },
        ],
      },
      devOptions: {
        enabled: true,
        type: 'module',
        navigateFallback: 'index.html',
      },
    }),
  ],
  build: {
    sourcemap: true,
    chunkSizeWarningLimit: 1000,
    rollupOptions: {
      output: {
        manualChunks(id) {
          const normalizedId = id.replaceAll('\\', '/')

          if (!normalizedId.includes('node_modules')) {
            return undefined
          }

          if (normalizedId.includes('/node_modules/@supabase/')) {
            return 'vendor-supabase'
          }

          if (normalizedId.includes('/node_modules/vue/') || normalizedId.includes('/node_modules/@vue/')) {
            return 'vendor-vue'
          }

          if (
            normalizedId.includes('/node_modules/primevue/') ||
            normalizedId.includes('/node_modules/@primeuix/') ||
            normalizedId.includes('/node_modules/primeicons/')
          ) {
            return undefined
          }

          return 'vendor'
        },
      },
    },
  },
})
