const { createClient } = require('@supabase/supabase-js');
require('dotenv').config();

async function run() {
  const anon = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_ANON_KEY);
  const targetId = '17ce7b7d-310c-448b-ad31-7648a98af363';
  
  console.log('Testing query from ApiService.fetchPatientProblemRequests...');
  const { data, error } = await anon
    .from('patient_problem_requests')
    .select(`
      *,
      patient:users!patient_id(id, name, email, phone, city, state, pincode),
      dentist:dentists!suggested_dentist_id(
        id,
        speciality,
        users:user_id(name, email, phone),
        clinics:clinic_id(clinic_name, location)
      )
    `)
    .eq('patient_id', targetId);
    
  console.log('Error:', error);
  console.log('Data:', JSON.stringify(data, null, 2));
}

run().then(() => process.exit(0)).catch(e => { console.error(e); process.exit(1); });
