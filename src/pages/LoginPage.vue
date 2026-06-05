<template>
  <main class="login-shell">
    <section class="login-hero">
      <div class="brand-mark">POS</div>
      <p class="eyebrow">Secure access</p>
      <h1>Sign in to the POS back office.</h1>
      <p>
        Use your staff username and password. Admins create staff accounts from
        the User & Role Management module.
      </p>
    </section>

    <section class="login-card">
      <div class="panel__header">
        <div>
          <p class="eyebrow">{{ modeEyebrow }}</p>
          <h2>{{ modeTitle }}</h2>
        </div>
      </div>

      <PMessage v-if="message" :severity="messageSeverity" :closable="false" class="setup-message">
        {{ message }}
      </PMessage>

      <PMessage v-if="auth.state.error" severity="error" :closable="false" class="setup-message">
        {{ auth.state.error }}
      </PMessage>

      <form class="login-form" @submit.prevent="submit">
        <label v-if="isCreateMode">
          Full name
          <PInputText v-model.trim="form.fullName" autocomplete="name" fluid />
        </label>
        <label>
          Username
          <PInputText v-model.trim="form.username" autocomplete="username" fluid />
        </label>
        <label>
          Password
          <PInputText v-model="form.password" type="password" :autocomplete="isLoginMode ? 'current-password' : 'new-password'" fluid />
        </label>

        <PButton
          type="submit"
          :icon="submitIcon"
          :label="submitLabel"
          :loading="auth.state.loading"
        />
      </form>

      <div v-if="auth.state.session && auth.state.profile && !auth.state.profile.is_active" class="bootstrap-panel">
        <h3>Account inactive</h3>
        <p>Your login exists, but an admin must activate your staff profile before you can use the system.</p>
        <PButton icon="pi pi-sign-out" label="Sign out" severity="secondary" outlined @click="auth.signOut" />
      </div>

      <div class="login-links">
        <button class="text-button" type="button" @click="setMode('login')">Sign in</button>
        <button class="text-button" type="button" @click="setMode('firstAdmin')">Create first admin</button>
      </div>
    </section>
  </main>
</template>

<script setup>
import { computed, reactive, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useAuthStore } from '../stores/authStore'

const auth = useAuthStore()
const route = useRoute()
const router = useRouter()

const mode = ref('login')
const message = ref('')
const messageSeverity = ref('info')

const form = reactive({
  fullName: '',
  username: '',
  password: '',
})

const isLoginMode = computed(() => mode.value === 'login')
const isCreateMode = computed(() => mode.value === 'firstAdmin')
const redirectTo = computed(() => route.query.redirect?.toString() || '/dashboard')
const modeEyebrow = computed(() => (isCreateMode.value ? 'First admin' : 'Welcome back'))
const modeTitle = computed(() => (isCreateMode.value ? 'Create admin account' : 'Login'))
const submitIcon = computed(() => (isCreateMode.value ? 'pi pi-user-plus' : 'pi pi-lock-open'))
const submitLabel = computed(() => (isCreateMode.value ? 'Create first admin' : 'Sign in'))

function setMessage(text, severity = 'info') {
  message.value = text
  messageSeverity.value = severity
}

function setMode(nextMode) {
  mode.value = nextMode
  message.value = ''
}

function validateForm() {
  if (!form.username.trim()) return 'Username is required.'
  if (!form.password.trim()) return 'Password is required.'
  if (form.password.trim().length < 6) return 'Password must be at least 6 characters.'
  if (isCreateMode.value && !form.fullName.trim()) return 'Full name is required.'

  return ''
}

async function submit() {
  message.value = ''

  const validationError = validateForm()
  if (validationError) {
    setMessage(validationError, 'error')
    return
  }

  try {
    if (isCreateMode.value) {
      await auth.createFirstAdmin(form)
    } else {
      await auth.signIn(form)
    }

    if (auth.isAuthenticated.value) {
      await router.push(redirectTo.value)
      return
    }

    setMessage('Signed in, but this account is not active yet.', 'warn')
  } catch (error) {
    setMessage(error.message, 'error')
  }
}
</script>
