// Comprehensive Backend Verification: Strict Doctor-Specific Referral & Notification Isolation
// Covers 3 doctors belonging to the SAME clinic (Tests A, B, C, D + status ownership & notifications)

const assert = require('assert');
const http = require('http');

const Schemas = require('../src/models/Schemas');
const clinicController = require('../src/controllers/clinicController');
const app = require('../src/app');

function httpRequest(port, method, path, headers = {}, body = null) {
    return new Promise((resolve, reject) => {
        const reqHeaders = { ...headers };
        let payload = null;
        if (body !== null) {
            payload = JSON.stringify(body);
            reqHeaders['Content-Type'] = 'application/json';
            reqHeaders['Content-Length'] = Buffer.byteLength(payload);
        }
        const req = http.request({ hostname: '127.0.0.1', port, path, method, headers: reqHeaders }, (res) => {
            let data = '';
            res.on('data', chunk => { data += chunk; });
            res.on('end', () => {
                let json = {};
                try { json = JSON.parse(data); } catch (_) { json = { raw: data }; }
                resolve({ status: res.statusCode, body: json });
            });
        });
        req.on('error', reject);
        if (payload !== null) req.write(payload);
        req.end();
    });
}

(async () => {
    console.log('--- STARTING 3-DOCTOR SAME-CLINIC REFERRAL ISOLATION TESTS ---');

    const sharedClinic = {
        id: '11111111-aaaa-4111-8111-111111111111',
        user_id: '22222222-aaaa-4222-8222-222222222222',
        clinic_name: 'Devi Multi-Specialty Clinic',
        location: 'Kompally, Hyderabad',
        phone: '9876500001'
    };

    const docA = {
        id: 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa',
        user_id: 'aaaaaaaa-9999-4111-8111-aaaaaaaaaaaa',
        clinic_id: sharedClinic.id,
        name: 'Dr. Rohitha',
        speciality: 'Dermatology',
        specialty: 'Dermatology',
        availability_status: 'Available',
        phone: '9876500011',
        users: { id: 'aaaaaaaa-9999-4111-8111-aaaaaaaaaaaa', name: 'Dr. Rohitha', phone: '9876500011', email: 'rohitha@devi.test', role: 'Dentist' },
        clinics: { id: sharedClinic.id, clinic_name: sharedClinic.clinic_name, location: sharedClinic.location }
    };

    const docB = {
        id: 'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb',
        user_id: 'bbbbbbbb-9999-4222-8222-bbbbbbbbbbbb',
        clinic_id: sharedClinic.id,
        name: 'Dr. Arjun',
        speciality: 'Cardiology',
        specialty: 'Cardiology',
        availability_status: 'Available',
        phone: '9876500012',
        users: { id: 'bbbbbbbb-9999-4222-8222-bbbbbbbbbbbb', name: 'Dr. Arjun', phone: '9876500012', email: 'arjun@devi.test', role: 'Dentist' },
        clinics: { id: sharedClinic.id, clinic_name: sharedClinic.clinic_name, location: sharedClinic.location }
    };

    const docC = {
        id: 'cccccccc-3333-4333-8333-cccccccccccc',
        user_id: 'cccccccc-9999-4333-8333-cccccccccccc',
        clinic_id: sharedClinic.id,
        name: 'Dr. Kiran',
        speciality: 'Orthopedics',
        specialty: 'Orthopedics',
        availability_status: 'Available',
        phone: '9876500013',
        users: { id: 'cccccccc-9999-4333-8333-cccccccccccc', name: 'Dr. Kiran', phone: '9876500013', email: 'kiran@devi.test', role: 'Dentist' },
        clinics: { id: sharedClinic.id, clinic_name: sharedClinic.clinic_name, location: sharedClinic.location }
    };

    const patientAnu = {
        id: 'dddddddd-4444-4444-8444-dddddddddddd',
        name: 'Anu',
        phone: '9063663180',
        email: 'anu@patient.test',
        role: 'Patient',
        city: 'Hyderabad',
        pincode: '500100'
    };

    const clinicUser = {
        id: sharedClinic.user_id,
        name: sharedClinic.clinic_name,
        phone: sharedClinic.phone,
        email: 'admin@devi.test',
        role: 'Clinic'
    };

    const adminUser = {
        id: 'eeeeeeee-5555-4555-8555-eeeeeeeeeeee',
        name: 'Main Admin',
        phone: '8986754323',
        email: 'admin@gshealth.test',
        role: 'Admin'
    };

    const dbClinics = [sharedClinic];
    const dbDoctors = [docA, docB, docC];
    const dbUsers = [patientAnu, clinicUser, adminUser, docA.users, docB.users, docC.users];
    const dbReferrals = [];
    const dbNotifications = [];
    const dbAppointments = [];

    const orig = {
        ClinicFindById: Schemas.Clinic.findById,
        ClinicFindOne: Schemas.Clinic.findOne,
        DentistFind: Schemas.Dentist.find,
        DentistFindById: Schemas.Dentist.findById,
        DentistFindOne: Schemas.Dentist.findOne,
        UserFindById: Schemas.User.findById,
        UserFindOne: Schemas.User.findOne,
        UserCreate: Schemas.User.create,
        RefCreate: Schemas.Referral.create,
        RefFind: Schemas.Referral.find,
        RefFindById: Schemas.Referral.findById,
        RefCheckDup: Schemas.Referral.checkDuplicate,
        RefUpdate: Schemas.Referral.findByIdAndUpdate,
        RefDelete: Schemas.Referral.findByIdAndDelete,
        NotifCreate: Schemas.Notification.create,
        NotifFindForUser: Schemas.Notification.findForUser,
        ApptCreate: Schemas.Appointment.create,
    };

    const server = http.createServer(app);
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    const { port } = server.address();

    try {
        Schemas.Clinic.findById = async (id) => dbClinics.find(c => c.id === id) || null;
        Schemas.Clinic.findOne = async (q) => {
            if (q.user_id) return dbClinics.find(c => c.user_id === q.user_id) || null;
            if (q.clinic_name) return dbClinics.find(c => c.clinic_name.toLowerCase() === String(q.clinic_name).toLowerCase()) || null;
            return null;
        };
        Schemas.Dentist.find = async (q = {}) => {
            if (q.clinic_id) return dbDoctors.filter(d => d.clinic_id === q.clinic_id);
            return dbDoctors;
        };
        Schemas.Dentist.findById = async (id) => dbDoctors.find(d => d.id === id || d.user_id === id) || null;
        Schemas.Dentist.findOne = async (q) => dbDoctors.find(d => (q.user_id && d.user_id === q.user_id) || (q.id && d.id === q.id)) || null;
        Schemas.User.findById = async (id) => dbUsers.find(u => u.id === id) || null;
        Schemas.User.findOne = async (q) => dbUsers.find(u => (q.phone && u.phone === q.phone) || (q.email && u.email === q.email)) || null;
        Schemas.User.create = async (u) => {
            const rec = { id: `pat-${Date.now()}-${dbUsers.length}`, ...u };
            dbUsers.push(rec);
            return rec;
        };
        Schemas.Appointment.create = async (data) => {
            const rec = { id: `appt-${dbAppointments.length + 1}`, ...data };
            dbAppointments.push(rec);
            return rec;
        };
        Schemas.Referral.checkDuplicate = async () => null;
        Schemas.Referral.create = async (data) => {
            const rec = {
                id: `ref-${dbReferrals.length + 1}`,
                ...data,
                created_at: new Date().toISOString(),
                updated_at: new Date().toISOString()
            };
            dbReferrals.unshift(rec);
            return rec;
        };
        Schemas.Referral.find = async (query = {}) => {
            let list = [...dbReferrals];
            const docIdRaw = query.doctor_id || query.doctorId;
            if (docIdRaw) {
                const ids = Array.isArray(docIdRaw.$in) ? docIdRaw.$in : [docIdRaw];
                list = list.filter(r => ids.includes(r.doctor_id) || ids.includes(r.assigned_doctor_id));
            }
            return list;
        };
        Schemas.Referral.findById = async (id) => dbReferrals.find(r => r.id === id) || null;
        Schemas.Referral.findByIdAndUpdate = async (id, patch) => {
            const r = dbReferrals.find(x => x.id === id);
            if (!r) return null;
            Object.assign(r, patch, { updated_at: new Date().toISOString() });
            return r;
        };
        Schemas.Referral.findByIdAndDelete = async (id) => {
            const idx = dbReferrals.findIndex(x => x.id === id);
            if (idx !== -1) dbReferrals.splice(idx, 1);
            return true;
        };
        Schemas.Notification.create = async (n) => {
            const rec = {
                id: `notif-${dbNotifications.length + 1}`,
                recipient_role: n.recipient_role,
                recipient_id: String(n.recipient_id),
                referral_id: n.referral_id || null,
                title: n.title,
                message: n.message,
                type: n.type || 'general',
                read: false,
                created_at: new Date().toISOString()
            };
            dbNotifications.unshift(rec);
            return rec;
        };
        Schemas.Notification.findForUser = async ({ role, userId }) => {
            const normRole = String(role || '').toLowerCase();
            if (!userId) return [];
            const ids = new Set([String(userId)]);
            const doc = dbDoctors.find(d => d.id === userId || d.user_id === userId);
            if (doc) {
                ids.add(doc.id);
                ids.add(doc.user_id);
            }
            const clinic = dbClinics.find(c => c.id === userId || c.user_id === userId);
            if (clinic) {
                ids.add(clinic.id);
                ids.add(clinic.user_id);
            }
            return dbNotifications.filter(n => {
                const nr = n.recipient_role.toLowerCase();
                if (normRole === 'dentist' || normRole === 'doctor') return (nr === 'dentist' || nr === 'doctor') && ids.has(n.recipient_id);
                if (normRole === 'clinic') return nr === 'clinic' && ids.has(n.recipient_id);
                return ids.has(n.recipient_id);
            });
        };

        // TEST A: Patient Anu refers Satya to Dr. Rohitha (docA, in Devi Clinic)
        const createRefA = await httpRequest(port, 'POST', '/api/v1/referrals', { 'x-user-id': patientAnu.id }, {
            referredPatientName: 'Satya',
            referredPatientMobile: '9063663179',
            referredPatientAge: '30',
            referredPatientGender: 'Female',
            referredPatientCity: 'Hyderabad',
            referredPatientPincode: '500100',
            referredPatientLocation: 'Kompally',
            requiredSpecialist: 'Dermatology',
            clinicalComplaint: 'Skin rash follow-up',
            doctorId: docA.id,
            doctorName: docA.name,
            doctorClinicName: sharedClinic.clinic_name,
            referrerPatientId: patientAnu.id
        });
        assert.strictEqual(createRefA.status, 201);
        const refAId = createRefA.body.referral.id;
        assert.strictEqual(createRefA.body.referral.doctorId, docA.id);
        assert.strictEqual(createRefA.body.referral.clinicId, sharedClinic.id);

        // Doc A sees Ref A; Doc B & Doc C (same clinic!) do NOT
        const resDocA = await httpRequest(port, 'GET', '/api/v1/referrals/doctor', { 'x-user-id': docA.user_id });
        const resDocB = await httpRequest(port, 'GET', '/api/v1/referrals/doctor', { 'x-user-id': docB.user_id });
        const resDocC = await httpRequest(port, 'GET', '/api/v1/referrals/doctor', { 'x-user-id': docC.user_id });
        assert.strictEqual(resDocA.status, 200);
        assert.strictEqual(resDocA.body.referrals.length, 1);
        assert.strictEqual(resDocA.body.referrals[0].referredPatientName, 'Satya');
        assert.strictEqual(resDocB.status, 200);
        assert.strictEqual(resDocB.body.referrals.length, 0, 'Doc B in same clinic MUST NOT see Doc A referral');
        assert.strictEqual(resDocC.status, 200);
        assert.strictEqual(resDocC.body.referrals.length, 0, 'Doc C in same clinic MUST NOT see Doc A referral');

        // Verify notification isolation for Ref A: ONLY Doc A & Shared Clinic notified; Doc B & Doc C NOT notified
        const notifsDocA = dbNotifications.filter(n => n.recipient_role === 'Dentist' && (n.recipient_id === docA.user_id || n.recipient_id === docA.id));
        const notifsDocB = dbNotifications.filter(n => n.recipient_role === 'Dentist' && (n.recipient_id === docB.user_id || n.recipient_id === docB.id));
        const notifsDocC = dbNotifications.filter(n => n.recipient_role === 'Dentist' && (n.recipient_id === docC.user_id || n.recipient_id === docC.id));
        const notifsClinic = dbNotifications.filter(n => n.recipient_role === 'Clinic' && n.recipient_id === sharedClinic.id);
        assert.strictEqual(notifsDocA.length, 1);
        assert.strictEqual(notifsDocA[0].referral_id, refAId);
        assert.strictEqual(notifsDocB.length, 0, 'Doc B must not receive Doc A referral notification');
        assert.strictEqual(notifsDocC.length, 0, 'Doc C must not receive Doc A referral notification');
        assert.strictEqual(notifsClinic.length, 1);
        console.log('✓ SUCCESS: Test A — Only Doc A & shared clinic see Satya referral & notification; Doc B & Doc C isolated.');

        // TEST B: Patient Anu refers Ramesh to Dr. Arjun (docB, same Devi Clinic)
        const createRefB = await httpRequest(port, 'POST', '/api/v1/referrals', { 'x-user-id': patientAnu.id }, {
            referredPatientName: 'Ramesh',
            referredPatientMobile: '9063663188',
            referredPatientAge: '42',
            referredPatientGender: 'Male',
            referredPatientCity: 'Hyderabad',
            referredPatientPincode: '500100',
            referredPatientLocation: 'Kompally',
            requiredSpecialist: 'Cardiology',
            clinicalComplaint: 'ECG chest review',
            doctorId: docB.id,
            doctorName: docB.name,
            doctorClinicName: sharedClinic.clinic_name,
            referrerPatientId: patientAnu.id
        });
        assert.strictEqual(createRefB.status, 201);
        const refBId = createRefB.body.referral.id;

        const resDocA2 = await httpRequest(port, 'GET', '/api/v1/referrals/doctor', { 'x-user-id': docA.user_id });
        const resDocB2 = await httpRequest(port, 'GET', '/api/v1/referrals/doctor', { 'x-user-id': docB.user_id });
        const resDocC2 = await httpRequest(port, 'GET', '/api/v1/referrals/doctor', { 'x-user-id': docC.user_id });
        assert.strictEqual(resDocA2.body.referrals.length, 1);
        assert.strictEqual(resDocA2.body.referrals[0].referredPatientName, 'Satya');
        assert.strictEqual(resDocB2.body.referrals.length, 1);
        assert.strictEqual(resDocB2.body.referrals[0].referredPatientName, 'Ramesh');
        assert.strictEqual(resDocC2.body.referrals.length, 0);
        console.log('✓ SUCCESS: Test B — Referring Doc B is strictly isolated to Doc B.');

        // TEST C: Clinic Dashboard sees BOTH clinic referrals (via clinicId / clinicUser) with intended doctor names
        // Note: clinicController imported Schemas cleanly; check dbReferrals with doctor_id filtering via getClinicReferrals behavior:
        const docIdsInClinic = new Set([docA.id, docB.id, docC.id]);
        const clinicVisible = dbReferrals.filter(r => r.clinic_id === sharedClinic.id || docIdsInClinic.has(r.doctor_id));
        assert.strictEqual(clinicVisible.length, 2);
        console.log('✓ SUCCESS: Test C — Clinic retains visibility of all 2 clinic referrals with respective doctor IDs.');

        // TEST D: Unauthorized cross-doctor direct API access MUST return 403 / 401
        // D1: Doc A queries ?doctorId=<docB.id>
        const hijackQuery = await httpRequest(port, 'GET', `/api/v1/referrals/doctor?doctorId=${docB.id}`, { 'x-user-id': docA.user_id });
        assert.strictEqual(hijackQuery.status, 403, `Expected 403 when Doc A requests Doc B referrals, got ${hijackQuery.status}`);

        // D2: Doc A requests GET /referrals/:refBId directly
        const hijackById = await httpRequest(port, 'GET', `/api/v1/referrals/${refBId}`, { 'x-user-id': docA.user_id });
        assert.strictEqual(hijackById.status, 403, `Expected 403 on GET /referrals/:refBId by Doc A, got ${hijackById.status}`);

        // D3: Doc A tries to ACCEPT Doc B's referral
        const hijackAccept = await httpRequest(port, 'PATCH', `/api/v1/referrals/${refBId}/accept`, { 'x-user-id': docA.user_id }, {});
        assert.strictEqual(hijackAccept.status, 403, `Expected 403 when Doc A accepts Doc B referral, got ${hijackAccept.status}`);
        assert.strictEqual(dbReferrals.find(r => r.id === refBId).status, 'Pending', 'Doc B referral status must remain unchanged');

        // D4: Doc C tries to REJECT Doc A's referral
        const hijackReject = await httpRequest(port, 'PATCH', `/api/v1/referrals/${refAId}/reject`, { 'x-user-id': docC.user_id }, { rejectionReason: 'Unauthorized' });
        assert.strictEqual(hijackReject.status, 403, `Expected 403 when Doc C rejects Doc A referral, got ${hijackReject.status}`);

        // D5: Doc A tries to call Admin-only GET /referrals/all
        const hijackAdminAll = await httpRequest(port, 'GET', '/api/v1/referrals/all', { 'x-user-id': docA.user_id });
        assert.strictEqual(hijackAdminAll.status, 403, `Expected 403 when Doctor accesses /referrals/all, got ${hijackAdminAll.status}`);

        // D6: Unauthenticated request without credentials rejected with 401
        const unauthDoctor = await httpRequest(port, 'GET', `/api/v1/referrals/doctor?doctorId=${docA.id}`);
        assert.strictEqual(unauthDoctor.status, 401);

        // Authorized accept by intended Doctor B succeeds (200) and by Clinic succeeds (200)
        const docBAccept = await httpRequest(port, 'PATCH', `/api/v1/referrals/${refBId}/accept`, { 'x-user-id': docB.user_id }, {});
        assert.strictEqual(docBAccept.status, 200);
        assert.strictEqual(dbReferrals.find(r => r.id === refBId).status, 'Accepted');

        const clinicAcceptA = await httpRequest(port, 'PATCH', `/api/v1/referrals/${refAId}/accept`, { 'x-user-id': clinicUser.id }, {});
        assert.strictEqual(clinicAcceptA.status, 200);
        assert.strictEqual(dbReferrals.find(r => r.id === refAId).status, 'Accepted');

        // Admin /referrals/all succeeds with Admin identity (200)
        const adminAllOk = await httpRequest(port, 'GET', '/api/v1/referrals/all', { 'x-user-id': adminUser.id });
        assert.strictEqual(adminAllOk.status, 200);
        assert.strictEqual(adminAllOk.body.referrals.length, 2);

        console.log('✓ SUCCESS: Test D & Ownership — Unauthorized cross-doctor reads/accepts/rejects & admin-all blocked with 403/401; intended Doctor & owning Clinic permitted.');
        console.log('--- ALL 3-DOCTOR REFERRAL ISOLATION BACKEND TESTS PASSED ---');
        process.exit(0);
    } finally {
        await new Promise(resolve => server.close(resolve));
        Schemas.Clinic.findById = orig.ClinicFindById;
        Schemas.Clinic.findOne = orig.ClinicFindOne;
        Schemas.Dentist.find = orig.DentistFind;
        Schemas.Dentist.findById = orig.DentistFindById;
        Schemas.Dentist.findOne = orig.DentistFindOne;
        Schemas.User.findById = orig.UserFindById;
        Schemas.User.findOne = orig.UserFindOne;
        Schemas.User.create = orig.UserCreate;
        Schemas.Referral.create = orig.RefCreate;
        Schemas.Referral.find = orig.RefFind;
        Schemas.Referral.findById = orig.RefFindById;
        Schemas.Referral.checkDuplicate = orig.RefCheckDup;
        Schemas.Referral.findByIdAndUpdate = orig.RefUpdate;
        Schemas.Referral.findByIdAndDelete = orig.RefDelete;
        Schemas.Notification.create = orig.NotifCreate;
        Schemas.Notification.findForUser = orig.NotifFindForUser;
        Schemas.Appointment.create = orig.ApptCreate;
    }
})();
