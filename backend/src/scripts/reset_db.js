require('dotenv').config();
const { supabaseAdmin } = require('../config/supabase');

async function clearDatabase() {
    console.log('⚡ Starting Supabase PostgreSQL Database Reset...');
    try {
        const tables = ['chat_messages', 'medical_records', 'appointments', 'dentists', 'clinics', 'users'];

        for (const tbl of tables) {
            console.log(`Clearing ${tbl} table...`);
            const { data } = await supabaseAdmin.from(tbl).select('id');
            if (data && data.length > 0) {
                const ids = data.map(r => r.id);
                const { error } = await supabaseAdmin.from(tbl).delete().in('id', ids);
                if (error) console.error(`Error deleting from ${tbl}:`, error.message);
                else console.log(`  - Deleted ${ids.length} rows from ${tbl}.`);
            } else {
                console.log(`  - ${tbl} is already empty.`);
            }
        }

        console.log('✅ ALL SUPABASE POSTGRESQL TABLES CLEARED SUCCESSFULLY!');
        process.exit(0);
    } catch (e) {
        console.error('❌ Reset error:', e.message);
        process.exit(1);
    }
}

clearDatabase();
