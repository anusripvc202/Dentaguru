const { createClient } = require('@supabase/supabase-js');
require('dotenv').config({ path: require('path').resolve(__dirname, '../../.env') });

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.SUPABASE_ANON_KEY);

async function listPatients() {
  console.log('=== REGISTERED PATIENTS IN DATABASE ===\n');

  // 1. Fetch all users with role 'Patient'
  const { data: patients, error: pErr } = await supabase
    .from('users')
    .select('*')
    .ilike('role', '%Patient%');

  if (pErr) {
    console.error('Error fetching patients:', pErr.message);
    return;
  }

  console.log(`Total Registered Patients: ${patients.length}\n`);

  for (const [idx, p] of patients.entries()) {
    console.log(`--- Patient #${idx + 1} ---`);
    console.log(`User ID: ${p.id}`);
    console.log(`Name: ${p.name || 'Not provided'}`);
    console.log(`Email: ${p.email}`);
    console.log(`Phone: ${p.phone || 'Not provided'}`);
    console.log(`Role: ${p.role}`);
    console.log(`Location: ${p.city || ''}, ${p.state || ''} (PIN: ${p.pincode || ''})`);
    console.log(`Created At: ${p.created_at || 'N/A'}`);

    // Check patient problem requests
    const { data: reqs } = await supabase
      .from('patient_problem_requests')
      .select('id, problem_category, status, created_at, suggested_dentist_id')
      .eq('patient_id', p.id);

    console.log(`Problem Requests (${reqs?.length || 0}):`, reqs);

    // Check appointments
    const { data: appts } = await supabase
      .from('appointments')
      .select('id, treatment, status, dentist_id, appointment_date, time_slot')
      .eq('patient_id', p.id);

    console.log(`Appointments (${appts?.length || 0}):`, appts);
    console.log('\n');
  }

  // 2. Also check all users in database for completeness
  console.log('=== ALL USERS IN DATABASE ===');
  const { data: allUsers } = await supabase.from('users').select('id, name, email, role, created_at');
  console.table(allUsers);
}

listPatients().then(() => process.exit(0)).catch(e => { console.error(e); process.exit(1); });
