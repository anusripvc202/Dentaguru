require('dotenv').config();
const nodemailer = require('nodemailer');

const getTransporter = async () => {
    const gmailUser = (process.env.GMAIL_USER || 'anusripvc202@gmail.com').trim();
    const gmailPass = (process.env.GMAIL_APP_PASSWORD || 'vxrqzpifcemgshkh').trim();

    return nodemailer.createTransport({
        host: 'smtp.gmail.com',
        port: 465,
        secure: true,
        auth: { user: gmailUser, pass: gmailPass },
        tls: { rejectUnauthorized: false },
        family: 4,
        connectionTimeout: 15000,
        greetingTimeout: 15000,
        socketTimeout: 15000,
    });
};

const sendOtpEmail = async (toEmail, otpCode, isPasswordReset = false) => {
    try {
        const mailTransporter = await getTransporter();
        const senderAddress = (process.env.GMAIL_USER || 'anusripvc202@gmail.com').trim();
        const fromHeader = `"DentaGuru Security" <${senderAddress}>`;
        const subject = isPasswordReset ? `🔑 DentaGuru Password Reset OTP: ${otpCode}` : `📩 DentaGuru Security OTP Verification Code: ${otpCode}`;

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
                    <p style="font-size: 12px; color: #64748b; text-align: center; margin-bottom: 0;">This OTP code is valid for 120 minutes. Please do not share this code with anyone.</p>
                </div>
            </div>
        `;

        const info = await mailTransporter.sendMail({ from: fromHeader, to: toEmail, subject, html });
        console.log(`✅ 4-Digit OTP Email dispatched via Nodemailer to [${toEmail}] (Code: ${otpCode})`);
        return { success: true, messageId: info.messageId, otp: otpCode };
    } catch (err) {
        console.error('❌ Failed to send 4-digit OTP email:', err.message);
        return { success: false, error: err.message };
    }
};

module.exports = { sendOtpEmail };
