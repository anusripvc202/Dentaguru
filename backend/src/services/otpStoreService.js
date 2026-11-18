const crypto = require('crypto');
const { supabaseAdmin } = require('../config/supabase');

const OTP_SALT = process.env.OTP_SALT || process.env.JWT_SECRET || 'gs_health_otp_salt_2026';
const OTP_EXPIRY_SECONDS = 5 * 60; // 5 minutes TTL (300 seconds)
const OTP_COOLDOWN_SECONDS = 30; // 30 seconds resend cooldown
const OTP_COOLDOWN_MS = OTP_COOLDOWN_SECONDS * 1000;
const OTP_RATE_LIMIT_WINDOW_SECONDS = 15 * 60; // 15 minutes window (900 seconds)
const OTP_MAX_REQUESTS_PER_WINDOW = 5; // Max 5 requests per 15 minutes
const OTP_MAX_ATTEMPTS = 5; // Max 5 incorrect attempts

// In-memory store strictly for local development / automated unit tests ONLY.
// Never permitted when NODE_ENV === 'production'.
const localOtpMap = new Map();
const localLimitMap = new Map();
const localMutexQueues = new Map();

/**
 * Normalize key (10-digit Indian/tail phone or lowercased email)
 */
function normalizeKey(identifier) {
    if (!identifier) return '';
    const str = String(identifier).trim().toLowerCase();
    if (str.includes('@')) return str;
    const digits = str.replace(/\D/g, '');
    return digits.length >= 10 ? digits.slice(-10) : digits;
}

/**
 * Salted HMAC-SHA256 hash of OTP code (raw OTPs are never stored)
 */
function hashOtp(code) {
    return crypto.createHmac('sha256', OTP_SALT).update(String(code).trim()).digest('hex');
}

/**
 * Cryptographically secure 6-digit numeric OTP (100000 - 999999)
 */
function generateRandomOtp() {
    return crypto.randomInt(100000, 1000000).toString();
}

function isMissingRpcError(error) {
    if (!error) return false;
    const code = String(error.code || '');
    const msg = String(error.message || '').toLowerCase();
    return code === 'PGRST202' || code === '42883' || msg.includes('could not find the function') || msg.includes('does not exist');
}

class OtpStoreService {
    constructor(options = {}) {
        this.supabaseClient = options.supabaseClient !== undefined ? options.supabaseClient : supabaseAdmin;
        this.isProduction = options.isProduction !== undefined
            ? options.isProduction
            : (process.env.NODE_ENV === 'production');
        this.forceMemoryInDev = options.forceMemoryInDev || false;
    }

    /**
     * Production safety check: requires configured Supabase service_role client.
     * In-memory storage is strictly prohibited in production.
     */
    _ensureProductionConfig() {
        if (this.isProduction) {
            const url = process.env.SUPABASE_URL;
            const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
            const anonKey = process.env.SUPABASE_ANON_KEY;

            const hasClient = Boolean(this.supabaseClient && typeof this.supabaseClient.rpc === 'function');
            const hasValidEnv = Boolean(
                url &&
                !url.includes('placeholder') &&
                serviceKey &&
                serviceKey !== anonKey
            );

            if (!hasClient || (!hasValidEnv && this.supabaseClient === supabaseAdmin)) {
                throw new Error(
                    'GS HEALTH Production Configuration Error: Valid SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are strictly required in production for atomic OTP storage. In-memory OTP storage is disabled in production.'
                );
            }
        }
    }

    /**
     * Async per-identifier mutex for local dev/test concurrency safety
     */
    async _withLocalLock(key, taskFn) {
        const prev = localMutexQueues.get(key) || Promise.resolve();
        let release;
        const next = new Promise(resolve => { release = resolve; });
        const chained = prev.then(() => next);
        localMutexQueues.set(key, chained);

        await prev;
        try {
            return await taskFn();
        } finally {
            release();
            if (localMutexQueues.get(key) === chained) {
                localMutexQueues.delete(key);
            }
        }
    }

