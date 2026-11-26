const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');

const Schemas = require('../src/models/Schemas');
const authController = require('../src/controllers/authController');
const clinicController = require('../src/controllers/clinicController');

function createMockRes() {
    const out = { statusCode: 200, body: null };
    return {
        status(code) { out.statusCode = code; return this; },
        json(payload) { out.body = payload; return this; },
        get result() { return out; }
    };
}

test('1. Clinic Registration succeeds independently without doctor details, enforces required fields & OSM coords, and keeps state separate from clinic_address', async () => {
    const origUserFindByMobile = Schemas.User.findByMobile;
    const origUserFindOne = Schemas.User.findOne;
    const origUserCreate = Schemas.User.create;
    const origUserUpdate = Schemas.User.findByIdAndUpdate;
    const origClinicFindOne = Schemas.Clinic.findOne;
    const origClinicCreate = Schemas.Clinic.create;
    const origNotifCreate = Schemas.Notification.create;

    let savedUser = null;
    let savedClinic = null;

    Schemas.User.findByMobile = async () => null;
    Schemas.User.findOne = async () => null;
    Schemas.User.create = async (u) => {
        savedUser = { id: 'usr-clinic-01', refresh_tokens: [], ...u };
        return savedUser;
    };
    Schemas.User.findByIdAndUpdate = async (_id, patch) => {
        savedUser = { ...savedUser, ...patch };
        return savedUser;
    };
    Schemas.Clinic.findOne = async () => null;
    Schemas.Clinic.create = async (c) => {
        savedClinic = { id: 'cli-01', ...c };
        return savedClinic;
    };
    Schemas.Notification.create = async () => ({ id: 'notif-1' });

    try {
        // Missing map coordinates must fail validation (400)
        const badRes = createMockRes();
        await authController.register({
            body: {
                role: 'Clinic',
                phone: '9811100011',
                clinicName: 'Lotus Care Clinic',
                clinicAddress: '45 Linking Road, Bandra West',
                city: 'Mumbai',
                state: 'Maharashtra',
                pincode: '400050',
            }
        }, badRes);
        assert.strictEqual(badRes.result.statusCode, 400);
        assert.strictEqual(badRes.result.body.success, false);

        // Valid Clinic registration without any Doctor Name or Consultation Type succeeds (201)
        const okRes = createMockRes();
        await authController.register({
            body: {
                role: 'Clinic',
                phone: '9811100011',
                clinicName: 'Lotus Care Clinic',
                clinicAddress: '45 Linking Road, Bandra West',
                city: 'Mumbai',
                state: 'Maharashtra',
                pincode: '400050',
                latitude: 19.06069,
                longitude: 72.83624,
            }
        }, okRes);
        assert.strictEqual(okRes.result.statusCode, 201);
        assert.strictEqual(okRes.result.body.success, true);
        assert.strictEqual(savedClinic.clinic_name, 'Lotus Care Clinic');
        assert.strictEqual(savedClinic.clinic_address, '45 Linking Road, Bandra West');
        assert.strictEqual(savedClinic.state, 'Maharashtra');
        assert.strictEqual(savedUser.state, 'Maharashtra'); // NOT merged with clinic_address!
        assert.strictEqual(savedClinic.city, 'Mumbai');
        assert.strictEqual(savedClinic.pincode, '400050');
        assert.strictEqual(savedClinic.latitude, 19.06069);
        assert.strictEqual(savedClinic.longitude, 72.83624);
        assert.strictEqual(okRes.result.body.user.clinicId, 'cli-01');
        assert.strictEqual(okRes.result.body.user.state, 'Maharashtra');
        assert.strictEqual(okRes.result.body.user.latitude, 19.06069);
    } finally {
        Schemas.User.findByMobile = origUserFindByMobile;
        Schemas.User.findOne = origUserFindOne;
        Schemas.User.create = origUserCreate;
        Schemas.User.findByIdAndUpdate = origUserUpdate;
        Schemas.Clinic.findOne = origClinicFindOne;
        Schemas.Clinic.create = origClinicCreate;
        Schemas.Notification.create = origNotifCreate;
    }
});

