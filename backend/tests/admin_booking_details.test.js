/**
 * GS HEALTH — Admin Dashboard Selected Doctor & Booking Details E2E Test (gs-health-test ONLY)
 * Verifies:
 * 1. Patient books an appointment with Doctor A (auto-persisting dentist_id & clinic_id).
 * 2. Even if another doctor (Doctor B) is later assigned on a problem request for the same patient,
 *    Admin GET /appointments strictly returns Doctor A (selectedDoctor), never Doctor B.
 * 3. Returns complete patient (name, mobile), selectedDoctor (name, photo, specialty), clinic,
 *    appointment date & time slot, booking created_at, and status.
 * 4. Preserves existing appointments and backend authorization.
 */
require('dotenv').config();
const assert = require('assert');
const crypto = require('crypto');

const supaUrl = (process.env.SUPABASE_URL || '').trim();
if (!supaUrl.includes('ojinzcdldwugpnxrnjcq') || supaUrl.includes('fommrwxpqzkcktweosgp')) {
    console.error('SAFETY ABORT: admin_booking_details.test.js may ONLY run against gs-health-test (ojinzcdldwugpnxrnjcq).');
    process.exit(1);
}

const { supabaseAdmin } = require('../src/config/supabase');
const appointmentController = require('../src/controllers/appointmentController');

function createMockRes() {
    const out = { statusCode: 200, body: null };
    const res = {
        status(code) {
            out.statusCode = code;
            return res;
        },
        json(payload) {
            out.body = payload;
            return res;
        }
    };
    return { res, out };
}

