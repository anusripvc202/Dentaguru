require('dotenv').config();
const nodemailer = require('nodemailer');
const https = require('https');

/**
 * Send email via Resend HTTPS REST API (Port 443 - Guaranteed Instant Cloud Delivery)
 */
const sendViaResendApi = (toEmail, subject, html, apiKey) => {
    return new Promise((resolve) => {
        const sender = 'DentaGuru Security <onboarding@resend.dev>';
        const postData = JSON.stringify({
            from: sender,
            to: [toEmail],
            subject: subject,
            html: html,
        });

        const options = {
            hostname: 'api.resend.com',
            port: 443,
            path: '/emails',
            method: 'POST',
            headers: {
                'Authorization': `Bearer ${apiKey.trim()}`,
                'Content-Type': 'application/json',
                'Content-Length': Buffer.byteLength(postData)
            }
        };

        const req = https.request(options, (res) => {
            let body = '';
            res.on('data', (chunk) => body += chunk);
            res.on('end', () => {
                try {
                    const parsed = JSON.parse(body);
                    if (res.statusCode >= 200 && res.statusCode < 300) {
                        console.log(`⚡ Instant Resend API Email dispatched to [${toEmail}] (ID: ${parsed.id})`);
                        resolve({ success: true, messageId: parsed.id });
                    } else {
                        console.warn(`⚠️ Resend API warning (${res.statusCode}):`, parsed.message || body);
                        resolve({ success: false, error: parsed.message || body });
                    }
                } catch (e) {
                    resolve({ success: false, error: body });
                }
            });
        });

        req.on('error', (e) => {
            console.warn('⚠️ Resend HTTPS request failed:', e.message);
            resolve({ success: false, error: e.message });
        });

        req.setTimeout(8000, () => {
            req.destroy();
            resolve({ success: false, error: 'Resend API timeout' });
        });

        req.write(postData);
        req.end();
    });
};

const getTransporter = async () => {
    const gmailUser = (process.env.GMAIL_USER || 'anusripvc202@gmail.com').trim();
    const gmailPass = (process.env.GMAIL_APP_PASSWORD || 'vxrqzpifcemgshkh').trim();

    if (gmailUser && gmailPass) {
        return nodemailer.createTransport({
            host: 'smtp.gmail.com',
            port: 465,
            secure: true,
            auth: {
                user: gmailUser,
                pass: gmailPass,
            },
            tls: {
                rejectUnauthorized: false
            },
            family: 4,
            connectionTimeout: 15000,
            greetingTimeout: 15000,
            socketTimeout: 15000,
        });
    }

    if (process.env.SMTP_HOST && process.env.SMTP_USER) {
        return nodemailer.createTransport({
            host: process.env.SMTP_HOST.trim(),
            port: parseInt(process.env.SMTP_PORT || '587'),
            secure: process.env.SMTP_SECURE === 'true',
            auth: {
                user: process.env.SMTP_USER.trim(),
                pass: process.env.SMTP_PASS.trim(),
            },
            family: 4,
        });
    }

    try {
        const testAccount = await nodemailer.createTestAccount();
        return nodemailer.createTransport({
            host: 'smtp.ethereal.email',
            port: 587,
            secure: false,
            auth: {
                user: testAccount.user,
                pass: testAccount.pass,
            },
            family: 4,
        });
    } catch (err) {
        console.warn('⚠️ Could not initialize Ethereal SMTP transporter:', err.message);
        return null;
    }
};

/**
 * Send 4-Digit OTP Code directly to User Email Inbox
 */
const sendOtpEmail = async (toEmail, otpCode, isPasswordReset = false) => {
    const subject = isPasswordReset
        ? `🔑 DentaGuru Password Reset OTP: ${otpCode}`
        : `📩 DentaGuru Security OTP Verification Code: ${otpCode}`;

    const html = `
        <div style="font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; padding: 20px; background-color: #f4f6f9;">
            <div style="max-width: 500px; margin: auto; background: #ffffff; padding: 28px; border-radius: 16px; box-shadow: 0 4px 15px rgba(0,0,0,0.06); border: 1px solid #e2e8f0;">
                <div style="text-align: center; margin-bottom: 20px;">
                    <h2 style="color: #0B41CD; margin: 0; font-size: 22px;">DentaGuru Security Verification</h2>
                    <p style="color: #64748b; font-size: 13px; margin-top: 4px;">Dental Healthcare Platform Security</p>
                </div>
                <p style="font-size: 14px; color: #334155;">Hello,</p>
                <p style="font-size: 14px; color: #334155;">Please enter the following <strong>4-digit OTP verification code</strong> in your DentaGuru mobile app to complete your verification:</p>
                <div style="text-align: center; margin: 28px 0;">
                    <span style="font-size: 36px; font-weight: 800; letter-spacing: 12px; color: #0B41CD; background: #EEF2FF; padding: 14px 28px; border-radius: 12px; border: 2px dashed #818CF8; display: inline-block;">${otpCode}</span>
                </div>
                <p style="font-size: 12px; color: #64748b; text-align: center; margin-bottom: 0;">This OTP code is valid for 10 minutes. Please do not share this code with anyone.</p>
            </div>
        </div>
    `;

    // Direct Gmail SMTP Port 465 SSL Delivery (Delivers to ANY recipient email worldwide)

    // 2. Secondary Attempt: Nodemailer SMTP (Gmail / Custom SMTP / Ethereal)
    try {
        const mailTransporter = await getTransporter();
        if (!mailTransporter) return { success: false, reason: 'No transporter available' };

        const senderAddress = (process.env.GMAIL_USER || '').trim() || 'anusripvc202@gmail.com';
        const fromHeader = `"DentaGuru Security" <${senderAddress}>`;

        const info = await mailTransporter.sendMail({
            from: fromHeader,
            to: toEmail,
            subject,
            html,
        });

        const previewUrl = nodemailer.getTestMessageUrl(info);
        if (previewUrl) {
            console.log(`📧 Ethereal Real Email Preview URL: ${previewUrl}`);
        }
        console.log(`✅ 4-Digit OTP Email dispatched via Nodemailer to [${toEmail}] (Code: ${otpCode})`);
        return { success: true, messageId: info.messageId, previewUrl, otp: otpCode };
    } catch (err) {
        console.error('❌ Failed to send 4-digit OTP email:', err.message);
        return { success: false, error: err.message };
    }
};

module.exports = {
    sendOtpEmail,
};
