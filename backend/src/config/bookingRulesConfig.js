/**
 * Centralized, separately configurable Smart Hybrid Appointment Booking & Slot Generation Rules.
 * Unifies In-Person & Online consultations on one doctor calendar with configurable durations,
 * post-consultation buffers, advance booking lead times, slot intervals, max booking windows,
 * server-side timezone handling, and admin delay alert thresholds.
 */
const DEFAULT_TIMEZONE = process.env.CLINIC_TIMEZONE || 'Asia/Kolkata';

const bookingRulesState = {
    inPersonDurationMinutes: Number(process.env.IN_PERSON_DURATION_MINUTES || 30),
    onlineDurationMinutes: Number(process.env.ONLINE_DURATION_MINUTES || 20),
    inPersonBufferMinutes: Number(process.env.IN_PERSON_BUFFER_MINUTES || 10),
    onlineBufferMinutes: Number(process.env.ONLINE_BUFFER_MINUTES || 5),
    minAdvanceBookingMinutes: Number(process.env.MIN_ADVANCE_BOOKING_MINUTES || 30),
    defaultSlotIntervalMinutes: Number(process.env.DEFAULT_SLOT_INTERVAL_MINUTES || 30),
    maxAdvanceBookingDays: Number(process.env.MAX_ADVANCE_BOOKING_DAYS || 90),
    adminDelayAlertThresholdMinutes: Number(process.env.ADMIN_DELAY_ALERT_THRESHOLD_MINUTES || 15),
    timezone: DEFAULT_TIMEZONE,
    debugNowOverride: null,
};

const APPOINTMENT_STATUSES = [
    'PENDING',
    'CONFIRMED',
    'IN_PROGRESS',
    'DELAYED',
    'COMPLETED',
    'NO_SHOW',
    'CANCELLED',
    'REJECTED',
    'RESCHEDULED',
];

const DOCTOR_PRESENCE_AND_SCHEDULE_STATUSES = [
    'Available',
    'Busy – Online Consultation',
    'Busy – In-Person Consultation',
    'Delayed',
    'Offline',
    'Online',
    'Busy',
    'Unavailable',
];

function getBookingRulesConfig() {
    return {
        inPersonDurationMinutes: bookingRulesState.inPersonDurationMinutes,
        onlineDurationMinutes: bookingRulesState.onlineDurationMinutes,
        inPersonBufferMinutes: bookingRulesState.inPersonBufferMinutes,
        onlineBufferMinutes: bookingRulesState.onlineBufferMinutes,
        minAdvanceBookingMinutes: bookingRulesState.minAdvanceBookingMinutes,
        defaultSlotIntervalMinutes: bookingRulesState.defaultSlotIntervalMinutes,
        maxAdvanceBookingDays: bookingRulesState.maxAdvanceBookingDays,
        adminDelayAlertThresholdMinutes: bookingRulesState.adminDelayAlertThresholdMinutes,
        timezone: bookingRulesState.timezone,
    };
}

function setBookingRulesConfig(overrides = {}) {
    if (overrides.inPersonDurationMinutes !== undefined) {
        bookingRulesState.inPersonDurationMinutes = Math.max(5, Number(overrides.inPersonDurationMinutes) || 30);
    }
    if (overrides.onlineDurationMinutes !== undefined) {
        bookingRulesState.onlineDurationMinutes = Math.max(5, Number(overrides.onlineDurationMinutes) || 20);
    }
    if (overrides.inPersonBufferMinutes !== undefined) {
        bookingRulesState.inPersonBufferMinutes = Math.max(0, Number(overrides.inPersonBufferMinutes) ?? 0);
    }
    if (overrides.onlineBufferMinutes !== undefined) {
        bookingRulesState.onlineBufferMinutes = Math.max(0, Number(overrides.onlineBufferMinutes) ?? 0);
    }
    if (overrides.minAdvanceBookingMinutes !== undefined) {
        bookingRulesState.minAdvanceBookingMinutes = Math.max(0, Number(overrides.minAdvanceBookingMinutes) ?? 0);
    }
    if (overrides.defaultSlotIntervalMinutes !== undefined) {
        bookingRulesState.defaultSlotIntervalMinutes = Math.max(5, Number(overrides.defaultSlotIntervalMinutes) || 30);
    }
    if (overrides.maxAdvanceBookingDays !== undefined) {
        bookingRulesState.maxAdvanceBookingDays = Math.max(1, Number(overrides.maxAdvanceBookingDays) || 90);
    }
    if (overrides.adminDelayAlertThresholdMinutes !== undefined) {
        bookingRulesState.adminDelayAlertThresholdMinutes = Math.max(1, Number(overrides.adminDelayAlertThresholdMinutes) || 15);
    }
    if (overrides.timezone !== undefined && String(overrides.timezone).trim()) {
        const candidateTz = String(overrides.timezone).trim();
        try {
            new Intl.DateTimeFormat('en-US', { timeZone: candidateTz }).format(new Date());
            bookingRulesState.timezone = candidateTz;
        } catch (_) {}
    }
    if (overrides.debugNowOverride !== undefined) {
        bookingRulesState.debugNowOverride = overrides.debugNowOverride;
    }
    return getBookingRulesConfig();
}

