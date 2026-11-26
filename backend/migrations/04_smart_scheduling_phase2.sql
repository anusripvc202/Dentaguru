-- =============================================================================
-- GS HEALTH / DENTAGURU MIGRATION: 04_smart_scheduling_phase2.sql (FINAL v4)
-- Target Environment: STAGING ONLY (ojinzcdldwugpnxrnjcq)
-- Safety: Transactional, Idempotent, Non-Destructive, Zero NULL Bypass,
--         Mandatory p_lock_id, Strict Released-Slot Lock Ownership,
--         Custom OTP/JWT-Compatible RLS, service_role-Gated Atomic RPCs
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

CREATE EXTENSION IF NOT EXISTS btree_gist;

-- 1. IMMUTABLE & IDENTITY HELPERS (Custom OTP/JWT + Active User Verification)
CREATE OR REPLACE FUNCTION public.parse_clock_slot_minutes(p_slot TEXT)
RETURNS INTEGER
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    v_match TEXT[];
    v_hour  INTEGER;
    v_min   INTEGER;
    v_ampm  TEXT;
BEGIN
    IF p_slot IS NULL OR btrim(p_slot) = '' THEN RETURN NULL; END IF;
    v_match := regexp_match(btrim(p_slot), '^(\d{1,2}):(\d{2})\s*(AM|PM)$', 'i');
    IF v_match IS NULL THEN RETURN NULL; END IF;
    v_hour := v_match[1]::INTEGER;
    v_min  := v_match[2]::INTEGER;
    v_ampm := upper(v_match[3]);
    IF v_hour < 1 OR v_hour > 12 OR v_min < 0 OR v_min > 59 THEN RETURN NULL; END IF;
    IF v_ampm = 'PM' AND v_hour < 12 THEN v_hour := v_hour + 12; END IF;
    IF v_ampm = 'AM' AND v_hour = 12 THEN v_hour := 0; END IF;
    RETURN v_hour * 60 + v_min;
END;
$$;

CREATE OR REPLACE FUNCTION public.gs_health_try_uuid(p_raw TEXT)
RETURNS UUID
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
    IF p_raw IS NULL OR btrim(p_raw) = '' THEN RETURN NULL; END IF;
    RETURN btrim(p_raw)::UUID;
EXCEPTION WHEN others THEN
    RETURN NULL;
END;
$$;

-- Resolves canonical ACTIVE public.users.id from GS Health custom Realtime JWT (sub / user_id)
CREATE OR REPLACE FUNCTION public.gs_health_active_user_id()
RETURNS UUID
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_claims_raw TEXT;
    v_claims     JSONB;
    v_candidate  UUID;
    v_active_id  UUID;
BEGIN
    v_claims_raw := NULLIF(btrim(current_setting('request.jwt.claims', true)), '');
    IF v_claims_raw IS NOT NULL THEN
        BEGIN
            v_claims := v_claims_raw::JSONB;
            v_candidate := COALESCE(
                public.gs_health_try_uuid(v_claims ->> 'sub'),
                public.gs_health_try_uuid(v_claims ->> 'user_id')
            );
        EXCEPTION WHEN others THEN
            v_candidate := NULL;
        END;
    END IF;

    IF v_candidate IS NULL THEN
        v_candidate := public.gs_health_try_uuid(NULLIF(btrim(current_setting('request.jwt.claim.sub', true)), ''));
    END IF;

    IF v_candidate IS NULL THEN
        RETURN NULL;
    END IF;

    -- Fail closed: must exist in public.users with explicit ACTIVE status
    SELECT u.id INTO v_active_id
      FROM public.users u
     WHERE u.id = v_candidate
       AND upper(btrim(COALESCE(u.status, ''))) = 'ACTIVE'
     LIMIT 1;

    RETURN v_active_id;
END;
$$;

-- Resolves canonical public.dentists.id for an ACTIVE authenticated doctor
CREATE OR REPLACE FUNCTION public.gs_health_active_dentist_id()
RETURNS UUID
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_uid        UUID := public.gs_health_active_user_id();
    v_dentist_id UUID;
BEGIN
    IF v_uid IS NULL THEN RETURN NULL; END IF;
    SELECT d.id INTO v_dentist_id
      FROM public.dentists d
     WHERE d.user_id = v_uid
     LIMIT 1;
    RETURN v_dentist_id;
END;
$$;

-- 2. DOCTOR SMART SCHEDULING SETTINGS (Strictly separate from users.device_token)
CREATE TABLE IF NOT EXISTS public.doctor_scheduling_settings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    dentist_id UUID NOT NULL UNIQUE REFERENCES public.dentists(id) ON DELETE CASCADE,
    working_days TEXT[] NOT NULL DEFAULT ARRAY['Monday','Tuesday','Wednesday','Thursday','Friday'],
    start_time TEXT NOT NULL DEFAULT '09:00 AM',
    end_time TEXT NOT NULL DEFAULT '05:00 PM',
    breaks JSONB NOT NULL DEFAULT '[{"startTime":"01:00 PM","endTime":"02:00 PM"}]'::jsonb,
    default_duration_minutes INTEGER NOT NULL DEFAULT 30
        CHECK (default_duration_minutes IN (15, 20, 30, 45, 60)),
    in_person_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    in_person_duration_minutes INTEGER NOT NULL DEFAULT 30
        CHECK (in_person_duration_minutes IN (15, 20, 30, 45, 60)),
    online_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    online_duration_minutes INTEGER NOT NULL DEFAULT 20
        CHECK (online_duration_minutes IN (15, 20, 30, 45, 60)),
    online_working_days TEXT[],
    online_start_time TEXT,
    online_end_time TEXT,
    buffer_minutes INTEGER NOT NULL DEFAULT 5
        CHECK (buffer_minutes >= 0 AND buffer_minutes <= 60),
    online_buffer_minutes INTEGER NOT NULL DEFAULT 5
        CHECK (online_buffer_minutes >= 0 AND online_buffer_minutes <= 60),
    in_person_buffer_minutes INTEGER NOT NULL DEFAULT 10
        CHECK (in_person_buffer_minutes >= 0 AND in_person_buffer_minutes <= 60),
    max_appointments_per_day INTEGER
        CHECK (max_appointments_per_day IS NULL OR max_appointments_per_day > 0),
    allow_simultaneous_online_and_in_person BOOLEAN NOT NULL DEFAULT FALSE,
    blocked_time_ranges JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_doctor_scheduling_settings_dentist
    ON public.doctor_scheduling_settings (dentist_id);

