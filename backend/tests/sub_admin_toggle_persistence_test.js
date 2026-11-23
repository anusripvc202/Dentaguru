/**
 * End-to-End Integration Test against live Express API + live Supabase PostgreSQL:
 * GS HEALTH – Sub-Admin Active/Deactive Toggle Persistence & Access Control (Tests 1–6)
 */
require('dotenv').config();
const assert = require('assert');
const http = require('http');
const app = require('../src/app');
const { supabaseAdmin } = require('../src/config/supabase');

let BASE_URL = process.env.API_BASE_URL || '';

async function jsonFetch(url, options = {}) {
    const res = await fetch(url, {
        ...options,
        headers: {
            'Content-Type': 'application/json',
            ...(options.headers || {}),
        },
    });
    const text = await res.text();
    let body = {};
    try {
        body = text ? JSON.parse(text) : {};
    } catch (_) {
        body = { raw: text };
    }
    return { status: res.status, body };
}

(async () => {
    const ts = Date.now().toString().slice(-6);
    const subPhone = `93${ts}77`;
    const subPass = `SubPass_${ts}!`;
    let createdSubAdminId = null;
    let seededAdminId = null;
    let localServer = null;

    if (!BASE_URL) {
        localServer = http.createServer(app);
        await new Promise((resolve) => localServer.listen(0, '127.0.0.1', resolve));
        BASE_URL = `http://127.0.0.1:${localServer.address().port}/api/v1`;
    }

    try {
        console.log(`🧪 Starting Sub-Admin Toggle Persistence & Access Control E2E Test (ts=${ts})...`);

        const { User } = require('../src/models/Schemas');
        let adminUser = await User.findByMobile('9281030535').catch(() => null);
        if (!adminUser) {
            adminUser = await User.create({
                name: 'GS Health Test Admin',
                email: `admin.toggle.${ts}@gshealth-test.local`,
                password: `AdminPass_${ts}!`,
                phone: '9281030535',
                role: 'Admin',
                status: 'ACTIVE'
            });
            seededAdminId = adminUser?.id || null;
        }

        // Authenticate as Primary Main Admin
        const adminOtpReq = await jsonFetch(`${BASE_URL}/auth/otp/request`, {
            method: 'POST',
            body: JSON.stringify({ phone: '9281030535' }),
        });
        assert.strictEqual(adminOtpReq.status, 200, `Admin OTP request failed: ${JSON.stringify(adminOtpReq.body)}`);
        assert.ok(adminOtpReq.body.otp, 'Expected on-screen OTP in dev mode');

        const adminLogin = await jsonFetch(`${BASE_URL}/auth/otp/verify`, {
            method: 'POST',
            body: JSON.stringify({ phone: '9281030535', code: adminOtpReq.body.otp }),
        });
        assert.strictEqual(adminLogin.status, 200, `Admin login failed: ${JSON.stringify(adminLogin.body)}`);
        let adminToken = adminLogin.body.accessToken;
        assert.ok(adminToken, 'Expected Admin accessToken');

        // TEST 1: Create new Sub-Admin -> verify ACTIVE -> click Deactive -> verify INACTIVE
        const createRes = await jsonFetch(`${BASE_URL}/admin/sub-admins`, {
            method: 'POST',
            headers: { Authorization: `Bearer ${adminToken}` },
            body: JSON.stringify({
                name: `ToggleTest SubAdmin ${ts}`,
                phone: subPhone,
                password: subPass,
                role: 'Sub-Admin',
                permissions: ['PATIENT_VIEW', 'DENTIST_VIEW'],
            }),
        });
        assert.strictEqual(createRes.status, 201, `Create Sub-Admin failed: ${JSON.stringify(createRes.body)}`);
        createdSubAdminId = createRes.body.subAdmin.id;
        assert.strictEqual(createRes.body.subAdmin.status, 'ACTIVE', 'Newly created sub-admin must start ACTIVE');

        // Verify direct Supabase row is ACTIVE
        let { data: dbRow } = await supabaseAdmin
            .from('users')
            .select('id, status, device_token')
            .eq('id', createdSubAdminId)
            .single();
        assert.strictEqual(dbRow.status, 'ACTIVE');

        // Log in as active Sub-Admin before deactivation to get a valid JWT + refreshToken
        const subLogin1 = await jsonFetch(`${BASE_URL}/auth/login`, {
            method: 'POST',
            body: JSON.stringify({ phone: subPhone, password: subPass, role: 'Sub-Admin' }),
        });
        assert.strictEqual(subLogin1.status, 200, `Active sub-admin login failed: ${JSON.stringify(subLogin1.body)}`);
        const oldSubJwt = subLogin1.body.accessToken;
        const oldRefresh = subLogin1.body.refreshToken;
        assert.ok(oldSubJwt && oldRefresh);

        // Ensure previously-issued token works while ACTIVE
        const activeProtected = await jsonFetch(`${BASE_URL}/admin/patients`, {
            headers: { Authorization: `Bearer ${oldSubJwt}` },
        });
        assert.strictEqual(activeProtected.status, 200, `Active sub-admin with PATIENT_VIEW should access /admin/patients, got ${activeProtected.status}`);

        // Wait 1.1s so jwt iat (in seconds) precedes revokedBefore timestamp cleanly
        await new Promise((r) => setTimeout(r, 1100));

        // Deactivate Sub-Admin
        const deactRes = await jsonFetch(`${BASE_URL}/admin/sub-admins/${createdSubAdminId}/status`, {
            method: 'PATCH',
            headers: { Authorization: `Bearer ${adminToken}` },
            body: JSON.stringify({ status: 'INACTIVE', is_active: false }),
        });
        assert.strictEqual(deactRes.status, 200, `Deactivate failed: ${JSON.stringify(deactRes.body)}`);
        assert.strictEqual(deactRes.body.subAdmin.status, 'INACTIVE');
        assert.strictEqual(deactRes.body.subAdmin.is_active, false);

        // TEST 2: Simulate browser refresh -> GET /admin/sub-admins + direct Supabase query must remain INACTIVE
        const listAfterDeact = await jsonFetch(`${BASE_URL}/admin/sub-admins`, {
            headers: { Authorization: `Bearer ${adminToken}` },
        });
        assert.strictEqual(listAfterDeact.status, 200);
        const foundAfterDeact = (listAfterDeact.body.subAdmins || []).find((s) => s.id === createdSubAdminId);
        assert.ok(foundAfterDeact, 'Sub-admin missing from GET /admin/sub-admins');
        assert.strictEqual(foundAfterDeact.status, 'INACTIVE', `Expected INACTIVE after refresh, got ${foundAfterDeact.status}`);

        ({ data: dbRow } = await supabaseAdmin
            .from('users')
            .select('id, status, device_token')
            .eq('id', createdSubAdminId)
            .single());
        assert.strictEqual(dbRow.status, 'INACTIVE', 'Supabase users.status column must persist INACTIVE');
        assert.strictEqual(JSON.parse(dbRow.device_token).status, 'INACTIVE', 'Supabase device_token.status must persist INACTIVE');

        // TEST 3: Admin relogin (fresh session token via refresh-token) + profile update without status must NOT flip INACTIVE back to ACTIVE
        const adminRelogin = await jsonFetch(`${BASE_URL}/auth/refresh`, {
            method: 'POST',
            body: JSON.stringify({ refreshToken: adminLogin.body.refreshToken }),
        });
        assert.strictEqual(adminRelogin.status, 200, `Admin relogin failed: ${JSON.stringify(adminRelogin.body)}`);
        adminToken = adminRelogin.body.accessToken;
        assert.ok(adminToken, 'Expected fresh Admin accessToken on relogin');

        const listAfterRelogin = await jsonFetch(`${BASE_URL}/admin/sub-admins`, {
            headers: { Authorization: `Bearer ${adminToken}` },
        });
        assert.strictEqual(listAfterRelogin.status, 200, `GET sub-admins after relogin failed: ${JSON.stringify(listAfterRelogin.body)}`);
        const foundAfterRelogin = (listAfterRelogin.body.subAdmins || []).find((s) => s.id === createdSubAdminId);
        assert.ok(foundAfterRelogin, 'Sub-admin missing from GET /admin/sub-admins after relogin');
        assert.strictEqual(foundAfterRelogin.status, 'INACTIVE', 'Status must stay INACTIVE after Admin relogin');

        const profileUpdateNoStatus = await jsonFetch(`${BASE_URL}/admin/sub-admins/${createdSubAdminId}`, {
            method: 'PUT',
            headers: { Authorization: `Bearer ${adminToken}` },
            body: JSON.stringify({ name: `ToggleTest SubAdmin ${ts} Renamed` }),
        });
        assert.strictEqual(profileUpdateNoStatus.status, 200);
        assert.strictEqual(profileUpdateNoStatus.body.subAdmin.status, 'INACTIVE', 'Profile edit without status must not revert INACTIVE to ACTIVE');

        // TEST 4: Inactive Sub-Admin login (password & OTP), refreshToken, and existing JWT must ALL be blocked
        const subBlockedPwd = await jsonFetch(`${BASE_URL}/auth/login`, {
            method: 'POST',
            body: JSON.stringify({ phone: subPhone, password: subPass, role: 'Sub-Admin' }),
        });
        assert.strictEqual(subBlockedPwd.status, 403, `Deactivated sub-admin login must be 403, got ${subBlockedPwd.status}`);
        assert.strictEqual(subBlockedPwd.body.code, 'ACCOUNT_DEACTIVATED');

        const subOtpReq = await jsonFetch(`${BASE_URL}/auth/otp/request`, {
            method: 'POST',
            body: JSON.stringify({ phone: subPhone }),
        });
        if (subOtpReq.body.otp) {
            const subBlockedOtp = await jsonFetch(`${BASE_URL}/auth/otp/verify`, {
                method: 'POST',
                body: JSON.stringify({ phone: subPhone, code: subOtpReq.body.otp }),
            });
            assert.strictEqual(subBlockedOtp.status, 403, `Deactivated sub-admin OTP verify must be 403, got ${subBlockedOtp.status}`);
            assert.strictEqual(subBlockedOtp.body.code, 'ACCOUNT_DEACTIVATED');
        }

        const subBlockedRefresh = await jsonFetch(`${BASE_URL}/auth/refresh`, {
            method: 'POST',
            body: JSON.stringify({ refreshToken: oldRefresh }),
        });
        assert.strictEqual(subBlockedRefresh.status, 403, `Deactivated sub-admin refresh-token must be 403, got ${subBlockedRefresh.status}`);

        const subBlockedOldJwt = await jsonFetch(`${BASE_URL}/admin/patients`, {
            headers: { Authorization: `Bearer ${oldSubJwt}` },
        });
        assert.strictEqual(subBlockedOldJwt.status, 403, `Existing JWT of deactivated sub-admin must be blocked, got ${subBlockedOldJwt.status}`);
        assert.strictEqual(subBlockedOldJwt.body.code, 'ACCOUNT_DEACTIVATED');

        // TEST 5 & 6: Repeated INACTIVE <-> ACTIVE toggle cycles and restored Sub-Admin access
        for (const target of ['ACTIVE', 'INACTIVE', 'ACTIVE']) {
            const tog = await jsonFetch(`${BASE_URL}/admin/sub-admins/${createdSubAdminId}/status`, {
                method: 'PATCH',
                headers: { Authorization: `Bearer ${adminToken}` },
                body: JSON.stringify({ status: target, is_active: target === 'ACTIVE' }),
            });
            assert.strictEqual(tog.status, 200);
            assert.strictEqual(tog.body.subAdmin.status, target);

            const checkList = await jsonFetch(`${BASE_URL}/admin/sub-admins`, {
                headers: { Authorization: `Bearer ${adminToken}` },
            });
            const row = (checkList.body.subAdmins || []).find((s) => s.id === createdSubAdminId);
            assert.strictEqual(row.status, target, `Expected status ${target} after toggle cycle`);

            const { data: cycleDb } = await supabaseAdmin
                .from('users')
                .select('status')
                .eq('id', createdSubAdminId)
                .single();
            assert.strictEqual(cycleDb.status, target, `Expected Supabase users.status=${target}`);
        }

        // Now ACTIVE again: login must succeed
        const subLoginAfterReactivate = await jsonFetch(`${BASE_URL}/auth/login`, {
            method: 'POST',
            body: JSON.stringify({ phone: subPhone, password: subPass, role: 'Sub-Admin' }),
        });
        assert.strictEqual(subLoginAfterReactivate.status, 200, `Reactivated sub-admin login failed: ${JSON.stringify(subLoginAfterReactivate.body)}`);
        assert.strictEqual(subLoginAfterReactivate.body.user.status, 'ACTIVE');

        console.log('✅ All Sub-Admin Active/Deactive Persistence & Access Control E2E Tests (1–6) PASSED!');
    } finally {
        if (createdSubAdminId) {
            try { await supabaseAdmin.from('sub_admin_permissions').delete().eq('user_id', createdSubAdminId); } catch (_) { }
            try { await supabaseAdmin.from('sub_admin_districts').delete().eq('sub_admin_id', createdSubAdminId); } catch (_) { }
            try { await supabaseAdmin.from('audit_logs').delete().eq('target_resource', createdSubAdminId); } catch (_) { }
            try { await supabaseAdmin.from('users').delete().eq('id', createdSubAdminId); } catch (_) { }
        }
        if (seededAdminId) {
            try { await supabaseAdmin.from('users').delete().eq('id', seededAdminId); } catch (_) { }
        }
        if (localServer) {
            localServer.closeAllConnections?.();
            await new Promise((resolve) => localServer.close(resolve));
        }
    }
})();