function resetBookingRulesConfig() {
    bookingRulesState.inPersonDurationMinutes = Number(process.env.IN_PERSON_DURATION_MINUTES || 30);
    bookingRulesState.onlineDurationMinutes = Number(process.env.ONLINE_DURATION_MINUTES || 20);
    bookingRulesState.inPersonBufferMinutes = Number(process.env.IN_PERSON_BUFFER_MINUTES || 10);
    bookingRulesState.onlineBufferMinutes = Number(process.env.ONLINE_BUFFER_MINUTES || 5);
    bookingRulesState.minAdvanceBookingMinutes = Number(process.env.MIN_ADVANCE_BOOKING_MINUTES || 30);
    bookingRulesState.defaultSlotIntervalMinutes = Number(process.env.DEFAULT_SLOT_INTERVAL_MINUTES || 30);
    bookingRulesState.maxAdvanceBookingDays = Number(process.env.MAX_ADVANCE_BOOKING_DAYS || 90);
    bookingRulesState.adminDelayAlertThresholdMinutes = Number(process.env.ADMIN_DELAY_ALERT_THRESHOLD_MINUTES || 15);
    bookingRulesState.timezone = DEFAULT_TIMEZONE;
    bookingRulesState.debugNowOverride = null;
}

function getNowPartsInTimezone(dateObj = new Date(), tz = bookingRulesState.timezone) {
    const d = dateObj instanceof Date ? dateObj : new Date(dateObj);
    const effectiveTz = tz || DEFAULT_TIMEZONE;
    try {
        const fmt = new Intl.DateTimeFormat('en-CA', {
            timeZone: effectiveTz,
            year: 'numeric',
            month: '2-digit',
            day: '2-digit',
            hour: '2-digit',
            minute: '2-digit',
            hour12: false,
        });
        const parts = fmt.formatToParts(d);
        const map = {};
        for (const p of parts) {
            if (p.type !== 'literal') map[p.type] = p.value;
        }
        const rawHour = parseInt(map.hour || '0', 10);
        const hours = rawHour === 24 ? 0 : rawHour;
        const minutes = parseInt(map.minute || '0', 10);
        return {
            ymd: `${map.year}-${map.month}-${map.day}`,
            hours,
            minutes,
            totalMinutes: hours * 60 + minutes,
            timezone: effectiveTz,
        };
    } catch (_) {
        const yyyy = d.getFullYear();
        const mm = String(d.getMonth() + 1).padStart(2, '0');
        const dd = String(d.getDate()).padStart(2, '0');
        const hours = d.getHours();
        const minutes = d.getMinutes();
        return {
            ymd: `${yyyy}-${mm}-${dd}`,
            hours,
            minutes,
            totalMinutes: hours * 60 + minutes,
            timezone: 'local',
        };
    }
}

function formatYmdInTimezone(dateObj = new Date(), tz = bookingRulesState.timezone) {
    return getNowPartsInTimezone(dateObj, tz).ymd;
}

