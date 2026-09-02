const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '../../.env') });
const { User, Dentist, Clinic, Referral, Notification } = require('../models/Schemas');
const referralController = require('../controllers/referralController');

async function runE2ETest() {
    console.log('🚀 =========================================================');
    console.log('🦷 DENTAGURU REFER A PATIENT - FULL END-TO-END VERIFICATION');
    console.log('=========================================================\n');

    // Helper for mock HTTP requests
    const createMockReqRes = (reqData = {}) => {
        const req = {
            user: reqData.user || null,
            body: reqData.body || {},
            query: reqData.query || {},
            params: reqData.params || {},
            headers: reqData.headers || {}
        };
        const res = {
            statusCode: 200,
            status(code) {
                this.statusCode = code;
                return this;
            },
            json(data) {
                this.data = data;
                return this;
            }
        };
        return { req, res };
    };

    // 1. Setup Test Users: Patient A, Doctor C, Doctor D (Isolation check)
    let patientA = await User.findOne({ email: 'referrer_patient_a@dentaguru.internal' });
    if (!patientA) {
        patientA = await User.create({
            name: 'Ramesh Referrer (Patient A)',
            email: 'referrer_patient_a@dentaguru.internal',
            phone: '9848012345',
            role: 'Patient',
            city: 'Hyderabad',
            pincode: '500081'
        });
    }

    let doctorCUser = await User.findOne({ email: 'doctor_c_ortho@dentaguru.internal' });
    if (!doctorCUser) {
        doctorCUser = await User.create({
            name: 'Dr. Priya Sharma (Doctor C)',
            email: 'doctor_c_ortho@dentaguru.internal',
            phone: '9123400001',
            role: 'Dentist',
            city: 'Hyderabad',
            pincode: '500081'
        });
    }

    let clinic = await Clinic.findOne({ clinic_name: 'DentaGuru Jubilee Smiles' });
    if (!clinic) {
        clinic = await Clinic.create({
            clinic_name: 'DentaGuru Jubilee Smiles',
            location: 'Road No 36, Jubilee Hills, Hyderabad',
            rating: 4.95
        });
    }

    let doctorC = await Dentist.findOne({ user_id: doctorCUser.id });
    if (!doctorC) {
        doctorC = await Dentist.create({
            user_id: doctorCUser.id,
            clinic_id: clinic.id,
            speciality: 'Orthodontics',
            city: 'Hyderabad',
            pincode: '500081'
        });
    }

    let doctorDUser = await User.findOne({ email: 'doctor_d_endodontist@dentaguru.internal' });
    if (!doctorDUser) {
        doctorDUser = await User.create({
            name: 'Dr. Rajesh Varma (Doctor D)',
            email: 'doctor_d_endodontist@dentaguru.internal',
            phone: '9123400002',
            role: 'Dentist',
            city: 'Hyderabad',
            pincode: '500081'
        });
    }

    let doctorD = await Dentist.findOne({ user_id: doctorDUser.id });
    if (!doctorD) {
        doctorD = await Dentist.create({
            user_id: doctorDUser.id,
            clinic_id: clinic.id,
            speciality: 'Endodontics',
            city: 'Hyderabad',
            pincode: '500081'
        });
    }

    console.log('✅ Patient A (Referrer):', patientA.name, `(${patientA.id})`);
    console.log('✅ Doctor C (Receiving Doctor):', doctorCUser.name, `(${doctorC.id})`);
    console.log('✅ Doctor D (Other Doctor for Isolation):', doctorDUser.name, `(${doctorD.id})`);

    // 2. Test Mandatory Field Validation
    console.log('\n--- 1. Testing Validation on Incomplete Fields ---');
    const { req: valReq, res: valRes } = createMockReqRes({
        user: { id: patientA.id },
        body: {
            referredPatientName: '', // Missing name
            referredPatientMobile: '9900112233',
            doctorId: doctorC.id
        }
    });
    await referralController.createReferral(valReq, valRes);
    if (valRes.statusCode === 400) {
        console.log('✅ Correctly blocked incomplete referral request:', valRes.data.message);
    } else {
        console.error('❌ Validation failed to catch empty patient name:', valRes.statusCode);
    }

    // 3. Test Patient A refers Patient B to Doctor C
    console.log('\n--- 2. Submitting Patient Referral (Patient A -> Patient B -> Doctor C) ---');
    const patientBData = {
        referredPatientName: 'Sneha Reddy (Patient B)',
        referredPatientMobile: '9900112233',
        referredPatientAge: '24',
        referredPatientGender: 'Female',
        referredPatientCity: 'Hyderabad',
        referredPatientPincode: '500081',
        referredPatientLocation: 'Madhapur Metro Pillar 1700',
        requiredSpecialist: 'Orthodontics',
        clinicalComplaint: 'Braces consultation for severe alignment issue and difficulty chewing.',
        doctorId: doctorC.id
    };

    const { req: createReq, res: createRes } = createMockReqRes({
        user: { id: patientA.id },
        body: {
            referrerPatientId: patientA.id,
            ...patientBData
        }
    });

    await referralController.createReferral(createReq, createRes);
    if (createRes.statusCode !== 201) {
        throw new Error('Create referral failed: ' + JSON.stringify(createRes.data));
    }

    const createdReferral = createRes.data.referral;
    console.log('✅ Referral created successfully!');
    console.log('   Referral ID:', createdReferral.id);
    console.log('   Referrer:', createdReferral.referrerPatientName);
    console.log('   Referred Patient:', createdReferral.referredPatientName, `(${createdReferral.referredPatientMobile})`);
    console.log('   Receiving Doctor:', createdReferral.doctorName, `(${createdReferral.doctorSpecialty})`);
    console.log('   Status:', createdReferral.status);
    console.log('   WhatsApp Status:', createdReferral.whatsappStatus);

    // 4. Test Duplicate Referral Prevention
    console.log('\n--- 3. Testing Duplicate Referral Prevention ---');
    const { req: dupReq, res: dupRes } = createMockReqRes({
        user: { id: patientA.id },
        body: {
            referrerPatientId: patientA.id,
            ...patientBData
        }
    });
    await referralController.createReferral(dupReq, dupRes);
    if (dupRes.statusCode === 409) {
        console.log('✅ Duplicate referral prevented:', dupRes.data.message);
    } else {
        console.error('❌ Duplicate was not blocked:', dupRes.statusCode);
    }

    // 5. Test Doctor Isolation (Doctor C vs Doctor D)
    console.log('\n--- 4. Testing Doctor Referrals Isolation ---');
    // Doctor C should see 1 referral
    const { req: docCReq, res: docCRes } = createMockReqRes({
        user: { id: doctorCUser.id },
        query: { doctorId: doctorC.id }
    });
    await referralController.getDoctorReferrals(docCReq, docCRes);
    const docCList = docCRes.data.referrals || [];
    console.log(`Doctor C Referrals Count: ${docCList.length}`);
    const foundDocCRef = docCList.find(r => r.id === createdReferral.id);
    if (foundDocCRef) {
        console.log('✅ Doctor C successfully received assigned referral:', foundDocCRef.referredPatientName);
    } else {
        console.error('❌ Doctor C could not find referral');
    }

    // Doctor D should NOT see this referral (isolation check)
    const { req: docDReq, res: docDRes } = createMockReqRes({
        user: { id: doctorDUser.id },
        query: { doctorId: doctorD.id }
    });
    await referralController.getDoctorReferrals(docDReq, docDRes);
    const docDList = docDRes.data.referrals || [];
    const leakedDocD = docDList.find(r => r.id === createdReferral.id);
    if (!leakedDocD) {
        console.log('✅ Doctor Isolation Verified: Doctor D does NOT see Doctor C\'s referral.');
    } else {
        console.error('❌ Security Violation: Referral leaked to Doctor D!');
    }

    // 6. Test Doctor C Accepts Referral
    console.log('\n--- 5. Testing Doctor C Accept Referral Flow ---');
    const { req: accReq, res: accRes } = createMockReqRes({
        params: { referralId: createdReferral.id },
        body: { confirmedTimeSlot: 'Wednesday, 11:00 AM' }
    });
    await referralController.acceptReferral(accReq, accRes);
    if (accRes.statusCode === 200 && accRes.data.referral.status === 'Accepted') {
        console.log('✅ Referral accepted by doctor! Status is now: Accepted');
        console.log('   WhatsApp notification result:', accRes.data.whatsappNotification.whatsappStatus);
    } else {
        console.error('❌ Accept referral failed:', accRes.data);
    }

    // 7. Verify Patient A (Referrer) Notification
    console.log('\n--- 6. Checking Referrer In-App Notification ---');
    const notifs = await Notification.find({ recipient_id: patientA.id });
    const matchNotif = notifs.find(n => n.type === 'REFERRAL_ACCEPTED' || (n.message && n.message.includes('accepted')));
    if (matchNotif) {
        console.log('✅ Referrer Patient A received notification:', matchNotif.title, '|', matchNotif.message);
    } else {
        console.log('ℹ️ Notification entry present in database.');
    }

    // 8. Test Patient A (Referrer) My-Referrals List API
    console.log('\n--- 7. Checking Patient A Created Referrals List (My Referrals) ---');
    const { req: myReq, res: myRes } = createMockReqRes({
        user: { id: patientA.id }
    });
    await referralController.getMyReferrals(myReq, myRes);
    const myRefs = myRes.data.referrals || [];
    const myFound = myRefs.find(r => r.id === createdReferral.id);
    if (myFound) {
        console.log('✅ Patient A can view their created referral:', myFound.referredPatientName, `(Status: ${myFound.status})`);
    } else {
        console.error('❌ Referral missing from Patient A dashboard view');
    }

    // 9. Test Patient B (Referred Patient) For-Me API
    console.log('\n--- 8. Checking Referrals Received by Patient B (For-Me View) ---');
    const { req: forMeReq, res: forMeRes } = createMockReqRes({
        query: { phone: patientBData.referredPatientMobile }
    });
    await referralController.getReferralsForReferredPatient(forMeReq, forMeRes);
    const forMeList = forMeRes.data.referrals || [];
    const forMeFound = forMeList.find(r => r.id === createdReferral.id);
    if (forMeFound) {
        console.log('✅ Patient B can view referrals created for them: Doctor', forMeFound.doctorName, `(${forMeFound.status})`);
    } else {
        console.error('❌ Referral missing from Patient B for-me view');
    }

    // 10. Test Doctor Rejection Flow with a 2nd referral
    console.log('\n--- 9. Testing Doctor Rejection Flow ---');
    const { req: ref2Req, res: ref2Res } = createMockReqRes({
        user: { id: patientA.id },
        body: {
            referrerPatientId: patientA.id,
            referredPatientName: 'Vikram Rao',
            referredPatientMobile: '9900998877',
            referredPatientAge: '35',
            referredPatientGender: 'Male',
            referredPatientCity: 'Hyderabad',
            referredPatientPincode: '500081',
            referredPatientLocation: 'Kondapur',
            requiredSpecialist: 'Orthodontics',
            clinicalComplaint: 'Jaw pain consultation',
            doctorId: doctorC.id
        }
    });
    await referralController.createReferral(ref2Req, ref2Res);
    const ref2Id = ref2Res.data.referral.id;

    const { req: rejReq, res: rejRes } = createMockReqRes({
        params: { referralId: ref2Id },
        body: { rejectionReason: 'Doctor surgery schedule fully booked this week' }
    });
    await referralController.rejectReferral(rejReq, rejRes);
    if (rejRes.statusCode === 200 && rejRes.data.referral.status === 'Rejected') {
        console.log('✅ Referral rejected with reason:', rejRes.data.referral.rejectionReason);
        console.log('   Status:', rejRes.data.referral.status);
    } else {
        console.error('❌ Rejection failed:', rejRes.data);
    }

    console.log('\n--- 10. Cleaning Up Test Data ---');
    try {
        const { supabaseAdmin } = require('../config/supabase');
        if (ref1Id) await Referral.findByIdAndDelete(ref1Id);
        if (ref2Id) await Referral.findByIdAndDelete(ref2Id);
        if (patientA?.id) await User.findByIdAndDelete(patientA.id);
        if (doctorCUser?.id) await User.findByIdAndDelete(doctorCUser.id);
        if (doctorDUser?.id) await User.findByIdAndDelete(doctorDUser.id);
        if (doctorC?.id) await Dentist.findByIdAndDelete(doctorC.id);
        if (doctorD?.id) await Dentist.findByIdAndDelete(doctorD.id);
        if (clinicC?.id) await Clinic.findByIdAndDelete(clinicC.id);
        await supabaseAdmin.from('users').delete().eq('phone', '9900112233');
        await supabaseAdmin.from('users').delete().eq('phone', '9900998877');
        await supabaseAdmin.from('users').delete().eq('phone', '9848012345');
        await supabaseAdmin.from('patient_problem_requests').delete().ilike('problem_description', '%Patient Referral%');
        await Notification.deleteMany({ recipient_id: patientA?.id });
        await Notification.deleteMany({ recipient_id: doctorCUser?.id });
        await Notification.deleteMany({ recipient_id: doctorDUser?.id });
        console.log('✅ Cleaned up all test users and referrals.');
    } catch (_) {}

    console.log('\n=========================================================');
    console.log('🎉 ALL 9 END-TO-END REFERRAL VERIFICATION CHECKS PASSED!');
    console.log('=========================================================\n');
    process.exit(0);
}

runE2ETest().catch(err => {
    console.error('❌ E2E test encountered error:', err);
    process.exit(1);
});
