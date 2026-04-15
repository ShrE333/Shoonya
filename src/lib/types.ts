export type Profile = {
  id: string
  full_name: string | null
  email: string | null
  phone: string | null
  age: number | null
  address: string | null
  city: string | null
  state: string | null
  pincode: string | null
  pan_number: string | null
  aadhar_number: string | null
  monthly_income: number | null
  employment_type: string | null
  role: 'user' | 'admin'
  created_at: string
}

export type Loan = {
  id: string
  user_id: string
  loan_type: string
  amount_requested: number
  tenure_months: number
  purpose: string
  status: 'pending' | 'under_review' | 'approved' | 'rejected'
  eligibility_score: number | null
  approved_amount: number | null
  interest_rate: number | null
  emi_amount: number | null
  remarks: string | null
  created_at: string
  updated_at: string
}

export type KYC = {
  id: string
  user_id: string
  status: 'pending' | 'link_sent' | 'completed' | 'failed' | 'verified'
  kyc_link: string | null
  link_sent_at: string | null
  wa_message_sid: string | null
  selfie_url: string | null
  face_age_estimate: number | null
  face_gender: string | null
  liveness_score: number | null
  location_lat: number | null
  location_lng: number | null
  completed_at: string | null
  verified_by: string | null
  created_at: string
}

export type ChatMessage = {
  id: string
  role: 'user' | 'assistant'
  content: string
  timestamp: Date
}

export type LoanWithProfile = Loan & {
  profiles: Profile
}

export type KYCWithProfile = KYC & {
  profiles: Profile
}
