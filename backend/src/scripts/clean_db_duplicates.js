const { createClient } = require('@supabase/supabase-js');
require('dotenv').config({ path: require('path').resolve(__dirname, '../../.env') });

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.SUPABASE_ANON_KEY);

async function cleanDuplicatesInDb() {
  console.log('--- Cleaning DB duplicate entries ---');

  // 1. Remove orphaned unassigned appointment for anu where assigned appointment already exists
  const { error: aErr } = await supabase.from('appointments').delete().eq('id', '567e70e7-7374-44f9-94b0-997676ae466f');
  if (aErr) console.log('Appointment cleanup notice:', aErr.message);
  else console.log('✅ Cleaned duplicate unassigned appointment');

  // 2. Remove duplicate suggestion
  const { error: sErr } = await supabase.from('dentist_suggestions').delete().eq('id', '0d68e029-d3bf-4bcc-8578-d3ef7a95383d');
  if (sErr) console.log('Suggestion cleanup notice:', sErr.message);
  else console.log('✅ Cleaned duplicate dentist suggestion');

  console.log('--- Clean complete ---');
}

cleanDuplicatesInDb().then(() => process.exit(0)).catch(e => { console.error(e); process.exit(1); });
