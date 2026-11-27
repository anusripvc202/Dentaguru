/**
 * GS HEALTH — Smart Dynamic Appointment Scheduling & Early Slot Release Engine
 *
 * Pure, deterministic scheduling logic operating in Asia/Kolkata timezone:
 * - Working days & working hours
 * - Multiple breaks per day
 * - Separate Online & In-Person schedules, durations (15, 20, 30, 45, 60 min), and buffers
 * - Shared capacity across Online & In-Person unless explicitly separated
 * - Maximum appointments per day
 * - Blocked dates & custom blocked time ranges
 * - Active temporary slot lock awareness & released early-completion slot integration
 * - Strict early-completion slot release calculation (never moves confirmed visits; never auto-completes)
 */

const {
    getBookingRulesConfig,
    getNowPartsInTimezone,
    normalizeDateToTimezoneYmd,
    parseClockSlotMinutes,
    minutesToClockSlot,
    normalizeConsultationType,
    getConsultationTimingForType,
    checkSlotBookableForDateYmd,
    intervalsOverlap,
    getAppointmentOccupiedInterval,
} = require('../config/bookingRulesConfig');

const ALLOWED_DURATIONS = [15, 20, 30, 45, 60];
const FULL_WEEKDAYS = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const SHORT_TO_FULL_WEEKDAY = {
    mon: 'Monday', monday: 'Monday',
    tue: 'Tuesday', tues: 'Tuesday', tuesday: 'Tuesday',
    wed: 'Wednesday', wednesday: 'Wednesday',
    thu: 'Thursday', thur: 'Thursday', thurs: 'Thursday', thursday: 'Thursday',
    fri: 'Friday', friday: 'Friday',
    sat: 'Saturday', saturday: 'Saturday',
    sun: 'Sunday', sunday: 'Sunday',
};

const INACTIVE_APPOINTMENT_STATUSES = new Set(['CANCELLED', 'CANCELED', 'REJECTED', 'NO_SHOW']);

const DEFAULT_SMART_SCHEDULE = {
    workingDays: ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'],
    startTime: '09:00 AM',
    endTime: '05:00 PM',
    breaks: [{ startTime: '01:00 PM', endTime: '02:00 PM', label: 'Lunch Break' }],
    hasBreak: true,
    breakStartTime: '01:00 PM',
    breakEndTime: '02:00 PM',
    slotDurationMinutes: 30,
    slotIntervalMinutes: 30,
    defaultDurationMinutes: 30,
    inPersonEnabled: true,
    inPersonDurationMinutes: 30,
    onlineEnabled: true,
    onlineDurationMinutes: 20,
    useSeparateOnlineHours: false,
    onlineWorkingDays: null,
    onlineStartTime: null,
    onlineEndTime: null,
    onlineBreaks: null,
    onlineHasBreak: false,
    onlineBreakStartTime: null,
    onlineBreakEndTime: null,
    bufferMinutes: 5,
    onlineBufferMinutes: 5,
    inPersonBufferMinutes: 10,
    maxAppointmentsPerDay: null,
    allowSimultaneousOnlineAndInPerson: false,
    blockedTimeRanges: {},
    timezone: 'Asia/Kolkata',
    isConfigured: false,
};

function sanitizeAllowedDuration(val, fallback = 30) {
    const n = parseInt(String(val ?? ''), 10);
    if (ALLOWED_DURATIONS.includes(n)) return n;
    return ALLOWED_DURATIONS.includes(fallback) ? fallback : 30;
}

function sanitizeBufferMinutes(val, fallback = 5) {
    if (val === undefined || val === null || val === '') return fallback;
    const n = parseInt(String(val), 10);
    if (!Number.isFinite(n)) return fallback;
    return Math.max(0, Math.min(60, n));
}

function normalizeWorkingDaysList(rawDays) {
    let arr = [];
    if (Array.isArray(rawDays)) {
        arr = rawDays;
    } else if (typeof rawDays === 'string') {
        const trimmed = rawDays.trim();
        if (trimmed.startsWith('[')) {
            try {
                const parsed = JSON.parse(trimmed);
                if (Array.isArray(parsed)) arr = parsed;
            } catch (_) {
                arr = trimmed.split(',');
            }
        } else if (trimmed) {
            arr = trimmed.split(',');
        }
    }
    const out = [];
    for (const item of arr) {
        const mapped = SHORT_TO_FULL_WEEKDAY[String(item || '').trim().toLowerCase()];
        if (mapped && !out.includes(mapped)) out.push(mapped);
    }
    return FULL_WEEKDAYS.filter(d => out.includes(d));
}

function sanitizeBreaksList(raw = {}, fallback = DEFAULT_SMART_SCHEDULE) {
    const rawBreaks = raw.breaks;
    const cleaned = [];

    if (Array.isArray(rawBreaks)) {
        for (const item of rawBreaks) {
            if (!item || typeof item !== 'object') continue;
            const sStr = String(item.startTime || item.start_time || '').trim();
            const eStr = String(item.endTime || item.end_time || '').trim();
            const sMin = parseClockSlotMinutes(sStr);
            const eMin = parseClockSlotMinutes(eStr);
            if (sMin !== null && eMin !== null && eMin > sMin) {
                cleaned.push({
                    startTime: minutesToClockSlot(sMin),
                    endTime: minutesToClockSlot(eMin),
                    startMin: sMin,
                    endMin: eMin,
                    label: String(item.label || item.name || 'Break').trim(),
                });
            }
        }
        cleaned.sort((a, b) => a.startMin - b.startMin);
        return cleaned;
    }

    // Legacy single-break compatibility (hasBreak / breakStartTime / breakEndTime)
    const explicitHasBreak = raw.hasBreak !== undefined
        ? Boolean(raw.hasBreak)
        : (raw.has_break !== undefined ? Boolean(raw.has_break) : undefined);

    if (explicitHasBreak === false) {
        return [];
    }

    const legacyStart = String(raw.breakStartTime || raw.break_start_time || '').trim();
    const legacyEnd = String(raw.breakEndTime || raw.break_end_time || '').trim();
    if (legacyStart && legacyEnd) {
        const sMin = parseClockSlotMinutes(legacyStart);
        const eMin = parseClockSlotMinutes(legacyEnd);
        if (sMin !== null && eMin !== null && eMin > sMin) {
            return [{
                startTime: minutesToClockSlot(sMin),
                endTime: minutesToClockSlot(eMin),
                startMin: sMin,
                endMin: eMin,
                label: 'Lunch Break',
            }];
        }
    }

    if (explicitHasBreak === true) {
        const fbStart = String(fallback.breakStartTime || '01:00 PM').trim();
        const fbEnd = String(fallback.breakEndTime || '02:00 PM').trim();
        const sMin = parseClockSlotMinutes(fbStart) ?? 780;
        const eMin = parseClockSlotMinutes(fbEnd) ?? 840;
        return [{
            startTime: minutesToClockSlot(sMin),
            endTime: minutesToClockSlot(eMin),
            startMin: sMin,
            endMin: eMin,
            label: 'Lunch Break',
        }];
    }

    if (Array.isArray(fallback.breaks)) {
        return fallback.breaks.map(b => {
            const sMin = b.startMin ?? parseClockSlotMinutes(b.startTime) ?? 780;
            const eMin = b.endMin ?? parseClockSlotMinutes(b.endTime) ?? 840;
            return {
                startTime: minutesToClockSlot(sMin),
                endTime: minutesToClockSlot(eMin),
                startMin: sMin,
                endMin: eMin,
                label: b.label || 'Break',
            };
        }).filter(b => b.endMin > b.startMin);
    }

    return [];
}

