const { createClient } = require('@supabase/supabase-js');
require('dotenv').config();

async function testAnon() {
  const url = process.env.SUPABASE_URL;
  const anonKey = process.env.SUPABASE_ANON_KEY;
  console.log('Testing Supabase Anon Key with URL:', url);

  const anonClient = createClient(url, anonKey);
  const testRoom = 'CHAT_TEST_ANON';

  console.log('1. Testing Anon Insert...');
  const { data: insertData, error: insertErr } = await anonClient
    .from('chat_messages')
    .insert({
      room_id: testRoom,
      message: 'Hello from Anon test',
      type: 'doctor'
    })
    .select();

  console.log('  Insert result:', insertData);
  console.log('  Insert error:', insertErr);

  console.log('\n2. Testing Anon Select with joined users...');
  const { data: selectData, error: selectErr } = await anonClient
    .from('chat_messages')
    .select('*, sender:users!sender_id(id, name, email, role), receiver:users!receiver_id(id, name, email, role)')
    .eq('room_id', testRoom);

  console.log('  Select result:', selectData);
  console.log('  Select error:', selectErr);

  console.log('\n3. Testing Anon Select simple...');
  const { data: simpleData, error: simpleErr } = await anonClient
    .from('chat_messages')
    .select('*')
    .eq('room_id', testRoom);

  console.log('  Simple select result:', simpleData);
  console.log('  Simple select error:', simpleErr);

  if (insertData && insertData[0]) {
    await anonClient.from('chat_messages').delete().eq('id', insertData[0].id);
    console.log('  Cleaned up test message.');
  }
}

testAnon().then(() => process.exit(0)).catch(e => { console.error(e); process.exit(1); });
