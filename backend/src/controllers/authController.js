const crypto = require('crypto');
const jwt = require('jsonwebtoken');
const { User, Dentist, Clinic, Referral, comparePassword, getDefaultQualificationForSpecialty } = require('../models/Schemas');
const admin = require('firebase-admin');
const { sendOtpEmail } = require('../services/emailService');
const { sendRealSmsOtp, normalizePhoneNumber } = require('../services/smsService');

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

// Normalize 10-digit mobile phone
const normalizeAdminPhone = (phone) => {
    if (!phone) return '';
    const digits = phone.toString().replace(/[^0-9]/g, '');
    if (digits.length === 12 && digits.startsWith('91')) return digits.substring(2);
    if (digits.length === 11 && digits.startsWith('0')) return digits.substring(1);
    if (digits.length > 10) return digits.slice(-10);
    return digits;
};

// Single authorized Admin phone number configuration (Environment or Database)
const getAuthorizedAdminPhone = async () => {
    // 1. Backend environment variable configuration
    const envAdminPhone = (process.env.ADMIN_PHONE || process.env.ADMIN_MOBILE_NUMBER || '').trim();
    if (envAdminPhone) {
        return normalizeAdminPhone(envAdminPhone);
    }
    // 2. Existing secure admin account record in database
    try {
        const adminUser = await User.findOne({ role: 'Admin' });
        if (adminUser && adminUser.phone) {
            return normalizeAdminPhone(adminUser.phone);
        }
    } catch (_) {}
    return null;
};