    /**
     * Check 30s resend cooldown and 15-minute sliding rate limit
     */
    async checkRateLimit(identifier) {
        this._ensureProductionConfig();
        const cleanKey = normalizeKey(identifier);
        if (!cleanKey) return { allowed: true };

        if (!this.forceMemoryInDev && this.supabaseClient && typeof this.supabaseClient.rpc === 'function') {
            try {
                const { data, error } = await this.supabaseClient.rpc('check_otp_rate_limit', {
                    p_identifier: cleanKey,
                    p_cooldown_seconds: OTP_COOLDOWN_SECONDS,
                    p_window_seconds: OTP_RATE_LIMIT_WINDOW_SECONDS,
                    p_max_requests: OTP_MAX_REQUESTS_PER_WINDOW
                });

                if (error) {
                    if (!this.isProduction && isMissingRpcError(error)) {
                        // Migration 02 not applied yet in local dev/test environment; fall through to local store
                    } else {
                        throw new Error(error.message || 'Supabase OTP rate-limit RPC failed.');
                    }
                } else if (data) {
                    return data;
                }
            } catch (err) {
                if (this.isProduction) {
                    throw new Error(`Production Supabase checkRateLimit failure: ${err.message}`);
                }
            }
        }

        if (this.isProduction) {
            throw new Error('Production Error: Supabase RPC storage required for OTP rate limiting.');
        }

        // Dev/Test local fallback
        return this._withLocalLock(cleanKey, () => {
            const now = Date.now();
            const existing = localLimitMap.get(cleanKey);
            if (existing) {
                if (existing.requestCount > 0 && existing.lastRequestedAt && (now - existing.lastRequestedAt < OTP_COOLDOWN_MS)) {
                    const remainingSec = Math.max(1, Math.ceil((OTP_COOLDOWN_MS - (now - existing.lastRequestedAt)) / 1000));
                    return {
                        allowed: false,
                        status: 429,
                        reason: 'COOLDOWN',
                        remainingSeconds: remainingSec,
                        message: `Please wait ${remainingSec} seconds before requesting a new OTP.`
                    };
                }
                if (existing.windowStart && (now - existing.windowStart < OTP_RATE_LIMIT_WINDOW_SECONDS * 1000)) {
                    if (existing.requestCount >= OTP_MAX_REQUESTS_PER_WINDOW) {
                        return {
                            allowed: false,
                            status: 429,
                            reason: 'RATE_LIMIT',
                            message: 'Too many OTP requests. Please wait 15 minutes before requesting again.'
                        };
                    }
                }
            }
            return { allowed: true, status: 200 };
        });
    }