function sanitizeOnlineBreaksList(raw = {}, fallback = DEFAULT_SMART_SCHEDULE) {
    const rawOnlineBreaks = raw.onlineBreaks !== undefined ? raw.onlineBreaks : raw.online_breaks;
    if (rawOnlineBreaks === null) {
        return null;
    }
    if (Array.isArray(rawOnlineBreaks)) {
        const cleaned = [];
        for (const item of rawOnlineBreaks) {
            if (!item || typeof item !== 'object') continue;
            const sStr = String(item.startTime || item.start_time || '').trim();
            const eStr = String(item.endTime || item.end_time || '').trim();
            const sMin = parseClockSlotMinutes(sStr);
            const eMin = parseClockSlotMinutes(eStr);
            if (sMin !== null && eMin !== null && eMin > sMin) {
                cleaned.push({
                    startTime: minutesToClockSlot(sMin),
                    endTime: minutesToClockSlot(eMin),
                    startMin: sMin,
                    endMin: eMin,
                    label: String(item.label || item.name || 'Online Break').trim(),
                });
            }
        }
        cleaned.sort((a, b) => a.startMin - b.startMin);
        return cleaned;
    }

    const explicitOnlineHasBreak = raw.onlineHasBreak !== undefined
        ? Boolean(raw.onlineHasBreak)
        : (raw.online_has_break !== undefined ? Boolean(raw.online_has_break) : undefined);

    if (explicitOnlineHasBreak === false) {
        return [];
    }

    const onlineStart = String(raw.onlineBreakStartTime || raw.online_break_start_time || '').trim();
    const onlineEnd = String(raw.onlineBreakEndTime || raw.online_break_end_time || '').trim();
    if (onlineStart && onlineEnd) {
        const sMin = parseClockSlotMinutes(onlineStart);
        const eMin = parseClockSlotMinutes(onlineEnd);
        if (sMin !== null && eMin !== null && eMin > sMin) {
            return [{
                startTime: minutesToClockSlot(sMin),
                endTime: minutesToClockSlot(eMin),
                startMin: sMin,
                endMin: eMin,
                label: 'Online Break',
            }];
        }
    }

    if (Array.isArray(fallback.onlineBreaks)) {
        return fallback.onlineBreaks.map(b => {
            const sMin = b.startMin ?? parseClockSlotMinutes(b.startTime) ?? 660;
            const eMin = b.endMin ?? parseClockSlotMinutes(b.endTime) ?? 690;
            return {
                startTime: minutesToClockSlot(sMin),
                endTime: minutesToClockSlot(eMin),
                startMin: sMin,
                endMin: eMin,
                label: b.label || 'Online Break',
            };
        }).filter(b => b.endMin > b.startMin);
    }

    return null;
}

function sanitizeBlockedTimeRanges(rawRanges, fallbackRanges = {}) {
    const src = (rawRanges && typeof rawRanges === 'object' && !Array.isArray(rawRanges))
        ? rawRanges
        : ((fallbackRanges && typeof fallbackRanges === 'object') ? fallbackRanges : {});
    const out = {};
    for (const [dateKey, list] of Object.entries(src)) {
        if (dateKey === '_scheduleMeta') continue;
        const cleanDate = normalizeDateToTimezoneYmd(dateKey);
        if (!cleanDate || !Array.isArray(list)) continue;
        const cleanList = [];
        for (const item of list) {
            if (!item || typeof item !== 'object') continue;
            const sMin = item.startMin !== undefined
                ? Number(item.startMin)
                : parseClockSlotMinutes(item.startTime || item.start_time || item.slot);
            const eMin = item.endMin !== undefined
                ? Number(item.endMin)
                : parseClockSlotMinutes(item.endTime || item.end_time);
            if (sMin !== null && Number.isFinite(sMin) && eMin !== null && Number.isFinite(eMin) && eMin > sMin) {
                cleanList.push({
                    startTime: minutesToClockSlot(sMin),
                    endTime: minutesToClockSlot(eMin),
                    startMin: sMin,
                    endMin: eMin,
                    reason: String(item.reason || 'Blocked').trim(),
                    blockedByRole: item.blockedByRole || undefined,
                    updatedAt: item.updatedAt || undefined,
                });
            }
        }
        if (cleanList.length > 0) {
            cleanList.sort((a, b) => a.startMin - b.startMin);
            out[cleanDate] = cleanList;
        }
    }
    return out;
}

/**
 * Normalizes any camelCase or snake_case schedule object into the canonical Smart Schedule shape.
 */
