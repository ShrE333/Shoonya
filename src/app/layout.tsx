import type { Metadata } from 'next'
import { Inter } from 'next/font/google'
import './globals.css'
import { Toaster } from 'sonner'

const inter = Inter({ subsets: ['latin'] })

export const metadata: Metadata = {
  title: 'Shoonya — Smart Loan Platform',
  description: 'Apply for loans, complete KYC, and track your loan status with Shoonya.',
  keywords: 'loan, bank, KYC, EMI, personal loan, home loan, business loan',
}

export default function RootLayout({
  children,
}: {
  children: React.ReactNode
}) {
  return (
    <html lang="en" className="dark">
      <body className={inter.className}>
        {children}
        <Toaster position="top-right" richColors theme="dark" />
      </body>
    </html>
  )
}
