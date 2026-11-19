const { Appointment, Clinic, Dentist, User, Notification, MedicalRecord, Referral, DoctorAvailability, PatientAssignmentHistory, District, ASSIGNMENT_SOURCES, isDoctorRecordAvailable } = require('../models/Schemas');
const { sendPushNotification } = require('../services/notificationService');
const { generateTimeSlots } = require('./availabilityController');

function enrichAppointmentRecord(a) {
    if (!a || typeof a !== 'object') return a;
    const patientObj = a.patient && typeof a.patient === 'object' ? a.patient : {};
    const dentistObj = a.dentist && typeof a.dentist === 'object' ? a.dentist : {};
    const dentistUserObj = dentistObj.users && typeof dentistObj.users === 'object' ? dentistObj.users : {};
    const dentistClinicObj = dentistObj.clinics && typeof dentistObj.clinics === 'object' ? dentistObj.clinics : {};
    const clinicObj = a.clinic && typeof a.clinic === 'object' ? a.clinic : {};

    let patientMeta = {};
    if (patientObj.device_token && typeof patientObj.device_token === 'string' && patientObj.device_token.startsWith('{')) {
        try {
            patientMeta = JSON.parse(patientObj.device_token);
        } catch (_) {}
    }

    const rawDocName = (dentistUserObj.name || dentistObj.name || a.dentist_name || '').toString().trim();
    const formattedDocName = rawDocName
        ? (rawDocName.toLowerCase().startsWith('dr.') || rawDocName.toLowerCase().startsWith('dr ')
            ? rawDocName
            : `Dr. ${rawDocName}`)
        : '';

    const resolvedSpecialty = (dentistObj.speciality || dentistObj.specialty || a.specialty || a.doctor_specialty || '').toString().trim();
    const resolvedClinicName = (
        clinicObj.clinic_name ||
        clinicObj.name ||
        dentistClinicObj.clinic_name ||
        dentistClinicObj.name ||
        a.clinic_name ||
        ''
    ).toString().trim();
    const resolvedClinicId = a.clinic_id || clinicObj.id || dentistObj.clinic_id || dentistClinicObj.id || null;
    const resolvedPhoto = dentistUserObj.biometric_token || dentistObj.profilePhoto || a.doctor_photo || null;

    const resolvedPatientName = (patientObj.name || a.patient_name || '').toString().trim();
    const resolvedPatientPhone = (patientObj.phone || a.patient_phone || '').toString().trim();
    const resolvedPatientEmail = (patientObj.email || a.patient_email || '').toString().trim();
    const resolvedPatientCity = (patientObj.city || patientMeta.city || '').toString().trim();
    const resolvedPatientPincode = (patientObj.pincode || patientMeta.pincode || '').toString().trim();
    const resolvedPatientAge = (patientObj.age || patientMeta.age || '').toString().trim();
    const resolvedPatientGender = (patientObj.gender || patientMeta.gender || '').toString().trim();
    const resolvedPatientBloodGroup = (patientObj.blood_group || patientMeta.bloodGroup || '').toString().trim();

    return {
        ...a,
        patient_name: resolvedPatientName,
        patient_phone: resolvedPatientPhone,
        patient_email: resolvedPatientEmail,
        patient_city: resolvedPatientCity,
        patient_pincode: resolvedPatientPincode,
        patient_age: resolvedPatientAge,
        patient_gender: resolvedPatientGender,
        dentist_name: formattedDocName,
        doctor_specialty: resolvedSpecialty,
        doctor_photo: resolvedPhoto,
        clinic_id: resolvedClinicId,
        clinic_name: resolvedClinicName,
        booking_created_at: a.created_at || a.booking_created_at || null,
        selectedDoctor: {
            id: a.dentist_id || dentistObj.id || null,
            user_id: dentistObj.user_id || dentistUserObj.id || null,
            name: formattedDocName,
            specialty: resolvedSpecialty,
            qualification: dentistObj.qualifications || dentistObj.qualification || '',
            profilePhoto: resolvedPhoto,
            clinicId: resolvedClinicId,
            clinicName: resolvedClinicName,
        },
        patient: {
            id: a.patient_id || patientObj.id || null,
            name: resolvedPatientName,
            phone: resolvedPatientPhone,
            email: resolvedPatientEmail,
            city: resolvedPatientCity,
            pincode: resolvedPatientPincode,
            age: resolvedPatientAge,
            gender: resolvedPatientGender,
            bloodGroup: resolvedPatientBloodGroup,
        },
        clinic: {
            id: resolvedClinicId,
            clinic_name: resolvedClinicName,
            location: (clinicObj.location || dentistClinicObj.location || '').toString().trim(),
        },
    };
}