function sanitizeSmartSchedule(rawInput = {}, fallback = DEFAULT_SMART_SCHEDULE) {
    const rawRangesObj = (rawInput && typeof rawInput === 'object')
        ? (rawInput.blockedTimeRanges ?? rawInput.blocked_time_ranges)
        : null;
    const embeddedMeta = (rawRangesObj && typeof rawRangesObj === 'object' && rawRangesObj._scheduleMeta && typeof rawRangesObj._scheduleMeta === 'object')
        ? rawRangesObj._scheduleMeta
        : {};
    const raw = { ...embeddedMeta, ...(rawInput || {}) };

    const fb = { ...DEFAULT_SMART_SCHEDULE, ...(fallback || {}) };
    const workingDays = normalizeWorkingDaysList(
        raw.inPersonWorkingDays ?? raw.in_person_working_days ?? raw.workingDays ?? raw.working_days
    );
    const effectiveWorkingDays = workingDays.length > 0 ? workingDays : [...fb.workingDays];

    const startTime = String(
        raw.inPersonStartTime || raw.in_person_start_time || raw.startTime || raw.start_time || fb.startTime || '09:00 AM'
    ).trim();
    const endTime = String(
        raw.inPersonEndTime || raw.in_person_end_time || raw.endTime || raw.end_time || fb.endTime || '05:00 PM'
    ).trim();

    const breaksSource = (raw.inPersonBreaks !== undefined || raw.in_person_breaks !== undefined)
        ? { ...raw, breaks: raw.inPersonBreaks ?? raw.in_person_breaks }
        : raw;
    const breaks = sanitizeBreaksList(breaksSource, fb);
    const primaryBreak = breaks[0] || null;

    const legacyDurRaw = raw.slotDurationMinutes ?? raw.slot_duration_minutes ?? raw.defaultDurationMinutes ?? raw.default_duration_minutes;
    const defaultDurationMinutes = sanitizeAllowedDuration(legacyDurRaw, fb.defaultDurationMinutes || fb.slotDurationMinutes || 30);

    const inPersonDurationMinutes = sanitizeAllowedDuration(
        raw.inPersonDurationMinutes ?? raw.in_person_duration_minutes ?? legacyDurRaw,
        fb.inPersonDurationMinutes || defaultDurationMinutes
    );

    const onlineDurationMinutes = sanitizeAllowedDuration(
        raw.onlineDurationMinutes ?? raw.online_duration_minutes,
        fb.onlineDurationMinutes || 20
    );

    const inPersonEnabled = raw.inPersonEnabled !== undefined
        ? Boolean(raw.inPersonEnabled)
        : (raw.in_person_enabled !== undefined ? Boolean(raw.in_person_enabled) : Boolean(fb.inPersonEnabled ?? true));

    const onlineEnabled = raw.onlineEnabled !== undefined
        ? Boolean(raw.onlineEnabled)
        : (raw.online_enabled !== undefined ? Boolean(raw.online_enabled) : Boolean(fb.onlineEnabled ?? true));

    const rawOnlineDays = raw.onlineWorkingDays !== undefined ? raw.onlineWorkingDays : raw.online_working_days;
    let onlineWorkingDays = fb.onlineWorkingDays || null;
    if (rawOnlineDays === null || (Array.isArray(rawOnlineDays) && rawOnlineDays.length === 0)) {
        onlineWorkingDays = null;
    } else if (rawOnlineDays !== undefined) {
        const parsedOnlineDays = normalizeWorkingDaysList(rawOnlineDays);
        onlineWorkingDays = parsedOnlineDays.length > 0 ? parsedOnlineDays : null;
    }

    const rawOnlineStart = raw.onlineStartTime !== undefined ? raw.onlineStartTime : raw.online_start_time;
    const rawOnlineEnd = raw.onlineEndTime !== undefined ? raw.onlineEndTime : raw.online_end_time;
    let onlineStartTime = rawOnlineStart === null || rawOnlineStart === ''
        ? null
        : (rawOnlineStart !== undefined ? String(rawOnlineStart).trim() : (fb.onlineStartTime || null));
    let onlineEndTime = rawOnlineEnd === null || rawOnlineEnd === ''
        ? null
        : (rawOnlineEnd !== undefined ? String(rawOnlineEnd).trim() : (fb.onlineEndTime || null));

    const onlineBreaks = sanitizeOnlineBreaksList(raw, fb);
    const primaryOnlineBreak = Array.isArray(onlineBreaks) && onlineBreaks.length > 0 ? onlineBreaks[0] : null;

    let useSeparateOnlineHours = false;
    if (raw.useSeparateOnlineHours !== undefined || raw.use_separate_online_hours !== undefined) {
        useSeparateOnlineHours = Boolean(raw.useSeparateOnlineHours ?? raw.use_separate_online_hours);
    } else if (rawOnlineStart === null || rawOnlineEnd === null) {
        useSeparateOnlineHours = false;
    } else if (
        raw.onlineBreaks !== undefined ||
        raw.online_breaks !== undefined ||
        raw.onlineHasBreak !== undefined ||
        raw.online_has_break !== undefined
    ) {
        useSeparateOnlineHours = Boolean(onlineStartTime && onlineEndTime);
    } else if (onlineStartTime && onlineEndTime) {
        if (onlineStartTime !== startTime) {
            useSeparateOnlineHours = true;
        } else {
            useSeparateOnlineHours = Boolean(fb.useSeparateOnlineHours);
        }
    } else {
        useSeparateOnlineHours = Boolean(fb.useSeparateOnlineHours && onlineStartTime && onlineEndTime);
    }

    if (useSeparateOnlineHours) {
        onlineStartTime = onlineStartTime || startTime;
        onlineEndTime = onlineEndTime || endTime;
    } else if (
        (raw.useSeparateOnlineHours === false || raw.use_separate_online_hours === false) &&
        rawOnlineStart === undefined &&
        rawOnlineEnd === undefined
    ) {
        onlineStartTime = null;
        onlineEndTime = null;
    }

    const bufferMinutes = sanitizeBufferMinutes(raw.bufferMinutes ?? raw.buffer_minutes, fb.bufferMinutes ?? 5);
    const onlineBufferMinutes = sanitizeBufferMinutes(raw.onlineBufferMinutes ?? raw.online_buffer_minutes, fb.onlineBufferMinutes ?? 5);
    const inPersonBufferMinutes = sanitizeBufferMinutes(raw.inPersonBufferMinutes ?? raw.in_person_buffer_minutes, fb.inPersonBufferMinutes ?? 10);

    const rawMaxPerDay = raw.maxAppointmentsPerDay !== undefined ? raw.maxAppointmentsPerDay : raw.max_appointments_per_day;
    let maxAppointmentsPerDay = fb.maxAppointmentsPerDay ?? null;
    if (rawMaxPerDay === null || rawMaxPerDay === '' || rawMaxPerDay === 0 || rawMaxPerDay === '0') {
        maxAppointmentsPerDay = null;
    } else if (rawMaxPerDay !== undefined) {
        const parsedMax = parseInt(String(rawMaxPerDay), 10);
        maxAppointmentsPerDay = Number.isFinite(parsedMax) && parsedMax > 0 ? parsedMax : null;
    }

    const allowSimultaneousOnlineAndInPerson = raw.allowSimultaneousOnlineAndInPerson !== undefined
        ? Boolean(raw.allowSimultaneousOnlineAndInPerson)
        : (raw.allow_simultaneous_online_and_in_person !== undefined
            ? Boolean(raw.allow_simultaneous_online_and_in_person)
            : Boolean(fb.allowSimultaneousOnlineAndInPerson ?? false));

    const blockedTimeRanges = sanitizeBlockedTimeRanges(
        raw.blockedTimeRanges ?? raw.blocked_time_ranges,
        fb.blockedTimeRanges
    );

    const isConfigured = raw.isConfigured !== undefined
        ? Boolean(raw.isConfigured)
        : (raw.is_configured !== undefined ? Boolean(raw.is_configured) : Boolean(fb.isConfigured));

    return {
        workingDays: effectiveWorkingDays,
        startTime,
        endTime,
        breaks,
        hasBreak: breaks.length > 0,
        breakStartTime: primaryBreak ? primaryBreak.startTime : null,
        breakEndTime: primaryBreak ? primaryBreak.endTime : null,
        slotDurationMinutes: inPersonDurationMinutes,
        slotIntervalMinutes: inPersonDurationMinutes,
        defaultDurationMinutes,
        inPersonEnabled,
        inPersonDurationMinutes,
        onlineEnabled,
        onlineDurationMinutes,
        useSeparateOnlineHours,
        onlineWorkingDays,
        onlineStartTime,
        onlineEndTime,
        onlineBreaks,
        onlineHasBreak: Array.isArray(onlineBreaks) ? onlineBreaks.length > 0 : false,
        onlineBreakStartTime: primaryOnlineBreak ? primaryOnlineBreak.startTime : null,
        onlineBreakEndTime: primaryOnlineBreak ? primaryOnlineBreak.endTime : null,
        bufferMinutes,
        onlineBufferMinutes,
        inPersonBufferMinutes,
        maxAppointmentsPerDay,
        allowSimultaneousOnlineAndInPerson,
        blockedTimeRanges,
        timezone: 'Asia/Kolkata',
        isConfigured,
        updatedAt: raw.updatedAt || raw.updated_at || new Date().toISOString(),
    };
}

/**
 * Resolves effective schedule window & timing parameters for a consultation type ('Online' | 'In-Person').
 */
function getModeScheduleWindow(scheduleInput, consultationType = 'In-Person', rulesOverride = null) {
    const schedule = sanitizeSmartSchedule(scheduleInput || {});
    const rules = { ...getBookingRulesConfig(), ...(rulesOverride || {}) };
    const mode = normalizeConsultationType(consultationType);
    const isOnline = mode === 'Online';
    const useSeparate = Boolean(schedule.useSeparateOnlineHours);

    const enabled = isOnline ? Boolean(schedule.onlineEnabled) : Boolean(schedule.inPersonEnabled);
    const workingDays = (isOnline && Array.isArray(schedule.onlineWorkingDays) && schedule.onlineWorkingDays.length > 0)
        ? schedule.onlineWorkingDays
        : schedule.workingDays;

    const hasOnlineHours = Boolean(schedule.onlineStartTime && schedule.onlineEndTime);
    const startTime = (isOnline && (useSeparate || hasOnlineHours) && schedule.onlineStartTime)
        ? schedule.onlineStartTime
        : schedule.startTime;
    const endTime = (isOnline && (useSeparate || hasOnlineHours) && schedule.onlineEndTime)
        ? schedule.onlineEndTime
        : schedule.endTime;
    const startMin = parseClockSlotMinutes(startTime);
    const endMin = parseClockSlotMinutes(endTime);

    const durationMinutes = isOnline
        ? sanitizeAllowedDuration(schedule.onlineDurationMinutes, rules.onlineDurationMinutes || 20)
        : sanitizeAllowedDuration(schedule.inPersonDurationMinutes || schedule.slotDurationMinutes, rules.inPersonDurationMinutes || 30);

    const bufferMinutes = isOnline
        ? sanitizeBufferMinutes(schedule.onlineBufferMinutes, rules.onlineBufferMinutes ?? 5)
        : sanitizeBufferMinutes(schedule.inPersonBufferMinutes, rules.inPersonBufferMinutes ?? 10);

    const breaks = isOnline
        ? (useSeparate
            ? (Array.isArray(schedule.onlineBreaks) ? schedule.onlineBreaks : [])
            : (Array.isArray(schedule.onlineBreaks) ? schedule.onlineBreaks : (schedule.breaks || [])))
        : (schedule.breaks || []);

    const stepMinutes = useSeparate
        ? (durationMinutes + bufferMinutes)
        : durationMinutes;

    const capacityLane = schedule.allowSimultaneousOnlineAndInPerson ? mode.toUpperCase() : 'SHARED';

    return {
        consultationType: mode,
        useSeparateOnlineHours: useSeparate,
        enabled,
        workingDays,
        startTime,
        endTime,
        startMin,
        endMin,
        durationMinutes,
        bufferMinutes,
        stepMinutes,
        totalOccupiedMinutes: durationMinutes + bufferMinutes,
        breaks,
        maxAppointmentsPerDay: schedule.maxAppointmentsPerDay,
        allowSimultaneousOnlineAndInPerson: Boolean(schedule.allowSimultaneousOnlineAndInPerson),
        capacityLane,
        timezone: schedule.timezone || rules.timezone || 'Asia/Kolkata',
    };
}

