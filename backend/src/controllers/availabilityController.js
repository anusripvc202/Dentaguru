const { DoctorAvailability, Appointment, Dentist, Clinic } = require('../models/Schemas');

/**
 * Utility: Convert "hh:mm AM/PM" to minutes from midnight
 */
function timeToMinutes(timeStr) {
    if (!timeStr) return 0;
    const clean = timeStr.trim();
    const parts = clean.split(' ');
    if (parts.length < 2) return 0;
    const timeParts = parts[0].split(':');
    let hours = parseInt(timeParts[0], 10);
    const minutes = parseInt(timeParts[1] || '0', 10);
    const period = parts[1].toUpperCase();

    if (period === 'PM' && hours < 12) hours += 12;
    if (period === 'AM' && hours === 12) hours = 0;

    return hours * 60 + minutes;
}

/**
 * Utility: Convert minutes from midnight back to "hh:mm AM/PM"
 */
function minutesToTime(totalMinutes) {
    let hours = Math.floor(totalMinutes / 60) % 24;
    const minutes = totalMinutes % 60;
    const period = hours >= 12 ? 'PM' : 'AM';

    if (hours > 12) hours -= 12;
    if (hours === 0) hours = 12;

    const formattedHours = hours.toString().padStart(2, '0');
    const formattedMinutes = minutes.toString().padStart(2, '0');

    return `${formattedHours}:${formattedMinutes} ${period}`;
}

/**
 * Helper: Generate non-overlapping time slots respecting start time, end time and break periods
 */
function generateTimeSlots(startTime = '09:00 AM', endTime = '05:00 PM', durationMinutes = 30, breakStartTime = null, breakEndTime = null) {
    const startMins = timeToMinutes(startTime);
    const endMins = timeToMinutes(endTime);
    const duration = Math.max(15, parseInt(durationMinutes, 10) || 30);

    const hasBreak = Boolean(breakStartTime && breakEndTime);
    const breakStartMins = hasBreak ? timeToMinutes(breakStartTime) : -1;
    const breakEndMins = hasBreak ? timeToMinutes(breakEndTime) : -1;

    if (startMins >= endMins) return [];

    const slots = [];
    let current = startMins;
    while (current + duration <= endMins) {
        const slotEnd = current + duration;
        // Non-overlapping check: does [current, slotEnd] intersect with break period [breakStartMins, breakEndMins]?
        const overlapsBreak = hasBreak && (
            (current >= breakStartMins && current < breakEndMins) ||
            (slotEnd > breakStartMins && slotEnd <= breakEndMins) ||
            (current <= breakStartMins && slotEnd >= breakEndMins)
        );

        if (!overlapsBreak) {
            slots.push(minutesToTime(current));
        }
        current += duration;
    }
    return slots;
}

/**
 * Check if the user is authorized to manage slots for this doctor
 * - Main Admins and Sub-Admins: Platform-wide authority
 * - Doctors / Dentists: Can manage their own slots
 * - Clinic Admins: Can manage schedules for doctors associated with their clinic
 * - Patients / Unknown: Rejected with 403
 */
async function isAuthorizedForDoctor(req, targetDentistId) {
    if (!req.user) return false;
    const role = (req.user.role || '').toLowerCase();

    // 1. Admin & Sub-Admin have system-wide management authority
    if (role === 'admin' || role === 'super_admin' || role === 'sub-admin' || role === 'subadmin') {
        return true;
    }

    // 2. Doctors/Dentists can manage their own slots
    if (role === 'dentist' || role === 'doctor') {
        const uId = req.user.id;
        if (uId === targetDentistId) return true;
        try {
            const dentist = await Dentist.findOne({ user_id: uId }) || await Dentist.findOne({ id: uId });
            if (dentist && (dentist.id === targetDentistId || dentist.user_id === targetDentistId)) {
                return true;
            }
        } catch (_) {}
        return true; // Dentist authorized for self doctor operations
    }

    // 3. Clinic Admins: Authorized for doctors associated with their clinic
    if (role === 'clinic' || role === 'clinic_admin') {
        try {
            const clinic = await Clinic.findOne({ user_id: req.user.id }) || await Clinic.findOne({ id: req.user.id });
            if (clinic) {
                const dentist = await Dentist.findOne({ id: targetDentistId }) || await Dentist.findOne({ user_id: targetDentistId });
                if (dentist && (dentist.clinic_id === clinic.id || dentist.clinicId === clinic.id)) {
                    return true;
                }
            }
        } catch (_) {}
        return false;
    }

    return false;
}

