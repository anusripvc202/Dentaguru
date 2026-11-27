const { supabaseAdmin } = require('../config/supabase');
const { isCloudEnv } = require('../config/secrets');
const {
    User,
    Clinic,
    ClinicDoctor,
    Dentist,
    Notification,
    resolveClinicIds,
    resolveMedicalSpecialtyRecord,
    matchesSpecialtyQuery,
    getDefaultQualificationForSpecialty,
    isDoctorRecordAvailable,
    normalizeAvailabilityStatus,
    resolveDoctorConsultationModes,
    normalizeLanguagesList,
    parseLanguageFilters,
    extractDoctorLanguages,
    doctorMatchesLanguages,
    mergeSupportedAndDoctorLanguages
} = require('../models/Schemas');
const {
    validateCoordinates,
    validateDoctorRegistrationClinicFields,
    isValidIndianPincode,
    parseUserDeviceMeta
} = require('../utils/doctorClinicLocationHelper');

function formatClinicRecord(c, associatedDoctorsCount = null) {
    if (!c) return null;
    const uObj = Array.isArray(c.users) ? (c.users[0] || {}) : (c.users || {});
    const uMeta = parseUserDeviceMeta(uObj.device_token);
    const clinicAddress = String(c.clinic_address || c.clinicAddress || c.location || uMeta.clinicAddress || '').trim();
    const city = String(c.city || uObj.city || uMeta.city || '').trim();
    const state = String(c.state || uObj.state || uMeta.state || '').trim();
    const pincode = String(c.pincode || uObj.pincode || uMeta.pincode || '').trim();
    const rawLat = c.latitude ?? uObj.latitude ?? uMeta.latitude ?? null;
    const rawLng = c.longitude ?? uObj.longitude ?? uMeta.longitude ?? null;
    const latitude = rawLat !== null && rawLat !== '' && Number.isFinite(Number(rawLat)) ? Number(rawLat) : null;
    const longitude = rawLng !== null && rawLng !== '' && Number.isFinite(Number(rawLng)) ? Number(rawLng) : null;

    return {
        ...c,
        id: c.id,
        clinicId: c.id,
        user_id: c.user_id || uObj.id || null,
        userId: c.user_id || uObj.id || null,
        clinic_name: c.clinic_name || c.clinicName || uObj.name || '',
        clinicName: c.clinic_name || c.clinicName || uObj.name || '',
        clinic_address: clinicAddress,
        clinicAddress,
        location: c.location || clinicAddress,
        city,
        state,
        pincode,
        latitude,
        longitude,
        phone: c.phone || uObj.phone || '',
        email: c.email || uObj.email || '',
        verified: c.verified !== undefined ? c.verified : true,
        services: Array.isArray(c.services) ? c.services : [],
        pricing: Array.isArray(c.pricing) ? c.pricing : [],
        ...(associatedDoctorsCount !== null ? {
            associatedDoctorsCount,
            totalDoctors: associatedDoctorsCount
        } : {})
    };
}

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

function combineNameParts(obj = {}) {
    if (!obj || typeof obj !== 'object') return '';
    const first = String(obj.first_name ?? obj.firstName ?? '').trim();
    const middle = String(obj.middle_name ?? obj.middleName ?? '').trim();
    const last = String(obj.last_name ?? obj.lastName ?? '').trim();
    return [first, middle, last].filter(Boolean).join(' ').replace(/\s+/g, ' ').trim();
}

function normalizeDoctorDisplayName(raw) {
    const cleaned = String(raw || '').replace(/\s+/g, ' ').trim();
    if (!cleaned) return 'Doctor';
    const withoutPrefix = cleaned.replace(/^(dr\.?\s+)+/i, '').trim();
    if (!withoutPrefix) return 'Doctor';
    if (withoutPrefix.toLowerCase() === 'doctor') return 'Doctor';
    return `Dr. ${withoutPrefix}`;
}

function resolveDoctorFullName(d = {}, uObjInput = null) {
    const uObj = uObjInput || (Array.isArray(d.users) ? (d.users[0] || {}) : (d.users || d.user || {}));
    const uMeta = parseUserDeviceMeta(uObj.device_token);
    const isGeneric = (v) => {
        const s = String(v || '').replace(/\s+/g, ' ').trim().toLowerCase();
        return !s || s === 'doctor' || s === 'dr.' || s === 'dr. doctor' || s === 'dentist' || s === 'dr. dentist' || s === 'specialist';
    };

    const candidates = [
        d.full_name,
        d.fullName,
        d.doctor_name,
        d.doctorName,
        d.dentist_name,
        combineNameParts(d),
        d.name,
        uObj.full_name,
        uObj.fullName,
        combineNameParts(uObj),
        uObj.name,
        uMeta.fullName,
        uMeta.full_name,
        combineNameParts(uMeta),
        uMeta.name
    ];

    let best = '';
    for (const c of candidates) {
        const trimmed = String(c || '').replace(/\s+/g, ' ').trim();
        if (!trimmed) continue;
        if (!isGeneric(trimmed)) {
            // Prefer the most complete (longest) non-generic full name if a candidate has more words than a partial one
            if (!best || trimmed.split(' ').length > best.split(' ').length) {
                best = trimmed;
            }
        }
    }

    return normalizeDoctorDisplayName(best || 'Doctor');
}

