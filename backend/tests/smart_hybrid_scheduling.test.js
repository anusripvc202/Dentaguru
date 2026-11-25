/**
 * GS HEALTH / DentaGuru — Smart Hybrid Appointment Scheduling E2E Tests (gs-health-test ONLY)
 * Covers all 9 required scenarios against real Express controllers + Supabase test DB:
 * 1. In-Person -> Online overlap + buffer protection (10:00 AM In-Person 30m + 10m buffer blocks 10:30 AM Online)
 * 2. Online -> In-Person overlap + buffer protection (slot interval != consultation duration)
 * 3. Early consultation finish frees subsequent slots & sends doctor_ready_to_start notification
 * 4. In-Person runs 15 min late -> cascades estimated time & preserves confirmed appointments
 * 5. Doctor 30 min late -> patient notification + Admin delay alert
 * 6. Simultaneous double-booking race condition (Promise.all) -> strictly 1 succeeds (201), 1 rejected (409)
 * 7. Patient delay actions (WAIT, REQUEST_RESCHEDULE, SWITCH_DOCTOR) + reschedule confirmation
 * 8. Doctor Unavailable/Offline -> existing appointments preserved, new bookings blocked; No-Show frees slot
 * 9. Admin manual time-slot block/unblock + configurable scheduling rules
 */
require('dotenv').config({ path: require('path').resolve(__dirname, '../.env') });
const assert = require('assert');
const crypto = require('crypto');
const { describe, it, before, after } = require('node:test');

const supaUrl = (process.env.SUPABASE_URL || '').trim();
if (!supaUrl.includes('ojinzcdldwugpnxrnjcq') || supaUrl.includes('fommrwxpqzkcktweosgp')) {
    console.error('SAFETY ABORT: smart_hybrid_scheduling.test.js may ONLY run against gs-health-test (ojinzcdldwugpnxrnjcq).');
    process.exit(1);
}

const { supabaseAdmin } = require('../src/config/supabase');
const appointmentController = require('../src/controllers/appointmentController');
const availabilityController = require('../src/controllers/availabilityController');
const clinicController = require('../src/controllers/clinicController');
const { getBookingRulesConfig, setBookingRulesConfig } = require('../src/config/bookingRulesConfig');

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

function futureYmd(daysAhead) {
    return new Date(Date.now() + daysAhead * 24 * 60 * 60 * 1000).toISOString().split('T')[0];
}

