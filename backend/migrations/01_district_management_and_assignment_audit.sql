-- =============================================================================
-- GS HEALTH SUPABASE POSTGRESQL MIGRATION: 01_district_management_and_assignment_audit.sql
-- Module: Multiple District Management, Sub-Admin Permissions & Immutable Patient Assignment Audit
-- Idempotent, safe migration using IF NOT EXISTS and non-destructive extensions.
-- =============================================================================

-- 1. DISTRICTS TABLE
CREATE TABLE IF NOT EXISTS public.districts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(150) NOT NULL UNIQUE,
    state VARCHAR(100) NOT NULL DEFAULT 'Telangana',
    country VARCHAR(50) NOT NULL DEFAULT 'India',
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_districts_name ON public.districts(name);
CREATE INDEX IF NOT EXISTS idx_districts_state ON public.districts(state);
CREATE INDEX IF NOT EXISTS idx_districts_is_active ON public.districts(is_active);

-- 2. SUB-ADMIN DISTRICT MAPPINGS TABLE (Many-to-Many: Sub-Admin <-> District)
CREATE TABLE IF NOT EXISTS public.sub_admin_districts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sub_admin_user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    district_id UUID NOT NULL REFERENCES public.districts(id) ON DELETE CASCADE,
    assigned_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT unique_subadmin_district UNIQUE (sub_admin_user_id, district_id)
);
CREATE INDEX IF NOT EXISTS idx_sub_admin_districts_user ON public.sub_admin_districts(sub_admin_user_id);
CREATE INDEX IF NOT EXISTS idx_sub_admin_districts_district ON public.sub_admin_districts(district_id);

-- 3. SUB-ADMIN PERMISSIONS TABLE EXTENSIONS
CREATE TABLE IF NOT EXISTS public.sub_admin_permissions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    permission VARCHAR(100) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
ALTER TABLE public.sub_admin_permissions ADD COLUMN IF NOT EXISTS granted BOOLEAN DEFAULT true;
ALTER TABLE public.sub_admin_permissions ADD COLUMN IF NOT EXISTS updated_by UUID REFERENCES public.users(id) ON DELETE SET NULL;
ALTER TABLE public.sub_admin_permissions ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'unique_subadmin_permission_pair'
    ) THEN
        ALTER TABLE public.sub_admin_permissions 
            ADD CONSTRAINT unique_subadmin_permission_pair UNIQUE (user_id, permission);
    END IF;
EXCEPTION
    WHEN others THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS idx_sub_admin_permissions_user ON public.sub_admin_permissions(user_id);
CREATE INDEX IF NOT EXISTS idx_sub_admin_permissions_perm ON public.sub_admin_permissions(permission);

-- 4. PERMISSION CHANGE AUDIT LOG TABLE
CREATE TABLE IF NOT EXISTS public.permission_change_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sub_admin_user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    changed_by_user_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
    changed_by_role VARCHAR(50) DEFAULT 'Admin',
    action VARCHAR(50) NOT NULL, -- 'GRANTED', 'REVOKED', 'INITIAL_RESTRICTED'
    permission_key VARCHAR(100) NOT NULL,
    previous_state BOOLEAN,
    new_state BOOLEAN,
    reason TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_perm_change_sub_admin ON public.permission_change_history(sub_admin_user_id);
CREATE INDEX IF NOT EXISTS idx_perm_change_created_at ON public.permission_change_history(created_at);

-- 5. IMMUTABLE PATIENT ASSIGNMENT AUDIT HISTORY TABLE
CREATE TABLE IF NOT EXISTS public.patient_assignment_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    patient_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    doctor_id UUID NOT NULL REFERENCES public.dentists(id) ON DELETE CASCADE,
    appointment_id UUID REFERENCES public.appointments(id) ON DELETE SET NULL,
    request_id UUID REFERENCES public.patient_problem_requests(id) ON DELETE SET NULL,
    assigned_by_user_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
    assigned_by_name VARCHAR(255),
    assigned_by_role VARCHAR(50) NOT NULL, -- 'PATIENT', 'MAIN_ADMIN', 'SUB_ADMIN'
    assignment_source VARCHAR(50) NOT NULL, -- 'PATIENT_DIRECT_BOOKING', 'MAIN_ADMIN_ASSIGNMENT', 'SUB_ADMIN_ASSIGNMENT'
    district_id UUID REFERENCES public.districts(id) ON DELETE SET NULL,
    district_name VARCHAR(150),
    previous_assignment_id UUID REFERENCES public.patient_assignment_history(id) ON DELETE SET NULL,
    assignment_reason TEXT,
    status VARCHAR(50) DEFAULT 'ASSIGNED', -- 'ASSIGNED', 'REASSIGNED', 'CONFIRMED', 'COMPLETED', 'CANCELLED'
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_assign_history_patient ON public.patient_assignment_history(patient_id);
CREATE INDEX IF NOT EXISTS idx_assign_history_doctor ON public.patient_assignment_history(doctor_id);
CREATE INDEX IF NOT EXISTS idx_assign_history_assigned_by ON public.patient_assignment_history(assigned_by_user_id);
CREATE INDEX IF NOT EXISTS idx_assign_history_district ON public.patient_assignment_history(district_id);
CREATE INDEX IF NOT EXISTS idx_assign_history_source ON public.patient_assignment_history(assignment_source);
CREATE INDEX IF NOT EXISTS idx_assign_history_created_at ON public.patient_assignment_history(created_at);

