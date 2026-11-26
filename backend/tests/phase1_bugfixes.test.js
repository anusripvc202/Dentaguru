/**
 * GS HEALTH — Phase 1 Bug Fixes Verification Tests (Pure In-Memory Mocked, Zero DB Writes)
 * Covers:
 * 1. Online consultation 20-minute slot generation vs In-Person 30-minute slots
 * 2. Non-destructive users.device_token merge (FCM tokens, doctor schedules, blocked slots, and patient metadata never overwrite each other)
 * 3. Safe FCM token extraction for legacy raw strings and JSON-backed users
 */
const assert = require('assert');
const { describe, it, after } = require('node:test');

process.env.SUPABASE_URL = process.env.SUPABASE_URL || 'https://mock-local-unit.supabase.co';
process.env.SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY || 'mock-anon-key-unit-test';
process.env.SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY || 'mock-service-role-key-unit-test';

const {
    parseDeviceTokenPayload,
    extractFcmToken,
    extractFcmTokens,
    mergeDeviceTokenPayload,
} = require('../src/utils/deviceTokenHelper');
const { supabaseAdmin } = require('../src/config/supabase');
const Schemas = require('../src/models/Schemas');
const availabilityController = require('../src/controllers/availabilityController');
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

describe('Phase 1 Bug Fixes — Online 20-min Slots & Device Token Non-Destructive Merge', () => {
    const origDentistFindById = Schemas.Dentist.findById;
    const origAvailFindOne = Schemas.DoctorAvailability.findOne;
    const origAvailGetSchedule = Schemas.DoctorAvailability.getSchedule;
    const origAvailGetBlocked = Schemas.DoctorAvailability.getBlockedSlotsForDate;
    const origApptFind = Schemas.Appointment.find;
    const origSupabaseFrom = supabaseAdmin.from;

    after(() => {
        Schemas.Dentist.findById = origDentistFindById;
        Schemas.DoctorAvailability.findOne = origAvailFindOne;
        Schemas.DoctorAvailability.getSchedule = origAvailGetSchedule;
        Schemas.DoctorAvailability.getBlockedSlotsForDate = origAvailGetBlocked;
        Schemas.Appointment.find = origApptFind;
        supabaseAdmin.from = origSupabaseFrom;
        resetBookingRulesConfig();
    });

    it('Fix 1: GET /doctor-availability returns 20-minute slots for Online and 30-minute slots for In-Person (even when a 30-min availability row exists)', async () => {
        setBookingRulesConfig({
            inPersonDurationMinutes: 30,
            onlineDurationMinutes: 20,
            inPersonBufferMinutes: 10,
            onlineBufferMinutes: 5,
            debugNowOverride: new Date('2026-12-09T03:00:00.000Z'),
        });

        const docId = '22222222-2222-4222-8222-222222222210';
        Schemas.Dentist.findById = async () => ({
            id: docId,
            user_id: '11111111-1111-4111-8111-111111111110',
            availability_status: 'Available',
            verification_status: 'VERIFIED',
        });
        Schemas.DoctorAvailability.getSchedule = async () => ({
            workingDays: ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'],
            startTime: '09:00 AM',
            endTime: '11:00 AM',
            slotDurationMinutes: 30,
            slotIntervalMinutes: 30,
            hasBreak: false,
            breakStartTime: null,
            breakEndTime: null,
            isConfigured: true,
        });
        // Simulate an existing 30-min availability row persisted when schedule was saved
        Schemas.DoctorAvailability.findOne = async () => ({
            dentist_id: docId,
            date: '2026-12-10',
            start_time: '09:00 AM',
            end_time: '11:00 AM',
            slot_duration_minutes: 30,
            slots: ['09:00 AM', '09:30 AM', '10:00 AM', '10:30 AM'],
            is_blocked: false,
        });
        Schemas.DoctorAvailability.getBlockedSlotsForDate = async () => [];
        Schemas.Appointment.find = async () => [];

        // 1. In-Person request -> 30-minute intervals
        const { res: resInPerson, out: outInPerson } = createMockRes();
        await availabilityController.getDoctorAvailability(
            { query: { dentistId: docId, date: '2026-12-10', consultationType: 'In-Person' } },
            resInPerson
        );
        assert.strictEqual(outInPerson.statusCode, 200);
        assert.strictEqual(outInPerson.body.availability.consultationDurationMinutes, 30);
        assert.deepStrictEqual(outInPerson.body.availability.allSlots, [
            '09:00 AM',
            '09:30 AM',
            '10:00 AM',
            '10:30 AM',
        ]);

        // 2. Online request -> 20-minute intervals (NOT static 30-min grid!)
        const { res: resOnline, out: outOnline } = createMockRes();
        await availabilityController.getDoctorAvailability(
            { query: { dentistId: docId, date: '2026-12-10', consultationType: 'Online' } },
            resOnline
        );
        assert.strictEqual(outOnline.statusCode, 200);
        assert.strictEqual(outOnline.body.availability.consultationDurationMinutes, 20);
        assert.strictEqual(outOnline.body.availability.slotDurationMinutes, 20);
        assert.deepStrictEqual(outOnline.body.availability.allSlots, [
            '09:00 AM',
            '09:20 AM',
            '09:40 AM',
            '10:00 AM',
            '10:20 AM',
            '10:40 AM',
        ]);
        assert.deepStrictEqual(outOnline.body.availability.availableSlots, [
            '09:00 AM',
            '09:20 AM',
            '09:40 AM',
            '10:00 AM',
            '10:20 AM',
            '10:40 AM',
        ]);
    });

    it('Fix 3a: deviceTokenHelper non-destructively merges FCM tokens, doctor schedules, blocked slots, and patient metadata', () => {
        // Case 1: Doctor already has schedule + blocked slots; saving FCM token MUST preserve both
        const existingDoctorMeta = JSON.stringify({
            city: 'Hyderabad',
            schedule: { workingDays: ['Monday', 'Wednesday'], startTime: '10:00 AM', endTime: '04:00 PM', slotDurationMinutes: 30 },
            blockedSlotsByDate: { '2026-12-10': [{ startTime: '02:00 PM', reason: 'Surgery' }] },
        });
        const afterFcm = mergeDeviceTokenPayload(existingDoctorMeta, { fcmToken: 'fcm_doctor_token_abc123456' });
        const parsedAfterFcm = JSON.parse(afterFcm);
        assert.strictEqual(parsedAfterFcm.city, 'Hyderabad');
        assert.strictEqual(parsedAfterFcm.schedule.startTime, '10:00 AM');
        assert.strictEqual(parsedAfterFcm.blockedSlotsByDate['2026-12-10'].length, 1);
        assert.strictEqual(extractFcmToken(afterFcm), 'fcm_doctor_token_abc123456');

        // Case 2: Legacy user has a bare raw FCM token string; saving schedule or patient profile MUST preserve the FCM token
        const legacyRawFcm = 'fcm_legacy_raw_token_xyz987654';
        const afterSchedule = mergeDeviceTokenPayload(legacyRawFcm, {
            schedule: { workingDays: ['Monday'], startTime: '09:00 AM', endTime: '01:00 PM' },
        });
        const parsedAfterSchedule = JSON.parse(afterSchedule);
        assert.strictEqual(parsedAfterSchedule.schedule.startTime, '09:00 AM');
        assert.strictEqual(extractFcmToken(afterSchedule), legacyRawFcm);

        // Case 3: Patient with JSON metadata only (no FCM token) -> extractFcmToken returns null (never returns JSON!)
        const metaOnly = JSON.stringify({ city: 'Warangal', age: '32', gender: 'Female' });
        assert.strictEqual(extractFcmToken({ device_token: metaOnly }), null);

        // Case 4: Second device token added -> preserves history up to 5 tokens and puts newest first
        const afterSecondDevice = mergeDeviceTokenPayload(afterFcm, { fcmToken: 'fcm_doctor_token_device2_999' });
        assert.strictEqual(extractFcmToken(afterSecondDevice), 'fcm_doctor_token_device2_999');
        assert.deepStrictEqual(extractFcmTokens(afterSecondDevice), [
            'fcm_doctor_token_device2_999',
            'fcm_doctor_token_abc123456',
        ]);
        assert.strictEqual(parseDeviceTokenPayload(afterSecondDevice).schedule.startTime, '10:00 AM');
    });

    it('Fix 3b: User.updateFcmToken and User.findByIdAndUpdate never overwrite existing schedule/metadata in users.device_token', async () => {
        const userId = '11111111-1111-4111-8111-111111111199';
        const store = {
            id: userId,
            name: 'Dr. Safe Merge',
            role: 'Dentist',
            device_token: JSON.stringify({
                city: 'Hyderabad',
                schedule: { workingDays: ['Monday', 'Friday'], startTime: '09:30 AM', endTime: '05:30 PM' },
            }),
        };

        supabaseAdmin.from = () => {
            let pendingUpdate = null;
            const chain = {
                select() { return chain; },
                update(payload) {
                    pendingUpdate = payload;
                    if (payload.device_token !== undefined) store.device_token = payload.device_token;
                    if (payload.city !== undefined) store.city = payload.city;
                    return chain;
                },
                eq() { return chain; },
                maybeSingle() {
                    return Promise.resolve({ data: { ...store }, error: null });
                },
                then(resolve, reject) {
                    return Promise.resolve({ data: pendingUpdate ? { ...store } : [{ ...store }], error: null }).then(resolve, reject);
                },
            };
            return chain;
        };

        // 1. Update FCM token -> schedule & city MUST remain intact
        const updated1 = await Schemas.User.updateFcmToken(userId, 'fcm_live_device_token_123456');
        assert.strictEqual(updated1.fcm_token, 'fcm_live_device_token_123456');
        const meta1 = JSON.parse(store.device_token);
        assert.strictEqual(meta1.schedule.startTime, '09:30 AM');
        assert.strictEqual(meta1.city, 'Hyderabad');
        assert.strictEqual(meta1.fcmToken, 'fcm_live_device_token_123456');

        // 2. Legacy caller updating profile city -> FCM token & schedule MUST remain intact
        await Schemas.User.findByIdAndUpdate(userId, { city: 'Secunderabad' });
        const meta2 = JSON.parse(store.device_token);
        assert.strictEqual(meta2.city, 'Secunderabad');
        assert.strictEqual(meta2.schedule.startTime, '09:30 AM');
        assert.strictEqual(meta2.fcmToken, 'fcm_live_device_token_123456');
    });
});
