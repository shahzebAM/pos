import { registerSW } from 'virtual:pwa-register'

let refreshServiceWorker = () => {}

refreshServiceWorker = registerSW({
  immediate: true,
  onNeedRefresh() {
    refreshServiceWorker(true)
  },
  onOfflineReady() {
    window.dispatchEvent(new CustomEvent('pos:pwa-offline-ready'))
  },
})
