const express = require('express');
const router = express.Router();

// Controllers
const auth = require('../controllers/authController');
const appointments = require('../controllers/appointmentController');
const clinics = require('../controllers/clinicController');
const upload = require('../controllers/uploadController');
const chat = require('../controllers/chatController');
const records = require('../controllers/recordController');
const problemRequests = require('../controllers/problemRequestController');
const verification = require('../controllers/verificationController');
const referrals = require('../controllers/referralController');
const availability = require('../controllers/availabilityController');
const specialties = require('../controllers/specialtyController');
const districts = require('../controllers/districtController');
const assignments = require('../controllers/assignmentController');
const doctorActivityCalendar = require('../controllers/doctorActivityCalendarController');
const requestsReferralsCalendar = require('../controllers/requestsReferralsCalendarController');

// Middlewares
const { authenticateJWT, optionalAuth, requireRole, requireMainAdmin, requirePermission, enforceSubAdminPermissionIfAuthenticated, requireChatAccess, enforceDistrictAccess } = require('../middleware/auth');

// ─────────────────────────────────────────────
// 1. AUTHENTICATION ENDPOINTS
// ─────────────────────────────────────────────
router.post('/auth/register', auth.register);
router.post('/auth/login', auth.login);
router.post('/auth/otp/request', auth.requestOTP);
router.post('/auth/otp/verify', auth.verifyOTP);
router.get('/auth/patient/profile', authenticateJWT, auth.getPatientProfile);
router.put('/auth/patient/profile', authenticateJWT, auth.updatePatientProfile);
router.patch('/auth/patient/profile', authenticateJWT, auth.updatePatientProfile);
router.post('/auth/forgot-password', auth.forgotPassword);
router.post('/auth/reset-password', auth.resetPassword);
router.post('/auth/refresh', auth.refreshToken);
router.get('/auth/realtime-token', authenticateJWT, auth.getRealtimeToken);
router.post('/auth/realtime-token', authenticateJWT, auth.getRealtimeToken);
router.post('/auth/supabase-sync', auth.supabaseAuthSync);
router.post('/auth/biometric', authenticateJWT, auth.saveBiometric);
router.put('/auth/fcm-token', authenticateJWT, auth.updateFcmToken);
router.post('/auth/reset-db', authenticateJWT, requireMainAdmin, auth.resetDatabase);

// ─────────────────────────────────────────────
// 2. PATIENT PROBLEM REQUESTS & ADMIN SUGGESTIONS
// ─────────────────────────────────────────────
router.post('/patient/problem-requests', optionalAuth, problemRequests.createProblemRequest);
router.get('/patient/problem-requests', optionalAuth, problemRequests.getPatientProblemRequests);
router.get('/patient/suggested-dentists', optionalAuth, problemRequests.getSuggestedDentists);
router.get('/dentist/assigned-requests', optionalAuth, problemRequests.getDentistAssignedRequests);
router.get('/dentist/problem-requests', optionalAuth, problemRequests.getDentistAssignedRequests);
router.patch('/problem-requests/:id/accept', optionalAuth, problemRequests.acceptProblemRequest);
router.post('/problem-requests/:id/accept', optionalAuth, problemRequests.acceptProblemRequest);
router.patch('/dentist/problem-requests/:id/accept', optionalAuth, problemRequests.acceptProblemRequest);

