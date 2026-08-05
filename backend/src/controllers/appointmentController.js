const { Appointment, Clinic, Dentist, User } = require('../models/Schemas');
const { sendPushNotification } = require('../services/notificationService');

// 1. BOOK APPOINTMENT
exports.bookAppointment = async (req, res) => {
    const { dentistId, clinicId, date, timeSlot, treatment, patientId } = req.body;
    try {
        const targetPatientId = patientId || (req.user ? req.user.id : 'PATIENT-GUEST');
        const appointment = await Appointment.create({
            patient_id: targetPatientId,
            dentist_id: dentistId || null,
            clinic_id: clinicId || null,
            date: date ? new Date(date).toISOString() : new Date().toISOString(),
            time_slot: timeSlot || 'Today, 2:30 PM',
            treatment: treatment || 'Dental Consultation',
            status: 'confirmed',
            payment_status: 'paid',
            qr_code_string: `DENTAGURU-${targetPatientId}-${Date.now()}`
        });

        // 🔔 Firebase FCM Push Notification
        if (req.user && req.user.id) {
            const patient = await User.findById(req.user.id);
            if (patient?.device_token) {
                await sendPushNotification(
                    patient.device_token,
                    '✅ Appointment Confirmed!',
                    `Your appointment for ${treatment} at ${timeSlot} on ${new Date(date).toDateString()} is confirmed.`,
                    { appointmentId: String(appointment.id), type: 'appointment_confirmed' }
                );
            }
        }

        res.status(201).json({
            success: true,
            message: 'Appointment booked successfully.',
            appointment
        });
    } catch (err) {
        console.error('Booking Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to book appointment.' });
    }
};

// 2. GET APPOINTMENTS
exports.getAppointments = async (req, res) => {
    try {
        const { patientId, dentistId, clinicId } = req.query;
        let query = {};
        if (patientId) query.patient_id = patientId;
        if (dentistId) query.dentist_id = dentistId;
        if (clinicId) query.clinic_id = clinicId;

        if (req.user) {
            if (req.user.role === 'Patient') {
                query.patient_id = req.user.id;
            } else if (req.user.role === 'Dentist') {
                const dentist = await Dentist.findOne({ user_id: req.user.id });
                if (dentist) query.dentist_id = dentist.id;
            } else if (req.user.role === 'Clinic') {
                const clinic = await Clinic.findOne({ user_id: req.user.id });
                if (clinic) query.clinic_id = clinic.id;
            }
        }

        const list = await Appointment.find(query);
        res.json({ success: true, count: list.length, appointments: list });
    } catch (err) {
        console.error('Get Appointments Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to fetch appointments.' });
    }
};

// 3. RESCHEDULE APPOINTMENT
exports.rescheduleAppointment = async (req, res) => {
    const { id } = req.params;
    const { date, timeSlot } = req.body;
    try {
        const appointment = await Appointment.findById(id);
        if (!appointment) {
            return res.status(404).json({ success: false, message: 'Appointment not found.' });
        }

        if (req.user.role === 'Patient' && appointment.patient_id !== req.user.id) {
            return res.status(403).json({ success: false, message: 'Access denied.' });
        }

        const updated = await Appointment.findByIdAndUpdate(id, {
            date: new Date(date).toISOString(),
            time_slot: timeSlot,
            status: 'rescheduled'
        });

        const patient = await User.findById(appointment.patient_id);
        if (patient?.device_token) {
            await sendPushNotification(
                patient.device_token,
                '📅 Appointment Rescheduled',
                `Your appointment has been rescheduled to ${timeSlot} on ${new Date(date).toDateString()}.`,
                { appointmentId: String(id), type: 'appointment_rescheduled' }
            );
        }

        res.json({ success: true, message: 'Appointment rescheduled successfully.', appointment: updated });
    } catch (err) {
        res.status(500).json({ success: false, message: 'Failed to reschedule appointment.' });
    }
};

// 4. CANCEL APPOINTMENT
exports.cancelAppointment = async (req, res) => {
    const { id } = req.params;
    try {
        const appointment = await Appointment.findById(id);
        if (!appointment) {
            return res.status(404).json({ success: false, message: 'Appointment not found.' });
        }

        if (req.user.role === 'Patient' && appointment.patient_id !== req.user.id) {
            return res.status(403).json({ success: false, message: 'Access denied.' });
        }

        const updated = await Appointment.findByIdAndUpdate(id, { status: 'cancelled' });

        const patient = await User.findById(appointment.patient_id);
        if (patient?.device_token) {
            await sendPushNotification(
                patient.device_token,
                '❌ Appointment Cancelled',
                `Your appointment has been cancelled. Book a new one anytime on DentaGuru.`,
                { appointmentId: String(id), type: 'appointment_cancelled' }
            );
        }

        res.json({ success: true, message: 'Appointment cancelled successfully.', appointment: updated });
    } catch (err) {
        res.status(500).json({ success: false, message: 'Failed to cancel appointment.' });
    }
};