test('2. Associate multiple existing doctors, prevent duplicate associations, and remove association without deleting doctor account', async () => {
    const origClinicFindById = Schemas.Clinic.findById;
    const origDentistFind = Schemas.Dentist.find;
    const origDentistFindById = Schemas.Dentist.findById;
    const origDentistFindOne = Schemas.Dentist.findOne;
    const origDentistUpdate = Schemas.Dentist.findByIdAndUpdate;
    const origAssoc = Schemas.ClinicDoctor.associate;
    const origGetIds = Schemas.ClinicDoctor.getDoctorIdsForClinic;
    const origRemove = Schemas.ClinicDoctor.remove;

    const clinicRec = {
        id: 'cli-100',
        clinic_name: 'Sunrise Health Hub',
        clinic_address: '12 MG Road',
        city: 'Bengaluru',
        state: 'Karnataka',
        pincode: '560001',
        latitude: 12.9716,
        longitude: 77.5946,
    };

    const doctorsStore = [
        { id: 'doc-A', user_id: 'u-A', clinic_id: null, name: 'Dr. Asha Menon', speciality: 'Cardiology', department: 'Heart Care', phone: '9800011111', availability_status: 'Available' },
        { id: 'doc-B', user_id: 'u-B', clinic_id: null, name: 'Dr. Rajiv Verma', speciality: 'Dentistry', department: 'Oral Care', phone: '9800022222', availability_status: 'Available' },
    ];
    const assocSet = new Set();

    Schemas.Clinic.findById = async (id) => (id === 'cli-100' ? clinicRec : null);
    Schemas.Dentist.find = async (q = {}) => {
        if (q.clinic_id) return doctorsStore.filter(d => d.clinic_id === q.clinic_id);
        return doctorsStore;
    };
    Schemas.Dentist.findById = async (id) => doctorsStore.find(d => d.id === id) || null;
    Schemas.Dentist.findOne = async (q = {}) => {
        if (q.user_id) return doctorsStore.find(d => d.user_id === q.user_id) || null;
        return null;
    };
    Schemas.Dentist.findByIdAndUpdate = async (id, patch) => {
        const d = doctorsStore.find(x => x.id === id);
        if (d) Object.assign(d, patch);
        return d || null;
    };
    Schemas.ClinicDoctor.getDoctorIdsForClinic = async () => Array.from(assocSet);
    Schemas.ClinicDoctor.associate = async (_cid, did) => {
        if (assocSet.has(did)) return { ok: true, duplicate: true };
        assocSet.add(did);
        return { ok: true, duplicate: false };
    };
    Schemas.ClinicDoctor.remove = async (_cid, did) => {
        assocSet.delete(did);
        return true;
    };

    try {
        // Multi-select associate both existing doctors
        const multiRes = createMockRes();
        await clinicController.associateClinicDoctor({
            user: { id: 'admin-1', role: 'ADMIN' },
            params: { clinicId: 'cli-100' },
            body: { doctorIds: ['doc-A', 'doc-B'] }
        }, multiRes);
        assert.strictEqual(multiRes.result.statusCode, 200);
        assert.strictEqual(multiRes.result.body.success, true);
        assert.strictEqual(multiRes.result.body.addedCount, 2);
        assert.strictEqual(doctorsStore[0].clinic_id, 'cli-100');
        assert.strictEqual(doctorsStore[1].clinic_id, 'cli-100');
        assert.strictEqual(doctorsStore.length, 2); // zero duplicate doctor accounts created

        // Duplicate association attempt must return 409 ALREADY_ASSOCIATED
        const dupRes = createMockRes();
        await clinicController.associateClinicDoctor({
            user: { id: 'admin-1', role: 'ADMIN' },
            params: { clinicId: 'cli-100' },
            body: { doctorId: 'doc-A' }
        }, dupRes);
        assert.strictEqual(dupRes.result.statusCode, 409);
        assert.strictEqual(dupRes.result.body.code, 'ALREADY_ASSOCIATED');

        // Remove doctor association preserves doctor account
        const remRes = createMockRes();
        await clinicController.removeDoctorFromClinic({
            user: { id: 'admin-1', role: 'ADMIN' },
            params: { clinicId: 'cli-100', doctorId: 'doc-A' }
        }, remRes);
        assert.strictEqual(remRes.result.statusCode, 200);
        assert.strictEqual(remRes.result.body.success, true);
        assert.strictEqual(doctorsStore[0].clinic_id, null);
        assert.strictEqual(doctorsStore.length, 2); // doctor account preserved!
    } finally {
        Schemas.Clinic.findById = origClinicFindById;
        Schemas.Dentist.find = origDentistFind;
        Schemas.Dentist.findById = origDentistFindById;
        Schemas.Dentist.findOne = origDentistFindOne;
        Schemas.Dentist.findByIdAndUpdate = origDentistUpdate;
        Schemas.ClinicDoctor.associate = origAssoc;
        Schemas.ClinicDoctor.getDoctorIdsForClinic = origGetIds;
        Schemas.ClinicDoctor.remove = origRemove;
    }
});

