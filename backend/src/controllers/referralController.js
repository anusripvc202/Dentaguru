const { Referral, User, Appointment, Dentist, Clinic, Notification, PatientProblemRequest, isDoctorRecordAvailable } = require('../models/Schemas');
const { isCloudEnv } = require('../config/secrets');
const { sendPushNotification } = require('../services/notificationService');
const {
    sendNewReferralWhatsApp,
    sendReferralAcceptedWhatsApp,
    sendReferralRejectedWhatsApp,
    sendDoctorReferralAlert,
    sendClinicReferralAlert,
    isWhatsAppProviderConfigured
} = require('../services/whatsappService');
const { resolveClinicRecordAndDoctorIds } = require('./clinicController');

/**
 * Helper to extract user ID from authenticated request
 */
const getUserIdFromReq = (req) => {
    if (req.user && req.user.id) return req.user.id;
    if (req.headers && req.headers['x-user-id']) return req.headers['x-user-id'];
    if (req.query && req.query.userId) return req.query.userId;
    return null;
};

const isAdminRoleString = (role) => {
    const r = String(role || '').trim().toLowerCase();
    return r === 'admin' || r === 'sub-admin' || r === 'subadmin' || r === 'sub_admin' || r === 'primaryadmin' || r === 'superadmin' || r === 'super_admin';
};

const isDoctorRoleString = (role) => {
    const r = String(role || '').trim().toLowerCase();
    return r === 'dentist' || r === 'doctor';
};

const isClinicRoleString = (role) => {
    const r = String(role || '').trim().toLowerCase();
    return r === 'clinic' || r === 'clinic_admin';
};

/**
 * Resolve authenticated caller identity (prefer verified req.user; fall back to x-user-id header only if req.user is absent).
 */
const resolveCallerIdentity = async (req) => {
    if (req.user && req.user.id) {
        return {
            id: String(req.user.id).trim(),
            role: String(req.user.role || '').trim(),
            fromJwt: true
        };
    }
    if (isCloudEnv()) {
        return null;
    }
    const headerUserId = (req.headers && req.headers['x-user-id']) ? String(req.headers['x-user-id']).trim() : '';
    if (!headerUserId) return null;

    const user = await User.findById(headerUserId).catch(() => null);
    if (user && user.id) {
        return {
            id: String(user.id).trim(),
            role: String(user.role || '').trim(),
            fromJwt: false
        };
    }
    const doc = await Dentist.findById(headerUserId).catch(() => null)
        || await Dentist.findOne({ user_id: headerUserId }).catch(() => null);
    if (doc) {
        const linkedUser = doc.user_id ? await User.findById(doc.user_id).catch(() => null) : null;
        return {
            id: String(doc.user_id || doc.id || headerUserId).trim(),
            role: String(linkedUser?.role || 'DOCTOR').trim(),
            fromJwt: false
        };
    }
    const clinic = await Clinic.findById(headerUserId).catch(() => null)
        || await Clinic.findOne({ user_id: headerUserId }).catch(() => null);
    if (clinic) {
        return {
            id: String(clinic.user_id || clinic.id || headerUserId).trim(),
            role: 'Clinic',
            fromJwt: false
        };
    }
    return { id: headerUserId, role: '', fromJwt: false };
};

/**
 * Resolve strict IDs (dentists.id & dentists.user_id ONLY) for a single doctor — never clinic or other doctors.
 */
const resolveStrictDoctorIds = async (doctorOrUserId) => {
    const id = String(doctorOrUserId || '').trim();
    const allIds = new Set();
    if (!id) return { dentistId: null, userId: null, allIds };
    allIds.add(id);

    let doc = await Dentist.findById(id).catch(() => null);
    if (!doc) {
        doc = await Dentist.findOne({ user_id: id }).catch(() => null);
    }
    if (doc?.id) allIds.add(String(doc.id).trim());
    if (doc?.user_id) allIds.add(String(doc.user_id).trim());

    return {
        dentistId: doc?.id ? String(doc.id).trim() : null,
        userId: doc?.user_id ? String(doc.user_id).trim() : null,
        allIds
    };
};

const isReferralAssignedToDoctor = (ref, doctorIdSet) => {
    if (!ref || !doctorIdSet || doctorIdSet.size === 0) return false;
    const primary = ref.doctor_id ? String(ref.doctor_id).trim() : '';
    const assigned = ref.assigned_doctor_id ? String(ref.assigned_doctor_id).trim() : '';
    return (primary && doctorIdSet.has(primary)) || (assigned && doctorIdSet.has(assigned));
};

/**
 * Enforce backend RBAC & ownership before reading or mutating a referral record.
 * @returns {Promise<{ ok: true, caller: { id: string, role: string, fromJwt: boolean }, status?: number, message?: string } | { ok: false, status: number, message: string, caller?: any }>}
 */
const authorizeReferralAccess = async (req, ref, { forStatusMutation = false } = {}) => {
    const caller = await resolveCallerIdentity(req);
    if (!caller || !caller.id) {
        return { ok: false, status: 401, message: 'Authentication required to access referral records.' };
    }

    if (isAdminRoleString(caller.role)) {
        return { ok: true, caller };
    }

    if (isDoctorRoleString(caller.role)) {
        const { allIds } = await resolveStrictDoctorIds(caller.id);
        if (isReferralAssignedToDoctor(ref, allIds)) {
            return { ok: true, caller };
        }
        if (!forStatusMutation) {
            const refCreatorIds = [ref.referrer_patient_id, ref.referrer_id].filter(Boolean).map(v => String(v).trim());
            if (refCreatorIds.some(cid => allIds.has(cid))) {
                return { ok: true, caller };
            }
        }
        return {
            ok: false,
            status: 403,
            message: 'Access Denied: You are not authorized to access or update another doctor\'s patient referral.'
        };
    }

    if (isClinicRoleString(caller.role)) {
        const resolvedClinic = await resolveClinicRecordAndDoctorIds(caller.id);
        const clinicDocIds = new Set((resolvedClinic?.doctorIds || []).map(String));
        const refClinicId = ref.clinic_id ? String(ref.clinic_id).trim() : '';
        const refDocId = String(ref.doctor_id || ref.assigned_doctor_id || '').trim();
        const belongsToClinic = Boolean(resolvedClinic?.clinicId) && (
            (refClinicId && refClinicId === String(resolvedClinic.clinicId)) ||
            (refDocId && clinicDocIds.has(refDocId))
        );
        if (belongsToClinic) {
            return { ok: true, caller };
        }
        return {
            ok: false,
            status: 403,
            message: 'Access Denied: This referral belongs to another clinic.'
        };
    }

    if (forStatusMutation) {
        return {
            ok: false,
            status: 403,
            message: 'Access Denied: Only the intended specialist doctor or authorized clinic can update referral status.'
        };
    }

    const participantIds = [
        ref.referrer_patient_id,
        ref.referrer_id,
        ref.referred_patient_id,
        ref.referred_user_id
    ].filter(Boolean).map(v => String(v).trim());
    if (participantIds.includes(caller.id)) {
        return { ok: true, caller };
    }

    return {
        ok: false,
        status: 403,
        message: 'Access Denied: You are not authorized to view this referral.'
    };
};

