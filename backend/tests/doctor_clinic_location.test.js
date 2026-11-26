const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

// Provide isolated local-only test env values so supabase.js initializes in offline unit tests
process.env.NODE_ENV = 'test';
process.env.SUPABASE_URL = process.env.SUPABASE_URL || 'https://offline-unit-test.supabase.co';
process.env.SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY || 'test-anon-key';
process.env.SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY || 'test-service-role-key';
process.env.JWT_SECRET = process.env.JWT_SECRET || 'test-jwt-secret-key';

const {
    validateCoordinates,
    isValidIndianPincode,
    validateDoctorRegistrationClinicFields,
    parseUserDeviceMeta
} = require('../src/utils/doctorClinicLocationHelper');

test('1. Coordinate validation enforces lat/lng ranges, pairing, and explicit clearing', () => {
    const omitted = validateCoordinates(undefined, undefined, false);
    assert.equal(omitted.ok, true);
    assert.equal(omitted.hasUpdate, false);

    const cleared = validateCoordinates(undefined, undefined, true);
    assert.equal(cleared.ok, true);
    assert.equal(cleared.hasUpdate, true);
    assert.equal(cleared.latitude, null);
    assert.equal(cleared.longitude, null);

    const valid = validateCoordinates(19.07609, 72.877426, false);
    assert.equal(valid.ok, true);
    assert.equal(valid.hasUpdate, true);
    assert.equal(valid.latitude, 19.07609);
    assert.equal(valid.longitude, 72.877426);

    const zeroEquator = validateCoordinates(0, 0, false);
    assert.equal(zeroEquator.ok, true);
    assert.equal(zeroEquator.latitude, 0);
    assert.equal(zeroEquator.longitude, 0);

    assert.equal(validateCoordinates(95.1, 72.8, false).ok, false);
    assert.equal(validateCoordinates(19.0, 181.2, false).ok, false);
    assert.equal(validateCoordinates(19.076, null, false).ok, false);
});

test('2. Doctor clinic registration validator requires name, address, city, state, 6-digit pincode, and map coordinates', () => {
    assert.equal(isValidIndianPincode('400050'), true);
    assert.equal(isValidIndianPincode('40005'), false);
    assert.equal(isValidIndianPincode('40005A'), false);

    assert.equal(
        validateDoctorRegistrationClinicFields({
            clinicName: '',
            clinicAddress: 'Hill Road',
            city: 'Mumbai',
            state: 'Maharashtra',
            pincode: '400050',
            latitude: 19.05444,
            longitude: 72.83002
        }).ok,
        false
    );

    assert.equal(
        validateDoctorRegistrationClinicFields({
            clinicName: 'Smile Care',
            clinicAddress: 'Hill Road',
            city: 'Mumbai',
            state: '',
            pincode: '400050',
            latitude: 19.05444,
            longitude: 72.83002
        }).ok,
        false
    );

    assert.equal(
        validateDoctorRegistrationClinicFields({
            clinicName: 'Smile Care',
            clinicAddress: 'Hill Road',
            city: 'Mumbai',
            state: 'Maharashtra',
            pincode: '40005',
            latitude: 19.05444,
            longitude: 72.83002
        }).ok,
        false
    );

    const missingMap = validateDoctorRegistrationClinicFields({
        clinicName: 'Smile Care',
        clinicAddress: 'Hill Road',
        city: 'Mumbai',
        state: 'Maharashtra',
        pincode: '400050',
        latitude: null,
        longitude: null
    });
    assert.equal(missingMap.ok, false);
    assert.match(missingMap.message, /map/i);

    const okResult = validateDoctorRegistrationClinicFields({
        clinicName: 'Smile Care',
        clinicAddress: 'Hill Road, Bandra West',
        city: 'Mumbai',
        state: 'Maharashtra',
        pincode: '400050',
        latitude: 19.05444,
        longitude: 72.83002
    });
    assert.equal(okResult.ok, true);
    assert.equal(okResult.state, 'Maharashtra');
    assert.equal(okResult.clinicAddress, 'Hill Road, Bandra West');
});

