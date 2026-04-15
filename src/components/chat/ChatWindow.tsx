'use client'

import { useState, useRef, useEffect } from 'react'
import { Profile, Loan, ChatMessage } from '@/lib/types'
import { formatCurrency, formatRelativeTime } from '@/lib/utils'
import { Send, Bot, Loader2, Sparkles } from 'lucide-react'
import { createClient } from '@/lib/supabase/client'
import { toast } from 'sonner'

type Props = {
  profile: Profile
  loans: Loan[]
}

const QUICK_PROMPTS = [
  'What is my loan status?',
  'How is my EMI calculated?',
  'When will my loan be approved?',
  'What documents are needed?',
]

export default function ChatWindow({ profile, loans }: Props) {
  const [messages, setMessages] = useState<ChatMessage[]>([
    {
      id: '1',
      role: 'assistant',
      content: `Hi ${profile.full_name?.split(' ')[0]}! 👋 I'm your Shoonya Loan Assistant. I can help you with loan eligibility, EMI calculations, application status, and more. What would you like to know?`,
      timestamp: new Date(),
    },
  ])
  const [input, setInput] = useState('')
  const [loading, setLoading] = useState(false)
  const messagesEndRef = useRef<HTMLDivElement>(null)
  const supabase = createClient()

  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [messages])

  const sendMessage = async (text?: string) => {
    const messageText = text || input.trim()
    if (!messageText || loading) return

    const userMessage: ChatMessage = {
      id: Date.now().toString(),
      role: 'user',
      content: messageText,
      timestamp: new Date(),
    }

    setMessages(prev => [...prev, userMessage])
    setInput('')
    setLoading(true)

    try {
      const res = await fetch('/api/chat', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          message: messageText,
          userId: profile.id,
          loans: loans.map(l => ({
            type: l.loan_type,
            amount: l.amount_requested,
            status: l.status,
            emi: l.emi_amount,
            rate: l.interest_rate,
          })),
        }),
      })

      const data = await res.json()
      if (!res.ok) throw new Error(data.error || 'Failed to chat')

      const aiMessage: ChatMessage = {
        id: (Date.now() + 1).toString(),
        role: 'assistant',
        content: data.reply || "I'm sorry, I couldn't process that. Please try again.",
        timestamp: new Date(),
      }

      setMessages(prev => [...prev, aiMessage])
    } catch {
      // Fallback response if edge function not set up
      const fallbacks: Record<string, string> = {
        status: loans.length > 0
          ? `You have ${loans.length} loan(s). ${loans.filter(l => l.status === 'approved').length} approved, ${loans.filter(l => l.status === 'pending').length} pending.`
          : "You haven't applied for any loans yet. Would you like to apply now?",
        emi: 'EMI = P × r × (1+r)^n / ((1+r)^n - 1), where P is principal, r is monthly rate, n is tenure in months.',
        kyc: 'Our admin team will send you a KYC verification link on WhatsApp. Please ensure your number is registered.',
        document: 'We need: PAN card, Aadhaar, last 3 months salary slips, and 6 months bank statements.',
      }

      const key = Object.keys(fallbacks).find(k => messageText.toLowerCase().includes(k))
      const reply = key ? fallbacks[key] : `Thank you for your question about "${messageText}". Our AI assistant is being configured. Please contact support for immediate help.`

      setMessages(prev => [...prev, {
        id: (Date.now() + 1).toString(),
        role: 'assistant',
        content: reply,
        timestamp: new Date(),
      }])
    } finally {
      setLoading(false)
    }
  }

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault()
      sendMessage()
    }
  }

  return (
    <div className="glass-card flex flex-col" style={{ height: '70vh' }}>
      {/* Chat header */}
      <div className="flex items-center gap-3 p-4 border-b border-border">
        <div className="w-10 h-10 rounded-full bg-gradient-to-br from-violet-500 to-purple-600 flex items-center justify-center">
          <Bot className="w-5 h-5 text-white" />
        </div>
        <div>
          <p className="font-semibold text-sm">Shoonya AI Assistant</p>
          <div className="flex items-center gap-1.5">
            <div className="w-2 h-2 rounded-full bg-emerald-400 animate-pulse" />
            <span className="text-xs text-emerald-400">Online</span>
          </div>
        </div>
        <div className="ml-auto flex items-center gap-1 px-3 py-1 rounded-full bg-primary/10 border border-primary/20">
          <Sparkles className="w-3 h-3 text-primary" />
          <span className="text-xs text-primary font-medium">AI Powered</span>
        </div>
      </div>

      {/* Messages */}
      <div className="flex-1 overflow-y-auto p-4 space-y-4">
        {messages.map((msg) => (
          <div key={msg.id} className={`flex gap-3 ${msg.role === 'user' ? 'flex-row-reverse' : 'flex-row'}`}>
            {msg.role === 'assistant' && (
              <div className="w-8 h-8 rounded-full bg-gradient-to-br from-violet-500 to-purple-600 flex items-center justify-center flex-shrink-0 mt-1">
                <Bot className="w-4 h-4 text-white" />
              </div>
            )}
            <div className={msg.role === 'user' ? 'chat-bubble-user' : 'chat-bubble-ai'}>
              <p className="leading-relaxed">{msg.content}</p>
              <p className={`text-[10px] mt-1 ${msg.role === 'user' ? 'text-white/60' : 'text-muted-foreground'}`}>
                {formatRelativeTime(msg.timestamp.toISOString())}
              </p>
            </div>
          </div>
        ))}

        {loading && (
          <div className="flex gap-3">
            <div className="w-8 h-8 rounded-full bg-gradient-to-br from-violet-500 to-purple-600 flex items-center justify-center flex-shrink-0">
              <Bot className="w-4 h-4 text-white" />
            </div>
            <div className="chat-bubble-ai flex items-center gap-2">
              <Loader2 className="w-4 h-4 animate-spin text-primary" />
              <span className="text-sm text-muted-foreground">Thinking...</span>
            </div>
          </div>
        )}
        <div ref={messagesEndRef} />
      </div>

      {/* Quick prompts */}
      {messages.length <= 2 && (
        <div className="px-4 pb-3 flex flex-wrap gap-2">
          {QUICK_PROMPTS.map((prompt) => (
            <button
              key={prompt}
              onClick={() => sendMessage(prompt)}
              className="text-xs px-3 py-1.5 rounded-full border border-border bg-muted/40 hover:bg-muted text-muted-foreground hover:text-foreground transition-all"
            >
              {prompt}
            </button>
          ))}
        </div>
      )}

      {/* Input */}
      <div className="p-4 border-t border-border">
        <div className="flex gap-3">
          <input
            value={input}
            onChange={(e) => setInput(e.target.value)}
            onKeyDown={handleKeyDown}
            placeholder="Ask about your loans, EMI, eligibility..."
            className="input-dark flex-1 py-2"
            disabled={loading}
          />
          <button
            onClick={() => sendMessage()}
            disabled={!input.trim() || loading}
            className="w-10 h-10 rounded-xl bg-gradient-to-r from-violet-600 to-purple-600 flex items-center justify-center text-white disabled:opacity-50 disabled:cursor-not-allowed btn-glow transition-all"
          >
            <Send className="w-4 h-4" />
          </button>
        </div>
        <p className="text-[10px] text-muted-foreground mt-2 text-center">
          Scoped to loan queries only. Powered by AI — always verify critical info.
        </p>
      </div>
    </div>
  )
}