/**
 * Helper to populate rich referral object with referrer, doctor, clinic, and patient info
 */
const populateReferralData = async (ref) => {
    if (!ref) return null;

    const referrerId = ref.referrer_patient_id || ref.referrer_id;
    const referredId = ref.referred_patient_id || ref.referred_user_id;
    const doctorId = ref.doctor_id || ref.assigned_doctor_id;

    // 1. Fetch Referrer User
    let referrer = null;
    if (referrerId) {
        referrer = await User.findById(referrerId);
    }

    // 2. Fetch Doctor & Clinic Info
    let doctor = null;
    let clinic = null;
    if (doctorId) {
        doctor = await Dentist.findById(doctorId);
        if (!doctor) {
            doctor = await Dentist.findOne({ user_id: doctorId });
        }
        if (!doctor) {
            const userDoc = await User.findById(doctorId);
            if (userDoc) {
                doctor = {
                    id: userDoc.id,
                    user_id: userDoc.id,
                    clinic_id: null,
                    name: userDoc.name,
                    phone: userDoc.phone,
                    city: userDoc.city,
                    pincode: userDoc.pincode,
                    specialty: userDoc.specialty,
                    speciality: userDoc.specialty,
                    clinic_name: userDoc.clinic_name,
                    clinics: null,
                    clinic_address: '',
                    location: '',
                    languages: userDoc.languages || ['English'],
                    users: userDoc
                };
            }
        }
        if (doctor && doctor.clinic_id) {
            clinic = await Clinic.findById(doctor.clinic_id);
        }
    }

    // 3. Fetch Existing Referred User if linked
    let referredUser = null;
    if (referredId) {
        referredUser = await User.findById(referredId);
    } else if (ref.referred_patient_mobile) {
        referredUser = await User.findOne({ phone: ref.referred_patient_mobile });
    }

    let rawDocName = ref.doctor_name || ref.doctorName || doctor?.users?.name || doctor?.name || 'Attending Doctor';
    while (rawDocName.toLowerCase().startsWith('dr. dr.') || rawDocName.toLowerCase().startsWith('dr. dr ') || rawDocName.toLowerCase().startsWith('dr dr ')) {
        rawDocName = rawDocName.substring(3).trim();
        if (rawDocName.startsWith('.')) rawDocName = rawDocName.substring(1).trim();
    }
    const formattedDoctorName = (rawDocName.toLowerCase().startsWith('dr.') || rawDocName.toLowerCase().startsWith('dr '))
        ? rawDocName
        : `Dr. ${rawDocName}`;
    const docSpecialty = doctor?.speciality || doctor?.specialty || ref.required_specialist || 'Specialist Consultation';
    const clinicName = ref.doctor_clinic_name || ref.doctorClinicName || clinic?.clinic_name || doctor?.clinics?.clinic_name || doctor?.clinic_name || 'GS HEALTH Partner Clinic';

    let referrerName = referrer?.name || 'Patient Referrer';
    if (referrer && isDoctorRoleString(referrer.role)) {
        if (!referrerName.startsWith('Dr.') && !referrerName.startsWith('Dr ')) {
            referrerName = `Dr. ${referrerName}`;
        }
    }

    return {
        id: ref.id,
        referralId: ref.id,
        referrerPatientId: referrerId,
        referrerPatientName: referrerName,
        referrerPatientPhone: referrer?.phone || '',
        referrerPatientEmail: referrer?.email || '',

        referredPatientId: referredId || referredUser?.id || null,
        referredPatientName: ref.referred_patient_name || referredUser?.name || 'Referred Patient',
        referredPatientMobile: ref.referred_patient_mobile || referredUser?.phone || '',
        referredPatientAge: ref.referred_patient_age || '',
        referredPatientGender: ref.referred_patient_gender || '',
        referredPatientCity: ref.referred_patient_city || '',
        referredPatientPincode: ref.referred_patient_pincode || '',
        referredPatientLocation: ref.referred_patient_location || '',

        requiredSpecialist: ref.required_specialist || docSpecialty,
        clinicalComplaint: ref.clinical_complaint || '',

        doctorId: doctorId,
        clinicId: ref.clinic_id || doctor?.clinic_id || clinic?.id || null,
        doctorName: formattedDoctorName,
        doctorSpecialty: docSpecialty,
        doctorClinicName: clinicName,
        doctorCity: ref.doctor_city || ref.doctorCity || doctor?.city || clinic?.location || '',
        doctorPincode: ref.doctor_pincode || ref.doctorPincode || doctor?.pincode || '',
        doctorLocation: ref.doctor_location || ref.doctorLocation || doctor?.clinic_address || doctor?.clinics?.location || doctor?.location || clinic?.location || '',
        doctorPhone: ref.doctor_phone || ref.doctorPhone || doctor?.users?.phone || doctor?.phone || '',
        doctorLanguages: doctor?.languages || ['English'],

        status: ref.status || 'Pending',
        referralStatus: ref.status || 'Pending',
        rejectionReason: ref.rejection_reason || null,
        whatsappStatus: ref.whatsapp_status || 'Pending',
        referralDate: ref.referral_date || ref.created_at || new Date().toISOString(),
        createdAt: ref.created_at || new Date().toISOString(),
        updatedAt: ref.updated_at || new Date().toISOString(),

        // Backward compatibility
        referrerId: referrerId,
        referredUserId: referredId,
        referralCode: ref.referral_code || ''
    };
};

/**
 * 1. CREATE REFERRAL (Patient Refers Another Patient to Doctor)
 * Flow: Patient A (Referrer) -> Patient B (Referred Patient) -> Doctor C (Receiving Doctor)
 */