test('3. parseUserDeviceMeta safely extracts doctor metadata without crashing on raw FCM tokens', () => {
    assert.deepEqual(parseUserDeviceMeta('raw_fcm_token_xyz'), {});
    assert.deepEqual(parseUserDeviceMeta(null), {});
    const parsed = parseUserDeviceMeta(JSON.stringify({
        clinicName: 'Metro Dental',
        clinicAddress: 'MG Road',
        fcmToken: 'tok-123'
    }));
    assert.equal(parsed.clinicName, 'Metro Dental');
    assert.equal(parsed.fcmToken, 'tok-123');
});

test('4. Migration 05 and Rollback SQL are idempotent, non-destructive, and contain no consultation_mode', () => {
    const migPath = path.resolve(__dirname, '../migrations/05_doctor_clinic_location.sql');
    const rbPath = path.resolve(__dirname, '../migrations/05_rollback_doctor_clinic_location.sql');

    assert.equal(fs.existsSync(migPath), true, 'Migration 05 file must exist');
    assert.equal(fs.existsSync(rbPath), true, 'Rollback 05 file must exist');

    const migSql = fs.readFileSync(migPath, 'utf8');
    const rbSql = fs.readFileSync(rbPath, 'utf8');

    assert.match(migSql, /ADD COLUMN IF NOT EXISTS clinic_name/i);
    assert.match(migSql, /ADD COLUMN IF NOT EXISTS clinic_address/i);
    assert.match(migSql, /ADD COLUMN IF NOT EXISTS state/i);
    assert.match(migSql, /ADD COLUMN IF NOT EXISTS city/i);
    assert.match(migSql, /ADD COLUMN IF NOT EXISTS pincode/i);
    assert.match(migSql, /ADD COLUMN IF NOT EXISTS latitude/i);
    assert.match(migSql, /ADD COLUMN IF NOT EXISTS longitude/i);
    assert.match(migSql, /dentists_lat_lng_range_check/i);
    assert.doesNotMatch(migSql, /consultation_mode/i, 'Migration 05 must not add consultation_mode');

    assert.match(rbSql, /CREATE TABLE IF NOT EXISTS public\._rollback_archive_05_dentists_clinic_location/i);
    assert.match(rbSql, /INSERT INTO public\._rollback_archive_05_dentists_clinic_location/i);
    assert.doesNotMatch(rbSql, /consultation_mode/i);
    assert.doesNotMatch(rbSql, /DROP\s+COLUMN/i, 'Rollback must never drop data columns');
    assert.doesNotMatch(rbSql, /DELETE\s+FROM/i, 'Rollback must never delete doctor records');
    assert.doesNotMatch(rbSql, /TRUNCATE/i, 'Rollback must never truncate tables');
});

