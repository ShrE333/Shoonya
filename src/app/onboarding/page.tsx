'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import { toast } from 'sonner'
import { 
  User, Phone, Briefcase, CheckCircle, ChevronRight, 
  ChevronLeft, Loader2, MapPin, CreditCard 
} from 'lucide-react'
import { cn } from '@/lib/utils'

const step1Schema = z.object({
  full_name: z.string().min(2, 'Full name must be at least 2 characters'),
  age: z.number().min(18, 'Must be at least 18 years old').max(70, 'Must be under 70'),
  gender: z.string().min(1, 'Please select gender'),
  address: z.string().min(5, 'Enter a valid address'),
  city: z.string().min(2, 'Enter city'),
  state: z.string().min(2, 'Enter state'),
  pincode: z.string().regex(/^\d{6}$/, 'Enter valid 6-digit pincode'),
})

const step2Schema = z.object({
  phone: z.string().regex(/^[6-9]\d{9}$/, 'Enter valid 10-digit mobile number'),
  alternate_phone: z.string().regex(/^[6-9]\d{9}$/, 'Enter valid number').optional().or(z.literal('')),
})

const step3Schema = z.object({
  employment_type: z.string().min(1, 'Select employment type'),
  monthly_income: z.number().min(5000, 'Minimum income ₹5,000'),
  pan_number: z.string().regex(/^[A-Z]{5}[0-9]{4}[A-Z]{1}$/, 'Enter valid PAN (e.g. ABCDE1234F)'),
  aadhar_number: z.string().regex(/^\d{12}$/, 'Enter valid 12-digit Aadhaar'),
})

type Step1Data = z.infer<typeof step1Schema>
type Step2Data = z.infer<typeof step2Schema>
type Step3Data = z.infer<typeof step3Schema>

type FormData = Step1Data & Step2Data & Step3Data

const STEPS = [
  { id: 1, title: 'Personal Info', icon: User },
  { id: 2, title: 'Contact', icon: Phone },
  { id: 3, title: 'Financial', icon: Briefcase },
  { id: 4, title: 'Review', icon: CheckCircle },
]