router.get('/admin/problem-requests', optionalAuth, requirePermission('ASSIGNMENT_VIEW', ['PROBLEM_VIEW']), problemRequests.getAdminProblemRequests);
router.patch('/admin/problem-requests/:id/review', optionalAuth, requirePermission('PROBLEM_UPDATE', ['ASSIGNMENT_CREATE']), problemRequests.markAdminReviewed);
router.patch('/problem-requests/:id/review', optionalAuth, requirePermission('PROBLEM_UPDATE', ['ASSIGNMENT_CREATE']), problemRequests.markAdminReviewed);
router.post('/admin/problem-requests/:id/suggest-dentist', optionalAuth, requirePermission('ASSIGNMENT_CREATE'), problemRequests.suggestDentist);
router.post('/problem-requests/:id/suggest-dentist', optionalAuth, requirePermission('ASSIGNMENT_CREATE'), problemRequests.suggestDentist);
router.patch('/problem-requests/:id/coordinator-status', optionalAuth, requirePermission('PROBLEM_UPDATE', ['ASSIGNMENT_CREATE']), problemRequests.updateCoordinatorStatus);
router.patch('/admin/problem-requests/:id/coordinator-status', optionalAuth, requirePermission('PROBLEM_UPDATE', ['ASSIGNMENT_CREATE']), problemRequests.updateCoordinatorStatus);
router.delete('/admin/problem-requests/:id', optionalAuth, requirePermission('PROBLEM_UPDATE'), problemRequests.deleteProblemRequest);
router.delete('/patient/problem-requests/:id', optionalAuth, problemRequests.deleteProblemRequest);
router.get('/admin/patients', optionalAuth, requirePermission('PATIENT_VIEW'), auth.getPatients);
router.get('/patients', optionalAuth, requirePermission('PATIENT_VIEW'), auth.getPatients);
router.get('/admin/patients/:id', optionalAuth, requirePermission('PATIENT_VIEW'), auth.getPatientById);
router.get('/patients/:id', optionalAuth, requirePermission('PATIENT_VIEW'), auth.getPatientById);
router.put('/admin/patients/:id/district', optionalAuth, requireMainAdmin, auth.updatePatientDistrictByAdmin);
router.patch('/admin/patients/:id/district', optionalAuth, requireMainAdmin, auth.updatePatientDistrictByAdmin);

// Sub-Admin Management Routes (Strictly Primary Main Admin Only)
router.post('/admin/sub-admins', optionalAuth, requireMainAdmin, auth.createSubAdmin);
router.get('/admin/sub-admins', optionalAuth, requireMainAdmin, auth.getSubAdmins);
router.put('/admin/sub-admins/:id', optionalAuth, requireMainAdmin, auth.updateSubAdmin);
router.patch('/admin/sub-admins/:id/status', optionalAuth, requireMainAdmin, auth.toggleSubAdminStatus);
router.delete('/admin/sub-admins/:id', optionalAuth, requireMainAdmin, auth.deleteSubAdmin);
router.get('/admin/sub-admins/:id/permissions', optionalAuth, requireMainAdmin, auth.getSubAdminPermissions);
router.put('/admin/sub-admins/:id/permissions', optionalAuth, requireMainAdmin, auth.updateSubAdminPermissions);
router.get('/admin/sub-admins/:id/assignment-history', optionalAuth, requireMainAdmin, auth.getSubAdminAssignmentHistory);

// ─────────────────────────────────────────────
// 2b. DISTRICT MANAGEMENT ENDPOINTS
// ─────────────────────────────────────────────
router.get('/districts', optionalAuth, districts.getDistricts);
router.get('/admin/districts', optionalAuth, requireMainAdmin, districts.getAdminDistricts);
router.post('/admin/districts', optionalAuth, requireMainAdmin, districts.createDistrict);
router.put('/admin/districts/:id', optionalAuth, requireMainAdmin, districts.updateDistrict);
router.patch('/admin/districts/:id/status', optionalAuth, requireMainAdmin, districts.toggleDistrictStatus);
router.get('/admin/sub-admins/:id/districts', optionalAuth, districts.getSubAdminDistricts);
router.post('/admin/sub-admins/:id/districts', optionalAuth, requireMainAdmin, districts.assignSubAdminDistricts);
router.delete('/admin/sub-admins/:id/districts/:districtId', optionalAuth, requireMainAdmin, districts.removeSubAdminDistrict);

// ─────────────────────────────────────────────
// 2c. PATIENT ASSIGNMENT & IMMUTABLE AUDIT TRAIL ENDPOINTS
// ─────────────────────────────────────────────
router.post('/patient-assignments', optionalAuth, requirePermission('ASSIGNMENT_CREATE', ['PATIENT_ASSIGN']), assignments.assignPatientToDoctor);
router.post('/patient-assignments/reassign', optionalAuth, requirePermission('ASSIGNMENT_CREATE', ['PATIENT_REASSIGN']), assignments.reassignPatient);
router.get('/patient-assignments/history', optionalAuth, requirePermission('ASSIGNMENT_VIEW', ['ASSIGNMENT_HISTORY_VIEW']), assignments.getAssignmentHistory);
router.get('/patient-assignments/patient/:patientId', optionalAuth, requirePermission('ASSIGNMENT_VIEW', ['PATIENT_VIEW']), assignments.getPatientTimeline);
router.get('/admin/reports/assignment-statistics', optionalAuth, requirePermission('REPORT_VIEW', ['REPORT_ASSIGNMENT_VIEW']), assignments.getAssignmentStatistics);
router.get('/admin/reports/districts', optionalAuth, requirePermission('REPORT_VIEW', ['REPORT_DISTRICT_VIEW']), assignments.getDistrictReports);

