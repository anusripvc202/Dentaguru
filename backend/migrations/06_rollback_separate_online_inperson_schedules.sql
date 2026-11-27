-- =============================================================================
-- GS HEALTH / DENTAGURU ROLLBACK: 06_rollback_separate_online_inperson_schedules.sql
-- Target Environment: STAGING ONLY (ojinzcdldwugpnxrnjcq)
-- Purpose: Non-destructive rollback for 06_separate_online_inperson_schedules.sql
--          Archives separate Online schedule settings before resetting defaults.
-- Safety: Transactional, Idempotent, Zero DROP TABLE / Zero DROP COLUMN.
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
            'ROLLBACK BLOCKED BY STAGING SAFETY GATE: Independently verify Supabase Dashboard project ref equals "%" before flipping flags in a temporary execution copy.',
            v_expected_project_ref;
    END IF;
END $$;

CREATE SCHEMA IF NOT EXISTS archive_phase6_rollback;

CREATE TABLE IF NOT EXISTS archive_phase6_rollback.doctor_scheduling_settings_backup AS
SELECT * FROM public.doctor_scheduling_settings WHERE FALSE;

INSERT INTO archive_phase6_rollback.doctor_scheduling_settings_backup
SELECT * FROM public.doctor_scheduling_settings;

UPDATE public.doctor_scheduling_settings
   SET use_separate_online_hours = FALSE,
       online_breaks = '[]'::jsonb,
       online_has_break = FALSE,
       online_break_start_time = NULL,
       online_break_end_time = NULL,
       updated_at = NOW();

COMMIT;
