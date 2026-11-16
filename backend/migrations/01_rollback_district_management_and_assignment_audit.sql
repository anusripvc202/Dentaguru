-- =============================================================================
-- GS HEALTH ROLLBACK SCRIPT: 01_rollback_district_management_and_assignment_audit.sql
-- Reverses non-core extensions introduced in 01_district_management_and_assignment_audit.sql
-- =============================================================================

DROP TABLE IF EXISTS public.patient_assignment_history CASCADE;
DROP TABLE IF EXISTS public.permission_change_history CASCADE;
DROP TABLE IF EXISTS public.sub_admin_districts CASCADE;
DROP TABLE IF EXISTS public.districts CASCADE;

-- Drop added columns from existing tables safely
ALTER TABLE public.users DROP COLUMN IF EXISTS district_id;
ALTER TABLE public.users DROP COLUMN IF EXISTS district;
ALTER TABLE public.users DROP COLUMN IF EXISTS district_identification_status;

ALTER TABLE public.patient_problem_requests DROP COLUMN IF EXISTS district_id;
ALTER TABLE public.patient_problem_requests DROP COLUMN IF EXISTS district;
ALTER TABLE public.patient_problem_requests DROP COLUMN IF EXISTS district_identification_status;

ALTER TABLE public.dentists DROP COLUMN IF EXISTS district_id;
ALTER TABLE public.dentists DROP COLUMN IF EXISTS district;
