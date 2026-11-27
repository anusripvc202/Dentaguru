const test = require('node:test');
const assert = require('node:assert/strict');
const jwt = require('jsonwebtoken');
const bcrypt = require('bcryptjs');

process.env.JWT_SECRET = process.env.JWT_SECRET || 'test_jwt_secret_for_sub_admin_flow_123456';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test_refresh_secret_for_sub_admin_flow_123456';
process.env.ADMIN_PHONE = process.env.ADMIN_PHONE || '7013245861';

const Schemas = require('../src/models/Schemas');
const authController = require('../src/controllers/authController');
const { optionalAuth, requireMainAdmin, requirePermission, enforceSubAdminPermissionIfAuthenticated } = require('../src/middleware/auth');
const { getJwtSecret } = require('../src/config/secrets');

function createMockRes() {
    const res = {
        statusCode: 200,
        body: null,
        status(code) {
            this.statusCode = code;
            return this;
        },
        json(payload) {
            this.body = payload;
            return this;
        }
    };
    return res;
}

async function runMiddlewareChain(req, res, middlewares) {
    for (const fn of middlewares) {
        let nextCalled = false;
        await fn(req, res, () => {
            nextCalled = true;
        });
        if (!nextCalled) {
            return res;
        }
    }
    return res;
}