async function runTests() {
    let passed = 0;
    let failed = 0;
    const suffix = Date.now().toString().slice(-6);
    // 1x1 transparent PNG base64 fixture
    const samplePhotoB64 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';

    const ids = {
        docAUserId: null,
        docBUserId: null,
        patientUserId: null,
        clinicAId: null,
        clinicBId: null,
        dentistAId: null,
        dentistBId: null,
        appointmentId: null,
        requestId: null
    };

    async function testCase(name, fn) {
        try {
            await fn();
            console.log(`✓ ${name}`);
            passed++;
        } catch (err) {
            console.error(`✗ ${name}:`, err.message);
            failed++;
        }
    }

    try {
        // Seed Doctor A, Doctor B, Clinics A & B, and Patient in gs-health-test
        const { data: docAUser, error: e1 } = await supabaseAdmin.from('users').insert({
            name: `Aarav Selected ${suffix}`,
            email: `doca_${suffix}@gshealth-booking-test.local`,
            password: `Test_${crypto.randomBytes(8).toString('hex')}`,
            phone: `9111${suffix}`,
            role: 'Dentist',
            status: 'ACTIVE',
            city: 'Hyderabad',
            biometric_token: samplePhotoB64
        }).select().single();
        if (e1) throw e1;
        ids.docAUserId = docAUser.id;

        const { data: docBUser, error: e2 } = await supabaseAdmin.from('users').insert({
            name: `Vikram LaterAssigned ${suffix}`,
            email: `docb_${suffix}@gshealth-booking-test.local`,
            password: `Test_${crypto.randomBytes(8).toString('hex')}`,
            phone: `9222${suffix}`,
            role: 'Dentist',
            status: 'ACTIVE',
            city: 'Hyderabad'
        }).select().single();
        if (e2) throw e2;
        ids.docBUserId = docBUser.id;

        const { data: patUser, error: e3 } = await supabaseAdmin.from('users').insert({
            name: `Riya BookingPatient ${suffix}`,
            email: `pat_${suffix}@gshealth-booking-test.local`,
            password: `Test_${crypto.randomBytes(8).toString('hex')}`,
            phone: `9333${suffix}`,
            role: 'Patient',
            status: 'ACTIVE',
            city: 'Hyderabad'
        }).select().single();
        if (e3) throw e3;
        ids.patientUserId = patUser.id;

        const { data: clinicA, error: e4 } = await supabaseAdmin.from('clinics').insert({
            user_id: docAUser.id,
            clinic_name: `Apex Heart & Care ${suffix}`,
            location: 'Banjara Hills, Hyderabad',
            verified: true,
            services: ['Cardiology']
        }).select().single();
        if (e4) throw e4;
        ids.clinicAId = clinicA.id;

        const { data: clinicB, error: e5 } = await supabaseAdmin.from('clinics').insert({
            user_id: docBUser.id,
            clinic_name: `Other Ortho Clinic ${suffix}`,
            location: 'Madhapur, Hyderabad',
            verified: true,
            services: ['Orthopedics']
        }).select().single();
        if (e5) throw e5;
        ids.clinicBId = clinicB.id;

        const { data: dentA, error: e6 } = await supabaseAdmin.from('dentists').insert({
            user_id: docAUser.id,
            clinic_id: clinicA.id,
            speciality: 'Cardiology',
            license_number: `DOCA-LIC-${suffix}`,
            qualifications: 'MBBS, MD, DM (Cardiology)',
            availability_status: 'Available',
            verification_status: 'VERIFIED',
            city: 'Hyderabad'
        }).select().single();
        if (e6) throw e6;
        ids.dentistAId = dentA.id;

        const { data: dentB, error: e7 } = await supabaseAdmin.from('dentists').insert({
            user_id: docBUser.id,
            clinic_id: clinicB.id,
            speciality: 'Orthopedics',
            license_number: `DOCB-LIC-${suffix}`,
            qualifications: 'MBBS, MS (Ortho)',
            availability_status: 'Available',
            verification_status: 'VERIFIED',
            city: 'Hyderabad'
        }).select().single();
        if (e7) throw e7;
        ids.dentistBId = dentB.id;

        const apptDate = new Date(Date.now() + 3 * 24 * 60 * 60 * 1000).toISOString().split('T')[0];

        await testCase('1. Patient books appointment with Doctor A -> persists exact dentist_id and auto-resolves clinic_id', async () => {
            const call = createMockRes();
            await appointmentController.bookAppointment(
                {
                    user: { id: ids.patientUserId, role: 'Patient' },
                    body: {
                        dentistId: ids.dentistAId,
                        patientId: ids.patientUserId,
                        date: apptDate,
                        timeSlot: '10:30 AM',
                        treatment: 'Cardiac Evaluation'
                    }
                },
                call.res
            );
            assert.strictEqual(call.out.statusCode, 201, `Expected 201, got ${call.out.statusCode}: ${JSON.stringify(call.out.body)}`);
            const appt = call.out.body.appointment;
            ids.appointmentId = appt.id;
            assert.strictEqual(appt.dentist_id, ids.dentistAId);
            assert.strictEqual(appt.clinic_id, ids.clinicAId);
            assert.strictEqual(appt.time_slot, '10:30 AM');
        });

        await testCase('2. Separate problem request assigned to Doctor B does NOT alter the appointment selected doctor', async () => {
            const { data: reqRow, error: reqErr } = await supabaseAdmin.from('patient_problem_requests').insert({
                patient_id: ids.patientUserId,
                problem_category: 'Orthopedics',
                problem_description: 'Separate knee pain request',
                status: 'DENTIST_ASSIGNED',
                suggested_dentist_id: ids.dentistBId
            }).select().single();
            if (reqErr) throw reqErr;
            ids.requestId = reqRow.id;
        });

        await testCase('3. Admin GET /appointments returns Doctor A (photo, specialty, clinic), patient details, dates, and NOT Doctor B', async () => {
            const call = createMockRes();
            await appointmentController.getAppointments(
                { query: {}, user: { id: 'admin-test-caller', role: 'Admin' } },
                call.res
            );
            assert.strictEqual(call.out.statusCode, 200);
            const found = (call.out.body.appointments || []).find(a => a.id === ids.appointmentId);
            assert.ok(found, 'Booked appointment must be returned in Admin GET /appointments');

            assert.strictEqual(found.dentist_id, ids.dentistAId);
            assert.strictEqual(found.clinic_id, ids.clinicAId);
            assert.strictEqual(found.patient.name, `Riya BookingPatient ${suffix}`);
            assert.strictEqual(found.patient.phone, `9333${suffix}`);
            assert.strictEqual(found.selectedDoctor.name, `Dr. Aarav Selected ${suffix}`);
            assert.notStrictEqual(found.selectedDoctor.name, `Dr. Vikram LaterAssigned ${suffix}`);
            assert.strictEqual(found.selectedDoctor.specialty, 'Cardiology');
            assert.strictEqual(found.selectedDoctor.profilePhoto, samplePhotoB64);
            assert.strictEqual(found.clinic.clinic_name, `Apex Heart & Care ${suffix}`);
            assert.strictEqual(found.time_slot, '10:30 AM');
            assert.ok(String(found.date).startsWith(apptDate));
            assert.ok(found.booking_created_at && found.created_at, 'Booking created timestamp must be included');
            assert.strictEqual(found.status, 'PENDING');
        });

        await testCase('4. Unauthenticated GET /appointments without filters returns empty list (authorization preserved)', async () => {
            const call = createMockRes();
            await appointmentController.getAppointments({ query: {}, user: null }, call.res);
            assert.strictEqual(call.out.statusCode, 200);
            assert.deepStrictEqual(call.out.body.appointments, []);
        });
    } finally {
        const safeDel = async (fn) => { try { await fn(); } catch (_) {} };
        if (ids.requestId) await safeDel(() => supabaseAdmin.from('patient_problem_requests').delete().eq('id', ids.requestId));
        if (ids.appointmentId) {
            await safeDel(() => supabaseAdmin.from('patient_assignment_history').delete().eq('appointment_id', ids.appointmentId));
            await safeDel(() => supabaseAdmin.from('appointments').delete().eq('id', ids.appointmentId));
        }
        if (ids.dentistAId) {
            await safeDel(() => supabaseAdmin.from('notifications').delete().eq('recipient_id', ids.dentistAId));
            await safeDel(() => supabaseAdmin.from('dentists').delete().eq('id', ids.dentistAId));
        }
        if (ids.dentistBId) await safeDel(() => supabaseAdmin.from('dentists').delete().eq('id', ids.dentistBId));
        if (ids.clinicAId) await safeDel(() => supabaseAdmin.from('clinics').delete().eq('id', ids.clinicAId));
        if (ids.clinicBId) await safeDel(() => supabaseAdmin.from('clinics').delete().eq('id', ids.clinicBId));
        if (ids.patientUserId) await safeDel(() => supabaseAdmin.from('users').delete().eq('id', ids.patientUserId));
        if (ids.docAUserId) await safeDel(() => supabaseAdmin.from('users').delete().eq('id', ids.docAUserId));
        if (ids.docBUserId) await safeDel(() => supabaseAdmin.from('users').delete().eq('id', ids.docBUserId));
    }

    console.log('\n=================================================');
    console.log(`ADMIN BOOKING DETAILS RESULTS: ${passed} Passed, ${failed} Failed`);
    console.log('=================================================\n');
    if (failed > 0) process.exit(1);
}

runTests().catch(err => {
    console.error('Fatal test error:', err);
    process.exit(1);
});