-- 3. RELEASED EARLY-COMPLETION SLOTS
CREATE TABLE IF NOT EXISTS public.released_slots (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    dentist_id UUID NOT NULL REFERENCES public.dentists(id) ON DELETE CASCADE,
    source_appointment_id UUID REFERENCES public.appointments(id) ON DELETE SET NULL,
    appointment_date DATE NOT NULL,
    start_time TEXT NOT NULL,
    end_time TEXT NOT NULL,
    start_min INTEGER NOT NULL CHECK (start_min >= 0 AND start_min < 1440),
    end_min INTEGER NOT NULL CHECK (end_min > start_min AND end_min <= 1440),
    duration_minutes INTEGER NOT NULL CHECK (duration_minutes IN (15, 20, 30, 45, 60)),
    buffer_minutes INTEGER NOT NULL DEFAULT 0 CHECK (buffer_minutes >= 0 AND buffer_minutes <= 60),
    consultation_type TEXT NOT NULL DEFAULT 'In-Person' CHECK (consultation_type IN ('In-Person', 'Online')),
    status TEXT NOT NULL DEFAULT 'AVAILABLE' CHECK (status IN ('AVAILABLE', 'LOCKED', 'BOOKED', 'EXPIRED')),
    claimed_by_appointment_id UUID REFERENCES public.appointments(id) ON DELETE SET NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_released_slots_dentist_date_status
    ON public.released_slots (dentist_id, appointment_date, status, expires_at);

-- Prevent duplicate active released slots for same doctor/date/type/start_min
CREATE UNIQUE INDEX IF NOT EXISTS uq_released_slots_active_window
    ON public.released_slots (dentist_id, appointment_date, consultation_type, start_min)
    WHERE status IN ('AVAILABLE', 'LOCKED');

-- 4. STRUCTURED TIMING COLUMNS, STRICT TRIGGER & ZERO-BYPASS GiST ON public.appointments
ALTER TABLE public.appointments
    ADD COLUMN IF NOT EXISTS appointment_date DATE,
    ADD COLUMN IF NOT EXISTS consultation_type TEXT DEFAULT 'In-Person',
    ADD COLUMN IF NOT EXISTS capacity_lane TEXT NOT NULL DEFAULT 'SHARED',
    ADD COLUMN IF NOT EXISTS duration_minutes INTEGER DEFAULT 30,
    ADD COLUMN IF NOT EXISTS buffer_minutes INTEGER DEFAULT 0,
    ADD COLUMN IF NOT EXISTS delay_minutes INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS scheduled_start_min INTEGER,
    ADD COLUMN IF NOT EXISTS scheduled_end_min INTEGER,
    ADD COLUMN IF NOT EXISTS effective_end_min INTEGER,
    ADD COLUMN IF NOT EXISTS scheduled_start_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS scheduled_end_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS actual_start_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS actual_end_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS finished_early BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS released_slot_id UUID REFERENCES public.released_slots(id) ON DELETE SET NULL;

CREATE OR REPLACE FUNCTION public.sync_appointment_timing_intervals()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_settings        public.doctor_scheduling_settings%ROWTYPE;
    v_has_settings    BOOLEAN := FALSE;
    v_mode            TEXT;
    v_start_min       INTEGER;
    v_dur             INTEGER;
    v_buf             INTEGER;
    v_status          TEXT;
    v_is_active       BOOLEAN;
    v_actual_end_min  INTEGER;
    v_actual_end_date DATE;
    v_consult_end_min INTEGER;
BEGIN
    v_status := upper(btrim(COALESCE(NEW.status, 'PENDING')));
    v_is_active := v_status NOT IN ('CANCELLED', 'CANCELED', 'REJECTED', 'NO_SHOW');

    IF NEW.appointment_date IS NULL AND NEW.date IS NOT NULL THEN
        NEW.appointment_date := (NEW.date AT TIME ZONE 'Asia/Kolkata')::DATE;
    END IF;

    v_mode := COALESCE(NULLIF(btrim(NEW.consultation_type), ''), '');
    IF v_mode = '' THEN
        IF lower(COALESCE(NEW.treatment, '') || ' ' || COALESCE(NEW.qr_code_string, '')) ~ '(online|video|teleconsult|virtual)' THEN
            v_mode := 'Online';
        ELSE
            v_mode := 'In-Person';
        END IF;
    ELSIF lower(v_mode) ~ '(online|video|teleconsult|virtual)' THEN
        v_mode := 'Online';
    ELSE
        v_mode := 'In-Person';
    END IF;
    NEW.consultation_type := v_mode;

    IF NEW.dentist_id IS NOT NULL THEN
        SELECT * INTO v_settings
          FROM public.doctor_scheduling_settings
         WHERE dentist_id = NEW.dentist_id
         LIMIT 1;
        v_has_settings := FOUND;
    END IF;

    IF v_has_settings AND v_settings.allow_simultaneous_online_and_in_person THEN
        NEW.capacity_lane := upper(v_mode);
    ELSE
        NEW.capacity_lane := 'SHARED';
    END IF;

    IF TG_OP = 'INSERT' OR NEW.scheduled_start_min IS NULL OR NEW.time_slot IS DISTINCT FROM OLD.time_slot THEN
        v_start_min := COALESCE(
            CASE WHEN TG_OP = 'INSERT' OR NEW.time_slot IS NOT DISTINCT FROM OLD.time_slot THEN NEW.scheduled_start_min ELSE NULL END,
            public.parse_clock_slot_minutes(NEW.time_slot)
        );
        NEW.scheduled_start_min := v_start_min;
    ELSE
        v_start_min := NEW.scheduled_start_min;
    END IF;

    IF NEW.duration_minutes IS NULL OR NEW.duration_minutes <= 0 THEN
        v_dur := CASE
            WHEN v_mode = 'Online' THEN CASE WHEN v_has_settings THEN v_settings.online_duration_minutes ELSE 20 END
            ELSE CASE WHEN v_has_settings THEN v_settings.in_person_duration_minutes ELSE 30 END
        END;
        NEW.duration_minutes := v_dur;
    ELSE
        v_dur := NEW.duration_minutes;
    END IF;

    IF NEW.buffer_minutes IS NULL OR NEW.buffer_minutes < 0 THEN
        v_buf := CASE
            WHEN v_mode = 'Online' THEN CASE WHEN v_has_settings THEN v_settings.online_buffer_minutes ELSE 5 END
            ELSE CASE WHEN v_has_settings THEN v_settings.in_person_buffer_minutes ELSE 10 END
        END;
        NEW.buffer_minutes := v_buf;
    ELSE
        v_buf := NEW.buffer_minutes;
    END IF;

    -- Fail closed: reject any active appointment with missing/unparseable timing fields (no NULL bypass!)
    IF v_is_active THEN
        IF NEW.dentist_id IS NULL THEN
            RAISE EXCEPTION 'Active appointment requires non-null dentist_id.' USING ERRCODE = '23514';
        END IF;
        IF NEW.appointment_date IS NULL THEN
            RAISE EXCEPTION 'Active appointment requires valid appointment_date.' USING ERRCODE = '23514';
        END IF;
        IF v_start_min IS NULL OR v_start_min < 0 OR v_start_min >= 1440 THEN
            RAISE EXCEPTION 'Active appointment requires a valid clock time_slot (hh:mm AM/PM) or scheduled_start_min (0..1439). Got time_slot=%', NEW.time_slot USING ERRCODE = '23514';
        END IF;
    END IF;

    IF v_start_min IS NOT NULL THEN
        NEW.scheduled_end_min := v_start_min + v_dur;
        v_consult_end_min := NEW.scheduled_end_min;

        IF v_status = 'COMPLETED' AND NEW.actual_end_at IS NOT NULL THEN
            v_actual_end_date := (NEW.actual_end_at AT TIME ZONE 'Asia/Kolkata')::DATE;
            IF NEW.appointment_date IS NULL OR v_actual_end_date = NEW.appointment_date THEN
                v_actual_end_min :=
                    (EXTRACT(HOUR FROM (NEW.actual_end_at AT TIME ZONE 'Asia/Kolkata'))::INTEGER * 60) +
                    EXTRACT(MINUTE FROM (NEW.actual_end_at AT TIME ZONE 'Asia/Kolkata'))::INTEGER;
                IF v_actual_end_min >= v_start_min AND v_actual_end_min < NEW.scheduled_end_min THEN
                    v_consult_end_min := GREATEST(v_start_min + 1, v_actual_end_min);
                    NEW.finished_early := TRUE;
                END IF;
            END IF;
        ELSIF COALESCE(NEW.delay_minutes, 0) > 0 AND v_status IN ('IN_PROGRESS', 'DELAYED', 'CONFIRMED', 'PENDING', 'RESCHEDULED') THEN
            v_consult_end_min := NEW.scheduled_end_min + NEW.delay_minutes;
        END IF;

        NEW.effective_end_min := GREATEST(v_start_min + 1, v_consult_end_min + v_buf);

        IF NEW.appointment_date IS NOT NULL THEN
            NEW.scheduled_start_at := ((NEW.appointment_date::TIMESTAMP + make_interval(mins => v_start_min)) AT TIME ZONE 'Asia/Kolkata');
            NEW.scheduled_end_at   := ((NEW.appointment_date::TIMESTAMP + make_interval(mins => NEW.scheduled_end_min)) AT TIME ZONE 'Asia/Kolkata');
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_appointments_sync_timing_intervals ON public.appointments;
CREATE TRIGGER trg_appointments_sync_timing_intervals
    BEFORE INSERT OR UPDATE ON public.appointments
    FOR EACH ROW
    EXECUTE FUNCTION public.sync_appointment_timing_intervals();

-- Backfill any pre-existing rows (Staging currently has 0 appointments)
UPDATE public.appointments
   SET appointment_date = COALESCE(appointment_date, (date AT TIME ZONE 'Asia/Kolkata')::DATE)
 WHERE appointment_date IS NULL
    OR scheduled_start_min IS NULL
    OR effective_end_min IS NULL;

-- Unconditional active-row CHECK constraint: ZERO NULL or non-clock bypass possible
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_appointments_active_timing_not_null') THEN
        ALTER TABLE public.appointments
            ADD CONSTRAINT chk_appointments_active_timing_not_null
            CHECK (
                upper(btrim(COALESCE(status, 'PENDING'))) IN ('CANCELLED', 'CANCELED', 'REJECTED', 'NO_SHOW')
                OR (
                    dentist_id IS NOT NULL
                    AND appointment_date IS NOT NULL
                    AND consultation_type IN ('In-Person', 'Online')
                    AND capacity_lane IN ('SHARED', 'IN-PERSON', 'ONLINE')
                    AND duration_minutes IS NOT NULL AND duration_minutes > 0
                    AND buffer_minutes IS NOT NULL AND buffer_minutes >= 0
                    AND scheduled_start_min IS NOT NULL AND scheduled_start_min >= 0 AND scheduled_start_min < 1440
                    AND scheduled_end_min IS NOT NULL AND scheduled_end_min = scheduled_start_min + duration_minutes
                    AND effective_end_min IS NOT NULL AND effective_end_min > scheduled_start_min
                    AND scheduled_start_at IS NOT NULL
                    AND scheduled_end_at IS NOT NULL
                    AND scheduled_end_at > scheduled_start_at
                )
            );
    END IF;
END $$;

-- Strict GiST interval exclusion constraint across ALL active rows (zero IS NOT NULL escape hatches)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'excl_appointments_no_overlapping_intervals') THEN
        ALTER TABLE public.appointments
            ADD CONSTRAINT excl_appointments_no_overlapping_intervals
            EXCLUDE USING gist (
                dentist_id WITH =,
                appointment_date WITH =,
                capacity_lane WITH =,
                int4range(scheduled_start_min, effective_end_min, '[)') WITH &&
            )
            WHERE (
                upper(btrim(COALESCE(status, 'PENDING'))) NOT IN ('CANCELLED', 'CANCELED', 'REJECTED', 'NO_SHOW')
            );
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_appointments_dentist_appt_date_status
    ON public.appointments (dentist_id, appointment_date, status);

