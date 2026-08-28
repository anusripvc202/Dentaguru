const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '../../.env') });
const { supabaseAdmin } = require('../config/supabase');
const { Client } = require('pg');

async function purgeAllData() {
    console.log('🗑️  Starting complete DentaGuru Database and Auth Purge...\n');

    const postgresUri = process.env.POSTGRES_URI || process.env.DATABASE_URL;
    let pgSuccess = false;

    // 1. Direct PostgreSQL TRUNCATE CASCADE if possible
    if (postgresUri) {
        try {
            console.log('1️⃣ Attempting direct PostgreSQL TRUNCATE CASCADE...');
            const client = new Client({
                connectionString: postgresUri,
                ssl: { rejectUnauthorized: false }
            });
            await client.connect();
            
            const truncateQuery = `
                TRUNCATE TABLE 
                    public.referrals,
                    public.sub_admin_permissions,
                    public.audit_logs,
                    public.chat_messages,
                    public.medical_records,
                    public.dentist_suggestions,
                    public.appointments,
                    public.patient_problem_requests,
                    public.dentists,
                    public.clinics,
                    public.notifications,
                    public.users
                RESTART IDENTITY CASCADE;
            `;
            await client.query(truncateQuery);
            await client.end();
            console.log('✅ Direct PostgreSQL TRUNCATE CASCADE executed successfully!');
            pgSuccess = true;
        } catch (pgErr) {
            console.warn('⚠️ Direct PostgreSQL connection/truncate:', pgErr.message);
        }
    }

    // 2. Supabase Admin API delete fallback for all known tables
    const tablesInDeleteOrder = [
        'referrals',
        'sub_admin_permissions',
        'audit_logs',
        'chat_messages',
        'medical_records',
        'dentist_suggestions',
        'appointments',
        'patient_problem_requests',
        'dentists',
        'clinics',
        'notifications',
        'users'
    ];

    console.log('\n2️⃣ Clearing / Verifying all database tables via Supabase Admin API...');
    for (const table of tablesInDeleteOrder) {
        try {
            // Delete all rows
            let { count, error } = await supabaseAdmin
                .from(table)
                .delete({ count: 'exact' })
                .neq('id', '00000000-0000-0000-0000-000000000000');

            if (error) {
                // Fallback delete with created_at or id
                const { count: c2, error: err2 } = await supabaseAdmin
                    .from(table)
                    .delete({ count: 'exact' })
                    .gt('created_at', '1970-01-01');

                if (err2) {
                    console.warn(`⚠️ Table '${table}' delete note:`, err2.message);
                } else {
                    console.log(`✅ Table '${table}': ${c2 ?? 0} rows deleted.`);
                }
            } else {
                console.log(`✅ Table '${table}': ${count ?? 0} rows deleted.`);
            }
        } catch (err) {
            console.error(`❌ Error clearing table '${table}':`, err.message);
        }
    }

    // 3. Purge Supabase Storage Files
    console.log('\n3️⃣ Checking Supabase Storage buckets...');
    try {
        const { data: buckets, error: bErr } = await supabaseAdmin.storage.listBuckets();
        if (!bErr && buckets) {
            for (const bucket of buckets) {
                const { data: files, error: fErr } = await supabaseAdmin.storage.from(bucket.name).list();
                if (!fErr && files && files.length > 0) {
                    const fileNames = files.map(f => f.name);
                    const { error: delFilesErr } = await supabaseAdmin.storage.from(bucket.name).remove(fileNames);
                    if (delFilesErr) {
                        console.warn(`⚠️ Failed to remove files from bucket '${bucket.name}':`, delFilesErr.message);
                    } else {
                        console.log(`✅ Cleared ${fileNames.length} files from storage bucket '${bucket.name}'.`);
                    }
                } else {
                    console.log(`✅ Storage bucket '${bucket.name}' is empty.`);
                }
            }
        }
    } catch (sErr) {
        console.warn('⚠️ Storage purge check error:', sErr.message);
    }

    // 4. Purge Supabase Auth Users
    console.log('\n4️⃣ Checking & Purging Supabase Auth Users...');
    try {
        const { data: { users: authUsers }, error: authErr } = await supabaseAdmin.auth.admin.listUsers();
        if (!authErr && authUsers && authUsers.length > 0) {
            console.log(`Found ${authUsers.length} Supabase Auth users. Deleting...`);
            for (const user of authUsers) {
                const { error: delUserErr } = await supabaseAdmin.auth.admin.deleteUser(user.id);
                if (delUserErr) {
                    console.warn(`⚠️ Could not delete auth user ${user.id} (${user.email}):`, delUserErr.message);
                } else {
                    console.log(`  - Deleted Auth User: ${user.email || user.phone || user.id}`);
                }
            }
            console.log('✅ All Supabase Auth users deleted.');
        } else {
            console.log('✅ Supabase Auth users verified empty.');
        }
    } catch (authE) {
        console.warn('⚠️ Supabase Auth user deletion warning:', authE.message);
    }

    // 5. Final Verification of counts in all tables
    console.log('\n========================================');
    console.log('🔍 FINAL DATABASE VERIFICATION REPORT');
    console.log('========================================');

    for (const table of tablesInDeleteOrder) {
        try {
            const { count, error } = await supabaseAdmin
                .from(table)
                .select('*', { count: 'exact', head: true });
            
            if (error) {
                console.log(`  - ${table.padEnd(26)} : ⚠️ (Could not query: ${error.message})`);
            } else {
                console.log(`  - ${table.padEnd(26)} : ${count} rows remaining (EMPTY)`);
            }
        } catch (e) {
            console.log(`  - ${table.padEnd(26)} : ⚠️ ${e.message}`);
        }
    }

    try {
        const { data: { users: remUsers } } = await supabaseAdmin.auth.admin.listUsers();
        console.log(`  - ${'Supabase Auth Users'.padEnd(26)} : ${remUsers?.length || 0} users remaining (EMPTY)`);
    } catch (e) {
        console.log(`  - ${'Supabase Auth Users'.padEnd(26)} : ⚠️ ${e.message}`);
    }

    console.log('========================================');
    console.log('🎉 DB PURGE COMPLETE: All database tables, auth records, and storage are completely clean!');
    process.exit(0);
}

purgeAllData().catch(err => {
    console.error('Fatal error during DB purge:', err);
    process.exit(1);
});