// ─────────────────────────────────────────────
// 3. ADMIN VERIFICATION ENDPOINTS
// ─────────────────────────────────────────────
router.get('/admin/dentists/verification', optionalAuth, requirePermission('DENTIST_VIEW'), verification.getDentistsForVerification);
router.patch('/admin/dentists/:id/verify', optionalAuth, requirePermission('DENTIST_EDIT', ['DENTIST_VERIFY', 'DENTIST_MANAGE']), verification.verifyDentist);
router.get('/admin/clinics/verification', optionalAuth, requirePermission('CLINIC_VIEW', ['DENTIST_VIEW']), verification.getClinicsForVerification);
router.patch('/admin/clinics/:id/verify', optionalAuth, requirePermission('CLINIC_MANAGE', ['DENTIST_EDIT', 'DENTIST_VERIFY', 'DENTIST_MANAGE']), verification.verifyClinic);

// ─────────────────────────────────────────────
// 4. APPOINTMENTS STATE MACHINE & NOTIFICATIONS ENDPOINTS
// ─────────────────────────────────────────────
router.post('/appointments', optionalAuth, appointments.bookAppointment);
router.get('/appointments', optionalAuth, appointments.getAppointments);
router.patch('/appointments/:id/accept', optionalAuth, appointments.acceptAppointment);
router.put('/appointments/:id/accept', optionalAuth, appointments.acceptAppointment);
router.post('/appointments/:id/accept', optionalAuth, appointments.acceptAppointment);
router.patch('/appointments/:id/reject', optionalAuth, appointments.rejectAppointment);
router.put('/appointments/:id/reject', optionalAuth, appointments.rejectAppointment);
router.post('/appointments/:id/reject', optionalAuth, appointments.rejectAppointment);
router.patch('/appointments/:id/reschedule', optionalAuth, appointments.rescheduleAppointment);
router.put('/appointments/:id', optionalAuth, appointments.rescheduleAppointment);
router.patch('/appointments/:id/cancel', optionalAuth, appointments.cancelAppointment);
router.delete('/appointments/:id', optionalAuth, appointments.cancelAppointment);
router.patch('/appointments/:id/complete', optionalAuth, appointments.completeConsultation);
router.patch('/appointments/:id/start', optionalAuth, appointments.startConsultation);
router.post('/appointments/:id/start', optionalAuth, appointments.startConsultation);
router.patch('/appointments/:id/delay', optionalAuth, appointments.markConsultationDelayed);
router.post('/appointments/:id/delay', optionalAuth, appointments.markConsultationDelayed);
router.patch('/appointments/:id/no-show', optionalAuth, appointments.markPatientNoShow);
router.post('/appointments/:id/no-show', optionalAuth, appointments.markPatientNoShow);
router.post('/appointments/:id/delay-response', optionalAuth, appointments.submitPatientDelayResponse);
router.patch('/appointments/:id/reschedule-request', optionalAuth, appointments.submitPatientDelayResponse);

