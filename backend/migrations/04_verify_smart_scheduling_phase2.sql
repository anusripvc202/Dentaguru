-- =============================================================================
-- GS HEALTH MIGRATION 04 VERIFICATION & LOCK-BYPASS TEST SUITE
-- Target Environment: STAGING ONLY (ojinzcdldwugpnxrnjcq)
-- Runs inside BEGIN ... ROLLBACK so zero test records persist on Staging.
-- =============================================================================

-- Part A: Read-Only Preflight Checks (run before applying Migration 04)
-- SELECT name, default_version, installed_version FROM pg_available_extensions WHERE name = 'btree_gist';
-- SELECT tablename, policyname, roles, cmd FROM pg_policies WHERE schemaname = 'public' AND tablename IN ('appointments','doctor_availability','notifications','users','dentists');

-- Part B: Post-Migration Transactional Verification (7 Lock & Released-Slot Cases)
BEGIN;

DO $$
DECLARE
    v_p1             UUID;
    v_p2             UUID;
    v_doc_user       UUID;
    v_dentist        UUID;
    v_date           DATE := CURRENT_DATE + 7;
    v_rel_id         UUID;
    v_res            JSONB;
    v_lock_id        UUID;
    v_tampered_lock  UUID;
    v_rel_lock_id    UUID;
    v_appt_id        UUID;
    v_rel_status     TEXT;
    v_lock_status    TEXT;
    v_omitted_failed BOOLEAN := FALSE;
