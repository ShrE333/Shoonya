'use client'

import { useEffect, useState } from 'react'
import { createClient } from '@/lib/supabase/client'
import { useRouter } from 'next/navigation'
import { LogIn, Shield, Zap, BarChart3, Loader2, Mail, Lock } from 'lucide-react'
import { toast } from 'sonner'

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
            emailRedirectTo: `${window.location.origin}/auth/callback`,
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
          redirectTo: `${window.location.origin}/auth/callback`,
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
    <div className="min-h-screen mesh-bg flex">
      {/* Left panel - marketing */}
      <div className="hidden lg:flex flex-col justify-between w-1/2 p-12 border-r border-border">
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-violet-500 to-purple-600 flex items-center justify-center">
            <span className="text-white font-bold">S</span>
          </div>
          <span className="text-2xl font-bold gradient-text">Shoonya</span>
        </div>

        <div>
          <h1 className="text-4xl font-black text-foreground mb-4 leading-tight">
            Your financial future<br />
            <span className="gradient-text">starts here</span>
          </h1>
          <p className="text-muted-foreground text-lg mb-10">
            Smart loans. Fast approvals. Digital-first experience.
          </p>

          <div className="space-y-6">
            {[
              {
                icon: <Zap className="w-5 h-5 text-yellow-400" />,
                title: 'Instant eligibility check',
                desc: 'Know your loan eligibility in under 60 seconds',
              },
              {
                icon: <Shield className="w-5 h-5 text-violet-400" />,
                title: 'Secure digital KYC',
                desc: 'Biometric verification from your phone',
              },
              {
                icon: <BarChart3 className="w-5 h-5 text-emerald-400" />,
                title: 'AI Loan Assistant',
                desc: 'Get instant answers to all your loan queries',
              },
            ].map((item) => (
              <div key={item.title} className="flex items-start gap-4">
                <div className="w-10 h-10 rounded-xl bg-muted/60 flex items-center justify-center flex-shrink-0">
                  {item.icon}
                </div>
                <div>
                  <p className="font-semibold text-sm">{item.title}</p>
                  <p className="text-muted-foreground text-sm">{item.desc}</p>
                </div>
              </div>
            ))}
          </div>
        </div>

        <p className="text-xs text-muted-foreground">
          © 2025 Shoonya Financial Services. RBI registered NBFC.
        </p>
      </div>

      {/* Right panel - login */}
      <div className="flex-1 flex items-center justify-center p-8">
        <div className="w-full max-w-md">
          {/* Mobile logo */}
          <div className="flex items-center gap-3 mb-10 lg:hidden">
            <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-violet-500 to-purple-600 flex items-center justify-center">
              <span className="text-white font-bold">S</span>
            </div>
            <span className="text-2xl font-bold gradient-text">Shoonya</span>
          </div>

          <div className="glass-card p-8 gradient-border">
            <div className="mb-6">
              <h2 className="text-2xl font-bold text-foreground mb-2">
                {isSignUp ? 'Create an account' : 'Welcome back'}
              </h2>
              <p className="text-muted-foreground text-sm">
                {isSignUp 
                  ? 'Sign up to apply for and track your loans' 
                  : 'Sign in to manage your loans and track applications'}
              </p>
            </div>

            <form onSubmit={handleEmailAuth} className="space-y-4 mb-6">
              <div>
                <label className="block text-sm font-medium mb-1 flex items-center gap-2 text-muted-foreground">
                   Email
                </label>
                <div className="relative">
                  <Mail className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
                  <input
                    type="email"
                    value={email}
                    onChange={(e) => setEmail(e.target.value)}
                    placeholder="name@example.com"
                    className="input-dark pl-10 py-2.5"
                    required
                  />
                </div>
              </div>

              <div>
                <label className="block text-sm font-medium mb-1 flex items-center gap-2 text-muted-foreground">
                   Password
                </label>
                <div className="relative">
                  <Lock className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
                  <input
                    type="password"
                    value={password}
                    onChange={(e) => setPassword(e.target.value)}
                    placeholder="••••••••"
                    minLength={6}
                    className="input-dark pl-10 py-2.5"
                    required
                  />
                </div>
              </div>

              <button
                type="submit"
                disabled={loading}
                className="w-full flex items-center justify-center gap-3 px-6 py-3 rounded-xl bg-gradient-to-r from-violet-600 to-purple-600 text-white font-semibold text-sm hover:opacity-90 transition-all duration-200 disabled:opacity-70 disabled:cursor-not-allowed btn-glow mt-2"
              >
                {loading ? <Loader2 className="w-5 h-5 animate-spin" /> : null}
                {loading ? 'Processing...' : (isSignUp ? 'Sign Up' : 'Sign In')}
              </button>
            </form>

            <div className="flex items-center gap-3 mb-6">
              <div className="h-px bg-border flex-1"></div>
              <span className="text-xs text-muted-foreground uppercase font-medium">Or continue with</span>
              <div className="h-px bg-border flex-1"></div>
            </div>

            <button
              type="button"
              onClick={handleGoogleLogin}
              disabled={loading}
              className="w-full flex items-center justify-center gap-3 px-6 py-3 rounded-xl bg-white text-gray-900 font-semibold text-sm hover:bg-gray-100 transition-all duration-200 disabled:opacity-70 disabled:cursor-not-allowed border border-transparent shadow-sm hover:shadow-md"
            >
              <LogIn className="w-5 h-5" />
              Google
            </button>

            <div className="mt-8 text-center">
              <button
                type="button"
                onClick={() => setIsSignUp(!isSignUp)}
                className="text-sm font-medium hover:text-primary transition-colors text-muted-foreground"
              >
                {isSignUp 
                  ? 'Already have an account? Sign in' 
                  : "Don't have an account? Sign up"}
              </button>
            </div>
            
            <div className="mt-6 p-4 rounded-xl bg-muted/40 border border-border">
              <p className="text-xs text-muted-foreground text-center">
                🔒 Your data is fully encrypted.
              </p>
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}