-- 5. TEMPORARY SLOT LOCKS
CREATE TABLE IF NOT EXISTS public.appointment_slot_locks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    dentist_id UUID NOT NULL REFERENCES public.dentists(id) ON DELETE CASCADE,
    patient_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    appointment_date DATE NOT NULL,
    start_time TEXT NOT NULL,
    end_time TEXT NOT NULL,
    start_min INTEGER NOT NULL CHECK (start_min >= 0 AND start_min < 1440),
    end_min INTEGER NOT NULL CHECK (end_min > start_min),
    consultation_type TEXT NOT NULL DEFAULT 'In-Person' CHECK (consultation_type IN ('In-Person', 'Online')),
    released_slot_id UUID REFERENCES public.released_slots(id) ON DELETE SET NULL,
    status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'CONFIRMED', 'RELEASED', 'EXPIRED')),
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_slot_locks_dentist_date_active
    ON public.appointment_slot_locks (dentist_id, appointment_date, expires_at)
    WHERE status = 'ACTIVE';

-- 6. PATIENT-DOCTOR PREFERENCES & DUPLICATE-NOTIFICATION AUDIT LOG
CREATE TABLE IF NOT EXISTS public.patient_doctor_preferences (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    patient_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    dentist_id UUID NOT NULL REFERENCES public.dentists(id) ON DELETE CASCADE,
    is_favorite BOOLEAN NOT NULL DEFAULT FALSE,
    notify_earlier_slots BOOLEAN NOT NULL DEFAULT FALSE,
    preferred_consultation_type TEXT NOT NULL DEFAULT 'Any'
        CHECK (preferred_consultation_type IN ('Any', 'Online', 'In-Person')),
    preferred_date DATE,
    earliest_time_min INTEGER,
    latest_time_min INTEGER,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (patient_id, dentist_id)
);

