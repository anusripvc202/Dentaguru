const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '../../.env') });
const { supabaseAdmin } = require('../config/supabase');

async function migrateReferrals() {
    console.log('🔄 Checking / Migrating Supabase schema for Referrals...');

    // 1. Try querying referrals table via supabaseAdmin
    const { data, error } = await supabaseAdmin
        .from('referrals')
        .select('*')
        .limit(1);

    if (error) {
        console.log(`⚠️ Note on referrals table query: ${error.message} (Code: ${error.code})`);
        console.log('If table is not yet in Supabase schema cache, create it in Supabase SQL Editor if needed.');
    } else {
        console.log('✅ referrals table exists and is accessible via Supabase client.');
    }

    // 2. Check users table columns
    const { data: uData, error: uErr } = await supabaseAdmin
        .from('users')
        .select('id, name, referral_code')
        .limit(1);

    if (uErr) {
        console.log(`⚠️ Note on users.referral_code: ${uErr.message}`);
    } else {
        console.log('✅ users.referral_code column exists and is accessible.');
    }
}

migrateReferrals().then(() => process.exit(0)).catch(e => {
    console.error(e);
    process.exit(1);
});
