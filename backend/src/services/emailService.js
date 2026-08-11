require('dotenv').config();

/**
 * DentaGuru Email Service
 * Email OTP authentication is handled directly by Supabase Auth (Supabase Flutter Client).
 * Nodemailer and Gmail SMTP email OTP dependencies have been removed.
 */
const sendOtpEmail = async (toEmail, otpCode, isPasswordReset = false) => {
    console.log(`ℹ️ Email OTP for [${toEmail}] is managed via Supabase Auth client directly.`);
    return { success: true, message: 'Email OTP handled by Supabase Auth.' };
};

module.exports = {
    sendOtpEmail,
};