CREATE INDEX IF NOT EXISTS idx_patient_doctor_prefs_notify
    ON public.patient_doctor_preferences (dentist_id, notify_earlier_slots)
    WHERE notify_earlier_slots = TRUE;

CREATE TABLE IF NOT EXISTS public.slot_notification_deliveries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    released_slot_id UUID NOT NULL REFERENCES public.released_slots(id) ON DELETE CASCADE,
    patient_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    delivery_status TEXT NOT NULL DEFAULT 'PENDING'
        CHECK (delivery_status IN ('PENDING', 'SENT', 'FAILED', 'SKIPPED')),
    fcm_message_id TEXT,
    error_message TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (released_slot_id, patient_id)
);

ALTER TABLE public.notifications
    ADD COLUMN IF NOT EXISTS data JSONB NOT NULL DEFAULT '{}'::jsonb;

-- 7. ATOMIC RPC 1: ACQUIRE TEMPORARY SLOT LOCK
CREATE OR REPLACE FUNCTION public.acquire_appointment_slot_lock(
    p_dentist_id UUID,
    p_patient_id UUID,
    p_date DATE,
    p_start_time TEXT,
    p_end_time TEXT,
    p_start_min INTEGER,
    p_end_min INTEGER,
    p_consultation_type TEXT DEFAULT 'In-Person',
    p_released_slot_id UUID DEFAULT NULL,
    p_ttl_seconds INTEGER DEFAULT 300
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_settings      public.doctor_scheduling_settings%ROWTYPE;
    v_lane          TEXT := 'SHARED';
    v_mode          TEXT := CASE WHEN lower(COALESCE(p_consultation_type, '')) ~ '(online|video|teleconsult|virtual)' THEN 'Online' ELSE 'In-Person' END;
    v_rel           public.released_slots%ROWTYPE;
    v_conflict_rel  UUID;
    v_conflict_appt UUID;
    v_conflict_lock UUID;
    v_lock_row      public.appointment_slot_locks%ROWTYPE;
    v_active_count  INTEGER := 0;
BEGIN
    IF p_dentist_id IS NULL OR p_patient_id IS NULL OR p_date IS NULL
       OR p_start_min IS NULL OR p_end_min IS NULL
       OR p_start_min < 0 OR p_start_min >= 1440 OR p_end_min <= p_start_min
       OR public.parse_clock_slot_minutes(p_start_time) IS DISTINCT FROM p_start_min THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'INVALID_INTERVAL', 'message', 'Invalid appointment slot parameters.');
    END IF;

    PERFORM pg_advisory_xact_lock(hashtext(p_dentist_id::text || ':' || p_date::text));

    -- Step A: Expire stale locks and restore orphaned LOCKED released_slots
    WITH expired_locks AS (
        UPDATE public.appointment_slot_locks
           SET status = 'EXPIRED'
         WHERE dentist_id = p_dentist_id
           AND appointment_date = p_date
           AND status = 'ACTIVE'
           AND expires_at <= NOW()
         RETURNING released_slot_id
    )
    UPDATE public.released_slots rs
       SET status = CASE WHEN rs.expires_at > NOW() THEN 'AVAILABLE' ELSE 'EXPIRED' END
      FROM expired_locks el
     WHERE rs.id = el.released_slot_id AND rs.status = 'LOCKED';

    UPDATE public.released_slots
       SET status = 'EXPIRED'
     WHERE dentist_id = p_dentist_id
       AND appointment_date = p_date
       AND status = 'AVAILABLE'
       AND expires_at <= NOW();

    -- Step B: Load settings for lane & daily limit
    SELECT * INTO v_settings FROM public.doctor_scheduling_settings WHERE dentist_id = p_dentist_id LIMIT 1;
    IF FOUND THEN
        IF v_settings.allow_simultaneous_online_and_in_person THEN
            v_lane := upper(v_mode);
        END IF;
        IF v_settings.max_appointments_per_day IS NOT NULL THEN
            SELECT COUNT(*) INTO v_active_count
              FROM public.appointments
             WHERE dentist_id = p_dentist_id
               AND appointment_date = p_date
               AND upper(btrim(COALESCE(status, 'PENDING'))) NOT IN ('CANCELLED', 'CANCELED', 'REJECTED', 'NO_SHOW');
            IF v_active_count >= v_settings.max_appointments_per_day THEN
                RETURN jsonb_build_object('success', FALSE, 'reason', 'DAILY_LIMIT_REACHED', 'message', 'Maximum appointments for this date have been reached.');
            END IF;
        END IF;
    END IF;

    -- Step C: Validate released_slot ownership OR prevent regular lock from hijacking an active released slot
    IF p_released_slot_id IS NOT NULL THEN
        SELECT * INTO v_rel FROM public.released_slots WHERE id = p_released_slot_id FOR UPDATE;
        IF NOT FOUND
           OR v_rel.dentist_id <> p_dentist_id
           OR v_rel.appointment_date <> p_date
           OR v_rel.consultation_type <> v_mode
           OR v_rel.start_min <> p_start_min
           OR (v_rel.start_min + v_rel.duration_minutes + v_rel.buffer_minutes) <> p_end_min
           OR v_rel.status <> 'AVAILABLE'
           OR v_rel.expires_at <= NOW() THEN
            RETURN jsonb_build_object('success', FALSE, 'reason', 'RELEASED_SLOT_UNAVAILABLE', 'message', 'This slot is no longer available. Please select another time.');
        END IF;
    ELSE
        SELECT id INTO v_conflict_rel
          FROM public.released_slots
         WHERE dentist_id = p_dentist_id
           AND appointment_date = p_date
           AND status IN ('AVAILABLE', 'LOCKED')
           AND expires_at > NOW()
           AND (v_lane = 'SHARED' OR upper(consultation_type) = v_lane)
           AND start_min < p_end_min
           AND (start_min + duration_minutes + buffer_minutes) > p_start_min
         LIMIT 1;
        IF v_conflict_rel IS NOT NULL THEN
            RETURN jsonb_build_object(
                'success', FALSE,
                'reason', 'RELEASED_SLOT_LOCK_REQUIRED',
                'message', 'This released slot must be locked using its released slot ID.'
            );
        END IF;
    END IF;

    -- Step D: Validate no overlapping active appointment
    SELECT id INTO v_conflict_appt
      FROM public.appointments
     WHERE dentist_id = p_dentist_id
       AND appointment_date = p_date
       AND upper(btrim(COALESCE(status, 'PENDING'))) NOT IN ('CANCELLED', 'CANCELED', 'REJECTED', 'NO_SHOW')
       AND capacity_lane = v_lane
       AND scheduled_start_min < p_end_min
       AND effective_end_min > p_start_min
     LIMIT 1;
    IF v_conflict_appt IS NOT NULL THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'APPOINTMENT_CONFLICT', 'message', 'This slot is no longer available. Please select another time.');
    END IF;

    -- Step E: Validate no overlapping active lock held by another patient
    SELECT id INTO v_conflict_lock
      FROM public.appointment_slot_locks
     WHERE dentist_id = p_dentist_id
       AND appointment_date = p_date
       AND status = 'ACTIVE'
       AND expires_at > NOW()
       AND patient_id <> p_patient_id
       AND (v_lane = 'SHARED' OR upper(consultation_type) = v_lane)
       AND start_min < p_end_min
       AND end_min > p_start_min
     LIMIT 1;
    IF v_conflict_lock IS NOT NULL THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'SLOT_LOCKED', 'message', 'This slot is no longer available. Please select another time.');
    END IF;

    -- Step F: All validations passed -> safely release caller's previous active lock
    WITH prev_locks AS (
        UPDATE public.appointment_slot_locks
           SET status = 'RELEASED'
         WHERE dentist_id = p_dentist_id
           AND patient_id = p_patient_id
           AND appointment_date = p_date
           AND status = 'ACTIVE'
         RETURNING released_slot_id
    )
    UPDATE public.released_slots rs
       SET status = CASE WHEN rs.expires_at > NOW() THEN 'AVAILABLE' ELSE 'EXPIRED' END
      FROM prev_locks pl
     WHERE rs.id = pl.released_slot_id
       AND rs.status = 'LOCKED'
       AND rs.id IS DISTINCT FROM p_released_slot_id;

    INSERT INTO public.appointment_slot_locks (
        dentist_id, patient_id, appointment_date, start_time, end_time,
        start_min, end_min, consultation_type, released_slot_id,
        status, expires_at
    ) VALUES (
        p_dentist_id, p_patient_id, p_date, btrim(p_start_time), btrim(p_end_time),
        p_start_min, p_end_min, v_mode, p_released_slot_id,
        'ACTIVE', NOW() + make_interval(secs => GREATEST(30, LEAST(900, COALESCE(p_ttl_seconds, 300))))
    ) RETURNING * INTO v_lock_row;

    IF p_released_slot_id IS NOT NULL THEN
        UPDATE public.released_slots SET status = 'LOCKED' WHERE id = p_released_slot_id;
    END IF;

    RETURN jsonb_build_object('success', TRUE, 'lockId', v_lock_row.id, 'expiresAt', v_lock_row.expires_at);