test('3. Dynamic Clinic search (Name, ID, City, State, Pincode, Address) and Clinic-wise Doctor search & filters work accurately with pagination', async () => {
    const origClinicFind = Schemas.Clinic.find;
    const origClinicFindById = Schemas.Clinic.findById;
    const origDentistFind = Schemas.Dentist.find;
    const origUserFind = Schemas.User.find;
    const origResolveScope = clinicController.resolveClinicRecordAndDoctorIds;
    const origGetIds = Schemas.ClinicDoctor.getDoctorIdsForClinic;

    const clinicsFixture = [
        { id: 'cli-mum-01', clinic_name: 'Lotus Care Clinic', clinic_address: '45 Linking Road', city: 'Mumbai', state: 'Maharashtra', pincode: '400050', latitude: 19.06, longitude: 72.83 },
        { id: 'cli-blr-02', clinic_name: 'Sunrise Health Hub', clinic_address: '12 MG Road', city: 'Bengaluru', state: 'Karnataka', pincode: '560001', latitude: 12.97, longitude: 77.59 },
    ];
    const doctorsFixture = [
        { id: 'doc-1', user_id: 'u-1', clinic_id: 'cli-mum-01', name: 'Dr. Asha Menon', speciality: 'Cardiology', department: 'Heart Care', phone: '9800011111', availability_status: 'Available' },
        { id: 'doc-2', user_id: 'u-2', clinic_id: 'cli-mum-01', name: 'Dr. Vikram Joshi', speciality: 'Dentistry', department: 'Oral Care', phone: '9800022222', availability_status: 'Available' },
        { id: 'doc-3', user_id: 'u-3', clinic_id: 'cli-blr-02', name: 'Dr. Sneha Rao', speciality: 'Pediatrics', department: 'Child Health', phone: '9800033333', availability_status: 'Available' },
    ];

    Schemas.Clinic.find = async () => clinicsFixture;
    Schemas.Clinic.findById = async (id) => clinicsFixture.find(c => c.id === id) || null;
    Schemas.Dentist.find = async (q = {}) => {
        if (q.clinic_id) return doctorsFixture.filter(d => d.clinic_id === q.clinic_id);
        return doctorsFixture;
    };
    Schemas.User.find = async () => [];
    Schemas.ClinicDoctor.getDoctorIdsForClinic = async () => [];
    clinicController.resolveClinicRecordAndDoctorIds = async (cid) => ({
        clinic: clinicsFixture.find(c => c.id === cid) || null,
        clinicId: cid,
        clinicName: clinicsFixture.find(c => c.id === cid)?.clinic_name || '',
        doctorIds: doctorsFixture.filter(d => d.clinic_id === cid).map(d => d.id),
    });

    try {
        // Search clinics by Name, ID, City, State, Pincode, Address
        for (const q of ['lotus', 'cli-mum-01', 'mumbai', 'maharashtra', '400050', 'linking road']) {
            const res = createMockRes();
            await clinicController.getClinics({ query: { search: q, page: 1, pageSize: 10 } }, res);
            assert.strictEqual(res.result.statusCode, 200);
            assert.strictEqual(res.result.body.clinics.length, 1, `Expected 1 clinic for query "${q}"`);
            assert.strictEqual(res.result.body.clinics[0].id, 'cli-mum-01');
            assert.strictEqual(res.result.body.clinics[0].associatedDoctorsCount, 2);
        }

        // Empty search result
        const noneRes = createMockRes();
        await clinicController.getClinics({ query: { search: 'nonexistent-xyz' } }, noneRes);
        assert.strictEqual(noneRes.result.body.clinics.length, 0);

        // Clinic-wise doctors: search by name, mobile, ID, specialization, and combined specialty + department
        const byName = createMockRes();
        await clinicController.getClinicDentists({
            user: { id: 'adm-1', role: 'ADMIN' },
            params: { clinicId: 'cli-mum-01' },
            query: { search: 'vikram' }
        }, byName);
        assert.strictEqual(byName.result.body.doctors.length, 1);
        assert.strictEqual(byName.result.body.doctors[0].id, 'doc-2');

        const byMobile = createMockRes();
        await clinicController.getClinicDentists({
            user: { id: 'adm-1', role: 'ADMIN' },
            params: { clinicId: 'cli-mum-01' },
            query: { search: '9800011111' }
        }, byMobile);
        assert.strictEqual(byMobile.result.body.doctors.length, 1);
        assert.strictEqual(byMobile.result.body.doctors[0].id, 'doc-1');

        const combined = createMockRes();
        await clinicController.getClinicDentists({
            user: { id: 'adm-1', role: 'ADMIN' },
            params: { clinicId: 'cli-mum-01' },
            query: { specialty: 'Cardiology', department: 'Heart Care' }
        }, combined);
        assert.strictEqual(combined.result.body.doctors.length, 1);
        assert.strictEqual(combined.result.body.doctors[0].name, 'Dr. Asha Menon');
    } finally {
        Schemas.Clinic.find = origClinicFind;
        Schemas.Clinic.findById = origClinicFindById;
        Schemas.Dentist.find = origDentistFind;
        Schemas.User.find = origUserFind;
        Schemas.ClinicDoctor.getDoctorIdsForClinic = origGetIds;
        clinicController.resolveClinicRecordAndDoctorIds = origResolveScope;
    }
});

