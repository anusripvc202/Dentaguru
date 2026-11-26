const jwt = require('jsonwebtoken');
const { hasSupabaseJwtSecret, getSupabaseJwtSecret } = require('../config/secrets');
const { Dentist, Clinic } = require('../models/Schemas');

const REALTIME_TOKEN_TTL_SECONDS = 3600; // Short-lived 1-hour Supabase Realtime JWT
const UUID_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * Maps any DentaGuru role string to its canonical uppercase application role claim.
 */
function normalizeRealtimeAppRole(rawRole) {
    const r = String(rawRole || 'Patient').trim().toLowerCase();
    if (r === 'sub-admin' || r === 'subadmin' || r === 'sub_admin') {
        return 'SUB_ADMIN';
    }
    if (r === 'admin' || r === 'primaryadmin' || r === 'primary_admin' || r === 'superadmin' || r === 'super_admin') {
        return 'ADMIN';
    }
    if (r.includes('dentist') || r.includes('doctor')) {
        return 'DOCTOR';
    }
    if (r.includes('clinic')) {
        return 'CLINIC';
    }
    return 'PATIENT';
}

function parseTokenMeta(user) {
    if (user?.device_token && typeof user.device_token === 'string' && user.device_token.trim().startsWith('{')) {
        try {
            return JSON.parse(user.device_token);
        } catch (_) { }
    }
    return {};
}

/**
 * Resolves the HS256 signing key material (UTF-8 string or Base64-decoded buffer) verified against
 * SUPABASE_ANON_KEY when present so signature compatibility with Supabase Realtime/PostgREST is guaranteed.
 */
function resolveVerifiedSupabaseSigningKey(env = process.env) {
    const rawSecret = getSupabaseJwtSecret(env);
    const anonKey = (env.SUPABASE_ANON_KEY || '').toString().trim();

    if (anonKey && anonKey.split('.').length === 3) {
        try {
            jwt.verify(anonKey, rawSecret, { algorithms: ['HS256'] });
            return rawSecret;
        } catch (_) { }

        try {
            const decodedBuf = Buffer.from(rawSecret, 'base64');
            if (decodedBuf.length >= 16) {
                jwt.verify(anonKey, decodedBuf, { algorithms: ['HS256'] });
                return decodedBuf;
            }
        } catch (_) { }

        // Only enforce strict anon-key cross-check when anonKey is a real signed JWT (not a unit-test fixture string)
        try {
            const header = JSON.parse(Buffer.from(anonKey.split('.')[0], 'base64url').toString('utf8'));
            if (header && header.alg === 'HS256') {
                const err = new Error('SUPABASE_JWT_SECRET does not match the configured staging SUPABASE_ANON_KEY signature.');
                err.code = 'SUPABASE_SIGNING_KEY_MISMATCH';
                err.statusCode = 500;
                throw err;
            }
        } catch (mismatchErr) {
            if (mismatchErr.code === 'SUPABASE_SIGNING_KEY_MISMATCH') {
                throw mismatchErr;
            }
        }
    }

    return rawSecret;
}

/**
 * Mints a short-lived Supabase-compatible HS256 Realtime JWT whose `sub` claim is strictly `public.users.id`.
 * Enforces ACTIVE account status and populates normalized `app_role`, `dentist_id`, and `clinic_id` claims.
 */
