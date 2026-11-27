const test = require('node:test');
const assert = require('node:assert/strict');
const jwt = require('jsonwebtoken');

process.env.JWT_SECRET = process.env.JWT_SECRET || 'test_jwt_secret_for_sub_admin_district_123456';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test_refresh_secret_for_sub_admin_district_123456';
process.env.ADMIN_PHONE = process.env.ADMIN_PHONE || '7013245861';

const Schemas = require('../src/models/Schemas');
const authController = require('../src/controllers/authController');
const districtController = require('../src/controllers/districtController');
const problemRequestController = require('../src/controllers/problemRequestController');
const referralController = require('../src/controllers/referralController');
const assignmentController = require('../src/controllers/assignmentController');
const recordController = require('../src/controllers/recordController');
const appointmentController = require('../src/controllers/appointmentController');
const { optionalAuth, requireMainAdmin, requirePermission } = require('../src/middleware/auth');
const { getJwtSecret } = require('../src/config/secrets');

function createMockRes() {
    return {
        statusCode: 200,
        body: null,
        status(code) {
            this.statusCode = code;
            return this;
        },
        json(payload) {
            this.body = payload;
            return this;
        }
    };
}

async function runMiddlewareChain(req, res, middlewares) {
    for (const fn of middlewares) {
        let nextCalled = false;
        await fn(req, res, () => {
            nextCalled = true;
        });
        if (!nextCalled) {
            return res;
        }
    }
    return res;
}

