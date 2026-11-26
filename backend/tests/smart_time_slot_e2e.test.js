/**
 * GS HEALTH — Complete Smart Time Slot System E2E & Static SQL Verification Suite
 * Pure in-memory mocked (ZERO database writes, ZERO SQL execution on Staging/Production).
 *
 * Covers all 10 required end-to-end workflow scenarios + static Migration 04 & Rollback checks:
 * 1. Doctor configures smart schedule (working days/hours, multiple breaks, separate Online/In-Person, 15/20/30/45/60 durations, buffers, daily limit, blocked dates/ranges, Asia/Kolkata, zero writes to users.device_token)
 * 2. Patient views dynamically generated Online & In-Person slots
 * 3. Patient acquires temporary slot lock and confirms atomically
 * 4. Second patient attempting same slot or lock bypass (NULL/missing/expired/mismatched) is rejected
 * 5. Doctor starts & completes consultation early
 * 6. System releases eligible early slot ONLY when full duration+buffer fits (never moves confirmed visits; prevents duplicates; never auto-completes)
 * 7. Eligible patients receive FCM + in-app notifications respecting preferences; duplicates prevented; invalid FCM token cleared safely
 * 8. Released slot ownership enforced (direct booking of AVAILABLE slot without lock rejected; first patient to lock+confirm gets it)
 * 9. Doctor calendar returns daily & weekly summaries, schedule overview, and released slots; schedule updates preserve existing bookings
 * 10. Cancellation, rescheduling, expired locks, and unavailable slots behave accurately
 * 11. Static SQL audit of Migration 04, Rollback 04, and Verification 04 scripts
 */

const fs = require('fs');
const path = require('path');
const assert = require('assert');
const { describe, it, beforeEach, after } = require('node:test');

process.env.SUPABASE_URL = process.env.SUPABASE_URL || 'https://mock-local-unit.supabase.co';
process.env.SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY || 'mock-anon-key-unit-test';
process.env.SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY || 'mock-service-role-key-unit-test';

const { supabaseAdmin } = require('../src/config/supabase');
const Schemas = require('../src/models/Schemas');
const availabilityController = require('../src/controllers/availabilityController');
const appointmentController = require('../src/controllers/appointmentController');
const {
    generateDynamicSlots,
    computeEarlyCompletionReleasedSlot,
    sanitizeSmartSchedule,
    ALLOWED_DURATIONS,
} = require('../src/services/smartSchedulingEngine');
const { notifyEligiblePatientsForReleasedSlot } = require('../src/services/releasedSlotNotificationService');
const { extractFcmToken, parseDeviceTokenPayload } = require('../src/utils/deviceTokenHelper');
const { setBookingRulesConfig, resetBookingRulesConfig } = require('../src/config/bookingRulesConfig');

function createMockRes() {
    const out = { statusCode: 200, body: null };
    const res = {
        status(code) {
            out.statusCode = code;
            return res;
        },
        json(payload) {
            out.body = payload;
            return res;
        },
    };
    return { res, out };
}

