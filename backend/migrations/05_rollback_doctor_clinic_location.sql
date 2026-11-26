-- ============================================================================
-- Rollback for Migration 05: Non-Destructive Rollback
-- Preserves all doctor clinic names, clinic addresses, consultation modes,
-- and OpenStreetMap coordinates in an archive table and leaves data columns
-- intact so zero production/staging doctor location data is ever lost.
-- ============================================================================

BEGIN;

-- 1. Archive snapshot of all doctor clinic & location fields before relaxing constraints
CREATE TABLE IF NOT EXISTS public._rollback_archive_05_dentists_clinic_location (
  archived_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  dentist_id UUID NOT NULL,
  user_id UUID,
  clinic_id UUID,
  clinic_name VARCHAR(255),
  clinic_address TEXT,
  consultation_mode VARCHAR(30),
  state VARCHAR(100),
  city VARCHAR(100),
  pincode VARCHAR(20),
  latitude NUMERIC,
  longitude NUMERIC
);

INSERT INTO public._rollback_archive_05_dentists_clinic_location (
  dentist_id,
  user_id,
  clinic_id,
  clinic_name,
  clinic_address,
  consultation_mode,
  state,
  city,
  pincode,
  latitude,
  longitude
)
SELECT
  id,
  user_id,
  clinic_id,
  clinic_name,
  clinic_address,
  consultation_mode,
  state,
  city,
  pincode,
  latitude,
  longitude
FROM public.dentists;

-- 2. Drop only Migration 05 constraints & indexes (data columns are preserved non-destructively)
DROP INDEX IF EXISTS public.idx_dentists_geo_coords;
DROP INDEX IF EXISTS public.idx_dentists_consultation_mode;
DROP INDEX IF EXISTS public.idx_dentists_city_pincode;

ALTER TABLE public.dentists
  DROP CONSTRAINT IF EXISTS dentists_lat_lng_range_check;

ALTER TABLE public.dentists
  DROP CONSTRAINT IF EXISTS dentists_consultation_mode_check;

COMMIT;
