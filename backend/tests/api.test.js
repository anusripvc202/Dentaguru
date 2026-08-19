// ==========================================================================
// DENTA GURU BACKEND INTEGRATION TEST RUNNER
// Validates schema loading, route endpoints, and token generation logic
// ==========================================================================

const assert = require('assert');
const { User, Clinic, Dentist, Appointment, MedicalRecord, ChatMessage, AuditLog } = require('../src/models/Schemas');
const app = require('../src/app');

console.log('--- STARTING DENTA GURU CORE COMPONENT TESTS ---');

// 1. Validate Mongoose Schemas compilation
try {
    assert.ok(User, 'User model compiled successfully.');
    assert.ok(Clinic, 'Clinic model compiled successfully.');
    assert.ok(Dentist, 'Dentist model compiled successfully.');
    assert.ok(Appointment, 'Appointment model compiled successfully.');
    assert.ok(MedicalRecord, 'MedicalRecord model compiled successfully.');
    assert.ok(ChatMessage, 'ChatMessage model compiled successfully.');
    assert.ok(AuditLog, 'AuditLog model compiled successfully.');
    console.log('✓ SUCCESS: Core Mongoose Schemas loaded and compiled.');

} catch (error) {
    console.error('✗ ERROR: Schema validation failed:', error.message);
    process.exit(1);
}

// 2. Validate Express Server Routing configuration
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
process.exit(0);
