-- =============================================================================
-- MIGRATION 08: STRICT SUB-ADMIN DISTRICT-BASED PATIENT ACCESS CONTROL
-- Target: STAGING SUPABASE ONLY (ojinzcdldwugpnxrnjcq)
-- DO NOT EXECUTE ON PRODUCTION (fommrwxpqzkcktweosgp) WITHOUT APPROVAL.
-- Note: Local staging preparation file only (idempotent & non-destructive).
-- =============================================================================

BEGIN;

-- 1. Ensure patient district identification columns exist on users
ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS district_id VARCHAR(100),
    ADD COLUMN IF NOT EXISTS district VARCHAR(150),
    ADD COLUMN IF NOT EXISTS state VARCHAR(100);

CREATE INDEX IF NOT EXISTS idx_users_role_district_id
    ON public.users(role, district_id);
CREATE INDEX IF NOT EXISTS idx_users_role_state_district
    ON public.users(role, state, district);

-- 2. Ensure districts catalog contains all active canonical districts (including AP)
INSERT INTO public.districts (id, name, state, country, is_active)
SELECT v.id::uuid, v.name, v.state, 'India', true
FROM (VALUES
    ('00000000-0000-0000-0000-000000000001', 'Hyderabad', 'Telangana'),
    ('00000000-0000-0000-0000-000000000002', 'Medchal-Malkajgiri', 'Telangana'),
    ('00000000-0000-0000-0000-000000000003', 'Rangareddy', 'Telangana'),
    ('00000000-0000-0000-0000-000000000004', 'Warangal', 'Telangana'),
    ('00000000-0000-0000-0000-000000000005', 'Karimnagar', 'Telangana'),
    ('00000000-0000-0000-0000-000000000006', 'Nizamabad', 'Telangana'),
    ('00000000-0000-0000-0000-000000000007', 'Adilabad', 'Telangana'),
    ('00000000-0000-0000-0000-000000000008', 'Khammam', 'Telangana'),
    ('00000000-0000-0000-0000-000000000009', 'Nalgonda', 'Telangana'),
    ('00000000-0000-0000-0000-000000000010', 'Mahabubnagar', 'Telangana'),
    ('00000000-0000-0000-0000-000000000018', 'Visakhapatnam', 'Andhra Pradesh'),
    ('00000000-0000-0000-0000-000000000019', 'Vijayawada', 'Andhra Pradesh'),
    ('00000000-0000-0000-0000-000000000020', 'Guntur', 'Andhra Pradesh')
) AS v(id, name, state)
WHERE NOT EXISTS (
    SELECT 1 FROM public.districts d WHERE LOWER(d.name) = LOWER(v.name)
);

-- 3. Ensure patient_problem_requests stores patient's own district_id/district/state
ALTER TABLE public.patient_problem_requests
    ADD COLUMN IF NOT EXISTS district_id VARCHAR(100),
    ADD COLUMN IF NOT EXISTS district VARCHAR(150),
    ADD COLUMN IF NOT EXISTS state VARCHAR(100);

CREATE INDEX IF NOT EXISTS idx_problem_requests_district_id
    ON public.patient_problem_requests(district_id);

-- 4. Ensure referrals stores referred patient's own district_id/district/state
ALTER TABLE public.referrals
    ADD COLUMN IF NOT EXISTS patient_district_id VARCHAR(100),
    ADD COLUMN IF NOT EXISTS referred_patient_district VARCHAR(150),
    ADD COLUMN IF NOT EXISTS referred_patient_state VARCHAR(100);

CREATE INDEX IF NOT EXISTS idx_referrals_patient_district_id
    ON public.referrals(patient_district_id);

-- 5. Ensure sub_admin_districts table and lookup indexes exist
CREATE TABLE IF NOT EXISTS public.sub_admin_districts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sub_admin_user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    district_id UUID NOT NULL REFERENCES public.districts(id) ON DELETE CASCADE,
    assigned_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT unique_subadmin_district UNIQUE (sub_admin_user_id, district_id)
);

CREATE INDEX IF NOT EXISTS idx_sub_admin_districts_user
    ON public.sub_admin_districts(sub_admin_user_id);
CREATE INDEX IF NOT EXISTS idx_sub_admin_districts_district
    ON public.sub_admin_districts(district_id);

COMMIT;
