const path = require('path');
require('dotenv').config({ path: path.resolve(__dirname, '../../.env') });
const { User, Dentist } = require('../models/Schemas');
const authController = require('../controllers/authController');
const jwt = require('jsonwebtoken');

const JWT_SECRET = process.env.JWT_SECRET || 'supersecretjwtkey123';
const REFRESH_SECRET = process.env.REFRESH_SECRET || 'supersecretrefreshkey456';

async function runMultiDeviceDoctorTest() {
    console.log('====================================================');
    console.log('🩺 TESTING DOCTOR MULTI-DEVICE SIMULTANEOUS LOGIN');
    console.log('====================================================\n');

    try {
        // 1. Find or create a test Doctor
        let doctor = await User.findOne({ role: 'Dentist' });
        if (!doctor) {
            console.log('Creating a test Doctor account...');
            doctor = await User.create({
                name: 'Dr. MultiDevice Test',
                email: 'dr.multidevice@dentaguru.internal',
                phone: '9888877777',
                role: 'Dentist',
                city: 'Hyderabad',
                pincode: '500081',
                state: 'Telangana'
            });
        }

        console.log(`✅ Doctor Account: ID=${doctor.id}, Name=${doctor.name}, Phone=${doctor.phone}`);

        // Helper to mock express req/res
        function mockReqRes(body, headers = {}) {
            let resData = null;
            let statusCode = 200;
            const req = { body, headers, user: null };
            const res = {
                status(code) {
                    statusCode = code;
                    return this;
                },
                json(data) {
                    resData = data;
                    return this;
                }
            };
            return { req, res, getResult: () => ({ statusCode, data: resData }) };
        }

        // 2. Step 1: Doctor Device (Device 1) Login
        console.log('\n--- 📱 DEVICE 1 (Doctor Phone) LOGIN ---');
        // Request OTP for Device 1
        const otpReq1 = mockReqRes({ phone: doctor.phone });
        await authController.requestOTP(otpReq1.req, otpReq1.res);
        const otp1 = otpReq1.getResult().data.otp;
        console.log(`1. Device 1 requested OTP: received ${otp1}`);

        // Device 1 logs in with OTP
        const login1 = mockReqRes({ phone: doctor.phone, otp: otp1, role: 'Dentist' });
        await authController.login(login1.req, login1.res);
        const res1 = login1.getResult();
        console.log(`2. Device 1 login response status: ${res1.statusCode}, success: ${res1.data?.success}`);
        if (!res1.data?.success) throw new Error('Device 1 login failed');

        const device1AccessToken = res1.data.accessToken;
        const device1RefreshToken = res1.data.refreshToken;
        console.log(`3. Device 1 Token Generated. AccessToken valid: ${!!device1AccessToken}`);

        // 3. Step 2: Receptionist Device (Device 2) Login using SAME Doctor Mobile Number
        console.log('\n--- 💻 DEVICE 2 (Receptionist Desk) LOGIN ---');
        // Request OTP for Device 2
        const otpReq2 = mockReqRes({ phone: doctor.phone });
        await authController.requestOTP(otpReq2.req, otpReq2.res);
        const otp2 = otpReq2.getResult().data.otp;
        console.log(`1. Device 2 requested OTP for same Doctor phone: received ${otp2}`);

        // Device 2 logs in with OTP
        const login2 = mockReqRes({ phone: doctor.phone, otp: otp2, role: 'Dentist' });
        await authController.login(login2.req, login2.res);
        const res2 = login2.getResult();
        console.log(`2. Device 2 login response status: ${res2.statusCode}, success: ${res2.data?.success}`);
        if (!res2.data?.success) throw new Error('Device 2 login failed');

        const device2AccessToken = res2.data.accessToken;
        const device2RefreshToken = res2.data.refreshToken;
        console.log(`3. Device 2 Token Generated. AccessToken valid: ${!!device2AccessToken}`);

        // 4. Verification Check 1: Both devices point to the EXACT same doctor user ID
        console.log('\n--- 🔍 VERIFICATION: USER IDENTITY & DATA PARITY ---');
        console.log(`Device 1 User ID: ${res1.data.user.id}`);
        console.log(`Device 2 User ID: ${res2.data.user.id}`);
        if (res1.data.user.id === res2.data.user.id && res1.data.user.id === doctor.id) {
            console.log('✅ TEST 1 PASSED: Both devices share the exact same Doctor Account/User ID.');
        } else {
            throw new Error('TEST 1 FAILED: User IDs do not match');
        }

        // 5. Verification Check 2: Device 1 JWT verification while Device 2 is active
        console.log('\n--- 🔍 VERIFICATION: SIMULTANEOUS ACCESS VALIDITY ---');
        const decoded1 = jwt.verify(device1AccessToken, JWT_SECRET);
        const decoded2 = jwt.verify(device2AccessToken, JWT_SECRET);
        console.log(`Device 1 decoded role: ${decoded1.role}, id: ${decoded1.id}`);
        console.log(`Device 2 decoded role: ${decoded2.role}, id: ${decoded2.id}`);
        if (decoded1.id === doctor.id && decoded2.id === doctor.id) {
            console.log('✅ TEST 2 PASSED: Both Device 1 and Device 2 access tokens are simultaneously active.');
        } else {
            throw new Error('TEST 2 FAILED: Access tokens validation mismatch');
        }

        // 6. Verification Check 3: Device 1 Refresh Token is NOT invalidated by Device 2 login
        console.log('\n--- 🔍 VERIFICATION: REFRESH TOKEN MULTI-DEVICE PERSISTENCE ---');
        const refreshReq1 = mockReqRes({ token: device1RefreshToken });
        await authController.refreshToken(refreshReq1.req, refreshReq1.res);
        const refreshRes1 = refreshReq1.getResult();
        console.log(`Device 1 refresh status: ${refreshRes1.statusCode}, success: ${refreshRes1.data?.success}`);
        if (refreshRes1.data?.success && refreshRes1.data.accessToken) {
            console.log('✅ TEST 3 PASSED: Device 1 session remained 100% active and successfully refreshed its token!');
        } else {
            throw new Error(`TEST 3 FAILED: Device 1 session was invalidated: ${JSON.stringify(refreshRes1.data)}`);
        }

        // 7. Verification Check 4: Device 2 Refresh Token is also valid
        const refreshReq2 = mockReqRes({ token: device2RefreshToken });
        await authController.refreshToken(refreshReq2.req, refreshReq2.res);
        const refreshRes2 = refreshReq2.getResult();
        console.log(`Device 2 refresh status: ${refreshRes2.statusCode}, success: ${refreshRes2.data?.success}`);
        if (refreshRes2.data?.success && refreshRes2.data.accessToken) {
            console.log('✅ TEST 4 PASSED: Device 2 session is 100% active and successfully refreshed its token!');
        } else {
            throw new Error(`TEST 4 FAILED: Device 2 session failed to refresh: ${JSON.stringify(refreshRes2.data)}`);
        }

        console.log('\n====================================================');
        console.log('🎉 ALL DOCTOR MULTI-DEVICE TESTS PASSED SUCCESSFULLY!');
        console.log('====================================================');

    } catch (e) {
        console.error('❌ Test error:', e.message);
        process.exit(1);
    } finally {
        process.exit(0);
    }
}

runMultiDeviceDoctorTest();
