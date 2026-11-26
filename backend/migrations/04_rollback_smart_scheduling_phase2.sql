-- =============================================================================
-- GS HEALTH ROLLBACK: 04_rollback_smart_scheduling_phase2.sql (100% DATA-PRESERVING)
-- Target Environment: STAGING ONLY (ojinzcdldwugpnxrnjcq)
-- Guarantee: ZERO DROP TABLE and ZERO DROP COLUMN statements.
--            Archives all Phase 2 data into archive_phase2_rollback, removes only
--            enforcement hooks/RPCs/constraints/Realtime publications, locks retained
--            tables to service_role, and preserves 100% Phase 1 compatibility.
-- =============================================================================

BEGIN;

-- 0. EXPLICIT STAGING ROLLBACK SAFETY GATE (Aborts by default!)
DO $$
DECLARE
    v_confirm_staging_rollback    CONSTANT BOOLEAN := false;
    v_confirm_staging_project_ref CONSTANT TEXT    := '';
    v_expected_project_ref        CONSTANT TEXT    := 'ojinzcdldwugpnxrnjcq';
BEGIN
    IF NOT v_confirm_staging_rollback
       OR v_confirm_staging_project_ref IS DISTINCT FROM v_expected_project_ref THEN
        RAISE EXCEPTION
            'ROLLBACK BLOCKED BY STAGING SAFETY GATE: Verify Supabase project ref equals "%" before executing.',
            v_expected_project_ref;
    END IF;
END $$;

-- 1. ARCHIVE ALL PHASE 2 DATA INTO archive_phase2_rollback WITH ROW-COUNT AUDIT
CREATE SCHEMA IF NOT EXISTS archive_phase2_rollback;
REVOKE ALL ON SCHEMA archive_phase2_rollback FROM PUBLIC, anon, authenticated;

DO $$
DECLARE
    v_ts  TEXT := to_char(NOW() AT TIME ZONE 'UTC', 'YYYYMMDD_HH24MISS');
    v_cnt BIGINT;
BEGIN
    IF to_regclass('public.doctor_scheduling_settings') IS NOT NULL THEN
        EXECUTE format('CREATE TABLE archive_phase2_rollback.doctor_scheduling_settings_%s AS SELECT * FROM public.doctor_scheduling_settings', v_ts);
        EXECUTE format('SELECT COUNT(*) FROM archive_phase2_rollback.doctor_scheduling_settings_%s', v_ts) INTO v_cnt;
        RAISE NOTICE '[Rollback Archive] doctor_scheduling_settings archived: % rows', v_cnt;
    END IF;

    IF to_regclass('public.released_slots') IS NOT NULL THEN
        EXECUTE format('CREATE TABLE archive_phase2_rollback.released_slots_%s AS SELECT * FROM public.released_slots', v_ts);
        EXECUTE format('SELECT COUNT(*) FROM archive_phase2_rollback.released_slots_%s', v_ts) INTO v_cnt;
        RAISE NOTICE '[Rollback Archive] released_slots archived: % rows', v_cnt;
    END IF;

    IF to_regclass('public.appointment_slot_locks') IS NOT NULL THEN
        EXECUTE format('CREATE TABLE archive_phase2_rollback.appointment_slot_locks_%s AS SELECT * FROM public.appointment_slot_locks', v_ts);
        EXECUTE format('SELECT COUNT(*) FROM archive_phase2_rollback.appointment_slot_locks_%s', v_ts) INTO v_cnt;
        RAISE NOTICE '[Rollback Archive] appointment_slot_locks archived: % rows', v_cnt;
    END IF;

    IF to_regclass('public.patient_doctor_preferences') IS NOT NULL THEN
        EXECUTE format('CREATE TABLE archive_phase2_rollback.patient_doctor_preferences_%s AS SELECT * FROM public.patient_doctor_preferences', v_ts);
        EXECUTE format('SELECT COUNT(*) FROM archive_phase2_rollback.patient_doctor_preferences_%s', v_ts) INTO v_cnt;
        RAISE NOTICE '[Rollback Archive] patient_doctor_preferences archived: % rows', v_cnt;
    END IF;

    IF to_regclass('public.slot_notification_deliveries') IS NOT NULL THEN
        EXECUTE format('CREATE TABLE archive_phase2_rollback.slot_notification_deliveries_%s AS SELECT * FROM public.slot_notification_deliveries', v_ts);
        EXECUTE format('SELECT COUNT(*) FROM archive_phase2_rollback.slot_notification_deliveries_%s', v_ts) INTO v_cnt;
        RAISE NOTICE '[Rollback Archive] slot_notification_deliveries archived: % rows', v_cnt;
    END IF;

    EXECUTE format(
        'CREATE TABLE archive_phase2_rollback.appointments_timing_%s AS SELECT id, appointment_date, consultation_type, capacity_lane, duration_minutes, buffer_minutes, delay_minutes, scheduled_start_min, scheduled_end_min, effective_end_min, scheduled_start_at, scheduled_end_at, actual_start_at, actual_end_at, finished_early, released_slot_id FROM public.appointments',
        v_ts
    );

    EXECUTE format(
        'CREATE TABLE archive_phase2_rollback.notifications_data_%s AS SELECT id, data FROM public.notifications WHERE data IS NOT NULL AND data <> ''{}''::jsonb',
        v_ts
    );
