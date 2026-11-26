const crypto = require('crypto');
const jwt = require('jsonwebtoken');
const { supabase, supabaseAdmin } = require('../config/supabase');
const { User, Dentist, Clinic, Referral, Notification, PatientProblemRequest, comparePassword, getDefaultQualificationForSpecialty, resolveMedicalSpecialtyRecord, isDoctorRecordAvailable, extractDoctorLanguages, canonicalPhone10 } = require('../models/Schemas');
const admin = require('firebase-admin');
const { sendOtpEmail } = require('../services/emailService');
const { sendRealSmsOtp, normalizePhoneNumber } = require('../services/smsService');
const { isCloudEnv, getJwtSecret, getRefreshSecret, isAuthorizedStagingOtpRequest } = require('../config/secrets');
const { normalizeRealtimeAppRole, mintSupabaseRealtimeTokenForUser, tryMintSupabaseRealtimeTokenForUser } = require('../services/realtimeTokenService');
const supabaseStorageService = require('../services/supabaseStorageService');

// Helper: Generate JWT tokens
const generateTokens = (user) => {
    const accessToken = jwt.sign(
        { id: user.id, role: user.role },
        getJwtSecret(),
        { expiresIn: '7d' }
    );
    const refreshToken = jwt.sign(
        { id: user.id },
        getRefreshSecret(),
        { expiresIn: '30d' }
    );
    return { accessToken, refreshToken };
};

// Normalize 10-digit mobile phone
const normalizeAdminPhone = (phone) => canonicalPhone10(phone);

// Flexible Patient Profile Completion Mandatory Field Configuration
// Profile Image, Pincode, and Age are optional by default; Gender remains required.
const PATIENT_PROFILE_REQUIREMENTS = {
    requireProfileImage: process.env.PATIENT_REQ_PROFILE_IMAGE === 'true',
    requirePincode: process.env.PATIENT_REQ_PINCODE === 'true',
    requireAge: process.env.PATIENT_REQ_AGE === 'true',
    requireGender: process.env.PATIENT_REQ_GENDER !== 'false',
    requireFullName: process.env.PATIENT_REQ_FULL_NAME === 'true',
    requireAddress: process.env.PATIENT_REQ_ADDRESS === 'true',
    requirePreferredLanguage: process.env.PATIENT_REQ_PREFERRED_LANGUAGE === 'true',
    requireBloodGroup: process.env.PATIENT_REQ_BLOOD_GROUP === 'true',
};

const MAX_PROFILE_IMAGE_BYTES = 5 * 1024 * 1024; // 5 MB

/**
 * Validates and uploads a base64 data-URI profile image to the existing Supabase Storage bucket
 * (`dentaguru-storage`), returning the public URL. Accepts null/empty values and existing http(s) URLs.
 */
async function resolveAndUploadProfilePhoto(rawPhoto, { roleFolder = 'doctors', storageService = supabaseStorageService } = {}) {
    if (rawPhoto === undefined || rawPhoto === null) {
        return { ok: true, photoUrl: null };
    }
    const trimmed = String(rawPhoto).trim();
    if (!trimmed || trimmed.toLowerCase() === 'null') {
        return { ok: true, photoUrl: null };
    }
    if (/^https?:\/\/.+/i.test(trimmed)) {
        return { ok: true, photoUrl: trimmed };
    }

    const dataUriMatch = trimmed.match(/^data:(image\/(?:jpeg|jpg|png|webp));base64,([A-Za-z0-9+/=\s]+)$/i);
    if (!dataUriMatch) {
        if (trimmed.toLowerCase().startsWith('data:')) {
            return {
                ok: false,
                status: 400,
                code: 'INVALID_PROFILE_IMAGE_TYPE',
                message: 'Unsupported profile image format. Please select a JPG, PNG, or WEBP image.'
            };
        }
        return { ok: true, photoUrl: trimmed };
    }

    const rawMime = dataUriMatch[1].toLowerCase();
    const mimeType = rawMime === 'image/jpg' ? 'image/jpeg' : rawMime;
    const ext = mimeType === 'image/png' ? 'png' : (mimeType === 'image/webp' ? 'webp' : 'jpg');
    const cleanB64 = dataUriMatch[2].replace(/\s+/g, '');
    const buffer = Buffer.from(cleanB64, 'base64');

    if (!buffer || buffer.length === 0) {
        return {
            ok: false,
            status: 400,
            code: 'EMPTY_PROFILE_IMAGE',
            message: 'Selected profile image is empty. Please choose another image.'
        };
    }
    if (buffer.length > MAX_PROFILE_IMAGE_BYTES) {
        return {
            ok: false,
            status: 400,
            code: 'PROFILE_IMAGE_TOO_LARGE',
            message: 'Profile image exceeds the 5 MB size limit. Please choose a smaller image.'
        };
    }

    const canUploadToSupabase = Boolean(
        process.env.SUPABASE_URL &&
        !process.env.SUPABASE_URL.includes('placeholder') &&
        storageService &&
        typeof storageService.uploadFile === 'function'
    );

    if (!canUploadToSupabase) {
        return { ok: true, photoUrl: trimmed };
    }

    const safeFolder = String(roleFolder || 'doctors').replace(/[^a-zA-Z0-9_-]/g, '') || 'doctors';
    const filePath = `avatars/${safeFolder}/${Date.now()}_${crypto.randomBytes(4).toString('hex')}.${ext}`;
    try {
        const uploaded = await storageService.uploadFile(buffer, filePath, mimeType);
        if (!uploaded || !uploaded.publicUrl) {
            throw new Error('Storage did not return a public image URL.');
        }
        return { ok: true, photoUrl: uploaded.publicUrl, storagePath: uploaded.path || filePath };
    } catch (uploadErr) {
        console.error('Profile Image Storage Upload Error:', uploadErr.message);
        return {
            ok: false,
            status: 502,
            code: 'PROFILE_IMAGE_UPLOAD_FAILED',
            message: 'Failed to upload profile image to storage. Please try again or remove the image.'
        };
    }
}

const isPatientProfileComplete = (user = {}, tokenMeta = {}, reqs = PATIENT_PROFILE_REQUIREMENTS) => {
    const rawPhoto = String(user.biometric_token || tokenMeta.profilePhoto || '').trim();
    const rawPincode = String(user.pincode || tokenMeta.pincode || '').trim();
    const rawAge = String(user.age || user.patient_age || tokenMeta.age || '').trim();
    const rawGender = String(user.gender || tokenMeta.gender || '').trim();
    const rawName = String(user.name || tokenMeta.name || '').trim();
    const rawAddress = String(user.address || tokenMeta.address || '').trim();
    const rawBlood = String(user.blood_group || tokenMeta.bloodGroup || '').trim();
    const langs = Array.isArray(user.languages) && user.languages.length > 0
        ? user.languages
        : (Array.isArray(tokenMeta.languages) ? tokenMeta.languages : []);

    const parsedAge = parseInt(rawAge, 10);
    const hasValidAge = Boolean(/^\d+$/.test(rawAge) && !Number.isNaN(parsedAge) && parsedAge >= 1 && parsedAge <= 120);
    const hasValidPincode = /^\d{6}$/.test(rawPincode);
    const hasValidGender = rawGender.length > 0 && rawGender.toLowerCase() !== 'null';
    const hasProfilePhoto = rawPhoto.length > 0 && rawPhoto.toLowerCase() !== 'null';
    const hasFullName = rawName.length > 0 && rawName.toLowerCase() !== 'patient' && rawName.toLowerCase() !== 'null';
    const hasAddress = rawAddress.length > 0 && rawAddress.toLowerCase() !== 'null';
    const hasBloodGroup = rawBlood.length > 0 && rawBlood.toLowerCase() !== 'null';
    const hasLanguage = langs.some(l => String(l || '').trim().length > 0);

    if (reqs.requireProfileImage && !hasProfilePhoto) return false;
    if (reqs.requirePincode && !hasValidPincode) return false;
    if (reqs.requireAge && !hasValidAge) return false;
    if (reqs.requireGender && !hasValidGender) return false;
    if (reqs.requireFullName && !hasFullName) return false;
    if (reqs.requireAddress && !hasAddress) return false;
    if (reqs.requirePreferredLanguage && !hasLanguage) return false;
    if (reqs.requireBloodGroup && !hasBloodGroup) return false;

    return true;
};

const parseUserTokenMeta = (user) => {
    if (user?.device_token && typeof user.device_token === 'string' && user.device_token.trim().startsWith('{')) {
        try {
            return JSON.parse(user.device_token);
        } catch (_) { }
    }
    return {};
};

const buildPatientUserPayload = (user, overrideMeta = null) => {
    const tokenMeta = overrideMeta || parseUserTokenMeta(user);
    const rawAge = user.age || user.patient_age || tokenMeta.age || '';
    const rawGender = user.gender || tokenMeta.gender || '';
    const rawPincode = user.pincode || tokenMeta.pincode || '';
    const resolvedLanguages = Array.isArray(user.languages) && user.languages.length > 0
        ? user.languages
        : (Array.isArray(tokenMeta.languages) && tokenMeta.languages.length > 0 ? tokenMeta.languages : ['English']);

    return {
        id: user.id,
        name: user.name || 'Patient',
        email: user.email || '',
        role: user.role || 'Patient',
        phone: user.phone || '',
        city: user.city || tokenMeta.city || '',
        pincode: String(rawPincode || ''),
        state: user.state || tokenMeta.state || '',
        address: user.address || tokenMeta.address || '',
        age: String(rawAge || ''),
        gender: String(rawGender || ''),
        bloodGroup: user.blood_group || tokenMeta.bloodGroup || '',
        emergencyContact: user.emergency_contact || tokenMeta.emergencyContact || '',
        languages: resolvedLanguages,
        profilePhoto: user.biometric_token || tokenMeta.profilePhoto || null,
        isProfileComplete: isPatientProfileComplete(user, tokenMeta),
    };
};

// Authoritative Admin / Sub-Admin role & account status helpers
const MAIN_ADMIN_ROLES = new Set([
    'admin',
    'primaryadmin',
    'primary_admin',
    'superadmin',
    'super_admin'
]);

const SUB_ADMIN_ROLES = new Set([
    'sub-admin',
    'subadmin',
    'sub_admin'
]);

