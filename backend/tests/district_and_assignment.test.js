// =============================================================================
// GS HEALTH – DISTRICT, PERMISSIONS & ASSIGNMENT AUDIT BACKEND TEST SUITE
// Validates:
// 1. District CRUD & Multi-District Sub-Admin Mapping with Deduplication
// 2. Sub-Admin Restricted Default Permissions & Permission Change Audit History
// 3. Sub-Admin Self-Escalation Prevention
// 4. Strict District-Level Access Control (Cross-District Rejection 403)
// 5. Patient-to-Doctor Assignment Scenarios:
//    - Scenario A: Patient Direct Booking (PATIENT_DIRECT_BOOKING)
//    - Scenario B: Main Admin Assignment (MAIN_ADMIN_ASSIGNMENT)
//    - Scenario C: Sub-Admin Assignment (SUB_ADMIN_ASSIGNMENT)
//    - Scenario D: Reassignment with Immutable History Chaining
// 6. Dynamic Assignment Metrics & District-wise Reports
// =============================================================================

const assert = require('assert');
const {
    District,
    SubAdminDistrict,
    PermissionChangeHistory,
    PatientAssignmentHistory,
    User,
    Dentist,
    ASSIGNMENT_SOURCES,
    PERMISSION_CONSTANTS
} = require('../src/models/Schemas');

const districtController = require('../src/controllers/districtController');
const assignmentController = require('../src/controllers/assignmentController');
const authController = require('../src/controllers/authController');

console.log('--- STARTING GS HEALTH DISTRICT & ASSIGNMENT AUDIT TESTS ---');

