import { createApp } from 'vue'
import PrimeVue from 'primevue/config'
import Aura from '@primeuix/themes/aura'
import Badge from 'primevue/badge'
import Button from 'primevue/button'
import Card from 'primevue/card'
import Checkbox from 'primevue/checkbox'
import Column from 'primevue/column'
import DataTable from 'primevue/datatable'
import DatePicker from 'primevue/datepicker'
import Dialog from 'primevue/dialog'
import InputNumber from 'primevue/inputnumber'
import InputText from 'primevue/inputtext'
import Message from 'primevue/message'
import Select from 'primevue/select'
import Skeleton from 'primevue/skeleton'
import Tag from 'primevue/tag'
import Textarea from 'primevue/textarea'
import App from './App.vue'
import router from './router'
import 'primeicons/primeicons.css'
import './assets/styles.css'
import './registerServiceWorker'

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

app.component('PBadge', Badge)
app.component('PButton', Button)
app.component('PCard', Card)
app.component('PCheckbox', Checkbox)
app.component('PColumn', Column)
app.component('PDataTable', DataTable)
app.component('PDatePicker', DatePicker)
app.component('PDialog', Dialog)
app.component('PInputNumber', InputNumber)
app.component('PInputText', InputText)
app.component('PMessage', Message)
app.component('PSelect', Select)
app.component('PSkeleton', Skeleton)
app.component('PTag', Tag)
app.component('PTextarea', Textarea)

app.mount('#app')
