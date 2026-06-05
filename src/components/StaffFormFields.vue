<template>
  <div class="staff-form">
    <div class="form-grid">
      <label>
        Full name
        <PInputText
          :model-value="modelValue.full_name"
          autocomplete="name"
          :invalid="Boolean(errors.full_name)"
          fluid
          @update:model-value="update('full_name', $event)"
        />
        <small v-if="errors.full_name" class="field-error">{{ errors.full_name }}</small>
      </label>
      <label>
        Username
        <PInputText
          :model-value="modelValue.username"
          autocomplete="username"
          :invalid="Boolean(errors.username)"
          fluid
          @update:model-value="update('username', normalizeUsername($event))"
        />
        <small v-if="errors.username" class="field-error">{{ errors.username }}</small>
      </label>
      <label v-if="mode === 'create'">
        Password
        <PInputText
          :model-value="modelValue.password"
          type="password"
          autocomplete="new-password"
          :invalid="Boolean(errors.password)"
          fluid
          @update:model-value="update('password', $event)"
        />
        <small v-if="errors.password" class="field-error">{{ errors.password }}</small>
      </label>
      <label>
        Phone
        <PInputText :model-value="modelValue.phone" autocomplete="tel" fluid @update:model-value="update('phone', $event)" />
      </label>
      <label>
        Job title
        <PInputText :model-value="modelValue.job_title" fluid @update:model-value="update('job_title', $event)" />
      </label>
      <label>
        Role
        <PSelect
          :model-value="modelValue.role"
          :options="roleOptions"
          option-label="label"
          option-value="value"
          fluid
          @update:model-value="update('role', $event)"
        />
      </label>
      <label>
        Primary branch
        <PSelect
          :model-value="modelValue.branch_id"
          :options="branchOptions"
          option-label="name"
          option-value="id"
          :invalid="Boolean(errors.branch_id)"
          fluid
          @update:model-value="update('branch_id', $event)"
        />
        <small v-if="errors.branch_id" class="field-error">{{ errors.branch_id }}</small>
      </label>
      <label>
        Shift start
        <PInputText :model-value="modelValue.shift_start" type="time" fluid @update:model-value="update('shift_start', $event)" />
      </label>
      <label>
        Shift end
        <PInputText :model-value="modelValue.shift_end" type="time" fluid @update:model-value="update('shift_end', $event)" />
      </label>
      <label>
        Max discount %
        <PInputNumber
          :model-value="modelValue.max_discount_percent"
          suffix="%"
          :min="0"
          :max="100"
          fluid
          @update:model-value="update('max_discount_percent', $event)"
        />
      </label>
    </div>

    <div class="switch-row">
      <label class="inline-check">
        <PCheckbox
          :model-value="modelValue.can_access_all_branches"
          binary
          @update:model-value="update('can_access_all_branches', $event)"
        />
        All branches
      </label>
      <label class="inline-check">
        <PCheckbox :model-value="modelValue.can_open_shift" binary @update:model-value="update('can_open_shift', $event)" />
        Can open shift
      </label>
      <label class="inline-check">
        <PCheckbox :model-value="modelValue.can_close_shift" binary @update:model-value="update('can_close_shift', $event)" />
        Can close shift
      </label>
    </div>

    <section class="mini-section">
      <h3>Allowed branches</h3>
      <div class="permission-grid">
        <label v-for="branch in branches" :key="branch.id" class="inline-check">
          <PCheckbox
            :model-value="modelValue.allowed_branch_ids?.includes(branch.id)"
            binary
            @update:model-value="toggleArrayValue('allowed_branch_ids', branch.id)"
          />
          {{ branch.branch_code }} - {{ branch.name }}
        </label>
      </div>
    </section>

    <section class="mini-section">
      <h3>Shift days</h3>
      <div class="day-grid">
        <label v-for="day in dayOptions" :key="day.value" class="inline-check">
          <PCheckbox
            :model-value="modelValue.shift_days?.includes(day.value)"
            binary
            @update:model-value="toggleArrayValue('shift_days', day.value)"
          />
          {{ day.label }}
        </label>
      </div>
    </section>

    <section class="mini-section">
      <h3>Permissions</h3>
      <div class="permission-grid">
        <label v-for="permission in permissions" :key="permission.key" class="inline-check">
          <PCheckbox
            :model-value="modelValue.permissions?.includes(permission.key)"
            binary
            @update:model-value="toggleArrayValue('permissions', permission.key)"
          />
          {{ permission.label }}
        </label>
      </div>
    </section>
  </div>
</template>

<script setup>
import { computed } from 'vue'

const roleOptions = [
  { label: 'Admin', value: 'admin' },
  { label: 'Manager', value: 'manager' },
  { label: 'Cashier', value: 'cashier' },
  { label: 'Auditor', value: 'auditor' },
]

const dayOptions = [
  { label: 'Mon', value: 1 },
  { label: 'Tue', value: 2 },
  { label: 'Wed', value: 3 },
  { label: 'Thu', value: 4 },
  { label: 'Fri', value: 5 },
  { label: 'Sat', value: 6 },
  { label: 'Sun', value: 7 },
]

const props = defineProps({
  modelValue: {
    type: Object,
    required: true,
  },
  branches: {
    type: Array,
    default: () => [],
  },
  permissions: {
    type: Array,
    default: () => [],
  },
  mode: {
    type: String,
    default: 'create',
  },
  errors: {
    type: Object,
    default: () => ({}),
  },
})

const emit = defineEmits(['update:modelValue', 'field-change'])

const branchOptions = computed(() => [{ id: null, name: 'No single branch' }, ...props.branches])

function normalizeUsername(value) {
  return String(value || '').trim().toLowerCase()
}

function update(key, value) {
  emit('update:modelValue', {
    ...props.modelValue,
    [key]: value,
  })
  emit('field-change', key)
}

function toggleArrayValue(key, value) {
  const current = Array.isArray(props.modelValue[key]) ? props.modelValue[key] : []
  const next = current.includes(value) ? current.filter((item) => item !== value) : [...current, value]
  update(key, next)
}
</script>
