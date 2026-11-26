const test = require('node:test');
const assert = require('node:assert/strict');
const http = require('http');
const jwt = require('jsonwebtoken');

const app = require('../src/app');
const Schemas = require('../src/models/Schemas');
const authController = require('../src/controllers/authController');
const { otpStoreService } = require('../src/services/otpStoreService');
const { getJwtSecret } = require('../src/config/secrets');

function createApiRequester(server) {
    const { port } = server.address();
    return (method, urlPath, headers = {}, body = null) => new Promise((resolve, reject) => {
        const payload = body ? JSON.stringify(body) : null;
        const req = http.request({
            hostname: '127.0.0.1',
            port,
            path: urlPath,
            method,
            headers: {
                ...(payload ? { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(payload) } : {}),
                ...headers,
            }
        }, (res) => {
            let raw = '';
            res.on('data', (chunk) => { raw += chunk; });
            res.on('end', () => {
                try {
                    resolve({ status: res.statusCode, json: raw ? JSON.parse(raw) : {} });
                } catch (e) {
                    resolve({ status: res.statusCode, json: { raw } });
                }
            });
        });
        req.on('error', reject);
        if (payload) req.write(payload);
        req.end();
    });
}

test('1. Phone normalization handles all Indian country-code & formatting variants consistently', () => {
    const expected = '9281030535';
    const variants = [
        '9281030535',
        '+919281030535',
        '+91 92810 30535',
        '+91-92810-30535',
        '919281030535',
        '09281030535',
        '00919281030535',
        '+91 09281030535',
    ];
    for (const v of variants) {
        assert.strictEqual(Schemas.canonicalPhone10(v), expected, `Failed normalizing variant: ${v}`);
    }

    // Placeholder env var (+91XXXXXXXXXX) must be ignored instead of turning into invalid "91"
    const parsedPlaceholder = authController._getConfiguredEnvAdminPhones({
        ADMIN_PHONE: '+91XXXXXXXXXX',
        ADMIN_MOBILE_NUMBER: '   '
    });
    assert.strictEqual(parsedPlaceholder.size, 0);

    const parsedValidList = authController._getConfiguredEnvAdminPhones({
        ADMIN_PHONE: '+91 92810 30535, +91XXXXXXXXXX, 09876543210'
    });
    assert.strictEqual(parsedValidList.has('9281030535'), true);
    assert.strictEqual(parsedValidList.has('9876543210'), true);
    assert.strictEqual(parsedValidList.size, 2);
});

