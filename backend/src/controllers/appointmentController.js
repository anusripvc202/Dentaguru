const { Appointment, Clinic, Dentist, User, Notification, MedicalRecord, Referral, DoctorAvailability } = require('../models/Schemas');
const { sendPushNotification } = require('../services/notificationService');

// 1. BOOK APPOINTMENT (Patient -> Dentist) [Initial Status: PENDING]
exports.bookAppointment = async (req, res) => {
    const { dentistId, clinicId, date, timeSlot, treatment, patientId, requestId } = req.body;
    try {
        const targetPatientId = patientId || (req.user ? req.user.id : null);
        const requestedDateStr = date ? new Date(date).toISOString().split('T')[0] : new Date().toISOString().split('T')[0];
        const normalizedSlot = (timeSlot || 'Today, 2:30 PM').trim();

        // 🛡️ Verify doctor availability publication and block status
        if (dentistId) {
            try {
                const avail = await DoctorAvailability.findOne({ dentist_id: dentistId, date: requestedDateStr });
                if (avail) {
                    if (avail.is_blocked) {
                        return res.status(409).json({
                            success: false,
                            message: `The doctor is unavailable on this date (${avail.blocked_reason || 'Blocked / On Leave'}). Please choose another date.`
                        });
                    }
                    if (Array.isArray(avail.slots) && avail.slots.length > 0) {
                        const inSlots = avail.slots.some(s => s.trim().toLowerCase() === normalizedSlot.toLowerCase());
                        if (!inSlots) {
                            return res.status(400).json({
                                success: false,
                                message: `The time slot (${normalizedSlot}) is not a published slot for this doctor.`
                            });
                        }
                    }
                }
            } catch (_) {}
        }

        // 🛡️ Prevent duplicate bookings & unavailable time-slot bookings
        if (dentistId) {
            const existingDentistAppts = await Appointment.find({ dentistId });
            const conflict = existingDentistAppts.find(a => {
                const aStatus = (a.status || '').toUpperCase();
                if (aStatus === 'CANCELLED' || aStatus === 'REJECTED') return false;
                const aDateStr = (a.date || a.appointment_date || '').split('T')[0];
                const aSlot = (a.time_slot || a.timeSlot || '').trim();
                return aDateStr === requestedDateStr && aSlot.toLowerCase() === normalizedSlot.toLowerCase();
            });
            if (conflict) {
                return res.status(409).json({
                    success: false,
                    message: `The time slot (${normalizedSlot}) is already booked for this doctor on this date. Please select another slot.`
                });
            }
        }

        if (targetPatientId) {
            const existingPatientAppts = await Appointment.find({ patientId: targetPatientId });
            const patientConflict = existingPatientAppts.find(a => {
                const aStatus = (a.status || '').toUpperCase();
                if (aStatus === 'CANCELLED' || aStatus === 'REJECTED') return false;
                const aDateStr = (a.date || a.appointment_date || '').split('T')[0];
                const aSlot = (a.time_slot || a.timeSlot || '').trim();
                return aDateStr === requestedDateStr && aSlot.toLowerCase() === normalizedSlot.toLowerCase();
            });
            if (patientConflict) {
                return res.status(409).json({
                    success: false,
                    message: `You already have an appointment booked for ${normalizedSlot} on this date. Please select another slot.`
                });
            }
        }

        const appointment = await Appointment.create({
            patient_id: targetPatientId,
            dentist_id: dentistId || null,
            clinic_id: clinicId || null,
            request_id: requestId || null,
            date: date ? new Date(date).toISOString() : new Date().toISOString(),
            time_slot: timeSlot || 'Today, 2:30 PM',
            treatment: treatment || 'Dental Consultation',
            status: 'PENDING',
            qr_code_string: `DENTAGURU-${targetPatientId || 'PATIENT'}-${Date.now()}`
        });

        // 🔗 Update Referral Attribution if patient was referred
        if (targetPatientId) {
            try {
                await Referral.updateStatusForReferredUser(targetPatientId, 'CONSULTATION_BOOKED', {
                    appointment_id: appointment.id,
                    assigned_doctor_id: dentistId || null
                });
            } catch (_) {}
        }

        // 🔔 Notification to Dentist & Patient
        await Notification.create({
            recipient_role: 'Dentist',
            recipient_id: dentistId || 'ALL',
            title: '📅 New Appointment Request',
            message: `Patient requested appointment for ${treatment} at ${timeSlot}`,
            type: 'appointment_request'
        });

        if (req.user && req.user.id) {
            const patient = await User.findById(req.user.id);
            if (patient?.device_token) {
                await sendPushNotification(
                    patient.device_token,
                    '📋 Appointment Request Submitted',
                    `Your appointment request for ${treatment} is pending dentist confirmation.`,
                    { appointmentId: String(appointment.id), type: 'appointment_pending' }
                );
            }
        }

        res.status(201).json({
            success: true,
            message: 'Appointment request submitted successfully.',
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
        const { patientId, dentistId, clinicId, status } = req.query;
        let query = {};
        if (status) query.status = status;

        if (patientId) {
            const user = await User.findById(patientId);
            const possibleIds = [patientId];
            if (user && user.id) possibleIds.push(user.id);
            if (user && user.name) possibleIds.push(user.name);
            if (user && user.email) possibleIds.push(user.email);
            query.patient_id = { $in: possibleIds };
        } else if (req.user && (req.user.role === 'Patient' || req.user.role === 'patient')) {
            const user = await User.findById(req.user.id) || req.user;
            const possibleIds = [req.user.id];
            if (user && user.name) possibleIds.push(user.name);
            if (user && user.email) possibleIds.push(user.email);
            query.patient_id = { $in: possibleIds };
        }

        if (dentistId) {
            const dentist = await Dentist.findOne({ id: dentistId }) || await Dentist.findOne({ user_id: dentistId });
            const possibleDocIds = [dentistId];
            if (dentist) {
                if (dentist.id) possibleDocIds.push(dentist.id);
                if (dentist.user_id) possibleDocIds.push(dentist.user_id);
                if (dentist.name) possibleDocIds.push(dentist.name);
            }
            query.dentist_id = { $in: possibleDocIds };
        } else if (req.user && (req.user.role === 'Dentist' || req.user.role === 'doctor')) {
            const dentist = await Dentist.findOne({ user_id: req.user.id });
            const possibleDocIds = [req.user.id];
            if (dentist) {
                if (dentist.id) possibleDocIds.push(dentist.id);
                if (dentist.name) possibleDocIds.push(dentist.name);
            }
            if (req.user.name) possibleDocIds.push(req.user.name);
            query.dentist_id = { $in: possibleDocIds };
        }

        if (clinicId) {
            query.clinic_id = clinicId;
        } else if (req.user && (req.user.role === 'Clinic' || req.user.role === 'clinic')) {
            const clinic = await Clinic.findOne({ user_id: req.user.id });
            if (clinic) query.clinic_id = clinic.id;
        }

        const isAdmin = req.user && (req.user.role === 'Admin' || req.user.role === 'admin' || req.user.role === 'Sub-Admin' || req.user.role === 'subadmin');
        if (!isAdmin && !patientId && !dentistId && !clinicId && !req.user) {
            return res.json({ success: true, count: 0, appointments: [] });
        }

        const list = await Appointment.find(query);
        res.json({ success: true, count: list.length, appointments: list });
    } catch (err) {
        console.error('Get Appointments Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to fetch appointments.' });
    }
};

// 3. DENTIST: ACCEPT APPOINTMENT [PENDING -> CONFIRMED]
exports.acceptAppointment = async (req, res) => {
    const { id } = req.params;
    try {
        const appointment = await Appointment.findById(id);
        if (!appointment) {
            return res.status(404).json({ success: false, message: 'Appointment not found.' });
        }

        const updated = await Appointment.findByIdAndUpdate(id, { status: 'CONFIRMED' });

        await Notification.create({
            recipient_role: 'Patient',
            recipient_id: appointment.patient_id || 'ALL',
            title: '🎉 Appointment Confirmed',
            message: `Your appointment for ${appointment.treatment} has been confirmed by your dentist.`,
            type: 'appointment_confirmed'
        });

        const patient = await User.findById(appointment.patient_id);
        if (patient?.device_token) {
            await sendPushNotification(
                patient.device_token,
                '🎉 Appointment Confirmed!',
                `Your dentist confirmed your visit for ${appointment.treatment}.`,
                { appointmentId: String(id), type: 'appointment_confirmed' }
            );
        }

        res.json({ success: true, message: 'Appointment confirmed successfully.', appointment: updated });
    } catch (err) {
        console.error('Accept Appointment Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to accept appointment.' });
    }
};