/**
 * Generates non-overlapping base time slots honoring start/end hours, optional buffer step, and multiple breaks.
 */
function generateBaseSlotsWithBreaks({
    startTime = '09:00 AM',
    endTime = '05:00 PM',
    durationMinutes = 30,
    bufferMinutes = 0,
    stepMinutes = null,
    breaks = [],
}) {
    const startMin = parseClockSlotMinutes(startTime);
    const endMin = parseClockSlotMinutes(endTime);
    const dur = Math.max(5, parseInt(String(durationMinutes), 10) || 30);
    const buf = Math.max(0, parseInt(String(bufferMinutes), 10) || 0);
    const step = (stepMinutes !== null && stepMinutes !== undefined && Number(stepMinutes) > 0)
        ? Number(stepMinutes)
        : (buf > 0 ? dur + buf : dur);
    if (startMin === null || endMin === null || startMin >= endMin) return [];

    const normalizedBreaks = (Array.isArray(breaks) ? breaks : [])
        .map(b => {
            const s = b.startMin !== undefined ? Number(b.startMin) : parseClockSlotMinutes(b.startTime || b.start_time);
            const e = b.endMin !== undefined ? Number(b.endMin) : parseClockSlotMinutes(b.endTime || b.end_time);
            return s !== null && e !== null && e > s ? { startMin: s, endMin: e } : null;
        })
        .filter(Boolean)
        .sort((a, b) => a.startMin - b.startMin);

    const slots = [];
    let current = startMin;
    while (current + dur <= endMin) {
        const slotEnd = current + dur;
        const overlappingBreak = normalizedBreaks.find(b => intervalsOverlap(current, slotEnd, b.startMin, b.endMin));
        if (overlappingBreak) {
            // Advance cleanly to the end of the break so post-break slots align neatly!
            current = Math.max(current + 5, overlappingBreak.endMin);
            continue;
        }
        slots.push(minutesToClockSlot(current));
        current += step;
    }
    return slots;
}

function getWeekdayNameFromYmd(ymd) {
    const clean = normalizeDateToTimezoneYmd(ymd);
    if (!clean) return '';
    const [y, m, d] = clean.split('-').map(n => parseInt(n, 10));
    const dt = new Date(Date.UTC(y, m - 1, d, 12, 0, 0));
    return ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'][dt.getUTCDay()] || '';
}

function normalizeBlockedRangesForDate(schedule, dateYmd, externalBlockedSlots = [], fallbackDuration = 30) {
    const cleanDate = normalizeDateToTimezoneYmd(dateYmd);
    const fromSchedule = (schedule?.blockedTimeRanges && Array.isArray(schedule.blockedTimeRanges[cleanDate]))
        ? schedule.blockedTimeRanges[cleanDate]
        : [];
    const combined = [...fromSchedule, ...(Array.isArray(externalBlockedSlots) ? externalBlockedSlots : [])];
    const parsed = [];
    const seen = new Set();

    for (const item of combined) {
        if (!item) continue;
        if (typeof item === 'string') {
            const s = parseClockSlotMinutes(item);
            if (s !== null) {
                const e = s + fallbackDuration;
                const key = `${s}-${e}`;
                if (!seen.has(key)) {
                    seen.add(key);
                    parsed.push({ startMin: s, endMin: e, startTime: minutesToClockSlot(s), endTime: minutesToClockSlot(e), reason: 'Blocked' });
                }
            }
            continue;
        }
        const s = item.startMin !== undefined ? Number(item.startMin) : parseClockSlotMinutes(item.startTime || item.start_time || item.slot);
        const e = item.endMin !== undefined
            ? Number(item.endMin)
            : (item.endTime || item.end_time
                ? parseClockSlotMinutes(item.endTime || item.end_time)
                : (s !== null ? s + (Number(item.durationMinutes) || fallbackDuration) : null));
        if (s !== null && e !== null && e > s) {
            const key = `${s}-${e}`;
            if (!seen.has(key)) {
                seen.add(key);
                parsed.push({
                    startMin: s,
                    endMin: e,
                    startTime: minutesToClockSlot(s),
                    endTime: minutesToClockSlot(e),
                    reason: String(item.reason || 'Blocked').trim(),
                });
            }
        }
    }
    return parsed.sort((a, b) => a.startMin - b.startMin);
}

function getEffectiveOccupiedIntervals(activeAppointments = [], schedule = DEFAULT_SMART_SCHEDULE, consultationType = 'In-Person', options = {}) {
    const modeWin = getModeScheduleWindow(schedule, consultationType, options.rulesOverride);
    const excludeId = options.excludeAppointmentId ? String(options.excludeAppointmentId) : null;
    const now = options.now || null;

    const rulesWithSchedule = {
        ...getBookingRulesConfig(),
        ...(options.rulesOverride || {}),
        inPersonDurationMinutes: schedule.inPersonDurationMinutes ?? 30,
        onlineDurationMinutes: schedule.onlineDurationMinutes ?? 20,
        inPersonBufferMinutes: schedule.inPersonBufferMinutes ?? 10,
        onlineBufferMinutes: schedule.onlineBufferMinutes ?? 5,
    };

    return (activeAppointments || [])
        .filter(a => {
            if (!a) return false;
            if (excludeId && String(a.id) === excludeId) return false;
            const st = String(a.status || 'PENDING').trim().toUpperCase();
            if (INACTIVE_APPOINTMENT_STATUSES.has(st)) return false;
            return true;
        })
        .map(a => getAppointmentOccupiedInterval(a, rulesWithSchedule, now))
        .filter(Boolean)
        .filter(occ => {
            if (modeWin.useSeparateOnlineHours) {
                return occ.consultationType.toUpperCase() === modeWin.consultationType.toUpperCase();
            }
            if (modeWin.capacityLane === 'SHARED') return true;
            return occ.consultationType.toUpperCase() === modeWin.capacityLane;
        });
}

