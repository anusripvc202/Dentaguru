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

    console.log('\n=================================================');
    console.log(`RESULTS: ${passed} Passed, ${failed} Failed`);
    console.log('=================================================\n');

    if (failed > 0) process.exit(1);
}

runTests().catch(err => {
    console.error('Fatal test error:', err);
    process.exit(1);
});