const INACTIVE_ACCOUNT_STATUSES = new Set([
    'INACTIVE',
    'DEACTIVATED',
    'SUSPENDED',
    'BLOCKED'
]);

const isMainAdminRole = (role) => MAIN_ADMIN_ROLES.has(String(role || '').trim().toLowerCase());
const isSubAdminRole = (role) => SUB_ADMIN_ROLES.has(String(role || '').trim().toLowerCase());

const getEffectiveUserStatus = (user, tokenMeta = {}) => {
    const raw = user?.status ?? tokenMeta?.status ?? 'ACTIVE';
    const normalized = String(raw || '').trim().toUpperCase();
    return normalized || 'ACTIVE';
};

const isAccountActive = (user, tokenMeta = {}) =>
    !INACTIVE_ACCOUNT_STATUSES.has(getEffectiveUserStatus(user, tokenMeta));

// Parse valid 10-digit admin phones from env config (ignores placeholders like "+91XXXXXXXXXX")
const getConfiguredEnvAdminPhones = (env = process.env) => {
    const raw = [env.ADMIN_PHONE || '', env.ADMIN_MOBILE_NUMBER || '']
        .filter(Boolean)
        .join(',');
    const phones = new Set();
    for (const part of raw.split(',')) {
        const norm = normalizeAdminPhone(part);
        if (/^\d{10}$/.test(norm)) {
            phones.add(norm);
        }
    }
    return phones;
};

/**
 * Authoritative Main Admin verification backed by the database user record.
 * - Requires an existing user record with a valid ID and Main Admin role in public.users.
 * - Requires the account to be active (rejects INACTIVE/DEACTIVATED/SUSPENDED/BLOCKED).
 * - When authenticating via mobile number/OTP, requires exact normalized 10-digit phone match
 *   between the verified mobile number and the stored Admin record's phone.
 * - Never lets a stale/placeholder/mismatched ADMIN_PHONE env var override a verified active DB Admin record.
 */
const evaluateMainAdminAuthorization = ({ user, normalizedPhone = '', isPhoneAuth = true }) => {
    if (!user || !user.id) {
        return {
            authorized: false,
            isMainAdminRole: false,
            isActive: false,
            reason: 'USER_NOT_FOUND'
        };
    }

    const hasMainAdminRole = isMainAdminRole(user.role);
    const tokenMeta = parseUserTokenMeta(user);
    const effectiveStatus = getEffectiveUserStatus(user, tokenMeta);
    const active = isAccountActive(user, tokenMeta);

    if (!hasMainAdminRole) {
        return {
            authorized: false,
            isMainAdminRole: false,
            isActive: active,
            effectiveStatus,
            reason: 'NOT_MAIN_ADMIN_ROLE'
        };
    }

    if (!active) {
        return {
            authorized: false,
            isMainAdminRole: true,
            isActive: false,
            effectiveStatus,
            reason: 'ACCOUNT_DEACTIVATED'
        };
    }

    const storedAdminPhone = normalizeAdminPhone(user.phone);
    if (isPhoneAuth) {
        const validVerifiedPhone = /^\d{10}$/.test(normalizedPhone);
        const validStoredPhone = /^\d{10}$/.test(storedAdminPhone);
        if (!validVerifiedPhone || !validStoredPhone || storedAdminPhone !== normalizedPhone) {
            return {
                authorized: false,
                isMainAdminRole: true,
                isActive: true,
                effectiveStatus,
                reason: 'PHONE_MISMATCH'
            };
        }
    }

    return {
        authorized: true,
        isMainAdminRole: true,
        isActive: true,
        effectiveStatus,
        normalizedAdminPhone: storedAdminPhone,
        reason: 'AUTHORIZED'
    };
};

// Retrieve authorized active Main Admin phone numbers from database (and valid 10-digit env config)
const getAuthorizedAdminPhone = async () => {
    try {
        const adminUser = await User.findOne({ role: 'Admin' }) || await User.findOne({ role: 'ADMIN' });
        if (adminUser && adminUser.phone && isAccountActive(adminUser, parseUserTokenMeta(adminUser))) {
            const norm = normalizeAdminPhone(adminUser.phone);
            if (/^\d{10}$/.test(norm)) return norm;
        }
    } catch (_) { }
    const envPhones = Array.from(getConfiguredEnvAdminPhones());
    return envPhones.length > 0 ? envPhones[0] : null;
};