exports.createReferral = async (req, res) => {
    try {
        const loggedInRawId = getUserIdFromReq(req) || req.body.referrerPatientId || req.body.referrerId || req.body.referrer_patient_id || req.body.referrer_id;
        if (!loggedInRawId) {
            return res.status(401).json({
                success: false,
                message: 'Authentication required: Logged-in user must be the referrer.'
            });
        }

        // Resolve canonical user ID if a dentist table ID was passed as referrer
        let loggedInUserId = loggedInRawId;
        try {
            const directUser = await User.findById(loggedInRawId);
            if (!directUser) {
                const asDentist = await Dentist.findById(loggedInRawId);
                if (asDentist?.user_id) {
                    loggedInUserId = asDentist.user_id;
                }
            }
        } catch (_) { }

        const {
            referredPatientName,
            referredPatientMobile,
            referredPatientAge,
            referredPatientGender,
            referredPatientCity,
            referredPatientPincode,
            referredPatientLocation,
            requiredSpecialist,
            clinicalComplaint,
            doctorId,
            doctorName: incomingDocName,
            doctorClinicName: incomingClinicName,
            doctorLocation: incomingLocation,
            doctorCity: incomingCity,
            doctorPincode: incomingPincode,
            doctorPhone: incomingPhone
        } = req.body;

        // Mandatory Field Validation
        if (!referredPatientName || !referredPatientName.trim()) {
            return res.status(400).json({ success: false, message: 'Patient Name is required.' });
        }
        if (!referredPatientMobile || !referredPatientMobile.trim()) {
            return res.status(400).json({ success: false, message: 'Mobile Number is required.' });
        }
        if (!referredPatientAge) {
            return res.status(400).json({ success: false, message: 'Age is required.' });
        }
        if (!referredPatientGender || !referredPatientGender.trim()) {
            return res.status(400).json({ success: false, message: 'Gender is required.' });
        }
        if (!referredPatientCity || !referredPatientCity.trim()) {
            return res.status(400).json({ success: false, message: 'City is required.' });
        }
        if (!referredPatientPincode || !referredPatientPincode.trim()) {
            return res.status(400).json({ success: false, message: 'Pincode is required.' });
        }
        if (!referredPatientLocation || !referredPatientLocation.trim()) {
            return res.status(400).json({ success: false, message: 'Location is required.' });
        }
        if (!requiredSpecialist || !requiredSpecialist.trim()) {
            return res.status(400).json({ success: false, message: 'Required Specialist / Category is required.' });
        }
        if (!clinicalComplaint || !clinicalComplaint.trim()) {
            return res.status(400).json({ success: false, message: 'Problem / Clinical Complaint is required.' });
        }
        if (!doctorId) {
            return res.status(400).json({ success: false, message: 'Selected Doctor is required.' });
        }

        // Enforce Doctor Availability ON/OFF strictly on backend before creating a new referral
        const targetReferralDoc = await Dentist.findById(doctorId).catch(() => null)
            || await Dentist.findOne({ user_id: doctorId }).catch(() => null);
        if (targetReferralDoc && !isDoctorRecordAvailable(targetReferralDoc)) {
            return res.status(409).json({
                success: false,
                unavailable: true,
                isAvailable: false,
                message: 'Selected doctor is currently unavailable for new referrals.'
            });
        }

        const cleanMobile = referredPatientMobile.trim();

        // 1. Duplicate Referral Prevention Check (Section 22)
        const existingPending = await Referral.checkDuplicate(loggedInUserId, cleanMobile, doctorId);
        if (existingPending) {
            return res.status(409).json({
                success: false,
                isDuplicate: true,
                message: `A pending referral for ${referredPatientName} to this doctor already exists.`,
                referral: await populateReferralData(existingPending)
            });
        }

        // 2. Existing Patient Check / Auto-Create Referred Patient in Database (Section 5)
        let linkedPatientId = null;
        const digitsOnly = cleanMobile.replace(/[^0-9]/g, '');
        const raw10 = digitsOnly.length >= 10 ? digitsOnly.slice(-10) : digitsOnly;
        const patientEmail = `user_${raw10}@dentaguru.internal`;

        let existingPatientUser = await User.findOne({ phone: cleanMobile });
        if (!existingPatientUser && raw10 !== cleanMobile) {
            existingPatientUser = await User.findOne({ phone: raw10 });
        }
        if (!existingPatientUser) {
            existingPatientUser = await User.findOne({ email: patientEmail });
        }

        if (existingPatientUser && existingPatientUser.id) {
            linkedPatientId = existingPatientUser.id;
        } else {
            // Automatically register and persist the referred patient into DB 'users' table!
            try {
                const newPatientUser = await User.create({
                    name: referredPatientName.trim(),
                    email: patientEmail,
                    password: `Referred_${raw10}_Secure!`,
                    phone: raw10,
                    role: 'Patient',
                    city: referredPatientCity.trim(),
                    pincode: referredPatientPincode.trim(),
                    state: referredPatientLocation.trim(),
                    age: String(referredPatientAge).trim(),
                    gender: referredPatientGender.trim(),
                    emergency_contact: cleanMobile,
                });
                if (newPatientUser && newPatientUser.id) {
                    linkedPatientId = newPatientUser.id;
                }
            } catch (err) {
                console.error('⚠️ Could not auto-create referred patient user in DB:', err.message);
            }
        }

        // 3. Fetch Referrer & Doctor Details
        const referrerUser = await User.findById(loggedInUserId);
        let referrerName = referrerUser?.name || 'Patient';
        if (referrerUser && isDoctorRoleString(referrerUser.role)) {
            if (!referrerName.startsWith('Dr.') && !referrerName.startsWith('Dr ')) {
                referrerName = `Dr. ${referrerName}`;
            }
        }

        let doctor = await Dentist.findById(doctorId);
        if (!doctor) doctor = await Dentist.findOne({ user_id: doctorId });
        if (!doctor) doctor = await Dentist.findOne({ id: doctorId });
        if (!doctor) {
            const userDoc = await User.findById(doctorId);
            if (userDoc) {
                doctor = {
                    id: userDoc.id,
                    user_id: userDoc.id,
                    clinic_id: null,
                    name: userDoc.name,
                    phone: userDoc.phone,
                    city: userDoc.city,
                    pincode: userDoc.pincode,
                    specialty: userDoc.specialty,
                    speciality: userDoc.specialty,
                    clinic_name: userDoc.clinic_name,
                    clinics: null,
                    clinic_address: userDoc.address || '',
                    location: '',
                    languages: userDoc.languages || ['English'],
                    users: userDoc
                };
            }
        }

        let clinic = null;
        if (doctor?.clinic_id) {
            clinic = await Clinic.findById(doctor.clinic_id).catch(() => null);
        }
        const candidateClinicName = (incomingClinicName || clinic?.clinic_name || doctor?.clinics?.clinic_name || doctor?.clinic_name || '').toString().trim();
        const candidateClinicLower = candidateClinicName.toLowerCase();
        if (!clinic && candidateClinicName &&
            candidateClinicLower !== 'gs health partner clinic' &&
            candidateClinicLower !== 'gs health practice' &&
            candidateClinicLower !== 'independent practice') {
            clinic = await Clinic.findOne({ clinic_name: candidateClinicName }).catch(() => null);
        }
        const resolvedClinicId = clinic?.id || doctor?.clinic_id || null;
        let doctorName = incomingDocName || doctor?.users?.name || doctor?.name || 'Specialist';
        if (incomingDocName && incomingDocName.trim() && incomingDocName !== 'Dr. Specialist' && incomingDocName !== 'Doctor') {
            doctorName = incomingDocName.trim();
        }
        while (doctorName.toLowerCase().startsWith('dr. dr.') || doctorName.toLowerCase().startsWith('dr. dr ') || doctorName.toLowerCase().startsWith('dr dr ')) {
            doctorName = doctorName.substring(3).trim();
            if (doctorName.startsWith('.')) doctorName = doctorName.substring(1).trim();
        }
        const formattedDoctorName = (doctorName.toLowerCase().startsWith('dr.') || doctorName.toLowerCase().startsWith('dr '))
            ? doctorName
            : `Dr. ${doctorName}`;
        const doctorClinic = candidateClinicName || 'GS HEALTH Partner Clinic';
        const doctorSpecialty = doctor?.speciality || doctor?.specialty || requiredSpecialist;
        const doctorLocation = incomingLocation || doctor?.clinic_address || doctor?.clinics?.location || clinic?.address || clinic?.location || '';
        const doctorCity = incomingCity || doctor?.city || clinic?.city || '';
        const doctorPincode = incomingPincode || doctor?.pincode || clinic?.pincode || '';
        const doctorPhone = incomingPhone || doctor?.users?.phone || doctor?.phone || '';

        // 4. Create Referral Record (store canonical dentist.id & clinic.id so FK, clinic & doctor queries match)
        const canonicalDoctorId = doctor?.id || doctorId;
        const referralTimestamp = new Date().toISOString();
        const newReferralRecord = await Referral.create({
            referrer_patient_id: loggedInUserId,
            referred_patient_id: linkedPatientId,
            referred_user_id: linkedPatientId,
            referrer_id: loggedInUserId,
            referred_patient_name: referredPatientName.trim(),
            referred_patient_mobile: cleanMobile,
            referred_patient_age: String(referredPatientAge).trim(),
            referred_patient_gender: referredPatientGender.trim(),
            referred_patient_city: referredPatientCity.trim(),
            referred_patient_pincode: referredPatientPincode.trim(),
            referred_patient_location: referredPatientLocation.trim(),
            required_specialist: requiredSpecialist.trim(),
            clinical_complaint: clinicalComplaint.trim(),
            doctor_id: canonicalDoctorId,
            assigned_doctor_id: canonicalDoctorId,
            clinic_id: resolvedClinicId,
            doctor_name: formattedDoctorName,
            doctor_clinic_name: doctorClinic,
            doctor_location: doctorLocation,
            doctor_city: doctorCity,
            doctor_pincode: doctorPincode,
            doctor_phone: doctorPhone,
            status: 'Pending',
            whatsapp_status: 'Pending',
            referral_date: referralTimestamp
        });

        // 5. Create In-App Notifications for Receiving Doctor, Associated Clinic, Referred Patient & Admin
        const doctorRecipientId = doctor?.user_id || doctor?.id || canonicalDoctorId;
        const refDateOnly = referralTimestamp.split('T')[0];
        const hasNamedClinic = Boolean(resolvedClinicId) &&
            doctorClinic.toLowerCase() !== 'gs health partner clinic' &&
            doctorClinic.toLowerCase() !== 'gs health practice';
        try {
            await Notification.create({
                recipient_role: 'Dentist',
                recipient_id: doctorRecipientId,
                referral_id: newReferralRecord.id,
                type: 'NEW_REFERRAL',
                title: 'New Patient Referral',
                message: `You have received a new patient referral for ${referredPatientName.trim()} (${doctorSpecialty})${hasNamedClinic ? ' at ' + doctorClinic : ''} on ${refDateOnly}. Status: Pending.`
            });
            if (resolvedClinicId) {
                await Notification.create({
                    recipient_role: 'Clinic',
                    recipient_id: resolvedClinicId,
                    referral_id: newReferralRecord.id,
                    type: 'clinic_new_referral',
                    title: 'New Patient Referral',
                    message: `A patient has referred ${formattedDoctorName}, ${doctorSpecialty} for ${referredPatientName.trim()} on ${refDateOnly}. Status: Pending.`
                });
            }
            if (linkedPatientId) {
                await Notification.create({
                    recipient_role: 'Patient',
                    recipient_id: linkedPatientId,
                    referral_id: newReferralRecord.id,
                    type: 'NEW_REFERRAL',
                    title: 'Specialist Referral Received',
                    message: `${referrerName} referred you to ${formattedDoctorName} (${doctorSpecialty}).`
                });
            }
            await Notification.create({
                recipient_role: 'Admin',
                recipient_id: 'ALL_ADMINS',
                referral_id: newReferralRecord.id,
                type: 'NEW_REFERRAL',
                title: 'New Patient Referral Submitted',
                message: `${referrerName} referred ${referredPatientName.trim()} to ${formattedDoctorName}.`
            });
        } catch (_) { }

        // Send Push & Registered Mobile Alerts to Concerned Doctor and Clinic (no simulated SMS/WhatsApp)
        if (doctor?.users?.device_token && typeof doctor.users.device_token === 'string' && !doctor.users.device_token.startsWith('{')) {
            sendPushNotification(
                doctor.users.device_token,
                'New Patient Referral',
                `${referredPatientName.trim()} referred for ${doctorSpecialty}.`
            ).catch(() => { });
        }
        let doctorMobileAlert = { success: false, providerConfigured: isWhatsAppProviderConfigured(), whatsappStatus: 'NotAttempted' };
        let clinicMobileAlert = { success: false, providerConfigured: isWhatsAppProviderConfigured(), whatsappStatus: 'NotAttempted' };
        if (doctorPhone) {
            doctorMobileAlert = await sendDoctorReferralAlert({
                doctorPhone,
                doctorName: formattedDoctorName,
                patientName: referredPatientName.trim(),
                specialty: doctorSpecialty,
                referralDate: refDateOnly,
                referralId: String(newReferralRecord.id)
            }).catch(() => doctorMobileAlert);
        }
        if (resolvedClinicId) {
            try {
                const clinicUser = clinic?.user_id ? await User.findById(clinic.user_id).catch(() => null) : null;
                const clinicPhone = clinic?.phone || clinicUser?.phone || '';
                if (clinicUser?.device_token && typeof clinicUser.device_token === 'string' && !clinicUser.device_token.startsWith('{')) {
                    sendPushNotification(
                        clinicUser.device_token,
                        'New Patient Referral',
                        `Patient ${referredPatientName.trim()} referred to ${formattedDoctorName} (${doctorSpecialty}).`
                    ).catch(() => { });
                }
                if (clinicPhone) {
                    clinicMobileAlert = await sendClinicReferralAlert({
                        clinicPhone,
                        clinicName: doctorClinic,
                        doctorName: formattedDoctorName,
                        specialty: doctorSpecialty,
                        patientName: referredPatientName.trim(),
                        referralDate: refDateOnly,
                        referralId: String(newReferralRecord.id)
                    }).catch(() => clinicMobileAlert);
                }
            } catch (_) { }
        }

        // 6. Send WhatsApp Notification to REFERRED PATIENT (Section 14 & 17)
        let waResult = { success: false, whatsappStatus: 'Pending' };
        try {
            waResult = await sendNewReferralWhatsApp({
                referredPatientName: referredPatientName.trim(),
                referredPatientMobile: cleanMobile,
                doctorName: formattedDoctorName,
                doctorSpecialty: doctorSpecialty,
                doctorClinic: doctorClinic,
                doctorAddress: doctorLocation,
                doctorCity: doctorCity,
                doctorPincode: doctorPincode,
                doctorPhone: doctorPhone,
                referrerName: referrerName,
                clinicalComplaint: clinicalComplaint.trim()
            });

            if (waResult && waResult.whatsappStatus) {
                await Referral.findByIdAndUpdate(newReferralRecord.id, {
                    whatsapp_status: waResult.whatsappStatus
                });
                newReferralRecord.whatsapp_status = waResult.whatsappStatus;
            }
        } catch (waErr) {
            console.error('⚠️ WhatsApp notification error (non-fatal):', waErr.message);
        }

        const populated = await populateReferralData(newReferralRecord);

        return res.status(201).json({
            success: true,
            message: 'Referral submitted successfully.',
            referral: populated,
            whatsappNotification: waResult,
            notificationStatus: {
                inAppDoctorNotified: true,
                inAppClinicNotified: Boolean(resolvedClinicId),
                externalSmsWhatsappConfigured: isWhatsAppProviderConfigured(),
                doctorMobileAlert,
                clinicMobileAlert
            }
        });
    } catch (err) {
        console.error('❌ Error creating referral:', err);
        return res.status(500).json({
            success: false,
            message: 'Failed to create patient referral: ' + err.message
        });
    }
};

