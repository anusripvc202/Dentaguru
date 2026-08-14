const { createClient } = require('@supabase/supabase-js');
require('dotenv').config({ path: require('path').resolve(__dirname, '../../.env') });

const supabaseUrl = process.env.SUPABASE_URL;
const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.SUPABASE_ANON_KEY;

console.log('Supabase URL:', supabaseUrl ? 'Found' : 'Missing');
console.log('Supabase Key:', supabaseKey ? 'Found' : 'Missing');

const supabase = createClient(supabaseUrl, supabaseKey);

async function inspectDb() {
  console.log('=== USERS (Dentist/Doctor) ===');
  const { data: users, error: uErr } = await supabase.from('users').select('*');
  if (uErr) console.error('Users err:', uErr);
  else {
    console.log(`Total users: ${users.length}`);
    users.forEach(u => console.log(`User: id=${u.id}, name=${u.name}, email=${u.email}, role=${u.role}`));
  }

  console.log('\n=== DENTISTS TABLE ===');
  const { data: dentists, error: dErr } = await supabase.from('dentists').select('*');
  if (dErr) console.error('Dentists err:', dErr);
  else {
    console.log(`Total dentists: ${dentists.length}`);
    dentists.forEach(d => console.log(`Dentist: id=${d.id}, user_id=${d.user_id}, clinic_id=${d.clinic_id}, speciality=${d.speciality}`));
  }

  console.log('\n=== PATIENT PROBLEM REQUESTS ===');
  const { data: requests, error: rErr } = await supabase.from('patient_problem_requests').select('*');
  if (rErr) console.error('Requests err:', rErr);
  else {
    console.log(`Total requests: ${requests.length}`);
    requests.forEach(r => console.log(`Request: id=${r.id}, patient_name=${r.patient_name}, patient_id=${r.patient_id}, suggested_dentist_id=${r.suggested_dentist_id}, assigned_doctor_id=${r.assigned_doctor_id}, status=${r.status}, admin_notes=${r.admin_notes}`));
  }

  console.log('\n=== DENTIST SUGGESTIONS ===');
  const { data: suggestions, error: sErr } = await supabase.from('dentist_suggestions').select('*');
  if (sErr) console.error('Suggestions err:', sErr);
  else {
    console.log(`Total suggestions: ${suggestions?.length || 0}`);
    suggestions?.forEach(s => console.log(`Suggestion: id=${s.id}, request_id=${s.request_id}, dentist_id=${s.dentist_id}, status=${s.status}`));
  }

  console.log('\n=== APPOINTMENTS ===');
  const { data: appointments, error: aErr } = await supabase.from('appointments').select('*');
  if (aErr) console.error('Appointments err:', aErr);
  else {
    console.log(`Total appointments: ${appointments?.length || 0}`);
    appointments?.forEach(a => console.log(`Appointment: id=${a.id}, patient_id=${a.patient_id}, dentist_id=${a.dentist_id}, status=${a.status}, treatment=${a.treatment}`));
  }
}

inspectDb().then(() => process.exit(0)).catch(e => { console.error(e); process.exit(1); });
