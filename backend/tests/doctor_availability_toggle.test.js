/**
 * GS HEALTH — End-to-End Doctor Availability ON/OFF Test Suite (against gs-health-test ONLY)
 * Verifies:
 * 1. Doctor ON  -> visible in patient search, profile accessible, bookings & records succeed.
 * 2. Doctor OFF -> persisted in Supabase, hidden from patient search/specialty/clinic listings.
 * 3. Doctor OFF -> direct profile access (GET /doctors/:id) returns 403 & exposes ZERO details to patients.
 * 4. Doctor OFF -> new bookings, direct consultation requests, referrals, and slots rejected by backend.
 * 5. Existing appointments & medical records remain 100% intact when Availability is OFF.
 * 6. Doctor ON again -> profile immediately visible again without re-registration; new bookings work.
 */
require('dotenv').config();
const assert = require('assert');
const crypto = require('crypto');

const supaUrl = (process.env.SUPABASE_URL || '').trim();
if (!supaUrl.includes('ojinzcdldwugpnxrnjcq') || supaUrl.includes('fommrwxpqzkcktweosgp')) {
    console.error('SAFETY ABORT: doctor_availability_toggle.test.js may ONLY run against gs-health-test (ojinzcdldwugpnxrnjcq).');
    process.exit(1);
}

