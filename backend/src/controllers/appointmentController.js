const { supabaseAdmin } = require('../config/supabase');
const { Appointment, Clinic, Dentist, User, Notification, MedicalRecord, Referral, DoctorAvailability, PatientAssignmentHistory, District, SubAdminDistrict, SubAdminPermission, ASSIGNMENT_SOURCES, isDoctorRecordAvailable, resolveClinicIds, resolveDentistIds } = require('../models/Schemas');
const { sendPushNotification } = require('../services/notificationService');
const { generateTimeSlots } = require('./availabilityController');
const { resolveClinicRecordAndDoctorIds } = require('./clinicController');
const { sendDoctorBookingAlert, sendClinicBookingAlert, isWhatsAppProviderConfigured } = require('../services/whatsappService');
const {
    getBookingRulesConfig,
    getNowPartsInTimezone,
    normalizeDateToTimezoneYmd,
    checkSlotBookableForDateYmd,
    formatLocalYmd,
    parseClockSlotMinutes,
    minutesToClockSlot,
    normalizeConsultationType,
    getConsultationTimingForType,
    extractAppointmentScheduleMeta,
    encodeAppointmentQrWithMeta,
    intervalsOverlap,
    getAppointmentOccupiedInterval,
} = require('../config/bookingRulesConfig');

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
    const resolvedFee = (dentistObj.consultation_fee || dentistObj.consultationFee || a.consultation_fee || '').toString().trim();
    const rawMeta = extractAppointmentScheduleMeta(a);
    const treatmentTextLower = String(a.treatment || '').toLowerCase();
    const resolvedConsultationMode = normalizeConsultationType(
        rawMeta.consultationType ||
        a.consultation_type ||
        a.consultationMode ||
        (treatmentTextLower.includes('online') || treatmentTextLower.includes('video') || treatmentTextLower.includes('teleconsult')
            ? 'Online'
            : 'In-Person')
    );
    const timing = getConsultationTimingForType(resolvedConsultationMode);
    const interval = getAppointmentOccupiedInterval(a);
    const resolvedDurationMinutes = Number(rawMeta.durationMinutes || interval?.durationMinutes || timing.durationMinutes);
    const resolvedBufferMinutes = rawMeta.bufferMinutes !== undefined
        ? Number(rawMeta.bufferMinutes)
        : (interval?.bufferMinutes ?? timing.bufferMinutes);
    const startSlotStr = (a.time_slot || a.timeSlot || rawMeta.scheduledStartTime || '').toString().trim();
    const startMins = parseClockSlotMinutes(startSlotStr);
    const scheduledEndTime = rawMeta.scheduledEndTime ||
        interval?.scheduledEndTime ||
        (startMins !== null ? minutesToClockSlot(startMins + resolvedDurationMinutes) : null);
    const bufferEndTime = rawMeta.bufferEndTime ||
        interval?.bufferEndTime ||
        (startMins !== null ? minutesToClockSlot(startMins + resolvedDurationMinutes + resolvedBufferMinutes) : null);
    const delayMinutes = Math.max(
        Number(rawMeta.delayMinutes || 0) || 0,
        Number(rawMeta.estimatedDelayMinutes || 0) || 0,
        Number(interval?.delayMinutes || 0) || 0
    );
    const estimatedStartTime = rawMeta.estimatedStartTime ||
        (delayMinutes > 0 && startMins !== null ? minutesToClockSlot(startMins + delayMinutes) : null);

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
        consultation_fee: resolvedFee,
        consultationFee: resolvedFee,
        consultation_type: resolvedConsultationMode,
        consultationMode: resolvedConsultationMode,
        duration_minutes: resolvedDurationMinutes,
        buffer_minutes: resolvedBufferMinutes,
        scheduled_start_time: startSlotStr || null,
        scheduled_end_time: scheduledEndTime,
        buffer_end_time: bufferEndTime,
        actual_start_at: rawMeta.actualStartAt || null,
        actual_end_at: rawMeta.actualEndAt || null,
        delay_minutes: delayMinutes,
        estimated_start_time: estimatedStartTime,
        finished_early: Boolean(rawMeta.finishedEarly),
        reschedule_request: rawMeta.rescheduleRequest || null,
        patient_delay_choice: rawMeta.patientDelayChoice || null,
        no_show_at: rawMeta.noShowAt || null,
        cancelled_at: rawMeta.cancelledAt || null,
        clinic_id: resolvedClinicId,
        clinic_name: resolvedClinicName,
        booking_created_at: a.created_at || a.booking_created_at || null,
        selectedDoctor: {
            id: a.dentist_id || dentistObj.id || null,
            user_id: dentistObj.user_id || dentistUserObj.id || null,
            name: formattedDocName,
            specialty: resolvedSpecialty,
            qualification: dentistObj.qualifications || dentistObj.qualification || '',
            consultationFee: resolvedFee,
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
    const { dentistId, clinicId, date, timeSlot, treatment, consultationMode, consultationType, patientId, requestId } = req.body;
    try {
        const targetPatientId = patientId || (req.user ? req.user.id : null);
        const requestedDateStr = date ? DoctorAvailability.extractDateYmd(date) : formatLocalYmd(new Date());
        const normalizedSlot = (timeSlot || '').toString().trim();
        if (!normalizedSlot) {
            return res.status(400).json({
                success: false,
                message: 'Please select an available time slot before booking.'
            });
        }

        // 🛡️ Prevent past-date, past-slot, and <30-minute advance bookings on backend
        const advanceCheck = checkSlotBookableForDateYmd(requestedDateStr, normalizedSlot);
        if (!advanceCheck.bookable) {
            return res.status(400).json({
                success: false,
                reason: advanceCheck.reason,
                message: advanceCheck.message
            });
        }

        // Serialize availability verification, unified conflict check, and booking creation per doctor
        const resolvedLockIds = dentistId
            ? await resolveDentistIds(dentistId).catch(() => ({ canonicalId: dentistId }))
            : { canonicalId: null };
        const lockKey = resolvedLockIds.canonicalId || dentistId || targetPatientId || 'default';

        const bookingOutcome = await _withDoctorBookingLock(lockKey, async () => {
            const rules = getBookingRulesConfig();
            const rawModeInput = String(consultationMode || consultationType || '').trim();
            const baseTreatmentInput = (treatment || 'Medical Consultation').toString().trim();
            const timing = getConsultationTimingForType(rawModeInput || baseTreatmentInput, rules);
            const candStartMin = parseClockSlotMinutes(normalizedSlot);
            const candConsultEndMin = candStartMin !== null ? candStartMin + timing.durationMinutes : null;
            const candOccupiedEndMin = candStartMin !== null ? candStartMin + timing.totalBlockedMinutes : null;

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

            // 🛡️ Verify doctor availability publication, working schedule, lunch break, manually blocked slots, and block status
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

                const workingStartTime = avail?.start_time || schedule.startTime || '09:00 AM';
                const workingEndTime = avail?.end_time || schedule.endTime || '05:00 PM';
                const slotInterval = avail?.slot_duration_minutes || schedule.slotIntervalMinutes || schedule.slotDurationMinutes || rules.defaultSlotIntervalMinutes || 30;
                const breakStartTime = schedule.hasBreak ? schedule.breakStartTime : null;
                const breakEndTime = schedule.hasBreak ? schedule.breakEndTime : null;

                const effectiveSlots = hasCustomDateSlots
                    ? avail.slots
                    : (schedule && schedule.isConfigured
                        ? generateTimeSlots(workingStartTime, workingEndTime, slotInterval, breakStartTime, breakEndTime)
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

                // Check break & working-hour boundary when clock times exist
                if (candStartMin !== null && !hasCustomDateSlots) {
                    if (schedule && schedule.isConfigured) {
                        const workStartMin = parseClockSlotMinutes(workingStartTime);
                        const workEndMin = parseClockSlotMinutes(workingEndTime);
                        if (workStartMin !== null && workEndMin !== null && (candStartMin < workStartMin || candConsultEndMin > workEndMin)) {
                            return {
                                errorStatus: 400,
                                errorBody: {
                                    success: false,
                                    message: `The ${timing.consultationType} consultation at ${normalizedSlot} (${timing.durationMinutes} min) falls outside doctor working hours (${workingStartTime} - ${workingEndTime}).`
                                }
                            };
                        }
                    }
                    if (breakStartTime && breakEndTime) {
                        const bStart = parseClockSlotMinutes(breakStartTime);
                        const bEnd = parseClockSlotMinutes(breakEndTime);
                        if (bStart !== null && bEnd !== null && intervalsOverlap(candStartMin, candConsultEndMin, bStart, bEnd)) {
                            return {
                                errorStatus: 400,
                                errorBody: {
                                    success: false,
                                    message: `The time slot (${normalizedSlot}) overlaps with the doctor's break period (${breakStartTime} - ${breakEndTime}).`
                                }
                            };
                        }
                    }
                }

                // Check Admin / Doctor manually blocked individual time slots
                const blockedSlots = await DoctorAvailability.getBlockedSlotsForDate(dentistId, requestedDateStr);
                if (Array.isArray(blockedSlots) && blockedSlots.length > 0) {
                    const blockedMatch = blockedSlots.find(b => {
                        const bStart = b.startMin !== undefined ? Number(b.startMin) : parseClockSlotMinutes(b.startTime || b.slot);
                        const bEnd = b.endMin !== undefined
                            ? Number(b.endMin)
                            : (b.endTime ? parseClockSlotMinutes(b.endTime) : (bStart !== null ? bStart + timing.durationMinutes : null));
                        if (candStartMin !== null && bStart !== null && bEnd !== null) {
                            return intervalsOverlap(candStartMin, candConsultEndMin, bStart, bEnd);
                        }
                        return String(b.startTime || b.slot || '').trim().toLowerCase() === normalizedSlot.toLowerCase();
                    });
                    if (blockedMatch) {
                        return {
                            errorStatus: 409,
                            errorBody: {
                                success: false,
                                isBlocked: true,
                                message: `The time slot (${normalizedSlot}) has been manually blocked (${blockedMatch.reason || 'Unavailable'}). Please select another slot.`
                            }
                        };
                    }
                }
            }

            // 🛡️ Unified cross-type interval & buffer conflict check across doctor's calendar
            if (dentistId) {
                const existingDentistAppts = await Appointment.find({ dentistId });
                const conflictAppt = existingDentistAppts.find(a => {
                    const aStatus = (a.status || '').toUpperCase();
                    if (aStatus === 'CANCELLED' || aStatus === 'REJECTED' || aStatus === 'NO_SHOW') return false;
                    const aDateStr = (a.date || a.appointment_date || '').split('T')[0];
                    if (aDateStr !== requestedDateStr) return false;

                    const occ = getAppointmentOccupiedInterval(a, rules);
                    if (candStartMin !== null && occ) {
                        return intervalsOverlap(candStartMin, candOccupiedEndMin, occ.startMin, occ.occupiedEndMin);
                    }
                    const aSlot = (a.time_slot || a.timeSlot || '').trim();
                    return aSlot.toLowerCase() === normalizedSlot.toLowerCase();
                });
                if (conflictAppt) {
                    const occ = getAppointmentOccupiedInterval(conflictAppt, rules);
                    const detailMsg = occ
                        ? `The time slot (${normalizedSlot}) overlaps with an existing ${occ.consultationType} appointment (${occ.timeSlot} - ${occ.scheduledEndTime}, reserved with ${occ.bufferMinutes}m buffer until ${occ.bufferEndTime}).`
                        : `The time slot (${normalizedSlot}) is already booked for this doctor on this date.`;
                    return {
                        errorStatus: 409,
                        errorBody: {
                            success: false,
                            conflict: true,
                            message: `${detailMsg} Please select another slot.`
                        }
                    };
                }
            }

            if (targetPatientId) {
                const existingPatientAppts = await Appointment.find({ patientId: targetPatientId });
                const patientConflict = existingPatientAppts.find(a => {
                    const aStatus = (a.status || '').toUpperCase();
                    if (aStatus === 'CANCELLED' || aStatus === 'REJECTED' || aStatus === 'NO_SHOW') return false;
                    const aDateStr = (a.date || a.appointment_date || '').split('T')[0];
                    if (aDateStr !== requestedDateStr) return false;
                    const occ = getAppointmentOccupiedInterval(a, rules);
                    if (candStartMin !== null && occ) {
                        return intervalsOverlap(candStartMin, candConsultEndMin, occ.startMin, occ.scheduledEndMin);
                    }
                    const aSlot = (a.time_slot || a.timeSlot || '').trim();
                    return aSlot.toLowerCase() === normalizedSlot.toLowerCase();
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
            let effectiveClinicId = null;
            if (clinicId) {
                const resolvedExplicitClinic = await resolveClinicIds(clinicId);
                effectiveClinicId = resolvedExplicitClinic.clinicId || null;
            }
            if (!effectiveClinicId && resolvedDoctor?.clinic_id) {
                effectiveClinicId = resolvedDoctor.clinic_id;
            }
            if (!effectiveClinicId && resolvedDoctor) {
                const candidateClinicName = (resolvedDoctor.clinics?.clinic_name || resolvedDoctor.clinicName || '').toString().trim();
                const lower = candidateClinicName.toLowerCase();
                if (candidateClinicName && lower !== 'gs health practice' && lower !== 'independent practice') {
                    const matchedClinic = await Clinic.findOne({ clinic_name: candidateClinicName }).catch(() => null);
                    if (matchedClinic?.id) effectiveClinicId = matchedClinic.id;
                }
            }

            const isOnlineBooking = timing.consultationType === 'Online';
            const finalTreatment = (rawModeInput && !baseTreatmentInput.toLowerCase().includes('online') && !baseTreatmentInput.toLowerCase().includes('in-person'))
                ? `${isOnlineBooking ? 'Online' : 'In-Person'} - ${baseTreatmentInput}`
                : baseTreatmentInput;

            const scheduleMeta = {
                consultationType: timing.consultationType,
                durationMinutes: timing.durationMinutes,
                bufferMinutes: timing.bufferMinutes,
                scheduledStartTime: normalizedSlot,
                scheduledEndTime: candConsultEndMin !== null ? minutesToClockSlot(candConsultEndMin) : null,
                bufferEndTime: candOccupiedEndMin !== null ? minutesToClockSlot(candOccupiedEndMin) : null,
                delayMinutes: 0,
            };

            const appointment = await Appointment.create({
                patient_id: targetPatientId,
                dentist_id: effectiveDentistId,
                clinic_id: effectiveClinicId,
                request_id: requestId || null,
                date: date ? new Date(date).toISOString() : new Date().toISOString(),
                time_slot: normalizedSlot,
                treatment: finalTreatment,
                status: 'PENDING',
                qr_code_string: encodeAppointmentQrWithMeta(`DENTAGURU-${targetPatientId || 'PATIENT'}-${Date.now()}`, scheduleMeta)
            });

            // Cross-process race safety check immediately after insert
            if (effectiveDentistId) {
                try {
                    const postInsertAppts = await Appointment.find({ dentistId: effectiveDentistId });
                    const competing = postInsertAppts.filter(a => {
                        if (String(a.id) === String(appointment.id)) return false;
                        const aStatus = (a.status || '').toUpperCase();
                        if (aStatus === 'CANCELLED' || aStatus === 'REJECTED' || aStatus === 'NO_SHOW') return false;
                        const aDateStr = (a.date || a.appointment_date || '').split('T')[0];
                        if (aDateStr !== requestedDateStr) return false;
                        const occ = getAppointmentOccupiedInterval(a, rules);
                        if (candStartMin !== null && occ) {
                            return intervalsOverlap(candStartMin, candOccupiedEndMin, occ.startMin, occ.occupiedEndMin);
                        }
                        return String(a.time_slot || '').trim().toLowerCase() === normalizedSlot.toLowerCase();
                    });
                    if (competing.length > 0) {
                        const myKey = `${appointment.created_at || ''}_${appointment.id}`;
                        const earlierWinner = competing.some(c => `${c.created_at || ''}_${c.id}` < myKey);
                        if (earlierWinner) {
                            await supabaseAdmin.from('appointments').delete().eq('id', appointment.id);
                            return {
                                errorStatus: 409,
                                errorBody: {
                                    success: false,
                                    conflict: true,
                                    message: `The time slot (${normalizedSlot}) was just booked by another patient. Please select another slot.`
                                }
                            };
                        }
                    }
                } catch (_) {}
            }

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
        const resolvedClinicId = enrichedAppt.clinic_id || appointment.clinic_id || null;
        const clinicDisplayName = enrichedAppt.clinic_name || 'GS HEALTH Practice';
        const effectiveTreatment = appointment.treatment || treatment || 'Medical Consultation';

        // 🔔 1. Persistent Notification to Concerned Doctor (Doctor-isolated)
        await Notification.create({
            recipient_role: 'Dentist',
            recipient_id: appointment.dentist_id || dentistId || 'ALL',
            title: 'New Appointment Booking',
            message: `${patientDisplayName} booked an appointment (${effectiveTreatment}) with you on ${requestedDateStr} at ${normalizedSlot}. Status: PENDING.`,
            type: 'appointment_request'
        });

        // 🔔 1b. Persistent Notification to Associated Clinic (ONLY when doctor belongs to a clinic)
        let clinicRecord = null;
        let clinicUser = null;
        if (resolvedClinicId) {
            clinicRecord = await Clinic.findById(resolvedClinicId).catch(() => null);
            if (clinicRecord?.user_id) {
                clinicUser = await User.findById(clinicRecord.user_id).catch(() => null);
            }
            await Notification.create({
                recipient_role: 'Clinic',
                recipient_id: resolvedClinicId,
                title: 'New Appointment Booking',
                message: `${patientDisplayName} booked an appointment with ${doctorDisplayName} on ${requestedDateStr} at ${normalizedSlot}. Status: PENDING.`,
                type: 'clinic_appointment_booked'
            });
        }

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

        // 🔔 4. Push & External Mobile Alerts (without simulating external SMS/WhatsApp delivery)
        let doctorExternalAlert = { success: false, providerConfigured: isWhatsAppProviderConfigured(), whatsappStatus: 'NotAttempted' };
        let clinicExternalAlert = { success: false, providerConfigured: isWhatsAppProviderConfigured(), whatsappStatus: 'NotAttempted' };
        try {
            const targetDocId = appointment.dentist_id || dentistId;
            if (targetDocId) {
                const docRec = await Dentist.findById(targetDocId).catch(() => null);
                const docUser = docRec?.users || (docRec?.user_id ? await User.findById(docRec.user_id).catch(() => null) : null);
                const docPhone = docUser?.phone || docRec?.phone || '';
                if (docUser?.device_token && !String(docUser.device_token).startsWith('{')) {
                    await sendPushNotification(
                        docUser.device_token,
                        'New Appointment Booking',
                        `${patientDisplayName} booked an appointment on ${requestedDateStr} at ${normalizedSlot}.`,
                        { appointmentId: String(appointment.id), type: 'appointment_request' }
                    );
                }
                if (docPhone) {
                    doctorExternalAlert = await sendDoctorBookingAlert({
                        doctorPhone: docPhone,
                        doctorName: doctorDisplayName,
                        patientName: patientDisplayName,
                        appointmentDate: requestedDateStr,
                        appointmentTime: normalizedSlot,
                        appointmentType: effectiveTreatment,
                        bookingId: String(appointment.id)
                    });
                }
            }
            if (resolvedClinicId) {
                const clinicPhone = clinicRecord?.phone || clinicUser?.phone || '';
                if (clinicUser?.device_token && !String(clinicUser.device_token).startsWith('{')) {
                    await sendPushNotification(
                        clinicUser.device_token,
                        'New Appointment Booking',
                        `${patientDisplayName} booked with ${doctorDisplayName} on ${requestedDateStr} at ${normalizedSlot}.`,
                        { appointmentId: String(appointment.id), clinicId: String(resolvedClinicId), type: 'clinic_appointment_booked' }
                    );
                }
                if (clinicPhone) {
                    clinicExternalAlert = await sendClinicBookingAlert({
                        clinicPhone,
                        clinicName: clinicDisplayName,
                        doctorName: doctorDisplayName,
                        patientName: patientDisplayName,
                        appointmentDate: requestedDateStr,
                        appointmentTime: normalizedSlot,
                        bookingId: String(appointment.id)
                    });
                }
            }
        } catch (extErr) {
            console.warn('⚠️ External booking notification dispatch notice:', extErr.message);
        }

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
            appointment: enrichedAppt,
            notificationStatus: {
                inAppClinicNotified: Boolean(resolvedClinicId),
                inAppDoctorNotified: true,
                externalSmsWhatsappConfigured: isWhatsAppProviderConfigured(),
                doctorExternalAlert,
                clinicExternalAlert
            }
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

        const callerRoleLower = (req.user?.role || '').toString().trim().toLowerCase();
        const isCallerClinic = callerRoleLower === 'clinic' || callerRoleLower === 'clinic_admin';

        if (isCallerClinic) {
            // Strict clinic RBAC isolation: clinic user can only read bookings of its own clinic
            const resolvedClinic = await resolveClinicRecordAndDoctorIds(req.user.id);
            if (!resolvedClinic.clinicId) {
                return res.json({ success: true, count: 0, appointments: [] });
            }
            query.clinic_id = resolvedClinic.clinicId;
            query.clinic_dentist_ids = resolvedClinic.doctorIds;
        } else if (clinicId) {
            const resolvedClinic = await resolveClinicRecordAndDoctorIds(clinicId);
            if (!resolvedClinic.clinicId) {
                return res.json({ success: true, count: 0, appointments: [] });
            }
            query.clinic_id = resolvedClinic.clinicId;
            query.clinic_dentist_ids = resolvedClinic.doctorIds;
        }

        const isAdmin = req.user && (callerRoleLower === 'admin' || callerRoleLower === 'sub-admin' || callerRoleLower === 'subadmin' || callerRoleLower === 'superadmin' || callerRoleLower === 'primaryadmin');
        if (!isAdmin && !patientId && !dentistId && !clinicId && !req.user) {
            return res.json({ success: true, count: 0, appointments: [] });
        }

        const rawList = await Appointment.find(query);
        const allReferrals = await Referral.find().catch(() => []);
        const referralByApptId = new Map();
        for (const r of (allReferrals || [])) {
            if (r?.appointment_id) referralByApptId.set(String(r.appointment_id), r);
        }

        const enrichedList = await Promise.all(rawList.map(async (a) => {
            const enriched = enrichAppointmentRecord(a);
            const linkedRef = referralByApptId.get(String(a.id));
            if (linkedRef) {
                enriched.referral_id = linkedRef.id;
                enriched.referral_source = linkedRef.referrer_patient_name || 'Patient Referral';
            }
            if (!enriched.dentist_name && a && a.dentist_id) {
                try {
                    const doc = await Dentist.findById(a.dentist_id).catch(() => null)
                        || await Dentist.findOne({ user_id: a.dentist_id }).catch(() => null);
                    const user = doc?.users || (doc?.user_id ? await User.findById(doc.user_id).catch(() => null) : null)
                        || await User.findById(a.dentist_id).catch(() => null);
                    const fallbackName = (user?.name || doc?.name || '').toString().trim();
                    if (fallbackName) {
                        const formatted = (fallbackName.toLowerCase().startsWith('dr.') || fallbackName.toLowerCase().startsWith('dr '))
                            ? fallbackName
                            : `Dr. ${fallbackName}`;
                        enriched.dentist_name = formatted;
                        if (enriched.selectedDoctor) {
                            enriched.selectedDoctor.name = formatted;
                            if (!enriched.selectedDoctor.specialty && (doc?.speciality || doc?.specialty)) {
                                enriched.selectedDoctor.specialty = doc.speciality || doc.specialty;
                                enriched.doctor_specialty = enriched.selectedDoctor.specialty;
                            }
                        }
                    }
                } catch (_) {}
            }
            return enriched;
        }));

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

        const confirmedClinicId = enriched.clinic_id || appointment.clinic_id;
        if (confirmedClinicId) {
            await Notification.create({
                recipient_role: 'Clinic',
                recipient_id: confirmedClinicId,
                title: 'Appointment Confirmed',
                message: `${docName} confirmed visit for ${patName} (${apptDateStr} at ${appointment.time_slot}).`,
                type: 'clinic_appointment_confirmed'
            });
        }

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

// 5. RESCHEDULE APPOINTMENT [-> RESCHEDULED: Unified conflict + buffer + blocked slot protection]
exports.rescheduleAppointment = async (req, res) => {
    const { id } = req.params;
    const { date, timeSlot } = req.body;
    try {
        const appointment = await Appointment.findById(id);
        if (!appointment) {
            return res.status(404).json({ success: false, message: 'Appointment not found.' });
        }

        if (req.user) {
            const role = (req.user.role || '').toLowerCase();
            const isSystemAdmin = role === 'admin' || role === 'super_admin' || role === 'superadmin' || role === 'sub-admin' || role === 'subadmin';
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

        const newDateStr = date ? DoctorAvailability.extractDateYmd(date) : (appointment.date ? DoctorAvailability.extractDateYmd(appointment.date) : '');
        const newSlot = (timeSlot || appointment.time_slot || '').trim();
        const reschedCheck = checkSlotBookableForDateYmd(newDateStr, newSlot);
        if (!reschedCheck.bookable) {
            return res.status(400).json({
                success: false,
                reason: reschedCheck.reason,
                message: reschedCheck.message
            });
        }

        const lockKey = appointment.dentist_id || id;
        const outcome = await _withDoctorBookingLock(lockKey, async () => {
            const rules = getBookingRulesConfig();
            const prevMeta = extractAppointmentScheduleMeta(appointment);
            const mode = normalizeConsultationType(prevMeta.consultationType || appointment.consultation_type, appointment.treatment || '');
            const timing = getConsultationTimingForType(mode, rules);
            const candStart = parseClockSlotMinutes(newSlot);
            const candConsultEnd = candStart !== null ? candStart + timing.durationMinutes : null;
            const candOccupiedEnd = candStart !== null ? candStart + timing.totalBlockedMinutes : null;

            if (appointment.dentist_id) {
                const resolvedDoctor = await Dentist.findById(appointment.dentist_id).catch(() => null);
                if (resolvedDoctor && !isDoctorRecordAvailable(resolvedDoctor)) {
                    return {
                        errorStatus: 409,
                        errorBody: { success: false, message: 'Doctor is currently unavailable for rescheduling.' }
                    };
                }
                const avail = await DoctorAvailability.findOne({ dentist_id: appointment.dentist_id, date: newDateStr });
                if (avail && avail.is_blocked) {
                    return {
                        errorStatus: 409,
                        errorBody: { success: false, isBlocked: true, message: `Doctor is unavailable on ${newDateStr} (${avail.blocked_reason || 'Blocked'}).` }
                    };
                }
                const blockedSlots = await DoctorAvailability.getBlockedSlotsForDate(appointment.dentist_id, newDateStr);
                if (Array.isArray(blockedSlots) && blockedSlots.length > 0 && candStart !== null) {
                    const hitBlock = blockedSlots.find(b => {
                        const bStart = b.startMin !== undefined ? Number(b.startMin) : parseClockSlotMinutes(b.startTime || b.slot);
                        const bEnd = b.endMin !== undefined ? Number(b.endMin) : (b.endTime ? parseClockSlotMinutes(b.endTime) : (bStart !== null ? bStart + timing.durationMinutes : null));
                        return bStart !== null && bEnd !== null && intervalsOverlap(candStart, candConsultEnd, bStart, bEnd);
                    });
                    if (hitBlock) {
                        return {
                            errorStatus: 409,
                            errorBody: { success: false, isBlocked: true, message: `The time slot (${newSlot}) is blocked (${hitBlock.reason || 'Unavailable'}).` }
                        };
                    }
                }

                const existingDentistAppts = await Appointment.find({ dentistId: appointment.dentist_id });
                const conflict = existingDentistAppts.find(a => {
                    if (String(a.id) === String(id)) return false;
                    const aStatus = (a.status || '').toUpperCase();
                    if (aStatus === 'CANCELLED' || aStatus === 'REJECTED' || aStatus === 'NO_SHOW') return false;
                    const aDateStr = (a.date || a.appointment_date || '').split('T')[0];
                    if (aDateStr !== newDateStr) return false;
                    const occ = getAppointmentOccupiedInterval(a, rules);
                    if (candStart !== null && occ) {
                        return intervalsOverlap(candStart, candOccupiedEnd, occ.startMin, occ.occupiedEndMin);
                    }
                    const aSlot = (a.time_slot || a.timeSlot || '').trim();
                    return aSlot.toLowerCase() === newSlot.toLowerCase();
                });
                if (conflict) {
                    return {
                        errorStatus: 409,
                        errorBody: {
                            success: false,
                            conflict: true,
                            message: `The time slot (${newSlot}) overlaps with another consultation or buffer period for this doctor.`
                        }
                    };
                }
            }

            const nextMeta = {
                consultationType: timing.consultationType,
                durationMinutes: timing.durationMinutes,
                bufferMinutes: timing.bufferMinutes,
                scheduledStartTime: newSlot,
                scheduledEndTime: candConsultEnd !== null ? minutesToClockSlot(candConsultEnd) : null,
                bufferEndTime: candOccupiedEnd !== null ? minutesToClockSlot(candOccupiedEnd) : null,
                delayMinutes: 0,
                estimatedDelayMinutes: 0,
                estimatedStartTime: null,
                ...(prevMeta.rescheduleRequest
                    ? { rescheduleRequest: { ...prevMeta.rescheduleRequest, status: 'APPROVED', resolvedAt: new Date().toISOString() } }
                    : {}),
            };

            await Appointment.findByIdAndUpdate(id, {
                date: date ? new Date(date).toISOString() : appointment.date,
                time_slot: newSlot,
                status: 'RESCHEDULED',
                qr_code_string: encodeAppointmentQrWithMeta(appointment.qr_code_string, nextMeta),
            });
            return { nextMeta };
        });

        if (outcome.errorStatus) {
            return res.status(outcome.errorStatus).json(outcome.errorBody);
        }

        const fullAppt = await Appointment.findById(id).catch(() => null);
        const enriched = enrichAppointmentRecord(fullAppt || {
            ...appointment,
            date: date ? new Date(date).toISOString() : appointment.date,
            time_slot: newSlot,
            status: 'RESCHEDULED'
        });
        const docName = enriched.dentist_name || 'Doctor';
        const patName = enriched.patient_name || 'Patient';

        await Notification.create({
            recipient_role: 'Patient',
            recipient_id: appointment.patient_id || 'ALL',
            title: '📅 Rescheduling confirmation',
            message: `Your appointment with ${docName} is confirmed for ${newDateStr} at ${newSlot}.`,
            type: 'appointment_rescheduled'
        });

        if (appointment.dentist_id) {
            await Notification.create({
                recipient_role: 'Dentist',
                recipient_id: appointment.dentist_id,
                title: '📅 Rescheduling confirmation',
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
                '📅 Rescheduling confirmation',
                `Your appointment has been rescheduled to ${newDateStr} at ${newSlot}.`,
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

        await Appointment.findByIdAndUpdate(id, {
            status: 'CANCELLED',
            qr_code_string: encodeAppointmentQrWithMeta(appointment.qr_code_string, {
                cancelledAt: new Date().toISOString(),
            }),
        });
        const prevApptStatus = String(appointment.status || '').trim().toUpperCase();
        if ((prevApptStatus === 'IN_PROGRESS' || prevApptStatus === 'DELAYED') && appointment.dentist_id) {
            await _updateDoctorLiveStatus(appointment.dentist_id, 'Available');
        }
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

        const cancelledClinicId = enriched.clinic_id || appointment.clinic_id;
        if (cancelledClinicId) {
            await Notification.create({
                recipient_role: 'Clinic',
                recipient_id: cancelledClinicId,
                title: 'Appointment Cancelled',
                message: `Appointment for ${patName} with ${docName} (${apptDateStr} at ${appointment.time_slot}) was cancelled.`,
                type: 'clinic_appointment_cancelled'
            });
        }

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

// Helper: Persist Doctor Live Presence / Consultation Status
async function _updateDoctorLiveStatus(dentistId, liveStatus) {
    if (!dentistId || !liveStatus) return;
    try {
        const doc = await Dentist.findById(dentistId).catch(() => null);
        if (!doc) return;
        const curr = String(doc.availability_status || '').trim().toLowerCase();
        // Do not accidentally override Offline / Unavailable with Available
        if (liveStatus === 'Available' && (curr === 'unavailable' || curr === 'offline')) {
            return;
        }
        await Dentist.findByIdAndUpdate(doc.id, { availability_status: liveStatus });
        if (doc.user_id) {
            const docUser = await User.findById(doc.user_id).catch(() => null);
            let meta = {};
            if (docUser?.device_token && typeof docUser.device_token === 'string' && docUser.device_token.trim().startsWith('{')) {
                try { meta = JSON.parse(docUser.device_token); } catch (_) {}
            }
            meta.onlineStatus = liveStatus;
            await User.findByIdAndUpdate(doc.user_id, { device_token: JSON.stringify(meta) });
        }
    } catch (e) {
        console.warn('⚠️ _updateDoctorLiveStatus notice:', e.message);
    }
}

function _isStaffAuthorizedForAppointment(req, appointment) {
    if (!req.user) return true;
    const role = (req.user.role || '').toString().trim().toLowerCase();
    if (role === 'patient') return false;
    if (role === 'admin' || role === 'super_admin' || role === 'superadmin' || role === 'sub-admin' || role === 'subadmin' || role === 'primaryadmin') {
        return true;
    }
    const callerId = String(req.user.id || '').trim();
    if (role === 'dentist' || role === 'doctor') {
        return callerId === String(appointment.dentist_id || '').trim() ||
            callerId === String(appointment.dentist?.user_id || '').trim();
    }
    if (role === 'clinic' || role === 'clinic_admin') {
        return true;
    }
    return false;
}

// 7. DENTIST: COMPLETE CONSULTATION [CONFIRMED / IN_PROGRESS / DELAYED -> COMPLETED]
exports.completeConsultation = async (req, res) => {
    const { id } = req.params;
    const { symptoms, diagnosis, treatmentNotes, treatmentPlan, followUpDate, prescriptions, attachments, actualEndAt } = req.body;
    try {
        const appointment = await Appointment.findById(id);
        if (!appointment) {
            return res.status(404).json({ success: false, message: 'Appointment not found.' });
        }
        if (!_isStaffAuthorizedForAppointment(req, appointment)) {
            return res.status(403).json({ success: false, message: 'Forbidden: Only authorized clinical staff or Admin can complete a consultation.' });
        }

        const rules = getBookingRulesConfig();
        const completedAtIso = actualEndAt ? new Date(actualEndAt).toISOString() : new Date().toISOString();
        const interval = getAppointmentOccupiedInterval({
            ...appointment,
            status: 'COMPLETED',
            qr_code_string: encodeAppointmentQrWithMeta(appointment.qr_code_string, { actualEndAt: completedAtIso }),
        }, rules);
        const completedParts = getNowPartsInTimezone(new Date(completedAtIso), rules.timezone);
        const finishedEarly = Boolean(
            interval &&
            completedParts.totalMinutes >= interval.startMin &&
            completedParts.totalMinutes < interval.scheduledEndMin
        );

        const nextMeta = {
            actualEndAt: completedAtIso,
            finishedEarly,
            delayMinutes: 0,
        };

        // 1. Mark Appointment Status COMPLETED with actualEndAt & early-finish detection
        await Appointment.findByIdAndUpdate(id, {
            status: 'COMPLETED',
            qr_code_string: encodeAppointmentQrWithMeta(appointment.qr_code_string, nextMeta),
        });
        if (appointment.dentist_id) {
            await _updateDoctorLiveStatus(appointment.dentist_id, 'Available');
        }
        const fullAppt = await Appointment.findById(id).catch(() => null);
        const enriched = enrichAppointmentRecord(fullAppt || {
            ...appointment,
            status: 'COMPLETED',
            qr_code_string: encodeAppointmentQrWithMeta(appointment.qr_code_string, nextMeta),
        });
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
            message: `${docName} completed consultation for ${patName}${finishedEarly ? ' (finished early — upcoming slot buffer updated)' : ''}.`,
            type: 'admin_consultation_completed'
        });

        const completedClinicId = enriched.clinic_id || appointment.clinic_id;
        if (completedClinicId) {
            await Notification.create({
                recipient_role: 'Clinic',
                recipient_id: completedClinicId,
                title: 'Consultation Completed',
                message: `${docName} completed consultation for ${patName}.`,
                type: 'clinic_consultation_completed'
            });
        }

        // Notify next queued confirmed patient on same day that doctor is available / ready soon
        if (appointment.dentist_id && interval) {
            try {
                const apptDateYmd = (appointment.date || appointment.appointment_date || '').split('T')[0];
                const sameDocAppts = await Appointment.find({ dentistId: appointment.dentist_id });
                const nextUp = sameDocAppts
                    .filter(a => String(a.id) !== String(id))
                    .filter(a => ['CONFIRMED', 'PENDING', 'RESCHEDULED', 'DELAYED'].includes(String(a.status || '').toUpperCase()))
                    .filter(a => (a.date || a.appointment_date || '').split('T')[0] === apptDateYmd)
                    .map(a => ({ appt: a, startMin: parseClockSlotMinutes(a.time_slot || a.timeSlot) }))
                    .filter(x => x.startMin !== null && x.startMin >= interval.startMin)
                    .sort((x, y) => x.startMin - y.startMin)[0];

                if (nextUp?.appt?.patient_id && finishedEarly) {
                    await Notification.create({
                        recipient_role: 'Patient',
                        recipient_id: nextUp.appt.patient_id,
                        title: '🩺 Doctor ready to start',
                        message: `${docName} finished the previous consultation early and is available for your ${nextUp.appt.time_slot} visit.`,
                        type: 'doctor_ready_to_start'
                    });
                }
            } catch (_) {}
        }

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
            finishedEarly,
            doctorStatus: 'Available',
            appointment: enriched,
            record: newRecord
        });
    } catch (err) {
        console.error('Complete Consultation Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to complete consultation.' });
    }
};

// 7B. START CONSULTATION [-> IN_PROGRESS & Busy – Online/In-Person Consultation]
exports.startConsultation = async (req, res) => {
    const { id } = req.params;
    try {
        const appointment = await Appointment.findById(id);
        if (!appointment) {
            return res.status(404).json({ success: false, message: 'Appointment not found.' });
        }
        if (!_isStaffAuthorizedForAppointment(req, appointment)) {
            return res.status(403).json({ success: false, message: 'Forbidden: Only assigned Doctor or Admin can start consultation.' });
        }

        const prevMeta = extractAppointmentScheduleMeta(appointment);
        const mode = normalizeConsultationType(
            prevMeta.consultationType || appointment.consultation_type,
            appointment.treatment || ''
        );
        const doctorBusyStatus = mode === 'Online'
            ? 'Busy – Online Consultation'
            : 'Busy – In-Person Consultation';
        const actualStartIso = req.body?.actualStartAt
            ? new Date(req.body.actualStartAt).toISOString()
            : new Date().toISOString();

        const nextQr = encodeAppointmentQrWithMeta(appointment.qr_code_string, {
            actualStartAt: actualStartIso,
            consultationType: mode,
        });

        await Appointment.findByIdAndUpdate(id, {
            status: 'IN_PROGRESS',
            qr_code_string: nextQr,
        });
        if (appointment.dentist_id) {
            await _updateDoctorLiveStatus(appointment.dentist_id, doctorBusyStatus);
        }

        const fullAppt = await Appointment.findById(id).catch(() => null);
        const enriched = enrichAppointmentRecord(fullAppt || {
            ...appointment,
            status: 'IN_PROGRESS',
            qr_code_string: nextQr,
        });
        const docName = enriched.dentist_name || 'your doctor';

        if (appointment.patient_id) {
            await Notification.create({
                recipient_role: 'Patient',
                recipient_id: appointment.patient_id,
                title: '🩺 Doctor ready to start',
                message: `${docName} has started your ${mode} consultation (${appointment.time_slot}).`,
                type: 'doctor_ready_to_start'
            });
        }

        res.json({
            success: true,
            message: `Consultation started. Doctor status updated to ${doctorBusyStatus}.`,
            doctorStatus: doctorBusyStatus,
            appointment: enriched,
        });
    } catch (err) {
        console.error('Start Consultation Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to start consultation.' });
    }
};

// 7C. MARK CONSULTATION DELAYED [-> DELAYED, notifies next patient + Admin threshold alert, never auto-cancels]
exports.markConsultationDelayed = async (req, res) => {
    const { id } = req.params;
    try {
        const appointment = await Appointment.findById(id);
        if (!appointment) {
            return res.status(404).json({ success: false, message: 'Appointment not found.' });
        }
        if (!_isStaffAuthorizedForAppointment(req, appointment)) {
            return res.status(403).json({ success: false, message: 'Forbidden: Only assigned Doctor or Admin can mark delay.' });
        }

        const rules = getBookingRulesConfig();
        const interval = getAppointmentOccupiedInterval(appointment, rules);
        const requestedDelay = req.body?.delayMinutes !== undefined ? Number(req.body.delayMinutes) : null;
        let delayMinutes = requestedDelay !== null && !Number.isNaN(requestedDelay)
            ? Math.max(1, Math.round(requestedDelay))
            : 15;
        if (requestedDelay === null && interval) {
            const nowParts = getNowPartsInTimezone(new Date(), rules.timezone);
            const apptDateStr = (appointment.date || appointment.appointment_date || '').split('T')[0];
            if (apptDateStr === nowParts.ymd && nowParts.totalMinutes > interval.scheduledEndMin) {
                delayMinutes = Math.max(5, nowParts.totalMinutes - interval.scheduledEndMin);
            }
        }

        const delayedQr = encodeAppointmentQrWithMeta(appointment.qr_code_string, {
            delayMinutes,
            delayMarkedAt: new Date().toISOString(),
        });
        await Appointment.findByIdAndUpdate(id, {
            status: 'DELAYED',
            qr_code_string: delayedQr,
        });
        if (appointment.dentist_id) {
            await _updateDoctorLiveStatus(appointment.dentist_id, 'Delayed');
        }

        const fullAppt = await Appointment.findById(id).catch(() => null);
        const enriched = enrichAppointmentRecord(fullAppt || {
            ...appointment,
            status: 'DELAYED',
            qr_code_string: delayedQr,
        });
        const docName = enriched.dentist_name || 'Doctor';
        const patName = enriched.patient_name || 'Patient';

        // Find next confirmed/pending appointment on the same calendar date & update its ETA without cancelling/moving it
        let nextAppointment = null;
        const apptDateYmd = (appointment.date || appointment.appointment_date || '').split('T')[0];
        if (appointment.dentist_id) {
            const allDocAppts = await Appointment.find({ dentistId: appointment.dentist_id });
            const curStartMin = parseClockSlotMinutes(appointment.time_slot || appointment.timeSlot) ?? -1;
            const candidates = allDocAppts
                .filter(a => String(a.id) !== String(id))
                .filter(a => {
                    const st = String(a.status || '').toUpperCase();
                    if (st === 'CANCELLED' || st === 'REJECTED' || st === 'COMPLETED' || st === 'NO_SHOW') return false;
                    return (a.date || a.appointment_date || '').split('T')[0] === apptDateYmd;
                })
                .map(a => ({ appt: a, startMin: parseClockSlotMinutes(a.time_slot || a.timeSlot) }))
                .filter(x => x.startMin !== null && x.startMin > curStartMin)
                .sort((a, b) => a.startMin - b.startMin);

            if (candidates.length > 0) {
                const nextRec = candidates[0].appt;
                const nextStartMin = candidates[0].startMin;
                const updatedEta = minutesToClockSlot(nextStartMin + delayMinutes);
                const nextQr = encodeAppointmentQrWithMeta(nextRec.qr_code_string, {
                    estimatedDelayMinutes: delayMinutes,
                    delayMinutes,
                    estimatedStartTime: updatedEta,
                    delayedByAppointmentId: String(id),
                    patientDelayOptions: ['WAIT', 'REQUEST_RESCHEDULE', 'SWITCH_DOCTOR'],
                });
                // Preserve confirmed status — NEVER auto-cancel or move confirmed booking
                await Appointment.findByIdAndUpdate(nextRec.id, { qr_code_string: nextQr });
                nextAppointment = enrichAppointmentRecord({ ...nextRec, qr_code_string: nextQr });

                if (nextRec.patient_id) {
                    await Notification.create({
                        recipient_role: 'Patient',
                        recipient_id: nextRec.patient_id,
                        title: '⏱️ Doctor running late',
                        message: `${docName} is running ${delayMinutes} minutes late. Your ${nextRec.time_slot} appointment remains active; you can Wait, Request Reschedule, or Switch Doctor.`,
                        type: 'doctor_running_late'
                    });
                    await Notification.create({
                        recipient_role: 'Patient',
                        recipient_id: nextRec.patient_id,
                        title: '🕒 Updated estimated consultation time',
                        message: `Updated estimated consultation time with ${docName}: ${updatedEta} (~${delayMinutes} min delay).`,
                        type: 'estimated_time_updated'
                    });
                }
            }
        }

        const adminAlertTriggered = delayMinutes >= rules.adminDelayAlertThresholdMinutes;
        if (adminAlertTriggered) {
            await Notification.create({
                recipient_role: 'Admin',
                recipient_id: 'ALL_ADMINS',
                title: '⚠️ Doctor Consultation Delay Alert',
                message: `${docName} is delayed by ${delayMinutes} mins on ${patName}'s ${appointment.time_slot} (${enriched.consultationMode}) visit.${nextAppointment ? ` Next patient notified (ETA ${nextAppointment.estimated_start_time}).` : ''}`,
                type: 'admin_doctor_delay_alert'
            });
        }

        res.json({
            success: true,
            message: `Consultation marked delayed by ${delayMinutes} minutes.`,
            delayMinutes,
            doctorStatus: 'Delayed',
            adminAlertTriggered,
            appointment: enriched,
            nextAppointment,
        });
    } catch (err) {
        console.error('Mark Delay Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to mark consultation delay.' });
    }
};

// 7D. MARK PATIENT NO-SHOW [-> NO_SHOW, releases slot + resets Doctor to Available]
exports.markPatientNoShow = async (req, res) => {
    const { id } = req.params;
    try {
        const appointment = await Appointment.findById(id);
        if (!appointment) {
            return res.status(404).json({ success: false, message: 'Appointment not found.' });
        }
        if (!_isStaffAuthorizedForAppointment(req, appointment)) {
            return res.status(403).json({ success: false, message: 'Forbidden: Only assigned Doctor or Admin can mark patient no-show.' });
        }

        const noShowQr = encodeAppointmentQrWithMeta(appointment.qr_code_string, {
            noShowAt: new Date().toISOString(),
            delayMinutes: 0,
        });
        await Appointment.findByIdAndUpdate(id, {
            status: 'NO_SHOW',
            qr_code_string: noShowQr,
        });
        if (appointment.dentist_id) {
            await _updateDoctorLiveStatus(appointment.dentist_id, 'Available');
        }

        const fullAppt = await Appointment.findById(id).catch(() => null);
        const enriched = enrichAppointmentRecord(fullAppt || {
            ...appointment,
            status: 'NO_SHOW',
            qr_code_string: noShowQr,
        });

        if (appointment.patient_id) {
            await Notification.create({
                recipient_role: 'Patient',
                recipient_id: appointment.patient_id,
                title: '⚠️ Missed Appointment (No-Show)',
                message: `Your ${appointment.time_slot} consultation with ${enriched.dentist_name || 'your doctor'} was marked No-Show.`,
                type: 'appointment_no_show'
            });
        }

        res.json({
            success: true,
            message: 'Appointment marked as Patient No-Show and slot released.',
            doctorStatus: 'Available',
            appointment: enriched,
        });
    } catch (err) {
        res.status(500).json({ success: false, message: 'Failed to mark patient no-show.' });
    }
};

// 7E. PATIENT RESPONSE TO DELAY (Wait / Request Reschedule / Switch Doctor — never alters confirmed bookings)
exports.submitPatientDelayResponse = async (req, res) => {
    const { id } = req.params;
    const { action, choice, requestedDate, requestedTimeSlot, reason } = req.body;
    try {
        const appointment = await Appointment.findById(id);
        if (!appointment) {
            return res.status(404).json({ success: false, message: 'Appointment not found.' });
        }
        const normalizedAction = String(action || choice || (requestedDate || requestedTimeSlot ? 'REQUEST_RESCHEDULE' : 'WAIT'))
            .trim()
            .toUpperCase();
        if (!['WAIT', 'REQUEST_RESCHEDULE', 'SWITCH_DOCTOR'].includes(normalizedAction)) {
            return res.status(400).json({
                success: false,
                message: 'Valid delay response action required: WAIT, REQUEST_RESCHEDULE, or SWITCH_DOCTOR.'
            });
        }

        const prevMeta = extractAppointmentScheduleMeta(appointment);
        const nextMetaUpdate = {
            patientDelayChoice: normalizedAction,
            patientDelayRespondedAt: new Date().toISOString(),
        };
        if (normalizedAction === 'REQUEST_RESCHEDULE') {
            nextMetaUpdate.rescheduleRequest = {
                status: 'PENDING',
                requestedDate: requestedDate || null,
                requestedTimeSlot: requestedTimeSlot || null,
                reason: String(reason || 'Requested reschedule due to schedule change').trim(),
                requestedAt: new Date().toISOString(),
            };
        }

        const updatedQr = encodeAppointmentQrWithMeta(appointment.qr_code_string, nextMetaUpdate);
        await Appointment.findByIdAndUpdate(id, { qr_code_string: updatedQr });

        const fullAppt = await Appointment.findById(id).catch(() => null);
        const enriched = enrichAppointmentRecord(fullAppt || {
            ...appointment,
            qr_code_string: updatedQr,
        });

        if (normalizedAction === 'REQUEST_RESCHEDULE') {
            await Notification.create({
                recipient_role: 'Admin',
                recipient_id: 'ALL_ADMINS',
                title: '📅 Pending Reschedule Request',
                message: `${enriched.patient_name || 'Patient'} requested rescheduling for ${enriched.dentist_name || 'Doctor'} (${appointment.time_slot}${requestedTimeSlot ? ` -> ${requestedTimeSlot}` : ''}).`,
                type: 'reschedule_request'
            });
            if (appointment.dentist_id) {
                await Notification.create({
                    recipient_role: 'Dentist',
                    recipient_id: appointment.dentist_id,
                    title: '📅 Patient Requested Reschedule',
                    message: `${enriched.patient_name || 'Patient'} requested to reschedule ${appointment.time_slot}.`,
                    type: 'reschedule_request'
                });
            }
        }

        let alternateDoctors = [];
        if (normalizedAction === 'SWITCH_DOCTOR') {
            const docs = await Dentist.find({}).catch(() => []);
            const targetSpec = String(enriched.doctor_specialty || prevMeta.specialty || '').trim().toLowerCase();
            alternateDoctors = docs
                .filter(d => String(d.id) !== String(appointment.dentist_id) && isDoctorRecordAvailable(d))
                .filter(d => !targetSpec || String(d.speciality || d.specialty || '').toLowerCase().includes(targetSpec))
                .slice(0, 10)
                .map(d => ({
                    id: d.id,
                    name: d.users?.name || d.name || 'Doctor',
                    specialty: d.speciality || d.specialty || 'General Medicine',
                    availability_status: d.availability_status || 'Available',
                }));
        }

        res.json({
            success: true,
            action: normalizedAction,
            appointment: enriched,
            alternateDoctors,
            message: normalizedAction === 'WAIT'
                ? 'Confirmed appointment preserved. You are queued to wait.'
                : normalizedAction === 'REQUEST_RESCHEDULE'
                    ? 'Reschedule request submitted without altering your confirmed booking.'
                    : 'Available alternate specialists retrieved.',
        });
    } catch (err) {
        console.error('Delay Response Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to record response.' });
    }
};

// 7F. LIVE SCHEDULING MONITOR FOR ADMIN DASHBOARD
exports.getLiveSchedulingStatus = async (req, res) => {
    try {
        const rules = getBookingRulesConfig();
        const now = new Date();
        const nowParts = getNowPartsInTimezone(now, rules.timezone);
        const filterDate = req.query.date ? DoctorAvailability.extractDateYmd(req.query.date) : null;

        const [allDoctors, rawAppts] = await Promise.all([
            Dentist.find({}).catch(() => []),
            Appointment.find({}).catch(() => []),
        ]);
        const enrichedAppts = (rawAppts || []).map(enrichAppointmentRecord);

        const pendingRescheduleRequests = enrichedAppts
            .filter(a => a.reschedule_request && String(a.reschedule_request.status || '').toUpperCase() === 'PENDING')
            .map(a => ({
                appointmentId: a.id,
                patientName: a.patient_name || 'Patient',
                doctorId: a.dentist_id || null,
                doctorName: a.dentist_name || 'Doctor',
                currentDate: (a.date || '').split('T')[0],
                currentTimeSlot: a.time_slot || '',
                consultationType: a.consultationMode || 'In-Person',
                requestedDate: a.reschedule_request.requestedDate || null,
                requestedTimeSlot: a.reschedule_request.requestedTimeSlot || null,
                reason: a.reschedule_request.reason || '',
                requestedAt: a.reschedule_request.requestedAt || null,
            }));

        const doctorsSummary = (allDoctors || []).map(doc => {
            const docAppts = enrichedAppts.filter(a => {
                const st = String(a.status || '').toUpperCase();
                if (st === 'CANCELLED' || st === 'REJECTED' || st === 'NO_SHOW') return false;
                const dId = String(a.dentist_id || '');
                const matches = dId === String(doc.id) || (doc.user_id && dId === String(doc.user_id));
                if (!matches) return false;
                if (filterDate) {
                    return (a.date || '').split('T')[0] === filterDate;
                }
                return true;
            });

            docAppts.sort((a, b) => {
                const da = (a.date || '').split('T')[0];
                const db = (b.date || '').split('T')[0];
                if (da !== db) return da.localeCompare(db);
                const ma = parseClockSlotMinutes(a.time_slot || '') ?? 9999;
                const mb = parseClockSlotMinutes(b.time_slot || '') ?? 9999;
                return ma - mb;
            });

            const activeCurrent = docAppts.find(a => ['IN_PROGRESS', 'DELAYED'].includes(String(a.status || '').toUpperCase())) ||
                docAppts.find(a => ['CONFIRMED', 'PENDING', 'RESCHEDULED'].includes(String(a.status || '').toUpperCase())) ||
                docAppts.find(a => String(a.status || '').toUpperCase() === 'COMPLETED') ||
                null;

            let nextAppt = null;
            if (activeCurrent) {
                const curIdx = docAppts.findIndex(a => a.id === activeCurrent.id);
                nextAppt = docAppts.slice(curIdx + 1).find(a => !['COMPLETED'].includes(String(a.status || '').toUpperCase())) || null;
            }

            let delayDuration = Number(activeCurrent?.delay_minutes || 0) || 0;
            if (activeCurrent && !['COMPLETED'].includes(String(activeCurrent.status || '').toUpperCase())) {
                const apptDate = (activeCurrent.date || '').split('T')[0];
                const endMin = parseClockSlotMinutes(activeCurrent.scheduled_end_time || '');
                if (apptDate === nowParts.ymd && endMin !== null && nowParts.totalMinutes > endMin) {
                    delayDuration = Math.max(delayDuration, nowParts.totalMinutes - endMin);
                }
            }

            const docNameRaw = (doc.users?.name || doc.name || 'Doctor').toString().trim();
            const docName = docNameRaw.toLowerCase().startsWith('dr') ? docNameRaw : `Dr. ${docNameRaw}`;
            return {
                doctorId: doc.id,
                doctorName: docName,
                specialty: doc.speciality || doc.specialty || 'General Medicine',
                currentAvailability: doc.availability_status || 'Available',
                isAvailable: isDoctorRecordAvailable(doc),
                delayDurationMinutes: delayDuration,
                currentAppointment: activeCurrent ? {
                    id: activeCurrent.id,
                    patientName: activeCurrent.patient_name || 'Patient',
                    consultationType: activeCurrent.consultationMode || 'In-Person',
                    status: activeCurrent.status,
                    date: (activeCurrent.date || '').split('T')[0],
                    scheduledStartTime: activeCurrent.scheduled_start_time || activeCurrent.time_slot || '',
                    scheduledEndTime: activeCurrent.scheduled_end_time || '',
                    bufferEndTime: activeCurrent.buffer_end_time || '',
                    actualStartAt: activeCurrent.actual_start_at || null,
                    actualEndAt: activeCurrent.actual_end_at || null,
                    delayMinutes: delayDuration,
                } : null,
                nextAppointment: nextAppt ? {
                    id: nextAppt.id,
                    patientName: nextAppt.patient_name || 'Patient',
                    consultationType: nextAppt.consultationMode || 'In-Person',
                    status: nextAppt.status,
                    date: (nextAppt.date || '').split('T')[0],
                    scheduledStartTime: nextAppt.scheduled_start_time || nextAppt.time_slot || '',
                    scheduledEndTime: nextAppt.scheduled_end_time || '',
                    estimatedStartTime: nextAppt.estimated_start_time || null,
                } : null,
                pendingRescheduleCount: docAppts.filter(a => a.reschedule_request?.status === 'PENDING').length,
            };
        });

        res.json({
            success: true,
            timezone: rules.timezone,
            serverNowYmd: nowParts.ymd,
            rules,
            doctors: doctorsSummary,
            pendingRescheduleRequests,
        });
    } catch (err) {
        console.error('Get Live Scheduling Status Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to load live scheduling status.' });
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
                    // For doctors, allow passing only their own users.id or dentists.id
                    if (callerRoleLower === 'dentist' || callerRoleLower === 'doctor') {
                        const resolvedDoc = await resolveDentistIds(req.user.id).catch(() => ({ allIds: [] }));
                        const allowedIds = new Set([String(req.user.id), ...((resolvedDoc.allIds || []).map(String))]);
                        if (!allowedIds.has(String(effectiveUserId))) {
                            effectiveUserId = req.user.id;
                        }
                    } else if (callerRoleLower === 'clinic' || callerRoleLower === 'clinic_admin') {
                        const resolvedClinic = await resolveClinicIds(req.user.id);
                        const allowedIds = new Set((resolvedClinic.allIds || []).map(String));
                        if (!allowedIds.has(String(effectiveUserId))) {
                            effectiveUserId = resolvedClinic.clinicId || req.user.id;
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

// =============================================================================
// 11. CALENDAR-BASED VISIT MANAGEMENT (DOCTOR VISITS CALENDAR & ADMIN GLOBAL VISITS CALENDAR)
// =============================================================================

function _classifyCalendarAppointment(a) {
    const rawStatus = String(a?.status || 'PENDING').trim().toUpperCase();
    const isCompleted = rawStatus === 'COMPLETED';
    const isCancelled = rawStatus === 'CANCELLED' || rawStatus === 'CANCELED' || rawStatus === 'REJECTED';
    const isNoShow = rawStatus === 'NO_SHOW' || rawStatus === 'NOSHOW';
    const isInProgress = rawStatus === 'IN_PROGRESS' || rawStatus === 'STARTED';
    const isPending = !isCompleted && !isCancelled && !isNoShow;
    // Actual visit requires consultation completion or active in-progress session (never pending/cancelled/no-show/referral)
    const actuallyVisited = !isCancelled && !isNoShow && (
        isCompleted ||
        isInProgress ||
        Boolean(a?.actual_start_at) ||
        Boolean(a?.actual_end_at)
    );
    const consultType = normalizeConsultationType(
        a?.consultationMode || a?.consultation_type || a?.treatment || 'In-Person'
    );
    const isOnline = consultType === 'Online';
    const isInPerson = !isOnline;

    return {
        rawStatus,
        isCompleted,
        isCancelled,
        isNoShow,
        isInProgress,
        isPending,
        actuallyVisited,
        consultType,
        isOnline,
        isInPerson,
    };
}

function _getUniquePatientKeyFromAppointment(a) {
    const pid = String(a?.patient_id || a?.patient?.id || '').trim();
    if (pid) return `id:${pid}`;
    const rawPhone = String(a?.patient_phone || a?.patient?.phone || '').replace(/\D/g, '');
    const p10 = rawPhone.length >= 10 ? rawPhone.slice(-10) : rawPhone;
    if (p10.length >= 10) return `ph:${p10}`;
    return `appt:${a?.id || Math.random()}`;
}

async function _resolveCalendarCaller(req) {
    if (req.user && req.user.id) {
        return {
            id: String(req.user.id).trim(),
            role: String(req.user.role || '').trim(),
            permissions: Array.isArray(req.user.permissions) ? req.user.permissions : [],
            fromJwt: true,
        };
    }
    const headerUserId = (req.headers && req.headers['x-user-id'])
        ? String(req.headers['x-user-id']).trim()
        : '';
    if (!headerUserId) return null;

    const u = await User.findById(headerUserId).catch(() => null);
    if (u && u.id) {
        let perms = u.permissions || [];
        const rLower = String(u.role || '').trim().toLowerCase();
        if ((!perms || perms.length === 0) && (rLower === 'sub-admin' || rLower === 'subadmin' || rLower === 'sub_admin')) {
            perms = await SubAdminPermission.getPermissionsForUser(u.id).catch(() => []);
        }
        return {
            id: String(u.id).trim(),
            role: String(u.role || '').trim(),
            permissions: perms,
            fromJwt: false,
        };
    }
    const doc = await Dentist.findById(headerUserId).catch(() => null)
        || await Dentist.findOne({ user_id: headerUserId }).catch(() => null);
    if (doc) {
        return {
            id: String(doc.user_id || doc.id || headerUserId).trim(),
            role: 'Dentist',
            permissions: [],
            fromJwt: false,
        };
    }
    return null;
}

function _buildReferralTrackingEntry(ref, usersById, usersByPhone, doctorsById, matchingAppts, tz) {
    const referrerId = String(ref.referrer_patient_id || ref.referrer_id || '').trim();
    const referredId = String(ref.referred_patient_id || ref.referred_user_id || '').trim();
    const rawMobile = String(ref.referred_patient_mobile || '').trim();
    const mobile10 = rawMobile.replace(/\D/g, '').slice(-10);

    const referrerUser = (referrerId && usersById.get(referrerId)) || null;
    const referredUser = (referredId && usersById.get(referredId)) ||
        (mobile10.length === 10 && usersByPhone.get(mobile10)) ||
        null;

    const docId = String(ref.doctor_id || ref.assigned_doctor_id || '').trim();
    const docObj = (docId && doctorsById.get(docId)) || null;
    let rawDocName = String(ref.doctor_name || ref.doctorName || docObj?.users?.name || docObj?.name || '').trim();
    if (rawDocName && !rawDocName.toLowerCase().startsWith('dr') && !rawDocName.toLowerCase().startsWith('any ')) {
        rawDocName = `Dr. ${rawDocName}`;
    }

    const referralYmd = normalizeDateToTimezoneYmd(ref.referral_date || ref.created_at, tz);

    // Find if the referred patient booked or completed an appointment (strictly verified against actual appointments)
    const patientAppts = (matchingAppts || []).filter(a => {
        const aPid = String(a.patient_id || a.patient?.id || '').trim();
        const aPh10 = String(a.patient_phone || a.patient?.phone || '').replace(/\D/g, '').slice(-10);
        const targetId = referredId || (referredUser?.id ? String(referredUser.id).trim() : '');

        if (targetId && aPid) return targetId === aPid;
        if (mobile10.length === 10 && aPh10.length === 10) return mobile10 === aPh10;
        return false;
    });

    const nonCancelledAppts = patientAppts.filter(a => {
        const st = String(a.status || '').trim().toUpperCase();
        return st !== 'CANCELLED' && st !== 'CANCELED' && st !== 'REJECTED';
    });
    const completedAppt = nonCancelledAppts.find(a => String(a.status || '').trim().toUpperCase() === 'COMPLETED') || null;
    const activeAppt = completedAppt || nonCancelledAppts[0] || null;

    const referrerRoleLower = String(referrerUser?.role || 'Patient').trim().toLowerCase();
    const isReferredByPatient = !referrerUser || referrerRoleLower === 'patient';

    return {
        referralId: ref.id,
        id: ref.id,
        referredPatientId: referredId || referredUser?.id || null,
        referredPatientName: ref.referred_patient_name || referredUser?.name || 'Referred Patient',
        referredPatientMobile: rawMobile || referredUser?.phone || '',
        referringPatientId: referrerId || null,
        referringPatientName: referrerUser?.name || ref.referrer_patient_name || 'Referring Patient',
        referringPatientPhone: referrerUser?.phone || ref.referrer_patient_phone || '',
        referringPatientEmail: referrerUser?.email || '',
        isReferredByPatient,
        referredDoctorId: docId || null,
        referredDoctorName: rawDocName || 'Unassigned',
        specialty: ref.required_specialist || docObj?.speciality || docObj?.specialty || 'General Medicine',
        clinicalComplaint: ref.clinical_complaint || '',
        referralDate: referralYmd,
        referralTimestamp: ref.referral_date || ref.created_at || null,
        referralStatus: ref.status || 'Pending',
        hasBookedAppointment: nonCancelledAppts.length > 0,
        bookedAppointmentId: activeAppt ? activeAppt.id : null,
        bookedAppointmentDate: activeAppt ? normalizeDateToTimezoneYmd(activeAppt.date, tz) : null,
        bookedAppointmentTimeSlot: activeAppt ? (activeAppt.time_slot || '') : null,
        bookedAppointmentStatus: activeAppt ? activeAppt.status : null,
        hasCompletedConsultation: Boolean(completedAppt),
    };
}

// 11A. DOCTOR DASHBOARD VISITS CALENDAR API
exports.getDoctorVisitsCalendar = async (req, res) => {
    try {
        const rules = getBookingRulesConfig();
        const tz = rules.timezone || 'Asia/Kolkata';
        const nowParts = getNowPartsInTimezone(rules.debugNowOverride || new Date(), tz);

        const caller = await _resolveCalendarCaller(req);
        const callerRoleLower = String(caller?.role || '').trim().toLowerCase();
        const isCallerAdmin = ['admin', 'primaryadmin', 'primary_admin', 'superadmin', 'super_admin', 'sub-admin', 'subadmin', 'sub_admin'].includes(callerRoleLower);
        const isCallerDoctor = ['dentist', 'doctor'].includes(callerRoleLower);

        if (caller && callerRoleLower === 'patient') {
            return res.status(403).json({
                success: false,
                message: 'Access Denied: Patients are not authorized to access the Doctor Visits Calendar.',
            });
        }

        const requestedDoctorId = String(req.query.doctorId || req.query.dentistId || '').trim();
        let targetDoctorId = requestedDoctorId;

        if (isCallerDoctor) {
            const ownResolved = await resolveDentistIds(caller.id);
            const ownIdSet = new Set([
                String(caller.id),
                ...(ownResolved.allIds || []).map(String),
            ]);
            if (requestedDoctorId && !ownIdSet.has(requestedDoctorId)) {
                return res.status(403).json({
                    success: false,
                    message: "Access Denied: You cannot access another doctor's visit records.",
                });
            }
            targetDoctorId = ownResolved.dentistId || caller.id;
        } else if (!targetDoctorId && caller?.id) {
            targetDoctorId = caller.id;
        }

        if (!targetDoctorId) {
            return res.status(400).json({
                success: false,
                message: 'doctorId is required to load the Doctor Visits Calendar.',
            });
        }

        const resolvedDoc = await resolveDentistIds(targetDoctorId);
        const doctorIdSet = new Set([
            targetDoctorId,
            ...(resolvedDoc.allIds || []).map(String),
        ].filter(Boolean));

        const selectedDate = normalizeDateToTimezoneYmd(req.query.date, tz) || nowParts.ymd;
        const selectedMonth = (req.query.month && /^\d{4}-\d{2}$/.test(String(req.query.month).trim()))
            ? String(req.query.month).trim()
            : selectedDate.slice(0, 7);

        const filterConsultationType = String(req.query.consultationType || '').trim();
        const filterStatus = String(req.query.status || '').trim().toUpperCase();
        const filterSpecialty = String(req.query.specialty || '').trim().toLowerCase();

        const [allAppts, allReferrals, allUsers, allDoctors, allRecords] = await Promise.all([
            Appointment.find({}).catch(() => []),
            Referral.find({}).catch(() => []),
            User.find({}).catch(() => []),
            Dentist.find({}).catch(() => []),
            MedicalRecord.find({}).catch(() => []),
        ]);

        const usersById = new Map();
        const usersByPhone = new Map();
        for (const u of (allUsers || [])) {
            if (u?.id) usersById.set(String(u.id).trim(), u);
            const ph10 = String(u?.phone || '').replace(/\D/g, '').slice(-10);
            if (ph10.length === 10) usersByPhone.set(ph10, u);
        }

        const doctorsById = new Map();
        let currentDoctorObj = null;
        for (const d of (allDoctors || [])) {
            if (d?.id) doctorsById.set(String(d.id).trim(), d);
            if (d?.user_id) doctorsById.set(String(d.user_id).trim(), d);
            if ((d?.id && doctorIdSet.has(String(d.id).trim())) || (d?.user_id && doctorIdSet.has(String(d.user_id).trim()))) {
                currentDoctorObj = d;
            }
        }

        // Filter strictly to appointments assigned to this doctor
        const doctorAppts = (allAppts || [])
            .filter(a => {
                const dId = String(a?.dentist_id || a?.dentist?.id || '').trim();
                const dUserId = String(a?.dentist?.user_id || '').trim();
                return (dId && doctorIdSet.has(dId)) || (dUserId && doctorIdSet.has(dUserId));
            })
            .map(a => {
                const enriched = enrichAppointmentRecord(a);
                const apptYmd = normalizeDateToTimezoneYmd(enriched.date, tz);
                return { ...enriched, asiaKolkataDate: apptYmd };
            });

        // Filter strictly to referrals assigned to this doctor
        const doctorReferralsRaw = (allReferrals || []).filter(r => {
            const rDocId = String(r?.doctor_id || '').trim();
            const rAssignedId = String(r?.assigned_doctor_id || '').trim();
            return (rDocId && doctorIdSet.has(rDocId)) || (rAssignedId && doctorIdSet.has(rAssignedId));
        });

        const doctorReferrals = doctorReferralsRaw.map(r =>
            _buildReferralTrackingEntry(r, usersById, usersByPhone, doctorsById, doctorAppts, tz)
        );

        // Index referrals by referred patient ID and phone so visit cards show referral source when applicable
        const referralByPatientId = new Map();
        const referralByPatientPhone = new Map();
        for (const refItem of doctorReferrals) {
            if (refItem.referredPatientId) {
                referralByPatientId.set(String(refItem.referredPatientId).trim(), refItem);
            }
            const ph10 = String(refItem.referredPatientMobile || '').replace(/\D/g, '').slice(-10);
            if (ph10.length === 10) {
                referralByPatientPhone.set(ph10, refItem);
            }
        }

        // Index prescriptions/medical records for this doctor
        const doctorRecords = (allRecords || []).filter(rec => {
            const rDocId = String(rec?.dentist_id || '').trim();
            return !rDocId || doctorIdSet.has(rDocId);
        });

        // Monthly Calendar Aggregation for `selectedMonth`
        const monthlyCalendar = {};
        const ensureMonthDay = (ymd) => {
            if (!monthlyCalendar[ymd]) {
                monthlyCalendar[ymd] = {
                    date: ymd,
                    totalAppointments: 0,
                    actualPatientVisits: 0,
                    _visitedPatientsSet: new Set(),
                    completedConsultations: 0,
                    pendingConsultations: 0,
                    cancelledAppointments: 0,
                    noShowAppointments: 0,
                    onlineConsultations: 0,
                    inPersonConsultations: 0,
                    patientReferralsReceived: 0,
                    hasCompleted: false,
                    hasPending: false,
                    hasCancelled: false,
                    hasNoShow: false,
                    hasReferrals: false,
                };
            }
            return monthlyCalendar[ymd];
        };

        for (const a of doctorAppts) {
            const ymd = a.asiaKolkataDate;
            if (!ymd || !ymd.startsWith(selectedMonth)) continue;
            const bucket = ensureMonthDay(ymd);
            const cls = _classifyCalendarAppointment(a);
            bucket.totalAppointments += 1;
            if (cls.actuallyVisited) {
                bucket._visitedPatientsSet.add(_getUniquePatientKeyFromAppointment(a));
            }
            if (cls.isCompleted) {
                bucket.completedConsultations += 1;
                bucket.hasCompleted = true;
            } else if (cls.isCancelled) {
                bucket.cancelledAppointments += 1;
                bucket.hasCancelled = true;
            } else if (cls.isNoShow) {
                bucket.noShowAppointments += 1;
                bucket.hasNoShow = true;
            } else if (cls.isPending) {
                bucket.pendingConsultations += 1;
                bucket.hasPending = true;
            }
            if (cls.isOnline) bucket.onlineConsultations += 1;
            else bucket.inPersonConsultations += 1;
        }

        for (const refItem of doctorReferrals) {
            const ymd = refItem.referralDate;
            if (!ymd || !ymd.startsWith(selectedMonth)) continue;
            const bucket = ensureMonthDay(ymd);
            bucket.patientReferralsReceived += 1;
            bucket.hasReferrals = true;
        }

        for (const ymd of Object.keys(monthlyCalendar)) {
            monthlyCalendar[ymd].actualPatientVisits = monthlyCalendar[ymd]._visitedPatientsSet.size;
            delete monthlyCalendar[ymd]._visitedPatientsSet;
        }

        // Selected Date Filtering & Stats
        const apptsOnSelectedDate = doctorAppts.filter(a => {
            if (a.asiaKolkataDate !== selectedDate) return false;
            const cls = _classifyCalendarAppointment(a);
            if (filterConsultationType && filterConsultationType.toLowerCase() !== 'all') {
                const wantType = normalizeConsultationType(filterConsultationType);
                if (cls.consultType !== wantType) return false;
            }
            if (filterStatus && filterStatus !== 'ALL') {
                if (cls.rawStatus !== filterStatus) return false;
            }
            if (filterSpecialty && filterSpecialty !== 'all') {
                const sp = String(a.doctor_specialty || currentDoctorObj?.speciality || currentDoctorObj?.specialty || '').trim().toLowerCase();
                if (!sp.includes(filterSpecialty)) return false;
            }
            return true;
        });

        apptsOnSelectedDate.sort((a, b) => {
            const ma = parseClockSlotMinutes(a.time_slot || '') ?? 9999;
            const mb = parseClockSlotMinutes(b.time_slot || '') ?? 9999;
            return ma - mb;
        });

        const referralsOnSelectedDate = doctorReferrals.filter(r => r.referralDate === selectedDate);
        const visitedPatientsOnDate = new Set();
        let completedCount = 0;
        let pendingCount = 0;
        let cancelledCount = 0;
        let noShowCount = 0;
        let onlineCount = 0;
        let inPersonCount = 0;

        for (const a of apptsOnSelectedDate) {
            const cls = _classifyCalendarAppointment(a);
            if (cls.actuallyVisited) {
                visitedPatientsOnDate.add(_getUniquePatientKeyFromAppointment(a));
            }
            if (cls.isCompleted) completedCount += 1;
            else if (cls.isCancelled) cancelledCount += 1;
            else if (cls.isNoShow) noShowCount += 1;
            else if (cls.isPending) pendingCount += 1;

            if (cls.isOnline) onlineCount += 1;
            else inPersonCount += 1;
        }

        // Check role permissions for contact & prescription visibility
        let canViewPatientContact = true;
        const canAccessConsultationDetails = true;
        const canAccessPrescription = true;
        if (isCallerAdmin && callerRoleLower.includes('sub')) {
            const permsUpper = (caller?.permissions || []).map(p => String(p || '').toUpperCase());
            canViewPatientContact = permsUpper.includes('*') || permsUpper.includes('ALL') || permsUpper.includes('PATIENT_VIEW');
        }

        const visitsList = apptsOnSelectedDate.map(a => {
            const cls = _classifyCalendarAppointment(a);
            const pId = String(a.patient_id || a.patient?.id || '').trim();
            const pUser = (pId && usersById.get(pId)) || null;
            const ph10 = String(a.patient_phone || a.patient?.phone || pUser?.phone || '').replace(/\D/g, '').slice(-10);
            const matchedRef = (pId && referralByPatientId.get(pId)) ||
                (ph10.length === 10 && referralByPatientPhone.get(ph10)) ||
                null;
            const patientPrescriptions = doctorRecords.filter(rec => {
                const recPid = String(rec?.patient_id || '').trim();
                return pId && recPid === pId;
            });

            return {
                appointmentId: a.id,
                id: a.id,
                patientId: pId || null,
                patientName: a.patient_name || pUser?.name || 'Patient',
                patientProfileImage: pUser?.biometric_token || a.patient?.profilePhoto || null,
                patientPhone: canViewPatientContact ? (a.patient_phone || pUser?.phone || '') : null,
                patientEmail: canViewPatientContact ? (a.patient_email || pUser?.email || '') : null,
                patientCity: a.patient_city || pUser?.city || '',
                patientAge: a.patient_age || pUser?.age || '',
                patientGender: a.patient_gender || pUser?.gender || '',
                consultationDate: a.asiaKolkataDate,
                consultationTime: a.time_slot || '',
                scheduledEndTime: a.scheduled_end_time || null,
                actualStartAt: a.actual_start_at || null,
                actualEndAt: a.actual_end_at || null,
                consultationType: cls.consultType,
                specialty: a.doctor_specialty || currentDoctorObj?.speciality || currentDoctorObj?.specialty || 'General Medicine',
                treatment: a.treatment || 'Medical Consultation',
                status: cls.rawStatus,
                actuallyVisited: cls.actuallyVisited,
                delayMinutes: Number(a.delay_minutes || 0) || 0,
                referralSource: matchedRef ? {
                    referralId: matchedRef.referralId,
                    referringPatientName: matchedRef.referringPatientName,
                    referringPatientPhone: canViewPatientContact ? matchedRef.referringPatientPhone : null,
                    referralDate: matchedRef.referralDate,
                    referralStatus: matchedRef.referralStatus,
                } : null,
                canViewPatientContact,
                canAccessConsultationDetails,
                canAccessPrescription,
                hasPrescription: patientPrescriptions.length > 0,
                prescriptionCount: patientPrescriptions.length,
                latestPrescriptionId: patientPrescriptions[0]?.id || null,
            };
        });

        const selectedDateStats = {
            date: selectedDate,
            totalAppointments: apptsOnSelectedDate.length,
            actualPatientVisits: visitedPatientsOnDate.size,
            completedConsultations: completedCount,
            pendingConsultations: pendingCount,
            cancelledAppointments: cancelledCount,
            noShowAppointments: noShowCount,
            onlineConsultations: onlineCount,
            inPersonConsultations: inPersonCount,
            patientReferralsReceived: referralsOnSelectedDate.length,
            patientsReferredByOtherPatients: referralsOnSelectedDate.filter(r => r.isReferredByPatient).length,
            totalReferralsAllTime: doctorReferrals.length,
        };

        res.json({
            success: true,
            timezone: tz,
            doctorId: resolvedDoc.dentistId || targetDoctorId,
            doctorName: currentDoctorObj?.users?.name || currentDoctorObj?.name || 'Doctor',
            specialty: currentDoctorObj?.speciality || currentDoctorObj?.specialty || 'General Medicine',
            selectedDate,
            month: selectedMonth,
            selectedDateStats,
            monthlyCalendar,
            visits: visitsList,
            referralsOnDate: referralsOnSelectedDate,
            allReferrals: doctorReferrals,
        });
    } catch (err) {
        console.error('Get Doctor Visits Calendar Error:', err.message);
        res.status(500).json({
            success: false,
            message: 'Failed to load Doctor Visits Calendar.',
        });
    }
};

// 11B. ADMIN GLOBAL VISITS CALENDAR API (Platform-Wide + Sub-Admin District Scoping)
exports.getAdminGlobalVisitsCalendar = async (req, res) => {
    try {
        const rules = getBookingRulesConfig();
        const tz = rules.timezone || 'Asia/Kolkata';
        const nowParts = getNowPartsInTimezone(rules.debugNowOverride || new Date(), tz);

        const caller = await _resolveCalendarCaller(req);
        const callerRoleLower = String(caller?.role || '').trim().toLowerCase();
        const isMainAdmin = !caller || ['admin', 'primaryadmin', 'primary_admin', 'superadmin', 'super_admin'].includes(callerRoleLower);
        const isSubAdmin = ['sub-admin', 'subadmin', 'sub_admin'].includes(callerRoleLower);

        if (caller && !isMainAdmin && !isSubAdmin) {
            return res.status(403).json({
                success: false,
                message: 'Access Denied: Only Administrators and authorized Sub-Administrators can access the Global Visits Calendar.',
            });
        }

        let assignedDistricts = [];
        let canViewPatientContact = true;
        if (isSubAdmin && caller?.id) {
            const permsUpper = (caller.permissions || []).map(p => String(p || '').toUpperCase());
            const hasCalendarPerm = permsUpper.includes('*') ||
                permsUpper.includes('ALL') ||
                permsUpper.includes('APPOINTMENT_VIEW') ||
                permsUpper.includes('REPORT_VIEW') ||
                permsUpper.includes('CLINIC_VIEW') ||
                permsUpper.includes('DENTIST_VIEW');
            if (!hasCalendarPerm) {
                return res.status(403).json({
                    success: false,
                    message: "Access Denied: Your Sub-Admin account lacks 'APPOINTMENT_VIEW' or 'REPORT_VIEW' permission.",
                });
            }
            canViewPatientContact = permsUpper.includes('*') || permsUpper.includes('ALL') || permsUpper.includes('PATIENT_VIEW');
            assignedDistricts = await SubAdminDistrict.getDistrictsForSubAdmin(caller.id).catch(() => []);
        }

        const authDistrictIds = new Set((assignedDistricts || []).map(d => String(d.id || '').trim()).filter(Boolean));
        const authDistrictNames = new Set((assignedDistricts || []).map(d => String(d.name || '').trim().toLowerCase()).filter(Boolean));

        const isLocationPermittedForSubAdmin = ({ districtId, districtName, city, state, pincode, location }) => {
            if (!isSubAdmin) return true;
            if (authDistrictIds.size === 0 && authDistrictNames.size === 0) return false;
            if (districtId && authDistrictIds.has(String(districtId).trim())) return true;
            if (districtName && authDistrictNames.has(String(districtName).trim().toLowerCase())) return true;
            if (city && authDistrictNames.has(String(city).trim().toLowerCase())) return true;

            const resolved = District.resolveDistrictFromLocation({
                city: city || location || '',
                district: districtName || '',
                state: state || '',
                pincode: pincode || '',
            });
            if (resolved?.districtId && authDistrictIds.has(String(resolved.districtId).trim())) return true;
            if (resolved?.districtName && authDistrictNames.has(String(resolved.districtName).trim().toLowerCase())) return true;
            if (location) {
                const locLower = String(location).toLowerCase();
                for (const dName of authDistrictNames) {
                    if (dName && locLower.includes(dName)) return true;
                }
            }
            return false;
        };

        const reqDistrictFilter = String(req.query.district || req.query.districtId || '').trim();
        if (isSubAdmin && reqDistrictFilter && reqDistrictFilter.toLowerCase() !== 'all') {
            const permitted = authDistrictIds.has(reqDistrictFilter) ||
                authDistrictNames.has(reqDistrictFilter.toLowerCase());
            if (!permitted) {
                return res.status(403).json({
                    success: false,
                    message: `Access Denied: District '${reqDistrictFilter}' is outside your assigned Sub-Admin jurisdiction.`,
                });
            }
        }

        const selectedDate = normalizeDateToTimezoneYmd(req.query.date, tz) || nowParts.ymd;
        const selectedMonth = (req.query.month && /^\d{4}-\d{2}$/.test(String(req.query.month).trim()))
            ? String(req.query.month).trim()
            : selectedDate.slice(0, 7);

        const filterClinic = String(req.query.clinicId || req.query.hospital || req.query.clinic || '').trim();
        const filterDoctor = String(req.query.doctorId || req.query.doctor || '').trim();
        const filterSpecialty = String(req.query.specialty || '').trim().toLowerCase();
        const filterConsultationType = String(req.query.consultationType || '').trim();

        const [rawAppts, rawReferrals, rawUsers, rawDoctors, rawClinics] = await Promise.all([
            Appointment.find({}).catch(() => []),
            Referral.find({}).catch(() => []),
            User.find({}).catch(() => []),
            Dentist.find({}).catch(() => []),
            Clinic.find({}).catch(() => []),
        ]);

        const usersById = new Map();
        const usersByPhone = new Map();
        for (const u of (rawUsers || [])) {
            if (u?.id) usersById.set(String(u.id).trim(), u);
            const ph10 = String(u?.phone || '').replace(/\D/g, '').slice(-10);
            if (ph10.length === 10) usersByPhone.set(ph10, u);
        }

        // Scope clinics and doctors for Sub-Admin if applicable
        const permittedClinics = (rawClinics || []).filter(c =>
            isLocationPermittedForSubAdmin({
                districtId: c.district_id,
                districtName: c.district,
                city: c.city,
                state: c.state,
                pincode: c.pincode,
                location: c.location,
            })
        );
        const permittedClinicIds = new Set(permittedClinics.map(c => String(c.id).trim()));
        const clinicsById = new Map();
        for (const c of permittedClinics) {
            if (c?.id) clinicsById.set(String(c.id).trim(), c);
        }

        const permittedDoctors = (rawDoctors || []).filter(d => {
            if (!isSubAdmin) return true;
            if (d.clinic_id && permittedClinicIds.has(String(d.clinic_id).trim())) return true;
            return isLocationPermittedForSubAdmin({
                districtId: d.district_id || d.users?.district_id,
                districtName: d.district || d.users?.district,
                city: d.city || d.users?.city,
                state: d.state || d.users?.state,
                pincode: d.pincode || d.users?.pincode,
                location: d.clinic_address || d.location,
            });
        });
        const doctorsById = new Map();
        const permittedDoctorIds = new Set();
        for (const d of permittedDoctors) {
            if (d?.id) {
                doctorsById.set(String(d.id).trim(), d);
                permittedDoctorIds.add(String(d.id).trim());
            }
            if (d?.user_id) {
                doctorsById.set(String(d.user_id).trim(), d);
                permittedDoctorIds.add(String(d.user_id).trim());
            }
        }

        // Enrich and scope appointments
        const allPermittedAppts = (rawAppts || [])
            .map(a => {
                const enriched = enrichAppointmentRecord(a);
                const apptYmd = normalizeDateToTimezoneYmd(enriched.date, tz);
                return { ...enriched, asiaKolkataDate: apptYmd };
            })
            .filter(a => {
                if (!isSubAdmin) return true;
                const dId = String(a.dentist_id || a.selectedDoctor?.id || '').trim();
                const cId = String(a.clinic_id || a.clinic?.id || '').trim();
                if (cId && permittedClinicIds.has(cId)) return true;
                if (dId && permittedDoctorIds.has(dId)) return true;
                return isLocationPermittedForSubAdmin({
                    city: a.patient_city || a.patient?.city,
                    pincode: a.patient_pincode || a.patient?.pincode,
                    location: a.clinic?.location || a.clinic_name,
                });
            });

        // Apply optional query filters (hospital/clinic, doctor, specialty, consultationType, district)
        const matchesQueryFilters = (a) => {
            if (filterClinic && filterClinic.toLowerCase() !== 'all') {
                const cId = String(a.clinic_id || a.clinic?.id || '').trim();
                const cName = String(a.clinic_name || a.clinic?.clinic_name || '').trim().toLowerCase();
                const fLower = filterClinic.toLowerCase();
                if (cId !== filterClinic && !cName.includes(fLower)) return false;
            }
            if (filterDoctor && filterDoctor.toLowerCase() !== 'all') {
                const dId = String(a.dentist_id || a.selectedDoctor?.id || '').trim();
                const dUserId = String(a.selectedDoctor?.user_id || '').trim();
                const dName = String(a.dentist_name || a.selectedDoctor?.name || '').trim().toLowerCase();
                const fLower = filterDoctor.toLowerCase();
                if (dId !== filterDoctor && dUserId !== filterDoctor && !dName.includes(fLower)) return false;
            }
            if (filterSpecialty && filterSpecialty !== 'all') {
                const sp = String(a.doctor_specialty || a.selectedDoctor?.specialty || '').trim().toLowerCase();
                if (!sp.includes(filterSpecialty)) return false;
            }
            if (filterConsultationType && filterConsultationType.toLowerCase() !== 'all') {
                const cls = _classifyCalendarAppointment(a);
                const wantType = normalizeConsultationType(filterConsultationType);
                if (cls.consultType !== wantType) return false;
            }
            if (reqDistrictFilter && reqDistrictFilter.toLowerCase() !== 'all') {
                const fLower = reqDistrictFilter.toLowerCase();
                const pCity = String(a.patient_city || '').toLowerCase();
                const cLoc = String(a.clinic?.location || '').toLowerCase();
                if (!pCity.includes(fLower) && !cLoc.includes(fLower)) return false;
            }
            return true;
        };

        const filteredAppts = allPermittedAppts.filter(matchesQueryFilters);

        // Scope referrals & map to tracking entries
        const permittedReferralsRaw = (rawReferrals || []).filter(r => {
            if (!isSubAdmin) return true;
            const rDocId = String(r.doctor_id || r.assigned_doctor_id || '').trim();
            const rClinicId = String(r.clinic_id || '').trim();
            if (rDocId && permittedDoctorIds.has(rDocId)) return true;
            if (rClinicId && permittedClinicIds.has(rClinicId)) return true;
            return isLocationPermittedForSubAdmin({
                city: r.referred_patient_city || r.doctor_city,
                pincode: r.referred_patient_pincode || r.doctor_pincode,
                location: r.referred_patient_location || r.doctor_location,
            });
        });

        const allReferralEntries = permittedReferralsRaw
            .map(r => _buildReferralTrackingEntry(r, usersById, usersByPhone, doctorsById, allPermittedAppts, tz))
            .filter(refItem => {
                if (filterDoctor && filterDoctor.toLowerCase() !== 'all') {
                    const fLower = filterDoctor.toLowerCase();
                    const matchesDoc = refItem.referredDoctorId === filterDoctor ||
                        String(refItem.referredDoctorName || '').toLowerCase().includes(fLower);
                    if (!matchesDoc) return false;
                }
                if (filterSpecialty && filterSpecialty !== 'all') {
                    if (!String(refItem.specialty || '').toLowerCase().includes(filterSpecialty)) return false;
                }
                return true;
            });

        // Scope patient users for new registration counts
        const permittedPatients = (rawUsers || []).filter(u => {
            const rLower = String(u?.role || 'Patient').trim().toLowerCase();
            if (rLower !== 'patient') return false;
            if (!isSubAdmin) return true;
            return isLocationPermittedForSubAdmin({
                districtId: u.district_id,
                districtName: u.district,
                city: u.city,
                state: u.state,
                pincode: u.pincode,
            });
        });

        // Build Monthly Calendar Aggregation for `selectedMonth`
        const monthlyCalendar = {};
        const ensureMonthDay = (ymd) => {
            if (!monthlyCalendar[ymd]) {
                monthlyCalendar[ymd] = {
                    date: ymd,
                    totalScheduledAppointments: 0,
                    actualPatientVisits: 0,
                    _visitedPatientsSet: new Set(),
                    completedAppointments: 0,
                    pendingAppointments: 0,
                    cancelledAppointments: 0,
                    noShowAppointments: 0,
                    onlineConsultations: 0,
                    inPersonConsultations: 0,
                    newPatientRegistrations: 0,
                    patientReferrals: 0,
                    hasCompleted: false,
                    hasPending: false,
                    hasCancelled: false,
                    hasNoShow: false,
                    hasReferrals: false,
                };
            }
            return monthlyCalendar[ymd];
        };

        for (const a of filteredAppts) {
            const ymd = a.asiaKolkataDate;
            if (!ymd || !ymd.startsWith(selectedMonth)) continue;
            const bucket = ensureMonthDay(ymd);
            const cls = _classifyCalendarAppointment(a);
            bucket.totalScheduledAppointments += 1;
            if (cls.actuallyVisited) {
                bucket._visitedPatientsSet.add(_getUniquePatientKeyFromAppointment(a));
            }
            if (cls.isCompleted) {
                bucket.completedAppointments += 1;
                bucket.hasCompleted = true;
            } else if (cls.isCancelled) {
                bucket.cancelledAppointments += 1;
                bucket.hasCancelled = true;
            } else if (cls.isNoShow) {
                bucket.noShowAppointments += 1;
                bucket.hasNoShow = true;
            } else if (cls.isPending) {
                bucket.pendingAppointments += 1;
                bucket.hasPending = true;
            }
            if (cls.isOnline) bucket.onlineConsultations += 1;
            else bucket.inPersonConsultations += 1;
        }

        for (const refItem of allReferralEntries) {
            const ymd = refItem.referralDate;
            if (!ymd || !ymd.startsWith(selectedMonth)) continue;
            const bucket = ensureMonthDay(ymd);
            bucket.patientReferrals += 1;
            bucket.hasReferrals = true;
        }

        for (const p of permittedPatients) {
            const regYmd = normalizeDateToTimezoneYmd(p.created_at, tz);
            if (!regYmd || !regYmd.startsWith(selectedMonth)) continue;
            const bucket = ensureMonthDay(regYmd);
            bucket.newPatientRegistrations += 1;
        }

        for (const ymd of Object.keys(monthlyCalendar)) {
            monthlyCalendar[ymd].actualPatientVisits = monthlyCalendar[ymd]._visitedPatientsSet.size;
            delete monthlyCalendar[ymd]._visitedPatientsSet;
        }

        // Selected Date Platform-Wide Statistics
        const apptsOnSelectedDate = filteredAppts.filter(a => a.asiaKolkataDate === selectedDate);
        apptsOnSelectedDate.sort((a, b) => {
            const ma = parseClockSlotMinutes(a.time_slot || '') ?? 9999;
            const mb = parseClockSlotMinutes(b.time_slot || '') ?? 9999;
            return ma - mb;
        });

        const referralsOnSelectedDate = allReferralEntries.filter(r => r.referralDate === selectedDate);
        const newRegistrationsOnSelectedDate = permittedPatients.filter(
            p => normalizeDateToTimezoneYmd(p.created_at, tz) === selectedDate
        );

        const uniqueVisitedPatientsOnDate = new Set();
        let completedCount = 0;
        let pendingCount = 0;
        let cancelledCount = 0;
        let noShowCount = 0;
        let onlineCount = 0;
        let inPersonCount = 0;

        for (const a of apptsOnSelectedDate) {
            const cls = _classifyCalendarAppointment(a);
            if (cls.actuallyVisited) {
                uniqueVisitedPatientsOnDate.add(_getUniquePatientKeyFromAppointment(a));
            }
            if (cls.isCompleted) completedCount += 1;
            else if (cls.isCancelled) cancelledCount += 1;
            else if (cls.isNoShow) noShowCount += 1;
            else if (cls.isPending) pendingCount += 1;

            if (cls.isOnline) onlineCount += 1;
            else inPersonCount += 1;
        }

        // Map referral by patient for visit enrichment
        const referralByPatientId = new Map();
        const referralByPatientPhone = new Map();
        for (const r of allReferralEntries) {
            if (r.referredPatientId) referralByPatientId.set(String(r.referredPatientId).trim(), r);
            const ph10 = String(r.referredPatientMobile || '').replace(/\D/g, '').slice(-10);
            if (ph10.length === 10) referralByPatientPhone.set(ph10, r);
        }

        const buildVisitItem = (a) => {
            const cls = _classifyCalendarAppointment(a);
            const pId = String(a.patient_id || a.patient?.id || '').trim();
            const pUser = (pId && usersById.get(pId)) || null;
            const ph10 = String(a.patient_phone || a.patient?.phone || pUser?.phone || '').replace(/\D/g, '').slice(-10);
            const matchedRef = (pId && referralByPatientId.get(pId)) ||
                (ph10.length === 10 && referralByPatientPhone.get(ph10)) ||
                null;
            const dId = String(a.dentist_id || a.selectedDoctor?.id || '').trim();
            const dObj = (dId && doctorsById.get(dId)) || null;
            const cId = String(a.clinic_id || a.clinic?.id || dObj?.clinic_id || '').trim();
            const cObj = (cId && clinicsById.get(cId)) || null;
            const clinicName = a.clinic_name || cObj?.clinic_name || dObj?.clinics?.clinic_name || dObj?.clinic_name || '';

            return {
                appointmentId: a.id,
                id: a.id,
                patientId: pId || null,
                patientName: a.patient_name || pUser?.name || 'Patient',
                patientProfileImage: pUser?.biometric_token || null,
                patientPhone: canViewPatientContact ? (a.patient_phone || pUser?.phone || '') : null,
                patientEmail: canViewPatientContact ? (a.patient_email || pUser?.email || '') : null,
                patientCity: a.patient_city || pUser?.city || '',
                doctorId: dId || null,
                doctorName: a.dentist_name || dObj?.users?.name || dObj?.name || 'Doctor',
                specialty: a.doctor_specialty || dObj?.speciality || dObj?.specialty || 'General Medicine',
                clinicId: cId || null,
                clinicName,
                consultationDate: a.asiaKolkataDate,
                consultationTime: a.time_slot || '',
                scheduledEndTime: a.scheduled_end_time || null,
                actualStartAt: a.actual_start_at || null,
                actualEndAt: a.actual_end_at || null,
                consultationType: cls.consultType,
                treatment: a.treatment || 'Medical Consultation',
                status: cls.rawStatus,
                actuallyVisited: cls.actuallyVisited,
                referralSource: matchedRef ? {
                    referralId: matchedRef.referralId,
                    referringPatientName: matchedRef.referringPatientName,
                    referralDate: matchedRef.referralDate,
                    referralStatus: matchedRef.referralStatus,
                } : null,
                canViewPatientContact,
            };
        };

        const visitsList = apptsOnSelectedDate.map(buildVisitItem);

        // Hospital / Clinic Breakdown on `selectedDate`
        const hospitalMap = new Map();
        for (const c of permittedClinics) {
            const cId = String(c.id).trim();
            hospitalMap.set(cId, {
                clinicId: cId,
                clinicName: c.clinic_name || c.name || 'Hospital / Clinic',
                location: c.location || '',
                city: c.city || '',
                district: c.district || '',
                pincode: c.pincode || '',
                scheduledVisits: 0,
                actualPatientVisits: 0,
                _visitedPatientsSet: new Set(),
                completedVisits: 0,
                pendingVisits: 0,
                cancelledVisits: 0,
                noShowVisits: 0,
                onlineVisits: 0,
                inPersonVisits: 0,
                assignedDoctors: [],
                _doctorIdsSet: new Set(),
                visits: [],
            });
        }

        // Attach assigned doctors to their respective hospitals/clinics
        for (const d of permittedDoctors) {
            const cId = String(d.clinic_id || d.clinics?.id || '').trim();
            const cName = String(d.clinics?.clinic_name || d.clinic_name || '').trim();
            let bucket = (cId && hospitalMap.get(cId)) || null;
            if (!bucket && cName) {
                for (const b of hospitalMap.values()) {
                    if (b.clinicName.trim().toLowerCase() === cName.toLowerCase()) {
                        bucket = b;
                        break;
                    }
                }
                if (!bucket) {
                    const synthKey = cId || `clinic:${cName.toLowerCase()}`;
                    bucket = {
                        clinicId: synthKey,
                        clinicName: cName,
                        location: d.clinic_address || d.location || '',
                        city: d.city || '',
                        district: d.district || '',
                        pincode: d.pincode || '',
                        scheduledVisits: 0,
                        actualPatientVisits: 0,
                        _visitedPatientsSet: new Set(),
                        completedVisits: 0,
                        pendingVisits: 0,
                        cancelledVisits: 0,
                        noShowVisits: 0,
                        onlineVisits: 0,
                        inPersonVisits: 0,
                        assignedDoctors: [],
                        _doctorIdsSet: new Set(),
                        visits: [],
                    };
                    hospitalMap.set(synthKey, bucket);
                }
            }
            if (bucket && d.id && !bucket._doctorIdsSet.has(String(d.id))) {
                bucket._doctorIdsSet.add(String(d.id));
                const rawName = String(d.users?.name || d.name || 'Doctor').trim();
                const docName = rawName.toLowerCase().startsWith('dr') ? rawName : `Dr. ${rawName}`;
                bucket.assignedDoctors.push({
                    doctorId: d.id,
                    doctorName: docName,
                    specialty: d.speciality || d.specialty || 'General Medicine',
                });
            }
        }

        // Populate hospital/clinic visit counts for `selectedDate`
        for (let i = 0; i < apptsOnSelectedDate.length; i++) {
            const a = apptsOnSelectedDate[i];
            const vItem = visitsList[i];
            const cls = _classifyCalendarAppointment(a);
            const cId = String(vItem.clinicId || '').trim();
            const cName = String(vItem.clinicName || '').trim();
            let bucket = (cId && hospitalMap.get(cId)) || null;
            if (!bucket && cName) {
                for (const b of hospitalMap.values()) {
                    if (b.clinicName.trim().toLowerCase() === cName.toLowerCase()) {
                        bucket = b;
                        break;
                    }
                }
            }
            if (!bucket && (cId || cName)) {
                const key = cId || `clinic:${cName.toLowerCase()}`;
                bucket = {
                    clinicId: key,
                    clinicName: cName || 'Hospital / Clinic',
                    location: a.clinic?.location || '',
                    city: a.patient_city || '',
                    district: '',
                    pincode: '',
                    scheduledVisits: 0,
                    actualPatientVisits: 0,
                    _visitedPatientsSet: new Set(),
                    completedVisits: 0,
                    pendingVisits: 0,
                    cancelledVisits: 0,
                    noShowVisits: 0,
                    onlineVisits: 0,
                    inPersonVisits: 0,
                    assignedDoctors: [],
                    _doctorIdsSet: new Set(),
                    visits: [],
                };
                hospitalMap.set(key, bucket);
            }
            if (bucket) {
                bucket.scheduledVisits += 1;
                if (cls.actuallyVisited) {
                    bucket._visitedPatientsSet.add(_getUniquePatientKeyFromAppointment(a));
                }
                if (cls.isCompleted) bucket.completedVisits += 1;
                else if (cls.isCancelled) bucket.cancelledVisits += 1;
                else if (cls.isNoShow) bucket.noShowVisits += 1;
                else if (cls.isPending) bucket.pendingVisits += 1;

                if (cls.isOnline) bucket.onlineVisits += 1;
                else bucket.inPersonVisits += 1;
                bucket.visits.push(vItem);
            }
        }

        const hospitalClinicBreakdown = Array.from(hospitalMap.values())
            .filter(b => {
                if (filterClinic && filterClinic.toLowerCase() !== 'all') {
                    const fLower = filterClinic.toLowerCase();
                    return b.clinicId === filterClinic || b.clinicName.toLowerCase().includes(fLower);
                }
                return true;
            })
            .map(b => {
                const actualPatientVisits = b._visitedPatientsSet.size;
                const copy = { ...b, actualPatientVisits };
                delete copy._visitedPatientsSet;
                delete copy._doctorIdsSet;
                return copy;
            });

        // Doctor-wise Consultation Breakdown on `selectedDate`
        const doctorStatsMap = new Map();
        for (const d of permittedDoctors) {
            const dId = String(d.id).trim();
            const rawName = String(d.users?.name || d.name || 'Doctor').trim();
            const docName = rawName.toLowerCase().startsWith('dr') ? rawName : `Dr. ${rawName}`;
            const cObj = (d.clinic_id && clinicsById.get(String(d.clinic_id).trim())) || null;
            doctorStatsMap.set(dId, {
                doctorId: dId,
                userId: d.user_id || null,
                doctorName: docName,
                specialty: d.speciality || d.specialty || 'General Medicine',
                clinicId: d.clinic_id || null,
                clinicName: cObj?.clinic_name || d.clinics?.clinic_name || d.clinic_name || '',
                scheduledConsultations: 0,
                actualPatientVisits: 0,
                _visitedPatientsSet: new Set(),
                completedConsultations: 0,
                pendingConsultations: 0,
                cancelledConsultations: 0,
                noShowConsultations: 0,
                onlineConsultations: 0,
                inPersonConsultations: 0,
            });
        }

        for (const a of apptsOnSelectedDate) {
            const cls = _classifyCalendarAppointment(a);
            const rawDocId = String(a.dentist_id || a.selectedDoctor?.id || '').trim();
            const docObj = (rawDocId && doctorsById.get(rawDocId)) || null;
            const canonicalDocId = docObj?.id ? String(docObj.id).trim() : rawDocId;
            let dBucket = canonicalDocId ? doctorStatsMap.get(canonicalDocId) : null;
            if (!dBucket && canonicalDocId) {
                dBucket = {
                    doctorId: canonicalDocId,
                    userId: null,
                    doctorName: a.dentist_name || 'Doctor',
                    specialty: a.doctor_specialty || 'General Medicine',
                    clinicId: a.clinic_id || null,
                    clinicName: a.clinic_name || '',
                    scheduledConsultations: 0,
                    actualPatientVisits: 0,
                    _visitedPatientsSet: new Set(),
                    completedConsultations: 0,
                    pendingConsultations: 0,
                    cancelledConsultations: 0,
                    noShowConsultations: 0,
                    onlineConsultations: 0,
                    inPersonConsultations: 0,
                };
                doctorStatsMap.set(canonicalDocId, dBucket);
            }
            if (dBucket) {
                dBucket.scheduledConsultations += 1;
                if (cls.actuallyVisited) {
                    dBucket._visitedPatientsSet.add(_getUniquePatientKeyFromAppointment(a));
                }
                if (cls.isCompleted) dBucket.completedConsultations += 1;
                else if (cls.isCancelled) dBucket.cancelledConsultations += 1;
                else if (cls.isNoShow) dBucket.noShowConsultations += 1;
                else if (cls.isPending) dBucket.pendingConsultations += 1;

                if (cls.isOnline) dBucket.onlineConsultations += 1;
                else dBucket.inPersonConsultations += 1;
            }
        }

        const doctorBreakdown = Array.from(doctorStatsMap.values())
            .filter(d => {
                if (filterDoctor && filterDoctor.toLowerCase() !== 'all') {
                    const fLower = filterDoctor.toLowerCase();
                    return d.doctorId === filterDoctor ||
                        d.userId === filterDoctor ||
                        d.doctorName.toLowerCase().includes(fLower);
                }
                return true;
            })
            .map(d => {
                const actualPatientVisits = d._visitedPatientsSet.size;
                const copy = { ...d, actualPatientVisits };
                delete copy._visitedPatientsSet;
                return copy;
            });

        const selectedDateStats = {
            date: selectedDate,
            totalScheduledAppointments: apptsOnSelectedDate.length,
            actualPatientVisits: uniqueVisitedPatientsOnDate.size,
            completedAppointments: completedCount,
            pendingAppointments: pendingCount,
            cancelledAppointments: cancelledCount,
            noShowAppointments: noShowCount,
            onlineConsultations: onlineCount,
            inPersonConsultations: inPersonCount,
            newPatientRegistrations: newRegistrationsOnSelectedDate.length,
            patientReferrals: referralsOnSelectedDate.length,
            hospitalCount: hospitalClinicBreakdown.length,
            doctorCount: doctorBreakdown.length,
        };

        res.json({
            success: true,
            timezone: tz,
            selectedDate,
            month: selectedMonth,
            isSubAdminScoped: isSubAdmin,
            assignedDistricts: isSubAdmin ? assignedDistricts : [],
            selectedDateStats,
            monthlyCalendar,
            hospitalClinicBreakdown,
            doctorBreakdown,
            visits: visitsList,
            referralsOnDate: referralsOnSelectedDate,
            allReferrals: allReferralEntries,
        });
    } catch (err) {
        console.error('Get Admin Global Visits Calendar Error:', err.message);
        res.status(500).json({
            success: false,
            message: 'Failed to load Admin Global Visits Calendar.',
        });
    }
};


