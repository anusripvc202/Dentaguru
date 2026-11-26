-- ============================================================================
-- Migration 05: Doctor Clinic Details & OpenStreetMap Coordinates
-- Target: Staging Supabase (ojinzcdldwugpnxrnjcq) — LOCAL FILE ONLY
-- Additive, idempotent, 100% backward-compatible with existing doctors & clinics
-- ============================================================================

BEGIN;

-- 1. Add dedicated clinic & location columns to public.dentists
ALTER TABLE public.dentists
  ADD COLUMN IF NOT EXISTS clinic_name VARCHAR(255),
  ADD COLUMN IF NOT EXISTS clinic_address TEXT,
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

-- 4. Coordinate range validation constraint (idempotent, NULL-safe for legacy rows)
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

-- 5. Supporting indexes for doctor location lookup & geospatial filtering
CREATE INDEX IF NOT EXISTS idx_dentists_city_pincode
  ON public.dentists (city, pincode);

CREATE INDEX IF NOT EXISTS idx_dentists_geo_coords
  ON public.dentists (latitude, longitude)
  WHERE latitude IS NOT NULL AND longitude IS NOT NULL;

COMMIT;