// 1. REGISTER
exports.register = async (req, res) => {
    const { name, email, password, phone, role, fcmToken, specialty, licenseNumber, clinicName, clinicAddress, location, state, city, pincode, latitude, longitude, qualification, experienceYears, profilePhoto, age, gender, bloodGroup, emergencyContact, languages, languagesKnown, referralCode, ref } = req.body;
    try {
        const { validateCoordinates, validateDoctorRegistrationClinicFields } = require('../utils/doctorClinicLocationHelper');
        const normalizedRole = (role || 'Patient').toString().trim();
        const rawPhone = (phone || '').toString().trim();
        const canonical10 = canonicalPhone10(rawPhone);
        const normalizedPhone = canonical10.length >= 10 ? canonical10 : rawPhone;
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
            if (existingEmail && canonicalPhone10(existingEmail.phone) !== canonicalPhone10(normalizedPhone)) {
                return res.status(400).json({ success: false, message: 'Email already registered.' });
            }
        }

        // Canonical mobile uniqueness check across +91 / 91 / 0 / spaced variants
        const existingPhone = await User.findByMobile(normalizedPhone);
        if (existingPhone) {
            return res.status(400).json({
                success: false,
                code: 'MOBILE_ALREADY_REGISTERED',
                existingRole: existingPhone.role || 'Patient',
                message: 'Phone number already registered. Please sign in with OTP.'
            });
        }

        // 2. Mandatory Field Validation: City & Doctor Clinic Location Fields
        const normalizedCity = (city || '').toString().trim();
        const normalizedState = (state || '').toString().trim();
        const normalizedPincode = (pincode !== undefined && pincode !== null) ? String(pincode).trim() : '';
        const normalizedAge = (age !== undefined && age !== null) ? String(age).trim() : '';
        const normalizedClinicAddress = (clinicAddress || location || '').toString().trim();
        const normalizedLocation = (normalizedClinicAddress || normalizedState || '').toString().trim();

        const isDoctorReg = normalizedRole.toLowerCase() === 'dentist' || normalizedRole.toLowerCase() === 'doctor';
        const isClinicReg = normalizedRole.toLowerCase() === 'clinic' || normalizedRole.toLowerCase() === 'clinic_admin';
        let effectiveLatitude = null;
        let effectiveLongitude = null;
        let effectiveClinicName = (clinicName || (isClinicReg ? name : '') || '').toString().trim();
        let effectiveClinicAddress = normalizedClinicAddress;

        if (isDoctorReg || isClinicReg) {
            const facilityCheck = validateDoctorRegistrationClinicFields({
                clinicName: effectiveClinicName,
                clinicAddress: effectiveClinicAddress,
                city: normalizedCity,
                state: normalizedState,
                pincode: normalizedPincode,
                latitude,
                longitude
            });
            if (!facilityCheck.ok) {
                return res.status(400).json({ success: false, message: facilityCheck.message });
            }
            effectiveClinicName = facilityCheck.clinicName;
            effectiveClinicAddress = facilityCheck.clinicAddress;
            effectiveLatitude = facilityCheck.latitude;
            effectiveLongitude = facilityCheck.longitude;
        } else {
            const coordValidation = validateCoordinates(latitude, longitude, false);
            if (!coordValidation.ok) {
                return res.status(400).json({ success: false, message: coordValidation.message });
            }
            effectiveLatitude = coordValidation.hasUpdate ? coordValidation.latitude : null;
            effectiveLongitude = coordValidation.hasUpdate ? coordValidation.longitude : null;
        }

        if (!isDoctorReg && normalizedPincode.length > 0 && !/^\d{6}$/.test(normalizedPincode)) {
            return res.status(400).json({ success: false, message: 'Please enter a valid 6-digit pincode.' });
        }
        if (normalizedAge.length > 0) {
            const parsedAge = parseInt(normalizedAge, 10);
            if (!/^\d+$/.test(normalizedAge) || Number.isNaN(parsedAge) || parsedAge < 1 || parsedAge > 120) {
                return res.status(400).json({ success: false, message: 'Please enter a valid age between 1 and 120.' });
            }
        }
        const rawLanguages = languages || languagesKnown;
        let cleanLanguages = [];
        if (Array.isArray(rawLanguages)) {
            cleanLanguages = rawLanguages.map(l => (l || '').toString().trim()).filter(Boolean);
        } else if (typeof rawLanguages === 'string' && rawLanguages.trim().length > 0) {
            cleanLanguages = rawLanguages.split(',').map(s => s.trim()).filter(Boolean);
        }

        const requestedClinicId = (req.body.clinicId || req.body.clinic_id || '').toString().trim();
        const hasClinicContext = Boolean(requestedClinicId || effectiveClinicName.length > 0);
        if (!normalizedCity && !(isDoctorReg && hasClinicContext)) {
            return res.status(400).json({ success: false, message: 'City is mandatory for registration.' });
        }

        // Generate unique referral code for this user
        const cleanNamePrefix = (name || 'PAT').replace(/[^a-zA-Z]/g, '').substring(0, 3).toUpperCase() || 'DEN';
        const userReferralCode = `DG-${cleanNamePrefix}${normalizedPhone ? normalizedPhone.slice(-4) : Math.floor(1000 + Math.random() * 9000)}`;

        // Passwordless support: if password omitted, generate secure internal hash
        const effectivePassword = (password && password.trim().length >= 4)
            ? password.trim()
            : (`OTP_SECURE_${require('crypto').randomBytes(12).toString('hex')}`);

        const finalLanguages = cleanLanguages.length > 0 ? cleanLanguages : ['English'];

        if (isDoctorReg) {
            effectiveAssignedRole = 'DOCTOR';
        }
        const rawSpecInput = (specialty || req.body.speciality || req.body.specialtyName || req.body.medicalSpecialty || '').toString().trim();
        const specResolution = isDoctorReg
            ? await resolveMedicalSpecialtyRecord(rawSpecInput || 'General Medicine', req.body.specialtyId || req.body.specialty_id || null)
            : { specialty: rawSpecInput || 'General Medicine', specialty_id: null, department: '' };
        const resolvedDocSpecialty = specResolution.specialty;
        const resolvedDocQualification = qualification || req.body.qualifications || getDefaultQualificationForSpecialty(resolvedDocSpecialty);
        const resolvedDocExp = experienceYears ? parseInt(experienceYears, 10) : 5;

        const photoResolution = await resolveAndUploadProfilePhoto(profilePhoto, {
            roleFolder: isDoctorReg ? 'doctors' : 'patients'
        });
        if (!photoResolution.ok) {
            return res.status(photoResolution.status || 400).json({
                success: false,
                code: photoResolution.code || 'PROFILE_IMAGE_ERROR',
                message: photoResolution.message || 'Failed to process profile image.'
            });
        }
        const resolvedProfilePhotoUrl = photoResolution.photoUrl || null;

        let user;
        const effectiveState = normalizedState;
        const effectivePincode = normalizedPincode;
        const profileMetaObj = {
            age: normalizedAge,
            gender: gender || '',
            bloodGroup: bloodGroup || '',
            emergencyContact: emergencyContact || '',
            city: normalizedCity,
            state: effectiveState,
            pincode: effectivePincode,
            location: normalizedLocation,
            address: normalizedClinicAddress || normalizedLocation,
            languages: finalLanguages,
            referral_code: userReferralCode,
            ...(resolvedProfilePhotoUrl ? { profilePhoto: resolvedProfilePhotoUrl } : {}),
            ...(isDoctorReg ? {
                specialty: resolvedDocSpecialty,
                specialtyId: specResolution.specialty_id || null,
                department: specResolution.department || '',
                qualification: resolvedDocQualification,
                experienceYears: resolvedDocExp,
                clinicId: requestedClinicId || null,
                clinicName: effectiveClinicName,
                clinicAddress: effectiveClinicAddress,
                latitude: effectiveLatitude,
                longitude: effectiveLongitude,
                licenseNumber: licenseNumber || ''
            } : {})
        };
        const metaDeviceToken = fcmToken
            ? JSON.stringify({ ...profileMetaObj, fcmToken })
            : JSON.stringify(profileMetaObj);

        try {
            user = await User.create({
                name: name || (isDoctorReg ? 'Dr. Specialist' : (effectiveAssignedRole === 'Sub-Admin' ? 'Sub-Admin' : 'Patient')),
                email: effectiveEmail,
                password: effectivePassword,
                phone: normalizedPhone,
                role: effectiveAssignedRole,
                state: effectiveState,
                city: normalizedCity,
                pincode: effectivePincode,
                age: normalizedAge,
                gender: gender || '',
                blood_group: bloodGroup || '',
                emergency_contact: emergencyContact || '',
                languages: finalLanguages,
                referral_code: userReferralCode,
                latitude: effectiveLatitude,
                longitude: effectiveLongitude,
                device_token: metaDeviceToken,
                biometric_token: resolvedProfilePhotoUrl
            });
        } catch (createErr) {
            // Schema fallback: if DB table lacks age/gender/blood_group/languages columns
            user = await User.create({
                name: name || (isDoctorReg ? 'Dr. Specialist' : (effectiveAssignedRole === 'Sub-Admin' ? 'Sub-Admin' : 'Patient')),
                email: effectiveEmail,
                password: effectivePassword,
                phone: normalizedPhone,
                role: effectiveAssignedRole,
                state: effectiveState,
                city: normalizedCity,
                pincode: effectivePincode,
                latitude: effectiveLatitude,
                longitude: effectiveLongitude,
                device_token: metaDeviceToken,
                biometric_token: resolvedProfilePhotoUrl
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
        let createdDentistRecord = null;
        let linkedClinicName = effectiveClinicName;
        if (isDoctorReg) {
            let licNum = (licenseNumber && licenseNumber.trim()) ? licenseNumber.trim() : '';
            const licLower = licNum.toLowerCase();
            if (!licNum || licLower === 'med-lic-reg' || licLower === 'med-lic-registered') {
                licNum = `MED-LIC-${Date.now()}-${Math.floor(1000 + Math.random() * 9000)}`;
            } else {
                const existingLic = await Dentist.findOne({ license_number: licNum }).catch(() => null);
                if (existingLic) {
                    licNum = `${licNum}-${Date.now().toString().slice(-5)}-${Math.floor(100 + Math.random() * 900)}`;
                }
            }

            let clinicId = null;
            const cName = linkedClinicName;
            if (requestedClinicId || cName.length > 0) {
                try {
                    let clinic = requestedClinicId ? await Clinic.findById(requestedClinicId).catch(() => null) : null;
                    if (!clinic && cName.length > 0) {
                        clinic = await Clinic.findOne({ clinic_name: cName });
                    }
                    const cAddr = effectiveClinicAddress;
                    const cPin = effectivePincode;
                    const fullLoc = cAddr
                        ? (cPin && !cAddr.includes(cPin) ? `${cAddr} - ${cPin}` : cAddr)
                        : (normalizedCity ? `${normalizedCity}${cPin ? ' - ' + cPin : ''}` : '');
                    if (!clinic && cName.length > 0) {
                        const defaultPricing = Array.isArray(req.body.pricing) ? req.body.pricing : [];
                        clinic = await Clinic.create({
                            user_id: user.id,
                            clinic_name: cName,
                            location: fullLoc,
                            latitude: effectiveLatitude,
                            longitude: effectiveLongitude,
                            verified: true,
                            rating: 0,
                            reviews_count: 0,
                            services: [resolvedDocSpecialty, 'General Consultation'],
                            pricing: defaultPricing
                        });
                        console.log(`✅ New Clinic record created in 'clinics' table for: ${cName}`);
                        await Notification.create({
                            recipient_role: 'Admin',
                            recipient_id: 'ALL_ADMINS',
                            title: '🏥 New Clinic Registered',
                            message: `Clinic "${cName}" registered in ${normalizedCity || fullLoc || 'GS Health'}.`,
                            type: 'clinic_registered'
                        }).catch(() => null);
                    } else if (clinic) {
                        const currentServices = Array.isArray(clinic.services) ? [...clinic.services] : [];
                        const clinicUpdates = {};
                        if (resolvedDocSpecialty && !currentServices.includes(resolvedDocSpecialty)) {
                            currentServices.push(resolvedDocSpecialty);
                            clinicUpdates.services = currentServices;
                        }
                        if (clinic.latitude == null && effectiveLatitude != null) clinicUpdates.latitude = effectiveLatitude;
                        if (clinic.longitude == null && effectiveLongitude != null) clinicUpdates.longitude = effectiveLongitude;
                        if (Object.keys(clinicUpdates).length > 0) {
                            await Clinic.findByIdAndUpdate(clinic.id, clinicUpdates);
                        }
                        if (!linkedClinicName && clinic.clinic_name) linkedClinicName = clinic.clinic_name;
                        console.log(`ℹ️ Existing Clinic record linked: ${clinic.clinic_name || cName}`);
                    }
                    clinicId = clinic ? clinic.id : null;
                } catch (cErr) {
                    console.error('⚠️ Clinic Table Creation Warning:', cErr.message);
                }
            } else {
                console.log(`ℹ️ No clinic name provided for doctor ${user.name}. Leaving clinic_id as NULL.`);
            }

            try {
                createdDentistRecord = await Dentist.create({
                    user_id: user.id,
                    clinic_id: clinicId,
                    clinic_name: linkedClinicName,
                    clinic_address: effectiveClinicAddress,
                    speciality: resolvedDocSpecialty,
                    specialty_id: specResolution.specialty_id || null,
                    department: specResolution.department || '',
                    license_number: licNum,
                    experience_years: resolvedDocExp,
                    qualifications: resolvedDocQualification,
                    availability_status: 'Available',
                    consultation_fee: (req.body.consultationFee || req.body.consultation_fee || '').toString(),
                    bio: (req.body.bio || '').toString(),
                    state: effectiveState,
                    city: normalizedCity,
                    pincode: effectivePincode,
                    languages: finalLanguages,
                    latitude: effectiveLatitude,
                    longitude: effectiveLongitude,
                    rating: 5.0,
                    reviews_count: 0
                });
                console.log(`✅ Doctor record created in 'dentists' table for user: ${user.name}`);
            } catch (dErr) {
                console.error('⚠️ Doctor Table Creation Warning:', dErr.message);
            }
        }

        // If registering as a Clinic, ensure a canonical row exists in 'clinics' table linked to user.id
        let createdClinicRecord = null;
        const regRoleLower = (effectiveAssignedRole || '').toLowerCase();
        if (regRoleLower === 'clinic' || regRoleLower === 'clinic_admin') {
            const cName = effectiveClinicName || (user.name || 'GS HEALTH Clinic').trim();
            const cAddr = effectiveClinicAddress || normalizedLocation || '';
            try {
                let existingClinic = await Clinic.findOne({ clinic_name: cName });
                if (!existingClinic) {
                    existingClinic = await Clinic.create({
                        user_id: user.id,
                        clinic_name: cName,
                        clinic_address: cAddr,
                        location: cAddr,
                        city: normalizedCity,
                        state: effectiveState,
                        pincode: effectivePincode,
                        latitude: effectiveLatitude,
                        longitude: effectiveLongitude,
                        verified: true,
                        rating: 0,
                        reviews_count: 0,
                        services: ['General Consultation']
                    });
                } else {
                    const clinicPatch = {
                        ...(!existingClinic.user_id ? { user_id: user.id } : {}),
                        ...(cAddr ? { clinic_address: cAddr, location: cAddr } : {}),
                        ...(normalizedCity ? { city: normalizedCity } : {}),
                        ...(effectiveState ? { state: effectiveState } : {}),
                        ...(effectivePincode ? { pincode: effectivePincode } : {}),
                        ...(effectiveLatitude !== null && effectiveLongitude !== null ? { latitude: effectiveLatitude, longitude: effectiveLongitude } : {})
                    };
                    existingClinic = await Clinic.findByIdAndUpdate(existingClinic.id, clinicPatch);
                }
                createdClinicRecord = existingClinic;
            } catch (cErr) {
                console.error('⚠️ Clinic user registration table link notice:', cErr.message);
            }
        }

        // 🔔 Emit persistent Admin Notification for new user registration (Patient / Doctor / Clinic)
        try {
            const roleLower = (effectiveAssignedRole || 'Patient').toLowerCase();
            if (isDoctorReg) {
                const docDisplay = (user.name || '').toLowerCase().startsWith('dr') ? user.name : `Dr. ${user.name}`;
                await Notification.create({
                    recipient_role: 'Admin',
                    recipient_id: 'ALL_ADMINS',
                    title: '🩺 New Doctor Registered',
                    message: `${docDisplay} (${resolvedDocSpecialty}) registered in ${normalizedCity || 'GS Health'}.`,
                    type: 'doctor_registered'
                });
            } else if (roleLower === 'clinic' || roleLower === 'clinic_admin') {
                await Notification.create({
                    recipient_role: 'Admin',
                    recipient_id: 'ALL_ADMINS',
                    title: '🏥 New Clinic Registered',
                    message: `Clinic "${clinicName || user.name}" (${user.phone}) registered in ${normalizedCity || 'GS Health'}.`,
                    type: 'clinic_registered'
                });
            } else if (roleLower === 'patient') {
                await Notification.create({
                    recipient_role: 'Admin',
                    recipient_id: 'ALL_ADMINS',
                    title: '👤 New Patient Registered',
                    message: `${user.name} (${user.phone}) registered as a Patient in ${normalizedCity || 'GS Health'}.`,
                    type: 'patient_registered'
                });
            }
        } catch (notifErr) {
            console.warn('⚠️ Registration admin notification notice:', notifErr.message);
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
        } catch (_) { }

        const rtBundle = await tryMintSupabaseRealtimeTokenForUser(user, {
            dentistId: createdDentistRecord?.id || null,
            clinicId: createdClinicRecord?.id || createdDentistRecord?.clinic_id || null,
        }).catch(() => null);

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
                    dentistId: createdDentistRecord?.id || user.id,
                    userId: user.id,
                    clinicId: createdDentistRecord?.clinic_id || requestedClinicId || null,
                    specialty: createdDentistRecord?.speciality || resolvedDocSpecialty,
                    specialtyId: createdDentistRecord?.specialty_id || specResolution.specialty_id || null,
                    department: createdDentistRecord?.department || specResolution.department || '',
                    qualification: createdDentistRecord?.qualifications || resolvedDocQualification,
                    experienceYears: createdDentistRecord?.experience_years || resolvedDocExp,
                    clinicName: linkedClinicName || effectiveClinicName,
                    clinicAddress: effectiveClinicAddress,
                    state: effectiveState,
                    pincode: effectivePincode,
                    latitude: effectiveLatitude,
                    longitude: effectiveLongitude,
                    licenseNumber: createdDentistRecord?.license_number || licenseNumber || '',
                    availability_status: 'Available',
                    isAvailable: true
                } : {}),
                ...(createdClinicRecord ? {
                    clinicId: createdClinicRecord.id,
                    clinicName: createdClinicRecord.clinic_name || effectiveClinicName || user.name,
                    clinicAddress: createdClinicRecord.clinic_address || effectiveClinicAddress || normalizedLocation,
                    clinicLocation: createdClinicRecord.location || effectiveClinicAddress || normalizedLocation,
                    city: createdClinicRecord.city || normalizedCity,
                    state: createdClinicRecord.state || effectiveState,
                    pincode: createdClinicRecord.pincode || effectivePincode,
                    latitude: createdClinicRecord.latitude ?? effectiveLatitude,
                    longitude: createdClinicRecord.longitude ?? effectiveLongitude
                } : {})
            },
            accessToken,
            refreshToken,
            ...(rtBundle ? {
                realtimeToken: rtBundle.realtimeToken,
                realtimeTokenExpiresAt: rtBundle.realtimeTokenExpiresAt,
            } : {})
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
            user = await User.findByMobile(rawIdentifier)
                || await User.findOne({ phone: identifier })
                || (rawIdentifier !== identifier ? await User.findOne({ phone: rawIdentifier }) : null)
                || await User.findOne({ email: identifier.toLowerCase() });
        }
        if (!user) {
            return res.status(400).json({ success: false, message: 'Invalid credentials. User not registered.' });
        }

        // 1. Passwordless Mobile OTP Login Verification (if provided)
        if (otpCode.length > 0) {
            const otpTargetKey = normalizeKey(identifier) || normalizeKey(rawIdentifier) || normalizeKey(user.phone) || normalizeKey(user.email);
            let otpVerification = await verifyStoredOtp(otpTargetKey, otpCode);
            if (!otpVerification.valid && user.phone) {
                const fallbackKey = normalizeKey(user.phone);
                if (fallbackKey && fallbackKey !== otpTargetKey) {
                    otpVerification = await verifyStoredOtp(fallbackKey, otpCode);
                }
            }
            if (!otpVerification.valid) {
                return res.status(400).json({
                    success: false,
                    message: otpVerification.message || 'Invalid or expired OTP. Please request a new OTP.'
                });
            }
        } else if (password) {
            // 2. Password Login Verification (if password provided)
            const isMatch = await comparePassword(password, user.password);
            if (!isMatch) {
                return res.status(400).json({ success: false, message: 'Invalid credentials.' });
            }
        } else if (isCloudEnv()) {
            return res.status(401).json({
                success: false,
                message: 'Authentication required: provide a verified OTP code or password.'
            });
        }
        // Direct registered mobile / email sign in permitted only in non-cloud local test/dev environments

        const userRoleStr = (user.role || '').toString().trim().toLowerCase();
        const isSubAdminUser = isSubAdminRole(userRoleStr);
        const isStrictMainAdminRole = isMainAdminRole(userRoleStr);
        const tokenMeta = parseUserTokenMeta(user);
        const effectiveStatus = getEffectiveUserStatus(user, tokenMeta);

        // Enforce active account status for both Main Admin and Sub-Admin accounts
        if ((isStrictMainAdminRole || isSubAdminUser) && !isAccountActive(user, tokenMeta)) {
            return res.status(403).json({
                success: false,
                code: 'ACCOUNT_DEACTIVATED',
                message: isSubAdminUser
                    ? 'Access Denied: Your Sub-Admin account has been deactivated by the Main Admin. Please contact the administrator.'
                    : 'Access Denied: Your Admin account is currently inactive or deactivated.'
            });
        }

        // Enforce Portal Role Matching and Authoritative DB-Backed Main Admin Verification
        const requestedRole = (role || '').trim().toLowerCase();
        const userRole = userRoleStr;
        const isReqSubAdmin = isSubAdminRole(requestedRole);
        const isReqAdmin = requestedRole.includes('admin') && !isReqSubAdmin;
        const isUserAdmin = isStrictMainAdminRole;

        const isPhoneIdentifier = !identifier.includes('@');
        const normalizedIdentifier = isPhoneIdentifier ? normalizeAdminPhone(identifier) : '';
        const mainAdminAuth = evaluateMainAdminAuthorization({
            user,
            normalizedPhone: normalizedIdentifier,
            isPhoneAuth: isPhoneIdentifier
        });
        const isAuthorizedAdmin = mainAdminAuth.authorized;

        if (isReqAdmin && !isSubAdminUser && !isAuthorizedAdmin) {
            return res.status(403).json({
                success: false,
                message: 'Unauthorized Admin access: This mobile number is not authorized as Main Admin.'
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

            if ((isReqAdmin || isReqSubAdmin) && !isUserAdmin && !isSubAdminUser) {
                return res.status(403).json({ success: false, message: `Role Mismatch: Your account is registered as '${user.role}'. Cannot log into Admin Portal.` });
            }
            if (!isUserAdmin && !isSubAdminUser) {
                if (isReqDentist && !isUserDentist) {
                    return res.status(403).json({ success: false, message: `Role Mismatch: Your account is registered as '${user.role}'. Cannot log into Doctor Portal.` });
                }
                if (isReqPatient && !isUserPatient) {
                    return res.status(403).json({ success: false, message: `Role Mismatch: Your account is registered as '${user.role}'. Cannot log into Patient Portal.` });
                }
            }
        }

        if (fcmToken) {
            User.updateFcmToken(user.id, fcmToken).catch(() => { });
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
        }).catch(() => { });

        let userLanguages = (Array.isArray(user.languages) && user.languages.length > 0)
            ? user.languages
            : (Array.isArray(tokenMeta.languages) && tokenMeta.languages.length > 0 ? tokenMeta.languages : ['English']);

        let doctorExtra = {};
        if (userRoleStr.includes('dentist') || userRoleStr.includes('doctor')) {
            try {
                const docRec = await Dentist.findById(user.id) || await Dentist.findOne({ user_id: user.id });
                const resolvedSpec = docRec?.speciality || docRec?.specialty || tokenMeta.specialty || 'General Medicine';
                const docLanguages = docRec ? extractDoctorLanguages({ ...docRec, users: user }) : userLanguages;
                userLanguages = docLanguages;
                const rawDocLat = docRec?.latitude ?? docRec?.clinics?.latitude ?? user.latitude ?? tokenMeta.latitude ?? null;
                const rawDocLng = docRec?.longitude ?? docRec?.clinics?.longitude ?? user.longitude ?? tokenMeta.longitude ?? null;
                const parsedDocLat = rawDocLat !== null && rawDocLat !== '' && Number.isFinite(Number(rawDocLat)) ? Number(rawDocLat) : null;
                const parsedDocLng = rawDocLng !== null && rawDocLng !== '' && Number.isFinite(Number(rawDocLng)) ? Number(rawDocLng) : null;
                doctorExtra = {
                    dentistId: docRec?.id || user.id,
                    userId: user.id,
                    clinicId: docRec?.clinic_id || null,
                    specialty: resolvedSpec,
                    qualification: docRec?.qualifications || docRec?.qualification || tokenMeta.qualification || getDefaultQualificationForSpecialty(resolvedSpec),
                    experienceYears: docRec?.experience_years || docRec?.experienceYears || tokenMeta.experienceYears || 5,
                    clinicName: docRec?.clinic_name || docRec?.clinics?.clinic_name || docRec?.clinicName || tokenMeta.clinicName || '',
                    clinicAddress: docRec?.clinic_address || docRec?.clinics?.location || docRec?.clinicAddress || tokenMeta.clinicAddress || '',
                    city: docRec?.city || user.city || tokenMeta.city || '',
                    state: docRec?.state || user.state || tokenMeta.state || '',
                    pincode: docRec?.pincode || user.pincode || tokenMeta.pincode || '',
                    latitude: parsedDocLat,
                    longitude: parsedDocLng,
                    licenseNumber: docRec?.license_number || docRec?.licenseNumber || tokenMeta.licenseNumber || 'MED-LIC-REG',
                    languages: docLanguages,
                    verificationStatus: docRec?.verification_status || 'VERIFIED',
                    availability_status: docRec?.availability_status || 'Available',
                    isAvailable: docRec ? isDoctorRecordAvailable(docRec) : true
                };
            } catch (_) { }
        }

        let clinicExtra = {};
        if (userRoleStr.includes('clinic')) {
            try {
                const cName = (tokenMeta.clinicName || user.name || '').toString().trim();
                const clinicRec = await Clinic.findOne({ user_id: user.id })
                    || (cName ? await Clinic.findOne({ clinic_name: cName }) : null);
                const resolvedClinicAddr = clinicRec?.clinic_address || clinicRec?.location || tokenMeta.clinicAddress || tokenMeta.location || '';
                const resolvedClinicLat = clinicRec?.latitude ?? user.latitude ?? tokenMeta.latitude ?? null;
                const resolvedClinicLng = clinicRec?.longitude ?? user.longitude ?? tokenMeta.longitude ?? null;
                clinicExtra = {
                    clinicId: clinicRec?.id || null,
                    clinicName: clinicRec?.clinic_name || cName,
                    clinicAddress: resolvedClinicAddr,
                    clinicLocation: resolvedClinicAddr,
                    city: clinicRec?.city || user.city || tokenMeta.city || '',
                    state: clinicRec?.state || user.state || tokenMeta.state || '',
                    pincode: clinicRec?.pincode || user.pincode || tokenMeta.pincode || '',
                    latitude: resolvedClinicLat !== null && Number.isFinite(Number(resolvedClinicLat)) ? Number(resolvedClinicLat) : null,
                    longitude: resolvedClinicLng !== null && Number.isFinite(Number(resolvedClinicLng)) ? Number(resolvedClinicLng) : null,
                };
            } catch (_) { }
        }

        let subAdminExtra = {};
        if (isSubAdminUser) {
            try {
                const { SubAdminDistrict } = require('../models/Schemas');
                const assignedDistricts = await SubAdminDistrict.getDistrictsForSubAdmin(user.id);
                subAdminExtra = {
                    assignedDistricts,
                    districts: assignedDistricts,
                    districtIds: (assignedDistricts || []).map(d => d.district_id || d.id).filter(Boolean)
                };
            } catch (_) { }
        }

        const rtBundle = isSubAdminUser
            ? null
            : await tryMintSupabaseRealtimeTokenForUser(
                { ...user, permissions: userPermissions, status: effectiveStatus },
                {
                    dentistId: doctorExtra.dentistId || null,
                    clinicId: clinicExtra.clinicId || doctorExtra.clinicId || null,
                }
            ).catch(() => null);

        res.json({
            success: true,
            message: 'Login successful.',
            accessToken,
            refreshToken,
            ...(rtBundle ? {
                realtimeToken: rtBundle.realtimeToken,
                realtimeTokenExpiresAt: rtBundle.realtimeTokenExpiresAt,
            } : {}),
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
                ...doctorExtra,
                ...clinicExtra,
                ...subAdminExtra
            }
        });
    } catch (err) {
        console.error('Login Error:', err.message);
        res.status(500).json({ success: false, message: 'Server login error.' });
    }
};

