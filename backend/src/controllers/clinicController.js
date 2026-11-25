const { supabaseAdmin } = require('../config/supabase');
const { isCloudEnv } = require('../config/secrets');
const {
    User,
    Clinic,
    Dentist,
    Notification,
    resolveClinicIds,
    resolveMedicalSpecialtyRecord,
    matchesSpecialtyQuery,
    getDefaultQualificationForSpecialty,
    isDoctorRecordAvailable,
    normalizeAvailabilityStatus,
    normalizeLanguagesList,
    parseLanguageFilters,
    extractDoctorLanguages,
    doctorMatchesLanguages,
    mergeSupportedAndDoctorLanguages
} = require('../models/Schemas');

function isPrivilegedDoctorViewer(req, targetDoctor = null) {
    const role = (req.user?.role || '').toString().trim().toLowerCase();
    if (
        role === 'admin' ||
        role === 'superadmin' ||
        role === 'super_admin' ||
        role === 'primaryadmin' ||
        role === 'sub-admin' ||
        role === 'subadmin' ||
        role === 'clinic' ||
        role === 'clinic_admin'
    ) {
        return true;
    }
    if (role === 'dentist' || role === 'doctor') {
        if (!targetDoctor) return true;
        const callerId = String(req.user?.id || '').trim();
        if (!callerId) return false;
        return callerId === String(targetDoctor.id || '').trim() ||
            callerId === String(targetDoctor.user_id || targetDoctor.users?.id || '').trim();
    }
    return false;
}

function formatDentistRecord(d) {
    const uObj = d.users || {};
    const cObj = d.clinics || {};
    const name = d.name || uObj.name || 'Doctor';
    const formattedName = name.startsWith('Dr.') ? name : `Dr. ${name}`;

    const doctorLangs = extractDoctorLanguages(d);

    const resolvedSpec = d.speciality || d.specialty || d.medical_specialties?.name || 'General Medicine';
    const resolvedQual = d.qualifications || d.qualification || getDefaultQualificationForSpecialty(resolvedSpec);
    const availabilityStatus = d.availability_status || d.status || 'Available';
    const isAvailable = isDoctorRecordAvailable(d);
    const normStatusLower = String(availabilityStatus || '').trim().toLowerCase();
    let metaOnline = '';
    if (uObj.device_token && typeof uObj.device_token === 'string' && uObj.device_token.trim().startsWith('{')) {
        try {
            const parsedMeta = JSON.parse(uObj.device_token);
            if (parsedMeta && parsedMeta.onlineStatus) {
                metaOnline = String(parsedMeta.onlineStatus).trim().toLowerCase();
            }
        } catch (_) {}
    }
    const explicitOnline = String(d.online_status || d.onlineStatus || metaOnline || '').trim();
    const explicitOnlineLower = explicitOnline.toLowerCase();
    const isOnline = isAvailable && (explicitOnlineLower
        ? (explicitOnlineLower === 'online' || explicitOnlineLower.includes('busy') || explicitOnlineLower === 'delayed')
        : (normStatusLower === 'online' || normStatusLower === 'available' || normStatusLower.includes('busy') || normStatusLower === 'delayed'));
    const reviewCountVal = Number(d.reviews_count ?? d.reviewCount ?? 0) || 0;
    const resolvedOnlineStatus = !isAvailable
        ? (normStatusLower === 'offline' ? 'Offline' : 'Unavailable')
        : (explicitOnline || (normStatusLower.includes('busy') || normStatusLower === 'delayed' ? availabilityStatus : (isOnline ? 'Online' : 'Offline')));

    return {
        id: d.id,
        user_id: d.user_id || uObj.id,
        clinic_id: d.clinic_id || cObj.id || null,
        clinicId: d.clinic_id || cObj.id || null,
        name: formattedName,
        email: d.email || uObj.email || '',
        phone: d.phone || uObj.phone || '',
        speciality: resolvedSpec,
        specialty: resolvedSpec,
        specialty_id: d.specialty_id || d.medical_specialties?.id || null,
        specialtyId: d.specialty_id || d.medical_specialties?.id || null,
        department: d.department || d.medical_specialties?.department || '',
        license_number: d.license_number || d.licenseNumber || '',
        licenseNumber: d.license_number || d.licenseNumber || '',
        qualification: resolvedQual,
        experienceYears: d.experience_years || d.experienceYears || 5,
        experience_years: d.experience_years || d.experienceYears || 5,
        consultation_fee: d.consultation_fee || d.consultationFee || '',
        consultationFee: d.consultation_fee || d.consultationFee || '',
        bio: d.bio || '',
        rating: reviewCountVal > 0 ? (Number(d.rating) || 0) : 0,
        reviews_count: reviewCountVal,
        clinicName: cObj.clinic_name || d.clinicName || '',
        clinicAddress: cObj.location || d.clinicAddress || d.location || '',
        state: d.state || uObj.state || '',
        city: d.city || uObj.city || '',
        pincode: d.pincode || uObj.pincode || '',
        languages: doctorLangs,
        latitude: d.latitude || uObj.latitude || null,
        longitude: d.longitude || uObj.longitude || null,
        availability_status: availabilityStatus,
        status: availabilityStatus,
        onlineStatus: resolvedOnlineStatus,
        liveStatus: resolvedOnlineStatus,
        isAvailable,
        isOnline,
        verificationStatus: d.verification_status || d.verificationStatus || 'VERIFIED',
        profilePhoto: uObj.biometric_token || d.profilePhoto || null,
        users: uObj,
        clinics: cObj
    };
}

/**
 * Resolve canonical clinic record, clinic identifiers (clinics.id + user_id + clinic_name),
 * and attached doctor IDs for strict multi-clinic scoping across bookings, referrals & notifications.
 */
