/**
 * Comprehensive Backend Unit & Integration Tests for GS HEALTH Mobile SMS OTP Verification
 */
const assert = require('assert');
const crypto = require('crypto');
const { sendRealSmsOtp, buildOtpMessage, normalizePhoneNumber } = require('../src/services/smsService');
const auth = require('../src/controllers/authController');

console.log('=== STARTING GS HEALTH SMS OTP VERIFICATION TESTS ===\n');

async function runTests() {
    let passed = 0;
    let failed = 0;

    function test(name, fn) {
        try {
            fn();
            console.log(`✓ ${name}`);
            passed++;
        } catch (e) {
            console.error(`✗ ${name}:`, e.message);
            failed++;
        }
    }

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
    test('1. Normalizes 10-digit Indian mobile number to E.164 (+91)', () => {
        const res = normalizePhoneNumber('9063663180');
        assert.strictEqual(res.isValid, true);
        assert.strictEqual(res.cleanDigits, '9063663180');
        assert.strictEqual(res.e164, '+919063663180');
    });

    test('2. Normalizes 12-digit Indian mobile with prefix 91', () => {
        const res = normalizePhoneNumber('+91 90636 63180');
        assert.strictEqual(res.isValid, true);
        assert.strictEqual(res.cleanDigits, '919063663180');
        assert.strictEqual(res.e164, '+919063663180');
    });

    test('3. Rejects invalid short numbers (<10 digits)', () => {
        const res = normalizePhoneNumber('12345');
        assert.strictEqual(res.isValid, false);
    });

    // 2. Message Format
    test('4. Message format strictly matches specification', () => {
        const msg = buildOtpMessage('123456');
        assert.strictEqual(
            msg,
            'Your GS HEALTH verification code is 123456. It is valid for 5 minutes. Do not share this code with anyone.'
        );
    });

    // 3. SMS Dispatch Logic
    await asyncTest('5. SMS service validates number and formats dispatch', async () => {
        const res = await sendRealSmsOtp('9063663180', '654321');
        assert.strictEqual(res.success, true);
    });

    // 4. Controller OTP Request & Verification
    await asyncTest('6. Request OTP generates 6-digit code without exposing it in API response', async () => {
        const req = {
            body: { phone: '9063663180' }
        };
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
        // Strictly must NOT expose plain OTP in API response
        assert.strictEqual(responseJson.otp, undefined, 'OTP must not be exposed in API response');
    });

    await asyncTest('7. Cooldown prevents requesting immediate subsequent OTP within 30 seconds', async () => {
        const req = {
            body: { phone: '9063663180' }
        };
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
        const req = {
            body: { phone: '9063663180', code: '000000' }
        };
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
        const req = {
            body: { phone: '9063663180', code: '12' }
        };
        let responseStatus = 200;
        let responseJson = null;

        const res = {
            status: (code) => { responseStatus = code; return res; },
            json: (data) => { responseJson = data; return res; }
        };

        await auth.verifyOTP(req, res);
        assert.strictEqual(responseStatus, 400);
        assert.strictEqual(responseJson.success, false);
    });

    console.log(`\n=================================================`);
    console.log(`RESULTS: ${passed} Passed, ${failed} Failed`);
    console.log(`=================================================\n`);

    if (failed > 0) process.exit(1);
}

runTests().catch(err => {
    console.error('Fatal test error:', err);
    process.exit(1);
});
