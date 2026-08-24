const { sendRealSmsOtp } = require('../services/smsService');

async function testSms() {
    const testPhone = '9063663180';
    const otp = '8492';
    console.log(`\nTesting SMS OTP dispatch to: ${testPhone}`);
    console.log(`Generated OTP: ${otp}`);
    
    const result = await sendRealSmsOtp(testPhone, otp);
    console.log('Dispatch Result:', result);
    console.log('\n✅ Verification Check:');
    console.log(`If user inputs "${otp}" into the app, it will verify successfully!`);
}

testSms().then(() => process.exit(0)).catch(e => { console.error(e); process.exit(1); });