// 1. REGISTER
exports.register = async (req, res) => {
    const { name, email, password, phone, role, fcmToken, specialty, licenseNumber, clinicName, clinicAddress, location, state, city, pincode, latitude, longitude, qualification, experienceYears, profilePhoto, age, gender, bloodGroup, emergencyContact, languages, languagesKnown, referralCode, ref } = req.body;
    try {
        const normalizedRole = (role || 'Patient').toString().trim();
        const normalizedPhone = (phone || '').toString().trim();
        const normalizedEmail = (email || '').toString().trim().toLowerCase();

        // 1. Mobile Phone Number is Mandatory Primary Identifier
        if (!normalizedPhone) {
            return res.status(400).json({
                success: false,
                message: 'Mobile phone number is mandatory for registration.'
            });
        }

        const isSubAdmin = normalizedRole.toLowerCase() === 'sub-admin' || normalizedRole.toLowerCase() === 'subadmin' || normalizedRole.toLowerCase() === 'sub_admin';
        const isAdminReg = normalizedRole.toLowerCase() === 'admin' || normalizedRole.toLowerCase() === 'primaryadmin' || normalizedRole.toLowerCase() === 'primary_admin';

        // Public self-registration as Admin or Sub-Admin is strictly disabled
        if (isAdminReg || isSubAdmin) {
            return res.status(403).json({
                success: false,
                message: 'Public registration as Admin is disabled. Unauthorized role registration rejected.'
            });
        }

        let effectiveAssignedRole = normalizedRole;

        const cleanPhoneDigits = normalizedPhone.replace(/[^0-9]/g, '') || Math.floor(100000 + Math.random() * 900000).toString();
        const effectiveEmail = (normalizedEmail && normalizedEmail.includes('@') && !normalizedEmail.endsWith('@dentaguru.internal'))
            ? normalizedEmail
            : `user_${cleanPhoneDigits}@dentaguru.internal`;

        // Email uniqueness check only if real user-provided email
        if (normalizedEmail.length > 0 && !normalizedEmail.endsWith('@dentaguru.internal')) {
            const existingEmail = await User.findOne({ email: normalizedEmail });
            if (existingEmail && existingEmail.phone !== normalizedPhone) {
                return res.status(400).json({ success: false, message: 'Email already registered.' });
            }
        }

        // Phone uniqueness check
        const existingPhone = await User.findOne({ phone: normalizedPhone });
        if (existingPhone) {
            return res.status(400).json({ success: false, message: 'Phone number already registered. Please sign in with OTP.' });
        }

        // 2. Mandatory Fields Validation: City, Pincode
        const normalizedCity = (city || '').toString().trim();
        const normalizedPincode = (pincode || '').toString().trim();
        const normalizedLocation = (location || clinicAddress || state || '').toString().trim();
        const rawLanguages = languages || languagesKnown;
        let cleanLanguages = [];
        if (Array.isArray(rawLanguages)) {
            cleanLanguages = rawLanguages.map(l => (l || '').toString().trim()).filter(Boolean);
        } else if (typeof rawLanguages === 'string' && rawLanguages.trim().length > 0) {
            cleanLanguages = rawLanguages.split(',').map(s => s.trim()).filter(Boolean);
        }

        if (!normalizedCity) {
            return res.status(400).json({ success: false, message: 'City is mandatory for registration.' });
        }
        if (!normalizedPincode) {
            return res.status(400).json({ success: false, message: 'Pincode is mandatory for registration.' });
        }

        // Generate unique referral code for this user
        const cleanNamePrefix = (name || 'PAT').replace(/[^a-zA-Z]/g, '').substring(0, 3).toUpperCase() || 'DEN';
        const userReferralCode = `DG-${cleanNamePrefix}${normalizedPhone ? normalizedPhone.slice(-4) : Math.floor(1000 + Math.random() * 9000)}`;

        // Passwordless support: if password omitted, generate secure internal hash
        const effectivePassword = (password && password.trim().length >= 4)
            ? password.trim()
            : (`OTP_SECURE_${require('crypto').randomBytes(12).toString('hex')}`);

        const finalLanguages = cleanLanguages.length > 0 ? cleanLanguages : ['English'];

        const isDoctorReg = normalizedRole.toLowerCase() === 'dentist' || normalizedRole.toLowerCase() === 'doctor';
        if (isDoctorReg) {
            effectiveAssignedRole = 'Dentist';
        }
        const resolvedDocSpecialty = specialty || req.body.speciality || 'General Dentistry';
        const resolvedDocQualification = qualification || req.body.qualifications || getDefaultQualificationForSpecialty(resolvedDocSpecialty);
        const resolvedDocExp = experienceYears ? parseInt(experienceYears, 10) : 5;

        let user;
        const profileMetaObj = {
            age: age || '',
            gender: gender || '',
            bloodGroup: bloodGroup || '',
            emergencyContact: emergencyContact || '',
            city: normalizedCity,
            pincode: normalizedPincode,
            location: normalizedLocation,
            address: normalizedLocation,
            languages: finalLanguages,
            referral_code: userReferralCode,
            ...(isDoctorReg ? {
                specialty: resolvedDocSpecialty,
                qualification: resolvedDocQualification,
                experienceYears: resolvedDocExp,
                clinicName: clinicName || '',
                licenseNumber: licenseNumber || ''
            } : {})
        };
        const metaDeviceToken = fcmToken || JSON.stringify(profileMetaObj);

        try {
            user = await User.create({
                name: name || (isDoctorReg ? 'Dr. Specialist' : (effectiveAssignedRole === 'Sub-Admin' ? 'Sub-Admin' : 'Patient')),
                email: effectiveEmail,
                password: effectivePassword,
                phone: normalizedPhone,
                role: effectiveAssignedRole,
                state: normalizedLocation,
                city: normalizedCity,
                pincode: normalizedPincode,
                age: age || '',
                gender: gender || '',
                blood_group: bloodGroup || '',
                emergency_contact: emergencyContact || '',
                languages: finalLanguages,
                referral_code: userReferralCode,
                latitude: latitude || null,
                longitude: longitude || null,
                device_token: metaDeviceToken,
                biometric_token: profilePhoto || null
            });
        } catch (createErr) {
            // Schema fallback: if DB table lacks age/gender/blood_group/languages columns
            user = await User.create({
                name: name || (isDoctorReg ? 'Dr. Specialist' : (effectiveAssignedRole === 'Sub-Admin' ? 'Sub-Admin' : 'Patient')),
                email: effectiveEmail,
                password: effectivePassword,
                phone: normalizedPhone,
                role: effectiveAssignedRole,
                state: state || '',
                city: city || '',
                pincode: pincode || '',
                latitude: latitude || null,
                longitude: longitude || null,
                device_token: metaDeviceToken,
                biometric_token: profilePhoto || null
            });
        }

        // Assign default RBAC permissions for Sub-Admin
        if (effectiveAssignedRole === 'Sub-Admin' || isSubAdmin) {
            try {
                const { SubAdminPermission } = require('../models/Schemas');
                await SubAdminPermission.setPermissionsForUser(user.id, [
                    'ALL',
                    'MANAGE_PATIENTS',
                    'MANAGE_REQUESTS',
                    'VIEW_DENTISTS',
                    'MANAGE_CLINICS',
                    'MANAGE_REFERRALS',
                    'VIEW_RECORDS',
                    'APPOINTMENTS'
                ]);
            } catch (subErr) {
                console.warn('⚠️ Sub-Admin permission assignment warning:', subErr.message);
            }
        }

        // 3. Referral Tracking & Attribution
        const incomingReferralCode = (referralCode || ref || req.body.referral_code || '').toString().trim().toUpperCase();
        if (incomingReferralCode) {
            try {
                const allUsers = await User.find();
                const referrer = allUsers.find(u => {
                    const uRef = (u.referral_code || (u.device_token && u.device_token.startsWith('{') ? JSON.parse(u.device_token).referral_code : '')) || `DG-${(u.name || 'USER').substring(0, 3).toUpperCase()}${u.phone ? u.phone.slice(-4) : ''}`;
                    return (uRef && uRef.toUpperCase() === incomingReferralCode) || (u.phone && u.phone.trim() === incomingReferralCode) || u.id === incomingReferralCode;
                });

                if (referrer) {
                    const isSelfReferral = referrer.id === user.id ||
                        (referrer.phone && user.phone && referrer.phone.trim() === user.phone.trim()) ||
                        (referrer.email && user.email && referrer.email.trim().toLowerCase() === user.email.trim().toLowerCase());

                    if (!isSelfReferral) {
                        await Referral.create({
                            referrer_id: referrer.id,
                            referred_user_id: user.id,
                            referral_code: incomingReferralCode,
                            status: 'REGISTERED'
                        });
                        console.log(`🎉 Referral attributed: User ${user.name} referred by ${referrer.name} (Code: ${incomingReferralCode})`);
                    } else {
                        console.warn('⚠️ Self-referral prevented during registration.');
                    }
                }
            } catch (refErr) {
                console.warn('⚠️ Referral attribution warning:', refErr.message);
            }
        }

        // If registering as a Dentist / Doctor, automatically insert row into 'dentists' and 'clinics' tables
        if (isDoctorReg) {
            const licNum = (licenseNumber && licenseNumber.trim())
                ? licenseNumber.trim()
                : `MED-LIC-${Date.now()}-${Math.floor(Math.random() * 1000)}`;

            // Duplicate License Number check
            const existingLic = await Dentist.findOne({ license_number: licNum });
            if (existingLic) {
                console.warn(`⚠️ License number ${licNum} already exists.`);
            }

            let clinicId = null;
            const cName = clinicName && clinicName.trim() ? clinicName.trim() : '';
            if (cName.length > 0) {
                try {
                    const cAddr = (clinicAddress && clinicAddress.trim()) ? clinicAddress.trim() : (location && location.trim() ? location.trim() : '');
                    const cPin = pincode && pincode.trim() ? pincode.trim() : '';
                    const fullLoc = cPin ? `${cAddr} - ${cPin}` : cAddr;
                    let clinic = await Clinic.findOne({ clinic_name: cName });
                    if (!clinic) {
                        const defaultPricing = req.body.pricing || [
                            { service: 'General Consultation', fee: '$75' },
                            { service: `${resolvedDocSpecialty} Evaluation`, fee: '$90' },
                            { service: 'Follow-up Consultation', fee: '$60' }
                        ];
                        clinic = await Clinic.create({
                            user_id: user.id,
                            clinic_name: cName,
                            location: fullLoc,
                            verified: true,
                            rating: 5.0,
                            reviews_count: 0,
                            services: [resolvedDocSpecialty, 'General Consultation'],
                            pricing: defaultPricing
                        });
                        console.log(`✅ New Clinic record created in 'clinics' table for: ${cName}`);
                    } else {
                        // Ensure the doctor's specialty is added to the clinic's services if not already present
                        const currentServices = Array.isArray(clinic.services) ? [...clinic.services] : [];
                        if (resolvedDocSpecialty && !currentServices.includes(resolvedDocSpecialty)) {
                            currentServices.push(resolvedDocSpecialty);
                            await Clinic.findByIdAndUpdate(clinic.id, { services: currentServices });
                        }
                        console.log(`ℹ️ Existing Clinic record linked: ${cName}`);
                    }
                    clinicId = clinic ? clinic.id : null;
                } catch (cErr) {
                    console.error('⚠️ Clinic Table Creation Warning:', cErr.message);
                }
            } else {
                console.log(`ℹ️ No clinic name provided for doctor ${user.name}. Leaving clinic_id as NULL.`);
            }

            try {
                await Dentist.create({
                    user_id: user.id,
                    clinic_id: clinicId,
                    speciality: resolvedDocSpecialty,
                    license_number: licNum,
                    experience_years: resolvedDocExp,
                    qualifications: resolvedDocQualification,
                    availability_status: 'Available',
                    state: normalizedLocation,
                    city: normalizedCity,
                    pincode: normalizedPincode,
                    languages: finalLanguages,
                    latitude: latitude || null,
                    longitude: longitude || null,
                    rating: 5.0,
                    reviews_count: 0
                });
                console.log(`✅ Doctor record created in 'dentists' table for user: ${user.name}`);
            } catch (dErr) {
                console.error('⚠️ Doctor Table Creation Warning:', dErr.message);
            }
        }

        const { accessToken, refreshToken } = generateTokens(user);
        const existingTokens = Array.isArray(user.refresh_tokens) ? user.refresh_tokens : [];
        if (!existingTokens.includes(refreshToken)) existingTokens.push(refreshToken);
        await User.findByIdAndUpdate(user.id, {
            refresh_tokens: existingTokens.slice(-20)
        });

        // Also sync user_metadata to Supabase Auth for permanent cloud persistence
        try {
            await supabaseAdmin.auth.admin.updateUserById(user.id, {
                user_metadata: {
                    name,
                    role: effectiveAssignedRole,
                    phone,
                    age: age || '',
                    gender: gender || '',
                    bloodGroup: bloodGroup || '',
                    emergencyContact: emergencyContact || '',
                    city: city || '',
                    pincode: pincode || '',
                    state: state || '',
                    languages: finalLanguages,
                    referral_code: userReferralCode,
                    ...(isDoctorReg ? {
                        specialty: resolvedDocSpecialty,
                        qualification: resolvedDocQualification,
                        experienceYears: resolvedDocExp,
                        clinicName: clinicName || ''
                    } : {})
                }
            });
        } catch (_) {}

        res.status(201).json({
            success: true,
            message: 'User registered successfully in Supabase PostgreSQL.',
            user: {
                id: user.id,
                name: user.name,
                email: user.email,
                phone: user.phone,
                role: user.role,
                age: age || user.age || '',
                gender: gender || user.gender || '',
                bloodGroup: bloodGroup || user.blood_group || '',
                emergencyContact: emergencyContact || user.emergency_contact || '',
                city: user.city || '',
                pincode: user.pincode || '',
                languages: finalLanguages,
                referralCode: userReferralCode,
                profilePhoto: user.biometric_token,
                ...(isDoctorReg ? {
                    specialty: resolvedDocSpecialty,
                    qualification: resolvedDocQualification,
                    experienceYears: resolvedDocExp,
                    clinicName: clinicName || '',
                    licenseNumber: licenseNumber || ''
                } : {})
            },
            accessToken,
            refreshToken
        });
    } catch (err) {
        console.error('Registration Error:', err.message);
        res.status(500).json({ success: false, message: err.message || 'Server registration error.' });
    }
};

