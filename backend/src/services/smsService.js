const https = require('https');
const http = require('http');

/**
 * Send Real Mobile SMS via Fast2SMS (India +91) or Twilio (Global)
 * @param {string} phone - Target mobile number (e.g. +919988776655 or 9988776655)
 * @param {string} otpCode - 4-digit OTP code (e.g. 8849)
 */
const sendRealSmsOtp = async (phone, otpCode) => {
    if (!phone || !phone.trim()) {
        console.log('⚠️ SMS Service: No phone number provided.');
        return { success: false, reason: 'No phone number provided' };
    }

    const cleanPhone = phone.trim().replaceAll(/[^0-9]/g, '');
    const isIndia = cleanPhone.length === 10 || (cleanPhone.length === 12 && cleanPhone.startsWith('91'));
    const phone10Digit = cleanPhone.length > 10 ? cleanPhone.slice(-10) : cleanPhone;

    // 1. Fast2SMS Integration (India +91 Numbers)
    const fast2smsKey = process.env.FAST2SMS_API_KEY;
    if (fast2smsKey && isIndia) {
        try {
            console.log(`📱 Sending Real SMS via Fast2SMS to [${phone10Digit}]...`);
            const postData = JSON.stringify({
                route: 'otp',
                variables_values: otpCode,
                numbers: phone10Digit,
            });

            const options = {
                hostname: 'www.fast2sms.com',
                path: '/dev/bulkV2',
                method: 'POST',
                headers: {
                    'authorization': fast2smsKey,
                    'Content-Type': 'application/json',
                    'Content-Length': Buffer.byteLength(postData),
                },
            };

            return new Promise((resolve) => {
                const req = https.request(options, (res) => {
                    let body = '';
                    res.on('data', chunk => body += chunk);
                    res.on('end', () => {
                        console.log(`✅ Fast2SMS API Response: ${body}`);
                        resolve({ success: res.statusCode === 200, gateway: 'Fast2SMS', response: body });
                    });
                });
                req.on('error', (err) => {
                    console.error('❌ Fast2SMS Error:', err.message);
                    resolve({ success: false, error: err.message });
                });
                req.write(postData);
                req.end();
            });
        } catch (err) {
            console.error('❌ Fast2SMS Exception:', err.message);
        }
    }

    // 2. Twilio SMS Integration (Global Numbers)
    const twilioAccountSid = process.env.TWILIO_ACCOUNT_SID;
    const twilioAuthToken = process.env.TWILIO_AUTH_TOKEN;
    const twilioFromNumber = process.env.TWILIO_PHONE_NUMBER;

    if (twilioAccountSid && twilioAuthToken && twilioFromNumber) {
        try {
            const formattedPhone = phone.startsWith('+') ? phone : `+${phone}`;
            console.log(`📱 Sending Real SMS via Twilio to [${formattedPhone}]...`);
            const auth = Buffer.from(`${twilioAccountSid}:${twilioAuthToken}`).toString('base64');
            const postData = new URLSearchParams({
                To: formattedPhone,
                From: twilioFromNumber,
                Body: `Your DentaGuru Security OTP Verification Code is ${otpCode}. Valid for 10 minutes.`,
            }).toString();

            const options = {
                hostname: 'api.twilio.com',
                path: `/2010-04-01/Accounts/${twilioAccountSid}/Messages.json`,
                method: 'POST',
                headers: {
                    'Authorization': `Basic ${auth}`,
                    'Content-Type': 'application/x-www-form-urlencoded',
                    'Content-Length': Buffer.byteLength(postData),
                },
            };

            return new Promise((resolve) => {
                const req = https.request(options, (res) => {
                    let body = '';
                    res.on('data', chunk => body += chunk);
                    res.on('end', () => {
                        console.log(`✅ Twilio API Response: ${body}`);
                        resolve({ success: res.statusCode === 200 || res.statusCode === 201, gateway: 'Twilio', response: body });
                    });
                });
                req.on('error', (err) => {
                    console.error('❌ Twilio Error:', err.message);
                    resolve({ success: false, error: err.message });
                });
                req.write(postData);
                req.end();
            });
        } catch (err) {
            console.error('❌ Twilio Exception:', err.message);
        }
    }

    console.log(`ℹ️ Real SMS simulation active for phone [${phone}] (Code: ${otpCode}). Configure FAST2SMS_API_KEY or TWILIO_ACCOUNT_SID in .env for live carrier SMS dispatch.`);
    return { success: true, simulated: true, code: otpCode };
};

module.exports = {
    sendRealSmsOtp,
};