// 5-6. FORGOT / RESET PASSWORD live below using otpStoreService & strict OTP verification

// 7. REFRESH TOKEN
exports.refreshToken = async (req, res) => {
    const token = req.body.refreshToken || req.body.token;
    if (!token) {
        return res.status(401).json({ success: false, message: 'Refresh Token Required.' });
    }

    try {
        const decoded = /** @type {any} */ (jwt.verify(token, getRefreshSecret()));
        const user = await User.findById(decoded.id);
        if (!user) {
            return res.status(403).json({ success: false, message: 'User account not found.' });
        }

        const roleLower = (user.role || '').toString().trim().toLowerCase();
        const isSubAdmin = roleLower === 'sub-admin' || roleLower === 'subadmin' || roleLower === 'sub_admin';
        const effectiveStatus = (user.status || 'ACTIVE').toString().trim().toUpperCase();
        if (isSubAdmin && (effectiveStatus === 'INACTIVE' || effectiveStatus === 'DEACTIVATED')) {
            return res.status(403).json({
                success: false,
                code: 'ACCOUNT_DEACTIVATED',
                message: 'Access Denied: Your Sub-Admin account has been deactivated by the Main Admin.'
            });
        }
        if (isSubAdmin && user.device_token && typeof user.device_token === 'string' && user.device_token.trim().startsWith('{')) {
            try {
                const meta = JSON.parse(user.device_token);
                if (meta.revokedBefore && decoded.iat && (decoded.iat * 1000) < Number(meta.revokedBefore)) {
                    return res.status(403).json({
                        success: false,
                        code: 'ACCOUNT_DEACTIVATED',
                        message: 'Session invalidated by administrator. Please sign in again.'
                    });
                }
            } catch (_) { }
        }

        const { accessToken, refreshToken: newRefreshToken } = generateTokens(user);
        const rtBundle = isSubAdmin
            ? null
            : await tryMintSupabaseRealtimeTokenForUser(user).catch(() => null);
        res.json({
            success: true,
            accessToken,
            refreshToken: newRefreshToken,
            ...(rtBundle ? {
                realtimeToken: rtBundle.realtimeToken,
                realtimeTokenExpiresAt: rtBundle.realtimeTokenExpiresAt,
            } : {})
        });
    } catch (err) {
        res.status(403).json({ success: false, message: 'Invalid or expired refresh token.' });
    }
};