exports.resolveClinicRecordAndDoctorIds = async (rawClinicIdentifier) => {
    const resolved = await resolveClinicIds(rawClinicIdentifier);
    let clinic = resolved.clinicRecord || (resolved.clinicId ? await Clinic.findById(resolved.clinicId) : null);
    if (!clinic && rawClinicIdentifier) {
        const cleanRaw = String(rawClinicIdentifier).trim();
        clinic = await Clinic.findById(cleanRaw).catch(() => null)
            || await Clinic.findOne({ user_id: cleanRaw }).catch(() => null)
            || await Clinic.findOne({ clinic_name: cleanRaw }).catch(() => null);
    }
    const clinicId = clinic?.id || resolved.clinicId || null;
    const clinicName = (clinic?.clinic_name || resolved.clinicName || '').trim();
    const doctorIds = new Set();

    if (clinicId) {
        const byClinicId = await Dentist.find({ clinic_id: clinicId }).catch(() => []);
        for (const d of (byClinicId || [])) {
            if (d?.id) doctorIds.add(String(d.id));
            if (d?.user_id) doctorIds.add(String(d.user_id));
        }
    }

    if (clinicName && clinicName.toLowerCase() !== 'gs health practice' && clinicName.toLowerCase() !== 'independent practice') {
        const allDocs = await Dentist.find({}).catch(() => []);
        const targetLower = clinicName.toLowerCase();
        for (const d of (allDocs || [])) {
            const cName = (d.clinics?.clinic_name || d.clinicName || '').toString().trim().toLowerCase();
            if (cName && cName === targetLower) {
                if (d?.id) doctorIds.add(String(d.id));
                if (d?.user_id) doctorIds.add(String(d.user_id));
            }
        }
    }

    return {
        clinic,
        clinicId,
        clinicUserId: clinic?.user_id || resolved.clinicUserId || null,
        clinicName,
        allClinicIds: resolved.allIds,
        doctorIds: Array.from(doctorIds),
    };
};

function ensureClinicOrDoctorMutationAuth(req, res) {
    if (req.user) {
        const callerRole = (req.user.role || '').toString().trim().toLowerCase();
        if (callerRole === 'patient') {
            res.status(403).json({
                success: false,
                message: 'Forbidden: Patients are not authorized to modify clinic or doctor records.'
            });
            return false;
        }
        return true;
    }

    if (isCloudEnv() || (req.headers && !req.headers['x-user-id'] && !req.headers.authorization)) {
        res.status(401).json({
            success: false,
            message: 'Authentication required.'
        });
        return false;
    }
    return true;
}

// 1. REGISTER CLINIC PROFILE
exports.registerClinicProfile = async (req, res) => {
    if (!ensureClinicOrDoctorMutationAuth(req, res)) return;
    const { clinicName, location, services, pricing, coordinates } = req.body;
    try {
        const role = req.user?.role || '';
        const cleanName = (clinicName || '').toString().trim();
        if (cleanName) {
            const byName = await Clinic.findOne({ clinic_name: cleanName }).catch(() => null);
            if (byName) {
                if (req.user?.id && !byName.user_id) {
                    await Clinic.findByIdAndUpdate(byName.id, { user_id: req.user.id });
                }
                return res.status(200).json({ success: true, message: 'Existing clinic profile linked.', clinic: byName });
            }
        }
        if (role !== 'SuperAdmin' && role !== 'Admin' && req.user?.id) {
            const clinic = await Clinic.findOne({ user_id: req.user.id });
            if (clinic) {
                return res.status(200).json({ success: true, message: 'Clinic profile already exists.', clinic });
            }
        }

        const clinic = await Clinic.create({
            userId: req.user?.id || null,
            clinicName,
            location,
            services,
            pricing,
            coordinates: coordinates ? { type: 'Point', coordinates } : undefined
        });

        try {
            await Notification.create({
                recipient_role: 'Admin',
                recipient_id: 'ALL_ADMINS',
                title: '🏥 New Clinic Profile Registered',
                message: `Clinic "${clinicName || 'GS Health Clinic'}" registered at ${location || 'Healthcare Hub'}.`,
                type: 'clinic_registered'
            });
        } catch (_) { }

        res.status(201).json({ success: true, message: 'Clinic profile created in Supabase PostgreSQL.', clinic });
    } catch (err) {
        console.error('Clinic Profile Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to create clinic profile.' });
    }
};

// 2. GET ALL CLINICS
exports.getClinics = async (req, res) => {
    const { search, service } = req.query;
    try {
        let query = {};
        if (search) query.clinicName = search;
        if (service) query.services = service;

        const clinics = await Clinic.find(query);
        res.json({ success: true, count: clinics.length, clinics });
    } catch (err) {
        res.status(500).json({ success: false, message: 'Failed to fetch clinics list.' });
    }
};

// 3. GET CLINIC DENTISTS
exports.getClinicDentists = async (req, res) => {
    const { clinicId } = req.params;
    try {
        const includeUnavailableRequested = String(req.query.includeUnavailable || '').trim().toLowerCase() === 'true';
        const allowUnavailable = isPrivilegedDoctorViewer(req) && (includeUnavailableRequested || req.query.includeUnavailable === undefined);

        const resolvedScope = await exports.resolveClinicRecordAndDoctorIds(clinicId);
        const canonicalClinicId = resolvedScope.clinicId || clinicId;
        const rawDentists = canonicalClinicId ? await Dentist.find({ clinic_id: canonicalClinicId }) : [];

        // Also include clinic-named doctors resolved via resolveClinicRecordAndDoctorIds (without losing clinic_id scoping)
        const seenIds = new Set(rawDentists.map(d => String(d.id || '')));
        const seenUserIds = new Set(rawDentists.map(d => String(d.user_id || d.users?.id || '')).filter(Boolean));
        if (resolvedScope.doctorIds && resolvedScope.doctorIds.length > 0) {
            const allDentists = await Dentist.find({});
            const scopedIdSet = new Set(resolvedScope.doctorIds.map(id => String(id)));
            for (const d of (allDentists || [])) {
                if (!seenIds.has(String(d.id || '')) && (scopedIdSet.has(String(d.id || '')) || scopedIdSet.has(String(d.user_id || '')))) {
                    rawDentists.push(d);
                    seenIds.add(String(d.id || ''));
                    if (d.user_id) seenUserIds.add(String(d.user_id));
                }
            }
        }

        // Also include Dentist/Doctor-role user accounts linked via device_token metadata if they don't yet have a dentists row
        if (canonicalClinicId || resolvedScope.clinicName) {
            const doctorRoleUsers = await User.find({ role: { $in: ['DOCTOR', 'Doctor', 'Dentist'] } }).catch(() => []);
            const targetClinicNameLower = (resolvedScope.clinicName || '').trim().toLowerCase();
            for (const u of doctorRoleUsers) {
                const uid = String(u.id || '').trim();
                if (!uid || seenUserIds.has(uid) || seenIds.has(uid)) continue;
                let meta = {};
                if (u.device_token && typeof u.device_token === 'string' && u.device_token.startsWith('{')) {
                    try { meta = JSON.parse(u.device_token); } catch (_) { }
                }
                const metaCid = String(meta.clinicId || meta.clinic_id || '').trim();
                const metaCName = String(meta.clinicName || u.clinic_name || '').trim().toLowerCase();
                const matchesClinic = (canonicalClinicId && metaCid && metaCid === String(canonicalClinicId)) ||
                    (targetClinicNameLower && metaCName && metaCName === targetClinicNameLower);
                if (matchesClinic) {
                    const uSpec = u.specialty || meta.specialty || 'General Medicine';
                    rawDentists.push({
                        id: u.id,
                        user_id: u.id,
                        clinic_id: canonicalClinicId || null,
                        name: u.name,
                        speciality: uSpec,
                        specialty: uSpec,
                        specialty_id: meta.specialtyId || null,
                        department: meta.department || '',
                        qualifications: u.qualification || meta.qualification || getDefaultQualificationForSpecialty(uSpec),
                        experience_years: u.experienceYears || meta.experienceYears || 5,
                        clinicName: resolvedScope.clinicName || meta.clinicName || '',
                        phone: u.phone || '',
                        email: u.email || '',
                        state: u.state || '',
                        city: u.city || '',
                        pincode: u.pincode || '',
                        languages: extractDoctorLanguages({ languages: u.languages, users: u }),
                        availability_status: 'Available',
                        users: u,
                        clinics: resolvedScope.clinic || {}
                    });
                    seenIds.add(uid);
                    seenUserIds.add(uid);
                }
            }
        }

        const formattedDentists = rawDentists.map(formatDentistRecord);
        const visibleDentists = allowUnavailable
            ? formattedDentists
            : formattedDentists.filter(d => d.isAvailable);
        res.json({
            success: true,
            count: visibleDentists.length,
            clinic: resolvedScope.clinic || null,
            dentists: visibleDentists,
            doctors: visibleDentists
        });
    } catch (err) {
        res.status(500).json({ success: false, message: 'Failed to fetch clinic doctors.' });
    }
};