test('5. authController.register saves separate state vs clinic_address and preserves coordinates', async () => {
    const Schemas = require('../src/models/Schemas');
    const authController = require('../src/controllers/authController');

    const origUserFindOne = Schemas.User.findOne;
    const origUserFindByMobile = Schemas.User.findByMobile;
    const origUserCreate = Schemas.User.create;
    const origUserUpdate = Schemas.User.findByIdAndUpdate;
    const origClinicFindOne = Schemas.Clinic.findOne;
    const origClinicCreate = Schemas.Clinic.create;
    const origDentistCreate = Schemas.Dentist.create;
    const origDentistFindOne = Schemas.Dentist.findOne;
    const origNotifCreate = Schemas.Notification.create;

    let savedUserPayload = null;
    let savedDentistPayload = null;

    try {
        Schemas.User.findOne = async () => null;
        Schemas.User.findByMobile = async () => null;
        Schemas.User.create = async (payload) => {
            savedUserPayload = payload;
            return { id: 'usr-doc-101', ...payload };
        };
        Schemas.User.findByIdAndUpdate = async (id, payload) => ({ id, ...payload });
        Schemas.Clinic.findOne = async () => null;
        Schemas.Clinic.create = async (payload) => ({ id: 'cln-101', ...payload });
        Schemas.Dentist.findOne = async () => null;
        Schemas.Dentist.create = async (payload) => {
            savedDentistPayload = payload;
            return { id: 'dent-101', ...payload };
        };
        Schemas.Notification.create = async () => ({ id: 'notif-1' });

        const makeRes = () => {
            const state = { statusCode: 200, body: null };
            return {
                state,
                status(code) { state.statusCode = code; return this; },
                json(body) { state.body = body; return this; }
            };
        };

        // Missing map coordinates must be rejected with 400
        const resMissingMap = makeRes();
        await authController.register({
            body: {
                name: 'Dr. Vikram Joshi',
                phone: '9876501234',
                role: 'Dentist',
                clinicName: 'Joshi Dental Studio',
                clinicAddress: '14 Linking Road, Bandra West',
                city: 'Mumbai',
                state: 'Maharashtra',
                pincode: '400050'
            }
        }, resMissingMap);
        assert.equal(resMissingMap.state.statusCode, 400);
        assert.equal(resMissingMap.state.body.success, false);

        // Full valid registration saves exact state (not clinicAddress) and coordinates
        const resValid = makeRes();
        await authController.register({
            body: {
                name: 'Dr. Vikram Joshi',
                phone: '9876501234',
                role: 'Dentist',
                specialty: 'Endodontics',
                clinicName: 'Joshi Dental Studio',
                clinicAddress: '14 Linking Road, Bandra West',
                city: 'Mumbai',
                state: 'Maharashtra',
                pincode: '400050',
                latitude: 19.060692,
                longitude: 72.83625
            }
        }, resValid);

        assert.equal(resValid.state.statusCode, 201);
        assert.equal(resValid.state.body.success, true);
        assert.equal(savedUserPayload.state, 'Maharashtra');
        assert.equal(savedDentistPayload.state, 'Maharashtra');
        assert.equal(savedDentistPayload.clinic_name, 'Joshi Dental Studio');
        assert.equal(savedDentistPayload.clinic_address, '14 Linking Road, Bandra West');
        assert.equal(savedDentistPayload.city, 'Mumbai');
        assert.equal(savedDentistPayload.pincode, '400050');
        assert.equal(savedDentistPayload.latitude, 19.060692);
        assert.equal(savedDentistPayload.longitude, 72.83625);
        assert.equal(resValid.state.body.user.clinicName, 'Joshi Dental Studio');
        assert.equal(resValid.state.body.user.clinicAddress, '14 Linking Road, Bandra West');
        assert.equal(resValid.state.body.user.state, 'Maharashtra');
        assert.equal(resValid.state.body.user.latitude, 19.060692);
        assert.equal(resValid.state.body.user.longitude, 72.83625);
    } finally {
        Schemas.User.findOne = origUserFindOne;
        Schemas.User.findByMobile = origUserFindByMobile;
        Schemas.User.create = origUserCreate;
        Schemas.User.findByIdAndUpdate = origUserUpdate;
        Schemas.Clinic.findOne = origClinicFindOne;
        Schemas.Clinic.create = origClinicCreate;
        Schemas.Dentist.create = origDentistCreate;
        Schemas.Dentist.findOne = origDentistFindOne;
        Schemas.Notification.create = origNotifCreate;
    }
});

