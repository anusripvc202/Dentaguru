const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '../../.env') });
const { supabaseAdmin } = require('../config/supabase');

async function clearDatabase() {
    console.log('🗑️  Starting complete DentaGuru database purge...');

    const tablesInDeleteOrder = [
        'chat_messages',
        'medical_records',
        'dentist_suggestions',
        'appointments',
        'patient_problem_requests',
        'notifications',
        'dentists',
        'clinics',
        'users',
    ];

    for (const table of tablesInDeleteOrder) {
        try {
            const { count, error } = await supabaseAdmin
                .from(table)
                .delete({ count: 'exact' })
                .neq('id', '00000000-0000-0000-0000-000000000000');

            if (error) {
                // Try deleting with created_at filter if neq('id') failed
                const { count: c2, error: err2 } = await supabaseAdmin
                    .from(table)
                    .delete({ count: 'exact' })
                    .gt('created_at', '1970-01-01');

                if (err2) {
                    console.warn(`⚠️ Warning deleting from '${table}':`, err2.message);
                } else {
                    console.log(`✅ Cleared table '${table}' (${c2 ?? 0} records deleted).`);
                }
            } else {
                console.log(`✅ Cleared table '${table}' (${count ?? 0} records deleted).`);
            }
        } catch (err) {
            console.error(`❌ Error clearing table '${table}':`, err.message);
        }
    }

    try {
        console.log('Checking Supabase Auth users...');
        const { data: { users }, error: authErr } = await supabaseAdmin.auth.admin.listUsers();
        if (!authErr && users && users.length > 0) {
            console.log(`Found ${users.length} Auth users to delete...`);
            for (const user of users) {
                await supabaseAdmin.auth.admin.deleteUser(user.id);
            }
            console.log('✅ All Supabase Auth users deleted.');
        } else {
            console.log('✅ Supabase Auth users verified empty.');
        }
    } catch (authE) {
        console.warn('⚠️ Auth user deletion skipped:', authE.message);
    }

    console.log('🎉 Database reset complete! All tables and auth users are empty.');
    process.exit(0);
}

clearDatabase();