test('2. Admin OTP Login succeeds even when ADMIN_PHONE env var is mismatched, placeholder, or unset, across all phone formats and Main Admin role variants', async () => {
    const prevEnv = process.env.NODE_ENV;
    const prevMode = process.env.OTP_DELIVERY_MODE;
    const prevStagingKey = process.env.STAGING_OTP_ACCESS_KEY;
    const prevAdminPhone = process.env.ADMIN_PHONE;
    const prevJwt = process.env.JWT_SECRET;
    const prevRefresh = process.env.REFRESH_SECRET;
    const prevSalt = process.env.OTP_SALT;

    const origFindByMobile = Schemas.User.findByMobile;
    const origFindOne = Schemas.User.findOne;
    const origFindById = Schemas.User.findById;
    const origUpdate = Schemas.User.findByIdAndUpdate;
    const origRpc = otpStoreService.supabaseClient;

    const usersFixture = [
        {
            id: '339f745b-2192-4055-abec-d7e4adc6c837',
            name: 'GS HEALTH Admin',
            email: 'user_9281030535@dentaguru.internal',
            phone: '9281030535',
            role: 'ADMIN',
            status: 'ACTIVE',
            refresh_tokens: []
        },
        {
            id: 'admin-super-02',
            name: 'Secondary Super Admin',
            email: 'super@gshealth.local',
            phone: '+91 98111 22233',
            role: 'super_admin',
            status: 'ACTIVE',
            refresh_tokens: []
        },
        {
            id: 'admin-inactive-03',
            name: 'Deactivated Admin',
            email: 'inactive.admin@gshealth.local',
            phone: '9822233344',
            role: 'Admin',
            status: 'DEACTIVATED',
            refresh_tokens: []
        },
        {
            id: 'subadmin-active-04',
            name: 'Active Sub-Admin',
            email: 'sub@gshealth.local',
            phone: '9833344455',
            role: 'Sub-Admin',
            status: 'ACTIVE',
            permissions: ['PATIENT_VIEW'],
            refresh_tokens: []
        },
        {
            id: 'patient-ordinary-05',
            name: 'Ordinary Patient',
            email: 'patient@gshealth.local',
            phone: '9844455566',
            role: 'Patient',
            status: 'ACTIVE',
            refresh_tokens: []
        }
    ];

    const rpcChallenges = new Map();
    otpStoreService.supabaseClient = {
        rpc: async (fnName, params) => {
            if (fnName === 'request_otp_challenge') {
                rpcChallenges.set(params.p_identifier, { hash: params.p_hashed_code, used: false });
                return { data: { allowed: true, status: 200, requestCount: 1 }, error: null };
            }
            if (fnName === 'verify_otp_challenge') {
                const entry = rpcChallenges.get(params.p_identifier);
                if (!entry || entry.used || entry.hash !== params.p_incoming_hash) {
                    return { data: { valid: false, reason: 'INVALID_CODE', message: 'Invalid or expired OTP.' }, error: null };
                }
                entry.used = true;
                return { data: { valid: true, reason: 'VERIFIED', message: 'Verified.' }, error: null };
            }
            return { data: { allowed: true }, error: null };
        }
    };

    Schemas.User.findByMobile = async (phone) => {
        const norm = Schemas.canonicalPhone10(phone);
        return usersFixture.find(u => Schemas.canonicalPhone10(u.phone) === norm) || null;
    };
    Schemas.User.findOne = async (q = {}) => {
        if (q.phone) {
            const norm = Schemas.canonicalPhone10(q.phone);
            return usersFixture.find(u => Schemas.canonicalPhone10(u.phone) === norm) || null;
        }
        if (q.email) {
            return usersFixture.find(u => u.email.toLowerCase() === String(q.email).toLowerCase()) || null;
        }
        if (q.role) {
            return usersFixture.find(u => u.role === q.role) || null;
        }
        return null;
    };
    Schemas.User.findById = async (id) => usersFixture.find(u => u.id === id) || null;
    Schemas.User.findByIdAndUpdate = async (id, patch) => {
        const u = usersFixture.find(x => x.id === id);
        if (u && patch) Object.assign(u, patch);
        return u || null;
    };

    const server = http.createServer(app);
    await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
    const apiReq = createApiRequester(server);
    const stagingKey = 'staging_admin_login_fix_test_key_32chars_min!';

    try {
        process.env.NODE_ENV = 'staging';
        process.env.OTP_DELIVERY_MODE = 'on_screen';
        process.env.STAGING_OTP_ACCESS_KEY = stagingKey;
        process.env.JWT_SECRET = 'staging_admin_login_fix_jwt_secret_key_2026!';
        process.env.REFRESH_SECRET = 'staging_admin_login_fix_refresh_secret_2026!';
        process.env.OTP_SALT = 'staging_admin_login_fix_otp_salt_key_2026!';

        // Scenario A: ADMIN_PHONE env var set to a DIFFERENT number (reproduces the exact Render staging bug)
        // AND Scenario B: ADMIN_PHONE set to placeholder "+91XXXXXXXXXX"
        // AND Scenario C: ADMIN_PHONE unset
        const envConfigs = ['9999988888', '+91XXXXXXXXXX', ''];
        const phoneInputs = ['+91 92810 30535', '9281030535', '00919281030535'];

        for (let i = 0; i < envConfigs.length; i++) {
            if (envConfigs[i]) process.env.ADMIN_PHONE = envConfigs[i];
            else delete process.env.ADMIN_PHONE;

            const phoneInput = phoneInputs[i];
            const otpReq = await apiReq(
                'POST',
                '/api/v1/auth/otp/request',
                { 'x-staging-otp-key': stagingKey },
                { phone: phoneInput }
            );
            assert.strictEqual(otpReq.status, 200, `OTP request failed for ${phoneInput}`);
            assert.strictEqual(otpReq.json.success, true);
            assert.strictEqual(otpReq.json.isAdmin, true, `Must detect active DB ADMIN even with ADMIN_PHONE="${envConfigs[i]}"`);

            const otpVerify = await apiReq(
                'POST',
                '/api/v1/auth/otp/verify',
                {},
                { phone: phoneInput, code: otpReq.json.otp, role: 'Admin' }
            );
            assert.strictEqual(otpVerify.status, 200, `OTP verify failed for ${phoneInput}: ${JSON.stringify(otpVerify.json)}`);
            assert.strictEqual(otpVerify.json.success, true);
            assert.strictEqual(otpVerify.json.isAdmin, true);
            assert.strictEqual(otpVerify.json.user.id, '339f745b-2192-4055-abec-d7e4adc6c837');
            assert.strictEqual(otpVerify.json.user.role, 'ADMIN');

            const decoded = jwt.verify(otpVerify.json.accessToken, getJwtSecret());
            assert.strictEqual(decoded.id, '339f745b-2192-4055-abec-d7e4adc6c837');
            assert.strictEqual(decoded.role, 'ADMIN');

            // Verify generated JWT grants access to protected Main Admin route
            const adminApiRes = await apiReq(
                'GET',
                '/api/v1/admin/sub-admins',
                { Authorization: `Bearer ${otpVerify.json.accessToken}` }
            );
            assert.strictEqual(adminApiRes.status, 200, 'Verified Admin JWT must access protected Admin endpoints');
        }

        // Scenario D: Secondary Admin with role 'super_admin' and formatted phone '+91 98111 22233' succeeds
        process.env.ADMIN_PHONE = '9281030535';
        const superReq = await apiReq('POST', '/api/v1/auth/otp/request', { 'x-staging-otp-key': stagingKey }, { phone: '9811122233' });
        assert.strictEqual(superReq.status, 200);
        assert.strictEqual(superReq.json.isAdmin, true);

        const superVerify = await apiReq('POST', '/api/v1/auth/otp/verify', {}, { phone: '+91-98111-22233', code: superReq.json.otp });
        assert.strictEqual(superVerify.status, 200);
        assert.strictEqual(superVerify.json.isAdmin, true);
        assert.strictEqual(superVerify.json.user.id, 'admin-super-02');
        assert.strictEqual(superVerify.json.user.role, 'super_admin');

        // Scenario E: /auth/login with verified OTP also succeeds for DB Admin even with mismatched ADMIN_PHONE
        process.env.ADMIN_PHONE = '1111122222';
        const loginOtpReq = await apiReq('POST', '/api/v1/auth/otp/request', { 'x-staging-otp-key': stagingKey }, { phone: '+919281030535' });
        const loginRes = await apiReq('POST', '/api/v1/auth/login', {}, {
            phone: '+91 92810 30535',
            otp: loginOtpReq.json.otp,
            role: 'Admin'
        });
        assert.strictEqual(loginRes.status, 200, `Admin /auth/login failed: ${JSON.stringify(loginRes.json)}`);
        assert.strictEqual(loginRes.json.success, true);
        assert.strictEqual(loginRes.json.user.id, '339f745b-2192-4055-abec-d7e4adc6c837');
        assert.strictEqual(loginRes.json.user.role, 'ADMIN');

        // Scenario F: Deactivated Admin is strictly rejected with 403 ACCOUNT_DEACTIVATED
        const inactiveReq = await apiReq('POST', '/api/v1/auth/otp/request', { 'x-staging-otp-key': stagingKey }, { phone: '9822233344' });
        assert.strictEqual(inactiveReq.status, 200);
        assert.strictEqual(inactiveReq.json.isAdmin, false, 'Deactivated Admin must NOT be marked isAdmin: true');

        const inactiveVerify = await apiReq('POST', '/api/v1/auth/otp/verify', {}, { phone: '9822233344', code: inactiveReq.json.otp });
        assert.strictEqual(inactiveVerify.status, 403);
        assert.strictEqual(inactiveVerify.json.code, 'ACCOUNT_DEACTIVATED');
        assert.strictEqual(inactiveVerify.json.accessToken, undefined);

        // Scenario G: Security — Ordinary Patient cannot gain Admin access via OTP
        const patReq = await apiReq('POST', '/api/v1/auth/otp/request', { 'x-staging-otp-key': stagingKey }, { phone: '9844455566' });
        assert.strictEqual(patReq.status, 200);
        assert.strictEqual(patReq.json.isAdmin, false);

        const patAdminAttempt = await apiReq('POST', '/api/v1/auth/otp/verify', {}, {
            phone: '9844455566',
            code: patReq.json.otp,
            role: 'Admin'
        });
        assert.strictEqual(patAdminAttempt.status, 403);
        assert.match(patAdminAttempt.json.message, /Unauthorized Admin access/i);
        assert.strictEqual(patAdminAttempt.json.accessToken, undefined);

        // Ordinary Patient normal login still succeeds
        const patReq2 = await apiReq('POST', '/api/v1/auth/otp/request', { 'x-staging-otp-key': stagingKey }, { phone: '9844455566' });
        const patNormalVerify = await apiReq('POST', '/api/v1/auth/otp/verify', {}, {
            phone: '9844455566',
            code: patReq2.json.otp,
            role: 'Patient',
            autoCreatePatient: true
        });
        assert.strictEqual(patNormalVerify.status, 200);
        assert.strictEqual(patNormalVerify.json.success, true);
        assert.strictEqual(patNormalVerify.json.isAdmin, false);
        assert.strictEqual(patNormalVerify.json.user.role, 'Patient');

        // Scenario H: Security — Unregistered mobile number cannot gain Admin access via OTP
        const unknownReq = await apiReq('POST', '/api/v1/auth/otp/request', { 'x-staging-otp-key': stagingKey }, { phone: '9855566677' });
        assert.strictEqual(unknownReq.status, 200);
        assert.strictEqual(unknownReq.json.isAdmin, false);

        const unknownAdminAttempt = await apiReq('POST', '/api/v1/auth/otp/verify', {}, {
            phone: '9855566677',
            code: unknownReq.json.otp,
            role: 'Admin'
        });
        assert.strictEqual(unknownAdminAttempt.status, 403);
        assert.match(unknownAdminAttempt.json.message, /Unauthorized Admin access/i);
        assert.strictEqual(unknownAdminAttempt.json.accessToken, undefined);

        // Scenario I: Active Sub-Admin OTP login still works cleanly
        const subReq = await apiReq('POST', '/api/v1/auth/otp/request', { 'x-staging-otp-key': stagingKey }, { phone: '9833344455' });
        const subVerify = await apiReq('POST', '/api/v1/auth/otp/verify', {}, {
            phone: '9833344455',
            code: subReq.json.otp
        });
        assert.strictEqual(subVerify.status, 200);
        assert.strictEqual(subVerify.json.isSubAdmin, true);
        assert.strictEqual(subVerify.json.isAdmin, false);
        assert.strictEqual(subVerify.json.user.role, 'Sub-Admin');
    } finally {
        Schemas.User.findByMobile = origFindByMobile;
        Schemas.User.findOne = origFindOne;
        Schemas.User.findById = origFindById;
        Schemas.User.findByIdAndUpdate = origUpdate;
        otpStoreService.supabaseClient = origRpc;
        if (prevEnv !== undefined) process.env.NODE_ENV = prevEnv; else delete process.env.NODE_ENV;
        if (prevMode !== undefined) process.env.OTP_DELIVERY_MODE = prevMode; else delete process.env.OTP_DELIVERY_MODE;
        if (prevStagingKey !== undefined) process.env.STAGING_OTP_ACCESS_KEY = prevStagingKey; else delete process.env.STAGING_OTP_ACCESS_KEY;
        if (prevAdminPhone !== undefined) process.env.ADMIN_PHONE = prevAdminPhone; else delete process.env.ADMIN_PHONE;
        if (prevJwt !== undefined) process.env.JWT_SECRET = prevJwt; else delete process.env.JWT_SECRET;
        if (prevRefresh !== undefined) process.env.REFRESH_SECRET = prevRefresh; else delete process.env.REFRESH_SECRET;
        if (prevSalt !== undefined) process.env.OTP_SALT = prevSalt; else delete process.env.OTP_SALT;
        await new Promise((resolve) => server.close(resolve));
    }
});

