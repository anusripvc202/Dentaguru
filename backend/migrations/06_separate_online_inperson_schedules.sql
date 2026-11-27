-- =============================================================================
-- GS HEALTH / DENTAGURU MIGRATION: 06_separate_online_inperson_schedules.sql
-- Target Environment: STAGING ONLY (ojinzcdldwugpnxrnjcq)
-- Purpose: Add dedicated columns for Separate Online & In-Person Working Hours
--          and Online Breaks on public.doctor_scheduling_settings.
-- Safety: Transactional, Idempotent, Non-Destructive, Staging Safety Gate Enabled.
--         Prepared locally only — DO NOT EXECUTE without explicit approval.
-- =============================================================================

BEGIN;

-- 0. EXPLICIT STAGING ENVIRONMENT CONFIRMATION GATE (Aborts by default!)
DO $$
DECLARE
    v_confirm_staging_deployment  CONSTANT BOOLEAN := false;
    v_confirm_staging_project_ref CONSTANT TEXT    := '';
    v_expected_project_ref        CONSTANT TEXT    := 'ojinzcdldwugpnxrnjcq';
BEGIN
    IF NOT v_confirm_staging_deployment
       OR v_confirm_staging_project_ref IS DISTINCT FROM v_expected_project_ref THEN
        RAISE EXCEPTION
            'MIGRATION BLOCKED BY STAGING SAFETY GATE: Independently verify Supabase Dashboard project ref equals "%" before flipping flags in a temporary execution copy.',
            v_expected_project_ref;
    END IF;
END $$;

-- 1. Extend public.doctor_scheduling_settings with separate Online schedule & break columns
ALTER TABLE IF EXISTS public.doctor_scheduling_settings
    ADD COLUMN IF NOT EXISTS use_separate_online_hours BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS online_breaks JSONB NOT NULL DEFAULT '[]'::jsonb,
    ADD COLUMN IF NOT EXISTS online_has_break BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS online_break_start_time TEXT,
    ADD COLUMN IF NOT EXISTS online_break_end_time TEXT;

COMMIT;
