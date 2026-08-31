require('dotenv').config({ path: require('path').resolve(__dirname, '../../.env') });
const { createClient } = require('@supabase/supabase-js');

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);

async function check() {
  console.log('Supabase URL:', process.env.SUPABASE_URL);

  const tables = [
    'users',
    'clinics',
    'dentists',
    'patient_problem_requests',
    'dentist_suggestions',
    'appointments',
    'medical_records',
    'chat_messages',
    'notifications',
    'audit_logs',
    'referrals',
    'patient_referrals'
  ];

  for (const t of tables) {
    const { data, error } = await supabase.from(t).select('*').limit(1);
    if (error) {
      console.log(`❌ Table '${t}': ${error.message} (${error.code})`);
    } else {
      console.log(`✅ Table '${t}': exists (rows returned: ${data.length})`);
    }
  }
}

check();
