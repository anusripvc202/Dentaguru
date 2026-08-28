const { Referral, User, Appointment, Dentist, Clinic, PatientProblemRequest } = require('../models/Schemas');

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
 * 1. GET MY REFERRALS (Patient View)
 * Returns stats and list of referred friends for logged-in patient
 */
exports.getMyReferrals = async (req, res) => {
    try {
        const userId = getUserIdFromReq(req);
        if (!userId) {
            return res.status(400).json({
                success: false,
                message: 'User ID is required to fetch referral metrics.'
            });
        }

        // 1. Fetch user to get their referral code
        const user = await User.findById(userId);
        const referralCode = user?.referral_code || (user?.device_token && user.device_token.startsWith('{') ? JSON.parse(user.device_token).referral_code : null) || `DG-${(user?.name || 'USER').substring(0, 3).toUpperCase()}${user?.phone ? user.phone.slice(-4) : '2026'}`;

        // 2. Fetch referrals made by this user
        const rawReferrals = await Referral.find({ referrer_id: userId });

        // 3. Populate referred user info and consultation statuses
        const populatedReferrals = [];
        for (const ref of rawReferrals) {
            const referredUser = await User.findById(ref.referred_user_id);
            
            // Check if referred user has an appointment or consultation
            let appointmentInfo = null;
            if (ref.appointment_id) {
                appointmentInfo = await Appointment.findById(ref.appointment_id);
            } else {
                const appts = await Appointment.find({ patientId: ref.referred_user_id });
                if (appts && appts.length > 0) appointmentInfo = appts[0];
            }

            let status = ref.status || 'REGISTERED';
            if (appointmentInfo) {
                if (appointmentInfo.status === 'COMPLETED' || appointmentInfo.status === 'Completed') {
                    status = 'CONSULTATION_COMPLETED';
                } else {
                    status = 'CONSULTATION_BOOKED';
                }
            }

            // Doctor details if any
            let doctorName = null;
            let clinicName = null;
            if (appointmentInfo && appointmentInfo.dentist_id) {
                const doc = await Dentist.findById(appointmentInfo.dentist_id);
                if (doc) {
                    doctorName = doc.name;
                    if (doc.clinic_id) {
                        const cl = await Clinic.findById(doc.clinic_id);
                        clinicName = cl?.clinic_name;
                    }
                }
            }

            populatedReferrals.push({
                id: ref.id,
                referrerId: ref.referrer_id,
                referredUserId: ref.referred_user_id,
                referredUserName: referredUser ? referredUser.name : 'Registered Friend',
                referredUserPhone: referredUser ? (referredUser.phone ? `${referredUser.phone.slice(0, 3)}••••${referredUser.phone.slice(-3)}` : 'Verified Mobile') : 'Verified',
                referralCode: ref.referral_code || referralCode,
                status: status,
                assignedDoctorName: doctorName,
                assignedClinicName: clinicName,
                createdAt: ref.created_at || new Date().toISOString()
            });
        }

        // Calculate summary metrics
        const totalReferred = populatedReferrals.length;
        const registered = populatedReferrals.filter(r => r.status === 'REGISTERED').length;
        const consultationBooked = populatedReferrals.filter(r => r.status === 'CONSULTATION_BOOKED').length;
        const consultationsCompleted = populatedReferrals.filter(r => r.status === 'CONSULTATION_COMPLETED').length;

        return res.status(200).json({
            success: true,
            referralCode,
            stats: {
                totalReferred,
                registered,
                consultationBooked,
                consultationsCompleted
            },
            referrals: populatedReferrals
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
 * 2. GET ALL REFERRALS (Admin Management Table)
 */
exports.getAllReferralsAdmin = async (req, res) => {
    try {
        const rawReferrals = await Referral.find();
        const populatedList = [];

        for (const ref of rawReferrals) {
            const referrer = await User.findById(ref.referrer_id);
            const referred = await User.findById(ref.referred_user_id);

            let appt = null;
            if (ref.appointment_id) {
                appt = await Appointment.findById(ref.appointment_id);
            } else if (ref.referred_user_id) {
                const appts = await Appointment.find({ patientId: ref.referred_user_id });
                if (appts && appts.length > 0) appt = appts[0];
            }

            let status = ref.status || 'REGISTERED';
            if (appt) {
                if (appt.status === 'COMPLETED' || appt.status === 'Completed') {
                    status = 'CONSULTATION_COMPLETED';
                } else {
                    status = 'CONSULTATION_BOOKED';
                }
            }

            let doctorName = null;
            let clinicName = null;
            if (appt && appt.dentist_id) {
                const doc = await Dentist.findById(appt.dentist_id);
                if (doc) {
                    doctorName = doc.name;
                    if (doc.clinic_id) {
                        const cl = await Clinic.findById(doc.clinic_id);
                        clinicName = cl?.clinic_name;
                    }
                }
            }

            populatedList.push({
                id: ref.id,
                referrerId: ref.referrer_id,
                referrerName: referrer ? referrer.name : 'Unknown Patient',
                referrerPhone: referrer ? referrer.phone : '',
                referrerEmail: referrer ? referrer.email : '',
                referredUserId: ref.referred_user_id,
                referredUserName: referred ? referred.name : 'New Patient',
                referredUserPhone: referred ? referred.phone : '',
                referredUserEmail: referred ? referred.email : '',
                referralCode: ref.referral_code,
                status: status,
                registrationStatus: 'Verified Account',
                consultationStatus: status === 'CONSULTATION_COMPLETED' ? 'Completed' : (status === 'CONSULTATION_BOOKED' ? 'Scheduled' : 'Pending Booking'),
                assignedDoctorName: doctorName,
                assignedClinicName: clinicName,
                createdAt: ref.created_at || new Date().toISOString()
            });
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
 * 3. GET ADMIN REFERRAL GROWTH ANALYTICS
 */
exports.getAdminReferralAnalytics = async (req, res) => {
    try {
        const rawReferrals = await Referral.find();
        
        let totalReferrals = rawReferrals.length;
        let totalRegistered = 0;
        let totalConsultations = 0;
        const referrerMap = {};

        for (const ref of rawReferrals) {
            totalRegistered += 1; // each row in referrals is an attributed registered patient

            // Check consultation status
            let isConsultation = (ref.status === 'CONSULTATION_COMPLETED' || ref.status === 'CONSULTATION_BOOKED');
            if (!isConsultation && ref.referred_user_id) {
                const appts = await Appointment.find({ patientId: ref.referred_user_id });
                if (appts && appts.length > 0) isConsultation = true;
            }

            if (isConsultation) {
                totalConsultations += 1;
            }

            const refId = ref.referrer_id;
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

        // Conversion rates
        const conversionRateRegistration = totalReferrals > 0 ? ((totalRegistered / totalReferrals) * 100).toFixed(1) : '100.0';
        const conversionRateConsultation = totalRegistered > 0 ? ((totalConsultations / totalRegistered) * 100).toFixed(1) : '0.0';

        // Build top referring leaderboard
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