/**
 * 2. GET MY CREATED REFERRALS (Referrer View)
 * Returns referrals created by the logged-in patient + organic stats
 */
exports.getMyReferrals = async (req, res) => {
    try {
        const rawUserId = getUserIdFromReq(req);
        if (!rawUserId) {
            return res.status(400).json({
                success: false,
                message: 'User ID is required to fetch referrals.'
            });
        }

        let user = await User.findById(rawUserId);
        let userId = rawUserId;
        if (!user) {
            const doc = await Dentist.findById(rawUserId);
            if (doc?.user_id) {
                userId = doc.user_id;
                user = await User.findById(userId);
            }
        }
        const referralCode = user?.referral_code || `DG-${(user?.name || 'USER').substring(0, 3).toUpperCase()}${user?.phone ? user.phone.slice(-4) : '2026'}`;

        // Fetch patient/doctor referrals created by this user
        const allReferrals = await Referral.find();
        const rawReferrals = allReferrals.filter(r =>
            r.referrer_patient_id === userId ||
            r.referrer_id === userId ||
            r.referrer_patient_id === rawUserId ||
            r.referrer_id === rawUserId
        );
        const populatedList = [];

        for (const ref of rawReferrals) {
            const item = await populateReferralData(ref);
            if (item) populatedList.push(item);
        }

        const totalReferred = populatedList.length;
        const pending = populatedList.filter(r => r.status === 'Pending').length;
        const accepted = populatedList.filter(r => r.status === 'Accepted').length;
        const rejected = populatedList.filter(r => r.status === 'Rejected').length;

        return res.status(200).json({
            success: true,
            referralCode,
            stats: {
                totalReferred,
                registered: accepted + pending,
                consultationBooked: accepted,
                consultationsCompleted: 0,
                pending,
                accepted,
                rejected
            },
            referrals: populatedList
        });
    } catch (err) {
        console.error('❌ Error fetching patient referrals:', err);
        return res.status(500).json({
            success: false,
            message: 'Failed to retrieve referral data: ' + err.message
        });
    }
};

