const { createClient } = require('@supabase/supabase-js');
require('dotenv').config({ path: require('path').resolve(__dirname, '../../.env') });

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.SUPABASE_ANON_KEY);

async function testJoinQuery() {
  const { data, error } = await supabase.from('patient_problem_requests').select(`
    *,
    patient:users!patient_id(id, name, email, phone, city, state, pincode),
    dentist:dentists!suggested_dentist_id(
      id,
      speciality,
      users:user_id(name, email, phone),
      clinics:clinic_id(clinic_name, location)
    )
  `).order('created_at', { ascending: false });

  if (error) {
    console.error('Error in joined query:', error);
    return;
  }
  console.log('Joined requests:', JSON.stringify(data, null, 2));
}

testJoinQuery().then(() => {}).catch(console.error);