test('6. clinicController.updateDoctorProfile persists clinic address, state, pincode, and OSM coordinates', async () => {
    const Schemas = require('../src/models/Schemas');
    const clinicController = require('../src/controllers/clinicController');

    const origDentistUpdate = Schemas.Dentist.findByIdAndUpdate;
    const origDentistFindById = Schemas.Dentist.findById;
    const origClinicFindOne = Schemas.Clinic.findOne;
    const origClinicCreate = Schemas.Clinic.create;
    const origClinicUpdate = Schemas.Clinic.findByIdAndUpdate;
    const origUserUpdate = Schemas.User.findByIdAndUpdate;

    const capturedDentistUpdates = [];

    try {
        Schemas.Clinic.findOne = async () => null;
        Schemas.Clinic.create = async (payload) => ({ id: 'cln-1', ...payload });
        Schemas.Clinic.findByIdAndUpdate = async (id, patch) => ({ id, ...patch });
        Schemas.Dentist.findByIdAndUpdate = async (id, payload) => {
            capturedDentistUpdates.push({ id, payload });
            return {
                id,
                user_id: 'usr-1',
                speciality: 'Endodontics',
                ...payload,
                users: { id: 'usr-1', name: 'Dr. Priya Nair', phone: '9876543210', email: 'priya@gshealth.in' }
            };
        };
        Schemas.Dentist.findById = async (id) => {
            const last = capturedDentistUpdates[capturedDentistUpdates.length - 1]?.payload || {};
            return {
                id,
                user_id: 'usr-1',
                speciality: 'Endodontics',
                ...last,
                users: { id: 'usr-1', name: 'Dr. Priya Nair', phone: '9876543210', email: 'priya@gshealth.in' }
            };
        };
        Schemas.User.findByIdAndUpdate = async (id, payload) => ({ id, ...payload });

        const makeRes = () => {
            const state = { statusCode: 200, body: null };
            return {
                state,
                status(code) { state.statusCode = code; return this; },
                json(body) { state.body = body; return this; }
            };
        };

        const resA = makeRes();
        await clinicController.updateDoctorProfile({
            user: { id: 'usr-1', role: 'DOCTOR' },
            params: { id: 'doc-1' },
            body: {
                clinicName: 'Pearl Smile Dental Clinic',
                clinicAddress: '12 MG Road, Indiranagar',
                city: 'Bengaluru',
                state: 'Karnataka',
                pincode: '560038',
                latitude: 12.978369,
                longitude: 77.640836
            }
        }, resA);

        assert.equal(resA.state.statusCode, 200);
        assert.equal(resA.state.body.success, true);
        assert.equal(resA.state.body.doctor.clinicName, 'Pearl Smile Dental Clinic');
        assert.equal(resA.state.body.doctor.clinicAddress, '12 MG Road, Indiranagar');
        assert.equal(resA.state.body.doctor.city, 'Bengaluru');
        assert.equal(resA.state.body.doctor.state, 'Karnataka');
        assert.equal(resA.state.body.doctor.pincode, '560038');
        assert.equal(resA.state.body.doctor.latitude, 12.978369);
        assert.equal(resA.state.body.doctor.longitude, 77.640836);

        // Invalid coordinate pair returns HTTP 400
        const resBadCoord = makeRes();
        await clinicController.updateDoctorProfile({
            user: { id: 'usr-1', role: 'DOCTOR' },
            params: { id: 'doc-1' },
            body: { latitude: 12.978369 }
        }, resBadCoord);
        assert.equal(resBadCoord.state.statusCode, 400);

        // Invalid pincode returns HTTP 400
        const resBadPin = makeRes();
        await clinicController.updateDoctorProfile({
            user: { id: 'usr-1', role: 'DOCTOR' },
            params: { id: 'doc-1' },
            body: { pincode: '1234' }
        }, resBadPin);
        assert.equal(resBadPin.state.statusCode, 400);
    } finally {
        Schemas.Dentist.findByIdAndUpdate = origDentistUpdate;
        Schemas.Dentist.findById = origDentistFindById;
        Schemas.Clinic.findOne = origClinicFindOne;
        Schemas.Clinic.create = origClinicCreate;
        Schemas.Clinic.findByIdAndUpdate = origClinicUpdate;
        Schemas.User.findByIdAndUpdate = origUserUpdate;
    }
});
