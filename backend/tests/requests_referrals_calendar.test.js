require('dotenv').config();
const test = require('node:test');
const assert = require('node:assert/strict');
const Schemas = require('../src/models/Schemas');
const requestsReferralsCalendar = require('../src/controllers/requestsReferralsCalendarController');

function createMockRes() {
    const res = {
        statusCode: 200,
        body: null,
        status(code) {
            this.statusCode = code;
            return this;
        },
        json(payload) {
            this.body = payload;
            return this;
        },
    };
    return res;
}

test('1. getRequestsReferralsCalendar enforces Admin RBAC (rejects unauthenticated and non-admin callers)', async () => {
    const origUserFindById = Schemas.User.findById;
    try {
        // Unauthenticated -> 401
        const unauthRes = createMockRes();
        await requestsReferralsCalendar.getRequestsReferralsCalendar({ query: {} }, unauthRes);
        assert.equal(unauthRes.statusCode, 401);
        assert.equal(unauthRes.body.success, false);

        // Patient caller -> 403
        Schemas.User.findById = async () => ({ id: 'pat-1', role: 'Patient', status: 'ACTIVE' });
        const patRes = createMockRes();
        await requestsReferralsCalendar.getRequestsReferralsCalendar(
            { user: { id: 'pat-1', role: 'Patient' }, query: {} },
            patRes
        );
        assert.equal(patRes.statusCode, 403);
        assert.equal(patRes.body.success, false);
    } finally {
        Schemas.User.findById = origUserFindById;
    }
});

