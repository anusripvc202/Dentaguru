const jwt = require('jsonwebtoken');
const { User, Dentist, Clinic, comparePassword } = require('../models/Schemas');
const admin = require('firebase-admin');
const { sendOtpEmail } = require('../services/emailService');
const { sendRealSmsOtp } = require('../services/smsService');

const JWT_SECRET = process.env.JWT_SECRET || 'supersecretjwtkey123';
const REFRESH_SECRET = process.env.REFRESH_SECRET || 'supersecretrefreshkey456';

// Helper: Generate JWT tokens
const generateTokens = (user) => {
    const accessToken = jwt.sign(
        { id: user.id, role: user.role },
        JWT_SECRET,
        { expiresIn: '15m' }
    );
    const refreshToken = jwt.sign(
        { id: user.id },
        REFRESH_SECRET,
        { expiresIn: '7d' }
    );
    return { accessToken, refreshToken };
};

// 1. REGISTER
exports.register = async (req, res) => {
    const { name, email, password, phone, role, fcmToken, specialty, licenseNumber, clinicName, clinicAddress, profilePhoto } = req.body;
    try {
        const existingEmail = await User.findOne({ email });
        if (existingEmail) {
            return res.status(400).json({ success: false, message: 'Email already registered.' });
        }

        const existingPhone = await User.findOne({ phone });
        if (existingPhone) {
            return res.status(400).json({ success: false, message: 'Phone number already registered.' });
        }

        const user = await User.create({
            name,
            email,
            password,
            phone,
            role: role || 'Patient',
            device_token: fcmToken || null,
            biometric_token: profilePhoto || null
        });

        // If registering as a Dentist, automatically insert row into 'dentists' and 'clinics' tables
        if (role === 'Dentist' || (role && role.toLowerCase() === 'dentist')) {
            const licNum = (licenseNumber && licenseNumber.trim())
                ? licenseNumber.trim()
                : `DEN-LIC-${Date.now()}-${Math.floor(Math.random() * 1000)}`;

            let clinicId = null;
            const cName = clinicName && clinicName.trim() ? clinicName.trim() : '';
            if (cName.length > 0) {
                try {
                    const cAddr = clinicAddress && clinicAddress.trim() ? clinicAddress.trim() : '';
                    let clinic = await Clinic.findOne({ clinic_name: cName });
                    if (!clinic) {
                        const defaultPricing = req.body.pricing || [
                            { service: 'General Consultation', fee: '$75' },
                            { service: 'Tooth Decay / Cavity', fee: '$85' },
                            { service: 'Root Canal', fee: '$180' },
                            { service: 'Orthodontics', fee: '$200' },
                            { service: 'Tooth Extraction', fee: '$110' },
                            { service: 'Periodontics / Gum Care', fee: '$95' }
                        ];
                        clinic = await Clinic.create({
                            user_id: user.id,
                            clinic_name: cName,
                            location: cAddr,
                            verified: true,
                            rating: 5.0,
                            reviews_count: 0,
                            services: [specialty || 'General Dentistry', 'Root Canal', 'Orthodontics'],
                            pricing: defaultPricing
                        });
                        console.log(`✅ New Clinic record created in 'clinics' table for: ${cName}`);
                    } else {
                        console.log(`ℹ️ Existing Clinic record linked: ${cName}`);
                    }
                    clinicId = clinic ? clinic.id : null;
                } catch (cErr) {
                    console.error('⚠️ Clinic Table Creation Warning:', cErr.message);
                }
            } else {
                console.log(`ℹ️ No clinic name provided for dentist ${user.name}. Leaving clinic_id as NULL.`);
            }

            try {
                await Dentist.create({
                    user_id: user.id,
                    clinic_id: clinicId,
                    speciality: specialty || req.body.speciality || 'General Dentistry',
                    license_number: licNum,
                    availability_status: 'Available',
                    rating: 5.0,
                    reviews_count: 0
                });
                console.log(`✅ Dentist record created in 'dentists' table for user: ${user.name}`);
            } catch (dErr) {
                console.error('⚠️ Dentist Table Creation Warning:', dErr.message);
            }
        }

        const { accessToken, refreshToken } = generateTokens(user);
        await User.findByIdAndUpdate(user.id, {
            refresh_tokens: [refreshToken]
        });

        res.status(201).json({
            success: true,
            message: 'User registered successfully in Supabase PostgreSQL.',
            user: {
                id: user.id,
                name: user.name,
                email: user.email,
                phone: user.phone,
                role: user.role,
                profilePhoto: user.biometric_token
            },
            accessToken,
            refreshToken
        });
    } catch (err) {
        console.error('Registration Error:', err.message);
        res.status(500).json({ success: false, message: 'Server registration error.' });
    }
};

