const nodemailer = require('nodemailer');

// Configure Transporter from Environment Variables or Ethereal fallback
let transporter;

const getTransporter = async () => {
    const gmailUser = (process.env.GMAIL_USER || '').trim();
    const gmailPass = (process.env.GMAIL_APP_PASSWORD || '').trim();

    if (gmailUser && gmailPass) {
        return nodemailer.createTransport({
            host: 'smtp.gmail.com',
            port: 587,
            secure: false,
            requireTLS: true,
            auth: {
                user: gmailUser,
                pass: gmailPass,
            },
            tls: {
                rejectUnauthorized: false
            },
            connectionTimeout: 10000,
            greetingTimeout: 10000,
            socketTimeout: 10000,
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
        });
    }

    // Fallback to auto-created Ethereal test account for real-time inbox testing
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
        });
    } catch (err) {
        console.warn('⚠️ Could not initialize Ethereal SMTP transporter:', err.message);
        return null;
    }
};

/**
 * Send an OTP Verification Email to user's inbox
 */
const sendOtpEmail = async (toEmail, otpCode, isReset = false) => {
    if (!toEmail || !toEmail.includes('@')) return { success: false, reason: 'Invalid Email' };

    try {
        const mailTransporter = await getTransporter();
        if (!mailTransporter) return { success: false, reason: 'No transporter' };

        const subject = isReset ? '🔐 DentaGuru Password Reset OTP Code' : '📩 DentaGuru Mobile & Email OTP Verification';
        const html = `
            <div style="font-family: Arial, sans-serif; max-width: 500px; margin: 0 auto; padding: 20px; border: 1px solid #e0e0e0; border-radius: 12px;">
                <div style="text-align: center; margin-bottom: 20px;">
                    <h2 style="color: #0052CC; margin: 0;">🦷 DentaGuru Healthcare</h2>
                    <p style="color: #666; font-size: 13px;">${isReset ? 'Password Reset Verification' : 'Account Registration Verification'}</p>
                </div>
                <div style="background-color: #F8FAFC; padding: 20px; border-radius: 10px; text-align: center;">
                    <p style="font-size: 14px; color: #333; margin-bottom: 10px;">Your 4-Digit Security OTP Code is:</p>
                    <div style="font-size: 32px; font-weight: bold; color: #10B981; letter-spacing: 6px; margin: 15px 0;">${otpCode}</div>
                    <p style="font-size: 12px; color: #777;">This code will expire in 10 minutes. Do not share it with anyone.</p>
                </div>
                <p style="font-size: 11px; color: #aaa; text-align: center; margin-top: 20px;">If you did not request this code, please ignore this email.</p>
            </div>
        `;

        const info = await mailTransporter.sendMail({
            from: process.env.EMAIL_FROM || '"DentaGuru Security" <no-reply@dentaguru.com>',
            to: toEmail,
            subject,
            html,
        });

        const previewUrl = nodemailer.getTestMessageUrl(info);
        if (previewUrl) {
            console.log(`📧 Ethereal Real Email Preview URL: ${previewUrl}`);
        }
        console.log(`✅ Real OTP Email dispatched to [${toEmail}] (MessageID: ${info.messageId})`);
        return { success: true, messageId: info.messageId, previewUrl };
    } catch (err) {
        console.error('❌ Failed to send OTP email via Nodemailer:', err.message);
        return { success: false, error: err.message };
    }
};

module.exports = {
    sendOtpEmail,
};