function getEffectiveActiveLocks(activeLocks = [], schedule = DEFAULT_SMART_SCHEDULE, consultationType = 'In-Person', options = {}) {
    const modeWin = getModeScheduleWindow(schedule, consultationType, options.rulesOverride);
    const nowMs = (options.now ? new Date(options.now) : new Date()).getTime();
    const excludePatientId = options.excludePatientId ? String(options.excludePatientId) : null;

    return (activeLocks || [])
        .filter(lock => {
            if (!lock) return false;
            if (String(lock.status || '').toUpperCase() !== 'ACTIVE') return false;
            const expMs = lock.expires_at || lock.expiresAt ? new Date(lock.expires_at || lock.expiresAt).getTime() : 0;
            if (!expMs || expMs <= nowMs) return false;
            if (excludePatientId && String(lock.patient_id || lock.patientId || '') === excludePatientId) return false;
            if (modeWin.capacityLane !== 'SHARED') {
                const lMode = normalizeConsultationType(lock.consultation_type || lock.consultationType);
                if (lMode.toUpperCase() !== modeWin.capacityLane) return false;
            }
            return true;
        })
        .map(lock => ({
            id: lock.id,
            patientId: String(lock.patient_id || lock.patientId || ''),
            startMin: Number(lock.start_min ?? lock.startMin ?? parseClockSlotMinutes(lock.start_time || lock.startTime)),
            endMin: Number(lock.end_min ?? lock.endMin ?? parseClockSlotMinutes(lock.end_time || lock.endTime)),
            startTime: lock.start_time || lock.startTime,
            releasedSlotId: lock.released_slot_id || lock.releasedSlotId || null,
            expiresAt: lock.expires_at || lock.expiresAt,
        }))
        .filter(l => Number.isFinite(l.startMin) && Number.isFinite(l.endMin) && l.endMin > l.startMin);
}

/**
 * Generates dynamic availability slots (both regular schedule slots and eligible AVAILABLE released slots).
 */
function generateDynamicSlots({
    schedule: rawSchedule,
    dateYmd,
    consultationType = 'In-Person',
    activeAppointments = [],
    activeLocks = [],
    releasedSlots = [],
    blockedSlots = [],
    explicitDateRecord = null,
    excludeAppointmentId = null,
    callerPatientId = null,
    rulesOverride = null,
    now = null,
}) {
    const cleanDate = normalizeDateToTimezoneYmd(dateYmd);
    const schedule = sanitizeSmartSchedule(rawSchedule || {});
    const rules = { ...getBookingRulesConfig(), ...(rulesOverride || {}) };
    const modeWin = getModeScheduleWindow(schedule, consultationType, rules);
    const weekdayName = getWeekdayNameFromYmd(cleanDate);

    const isBlockedDate = Boolean(explicitDateRecord && explicitDateRecord.is_blocked);
    const blockedReason = isBlockedDate ? (explicitDateRecord.blocked_reason || 'Doctor on Leave / Clinic Closed') : null;

    const hasExplicitDateSlots = Boolean(
        explicitDateRecord && !isBlockedDate && Array.isArray(explicitDateRecord.slots) && explicitDateRecord.slots.length > 0
    );

    const isWorkingDay = modeWin.enabled && (
        !schedule.isConfigured ||
        modeWin.workingDays.includes(weekdayName) ||
        (hasExplicitDateSlots && modeWin.consultationType === 'In-Person')
    );

    const activeApptsForDate = (activeAppointments || []).filter(a => {
        if (!a) return false;
        if (excludeAppointmentId && String(a.id) === String(excludeAppointmentId)) return false;
        const st = String(a.status || 'PENDING').trim().toUpperCase();
        if (INACTIVE_APPOINTMENT_STATUSES.has(st)) return false;
        const aDate = normalizeDateToTimezoneYmd(a.appointment_date || a.date);
        return aDate === cleanDate;
    });

    const dailyLimitReached = Boolean(
        schedule.maxAppointmentsPerDay !== null &&
        activeApptsForDate.length >= schedule.maxAppointmentsPerDay
    );

    const useExplicitSlotsForMode = hasExplicitDateSlots &&
        !modeWin.useSeparateOnlineHours && (
        modeWin.consultationType !== 'Online' ||
        Number(explicitDateRecord?.slot_duration_minutes || 0) === Number(modeWin.durationMinutes)
    ) && !(schedule.breaks && schedule.breaks.length > 1);

    const workingStartTime = modeWin.useSeparateOnlineHours
        ? modeWin.startTime
        : ((modeWin.consultationType === 'Online' && schedule.onlineStartTime)
            ? schedule.onlineStartTime
            : (explicitDateRecord?.start_time || modeWin.startTime));
    const workingEndTime = modeWin.useSeparateOnlineHours
        ? modeWin.endTime
        : ((modeWin.consultationType === 'Online' && schedule.onlineEndTime)
            ? schedule.onlineEndTime
            : (explicitDateRecord?.end_time || modeWin.endTime));

    let allBaseSlots = [];
    if (!isBlockedDate && isWorkingDay) {
        if (useExplicitSlotsForMode) {
            allBaseSlots = [...explicitDateRecord.slots];
        } else {
            allBaseSlots = generateBaseSlotsWithBreaks({
                startTime: workingStartTime,
                endTime: workingEndTime,
                durationMinutes: modeWin.durationMinutes,
                bufferMinutes: modeWin.bufferMinutes,
                stepMinutes: modeWin.stepMinutes,
                breaks: modeWin.breaks,
            });
        }
    }

    const occupiedIntervals = getEffectiveOccupiedIntervals(activeApptsForDate, schedule, modeWin.consultationType, {
        rulesOverride: rules,
        now,
        excludeAppointmentId,
    });

    const parsedBlocked = normalizeBlockedRangesForDate(schedule, cleanDate, blockedSlots, modeWin.durationMinutes);
    const otherActiveLocks = getEffectiveActiveLocks(activeLocks, schedule, modeWin.consultationType, {
        rulesOverride: rules,
        now,
        excludePatientId: callerPatientId,
    });

    const workingStartMin = parseClockSlotMinutes(workingStartTime);
    const workingEndMin = parseClockSlotMinutes(workingEndTime);
    const nowMs = (now ? new Date(now) : (rules.debugNowOverride ? new Date(rules.debugNowOverride) : new Date())).getTime();
    const effectiveNowDate = new Date(nowMs);

    const isIntervalFree = (candStart, candDur, candBuf, skipWorkingEnd = false) => {
        const candConsultEnd = candStart + candDur;
        const candOccupiedEnd = candStart + candDur + candBuf;
        if (workingStartMin !== null && candStart < workingStartMin) return false;
        if (!skipWorkingEnd && workingEndMin !== null && candConsultEnd > workingEndMin) return false;
        if (modeWin.breaks.some(b => intervalsOverlap(candStart, candConsultEnd, b.startMin, b.endMin))) return false;
        if (parsedBlocked.some(b => intervalsOverlap(candStart, candConsultEnd, b.startMin, b.endMin))) return false;
        if (occupiedIntervals.some(occ => intervalsOverlap(candStart, candOccupiedEnd, occ.startMin, occ.occupiedEndMin))) return false;
        if (otherActiveLocks.some(l => intervalsOverlap(candStart, candOccupiedEnd, l.startMin, l.endMin))) return false;
        return true;
    };

    const availableRegularItems = [];
    const lockedSlots = [];
    if (!isBlockedDate && isWorkingDay && !dailyLimitReached) {
        for (const slot of allBaseSlots) {
            const check = checkSlotBookableForDateYmd(cleanDate, slot, { ...rules, now: effectiveNowDate });
            if (!check.bookable) continue;
            const candStart = parseClockSlotMinutes(slot);
            if (candStart === null) continue;
            const candOccupiedEnd = candStart + modeWin.durationMinutes + modeWin.bufferMinutes;

            if (otherActiveLocks.some(l => intervalsOverlap(candStart, candOccupiedEnd, l.startMin, l.endMin))) {
                lockedSlots.push(slot);
                continue;
            }
            if (!isIntervalFree(candStart, modeWin.durationMinutes, modeWin.bufferMinutes, useExplicitSlotsForMode)) {
                continue;
            }
            availableRegularItems.push({
                startTime: slot,
                endTime: minutesToClockSlot(candStart + modeWin.durationMinutes),
                startMin: candStart,
                endMin: candStart + modeWin.durationMinutes,
                occupiedEndMin: candOccupiedEnd,
                durationMinutes: modeWin.durationMinutes,
                bufferMinutes: modeWin.bufferMinutes,
                consultationType: modeWin.consultationType,
                isReleasedSlot: false,
                releasedSlotId: null,
                expiresAt: null,
            });
        }
    }

    // Merge eligible AVAILABLE unexpired released slots (e.g., from early consultation completions)
    const eligibleReleasedItems = [];
    if (!isBlockedDate && isWorkingDay && !dailyLimitReached && Array.isArray(releasedSlots)) {
        for (const rel of releasedSlots) {
            if (!rel) continue;
            const relStatus = String(rel.status || '').toUpperCase();
            if (relStatus !== 'AVAILABLE') continue;
            const relDate = normalizeDateToTimezoneYmd(rel.appointment_date || rel.appointmentDate);
            if (relDate !== cleanDate) continue;
            const relMode = normalizeConsultationType(rel.consultation_type || rel.consultationType);
            if (relMode !== modeWin.consultationType) continue;
            const expMs = rel.expires_at || rel.expiresAt ? new Date(rel.expires_at || rel.expiresAt).getTime() : 0;
            if (!expMs || expMs <= nowMs) continue;

            const rStart = Number(rel.start_min ?? rel.startMin ?? parseClockSlotMinutes(rel.start_time || rel.startTime));
            const rDur = Number(rel.duration_minutes ?? rel.durationMinutes ?? modeWin.durationMinutes);
            const rBuf = Number(rel.buffer_minutes ?? rel.bufferMinutes ?? modeWin.bufferMinutes);
            if (!Number.isFinite(rStart) || !Number.isFinite(rDur) || rDur <= 0) continue;

            const rStartTime = rel.start_time || rel.startTime || minutesToClockSlot(rStart);
            // Released slots are near-term openings; only ensure the slot itself has not already passed
            const nowParts = getNowPartsInTimezone(effectiveNowDate, modeWin.timezone);
            if (cleanDate === nowParts.ymd && rStart <= nowParts.totalMinutes) continue;

            if (!isIntervalFree(rStart, rDur, rBuf, false)) continue;

            // Avoid duplicating an identical start_min already present in regular slots (prefer marking it as releasedSlot!)
            const existingIdx = availableRegularItems.findIndex(item => item.startMin === rStart);
            const relItem = {
                startTime: rStartTime,
                endTime: rel.end_time || rel.endTime || minutesToClockSlot(rStart + rDur),
                startMin: rStart,
                endMin: rStart + rDur,
                occupiedEndMin: rStart + rDur + rBuf,
                durationMinutes: rDur,
                bufferMinutes: rBuf,
                consultationType: relMode,
                isReleasedSlot: true,
                releasedSlotId: rel.id,
                expiresAt: rel.expires_at || rel.expiresAt,
            };
            if (existingIdx !== -1) {
                availableRegularItems[existingIdx] = relItem;
            } else {
                eligibleReleasedItems.push(relItem);
            }
        }
    }

    const slotItems = [...availableRegularItems, ...eligibleReleasedItems].sort((a, b) => a.startMin - b.startMin);
    const availableSlots = slotItems.map(s => s.startTime);

    // Ensure allSlots includes released slots so UIs rendering allSlots with booked/released state display them
    const allSlotsMerged = [...allBaseSlots];
    for (const relItem of eligibleReleasedItems) {
        if (!allSlotsMerged.some(s => s.trim().toLowerCase() === relItem.startTime.trim().toLowerCase())) {
            allSlotsMerged.push(relItem.startTime);
        }
    }
    allSlotsMerged.sort((a, b) => (parseClockSlotMinutes(a) ?? 9999) - (parseClockSlotMinutes(b) ?? 9999));

    const bookedSlots = activeApptsForDate
        .map(a => String(a.time_slot || a.timeSlot || '').trim())
        .filter(Boolean);

    const activeDelayMinutes = occupiedIntervals.reduce(
        (maxDelay, item) => Math.max(maxDelay, Number(item.delayMinutes || 0)),
        0
    );

    return {
        date: cleanDate,
        dayOfWeek: explicitDateRecord?.day_of_week || weekdayName,
        consultationType: modeWin.consultationType,
        modeEnabled: modeWin.enabled,
        isWorkingDay,
        isBlocked: isBlockedDate,
        blockedReason,
        startTime: workingStartTime,
        endTime: workingEndTime,
        slotDurationMinutes: modeWin.durationMinutes,
        slotIntervalMinutes: modeWin.durationMinutes,
        consultationDurationMinutes: modeWin.durationMinutes,
        bufferMinutes: modeWin.bufferMinutes,
        breaks: modeWin.breaks,
        hasBreak: modeWin.breaks.length > 0,
        breakStartTime: modeWin.breaks[0]?.startTime || null,
        breakEndTime: modeWin.breaks[0]?.endTime || null,
        workingDays: modeWin.workingDays,
        maxAppointmentsPerDay: schedule.maxAppointmentsPerDay,
        dailyLimitReached,
        allowSimultaneousOnlineAndInPerson: schedule.allowSimultaneousOnlineAndInPerson,
        activeDelayMinutes,
        allSlots: allSlotsMerged,
        bookedSlots,
        lockedSlots,
        blockedSlots: parsedBlocked,
        occupiedIntervals,
        availableSlots,
        slotItems,
        releasedSlots: slotItems.filter(s => s.isReleasedSlot),
        existingAppointmentsCount: activeApptsForDate.length,
    };
}

