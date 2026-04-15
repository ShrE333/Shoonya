'use client'

import { useState } from 'react'
import { LoanWithProfile } from '@/lib/types'
import { formatCurrency, formatDate, getLoanStatusLabel, calculateEMI } from '@/lib/utils'
import { X, Loader2, CheckCircle } from 'lucide-react'
import { createClient } from '@/lib/supabase/client'
import { useRouter } from 'next/navigation'
import { toast } from 'sonner'

type Props = {
  loan: LoanWithProfile
  onClose: () => void
  adminId: string
}

const STATUSES = ['pending', 'under_review', 'approved', 'rejected'] as const

export default function LoanDetailModal({ loan, onClose, adminId }: Props) {
  const [status, setStatus] = useState(loan.status)
  const [approvedAmount, setApprovedAmount] = useState(loan.approved_amount || loan.amount_requested)
  const [interestRate, setInterestRate] = useState(loan.interest_rate || 12)
  const [remarks, setRemarks] = useState(loan.remarks || '')
  const [saving, setSaving] = useState(false)
  const supabase = createClient()
  const router = useRouter()

  const emi = calculateEMI(approvedAmount, interestRate, loan.tenure_months)

  const handleSave = async () => {
    setSaving(true)
    try {
      const { error } = await supabase
        .from('loans')
        .update({
          status,
          approved_amount: status === 'approved' ? approvedAmount : null,
          interest_rate: status === 'approved' ? interestRate : null,
          emi_amount: status === 'approved' ? emi : null,
          remarks,
          updated_at: new Date().toISOString(),
        })
        .eq('id', loan.id)

      if (error) throw error
      toast.success('Loan application updated')
      onClose()
      router.refresh()
    } catch {
      toast.error('Failed to update loan')
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
      <div className="absolute inset-0 bg-black/60 backdrop-blur-sm" onClick={onClose} />
      <div className="relative glass-card p-6 w-full max-w-lg max-h-[90vh] overflow-y-auto">
        <div className="flex items-center justify-between mb-6">
          <div>
            <h2 className="text-lg font-bold">Review Loan Application</h2>
            <p className="text-sm text-muted-foreground">{loan.profiles?.full_name}</p>
          </div>
          <button onClick={onClose} className="p-2 rounded-xl hover:bg-muted transition-all">
            <X className="w-4 h-4" />
          </button>
        </div>

        {/* Loan info */}
        <div className="grid grid-cols-2 gap-3 mb-6">
          {[
            { label: 'Loan Type', value: loan.loan_type },
            { label: 'Amount Requested', value: formatCurrency(loan.amount_requested) },
            { label: 'Tenure', value: `${loan.tenure_months} months` },
            { label: 'Purpose', value: loan.purpose },
            { label: 'Applied On', value: formatDate(loan.created_at) },
            { label: 'Eligibility Score', value: loan.eligibility_score ? `${loan.eligibility_score}/100` : '—' },
          ].map(({ label, value }) => (
            <div key={label} className="p-3 rounded-xl bg-muted/40 border border-border">
              <p className="text-xs text-muted-foreground mb-0.5">{label}</p>
              <p className="text-sm font-medium">{value}</p>
            </div>
          ))}
        </div>

        {/* Status */}
        <div className="mb-5">
          <label className="block text-sm font-medium mb-2">Update Status</label>
          <div className="grid grid-cols-2 gap-2">
            {STATUSES.map(s => (
              <button
                key={s}
                onClick={() => setStatus(s)}
                className={`py-2.5 rounded-xl text-sm font-medium capitalize transition-all border ${
                  status === s
                    ? 'bg-primary/15 border-primary/40 text-primary'
                    : 'border-border text-muted-foreground hover:border-muted-foreground'
                }`}
              >
                {getLoanStatusLabel(s)}
              </button>
            ))}
          </div>
        </div>

        {/* Approved amount + rate (only when approving) */}
        {status === 'approved' && (
          <div className="space-y-4 mb-5 p-4 rounded-xl bg-emerald-500/10 border border-emerald-500/20">
            <h3 className="text-sm font-semibold text-emerald-400">Approval Details</h3>
            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="block text-xs text-muted-foreground mb-1">Approved Amount (₹)</label>
                <input
                  type="number"
                  value={approvedAmount}
                  onChange={e => setApprovedAmount(Number(e.target.value))}
                  className="input-dark text-sm py-2"
                />
              </div>
              <div>
                <label className="block text-xs text-muted-foreground mb-1">Interest Rate (% p.a.)</label>
                <input
                  type="number"
                  step="0.1"
                  value={interestRate}
                  onChange={e => setInterestRate(Number(e.target.value))}
                  className="input-dark text-sm py-2"
                />
              </div>
            </div>
            <div className="flex items-center justify-between text-sm p-3 rounded-lg bg-emerald-500/10">
              <span className="text-muted-foreground">Monthly EMI</span>
              <span className="font-bold text-emerald-400">{formatCurrency(emi)}</span>
            </div>
          </div>
        )}

        {/* Remarks */}
        <div className="mb-6">
          <label className="block text-sm font-medium mb-2">Remarks (visible to user)</label>
          <textarea
            value={remarks}
            onChange={e => setRemarks(e.target.value)}
            rows={3}
            placeholder="Add any notes or reasons..."
            className="input-dark resize-none text-sm"
          />
        </div>

        <div className="flex gap-3">
          <button
            onClick={onClose}
            className="px-5 py-2.5 rounded-xl border border-border text-sm font-medium hover:bg-muted/40 transition-all"
          >
            Cancel
          </button>
          <button
            onClick={handleSave}
            disabled={saving}
            className="flex-1 flex items-center justify-center gap-2 py-2.5 rounded-xl bg-gradient-to-r from-violet-600 to-purple-600 text-white text-sm font-semibold btn-glow disabled:opacity-70"
          >
            {saving ? <Loader2 className="w-4 h-4 animate-spin" /> : <CheckCircle className="w-4 h-4" />}
            {saving ? 'Saving...' : 'Save Changes'}
          </button>
        </div>
      </div>
    </div>
  )
}
