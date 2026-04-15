import { clsx, type ClassValue } from 'clsx'
import { twMerge } from 'tailwind-merge'

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}

export function formatCurrency(amount: number): string {
  return new Intl.NumberFormat('en-IN', {
    style: 'currency',
    currency: 'INR',
    maximumFractionDigits: 0,
  }).format(amount)
}

export function formatDate(dateString: string): string {
  return new Intl.DateTimeFormat('en-IN', {
    day: '2-digit',
    month: 'short',
    year: 'numeric',
  }).format(new Date(dateString))
}

export function formatRelativeTime(dateString: string): string {
  const date = new Date(dateString)
  const now = new Date()
  const diffMs = now.getTime() - date.getTime()
  const diffMins = Math.floor(diffMs / 60000)
  const diffHours = Math.floor(diffMs / 3600000)
  const diffDays = Math.floor(diffMs / 86400000)

  if (diffMins < 1) return 'Just now'
  if (diffMins < 60) return `${diffMins}m ago`
  if (diffHours < 24) return `${diffHours}h ago`
  if (diffDays < 7) return `${diffDays}d ago`
  return formatDate(dateString)
}

export function calculateEMI(principal: number, rate: number, tenure: number): number {
  // rate is annual %, tenure in months
  const monthlyRate = rate / 12 / 100
  if (monthlyRate === 0) return principal / tenure
  const emi =
    (principal * monthlyRate * Math.pow(1 + monthlyRate, tenure)) /
    (Math.pow(1 + monthlyRate, tenure) - 1)
  return Math.round(emi)
}

export function getLoanStatusLabel(status: string): string {
  const labels: Record<string, string> = {
    pending: 'Pending',
    under_review: 'Under Review',
    approved: 'Approved',
    rejected: 'Rejected',
  }
  return labels[status] || status
}

export function getKYCStatusLabel(status: string): string {
  const labels: Record<string, string> = {
    pending: 'Not Started',
    link_sent: 'Link Sent',
    completed: 'Submitted',
    failed: 'Failed',
    verified: 'Verified',
  }
  return labels[status] || status
}

export function generateToken(): string {
  return crypto.randomUUID().replace(/-/g, '')
}

export function maskAadhar(aadhar: string): string {
  return `XXXX XXXX ${aadhar.slice(-4)}`
}

export function maskPAN(pan: string): string {
  return `${pan.slice(0, 2)}XXXXXXX${pan.slice(-1)}`
}
