const express = require('express');
const router = express.Router();

// Controllers
const auth = require('../controllers/authController');
const appointments = require('../controllers/appointmentController');
const clinics = require('../controllers/clinicController');

// Middlewares
const { authenticateJWT, requireRole } = require('../middleware/auth');

// 1. AUTHENTICATION ENDPOINTS
router.post('/auth/register', auth.register);
router.post('/auth/login', auth.login);
router.post('/auth/otp/request', auth.requestOTP);
router.post('/auth/otp/verify', auth.verifyOTP);
router.post('/auth/refresh', auth.refreshToken);
router.post('/auth/biometric', authenticateJWT, auth.saveBiometric);

// 2. APPOINTMENTS ENDPOINTS
router.post('/appointments', authenticateJWT, appointments.bookAppointment);
router.get('/appointments', authenticateJWT, appointments.getAppointments);
router.put('/appointments/:id', authenticateJWT, appointments.rescheduleAppointment);
router.delete('/appointments/:id', authenticateJWT, appointments.cancelAppointment);

// 3. CLINIC PROFILE ENDPOINTS
router.post('/clinics', authenticateJWT, requireRole(['Clinic', 'SuperAdmin']), clinics.registerClinicProfile);
router.get('/clinics', clinics.getClinics);
router.get('/clinics/:clinicId/dentists', clinics.getClinicDentists);

module.exports = router;
