const path = require('path');
require('dotenv').config({ path: path.resolve(__dirname, '../../.env') });
const { supabaseAdmin } = require('../config/supabase');
const bcrypt = require('bcryptjs');

async function checkRahul() {
    try {
        const { data, error } = await supabaseAdmin.from('users').select('*').ilike('email', 'rahul202@gmail.com').maybeSingle();
        console.log('User data for rahul202@gmail.com:', data);
        if (data && data.password) {
            console.log('Stored password in DB:', data.password);
            const matchesTrivikram = await bcrypt.compare('Trivikram', data.password).catch(() => false);
            console.log('Matches "Trivikram" (bcrypt):', matchesTrivikram);
            console.log('Matches "Trivikram" (plaintext):', data.password === 'Trivikram');
        }

        // Also check Supabase Auth currentUser / users
        const { data: authUsers, error: aErr } = await supabaseAdmin.auth.admin.listUsers();
        const rahulAuth = authUsers?.users?.find(u => u.email === 'rahul202@gmail.com');
        console.log('Rahul in Supabase Auth:', rahulAuth ? { id: rahulAuth.id, email: rahulAuth.email } : 'Not in Supabase Auth');

    } catch (e) {
        console.error('Error checking user:', e);
    } finally {
        process.exit(0);
    }
}

checkRahul();