    /**
     * Atomically verify cooldown & rate limits AND store hashed OTP challenge.
     * Ensures SMS dispatch only happens after challenge creation succeeds.
     */
    async requestAndStoreOtp(identifier, code) {
        this._ensureProductionConfig();
        const cleanKey = normalizeKey(identifier);
        if (!cleanKey) {
            return { allowed: false, status: 400, message: 'Identifier is required.' };
        }

        const hashedCode = hashOtp(code);

        if (!this.forceMemoryInDev && this.supabaseClient && typeof this.supabaseClient.rpc === 'function') {
            try {
                const { data, error } = await this.supabaseClient.rpc('request_otp_challenge', {
                    p_identifier: cleanKey,
                    p_hashed_code: hashedCode,
                    p_ttl_seconds: OTP_EXPIRY_SECONDS,
                    p_cooldown_seconds: OTP_COOLDOWN_SECONDS,
                    p_window_seconds: OTP_RATE_LIMIT_WINDOW_SECONDS,
                    p_max_requests: OTP_MAX_REQUESTS_PER_WINDOW,
                    p_max_attempts: OTP_MAX_ATTEMPTS
                });

                if (error) {
                    if (!this.isProduction && isMissingRpcError(error)) {
                        // Migration 02 not applied yet in local dev/test environment; fall through to local store
                    } else {
                        throw new Error(error.message || 'Supabase request_otp_challenge RPC failed.');
                    }
                } else if (data) {
                    return data;
                }
            } catch (err) {
                if (this.isProduction) {
                    throw new Error(`Production Supabase requestAndStoreOtp failure: ${err.message}`);
                }
            }
        }

        if (this.isProduction) {
            throw new Error('Production Error: Supabase RPC storage required for OTP creation.');
        }

        // Dev/Test atomic local mutex fallback
        return this._withLocalLock(cleanKey, () => {
            const now = Date.now();
            const existingLimit = localLimitMap.get(cleanKey);

            if (existingLimit && existingLimit.requestCount > 0 && existingLimit.lastRequestedAt && (now - existingLimit.lastRequestedAt < OTP_COOLDOWN_MS)) {
                const remainingSec = Math.max(1, Math.ceil((OTP_COOLDOWN_MS - (now - existingLimit.lastRequestedAt)) / 1000));
                return {
                    allowed: false,
                    status: 429,
                    reason: 'COOLDOWN',
                    remainingSeconds: remainingSec,
                    message: `Please wait ${remainingSec} seconds before requesting a new OTP.`
                };
            }

            let requestCount = 1;
            let windowStart = now;
            if (existingLimit && existingLimit.windowStart && (now - existingLimit.windowStart < OTP_RATE_LIMIT_WINDOW_SECONDS * 1000)) {
                if (existingLimit.requestCount >= OTP_MAX_REQUESTS_PER_WINDOW) {
                    return {
                        allowed: false,
                        status: 429,
                        reason: 'RATE_LIMIT',
                        message: 'Too many OTP requests. Please wait 15 minutes before requesting again.'
                    };
                }
                requestCount = (existingLimit.requestCount || 0) + 1;
                windowStart = existingLimit.windowStart;
            }

            localLimitMap.set(cleanKey, {
                requestCount,
                windowStart,
                lastRequestedAt: now
            });

            const expiresAt = now + (OTP_EXPIRY_SECONDS * 1000);
            localOtpMap.set(cleanKey, {
                hashedCode,
                createdAt: now,
                expiresAt,
                attempts: 0,
                used: false
            });

            return {
                allowed: true,
                status: 200,
                requestCount,
                expiresAt: new Date(expiresAt).toISOString()
            };
        });
    }

    /**
     * Store OTP directly (used by legacy callers/tests; delegates to atomic RPC when available)
     */
    async storeOtp(identifier, code) {
        const res = await this.requestAndStoreOtp(identifier, code);
        if (!res.allowed) {
            return res;
        }
        return res;
    }