// Per-doctor async mutex queue to serialize concurrent availability checks & slot bookings
const _doctorBookingLocks = new Map();
async function _withDoctorBookingLock(doctorKey, taskFn) {
    const key = String(doctorKey || 'global').trim().toLowerCase();
    const prev = _doctorBookingLocks.get(key) || Promise.resolve();
    let release;
    const next = new Promise(resolve => { release = resolve; });
    const chained = prev.then(() => next);
    _doctorBookingLocks.set(key, chained);

    await prev;
    try {
        return await taskFn();
    } finally {
        release();
        if (_doctorBookingLocks.get(key) === chained) {
            _doctorBookingLocks.delete(key);
        }
    }
}

// 1. BOOK APPOINTMENT (Patient -> Dentist) [Initial Status: PENDING]
exports.bookAppointment = async (req, res) => {
    const { dentistId, clinicId, date, timeSlot, treatment, patientId, requestId } = req.body;
    try {
        const targetPatientId = patientId || (req.user ? req.user.id : null);
        const requestedDateStr = date ? DoctorAvailability.extractDateYmd(date) : DoctorAvailability.extractDateYmd(new Date());
        const normalizedSlot = (timeSlot || 'Today, 2:30 PM').trim();

        // 🛡️ Prevent past-date bookings
        const todayStr = DoctorAvailability.extractDateYmd(new Date());
        if (requestedDateStr < todayStr) {
            return res.status(400).json({
                success: false,
                message: 'Cannot book appointments for past dates. Please select today or a future date.'
            });
        }

        // Serialize availability verification, slot conflict check, and booking creation per doctor
        const bookingOutcome = await _withDoctorBookingLock(dentistId || targetPatientId || 'default', async () => {
            // 🛡️ Enforce Doctor Availability ON/OFF strictly at backend (prevents direct API bypass)
            let resolvedDoctor = null;
            if (dentistId) {
                resolvedDoctor = await Dentist.findById(dentistId);
                if (resolvedDoctor && !isDoctorRecordAvailable(resolvedDoctor)) {
                    return {
                        errorStatus: 409,
                        errorBody: {
                            success: false,
                            unavailable: true,
                            isAvailable: false,
                            message: 'Doctor is currently unavailable and not accepting new bookings.'
                        }
                    };
                }
            }

            // 🛡️ Verify doctor availability publication, working schedule, lunch break, and block status
            if (dentistId) {
                const avail = await DoctorAvailability.findOne({ dentist_id: dentistId, date: requestedDateStr });
                if (avail && avail.is_blocked) {
                    return {
                        errorStatus: 409,
                        errorBody: {
                            success: false,
                            isBlocked: true,
                            message: `The doctor is unavailable on this date (${avail.blocked_reason || 'Blocked / On Leave'}). Please choose another date.`
                        }
                    };
                }

                const schedule = await DoctorAvailability.getSchedule(dentistId);
                const weekdayName = DoctorAvailability.getWeekdayNameFromYmd(requestedDateStr);
                const hasCustomDateSlots = Boolean(avail && !avail.is_blocked && Array.isArray(avail.slots) && avail.slots.length > 0);

                if (schedule && schedule.isConfigured && !hasCustomDateSlots) {
                    const workingDays = Array.isArray(schedule.workingDays) ? schedule.workingDays : [];
                    if (workingDays.length > 0 && weekdayName && !workingDays.includes(weekdayName)) {
                        return {
                            errorStatus: 409,
                            errorBody: {
                                success: false,
                                message: `The doctor does not consult on ${weekdayName}s. Please select a configured working day.`
                            }
                        };
                    }
                }

                const effectiveSlots = hasCustomDateSlots
                    ? avail.slots
                    : (schedule && schedule.isConfigured
                        ? generateTimeSlots(
                            schedule.startTime,
                            schedule.endTime,
                            schedule.slotDurationMinutes,
                            schedule.hasBreak ? schedule.breakStartTime : null,
                            schedule.hasBreak ? schedule.breakEndTime : null
                        )
                        : []);

                const looksLikeClockSlot = /^\d{1,2}:\d{2}\s*(AM|PM)$/i.test(normalizedSlot);
                if (effectiveSlots.length > 0 && (hasCustomDateSlots || looksLikeClockSlot)) {
                    const inSlots = effectiveSlots.some(s => s.trim().toLowerCase() === normalizedSlot.toLowerCase());
                    if (!inSlots) {
                        return {
                            errorStatus: 400,
                            errorBody: {
                                success: false,
                                message: `The time slot (${normalizedSlot}) is unavailable or falls outside working hours / during lunch break.`
                            }
                        };
                    }
                }
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
                    return {
                        errorStatus: 409,
                        errorBody: {
                            success: false,
                            message: `The time slot (${normalizedSlot}) is already booked for this doctor on this date. Please select another slot.`
                        }
                    };
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
                    return {
                        errorStatus: 409,
                        errorBody: {
                            success: false,
                            message: `You already have an appointment booked for ${normalizedSlot} on this date. Please select another slot.`
                        }
                    };
                }
            }

            const effectiveDentistId = resolvedDoctor?.id || dentistId || null;
            const effectiveClinicId = clinicId || resolvedDoctor?.clinic_id || null;

            const appointment = await Appointment.create({
                patient_id: targetPatientId,
                dentist_id: effectiveDentistId,
                clinic_id: effectiveClinicId,
                request_id: requestId || null,
                date: date ? new Date(date).toISOString() : new Date().toISOString(),
                time_slot: timeSlot || 'Today, 2:30 PM',
                treatment: treatment || 'Medical Consultation',
                status: 'PENDING',
                qr_code_string: `DENTAGURU-${targetPatientId || 'PATIENT'}-${Date.now()}`
            });
            return { appointment };
        });

        if (bookingOutcome.errorStatus) {
            return res.status(bookingOutcome.errorStatus).json(bookingOutcome.errorBody);
        }
        const appointment = bookingOutcome.appointment;

        // 📜 Immutable Patient Assignment Audit Record (Scenario A: Direct Booking)
        if (targetPatientId && dentistId) {
            try {
                const patientUser = await User.findById(targetPatientId).catch(() => null);
                const locRes = District.resolveDistrictFromLocation({
                    city: patientUser?.city,
                    district: patientUser?.district,
                    state: patientUser?.state,
                    pincode: patientUser?.pincode
                });

                const userRoleLower = (req.user?.role || '').toLowerCase();
                const isMainAdmin = userRoleLower === 'admin' || userRoleLower === 'primaryadmin' || userRoleLower === 'superadmin';
                const isSubAdmin = userRoleLower === 'sub-admin' || userRoleLower === 'subadmin';

                let source = ASSIGNMENT_SOURCES.PATIENT_DIRECT_BOOKING;
                let assignedRole = 'PATIENT';
                let assignedName = patientUser?.name || req.user?.name || 'Direct Patient Booking';
                let assignedUserId = targetPatientId;

                if (isMainAdmin) {
                    source = ASSIGNMENT_SOURCES.MAIN_ADMIN_ASSIGNMENT;
                    assignedRole = 'MAIN_ADMIN';
                    assignedName = req.user?.name || 'Main Admin';
                    assignedUserId = req.user?.id;
                } else if (isSubAdmin) {
                    source = ASSIGNMENT_SOURCES.SUB_ADMIN_ASSIGNMENT;
                    assignedRole = 'SUB_ADMIN';
                    assignedName = req.user?.name || 'Sub-Admin';
                    assignedUserId = req.user?.id;
                }

                await PatientAssignmentHistory.recordAssignment({
                    patientId: targetPatientId,
                    doctorId: dentistId,
                    appointmentId: appointment.id,
                    requestId: requestId || null,
                    assignedByUserId: assignedUserId,
                    assignedByName: assignedName,
                    assignedByRole: assignedRole,
                    assignmentSource: source,
                    districtId: locRes.districtId || null,
                    districtName: locRes.district || patientUser?.district || patientUser?.city || 'Unassigned / Review',
                    assignmentReason: treatment ? `Direct consultation booking for ${treatment}` : 'Patient consultation booking.',
                    status: 'ASSIGNED'
                });
            } catch (auditErr) {
                console.warn('⚠️ Patient assignment audit trail notice:', auditErr.message);
            }
        }

        // 🔗 Update Referral Attribution if patient was referred
        if (targetPatientId) {
            try {
                await Referral.updateStatusForReferredUser(targetPatientId, 'CONSULTATION_BOOKED', {
                    appointment_id: appointment.id,
                    assigned_doctor_id: dentistId || null
                });
            } catch (_) {}
        }

        // Fetch enriched record so notifications and response carry full patient, doctor, and clinic metadata
        const fullAppt = await Appointment.findById(appointment.id).catch(() => null);
        const enrichedAppt = enrichAppointmentRecord(fullAppt || appointment);
        const patientDisplayName = enrichedAppt.patient_name || 'Patient';
        const doctorDisplayName = enrichedAppt.dentist_name || 'Selected Doctor';
        const clinicDisplayName = enrichedAppt.clinic_name || 'GS Health Practice';
        const effectiveTreatment = appointment.treatment || treatment || 'Medical Consultation';

        // 🔔 1. Persistent Notification to Doctor
        await Notification.create({
            recipient_role: 'Dentist',
            recipient_id: appointment.dentist_id || dentistId || 'ALL',
            title: '📅 New Appointment Booked',
            message: `${patientDisplayName} booked an appointment for ${effectiveTreatment} on ${requestedDateStr} at ${normalizedSlot}.`,
            type: 'appointment_request'
        });

        // 🔔 2. Persistent Notification to Patient
        if (targetPatientId || appointment.patient_id) {
            await Notification.create({
                recipient_role: 'Patient',
                recipient_id: targetPatientId || appointment.patient_id,
                title: '✅ Appointment Booking Submitted',
                message: `Your appointment with ${doctorDisplayName} (${clinicDisplayName}) on ${requestedDateStr} at ${normalizedSlot} has been booked and is pending confirmation.`,
                type: 'appointment_booked'
            });
        }

        // 🔔 3. Persistent Notification to Admin
        await Notification.create({
            recipient_role: 'Admin',
            recipient_id: 'ALL_ADMINS',
            title: '📋 New Appointment Booked',
            message: `${patientDisplayName} booked an appointment with ${doctorDisplayName} (${clinicDisplayName}) on ${requestedDateStr} at ${normalizedSlot}.`,
            type: 'admin_appointment_booked'
        });

        const patientAccountId = targetPatientId || (req.user && req.user.id);
        if (patientAccountId) {
            const patient = await User.findById(patientAccountId).catch(() => null);
            if (patient?.device_token && !String(patient.device_token).startsWith('{')) {
                await sendPushNotification(
                    patient.device_token,
                    '📋 Appointment Request Submitted',
                    `Your appointment request with ${doctorDisplayName} for ${effectiveTreatment} is pending confirmation.`,
                    { appointmentId: String(appointment.id), type: 'appointment_pending' }
                );
            }
        }

        res.status(201).json({
            success: true,
            message: 'Appointment request submitted successfully.',
            appointment: enrichedAppt
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
            const user = await User.findById(patientId).catch(() => null);
            const possibleIds = [patientId];
            if (user && user.id) possibleIds.push(user.id);
            if (user && user.name) possibleIds.push(user.name);
            if (user && user.email) possibleIds.push(user.email);
            query.patient_id = { $in: possibleIds };
        } else if (req.user && (req.user.role === 'Patient' || req.user.role === 'patient')) {
            const user = await User.findById(req.user.id).catch(() => null) || req.user;
            const possibleIds = [req.user.id];
            if (user && user.name) possibleIds.push(user.name);
            if (user && user.email) possibleIds.push(user.email);
            query.patient_id = { $in: possibleIds };
        }

        if (dentistId) {
            const dentist = await Dentist.findById(dentistId).catch(() => null) || await Dentist.findOne({ user_id: dentistId }).catch(() => null);
            const possibleDocIds = [dentistId];
            if (dentist) {
                if (dentist.id) possibleDocIds.push(dentist.id);
                if (dentist.user_id) possibleDocIds.push(dentist.user_id);
                if (dentist.name) possibleDocIds.push(dentist.name);
            }
            query.dentist_id = { $in: possibleDocIds };
        } else if (req.user && (req.user.role === 'Dentist' || req.user.role === 'doctor' || req.user.role === 'dentist' || req.user.role === 'Doctor')) {
            const dentist = await Dentist.findById(req.user.id).catch(() => null) || await Dentist.findOne({ user_id: req.user.id }).catch(() => null);
            const possibleDocIds = [req.user.id];
            if (dentist) {
                if (dentist.id) possibleDocIds.push(dentist.id);
                if (dentist.user_id) possibleDocIds.push(dentist.user_id);
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

        const rawList = await Appointment.find(query);
        const enrichedList = rawList.map(a => enrichAppointmentRecord(a));

        res.json({ success: true, count: enrichedList.length, appointments: enrichedList });
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

        await Appointment.findByIdAndUpdate(id, { status: 'CONFIRMED' });
        const fullAppt = await Appointment.findById(id).catch(() => null);
        const enriched = enrichAppointmentRecord(fullAppt || { ...appointment, status: 'CONFIRMED' });
        const docName = enriched.dentist_name || 'your doctor';
        const patName = enriched.patient_name || 'Patient';
        const apptDateStr = (enriched.date || '').toString().split('T')[0];

        await Notification.create({
            recipient_role: 'Patient',
            recipient_id: appointment.patient_id || 'ALL',
            title: '🎉 Appointment Confirmed',
            message: `Your appointment with ${docName} for ${appointment.treatment} on ${apptDateStr} at ${appointment.time_slot} has been confirmed.`,
            type: 'appointment_confirmed'
        });

        await Notification.create({
            recipient_role: 'Admin',
            recipient_id: 'ALL_ADMINS',
            title: '✅ Appointment Confirmed',
            message: `${docName} confirmed the appointment for ${patName} (${apptDateStr} at ${appointment.time_slot}).`,
            type: 'admin_appointment_confirmed'
        });

        const patient = await User.findById(appointment.patient_id).catch(() => null);
        if (patient?.device_token && !String(patient.device_token).startsWith('{')) {
            await sendPushNotification(
                patient.device_token,
                '🎉 Appointment Confirmed!',
                `Your doctor confirmed your visit for ${appointment.treatment}.`,
                { appointmentId: String(id), type: 'appointment_confirmed' }
            );
        }

        res.json({ success: true, message: 'Appointment confirmed successfully.', appointment: enriched });
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

        await Appointment.findByIdAndUpdate(id, { status: 'REJECTED' });
        const fullAppt = await Appointment.findById(id).catch(() => null);
        const enriched = enrichAppointmentRecord(fullAppt || { ...appointment, status: 'REJECTED' });
        const docName = enriched.dentist_name || 'Doctor';
        const patName = enriched.patient_name || 'Patient';

        await Notification.create({
            recipient_role: 'Patient',
            recipient_id: appointment.patient_id || 'ALL',
            title: '❌ Appointment Request Declined',
            message: `${docName} was unable to accept appointment. ${reason || 'Please select an alternate date or doctor.'}`,
            type: 'appointment_rejected'
        });

        await Notification.create({
            recipient_role: 'Admin',
            recipient_id: 'ALL_ADMINS',
            title: '⚠️ Appointment Request Declined',
            message: `Appointment for ${patName} with ${docName} was declined. ${reason || ''}`.trim(),
            type: 'admin_appointment_rejected'
        });

        const patient = await User.findById(appointment.patient_id).catch(() => null);
        if (patient?.device_token && !String(patient.device_token).startsWith('{')) {
            await sendPushNotification(
                patient.device_token,
                '❌ Appointment Request Declined',
                `Your appointment request was declined. Please try another slot.`,
                { appointmentId: String(id), type: 'appointment_rejected' }
            );
        }

        res.json({ success: true, message: 'Appointment rejected.', appointment: enriched });
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

        // Role Authorization Guard: User must be admin, patient owner, assigned doctor, or associated clinic
        if (req.user) {
            const role = (req.user.role || '').toLowerCase();
            const isSystemAdmin = role === 'admin' || role === 'super_admin' || role === 'sub-admin' || role === 'subadmin';
            const isOwnerPatient = String(appointment.patient_id) === String(req.user.id);
            const isAssignedDoctor = String(appointment.dentist_id) === String(req.user.id) ||
                String(appointment.dentist?.user_id || '') === String(req.user.id);
            let isClinicAdmin = false;
            if (role === 'clinic' || role === 'clinic_admin') {
                try {
                    const clinic = await Clinic.findOne({ user_id: req.user.id }) || await Clinic.findOne({ id: req.user.id });
                    if (clinic && String(appointment.clinic_id) === String(clinic.id)) isClinicAdmin = true;
                } catch (_) {}
            }
            if (!isSystemAdmin && !isOwnerPatient && !isAssignedDoctor && !isClinicAdmin) {
                return res.status(403).json({
                    success: false,
                    message: 'Access Denied: You are not authorized to reschedule this appointment.'
                });
            }
        }

        // 🛡️ Prevent past-date rescheduling
        const newDateStr = date ? new Date(date).toISOString().split('T')[0] : (appointment.date ? new Date(appointment.date).toISOString().split('T')[0] : '');
        const todayStr = new Date().toISOString().split('T')[0];
        if (newDateStr && newDateStr < todayStr) {
            return res.status(400).json({
                success: false,
                message: 'Cannot reschedule appointments to past dates. Please select today or a future date.'
            });
        }

        // 🛡️ Prevent slot conflict on reschedule
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

        await Appointment.findByIdAndUpdate(id, {
            date: date ? new Date(date).toISOString() : appointment.date,
            time_slot: timeSlot || appointment.time_slot,
            status: 'RESCHEDULED'
        });
        const fullAppt = await Appointment.findById(id).catch(() => null);
        const enriched = enrichAppointmentRecord(fullAppt || {
            ...appointment,
            date: date ? new Date(date).toISOString() : appointment.date,
            time_slot: timeSlot || appointment.time_slot,
            status: 'RESCHEDULED'
        });
        const docName = enriched.dentist_name || 'Doctor';
        const patName = enriched.patient_name || 'Patient';

        await Notification.create({
            recipient_role: 'Patient',
            recipient_id: appointment.patient_id || 'ALL',
            title: '📅 Appointment Rescheduled',
            message: `Your appointment with ${docName} has been rescheduled to ${newDateStr} at ${newSlot}.`,
            type: 'appointment_rescheduled'
        });

        if (appointment.dentist_id) {
            await Notification.create({
                recipient_role: 'Dentist',
                recipient_id: appointment.dentist_id,
                title: '📅 Appointment Rescheduled',
                message: `Appointment with ${patName} has been rescheduled to ${newDateStr} at ${newSlot}.`,
                type: 'appointment_rescheduled'
            });
        }

        await Notification.create({
            recipient_role: 'Admin',
            recipient_id: 'ALL_ADMINS',
            title: '📅 Appointment Rescheduled',
            message: `Appointment for ${patName} with ${docName} was rescheduled to ${newDateStr} at ${newSlot}.`,
            type: 'admin_appointment_rescheduled'
        });

        const patient = await User.findById(appointment.patient_id).catch(() => null);
        if (patient?.device_token && !String(patient.device_token).startsWith('{')) {
            await sendPushNotification(
                patient.device_token,
                '📅 Appointment Rescheduled',
                `Your appointment has been rescheduled to ${newSlot}.`,
                { appointmentId: String(id), type: 'appointment_rescheduled' }
            );
        }

        res.json({ success: true, message: 'Appointment rescheduled successfully.', appointment: enriched });
    } catch (err) {
        res.status(500).json({ success: false, message: 'Failed to reschedule appointment.' });
    }
};

// 6. CANCEL APPOINTMENT [-> CANCELLED: RELEASES SLOT IMMEDIATELY]
exports.cancelAppointment = async (req, res) => {
    const { id } = req.params;
    try {
        const appointment = await Appointment.findById(id);
        if (!appointment) {
            return res.status(404).json({ success: false, message: 'Appointment not found.' });
        }

        // Role Authorization Guard: User must be admin, patient owner, assigned doctor, or associated clinic
        if (req.user) {
            const role = (req.user.role || '').toLowerCase();
            const isSystemAdmin = role === 'admin' || role === 'super_admin' || role === 'sub-admin' || role === 'subadmin';
            const isOwnerPatient = String(appointment.patient_id) === String(req.user.id);
            const isAssignedDoctor = String(appointment.dentist_id) === String(req.user.id) ||
                String(appointment.dentist?.user_id || '') === String(req.user.id);
            let isClinicAdmin = false;
            if (role === 'clinic' || role === 'clinic_admin') {
                try {
                    const clinic = await Clinic.findOne({ user_id: req.user.id }) || await Clinic.findOne({ id: req.user.id });
                    if (clinic && String(appointment.clinic_id) === String(clinic.id)) isClinicAdmin = true;
                } catch (_) {}
            }
            if (!isSystemAdmin && !isOwnerPatient && !isAssignedDoctor && !isClinicAdmin) {
                return res.status(403).json({
                    success: false,
                    message: 'Access Denied: You are not authorized to cancel this appointment.'
                });
            }
        }

        await Appointment.findByIdAndUpdate(id, { status: 'CANCELLED' });
        const fullAppt = await Appointment.findById(id).catch(() => null);
        const enriched = enrichAppointmentRecord(fullAppt || { ...appointment, status: 'CANCELLED' });
        const docName = enriched.dentist_name || 'Doctor';
        const patName = enriched.patient_name || 'Patient';
        const apptDateStr = (enriched.date || '').toString().split('T')[0];

        if (appointment.patient_id) {
            await Notification.create({
                recipient_role: 'Patient',
                recipient_id: appointment.patient_id,
                title: '🚫 Appointment Cancelled',
                message: `Your appointment with ${docName} on ${apptDateStr} at ${appointment.time_slot} has been cancelled.`,
                type: 'appointment_cancelled'
            });
        }

        if (appointment.dentist_id) {
            await Notification.create({
                recipient_role: 'Dentist',
                recipient_id: appointment.dentist_id,
                title: '🚫 Appointment Cancelled',
                message: `Appointment with ${patName} on ${apptDateStr} at ${appointment.time_slot} has been cancelled.`,
                type: 'appointment_cancelled'
            });
        }

        await Notification.create({
            recipient_role: 'Admin',
            recipient_id: 'ALL_ADMINS',
            title: '🚫 Appointment Cancelled',
            message: `Appointment for ${patName} with ${docName} (${apptDateStr} at ${appointment.time_slot}) was cancelled.`,
            type: 'admin_appointment_cancelled'
        });

        const patient = await User.findById(appointment.patient_id).catch(() => null);
        if (patient?.device_token && !String(patient.device_token).startsWith('{')) {
            await sendPushNotification(
                patient.device_token,
                '🚫 Appointment Cancelled',
                `Your appointment has been cancelled.`,
                { appointmentId: String(id), type: 'appointment_cancelled' }
            );
        }

        res.json({ success: true, message: 'Appointment cancelled successfully. Slot has been released.', appointment: enriched });
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
        await Appointment.findByIdAndUpdate(id, { status: 'COMPLETED' });
        const fullAppt = await Appointment.findById(id).catch(() => null);
        const enriched = enrichAppointmentRecord(fullAppt || { ...appointment, status: 'COMPLETED' });
        const docName = enriched.dentist_name || 'Doctor';
        const patName = enriched.patient_name || 'Patient';

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
            diagnosis: diagnosis || appointment.treatment || 'Medical Consultation',
            symptoms: symptoms || '',
            treatment: treatmentPlan || treatmentNotes || appointment.treatment,
            notes: treatmentNotes || '',
            prescriptions: prescriptions || [],
            attachments: attachments || [],
            follow_up_date: followUpDate ? new Date(followUpDate).toISOString() : null
        });

        // 3. Dispatch Notifications to Patient & Admin
        await Notification.create({
            recipient_role: 'Patient',
            recipient_id: appointment.patient_id || 'ALL',
            title: '✅ Consultation Completed & E-Prescription Issued',
            message: `Your consultation with ${docName} is complete. Tap to view medical records and prescriptions.`,
            type: 'consultation_completed'
        });

        await Notification.create({
            recipient_role: 'Admin',
            recipient_id: 'ALL_ADMINS',
            title: '✅ Consultation Completed',
            message: `${docName} completed consultation for ${patName}.`,
            type: 'admin_consultation_completed'
        });

        const patient = await User.findById(appointment.patient_id).catch(() => null);
        if (patient?.device_token && !String(patient.device_token).startsWith('{')) {
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
            appointment: enriched,
            record: newRecord
        });
    } catch (err) {
        console.error('Complete Consultation Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to complete consultation.' });
    }
};