// 7b. MINT / REFRESH SHORT-LIVED SUPABASE REALTIME JWT (Authenticated via Express JWT)
exports.getRealtimeToken = async (req, res) => {
    try {
        if (!req.user || !req.user.id) {
            return res.status(401).json({ success: false, message: 'Authentication required.' });
        }

        const dbUser = await User.findById(req.user.id);
        if (!dbUser) {
            return res.status(404).json({ success: false, message: 'User account not found.' });
        }

        if (normalizeRealtimeAppRole(dbUser.role) === 'SUB_ADMIN') {
            return res.status(403).json({
                success: false,
                code: 'CHAT_FORBIDDEN_FOR_ROLE',
                message: 'Access Denied: Sub-Admins are strictly prohibited from chat and Realtime chat subscriptions.'
            });
        }

        const rtBundle = await mintSupabaseRealtimeTokenForUser(dbUser);
        return res.json({
            success: true,
            realtimeToken: rtBundle.realtimeToken,
            realtimeTokenExpiresAt: rtBundle.realtimeTokenExpiresAt,
            expiresIn: rtBundle.expiresIn,
            claims: {
                sub: rtBundle.claims.sub,
                aud: rtBundle.claims.aud,
                role: rtBundle.claims.role,
                appRole: rtBundle.claims.app_role,
                dentistId: rtBundle.claims.dentist_id,
                clinicId: rtBundle.claims.clinic_id,
            }
        });
    } catch (err) {
        const status = err.statusCode || 500;
        return res.status(status).json({
            success: false,
            ...(err.code ? { code: err.code } : {}),
            message: err.message || 'Unable to generate Supabase Realtime token.'
        });
    }
};