/**
 * 3. GET DOCTOR REFERRALS (Receiving Doctor View)
 * Strict Doctor Isolation: uses authenticated doctor identity ONLY.
 * Never returns another doctor's or clinic-wide referrals.
 */
exports.getDoctorReferrals = async (req, res) => {
    try {
        const caller = await resolveCallerIdentity(req);
        if (!caller || !caller.id) {
            return res.status(401).json({
                success: false,
                message: 'Authentication required to fetch doctor referrals.'
            });
        }

        const callerIsAdmin = isAdminRoleString(caller.role);
        const callerIsDoctor = !caller.role || isDoctorRoleString(caller.role);

        if (!callerIsAdmin && !callerIsDoctor) {
            return res.status(403).json({
                success: false,
                message: 'Access Denied: Only authorized doctors can access doctor referrals.'
            });
        }

        const requestedDoctorId = (req.query?.doctorId || req.query?.userId || '').toString().trim();

        let targetLookupId = caller.id;
        if (callerIsAdmin && requestedDoctorId) {
            targetLookupId = requestedDoctorId;
        }

        const { allIds: docIdSet } = await resolveStrictDoctorIds(targetLookupId);

        // Reject attempts by Doctor A to pass ?doctorId=<Doctor B>
        if (!callerIsAdmin && requestedDoctorId && !docIdSet.has(requestedDoctorId)) {
            return res.status(403).json({
                success: false,
                message: 'Access Denied: You are not authorized to view another doctor\'s patient referrals.'
            });
        }

        const idArray = Array.from(docIdSet);
        const scopedReferrals = await Referral.find({ doctor_id: { $in: idArray } });
        const doctorReferrals = (scopedReferrals || []).filter(r => isReferralAssignedToDoctor(r, docIdSet));

        const populated = [];
        for (const r of doctorReferrals) {
            const item = await populateReferralData(r);
            if (item) populated.push(item);
        }

        return res.status(200).json({
            success: true,
            count: populated.length,
            referrals: populated
        });
    } catch (err) {
        console.error('❌ Error fetching doctor referrals:', err);
        return res.status(500).json({
            success: false,
            message: 'Failed to fetch doctor referrals: ' + err.message
        });
    }
};