test('1-5. Main Admin creates Sub-Admin, validates required fields & duplicates, hashes password, and assigns Sub-Admin role & permissions', async () => {
    const origFindOne = Schemas.User.findOne;
    const origFindByMobile = Schemas.User.findByMobile;
    const origFindById = Schemas.User.findById;
    const origCreate = Schemas.User.create;
    const origAssignDistricts = Schemas.SubAdminDistrict.assignDistrictsToSubAdmin;
    const origLogChange = Schemas.PermissionChangeHistory.logChange;

    const usersById = new Map();
    const usersByPhone = new Map();
    const usersByEmail = new Map();

    const mainAdmin = {
        id: 'admin-main-1',
        name: 'Primary Admin',
        email: 'admin@gshealth.com',
        phone: '7013245861',
        role: 'Admin',
        status: 'ACTIVE'
    };
    usersById.set(mainAdmin.id, mainAdmin);
    usersByPhone.set(mainAdmin.phone, mainAdmin);
    usersByEmail.set(mainAdmin.email, mainAdmin);

    try {
        Schemas.User.findById = async (id) => usersById.get(id) || null;
        Schemas.User.findByMobile = async (phone) => {
            const d = String(phone || '').replace(/\D/g, '').slice(-10);
            return usersByPhone.get(d) || null;
        };
        Schemas.User.findOne = async (filter) => {
            if (filter?.email) return usersByEmail.get(String(filter.email).toLowerCase()) || null;
            if (filter?.phone) {
                const d = String(filter.phone).replace(/\D/g, '').slice(-10);
                return usersByPhone.get(d) || null;
            }
            return null;
        };
        Schemas.User.create = async (data) => {
            const hashedPassword = await bcrypt.hash(data.password, 10);
            const record = {
                id: `sub-admin-${usersById.size + 1}`,
                ...data,
                password: hashedPassword,
                created_at: new Date().toISOString()
            };
            usersById.set(record.id, record);
            usersByPhone.set(record.phone, record);
            usersByEmail.set(record.email.toLowerCase(), record);
            return record;
        };
        Schemas.SubAdminDistrict.assignDistrictsToSubAdmin = async (id, dIds) =>
            dIds.map((dId) => ({ id: dId, name: `District ${dId}` }));
        Schemas.PermissionChangeHistory.logChange = async () => null;

        const adminToken = jwt.sign({ id: mainAdmin.id, role: 'Admin' }, getJwtSecret(), { expiresIn: '1h' });

        // Test 2a: Missing Full Name validation
        {
            const req = {
                headers: { authorization: `Bearer ${adminToken}` },
                body: { name: '   ', phone: '9876543210', email: 'rahul@gshealth.com' }
            };
            const res = createMockRes();
            await runMiddlewareChain(req, res, [optionalAuth, requireMainAdmin, authController.createSubAdmin]);
            assert.equal(res.statusCode, 400);
            assert.equal(res.body?.code, 'MISSING_NAME');
        }

        // Test 2b: Invalid phone number validation
        {
            const req = {
                headers: { authorization: `Bearer ${adminToken}` },
                body: { name: 'Rahul Sharma', phone: '12345', email: 'rahul@gshealth.com' }
            };
            const res = createMockRes();
            await runMiddlewareChain(req, res, [optionalAuth, requireMainAdmin, authController.createSubAdmin]);
            assert.equal(res.statusCode, 400);
            assert.equal(res.body?.code, 'INVALID_PHONE');
        }

        // Test 2c: Invalid email validation
        {
            const req = {
                headers: { authorization: `Bearer ${adminToken}` },
                body: { name: 'Rahul Sharma', phone: '9876543210', email: 'not-an-email' }
            };
            const res = createMockRes();
            await runMiddlewareChain(req, res, [optionalAuth, requireMainAdmin, authController.createSubAdmin]);
            assert.equal(res.statusCode, 400);
            assert.equal(res.body?.code, 'INVALID_EMAIL');
        }

        // Test 1, 4, 5: Main Admin creates Sub-Admin successfully with hashed password, role 'Sub-Admin', and restricted permissions (never automatic ALL/*)
        {
            const req = {
                headers: { authorization: `Bearer ${adminToken}` },
                body: {
                    name: 'Rahul Sharma',
                    phone: '+91 98765 43210',
                    email: 'Rahul@GSHealth.com',
                    password: 'SecurePassword123',
                    permissions: ['PATIENT_VIEW', 'DENTIST_VIEW', 'ALL', '*'],
                    districtIds: ['dist-hyd']
                }
            };
            const res = createMockRes();
            await runMiddlewareChain(req, res, [optionalAuth, requireMainAdmin, authController.createSubAdmin]);
            assert.equal(res.statusCode, 201);
            assert.equal(res.body?.success, true);
            assert.equal(res.body?.subAdmin?.name, 'Rahul Sharma');
            assert.equal(res.body?.subAdmin?.phone, '9876543210');
            assert.equal(res.body?.subAdmin?.email, 'rahul@gshealth.com');
            assert.equal(res.body?.subAdmin?.role, 'Sub-Admin');
            assert.equal(res.body?.subAdmin?.password, undefined, 'API response must never expose password');
            assert.ok(!res.body?.subAdmin?.permissions.includes('ALL'), 'Must strip ALL wildcard from Sub-Admin');
            assert.ok(!res.body?.subAdmin?.permissions.includes('*'), 'Must strip * wildcard from Sub-Admin');
            assert.deepEqual(res.body?.subAdmin?.permissions, ['PATIENT_VIEW', 'DENTIST_VIEW']);

            const savedRecord = usersByPhone.get('9876543210');
            assert.ok(savedRecord, 'Sub-Admin record must be saved in database');
            assert.notEqual(savedRecord.password, 'SecurePassword123', 'Password must never be stored in plain text');
            assert.ok(savedRecord.password.startsWith('$2'), 'Password must be bcrypt-hashed');
            const matches = await Schemas.comparePassword('SecurePassword123', savedRecord.password);
            assert.equal(matches, true);
        }

        // Test 3a: Duplicate mobile number rejected across formatting variants
        {
            const req = {
                headers: { authorization: `Bearer ${adminToken}` },
                body: {
                    name: 'Duplicate Mobile User',
                    phone: '9876543210',
                    email: 'another@gshealth.com'
                }
            };
            const res = createMockRes();
            await runMiddlewareChain(req, res, [optionalAuth, requireMainAdmin, authController.createSubAdmin]);
            assert.equal(res.statusCode, 400);
            assert.equal(res.body?.code, 'MOBILE_ALREADY_REGISTERED');
        }

        // Test 3b: Duplicate email address rejected
        {
            const req = {
                headers: { authorization: `Bearer ${adminToken}` },
                body: {
                    name: 'Duplicate Email User',
                    phone: '9876500001',
                    email: 'rahul@gshealth.com'
                }
            };
            const res = createMockRes();
            await runMiddlewareChain(req, res, [optionalAuth, requireMainAdmin, authController.createSubAdmin]);
            assert.equal(res.statusCode, 400);
            assert.equal(res.body?.code, 'EMAIL_ALREADY_REGISTERED');
        }
    } finally {
        Schemas.User.findOne = origFindOne;
        Schemas.User.findByMobile = origFindByMobile;
        Schemas.User.findById = origFindById;
        Schemas.User.create = origCreate;
        Schemas.SubAdminDistrict.assignDistrictsToSubAdmin = origAssignDistricts;
        Schemas.PermissionChangeHistory.logChange = origLogChange;
    }
});

