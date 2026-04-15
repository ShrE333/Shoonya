-- ================================================================
-- Shoonya Database Schema
-- Run this in Supabase SQL Editor
-- ================================================================

-- PROFILES TABLE
create table public.profiles (
  id uuid references auth.users primary key,
  full_name text,
  email text,
  phone text,
  age integer,
  gender text,
  address text,
  city text,
  state text,
  pincode text,
  pan_number text,
  aadhar_number text,
  monthly_income numeric,
  employment_type text,
  role text default 'user', -- user | admin
  created_at timestamptz default now()
);

-- LOANS TABLE
create table public.loans (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.profiles,
  loan_type text,
  amount_requested numeric,
  tenure_months integer,
  purpose text,
  status text default 'pending', -- pending | under_review | approved | rejected
  eligibility_score numeric,
  approved_amount numeric,
  interest_rate numeric,
  emi_amount numeric,
  remarks text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- KYC TABLE
create table public.kyc (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.profiles unique,
  status text default 'pending', -- pending | link_sent | completed | failed | verified
  kyc_link text,
  link_sent_at timestamptz,
  wa_message_sid text,
  selfie_url text,
  face_age_estimate integer,
  face_gender text,
  liveness_score numeric,
  location_lat numeric,
  location_lng numeric,
  completed_at timestamptz,
  verified_by uuid references public.profiles,
  created_at timestamptz default now()
);

-- ================================================================
-- RLS POLICIES
-- ================================================================
alter table public.profiles enable row level security;
alter table public.loans enable row level security;
alter table public.kyc enable row level security;

-- Profiles: users see only their own
create policy "own profile read" on profiles for select using (auth.uid() = id);
create policy "own profile update" on profiles for update using (auth.uid() = id);
create policy "own profile insert" on profiles for insert with check (auth.uid() = id);

-- Loans: users see only their own
create policy "own loans" on loans for all using (auth.uid() = user_id);

-- KYC: users see only their own
create policy "own kyc" on kyc for all using (auth.uid() = user_id);

-- KYC: allow read by kyc_link (for token validation)
create policy "kyc by token" on kyc for select using (true);

-- ================================================================
-- STORAGE BUCKETS
-- ================================================================
insert into storage.buckets (id, name, public) values ('kyc-assets', 'kyc-assets', true);

create policy "kyc selfie upload" on storage.objects
  for insert with check (bucket_id = 'kyc-assets');

create policy "kyc selfie read" on storage.objects
  for select using (bucket_id = 'kyc-assets');

-- ================================================================
-- INDEXES
-- ================================================================
create index idx_loans_user_id on loans(user_id);
create index idx_loans_status on loans(status);
create index idx_kyc_user_id on kyc(user_id);
create index idx_kyc_link on kyc(kyc_link);

-- ================================================================
-- UPDATED_AT TRIGGER
-- ================================================================
create or replace function handle_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

create trigger loans_updated_at
  before update on loans
  for each row execute function handle_updated_at();

-- ================================================================
-- MAKE AN ADMIN (run separately, replace with your email)
-- ================================================================
-- update profiles set role = 'admin' where email = 'admin@yourdomain.com';