-- 6. EXTEND USERS AND PATIENT REQUESTS WITH DISTRICT FIELDS (Non-destructive)
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS district_id UUID REFERENCES public.districts(id) ON DELETE SET NULL;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS district VARCHAR(150) DEFAULT '';
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS district_identification_status VARCHAR(50) DEFAULT 'IDENTIFIED';

ALTER TABLE public.patient_problem_requests ADD COLUMN IF NOT EXISTS district_id UUID REFERENCES public.districts(id) ON DELETE SET NULL;
ALTER TABLE public.patient_problem_requests ADD COLUMN IF NOT EXISTS district VARCHAR(150) DEFAULT '';
ALTER TABLE public.patient_problem_requests ADD COLUMN IF NOT EXISTS district_identification_status VARCHAR(50) DEFAULT 'IDENTIFIED';

ALTER TABLE public.dentists ADD COLUMN IF NOT EXISTS district_id UUID REFERENCES public.districts(id) ON DELETE SET NULL;
ALTER TABLE public.dentists ADD COLUMN IF NOT EXISTS district VARCHAR(150) DEFAULT '';

-- 7. ENABLE ROW LEVEL SECURITY (RLS)
ALTER TABLE public.districts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sub_admin_districts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sub_admin_permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.permission_change_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.patient_assignment_history ENABLE ROW LEVEL SECURITY;

DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Allow All Districts') THEN
        CREATE POLICY "Allow All Districts" ON public.districts FOR ALL USING (true);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Allow All Sub Admin Districts') THEN
        CREATE POLICY "Allow All Sub Admin Districts" ON public.sub_admin_districts FOR ALL USING (true);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Allow All Sub Admin Permissions') THEN
        CREATE POLICY "Allow All Sub Admin Permissions" ON public.sub_admin_permissions FOR ALL USING (true);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Allow All Permission Change History') THEN
        CREATE POLICY "Allow All Permission Change History" ON public.permission_change_history FOR ALL USING (true);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Allow All Patient Assignment History') THEN
        CREATE POLICY "Allow All Patient Assignment History" ON public.patient_assignment_history FOR ALL USING (true);
    END IF;
END $$;

-- 8. SEED INITIAL DISTRICTS (Idempotent seed)
INSERT INTO public.districts (name, state, country, is_active)
VALUES
    ('Hyderabad', 'Telangana', 'India', true),
    ('Medchal-Malkajgiri', 'Telangana', 'India', true),
    ('Rangareddy', 'Telangana', 'India', true),
    ('Warangal', 'Telangana', 'India', true),
    ('Karimnagar', 'Telangana', 'India', true),
    ('Nizamabad', 'Telangana', 'India', true),
    ('Adilabad', 'Telangana', 'India', true),
    ('Khammam', 'Telangana', 'India', true),
    ('Nalgonda', 'Telangana', 'India', true),
    ('Mahabubnagar', 'Telangana', 'India', true),
    ('Mumbai City', 'Maharashtra', 'India', true),
    ('Mumbai Suburban', 'Maharashtra', 'India', true),
    ('Pune', 'Maharashtra', 'India', true),
    ('Thane', 'Maharashtra', 'India', true),
    ('Bengaluru Urban', 'Karnataka', 'India', true),
    ('Chennai', 'Tamil Nadu', 'India', true),
    ('Delhi', 'Delhi', 'India', true)
ON CONFLICT (name) DO UPDATE 
SET state = EXCLUDED.state, is_active = EXCLUDED.is_active;
