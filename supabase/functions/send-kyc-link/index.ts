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
    const { userId, phone, name } = await req.json()

    if (!userId || !phone) {
      return new Response(
        JSON.stringify({ error: 'userId and phone are required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    )

    // Generate unique token
    const token = crypto.randomUUID().replace(/-/g, '')
    const kycLink = `${Deno.env.get('NEXT_PUBLIC_APP_URL')}/kyc/${token}`

    // Update kyc record with token
    const { error: dbError } = await supabase
      .from('kyc')
      .upsert({
        user_id: userId,
        kyc_link: token,
        status: 'link_sent',
        link_sent_at: new Date().toISOString(),
      }, { onConflict: 'user_id' })

    if (dbError) throw dbError

    // Send WhatsApp via Twilio
    const twilioSid = Deno.env.get('TWILIO_ACCOUNT_SID')!
    const twilioToken = Deno.env.get('TWILIO_AUTH_TOKEN')!
    const twilioFrom = Deno.env.get('TWILIO_WHATSAPP_FROM') || 'whatsapp:+14155238886'

    const message = `Hello ${name || 'there'} 👋\n\nYour KYC verification link for *Shoonya* is ready.\n\nClick here to verify: ${kycLink}\n\n⏰ This link expires in 24 hours.\n\n_Shoonya Financial Services_`

    const twilioResp = await fetch(
      `https://api.twilio.com/2010-04-01/Accounts/${twilioSid}/Messages.json`,
      {
        method: 'POST',
        headers: {
          'Authorization': `Basic ${btoa(`${twilioSid}:${twilioToken}`)}`,
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: new URLSearchParams({
          From: twilioFrom,
          To: `whatsapp:+91${phone}`,
          Body: message,
        }),
      }
    )

    const twilioData = await twilioResp.json()

    if (!twilioResp.ok) {
      throw new Error(`Twilio error: ${twilioData.message}`)
    }

    // Save message SID
    await supabase
      .from('kyc')
      .update({ wa_message_sid: twilioData.sid })
      .eq('user_id', userId)

    return new Response(
      JSON.stringify({ success: true, token, messageSid: twilioData.sid }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (err) {
    const error = err instanceof Error ? err.message : 'Unknown error'
    return new Response(
      JSON.stringify({ error }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
