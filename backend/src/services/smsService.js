const https = require('https');
const http = require('http');

/**
 * Standard GS HEALTH SMS Message Format
 * "Your GS HEALTH verification code is 123456. It is valid for 5 minutes. Do not share this code with anyone."
 */
function buildOtpMessage(otpCode) {
    return `Your GS HEALTH verification code is ${otpCode}. It is valid for 5 minutes. Do not share this code with anyone.`;
}

/**
 * Normalize and validate mobile phone number
 * Returns { isValid: boolean, cleanDigits: string, e164: string }
 */
function normalizePhoneNumber(phone) {
    if (!phone) return { isValid: false, cleanDigits: '', e164: '' };
    const cleanDigits = phone.toString().trim().replace(/[^0-9]/g, '');
    
    // Check Indian 10-digit mobile or with 91 prefix
    let e164 = '';
    if (cleanDigits.length === 10) {
        e164 = `+91${cleanDigits}`;
    } else if (cleanDigits.length === 12 && cleanDigits.startsWith('91')) {
        e164 = `+${cleanDigits}`;
    } else if (cleanDigits.length >= 10 && cleanDigits.length <= 15) {
        e164 = phone.toString().trim().startsWith('+') ? phone.toString().trim() : `+${cleanDigits}`;
    }

    const isValid = cleanDigits.length >= 10 && cleanDigits.length <= 15;
    return { isValid, cleanDigits, e164 };
}

/**
 * Send Real Mobile SMS via Fast2SMS (India +91) or Twilio (Global / E.164)
 * @param {string} phone - Target mobile number (e.g. +919988776655 or 9988776655)
 * @param {string} otpCode - 6-digit OTP code
 */
const sendRealSmsOtp = async (phone, otpCode) => {
    const { isValid, cleanDigits, e164 } = normalizePhoneNumber(phone);
    if (!isValid) {
        console.warn('⚠️ SMS Service: Invalid mobile number format provided.');
        return { success: false, reason: 'Invalid mobile phone number format. Minimum 10 digits required.' };
    }

    const isIndia = cleanDigits.length === 10 || (cleanDigits.length === 12 && cleanDigits.startsWith('91'));
    const phone10Digit = cleanDigits.length > 10 ? cleanDigits.slice(-10) : cleanDigits;
    const smsBody = buildOtpMessage(otpCode);

    // 1. Fast2SMS Integration (India +91 Numbers)
    const fast2smsKey = process.env.FAST2SMS_API_KEY;
    if (fast2smsKey && isIndia) {
        try {
            console.log(`📱 [Fast2SMS] Dispatching OTP SMS to [${phone10Digit}]...`);
            const postData = JSON.stringify({
                route: 'otp',
                variables_values: String(otpCode),
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

            const result = await new Promise((resolve) => {
                const req = https.request(options, (res) => {
                    let body = '';
                    res.on('data', chunk => body += chunk);
                    res.on('end', () => {
                        const isSuccess = res.statusCode === 200;
                        if (isSuccess) {
                            console.log(`✅ [Fast2SMS] Dispatched successfully to [${phone10Digit}]`);
                        } else {
                            console.warn(`⚠️ [Fast2SMS] Gateway response code ${res.statusCode}: ${body}`);
                        }
                        resolve({ success: isSuccess, gateway: 'Fast2SMS', response: body });
                    });
                });
                req.on('error', (err) => {
                    console.error('❌ [Fast2SMS] Network error:', err.message);
                    resolve({ success: false, error: err.message, gateway: 'Fast2SMS' });
                });
                req.write(postData);
                req.end();
            });

            if (result.success) {
                return result;
            }
        } catch (err) {
            console.error('❌ [Fast2SMS] Exception:', err.message);
        }
    }

    // 2. Twilio SMS Integration (Global & India Numbers)
    const twilioAccountSid = process.env.TWILIO_ACCOUNT_SID;
    const twilioAuthToken = process.env.TWILIO_AUTH_TOKEN;
    const twilioFromNumber = process.env.TWILIO_PHONE_NUMBER;
    const twilioMessagingServiceSid = process.env.TWILIO_MESSAGING_SERVICE_SID;

    if (twilioAccountSid && twilioAuthToken && (twilioFromNumber || twilioMessagingServiceSid)) {
        try {
            console.log(`📱 [Twilio] Dispatching SMS to [${e164}]...`);
            const auth = Buffer.from(`${twilioAccountSid}:${twilioAuthToken}`).toString('base64');
            const params = {
                To: e164,
                Body: smsBody,
            };
            if (twilioMessagingServiceSid) {
                params.MessagingServiceSid = twilioMessagingServiceSid;
            } else if (twilioFromNumber) {
                params.From = twilioFromNumber;
            }

            const postData = new URLSearchParams(params).toString();
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

            return await new Promise((resolve) => {
                const req = https.request(options, (res) => {
                    let body = '';
                    res.on('data', chunk => body += chunk);
                    res.on('end', () => {
                        const isSuccess = res.statusCode === 200 || res.statusCode === 201;
                        if (isSuccess) {
                            console.log(`✅ [Twilio] Dispatched successfully to [${e164}]`);
                        } else {
                            console.warn(`⚠️ [Twilio] Gateway response ${res.statusCode}: ${body}`);
                        }
                        resolve({ success: isSuccess, gateway: 'Twilio', response: body });
                    });
                });
                req.on('error', (err) => {
                    console.error('❌ [Twilio] Network error:', err.message);
                    resolve({ success: false, error: err.message, gateway: 'Twilio' });
                });
                req.write(postData);
                req.end();
            });
        } catch (err) {
            console.error('❌ [Twilio] Exception:', err.message);
        }
    }

    // 3. Fallback / Development Simulation mode
    if (process.env.NODE_ENV !== 'production') {
        console.log(`ℹ️ [SMS Simulation] OTP code dispatched to [${e164 || phone10Digit}]. To send via live carrier, configure FAST2SMS_API_KEY or TWILIO_ACCOUNT_SID in environment.`);
    } else {
        console.warn(`⚠️ [SMS Notice] No live SMS gateway credentials (FAST2SMS_API_KEY / TWILIO_ACCOUNT_SID) configured.`);
    }
    return { success: true, simulated: true, gateway: 'Simulator' };
};

module.exports = {
    sendRealSmsOtp,
    buildOtpMessage,
    normalizePhoneNumber,
};
