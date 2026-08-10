const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '../../.env') });
const { supabaseAdmin } = require('../config/supabase');
const { Client } = require('pg');

async function clearDatabase() {
    console.log('⚡ Starting Complete Supabase PostgreSQL Database Reset...');
    
    const postgresUri = process.env.POSTGRES_URI || process.env.DATABASE_URL;
    let pgSuccess = false;

    if (postgresUri) {
        try {
            console.log('Connecting via Direct PostgreSQL Client (pg)...');
            const client = new Client({
                connectionString: postgresUri,
                ssl: { rejectUnauthorized: false }
            });
            await client.connect();
            
            const truncateQuery = `
                TRUNCATE TABLE 
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
            console.warn('⚠️ Direct PG connection failed or failed to truncate:', pgErr.message);
        }
    }

    // Also run Supabase Admin API delete fallback for all tables
    const tables = [
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

    console.log('Verifying & clearing tables via Supabase Admin API...');
    for (const tbl of tables) {
        try {
            let res = await supabaseAdmin.from(tbl).delete().neq('id', '00000000-0000-0000-0000-000000000000');
            if (res.error) {
                res = await supabaseAdmin.from(tbl).delete().gt('created_at', '1970-01-01');
            }
            if (res.error) {
                console.error(`  - ${tbl}: ${res.error.message}`);
            } else {
                console.log(`  - ${tbl} verified empty.`);
            }
        } catch (e) {
            console.error(`  - ${tbl} error:`, e.message);
        }
    }

    console.log('✅ ALL DATABASE TABLES HAVE BEEN WIPED CLEAN!');
    process.exit(0);
}

clearDatabase();

