const test = require('node:test');
const assert = require('node:assert/strict');

const clinicController = require('../src/controllers/clinicController');
const authController = require('../src/controllers/authController');
const Schemas = require('../src/models/Schemas');

function makeRes() {
    const out = { statusCode: 200, body: null };
    out.status = (code) => {
        out.statusCode = code;
        return out;
    };
    out.json = (payload) => {
        out.body = payload;
        return out;
    };
    return out;
}

test('Doctor full name resolution combines first/middle/last names and avoids Dr. Dr. duplication', () => {
    const { _resolveDoctorFullName, _formatDentistRecord } = clinicController;

    assert.equal(
        _resolveDoctorFullName({
            first_name: 'Venkata',
            middle_name: 'Subramanya',
            last_name: 'Sharma'
        }),
        'Dr. Venkata Subramanya Sharma'
    );

    assert.equal(
        _resolveDoctorFullName({
            name: 'Dr. Dr. Ananya Kumari Reddy'
        }),
        'Dr. Ananya Kumari Reddy'
    );

    const formatted = _formatDentistRecord({
        id: 'doc-1',
        user_id: 'usr-1',
        clinic_id: 'cli-1',
        speciality: 'Cardiology',
        users: [{ id: 'usr-1', name: 'Dr. Rajeshwar Rao Deshmukh', phone: '9876543210', email: 'raj@gshealth.in' }],
        clinics: { id: 'cli-1', clinic_name: 'GS Heart Clinic' }
    });
    assert.equal(formatted.name, 'Dr. Rajeshwar Rao Deshmukh');
    assert.equal(formatted.fullName, 'Dr. Rajeshwar Rao Deshmukh');
    assert.equal(formatted.full_name, 'Dr. Rajeshwar Rao Deshmukh');
});

test('associateClinicDoctor preserves full doctor name even when Dentist.findByIdAndUpdate returns row without joined users', async () => {
    const origClinicFindById = Schemas.Clinic.findById;
    const origDentistFind = Schemas.Dentist.find;
    const origDentistFindById = Schemas.Dentist.findById;
    const origDentistFindByIdAndUpdate = Schemas.Dentist.findByIdAndUpdate;
    const origClinicDoctorGet = Schemas.ClinicDoctor.getDoctorIdsForClinic;
    const origClinicDoctorAssoc = Schemas.ClinicDoctor.associate;

    try {
        const clinic = { id: 'clinic-101', clinic_name: 'Apex Multispecialty Clinic', city: 'Hyderabad' };
        const fullDoctor = {
            id: 'dentist-202',
            user_id: 'user-202',
            clinic_id: null,
            speciality: 'Neurology',
            qualifications: 'MBBS, DM',
            experience_years: 12,
            users: {
                id: 'user-202',
                name: 'Dr. Venkata Subramanya Narayana Sharma',
                phone: '9876500111',
                email: 'venkata@gshealth.in'
            }
        };

        Schemas.Clinic.findById = async (id) => (id === clinic.id ? clinic : null);
        Schemas.Dentist.find = async () => [fullDoctor];
        Schemas.Dentist.findById = async (id) => (id === fullDoctor.id ? fullDoctor : null);
        // Simulate Supabase update returning dentists row WITHOUT joined users
        Schemas.Dentist.findByIdAndUpdate = async (id, patch) => ({
            id,
            user_id: fullDoctor.user_id,
            clinic_id: patch.clinic_id,
            clinic_name: patch.clinic_name,
            speciality: fullDoctor.speciality,
            qualifications: fullDoctor.qualifications,
            experience_years: fullDoctor.experience_years
        });
        Schemas.ClinicDoctor.getDoctorIdsForClinic = async () => [];
        Schemas.ClinicDoctor.associate = async () => ({ duplicate: false });

        const req = {
            params: { clinicId: clinic.id },
            body: { doctorIds: [fullDoctor.id], clinicName: clinic.clinic_name },
            user: { id: 'clinic-owner-1', role: 'Clinic' }
        };
        const res = makeRes();
        await clinicController.associateClinicDoctor(req, res);

        assert.equal(res.statusCode, 200);
        assert.equal(res.body.success, true);
        assert.equal(res.body.doctor.name, 'Dr. Venkata Subramanya Narayana Sharma');
        assert.equal(res.body.doctors[0].fullName, 'Dr. Venkata Subramanya Narayana Sharma');
    } finally {
        Schemas.Clinic.findById = origClinicFindById;
        Schemas.Dentist.find = origDentistFind;
        Schemas.Dentist.findById = origDentistFindById;
        Schemas.Dentist.findByIdAndUpdate = origDentistFindByIdAndUpdate;
        Schemas.ClinicDoctor.getDoctorIdsForClinic = origClinicDoctorGet;
        Schemas.ClinicDoctor.associate = origClinicDoctorAssoc;
    }
});

test('Coordinator rename keeps Sub-Admin DB role backward-compatible and returns Coordinator messages', async () => {
    const origUserCreate = Schemas.User.create;
    const origUserFindByMobile = Schemas.User.findByMobile;
    const origUserFindOne = Schemas.User.findOne;
    const origSetPerms = Schemas.SubAdminPermission.setPermissionsForUser;
    const origAssignDists = Schemas.SubAdminDistrict.assignDistrictsToSubAdmin;
    const origPermLog = Schemas.PermissionChangeHistory.logChange;

    try {
        // Validation error message uses Coordinator terminology
        const badReq = {
            body: { name: '', phone: '9988776655' },
            user: { id: 'main-admin-1', role: 'Admin' }
        };
        const badRes = makeRes();
        await authController.createSubAdmin(badReq, badRes);
        assert.equal(badRes.statusCode, 400);
        assert.match(badRes.body.message, /Coordinator/i);
        assert.doesNotMatch(badRes.body.message, /Sub-Admin/i);

        // Creating a Coordinator preserves internal role 'Sub-Admin' for 100% DB/JWT backward compatibility
        let createdPayload = null;
        Schemas.User.findByMobile = async () => null;
        Schemas.User.findOne = async () => null;
        Schemas.User.create = async (payload) => {
            createdPayload = payload;
            return { id: 'coord-101', ...payload };
        };
        Schemas.SubAdminPermission.setPermissionsForUser = async () => true;
        Schemas.SubAdminDistrict.assignDistrictsToSubAdmin = async () => [{ id: 'dist-hyd', name: 'Hyderabad', state: 'Telangana' }];
        Schemas.PermissionChangeHistory.logChange = async () => true;

        const okReq = {
            body: {
                name: 'Suresh Coordinator',
                phone: '9988776655',
                email: 'suresh.coord@gshealth.in',
                permissions: ['PATIENT_VIEW'],
                districtIds: ['dist-hyd']
            },
            user: { id: 'main-admin-1', role: 'Admin' }
        };
        const okRes = makeRes();
        await authController.createSubAdmin(okReq, okRes);

        assert.equal(okRes.statusCode, 201);
        assert.equal(okRes.body.success, true);
        assert.equal(createdPayload.role, 'Sub-Admin', 'Internal DB role must stay Sub-Admin for backward compatibility');
        assert.match(okRes.body.message, /Coordinator/i);
    } finally {
        Schemas.User.create = origUserCreate;
        Schemas.User.findByMobile = origUserFindByMobile;
        Schemas.User.findOne = origUserFindOne;
        Schemas.SubAdminPermission.setPermissionsForUser = origSetPerms;
        Schemas.SubAdminDistrict.assignDistrictsToSubAdmin = origAssignDists;
        Schemas.PermissionChangeHistory.logChange = origPermLog;
    }
});