BEGIN
    INSERT INTO public.users (name, email, password, phone, role, status)
    VALUES ('M04 Test Patient 1', 'm04_p1_' || gen_random_uuid() || '@test.local', 'x', '9000011101', 'Patient', 'ACTIVE')
    RETURNING id INTO v_p1;

    INSERT INTO public.users (name, email, password, phone, role, status)
    VALUES ('M04 Test Patient 2', 'm04_p2_' || gen_random_uuid() || '@test.local', 'x', '9000011102', 'Patient', 'ACTIVE')
    RETURNING id INTO v_p2;

    INSERT INTO public.users (name, email, password, phone, role, status)
    VALUES ('M04 Test Doctor', 'm04_doc_' || gen_random_uuid() || '@test.local', 'x', '9000011103', 'DOCTOR', 'ACTIVE')
    RETURNING id INTO v_doc_user;

    INSERT INTO public.dentists (user_id, speciality, license_number)
    VALUES (v_doc_user, 'General Medicine', 'M04-LIC-' || gen_random_uuid())
    RETURNING id INTO v_dentist;

    INSERT INTO public.released_slots (
        dentist_id, appointment_date, start_time, end_time,
        start_min, end_min, duration_minutes, buffer_minutes,
        consultation_type, status, expires_at
    ) VALUES (
        v_dentist, v_date, '10:00 AM', '10:20 AM',
        600, 620, 20, 5,
        'Online', 'AVAILABLE', NOW() + interval '1 hour'
    ) RETURNING id INTO v_rel_id;

    -- T1: Omitting p_lock_id (12 args) MUST fail at PostgreSQL signature resolution
    BEGIN
        EXECUTE 'SELECT public.confirm_appointment_booking($1,$2,NULL,$3,$4,$5,$6,$7,$8,$9,$10,$11)'
          USING v_p1, v_dentist, v_date, '11:00 AM', 660, 30, 10, 'In-Person', 'Checkup', 'PENDING', 'QR-T1';
    EXCEPTION WHEN undefined_function THEN
        v_omitted_failed := TRUE;
    END;
    IF NOT v_omitted_failed THEN
        RAISE EXCEPTION 'T1 FAILED: 12-argument call omitting p_lock_id was not rejected';
    END IF;

    -- T2: Explicit p_lock_id => NULL MUST be rejected with LOCK_REQUIRED
    v_res := public.confirm_appointment_booking(
        v_p1, v_dentist, NULL, v_date, '11:00 AM', 660, 30, 10,
        'In-Person', 'Checkup', 'PENDING', 'QR-T2', NULL, NULL
    );
    IF (v_res ->> 'success')::BOOLEAN IS DISTINCT FROM FALSE OR (v_res ->> 'reason') <> 'LOCK_REQUIRED' THEN
        RAISE EXCEPTION 'T2 FAILED: expected LOCK_REQUIRED, got %', v_res;
    END IF;

    -- T3a: Non-existent p_lock_id MUST be rejected
    v_res := public.confirm_appointment_booking(
        v_p1, v_dentist, NULL, v_date, '11:00 AM', 660, 30, 10,
        'In-Person', 'Checkup', 'PENDING', 'QR-T3A', gen_random_uuid(), NULL
    );
    IF (v_res ->> 'success')::BOOLEAN IS DISTINCT FROM FALSE OR (v_res ->> 'reason') <> 'LOCK_MISMATCH_OR_EXPIRED' THEN
        RAISE EXCEPTION 'T3a FAILED: expected LOCK_MISMATCH_OR_EXPIRED, got %', v_res;
    END IF;

    -- T3b: Expired lock MUST be rejected
    v_res := public.acquire_appointment_slot_lock(
        v_dentist, v_p1, v_date, '11:00 AM', '11:40 AM', 660, 700, 'In-Person', NULL, 300
    );
    v_lock_id := (v_res ->> 'lockId')::UUID;
    UPDATE public.appointment_slot_locks SET expires_at = NOW() - interval '1 second' WHERE id = v_lock_id;
    v_res := public.confirm_appointment_booking(
        v_p1, v_dentist, NULL, v_date, '11:00 AM', 660, 30, 10,
        'In-Person', 'Checkup', 'PENDING', 'QR-T3B', v_lock_id, NULL
    );
    IF (v_res ->> 'success')::BOOLEAN IS DISTINCT FROM FALSE OR (v_res ->> 'reason') <> 'LOCK_MISMATCH_OR_EXPIRED' THEN
        RAISE EXCEPTION 'T3b FAILED: expired lock should return LOCK_MISMATCH_OR_EXPIRED, got %', v_res;
    END IF;

    -- T3c: Mismatched patient / mode MUST be rejected without altering valid lock
    v_res := public.acquire_appointment_slot_lock(
        v_dentist, v_p1, v_date, '11:00 AM', '11:40 AM', 660, 700, 'In-Person', NULL, 300
    );
    v_lock_id := (v_res ->> 'lockId')::UUID;
    v_res := public.confirm_appointment_booking(
        v_p2, v_dentist, NULL, v_date, '11:00 AM', 660, 30, 10,
        'In-Person', 'Checkup', 'PENDING', 'QR-T3C-PAT', v_lock_id, NULL
    );
    IF (v_res ->> 'success')::BOOLEAN IS DISTINCT FROM FALSE OR (v_res ->> 'reason') <> 'LOCK_MISMATCH_OR_EXPIRED' THEN
        RAISE EXCEPTION 'T3c-patient FAILED: got %', v_res;
    END IF;
    v_res := public.confirm_appointment_booking(
        v_p1, v_dentist, NULL, v_date, '11:00 AM', 660, 30, 10,
        'Online', 'Checkup', 'PENDING', 'QR-T3C-MODE', v_lock_id, NULL
    );
    IF (v_res ->> 'success')::BOOLEAN IS DISTINCT FROM FALSE OR (v_res ->> 'reason') <> 'LOCK_MISMATCH_OR_EXPIRED' THEN
        RAISE EXCEPTION 'T3c-mode FAILED: got %', v_res;
    END IF;

    -- T4: Direct booking of AVAILABLE released slot with p_lock_id => NULL MUST fail & preserve AVAILABLE
    v_res := public.confirm_appointment_booking(
        v_p2, v_dentist, NULL, v_date, '10:00 AM', 600, 20, 5,
        'Online', 'Early Online Consult', 'PENDING', 'QR-T4', NULL, v_rel_id
    );
    SELECT status INTO v_rel_status FROM public.released_slots WHERE id = v_rel_id;
    IF (v_res ->> 'success')::BOOLEAN IS DISTINCT FROM FALSE
       OR (v_res ->> 'reason') <> 'LOCK_REQUIRED'
       OR v_rel_status <> 'AVAILABLE' THEN
        RAISE EXCEPTION 'T4 FAILED: res=%, rel_status=%', v_res, v_rel_status;
    END IF;

    -- T5a: Booking AVAILABLE released slot using a regular lock MUST fail
    v_res := public.confirm_appointment_booking(
        v_p1, v_dentist, NULL, v_date, '10:00 AM', 600, 20, 5,
        'Online', 'Early Online Consult', 'PENDING', 'QR-T5A', v_lock_id, v_rel_id
    );
    IF (v_res ->> 'success')::BOOLEAN IS DISTINCT FROM FALSE OR (v_res ->> 'reason') <> 'LOCK_MISMATCH_OR_EXPIRED' THEN
        RAISE EXCEPTION 'T5a FAILED: got %', v_res;
    END IF;

    -- T5b: Acquiring a regular lock overlapping an AVAILABLE released slot MUST fail
    v_res := public.acquire_appointment_slot_lock(
        v_dentist, v_p2, v_date, '10:00 AM', '10:25 AM', 600, 625, 'Online', NULL, 300
    );
    IF (v_res ->> 'success')::BOOLEAN IS DISTINCT FROM FALSE OR (v_res ->> 'reason') <> 'RELEASED_SLOT_LOCK_REQUIRED' THEN
        RAISE EXCEPTION 'T5b FAILED: expected RELEASED_SLOT_LOCK_REQUIRED, got %', v_res;
    END IF;

    -- T5c: Tampered lock pointing to released_slot while still AVAILABLE MUST fail
    INSERT INTO public.appointment_slot_locks (
        dentist_id, patient_id, appointment_date, start_time, end_time,
        start_min, end_min, consultation_type, released_slot_id, status, expires_at
    ) VALUES (
        v_dentist, v_p2, v_date, '10:00 AM', '10:25 AM',
        600, 625, 'Online', v_rel_id, 'ACTIVE', NOW() + interval '5 minutes'
    ) RETURNING id INTO v_tampered_lock;

    v_res := public.confirm_appointment_booking(
        v_p2, v_dentist, NULL, v_date, '10:00 AM', 600, 20, 5,
        'Online', 'Early Online Consult', 'PENDING', 'QR-T5C', v_tampered_lock, v_rel_id
    );
    IF (v_res ->> 'success')::BOOLEAN IS DISTINCT FROM FALSE OR (v_res ->> 'reason') <> 'RELEASED_SLOT_LOCK_MISMATCH' THEN
        RAISE EXCEPTION 'T5c FAILED: expected RELEASED_SLOT_LOCK_MISMATCH, got %', v_res;
    END IF;
    UPDATE public.appointment_slot_locks SET status = 'RELEASED' WHERE id = v_tampered_lock;

    -- T6: Valid regular locked booking MUST succeed
    v_res := public.confirm_appointment_booking(
        v_p1, v_dentist, NULL, v_date, '11:00 AM', 660, 30, 10,
        'In-Person', 'Checkup', 'PENDING', 'QR-T6', v_lock_id, NULL
    );
    SELECT status INTO v_lock_status FROM public.appointment_slot_locks WHERE id = v_lock_id;
    IF (v_res ->> 'success')::BOOLEAN IS DISTINCT FROM TRUE OR v_lock_status <> 'CONFIRMED' THEN
        RAISE EXCEPTION 'T6 FAILED: res=%, lock_status=%', v_res, v_lock_status;
    END IF;

    -- T7: Valid released-slot lock -> confirm MUST succeed
    v_res := public.acquire_appointment_slot_lock(
        v_dentist, v_p2, v_date, '10:00 AM', '10:25 AM', 600, 625, 'Online', v_rel_id, 300
    );
    v_rel_lock_id := (v_res ->> 'lockId')::UUID;
    SELECT status INTO v_rel_status FROM public.released_slots WHERE id = v_rel_id;
    IF (v_res ->> 'success')::BOOLEAN IS DISTINCT FROM TRUE OR v_rel_status <> 'LOCKED' THEN
        RAISE EXCEPTION 'T7-lock FAILED: res=%, rel_status=%', v_res, v_rel_status;
    END IF;

    v_res := public.confirm_appointment_booking(
        v_p2, v_dentist, NULL, v_date, '10:00 AM', 600, 20, 5,
        'Online', 'Early Online Consult', 'PENDING', 'QR-T7', v_rel_lock_id, v_rel_id
    );
    v_appt_id := ((v_res -> 'appointment') ->> 'id')::UUID;
    SELECT status INTO v_lock_status FROM public.appointment_slot_locks WHERE id = v_rel_lock_id;
    SELECT status INTO v_rel_status FROM public.released_slots WHERE id = v_rel_id;
    IF (v_res ->> 'success')::BOOLEAN IS DISTINCT FROM TRUE
       OR v_appt_id IS NULL
       OR v_lock_status <> 'CONFIRMED'
       OR v_rel_status <> 'BOOKED'
       OR NOT EXISTS (
           SELECT 1 FROM public.released_slots
            WHERE id = v_rel_id AND claimed_by_appointment_id = v_appt_id
       ) THEN
        RAISE EXCEPTION 'T7-confirm FAILED: res=%, lock_status=%, rel_status=%', v_res, v_lock_status, v_rel_status;
    END IF;

    RAISE NOTICE 'ALL 7 MIGRATION 04 LOCK & RELEASED-SLOT TESTS PASSED';
END $$;

ROLLBACK;