function formatLocalYmd(dateObj) {
    return formatYmdInTimezone(dateObj || new Date(), bookingRulesState.timezone);
}

/**
 * Normalizes a plain YYYY-MM-DD date string or ISO timestamp into an Asia/Kolkata (or specified tz) YYYY-MM-DD date string.
 * - Plain 'YYYY-MM-DD' or midnight 'YYYY-MM-DDT00:00:00(.000)Z' preserves 'YYYY-MM-DD'.
 * - Full ISO timestamps with time/offset (e.g. '2026-11-25T20:15:00.000Z') are converted to the calendar date in `tz`.
 */
function normalizeDateToTimezoneYmd(rawDateOrTimestamp, tz = bookingRulesState.timezone) {
    if (!rawDateOrTimestamp) return '';
    if (rawDateOrTimestamp instanceof Date) {
        if (Number.isNaN(rawDateOrTimestamp.getTime())) return '';
        return formatYmdInTimezone(rawDateOrTimestamp, tz);
    }
    const str = String(rawDateOrTimestamp).trim();
    if (!str) return '';
    if (/^\d{4}-\d{2}-\d{2}$/.test(str)) {
        return str;
    }
    if (/^\d{4}-\d{2}-\d{2}T00:00:00(?:\.000)?Z?$/i.test(str)) {
        return str.slice(0, 10);
    }
    const parsed = new Date(str);
    if (!Number.isNaN(parsed.getTime())) {
        return formatYmdInTimezone(parsed, tz);
    }
    if (/^\d{4}-\d{2}-\d{2}/.test(str)) {
        return str.slice(0, 10);
    }
    return '';
}

function addDaysToYmd(ymd, days) {
    const m = String(ymd || '').trim().match(/^(\d{4})-(\d{2})-(\d{2})/);
    if (!m) return '';
    const dt = new Date(Date.UTC(parseInt(m[1], 10), parseInt(m[2], 10) - 1, parseInt(m[3], 10) + (Number(days) || 0)));
    return dt.toISOString().split('T')[0];
}

function parseClockSlotMinutes(slotStr) {
    if (!slotStr) return null;
    const match = String(slotStr).trim().match(/^(\d{1,2}):(\d{2})\s*(AM|PM)$/i);
    if (!match) return null;
    let hours = parseInt(match[1], 10);
    const mins = parseInt(match[2], 10);
    const period = match[3].toUpperCase();
    if (hours < 1 || hours > 12 || mins < 0 || mins > 59) return null;
    if (period === 'PM' && hours < 12) hours += 12;
    if (period === 'AM' && hours === 12) hours = 0;
    return hours * 60 + mins;
}

function minutesToClockSlot(totalMinutes) {
    const wrapped = ((Math.round(totalMinutes) % 1440) + 1440) % 1440;
    let hours = Math.floor(wrapped / 60);
    const mins = wrapped % 60;
    const period = hours >= 12 ? 'PM' : 'AM';
    if (hours > 12) hours -= 12;
    if (hours === 0) hours = 12;
    return `${String(hours).padStart(2, '0')}:${String(mins).padStart(2, '0')} ${period}`;
}

function normalizeConsultationType(raw, fallbackTreatment = '') {
    const combined = `${raw || ''} ${fallbackTreatment || ''}`.trim().toLowerCase();
    if (
        combined.includes('online') ||
        combined.includes('video') ||
        combined.includes('teleconsult') ||
        combined.includes('virtual')
    ) {
        return 'Online';
    }
    return 'In-Person';
}

function getConsultationTimingForType(consultationType, rulesOverride = null) {
    const rules = { ...getBookingRulesConfig(), ...(rulesOverride || {}) };
    const mode = normalizeConsultationType(consultationType);
    const durationMinutes = mode === 'Online'
        ? Math.max(5, Number(rules.onlineDurationMinutes) || 20)
        : Math.max(5, Number(rules.inPersonDurationMinutes) || 30);
    const bufferMinutes = mode === 'Online'
        ? Math.max(0, Number(rules.onlineBufferMinutes) ?? 5)
        : Math.max(0, Number(rules.inPersonBufferMinutes) ?? 10);
    return {
        consultationType: mode,
        durationMinutes,
        bufferMinutes,
        totalBlockedMinutes: durationMinutes + bufferMinutes,
    };
}

