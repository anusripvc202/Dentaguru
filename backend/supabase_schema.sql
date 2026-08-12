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
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

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
END $$;