END;
$$;

-- 8. ATOMIC RPC 2: RELEASE TEMPORARY SLOT LOCK
CREATE OR REPLACE FUNCTION public.release_appointment_slot_lock(
    p_lock_id UUID,
    p_patient_id UUID
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_lock public.appointment_slot_locks%ROWTYPE;
BEGIN
    SELECT * INTO v_lock FROM public.appointment_slot_locks WHERE id = p_lock_id FOR UPDATE;
    IF NOT FOUND THEN RETURN jsonb_build_object('success', FALSE, 'reason', 'NOT_FOUND'); END IF;
    IF v_lock.patient_id <> p_patient_id THEN RETURN jsonb_build_object('success', FALSE, 'reason', 'FORBIDDEN'); END IF;
    IF v_lock.status <> 'ACTIVE' THEN RETURN jsonb_build_object('success', TRUE, 'status', v_lock.status); END IF;

    PERFORM pg_advisory_xact_lock(hashtext(v_lock.dentist_id::text || ':' || v_lock.appointment_date::text));

    UPDATE public.appointment_slot_locks SET status = 'RELEASED' WHERE id = p_lock_id;
    IF v_lock.released_slot_id IS NOT NULL THEN
        UPDATE public.released_slots
           SET status = CASE WHEN expires_at > NOW() THEN 'AVAILABLE' ELSE 'EXPIRED' END
         WHERE id = v_lock.released_slot_id AND status = 'LOCKED';
    END IF;
    RETURN jsonb_build_object('success', TRUE, 'status', 'RELEASED');
END;
$$;

-- 9. ATOMIC RPC 3: CONFIRM APPOINTMENT BOOKING (MANDATORY p_lock_id + STRICT RELEASED-SLOT LOCK OWNERSHIP)
DROP FUNCTION IF EXISTS public.confirm_appointment_booking(
    UUID, UUID, UUID, DATE, TEXT, INTEGER, INTEGER, INTEGER, TEXT, TEXT, TEXT, TEXT, UUID, UUID
);

CREATE OR REPLACE FUNCTION public.confirm_appointment_booking(
    p_patient_id UUID,
    p_dentist_id UUID,
    p_clinic_id UUID,
    p_date DATE,
    p_time_slot TEXT,
    p_start_min INTEGER,
    p_duration_minutes INTEGER,
    p_buffer_minutes INTEGER,
    p_consultation_type TEXT,
    p_treatment TEXT,
    p_status TEXT,
    p_qr_code_string TEXT,
    p_lock_id UUID,                       -- MANDATORY: NO DEFAULT ALLOWED
    p_released_slot_id UUID DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_settings          public.doctor_scheduling_settings%ROWTYPE;
    v_mode              TEXT := CASE WHEN lower(COALESCE(p_consultation_type, '')) ~ '(online|video|teleconsult|virtual)' THEN 'Online' ELSE 'In-Person' END;
    v_lane              TEXT := 'SHARED';
    v_buf               INTEGER := GREATEST(0, COALESCE(p_buffer_minutes, 0));
    v_consult_end_min   INTEGER := p_start_min + p_duration_minutes;
    v_occupied_end_min  INTEGER := p_start_min + p_duration_minutes + v_buf;
    v_lock              public.appointment_slot_locks%ROWTYPE;
    v_rel               public.released_slots%ROWTYPE;
    v_conflict_rel      UUID;
    v_conflict_lock     UUID;
    v_patient_conflict  UUID;
    v_active_count      INTEGER := 0;
    v_appt              public.appointments%ROWTYPE;
    v_legacy_date_ts    TIMESTAMPTZ := ((p_date::TEXT || ' 00:00:00+00')::TIMESTAMPTZ);
BEGIN
    -- 0a. MANDATORY LOCK CHECK: Reject NULL p_lock_id unconditionally
    IF p_lock_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'reason', 'LOCK_REQUIRED',
            'message', 'An active slot lock is required to confirm this booking.'
        );
    END IF;

    -- 0b. Parameter integrity check
    IF p_patient_id IS NULL OR p_dentist_id IS NULL OR p_date IS NULL
       OR p_start_min IS NULL OR p_duration_minutes IS NULL OR p_duration_minutes <= 0
       OR public.parse_clock_slot_minutes(p_time_slot) IS DISTINCT FROM p_start_min THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'INVALID_PARAMETERS', 'message', 'Invalid booking parameters.');
    END IF;

    PERFORM pg_advisory_xact_lock(hashtext(p_dentist_id::text || ':' || p_date::text));

    -- 1. Expire stale locks and restore orphaned LOCKED released_slots
    WITH expired_locks AS (
        UPDATE public.appointment_slot_locks
           SET status = 'EXPIRED'
         WHERE dentist_id = p_dentist_id
           AND appointment_date = p_date
           AND status = 'ACTIVE'
           AND expires_at <= NOW()
         RETURNING released_slot_id
    )
    UPDATE public.released_slots rs
       SET status = CASE WHEN rs.expires_at > NOW() THEN 'AVAILABLE' ELSE 'EXPIRED' END
      FROM expired_locks el
     WHERE rs.id = el.released_slot_id AND rs.status = 'LOCKED';

    UPDATE public.released_slots
       SET status = 'EXPIRED'
     WHERE dentist_id = p_dentist_id
       AND appointment_date = p_date
       AND status = 'AVAILABLE'
       AND expires_at <= NOW();

    -- 2. UNCONDITIONAL EXACT LOCK MATCH VALIDATION
    SELECT * INTO v_lock
      FROM public.appointment_slot_locks
     WHERE id = p_lock_id
       FOR UPDATE;

    IF NOT FOUND
       OR v_lock.patient_id <> p_patient_id
       OR v_lock.dentist_id <> p_dentist_id
       OR v_lock.appointment_date <> p_date
       OR v_lock.start_min <> p_start_min
       OR v_lock.end_min <> v_occupied_end_min
       OR lower(btrim(v_lock.start_time)) <> lower(btrim(COALESCE(p_time_slot, '')))
       OR v_lock.consultation_type <> v_mode
       OR v_lock.released_slot_id IS DISTINCT FROM p_released_slot_id
       OR v_lock.status <> 'ACTIVE'
       OR v_lock.expires_at <= NOW() THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'reason', 'LOCK_MISMATCH_OR_EXPIRED',
            'message', 'This slot is no longer available. Please select another time.'
        );
    END IF;

    -- 3. Check lane & daily appointment limit
    SELECT * INTO v_settings FROM public.doctor_scheduling_settings WHERE dentist_id = p_dentist_id LIMIT 1;
    IF FOUND THEN
        IF v_settings.allow_simultaneous_online_and_in_person THEN
            v_lane := upper(v_mode);
        END IF;
        IF v_settings.max_appointments_per_day IS NOT NULL THEN
            SELECT COUNT(*) INTO v_active_count
              FROM public.appointments
             WHERE dentist_id = p_dentist_id
               AND appointment_date = p_date
               AND upper(btrim(COALESCE(status, 'PENDING'))) NOT IN ('CANCELLED', 'CANCELED', 'REJECTED', 'NO_SHOW');
            IF v_active_count >= v_settings.max_appointments_per_day THEN
                RETURN jsonb_build_object('success', FALSE, 'reason', 'DAILY_LIMIT_REACHED', 'message', 'Maximum appointments for this date have been reached.');
            END IF;
        END IF;
    END IF;

    -- 4. STRICT RELEASED-SLOT OWNERSHIP VALIDATION
    IF p_released_slot_id IS NOT NULL THEN
        SELECT * INTO v_rel
          FROM public.released_slots
         WHERE id = p_released_slot_id
           FOR UPDATE;

        IF NOT FOUND
           OR v_rel.dentist_id <> p_dentist_id
           OR v_rel.appointment_date <> p_date
           OR v_rel.consultation_type <> v_mode
           OR v_rel.start_min <> p_start_min
           OR v_rel.duration_minutes <> p_duration_minutes
           OR (v_rel.start_min + v_rel.duration_minutes + v_rel.buffer_minutes) <> v_occupied_end_min
           OR v_rel.expires_at <= NOW()
           OR v_rel.status <> 'LOCKED'
           OR v_lock.released_slot_id IS DISTINCT FROM p_released_slot_id THEN
            RETURN jsonb_build_object(
                'success', FALSE,
                'reason', 'RELEASED_SLOT_LOCK_MISMATCH',
                'message', 'This slot is no longer available. Please select another time.'
            );
        END IF;
    ELSE
        SELECT id INTO v_conflict_rel
          FROM public.released_slots
         WHERE dentist_id = p_dentist_id
           AND appointment_date = p_date
           AND status IN ('AVAILABLE', 'LOCKED')
           AND expires_at > NOW()
           AND (v_lane = 'SHARED' OR upper(consultation_type) = v_lane)
           AND start_min < v_occupied_end_min
           AND (start_min + duration_minutes + buffer_minutes) > p_start_min
         LIMIT 1;
        IF v_conflict_rel IS NOT NULL THEN
            RETURN jsonb_build_object(
                'success', FALSE,
                'reason', 'RELEASED_SLOT_LOCK_REQUIRED',
                'message', 'This released slot must be booked via its active released-slot lock.'
            );
        END IF;
    END IF;

    -- 5. Verify no other patient holds an overlapping active lock
    SELECT id INTO v_conflict_lock
      FROM public.appointment_slot_locks
     WHERE dentist_id = p_dentist_id
       AND appointment_date = p_date
       AND status = 'ACTIVE'
       AND expires_at > NOW()
       AND patient_id <> p_patient_id
       AND (v_lane = 'SHARED' OR upper(consultation_type) = v_lane)
       AND start_min < v_occupied_end_min
       AND end_min > p_start_min
     LIMIT 1;
    IF v_conflict_lock IS NOT NULL THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'SLOT_LOCKED', 'message', 'This slot is no longer available. Please select another time.');
    END IF;

    -- 6. Prevent same patient double-booking overlapping consultations
    SELECT id INTO v_patient_conflict
      FROM public.appointments
     WHERE patient_id = p_patient_id
       AND appointment_date = p_date
       AND upper(btrim(COALESCE(status, 'PENDING'))) NOT IN ('CANCELLED', 'CANCELED', 'REJECTED', 'NO_SHOW')
       AND scheduled_start_min < v_consult_end_min
       AND scheduled_end_min > p_start_min
     LIMIT 1;
    IF v_patient_conflict IS NOT NULL THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'PATIENT_CONFLICT', 'message', 'You already have an appointment booked during this time. Please select another time.');
    END IF;

    -- 7. Atomic appointment insert (strict trigger + GiST exclusion constraint guarantee zero overlap)
    BEGIN
        INSERT INTO public.appointments (
            patient_id, dentist_id, clinic_id, date, appointment_date,
            time_slot, treatment, status, qr_code_string,
            consultation_type, duration_minutes, buffer_minutes,
            scheduled_start_min, released_slot_id
        ) VALUES (
            p_patient_id, p_dentist_id, p_clinic_id, v_legacy_date_ts, p_date,
            btrim(p_time_slot), p_treatment, COALESCE(NULLIF(btrim(p_status), ''), 'PENDING'), p_qr_code_string,
            v_mode, p_duration_minutes, v_buf,
            p_start_min, p_released_slot_id
        ) RETURNING * INTO v_appt;
    EXCEPTION WHEN exclusion_violation THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'APPOINTMENT_CONFLICT', 'message', 'This slot is no longer available. Please select another time.');
    END;

    -- 8. Atomically mark caller's mandatory lock CONFIRMED and owned released_slot BOOKED
    UPDATE public.appointment_slot_locks
       SET status = 'CONFIRMED'
     WHERE id = p_lock_id
       AND status = 'ACTIVE';

    IF p_released_slot_id IS NOT NULL THEN
        UPDATE public.released_slots
           SET status = 'BOOKED',
               claimed_by_appointment_id = v_appt.id
         WHERE id = p_released_slot_id
           AND status = 'LOCKED';
    END IF;

    RETURN jsonb_build_object('success', TRUE, 'appointment', to_jsonb(v_appt));
