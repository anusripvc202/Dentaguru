const { createClient } = require('@supabase/supabase-js');
require('dotenv').config({ path: require('path').resolve(__dirname, '../../.env') });
const { PatientProblemRequest, DentistSuggestion, Dentist, User } = require('../models/Schemas');
const problemController = require('../controllers/problemRequestController');

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.SUPABASE_ANON_KEY);

async function runMultiDentistTest() {
  console.log('=== MULTI-DENTIST ISOLATION & PERSISTENCE TEST ===\n');

  // Dentist A: Nikhil
  const docA_userId = '980e86de-41d1-4160-9f08-66abb35a41b8';
  const docA_dentistId = 'afb07295-955f-4ad2-a48f-b67ffb7cfd65';

  // Dentist B: Satya
  const docB_userId = '1a327e09-4cdf-4b9e-932d-f6eef5b87661';
  const docB_dentistId = 'ce7bf581-e71b-45b7-a07f-f0a6caa8c495';

  // 1. Ensure Request 1 is assigned to Dentist A
  const req1Id = '17d84a4e-d402-4382-acae-79ef56a5e535';
  await supabase.from('patient_problem_requests').update({
    status: 'DENTIST_ASSIGNED',
    suggested_dentist_id: docA_dentistId,
    admin_notes: 'Assigned to Dr. Nikhil'
  }).eq('id', req1Id);

  // 2. Query Dentist A via controller
  console.log('Step 1: Querying Dentist A (Nikhil) dashboard...');
  const reqA = { query: { dentistId: docA_userId }, user: { id: docA_userId, role: 'Dentist' } };
  let resAData = null;
  const resA = {
    json: (d) => { resAData = d; return d; },
    status: () => resA
  };
  await problemController.getDentistAssignedRequests(reqA, resA);
  console.log(`Dentist A requests count: ${resAData?.count || resAData?.requests?.length}`);
  console.log('Dentist A requests:', resAData?.requests?.map(r => ({ id: r.id, patient: r.patientName, status: r.status, suggested_dentist_id: r.suggested_dentist_id })));

  // 3. Query Dentist B via controller
  console.log('\nStep 2: Querying Dentist B (Satya) dashboard (unassigned)...');
  const reqB = { query: { dentistId: docB_userId }, user: { id: docB_userId, role: 'Dentist' } };
  let resBData = null;
  const resB = {
    json: (d) => { resBData = d; return d; },
    status: () => resB
  };
  await problemController.getDentistAssignedRequests(reqB, resB);
  console.log(`Dentist B requests count: ${resBData?.count || resBData?.requests?.length} (Expected: 0)`);

  // 4. Admin suggests Dentist B for Request 1 or a new request
  console.log('\nStep 3: Creating Request 2 for Patient and assigning to Dentist B...');
  const { data: newReq } = await supabase.from('patient_problem_requests').insert({
    patient_id: '3968be4f-54b2-487e-98b1-195a9539155a',
    problem_category: 'Orthodontic Braces Consultation',
    problem_description: 'Need braces consultation',
    status: 'PENDING_ADMIN_REVIEW'
  }).select().single();

  console.log('Created Request 2:', newReq.id);

  // Admin assigns Request 2 to Dentist B
  const suggestReq = {
    params: { id: newReq.id },
    body: {
      dentistId: docB_userId, // Pass user ID
      doctorName: 'Dr. Satya',
      notes: 'Assigned to Dr. Satya Orthodontics'
    },
    user: { id: '0e910148-3d14-462e-8360-cab694a70209', role: 'Admin' }
  };
  let suggestResData = null;
  const suggestRes = {
    json: (d) => { suggestResData = d; return d; },
    status: (code) => { return { json: (d) => { suggestResData = d; return d; } }; }
  };
  await problemController.suggestDentist(suggestReq, suggestRes);
  console.log('Admin suggest dentist result:', suggestResData?.success, suggestResData?.message);

  // 5. Query Dentist B again
  console.log('\nStep 4: Querying Dentist B after assignment...');
  let resBData2 = null;
  const resB2 = {
    json: (d) => { resBData2 = d; return d; },
    status: () => resB2
  };
  await problemController.getDentistAssignedRequests(reqB, resB2);
  console.log(`Dentist B requests count: ${resBData2?.count || resBData2?.requests?.length} (Expected: 1)`);
  console.log('Dentist B requests:', resBData2?.requests?.map(r => ({ id: r.id, patient: r.patientName, category: r.problem_category, suggested_dentist_id: r.suggested_dentist_id })));

  // 6. Query Dentist A again (must still have Request 1 and NOT Request 2)
  console.log('\nStep 5: Querying Dentist A to verify existing data is preserved...');
  let resAData2 = null;
  const resA2 = {
    json: (d) => { resAData2 = d; return d; },
    status: () => resA2
  };
  await problemController.getDentistAssignedRequests(reqA, resA2);
  console.log(`Dentist A requests count: ${resAData2?.count || resAData2?.requests?.length} (Expected: 1)`);
  console.log('Dentist A requests:', resAData2?.requests?.map(r => ({ id: r.id, patient: r.patientName, category: r.problem_category })));

  // Clean up temporary request 2
  await supabase.from('patient_problem_requests').delete().eq('id', newReq.id);
  await supabase.from('dentist_suggestions').delete().eq('request_id', newReq.id);
  console.log('\nTest cleanup complete.');
}

runMultiDentistTest().then(() => process.exit(0)).catch(e => { console.error('Test error:', e); process.exit(1); });