/**
 * Computes whether an early consultation completion creates a genuinely bookable released slot.
 * Rules:
 * - Only runs when completed strictly earlier than scheduledEndMin on the same Asia/Kolkata date.
 * - Releases a slot ONLY if full (durationMinutes + bufferMinutes) fits before the next appointment,
 *   next break, next blocked time range, or working-hour end.
 * - Never moves or alters existing confirmed appointments.
 * - Never creates duplicate released slots for the same doctor/date/type/startMin.
 */
function computeEarlyCompletionReleasedSlot({
    completedAppointment,
    actualEndAt,
    schedule: rawSchedule,
    activeAppointments = [],
    blockedSlots = [],
    existingReleasedSlots = [],
    rulesOverride = null,
}) {
    if (!completedAppointment || !actualEndAt) return null;
    const schedule = sanitizeSmartSchedule(rawSchedule || {});
    const rules = {
        ...getBookingRulesConfig(),
        ...(rulesOverride || {}),
        inPersonDurationMinutes: schedule.inPersonDurationMinutes ?? 30,
        onlineDurationMinutes: schedule.onlineDurationMinutes ?? 20,
        inPersonBufferMinutes: schedule.inPersonBufferMinutes ?? 10,
        onlineBufferMinutes: schedule.onlineBufferMinutes ?? 5,
    };

    const dateYmd = normalizeDateToTimezoneYmd(
        completedAppointment.appointment_date || completedAppointment.date,
        rules.timezone
    );
    if (!dateYmd) return null;

    const actualDateObj = new Date(actualEndAt);
    if (Number.isNaN(actualDateObj.getTime())) return null;
    const actualParts = getNowPartsInTimezone(actualDateObj, rules.timezone);
    if (actualParts.ymd !== dateYmd) return null;

    const completedInterval = getAppointmentOccupiedInterval(
        { ...completedAppointment, status: 'CONFIRMED' }, // use original scheduled end for comparison
        rules
    );
    if (!completedInterval) return null;

    const actualEndMin = actualParts.totalMinutes;
    // Must genuinely finish early (strictly before scheduled end, and not before start)
    if (actualEndMin < completedInterval.startMin || actualEndMin >= completedInterval.scheduledEndMin) {
        return null;
    }

    // Respect daily appointment limit: don't release new slot if doctor already hit daily cap
    const activeForDate = (activeAppointments || []).filter(a => {
        if (!a) return false;
        const st = String(a.status || 'PENDING').trim().toUpperCase();
        if (INACTIVE_APPOINTMENT_STATUSES.has(st)) return false;
        return normalizeDateToTimezoneYmd(a.appointment_date || a.date, rules.timezone) === dateYmd;
    });
    if (schedule.maxAppointmentsPerDay !== null && activeForDate.length >= schedule.maxAppointmentsPerDay) {
        return null;
    }

    // Earliest moment the doctor is free after finishing + post-consultation cleanup buffer (aligned to 5-min boundary)
    const rawFreeStartMin = actualEndMin + completedInterval.bufferMinutes;
    const freedStartMin = Math.ceil(rawFreeStartMin / 5) * 5;

    // Candidate mode order: completed appointment's own mode first, then the other enabled mode
    const primaryMode = completedInterval.consultationType;
    const secondaryMode = primaryMode === 'Online' ? 'In-Person' : 'Online';
    const candidateModes = [primaryMode, secondaryMode];

    const weekdayName = getWeekdayNameFromYmd(dateYmd);

    for (const candidateMode of candidateModes) {
        const modeWin = getModeScheduleWindow(schedule, candidateMode, rules);
        if (!modeWin.enabled) continue;
        if (schedule.isConfigured && !modeWin.workingDays.includes(weekdayName)) continue;
        if (modeWin.startMin === null || modeWin.endMin === null) continue;
        if (freedStartMin < modeWin.startMin) continue;

        const neededConsultEnd = freedStartMin + modeWin.durationMinutes;
        const neededOccupiedEnd = freedStartMin + modeWin.durationMinutes + modeWin.bufferMinutes;

        // Hard ceiling: working end time
        let ceilingMin = modeWin.endMin;

        // Check breaks
        const hitsBreak = modeWin.breaks.some(b => intervalsOverlap(freedStartMin, neededConsultEnd, b.startMin, b.endMin));
        if (hitsBreak) continue;
        for (const b of modeWin.breaks) {
            if (b.startMin >= freedStartMin && b.startMin < ceilingMin) {
                ceilingMin = b.startMin;
            }
        }

        // Check blocked time ranges
        const blockedForDate = normalizeBlockedRangesForDate(schedule, dateYmd, blockedSlots, modeWin.durationMinutes);
        const hitsBlocked = blockedForDate.some(b => intervalsOverlap(freedStartMin, neededConsultEnd, b.startMin, b.endMin));
        if (hitsBlocked) continue;
        for (const b of blockedForDate) {
            if (b.startMin >= freedStartMin && b.startMin < ceilingMin) {
                ceilingMin = b.startMin;
            }
        }

        // Check existing appointments (never move or overlap any existing confirmed/pending appointment!)
        const otherOccupied = getEffectiveOccupiedIntervals(activeForDate, schedule, candidateMode, {
            rulesOverride: rules,
            excludeAppointmentId: completedAppointment.id,
        });
        const hitsAppt = otherOccupied.some(occ => intervalsOverlap(freedStartMin, neededOccupiedEnd, occ.startMin, occ.occupiedEndMin));
        if (hitsAppt) continue;

        for (const occ of otherOccupied) {
            if (occ.startMin >= freedStartMin && occ.startMin < ceilingMin) {
                ceilingMin = occ.startMin;
            }
        }

        // Strict fit requirement: BOTH full duration AND required buffer must fit before ceiling!
        // (At working-hour end, consultation must end by workingEndMin; before next appt, duration + buffer must fit before next appt start)
        const nextBoundaryRequiresBuffer = ceilingMin < modeWin.endMin;
        const requiredEnd = nextBoundaryRequiresBuffer ? neededOccupiedEnd : neededConsultEnd;
        if (requiredEnd > ceilingMin) {
            continue;
        }

        // Duplicate prevention: do not create duplicate released slot for same doctor/date/mode/startMin or overlapping window
        const hasDuplicate = (existingReleasedSlots || []).some(rel => {
            if (!rel) return false;
            const st = String(rel.status || '').toUpperCase();
            if (st === 'EXPIRED') return false;
            const rDate = normalizeDateToTimezoneYmd(rel.appointment_date || rel.appointmentDate, rules.timezone);
            if (rDate !== dateYmd) return false;
            const rStart = Number(rel.start_min ?? rel.startMin ?? parseClockSlotMinutes(rel.start_time || rel.startTime));
            const rEnd = Number(rel.end_min ?? rel.endMin ?? (rStart + Number(rel.duration_minutes || modeWin.durationMinutes)));
            return intervalsOverlap(freedStartMin, neededConsultEnd, rStart, rEnd);
        });
        if (hasDuplicate) {
            return null;
        }

        // Compute slot expiry in Asia/Kolkata: expires at the released slot's own start time
        const slotStartHour = Math.floor(freedStartMin / 60);
        const slotStartMinPart = freedStartMin % 60;
        const istIso = `${dateYmd}T${String(slotStartHour).padStart(2, '0')}:${String(slotStartMinPart).padStart(2, '0')}:00+05:30`;
        const slotStartUtc = new Date(istIso);
        // Ensure at least 5 minutes expiry buffer if testing with synthetic clock, otherwise expires at slot start
        const expiresAt = slotStartUtc.getTime() > actualDateObj.getTime()
            ? slotStartUtc.toISOString()
            : new Date(actualDateObj.getTime() + 15 * 60 * 1000).toISOString();

        return {
            dentist_id: completedAppointment.dentist_id || completedAppointment.dentistId,
            source_appointment_id: completedAppointment.id || null,
            appointment_date: dateYmd,
            start_time: minutesToClockSlot(freedStartMin),
            end_time: minutesToClockSlot(neededConsultEnd),
            start_min: freedStartMin,
            end_min: neededConsultEnd,
            duration_minutes: modeWin.durationMinutes,
            buffer_minutes: modeWin.bufferMinutes,
            consultation_type: candidateMode,
            status: 'AVAILABLE',
            expires_at: expiresAt,
        };
    }

    return null;
}