// 4. GET ALL DENTISTS / DOCTORS (with optional state/city/pincode/specialty/search/availability/language filters)
// Enforces Doctor Availability ON/OFF strictly on the backend:
// - Patient / public callers ONLY receive available doctors (OFF doctors are hidden).
// - Admin / Sub-Admin / Clinic / Doctor callers may view unavailable doctors with includeUnavailable=true (or by default for Admin/Clinic/Doctor).
exports.getAllDentists = async (req, res) => {
    try {
        const { state, city, pincode, specialty, speciality, search, availability, language, languages, includeUnavailable } = req.query;
        const effectiveSpecialty = (specialty || speciality || '').trim();
        const searchKw = (search || '').trim().toLowerCase();
        const explicitIncludeUnavailable = String(includeUnavailable || '').trim().toLowerCase() === 'true';
        const explicitHideUnavailable = String(includeUnavailable || '').trim().toLowerCase() === 'false';
        const privilegedCaller = isPrivilegedDoctorViewer(req);
        const allowUnavailable = !explicitHideUnavailable && (explicitIncludeUnavailable || (privilegedCaller && Boolean(req.user)));
        const selectedLangFilters = parseLanguageFilters(languages || language);

        // Fetch all dentist rows before applying location/specialty/language filters so:
        // 1) OFF doctors are never resurrected by User merge,
        // 2) availableLanguages always reflects all eligible registered doctors, and
        // 3) city/pincode/specialty match consistently across dentists, users, and clinics fields.
        const dentists = await Dentist.find({});
        const { User } = require('../models/Schemas');

        // Track ALL existing dentist rows (including OFF ones) so the User fallback merge cannot create duplicate doctor records or resurrect an OFF doctor
        const existingEmails = new Set(dentists.map(d => (d.email || d.users?.email || '').toLowerCase()).filter(Boolean));
        const existingUserIds = new Set(dentists.map(d => String(d.user_id || d.users?.id || d.id || '').trim()).filter(Boolean));
        const normPhone10 = (p) => {
            const digits = String(p || '').replace(/[^0-9]/g, '');
            return digits.length >= 10 ? digits.slice(-10) : digits;
        };
        const existingPhones = new Set(dentists.map(d => normPhone10(d.phone || d.users?.phone)).filter(Boolean));

        // Also fetch user-based dentists / doctors and merge (those not yet in dentists table)
        const dentistUsers = await User.find({ role: { $in: ['DOCTOR', 'Doctor', 'Dentist'] } });

        for (const u of dentistUsers) {
            const emailClean = (u.email || '').toLowerCase();
            const userIdClean = String(u.id || '').trim();
            const phoneClean = normPhone10(u.phone);
            const alreadyMatched = (emailClean && existingEmails.has(emailClean)) ||
                (userIdClean && existingUserIds.has(userIdClean)) ||
                (phoneClean && existingPhones.has(phoneClean));
            if (!alreadyMatched) {
                let userMeta = {};
                if (u.device_token && typeof u.device_token === 'string' && u.device_token.startsWith('{')) {
                    try {
                        userMeta = JSON.parse(u.device_token);
                    } catch (_) { }
                }
                const userLangs = extractDoctorLanguages({ languages: u.languages, users: u });
                const uSpec = u.specialty || userMeta.specialty || 'General Medicine';
                const uQual = u.qualification || userMeta.qualification || getDefaultQualificationForSpecialty(uSpec);
                const uExp = u.experienceYears || userMeta.experienceYears || 5;
                dentists.push({
                    id: u.id,
                    user_id: u.id,
                    name: u.name.startsWith('Dr.') ? u.name : `Dr. ${u.name}`,
                    speciality: uSpec,
                    specialty: uSpec,
                    qualification: uQual,
                    experienceYears: uExp,
                    rating: 5.0,
                    reviews_count: 1,
                    clinicName: u.clinic_name || userMeta.clinicName || '',
                    phone: u.phone || '',
                    email: u.email || '',
                    state: u.state || '',
                    city: u.city || '',
                    pincode: u.pincode || '',
                    languages: userLangs,
                    latitude: u.latitude || null,
                    longitude: u.longitude || null,
                    availability_status: 'Available',
                    license_number: userMeta.licenseNumber || 'MED-LIC-REG',
                    users: { id: u.id, name: u.name, email: u.email, phone: u.phone, state: u.state || '', city: u.city || '', pincode: u.pincode || '', languages: userLangs, latitude: u.latitude, longitude: u.longitude, device_token: u.device_token, biometric_token: u.biometric_token }
                });
                if (emailClean) existingEmails.add(emailClean);
                if (userIdClean) existingUserIds.add(userIdClean);
                if (phoneClean) existingPhones.add(phoneClean);
            }
        }

        let formattedDentists = dentists.map(formatDentistRecord);

        // Enforce Availability ON/OFF & Online presence visibility on backend
        const onlineOnlyRequested = String(req.query.onlineOnly || '').trim().toLowerCase() === 'true';
        if (onlineOnlyRequested) {
            formattedDentists = formattedDentists.filter(d => d.isOnline);
        } else if (availability && availability.trim()) {
            const rawAvailLower = availability.trim().toLowerCase();
            if (rawAvailLower === 'online') {
                formattedDentists = formattedDentists.filter(d => d.isOnline);
            } else {
                const availNormalized = normalizeAvailabilityStatus(availability.trim());
                if (availNormalized === 'Available') {
                    formattedDentists = formattedDentists.filter(d => d.isAvailable);
                } else if (availNormalized === 'Unavailable') {
                    formattedDentists = allowUnavailable ? formattedDentists.filter(d => !d.isAvailable) : [];
                } else {
                    formattedDentists = formattedDentists.filter(d =>
                        (d.availability_status || '').trim().toLowerCase() === rawAvailLower &&
                        (allowUnavailable || d.isAvailable)
                    );
                }
            }
        } else if (!allowUnavailable) {
            formattedDentists = formattedDentists.filter(d => d.isAvailable);
        }

        // Collect supported application languages + all languages spoken by eligible registered doctors
        const availableLanguages = mergeSupportedAndDoctorLanguages(
            formattedDentists.flatMap(d => d.languages || [])
        );

        // Apply combined State, City, Pincode, Specialty, Search, and Language filters at backend level
        if (state && state.trim()) {
            const stateKw = state.trim().toLowerCase();
            formattedDentists = formattedDentists.filter(d =>
                (d.state || '').toLowerCase().includes(stateKw) ||
                (d.location || '').toLowerCase().includes(stateKw)
            );
        }
        if (city && city.trim()) {
            const cityKw = city.trim().toLowerCase();
            formattedDentists = formattedDentists.filter(d =>
                (d.city || '').toLowerCase().includes(cityKw) ||
                (d.state || '').toLowerCase().includes(cityKw) ||
                (d.location || '').toLowerCase().includes(cityKw) ||
                (d.clinicName || '').toLowerCase().includes(cityKw)
            );
        }
        if (pincode && pincode.trim()) {
            const pinKw = pincode.trim().toLowerCase();
            formattedDentists = formattedDentists.filter(d =>
                (d.pincode || '').toLowerCase().includes(pinKw) ||
                (d.location || '').toLowerCase().includes(pinKw)
            );
        }
        if (effectiveSpecialty && effectiveSpecialty.toLowerCase() !== 'all' && effectiveSpecialty.toLowerCase() !== 'all specialties') {
            formattedDentists = formattedDentists.filter(d => matchesSpecialtyQuery(d.specialty || d.speciality, effectiveSpecialty));
        }

        if (searchKw) {
            formattedDentists = formattedDentists.filter(d => {
                return (d.name || '').toLowerCase().includes(searchKw) ||
                    (d.specialty || '').toLowerCase().includes(searchKw) ||
                    (d.qualification || '').toLowerCase().includes(searchKw) ||
                    (d.clinicName || '').toLowerCase().includes(searchKw) ||
                    (d.city || '').toLowerCase().includes(searchKw) ||
                    (d.pincode || '').includes(searchKw) ||
                    (d.languages || []).some(l => (l || '').toLowerCase().includes(searchKw));
            });
        }

        if (selectedLangFilters.length > 0) {
            formattedDentists = formattedDentists.filter(d => doctorMatchesLanguages(d, selectedLangFilters));
        }

        const pCity = (req.query.patientCity || req.query.city || '').trim().toLowerCase();
        const pPin = (req.query.patientPincode || req.query.pincode || '').trim();

        if (pCity || pPin) {
            formattedDentists.sort((a, b) => {
                const aCity = (a.city || '').trim().toLowerCase();
                const aPin = (a.pincode || '').trim();
                const bCity = (b.city || '').trim().toLowerCase();
                const bPin = (b.pincode || '').trim();

                let scoreA = 3; // Other location
                if (pPin && aPin && aPin === pPin) scoreA = 1; // Same Pincode
                else if (pCity && aCity && (aCity === pCity || aCity.includes(pCity) || pCity.includes(aCity))) scoreA = 2; // Same City

                let scoreB = 3;
                if (pPin && bPin && bPin === pPin) scoreB = 1;
                else if (pCity && bCity && (bCity === pCity || bCity.includes(pCity) || pCity.includes(bCity))) scoreB = 2;

                if (scoreA !== scoreB) return scoreA - scoreB;
                return (b.rating || 5.0) - (a.rating || 5.0);
            });
        }

        res.json({
            success: true,
            count: formattedDentists.length,
            dentists: formattedDentists,
            doctors: formattedDentists,
            availableLanguages
        });
    } catch (err) {
        console.error('Get All Doctors Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to fetch all doctors.' });
    }
};

