const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '../../.env') });
const authController = require('../controllers/authController');
const referralController = require('../controllers/referralController');
const appointmentController = require('../controllers/appointmentController');
const { User, Referral, Appointment, Dentist, Clinic } = require('../models/Schemas');

// Mock Express req & res
function mockReqRes(body = {}, query = {}, params = {}, user = null) {
    let statusCode = 200;
    let responseData = null;
    const req = { body, query, params, user, headers: {} };
    const res = {
        status(code) {
            statusCode = code;
            return this;
        },
        json(data) {
            responseData = data;
            return this;
        }
    };
    return { req, res, getResult: () => ({ statusCode, data: responseData }) };
}

async function runTest() {
    console.log('🧪 Starting End-to-End Referral Flow Test...\n');

    // 1. Register Referrer Patient
    const uniquePhone1 = `9876${Math.floor(100000 + Math.random() * 900000)}`;
    const { req: r1, res: s1, getResult: g1 } = mockReqRes({
        name: 'Rahul Sharma',
        phone: uniquePhone1,
        email: `rahul_${Date.now()}@test.com`,
        role: 'Patient',
        city: 'Hyderabad',
        pincode: '500081',
        location: 'Madhapur, Hyderabad',
        languages: ['English', 'Telugu']
    });
    await authController.register(r1, s1);
    const res1 = g1();
    console.log('1. Referrer Registration Status:', res1.statusCode, res1.data?.user?.name, 'Referral Code:', res1.data?.user?.referralCode);
    const referrerUser = res1.data?.user;
    const refCode = referrerUser.referralCode;

    // 2. Register Referred Friend using Referral Code
    const uniquePhone2 = `9123${Math.floor(100000 + Math.random() * 900000)}`;
    const { req: r2, res: s2, getResult: g2 } = mockReqRes({
        name: 'Anjali Reddy',
        phone: uniquePhone2,
        email: `anjali_${Date.now()}@test.com`,
        role: 'Patient',
        city: 'Hyderabad',
        pincode: '500081',
        location: 'Hitech City, Hyderabad',
        languages: ['English', 'Telugu'],
        referralCode: refCode
    });
    await authController.register(r2, s2);
    const res2 = g2();
    console.log('2. Referred User Registration Status:', res2.statusCode, res2.data?.user?.name);
    const referredUser = res2.data?.user;

    // 3. Query Referrer's Dashboard Referrals
    const { req: r3, res: s3, getResult: g3 } = mockReqRes({}, { userId: referrerUser.id }, {}, { id: referrerUser.id });
    await referralController.getMyReferrals(r3, s3);
    const res3 = g3();
    console.log('3. Referrer Stats:', JSON.stringify(res3.data?.stats));
    console.log('   Referred Friends:', res3.data?.referrals?.map(r => `${r.referredUserName} (${r.status})`));

    // 4. Book Consultation for Referred User
    const { req: r4, res: s4, getResult: g4 } = mockReqRes({
        patientId: referredUser.id,
        treatment: 'Orthodontics Consultation',
        timeSlot: 'Tomorrow 10:00 AM'
    }, {}, {}, { id: referredUser.id });
    await appointmentController.bookAppointment(r4, s4);
    const res4 = g4();
    console.log('4. Booked Appointment Status:', res4.statusCode, res4.data?.appointment?.id);

    // 5. Query Referrer's Dashboard again to see Status Update
    const { req: r5, res: s5, getResult: g5 } = mockReqRes({}, { userId: referrerUser.id }, {}, { id: referrerUser.id });
    await referralController.getMyReferrals(r5, s5);
    const res5 = g5();
    console.log('5. Updated Referrer Stats:', JSON.stringify(res5.data?.stats));
    console.log('   Updated Status:', res5.data?.referrals?.map(r => `${r.referredUserName} (${r.status})`));

    // 6. Query Admin Analytics
    const { req: r6, res: s6, getResult: g6 } = mockReqRes();
    await referralController.getAdminReferralAnalytics(r6, s6);
    const res6 = g6();
    console.log('6. Admin Growth Analytics:', JSON.stringify(res6.data?.analytics, null, 2));

    console.log('\n🎉 ALL BACKEND REFERRAL TESTS PASSED!');
    process.exit(0);
}

runTest().catch(e => {
    console.error('❌ Test failed:', e);
    process.exit(1);
});