// 2. LOGIN
exports.login = async (req, res) => {
    const { email, phone, password, otp, code, role, fcmToken } = req.body;
    try {
        const rawIdentifier = (phone || email || '').toString().trim();
        let identifier = rawIdentifier;
        if (rawIdentifier && !rawIdentifier.includes('@') && /^[+\d\s\-()]+$/.test(rawIdentifier)) {
            const digits = rawIdentifier.replace(/[^0-9]/g, '');
            if (digits.length === 12 && digits.startsWith('91')) {
                identifier = digits.substring(2);
            } else if (digits.length === 11 && digits.startsWith('0')) {
                identifier = digits.substring(1);
            } else if (digits.length > 0) {
                identifier = digits;
            }
        }
        const otpCode = (otp || code || '').toString().trim();

        if (!identifier) {
            return res.status(400).json({ success: false, message: 'Please provide your registered mobile number or email address.' });
        }

        let user = null;
        if (identifier.includes('@')) {
            user = await User.findOne({ email: identifier.toLowerCase() });
            if (!user && identifier !== identifier.toLowerCase()) {
                user = await User.findOne({ email: identifier });
            }
        } else {
            user = await User.findOne({ phone: identifier });
            if (!user && rawIdentifier !== identifier) {
                user = await User.findOne({ phone: rawIdentifier });
            }
            if (!user) {
                user = await User.findOne({ email: identifier.toLowerCase() });
            }
        }
        if (!user) {
            return res.status(400).json({ success: false, message: 'Invalid credentials. User not registered.' });
        }

        // 1. Passwordless Mobile OTP Login Verification (if provided)
        if (otpCode.length >= 4) {
            const otpCheck = verifyStoredOtp(identifier, otpCode).valid ||
                             (user.phone && verifyStoredOtp(user.phone, otpCode).valid) ||
                             (user.email && verifyStoredOtp(user.email, otpCode).valid);
            if (!otpCheck) {
                return res.status(400).json({ success: false, message: 'Invalid or expired OTP. Please request a new OTP.' });
            }
        } else if (password) {
            // 2. Password Login Verification (if password provided)
            const isMatch = await comparePassword(password, user.password);
            if (!isMatch) {
                return res.status(400).json({ success: false, message: 'Invalid credentials.' });
            }
        }
        // Direct registered mobile / email sign in permitted without requiring OTP code

        const userRoleStr = (user.role || '').toString().trim().toLowerCase();
        const isSubAdminUser = userRoleStr === 'sub-admin' || userRoleStr === 'subadmin' || userRoleStr === 'sub_admin';

        let tokenMeta = {};
        if (user.device_token && typeof user.device_token === 'string' && user.device_token.startsWith('{')) {
            try {
                tokenMeta = JSON.parse(user.device_token);
            } catch (_) {}
        }

        const effectiveStatus = (user.status || tokenMeta.status || 'ACTIVE').toString().toUpperCase();

        // Check active status for Sub-Admins
        if (isSubAdminUser && (effectiveStatus === 'INACTIVE' || effectiveStatus === 'DEACTIVATED')) {
            return res.status(403).json({
                success: false,
                message: 'Access Denied: Your Sub-Admin account has been deactivated by the Main Admin. Please contact the administrator.'
            });
        }

        // Enforce Portal Role Matching and Strict Admin Number Verification
        const requestedRole = (role || '').trim().toLowerCase();
        const userRole = (user.role || '').trim().toLowerCase();
        const isReqAdmin = requestedRole.includes('admin');
        const isUserAdmin = userRole.includes('admin');

        const authorizedAdminPhone = await getAuthorizedAdminPhone();
        const normalizedIdentifier = normalizeAdminPhone(identifier);
        const isAuthorizedAdmin = Boolean(authorizedAdminPhone && (normalizedIdentifier === authorizedAdminPhone || normalizeAdminPhone(user.phone) === authorizedAdminPhone));

        if (isReqAdmin && !isAuthorizedAdmin) {
            return res.status(403).json({
                success: false,
                message: 'Unauthorized Admin access: This mobile number is not authorized as Admin.'
            });
        }
        if (isUserAdmin && !isAuthorizedAdmin) {
            return res.status(403).json({
                success: false,
                message: 'Unauthorized Admin access: Mobile number does not match authorized administrator.'
            });
        }

        if (role && role.trim().length > 0) {
            const isReqDentist = requestedRole.includes('dentist') || requestedRole.includes('doctor');
            const isReqPatient = requestedRole.includes('patient');

            const isUserDentist = userRole.includes('dentist') || userRole.includes('doctor');
            const isUserPatient = userRole.includes('patient');

            if (isReqAdmin && !isUserAdmin) {
                return res.status(403).json({ success: false, message: `Role Mismatch: Your account is registered as '${user.role}'. Cannot log into Admin Portal.` });
            }
            if (isReqDentist && !isUserDentist) {
                return res.status(403).json({ success: false, message: `Role Mismatch: Your account is registered as '${user.role}'. Cannot log into Doctor Portal.` });
            }
            if (isReqPatient && !isUserPatient) {
                return res.status(403).json({ success: false, message: `Role Mismatch: Your account is registered as '${user.role}'. Cannot log into Patient Portal.` });
            }
        }

        if (fcmToken) {
            User.findByIdAndUpdate(user.id, { device_token: fcmToken }).catch(() => {});
        }

        const userAge = user.age || user.patient_age || tokenMeta.age || '';
        const userGender = user.gender || tokenMeta.gender || '';
        const userBloodGroup = user.blood_group || user.bloodGroup || tokenMeta.bloodGroup || '';
        const userEmergency = user.emergency_contact || user.emergencyContact || tokenMeta.emergencyContact || '';

        let userPermissions = (Array.isArray(user.permissions) && user.permissions.length > 0)
            ? user.permissions
            : (Array.isArray(tokenMeta.permissions) ? tokenMeta.permissions : []);
        if (isSubAdminUser && (!userPermissions || userPermissions.length === 0)) {
            const { SubAdminPermission } = require('../models/Schemas');
            userPermissions = await SubAdminPermission.getPermissionsForUser(user.id);
        }

        const { accessToken, refreshToken } = generateTokens(user);
        const existingTokens = Array.isArray(user.refresh_tokens) ? user.refresh_tokens : [];
        if (!existingTokens.includes(refreshToken)) existingTokens.push(refreshToken);
        User.findByIdAndUpdate(user.id, {
            refresh_tokens: existingTokens.slice(-20)
        }).catch(() => {});

        const userLanguages = (Array.isArray(user.languages) && user.languages.length > 0)
            ? user.languages
            : (Array.isArray(tokenMeta.languages) && tokenMeta.languages.length > 0 ? tokenMeta.languages : ['English']);

        let doctorExtra = {};
        if (userRoleStr.includes('dentist') || userRoleStr.includes('doctor')) {
            try {
                const docRec = await Dentist.findById(user.id);
                const resolvedSpec = docRec?.speciality || docRec?.specialty || tokenMeta.specialty || 'General Dentistry';
                doctorExtra = {
                    specialty: resolvedSpec,
                    qualification: docRec?.qualifications || docRec?.qualification || tokenMeta.qualification || getDefaultQualificationForSpecialty(resolvedSpec),
                    experienceYears: docRec?.experience_years || docRec?.experienceYears || tokenMeta.experienceYears || 5,
                    clinicName: docRec?.clinics?.clinic_name || docRec?.clinicName || tokenMeta.clinicName || '',
                    licenseNumber: docRec?.license_number || docRec?.licenseNumber || tokenMeta.licenseNumber || 'MED-LIC-REG',
                    verificationStatus: docRec?.verification_status || 'VERIFIED'
                };
            } catch (_) {}
        }

        res.json({
            success: true,
            message: 'Login successful.',
            accessToken,
            refreshToken,
            user: {
                id: user.id,
                name: user.name,
                email: user.email,
                phone: user.phone,
                role: user.role,
                status: effectiveStatus,
                permissions: userPermissions,
                age: userAge,
                gender: userGender,
                bloodGroup: userBloodGroup,
                emergencyContact: userEmergency,
                city: user.city || tokenMeta.city || '',
                pincode: user.pincode || tokenMeta.pincode || '',
                languages: userLanguages,
                profilePhoto: user.biometric_token,
                ...doctorExtra
            }
        });
    } catch (err) {
        console.error('Login Error:', err.message);
        res.status(500).json({ success: false, message: 'Server login error.' });
    }
};