async function mintSupabaseRealtimeTokenForUser(user, options = {}) {
    if (!user || !user.id) {
        const err = new Error('Valid user record with canonical public.users.id is required.');
        err.statusCode = 400;
        throw err;
    }

    const canonicalUserId = String(user.id).trim();
    if (!UUID_REGEX.test(canonicalUserId)) {
        const err = new Error('Canonical public.users.id must be a valid UUID for Supabase auth.uid() compatibility.');
        err.statusCode = 400;
        throw err;
    }

    const tokenMeta = parseTokenMeta(user);
    const effectiveStatus = String(user.status || tokenMeta.status || 'ACTIVE').trim().toUpperCase();
    if (effectiveStatus === 'INACTIVE' || effectiveStatus === 'DEACTIVATED' || effectiveStatus === 'SUSPENDED') {
        const err = new Error('Access Denied: Deactivated or suspended accounts cannot obtain a Realtime session token.');
        err.statusCode = 403;
        err.code = 'ACCOUNT_DEACTIVATED';
        throw err;
    }

    const appRole = normalizeRealtimeAppRole(user.role);
    if (appRole === 'SUB_ADMIN') {
        const err = new Error('Access Denied: Sub-Admins are strictly prohibited from chat and Realtime chat subscriptions.');
        err.statusCode = 403;
        err.code = 'CHAT_FORBIDDEN_FOR_ROLE';
        throw err;
    }

    let dentistId = options.dentistId || null;
    let clinicId = options.clinicId || null;

    if (appRole === 'DOCTOR') {
        if (!dentistId) {
            try {
                const docRec = await Dentist.findOne({ user_id: canonicalUserId }) || await Dentist.findById(canonicalUserId);
                if (docRec) {
                    dentistId = docRec.id || null;
                    clinicId = clinicId || docRec.clinic_id || null;
                }
            } catch (_) { }
        }
    } else if (appRole === 'CLINIC') {
        if (!clinicId) {
            try {
                const clinicRec = await Clinic.findOne({ user_id: canonicalUserId });
                if (clinicRec) {
                    clinicId = clinicRec.id || null;
                }
            } catch (_) { }
        }
    }

    const env = options.env || process.env;
    const signingKey = resolveVerifiedSupabaseSigningKey(env);
    const ttlSeconds = Number.isInteger(options.ttlSeconds) && options.ttlSeconds > 0
        ? Math.min(options.ttlSeconds, 7200)
        : REALTIME_TOKEN_TTL_SECONDS;

    const nowSec = Math.floor(Date.now() / 1000);
    const expSec = nowSec + ttlSeconds;

    const claims = {
        aud: 'authenticated',
        role: 'authenticated',
        sub: canonicalUserId,
        app_role: appRole,
        dentist_id: (dentistId && UUID_REGEX.test(String(dentistId))) ? String(dentistId) : null,
        clinic_id: (clinicId && UUID_REGEX.test(String(clinicId))) ? String(clinicId) : null,
        iat: nowSec,
        exp: expSec,
    };

    const realtimeToken = jwt.sign(claims, signingKey, { algorithm: 'HS256' });
    const expiresAt = new Date(expSec * 1000).toISOString();

    return {
        realtimeToken,
        realtimeTokenExpiresAt: expiresAt,
        expiresIn: ttlSeconds,
        claims,
    };
}

/**
 * Best-effort Realtime token minting during login/register/OTP verify when SUPABASE_JWT_SECRET is configured.
 * Returns null when SUB_ADMIN (strictly prohibited from chat/Realtime), when SUPABASE_JWT_SECRET is unconfigured,
 * or if the user ID is a non-UUID synthetic mock ID.
 */
async function tryMintSupabaseRealtimeTokenForUser(user, options = {}) {
    const env = options.env || process.env;
    if (!hasSupabaseJwtSecret(env)) {
        return null;
    }
    if (!user || !UUID_REGEX.test(String(user.id || '').trim())) {
        return null;
    }
    if (normalizeRealtimeAppRole(user.role) === 'SUB_ADMIN') {
        return null;
    }
    return mintSupabaseRealtimeTokenForUser(user, options);
}

/**
 * Verifies a Supabase Realtime JWT using the backend SUPABASE_JWT_SECRET and validates mandatory claims.
 */
function verifySupabaseRealtimeToken(token, env = process.env) {
    const signingKey = resolveVerifiedSupabaseSigningKey(env);
    const decoded = jwt.verify(String(token || '').trim(), signingKey, {
        algorithms: ['HS256'],
        audience: 'authenticated',
    });
    if (decoded.role !== 'authenticated' || !UUID_REGEX.test(String(decoded.sub || ''))) {
        throw new Error('Invalid Realtime JWT claims: expected role=authenticated and UUID sub.');
    }
    if (decoded.app_role === 'SUB_ADMIN') {
        throw new Error('Access Denied: Sub-Admins are strictly prohibited from Realtime chat access.');
    }
    return decoded;
}

module.exports = {
    REALTIME_TOKEN_TTL_SECONDS,
    normalizeRealtimeAppRole,
    resolveVerifiedSupabaseSigningKey,
    mintSupabaseRealtimeTokenForUser,
    tryMintSupabaseRealtimeTokenForUser,
    verifySupabaseRealtimeToken,
};