test('4. Migration 06 & Rollback 06 SQL are idempotent and strictly non-destructive', () => {
    const migPath = path.join(__dirname, '..', 'migrations', '06_clinic_management_and_doctors.sql');
    const rbPath = path.join(__dirname, '..', 'migrations', '06_rollback_clinic_management_and_doctors.sql');
    const migSql = fs.readFileSync(migPath, 'utf8');
    const rbSql = fs.readFileSync(rbPath, 'utf8');

    assert.match(migSql, /ADD COLUMN IF NOT EXISTS clinic_address/i);
    assert.match(migSql, /CREATE TABLE IF NOT EXISTS public\.clinic_doctors/i);
    assert.match(migSql, /UNIQUE \(clinic_id, doctor_id\)/i);
    assert.match(migSql, /chk_clinics_valid_coordinates/i);

    const rbExecutable = rbSql
        .split(/\r?\n/)
        .filter((line) => !line.trim().startsWith('--'))
        .join('\n');

    assert.match(rbExecutable, /_rollback_archive_06_clinics_location/i);
    assert.match(rbExecutable, /_rollback_archive_06_clinic_doctors/i);
    assert.doesNotMatch(rbExecutable, /\bDROP\s+COLUMN\b/i);
    assert.doesNotMatch(rbExecutable, /\bDROP\s+TABLE\b/i);
    assert.doesNotMatch(rbExecutable, /\bTRUNCATE\b/i);
    assert.doesNotMatch(rbExecutable, /\bDELETE\s+FROM\b/i);
});