// 4a. GET DISTINCT AVAILABLE LANGUAGES FROM REGISTERED DOCTORS
exports.getAvailableDoctorLanguages = async (req, res) => {
    try {
        const includeUnavailableRequested = String(req.query.includeUnavailable || '').trim().toLowerCase() === 'true';
        const explicitHideUnavailable = String(req.query.includeUnavailable || '').trim().toLowerCase() === 'false';
        const allowUnavailable = !explicitHideUnavailable && (includeUnavailableRequested || (isPrivilegedDoctorViewer(req) && Boolean(req.user)));

        const dentists = await Dentist.find({});
        const { User } = require('../models/Schemas');
        const existingEmails = new Set(dentists.map(d => (d.email || d.users?.email || '').toLowerCase()).filter(Boolean));
        const existingUserIds = new Set(dentists.map(d => String(d.user_id || d.users?.id || d.id || '').trim()).filter(Boolean));

        const doctorRoleUsers = await User.find({ role: { $in: ['DOCTOR', 'Doctor', 'Dentist'] } });
        for (const u of doctorRoleUsers) {
            const emailClean = (u.email || '').toLowerCase();
            const userIdClean = String(u.id || '').trim();
            if ((!emailClean || !existingEmails.has(emailClean)) && (!userIdClean || !existingUserIds.has(userIdClean))) {
                dentists.push({
                    id: u.id,
                    user_id: u.id,
                    availability_status: 'Available',
                    languages: extractDoctorLanguages({ languages: u.languages, users: u }),
                    users: u
                });
            }
        }

        const eligible = allowUnavailable ? dentists : dentists.filter(d => isDoctorRecordAvailable(d));
        const languages = mergeSupportedAndDoctorLanguages(
            eligible.flatMap(d => extractDoctorLanguages(d))
        );

        res.json({
            success: true,
            count: languages.length,
            languages
        });
    } catch (err) {
        console.error('Get Doctor Languages Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to fetch available doctor languages.' });
    }
};

