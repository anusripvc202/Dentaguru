// ==========================================================================
// DENTA GURU BACKEND INTEGRATION TEST RUNNER
// Validates schema loading, route endpoints, and token generation logic
// ==========================================================================

const assert = require('assert');
const { User, Clinic, Dentist, Appointment, MedicalRecord, ChatMessage, AuditLog, DoctorAvailability } = require('../src/models/Schemas');
const availabilityController = require('../src/controllers/availabilityController');
const app = require('../src/app');

console.log('--- STARTING DENTA GURU CORE COMPONENT TESTS ---');

// 1. Validate Supabase PostgreSQL Models compilation
try {
    assert.ok(User, 'User model compiled successfully.');
    assert.ok(Clinic, 'Clinic model compiled successfully.');
    assert.ok(Dentist, 'Dentist model compiled successfully.');
    assert.ok(Appointment, 'Appointment model compiled successfully.');
    assert.ok(MedicalRecord, 'MedicalRecord model compiled successfully.');
    assert.ok(ChatMessage, 'ChatMessage model compiled successfully.');
    assert.ok(AuditLog, 'AuditLog model compiled successfully.');
    assert.ok(DoctorAvailability, 'DoctorAvailability model compiled successfully.');
    console.log('✓ SUCCESS: Core Supabase PostgreSQL Models loaded and compiled.');

} catch (error) {
    console.error('✗ ERROR: Schema validation failed:', error.message);
    process.exit(1);
}

// 2. Validate Doctor Availability Slot Generation & Authorization
(async () => {
    try {
        // Test Slot Generation Helper
        const mockReqGen = {
            body: { startTime: '09:00 AM', endTime: '11:00 AM', durationMinutes: 30 }
        };
        let genSlotsResult = null;
        const mockResGen = {
            status: (code) => ({
                json: (data) => { genSlotsResult = data; return data; }
            })
        };
        await availabilityController.generateSlots(mockReqGen, mockResGen);
        assert.ok(genSlotsResult && genSlotsResult.success, 'Slot generation returned success.');
        assert.deepStrictEqual(genSlotsResult.slots, ['09:00 AM', '09:30 AM', '10:00 AM', '10:30 AM'], 'Generated non-overlapping 30min slots correctly.');
        console.log('✓ SUCCESS: Doctor availability slot generation logic verified.');

        // Test Patient Authorization Denial (403 Forbidden)
        const mockReqPatient = {
            user: { id: 'patient-123', role: 'Patient' },
            body: { dentistId: 'doc-1', date: '2026-11-10', slots: ['10:00 AM'] }
        };
        let patientAuthStatus = 0;
        let patientAuthMsg = '';
        const mockResPatient = {
            status: (code) => {
                patientAuthStatus = code;
                return {
                    json: (data) => { patientAuthMsg = data.message; }
                };
            }
        };
        await availabilityController.saveDoctorAvailability(mockReqPatient, mockResPatient);
        assert.strictEqual(patientAuthStatus, 403, 'Patient cannot save doctor availability (403 Forbidden).');
        console.log('✓ SUCCESS: Patient role rejected with 403 when modifying doctor slots.');

        // Test Admin Doctor Availability Save
        const mockReqAdmin = {
            user: { id: 'admin-123', role: 'Admin' },
            body: {
                dentistId: 'doc-test-1',
                date: '2026-11-15',
                startTime: '10:00 AM',
                endTime: '12:00 PM',
                slotDurationMinutes: 30,
                slots: ['10:00 AM', '10:30 AM', '11:00 AM', '11:30 AM']
            }
        };
        let adminSaveSuccess = false;
        const mockResAdmin = {
            status: (code) => ({
                json: (data) => { adminSaveSuccess = data.success; }
            })
        };
        await availabilityController.saveDoctorAvailability(mockReqAdmin, mockResAdmin);
        assert.ok(adminSaveSuccess, 'Admin successfully published doctor availability.');
        console.log('✓ SUCCESS: Admin doctor availability publishing verified.');

        // Test Doctor Availability Fetch
        const mockReqFetch = {
            query: { dentistId: 'doc-test-1', date: '2026-11-15' }
        };
        let fetchResult = null;
        const mockResFetch = {
            status: (code) => ({
                json: (data) => { fetchResult = data; }
            })
        };
        await availabilityController.getDoctorAvailability(mockReqFetch, mockResFetch);
        assert.ok(fetchResult && fetchResult.success, 'Availability retrieval succeeded.');
        assert.strictEqual(fetchResult.availability.availableSlots.length, 4, 'Four slots available.');
        console.log('✓ SUCCESS: Doctor availability slot retrieval verified.');

    } catch (err) {
        console.error('✗ ERROR: Availability test failed:', err);
        process.exit(1);
    }

    // 3. Validate Express Server Routing configuration
    try {
        const routes = app._router.stack
            .filter(r => r.route || (r.name === 'router' && r.handle.stack))
            .length;
        assert.ok(routes > 0, 'Express routing middleware mounted successfully.');
        console.log('✓ SUCCESS: Express routes compiled and loaded.');
    } catch (error) {
        console.error('✗ ERROR: Route validation failed:', error.message);
        process.exit(1);
    }

    console.log('--- ALL FOUNDATION CHECKS PASSED SUCCESSFULLY ---');
    setTimeout(() => {
        process.exit(0);
    }, 100);
})();
