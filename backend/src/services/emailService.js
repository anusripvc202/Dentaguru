require('dotenv').config();

/**
 * DentaGuru Email Service
 * 
 * Email OTP Authentication is handled exclusively by Supabase Auth (Supabase Client in Flutter app),
 * with email delivery routed through Resend Custom SMTP.
 * 
 * Nodemailer, Gmail SMTP, and in-memory email OTP generation have been completely removed.
 */
const sendOtpEmail = async (toEmail, otpCode, isPasswordReset = false) => {
    console.log(`ℹ️ Email OTP for [${toEmail}] is managed exclusively by Supabase Auth with Resend Custom SMTP.`);
    return { success: true, message: 'Email OTP handled by Supabase Auth.' };
};

module.exports = {
    sendOtpEmail,
};