/**
 * Validates a booking or rescheduling request against the doctor's full smart schedule.
 */
function validateSlotAgainstSchedule({
    schedule: rawSchedule,
    dateYmd,
    timeSlot,
    consultationType = 'In-Person',
    activeAppointments = [],
    blockedSlots = [],
    explicitDateRecord = null,
    releasedSlot = null,
    excludeAppointmentId = null,
    rulesOverride = null,
}) {
    const cleanDate = normalizeDateToTimezoneYmd(dateYmd);
    const schedule = sanitizeSmartSchedule(rawSchedule || {});
    const rules = { ...getBookingRulesConfig(), ...(rulesOverride || {}) };
    const modeWin = getModeScheduleWindow(schedule, consultationType, rules);
    const weekdayName = getWeekdayNameFromYmd(cleanDate);

    if (explicitDateRecord && explicitDateRecord.is_blocked) {
        return {
            valid: false,
            status: 409,
            reason: 'DATE_BLOCKED',
            isBlocked: true,
            message: `The doctor is unavailable on this date (${explicitDateRecord.blocked_reason || 'Blocked / On Leave'}). Please choose another date.`,
        };
    }

    if (!modeWin.enabled) {
        return {
            valid: false,
            status: 409,
            reason: 'CONSULTATION_TYPE_DISABLED',
            message: `This doctor is not accepting ${modeWin.consultationType} consultations.`,
        };
    }

    const hasCustomDateSlots = Boolean(
        !modeWin.useSeparateOnlineHours &&
        explicitDateRecord &&
        !explicitDateRecord.is_blocked &&
        Array.isArray(explicitDateRecord.slots) &&
        explicitDateRecord.slots.length > 0
    );

    if (schedule.isConfigured && !hasCustomDateSlots && modeWin.workingDays.length > 0 && weekdayName && !modeWin.workingDays.includes(weekdayName)) {
        return {
            valid: false,
            status: 409,
            reason: 'NON_WORKING_DAY',
            message: `The doctor does not consult on ${weekdayName}s for ${modeWin.consultationType} visits. Please select a configured working day.`,
        };
    }

    const activeForDate = (activeAppointments || []).filter(a => {
        if (!a) return false;
        if (excludeAppointmentId && String(a.id) === String(excludeAppointmentId)) return false;
        const st = String(a.status || 'PENDING').trim().toUpperCase();
        if (INACTIVE_APPOINTMENT_STATUSES.has(st)) return false;
        return normalizeDateToTimezoneYmd(a.appointment_date || a.date, rules.timezone) === cleanDate;
    });

    if (schedule.maxAppointmentsPerDay !== null && activeForDate.length >= schedule.maxAppointmentsPerDay) {
        return {
            valid: false,
            status: 409,
            reason: 'DAILY_LIMIT_REACHED',
            message: `The doctor has reached the maximum daily limit (${schedule.maxAppointmentsPerDay}) for ${cleanDate}. Please select another date.`,
        };
    }

    const candStartMin = parseClockSlotMinutes(timeSlot);
    if (candStartMin === null) {
        return {
            valid: false,
            status: 400,
            reason: 'INVALID_TIME_SLOT',
            message: `Invalid time slot format (${timeSlot}). Expected hh:mm AM/PM.`,
        };
    }

    const effectiveDur = releasedSlot ? Number(releasedSlot.duration_minutes || modeWin.durationMinutes) : modeWin.durationMinutes;
    const effectiveBuf = releasedSlot ? Number(releasedSlot.buffer_minutes ?? modeWin.bufferMinutes) : modeWin.bufferMinutes;
    const candConsultEndMin = candStartMin + effectiveDur;
    const candOccupiedEndMin = candStartMin + effectiveDur + effectiveBuf;

    // Working hours boundary check
    const workingStartTime = modeWin.useSeparateOnlineHours
        ? modeWin.startTime
        : ((modeWin.consultationType === 'Online' && schedule.onlineStartTime)
            ? schedule.onlineStartTime
            : (explicitDateRecord?.start_time || modeWin.startTime));
    const workingEndTime = modeWin.useSeparateOnlineHours
        ? modeWin.endTime
        : ((modeWin.consultationType === 'Online' && schedule.onlineEndTime)
            ? schedule.onlineEndTime
            : (explicitDateRecord?.end_time || modeWin.endTime));
    const workStartMin = parseClockSlotMinutes(workingStartTime);
    const workEndMin = parseClockSlotMinutes(workingEndTime);

    if ((schedule.isConfigured || modeWin.useSeparateOnlineHours) && !hasCustomDateSlots && workStartMin !== null && workEndMin !== null) {
        if (candStartMin < workStartMin || candConsultEndMin > workEndMin) {
            return {
                valid: false,
                status: 400,
                reason: 'OUTSIDE_WORKING_HOURS',
                message: `The ${modeWin.consultationType} consultation at ${timeSlot} (${effectiveDur} min) falls outside doctor working hours (${workingStartTime} - ${workingEndTime}).`,
            };
        }
    }

    // Multiple breaks check
    const hitBreak = modeWin.breaks.find(b => intervalsOverlap(candStartMin, candConsultEndMin, b.startMin, b.endMin));
    if (hitBreak) {
        return {
            valid: false,
            status: 400,
            reason: 'OVERLAPS_BREAK',
            message: `The time slot (${timeSlot}) overlaps with the doctor's break period (${hitBreak.startTime} - ${hitBreak.endTime}).`,
        };
    }

    // When separate Online and In-Person schedules are enabled, enforce that regular bookings match a generated slot for that mode
    if (modeWin.useSeparateOnlineHours && !releasedSlot && !hasCustomDateSlots && workStartMin !== null && workEndMin !== null) {
        const modeSlots = generateBaseSlotsWithBreaks({
            startTime: workingStartTime,
            endTime: workingEndTime,
            durationMinutes: modeWin.durationMinutes,
            bufferMinutes: modeWin.bufferMinutes,
            stepMinutes: modeWin.stepMinutes,
            breaks: modeWin.breaks,
        });
        const canonicalCandidate = minutesToClockSlot(candStartMin);
        if (!modeSlots.includes(canonicalCandidate)) {
            return {
                valid: false,
                status: 400,
                reason: 'INVALID_MODE_SLOT',
                message: `The time slot (${timeSlot}) is not a valid ${modeWin.consultationType} slot for the configured schedule (${workingStartTime} - ${workingEndTime}).`,
            };
        }
    }

    // Blocked time ranges check
    const blockedRanges = normalizeBlockedRangesForDate(schedule, cleanDate, blockedSlots, effectiveDur);
    const hitBlock = blockedRanges.find(b => intervalsOverlap(candStartMin, candConsultEndMin, b.startMin, b.endMin));
    if (hitBlock) {
        return {
            valid: false,
            status: 409,
            reason: 'SLOT_BLOCKED',
            isBlocked: true,
            message: `The time slot (${timeSlot}) has been manually blocked (${hitBlock.reason || 'Unavailable'}). Please select another slot.`,
        };
    }

    // Active appointment conflict check (respecting shared vs separate Online/In-Person capacity lane!)
    const occupied = getEffectiveOccupiedIntervals(activeForDate, schedule, modeWin.consultationType, {
        rulesOverride: rules,
        excludeAppointmentId,
    });
    const conflictOcc = occupied.find(occ => intervalsOverlap(candStartMin, candOccupiedEndMin, occ.startMin, occ.occupiedEndMin));
    if (conflictOcc) {
        return {
            valid: false,
            status: 409,
            reason: 'APPOINTMENT_CONFLICT',
            conflict: true,
            message: `The time slot (${timeSlot}) overlaps with an existing ${conflictOcc.consultationType} appointment (${conflictOcc.timeSlot} - ${conflictOcc.scheduledEndTime}, reserved with ${conflictOcc.bufferMinutes}m buffer until ${conflictOcc.bufferEndTime}). Please select another slot.`,
        };
    }

    return {
        valid: true,
        timing: {
            consultationType: modeWin.consultationType,
            durationMinutes: effectiveDur,
            bufferMinutes: effectiveBuf,
            startMin: candStartMin,
            consultEndMin: candConsultEndMin,
            occupiedEndMin: candOccupiedEndMin,
            capacityLane: modeWin.capacityLane,
        },
    };
}

module.exports = {
    ALLOWED_DURATIONS,
    FULL_WEEKDAYS,
    DEFAULT_SMART_SCHEDULE,
    sanitizeAllowedDuration,
    sanitizeBufferMinutes,
    normalizeWorkingDaysList,
    sanitizeBreaksList,
    sanitizeBlockedTimeRanges,
    sanitizeSmartSchedule,
    getModeScheduleWindow,
    generateBaseSlotsWithBreaks,
    getWeekdayNameFromYmd,
    normalizeBlockedRangesForDate,
    getEffectiveOccupiedIntervals,
    getEffectiveActiveLocks,
    generateDynamicSlots,
    computeEarlyCompletionReleasedSlot,
    validateSlotAgainstSchedule,
};
