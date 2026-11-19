require('dotenv').config();
const { createClient } = require('@supabase/supabase-js');

const PRODUCTION_SUPABASE_PROJECT_REF = 'fommrwxpqzkcktweosgp';

/**
 * Fail-closed Supabase configuration resolver:
 * - Zero hardcoded production URL or key fallbacks.
 * - Fails immediately if SUPABASE_URL, SUPABASE_ANON_KEY, or SUPABASE_SERVICE_ROLE_KEY is missing.
 * - In development/testing (NODE_ENV !== 'production'), refuses connecting to production Supabase.
 */
function resolveSupabaseConfig(env = process.env) {
    const nodeEnv = (env.NODE_ENV || 'development').trim().toLowerCase();
    const isProduction = nodeEnv === 'production';

    const supabaseUrl = (env.SUPABASE_URL || '').trim().replace(/\/+$/, '');
    const supabaseAnonKey = (env.SUPABASE_ANON_KEY || '').trim();
    const supabaseServiceKey = (env.SUPABASE_SERVICE_ROLE_KEY || '').trim();

    const missing = [];
    if (!supabaseUrl || supabaseUrl.toLowerCase().includes('placeholder')) {
        missing.push('SUPABASE_URL');
    }
    if (!supabaseAnonKey || supabaseAnonKey.toLowerCase().includes('placeholder')) {
        missing.push('SUPABASE_ANON_KEY');
    }
    if (!supabaseServiceKey || supabaseServiceKey.toLowerCase().includes('placeholder')) {
        missing.push('SUPABASE_SERVICE_ROLE_KEY');
    }

    if (missing.length > 0) {
        throw new Error(
            `GS HEALTH Supabase Configuration Error (${nodeEnv}): Missing required environment variable(s): ${missing.join(', ')}. ` +
            'Hardcoded fallback credentials are disabled.'
        );
    }

    if (!/^https?:\/\//i.test(supabaseUrl)) {
        throw new Error(
            `GS HEALTH Supabase Configuration Error (${nodeEnv}): SUPABASE_URL must be a valid HTTP(S) URL.`
        );
    }

    if (!isProduction) {
        const normalizedUrl = supabaseUrl.toLowerCase();
        const prodUrl = (env.PRODUCTION_SUPABASE_URL || '').trim().toLowerCase().replace(/\/+$/, '');
        if (
            normalizedUrl.includes(PRODUCTION_SUPABASE_PROJECT_REF) ||
            (prodUrl && normalizedUrl === prodUrl)
        ) {
            throw new Error(
                `GS HEALTH Isolation Error (${nodeEnv}): Local development/testing backend must never connect to ` +
                `production Supabase project (${PRODUCTION_SUPABASE_PROJECT_REF}). Configure a dedicated test Supabase project.`
            );
        }
    }

    return {
        supabaseUrl,
        supabaseAnonKey,
        supabaseServiceKey,
    };
}

const { supabaseUrl, supabaseAnonKey, supabaseServiceKey } = resolveSupabaseConfig(process.env);

// Public client (with Anon key)
const supabase = createClient(supabaseUrl, supabaseAnonKey);

// Admin client (with Service Role key for elevated server operations)
const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey, {
    auth: {
        autoRefreshToken: false,
        persistSession: false
    }
});

/**
 * Health check helper to test Supabase connectivity & auto-initialize default bucket
 */
const checkSupabaseHealth = async () => {
    try {
        if (!process.env.SUPABASE_URL || process.env.SUPABASE_URL.includes('placeholder')) {
            return { configured: false, status: 'unconfigured', message: 'SUPABASE_URL environment variable is not configured.' };
        }
        // Ping storage buckets list to test API key & network connection
        const { data: buckets, error } = await supabaseAdmin.storage.listBuckets();
        if (error) throw error;

        // Auto-create default bucket if missing
        const bucketName = 'dentaguru-storage';
        const exists = buckets.some(b => b.name === bucketName);
        if (!exists) {
            await supabaseAdmin.storage.createBucket(bucketName, {
                public: true,
                fileSizeLimit: 20971520 // 20MB
            });
            console.log(`✅ Supabase Storage Bucket '${bucketName}' created successfully.`);
        }

        return { configured: true, status: 'connected', bucketsCount: buckets ? buckets.length : 0 };
    } catch (err) {
        return { configured: true, status: 'error', message: err.message };
    }
};

module.exports = {
    supabase,
    supabaseAdmin,
    checkSupabaseHealth,
    resolveSupabaseConfig,
    PRODUCTION_SUPABASE_PROJECT_REF,
};


