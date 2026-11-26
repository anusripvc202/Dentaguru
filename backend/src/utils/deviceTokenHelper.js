/**
 * Centralized, non-destructive helper for users.device_token.
 *
 * Historically `public.users.device_token` has been shared between:
 *  - Raw FCM registration tokens (plain string)
 *  - Patient profile metadata (city, pincode, age, gender, bloodGroup, etc.)
 *  - Sub-Admin permissions & status metadata
 *  - Doctor weekly schedules (`schedule`), `blockedSlotsByDate`, and `onlineStatus`
 *
 * This helper guarantees that writing an FCM token NEVER overwrites doctor schedules or
 * patient metadata, and writing schedules/metadata NEVER overwrites an existing FCM token.
 */

const MAX_STORED_FCM_TOKENS = 5;

function _isLikelyRawFcmToken(value) {
    if (typeof value !== 'string') return false;
    const trimmed = value.trim();
    if (!trimmed || trimmed.startsWith('{') || trimmed.startsWith('[')) return false;
    return trimmed.length >= 10;
}

/**
 * Safely parses `users.device_token` into a mutable metadata object.
 * Legacy raw FCM token strings are upgraded losslessly to `{ fcmToken, fcmTokens }`.
 */
function parseDeviceTokenPayload(rawDeviceToken) {
    if (!rawDeviceToken) return {};
    if (typeof rawDeviceToken === 'object' && !Array.isArray(rawDeviceToken)) {
        return { ...rawDeviceToken };
    }
    if (typeof rawDeviceToken !== 'string') return {};
    const trimmed = rawDeviceToken.trim();
    if (!trimmed) return {};
    if (trimmed.startsWith('{')) {
        try {
            const parsed = JSON.parse(trimmed);
            if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
                return { ...parsed };
            }
        } catch (_) {
            return {};
        }
        return {};
    }
    if (_isLikelyRawFcmToken(trimmed)) {
        return {
            fcmToken: trimmed,
            fcmTokens: [trimmed],
        };
    }
    return {};
}

/**
 * Extracts all unique valid FCM registration tokens from a user object or raw `device_token` value.
 */
function extractFcmTokens(userOrRaw) {
    if (!userOrRaw) return [];
    const tokens = [];
    const addToken = (candidate) => {
        if (_isLikelyRawFcmToken(candidate)) {
            const clean = candidate.trim();
            if (!tokens.includes(clean)) tokens.push(clean);
        }
    };

    if (typeof userOrRaw === 'string') {
        const meta = parseDeviceTokenPayload(userOrRaw);
        addToken(meta.fcmToken);
        if (Array.isArray(meta.fcmTokens)) {
            for (const t of meta.fcmTokens) addToken(t);
        }
        return tokens;
    }

    if (typeof userOrRaw === 'object') {
        addToken(userOrRaw.fcm_token);
        addToken(userOrRaw.fcmToken);
        if (Array.isArray(userOrRaw.fcmTokens)) {
            for (const t of userOrRaw.fcmTokens) addToken(t);
        }
        const meta = parseDeviceTokenPayload(userOrRaw.device_token);
        addToken(meta.fcmToken);
        if (Array.isArray(meta.fcmTokens)) {
            for (const t of meta.fcmTokens) addToken(t);
        }
    }
    return tokens;
}

/**
 * Extracts the primary (most recent) valid FCM token from a user object or raw `device_token`.
 */
function extractFcmToken(userOrRaw) {
    const tokens = extractFcmTokens(userOrRaw);
    return tokens.length > 0 ? tokens[0] : null;
}

/**
 * Non-destructively merges a patch (FCM token and/or schedule/profile metadata) into an
 * existing `users.device_token` value and returns the serialized JSON string.
 */
function mergeDeviceTokenPayload(existingRaw, patch = {}) {
    const base = parseDeviceTokenPayload(existingRaw);
    let patchObj = {};

    if (typeof patch === 'string') {
        patchObj = parseDeviceTokenPayload(patch);
    } else if (patch && typeof patch === 'object' && !Array.isArray(patch)) {
        patchObj = { ...patch };
    }

    // Collect existing tokens first, then prepend newly supplied token(s) so newest is primary
    const existingTokens = extractFcmTokens(base);
    const incomingTokens = [];
    if (_isLikelyRawFcmToken(patchObj.fcmToken)) {
        incomingTokens.push(patchObj.fcmToken.trim());
    }
    if (_isLikelyRawFcmToken(patchObj.fcm_token)) {
        incomingTokens.push(patchObj.fcm_token.trim());
    }
    if (Array.isArray(patchObj.fcmTokens)) {
        for (const t of patchObj.fcmTokens) {
            if (_isLikelyRawFcmToken(t)) incomingTokens.push(t.trim());
        }
    }

    const merged = { ...base };
    const tokensToRemove = new Set();
    if (typeof patchObj.removeFcmToken === 'string' && patchObj.removeFcmToken.trim()) {
        tokensToRemove.add(patchObj.removeFcmToken.trim());
    }
    if (Array.isArray(patchObj.removeFcmTokens)) {
        for (const t of patchObj.removeFcmTokens) {
            if (typeof t === 'string' && t.trim()) tokensToRemove.add(t.trim());
        }
    }

    for (const [key, val] of Object.entries(patchObj)) {
        if (
            key === 'fcmToken' ||
            key === 'fcm_token' ||
            key === 'fcmTokens' ||
            key === 'removeFcmToken' ||
            key === 'removeFcmTokens'
        ) continue;
        if (val === undefined) continue;
        if (key === 'schedule' && val && typeof val === 'object') {
            merged.schedule = { ...(base.schedule || {}), ...val };
        } else if (key === 'blockedSlotsByDate' && val && typeof val === 'object') {
            merged.blockedSlotsByDate = { ...val };
        } else {
            merged[key] = val;
        }
    }

    const dedupedTokens = [];
    for (const t of [...incomingTokens, ...existingTokens]) {
        if (tokensToRemove.has(t)) continue;
        if (!dedupedTokens.includes(t)) dedupedTokens.push(t);
        if (dedupedTokens.length >= MAX_STORED_FCM_TOKENS) break;
    }

    if (dedupedTokens.length > 0) {
        merged.fcmToken = dedupedTokens[0];
        merged.fcmTokens = dedupedTokens;
        if (incomingTokens.length > 0) {
            merged.fcmTokenUpdatedAt = new Date().toISOString();
        }
    } else if (tokensToRemove.size > 0) {
        delete merged.fcmToken;
        delete merged.fcmTokens;
    }

    return JSON.stringify(merged);
}

module.exports = {
    parseDeviceTokenPayload,
    extractFcmToken,
    extractFcmTokens,
    mergeDeviceTokenPayload,
};
