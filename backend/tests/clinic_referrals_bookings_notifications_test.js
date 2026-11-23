// End-to-End Backend Verification: Clinic Referrals, Bookings & Notifications
// Validates strict multi-clinic isolation, clinic_id resolution, doctor & clinic notifications,
// read persistence, and non-simulated WhatsApp/SMS reporting without mutating live production rows.

const assert = require('assert');
const http = require('http');

const Schemas = require('../src/models/Schemas');
const clinicController = require('../src/controllers/clinicController');
const appointmentController = require('../src/controllers/appointmentController');
const referralController = require('../src/controllers/referralController');
const whatsappService = require('../src/services/whatsappService');
const app = require('../src/app');

(async () => {
    console.log('--- STARTING CLINIC REFERRALS, BOOKINGS & NOTIFICATIONS BACKEND TESTS ---');

    const clinicA = {
        id: '11111111-1111-4111-8111-111111111111',
        user_id: 'aaaa1111-1111-4111-8111-111111111111',
        clinic_name: 'Apollo Heart Care Clinic',
        location: 'Hyderabad',
        phone: '9876500001'
    };
    const clinicB = {
        id: '22222222-2222-4222-8222-222222222222',
        user_id: 'bbbb2222-2222-4222-8222-222222222222',
        clinic_name: 'City Skin Clinic',
        location: 'Secunderabad',
        phone: '9876500002'
    };
    const docClinicA = {
        id: '33333333-3333-4333-8333-333333333333',
        user_id: 'cccc3333-3333-4333-8333-333333333333',
        clinic_id: clinicA.id,
        name: 'Dr. Arjun Rao',
        speciality: 'Cardiology',
        specialty: 'Cardiology',
        availability_status: 'Available',
        phone: '9876500011',
        users: { id: 'cccc3333-3333-4333-8333-333333333333', name: 'Dr. Arjun Rao', phone: '9876500011', email: 'arjun@clinicA.test' },
        clinics: { id: clinicA.id, clinic_name: clinicA.clinic_name, location: clinicA.location }
    };
    const docIndependent = {
        id: '44444444-4444-4444-8444-444444444444',
        user_id: 'dddd4444-4444-4444-8444-444444444444',
        clinic_id: null,
        name: 'Dr. Solo Care',
        speciality: 'General Medicine',
        specialty: 'General Medicine',
        availability_status: 'Available',
        phone: '9876500022',
        users: { id: 'dddd4444-4444-4444-8444-444444444444', name: 'Dr. Solo Care', phone: '9876500022', email: 'solo@indep.test' },
        clinics: {}
    };
    const patientUser = {
        id: '55555555-5555-4555-8555-555555555555',
        name: 'Anu',
        phone: '9063663180',
        email: 'anu@patient.test',
        role: 'Patient',
        city: 'Hyderabad',
        pincode: '500081'
    };
    const clinicAUser = {
        id: clinicA.user_id,
        name: clinicA.clinic_name,
        phone: clinicA.phone,
        email: 'admin@clinica.test',
        role: 'Clinic'
    };

    const dbClinics = [clinicA, clinicB];
    const dbDoctors = [docClinicA, docIndependent];
    const dbUsers = [patientUser, clinicAUser, docClinicA.users, docIndependent.users];
    const dbAppointments = [];
    const dbReferrals = [];
    const dbNotifications = [];

    // Save originals to restore cleanly
    const orig = {
        ClinicFindById: Schemas.Clinic.findById,
        ClinicFindOne: Schemas.Clinic.findOne,
        DentistFind: Schemas.Dentist.find,
        DentistFindById: Schemas.Dentist.findById,
        DentistFindOne: Schemas.Dentist.findOne,
        UserFindById: Schemas.User.findById,
        UserFindOne: Schemas.User.findOne,
        UserCreate: Schemas.User.create,
        ApptCreate: Schemas.Appointment.create,
        ApptFind: Schemas.Appointment.find,
        ApptFindById: Schemas.Appointment.findById,
        RefCreate: Schemas.Referral.create,
        RefFind: Schemas.Referral.find,
        RefFindById: Schemas.Referral.findById,
        RefCheckDup: Schemas.Referral.checkDuplicate,
        RefUpdateStatusForRefUser: Schemas.Referral.updateStatusForReferredUser,
        RefUpdate: Schemas.Referral.findByIdAndUpdate,
        NotifCreate: Schemas.Notification.create,
        NotifFindForUser: Schemas.Notification.findForUser,
        NotifMarkRead: Schemas.Notification.markAsRead,
        NotifMarkAll: Schemas.Notification.markAllAsReadForUser,
        ResolveClinicIds: clinicController.resolveClinicRecordAndDoctorIds,
    };

    try {
        Schemas.Clinic.findById = async (id) => dbClinics.find(c => c.id === id) || null;
        Schemas.Clinic.findOne = async (q) => {
            if (q.user_id) return dbClinics.find(c => c.user_id === q.user_id) || null;
            if (q.clinic_name) return dbClinics.find(c => c.clinic_name.toLowerCase() === String(q.clinic_name).toLowerCase()) || null;
            return null;
        };
        Schemas.Dentist.find = async (q = {}) => {
            if (q.clinic_id) return dbDoctors.filter(d => d.clinic_id === q.clinic_id);
            return dbDoctors;
        };
        Schemas.Dentist.findById = async (id) => dbDoctors.find(d => d.id === id || d.user_id === id) || null;
        Schemas.Dentist.findOne = async (q) => dbDoctors.find(d => (q.user_id && d.user_id === q.user_id) || (q.id && d.id === q.id)) || null;
        Schemas.User.findById = async (id) => dbUsers.find(u => u.id === id) || null;
        Schemas.User.findOne = async (q) => dbUsers.find(u => (q.phone && u.phone === q.phone) || (q.email && u.email === q.email)) || null;
        Schemas.User.create = async (u) => {
            const rec = { id: `pat-${Date.now()}`, ...u };
            dbUsers.push(rec);
            return rec;
        };

        // Note: clinicController imported Schemas directly, and Schemas.resolveClinicIds reads supabase.
        // We patch Schemas.resolveClinicIds by mutating exported method where supported OR stubbing getClinicReferrals helper:
        Schemas.Notification.create = async (n) => {
            const rec = {
                id: `notif-${dbNotifications.length + 1}`,
                recipient_role: n.recipient_role,
                recipient_id: String(n.recipient_id),
                referral_id: n.referral_id || null,
                title: n.title,
                message: n.message,
                type: n.type || 'general',
                read: false,
                created_at: new Date().toISOString()
            };
            dbNotifications.unshift(rec);
            return rec;
        };
        Schemas.Notification.findForUser = async ({ role, userId }) => {
            const normRole = String(role || '').toLowerCase();
            const c = dbClinics.find(cl => cl.id === userId || cl.user_id === userId || cl.clinic_name.toLowerCase() === String(userId || '').toLowerCase());
            const ids = new Set([String(userId || '')]);
            if (c) {
                ids.add(c.id);
                ids.add(c.user_id);
                ids.add(c.clinic_name);
            }
            const d = dbDoctors.find(doc => doc.id === userId || doc.user_id === userId);
            if (d) {
                ids.add(d.id);
                ids.add(d.user_id);
            }
            return dbNotifications.filter(n => {
                const nr = n.recipient_role.toLowerCase();
                if (normRole === 'clinic') return nr === 'clinic' && ids.has(n.recipient_id);
                if (normRole === 'dentist' || normRole === 'doctor') return (nr === 'dentist' || nr === 'doctor') && ids.has(n.recipient_id);
                return ids.has(n.recipient_id);
            });
        };
        Schemas.Notification.markAsRead = async (id) => {
            const found = dbNotifications.find(n => n.id === id);
            if (found) found.read = true;
            return found;
        };

        Schemas.Referral.checkDuplicate = async () => null;
        Schemas.Referral.updateStatusForReferredUser = async () => null;
        Schemas.Referral.create = async (data) => {
            const rec = {
                id: `ref-${dbReferrals.length + 1}`,
                ...data,
                created_at: new Date().toISOString(),
                updated_at: new Date().toISOString()
            };
            dbReferrals.unshift(rec);
            return rec;
        };
        Schemas.Referral.find = async () => dbReferrals;
        Schemas.Referral.findById = async (id) => dbReferrals.find(r => r.id === id) || null;
        Schemas.Referral.findByIdAndUpdate = async (id, upd) => {
            const found = dbReferrals.find(r => r.id === id);
            if (found) Object.assign(found, upd);
            return found;
        };

        Schemas.Appointment.create = async (data) => {
            const rec = {
                id: `appt-${dbAppointments.length + 1}`,
                ...data,
                created_at: new Date().toISOString()
            };
            dbAppointments.unshift(rec);
            return rec;
        };
        Schemas.Appointment.find = async (q = {}) => {
            return dbAppointments.filter(a => {
                const qClinicId = q.clinic_id || q.clinicId;
                if (qClinicId) {
                    const clinicDocIds = new Set(q.clinic_dentist_ids || []);
                    if (a.clinic_id === qClinicId) return true;
                    if (a.dentist_id && clinicDocIds.has(a.dentist_id)) return true;
                    return false;
                }
                if (q.dentistId || q.dentist_id) {
                    const target = q.dentistId || q.dentist_id;
                    const arr = target.$in || [target];
                    return arr.includes(a.dentist_id);
                }
                return true;
            });
        };
        Schemas.Appointment.findById = async (id) => {
            const a = dbAppointments.find(x => x.id === id);
            if (!a) return null;
            const d = dbDoctors.find(doc => doc.id === a.dentist_id);
            const c = dbClinics.find(cl => cl.id === a.clinic_id);
            const p = dbUsers.find(u => u.id === a.patient_id);
            return { ...a, patient: p, dentist: d, clinic: c };
        };

        // Disable Twilio/Meta env vars for honest non-simulated alert test
        const prevTwilioSid = process.env.TWILIO_ACCOUNT_SID;
        const prevMetaToken = process.env.WHATSAPP_API_TOKEN;
        delete process.env.TWILIO_ACCOUNT_SID;
        delete process.env.WHATSAPP_API_TOKEN;

        try {
            // Test 5: External WhatsApp/SMS must NOT simulate sent when unconfigured
            assert.strictEqual(whatsappService.isWhatsAppProviderConfigured(), false);
            const honestRes = await whatsappService.sendClinicBookingAlert({
                clinicPhone: clinicA.phone,
                clinicName: clinicA.clinic_name,
                doctorName: docClinicA.name,
                patientName: 'Anu',
                appointmentDate: '2026-12-01',
                appointmentTime: '10:00 AM',
                bookingId: 'b-test-1'
            });
            assert.strictEqual(honestRes.providerConfigured, false);
            assert.strictEqual(honestRes.success, false);
            assert.strictEqual(honestRes.whatsappStatus, 'NotConfigured');
            console.log('✓ SUCCESS: Unconfigured SMS/WhatsApp reports NotConfigured honestly (no fake delivery).');

            // Test 1: Patient refers Clinic A doctor -> saves clinic_id + notifies Clinic A & Doctor A (NOT Clinic B)
            let refResPayload = null;
            await referralController.createReferral(
                {
                    headers: { 'x-user-id': patientUser.id },
                    body: {
                        referrerPatientId: patientUser.id,
                        referredPatientName: 'Satya Friend',
                        referredPatientMobile: '9988776611',
                        referredPatientAge: '32',
                        referredPatientGender: 'Female',
                        referredPatientCity: 'Hyderabad',
                        referredPatientPincode: '500081',
                        referredPatientLocation: 'Madhapur',
                        requiredSpecialist: 'Cardiology',
                        clinicalComplaint: 'Chest palpitations review',
                        doctorId: docClinicA.id
                    }
                },
                {
                    status: () => ({ json: (d) => { refResPayload = d; return d; } })
                }
            );
            assert.strictEqual(refResPayload.success, true);
            assert.strictEqual(refResPayload.referral.clinicId, clinicA.id);
            assert.strictEqual(dbReferrals.length, 1);
            assert.strictEqual(dbAppointments.length, 0, 'Creating referral must NOT auto-create a confirmed appointment');

            const clinicANotifsAfterRef = await Schemas.Notification.findForUser({ role: 'Clinic', userId: clinicA.user_id });
            const docANotifsAfterRef = await Schemas.Notification.findForUser({ role: 'Dentist', userId: docClinicA.user_id });
            const clinicBNotifsAfterRef = await Schemas.Notification.findForUser({ role: 'Clinic', userId: clinicB.id });
            assert.strictEqual(clinicANotifsAfterRef.length, 1, 'Clinic A must receive referral notification');
            assert.strictEqual(docANotifsAfterRef.length, 1, 'Doctor A must receive referral notification');
            assert.strictEqual(clinicBNotifsAfterRef.length, 0, 'Clinic B must NOT receive Clinic A referral notification');
            console.log('✓ SUCCESS: Test 1 — Patient referral persisted to Clinic A, notified Clinic A & Doctor A with Clinic B isolated.');

            // Test 2 & 3: Patient books appointment with Clinic A doctor -> Clinic A sees it & gets notified; Clinic B & independent doctor stay isolated
            let bookResPayload = null;
            const futureDate = new Date(Date.now() + 86400000 * 3).toISOString().split('T')[0];
            await appointmentController.bookAppointment(
                {
                    user: { id: patientUser.id, role: 'Patient' },
                    body: {
                        patientId: patientUser.id,
                        dentistId: docClinicA.id,
                        date: futureDate,
                        timeSlot: '10:30 AM',
                        treatment: 'Cardiology Consultation'
                    }
                },
                {
                    status: () => ({ json: (d) => { bookResPayload = d; return d; } }),
                    json: (d) => { bookResPayload = d; return d; }
                }
            );
            assert.strictEqual(bookResPayload.success, true);
            assert.strictEqual(bookResPayload.appointment.clinic_id, clinicA.id);

            // Book independent doctor -> must NOT generate any Clinic notification
            let indepBookRes = null;
            await appointmentController.bookAppointment(
                {
                    user: { id: patientUser.id, role: 'Patient' },
                    body: {
                        patientId: patientUser.id,
                        dentistId: docIndependent.id,
                        date: futureDate,
                        timeSlot: '11:30 AM',
                        treatment: 'General Medicine'
                    }
                },
                {
                    status: () => ({ json: (d) => { indepBookRes = d; return d; } }),
                    json: (d) => { indepBookRes = d; return d; }
                }
            );
            assert.strictEqual(indepBookRes.success, true);
            assert.strictEqual(indepBookRes.appointment.clinic_id, null);

            // Query bookings for Clinic A (via clinics.id and clinics.user_id) and Clinic B
            const clinicABookings = await Schemas.Appointment.find({ clinicId: clinicA.id, clinic_dentist_ids: [docClinicA.id] });
            const clinicBBookings = await Schemas.Appointment.find({ clinicId: clinicB.id, clinic_dentist_ids: [] });
            assert.strictEqual(clinicABookings.length, 1, 'Clinic A must see 1 booking');
            assert.strictEqual(clinicBBookings.length, 0, 'Clinic B must see 0 Clinic A bookings');

            const clinicANotifsAll = await Schemas.Notification.findForUser({ role: 'Clinic', userId: clinicA.id });
            const docANotifsAll = await Schemas.Notification.findForUser({ role: 'Dentist', userId: docClinicA.id });
            assert.strictEqual(clinicANotifsAll.length, 2, 'Clinic A has 1 referral + 1 booking notification');
            assert.strictEqual(docANotifsAll.length, 2, 'Doctor A has 1 referral + 1 booking notification');
            assert.strictEqual((await Schemas.Notification.findForUser({ role: 'Clinic', userId: clinicB.id })).length, 0);
            console.log('✓ SUCCESS: Test 2 & 3 — Clinic A booking persisted & scoped strictly; independent doctor skipped clinic alert.');

            // Test 4: Mark notification read persists across subsequent queries
            const notifToRead = clinicANotifsAll[0];
            assert.strictEqual(notifToRead.read, false);
            await Schemas.Notification.markAsRead(notifToRead.id);
            const reloadedNotifs = await Schemas.Notification.findForUser({ role: 'Clinic', userId: clinicA.user_id });
            assert.strictEqual(reloadedNotifs.filter(n => !n.read).length, 1);
            console.log('✓ SUCCESS: Test 4 — Persistent notification read status & unread count verified.');

            // HTTP Express endpoint smoke check: GET /api/v1/referrals/clinic route exists before :referralId
            const server = http.createServer(app);
            await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
            const { port } = server.address();
            try {
                const routeCheck = await new Promise((resolve, reject) => {
                    const req = http.request({
                        hostname: '127.0.0.1',
                        port,
                        path: '/api/v1/referrals/clinic',
                        method: 'GET'
                    }, (res) => {
                        let body = '';
                        res.on('data', c => body += c);
                        res.on('end', () => resolve({ statusCode: res.statusCode, body }));
                    });
                    req.on('error', reject);
                    req.end();
                });
                // Without clinicId param, getClinicReferrals returns 400 (proving it routed to getClinicReferrals, NOT getReferralById 404!)
                assert.strictEqual(routeCheck.statusCode, 400, `Expected 400 from getClinicReferrals without clinicId, got ${routeCheck.statusCode}: ${routeCheck.body}`);
                console.log('✓ SUCCESS: GET /api/v1/referrals/clinic route mounted cleanly ahead of :referralId.');
            } finally {
                await new Promise(resolve => server.close(resolve));
            }
        } finally {
            if (prevTwilioSid !== undefined) process.env.TWILIO_ACCOUNT_SID = prevTwilioSid;
            if (prevMetaToken !== undefined) process.env.WHATSAPP_API_TOKEN = prevMetaToken;
        }
    } finally {
        Schemas.Clinic.findById = orig.ClinicFindById;
        Schemas.Clinic.findOne = orig.ClinicFindOne;
        Schemas.Dentist.find = orig.DentistFind;
        Schemas.Dentist.findById = orig.DentistFindById;
        Schemas.Dentist.findOne = orig.DentistFindOne;
        Schemas.User.findById = orig.UserFindById;
        Schemas.User.findOne = orig.UserFindOne;
        Schemas.User.create = orig.UserCreate;
        Schemas.Appointment.create = orig.ApptCreate;
        Schemas.Appointment.find = orig.ApptFind;
        Schemas.Appointment.findById = orig.ApptFindById;
        Schemas.Referral.create = orig.RefCreate;
        Schemas.Referral.find = orig.RefFind;
        Schemas.Referral.findById = orig.RefFindById;
        Schemas.Referral.checkDuplicate = orig.RefCheckDup;
        Schemas.Referral.updateStatusForReferredUser = orig.RefUpdateStatusForRefUser;
        Schemas.Referral.findByIdAndUpdate = orig.RefUpdate;
        Schemas.Notification.create = orig.NotifCreate;
        Schemas.Notification.findForUser = orig.NotifFindForUser;
        Schemas.Notification.markAsRead = orig.NotifMarkRead;
        Schemas.Notification.markAllAsReadForUser = orig.NotifMarkAll;
    }

    console.log('--- ALL CLINIC REFERRAL, BOOKING & NOTIFICATION TESTS PASSED ---');
    process.exit(0);
})();
