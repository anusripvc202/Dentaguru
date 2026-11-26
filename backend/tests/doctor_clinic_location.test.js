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
    normalizeConsultationMode,
    validateCoordinates,
    parseUserDeviceMeta
} = require('../src/utils/doctorClinicLocationHelper');

test('1. Consultation mode normalization supports BOTH, IN_PERSON, ONLINE_ONLY and legacy ONLINE', () => {
    assert.equal(normalizeConsultationMode(undefined), 'BOTH');
    assert.equal(normalizeConsultationMode(''), 'BOTH');
    assert.equal(normalizeConsultationMode('both'), 'BOTH');
    assert.equal(normalizeConsultationMode('in_person'), 'IN_PERSON');
    assert.equal(normalizeConsultationMode('In-Person'), 'IN_PERSON');
    assert.equal(normalizeConsultationMode('online'), 'ONLINE_ONLY');
    assert.equal(normalizeConsultationMode('ONLINE_ONLY'), 'ONLINE_ONLY');
});

test('2. Coordinate validation enforces bounds, pairing, and explicit clearing', () => {
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

    const outOfRangeLat = validateCoordinates(95.1, 72.8, false);
    assert.equal(outOfRangeLat.ok, false);

    const outOfRangeLng = validateCoordinates(19.0, 181.2, false);
    assert.equal(outOfRangeLng.ok, false);

    const unpaired = validateCoordinates(19.076, null, false);
    assert.equal(unpaired.ok, false);
});

test('3. parseUserDeviceMeta safely extracts doctor metadata without crashing on raw FCM tokens', () => {
    assert.deepEqual(parseUserDeviceMeta('raw_fcm_token_xyz'), {});
    assert.deepEqual(parseUserDeviceMeta(null), {});
    const parsed = parseUserDeviceMeta(JSON.stringify({
        consultationMode: 'ONLINE_ONLY',
        fcmToken: 'tok-123'
    }));
    assert.equal(parsed.consultationMode, 'ONLINE_ONLY');
    assert.equal(parsed.fcmToken, 'tok-123');
});

test('4. Migration 05 and Rollback SQL are idempotent and non-destructive', () => {
    const migPath = path.resolve(__dirname, '../migrations/05_doctor_clinic_location.sql');
    const rbPath = path.resolve(__dirname, '../migrations/05_rollback_doctor_clinic_location.sql');

    assert.equal(fs.existsSync(migPath), true, 'Migration 05 file must exist');
    assert.equal(fs.existsSync(rbPath), true, 'Rollback 05 file must exist');

    const migSql = fs.readFileSync(migPath, 'utf8');
    const rbSql = fs.readFileSync(rbPath, 'utf8');

    assert.match(migSql, /ADD COLUMN IF NOT EXISTS clinic_name/i);
    assert.match(migSql, /ADD COLUMN IF NOT EXISTS clinic_address/i);
    assert.match(migSql, /ADD COLUMN IF NOT EXISTS consultation_mode/i);
    assert.match(migSql, /DEFAULT 'BOTH'/i);
    assert.match(migSql, /dentists_consultation_mode_check/i);
    assert.match(migSql, /dentists_lat_lng_range_check/i);

    assert.match(rbSql, /CREATE TABLE IF NOT EXISTS public\._rollback_archive_05_dentists_clinic_location/i);
    assert.match(rbSql, /INSERT INTO public\._rollback_archive_05_dentists_clinic_location/i);
    assert.doesNotMatch(rbSql, /DROP\s+COLUMN/i, 'Rollback must never drop data columns');
    assert.doesNotMatch(rbSql, /DELETE\s+FROM/i, 'Rollback must never delete doctor records');
    assert.doesNotMatch(rbSql, /TRUNCATE/i, 'Rollback must never truncate tables');
});

test('5. clinicController.updateDoctorProfile persists clinic address, state, coords and handles ONLINE_ONLY switch', async () => {
    const Schemas = require('../src/models/Schemas');
    const clinicController = require('../src/controllers/clinicController');

    const origDentistUpdate = Schemas.Dentist.findByIdAndUpdate;
    const origDentistFindById = Schemas.Dentist.findById;
    const origClinicFindOne = Schemas.Clinic.findOne;
    const origClinicCreate = Schemas.Clinic.create;
    const origClinicUpdate = Schemas.Clinic.findByIdAndUpdate;
    const origUserUpdate = Schemas.User.findByIdAndUpdate;

    const capturedDentistUpdates = [];
    const capturedUserUpdates = [];

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
        Schemas.User.findByIdAndUpdate = async (id, payload) => {
            capturedUserUpdates.push({ id, payload });
            return { id, ...payload };
        };

        const makeRes = () => {
            const state = { statusCode: 200, body: null };
            return {
                state,
                status(code) { state.statusCode = code; return this; },
                json(body) { state.body = body; return this; }
            };
        };

        // Case A: Update clinic address, state, pincode, and OSM coordinates
        const resA = makeRes();
        await clinicController.updateDoctorProfile({
            user: { id: 'usr-1', role: 'DOCTOR' },
            params: { id: 'doc-1' },
            body: {
                consultationMode: 'IN_PERSON',
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
        assert.equal(resA.state.body.doctor.consultationMode, 'IN_PERSON');
        assert.equal(resA.state.body.doctor.clinicName, 'Pearl Smile Dental Clinic');
        assert.equal(resA.state.body.doctor.clinicAddress, '12 MG Road, Indiranagar');
        assert.equal(resA.state.body.doctor.state, 'Karnataka');
        assert.equal(resA.state.body.doctor.pincode, '560038');
        assert.equal(resA.state.body.doctor.latitude, 12.978369);
        assert.equal(resA.state.body.doctor.longitude, 77.640836);

        // Case B: Switching to ONLINE_ONLY clears clinic location & coordinates
        const resB = makeRes();
        await clinicController.updateDoctorProfile({
            user: { id: 'usr-1', role: 'DOCTOR' },
            params: { id: 'doc-1' },
            body: {
                consultationMode: 'ONLINE_ONLY',
                city: 'Bengaluru'
            }
        }, resB);

        assert.equal(resB.state.statusCode, 200);
        assert.equal(resB.state.body.doctor.consultationMode, 'ONLINE_ONLY');
        assert.equal(resB.state.body.doctor.clinicName, '');
        assert.equal(resB.state.body.doctor.clinicAddress, '');
        assert.equal(resB.state.body.doctor.latitude, null);
        assert.equal(resB.state.body.doctor.longitude, null);

        // Case C: Invalid coordinate pair returns HTTP 400
        const resC = makeRes();
        await clinicController.updateDoctorProfile({
            user: { id: 'usr-1', role: 'DOCTOR' },
            params: { id: 'doc-1' },
            body: {
                latitude: 12.978369
            }
        }, resC);
        assert.equal(resC.state.statusCode, 400);
        assert.equal(resC.state.body.success, false);
    } finally {
        Schemas.Dentist.findByIdAndUpdate = origDentistUpdate;
        Schemas.Dentist.findById = origDentistFindById;
        Schemas.Clinic.findOne = origClinicFindOne;
        Schemas.Clinic.create = origClinicCreate;
        Schemas.Clinic.findByIdAndUpdate = origClinicUpdate;
        Schemas.User.findByIdAndUpdate = origUserUpdate;
    }
});
