const { createClient } = require('@supabase/supabase-js');
require('dotenv').config({ path: require('path').resolve(__dirname, '../../.env') });

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.SUPABASE_ANON_KEY);

async function checkAppointments() {
  const { data: appts, error } = await supabase.from('appointments').select('*');
  console.log('Appointments in DB:', appts);
  if (error) console.error('Appt error:', error);
}

checkAppointments().then(() => process.exit(0)).catch(e => { console.error(e); process.exit(1); });
