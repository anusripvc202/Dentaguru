const test = require('node:test');
const assert = require('node:assert/strict');
const http = require('http');
const jwt = require('jsonwebtoken');

const app = require('../src/app');
const Schemas = require('../src/models/Schemas');
const calendarCtrl = require('../src/controllers/doctorActivityCalendarController');
const { getJwtSecret } = require('../src/config/secrets');

function buildFixtures() {
    const rawUsers = [
        { id: 'u-doc-1', name: 'Asha Menon', phone: '9000001001', role: 'DOCTOR', status: 'ACTIVE' },
        { id: 'u-doc-2', name: 'Rajiv Verma', phone: '9000001002', role: 'DOCTOR', status: 'ACTIVE' },
        { id: 'u-pat-1', name: 'Kavya Nair', phone: '9111100001', role: 'Patient', status: 'ACTIVE' },
        { id: 'u-pat-2', name: 'Rohan Das', phone: '9111100002', role: 'Patient', status: 'ACTIVE' },
        { id: 'u-pat-3', name: 'Meera Iyer', phone: '9111100003', role: 'Patient', status: 'ACTIVE' },
        { id: 'u-admin-1', name: 'GS HEALTH Admin', phone: '9281030535', role: 'ADMIN', status: 'ACTIVE' },
    ];

    const rawClinics = [
        { id: 'cli-1', clinic_name: 'GS Heart & Dental Center', city: 'Bengaluru', district: 'Bengaluru' },
    ];

    const rawDoctors = [
        { id: 'doc-1', user_id: 'u-doc-1', name: 'Asha Menon', speciality: 'Cardiology', clinic_id: 'cli-1' },
        { id: 'doc-2', user_id: 'u-doc-2', name: 'Rajiv Verma', speciality: 'Dentistry', clinic_id: 'cli-1' },
    ];

    // Date 2026-11-26 has multiple doctors, multiple patients, duplicate appointment row, and 1 patient visiting twice
    const rawAppointments = [
        {
            id: 'appt-1',
            patient_id: 'u-pat-1',
            patient_name: 'Kavya Nair',
            patient_phone: '9111100001',
            dentist_id: 'doc-1',
            clinic_id: 'cli-1',
            date: '2026-11-26',
            time_slot: '09:30 AM',
            consultation_type: 'In-Person',
            status: 'COMPLETED',
            treatment: 'Cardiac Checkup',
        },
        // Intentional duplicate ID row to confirm zero double-counting
        {
            id: 'appt-1',
            patient_id: 'u-pat-1',
            patient_name: 'Kavya Nair',
            patient_phone: '9111100001',
            dentist_id: 'doc-1',
            clinic_id: 'cli-1',
            date: '2026-11-26',
            time_slot: '09:30 AM',
            consultation_type: 'In-Person',
            status: 'COMPLETED',
            treatment: 'Cardiac Checkup',
        },
        // Same patient Kavya Nair completes a second consultation later that day -> unique patientsChecked must NOT double count!
        {
            id: 'appt-2',
            patient_id: 'u-pat-1',
            patient_name: 'Kavya Nair',
            patient_phone: '9111100001',
            dentist_id: 'doc-1',
            clinic_id: 'cli-1',
            date: '2026-11-26',
            time_slot: '11:00 AM',
            consultation_type: 'Online',
            status: 'COMPLETED',
            treatment: 'ECG Review',
        },
        {
            id: 'appt-3',
            patient_id: 'u-pat-2',
            patient_name: 'Rohan Das',
            patient_phone: '9111100002',
            dentist_id: 'doc-1',
            clinic_id: 'cli-1',
            date: '2026-11-26',
            time_slot: '02:00 PM',
            consultation_type: 'Online',
            status: 'PENDING',
            treatment: 'Follow-up',
        },
        {
            id: 'appt-4',
            patient_id: 'u-pat-3',
            patient_name: 'Meera Iyer',
            patient_phone: '9111100003',
            dentist_id: 'doc-2',
            clinic_id: 'cli-1',
            date: '2026-11-26',
            time_slot: '10:30 AM',
            consultation_type: 'In-Person',
            status: 'CANCELLED',
            treatment: 'Dental Scaling',
        },
        {
            id: 'appt-5',
            patient_id: 'u-pat-2',
            patient_name: 'Rohan Das',
            patient_phone: '9111100002',
            dentist_id: 'doc-2',
            clinic_id: 'cli-1',
            date: '2026-11-26',
            time_slot: '04:00 PM',
            consultation_type: 'In-Person',
            status: 'COMPLETED',
            treatment: 'Root Canal',
        },
        // Another day in same month
        {
            id: 'appt-6',
            patient_id: 'u-pat-3',
            patient_name: 'Meera Iyer',
            patient_phone: '9111100003',
            dentist_id: 'doc-2',
            clinic_id: 'cli-1',
            date: '2026-11-20',
            time_slot: '10:00 AM',
            consultation_type: 'Online',
            status: 'PENDING',
            treatment: 'Consultation',
        },
    ];

    const rawReferrals = [
        // Dr. Asha Menon (u-doc-1) refers Rohan Das to Dr. Rajiv Verma (doc-2)
        {
            id: 'ref-1',
            referrer_patient_id: 'u-doc-1',
            referred_patient_id: 'u-pat-2',
            referred_patient_name: 'Rohan Das',
            referred_patient_mobile: '9111100002',
            doctor_id: 'doc-2',
            required_specialist: 'Dentistry',
            referral_date: '2026-11-26T08:30:00+05:30',
            status: 'Accepted',
        },
        // Patient Kavya refers Meera to Dr. Asha Menon
        {
            id: 'ref-2',
            referrer_patient_id: 'u-pat-1',
            referred_patient_id: 'u-pat-3',
            referred_patient_name: 'Meera Iyer',
            referred_patient_mobile: '9111100003',
            doctor_id: 'doc-1',
            required_specialist: 'Cardiology',
            referral_date: '2026-11-26T12:00:00+05:30',
            status: 'Pending',
        },
        // Dr. Rajiv Verma refers Kavya to Dr. Asha Menon (Completed)
        {
            id: 'ref-3',
            referrer_patient_id: 'u-doc-2',
            referred_patient_id: 'u-pat-1',
            referred_patient_name: 'Kavya Nair',
            referred_patient_mobile: '9111100001',
            doctor_id: 'doc-1',
            required_specialist: 'Cardiology',
            referral_date: '2026-11-26T15:00:00+05:30',
            status: 'Completed',
        },
        // Rejected referral on same day
        {
            id: 'ref-4',
            referrer_patient_id: 'u-doc-1',
            referred_patient_name: 'Suresh Kumar',
            referred_patient_mobile: '9111100099',
            doctor_id: 'doc-2',
            required_specialist: 'Dentistry',
            referral_date: '2026-11-26T16:15:00+05:30',
            status: 'Rejected',
        },
    ];

    return { rawUsers, rawClinics, rawDoctors, rawAppointments, rawReferrals };
}

