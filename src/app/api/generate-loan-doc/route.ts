import { NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'

export async function POST(req: Request) {
  try {
    const { loanId, userId, amount, rate, emi, tenure } = await req.json()

    const supabase = createClient(
      process.env.NEXT_PUBLIC_SUPABASE_URL!,
      process.env.SUPABASE_SERVICE_ROLE_KEY!
    )

    // Generate a simple Mock Sanction Letter Content (In production this would use a PDF library)
    // For now, we update the database and prepare for the PDF tab to show it
    
    const sanctionText = `LOAN SANCTION LETTER\n\nLoan ID: ${loanId}\nApproved Amount: ₹${amount}\nRate: ${rate}%\nEMI: ₹${emi}\nTenure: ${tenure} Months\n\nThis is an digitally signed document.`
    
    // We'll upload this as a metadata/text for now or a dummy PDF
    const { error: uploadError } = await supabase.storage
      .from('documents')
      .upload(`${userId}/sanction_letter_${loanId}.txt`, sanctionText, {
        contentType: 'text/plain',
        upsert: true
      })

    if (uploadError) throw uploadError

    return NextResponse.json({ success: true })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}
