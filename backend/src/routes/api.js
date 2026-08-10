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
const { authenticateJWT, requireRole } = require('../middleware/auth');

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
router.post('/patient/problem-requests', problemRequests.createProblemRequest);
router.get('/patient/problem-requests', problemRequests.getPatientProblemRequests);
router.get('/patient/suggested-dentists', problemRequests.getSuggestedDentists);

router.get('/admin/problem-requests', problemRequests.getAdminProblemRequests);
router.post('/admin/problem-requests/:id/suggest-dentist', problemRequests.suggestDentist);

// ─────────────────────────────────────────────
// 3. ADMIN VERIFICATION ENDPOINTS
// ─────────────────────────────────────────────
router.get('/admin/dentists/verification', verification.getDentistsForVerification);
router.patch('/admin/dentists/:id/verify', verification.verifyDentist);
router.get('/admin/clinics/verification', verification.getClinicsForVerification);
router.patch('/admin/clinics/:id/verify', verification.verifyClinic);

// ─────────────────────────────────────────────
// 4. APPOINTMENTS STATE MACHINE ENDPOINTS
// ─────────────────────────────────────────────
router.post('/appointments', appointments.bookAppointment);
router.get('/appointments', appointments.getAppointments);
router.patch('/appointments/:id/accept', appointments.acceptAppointment);
router.patch('/appointments/:id/reject', appointments.rejectAppointment);
router.patch('/appointments/:id/reschedule', appointments.rescheduleAppointment);
router.put('/appointments/:id', appointments.rescheduleAppointment);
router.patch('/appointments/:id/cancel', appointments.cancelAppointment);
router.delete('/appointments/:id', appointments.cancelAppointment);
router.patch('/appointments/:id/complete', appointments.completeConsultation);

// ─────────────────────────────────────────────
// 5. CLINIC PROFILE ENDPOINTS
// ─────────────────────────────────────────────
router.post('/clinics', clinics.registerClinicProfile);
router.get('/clinics', clinics.getClinics);
router.get('/clinics/:clinicId/dentists', clinics.getClinicDentists);
router.get('/dentists', clinics.getAllDentists);

// ─────────────────────────────────────────────
// 6. SECURE CLOUD STORAGE ENDPOINTS (AWS S3)
// ─────────────────────────────────────────────
router.post('/upload', authenticateJWT, upload.uploadFile);

// ─────────────────────────────────────────────
// 7. CHAT MESSAGES ENDPOINTS (Supabase)
// ─────────────────────────────────────────────
router.post('/chat/send', chat.sendMessage);
router.get('/chat/messages', chat.getMessages);
router.post('/chat/clear', chat.clearMessages);
router.delete('/chat/clear', chat.clearMessages);

// ─────────────────────────────────────────────
// 8. MEDICAL RECORDS & PRESCRIPTIONS ENDPOINTS
// ─────────────────────────────────────────────
router.get('/records', records.getPatientRecords);
router.post('/records', records.createRecord);

module.exports = router;

