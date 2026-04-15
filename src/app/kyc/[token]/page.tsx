'use client'

import { useEffect } from 'react'
import { useParams } from 'next/navigation'
import { ExternalLink, ShieldAlert } from 'lucide-react'

export default function KYCRedirectPage() {
  const params = useParams()
  const token = params.token as string

  useEffect(() => {
    // Attempt automatic redirect to the Flutter app via custom scheme
    if (token) {
      setTimeout(() => {
        window.location.href = `shoonya://kyc/${token}`;
      }, 500);
    }
  }, [token])

  const handleManualRedirect = () => {
    window.location.href = `shoonya://kyc/${token}`;
  }

  return (
    <div className="min-h-screen mesh-bg flex flex-col items-center justify-center p-4">
      {/* Logo */}
      <div className="flex items-center gap-3 mb-8">
        <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-violet-500 to-purple-600 flex items-center justify-center">
          <span className="text-white font-bold">S</span>
        </div>
        <span className="text-2xl font-bold gradient-text">Shoonya KYC</span>
      </div>

      <div className="w-full max-w-md">
        <div className="glass-card p-10 text-center">
          <div className="w-20 h-20 rounded-full bg-primary/20 flex items-center justify-center mx-auto mb-6">
            <ShieldAlert className="w-10 h-10 text-primary" />
          </div>
          <h2 className="text-xl font-bold mb-3">Open in Shoonya App</h2>
          <p className="text-muted-foreground text-sm mb-8">
            For security and optimal face detection, the KYC verification must be completed securely within the Shoonya mobile application.
          </p>
          
          <button
            onClick={handleManualRedirect}
            className="w-full py-4 rounded-xl bg-gradient-to-r from-violet-600 to-purple-600 text-white font-bold btn-glow flex items-center justify-center gap-2"
          >
            <span>Open App to Verify</span>
            <ExternalLink className="w-5 h-5" />
          </button>
        </div>
      </div>
    </div>
  )
}
