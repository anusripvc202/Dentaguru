const { createClient } = require('@supabase/supabase-js');
require('dotenv').config({ path: require('path').resolve(__dirname, '../../.env') });

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.SUPABASE_ANON_KEY);

async function updateReferralRequests() {
  console.log('=== UPDATING REFERRAL REQUESTS TO DIRECT DOCTOR ASSIGNMENT ===\n');

  // 1. Get Dr. Nikhil's dentist id
  const { data: dentists } = await supabase
    .from('dentists')
    .select('id, user_id, users(name)')
    .limit(5);

  const nikhil = dentists?.find(d => d.users?.name?.toLowerCase().includes('nikhil')) || dentists?.[0];
  if (!nikhil) {
    console.log('No dentist found.');
    return;
  }
  console.log('Target Doctor:', nikhil);

  // 2. Find problem requests with referral description
  const { data: requests } = await supabase
    .from('patient_problem_requests')
    .select('*');

  for (const r of requests || []) {
    const isReferral = (r.problem_description || '').toLowerCase().includes('nikhil') ||
                       (r.problem_description || '').toLowerCase().includes('refer');
    if (isReferral) {
      console.log(`Updating request ${r.id} -> DENTIST_ASSIGNED (Dr. Nikhil)...`);
      await supabase
        .from('patient_problem_requests')
        .update({
          status: 'DENTIST_ASSIGNED',
          suggested_dentist_id: nikhil.id,
          admin_notes: 'Direct referral to Dr. Nikhil (Nikhil clinic)'
        })
        .eq('id', r.id);

      // Ensure dentist_suggestion exists
      const { data: existingSug } = await supabase
        .from('dentist_suggestions')
        .select('*')
        .eq('request_id', r.id);

      if (!existingSug || existingSug.length === 0) {
        await supabase
          .from('dentist_suggestions')
          .insert({
            request_id: r.id,
            patient_id: r.patient_id,
            dentist_id: nikhil.id,
            status: 'SUGGESTED',
            notes: 'Direct patient referral selection to Dr. Nikhil'
          });
      }
    }
  }

  console.log('\nAll referral requests updated to direct doctor assignment.');
}

updateReferralRequests().then(() => process.exit(0)).catch(e => { console.error(e); process.exit(1); });
