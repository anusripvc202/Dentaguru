const { Appointment, Clinic, User } = require('../models/Schemas');
const { sendPushNotification } = require('../services/notificationService');

// 1. BOOK APPOINTMENT
exports.bookAppointment = async (req, res) => {
    const { dentistId, clinicId, date, timeSlot, treatment } = req.body;
    try {
        // Validate clinic availability slot
        const clinic = await Clinic.findById(clinicId);
        if (!clinic) {
            return res.status(404).json({ success: false, message: 'Clinic not found.' });
        }

        // Create appointment
        const appointment = new Appointment({
            patientId: req.user.id,
            dentistId,
            clinicId,
            date: new Date(date),
            timeSlot,
            treatment,
            status: 'confirmed',
            qrCodeString: `DENTAGURU-${req.user.id}-${Date.now()}`
        });

        await appointment.save();

        // 🔔 Firebase FCM — Notify patient of confirmed booking
        const patient = await User.findById(req.user.id).select('deviceToken name');
        if (patient?.deviceToken) {
            await sendPushNotification(
                patient.deviceToken,
                '✅ Appointment Confirmed!',
                `Your appointment for ${treatment} at ${timeSlot} on ${new Date(date).toDateString()} is confirmed.`,
                { appointmentId: String(appointment._id), type: 'appointment_confirmed' }
            );
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

// 2. GET APPOINTMENTS (Role specific list)
exports.getAppointments = async (req, res) => {
    try {
        let query = {};
        if (req.user.role === 'Patient') {
            query.patientId = req.user.id;
        } else if (req.user.role === 'Dentist') {
            // Find dentist profile first
            const dentist = await mongoose.model('Dentist').findOne({ userId: req.user.id });
            if (dentist) {
                query.dentistId = dentist._id;
            } else {
                return res.status(400).json({ success: false, message: 'Dentist profile not found.' });
            }
        } else if (req.user.role === 'Clinic') {
            const clinic = await Clinic.findOne({ userId: req.user.id });
            if (clinic) {
                query.clinicId = clinic._id;
            } else {
                return res.status(400).json({ success: false, message: 'Clinic profile not found.' });
            }
        }
        // SuperAdmin gets all

        const list = await Appointment.find(query)
            .populate('patientId', 'name email phone')
            .populate('clinicId', 'clinicName location')
            .sort({ date: 1 });

        res.json({ success: true, count: list.length, appointments: list });
    } catch (err) {
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

        // Restrict edits to patient owner or doctor/clinic
        if (req.user.role === 'Patient' && appointment.patientId.toString() !== req.user.id) {
            return res.status(403).json({ success: false, message: 'Access denied.' });
        }

        appointment.date = new Date(date);
        appointment.timeSlot = timeSlot;
        appointment.status = 'rescheduled';
        await appointment.save();

        // 🔔 Firebase FCM — Notify patient of reschedule
        const patient = await User.findById(appointment.patientId).select('deviceToken');
        if (patient?.deviceToken) {
            await sendPushNotification(
                patient.deviceToken,
                '📅 Appointment Rescheduled',
                `Your appointment has been rescheduled to ${timeSlot} on ${new Date(date).toDateString()}.`,
                { appointmentId: String(appointment._id), type: 'appointment_rescheduled' }
            );
        }

        res.json({ success: true, message: 'Appointment rescheduled successfully.', appointment });
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

        if (req.user.role === 'Patient' && appointment.patientId.toString() !== req.user.id) {
            return res.status(403).json({ success: false, message: 'Access denied.' });
        }

        appointment.status = 'cancelled';
        await appointment.save();

        // 🔔 Firebase FCM — Notify patient of cancellation
        const patient = await User.findById(appointment.patientId).select('deviceToken');
        if (patient?.deviceToken) {
            await sendPushNotification(
                patient.deviceToken,
                '❌ Appointment Cancelled',
                `Your appointment has been cancelled. Book a new one anytime on DentaGuru.`,
                { appointmentId: String(appointment._id), type: 'appointment_cancelled' }
            );
        }

        res.json({ success: true, message: 'Appointment cancelled successfully.', appointment });
    } catch (err) {
        res.status(500).json({ success: false, message: 'Failed to cancel appointment.' });
    }
};