// 2. LOGIN
exports.login = async (req, res) => {
    const { email, password, role, fcmToken } = req.body;
    try {
        let user = await User.findOne({ email });
        if (!user) {
            user = await User.findOne({ phone: email });
        }
        if (!user) {
            return res.status(400).json({ success: false, message: 'Invalid credentials. User not registered.' });
        }

        const isMatch = await comparePassword(password, user.password);
        if (!isMatch) {
            return res.status(400).json({ success: false, message: 'Invalid credentials.' });
        }

        // Enforce Portal Role Matching
        if (role && role.trim().length > 0) {
            const requestedRole = role.trim().toLowerCase();
            const userRole = (user.role || '').trim().toLowerCase();

            const isReqAdmin = requestedRole.includes('admin');
            const isReqDentist = requestedRole.includes('dentist') || requestedRole.includes('doctor');
            const isReqPatient = requestedRole.includes('patient');

            const isUserAdmin = userRole.includes('admin');
            const isUserDentist = userRole.includes('dentist') || userRole.includes('doctor');
            const isUserPatient = userRole.includes('patient');

            let roleMismatch = false;
            if (isReqAdmin && !isUserAdmin) roleMismatch = true;
            if (isReqDentist && !isUserDentist) roleMismatch = true;
            if (isReqPatient && !isUserPatient) roleMismatch = true;

            if (roleMismatch) {
                return res.status(403).json({
                    success: false,
                    message: `Access Denied: This account is registered as a ${user.role}. Please select the ${user.role} tab to sign in.`
                });
            }
        }

        const { accessToken, refreshToken } = generateTokens(user);
        const existingTokens = user.refresh_tokens || [];
        existingTokens.push(refreshToken);

        const updatePayload = { refresh_tokens: existingTokens };
        if (fcmToken) updatePayload.device_token = fcmToken;

        await User.findByIdAndUpdate(user.id, updatePayload);

        res.json({
            success: true,
            user: {
                id: user.id,
                name: user.name,
                email: user.email,
                phone: user.phone,
                role: user.role,
                profilePhoto: user.biometric_token
            },
            accessToken,
            refreshToken
        });
    } catch (err) {
        console.error('Login Error:', err.message);
        res.status(500).json({ success: false, message: 'Server login error.' });
    }
};

// In-memory store for real active OTPs (Key: normalized phone or email, Value: { code, expiresAt })
const activeOtpStore = new Map();

function generateRandomOtp() {
    return Math.floor(1000 + Math.random() * 9000).toString();
}

function normalizeKey(identifier) {
    if (!identifier) return '';
    const str = String(identifier).trim().toLowerCase();
    if (str.includes('@')) return str;
    const digits = str.replace(/\D/g, '');
    return digits.length >= 10 ? digits.slice(-10) : digits;
}

function storeOtp(identifier, code) {
    if (!identifier) return;
    const cleanKey = normalizeKey(identifier);
    if (!cleanKey) return;

    let existing = activeOtpStore.get(cleanKey);
    if (!existing || !Array.isArray(existing.codes)) {
        existing = { codes: [], expiresAt: Date.now() + 120 * 60 * 1000 };
    }
    existing.codes.push(String(code).trim());
    existing.expiresAt = Date.now() + 120 * 60 * 1000; // 120 minutes (2 hours) validity
    activeOtpStore.set(cleanKey, existing);
}

function verifyStoredOtp(identifier, code) {
    if (!code) return false;
    const cleanCode = String(code).trim();

    // 1. Check normalized key entry
    if (identifier) {
        const cleanKey = normalizeKey(identifier);
        const entry = activeOtpStore.get(cleanKey);
        if (entry && Date.now() <= entry.expiresAt && Array.isArray(entry.codes)) {
            if (entry.codes.includes(cleanCode)) {
                return true;
            }
        }
    }

    // 2. Fallback check across all active OTP entries in session
    for (const [_, entry] of activeOtpStore.entries()) {
        if (Date.now() <= entry.expiresAt && Array.isArray(entry.codes)) {
            if (entry.codes.includes(cleanCode)) {
                return true;
            }
        }
    }

    return false;
}