(async () => {
    try {
        // ─────────────────────────────────────────────────────────────────────
        // TEST 1: District CRUD & Seed Verification
        // ─────────────────────────────────────────────────────────────────────
        const initialDistricts = await District.find({ is_active: true });
        assert.ok(initialDistricts.length >= 10, 'Active seed districts loaded correctly.');
        const hyd = initialDistricts.find(d => d.name === 'Hyderabad');
        assert.ok(hyd, 'Hyderabad district exists in seed.');

        // Test District Creation
        const mockReqCreateDist = {
            body: { name: 'Khammam West', state: 'Telangana', country: 'India', is_active: true }
        };
        let createDistRes = null;
        let createDistStatus = 200;
        await districtController.createDistrict(mockReqCreateDist, {
            status: (c) => { createDistStatus = c; return { json: (d) => { createDistRes = d; } }; },
            json: (d) => { createDistRes = d; }
        });
        assert.strictEqual(createDistStatus, 201, 'District created with 201 Created status.');
        assert.ok(createDistRes && createDistRes.success, 'District creation response marked success.');
        assert.strictEqual(createDistRes.district.name, 'Khammam West');
        console.log('✓ SUCCESS: Test 1 - District CRUD and seed verification passed.');

        // ─────────────────────────────────────────────────────────────────────
        // TEST 2: Multi-District Assignment & Duplicate Mapping Prevention
        // ─────────────────────────────────────────────────────────────────────
        const testSubAdminId = 'c0000000-0000-0000-0000-000000000001';
        const testSubAdminUser = await User.create({
            id: testSubAdminId,
            name: 'Vikram Rao',
            email: `vikram_${Date.now()}@gshealth.in`,
            phone: `98888${Math.floor(10000 + Math.random() * 90000)}`,
            role: 'Sub-Admin',
            status: 'ACTIVE',
            permissions: ['PATIENT_VIEW']
        });

        const effectiveSubAdminId = testSubAdminUser ? testSubAdminUser.id : testSubAdminId;

        const distHyd = (await District.findOne({ name: 'Hyderabad' })) || { id: 'dist-hyd', name: 'Hyderabad' };
        const distMedchal = (await District.findOne({ name: 'Medchal-Malkajgiri' })) || { id: 'dist-medchal', name: 'Medchal-Malkajgiri' };
        const distRangareddy = (await District.findOne({ name: 'Rangareddy' })) || { id: 'dist-rangareddy', name: 'Rangareddy' };

        // Assign multiple districts with duplicates in array to test deduplication
        const mockReqAssignDist = {
            params: { id: effectiveSubAdminId },
            user: { id: 'admin-main-1', role: 'Admin' },
            body: { districtIds: [distHyd.id, distMedchal.id, distRangareddy.id, distHyd.id] }
        };
        let assignDistRes = null;
        await districtController.assignSubAdminDistricts(mockReqAssignDist, {
            status: () => ({ json: (d) => { assignDistRes = d; } }),
            json: (d) => { assignDistRes = d; }
        });

        assert.ok(assignDistRes && assignDistRes.success, 'Multi-district assignment succeeded.');
        const assignedDistricts = await SubAdminDistrict.getDistrictsForSubAdmin(effectiveSubAdminId);
        assert.strictEqual(assignedDistricts.length, 3, 'Duplicate district IDs deduplicated strictly to 3.');
        assert.ok(assignedDistricts.some(d => d.name === 'Hyderabad'), 'Hyderabad assigned.');
        assert.ok(assignedDistricts.some(d => d.name === 'Medchal-Malkajgiri'), 'Medchal assigned.');
        assert.ok(assignedDistricts.some(d => d.name === 'Rangareddy'), 'Rangareddy assigned.');

        // Test District Removal
        const mockReqRemoveDist = {
            params: { id: effectiveSubAdminId, districtId: distRangareddy.id },
            user: { id: 'admin-main-1', role: 'Admin' }
        };
        let removeDistRes = null;
        await districtController.removeSubAdminDistrict(mockReqRemoveDist, {
            status: () => ({ json: (d) => { removeDistRes = d; } }),
            json: (d) => { removeDistRes = d; }
        });
        assert.ok(removeDistRes && removeDistRes.success, 'District removed successfully.');
        const afterRemoval = await SubAdminDistrict.getDistrictsForSubAdmin(effectiveSubAdminId);
        assert.strictEqual(afterRemoval.length, 2, 'Sub-admin now has exactly 2 districts.');
        console.log('✓ SUCCESS: Test 2 - Multi-district assignment, deduplication, and removal passed.');

        // ─────────────────────────────────────────────────────────────────────
        // TEST 3: Sub-Admin Restricted Default Permissions & Permission Audit Log
        // ─────────────────────────────────────────────────────────────────────
        const mockReqCreateSubAdmin = {
            user: { id: 'admin-main-1', role: 'Admin' },
            body: {
                name: 'Kavita Reddy',
                phone: `9888${Math.floor(100000 + Math.random() * 900000)}`,
                email: `kavita.subadmin.${Date.now()}@gshealth.in`,
                city: 'Warangal',
                districtIds: [distHyd.id]
            }
        };
        let createSubAdminRes = null;
        let createSubAdminStatus = 200;
        await authController.createSubAdmin(mockReqCreateSubAdmin, {
            status: (c) => { createSubAdminStatus = c; return { json: (d) => { createSubAdminRes = d; } }; },
            json: (d) => { createSubAdminRes = d; }
        });
        assert.strictEqual(createSubAdminStatus, 201, 'Sub-admin created with 201 Created.');
        assert.deepStrictEqual(createSubAdminRes.subAdmin.permissions, ['PATIENT_VIEW'], 'New Sub-admin strictly defaults to RESTRICTED permission.');

        // Update permissions individually and verify PermissionChangeHistory
        const subAdminId2 = createSubAdminRes.subAdmin.id;
        const mockReqUpdatePerms = {
            params: { id: subAdminId2 },
            user: { id: 'admin-main-1', name: 'Main Admin', role: 'Admin' },
            body: {
                permissions: ['PATIENT_VIEW', 'PATIENT_ASSIGN', 'DENTIST_VIEW'],
                reason: 'Authorized for Hyderabad district patient coordination.'
            }
        };
        let updatePermsRes = null;
        await authController.updateSubAdminPermissions(mockReqUpdatePerms, {
            status: () => ({ json: (d) => { updatePermsRes = d; } }),
            json: (d) => { updatePermsRes = d; }
        });
        assert.ok(updatePermsRes && updatePermsRes.success, 'Permissions updated successfully.');
        assert.deepStrictEqual(updatePermsRes.permissions, ['PATIENT_VIEW', 'PATIENT_ASSIGN', 'DENTIST_VIEW']);

        const permHistory = await PermissionChangeHistory.getHistoryForUser(subAdminId2);
        assert.ok(permHistory.length >= 2, 'Permission change history records generated.');
        assert.ok(permHistory.some(h => h.permission_key === 'PATIENT_ASSIGN' && h.action === 'GRANTED'), 'Audit log recorded GRANTED action for PATIENT_ASSIGN.');
        console.log('✓ SUCCESS: Test 3 - Restricted permission defaults and permission change audit log passed.');

        // ─────────────────────────────────────────────────────────────────────
        // TEST 4: Sub-Admin Self-Escalation Prevention
        // ─────────────────────────────────────────────────────────────────────
        const mockReqSelfEscalate = {
            params: { id: subAdminId2 },
            user: { id: subAdminId2, role: 'Sub-Admin' }, // Sub-admin trying to update their own permissions
            body: {
                permissions: ['PATIENT_VIEW', 'PATIENT_ASSIGN', 'CLINIC_MANAGE', 'ADMIN']
            }
        };
        let selfEscalateStatus = 200;
        let selfEscalateMsg = '';
        await authController.updateSubAdminPermissions(mockReqSelfEscalate, {
            status: (c) => { selfEscalateStatus = c; return { json: (d) => { selfEscalateMsg = d.message; } }; },
            json: (d) => { selfEscalateMsg = d.message; }
        });
        assert.strictEqual(selfEscalateStatus, 403, 'Sub-admin self-escalation rejected with 403 Forbidden.');
        console.log('✓ SUCCESS: Test 4 - Sub-admin self-escalation rejected strictly with 403.');

        // ─────────────────────────────────────────────────────────────────────
        // TEST 5: Patient Assignment Scenarios & Cross-District Rejection
        // ─────────────────────────────────────────────────────────────────────
        // Setup Test Patient in Mumbai
        const patientMumbai = await User.create({
            id: 'c0000000-0000-0000-0000-000000000002',
            name: 'Riya Sharma',
            phone: `91111${Math.floor(10000 + Math.random() * 90000)}`,
            email: `riya_${Date.now()}@test.com`,
            city: 'Mumbai',
            district: 'Mumbai Suburban',
            state: 'Maharashtra',
            pincode: '400050',
            role: 'Patient'
        });

        // Setup Test Patient in Hyderabad
        const patientHyderabad = await User.create({
            id: 'c0000000-0000-0000-0000-000000000003',
            name: 'Ananya Rao',
            phone: `92222${Math.floor(10000 + Math.random() * 90000)}`,
            email: `ananya_${Date.now()}@test.com`,
            city: 'Hyderabad',
            district: 'Hyderabad',
            state: 'Telangana',
            pincode: '500001',
            role: 'Patient'
        });

        // Setup Test Doctor
        const testDoctor = await Dentist.create({
            id: 'd0000000-0000-0000-0000-000000000001',
            name: 'Dr. Suresh Kumar',
            speciality: 'Endodontist',
            city: 'Hyderabad',
            district: 'Hyderabad',
            state: 'Telangana',
            license_number: `DENT-HYD-${Date.now()}`
        });

        // Sub-Admin with only Hyderabad assignment tries to assign Mumbai patient -> MUST BE REJECTED 403
        const mockReqCrossDistrict = {
            user: { id: subAdminId2, name: 'Kavita Reddy', role: 'Sub-Admin' },
            body: {
                patientId: patientMumbai.id,
                doctorId: testDoctor.id,
                reason: 'Cross-district assignment attempt'
            }
        };
        let crossDistrictStatus = 200;
        let crossDistrictMsg = '';
        await assignmentController.assignPatientToDoctor(mockReqCrossDistrict, {
            status: (c) => { crossDistrictStatus = c; return { json: (d) => { crossDistrictMsg = d.message; } }; },
            json: (d) => { crossDistrictMsg = d.message; }
        });
        assert.strictEqual(crossDistrictStatus, 403, 'Cross-district assignment strictly rejected with 403 Forbidden.');
        console.log('✓ SUCCESS: Test 5A - Cross-district access control enforced (403 Forbidden).');

        // Sub-Admin assigns Hyderabad patient (AUTHORIZED) -> SCENARIO C: SUB_ADMIN_ASSIGNMENT
        const mockReqSubAdminAssign = {
            user: { id: subAdminId2, name: 'Kavita Reddy', role: 'Sub-Admin' },
            body: {
                patientId: patientHyderabad.id,
                doctorId: testDoctor.id,
                reason: 'Patient referred for acute root canal therapy.'
            }
        };
        let subAdminAssignRes = null;
        await assignmentController.assignPatientToDoctor(mockReqSubAdminAssign, {
            status: () => ({ json: (d) => { subAdminAssignRes = d; } }),
            json: (d) => { subAdminAssignRes = d; }
        });
        assert.ok(subAdminAssignRes && subAdminAssignRes.success, 'Sub-admin assignment succeeded.');
        assert.strictEqual(subAdminAssignRes.assignment.assignment_source, ASSIGNMENT_SOURCES.SUB_ADMIN_ASSIGNMENT);
        assert.strictEqual(subAdminAssignRes.assignment.assigned_by_name, 'Kavita Reddy');
        assert.strictEqual(subAdminAssignRes.assignment.assigned_by_role, 'SUB_ADMIN');
        assert.strictEqual(subAdminAssignRes.assignment.district_name, 'Hyderabad');
        console.log('✓ SUCCESS: Test 5B - Sub-Admin authorized assignment verified with immutable audit trail.');

        // SCENARIO B: Main Admin Assignment
        const mockReqAdminAssign = {
            user: { id: 'admin-main-1', name: 'Main Admin', role: 'Admin' },
            body: {
                patientId: patientMumbai.id,
                doctorId: testDoctor.id,
                reason: 'Direct assignment by Primary Medical Administrator.'
            }
        };
        let adminAssignRes = null;
        await assignmentController.assignPatientToDoctor(mockReqAdminAssign, {
            status: () => ({ json: (d) => { adminAssignRes = d; } }),
            json: (d) => { adminAssignRes = d; }
        });
        assert.ok(adminAssignRes && adminAssignRes.success, 'Main Admin assignment succeeded.');
        assert.strictEqual(adminAssignRes.assignment.assignment_source, ASSIGNMENT_SOURCES.MAIN_ADMIN_ASSIGNMENT);
        assert.strictEqual(adminAssignRes.assignment.assigned_by_name, 'Main Admin');
        assert.strictEqual(adminAssignRes.assignment.assigned_by_role, 'MAIN_ADMIN');
        console.log('✓ SUCCESS: Test 5C - Main Admin assignment verified.');

        // SCENARIO D: Reassignment with Immutable History Chaining
        const newDoctor = await Dentist.create({
            id: 'd0000000-0000-0000-0000-000000000002',
            name: 'Dr. Neha Sen',
            speciality: 'Orthodontist',
            city: 'Hyderabad',
            district: 'Hyderabad',
            state: 'Telangana',
            license_number: `DENT-HYD-NEW-${Date.now()}`
        });

        const initialAssignmentId = subAdminAssignRes.assignment.id;
        const mockReqReassign = {
            user: { id: 'admin-main-1', name: 'Main Admin', role: 'Admin' },
            body: {
                previousAssignmentId: initialAssignmentId,
                patientId: patientHyderabad.id,
                newDoctorId: newDoctor.id,
                reason: 'Patient requested second opinion with orthodontic specialist.'
            }
        };
        let reassignRes = null;
        await assignmentController.reassignPatient(mockReqReassign, {
            status: () => ({ json: (d) => { reassignRes = d; } }),
            json: (d) => { reassignRes = d; }
        });
        assert.ok(reassignRes && reassignRes.success, 'Reassignment succeeded.');
        assert.strictEqual(reassignRes.assignment.previous_assignment_id, initialAssignmentId, 'Chained to previous assignment ID.');
        assert.strictEqual(reassignRes.assignment.status, 'REASSIGNED');

        // Verify that original assignment was NOT deleted or overwritten
        const patientTimeline = await PatientAssignmentHistory.getHistoryForPatient(patientHyderabad.id);
        assert.strictEqual(patientTimeline.length, 2, 'Chronological timeline contains both initial assignment and reassignment.');
        console.log('✓ SUCCESS: Test 5D - Reassignment chaining and audit immutability verified.');

        // ─────────────────────────────────────────────────────────────────────
        // TEST 6: Dynamic Assignment Statistics & District-wise Reports
        // ─────────────────────────────────────────────────────────────────────
        let statsRes = null;
        await assignmentController.getAssignmentStatistics({}, {
            status: () => ({ json: (d) => { statsRes = d; } }),
            json: (d) => { statsRes = d; }
        });
        assert.ok(statsRes && statsRes.success, 'Assignment statistics retrieved.');
        assert.ok(statsRes.statistics.totalDistricts >= 10, 'Total districts counted dynamically.');
        assert.ok(statsRes.statistics.totalAssignments >= 2, 'Total assignments counted dynamically.');
        assert.ok(statsRes.statistics.adminAssignments >= 1, 'Admin assignments tracked dynamically.');
        assert.ok(statsRes.statistics.subAdminAssignments >= 1, 'Sub-admin assignments tracked dynamically.');

        let reportsRes = null;
        await assignmentController.getDistrictReports({}, {
            status: () => ({ json: (d) => { reportsRes = d; } }),
            json: (d) => { reportsRes = d; }
        });
        assert.ok(reportsRes && reportsRes.success, 'District reports retrieved.');
        assert.ok(reportsRes.reports.length >= 10, 'District-wise reports generated for all districts.');
        const hydReport = reportsRes.reports.find(r => r.district_name === 'Hyderabad');
        assert.ok(hydReport, 'Hyderabad district report found.');
        assert.ok(hydReport.total_assignments >= 1, 'Hyderabad assignments aggregated.');
        console.log('✓ SUCCESS: Test 6 - Dynamic assignment statistics and district reports verified.');

        console.log('--- ALL GS HEALTH DISTRICT & ASSIGNMENT AUDIT TESTS PASSED SUCCESSFULLY (6/6) ---');
        process.exit(0);
    } catch (err) {
        console.error('✗ ERROR during test execution:', err);
        process.exit(1);
    }
})();
