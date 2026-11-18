-- =============================================================================
-- GS HEALTH ROLLBACK SCRIPT: 02_rollback_supabase_otp_storage.sql
-- Reverses all RPC functions and tables introduced in 02_supabase_otp_storage.sql
-- Order: Drop dependent PL/pgSQL RPC functions first, then drop tables & indexes.
-- =============================================================================

-- 1. Drop atomic OTP RPC functions (dependent on otp_challenges & otp_rate_limits row types)
DROP FUNCTION IF EXISTS public.invalidate_otp_challenge(TEXT, BOOLEAN);
DROP FUNCTION IF EXISTS public.verify_otp_challenge(TEXT, TEXT);
DROP FUNCTION IF EXISTS public.request_otp_challenge(TEXT, TEXT, INTEGER, INTEGER, INTEGER, INTEGER, INTEGER);
DROP FUNCTION IF EXISTS public.check_otp_rate_limit(TEXT, INTEGER, INTEGER, INTEGER);

-- 2. Drop OTP tables (automatically removes associated indexes and RLS policies)
DROP TABLE IF EXISTS public.otp_challenges;
DROP TABLE IF EXISTS public.otp_rate_limits;
