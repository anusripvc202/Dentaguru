const express = require('express');
const router = express.Router();

// Controllers
const auth = require('../controllers/authController');
const appointments = require('../controllers/appointmentController');
const clinics = require('../controllers/clinicController');
const upload = require('../controllers/uploadController');
const chat = require('../controllers/chatController');
const records = require('../controllers/recordController');

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
// 2. APPOINTMENTS ENDPOINTS
// ─────────────────────────────────────────────
router.post('/appointments', appointments.bookAppointment);
router.get('/appointments', appointments.getAppointments);
router.put('/appointments/:id', appointments.rescheduleAppointment);
router.delete('/appointments/:id', appointments.cancelAppointment);

// ─────────────────────────────────────────────
// 3. CLINIC PROFILE ENDPOINTS
// ─────────────────────────────────────────────
router.post('/clinics', clinics.registerClinicProfile);
router.get('/clinics', clinics.getClinics);
router.get('/clinics/:clinicId/dentists', clinics.getClinicDentists);
router.get('/dentists', clinics.getAllDentists);

// ─────────────────────────────────────────────
// 4. SECURE CLOUD STORAGE ENDPOINTS (AWS S3)
// ─────────────────────────────────────────────
// POST /api/v1/upload          — Upload file (multipart/form-data, field: "file", optional: "folder")
// GET  /api/v1/upload/signed-url?key=<s3-key> — Get 15-min pre-signed access URL
router.post('/upload', authenticateJWT, upload.uploadFile);
// ─────────────────────────────────────────────
// 5. CHAT MESSAGES ENDPOINTS (Supabase)
// ─────────────────────────────────────────────
router.post('/chat/send', chat.sendMessage);
router.get('/chat/messages', chat.getMessages);
router.post('/chat/clear', chat.clearMessages);
router.delete('/chat/clear', chat.clearMessages);

// ─────────────────────────────────────────────
// 6. MEDICAL RECORDS & PRESCRIPTIONS ENDPOINTS
// ─────────────────────────────────────────────
router.get('/records', records.getPatientRecords);
router.post('/records', records.createRecord);

module.exports = router;