// 4b. GET SINGLE DOCTOR PROFILE BY ID (Strictly hides details from patients when availability is OFF)
exports.getDoctorById = async (req, res) => {
    const { id } = req.params;
    try {
        if (!id || !String(id).trim()) {
            return res.status(400).json({ success: false, message: 'Doctor ID is required.' });
        }

        const doctor = await Dentist.findById(id);
        if (!doctor) {
            return res.status(404).json({ success: false, message: 'Doctor profile not found.' });
        }

        const isAvailable = isDoctorRecordAvailable(doctor);
        const canViewUnavailable = isPrivilegedDoctorViewer(req, doctor);

        if (!isAvailable && !canViewUnavailable) {
            return res.status(403).json({
                success: false,
                unavailable: true,
                isAvailable: false,
                message: 'Doctor is currently unavailable.'
            });
        }

        const formatted = formatDentistRecord(doctor);
        res.json({
            success: true,
            isAvailable: formatted.isAvailable,
            availability_status: formatted.availability_status,
            doctor: formatted
        });
    } catch (err) {
        console.error('Get Doctor By ID Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to fetch doctor profile.' });
    }
};

// 4c. TOGGLE / UPDATE DOCTOR AVAILABILITY ON/OFF (Persists availability_status in Supabase without touching profile/appointments/records)
exports.updateDoctorAvailability = async (req, res) => {
    if (!ensureClinicOrDoctorMutationAuth(req, res)) return;
    const { id } = req.params;
    try {
        if (!id || !String(id).trim()) {
            return res.status(400).json({ success: false, message: 'Doctor ID is required.' });
        }

        const callerRole = (req.user?.role || '').toString().trim().toLowerCase();
        if (callerRole === 'patient') {
            return res.status(403).json({
                success: false,
                message: 'Forbidden: Patients cannot modify doctor availability.'
            });
        }

        const explicitOnlineStatus = req.body.onlineStatus !== undefined
            ? String(req.body.onlineStatus).trim()
            : (req.body.online_status !== undefined ? String(req.body.online_status).trim() : '');
        const rawInput = req.body.isAvailable !== undefined
            ? req.body.isAvailable
            : (req.body.available !== undefined
                ? req.body.available
                : (req.body.availability_status !== undefined ? req.body.availability_status : req.body.status));

        // Support distinguishing Online Presence ('Offline' presence while schedule remains 'Available')
        let normalizedStatus = normalizeAvailabilityStatus(rawInput);
        let resolvedOnlinePresence = explicitOnlineStatus;
        if (!normalizedStatus && explicitOnlineStatus) {
            const ol = explicitOnlineStatus.toLowerCase();
            if (ol === 'online') normalizedStatus = 'Online';
            else if (ol === 'busy') normalizedStatus = 'Busy';
            else if (ol === 'offline') normalizedStatus = 'Available';
        }
        if (!normalizedStatus) {
            return res.status(400).json({
                success: false,
                message: 'Valid availability status is required (Online, Offline, Available, Busy, Unavailable, or isAvailable: true/false).'
            });
        }

        let existingDoctor = await Dentist.findById(id);
        if (!existingDoctor && req.user?.id) {
            existingDoctor = await Dentist.findById(req.user.id);
        }
        if (!existingDoctor && String(id).toUpperCase().startsWith('DOC-')) {
            const allDentists = await Dentist.find({});
            if (allDentists.length === 1) {
                existingDoctor = allDentists[0];
            }
        }
        if (!existingDoctor) {
            return res.status(404).json({ success: false, message: 'Doctor not found.' });
        }

        // Doctors may only update their own availability
        if ((callerRole === 'dentist' || callerRole === 'doctor') && req.user?.id) {
            const callerId = String(req.user.id).trim();
            const ownsRecord = callerId === String(existingDoctor.id || '').trim() ||
                callerId === String(existingDoctor.user_id || '').trim();
            if (!ownsRecord) {
                return res.status(403).json({
                    success: false,
                    message: 'Forbidden: You can only update your own availability status.'
                });
            }
        }

        const updatedDoctor = await Dentist.findByIdAndUpdate(existingDoctor.id, {
            availability_status: normalizedStatus
        });
        if (resolvedOnlinePresence && existingDoctor.user_id) {
            try {
                const docUser = await User.findById(existingDoctor.user_id);
                let meta = {};
                if (docUser?.device_token && typeof docUser.device_token === 'string' && docUser.device_token.trim().startsWith('{')) {
                    try { meta = JSON.parse(docUser.device_token); } catch (_) {}
                }
                meta.onlineStatus = resolvedOnlinePresence;
                await User.findByIdAndUpdate(existingDoctor.user_id, { device_token: JSON.stringify(meta) });
            } catch (_) {}
        }
        const refreshed = await Dentist.findById(existingDoctor.id) || updatedDoctor || existingDoctor;
        const formatted = formatDentistRecord({
            ...refreshed,
            availability_status: normalizedStatus,
            ...(resolvedOnlinePresence ? { onlineStatus: resolvedOnlinePresence } : {})
        });
        const isAvailable = normalizedStatus !== 'Unavailable';

        res.json({
            success: true,
            isAvailable,
            availability_status: normalizedStatus,
            message: isAvailable
                ? 'Availability turned ON. Your profile is now visible to patients and open for new bookings.'
                : 'Availability turned OFF. Your profile is hidden from patient search and new bookings.',
            doctor: formatted
        });
    } catch (err) {
        console.error('Update Doctor Availability Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to update doctor availability.' });
    }
};

// 5. GET PATIENT SAVED DOCTORS (My Doctors)
exports.getPatientDoctors = async (req, res) => {
    try {
        const { PatientDoctor } = require('../models/Schemas');
        const patientId = req.query.patientId || req.user?.id;
        if (!patientId) {
            return res.status(400).json({ success: false, message: 'patientId is required' });
        }
        const doctorIds = await PatientDoctor.getDoctorsForPatient(patientId);
        res.json({ success: true, count: doctorIds.length, doctorIds });
    } catch (err) {
        console.error('Get Patient Doctors Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to fetch patient doctors.' });
    }
};

// 6. ADD DOCTOR TO PATIENT'S "MY DOCTORS"
exports.addPatientDoctor = async (req, res) => {
    try {
        const { PatientDoctor } = require('../models/Schemas');
        const patientId = req.body.patientId || req.user?.id;
        const doctorId = req.body.doctorId;

        if (!patientId || !doctorId) {
            return res.status(400).json({ success: false, message: 'Both patientId and doctorId are required' });
        }

        const result = await PatientDoctor.addDoctorForPatient(patientId, doctorId);
        res.json({ success: true, message: 'Doctor added to My Doctors successfully.', data: result.data });
    } catch (err) {
        console.error('Add Patient Doctor Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to add doctor to patient list.' });
    }
};

