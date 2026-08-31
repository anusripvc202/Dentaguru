require('dotenv').config({ path: require('path').resolve(__dirname, '../../.env') });
const { createClient } = require('@supabase/supabase-js');

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);

async function inspectTables() {
  const { data: pprData, error: pprError } = await supabase.from('patient_problem_requests').select('*').limit(1);
  console.log('patient_problem_requests sample:', pprData);

  const { data: notifData, error: notifError } = await supabase.from('notifications').select('*').limit(1);
  console.log('notifications sample:', notifData);

  const { data: apptData, error: apptError } = await supabase.from('appointments').select('*').limit(1);
  console.log('appointments sample:', apptData);

  const { data: userData, error: userError } = await supabase.from('users').select('*').limit(1);
  console.log('users sample keys:', userData ? Object.keys(userData[0] || {}) : userError);
}

inspectTables();