test('1. Date with no appointments or referrals returns clean zeroed summary and empty arrays', () => {
    const fixtures = buildFixtures();
    const res = calendarCtrl._buildDoctorActivityCalendarPayload({
        ...fixtures,
        selectedDate: '2026-11-15',
        selectedMonth: '2026-11',
        todayYmd: '2026-11-26',
    });

    assert.strictEqual(res.success, true);
    assert.strictEqual(res.dailySummary.totalDoctorsActive, 0);
    assert.strictEqual(res.dailySummary.totalAppointments, 0);
    assert.strictEqual(res.dailySummary.totalPatientsChecked, 0);
    assert.strictEqual(res.dailySummary.totalReferrals, 0);
    assert.strictEqual(res.dailySummary.pendingAppointments, 0);
    assert.strictEqual(res.dailySummary.completedAppointments, 0);
    assert.strictEqual(res.dailySummary.cancelledAppointments, 0);
    assert.deepStrictEqual(res.doctorActivity, []);
    assert.deepStrictEqual(res.appointments, []);
    assert.deepStrictEqual(res.referrals, []);
    // Monthly indicators still show activity on other dates in Nov 2026
    assert.strictEqual(res.monthlyCalendar['2026-11-20'].totalAppointments, 1);
    assert.strictEqual(res.monthlyCalendar['2026-11-26'].totalAppointments, 5);
    assert.strictEqual(res.monthlyCalendar['2026-11-26'].totalReferrals, 4);
});