const { supabaseAdmin } = require('../src/config/supabase');
const clinicController = require('../src/controllers/clinicController');
const appointmentController = require('../src/controllers/appointmentController');
const problemRequestController = require('../src/controllers/problemRequestController');
const referralController = require('../src/controllers/referralController');
const availabilityController = require('../src/controllers/availabilityController');

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
    const createdIds = {
        doctorUserId: null,
        patientUserId: null,
        clinicId: null,
        dentistId: null,
        appointmentIds: [],
        recordIds: []
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
        // Seed isolated test records in gs-health-test
        const { data: docUser, error: docUserErr } = await supabaseAdmin
            .from('users')
            .insert({
                name: `Dr. AvailTest ${suffix}`,
                email: `avail_doc_${suffix}@gshealth-test.local`,
                password: `Test_${crypto.randomBytes(8).toString('hex')}`,
                phone: `9777${suffix}`,
                role: 'Dentist',
                status: 'ACTIVE',
                city: 'Hyderabad',
                state: 'Telangana',
                pincode: '500032'
            })
            .select()
            .single();
        if (docUserErr) throw new Error(`Seed doctor user failed: ${docUserErr.message}`);
        createdIds.doctorUserId = docUser.id;

        const { data: patUser, error: patUserErr } = await supabaseAdmin
            .from('users')
            .insert({
                name: `Patient AvailTest ${suffix}`,
                email: `avail_pat_${suffix}@gshealth-test.local`,
                password: `Test_${crypto.randomBytes(8).toString('hex')}`,
                phone: `9666${suffix}`,
                role: 'Patient',
                status: 'ACTIVE',
                city: 'Hyderabad',
                state: 'Telangana',
                pincode: '500032'
            })
            .select()
            .single();
        if (patUserErr) throw new Error(`Seed patient user failed: ${patUserErr.message}`);
        createdIds.patientUserId = patUser.id;

        const { data: clinicRow, error: clinicErr } = await supabaseAdmin
            .from('clinics')
            .insert({
                user_id: docUser.id,
                clinic_name: `Avail Test Clinic ${suffix}`,
                location: 'Hyderabad - 500032',
                verified: true,
                services: ['Cardiology', 'General Consultation']
            })
            .select()
            .single();
        if (clinicErr) throw new Error(`Seed clinic failed: ${clinicErr.message}`);
        createdIds.clinicId = clinicRow.id;

        const { data: dentistRow, error: dentistErr } = await supabaseAdmin
            .from('dentists')
            .insert({
                user_id: docUser.id,
                clinic_id: clinicRow.id,
                speciality: 'Cardiology',
                license_number: `AVAIL-LIC-${suffix}`,
                experience_years: 9,
                qualifications: 'MBBS, MD, DM (Cardiology)',
                availability_status: 'Available',
                verification_status: 'VERIFIED',
                city: 'Hyderabad',
                state: 'Telangana',
                pincode: '500032'
            })
            .select()
            .single();
        if (dentistErr) throw new Error(`Seed dentist failed: ${dentistErr.message}`);
        createdIds.dentistId = dentistRow.id;

        const tomorrow = new Date(Date.now() + 2 * 24 * 60 * 60 * 1000).toISOString().split('T')[0];

        // 1. Doctor ON -> visible in patient search, profile accessible, booking & medical record succeed
        await testCase('1. Doctor ON -> visible in patient search, specialty search, profile, and booking succeeds', async () => {
            // Patient search
            const searchCall = createMockRes();
            await clinicController.getAllDentists(
                { query: { search: `AvailTest ${suffix}` }, user: { id: createdIds.patientUserId, role: 'Patient' } },
                searchCall.res
            );
            assert.strictEqual(searchCall.out.statusCode, 200);
            assert.ok(searchCall.out.body.doctors.some(d => d.id === createdIds.dentistId), 'Doctor ON must appear in patient search');

            // Direct profile access
            const profCall = createMockRes();
            await clinicController.getDoctorById(
                { params: { id: createdIds.dentistId }, user: { id: createdIds.patientUserId, role: 'Patient' } },
                profCall.res
            );
            assert.strictEqual(profCall.out.statusCode, 200);
            assert.strictEqual(profCall.out.body.isAvailable, true);
            assert.strictEqual(profCall.out.body.doctor.id, createdIds.dentistId);

            // Book initial appointment while ON
            const bookCall = createMockRes();
            await appointmentController.bookAppointment(
                {
                    user: { id: createdIds.patientUserId, role: 'Patient' },
                    body: {
                        dentistId: createdIds.dentistId,
                        clinicId: createdIds.clinicId,
                        patientId: createdIds.patientUserId,
                        date: tomorrow,
                        timeSlot: '10:00 AM',
                        treatment: 'Cardiac Checkup'
                    }
                },
                bookCall.res
            );
            assert.strictEqual(bookCall.out.statusCode, 201, `Expected 201, got ${bookCall.out.statusCode}: ${JSON.stringify(bookCall.out.body)}`);
            const apptId = bookCall.out.body.appointment.id;
            createdIds.appointmentIds.push(apptId);

            // Create an existing medical record linked to this doctor & patient
            const { data: rec, error: recErr } = await supabaseAdmin
                .from('medical_records')
                .insert({
                    patient_id: createdIds.patientUserId,
                    dentist_id: createdIds.dentistId,
                    appointment_id: apptId,
                    diagnosis: 'Baseline ECG Normal',
                    treatment: 'Routine follow-up'
                })
                .select()
                .single();
            if (recErr) throw new Error(`Medical record seed failed: ${recErr.message}`);
            createdIds.recordIds.push(rec.id);
        });

        // 2. Toggle OFF persists in Supabase & rejects unauthorized patient attempts
        await testCase('2. Doctor toggles Availability OFF -> persisted in Supabase; Patient role rejected with 403', async () => {
            const patAttempt = createMockRes();
            await clinicController.updateDoctorAvailability(
                {
                    params: { id: createdIds.dentistId },
                    user: { id: createdIds.patientUserId, role: 'Patient' },
                    body: { isAvailable: false }
                },
                patAttempt.res
            );
            assert.strictEqual(patAttempt.out.statusCode, 403);

            const docToggleOff = createMockRes();
            await clinicController.updateDoctorAvailability(
                {
                    params: { id: createdIds.dentistId },
                    user: { id: createdIds.doctorUserId, role: 'Dentist' },
                    body: { isAvailable: false }
                },
                docToggleOff.res
            );
            assert.strictEqual(docToggleOff.out.statusCode, 200);
            assert.strictEqual(docToggleOff.out.body.isAvailable, false);
            assert.strictEqual(docToggleOff.out.body.availability_status, 'Unavailable');

            // Confirm persistence directly in Supabase dentists table
            const { data: dbRow } = await supabaseAdmin
                .from('dentists')
                .select('availability_status, speciality, qualifications, license_number')
                .eq('id', createdIds.dentistId)
                .single();
            assert.strictEqual(dbRow.availability_status, 'Unavailable');
            assert.strictEqual(dbRow.speciality, 'Cardiology', 'Doctor profile fields must NOT be deleted');
            assert.strictEqual(dbRow.license_number, `AVAIL-LIC-${suffix}`);
        });

        // 3. Doctor OFF -> hidden from default patient search, specialty search & clinic listing, but returned when includeUnavailable=true
        await testCase('3. Doctor OFF -> hidden from default search/specialty/clinic; visible with Unavailable status when includeUnavailable=true', async () => {
            const defaultPatientSearch = createMockRes();
            await clinicController.getAllDentists(
                {
                    query: { search: `AvailTest ${suffix}` },
                    user: { id: createdIds.patientUserId, role: 'Patient' }
                },
                defaultPatientSearch.res
            );
            assert.strictEqual(defaultPatientSearch.out.statusCode, 200);
            assert.strictEqual(
                defaultPatientSearch.out.body.doctors.some(d => d.id === createdIds.dentistId || d.user_id === createdIds.doctorUserId),
                false,
                'OFF doctor must NOT appear in default patient search (without includeUnavailable=true)'
            );

            const patientSearch = createMockRes();
            await clinicController.getAllDentists(
                {
                    query: { search: `AvailTest ${suffix}`, includeUnavailable: 'true' },
                    user: { id: createdIds.patientUserId, role: 'Patient' }
                },
                patientSearch.res
            );
            assert.strictEqual(patientSearch.out.statusCode, 200);
            const matchedOff = patientSearch.out.body.doctors.find(d => d.id === createdIds.dentistId || d.user_id === createdIds.doctorUserId);
            assert.ok(matchedOff, 'Registered doctor must appear in directory listing when includeUnavailable=true');
            assert.strictEqual(matchedOff.isAvailable, false);
            assert.strictEqual(matchedOff.availability_status, 'Unavailable');

            const specSearch = createMockRes();
            await clinicController.getAllDentists(
                { query: { specialty: 'Cardiology' }, user: null },
                specSearch.res
            );
            assert.strictEqual(
                specSearch.out.body.doctors.some(d => d.id === createdIds.dentistId),
                false,
                'OFF doctor must NOT appear in specialty search'
            );

            const clinicDocs = createMockRes();
            await clinicController.getClinicDentists(
                { params: { clinicId: createdIds.clinicId }, query: {}, user: { id: createdIds.patientUserId, role: 'Patient' } },
                clinicDocs.res
            );
            assert.strictEqual(
                clinicDocs.out.body.dentists.some(d => d.id === createdIds.dentistId),
                false,
                'OFF doctor must NOT appear in patient-facing clinic doctor list'
            );
        });

        // 4. Doctor OFF -> direct profile access does not expose details to patients
        await testCase('4. Doctor OFF -> direct profile access returns 403 and exposes ZERO details to patients', async () => {
            const patDirect = createMockRes();
            await clinicController.getDoctorById(
                { params: { id: createdIds.dentistId }, user: { id: createdIds.patientUserId, role: 'Patient' } },
                patDirect.res
            );
            assert.strictEqual(patDirect.out.statusCode, 403);
            assert.strictEqual(patDirect.out.body.success, false);
            assert.strictEqual(patDirect.out.body.unavailable, true);
            assert.strictEqual(patDirect.out.body.doctor, undefined, 'Doctor details must NOT be exposed when OFF');
            assert.ok(String(patDirect.out.body.message).toLowerCase().includes('unavailable'));

            // Unauthenticated bookmark check
            const anonDirect = createMockRes();
            await clinicController.getDoctorById({ params: { id: createdIds.dentistId }, user: null }, anonDirect.res);
            assert.strictEqual(anonDirect.out.statusCode, 403);
            assert.strictEqual(anonDirect.out.body.doctor, undefined);

            // Doctor self & Admin can still view profile
            const selfDirect = createMockRes();
            await clinicController.getDoctorById(
                { params: { id: createdIds.dentistId }, user: { id: createdIds.doctorUserId, role: 'Dentist' } },
                selfDirect.res
            );
            assert.strictEqual(selfDirect.out.statusCode, 200);
            assert.strictEqual(selfDirect.out.body.isAvailable, false);
        });

        // 5. Doctor OFF -> new booking, direct consultation request, referral, and slots rejected by backend
        await testCase('5. Doctor OFF -> new appointment booking, direct request, referral, and slots are rejected by backend', async () => {
            // Direct booking attempt
            const bookBlocked = createMockRes();
            await appointmentController.bookAppointment(
                {
                    user: { id: createdIds.patientUserId, role: 'Patient' },
                    body: {
                        dentistId: createdIds.dentistId,
                        clinicId: createdIds.clinicId,
                        patientId: createdIds.patientUserId,
                        date: tomorrow,
                        timeSlot: '11:00 AM',
                        treatment: 'New Booking Attempt While OFF'
                    }
                },
                bookBlocked.res
            );
            assert.strictEqual(bookBlocked.out.statusCode, 409);
            assert.strictEqual(bookBlocked.out.body.unavailable, true);

            // Direct consultation request attempt
            const reqBlocked = createMockRes();
            await problemRequestController.createProblemRequest(
                {
                    user: { id: createdIds.patientUserId, role: 'Patient' },
                    body: {
                        patientId: createdIds.patientUserId,
                        preferredDoctorId: createdIds.dentistId,
                        problemCategory: 'Cardiology',
                        problemDescription: 'Chest check'
                    }
                },
                reqBlocked.res
            );
            assert.strictEqual(reqBlocked.out.statusCode, 409);
            assert.strictEqual(reqBlocked.out.body.unavailable, true);

            // Referral attempt
            const refBlocked = createMockRes();
            await referralController.createReferral(
                {
                    user: { id: createdIds.patientUserId, role: 'Patient' },
                    body: {
                        referredPatientName: 'Friend Test',
                        referredPatientMobile: '9555512345',
                        referredPatientAge: '30',
                        referredPatientGender: 'Male',
                        referredPatientCity: 'Hyderabad',
                        referredPatientPincode: '500032',
                        referredPatientLocation: 'Gachibowli',
                        requiredSpecialist: 'Cardiology',
                        clinicalComplaint: 'Palpitations',
                        doctorId: createdIds.dentistId
                    }
                },
                refBlocked.res
            );
            assert.strictEqual(refBlocked.out.statusCode, 409);
            assert.strictEqual(refBlocked.out.body.unavailable, true);

            // Slots query for patient returns empty & blocked
            const slotsBlocked = createMockRes();
            await availabilityController.getDoctorAvailability(
                { query: { dentistId: createdIds.dentistId, date: tomorrow }, user: { id: createdIds.patientUserId, role: 'Patient' } },
                slotsBlocked.res
            );
            assert.strictEqual(slotsBlocked.out.statusCode, 200);
            assert.strictEqual(slotsBlocked.out.body.doctorAvailable, false);
            assert.deepStrictEqual(slotsBlocked.out.body.availability.availableSlots, []);
        });

        // 6. Existing appointments and medical records remain 100% intact
        await testCase('6. Existing appointments and medical records remain intact while doctor is OFF', async () => {
            const { data: appts } = await supabaseAdmin
                .from('appointments')
                .select('id, status, treatment')
                .eq('id', createdIds.appointmentIds[0]);
            assert.strictEqual(appts.length, 1);
            assert.strictEqual(appts[0].treatment, 'Cardiac Checkup');

            const { data: recs } = await supabaseAdmin
                .from('medical_records')
                .select('id, diagnosis')
                .eq('id', createdIds.recordIds[0]);
            assert.strictEqual(recs.length, 1);
            assert.strictEqual(recs[0].diagnosis, 'Baseline ECG Normal');
        });

        // 7. Doctor ON again -> profile immediately visible without re-registration; new bookings work
        await testCase('7. Doctor ON again -> profile visible in patient search/profile and new bookings succeed', async () => {
            const docToggleOn = createMockRes();
            await clinicController.updateDoctorAvailability(
                {
                    params: { id: createdIds.dentistId },
                    user: { id: createdIds.doctorUserId, role: 'Dentist' },
                    body: { isAvailable: true }
                },
                docToggleOn.res
            );
            assert.strictEqual(docToggleOn.out.statusCode, 200);
            assert.strictEqual(docToggleOn.out.body.isAvailable, true);
            assert.strictEqual(docToggleOn.out.body.availability_status, 'Available');

            // Visible again in patient search
            const searchAgain = createMockRes();
            await clinicController.getAllDentists(
                { query: { search: `AvailTest ${suffix}` }, user: { id: createdIds.patientUserId, role: 'Patient' } },
                searchAgain.res
            );
            assert.ok(searchAgain.out.body.doctors.some(d => d.id === createdIds.dentistId));

            // Profile accessible again
            const profAgain = createMockRes();
            await clinicController.getDoctorById(
                { params: { id: createdIds.dentistId }, user: { id: createdIds.patientUserId, role: 'Patient' } },
                profAgain.res
            );
            assert.strictEqual(profAgain.out.statusCode, 200);
            assert.strictEqual(profAgain.out.body.doctor.id, createdIds.dentistId);

            // Concurrent booking race: two simultaneous bookings for same slot -> strictly 1 succeeds (201), 1 conflicts (409)
            const c1 = createMockRes();
            const c2 = createMockRes();
            await Promise.all([
                appointmentController.bookAppointment(
                    {
                        user: { id: createdIds.patientUserId, role: 'Patient' },
                        body: {
                            dentistId: createdIds.dentistId,
                            clinicId: createdIds.clinicId,
                            patientId: createdIds.patientUserId,
                            date: tomorrow,
                            timeSlot: '02:00 PM',
                            treatment: 'Follow-up After Re-enable'
                        }
                    },
                    c1.res
                ),
                appointmentController.bookAppointment(
                    {
                        user: { id: createdIds.patientUserId, role: 'Patient' },
                        body: {
                            dentistId: createdIds.dentistId,
                            clinicId: createdIds.clinicId,
                            patientId: createdIds.patientUserId,
                            date: tomorrow,
                            timeSlot: '02:00 PM',
                            treatment: 'Duplicate Concurrent Booking'
                        }
                    },
                    c2.res
                )
            ]);
            const statuses = [c1.out.statusCode, c2.out.statusCode].sort();
            assert.deepStrictEqual(statuses, [201, 409], `Expected [201, 409] for concurrent same-slot bookings, got ${JSON.stringify(statuses)}`);
            const winner = c1.out.statusCode === 201 ? c1.out.body : c2.out.body;
            if (winner?.appointment?.id) createdIds.appointmentIds.push(winner.appointment.id);
        });
    } finally {
        // Clean up temporary test rows in gs-health-test
        const safeDel = async (fn) => { try { await fn(); } catch (_) {} };
        for (const rId of createdIds.recordIds) {
            await safeDel(() => supabaseAdmin.from('medical_records').delete().eq('id', rId));
        }
        for (const aId of createdIds.appointmentIds) {
            await safeDel(() => supabaseAdmin.from('patient_assignment_history').delete().eq('appointment_id', aId));
            await safeDel(() => supabaseAdmin.from('appointments').delete().eq('id', aId));
        }
        if (createdIds.dentistId) {
            await safeDel(() => supabaseAdmin.from('notifications').delete().eq('recipient_id', createdIds.dentistId));
            await safeDel(() => supabaseAdmin.from('dentists').delete().eq('id', createdIds.dentistId));
        }
        if (createdIds.clinicId) {
            await safeDel(() => supabaseAdmin.from('clinics').delete().eq('id', createdIds.clinicId));
        }
        if (createdIds.patientUserId) {
            await safeDel(() => supabaseAdmin.from('users').delete().eq('id', createdIds.patientUserId));
        }
        if (createdIds.doctorUserId) {
            await safeDel(() => supabaseAdmin.from('users').delete().eq('id', createdIds.doctorUserId));
        }
    }

    console.log('\n=================================================');
    console.log(`DOCTOR AVAILABILITY RESULTS: ${passed} Passed, ${failed} Failed`);
    console.log('=================================================\n');
    if (failed > 0) process.exit(1);
}

runTests().catch(err => {
    console.error('Fatal test error:', err);
    process.exit(1);
});
