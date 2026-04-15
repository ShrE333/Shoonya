'use client'

import { useState } from 'react'
import { Profile, Loan, KYC, LoanWithProfile, KYCWithProfile } from '@/lib/types'
import { formatCurrency, formatDate, getLoanStatusLabel, getKYCStatusLabel, cn } from '@/lib/utils'
import {
  Users, FileText, Shield, BarChart3, LogOut, Menu, X,
  CheckCircle, XCircle, Clock, AlertCircle, Send,
  Eye, Loader2, TrendingUp, DollarSign, UserCheck
} from 'lucide-react'
import { createClient } from '@/lib/supabase/client'
import { useRouter } from 'next/navigation'
import { toast } from 'sonner'
import LoanDetailModal from '@/components/admin/LoanDetailModal'
import UserProfileDrawer from '@/components/admin/UserProfileDrawer'

type Props = {
  adminProfile: Profile
  profiles: Profile[]
  loans: LoanWithProfile[]
  kycs: KYCWithProfile[]
}

type AdminTab = 'users' | 'loans' | 'kyc' | 'analytics'

const STATUS_ICON: Record<string, React.ReactNode> = {
  pending: <Clock className="w-3 h-3" />,
  under_review: <AlertCircle className="w-3 h-3" />,
  approved: <CheckCircle className="w-3 h-3" />,
  rejected: <XCircle className="w-3 h-3" />,
  link_sent: <Send className="w-3 h-3" />,
  completed: <Eye className="w-3 h-3" />,
  verified: <CheckCircle className="w-3 h-3" />,
  failed: <XCircle className="w-3 h-3" />,
}

