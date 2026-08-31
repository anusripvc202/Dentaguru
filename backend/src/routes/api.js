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

// Middlewares
const { authenticateJWT, optionalAuth, requireRole, requireMainAdmin, requirePermission, requireChatAccess } = require('../middleware/auth');

// ─────────────────────────────────────────────
// 1. AUTHENTICATION ENDPOINTS
// ─────────────────────────────────────────────
router.post('/auth/register', auth.register);
router.post('/auth/login', auth.login);
router.post('/auth/otp/request', auth.requestOTP);
router.post('/auth/otp/verify', auth.verifyOTP);
router.post('/auth/forgot-password', auth.forgotPassword);
router.post('/auth/reset-password', auth.resetPassword);
router.post('/auth/refresh', auth.refreshToken);
router.post('/auth/supabase-sync', auth.supabaseAuthSync);
router.post('/auth/biometric', authenticateJWT, auth.saveBiometric);
router.put('/auth/fcm-token', authenticateJWT, auth.updateFcmToken);
router.post('/auth/reset-db', auth.resetDatabase);

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
router.delete('/admin/problem-requests/:id', optionalAuth, requirePermission('PROBLEM_UPDATE'), problemRequests.deleteProblemRequest);
router.delete('/patient/problem-requests/:id', optionalAuth, problemRequests.deleteProblemRequest);
router.get('/admin/patients', optionalAuth, requirePermission('PATIENT_VIEW'), auth.getPatients);
router.get('/patients', optionalAuth, auth.getPatients);

// Sub-Admin Management Routes (Strictly Primary Main Admin Only)
router.post('/admin/sub-admins', optionalAuth, requireMainAdmin, auth.createSubAdmin);
router.get('/admin/sub-admins', optionalAuth, requireMainAdmin, auth.getSubAdmins);
router.put('/admin/sub-admins/:id', optionalAuth, requireMainAdmin, auth.updateSubAdmin);
router.patch('/admin/sub-admins/:id/status', optionalAuth, requireMainAdmin, auth.toggleSubAdminStatus);
router.delete('/admin/sub-admins/:id', optionalAuth, requireMainAdmin, auth.deleteSubAdmin);

// ─────────────────────────────────────────────
// 3. ADMIN VERIFICATION ENDPOINTS
// ─────────────────────────────────────────────
router.get('/admin/dentists/verification', optionalAuth, requirePermission('DENTIST_VIEW'), verification.getDentistsForVerification);
router.patch('/admin/dentists/:id/verify', optionalAuth, requirePermission('DENTIST_EDIT'), verification.verifyDentist);
router.get('/admin/clinics/verification', optionalAuth, requirePermission('DENTIST_VIEW'), verification.getClinicsForVerification);
router.patch('/admin/clinics/:id/verify', optionalAuth, requirePermission('DENTIST_EDIT'), verification.verifyClinic);

// ─────────────────────────────────────────────
// 4. APPOINTMENTS STATE MACHINE ENDPOINTS
// ─────────────────────────────────────────────
router.post('/appointments', optionalAuth, appointments.bookAppointment);
router.get('/appointments', optionalAuth, appointments.getAppointments);
router.patch('/appointments/:id/accept', optionalAuth, appointments.acceptAppointment);
router.patch('/appointments/:id/reject', optionalAuth, appointments.rejectAppointment);
router.patch('/appointments/:id/reschedule', optionalAuth, appointments.rescheduleAppointment);
router.put('/appointments/:id', optionalAuth, appointments.rescheduleAppointment);
router.patch('/appointments/:id/cancel', optionalAuth, appointments.cancelAppointment);
router.delete('/appointments/:id', optionalAuth, appointments.cancelAppointment);
router.patch('/appointments/:id/complete', optionalAuth, appointments.completeConsultation);

// ─────────────────────────────────────────────
// 5. CLINIC PROFILE ENDPOINTS
// ─────────────────────────────────────────────
router.post('/clinics', optionalAuth, clinics.registerClinicProfile);
router.get('/clinics', optionalAuth, clinics.getClinics);
router.get('/clinics/:clinicId/dentists', optionalAuth, clinics.getClinicDentists);
router.get('/dentists', optionalAuth, clinics.getAllDentists);

// Patient Saved Doctors (My Doctors) Endpoints
router.get('/patient/my-doctors', optionalAuth, clinics.getPatientDoctors);
router.post('/patient/my-doctors', optionalAuth, clinics.addPatientDoctor);
router.delete('/patient/my-doctors/:doctorId', optionalAuth, clinics.removePatientDoctor);
router.delete('/patient/my-doctors', optionalAuth, clinics.removePatientDoctor);

// ─────────────────────────────────────────────
// 6. SECURE CLOUD STORAGE ENDPOINTS (AWS S3)
// ─────────────────────────────────────────────
router.post('/upload', authenticateJWT, upload.uploadFile);

// ─────────────────────────────────────────────
// 7. CHAT MESSAGES & CONVERSATIONS ENDPOINTS (Role-Based Access & Audit Logging)
// ─────────────────────────────────────────────
router.get('/chat/conversations', optionalAuth, requireChatAccess, chat.getConversations);
router.get('/chat/messages', optionalAuth, requireChatAccess, chat.getMessages);
router.post('/chat/send', optionalAuth, requireChatAccess, chat.sendMessage);
router.post('/chat/clear', optionalAuth, requireChatAccess, chat.clearMessages);
router.delete('/chat/clear', optionalAuth, requireChatAccess, chat.clearMessages);
router.get('/chat/audit-logs', optionalAuth, requireMainAdmin, chat.getAuditLogs);


// ─────────────────────────────────────────────
// 8. MEDICAL RECORDS & PRESCRIPTIONS ENDPOINTS
// ─────────────────────────────────────────────
router.get('/records', optionalAuth, records.getPatientRecords);
router.post('/records', optionalAuth, records.createRecord);

// ─────────────────────────────────────────────
// 9. REFERRAL MANAGEMENT & GROWTH ENDPOINTS
// ─────────────────────────────────────────────
router.post('/referrals', optionalAuth, referrals.createReferral);
router.get('/referrals/my-referrals', optionalAuth, referrals.getMyReferrals);
router.get('/referrals/doctor', optionalAuth, referrals.getDoctorReferrals);
router.get('/referrals/received', optionalAuth, referrals.getDoctorReferrals);
router.get('/referrals/for-me', optionalAuth, referrals.getReferralsForReferredPatient);
router.post('/referrals/check-patient', optionalAuth, referrals.checkPatientExists);
router.get('/referrals/all', optionalAuth, referrals.getAllReferralsAdmin);
router.get('/referrals/analytics', optionalAuth, referrals.getAdminReferralAnalytics);
router.get('/referrals/:referralId', optionalAuth, referrals.getReferralById);
router.patch('/referrals/:referralId/accept', optionalAuth, referrals.acceptReferral);
router.patch('/referrals/:referralId/reject', optionalAuth, referrals.rejectReferral);
router.post('/referrals/:referralId/notify-whatsapp', optionalAuth, referrals.notifyWhatsApp);

module.exports = router;


