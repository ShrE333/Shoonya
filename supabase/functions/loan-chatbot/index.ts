import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { message, userId, loans } = await req.json()

    if (!message || !userId) {
      return new Response(
        JSON.stringify({ error: 'message and userId are required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
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
      ? `User's active loans:\n${loans.map((l: { type: string; amount: number; status: string; emi: number | null; rate: number | null }) =>
          `- ${l.type}: ₹${l.amount.toLocaleString('en-IN')}, Status: ${l.status}${l.emi ? `, EMI: ₹${l.emi}` : ''}${l.rate ? `, Rate: ${l.rate}%` : ''}`
        ).join('\n')}`
      : 'User has no active loans.'

    const systemPrompt = `You are a helpful loan assistant for Shoonya Financial Services, an Indian NBFC. 
You only answer questions related to loans, EMI, eligibility, KYC, and financial topics specific to Shoonya.
If asked anything unrelated to loans or finance, politely decline and redirect.

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
- Always recommend completing KYC for better rates
- Keep responses under 150 words`

    // Call OpenAI
    const openaiResp = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${Deno.env.get('OPENAI_API_KEY')}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: 'gpt-4o-mini',
        messages: [
          { role: 'system', content: systemPrompt },
          { role: 'user', content: message },
        ],
        max_tokens: 300,
        temperature: 0.7,
      }),
    })

    const openaiData = await openaiResp.json()

    if (!openaiResp.ok) {
      throw new Error(openaiData.error?.message || 'OpenAI API error')
    }

    const reply = openaiData.choices?.[0]?.message?.content || 
      "I'm sorry, I couldn't process your request. Please try again."

    return new Response(
      JSON.stringify({ reply }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (err) {
    const error = err instanceof Error ? err.message : 'Unknown error'
    return new Response(
      JSON.stringify({ error, reply: 'Our AI assistant is temporarily unavailable. Please try again later.' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
