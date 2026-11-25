/**
 * GS HEALTH / DentaGuru — Calendar-Based Visit Management E2E Tests (gs-health-test ONLY)
 * Covers all 12 required Phase 6 scenarios against real Express controllers + Supabase test DB:
 * 1. Doctor selects a date with multiple appointments.
 * 2. Doctor selects a date with no appointments.
 * 3. Doctor sees patient referral information.
 * 4. Doctor sees correct pending/completed counts.
 * 5. Admin sees all hospitals and clinics.
 * 6. Admin selects a date and sees accurate overall counts (with unique patient deduplication).
 * 7. Admin filters by hospital and doctor.
 * 8. Referral does not incorrectly count as a completed visit.
 * 9. Cancelled and no-show appointments are counted separately.
 * 10. Doctor cannot access another doctor's visit records (403 Forbidden).
 * 11. Sub-Admin district permissions are respected.
 * 12. Asia/Kolkata date boundaries are handled correctly.
 */
require('dotenv').config({ path: require('path').resolve(__dirname, '../.env') });
const assert = require('assert');
const crypto = require('crypto');
const { describe, it, before, after } = require('node:test');

const supaUrl = (process.env.SUPABASE_URL || '').trim();
if (!supaUrl.includes('ojinzcdldwugpnxrnjcq') || supaUrl.includes('fommrwxpqzkcktweosgp')) {
    console.error('SAFETY ABORT: calendar_visit_management.test.js may ONLY run against gs-health-test (ojinzcdldwugpnxrnjcq).');
    process.exit(1);
}

const { supabaseAdmin } = require('../src/config/supabase');
const {
    Referral,
    District,
    SubAdminDistrict,
    SubAdminPermission,
} = require('../src/models/Schemas');
const appointmentController = require('../src/controllers/appointmentController');
const { normalizeDateToTimezoneYmd } = require('../src/config/bookingRulesConfig');

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
        },
    };
    return { res, out };
}