// 4. DENTIST: REJECT APPOINTMENT [PENDING -> REJECTED]
exports.rejectAppointment = async (req, res) => {
    const { id } = req.params;
    const { reason } = req.body;
    try {
        const appointment = await Appointment.findById(id);
        if (!appointment) {
            return res.status(404).json({ success: false, message: 'Appointment not found.' });
        }

        const updated = await Appointment.findByIdAndUpdate(id, { status: 'REJECTED' });

        await Notification.create({
            recipient_role: 'Patient',
            recipient_id: appointment.patient_id || 'ALL',
            title: '❌ Appointment Request Declined',
            message: `Dentist was unable to accept appointment. ${reason || 'Please select an alternate date or doctor.'}`,
            type: 'appointment_rejected'
        });

        const patient = await User.findById(appointment.patient_id);
        if (patient?.device_token) {
            await sendPushNotification(
                patient.device_token,
                '❌ Appointment Request Declined',
                `Your appointment request was declined. Please try another slot.`,
                { appointmentId: String(id), type: 'appointment_rejected' }
            );
        }

        res.json({ success: true, message: 'Appointment rejected.', appointment: updated });
    } catch (err) {
        console.error('Reject Appointment Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to reject appointment.' });
    }
};

// 5. RESCHEDULE APPOINTMENT [-> RESCHEDULED]
exports.rescheduleAppointment = async (req, res) => {
    const { id } = req.params;
    const { date, timeSlot } = req.body;
    try {
        const appointment = await Appointment.findById(id);
        if (!appointment) {
            return res.status(404).json({ success: false, message: 'Appointment not found.' });
        }

        // 🛡️ Prevent slot conflict on reschedule
        const newDateStr = date ? new Date(date).toISOString().split('T')[0] : (appointment.date ? new Date(appointment.date).toISOString().split('T')[0] : '');
        const newSlot = (timeSlot || appointment.time_slot || '').trim();
        if (appointment.dentist_id && newSlot) {
            const existingDentistAppts = await Appointment.find({ dentistId: appointment.dentist_id });
            const conflict = existingDentistAppts.find(a => {
                if (String(a.id) === String(id)) return false;
                const aStatus = (a.status || '').toUpperCase();
                if (aStatus === 'CANCELLED' || aStatus === 'REJECTED') return false;
                const aDateStr = (a.date || a.appointment_date || '').split('T')[0];
                const aSlot = (a.time_slot || a.timeSlot || '').trim();
                return aDateStr === newDateStr && aSlot.toLowerCase() === newSlot.toLowerCase();
            });
            if (conflict) {
                return res.status(409).json({
                    success: false,
                    message: `The time slot (${newSlot}) is already booked for this doctor on this date. Please select another slot.`
                });
            }
        }

        const updated = await Appointment.findByIdAndUpdate(id, {
            date: date ? new Date(date).toISOString() : appointment.date,
            time_slot: timeSlot || appointment.time_slot,
            status: 'RESCHEDULED'
        });

        await Notification.create({
            recipient_role: 'Patient',
            recipient_id: appointment.patient_id || 'ALL',
            title: '📅 Appointment Rescheduled',
            message: `Appointment updated to ${timeSlot || appointment.time_slot}.`,
            type: 'appointment_rescheduled'
        });

        const patient = await User.findById(appointment.patient_id);
        if (patient?.device_token) {
            await sendPushNotification(
                patient.device_token,
                '📅 Appointment Rescheduled',
                `Your appointment has been rescheduled to ${timeSlot}.`,
                { appointmentId: String(id), type: 'appointment_rescheduled' }
            );
        }

        res.json({ success: true, message: 'Appointment rescheduled successfully.', appointment: updated });
    } catch (err) {
        res.status(500).json({ success: false, message: 'Failed to reschedule appointment.' });
    }
};