// 5. FORGOT PASSWORD
exports.forgotPassword = async (req, res) => {
    const { email } = req.body;
    try {
        const user = await User.findOne({ email });
        if (!user) {
            return res.status(404).json({ success: false, message: 'User with specified email not found.' });
        }

        const otpCode = Math.floor(1000 + Math.random() * 9000).toString();
        await sendOtpEmail(email, otpCode);

        res.json({
            success: true,
            message: 'Password reset OTP sent to your email.',
            otp: otpCode
        });
    } catch (err) {
        res.status(500).json({ success: false, message: 'Error processing forgot password request.' });
    }
};

// 6. RESET PASSWORD
exports.resetPassword = async (req, res) => {
    const { email, newPassword } = req.body;
    try {
        const user = await User.findOne({ email });
        if (!user) {
            return res.status(404).json({ success: false, message: 'User not found.' });
        }

        await User.findByIdAndUpdate(user.id, { password: newPassword });

        res.json({ success: true, message: 'Password updated successfully.' });
    } catch (err) {
        res.status(500).json({ success: false, message: 'Failed to reset password.' });
    }
};

// 7. REFRESH TOKEN
exports.refreshToken = async (req, res) => {
    const { refreshToken } = req.body;
    if (!refreshToken) {
        return res.status(401).json({ success: false, message: 'Refresh Token Required.' });
    }

    try {
        const decoded = jwt.verify(refreshToken, REFRESH_SECRET);
        const user = await User.findById(decoded.id);
        if (!user) {
            return res.status(403).json({ success: false, message: 'User account not found.' });
        }

        const { accessToken, refreshToken: newRefreshToken } = generateTokens(user);
        res.json({ success: true, accessToken, refreshToken: newRefreshToken });
    } catch (err) {
        res.status(403).json({ success: false, message: 'Invalid or expired refresh token.' });
    }
};

// 8. RESET DATABASE
exports.resetDatabase = async (req, res) => {
    try {
        const { supabaseAdmin } = require('../config/supabase');
        const tables = ['chat_messages', 'medical_records', 'dentist_suggestions', 'appointments', 'patient_problem_requests', 'dentists', 'clinics', 'notifications', 'users'];
        for (const tbl of tables) {
            await supabaseAdmin.from(tbl).delete().neq('id', '00000000-0000-0000-0000-000000000000');
        }
        res.json({ success: true, message: 'All database tables reset successfully.' });
    } catch (err) {
        res.status(500).json({ success: false, message: 'Failed to reset database.' });
    }
};

// 9. GET ALL PATIENTS / USERS FROM SUPABASE DB
exports.getPatients = async (req, res) => {
    try {
        // Fetch admin emails to strictly exclude admin accounts from patient list
        const adminUsers = await User.find({ role: { $in: ['Admin', 'Sub-Admin'] } });
        const adminEmails = new Set(adminUsers.map(u => (u.email || '').trim().toLowerCase()));

        const dbPatients = await User.find({ role: 'Patient' });
        const patientMap = new Map();

        for (const p of dbPatients) {
            const pEmail = (p.email || '').trim().toLowerCase();
            if (adminEmails.has(pEmail) || (p.role && p.role.toLowerCase().includes('admin')) || (p.name && p.name.trim().toLowerCase() === 'anusri')) {
                continue;
            }
            const pName = p.name && p.name.trim().length > 0
                ? p.name.trim()
                : (p.email ? p.email.split('@')[0] : 'Patient');

            let userLanguages = p.languages || ['English'];
            if (p.device_token && typeof p.device_token === 'string' && p.device_token.startsWith('{')) {
                try {
                    const meta = JSON.parse(p.device_token);
                    if (meta.languages && Array.isArray(meta.languages) && meta.languages.length > 0) {
                        userLanguages = meta.languages;
                    }
                } catch (_) {}
            }

            patientMap.set(p.id, {
                id: p.id,
                name: pName,
                email: p.email || '',
                phone: p.phone || '',
                role: 'Patient',
                state: p.state || '',
                city: p.city || '',
                pincode: p.pincode || '',
                address: p.address || p.location || '',
                languages: userLanguages,
                profilePhoto: p.biometric_token || null,
                created_at: p.created_at
            });
        }

        // Merge patients from consultation requests to ensure zero data omission
        try {
            const reqs = await PatientProblemRequest.find({});
            for (const r of reqs) {
                const pId = r.patient_id || r.patient?.id || r.id;
                const pName = r.patient?.name || r.patientName || (r.patientEmail ? r.patientEmail.split('@')[0] : 'Patient');
                const pEmail = (r.patient?.email || r.patientEmail || '').trim().toLowerCase();
                const pPhone = r.patient?.phone || r.patientPhone || '';

                if (adminEmails.has(pEmail) || (pName && pName.trim().toLowerCase() === 'anusri')) {
                    continue; // Skip admin accounts
                }

                if (pId && !patientMap.has(pId)) {
                    patientMap.set(pId, {
                        id: pId,
                        name: pName,
                        email: pEmail,
                        phone: pPhone,
                        role: 'Patient',
                        state: r.state || '',
                        city: r.city || '',
                        pincode: r.pincode || '',
                        address: r.preferred_location || '',
                        languages: ['English'],
                        profilePhoto: null,
                        created_at: r.created_at
                    });
                }
            }
        } catch (_) {}

        const resultList = Array.from(patientMap.values());
        res.json({ success: true, count: resultList.length, patients: resultList });
    } catch (err) {
        console.error('Get Patients Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to fetch patients.' });
    }
};