END;
$$;

-- 10. GS HEALTH CUSTOM OTP/JWT-COMPATIBLE RLS POLICIES & RPC PERMISSIONS
ALTER TABLE public.doctor_scheduling_settings   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.released_slots               ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.appointment_slot_locks       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.patient_doctor_preferences   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.slot_notification_deliveries ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS p2_sched_settings_service_all ON public.doctor_scheduling_settings;
CREATE POLICY p2_sched_settings_service_all ON public.doctor_scheduling_settings FOR ALL TO service_role USING (TRUE) WITH CHECK (TRUE);
DROP POLICY IF EXISTS p2_sched_settings_auth_select ON public.doctor_scheduling_settings;
CREATE POLICY p2_sched_settings_auth_select ON public.doctor_scheduling_settings FOR SELECT TO authenticated
    USING (public.gs_health_active_user_id() IS NOT NULL);

DROP POLICY IF EXISTS p2_released_slots_service_all ON public.released_slots;
CREATE POLICY p2_released_slots_service_all ON public.released_slots FOR ALL TO service_role USING (TRUE) WITH CHECK (TRUE);
DROP POLICY IF EXISTS p2_released_slots_auth_select ON public.released_slots;
CREATE POLICY p2_released_slots_auth_select ON public.released_slots FOR SELECT TO authenticated
    USING (
        (public.gs_health_active_user_id() IS NOT NULL AND status = 'AVAILABLE' AND expires_at > NOW())
        OR dentist_id = public.gs_health_active_dentist_id()
    );