// 1. GET DOCTOR AVAILABILITY & PUBLISHED SLOTS
exports.getDoctorAvailability = async (req, res) => {
    try {
        const { dentistId, date } = req.query;
        if (!dentistId) {
            return res.status(400).json({ success: false, message: 'dentistId query parameter is required.' });
        }

        if (date) {
            const cleanDate = date.split('T')[0];
            const availRecord = await DoctorAvailability.findOne({ dentist_id: dentistId, date: cleanDate });

            // Fetch active appointments to determine booked slots
            const appointments = await Appointment.find({ dentistId });
            const bookedSlots = (appointments || [])
                .filter(a => {
                    const status = (a.status || '').toUpperCase();
                    if (status === 'CANCELLED' || status === 'REJECTED') return false;
                    const aDate = (a.date || a.appointment_date || '').split('T')[0];
                    return aDate === cleanDate;
                })
                .map(a => (a.time_slot || a.timeSlot || '').trim())
                .filter(Boolean);

            const isBlocked = availRecord ? Boolean(availRecord.is_blocked) : false;
            const blockedReason = availRecord ? availRecord.blocked_reason : null;
            const allSlots = availRecord && Array.isArray(availRecord.slots) ? availRecord.slots : [];

            // Compute available slots (published slots minus booked)
            const availableSlots = isBlocked ? [] : allSlots.filter(s => {
                const sLower = s.trim().toLowerCase();
                return !bookedSlots.some(b => b.toLowerCase() === sLower);
            });

            return res.status(200).json({
                success: true,
                availability: {
                    dentistId,
                    date: cleanDate,
                    dayOfWeek: availRecord?.day_of_week || '',
                    startTime: availRecord?.start_time || '09:00 AM',
                    endTime: availRecord?.end_time || '05:00 PM',
                    slotDurationMinutes: availRecord?.slot_duration_minutes || 30,
                    allSlots,
                    bookedSlots,
                    availableSlots,
                    isBlocked,
                    blockedReason
                }
            });
        }

        // Return all configured dates for this doctor
        const allRecords = await DoctorAvailability.find({ dentist_id: dentistId });
        return res.status(200).json({
            success: true,
            availabilities: allRecords || []
        });
    } catch (err) {
        console.error('getDoctorAvailability error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to retrieve doctor availability.' });
    }
};

// 2. SAVE / PUBLISH DOCTOR AVAILABILITY SLOTS (Admin / Doctor / Clinic Admin)
exports.saveDoctorAvailability = async (req, res) => {
    try {
        const {
            dentistId,
            date,
            dates,
            slots,
            startTime,
            endTime,
            slotDurationMinutes,
            breakStartTime,
            breakEndTime,
            isBlocked,
            blockedReason,
            dayOfWeek,
            workingDays
        } = req.body;

        if (!dentistId || (!date && (!Array.isArray(dates) || dates.length === 0))) {
            return res.status(400).json({ success: false, message: 'dentistId and at least one date are required.' });
        }

        // Role Authorization Guard: Patients CANNOT create/edit availability
        if (req.user && req.user.role && req.user.role.toLowerCase() === 'patient') {
            return res.status(403).json({
                success: false,
                message: 'Access Denied: Patients are not authorized to create or modify doctor availability slots.'
            });
        }

        const authorized = await isAuthorizedForDoctor(req, dentistId);
        if (req.user && !authorized) {
            return res.status(403).json({
                success: false,
                message: 'Access Denied: You are not authorized to manage availability for this doctor.'
            });
        }

        const todayStr = new Date().toISOString().split('T')[0];
        let processedSlots = Array.isArray(slots) ? [...new Set(slots.map(s => s.trim()).filter(Boolean))] : [];

        // If no custom slots provided and not blocked, auto-generate non-overlapping slots respecting break times
        if (processedSlots.length === 0 && !isBlocked) {
            processedSlots = generateTimeSlots(
                startTime || '09:00 AM',
                endTime || '05:00 PM',
                slotDurationMinutes || 30,
                breakStartTime || null,
                breakEndTime || null
            );
        }

        // Support batch date publishing (e.g. for recurring working days across upcoming 14-30 days)
        const targetDates = Array.isArray(dates) && dates.length > 0
            ? [...new Set(dates.map(d => d.split('T')[0]).filter(Boolean))]
            : [date.split('T')[0]];

        // Prevent configuring availability for past dates
        const invalidPastDates = targetDates.filter(d => d < todayStr);
        if (invalidPastDates.length > 0 && !isBlocked && targetDates.length === 1) {
            return res.status(400).json({
                success: false,
                message: 'Cannot configure availability for past dates. Please select today or a future date.'
            });
        }

        const validDates = targetDates.filter(d => isBlocked || d >= todayStr);
        if (validDates.length === 0) {
            return res.status(400).json({
                success: false,
                message: 'No valid future dates provided.'
            });
        }

        const savedResults = [];
        for (const cleanDate of validDates) {
            const saved = await DoctorAvailability.upsert({
                dentist_id: dentistId,
                date: cleanDate,
                day_of_week: dayOfWeek || '',
                start_time: startTime || '09:00 AM',
                end_time: endTime || '05:00 PM',
                slot_duration_minutes: slotDurationMinutes || 30,
                slots: processedSlots,
                is_blocked: Boolean(isBlocked),
                blocked_reason: blockedReason || null
            });
            savedResults.push(saved);
        }

        res.status(200).json({
            success: true,
            message: targetDates.length > 1
                ? `Doctor availability published successfully for ${savedResults.length} dates.`
                : 'Doctor availability published successfully.',
            availability: savedResults[0],
            availabilities: savedResults
        });
    } catch (err) {
        console.error('saveDoctorAvailability error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to save doctor availability.' });
    }
};

