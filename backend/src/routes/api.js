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

// Middlewares
const { authenticateJWT, optionalAuth, requireRole } = require('../middleware/auth');

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

router.get('/admin/problem-requests', optionalAuth, problemRequests.getAdminProblemRequests);
router.patch('/admin/problem-requests/:id/review', optionalAuth, problemRequests.markAdminReviewed);
router.patch('/problem-requests/:id/review', optionalAuth, problemRequests.markAdminReviewed);
router.post('/admin/problem-requests/:id/suggest-dentist', optionalAuth, problemRequests.suggestDentist);
router.post('/problem-requests/:id/suggest-dentist', optionalAuth, problemRequests.suggestDentist);
router.delete('/admin/problem-requests/:id', optionalAuth, problemRequests.deleteProblemRequest);
router.delete('/patient/problem-requests/:id', optionalAuth, problemRequests.deleteProblemRequest);
router.get('/admin/patients', optionalAuth, auth.getPatients);
router.get('/patients', optionalAuth, auth.getPatients);

// Sub-Admin Management Routes
router.post('/admin/sub-admins', optionalAuth, auth.createSubAdmin);
router.get('/admin/sub-admins', optionalAuth, auth.getSubAdmins);
router.delete('/admin/sub-admins/:id', optionalAuth, auth.deleteSubAdmin);

// ─────────────────────────────────────────────
// 3. ADMIN VERIFICATION ENDPOINTS
// ─────────────────────────────────────────────
router.get('/admin/dentists/verification', optionalAuth, verification.getDentistsForVerification);
router.patch('/admin/dentists/:id/verify', optionalAuth, verification.verifyDentist);
router.get('/admin/clinics/verification', optionalAuth, verification.getClinicsForVerification);
router.patch('/admin/clinics/:id/verify', optionalAuth, verification.verifyClinic);

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

// ─────────────────────────────────────────────
// 6. SECURE CLOUD STORAGE ENDPOINTS (AWS S3)
// ─────────────────────────────────────────────
router.post('/upload', authenticateJWT, upload.uploadFile);

// ─────────────────────────────────────────────
// 7. CHAT MESSAGES ENDPOINTS (Supabase)
// ─────────────────────────────────────────────
router.post('/chat/send', optionalAuth, chat.sendMessage);
router.get('/chat/messages', optionalAuth, chat.getMessages);
router.post('/chat/clear', optionalAuth, chat.clearMessages);
router.delete('/chat/clear', optionalAuth, chat.clearMessages);

// ─────────────────────────────────────────────
// 8. MEDICAL RECORDS & PRESCRIPTIONS ENDPOINTS
// ─────────────────────────────────────────────
router.get('/records', optionalAuth, records.getPatientRecords);
router.post('/records', optionalAuth, records.createRecord);

module.exports = router;

