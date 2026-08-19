const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '../../.env') });
const { supabaseAdmin } = require('../config/supabase');

async function purgeExceptAdmin() {
    console.log('🗑️ Purging database data while preserving Admin accounts...');
    
    const tables = [
        'chat_messages',
        'medical_records',
        'dentist_suggestions',
        'appointments',
        'patient_problem_requests',
        'notifications',
        'dentists',
        'clinics',
    ];

    for (const tbl of tables) {
        try {
            const { count, error } = await supabaseAdmin
                .from(tbl)
                .delete({ count: 'exact' })
                .neq('id', '00000000-0000-0000-0000-000000000000');
            if (error) {
                console.warn(`⚠️ Warning clearing '${tbl}':`, error.message);
            } else {
                console.log(`✅ Cleared '${tbl}' (${count ?? 0} rows deleted)`);
            }
        } catch (e) {
            console.warn(`⚠️ Error clearing '${tbl}':`, e.message);
        }
    }

    // Delete users that are NOT Admin
    try {
        const { data: allUsers, error: uErr } = await supabaseAdmin.from('users').select('id, name, email, role');
        if (!uErr && allUsers) {
            for (const u of allUsers) {
                const roleLower = (u.role || '').toLowerCase();
                const emailLower = (u.email || '').toLowerCase();
                const isAdmin = roleLower.includes('admin') || emailLower.includes('anusripvc202') || emailLower.includes('admin@dentaguru.com');
                
                if (!isAdmin) {
                    await supabaseAdmin.from('users').delete().eq('id', u.id);
                    console.log(`✅ Deleted User: ${u.name} (${u.email}) [Role: ${u.role}]`);
                } else {
                    console.log(`🛡️ Preserved Admin User: ${u.name} (${u.email}) [Role: ${u.role}]`);
                }
            }
        }
    } catch (e) {
        console.error('Error deleting non-admin users:', e.message);
    }

    // Delete non-admin Auth users
    try {
        const { data: { users }, error: authErr } = await supabaseAdmin.auth.admin.listUsers();
        if (!authErr && users && users.length > 0) {
            for (const u of users) {
                const emailLower = (u.email || '').toLowerCase();
                const isAdmin = emailLower.includes('anusripvc202') || emailLower.includes('admin@dentaguru.com');
                
                if (!isAdmin) {
                    await supabaseAdmin.auth.admin.deleteUser(u.id);
                    console.log(`✅ Deleted Auth user: ${u.email}`);
                } else {
                    console.log(`🛡️ Preserved Auth user: ${u.email}`);
                }
            }
        }
    } catch (authE) {
        console.warn('Auth purge note:', authE.message);
    }

    console.log('\n🎉 Purge complete! Only Admin accounts remain in the database.');
    process.exit(0);
}

purgeExceptAdmin();