export default function OnboardingPage() {
  const [currentStep, setCurrentStep] = useState(1)
  const [formData, setFormData] = useState<Partial<FormData>>({})
  const [submitting, setSubmitting] = useState(false)
  const router = useRouter()
  const supabase = createClient()

  const step1Form = useForm<Step1Data>({
    resolver: zodResolver(step1Schema),
    defaultValues: formData,
  })
  const step2Form = useForm<Step2Data>({
    resolver: zodResolver(step2Schema),
    defaultValues: formData,
  })
  const step3Form = useForm<Step3Data>({
    resolver: zodResolver(step3Schema),
    defaultValues: formData,
  })

  const handleStep1 = (data: Step1Data) => {
    setFormData(prev => ({ ...prev, ...data }))
    setCurrentStep(2)
  }

  const handleStep2 = (data: Step2Data) => {
    setFormData(prev => ({ ...prev, ...data }))
    setCurrentStep(3)
  }

  const handleStep3 = (data: Step3Data) => {
    setFormData(prev => ({ ...prev, ...data }))
    setCurrentStep(4)
  }

  const handleSubmit = async () => {
    setSubmitting(true)
    try {
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) throw new Error('Not authenticated')

      // Strip alternate_phone since it's not in the main schema
      const { alternate_phone, ...safeProfileData } = formData

      const { error } = await supabase.from('profiles').upsert({
        id: user.id,
        email: user.email,
        ...safeProfileData,
      })

      // Admin review paradigm - Create initial un-linked pending KYC record 
      await supabase.from('kyc').upsert({
        user_id: user.id,
        status: 'pending',
      }, { onConflict: 'user_id' })

      toast.success('Profile created! Welcome to Shoonya 🎉')
      router.push('/dashboard')
    } catch (err: unknown) {
      const errorMessage = err instanceof Error ? err.message : 'Failed to save profile'
      toast.error(errorMessage)
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <div className="min-h-screen mesh-bg flex flex-col items-center justify-center p-4 py-8">
      {/* Logo */}
      <div className="flex items-center gap-3 mb-8">
        <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-violet-500 to-purple-600 flex items-center justify-center">
          <span className="text-white font-bold">S</span>
        </div>
        <span className="text-2xl font-bold gradient-text">Shoonya</span>
      </div>

      {/* Progress stepper */}
      <div className="w-full max-w-2xl mb-8">
        <div className="flex items-center justify-between relative">
          <div className="absolute top-5 left-0 right-0 h-0.5 bg-border -z-10" />
          <div
            className="absolute top-5 left-0 h-0.5 bg-gradient-to-r from-violet-600 to-purple-600 -z-10 transition-all duration-500"
            style={{ width: `${((currentStep - 1) / (STEPS.length - 1)) * 100}%` }}
          />
          {STEPS.map((step) => {
            const Icon = step.icon
            const isCompleted = currentStep > step.id
            const isActive = currentStep === step.id
            return (
              <div key={step.id} className="flex flex-col items-center gap-2">
                <div
                  className={cn(
                    'w-10 h-10 rounded-full flex items-center justify-center transition-all duration-300 border-2',
                    isCompleted
                      ? 'bg-gradient-to-br from-violet-600 to-purple-600 border-violet-600'
                      : isActive
                      ? 'bg-muted border-violet-600'
                      : 'bg-muted border-border'
                  )}
                >
                  {isCompleted ? (
                    <CheckCircle className="w-5 h-5 text-white" />
                  ) : (
                    <Icon className={cn('w-4 h-4', isActive ? 'text-primary' : 'text-muted-foreground')} />
                  )}
                </div>
                <span
                  className={cn(
                    'text-xs font-medium hidden sm:block',
                    isActive ? 'text-foreground' : 'text-muted-foreground'
                  )}
                >
                  {step.title}
                </span>
              </div>
            )
          })}
        </div>
      </div>

      {/* Form card */}
      <div className="w-full max-w-2xl glass-card p-8">
        <h2 className="text-2xl font-bold mb-1">
          {currentStep === 1 && 'Personal Information'}
          {currentStep === 2 && 'Contact Details'}
          {currentStep === 3 && 'Financial Information'}
          {currentStep === 4 && 'Review & Submit'}
        </h2>
        <p className="text-muted-foreground text-sm mb-8">
          {currentStep === 1 && 'Tell us about yourself to get started'}
          {currentStep === 2 && 'How can we reach you?'}
          {currentStep === 3 && 'Help us calculate your eligibility'}
          {currentStep === 4 && 'Review your information before submitting'}
        </p>

        {/* Step 1 */}
        {currentStep === 1 && (
          <form onSubmit={step1Form.handleSubmit(handleStep1)} className="space-y-5">
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-5">
              <div className="sm:col-span-2">
                <label className="block text-sm font-medium mb-2">Full Name *</label>
                <input
                  {...step1Form.register('full_name')}
                  placeholder="As per Aadhaar card"
                  className="input-dark"
                />
                {step1Form.formState.errors.full_name && (
                  <p className="text-destructive text-xs mt-1">{step1Form.formState.errors.full_name.message}</p>
                )}
              </div>
              <div>
                <label className="block text-sm font-medium mb-2">Age *</label>
                <input
                  type="number"
                  {...step1Form.register('age', { valueAsNumber: true })}
                  placeholder="25"
                  className="input-dark"
                />
                {step1Form.formState.errors.age && (
                  <p className="text-destructive text-xs mt-1">{step1Form.formState.errors.age.message}</p>
                )}
              </div>
              <div>
                <label className="block text-sm font-medium mb-2">Gender *</label>
                <select {...step1Form.register('gender')} className="input-dark">
                  <option value="">Select gender</option>
                  <option value="male">Male</option>
                  <option value="female">Female</option>
                  <option value="other">Other</option>
                  <option value="prefer_not">Prefer not to say</option>
                </select>
                {step1Form.formState.errors.gender && (
                  <p className="text-destructive text-xs mt-1">{step1Form.formState.errors.gender.message}</p>
                )}
              </div>
              <div className="sm:col-span-2">
                <label className="block text-sm font-medium mb-2">Address *</label>
                <input
                  {...step1Form.register('address')}
                  placeholder="House/Flat No, Street, Area"
                  className="input-dark"
                />
                {step1Form.formState.errors.address && (
                  <p className="text-destructive text-xs mt-1">{step1Form.formState.errors.address.message}</p>
                )}
              </div>
              <div>
                <label className="block text-sm font-medium mb-2">City *</label>
                <input {...step1Form.register('city')} placeholder="Mumbai" className="input-dark" />
                {step1Form.formState.errors.city && (
                  <p className="text-destructive text-xs mt-1">{step1Form.formState.errors.city.message}</p>
                )}
              </div>
              <div>
                <label className="block text-sm font-medium mb-2">State *</label>
                <input {...step1Form.register('state')} placeholder="Maharashtra" className="input-dark" />
                {step1Form.formState.errors.state && (
                  <p className="text-destructive text-xs mt-1">{step1Form.formState.errors.state.message}</p>
                )}
              </div>
              <div>
                <label className="block text-sm font-medium mb-2">Pincode *</label>
                <input
                  {...step1Form.register('pincode')}
                  placeholder="400001"
                  maxLength={6}
                  className="input-dark"
                />
                {step1Form.formState.errors.pincode && (
                  <p className="text-destructive text-xs mt-1">{step1Form.formState.errors.pincode.message}</p>
                )}
              </div>
            </div>
            <button
              type="submit"
              className="w-full flex items-center justify-center gap-2 py-3 rounded-xl bg-gradient-to-r from-violet-600 to-purple-600 text-white font-semibold btn-glow"
            >
              Continue <ChevronRight className="w-4 h-4" />
            </button>
          </form>
        )}

        {/* Step 2 */}
        {currentStep === 2 && (
          <form onSubmit={step2Form.handleSubmit(handleStep2)} className="space-y-5">
            <div>
              <label className="block text-sm font-medium mb-2">Mobile Number *</label>
              <div className="flex gap-2">
                <span className="input-dark w-16 flex items-center justify-center text-muted-foreground">+91</span>
                <input
                  {...step2Form.register('phone')}
                  placeholder="9876543210"
                  maxLength={10}
                  className="input-dark flex-1"
                />
              </div>
              {step2Form.formState.errors.phone && (
                <p className="text-destructive text-xs mt-1">{step2Form.formState.errors.phone.message}</p>
              )}
            </div>
            <div>
              <label className="block text-sm font-medium mb-2">Alternate Phone (optional)</label>
              <div className="flex gap-2">
                <span className="input-dark w-16 flex items-center justify-center text-muted-foreground">+91</span>
                <input
                  {...step2Form.register('alternate_phone')}
                  placeholder="9876543210"
                  maxLength={10}
                  className="input-dark flex-1"
                />
              </div>
              {step2Form.formState.errors.alternate_phone && (
                <p className="text-destructive text-xs mt-1">{step2Form.formState.errors.alternate_phone.message}</p>
              )}
            </div>
            <div className="flex gap-3">
              <button
                type="button"
                onClick={() => setCurrentStep(1)}
                className="flex items-center gap-2 px-6 py-3 rounded-xl border border-border text-foreground font-semibold hover:bg-muted/40 transition-all"
              >
                <ChevronLeft className="w-4 h-4" /> Back
              </button>
              <button
                type="submit"
                className="flex-1 flex items-center justify-center gap-2 py-3 rounded-xl bg-gradient-to-r from-violet-600 to-purple-600 text-white font-semibold btn-glow"
              >
                Continue <ChevronRight className="w-4 h-4" />
              </button>
            </div>
          </form>
        )}

        {/* Step 3 */}
        {currentStep === 3 && (
          <form onSubmit={step3Form.handleSubmit(handleStep3)} className="space-y-5">
            <div>
              <label className="block text-sm font-medium mb-2">Employment Type *</label>
              <select {...step3Form.register('employment_type')} className="input-dark">
                <option value="">Select type</option>
                <option value="salaried">Salaried</option>
                <option value="self_employed">Self Employed</option>
                <option value="business">Business Owner</option>
                <option value="freelancer">Freelancer</option>
                <option value="retired">Retired</option>
              </select>
              {step3Form.formState.errors.employment_type && (
                <p className="text-destructive text-xs mt-1">{step3Form.formState.errors.employment_type.message}</p>
              )}
            </div>
            <div>
              <label className="block text-sm font-medium mb-2">Monthly Income *</label>
              <div className="relative">
                <span className="absolute left-4 top-1/2 -translate-y-1/2 text-muted-foreground">₹</span>
                <input
                  type="number"
                  {...step3Form.register('monthly_income', { valueAsNumber: true })}
                  placeholder="50000"
                  className="input-dark pl-8"
                />
              </div>
              {step3Form.formState.errors.monthly_income && (
                <p className="text-destructive text-xs mt-1">{step3Form.formState.errors.monthly_income.message}</p>
              )}
            </div>
            <div>
              <label className="block text-sm font-medium mb-2 flex items-center gap-1">
                <CreditCard className="w-4 h-4" /> PAN Number *
              </label>
              <input
                {...step3Form.register('pan_number')}
                placeholder="ABCDE1234F"
                maxLength={10}
                className="input-dark uppercase"
                onChange={(e) => {
                  e.target.value = e.target.value.toUpperCase()
                  step3Form.setValue('pan_number', e.target.value)
                }}
              />
              {step3Form.formState.errors.pan_number && (
                <p className="text-destructive text-xs mt-1">{step3Form.formState.errors.pan_number.message}</p>
              )}
            </div>
            <div>
              <label className="block text-sm font-medium mb-2 flex items-center gap-1">
                <MapPin className="w-4 h-4" /> Aadhaar Number *
              </label>
              <input
                {...step3Form.register('aadhar_number')}
                placeholder="123456789012"
                maxLength={12}
                className="input-dark"
              />
              {step3Form.formState.errors.aadhar_number && (
                <p className="text-destructive text-xs mt-1">{step3Form.formState.errors.aadhar_number.message}</p>
              )}
            </div>
            <div className="flex gap-3">
              <button
                type="button"
                onClick={() => setCurrentStep(2)}
                className="flex items-center gap-2 px-6 py-3 rounded-xl border border-border text-foreground font-semibold hover:bg-muted/40 transition-all"
              >
                <ChevronLeft className="w-4 h-4" /> Back
              </button>
              <button
                type="submit"
                className="flex-1 flex items-center justify-center gap-2 py-3 rounded-xl bg-gradient-to-r from-violet-600 to-purple-600 text-white font-semibold btn-glow"
              >
                Review <ChevronRight className="w-4 h-4" />
              </button>
            </div>
          </form>
        )}

        {/* Step 4 - Review */}
        {currentStep === 4 && (
          <div className="space-y-6">
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
              {[
                { label: 'Full Name', value: formData.full_name },
                { label: 'Age', value: formData.age },
                { label: 'Gender', value: formData.gender },
                { label: 'Address', value: formData.address },
                { label: 'City', value: formData.city },
                { label: 'State', value: formData.state },
                { label: 'Pincode', value: formData.pincode },
                { label: 'Mobile', value: `+91 ${formData.phone}` },
                { label: 'Employment', value: formData.employment_type },
                { label: 'Monthly Income', value: `₹${(formData.monthly_income || 0).toLocaleString('en-IN')}` },
                { label: 'PAN', value: formData.pan_number },
                { label: 'Aadhaar', value: formData.aadhar_number ? `XXXX XXXX ${formData.aadhar_number.slice(-4)}` : '' },
              ].map((item) => (
                <div key={item.label} className="p-3 rounded-xl bg-muted/40 border border-border">
                  <p className="text-xs text-muted-foreground mb-0.5">{item.label}</p>
                  <p className="text-sm font-medium">{item.value || '—'}</p>
                </div>
              ))}
            </div>
            <div className="flex gap-3">
              <button
                type="button"
                onClick={() => setCurrentStep(3)}
                className="flex items-center gap-2 px-6 py-3 rounded-xl border border-border text-foreground font-semibold hover:bg-muted/40 transition-all"
              >
                <ChevronLeft className="w-4 h-4" /> Back
              </button>
              <button
                onClick={handleSubmit}
                disabled={submitting}
                className="flex-1 flex items-center justify-center gap-2 py-3 rounded-xl bg-gradient-to-r from-violet-600 to-purple-600 text-white font-semibold btn-glow disabled:opacity-70"
              >
                {submitting ? (
                  <><Loader2 className="w-4 h-4 animate-spin" /> Saving...</>
                ) : (
                  <><CheckCircle className="w-4 h-4" /> Submit Profile</>
                )}
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  )
}
