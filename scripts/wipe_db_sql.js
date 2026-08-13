/**
 * DentaGuru – SQL Fallback Wipe for tables not in PostgREST schema cache.
 * Uses a direct PostgreSQL connection with TRUNCATE ... CASCADE.
 */

const { Client } = require('pg');

const DATABASE_URL =
  'postgresql://postgres:ftYPDdeY0kEjDsaG@db.fommrwxpqzkcktweosgp.supabase.co:5432/postgres';

const TABLES = [
  'notifications',
  'dentist_suggestions',
  'patient_problem_requests',
];

async function main() {
  const client = new Client({ connectionString: DATABASE_URL, ssl: { rejectUnauthorized: false } });
  await client.connect();
  console.log('Connected to Supabase PostgreSQL\n');

  for (const table of TABLES) {
    try {
      // Check if table exists first
      const exists = await client.query(
        `SELECT to_regclass('public.${table}') AS result`
      );
      if (!exists.rows[0].result) {
        console.log(`  - ${table}: table does not exist (skipped)`);
        continue;
      }
      const res = await client.query(`TRUNCATE TABLE public.${table} CASCADE`);
      console.log(`  v ${table}: truncated`);
    } catch (err) {
      console.error(`  x ${table}: ${err.message}`);
    }
  }

  await client.end();
  console.log('\nDone.');
}

main().catch((err) => {
  console.error('Fatal:', err.message);
  process.exit(1);
});
