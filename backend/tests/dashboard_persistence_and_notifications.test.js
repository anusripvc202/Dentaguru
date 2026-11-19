const test = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');

require('dotenv').config();
process.env.NODE_ENV = 'test';
process.env.OTP_DELIVERY_MODE = 'on_screen';

const app = require('../src/app');
const { supabaseAdmin } = require('../src/config/supabase');

function startTestServer() {
    return new Promise((resolve) => {
        const server = http.createServer(app);
        server.listen(0, '127.0.0.1', () => {
            const { port } = server.address();
            resolve({
                server,
                baseUrl: `http://127.0.0.1:${port}/api/v1`
            });
        });
    });
}

async function apiRequest(baseUrl, method, path, { body, token } = {}) {
    const headers = { 'Content-Type': 'application/json' };
    if (token) headers.Authorization = `Bearer ${token}`;
    const res = await fetch(`${baseUrl}${path}`, {
        method,
        headers,
        body: body ? JSON.stringify(body) : undefined
    });
    const json = await res.json().catch(() => ({}));
    return { status: res.status, body: json };
}

test('GS HEALTH Complete Dashboard Data Persistence, Notifications & Find Doctors E2E Suite (Scenarios 1-13)', async (t) => {
    const { server, baseUrl } = await startTestServer();

    const createdUserIds = [];
    const createdDentistIds = [];
    const createdClinicIds = [];
    const createdAppointmentIds = [];
    const createdNotificationIds = [];

    t.after(async () => {
        for (const id of createdNotificationIds) {
            try { await supabaseAdmin.from('notifications').delete().eq('id', id); } catch (_) {}
        }
        for (const id of createdAppointmentIds) {
            try { await supabaseAdmin.from('patient_assignment_history').delete().eq('appointment_id', id); } catch (_) {}
            try { await supabaseAdmin.from('appointments').delete().eq('id', id); } catch (_) {}
        }
        for (const id of createdDentistIds) {
            try { await supabaseAdmin.from('notifications').delete().eq('recipient_id', id); } catch (_) {}
            try { await supabaseAdmin.from('dentists').delete().eq('id', id); } catch (_) {}
        }
        for (const id of createdClinicIds) {
            try { await supabaseAdmin.from('clinics').delete().eq('id', id); } catch (_) {}
        }
        for (const id of createdUserIds) {
            try { await supabaseAdmin.from('notifications').delete().eq('recipient_id', id); } catch (_) {}
            try { await supabaseAdmin.from('users').delete().eq('id', id); } catch (_) {}
        }
        if (typeof server.closeAllConnections === 'function') {
            server.closeAllConnections();
        }
        await new Promise((resolve) => server.close(resolve));
    });

    const suffix = String(Date.now()).slice(-6);
    const patientPhone = `9711${suffix}`;
    const docBPhone = `9722${suffix}`;
    const docCPhone = `9733${suffix}`;

    let patientId;
    let patientToken;
    let docBUserId;
    let docBDentistId;
    let docBToken;
    let docCDentistId;
    let adminId;
    let adminToken;
    let bookedApptId;

    await t.test('Setup: Register Patient A, Doctor B, Doctor C, and authenticate Admin (verifying Admin registration notifications)', async () => {
        // 1. Register Patient A
        const patReg = await apiRequest(baseUrl, 'POST', '/auth/register', {
            body: {
                name: `Patient A ${suffix}`,
                phone: patientPhone,
                role: 'Patient',
                city: 'Hyderabad',
                pincode: '500081',
                age: '29',
                gender: 'Female'
            }
        });
        assert.equal(patReg.status, 201, `Patient A registration failed: ${JSON.stringify(patReg.body)}`);
        patientId = patReg.body.user.id;
        patientToken = patReg.body.accessToken;
        createdUserIds.push(patientId);

        // 2. Register Doctor B (Availability ON by default)
        const docBReg = await apiRequest(baseUrl, 'POST', '/auth/register', {
            body: {
                name: `Doctor B ${suffix}`,
                phone: docBPhone,
                role: 'Dentist',
                specialty: 'Orthodontics',
                qualification: 'BDS, MDS (Ortho)',
                clinicName: `Ortho Care Clinic ${suffix}`,
                city: 'Hyderabad',
                pincode: '500081',
                experienceYears: 9
            }
        });
        assert.equal(docBReg.status, 201, `Doctor B registration failed: ${JSON.stringify(docBReg.body)}`);
        docBUserId = docBReg.body.user.id;
        docBDentistId = docBReg.body.user.dentistId;
        docBToken = docBReg.body.accessToken;
        assert.ok(docBDentistId, 'Doctor registration must return dentistId');
        createdUserIds.push(docBUserId);
        createdDentistIds.push(docBDentistId);

        const { data: docBRow } = await supabaseAdmin.from('dentists').select('clinic_id').eq('id', docBDentistId).maybeSingle();
        if (docBRow?.clinic_id) createdClinicIds.push(docBRow.clinic_id);

        // 3. Register Doctor C (Second doctor for Find Doctors & non-substitution verification)
        const docCReg = await apiRequest(baseUrl, 'POST', '/auth/register', {
            body: {
                name: `Doctor C ${suffix}`,
                phone: docCPhone,
                role: 'Dentist',
                specialty: 'Endodontics',
                qualification: 'BDS, MDS (Endo)',
                clinicName: `Root Canal Center ${suffix}`,
                city: 'Hyderabad',
                pincode: '500082',
                experienceYears: 7
            }
        });
        assert.equal(docCReg.status, 201, `Doctor C registration failed: ${JSON.stringify(docCReg.body)}`);
        createdUserIds.push(docCReg.body.user.id);
        docCDentistId = docCReg.body.user.dentistId;
        createdDentistIds.push(docCDentistId);

        const { data: docCRow } = await supabaseAdmin.from('dentists').select('clinic_id').eq('id', docCDentistId).maybeSingle();
        if (docCRow?.clinic_id) createdClinicIds.push(docCRow.clinic_id);

        // 4. Authenticate Primary Admin (9281030535)
        const adminLogin = await apiRequest(baseUrl, 'POST', '/auth/login', {
            body: { phone: '9281030535', role: 'Admin' }
        });
        assert.equal(adminLogin.status, 200, `Admin login failed: ${JSON.stringify(adminLogin.body)}`);
        adminId = adminLogin.body.user.id;
        adminToken = adminLogin.body.accessToken;
    });

    await t.test('Scenarios 1, 2, 3, 4: Patient A books appointment with Doctor B -> visible in Patient, Doctor, and Admin dashboards', async () => {
        const tomorrow = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString().split('T')[0];

        // Scenario 1: Patient A books an appointment with Doctor B
        const bookRes = await apiRequest(baseUrl, 'POST', '/appointments', {
            token: patientToken,
            body: {
                patientId,
                dentistId: docBDentistId,
                date: tomorrow,
                timeSlot: '10:30 AM',
                treatment: 'Orthodontic Braces Consultation'
            }
        });
        assert.equal(bookRes.status, 201, `Booking failed: ${JSON.stringify(bookRes.body)}`);
        bookedApptId = bookRes.body.appointment.id;
        createdAppointmentIds.push(bookedApptId);

        // Scenario 2: Booking appears in Patient A's dashboard
        const patAppts = await apiRequest(baseUrl, 'GET', `/appointments?patientId=${patientId}`, {
            token: patientToken
        });
        assert.equal(patAppts.status, 200);
        const patBooking = patAppts.body.appointments.find((a) => a.id === bookedApptId);
        assert.ok(patBooking, 'Booking must be returned for Patient A');
        assert.equal(patBooking.dentist_id, docBDentistId);
        assert.ok(patBooking.selectedDoctor.name.includes(`Doctor B ${suffix}`));
        assert.equal(patBooking.selectedDoctor.specialty, 'Orthodontics');
        assert.equal(patBooking.clinic_name, `Ortho Care Clinic ${suffix}`);
        assert.equal(patBooking.time_slot, '10:30 AM');
        assert.ok(patBooking.booking_created_at, 'booking_created_at must be present');

        // Scenario 3: Booking appears in Doctor B's dashboard (queried by both dentists.id AND users.id)
        const docApptsByDentistId = await apiRequest(baseUrl, 'GET', `/appointments?dentistId=${docBDentistId}`, {
            token: docBToken
        });
        assert.equal(docApptsByDentistId.status, 200);
        assert.ok(
            docApptsByDentistId.body.appointments.some((a) => a.id === bookedApptId),
            'Booking must be visible when Doctor B queries by dentists.id'
        );

        const docApptsByUserId = await apiRequest(baseUrl, 'GET', `/appointments?dentistId=${docBUserId}`, {
            token: docBToken
        });
        assert.equal(docApptsByUserId.status, 200);
        const docBooking = docApptsByUserId.body.appointments.find((a) => a.id === bookedApptId);
        assert.ok(docBooking, 'Booking must ALSO be visible when Doctor B queries by users.id');
        assert.equal(docBooking.patient.name, `Patient A ${suffix}`);
        assert.equal(docBooking.patient.phone, patientPhone);
        assert.equal(docBooking.patient.city, 'Hyderabad');

        // Scenario 4: Booking appears in Admin dashboard with exact selected Doctor B (even after assigning Doctor C to patient)
        const adminAppts = await apiRequest(baseUrl, 'GET', '/appointments', {
            token: adminToken
        });
        assert.equal(adminAppts.status, 200);
        const adminBooking = adminAppts.body.appointments.find((a) => a.id === bookedApptId);
        assert.ok(adminBooking, 'Booking must be visible in Admin dashboard');
        assert.equal(adminBooking.dentist_id, docBDentistId, 'Admin must see exact selected Doctor B');
        assert.ok(adminBooking.selectedDoctor.name.includes(`Doctor B ${suffix}`));
    });

    await t.test('Scenarios 5, 6, 7: Patient A, Doctor B, and Admin log out and log back in -> booking persists across all 3 dashboards', async () => {
        // Scenario 5: Patient A logs out and logs back in via OTP/login
        const patReLogin = await apiRequest(baseUrl, 'POST', '/auth/login', {
            body: { phone: patientPhone, role: 'Patient' }
        });
        assert.equal(patReLogin.status, 200);
        const freshPatientToken = patReLogin.body.accessToken;
        const freshPatientId = patReLogin.body.user.id;
        assert.equal(freshPatientId, patientId);

        const patApptsAfterRelogin = await apiRequest(baseUrl, 'GET', `/appointments?patientId=${freshPatientId}`, {
            token: freshPatientToken
        });
        assert.equal(patApptsAfterRelogin.status, 200);
        assert.ok(
            patApptsAfterRelogin.body.appointments.some((a) => a.id === bookedApptId),
            'Booking must still be visible in Patient A dashboard after logout and login'
        );

        // Scenario 6: Doctor B logs out and logs back in -> verify login returns both dentistId and userId & booking persists
        const docReLogin = await apiRequest(baseUrl, 'POST', '/auth/login', {
            body: { phone: docBPhone, role: 'Dentist' }
        });
        assert.equal(docReLogin.status, 200);
        assert.equal(docReLogin.body.user.dentistId, docBDentistId, 'Doctor login must return dentists.id as dentistId');
        assert.equal(docReLogin.body.user.userId, docBUserId, 'Doctor login must return users.id as userId');
        const freshDocToken = docReLogin.body.accessToken;

        const docApptsAfterRelogin = await apiRequest(
            baseUrl,
            'GET',
            `/appointments?dentistId=${docReLogin.body.user.dentistId}`,
            { token: freshDocToken }
        );
        assert.equal(docApptsAfterRelogin.status, 200);
        assert.ok(
            docApptsAfterRelogin.body.appointments.some((a) => a.id === bookedApptId),
            'Booking must still be visible in Doctor B dashboard after logout and login'
        );

        // Scenario 7: Admin logs out and logs back in -> booking is still visible
        const adminReLogin = await apiRequest(baseUrl, 'POST', '/auth/login', {
            body: { phone: '9281030535', role: 'Admin' }
        });
        assert.equal(adminReLogin.status, 200);
        const freshAdminToken = adminReLogin.body.accessToken;

        const adminApptsAfterRelogin = await apiRequest(baseUrl, 'GET', '/appointments', {
            token: freshAdminToken
        });
        assert.equal(adminApptsAfterRelogin.status, 200);
        assert.ok(
            adminApptsAfterRelogin.body.appointments.some((a) => a.id === bookedApptId),
            'Booking must still be visible in Admin dashboard after logout and login'
        );
    });

    await t.test('Scenarios 8, 9, 10: Patient, Doctor, and Admin receive persistent notifications, support mark-as-read, and persist across login', async () => {
        // Scenario 8: Patient receives booking notification
        const patNotifsRes = await apiRequest(
            baseUrl,
            'GET',
            `/notifications?role=Patient&userId=${patientId}`,
            { token: patientToken }
        );
        assert.equal(patNotifsRes.status, 200);
        const patBookingNotif = patNotifsRes.body.notifications.find(
            (n) => n.recipient_id === patientId && n.message.includes(`Doctor B ${suffix}`)
        );
        assert.ok(patBookingNotif, 'Patient A must receive persistent booking notification');
        createdNotificationIds.push(patBookingNotif.id);
        assert.equal(patBookingNotif.read, false);

        // Mark Patient notification as read and verify persistence
        const markReadRes = await apiRequest(baseUrl, 'PUT', `/notifications/${patBookingNotif.id}/read`, {
            token: patientToken
        });
        assert.equal(markReadRes.status, 200);

        const patNotifsAfterRead = await apiRequest(
            baseUrl,
            'GET',
            `/notifications?role=Patient&userId=${patientId}`,
            { token: patientToken }
        );
        const updatedPatNotif = patNotifsAfterRead.body.notifications.find((n) => n.id === patBookingNotif.id);
        assert.equal(updatedPatNotif.read, true, 'Notification read state must persist in Supabase');

        // Scenario 9: Doctor receives booking notification (resolvable by both users.id and dentists.id)
        const docNotifsByUserId = await apiRequest(
            baseUrl,
            'GET',
            `/notifications?role=Dentist&userId=${docBUserId}`,
            { token: docBToken }
        );
        assert.equal(docNotifsByUserId.status, 200);
        const docBookingNotif = docNotifsByUserId.body.notifications.find(
            (n) => (n.recipient_id === docBDentistId || n.recipient_id === docBUserId) &&
                n.message.includes(`Patient A ${suffix}`)
        );
        assert.ok(docBookingNotif, 'Doctor B must receive persistent booking notification even when queried by users.id');
        createdNotificationIds.push(docBookingNotif.id);

        // Scenario 10: Admin receives booking notification AND registration notifications
        const adminNotifsRes = await apiRequest(
            baseUrl,
            'GET',
            `/notifications?role=Admin&userId=${adminId}`,
            { token: adminToken }
        );
        assert.equal(adminNotifsRes.status, 200);
        const adminBookingNotif = adminNotifsRes.body.notifications.find(
            (n) => n.message.includes(`Patient A ${suffix}`) && n.message.includes(`Doctor B ${suffix}`)
        );
        assert.ok(adminBookingNotif, 'Admin must receive persistent booking notification');
        createdNotificationIds.push(adminBookingNotif.id);

        const adminPatRegNotif = adminNotifsRes.body.notifications.find(
            (n) => n.type === 'patient_registered' && n.message.includes(`Patient A ${suffix}`)
        );
        assert.ok(adminPatRegNotif, 'Admin must receive persistent notification when a new patient registers');
        createdNotificationIds.push(adminPatRegNotif.id);

        const adminDocRegNotif = adminNotifsRes.body.notifications.find(
            (n) => n.type === 'doctor_registered' && n.message.includes(`Doctor B ${suffix}`)
        );
        assert.ok(adminDocRegNotif, 'Admin must receive persistent notification when a new doctor registers');
        createdNotificationIds.push(adminDocRegNotif.id);

        // Also test appointment confirmation status change notification to Patient & Admin
        const confirmRes = await apiRequest(baseUrl, 'PATCH', `/appointments/${bookedApptId}/accept`, {
            token: docBToken
        });
        assert.equal(confirmRes.status, 200);
        assert.equal(confirmRes.body.appointment.status, 'CONFIRMED');

        const patNotifsAfterConfirm = await apiRequest(
            baseUrl,
            'GET',
            `/notifications?role=Patient&userId=${patientId}`,
            { token: patientToken }
        );
        const confirmNotif = patNotifsAfterConfirm.body.notifications.find(
            (n) => n.type === 'appointment_confirmed' && n.recipient_id === patientId
        );
        assert.ok(confirmNotif, 'Patient must receive persistent notification when appointment is confirmed');
        createdNotificationIds.push(confirmNotif.id);
    });

    await t.test('Scenarios 11, 12, 13: Patient Find Doctors lists all ON doctors, hides OFF doctors, and restores when turned ON again', async () => {
        // Scenario 11: Find Doctors displays all registered doctors whose availability is ON (Doctor B, Doctor C, and existing Dr. sri)
        const listOnRes = await apiRequest(baseUrl, 'GET', '/dentists');
        assert.equal(listOnRes.status, 200);
        const docIdsOn = listOnRes.body.dentists.map((d) => d.id);
        assert.ok(docIdsOn.includes(docBDentistId), 'Doctor B (ON) must be visible in Find Doctors');
        assert.ok(docIdsOn.includes(docCDentistId), 'Doctor C (ON) must be visible in Find Doctors');

        // Scenario 12: Turning Doctor B availability OFF removes them from Find Doctors
        const toggleOffRes = await apiRequest(baseUrl, 'PATCH', `/dentists/${docBDentistId}/availability`, {
            token: docBToken,
            body: { isAvailable: false }
        });
        assert.equal(toggleOffRes.status, 200);
        assert.equal(toggleOffRes.body.isAvailable, false);

        const listAfterOff = await apiRequest(baseUrl, 'GET', '/dentists');
        assert.equal(listAfterOff.status, 200);
        const docIdsAfterOff = listAfterOff.body.dentists.map((d) => d.id);
        assert.ok(!docIdsAfterOff.includes(docBDentistId), 'Doctor B (OFF) must be hidden from Find Doctors');
        assert.ok(docIdsAfterOff.includes(docCDentistId), 'Doctor C (still ON) must remain visible in Find Doctors');

        // Existing appointment for Doctor B remains intact while Doctor B is OFF
        const patApptsWhileDocOff = await apiRequest(baseUrl, 'GET', `/appointments?patientId=${patientId}`, {
            token: patientToken
        });
        assert.ok(
            patApptsWhileDocOff.body.appointments.some((a) => a.id === bookedApptId),
            'Existing booked appointment must remain intact when doctor turns availability OFF'
        );

        // Scenario 13: Turning Doctor B availability ON makes them visible again in Find Doctors
        const toggleOnRes = await apiRequest(baseUrl, 'PATCH', `/dentists/${docBDentistId}/availability`, {
            token: docBToken,
            body: { isAvailable: true }
        });
        assert.equal(toggleOnRes.status, 200);
        assert.equal(toggleOnRes.body.isAvailable, true);

        const listAfterOn = await apiRequest(baseUrl, 'GET', '/dentists');
        assert.equal(listAfterOn.status, 200);
        const docIdsAfterOn = listAfterOn.body.dentists.map((d) => d.id);
        assert.ok(docIdsAfterOn.includes(docBDentistId), 'Doctor B (turned ON again) must be visible in Find Doctors');
    });
});