DROP POLICY IF EXISTS p2_slot_locks_service_all ON public.appointment_slot_locks;
CREATE POLICY p2_slot_locks_service_all ON public.appointment_slot_locks FOR ALL TO service_role USING (TRUE) WITH CHECK (TRUE);
DROP POLICY IF EXISTS p2_slot_locks_own_select ON public.appointment_slot_locks;
CREATE POLICY p2_slot_locks_own_select ON public.appointment_slot_locks FOR SELECT TO authenticated
    USING (
        patient_id = public.gs_health_active_user_id()
        OR dentist_id = public.gs_health_active_dentist_id()
    );

DROP POLICY IF EXISTS p2_pat_prefs_service_all ON public.patient_doctor_preferences;
CREATE POLICY p2_pat_prefs_service_all ON public.patient_doctor_preferences FOR ALL TO service_role USING (TRUE) WITH CHECK (TRUE);
DROP POLICY IF EXISTS p2_pat_prefs_own_all ON public.patient_doctor_preferences;
CREATE POLICY p2_pat_prefs_own_all ON public.patient_doctor_preferences FOR ALL TO authenticated
    USING (patient_id = public.gs_health_active_user_id())
    WITH CHECK (patient_id = public.gs_health_active_user_id());

DROP POLICY IF EXISTS p2_notif_deliveries_service_all ON public.slot_notification_deliveries;
CREATE POLICY p2_notif_deliveries_service_all ON public.slot_notification_deliveries FOR ALL TO service_role USING (TRUE) WITH CHECK (TRUE);

