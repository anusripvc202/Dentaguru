const { createClient } = require('@supabase/supabase-js');
require('dotenv').config({ path: require('path').resolve(__dirname, '../../.env') });

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.SUPABASE_ANON_KEY);

async function testUpdate() {
  console.log('Testing update with assigned_doctor_id columns:');
  const reqId = '17d84a4e-d402-4382-acae-79ef56a5e535';
  const dentistId = 'afb07295-955f-4ad2-a48f-b67ffb7cfd65'; // Dentist Nikhil in dentists table

  const { data, error } = await supabase.from('patient_problem_requests').update({
    status: 'DENTIST_ASSIGNED',
    suggested_dentist_id: dentistId,
    assigned_doctor_id: dentistId,
    assigned_doctor_name: 'Dr. Nikhil',
    assigned_doctor_specialty: 'General Dentistry',
    assigned_doctor_clinic: 'DentaGuru Clinic',
    admin_notes: 'Test notes'
  }).eq('id', reqId).select();

  console.log('Result with extra columns:', { data, error });

  console.log('\nTesting update with ONLY native schema columns:');
  const { data: data2, error: error2 } = await supabase.from('patient_problem_requests').update({
    status: 'DENTIST_ASSIGNED',
    suggested_dentist_id: dentistId,
    admin_notes: 'Test notes'
  }).eq('id', reqId).select();

  console.log('Result with native columns:', { data: data2, error: error2 });
}

testUpdate().then(() => process.exit(0)).catch(e => { console.error(e); process.exit(1); });