    /**
     * Atomically verify OTP with max attempts tracking and single-use replay protection
     */
    async verifyOtp(identifier, code) {
        this._ensureProductionConfig();
        if (!code) {
            return { valid: false, message: 'Please enter the 6-digit OTP code.' };
        }
        const cleanCode = String(code).trim();
        if (!/^\d{6}$/.test(cleanCode)) {
            return { valid: false, message: 'Please enter a valid 6-digit OTP code.' };
        }

        const cleanKey = normalizeKey(identifier);
        if (!cleanKey) {
            return { valid: false, message: 'Invalid or expired OTP. Please request a new OTP.' };
        }

        const incomingHash = hashOtp(cleanCode);

        if (!this.forceMemoryInDev && this.supabaseClient && typeof this.supabaseClient.rpc === 'function') {
            try {
                const { data, error } = await this.supabaseClient.rpc('verify_otp_challenge', {
                    p_identifier: cleanKey,
                    p_incoming_hash: incomingHash
                });

                if (error) {
                    if (!this.isProduction && isMissingRpcError(error)) {
                        // Migration 02 not applied yet in local dev/test environment; fall through to local store
                    } else {
                        throw new Error(error.message || 'Supabase verify_otp_challenge RPC failed.');
                    }
                } else if (data) {
                    return data;
                }
            } catch (err) {
                if (this.isProduction) {
                    throw new Error(`Production Supabase verifyOtp failure: ${err.message}`);
                }
            }
        }

        if (this.isProduction) {
            throw new Error('Production Error: Supabase RPC storage required for OTP verification.');
        }

        // Dev/Test atomic local mutex fallback
        return this._withLocalLock(cleanKey, () => {
            const now = Date.now();
            const entry = localOtpMap.get(cleanKey);

            if (!entry || entry.used) {
                return { valid: false, reason: 'NOT_FOUND', message: 'Invalid or expired OTP. Please request a new OTP.' };
            }

            if (now > entry.expiresAt) {
                localOtpMap.delete(cleanKey);
                return { valid: false, reason: 'EXPIRED', message: 'OTP has expired. Please request a new OTP.' };
            }

            if (entry.attempts >= OTP_MAX_ATTEMPTS) {
                localOtpMap.delete(cleanKey);
                return {
                    valid: false,
                    reason: 'MAX_ATTEMPTS',
                    message: 'Maximum incorrect attempts exceeded. This OTP has been invalidated. Please request a new OTP.'
                };
            }

            if (incomingHash !== entry.hashedCode) {
                entry.attempts += 1;
                const remaining = OTP_MAX_ATTEMPTS - entry.attempts;
                if (remaining <= 0) {
                    localOtpMap.delete(cleanKey);
                    return {
                        valid: false,
                        reason: 'MAX_ATTEMPTS',
                        remainingAttempts: 0,
                        message: 'Maximum incorrect attempts exceeded. This OTP has been invalidated. Please request a new OTP.'
                    };
                }
                return {
                    valid: false,
                    reason: 'INVALID_CODE',
                    remainingAttempts: remaining,
                    message: `Invalid OTP code. ${remaining} attempt(s) remaining.`
                };
            }

            // Valid match! Delete immediately for single-use replay protection
            entry.used = true;
            localOtpMap.delete(cleanKey);
            return { valid: true, reason: 'VERIFIED', message: 'OTP verified successfully.' };
        });
    }

    /**
     * Invalidate an OTP challenge (e.g., if SMS carrier dispatch fails)
     * and optionally roll back the rate-limit increment & cooldown.
     */
    async invalidateOtp(identifier, rollbackRateLimit = true) {
        this._ensureProductionConfig();
        const cleanKey = normalizeKey(identifier);
        if (!cleanKey) return { invalidated: false };

        if (!this.forceMemoryInDev && this.supabaseClient && typeof this.supabaseClient.rpc === 'function') {
            try {
                const { data, error } = await this.supabaseClient.rpc('invalidate_otp_challenge', {
                    p_identifier: cleanKey,
                    p_rollback_rate_limit: Boolean(rollbackRateLimit)
                });

                if (error) {
                    if (!this.isProduction && isMissingRpcError(error)) {
                        // Fall through to local store
                    } else {
                        throw new Error(error.message || 'Supabase invalidate_otp_challenge RPC failed.');
                    }
                } else if (data) {
                    return data;
                }
            } catch (err) {
                if (this.isProduction) {
                    throw new Error(`Production Supabase invalidateOtp failure: ${err.message}`);
                }
            }
        }

        if (this.isProduction) {
            throw new Error('Production Error: Supabase RPC storage required for OTP invalidation.');
        }

        return this._withLocalLock(cleanKey, () => {
            localOtpMap.delete(cleanKey);
            if (rollbackRateLimit) {
                const existingLimit = localLimitMap.get(cleanKey);
                if (existingLimit) {
                    existingLimit.requestCount = Math.max(0, (existingLimit.requestCount || 0) - 1);
                    existingLimit.lastRequestedAt = 0;
                }
            }
            return { invalidated: true };
        });
    }
}

const otpStoreService = new OtpStoreService();

module.exports = {
    otpStoreService,
    OtpStoreService,
    generateRandomOtp,
    hashOtp,
    normalizeKey,
    localOtpMap,
    localLimitMap
};