function checkSlotBookableForDateYmd(dateYmd, slotStr, options = {}) {
    const tz = options.timezone || bookingRulesState.timezone;
    const now = options.now || bookingRulesState.debugNowOverride || new Date();
    const minAdvance = options.minAdvanceBookingMinutes !== undefined
        ? Number(options.minAdvanceBookingMinutes)
        : bookingRulesState.minAdvanceBookingMinutes;
    const maxAdvanceDays = options.maxAdvanceBookingDays !== undefined
        ? Number(options.maxAdvanceBookingDays)
        : bookingRulesState.maxAdvanceBookingDays;

    const cleanDate = String(dateYmd || '').trim().split('T')[0];
    const nowParts = getNowPartsInTimezone(now, tz);
    const todayYmd = nowParts.ymd;

    if (!cleanDate || cleanDate < todayYmd) {
        return {
            bookable: false,
            reason: 'PAST_DATE',
            message: 'Cannot book appointments for past dates. Please select today or a future date.',
        };
    }

    const maxAllowedYmd = addDaysToYmd(todayYmd, maxAdvanceDays);
    if (maxAllowedYmd && cleanDate > maxAllowedYmd) {
        return {
            bookable: false,
            reason: 'EXCEEDS_MAX_ADVANCE_WINDOW',
            message: `Appointments can only be booked up to ${maxAdvanceDays} days in advance (until ${maxAllowedYmd}).`,
        };
    }

    if (cleanDate === todayYmd) {
        const slotMins = parseClockSlotMinutes(slotStr);
        if (slotMins !== null) {
            const nowMins = nowParts.totalMinutes;
            if (slotMins <= nowMins) {
                return {
                    bookable: false,
                    reason: 'PAST_SLOT',
                    message: `The selected time slot (${slotStr}) has already passed for today. Please choose a future slot.`,
                };
            }
            if (slotMins < nowMins + minAdvance) {
                return {
                    bookable: false,
                    reason: 'INSUFFICIENT_ADVANCE_NOTICE',
                    message: `Appointments must be booked at least ${minAdvance} minutes in advance. Please select a later slot.`,
                };
            }
        }
    }

    return { bookable: true, reason: 'OK', message: '' };
}

function filterBookableSlotsForDateYmd(dateYmd, slots, options = {}) {
    if (!Array.isArray(slots)) return [];
    return slots.filter((s) => checkSlotBookableForDateYmd(dateYmd, s, options).bookable);
}

function extractAppointmentScheduleMeta(appt = {}) {
    if (!appt || typeof appt !== 'object') return {};
    if (appt.scheduleMeta && typeof appt.scheduleMeta === 'object') {
        return { ...appt.scheduleMeta };
    }
    const rawQr = appt.qr_code_string ?? appt.qrCodeString;
    if (rawQr && typeof rawQr === 'string' && rawQr.trim().startsWith('{')) {
        try {
            const parsed = JSON.parse(rawQr);
            if (parsed && typeof parsed === 'object') {
                if (parsed.scheduleMeta && typeof parsed.scheduleMeta === 'object') {
                    return { ...parsed.scheduleMeta };
                }
                if (parsed._smartSched) {
                    return { ...parsed._smartSched };
                }
            }
        } catch (_) {}
    }
    return {};
}

function encodeAppointmentQrWithMeta(existingQr, nextMeta = {}) {
    let baseCode = `DENTAGURU-${Date.now()}`;
    let prevMeta = {};
    if (existingQr && typeof existingQr === 'string') {
        const trimmed = existingQr.trim();
        if (trimmed.startsWith('{')) {
            try {
                const parsed = JSON.parse(trimmed);
                if (parsed && typeof parsed === 'object') {
                    baseCode = parsed.code || baseCode;
                    prevMeta = parsed.scheduleMeta || parsed._smartSched || {};
                }
            } catch (_) {
                baseCode = trimmed;
            }
        } else if (trimmed) {
            baseCode = trimmed;
        }
    }
    return JSON.stringify({
        code: baseCode,
        scheduleMeta: { ...prevMeta, ...nextMeta },
    });
}

