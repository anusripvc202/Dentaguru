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
    xray_urls TEXT[] DEFAULT '{}',
    lab_report_urls TEXT[] DEFAULT '{}',
    follow_up_date TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
ALTER TABLE public.medical_records ADD COLUMN IF NOT EXISTS xray_urls TEXT[] DEFAULT '{}';
ALTER TABLE public.medical_records ADD COLUMN IF NOT EXISTS lab_report_urls TEXT[] DEFAULT '{}';

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

-- 12. DOCTOR AVAILABILITY & SLOTS TABLE
CREATE TABLE IF NOT EXISTS public.doctor_availability (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    dentist_id UUID REFERENCES public.dentists(id) ON DELETE CASCADE,
    date VARCHAR(20) NOT NULL,
    day_of_week VARCHAR(20),
    start_time VARCHAR(20) DEFAULT '09:00 AM',
    end_time VARCHAR(20) DEFAULT '05:00 PM',
    slot_duration_minutes INTEGER DEFAULT 30,
    slots TEXT[] DEFAULT '{}',
    is_blocked BOOLEAN DEFAULT false,
    blocked_reason TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT unique_dentist_date_availability UNIQUE (dentist_id, date)
);
CREATE INDEX IF NOT EXISTS idx_doctor_availability_dentist_date ON public.doctor_availability(dentist_id, date);
ALTER TABLE public.doctor_availability ENABLE ROW LEVEL SECURITY;

-- 13. MEDICAL SPECIALTIES TABLE (Multi-Specialty Healthcare Platform)
CREATE TABLE IF NOT EXISTS public.medical_specialties (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code VARCHAR(100) UNIQUE NOT NULL,
    name VARCHAR(255) UNIQUE NOT NULL,
    department VARCHAR(255) DEFAULT '',
    description TEXT DEFAULT '',
    icon VARCHAR(100) DEFAULT 'medical_services',
    default_qualifications VARCHAR(255) DEFAULT 'MBBS, MD',
    consultation_types TEXT[] DEFAULT '{}',
    sub_specialties TEXT[] DEFAULT '{}',
    is_active BOOLEAN DEFAULT true,
    display_order INTEGER DEFAULT 100,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_medical_specialties_active ON public.medical_specialties(is_active, display_order);
ALTER TABLE public.medical_specialties ENABLE ROW LEVEL SECURITY;

-- 14. DOCTOR SPECIALTIES & QUALIFICATIONS EXTENSIONS (Backward-Compatible)
ALTER TABLE public.dentists ADD COLUMN IF NOT EXISTS specialty_id UUID REFERENCES public.medical_specialties(id) ON DELETE SET NULL;
ALTER TABLE public.dentists ADD COLUMN IF NOT EXISTS department VARCHAR(255) DEFAULT '';
ALTER TABLE public.dentists ADD COLUMN IF NOT EXISTS sub_specialty VARCHAR(255) DEFAULT '';
ALTER TABLE public.dentists ADD COLUMN IF NOT EXISTS bio TEXT DEFAULT '';
ALTER TABLE public.dentists ADD COLUMN IF NOT EXISTS consultation_fee VARCHAR(50) DEFAULT '$75';
ALTER TABLE public.dentists ADD COLUMN IF NOT EXISTS languages TEXT[] DEFAULT '{English}';

CREATE TABLE IF NOT EXISTS public.doctor_specialties (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    doctor_id UUID REFERENCES public.dentists(id) ON DELETE CASCADE,
    specialty_id UUID REFERENCES public.medical_specialties(id) ON DELETE CASCADE,
    specialty_name VARCHAR(255) NOT NULL,
    is_primary BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT unique_doctor_specialty UNIQUE (doctor_id, specialty_name)
);
CREATE INDEX IF NOT EXISTS idx_doctor_specialties_doctor_id ON public.doctor_specialties(doctor_id);
CREATE INDEX IF NOT EXISTS idx_doctor_specialties_specialty_name ON public.doctor_specialties(specialty_name);
ALTER TABLE public.doctor_specialties ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.doctor_qualifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    doctor_id UUID REFERENCES public.dentists(id) ON DELETE CASCADE,
    degree VARCHAR(255) NOT NULL,
    institution VARCHAR(255) DEFAULT '',
    completion_year INTEGER,
    registration_council VARCHAR(255) DEFAULT '',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_doctor_qualifications_doctor_id ON public.doctor_qualifications(doctor_id);
ALTER TABLE public.doctor_qualifications ENABLE ROW LEVEL SECURITY;

-- 15. MULTI-SPECIALTY CLINIC DEPARTMENTS EXTENSIONS (Backward-Compatible)
ALTER TABLE public.clinics ADD COLUMN IF NOT EXISTS departments TEXT[] DEFAULT '{Dentistry}';
ALTER TABLE public.clinics ADD COLUMN IF NOT EXISTS city VARCHAR(100) DEFAULT '';
ALTER TABLE public.clinics ADD COLUMN IF NOT EXISTS pincode VARCHAR(20) DEFAULT '';
ALTER TABLE public.clinics ADD COLUMN IF NOT EXISTS phone VARCHAR(50) DEFAULT '';

CREATE TABLE IF NOT EXISTS public.clinic_departments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    clinic_id UUID REFERENCES public.clinics(id) ON DELETE CASCADE,
    specialty_id UUID REFERENCES public.medical_specialties(id) ON DELETE SET NULL,
    department_name VARCHAR(255) NOT NULL,
    head_doctor_id UUID REFERENCES public.dentists(id) ON DELETE SET NULL,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT unique_clinic_department UNIQUE (clinic_id, department_name)
);
CREATE INDEX IF NOT EXISTS idx_clinic_departments_clinic_id ON public.clinic_departments(clinic_id);
ALTER TABLE public.clinic_departments ENABLE ROW LEVEL SECURITY;

