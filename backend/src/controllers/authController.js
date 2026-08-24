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
    const { name, email, password, phone, role, fcmToken, specialty, licenseNumber, clinicName, clinicAddress, location, state, city, pincode, latitude, longitude, qualification, experienceYears, profilePhoto, age, gender, bloodGroup, emergencyContact, languages, languagesKnown } = req.body;
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

        if (isSubAdmin) {
            return res.status(403).json({
                success: false,
                message: 'Access Denied: Sub-Admins cannot register publicly. They must be created by the Primary Admin from the Admin Dashboard.'
            });
        }

        // Database-level Single Primary Admin Enforcement
        if (isAdminReg) {
            const existingAdmins = await User.find({ role: 'Admin' });
            if (existingAdmins && existingAdmins.length > 0) {
                const matchAdmin = existingAdmins.find(a => (normalizedEmail && (a.email || '').trim().toLowerCase() === normalizedEmail) || (a.phone && a.phone.trim() === normalizedPhone));
                if (matchAdmin) {
                    return res.status(200).json({
                        success: true,
                        message: 'Primary Admin is already registered. Logging into Admin Dashboard...',
                        user: matchAdmin,
                    });
                }
                return res.status(403).json({
                    success: false,
                    message: 'Primary Admin is already registered in the system. Only one Primary Admin is allowed. Please log in using your Admin credentials.'
                });
            }
        }

        // Email uniqueness check only if provided
        if (normalizedEmail.length > 0) {
            const existingEmail = await User.findOne({ email: normalizedEmail });
            if (existingEmail) {
                return res.status(400).json({ success: false, message: 'Email already registered.' });
            }
        }

        // Phone uniqueness check
        const existingPhone = await User.findOne({ phone: normalizedPhone });
        if (existingPhone) {
            return res.status(400).json({ success: false, message: 'Phone number already registered. Please sign in with OTP.' });
        }

        // 2. Mandatory Fields Validation: City, Pincode, Language, Location
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
        if (!normalizedLocation) {
            return res.status(400).json({ success: false, message: 'Location / Address is mandatory for registration.' });
        }
        if (cleanLanguages.length === 0) {
            return res.status(400).json({ success: false, message: 'Language selection is mandatory for registration.' });
        }

        // Passwordless support: if password omitted, generate secure internal hash
        const effectivePassword = (password && password.trim().length >= 4)
            ? password.trim()
            : (`OTP_SECURE_${require('crypto').randomBytes(12).toString('hex')}`);

        const finalLanguages = cleanLanguages;

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
            languages: finalLanguages
        };
        const metaDeviceToken = fcmToken || JSON.stringify(profileMetaObj);

        try {
            user = await User.create({
                name: name || (normalizedRole === 'Dentist' ? 'Dr. Specialist' : 'Patient'),
                email: normalizedEmail,
                password: effectivePassword,
                phone: normalizedPhone,
                role: normalizedRole,
                state: normalizedLocation,
                city: normalizedCity,
                pincode: normalizedPincode,
                age: age || '',
                gender: gender || '',
                blood_group: bloodGroup || '',
                emergency_contact: emergencyContact || '',
                languages: finalLanguages,
                latitude: latitude || null,
                longitude: longitude || null,
                device_token: metaDeviceToken,
                biometric_token: profilePhoto || null
            });
        } catch (createErr) {
            // Schema fallback: if DB table lacks age/gender/blood_group/languages columns
            user = await User.create({
                name: name || (normalizedRole === 'Dentist' ? 'Dr. Specialist' : 'Patient'),
                email: normalizedEmail,
                password: effectivePassword,
                phone: normalizedPhone,
                role: normalizedRole,
                state: state || '',
                city: city || '',
                pincode: pincode || '',
                latitude: latitude || null,
                longitude: longitude || null,
                device_token: metaDeviceToken,
                biometric_token: profilePhoto || null
            });
        }

        // If registering as a Dentist, automatically insert row into 'dentists' and 'clinics' tables
        if (role === 'Dentist' || (role && role.toLowerCase() === 'dentist')) {
            const licNum = (licenseNumber && licenseNumber.trim())
                ? licenseNumber.trim()
                : `DEN-LIC-${Date.now()}-${Math.floor(Math.random() * 1000)}`;

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
                            { service: 'Tooth Decay / Cavity', fee: '$85' },
                            { service: 'Root Canal', fee: '$180' },
                            { service: 'Orthodontics', fee: '$200' },
                            { service: 'Tooth Extraction', fee: '$110' },
                            { service: 'Periodontics / Gum Care', fee: '$95' }
                        ];
                        clinic = await Clinic.create({
                            user_id: user.id,
                            clinic_name: cName,
                            location: fullLoc,
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
                    experience_years: experienceYears ? parseInt(experienceYears) : 5,
                    qualifications: qualification || 'BDS, MDS',
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
                console.log(`✅ Dentist record created in 'dentists' table for user: ${user.name}`);
            } catch (dErr) {
                console.error('⚠️ Dentist Table Creation Warning:', dErr.message);
            }
        }

        const { accessToken, refreshToken } = generateTokens(user);
        await User.findByIdAndUpdate(user.id, {
            refresh_tokens: [refreshToken]
        });

        // Also sync user_metadata to Supabase Auth for permanent cloud persistence
        try {
            await supabaseAdmin.auth.admin.updateUserById(user.id, {
                user_metadata: {
                    name,
                    role: role || 'Patient',
                    phone,
                    age: age || '',
                    gender: gender || '',
                    bloodGroup: bloodGroup || '',
                    emergencyContact: emergencyContact || '',
                    city: city || '',
                    pincode: pincode || '',
                    state: state || '',
                    languages: finalLanguages
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
                profilePhoto: user.biometric_token
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
        const identifier = (phone || email || '').toString().trim();
        const otpCode = (otp || code || '').toString().trim();

        if (!identifier) {
            return res.status(400).json({ success: false, message: 'Please provide your registered mobile number or email address.' });
        }

        let user = await User.findOne({ phone: identifier });
        if (!user) {
            user = await User.findOne({ email: identifier.toLowerCase() });
        }
        if (!user) {
            user = await User.findOne({ email: identifier });
        }
        if (!user) {
            return res.status(400).json({ success: false, message: 'Invalid credentials. User not registered.' });
        }

        // 1. Passwordless Mobile OTP Login Verification (if provided)
        if (otpCode.length >= 4) {
            const isValidOtp = verifyStoredOtp(identifier, otpCode) || verifyStoredOtp(user.phone, otpCode) || verifyStoredOtp(user.email, otpCode);
            if (!isValidOtp) {
                return res.status(400).json({ success: false, message: 'Invalid or expired OTP.' });
            }
        } else if (password) {
            // 2. Password Login Verification (if password provided)
            const isMatch = await comparePassword(password, user.password);
            if (!isMatch) {
                return res.status(400).json({ success: false, message: 'Invalid credentials.' });
            }
        }
        // Direct registered mobile / email sign in permitted without requiring OTP code

        const normalizedUserEmail = (user.email || '').toString().trim().toLowerCase();
        const userRoleStr = (user.role || '').toString().trim().toLowerCase();
        const reqRoleStr = (role || '').toString().trim().toLowerCase();
        const isSubAdminUser = userRoleStr === 'sub-admin' || userRoleStr === 'subadmin' || userRoleStr === 'sub_admin';

        // Check active status for Sub-Admins
        if (isSubAdminUser && (user.status === 'INACTIVE' || user.status === 'DEACTIVATED')) {
            return res.status(403).json({
                success: false,
                message: 'Access Denied: Your Sub-Admin account has been deactivated by the Main Admin. Please contact the administrator.'
            });
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

            if (isReqAdmin && !isUserAdmin) {
                return res.status(403).json({ success: false, message: `Role Mismatch: Your account is registered as '${user.role}'. Cannot log into Admin Portal.` });
            }
            if (isReqDentist && !isUserDentist) {
                return res.status(403).json({ success: false, message: `Role Mismatch: Your account is registered as '${user.role}'. Cannot log into Dentist Portal.` });
            }
            if (isReqPatient && !isUserPatient && !isUserAdmin) {
                return res.status(403).json({ success: false, message: `Role Mismatch: Your account is registered as '${user.role}'. Cannot log into Patient Portal.` });
            }
        }

        if (fcmToken) {
            await User.findByIdAndUpdate(user.id, { device_token: fcmToken });
        }

        let userAge = user.age || user.patient_age || '';
        let userGender = user.gender || '';
        let userBloodGroup = user.blood_group || user.bloodGroup || '';
        let userEmergency = user.emergency_contact || user.emergencyContact || '';

        if (!userAge || !userGender) {
            try {
                const { data: { user: sbAuthUser } } = await supabaseAdmin.auth.admin.getUserById(user.id);
                if (sbAuthUser && sbAuthUser.user_metadata) {
                    if (!userAge) userAge = sbAuthUser.user_metadata.age || sbAuthUser.user_metadata.patient_age || '';
                    if (!userGender) userGender = sbAuthUser.user_metadata.gender || '';
                    if (!userBloodGroup) userBloodGroup = sbAuthUser.user_metadata.bloodGroup || sbAuthUser.user_metadata.blood_group || '';
                    if (!userEmergency) userEmergency = sbAuthUser.user_metadata.emergencyContact || sbAuthUser.user_metadata.emergency_contact || '';
                }
            } catch (_) {}
        }

        let userPermissions = user.permissions || [];
        if (isSubAdminUser && (!userPermissions || userPermissions.length === 0)) {
            const { SubAdminPermission } = require('../models/Schemas');
            userPermissions = await SubAdminPermission.getPermissionsForUser(user.id);
        }

        const { accessToken, refreshToken } = generateTokens(user);
        await User.findByIdAndUpdate(user.id, {
            refresh_tokens: [refreshToken]
        });

        let userLanguages = user.languages || ['English'];
        if (user.device_token && user.device_token.startsWith('{')) {
            try {
                const meta = JSON.parse(user.device_token);
                if (meta.languages && Array.isArray(meta.languages)) userLanguages = meta.languages;
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
                status: user.status || 'ACTIVE',
                permissions: userPermissions,
                age: userAge,
                gender: userGender,
                bloodGroup: userBloodGroup,
                emergencyContact: userEmergency,
                city: user.city || '',
                pincode: user.pincode || '',
                languages: userLanguages,
                profilePhoto: user.biometric_token
            }
        });
    } catch (err) {
        console.error('Login Error:', err.message);
        res.status(500).json({ success: false, message: 'Server login error.' });
    }
};

// 3. REQUEST OTP
exports.requestOTP = async (req, res) => {
    const { phone, email } = req.body;
    try {
        const otpCode = Math.floor(1000 + Math.random() * 9000).toString();
        const targetEmail = (email || '').trim();

        if (targetEmail.length > 0) {
            await sendOtpEmail(targetEmail, otpCode);
        }
        if (phone && phone.trim().length > 0) {
            await sendRealSmsOtp(phone, otpCode);
        }

        res.json({
            success: true,
            message: 'OTP sent to registered contact details.',
            otp: otpCode
        });
    } catch (err) {
        console.error('Request OTP Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to dispatch OTP code.' });
    }
};

