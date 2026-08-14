const { createClient } = require('@supabase/supabase-js');
require('dotenv').config({ path: require('path').resolve(__dirname, '../../.env') });

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.SUPABASE_ANON_KEY);

async function testFk() {
  const reqId = '17d84a4e-d402-4382-acae-79ef56a5e535';
  const dentistTableId = 'afb07295-955f-4ad2-a48f-b67ffb7cfd65'; // In dentists table
  const userTableId = '980e86de-41d1-4160-9f08-66abb35a41b8';    // In users table

  console.log('Testing with dentistTableId:');
  const r1 = await supabase.from('patient_problem_requests').update({ suggested_dentist_id: dentistTableId }).eq('id', reqId).select();
  console.log('r1:', r1.error ? r1.error.message : 'SUCCESS');

  console.log('Testing with userTableId:');
  const r2 = await supabase.from('patient_problem_requests').update({ suggested_dentist_id: userTableId }).eq('id', reqId).select();
  console.log('r2:', r2.error ? r2.error.message : 'SUCCESS');
}

testFk().then(() => process.exit(0)).catch(e => { console.error(e); process.exit(1); });
