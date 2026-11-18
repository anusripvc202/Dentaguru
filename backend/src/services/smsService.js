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
 * @param {object} [options] - Additional dispatch options (e.g. { route: 'q' | 'otp' })
 */
const sendRealSmsOtp = async (phone, otpCode, options = {}) => {
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
            // Fast2SMS Quick SMS Route (route: "q")
            // Note: Fast2SMS officially closed the legacy route=otp API. "q" is the supported route.
            let selectedRoute = (options.route || process.env.FAST2SMS_ROUTE || 'q').trim().toLowerCase();
            if (selectedRoute === 'otp') {
                console.warn('⚠️ [Fast2SMS] Legacy route "otp" is officially closed by provider. Redirecting to supported Quick SMS route "q".');
                selectedRoute = 'q';
            }

            const maskedPhone = phone10Digit.length >= 5 ? phone10Digit.slice(0, 5) + '*****' : '*****';
            console.log(`📱 [Fast2SMS] Dispatching SMS via route [${selectedRoute}] to [+91 ${maskedPhone}]...`);

            // Official Fast2SMS Quick SMS Payload (https://docs.fast2sms.com/reference/quick-sms)
            const postPayload = {
                route: 'q',
                message: smsBody,
                language: 'english',
                flash: 0,
                numbers: phone10Digit,
            };

            const postData = JSON.stringify(postPayload);

            const requestOptions = {
                hostname: 'www.fast2sms.com',
                path: '/dev/bulkV2',
                method: 'POST',
                headers: {
                    'authorization': fast2smsKey.trim(),
                    'Content-Type': 'application/json',
                    'Content-Length': Buffer.byteLength(postData),
                },
            };

            const result = await new Promise((resolve) => {
                const req = https.request(requestOptions, (res) => {
                    let body = '';
                    res.on('data', chunk => body += chunk);
                    res.on('end', () => {
                        let parsed = null;
                        try {
                            parsed = JSON.parse(body);
                        } catch (_) {}

                        const isSuccess = res.statusCode === 200 && (parsed ? parsed.return === true : true);
                        if (isSuccess) {
                            console.log(`✅ [Fast2SMS] Dispatched successfully via route [${selectedRoute}] to [+91 ${maskedPhone}]`);
                        } else {
                            console.warn(`⚠️ [Fast2SMS] Gateway response code ${res.statusCode}: ${body}`);
                        }
                        resolve({
                            success: isSuccess,
                            gateway: 'Fast2SMS',
                            route: selectedRoute,
                            statusCode: res.statusCode,
                            response: body,
                            parsed: parsed
                        });
                    });
                });
                req.on('error', (err) => {
                    console.error('❌ [Fast2SMS] Network error:', err.message);
                    resolve({ success: false, error: err.message, gateway: 'Fast2SMS', route: selectedRoute });
                });
                req.write(postData);
                req.end();
            });

            if (result.success) {
                return result;
            }

            // If Fast2SMS failed and no Twilio fallback is available, return the real carrier error
            let errorMessage = 'Fast2SMS dispatch failed';
            if (result.parsed && result.parsed.message) {
                errorMessage = Array.isArray(result.parsed.message) ? result.parsed.message.join(', ') : result.parsed.message;
            } else {
                try {
                    const parsed = JSON.parse(result.response);
                    if (parsed.message) errorMessage = Array.isArray(parsed.message) ? parsed.message.join(', ') : parsed.message;
                } catch (_) {}
            }

            if (!process.env.TWILIO_ACCOUNT_SID) {
                return {
                    success: false,
                    gateway: 'Fast2SMS',
                    route: selectedRoute,
                    statusCode: result.statusCode,
                    error: errorMessage,
                    response: result.response
                };
            }
        } catch (err) {
            console.error('❌ [Fast2SMS] Exception:', err.message);
            if (!process.env.TWILIO_ACCOUNT_SID) {
                return { success: false, gateway: 'Fast2SMS', error: err.message };
            }
        }
    }

    // 2. Twilio SMS Integration (Global & India Numbers)
    const twilioAccountSid = process.env.TWILIO_ACCOUNT_SID;
    const twilioAuthToken = process.env.TWILIO_AUTH_TOKEN;
    const twilioFromNumber = process.env.TWILIO_PHONE_NUMBER;
    const twilioMessagingServiceSid = process.env.TWILIO_MESSAGING_SERVICE_SID;

    if (twilioAccountSid && twilioAuthToken && (twilioFromNumber || twilioMessagingServiceSid)) {
        const maskedE164 = e164.length > 6 ? `${e164.slice(0, -5)}*****` : '*****';
        try {
            console.log(`📱 [Twilio] Dispatching SMS to [${maskedE164}]...`);
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
                            console.log(`✅ [Twilio] Dispatched successfully to [${maskedE164}]`);
                        } else {
                            console.warn(`⚠️ [Twilio] Gateway response ${res.statusCode}: ${body}`);
                        }
                        resolve({ success: isSuccess, gateway: 'Twilio', statusCode: res.statusCode, response: body });
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
            return { success: false, error: err.message, gateway: 'Twilio' };
        }
    }

    // 3. Production Guard vs Development Simulation Mode
    if (process.env.NODE_ENV === 'production') {
        console.error('❌ [SMS Production Error] No live SMS gateway credentials (FAST2SMS_API_KEY / TWILIO_ACCOUNT_SID) configured.');
        return {
            success: false,
            simulated: false,
            gateway: 'None',
            error: 'SMS gateway is not configured in production environment.'
        };
    }

    const maskedTarget = phone10Digit.length >= 5 ? `+91 ${phone10Digit.slice(0, 5)}*****` : '*****';
    console.log(`ℹ️ [SMS Simulation] OTP code dispatched to [${maskedTarget}]. To send via live carrier, configure FAST2SMS_API_KEY or TWILIO_ACCOUNT_SID in environment.`);
    return { success: true, simulated: true, gateway: 'Simulator' };
};

/**
 * Query Fast2SMS Account Wallet Balance
 * @param {string} [apiKey] - Optional explicit key, defaults to process.env.FAST2SMS_API_KEY
 */
const checkFast2SmsBalance = async (apiKey) => {
    const key = apiKey || process.env.FAST2SMS_API_KEY;
    if (!key) {
        return { success: false, reason: 'FAST2SMS_API_KEY is not configured.' };
    }

    return new Promise((resolve) => {
        const req = https.request({
            hostname: 'www.fast2sms.com',
            path: '/dev/wallet',
            method: 'GET',
            headers: {
                'authorization': key.trim(),
            },
        }, (res) => {
            let body = '';
            res.on('data', chunk => body += chunk);
            res.on('end', () => {
                try {
                    const parsed = JSON.parse(body);
                    resolve({ success: res.statusCode === 200, statusCode: res.statusCode, data: parsed });
                } catch (e) {
                    resolve({ success: false, statusCode: res.statusCode, raw: body });
                }
            });
        });
        req.on('error', (err) => {
            resolve({ success: false, error: err.message });
        });
        req.end();
    });
};

module.exports = {
    sendRealSmsOtp,
    buildOtpMessage,
    normalizePhoneNumber,
    checkFast2SmsBalance,
};