REVOKE ALL ON FUNCTION public.acquire_appointment_slot_lock(UUID, UUID, DATE, TEXT, TEXT, INTEGER, INTEGER, TEXT, UUID, INTEGER) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.acquire_appointment_slot_lock(UUID, UUID, DATE, TEXT, TEXT, INTEGER, INTEGER, TEXT, UUID, INTEGER) TO service_role;

REVOKE ALL ON FUNCTION public.release_appointment_slot_lock(UUID, UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.release_appointment_slot_lock(UUID, UUID) TO service_role;

REVOKE ALL ON FUNCTION public.confirm_appointment_booking(UUID, UUID, UUID, DATE, TEXT, INTEGER, INTEGER, INTEGER, TEXT, TEXT, TEXT, TEXT, UUID, UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.confirm_appointment_booking(UUID, UUID, UUID, DATE, TEXT, INTEGER, INTEGER, INTEGER, TEXT, TEXT, TEXT, TEXT, UUID, UUID) TO service_role;

-- 11. REALTIME PUBLICATION (Non-PII availability tables only)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
        BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.doctor_availability; EXCEPTION WHEN duplicate_object THEN NULL; END;
        BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.doctor_scheduling_settings; EXCEPTION WHEN duplicate_object THEN NULL; END;
        BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.released_slots; EXCEPTION WHEN duplicate_object THEN NULL; END;
    END IF;
END $$;

COMMIT;
