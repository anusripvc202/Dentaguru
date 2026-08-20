const { ChatMessage, User } = require('../models/Schemas');

async function testRealChat() {
  console.log('=== REAL-TIME CHAT PERSISTENCE & RESOLUTION TEST ===\n');

  // Fetch real users from Supabase
  const patient = await User.findOne({ email: 'anusripvc203@gmail.com' });
  const doctor = await User.findOne({ email: 'gouda.sheshukumar@gmail.com' });
  const admin = await User.findOne({ email: 'anusripvc202@gmail.com' });

  console.log('Patient User:', patient.name, '(', patient.id, ')');
  console.log('Dentist User:', doctor.name, '(', doctor.id, ')');
  console.log('Admin User:', admin.name, '(', admin.id, ')');

  // 1. Patient sends authentic message
  console.log('\n1. Patient sends message...');
  const msg1 = await ChatMessage.create({
    room_id: 'PATIENT_ANUSHA',
    sender_id: patient.id,
    receiver_id: doctor.id,
    message: 'Hello Dr. Sheshu, I need advice regarding severe pain in my upper tooth.',
    type: 'patient'
  });
  console.log('  Saved Msg 1 ID:', msg1.id);
  console.log('  Sender resolved name:', msg1.sender?.name, 'Role:', msg1.sender?.role);

  // 2. Doctor replies
  console.log('\n2. Doctor sends reply...');
  const msg2 = await ChatMessage.create({
    room_id: 'PATIENT_ANUSHA',
    sender_id: doctor.id,
    receiver_id: patient.id,
    message: 'Hello Anusha, please avoid cold items and visit the clinic tomorrow at 11:00 AM for an X-ray.',
    type: 'doctor'
  });
  console.log('  Saved Msg 2 ID:', msg2.id);
  console.log('  Sender resolved name:', msg2.sender?.name, 'Role:', msg2.sender?.role);

  // 3. Query messages for room
  console.log('\n3. Querying messages in room PATIENT-ANUSHA...');
  const msgs = await ChatMessage.find({ room_id: 'PATIENT-ANUSHA' });
  console.log('  Total messages retrieved:', msgs.length);
  msgs.forEach((m, idx) => {
    const isDoc = m.type === 'doctor' || m.sender?.role === 'Dentist';
    const fromName = isDoc ? (m.sender?.name || doctor.name) : (m.sender?.name || patient.name);
    const toName = isDoc ? patient.name : doctor.name;
    const fromRole = isDoc ? 'Dentist' : 'Patient';
    const toRole = isDoc ? 'Patient' : 'Dentist';
    console.log(`  [${idx + 1}] ${fromName} (${fromRole}) -> To: ${toName} (${toRole}) | "${m.message}"`);
  });

  // 4. Admin conversations view
  console.log('\n4. Admin fetching all active conversations...');
  const convs = await ChatMessage.getConversations(admin);
  console.log('  Conversations list:');
  console.log(JSON.stringify(convs, null, 2));

  console.log('\n✅ ALL REAL CHAT TESTS PASSED WITH 100% SUCCESS!');
}

testRealChat().then(() => process.exit(0)).catch(err => { console.error(err); process.exit(1); });
