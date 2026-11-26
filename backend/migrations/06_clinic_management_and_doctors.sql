-- =============================================================================
-- Migration 06: Clinic Management Structured Location & Clinic-Doctor Associations
-- Target Environment: STAGING ONLY (ojinzcdldwugpnxrnjcq)
-- DO NOT EXECUTE AUTOMATICALLY — FOR REVIEW & APPROVAL BEFORE RUNNING IN SUPABASE
-- =============================================================================

BEGIN;

-- 1. Add structured address & coordinate columns to public.clinics (idempotent)
ALTER TABLE public.clinics
    ADD COLUMN IF NOT EXISTS clinic_address TEXT,
    ADD COLUMN IF NOT EXISTS city VARCHAR(120),
    ADD COLUMN IF NOT EXISTS state VARCHAR(120),
    ADD COLUMN IF NOT EXISTS pincode VARCHAR(10),
    ADD COLUMN IF NOT EXISTS latitude DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS longitude DOUBLE PRECISION;

-- 2. Backfill clinic_address from existing location where clinic_address is empty
UPDATE public.clinics
SET clinic_address = location
WHERE (clinic_address IS NULL OR BTRIM(clinic_address) = '')
  AND location IS NOT NULL
  AND BTRIM(location) <> '';

-- 3. Backfill city/state/pincode/coordinates from linked clinic owner user row where missing
UPDATE public.clinics c
SET
    city = COALESCE(NULLIF(BTRIM(c.city), ''), NULLIF(BTRIM(u.city), '')),
    state = COALESCE(NULLIF(BTRIM(c.state), ''), NULLIF(BTRIM(u.state), '')),
    pincode = COALESCE(NULLIF(BTRIM(c.pincode), ''), NULLIF(BTRIM(u.pincode), '')),
    latitude = COALESCE(c.latitude, u.latitude),
    longitude = COALESCE(c.longitude, u.longitude)
FROM public.users u
WHERE c.user_id = u.id;

-- 4. Coordinate bounds & pairing check constraint on public.clinics
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'chk_clinics_valid_coordinates'
          AND conrelid = 'public.clinics'::regclass
    ) THEN
        ALTER TABLE public.clinics
            ADD CONSTRAINT chk_clinics_valid_coordinates
            CHECK (
                (latitude IS NULL AND longitude IS NULL)
                OR (
                    latitude IS NOT NULL
                    AND longitude IS NOT NULL
                    AND latitude BETWEEN -90 AND 90
                    AND longitude BETWEEN -180 AND 180
                )
            );
    END IF;
END $$;

-- 5. Create normalized clinic_doctors association table (prevents duplicate clinic-doctor links)
CREATE TABLE IF NOT EXISTS public.clinic_doctors (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    clinic_id UUID NOT NULL REFERENCES public.clinics(id) ON DELETE CASCADE,
    doctor_id UUID NOT NULL REFERENCES public.dentists(id) ON DELETE CASCADE,
    status VARCHAR(32) NOT NULL DEFAULT 'ACTIVE',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_clinic_doctors_clinic_doctor UNIQUE (clinic_id, doctor_id)
);

-- 6. Backfill existing dentists.clinic_id links into public.clinic_doctors (idempotent)
INSERT INTO public.clinic_doctors (clinic_id, doctor_id, status)
SELECT d.clinic_id, d.id, 'ACTIVE'
FROM public.dentists d
INNER JOIN public.clinics c ON c.id = d.clinic_id
WHERE d.clinic_id IS NOT NULL
ON CONFLICT (clinic_id, doctor_id) DO NOTHING;

-- 7. Indexes for fast clinic search and clinic-wise doctor lookups
CREATE INDEX IF NOT EXISTS idx_clinics_city_lower ON public.clinics (LOWER(city));
CREATE INDEX IF NOT EXISTS idx_clinics_state_lower ON public.clinics (LOWER(state));
CREATE INDEX IF NOT EXISTS idx_clinics_pincode ON public.clinics (pincode);
CREATE INDEX IF NOT EXISTS idx_clinic_doctors_clinic_id ON public.clinic_doctors (clinic_id);
CREATE INDEX IF NOT EXISTS idx_clinic_doctors_doctor_id ON public.clinic_doctors (doctor_id);

COMMIT;