function intervalsOverlap(startA, endA, startB, endB) {
    return startA < endB && endA > startB;
}

function getAppointmentOccupiedInterval(appt, rulesOverride = null, nowDate = null) {
    if (!appt || typeof appt !== 'object') return null;
    const status = String(appt.status || 'PENDING').trim().toUpperCase();
    if (status === 'CANCELLED' || status === 'REJECTED' || status === 'NO_SHOW') {
        return null;
    }

    const meta = extractAppointmentScheduleMeta(appt);
    const slotStr = (appt.time_slot || appt.timeSlot || meta.scheduledStartTime || '').toString().trim();
    const startMin = parseClockSlotMinutes(slotStr);
    if (startMin === null) return null;

    const consultationType = normalizeConsultationType(
        meta.consultationType || appt.consultation_type || appt.consultationMode,
        appt.treatment || ''
    );
    const timing = getConsultationTimingForType(consultationType, rulesOverride);
    const durationMinutes = Number(meta.durationMinutes || appt.duration_minutes) > 0
        ? Number(meta.durationMinutes || appt.duration_minutes)
        : timing.durationMinutes;
    const bufferMinutes = meta.bufferMinutes !== undefined && Number(meta.bufferMinutes) >= 0
        ? Number(meta.bufferMinutes)
        : (appt.buffer_minutes !== undefined && Number(appt.buffer_minutes) >= 0 ? Number(appt.buffer_minutes) : timing.bufferMinutes);

    const scheduledEndMin = startMin + durationMinutes;
    const rules = { ...getBookingRulesConfig(), ...(rulesOverride || {}) };
    const now = nowDate || bookingRulesState.debugNowOverride || new Date();
    const nowParts = getNowPartsInTimezone(now, rules.timezone);
    const apptDateYmd = String(appt.date || appt.appointment_date || '').trim().split('T')[0];

    let effectiveConsultEndMin = scheduledEndMin;
    let delayMinutes = Number(meta.delayMinutes || appt.delay_minutes || 0) || 0;

    if (status === 'COMPLETED' && (meta.actualEndAt || appt.actual_end_at)) {
        const actualParts = getNowPartsInTimezone(new Date(meta.actualEndAt || appt.actual_end_at), rules.timezone);
        if (!apptDateYmd || actualParts.ymd === apptDateYmd) {
            // Early completion frees the remainder of the consultation slot after post-consultation buffer!
            if (actualParts.totalMinutes >= startMin && actualParts.totalMinutes < scheduledEndMin) {
                effectiveConsultEndMin = actualParts.totalMinutes;
            }
        }
    } else if (status === 'IN_PROGRESS' || status === 'DELAYED') {
        if (apptDateYmd && nowParts.ymd === apptDateYmd && nowParts.totalMinutes > scheduledEndMin) {
            delayMinutes = Math.max(delayMinutes, nowParts.totalMinutes - scheduledEndMin);
        }
        effectiveConsultEndMin = scheduledEndMin + delayMinutes;
    } else if (delayMinutes > 0) {
        effectiveConsultEndMin = scheduledEndMin + delayMinutes;
    }

    const occupiedEndMin = effectiveConsultEndMin + bufferMinutes;
    return {
        appointmentId: appt.id ? String(appt.id) : '',
        patientId: appt.patient_id ? String(appt.patient_id) : '',
        status,
        consultationType,
        timeSlot: slotStr,
        startMin,
        durationMinutes,
        bufferMinutes,
        scheduledEndMin,
        effectiveConsultEndMin,
        occupiedEndMin,
        delayMinutes,
        scheduledEndTime: minutesToClockSlot(scheduledEndMin),
        bufferEndTime: minutesToClockSlot(occupiedEndMin),
    };
}