// 3. OTP VERIFICATION SERVICE (Mobile SMS - Email OTP handled directly by Supabase Auth in Flutter app)
exports.requestOTP = async (req, res) => {
    const { phone, email } = req.body;
    try {
        const pNum = phone ? phone.trim() : '';

        if (!pNum) {
            return res.json({
                success: true,
                message: 'Email OTP is managed directly via Supabase Auth.'
            });
        }

        const realOtp = generateRandomOtp();
        storeOtp(pNum, realOtp);

        console.log(`=============================================================`);
        console.log(`🔑 REAL DYNAMIC MOBILE SMS OTP GENERATED FOR [${pNum}]: >>> ${realOtp} <<<`);
        console.log(`=============================================================`);

        // Send Real Mobile SMS via Fast2SMS / Twilio if phone provided
        if (pNum.length >= 10) {
            sendRealSmsOtp(pNum, realOtp).catch(e => console.error('SMS send warning:', e));
        }

        res.json({
            success: true,
            message: `OTP verification code dispatched to mobile ${pNum}. Check your SMS.`,
            otp: realOtp
        });
    } catch (err) {
        res.status(500).json({ success: false, message: 'Failed to request OTP.' });
    }
};

exports.verifyOTP = async (req, res) => {
    const { phone, email, code } = req.body;
    try {
        const pNum = phone ? phone.trim() : '';
        const eMail = email ? email.trim() : '';

        const isValid = pNum ? verifyStoredOtp(pNum, code) : true;

        if (!isValid) {
            return res.status(400).json({ success: false, message: 'Invalid or expired OTP.' });
        }

        const user = (pNum ? await User.findOne({ phone: pNum }) : null) || (eMail ? await User.findOne({ email: eMail }) : null);

        if (user) {
            const { accessToken, refreshToken } = generateTokens(user);
            const existingTokens = user.refresh_tokens || [];
            existingTokens.push(refreshToken);
            await User.findByIdAndUpdate(user.id, { refresh_tokens: existingTokens });

            return res.json({
                success: true,
                message: '4-Digit OTP Verified successfully.',
                user: {
                    id: user.id,
                    name: user.name,
                    email: user.email,
                    role: user.role
                },
                accessToken,
                refreshToken
            });
        }

        res.json({
            success: true,
            verified: true,
            message: '4-Digit OTP Verified successfully.'
        });
    } catch (err) {
        res.status(500).json({ success: false, message: 'Verification failed.' });
    }
};

// 4. FORGOT PASSWORD (Request Reset OTP)
exports.forgotPassword = async (req, res) => {
    const { email, phone } = req.body;
    try {
        const identifier = (email || phone || '').trim();
        if (!identifier) {
            return res.status(400).json({ success: false, message: 'Email address or phone number is required.' });
        }

        let user = await User.findOne({ email: identifier });
        if (!user) {
            user = await User.findOne({ phone: identifier });
        }

        if (!user) {
            return res.status(404).json({ success: false, message: 'No registered account found with that email or phone number.' });
        }

        const realOtp = generateRandomOtp();
        storeOtp(user.email, realOtp);
        storeOtp(user.phone, realOtp);

        console.log(`=============================================================`);
        console.log(`🔑 FORGOT PASSWORD REAL OTP FOR [${user.email || user.phone}]: >>> ${realOtp} <<<`);
        console.log(`=============================================================`);

        if (user.phone && user.phone.length >= 10) {
            sendRealSmsOtp(user.phone, realOtp).catch(e => console.error('Password reset SMS warning:', e));
        }

        if (user.email && user.email.includes('@')) {
            await sendOtpEmail(user.email, realOtp, true).catch(e => console.error('Password reset email warning:', e));
        }

        res.json({
            success: true,
            message: `Password reset 4-digit OTP code sent to ${user.email || user.phone}.`,
            otp: realOtp
        });
    } catch (err) {
        console.error('Forgot Password Error:', err.message);
        res.status(500).json({ success: false, message: 'Server error requesting password reset.' });
    }
};

// 5. RESET PASSWORD (Confirm OTP & Update Password in Supabase DB)
exports.resetPassword = async (req, res) => {
    const { email, phone, code, newPassword } = req.body;
    try {
        const identifier = (email || phone || '').trim();
        if (!identifier) {
            return res.status(400).json({ success: false, message: 'Email address or phone number is required.' });
        }
        if (!newPassword || newPassword.trim().length < 6) {
            return res.status(400).json({ success: false, message: 'New password must be at least 6 characters.' });
        }

        const isValid = verifyStoredOtp(identifier, code) || verifyStoredOtp(email, code) || verifyStoredOtp(phone, code);
        if (!isValid) {
            return res.status(400).json({ success: false, message: 'Invalid or expired reset OTP code.' });
        }

        let user = await User.findOne({ email: identifier });
        if (!user) {
            user = await User.findOne({ phone: identifier });
        }

        if (!user) {
            return res.status(404).json({ success: false, message: 'User account not found.' });
        }

        // Update password in Supabase PostgreSQL
        await User.findByIdAndUpdate(user.id, { password: newPassword.trim() });

        console.log(`✅ Password reset successfully in Supabase DB for user: ${user.email}`);

        res.json({
            success: true,
            message: '🎉 Your password has been reset successfully! You can now log in with your new password.'
        });
    } catch (err) {
        console.error('Reset Password Error:', err.message);
        res.status(500).json({ success: false, message: 'Server error resetting password.' });
    }
};

