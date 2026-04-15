import Link from 'next/link'
import { ArrowRight, Shield, Zap, BarChart3, CheckCircle, Star, ChevronRight } from 'lucide-react'

export default function HomePage() {
  return (
    <main className="min-h-screen mesh-bg flex flex-col">
      {/* Nav */}
      <nav className="fixed top-0 left-0 right-0 z-50 flex items-center justify-between px-6 py-4 backdrop-blur-xl border-b border-white/5">
        <div className="flex items-center gap-3">
          <div className="w-8 h-8 rounded-xl bg-gradient-to-br from-violet-500 to-purple-600 flex items-center justify-center">
            <span className="text-white font-bold text-sm">S</span>
          </div>
          <span className="text-xl font-bold gradient-text">Shoonya</span>
        </div>
        <Link
          href="/login"
          className="flex items-center gap-2 px-5 py-2.5 rounded-xl bg-primary text-primary-foreground text-sm font-semibold btn-glow transition-all"
        >
          Get Started <ArrowRight className="w-4 h-4" />
        </Link>
      </nav>

      {/* Hero */}
      <section className="flex-1 flex flex-col items-center justify-center text-center px-6 pt-28 pb-20">
        <div className="inline-flex items-center gap-2 px-4 py-2 rounded-full bg-primary/10 border border-primary/20 text-primary text-sm font-medium mb-8">
          <Star className="w-4 h-4" />
          Smart Loan Platform — Powered by AI
        </div>

        <h1 className="text-5xl md:text-7xl font-black tracking-tight mb-6 max-w-4xl">
          Loans made{' '}
          <span className="gradient-text">simple</span>,<br />
          approvals made{' '}
          <span className="gradient-text">fast</span>
        </h1>

        <p className="text-xl text-muted-foreground max-w-2xl mb-10 leading-relaxed">
          Apply for personal, home, or business loans in minutes. AI-powered eligibility checks, 
          digital KYC, and real-time tracking — all in one place.
        </p>

        <div className="flex flex-col sm:flex-row items-center gap-4">
          <Link
            href="/login"
            className="flex items-center gap-2 px-8 py-4 rounded-2xl bg-gradient-to-r from-violet-600 to-purple-600 text-white font-bold text-lg btn-glow"
          >
            Apply Now <ArrowRight className="w-5 h-5" />
          </Link>
          <Link
            href="/login"
            className="flex items-center gap-2 px-8 py-4 rounded-2xl border border-border text-foreground font-semibold text-lg hover:bg-muted/40 transition-all"
          >
            Track Application <ChevronRight className="w-5 h-5" />
          </Link>
        </div>

        {/* Stats row */}
        <div className="flex flex-wrap items-center justify-center gap-8 mt-16 text-center">
          {[
            { value: '₹50Cr+', label: 'Loans Disbursed' },
            { value: '10,000+', label: 'Happy Customers' },
            { value: '< 48hrs', label: 'Avg Approval Time' },
            { value: '99.9%', label: 'Uptime' },
          ].map((stat) => (
            <div key={stat.label} className="flex flex-col items-center">
              <span className="text-3xl font-black gradient-text">{stat.value}</span>
              <span className="text-sm text-muted-foreground mt-1">{stat.label}</span>
            </div>
          ))}
        </div>
      </section>

      {/* Features */}
      <section className="px-6 pb-24 max-w-6xl mx-auto w-full">
        <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
          {[
            {
              icon: <Zap className="w-6 h-6 text-yellow-400" />,
              title: 'Instant Eligibility',
              desc: 'AI-powered scoring checks your eligibility in seconds with no paperwork.',
              color: 'from-yellow-500/10 to-orange-500/5',
              border: 'border-yellow-500/20',
            },
            {
              icon: <Shield className="w-6 h-6 text-violet-400" />,
              title: 'Digital KYC',
              desc: 'Face-based biometric verification via WhatsApp link. No branch visit needed.',
              color: 'from-violet-500/10 to-purple-500/5',
              border: 'border-violet-500/20',
            },
            {
              icon: <BarChart3 className="w-6 h-6 text-emerald-400" />,
              title: 'Real-time Tracking',
              desc: 'Track your loan status, EMI schedule, and chat with our AI assistant anytime.',
              color: 'from-emerald-500/10 to-teal-500/5',
              border: 'border-emerald-500/20',
            },
          ].map((f) => (
            <div
              key={f.title}
              className={`glass-card p-8 bg-gradient-to-br ${f.color} border ${f.border}`}
            >
              <div className="w-12 h-12 rounded-2xl bg-muted/60 flex items-center justify-center mb-5">
                {f.icon}
              </div>
              <h3 className="text-lg font-bold text-foreground mb-2">{f.title}</h3>
              <p className="text-muted-foreground text-sm leading-relaxed">{f.desc}</p>
            </div>
          ))}
        </div>

        {/* Loan types */}
        <div className="mt-12 glass-card p-8">
          <h2 className="text-2xl font-bold text-center mb-8">Loan Products</h2>
          <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
            {[
              { name: 'Personal Loan', range: 'Up to ₹25L', rate: '10.5%' },
              { name: 'Home Loan', range: 'Up to ₹5Cr', rate: '8.5%' },
              { name: 'Business Loan', range: 'Up to ₹50L', rate: '12%' },
              { name: 'Education Loan', range: 'Up to ₹75L', rate: '9%' },
            ].map((loan) => (
              <div key={loan.name} className="text-center p-5 rounded-xl bg-muted/40 border border-border hover:border-primary/30 transition-all">
                <CheckCircle className="w-8 h-8 text-primary mx-auto mb-3" />
                <p className="font-semibold text-sm mb-1">{loan.name}</p>
                <p className="text-xs text-muted-foreground">{loan.range}</p>
                <p className="text-xs text-primary font-medium mt-1">From {loan.rate}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Footer */}
      <footer className="border-t border-border px-6 py-8 text-center text-sm text-muted-foreground">
        © 2025 Shoonya Financial Services. All rights reserved.
      </footer>
    </main>
  )
}