function computeUnifiedAvailableSlots({
    dateYmd,
    baseSlots = [],
    workingEndTime = null,
    breakStartTime = null,
    breakEndTime = null,
    activeAppointments = [],
    blockedSlots = [],
    consultationType = 'In-Person',
    rulesOverride = null,
    now = null,
    excludeAppointmentId = null,
}) {
    if (!Array.isArray(baseSlots) || baseSlots.length === 0) return [];
    const candidateTiming = getConsultationTimingForType(consultationType, rulesOverride);
    const workingEndMin = workingEndTime ? parseClockSlotMinutes(workingEndTime) : null;
    const breakStartMin = breakStartTime ? parseClockSlotMinutes(breakStartTime) : null;
    const breakEndMin = breakEndTime ? parseClockSlotMinutes(breakEndTime) : null;
    const hasBreak = breakStartMin !== null && breakEndMin !== null && breakEndMin > breakStartMin;

    const occupiedIntervals = (activeAppointments || [])
        .filter(a => !excludeAppointmentId || String(a.id) !== String(excludeAppointmentId))
        .map(a => getAppointmentOccupiedInterval(a, rulesOverride, now))
        .filter(Boolean);

    const parsedBlocked = (blockedSlots || [])
        .map(b => {
            if (typeof b === 'string') {
                const s = parseClockSlotMinutes(b);
                return s !== null ? { startMin: s, endMin: s + candidateTiming.durationMinutes } : null;
            }
            if (b && typeof b === 'object') {
                const s = b.startMin !== undefined ? Number(b.startMin) : parseClockSlotMinutes(b.startTime || b.timeSlot || b.slot);
                const e = b.endMin !== undefined
                    ? Number(b.endMin)
                    : (b.endTime ? parseClockSlotMinutes(b.endTime) : (s !== null ? s + (Number(b.durationMinutes) || candidateTiming.durationMinutes) : null));
                return s !== null && e !== null && e > s ? { startMin: s, endMin: e } : null;
            }
            return null;
        })
        .filter(Boolean);

    return baseSlots.filter((slot) => {
        const check = checkSlotBookableForDateYmd(dateYmd, slot, { ...(rulesOverride || {}), now });
        if (!check.bookable) return false;

        const candStart = parseClockSlotMinutes(slot);
        if (candStart === null) {
            // Non-clock label fallback: match exact booked strings only
            const lower = String(slot || '').trim().toLowerCase();
            return !(activeAppointments || []).some(a =>
                String(a.time_slot || a.timeSlot || '').trim().toLowerCase() === lower
            );
        }

        const candConsultEnd = candStart + candidateTiming.durationMinutes;
        const candOccupiedEnd = candStart + candidateTiming.totalBlockedMinutes;

        if (workingEndMin !== null && candConsultEnd > workingEndMin) {
            return false;
        }
        if (hasBreak && intervalsOverlap(candStart, candConsultEnd, breakStartMin, breakEndMin)) {
            return false;
        }
        if (parsedBlocked.some(b => intervalsOverlap(candStart, candConsultEnd, b.startMin, b.endMin))) {
            return false;
        }
        // Unified cross-type check: candidate [start, consultEnd + buffer] cannot overlap any existing [start, consultEnd + delay + buffer]
        if (occupiedIntervals.some(occ => intervalsOverlap(candStart, candOccupiedEnd, occ.startMin, occ.occupiedEndMin))) {
            return false;
        }
        return true;
    });
}

module.exports = {
    APPOINTMENT_STATUSES,
    DOCTOR_PRESENCE_AND_SCHEDULE_STATUSES,
    getBookingRulesConfig,
    setBookingRulesConfig,
    resetBookingRulesConfig,
    getNowPartsInTimezone,
    formatYmdInTimezone,
    formatLocalYmd,
    normalizeDateToTimezoneYmd,
    addDaysToYmd,
    parseClockSlotMinutes,
    minutesToClockSlot,
    normalizeConsultationType,
    getConsultationTimingForType,
    checkSlotBookableForDateYmd,
    filterBookableSlotsForDateYmd,
    extractAppointmentScheduleMeta,
    encodeAppointmentQrWithMeta,
    intervalsOverlap,
    getAppointmentOccupiedInterval,
    computeUnifiedAvailableSlots,
};
