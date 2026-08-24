const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '../../.env') });
const { supabaseAdmin } = require('../config/supabase');

async function removeAdminsAndSubAdmins() {
    console.log('🗑️ Removing all Admin and Sub-Admin accounts from DB...');

    const preservedUserIds = [
        'bce272f5-387e-4850-a54d-320eb391f4db', // Dr. G.Sheshu Kumar (Dentist)
        'bc48a045-1a03-49bc-be8e-dc7cc4b2fff9', // bashipaka akhila (Patient)
    ];

    const preservedEmails = [
        'gouda.sheshukumar@gmail.com',
        'ammuamala895@gmail.com',
    ];

    // 1. Fetch public.users to delete
    const { data: users, error: uErr } = await supabaseAdmin.from('users').select('*');
    if (uErr) {
        console.error('Error fetching users:', uErr);
        process.exit(1);
    }

    for (const u of users) {
        if (!preservedUserIds.includes(u.id) && !preservedEmails.includes((u.email || '').toLowerCase())) {
            const { error: delErr } = await supabaseAdmin.from('users').delete().eq('id', u.id);
            if (delErr) {
                console.warn(`⚠️ Error deleting public user ${u.name} (${u.email}):`, delErr.message);
            } else {
                console.log(`✅ DELETED public.users: [${u.role}] ${u.name} (${u.email}) [ID: ${u.id}]`);
            }
        } else {
            console.log(`🛡️ PRESERVED public.users: [${u.role}] ${u.name} (${u.email}) [ID: ${u.id}]`);
        }
    }

    // 2. Delete from Supabase Auth
    try {
        const { data: { users: authUsers }, error: authErr } = await supabaseAdmin.auth.admin.listUsers();
        if (!authErr && authUsers) {
            for (const au of authUsers) {
                const auEmail = (au.email || '').toLowerCase().trim();
                if (!preservedEmails.includes(auEmail)) {
                    await supabaseAdmin.auth.admin.deleteUser(au.id);
                    console.log(`✅ DELETED auth.users: ${au.email} [ID: ${au.id}]`);
                } else {
                    console.log(`🛡️ PRESERVED auth.users: ${au.email} [ID: ${au.id}]`);
                }
            }
        }
    } catch (e) {
        console.warn('Auth user deletion warning:', e.message);
    }

    console.log('\n=========================================');
    console.log('🎉 ALL ADMIN & SUB-ADMIN ACCOUNTS REMOVED!');
    console.log('Preserved in DB:');
    console.log(' - Dentist: Dr. G.Sheshu Kumar (gouda.sheshukumar@gmail.com / 8977906566)');
    console.log(' - Patient: bashipaka akhila (ammuamala895@gmail.com / 7799332395)');
    console.log('=========================================\n');
    process.exit(0);
}

removeAdminsAndSubAdmins().catch(err => {
    console.error('Fatal error:', err);
    process.exit(1);
});
