/**
 * Doctor Clinic Details & OpenStreetMap Coordinates Validation Helper
 * Shared across authController, clinicController, and Schemas.js.
 */

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
 * Validates latitude/longitude pair.
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

function isValidIndianPincode(raw) {
    if (raw === undefined || raw === null) return false;
    return /^\d{6}$/.test(String(raw).trim());
}

/**
 * Validates all required doctor clinic registration fields.
 */
function validateDoctorRegistrationClinicFields({
    clinicName,
    clinicAddress,
    city,
    state,
    pincode,
    latitude,
    longitude
}) {
    const cleanClinicName = (clinicName || '').toString().trim();
    const cleanClinicAddress = (clinicAddress || '').toString().trim();
    const cleanCity = (city || '').toString().trim();
    const cleanState = (state || '').toString().trim();
    const cleanPincode = (pincode !== undefined && pincode !== null) ? String(pincode).trim() : '';

    if (!cleanClinicName) {
        return { ok: false, message: 'Clinic name is required for doctor registration.' };
    }
    if (!cleanClinicAddress) {
        return { ok: false, message: 'Clinic address is required for doctor registration.' };
    }
    if (!cleanCity) {
        return { ok: false, message: 'City is required for doctor registration.' };
    }
    if (!cleanState) {
        return { ok: false, message: 'State is required for doctor registration.' };
    }
    if (!cleanPincode || !isValidIndianPincode(cleanPincode)) {
        return { ok: false, message: 'Please enter a valid 6-digit pincode.' };
    }

    const coordCheck = validateCoordinates(latitude, longitude, false);
    if (!coordCheck.ok) {
        return coordCheck;
    }
    if (!coordCheck.hasUpdate || coordCheck.latitude === null || coordCheck.longitude === null) {
        return { ok: false, message: 'Please select your clinic location on the map.' };
    }

    return {
        ok: true,
        clinicName: cleanClinicName,
        clinicAddress: cleanClinicAddress,
        city: cleanCity,
        state: cleanState,
        pincode: cleanPincode,
        latitude: coordCheck.latitude,
        longitude: coordCheck.longitude
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
    parseCoordinateValue,
    validateCoordinates,
    isValidIndianPincode,
    validateDoctorRegistrationClinicFields,
    parseUserDeviceMeta
};
