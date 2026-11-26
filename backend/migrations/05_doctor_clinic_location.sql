-- ============================================================================
-- Migration 05: Doctor Clinic Details, Consultation Mode & OpenStreetMap Coords
-- Target: Staging Supabase (ojinzcdldwugpnxrnjcq) — LOCAL FILE ONLY
-- Additive, idempotent, 100% backward-compatible with existing doctors & clinics
-- ============================================================================

BEGIN;

-- 1. Add dedicated clinic & consultation mode columns to public.dentists
ALTER TABLE public.dentists
  ADD COLUMN IF NOT EXISTS clinic_name VARCHAR(255),
  ADD COLUMN IF NOT EXISTS clinic_address TEXT,
  ADD COLUMN IF NOT EXISTS consultation_mode VARCHAR(30) NOT NULL DEFAULT 'BOTH',
  ADD COLUMN IF NOT EXISTS state VARCHAR(100),
  ADD COLUMN IF NOT EXISTS city VARCHAR(100),
  ADD COLUMN IF NOT EXISTS pincode VARCHAR(20),
  ADD COLUMN IF NOT EXISTS latitude NUMERIC,
  ADD COLUMN IF NOT EXISTS longitude NUMERIC;

-- 2. Ensure public.clinics also has nullable latitude / longitude columns
ALTER TABLE public.clinics
  ADD COLUMN IF NOT EXISTS latitude NUMERIC,
  ADD COLUMN IF NOT EXISTS longitude NUMERIC;

-- 3. Backfill dentists.clinic_name / clinic_address / coordinates from linked clinics where missing
UPDATE public.dentists d
SET
  clinic_name = COALESCE(NULLIF(BTRIM(d.clinic_name), ''), NULLIF(BTRIM(c.clinic_name), '')),
  clinic_address = COALESCE(NULLIF(BTRIM(d.clinic_address), ''), NULLIF(BTRIM(c.location), '')),
  latitude = COALESCE(d.latitude, c.latitude),
  longitude = COALESCE(d.longitude, c.longitude)
FROM public.clinics c
WHERE d.clinic_id = c.id
  AND (
    d.clinic_name IS NULL OR BTRIM(d.clinic_name) = ''
    OR d.clinic_address IS NULL OR BTRIM(d.clinic_address) = ''
    OR (d.latitude IS NULL AND c.latitude IS NOT NULL)
    OR (d.longitude IS NULL AND c.longitude IS NOT NULL)
  );

-- 4. Normalize any legacy consultation_mode values before applying CHECK constraint
UPDATE public.dentists
SET consultation_mode = CASE
  WHEN UPPER(BTRIM(COALESCE(consultation_mode, ''))) IN ('ONLINE', 'ONLINE_ONLY', 'ONLINE ONLY') THEN 'ONLINE_ONLY'
  WHEN UPPER(BTRIM(COALESCE(consultation_mode, ''))) IN ('IN_PERSON', 'IN-PERSON', 'IN PERSON', 'CLINIC') THEN 'IN_PERSON'
  ELSE 'BOTH'
END;

-- 5. Add validation constraints (idempotent)
ALTER TABLE public.dentists
  DROP CONSTRAINT IF EXISTS dentists_consultation_mode_check;
ALTER TABLE public.dentists
  ADD CONSTRAINT dentists_consultation_mode_check
  CHECK (consultation_mode IN ('BOTH', 'IN_PERSON', 'ONLINE_ONLY'));

ALTER TABLE public.dentists
  DROP CONSTRAINT IF EXISTS dentists_lat_lng_range_check;
ALTER TABLE public.dentists
  ADD CONSTRAINT dentists_lat_lng_range_check
  CHECK (
    (latitude IS NULL AND longitude IS NULL)
    OR (
      latitude IS NOT NULL
      AND longitude IS NOT NULL
      AND latitude >= -90 AND latitude <= 90
      AND longitude >= -180 AND longitude <= 180
    )
  );

-- 6. Supporting indexes for doctor discovery & geospatial filtering
CREATE INDEX IF NOT EXISTS idx_dentists_city_pincode
  ON public.dentists (city, pincode);

CREATE INDEX IF NOT EXISTS idx_dentists_consultation_mode
  ON public.dentists (consultation_mode);

CREATE INDEX IF NOT EXISTS idx_dentists_geo_coords
  ON public.dentists (latitude, longitude)
  WHERE latitude IS NOT NULL AND longitude IS NOT NULL;

COMMIT;