function formatDentistRecord(d) {
    const uObj = Array.isArray(d.users) ? (d.users[0] || {}) : (d.users || d.user || {});
    const cObj = Array.isArray(d.clinics) ? (d.clinics[0] || {}) : (d.clinics || d.clinic || {});
    const formattedName = resolveDoctorFullName(d, uObj);

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
        } catch (_) { }
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

    const { parseUserDeviceMeta } = require('../utils/doctorClinicLocationHelper');
    const uMeta = parseUserDeviceMeta(uObj.device_token);
    const rawLat = d.latitude ?? cObj.latitude ?? uObj.latitude ?? uMeta.latitude ?? null;
    const rawLng = d.longitude ?? cObj.longitude ?? uObj.longitude ?? uMeta.longitude ?? null;
    const resolvedLat = rawLat !== null && rawLat !== '' && Number.isFinite(Number(rawLat)) ? Number(rawLat) : null;
    const resolvedLng = rawLng !== null && rawLng !== '' && Number.isFinite(Number(rawLng)) ? Number(rawLng) : null;
    const consultModes = resolveDoctorConsultationModes(d);

    return {
        id: d.id,
        user_id: d.user_id || uObj.id,
        clinic_id: d.clinic_id || cObj.id || null,
        clinicId: d.clinic_id || cObj.id || null,
        name: formattedName,
        fullName: formattedName,
        full_name: formattedName,
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
        clinicName: d.clinic_name || cObj.clinic_name || d.clinicName || uMeta.clinicName || '',
        clinicAddress: d.clinic_address || cObj.location || d.clinicAddress || d.location || uMeta.clinicAddress || '',
        state: d.state || uObj.state || uMeta.state || '',
        city: d.city || uObj.city || uMeta.city || '',
        pincode: d.pincode || uObj.pincode || uMeta.pincode || '',
        languages: doctorLangs,
        latitude: resolvedLat,
        longitude: resolvedLng,
        availability_status: availabilityStatus,
        status: availabilityStatus,
        onlineStatus: resolvedOnlineStatus,
        liveStatus: resolvedOnlineStatus,
        isAvailable,
        isOnline,
        online_consultation_enabled: consultModes.onlineConsultationEnabled,
        onlineConsultationEnabled: consultModes.onlineConsultationEnabled,
        in_person_consultation_enabled: consultModes.inPersonConsultationEnabled,
        inPersonConsultationEnabled: consultModes.inPersonConsultationEnabled,
        supportsOnlineConsultation: isAvailable && consultModes.onlineConsultationEnabled,
        supportsInPersonConsultation: isAvailable && consultModes.inPersonConsultationEnabled,
        consultationModes: consultModes.consultationModes,
        consultationModeLabel: consultModes.consultationModeLabel,
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

// 1. REGISTER CLINIC PROFILE (Independent of Doctor Registration, Full Address + OSM Coordinates)
exports.registerClinicProfile = async (req, res) => {
    if (!ensureClinicOrDoctorMutationAuth(req, res)) return;
    const {
        clinicName,
        clinicAddress,
        location,
        city,
        state,
        pincode,
        latitude,
        longitude,
        services,
        pricing,
        coordinates
    } = req.body;
    try {
        const role = String(req.user?.role || '').trim().toLowerCase();
        const cleanName = String(clinicName || '').trim();
        const cleanAddress = String(clinicAddress || location || '').trim();
        const cleanCity = String(city || '').trim();
        const cleanState = String(state || '').trim();
        const cleanPincode = String(pincode || '').trim();

        const rawLat = latitude !== undefined ? latitude : (coordinates?.[1] ?? undefined);
        const rawLng = longitude !== undefined ? longitude : (coordinates?.[0] ?? undefined);

        // When structured clinic fields are provided (new Clinic Registration flow), validate strictly
        const isStructuredRegistration = Boolean(
            clinicAddress !== undefined ||
            city !== undefined ||
            state !== undefined ||
            pincode !== undefined ||
            rawLat !== undefined ||
            rawLng !== undefined
        );
        let resolvedLat = null;
        let resolvedLng = null;

        if (isStructuredRegistration) {
            const check = validateDoctorRegistrationClinicFields({
                clinicName: cleanName,
                clinicAddress: cleanAddress,
                city: cleanCity,
                state: cleanState,
                pincode: cleanPincode,
                latitude: rawLat,
                longitude: rawLng,
            });
            if (!check.ok) {
                return res.status(400).json({ success: false, message: check.message });
            }
            resolvedLat = check.latitude;
            resolvedLng = check.longitude;
        } else if (!cleanName) {
            return res.status(400).json({ success: false, message: 'Clinic name is required.' });
        }

        if (cleanName) {
            const byName = await Clinic.findOne({ clinic_name: cleanName }).catch(() => null);
            if (byName) {
                const patch = {
                    ...(!byName.user_id && req.user?.id ? { user_id: req.user.id } : {}),
                    ...(cleanAddress ? { clinic_address: cleanAddress, location: cleanAddress } : {}),
                    ...(cleanCity ? { city: cleanCity } : {}),
                    ...(cleanState ? { state: cleanState } : {}),
                    ...(cleanPincode ? { pincode: cleanPincode } : {}),
                    ...(resolvedLat !== null && resolvedLng !== null ? { latitude: resolvedLat, longitude: resolvedLng } : {}),
                };
                const updated = Object.keys(patch).length > 0
                    ? await Clinic.findByIdAndUpdate(byName.id, patch)
                    : byName;
                return res.status(200).json({
                    success: true,
                    message: 'Existing clinic profile linked.',
                    clinic: formatClinicRecord(updated)
                });
            }
        }
        const isAdminCaller = role === 'superadmin' || role === 'super_admin' || role === 'admin' || role === 'primaryadmin' || role === 'primary_admin';
        if (!isAdminCaller && req.user?.id) {
            const clinic = await Clinic.findOne({ user_id: req.user.id });
            if (clinic) {
                return res.status(200).json({
                    success: true,
                    message: 'Clinic profile already exists.',
                    clinic: formatClinicRecord(clinic)
                });
            }
        }

        const clinic = await Clinic.create({
            userId: req.user?.id || null,
            clinicName: cleanName,
            clinicAddress: cleanAddress,
            location: cleanAddress,
            city: cleanCity,
            state: cleanState,
            pincode: cleanPincode,
            latitude: resolvedLat,
            longitude: resolvedLng,
            services,
            pricing,
            coordinates: coordinates ? { type: 'Point', coordinates } : undefined
        });

        try {
            await Notification.create({
                recipient_role: 'Admin',
                recipient_id: 'ALL_ADMINS',
                title: '🏥 New Clinic Profile Registered',
                message: `Clinic "${cleanName || 'GS Health Clinic'}" registered at ${cleanCity || cleanAddress || 'Healthcare Hub'}.`,
                type: 'clinic_registered'
            });
        } catch (_) { }

        res.status(201).json({
            success: true,
            message: 'Clinic profile created in Supabase PostgreSQL.',
            clinic: formatClinicRecord(clinic, 0)
        });
    } catch (err) {
        console.error('Clinic Profile Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to create clinic profile.' });
    }
};

// 2. GET ALL CLINICS (Dynamic Case-Insensitive Search across Name, ID, City, State, Pincode, Address + Pagination)
exports.getClinics = async (req, res) => {
    const { search, q, service, city, state, pincode, page, pageSize, limit } = req.query;
    try {
        const [rawClinics, allDentists] = await Promise.all([
            Clinic.find({}),
            Dentist.find({}).catch(() => [])
        ]);

        // Compute associated doctors count per clinic (without duplicates)
        const docCountByClinicId = new Map();
        const docCountByClinicName = new Map();
        const seenDocClinicPairs = new Set();
        for (const d of (allDentists || [])) {
            const docKey = String(d.id || d.user_id || '').trim();
            if (!docKey) continue;
            const cId = String(d.clinic_id || d.clinics?.id || '').trim();
            const cNameLower = String(d.clinic_name || d.clinics?.clinic_name || d.clinicName || '').trim().toLowerCase();
            if (cId) {
                const pair = `${cId}|${docKey}`;
                if (!seenDocClinicPairs.has(pair)) {
                    seenDocClinicPairs.add(pair);
                    docCountByClinicId.set(cId, (docCountByClinicId.get(cId) || 0) + 1);
                }
            } else if (cNameLower && cNameLower !== 'independent practice') {
                const pair = `name:${cNameLower}|${docKey}`;
                if (!seenDocClinicPairs.has(pair)) {
                    seenDocClinicPairs.add(pair);
                    docCountByClinicName.set(cNameLower, (docCountByClinicName.get(cNameLower) || 0) + 1);
                }
            }
        }

        let formatted = (rawClinics || []).map((c) => {
            const cId = String(c.id || '').trim();
            const cNameLower = String(c.clinic_name || c.clinicName || '').trim().toLowerCase();
            const count = (cId && docCountByClinicId.has(cId))
                ? docCountByClinicId.get(cId)
                : (docCountByClinicName.get(cNameLower) || 0);
            return formatClinicRecord(c, count);
        });

        const searchKw = String(search || q || '').trim().toLowerCase();
        if (searchKw) {
            formatted = formatted.filter((c) => {
                const hay = [
                    c.clinicName,
                    c.id,
                    c.clinicAddress,
                    c.location,
                    c.city,
                    c.state,
                    c.pincode,
                ].join(' ').toLowerCase();
                return hay.includes(searchKw);
            });
        }
        if (city && String(city).trim()) {
            const cityKw = String(city).trim().toLowerCase();
            formatted = formatted.filter((c) =>
                String(c.city || '').toLowerCase().includes(cityKw) ||
                String(c.clinicAddress || '').toLowerCase().includes(cityKw)
            );
        }
        if (state && String(state).trim()) {
            const stateKw = String(state).trim().toLowerCase();
            formatted = formatted.filter((c) => String(c.state || '').toLowerCase().includes(stateKw));
        }
        if (pincode && String(pincode).trim()) {
            const pinKw = String(pincode).trim();
            formatted = formatted.filter((c) => String(c.pincode || '').includes(pinKw));
        }
        if (service && String(service).trim()) {
            const servKw = String(service).trim().toLowerCase();
            formatted = formatted.filter((c) =>
                (c.services || []).some((s) => String(s || '').toLowerCase().includes(servKw))
            );
        }

        const totalItems = formatted.length;
        const hasPagination = page !== undefined || pageSize !== undefined || limit !== undefined;
        let paginated = formatted;
        let pagination = null;
        if (hasPagination) {
            const safePageSize = Math.min(100, Math.max(1, parseInt(pageSize || limit, 10) || 25));
            const totalPages = Math.max(1, Math.ceil(totalItems / safePageSize));
            const safePage = Math.min(Math.max(1, parseInt(page, 10) || 1), totalPages);
            const start = (safePage - 1) * safePageSize;
            paginated = formatted.slice(start, start + safePageSize);
            pagination = { page: safePage, pageSize: safePageSize, totalItems, totalPages };
        }

        res.json({
            success: true,
            count: paginated.length,
            totalCount: totalItems,
            ...(pagination ? { pagination } : {}),
            clinics: paginated
        });
    } catch (err) {
        res.status(500).json({ success: false, message: 'Failed to fetch clinics list.' });
    }
};

