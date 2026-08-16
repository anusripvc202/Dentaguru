const { createClient } = require('@supabase/supabase-js');
require('dotenv').config({ path: require('path').resolve(__dirname, '../../.env') });

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.SUPABASE_ANON_KEY);

async function inspectAll() {
  console.log('\n================== 1. ADMIN USERS IN DATABASE ==================');
  const { data: admins } = await supabase
    .from('users')
    .select('id, name, email, role, phone, created_at')
    .or('role.ilike.%admin%,email.ilike.%admin%');
  console.log(JSON.stringify(admins, null, 2));

  console.log('\n================== 2. ALL USERS IN DATABASE ==================');
  const { data: users } = await supabase
    .from('users')
    .select('id, name, email, role, phone, city, state, pincode');
  console.log(JSON.stringify(users, null, 2));

  console.log('\n================== 3. ALL DENTISTS IN DATABASE ==================');
  const { data: dentists } = await supabase
    .from('dentists')
    .select('id, user_id, speciality, clinic_id, users(name, email, phone), clinics(clinic_name, location)');
  console.log(JSON.stringify(dentists, null, 2));

  console.log('\n================== 4. PATIENT PROBLEM REQUESTS ==================');
  const { data: requests } = await supabase
    .from('patient_problem_requests')
    .select('*');
  console.log(JSON.stringify(requests, null, 2));

  console.log('\n================== 5. DENTIST SUGGESTIONS TABLE ==================');
  try {
    const { data: suggestions, error: sugErr } = await supabase
      .from('dentist_suggestions')
      .select('*');
    console.log('Suggestions:', sugErr || JSON.stringify(suggestions, null, 2));
  } catch (e) {
    console.log('No dentist_suggestions table or error:', e.message);
  }

  console.log('\n================== 6. APPOINTMENTS TABLE ==================');
  const { data: appointments } = await supabase
    .from('appointments')
    .select('id, patient_id, dentist_id, appointment_date, time_slot, status, reason');
  console.log(JSON.stringify(appointments, null, 2));
}

inspectAll().then(() => {}).catch(console.error);
