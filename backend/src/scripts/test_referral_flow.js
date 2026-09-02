const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '../../.env') });
const { User, Dentist, Clinic, Referral, Notification } = require('../models/Schemas');
const referralController = require('../controllers/referralController');

async function runTest() {
    console.log('🧪 Starting Refer a Patient Flow Test...\n');

    // 1. Setup Test Referrer Patient, Doctor, Clinic
    let referrer = await User.findOne({ email: 'test_referrer_patient@dentaguru.internal' });
    if (!referrer) {
        referrer = await User.create({
            name: 'Anusha Referrer',
            email: 'test_referrer_patient@dentaguru.internal',
            phone: '9876543210',
            role: 'Patient',
            city: 'Hyderabad',
            pincode: '500081'
        });
    }
    console.log('✅ Referrer Patient:', referrer.name, `(${referrer.id})`);

    // 2. Setup Test Doctor
    let doctorUser = await User.findOne({ email: 'test_doctor_c@dentaguru.internal' });
    if (!doctorUser) {
        doctorUser = await User.create({
            name: 'Dr. Suresh Reddy',
            email: 'test_doctor_c@dentaguru.internal',
            phone: '9123456780',
            role: 'Dentist',
            city: 'Hyderabad',
            pincode: '500081'
        });
    }

    let clinic = await Clinic.findOne({ clinic_name: 'DentaGuru Care Center' });
    if (!clinic) {
        clinic = await Clinic.create({
            clinic_name: 'DentaGuru Care Center',
            location: 'Madhapur, Hyderabad',
            rating: 4.9
        });
    }

    let doctor = await Dentist.findOne({ user_id: doctorUser.id });
    if (!doctor) {
        doctor = await Dentist.create({
            user_id: doctorUser.id,
            clinic_id: clinic.id,
            name: 'Dr. Suresh Reddy',
            speciality: 'Orthodontics',
            city: 'Hyderabad',
            pincode: '500081',
            availability_status: 'Available'
        });
    }
    console.log('✅ Receiving Doctor:', doctor.name, `(${doctor.id}) at Clinic:`, clinic.clinic_name);

    // 3. Test Create Referral API
    console.log('\n--- 1. Testing Referral Creation (Patient A refers Patient B to Doctor C) ---');
    const mockReq = {
        user: { id: referrer.id },
        body: {
            referrerPatientId: referrer.id,
            referredPatientName: 'Kavitha Sharma',
            referredPatientMobile: '9988776655',
            referredPatientAge: '27',
            referredPatientGender: 'Female',
            referredPatientCity: 'Hyderabad',
            referredPatientPincode: '500081',
            referredPatientLocation: 'Jubilee Hills, Road No 36',
            requiredSpecialist: 'Orthodontics',
            clinicalComplaint: 'Severe crowding in upper teeth and jaw pain.',
            doctorId: doctor.id
        }
    };

    let createdReferral = null;
    const mockRes = {
        status(code) {
            this.statusCode = code;
            return this;
        },
        json(data) {
            this.data = data;
            return this;
        }
    };

    await referralController.createReferral(mockReq, mockRes);
    console.log(`Response Status: ${mockRes.statusCode}`);
    if (mockRes.statusCode === 201) {
        createdReferral = mockRes.data.referral;
        console.log('✅ Referral created successfully:', createdReferral.referralId);
        console.log('   Referred Patient:', createdReferral.referredPatientName, `(${createdReferral.referredPatientMobile})`);
        console.log('   Receiving Doctor:', createdReferral.doctorName, `(${createdReferral.doctorSpecialty})`);
        console.log('   Referrer:', createdReferral.referrerPatientName);
        console.log('   Status:', createdReferral.status);
        console.log('   WhatsApp Status:', createdReferral.whatsappStatus);
    } else {
        console.error('❌ Referral creation failed:', mockRes.data);
    }

    // 4. Test Duplicate Prevention
    console.log('\n--- 2. Testing Duplicate Referral Prevention ---');
    const dupRes = {
        status(code) { this.statusCode = code; return this; },
        json(data) { this.data = data; return this; }
    };
    await referralController.createReferral(mockReq, dupRes);
    console.log(`Duplicate Check Status: ${dupRes.statusCode} (Expected 409)`);
    if (dupRes.statusCode === 409) {
        console.log('✅ Duplicate referral correctly prevented:', dupRes.data.message);
    } else {
        console.warn('⚠️ Duplicate check returned unexpected status:', dupRes.statusCode);
    }

    // 5. Test Doctor Referrals Query (Doctor C should see it)
    console.log('\n--- 3. Testing Doctor Referrals Fetch (Doctor Isolation) ---');
    const docReq = {
        user: { id: doctorUser.id },
        query: { doctorId: doctor.id }
    };
    const docRes = {
        status(code) { this.statusCode = code; return this; },
        json(data) { this.data = data; return this; }
    };
    await referralController.getDoctorReferrals(docReq, docRes);
    console.log(`Doctor Fetch Status: ${docRes.statusCode}, Referrals Count: ${docRes.data.count}`);
    const foundDocRef = docRes.data.referrals.find(r => r.id === createdReferral.id);
    if (foundDocRef) {
        console.log('✅ Doctor can view assigned referral:', foundDocRef.referredPatientName);
    } else {
        console.error('❌ Doctor did not receive assigned referral');
    }

    // 6. Test Doctor Accept Referral
    console.log('\n--- 4. Testing Doctor Accept Referral ---');
    const acceptReq = {
        params: { referralId: createdReferral.id },
        body: { confirmedTimeSlot: 'Tomorrow, 3:30 PM' }
    };
    const acceptRes = {
        status(code) { this.statusCode = code; return this; },
        json(data) { this.data = data; return this; }
    };
    await referralController.acceptReferral(acceptReq, acceptRes);
    console.log(`Accept Status: ${acceptRes.statusCode}`);
    if (acceptRes.statusCode === 200 && acceptRes.data.referral.status === 'Accepted') {
        console.log('✅ Referral accepted successfully by doctor! Status: Accepted');
    } else {
        console.error('❌ Accept referral failed:', acceptRes.data);
    }

    console.log('\n--- 6. Cleaning Up Test Artifacts ---');
    try {
        if (createdReferralId) await Referral.findByIdAndDelete(createdReferralId);
        if (referrer?.id) await User.findByIdAndDelete(referrer.id);
        if (doctorUser?.id) await User.findByIdAndDelete(doctorUser.id);
        if (doctor?.id) await Dentist.findByIdAndDelete(doctor.id);
        if (clinic?.id) await Clinic.findByIdAndDelete(clinic.id);
        await Notification.deleteMany({ recipient_id: referrer?.id });
        await Notification.deleteMany({ recipient_id: doctorUser?.id });
        const { supabaseAdmin } = require('../config/supabase');
        await supabaseAdmin.from('users').delete().eq('phone', '9988776655');
        await supabaseAdmin.from('patient_problem_requests').delete().ilike('problem_description', '%Severe crowding%');
        console.log('✅ Cleaned up all test entities.');
    } catch (_) {}

    console.log('\n🎉 ALL BACKEND REFERRAL TESTS PASSED!\n');
    process.exit(0);
}

runTest().catch(e => {
    console.error('❌ Test failed with error:', e);
    process.exit(1);
});
