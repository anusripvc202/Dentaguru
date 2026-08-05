require('dotenv').config();
const { supabaseAdmin } = require('../config/supabase');

async function clearDatabase() {
    console.log('⚡ Starting Supabase PostgreSQL Database Reset...');
    try {
        console.log('Clearing chat_messages table...');
        await supabaseAdmin.from('chat_messages').delete().neq('id', '00000000-0000-0000-0000-000000000000');

        console.log('Clearing medical_records table...');
        await supabaseAdmin.from('medical_records').delete().neq('id', '00000000-0000-0000-0000-000000000000');

        console.log('Clearing appointments table...');
        await supabaseAdmin.from('appointments').delete().neq('id', '00000000-0000-0000-0000-000000000000');

        console.log('Clearing dentists table...');
        await supabaseAdmin.from('dentists').delete().neq('id', '00000000-0000-0000-0000-000000000000');

        console.log('Clearing clinics table...');
        await supabaseAdmin.from('clinics').delete().neq('id', '00000000-0000-0000-0000-000000000000');

        console.log('Clearing users table...');
        await supabaseAdmin.from('users').delete().neq('id', '00000000-0000-0000-0000-000000000000');

        console.log('✅ ALL SUPABASE POSTGRESQL TABLES CLEARED SUCCESSFULLY!');
        process.exit(0);
    } catch (e) {
        console.error('❌ Reset error:', e.message);
        process.exit(1);
    }
}

clearDatabase();
