'use client'

import { Profile, Loan, KYC } from '@/lib/types'
import { formatCurrency, formatDate, getLoanStatusLabel, getKYCStatusLabel, maskAadhar, maskPAN } from '@/lib/utils'
import { X, User, Phone, MapPin, Briefcase, Shield } from 'lucide-react'

type Props = {
  user: Profile
  loans: Loan[]
  kyc: KYC | null
  onClose: () => void
}

export default function UserProfileDrawer({ user, loans, kyc, onClose }: Props) {
  return (
    <div className="fixed inset-0 z-50 flex justify-end">
      <div className="absolute inset-0 bg-black/50 backdrop-blur-sm" onClick={onClose} />
      <div className="relative w-full max-w-md glass-card rounded-none rounded-l-2xl overflow-y-auto">
        <div className="sticky top-0 flex items-center justify-between p-5 border-b border-border bg-card/80 backdrop-blur">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-full bg-gradient-to-br from-violet-500 to-purple-600 flex items-center justify-center font-bold">
              {user.full_name?.charAt(0) || '?'}
            </div>
            <div>
              <p className="font-semibold">{user.full_name}</p>
              <p className="text-xs text-muted-foreground">{user.email}</p>
            </div>
          </div>
          <button onClick={onClose} className="p-2 rounded-xl hover:bg-muted transition-all">
            <X className="w-4 h-4" />
          </button>
        </div>

        <div className="p-5 space-y-6">
          {/* Personal info */}
          <section>
            <h3 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-3 flex items-center gap-2">
              <User className="w-3 h-3" /> Personal
            </h3>
            <div className="grid grid-cols-2 gap-3">
              {[
                { label: 'Age', value: user.age },
                { label: 'Employment', value: user.employment_type },
                { label: 'Monthly Income', value: user.monthly_income ? formatCurrency(user.monthly_income) : '—' },
                { label: 'Joined', value: formatDate(user.created_at) },
              ].map(({ label, value }) => (
                <div key={label} className="p-3 rounded-xl bg-muted/40 border border-border">
                  <p className="text-xs text-muted-foreground">{label}</p>
                  <p className="text-sm font-medium mt-0.5">{value || '—'}</p>
                </div>
              ))}
            </div>
          </section>

          {/* Contact */}
          <section>
            <h3 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-3 flex items-center gap-2">
              <Phone className="w-3 h-3" /> Contact
            </h3>
            <div className="space-y-2">
              <div className="p-3 rounded-xl bg-muted/40 border border-border">
                <p className="text-xs text-muted-foreground">Phone</p>
                <p className="text-sm font-medium">{user.phone ? `+91 ${user.phone}` : '—'}</p>
              </div>
              <div className="p-3 rounded-xl bg-muted/40 border border-border">
                <p className="text-xs text-muted-foreground">Address</p>
                <p className="text-sm font-medium">
                  {user.address ? `${user.address}, ${user.city}, ${user.state} — ${user.pincode}` : '—'}
                </p>
              </div>
            </div>
          </section>

          {/* KYC & Documents */}
          <section>
            <h3 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-3 flex items-center gap-2">
              <Shield className="w-3 h-3" /> KYC & Documents
            </h3>
            <div className="p-4 rounded-xl bg-muted/40 border border-border space-y-3">
              <div className="flex justify-between text-sm">
                <span className="text-muted-foreground">KYC Status</span>
                <span className="font-medium">{getKYCStatusLabel(kyc?.status || 'pending')}</span>
              </div>
              {user.pan_number && (
                <div className="flex justify-between text-sm">
                  <span className="text-muted-foreground">PAN</span>
                  <span className="font-mono">{maskPAN(user.pan_number)}</span>
                </div>
              )}
              {user.aadhar_number && (
                <div className="flex justify-between text-sm">
                  <span className="text-muted-foreground">Aadhaar</span>
                  <span className="font-mono">{maskAadhar(user.aadhar_number)}</span>
                </div>
              )}
              {kyc?.selfie_url && (
                <div>
                  <p className="text-xs text-muted-foreground mb-2">KYC Selfie</p>
                  <img
                    src={kyc.selfie_url}
                    alt="KYC Selfie"
                    className="w-24 h-24 rounded-xl object-cover border border-border"
                  />
                </div>
              )}
            </div>
          </section>

          {/* Loan history */}
          <section>
            <h3 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-3 flex items-center gap-2">
              <Briefcase className="w-3 h-3" /> Loan History ({loans.length})
            </h3>
            {loans.length === 0 ? (
              <p className="text-sm text-muted-foreground text-center py-4">No loans applied</p>
            ) : (
              <div className="space-y-2">
                {loans.map(loan => (
                  <div key={loan.id} className="p-3 rounded-xl bg-muted/40 border border-border flex items-center justify-between">
                    <div>
                      <p className="text-sm font-medium">{loan.loan_type}</p>
                      <p className="text-xs text-muted-foreground">{formatDate(loan.created_at)}</p>
                    </div>
                    <div className="text-right">
                      <p className="text-sm font-bold">{formatCurrency(loan.amount_requested)}</p>
                      <span className={`badge-${loan.status} text-[10px]`}>
                        {getLoanStatusLabel(loan.status)}
                      </span>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </section>
        </div>
      </div>
    </div>
  )
}