export default function AdminClient({ adminProfile, profiles, loans, kycs }: Props) {
  const [activeTab, setActiveTab] = useState<AdminTab>('users')
  const [sidebarOpen, setSidebarOpen] = useState(false)
  const [selectedLoan, setSelectedLoan] = useState<LoanWithProfile | null>(null)
  const [selectedUser, setSelectedUser] = useState<Profile | null>(null)
  const [sendingKYC, setSendingKYC] = useState<string | null>(null)
  const supabase = createClient()
  const router = useRouter()

  const handleSignOut = async () => {
    await supabase.auth.signOut()
    router.push('/login')
  }

  const handleSendKYCLink = async (userId: string, phone: string, name: string) => {
    setSendingKYC(userId)
    try {
      const res = await fetch('/api/send-kyc-link', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ userId, phone, name }),
      })
      const data = await res.json()
      
      if (!res.ok) throw new Error(data.error || 'Failed to send')
      
      if (data.warning) {
        toast.warning(`Link generated, but WhatsApp failed: ${data.warning}`, {
          duration: 6000
        })
      } else {
        toast.success(`KYC link sent to ${name} via WhatsApp!`)
      }
      
      router.refresh()
    } catch (err: any) {
      toast.error(err.message || 'Failed to send KYC link. Check Twilio credentials.')
    } finally {
      setSendingKYC(null)
    }
  }

  const handleVerifyKYC = async (kycId: string, status: 'verified' | 'failed') => {
    try {
      const { error } = await supabase
        .from('kyc')
        .update({ status, verified_by: adminProfile.id })
        .eq('id', kycId)
      if (error) throw error
      toast.success(`KYC marked as ${status}`)
      router.refresh()
    } catch {
      toast.error('Failed to update KYC status')
    }
  }

  const navItems = [
    { id: 'users', label: 'Users', icon: Users, count: profiles.length },
    { id: 'loans', label: 'Loan Applications', icon: FileText, count: loans.length },
    { id: 'kyc', label: 'KYC Management', icon: Shield, count: kycs.filter(k => k.status === 'completed' || k.status === 'pending').length },
    { id: 'analytics', label: 'Analytics', icon: BarChart3 },
  ]

  return (
    <div className="min-h-screen mesh-bg flex">
      {/* Sidebar */}
      <aside className={cn(
        'fixed inset-y-0 left-0 z-50 w-64 flex flex-col bg-card/90 backdrop-blur-xl border-r border-border transition-transform duration-300',
        sidebarOpen ? 'translate-x-0' : '-translate-x-full lg:translate-x-0'
      )}>
        {/* Sidebar header */}
        <div className="flex items-center justify-between p-5 border-b border-border">
          <div className="flex items-center gap-3">
            <div className="w-8 h-8 rounded-xl bg-gradient-to-br from-violet-500 to-purple-600 flex items-center justify-center">
              <span className="text-white font-bold text-sm">S</span>
            </div>
            <div>
              <span className="text-base font-bold gradient-text">Shoonya</span>
              <p className="text-[10px] text-muted-foreground">Admin Panel</p>
            </div>
          </div>
          <button onClick={() => setSidebarOpen(false)} className="lg:hidden p-1 rounded hover:bg-muted">
            <X className="w-4 h-4" />
          </button>
        </div>

        {/* Nav items */}
        <nav className="flex-1 p-4 space-y-1">
          {navItems.map(({ id, label, icon: Icon, count }) => (
            <button
              key={id}
              onClick={() => { setActiveTab(id as AdminTab); setSidebarOpen(false) }}
              className={cn(
                'w-full flex items-center justify-between px-4 py-3 rounded-xl text-sm font-medium transition-all',
                activeTab === id
                  ? 'bg-primary/15 text-primary border border-primary/20'
                  : 'text-muted-foreground hover:bg-muted/60 hover:text-foreground'
              )}
            >
              <div className="flex items-center gap-3">
                <Icon className="w-4 h-4" />
                {label}
              </div>
              {count !== undefined && (
                <span className={cn(
                  'text-xs px-2 py-0.5 rounded-full',
                  activeTab === id ? 'bg-primary/20 text-primary' : 'bg-muted text-muted-foreground'
                )}>
                  {count}
                </span>
              )}
            </button>
          ))}
        </nav>

        {/* Sidebar footer */}
        <div className="p-4 border-t border-border">
          <div className="flex items-center gap-3 mb-3 px-2">
            <div className="w-8 h-8 rounded-full bg-gradient-to-br from-violet-500 to-purple-600 flex items-center justify-center">
              <span className="text-white text-xs font-bold">
                {adminProfile.full_name?.charAt(0) || 'A'}
              </span>
            </div>
            <div className="flex-1 min-w-0">
              <p className="text-sm font-medium truncate">{adminProfile.full_name || 'Admin'}</p>
              <p className="text-xs text-muted-foreground truncate">{adminProfile.email}</p>
            </div>
          </div>
          <button
            onClick={handleSignOut}
            className="w-full flex items-center gap-2 px-3 py-2 rounded-lg text-sm text-muted-foreground hover:text-destructive hover:bg-destructive/10 transition-all"
          >
            <LogOut className="w-4 h-4" /> Sign out
          </button>
        </div>
      </aside>

      {/* Sidebar overlay on mobile */}
      {sidebarOpen && (
        <div className="fixed inset-0 z-40 bg-black/50 lg:hidden" onClick={() => setSidebarOpen(false)} />
      )}

      {/* Main content */}
      <main className="flex-1 lg:ml-64 flex flex-col min-h-screen">
        {/* Top bar */}
        <header className="sticky top-0 z-30 flex items-center gap-4 px-6 py-4 backdrop-blur-xl border-b border-border bg-background/50">
          <button
            onClick={() => setSidebarOpen(true)}
            className="lg:hidden p-2 rounded-xl hover:bg-muted"
          >
            <Menu className="w-4 h-4" />
          </button>
          <div>
            <h1 className="font-bold text-lg capitalize">
              {activeTab === 'kyc' ? 'KYC Management' : activeTab.charAt(0).toUpperCase() + activeTab.slice(1)}
            </h1>
            <p className="text-xs text-muted-foreground">
              {activeTab === 'users' && `${profiles.length} registered users`}
              {activeTab === 'loans' && `${loans.length} total applications`}
              {activeTab === 'kyc' && `${kycs.filter(k => k.status === 'completed').length} pending review`}
              {activeTab === 'analytics' && 'Platform overview'}
            </p>
          </div>
        </header>

        <div className="flex-1 p-6">
          {/* USERS TAB */}
          {activeTab === 'users' && (
            <div className="glass-card overflow-hidden">
              <div className="overflow-x-auto">
                <table className="w-full data-table">
                  <thead>
                    <tr>
                      <th>Name</th>
                      <th>Email</th>
                      <th>Phone</th>
                      <th>KYC</th>
                      <th>Loans</th>
                      <th>Joined</th>
                      <th>Actions</th>
                    </tr>
                  </thead>
                  <tbody>
                    {profiles.map((p) => {
                      const userKYC = kycs.find(k => k.user_id === p.id)
                      const userLoans = loans.filter(l => l.user_id === p.id)
                      return (
                        <tr key={p.id}>
                          <td>
                            <div className="flex items-center gap-2">
                              <div className="w-8 h-8 rounded-full bg-gradient-to-br from-violet-500/30 to-purple-600/30 flex items-center justify-center text-xs font-bold">
                                {p.full_name?.charAt(0) || '?'}
                              </div>
                              <span className="font-medium">{p.full_name || '—'}</span>
                            </div>
                          </td>
                          <td className="text-muted-foreground">{p.email}</td>
                          <td className="text-muted-foreground">{p.phone || '—'}</td>
                          <td>
                            <span className={`badge-${userKYC?.status === 'verified' ? 'approved' : userKYC?.status === 'failed' ? 'rejected' : 'pending'}`}>
                              {STATUS_ICON[userKYC?.status || 'pending']}
                              {getKYCStatusLabel(userKYC?.status || 'pending')}
                            </span>
                          </td>
                          <td>
                            <span className="text-sm font-medium">{userLoans.length}</span>
                          </td>
                          <td className="text-muted-foreground text-xs">{formatDate(p.created_at)}</td>
                          <td>
                            <button
                              onClick={() => setSelectedUser(p)}
                              className="flex items-center gap-1 text-xs px-3 py-1.5 rounded-lg bg-muted hover:bg-muted/80 text-muted-foreground hover:text-foreground transition-all"
                            >
                              <Eye className="w-3 h-3" /> View
                            </button>
                          </td>
                        </tr>
                      )
                    })}
                  </tbody>
                </table>
                {profiles.length === 0 && (
                  <div className="text-center py-12 text-muted-foreground">No users registered yet</div>
                )}
              </div>
            </div>
          )}

          {/* LOANS TAB */}
          {activeTab === 'loans' && (
            <div className="space-y-4">
              {/* Filters */}
              <div className="flex flex-wrap gap-3">
                {['all', 'pending', 'under_review', 'approved', 'rejected'].map(status => (
                  <button
                    key={status}
                    className="text-xs px-3 py-1.5 rounded-full border border-border hover:border-primary/50 capitalize transition-all"
                  >
                    {status === 'all' ? 'All' : getLoanStatusLabel(status)}
                  </button>
                ))}
              </div>

              <div className="glass-card overflow-hidden">
                <div className="overflow-x-auto">
                  <table className="w-full data-table">
                    <thead>
                      <tr>
                        <th>Applicant</th>
                        <th>Type</th>
                        <th>Amount</th>
                        <th>Status</th>
                        <th>Score</th>
                        <th>Applied</th>
                        <th>Actions</th>
                      </tr>
                    </thead>
                    <tbody>
                      {loans.map((loan) => (
                        <tr key={loan.id}>
                          <td>
                            <div>
                              <p className="font-medium text-sm">{loan.profiles?.full_name || '—'}</p>
                              <p className="text-xs text-muted-foreground">{loan.profiles?.email}</p>
                            </div>
                          </td>
                          <td className="text-sm">{loan.loan_type}</td>
                          <td className="font-medium">{formatCurrency(loan.amount_requested)}</td>
                          <td>
                            <span className={`badge-${loan.status}`}>
                              {STATUS_ICON[loan.status]}
                              {getLoanStatusLabel(loan.status)}
                            </span>
                          </td>
                          <td>
                            {loan.eligibility_score ? (
                              <span className={cn(
                                'text-sm font-semibold',
                                loan.eligibility_score >= 65 ? 'text-emerald-400' : 'text-amber-400'
                              )}>
                                {loan.eligibility_score}
                              </span>
                            ) : '—'}
                          </td>
                          <td className="text-muted-foreground text-xs">{formatDate(loan.created_at)}</td>
                          <td>
                            <button
                              onClick={() => setSelectedLoan(loan)}
                              className="flex items-center gap-1 text-xs px-3 py-1.5 rounded-lg bg-primary/15 hover:bg-primary/20 text-primary transition-all"
                            >
                              <Eye className="w-3 h-3" /> Review
                            </button>
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                  {loans.length === 0 && (
                    <div className="text-center py-12 text-muted-foreground">No loan applications yet</div>
                  )}
                </div>
              </div>
            </div>
          )}

          {/* KYC TAB */}
          {activeTab === 'kyc' && (
            <div className="glass-card overflow-hidden">
              <div className="overflow-x-auto">
                <table className="w-full data-table">
                  <thead>
                    <tr>
                      <th>User</th>
                      <th>Phone</th>
                      <th>KYC Status</th>
                      <th>Face Age</th>
                      <th>Liveness</th>
                      <th>Submitted</th>
                      <th>Actions</th>
                    </tr>
                  </thead>
                  <tbody>
                    {profiles.map((profile) => {
                      const kyc = kycs.find(k => k.user_id === profile.id);
                      const status = kyc?.status || 'pending';
                      
                      return (
                      <tr key={profile.id}>
                        <td>
                          <div>
                            <p className="font-medium text-sm">{profile.full_name || '—'}</p>
                            <p className="text-xs text-muted-foreground">{profile.email}</p>
                          </div>
                        </td>
                        <td className="text-muted-foreground text-sm">{profile.phone || '—'}</td>
                        <td>
                          <span className={`badge-${status === 'verified' ? 'approved' : status === 'failed' ? 'rejected' : status === 'completed' ? 'under_review' : 'pending'}`}>
                            {STATUS_ICON[status]}
                            {getKYCStatusLabel(status)}
                          </span>
                        </td>
                        <td className="text-sm">{kyc?.face_age_estimate ? `~${kyc.face_age_estimate} yrs` : '—'}</td>
                        <td className="text-sm">
                          {kyc?.liveness_score ? (
                            <span className={kyc.liveness_score > 0.8 ? 'text-emerald-400' : 'text-amber-400'}>
                              {Math.round(kyc.liveness_score * 100)}%
                            </span>
                          ) : '—'}
                        </td>
                        <td className="text-muted-foreground text-xs">
                          {kyc?.completed_at ? formatDate(kyc.completed_at) : '—'}
                        </td>
                        <td>
                          <div className="flex items-center gap-2">
                            {/* Send KYC link if pending or link_sent */}
                            {(status === 'pending' || status === 'link_sent') && (
                              <button
                                onClick={() => {
                                  if (!profile.phone) {
                                    toast.error("User hasn't provided a phone number yet.")
                                    return
                                  }
                                  handleSendKYCLink(profile.id, profile.phone, profile.full_name || '')
                                }}
                                disabled={sendingKYC === profile.id}
                                className={cn(
                                  "flex items-center gap-1 text-xs px-3 py-1.5 rounded-lg transition-all disabled:opacity-50",
                                  profile.phone ? "bg-blue-500/15 hover:bg-blue-500/25 text-blue-400" : "bg-muted text-muted-foreground"
                                )}
                              >
                                {sendingKYC === profile.id ? (
                                  <Loader2 className="w-3 h-3 animate-spin" />
                                ) : (
                                  <Send className="w-3 h-3" />
                                )}
                                {status === 'link_sent' ? 'Resend' : 'Send Link'}
                              </button>
                            )}
                            {/* Verify/Fail for completed KYC */}
                            {status === 'completed' && kyc && (
                              <>
                                {kyc.selfie_url && (
                                  <a
                                    href={kyc.selfie_url}
                                    target="_blank"
                                    rel="noreferrer"
                                    className="flex items-center gap-1 text-xs px-2 py-1.5 rounded-lg bg-muted hover:bg-muted/80 transition-all"
                                  >
                                    <Eye className="w-3 h-3" />
                                  </a>
                                )}
                                <button
                                  onClick={() => handleVerifyKYC(kyc.id, 'verified')}
                                  className="flex items-center gap-1 text-xs px-2 py-1.5 rounded-lg bg-emerald-500/15 hover:bg-emerald-500/25 text-emerald-400 transition-all"
                                >
                                  <CheckCircle className="w-3 h-3" />
                                </button>
                                <button
                                  onClick={() => handleVerifyKYC(kyc.id, 'failed')}
                                  className="flex items-center gap-1 text-xs px-2 py-1.5 rounded-lg bg-destructive/15 hover:bg-destructive/25 text-destructive transition-all"
                                >
                                  <XCircle className="w-3 h-3" />
                                </button>
                              </>
                            )}
                          </div>
                        </td>
                      </tr>
                    )})}
                  </tbody>
                </table>
                {kycs.length === 0 && (
                  <div className="text-center py-12 text-muted-foreground">No KYC records yet</div>
                )}
              </div>
            </div>
          )}

          {/* ANALYTICS TAB */}
          {activeTab === 'analytics' && (
            <div className="space-y-6">
              <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
                {[
                  {
                    label: 'Total Users',
                    value: profiles.length,
                    icon: <Users className="w-5 h-5 text-violet-400" />,
                    color: 'from-violet-500/10',
                  },
                  {
                    label: 'Total Applications',
                    value: loans.length,
                    icon: <FileText className="w-5 h-5 text-blue-400" />,
                    color: 'from-blue-500/10',
                  },
                  {
                    label: 'KYC Verified',
                    value: kycs.filter(k => k.status === 'verified').length,
                    icon: <UserCheck className="w-5 h-5 text-emerald-400" />,
                    color: 'from-emerald-500/10',
                  },
                  {
                    label: 'Approved Loans',
                    value: `₹${(loans.filter(l => l.status === 'approved').reduce((s, l) => s + (l.approved_amount || 0), 0) / 100000).toFixed(1)}L`,
                    icon: <DollarSign className="w-5 h-5 text-amber-400" />,
                    color: 'from-amber-500/10',
                  },
                ].map((stat) => (
                  <div key={stat.label} className={`glass-card p-5 bg-gradient-to-br ${stat.color} to-transparent`}>
                    <div className="flex items-center justify-between mb-3">
                      <span className="text-xs text-muted-foreground">{stat.label}</span>
                      {stat.icon}
                    </div>
                    <p className="text-2xl font-black">{stat.value}</p>
                  </div>
                ))}
              </div>

              {/* Loan status breakdown */}
              <div className="glass-card p-6">
                <h3 className="font-semibold mb-4 flex items-center gap-2">
                  <TrendingUp className="w-4 h-4 text-primary" /> Loan Status Breakdown
                </h3>
                <div className="space-y-3">
                  {[
                    { status: 'pending', label: 'Pending', color: 'bg-amber-400' },
                    { status: 'under_review', label: 'Under Review', color: 'bg-blue-400' },
                    { status: 'approved', label: 'Approved', color: 'bg-emerald-400' },
                    { status: 'rejected', label: 'Rejected', color: 'bg-red-400' },
                  ].map(({ status, label, color }) => {
                    const count = loans.filter(l => l.status === status).length
                    const pct = loans.length ? Math.round((count / loans.length) * 100) : 0
                    return (
                      <div key={status}>
                        <div className="flex justify-between text-sm mb-1">
                          <span className="text-muted-foreground">{label}</span>
                          <span className="font-medium">{count} ({pct}%)</span>
                        </div>
                        <div className="h-2 bg-muted rounded-full overflow-hidden">
                          <div
                            className={`h-full rounded-full ${color} transition-all`}
                            style={{ width: `${pct}%` }}
                          />
                        </div>
                      </div>
                    )
                  })}
                </div>
              </div>
            </div>
          )}
        </div>
      </main>

      {/* Modals */}
      {selectedLoan && (
        <LoanDetailModal
          loan={selectedLoan}
          onClose={() => setSelectedLoan(null)}
          adminId={adminProfile.id}
        />
      )}
      {selectedUser && (
        <UserProfileDrawer
          user={selectedUser}
          loans={loans.filter(l => l.user_id === selectedUser.id)}
          kyc={kycs.find(k => k.user_id === selectedUser.id) || null}
          onClose={() => setSelectedUser(null)}
        />
      )}
    </div>
  )
}
