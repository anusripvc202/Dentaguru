const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '../../.env') });
const { supabaseAdmin } = require('../config/supabase');

async function purgeExceptSeshuAndAkhila() {
    console.log('🗑️ Purging database: Keeping ONLY Dentist Dr. G.Sheshu Kumar, Patient Bashipaka Akhila, and Admin...');

    // 1. Identify users to keep
    const preservedEmails = [
        'gouda.sheshukumar@gmail.com', // Dentist Dr. G.Sheshu Kumar
        'ammuamala895@gmail.com',       // Patient bashipaka akhila
        'anusripvc202@gmail.com',       // Admin
        'admin@dentaguru.com',          // Admin
        'ssrajuqc@gmail.com',           // Sub-Admin
    ];

    const preservedNames = [
        'dr. g.sheshu kumar',
        'sheshu kumar',
        'seshu',
        'bashipaka akhila',
        'bhashipaka akhila',
        'anusri',
        'sri',
    ];

    function shouldKeepUser(user) {
        if (!user) return false;
        const email = (user.email || '').toLowerCase().trim();
        const name = (user.name || '').toLowerCase().trim();
        const role = (user.role || '').toLowerCase().trim();
        
        if (preservedEmails.includes(email)) return true;
        if (preservedNames.some(n => name.includes(n))) return true;
        if (role.includes('admin')) return true;
        return false;
    }

    // 2. Fetch all users from public.users
    const { data: allUsers, error: uErr } = await supabaseAdmin.from('users').select('*');
    if (uErr) {
        console.error('Error fetching users:', uErr);
        process.exit(1);
    }

    const usersToKeep = [];
    const usersToDelete = [];

    for (const u of allUsers) {
        if (shouldKeepUser(u)) {
            usersToKeep.push(u);
            console.log(`🛡️ KEEP USER: [${u.role}] ${u.name} (${u.email}) [ID: ${u.id}]`);
        } else {
            usersToDelete.push(u);
            console.log(`❌ TO DELETE: [${u.role}] ${u.name} (${u.email}) [ID: ${u.id}]`);
        }
    }

    const deleteUserIds = usersToDelete.map(u => u.id);
    const keepUserIds = usersToKeep.map(u => u.id);

    // 3. Clear problem requests, suggestions, appointments for deleted users or reset them cleanly
    const tablesToClean = [
        'chat_messages',
        'medical_records',
        'dentist_suggestions',
        'appointments',
        'patient_problem_requests',
        'notifications',
    ];

    for (const tbl of tablesToClean) {
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

    // 4. In `dentists` table: keep Sheshu Kumar's dentist record and delete other dentists
    try {
        const { data: allDentists } = await supabaseAdmin.from('dentists').select('*');
        if (allDentists) {
            for (const d of allDentists) {
                if (keepUserIds.includes(d.user_id)) {
                    console.log(`🛡️ KEEP DENTIST: id=${d.id}, user_id=${d.user_id}`);
                } else {
                    await supabaseAdmin.from('dentists').delete().eq('id', d.id);
                    console.log(`✅ DELETED DENTIST: id=${d.id}, user_id=${d.user_id}`);
                }
            }
        }
    } catch (e) {
        console.warn('Error cleaning dentists table:', e.message);
    }

    // 5. In `clinics` table: remove clinics not linked to Sheshu Kumar
    try {
        const { data: keepDentists } = await supabaseAdmin.from('dentists').select('clinic_id');
        const keepClinicIds = (keepDentists || []).map(d => d.clinic_id).filter(Boolean);
        
        const { data: allClinics } = await supabaseAdmin.from('clinics').select('*');
        if (allClinics) {
            for (const c of allClinics) {
                if (keepClinicIds.includes(c.id)) {
                    console.log(`🛡️ KEEP CLINIC: ${c.name} (${c.id})`);
                } else {
                    await supabaseAdmin.from('clinics').delete().eq('id', c.id);
                    console.log(`✅ DELETED CLINIC: ${c.name} (${c.id})`);
                }
            }
        }
    } catch (e) {
        console.warn('Error cleaning clinics table:', e.message);
    }

    // 6. Delete non-preserved users from public.users
    for (const u of usersToDelete) {
        try {
            const { error: delErr } = await supabaseAdmin.from('users').delete().eq('id', u.id);
            if (delErr) {
                console.warn(`⚠️ Error deleting public user ${u.email}:`, delErr.message);
            } else {
                console.log(`✅ DELETED public.users: ${u.name} (${u.email})`);
            }
        } catch (e) {
            console.warn(`⚠️ Error deleting public user ${u.email}:`, e.message);
        }
    }

    // 7. Delete non-preserved users from Supabase Auth
    try {
        const { data: { users: authUsers }, error: authErr } = await supabaseAdmin.auth.admin.listUsers();
        if (!authErr && authUsers) {
            for (const au of authUsers) {
                const auEmail = (au.email || '').toLowerCase().trim();
                const shouldKeepAuth = preservedEmails.includes(auEmail);
                if (!shouldKeepAuth) {
                    await supabaseAdmin.auth.admin.deleteUser(au.id);
                    console.log(`✅ DELETED auth.users: ${au.email} [ID: ${au.id}]`);
                } else {
                    console.log(`🛡️ PRESERVED auth.users: ${au.email} [ID: ${au.id}]`);
                }
            }
        }
    } catch (e) {
        console.warn('Auth users purge note:', e.message);
    }

    console.log('\n=========================================');
    console.log('🎉 PURGE SUCCESSFUL!');
    console.log('Preserved in DB:');
    console.log(' - Dentist: Dr. G.Sheshu Kumar (gouda.sheshukumar@gmail.com / 8977906566)');
    console.log(' - Patient: bashipaka akhila (ammuamala895@gmail.com / 7799332395)');
    console.log(' - Admin / Sub-Admin accounts');
    console.log('All other sample / duplicate data removed!');
    console.log('=========================================\n');
    process.exit(0);
}

purgeExceptSeshuAndAkhila().catch(err => {
    console.error('Fatal error purging DB:', err);
    process.exit(1);
});