describe('Calendar-Based Visit Management (Doctor & Admin Visits Calendars)', () => {
    const createdUserIds = [];
    const createdDentistIds = [];
    const createdClinicIds = [];
    const createdAppointmentIds = [];
    const createdReferralIds = [];
    const createdDistrictIds = [];

    let clinicAId, clinicBId;
    let docAUserId, docADentistId;
    let docBUserId, docBDentistId;
    let patient1Id, patient2Id, patient3Id, referredOnlyPatientId;
    let subAdminId, districtHydId;

    const activeDate = '2026-12-10';
    const emptyDate = '2026-12-11';

    before(async () => {
        const suffix = Date.now().toString().slice(-6);
        const pw = 'TestPassword123!';

        // 1. Create two doctors + 4 patients + 1 Sub-Admin in users table
        const { data: docAUser, error: uErr1 } = await supabaseAdmin.from('users').insert({
            name: `Dr. Arjun Calendar ${suffix}`,
            email: `dr_arjun_cal_${suffix}@gshealth-test.local`,
            password: pw,
            phone: `9211${suffix}`,
            role: 'Dentist',
            status: 'ACTIVE',
            city: 'Hyderabad',
        }).select().single();
        if (uErr1) throw uErr1;
        docAUserId = docAUser.id;
        createdUserIds.push(docAUserId);

        const { data: docBUser, error: uErr2 } = await supabaseAdmin.from('users').insert({
            name: `Dr. Meera Calendar ${suffix}`,
            email: `dr_meera_cal_${suffix}@gshealth-test.local`,
            password: pw,
            phone: `9212${suffix}`,
            role: 'Dentist',
            status: 'ACTIVE',
            city: 'Warangal',
        }).select().single();
        if (uErr2) throw uErr2;
        docBUserId = docBUser.id;
        createdUserIds.push(docBUserId);

        const { data: p1User, error: uErr3 } = await supabaseAdmin.from('users').insert({
            name: `Patient One Visited ${suffix}`,
            email: `p1_cal_${suffix}@gshealth-test.local`,
            password: pw,
            phone: `9311${suffix}`,
            role: 'Patient',
            status: 'ACTIVE',
            city: 'Hyderabad',
        }).select().single();
        if (uErr3) throw uErr3;
        patient1Id = p1User.id;
        createdUserIds.push(patient1Id);

        const { data: p2User, error: uErr4 } = await supabaseAdmin.from('users').insert({
            name: `Patient Two Pending ${suffix}`,
            email: `p2_cal_${suffix}@gshealth-test.local`,
            password: pw,
            phone: `9312${suffix}`,
            role: 'Patient',
            status: 'ACTIVE',
            city: 'Hyderabad',
        }).select().single();
        if (uErr4) throw uErr4;
        patient2Id = p2User.id;
        createdUserIds.push(patient2Id);

        const { data: p3User, error: uErr5 } = await supabaseAdmin.from('users').insert({
            name: `Patient Three Cancelled ${suffix}`,
            email: `p3_cal_${suffix}@gshealth-test.local`,
            password: pw,
            phone: `9313${suffix}`,
            role: 'Patient',
            status: 'ACTIVE',
            city: 'Warangal',
        }).select().single();
        if (uErr5) throw uErr5;
        patient3Id = p3User.id;
        createdUserIds.push(patient3Id);

        const { data: p4User, error: uErr6 } = await supabaseAdmin.from('users').insert({
            name: `Referred Friend Unbooked ${suffix}`,
            email: `p4_cal_${suffix}@gshealth-test.local`,
            password: pw,
            phone: `9314${suffix}`,
            role: 'Patient',
            status: 'ACTIVE',
            city: 'Hyderabad',
        }).select().single();
        if (uErr6) throw uErr6;
        referredOnlyPatientId = p4User.id;
        createdUserIds.push(referredOnlyPatientId);

        const { data: subAdminUser, error: uErr7 } = await supabaseAdmin.from('users').insert({
            name: `SubAdmin Hyd ${suffix}`,
            email: `subadmin_cal_${suffix}@gshealth-test.local`,
            password: pw,
            phone: `9411${suffix}`,
            role: 'Sub-Admin',
            status: 'ACTIVE',
            city: 'Hyderabad',
        }).select().single();
        if (uErr7) throw uErr7;
        subAdminId = subAdminUser.id;
        createdUserIds.push(subAdminId);

        // 2. Create two distinct hospitals/clinics in different cities/districts
        const { data: cA, error: cErr1 } = await supabaseAdmin.from('clinics').insert({
            user_id: docAUserId,
            clinic_name: `Apollo Heart Hospital ${suffix}`,
            location: 'Jubilee Hills, Hyderabad',
            verified: true,
            services: ['Cardiology'],
        }).select().single();
        if (cErr1) throw cErr1;
        clinicAId = cA.id;
        createdClinicIds.push(clinicAId);

        const { data: cB, error: cErr2 } = await supabaseAdmin.from('clinics').insert({
            user_id: docBUserId,
            clinic_name: `KIMS Ortho Clinic ${suffix}`,
            location: 'Hanamkonda, Warangal',
            verified: true,
            services: ['Orthopedics'],
        }).select().single();
        if (cErr2) throw cErr2;
        clinicBId = cB.id;
        createdClinicIds.push(clinicBId);

        // 3. Create dentist profiles for Doctor A (Clinic A) and Doctor B (Clinic B)
        const { data: dA, error: dErr1 } = await supabaseAdmin.from('dentists').insert({
            user_id: docAUserId,
            clinic_id: clinicAId,
            speciality: 'Cardiology',
            license_number: `CAL-A-${suffix}`,
            qualifications: 'MBBS, MD',
            availability_status: 'Available',
            verification_status: 'VERIFIED',
            city: 'Hyderabad',
        }).select().single();
        if (dErr1) throw dErr1;
        docADentistId = dA.id;
        createdDentistIds.push(docADentistId);

        const { data: dB, error: dErr2 } = await supabaseAdmin.from('dentists').insert({
            user_id: docBUserId,
            clinic_id: clinicBId,
            speciality: 'Orthopedics',
            license_number: `CAL-B-${suffix}`,
            qualifications: 'MBBS, MS Ortho',
            availability_status: 'Available',
            verification_status: 'VERIFIED',
            city: 'Warangal',
        }).select().single();
        if (dErr2) throw dErr2;
        docBDentistId = dB.id;
        createdDentistIds.push(docBDentistId);

        // 4. Configure Sub-Admin permission & Hyderabad district assignment via Schemas models
        await SubAdminPermission.setPermissionsForUser(subAdminId, ['APPOINTMENT_VIEW', 'PATIENT_VIEW']);
        let hydDist = await District.findOne({ name: 'Hyderabad' });
        if (!hydDist) {
            hydDist = await District.create({
                name: 'Hyderabad',
                state: 'Telangana',
                country: 'India',
                is_active: true,
            });
            createdDistrictIds.push(hydDist.id);
        }
        districtHydId = hydDist.id;
        await SubAdminDistrict.assignDistrictsToSubAdmin(subAdminId, [districtHydId], docAUserId);

        // 5. Insert appointments on `activeDate` (2026-12-10) for Doctor A and Doctor B:
        const apptRows = [
            {
                patient_id: patient1Id,
                dentist_id: docADentistId,
                clinic_id: clinicAId,
                date: activeDate,
                time_slot: '09:30 AM',
                treatment: 'In-Person - Cardiology Checkup',
                status: 'COMPLETED',
            },
            {
                patient_id: patient1Id,
                dentist_id: docADentistId,
                clinic_id: clinicAId,
                date: activeDate,
                time_slot: '11:00 AM',
                treatment: 'Online - Cardiology Follow-up',
                status: 'COMPLETED',
            },
            {
                patient_id: patient2Id,
                dentist_id: docADentistId,
                clinic_id: clinicAId,
                date: activeDate,
                time_slot: '12:00 PM',
                treatment: 'Online - ECG Review',
                status: 'CONFIRMED',
            },
            {
                patient_id: patient3Id,
                dentist_id: docADentistId,
                clinic_id: clinicAId,
                date: activeDate,
                time_slot: '02:00 PM',
                treatment: 'In-Person - Consultation',
                status: 'CANCELLED',
            },
            {
                patient_id: patient3Id,
                dentist_id: docADentistId,
                clinic_id: clinicAId,
                date: activeDate,
                time_slot: '03:00 PM',
                treatment: 'In-Person - Consultation',
                status: 'NO_SHOW',
            },
            {
                patient_id: patient3Id,
                dentist_id: docBDentistId,
                clinic_id: clinicBId,
                date: activeDate,
                time_slot: '10:00 AM',
                treatment: 'In-Person - Knee Evaluation',
                status: 'COMPLETED',
            },
        ];
        const { data: insertedAppts, error: aErr } = await supabaseAdmin.from('appointments').insert(apptRows).select();
        if (aErr) throw aErr;
        for (const r of (insertedAppts || [])) createdAppointmentIds.push(r.id);

        // 6. Insert 2 Referrals for Doctor A using Referral.create:
        const createdRef1 = await Referral.create({
            referrer_patient_id: patient1Id,
            referred_patient_id: referredOnlyPatientId,
            referred_patient_name: `Referred Friend Unbooked ${suffix}`,
            referred_patient_mobile: `9314${suffix}`,
            referred_patient_age: '32',
            referred_patient_gender: 'Male',
            referred_patient_city: 'Hyderabad',
            referred_patient_pincode: '500033',
            referred_patient_location: 'Hyderabad',
            required_specialist: 'Cardiology',
            clinical_complaint: 'Chest discomfort',
            doctor_id: docADentistId,
            status: 'Pending',
            referral_date: '2026-12-09T20:15:00.000Z',
            created_at: '2026-12-09T20:15:00.000Z',
        });
        createdReferralIds.push(createdRef1.id);

        const createdRef2 = await Referral.create({
            referrer_patient_id: patient2Id,
            referred_patient_id: patient1Id,
            referred_patient_name: `Patient One Visited ${suffix}`,
            referred_patient_mobile: `9311${suffix}`,
            referred_patient_age: '29',
            referred_patient_gender: 'Female',
            referred_patient_city: 'Hyderabad',
            referred_patient_pincode: '500033',
            referred_patient_location: 'Hyderabad',
            required_specialist: 'Cardiology',
            clinical_complaint: 'BP check',
            doctor_id: docADentistId,
            status: 'Accepted',
            referral_date: `${activeDate}T06:00:00.000Z`,
            created_at: `${activeDate}T06:00:00.000Z`,
        });
        createdReferralIds.push(createdRef2.id);
    });

    after(async () => {
        for (const rId of createdReferralIds) {
            await Referral.findByIdAndDelete(rId).catch(() => {});
        }
        if (createdAppointmentIds.length) {
            await supabaseAdmin.from('appointments').delete().in('id', createdAppointmentIds);
        }
        if (subAdminId) {
            await supabaseAdmin.from('sub_admin_permissions').delete().eq('user_id', subAdminId);
            await supabaseAdmin.from('sub_admin_districts').delete().eq('sub_admin_id', subAdminId);
        }
        if (createdDistrictIds.length) {
            await supabaseAdmin.from('districts').delete().in('id', createdDistrictIds);
        }
        if (createdDentistIds.length) {
            await supabaseAdmin.from('dentists').delete().in('id', createdDentistIds);
        }
        if (createdClinicIds.length) {
            await supabaseAdmin.from('clinics').delete().in('id', createdClinicIds);
        }
        if (createdUserIds.length) {
            await supabaseAdmin.from('users').delete().in('id', createdUserIds);
        }
    });

    it('Scenarios 1, 3, 4, 8, 9 & 12: Doctor selects date with multiple appointments -> sees accurate pending/completed/cancelled/no-show/referral counts, deduplicated actual visits, and Asia/Kolkata boundary handling', async () => {
        assert.strictEqual(
            normalizeDateToTimezoneYmd('2026-12-09T20:15:00.000Z', 'Asia/Kolkata'),
            '2026-12-10',
            '20:15 UTC on Dec 9 must resolve to Dec 10 in Asia/Kolkata (+05:30)'
        );
        assert.strictEqual(
            normalizeDateToTimezoneYmd('2026-12-09T17:30:00.000Z', 'Asia/Kolkata'),
            '2026-12-09',
            '17:30 UTC on Dec 9 must remain Dec 9 in Asia/Kolkata (+05:30)'
        );

        const { res, out } = createMockRes();
        await appointmentController.getDoctorVisitsCalendar(
            {
                user: { id: docAUserId, role: 'Dentist' },
                query: { doctorId: docADentistId, date: activeDate, month: '2026-12' },
            },
            res
        );

        assert.strictEqual(out.statusCode, 200);
        assert.strictEqual(out.body.success, true);

        const stats = out.body.selectedDateStats;
        assert.strictEqual(stats.totalAppointments, 5, 'Total appointments for Doctor A should be 5');
        assert.strictEqual(stats.completedConsultations, 2, 'Completed consultations should be 2');
        assert.strictEqual(
            stats.actualPatientVisits,
            1,
            'Unique patients who actually visited must be 1 (Patient 1 deduplicated; unbooked referral NOT counted)'
        );
        assert.strictEqual(stats.pendingConsultations, 1, 'Pending consultations should be 1');
        assert.strictEqual(stats.cancelledAppointments, 1, 'Cancelled appointments should be 1');
        assert.strictEqual(stats.noShowAppointments, 1, 'No-Show appointments should be 1 (separate from cancelled)');
        assert.strictEqual(stats.onlineConsultations, 2, 'Online consultations should be 2');
        assert.strictEqual(stats.inPersonConsultations, 3, 'In-Person consultations should be 3');

        assert.strictEqual(stats.patientReferralsReceived, 2, 'Should count both referrals on 2026-12-10 in Asia/Kolkata');
        assert.strictEqual(stats.patientsReferredByOtherPatients, 2);

        const refsOnDate = out.body.referralsOnDate;
        const unbookedRef = refsOnDate.find(r => r.referredPatientId === referredOnlyPatientId);
        assert.ok(unbookedRef, 'Unbooked referral should be present in referral tracking list');
        assert.strictEqual(unbookedRef.hasBookedAppointment, false);
        assert.strictEqual(unbookedRef.hasCompletedConsultation, false);

        const completedRef = refsOnDate.find(r => r.referredPatientId === patient1Id);
        assert.ok(completedRef, 'Booked & completed referral should be present');
        assert.strictEqual(completedRef.hasBookedAppointment, true);
        assert.strictEqual(completedRef.hasCompletedConsultation, true);
    });

    it('Scenario 2: Doctor selects a date with no appointments -> returns zero stats and empty visits list', async () => {
        const { res, out } = createMockRes();
        await appointmentController.getDoctorVisitsCalendar(
            {
                user: { id: docAUserId, role: 'Dentist' },
                query: { doctorId: docADentistId, date: emptyDate, month: '2026-12' },
            },
            res
        );

        assert.strictEqual(out.statusCode, 200);
        assert.strictEqual(out.body.success, true);
        assert.strictEqual(out.body.selectedDateStats.totalAppointments, 0);
        assert.strictEqual(out.body.selectedDateStats.actualPatientVisits, 0);
        assert.strictEqual(out.body.visits.length, 0);
    });

    it("Scenario 10: Doctor cannot access another doctor's visit records (returns 403 Forbidden)", async () => {
        const { res, out } = createMockRes();
        await appointmentController.getDoctorVisitsCalendar(
            {
                user: { id: docAUserId, role: 'Dentist' },
                query: { doctorId: docBDentistId, date: activeDate },
            },
            res
        );

        assert.strictEqual(out.statusCode, 403, 'Doctor A requesting Doctor B calendar must be rejected with 403');
        assert.strictEqual(out.body.success, false);
    });

    it('Scenarios 5, 6 & 7: Admin sees all hospitals and clinics, accurate platform-wide counts, and filters by hospital and doctor', async () => {
        const { res, out } = createMockRes();
        await appointmentController.getAdminGlobalVisitsCalendar(
            {
                user: { id: 'admin-main', role: 'Admin' },
                query: { date: activeDate, month: '2026-12' },
            },
            res
        );

        assert.strictEqual(out.statusCode, 200);
        assert.strictEqual(out.body.success, true);

        const hospA = out.body.hospitalClinicBreakdown.find(h => h.clinicId === clinicAId);
        const hospB = out.body.hospitalClinicBreakdown.find(h => h.clinicId === clinicBId);
        assert.ok(hospA, 'Clinic A must be in hospital/clinic breakdown');
        assert.ok(hospB, 'Clinic B must be in hospital/clinic breakdown');
        assert.strictEqual(hospA.scheduledVisits, 5);
        assert.strictEqual(hospA.completedVisits, 2);
        assert.strictEqual(hospA.actualPatientVisits, 1, 'Clinic A has 1 unique visited patient');
        assert.strictEqual(hospA.pendingVisits, 1);
        assert.strictEqual(hospA.cancelledVisits, 1);
        assert.strictEqual(hospA.noShowVisits, 1);
        assert.strictEqual(hospB.scheduledVisits, 1);
        assert.strictEqual(hospB.completedVisits, 1);
        assert.strictEqual(hospB.actualPatientVisits, 1);

        const { res: resFiltered, out: outFiltered } = createMockRes();
        await appointmentController.getAdminGlobalVisitsCalendar(
            {
                user: { id: 'admin-main', role: 'Admin' },
                query: {
                    date: activeDate,
                    month: '2026-12',
                    clinicId: clinicBId,
                    doctorId: docBDentistId,
                },
            },
            resFiltered
        );

        assert.strictEqual(outFiltered.statusCode, 200);
        assert.strictEqual(outFiltered.body.selectedDateStats.totalScheduledAppointments, 1);
        assert.strictEqual(outFiltered.body.selectedDateStats.completedAppointments, 1);
        assert.strictEqual(outFiltered.body.visits.length, 1);
        assert.strictEqual(outFiltered.body.visits[0].clinicId, clinicBId);
    });

    it('Scenario 11: Sub-Admin district permissions are respected (sees assigned Hyderabad district, blocked from Warangal)', async () => {
        const { res, out } = createMockRes();
        await appointmentController.getAdminGlobalVisitsCalendar(
            {
                user: {
                    id: subAdminId,
                    role: 'Sub-Admin',
                    permissions: ['APPOINTMENT_VIEW', 'PATIENT_VIEW'],
                },
                query: { date: activeDate, month: '2026-12' },
            },
            res
        );

        assert.strictEqual(out.statusCode, 200);
        assert.strictEqual(out.body.isSubAdminScoped, true);
        const seesClinicA = out.body.hospitalClinicBreakdown.some(h => h.clinicId === clinicAId);
        const seesClinicB = out.body.hospitalClinicBreakdown.some(h => h.clinicId === clinicBId);
        assert.strictEqual(seesClinicA, true, 'Sub-Admin assigned to Hyderabad should see Hyderabad clinic');
        assert.strictEqual(seesClinicB, false, 'Sub-Admin assigned to Hyderabad must NOT see Warangal clinic');

        const { res: resForbidden, out: outForbidden } = createMockRes();
        await appointmentController.getAdminGlobalVisitsCalendar(
            {
                user: {
                    id: subAdminId,
                    role: 'Sub-Admin',
                    permissions: ['APPOINTMENT_VIEW'],
                },
                query: { date: activeDate, district: 'Warangal' },
            },
            resForbidden
        );
        assert.strictEqual(outForbidden.statusCode, 403, 'Sub-Admin querying unauthorized district must receive 403');
    });

    it('Scenario 13: Two different patients with identical names are NEVER merged into 1 patient, while multiple appointments for the same patient_id ARE deduplicated', async () => {
        const dupSuffix = String(Date.now()).slice(-6);
        const dupNameDate = '2026-12-12';
        const identicalName = `Ravi Kumar Identical ${dupSuffix}`;

        const { data: uSame1, error: e1 } = await supabaseAdmin.from('users').insert([{
            name: identicalName,
            email: `ravi_dup1_${dupSuffix}@gshealth.test`,
            phone: `9411${dupSuffix}`,
            role: 'Patient',
            password: 'hashed_test_password',
        }]).select().single();
        if (e1) throw e1;
        createdUserIds.push(uSame1.id);

        const { data: uSame2, error: e2 } = await supabaseAdmin.from('users').insert([{
            name: identicalName,
            email: `ravi_dup2_${dupSuffix}@gshealth.test`,
            phone: `9412${dupSuffix}`,
            role: 'Patient',
            password: 'hashed_test_password',
        }]).select().single();
        if (e2) throw e2;
        createdUserIds.push(uSame2.id);

        // Insert 3 completed appointments on dupNameDate:
        // - 2 completed appointments for uSame1 (same patient_id)
        // - 1 completed appointment for uSame2 (different patient_id, exact same name)
        const { data: dupAppts, error: dupErr } = await supabaseAdmin.from('appointments').insert([
            {
                patient_id: uSame1.id,
                dentist_id: docADentistId,
                clinic_id: clinicAId,
                date: dupNameDate,
                time_slot: '09:00 AM',
                treatment: 'In-Person - Consultation 1',
                status: 'COMPLETED',
            },
            {
                patient_id: uSame1.id,
                dentist_id: docADentistId,
                clinic_id: clinicAId,
                date: dupNameDate,
                time_slot: '11:00 AM',
                treatment: 'Online - Follow-up 2',
                status: 'COMPLETED',
            },
            {
                patient_id: uSame2.id,
                dentist_id: docADentistId,
                clinic_id: clinicAId,
                date: dupNameDate,
                time_slot: '02:00 PM',
                treatment: 'In-Person - Consultation for second Ravi Kumar',
                status: 'COMPLETED',
            },
        ]).select();
        if (dupErr) throw dupErr;
        for (const r of (dupAppts || [])) createdAppointmentIds.push(r.id);

        const { res, out } = createMockRes();
        await appointmentController.getDoctorVisitsCalendar(
            {
                user: { id: docAUserId, role: 'Dentist' },
                query: { doctorId: docADentistId, date: dupNameDate, month: '2026-12' },
            },
            res
        );

        assert.strictEqual(out.statusCode, 200);
        const stats = out.body.selectedDateStats;
        assert.strictEqual(stats.totalAppointments, 3, '3 total appointments on 2026-12-12');
        assert.strictEqual(stats.completedConsultations, 3, '3 completed consultations on 2026-12-12');
        assert.strictEqual(
            stats.actualPatientVisits,
            2,
            'Two different patients with identical names must be counted as 2 unique actual patient visits, while uSame1 two appointments count once'
        );
    });
});
