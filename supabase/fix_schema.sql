-- ================================================================
-- DATABASE PATCH: Fixing KYC Schema & Admin Permissions
-- Run this in your Supabase SQL Editor to unblock the pipeline!
-- ================================================================

-- 1. ADD MISSING COLUMNS
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS kyc_status text DEFAULT 'pending';
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS loan_limit numeric DEFAULT 10000;

-- 2. CREATE 'documents' BUCKET (Used by the platform)
INSERT INTO storage.buckets (id, name, public) 
VALUES ('documents', 'documents', true)
ON CONFLICT (id) DO NOTHING;

-- 3. UNBLOCK ADMINS (Allow Admins to see & update ALL loans)
DROP POLICY IF EXISTS "admin loans" ON public.loans;
CREATE POLICY "admin loans" ON public.loans 
FOR ALL USING (
  (SELECT role FROM profiles WHERE id = auth.uid()) = 'admin'
);

-- 4. UNBLOCK USER UPDATES (Allow users to finish their KYC)
DROP POLICY IF EXISTS "own profile update" ON public.profiles;
CREATE POLICY "own profile update" ON profiles 
FOR UPDATE USING (auth.uid() = id);

-- 5. STORAGE PERMISSIONS (Allow uploads to documents bucket)
DROP POLICY IF EXISTS "document upload" ON storage.objects;
CREATE POLICY "document upload" ON storage.objects
FOR ALL USING (bucket_id = 'documents');

-- 6. MAKE SURE YOU ARE AN ADMIN (REPLACE with your email)
-- UPDATE profiles SET role = 'admin' WHERE email = 'YOUR_EMAIL_HERE';
