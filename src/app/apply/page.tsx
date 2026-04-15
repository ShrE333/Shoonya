'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import { toast } from 'sonner'
import { ArrowLeft, Loader2, IndianRupee, Calculator, CheckCircle } from 'lucide-react'
import Link from 'next/link'
import { calculateEMI, formatCurrency } from '@/lib/utils'

const LOAN_TYPES = [
  'Personal Loan',
  'Home Loan',
  'Business Loan',
  'Education Loan',
  'Vehicle Loan',
  'Gold Loan',
  'Mortgage Loan',
]

const schema = z.object({
  loan_type: z.string().min(1, 'Select loan type'),
  amount_requested: z.number().min(10000, 'Minimum ₹10,000').max(50000000, 'Maximum ₹5 Crore'),
  tenure_months: z.number().min(6, 'Minimum 6 months').max(360, 'Maximum 360 months'),
  purpose: z.string().min(10, 'Describe the purpose (min 10 chars)'),
})

type FormData = z.infer<typeof schema>

export default function ApplyLoanPage() {
  const [submitting, setSubmitting] = useState(false)
  const [submitted, setSubmitted] = useState(false)
  const router = useRouter()
  const supabase = createClient()

  const { register, handleSubmit, watch, formState: { errors } } = useForm<FormData>({
    resolver: zodResolver(schema),
    defaultValues: {
      loan_type: '',
      amount_requested: 100000,
      tenure_months: 24,
      purpose: '',
    },
  })

  const watchedAmount = watch('amount_requested')
  const watchedTenure = watch('tenure_months')

  // Estimated EMI at 12% p.a. (default)
  const estimatedEMI = calculateEMI(watchedAmount || 0, 12, watchedTenure || 12)

  // Simple eligibility score based on amount and tenure
  // Real scoring happens on admin side
  const getEligibilityScore = (amount: number): number => {
    if (amount <= 500000) return 75
    if (amount <= 2000000) return 65
    return 55
  }

  const onSubmit = async (data: FormData) => {
    setSubmitting(true)
    try {
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) throw new Error('Not authenticated')

      const { error } = await supabase.from('loans').insert({
        user_id: user.id,
        ...data,
        status: 'pending',
        eligibility_score: getEligibilityScore(data.amount_requested),
      })

      if (error) throw error

      setSubmitted(true)
      toast.success('Loan application submitted successfully!')
    } catch (err: unknown) {
      const errorMessage = err instanceof Error ? err.message : 'Failed to submit application'
      toast.error(errorMessage)
    } finally {
      setSubmitting(false)
    }
  }

  if (submitted) {
    return (
      <div className="min-h-screen mesh-bg flex items-center justify-center p-4">
        <div className="glass-card p-12 text-center max-w-md w-full">
          <div className="w-20 h-20 rounded-full bg-emerald-500/20 flex items-center justify-center mx-auto mb-6">
            <CheckCircle className="w-10 h-10 text-emerald-400" />
          </div>
          <h2 className="text-2xl font-bold mb-3">Application Submitted!</h2>
          <p className="text-muted-foreground text-sm mb-8">
            Your loan application is under review. We'll notify you within 48 hours.
            You can track the status on your dashboard.
          </p>
          <Link
            href="/dashboard"
            className="inline-flex items-center gap-2 px-6 py-3 rounded-xl bg-gradient-to-r from-violet-600 to-purple-600 text-white font-semibold btn-glow"
          >
            Back to Dashboard
          </Link>
        </div>
      </div>
    )
  }

  return (
    <div className="min-h-screen mesh-bg flex flex-col">
      <header className="sticky top-0 z-40 flex items-center gap-4 px-6 py-4 backdrop-blur-xl border-b border-border">
        <Link href="/dashboard" className="p-2 rounded-xl hover:bg-muted/60 text-muted-foreground hover:text-foreground transition-all">
          <ArrowLeft className="w-4 h-4" />
        </Link>
        <div>
          <h1 className="font-bold">Apply for Loan</h1>
          <p className="text-xs text-muted-foreground">Fill in the details to apply</p>
        </div>
      </header>

      <div className="flex-1 max-w-3xl mx-auto w-full px-4 py-6">
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
          {/* Form */}
          <form onSubmit={handleSubmit(onSubmit)} className="lg:col-span-2 glass-card p-6 space-y-5">
            <div>
              <label className="block text-sm font-medium mb-2">Loan Type *</label>
              <select {...register('loan_type')} className="input-dark">
                <option value="">Select loan type</option>
                {LOAN_TYPES.map(t => (
                  <option key={t} value={t}>{t}</option>
                ))}
              </select>
              {errors.loan_type && <p className="text-destructive text-xs mt-1">{errors.loan_type.message}</p>}
            </div>

            <div>
              <label className="block text-sm font-medium mb-2">Loan Amount *</label>
              <div className="relative">
                <IndianRupee className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
                <input
                  type="number"
                  {...register('amount_requested', { valueAsNumber: true })}
                  placeholder="500000"
                  className="input-dark pl-9"
                />
              </div>
              {errors.amount_requested && <p className="text-destructive text-xs mt-1">{errors.amount_requested.message}</p>}
            </div>

            <div>
              <label className="block text-sm font-medium mb-2">Tenure (months) *</label>
              <input
                type="number"
                {...register('tenure_months', { valueAsNumber: true })}
                placeholder="24"
                className="input-dark"
              />
              {errors.tenure_months && <p className="text-destructive text-xs mt-1">{errors.tenure_months.message}</p>}
              <div className="flex gap-2 mt-2">
                {[12, 24, 36, 60, 84].map(t => (
                  <button
                    key={t}
                    type="button"
                    onClick={() => (document.querySelector('input[placeholder="24"]') as HTMLInputElement).value = t.toString()}
                    className="text-xs px-3 py-1 rounded-lg border border-border hover:border-primary/50 hover:text-primary transition-all"
                  >
                    {t}m
                  </button>
                ))}
              </div>
            </div>

            <div>
              <label className="block text-sm font-medium mb-2">Purpose of Loan *</label>
              <textarea
                {...register('purpose')}
                rows={3}
                placeholder="Describe why you need this loan (e.g., home renovation, business expansion, medical expenses...)"
                className="input-dark resize-none"
              />
              {errors.purpose && <p className="text-destructive text-xs mt-1">{errors.purpose.message}</p>}
            </div>

            <button
              type="submit"
              disabled={submitting}
              className="w-full flex items-center justify-center gap-2 py-3 rounded-xl bg-gradient-to-r from-violet-600 to-purple-600 text-white font-semibold btn-glow disabled:opacity-70"
            >
              {submitting ? (
                <><Loader2 className="w-4 h-4 animate-spin" /> Submitting...</>
              ) : (
                'Submit Application'
              )}
            </button>
          </form>

          {/* EMI Calculator sidebar */}
          <div className="space-y-4">
            <div className="glass-card p-5">
              <div className="flex items-center gap-2 mb-4">
                <Calculator className="w-4 h-4 text-primary" />
                <h3 className="font-semibold text-sm">EMI Estimate</h3>
              </div>
              <p className="text-xs text-muted-foreground mb-2">At 12% p.a. (indicative)</p>
              <div className="text-center py-4">
                <p className="text-3xl font-black gradient-text">
                  {formatCurrency(estimatedEMI)}
                </p>
                <p className="text-xs text-muted-foreground mt-1">per month</p>
              </div>
              <div className="space-y-2 text-sm">
                <div className="flex justify-between text-muted-foreground">
                  <span>Principal</span>
                  <span>{formatCurrency(watchedAmount || 0)}</span>
                </div>
                <div className="flex justify-between text-muted-foreground">
                  <span>Tenure</span>
                  <span>{watchedTenure || 0} months</span>
                </div>
                <div className="flex justify-between font-semibold border-t border-border pt-2">
                  <span>Total Payable</span>
                  <span>{formatCurrency((estimatedEMI * watchedTenure) || 0)}</span>
                </div>
              </div>
            </div>

            <div className="glass-card p-5 bg-gradient-to-br from-violet-500/10 to-purple-500/5 border-violet-500/20">
              <h3 className="font-semibold text-sm mb-3">💡 Tips</h3>
              <ul className="space-y-2 text-xs text-muted-foreground">
                <li>• Higher income increases eligibility</li>
                <li>• Shorter tenure = higher EMI, less interest</li>
                <li>• KYC verified users get faster approval</li>
                <li>• Keep CIBIL score above 750 for best rates</li>
              </ul>
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}