// 7. REMOVE DOCTOR FROM PATIENT'S "MY DOCTORS"
exports.removePatientDoctor = async (req, res) => {
    try {
        const { PatientDoctor } = require('../models/Schemas');
        const patientId = req.query.patientId || req.body.patientId || req.user?.id;
        const doctorId = req.params.doctorId || req.body.doctorId;

        if (!patientId || !doctorId) {
            return res.status(400).json({ success: false, message: 'Both patientId and doctorId are required' });
        }

        await PatientDoctor.removeDoctorForPatient(patientId, doctorId);
        res.json({ success: true, message: 'Doctor removed from My Doctors successfully.' });
    } catch (err) {
        console.error('Remove Patient Doctor Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to remove doctor from patient list.' });
    }
};

// 8. DELETE DENTIST (PERMANENT REMOVAL)
exports.deleteDentist = async (req, res) => {
    const { id } = req.params;
    try {
        if (!id) {
            return res.status(400).json({ success: false, message: 'Doctor ID is required.' });
        }

        const { supabaseAdmin } = require('../config/supabase');

        // 1. Delete from patient_doctors junction if any
        try {
            await supabaseAdmin.from('patient_doctors').delete().or(`doctor_id.eq.${id},patient_id.eq.${id}`);
        } catch (_) { }

        // 2. Check dentists table and delete
        let userId = null;
        try {
            const { data: dData } = await supabaseAdmin.from('dentists').select('id, user_id').or(`id.eq.${id},user_id.eq.${id}`).maybeSingle();
            if (dData) {
                userId = dData.user_id;
                await supabaseAdmin.from('dentists').delete().or(`id.eq.${dData.id},id.eq.${id},user_id.eq.${id}`);
            } else {
                await supabaseAdmin.from('dentists').delete().or(`id.eq.${id},user_id.eq.${id}`);
            }
        } catch (_) { }

        // 3. Delete from users table if applicable
        const targetUserId = userId || id;
        try {
            await supabaseAdmin.from('users').delete().eq('id', targetUserId);
            await supabaseAdmin.auth.admin.deleteUser(targetUserId);
        } catch (_) { }

        res.json({ success: true, message: 'Doctor deleted successfully.' });
    } catch (err) {
        console.error('Delete Dentist Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to delete doctor.' });
    }
};

// 9. UPDATE DOCTOR PROFESSIONAL PROFILE (Specialty, Qualification, Experience, Clinic, Availability)
exports.updateDoctorProfile = async (req, res) => {
    if (!ensureClinicOrDoctorMutationAuth(req, res)) return;
    const { id } = req.params;
    const {
        name,
        specialty,
        speciality,
        specialtyId,
        specialty_id,
        specialtyName,
        medicalSpecialty,
        department,
        qualification,
        qualifications,
        experienceYears,
        experience_years,
        licenseNumber,
        license_number,
        clinicName,
        city,
        pincode,
        state,
        status,
        availability_status,
        languages,
        languagesKnown
    } = req.body;
    try {
        if (!id) {
            return res.status(400).json({ success: false, message: 'Doctor ID is required.' });
        }

        const { User } = require('../models/Schemas');
        const normalizedLanguages = (languages !== undefined || languagesKnown !== undefined)
            ? normalizeLanguagesList(languages ?? languagesKnown)
            : null;
        const requestedSpec = (specialty || speciality || specialtyName || medicalSpecialty || '').toString().trim();
        const requestedSpecId = (specialtyId || specialty_id || '').toString().trim() || undefined;
        let clinicId = undefined;
        if (clinicName && String(clinicName).trim()) {
            const cName = String(clinicName).trim();
            let clinic = await Clinic.findOne({ clinic_name: cName });
            if (!clinic) {
                clinic = await Clinic.create({
                    clinic_name: cName,
                    location: city ? `${city}${pincode ? ' - ' + pincode : ''}` : 'GS HEALTH Medical Center',
                    verified: true,
                    services: [requestedSpec || 'General Medicine']
                });
            }
            if (clinic && clinic.id) clinicId = clinic.id;
        }

        const updatedDentist = await Dentist.findByIdAndUpdate(id, {
            ...(requestedSpec ? { speciality: requestedSpec } : {}),
            ...(requestedSpecId ? { specialty_id: requestedSpecId } : {}),
            ...(department ? { department } : {}),
            qualifications: qualification || qualifications,
            experience_years: experienceYears ?? experience_years,
            license_number: licenseNumber || license_number,
            availability_status: status || availability_status,
            ...(clinicId !== undefined ? { clinic_id: clinicId } : {}),
            ...(city !== undefined ? { city } : {}),
            ...(pincode !== undefined ? { pincode } : {}),
            ...(state !== undefined ? { state } : {}),
            ...(normalizedLanguages && normalizedLanguages.length > 0 ? { languages: normalizedLanguages } : {})
        });

        const targetUserId = updatedDentist?.user_id || id;
        if (name || city || pincode || (normalizedLanguages && normalizedLanguages.length > 0)) {
            try {
                await User.findByIdAndUpdate(targetUserId, {
                    ...(name ? { name } : {}),
                    ...(city ? { city } : {}),
                    ...(pincode ? { pincode } : {}),
                    ...(normalizedLanguages && normalizedLanguages.length > 0 ? { languages: normalizedLanguages } : {})
                });
            } catch (_) { }
        }

        const refreshed = await Dentist.findById(updatedDentist?.id || id) || updatedDentist;
        res.json({
            success: true,
            message: 'Doctor professional profile updated successfully.',
            doctor: refreshed ? formatDentistRecord(refreshed) : updatedDentist
        });
    } catch (err) {
        console.error('Update Doctor Profile Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to update doctor profile.' });
    }
};