test('Strict Sub-Admin District-Based Patient Access Control (all 8 security & visibility scenarios)', async () => {
    const originals = {
        userFind: Schemas.User.find,
        userFindById: Schemas.User.findById,
        userFindOne: Schemas.User.findOne,
        userFindByIdAndUpdate: Schemas.User.findByIdAndUpdate,
        getDistricts: Schemas.SubAdminDistrict.getDistrictsForSubAdmin,
        assignDistricts: Schemas.SubAdminDistrict.assignDistrictsToSubAdmin,
        reqFind: Schemas.PatientProblemRequest.find,
        reqFindById: Schemas.PatientProblemRequest.findById,
        refFind: Schemas.Referral.find,
        refFindById: Schemas.Referral.findById,
        dentistFind: Schemas.Dentist.find,
        dentistFindById: Schemas.Dentist.findById,
        clinicFind: Schemas.Clinic.find,
        recFind: Schemas.MedicalRecord.find,
        apptFind: Schemas.Appointment.find,
        histGetAll: Schemas.PatientAssignmentHistory.getHistory,
        histByPatient: Schemas.PatientAssignmentHistory.findByPatient,
        histCreate: Schemas.PatientAssignmentHistory.create,
        districtFind: Schemas.District.find,
        districtFindById: Schemas.District.findById,
    };

    // Fixtures:
    // District A = Hyderabad (dist-hyd, Telangana)
    // District B = Vijayawada (dist-vijayawada, Andhra Pradesh)
    const users = [
        {
            id: 'admin-main-1',
            name: 'Main Admin',
            email: 'admin@gshealth.com',
            phone: '7013245861',
            role: 'Admin',
            status: 'ACTIVE',
            permissions: ['*'],
        },
        {
            id: 'subadmin-a',
            name: 'Sub Admin Hyderabad',
            email: 'subadmin.a@gshealth.com',
            phone: '9000000011',
            role: 'Sub-Admin',
            status: 'ACTIVE',
            permissions: [
                'PATIENT_VIEW',
                'PROBLEM_VIEW',
                'PROBLEM_UPDATE',
                'REFERRAL_VIEW',
                'ASSIGNMENT_VIEW',
                'ASSIGNMENT_CREATE',
                'ASSIGNMENT_HISTORY_VIEW',
                'REPORT_VIEW',
                'APPOINTMENT_VIEW',
            ],
        },
        {
            id: 'subadmin-unassigned',
            name: 'Sub Admin No District',
            email: 'subadmin.none@gshealth.com',
            phone: '9000000012',
            role: 'Sub-Admin',
            status: 'ACTIVE',
            permissions: ['PATIENT_VIEW', 'PROBLEM_VIEW', 'REFERRAL_VIEW', 'REPORT_VIEW'],
        },
        // Patient A in District A (Hyderabad)
        {
            id: 'pat-a-hyd',
            name: 'Ananya Hyderabad',
            email: 'ananya@example.com',
            phone: '9111111111',
            role: 'Patient',
            state: 'Telangana',
            district: 'Hyderabad',
            district_id: 'dist-hyd',
            city: 'Hyderabad',
            pincode: '500032',
        },
        // Patient B in District B (Vijayawada) — even though treated by a Hyderabad clinic/doctor, MUST stay hidden from Sub-Admin A!
        {
            id: 'pat-b-vja',
            name: 'Bhaskar Vijayawada',
            email: 'bhaskar@example.com',
            phone: '9222222222',
            role: 'Patient',
            state: 'Andhra Pradesh',
            district: 'Vijayawada',
            district_id: 'dist-vijayawada',
            city: 'Vijayawada',
            pincode: '520001',
        },
        // Patient C with missing / invalid district — MUST NOT be exposed to any Sub-Admin!
        {
            id: 'pat-c-missing',
            name: 'Charan Unverified',
            email: 'charan@example.com',
            phone: '9333333333',
            role: 'Patient',
            state: '',
            district: '',
            district_id: '',
            city: 'Unknown Hamlet',
            pincode: '',
        },
        // Doctor in Hyderabad (used specifically to prove doctor/clinic district does NOT leak Patient B into District A)
        {
            id: 'doc-user-hyd',
            name: 'Dr. Sri Hyderabad',
            email: 'drsri@gshealth.com',
            phone: '9444444444',
            role: 'Dentist',
            city: 'Hyderabad',
            state: 'Telangana',
        },
    ];

    const dentists = [
        {
            id: 'dent-hyd-1',
            user_id: 'doc-user-hyd',
            clinic_id: 'clinic-hyd-1',
            city: 'Hyderabad',
            state: 'Telangana',
            pincode: '500001',
            speciality: 'General Medicine',
            users: { id: 'doc-user-hyd', name: 'Dr. Sri Hyderabad', city: 'Hyderabad', state: 'Telangana' },
            clinics: { id: 'clinic-hyd-1', clinic_name: 'Hyderabad Care Clinic', location: 'Hyderabad, Telangana', city: 'Hyderabad', state: 'Telangana' },
        },
    ];

    const clinics = [
        {
            id: 'clinic-hyd-1',
            clinic_name: 'Hyderabad Care Clinic',
            location: 'Banjara Hills, Hyderabad',
            city: 'Hyderabad',
            state: 'Telangana',
            pincode: '500034',
        },
    ];

    const requests = [
        {
            id: 'req-hyd-1',
            patient_id: 'pat-a-hyd',
            patient_name: 'Ananya Hyderabad',
            patient_phone: '9111111111',
            state: 'Telangana',
            district: 'Hyderabad',
            district_id: 'dist-hyd',
            city: 'Hyderabad',
            pincode: '500032',
            problem_category: 'Dental Pain',
            problem_description: 'Toothache in District A',
            status: 'SUBMITTED',
            suggested_dentist_id: 'dent-hyd-1',
            patient: users.find(u => u.id === 'pat-a-hyd'),
            suggested_dentist: dentists[0],
            created_at: '2026-11-27T09:00:00Z',
        },
        {
            id: 'req-vja-2',
            patient_id: 'pat-b-vja',
            patient_name: 'Bhaskar Vijayawada',
            patient_phone: '9222222222',
            state: 'Andhra Pradesh',
            district: 'Vijayawada',
            district_id: 'dist-vijayawada',
            city: 'Vijayawada',
            pincode: '520001',
            problem_category: 'Checkup',
            problem_description: 'Checkup in District B consulting Hyderabad doctor',
            status: 'SUBMITTED',
            suggested_dentist_id: 'dent-hyd-1', // Doctor is in Hyderabad, patient is in Vijayawada!
            patient: users.find(u => u.id === 'pat-b-vja'),
            suggested_dentist: dentists[0],
            created_at: '2026-11-27T09:30:00Z',
        },
        {
            id: 'req-missing-3',
            patient_id: 'pat-c-missing',
            patient_name: 'Charan Unverified',
            patient_phone: '9333333333',
            city: 'Unknown Hamlet',
            problem_category: 'Consultation',
            problem_description: 'Missing district request',
            status: 'SUBMITTED',
            patient: users.find(u => u.id === 'pat-c-missing'),
            created_at: '2026-11-27T09:45:00Z',
        },
    ];

    const referrals = [
        {
            id: 'ref-hyd-1',
            referrer_id: 'doc-user-hyd',
            doctor_id: 'dent-hyd-1',
            referred_patient_id: 'pat-a-hyd',
            referred_patient_name: 'Ananya Hyderabad',
            referred_patient_mobile: '9111111111',
            referred_patient_state: 'Telangana',
            referred_patient_district: 'Hyderabad',
            patient_district_id: 'dist-hyd',
            referred_patient_city: 'Hyderabad',
            referred_patient_pincode: '500032',
            status: 'Pending',
            clinic_id: 'clinic-hyd-1',
            created_at: '2026-11-27T10:00:00Z',
        },
        {
            id: 'ref-vja-2',
            referrer_id: 'doc-user-hyd', // Referring doctor & clinic are in Hyderabad!
            doctor_id: 'dent-hyd-1',
            referred_patient_id: 'pat-b-vja', // Referred patient is in Vijayawada!
            referred_patient_name: 'Bhaskar Vijayawada',
            referred_patient_mobile: '9222222222',
            referred_patient_state: 'Andhra Pradesh',
            referred_patient_district: 'Vijayawada',
            patient_district_id: 'dist-vijayawada',
            referred_patient_city: 'Vijayawada',
            referred_patient_pincode: '520001',
            status: 'Pending',
            clinic_id: 'clinic-hyd-1',
            created_at: '2026-11-27T10:15:00Z',
        },
        {
            id: 'ref-missing-3',
            referrer_id: 'doc-user-hyd',
            doctor_id: 'dent-hyd-1',
            referred_patient_id: 'pat-c-missing',
            referred_patient_name: 'Charan Unverified',
            referred_patient_mobile: '9333333333',
            referred_patient_city: 'Unknown Hamlet',
            status: 'Pending',
            clinic_id: 'clinic-hyd-1',
            created_at: '2026-11-27T10:30:00Z',
        },
    ];

    const medicalRecords = [
        { id: 'rec-a', patient_id: 'pat-a-hyd', title: 'X-Ray A' },
        { id: 'rec-b', patient_id: 'pat-b-vja', title: 'X-Ray B' },
        { id: 'rec-c', patient_id: 'pat-c-missing', title: 'X-Ray C' },
    ];

    const appointments = [
        {
            id: 'appt-a',
            patient_id: 'pat-a-hyd',
            dentist_id: 'dent-hyd-1',
            clinic_id: 'clinic-hyd-1',
            date: '2026-11-27',
            time_slot: '10:00 AM',
            status: 'CONFIRMED',
            patient: users.find(u => u.id === 'pat-a-hyd'),
            dentist: dentists[0],
            clinic: clinics[0],
        },
        {
            id: 'appt-b',
            patient_id: 'pat-b-vja',
            dentist_id: 'dent-hyd-1', // Doctor & clinic in Hyderabad, patient in Vijayawada!
            clinic_id: 'clinic-hyd-1',
            date: '2026-11-27',
            time_slot: '11:00 AM',
            status: 'CONFIRMED',
            patient: users.find(u => u.id === 'pat-b-vja'),
            dentist: dentists[0],
            clinic: clinics[0],
        },
    ];

    const assignmentHistory = [
        {
            id: 'hist-a',
            patient_id: 'pat-a-hyd',
            doctor_id: 'dent-hyd-1',
            district_id: 'dist-hyd',
            district_name: 'Hyderabad',
            assignment_source: 'SUB_ADMIN_ASSIGNMENT',
            assigned_by_role: 'SUB_ADMIN',
            status: 'ACTIVE',
            created_at: '2026-11-27T09:00:00Z',
        },
        {
            id: 'hist-b',
            patient_id: 'pat-b-vja',
            doctor_id: 'dent-hyd-1',
            district_id: 'dist-vijayawada',
            district_name: 'Vijayawada',
            assignment_source: 'MAIN_ADMIN_ASSIGNMENT',
            assigned_by_role: 'MAIN_ADMIN',
            status: 'ACTIVE',
            created_at: '2026-11-27T09:15:00Z',
        },
    ];

    const subAdminDistrictMap = new Map();

    try {
        Schemas.User.find = async (filter = {}) => {
            if (filter && filter.role) {
                if (typeof filter.role === 'string') {
                    return users.filter(u => String(u.role || '').toLowerCase() === filter.role.toLowerCase());
                }
                if (filter.role && Array.isArray(filter.role.$in)) {
                    const allowedRoles = filter.role.$in.map(r => String(r).toLowerCase());
                    return users.filter(u => allowedRoles.includes(String(u.role || '').toLowerCase()));
                }
            }
            return users;
        };
        Schemas.User.findById = async (id) => users.find(u => u.id === id) || null;
        Schemas.User.findOne = async (filter = {}) => {
            if (filter?.id) return users.find(u => u.id === filter.id) || null;
            if (filter?.email) return users.find(u => String(u.email).toLowerCase() === String(filter.email).toLowerCase()) || null;
            if (filter?.phone) return users.find(u => u.phone === filter.phone) || null;
            return null;
        };
        Schemas.User.findByIdAndUpdate = async (id, patch) => {
            const idx = users.findIndex(u => u.id === id);
            if (idx === -1) return null;
            users[idx] = { ...users[idx], ...patch };
            return users[idx];
        };

        Schemas.District.find = async () => Schemas.DEFAULT_DISTRICTS.map(d => ({ ...d }));
        Schemas.District.findById = async (id) =>
            Schemas.DEFAULT_DISTRICTS.find(d => d.id === id) || null;
        Schemas.SubAdminDistrict.assignDistrictsToSubAdmin = async (subAdminId, districtIds) => {
            const unique = Array.from(new Set(districtIds));
            const rows = [];
            for (const dId of unique) {
                const dist = await Schemas.District.findById(dId);
                if (dist) rows.push(dist);
            }
            subAdminDistrictMap.set(subAdminId, rows);
            return rows;
        };
        Schemas.SubAdminDistrict.getDistrictsForSubAdmin = async (subAdminId) => {
            return subAdminDistrictMap.get(subAdminId) || [];
        };

        Schemas.PatientProblemRequest.find = async () => requests;
        Schemas.PatientProblemRequest.findById = async (id) => requests.find(r => r.id === id) || null;
        Schemas.Referral.find = async () => referrals;
        Schemas.Referral.findById = async (id) => referrals.find(r => r.id === id) || null;
        Schemas.Dentist.find = async () => dentists;
        Schemas.Dentist.findById = async (id) => dentists.find(d => d.id === id) || null;
        Schemas.Clinic.find = async () => clinics;
        Schemas.MedicalRecord.find = async (filter = {}) => {
            if (filter?.patient_id) return medicalRecords.filter(m => m.patient_id === filter.patient_id);
            return medicalRecords;
        };
        Schemas.Appointment.find = async () => appointments;
        Schemas.PatientAssignmentHistory.getHistory = async (filters = {}) => {
            if (filters.district_id) {
                return assignmentHistory.filter(h => h.district_id === filters.district_id);
            }
            return assignmentHistory;
        };
        Schemas.PatientAssignmentHistory.findByPatient = async (patientId) =>
            assignmentHistory.filter(h => h.patient_id === patientId);
        Schemas.PatientAssignmentHistory.create = async (row) => {
            const created = { id: `hist-${assignmentHistory.length + 1}`, ...row };
            assignmentHistory.push(created);
            return created;
        };

        const mainAdminToken = jwt.sign({ id: 'admin-main-1', role: 'Admin' }, getJwtSecret(), { expiresIn: '1h' });
        const subAdminAToken = jwt.sign({ id: 'subadmin-a', role: 'Sub-Admin' }, getJwtSecret(), { expiresIn: '1h' });
        const subAdminNoneToken = jwt.sign({ id: 'subadmin-unassigned', role: 'Sub-Admin' }, getJwtSecret(), { expiresIn: '1h' });

        // 1. Main Admin assigns District A (dist-hyd) to Sub-Admin A
        {
            const req = {
                headers: { authorization: `Bearer ${mainAdminToken}` },
                params: { id: 'subadmin-a' },
                body: { districtIds: ['dist-hyd'] }
            };
            const res = createMockRes();
            await runMiddlewareChain(req, res, [optionalAuth, requireMainAdmin, districtController.assignSubAdminDistricts]);
            assert.equal(res.statusCode, 200);
            assert.equal(res.body?.success, true);
            assert.equal(res.body?.districts?.length, 1);
            assert.equal(res.body?.districts?.[0]?.id, 'dist-hyd');
        }

        // Security check: Sub-Admin CANNOT modify their own district assignment
        {
            const req = {
                headers: { authorization: `Bearer ${subAdminAToken}` },
                params: { id: 'subadmin-a' },
                body: { districtIds: ['dist-vijayawada'] }
            };
            const res = createMockRes();
            await runMiddlewareChain(req, res, [optionalAuth, requireMainAdmin, districtController.assignSubAdminDistricts]);
            assert.equal(res.statusCode, 403);
        }

        // 2 & 8. Sub-Admin A sees ONLY District A patients; missing-district patient is NOT exposed
        {
            const req = {
                headers: { authorization: `Bearer ${subAdminAToken}` },
                query: {}
            };
            const res = createMockRes();
            await runMiddlewareChain(req, res, [optionalAuth, requirePermission('PATIENT_VIEW'), authController.getPatients]);
            assert.equal(res.statusCode, 200);
            assert.equal(res.body?.patients?.length, 1);
            assert.equal(res.body?.patients?.[0]?.id, 'pat-a-hyd');
            assert.equal(res.body?.patients?.[0]?.districtId, 'dist-hyd');
        }

        // Sub-Admin with NO assigned district sees 0 patients (never falls back to global!)
        {
            const req = {
                headers: { authorization: `Bearer ${subAdminNoneToken}` },
                query: {}
            };
            const res = createMockRes();
            await runMiddlewareChain(req, res, [optionalAuth, requirePermission('PATIENT_VIEW'), authController.getPatients]);
            assert.equal(res.statusCode, 200);
            assert.equal(res.body?.patients?.length, 0);
        }

        // 3. Search for District B patient ("Bhaskar" / "Vijayawada") as Sub-Admin A returns 0 results
        {
            const req = {
                headers: { authorization: `Bearer ${subAdminAToken}` },
                query: { search: 'Bhaskar' }
            };
            const res = createMockRes();
            await runMiddlewareChain(req, res, [optionalAuth, requirePermission('PATIENT_VIEW'), authController.getPatients]);
            assert.equal(res.statusCode, 200);
            assert.equal(res.body?.patients?.length, 0);
        }

        // 4. Direct API access to District B patient or missing-district patient returns 403 Forbidden
        {
            const reqB = {
                headers: { authorization: `Bearer ${subAdminAToken}` },
                params: { id: 'pat-b-vja' }
            };
            const resB = createMockRes();
            await runMiddlewareChain(reqB, resB, [optionalAuth, requirePermission('PATIENT_VIEW'), authController.getPatientById]);
            assert.equal(resB.statusCode, 403);
            assert.equal(resB.body?.code, 'DISTRICT_ACCESS_DENIED');

            const reqMissing = {
                headers: { authorization: `Bearer ${subAdminAToken}` },
                params: { id: 'pat-c-missing' }
            };
            const resMissing = createMockRes();
            await runMiddlewareChain(reqMissing, resMissing, [optionalAuth, requirePermission('PATIENT_VIEW'), authController.getPatientById]);
            assert.equal(resMissing.statusCode, 403);

            const reqAllowed = {
                headers: { authorization: `Bearer ${subAdminAToken}` },
                params: { id: 'pat-a-hyd' }
            };
            const resAllowed = createMockRes();
            await runMiddlewareChain(reqAllowed, resAllowed, [optionalAuth, requirePermission('PATIENT_VIEW'), authController.getPatientById]);
            assert.equal(resAllowed.statusCode, 200);
            assert.equal(resAllowed.body?.patient?.id, 'pat-a-hyd');
        }

        // 5. Patient requests, referrals, appointments, medical records & assignment endpoints respect patient's district (never clinic/doctor district)
        {
            // Requests
            const req = { headers: { authorization: `Bearer ${subAdminAToken}` }, query: {} };
            const res = createMockRes();
            await runMiddlewareChain(req, res, [optionalAuth, requirePermission('PROBLEM_VIEW'), problemRequestController.getAdminProblemRequests]);
            assert.equal(res.statusCode, 200);
            assert.equal(res.body?.requests?.length, 1);
            assert.equal(res.body?.requests?.[0]?.id, 'req-hyd-1');

            // Referrals (even though doctor & clinic are in Hyderabad, District B patient referral is excluded!)
            const refReq = { headers: { authorization: `Bearer ${subAdminAToken}` }, query: {} };
            const refRes = createMockRes();
            await runMiddlewareChain(refReq, refRes, [optionalAuth, requirePermission('REFERRAL_VIEW'), referralController.getAllReferralsAdmin]);
            assert.equal(refRes.statusCode, 200);
            assert.equal(refRes.body?.referrals?.length, 1);
            assert.equal(refRes.body?.referrals?.[0]?.id, 'ref-hyd-1');

            // Direct referral access to District B referral returns 403
            const refDirectReq = { headers: { authorization: `Bearer ${subAdminAToken}` }, params: { referralId: 'ref-vja-2' } };
            const refDirectRes = createMockRes();
            await runMiddlewareChain(refDirectReq, refDirectRes, [optionalAuth, requirePermission('REFERRAL_VIEW'), referralController.getReferralById]);
            assert.equal(refDirectRes.statusCode, 403);

            // Medical records of District B patient returns 403
            const recReq = { headers: { authorization: `Bearer ${subAdminAToken}` }, query: { patientId: 'pat-b-vja' } };
            const recRes = createMockRes();
            await runMiddlewareChain(recReq, recRes, [optionalAuth, recordController.getPatientRecords]);
            assert.equal(recRes.statusCode, 403);

            // Direct patient assignment timeline for District B patient returns 403
            const tlReq = { headers: { authorization: `Bearer ${subAdminAToken}` }, params: { patientId: 'pat-b-vja' } };
            const tlRes = createMockRes();
            await runMiddlewareChain(tlReq, tlRes, [optionalAuth, requirePermission('ASSIGNMENT_VIEW'), assignmentController.getPatientTimeline]);
            assert.equal(tlRes.statusCode, 403);

            // Appointments: only District A patient's appointment returned (not District B patient consulting Hyderabad doctor)
            const apptReq = { headers: { authorization: `Bearer ${subAdminAToken}` }, query: {} };
            const apptRes = createMockRes();
            await runMiddlewareChain(apptReq, apptRes, [optionalAuth, requirePermission('APPOINTMENT_VIEW'), appointmentController.getAppointments]);
            assert.equal(apptRes.statusCode, 200);
            assert.equal(apptRes.body?.appointments?.length, 1);
            assert.equal(apptRes.body?.appointments?.[0]?.id, 'appt-a');
        }

        // 6. Dashboard counts / assignment statistics / referral analytics / district reports show ONLY District A records
        {
            const statsReq = { headers: { authorization: `Bearer ${subAdminAToken}` }, query: {} };
            const statsRes = createMockRes();
            await runMiddlewareChain(statsReq, statsRes, [optionalAuth, requirePermission('REPORT_VIEW'), assignmentController.getAssignmentStatistics]);
            assert.equal(statsRes.statusCode, 200);
            assert.equal(statsRes.body?.statistics?.totalAssignments, 1);
            assert.equal(statsRes.body?.statistics?.totalPatients, 1);

            const repReq = { headers: { authorization: `Bearer ${subAdminAToken}` }, query: {} };
            const repRes = createMockRes();
            await runMiddlewareChain(repReq, repRes, [optionalAuth, requirePermission('REPORT_VIEW'), assignmentController.getDistrictReports]);
            assert.equal(repRes.statusCode, 200);
            assert.equal(repRes.body?.reports?.length, 1);
            assert.equal(repRes.body?.reports?.[0]?.district_id, 'dist-hyd');
            assert.equal(repRes.body?.reports?.[0]?.total_patients, 1);

            const refAnalyticsReq = { headers: { authorization: `Bearer ${subAdminAToken}` }, query: {} };
            const refAnalyticsRes = createMockRes();
            await runMiddlewareChain(refAnalyticsReq, refAnalyticsRes, [optionalAuth, requirePermission('REFERRAL_VIEW'), referralController.getAdminReferralAnalytics]);
            assert.equal(refAnalyticsRes.statusCode, 200);
            assert.equal(refAnalyticsRes.body?.analytics?.totalReferrals, 1);
        }

        // 7. Main Admin retains access to ALL districts AND can filter by State and District
        {
            const allReq = { headers: { authorization: `Bearer ${mainAdminToken}` }, query: {} };
            const allRes = createMockRes();
            await runMiddlewareChain(allReq, allRes, [optionalAuth, requirePermission('PATIENT_VIEW'), authController.getPatients]);
            assert.equal(allRes.statusCode, 200);
            assert.equal(allRes.body?.patients?.length, 3);

            const apReq = { headers: { authorization: `Bearer ${mainAdminToken}` }, query: { state: 'Andhra Pradesh' } };
            const apRes = createMockRes();
            await runMiddlewareChain(apReq, apRes, [optionalAuth, requirePermission('PATIENT_VIEW'), authController.getPatients]);
            assert.equal(apRes.statusCode, 200);
            assert.equal(apRes.body?.patients?.length, 1);
            assert.equal(apRes.body?.patients?.[0]?.id, 'pat-b-vja');

            const distReq = { headers: { authorization: `Bearer ${mainAdminToken}` }, query: { districtId: 'dist-hyd' } };
            const distRes = createMockRes();
            await runMiddlewareChain(distReq, distRes, [optionalAuth, requirePermission('PATIENT_VIEW'), authController.getPatients]);
            assert.equal(distRes.statusCode, 200);
            assert.equal(distRes.body?.patients?.length, 1);
            assert.equal(distRes.body?.patients?.[0]?.id, 'pat-a-hyd');
        }
    } finally {
        Schemas.User.find = originals.userFind;
        Schemas.User.findById = originals.userFindById;
        Schemas.User.findOne = originals.userFindOne;
        Schemas.User.findByIdAndUpdate = originals.userFindByIdAndUpdate;
        Schemas.SubAdminDistrict.getDistrictsForSubAdmin = originals.getDistricts;
        Schemas.SubAdminDistrict.assignDistrictsToSubAdmin = originals.assignDistricts;
        Schemas.PatientProblemRequest.find = originals.reqFind;
        Schemas.PatientProblemRequest.findById = originals.reqFindById;
        Schemas.Referral.find = originals.refFind;
        Schemas.Referral.findById = originals.refFindById;
        Schemas.Dentist.find = originals.dentistFind;
        Schemas.Dentist.findById = originals.dentistFindById;
        Schemas.Clinic.find = originals.clinicFind;
        Schemas.MedicalRecord.find = originals.recFind;
        Schemas.Appointment.find = originals.apptFind;
        Schemas.PatientAssignmentHistory.getHistory = originals.histGetAll;
        Schemas.PatientAssignmentHistory.findByPatient = originals.histByPatient;
        Schemas.PatientAssignmentHistory.create = originals.histCreate;
        Schemas.District.find = originals.districtFind;
        Schemas.District.findById = originals.districtFindById;
    }
});