test('2. Multiple doctors & patients aggregate exact deduplicated counts, pending/completed/cancelled stats, and referrals given/received', () => {
    const fixtures = buildFixtures();
    const res = calendarCtrl._buildDoctorActivityCalendarPayload({
        ...fixtures,
        selectedDate: '2026-11-26',
        selectedMonth: '2026-11',
        todayYmd: '2026-11-26',
    });

    assert.strictEqual(res.dailySummary.totalDoctorsActive, 2);
    assert.strictEqual(res.dailySummary.totalAppointments, 5); // duplicate appt-1 removed
    assert.strictEqual(res.dailySummary.totalPatientsChecked, 2); // unique: Kavya (2 completed) + Rohan (1 completed)
    assert.strictEqual(res.dailySummary.totalReferrals, 4);
    assert.strictEqual(res.dailySummary.completedAppointments, 3);
    assert.strictEqual(res.dailySummary.pendingAppointments, 1);
    assert.strictEqual(res.dailySummary.cancelledAppointments, 1);

    const doc1 = res.doctorActivity.find(d => d.doctorId === 'doc-1');
    const doc2 = res.doctorActivity.find(d => d.doctorId === 'doc-2');
    assert.ok(doc1 && doc2);

    assert.strictEqual(doc1.totalAppointments, 3);
    assert.strictEqual(doc1.patientsChecked, 1); // Kavya completed twice -> counted once
    assert.strictEqual(doc1.completedAppointments, 2);
    assert.strictEqual(doc1.pendingAppointments, 1);
    assert.strictEqual(doc1.cancelledAppointments, 0);
    assert.strictEqual(doc1.referralsReceived, 2); // ref-2 + ref-3
    assert.strictEqual(doc1.referralsGiven, 2); // ref-1 + ref-4

    assert.strictEqual(doc2.totalAppointments, 2);
    assert.strictEqual(doc2.patientsChecked, 1); // Rohan
    assert.strictEqual(doc2.completedAppointments, 1);
    assert.strictEqual(doc2.pendingAppointments, 0);
    assert.strictEqual(doc2.cancelledAppointments, 1);
    assert.strictEqual(doc2.referralsReceived, 2); // ref-1 + ref-4
    assert.strictEqual(doc2.referralsGiven, 1); // ref-3

    // Verify appointment referral enrichment
    const rohanAppt = res.appointments.find(a => a.appointmentId === 'appt-3');
    assert.ok(rohanAppt.referralInfo);
    assert.strictEqual(rohanAppt.referralInfo.referralId, 'ref-1');
});

test('3. Filters (doctor, appointment status, referral status, search) and pagination work accurately', () => {
    const fixtures = buildFixtures();

    // Doctor filter = doc-2
    const doc2Res = calendarCtrl._buildDoctorActivityCalendarPayload({
        ...fixtures,
        selectedDate: '2026-11-26',
        selectedMonth: '2026-11',
        filterDoctor: 'doc-2',
    });
    assert.strictEqual(doc2Res.dailySummary.totalAppointments, 2);
    assert.strictEqual(doc2Res.appointments.every(a => a.doctorId === 'doc-2'), true);

    // Appointment status filter = Pending
    const pendingRes = calendarCtrl._buildDoctorActivityCalendarPayload({
        ...fixtures,
        selectedDate: '2026-11-26',
        selectedMonth: '2026-11',
        filterAppointmentStatus: 'Pending',
    });
    assert.strictEqual(pendingRes.dailySummary.totalAppointments, 1);
    assert.strictEqual(pendingRes.dailySummary.pendingAppointments, 1);
    assert.strictEqual(pendingRes.appointments[0].appointmentId, 'appt-3');

    // Referral status filters: Pending, Accepted, Completed, Rejected
    for (const st of ['Pending', 'Accepted', 'Completed', 'Rejected']) {
        const refRes = calendarCtrl._buildDoctorActivityCalendarPayload({
            ...fixtures,
            selectedDate: '2026-11-26',
            selectedMonth: '2026-11',
            filterReferralStatus: st,
        });
        assert.strictEqual(refRes.dailySummary.totalReferrals, 1, `Expected 1 ${st} referral`);
        assert.strictEqual(refRes.referrals[0].referralStatus, st);
    }

    // Search by patient name
    const searchRes = calendarCtrl._buildDoctorActivityCalendarPayload({
        ...fixtures,
        selectedDate: '2026-11-26',
        selectedMonth: '2026-11',
        searchQuery: 'Kavya',
    });
    assert.strictEqual(searchRes.dailySummary.totalAppointments, 2);
    assert.strictEqual(searchRes.appointments.every(a => a.patientName.includes('Kavya')), true);

    // Pagination check (pageSize = 2 on 5 appointments -> 3 pages)
    const page2Res = calendarCtrl._buildDoctorActivityCalendarPayload({
        ...fixtures,
        selectedDate: '2026-11-26',
        selectedMonth: '2026-11',
        page: 2,
        pageSize: 2,
    });
    assert.strictEqual(page2Res.appointmentsPagination.totalItems, 5);
    assert.strictEqual(page2Res.appointmentsPagination.totalPages, 3);
    assert.strictEqual(page2Res.appointmentsPagination.page, 2);
    assert.strictEqual(page2Res.appointments.length, 2);
});