// 4. REFRESH TOKEN
exports.refreshToken = async (req, res) => {
    const { token } = req.body;
    if (!token) return res.status(401).json({ success: false, message: 'Token required.' });

    try {
        const decoded = jwt.verify(token, REFRESH_SECRET);
        const user = await User.findById(decoded.id);

        if (!user || !(user.refresh_tokens || []).includes(token)) {
            return res.status(403).json({ success: false, message: 'Invalid refresh token.' });
        }

        const newAccessToken = jwt.sign(
            { id: user.id, role: user.role },
            JWT_SECRET,
            { expiresIn: '15m' }
        );

        res.json({
            success: true,
            accessToken: newAccessToken
        });
    } catch (err) {
        res.status(403).json({ success: false, message: 'Invalid or expired refresh token.' });
    }
};

// 5. UPDATE BIOMETRIC TOKEN
exports.saveBiometric = async (req, res) => {
    const { biometricToken } = req.body;
    try {
        await User.findByIdAndUpdate(req.user.id, { biometric_token: biometricToken });
        res.json({ success: true, message: 'Biometric token configured successfully.' });
    } catch (err) {
        res.status(500).json({ success: false, message: 'Failed to configure biometrics.' });
    }
};

// 6. UPDATE FCM DEVICE TOKEN (Firebase Push Notifications)
exports.updateFcmToken = async (req, res) => {
    const { fcmToken } = req.body;
    if (!fcmToken) {
        return res.status(400).json({ success: false, message: 'fcmToken is required.' });
    }
    try {
        await User.findByIdAndUpdate(req.user.id, { device_token: fcmToken });
        res.json({ success: true, message: 'FCM device token updated successfully.' });
    } catch (err) {
        res.status(500).json({ success: false, message: 'Failed to update FCM token.' });
    }
};

// 7. SUPABASE AUTH USER SYNC
exports.supabaseAuthSync = async (req, res) => {
    const { supabaseToken, name, phone, role } = req.body;
    if (!supabaseToken) {
        return res.status(400).json({ success: false, message: 'supabaseToken is required.' });
    }

    try {
        const { data: { user: sbUser }, error } = await supabase.auth.getUser(supabaseToken);
        if (error || !sbUser) {
            return res.status(401).json({ success: false, message: 'Invalid Supabase Auth token.' });
        }

        let dbUser = await User.findOne({ email: sbUser.email });
        if (!dbUser) {
            dbUser = await User.create({
                name: name || sbUser.user_metadata?.full_name || sbUser.email.split('@')[0],
                email: sbUser.email,
                password: `sb_${sbUser.id.substring(0, 12)}`,
                phone: phone || sbUser.phone || `+1000${Math.floor(1000000 + Math.random() * 9000000)}`,
                role: role || sbUser.user_metadata?.role || 'Patient'
            });
        }

        const { accessToken, refreshToken } = generateTokens(dbUser);
        const existingTokens = dbUser.refresh_tokens || [];
        existingTokens.push(refreshToken);
        await User.findByIdAndUpdate(dbUser.id, { refresh_tokens: existingTokens });

        res.json({
            success: true,
            message: 'Supabase identity synced successfully.',
            user: {
                id: dbUser.id,
                name: dbUser.name,
                email: dbUser.email,
                role: dbUser.role,
                phone: dbUser.phone
            },
            accessToken,
            refreshToken
        });
    } catch (err) {
        console.error('Supabase Auth Sync Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to sync Supabase Auth identity.' });
    }
};

// 8. RESET ALL DATABASE TABLES
exports.resetDatabase = async (req, res) => {
    try {
        const tables = ['chat_messages', 'medical_records', 'appointments', 'dentists', 'clinics', 'users'];
        for (const tbl of tables) {
            await supabaseAdmin.from(tbl).delete().neq('id', '00000000-0000-0000-0000-000000000000');
        }

        res.json({
            success: true,
            message: 'All Supabase PostgreSQL database tables reset successfully.'
        });
    } catch (err) {
        console.error('Reset Database Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to reset database tables.' });
    }
};