/**
 * 3b. GET CLINIC REFERRALS (Receiving Clinic View - Strict Multi-Clinic Isolation)
 */
exports.getClinicReferrals = async (req, res) => {
    try {
        const callerRoleLower = (req.user?.role || '').toString().trim().toLowerCase();
        const isCallerClinic = callerRoleLower === 'clinic' || callerRoleLower === 'clinic_admin';
        const rawClinicIdentifier = isCallerClinic
            ? req.user.id
            : (req.query.clinicId || req.query.clinicName || getUserIdFromReq(req));

        if (!rawClinicIdentifier) {
            return res.status(400).json({
                success: false,
                message: 'Clinic ID or Clinic Name is required to fetch clinic referrals.'
            });
        }

        const resolved = await resolveClinicRecordAndDoctorIds(rawClinicIdentifier);
        if (!resolved.clinicId) {
            return res.status(200).json({
                success: true,
                count: 0,
                clinicId: null,
                clinicName: resolved.clinicName || '',
                referrals: []
            });
        }

        const clinicDocIds = new Set(resolved.doctorIds);
        const targetClinicLower = resolved.clinicName.toLowerCase();
        const allReferrals = await Referral.find();

        const clinicReferrals = (allReferrals || []).filter(r => {
            if (r.clinic_id && String(r.clinic_id) === String(resolved.clinicId)) return true;
            const assignedDocId = String(r.doctor_id || r.assigned_doctor_id || '').trim();
            if (assignedDocId && clinicDocIds.has(assignedDocId)) return true;
            const docClinicId = String(r.doctor?.clinic_id || '').trim();
            if (docClinicId && docClinicId === String(resolved.clinicId)) return true;
            const refClinicName = (r.doctor_clinic_name || r.doctorClinicName || r.doctor?.clinics?.clinic_name || '').toString().trim().toLowerCase();
            if (targetClinicLower && refClinicName && refClinicName === targetClinicLower) return true;
            return false;
        });

        const populated = [];
        for (const r of clinicReferrals) {
            const item = await populateReferralData(r);
            if (item) populated.push(item);
        }

        return res.status(200).json({
            success: true,
            count: populated.length,
            clinicId: resolved.clinicId,
            clinicName: resolved.clinicName,
            referrals: populated
        });
    } catch (err) {
        console.error('❌ Error fetching clinic referrals:', err);
        return res.status(500).json({
            success: false,
            message: 'Failed to fetch clinic referrals: ' + err.message
        });
    }
};

/**
 * 4. GET REFERRALS FOR REFERRED PATIENT (Referred Patient View - Section 20)
 */
exports.getReferralsForReferredPatient = async (req, res) => {
    try {
        const userId = getUserIdFromReq(req);
        let phone = req.query.phone;

        if (userId) {
            const u = await User.findById(userId);
            if (u && u.phone) phone = u.phone;
        }

        const allReferrals = await Referral.find();
        const normalizedPhone10 = phone ? String(phone).replace(/[^0-9]/g, '').slice(-10) : '';
        const matching = allReferrals.filter(r => {
            if (userId && (r.referred_patient_id === userId || r.referred_user_id === userId)) return true;
            if (normalizedPhone10.length >= 10 && r.referred_patient_mobile) {
                const refDigits10 = String(r.referred_patient_mobile).replace(/[^0-9]/g, '').slice(-10);
                if (refDigits10 && refDigits10 === normalizedPhone10) return true;
            }
            return false;
        });

        const populated = [];
        for (const r of matching) {
            const item = await populateReferralData(r);
            if (item) populated.push(item);
        }

        return res.status(200).json({
            success: true,
            count: populated.length,
            referrals: populated
        });
    } catch (err) {
        console.error('❌ Error fetching referred patient referrals:', err);
        return res.status(500).json({
            success: false,
            message: 'Failed to retrieve referrals for patient: ' + err.message
        });
    }
};

/**
 * 5. GET SINGLE REFERRAL (Section 11 — Enforces Ownership/RBAC)
 */
exports.getReferralById = async (req, res) => {
    try {
        const { referralId } = req.params;
        const ref = await Referral.findById(referralId);
        if (!ref) {
            return res.status(404).json({
                success: false,
                message: 'Referral not found.'
            });
        }

        const auth = await authorizeReferralAccess(req, ref, { forStatusMutation: false });
        if (!auth.ok) {
            return res.status(auth.status || 403).json({
                success: false,
                message: auth.message
            });
        }

        const populated = await populateReferralData(ref);
        return res.status(200).json({
            success: true,
            referral: populated
        });
    } catch (err) {
        return res.status(500).json({
            success: false,
            message: 'Failed to retrieve referral details: ' + err.message
        });
    }
};

/**
 * 6. ACCEPT REFERRAL (Intended Doctor or Authorized Clinic Only - Section 12 & 15)
 */