router.get('/scheduling/rules', optionalAuth, availability.getSchedulingRules);
router.put('/scheduling/rules', optionalAuth, availability.updateSchedulingRules);
router.patch('/scheduling/rules', optionalAuth, availability.updateSchedulingRules);
router.get('/scheduling/live-status', optionalAuth, appointments.getLiveSchedulingStatus);
router.post('/appointments/locks', optionalAuth, availability.acquireSlotLock);
router.delete('/appointments/locks/:lockId', optionalAuth, availability.releaseSlotLock);
router.get('/doctor-availability/settings', optionalAuth, availability.getDoctorSchedule);
router.put('/doctor-availability/settings', optionalAuth, availability.updateDoctorSchedule);
router.patch('/doctor-availability/settings', optionalAuth, availability.updateDoctorSchedule);
router.get('/doctor-availability/released-slots', optionalAuth, availability.getReleasedSlots);
router.get('/patient/doctor-preferences', optionalAuth, availability.getPatientDoctorPreferences);
router.put('/patient/doctor-preferences', optionalAuth, availability.upsertPatientDoctorPreference);
router.post('/patient/doctor-preferences', optionalAuth, availability.upsertPatientDoctorPreference);
router.get('/visits-calendar/doctor', optionalAuth, appointments.getDoctorVisitsCalendar);
router.get('/doctor/visits-calendar', optionalAuth, appointments.getDoctorVisitsCalendar);
router.get('/visits-calendar/admin', optionalAuth, enforceSubAdminPermissionIfAuthenticated('APPOINTMENT_VIEW'), appointments.getAdminGlobalVisitsCalendar);
router.get('/admin/visits-calendar', optionalAuth, enforceSubAdminPermissionIfAuthenticated('APPOINTMENT_VIEW'), appointments.getAdminGlobalVisitsCalendar);
router.get('/admin/doctor-activity-calendar', optionalAuth, enforceSubAdminPermissionIfAuthenticated('DENTIST_VIEW', ['APPOINTMENT_VIEW']), doctorActivityCalendar.getDoctorActivityCalendar);
router.get('/doctor-activity-calendar/admin', optionalAuth, enforceSubAdminPermissionIfAuthenticated('DENTIST_VIEW', ['APPOINTMENT_VIEW']), doctorActivityCalendar.getDoctorActivityCalendar);
router.get('/admin/requests-referrals-calendar', optionalAuth, enforceSubAdminPermissionIfAuthenticated('PROBLEM_VIEW', ['ASSIGNMENT_VIEW', 'REFERRAL_VIEW']), requestsReferralsCalendar.getRequestsReferralsCalendar);
router.get('/requests-referrals-calendar/admin', optionalAuth, enforceSubAdminPermissionIfAuthenticated('PROBLEM_VIEW', ['ASSIGNMENT_VIEW', 'REFERRAL_VIEW']), requestsReferralsCalendar.getRequestsReferralsCalendar);

router.get('/notifications', optionalAuth, appointments.getNotifications);
router.put('/notifications/read-all', optionalAuth, appointments.markAllNotificationsRead);
router.patch('/notifications/read-all', optionalAuth, appointments.markAllNotificationsRead);
router.put('/notifications/:id/read', optionalAuth, appointments.markNotificationRead);
router.patch('/notifications/:id/read', optionalAuth, appointments.markNotificationRead);

// ─────────────────────────────────────────────
// 5. CLINIC & DOCTOR PROFILE ENDPOINTS
// ─────────────────────────────────────────────
router.post('/clinics', optionalAuth, clinics.registerClinicProfile);
router.get('/clinics', optionalAuth, clinics.getClinics);
router.put('/clinics/:id', optionalAuth, clinics.updateClinicDepartments);
router.patch('/clinics/:id/departments', optionalAuth, clinics.updateClinicDepartments);
router.delete('/clinics/:id', optionalAuth, requireMainAdmin, clinics.deleteClinic);
router.get('/clinics/:clinicId/dentists', optionalAuth, clinics.getClinicDentists);
router.get('/clinics/:clinicId/doctors', optionalAuth, clinics.getClinicDentists);
router.post('/clinics/:clinicId/doctors', optionalAuth, clinics.addClinicDoctor);
router.post('/clinics/:clinicId/dentists', optionalAuth, clinics.addClinicDoctor);
router.post('/clinics/:clinicId/doctors/associate', optionalAuth, clinics.associateClinicDoctor);
router.delete('/clinics/:clinicId/doctors/:doctorId', optionalAuth, clinics.removeDoctorFromClinic);
router.get('/dentists/languages', optionalAuth, clinics.getAvailableDoctorLanguages);
router.get('/doctors/languages', optionalAuth, clinics.getAvailableDoctorLanguages);
router.get('/dentists', optionalAuth, clinics.getAllDentists);
router.get('/doctors', optionalAuth, clinics.getAllDentists);
router.get('/dentists/:id', optionalAuth, clinics.getDoctorById);
router.get('/doctors/:id', optionalAuth, clinics.getDoctorById);
router.patch('/dentists/:id/availability', optionalAuth, clinics.updateDoctorAvailability);
router.put('/dentists/:id/availability', optionalAuth, clinics.updateDoctorAvailability);
router.post('/dentists/:id/availability', optionalAuth, clinics.updateDoctorAvailability);
router.patch('/doctors/:id/availability', optionalAuth, clinics.updateDoctorAvailability);
router.put('/doctors/:id/availability', optionalAuth, clinics.updateDoctorAvailability);
router.post('/doctors/:id/availability', optionalAuth, clinics.updateDoctorAvailability);
router.put('/dentists/:id/profile', optionalAuth, clinics.updateDoctorProfile);
router.patch('/dentists/:id/profile', optionalAuth, clinics.updateDoctorProfile);
router.put('/doctors/:id/profile', optionalAuth, clinics.updateDoctorProfile);
router.patch('/doctors/:id/profile', optionalAuth, clinics.updateDoctorProfile);
router.delete('/dentists/:id', optionalAuth, requireMainAdmin, clinics.deleteDentist);
router.delete('/doctors/:id', optionalAuth, requireMainAdmin, clinics.deleteDentist);
router.delete('/admin/dentists/:id', optionalAuth, requireMainAdmin, clinics.deleteDentist);
router.delete('/admin/doctors/:id', optionalAuth, requireMainAdmin, clinics.deleteDentist);