// 10. UPDATE CLINIC DEPARTMENTS & SERVICES (Multi-Specialty Clinic Management)
exports.updateClinicDepartments = async (req, res) => {
    if (!ensureClinicOrDoctorMutationAuth(req, res)) return;
    const { id } = req.params;
    const { clinicName, location, departments, services, pricing } = req.body;
    try {
        const mergedServices = Array.isArray(departments) && departments.length > 0
            ? departments
            : (Array.isArray(services) ? services : undefined);

        const updatePayload = {};
        if (clinicName) updatePayload.clinic_name = clinicName;
        if (location) updatePayload.location = location;
        if (mergedServices) updatePayload.services = mergedServices;
        if (pricing) updatePayload.pricing = pricing;

        let clinic = null;
        if (id && id !== 'default') {
            clinic = await Clinic.findByIdAndUpdate(id, updatePayload);
        } else if (clinicName) {
            const existing = await Clinic.findOne({ clinic_name: clinicName });
            if (existing) {
                clinic = await Clinic.findByIdAndUpdate(existing.id, updatePayload);
            } else {
                clinic = await Clinic.create({
                    clinic_name: clinicName,
                    location: location || 'GS HEALTH Multi-Specialty Center',
                    services: mergedServices || ['General Medicine', 'Dentistry'],
                    pricing: pricing || []
                });
            }
        }

        res.json({
            success: true,
            message: 'Clinic departments and services updated successfully.',
            clinic
        });
    } catch (err) {
        console.error('Update Clinic Departments Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to update clinic departments.' });
    }
};

// 10b. ADD NEW DOCTOR DIRECTLY UNDER A CLINIC (Supports Multiple Doctors per Clinic)
exports.addClinicDoctor = async (req, res) => {
    if (!ensureClinicOrDoctorMutationAuth(req, res)) return;
    const { clinicId } = req.params;
    const {
        name,
        phone,
        email,
        specialty,
        speciality,
        specialtyId,
        specialty_id,
        qualification,
        qualifications,
        experienceYears,
        experience_years,
        licenseNumber,
        license_number,
        consultationFee,
        consultation_fee,
        bio,
        city,
        pincode,
        state,
        languages,
        clinicName
    } = req.body;
    try {
        const cleanName = String(name || '').trim();
        const rawPhone = String(phone || '').trim();
        const phoneDigits = rawPhone.replace(/[^0-9]/g, '');
        const cleanPhone = phoneDigits.length === 12 && phoneDigits.startsWith('91')
            ? phoneDigits.slice(2)
            : (phoneDigits.length === 11 && phoneDigits.startsWith('0') ? phoneDigits.slice(1) : phoneDigits);

        if (!cleanName || cleanPhone.length < 10) {
            return res.status(400).json({
                success: false,
                message: 'Doctor full name and valid 10-digit phone number are required.'
            });
        }

        const resolvedScope = await exports.resolveClinicRecordAndDoctorIds(clinicId !== 'default' ? clinicId : (clinicName || ''));
        let targetClinic = resolvedScope.clinic;
        if (!targetClinic && clinicName && String(clinicName).trim()) {
            targetClinic = await Clinic.findOne({ clinic_name: String(clinicName).trim() }).catch(() => null);
            if (!targetClinic) {
                targetClinic = await Clinic.create({
                    clinic_name: String(clinicName).trim(),
                    location: [city, pincode].filter(Boolean).join(' - ') || 'GS HEALTH Medical Center',
                    verified: true,
                    services: [specialty || speciality || 'General Medicine']
                });
            }
        }
        const canonicalClinicId = targetClinic?.id || (clinicId && clinicId !== 'default' ? clinicId : null);
        const resolvedClinicName = targetClinic?.clinic_name || String(clinicName || '').trim();

        const rawSpecInput = String(specialty || speciality || '').trim();
        const specResolution = await resolveMedicalSpecialtyRecord(
            rawSpecInput || 'General Medicine',
            specialtyId || specialty_id || null
        );
        const resolvedSpec = specResolution.specialty;
        const resolvedQual = String(qualification || qualifications || '').trim() || getDefaultQualificationForSpecialty(resolvedSpec);
        const resolvedExp = parseInt(experienceYears ?? experience_years ?? 5, 10) || 5;
        const cleanLangs = normalizeLanguagesList(languages);
        const finalLangs = cleanLangs.length > 0 ? cleanLangs : ['English'];

        // Check if doctor account already exists by phone or email
        let user = await User.findByMobile(cleanPhone).catch(() => null);
        const cleanEmailInput = String(email || '').trim().toLowerCase();
        if (!user && cleanEmailInput && cleanEmailInput.includes('@')) {
            user = await User.findOne({ email: cleanEmailInput }).catch(() => null);
        }

        if (!user) {
            const generatedEmail = (cleanEmailInput && cleanEmailInput.includes('@'))
                ? cleanEmailInput
                : `user_${cleanPhone}@dentaguru.internal`;
            const effectivePassword = `OTP_SECURE_${require('crypto').randomBytes(12).toString('hex')}`;
            const formattedDocName = cleanName.startsWith('Dr.') ? cleanName : `Dr. ${cleanName}`;
            const metaObj = {
                city: String(city || targetClinic?.city || '').trim(),
                pincode: String(pincode || targetClinic?.pincode || '').trim(),
                location: targetClinic?.location || '',
                languages: finalLangs,
                specialty: resolvedSpec,
                specialtyId: specResolution.specialty_id || null,
                department: specResolution.department || '',
                qualification: resolvedQual,
                experienceYears: resolvedExp,
                clinicId: canonicalClinicId,
                clinicName: resolvedClinicName,
                licenseNumber: String(licenseNumber || license_number || '').trim()
            };
            user = await User.create({
                name: formattedDocName,
                email: generatedEmail,
                password: effectivePassword,
                phone: cleanPhone,
                role: 'DOCTOR',
                state: String(state || '').trim(),
                city: metaObj.city,
                pincode: metaObj.pincode,
                languages: finalLangs,
                device_token: JSON.stringify(metaObj)
            });
        }

        // Check if this user already has a dentists row
        let dentistRec = await Dentist.findOne({ user_id: user.id }).catch(() => null);
        if (dentistRec) {
            dentistRec = await Dentist.findByIdAndUpdate(dentistRec.id, {
                ...(canonicalClinicId ? { clinic_id: canonicalClinicId } : {}),
                ...(rawSpecInput ? { speciality: resolvedSpec, specialty_id: specResolution.specialty_id, department: specResolution.department } : {}),
                qualifications: resolvedQual,
                experience_years: resolvedExp,
                ...(consultationFee || consultation_fee ? { consultation_fee: String(consultationFee || consultation_fee) } : {}),
                ...(bio !== undefined ? { bio: String(bio || '') } : {}),
                availability_status: 'Available'
            });
        } else {
            dentistRec = await Dentist.create({
                user_id: user.id,
                clinic_id: canonicalClinicId,
                speciality: resolvedSpec,
                specialty_id: specResolution.specialty_id || null,
                department: specResolution.department || '',
                license_number: String(licenseNumber || license_number || '').trim(),
                experience_years: resolvedExp,
                qualifications: resolvedQual,
                availability_status: 'Available',
                consultation_fee: String(consultationFee || consultation_fee || ''),
                bio: String(bio || ''),
                state: String(state || '').trim(),
                city: String(city || targetClinic?.city || '').trim(),
                pincode: String(pincode || targetClinic?.pincode || '').trim(),
                languages: finalLangs,
                rating: 5.0,
                reviews_count: 0
            });
        }

        if (targetClinic && resolvedSpec) {
            const currentServices = Array.isArray(targetClinic.services) ? [...targetClinic.services] : [];
            if (!currentServices.some(s => String(s).toLowerCase() === resolvedSpec.toLowerCase())) {
                currentServices.push(resolvedSpec);
                await Clinic.findByIdAndUpdate(targetClinic.id, { services: currentServices }).catch(() => null);
            }
        }

        await Notification.create({
            recipient_role: 'Admin',
            recipient_id: 'ALL_ADMINS',
            title: '🩺 New Clinic Doctor Added',
            message: `${user.name} (${resolvedSpec}) added to ${resolvedClinicName || 'Clinic'}.`,
            type: 'doctor_registered'
        }).catch(() => null);

        const refreshedDoctor = (dentistRec?.id ? await Dentist.findById(dentistRec.id).catch(() => null) : null) || {
            ...dentistRec,
            users: user,
            clinics: targetClinic || {}
        };
        const formatted = formatDentistRecord(refreshedDoctor);
        const allClinicDoctors = canonicalClinicId
            ? (await Dentist.find({ clinic_id: canonicalClinicId }).catch(() => [])).map(formatDentistRecord)
            : [formatted];

        res.status(201).json({
            success: true,
            message: 'Doctor added to clinic successfully.',
            doctor: formatted,
            doctors: allClinicDoctors
        });
    } catch (err) {
        console.error('Add Clinic Doctor Error:', err.message);
        res.status(500).json({ success: false, message: err.message || 'Failed to add doctor to clinic.' });
    }
};

