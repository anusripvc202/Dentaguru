/**
 * List all tables in the public schema via Supabase information_schema view.
 */

const { createClient } = require('@supabase/supabase-js');

const supabase = createClient(
  'https://fommrwxpqzkcktweosgp.supabase.co',
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZvbW1yd3hwcXprY2t0d2Vvc2dwIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc4NTgxMzcxMCwiZXhwIjoyMTAxMzg5NzEwfQ.1M9FR4AJujgbNWF9s3rgTwewN6BiBTNalY53mDMCvGg',
  { auth: { persistSession: false } }
);

async function main() {
  // Try each table and see if it responds
  const tables = [
    'users', 'clinics', 'dentists', 'appointments', 'medical_records',
    'chat_messages', 'notifications', 'dentist_suggestions', 'patient_problem_requests'
  ];

  console.log('Checking table existence:\n');
  for (const t of tables) {
    const { data, error } = await supabase.from(t).select('id').limit(1);
    if (error) {
      console.log(`  MISSING  ${t}  (${error.message})`);
    } else {
      console.log(`  EXISTS   ${t}`);
    }
  }
}

main().catch(console.error);
