const { PatientProblemRequest, DentistSuggestion, Dentist, User, Notification } = require('../models/Schemas');
const { sendPushNotification } = require('../services/notificationService');

// 1. PATIENT: CREATE DENTAL PROBLEM REQUEST
exports.createProblemRequest = async (req, res) => {
    const { problemCategory, problemDescription, symptoms, preferredLocation, attachments } = req.body;
    try {
        const patientId = req.user ? req.user.id : req.body.patientId;
        const request = await PatientProblemRequest.create({
            patient_id: patientId,
            problem_category: problemCategory || 'General Dental Issue',
            problem_description: problemDescription || '',
            symptoms: symptoms || '',
            preferred_location: preferredLocation || null,
            attachments: attachments || [],
            status: 'PENDING_ADMIN_REVIEW'
        });

        // 🔔 Dispatch Notification to Admin
        await Notification.create({
            recipient_role: 'Admin',
            recipient_id: 'ALL',
            title: '🚨 New Dental Problem Request',
            message: `Patient submitted a new problem: ${problemCategory}`,
            type: 'problem_request'
        });

        res.status(201).json({
            success: true,
            message: 'Dental problem request submitted successfully. Awaiting admin review.',
            request
        });
    } catch (err) {
        console.error('Create Problem Request Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to submit problem request.' });
    }
};

// 2. PATIENT: GET MY PROBLEM REQUESTS
exports.getPatientProblemRequests = async (req, res) => {
    try {
        let query = {};
        const targetId = req.query.patientId || (req.user ? req.user.id : null);
        if (targetId) {
            const user = await User.findById(targetId);
            const possibleIds = [targetId];
            if (user && user.name) possibleIds.push(user.name);
            if (user && user.email) possibleIds.push(user.email);
            if (req.user && req.user.id && !possibleIds.includes(req.user.id)) possibleIds.push(req.user.id);
            query.patient_id = { $in: possibleIds };
        } else if (req.user) {
            const user = await User.findById(req.user.id);
            const possibleIds = [req.user.id];
            if (user && user.name) possibleIds.push(user.name);
            if (user && user.email) possibleIds.push(user.email);
            query.patient_id = { $in: possibleIds };
        }

        const requests = await PatientProblemRequest.find(query);
        res.json({ success: true, count: requests.length, requests });
    } catch (err) {
        console.error('Get Patient Problem Requests Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to fetch problem requests.' });
    }
};

// 3. ADMIN: GET ALL PROBLEM REQUESTS
exports.getAdminProblemRequests = async (req, res) => {
    try {
        const { status } = req.query;
        const query = status ? { status } : {};
        const requests = await PatientProblemRequest.find(query);
        res.json({ success: true, count: requests.length, requests });
    } catch (err) {
        console.error('Get Admin Problem Requests Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to fetch problem requests for admin.' });
    }
};

// 4. ADMIN: SUGGEST DENTIST FOR REQUEST
exports.suggestDentist = async (req, res) => {
    const { id } = req.params; // Request ID
    const { dentistId, notes } = req.body;
    try {
        const problemReq = await PatientProblemRequest.findById(id);
        if (!problemReq) {
            return res.status(404).json({ success: false, message: 'Problem request not found.' });
        }

        const dentist = await Dentist.findOne({ id: dentistId });
        if (!dentist) {
            return res.status(404).json({ success: false, message: 'Selected dentist not found.' });
        }

        // 1. Update Request Status to DENTIST_SUGGESTED
        const updatedReq = await PatientProblemRequest.findByIdAndUpdate(id, {
            status: 'DENTIST_SUGGESTED',
            suggested_dentist_id: dentistId,
            admin_notes: notes || 'Admin reviewed symptoms and suggested specialized dentist.'
        });

        // 2. Create Dentist Suggestion Record
        const adminId = req.user ? req.user.id : null;
        await DentistSuggestion.create({
            request_id: id,
            patient_id: problemReq.patient_id,
            admin_id: adminId,
            dentist_id: dentistId,
            notes: notes || 'Admin suggested dentist'
        });

        // 3. Create In-App Notification for Patient & Dentist
        await Notification.create({
            recipient_role: 'Patient',
            recipient_id: problemReq.patient_id || 'ALL',
            title: '🩺 Dentist Suggested by Admin',
            message: `Admin has reviewed your dental problem request and suggested a specialist. Tap to view dentist profile.`,
            type: 'dentist_suggested'
        });

        await Notification.create({
            recipient_role: 'Dentist',
            recipient_id: dentist.user_id || dentistId,
            title: '📋 New Patient Referral',
            message: `Admin suggested a patient request (${problemReq.problem_category}) to your profile.`,
            type: 'referral_received'
        });

        // 4. Send Push Notification if FCM token available
        const patientUser = await User.findById(problemReq.patient_id);
        if (patientUser?.device_token) {
            await sendPushNotification(
                patientUser.device_token,
                '🩺 Dentist Suggested by Admin',
                `Admin suggested a specialist for your request: ${problemReq.problem_category}`,
                { requestId: String(id), dentistId: String(dentistId), type: 'dentist_suggested' }
            );
        }

        // 5. Existing WhatsApp Integration Logging / Payload Trigger
        console.log(`💬 [WhatsApp Integration] Sending Dentist details to Patient ${patientUser?.phone || 'Phone'}:`);
        console.log(`   - Dentist: ${dentist.speciality} Specialist`);
        console.log(`   - Request ID: ${id}`);

        res.json({
            success: true,
            message: 'Dentist details successfully suggested to patient.',
            request: updatedReq
        });
    } catch (err) {
        console.error('Suggest Dentist Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to suggest dentist.' });
    }
};

// 5. PATIENT: GET SUGGESTED DENTISTS FOR MY REQUESTS
exports.getSuggestedDentists = async (req, res) => {
    try {
        const patientId = req.user ? req.user.id : req.query.patientId;
        const suggestions = await DentistSuggestion.find({ patient_id: patientId });
        res.json({ success: true, count: suggestions.length, suggestions });
    } catch (err) {
        console.error('Get Suggested Dentists Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to fetch suggested dentists.' });
    }
};
