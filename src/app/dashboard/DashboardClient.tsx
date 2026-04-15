'use client'

import { useState } from 'react'
import { Profile, Loan, KYC } from '@/lib/types'
import { formatCurrency, formatDate, getLoanStatusLabel, getKYCStatusLabel, cn } from '@/lib/utils'
import { 
  LayoutDashboard, MessageSquare, LogOut, User, ChevronRight,
  Plus, Shield, CheckCircle, Clock, XCircle, AlertCircle,
  TrendingUp, DollarSign, Calendar, Percent
} from 'lucide-react'
import { createClient } from '@/lib/supabase/client'
import { useRouter } from 'next/navigation'
import { toast } from 'sonner'
import ChatWindow from '@/components/chat/ChatWindow'
import Link from 'next/link'

type Props = {
  profile: Profile
  loans: Loan[]
  kyc: KYC | null
}

type LoanTab = 'all' | 'eligible' | 'approved'

const STATUS_ICON: Record<string, React.ReactNode> = {
  pending: <Clock className="w-3 h-3" />,
  under_review: <AlertCircle className="w-3 h-3" />,
  approved: <CheckCircle className="w-3 h-3" />,
  rejected: <XCircle className="w-3 h-3" />,
}

export default function DashboardClient({ profile, loans, kyc }: Props) {
  const [activeTab, setActiveTab] = useState<'loans' | 'chat'>('loans')
  const [loanTab, setLoanTab] = useState<LoanTab>('all')
  const supabase = createClient()
  const router = useRouter()

  const handleSignOut = async () => {
    await supabase.auth.signOut()
    router.push('/login')
    toast.success('Signed out successfully')
  }

  const filteredLoans = loans.filter(loan => {
    if (loanTab === 'eligible') return (loan.eligibility_score || 0) >= 65
    if (loanTab === 'approved') return loan.status === 'approved'
    return true
  })

  const kycStatus = kyc?.status || 'pending'
  const isKYCVerified = kycStatus === 'verified'

  return (
    <div className="min-h-screen mesh-bg flex flex-col">
      {/* Header */}
      <header className="sticky top-0 z-40 flex items-center justify-between px-6 py-4 backdrop-blur-xl border-b border-border">
        <div className="flex items-center gap-3">
          <div className="w-8 h-8 rounded-xl bg-gradient-to-br from-violet-500 to-purple-600 flex items-center justify-center">
            <span className="text-white font-bold text-sm">S</span>
          </div>
          <span className="text-xl font-bold gradient-text hidden sm:block">Shoonya</span>
        </div>
        <div className="flex items-center gap-3">
          <div className="flex items-center gap-2 px-3 py-1.5 rounded-full bg-muted/60 border border-border">
            <div className="w-6 h-6 rounded-full bg-gradient-to-br from-violet-500 to-purple-600 flex items-center justify-center">
              <User className="w-3 h-3 text-white" />
            </div>
            <span className="text-sm font-medium hidden sm:block">{profile.full_name?.split(' ')[0]}</span>
          </div>
          <button
            onClick={handleSignOut}
            className="p-2 rounded-xl hover:bg-muted/60 text-muted-foreground hover:text-foreground transition-all"
            title="Sign out"
          >
            <LogOut className="w-4 h-4" />
          </button>
        </div>
      </header>

      <div className="flex-1 max-w-5xl mx-auto w-full px-4 py-6">
        {/* Welcome */}
        <div className="mb-6">
          <h1 className="text-2xl font-bold">Hello, {profile.full_name?.split(' ')[0]} 👋</h1>
          <p className="text-muted-foreground text-sm mt-1">Manage your loans and track your finances</p>
        </div>

        {/* KYC Banner */}
        <div className={cn(
          'flex items-center justify-between p-4 rounded-2xl border mb-6',
          isKYCVerified
            ? 'bg-emerald-500/10 border-emerald-500/30'
            : kycStatus === 'link_sent'
            ? 'bg-blue-500/10 border-blue-500/30'
            : 'bg-amber-500/10 border-amber-500/30'
        )}>
          <div className="flex items-center gap-3">
            <div className={cn(
              'w-10 h-10 rounded-xl flex items-center justify-center',
              isKYCVerified ? 'bg-emerald-500/20' : 'bg-amber-500/20'
            )}>
              <Shield className={cn('w-5 h-5', isKYCVerified ? 'text-emerald-400' : 'text-amber-400')} />
            </div>
            <div>
              <p className="font-semibold text-sm">
                KYC Status:{' '}
                <span className={isKYCVerified ? 'text-emerald-400' : 'text-amber-400'}>
                  {getKYCStatusLabel(kycStatus)}
                </span>
              </p>
              <p className="text-xs text-muted-foreground">
                {isKYCVerified
                  ? 'Your identity is verified. You can apply for loans.'
                  : kycStatus === 'link_sent'
                  ? 'Check your WhatsApp for the KYC verification link'
                  : 'Complete KYC to unlock higher loan amounts'}
              </p>
            </div>
          </div>
          {!isKYCVerified && kycStatus !== 'link_sent' && (
            <span className="text-xs text-muted-foreground border border-border rounded-full px-3 py-1">
              Admin will send link
            </span>
          )}
        </div>

        {/* Stats row */}
        <div className="grid grid-cols-2 sm:grid-cols-4 gap-4 mb-6">
          {[
            {
              label: 'Total Loans',
              value: loans.length,
              icon: <LayoutDashboard className="w-4 h-4 text-violet-400" />,
              color: 'from-violet-500/10 to-purple-500/5',
            },
            {
              label: 'Approved',
              value: loans.filter(l => l.status === 'approved').length,
              icon: <CheckCircle className="w-4 h-4 text-emerald-400" />,
              color: 'from-emerald-500/10 to-teal-500/5',
            },
            {
              label: 'Under Review',
              value: loans.filter(l => l.status === 'under_review').length,
              icon: <AlertCircle className="w-4 h-4 text-blue-400" />,
              color: 'from-blue-500/10 to-sky-500/5',
            },
            {
              label: 'Total Approved',
              value: formatCurrency(loans.filter(l => l.status === 'approved').reduce((sum, l) => sum + (l.approved_amount || 0), 0)),
              icon: <DollarSign className="w-4 h-4 text-amber-400" />,
              color: 'from-amber-500/10 to-orange-500/5',
            },
          ].map((stat) => (
            <div key={stat.label} className={`glass-card p-4 bg-gradient-to-br ${stat.color}`}>
              <div className="flex items-center justify-between mb-2">
                <span className="text-xs text-muted-foreground">{stat.label}</span>
                {stat.icon}
              </div>
              <p className="text-xl font-bold">{stat.value}</p>
            </div>
          ))}
        </div>

        {/* Main tabs */}
        <div className="flex gap-1 p-1 bg-muted/40 rounded-xl mb-6 border border-border">
          {[
            { id: 'loans', label: 'My Loans', icon: LayoutDashboard },
            { id: 'chat', label: 'Loan Assistant', icon: MessageSquare },
          ].map(({ id, label, icon: Icon }) => (
            <button
              key={id}
              onClick={() => setActiveTab(id as 'loans' | 'chat')}
              className={cn(
                'flex-1 flex items-center justify-center gap-2 py-2.5 rounded-lg text-sm font-medium transition-all',
                activeTab === id
                  ? 'bg-background text-foreground shadow-sm'
                  : 'text-muted-foreground hover:text-foreground'
              )}
            >
              <Icon className="w-4 h-4" /> {label}
            </button>
          ))}
        </div>

        {/* Loans tab */}
        {activeTab === 'loans' && (
          <div>
            <div className="flex items-center justify-between mb-4">
              <div className="flex gap-1 p-1 bg-muted/40 rounded-lg border border-border text-sm">
                {(['all', 'eligible', 'approved'] as LoanTab[]).map((tab) => (
                  <button
                    key={tab}
                    onClick={() => setLoanTab(tab)}
                    className={cn(
                      'px-4 py-1.5 rounded-md capitalize transition-all font-medium',
                      loanTab === tab ? 'bg-primary text-primary-foreground' : 'text-muted-foreground hover:text-foreground'
                    )}
                  >
                    {tab === 'eligible' ? 'Eligible (≥65)' : tab.charAt(0).toUpperCase() + tab.slice(1)}
                  </button>
                ))}
              </div>
              <Link
                href="/apply"
                className="flex items-center gap-2 px-4 py-2 rounded-xl bg-gradient-to-r from-violet-600 to-purple-600 text-white text-sm font-semibold btn-glow"
              >
                <Plus className="w-4 h-4" /> Apply
              </Link>
            </div>

            {filteredLoans.length === 0 ? (
              <div className="glass-card p-12 text-center">
                <TrendingUp className="w-12 h-12 text-muted-foreground mx-auto mb-4" />
                <h3 className="text-lg font-semibold mb-2">No loans yet</h3>
                <p className="text-muted-foreground text-sm mb-6">
                  {loanTab === 'all'
                    ? "You haven't applied for any loans. Get started by clicking Apply."
                    : `No ${loanTab} loans found.`}
                </p>
                {loanTab === 'all' && (
                  <Link
                    href="/apply"
                    className="inline-flex items-center gap-2 px-6 py-3 rounded-xl bg-gradient-to-r from-violet-600 to-purple-600 text-white font-semibold btn-glow"
                  >
                    <Plus className="w-4 h-4" /> Apply for Loan
                  </Link>
                )}
              </div>
            ) : (
              <div className="space-y-4">
                {filteredLoans.map((loan) => (
                  <div key={loan.id} className="glass-card p-5 hover:border-primary/20 transition-all">
                    <div className="flex items-start justify-between mb-3">
                      <div>
                        <div className="flex items-center gap-2 mb-1">
                          <h3 className="font-semibold">{loan.loan_type}</h3>
                          <span className={`badge-${loan.status}`}>
                            {STATUS_ICON[loan.status]}
                            {getLoanStatusLabel(loan.status)}
                          </span>
                        </div>
                        <p className="text-sm text-muted-foreground">{loan.purpose}</p>
                      </div>
                      <div className="text-right">
                        <p className="text-lg font-bold">{formatCurrency(loan.amount_requested)}</p>
                        <p className="text-xs text-muted-foreground">Requested</p>
                      </div>
                    </div>

                    <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 pt-3 border-t border-border">
                      <div>
                        <p className="text-xs text-muted-foreground flex items-center gap-1"><Calendar className="w-3 h-3" /> Applied</p>
                        <p className="text-sm font-medium">{formatDate(loan.created_at)}</p>
                      </div>
                      <div>
                        <p className="text-xs text-muted-foreground">Tenure</p>
                        <p className="text-sm font-medium">{loan.tenure_months} months</p>
                      </div>
                      {loan.interest_rate && (
                        <div>
                          <p className="text-xs text-muted-foreground flex items-center gap-1"><Percent className="w-3 h-3" /> Rate</p>
                          <p className="text-sm font-medium text-emerald-400">{loan.interest_rate}% p.a.</p>
                        </div>
                      )}
                      {loan.emi_amount && (
                        <div>
                          <p className="text-xs text-muted-foreground">Monthly EMI</p>
                          <p className="text-sm font-bold text-primary">{formatCurrency(loan.emi_amount)}</p>
                        </div>
                      )}
                    </div>

                    {loan.eligibility_score && (
                      <div className="mt-3 pt-3 border-t border-border">
                        <div className="flex items-center justify-between mb-1">
                          <span className="text-xs text-muted-foreground">Eligibility Score</span>
                          <span className={cn(
                            'text-xs font-semibold',
                            loan.eligibility_score >= 65 ? 'text-emerald-400' : 'text-amber-400'
                          )}>
                            {loan.eligibility_score}/100
                          </span>
                        </div>
                        <div className="h-1.5 bg-muted rounded-full overflow-hidden">
                          <div
                            className="h-full rounded-full bg-gradient-to-r from-violet-600 to-purple-600 transition-all"
                            style={{ width: `${loan.eligibility_score}%` }}
                          />
                        </div>
                      </div>
                    )}

                    {loan.remarks && (
                      <div className="mt-3 p-3 rounded-lg bg-muted/40 border border-border">
                        <p className="text-xs text-muted-foreground mb-0.5">Admin Remarks</p>
                        <p className="text-sm">{loan.remarks}</p>
                      </div>
                    )}
                  </div>
                ))}
              </div>
            )}
          </div>
        )}

        {/* Chat tab */}
        {activeTab === 'chat' && (
          <ChatWindow profile={profile} loans={loans} />
        )}
      </div>
    </div>
  )
}