// Patient Saved Doctors (My Doctors) Endpoints
router.get('/patient/my-doctors', optionalAuth, clinics.getPatientDoctors);
router.post('/patient/my-doctors', optionalAuth, clinics.addPatientDoctor);
router.delete('/patient/my-doctors/:doctorId', optionalAuth, clinics.removePatientDoctor);
router.delete('/patient/my-doctors', optionalAuth, clinics.removePatientDoctor);

// ─────────────────────────────────────────────
// 6. SECURE CLOUD STORAGE ENDPOINTS (SUPABASE / AWS S3)
// ─────────────────────────────────────────────
router.post('/upload', authenticateJWT, upload.uploadFile);
router.get('/upload/signed-url', authenticateJWT, upload.getSignedFileUrl);

// ─────────────────────────────────────────────
// 7. CHAT MESSAGES & CONVERSATIONS ENDPOINTS (Role-Based Access & Audit Logging)
// ─────────────────────────────────────────────
router.get('/chat/conversations', optionalAuth, requireChatAccess, chat.getConversations);
router.get('/chat/messages', optionalAuth, requireChatAccess, chat.getMessages);
router.post('/chat/send', optionalAuth, requireChatAccess, chat.sendMessage);
router.post('/chat/read', optionalAuth, requireChatAccess, chat.markRoomRead);
router.patch('/chat/read', optionalAuth, requireChatAccess, chat.markRoomRead);
router.post('/chat/clear', optionalAuth, requireChatAccess, chat.clearMessages);
router.delete('/chat/clear', optionalAuth, requireChatAccess, chat.clearMessages);
router.get('/chat/audit-logs', optionalAuth, requireMainAdmin, chat.getAuditLogs);


// ─────────────────────────────────────────────
// 8. MEDICAL RECORDS & PRESCRIPTIONS ENDPOINTS
// ─────────────────────────────────────────────
router.get('/records', optionalAuth, records.getPatientRecords);
router.get('/records/shared-with-doctor', optionalAuth, records.getSharedRecordsForDoctor);
router.post('/records', optionalAuth, records.createRecord);
router.post('/records/share', optionalAuth, records.shareRecordsWithDoctor);
router.put('/records/:id', optionalAuth, records.updateRecord);
router.patch('/records/:id', optionalAuth, records.updateRecord);
router.delete('/records/:id', optionalAuth, records.deleteRecord);
router.post('/records/:id/revoke-share', optionalAuth, records.revokeRecordShare);
router.delete('/records/:id/share/:doctorId', optionalAuth, records.revokeRecordShare);
router.get('/records/:id/access', optionalAuth, records.getRecordFileAccess);

