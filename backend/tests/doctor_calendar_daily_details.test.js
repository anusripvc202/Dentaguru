/**
 * GS HEALTH — Doctor Dashboard Calendar & Daily Appointment Details Tests (In-Memory Mocked, Zero DB Writes)
 * Verifies all 8 required scenarios on getDoctorVisitsCalendar:
 * 1. Doctor with no appointments
 * 2. Doctor with appointments on multiple dates
 * 3. Selecting a date with multiple patient visits
 * 4. Accepted, pending, completed, rejected, and rescheduled statuses
 * 5. Online versus in-person consultations (mutually exclusive)
 * 6. Regular appointments versus referred patients (deduplicated referral stats)
 * 7. Monthly calendar navigation & per-date appointment counts
 * 8. Cross-doctor isolation (HTTP 403 + zero leaked records)
 */
const assert = require('assert');
const { describe, it, after } = require('node:test');

// Pure in-memory mocked unit test: never connects to any live Supabase instance
process.env.SUPABASE_URL = process.env.SUPABASE_URL || 'https://mock-local-unit.supabase.co';
process.env.SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY || 'mock-anon-key-unit-test';
process.env.SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY || 'mock-service-role-key-unit-test';

const { supabaseAdmin } = require('../src/config/supabase');
const Schemas = require('../src/models/Schemas');
const appointmentController = require('../src/controllers/appointmentController');

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