// 4. VERIFY OTP
exports.verifyOTP = async (req, res) => {
    const { phone, email, code } = req.body;
    try {
        if (!code || code.trim().length !== 4) {
            return res.status(400).json({ success: false, message: 'Invalid OTP code format.' });
        }
        res.json({ success: true, message: 'OTP verified successfully.' });
    } catch (err) {
        res.status(500).json({ success: false, message: 'Failed to verify OTP.' });
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
    const { name, email, password, phone, permissions, status, city, pincode, languages } = req.body;
    try {
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

        const cleanPerms = Array.isArray(permissions)
            ? permissions.map(p => (p || '').toString().trim().toUpperCase()).filter(p => p.length > 0)
            : ['PATIENT_VIEW', 'DENTIST_VIEW', 'ASSIGNMENT_VIEW', 'APPOINTMENT_VIEW', 'PROBLEM_VIEW', 'REPORT_VIEW'];

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
        const { SubAdminPermission } = require('../models/Schemas');
        const allUsers = await User.find();
        const subAdmins = allUsers.filter(u => {
            const r = (u.role || '').toLowerCase();
            return r === 'sub-admin' || r === 'subadmin' || r === 'sub_admin';
        });

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
                created_at: s.created_at
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
    const { name, phone, password, permissions, status } = req.body;
    try {
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
        }

        const updated = await User.findByIdAndUpdate(id, updatePayload);

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