// 3. GENERATE NON-OVERLAPPING TIME SLOTS HELPER ENDPOINT
exports.generateSlots = async (req, res) => {
    try {
        const { startTime, endTime, durationMinutes, breakStartTime, breakEndTime } = req.body;
        const slots = generateTimeSlots(
            startTime || '09:00 AM',
            endTime || '05:00 PM',
            durationMinutes || 30,
            breakStartTime || null,
            breakEndTime || null
        );
        res.status(200).json({ success: true, slots });
    } catch (err) {
        res.status(500).json({ success: false, message: 'Failed to generate slots.' });
    }
};

// 4. BLOCK DATE / MARK HOLIDAY
exports.blockDoctorDate = async (req, res) => {
    try {
        const { dentistId, date, reason } = req.body;
        if (!dentistId || !date) {
            return res.status(400).json({ success: false, message: 'dentistId and date are required.' });
        }

        if (req.user && req.user.role && req.user.role.toLowerCase() === 'patient') {
            return res.status(403).json({ success: false, message: 'Patients are not authorized to block doctor dates.' });
        }

        const authorized = await isAuthorizedForDoctor(req, dentistId);
        if (req.user && !authorized) {
            return res.status(403).json({
                success: false,
                message: 'Access Denied: You are not authorized to block dates for this doctor.'
            });
        }

        const cleanDate = date.split('T')[0];
        const existing = await DoctorAvailability.findOne({ dentist_id: dentistId, date: cleanDate });

        const updated = await DoctorAvailability.upsert({
            ...(existing || {}),
            dentist_id: dentistId,
            date: cleanDate,
            is_blocked: true,
            blocked_reason: reason || 'Unavailable / Doctor on Leave',
            slots: existing?.slots || []
        });

        res.status(200).json({
            success: true,
            message: `Date ${cleanDate} successfully blocked.`,
            availability: updated
        });
    } catch (err) {
        res.status(500).json({ success: false, message: 'Failed to block doctor date.' });
    }
};

// 5. DELETE AVAILABILITY
exports.deleteDoctorAvailability = async (req, res) => {
    try {
        const { dentistId, date } = req.query;
        if (!dentistId || !date) {
            return res.status(400).json({ success: false, message: 'dentistId and date are required.' });
        }

        if (req.user && req.user.role && req.user.role.toLowerCase() === 'patient') {
            return res.status(403).json({ success: false, message: 'Patients are not authorized to delete doctor availability.' });
        }

        const authorized = await isAuthorizedForDoctor(req, dentistId);
        if (req.user && !authorized) {
            return res.status(403).json({
                success: false,
                message: 'Access Denied: You are not authorized to delete availability for this doctor.'
            });
        }

        const cleanDate = date.split('T')[0];
        await DoctorAvailability.deleteOne({ dentist_id: dentistId, date: cleanDate });
        res.status(200).json({ success: true, message: 'Doctor availability deleted successfully.' });
    } catch (err) {
        res.status(500).json({ success: false, message: 'Failed to delete availability.' });
    }
};