// 8. RESET DATABASE (Strictly blocked in cloud environments and disabled unless explicitly enabled locally)
exports.resetDatabase = async (req, res) => {
    try {
        if (isCloudEnv() || process.env.ALLOW_DANGEROUS_DB_RESET !== 'true') {
            return res.status(403).json({
                success: false,
                message: 'Database reset endpoint is disabled for security.'
            });
        }
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
        const adminUsers = await User.find({ role: { $in: ['Admin', 'ADMIN', 'Sub-Admin', 'SUB_ADMIN'] } });
        const adminEmails = new Set(adminUsers.map(u => (u.email || '').trim().toLowerCase()));

        const dbPatients = await User.find({ role: 'Patient' });
        const patientMap = new Map();

        const seenEmails = new Set();
        const seenPhones = new Set();
        const nonPatientUsers = await User.find({ role: { $in: ['Admin', 'ADMIN', 'Sub-Admin', 'SUB_ADMIN', 'Dentist', 'Doctor', 'DOCTOR', 'Clinic'] } }).catch(() => []);
        const nonPatientIds = new Set(nonPatientUsers.map(u => String(u.id || '').trim()).filter(Boolean));
        const nonPatientEmails = new Set(nonPatientUsers.map(u => (u.email || '').trim().toLowerCase()).filter(Boolean));
        const normalizePhone10 = (raw) => {
            const digits = (raw || '').toString().replace(/\D/g, '');
            return digits.length >= 10 ? digits.slice(-10) : digits;
        };

        for (const p of dbPatients) {
            const pEmail = (p.email || '').trim().toLowerCase();
            const pPhone10 = normalizePhone10(p.phone);
            if (adminEmails.has(pEmail) || nonPatientEmails.has(pEmail) || (p.role && p.role.toLowerCase().includes('admin'))) {
                continue;
            }
            if (patientMap.has(p.id)) continue;
            if (pEmail && seenEmails.has(pEmail)) continue;
            if (pPhone10.length >= 10 && seenPhones.has(pPhone10)) continue;

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
                } catch (_) { }
            }

            if (pEmail) seenEmails.add(pEmail);
            if (pPhone10.length >= 10) seenPhones.add(pPhone10);

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
        } catch (_) { }

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
                } catch (_) { }
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
                status: (s.status || 'ACTIVE').toString().trim().toUpperCase(),
                city: sCity,
                pincode: sPin,
                languages: userLangs,
                permissions: perms,
                assignedDistricts,
                assignedPatientsCount,
                created_at: s.created_at,
                updated_at: s.status_updated_at || s.updated_at || s.created_at,
                updated_by: s.status_updated_by || null,
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
        const targetRoleLower = (target.role || '').toString().trim().toLowerCase();
        if (targetRoleLower === 'admin' || targetRoleLower === 'primaryadmin' || targetRoleLower === 'superadmin') {
            return res.status(403).json({ success: false, message: 'Cannot deactivate Primary Admin.' });
        }

        let newStatus = 'ACTIVE';
        if (status) {
            const parsed = status.toString().trim().toUpperCase();
            if (parsed === 'DEACTIVATED' || parsed === 'INACTIVE' || parsed === 'DISABLED') {
                newStatus = 'INACTIVE';
            } else if (parsed === 'ACTIVE' || parsed === 'ENABLED') {
                newStatus = 'ACTIVE';
            } else {
                return res.status(400).json({ success: false, message: `Invalid status '${status}'. Use ACTIVE or INACTIVE.` });
            }
        } else if (is_active !== undefined) {
            newStatus = (is_active === true || is_active === 'true' || is_active === 1) ? 'ACTIVE' : 'INACTIVE';
        } else {
            newStatus = (target.status || 'ACTIVE').toString().toUpperCase() === 'INACTIVE' ? 'ACTIVE' : 'INACTIVE';
        }

        const updatedAtIso = new Date().toISOString();
        const updatedById = req.user?.id || null;

        const updatePayload = {
            status: newStatus,
            status_updated_at: updatedAtIso,
            status_updated_by: updatedById,
            ...(newStatus === 'INACTIVE' ? { refresh_tokens: [] } : {})
        };

        const updated = await User.findByIdAndUpdate(id, updatePayload);

        // Best-effort sync to Supabase Auth ban/metadata + audit log
        try {
            const { supabaseAdmin } = require('../config/supabase');
            if (supabaseAdmin?.auth?.admin?.updateUserById) {
                await supabaseAdmin.auth.admin.updateUserById(id, {
                    user_metadata: { status: newStatus, statusUpdatedAt: updatedAtIso, statusUpdatedBy: updatedById },
                    ban_duration: newStatus === 'INACTIVE' ? '876000h' : 'none'
                });
            }
        } catch (_) { }

        try {
            const { AuditLog } = require('../models/Schemas');
            await AuditLog.create({
                user_id: updatedById,
                user_email: req.user?.email || 'admin',
                user_role: req.user?.role || 'Admin',
                action: newStatus === 'INACTIVE' ? 'SUB_ADMIN_DEACTIVATED' : 'SUB_ADMIN_ACTIVATED',
                target_resource: id,
                details: { subAdminName: target.name, previousStatus: target.status || 'ACTIVE', newStatus, updatedAt: updatedAtIso },
                ip_address: req.ip || '127.0.0.1'
            });
        } catch (_) { }

        res.json({
            success: true,
            message: newStatus === 'INACTIVE'
                ? `Sub-Admin '${target.name}' has been deactivated and active sessions invalidated.`
                : `Sub-Admin '${target.name}' has been reactivated.`,
            subAdmin: {
                id: updated?.id || id,
                name: updated?.name || target.name,
                email: updated?.email || target.email || '',
                phone: updated?.phone || target.phone || '',
                status: newStatus,
                is_active: newStatus === 'ACTIVE',
                updated_at: updatedAtIso,
                updated_by: updatedById
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
        } catch (_) { }

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

// Production-safe shared OTP storage service (Supabase PostgreSQL RPC with In-memory dev/test fallback)
const { otpStoreService, generateRandomOtp, hashOtp, normalizeKey, isOnScreenOtpTestMode, isPhoneAllowedForOnScreenOtp } = require('../services/otpStoreService');

async function checkOtpRateLimit(identifier) {
    return otpStoreService.checkRateLimit(identifier);
}

async function storeOtp(identifier, code) {
    return otpStoreService.storeOtp(identifier, code);
}

async function verifyStoredOtp(identifier, code) {
    return otpStoreService.verifyOtp(identifier, code);
}

function ensureAuthorizedStagingOtp(req, res, phoneToCheck = null) {
    if (!isOnScreenOtpTestMode()) return true;
    const stagingAuth = isAuthorizedStagingOtpRequest(req);
    if (!stagingAuth.authorized) {
        res.status(403).json({
            success: false,
            code: 'STAGING_OTP_KEY_REQUIRED',
            message: 'Valid staging OTP access key is required for on-screen OTP testing.'
        });
        return false;
    }
    if (phoneToCheck && !isPhoneAllowedForOnScreenOtp(phoneToCheck)) {
        res.status(403).json({
            success: false,
            message: 'On-screen testing OTP is restricted to approved testing numbers.'
        });
        return false;
    }
    return true;
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

        const phoneValidation = normalizePhoneNumber(pNum);
        if (!phoneValidation.isValid) {
            return res.status(400).json({
                success: false,
                message: 'Invalid mobile phone number format. Minimum 10 digits required.'
            });
        }

        const normalizedPhone = normalizeAdminPhone(pNum);
        let isAdmin = false;
        if (/^\d{10}$/.test(normalizedPhone)) {
            try {
                const matchedUser = await User.findByMobile(pNum)
                    || await User.findOne({ phone: normalizedPhone });
                const adminCheck = evaluateMainAdminAuthorization({
                    user: matchedUser,
                    normalizedPhone,
                    isPhoneAuth: true
                });
                isAdmin = adminCheck.authorized;
            } catch (_) {
                isAdmin = false;
            }
        }

        if (!ensureAuthorizedStagingOtp(req, res, pNum)) {
            return;
        }

        const realOtp = generateRandomOtp();

        // Atomically enforce cooldown + rate limits and store HMAC-hashed OTP before SMS dispatch
        const storeResult = await otpStoreService.requestAndStoreOtp(pNum, realOtp);
        if (!storeResult.allowed) {
            return res.status(storeResult.status || 429).json({
                success: false,
                message: storeResult.message
            });
        }

        // Send Mobile SMS (or short-circuit when local testing-only OTP_DELIVERY_MODE=on_screen is active)
        const smsResult = await sendRealSmsOtp(pNum, realOtp);
        if (!smsResult.success && !smsResult.simulated) {
            // Safely invalidate stored OTP challenge & roll back cooldown on carrier dispatch failure
            await otpStoreService.invalidateOtp(pNum, true).catch(() => { });
            return res.status(502).json({
                success: false,
                message: smsResult.error || 'SMS carrier gateway failed to dispatch verification code.'
            });
        }

        // Local Testing-Only On-Screen OTP Response (NODE_ENV !== 'production' && OTP_DELIVERY_MODE === 'on_screen')
        // Production (NODE_ENV === 'production') NEVER enters this branch and NEVER exposes OTP in API responses.
        if (isOnScreenOtpTestMode()) {
            return res.json({
                success: true,
                message: 'Verification code ready on screen (testing mode).',
                otp: realOtp,
                deliveryMode: 'on_screen',
                isAdmin: isAdmin
            });
        }

        // Production / Standard Response: NEVER expose OTP value in API response
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
        const otpTargetKey = normalizeKey(pNum || eMail);
        let verification = { valid: false, message: 'Phone number or email is required.' };
        if (otpTargetKey) {
            verification = await verifyStoredOtp(otpTargetKey, code);
        }

        if (!verification.valid) {
            return res.status(400).json({
                success: false,
                message: verification.message || 'Invalid or expired OTP.'
            });
        }

        const requestedRoleLower = (req.body.role || '').toString().trim().toLowerCase();
        const isReqSubAdmin = isSubAdminRole(requestedRoleLower);
        const isReqMainAdmin = requestedRoleLower.includes('admin') && !isReqSubAdmin;

        const user = (pNum ? await User.findByMobile(pNum) : null)
            || (pNum ? await User.findOne({ phone: pNum }) : null)
            || (normalizedPhone ? await User.findOne({ phone: normalizedPhone }) : null)
            || (eMail ? await User.findOne({ email: eMail.toLowerCase() }) : null)
            || (eMail ? await User.findOne({ email: eMail }) : null);

        if (user) {
            const roleLower = (user.role || '').toString().trim().toLowerCase();
            const isSubAdminUser = isSubAdminRole(roleLower);
            const isStrictMainAdminRole = isMainAdminRole(roleLower);
            const tokenMeta = parseUserTokenMeta(user);
            const effectiveStatus = getEffectiveUserStatus(user, tokenMeta);

            const mainAdminAuth = evaluateMainAdminAuthorization({
                user,
                normalizedPhone,
                isPhoneAuth: Boolean(pNum)
            });

            if (isStrictMainAdminRole && mainAdminAuth.reason === 'ACCOUNT_DEACTIVATED') {
                return res.status(403).json({
                    success: false,
                    code: 'ACCOUNT_DEACTIVATED',
                    message: 'Access Denied: Your Admin account is currently inactive or deactivated.'
                });
            }

            if (isStrictMainAdminRole && !mainAdminAuth.authorized) {
                return res.status(403).json({
                    success: false,
                    message: 'Unauthorized Admin access. OTP verification alone cannot grant Admin access.'
                });
            }

            if (isSubAdminUser && !isAccountActive(user, tokenMeta)) {
                return res.status(403).json({
                    success: false,
                    code: 'ACCOUNT_DEACTIVATED',
                    message: 'Access Denied: Your Sub-Admin account has been deactivated by the Main Admin. Please contact the administrator.'
                });
            }

            if ((isReqMainAdmin || isReqSubAdmin) && !mainAdminAuth.authorized && !isSubAdminUser) {
                return res.status(403).json({
                    success: false,
                    message: 'Unauthorized Admin access. OTP verification alone cannot grant Admin access.'
                });
            }

            const isAdmin = mainAdminAuth.authorized;

            let resolvedPermissions = Array.isArray(user.permissions) && user.permissions.length > 0
                ? user.permissions
                : (Array.isArray(tokenMeta.permissions) ? tokenMeta.permissions : []);
            let resolvedDistricts = Array.isArray(user.districts) ? user.districts : [];
            let resolvedDistrictIds = Array.isArray(user.districtIds) ? user.districtIds : [];

            if (isSubAdminUser) {
                try {
                    const { SubAdminPermission, SubAdminDistrict } = require('../models/Schemas');
                    if (resolvedPermissions.length === 0) {
                        resolvedPermissions = await SubAdminPermission.getPermissionsForUser(user.id);
                    }
                    const dList = await SubAdminDistrict.getDistrictsForSubAdmin(user.id);
                    if (Array.isArray(dList) && dList.length > 0) {
                        resolvedDistricts = dList;
                        resolvedDistrictIds = dList.map(d => d.district_id || d.id).filter(Boolean);
                    }
                } catch (_) { }
            }

            const { accessToken, refreshToken } = generateTokens({ ...user, permissions: resolvedPermissions });
            const existingTokens = Array.isArray(user.refresh_tokens) ? user.refresh_tokens : [];
            if (!existingTokens.includes(refreshToken)) existingTokens.push(refreshToken);
            await User.findByIdAndUpdate(user.id, { refresh_tokens: existingTokens.slice(-20) });

            const userRoleStr = roleLower;
            let resolvedUserLanguages = Array.isArray(user.languages) && user.languages.length > 0 ? user.languages : (tokenMeta.languages || ['English']);
            let doctorExtra = {};
            if (userRoleStr.includes('dentist') || userRoleStr.includes('doctor')) {
                try {
                    const docRec = await Dentist.findById(user.id) || await Dentist.findOne({ user_id: user.id });
                    const resolvedSpec = docRec?.speciality || docRec?.specialty || tokenMeta.specialty || 'General Medicine';
                    const docLanguages = docRec ? extractDoctorLanguages({ ...docRec, users: user }) : resolvedUserLanguages;
                    resolvedUserLanguages = docLanguages;
                    doctorExtra = {
                        dentistId: docRec?.id || user.id,
                        userId: user.id,
                        clinicId: docRec?.clinic_id || null,
                        specialty: resolvedSpec,
                        qualification: docRec?.qualifications || docRec?.qualification || tokenMeta.qualification || getDefaultQualificationForSpecialty(resolvedSpec),
                        experienceYears: docRec?.experience_years || docRec?.experienceYears || tokenMeta.experienceYears || 5,
                        clinicName: docRec?.clinics?.clinic_name || docRec?.clinicName || tokenMeta.clinicName || '',
                        licenseNumber: docRec?.license_number || docRec?.licenseNumber || tokenMeta.licenseNumber || 'MED-LIC-REG',
                        languages: docLanguages,
                        verificationStatus: docRec?.verification_status || 'VERIFIED',
                        availability_status: docRec?.availability_status || 'Available',
                        isAvailable: docRec ? isDoctorRecordAvailable(docRec) : true
                    };
                } catch (_) { }
            }

            let clinicExtra = {};
            if (userRoleStr.includes('clinic')) {
                try {
                    const cName = (tokenMeta.clinicName || user.name || '').toString().trim();
                    const clinicRec = await Clinic.findOne({ user_id: user.id })
                        || (cName ? await Clinic.findOne({ clinic_name: cName }) : null);
                    const resolvedClinicAddr = clinicRec?.clinic_address || clinicRec?.location || tokenMeta.clinicAddress || tokenMeta.location || '';
                    const resolvedClinicLat = clinicRec?.latitude ?? user.latitude ?? tokenMeta.latitude ?? null;
                    const resolvedClinicLng = clinicRec?.longitude ?? user.longitude ?? tokenMeta.longitude ?? null;
                    clinicExtra = {
                        clinicId: clinicRec?.id || null,
                        clinicName: clinicRec?.clinic_name || cName,
                        clinicAddress: resolvedClinicAddr,
                        clinicLocation: resolvedClinicAddr,
                        city: clinicRec?.city || user.city || tokenMeta.city || '',
                        state: clinicRec?.state || user.state || tokenMeta.state || '',
                        pincode: clinicRec?.pincode || user.pincode || tokenMeta.pincode || '',
                        latitude: resolvedClinicLat !== null && Number.isFinite(Number(resolvedClinicLat)) ? Number(resolvedClinicLat) : null,
                        longitude: resolvedClinicLng !== null && Number.isFinite(Number(resolvedClinicLng)) ? Number(resolvedClinicLng) : null,
                    };
                } catch (_) { }
            }

            const rtBundle = isSubAdminUser
                ? null
                : await tryMintSupabaseRealtimeTokenForUser(
                    { ...user, permissions: resolvedPermissions, status: effectiveStatus },
                    {
                        dentistId: doctorExtra.dentistId || null,
                        clinicId: clinicExtra.clinicId || doctorExtra.clinicId || null,
                    }
                ).catch(() => null);

            return res.json({
                success: true,
                message: 'OTP verified successfully.',
                user: {
                    id: user.id,
                    name: user.name,
                    email: user.email,
                    role: user.role,
                    phone: user.phone,
                    city: user.city || tokenMeta.city || '',
                    pincode: user.pincode || tokenMeta.pincode || '',
                    age: user.age || tokenMeta.age || '',
                    gender: user.gender || tokenMeta.gender || '',
                    bloodGroup: user.blood_group || tokenMeta.bloodGroup || '',
                    emergencyContact: user.emergency_contact || tokenMeta.emergencyContact || '',
                    languages: resolvedUserLanguages,
                    profilePhoto: user.biometric_token || null,
                    isProfileComplete: isPatientProfileComplete(user, tokenMeta),
                    permissions: resolvedPermissions,
                    status: effectiveStatus,
                    districtIds: resolvedDistrictIds,
                    districts: resolvedDistricts,
                    assignedDistricts: resolvedDistricts,
                    ...doctorExtra,
                    ...clinicExtra
                },
                accessToken,
                refreshToken,
                ...(rtBundle ? {
                    realtimeToken: rtBundle.realtimeToken,
                    realtimeTokenExpiresAt: rtBundle.realtimeTokenExpiresAt,
                } : {}),
                isAdmin: isAdmin,
                isSubAdmin: isSubAdminUser
            });
        }

        if (isReqMainAdmin || isReqSubAdmin) {
            return res.status(403).json({
                success: false,
                message: 'Unauthorized Admin access. OTP verification alone cannot grant Admin access.'
            });
        }

        const shouldAutoCreatePatient = req.body.autoCreatePatient === true
            && Boolean(pNum)
            && (requestedRoleLower === '' || requestedRoleLower === 'patient');

        if (shouldAutoCreatePatient) {
            const canonical10 = canonicalPhone10(pNum);
            if (/^\d{10}$/.test(canonical10)) {
                // Re-check canonical mobile across variants to guarantee zero duplicate rows
                let patientUser = await User.findByMobile(canonical10);
                let isNewPatient = false;

                if (!patientUser) {
                    const cleanEmail = (eMail && eMail.includes('@') && !eMail.endsWith('@dentaguru.internal'))
                        ? eMail.toLowerCase()
                        : `user_${canonical10}@dentaguru.internal`;
                    const generatedRefCode = `DG-PAT${canonical10.slice(-4)}`;
                    const metaObj = {
                        age: '',
                        gender: '',
                        bloodGroup: '',
                        emergencyContact: '',
                        city: '',
                        pincode: '',
                        languages: ['English'],
                        referral_code: generatedRefCode,
                        profileCompleted: false
                    };
                    const internalPass = `OTP_SECURE_${crypto.randomBytes(12).toString('hex')}`;

                    patientUser = await User.create({
                        name: 'Patient',
                        email: cleanEmail,
                        password: internalPass,
                        phone: canonical10,
                        role: 'Patient',
                        city: '',
                        pincode: '',
                        age: '',
                        gender: '',
                        languages: ['English'],
                        referral_code: generatedRefCode,
                        device_token: JSON.stringify(metaObj),
                        biometric_token: null
                    });
                    isNewPatient = true;
                }

                const { accessToken, refreshToken } = generateTokens(patientUser);
                const existingTokens = Array.isArray(patientUser.refresh_tokens) ? [...patientUser.refresh_tokens] : [];
                if (!existingTokens.includes(refreshToken)) existingTokens.push(refreshToken);
                await User.findByIdAndUpdate(patientUser.id, {
                    refresh_tokens: existingTokens.slice(-20)
                }).catch(() => null);

                const rtBundle = await tryMintSupabaseRealtimeTokenForUser(patientUser).catch(() => null);

                return res.json({
                    success: true,
                    message: 'OTP verified successfully.',
                    isNewPatient,
                    user: buildPatientUserPayload(patientUser),
                    accessToken,
                    refreshToken,
                    ...(rtBundle ? {
                        realtimeToken: rtBundle.realtimeToken,
                        realtimeTokenExpiresAt: rtBundle.realtimeTokenExpiresAt,
                    } : {}),
                    isAdmin: false,
                    isSubAdmin: false
                });
            }
        }

        res.json({
            success: true,
            verified: true,
            message: 'OTP verified successfully.',
            isAdmin: false
        });
    } catch (err) {
        res.status(500).json({ success: false, message: 'Verification failed.' });
    }
};

// 3b. AUTHENTICATED PATIENT PROFILE READ & DEFERRED COMPLETION UPDATE
exports.getPatientProfile = async (req, res) => {
    try {
        const userId = req.user?.id;
        if (!userId) {
            return res.status(401).json({ success: false, message: 'Authentication required.' });
        }
        const user = await User.findById(userId);
        if (!user) {
            return res.status(404).json({ success: false, message: 'Patient account not found.' });
        }
        return res.json({
            success: true,
            user: buildPatientUserPayload(user),
            profileRequirements: PATIENT_PROFILE_REQUIREMENTS,
        });
    } catch (err) {
        console.error('Get Patient Profile Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to load patient profile.' });
    }
};