// 6. CANCEL APPOINTMENT [-> CANCELLED]
exports.cancelAppointment = async (req, res) => {
    const { id } = req.params;
    try {
        const appointment = await Appointment.findById(id);
        if (!appointment) {
            return res.status(404).json({ success: false, message: 'Appointment not found.' });
        }

        const updated = await Appointment.findByIdAndUpdate(id, { status: 'CANCELLED' });

        const patient = await User.findById(appointment.patient_id);
        if (patient?.device_token) {
            await sendPushNotification(
                patient.device_token,
                '🚫 Appointment Cancelled',
                `Your appointment has been cancelled.`,
                { appointmentId: String(id), type: 'appointment_cancelled' }
            );
        }

        res.json({ success: true, message: 'Appointment cancelled successfully.', appointment: updated });
    } catch (err) {
        res.status(500).json({ success: false, message: 'Failed to cancel appointment.' });
    }
};

// 7. DENTIST: COMPLETE CONSULTATION [CONFIRMED -> COMPLETED]
exports.completeConsultation = async (req, res) => {
    const { id } = req.params;
    const { symptoms, diagnosis, treatmentNotes, treatmentPlan, followUpDate, prescriptions, attachments } = req.body;
    try {
        const appointment = await Appointment.findById(id);
        if (!appointment) {
            return res.status(404).json({ success: false, message: 'Appointment not found.' });
        }

        // 1. Mark Appointment Status COMPLETED
        const updatedApp = await Appointment.findByIdAndUpdate(id, { status: 'COMPLETED' });

        // 🔗 Update Referral Attribution to CONSULTATION_COMPLETED
        if (appointment.patient_id) {
            try {
                await Referral.updateStatusForReferredUser(appointment.patient_id, 'CONSULTATION_COMPLETED', {
                    appointment_id: id,
                    assigned_doctor_id: appointment.dentist_id || null
                });
            } catch (_) {}
        }

        // 2. Create Medical Record & E-Prescription
        const newRecord = await MedicalRecord.create({
            patient_id: appointment.patient_id,
            dentist_id: appointment.dentist_id,
            appointment_id: id,
            diagnosis: diagnosis || appointment.treatment || 'Dental Consultation',
            symptoms: symptoms || '',
            treatment: treatmentPlan || treatmentNotes || appointment.treatment,
            notes: treatmentNotes || '',
            prescriptions: prescriptions || [],
            attachments: attachments || [],
            follow_up_date: followUpDate ? new Date(followUpDate).toISOString() : null
        });

        // 3. Dispatch Notification to Patient
        await Notification.create({
            recipient_role: 'Patient',
            recipient_id: appointment.patient_id || 'ALL',
            title: '✅ Consultation Completed & E-Prescription Issued',
            message: `Your consultation is complete. Tap to view medical records and prescriptions.`,
            type: 'consultation_completed'
        });

        const patient = await User.findById(appointment.patient_id);
        if (patient?.device_token) {
            await sendPushNotification(
                patient.device_token,
                '✅ Consultation Completed',
                `New medical record and prescription added to your account.`,
                { appointmentId: String(id), recordId: String(newRecord.id), type: 'consultation_completed' }
            );
        }

        res.json({
            success: true,
            message: 'Consultation completed and medical record generated successfully.',
            appointment: updatedApp,
            record: newRecord
        });
    } catch (err) {
        console.error('Complete Consultation Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to complete consultation.' });
    }
};

