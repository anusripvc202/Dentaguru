const express = require('express');
const router = express.Router();

// Controllers
const auth = require('../controllers/authController');
const appointments = require('../controllers/appointmentController');
const clinics = require('../controllers/clinicController');
const upload = require('../controllers/uploadController');

// Middlewares
const { authenticateJWT, requireRole } = require('../middleware/auth');

// ─────────────────────────────────────────────
// 1. AUTHENTICATION ENDPOINTS
// ─────────────────────────────────────────────
router.post('/auth/register', auth.register);
router.post('/auth/login', auth.login);
router.post('/auth/otp/request', auth.requestOTP);
router.post('/auth/otp/verify', auth.verifyOTP);
router.post('/auth/refresh', auth.refreshToken);
router.post('/auth/biometric', authenticateJWT, auth.saveBiometric);
router.put('/auth/fcm-token', authenticateJWT, auth.updateFcmToken);

// ─────────────────────────────────────────────
// 2. APPOINTMENTS ENDPOINTS
// ─────────────────────────────────────────────
router.post('/appointments', authenticateJWT, appointments.bookAppointment);
router.get('/appointments', authenticateJWT, appointments.getAppointments);
router.put('/appointments/:id', authenticateJWT, appointments.rescheduleAppointment);
router.delete('/appointments/:id', authenticateJWT, appointments.cancelAppointment);

// ─────────────────────────────────────────────
// 3. CLINIC PROFILE ENDPOINTS
// ─────────────────────────────────────────────
router.post('/clinics', authenticateJWT, requireRole(['Clinic', 'SuperAdmin']), clinics.registerClinicProfile);
router.get('/clinics', clinics.getClinics);
router.get('/clinics/:clinicId/dentists', clinics.getClinicDentists);

// ─────────────────────────────────────────────
// 4. SECURE CLOUD STORAGE ENDPOINTS (AWS S3)
// ─────────────────────────────────────────────
// POST /api/v1/upload          — Upload file (multipart/form-data, field: "file", optional: "folder")
// GET  /api/v1/upload/signed-url?key=<s3-key> — Get 15-min pre-signed access URL
router.post('/upload', authenticateJWT, upload.uploadFile);
router.get('/upload/signed-url', authenticateJWT, upload.getSignedFileUrl);

module.exports = router;
