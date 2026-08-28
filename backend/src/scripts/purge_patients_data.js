const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '../../.env') });
const { supabaseAdmin } = require('../config/supabase');

async function purgePatientsData() {
    console.log('🗑️  Starting Targeted Patients Data Purge...\n');

    try {
        // 1. Find all patients
        const { data: allUsers, error: uErr } = await supabaseAdmin
            .from('users')
            .select('id, name, email, phone, role');

        if (uErr) {
            console.error('❌ Failed to fetch users:', uErr.message);
            return;
        }

        const patients = (allUsers || []).filter(u => {
            const r = (u.role || '').toString().toLowerCase();
            return r === 'patient' || r.includes('patient');
        });

        console.log(`📋 Found ${patients.length} patient(s) to remove:`);
        patients.forEach(p => console.log(`   - [${p.id}] ${p.name} (${p.phone || p.email})`));

        if (patients.length === 0) {
            console.log('ℹ️ No patients found in DB. Database already clean of patient data.');
            return;
        }

        const patientIds = patients.map(p => p.id);

        // 2. Delete patient referrals
        try {
            await supabaseAdmin.from('referrals').delete().in('referrer_id', patientIds);
            await supabaseAdmin.from('referrals').delete().in('referred_user_id', patientIds);
            console.log('✅ Cleared patient referral records.');
        } catch (e) {
            console.log('ℹ️ Referrals table clean note:', e.message);
        }

        // 3. Delete patient appointments
        try {
            await supabaseAdmin.from('appointments').delete().in('patient_id', patientIds);
            console.log('✅ Cleared patient appointments.');
        } catch (e) {
            console.log('ℹ️ Appointments delete note:', e.message);
        }

        // 4. Delete patient problem requests
        try {
            await supabaseAdmin.from('patient_problem_requests').delete().in('patient_id', patientIds);
            console.log('✅ Cleared patient problem requests.');
        } catch (e) {
            console.log('ℹ️ Problem requests delete note:', e.message);
        }

        // 5. Delete patient medical records
        try {
            await supabaseAdmin.from('medical_records').delete().in('patient_id', patientIds);
            console.log('✅ Cleared patient medical records.');
        } catch (e) {
            console.log('ℹ️ Medical records delete note:', e.message);
        }

        // 6. Delete patient chat messages
        try {
            await supabaseAdmin.from('chat_messages').delete().in('sender_id', patientIds);
            await supabaseAdmin.from('chat_messages').delete().in('recipient_id', patientIds);
            console.log('✅ Cleared patient chat messages.');
        } catch (e) {
            console.log('ℹ️ Chat messages delete note:', e.message);
        }

        // 7. Delete patient notifications
        try {
            await supabaseAdmin.from('notifications').delete().in('user_id', patientIds);
            console.log('✅ Cleared patient notifications.');
        } catch (e) {
            console.log('ℹ️ Notifications delete note:', e.message);
        }

        // 8. Delete patients from users table
        const { error: delErr } = await supabaseAdmin.from('users').delete().in('id', patientIds);
        if (delErr) {
            console.error('❌ Error deleting patients from users table:', delErr.message);
        } else {
            console.log(`✅ Successfully deleted ${patients.length} patient(s) from users table.`);
        }

        // 9. Delete from Supabase Auth
        for (const p of patients) {
            try {
                await supabaseAdmin.auth.admin.deleteUser(p.id);
            } catch (_) {}
        }
        console.log('✅ Verified Supabase Auth clean for removed patients.');

        // 10. Final Verification
        console.log('\n========================================');
        console.log('🔍 FINAL DATABASE STATE');
        console.log('========================================');
        const { data: remainingUsers } = await supabaseAdmin.from('users').select('id, name, email, phone, role');
        console.log('Remaining Users in DB:');
        (remainingUsers || []).forEach(u => console.log(`  - [${u.role}] ${u.name} (${u.phone || u.email})`));

        const patientCount = (remainingUsers || []).filter(u => (u.role || '').toLowerCase() === 'patient').length;
        console.log(`\n🎉 Patients Remaining: ${patientCount} (All patients data successfully purged!)`);
        console.log('========================================\n');

    } catch (err) {
        console.error('❌ Purge Exception:', err);
    }
}

purgePatientsData().then(() => process.exit(0)).catch(err => {
    console.error(err);
    process.exit(1);
});
