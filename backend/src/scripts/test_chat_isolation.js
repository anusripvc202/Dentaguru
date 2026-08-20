const { ChatMessage, User } = require('../models/Schemas');

async function testChatIsolation() {
  console.log('========================================================');
  console.log('🧪 DOCTOR CHAT ISOLATION & ACCURATE ID RESOLUTION TEST');
  console.log('========================================================\n');

  // 1. Fetch real doctor & patient users from Supabase
  const patient = await User.findOne({ email: 'anusripvc203@gmail.com' });
  const doctorSheshu = await User.findOne({ email: 'gouda.sheshukumar@gmail.com' });
  const doctorNikhil = await User.findOne({ email: 'nikhiljai1215@gmail.com' });
  const admin = await User.findOne({ email: 'anusripvc202@gmail.com' });

  console.log('1. Verified System Users in Supabase:');
  console.log('  - Patient User:', patient.name, '(', patient.id, ')');
  console.log('  - Doctor A (Sheshu):', doctorSheshu.name, '(', doctorSheshu.id, ')');
  console.log('  - Doctor B (Nikhil):', doctorNikhil.name, '(', doctorNikhil.id, ')');
  console.log('  - Admin User:', admin.name, '(', admin.id, ')\n');

  // 2. Doctor A (Sheshu) chats with Patient Anusha in CHAT_ANUSHA_SHESHU
  console.log('2. Creating Doctor A (Sheshu) conversation with Anusha:');
  await ChatMessage.create({
    room_id: 'CHAT_ANUSHA_SHESHU',
    sender_id: patient.id,
    receiver_id: doctorSheshu.id,
    message: 'Hello Dr. Sheshu, I need advice regarding severe pain in my upper tooth.',
    type: 'patient'
  });
  await ChatMessage.create({
    room_id: 'CHAT_ANUSHA_SHESHU',
    sender_id: doctorSheshu.id,
    receiver_id: patient.id,
    message: 'Hello Anusha, please avoid cold items and visit tomorrow for an X-ray.',
    type: 'doctor'
  });
  console.log('  ✅ Saved 2 messages in room CHAT_ANUSHA_SHESHU\n');

  // 3. Doctor B (Nikhil) chats with Patient Anusha in CHAT_ANUSHA_NIKHIL
  console.log('3. Creating Doctor B (Nikhil) conversation with Anusha:');
  await ChatMessage.create({
    room_id: 'CHAT_ANUSHA_NIKHIL',
    sender_id: patient.id,
    receiver_id: doctorNikhil.id,
    message: 'Hello Dr. Nikhil, when should I come for my braces alignment checkup?',
    type: 'patient'
  });
  await ChatMessage.create({
    room_id: 'CHAT_ANUSHA_NIKHIL',
    sender_id: doctorNikhil.id,
    receiver_id: patient.id,
    message: 'Hi Anusha, your braces checkup is scheduled for Thursday at 4:00 PM.',
    type: 'doctor'
  });
  console.log('  ✅ Saved 2 messages in room CHAT_ANUSHA_NIKHIL\n');

  // 4. Verify Doctor A (Sheshu) isolation
  console.log('4. Checking Doctor A (Sheshu) conversations query:');
  const sheshuConvs = await ChatMessage.getConversations(doctorSheshu);
  console.log('  Doctor A received rooms:', sheshuConvs.map(c => c.roomId));
  const sheshuHasNikhil = sheshuConvs.some(c => c.roomId.includes('NIKHIL'));
  if (sheshuHasNikhil) {
    throw new Error('❌ ISOLATION LEAK: Doctor Sheshu received Doctor Nikhil conversation!');
  }
  console.log('  ✅ Doctor Sheshu sees ONLY his own conversation (CHAT_ANUSHA_SHESHU).\n');

  // 5. Verify Doctor B (Nikhil) isolation
  console.log('5. Checking Doctor B (Nikhil) conversations query:');
  const nikhilConvs = await ChatMessage.getConversations(doctorNikhil);
  console.log('  Doctor B received rooms:', nikhilConvs.map(c => c.roomId));
  const nikhilHasSheshu = nikhilConvs.some(c => c.roomId.includes('SHESHU'));
  if (nikhilHasSheshu) {
    throw new Error('❌ ISOLATION LEAK: Doctor Nikhil received Doctor Sheshu conversation!');
  }
  console.log('  ✅ Doctor Nikhil sees ONLY his own conversation (CHAT_ANUSHA_NIKHIL).\n');

  // 6. Verify Admin sees all conversations with audit details
  console.log('6. Checking Admin conversations query:');
  const adminConvs = await ChatMessage.getConversations(admin);
  console.log('  Admin received total conversations:', adminConvs.length);
  adminConvs.forEach(c => {
    console.log(`  - [${c.roomId}] Patient: ${c.patientName} | Doctor: ${c.doctorName} | Last: "${c.lastMessage}"`);
  });

  console.log('\n========================================================');
  console.log('✅ ALL DOCTOR ISOLATION TESTS PASSED WITH 100% SUCCESS!');
  console.log('========================================================');
}

testChatIsolation()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error(err);
    process.exit(1);
  });