exports.updatePatientProfile = async (req, res) => {
    try {
        const userId = req.user?.id;
        if (!userId) {
            return res.status(401).json({ success: false, message: 'Authentication required.' });
        }

        const existingUser = await User.findById(userId);
        if (!existingUser) {
            return res.status(404).json({ success: false, message: 'Patient account not found.' });
        }

        const roleLower = (existingUser.role || 'Patient').toString().trim().toLowerCase();
        if (roleLower && roleLower !== 'patient') {
            return res.status(403).json({
                success: false,
                message: 'Patient profile endpoint can only update Patient accounts.'
            });
        }

        const existingMeta = parseUserTokenMeta(existingUser);
        const {
            name,
            city,
            address,
            bloodGroup,
            emergencyContact,
            languages,
            pincode,
            age,
            gender,
            profilePhoto,
            completeProfile
        } = req.body || {};

        const requireComplete = completeProfile !== false;

        const nextPincode = pincode !== undefined
            ? String(pincode || '').trim()
            : String(existingUser.pincode || existingMeta.pincode || '').trim();
        const nextAge = age !== undefined
            ? String(age || '').trim()
            : String(existingUser.age || existingMeta.age || '').trim();
        const nextGender = gender !== undefined
            ? String(gender || '').trim()
            : String(existingUser.gender || existingMeta.gender || '').trim();
        const incomingPhoto = profilePhoto !== undefined && profilePhoto !== null
            ? String(profilePhoto).trim()
            : '';
        const nextPhoto = incomingPhoto.length > 0
            ? incomingPhoto
            : String(existingUser.biometric_token || existingMeta.profilePhoto || '').trim();
        const nextName = name !== undefined
            ? String(name || '').trim()
            : String(existingUser.name || existingMeta.name || '').trim();
        const nextAddress = address !== undefined
            ? String(address || '').trim()
            : String(existingUser.address || existingMeta.address || '').trim();
        const nextBloodGroup = bloodGroup !== undefined
            ? String(bloodGroup || '').trim()
            : String(existingUser.blood_group || existingMeta.bloodGroup || '').trim();
        const nextLanguages = Array.isArray(languages)
            ? languages.map(l => String(l || '').trim()).filter(Boolean)
            : (Array.isArray(existingUser.languages) && existingUser.languages.length > 0
                ? existingUser.languages
                : (Array.isArray(existingMeta.languages) ? existingMeta.languages : []));

        if (requireComplete) {
            if (PATIENT_PROFILE_REQUIREMENTS.requireProfileImage && (!nextPhoto || nextPhoto.toLowerCase() === 'null')) {
                return res.status(400).json({ success: false, message: 'Profile image is required.' });
            }
            if (PATIENT_PROFILE_REQUIREMENTS.requireFullName && (!nextName || nextName.toLowerCase() === 'patient' || nextName.toLowerCase() === 'null')) {
                return res.status(400).json({ success: false, message: 'Full name is required.' });
            }
            if (PATIENT_PROFILE_REQUIREMENTS.requireAddress && (!nextAddress || nextAddress.toLowerCase() === 'null')) {
                return res.status(400).json({ success: false, message: 'Address is required.' });
            }
            if ((PATIENT_PROFILE_REQUIREMENTS.requirePincode || nextPincode.length > 0) && !/^\d{6}$/.test(nextPincode)) {
                return res.status(400).json({ success: false, message: 'Please enter a valid 6-digit pincode.' });
            }
            const ageInt = parseInt(nextAge, 10);
            if ((PATIENT_PROFILE_REQUIREMENTS.requireAge || nextAge.length > 0) && (!/^\d+$/.test(nextAge) || Number.isNaN(ageInt) || ageInt < 1 || ageInt > 120)) {
                return res.status(400).json({ success: false, message: 'Please enter a valid age between 1 and 120.' });
            }
            if (PATIENT_PROFILE_REQUIREMENTS.requireGender && (!nextGender || nextGender.toLowerCase() === 'null')) {
                return res.status(400).json({ success: false, message: 'Gender selection is required.' });
            }
            if (PATIENT_PROFILE_REQUIREMENTS.requirePreferredLanguage && nextLanguages.length === 0) {
                return res.status(400).json({ success: false, message: 'Please select at least one preferred language.' });
            }
            if (PATIENT_PROFILE_REQUIREMENTS.requireBloodGroup && (!nextBloodGroup || nextBloodGroup.toLowerCase() === 'null')) {
                return res.status(400).json({ success: false, message: 'Blood group selection is required.' });
            }
        } else {
            if (nextPincode.length > 0 && !/^\d{6}$/.test(nextPincode)) {
                return res.status(400).json({ success: false, message: 'Please enter a valid 6-digit pincode.' });
            }
            if (nextAge.length > 0) {
                const ageInt = parseInt(nextAge, 10);
                if (!/^\d+$/.test(nextAge) || Number.isNaN(ageInt) || ageInt < 1 || ageInt > 120) {
                    return res.status(400).json({ success: false, message: 'Please enter a valid age between 1 and 120.' });
                }
            }
        }

        const updatePayload = {
            pincode: nextPincode,
            age: nextAge,
            gender: nextGender,
        };
        if (nextPhoto.length > 0) {
            updatePayload.biometric_token = nextPhoto;
        }
        if (name !== undefined && String(name).trim().length > 0) {
            updatePayload.name = String(name).trim();
        }
        if (city !== undefined && city !== null && String(city).trim().length > 0) {
            updatePayload.city = String(city).trim();
        }
        if (address !== undefined && address !== null && String(address).trim().length > 0) {
            updatePayload.address = String(address).trim();
        }
        if (bloodGroup !== undefined && bloodGroup !== null && String(bloodGroup).trim().length > 0) {
            updatePayload.blood_group = String(bloodGroup).trim();
        }
        if (emergencyContact !== undefined && emergencyContact !== null && String(emergencyContact).trim().length > 0) {
            updatePayload.emergency_contact = String(emergencyContact).trim();
        }
        if (Array.isArray(languages) && languages.length > 0) {
            updatePayload.languages = languages.map(l => String(l || '').trim()).filter(Boolean);
        }

        const updatedUser = await User.findByIdAndUpdate(existingUser.id, updatePayload);
        return res.json({
            success: true,
            message: 'Patient profile saved successfully.',
            user: buildPatientUserPayload(updatedUser || { ...existingUser, ...updatePayload })
        });
    } catch (err) {
        console.error('Update Patient Profile Error:', err.message);
        res.status(500).json({ success: false, message: err.message || 'Failed to update patient profile.' });
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

        if (!ensureAuthorizedStagingOtp(req, res)) {
            return;
        }

        let user = await User.findOne({ email: identifier });
        if (!user) {
            user = await User.findOne({ phone: identifier });
        }

        if (!user) {
            return res.status(404).json({ success: false, message: 'No registered account found with that email or phone number.' });
        }

        if (!ensureAuthorizedStagingOtp(req, res, user.phone || null)) {
            return;
        }

        const realOtp = generateRandomOtp();
        if (user.phone && user.phone.length >= 10) {
            const pStore = await otpStoreService.requestAndStoreOtp(user.phone, realOtp);
            if (!pStore.allowed) {
                return res.status(pStore.status || 429).json({ success: false, message: pStore.message });
            }
        }
        if (user.email && !user.email.endsWith('@dentaguru.internal')) {
            const eStore = await otpStoreService.requestAndStoreOtp(user.email, realOtp);
            if (!eStore.allowed && (!user.phone || user.phone.length < 10)) {
                return res.status(eStore.status || 429).json({ success: false, message: eStore.message });
            }
        }

        let smsSent = false;
        let smsError = null;
        if (user.phone && user.phone.length >= 10) {
            const smsResult = await sendRealSmsOtp(user.phone, realOtp);
            smsSent = Boolean(smsResult.success || smsResult.simulated);
            if (!smsSent) smsError = smsResult.error;
        }

        let emailSent = false;
        if (user.email && user.email.includes('@') && !user.email.endsWith('@dentaguru.internal')) {
            try {
                await sendOtpEmail(user.email, realOtp, true);
                emailSent = true;
            } catch (e) {
                console.error('Password reset email warning:', e.message);
            }
        }

        if (!smsSent && !emailSent) {
            if (user.phone) await otpStoreService.invalidateOtp(user.phone, true).catch(() => { });
            if (user.email) await otpStoreService.invalidateOtp(user.email, true).catch(() => { });
            return res.status(502).json({
                success: false,
                message: smsError || 'Failed to dispatch password reset verification code.'
            });
        }

        // Local Testing-Only On-Screen OTP Response for Forgot Password (never active in production)
        if (isOnScreenOtpTestMode() && (!user.phone || isPhoneAllowedForOnScreenOtp(user.phone))) {
            return res.json({
                success: true,
                message: 'Password reset verification code ready on screen (testing mode).',
                otp: realOtp,
                deliveryMode: 'on_screen'
            });
        }

        res.json({
            success: true,
            message: 'Password reset verification code sent. Please check your SMS/email.'
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

        const otpTargetKey = normalizeKey(phone || email);
        const otpVerification = await verifyStoredOtp(otpTargetKey, code);
        if (!otpVerification.valid) {
            return res.status(400).json({
                success: false,
                message: otpVerification.message || 'Invalid or expired reset OTP code.'
            });
        }

        let user = await User.findOne({ email: identifier });
        if (!user) {
            user = await User.findOne({ phone: identifier });
        }

        if (!user) {
            return res.status(404).json({ success: false, message: 'User account not found.' });
        }

        // Update password in Supabase PostgreSQL and revoke prior refresh tokens
        await User.findByIdAndUpdate(user.id, {
            password: newPassword.trim(),
            refresh_tokens: []
        });

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

// (Active exports.refreshToken with Sub-Admin revocation enforcement is defined in section 7 above.)

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

// 6. UPDATE FCM DEVICE TOKEN (Firebase Push Notifications — non-destructive merge)
exports.updateFcmToken = async (req, res) => {
    const { fcmToken } = req.body;
    if (!fcmToken || typeof fcmToken !== 'string' || !fcmToken.trim()) {
        return res.status(400).json({ success: false, message: 'fcmToken is required.' });
    }
    try {
        await User.updateFcmToken(req.user.id, fcmToken.trim());
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
            const rawSyncRole = String(role || sbUser.user_metadata?.role || 'Patient').trim();
            const lowerSyncRole = rawSyncRole.toLowerCase();
            const canonicalSyncRole = (lowerSyncRole === 'dentist' || lowerSyncRole === 'doctor') ? 'DOCTOR' : rawSyncRole;
            dbUser = await User.create({
                name: name || sbUser.user_metadata?.full_name || sbUser.email.split('@')[0],
                email: sbUser.email,
                password: `sb_${sbUser.id.substring(0, 12)}`,
                phone: phone || sbUser.phone || `+1000${Math.floor(1000000 + Math.random() * 9000000)}`,
                role: canonicalSyncRole
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

exports._resolveAndUploadProfilePhoto = resolveAndUploadProfilePhoto;
exports._PATIENT_PROFILE_REQUIREMENTS = PATIENT_PROFILE_REQUIREMENTS;
exports._evaluateMainAdminAuthorization = evaluateMainAdminAuthorization;
exports._getConfiguredEnvAdminPhones = getConfiguredEnvAdminPhones;
exports._isMainAdminRole = isMainAdminRole;
exports._isAccountActive = isAccountActive;