// ─────────────────────────────────────────────
// 9. REFERRAL MANAGEMENT & GROWTH ENDPOINTS
// ─────────────────────────────────────────────
router.post('/referrals', optionalAuth, referrals.createReferral);
router.get('/referrals/my-referrals', optionalAuth, referrals.getMyReferrals);
router.get('/referrals/doctor', optionalAuth, referrals.getDoctorReferrals);
router.get('/referrals/clinic', optionalAuth, referrals.getClinicReferrals);
router.get('/referrals/received', optionalAuth, referrals.getDoctorReferrals);
router.get('/referrals/for-me', optionalAuth, referrals.getReferralsForReferredPatient);
router.post('/referrals/check-patient', optionalAuth, referrals.checkPatientExists);
router.get('/referrals/all', optionalAuth, enforceSubAdminPermissionIfAuthenticated('REFERRAL_VIEW', ['ASSIGNMENT_VIEW']), referrals.getAllReferralsAdmin);
router.get('/referrals/analytics', optionalAuth, enforceSubAdminPermissionIfAuthenticated('REFERRAL_VIEW', ['REPORT_VIEW']), referrals.getAdminReferralAnalytics);
router.get('/referrals/:referralId', optionalAuth, referrals.getReferralById);
router.patch('/referrals/:referralId/accept', optionalAuth, referrals.acceptReferral);
router.patch('/referrals/:referralId/reject', optionalAuth, referrals.rejectReferral);
router.patch('/referrals/:referralId/status', optionalAuth, referrals.updateReferralStatus);
router.put('/referrals/:referralId/status', optionalAuth, referrals.updateReferralStatus);
router.delete('/referrals/:referralId', optionalAuth, referrals.deleteReferral);
router.post('/referrals/:referralId/notify-whatsapp', optionalAuth, referrals.notifyWhatsApp);

// ─────────────────────────────────────────────
// 10. DOCTOR AVAILABILITY & TIME SLOT MANAGEMENT
// ─────────────────────────────────────────────
router.get('/doctor-availability', optionalAuth, availability.getDoctorAvailability);
router.post('/doctor-availability', optionalAuth, availability.saveDoctorAvailability);
router.get('/doctor-availability/schedule', optionalAuth, availability.getDoctorSchedule);
router.put('/doctor-availability/schedule', optionalAuth, availability.updateDoctorSchedule);
router.post('/doctor-availability/schedule', optionalAuth, availability.updateDoctorSchedule);
router.post('/doctor-availability/generate-slots', optionalAuth, availability.generateSlots);
router.get('/doctor-availability/blocked-dates', optionalAuth, availability.getBlockedDates);
router.post('/doctor-availability/block-date', optionalAuth, availability.blockDoctorDate);
router.patch('/doctor-availability/block-date', optionalAuth, availability.updateBlockedDateStatus);
router.put('/doctor-availability/block-date', optionalAuth, availability.updateBlockedDateStatus);
router.delete('/doctor-availability/block-date', optionalAuth, availability.unblockDoctorDate);
router.post('/doctor-availability/block-slot', optionalAuth, availability.blockTimeSlot);
router.delete('/doctor-availability/block-slot', optionalAuth, availability.unblockTimeSlot);
router.delete('/doctor-availability', optionalAuth, availability.deleteDoctorAvailability);

// ─────────────────────────────────────────────
// 11. MEDICAL SPECIALTIES & MULTI-SPECIALTY REPORTING
// ─────────────────────────────────────────────
router.get('/specialties', optionalAuth, specialties.getSpecialties);
router.get('/specialties/clinical-config', optionalAuth, specialties.getSpecialtyClinicalConfigEndpoint);
router.post('/triage/analyze', optionalAuth, specialties.analyzeAiTriage);
router.get('/admin/specialties', optionalAuth, requirePermission('DENTIST_VIEW', ['PATIENT_VIEW', 'ASSIGNMENT_VIEW']), specialties.getSpecialties);
router.post('/specialties', optionalAuth, requireMainAdmin, specialties.createSpecialty);
router.post('/admin/specialties', optionalAuth, requireMainAdmin, specialties.createSpecialty);
router.put('/specialties/:id', optionalAuth, requireMainAdmin, specialties.updateSpecialty);
router.patch('/specialties/:id', optionalAuth, requireMainAdmin, specialties.updateSpecialty);
router.put('/admin/specialties/:id', optionalAuth, requireMainAdmin, specialties.updateSpecialty);
router.patch('/admin/specialties/:id', optionalAuth, requireMainAdmin, specialties.updateSpecialty);
router.patch('/specialties/:id/status', optionalAuth, requireMainAdmin, specialties.toggleSpecialtyStatus);
router.patch('/admin/specialties/:id/status', optionalAuth, requireMainAdmin, specialties.toggleSpecialtyStatus);
router.delete('/specialties/:id', optionalAuth, requireMainAdmin, specialties.deleteSpecialty);
router.delete('/admin/specialties/:id', optionalAuth, requireMainAdmin, specialties.deleteSpecialty);
router.get('/admin/reports/specialties', optionalAuth, requireMainAdmin, specialties.getSpecialtyAnalyticsReport);

module.exports = router;