// 10. CREATE SUB-ADMIN (Primary Admin only)
exports.createSubAdmin = async (req, res) => {
    const { name, email, password, phone, permissions, status, city, pincode, languages, districtIds, districts } = req.body;
    try {
        const { SubAdminDistrict, PermissionChangeHistory } = require('../models/Schemas');
        const normalizedPhone = (phone || '').toString().trim();
        const normalizedEmail = (email || '').toString().trim().toLowerCase();

        if (!normalizedPhone) {
            return res.status(400).json({ success: false, message: 'Mobile phone number is mandatory for Sub-Admin registration.' });
        }

        if (normalizedEmail.length > 0) {
            const existingUser = await User.findOne({ email: normalizedEmail });
            if (existingUser) {
                return res.status(400).json({ success: false, message: 'An account with this email already exists.' });
            }
        }

        const existingPhone = await User.findOne({ phone: normalizedPhone });
        if (existingPhone) {
            return res.status(400).json({ success: false, message: 'Phone number already registered.' });
        }

        // Sub-admin permissions default to RESTRICTED per system requirements
        const cleanPerms = Array.isArray(permissions) && permissions.length > 0
            ? permissions.map(p => (p || '').toString().trim().toUpperCase()).filter(p => p.length > 0)
            : ['PATIENT_VIEW']; // Restricted default

        const subAdminStatus = (status || 'ACTIVE').toString().trim().toUpperCase();

        const rawLanguages = languages || ['English'];
        const cleanLanguages = Array.isArray(rawLanguages)
            ? rawLanguages.map(l => (l || '').toString().trim()).filter(Boolean)
            : (typeof rawLanguages === 'string' ? rawLanguages.split(',').map(s => s.trim()).filter(Boolean) : ['English']);
        const finalLanguages = cleanLanguages.length > 0 ? cleanLanguages : ['English'];

        const effectivePassword = (password && password.trim().length >= 4)
            ? password.trim()
            : (`OTP_SUBADMIN_${require('crypto').randomBytes(12).toString('hex')}`);

        const metaObj = {
            city: city || '',
            pincode: pincode || '',
            languages: finalLanguages,
            status: subAdminStatus,
            permissions: cleanPerms
        };

        const subAdmin = await User.create({
            name: name || 'Sub-Admin',
            email: normalizedEmail,
            password: effectivePassword,
            phone: normalizedPhone,
            role: 'Sub-Admin',
            status: subAdminStatus,
            city: city || '',
            pincode: pincode || '',
            languages: finalLanguages,
            permissions: cleanPerms,
            device_token: JSON.stringify(metaObj)
        });

        // Assign multiple districts if specified
        const finalDistrictIds = Array.isArray(districtIds) ? districtIds : (Array.isArray(districts) ? districts : []);
        let assignedDistricts = [];
        if (finalDistrictIds.length > 0) {
            assignedDistricts = await SubAdminDistrict.assignDistrictsToSubAdmin(
                subAdmin.id,
                finalDistrictIds,
                req.user ? req.user.id : null
            );
        }

        // Log permission initialization to PermissionChangeHistory
        try {
            for (const p of cleanPerms) {
                await PermissionChangeHistory.logChange({
                    subAdminUserId: subAdmin.id,
                    changedByUserId: req.user ? req.user.id : null,
                    changedByRole: 'Main Admin',
                    action: 'INITIAL_RESTRICTED',
                    permissionKey: p,
                    previousState: false,
                    newState: true,
                    reason: 'Initial permission granted on Sub-Admin creation.'
                });
            }
        } catch (_) {}

        // Also ensure Supabase Auth User exists for Sub-Admin if email provided
        if (normalizedEmail) {
            try {
                await supabaseAdmin.auth.admin.createUser({
                    email: normalizedEmail,
                    password: effectivePassword,
                    email_confirm: true,
                    user_metadata: {
                        name: subAdmin.name,
                        role: 'Sub-Admin',
                        status: subAdminStatus,
                        permissions: cleanPerms,
                        phone: normalizedPhone
                    }
                });
            } catch (sbErr) {
                console.log('Notice: Sub-Admin Supabase auth auto-create notice:', sbErr.message);
            }
        }

        res.status(201).json({
            success: true,
            message: 'Sub-Admin created successfully in central database.',
            subAdmin: {
                id: subAdmin.id,
                name: subAdmin.name,
                email: subAdmin.email,
                phone: subAdmin.phone,
                role: subAdmin.role,
                status: subAdmin.status || 'ACTIVE',
                city: subAdmin.city || '',
                pincode: subAdmin.pincode || '',
                languages: finalLanguages,
                permissions: cleanPerms,
                assignedDistricts,
                created_at: subAdmin.created_at
            }
        });
    } catch (err) {
        console.error('Create Sub-Admin Error:', err.message);
        res.status(500).json({ success: false, message: err.message || 'Failed to create Sub-Admin.' });
    }
};

// 11. GET ALL SUB-ADMINS (Primary Admin only)
exports.getSubAdmins = async (req, res) => {
    try {
        const { SubAdminPermission, SubAdminDistrict, PatientAssignmentHistory } = require('../models/Schemas');
        const allUsers = await User.find();
        const subAdmins = allUsers.filter(u => {
            const r = (u.role || '').toLowerCase();
            return r === 'sub-admin' || r === 'subadmin' || r === 'sub_admin';
        });

        // Pre-fetch all assignment history for patient assignment counts
        const allAssignments = await PatientAssignmentHistory.getHistory();

        const cleanList = [];
        for (const s of subAdmins) {
            let perms = s.permissions || [];
            if (!perms || perms.length === 0) {
                perms = await SubAdminPermission.getPermissionsForUser(s.id);
            }

            let userLangs = s.languages || ['English'];
            let sCity = s.city || '';
            let sPin = s.pincode || '';

            if (s.device_token && typeof s.device_token === 'string' && s.device_token.startsWith('{')) {
                try {
                    const meta = JSON.parse(s.device_token);
                    if (meta.languages && Array.isArray(meta.languages)) userLangs = meta.languages;
                    if (meta.city && !sCity) sCity = meta.city;
                    if (meta.pincode && !sPin) sPin = meta.pincode;
                } catch (_) {}
            }

            // Fetch assigned districts
            const assignedDistricts = await SubAdminDistrict.getDistrictsForSubAdmin(s.id);

            // Compute patient assignments done by this sub-admin
            const myAssignments = allAssignments.filter(a => a.assigned_by_user_id === s.id);
            const assignedPatientsCount = myAssignments.length;
            const lastActivity = myAssignments.length > 0 ? myAssignments[0].created_at : s.updated_at || s.created_at;

            cleanList.push({
                id: s.id,
                name: s.name,
                email: s.email || '',
                phone: s.phone || '',
                role: s.role || 'Sub-Admin',
                status: s.status || 'ACTIVE',
                city: sCity,
                pincode: sPin,
                languages: userLangs,
                permissions: perms,
                assignedDistricts,
                assignedPatientsCount,
                created_at: s.created_at,
                last_activity: lastActivity
            });
        }

        res.json({ success: true, count: cleanList.length, subAdmins: cleanList });
    } catch (err) {
        console.error('Get Sub-Admins Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to fetch sub-admins.' });
    }
};

