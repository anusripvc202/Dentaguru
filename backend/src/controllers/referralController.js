const { Referral, User, Appointment, Dentist, Clinic, Notification } = require('../models/Schemas');
const { sendPushNotification } = require('../services/notificationService');
const {
    sendNewReferralWhatsApp,
    sendReferralAcceptedWhatsApp,
    sendReferralRejectedWhatsApp
} = require('../services/whatsappService');

/**
 * Helper to extract user ID from authenticated request
 */
const getUserIdFromReq = (req) => {
    if (req.user && req.user.id) return req.user.id;
    if (req.query && req.query.userId) return req.query.userId;
    if (req.headers && req.headers['x-user-id']) return req.headers['x-user-id'];
    return null;
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

    const docName = doctor?.users?.name || doctor?.name || 'Attending Specialist';
    const formattedDoctorName = docName.startsWith('Dr.') ? docName : `Dr. ${docName}`;
    const docSpecialty = doctor?.speciality || doctor?.specialty || ref.required_specialist || 'Specialist Consultation';
    const clinicName = clinic?.clinic_name || doctor?.clinics?.clinic_name || doctor?.clinic_name || 'DentaGuru Partner Clinic';

    return {
        id: ref.id,
        referralId: ref.id,
        referrerPatientId: referrerId,
        referrerPatientName: referrer?.name || 'Patient Referrer',
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
        doctorName: formattedDoctorName,
        doctorSpecialty: docSpecialty,
        doctorClinicName: clinicName,
        doctorCity: doctor?.city || clinic?.location || '',
        doctorPincode: doctor?.pincode || '',
        doctorLocation: doctor?.clinics?.location || doctor?.location || clinic?.location || '',
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
        const loggedInUserId = getUserIdFromReq(req) || req.body.referrerPatientId || req.body.referrerId;
        if (!loggedInUserId) {
            return res.status(401).json({
                success: false,
                message: 'Authentication required: Logged-in patient must be the referrer.'
            });
        }

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
            doctorId
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

        // 2. Existing Patient Check (Section 5)
        let linkedPatientId = null;
        const existingPatientUser = await User.findOne({ phone: cleanMobile });
        if (existingPatientUser && existingPatientUser.id) {
            linkedPatientId = existingPatientUser.id;
        }

        // 3. Fetch Referrer & Doctor Details
        const referrerUser = await User.findById(loggedInUserId);
        const referrerName = referrerUser?.name || 'Patient';
        
        let doctor = await Dentist.findById(doctorId);
        if (!doctor) doctor = await Dentist.findOne({ user_id: doctorId });
        
        let clinic = null;
        if (doctor?.clinic_id) {
            clinic = await Clinic.findById(doctor.clinic_id);
        }
        const doctorName = doctor?.users?.name || doctor?.name || 'Specialist';
        const formattedDoctorName = doctorName.startsWith('Dr.') ? doctorName : `Dr. ${doctorName}`;
        const doctorClinic = clinic?.clinic_name || doctor?.clinic_name || 'DentaGuru Dental Clinic';
        const doctorSpecialty = doctor?.speciality || doctor?.specialty || requiredSpecialist;

        // 4. Create Referral Record
        const newReferralRecord = await Referral.create({
            referrer_patient_id: loggedInUserId,
            referred_patient_id: linkedPatientId,
            referred_patient_name: referredPatientName.trim(),
            referred_patient_mobile: cleanMobile,
            referred_patient_age: String(referredPatientAge).trim(),
            referred_patient_gender: referredPatientGender.trim(),
            referred_patient_city: referredPatientCity.trim(),
            referred_patient_pincode: referredPatientPincode.trim(),
            referred_patient_location: referredPatientLocation.trim(),
            required_specialist: requiredSpecialist.trim(),
            clinical_complaint: clinicalComplaint.trim(),
            doctor_id: doctorId,
            status: 'Pending',
            whatsapp_status: 'Pending',
            referral_date: new Date().toISOString()
        });

        // 5. Create In-App Notification for Doctor (Section 9)
        const doctorRecipientId = doctor?.user_id || doctor?.id || doctorId;
        await Notification.create({
            recipient_role: 'Dentist',
            recipient_id: doctorRecipientId,
            referral_id: newReferralRecord.id,
            type: 'NEW_REFERRAL',
            title: 'New Patient Referral',
            message: `${referrerName} has referred ${referredPatientName} to you.`
        });

        // Send Push Notification to Doctor if Device Token present
        if (doctor?.users?.device_token && typeof doctor.users.device_token === 'string' && !doctor.users.device_token.startsWith('{')) {
            sendPushNotification(
                doctor.users.device_token,
                'New Patient Referral',
                `${referrerName} referred a patient to you.`
            ).catch(() => {});
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
            whatsappNotification: waResult
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
        const userId = getUserIdFromReq(req);
        if (!userId) {
            return res.status(400).json({
                success: false,
                message: 'User ID is required to fetch referrals.'
            });
        }

        const user = await User.findById(userId);
        const referralCode = user?.referral_code || `DG-${(user?.name || 'USER').substring(0, 3).toUpperCase()}${user?.phone ? user.phone.slice(-4) : '2026'}`;

        // Fetch patient referrals created by this patient
        const rawReferrals = await Referral.find({ referrer_patient_id: userId });
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
 * Isolated view: doctor only sees referrals assigned to them (Section 10 & 21)
 */
exports.getDoctorReferrals = async (req, res) => {
    try {
        const doctorUserId = getUserIdFromReq(req) || req.query.doctorId;
        if (!doctorUserId) {
            return res.status(400).json({
                success: false,
                message: 'Doctor ID is required.'
            });
        }

        // Resolve doctor table ID
        let doctor = await Dentist.findById(doctorUserId);
        if (!doctor) {
            doctor = await Dentist.findOne({ user_id: doctorUserId });
        }

        const docIds = [doctorUserId];
        if (doctor?.id) docIds.push(doctor.id);
        if (doctor?.user_id) docIds.push(doctor.user_id);

        const allReferrals = await Referral.find();
        const doctorReferrals = allReferrals.filter(r => {
            const assigned = r.doctor_id || r.assigned_doctor_id;
            return docIds.includes(assigned);
        });

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
        const matching = allReferrals.filter(r => {
            if (userId && (r.referred_patient_id === userId || r.referred_user_id === userId)) return true;
            if (phone && r.referred_patient_mobile && r.referred_patient_mobile.includes(phone.replace(/[^0-9]/g, '').slice(-10))) return true;
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
 * 5. GET SINGLE REFERRAL (Section 11)
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
 * 6. ACCEPT REFERRAL (Doctor Accepts Referral - Section 12 & 15)
 */
exports.acceptReferral = async (req, res) => {
    try {
        const { referralId } = req.params;
        const { confirmedTimeSlot } = req.body;

        const ref = await Referral.findById(referralId);
        if (!ref) {
            return res.status(404).json({ success: false, message: 'Referral not found.' });
        }

        // 1. Update status to Accepted
        const updated = await Referral.findByIdAndUpdate(referralId, {
            status: 'Accepted',
            rejection_reason: null
        });

        const populated = await populateReferralData(updated);

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
        let waResult = { success: false };
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
 * 7. REJECT REFERRAL (Doctor Rejects Referral - Section 13 & 16)
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

        // 1. Update status to Rejected with reason
        const updated = await Referral.findByIdAndUpdate(referralId, {
            status: 'Rejected',
            rejection_reason: finalReason
        });

        const populated = await populateReferralData(updated);

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
        let waResult = { success: false };
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
            message: 'Patient does not currently have a registered DentaGuru account.'
        });
    } catch (err) {
        return res.status(500).json({ success: false, message: err.message });
    }
};

/**
 * 9. NOTIFY WHATSAPP MANUAL TRIGGER (Section 25)
 */
exports.notifyWhatsApp = async (req, res) => {
    try {
        const { referralId } = req.params;
        const ref = await Referral.findById(referralId);
        if (!ref) return res.status(404).json({ success: false, message: 'Referral not found' });

        const populated = await populateReferralData(ref);
        const waResult = await sendNewReferralWhatsApp({
            referredPatientName: populated.referredPatientName,
            referredPatientMobile: populated.referredPatientMobile,
            doctorName: populated.doctorName,
            doctorSpecialty: populated.doctorSpecialty,
            doctorClinic: populated.doctorClinicName,
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
 * 10. GET ALL REFERRALS (Admin Management Table)
 */
exports.getAllReferralsAdmin = async (req, res) => {
    try {
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
 * 11. GET ADMIN REFERRAL GROWTH ANALYTICS
 */
exports.getAdminReferralAnalytics = async (req, res) => {
    try {
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
