const { createClient } = require('@supabase/supabase-js');
require('dotenv').config({ path: require('path').resolve(__dirname, '../../.env') });

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.SUPABASE_ANON_KEY);

async function resolveDentistIds(input) {
  if (!input) return { dentistTableId: null, userTableId: null, allIds: [] };
  const str = String(input).trim();
  let dentistTableId = null;
  let userTableId = null;

  // 1. Direct check in dentists table by id or user_id
  try {
    const { data: d } = await supabase.from('dentists').select('id, user_id').or(`id.eq.${str},user_id.eq.${str}`).maybeSingle();
    if (d) {
      dentistTableId = d.id;
      userTableId = d.user_id;
    }
  } catch (_) {}

  // 2. If not found, check in users table by email or name
  if (!dentistTableId) {
    try {
      const { data: u } = await supabase.from('users').select('id').or(`email.eq.${str},name.eq.${str}`).maybeSingle();
      if (u) {
        userTableId = u.id;
        const { data: d } = await supabase.from('dentists').select('id, user_id').eq('user_id', u.id).maybeSingle();
        if (d) {
          dentistTableId = d.id;
        }
      }
    } catch (_) {}
  }

  const allIds = [dentistTableId, userTableId, str].filter(Boolean).filter((v, i, a) => a.indexOf(v) === i);
  return { dentistTableId: dentistTableId || str, userTableId, allIds };
}

async function testResolution() {
  console.log('Testing Nikhil (users.id):', await resolveDentistIds('980e86de-41d1-4160-9f08-66abb35a41b8'));
  console.log('Testing Nikhil (dentists.id):', await resolveDentistIds('afb07295-955f-4ad2-a48f-b67ffb7cfd65'));
  console.log('Testing Satya (users.id):', await resolveDentistIds('1a327e09-4cdf-4b9e-932d-f6eef5b87661'));
  console.log('Testing Satya (dentists.id):', await resolveDentistIds('ce7bf581-e71b-45b7-a07f-f0a6caa8c495'));
}

testResolution().then(() => process.exit(0)).catch(e => { console.error(e); process.exit(1); });
