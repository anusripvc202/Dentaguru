const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '../../.env') });
const { supabaseAdmin } = require('../config/supabase');

async function clearDatabase() {
    console.log('⚡ Starting Supabase PostgreSQL Database Reset...');
    try {
        const tables = ['chat_messages', 'medical_records', 'appointments', 'dentists', 'clinics', 'users'];

        for (const tbl of tables) {
            console.log(`Clearing ${tbl} table...`);
            const { error } = await supabaseAdmin.from(tbl).delete().gt('created_at', '1970-01-01');
            if (error) console.error(`Error deleting from ${tbl}:`, error.message);
            else console.log(`  - ${tbl} cleared successfully.`);
        }

        console.log('✅ ALL SUPABASE POSTGRESQL TABLES CLEARED SUCCESSFULLY!');
        process.exit(0);
    } catch (e) {
        console.error('❌ Reset error:', e.message);
        process.exit(1);
    }
}

clearDatabase();
