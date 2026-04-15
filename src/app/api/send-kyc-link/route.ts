import { NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'

export async function POST(req: Request) {
  try {
    const { userId, phone, name } = await req.json()

    if (!userId || !phone) {
      return NextResponse.json({ error: 'userId and phone are required' }, { status: 400 })
    }

    const supabase = createClient(
      process.env.NEXT_PUBLIC_SUPABASE_URL!,
      process.env.SUPABASE_SERVICE_ROLE_KEY!
    )

    // Generate unique token
    const token = crypto.randomUUID().replace(/-/g, '')
    const kycLink = `${process.env.NEXT_PUBLIC_APP_URL || 'http://localhost:3000'}/kyc/${token}`

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

    // Strictly clean and trim all credentials
    const twilioSid = (process.env.TWILIO_ACCOUNT_SID || '').trim()
    const twilioToken = (process.env.TWILIO_AUTH_TOKEN || '').trim()
    const rawTwilioFrom = (process.env.TWILIO_WHATSAPP_FROM || 'whatsapp:+14155238886').trim()
    const twilioFrom = rawTwilioFrom.startsWith('whatsapp:') ? rawTwilioFrom : `whatsapp:${rawTwilioFrom}`

    if (!twilioSid || !twilioToken || twilioSid === 'your_twilio_account_sid' || !twilioSid.startsWith('AC')) {
       // Return a mock success if Twilio isn't properly configured yet
       console.log(`[MOCK WHATSAPP SENT to ${phone}]: ${kycLink}`)
       return NextResponse.json({ success: true, token, messageSid: 'mock_sid_for_testing' })
    }

    const message = `Hello ${name || 'there'} 👋\n\nYour KYC verification link for *Shoonya* is ready.\n\nClick here to verify: ${kycLink}\n\n⏰ This link expires in 24 hours.\n\n_Shoonya Financial Services_`

    // Clean the phone number (remove any non-digit characters)
    const cleanPhone = phone.replace(/\D/g, '')
    
    // Formatting logic for Indian numbers:
    // 1. If it's 10 digits, it's a raw mobile number, add +91
    // 2. If it's 12 digits and starts with 91, it already has the country code
    let formattedTo = ''
    if (cleanPhone.length === 10) {
      formattedTo = `whatsapp:+91${cleanPhone}`
    } else if (cleanPhone.length === 12 && cleanPhone.startsWith('91')) {
      formattedTo = `whatsapp:+${cleanPhone}`
    } else {
      // Fallback for other formats
      formattedTo = `whatsapp:+${cleanPhone.startsWith('+') ? cleanPhone.slice(1) : cleanPhone}`
    }

    const twilioResp = await fetch(
      `https://api.twilio.com/2010-04-01/Accounts/${twilioSid}/Messages.json`,
      {
        method: 'POST',
        headers: {
          'Authorization': `Basic ${Buffer.from(`${twilioSid}:${twilioToken}`).toString('base64')}`,
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: new URLSearchParams({
          From: twilioFrom,
          To: formattedTo,
          Body: message,
        }),
      }
    )

    const twilioData = await twilioResp.json()

    if (!twilioResp.ok) {
      console.error('Twilio Error:', twilioData)
      console.log(`[MOCK WHATSAPP FALLBACK]: The link generated is ${kycLink}`)
      // Do not throw, just allow the UI to succeed so testing can continue
      return NextResponse.json({ 
        success: true, 
        token, 
        warning: `Twilio failed (${twilioData.message}), but KYC link was generated locally.`
      })
    }

    // Save message SID
    await supabase
      .from('kyc')
      .update({ wa_message_sid: twilioData.sid })
      .eq('user_id', userId)

    return NextResponse.json({ success: true, token, messageSid: twilioData.sid })
  } catch (error: any) {
    console.error('API Error:', error)
    return NextResponse.json({ error: error.message || 'Unknown error' }, { status: 500 })
  }
}
