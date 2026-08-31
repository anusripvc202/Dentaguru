require('dotenv').config({ path: require('path').resolve(__dirname, '../../.env') });
const { createClient } = require('@supabase/supabase-js');

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);

async function testRpc() {
  const rpcs = ['exec_sql', 'execute_sql', 'sql', 'run_sql', 'exec', 'execute'];
  for (const r of rpcs) {
    const { data, error } = await supabase.rpc(r, { query: 'SELECT 1;' });
    if (!error) {
      console.log(`✅ RPC '${r}' exists!`);
      return;
    } else {
      console.log(`❌ RPC '${r}': ${error.message}`);
    }
  }
}

testRpc();