describe('Doctor Calendar & Daily Appointment Details (All 8 Scenarios)', () => {
    const origApptFind = Schemas.Appointment.find;
    const origRefFind = Schemas.Referral.find;
    const origUserFind = Schemas.User.find;
    const origDentistFind = Schemas.Dentist.find;
    const origDentistFindById = Schemas.Dentist.findById;
    const origDentistFindOne = Schemas.Dentist.findOne;
    const origRecordFind = Schemas.MedicalRecord.find;
    const origSupabaseFrom = supabaseAdmin.from;

    after(() => {
        Schemas.Appointment.find = origApptFind;
        Schemas.Referral.find = origRefFind;
        Schemas.User.find = origUserFind;
        Schemas.Dentist.find = origDentistFind;
        Schemas.Dentist.findById = origDentistFindById;
        Schemas.Dentist.findOne = origDentistFindOne;
        Schemas.MedicalRecord.find = origRecordFind;
        supabaseAdmin.from = origSupabaseFrom;
    });

    const docNewUserId = '11111111-1111-4111-8111-111111111101';
    const docNewDentistId = '22222222-2222-4222-8222-222222222201';
    const docAUserId = '11111111-1111-4111-8111-111111111102';
    const docADentistId = '22222222-2222-4222-8222-222222222202';
    const docBUserId = '11111111-1111-4111-8111-111111111103';
    const docBDentistId = '22222222-2222-4222-8222-222222222203';

    const mockDentists = [
        { id: docNewDentistId, user_id: docNewUserId, name: 'Dr. Fresh Start', speciality: 'General Medicine', users: { id: docNewUserId, name: 'Dr. Fresh Start' } },
        { id: docADentistId, user_id: docAUserId, name: 'Dr. Anjali Rao', speciality: 'Cardiology', users: { id: docAUserId, name: 'Dr. Anjali Rao' } },
        { id: docBDentistId, user_id: docBUserId, name: 'Dr. Vikram Mehta', speciality: 'Orthopedics', users: { id: docBUserId, name: 'Dr. Vikram Mehta' } },
    ];

    const mockUsers = [
        { id: 'pat-1', name: 'Riya Sharma', phone: '9876543210', email: 'riya@test.com', role: 'Patient', profile_image_url: 'https://example.com/riya.png' },
        { id: 'pat-2', name: 'Arjun Nair', phone: '9876543211', email: 'arjun@test.com', role: 'Patient' },
        { id: 'pat-3', name: 'Meera Iyer', phone: '9876543212', email: 'meera@test.com', role: 'Patient' },
        { id: 'pat-4', name: 'Karan Verma', phone: '9876543213', email: 'karan@test.com', role: 'Patient' },
        { id: 'pat-5', name: 'Sneha Reddy', phone: '9876543214', email: 'sneha@test.com', role: 'Patient' },
        { id: 'pat-6', name: 'Referrer Priya', phone: '9876543215', email: 'priya@test.com', role: 'Patient' },
        { id: 'pat-other', name: 'Other Doc Patient', phone: '9999999999', email: 'other@test.com', role: 'Patient' },
    ];

    const mockAppointments = [
        // 2026-12-10 for Doctor A: 5 appointments covering all statuses + Online/In-Person + Referred vs Regular
        {
            id: 'apt-1',
            patient_id: 'pat-1',
            dentist_id: docADentistId,
            date: '2026-12-10',
            time_slot: '09:00 AM',
            consultation_type: 'Online',
            treatment: 'Online - Chest Pain Follow-up',
            notes: 'Mild chest tightness during walk',
            status: 'COMPLETED',
            patient: mockUsers[0],
            dentist: mockDentists[1],
        },
        {
            id: 'apt-2',
            patient_id: 'pat-2',
            dentist_id: docADentistId,
            date: '2026-12-10',
            time_slot: '10:30 AM',
            consultation_type: 'In-Person',
            treatment: 'In-Person - ECG Evaluation',
            notes: 'Routine ECG checkup',
            status: 'ACCEPTED',
            patient: mockUsers[1],
            dentist: mockDentists[1],
        },
        {
            id: 'apt-3',
            patient_id: 'pat-3',
            dentist_id: docADentistId,
            date: '2026-12-10',
            time_slot: '12:00 PM',
            consultation_type: 'Online',
            treatment: 'Online - BP Review',
            notes: 'High blood pressure readings',
            status: 'PENDING',
            patient: mockUsers[2],
            dentist: mockDentists[1],
        },
        {
            id: 'apt-4',
            patient_id: 'pat-4',
            dentist_id: docADentistId,
            date: '2026-12-10',
            time_slot: '02:00 PM',
            consultation_type: 'In-Person',
            treatment: 'In-Person - Consultation',
            notes: 'General fatigue',
            status: 'REJECTED',
            patient: mockUsers[3],
            dentist: mockDentists[1],
        },
        {
            id: 'apt-5',
            patient_id: 'pat-5',
            dentist_id: docADentistId,
            date: '2026-12-10',
            time_slot: '04:00 PM',
            consultation_type: 'In-Person',
            treatment: 'In-Person - Rescheduled Cardiac Check',
            notes: 'Rescheduled from Dec 9',
            status: 'RESCHEDULED',
            patient: mockUsers[4],
            dentist: mockDentists[1],
        },
        // 2026-12-15 (another date in Dec) & 2027-01-05 (next month)
        {
            id: 'apt-6',
            patient_id: 'pat-2',
            dentist_id: docADentistId,
            date: '2026-12-15',
            time_slot: '11:00 AM',
            consultation_type: 'Online',
            treatment: 'Online - Report Discussion',
            status: 'CONFIRMED',
            patient: mockUsers[1],
            dentist: mockDentists[1],
        },
        {
            id: 'apt-7',
            patient_id: 'pat-1',
            dentist_id: docADentistId,
            date: '2027-01-05',
            time_slot: '10:00 AM',
            consultation_type: 'In-Person',
            treatment: 'In-Person - New Year Checkup',
            status: 'PENDING',
            patient: mockUsers[0],
            dentist: mockDentists[1],
        },
        // Doctor B appointment on 2026-12-10 (must NEVER appear for Doctor A)
        {
            id: 'apt-doc-b',
            patient_id: 'pat-other',
            dentist_id: docBDentistId,
            date: '2026-12-10',
            time_slot: '09:30 AM',
            consultation_type: 'In-Person',
            treatment: 'In-Person - Knee Pain',
            status: 'COMPLETED',
            patient: mockUsers[6],
            dentist: mockDentists[2],
        },
    ];

    const mockReferrals = [
        // Accepted referral for pat-1 (who completed visit on 2026-12-10) + intentional duplicate row to test deduplication
        {
            id: 'ref-1',
            referrer_patient_id: 'pat-6',
            referred_patient_id: 'pat-1',
            referred_patient_name: 'Riya Sharma',
            referred_patient_mobile: '9876543210',
            doctor_id: docADentistId,
            required_specialist: 'Cardiology',
            clinical_complaint: 'Chest tightness',
            status: 'Accepted',
            referral_date: '2026-12-10T06:00:00.000Z',
        },
        {
            id: 'ref-1',
            referrer_patient_id: 'pat-6',
            referred_patient_id: 'pat-1',
            referred_patient_name: 'Riya Sharma',
            referred_patient_mobile: '9876543210',
            doctor_id: docADentistId,
            required_specialist: 'Cardiology',
            clinical_complaint: 'Chest tightness',
            status: 'Accepted',
            referral_date: '2026-12-10T06:00:00.000Z',
        },
        // Pending referral on 2026-12-10 (unbooked)
        {
            id: 'ref-2',
            referrer_patient_id: 'pat-2',
            referred_patient_id: 'pat-unbooked',
            referred_patient_name: 'Unbooked Friend',
            referred_patient_mobile: '9111222333',
            doctor_id: docADentistId,
            required_specialist: 'Cardiology',
            status: 'Pending',
            referral_date: '2026-12-10T08:00:00.000Z',
        },
        // Rejected referral on 2026-12-10
        {
            id: 'ref-3',
            referrer_patient_id: 'pat-3',
            referred_patient_id: 'pat-rej',
            referred_patient_name: 'Rejected Referral',
            referred_patient_mobile: '9111222444',
            doctor_id: docADentistId,
            required_specialist: 'Cardiology',
            status: 'Rejected',
            referral_date: '2026-12-10T09:00:00.000Z',
        },
        // Doctor B's referral (must NEVER appear for Doctor A)
        {
            id: 'ref-doc-b',
            referrer_patient_id: 'pat-other',
            referred_patient_id: 'pat-other',
            referred_patient_name: 'Other Doc Patient',
            referred_patient_mobile: '9999999999',
            doctor_id: docBDentistId,
            required_specialist: 'Orthopedics',
            status: 'Accepted',
            referral_date: '2026-12-10T09:00:00.000Z',
        },
    ];

    function installMocks() {
        Schemas.Appointment.find = async () => mockAppointments;
        Schemas.Referral.find = async () => mockReferrals;
        Schemas.User.find = async () => mockUsers;
        Schemas.Dentist.find = async () => mockDentists;
        Schemas.Dentist.findById = async (id) => mockDentists.find(d => d.id === id) || null;
        Schemas.Dentist.findOne = async (q) => mockDentists.find(d => d.user_id === q.user_id || d.id === q.id) || null;
        Schemas.MedicalRecord.find = async () => [];
        supabaseAdmin.from = (table) => {
            const rows = table === 'dentists' ? mockDentists : (table === 'users' ? mockUsers : []);
            let filtered = [...rows];
            const chain = {
                select() { return chain; },
                eq(col, val) {
                    filtered = filtered.filter(r => String(r[col] || '') === String(val || ''));
                    return chain;
                },
                or(expr) {
                    const m = String(expr || '').match(/id\.eq\.([^,]+),user_id\.eq\.([^,]+)/);
                    if (m) {
                        filtered = filtered.filter(r => String(r.id || '') === m[1] || String(r.user_id || '') === m[2]);
                    }
                    return chain;
                },
                limit(n) { filtered = filtered.slice(0, n); return chain; },
                single() { return Promise.resolve({ data: filtered[0] || null, error: null }); },
                maybeSingle() { return Promise.resolve({ data: filtered[0] || null, error: null }); },
                then(resolve, reject) { return Promise.resolve({ data: filtered, error: null }).then(resolve, reject); },
            };
            return chain;
        };
    }

    it('Scenario 1: Doctor with no appointments receives clean zero stats and empty lists', async () => {
        installMocks();
        const { res, out } = createMockRes();
        await appointmentController.getDoctorVisitsCalendar(
            {
                user: { id: docNewUserId, role: 'Dentist' },
                query: { doctorId: docNewDentistId, date: '2026-12-10', month: '2026-12' },
            },
            res
        );

        assert.strictEqual(out.statusCode, 200);
        assert.strictEqual(out.body.success, true);
        assert.strictEqual(out.body.selectedDateStats.totalAppointments, 0);
        assert.strictEqual(out.body.selectedDateStats.acceptedAppointments, 0);
        assert.strictEqual(out.body.selectedDateStats.pendingAppointments, 0);
        assert.strictEqual(out.body.selectedDateStats.completedConsultations, 0);
        assert.strictEqual(out.body.selectedDateStats.rejectedAppointments, 0);
        assert.strictEqual(out.body.selectedDateStats.rescheduledAppointments, 0);
        assert.strictEqual(out.body.selectedDateStats.onlineConsultations, 0);
        assert.strictEqual(out.body.selectedDateStats.inPersonConsultations, 0);
        assert.strictEqual(out.body.selectedDateStats.patientReferralsReceived, 0);
        assert.strictEqual(out.body.visits.length, 0);
        assert.strictEqual(Object.keys(out.body.monthlyCalendar).length, 0);
    });

    it('Scenarios 2, 3, 4, 5, 6 & 7: Multiple dates/months, all statuses, mutually exclusive Online/In-Person, deduplicated referrals, and filters', async () => {
        installMocks();
        const { res, out } = createMockRes();
        await appointmentController.getDoctorVisitsCalendar(
            {
                user: { id: docAUserId, role: 'Dentist' },
                query: { doctorId: docADentistId, date: '2026-12-10', month: '2026-12' },
            },
            res
        );

        assert.strictEqual(out.statusCode, 200);
        const stats = out.body.selectedDateStats;
        assert.strictEqual(stats.totalAppointments, 5);
        assert.strictEqual(stats.completedConsultations, 1);
        assert.strictEqual(stats.acceptedAppointments, 1);
        assert.strictEqual(stats.pendingAppointments, 1);
        assert.strictEqual(stats.rejectedAppointments, 1);
        assert.strictEqual(stats.rescheduledAppointments, 1);
        assert.strictEqual(stats.onlineConsultations, 2);
        assert.strictEqual(stats.inPersonConsultations, 3);
        assert.strictEqual(stats.onlineConsultations + stats.inPersonConsultations, stats.totalAppointments);

        // Monthly calendar counts across multiple dates in Dec 2026
        assert.strictEqual(out.body.monthlyCalendar['2026-12-10'].totalAppointments, 5);
        assert.strictEqual(out.body.monthlyCalendar['2026-12-15'].totalAppointments, 1);
        assert.strictEqual(out.body.monthlyCalendar['2027-01-05'], undefined);

        // Deduplicated referral counts on 2026-12-10 (ref-1 duplicated in raw data must only count ONCE!)
        assert.strictEqual(stats.patientReferralsReceived, 3);
        assert.strictEqual(stats.acceptedReferrals, 1);
        assert.strictEqual(stats.pendingReferrals, 1);
        assert.strictEqual(stats.rejectedReferrals, 1);
        assert.strictEqual(stats.completedReferredVisits, 1);

        // Visit cards details: profile image, patientId, problemDescription, referral info only on referred patient
        const riyaVisit = out.body.visits.find(v => v.appointmentId === 'apt-1');
        const arjunVisit = out.body.visits.find(v => v.appointmentId === 'apt-2');
        assert.ok(riyaVisit);
        assert.strictEqual(riyaVisit.patientProfileImage, 'https://example.com/riya.png');
        assert.strictEqual(riyaVisit.problemDescription, 'Mild chest tightness during walk');
        assert.strictEqual(riyaVisit.consultationType, 'Online');
        assert.strictEqual(riyaVisit.isReferred, true);
        assert.strictEqual(riyaVisit.referralSource.referringPatientName, 'Referrer Priya');
        assert.strictEqual(riyaVisit.referralSource.referralStatus, 'Accepted');

        assert.ok(arjunVisit);
        assert.strictEqual(arjunVisit.consultationType, 'In-Person');
        assert.strictEqual(arjunVisit.isReferred, false);
        assert.strictEqual(arjunVisit.referralSource, null);

        // Doctor B's appointment must NOT appear
        assert.strictEqual(out.body.visits.some(v => v.appointmentId === 'apt-doc-b'), false);

        // Filter check: referredOnly=true returns only apt-1 while preserving true selectedDateStats
        const { res: resRef, out: outRef } = createMockRes();
        await appointmentController.getDoctorVisitsCalendar(
            {
                user: { id: docAUserId, role: 'Dentist' },
                query: { doctorId: docADentistId, date: '2026-12-10', month: '2026-12', referredOnly: 'true' },
            },
            resRef
        );
        assert.strictEqual(outRef.body.visits.length, 1);
        assert.strictEqual(outRef.body.visits[0].appointmentId, 'apt-1');
        assert.strictEqual(outRef.body.selectedDateStats.totalAppointments, 5);

        // Next month check (2027-01)
        const { res: resJan, out: outJan } = createMockRes();
        await appointmentController.getDoctorVisitsCalendar(
            {
                user: { id: docAUserId, role: 'Dentist' },
                query: { doctorId: docADentistId, date: '2027-01-05', month: '2027-01' },
            },
            resJan
        );
        assert.strictEqual(outJan.body.monthlyCalendar['2027-01-05'].totalAppointments, 1);
        assert.strictEqual(outJan.body.visits.length, 1);
        assert.strictEqual(outJan.body.visits[0].appointmentId, 'apt-7');
    });

    it("Scenario 8: Doctor A cannot access Doctor B's calendar (HTTP 403 Forbidden)", async () => {
        installMocks();
        const { res, out } = createMockRes();
        await appointmentController.getDoctorVisitsCalendar(
            {
                user: { id: docAUserId, role: 'Dentist' },
                query: { doctorId: docBDentistId, date: '2026-12-10', month: '2026-12' },
            },
            res
        );
        assert.strictEqual(out.statusCode, 403);
        assert.strictEqual(out.body.success, false);
    });
});