test('4. GET /api/v1/admin/doctor-activity-calendar enforces Admin RBAC and serves live JSON response', async () => {
    const prevEnv = process.env.NODE_ENV;
    const prevJwt = process.env.JWT_SECRET;
    const origApptFind = Schemas.Appointment.find;
    const origRefFind = Schemas.Referral.find;
    const origUserFind = Schemas.User.find;
    const origUserFindById = Schemas.User.findById;
    const origDentistFind = Schemas.Dentist.find;
    const origClinicFind = Schemas.Clinic.find;

    const fixtures = buildFixtures();
    Schemas.Appointment.find = async () => fixtures.rawAppointments;
    Schemas.Referral.find = async () => fixtures.rawReferrals;
    Schemas.User.find = async () => fixtures.rawUsers;
    Schemas.User.findById = async (id) => fixtures.rawUsers.find(u => u.id === id) || null;
    Schemas.Dentist.find = async () => fixtures.rawDoctors;
    Schemas.Clinic.find = async () => fixtures.rawClinics;

    const server = http.createServer(app);
    await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
    const { port } = server.address();

    const apiGet = (urlPath, headers = {}) => new Promise((resolve, reject) => {
        const req = http.request({ hostname: '127.0.0.1', port, path: urlPath, method: 'GET', headers }, (res) => {
            let raw = '';
            res.on('data', (c) => { raw += c; });
            res.on('end', () => resolve({ status: res.statusCode, json: raw ? JSON.parse(raw) : {} }));
        });
        req.on('error', reject);
        req.end();
    });

    try {
        process.env.NODE_ENV = 'staging';
        process.env.JWT_SECRET = 'staging_doctor_activity_calendar_jwt_secret_2026!';

        // 1. Unauthenticated cloud request -> 401
        const unauth = await apiGet('/api/v1/admin/doctor-activity-calendar?date=2026-11-26&month=2026-11');
        assert.strictEqual(unauth.status, 401);

        // 2. Patient JWT -> 403
        const patToken = jwt.sign({ id: 'u-pat-1', role: 'Patient' }, getJwtSecret(), { expiresIn: '15m' });
        const patRes = await apiGet('/api/v1/admin/doctor-activity-calendar?date=2026-11-26&month=2026-11', {
            Authorization: `Bearer ${patToken}`,
        });
        assert.strictEqual(patRes.status, 403);

        // 3. Admin JWT -> 200 with full aggregated payload
        const adminToken = jwt.sign({ id: 'u-admin-1', role: 'ADMIN' }, getJwtSecret(), { expiresIn: '15m' });
        const adminRes = await apiGet('/api/v1/admin/doctor-activity-calendar?date=2026-11-26&month=2026-11', {
            Authorization: `Bearer ${adminToken}`,
        });
        assert.strictEqual(adminRes.status, 200);
        assert.strictEqual(adminRes.json.success, true);
        assert.strictEqual(adminRes.json.dailySummary.totalDoctorsActive, 2);
        assert.strictEqual(adminRes.json.dailySummary.totalAppointments, 5);
        assert.strictEqual(adminRes.json.dailySummary.totalReferrals, 4);
        assert.strictEqual(adminRes.json.doctorActivity.length, 2);
    } finally {
        Schemas.Appointment.find = origApptFind;
        Schemas.Referral.find = origRefFind;
        Schemas.User.find = origUserFind;
        Schemas.User.findById = origUserFindById;
        Schemas.Dentist.find = origDentistFind;
        Schemas.Clinic.find = origClinicFind;
        if (prevEnv !== undefined) process.env.NODE_ENV = prevEnv; else delete process.env.NODE_ENV;
        if (prevJwt !== undefined) process.env.JWT_SECRET = prevJwt; else delete process.env.JWT_SECRET;
        await new Promise((resolve) => server.close(resolve));
    }
});
