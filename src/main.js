import { createApp, defineAsyncComponent } from 'vue'
import PrimeVue from 'primevue/config'
import Aura from '@primeuix/themes/aura'
import App from './App.vue'
import router from './router'
import 'primeicons/primeicons.css'
import './assets/styles.css'

const registerPwaWhenIdle = () => {
  if (typeof window === 'undefined') return

  const register = () => import('./registerServiceWorker')

  if ('requestIdleCallback' in window) {
    window.requestIdleCallback(register, { timeout: 3000 })
    return
  }

  window.setTimeout(register, 1200)
}

const app = createApp(App)

app.use(PrimeVue, {
  ripple: true,
  theme: {
    preset: Aura,
    options: {
      darkModeSelector: false,
      cssLayer: false,
    },
  },
})

app.use(router)

const primeAsync = (loader) =>
  defineAsyncComponent({
    loader,
    delay: 0,
  })

app.component('PBadge', primeAsync(() => import('primevue/badge')))
app.component('PButton', primeAsync(() => import('primevue/button')))
app.component('PCard', primeAsync(() => import('primevue/card')))
app.component('PCheckbox', primeAsync(() => import('primevue/checkbox')))
app.component('PColumn', primeAsync(() => import('primevue/column')))
app.component('PDataTable', primeAsync(() => import('primevue/datatable')))
app.component('PDatePicker', primeAsync(() => import('primevue/datepicker')))
app.component('PDialog', primeAsync(() => import('primevue/dialog')))
app.component('PInputNumber', primeAsync(() => import('primevue/inputnumber')))
app.component('PInputText', primeAsync(() => import('primevue/inputtext')))
app.component('PMessage', primeAsync(() => import('primevue/message')))
app.component('PSelect', primeAsync(() => import('primevue/select')))
app.component('PSkeleton', primeAsync(() => import('primevue/skeleton')))
app.component('PTag', primeAsync(() => import('primevue/tag')))
app.component('PTextarea', primeAsync(() => import('primevue/textarea')))

app.mount('#app')
registerPwaWhenIdle()