test('6-10. Sub-Admin login, permission enforcement, unauthorized API rejection, edit & deactivate, and existing Admin/Doctor login flows', async () => {
    const origFindOne = Schemas.User.findOne;
    const origFindByMobile = Schemas.User.findByMobile;
    const origFindById = Schemas.User.findById;
    const origFindByIdAndUpdate = Schemas.User.findByIdAndUpdate;
    const origGetPerms = Schemas.SubAdminPermission.getPermissionsForUser;
    const origSetPerms = Schemas.SubAdminPermission.setPermissionsForUser;
    const origGetDistricts = Schemas.SubAdminDistrict.getDistrictsForSubAdmin;
    const origAssignDistricts = Schemas.SubAdminDistrict.assignDistrictsToSubAdmin;
    const origLogChange = Schemas.PermissionChangeHistory.logChange;
    const origDentistFindOne = Schemas.Dentist.findOne;
    const origDentistFindById = Schemas.Dentist.findById;

    const hashedSubAdminPass = await bcrypt.hash('SubAdminPass123', 10);
    const hashedAdminPass = await bcrypt.hash('MainAdminPass123', 10);
    const hashedDoctorPass = await bcrypt.hash('DoctorPass123', 10);

    const subAdminUser = {
        id: 'sub-admin-101',
        name: 'Priya SubAdmin',
        email: 'priya.subadmin@gshealth.com',
        phone: '9123456780',
        password: hashedSubAdminPass,
        role: 'Sub-Admin',
        status: 'ACTIVE',
        permissions: ['PATIENT_VIEW'],
        device_token: JSON.stringify({ status: 'ACTIVE', permissions: ['PATIENT_VIEW'] })
    };
    const mainAdminUser = {
        id: 'main-admin-1',
        name: 'GS Main Admin',
        email: 'admin@gshealth.com',
        phone: '7013245861',
        password: hashedAdminPass,
        role: 'Admin',
        status: 'ACTIVE'
    };
    const doctorUser = {
        id: 'doc-user-1',
        name: 'Dr. Arvind Rao',
        email: 'arvind@gshealth.com',
        phone: '9988776655',
        password: hashedDoctorPass,
        role: 'Dentist',
        status: 'ACTIVE'
    };

    const users = [subAdminUser, mainAdminUser, doctorUser];

    try {
        Schemas.User.findById = async (id) => users.find((u) => u.id === id) || null;
        Schemas.User.findByMobile = async (phone) => {
            const d = String(phone || '').replace(/\D/g, '').slice(-10);
            return users.find((u) => u.phone === d) || null;
        };
        Schemas.User.findOne = async (filter) => {
            if (filter?.email) {
                return users.find((u) => u.email.toLowerCase() === String(filter.email).toLowerCase()) || null;
            }
            if (filter?.phone) {
                const d = String(filter.phone).replace(/\D/g, '').slice(-10);
                return users.find((u) => u.phone === d) || null;
            }
            return null;
        };
        Schemas.User.findByIdAndUpdate = async (id, patch) => {
            const target = users.find((u) => u.id === id);
            if (!target) return null;
            Object.assign(target, patch);
            return target;
        };
        Schemas.SubAdminPermission.getPermissionsForUser = async (id) => {
            const u = users.find((x) => x.id === id);
            return u?.permissions || [];
        };
        Schemas.SubAdminPermission.setPermissionsForUser = async (id, perms) => {
            const u = users.find((x) => x.id === id);
            if (u) u.permissions = perms;
            return true;
        };
        Schemas.SubAdminDistrict.getDistrictsForSubAdmin = async () => [{ id: 'dist-1', name: 'Hyderabad' }];
        Schemas.SubAdminDistrict.assignDistrictsToSubAdmin = async () => [{ id: 'dist-1', name: 'Hyderabad' }];
        Schemas.PermissionChangeHistory.logChange = async () => null;
        Schemas.Dentist.findById = async () => null;
        Schemas.Dentist.findOne = async () => ({
            id: 'dentist-1',
            user_id: doctorUser.id,
            speciality: 'Cardiology',
            qualifications: 'MBBS, MD'
        });

        // Test 6: Sub-Admin logs in and loads role 'Sub-Admin' + permissions
        let subAdminToken = null;
        {
            const req = {
                body: {
                    email: 'priya.subadmin@gshealth.com',
                    password: 'SubAdminPass123',
                    role: 'Sub-Admin'
                }
            };
            const res = createMockRes();
            await authController.login(req, res);
            assert.equal(res.statusCode, 200);
            assert.equal(res.body?.success, true);
            assert.equal(res.body?.user?.role, 'Sub-Admin');
            assert.deepEqual(res.body?.user?.permissions, ['PATIENT_VIEW']);
            subAdminToken = res.body?.accessToken;
            assert.ok(subAdminToken, 'Sub-Admin login must issue JWT accessToken');
        }

        // Test 7 & 8: Sub-Admin can access permitted module (PATIENT_VIEW) but is rejected (403) on unpermitted modules & Main Admin routes
        {
            const reqAllowed = { headers: { authorization: `Bearer ${subAdminToken}` } };
            const resAllowed = createMockRes();
            let allowedNext = false;
            await optionalAuth(reqAllowed, resAllowed, () => {});
            await requirePermission('PATIENT_VIEW')(reqAllowed, resAllowed, () => {
                allowedNext = true;
            });
            assert.equal(allowedNext, true, 'Sub-Admin with PATIENT_VIEW must be allowed on PATIENT_VIEW route');

            const reqDeniedModule = { headers: { authorization: `Bearer ${subAdminToken}` } };
            const resDeniedModule = createMockRes();
            await runMiddlewareChain(reqDeniedModule, resDeniedModule, [
                optionalAuth,
                requirePermission('DENTIST_VIEW')
            ]);
            assert.equal(resDeniedModule.statusCode, 403);
            assert.match(resDeniedModule.body?.message || '', /DENTIST_VIEW/);

            const reqDeniedCalendar = { headers: { authorization: `Bearer ${subAdminToken}` } };
            const resDeniedCalendar = createMockRes();
            await runMiddlewareChain(reqDeniedCalendar, resDeniedCalendar, [
                optionalAuth,
                enforceSubAdminPermissionIfAuthenticated('REFERRAL_VIEW')
            ]);
            assert.equal(resDeniedCalendar.statusCode, 403);

            // Sub-Admin must not be able to create another Sub-Admin or Admin
            const reqCreateAnother = {
                headers: { authorization: `Bearer ${subAdminToken}` },
                body: { name: 'Illegal SubAdmin', phone: '9000011111' }
            };
            const resCreateAnother = createMockRes();
            await runMiddlewareChain(reqCreateAnother, resCreateAnother, [
                optionalAuth,
                requireMainAdmin,
                authController.createSubAdmin
            ]);
            assert.equal(resCreateAnother.statusCode, 403);
        }

        // Test 9: Main Admin edits Sub-Admin permissions & deactivates Sub-Admin -> login & API access rejected
        const mainAdminToken = jwt.sign({ id: mainAdminUser.id, role: 'Admin' }, getJwtSecret(), { expiresIn: '1h' });
        {
            const reqEdit = {
                headers: { authorization: `Bearer ${mainAdminToken}` },
                params: { id: subAdminUser.id },
                body: {
                    name: 'Priya SubAdmin Updated',
                    permissions: ['PATIENT_VIEW', 'DENTIST_VIEW', 'REPORT_VIEW']
                }
            };
            const resEdit = createMockRes();
            await runMiddlewareChain(reqEdit, resEdit, [optionalAuth, requireMainAdmin, authController.updateSubAdmin]);
            assert.equal(resEdit.statusCode, 200);
            assert.equal(resEdit.body?.subAdmin?.name, 'Priya SubAdmin Updated');
            assert.deepEqual(resEdit.body?.subAdmin?.permissions, ['PATIENT_VIEW', 'DENTIST_VIEW', 'REPORT_VIEW']);

            // Deactivate Sub-Admin
            const reqDeactivate = {
                headers: { authorization: `Bearer ${mainAdminToken}` },
                params: { id: subAdminUser.id },
                body: { status: 'INACTIVE' }
            };
            const resDeactivate = createMockRes();
            await runMiddlewareChain(reqDeactivate, resDeactivate, [
                optionalAuth,
                requireMainAdmin,
                authController.toggleSubAdminStatus
            ]);
            assert.equal(resDeactivate.statusCode, 200);
            assert.equal(resDeactivate.body?.subAdmin?.status, 'INACTIVE');

            // Deactivated Sub-Admin cannot log in
            const reqLoginDeactivated = {
                body: {
                    email: 'priya.subadmin@gshealth.com',
                    password: 'SubAdminPass123'
                }
            };
            const resLoginDeactivated = createMockRes();
            await authController.login(reqLoginDeactivated, resLoginDeactivated);
            assert.equal(resLoginDeactivated.statusCode, 403);
            assert.equal(resLoginDeactivated.body?.code, 'ACCOUNT_DEACTIVATED');

            // Deactivated Sub-Admin existing JWT token is rejected on API calls
            const reqApiDeactivated = { headers: { authorization: `Bearer ${subAdminToken}` } };
            const resApiDeactivated = createMockRes();
            await optionalAuth(reqApiDeactivated, resApiDeactivated, () => {});
            assert.equal(resApiDeactivated.statusCode, 403);
            assert.equal(resApiDeactivated.body?.code, 'ACCOUNT_DEACTIVATED');
        }

        // Test 10: Existing Main Admin and Doctor login flows work normally
        {
            const reqAdminLogin = {
                body: { phone: '7013245861', password: 'MainAdminPass123', role: 'Admin' }
            };
            const resAdminLogin = createMockRes();
            await authController.login(reqAdminLogin, resAdminLogin);
            assert.equal(resAdminLogin.statusCode, 200);
            assert.equal(resAdminLogin.body?.user?.role, 'Admin');

            const reqDoctorLogin = {
                body: { phone: '9988776655', password: 'DoctorPass123', role: 'Dentist' }
            };
            const resDoctorLogin = createMockRes();
            await authController.login(reqDoctorLogin, resDoctorLogin);
            assert.equal(resDoctorLogin.statusCode, 200);
            assert.equal(resDoctorLogin.body?.user?.role, 'Dentist');
            assert.equal(resDoctorLogin.body?.user?.specialty, 'Cardiology');
        }
    } finally {
        Schemas.User.findOne = origFindOne;
        Schemas.User.findByMobile = origFindByMobile;
        Schemas.User.findById = origFindById;
        Schemas.User.findByIdAndUpdate = origFindByIdAndUpdate;
        Schemas.SubAdminPermission.getPermissionsForUser = origGetPerms;
        Schemas.SubAdminPermission.setPermissionsForUser = origSetPerms;
        Schemas.SubAdminDistrict.getDistrictsForSubAdmin = origGetDistricts;
        Schemas.SubAdminDistrict.assignDistrictsToSubAdmin = origAssignDistricts;
        Schemas.PermissionChangeHistory.logChange = origLogChange;
        Schemas.Dentist.findOne = origDentistFindOne;
        Schemas.Dentist.findById = origDentistFindById;
    }
});
