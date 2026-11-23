const crypto = require('crypto');

const WEAK_DEFAULT_SECRETS = new Set([
    'supersecretjwtkey123',
    'supersecretrefreshkey456',
    'gs_health_otp_salt_2026',
    'dentaguru_super_secret_jwt_key_2026',
    'dentaguru_super_secret_refresh_key_2026',
    'fallback_secret',
    'changeme',
    'secret'
]);

// Ephemeral per-process fallback used ONLY in non-cloud local dev/test when env var is omitted.
const ephemeralDevSecrets = new Map();

function getNodeEnv(env = process.env) {
    return (env.NODE_ENV || 'development').trim().toLowerCase();
}

function isCloudEnv(env = process.env) {
    const nodeEnv = getNodeEnv(env);
    return nodeEnv === 'production' || nodeEnv === 'staging';
}

function isStrictProductionEnv(env = process.env) {
    return getNodeEnv(env) === 'production';
}

function isStagingOnScreenOtpEnv(env = process.env) {
    if (getNodeEnv(env) !== 'staging') return false;
    return (env.OTP_DELIVERY_MODE || '').trim().toLowerCase() === 'on_screen';
}

function isPlaceholderOrWeakSecret(raw) {
    if (!raw) return true;
    const lower = raw.toLowerCase();
    return lower.includes('placeholder')
        || lower.startsWith('your-')
        || lower.startsWith('replace-with-')
        || WEAK_DEFAULT_SECRETS.has(raw);
}

function resolveSecret(envKey, env = process.env) {
    const raw = (env[envKey] || '').toString().trim();
    const isWeakOrPlaceholder = isPlaceholderOrWeakSecret(raw);

    if (isCloudEnv(env)) {
        if (isWeakOrPlaceholder || raw.length < 16) {
            throw new Error(
                `GS HEALTH Security Configuration Error (${getNodeEnv(env)}): Missing or weak ${envKey}. It must be set to a strong secret (>=16 chars) via environment variables.`
            );
        }
        return raw;
    }

    if (raw && !isPlaceholderOrWeakSecret(raw)) {
        return raw;
    }

    if (!ephemeralDevSecrets.has(envKey)) {
        ephemeralDevSecrets.set(envKey, crypto.randomBytes(32).toString('hex'));
    }
    return ephemeralDevSecrets.get(envKey);
}

function getJwtSecret(env = process.env) {
    return resolveSecret('JWT_SECRET', env);
}

function getRefreshSecret(env = process.env) {
    return resolveSecret('REFRESH_SECRET', env);
}

function getOtpSalt(env = process.env) {
    return resolveSecret('OTP_SALT', env);
}

/**
 * Staging-only OTP access secret key:
 * - Production: ALWAYS null (never enabled, never accepted, never required).
 * - Staging + OTP_DELIVERY_MODE=on_screen: strictly requires a strong >=16-char STAGING_OTP_ACCESS_KEY.
 * - Local development/test: returns explicitly configured non-placeholder key if present, or null when unset.
 */
function getStagingOtpAccessKey(env = process.env) {
    if (isStrictProductionEnv(env)) {
        return null;
    }
    if (isStagingOnScreenOtpEnv(env)) {
        return resolveSecret('STAGING_OTP_ACCESS_KEY', env);
    }
    const raw = (env.STAGING_OTP_ACCESS_KEY || '').toString().trim();
    if (!raw || isPlaceholderOrWeakSecret(raw) || raw.length < 16) {
        return null;
    }
    return raw;
}

function constantTimeSecretMatch(provided, expected) {
    if (!provided || !expected) return false;
    const providedDigest = crypto.createHash('sha256').update(String(provided)).digest();
    const expectedDigest = crypto.createHash('sha256').update(String(expected)).digest();
    return crypto.timingSafeEqual(providedDigest, expectedDigest);
}

function extractStagingOtpAccessHeader(req) {
    if (!req) return '';
    if (typeof req.get === 'function') {
        const direct = req.get('x-staging-otp-key');
        if (direct) return String(direct).trim();
    }
    const headers = req.headers || {};
    for (const [key, val] of Object.entries(headers)) {
        if (key.toLowerCase() === 'x-staging-otp-key' && val !== undefined && val !== null) {
            return String(Array.isArray(val) ? val[0] : val).trim();
        }
    }
    return '';
}

/**
 * Verify staging OTP access key for on-screen OTP requests.
 * - Production: returns { authorized: false, required: false } (production does not use staging on-screen OTP).
 * - Staging (on_screen): strictly requires valid x-staging-otp-key matching STAGING_OTP_ACCESS_KEY.
 * - Local dev/test: enforces key if STAGING_OTP_ACCESS_KEY is explicitly configured; otherwise permits local testing.
 */
function isAuthorizedStagingOtpRequest(req, env = process.env) {
    if (isStrictProductionEnv(env)) {
        return { authorized: false, required: false };
    }

    let expectedKey = null;
    try {
        expectedKey = getStagingOtpAccessKey(env);
    } catch (_) {
        return { authorized: false, required: true, reason: 'MISCONFIGURED' };
    }

    if (isStagingOnScreenOtpEnv(env)) {
        if (!expectedKey) {
            return { authorized: false, required: true, reason: 'MISCONFIGURED' };
        }
        const providedKey = extractStagingOtpAccessHeader(req);
        return {
            authorized: constantTimeSecretMatch(providedKey, expectedKey),
            required: true,
        };
    }

    if (expectedKey) {
        const providedKey = extractStagingOtpAccessHeader(req);
        return {
            authorized: constantTimeSecretMatch(providedKey, expectedKey),
            required: true,
        };
    }

    return { authorized: true, required: false };
}

function validateCloudSecuritySecrets(env = process.env) {
    if (!isCloudEnv(env)) return true;
    getJwtSecret(env);
    getRefreshSecret(env);
    getOtpSalt(env);
    if (isStagingOnScreenOtpEnv(env)) {
        getStagingOtpAccessKey(env);
    }
    return true;
}

module.exports = {
    getNodeEnv,
    isCloudEnv,
    isStrictProductionEnv,
    isStagingOnScreenOtpEnv,
    getJwtSecret,
    getRefreshSecret,
    getOtpSalt,
    getStagingOtpAccessKey,
    isAuthorizedStagingOtpRequest,
    validateCloudSecuritySecrets,
    WEAK_DEFAULT_SECRETS
};
