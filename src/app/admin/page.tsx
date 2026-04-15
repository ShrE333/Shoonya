import { createClient } from '@/lib/supabase/server'
import { createClient as createSupabaseClient } from '@supabase/supabase-js'
import { redirect } from 'next/navigation'
import AdminClient from './AdminClient'

export default async function AdminPage() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const { data: profile } = await supabase
    .from('profiles')
    .select('*')
    .eq('id', user.id)
    .single()

  if (!profile || profile.role !== 'admin') redirect('/dashboard')

  // Instantiate a Service Role Client to completely bypass RLS
  const supabaseAdmin = createSupabaseClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!
  )

  const { data: profiles } = await supabaseAdmin
    .from('profiles')
    .select('*')
    .neq('role', 'admin')
    .order('created_at', { ascending: false })

  const { data: loans } = await supabaseAdmin
    .from('loans')
    .select('*, profiles(full_name, email, phone)')
    .order('created_at', { ascending: false })

  const { data: kycs } = await supabaseAdmin
    .from('kyc')
    .select('*, profiles(full_name, email, phone)')
    .order('created_at', { ascending: false })

  return (
    <AdminClient
      adminProfile={profile}
      profiles={profiles || []}
      loans={loans || []}
      kycs={kycs || []}
    />
  )
}
