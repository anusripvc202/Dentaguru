-- DENTA GURU SUPABASE POSTGRESQL SCHEMA
-- Run this script in your Supabase Dashboard -> SQL Editor

-- 1. USERS TABLE
CREATE TABLE IF NOT EXISTS public.users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    password VARCHAR(255) NOT NULL,
    phone VARCHAR(50) UNIQUE NOT NULL,
    role VARCHAR(50) DEFAULT 'Patient',
    state VARCHAR(100) DEFAULT '',
    city VARCHAR(100) DEFAULT '',
    pincode VARCHAR(20) DEFAULT '',
    latitude NUMERIC,
    longitude NUMERIC,
    biometric_token TEXT,
    device_token TEXT,
    refresh_tokens TEXT[] DEFAULT '{}',
    wallet_balance NUMERIC DEFAULT 0,
    loyalty_points INTEGER DEFAULT 0,
    age VARCHAR(20) DEFAULT '',
    gender VARCHAR(50) DEFAULT '',
    blood_group VARCHAR(50) DEFAULT '',
    emergency_contact VARCHAR(50) DEFAULT '',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE public.users ADD COLUMN IF NOT EXISTS age VARCHAR(20) DEFAULT '';
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS gender VARCHAR(50) DEFAULT '';
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS blood_group VARCHAR(50) DEFAULT '';
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS emergency_contact VARCHAR(50) DEFAULT '';
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS status VARCHAR(50) DEFAULT 'ACTIVE';
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS permissions TEXT[] DEFAULT '{}';

-- 1b. SUB-ADMIN PERMISSIONS TABLE
CREATE TABLE IF NOT EXISTS public.sub_admin_permissions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    permission VARCHAR(100) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_sub_admin_permissions_user_id ON public.sub_admin_permissions(user_id);