// 3. GET CLINIC DENTISTS (With Dynamic Doctor Search, Specialization, Department Filters & Pagination)
exports.getClinicDentists = async (req, res) => {
    const { clinicId } = req.params;
    try {
        const includeUnavailableRequested = String(req.query.includeUnavailable || '').trim().toLowerCase() === 'true';
        const allowUnavailable = isPrivilegedDoctorViewer(req) && (includeUnavailableRequested || req.query.includeUnavailable === undefined);

        const resolvedScope = await exports.resolveClinicRecordAndDoctorIds(clinicId);
        const canonicalClinicId = resolvedScope.clinicId || clinicId;
        const rawDentists = canonicalClinicId ? await Dentist.find({ clinic_id: canonicalClinicId }) : [];

        // Include clinic_doctors junction associations (when Migration 06 is active) + resolved clinic doctors
        const seenIds = new Set(rawDentists.map(d => String(d.id || '')));
        const seenUserIds = new Set(rawDentists.map(d => String(d.user_id || d.users?.id || '')).filter(Boolean));
        const junctionIds = canonicalClinicId
            ? await ClinicDoctor.getDoctorIdsForClinic(canonicalClinicId).catch(() => [])
            : [];
        const combinedScopedIds = new Set([
            ...(resolvedScope.doctorIds || []).map(id => String(id)),
            ...junctionIds.map(id => String(id)),
        ]);

        if (combinedScopedIds.size > 0) {
            const allDentists = await Dentist.find({});
            for (const d of (allDentists || [])) {
                if (!seenIds.has(String(d.id || '')) && (combinedScopedIds.has(String(d.id || '')) || combinedScopedIds.has(String(d.user_id || '')))) {
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
                const meta = parseUserDeviceMeta(u.device_token);
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

        // Ensure every clinic dentist record has hydrated user full name (never drops to 'Doctor')
        const missingNameUserIds = new Set();
        for (const d of rawDentists) {
            const uObj = Array.isArray(d.users) ? (d.users[0] || {}) : (d.users || {});
            if (!d.name && !uObj.name && d.user_id) {
                missingNameUserIds.add(String(d.user_id));
            }
        }
        if (missingNameUserIds.size > 0) {
            const fallbackUsers = await User.find({ role: { $in: ['DOCTOR', 'Doctor', 'Dentist'] } }).catch(() => []);
            const userMap = new Map((fallbackUsers || []).map(u => [String(u.id), u]));
            for (const d of rawDentists) {
                const uid = String(d.user_id || '');
                if (uid && userMap.has(uid)) {
                    const uObj = Array.isArray(d.users) ? (d.users[0] || {}) : (d.users || {});
                    if (!uObj.name) {
                        d.users = { ...uObj, ...userMap.get(uid) };
                    }
                }
            }
        }

        const formattedDentists = rawDentists.map(formatDentistRecord);
        let visibleDentists = allowUnavailable
            ? formattedDentists
            : formattedDentists.filter(d => d.isAvailable);

        const rawConsultMode = String(req.query.consultationMode || req.query.consultationType || '').trim().toLowerCase();
        if (rawConsultMode === 'online' || rawConsultMode === 'online consultation') {
            visibleDentists = visibleDentists.filter(d => d.onlineConsultationEnabled === true);
        } else if (
            rawConsultMode === 'offline' ||
            rawConsultMode === 'in-person' ||
            rawConsultMode === 'in_person' ||
            rawConsultMode === 'clinic' ||
            rawConsultMode === 'visit clinic' ||
            rawConsultMode === 'offline consultation'
        ) {
            visibleDentists = visibleDentists.filter(d => d.inPersonConsultationEnabled === true);
        }

        // Apply dynamic Doctor Search, Specialization, and Department (existing field) filters
        const searchKw = String(req.query.search || req.query.q || '').trim().toLowerCase();
        const specFilter = String(req.query.specialty || req.query.speciality || '').trim();
        const deptFilter = String(req.query.department || '').trim();

        if (searchKw) {
            const searchDigits = searchKw.replace(/\D/g, '');
            visibleDentists = visibleDentists.filter((d) => {
                const nameMatch = String(d.name || '').toLowerCase().includes(searchKw);
                const specMatch = String(d.specialty || d.speciality || '').toLowerCase().includes(searchKw);
                const idMatch = String(d.id || '').toLowerCase().includes(searchKw) ||
                    String(d.user_id || '').toLowerCase().includes(searchKw);
                const phoneMatch = String(d.phone || '').toLowerCase().includes(searchKw) ||
                    (searchDigits.length >= 3 && String(d.phone || '').replace(/\D/g, '').includes(searchDigits));
                const deptMatch = String(d.department || '').toLowerCase().includes(searchKw);
                return nameMatch || specMatch || idMatch || phoneMatch || deptMatch;
            });
        }
        if (specFilter && specFilter.toLowerCase() !== 'all') {
            visibleDentists = visibleDentists.filter((d) => matchesSpecialtyQuery(d.specialty || d.speciality, specFilter));
        }
        if (deptFilter && deptFilter.toLowerCase() !== 'all') {
            const deptLower = deptFilter.toLowerCase();
            visibleDentists = visibleDentists.filter((d) => String(d.department || '').trim().toLowerCase() === deptLower);
        }

        const totalItems = visibleDentists.length;
        const hasPagination = req.query.page !== undefined || req.query.pageSize !== undefined || req.query.limit !== undefined;
        let paginated = visibleDentists;
        let pagination = null;
        if (hasPagination) {
            const safePageSize = Math.min(100, Math.max(1, parseInt(req.query.pageSize || req.query.limit, 10) || 25));
            const totalPages = Math.max(1, Math.ceil(totalItems / safePageSize));
            const safePage = Math.min(Math.max(1, parseInt(req.query.page, 10) || 1), totalPages);
            const start = (safePage - 1) * safePageSize;
            paginated = visibleDentists.slice(start, start + safePageSize);
            pagination = { page: safePage, pageSize: safePageSize, totalItems, totalPages };
        }

        res.json({
            success: true,
            count: paginated.length,
            totalCount: totalItems,
            ...(pagination ? { pagination } : {}),
            clinic: resolvedScope.clinic ? formatClinicRecord(resolvedScope.clinic, formattedDentists.length) : null,
            dentists: paginated,
            doctors: paginated
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
        const rawConsultationMode = String(req.query.consultationMode || req.query.consultationType || '').trim().toLowerCase();
        if (rawConsultationMode === 'online' || rawConsultationMode === 'online consultation') {
            formattedDentists = formattedDentists.filter(d => d.onlineConsultationEnabled === true && (allowUnavailable || d.isAvailable));
        } else if (
            rawConsultationMode === 'offline' ||
            rawConsultationMode === 'in-person' ||
            rawConsultationMode === 'in_person' ||
            rawConsultationMode === 'clinic' ||
            rawConsultationMode === 'visit clinic' ||
            rawConsultationMode === 'offline consultation'
        ) {
            formattedDentists = formattedDentists.filter(d => d.inPersonConsultationEnabled === true && (allowUnavailable || d.isAvailable));
        } else if (onlineOnlyRequested) {
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

        // Optional date & timeSlot availability filtering
        const filterDateRaw = String(req.query.date || req.query.appointmentDate || '').trim();
        const filterTimeSlotRaw = String(req.query.timeSlot || req.query.slot || '').trim();
        if (filterDateRaw || filterTimeSlotRaw) {
            const { DoctorAvailability, Appointment } = require('../models/Schemas');
            const { sanitizeSmartSchedule, generateDynamicSlots } = require('../services/smartSchedulingEngine');
            const cleanDate = filterDateRaw ? DoctorAvailability.extractDateYmd(filterDateRaw) : DoctorAvailability.extractDateYmd(new Date());
            const targetModeForSlots = (rawConsultationMode === 'online' || rawConsultationMode === 'online consultation')
                ? 'Online'
                : 'In-Person';
            const filteredBySchedule = [];
            for (const doc of formattedDentists) {
                try {
                    const [availRec, rawSched, allAppts, blockedSlots] = await Promise.all([
                        DoctorAvailability.findOne({ dentist_id: doc.id, date: cleanDate }).catch(() => null),
                        DoctorAvailability.getSchedule(doc.id).catch(() => null),
                        Appointment.find({ dentistId: doc.id }).catch(() => []),
                        DoctorAvailability.getBlockedSlotsForDate(doc.id, cleanDate).catch(() => []),
                    ]);
                    if (availRec && availRec.is_blocked) continue;
                    const schedule = sanitizeSmartSchedule({
                        ...(rawSched || {}),
                        onlineEnabled: doc.onlineConsultationEnabled,
                        inPersonEnabled: doc.inPersonConsultationEnabled,
                    });
                    const activeAppts = (allAppts || []).filter(a => {
                        const st = String(a.status || '').toUpperCase();
                        if (st === 'CANCELLED' || st === 'REJECTED' || st === 'NO_SHOW') return false;
                        return DoctorAvailability.extractDateYmd(a.date || a.appointment_date) === cleanDate;
                    });
                    const dynamic = generateDynamicSlots({
                        schedule,
                        dateYmd: cleanDate,
                        consultationType: targetModeForSlots,
                        activeAppointments: activeAppts,
                        blockedSlots,
                        explicitDateRecord: availRec,
                    });
                    if (dynamic.isBlocked || !dynamic.isWorkingDay || (dynamic.availableSlots || []).length === 0) {
                        continue;
                    }
                    if (filterTimeSlotRaw) {
                        const slotGoal = filterTimeSlotRaw.toLowerCase();
                        const hasSlot = (dynamic.availableSlots || []).some(s => String(s || '').trim().toLowerCase() === slotGoal);
                        if (!hasSlot) continue;
                    }
                    doc.availableSlots = dynamic.availableSlots;
                    filteredBySchedule.push(doc);
                } catch (_) {
                    filteredBySchedule.push(doc);
                }
            }
            formattedDentists = filteredBySchedule;
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
                    try { meta = JSON.parse(docUser.device_token); } catch (_) { }
                }
                meta.onlineStatus = resolvedOnlinePresence;
                await User.findByIdAndUpdate(existingDoctor.user_id, { device_token: JSON.stringify(meta) });
            } catch (_) { }
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

// 9. UPDATE DOCTOR PROFESSIONAL PROFILE (Specialty, Qualification, Experience, Clinic, Location, Availability)
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
        clinic_name,
        clinicAddress,
        clinic_address,
        consultationFee,
        consultation_fee,
        bio,
        city,
        pincode,
        state,
        latitude,
        longitude,
        clearLocation,
        status,
        availability_status,
        languages,
        languagesKnown,
        phone,
        profilePhoto,
        removeProfilePhoto,
        onlineConsultationEnabled,
        online_consultation_enabled,
        supportsOnlineConsultation,
        inPersonConsultationEnabled,
        in_person_consultation_enabled,
        supportsInPersonConsultation,
        consultationMode
    } = req.body;
    try {
        if (!id) {
            return res.status(400).json({ success: false, message: 'Doctor ID is required.' });
        }

        const { User, DoctorAvailability } = require('../models/Schemas');
        const { _resolveAndUploadProfilePhoto } = require('./authController');
        const { validateCoordinates } = require('../utils/doctorClinicLocationHelper');

        const parseBoolOpt = (v) => {
            if (typeof v === 'boolean') return v;
            if (typeof v === 'number') return v !== 0;
            if (typeof v === 'string') {
                const s = v.trim().toLowerCase();
                if (s === 'true' || s === '1' || s === 'yes' || s === 'on') return true;
                if (s === 'false' || s === '0' || s === 'no' || s === 'off') return false;
            }
            return undefined;
        };
        let requestedOnlineFlag = parseBoolOpt(
            onlineConsultationEnabled ?? online_consultation_enabled ?? supportsOnlineConsultation
        );
        let requestedInPersonFlag = parseBoolOpt(
            inPersonConsultationEnabled ?? in_person_consultation_enabled ?? supportsInPersonConsultation
        );
        if (consultationMode && typeof consultationMode === 'string') {
            const cm = consultationMode.trim().toLowerCase();
            if (cm === 'both' || cm === 'hybrid') {
                if (requestedOnlineFlag === undefined) requestedOnlineFlag = true;
                if (requestedInPersonFlag === undefined) requestedInPersonFlag = true;
            } else if (cm === 'online' || cm === 'online only' || cm === 'online_only') {
                if (requestedOnlineFlag === undefined) requestedOnlineFlag = true;
                if (requestedInPersonFlag === undefined) requestedInPersonFlag = false;
            } else if (cm === 'offline' || cm === 'in-person' || cm === 'in_person' || cm === 'offline only' || cm === 'in-person only') {
                if (requestedOnlineFlag === undefined) requestedOnlineFlag = false;
                if (requestedInPersonFlag === undefined) requestedInPersonFlag = true;
            }
        }
        if (requestedOnlineFlag !== undefined || requestedInPersonFlag !== undefined) {
            const existingDocForMode = await Dentist.findById(id).catch(() => null);
            const currentModes = resolveDoctorConsultationModes(existingDocForMode || {});
            const nextOnline = requestedOnlineFlag !== undefined ? requestedOnlineFlag : currentModes.onlineConsultationEnabled;
            const nextInPerson = requestedInPersonFlag !== undefined ? requestedInPersonFlag : currentModes.inPersonConsultationEnabled;
            if (!nextOnline && !nextInPerson) {
                return res.status(400).json({
                    success: false,
                    code: 'INVALID_CONSULTATION_MODES',
                    message: 'At least one consultation mode (Online Consultation or In-Person Clinic Consultation) must be enabled.'
                });
            }
            requestedOnlineFlag = nextOnline;
            requestedInPersonFlag = nextInPerson;
        }

        const cleanPincode = pincode !== undefined && pincode !== null ? String(pincode).trim() : undefined;
        if (cleanPincode !== undefined && cleanPincode.length > 0 && !/^\d{6}$/.test(cleanPincode)) {
            return res.status(400).json({ success: false, message: 'Please enter a valid 6-digit pincode.' });
        }

        const coordValidation = validateCoordinates(latitude, longitude, clearLocation === true);
        if (!coordValidation.ok) {
            return res.status(400).json({ success: false, message: coordValidation.message });
        }

        const hasExplicitPhotoField = Object.prototype.hasOwnProperty.call(req.body || {}, 'profilePhoto');
        const shouldRemovePhoto = removeProfilePhoto === true ||
            (hasExplicitPhotoField && (profilePhoto === null || String(profilePhoto).trim() === '' || String(profilePhoto).trim().toLowerCase() === 'null'));

        let uploadedPhotoUrl;
        if (shouldRemovePhoto) {
            uploadedPhotoUrl = null;
        } else if (hasExplicitPhotoField && profilePhoto) {
            const photoResolution = await _resolveAndUploadProfilePhoto(profilePhoto, { roleFolder: 'doctors' });
            if (!photoResolution.ok) {
                return res.status(photoResolution.status || 400).json({
                    success: false,
                    code: photoResolution.code || 'PROFILE_IMAGE_UPLOAD_FAILED',
                    message: photoResolution.message || 'Failed to upload profile image.'
                });
            }
            uploadedPhotoUrl = photoResolution.photoUrl;
        }

        const normalizedLanguages = (languages !== undefined || languagesKnown !== undefined)
            ? normalizeLanguagesList(languages ?? languagesKnown)
            : null;
        const requestedSpec = (specialty || speciality || specialtyName || medicalSpecialty || '').toString().trim();
        const requestedSpecId = (specialtyId || specialty_id || '').toString().trim() || undefined;
        const incomingClinicName = clinicName !== undefined ? clinicName : clinic_name;
        const incomingClinicAddress = clinicAddress !== undefined ? clinicAddress : clinic_address;
        const cleanClinicName = incomingClinicName !== undefined && incomingClinicName !== null
            ? String(incomingClinicName).trim()
            : undefined;
        const cleanClinicAddress = incomingClinicAddress !== undefined && incomingClinicAddress !== null
            ? String(incomingClinicAddress).trim()
            : undefined;
        const cleanState = state !== undefined && state !== null ? String(state).trim() : undefined;
        const cleanCity = city !== undefined && city !== null ? String(city).trim() : undefined;

        let clinicId = undefined;
        if (cleanClinicName && cleanClinicName.length > 0) {
            let clinic = await Clinic.findOne({ clinic_name: cleanClinicName });
            const composedLoc = cleanClinicAddress && cleanClinicAddress.length > 0
                ? cleanClinicAddress
                : (cleanCity ? `${cleanCity}${cleanPincode ? ' - ' + cleanPincode : ''}` : 'GS HEALTH Medical Center');
            if (!clinic) {
                clinic = await Clinic.create({
                    clinic_name: cleanClinicName,
                    location: composedLoc,
                    latitude: coordValidation.hasUpdate ? coordValidation.latitude : null,
                    longitude: coordValidation.hasUpdate ? coordValidation.longitude : null,
                    verified: true,
                    services: [requestedSpec || 'General Medicine']
                });
            } else {
                const clinicPatch = {};
                if (cleanClinicAddress && cleanClinicAddress.length > 0) {
                    clinicPatch.location = cleanClinicAddress;
                }
                if (coordValidation.hasUpdate && coordValidation.latitude !== null && coordValidation.longitude !== null) {
                    clinicPatch.latitude = coordValidation.latitude;
                    clinicPatch.longitude = coordValidation.longitude;
                }
                if (Object.keys(clinicPatch).length > 0) {
                    await Clinic.findByIdAndUpdate(clinic.id, clinicPatch);
                }
            }
            if (clinic && clinic.id) clinicId = clinic.id;
        }

        const dentistUpdatePayload = {
            ...(requestedSpec ? { speciality: requestedSpec } : {}),
            ...(requestedSpecId ? { specialty_id: requestedSpecId } : {}),
            ...(department ? { department } : {}),
            ...(qualification || qualifications ? { qualifications: qualification || qualifications } : {}),
            ...(experienceYears !== undefined || experience_years !== undefined ? { experience_years: experienceYears ?? experience_years } : {}),
            ...(licenseNumber || license_number ? { license_number: licenseNumber || license_number } : {}),
            ...(consultationFee !== undefined || consultation_fee !== undefined ? { consultation_fee: consultationFee ?? consultation_fee } : {}),
            ...(bio !== undefined ? { bio } : {}),
            ...(status || availability_status ? { availability_status: status || availability_status } : {}),
            ...(clinicId !== undefined ? { clinic_id: clinicId } : {}),
            ...(cleanClinicName !== undefined ? { clinic_name: cleanClinicName } : {}),
            ...(cleanClinicAddress !== undefined ? { clinic_address: cleanClinicAddress } : {}),
            ...(cleanState !== undefined ? { state: cleanState } : {}),
            ...(cleanPincode !== undefined ? { pincode: cleanPincode } : {}),
            ...(coordValidation.hasUpdate ? { latitude: coordValidation.latitude, longitude: coordValidation.longitude } : {}),
            ...(cleanCity !== undefined ? { city: cleanCity } : {}),
            ...(normalizedLanguages && normalizedLanguages.length > 0 ? { languages: normalizedLanguages } : {}),
            ...(requestedOnlineFlag !== undefined ? { online_consultation_enabled: requestedOnlineFlag } : {}),
            ...(requestedInPersonFlag !== undefined ? { in_person_consultation_enabled: requestedInPersonFlag } : {})
        };

        const updatedDentist = await Dentist.findByIdAndUpdate(id, dentistUpdatePayload);

        const targetUserId = updatedDentist?.user_id || id;
        let existingUserMeta = {};
        try {
            const existingUserRow = await User.findById(targetUserId).catch(() => null);
            if (existingUserRow?.device_token && typeof existingUserRow.device_token === 'string' && existingUserRow.device_token.trim().startsWith('{')) {
                existingUserMeta = JSON.parse(existingUserRow.device_token);
            }
        } catch (_) { }
        const metaPatch = { ...existingUserMeta };
        if (cleanClinicName !== undefined) metaPatch.clinicName = cleanClinicName;
        if (cleanClinicAddress !== undefined) metaPatch.clinicAddress = cleanClinicAddress;
        if (cleanState !== undefined) metaPatch.state = cleanState;
        if (cleanPincode !== undefined) metaPatch.pincode = cleanPincode;
        if (coordValidation.hasUpdate) {
            metaPatch.latitude = coordValidation.latitude;
            metaPatch.longitude = coordValidation.longitude;
        }
        if (requestedOnlineFlag !== undefined) {
            metaPatch.onlineConsultationEnabled = requestedOnlineFlag;
            metaPatch.online_consultation_enabled = requestedOnlineFlag;
        }
        if (requestedInPersonFlag !== undefined) {
            metaPatch.inPersonConsultationEnabled = requestedInPersonFlag;
            metaPatch.in_person_consultation_enabled = requestedInPersonFlag;
        }
        const hasMetaChanges =
            cleanClinicName !== undefined ||
            cleanClinicAddress !== undefined ||
            cleanState !== undefined ||
            cleanPincode !== undefined ||
            coordValidation.hasUpdate ||
            requestedOnlineFlag !== undefined ||
            requestedInPersonFlag !== undefined;
        const userUpdates = {
            ...(name ? { name } : {}),
            ...(phone ? { phone } : {}),
            ...(cleanCity !== undefined ? { city: cleanCity } : {}),
            ...(cleanPincode !== undefined ? { pincode: cleanPincode } : {}),
            ...(cleanState !== undefined ? { state: cleanState } : {}),
            ...(coordValidation.hasUpdate ? { latitude: coordValidation.latitude, longitude: coordValidation.longitude } : {}),
            ...(normalizedLanguages && normalizedLanguages.length > 0 ? { languages: normalizedLanguages } : {}),
            ...(uploadedPhotoUrl !== undefined ? { biometric_token: uploadedPhotoUrl } : {}),
            ...(hasMetaChanges ? { device_token: JSON.stringify(metaPatch) } : {})
        };
        if (Object.keys(userUpdates).length > 0) {
            try {
                await User.findByIdAndUpdate(targetUserId, userUpdates);
            } catch (_) { }
        }
        if (requestedOnlineFlag !== undefined || requestedInPersonFlag !== undefined) {
            try {
                const targetDocId = updatedDentist?.id || id;
                const currentSched = await DoctorAvailability.getSchedule(targetDocId).catch(() => null);
                if (currentSched && currentSched.isConfigured) {
                    await DoctorAvailability.saveSchedule(targetDocId, {
                        ...currentSched,
                        ...(requestedOnlineFlag !== undefined ? { onlineEnabled: requestedOnlineFlag } : {}),
                        ...(requestedInPersonFlag !== undefined ? { inPersonEnabled: requestedInPersonFlag } : {}),
                    });
                }
            } catch (_) { }
        }

        const refreshed = await Dentist.findById(updatedDentist?.id || id) || updatedDentist;
        const formattedDoctor = refreshed ? formatDentistRecord(refreshed) : updatedDentist;
        if (formattedDoctor) {
            if (uploadedPhotoUrl !== undefined) formattedDoctor.profilePhoto = uploadedPhotoUrl;
            if (cleanClinicName !== undefined) formattedDoctor.clinicName = cleanClinicName;
            if (cleanClinicAddress !== undefined) formattedDoctor.clinicAddress = cleanClinicAddress;
            if (cleanState !== undefined) formattedDoctor.state = cleanState;
            if (cleanPincode !== undefined) formattedDoctor.pincode = cleanPincode;
            if (coordValidation.hasUpdate) {
                formattedDoctor.latitude = coordValidation.latitude;
                formattedDoctor.longitude = coordValidation.longitude;
            }
            if (requestedOnlineFlag !== undefined) {
                formattedDoctor.onlineConsultationEnabled = requestedOnlineFlag;
                formattedDoctor.online_consultation_enabled = requestedOnlineFlag;
                formattedDoctor.supportsOnlineConsultation = Boolean(formattedDoctor.isAvailable && requestedOnlineFlag);
            }
            if (requestedInPersonFlag !== undefined) {
                formattedDoctor.inPersonConsultationEnabled = requestedInPersonFlag;
                formattedDoctor.in_person_consultation_enabled = requestedInPersonFlag;
                formattedDoctor.supportsInPersonConsultation = Boolean(formattedDoctor.isAvailable && requestedInPersonFlag);
            }
        }
        res.json({
            success: true,
            message: 'Doctor professional profile updated successfully.',
            doctor: formattedDoctor
        });
    } catch (err) {
        console.error('Update Doctor Profile Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to update doctor profile.' });
    }
};

// 10. UPDATE CLINIC DETAILS, LOCATION & DEPARTMENTS (Multi-Specialty Clinic Management)
exports.updateClinicDepartments = async (req, res) => {
    if (!ensureClinicOrDoctorMutationAuth(req, res)) return;
    const { id } = req.params;
    const {
        clinicName,
        clinicAddress,
        location,
        city,
        state,
        pincode,
        latitude,
        longitude,
        departments,
        services,
        pricing
    } = req.body;
    try {
        const cleanPincode = pincode !== undefined ? String(pincode || '').trim() : undefined;
        if (cleanPincode !== undefined && cleanPincode.length > 0 && !isValidIndianPincode(cleanPincode)) {
            return res.status(400).json({ success: false, message: 'Please enter a valid 6-digit pincode.' });
        }
        const coordCheck = validateCoordinates(latitude, longitude, false);
        if (!coordCheck.ok) {
            return res.status(400).json({ success: false, message: coordCheck.message });
        }

        const mergedServices = Array.isArray(departments) && departments.length > 0
            ? departments
            : (Array.isArray(services) ? services : undefined);

        const cleanAddress = clinicAddress !== undefined
            ? String(clinicAddress || '').trim()
            : (location !== undefined ? String(location || '').trim() : undefined);
        const cleanCity = city !== undefined ? String(city || '').trim() : undefined;
        const cleanState = state !== undefined ? String(state || '').trim() : undefined;

        const updatePayload = {};
        if (clinicName !== undefined && String(clinicName).trim()) updatePayload.clinic_name = String(clinicName).trim();
        if (cleanAddress !== undefined) {
            updatePayload.clinic_address = cleanAddress;
            updatePayload.location = cleanAddress;
        }
        if (cleanCity !== undefined) updatePayload.city = cleanCity;
        if (cleanState !== undefined) updatePayload.state = cleanState;
        if (cleanPincode !== undefined) updatePayload.pincode = cleanPincode;
        if (coordCheck.hasUpdate) {
            updatePayload.latitude = coordCheck.latitude;
            updatePayload.longitude = coordCheck.longitude;
        }
        if (mergedServices) updatePayload.services = mergedServices;
        if (pricing) updatePayload.pricing = pricing;

        let clinic = null;
        if (id && id !== 'default') {
            clinic = await Clinic.findByIdAndUpdate(id, updatePayload);
        } else if (clinicName) {
            const existing = await Clinic.findOne({ clinic_name: String(clinicName).trim() });
            if (existing) {
                clinic = await Clinic.findByIdAndUpdate(existing.id, updatePayload);
            } else {
                clinic = await Clinic.create({
                    clinic_name: String(clinicName).trim(),
                    clinic_address: cleanAddress || 'GS HEALTH Multi-Specialty Center',
                    location: cleanAddress || 'GS HEALTH Multi-Specialty Center',
                    city: cleanCity || '',
                    state: cleanState || '',
                    pincode: cleanPincode || '',
                    latitude: coordCheck.hasUpdate ? coordCheck.latitude : null,
                    longitude: coordCheck.hasUpdate ? coordCheck.longitude : null,
                    services: mergedServices || ['General Medicine', 'Dentistry'],
                    pricing: pricing || []
                });
            }
        }

        // Sync structured address/coordinates to linked clinic owner user row for pre-Migration-06 persistence
        if (clinic?.user_id) {
            try {
                const ownerUser = await User.findById(clinic.user_id).catch(() => null);
                if (ownerUser) {
                    const existingMeta = parseUserDeviceMeta(ownerUser.device_token);
                    const nextMeta = {
                        ...existingMeta,
                        ...(updatePayload.clinic_name ? { clinicName: updatePayload.clinic_name } : {}),
                        ...(cleanAddress !== undefined ? { clinicAddress: cleanAddress, location: cleanAddress } : {}),
                        ...(cleanCity !== undefined ? { city: cleanCity } : {}),
                        ...(cleanState !== undefined ? { state: cleanState } : {}),
                        ...(cleanPincode !== undefined ? { pincode: cleanPincode } : {}),
                        ...(coordCheck.hasUpdate ? { latitude: coordCheck.latitude, longitude: coordCheck.longitude } : {}),
                    };
                    await User.findByIdAndUpdate(ownerUser.id, {
                        ...(cleanCity !== undefined ? { city: cleanCity } : {}),
                        ...(cleanState !== undefined ? { state: cleanState } : {}),
                        ...(cleanPincode !== undefined ? { pincode: cleanPincode } : {}),
                        ...(coordCheck.hasUpdate ? { latitude: coordCheck.latitude, longitude: coordCheck.longitude } : {}),
                        device_token: JSON.stringify(nextMeta),
                    }).catch(() => null);
                }
            } catch (_) { }
        }

        res.json({
            success: true,
            message: 'Clinic profile and departments updated successfully.',
            clinic: clinic ? formatClinicRecord(clinic) : null
        });
    } catch (err) {
        console.error('Update Clinic Departments Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to update clinic details.' });
    }
};

// 10b. ADD NEW DOCTOR DIRECTLY UNDER A CLINIC (Supports Multiple Doctors per Clinic)
exports.addClinicDoctor = async (req, res) => {
    if (!ensureClinicOrDoctorMutationAuth(req, res)) return;
    const { clinicId } = req.params;
    const {
        name,
        fullName,
        full_name,
        firstName,
        first_name,
        middleName,
        middle_name,
        lastName,
        last_name,
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
        clinicAddress,
        clinic_address,
        latitude,
        longitude,
        profilePhoto,
        languages,
        clinicName,
        rejectExistingAccount,
        preventDuplicateAccount
    } = req.body;
    try {
        const combinedPartsName = combineNameParts({
            firstName,
            first_name,
            middleName,
            middle_name,
            lastName,
            last_name
        });
        const rawCandidateName = String(fullName || full_name || name || combinedPartsName || '').replace(/\s+/g, ' ').trim();
        const cleanName = (combinedPartsName && combinedPartsName.split(' ').length > rawCandidateName.split(' ').length)
            ? combinedPartsName
            : rawCandidateName;
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

        // Also check dentists table directly in case a dentist row exists with this 10-digit mobile
        let existingDentistByPhone = null;
        if (user) {
            existingDentistByPhone = await Dentist.findOne({ user_id: user.id }).catch(() => null);
        }
        if (!existingDentistByPhone) {
            const allDentists = await Dentist.find({}).catch(() => []);
            existingDentistByPhone = (allDentists || []).find((d) => {
                const dDigits = String(d.phone || d.users?.phone || '').replace(/[^0-9]/g, '');
                return dDigits.length >= 10 && dDigits.slice(-10) === cleanPhone.slice(-10);
            }) || null;
        }

        const shouldRejectDuplicate = Boolean(rejectExistingAccount || preventDuplicateAccount);
        if (shouldRejectDuplicate && (user || existingDentistByPhone)) {
            const existingFormatted = existingDentistByPhone
                ? formatDentistRecord({ ...existingDentistByPhone, users: existingDentistByPhone.users || user || {} })
                : {
                    id: user.id,
                    user_id: user.id,
                    userId: user.id,
                    name: user.name || 'Doctor',
                    phone: user.phone || cleanPhone,
                    email: user.email || '',
                    specialty: resolvedSpec,
                    qualification: resolvedQual,
                    experience_years: resolvedExp,
                    clinic_id: null,
                    clinicName: ''
                };
            const alreadyInThisClinic = Boolean(
                canonicalClinicId &&
                String(existingDentistByPhone?.clinic_id || existingFormatted.clinic_id || '').trim() === String(canonicalClinicId).trim()
            );
            return res.status(409).json({
                success: false,
                code: 'MOBILE_ALREADY_REGISTERED',
                existingRole: user?.role || 'DOCTOR',
                existingDoctor: existingFormatted,
                alreadyInThisClinic,
                message: alreadyInThisClinic
                    ? `${existingFormatted.name} (${cleanPhone}) is already registered and associated with this clinic.`
                    : `A registered doctor account (${existingFormatted.name}) already exists for mobile number ${cleanPhone}. You can attach the existing account to this clinic instead of creating a duplicate.`
            });
        }

        const rawPhotoStr = (profilePhoto !== undefined && profilePhoto !== null && String(profilePhoto).trim() !== '' && String(profilePhoto).trim().toLowerCase() !== 'null')
            ? String(profilePhoto).trim()
            : null;
        const effectiveAddress = String(clinicAddress || clinic_address || targetClinic?.clinic_address || targetClinic?.location || '').trim();
        const effectiveCity = String(city || targetClinic?.city || '').trim();
        const effectiveState = String(state || targetClinic?.state || '').trim();
        const effectivePincode = String(pincode || targetClinic?.pincode || '').trim();
        const effectiveLat = (latitude !== undefined && latitude !== null && Number.isFinite(Number(latitude)))
            ? Number(latitude)
            : (targetClinic?.latitude ?? null);
        const effectiveLng = (longitude !== undefined && longitude !== null && Number.isFinite(Number(longitude)))
            ? Number(longitude)
            : (targetClinic?.longitude ?? null);

        let licNum = String(licenseNumber || license_number || '').trim();
        if (!licNum || licNum.toLowerCase() === 'med-lic-reg' || licNum.toLowerCase() === 'med-lic-registered') {
            licNum = `MED-LIC-${Date.now()}-${Math.floor(1000 + Math.random() * 9000)}`;
        } else {
            const existingLic = await Dentist.findOne({ license_number: licNum }).catch(() => null);
            if (existingLic && (!user || String(existingLic.user_id) !== String(user.id))) {
                licNum = `${licNum}-${Date.now().toString().slice(-4)}`;
            }
        }

        if (!user) {
            const generatedEmail = (cleanEmailInput && cleanEmailInput.includes('@'))
                ? cleanEmailInput
                : `user_${cleanPhone}@dentaguru.internal`;
            const effectivePassword = `OTP_SECURE_${require('crypto').randomBytes(12).toString('hex')}`;
            const formattedDocName = normalizeDoctorDisplayName(cleanName);
            const metaObj = {
                fullName: formattedDocName,
                city: effectiveCity,
                state: effectiveState,
                pincode: effectivePincode,
                location: effectiveAddress,
                address: effectiveAddress,
                clinicAddress: effectiveAddress,
                latitude: effectiveLat,
                longitude: effectiveLng,
                languages: finalLangs,
                specialty: resolvedSpec,
                specialtyId: specResolution.specialty_id || null,
                department: specResolution.department || '',
                qualification: resolvedQual,
                experienceYears: resolvedExp,
                clinicId: canonicalClinicId,
                clinicName: resolvedClinicName,
                licenseNumber: licNum,
                ...(rawPhotoStr ? { profilePhoto: rawPhotoStr } : {})
            };
            user = await User.create({
                name: formattedDocName,
                email: generatedEmail,
                password: effectivePassword,
                phone: cleanPhone,
                role: 'DOCTOR',
                state: effectiveState,
                city: effectiveCity,
                pincode: effectivePincode,
                latitude: effectiveLat,
                longitude: effectiveLng,
                languages: finalLangs,
                device_token: JSON.stringify(metaObj),
                ...(rawPhotoStr ? { biometric_token: rawPhotoStr } : {})
            });
        }

        // Check if this user already has a dentists row
        let dentistRec = existingDentistByPhone || await Dentist.findOne({ user_id: user.id }).catch(() => null);
        if (dentistRec) {
            dentistRec = await Dentist.findByIdAndUpdate(dentistRec.id, {
                ...(canonicalClinicId ? { clinic_id: canonicalClinicId } : {}),
                ...(resolvedClinicName ? { clinic_name: resolvedClinicName } : {}),
                ...(effectiveAddress ? { clinic_address: effectiveAddress } : {}),
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
                clinic_name: resolvedClinicName,
                clinic_address: effectiveAddress,
                speciality: resolvedSpec,
                specialty_id: specResolution.specialty_id || null,
                department: specResolution.department || '',
                license_number: licNum,
                experience_years: resolvedExp,
                qualifications: resolvedQual,
                availability_status: 'Available',
                consultation_fee: String(consultationFee || consultation_fee || ''),
                bio: String(bio || ''),
                state: effectiveState,
                city: effectiveCity,
                pincode: effectivePincode,
                latitude: effectiveLat,
                longitude: effectiveLng,
                languages: finalLangs,
                rating: 5.0,
                reviews_count: 0
            });
        }

        if (canonicalClinicId && dentistRec?.id) {
            await ClinicDoctor.associate(canonicalClinicId, dentistRec.id).catch(() => null);
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

        const fetchedAfterSave = dentistRec?.id ? await Dentist.findById(dentistRec.id).catch(() => null) : null;
        const fetchedUserObj = fetchedAfterSave
            ? (Array.isArray(fetchedAfterSave.users) ? (fetchedAfterSave.users[0] || {}) : (fetchedAfterSave.users || {}))
            : {};
        const refreshedDoctor = {
            ...(dentistRec || {}),
            ...(fetchedAfterSave || {}),
            name: fetchedUserObj.name || user?.name || normalizeDoctorDisplayName(cleanName),
            users: fetchedUserObj.name ? fetchedAfterSave.users : user,
            clinics: (fetchedAfterSave && fetchedAfterSave.clinics && Object.keys(fetchedAfterSave.clinics).length > 0)
                ? fetchedAfterSave.clinics
                : (targetClinic || {})
        };
        const formatted = formatDentistRecord(refreshedDoctor);
        const allClinicDoctors = canonicalClinicId
            ? (await Dentist.find({ clinic_id: canonicalClinicId }).catch(() => [])).map((d) => {
                const du = Array.isArray(d.users) ? (d.users[0] || {}) : (d.users || {});
                if (!du.name && String(d.user_id || '') === String(user?.id || '')) {
                    return formatDentistRecord({ ...d, users: user, clinics: d.clinics || targetClinic || {} });
                }
                return formatDentistRecord(d);
            })
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

// 11. ASSOCIATE ONE OR MULTIPLE EXISTING REGISTERED DOCTORS WITH CLINIC (No Duplicate Accounts or Duplicate Associations)
exports.associateClinicDoctor = async (req, res) => {
    if (!ensureClinicOrDoctorMutationAuth(req, res)) return;
    const { clinicId } = req.params;
    const {
        doctorId,
        doctorIds,
        phone,
        email,
        licenseNumber,
        clinicName,
        specialty,
        consultationFee,
        availableDays,
        availableSlots
    } = req.body;
    try {
        let resolvedClinic = null;
        let resolvedClinicId = clinicId && clinicId !== 'default' ? String(clinicId).trim() : '';
        if (resolvedClinicId) {
            resolvedClinic = await Clinic.findById(resolvedClinicId).catch(() => null);
        }
        if (!resolvedClinic && clinicName && String(clinicName).trim()) {
            resolvedClinic = await Clinic.findOne({ clinic_name: String(clinicName).trim() }).catch(() => null);
            if (resolvedClinic?.id) resolvedClinicId = String(resolvedClinic.id).trim();
        }
        if (!resolvedClinicId) {
            return res.status(400).json({
                success: false,
                message: 'A valid registered Clinic ID is required to associate doctors.'
            });
        }

        const requestedIds = Array.isArray(doctorIds)
            ? Array.from(new Set(doctorIds.map(v => String(v || '').trim()).filter(Boolean)))
            : (doctorId ? [String(doctorId).trim()] : []);

        const allDentists = await Dentist.find({}).catch(() => []);
        const findExistingRegisteredDoctor = async (lookupId = '') => {
            if (lookupId) {
                const direct = await Dentist.findById(lookupId).catch(() => null)
                    || await Dentist.findOne({ user_id: lookupId }).catch(() => null)
                    || allDentists.find(d => String(d.id) === lookupId || String(d.user_id) === lookupId);
                if (direct) return direct;
            }
            if (phone || email || licenseNumber) {
                const qPhone = String(phone || '').replace(/[^0-9]/g, '');
                const qEmail = String(email || '').trim().toLowerCase();
                const qLic = String(licenseNumber || '').trim().toLowerCase();
                return allDentists.find(d => {
                    const dPhone = String(d.phone || d.users?.phone || '').replace(/[^0-9]/g, '');
                    if (qPhone.length >= 10 && dPhone.length >= 10 && dPhone.slice(-10) === qPhone.slice(-10)) return true;
                    if (qEmail && String(d.email || d.users?.email || '').toLowerCase() === qEmail) return true;
                    if (qLic && String(d.license_number || '').toLowerCase() === qLic) return true;
                    return false;
                }) || null;
            }
            return null;
        };

        const existingAssocIds = new Set(
            (await ClinicDoctor.getDoctorIdsForClinic(resolvedClinicId).catch(() => [])).map(String)
        );
        for (const d of allDentists) {
            if (String(d.clinic_id || '').trim() === resolvedClinicId) {
                existingAssocIds.add(String(d.id));
            }
        }

        const targets = requestedIds.length > 0 ? requestedIds : ['__lookup__'];
        const associatedDoctors = [];
        const alreadyAssociated = [];
        const notFound = [];

        for (const tid of targets) {
            const targetDoctor = await findExistingRegisteredDoctor(tid === '__lookup__' ? '' : tid);
            if (!targetDoctor) {
                notFound.push(tid);
                continue;
            }
            const canonicalDocId = String(targetDoctor.id).trim();
            const isDuplicateInClinic = existingAssocIds.has(canonicalDocId) ||
                String(targetDoctor.clinic_id || '').trim() === resolvedClinicId;

            if (isDuplicateInClinic) {
                alreadyAssociated.push(formatDentistRecord(targetDoctor));
                continue;
            }

            // Record association in clinic_doctors (when migrated) AND synchronize dentists.clinic_id
            const assocRes = await ClinicDoctor.associate(resolvedClinicId, canonicalDocId);
            if (assocRes.duplicate) {
                alreadyAssociated.push(formatDentistRecord(targetDoctor));
                continue;
            }

            const updated = await Dentist.findByIdAndUpdate(canonicalDocId, {
                clinic_id: resolvedClinicId,
                ...(specialty ? { speciality: specialty } : {}),
                ...(resolvedClinic?.clinic_name ? { clinic_name: resolvedClinic.clinic_name } : {}),
            });
            existingAssocIds.add(canonicalDocId);
            const updatedUserObj = updated
                ? (Array.isArray(updated.users) ? (updated.users[0] || {}) : (updated.users || {}))
                : {};
            const hydratedAssocRecord = {
                ...targetDoctor,
                ...(updated || {}),
                clinic_id: resolvedClinicId,
                ...(resolvedClinic?.clinic_name ? { clinic_name: resolvedClinic.clinic_name } : {}),
                users: updatedUserObj.name ? updated.users : (targetDoctor.users || {}),
                clinics: (updated?.clinics && Object.keys(updated.clinics).length > 0)
                    ? updated.clinics
                    : (resolvedClinic || targetDoctor.clinics || {}),
            };
            associatedDoctors.push(formatDentistRecord(hydratedAssocRecord));
        }

        if (associatedDoctors.length === 0 && alreadyAssociated.length > 0 && notFound.length === 0) {
            return res.status(409).json({
                success: false,
                code: 'ALREADY_ASSOCIATED',
                message: 'Selected doctor is already associated with this clinic.',
                alreadyAssociated
            });
        }

        if (associatedDoctors.length === 0 && alreadyAssociated.length === 0) {
            return res.status(404).json({
                success: false,
                message: 'No existing registered GS HEALTH doctor account found matching the provided details.'
            });
        }

        res.json({
            success: true,
            associated: true,
            addedCount: associatedDoctors.length,
            duplicateSkippedCount: alreadyAssociated.length,
            message: associatedDoctors.length > 1
                ? `${associatedDoctors.length} existing doctors associated with clinic successfully.`
                : 'Existing doctor associated with clinic successfully without creating a duplicate account.',
            doctor: associatedDoctors[0] || alreadyAssociated[0],
            doctors: associatedDoctors,
            alreadyAssociated,
            notFound,
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
    const { clinicId, doctorId } = req.params;
    try {
        if (!doctorId) {
            return res.status(400).json({ success: false, message: 'Doctor ID is required.' });
        }

        const existingDoc = await Dentist.findById(doctorId).catch(() => null)
            || await Dentist.findOne({ user_id: doctorId }).catch(() => null);
        const canonicalDocId = existingDoc?.id || doctorId;

        await ClinicDoctor.remove(clinicId, canonicalDocId).catch(() => false);

        // Only clear clinic association (clinic_id: null) — never delete the user or dentist record
        const updated = await Dentist.findByIdAndUpdate(canonicalDocId, {
            clinic_id: null
        });

        res.json({
            success: true,
            message: 'Doctor association removed from clinic. Doctor account and patient records preserved.',
            doctor: updated ? formatDentistRecord(updated) : null
        });
    } catch (err) {
        console.error('Remove Doctor From Clinic Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to remove doctor association from clinic.' });
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

exports._resolveDoctorFullName = resolveDoctorFullName;
exports._formatDentistRecord = formatDentistRecord;

