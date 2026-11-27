-- =============================================================================
-- ROLLBACK 08: STRICT SUB-ADMIN DISTRICT-BASED PATIENT ACCESS CONTROL
-- Target: STAGING SUPABASE ONLY (ojinzcdldwugpnxrnjcq)
-- Non-destructive index cleanup; retains columns by default unless explicitly dropped.
-- =============================================================================

BEGIN;

DROP INDEX IF EXISTS public.idx_users_role_district_id;
DROP INDEX IF EXISTS public.idx_users_role_state_district;
DROP INDEX IF EXISTS public.idx_problem_requests_district_id;
DROP INDEX IF EXISTS public.idx_referrals_patient_district_id;

-- Optional destructive column drops (commented out to prevent unintended data loss):
-- ALTER TABLE public.users DROP COLUMN IF EXISTS district_id;
-- ALTER TABLE public.users DROP COLUMN IF EXISTS district;
-- ALTER TABLE public.patient_problem_requests DROP COLUMN IF EXISTS district_id;
-- ALTER TABLE public.patient_problem_requests DROP COLUMN IF EXISTS district;
-- ALTER TABLE public.referrals DROP COLUMN IF EXISTS patient_district_id;
-- ALTER TABLE public.referrals DROP COLUMN IF EXISTS referred_patient_district;
-- ALTER TABLE public.referrals DROP COLUMN IF EXISTS referred_patient_state;

COMMIT;
