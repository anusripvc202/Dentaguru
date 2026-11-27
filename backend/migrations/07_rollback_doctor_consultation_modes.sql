-- =============================================================================
-- ROLLBACK 07: DOCTOR CONSULTATION AVAILABILITY MODES (ONLINE & IN-PERSON)
-- Target: STAGING SUPABASE ONLY
-- =============================================================================

BEGIN;

DROP INDEX IF EXISTS public.idx_dentists_consultation_modes;

ALTER TABLE public.dentists
  DROP CONSTRAINT IF EXISTS dentists_at_least_one_consultation_mode_chk;

ALTER TABLE public.dentists
  DROP COLUMN IF EXISTS online_consultation_enabled,
  DROP COLUMN IF EXISTS in_person_consultation_enabled;

COMMIT;
