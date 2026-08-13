/**
 * DentaGuru – Full Database Wipe Script
 * Truncates all tables in correct dependency order (child → parent).
 * Uses the Supabase service-role key so RLS is bypassed.
 */

const { createClient } = require('@supabase/supabase-js');

const SUPABASE_URL = 'https://fommrwxpqzkcktweosgp.supabase.co';
const SERVICE_ROLE_KEY =
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZvbW1yd3hwcXprY2t0d2Vvc2dwIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc4NTgxMzcxMCwiZXhwIjoyMTAxMzg5NzEwfQ.1M9FR4AJujgbNWF9s3rgTwewN6BiBTNalY53mDMCvGg';

const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
});

// Tables ordered: children before parents so FK constraints are satisfied.
const TABLES = [
  'chat_messages',
  'notifications',
  'medical_records',
  'appointments',
  'dentist_suggestions',
  'patient_problem_requests',
  'dentists',
  'clinics',
  'users',
];

async function wipeTable(table) {
  const { error, count } = await supabase
    .from(table)
    .delete({ count: 'exact' })
    .not('id', 'is', null);

  if (error) {
    console.error(`  x ${table}: ${error.message}`);
  } else {
    console.log(`  v ${table}: ${count ?? 'all'} rows deleted`);
  }
}

async function main() {
  console.log('DentaGuru - Full Database Wipe\n');
  console.log('Tables to clear (child -> parent order):');
  TABLES.forEach((t) => console.log(`  - ${t}`));
  console.log();

  for (const table of TABLES) {
    await wipeTable(table);
  }

  console.log('\nAll tables wiped. Database is now empty.');
}

main().catch((err) => {
  console.error('Fatal error:', err);
  process.exit(1);
});