exports.acceptReferral = async (req, res) => {
    try {
        const { referralId } = req.params;
        const { confirmedTimeSlot } = req.body;

        const ref = await Referral.findById(referralId);
        if (!ref) {
            return res.status(404).json({ success: false, message: 'Referral not found.' });
        }

        const auth = await authorizeReferralAccess(req, ref, { forStatusMutation: true });
        if (!auth.ok) {
            return res.status(auth.status || 403).json({ success: false, message: auth.message });
        }

        // 1. Update status to Accepted
        const updated = await Referral.findByIdAndUpdate(referralId, {
            status: 'Accepted',
            rejection_reason: null
        });

        // 1b. Ensure consultation appointment exists for this accepted referral
        const patientId = ref.referred_patient_id || ref.referred_user_id;
        const doctorId = ref.doctor_id || ref.assigned_doctor_id;
        let docClinicId = ref.clinic_id || null;
        if (!docClinicId && doctorId) {
            const docRec = await Dentist.findById(doctorId).catch(() => null);
            docClinicId = docRec?.clinic_id || null;
        }
        if (patientId && doctorId) {
            try {
                const appt = await Appointment.create({
                    patient_id: patientId,
                    dentist_id: doctorId,
                    clinic_id: docClinicId,
                    appointment_date: new Date().toISOString().split('T')[0],
                    time_slot: confirmedTimeSlot || '10:00 AM',
                    treatment: ref.required_specialist || 'Specialist Consultation',
                    status: 'CONFIRMED',
                    notes: `Referred Patient: ${ref.referred_patient_name} (${ref.referred_patient_mobile}). Clinical complaint: ${ref.clinical_complaint || ''}`
                });
                if (appt && appt.id) {
                    await Referral.findByIdAndUpdate(referralId, { appointment_id: appt.id });
                }
            } catch (apptErr) {
                console.warn('⚠️ Appointment auto-creation on referral accept notice:', apptErr.message);
            }
        }

        const populated = await populateReferralData(updated || ref);
        if (!populated) {
            return res.status(500).json({ success: false, message: 'Failed to populate accepted referral.' });
        }

        // 2. Notify Referrer Patient (Section 12)
        const referrerId = ref.referrer_patient_id || ref.referrer_id;
        if (referrerId) {
            await Notification.create({
                recipient_role: 'Patient',
                recipient_id: referrerId,
                referral_id: referralId,
                type: 'REFERRAL_ACCEPTED',
                title: 'Referral Accepted',
                message: `Your referral for ${populated.referredPatientName} has been accepted by ${populated.doctorName}.`
            });
        }

        // 3. Send WhatsApp Notification to REFERRED PATIENT (Section 15)
        let waResult = { success: false, whatsappStatus: 'Pending' };
        try {
            waResult = await sendReferralAcceptedWhatsApp({
                referredPatientName: populated.referredPatientName,
                referredPatientMobile: populated.referredPatientMobile,
                doctorName: populated.doctorName,
                doctorSpecialty: populated.doctorSpecialty,
                doctorClinic: populated.doctorClinicName,
                confirmedTimeSlot: confirmedTimeSlot || null
            });
        } catch (waErr) {
            console.error('⚠️ WhatsApp accept alert error (non-fatal):', waErr.message);
        }

        return res.status(200).json({
            success: true,
            message: `Referral for ${populated.referredPatientName} has been accepted.`,
            referral: populated,
            whatsappNotification: waResult
        });
    } catch (err) {
        console.error('❌ Error accepting referral:', err);
        return res.status(500).json({
            success: false,
            message: 'Failed to accept referral: ' + err.message
        });
    }
};

/**
 * 7. REJECT REFERRAL (Intended Doctor or Authorized Clinic Only - Section 13 & 16)
 */
exports.rejectReferral = async (req, res) => {
    try {
        const { referralId } = req.params;
        const { rejectionReason, reason } = req.body;
        const finalReason = rejectionReason || reason || 'Doctor is currently unavailable';

        const ref = await Referral.findById(referralId);
        if (!ref) {
            return res.status(404).json({ success: false, message: 'Referral not found.' });
        }

        const auth = await authorizeReferralAccess(req, ref, { forStatusMutation: true });
        if (!auth.ok) {
            return res.status(auth.status || 403).json({ success: false, message: auth.message });
        }

        // 1. Update status to Rejected with reason
        const updated = await Referral.findByIdAndUpdate(referralId, {
            status: 'Rejected',
            rejection_reason: finalReason
        });

        const populated = await populateReferralData(updated || ref);
        if (!populated) {
            return res.status(500).json({ success: false, message: 'Failed to populate rejected referral.' });
        }

        // 2. Notify Referrer Patient (Section 13)
        const referrerId = ref.referrer_patient_id || ref.referrer_id;
        if (referrerId) {
            await Notification.create({
                recipient_role: 'Patient',
                recipient_id: referrerId,
                referral_id: referralId,
                type: 'REFERRAL_REJECTED',
                title: 'Referral Update',
                message: `Your referral for ${populated.referredPatientName} was not accepted by ${populated.doctorName}.`
            });
        }

        // 3. Send WhatsApp Notification to REFERRED PATIENT (Section 16)
        let waResult = { success: false, whatsappStatus: 'Pending' };
        try {
            waResult = await sendReferralRejectedWhatsApp({
                referredPatientName: populated.referredPatientName,
                referredPatientMobile: populated.referredPatientMobile,
                doctorName: populated.doctorName,
                rejectionReason: finalReason
            });
        } catch (waErr) {
            console.error('⚠️ WhatsApp reject alert error (non-fatal):', waErr.message);
        }

        return res.status(200).json({
            success: true,
            message: `Referral for ${populated.referredPatientName} has been rejected.`,
            referral: populated,
            whatsappNotification: waResult
        });
    } catch (err) {
        console.error('❌ Error rejecting referral:', err);
        return res.status(500).json({
            success: false,
            message: 'Failed to reject referral: ' + err.message
        });
    }
};

/**
 * 8. CHECK PATIENT EXISTS BY MOBILE NUMBER (Section 5)
 */
exports.checkPatientExists = async (req, res) => {
    try {
        const phone = req.body.phone || req.body.mobile || req.query.phone || req.query.mobile;
        if (!phone) {
            return res.status(400).json({ success: false, message: 'Phone number is required.' });
        }

        const cleanDigits = String(phone).replace(/[^0-9]/g, '').slice(-10);
        const user = await User.findOne({ phone: cleanDigits });

        if (user && user.id) {
            return res.status(200).json({
                success: true,
                exists: true,
                patient: {
                    id: user.id,
                    name: user.name,
                    phone: user.phone,
                    email: user.email,
                    city: user.city,
                    pincode: user.pincode
                }
            });
        }

        return res.status(200).json({
            success: true,
            exists: false,
            message: 'Patient does not currently have a registered GS HEALTH account.'
        });
    } catch (err) {
        return res.status(500).json({ success: false, message: err.message });
    }
};

/**
 * 9. NOTIFY WHATSAPP MANUAL TRIGGER (Section 25 — Owner RBAC enforced)
 */