-- 16. MULTI-SPECIALTY EXTENSIONS FOR APPOINTMENTS, REQUESTS & RECORDS
ALTER TABLE public.appointments ADD COLUMN IF NOT EXISTS specialty VARCHAR(255) DEFAULT '';
ALTER TABLE public.appointments ADD COLUMN IF NOT EXISTS department VARCHAR(255) DEFAULT '';
ALTER TABLE public.patient_problem_requests ADD COLUMN IF NOT EXISTS specialty VARCHAR(255) DEFAULT 'Dentistry';
ALTER TABLE public.medical_records ADD COLUMN IF NOT EXISTS specialty VARCHAR(255) DEFAULT '';
ALTER TABLE public.referrals ADD COLUMN IF NOT EXISTS specialty VARCHAR(255) DEFAULT '';

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
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Allow All Doctor Availability') THEN
        CREATE POLICY "Allow All Doctor Availability" ON public.doctor_availability FOR ALL USING (true);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Allow All Medical Specialties') THEN
        CREATE POLICY "Allow All Medical Specialties" ON public.medical_specialties FOR ALL USING (true);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Allow All Doctor Specialties') THEN
        CREATE POLICY "Allow All Doctor Specialties" ON public.doctor_specialties FOR ALL USING (true);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Allow All Doctor Qualifications') THEN
        CREATE POLICY "Allow All Doctor Qualifications" ON public.doctor_qualifications FOR ALL USING (true);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Allow All Clinic Departments') THEN
        CREATE POLICY "Allow All Clinic Departments" ON public.clinic_departments FOR ALL USING (true);
    END IF;
END $$;

