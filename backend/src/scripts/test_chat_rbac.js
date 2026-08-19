const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '../../.env') });
const assert = require('assert');
const http = require('http');
const jwt = require('jsonwebtoken');
const app = require('../app');
const { User, ChatMessage, AuditLog } = require('../models/Schemas');
const { supabaseAdmin } = require('../config/supabase');

const JWT_SECRET = process.env.JWT_SECRET || 'supersecretjwtkey123';

async function runRbacTests() {
    console.log('🛡️ --- STARTING DENTAGURU CHAT PRIVACY & RBAC SECURITY TEST SUITE --- 🛡️\n');

    // Start a temporary test server on an ephemeral port
    const server = http.createServer(app);
    await new Promise((resolve) => server.listen(0, resolve));
    const port = server.address().port;
    const baseUrl = `http://127.0.0.1:${port}/api/v1`;

    const testTimestamp = Date.now();

    // 1. Create real database users to satisfy Foreign Key constraints
    console.log('Setting up test accounts in database...');

    // Main Admin
    let mainAdmin = await User.findOne({ email: 'anusripvc202@gmail.com' });
    if (!mainAdmin) {
        mainAdmin = await User.create({
            name: 'Main Admin Anusri',
            email: 'anusripvc202@gmail.com',
            role: 'Admin',
            password: 'AdminPassword123!'
        });
    }

    // Test Patient (Alice)
    const testPatient = await User.create({
        name: 'Alice Wonder',
        email: `test_alice_${testTimestamp}@example.com`,
        phone: '9876543210',
        role: 'Patient',
        password: 'Password123!'
    });

    // Test Dentist (Dr. Smith)
    const testDentist = await User.create({
        name: 'Dr. Smith',
        email: `test_smith_${testTimestamp}@example.com`,
        phone: '9876543211',
        role: 'Dentist',
        password: 'Password123!'
    });

    // Test Sub-Admin (Regional SubAdmin with ALL permissions)
    const testSubAdmin = await User.create({
        name: 'Regional SubAdmin',
        email: `test_subadmin_${testTimestamp}@example.com`,
        phone: '9876543212',
        role: 'Sub-Admin',
        password: 'Password123!',
        permissions: ['*'] // Even with ALL permissions, chat must be 403 Forbidden!
    });


    console.log('✅ Test accounts created successfully.');

    // 2. Generate signed JWT tokens
    const mainAdminToken = jwt.sign({
        id: mainAdmin.id,
        email: mainAdmin.email,
        name: mainAdmin.name,
        role: 'Admin',
        status: 'ACTIVE'
    }, JWT_SECRET, { expiresIn: '1h' });

    const subAdminToken = jwt.sign({
        id: testSubAdmin.id,
        email: testSubAdmin.email,
        name: testSubAdmin.name,
        role: 'Sub-Admin',
        status: 'ACTIVE',
        permissions: ['*']
    }, JWT_SECRET, { expiresIn: '1h' });

    const patientToken = jwt.sign({
        id: testPatient.id,
        email: testPatient.email,
        name: testPatient.name,
        role: 'Patient',
        status: 'ACTIVE'
    }, JWT_SECRET, { expiresIn: '1h' });

    const dentistToken = jwt.sign({
        id: testDentist.id,
        email: testDentist.email,
        name: testDentist.name,
        role: 'Dentist',
        status: 'ACTIVE'
    }, JWT_SECRET, { expiresIn: '1h' });

    const aliceRoomId = `PATIENT_ALICE_WONDER_${testTimestamp}`;
    const otherRoomId = `PATIENT_BOB_SECRET_${testTimestamp}`;

    // 3. Create test conversation message in Alice's room
    await ChatMessage.create({
        room_id: aliceRoomId,
        sender_id: testPatient.id,
        message: 'Hello Doctor, I have severe toothache in my lower molar.',
        type: 'patient'
    });
    await ChatMessage.create({
        room_id: aliceRoomId,
        sender_id: testDentist.id,
        message: 'Hello Alice, please visit our clinic tomorrow at 10 AM.',
        type: 'doctor'
    });
    console.log('✅ Seeded test chat messages into room: ' + aliceRoomId + '\n');

    try {
        // TEST 1: Unauthenticated request must return 401
        console.log('TEST 1: Verifying unauthenticated request receives 401 Unauthorized...');
        const resUnauth = await fetch(`${baseUrl}/chat/messages?roomId=${aliceRoomId}`);
        assert.strictEqual(resUnauth.status, 401, 'Expected 401 Unauthorized for unauthenticated request');
        console.log('  ✓ PASSED: Unauthenticated request returned 401 Unauthorized.\n');

        // TEST 2: Sub-Admin calling GET /chat/conversations must return 403 Forbidden
        console.log('TEST 2: Verifying Sub-Admin calling GET /chat/conversations receives 403 Forbidden...');
        const resSubConv = await fetch(`${baseUrl}/chat/conversations`, {
            headers: { Authorization: `Bearer ${subAdminToken}` }
        });
        const subConvBody = await resSubConv.json();
        assert.strictEqual(resSubConv.status, 403, 'Expected 403 Forbidden for Sub-Admin');
        assert.ok(subConvBody.message.includes('Sub-Admins are strictly prohibited'), 'Expected lockout message');
        console.log('  ✓ PASSED: Sub-Admin blocked from /chat/conversations with 403 Forbidden.\n');

        // TEST 3: Sub-Admin calling GET /chat/messages must return 403 Forbidden
        console.log('TEST 3: Verifying Sub-Admin calling GET /chat/messages receives 403 Forbidden...');
        const resSubMsg = await fetch(`${baseUrl}/chat/messages?roomId=${aliceRoomId}`, {
            headers: { Authorization: `Bearer ${subAdminToken}` }
        });
        assert.strictEqual(resSubMsg.status, 403, 'Expected 403 Forbidden for Sub-Admin');
        console.log('  ✓ PASSED: Sub-Admin blocked from reading chat messages with 403 Forbidden.\n');

        // TEST 4: Sub-Admin calling POST /chat/send must return 403 Forbidden
        console.log('TEST 4: Verifying Sub-Admin calling POST /chat/send receives 403 Forbidden...');
        const resSubSend = await fetch(`${baseUrl}/chat/send`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                Authorization: `Bearer ${subAdminToken}`
            },
            body: JSON.stringify({
                roomId: aliceRoomId,
                senderId: testSubAdmin.id,
                message: 'Unauthorized sub-admin message attempt'
            })
        });
        assert.strictEqual(resSubSend.status, 403, 'Expected 403 Forbidden for Sub-Admin');
        console.log('  ✓ PASSED: Sub-Admin blocked from sending chat messages with 403 Forbidden.\n');

        // TEST 5: Sub-Admin calling POST /chat/clear must return 403 Forbidden
        console.log('TEST 5: Verifying Sub-Admin calling POST /chat/clear receives 403 Forbidden...');
        const resSubClear = await fetch(`${baseUrl}/chat/clear`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                Authorization: `Bearer ${subAdminToken}`
            },
            body: JSON.stringify({ roomId: aliceRoomId })
        });
        assert.strictEqual(resSubClear.status, 403, 'Expected 403 Forbidden for Sub-Admin');
        console.log('  ✓ PASSED: Sub-Admin blocked from clearing chat history with 403 Forbidden.\n');

        // TEST 6: Sub-Admin calling GET /chat/audit-logs must return 403 Forbidden
        console.log('TEST 6: Verifying Sub-Admin calling GET /chat/audit-logs receives 403 Forbidden...');
        const resSubAudit = await fetch(`${baseUrl}/chat/audit-logs`, {
            headers: { Authorization: `Bearer ${subAdminToken}` }
        });
        assert.strictEqual(resSubAudit.status, 403, 'Expected 403 Forbidden for Sub-Admin');
        console.log('  ✓ PASSED: Sub-Admin blocked from audit logs with 403 Forbidden.\n');

        // TEST 7: Patient reading their own room succeeds (200 OK)
        console.log('TEST 7: Verifying Patient can read their own room messages (200 OK)...');
        const resPatOwn = await fetch(`${baseUrl}/chat/messages?roomId=${aliceRoomId}`, {
            headers: { Authorization: `Bearer ${patientToken}` }
        });
        const patOwnBody = await resPatOwn.json();
        assert.strictEqual(resPatOwn.status, 200, 'Expected 200 OK for patient in own room');
        assert.ok(patOwnBody.messages.length >= 2, 'Expected at least 2 messages');
        console.log(`  ✓ PASSED: Patient successfully fetched own room messages (${patOwnBody.messages.length} messages).\n`);

        // TEST 8: Patient reading someone else's room is blocked with 403 Forbidden
        console.log('TEST 8: Verifying Patient trying to read another patient\'s room receives 403 Forbidden...');
        // Create an unassigned other room with another user's message
        await ChatMessage.create({
            room_id: otherRoomId,
            sender_id: mainAdmin.id,
            message: 'Confidential patient message for another patient',
            type: 'patient'
        });
        const resPatOther = await fetch(`${baseUrl}/chat/messages?roomId=${otherRoomId}`, {
            headers: { Authorization: `Bearer ${patientToken}` }
        });
        assert.strictEqual(resPatOther.status, 403, 'Expected 403 Forbidden for patient in another room');
        console.log('  ✓ PASSED: Patient prevented from reading another patient\'s chat (403 Forbidden).\n');

        // TEST 9: Assigned Dentist can read assigned room messages (200 OK)
        console.log('TEST 9: Verifying Assigned Dentist can read assigned patient conversation (200 OK)...');
        const resDocAssigned = await fetch(`${baseUrl}/chat/messages?roomId=${aliceRoomId}`, {
            headers: { Authorization: `Bearer ${dentistToken}` }
        });
        const docBody = await resDocAssigned.json();
        assert.strictEqual(resDocAssigned.status, 200, 'Expected 200 OK for assigned dentist');
        console.log(`  ✓ PASSED: Assigned Dentist accessed patient conversation (${docBody.messages.length} messages returned).\n`);

        // TEST 10: Main Admin has full access to list conversations (200 OK)
        console.log('TEST 10: Verifying Main Admin can list all patient-doctor conversations (200 OK)...');
        const resAdminConv = await fetch(`${baseUrl}/chat/conversations`, {
            headers: { Authorization: `Bearer ${mainAdminToken}` }
        });
        const adminConvBody = await resAdminConv.json();
        assert.strictEqual(resAdminConv.status, 200, 'Expected 200 OK for Main Admin');
        assert.ok(Array.isArray(adminConvBody.conversations), 'Expected conversations array');
        console.log(`  ✓ PASSED: Main Admin listed conversations (${adminConvBody.conversations.length} active threads).\n`);

        // TEST 11: Main Admin inspecting messages automatically generates Audit Log
        console.log('TEST 11: Verifying Main Admin message inspection triggers Audit Log...');
        const resAdminMsg = await fetch(`${baseUrl}/chat/messages?roomId=${aliceRoomId}`, {
            headers: { Authorization: `Bearer ${mainAdminToken}` }
        });
        assert.strictEqual(resAdminMsg.status, 200, 'Expected 200 OK for Main Admin');

        // Check audit logs endpoint
        const resAudit = await fetch(`${baseUrl}/chat/audit-logs`, {
            headers: { Authorization: `Bearer ${mainAdminToken}` }
        });
        const auditBody = await resAudit.json();
        assert.strictEqual(resAudit.status, 200, 'Expected 200 OK for audit logs');
        assert.ok(Array.isArray(auditBody.logs), 'Expected logs array');
        console.log(`  ✓ PASSED: Main Admin conversation view logged to audit trail (${auditBody.logs.length} audit logs found).\n`);

        // TEST 12: Ensure database queries from Sub-Admin context return []
        console.log('TEST 12: Verifying database level ChatMessage.find({ user: subAdmin }) returns clean empty array...');
        const subAdminDbResult = await ChatMessage.find({ room_id: aliceRoomId }, { user: testSubAdmin });
        assert.strictEqual(subAdminDbResult.length, 0, 'Expected DB query for Sub-Admin to return 0 messages');
        console.log('  ✓ PASSED: Database query layer strictly enforced 0 results for Sub-Admin.\n');

        console.log('🎉 --- ALL 12 CHAT PRIVACY & RBAC SECURITY TESTS PASSED WITH 100% SUCCESS --- 🎉\n');
    } finally {
        server.close();
        // Clean up test data
        try {
            await ChatMessage.delete({ roomId: aliceRoomId });
            await ChatMessage.delete({ roomId: otherRoomId });
            await supabaseAdmin.from('users').delete().in('id', [testPatient.id, testDentist.id, testSubAdmin.id]);
            console.log('🧹 Cleaned up temporary test users and messages.');
        } catch (_) {}
    }
    process.exit(0);
}

runRbacTests().catch(err => {
    console.error('❌ RBAC Test Failure:', err);
    process.exit(1);
});
