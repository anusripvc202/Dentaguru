/**
 * DentaGuru – RPC-based wipe for tables missing from schema cache.
 * Uses Supabase's REST API with the service-role key to execute raw SQL.
 */

const https = require('https');

const SUPABASE_URL = 'fommrwxpqzkcktweosgp.supabase.co';
const SERVICE_ROLE_KEY =
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZvbW1yd3hwcXprY2t0d2Vvc2dwIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc4NTgxMzcxMCwiZXhwIjoyMTAxMzg5NzEwfQ.1M9FR4AJujgbNWF9s3rgTwewN6BiBTNalY53mDMCvGg';

const TABLES = [
  'notifications',
  'dentist_suggestions',
  'patient_problem_requests',
];

function postJson(path, body) {
  return new Promise((resolve, reject) => {
    const data = JSON.stringify(body);
    const req = https.request(
      {
        hostname: SUPABASE_URL,
        path,
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Content-Length': Buffer.byteLength(data),
          apikey: SERVICE_ROLE_KEY,
          Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
        },
      },
      (res) => {
        let body = '';
        res.on('data', (c) => (body += c));
        res.on('end', () => resolve({ status: res.statusCode, body }));
      }
    );
    req.on('error', reject);
    req.write(data);
    req.end();
  });
}

async function main() {
  console.log('DentaGuru – RPC SQL Wipe\n');

  // Build a single SQL statement to truncate all three tables at once
  const sql = TABLES.map((t) => `TRUNCATE TABLE public.${t} CASCADE;`).join('\n');
  console.log('Executing SQL:\n' + sql + '\n');

  const result = await postJson('/rest/v1/rpc/exec_sql', { sql });
  console.log('Status:', result.status);
  console.log('Response:', result.body);
}

main().catch((err) => {
  console.error('Fatal:', err.message);
  process.exit(1);
});
