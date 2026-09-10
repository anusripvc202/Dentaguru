const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '../../.env') });
const { supabaseAdmin } = require('../config/supabase');

async function removeAdminDataOnly() {
    console.log('🔍 Inspecting all Admin and SubAdmin accounts in DB...');

    // 1. Fetch all users from public.users
    const { data: publicUsers, error: pubErr } = await supabaseAdmin.from('users').select('*');
    if (pubErr) {
        console.error('Error fetching public.users:', pubErr);
        process.exit(1);
    }

    console.log(`Total public.users found: ${publicUsers.length}`);

    // Identify admin users
    const adminUsers = publicUsers.filter(u => {
        const role = (u.role || '').toLowerCase();
        return role.includes('admin');
    });

    console.log(`Admin/SubAdmin users found in public.users: ${adminUsers.length}`);
    adminUsers.forEach(a => console.log(` - [${a.role}] Name: ${a.name}, Email: ${a.email}, Phone: ${a.phone}, ID: ${a.id}`));

    // Fetch all auth.users
    let authUsers = [];
    try {
        const { data, error } = await supabaseAdmin.auth.admin.listUsers();
        if (error) {
            console.error('Error listing auth.users:', error);
        } else {
            authUsers = data.users || [];
        }
    } catch (e) {
        console.warn('Auth users listing warning:', e.message);
    }

    console.log(`Total auth.users found: ${authUsers.length}`);
    
    // Find auth users that match admin users or have admin metadata/role
    const adminAuthUserIds = new Set();
    const adminEmails = new Set(adminUsers.map(u => (u.email || '').toLowerCase().trim()).filter(Boolean));
    const adminPhones = new Set(adminUsers.map(u => (u.phone || '').trim()).filter(Boolean));

    adminUsers.forEach(u => adminAuthUserIds.add(u.id));

    authUsers.forEach(au => {
        const email = (au.email || '').toLowerCase().trim();
        const phone = (au.phone || '').trim();
        const roleMeta = (au.user_metadata?.role || au.app_metadata?.role || '').toLowerCase();
        
        if (roleMeta.includes('admin') || adminEmails.has(email) || (phone && adminPhones.has(phone))) {
            adminAuthUserIds.add(au.id);
            console.log(` - Auth Admin Match: Email: ${au.email}, Phone: ${au.phone}, ID: ${au.id}, Metadata:`, au.user_metadata);
        }
    });

    console.log(`\n🗑️ Deleting Admin data from public.users...`);
    for (const admin of adminUsers) {
        const { error: delErr } = await supabaseAdmin.from('users').delete().eq('id', admin.id);
        if (delErr) {
            console.error(`❌ Failed to delete public.users ID ${admin.id} (${admin.name}):`, delErr.message);
        } else {
            console.log(`✅ Deleted public.users: [${admin.role}] ${admin.name} (${admin.email || admin.phone}) [ID: ${admin.id}]`);
        }
    }

    console.log(`\n🗑️ Deleting Admin data from auth.users...`);
    for (const authId of adminAuthUserIds) {
        try {
            const { error: authDelErr } = await supabaseAdmin.auth.admin.deleteUser(authId);
            if (authDelErr) {
                console.error(`❌ Failed to delete auth.users ID ${authId}:`, authDelErr.message);
            } else {
                console.log(`✅ Deleted auth.users: ID ${authId}`);
            }
        } catch (e) {
            console.warn(`⚠️ Warning deleting auth user ${authId}:`, e.message);
        }
    }

    // Verify remaining data
    console.log('\n🔍 Verifying remaining DB data...');
    const { data: remainingUsers } = await supabaseAdmin.from('users').select('*');
    console.log(`\n=== REMAINING USERS (${remainingUsers?.length || 0}) ===`);
    remainingUsers?.forEach(u => {
        console.log(`User: [${u.role}] ${u.name} (Email: ${u.email}, Phone: ${u.phone}) [ID: ${u.id}]`);
    });

    const { data: remainingDentists } = await supabaseAdmin.from('dentists').select('*');
    console.log(`\n=== REMAINING DENTISTS (${remainingDentists?.length || 0}) ===`);
    remainingDentists?.forEach(d => {
        console.log(`Dentist ID: ${d.id}, User ID: ${d.user_id}, Speciality: ${d.speciality}`);
    });

    console.log('\n✅ Admin data removal completed successfully!');
    process.exit(0);
}

removeAdminDataOnly().catch(err => {
    console.error('Fatal error:', err);
    process.exit(1);
});