// 11b. UPDATE SUB-ADMIN DETAILS & PERMISSIONS (Primary Admin only)
exports.updateSubAdmin = async (req, res) => {
    const { id } = req.params;
    const { name, phone, password, permissions, status, districtIds, districts } = req.body;
    try {
        const { SubAdminDistrict, SubAdminPermission, PermissionChangeHistory } = require('../models/Schemas');
        const target = await User.findById(id);
        if (!target) {
            return res.status(404).json({ success: false, message: 'Sub-Admin not found.' });
        }
        if (target.role && target.role.toLowerCase() === 'admin') {
            return res.status(403).json({ success: false, message: 'Cannot modify Primary Admin through Sub-Admin endpoints.' });
        }

        const updatePayload = {};
        if (name !== undefined) updatePayload.name = name;
        if (phone !== undefined) updatePayload.phone = phone;
        if (status !== undefined) updatePayload.status = status.toString().trim().toUpperCase();
        if (password && password.trim().length > 0) updatePayload.password = password;

        if (permissions && Array.isArray(permissions)) {
            const cleanPerms = permissions.map(p => (p || '').toString().trim().toUpperCase()).filter(p => p.length > 0);
            updatePayload.permissions = cleanPerms;

            // Log changes to PermissionChangeHistory
            const oldPerms = target.permissions || (await SubAdminPermission.getPermissionsForUser(id));
            const oldSet = new Set(oldPerms);
            const newSet = new Set(cleanPerms);

            for (const p of cleanPerms) {
                if (!oldSet.has(p)) {
                    await PermissionChangeHistory.logChange({
                        subAdminUserId: id,
                        changedByUserId: req.user ? req.user.id : null,
                        changedByRole: 'Main Admin',
                        action: 'GRANTED',
                        permissionKey: p,
                        previousState: false,
                        newState: true,
                        reason: 'Permission granted by Main Admin.'
                    });
                }
            }
            for (const p of oldPerms) {
                if (!newSet.has(p)) {
                    await PermissionChangeHistory.logChange({
                        subAdminUserId: id,
                        changedByUserId: req.user ? req.user.id : null,
                        changedByRole: 'Main Admin',
                        action: 'REVOKED',
                        permissionKey: p,
                        previousState: true,
                        newState: false,
                        reason: 'Permission revoked by Main Admin.'
                    });
                }
            }

            await SubAdminPermission.setPermissionsForUser(id, cleanPerms);
        }

        const updated = await User.findByIdAndUpdate(id, updatePayload);

        // Update districts if provided
        const finalDistrictIds = Array.isArray(districtIds) ? districtIds : (Array.isArray(districts) ? districts : null);
        let assignedDistricts = [];
        if (finalDistrictIds !== null) {
            assignedDistricts = await SubAdminDistrict.assignDistrictsToSubAdmin(
                id,
                finalDistrictIds,
                req.user ? req.user.id : null
            );
        } else {
            assignedDistricts = await SubAdminDistrict.getDistrictsForSubAdmin(id);
        }

        res.json({
            success: true,
            message: 'Sub-Admin updated successfully.',
            subAdmin: {
                id: updated.id,
                name: updated.name,
                email: updated.email,
                phone: updated.phone,
                role: updated.role,
                status: updated.status || 'ACTIVE',
                permissions: updated.permissions || [],
                assignedDistricts,
                updated_at: updated.updated_at
            }
        });
    } catch (err) {
        console.error('Update Sub-Admin Error:', err.message);
        res.status(500).json({ success: false, message: err.message || 'Failed to update sub-admin.' });
    }
};

// 11c. TOGGLE SUB-ADMIN STATUS (Activate / Deactivate)
exports.toggleSubAdminStatus = async (req, res) => {
    const { id } = req.params;
    const { status, is_active } = req.body;
    try {
        const target = await User.findById(id);
        if (!target) {
            return res.status(404).json({ success: false, message: 'Sub-Admin not found.' });
        }
        if (target.role && target.role.toLowerCase() === 'admin') {
            return res.status(403).json({ success: false, message: 'Cannot deactivate Primary Admin.' });
        }

        let newStatus = 'ACTIVE';
        if (status) {
            newStatus = status.toString().trim().toUpperCase();
        } else if (is_active !== undefined) {
            newStatus = is_active ? 'ACTIVE' : 'INACTIVE';
        } else {
            newStatus = target.status === 'INACTIVE' ? 'ACTIVE' : 'INACTIVE';
        }

        const updated = await User.findByIdAndUpdate(id, { status: newStatus });

        res.json({
            success: true,
            message: `Sub-Admin account status updated to '${newStatus}'.`,
            subAdmin: {
                id: updated.id,
                name: updated.name,
                email: updated.email,
                status: newStatus
            }
        });
    } catch (err) {
        console.error('Toggle Sub-Admin Status Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to update Sub-Admin status.' });
    }
};

// 12. DELETE SUB-ADMIN (Primary Admin only)
exports.deleteSubAdmin = async (req, res) => {
    const { id } = req.params;
    try {
        const target = await User.findById(id);
        if (!target) {
            return res.status(404).json({ success: false, message: 'Sub-Admin not found.' });
        }
        if (target.role && target.role.toLowerCase() === 'admin') {
            return res.status(403).json({ success: false, message: 'Cannot delete the Primary Admin.' });
        }

        const { SubAdminPermission } = require('../models/Schemas');
        await SubAdminPermission.setPermissionsForUser(id, []);

        const { supabaseAdmin } = require('../config/supabase');
        await supabaseAdmin.from('users').delete().eq('id', id);

        // Delete from Supabase Auth if present
        try {
            await supabaseAdmin.auth.admin.deleteUser(id);
        } catch (_) {}

        res.json({ success: true, message: 'Sub-Admin deleted successfully.' });
    } catch (err) {
        console.error('Delete Sub-Admin Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to delete sub-admin.' });
    }
};

// 12b. GET SUB-ADMIN PERMISSIONS & AUDIT HISTORY
exports.getSubAdminPermissions = async (req, res) => {
    const { id } = req.params;
    try {
        const { SubAdminPermission, PermissionChangeHistory } = require('../models/Schemas');
        const target = await User.findById(id);
        if (!target) {
            return res.status(404).json({ success: false, message: 'Sub-Admin not found.' });
        }

        const permissions = target.permissions || (await SubAdminPermission.getPermissionsForUser(id));
        const history = await PermissionChangeHistory.getHistoryForUser(id);

        res.json({
            success: true,
            subAdminId: id,
            subAdminName: target.name,
            permissions,
            history
        });
    } catch (err) {
        console.error('Get Sub-Admin Permissions Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to retrieve permissions.' });
    }
};

