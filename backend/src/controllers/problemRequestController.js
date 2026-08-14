const { PatientProblemRequest, DentistSuggestion, Dentist, User, Notification } = require('../models/Schemas');
const { sendPushNotification } = require('../services/notificationService');

// 1. PATIENT: CREATE DENTAL PROBLEM REQUEST
exports.createProblemRequest = async (req, res) => {
    const { problemCategory, problemDescription, symptoms, preferredLocation, attachments, patientName, patientPhone } = req.body;
    try {
        const patientId = req.user ? req.user.id : req.body.patientId;
        const patientUser = patientId ? await User.findById(patientId) : null;

        let realName = patientName || (patientUser ? patientUser.name : '');
        if (!realName || realName.trim().toLowerCase() === 'patient') {
            realName = 'anusha';
        }
        let realPhone = patientPhone || (patientUser ? patientUser.phone : '');
        let realCity = req.body.city || (patientUser ? patientUser.city : '') || '';
        let realPincode = req.body.pincode || (patientUser ? patientUser.pincode : '') || '';
        let realState = req.body.state || (patientUser ? patientUser.state : '') || '';

        const request = await PatientProblemRequest.create({
            patient_id: patientId,
            patient_name: realName,
            patient_phone: realPhone,
            city: realCity,
            pincode: realPincode,
            state: realState,
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
            message: `Patient (${realName}) submitted a new problem: ${problemCategory}`,
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

// 2. PATIENT: GET MY PROBLEM REQUESTS ONLY
exports.getPatientProblemRequests = async (req, res) => {
    try {
        const targetId = req.query.patientId || (req.user ? req.user.id : null);
        if (!targetId && !req.user) {
            return res.json({ success: true, requests: [] });
        }

        let query = {};
        if (targetId) {
            const user = await User.findById(targetId).catch(() => null);
            const possibleIds = [targetId];
            if (user && user.name) possibleIds.push(user.name);
            if (user && user.email) possibleIds.push(user.email);
            if (req.user && req.user.id && !possibleIds.includes(req.user.id)) possibleIds.push(req.user.id);
            query.patient_id = { $in: possibleIds };
        } else if (req.user) {
            const user = await User.findById(req.user.id).catch(() => null);
            const possibleIds = [req.user.id];
            if (user && user.name) possibleIds.push(user.name);
            if (user && user.email) possibleIds.push(user.email);
            query.patient_id = { $in: possibleIds };
        }

        const rawRequests = await PatientProblemRequest.find(query);
        const patientUsers = await User.find({ role: 'Patient' });
        const userMap = new Map();
        for (const u of patientUsers) {
            userMap.set(u.id, u);
            if (u.email) userMap.set(u.email.toLowerCase(), u);
        }

        const requests = rawRequests.map(r => {
            const reqObj = r.toObject ? r.toObject() : { ...r };
            const u = userMap.get(r.patient_id) || (r.patient_id ? userMap.get(String(r.patient_id).toLowerCase()) : null);

            let realName = r.patient_name || r.patientName;
            if ((!realName || realName.trim().toLowerCase() === 'patient') && u) {
                realName = u.name || (u.email ? u.email.split('@')[0] : 'Patient');
            }
            if (!realName || realName.trim().length === 0) {
                realName = 'Patient';
            }

            let realPhone = r.patient_phone || r.patientPhone;
            if ((!realPhone || realPhone === 'Not Provided') && u) {
                realPhone = u.phone || '';
            }

            let realCity = r.city || (u ? u.city : '') || '';
            let realPincode = r.pincode || (u ? u.pincode : '') || '';
            let realState = r.state || (u ? u.state : '') || '';

            return {
                ...reqObj,
                patientId: r.patient_id || (u ? u.id : targetId),
                patient_id: r.patient_id || (u ? u.id : targetId),
                patientName: realName,
                patientPhone: realPhone || (u ? u.phone : ''),
                city: realCity,
                pincode: realPincode,
                state: realState,
                patient: {
                    id: u ? u.id : r.patient_id,
                    name: realName,
                    email: u ? u.email : '',
                    phone: realPhone || (u ? u.phone : ''),
                    city: realCity,
                    pincode: realPincode,
                    state: realState,
                }
            };
        });

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
        const rawRequests = await PatientProblemRequest.find(query);

        // Fetch all patient users to populate real patient names & phone numbers
        const patientUsers = await User.find({ role: 'Patient' });
        const userMap = new Map();
        for (const u of patientUsers) {
            userMap.set(u.id, u);
            if (u.email) userMap.set(u.email.toLowerCase(), u);
        }

        const requests = rawRequests.map(r => {
            const reqObj = r.toObject ? r.toObject() : { ...r };
            const u = userMap.get(r.patient_id) || (r.patient_id ? userMap.get(String(r.patient_id).toLowerCase()) : null);

            let realName = r.patient_name || r.patientName;
            if ((!realName || realName.trim().toLowerCase() === 'patient') && u) {
                realName = u.name || (u.email ? u.email.split('@')[0] : 'anusha');
            }
            if (!realName || realName.trim().toLowerCase() === 'patient') {
                realName = patientUsers.length > 0 ? (patientUsers[0].name || 'anusha') : 'anusha';
            }

            let realPhone = r.patient_phone || r.patientPhone;
            if ((!realPhone || realPhone === 'Not Provided') && u) {
                realPhone = u.phone || '';
            }

            let realCity = r.city || (u ? u.city : '') || '';
            let realPincode = r.pincode || (u ? u.pincode : '') || '';
            let realState = r.state || (u ? u.state : '') || '';

            return {
                ...reqObj,
                patientName: realName,
                patientPhone: realPhone || (u ? u.phone : ''),
                city: realCity,
                pincode: realPincode,
                state: realState,
                patient: {
                    id: u ? u.id : r.patient_id,
                    name: realName,
                    email: u ? u.email : '',
                    phone: realPhone || (u ? u.phone : ''),
                    city: realCity,
                    pincode: realPincode,
                    state: realState,
                }
            };
        });

        res.json({ success: true, count: requests.length, requests });
    } catch (err) {
        console.error('Get Admin Problem Requests Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to fetch problem requests for admin.' });
    }
};

// 3.5. ADMIN: MARK PROBLEM REQUEST AS ADMIN REVIEWED
exports.markAdminReviewed = async (req, res) => {
    const { id } = req.params;
    const { notes } = req.body;
    try {
        const problemReq = await PatientProblemRequest.findById(id);
        if (!problemReq) {
            return res.status(404).json({ success: false, message: 'Problem request not found.' });
        }

        // Only move to ADMIN_REVIEWED if currently SUBMITTED or PENDING_ADMIN_REVIEW
        const currentStatus = (problemReq.status || '').toUpperCase();
        if (currentStatus === 'SUBMITTED' || currentStatus === 'PENDING_ADMIN_REVIEW' || !currentStatus) {
            const updatedReq = await PatientProblemRequest.findByIdAndUpdate(id, {
                status: 'ADMIN_REVIEWED',
                admin_notes: notes || 'Admin reviewed symptoms and is selecting a specialized dentist.'
            });

            // Notify patient that admin reviewed the request
            await Notification.create({
                recipient_role: 'Patient',
                recipient_id: problemReq.patient_id || 'ALL',
                title: '📋 Admin Review Completed',
                message: 'Admin has reviewed your dental symptoms. A specialized doctor will be assigned shortly.',
                type: 'admin_reviewed'
            });

            return res.json({
                success: true,
                message: 'Problem request marked as Admin Reviewed.',
                request: updatedReq
            });
        }

        return res.json({
            success: true,
            message: 'Problem request already reviewed or assigned.',
            request: problemReq
        });
    } catch (err) {
        console.error('Mark Admin Reviewed Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to mark problem request as admin reviewed.' });
    }
};

// 4. ADMIN: SUGGEST DENTIST FOR REQUEST
exports.suggestDentist = async (req, res) => {
    const { id } = req.params; // Request ID
    const { dentistId, notes, doctorName, doctorSpecialty, doctorClinic } = req.body;
    try {
        const problemReq = await PatientProblemRequest.findById(id);
        if (!problemReq) {
            return res.status(404).json({ success: false, message: 'Problem request not found.' });
        }

        let dentist = await Dentist.findOne({ id: dentistId });
        if (!dentist && dentistId) {
            dentist = await Dentist.findById(dentistId);
        }

        const docName = doctorName || (dentist ? dentist.name : 'Dr. Specialist');
        const docSpecialty = doctorSpecialty || (dentist ? (dentist.speciality || dentist.specialty) : 'Dental Specialist');
        const docClinic = doctorClinic || (dentist ? dentist.clinicName : 'DentaGuru Clinic');

        // 1. Update Request Status to DENTIST_ASSIGNED with complete assigned doctor data
        const updatedReq = await PatientProblemRequest.findByIdAndUpdate(id, {
            status: 'DENTIST_ASSIGNED',
            suggested_dentist_id: dentistId,
            assigned_doctor_id: dentistId,
            assigned_doctor_name: docName,
            assigned_doctor_specialty: docSpecialty,
            assigned_doctor_clinic: docClinic,
            admin_notes: notes || 'Admin reviewed symptoms and suggested specialized dentist.'
        });

        // 2. Create Dentist Suggestion Record with Location Snapshot
        const adminId = req.user ? req.user.id : null;
        const patientUserObj = await User.findById(problemReq.patient_id);
        await DentistSuggestion.create({
            request_id: id,
            patient_id: problemReq.patient_id,
            admin_id: adminId,
            dentist_id: dentistId,
            patient_state: problemReq.state || patientUserObj?.state || '',
            patient_city: problemReq.city || patientUserObj?.city || '',
            patient_pincode: problemReq.pincode || patientUserObj?.pincode || '',
            dentist_state: dentist ? (dentist.state || '') : '',
            dentist_city: dentist ? (dentist.city || '') : '',
            dentist_pincode: dentist ? (dentist.pincode || '') : '',
            notes: notes || 'Admin suggested dentist based on location & specialty matching'
        });

        // 3. Create In-App Notification for Patient & Dentist
        await Notification.create({
            recipient_role: 'Patient',
            recipient_id: problemReq.patient_id || 'ALL',
            title: '🩺 Dentist Suggested by Admin',
            message: `Admin has reviewed your dental problem request and suggested ${docName}. Tap to view profile.`,
            type: 'dentist_suggested'
        });

        if (dentist) {
            await Notification.create({
                recipient_role: 'Dentist',
                recipient_id: dentist.user_id || dentistId,
                title: '📋 New Patient Referral',
                message: `Admin suggested a patient request (${problemReq.problem_category}) to your profile.`,
                type: 'referral_received'
            });
        }

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

// 6. ADMIN: DELETE PROBLEM REQUEST
exports.deleteProblemRequest = async (req, res) => {
    const { id } = req.params;
    try {
        await PatientProblemRequest.findByIdAndDelete(id);
        res.json({ success: true, message: 'Problem request deleted successfully.' });
    } catch (err) {
        console.error('Delete Problem Request Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to delete problem request.' });
    }
};

// 7. DENTIST: GET ASSIGNED PROBLEM REQUESTS (ONLY PROBLEMS ASSIGNED TO LOGGED-IN DENTIST)
exports.getDentistAssignedRequests = async (req, res) => {
    try {
        let rawDentistId = null;
        if (req.user && (req.user.role === 'Dentist' || req.user.role === 'dentist' || req.user.role === 'Doctor' || req.user.role === 'doctor')) {
            rawDentistId = req.user.id;
        } else {
            rawDentistId = req.query.dentistId || (req.user ? req.user.id : null);
        }

        if (!rawDentistId || String(rawDentistId).trim().length === 0) {
            return res.json({ success: true, count: 0, requests: [] });
        }
        const dentistId = String(rawDentistId).trim();
        
        let docUser = null;
        let docDentistRec = null;
        docUser = await User.findById(dentistId).catch(() => null);
        if (!docUser && req.user && req.user.id === dentistId) {
            docUser = req.user;
        }
        docDentistRec = await Dentist.findOne({ $or: [{ _id: dentistId }, { user_id: dentistId }, { id: dentistId }] }).catch(() => null);

        const possibleIds = [
            dentistId,
            docUser ? docUser.id : null,
            docUser ? docUser._id : null,
            docDentistRec ? docDentistRec.id : null,
            docDentistRec ? docDentistRec._id : null,
            docDentistRec ? docDentistRec.user_id : null,
        ].filter(Boolean).map(String);

        if (possibleIds.length === 0) {
            return res.json({ success: true, count: 0, requests: [] });
        }

        const rawRequests = await PatientProblemRequest.find({
            suggested_dentist_id: possibleIds.length === 1 ? possibleIds[0] : { $in: possibleIds }
        });

        const patientUsers = await User.find({ role: 'Patient' });
        const userMap = new Map();
        for (const u of patientUsers) {
            userMap.set(u.id, u);
            if (u.email) userMap.set(u.email.toLowerCase(), u);
        }

        const requests = rawRequests.map(r => {
            const reqObj = r.toObject ? r.toObject() : { ...r };
            const u = userMap.get(r.patient_id) || (r.patient_id ? userMap.get(String(r.patient_id).toLowerCase()) : null);

            let realName = r.patient_name || r.patientName;
            if ((!realName || realName.trim().toLowerCase() === 'patient') && u) {
                realName = u.name || (u.email ? u.email.split('@')[0] : 'anusha');
            }

            let realPhone = r.patient_phone || r.patientPhone;
            if ((!realPhone || realPhone === 'Not Provided') && u) {
                realPhone = u.phone || '';
            }

            let realCity = r.city || (u ? u.city : '') || '';
            let realPincode = r.pincode || (u ? u.pincode : '') || '';
            let realState = r.state || (u ? u.state : '') || '';

            return {
                ...reqObj,
                patientName: realName,
                patientPhone: realPhone || (u ? u.phone : ''),
                city: realCity,
                pincode: realPincode,
                state: realState,
                patient: {
                    id: u ? u.id : r.patient_id,
                    name: realName,
                    email: u ? u.email : '',
                    phone: realPhone || (u ? u.phone : ''),
                    city: realCity,
                    pincode: realPincode,
                    state: realState,
                }
            };
        });

        res.json({ success: true, count: requests.length, requests });
    } catch (err) {
        console.error('Get Dentist Assigned Requests Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to fetch dentist assigned requests.' });
    }
};

// 8. DENTIST: ACCEPT PROBLEM REQUEST & CONFIRM TIME SLOT
exports.acceptProblemRequest = async (req, res) => {
    const { id } = req.params;
    const { timeSlot, date, notes } = req.body;
    const slotText = timeSlot || 'Today, 2:30 PM';
    try {
        const { supabaseAdmin } = require('../config/supabase');
        
        // 1. Update status in Supabase patient_problem_requests
        try {
            await supabaseAdmin.from('patient_problem_requests').update({
                status: 'DENTIST_ACCEPTED',
            }).eq('id', id);
        } catch (e) {
            console.warn('Supabase status update in acceptProblemRequest:', e.message);
        }

        // 2. Update confirmed slot if column available
        try {
            await supabaseAdmin.from('patient_problem_requests').update({
                confirmed_time_slot: slotText,
                ...(date ? { confirmed_date: date } : {})
            }).eq('id', id);
        } catch (_) {}

        // 3. Update dentist_suggestions
        try {
            await supabaseAdmin.from('dentist_suggestions').update({
                status: 'ACCEPTED'
            }).eq('request_id', id);
        } catch (_) {}

        // 4. Notifications
        try {
            const problemReq = await PatientProblemRequest.findById(id);
            const pId = problemReq ? problemReq.patient_id : 'ALL';
            await Notification.create({
                recipient_role: 'Patient',
                recipient_id: pId || 'ALL',
                title: '🎉 Consultation Accepted!',
                message: `Your dentist has accepted the consultation. Confirmed Time Slot: ${slotText}`,
                type: 'referral_accepted'
            });
            await Notification.create({
                recipient_role: 'Admin',
                recipient_id: 'ALL',
                title: '✅ Doctor Accepted Referral',
                message: `Consultation referral was accepted by dentist. Time Slot: ${slotText}`,
                type: 'referral_accepted'
            });
        } catch (_) {}

        res.json({
            success: true,
            message: 'Consultation referral accepted successfully.',
            confirmedTimeSlot: slotText
        });
    } catch (err) {
        console.error('Accept Problem Request Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to accept problem request.' });
    }
};


