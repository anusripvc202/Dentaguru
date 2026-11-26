-- =============================================================================
-- Rollback 06 (NON-DESTRUCTIVE): Archive & Safely Roll Back Constraints/Indexes
-- Preserves all clinic location data and clinic-doctor association records.
-- Zero DROP COLUMN, zero DROP TABLE, zero DELETE, zero TRUNCATE.
-- =============================================================================

BEGIN;

-- 1. Non-destructive archive snapshot of clinics structured location fields
CREATE TABLE IF NOT EXISTS public._rollback_archive_06_clinics_location (
    archived_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    clinic_id UUID NOT NULL,
    clinic_name TEXT,
    clinic_address TEXT,
    city VARCHAR(120),
    state VARCHAR(120),
    pincode VARCHAR(10),
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION
);

INSERT INTO public._rollback_archive_06_clinics_location (
    clinic_id, clinic_name, clinic_address, city, state, pincode, latitude, longitude
)
SELECT
    c.id, c.clinic_name, c.clinic_address, c.city, c.state, c.pincode, c.latitude, c.longitude
FROM public.clinics c;

-- 2. Non-destructive archive snapshot of clinic_doctors associations (if table exists)
DO $$
BEGIN
    IF to_regclass('public.clinic_doctors') IS NOT NULL THEN
        CREATE TABLE IF NOT EXISTS public._rollback_archive_06_clinic_doctors (
            archived_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            association_id UUID,
            clinic_id UUID,
            doctor_id UUID,
            status VARCHAR(32)
        );
        INSERT INTO public._rollback_archive_06_clinic_doctors (
            association_id, clinic_id, doctor_id, status
        )
        SELECT id, clinic_id, doctor_id, status
        FROM public.clinic_doctors;
    END IF;
END $$;

-- 3. Drop only Migration 06 constraint & indexes (all columns and rows remain intact)
ALTER TABLE public.clinics DROP CONSTRAINT IF EXISTS chk_clinics_valid_coordinates;
DROP INDEX IF EXISTS public.idx_clinics_city_lower;
DROP INDEX IF EXISTS public.idx_clinics_state_lower;
DROP INDEX IF EXISTS public.idx_clinics_pincode;
DROP INDEX IF EXISTS public.idx_clinic_doctors_clinic_id;
DROP INDEX IF EXISTS public.idx_clinic_doctors_doctor_id;

COMMIT;
