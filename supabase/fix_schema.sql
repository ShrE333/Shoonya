-- ================================================================
-- MASTER DATABASE PATCH: Root-Level Pipeline Repair
-- ================================================================

-- 1. HARDEN LOANS TABLE SCHEMA
ALTER TABLE loans ADD COLUMN IF NOT EXISTS offers JSONB DEFAULT '[]'::jsonb;
ALTER TABLE loans ADD COLUMN IF NOT EXISTS selected_offer_index INTEGER;
ALTER TABLE loans ADD COLUMN IF NOT EXISTS tenure_months INTEGER;
ALTER TABLE loans ADD COLUMN IF NOT EXISTS interest_rate DECIMAL(10,2);
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS kyc_status text DEFAULT 'pending';
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS loan_limit numeric DEFAULT 10000;

-- 2. RESET POLICIES FOR TOTAL VISIBILITY
DROP POLICY IF EXISTS "admin loans" ON public.loans;
DROP POLICY IF EXISTS "Users can view own loans" ON public.loans;
DROP POLICY IF EXISTS "Users can insert own loans" ON public.loans;

-- Universal Admin Policy: Can see and manage everything
CREATE POLICY "admin_master_loans" ON public.loans 
FOR ALL USING (
  EXISTS (SELECT 1 FROM profiles WHERE profiles.id = auth.uid() AND profiles.role = 'admin')
) WITH CHECK (
  EXISTS (SELECT 1 FROM profiles WHERE profiles.id = auth.uid() AND profiles.role = 'admin')
);

-- Universal User Policy: Can manage their own loans
CREATE POLICY "user_own_loans" ON public.loans 
FOR ALL USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

-- 3. UNBLOCK PROFILE UPDATES
DROP POLICY IF EXISTS "own profile update" ON public.profiles;
CREATE POLICY "user_manage_own_profile" ON profiles 
FOR ALL USING (auth.uid() = id)
WITH CHECK (auth.uid() = id);

-- 4. STORAGE ACCESS (Absolute Permission for 'documents' bucket)
DROP POLICY IF EXISTS "document upload" ON storage.objects;
CREATE POLICY "universal_doc_access" ON storage.objects
FOR ALL USING (bucket_id = 'documents');

-- 5. ENSURE ACCOUNT IS ADMIN (Update your specific email)
UPDATE profiles SET role = 'admin' WHERE email = 'shr@gmail.com';
UPDATE profiles SET kyc_status = 'verified', loan_limit = 500000 WHERE email = 'shr@gmail.com';
