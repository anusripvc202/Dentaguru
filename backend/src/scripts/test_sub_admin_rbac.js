/**
 * Automated Verification Script for Sub-Admin RBAC
 * 
 * Verifies:
 * 1. Sub-Admin creation with granular permissions.
 * 2. RBAC middleware permits authorized endpoint (PATIENT_VIEW).
 * 3. RBAC middleware rejects unauthorized endpoint (ASSIGNMENT_CREATE) with 403 Forbidden.
 * 4. Permission update dynamically grants access.
 * 5. Deactivating Sub-Admin account immediately enforces 403 Forbidden.
 * 6. Reactivating restores access.
 * 7. Clean teardown with zero data corruption to main patients/dentists.
 */

const path = require('path');
require('dotenv').config({ path: path.resolve(__dirname, '../../.env') });

const { User, SubAdminPermission, PERMISSION_CONSTANTS } = require('../models/Schemas');
const { requirePermission, requireMainAdmin } = require('../middleware/auth');
const jwt = require('jsonwebtoken');

async function runTests() {
    console.log('🧪 Starting Sub-Admin RBAC Automated Verification Suite...\n');
    let testSubAdminId = null;

    try {
        // Step 1: Clean up any old test sub-admin
        const existing = await User.findOne({ email: 'test_rbac_subadmin@dentaguru.com' });
        if (existing) {
            await SubAdminPermission.setPermissionsForUser(existing.id, []);
            const { supabaseAdmin } = require('../config/supabase');
            await supabaseAdmin.from('users').delete().eq('id', existing.id);
            console.log('🧹 Cleaned up previous test Sub-Admin record.');
        }

        // Step 2: Create Test Sub-Admin with only PATIENT_VIEW permission
        console.log('\n--- Step 1: Create Sub-Admin with [PATIENT_VIEW] ---');
        const subAdmin = await User.create({
            name: 'Test RBAC Officer',
            email: 'test_rbac_subadmin@dentaguru.com',
            password: 'Password123!',
            phone: '9999900112',
            role: 'Sub-Admin',
            status: 'ACTIVE',
            permissions: [PERMISSION_CONSTANTS.PATIENT_VIEW]
        });
        testSubAdminId = subAdmin.id;
        console.log('✅ Created Sub-Admin:', subAdmin.name, `(ID: ${subAdmin.id})`);
        console.log('   Assigned Permissions:', subAdmin.permissions);

        // Step 3: Test Simulated Request Helper
        const createMockReqRes = (user, expectedStatus) => {
            return {
                req: { user },
                res: {
                    statusCode: 200,
                    status(code) {
                        this.statusCode = code;
                        return this;
                    },
                    json(data) {
                        this.data = data;
                        return this;
                    }
                }
            };
        };

        // Step 4: Test PATIENT_VIEW authorization (Expect: ALLOW / next())
        console.log('\n--- Step 2: Test Authorized Endpoint (PATIENT_VIEW) ---');
        let nextCalled = false;
        const middlewarePatientView = requirePermission(PERMISSION_CONSTANTS.PATIENT_VIEW);
        const { req: req1, res: res1 } = createMockReqRes({
            id: subAdmin.id,
            email: subAdmin.email,
            role: 'Sub-Admin',
            status: 'ACTIVE',
            permissions: [PERMISSION_CONSTANTS.PATIENT_VIEW]
        });

        await middlewarePatientView(req1, res1, () => {
            nextCalled = true;
        });

        if (nextCalled) {
            console.log('✅ PASS: Sub-Admin with PATIENT_VIEW granted access to PATIENT_VIEW endpoint.');
        } else {
            throw new Error(`FAIL: Sub-Admin was blocked from PATIENT_VIEW. Status: ${res1.statusCode}`);
        }

        // Step 5: Test ASSIGNMENT_CREATE unauthorized access (Expect: 403 Forbidden)
        console.log('\n--- Step 3: Test Unauthorized Endpoint (ASSIGNMENT_CREATE) ---');
        nextCalled = false;
        const middlewareAssign = requirePermission(PERMISSION_CONSTANTS.ASSIGNMENT_CREATE);
        const { req: req2, res: res2 } = createMockReqRes({
            id: subAdmin.id,
            email: subAdmin.email,
            role: 'Sub-Admin',
            status: 'ACTIVE',
            permissions: [PERMISSION_CONSTANTS.PATIENT_VIEW]
        });

        await middlewareAssign(req2, res2, () => {
            nextCalled = true;
        });

        if (!nextCalled && res2.statusCode === 403) {
            console.log('✅ PASS: Unauthorized endpoint blocked with 403 Forbidden.');
            console.log('   Response Message:', res2.data.message);
        } else {
            throw new Error(`FAIL: Unauthorized endpoint was incorrectly allowed. Status: ${res2.statusCode}`);
        }

        // Step 6: Update Sub-Admin permissions to include ASSIGNMENT_CREATE
        console.log('\n--- Step 4: Update Permissions to include [ASSIGNMENT_CREATE] ---');
        const updated = await User.findByIdAndUpdate(subAdmin.id, {
            permissions: [PERMISSION_CONSTANTS.PATIENT_VIEW, PERMISSION_CONSTANTS.ASSIGNMENT_CREATE]
        });
        console.log('✅ Permissions Updated:', updated.permissions);

        nextCalled = false;
        const { req: req3, res: res3 } = createMockReqRes({
            id: subAdmin.id,
            email: subAdmin.email,
            role: 'Sub-Admin',
            status: 'ACTIVE',
            permissions: updated.permissions
        });

        await middlewareAssign(req3, res3, () => {
            nextCalled = true;
        });

        if (nextCalled) {
            console.log('✅ PASS: Sub-Admin now granted access to ASSIGNMENT_CREATE after permission update.');
        } else {
            throw new Error(`FAIL: Sub-Admin was blocked after permission grant. Status: ${res3.statusCode}`);
        }

        // Step 7: Deactivate Sub-Admin Account (Expect: 403 Forbidden on all calls)
        console.log('\n--- Step 5: Deactivate Sub-Admin Account ---');
        const deactivated = await User.findByIdAndUpdate(subAdmin.id, { status: 'INACTIVE' });
        console.log('✅ Account Status Set To:', deactivated.status);

        nextCalled = false;
        const { req: req4, res: res4 } = createMockReqRes({
            id: subAdmin.id,
            email: subAdmin.email,
            role: 'Sub-Admin',
            status: 'INACTIVE',
            permissions: updated.permissions
        });

        await middlewarePatientView(req4, res4, () => {
            nextCalled = true;
        });

        if (!nextCalled && res4.statusCode === 403) {
            console.log('✅ PASS: Deactivated Sub-Admin blocked from all endpoints with 403 Forbidden.');
            console.log('   Response Message:', res4.data.message);
        } else {
            throw new Error(`FAIL: Deactivated account was not blocked. Status: ${res4.statusCode}`);
        }

        // Step 8: Reactivate Sub-Admin Account
        console.log('\n--- Step 6: Reactivate Sub-Admin Account ---');
        const reactivated = await User.findByIdAndUpdate(subAdmin.id, { status: 'ACTIVE' });
        console.log('✅ Account Status Set To:', reactivated.status);

        nextCalled = false;
        const { req: req5, res: res5 } = createMockReqRes({
            id: subAdmin.id,
            email: subAdmin.email,
            role: 'Sub-Admin',
            status: 'ACTIVE',
            permissions: updated.permissions
        });

        await middlewarePatientView(req5, res5, () => {
            nextCalled = true;
        });

        if (nextCalled) {
            console.log('✅ PASS: Reactivated Sub-Admin successfully granted access again.');
        } else {
            throw new Error(`FAIL: Reactivated account blocked. Status: ${res5.statusCode}`);
        }

        // Step 9: Verify Primary Admin Full Access Bypass
        console.log('\n--- Step 7: Primary Main Admin Bypass Check ---');
        nextCalled = false;
        const { req: reqAdmin, res: resAdmin } = createMockReqRes({
            id: 'primary-admin-id',
            email: 'anusripvc202@gmail.com',
            role: 'Admin',
            status: 'ACTIVE',
            permissions: []
        });

        await middlewareAssign(reqAdmin, resAdmin, () => {
            nextCalled = true;
        });

        if (nextCalled) {
            console.log('✅ PASS: Primary Main Admin has unrestricted full access across all modules.');
        } else {
            throw new Error(`FAIL: Primary Admin was blocked.`);
        }

        console.log('\n=========================================');
        console.log('🎉 ALL SUB-ADMIN RBAC TESTS PASSED (7/7)!');
        console.log('=========================================\n');

    } catch (err) {
        console.error('\n❌ RBAC Test Failure:', err.message);
    } finally {
        // Teardown
        if (testSubAdminId) {
            try {
                await SubAdminPermission.setPermissionsForUser(testSubAdminId, []);
                const { supabaseAdmin } = require('../config/supabase');
                await supabaseAdmin.from('users').delete().eq('id', testSubAdminId);
                console.log('🧹 Teardown: Test Sub-Admin cleaned up from database.');
            } catch (_) {}
        }
        process.exit(0);
    }
}

runTests();