-- Seed 16 Core Medical Specialties (Idempotent)
INSERT INTO public.medical_specialties (code, name, department, description, icon, default_qualifications, consultation_types, sub_specialties, is_active, display_order)
VALUES
    ('GEN_MED', 'General Medicine', 'Department of Internal & General Medicine', 'Primary care, internal medicine, acute & chronic illnesses, fever, and preventive health checkups.', 'medical_services', 'MBBS, MD (General Medicine)', ARRAY['General Consultation', 'Fever & Viral Infection', 'Diabetes & Blood Pressure Review', 'Preventive Health Checkup', 'Chronic Illness Follow-up'], ARRAY['Internal Medicine', 'Family Medicine'], true, 1),
    ('CARDIO', 'Cardiology', 'Department of Cardiology & Vascular Sciences', 'Diagnosis and treatment of heart conditions, hypertension, arrhythmias, and cardiovascular diseases.', 'MonitorHeart', 'MBBS, MD, DM (Cardiology)', ARRAY['Cardiac Consultation', 'ECG & Echo Review', 'Hypertension & Lipid Management', 'Chest Pain Evaluation', 'Post-Angioplasty Follow-up'], ARRAY['Interventional Cardiology', 'Electrophysiology'], true, 2),
    ('DERM', 'Dermatology', 'Department of Dermatology, Venereology & Cosmetology', 'Skin, hair, nail disorders, acne, eczema, psoriasis, and clinical dermatological procedures.', 'FaceRetouchingNatural', 'MBBS, MD (Dermatology, Venereology & Leprosy)', ARRAY['Skin & Acne Consultation', 'Hair Fall & Scalp Evaluation', 'Allergy & Rash Treatment', 'Eczema / Psoriasis Care', 'Cosmetic Dermatology'], ARRAY['Clinical Dermatology', 'Cosmetology', 'Trichology'], true, 3),
    ('NEURO', 'Neurology', 'Department of Neurology & Neurosciences', 'Disorders of the brain, spinal cord, peripheral nerves, migraine, epilepsy, and stroke care.', 'Psychology', 'MBBS, MD, DM (Neurology)', ARRAY['Neurological Consultation', 'Migraine & Headache Clinic', 'Epilepsy & Seizure Management', 'Stroke Recovery & Neuropathy', 'Memory & Movement Disorders'], ARRAY['Stroke Medicine', 'Epileptology'], true, 4),
    ('ORTHO', 'Orthopedics', 'Department of Orthopedics & Joint Replacement', 'Bone, joint, ligament, spine, sports injuries, arthritis, and fracture management.', 'AccessibilityNew', 'MBBS, MS (Orthopedics)', ARRAY['Bone & Joint Consultation', 'Back & Spine Pain Evaluation', 'Sports Injury & Ligament Care', 'Arthritis & Knee Replacement Review', 'Fracture & Trauma Follow-up'], ARRAY['Joint Replacement', 'Spine Surgery', 'Sports Medicine'], true, 5),
    ('PEDIA', 'Pediatrics', 'Department of Pediatrics & Child Health', 'Comprehensive medical care for infants, children, and adolescents including vaccinations and growth tracking.', 'ChildCare', 'MBBS, MD (Pediatrics), DCH', ARRAY['Child Health Consultation', 'Vaccination & Immunization', 'Growth & Nutrition Assessment', 'Pediatric Fever & Infection', 'Newborn & Infant Care'], ARRAY['Neonatology', 'Pediatric Critical Care'], true, 6),
    ('GYNEC', 'Gynecology', 'Department of Obstetrics & Gynecology', 'Women''s reproductive health, pregnancy care, prenatal checkups, PCOS, and gynecological wellness.', 'PregnantWoman', 'MBBS, MS / DGO (Obstetrics & Gynecology)', ARRAY['Gynecology Consultation', 'Antenatal / Pregnancy Checkup', 'PCOS & Hormonal Evaluation', 'Menstrual Health Clinic', 'Postnatal & Fertility Care'], ARRAY['Obstetrics', 'Fetal Medicine', 'Reproductive Medicine'], true, 7),
    ('ENT', 'ENT', 'Department of Otorhinolaryngology (Ear, Nose & Throat)', 'Ear infections, hearing loss, sinusitis, tonsillitis, throat disorders, and vertigo management.', 'Hearing', 'MBBS, MS (ENT)', ARRAY['ENT Consultation', 'Ear Pain & Hearing Assessment', 'Sinusitis & Nasal Allergy', 'Throat & Tonsil Infection', 'Vertigo & Balance Evaluation'], ARRAY['Otology', 'Rhinology', 'Laryngology'], true, 8),
    ('OPHTHAL', 'Ophthalmology', 'Department of Ophthalmology & Vision Sciences', 'Comprehensive eye exams, cataract, glaucoma, retina care, and vision correction.', 'Visibility', 'MBBS, MS (Ophthalmology)', ARRAY['Comprehensive Eye Exam', 'Cataract & Lens Consultation', 'Retina & Diabetic Eye Screening', 'Glaucoma Evaluation', 'Dry Eye & Vision Correction'], ARRAY['Retina', 'Cornea', 'Glaucoma'], true, 9),
    ('ONCO', 'Oncology', 'Department of Oncology & Cancer Care', 'Medical, surgical, and radiation oncology consultations, cancer screening, and follow-up care.', 'Biotech', 'MBBS, MD, DM (Medical Oncology) / MCh', ARRAY['Oncology Consultation', 'Cancer Screening & Prevention', 'Chemotherapy / Immunotherapy Review', 'Second Opinion & Tumor Board', 'Survivorship Follow-up'], ARRAY['Medical Oncology', 'Surgical Oncology', 'Radiation Oncology'], true, 10),
    ('URO', 'Urology', 'Department of Urology & Renal Sciences', 'Kidney stones, urinary tract infections, prostate health, and reconstructive urology.', 'WaterDrop', 'MBBS, MS, MCh (Urology)', ARRAY['Urology Consultation', 'Kidney Stone Evaluation', 'Urinary Tract Infection (UTI)', 'Prostate Health Screening', 'Bladder & Renal Follow-up'], ARRAY['Endourology', 'Andrology', 'Uro-Oncology'], true, 11),
    ('PSYCH', 'Psychiatry', 'Department of Psychiatry & Behavioral Sciences', 'Mental health consultations, anxiety, depression, stress management, sleep disorders, and counseling.', 'SelfImprovement', 'MBBS, MD (Psychiatry)', ARRAY['Psychiatric Consultation', 'Anxiety & Stress Management', 'Depression & Mood Clinic', 'Sleep Disorder Evaluation', 'Behavioral & De-addiction Support'], ARRAY['Adult Psychiatry', 'Child & Adolescent Psychiatry'], true, 12),
    ('GASTRO', 'Gastroenterology', 'Department of Gastroenterology & Hepatology', 'Digestive tract, stomach, liver, pancreas, acidity, IBS, and endoscopy consultations.', 'MedicationLiquid', 'MBBS, MD, DM (Gastroenterology)', ARRAY['Gastroenterology Consultation', 'Acidity, Reflux & Ulcer Care', 'Liver & Hepatology Evaluation', 'IBS & Digestive Disorder Clinic', 'Endoscopy / Colonoscopy Review'], ARRAY['Hepatology', 'Therapeutic Endoscopy'], true, 13),
    ('PULMO', 'Pulmonology', 'Department of Pulmonology & Respiratory Medicine', 'Asthma, COPD, bronchitis, sleep apnea, lung infections, and allergy management.', 'Air', 'MBBS, MD (Pulmonary Medicine)', ARRAY['Pulmonology Consultation', 'Asthma & Allergy Clinic', 'Chronic Cough & COPD Care', 'Sleep Apnea & Breathing Study', 'Post-Infection Lung Recovery'], ARRAY['Interventional Pulmonology', 'Sleep Medicine'], true, 14),
    ('ENDO', 'Endocrinology', 'Department of Endocrinology, Diabetes & Metabolism', 'Diabetes mellitus, thyroid disorders, hormonal imbalances, osteoporosis, and metabolic care.', 'Bloodtype', 'MBBS, MD, DM (Endocrinology)', ARRAY['Endocrinology Consultation', 'Comprehensive Diabetes Management', 'Thyroid Disorder Clinic', 'PCOS & Adrenal Hormone Review', 'Metabolic & Bone Density Care'], ARRAY['Diabetology', 'Thyroid & Metabolic Medicine'], true, 15),
    ('DENTAL', 'Dentistry', 'Department of Dental Sciences & Oral Healthcare', 'General dentistry, orthodontics, endodontics, root canal, periodontics, prosthodontics, and oral surgery.', 'HealthAndSafety', 'BDS, MDS', ARRAY['General Consultation', 'Dental Pain / Toothache', 'Tooth Decay / Cavity', 'Root Canal Consultation', 'Orthodontics / Braces', 'Periodontics / Gum Care', 'Tooth Extraction', 'Dental Cleaning & Scaling'], ARRAY['General Dentistry', 'Orthodontics', 'Endodontics', 'Periodontics', 'Prosthodontics', 'Pediatric Dentistry', 'Cosmetic Dentistry', 'Oral & Maxillofacial Surgery', 'Oral Surgery'], true, 16)
ON CONFLICT (code) DO NOTHING;




