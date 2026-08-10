const nodemailer = require('nodemailer');

// Configure Transporter from Environment Variables or Ethereal fallback
let transporter;

const getTransporter = async () => {
    const gmailUser = (process.env.GMAIL_USER || '').trim();
    const gmailPass = (process.env.GMAIL_APP_PASSWORD || '').trim();

    if (gmailUser && gmailPass) {
        return nodemailer.createTransport({
            service: 'gmail',
            auth: {
                user: gmailUser,
                pass: gmailPass,
            },
            tls: {
                rejectUnauthorized: false
            },
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

    // Nodemailer Direct Email Dispatch
    try {
        const mailTransporter = await getTransporter();
        if (!mailTransporter) return { success: false, reason: 'No transporter' };

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
