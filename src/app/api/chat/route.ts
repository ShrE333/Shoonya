import { NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'

export async function POST(req: Request) {
  try {
    const { message, userId, loans } = await req.json()

    if (!message || !userId) {
      return NextResponse.json({ error: 'message and userId are required' }, { status: 400 })
    }

    const supabase = createClient(
      process.env.NEXT_PUBLIC_SUPABASE_URL!,
      process.env.SUPABASE_SERVICE_ROLE_KEY!
    )

    // Fetch user profile for context
    const { data: profile } = await supabase
      .from('profiles')
      .select('full_name, monthly_income, employment_type')
      .eq('id', userId)
      .single()

    // Fetch KYC status
    const { data: kyc } = await supabase
      .from('kyc')
      .select('status')
      .eq('user_id', userId)
      .single()

    // Build system context
    const loansContext = loans && loans.length > 0
      ? `User's active loans:\n${loans.map((l: any) =>
          `- ${l.loan_type}: ₹${l.amount_requested.toLocaleString('en-IN')}, Status: ${l.status}`
        ).join('\n')}`
      : 'User has no active loans.'

    const systemPrompt = `You are a strict, helpful loan assistant for Shoonya Financial Services, an Indian NBFC. 
You MUST ONLY answer questions related to loans, EMI, eligibility, KYC, and financial topics specific to Shoonya.
If the user asks ANYTHING unrelated to loans, finance, or your identity, YOU MUST politely refuse to answer and redirect them to banking topics. Do not attempt to answer off-topic queries under any circumstances.

User context:
- Name: ${profile?.full_name || 'Customer'}
- Employment: ${profile?.employment_type || 'Unknown'}
- Monthly Income: ₹${profile?.monthly_income?.toLocaleString('en-IN') || 'Not provided'}
- KYC Status: ${kyc?.status || 'pending'}
- ${loansContext}

Response guidelines:
- Be concise and friendly
- Use Indian currency format (₹, Lakhs, Crores)
- Mention EMI calculations when relevant
- Keep responses strictly under 100 words`

    const groqKey = process.env.GROQ_API_KEY
    if (!groqKey || groqKey === 'your_groq_api_key') {
       return NextResponse.json({ reply: '[Mock API Response]: Your Groq API key is missing from .env.local, but your request was perfectly received!' })
    }

    const groqResp = await fetch('https://api.groq.com/openai/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${groqKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: 'llama-3.1-8b-instant',
        messages: [
          { role: 'system', content: systemPrompt },
          { role: 'user', content: message },
        ],
        max_tokens: 300,
        temperature: 0.7,
      }),
    })

    const groqData = await groqResp.json()

    if (!groqResp.ok) {
      throw new Error(groqData.error?.message || 'Groq API error')
    }

    const reply = groqData.choices?.[0]?.message?.content || 
      "I'm sorry, I couldn't process your request. Please try again."

    return NextResponse.json({ reply })
  } catch (error: any) {
    return NextResponse.json({ error: error.message, reply: 'Our AI assistant is temporarily unavailable.' }, { status: 500 })
  }
}
