export const currencyCode = import.meta.env.VITE_CURRENCY || 'PHP'

const moneyFormatter = new Intl.NumberFormat('en-PH', {
  style: 'currency',
  currency: currencyCode,
  maximumFractionDigits: 2,
})

const numberFormatter = new Intl.NumberFormat('en-PH')

const compactNumberFormatter = new Intl.NumberFormat('en-PH', {
  notation: 'compact',
  maximumFractionDigits: 1,
})

export function formatCurrency(value) {
  return moneyFormatter.format(Number(value || 0))
}

export function formatNumber(value) {
  return numberFormatter.format(Number(value || 0))
}

export function formatCompactCurrency(value) {
  return moneyFormatter.format(Number(value || 0)).replace(/\d[\d,.]*/, compactNumberFormatter.format(Number(value || 0)))
}

export function formatDate(value) {
  if (!value) return ''

  return new Intl.DateTimeFormat('en-PH', {
    month: 'short',
    day: '2-digit',
    year: 'numeric',
  }).format(new Date(`${value}T00:00:00`))
}

export function toISODate(value) {
  if (!value) return null
  const date = value instanceof Date ? value : new Date(value)
  const offset = date.getTimezoneOffset()
  const localDate = new Date(date.getTime() - offset * 60 * 1000)

  return localDate.toISOString().slice(0, 10)
}

export function todayISO() {
  return toISODate(new Date())
}

export function addDaysISO(days) {
  const date = new Date()
  date.setDate(date.getDate() + days)

  return toISODate(date)
}