// 11. ASSOCIATE EXISTING DOCTOR WITH CLINIC (No Duplicate Account Creation)
exports.associateClinicDoctor = async (req, res) => {
    if (!ensureClinicOrDoctorMutationAuth(req, res)) return;
    const { clinicId } = req.params;
    const { doctorId, phone, email, licenseNumber, clinicName, specialty, consultationFee, availableDays, availableSlots } = req.body;
    try {
        const { User } = require('../models/Schemas');
        let resolvedClinicId = clinicId !== 'default' ? clinicId : undefined;
        if (clinicName && String(clinicName).trim()) {
            let clinic = await Clinic.findOne({ clinic_name: String(clinicName).trim() });
            if (!clinic) {
                clinic = await Clinic.create({
                    clinic_name: String(clinicName).trim(),
                    location: 'GS HEALTH Partner Clinic',
                    verified: true,
                    services: [specialty || 'General Medicine']
                });
            }
            if (clinic && clinic.id) resolvedClinicId = clinic.id;
        }

        let targetDoctor = null;
        if (doctorId) {
            targetDoctor = await Dentist.findById(doctorId);
        }
        if (!targetDoctor && (phone || email || licenseNumber)) {
            const allDentists = await Dentist.find({});
            targetDoctor = allDentists.find(d => {
                const dPhone = (d.phone || d.users?.phone || '').replace(/[^0-9]/g, '');
                const qPhone = (phone || '').replace(/[^0-9]/g, '');
                if (qPhone.length >= 10 && dPhone.length >= 10 && dPhone.slice(-10) === qPhone.slice(-10)) return true;
                if (email && (d.email || d.users?.email || '').toLowerCase() === String(email).trim().toLowerCase()) return true;
                if (licenseNumber && (d.license_number || '').toLowerCase() === String(licenseNumber).trim().toLowerCase()) return true;
                return false;
            });
        }

        if (!targetDoctor && (phone || email)) {
            const existingUser = email ? await User.findOne({ email: String(email).trim() }) : null;
            if (existingUser) {
                targetDoctor = await Dentist.create({
                    user_id: existingUser.id,
                    clinic_id: resolvedClinicId || null,
                    speciality: specialty || existingUser.specialty || 'General Medicine',
                    qualifications: existingUser.qualification || getDefaultQualificationForSpecialty(specialty || 'General Medicine'),
                    license_number: licenseNumber || '',
                    experience_years: existingUser.experienceYears || 5,
                    availability_status: 'Available'
                });
            }
        }

        if (!targetDoctor) {
            return res.status(404).json({
                success: false,
                message: 'No existing GS HEALTH doctor account found matching the provided details.'
            });
        }

        const updated = await Dentist.findByIdAndUpdate(targetDoctor.id, {
            ...(resolvedClinicId ? { clinic_id: resolvedClinicId } : {}),
            ...(specialty ? { speciality: specialty } : {}),
            availability_status: 'Available'
        });

        res.json({
            success: true,
            associated: true,
            message: 'Existing doctor associated with clinic successfully without creating a duplicate account.',
            doctor: updated || targetDoctor,
            extra: { consultationFee, availableDays, availableSlots }
        });
    } catch (err) {
        console.error('Associate Clinic Doctor Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to associate doctor with clinic.' });
    }
};

// 12. REMOVE DOCTOR FROM CLINIC (Preserves Global Doctor Account & Patient Records)
exports.removeDoctorFromClinic = async (req, res) => {
    if (!ensureClinicOrDoctorMutationAuth(req, res)) return;
    const { doctorId } = req.params;
    try {
        if (!doctorId) {
            return res.status(400).json({ success: false, message: 'Doctor ID is required.' });
        }

        // Only clear clinic association (clinic_id: null) — never delete the user or dentist record
        const updated = await Dentist.findByIdAndUpdate(doctorId, {
            clinic_id: null
        });

        res.json({
            success: true,
            message: 'Doctor removed from clinic directory. Global doctor account and patient records preserved.',
            doctor: updated
        });
    } catch (err) {
        console.error('Remove Doctor From Clinic Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to remove doctor from clinic.' });
    }
};

// 13. DELETE CLINIC (PERMANENT REMOVAL ACROSS SUPABASE & BACKEND)
exports.deleteClinic = async (req, res) => {
    const { id } = req.params;
    try {
        if (!id) {
            return res.status(400).json({ success: false, message: 'Clinic ID is required.' });
        }

        if (supabaseAdmin) {
            await supabaseAdmin.from('clinics').delete().eq('id', id);
        }

        return res.json({
            success: true,
            message: 'Clinic facility and records permanently deleted.'
        });
    } catch (err) {
        console.error('Delete Clinic Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to delete clinic.' });
    }
};