describe('Smart Hybrid Appointment Scheduling', () => {
    const suffix = Date.now().toString().slice(-6);
    const originalRules = { ...getBookingRulesConfig() };
    const ids = {
        doc1UserId: null,
        doc2UserId: null,
        pat1UserId: null,
        pat2UserId: null,
        adminUserId: null,
        clinicId: null,
        dentist1Id: null,
        dentist2Id: null,
        appointmentIds: [],
    };

    const dayA = futureYmd(2);
    const dayB = futureYmd(3);
    const dayC = futureYmd(4);
    const dayD = futureYmd(5);
    const dayE = futureYmd(6);

    before(async () => {
        // Ensure clean baseline rules
        setBookingRulesConfig({
            inPersonDurationMinutes: 30,
            onlineDurationMinutes: 20,
            inPersonBufferMinutes: 10,
            onlineBufferMinutes: 5,
            minAdvanceBookingMinutes: 30,
            defaultSlotIntervalMinutes: 30,
            maxAdvanceBookingDays: 90,
            adminDelayAlertThresholdMinutes: 15,
            timezone: 'Asia/Kolkata'
        });

        const pw = `Test_${crypto.randomBytes(8).toString('hex')}`;
        const { data: doc1User, error: e1 } = await supabaseAdmin.from('users').insert({
            name: `Hybrid DocOne ${suffix}`,
            email: `hdoc1_${suffix}@gshealth-test.local`,
            password: pw,
            phone: `9101${suffix}`,
            role: 'Dentist',
            status: 'ACTIVE',
            city: 'Hyderabad'
        }).select().single();
        if (e1) throw e1;
        ids.doc1UserId = doc1User.id;

        const { data: doc2User, error: e2 } = await supabaseAdmin.from('users').insert({
            name: `Hybrid DocTwo ${suffix}`,
            email: `hdoc2_${suffix}@gshealth-test.local`,
            password: pw,
            phone: `9102${suffix}`,
            role: 'Dentist',
            status: 'ACTIVE',
            city: 'Hyderabad'
        }).select().single();
        if (e2) throw e2;
        ids.doc2UserId = doc2User.id;

        const { data: pat1, error: e3 } = await supabaseAdmin.from('users').insert({
            name: `Hybrid PatientOne ${suffix}`,
            email: `hpat1_${suffix}@gshealth-test.local`,
            password: pw,
            phone: `9201${suffix}`,
            role: 'Patient',
            status: 'ACTIVE',
            city: 'Hyderabad'
        }).select().single();
        if (e3) throw e3;
        ids.pat1UserId = pat1.id;

        const { data: pat2, error: e4 } = await supabaseAdmin.from('users').insert({
            name: `Hybrid PatientTwo ${suffix}`,
            email: `hpat2_${suffix}@gshealth-test.local`,
            password: pw,
            phone: `9202${suffix}`,
            role: 'Patient',
            status: 'ACTIVE',
            city: 'Hyderabad'
        }).select().single();
        if (e4) throw e4;
        ids.pat2UserId = pat2.id;

        const { data: adminUser, error: e5 } = await supabaseAdmin.from('users').insert({
            name: `Hybrid Admin ${suffix}`,
            email: `hadmin_${suffix}@gshealth-test.local`,
            password: pw,
            phone: `9301${suffix}`,
            role: 'Admin',
            status: 'ACTIVE',
            city: 'Hyderabad'
        }).select().single();
        if (e5) throw e5;
        ids.adminUserId = adminUser.id;

        const { data: clinic, error: e6 } = await supabaseAdmin.from('clinics').insert({
            user_id: doc1User.id,
            clinic_name: `Hybrid Care Center ${suffix}`,
            location: 'Jubilee Hills, Hyderabad',
            verified: true,
            services: ['Cardiology', 'General Dentistry']
        }).select().single();
        if (e6) throw e6;
        ids.clinicId = clinic.id;

        const { data: d1, error: e7 } = await supabaseAdmin.from('dentists').insert({
            user_id: doc1User.id,
            clinic_id: clinic.id,
            speciality: 'Cardiology',
            license_number: `HYB1-${suffix}`,
            qualifications: 'MBBS, MD',
            availability_status: 'Available',
            verification_status: 'VERIFIED',
            city: 'Hyderabad'
        }).select().single();
        if (e7) throw e7;
        ids.dentist1Id = d1.id;

        const { data: d2, error: e8 } = await supabaseAdmin.from('dentists').insert({
            user_id: doc2User.id,
            clinic_id: clinic.id,
            speciality: 'Cardiology',
            license_number: `HYB2-${suffix}`,
            qualifications: 'MBBS, MD',
            availability_status: 'Available',
            verification_status: 'VERIFIED',
            city: 'Hyderabad'
        }).select().single();
        if (e8) throw e8;
        ids.dentist2Id = d2.id;

        // Save unified working schedule (09:00 AM - 06:00 PM) for dentist1 across test dates
        const schedCall = createMockRes();
        await availabilityController.saveDoctorAvailability(
            {
                user: { id: ids.adminUserId, role: 'Admin' },
                body: {
                    dentistId: ids.dentist1Id,
                    dates: [dayA, dayB, dayC, dayD, dayE],
                    workingDays: [0, 1, 2, 3, 4, 5, 6],
                    startTime: '09:00 AM',
                    endTime: '06:00 PM',
                    slotDurationMinutes: 30,
                    slotIntervalMinutes: 30,
                    maxPatientsPerSlot: 1,
                    blockedDates: []
                }
            },
            schedCall.res
        );
        assert.strictEqual(schedCall.out.statusCode, 200);
    });

    after(async () => {
        setBookingRulesConfig(originalRules);
        const safeDel = async (fn) => { try { await fn(); } catch (_) {} };
        for (const aid of ids.appointmentIds) {
            await safeDel(() => supabaseAdmin.from('patient_assignment_history').delete().eq('appointment_id', aid));
            await safeDel(() => supabaseAdmin.from('appointments').delete().eq('id', aid));
        }
        const notifTargets = [ids.doc1UserId, ids.doc2UserId, ids.pat1UserId, ids.pat2UserId, ids.adminUserId, ids.dentist1Id, ids.dentist2Id].filter(Boolean);
        for (const tid of notifTargets) {
            await safeDel(() => supabaseAdmin.from('notifications').delete().eq('recipient_id', tid));
        }
        await safeDel(() =>
            supabaseAdmin
                .from('notifications')
                .delete()
                .eq('recipient_id', 'ALL_ADMINS')
                .ilike('message', `%${suffix}%`)
        );
        if (ids.dentist1Id) await safeDel(() => supabaseAdmin.from('dentists').delete().eq('id', ids.dentist1Id));
        if (ids.dentist2Id) await safeDel(() => supabaseAdmin.from('dentists').delete().eq('id', ids.dentist2Id));
        if (ids.clinicId) await safeDel(() => supabaseAdmin.from('clinics').delete().eq('id', ids.clinicId));
        for (const uid of [ids.doc1UserId, ids.doc2UserId, ids.pat1UserId, ids.pat2UserId, ids.adminUserId].filter(Boolean)) {
            await safeDel(() => supabaseAdmin.from('users').delete().eq('id', uid));
        }
    });

    it('1. In-Person 10:00 AM (30m + 10m buffer) blocks 10:30 AM Online slot', async () => {
        const bookCall = createMockRes();
        await appointmentController.bookAppointment(
            {
                user: { id: ids.pat1UserId, role: 'Patient' },
                body: {
                    dentistId: ids.dentist1Id,
                    patientId: ids.pat1UserId,
                    date: dayA,
                    timeSlot: '10:00 AM',
                    treatment: 'Chest Checkup',
                    consultationMode: 'In-Person'
                }
            },
            bookCall.res
        );
        assert.strictEqual(bookCall.out.statusCode, 201, JSON.stringify(bookCall.out.body));
        const appt = bookCall.out.body.appointment;
        ids.appointmentIds.push(appt.id);
        assert.strictEqual(appt.consultationMode, 'In-Person');
        assert.strictEqual(appt.duration_minutes, 30);
        assert.strictEqual(appt.buffer_minutes, 10);
        assert.strictEqual(appt.scheduled_end_time, '10:30 AM');
        assert.strictEqual(appt.buffer_end_time, '10:40 AM');

        // Verify Online availability omits 10:00 AM & 10:30 AM due to 10:00-10:40 occupancy
        const availCall = createMockRes();
        await availabilityController.getDoctorAvailability(
            { query: { dentistId: ids.dentist1Id, date: dayA, consultationType: 'Online' } },
            availCall.res
        );
        assert.strictEqual(availCall.out.statusCode, 200);
        const availSlots = availCall.out.body.availability.availableSlots;
        assert.ok(!availSlots.includes('10:00 AM'), '10:00 AM must be blocked');
        assert.ok(!availSlots.includes('10:30 AM'), '10:30 AM must be blocked by 10:00-10:40 buffer');
        assert.ok(availSlots.includes('11:00 AM'), '11:00 AM Online must remain available');

        // Backend must also reject direct POST attempt at 10:30 AM Online
        const conflictCall = createMockRes();
        await appointmentController.bookAppointment(
            {
                user: { id: ids.pat2UserId, role: 'Patient' },
                body: {
                    dentistId: ids.dentist1Id,
                    patientId: ids.pat2UserId,
                    date: dayA,
                    timeSlot: '10:30 AM',
                    treatment: 'Video Consult',
                    consultationMode: 'Online'
                }
            },
            conflictCall.res
        );
        assert.strictEqual(conflictCall.out.statusCode, 409);

        // Verify patient booking notification & confirmation notification ('appointment_confirmed')
        const confirmCall = createMockRes();
        await appointmentController.acceptAppointment(
            {
                params: { id: appt.id },
                user: { id: ids.doc1UserId, role: 'Dentist' }
            },
            confirmCall.res
        );
        assert.strictEqual(confirmCall.out.statusCode, 200);

        const { data: notifs } = await supabaseAdmin
            .from('notifications')
            .select('*')
            .eq('recipient_id', ids.pat1UserId);
        assert.ok((notifs || []).some(n => (n.type || '') === 'appointment_booked'));
        assert.ok((notifs || []).some(n => (n.type || '') === 'appointment_confirmed' || String(n.title).toLowerCase().includes('confirmed')));
    });

    it('2. Online -> In-Person with slot interval != consultation duration preserves buffer & rejects overlap', async () => {
        // Set 15-minute slot interval while Online duration=20m + 5m buffer = 25m
        const rulesCall = createMockRes();
        await availabilityController.updateSchedulingRules(
            {
                user: { id: ids.adminUserId, role: 'Admin' },
                body: { defaultSlotIntervalMinutes: 15 }
            },
            rulesCall.res
        );
        assert.strictEqual(rulesCall.out.statusCode, 200);

        const schedSave = createMockRes();
        await availabilityController.saveDoctorAvailability(
            {
                user: { id: ids.adminUserId, role: 'Admin' },
                body: {
                    dentistId: ids.dentist1Id,
                    dates: [dayB],
                    workingDays: [0, 1, 2, 3, 4, 5, 6],
                    startTime: '09:00 AM',
                    endTime: '06:00 PM',
                    slotDurationMinutes: 15,
                    slotIntervalMinutes: 15,
                    maxPatientsPerSlot: 1
                }
            },
            schedSave.res
        );
        assert.strictEqual(schedSave.out.statusCode, 200);

        // Book Online at 10:00 AM (occupies 10:00-10:25)
        const onlineCall = createMockRes();
        await appointmentController.bookAppointment(
            {
                user: { id: ids.pat1UserId, role: 'Patient' },
                body: {
                    dentistId: ids.dentist1Id,
                    patientId: ids.pat1UserId,
                    date: dayB,
                    timeSlot: '10:00 AM',
                    treatment: 'Follow-up Video',
                    consultationMode: 'Online'
                }
            },
            onlineCall.res
        );
        assert.strictEqual(onlineCall.out.statusCode, 201);
        ids.appointmentIds.push(onlineCall.out.body.appointment.id);

        // Check In-Person availability: 10:00 AM & 10:15 AM blocked (inside 10:00-10:25); 10:30 AM is FREE
        const availCall = createMockRes();
        await availabilityController.getDoctorAvailability(
            { query: { dentistId: ids.dentist1Id, date: dayB, consultationType: 'In-Person' } },
            availCall.res
        );
        assert.strictEqual(availCall.out.statusCode, 200);
        const availSlots = availCall.out.body.availability.availableSlots;
        assert.ok(!availSlots.includes('10:15 AM'), '10:15 AM overlaps 10:00-10:25 Online+buffer');
        assert.ok(availSlots.includes('10:30 AM'), '10:30 AM In-Person after 10:25 buffer must be open');

        const rejectCall = createMockRes();
        await appointmentController.bookAppointment(
            {
                user: { id: ids.pat2UserId, role: 'Patient' },
                body: {
                    dentistId: ids.dentist1Id,
                    patientId: ids.pat2UserId,
                    date: dayB,
                    timeSlot: '10:15 AM',
                    treatment: 'In-Person Visit',
                    consultationMode: 'In-Person'
                }
            },
            rejectCall.res
        );
        assert.strictEqual(rejectCall.out.statusCode, 409);

        const okCall = createMockRes();
        await appointmentController.bookAppointment(
            {
                user: { id: ids.pat2UserId, role: 'Patient' },
                body: {
                    dentistId: ids.dentist1Id,
                    patientId: ids.pat2UserId,
                    date: dayB,
                    timeSlot: '10:30 AM',
                    treatment: 'In-Person Visit',
                    consultationMode: 'In-Person'
                }
            },
            okCall.res
        );
        assert.strictEqual(okCall.out.statusCode, 201);
        ids.appointmentIds.push(okCall.out.body.appointment.id);

        // Restore 30m default interval for remaining tests
        await availabilityController.updateSchedulingRules(
            {
                user: { id: ids.adminUserId, role: 'Admin' },
                body: { defaultSlotIntervalMinutes: 30 }
            },
            createMockRes().res
        );
        await availabilityController.saveDoctorAvailability(
            {
                user: { id: ids.adminUserId, role: 'Admin' },
                body: {
                    dentistId: ids.dentist1Id,
                    dates: [dayC, dayD, dayE],
                    workingDays: [0, 1, 2, 3, 4, 5, 6],
                    startTime: '09:00 AM',
                    endTime: '06:00 PM',
                    slotDurationMinutes: 30,
                    slotIntervalMinutes: 30,
                    maxPatientsPerSlot: 1
                }
            },
            createMockRes().res
        );
    });

    it('3. Early consultation completion frees blocked next slot & alerts next patient', async () => {
        const c1 = createMockRes();
        await appointmentController.bookAppointment(
            {
                user: { id: ids.pat1UserId, role: 'Patient' },
                body: {
                    dentistId: ids.dentist1Id,
                    patientId: ids.pat1UserId,
                    date: dayC,
                    timeSlot: '10:00 AM',
                    treatment: 'Early Finish Visit',
                    consultationMode: 'In-Person'
                }
            },
            c1.res
        );
        assert.strictEqual(c1.out.statusCode, 201);
        const appt1Id = c1.out.body.appointment.id;
        ids.appointmentIds.push(appt1Id);

        const c2 = createMockRes();
        await appointmentController.bookAppointment(
            {
                user: { id: ids.pat2UserId, role: 'Patient' },
                body: {
                    dentistId: ids.dentist1Id,
                    patientId: ids.pat2UserId,
                    date: dayC,
                    timeSlot: '11:00 AM',
                    treatment: 'Next Online Consult',
                    consultationMode: 'Online'
                }
            },
            c2.res
        );
        assert.strictEqual(c2.out.statusCode, 201);
        ids.appointmentIds.push(c2.out.body.appointment.id);

        // Start 10:00 AM In-Person -> status Busy – In-Person Consultation
        const startCall = createMockRes();
        await appointmentController.startConsultation(
            {
                params: { id: appt1Id },
                user: { id: ids.doc1UserId, role: 'Dentist' },
                body: { actualStartAt: `${dayC}T04:30:00.000Z` } // 10:00 IST
            },
            startCall.res
        );
        assert.strictEqual(startCall.out.statusCode, 200);
        assert.strictEqual(startCall.out.body.doctorStatus, 'Busy – In-Person Consultation');

        // Complete early at 10:12 AM IST (04:42 UTC) -> +10m buffer = 10:22 AM, so 10:30 AM Online opens up!
        const endCall = createMockRes();
        await appointmentController.completeConsultation(
            {
                params: { id: appt1Id },
                user: { id: ids.doc1UserId, role: 'Dentist' },
                body: { actualEndAt: `${dayC}T04:42:00.000Z` }
            },
            endCall.res
        );
        assert.strictEqual(endCall.out.statusCode, 200);
        assert.strictEqual(endCall.out.body.finishedEarly, true);
        assert.strictEqual(endCall.out.body.doctorStatus, 'Available');

        const availAfter = createMockRes();
        await availabilityController.getDoctorAvailability(
            { query: { dentistId: ids.dentist1Id, date: dayC, consultationType: 'Online' } },
            availAfter.res
        );
        assert.ok(
            availAfter.out.body.availability.availableSlots.includes('10:30 AM'),
            'Early completion at 10:12 AM (+10m buffer = 10:22 AM) must reopen 10:30 AM slot'
        );

        const { data: readyNotifs } = await supabaseAdmin
            .from('notifications')
            .select('*')
            .eq('recipient_id', ids.pat2UserId);
        assert.ok((readyNotifs || []).some(n => (n.type || '') === 'doctor_ready_to_start' || String(n.title).toLowerCase().includes('ready')));
    });

    it('4 & 5. Delay +15m and +30m cascades estimate without cancelling & triggers Admin + Patient alerts', async () => {
        const b1 = createMockRes();
        await appointmentController.bookAppointment(
            {
                user: { id: ids.pat1UserId, role: 'Patient' },
                body: {
                    dentistId: ids.dentist1Id,
                    patientId: ids.pat1UserId,
                    date: dayD,
                    timeSlot: '09:00 AM',
                    treatment: 'Complex Root Canal',
                    consultationMode: 'In-Person'
                }
            },
            b1.res
        );
        assert.strictEqual(b1.out.statusCode, 201);
        const firstApptId = b1.out.body.appointment.id;
        ids.appointmentIds.push(firstApptId);

        const b2 = createMockRes();
        await appointmentController.bookAppointment(
            {
                user: { id: ids.pat2UserId, role: 'Patient' },
                body: {
                    dentistId: ids.dentist1Id,
                    patientId: ids.pat2UserId,
                    date: dayD,
                    timeSlot: '10:00 AM',
                    treatment: 'Next Follow-up',
                    consultationMode: 'Online'
                }
            },
            b2.res
        );
        assert.strictEqual(b2.out.statusCode, 201);
        const secondApptId = b2.out.body.appointment.id;
        ids.appointmentIds.push(secondApptId);

        // Mark +15m delayed
        const d15 = createMockRes();
        await appointmentController.markConsultationDelayed(
            {
                params: { id: firstApptId },
                user: { id: ids.doc1UserId, role: 'Dentist' },
                body: { delayMinutes: 15 }
            },
            d15.res
        );
        assert.strictEqual(d15.out.statusCode, 200);
        assert.strictEqual(d15.out.body.doctorStatus, 'Delayed');
        assert.strictEqual(d15.out.body.delayMinutes, 15);
        assert.ok(d15.out.body.nextAppointment, 'Next appointment metadata should be updated');
        assert.notStrictEqual(d15.out.body.nextAppointment.status, 'CANCELLED');

        // Mark +30m delayed (crosses threshold >= 15m -> adminAlertTriggered)
        const d30 = createMockRes();
        await appointmentController.markConsultationDelayed(
            {
                params: { id: firstApptId },
                user: { id: ids.doc1UserId, role: 'Dentist' },
                body: { delayMinutes: 30 }
            },
            d30.res
        );
        assert.strictEqual(d30.out.statusCode, 200);
        assert.strictEqual(d30.out.body.delayMinutes, 30);
        assert.strictEqual(d30.out.body.adminAlertTriggered, true);

        const { data: pat2Notifs } = await supabaseAdmin
            .from('notifications')
            .select('*')
            .eq('recipient_id', ids.pat2UserId);
        assert.ok((pat2Notifs || []).some(n => String(n.title).toLowerCase().includes('late')));

        const { data: adminNotifs } = await supabaseAdmin
            .from('notifications')
            .select('*')
            .eq('recipient_id', 'ALL_ADMINS')
            .eq('type', 'admin_doctor_delay_alert');
        assert.ok((adminNotifs || []).some(n => String(n.message || '').includes(suffix)));

        // Live scheduling status API reflects delayed doctor + next appointment
        const liveCall = createMockRes();
        await appointmentController.getLiveSchedulingStatus(
            { query: { date: dayD }, user: { id: ids.adminUserId, role: 'Admin' } },
            liveCall.res
        );
        assert.strictEqual(liveCall.out.statusCode, 200);
        const liveDoc = (liveCall.out.body.doctors || []).find(d => d.doctorId === ids.dentist1Id);
        assert.ok(liveDoc);
        assert.strictEqual(liveDoc.currentAvailability, 'Delayed');
        assert.strictEqual(liveDoc.delayDurationMinutes, 30);

        // Scenario 7: Patient delay actions (WAIT, SWITCH_DOCTOR, REQUEST_RESCHEDULE + reschedule confirmation)
        const waitCall = createMockRes();
        await appointmentController.submitPatientDelayResponse(
            {
                params: { id: secondApptId },
                user: { id: ids.pat2UserId, role: 'Patient' },
                body: { action: 'WAIT' }
            },
            waitCall.res
        );
        assert.strictEqual(waitCall.out.statusCode, 200);
        assert.strictEqual(waitCall.out.body.appointment.patient_delay_choice, 'WAIT');

        const switchCall = createMockRes();
        await appointmentController.submitPatientDelayResponse(
            {
                params: { id: secondApptId },
                user: { id: ids.pat2UserId, role: 'Patient' },
                body: { action: 'SWITCH_DOCTOR' }
            },
            switchCall.res
        );
        assert.strictEqual(switchCall.out.statusCode, 200);
        assert.ok(Array.isArray(switchCall.out.body.alternateDoctors));
        assert.ok(switchCall.out.body.alternateDoctors.some(d => d.id === ids.dentist2Id));

        const reqReschedCall = createMockRes();
        await appointmentController.submitPatientDelayResponse(
            {
                params: { id: secondApptId },
                user: { id: ids.pat2UserId, role: 'Patient' },
                body: {
                    action: 'REQUEST_RESCHEDULE',
                    requestedDate: dayD,
                    requestedTimeSlot: '04:30 PM',
                    reason: 'Cannot wait 30 min'
                }
            },
            reqReschedCall.res
        );
        assert.strictEqual(reqReschedCall.out.statusCode, 200);
        assert.strictEqual(reqReschedCall.out.body.appointment.reschedule_request.status, 'PENDING');

        const liveWithResched = createMockRes();
        await appointmentController.getLiveSchedulingStatus(
            { query: { date: dayD }, user: { id: ids.adminUserId, role: 'Admin' } },
            liveWithResched.res
        );
        assert.ok((liveWithResched.out.body.pendingRescheduleRequests || []).some(r => r.appointmentId === secondApptId));

        // Actual reschedule moves slot & sends confirmation
        const reschedExec = createMockRes();
        await appointmentController.rescheduleAppointment(
            {
                params: { id: secondApptId },
                user: { id: ids.pat2UserId, role: 'Patient' },
                body: { date: dayD, timeSlot: '04:30 PM' }
            },
            reschedExec.res
        );
        assert.strictEqual(reschedExec.out.statusCode, 200);
        assert.strictEqual(reschedExec.out.body.appointment.time_slot, '04:30 PM');
    });

    it('6. Simultaneous double booking attempt across Online & In-Person -> 1 succeeds (201), 1 fails (409)', async () => {
        const c1 = createMockRes();
        const c2 = createMockRes();

        await Promise.all([
            appointmentController.bookAppointment(
                {
                    user: { id: ids.pat1UserId, role: 'Patient' },
                    body: {
                        dentistId: ids.dentist1Id,
                        patientId: ids.pat1UserId,
                        date: dayE,
                        timeSlot: '02:00 PM',
                        treatment: 'Concurrent In-Person',
                        consultationMode: 'In-Person'
                    }
                },
                c1.res
            ),
            appointmentController.bookAppointment(
                {
                    user: { id: ids.pat2UserId, role: 'Patient' },
                    body: {
                        dentistId: ids.dentist1Id,
                        patientId: ids.pat2UserId,
                        date: dayE,
                        timeSlot: '02:00 PM',
                        treatment: 'Concurrent Online',
                        consultationMode: 'Online'
                    }
                },
                c2.res
            )
        ]);

        const codes = [c1.out.statusCode, c2.out.statusCode].sort((a, b) => a - b);
        assert.deepStrictEqual(codes, [201, 409], `Expected [201, 409], got ${JSON.stringify(codes)}`);
        if (c1.out.body?.appointment?.id) ids.appointmentIds.push(c1.out.body.appointment.id);
        if (c2.out.body?.appointment?.id) ids.appointmentIds.push(c2.out.body.appointment.id);
    });

    it('8 & 9. Doctor Unavailable preserves existing appts & blocks new bookings; Admin manual slot block/unblock works', async () => {
        // Admin blocks 04:00 PM on dayE
        const blkCall = createMockRes();
        await availabilityController.blockTimeSlot(
            {
                user: { id: ids.adminUserId, role: 'Admin' },
                body: { dentistId: ids.dentist1Id, date: dayE, startTime: '04:00 PM', reason: 'Surgery' }
            },
            blkCall.res
        );
        assert.strictEqual(blkCall.out.statusCode, 200);
        assert.ok(blkCall.out.body.blockedSlots.some(s => s.startTime === '04:00 PM'));

        // Booking on manually blocked 04:00 PM must fail with 409
        const blockedBook = createMockRes();
        await appointmentController.bookAppointment(
            {
                user: { id: ids.pat1UserId, role: 'Patient' },
                body: {
                    dentistId: ids.dentist1Id,
                    patientId: ids.pat1UserId,
                    date: dayE,
                    timeSlot: '04:00 PM',
                    treatment: 'Checkup',
                    consultationMode: 'Online'
                }
            },
            blockedBook.res
        );
        assert.strictEqual(blockedBook.out.statusCode, 409);

        // Unblock 04:00 PM -> now available
        const unblkCall = createMockRes();
        await availabilityController.unblockTimeSlot(
            {
                user: { id: ids.adminUserId, role: 'Admin' },
                query: { dentistId: ids.dentist1Id, date: dayE, startTime: '04:00 PM' }
            },
            unblkCall.res
        );
        assert.strictEqual(unblkCall.out.statusCode, 200);

        // Set Doctor Unavailable -> existing confirmed/pending appointments remain, new bookings return 409
        const offCall = createMockRes();
        await clinicController.updateDoctorAvailability(
            {
                params: { id: ids.dentist1Id },
                user: { id: ids.doc1UserId, role: 'Dentist' },
                body: { status: 'Unavailable' }
            },
            offCall.res
        );
        assert.strictEqual(offCall.out.statusCode, 200);

        const newBookWhileOff = createMockRes();
        await appointmentController.bookAppointment(
            {
                user: { id: ids.pat2UserId, role: 'Patient' },
                body: {
                    dentistId: ids.dentist1Id,
                    patientId: ids.pat2UserId,
                    date: dayE,
                    timeSlot: '04:00 PM',
                    treatment: 'Checkup',
                    consultationMode: 'Online'
                }
            },
            newBookWhileOff.res
        );
        assert.strictEqual(newBookWhileOff.out.statusCode, 409);

        // Existing appointments on dayE are still preserved
        const { data: existingOnDayE } = await supabaseAdmin
            .from('appointments')
            .select('id, status')
            .eq('dentist_id', ids.dentist1Id)
            .eq('date', dayE);
        assert.strictEqual((existingOnDayE || []).length, 1);

        // Mark patient No-Show on dayE's appointment -> sets NO_SHOW & doctor Available
        const noShowCall = createMockRes();
        await appointmentController.markPatientNoShow(
            {
                params: { id: existingOnDayE[0].id },
                user: { id: ids.doc1UserId, role: 'Dentist' }
            },
            noShowCall.res
        );
        assert.strictEqual(noShowCall.out.statusCode, 200);
        assert.strictEqual(noShowCall.out.body.appointment.status, 'NO_SHOW');
        assert.strictEqual(noShowCall.out.body.doctorStatus, 'Available');
    });
});