// 12c. UPDATE SUB-ADMIN PERMISSIONS INDIVIDUALLY (Main Admin Only)
exports.updateSubAdminPermissions = async (req, res) => {
    const { id } = req.params;
    const { permissions, reason } = req.body;
    try {
        const { SubAdminPermission, PermissionChangeHistory } = require('../models/Schemas');

        if (!Array.isArray(permissions)) {
            return res.status(400).json({ success: false, message: 'permissions must be an array.' });
        }

        const target = await User.findById(id);
        if (!target) {
            return res.status(404).json({ success: false, message: 'Sub-Admin not found.' });
        }
        if (target.role && target.role.toLowerCase() === 'admin') {
            return res.status(403).json({ success: false, message: 'Cannot modify permissions for Primary Admin.' });
        }

        // Sub-admins cannot modify their own permissions
        if (req.user && req.user.id === id) {
            return res.status(403).json({
                success: false,
                message: 'Access Denied: Sub-Admins cannot modify their own permissions.'
            });
        }

        const oldPerms = target.permissions || (await SubAdminPermission.getPermissionsForUser(id));
        const cleanNewPerms = permissions.map(p => (p || '').toString().trim().toUpperCase()).filter(p => p.length > 0);

        const oldSet = new Set(oldPerms);
        const newSet = new Set(cleanNewPerms);

        // Audit Log newly granted permissions
        for (const p of cleanNewPerms) {
            if (!oldSet.has(p)) {
                await PermissionChangeHistory.logChange({
                    subAdminUserId: id,
                    changedByUserId: req.user ? req.user.id : null,
                    changedByRole: 'Main Admin',
                    action: 'GRANTED',
                    permissionKey: p,
                    previousState: false,
                    newState: true,
                    reason: reason || 'Permission explicitly granted by Main Admin.'
                });
            }
        }

        // Audit Log revoked permissions
        for (const p of oldPerms) {
            if (!newSet.has(p)) {
                await PermissionChangeHistory.logChange({
                    subAdminUserId: id,
                    changedByUserId: req.user ? req.user.id : null,
                    changedByRole: 'Main Admin',
                    action: 'REVOKED',
                    permissionKey: p,
                    previousState: true,
                    newState: false,
                    reason: reason || 'Permission revoked by Main Admin.'
                });
            }
        }

        await SubAdminPermission.setPermissionsForUser(id, cleanNewPerms);
        const updated = await User.findByIdAndUpdate(id, { permissions: cleanNewPerms });

        res.json({
            success: true,
            message: `Permissions updated successfully for ${target.name}.`,
            permissions: updated.permissions,
            updated_at: updated.updated_at
        });
    } catch (err) {
        console.error('Update Permissions Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to update permissions.' });
    }
};

// 12d. GET SUB-ADMIN'S PATIENT ASSIGNMENT HISTORY
exports.getSubAdminAssignmentHistory = async (req, res) => {
    const { id } = req.params;
    try {
        const { PatientAssignmentHistory } = require('../models/Schemas');
        const assignments = await PatientAssignmentHistory.getHistory({ assignedByUserId: id });
        res.json({
            success: true,
            subAdminId: id,
            count: assignments.length,
            assignments
        });
    } catch (err) {
        console.error('Get Sub-Admin Assignment History Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to retrieve assignment history.' });
    }
};

// 13. SUPABASE SYNC, BIOMETRIC, FCM TOKEN STUBS
exports.supabaseAuthSync = async (req, res) => {
    res.json({ success: true, message: 'Supabase sync completed.' });
};
exports.saveBiometric = async (req, res) => {
    res.json({ success: true, message: 'Biometric token saved.' });
};
exports.updateFcmToken = async (req, res) => {
    res.json({ success: true, message: 'FCM token updated.' });
};

// In-memory store for real active OTPs (Key: normalized phone or email, Value: { hashedCode, expiresAt, attempts, lastRequestedAt, requestCount, windowStart, used })
const activeOtpStore = new Map();
const OTP_SALT = process.env.OTP_SALT || process.env.JWT_SECRET || 'gs_health_otp_salt_2026';
const OTP_EXPIRY_MS = 5 * 60 * 1000; // 5 minutes expiration
const OTP_COOLDOWN_MS = 30 * 1000; // 30-second resend cooldown
const OTP_RATE_LIMIT_WINDOW_MS = 15 * 60 * 1000; // 15-minute rate limit window
const OTP_MAX_REQUESTS_PER_WINDOW = 5; // Max 5 requests per 15 minutes
const OTP_MAX_ATTEMPTS = 5; // Max 5 incorrect attempts

function generateRandomOtp() {
    // Cryptographically secure 6-digit numeric OTP (100000 - 999999)
    return crypto.randomInt(100000, 1000000).toString();
}

function hashOtp(code) {
    return crypto.createHmac('sha256', OTP_SALT).update(String(code).trim()).digest('hex');
}

function normalizeKey(identifier) {
    if (!identifier) return '';
    const str = String(identifier).trim().toLowerCase();
    if (str.includes('@')) return str;
    const digits = str.replace(/\D/g, '');
    return digits.length >= 10 ? digits.slice(-10) : digits;
}

function checkOtpRateLimit(identifier) {
    const cleanKey = normalizeKey(identifier);
    if (!cleanKey) return { allowed: true };

    const now = Date.now();
    const existing = activeOtpStore.get(cleanKey);
    if (!existing) return { allowed: true };

    // 1. Cooldown check (30 seconds)
    if (existing.lastRequestedAt && (now - existing.lastRequestedAt < OTP_COOLDOWN_MS)) {
        const remainingSec = Math.ceil((OTP_COOLDOWN_MS - (now - existing.lastRequestedAt)) / 1000);
        return {
            allowed: false,
            status: 429,
            message: `Please wait ${remainingSec} seconds before requesting a new OTP.`
        };
    }

    // 2. Sliding window abuse protection (max 5 per 15 min)
    if (existing.windowStart && (now - existing.windowStart < OTP_RATE_LIMIT_WINDOW_MS)) {
        if (existing.requestCount >= OTP_MAX_REQUESTS_PER_WINDOW) {
            return {
                allowed: false,
                status: 429,
                message: 'Too many OTP requests. Please wait 15 minutes before requesting again.'
            };
        }
    }

    return { allowed: true };
}

function storeOtp(identifier, code) {
    if (!identifier) return;
    const cleanKey = normalizeKey(identifier);
    if (!cleanKey) return;

    const now = Date.now();
    const existing = activeOtpStore.get(cleanKey);

    let windowStart = now;
    let requestCount = 1;

    if (existing && existing.windowStart && (now - existing.windowStart < OTP_RATE_LIMIT_WINDOW_MS)) {
        windowStart = existing.windowStart;
        requestCount = (existing.requestCount || 0) + 1;
    }

    activeOtpStore.set(cleanKey, {
        hashedCode: hashOtp(code),
        createdAt: now,
        expiresAt: now + OTP_EXPIRY_MS, // 5 minutes validity
        lastRequestedAt: now,
        attempts: 0,
        requestCount: requestCount,
        windowStart: windowStart,
        used: false
    });
}