test('3. evaluateMainAdminAuthorization rejects phone mismatch, missing ID, non-admin role, and inactive status', () => {
    const validAdmin = { id: 'adm-1', role: 'ADMIN', phone: '+91 92810 30535', status: 'ACTIVE' };

    assert.strictEqual(
        authController._evaluateMainAdminAuthorization({ user: validAdmin, normalizedPhone: '9281030535', isPhoneAuth: true }).authorized,
        true
    );
    assert.strictEqual(
        authController._evaluateMainAdminAuthorization({ user: validAdmin, normalizedPhone: '9999900000', isPhoneAuth: true }).reason,
        'PHONE_MISMATCH'
    );
    assert.strictEqual(
        authController._evaluateMainAdminAuthorization({ user: { ...validAdmin, status: 'INACTIVE' }, normalizedPhone: '9281030535', isPhoneAuth: true }).reason,
        'ACCOUNT_DEACTIVATED'
    );
    assert.strictEqual(
        authController._evaluateMainAdminAuthorization({ user: { ...validAdmin, role: 'Patient' }, normalizedPhone: '9281030535', isPhoneAuth: true }).reason,
        'NOT_MAIN_ADMIN_ROLE'
    );
    assert.strictEqual(
        authController._evaluateMainAdminAuthorization({ user: { ...validAdmin, id: '' }, normalizedPhone: '9281030535', isPhoneAuth: true }).reason,
        'USER_NOT_FOUND'
    );
});
