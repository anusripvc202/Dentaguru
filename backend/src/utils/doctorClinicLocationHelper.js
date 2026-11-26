/**
 * Doctor Clinic Details, Consultation Mode & OpenStreetMap Coordinates Helper
 * Shared across authController, clinicController, and Schemas.js.
 */

const VALID_CONSULTATION_MODES = ['BOTH', 'IN_PERSON', 'ONLINE_ONLY'];

function normalizeConsultationMode(raw, fallback = 'BOTH') {
    if (raw === undefined || raw === null) return fallback;
    const norm = String(raw).trim().toUpperCase().replace(/[\s-]+/g, '_');
    if (norm === 'ONLINE' || norm === 'ONLINE_ONLY' || norm === 'TELEMEDICINE') {
        return 'ONLINE_ONLY';
    }
    if (norm === 'IN_PERSON' || norm === 'CLINIC' || norm === 'CLINIC_ONLY') {
        return 'IN_PERSON';
    }
    if (norm === 'BOTH' || norm === 'HYBRID' || norm === 'ALL') {
        return 'BOTH';
    }
    return fallback;
}

function parseCoordinateValue(raw, min, max) {
    if (raw === undefined) return undefined;
    if (raw === null || String(raw).trim() === '') return null;
    const num = Number(raw);
    if (!Number.isFinite(num) || num < min || num > max) {
        return NaN;
    }
    return num;
}

/**
 * Validates optional latitude/longitude pair.
 * - Both omitted -> { ok: true, hasUpdate: false, latitude: undefined, longitude: undefined }
 * - clearLocation === true or both explicitly null/empty -> { ok: true, hasUpdate: true, latitude: null, longitude: null }
 * - One provided without the other or out of range -> { ok: false, message }
 */
function validateCoordinates(rawLat, rawLng, clearLocation = false) {
    if (clearLocation === true) {
        return { ok: true, hasUpdate: true, latitude: null, longitude: null };
    }
    const lat = parseCoordinateValue(rawLat, -90, 90);
    const lng = parseCoordinateValue(rawLng, -180, 180);

    if (lat === undefined && lng === undefined) {
        return { ok: true, hasUpdate: false, latitude: undefined, longitude: undefined };
    }
    if (lat === null && lng === null) {
        return { ok: true, hasUpdate: true, latitude: null, longitude: null };
    }
    if (Number.isNaN(lat) || Number.isNaN(lng)) {
        return {
            ok: false,
            message: 'Invalid map coordinates. Latitude must be between -90 and 90, and longitude between -180 and 180.'
        };
    }
    if (lat === null || lat === undefined || lng === null || lng === undefined) {
        return {
            ok: false,
            message: 'Both latitude and longitude must be provided together when setting a map location.'
        };
    }
    return {
        ok: true,
        hasUpdate: true,
        latitude: Number(lat.toFixed(6)),
        longitude: Number(lng.toFixed(6))
    };
}

function parseUserDeviceMeta(rawDeviceToken) {
    if (!rawDeviceToken || typeof rawDeviceToken !== 'string') return {};
    const trimmed = rawDeviceToken.trim();
    if (!trimmed.startsWith('{')) return {};
    try {
        const parsed = JSON.parse(trimmed);
        return parsed && typeof parsed === 'object' ? parsed : {};
    } catch (_) {
        return {};
    }
}

module.exports = {
    VALID_CONSULTATION_MODES,
    normalizeConsultationMode,
    parseCoordinateValue,
    validateCoordinates,
    parseUserDeviceMeta
};