END $$;

-- 2. REMOVE PHASE 2 REALTIME PUBLICATIONS (Leaves public.appointments & Phase 1 untouched)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
        BEGIN ALTER PUBLICATION supabase_realtime DROP TABLE public.released_slots; EXCEPTION WHEN undefined_object THEN NULL; END;
        BEGIN ALTER PUBLICATION supabase_realtime DROP TABLE public.doctor_scheduling_settings; EXCEPTION WHEN undefined_object THEN NULL; END;
    END IF;
END $$;

-- 3. DROP ONLY PHASE 2 ENFORCEMENT HOOKS (Phase 1 backend works immediately; ALL data retained!)
DROP FUNCTION IF EXISTS public.confirm_appointment_booking(UUID, UUID, UUID, DATE, TEXT, INTEGER, INTEGER, INTEGER, TEXT, TEXT, TEXT, TEXT, UUID, UUID);
DROP FUNCTION IF EXISTS public.release_appointment_slot_lock(UUID, UUID);
DROP FUNCTION IF EXISTS public.acquire_appointment_slot_lock(UUID, UUID, DATE, TEXT, TEXT, INTEGER, INTEGER, TEXT, UUID, INTEGER);

DROP TRIGGER IF EXISTS trg_appointments_sync_timing_intervals ON public.appointments;
DROP FUNCTION IF EXISTS public.sync_appointment_timing_intervals();

ALTER TABLE public.appointments DROP CONSTRAINT IF EXISTS excl_appointments_no_overlapping_intervals;
ALTER TABLE public.appointments DROP CONSTRAINT IF EXISTS chk_appointments_active_timing_not_null;

-- 4. LOCK DOWN RETAINED PHASE 2 TABLES TO service_role ONLY (No anon/authenticated access while rolled back)
DO $$
BEGIN
    IF to_regclass('public.doctor_scheduling_settings') IS NOT NULL THEN
        DROP POLICY IF EXISTS p2_sched_settings_auth_select ON public.doctor_scheduling_settings;
    END IF;
    IF to_regclass('public.released_slots') IS NOT NULL THEN
        DROP POLICY IF EXISTS p2_released_slots_auth_select ON public.released_slots;
    END IF;
    IF to_regclass('public.appointment_slot_locks') IS NOT NULL THEN
        DROP POLICY IF EXISTS p2_slot_locks_own_select ON public.appointment_slot_locks;
    END IF;
    IF to_regclass('public.patient_doctor_preferences') IS NOT NULL THEN
        DROP POLICY IF EXISTS p2_pat_prefs_own_all ON public.patient_doctor_preferences;
    END IF;
END $$;

DROP FUNCTION IF EXISTS public.gs_health_active_dentist_id();
DROP FUNCTION IF EXISTS public.gs_health_active_user_id();
DROP FUNCTION IF EXISTS public.gs_health_try_uuid(TEXT);
DROP FUNCTION IF EXISTS public.parse_clock_slot_minutes(TEXT);

COMMIT;
