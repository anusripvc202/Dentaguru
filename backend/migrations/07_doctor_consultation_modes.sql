-- =============================================================================
-- MIGRATION 07: DOCTOR CONSULTATION AVAILABILITY MODES (ONLINE & IN-PERSON)
-- Target: STAGING SUPABASE ONLY (DO NOT EXECUTE ON PRODUCTION WITHOUT APPROVAL)
-- =============================================================================
-- Purpose:
--   1. Store whether a doctor supports online consultation (`online_consultation_enabled`).
--   2. Store whether a doctor supports in-person clinic consultation (`in_person_consultation_enabled`).
--   3. Support Online-Only, In-Person-Only, and Both consultation modes.
--   4. Important Safety Rule: Existing doctors with unknown consultation availability
--      default to `online_consultation_enabled = FALSE` and `in_person_consultation_enabled = TRUE`
--      so offline/unknown doctors are never falsely listed under Online Consultation.
-- =============================================================================

BEGIN;

ALTER TABLE public.dentists
  ADD COLUMN IF NOT EXISTS online_consultation_enabled BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS in_person_consultation_enabled BOOLEAN NOT NULL DEFAULT TRUE;

-- Ensure every doctor supports at least one consultation mode (Online, In-Person, or Both)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'dentists_at_least_one_consultation_mode_chk'
  ) THEN
    ALTER TABLE public.dentists
      ADD CONSTRAINT dentists_at_least_one_consultation_mode_chk
      CHECK (online_consultation_enabled = TRUE OR in_person_consultation_enabled = TRUE);
  END IF;
END $$;

-- Composite index for fast Online / Offline doctor filtering in Patient Dashboard
CREATE INDEX IF NOT EXISTS idx_dentists_consultation_modes
  ON public.dentists (online_consultation_enabled, in_person_consultation_enabled, is_available);

COMMIT;
