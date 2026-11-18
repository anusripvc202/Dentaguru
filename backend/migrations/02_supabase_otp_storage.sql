-- =============================================================================
-- GS HEALTH SUPABASE POSTGRESQL MIGRATION: 02_supabase_otp_storage.sql
-- Module: Production-Safe Atomic Mobile/Email OTP Storage & Rate Limiting
-- Security: RLS enabled with ZERO permissive policies for anon/authenticated.
--           Exclusive access via backend service_role & atomic RPC functions.
-- =============================================================================

-- 1. OTP CHALLENGES TABLE (Stores salted HMAC-SHA256 hashes only; never raw OTPs)
CREATE TABLE IF NOT EXISTS public.otp_challenges (
    identifier VARCHAR(255) PRIMARY KEY,
    hashed_code VARCHAR(64) NOT NULL,
    attempts INTEGER NOT NULL DEFAULT 0 CHECK (attempts >= 0),
    max_attempts INTEGER NOT NULL DEFAULT 5 CHECK (max_attempts > 0),
    used BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_otp_challenges_expires_at
    ON public.otp_challenges(expires_at);

-- 2. OTP RATE LIMITS TABLE (Tracks 30s cooldown & 15-min sliding window limits)
CREATE TABLE IF NOT EXISTS public.otp_rate_limits (
    identifier VARCHAR(255) PRIMARY KEY,
    request_count INTEGER NOT NULL DEFAULT 0 CHECK (request_count >= 0),
    window_start TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_requested_at TIMESTAMPTZ NOT NULL DEFAULT TO_TIMESTAMP(0),
    locked_until TIMESTAMPTZ NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_otp_rate_limits_window_start
    ON public.otp_rate_limits(window_start);

-- 3. STRICT ROW LEVEL SECURITY (Zero anon or authenticated client access)
ALTER TABLE public.otp_challenges ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.otp_rate_limits ENABLE ROW LEVEL SECURITY;

-- Drop any accidental permissive policies if previously created
DROP POLICY IF EXISTS "Allow All OTP Challenges" ON public.otp_challenges;
DROP POLICY IF EXISTS "Allow All OTP Rate Limits" ON public.otp_rate_limits;

-- Revoke all direct table privileges from public, anon, and authenticated roles
REVOKE ALL ON TABLE public.otp_challenges FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE public.otp_rate_limits FROM PUBLIC, anon, authenticated;

-- Grant table privileges solely to service_role (used by Express backend supabaseAdmin)
GRANT ALL ON TABLE public.otp_challenges TO service_role;
GRANT ALL ON TABLE public.otp_rate_limits TO service_role;

-- =============================================================================
-- 4. ATOMIC PL/pgSQL RPC FUNCTIONS (Row-level locking for concurrency safety)
-- =============================================================================

-- 4A. Read-only / Pre-flight Rate Limit & Cooldown Check
CREATE OR REPLACE FUNCTION public.check_otp_rate_limit(
    p_identifier TEXT,
    p_cooldown_seconds INTEGER DEFAULT 30,
    p_window_seconds INTEGER DEFAULT 900,
    p_max_requests INTEGER DEFAULT 5
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_limit public.otp_rate_limits%ROWTYPE;
    v_now TIMESTAMPTZ := NOW();
    v_remaining_cooldown INTEGER;
BEGIN
    IF p_identifier IS NULL OR BTRIM(p_identifier) = '' THEN
        RETURN jsonb_build_object('allowed', true, 'status', 200);
    END IF;

    SELECT * INTO v_limit
    FROM public.otp_rate_limits
    WHERE identifier = p_identifier;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('allowed', true, 'status', 200);
    END IF;

    -- 1. Check 30-second resend cooldown
    IF v_limit.request_count > 0
       AND v_limit.last_requested_at > v_now - make_interval(secs => p_cooldown_seconds) THEN
        v_remaining_cooldown := GREATEST(
            1,
            CEIL(EXTRACT(EPOCH FROM (v_limit.last_requested_at + make_interval(secs => p_cooldown_seconds) - v_now)))::INTEGER
        );
        RETURN jsonb_build_object(
            'allowed', false,
            'status', 429,
            'reason', 'COOLDOWN',
            'remainingSeconds', v_remaining_cooldown,
            'message', 'Please wait ' || v_remaining_cooldown || ' seconds before requesting a new OTP.'
        );
    END IF;

    -- 2. Check 15-minute window limit
    IF v_limit.window_start > v_now - make_interval(secs => p_window_seconds)
       AND v_limit.request_count >= p_max_requests THEN
        RETURN jsonb_build_object(
            'allowed', false,
            'status', 429,
            'reason', 'RATE_LIMIT',
            'message', 'Too many OTP requests. Please wait 15 minutes before requesting again.'
        );
    END IF;

    RETURN jsonb_build_object('allowed', true, 'status', 200);
END;
$$;

-- 4B. Atomic Rate-Limit Check + Challenge Creation (Single Transaction with FOR UPDATE)
CREATE OR REPLACE FUNCTION public.request_otp_challenge(
    p_identifier TEXT,
    p_hashed_code TEXT,
    p_ttl_seconds INTEGER DEFAULT 300,
    p_cooldown_seconds INTEGER DEFAULT 30,
    p_window_seconds INTEGER DEFAULT 900,
    p_max_requests INTEGER DEFAULT 5,
    p_max_attempts INTEGER DEFAULT 5
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_limit public.otp_rate_limits%ROWTYPE;
    v_now TIMESTAMPTZ := NOW();
    v_new_count INTEGER;
    v_new_window TIMESTAMPTZ;
    v_expires_at TIMESTAMPTZ;
    v_remaining_cooldown INTEGER;
BEGIN
    IF p_identifier IS NULL OR BTRIM(p_identifier) = '' THEN
        RETURN jsonb_build_object('allowed', false, 'status', 400, 'message', 'Identifier is required.');
    END IF;

    -- Bounded opportunistic cleanup of stale expired challenges older than 1 hour
    DELETE FROM public.otp_challenges
    WHERE identifier IN (
        SELECT identifier
        FROM public.otp_challenges
        WHERE expires_at < v_now - INTERVAL '1 hour'
        ORDER BY expires_at ASC
        LIMIT 50
        FOR UPDATE SKIP LOCKED
    );

    -- Ensure rate limit row exists and acquire row-level lock
    INSERT INTO public.otp_rate_limits (
        identifier, request_count, window_start, last_requested_at, updated_at
    ) VALUES (
        p_identifier, 0, v_now, TO_TIMESTAMP(0), v_now
    )
    ON CONFLICT (identifier) DO NOTHING;

    SELECT * INTO v_limit
    FROM public.otp_rate_limits
    WHERE identifier = p_identifier
    FOR UPDATE;

    -- 1. Enforce 30-second resend cooldown atomically
    IF v_limit.request_count > 0
       AND v_limit.last_requested_at > v_now - make_interval(secs => p_cooldown_seconds) THEN
        v_remaining_cooldown := GREATEST(
            1,
            CEIL(EXTRACT(EPOCH FROM (v_limit.last_requested_at + make_interval(secs => p_cooldown_seconds) - v_now)))::INTEGER
        );
        RETURN jsonb_build_object(
            'allowed', false,
            'status', 429,
            'reason', 'COOLDOWN',
            'remainingSeconds', v_remaining_cooldown,
            'message', 'Please wait ' || v_remaining_cooldown || ' seconds before requesting a new OTP.'
        );
    END IF;

    -- 2. Enforce max 5 requests per 15-minute window atomically
    IF v_limit.request_count = 0 OR v_limit.window_start <= v_now - make_interval(secs => p_window_seconds) THEN
        v_new_count := 1;
        v_new_window := v_now;
    ELSIF v_limit.request_count >= p_max_requests THEN
        RETURN jsonb_build_object(
            'allowed', false,
            'status', 429,
            'reason', 'RATE_LIMIT',
            'message', 'Too many OTP requests. Please wait 15 minutes before requesting again.'
        );
    ELSE
        v_new_count := v_limit.request_count + 1;
        v_new_window := v_limit.window_start;
    END IF;

    -- 3. Update rate limit tracker
    UPDATE public.otp_rate_limits
    SET request_count = v_new_count,
        window_start = v_new_window,
        last_requested_at = v_now,
        updated_at = v_now
    WHERE identifier = p_identifier;

    -- 4. Store/replace hashed OTP challenge with 5-minute expiration
    v_expires_at := v_now + make_interval(secs => p_ttl_seconds);

    INSERT INTO public.otp_challenges (
        identifier, hashed_code, attempts, max_attempts, used, created_at, expires_at
    ) VALUES (
        p_identifier, p_hashed_code, 0, p_max_attempts, false, v_now, v_expires_at
    )
    ON CONFLICT (identifier) DO UPDATE
    SET hashed_code = EXCLUDED.hashed_code,
        attempts = 0,
        max_attempts = EXCLUDED.max_attempts,
        used = false,
        created_at = v_now,
        expires_at = EXCLUDED.expires_at;

    RETURN jsonb_build_object(
        'allowed', true,
        'status', 200,
        'requestCount', v_new_count,
        'expiresAt', v_expires_at
    );
END;
$$;

-- 4C. Atomic OTP Verification with Attempt Lockout & Single-Use Replay Protection
CREATE OR REPLACE FUNCTION public.verify_otp_challenge(
    p_identifier TEXT,
    p_incoming_hash TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_challenge public.otp_challenges%ROWTYPE;
    v_now TIMESTAMPTZ := NOW();
    v_new_attempts INTEGER;
    v_remaining INTEGER;
BEGIN
    IF p_identifier IS NULL OR BTRIM(p_identifier) = '' THEN
        RETURN jsonb_build_object(
            'valid', false,
            'reason', 'MISSING_IDENTIFIER',
            'message', 'Invalid or expired OTP. Please request a new OTP.'
        );
    END IF;

    -- Lock the challenge row to serialize concurrent verification attempts
    SELECT * INTO v_challenge
    FROM public.otp_challenges
    WHERE identifier = p_identifier
    FOR UPDATE;

    IF NOT FOUND OR v_challenge.used = true THEN
        RETURN jsonb_build_object(
            'valid', false,
            'reason', 'NOT_FOUND',
            'message', 'Invalid or expired OTP. Please request a new OTP.'
        );
    END IF;

    -- Check 5-minute expiry
    IF v_now > v_challenge.expires_at THEN
        DELETE FROM public.otp_challenges WHERE identifier = p_identifier;
        RETURN jsonb_build_object(
            'valid', false,
            'reason', 'EXPIRED',
            'message', 'OTP has expired. Please request a new OTP.'
        );
    END IF;

    -- Check if max attempts already reached
    IF v_challenge.attempts >= v_challenge.max_attempts THEN
        DELETE FROM public.otp_challenges WHERE identifier = p_identifier;
        RETURN jsonb_build_object(
            'valid', false,
            'reason', 'MAX_ATTEMPTS',
            'message', 'Maximum incorrect attempts exceeded. This OTP has been invalidated. Please request a new OTP.'
        );
    END IF;

    -- Compare HMAC-SHA256 digests
    IF v_challenge.hashed_code <> p_incoming_hash THEN
        v_new_attempts := v_challenge.attempts + 1;
        v_remaining := v_challenge.max_attempts - v_new_attempts;

        IF v_remaining <= 0 THEN
            DELETE FROM public.otp_challenges WHERE identifier = p_identifier;
            RETURN jsonb_build_object(
                'valid', false,
                'reason', 'MAX_ATTEMPTS',
                'remainingAttempts', 0,
                'message', 'Maximum incorrect attempts exceeded. This OTP has been invalidated. Please request a new OTP.'
            );
        END IF;

        UPDATE public.otp_challenges
        SET attempts = v_new_attempts
        WHERE identifier = p_identifier;

        RETURN jsonb_build_object(
            'valid', false,
            'reason', 'INVALID_CODE',
            'remainingAttempts', v_remaining,
            'message', 'Invalid OTP code. ' || v_remaining || ' attempt(s) remaining.'
        );
    END IF;

    -- Valid match! Delete immediately inside locked transaction to enforce single-use replay protection
    DELETE FROM public.otp_challenges WHERE identifier = p_identifier;

    RETURN jsonb_build_object(
        'valid', true,
        'reason', 'VERIFIED',
        'message', 'OTP verified successfully.'
    );
END;
$$;

-- 4D. Safe Invalidation & Cooldown Rollback if Carrier SMS Dispatch Fails
CREATE OR REPLACE FUNCTION public.invalidate_otp_challenge(
    p_identifier TEXT,
    p_rollback_rate_limit BOOLEAN DEFAULT true
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_limit public.otp_rate_limits%ROWTYPE;
BEGIN
    IF p_identifier IS NULL OR BTRIM(p_identifier) = '' THEN
        RETURN jsonb_build_object('invalidated', false);
    END IF;

    DELETE FROM public.otp_challenges WHERE identifier = p_identifier;

    IF p_rollback_rate_limit THEN
        SELECT * INTO v_limit
        FROM public.otp_rate_limits
        WHERE identifier = p_identifier
        FOR UPDATE;

        IF FOUND THEN
            UPDATE public.otp_rate_limits
            SET request_count = GREATEST(0, request_count - 1),
                last_requested_at = TO_TIMESTAMP(0),
                updated_at = NOW()
            WHERE identifier = p_identifier;
        END IF;
    END IF;

    RETURN jsonb_build_object('invalidated', true);
END;
$$;

-- Restrict RPC execution strictly to service_role (Express backend)
REVOKE ALL ON FUNCTION public.check_otp_rate_limit(TEXT, INTEGER, INTEGER, INTEGER) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.check_otp_rate_limit(TEXT, INTEGER, INTEGER, INTEGER) TO service_role;

REVOKE ALL ON FUNCTION public.request_otp_challenge(TEXT, TEXT, INTEGER, INTEGER, INTEGER, INTEGER, INTEGER) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.request_otp_challenge(TEXT, TEXT, INTEGER, INTEGER, INTEGER, INTEGER, INTEGER) TO service_role;

REVOKE ALL ON FUNCTION public.verify_otp_challenge(TEXT, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.verify_otp_challenge(TEXT, TEXT) TO service_role;

REVOKE ALL ON FUNCTION public.invalidate_otp_challenge(TEXT, BOOLEAN) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.invalidate_otp_challenge(TEXT, BOOLEAN) TO service_role;
