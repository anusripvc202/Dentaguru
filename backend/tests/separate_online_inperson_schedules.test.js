const test = require('node:test');
const assert = require('node:assert/strict');

process.env.SUPABASE_URL = process.env.SUPABASE_URL || 'https://mock-local-unit.supabase.co';
process.env.SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY || 'mock-anon-key-unit-test';
process.env.SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY || 'mock-service-role-key-unit-test';

const { supabaseAdmin } = require('../src/config/supabase');
const Schemas = require('../src/models/Schemas');
const availabilityController = require('../src/controllers/availabilityController');
const appointmentController = require('../src/controllers/appointmentController');
const {
    generateDynamicSlots,
    validateSlotAgainstSchedule,
    sanitizeSmartSchedule,
} = require('../src/services/smartSchedulingEngine');
const { setBookingRulesConfig, resetBookingRulesConfig } = require('../src/config/bookingRulesConfig');

function createMockRes() {
    const out = { statusCode: 200, body: null };
    const res = {
        status(code) {
            out.statusCode = code;
            return this;
        },
        json(payload) {
            out.body = payload;
            return this;
        },
    };
    return { res, out };
}

test('Separate Online and In-Person Working Hours & Dynamic Appointment Slots (All 11 Scenarios)', async (t) => {
    const DOC_USER_ID = '11111111-1111-4111-8111-111111111099';
    const DENTIST_ID = '22222222-2222-4222-8222-222222222099';
    const PATIENT_ID = '33333333-3333-4333-8333-333333333099';
    const TEST_MON_YMD = '2026-12-07'; // Monday
    const TEST_TUE_YMD = '2026-12-08'; // Tuesday
    const MOCK_NOW_IST = new Date('2026-12-07T02:00:00.000Z'); // 07:30 AM IST

    const orig = {
        supabaseFrom: supabaseAdmin.from,
        supabaseRpc: supabaseAdmin.rpc,
        DentistFindById: Schemas.Dentist.findById,
        DentistFindOne: Schemas.Dentist.findOne,
        DentistFindByIdAndUpdate: Schemas.Dentist.findByIdAndUpdate,
        AvailFindOne: Schemas.DoctorAvailability.findOne,
        AvailFind: Schemas.DoctorAvailability.find,
        AvailUpsert: Schemas.DoctorAvailability.upsert,
        AvailDeleteOne: Schemas.DoctorAvailability.deleteOne,
        AvailResolveIds: Schemas.DoctorAvailability.resolveCanonicalIds,
        ApptFind: Schemas.Appointment.find,
        ApptCreate: Schemas.Appointment.create,
    };

    let memAppts = [];
    let memAvailByDate = new Map();

    t.beforeEach(() => {
        memAppts = [];
        memAvailByDate = new Map();
        Schemas.DoctorSchedulingSettings._clearInMemory();
        Schemas.AppointmentSlotLock._clearInMemory();
        Schemas.ReleasedSlot._clearInMemory();

        setBookingRulesConfig({
            inPersonDurationMinutes: 30,
            onlineDurationMinutes: 20,
            inPersonBufferMinutes: 10,
            onlineBufferMinutes: 5,
            minAdvanceBookingMinutes: 30,
            maxAdvanceBookingDays: 90,
            timezone: 'Asia/Kolkata',
            debugNowOverride: MOCK_NOW_IST,
        });

        supabaseAdmin.rpc = async () => ({ data: null, error: { message: 'mock disabled' } });
        supabaseAdmin.from = () => {
            const chain = {
                select() { return chain; },
                insert() { return chain; },
                upsert() { return chain; },
                update() { return chain; },
                delete() { return chain; },
                eq() { return chain; },
                in() { return chain; },
                gt() { return chain; },
                gte() { return chain; },
                or() { return chain; },
                order() { return chain; },
                limit() { return chain; },
                single() { return Promise.resolve({ data: null, error: { message: 'mock disabled' } }); },
                maybeSingle() { return Promise.resolve({ data: null, error: { message: 'mock disabled' } }); },
                then(resolve) { return Promise.resolve({ data: null, error: { message: 'mock disabled' } }).then(resolve); },
            };
            return chain;
        };

        Schemas.Dentist.findById = async () => ({
            id: DENTIST_ID,
            user_id: DOC_USER_ID,
            name: 'Dr. Neuro Specialist',
            speciality: 'Neurology',
            availability_status: 'Available',
            is_available: true,
            online_consultation_enabled: true,
            in_person_consultation_enabled: true,
        });
        Schemas.Dentist.findOne = Schemas.Dentist.findById;
        Schemas.Dentist.findByIdAndUpdate = async () => ({ id: DENTIST_ID });
        Schemas.DoctorAvailability.resolveCanonicalIds = async () => ({
            canonicalId: DENTIST_ID,
            dentistTableId: DENTIST_ID,
            userTableId: DOC_USER_ID,
            idsToMatch: [DENTIST_ID, DOC_USER_ID],
        });
        Schemas.DoctorAvailability.findOne = async ({ date }) => memAvailByDate.get(date) || null;
        Schemas.DoctorAvailability.find = async () => Array.from(memAvailByDate.values());
        Schemas.DoctorAvailability.upsert = async (rec) => {
            memAvailByDate.set(rec.date, rec);
            return rec;
        };
        Schemas.DoctorAvailability.deleteOne = async ({ date }) => {
            memAvailByDate.delete(date);
            return { success: true };
        };
        Schemas.Appointment.find = async () => memAppts;
        Schemas.Appointment.create = async (data) => {
            const created = { id: `appt-${memAppts.length + 1}`, ...data };
            memAppts.push(created);
            return created;
        };
    });

    t.afterEach(() => {
        supabaseAdmin.from = orig.supabaseFrom;
        supabaseAdmin.rpc = orig.supabaseRpc;
        Schemas.Dentist.findById = orig.DentistFindById;
        Schemas.Dentist.findOne = orig.DentistFindOne;
        Schemas.Dentist.findByIdAndUpdate = orig.DentistFindByIdAndUpdate;
        Schemas.DoctorAvailability.findOne = orig.AvailFindOne;
        Schemas.DoctorAvailability.find = orig.AvailFind;
        Schemas.DoctorAvailability.upsert = orig.AvailUpsert;
        Schemas.DoctorAvailability.deleteOne = orig.AvailDeleteOne;
        Schemas.DoctorAvailability.resolveCanonicalIds = orig.AvailResolveIds;
        Schemas.Appointment.find = orig.ApptFind;
        Schemas.Appointment.create = orig.ApptCreate;
        resetBookingRulesConfig();
    });

    await t.test('1-4 & 9. Online 10 AM-12 PM (20m + 5m buf) vs In-Person 12 PM-4 PM (30m + 10m buf): Online patients see ONLY Online slots; In-Person patients see ONLY In-Person slots', async () => {
        const { res: saveRes, out: saveOut } = createMockRes();
        await availabilityController.updateDoctorSchedule(
            {
                user: { id: DOC_USER_ID, role: 'DOCTOR' },
                body: {
                    dentistId: DENTIST_ID,
                    workingDays: ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'],
                    startTime: '12:00 PM',
                    endTime: '04:00 PM',
                    hasBreak: false,
                    breaks: [],
                    inPersonEnabled: true,
                    inPersonDurationMinutes: 30,
                    inPersonBufferMinutes: 10,
                    onlineEnabled: true,
                    useSeparateOnlineHours: true,
                    onlineWorkingDays: ['Monday', 'Wednesday', 'Friday'],
                    onlineStartTime: '10:00 AM',
                    onlineEndTime: '12:00 PM',
                    onlineHasBreak: false,
                    onlineBreaks: [],
                    onlineDurationMinutes: 20,
                    onlineBufferMinutes: 5,
                    applyToUpcomingDays: false,
                },
            },
            saveRes
        );

        assert.equal(saveOut.statusCode, 200);
        assert.equal(saveOut.body.success, true);
        assert.equal(saveOut.body.schedule.useSeparateOnlineHours, true);

        // Online patient queries Monday availability
        const { res: onRes, out: onOut } = createMockRes();
        await availabilityController.getDoctorAvailability(
            {
                user: { id: PATIENT_ID, role: 'Patient' },
                query: { dentistId: DENTIST_ID, date: TEST_MON_YMD, consultationType: 'Online' },
            },
            onRes
        );
        assert.equal(onOut.statusCode, 200);
        assert.equal(onOut.body.availability.startTime, '10:00 AM');
        assert.equal(onOut.body.availability.endTime, '12:00 PM');
        assert.deepEqual(onOut.body.availability.availableSlots, [
            '10:00 AM',
            '10:25 AM',
            '10:50 AM',
            '11:15 AM',
            '11:40 AM',
        ]);
        // Never shows In-Person slots
        assert.ok(!onOut.body.availability.availableSlots.includes('12:00 PM'));
        assert.ok(!onOut.body.availability.availableSlots.includes('12:40 PM'));

        // In-Person patient queries Monday availability
        const { res: ipRes, out: ipOut } = createMockRes();
        await availabilityController.getDoctorAvailability(
            {
                user: { id: PATIENT_ID, role: 'Patient' },
                query: { dentistId: DENTIST_ID, date: TEST_MON_YMD, consultationType: 'In-Person' },
            },
            ipRes
        );
        assert.equal(ipOut.statusCode, 200);
        assert.equal(ipOut.body.availability.startTime, '12:00 PM');
        assert.equal(ipOut.body.availability.endTime, '04:00 PM');
        assert.deepEqual(ipOut.body.availability.availableSlots, [
            '12:00 PM',
            '12:40 PM',
            '01:20 PM',
            '02:00 PM',
            '02:40 PM',
            '03:20 PM',
        ]);
        // Never shows Online slots
        assert.ok(!ipOut.body.availability.availableSlots.includes('10:00 AM'));
        assert.ok(!ipOut.body.availability.availableSlots.includes('10:25 AM'));

        // Check Tuesday (In-Person working day, but NOT an Online working day)
        const { res: tueOnRes, out: tueOnOut } = createMockRes();
        await availabilityController.getDoctorAvailability(
            {
                user: { id: PATIENT_ID, role: 'Patient' },
                query: { dentistId: DENTIST_ID, date: TEST_TUE_YMD, consultationType: 'Online' },
            },
            tueOnRes
        );
        assert.equal(tueOnOut.body.availability.isWorkingDay, false);
        assert.deepEqual(tueOnOut.body.availability.availableSlots, []);

        const { res: tueIpRes, out: tueIpOut } = createMockRes();
        await availabilityController.getDoctorAvailability(
            {
                user: { id: PATIENT_ID, role: 'Patient' },
                query: { dentistId: DENTIST_ID, date: TEST_TUE_YMD, consultationType: 'In-Person' },
            },
            tueIpRes
        );
        assert.equal(tueIpOut.body.availability.isWorkingDay, true);
        assert.equal(tueIpOut.body.availability.availableSlots.length, 6);
    });

    await t.test('5, 6, 7 & 10. Different breaks per mode, existing booked slots, blocked dates, and backend rejection of cross-mode / out-of-hours bookings', async () => {
        const schedule = sanitizeSmartSchedule({
            workingDays: ['Monday'],
            startTime: '12:00 PM',
            endTime: '04:00 PM',
            breaks: [{ startTime: '01:20 PM', endTime: '02:00 PM', label: 'In-Person Lunch' }],
            inPersonEnabled: true,
            inPersonDurationMinutes: 30,
            inPersonBufferMinutes: 10,
            onlineEnabled: true,
            useSeparateOnlineHours: true,
            onlineWorkingDays: ['Monday'],
            onlineStartTime: '10:00 AM',
            onlineEndTime: '12:00 PM',
            onlineBreaks: [{ startTime: '10:50 AM', endTime: '11:15 AM', label: 'Online Break' }],
            onlineDurationMinutes: 20,
            onlineBufferMinutes: 5,
            isConfigured: true,
        });

        // Existing booked Online slot at 10:00 AM and In-Person slot at 12:00 PM
        const activeAppointments = [
            {
                id: 'booked-on-1',
                date: TEST_MON_YMD,
                time_slot: '10:00 AM',
                consultation_type: 'Online',
                duration_minutes: 20,
                buffer_minutes: 5,
                status: 'CONFIRMED',
            },
            {
                id: 'booked-ip-1',
                date: TEST_MON_YMD,
                time_slot: '12:00 PM',
                consultation_type: 'In-Person',
                duration_minutes: 30,
                buffer_minutes: 10,
                status: 'CONFIRMED',
            },
        ];

        // Online slots exclude 10:00 AM (booked) and 10:50 AM (Online break), leaving 10:25 AM, 11:15 AM, 11:40 AM
        const onDyn = generateDynamicSlots({
            schedule,
            dateYmd: TEST_MON_YMD,
            consultationType: 'Online',
            activeAppointments,
            now: MOCK_NOW_IST,
        });
        assert.deepEqual(onDyn.availableSlots, ['10:25 AM', '11:15 AM', '11:40 AM']);

        // In-Person slots exclude 12:00 PM (booked) and 01:20 PM (In-Person break), leaving 12:40 PM, 02:00 PM, 02:40 PM, 03:20 PM
        const ipDyn = generateDynamicSlots({
            schedule,
            dateYmd: TEST_MON_YMD,
            consultationType: 'In-Person',
            activeAppointments,
            now: MOCK_NOW_IST,
        });
        assert.deepEqual(ipDyn.availableSlots, ['12:40 PM', '02:00 PM', '02:40 PM', '03:20 PM']);

        // Blocked date excludes all slots for both modes
        const blockedDyn = generateDynamicSlots({
            schedule,
            dateYmd: TEST_MON_YMD,
            consultationType: 'Online',
            explicitDateRecord: { date: TEST_MON_YMD, is_blocked: true, blocked_reason: 'Holiday' },
            now: MOCK_NOW_IST,
        });
        assert.equal(blockedDyn.isBlocked, true);
        assert.deepEqual(blockedDyn.availableSlots, []);

        // Backend validation rejects booking an In-Person slot (12:40 PM) as Online
        const invalidOnlineAtIpTime = validateSlotAgainstSchedule({
            schedule,
            dateYmd: TEST_MON_YMD,
            timeSlot: '12:40 PM',
            consultationType: 'Online',
            activeAppointments,
        });
        assert.equal(invalidOnlineAtIpTime.valid, false);
        assert.equal(invalidOnlineAtIpTime.reason, 'OUTSIDE_WORKING_HOURS');

        // Backend validation rejects booking an Online slot (10:25 AM) as In-Person
        const invalidIpAtOnlineTime = validateSlotAgainstSchedule({
            schedule,
            dateYmd: TEST_MON_YMD,
            timeSlot: '10:25 AM',
            consultationType: 'In-Person',
            activeAppointments,
        });
        assert.equal(invalidIpAtOnlineTime.valid, false);
        assert.equal(invalidIpAtOnlineTime.reason, 'OUTSIDE_WORKING_HOURS');

        // Backend validation rejects booking during Online break (10:50 AM)
        const invalidOnlineBreak = validateSlotAgainstSchedule({
            schedule,
            dateYmd: TEST_MON_YMD,
            timeSlot: '10:50 AM',
            consultationType: 'Online',
            activeAppointments,
        });
        assert.equal(invalidOnlineBreak.valid, false);
        assert.equal(invalidOnlineBreak.reason, 'OVERLAPS_BREAK');
    });

    await t.test('8. Separate schedule disabled preserves shared schedule behavior across enabled modes', async () => {
        const sharedSchedule = sanitizeSmartSchedule({
            workingDays: ['Monday'],
            startTime: '10:00 AM',
            endTime: '12:00 PM',
            breaks: [],
            inPersonEnabled: true,
            inPersonDurationMinutes: 30,
            inPersonBufferMinutes: 10,
            onlineEnabled: true,
            onlineDurationMinutes: 20,
            onlineBufferMinutes: 5,
            useSeparateOnlineHours: false,
            isConfigured: true,
        });

        assert.equal(sharedSchedule.useSeparateOnlineHours, false);
        const onShared = generateDynamicSlots({
            schedule: sharedSchedule,
            dateYmd: TEST_MON_YMD,
            consultationType: 'Online',
            now: MOCK_NOW_IST,
        });
        const ipShared = generateDynamicSlots({
            schedule: sharedSchedule,
            dateYmd: TEST_MON_YMD,
            consultationType: 'In-Person',
            now: MOCK_NOW_IST,
        });
        // Both share 10:00 AM - 12:00 PM window
        assert.equal(onShared.startTime, '10:00 AM');
        assert.equal(onShared.endTime, '12:00 PM');
        assert.equal(ipShared.startTime, '10:00 AM');
        assert.equal(ipShared.endTime, '12:00 PM');
        assert.ok(onShared.availableSlots.includes('10:00 AM'));
        assert.ok(ipShared.availableSlots.includes('10:00 AM'));
    });
});
