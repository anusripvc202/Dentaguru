/**
 * Comprehensive Backend Unit & Integration Tests for GS HEALTH Mobile SMS OTP Verification
 * Covers Supabase PostgreSQL RPC storage, concurrency, replay protection, SMS cleanup & RLS enforcement.
 */
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const https = require('https');
const { EventEmitter } = require('events');
const { sendRealSmsOtp, buildOtpMessage, normalizePhoneNumber } = require('../src/services/smsService');
const auth = require('../src/controllers/authController');
const {
    OtpStoreService,
    otpStoreService,
    hashOtp,
    localOtpMap,
    localLimitMap
} = require('../src/services/otpStoreService');

// Keep Tests 1–23 deterministic regardless of local backend/.env OTP_DELIVERY_MODE setting;
// Tests 24–28 explicitly toggle OTP_DELIVERY_MODE='on_screen'.
delete process.env.OTP_DELIVERY_MODE;

console.log('=== STARTING GS HEALTH SMS OTP & SUPABASE STORAGE TESTS ===\n');

async function runTests() {
    let passed = 0;
    let failed = 0;

    async function asyncTest(name, fn) {
        try {
            await fn();
            console.log(`✓ ${name}`);
            passed++;
        } catch (e) {
            console.error(`✗ ${name}:`, e.message);
            failed++;
        }
    }

    // 1. Phone Number Normalization & Validation
    await asyncTest('1. Normalizes 10-digit Indian mobile number to E.164 (+91)', async () => {
        const res = normalizePhoneNumber('9063663180');
        assert.strictEqual(res.isValid, true);
        assert.strictEqual(res.cleanDigits, '9063663180');
        assert.strictEqual(res.e164, '+919063663180');
    });

    await asyncTest('2. Normalizes 12-digit Indian mobile with prefix 91', async () => {
        const res = normalizePhoneNumber('+91 90636 63180');
        assert.strictEqual(res.isValid, true);
        assert.strictEqual(res.cleanDigits, '919063663180');
        assert.strictEqual(res.e164, '+919063663180');
    });

    await asyncTest('3. Rejects invalid short numbers (<10 digits)', async () => {
        const res = normalizePhoneNumber('12345');
        assert.strictEqual(res.isValid, false);
    });

    // 2. Message Format & Dispatch
    await asyncTest('4. Message format strictly matches specification', async () => {
        const msg = buildOtpMessage('123456');
        assert.strictEqual(
            msg,
            'Your GS HEALTH verification code is 123456. It is valid for 5 minutes. Do not share this code with anyone.'
        );
    });

    await asyncTest('5. SMS service validates number and formats dispatch', async () => {
        const res = await sendRealSmsOtp('9063663180', '654321');
        assert.strictEqual(res.success, true);
    });

    // 3. Controller OTP Request & Cooldown
    await asyncTest('6. Request OTP generates 6-digit code without exposing it in API response', async () => {
        localOtpMap.clear();
        localLimitMap.clear();
        const req = { body: { phone: '9063663180' } };
        let responseStatus = 200;
        let responseJson = null;

        const res = {
            status: (code) => { responseStatus = code; return res; },
            json: (data) => { responseJson = data; return res; }
        };

        await auth.requestOTP(req, res);
        assert.strictEqual(responseStatus, 200);
        assert.strictEqual(responseJson.success, true);
        assert.strictEqual(responseJson.message, 'OTP sent successfully to your mobile number.');
        assert.strictEqual(responseJson.otp, undefined, 'OTP must not be exposed in API response');
    });

    await asyncTest('7. Cooldown blocks immediate subsequent OTP request within 30 seconds', async () => {
        const req = { body: { phone: '9063663180' } };
        let responseStatus = 200;
        let responseJson = null;

        const res = {
            status: (code) => { responseStatus = code; return res; },
            json: (data) => { responseJson = data; return res; }
        };

        await auth.requestOTP(req, res);
        assert.strictEqual(responseStatus, 429, 'Expected 429 Too Many Requests due to cooldown');
        assert.ok(responseJson.message.includes('seconds before requesting a new OTP'));
    });

    await asyncTest('8. Invalid/wrong OTP is rejected with remaining attempt count', async () => {
        const req = { body: { phone: '9063663180', code: '000000' } };
        let responseStatus = 200;
        let responseJson = null;

        const res = {
            status: (code) => { responseStatus = code; return res; },
            json: (data) => { responseJson = data; return res; }
        };

        await auth.verifyOTP(req, res);
        assert.strictEqual(responseStatus, 400);
        assert.strictEqual(responseJson.success, false);
        assert.ok(responseJson.message.includes('attempt(s) remaining') || responseJson.message.includes('Invalid'));
    });

    await asyncTest('9. Non 6-digit code format is rejected immediately', async () => {
        const req = { body: { phone: '9063663180', code: '1234' } };
        let responseStatus = 200;
        let responseJson = null;

        const res = {
            status: (code) => { responseStatus = code; return res; },
            json: (data) => { responseJson = data; return res; }
        };

        await auth.verifyOTP(req, res);
        assert.strictEqual(responseStatus, 400);
        assert.strictEqual(responseJson.success, false);
        assert.ok(responseJson.message.includes('6-digit'));
    });

    // 4. Production Safety & Supabase Storage Checks
    await asyncTest('10. Production mode throws configuration error when Supabase service_role key is missing', async () => {
        const prevUrl = process.env.SUPABASE_URL;
        const prevService = process.env.SUPABASE_SERVICE_ROLE_KEY;
        const prevAnon = process.env.SUPABASE_ANON_KEY;

        process.env.SUPABASE_URL = 'https://example.supabase.co';
        process.env.SUPABASE_ANON_KEY = 'anon-key';
        process.env.SUPABASE_SERVICE_ROLE_KEY = 'anon-key'; // Simulates missing elevated service key

        try {
            const prodService = new OtpStoreService({ isProduction: true });
            assert.throws(() => {
                prodService._ensureProductionConfig();
            }, /Production Configuration Error: Valid SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY/);
        } finally {
            if (prevUrl !== undefined) process.env.SUPABASE_URL = prevUrl; else delete process.env.SUPABASE_URL;
            if (prevService !== undefined) process.env.SUPABASE_SERVICE_ROLE_KEY = prevService; else delete process.env.SUPABASE_SERVICE_ROLE_KEY;
            if (prevAnon !== undefined) process.env.SUPABASE_ANON_KEY = prevAnon; else delete process.env.SUPABASE_ANON_KEY;
        }
    });

    await asyncTest('11. Successful verification triggers immediate single-use replay protection', async () => {
        const svc = new OtpStoreService({ isProduction: false, forceMemoryInDev: true });
        const testPhone = '9000000001';
        const code = '556677';
        const r = await svc.requestAndStoreOtp(testPhone, code);
        assert.strictEqual(r.allowed, true);

        const v1 = await svc.verifyOtp(testPhone, code);
        assert.strictEqual(v1.valid, true);

        const v2 = await svc.verifyOtp(testPhone, code);
        assert.strictEqual(v2.valid, false, 'Replay attempt must be rejected immediately');
    });

    await asyncTest('12. Reaching maximum 5 incorrect attempts locks out and deletes OTP challenge', async () => {
        const svc = new OtpStoreService({ isProduction: false, forceMemoryInDev: true });
        const testPhone = '9000000002';
        const correctCode = '112233';
        await svc.requestAndStoreOtp(testPhone, correctCode);

        for (let i = 1; i <= 5; i++) {
            const failRes = await svc.verifyOtp(testPhone, '999999');
            assert.strictEqual(failRes.valid, false);
        }

        const finalCheck = await svc.verifyOtp(testPhone, correctCode);
        assert.strictEqual(finalCheck.valid, false, 'Locked-out OTP must reject even correct code');
    });

    await asyncTest('13. Expired OTP is rejected after 5-minute TTL', async () => {
        const svc = new OtpStoreService({ isProduction: false, forceMemoryInDev: true });
        const testPhone = '9000000003';
        const code = '445566';
        await svc.requestAndStoreOtp(testPhone, code);

        // Expire entry manually beyond 5 minutes
        const entry = localOtpMap.get(testPhone);
        assert.ok(entry, 'OTP entry should exist');
        assert.notStrictEqual(entry.hashedCode, code, 'Raw OTP must never be stored');
        entry.expiresAt = Date.now() - 1000;

        const expiredRes = await svc.verifyOtp(testPhone, code);
        assert.strictEqual(expiredRes.valid, false);
        assert.ok(expiredRes.message.includes('expired'));
    });

    await asyncTest('14. Rate limit strictly blocks 6th request within 15-minute window', async () => {
        const svc = new OtpStoreService({ isProduction: false, forceMemoryInDev: true });
        const testPhone = '9000000004';
        localLimitMap.delete(testPhone);

        for (let i = 1; i <= 5; i++) {
            const reqRes = await svc.requestAndStoreOtp(testPhone, '123456');
            assert.strictEqual(reqRes.allowed, true, `Request #${i} should be allowed`);
            // Simulate >30s elapsed between retries so we hit the 5-per-15-min window
            const lim = localLimitMap.get(testPhone);
            lim.lastRequestedAt = Date.now() - 35000;
        }

        const sixth = await svc.requestAndStoreOtp(testPhone, '123456');
        assert.strictEqual(sixth.allowed, false);
        assert.strictEqual(sixth.status, 429);
        assert.ok(sixth.message.includes('15 minutes'));
    });

    await asyncTest('15. HMAC-SHA256 salted hash consistency and RPC raw-OTP exclusion verified', async () => {
        const h1 = hashOtp('123456');
        const h2 = hashOtp('123456');
        const h3 = hashOtp('654321');
        assert.strictEqual(h1, h2);
        assert.notStrictEqual(h1, h3);
        assert.strictEqual(h1.length, 64);

        let capturedRpcArgs = null;
        const mockSupabase = {
            rpc: async (fnName, params) => {
                capturedRpcArgs = { fnName, params };
                return { data: { allowed: true, status: 200 }, error: null };
            }
        };
        const rpcSvc = new OtpStoreService({ supabaseClient: mockSupabase, isProduction: true });
        await rpcSvc.requestAndStoreOtp('+91 98765 43210', '887766');
        assert.strictEqual(capturedRpcArgs.fnName, 'request_otp_challenge');
        assert.strictEqual(capturedRpcArgs.params.p_identifier, '9876543210');
        assert.strictEqual(capturedRpcArgs.params.p_hashed_code, hashOtp('887766'));
        assert.ok(!JSON.stringify(capturedRpcArgs).includes('887766'), 'Raw OTP must never be sent to Supabase RPC');
    });

    await asyncTest('16. Concurrent OTP requests serialize atomically (only 1 allowed inside cooldown)', async () => {
        const svc = new OtpStoreService({ isProduction: false, forceMemoryInDev: true });
        const testPhone = '9000000005';
        localLimitMap.delete(testPhone);
        localOtpMap.delete(testPhone);

        const results = await Promise.all([
            svc.requestAndStoreOtp(testPhone, '111111'),
            svc.requestAndStoreOtp(testPhone, '222222'),
            svc.requestAndStoreOtp(testPhone, '333333'),
            svc.requestAndStoreOtp(testPhone, '444444'),
            svc.requestAndStoreOtp(testPhone, '555555')
        ]);

        const allowedCount = results.filter(r => r.allowed === true).length;
        const blockedCount = results.filter(r => r.allowed === false && r.status === 429).length;
        assert.strictEqual(allowedCount, 1, 'Exactly one concurrent request must succeed');
        assert.strictEqual(blockedCount, 4, 'Remaining 4 concurrent requests must hit 429 cooldown');
    });

    await asyncTest('17. Concurrent OTP verifications serialize atomically (single-use guaranteed)', async () => {
        const svc = new OtpStoreService({ isProduction: false, forceMemoryInDev: true });
        const testPhone = '9000000006';
        localLimitMap.delete(testPhone);
        localOtpMap.delete(testPhone);

        await svc.requestAndStoreOtp(testPhone, '778899');

        const results = await Promise.all([
            svc.verifyOtp(testPhone, '778899'),
            svc.verifyOtp(testPhone, '778899'),
            svc.verifyOtp(testPhone, '778899'),
            svc.verifyOtp(testPhone, '778899')
        ]);

        const validCount = results.filter(r => r.valid === true).length;
        const rejectedCount = results.filter(r => r.valid === false).length;
        assert.strictEqual(validCount, 1, 'Exactly one concurrent verification must succeed');
        assert.strictEqual(rejectedCount, 3, 'Concurrent replay attempts must be rejected');
    });

    await asyncTest('18. SMS carrier failure invalidates OTP challenge & rolls back rate limit cleanly', async () => {
        const testPhone = '9000000007';
        localLimitMap.delete(testPhone);
        localOtpMap.delete(testPhone);

        const prevKey = process.env.FAST2SMS_API_KEY;
        const prevTwilio = process.env.TWILIO_ACCOUNT_SID;
        const prevHttpsRequest = https.request;

        process.env.FAST2SMS_API_KEY = 'dummy_test_key_for_failure_sim';
        delete process.env.TWILIO_ACCOUNT_SID;

        // Mock Fast2SMS HTTP 400 rejection
        https.request = (_opts, cb) => {
            const req = new EventEmitter();
            req.write = () => { };
            req.end = () => {
                const res = new EventEmitter();
                res.statusCode = 400;
                cb(res);
                res.emit('data', JSON.stringify({ return: false, message: 'Carrier rejected test request' }));
                res.emit('end');
            };
            return req;
        };

        try {
            const req = { body: { phone: testPhone } };
            let status = 200;
            let body = null;
            const res = {
                status: (c) => { status = c; return res; },
                json: (d) => { body = d; return res; }
            };

            await auth.requestOTP(req, res);
            assert.strictEqual(status, 502, 'Failed SMS dispatch must return HTTP 502');
            assert.strictEqual(body.success, false);
            assert.ok(body.message.includes('Carrier rejected'));
            assert.strictEqual(localOtpMap.has(testPhone), false, 'OTP challenge must be invalidated on SMS failure');
            const limitAfterFail = await otpStoreService.checkRateLimit(testPhone);
            assert.strictEqual(limitAfterFail.allowed, true, 'Cooldown must roll back after SMS failure');
        } finally {
            https.request = prevHttpsRequest;
            if (prevKey !== undefined) process.env.FAST2SMS_API_KEY = prevKey; else delete process.env.FAST2SMS_API_KEY;
            if (prevTwilio !== undefined) process.env.TWILIO_ACCOUNT_SID = prevTwilio;
        }
    });

    await asyncTest('19. Unauthorized DB/RPC errors fail closed in production & SQL migration enforces strict RLS', async () => {
        // 19A: Production RPC error (e.g. permission denied for anon/authenticated) must throw, never fall back
        const unauthMockSupabase = {
            rpc: async () => ({
                data: null,
                error: { code: '42501', message: 'permission denied for function request_otp_challenge' }
            })
        };
        const prodSvc = new OtpStoreService({ supabaseClient: unauthMockSupabase, isProduction: true });
        await assert.rejects(
            () => prodSvc.requestAndStoreOtp('9000000008', '123456'),
            /permission denied/
        );

        // 19B: Verify migration SQL locks down tables & RPCs against anon/authenticated
        const sqlPath = path.resolve(__dirname, '../migrations/02_supabase_otp_storage.sql');
        const sql = fs.readFileSync(sqlPath, 'utf8');
        assert.ok(sql.includes('ALTER TABLE public.otp_challenges ENABLE ROW LEVEL SECURITY'), 'RLS must be enabled on otp_challenges');
        assert.ok(sql.includes('ALTER TABLE public.otp_rate_limits ENABLE ROW LEVEL SECURITY'), 'RLS must be enabled on otp_rate_limits');
        assert.ok(sql.includes('REVOKE ALL ON TABLE public.otp_challenges FROM PUBLIC, anon, authenticated'));
        assert.ok(sql.includes('REVOKE ALL ON TABLE public.otp_rate_limits FROM PUBLIC, anon, authenticated'));
        assert.ok(sql.includes('REVOKE ALL ON FUNCTION public.verify_otp_challenge(TEXT, TEXT) FROM PUBLIC, anon, authenticated'));
        assert.ok(sql.includes('GRANT EXECUTE ON FUNCTION public.verify_otp_challenge(TEXT, TEXT) TO service_role'));
        assert.ok(!/CREATE POLICY .* USING\s*\(\s*true\s*\)/i.test(sql), 'Must not contain permissive USING (true) policy');
    });

    await asyncTest('20. Production mode refuses SMS simulation when gateway keys are absent', async () => {
        const prevEnv = process.env.NODE_ENV;
        const prevKey = process.env.FAST2SMS_API_KEY;
        const prevTwilio = process.env.TWILIO_ACCOUNT_SID;
        process.env.NODE_ENV = 'production';
        delete process.env.FAST2SMS_API_KEY;
        delete process.env.TWILIO_ACCOUNT_SID;

        try {
            const res = await sendRealSmsOtp('9063663180', '123456');
            assert.strictEqual(res.success, false, 'Production must not simulate SMS success');
            assert.strictEqual(res.simulated, false);
        } finally {
            process.env.NODE_ENV = prevEnv;
            if (prevKey !== undefined) process.env.FAST2SMS_API_KEY = prevKey;
            if (prevTwilio !== undefined) process.env.TWILIO_ACCOUNT_SID = prevTwilio;
        }
    });

    await asyncTest('21. Request OTP rejects short invalid phone number with 400', async () => {
        const req = { body: { phone: '12345' } };
        let responseStatus = 200;
        let responseJson = null;
        const res = {
            status: (code) => { responseStatus = code; return res; },
            json: (data) => { responseJson = data; return res; }
        };
        await auth.requestOTP(req, res);
        assert.strictEqual(responseStatus, 400);
        assert.strictEqual(responseJson.success, false);
    });

    await asyncTest('22. Regression: Single wrong OTP in verifyOTP, resetPassword & login increments attempts exactly once', async () => {
        const prevForceMemory = otpStoreService.forceMemoryInDev;
        otpStoreService.forceMemoryInDev = true;
        try {
        const testPhone = '9000000010';
        const correctCode = '654321';
        localOtpMap.delete(testPhone);
        localLimitMap.delete(testPhone);

        await otpStoreService.requestAndStoreOtp(testPhone, correctCode);

        // 22A: verifyOTP with unnormalized +91 phone must increment attempts by 1 (not 2)
        let status = 200;
        let body = null;
        const makeRes = () => ({
            status: (c) => { status = c; return makeRes(); },
            json: (d) => { body = d; return d; }
        });
        await auth.verifyOTP({ body: { phone: `+91 ${testPhone}`, code: '000000' } }, makeRes());
        assert.strictEqual(status, 400);
        assert.ok(body.message.includes('4 attempt(s) remaining'), `Expected 4 attempts remaining, got: ${body.message}`);
        assert.strictEqual(localOtpMap.get(testPhone).attempts, 1, 'verifyOTP must increment attempts strictly once');

        // 22B: resetPassword with both email & phone (where email has no challenge) increments phone attempts strictly once
        status = 200;
        await auth.resetPassword({
            body: { email: 'user@example.com', phone: `+91${testPhone}`, code: '000000', newPassword: 'password123' }
        }, makeRes());
        assert.strictEqual(status, 400);
        assert.strictEqual(localOtpMap.get(testPhone).attempts, 2, 'resetPassword must increment attempts strictly once');

        // 22C: Spy on otpStoreService.verifyOtp during login & resetPassword to verify 1 invocation per submission
        const origVerify = otpStoreService.verifyOtp.bind(otpStoreService);
        let verifyCallCount = 0;
        otpStoreService.verifyOtp = async (...args) => {
            verifyCallCount++;
            return origVerify(...args);
        };
        try {
            await auth.verifyOTP({ body: { phone: `+91${testPhone}`, code: '000000' } }, makeRes());
            assert.strictEqual(verifyCallCount, 1, 'verifyOTP must invoke verifyOtp exactly once');
            assert.strictEqual(localOtpMap.get(testPhone).attempts, 3);

            verifyCallCount = 0;
            await auth.resetPassword({
                body: { phone: testPhone, code: '000000', newPassword: 'password123' }
            }, makeRes());
            assert.strictEqual(verifyCallCount, 1, 'resetPassword must invoke verifyOtp exactly once');
            assert.strictEqual(localOtpMap.get(testPhone).attempts, 4);

            // 5th attempt with valid code succeeds because prior 4 wrong attempts were not double-counted
            verifyCallCount = 0;
            status = 200;
            body = null;
            await auth.verifyOTP({ body: { phone: testPhone, code: correctCode } }, makeRes());
            assert.strictEqual(verifyCallCount, 1);
            assert.strictEqual(status, 200, '5th attempt with valid code succeeds because prior 4 wrong attempts were not double-counted');
            assert.strictEqual(body.success, true);

            // 22D: Verify auth.login with OTP invokes verifyOtp exactly once and increments attempts by 1
            const loginPhone = '9000000011';
            localOtpMap.delete(loginPhone);
            localLimitMap.delete(loginPhone);
            await otpStoreService.requestAndStoreOtp(loginPhone, '112244');

            const { User } = require('../src/models/Schemas');
            const origFindOne = User.findOne;
            User.findOne = async () => ({
                id: 'test-login-user',
                name: 'Test User',
                email: 'login@example.com',
                phone: `+91${loginPhone}`,
                role: 'Patient',
                status: 'ACTIVE'
            });
            try {
                verifyCallCount = 0;
                status = 200;
                await auth.login({ body: { phone: `+91 ${loginPhone}`, otp: '000000' } }, makeRes());
                assert.strictEqual(status, 400);
                assert.strictEqual(verifyCallCount, 1, 'login must invoke verifyOtp exactly once');
                assert.strictEqual(localOtpMap.get(loginPhone).attempts, 1, 'login must increment attempts strictly once');
            } finally {
                User.findOne = origFindOne;
            }
        } finally {
            otpStoreService.verifyOtp = origVerify;
        }
        } finally {
            otpStoreService.forceMemoryInDev = prevForceMemory;
        }
    });

    await asyncTest('23. Migration uses bounded SKIP LOCKED cleanup and rollback signatures match', async () => {
        const sqlPath = path.resolve(__dirname, '../migrations/02_supabase_otp_storage.sql');
        const rollbackPath = path.resolve(__dirname, '../migrations/02_rollback_supabase_otp_storage.sql');
        const sql = fs.readFileSync(sqlPath, 'utf8');
        const rollbackSql = fs.readFileSync(rollbackPath, 'utf8');

        assert.ok(sql.includes('LIMIT 50'), 'Stale cleanup must be bounded with LIMIT 50');
        assert.ok(sql.includes('FOR UPDATE SKIP LOCKED'), 'Stale cleanup must use FOR UPDATE SKIP LOCKED');
        assert.ok(rollbackSql.includes('DROP FUNCTION IF EXISTS public.invalidate_otp_challenge(TEXT, BOOLEAN)'));
        assert.ok(rollbackSql.includes('DROP FUNCTION IF EXISTS public.verify_otp_challenge(TEXT, TEXT)'));
        assert.ok(rollbackSql.includes('DROP FUNCTION IF EXISTS public.request_otp_challenge(TEXT, TEXT, INTEGER, INTEGER, INTEGER, INTEGER, INTEGER)'));
        assert.ok(rollbackSql.includes('DROP FUNCTION IF EXISTS public.check_otp_rate_limit(TEXT, INTEGER, INTEGER, INTEGER)'));
        assert.ok(rollbackSql.includes('DROP TABLE IF EXISTS public.otp_challenges'));
        assert.ok(rollbackSql.includes('DROP TABLE IF EXISTS public.otp_rate_limits'));
    });

    await asyncTest('24. On-screen testing mode (NODE_ENV=development & OTP_DELIVERY_MODE=on_screen) blocks Fast2SMS/Twilio, uses Supabase RPC hash storage, and returns 6-digit OTP', async () => {
        const { isOnScreenOtpTestMode } = require('../src/services/otpStoreService');
        const prevEnv = process.env.NODE_ENV;
        const prevMode = process.env.OTP_DELIVERY_MODE;
        const prevFast2Sms = process.env.FAST2SMS_API_KEY;
        const prevTwilioSid = process.env.TWILIO_ACCOUNT_SID;
        const prevTwilioToken = process.env.TWILIO_AUTH_TOKEN;
        const prevTwilioFrom = process.env.TWILIO_PHONE_NUMBER;
        const prevSupaUrl = process.env.SUPABASE_URL;
        const prevSupaService = process.env.SUPABASE_SERVICE_ROLE_KEY;
        const prevSupaAnon = process.env.SUPABASE_ANON_KEY;
        const prevOtpSalt = process.env.OTP_SALT;
        const prevHttpsRequest = https.request;
        const prevClient = otpStoreService.supabaseClient;

        process.env.NODE_ENV = 'development';
        process.env.OTP_DELIVERY_MODE = 'on_screen';
        process.env.FAST2SMS_API_KEY = 'must_be_blocked_fast2sms_key';
        process.env.TWILIO_ACCOUNT_SID = 'AC_must_be_blocked_twilio_sid';
        process.env.TWILIO_AUTH_TOKEN = 'must_be_blocked_twilio_token';
        process.env.TWILIO_PHONE_NUMBER = '+15550001234';
        process.env.SUPABASE_URL = 'https://test-project.supabase.co';
        process.env.SUPABASE_SERVICE_ROLE_KEY = 'test_service_role_key_xyz';
        process.env.SUPABASE_ANON_KEY = 'test_anon_key_abc';

        let externalSmsCalled = false;
        https.request = () => {
            externalSmsCalled = true;
            throw new Error('Fast2SMS/Twilio HTTP calls must NEVER happen when OTP_DELIVERY_MODE=on_screen');
        };

        const rpcChallenges = new Map();
        otpStoreService.supabaseClient = {
            rpc: async (fnName, params) => {
                if (fnName === 'request_otp_challenge') {
                    assert.strictEqual(params.p_hashed_code.length, 64, 'Must store 64-char HMAC-SHA256 hash in Supabase RPC');
                    assert.strictEqual(params.p_ttl_seconds, 300);
                    assert.strictEqual(params.p_cooldown_seconds, 30);
                    assert.strictEqual(params.p_max_attempts, 5);
                    rpcChallenges.set(params.p_identifier, { hash: params.p_hashed_code, used: false });
                    return { data: { allowed: true, status: 200, requestCount: 1 }, error: null };
                }
                if (fnName === 'verify_otp_challenge') {
                    const rec = rpcChallenges.get(params.p_identifier);
                    if (!rec || rec.used) return { data: { valid: false, reason: 'NOT_FOUND', message: 'Invalid or expired OTP.' }, error: null };
                    if (rec.hash !== params.p_incoming_hash) return { data: { valid: false, reason: 'INVALID_CODE', message: 'Invalid OTP code.' }, error: null };
                    rec.used = true;
                    rpcChallenges.delete(params.p_identifier);
                    return { data: { valid: true, reason: 'VERIFIED', message: 'OTP verified successfully.' }, error: null };
                }
                return { data: { allowed: true }, error: null };
            }
        };

        try {
            assert.strictEqual(isOnScreenOtpTestMode(), true);
            const anyPhone = '8765432190';
            let status = 200;
            let body = null;
            const res = {
                status: (c) => { status = c; return res; },
                json: (d) => { body = d; return res; }
            };

            await auth.requestOTP({ body: { phone: anyPhone } }, res);
            assert.strictEqual(status, 200);
            assert.strictEqual(body.success, true);
            assert.strictEqual(body.deliveryMode, 'on_screen');
            assert.match(String(body.otp), /^\d{6}$/, 'Must return random 6-digit OTP for testing');
            assert.strictEqual(externalSmsCalled, false, 'Fast2SMS/Twilio must be blocked in on_screen mode');
            assert.strictEqual(rpcChallenges.get(anyPhone).hash, hashOtp(body.otp), 'Stored hash must match salted HMAC-SHA256');

            // Verify single-use replay protection via Supabase RPC
            const v1 = await otpStoreService.verifyOtp(anyPhone, body.otp);
            assert.strictEqual(v1.valid, true);
            const v2 = await otpStoreService.verifyOtp(anyPhone, body.otp);
            assert.strictEqual(v2.valid, false, 'Replay attempt must be rejected');
        } finally {
            https.request = prevHttpsRequest;
            otpStoreService.supabaseClient = prevClient;
            if (prevEnv !== undefined) process.env.NODE_ENV = prevEnv; else delete process.env.NODE_ENV;
            if (prevMode !== undefined) process.env.OTP_DELIVERY_MODE = prevMode; else delete process.env.OTP_DELIVERY_MODE;
            if (prevFast2Sms !== undefined) process.env.FAST2SMS_API_KEY = prevFast2Sms; else delete process.env.FAST2SMS_API_KEY;
            if (prevTwilioSid !== undefined) process.env.TWILIO_ACCOUNT_SID = prevTwilioSid; else delete process.env.TWILIO_ACCOUNT_SID;
            if (prevTwilioToken !== undefined) process.env.TWILIO_AUTH_TOKEN = prevTwilioToken; else delete process.env.TWILIO_AUTH_TOKEN;
            if (prevTwilioFrom !== undefined) process.env.TWILIO_PHONE_NUMBER = prevTwilioFrom; else delete process.env.TWILIO_PHONE_NUMBER;
            if (prevSupaUrl !== undefined) process.env.SUPABASE_URL = prevSupaUrl; else delete process.env.SUPABASE_URL;
            if (prevSupaService !== undefined) process.env.SUPABASE_SERVICE_ROLE_KEY = prevSupaService; else delete process.env.SUPABASE_SERVICE_ROLE_KEY;
            if (prevSupaAnon !== undefined) process.env.SUPABASE_ANON_KEY = prevSupaAnon; else delete process.env.SUPABASE_ANON_KEY;
            if (prevOtpSalt !== undefined) process.env.OTP_SALT = prevOtpSalt; else delete process.env.OTP_SALT;
        }
    });

    await asyncTest('25. On-screen testing mode enforces Supabase RPC storage with NO in-memory fallback', async () => {
        const prevEnv = process.env.NODE_ENV;
        const prevMode = process.env.OTP_DELIVERY_MODE;
        const prevSupaUrl = process.env.SUPABASE_URL;
        const prevSupaService = process.env.SUPABASE_SERVICE_ROLE_KEY;
        const prevSupaAnon = process.env.SUPABASE_ANON_KEY;
        const prevOtpSalt = process.env.OTP_SALT;

        process.env.NODE_ENV = 'development';
        process.env.OTP_DELIVERY_MODE = 'on_screen';
        process.env.SUPABASE_URL = 'https://placeholder.supabase.co';
        delete process.env.SUPABASE_SERVICE_ROLE_KEY;
        process.env.SUPABASE_ANON_KEY = 'anon_key';

        try {
            const testSvc = new OtpStoreService();
            await assert.rejects(
                () => testSvc.requestAndStoreOtp('9000000099', '123456'),
                /In-memory OTP fallback is disabled/
            );

            // Also verify missing/failing RPC throws instead of falling back to memory
            const brokenRpcSvc = new OtpStoreService({
                supabaseClient: {
                    rpc: async () => ({ data: null, error: { code: 'PGRST202', message: 'could not find the function' } })
                }
            });
            await assert.rejects(
                () => brokenRpcSvc.requestAndStoreOtp('9000000099', '123456'),
                /could not find the function/
            );
        } finally {
            if (prevEnv !== undefined) process.env.NODE_ENV = prevEnv; else delete process.env.NODE_ENV;
            if (prevMode !== undefined) process.env.OTP_DELIVERY_MODE = prevMode; else delete process.env.OTP_DELIVERY_MODE;
            if (prevSupaUrl !== undefined) process.env.SUPABASE_URL = prevSupaUrl; else delete process.env.SUPABASE_URL;
            if (prevSupaService !== undefined) process.env.SUPABASE_SERVICE_ROLE_KEY = prevSupaService; else delete process.env.SUPABASE_SERVICE_ROLE_KEY;
            if (prevSupaAnon !== undefined) process.env.SUPABASE_ANON_KEY = prevSupaAnon; else delete process.env.SUPABASE_ANON_KEY;
            if (prevOtpSalt !== undefined) process.env.OTP_SALT = prevOtpSalt; else delete process.env.OTP_SALT;
        }
    });

    await asyncTest('26. Production (NODE_ENV=production) NEVER activates on_screen mode or exposes OTP even if OTP_DELIVERY_MODE=on_screen', async () => {
        const { isOnScreenOtpTestMode } = require('../src/services/otpStoreService');
        const prevEnv = process.env.NODE_ENV;
        const prevMode = process.env.OTP_DELIVERY_MODE;
        const prevFast2Sms = process.env.FAST2SMS_API_KEY;
        const prevSupaUrl = process.env.SUPABASE_URL;
        const prevSupaService = process.env.SUPABASE_SERVICE_ROLE_KEY;
        const prevSupaAnon = process.env.SUPABASE_ANON_KEY;
        const prevOtpSalt = process.env.OTP_SALT;
        const prevHttpsRequest = https.request;
        const prevClient = otpStoreService.supabaseClient;

        process.env.NODE_ENV = 'production';
        process.env.OTP_DELIVERY_MODE = 'on_screen'; // Must be ignored in production!
        process.env.FAST2SMS_API_KEY = 'prod_fast2sms_key';
        process.env.SUPABASE_URL = 'https://prod-project.supabase.co';
        process.env.SUPABASE_SERVICE_ROLE_KEY = 'prod_service_key';
        process.env.SUPABASE_ANON_KEY = 'prod_anon_key';
        process.env.OTP_SALT = 'strong_production_otp_salt_for_test_26_check!';

        let smsCalledInProd = false;
        https.request = (_opts, cb) => {
            smsCalledInProd = true;
            const req = new EventEmitter();
            req.write = () => {};
            req.end = () => {
                const res = new EventEmitter();
                res.statusCode = 200;
                cb(res);
                res.emit('data', JSON.stringify({ return: true, message: ['SMS sent successfully.'] }));
                res.emit('end');
            };
            return req;
        };

        otpStoreService.supabaseClient = {
            rpc: async () => ({ data: { allowed: true, status: 200 }, error: null })
        };

        try {
            assert.strictEqual(isOnScreenOtpTestMode(), false, 'Production must NEVER activate on_screen test mode');
            let status = 200;
            let body = null;
            const res = {
                status: (c) => { status = c; return res; },
                json: (d) => { body = d; return res; }
            };
            await auth.requestOTP({ body: { phone: '9876501234' } }, res);
            assert.strictEqual(status, 200);
            assert.strictEqual(smsCalledInProd, true, 'Production must continue using real SMS');
            assert.strictEqual(body.otp, undefined, 'Production API must NEVER expose OTP');
            assert.strictEqual(body.deliveryMode, undefined);
        } finally {
            https.request = prevHttpsRequest;
            otpStoreService.supabaseClient = prevClient;
            if (prevEnv !== undefined) process.env.NODE_ENV = prevEnv; else delete process.env.NODE_ENV;
            if (prevMode !== undefined) process.env.OTP_DELIVERY_MODE = prevMode; else delete process.env.OTP_DELIVERY_MODE;
            if (prevFast2Sms !== undefined) process.env.FAST2SMS_API_KEY = prevFast2Sms; else delete process.env.FAST2SMS_API_KEY;
            if (prevSupaUrl !== undefined) process.env.SUPABASE_URL = prevSupaUrl; else delete process.env.SUPABASE_URL;
            if (prevSupaService !== undefined) process.env.SUPABASE_SERVICE_ROLE_KEY = prevSupaService; else delete process.env.SUPABASE_SERVICE_ROLE_KEY;
            if (prevSupaAnon !== undefined) process.env.SUPABASE_ANON_KEY = prevSupaAnon; else delete process.env.SUPABASE_ANON_KEY;
            if (prevOtpSalt !== undefined) process.env.OTP_SALT = prevOtpSalt; else delete process.env.OTP_SALT;
        }
    });

    await asyncTest('27. Forgot Password API returns on-screen OTP in testing mode without sending real SMS', async () => {
        const prevEnv = process.env.NODE_ENV;
        const prevMode = process.env.OTP_DELIVERY_MODE;
        const prevFast2Sms = process.env.FAST2SMS_API_KEY;
        const prevHttpsRequest = https.request;
        const prevClient = otpStoreService.supabaseClient;
        const { User } = require('../src/models/Schemas');
        const prevFindOne = User.findOne;

        process.env.NODE_ENV = 'development';
        process.env.OTP_DELIVERY_MODE = 'on_screen';
        process.env.FAST2SMS_API_KEY = 'must_be_blocked_key';

        let externalCalled = false;
        https.request = () => {
            externalCalled = true;
            throw new Error('Must not call external SMS in on_screen testing mode');
        };

        otpStoreService.supabaseClient = {
            rpc: async () => ({ data: { allowed: true, status: 200 }, error: null })
        };
        User.findOne = async () => ({
            id: 'fp-user-1',
            email: 'fp@dentaguru.internal',
            phone: '9123450987'
        });

        try {
            let status = 200;
            let body = null;
            const res = {
                status: (c) => { status = c; return res; },
                json: (d) => { body = d; return res; }
            };
            await auth.forgotPassword({ body: { phone: '9123450987' } }, res);
            assert.strictEqual(status, 200);
            assert.strictEqual(body.success, true);
            assert.strictEqual(body.deliveryMode, 'on_screen');
            assert.match(String(body.otp), /^\d{6}$/);
            assert.strictEqual(externalCalled, false);
        } finally {
            https.request = prevHttpsRequest;
            otpStoreService.supabaseClient = prevClient;
            User.findOne = prevFindOne;
            if (prevEnv !== undefined) process.env.NODE_ENV = prevEnv; else delete process.env.NODE_ENV;
            if (prevMode !== undefined) process.env.OTP_DELIVERY_MODE = prevMode; else delete process.env.OTP_DELIVERY_MODE;
            if (prevFast2Sms !== undefined) process.env.FAST2SMS_API_KEY = prevFast2Sms; else delete process.env.FAST2SMS_API_KEY;
        }
    });

    await asyncTest('28. On-screen testing mode refuses connecting to production Supabase database URL', async () => {
        const prevEnv = process.env.NODE_ENV;
        const prevMode = process.env.OTP_DELIVERY_MODE;
        const prevSupaUrl = process.env.SUPABASE_URL;
        const prevSupaService = process.env.SUPABASE_SERVICE_ROLE_KEY;
        const prevSupaAnon = process.env.SUPABASE_ANON_KEY;
        const prevOtpSalt = process.env.OTP_SALT;
        const prevProdUrl = process.env.PRODUCTION_SUPABASE_URL;

        process.env.NODE_ENV = 'development';
        process.env.OTP_DELIVERY_MODE = 'on_screen';
        process.env.SUPABASE_SERVICE_ROLE_KEY = 'some_service_role_key';
        process.env.SUPABASE_ANON_KEY = 'some_anon_key';

        try {
            // Case A: Hardcoded production project ref (with or without trailing slash)
            process.env.SUPABASE_URL = 'https://fommrwxpqzkcktweosgp.supabase.co/';
            const svcA = new OtpStoreService();
            assert.throws(() => {
                svcA._ensureProductionConfig();
            }, /separate testing Supabase project/);

            // Case B: Custom PRODUCTION_SUPABASE_URL env match (trailing slash normalized)
            process.env.PRODUCTION_SUPABASE_URL = 'https://custom-prod-ref.supabase.co/';
            process.env.SUPABASE_URL = 'https://custom-prod-ref.supabase.co';
            const svcB = new OtpStoreService();
            assert.throws(() => {
                svcB._ensureProductionConfig();
            }, /separate testing Supabase project/);
        } finally {
            if (prevEnv !== undefined) process.env.NODE_ENV = prevEnv; else delete process.env.NODE_ENV;
            if (prevMode !== undefined) process.env.OTP_DELIVERY_MODE = prevMode; else delete process.env.OTP_DELIVERY_MODE;
            if (prevSupaUrl !== undefined) process.env.SUPABASE_URL = prevSupaUrl; else delete process.env.SUPABASE_URL;
            if (prevSupaService !== undefined) process.env.SUPABASE_SERVICE_ROLE_KEY = prevSupaService; else delete process.env.SUPABASE_SERVICE_ROLE_KEY;
            if (prevSupaAnon !== undefined) process.env.SUPABASE_ANON_KEY = prevSupaAnon; else delete process.env.SUPABASE_ANON_KEY;
            if (prevProdUrl !== undefined) process.env.PRODUCTION_SUPABASE_URL = prevProdUrl; else delete process.env.PRODUCTION_SUPABASE_URL;
        }
    });

    await asyncTest('29. Local development keep-alive is disabled and never pings production Render', async () => {
        const { resolveKeepAliveUrl } = require('../src/server');

        // Default local development (no KEEP_ALIVE_URL / RENDER_EXTERNAL_URL) -> disabled (null)
        assert.strictEqual(resolveKeepAliveUrl({ NODE_ENV: 'development' }), null);
        assert.strictEqual(resolveKeepAliveUrl({}), null);

        // Even if KEEP_ALIVE_URL or RENDER_EXTERNAL_URL points to production Render in dev -> blocked (null)
        assert.strictEqual(
            resolveKeepAliveUrl({
                NODE_ENV: 'development',
                KEEP_ALIVE_URL: 'https://dentaguru-backend.onrender.com/api/v1/clinics',
            }),
            null
        );
        assert.strictEqual(
            resolveKeepAliveUrl({
                NODE_ENV: 'development',
                RENDER_EXTERNAL_URL: 'https://dentaguru-backend.onrender.com',
            }),
            null
        );

        // Temporary non-production test Render service may ping its own test URL
        assert.strictEqual(
            resolveKeepAliveUrl({
                NODE_ENV: 'development',
                RENDER_EXTERNAL_URL: 'https://dentaguru-backend-test.onrender.com/',
            }),
            'https://dentaguru-backend-test.onrender.com/api/v1/clinics'
        );
    });

    await asyncTest('30. Production keep-alive behavior remains unchanged', async () => {
        const { resolveKeepAliveUrl, PRODUCTION_KEEP_ALIVE_URL } = require('../src/server');

        assert.strictEqual(
            resolveKeepAliveUrl({ NODE_ENV: 'production' }),
            PRODUCTION_KEEP_ALIVE_URL
        );
        assert.strictEqual(
            resolveKeepAliveUrl({
                NODE_ENV: 'production',
                RENDER_EXTERNAL_URL: 'https://dentaguru-backend.onrender.com',
            }),
            'https://dentaguru-backend.onrender.com/api/v1/clinics'
        );
        assert.strictEqual(
            resolveKeepAliveUrl({
                NODE_ENV: 'production',
                KEEP_ALIVE_URL: 'https://dentaguru-backend.onrender.com/health',
            }),
            'https://dentaguru-backend.onrender.com/health'
        );
    });

    await asyncTest('31. backend/src/config/supabase.js has no hardcoded production URL fallback and fails immediately when credentials are missing', async () => {
        const { resolveSupabaseConfig } = require('../src/config/supabase');
        const source = fs.readFileSync(path.resolve(__dirname, '../src/config/supabase.js'), 'utf8');

        assert.strictEqual(source.includes('fommrwxpqzkcktweosgp.supabase.co'), false, 'Hardcoded production URL must be removed');
        assert.strictEqual(source.includes('eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9'), false, 'Hardcoded production anon key must be removed');

        assert.throws(() => resolveSupabaseConfig({ NODE_ENV: 'development' }), /Missing required environment variable\(s\): SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY/);
        assert.throws(() => resolveSupabaseConfig({
            NODE_ENV: 'test',
            SUPABASE_URL: 'https://ojinzcdldwugpnxrnjcq.supabase.co',
            SUPABASE_ANON_KEY: 'test_anon_fixture',
        }), /SUPABASE_SERVICE_ROLE_KEY/);
        assert.throws(() => resolveSupabaseConfig({ NODE_ENV: 'production' }), /Missing required environment variable/);
    });

    await asyncTest('32. Development/testing backend refuses connecting to production Supabase even without OTP_DELIVERY_MODE', async () => {
        const { resolveSupabaseConfig } = require('../src/config/supabase');

        assert.throws(() => resolveSupabaseConfig({
            NODE_ENV: 'development',
            SUPABASE_URL: 'https://fommrwxpqzkcktweosgp.supabase.co',
            SUPABASE_ANON_KEY: 'dummy_anon_fixture',
            SUPABASE_SERVICE_ROLE_KEY: 'dummy_service_fixture',
        }), /Local development\/testing backend must never connect to production Supabase/);

        assert.throws(() => resolveSupabaseConfig({
            NODE_ENV: 'test',
            SUPABASE_URL: 'https://fommrwxpqzkcktweosgp.supabase.co/',
            SUPABASE_ANON_KEY: 'dummy_anon_fixture',
            SUPABASE_SERVICE_ROLE_KEY: 'dummy_service_fixture',
        }), /Local development\/testing backend must never connect to production Supabase/);

        // Dedicated test Supabase succeeds in development/test
        const testCfg = resolveSupabaseConfig({
            NODE_ENV: 'development',
            SUPABASE_URL: 'https://ojinzcdldwugpnxrnjcq.supabase.co/',
            SUPABASE_ANON_KEY: 'test_anon_fixture',
            SUPABASE_SERVICE_ROLE_KEY: 'test_service_fixture',
        });
        assert.strictEqual(testCfg.supabaseUrl, 'https://ojinzcdldwugpnxrnjcq.supabase.co');

        // Production explicitly allows production Supabase when env vars are set
        const prodCfg = resolveSupabaseConfig({
            NODE_ENV: 'production',
            SUPABASE_URL: 'https://fommrwxpqzkcktweosgp.supabase.co',
            SUPABASE_ANON_KEY: 'prod_anon_fixture',
            SUPABASE_SERVICE_ROLE_KEY: 'prod_service_fixture',
        });
        assert.strictEqual(prodCfg.supabaseUrl, 'https://fommrwxpqzkcktweosgp.supabase.co');
    });

    await asyncTest('33. Staging dynamic on-screen OTP accepts any valid phone with STAGING_OTP_ACCESS_KEY (zero SMS), rejects missing/bad key, and production disables it', async () => {
        const { isOnScreenOtpTestMode, isPhoneAllowedForOnScreenOtp } = require('../src/services/otpStoreService');
        const auth = require('../src/controllers/authController');

        const prevEnv = process.env.NODE_ENV;
        const prevMode = process.env.OTP_DELIVERY_MODE;
        const prevAllowlist = process.env.ON_SCREEN_OTP_ALLOWLIST;
        const prevStagingKey = process.env.STAGING_OTP_ACCESS_KEY;
        const prevAdminPhone = process.env.ADMIN_PHONE;
        const prevHttpsRequest = https.request;
        const prevClient = otpStoreService.supabaseClient;
        const prevSupaUrl = process.env.SUPABASE_URL;
        const prevSupaService = process.env.SUPABASE_SERVICE_ROLE_KEY;
        const prevSupaAnon = process.env.SUPABASE_ANON_KEY;
        const prevOtpSalt = process.env.OTP_SALT;

        let smsDispatchAttempted = false;
        https.request = () => {
            smsDispatchAttempted = true;
            throw new Error('SMS carrier must NOT be invoked in staging OTP_DELIVERY_MODE=on_screen');
        };

        const rpcChallenges = new Map();
        otpStoreService.supabaseClient = {
            rpc: async (fnName, params) => {
                if (fnName === 'request_otp_challenge') {
                    rpcChallenges.set(params.p_identifier, { hash: params.p_hashed_code, used: false });
                    return { data: { allowed: true, status: 200, requestCount: 1 }, error: null };
                }
                if (fnName === 'verify_otp_challenge') {
                    const rec = rpcChallenges.get(params.p_identifier);
                    if (!rec || rec.used || rec.hash !== params.p_incoming_hash) {
                        return { data: { valid: false, reason: 'INVALID_CODE', message: 'Invalid OTP.' }, error: null };
                    }
                    rec.used = true;
                    return { data: { valid: true, reason: 'VERIFIED', message: 'Verified.' }, error: null };
                }
                return { data: { allowed: true }, error: null };
            }
        };

        const stagingKeyValue = 'staging_secret_key_for_dynamic_otp_tests_2026!';
        try {
            process.env.NODE_ENV = 'staging';
            process.env.OTP_DELIVERY_MODE = 'on_screen';
            delete process.env.ON_SCREEN_OTP_ALLOWLIST;
            process.env.STAGING_OTP_ACCESS_KEY = stagingKeyValue;
            process.env.ADMIN_PHONE = '9281030535';
            process.env.SUPABASE_URL = 'https://ojinzcdldwugpnxrnjcq.supabase.co';
            process.env.SUPABASE_SERVICE_ROLE_KEY = 'staging_service_role_fixture';
            process.env.SUPABASE_ANON_KEY = 'staging_anon_fixture';
            process.env.OTP_SALT = 'strong_staging_otp_salt_for_test_33_allowlist!';

            assert.strictEqual(isOnScreenOtpTestMode(), true);
            // Dynamic mobile numbers (no fixed allowlist in staging)
            assert.strictEqual(isPhoneAllowedForOnScreenOtp('9888877777'), true);
            assert.strictEqual(isPhoneAllowedForOnScreenOtp('+91 7012345678'), true);
            assert.strictEqual(isPhoneAllowedForOnScreenOtp('12345'), false);

            // 1. Missing or invalid staging key header MUST be rejected with 403 and expose ZERO OTP
            let status = 200;
            let body = null;
            await auth.requestOTP(
                { body: { phone: '9888877777' }, headers: {} },
                { status(c) { status = c; return this; }, json(b) { body = b; return this; } }
            );
            assert.strictEqual(status, 403);
            assert.strictEqual(body.success, false);
            assert.strictEqual(body.code, 'STAGING_OTP_KEY_REQUIRED');
            assert.strictEqual(body.otp, undefined);

            status = 200;
            body = null;
            await auth.requestOTP(
                { body: { phone: '9888877777' }, headers: { 'x-staging-otp-key': 'wrong-key-value' } },
                { status(c) { status = c; return this; }, json(b) { body = b; return this; } }
            );
            assert.strictEqual(status, 403);
            assert.strictEqual(body.success, false);
            assert.strictEqual(body.otp, undefined);

            // 2. Arbitrary valid mobile number with valid staging key receives on-screen OTP without calling Fast2SMS/Twilio
            for (const testPhone of ['9888877777', '+917012345678']) {
                status = 200;
                body = null;
                await auth.requestOTP(
                    { body: { phone: testPhone }, headers: { 'x-staging-otp-key': stagingKeyValue } },
                    { status(c) { status = c; return this; }, json(b) { body = b; return this; } }
                );
                assert.strictEqual(status, 200);
                assert.strictEqual(body.success, true);
                assert.strictEqual(body.deliveryMode, 'on_screen');
                assert.match(String(body.otp), /^\d{6}$/);
                assert.strictEqual(smsDispatchAttempted, false, 'Zero external SMS requests should run in staging on-screen mode');

                // Verify HMAC-hashed single-use OTP check works end-to-end
                const v1 = await otpStoreService.verifyOtp(testPhone, body.otp);
                assert.strictEqual(v1.valid, true);
                const v2 = await otpStoreService.verifyOtp(testPhone, body.otp);
                assert.strictEqual(v2.valid, false, 'Replay attempt must be rejected');
            }

            // 3. Staging OTP rate-limit/cooldown & forgotPassword staging key guard
            const Schemas = require('../src/models/Schemas');
            const origFindOne = Schemas.User.findOne;
            const origRpc = otpStoreService.supabaseClient.rpc;
            try {
                Schemas.User.findOne = async () => ({ id: 'u-reset-1', phone: '9888877777', email: 'u@test.local' });
                otpStoreService.supabaseClient = {
                    rpc: async (fnName, params) => {
                        if (fnName === 'request_otp_challenge') {
                            if (params.p_identifier === '9777766666') {
                                return { data: { allowed: false, status: 429, reason: 'COOLDOWN', message: 'Please wait 30 seconds.' }, error: null };
                            }
                            return { data: { allowed: true, status: 200, requestCount: 1 }, error: null };
                        }
                        return { data: { allowed: true }, error: null };
                    }
                };

                // Cooldown preserved in staging
                status = 200; body = null;
                await auth.requestOTP(
                    { body: { phone: '9777766666' }, headers: { 'x-staging-otp-key': stagingKeyValue } },
                    { status(c) { status = c; return this; }, json(b) { body = b; return this; } }
                );
                assert.strictEqual(status, 429);
                assert.strictEqual(body.otp, undefined);

                // forgotPassword rejects missing staging key with 403 and serves OTP with valid key (zero SMS)
                status = 200; body = null;
                await auth.forgotPassword(
                    { body: { phone: '9888877777' }, headers: {} },
                    { status(c) { status = c; return this; }, json(b) { body = b; return this; } }
                );
                assert.strictEqual(status, 403);
                assert.strictEqual(body.otp, undefined);

                status = 200; body = null;
                await auth.forgotPassword(
                    { body: { phone: '9888877777' }, headers: { 'x-staging-otp-key': stagingKeyValue } },
                    { status(c) { status = c; return this; }, json(b) { body = b; return this; } }
                );
                assert.strictEqual(status, 200);
                assert.strictEqual(body.deliveryMode, 'on_screen');
                assert.match(String(body.otp), /^\d{6}$/);
                assert.strictEqual(smsDispatchAttempted, false);
            } finally {
                Schemas.User.findOne = origFindOne;
                otpStoreService.supabaseClient = { rpc: origRpc };
            }

            // 4. Even with STAGING_OTP_ACCESS_KEY set, production NEVER activates on-screen OTP
            process.env.NODE_ENV = 'production';
            process.env.OTP_DELIVERY_MODE = 'on_screen';
            assert.strictEqual(isOnScreenOtpTestMode(), false);
            assert.strictEqual(isPhoneAllowedForOnScreenOtp('9281030535'), false);
        } finally {
            https.request = prevHttpsRequest;
            otpStoreService.supabaseClient = prevClient;
            if (prevEnv !== undefined) process.env.NODE_ENV = prevEnv; else delete process.env.NODE_ENV;
            if (prevMode !== undefined) process.env.OTP_DELIVERY_MODE = prevMode; else delete process.env.OTP_DELIVERY_MODE;
            if (prevAllowlist !== undefined) process.env.ON_SCREEN_OTP_ALLOWLIST = prevAllowlist; else delete process.env.ON_SCREEN_OTP_ALLOWLIST;
            if (prevStagingKey !== undefined) process.env.STAGING_OTP_ACCESS_KEY = prevStagingKey; else delete process.env.STAGING_OTP_ACCESS_KEY;
            if (prevAdminPhone !== undefined) process.env.ADMIN_PHONE = prevAdminPhone; else delete process.env.ADMIN_PHONE;
            if (prevSupaUrl !== undefined) process.env.SUPABASE_URL = prevSupaUrl; else delete process.env.SUPABASE_URL;
            if (prevSupaService !== undefined) process.env.SUPABASE_SERVICE_ROLE_KEY = prevSupaService; else delete process.env.SUPABASE_SERVICE_ROLE_KEY;
            if (prevSupaAnon !== undefined) process.env.SUPABASE_ANON_KEY = prevSupaAnon; else delete process.env.SUPABASE_ANON_KEY;
            if (prevOtpSalt !== undefined) process.env.OTP_SALT = prevOtpSalt; else delete process.env.OTP_SALT;
        }
    });

    await asyncTest('34. Secrets helper fails fast in staging/production when secrets are missing or weak', async () => {
        const {
            getJwtSecret,
            getRefreshSecret,
            getOtpSalt,
            getStagingOtpAccessKey,
            isAuthorizedStagingOtpRequest,
            validateCloudSecuritySecrets,
        } = require('../src/config/secrets');

        assert.throws(() => validateCloudSecuritySecrets({ NODE_ENV: 'staging' }), /Missing or weak JWT_SECRET/);
        assert.throws(() => validateCloudSecuritySecrets({
            NODE_ENV: 'staging',
            OTP_DELIVERY_MODE: 'on_screen',
            JWT_SECRET: 'strong_jwt_secret_value_for_tests_32chars!',
            REFRESH_SECRET: 'strong_refresh_secret_value_for_tests_32chars',
            OTP_SALT: 'strong_otp_salt_value_for_tests_32chars',
        }), /Missing or weak STAGING_OTP_ACCESS_KEY/);

        assert.throws(() => validateCloudSecuritySecrets({
            NODE_ENV: 'production',
            JWT_SECRET: 'supersecretjwtkey123',
            REFRESH_SECRET: 'strong_refresh_secret_value_for_tests_32chars',
            OTP_SALT: 'strong_otp_salt_value_for_tests_32chars',
        }), /Missing or weak JWT_SECRET/);

        assert.throws(() => getOtpSalt({
            NODE_ENV: 'staging',
            OTP_SALT: 'gs_health_otp_salt_2026',
        }), /Missing or weak OTP_SALT/);

        // Production never exposes or accepts STAGING_OTP_ACCESS_KEY
        assert.strictEqual(getStagingOtpAccessKey({
            NODE_ENV: 'production',
            STAGING_OTP_ACCESS_KEY: 'staging_secret_should_never_activate_in_prod!',
        }), null);

        const strongEnv = {
            NODE_ENV: 'staging',
            OTP_DELIVERY_MODE: 'on_screen',
            JWT_SECRET: 'strong_test_jwt_secret_minimum_length_32chars!',
            REFRESH_SECRET: 'strong_test_refresh_secret_minimum_length_32!',
            OTP_SALT: 'strong_test_otp_salt_minimum_length_32chars!!',
            STAGING_OTP_ACCESS_KEY: 'strong_staging_otp_access_key_32chars_min!!',
        };
        assert.strictEqual(getJwtSecret(strongEnv), strongEnv.JWT_SECRET);
        assert.strictEqual(getRefreshSecret(strongEnv), strongEnv.REFRESH_SECRET);
        assert.strictEqual(getOtpSalt(strongEnv), strongEnv.OTP_SALT);
        assert.strictEqual(getStagingOtpAccessKey(strongEnv), strongEnv.STAGING_OTP_ACCESS_KEY);
        assert.strictEqual(validateCloudSecuritySecrets(strongEnv), true);
        assert.strictEqual(
            isAuthorizedStagingOtpRequest({ headers: { 'x-staging-otp-key': strongEnv.STAGING_OTP_ACCESS_KEY } }, strongEnv).authorized,
            true
        );
        assert.strictEqual(
            isAuthorizedStagingOtpRequest({ headers: { 'x-staging-otp-key': 'wrong_key' } }, strongEnv).authorized,
            false
        );

        // Non-cloud dev/test returns non-empty cryptographic ephemeral secret when unset
        const devJwt = getJwtSecret({ NODE_ENV: 'development' });
        assert.ok(devJwt && devJwt.length >= 32 && devJwt !== 'supersecretjwtkey123');
    });

    await asyncTest('35. Database reset endpoint refuses execution in cloud environments or without explicit local opt-in', async () => {
        const auth = require('../src/controllers/authController');
        const prevEnv = process.env.NODE_ENV;
        const prevResetFlag = process.env.ALLOW_DANGEROUS_DB_RESET;
        try {
            process.env.NODE_ENV = 'staging';
            process.env.ALLOW_DANGEROUS_DB_RESET = 'true';
            let status = 200;
            let body = null;
            await auth.resetDatabase({}, { status(c) { status = c; return this; }, json(b) { body = b; return this; } });
            assert.strictEqual(status, 403);
            assert.strictEqual(body.success, false);

            process.env.NODE_ENV = 'development';
            delete process.env.ALLOW_DANGEROUS_DB_RESET;
            status = 200;
            body = null;
            await auth.resetDatabase({}, { status(c) { status = c; return this; }, json(b) { body = b; return this; } });
            assert.strictEqual(status, 403);
            assert.strictEqual(body.success, false);
        } finally {
            if (prevEnv !== undefined) process.env.NODE_ENV = prevEnv; else delete process.env.NODE_ENV;
            if (prevResetFlag !== undefined) process.env.ALLOW_DANGEROUS_DB_RESET = prevResetFlag; else delete process.env.ALLOW_DANGEROUS_DB_RESET;
        }
    });

    await asyncTest('36. /health returns HTTP 503 when DB is disconnected and HTTP 200 when healthy; ALWAYS_ON_HOSTING disables keep-alive ping', async () => {
        const httpModule = require('http');
        const app = require('../src/app');
        const supabaseConfig = require('../src/config/supabase');
        const { resolveKeepAliveUrl } = require('../src/server');

        // Always-On hosting flag disables redundant self-ping
        assert.strictEqual(
            resolveKeepAliveUrl({
                NODE_ENV: 'production',
                ALWAYS_ON_HOSTING: 'true',
                RENDER_EXTERNAL_URL: 'https://dentaguru-backend.onrender.com',
            }),
            null
        );

        const prevSupaUrl = process.env.SUPABASE_URL;
        const origFrom = supabaseConfig.supabaseAdmin.from;
        const server = httpModule.createServer(app);
        await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
        const { port } = server.address();

        const fetchHealth = () => new Promise((resolve, reject) => {
            httpModule.get(`http://127.0.0.1:${port}/health`, (res) => {
                let raw = '';
                res.on('data', (chunk) => { raw += chunk; });
                res.on('end', () => resolve({ status: res.statusCode, json: JSON.parse(raw) }));
            }).on('error', reject);
        });

        try {
            process.env.SUPABASE_URL = 'https://ojinzcdldwugpnxrnjcq.supabase.co';
            supabaseConfig.supabaseAdmin.from = () => ({
                select: async () => ({ error: new Error('Simulated DB connectivity failure') })
            });
            const unhealthy = await fetchHealth();
            assert.strictEqual(unhealthy.status, 503);
            assert.strictEqual(unhealthy.json.status, 'unhealthy');

            supabaseConfig.supabaseAdmin.from = () => ({
                select: async () => ({ error: null })
            });
            const healthy = await fetchHealth();
            assert.strictEqual(healthy.status, 200);
            assert.strictEqual(healthy.json.status, 'healthy');
        } finally {
            supabaseConfig.supabaseAdmin.from = origFrom;
            if (prevSupaUrl !== undefined) process.env.SUPABASE_URL = prevSupaUrl; else delete process.env.SUPABASE_URL;
            await new Promise((resolve) => server.close(resolve));
        }
    });

    await asyncTest('37. WhatsApp/Twilio dispatch is hard-blocked in on-screen OTP testing mode even when credentials are present', async () => {
        const whatsappService = require('../src/services/whatsappService');
        const prevEnv = process.env.NODE_ENV;
        const prevMode = process.env.OTP_DELIVERY_MODE;
        const prevTwilioSid = process.env.TWILIO_ACCOUNT_SID;
        const prevTwilioToken = process.env.TWILIO_AUTH_TOKEN;
        const prevMetaToken = process.env.WHATSAPP_API_TOKEN;
        const prevMetaPhoneId = process.env.WHATSAPP_PHONE_NUMBER_ID;
        const prevHttpsRequest = https.request;

        let externalNetworkCalled = false;
        https.request = () => {
            externalNetworkCalled = true;
            throw new Error('External WhatsApp API must never be called in on-screen OTP testing mode');
        };

        try {
            process.env.NODE_ENV = 'staging';
            process.env.OTP_DELIVERY_MODE = 'on_screen';
            process.env.TWILIO_ACCOUNT_SID = 'AC_test_blocked_twilio_sid';
            process.env.TWILIO_AUTH_TOKEN = 'test_blocked_twilio_token';
            process.env.WHATSAPP_API_TOKEN = 'test_blocked_meta_token';
            process.env.WHATSAPP_PHONE_NUMBER_ID = '1234567890';

            const waRes = await whatsappService.dispatchWhatsApp({
                to: '9281030535',
                message: 'Testing mode block check',
                templateName: 'TEST_TEMPLATE'
            });
            assert.strictEqual(waRes.success, false);
            assert.strictEqual(waRes.blockedInTestMode, true);
            assert.strictEqual(waRes.whatsappStatus, 'BlockedInTestingMode');
            assert.strictEqual(externalNetworkCalled, false);
        } finally {
            https.request = prevHttpsRequest;
            if (prevEnv !== undefined) process.env.NODE_ENV = prevEnv; else delete process.env.NODE_ENV;
            if (prevMode !== undefined) process.env.OTP_DELIVERY_MODE = prevMode; else delete process.env.OTP_DELIVERY_MODE;
            if (prevTwilioSid !== undefined) process.env.TWILIO_ACCOUNT_SID = prevTwilioSid; else delete process.env.TWILIO_ACCOUNT_SID;
            if (prevTwilioToken !== undefined) process.env.TWILIO_AUTH_TOKEN = prevTwilioToken; else delete process.env.TWILIO_AUTH_TOKEN;
            if (prevMetaToken !== undefined) process.env.WHATSAPP_API_TOKEN = prevMetaToken; else delete process.env.WHATSAPP_API_TOKEN;
            if (prevMetaPhoneId !== undefined) process.env.WHATSAPP_PHONE_NUMBER_ID = prevMetaPhoneId; else delete process.env.WHATSAPP_PHONE_NUMBER_ID;
        }
    });

    await asyncTest('38. Two-way Supabase environment separation: production refuses testing Supabase project URL', async () => {
        const { resolveSupabaseConfig } = require('../src/config/supabase');

        assert.throws(() => resolveSupabaseConfig({
            NODE_ENV: 'production',
            SUPABASE_URL: 'https://ojinzcdldwugpnxrnjcq.supabase.co',
            SUPABASE_ANON_KEY: 'prod_anon_fixture',
            SUPABASE_SERVICE_ROLE_KEY: 'prod_service_fixture',
        }), /Production backend must never connect to testing Supabase project/);

        assert.throws(() => resolveSupabaseConfig({
            NODE_ENV: 'production',
            SUPABASE_URL: 'https://custom-test-ref.supabase.co/',
            TESTING_SUPABASE_URL: 'https://custom-test-ref.supabase.co',
            SUPABASE_ANON_KEY: 'prod_anon_fixture',
            SUPABASE_SERVICE_ROLE_KEY: 'prod_service_fixture',
        }), /Production backend must never connect to testing Supabase project/);
    });

    await asyncTest('39. Cloud auth security: enforces verified OTP/password on login, rejects unsigned sb_direct_ tokens, and verifies all 4 user-role OTP login flows', async () => {
        const httpModule = require('http');
        const app = require('../src/app');
        const Schemas = require('../src/models/Schemas');

        const prevEnv = process.env.NODE_ENV;
        const prevAdminPhone = process.env.ADMIN_PHONE;
        const prevJwt = process.env.JWT_SECRET;
        const prevRefresh = process.env.REFRESH_SECRET;
        const prevSalt = process.env.OTP_SALT;
        const origUserFindByMobile = Schemas.User.findByMobile;
        const origUserFindOne = Schemas.User.findOne;
        const origUserFindById = Schemas.User.findById;
        const origUserUpdate = Schemas.User.findByIdAndUpdate;
        const origDentistFindById = Schemas.Dentist.findById;
        const origDentistFindOne = Schemas.Dentist.findOne;
        const origClinicFindOne = Schemas.Clinic.findOne;
        const origVerifyOtp = otpStoreService.verifyOtp;

        const roleAccounts = [
            { id: 'u-pat-1', name: 'Test Patient', email: 'pat@test.local', phone: '9000001111', role: 'Patient', status: 'ACTIVE' },
            { id: 'u-doc-1', name: 'Dr. Test Doctor', email: 'doc@test.local', phone: '9000002222', role: 'DOCTOR', status: 'ACTIVE' },
            { id: 'u-cli-1', name: 'Test Clinic', email: 'cli@test.local', phone: '9000003333', role: 'Clinic', status: 'ACTIVE' },
            { id: 'u-adm-1', name: 'Main Admin', email: 'adm@test.local', phone: '9281030535', role: 'Admin', status: 'ACTIVE' },
        ];

        Schemas.User.findByMobile = async (phone) => {
            const d = String(phone || '').replace(/\D/g, '').slice(-10);
            return roleAccounts.find(u => u.phone === d) || null;
        };
        Schemas.User.findOne = async (q = {}) => {
            if (q.phone) {
                const d = String(q.phone).replace(/\D/g, '').slice(-10);
                return roleAccounts.find(u => u.phone === d) || null;
            }
            if (q.email) {
                return roleAccounts.find(u => u.email === String(q.email).toLowerCase()) || null;
            }
            if (q.role === 'Admin') {
                return roleAccounts[3];
            }
            return null;
        };
        Schemas.User.findById = async (id) => roleAccounts.find(u => u.id === id) || null;
        Schemas.User.findByIdAndUpdate = async (id) => roleAccounts.find(u => u.id === id) || null;
        Schemas.Dentist.findById = async () => ({ id: 'dent-1', user_id: 'u-doc-1', speciality: 'Cardiology', availability_status: 'Available' });
        Schemas.Dentist.findOne = async () => ({ id: 'dent-1', user_id: 'u-doc-1', speciality: 'Cardiology', availability_status: 'Available' });
        Schemas.Clinic.findOne = async () => ({ id: 'clin-1', user_id: 'u-cli-1', clinic_name: 'Test Clinic', location: 'Hyderabad' });
        otpStoreService.verifyOtp = async (_key, code) => ({
            valid: String(code) === '654321',
            message: String(code) === '654321' ? 'Verified' : 'Invalid OTP'
        });

        const server = httpModule.createServer(app);
        await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
        const { port } = server.address();

        const apiReq = (method, urlPath, headers = {}, body = null) => new Promise((resolve, reject) => {
            const payload = body ? JSON.stringify(body) : null;
            const req = httpModule.request({
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
                res.on('data', (c) => { raw += c; });
                res.on('end', () => resolve({ status: res.statusCode, json: raw ? JSON.parse(raw) : {} }));
            });
            req.on('error', reject);
            if (payload) req.write(payload);
            req.end();
        });

        try {
            process.env.NODE_ENV = 'staging';
            process.env.ADMIN_PHONE = '9281030535';
            process.env.JWT_SECRET = 'staging_strong_jwt_secret_for_role_auth_tests!';
            process.env.REFRESH_SECRET = 'staging_strong_refresh_secret_for_role_auth!';
            process.env.OTP_SALT = 'staging_strong_otp_salt_for_role_auth_tests!';

            // 1. Login without OTP or password in staging MUST fail with 401
            const noCreds = await apiReq('POST', '/api/v1/auth/login', {}, { phone: '9000001111' });
            assert.strictEqual(noCreds.status, 401);
            assert.strictEqual(noCreds.json.success, false);

            // 2. All 4 roles (Patient, Doctor, Clinic, Admin) succeed with verified OTP and receive signed JWTs
            for (const acc of roleAccounts) {
                const loginRes = await apiReq('POST', '/api/v1/auth/login', {}, {
                    phone: acc.phone,
                    otp: '654321',
                    role: acc.role === 'DOCTOR' ? 'Doctor' : acc.role,
                });
                assert.strictEqual(loginRes.status, 200, `Role ${acc.role} OTP login failed: ${JSON.stringify(loginRes.json)}`);
                assert.strictEqual(loginRes.json.success, true);
                assert.strictEqual(loginRes.json.user.id, acc.id);
                assert.ok(loginRes.json.accessToken && !loginRes.json.accessToken.startsWith('sb_direct_'));
            }

            // 3. Unsigned synthetic token sb_direct_<userId> MUST be rejected in staging/production
            const syntheticRes = await apiReq('GET', '/api/v1/admin/patients', {
                Authorization: 'Bearer sb_direct_u-adm-1'
            });
            assert.strictEqual(syntheticRes.status, 401, 'Unsigned sb_direct_ token must not authenticate in cloud mode');
        } finally {
            Schemas.User.findByMobile = origUserFindByMobile;
            Schemas.User.findOne = origUserFindOne;
            Schemas.User.findById = origUserFindById;
            Schemas.User.findByIdAndUpdate = origUserUpdate;
            Schemas.Dentist.findById = origDentistFindById;
            Schemas.Dentist.findOne = origDentistFindOne;
            Schemas.Clinic.findOne = origClinicFindOne;
            otpStoreService.verifyOtp = origVerifyOtp;
            if (prevEnv !== undefined) process.env.NODE_ENV = prevEnv; else delete process.env.NODE_ENV;
            if (prevAdminPhone !== undefined) process.env.ADMIN_PHONE = prevAdminPhone; else delete process.env.ADMIN_PHONE;
            if (prevJwt !== undefined) process.env.JWT_SECRET = prevJwt; else delete process.env.JWT_SECRET;
            if (prevRefresh !== undefined) process.env.REFRESH_SECRET = prevRefresh; else delete process.env.REFRESH_SECRET;
            if (prevSalt !== undefined) process.env.OTP_SALT = prevSalt; else delete process.env.OTP_SALT;
            await new Promise((resolve) => server.close(resolve));
        }
    });

    await asyncTest('40. Administrative route guards & CORS allowlist enforcement in staging/production', async () => {
        const httpModule = require('http');
        const jwt = require('jsonwebtoken');
        const app = require('../src/app');
        const Schemas = require('../src/models/Schemas');
        const { getJwtSecret } = require('../src/config/secrets');

        // 40A: CORS allowlist & staging loopback preflight evaluator
        const corsMiddleware = require('cors');
        const expressLib = require('express');
        const cloudNoOriginEval = app.buildCorsOriginEvaluator({ NODE_ENV: 'production', CORS_ORIGIN: '' });
        let corsAllowed = null;
        cloudNoOriginEval('https://evil.example.com', (err, allow) => { corsAllowed = !err && allow; });
        assert.strictEqual(corsAllowed, false, 'Unlisted browser origin must be blocked in production when CORS_ORIGIN is empty');
        cloudNoOriginEval('http://localhost:54321', (err, allow) => { corsAllowed = !err && allow; });
        assert.strictEqual(corsAllowed, false, 'Production must block localhost origins when CORS_ORIGIN is empty');

        const stagingNoOriginEval = app.buildCorsOriginEvaluator({ NODE_ENV: 'staging', CORS_ORIGIN: '' });
        stagingNoOriginEval('http://localhost:54321', (err, allow) => { corsAllowed = !err && allow; });
        assert.strictEqual(corsAllowed, true, 'Staging must allow Flutter Web localhost origin');
        stagingNoOriginEval('http://127.0.0.1:61234', (err, allow) => { corsAllowed = !err && allow; });
        assert.strictEqual(corsAllowed, true, 'Staging must allow Flutter Web 127.0.0.1 origin');
        stagingNoOriginEval('https://attacker.example.com', (err, allow) => { corsAllowed = !err && allow; });
        assert.strictEqual(corsAllowed, false, 'Staging must block untrusted public origins');

        const cloudAllowlistEval = app.buildCorsOriginEvaluator({
            NODE_ENV: 'staging',
            CORS_ORIGIN: 'https://staging.gshealth.in, https://admin.gshealth.in/'
        });
        cloudAllowlistEval('https://staging.gshealth.in', (err, allow) => { corsAllowed = !err && allow; });
        assert.strictEqual(corsAllowed, true, 'Allowlisted origin must be permitted');
        cloudAllowlistEval('http://localhost:54321', (err, allow) => { corsAllowed = !err && allow; });
        assert.strictEqual(corsAllowed, true, 'Staging allowlist still permits local Flutter Web loopback origin');
        cloudAllowlistEval('https://attacker.example.com', (err, allow) => { corsAllowed = !err && allow; });
        assert.strictEqual(corsAllowed, false, 'Non-allowlisted origin must be rejected');

        // Verify live OPTIONS preflight in staging returns 204 + Access-Control-Allow-Origin + x-staging-otp-key (never 500)
        const stagingApp = expressLib();
        const stagingCorsOpts = {
            origin: app.buildCorsOriginEvaluator({ NODE_ENV: 'staging', CORS_ORIGIN: '' }),
            methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
            allowedHeaders: ['Content-Type', 'Authorization', 'Accept', 'X-Requested-With', 'x-user-id', 'X-User-Id', 'x-staging-otp-key', 'X-Staging-Otp-Key'],
            credentials: true,
        };
        stagingApp.use(corsMiddleware(stagingCorsOpts));
        stagingApp.options('*', corsMiddleware(stagingCorsOpts));
        const preflightServer = httpModule.createServer(stagingApp);
        await new Promise((resolve) => preflightServer.listen(0, '127.0.0.1', resolve));
        try {
            const pPort = preflightServer.address().port;
            const runOptions = (origin) => new Promise((resolve, reject) => {
                const req = httpModule.request({
                    hostname: '127.0.0.1',
                    port: pPort,
                    path: '/api/v1/auth/otp/request',
                    method: 'OPTIONS',
                    headers: {
                        Origin: origin,
                        'Access-Control-Request-Method': 'POST',
                        'Access-Control-Request-Headers': 'content-type,x-staging-otp-key',
                    },
                }, (res) => {
                    res.resume();
                    res.on('end', () => resolve({ status: res.statusCode, headers: res.headers }));
                });
                req.on('error', reject);
                req.end();
            });

            const localPreflight = await runOptions('http://localhost:54321');
            assert.strictEqual(localPreflight.status, 204);
            assert.strictEqual(localPreflight.headers['access-control-allow-origin'], 'http://localhost:54321');
            assert.ok(String(localPreflight.headers['access-control-allow-headers'] || '').toLowerCase().includes('x-staging-otp-key'));

            const evilPreflight = await runOptions('https://attacker.example.com');
            assert.notStrictEqual(evilPreflight.status, 500, 'Disallowed origin must never trigger 500 Internal Server Error');
            assert.strictEqual(evilPreflight.headers['access-control-allow-origin'], undefined);
        } finally {
            await new Promise((resolve) => preflightServer.close(resolve));
        }

        // 40B: Patient, Clinic, Dentist, and Specialty administrative route protections
        const origFindById = Schemas.User.findById;
        const patientUser = { id: 'pat-guard-1', name: 'Patient Guard', email: 'pat@guard.local', role: 'Patient', status: 'ACTIVE' };
        Schemas.User.findById = async (id) => (id === patientUser.id ? patientUser : null);

        const server = httpModule.createServer(app);
        await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
        const { port } = server.address();

        const patientToken = jwt.sign({ id: patientUser.id, role: 'Patient' }, getJwtSecret(), { expiresIn: '15m' });

        const callRoute = (method, routePath, token = null) => new Promise((resolve, reject) => {
            const req = httpModule.request({
                hostname: '127.0.0.1',
                port,
                path: routePath,
                method,
                headers: {
                    'Content-Type': 'application/json',
                    ...(token ? { Authorization: `Bearer ${token}` } : {}),
                }
            }, (res) => {
                res.resume();
                res.on('end', () => resolve(res.statusCode));
            });
            req.on('error', reject);
            if (method === 'POST' || method === 'PUT' || method === 'PATCH') {
                req.write(JSON.stringify({ name: 'Unauthorized Attempt' }));
            }
            req.end();
        });

        try {
            // Unauthenticated requests -> 401
            assert.strictEqual(await callRoute('GET', '/api/v1/admin/patients'), 401);
            assert.strictEqual(await callRoute('GET', '/api/v1/patients'), 401);
            assert.strictEqual(await callRoute('DELETE', '/api/v1/clinics/c-1'), 401);
            assert.strictEqual(await callRoute('DELETE', '/api/v1/dentists/d-1'), 401);
            assert.strictEqual(await callRoute('POST', '/api/v1/specialties'), 401);
            assert.strictEqual(await callRoute('GET', '/api/v1/admin/specialties'), 401);
            assert.strictEqual(await callRoute('POST', '/api/v1/clinics'), 401);

            // Authenticated Patient role -> 403 Forbidden across admin & clinic/doctor mutation endpoints
            assert.strictEqual(await callRoute('GET', '/api/v1/admin/patients', patientToken), 403);
            assert.strictEqual(await callRoute('DELETE', '/api/v1/clinics/c-1', patientToken), 403);
            assert.strictEqual(await callRoute('DELETE', '/api/v1/dentists/d-1', patientToken), 403);
            assert.strictEqual(await callRoute('POST', '/api/v1/specialties', patientToken), 403);
            assert.strictEqual(await callRoute('GET', '/api/v1/admin/specialties', patientToken), 403);
            assert.strictEqual(await callRoute('POST', '/api/v1/clinics', patientToken), 403);
            assert.strictEqual(await callRoute('POST', '/api/v1/clinics/c-1/doctors', patientToken), 403);
            assert.strictEqual(await callRoute('PUT', '/api/v1/dentists/d-1/profile', patientToken), 403);
        } finally {
            Schemas.User.findById = origFindById;
            await new Promise((resolve) => server.close(resolve));
        }
    });

    await asyncTest('41. render.yaml configures both Production and Testing Render Starter services with dashboard-managed secrets', async () => {
        const renderYamlPath = path.resolve(__dirname, '../../render.yaml');
        const renderYaml = fs.readFileSync(renderYamlPath, 'utf8');

        assert.ok(renderYaml.includes('name: dentaguru-backend'), 'Must define production service dentaguru-backend');
        assert.ok(renderYaml.includes('name: dentaguru-backend-test'), 'Must define testing service dentaguru-backend-test');
        assert.strictEqual((renderYaml.match(/plan:\s*starter/g) || []).length, 2, 'Both services must use Render Starter plan');
        assert.strictEqual((renderYaml.match(/rootDir:\s*backend/g) || []).length, 2, 'Both services must set rootDir: backend');
        assert.strictEqual((renderYaml.match(/startCommand:\s*node src\/server\.js/g) || []).length, 2, 'Both services must set startCommand: node src/server.js');
        assert.strictEqual((renderYaml.match(/healthCheckPath:\s*\/health/g) || []).length, 2, 'Both services must set healthCheckPath: /health');
        assert.ok(renderYaml.includes('value: production'), 'Production service must set NODE_ENV=production');
        assert.ok(renderYaml.includes('value: staging'), 'Testing service must set NODE_ENV=staging');
        assert.ok(renderYaml.includes('key: OTP_DELIVERY_MODE\n        value: on_screen'), 'Testing service must set OTP_DELIVERY_MODE=on_screen');
        assert.ok(renderYaml.includes('key: STAGING_OTP_ACCESS_KEY\n        sync: false'), 'Testing service must declare STAGING_OTP_ACCESS_KEY');
        assert.ok(!renderYaml.includes('ON_SCREEN_OTP_ALLOWLIST'), 'Staging render config must not restrict phones via ON_SCREEN_OTP_ALLOWLIST');
        assert.ok(!renderYaml.includes('fommrwxpqzkcktweosgp'), 'render.yaml must never hardcode Supabase project refs or secrets');
    });

    console.log('\n=================================================');
    console.log(`RESULTS: ${passed} Passed, ${failed} Failed`);
    console.log('=================================================\n');

    if (failed > 0) process.exit(1);
}

runTests().catch(err => {
    console.error('Fatal test error:', err);
    process.exit(1);
});