-- 2. CLINICS TABLE
CREATE TABLE IF NOT EXISTS public.clinics (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    clinic_name VARCHAR(255) NOT NULL,
    location TEXT NOT NULL,
    latitude NUMERIC,
    longitude NUMERIC,
    verified BOOLEAN DEFAULT false,
    verification_status VARCHAR(50) DEFAULT 'PENDING_VERIFICATION',
    plan VARCHAR(50) DEFAULT 'Standard',
    active_slots TEXT[] DEFAULT '{}',
    services TEXT[] DEFAULT '{}',
    pricing JSONB DEFAULT '[]',
    branches JSONB DEFAULT '[]',
    working_hours JSONB DEFAULT '{}',
    rating NUMERIC DEFAULT 0,
    reviews_count INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 3. DENTISTS TABLE
CREATE TABLE IF NOT EXISTS public.dentists (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    clinic_id UUID REFERENCES public.clinics(id) ON DELETE CASCADE,
    speciality VARCHAR(255) NOT NULL,
    license_number VARCHAR(100) UNIQUE NOT NULL,
    experience_years INTEGER DEFAULT 5,
    qualifications VARCHAR(255) DEFAULT 'BDS, MDS',
    availability_status VARCHAR(50) DEFAULT 'Available',
    verification_status VARCHAR(50) DEFAULT 'PENDING_VERIFICATION',
    rating NUMERIC DEFAULT 0,
    reviews_count INTEGER DEFAULT 0,
    state VARCHAR(100) DEFAULT '',
    city VARCHAR(100) DEFAULT '',
    pincode VARCHAR(20) DEFAULT '',
    latitude NUMERIC,
    longitude NUMERIC,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ─────────────────────────────────────────────────────────────────
-- MIGRATION: Run this if the tables already exist in Supabase
-- ─────────────────────────────────────────────────────────────────
-- ALTER TABLE public.users ADD COLUMN IF NOT EXISTS state VARCHAR(100) DEFAULT '';
-- ALTER TABLE public.users ADD COLUMN IF NOT EXISTS city VARCHAR(100) DEFAULT '';
-- ALTER TABLE public.users ADD COLUMN IF NOT EXISTS pincode VARCHAR(20) DEFAULT '';
-- ALTER TABLE public.users ADD COLUMN IF NOT EXISTS latitude NUMERIC;
-- ALTER TABLE public.users ADD COLUMN IF NOT EXISTS longitude NUMERIC;

-- ALTER TABLE public.dentists ADD COLUMN IF NOT EXISTS state VARCHAR(100) DEFAULT '';
-- ALTER TABLE public.dentists ADD COLUMN IF NOT EXISTS city VARCHAR(100) DEFAULT '';
-- ALTER TABLE public.dentists ADD COLUMN IF NOT EXISTS pincode VARCHAR(20) DEFAULT '';
-- ALTER TABLE public.dentists ADD COLUMN IF NOT EXISTS latitude NUMERIC;
-- ALTER TABLE public.dentists ADD COLUMN IF NOT EXISTS longitude NUMERIC;

-- ALTER TABLE public.patient_problem_requests ADD COLUMN IF NOT EXISTS state VARCHAR(100) DEFAULT '';
-- ALTER TABLE public.patient_problem_requests ADD COLUMN IF NOT EXISTS city VARCHAR(100) DEFAULT '';
-- ALTER TABLE public.patient_problem_requests ADD COLUMN IF NOT EXISTS pincode VARCHAR(20) DEFAULT '';
-- ALTER TABLE public.patient_problem_requests ADD COLUMN IF NOT EXISTS latitude NUMERIC;
-- ALTER TABLE public.patient_problem_requests ADD COLUMN IF NOT EXISTS longitude NUMERIC;

-- ALTER TABLE public.dentist_suggestions ADD COLUMN IF NOT EXISTS patient_state VARCHAR(100) DEFAULT '';
-- ALTER TABLE public.dentist_suggestions ADD COLUMN IF NOT EXISTS patient_city VARCHAR(100) DEFAULT '';
-- ALTER TABLE public.dentist_suggestions ADD COLUMN IF NOT EXISTS patient_pincode VARCHAR(20) DEFAULT '';
-- ALTER TABLE public.dentist_suggestions ADD COLUMN IF NOT EXISTS dentist_state VARCHAR(100) DEFAULT '';
-- ALTER TABLE public.dentist_suggestions ADD COLUMN IF NOT EXISTS dentist_city VARCHAR(100) DEFAULT '';
-- ALTER TABLE public.dentist_suggestions ADD COLUMN IF NOT EXISTS dentist_pincode VARCHAR(20) DEFAULT '';
-- ─────────────────────────────────────────────────────────────────

-- 4. PATIENT PROBLEM REQUESTS TABLE
CREATE TABLE IF NOT EXISTS public.patient_problem_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    patient_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    problem_category VARCHAR(255) NOT NULL,
    problem_description TEXT NOT NULL,
    symptoms TEXT,
    preferred_location VARCHAR(255),
    state VARCHAR(100) DEFAULT '',
    city VARCHAR(100) DEFAULT '',
    pincode VARCHAR(20) DEFAULT '',
    latitude NUMERIC,
    longitude NUMERIC,
    attachments JSONB DEFAULT '[]',
    status VARCHAR(50) DEFAULT 'PENDING_ADMIN_REVIEW',
    suggested_dentist_id UUID REFERENCES public.dentists(id) ON DELETE SET NULL,
    admin_notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 5. DENTIST SUGGESTIONS TABLE
CREATE TABLE IF NOT EXISTS public.dentist_suggestions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    request_id UUID REFERENCES public.patient_problem_requests(id) ON DELETE CASCADE,
    patient_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    admin_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
    dentist_id UUID REFERENCES public.dentists(id) ON DELETE CASCADE,
    patient_state VARCHAR(100) DEFAULT '',
    patient_city VARCHAR(100) DEFAULT '',
    patient_pincode VARCHAR(20) DEFAULT '',
    dentist_state VARCHAR(100) DEFAULT '',
    dentist_city VARCHAR(100) DEFAULT '',
    dentist_pincode VARCHAR(20) DEFAULT '',
    suggested_date TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    status VARCHAR(50) DEFAULT 'SUGGESTED',
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 6. APPOINTMENTS TABLE
CREATE TABLE IF NOT EXISTS public.appointments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    request_id UUID REFERENCES public.patient_problem_requests(id) ON DELETE SET NULL,
    patient_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    dentist_id UUID REFERENCES public.dentists(id) ON DELETE CASCADE,
    clinic_id UUID REFERENCES public.clinics(id) ON DELETE CASCADE,
    date TIMESTAMP WITH TIME ZONE NOT NULL,
    time_slot VARCHAR(50) NOT NULL,
    treatment VARCHAR(255) NOT NULL,
    status VARCHAR(50) DEFAULT 'PENDING',
    qr_code_string TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 7. MEDICAL RECORDS TABLE
CREATE TABLE IF NOT EXISTS public.medical_records (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    patient_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    dentist_id UUID REFERENCES public.dentists(id) ON DELETE CASCADE,
    appointment_id UUID REFERENCES public.appointments(id) ON DELETE SET NULL,
    diagnosis TEXT NOT NULL,
    symptoms TEXT,
    treatment TEXT,
    notes TEXT,
    prescriptions JSONB DEFAULT '[]',
    attachments JSONB DEFAULT '[]',
    follow_up_date TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 8. CHAT MESSAGES TABLE
CREATE TABLE IF NOT EXISTS public.chat_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    room_id VARCHAR(255) NOT NULL,
    sender_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    receiver_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    message TEXT NOT NULL,
    type VARCHAR(50) DEFAULT 'text',
    read BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 9. NOTIFICATIONS TABLE
CREATE TABLE IF NOT EXISTS public.notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    recipient_role VARCHAR(50) NOT NULL,
    recipient_id VARCHAR(255) NOT NULL,
    title VARCHAR(255) NOT NULL,
    message TEXT NOT NULL,
    type VARCHAR(50) DEFAULT 'general',
    read BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 10. AUDIT LOGS TABLE (Admin Access & Chat Security Audit Trail)
CREATE TABLE IF NOT EXISTS public.audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
    user_email VARCHAR(255),
    user_role VARCHAR(50),
    action VARCHAR(100) NOT NULL,
    target_resource VARCHAR(255),
    details JSONB DEFAULT '{}'::jsonb,
    ip_address VARCHAR(100),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 11. REFERRALS TABLE (Patient Referrals & Organic Referral System)
CREATE TABLE IF NOT EXISTS public.referrals (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    referrer_patient_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    referred_patient_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
    referred_patient_name VARCHAR(255),
    referred_patient_mobile VARCHAR(50),
    referred_patient_age VARCHAR(20),
    referred_patient_gender VARCHAR(50),
    referred_patient_city VARCHAR(100),
    referred_patient_pincode VARCHAR(20),
    referred_patient_location VARCHAR(255),
    required_specialist VARCHAR(255),
    clinical_complaint TEXT,
    doctor_id UUID REFERENCES public.dentists(id) ON DELETE SET NULL,
    status VARCHAR(50) DEFAULT 'Pending',
    rejection_reason TEXT,
    whatsapp_status VARCHAR(50) DEFAULT 'Pending',
    referral_date TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    -- Backward-compatibility fields
    referrer_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    referred_user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    referral_code VARCHAR(100),
    appointment_id UUID REFERENCES public.appointments(id) ON DELETE SET NULL,
    assigned_doctor_id UUID REFERENCES public.dentists(id) ON DELETE SET NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Ensure all columns exist if table was previously created
ALTER TABLE public.referrals ADD COLUMN IF NOT EXISTS referrer_patient_id UUID REFERENCES public.users(id) ON DELETE CASCADE;
ALTER TABLE public.referrals ADD COLUMN IF NOT EXISTS referred_patient_id UUID REFERENCES public.users(id) ON DELETE SET NULL;
ALTER TABLE public.referrals ADD COLUMN IF NOT EXISTS referred_patient_name VARCHAR(255);
ALTER TABLE public.referrals ADD COLUMN IF NOT EXISTS referred_patient_mobile VARCHAR(50);
ALTER TABLE public.referrals ADD COLUMN IF NOT EXISTS referred_patient_age VARCHAR(20);
ALTER TABLE public.referrals ADD COLUMN IF NOT EXISTS referred_patient_gender VARCHAR(50);
ALTER TABLE public.referrals ADD COLUMN IF NOT EXISTS referred_patient_city VARCHAR(100);
ALTER TABLE public.referrals ADD COLUMN IF NOT EXISTS referred_patient_pincode VARCHAR(20);
ALTER TABLE public.referrals ADD COLUMN IF NOT EXISTS referred_patient_location VARCHAR(255);
ALTER TABLE public.referrals ADD COLUMN IF NOT EXISTS required_specialist VARCHAR(255);
ALTER TABLE public.referrals ADD COLUMN IF NOT EXISTS clinical_complaint TEXT;
ALTER TABLE public.referrals ADD COLUMN IF NOT EXISTS doctor_id UUID REFERENCES public.dentists(id) ON DELETE SET NULL;
ALTER TABLE public.referrals ADD COLUMN IF NOT EXISTS rejection_reason TEXT;
ALTER TABLE public.referrals ADD COLUMN IF NOT EXISTS whatsapp_status VARCHAR(50) DEFAULT 'Pending';
ALTER TABLE public.referrals ADD COLUMN IF NOT EXISTS referral_date TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP;

CREATE INDEX IF NOT EXISTS idx_referrals_referrer_patient_id ON public.referrals(referrer_patient_id);
CREATE INDEX IF NOT EXISTS idx_referrals_referred_patient_id ON public.referrals(referred_patient_id);
CREATE INDEX IF NOT EXISTS idx_referrals_referred_patient_mobile ON public.referrals(referred_patient_mobile);
CREATE INDEX IF NOT EXISTS idx_referrals_doctor_id ON public.referrals(doctor_id);
CREATE INDEX IF NOT EXISTS idx_referrals_status ON public.referrals(status);
CREATE INDEX IF NOT EXISTS idx_referrals_referrer_id ON public.referrals(referrer_id);
CREATE INDEX IF NOT EXISTS idx_referrals_referred_user_id ON public.referrals(referred_user_id);
CREATE INDEX IF NOT EXISTS idx_referrals_code ON public.referrals(referral_code);

ALTER TABLE public.notifications ADD COLUMN IF NOT EXISTS referral_id UUID REFERENCES public.referrals(id) ON DELETE SET NULL;
ALTER TABLE public.notifications ADD COLUMN IF NOT EXISTS notification_type VARCHAR(50);

ALTER TABLE public.users ADD COLUMN IF NOT EXISTS referral_code VARCHAR(50);

-- Enable Row Level Security (RLS)
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.clinics ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dentists ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.patient_problem_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dentist_suggestions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.appointments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.medical_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.referrals ENABLE ROW LEVEL SECURITY;

-- 11. PATIENT SAVED DOCTORS TABLE (My Doctors)
CREATE TABLE IF NOT EXISTS public.patient_doctors (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    patient_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    doctor_id UUID REFERENCES public.dentists(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT unique_patient_doctor UNIQUE (patient_id, doctor_id)
);
CREATE INDEX IF NOT EXISTS idx_patient_doctors_patient_id ON public.patient_doctors(patient_id);
ALTER TABLE public.patient_doctors ENABLE ROW LEVEL SECURITY;

-- Allow Service Role Access
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Allow All Users') THEN
        CREATE POLICY "Allow All Users" ON public.users FOR ALL USING (true);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Allow All Clinics') THEN
        CREATE POLICY "Allow All Clinics" ON public.clinics FOR ALL USING (true);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Allow All Dentists') THEN
        CREATE POLICY "Allow All Dentists" ON public.dentists FOR ALL USING (true);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Allow All Problem Requests') THEN
        CREATE POLICY "Allow All Problem Requests" ON public.patient_problem_requests FOR ALL USING (true);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Allow All Dentist Suggestions') THEN
        CREATE POLICY "Allow All Dentist Suggestions" ON public.dentist_suggestions FOR ALL USING (true);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Allow All Appointments') THEN
        CREATE POLICY "Allow All Appointments" ON public.appointments FOR ALL USING (true);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Allow All Medical Records') THEN
        CREATE POLICY "Allow All Medical Records" ON public.medical_records FOR ALL USING (true);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Allow All Chat Messages') THEN
        CREATE POLICY "Allow All Chat Messages" ON public.chat_messages FOR ALL USING (true);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Allow All Notifications') THEN
        CREATE POLICY "Allow All Notifications" ON public.notifications FOR ALL USING (true);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Allow All Audit Logs') THEN
        CREATE POLICY "Allow All Audit Logs" ON public.audit_logs FOR ALL USING (true);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Allow All Referrals') THEN
        CREATE POLICY "Allow All Referrals" ON public.referrals FOR ALL USING (true);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Allow All Patient Doctors') THEN
        CREATE POLICY "Allow All Patient Doctors" ON public.patient_doctors FOR ALL USING (true);
    END IF;
END $$;



