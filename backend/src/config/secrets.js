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

function resolveSecret(envKey, env = process.env) {
    const raw = (env[envKey] || '').toString().trim();
    const isWeakOrPlaceholder = !raw
        || raw.toLowerCase().includes('placeholder')
        || raw.toLowerCase().startsWith('your-')
        || WEAK_DEFAULT_SECRETS.has(raw);

    if (isCloudEnv(env)) {
        if (isWeakOrPlaceholder || raw.length < 16) {
            throw new Error(
                `GS HEALTH Security Configuration Error (${getNodeEnv(env)}): Missing or weak ${envKey}. It must be set to a strong secret (>=16 chars) via environment variables.`
            );
        }
        return raw;
    }

    if (raw && !raw.toLowerCase().includes('placeholder') && !raw.toLowerCase().startsWith('your-')) {
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

function validateCloudSecuritySecrets(env = process.env) {
    if (!isCloudEnv(env)) return true;
    getJwtSecret(env);
    getRefreshSecret(env);
    getOtpSalt(env);
    return true;
}

module.exports = {
    getNodeEnv,
    isCloudEnv,
    isStrictProductionEnv,
    getJwtSecret,
    getRefreshSecret,
    getOtpSalt,
    validateCloudSecuritySecrets,
    WEAK_DEFAULT_SECRETS
};
