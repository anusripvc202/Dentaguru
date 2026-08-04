require('dotenv').config();
const { createClient } = require('@supabase/supabase-js');

const supabaseUrl = process.env.SUPABASE_URL || 'https://placeholder-url.supabase.co';
const supabaseAnonKey = process.env.SUPABASE_ANON_KEY || 'placeholder-anon-key';
const supabaseServiceKey = process.env.SUPABASE_SERVICE_ROLE_KEY || supabaseAnonKey;

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
            return { configured: false, status: 'unconfigured', message: 'SUPABASE_URL environment variable is using default placeholder.' };
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
    checkSupabaseHealth
};