// 8. GET PERSISTENT NOTIFICATIONS (Patient, Doctor, Admin)
exports.getNotifications = async (req, res) => {
    try {
        const queryRole = (req.query.role || req.user?.role || '').toString().trim();
        const queryUserId = (req.query.userId || req.user?.id || '').toString().trim();

        // Enforce role-based access if JWT user is present
        let effectiveRole = queryRole;
        let effectiveUserId = queryUserId;

        if (req.user) {
            const callerRoleLower = (req.user.role || '').toString().trim().toLowerCase();
            const isCallerAdmin = callerRoleLower === 'admin' || callerRoleLower === 'sub-admin' || callerRoleLower === 'subadmin' || callerRoleLower === 'primaryadmin' || callerRoleLower === 'superadmin';
            if (!isCallerAdmin) {
                // Non-admin caller can only query notifications for their own role & user/dentist identity
                effectiveRole = req.user.role;
                if (!effectiveUserId) {
                    effectiveUserId = req.user.id;
                } else if (String(effectiveUserId) !== String(req.user.id)) {
                    // For doctors, allow passing either their users.id or dentists.id
                    if (callerRoleLower === 'dentist' || callerRoleLower === 'doctor') {
                        const doc = await Dentist.findById(req.user.id).catch(() => null);
                        const allowedIds = new Set([String(req.user.id), String(doc?.id || ''), String(doc?.user_id || '')]);
                        if (!allowedIds.has(String(effectiveUserId))) {
                            effectiveUserId = req.user.id;
                        }
                    } else {
                        effectiveUserId = req.user.id;
                    }
                }
            }
        }

        if (!effectiveRole && !effectiveUserId) {
            return res.json({ success: true, count: 0, unreadCount: 0, notifications: [] });
        }

        const list = await Notification.findForUser({
            role: effectiveRole,
            userId: effectiveUserId
        });
        const unreadCount = list.filter(n => !n.read).length;

        res.json({
            success: true,
            count: list.length,
            unreadCount,
            notifications: list
        });
    } catch (err) {
        console.error('Get Notifications Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to fetch notifications.' });
    }
};

// 9. MARK NOTIFICATION AS READ
exports.markNotificationRead = async (req, res) => {
    const { id } = req.params;
    try {
        if (!id) {
            return res.status(400).json({ success: false, message: 'Notification ID is required.' });
        }
        const updated = await Notification.markAsRead(id);
        res.json({
            success: true,
            message: 'Notification marked as read.',
            notification: updated || { id, read: true }
        });
    } catch (err) {
        console.error('Mark Notification Read Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to mark notification as read.' });
    }
};

// 10. MARK ALL NOTIFICATIONS AS READ FOR USER
exports.markAllNotificationsRead = async (req, res) => {
    try {
        const role = (req.body?.role || req.query?.role || req.user?.role || '').toString().trim();
        const userId = (req.body?.userId || req.query?.userId || req.user?.id || '').toString().trim();
        const updatedCount = await Notification.markAllAsReadForUser({ role, userId });
        res.json({
            success: true,
            message: 'All notifications marked as read.',
            updatedCount
        });
    } catch (err) {
        console.error('Mark All Notifications Read Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to mark all notifications as read.' });
    }
};