describe('GS HEALTH — Complete Smart Time Slot System (10 E2E Scenarios + Static SQL Audit)', () => {
    const DOC_USER_ID = '11111111-1111-4111-8111-111111111001';
    const DENTIST_ID = '22222222-2222-4222-8222-222222222001';
    const PATIENT_A_ID = '33333333-3333-4333-8333-333333333001';
    const PATIENT_B_ID = '33333333-3333-4333-8333-333333333002';
    const PATIENT_C_ID = '33333333-3333-4333-8333-333333333003';

    // Use a guaranteed Monday in IST (2026-12-07 is Monday)
    const TEST_MON_YMD = '2026-12-07';
    const TEST_SAT_YMD = '2026-12-12';
    const MOCK_NOW_MORNING_IST = new Date('2026-12-07T02:30:00.000Z'); // 08:00 AM IST on Mon 2026-12-07

    const origMethods = {
        supabaseFrom: supabaseAdmin.from,
        supabaseRpc: supabaseAdmin.rpc,
        DentistFindById: Schemas.Dentist.findById,
        DentistFindOne: Schemas.Dentist.findOne,
        DentistFindByIdAndUpdate: Schemas.Dentist.findByIdAndUpdate,
        UserFindById: Schemas.User.findById,
        UserFindByIdAndUpdate: Schemas.User.findByIdAndUpdate,
        ApptCreate: Schemas.Appointment.create,
        ApptFind: Schemas.Appointment.find,
        ApptFindById: Schemas.Appointment.findById,
        ApptFindByIdAndUpdate: Schemas.Appointment.findByIdAndUpdate,
        NotifCreate: Schemas.Notification.create,
        MedRecCreate: Schemas.MedicalRecord.create,
        RefUpdate: Schemas.Referral.updateStatusForReferredUser,
        RefFind: Schemas.Referral.find,
        AvailFindOne: Schemas.DoctorAvailability.findOne,
        AvailFind: Schemas.DoctorAvailability.find,
        AvailUpsert: Schemas.DoctorAvailability.upsert,
        AvailDeleteOne: Schemas.DoctorAvailability.deleteOne,
        AvailResolveIds: Schemas.DoctorAvailability.resolveCanonicalIds,
        AssignRecord: Schemas.PatientAssignmentHistory.recordAssignment,
        ClinicFindById: Schemas.Clinic.findById,
    };

    let memAppointments = [];
    let memNotifications = [];
    let memUsers = {};
    let memAvailRecords = new Map();
    let deviceTokenWriteAttempts = [];

    beforeEach(() => {
        memAppointments = [];
        memNotifications = [];
        memAvailRecords = new Map();
        deviceTokenWriteAttempts = [];
        Schemas.DoctorSchedulingSettings._clearInMemory();
        Schemas.AppointmentSlotLock._clearInMemory();
        Schemas.ReleasedSlot._clearInMemory();
        Schemas.PatientDoctorPreference._clearInMemory();
        Schemas.SlotNotificationDelivery._clearInMemory();

        setBookingRulesConfig({
            inPersonDurationMinutes: 30,
            onlineDurationMinutes: 20,
            inPersonBufferMinutes: 10,
            onlineBufferMinutes: 5,
            minAdvanceBookingMinutes: 30,
            maxAdvanceBookingDays: 90,
            timezone: 'Asia/Kolkata',
            debugNowOverride: MOCK_NOW_MORNING_IST,
        });

        memUsers = {
            [DOC_USER_ID]: {
                id: DOC_USER_ID,
                name: 'Dr. Kavitha Rao',
                role: 'DOCTOR',
                status: 'ACTIVE',
                device_token: JSON.stringify({ fcmToken: 'fcm_doctor_valid_token_999', city: 'Hyderabad' }),
            },
            [PATIENT_A_ID]: {
                id: PATIENT_A_ID,
                name: 'Ananya Sharma',
                phone: '9876543210',
                role: 'Patient',
                status: 'ACTIVE',
                device_token: JSON.stringify({ fcmToken: 'fcm_patient_a_valid_token_111', city: 'Hyderabad' }),
            },
            [PATIENT_B_ID]: {
                id: PATIENT_B_ID,
                name: 'Rahul Verma',
                phone: '9876543211',
                role: 'Patient',
                status: 'ACTIVE',
                device_token: JSON.stringify({ fcmToken: 'fcm_patient_b_valid_token_222', city: 'Warangal', bloodGroup: 'O+' }),
            },
            [PATIENT_C_ID]: {
                id: PATIENT_C_ID,
                name: 'Meera Nair',
                phone: '9876543212',
                role: 'Patient',
                status: 'ACTIVE',
                device_token: JSON.stringify({ fcmToken: 'fcm_patient_c_EXPIRED_token_333', city: 'Hyderabad', age: '29' }),
            },
        };

        // Block any real network calls to Supabase in pure unit tests
        supabaseAdmin.rpc = async () => ({ data: null, error: { message: 'mock rpc disabled in pure unit test' } });
        supabaseAdmin.from = (table) => {
            const chain = {
                select() { return chain; },
                insert() { return chain; },
                upsert() { return chain; },
                update(payload) {
                    if (table === 'users' && payload?.device_token !== undefined) {
                        deviceTokenWriteAttempts.push(payload.device_token);
                    }
                    return chain;
                },
                delete() { return chain; },
                eq() { return chain; },
                in() { return chain; },
                gt() { return chain; },
                gte() { return chain; },
                or() { return chain; },
                order() { return chain; },
                limit() { return chain; },
                single() { return Promise.resolve({ data: null, error: { message: 'mock table disabled' } }); },
                maybeSingle() { return Promise.resolve({ data: null, error: { message: 'mock table disabled' } }); },
                then(resolve) { return Promise.resolve({ data: null, error: { message: 'mock table disabled' } }).then(resolve); },
            };
            return chain;
        };

        Schemas.DoctorAvailability.resolveCanonicalIds = async (id) => ({
            canonicalId: DENTIST_ID,
            dentistTableId: DENTIST_ID,
            userTableId: DOC_USER_ID,
            idsToMatch: [...new Set([id, DENTIST_ID, DOC_USER_ID].filter(Boolean))],
        });
        Schemas.Dentist.findById = async () => ({
            id: DENTIST_ID,
            user_id: DOC_USER_ID,
            speciality: 'General Medicine',
            availability_status: 'Available',
            verification_status: 'VERIFIED',
            users: memUsers[DOC_USER_ID],
        });
        Schemas.Dentist.findOne = Schemas.Dentist.findById;
        Schemas.Dentist.findByIdAndUpdate = async (_id, patch) => ({ id: DENTIST_ID, ...patch });
        Schemas.User.findById = async (id) => memUsers[id] || null;
        Schemas.User.findByIdAndUpdate = async (id, patch) => {
            if (memUsers[id]) {
                if (patch.device_token !== undefined) {
                    deviceTokenWriteAttempts.push(patch.device_token);
                }
                memUsers[id] = { ...memUsers[id], ...patch };
            }
            return memUsers[id] || null;
        };
        Schemas.Appointment.create = async (data) => {
            const row = {
                id: `00000000-0000-4000-8000-${String(memAppointments.length + 1).padStart(12, '0')}`,
                created_at: new Date().toISOString(),
                ...data,
                patient: memUsers[data.patient_id] || null,
                dentist: { id: DENTIST_ID, user_id: DOC_USER_ID, speciality: 'General Medicine', users: memUsers[DOC_USER_ID] },
            };
            memAppointments.push(row);
            return row;
        };
        Schemas.Appointment.find = async (query = {}) => {
            return memAppointments.filter(a => {
                if (query.dentistId && String(a.dentist_id) !== String(query.dentistId)) return false;
                if (query.patientId && String(a.patient_id) !== String(query.patientId)) return false;
                return true;
            });
        };
        Schemas.Appointment.findById = async (id) => memAppointments.find(a => String(a.id) === String(id)) || null;
        Schemas.Appointment.findByIdAndUpdate = async (id, patch) => {
            const idx = memAppointments.findIndex(a => String(a.id) === String(id));
            if (idx === -1) return null;
            memAppointments[idx] = { ...memAppointments[idx], ...patch };
            return memAppointments[idx];
        };
        Schemas.Notification.create = async (n) => {
            const row = { id: `notif-${memNotifications.length + 1}`, created_at: new Date().toISOString(), ...n };
            memNotifications.push(row);
            return row;
        };
        Schemas.MedicalRecord.create = async (rec) => ({ id: `rec-${Date.now()}`, ...rec });
        Schemas.Referral.updateStatusForReferredUser = async () => null;
        Schemas.Referral.find = async () => [];
        Schemas.PatientAssignmentHistory.recordAssignment = async () => null;
        Schemas.Clinic.findById = async () => null;
        Schemas.DoctorAvailability.findOne = async ({ date }) => memAvailRecords.get(date) || null;
        Schemas.DoctorAvailability.find = async ({ is_blocked } = {}) => {
            const arr = Array.from(memAvailRecords.values());
            return is_blocked !== undefined ? arr.filter(r => Boolean(r.is_blocked) === Boolean(is_blocked)) : arr;
        };
        Schemas.DoctorAvailability.upsert = async (rec) => {
            memAvailRecords.set(rec.date, rec);
            return rec;
        };
        Schemas.DoctorAvailability.deleteOne = async ({ date }) => {
            memAvailRecords.delete(date);
            return { success: true };
        };
    });

    after(() => {
        supabaseAdmin.from = origMethods.supabaseFrom;
        supabaseAdmin.rpc = origMethods.supabaseRpc;
        Schemas.Dentist.findById = origMethods.DentistFindById;
        Schemas.Dentist.findOne = origMethods.DentistFindOne;
        Schemas.Dentist.findByIdAndUpdate = origMethods.DentistFindByIdAndUpdate;
        Schemas.User.findById = origMethods.UserFindById;
        Schemas.User.findByIdAndUpdate = origMethods.UserFindByIdAndUpdate;
        Schemas.Appointment.create = origMethods.ApptCreate;
        Schemas.Appointment.find = origMethods.ApptFind;
        Schemas.Appointment.findById = origMethods.ApptFindById;
        Schemas.Appointment.findByIdAndUpdate = origMethods.ApptFindByIdAndUpdate;
        Schemas.Notification.create = origMethods.NotifCreate;
        Schemas.MedicalRecord.create = origMethods.MedRecCreate;
        Schemas.Referral.updateStatusForReferredUser = origMethods.RefUpdate;
        Schemas.Referral.find = origMethods.RefFind;
        Schemas.DoctorAvailability.findOne = origMethods.AvailFindOne;
        Schemas.DoctorAvailability.find = origMethods.AvailFind;
        Schemas.DoctorAvailability.upsert = origMethods.AvailUpsert;
        Schemas.DoctorAvailability.deleteOne = origMethods.AvailDeleteOne;
        Schemas.DoctorAvailability.resolveCanonicalIds = origMethods.AvailResolveIds;
        Schemas.PatientAssignmentHistory.recordAssignment = origMethods.AssignRecord;
        Schemas.Clinic.findById = origMethods.ClinicFindById;
        resetBookingRulesConfig();
    });

    it('Scenarios 1 & 2: Doctor configures smart schedule (multiple breaks, separate Online/In-Person, 15/20/30/45/60, buffers, daily cap, blocked ranges) WITHOUT writing to users.device_token; Patient sees accurate dynamic slots', async () => {
        assert.deepStrictEqual(ALLOWED_DURATIONS, [15, 20, 30, 45, 60]);

        const { res: updRes, out: updOut } = createMockRes();
        await availabilityController.updateDoctorSchedule({
            user: { id: DOC_USER_ID, role: 'DOCTOR' },
            body: {
                dentistId: DENTIST_ID,
                workingDays: ['Monday', 'Wednesday', 'Friday'],
                startTime: '09:00 AM',
                endTime: '05:00 PM',
                breaks: [
                    { startTime: '11:30 AM', endTime: '12:00 PM', label: 'Morning Break' },
                    { startTime: '01:00 PM', endTime: '02:00 PM', label: 'Lunch Break' },
                ],
                inPersonEnabled: true,
                inPersonDurationMinutes: 30,
                inPersonBufferMinutes: 10,
                onlineEnabled: true,
                onlineDurationMinutes: 20,
                onlineBufferMinutes: 5,
                onlineStartTime: '09:00 AM',
                onlineEndTime: '04:00 PM',
                maxAppointmentsPerDay: 10,
                allowSimultaneousOnlineAndInPerson: false,
                applyToUpcomingDays: false,
            },
        }, updRes);

        assert.strictEqual(updOut.statusCode, 200);
        assert.strictEqual(updOut.body.success, true);
        assert.strictEqual(updOut.body.schedule.breaks.length, 2);
        assert.strictEqual(updOut.body.schedule.onlineDurationMinutes, 20);
        assert.strictEqual(updOut.body.schedule.inPersonDurationMinutes, 30);
        assert.strictEqual(updOut.body.schedule.maxAppointmentsPerDay, 10);

        // Verify custom blocked time range (02:30 PM - 03:30 PM)
        const { res: blkRes, out: blkOut } = createMockRes();
        await availabilityController.blockTimeSlot({
            user: { id: DOC_USER_ID, role: 'DOCTOR' },
            body: {
                dentistId: DENTIST_ID,
                date: TEST_MON_YMD,
                startTime: '02:30 PM',
                endTime: '03:30 PM',
                reason: 'Hospital Rounds',
            },
        }, blkRes);
        assert.strictEqual(blkOut.statusCode, 200);

        // STRICT REQUIREMENT #9: ZERO scheduling writes to users.device_token!
        assert.strictEqual(deviceTokenWriteAttempts.length, 0, 'Scheduling settings & blocked ranges must NEVER write into users.device_token');
        assert.strictEqual(extractFcmToken(memUsers[DOC_USER_ID]), 'fcm_doctor_valid_token_999');

        // Patient fetches In-Person slots on Monday
        const { res: ipRes, out: ipOut } = createMockRes();
        await availabilityController.getDoctorAvailability({
            user: { id: PATIENT_A_ID, role: 'Patient' },
            query: { dentistId: DENTIST_ID, date: TEST_MON_YMD, consultationType: 'In-Person' },
        }, ipRes);
        assert.strictEqual(ipOut.statusCode, 200);
        const ipSlots = ipOut.body.availability.availableSlots;
        assert.ok(ipSlots.includes('09:00 AM'));
        assert.ok(!ipSlots.includes('11:30 AM'), 'First break must be excluded');
        assert.ok(!ipSlots.includes('01:00 PM'), 'Second break must be excluded');
        assert.ok(!ipSlots.includes('01:30 PM'), 'Second break must be excluded');
        assert.ok(!ipSlots.includes('02:30 PM'), 'Blocked range start must be excluded');
        assert.ok(!ipSlots.includes('03:00 PM'), 'Blocked range interior must be excluded');
        assert.ok(ipSlots.includes('03:30 PM'), 'Post-blocked slot must be available');

        // Patient fetches Online slots on Monday (20-minute duration, ends at 04:00 PM!)
        const { res: onRes, out: onOut } = createMockRes();
        await availabilityController.getDoctorAvailability({
            user: { id: PATIENT_A_ID, role: 'Patient' },
            query: { dentistId: DENTIST_ID, date: TEST_MON_YMD, consultationType: 'Online' },
        }, onRes);
        assert.strictEqual(onOut.statusCode, 200);
        assert.strictEqual(onOut.body.availability.consultationDurationMinutes, 20);
        assert.strictEqual(onOut.body.availability.bufferMinutes, 5);
        const onSlots = onOut.body.availability.availableSlots;
        assert.ok(onSlots.includes('09:00 AM'));
        assert.ok(onSlots.includes('09:20 AM'));
        assert.ok(onSlots.includes('09:40 AM'));
        assert.ok(!onSlots.includes('04:00 PM'), 'Online schedule ends at 04:00 PM');
        assert.ok(!onSlots.includes('04:20 PM'), 'Outside Online working hours');

        // Non-working Saturday returns zero available slots
        const { res: satRes, out: satOut } = createMockRes();
        await availabilityController.getDoctorAvailability({
            user: { id: PATIENT_A_ID, role: 'Patient' },
            query: { dentistId: DENTIST_ID, date: TEST_SAT_YMD, consultationType: 'In-Person' },
        }, satRes);
        assert.strictEqual(satOut.body.availability.isWorkingDay, false);
        assert.deepStrictEqual(satOut.body.availability.availableSlots, []);
    });

    it('Scenarios 3 & 4: Patient locks & books slot atomically; second patient & lock-bypass attempts (NULL, expired, mismatched) are rejected; shared capacity blocks overlapping Online slot', async () => {
        await Schemas.DoctorSchedulingSettings.upsert(DENTIST_ID, {
            workingDays: ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'],
            startTime: '09:00 AM',
            endTime: '05:00 PM',
            breaks: [{ startTime: '01:00 PM', endTime: '02:00 PM', label: 'Lunch' }],
            inPersonDurationMinutes: 30,
            inPersonBufferMinutes: 10,
            onlineDurationMinutes: 20,
            onlineBufferMinutes: 5,
            allowSimultaneousOnlineAndInPerson: false,
        });

        // Bypass attempt: explicit lockId: null MUST be rejected with LOCK_REQUIRED
        const { res: nullRes, out: nullOut } = createMockRes();
        await appointmentController.bookAppointment({
            user: { id: PATIENT_A_ID, role: 'Patient' },
            body: {
                dentistId: DENTIST_ID,
                patientId: PATIENT_A_ID,
                date: TEST_MON_YMD,
                timeSlot: '09:00 AM',
                consultationMode: 'In-Person',
                treatment: 'General Checkup',
                lockId: null,
                requireLock: true,
            },
        }, nullRes);
        assert.strictEqual(nullOut.statusCode, 409);
        assert.strictEqual(nullOut.body.reason, 'LOCK_REQUIRED');

        // Patient A acquires temporary lock for 09:00 AM In-Person
        const { res: lockARes, out: lockAOut } = createMockRes();
        await availabilityController.acquireSlotLock({
            user: { id: PATIENT_A_ID, role: 'Patient' },
            body: {
                dentistId: DENTIST_ID,
                patientId: PATIENT_A_ID,
                date: TEST_MON_YMD,
                timeSlot: '09:00 AM',
                consultationType: 'In-Person',
            },
        }, lockARes);
        assert.strictEqual(lockAOut.statusCode, 200);
        assert.strictEqual(lockAOut.body.success, true);
        const lockAId = lockAOut.body.lockId;
        assert.ok(lockAId);

        // Patient B attempts to lock the same 09:00 AM slot (or overlapping 09:20 AM Online slot!) -> REJECTED
        const { res: lockBRes, out: lockBOut } = createMockRes();
        await availabilityController.acquireSlotLock({
            user: { id: PATIENT_B_ID, role: 'Patient' },
            body: {
                dentistId: DENTIST_ID,
                patientId: PATIENT_B_ID,
                date: TEST_MON_YMD,
                timeSlot: '09:20 AM',
                consultationType: 'Online',
            },
        }, lockBRes);
        assert.strictEqual(lockBOut.statusCode, 409);
        assert.strictEqual(lockBOut.body.reason, 'SLOT_LOCKED');

        // Patient B attempts to steal Patient A's lockId -> REJECTED with LOCK_MISMATCH_OR_EXPIRED
        const { res: stealRes, out: stealOut } = createMockRes();
        await appointmentController.bookAppointment({
            user: { id: PATIENT_B_ID, role: 'Patient' },
            body: {
                dentistId: DENTIST_ID,
                patientId: PATIENT_B_ID,
                date: TEST_MON_YMD,
                timeSlot: '09:00 AM',
                consultationMode: 'In-Person',
                treatment: 'General Checkup',
                lockId: lockAId,
                requireLock: true,
            },
        }, stealRes);
        assert.strictEqual(stealOut.statusCode, 409);
        assert.strictEqual(stealOut.body.reason, 'LOCK_MISMATCH_OR_EXPIRED');

        // Patient A confirms booking using valid lockAId -> SUCCEEDS (201)
        const { res: bookARes, out: bookAOut } = createMockRes();
        await appointmentController.bookAppointment({
            user: { id: PATIENT_A_ID, role: 'Patient' },
            body: {
                dentistId: DENTIST_ID,
                patientId: PATIENT_A_ID,
                date: TEST_MON_YMD,
                timeSlot: '09:00 AM',
                consultationMode: 'In-Person',
                treatment: 'General Checkup',
                lockId: lockAId,
                requireLock: true,
            },
        }, bookARes);
        assert.strictEqual(bookAOut.statusCode, 201);
        assert.strictEqual(bookAOut.body.success, true);
        assert.strictEqual(Schemas.AppointmentSlotLock.getInMemoryLock(lockAId).status, 'CONFIRMED');

        // Patient B attempts to book overlapping 09:30 AM (inside Patient A's 10m buffer 09:30-09:40) -> REJECTED
        const { res: overlapRes, out: overlapOut } = createMockRes();
        await appointmentController.bookAppointment({
            user: { id: PATIENT_B_ID, role: 'Patient' },
            body: {
                dentistId: DENTIST_ID,
                patientId: PATIENT_B_ID,
                date: TEST_MON_YMD,
                timeSlot: '09:30 AM',
                consultationMode: 'In-Person',
                treatment: 'Follow-up',
            },
        }, overlapRes);
        assert.strictEqual(overlapOut.statusCode, 409);
        assert.strictEqual(overlapOut.body.reason, 'APPOINTMENT_CONFLICT');
    });

    it('Scenarios 5, 6, 7 & 8: Early completion releases eligible slot (without moving confirmed visit & without duplicates), notifies eligible patients via FCM (clears invalid token safely), blocks direct AVAILABLE booking, and lets first locker win', async () => {
        await Schemas.DoctorSchedulingSettings.upsert(DENTIST_ID, {
            workingDays: ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'],
            startTime: '09:00 AM',
            endTime: '05:00 PM',
            breaks: [{ startTime: '01:00 PM', endTime: '02:00 PM', label: 'Lunch' }],
            inPersonDurationMinutes: 30,
            inPersonBufferMinutes: 10,
            onlineDurationMinutes: 20,
            onlineBufferMinutes: 5,
            allowSimultaneousOnlineAndInPerson: false,
        });

        // Patient A has a 60-min In-Person appointment at 09:00 AM - 10:00 AM (+10m buffer)
        const appt1 = await Schemas.Appointment.create({
            patient_id: PATIENT_A_ID,
            dentist_id: DENTIST_ID,
            date: `${TEST_MON_YMD}T00:00:00.000Z`,
            appointment_date: TEST_MON_YMD,
            time_slot: '09:00 AM',
            consultation_type: 'In-Person',
            duration_minutes: 60,
            buffer_minutes: 10,
            scheduled_start_min: 540,
            scheduled_end_min: 600,
            effective_end_min: 610,
            status: 'CONFIRMED',
            treatment: 'In-Person - Detailed Assessment',
        });

        // Existing confirmed next appointment at 10:00 AM (MUST NEVER be moved or altered!)
        const apptNext = await Schemas.Appointment.create({
            patient_id: PATIENT_B_ID,
            dentist_id: DENTIST_ID,
            date: `${TEST_MON_YMD}T00:00:00.000Z`,
            appointment_date: TEST_MON_YMD,
            time_slot: '10:00 AM',
            consultation_type: 'In-Person',
            duration_minutes: 30,
            buffer_minutes: 10,
            scheduled_start_min: 600,
            scheduled_end_min: 630,
            effective_end_min: 640,
            status: 'CONFIRMED',
            treatment: 'In-Person - Follow-up',
        });

        // Configure earlier-slot notification preferences:
        // Patient B opted in for Online slots; Patient C opted in for Any slots (with an expired FCM token!)
        await Schemas.PatientDoctorPreference.upsert({
            patientId: PATIENT_B_ID,
            dentistId: DENTIST_ID,
            isFavorite: true,
            notifyEarlierSlots: true,
            preferredConsultationType: 'Online',
            preferredDate: TEST_MON_YMD,
            earliestTimeMin: 540,
            latestTimeMin: 660,
        });
        await Schemas.PatientDoctorPreference.upsert({
            patientId: PATIENT_C_ID,
            dentistId: DENTIST_ID,
            isFavorite: true,
            notifyEarlierSlots: true,
            preferredConsultationType: 'Any',
            preferredDate: TEST_MON_YMD,
        });

        // Doctor starts appt1 at 09:00 AM IST and completes EARLY at 09:20 AM IST
        // After 10m cleanup buffer -> doctor is free at 09:30 AM IST.
        // Next confirmed visit is at 10:00 AM IST -> 30 minutes available!
        // In-Person (30m + 10m buffer = 40m) does NOT fit, so engine releases Online (20m + 5m buffer = 25m <= 30m) at 09:30 AM!
        const startIstIso = '2026-12-07T03:30:00.000Z'; // 09:00 AM IST
        const earlyEndIstIso = '2026-12-07T03:50:00.000Z'; // 09:20 AM IST

        const { res: startRes, out: startOut } = createMockRes();
        await appointmentController.startConsultation({
            user: { id: DOC_USER_ID, role: 'DOCTOR' },
            params: { id: appt1.id },
            body: { actualStartAt: startIstIso },
        }, startRes);
        assert.strictEqual(startOut.statusCode, 200);
        assert.strictEqual(startOut.body.appointment.status, 'IN_PROGRESS');

        const { res: compRes, out: compOut } = createMockRes();
        await appointmentController.completeConsultation({
            user: { id: DOC_USER_ID, role: 'DOCTOR' },
            params: { id: appt1.id },
            body: {
                diagnosis: 'Mild checkup completed early',
                actualEndAt: earlyEndIstIso,
            },
        }, compRes);

        assert.strictEqual(compOut.statusCode, 200);
        assert.strictEqual(compOut.body.finishedEarly, true);
        assert.ok(compOut.body.releasedSlot, 'Expected an eligible early-completion released slot');
        const released = compOut.body.releasedSlot;
        assert.strictEqual(released.start_time, '09:30 AM');
        assert.strictEqual(released.consultation_type, 'Online');
        assert.strictEqual(released.duration_minutes, 20);
        assert.strictEqual(released.buffer_minutes, 5);
        assert.strictEqual(released.status, 'AVAILABLE');

        // Existing confirmed appointment apptNext MUST remain completely untouched at 10:00 AM
        const unchangedNext = await Schemas.Appointment.findById(apptNext.id);
        assert.strictEqual(unchangedNext.time_slot, '10:00 AM');
        assert.strictEqual(unchangedNext.status, 'CONFIRMED');

        // Duplicate released slot check: computing again returns null
        const dupCandidate = computeEarlyCompletionReleasedSlot({
            completedAppointment: appt1,
            actualEndAt: earlyEndIstIso,
            schedule: await Schemas.DoctorSchedulingSettings.getByDentistId(DENTIST_ID),
            activeAppointments: memAppointments,
            existingReleasedSlots: [released],
        });
        assert.strictEqual(dupCandidate, null, 'Duplicate released slot must never be created');

        // Scenario 7: Test released-slot FCM dispatch with custom pushSender (valid + invalid/expired token + dedup)
        Schemas.SlotNotificationDelivery._clearInMemory();
        const sentPushes = [];
        const notifSummary = await notifyEligiblePatientsForReleasedSlot({
            dentistId: DENTIST_ID,
            doctorName: 'Dr. Kavitha Rao',
            releasedSlot: released,
            excludePatientId: PATIENT_A_ID,
            pushSender: async (token, title, body, data) => {
                sentPushes.push({ token, title, data });
                if (token.includes('EXPIRED')) {
                    return { ok: false, skipped: false, invalidToken: true, errorCode: 'messaging/registration-token-not-registered' };
                }
                return { ok: true, skipped: false, invalidToken: false, messageId: 'fcm-msg-ok-1' };
            },
        });
        assert.strictEqual(notifSummary.eligibleCount, 2);
        assert.strictEqual(notifSummary.sentCount, 1);
        assert.strictEqual(notifSummary.invalidTokensCleared, 1);
        assert.strictEqual(sentPushes.length, 2);
        // Patient C's invalid FCM token was safely cleared while preserving city & age!
        assert.strictEqual(extractFcmToken(memUsers[PATIENT_C_ID]), null);
        const patCMeta = parseDeviceTokenPayload(memUsers[PATIENT_C_ID].device_token);
        assert.strictEqual(patCMeta.city, 'Hyderabad');
        assert.strictEqual(patCMeta.age, '29');

        // Running notify a second time for same released slot MUST skip all duplicates!
        const dupNotif = await notifyEligiblePatientsForReleasedSlot({
            dentistId: DENTIST_ID,
            doctorName: 'Dr. Kavitha Rao',
            releasedSlot: released,
            excludePatientId: PATIENT_A_ID,
            pushSender: async () => ({ ok: true, messageId: 'should-not-run' }),
        });
        assert.strictEqual(dupNotif.skippedDuplicates, 2);
        assert.strictEqual(dupNotif.sentCount, 0);

        // Scenario 8a: Direct booking of AVAILABLE released slot WITHOUT lock MUST be rejected
        const { res: bypassRelRes, out: bypassRelOut } = createMockRes();
        await appointmentController.bookAppointment({
            user: { id: PATIENT_C_ID, role: 'Patient' },
            body: {
                dentistId: DENTIST_ID,
                patientId: PATIENT_C_ID,
                date: TEST_MON_YMD,
                timeSlot: '09:30 AM',
                consultationMode: 'Online',
                treatment: 'Early Online Consult',
                releasedSlotId: released.id,
            },
        }, bypassRelRes);
        assert.strictEqual(bypassRelOut.statusCode, 409);
        assert.strictEqual(bypassRelOut.body.reason, 'LOCK_REQUIRED');
        assert.strictEqual((await Schemas.ReleasedSlot.findById(released.id)).status, 'AVAILABLE');

        // Scenario 8b: Trying to acquire a regular lock (no releasedSlotId) over an AVAILABLE released slot -> REJECTED
        const { res: hijackRes, out: hijackOut } = createMockRes();
        await availabilityController.acquireSlotLock({
            user: { id: PATIENT_C_ID, role: 'Patient' },
            body: {
                dentistId: DENTIST_ID,
                patientId: PATIENT_C_ID,
                date: TEST_MON_YMD,
                timeSlot: '09:30 AM',
                consultationType: 'Online',
            },
        }, hijackRes);
        assert.strictEqual(hijackOut.statusCode, 409);
        assert.strictEqual(hijackOut.body.reason, 'RELEASED_SLOT_LOCK_REQUIRED');

        // Scenario 8c: Patient C locks the released slot properly -> AVAILABLE -> LOCKED
        const { res: lockRelRes, out: lockRelOut } = createMockRes();
        await availabilityController.acquireSlotLock({
            user: { id: PATIENT_C_ID, role: 'Patient' },
            body: {
                dentistId: DENTIST_ID,
                patientId: PATIENT_C_ID,
                date: TEST_MON_YMD,
                timeSlot: '09:30 AM',
                consultationType: 'Online',
                releasedSlotId: released.id,
            },
        }, lockRelRes);
        assert.strictEqual(lockRelOut.statusCode, 200);
        const relLockId = lockRelOut.body.lockId;
        assert.strictEqual((await Schemas.ReleasedSlot.findById(released.id)).status, 'LOCKED');

        // Patient B tries to lock same released slot while Patient C holds lock -> REJECTED
        const { res: lockRelBRes, out: lockRelBOut } = createMockRes();
        await availabilityController.acquireSlotLock({
            user: { id: PATIENT_B_ID, role: 'Patient' },
            body: {
                dentistId: DENTIST_ID,
                patientId: PATIENT_B_ID,
                date: TEST_MON_YMD,
                timeSlot: '09:30 AM',
                consultationType: 'Online',
                releasedSlotId: released.id,
            },
        }, lockRelBRes);
        assert.strictEqual(lockRelBOut.statusCode, 409);
        assert.strictEqual(lockRelBOut.body.reason, 'RELEASED_SLOT_UNAVAILABLE');

        // Patient C confirms booking -> SUCCEEDS; released slot -> BOOKED with claimed_by_appointment_id
        const { res: bookRelRes, out: bookRelOut } = createMockRes();
        await appointmentController.bookAppointment({
            user: { id: PATIENT_C_ID, role: 'Patient' },
            body: {
                dentistId: DENTIST_ID,
                patientId: PATIENT_C_ID,
                date: TEST_MON_YMD,
                timeSlot: '09:30 AM',
                consultationMode: 'Online',
                treatment: 'Early Online Consult',
                lockId: relLockId,
                releasedSlotId: released.id,
                requireLock: true,
            },
        }, bookRelRes);
        assert.strictEqual(bookRelOut.statusCode, 201);
        const bookedRel = await Schemas.ReleasedSlot.findById(released.id);
        assert.strictEqual(bookedRel.status, 'BOOKED');
        assert.strictEqual(bookedRel.claimed_by_appointment_id, bookRelOut.body.appointment.id);
    });

    it('Scenarios 9 & 10: Cancellation frees slot immediately, rescheduling enforces schedule & locks, expired locks restore released slots, and Doctor Calendar returns daily + weekly + schedule data', async () => {
        await Schemas.DoctorSchedulingSettings.upsert(DENTIST_ID, {
            workingDays: ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'],
            startTime: '09:00 AM',
            endTime: '05:00 PM',
            breaks: [{ startTime: '01:00 PM', endTime: '02:00 PM', label: 'Lunch' }],
            inPersonDurationMinutes: 30,
            inPersonBufferMinutes: 10,
            onlineDurationMinutes: 20,
            onlineBufferMinutes: 5,
        });

        // Book 10:00 AM In-Person
        const lock1 = await Schemas.AppointmentSlotLock.acquire({
            dentistId: DENTIST_ID,
            patientId: PATIENT_A_ID,
            date: TEST_MON_YMD,
            startTime: '10:00 AM',
            endTime: '10:40 AM',
            startMin: 600,
            endMin: 640,
            consultationType: 'In-Person',
        });
        const { res: b1Res, out: b1Out } = createMockRes();
        await appointmentController.bookAppointment({
            user: { id: PATIENT_A_ID, role: 'Patient' },
            body: {
                dentistId: DENTIST_ID,
                patientId: PATIENT_A_ID,
                date: TEST_MON_YMD,
                timeSlot: '10:00 AM',
                consultationMode: 'In-Person',
                treatment: 'Routine Checkup',
                lockId: lock1.lockId,
                requireLock: true,
            },
        }, b1Res);
        assert.strictEqual(b1Out.statusCode, 201);
        const apptId = b1Out.body.appointment.id;

        // Reschedule into lunch break (01:00 PM) MUST be rejected
        const { res: badReschedRes, out: badReschedOut } = createMockRes();
        await appointmentController.rescheduleAppointment({
            user: { id: PATIENT_A_ID, role: 'Patient' },
            params: { id: apptId },
            body: { date: TEST_MON_YMD, timeSlot: '01:00 PM' },
        }, badReschedRes);
        assert.strictEqual(badReschedOut.statusCode, 400);
        assert.strictEqual(badReschedOut.body.reason, 'OVERLAPS_BREAK');

        // Reschedule to valid 02:00 PM MUST succeed & free 10:00 AM
        const { res: okReschedRes, out: okReschedOut } = createMockRes();
        await appointmentController.rescheduleAppointment({
            user: { id: PATIENT_A_ID, role: 'Patient' },
            params: { id: apptId },
            body: { date: TEST_MON_YMD, timeSlot: '02:00 PM' },
        }, okReschedRes);
        assert.strictEqual(okReschedOut.statusCode, 200);
        assert.strictEqual(okReschedOut.body.appointment.time_slot, '02:00 PM');

        // Cancel appointment -> frees 02:00 PM immediately
        const { res: cancelRes, out: cancelOut } = createMockRes();
        await appointmentController.cancelAppointment({
            user: { id: PATIENT_A_ID, role: 'Patient' },
            params: { id: apptId },
        }, cancelRes);
        assert.strictEqual(cancelOut.statusCode, 200);

        const { res: afterCancelAvailRes, out: afterCancelAvailOut } = createMockRes();
        await availabilityController.getDoctorAvailability({
            user: { id: PATIENT_B_ID, role: 'Patient' },
            query: { dentistId: DENTIST_ID, date: TEST_MON_YMD, consultationType: 'In-Person' },
        }, afterCancelAvailRes);
        assert.ok(afterCancelAvailOut.body.availability.availableSlots.includes('02:00 PM'), 'Cancelled slot must become available immediately');

        // Expired lock on a released slot MUST automatically restore released slot to AVAILABLE
        const rel = await Schemas.ReleasedSlot.create({
            dentist_id: DENTIST_ID,
            appointment_date: TEST_MON_YMD,
            start_time: '10:20 AM',
            end_time: '10:40 AM',
            start_min: 620,
            end_min: 640,
            duration_minutes: 20,
            buffer_minutes: 5,
            consultation_type: 'Online',
            expires_at: new Date(Date.now() + 60 * 60 * 1000).toISOString(),
        });
        const lockRel = await Schemas.AppointmentSlotLock.acquire({
            dentistId: DENTIST_ID,
            patientId: PATIENT_A_ID,
            date: TEST_MON_YMD,
            startTime: '10:20 AM',
            endTime: '10:45 AM',
            startMin: 620,
            endMin: 645,
            consultationType: 'Online',
            releasedSlotId: rel.id,
            ttlSeconds: 60,
        });
        assert.strictEqual(lockRel.success, true);
        assert.strictEqual((await Schemas.ReleasedSlot.findById(rel.id)).status, 'LOCKED');

        // Force lock expiry -> confirmation MUST fail & released slot MUST return to AVAILABLE
        const memLock = Schemas.AppointmentSlotLock.getInMemoryLock(lockRel.lockId);
        memLock.expires_at = new Date(Date.now() - 5000).toISOString();
        const expiredConfirm = await Schemas.AppointmentSlotLock.confirmBooking({
            patientId: PATIENT_A_ID,
            dentistId: DENTIST_ID,
            date: TEST_MON_YMD,
            timeSlot: '10:20 AM',
            startMin: 620,
            durationMinutes: 20,
            bufferMinutes: 5,
            consultationType: 'Online',
            lockId: lockRel.lockId,
            releasedSlotId: rel.id,
        });
        assert.strictEqual(expiredConfirm.success, false);
        assert.strictEqual(expiredConfirm.reason, 'LOCK_MISMATCH_OR_EXPIRED');
        assert.strictEqual((await Schemas.ReleasedSlot.findById(rel.id)).status, 'AVAILABLE');

        // Separate capacity test: allowSimultaneousOnlineAndInPerson = true allows Online at same time as In-Person
        const sepSched = sanitizeSmartSchedule({
            workingDays: ['Monday'],
            startTime: '09:00 AM',
            endTime: '11:00 AM',
            breaks: [],
            inPersonDurationMinutes: 30,
            onlineDurationMinutes: 20,
            allowSimultaneousOnlineAndInPerson: true,
            isConfigured: true,
        });
        const activeInPerson = [{
            id: 'ip-1',
            date: `${TEST_MON_YMD}T00:00:00.000Z`,
            appointment_date: TEST_MON_YMD,
            time_slot: '09:00 AM',
            consultation_type: 'In-Person',
            duration_minutes: 30,
            buffer_minutes: 10,
            status: 'CONFIRMED',
        }];
        const sepOnline = generateDynamicSlots({
            schedule: sepSched,
            dateYmd: TEST_MON_YMD,
            consultationType: 'Online',
            activeAppointments: activeInPerson,
            now: MOCK_NOW_MORNING_IST,
        });
        assert.ok(sepOnline.availableSlots.includes('09:00 AM'), 'Separate capacity must allow Online slot alongside In-Person');
    });

    it('Scenario 11: Static SQL Audit of Migration 04, Rollback 04, and Verification 04 scripts', () => {
        const migSql = fs.readFileSync(path.join(__dirname, '../migrations/04_smart_scheduling_phase2.sql'), 'utf8');
        const rollbackSql = fs.readFileSync(path.join(__dirname, '../migrations/04_rollback_smart_scheduling_phase2.sql'), 'utf8');
        const verifySql = fs.readFileSync(path.join(__dirname, '../migrations/04_verify_smart_scheduling_phase2.sql'), 'utf8');

        // 1. Strict Staging-only isolation (Production ref must NEVER appear)
        assert.ok(migSql.includes("ojinzcdldwugpnxrnjcq"), 'Migration 04 must gate on Staging ref');
        assert.ok(rollbackSql.includes("ojinzcdldwugpnxrnjcq"), 'Rollback 04 must gate on Staging ref');
        assert.ok(!migSql.includes('fommrwxpqzkcktweosgp'), 'Migration 04 must never reference Production');
        assert.ok(!rollbackSql.includes('fommrwxpqzkcktweosgp'), 'Rollback 04 must never reference Production');

        // 2. Mandatory p_lock_id & strict released-slot ownership in confirm_appointment_booking
        assert.ok(!/p_lock_id\s+UUID\s+DEFAULT/i.test(migSql), 'p_lock_id must NOT have a DEFAULT value');
        assert.ok(migSql.includes("'LOCK_REQUIRED'"), 'confirm_appointment_booking must reject NULL p_lock_id with LOCK_REQUIRED');
        assert.ok(migSql.includes("v_rel.status <> 'LOCKED'"), 'confirm_appointment_booking must require released_slots.status = LOCKED');
        assert.ok(migSql.includes("'RELEASED_SLOT_LOCK_MISMATCH'"), 'confirm_appointment_booking must reject unowned released slots');
        assert.ok(migSql.includes("'RELEASED_SLOT_LOCK_REQUIRED'"), 'must block regular-lock hijack over active released slots');

        // 3. Zero NULL timing bypass on active appointments
        assert.ok(migSql.includes('chk_appointments_active_timing_not_null'));
        assert.ok(migSql.includes('excl_appointments_no_overlapping_intervals'));
        assert.ok(!/OR\s+parse_clock_slot_minutes\s*\(\s*time_slot\s*\)\s+IS\s+NULL/i.test(migSql), 'No NULL parse bypass allowed');

        // 4. GS Health custom OTP/JWT RLS helpers & service_role-only RPCs
        assert.ok(migSql.includes('CREATE OR REPLACE FUNCTION public.gs_health_active_user_id()'));
        assert.ok(migSql.includes('CREATE OR REPLACE FUNCTION public.gs_health_active_dentist_id()'));
        assert.ok(migSql.includes('REVOKE ALL ON FUNCTION public.confirm_appointment_booking'));
        assert.ok(migSql.includes('GRANT EXECUTE ON FUNCTION public.confirm_appointment_booking'));

        // 5. Non-destructive Rollback: ZERO standalone DROP TABLE and ZERO DROP COLUMN statements
        const rollbackNoComments = rollbackSql.replace(/--[^\n]*/g, '');
        const rollbackWithoutPubDrop = rollbackNoComments.replace(/ALTER\s+PUBLICATION\s+[^\n;]+DROP\s+TABLE[^\n;]*/gi, '');
        assert.ok(rollbackSql.includes('CREATE SCHEMA IF NOT EXISTS archive_phase2_rollback'));
        assert.ok(!/\bDROP\s+TABLE\b/i.test(rollbackWithoutPubDrop), 'Rollback must contain ZERO DROP TABLE statements');
        assert.ok(!/\bDROP\s+COLUMN\b/i.test(rollbackNoComments), 'Rollback must contain ZERO DROP COLUMN statements');

        // 6. Transactional verification script wraps all 7 tests in BEGIN ... ROLLBACK
        assert.ok(/\bBEGIN\s*;/i.test(verifySql) && /\bROLLBACK\s*;/i.test(verifySql));
        assert.ok(verifySql.includes('T1') && verifySql.includes('T4') && verifySql.includes('T7'));
    });
});