test('2. getRequestsReferralsCalendar aggregates monthly & daily Requests and Referrals strictly by creation date in Asia/Kolkata without duplicates', async () => {
    const origUserFindById = Schemas.User.findById;
    const origUserFind = Schemas.User.find;
    const origDentistFind = Schemas.Dentist.find;
    const origClinicFind = Schemas.Clinic.find;
    const origReqFind = Schemas.PatientProblemRequest.find;
    const origRefFind = Schemas.Referral.find;

    Schemas.User.findById = async (id) => {
        if (id === 'admin-1') return { id: 'admin-1', role: 'ADMIN', status: 'ACTIVE' };
        return null;
    };
    Schemas.User.find = async () => [
        { id: 'pat-1', name: 'Aarav Kulkarni', phone: '9800011111' },
        { id: 'pat-2', name: 'Meera Nair', phone: '9800022222' },
    ];
    Schemas.Dentist.find = async () => [
        { id: 'doc-1', user_id: 'u-doc-1', name: 'Dr. Asha Menon', speciality: 'Cardiology' },
        { id: 'doc-2', user_id: 'u-doc-2', name: 'Dr. Vikram Joshi', speciality: 'Endodontics' },
    ];
    Schemas.Clinic.find = async () => [];

    // Include a duplicate id to verify deduplication, plus an UTC timestamp near midnight that maps to 2026-11-26 in IST (+05:30)
    Schemas.PatientProblemRequest.find = async () => [
        {
            id: 'req-101',
            patient_id: 'pat-1',
            patient_name: 'Aarav Kulkarni',
            patient_phone: '9800011111',
            problem_category: 'Toothache & Cold Sensitivity',
            problem_description: 'Severe molar pain',
            status: 'PENDING_ADMIN_REVIEW',
            created_at: '2026-11-26T04:30:00.000Z', // 10:00 AM IST on 2026-11-26
        },
        {
            id: 'req-101', // duplicate row must be deduplicated
            patient_id: 'pat-1',
            patient_name: 'Aarav Kulkarni',
            problem_category: 'Toothache & Cold Sensitivity',
            status: 'PENDING_ADMIN_REVIEW',
            created_at: '2026-11-26T04:30:00.000Z',
        },
        {
            id: 'req-102',
            patient_id: 'pat-2',
            patient_name: 'Meera Nair',
            patient_phone: '9800022222',
            problem_category: 'Root Canal Triage',
            suggested_dentist_id: 'doc-2',
            status: 'DENTIST_ASSIGNED',
            created_at: '2026-11-26T19:30:00.000Z', // 01:00 AM IST on 2026-11-27!
        },
        {
            id: 'req-103',
            patient_id: 'pat-2',
            patient_name: 'Meera Nair',
            problem_category: 'Orthodontic Consult',
            suggested_dentist_id: 'doc-1',
            status: 'REJECTED',
            created_at: '2026-11-26T09:00:00.000Z', // 02:30 PM IST on 2026-11-26
        },
    ];

    Schemas.Referral.find = async () => [
        {
            id: 'ref-201',
            referrer_patient_id: 'doc-1',
            referrer_patient_name: 'Dr. Asha Menon',
            referred_patient_name: 'Aarav Kulkarni',
            referred_patient_mobile: '9800011111',
            doctor_id: 'doc-2',
            doctor_name: 'Dr. Vikram Joshi',
            required_specialist: 'Endodontics',
            status: 'Pending',
            referral_date: '2026-11-26T06:00:00.000Z',
        },
        {
            id: 'ref-202',
            referrer_patient_id: 'doc-2',
            referrer_patient_name: 'Dr. Vikram Joshi',
            referred_patient_name: 'Meera Nair',
            referred_patient_mobile: '9800022222',
            doctor_id: 'doc-1',
            doctor_name: 'Dr. Asha Menon',
            required_specialist: 'Cardiology',
            status: 'Accepted',
            referral_date: '2026-11-26T07:30:00.000Z',
        },
        {
            id: 'ref-203',
            referrer_patient_id: 'doc-1',
            referrer_patient_name: 'Dr. Asha Menon',
            referred_patient_name: 'Rohan Desai',
            referred_patient_mobile: '9800033333',
            doctor_id: 'doc-2',
            doctor_name: 'Dr. Vikram Joshi',
            required_specialist: 'Endodontics',
            status: 'Completed',
            referral_date: '2026-11-26T08:15:00.000Z',
        },
    ];

    try {
        const res = createMockRes();
        await requestsReferralsCalendar.getRequestsReferralsCalendar(
            {
                user: { id: 'admin-1', role: 'ADMIN' },
                query: { date: '2026-11-26', month: '2026-11' },
            },
            res
        );

        assert.equal(res.statusCode, 200);
        assert.equal(res.body.success, true);
        assert.equal(res.body.selectedDate, '2026-11-26');
        assert.equal(res.body.monthlyCalendar.length, 30);

        // Verify 2026-11-26 cell counts (req-101 Pending + req-103 Rejected = 2 requests; req-102 is 2026-11-27 in IST!)
        const day26 = res.body.monthlyCalendar.find((d) => d.date === '2026-11-26');
        const day27 = res.body.monthlyCalendar.find((d) => d.date === '2026-11-27');
        assert.equal(day26.requestsCount, 2);
        assert.equal(day26.referralsCount, 3);
        assert.equal(day27.requestsCount, 1);

        // Verify 8 dailySummary cards for 2026-11-26
        assert.equal(res.body.dailySummary.totalRequests, 2);
        assert.equal(res.body.dailySummary.pendingRequests, 1);
        assert.equal(res.body.dailySummary.approvedRequests, 0);
        assert.equal(res.body.dailySummary.rejectedRequests, 1);
        assert.equal(res.body.dailySummary.totalReferrals, 3);
        assert.equal(res.body.dailySummary.pendingReferrals, 1);
        assert.equal(res.body.dailySummary.acceptedReferrals, 1);
        assert.equal(res.body.dailySummary.completedReferrals, 1);

        // Verify combined search + status filters
        const filteredRes = createMockRes();
        await requestsReferralsCalendar.getRequestsReferralsCalendar(
            {
                user: { id: 'admin-1', role: 'ADMIN' },
                query: {
                    date: '2026-11-26',
                    month: '2026-11',
                    search: 'aarav',
                    requestStatus: 'Pending',
                    referralStatus: 'Pending',
                },
            },
            filteredRes
        );
        assert.equal(filteredRes.body.requests.length, 1);
        assert.equal(filteredRes.body.requests[0].requestId, 'req-101');
        assert.equal(filteredRes.body.referrals.length, 1);
        assert.equal(filteredRes.body.referrals[0].referralId, 'ref-201');
    } finally {
        Schemas.User.findById = origUserFindById;
        Schemas.User.find = origUserFind;
        Schemas.Dentist.find = origDentistFind;
        Schemas.Clinic.find = origClinicFind;
        Schemas.PatientProblemRequest.find = origReqFind;
        Schemas.Referral.find = origRefFind;
    }
});
