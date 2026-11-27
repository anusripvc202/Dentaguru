const test = require('node:test');
const assert = require('node:assert/strict');
const Schemas = require('../src/models/Schemas');
const appointmentController = require('../src/controllers/appointmentController');
const { resetBookingRulesConfig } = require('../src/config/bookingRulesConfig');

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

test('Backend Live Hybrid Doctor Calendar (getLiveSchedulingStatus) — Asia/Kolkata Current & Next Patient Logic', async (t) => {
    const origDentistFind = Schemas.Dentist.find;
    const origApptFind = Schemas.Appointment.find;

    t.afterEach(() => {
        Schemas.Dentist.find = origDentistFind;
        Schemas.Appointment.find = origApptFind;
        resetBookingRulesConfig();
    });

    await t.test('1. Consecutive appointments (09:00-09:30, 09:30-10:00, 10:00-10:30) at 08:45, 09:15, 09:30, 09:45, 10:00, and 10:45 IST', async () => {
        Schemas.Dentist.find = async () => [
            {
                id: 'doc-sri',
                user_id: 'user-sri',
                name: 'Dr. sri',
                speciality: 'Dentistry',
                availability_status: 'Available',
                is_available: true,
            },
        ];

        Schemas.Appointment.find = async () => [
            {
                id: 'appt-a',
                dentist_id: 'doc-sri',
                patient_id: 'pat-a',
                patient_name: 'Patient A',
                date: '2026-11-27',
                time_slot: '09:00 AM',
                consultation_type: 'In-Person',
                status: 'CONFIRMED',
            },
            {
                id: 'appt-b',
                dentist_id: 'doc-sri',
                patient_id: 'pat-b',
                patient_name: 'Patient B',
                date: '2026-11-27',
                time_slot: '09:30 AM',
                consultation_type: 'In-Person',
                status: 'CONFIRMED',
            },
            {
                id: 'appt-c',
                dentist_id: 'doc-sri',
                patient_id: 'pat-c',
                patient_name: 'Patient C',
                date: '2026-11-27',
                time_slot: '10:00 AM',
                consultation_type: 'In-Person',
                status: 'CONFIRMED',
            },
        ];

        const queryAtIst = async (istClockHms) => {
            const { res, out } = createMockRes();
            await appointmentController.getLiveSchedulingStatus(
                {
                    query: {
                        now: `2026-11-27T${istClockHms}+05:30`,
                    },
                },
                res
            );
            assert.equal(out.statusCode, 200);
            assert.equal(out.body.success, true);
            return out.body.doctors[0];
        };

        // 08:45 AM (Before first appointment)
        const at0845 = await queryAtIst('08:45:00');
        assert.equal(at0845.currentAppointment, null);
        assert.equal(at0845.nextAppointment?.patientName, 'Patient A');

        // 09:15 AM -> Current: Patient A, Next: Patient B
        const at0915 = await queryAtIst('09:15:00');
        assert.equal(at0915.currentAppointment?.patientName, 'Patient A');
        assert.equal(at0915.currentAppointment?.scheduledStartTime, '09:00 AM');
        assert.equal(at0915.currentAppointment?.scheduledEndTime, '09:30 AM');
        assert.equal(at0915.nextAppointment?.patientName, 'Patient B');

        // 09:30 AM (Exact end of Patient A) -> Current: Patient B, Next: Patient C
        const at0930 = await queryAtIst('09:30:00');
        assert.equal(at0930.currentAppointment?.patientName, 'Patient B');
        assert.equal(at0930.nextAppointment?.patientName, 'Patient C');

        // 09:45 AM -> Current: Patient B, Next: Patient C
        const at0945 = await queryAtIst('09:45:00');
        assert.equal(at0945.currentAppointment?.patientName, 'Patient B');
        assert.equal(at0945.nextAppointment?.patientName, 'Patient C');

        // 10:00 AM -> Current: Patient C, Next: null
        const at1000 = await queryAtIst('10:00:00');
        assert.equal(at1000.currentAppointment?.patientName, 'Patient C');
        assert.equal(at1000.nextAppointment, null);

        // 10:45 AM (After all appointments ended) -> Current: null, Next: null
        const at1045 = await queryAtIst('10:45:00');
        assert.equal(at1045.currentAppointment, null);
        assert.equal(at1045.nextAppointment, null);
        assert.equal(at1045.currentAvailability, 'Available');
    });

    await t.test('2. Excludes Completed, Cancelled, No-Show, Pending, and Duplicate records', async () => {
        Schemas.Dentist.find = async () => [
            {
                id: 'doc-sri',
                name: 'Dr. sri',
                speciality: 'Dentistry',
                availability_status: 'Available',
                is_available: true,
            },
        ];

        Schemas.Appointment.find = async () => [
            {
                id: 'appt-completed',
                dentist_id: 'doc-sri',
                patient_id: 'p1',
                patient_name: 'Completed Patient',
                date: '2026-11-27',
                time_slot: '09:00 AM',
                status: 'COMPLETED',
            },
            {
                id: 'appt-cancelled',
                dentist_id: 'doc-sri',
                patient_id: 'p2',
                patient_name: 'Cancelled Patient',
                date: '2026-11-27',
                time_slot: '09:30 AM',
                status: 'CANCELLED',
            },
            {
                id: 'appt-noshow',
                dentist_id: 'doc-sri',
                patient_id: 'p3',
                patient_name: 'NoShow Patient',
                date: '2026-11-27',
                time_slot: '10:00 AM',
                status: 'NO_SHOW',
            },
            {
                id: 'appt-pending',
                dentist_id: 'doc-sri',
                patient_id: 'p4',
                patient_name: 'Pending Patient',
                date: '2026-11-27',
                time_slot: '10:30 AM',
                status: 'PENDING',
            },
            {
                id: 'appt-confirmed',
                dentist_id: 'doc-sri',
                patient_id: 'p5',
                patient_name: 'Confirmed Next',
                date: '2026-11-27',
                time_slot: '11:00 AM',
                consultation_type: 'Online',
                status: 'CONFIRMED',
            },
        ];

        const { res, out } = createMockRes();
        await appointmentController.getLiveSchedulingStatus(
            { query: { now: '2026-11-27T09:10:00+05:30' } },
            res
        );
        const doc = out.body.doctors[0];
        assert.equal(doc.currentAppointment, null);
        assert.equal(doc.nextAppointment?.patientName, 'Confirmed Next');
        assert.equal(doc.nextAppointment?.scheduledStartTime, '11:00 AM');
        assert.equal(doc.nextAppointment?.scheduledEndTime, '11:20 AM');
    });
});
