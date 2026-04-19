'use client'

import { useEffect, useState } from 'react'
import { createClient } from '@/lib/supabase/client'
import { useRouter } from 'next/navigation'
import { LogIn, Shield, Zap, BarChart3, Loader2, Mail, Lock, ChevronRight } from 'lucide-react'
import { toast } from 'sonner'
import Image from 'next/image'

export default function LoginPage() {
  const [loading, setLoading] = useState(false)
  const [isSignUp, setIsSignUp] = useState(false)
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const supabase = createClient()
  const router = useRouter()

  useEffect(() => {
    const checkSession = async () => {
      const { data: { session } } = await supabase.auth.getSession()
      if (session) router.push('/dashboard')
    }
    checkSession()
  }, [supabase, router])

  const handleEmailAuth = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!email || !password) {
      toast.error('Please enter both email and password.')
      return
    }

    setLoading(true)
    try {
      if (isSignUp) {
        const { error, data } = await supabase.auth.signUp({
          email,
          password,
          options: {
            emailRedirectTo: `${process.env.NEXT_PUBLIC_APP_URL || window.location.origin}/auth/callback`,
          },
        })
        if (error) throw error
        if (data.session) {
           router.push('/auth/callback')
        } else {
           toast.success('Check your email for the confirmation link!')
           setEmail('')
           setPassword('')
        }
      } else {
        const { error } = await supabase.auth.signInWithPassword({
          email,
          password,
        })
        if (error) throw error
        router.push('/auth/callback')
      }
    } catch (error: any) {
      toast.error(error.message || 'Authentication failed.')
    } finally {
      setLoading(false)
    }
  }

  const handleGoogleLogin = async () => {
    setLoading(true)
    try {
      const { error } = await supabase.auth.signInWithOAuth({
        provider: 'google',
        options: {
          redirectTo: `${process.env.NEXT_PUBLIC_APP_URL || window.location.origin}/auth/callback`,
        },
      })
      if (error) throw error
    } catch (error: unknown) {
      const errorMessage = error instanceof Error ? error.message : 'Login failed. Please try again.'
      toast.error(errorMessage)
      setLoading(false)
    }
  }

  return (
    <div className="min-h-screen bg-[#020617] flex relative overflow-hidden">
      {/* Dynamic Background Elements */}
      <div className="absolute top-[-10%] left-[-10%] w-[40%] h-[40%] bg-emerald-500/10 blur-[120px] rounded-full"></div>
      <div className="absolute bottom-[-10%] right-[-10%] w-[40%] h-[40%] bg-violet-500/10 blur-[120px] rounded-full"></div>
      
      {/* Left panel - Premium Branding */}
      <div className="hidden lg:flex flex-col justify-between w-[55%] p-16 relative z-10">
        <div className="flex items-center gap-4">
          <div className="relative group">
            <div className="absolute -inset-1 bg-gradient-to-r from-emerald-500 to-teal-600 rounded-2xl blur opacity-25 group-hover:opacity-50 transition duration-1000 group-hover:duration-200"></div>
            <div className="relative w-14 h-14 rounded-2xl bg-slate-900 border border-slate-800 flex items-center justify-center overflow-hidden">
              <Image src="/logo.png" alt="Shoonya Logo" width={44} height={44} className="object-contain" />
            </div>
          </div>
          <div>
            <span className="text-2xl font-black text-white tracking-tighter">SHOONYA</span>
            <div className="px-2 py-0.5 rounded-full bg-emerald-500/10 border border-emerald-500/20 text-[10px] font-bold text-emerald-500 w-fit">FINTECH AI</div>
          </div>
        </div>

        <div>
          <h1 className="text-6xl font-black text-white mb-6 leading-[1.1] tracking-tight">
            Institutional Grade<br />
            <span className="text-transparent bg-clip-text bg-gradient-to-r from-emerald-400 to-teal-300">Loan Intelligence</span>
          </h1>
          <p className="text-slate-400 text-xl mb-12 max-w-xl leading-relaxed">
            Experience the future of zero-friction lending with our AI-driven identity protocol and instant credit evaluation engine.
          </p>

          <div className="grid grid-cols-2 gap-6 max-w-2xl">
            {[
              {
                icon: <Zap className="w-5 h-5 text-emerald-400" />,
                title: 'Instant Processing',
                desc: 'Eligibility in < 60s',
                border: 'border-emerald-500/10'
              },
              {
                icon: <Shield className="w-5 h-5 text-violet-400" />,
                title: 'Military Security',
                desc: 'End-to-end encryption',
                border: 'border-violet-500/10'
              }
            ].map((item) => (
              <div key={item.title} className={`p-6 rounded-3xl bg-slate-900/40 border ${item.border} backdrop-blur-sm group hover:bg-slate-900/60 transition-all cursor-default`}>
                <div className="w-10 h-10 rounded-xl bg-slate-800/50 flex items-center justify-center mb-4 group-hover:scale-110 transition-transform">
                  {item.icon}
                </div>
                <p className="font-bold text-white text-sm mb-1">{item.title}</p>
                <p className="text-slate-500 text-xs leading-relaxed">{item.desc}</p>
              </div>
            ))}
          </div>
        </div>

        <div className="flex items-center gap-6">
          <p className="text-xs text-slate-500 font-medium tracking-widest uppercase">
            © 2025 SHOONYA FINANCIAL SERVICES | RBI REGISTERED
          </p>
        </div>
      </div>

      {/* Right panel - Glass Auth Terminal */}
      <div className="flex-1 flex items-center justify-center p-6 relative z-10">
        <div className="w-full max-w-[440px]">
          {/* Mobile logo */}
          <div className="flex items-center gap-4 mb-10 lg:hidden px-4">
            <div className="w-12 h-12 rounded-2xl bg-slate-900 border border-slate-800 flex items-center justify-center overflow-hidden shadow-2xl">
              <Image src="/logo.png" alt="Shoonya Logo" width={36} height={36} className="object-contain" />
            </div>
            <span className="text-2xl font-black text-white tracking-tighter uppercase">Shoonya</span>
          </div>

          <div className="relative">
            {/* Background Glow */}
            <div className="absolute inset-0 bg-emerald-500/5 blur-3xl rounded-full"></div>
            
            <div className="relative p-10 rounded-[40px] bg-slate-900/50 border border-slate-800/50 backdrop-blur-2xl shadow-2xl">
              <div className="mb-10 text-center lg:text-left">
                <h2 className="text-3xl font-black text-white mb-3 tracking-tight">
                  {isSignUp ? 'Create Account' : 'Access Terminal'}
                </h2>
                <p className="text-slate-500 text-sm font-medium">
                  {isSignUp 
                    ? 'Initialize your financial identity' 
                    : 'System authorization required to proceed'}
                </p>
              </div>

              <form onSubmit={handleEmailAuth} className="space-y-5 mb-8">
                <div>
                  <div className="relative group">
                    <Mail className="absolute left-4 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-500 group-focus-within:text-emerald-400 transition-colors" />
                    <input
                      type="email"
                      value={email}
                      onChange={(e) => setEmail(e.target.value)}
                      placeholder="Corporate Email"
                      className="w-full bg-slate-950/50 border border-slate-800 rounded-2xl pl-12 pr-4 py-4 text-white text-sm focus:border-emerald-500/50 focus:ring-4 focus:ring-emerald-500/10 transition-all outline-none placeholder:text-slate-700"
                      required
                    />
                  </div>
                </div>

                <div>
                  <div className="relative group">
                    <Lock className="absolute left-4 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-500 group-focus-within:text-emerald-400 transition-colors" />
                    <input
                      type="password"
                      value={password}
                      onChange={(e) => setPassword(e.target.value)}
                      placeholder="Access Token / Password"
                      minLength={6}
                      className="w-full bg-slate-950/50 border border-slate-800 rounded-2xl pl-12 pr-4 py-4 text-white text-sm focus:border-emerald-500/50 focus:ring-4 focus:ring-emerald-500/10 transition-all outline-none placeholder:text-slate-700"
                      required
                    />
                  </div>
                </div>

                <button
                  type="submit"
                  disabled={loading}
                  className="w-full flex items-center justify-center gap-3 px-6 py-4 rounded-2xl bg-gradient-to-r from-emerald-600 to-teal-600 text-white font-bold text-sm hover:translate-y-[-2px] hover:shadow-[0_8px_30px_rgb(16,185,129,0.3)] transition-all duration-300 disabled:opacity-70 disabled:cursor-not-allowed mt-4 active:scale-95"
                >
                  {loading ? <Loader2 className="w-5 h-5 animate-spin" /> : null}
                  {loading ? 'AUTHORIZING...' : (isSignUp ? 'INITIALIZE IDENTITY' : 'AUTHORIZE ACCESS')}
                </button>
              </form>

              <div className="relative flex items-center gap-4 mb-8">
                <div className="h-px bg-slate-800 flex-1"></div>
                <span className="text-[10px] text-slate-600 uppercase font-black tracking-widest">Secure Channels</span>
                <div className="h-px bg-slate-800 flex-1"></div>
              </div>

              <button
                type="button"
                onClick={handleGoogleLogin}
                disabled={loading}
                className="w-full flex items-center justify-center gap-3 px-6 py-4 rounded-2xl bg-white text-slate-950 font-bold text-sm hover:bg-slate-100 transition-all duration-300 disabled:opacity-70 active:scale-95 shadow-xl shadow-white/5"
              >
                <LogIn className="w-5 h-5" />
                Google Authenticator
              </button>

              <div className="mt-10 text-center">
                <button
                  type="button"
                  onClick={() => setIsSignUp(!isSignUp)}
                  className="group flex items-center justify-center gap-2 mx-auto text-sm font-bold text-slate-400 hover:text-white transition-colors"
                >
                  {isSignUp 
                    ? 'Already part of the network? Sign in' 
                    : "Need institutional access? Request entry"}
                  <ChevronRight className="w-4 h-4 group-hover:translate-x-1 transition-transform" />
                </button>
              </div>
            </div>
            
            <div className="mt-8 flex items-center justify-center gap-2 px-6 py-3 rounded-2xl bg-emerald-500/5 border border-emerald-500/10">
              <Shield className="w-3.5 h-3.5 text-emerald-500" />
              <p className="text-[10px] text-emerald-500/80 font-black tracking-widest uppercase">
                End-to-End Encrypted Terminal
              </p>
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}