exports.notifyWhatsApp = async (req, res) => {
    try {
        const { referralId } = req.params;
        const ref = await Referral.findById(referralId);
        if (!ref) return res.status(404).json({ success: false, message: 'Referral not found' });

        const auth = await authorizeReferralAccess(req, ref, { forStatusMutation: false });
        if (!auth.ok) {
            return res.status(auth.status || 403).json({ success: false, message: auth.message });
        }

        const populated = await populateReferralData(ref);
        const waResult = await sendNewReferralWhatsApp({
            referredPatientName: populated.referredPatientName,
            referredPatientMobile: populated.referredPatientMobile,
            doctorName: populated.doctorName,
            doctorSpecialty: populated.doctorSpecialty,
            doctorClinic: populated.doctorClinicName,
            doctorAddress: populated.doctorLocation,
            doctorCity: populated.doctorCity,
            doctorPincode: populated.doctorPincode,
            doctorPhone: populated.doctorPhone,
            referrerName: populated.referrerPatientName,
            clinicalComplaint: populated.clinicalComplaint
        });

        await Referral.findByIdAndUpdate(referralId, {
            whatsapp_status: waResult.whatsappStatus || 'Sent'
        });

        return res.status(200).json({
            success: true,
            whatsappNotification: waResult
        });
    } catch (e) {
        return res.status(500).json({ success: false, message: e.message });
    }
};

/**
 * 10. GET ALL REFERRALS (Admin Management Table — Strictly Admin/Sub-Admin Only)
 */
exports.getAllReferralsAdmin = async (req, res) => {
    try {
        const caller = await resolveCallerIdentity(req);
        if (!caller || !caller.id) {
            return res.status(401).json({
                success: false,
                message: 'Authentication required for admin referrals.'
            });
        }
        if (!isAdminRoleString(caller.role)) {
            return res.status(403).json({
                success: false,
                message: 'Access Denied: Only Admins may retrieve platform-wide referrals.'
            });
        }

        const rawReferrals = await Referral.find();
        const populatedList = [];

        for (const ref of rawReferrals) {
            const item = await populateReferralData(ref);
            if (item) populatedList.push(item);
        }

        return res.status(200).json({
            success: true,
            count: populatedList.length,
            referrals: populatedList
        });
    } catch (err) {
        console.error('❌ Error fetching admin referrals:', err);
        return res.status(500).json({
            success: false,
            message: 'Failed to retrieve admin referrals list: ' + err.message
        });
    }
};

/**
 * 11. GET ADMIN REFERRAL GROWTH ANALYTICS (Strictly Admin/Sub-Admin Only)
 */
exports.getAdminReferralAnalytics = async (req, res) => {
    try {
        const caller = await resolveCallerIdentity(req);
        if (!caller || !caller.id) {
            return res.status(401).json({
                success: false,
                message: 'Authentication required for admin referral analytics.'
            });
        }
        if (!isAdminRoleString(caller.role)) {
            return res.status(403).json({
                success: false,
                message: 'Access Denied: Only Admins may view platform referral analytics.'
            });
        }

        const rawReferrals = await Referral.find();

        let totalReferrals = rawReferrals.length;
        let totalRegistered = 0;
        let totalConsultations = 0;
        const referrerMap = {};

        for (const ref of rawReferrals) {
            totalRegistered += 1;

            let isConsultation = (ref.status === 'Accepted' || ref.status === 'CONSULTATION_COMPLETED' || ref.status === 'CONSULTATION_BOOKED');
            if (isConsultation) {
                totalConsultations += 1;
            }

            const refId = ref.referrer_patient_id || ref.referrer_id;
            if (refId) {
                if (!referrerMap[refId]) {
                    referrerMap[refId] = {
                        referrerId: refId,
                        totalReferrals: 0,
                        completedConsultations: 0
                    };
                }
                referrerMap[refId].totalReferrals += 1;
                if (isConsultation) {
                    referrerMap[refId].completedConsultations += 1;
                }
            }
        }

        const conversionRateRegistration = totalReferrals > 0 ? ((totalRegistered / totalReferrals) * 100).toFixed(1) : '100.0';
        const conversionRateConsultation = totalRegistered > 0 ? ((totalConsultations / totalRegistered) * 100).toFixed(1) : '0.0';

        const topReferringPatients = [];
        for (const [refId, data] of Object.entries(referrerMap)) {
            const user = await User.findById(refId);
            topReferringPatients.push({
                referrerId: refId,
                name: user ? user.name : 'Active Patient',
                email: user ? user.email : '',
                phone: user ? user.phone : '',
                referralCode: user?.referral_code || `DG-${(user?.name || 'PAT').substring(0, 3).toUpperCase()}`,
                totalReferrals: data.totalReferrals,
                completedConsultations: data.completedConsultations
            });
        }

        topReferringPatients.sort((a, b) => b.totalReferrals - a.totalReferrals);

        return res.status(200).json({
            success: true,
            analytics: {
                totalReferrals,
                totalRegistered,
                totalConsultations,
                conversionRateRegistration: `${conversionRateRegistration}%`,
                conversionRateConsultation: `${conversionRateConsultation}%`,
                topReferringPatients: topReferringPatients.slice(0, 10)
            }
        });
    } catch (err) {
        console.error('❌ Error generating referral analytics:', err);
        return res.status(500).json({
            success: false,
            message: 'Failed to calculate growth analytics: ' + err.message
        });
    }
};

/**
 * 12. DELETE REFERRAL (Referrer / Patient / Admin deletes referral record)
 */
exports.deleteReferral = async (req, res) => {
    try {
        const { referralId } = req.params;
        if (!referralId) {
            return res.status(400).json({
                success: false,
                message: 'Referral ID is required.'
            });
        }

        const ref = await Referral.findById(referralId);
        if (ref) {
            const auth = await authorizeReferralAccess(req, ref, { forStatusMutation: false });
            if (!auth.ok) {
                return res.status(auth.status || 403).json({
                    success: false,
                    message: auth.message
                });
            }
            await Referral.findByIdAndDelete(referralId);
        } else {
            // Also attempt deletion on patient_problem_requests
            try {
                await PatientProblemRequest.findByIdAndDelete(referralId);
            } catch (_) { }
        }

        return res.status(200).json({
            success: true,
            message: 'Referral deleted successfully.'
        });
    } catch (err) {
        console.error('❌ Error deleting referral:', err);
        return res.status(500).json({
            success: false,
            message: 'Failed to delete referral: ' + err.message
        });
    }
};