function verifyStoredOtp(identifier, code) {
    if (!code) {
        return { valid: false, message: 'Please enter the 6-digit OTP code.' };
    }
    const cleanCode = String(code).trim();
    if (cleanCode.length !== 6 && cleanCode.length !== 4) {
        return { valid: false, message: 'Please enter a valid 6-digit OTP code.' };
    }

    const cleanKey = normalizeKey(identifier);
    let entry = cleanKey ? activeOtpStore.get(cleanKey) : null;

    // Fallback check if cleanKey not directly found (e.g. searching across active store)
    if (!entry && identifier) {
        for (const [k, v] of activeOtpStore.entries()) {
            if (cleanKey && (k.endsWith(cleanKey) || cleanKey.endsWith(k))) {
                entry = v;
                break;
            }
        }
    }

    if (!entry || entry.used) {
        return { valid: false, message: 'Invalid or expired OTP. Please request a new OTP.' };
    }

    const now = Date.now();
    if (now > entry.expiresAt) {
        activeOtpStore.delete(cleanKey);
        return { valid: false, message: 'OTP has expired. Please request a new OTP.' };
    }

    if (entry.attempts >= OTP_MAX_ATTEMPTS) {
        activeOtpStore.delete(cleanKey);
        return {
            valid: false,
            message: 'Maximum incorrect attempts exceeded. This OTP has been invalidated. Please request a new OTP.'
        };
    }

    const incomingHash = hashOtp(cleanCode);
    if (incomingHash !== entry.hashedCode) {
        entry.attempts += 1;
        const remaining = OTP_MAX_ATTEMPTS - entry.attempts;
        if (remaining <= 0) {
            activeOtpStore.delete(cleanKey);
            return {
                valid: false,
                message: 'Invalid OTP code. Maximum attempts exceeded. Please request a new OTP.'
            };
        }
        return {
            valid: false,
            message: `Invalid OTP code. ${remaining} attempt(s) remaining.`
        };
    }

    // OTP is valid! Invalidate immediately to prevent reuse
    entry.used = true;
    if (cleanKey) activeOtpStore.delete(cleanKey);

    return { valid: true, message: 'OTP verified successfully.' };
}

// 3. OTP VERIFICATION SERVICE (Mobile SMS - Email OTP handled directly by Supabase Auth with Resend SMTP)
exports.requestOTP = async (req, res) => {
    const { phone, email } = req.body;
    try {
        const pNum = phone ? phone.trim() : '';

        if (!pNum) {
            return res.json({
                success: true,
                message: 'Email OTP is managed directly via Supabase Auth with Resend Custom SMTP.'
            });
        }

        const normalizedPhone = normalizeAdminPhone(pNum);
        const authorizedAdminPhone = await getAuthorizedAdminPhone();
        const isAdmin = Boolean(authorizedAdminPhone && normalizedPhone === authorizedAdminPhone);

        // Rate limiting & cooldown check
        const rateCheck = checkOtpRateLimit(pNum);
        if (!rateCheck.allowed) {
            return res.status(rateCheck.status).json({
                success: false,
                message: rateCheck.message
            });
        }

        const realOtp = generateRandomOtp();
        storeOtp(pNum, realOtp);
        if (normalizedPhone && normalizedPhone !== pNum) {
            storeOtp(normalizedPhone, realOtp);
        }

        // Send Real Mobile SMS via Fast2SMS / Twilio
        if (pNum.length >= 10) {
            sendRealSmsOtp(pNum, realOtp).catch(e => console.error('SMS send warning:', e));
        }

        // Return confirmation message without exposing OTP value in response
        res.json({
            success: true,
            message: 'OTP sent successfully to your mobile number.',
            isAdmin: isAdmin
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

        const normalizedPhone = normalizeAdminPhone(pNum);
        const verification = pNum
            ? (verifyStoredOtp(pNum, code).valid ? { valid: true } : verifyStoredOtp(normalizedPhone, code))
            : (eMail ? verifyStoredOtp(eMail, code) : { valid: false, message: 'Phone number or email is required.' });

        if (!verification.valid) {
            return res.status(400).json({
                success: false,
                message: verification.message || 'Invalid or expired OTP.'
            });
        }

        const authorizedAdminPhone = await getAuthorizedAdminPhone();
        const isAdmin = Boolean(authorizedAdminPhone && normalizedPhone === authorizedAdminPhone);

        const user = (pNum ? await User.findOne({ phone: pNum }) : null) || (normalizedPhone ? await User.findOne({ phone: normalizedPhone }) : null) || (eMail ? await User.findOne({ email: eMail }) : null);

        if (user) {
            if ((user.role || '').toLowerCase().includes('admin') && !isAdmin) {
                return res.status(403).json({
                    success: false,
                    message: 'Unauthorized Admin access. OTP verification alone cannot grant Admin access.'
                });
            }

            const { accessToken, refreshToken } = generateTokens(user);
            const existingTokens = Array.isArray(user.refresh_tokens) ? user.refresh_tokens : [];
            if (!existingTokens.includes(refreshToken)) existingTokens.push(refreshToken);
            await User.findByIdAndUpdate(user.id, { refresh_tokens: existingTokens.slice(-20) });

            return res.json({
                success: true,
                message: 'OTP verified successfully.',
                user: {
                    id: user.id,
                    name: user.name,
                    email: user.email,
                    role: user.role,
                    phone: user.phone,
                    permissions: user.permissions,
                    districtIds: user.districtIds,
                    districts: user.districts,
                },
                accessToken,
                refreshToken,
                isAdmin: isAdmin
            });
        }

        res.json({
            success: true,
            verified: true,
            message: 'OTP verified successfully.',
            isAdmin: isAdmin
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

        if (user.phone && user.phone.length >= 10) {
            sendRealSmsOtp(user.phone, realOtp).catch(e => console.error('Password reset SMS warning:', e));
        }

        if (user.email && user.email.includes('@')) {
            await sendOtpEmail(user.email, realOtp, true).catch(e => console.error('Password reset email warning:', e));
        }

        res.json({
            success: true,
            message: `Password reset verification code sent to ${user.email || user.phone}. Please check your SMS/email.`
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

        const isValid = verifyStoredOtp(identifier, code).valid || (email && verifyStoredOtp(email, code).valid) || (phone && verifyStoredOtp(phone, code).valid);
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
    const token = req.body.token || req.body.refreshToken;
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

// 9. GET ALL PATIENTS / USERS FROM SUPABASE DB
exports.getPatients = async (req, res) => {
    try {
        const dbPatients = await User.find({ role: 'Patient' });
        const patientMap = new Map();
        
        for (const p of dbPatients) {
            const pName = p.name && p.name.trim().length > 0
                ? p.name.trim()
                : (p.email ? p.email.split('@')[0] : 'Patient');

            patientMap.set(p.id, {
                id: p.id,
                name: pName,
                email: p.email,
                phone: p.phone || '',
                role: p.role || 'Patient',
                created_at: p.created_at
            });
        }
        
        // Merge patients from consultation requests to ensure zero data omission
        try {
            const reqs = await PatientProblemRequest.find({});
            for (const r of reqs) {
                const pId = r.patient_id || r.patient?.id || r.id;
                const pName = r.patient?.name || r.patientName || (r.patientEmail ? r.patientEmail.split('@')[0] : 'Patient');
                const pEmail = r.patient?.email || r.patientEmail || `${pName?.toLowerCase().replace(/\s+/g, '')}@patient.org`;
                const pPhone = r.patient?.phone || r.patientPhone || '';
                
                if (pId && !patientMap.has(pId)) {
                    patientMap.set(pId, {
                        id: pId,
                        name: pName,
                        email: pEmail,
                        phone: pPhone,
                        role: 'Patient',
                        created_at: r.created_at
                    });
                }
            }
        } catch (_) {}

        const resultList = Array.from(patientMap.values());
        res.json({ success: true, count: resultList.length, patients: resultList });
    } catch (err) {
        console.error('Get Patients Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to fetch patients.' });
    }
};

