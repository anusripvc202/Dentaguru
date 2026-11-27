const { PatientProblemRequest, DentistSuggestion, Dentist, User, Notification, PatientAssignmentHistory, District, SubAdminDistrict, ASSIGNMENT_SOURCES, isDoctorRecordAvailable } = require('../models/Schemas');
const { sendPushNotification } = require('../services/notificationService');
const { resolveCallerAccessContext } = require('../middleware/auth');

/**
 * Resolves a consultation request's patient district strictly from the PATIENT'S registered location
 * (or the patient's own location fields on the request). NEVER falls back to doctor or clinic district!
 */
function buildRequestPatientLocationPayload(reqRow = {}, patientUser = null) {
    return {
        districtId: patientUser?.district_id || patientUser?.districtId || reqRow.district_id || reqRow.districtId || null,
        district: patientUser?.district || reqRow.district || null,
        city: (patientUser?.city && String(patientUser.city).trim()) ? patientUser.city : (reqRow.city || ''),
        state: (patientUser?.state && String(patientUser.state).trim()) ? patientUser.state : (reqRow.state || ''),
        pincode: (patientUser?.pincode && String(patientUser.pincode).trim()) ? patientUser.pincode : (reqRow.pincode || ''),
        device_token: patientUser?.device_token || null
    };
}

const COORDINATOR_STAGES = [
    'SUBMITTED',
    'ASSIGNED',
    'CONTACTING_PATIENT',
    'DOCTOR_IDENTIFIED',
    'RESOLVED',
    'CLOSED',
];

const COORDINATOR_STAGE_LABELS = {
    SUBMITTED: 'Submitted',
    PENDING_ADMIN_REVIEW: 'Submitted',
    ASSIGNED: 'Assigned',
    ADMIN_REVIEWED: 'Assigned',
    CONTACTING_PATIENT: 'Contacting Patient',
    DOCTOR_IDENTIFIED: 'Doctor Identified',
    DENTIST_ASSIGNED: 'Doctor Identified',
    DENTIST_SUGGESTED: 'Doctor Identified',
    RESOLVED: 'Resolved',
    DENTIST_ACCEPTED: 'Resolved',
    CLOSED: 'Closed',
    COMPLETED: 'Closed',
};

function normalizeCoordinatorStage(raw) {
    const clean = String(raw || '').trim();
    if (!clean) return 'SUBMITTED';
    const upper = clean.toUpperCase().replace(/[\s-]+/g, '_');
    if (COORDINATOR_STAGES.includes(upper)) return upper;
    if (upper === 'PENDING_ADMIN_REVIEW') return 'SUBMITTED';
    if (upper === 'ADMIN_REVIEWED' || upper === 'ADMIN_REVIEW') return 'ASSIGNED';
    if (upper === 'DENTIST_ASSIGNED' || upper === 'DENTIST_SUGGESTED') return 'DOCTOR_IDENTIFIED';
    if (upper === 'DENTIST_ACCEPTED') return 'RESOLVED';
    if (upper === 'COMPLETED') return 'CLOSED';
    return 'SUBMITTED';
}

function parseCoordinatorMeta(adminNotes) {
    const raw = String(adminNotes || '');
    const marker = 'COORD_META:';
    const idx = raw.indexOf(marker);
    if (idx === -1) return { humanNote: raw.trim(), meta: {} };
    const humanNote = raw.slice(0, idx).trim();
    const jsonPart = raw.slice(idx + marker.length).trim();
    try {
        const meta = JSON.parse(jsonPart);
        return { humanNote, meta: meta && typeof meta === 'object' ? meta : {} };
    } catch (_) {
        return { humanNote, meta: {} };
    }
}

function serializeCoordinatorMeta(humanNote, meta) {
    const cleanHuman = String(humanNote || '').trim();
    const serialized = `COORD_META:${JSON.stringify(meta || {})}`;
    return cleanHuman ? `${cleanHuman}\n${serialized}` : serialized;
}

// 1. PATIENT: CREATE MULTI-SPECIALTY CONSULTATION / TRIAGE / COORDINATOR ASSISTANCE REQUEST
exports.createProblemRequest = async (req, res) => {
    const { problemCategory, problemDescription, symptoms, preferredLocation, attachments, patientName, patientPhone, specialty, speciality, appointmentId, escalationType } = req.body;
    try {
        const patientId = req.user ? req.user.id : req.body.patientId;
        const patientUser = patientId ? await User.findById(patientId) : null;

        let realName = patientName || (patientUser ? patientUser.name : '');
        if (!realName || realName.trim().toLowerCase() === 'patient') {
            realName = (patientUser && patientUser.name) ? patientUser.name : 'Patient';
        }
        let realPhone = patientPhone || (patientUser ? patientUser.phone : '');
        let realCity = req.body.city || (patientUser ? patientUser.city : '') || '';
        let realPincode = req.body.pincode || (patientUser ? patientUser.pincode : '') || '';
        let realState = req.body.state || (patientUser ? patientUser.state : '') || '';

        const preferredDoctorId = req.body.preferredDoctorId || req.body.suggested_dentist_id;
        let resolvedSpecialty = String(specialty || speciality || '').trim();
        if (preferredDoctorId) {
            const targetDoc = await Dentist.findById(preferredDoctorId);
            if (targetDoc && !isDoctorRecordAvailable(targetDoc)) {
                return res.status(409).json({
                    success: false,
                    unavailable: true,
                    isAvailable: false,
                    message: 'Doctor is currently unavailable and not accepting new consultation requests.'
                });
            }
            if (!resolvedSpecialty && targetDoc) {
                resolvedSpecialty = String(targetDoc.speciality || targetDoc.specialty || '').trim();
            }
        }
        const isDirectReferral = !!preferredDoctorId;
        const isCoordinatorEscalation = !isDirectReferral && String(escalationType || '').toUpperCase() === 'COORDINATOR_ASSISTANCE';

        // Resolve patient's district & matching Sub-Admin coordinator if available
        const locRes = District.resolveDistrictFromLocation({
            city: realCity,
            district: patientUser?.district,
            state: realState,
            pincode: realPincode
        });
        const resolvedDistrictName = locRes.district || patientUser?.district || realCity || '';
        const resolvedDistrictId = locRes.districtId || null;

        let matchedCoordinator = null;
        if (!isDirectReferral) {
            try {
                const subAdmins = await User.find({ role: { $in: ['Sub-Admin', 'SUB_ADMIN', 'SUB-ADMIN'] } });
                for (const sa of (subAdmins || [])) {
                    const saStatus = String(sa.status || 'ACTIVE').toUpperCase();
                    if (saStatus !== 'ACTIVE') continue;
                    const assignedDists = await SubAdminDistrict.getDistrictsForSubAdmin(sa.id).catch(() => []);
                    const matchesDistrict = assignedDists.some(d =>
                        (resolvedDistrictId && d.id === resolvedDistrictId) ||
                        (resolvedDistrictName && d.name && d.name.toLowerCase() === resolvedDistrictName.toLowerCase())
                    );
                    if (matchesDistrict) {
                        matchedCoordinator = sa;
                        break;
                    }
                }
            } catch (_) {}
        }

        const initialStatus = isDirectReferral
            ? 'DENTIST_ASSIGNED'
            : (isCoordinatorEscalation
                ? (matchedCoordinator ? 'ASSIGNED' : 'SUBMITTED')
                : 'PENDING_ADMIN_REVIEW');

        const effectiveCategory = problemCategory || (resolvedSpecialty ? `${resolvedSpecialty} Consultation` : 'General Medical Consultation');
        const effectiveSymptoms = [
            resolvedSpecialty ? `Specialty: ${resolvedSpecialty}` : '',
            appointmentId ? `Appointment: ${appointmentId}` : '',
            isCoordinatorEscalation ? 'Coordinator Assistance Escalation' : '',
            symptoms || ''
        ].filter(Boolean).join(' • ');

        const coordMeta = isDirectReferral
            ? null
            : {
                escalationType: isCoordinatorEscalation ? 'COORDINATOR_ASSISTANCE' : 'TRIAGE',
                specialty: resolvedSpecialty || '',
                coordinatorStatus: matchedCoordinator && isCoordinatorEscalation ? 'ASSIGNED' : 'SUBMITTED',
                assignedCoordinatorId: matchedCoordinator?.id || null,
                assignedCoordinatorName: matchedCoordinator?.name || null,
                districtName: resolvedDistrictName || 'Unassigned',
                followUpNotes: []
            };
        const initialNotes = isDirectReferral
            ? `Direct patient referral to ${req.body.preferredDoctorName || 'Doctor'}`
            : serializeCoordinatorMeta(
                isCoordinatorEscalation
                    ? `Coordinator assistance requested${resolvedSpecialty ? ` for ${resolvedSpecialty}` : ''}.`
                    : '',
                coordMeta
            );

        const request = await PatientProblemRequest.create({
            patient_id: patientId,
            patient_name: realName,
            patient_phone: realPhone,
            city: realCity,
            pincode: realPincode,
            state: realState,
            specialty: resolvedSpecialty || undefined,
            problem_category: effectiveCategory,
            problem_description: problemDescription || '',
            symptoms: effectiveSymptoms,
            preferred_location: preferredLocation || null,
            attachments: attachments || [],
            status: initialStatus,
            suggested_dentist_id: preferredDoctorId || null,
            admin_notes: initialNotes
        });

        if (isDirectReferral) {
            try {
                await DentistSuggestion.create({
                    request_id: request.id || request._id,
                    patient_id: patientId,
                    dentist_id: preferredDoctorId,
                    status: 'SUGGESTED',
                    notes: `Direct referral consultation with ${req.body.preferredDoctorName || 'Doctor'}`
                });
            } catch (_) {}
        }

        // 🔔 Dispatch Notification to Doctor, District Coordinator / Sub-Admin, and Admin
        await Notification.create({
            recipient_role: isDirectReferral ? 'Dentist' : 'Admin',
            recipient_id: isDirectReferral ? preferredDoctorId : 'ALL_ADMINS',
            title: isDirectReferral
                ? '🩺 Direct Referral Consultation'
                : (isCoordinatorEscalation ? '🚨 Coordinator Assistance Needed' : '🚨 New Consultation Request'),
            message: isCoordinatorEscalation
                ? `Patient ${realName}${realPhone ? ` (${realPhone})` : ''} needs ${resolvedSpecialty || 'specialist'} assistance in ${resolvedDistrictName || 'their area'}.`
                : `Patient (${realName}) consultation request for ${effectiveCategory}`,
            type: isCoordinatorEscalation ? 'coordinator_escalation' : 'problem_request'
        });

        if (matchedCoordinator?.id) {
            await Notification.create({
                recipient_role: 'Sub-Admin',
                recipient_id: matchedCoordinator.id,
                title: '📞 District Coordinator Assistance Assigned',
                message: `Please contact ${realName}${realPhone ? ` (${realPhone})` : ''} for ${resolvedSpecialty || effectiveCategory} in ${resolvedDistrictName}.`,
                type: 'coordinator_escalation'
            }).catch(() => {});
        }

        res.status(201).json({
            success: true,
            message: isDirectReferral
                ? 'Referral submitted directly to doctor.'
                : (isCoordinatorEscalation
                    ? 'Your request has been escalated to our district coordinator team for phone follow-up.'
                    : 'Consultation request submitted successfully. Awaiting admin review.'),
            coordinatorStatus: COORDINATOR_STAGE_LABELS[initialStatus] || 'Submitted',
            assignedCoordinator: matchedCoordinator ? { id: matchedCoordinator.id, name: matchedCoordinator.name } : null,
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

// 3. ADMIN: GET ALL PROBLEM REQUESTS (Enforces Strict Sub-Admin District Access Control)
exports.getAdminProblemRequests = async (req, res) => {
    try {
        const callerCtx = await resolveCallerAccessContext(req);
        const reqDistrictId = String(req.query.districtId || req.query.district_id || '').trim();
        const reqDistrictName = String(req.query.district || '').trim();

        if (callerCtx.isSubAdmin && (reqDistrictId || reqDistrictName) && reqDistrictName.toLowerCase() !== 'all' && reqDistrictId.toLowerCase() !== 'all') {
            let requestedIdLower = reqDistrictId.toLowerCase();
            if (!requestedIdLower && reqDistrictName) {
                const resolvedFilter = District.resolveDistrictFromLocation({ district: reqDistrictName });
                requestedIdLower = resolvedFilter?.districtId ? String(resolvedFilter.districtId).toLowerCase() : '__unmatched__';
            }
            if (!callerCtx.assignedDistrictIds.has(requestedIdLower)) {
                return res.status(403).json({
                    success: false,
                    code: 'DISTRICT_ACCESS_DENIED',
                    message: 'Access Denied: You cannot view patient requests outside your assigned district.'
                });
            }
        }

        const { status } = req.query;
        const query = status ? { status } : {};
        const rawRequests = await PatientProblemRequest.find(query);

        // Fetch all patient users to populate real patient names, phone numbers & registered location
        const patientUsers = await User.find({ role: 'Patient' });
        const userMap = new Map();
        const phoneMap = new Map();
        for (const u of patientUsers) {
            userMap.set(u.id, u);
            if (u.email) userMap.set(u.email.toLowerCase(), u);
            const digits10 = String(u.phone || '').replace(/\D/g, '').slice(-10);
            if (digits10.length === 10) phoneMap.set(digits10, u);
        }

        let requests = [];
        for (const r of rawRequests) {
            const reqObj = r.toObject ? r.toObject() : { ...r };
            const rPhone10 = String(r.patient_phone || r.patientPhone || '').replace(/\D/g, '').slice(-10);
            const u = userMap.get(r.patient_id)
                || (r.patient_id ? userMap.get(String(r.patient_id).toLowerCase()) : null)
                || (rPhone10.length === 10 ? phoneMap.get(rPhone10) : null);

            const patientLocPayload = buildRequestPatientLocationPayload(r, u);
            const distInfo = District.resolvePatientDistrictStrict(patientLocPayload);

            // STRICT SUB-ADMIN DISTRICT ACCESS ENFORCEMENT:
            if (callerCtx.isSubAdmin) {
                const check = SubAdminDistrict.canSubAdminAccessPatientSync(callerCtx.assignedDistricts, patientLocPayload);
                if (!check.allowed) {
                    continue;
                }
            }

            let realName = r.patient_name || r.patientName;
            if ((!realName || realName.trim().toLowerCase() === 'patient') && u) {
                realName = u.name || (u.email ? u.email.split('@')[0] : 'Patient');
            }
            if (!realName || realName.trim().toLowerCase() === 'patient') {
                realName = 'Patient';
            }

            let realPhone = r.patient_phone || r.patientPhone;
            if ((!realPhone || realPhone === 'Not Provided') && u) {
                realPhone = u.phone || '';
            }

            let realCity = patientLocPayload.city || '';
            let realPincode = patientLocPayload.pincode || '';
            let realState = distInfo.state || patientLocPayload.state || '';

            const d = r.suggested_dentist || {};
            const dUser = d.users || {};
            const dClinic = d.clinics || {};
            const docName = dUser.name ? (dUser.name.startsWith('Dr.') ? dUser.name : `Dr. ${dUser.name}`) : (r.assigned_doctor_name || '');
            const docSpecialty = d.speciality || d.specialty || r.assigned_doctor_specialty || 'General Medicine';
            const docClinic = dClinic.clinic_name || r.assigned_doctor_clinic || 'GS HEALTH Care Center';

            const parsedCoord = parseCoordinatorMeta(r.admin_notes);
            requests.push({
                ...reqObj,
                patientName: realName,
                patientPhone: realPhone || (u ? u.phone : ''),
                city: realCity,
                pincode: realPincode,
                state: realState,
                district: distInfo.districtName || '',
                districtId: distInfo.districtId || null,
                district_id: distInfo.districtId || null,
                districtIdentificationStatus: distInfo.isVerified ? 'VERIFIED' : 'UNVERIFIED',
                coordinatorStatus: COORDINATOR_STAGE_LABELS[String(r.status || '').toUpperCase()] || parsedCoord.meta?.coordinatorStatus || 'Submitted',
                coordinatorMeta: parsedCoord.meta || {},
                assigned_doctor_name: docName || reqObj.assigned_doctor_name,
                assigned_doctor_specialty: docSpecialty || reqObj.assigned_doctor_specialty,
                assigned_doctor_clinic: docClinic || reqObj.assigned_doctor_clinic,
                dentist: {
                    id: d.id || r.suggested_dentist_id,
                    name: docName,
                    specialty: docSpecialty,
                    clinicName: docClinic,
                    email: dUser.email || '',
                    phone: dUser.phone || '',
                },
                patient: {
                    id: u ? u.id : r.patient_id,
                    name: realName,
                    email: u ? u.email : '',
                    phone: realPhone || (u ? u.phone : ''),
                    city: realCity,
                    pincode: realPincode,
                    state: realState,
                    district: distInfo.districtName || '',
                    districtId: distInfo.districtId || null,
                    districtIdentificationStatus: distInfo.isVerified ? 'VERIFIED' : 'UNVERIFIED',
                }
            });
        }

        // Optional State, District, and Search Filters
        const stateFilter = String(req.query.state || '').trim().toLowerCase();
        if (stateFilter && stateFilter !== 'all') {
            requests = requests.filter(r => String(r.state || '').trim().toLowerCase() === stateFilter);
        }
        if ((reqDistrictId && reqDistrictId.toLowerCase() !== 'all') || (reqDistrictName && reqDistrictName.toLowerCase() !== 'all')) {
            const resolvedFilter = !reqDistrictId && reqDistrictName
                ? District.resolveDistrictFromLocation({ district: reqDistrictName })
                : null;
            const effectiveIdLower = (reqDistrictId || resolvedFilter?.districtId || '').toString().toLowerCase();
            const targetNameLower = reqDistrictName.toLowerCase();
            requests = requests.filter(r => {
                if (effectiveIdLower && r.districtId && String(r.districtId).toLowerCase() === effectiveIdLower) return true;
                if (!effectiveIdLower && targetNameLower && String(r.district || '').toLowerCase() === targetNameLower) return true;
                return false;
            });
        }
        const searchQuery = String(req.query.search || req.query.q || '').trim().toLowerCase();
        if (searchQuery) {
            requests = requests.filter(r =>
                String(r.patientName || '').toLowerCase().includes(searchQuery) ||
                String(r.patientPhone || '').toLowerCase().includes(searchQuery) ||
                String(r.problem_category || r.problemCategory || '').toLowerCase().includes(searchQuery) ||
                String(r.problem_description || r.problemDescription || '').toLowerCase().includes(searchQuery) ||
                String(r.city || '').toLowerCase().includes(searchQuery) ||
                String(r.district || '').toLowerCase().includes(searchQuery) ||
                String(r.pincode || '').toLowerCase().includes(searchQuery)
            );
        }

        // Sort by actual creation timestamp descending (newest first)
        requests.sort((a, b) => {
            const tA = new Date(a.created_at || a.submitted_at || a.submittedAt || 0).getTime() || 0;
            const tB = new Date(b.created_at || b.submitted_at || b.submittedAt || 0).getTime() || 0;
            return tB - tA;
        });

        const totalCount = requests.length;
        const rawLimit = parseInt(req.query.limit, 10);
        const rawPage = parseInt(req.query.page, 10);
        let resultRequests = requests;
        if (Number.isFinite(rawLimit) && rawLimit > 0) {
            const page = (Number.isFinite(rawPage) && rawPage > 0) ? rawPage : 1;
            const start = (page - 1) * rawLimit;
            resultRequests = requests.slice(start, start + rawLimit);
        }

        res.json({
            success: true,
            count: resultRequests.length,
            totalCount,
            requests: resultRequests
        });
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

        const callerCtx = await resolveCallerAccessContext(req);
        if (callerCtx.isSubAdmin) {
            const patientUserObj = problemReq.patient_id ? await User.findById(problemReq.patient_id).catch(() => null) : null;
            const locPayload = buildRequestPatientLocationPayload(problemReq, patientUserObj);
            const check = SubAdminDistrict.canSubAdminAccessPatientSync(callerCtx.assignedDistricts, locPayload);
            if (!check.allowed) {
                return res.status(403).json({
                    success: false,
                    code: 'DISTRICT_ACCESS_DENIED',
                    message: 'Access Denied: You cannot review patient requests outside your assigned district.'
                });
            }
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
                message: 'Admin has reviewed your symptoms. A specialized doctor will be assigned shortly.',
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

        let dentist = null;
        if (dentistId) {
            dentist = await Dentist.findById(dentistId).catch(() => null);
        }
        if (!dentist && dentistId) {
            dentist = await Dentist.findOne({ $or: [{ id: dentistId }, { user_id: dentistId }, { _id: dentistId }] }).catch(() => null);
        }

        const resolvedDentistTableId = dentist ? dentist.id : dentistId;
        const resolvedDentistUserId = dentist ? (dentist.user_id || dentistId) : dentistId;

        const docName = doctorName || (dentist ? (dentist.users?.name || dentist.name) : 'Dr. Specialist');

        // Resolve Patient District Strictly from Patient Location & Enforce Sub-Admin Access
        const patientUserObj = problemReq.patient_id ? await User.findById(problemReq.patient_id).catch(() => null) : null;
        const patientLocPayload = buildRequestPatientLocationPayload(problemReq, patientUserObj);
        const locRes = District.resolvePatientDistrictStrict(patientLocPayload);

        const callerCtx = await resolveCallerAccessContext(req);
        const isMainAdmin = callerCtx.isMainAdmin;
        const isSubAdmin = callerCtx.isSubAdmin;

        const finalDistrictName = locRes.districtName || 'Unassigned / Review';
        const finalDistrictId = locRes.districtId || null;

        // Sub-Admin District Jurisdiction Enforcement (Strict districtId match; rejects missing/unverified district)
        if (isSubAdmin) {
            const check = SubAdminDistrict.canSubAdminAccessPatientSync(callerCtx.assignedDistricts, patientLocPayload);
            if (!check.allowed) {
                return res.status(403).json({
                    success: false,
                    code: 'DISTRICT_ACCESS_DENIED',
                    message: `Access Denied: You cannot assign patients in '${finalDistrictName}'. This patient request is outside your assigned district or has unverified district information.`
                });
            }
        }

        // 1. Update Request Status to DENTIST_ASSIGNED with valid native schema columns
        const updatedReq = await PatientProblemRequest.findByIdAndUpdate(id, {
            status: 'DENTIST_ASSIGNED',
            suggested_dentist_id: resolvedDentistTableId,
            district_id: finalDistrictId,
            district: finalDistrictName,
            admin_notes: notes || 'Admin reviewed symptoms and suggested specialized dentist.'
        });

        // 📜 Record in Immutable Patient Assignment Audit History
        try {
            const assignmentSource = isMainAdmin ? ASSIGNMENT_SOURCES.MAIN_ADMIN_ASSIGNMENT : ASSIGNMENT_SOURCES.SUB_ADMIN_ASSIGNMENT;
            const assignedByRole = isMainAdmin ? 'MAIN_ADMIN' : 'SUB_ADMIN';
            const assignedByName = req.user?.name || (isMainAdmin ? 'Main Admin' : 'Sub-Admin');

            await PatientAssignmentHistory.recordAssignment({
                patientId: problemReq.patient_id,
                doctorId: resolvedDentistTableId,
                appointmentId: null,
                requestId: id,
                assignedByUserId: req.user?.id || null,
                assignedByName,
                assignedByRole,
                assignmentSource,
                districtId: finalDistrictId,
                districtName: finalDistrictName,
                assignmentReason: notes || 'Admin reviewed symptoms and suggested specialized dentist.',
                status: 'ASSIGNED'
            });
        } catch (auditErr) {
            console.warn('⚠️ Patient assignment audit trail notice:', auditErr.message);
        }

        // 2. Create Dentist Suggestion Record with Location Snapshot
        const adminId = req.user ? req.user.id : null;
        await DentistSuggestion.create({
            request_id: id,
            patient_id: problemReq.patient_id,
            admin_id: adminId,
            dentist_id: resolvedDentistTableId,
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
            title: '🩺 Doctor Suggested by Admin',
            message: `Admin has reviewed your consultation request and suggested ${docName}. Tap to view profile.`,
            type: 'doctor_suggested'
        });

        if (dentist || resolvedDentistUserId) {
            await Notification.create({
                recipient_role: 'Dentist',
                recipient_id: resolvedDentistUserId,
                title: '📋 New Patient Referral',
                message: `Admin suggested a patient request (${problemReq.problem_category}) to your profile.`,
                type: 'referral_received'
            });
        }

        res.json({
            success: true,
            message: 'Doctor details successfully suggested to patient.',
            request: updatedReq
        });
    } catch (err) {
        console.error('Suggest Doctor Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to suggest doctor.' });
    }
};

// 5. PATIENT: GET SUGGESTED DOCTORS FOR MY REQUESTS
exports.getSuggestedDentists = async (req, res) => {
    try {
        const patientId = req.user ? req.user.id : req.query.patientId;
        const suggestions = await DentistSuggestion.find({ patient_id: patientId });
        res.json({ success: true, count: suggestions.length, suggestions });
    } catch (err) {
        console.error('Get Suggested Doctors Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to fetch suggested doctors.' });
    }
};

// 6. ADMIN: DELETE PROBLEM REQUEST
exports.deleteProblemRequest = async (req, res) => {
    const { id } = req.params;
    try {
        const existing = await PatientProblemRequest.findById(id);
        if (existing) {
            const callerCtx = await resolveCallerAccessContext(req);
            if (callerCtx.isSubAdmin) {
                const patientUserObj = existing.patient_id ? await User.findById(existing.patient_id).catch(() => null) : null;
                const locPayload = buildRequestPatientLocationPayload(existing, patientUserObj);
                const check = SubAdminDistrict.canSubAdminAccessPatientSync(callerCtx.assignedDistricts, locPayload);
                if (!check.allowed) {
                    return res.status(403).json({
                        success: false,
                        code: 'DISTRICT_ACCESS_DENIED',
                        message: 'Access Denied: You cannot delete patient requests outside your assigned district.'
                    });
                }
            }
        }
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
        
        // Lookup User by ID, email, or name
        docUser = await User.findOne({
            $or: [
                { id: dentistId },
                { _id: dentistId },
                { email: dentistId.toLowerCase() },
                { name: dentistId },
                { name: `Dr. ${dentistId}` }
            ]
        }).catch(() => null);
        
        if (!docUser && req.user && req.user.id === dentistId) {
            docUser = req.user;
        }
        
        // Lookup Dentist record by ID, user_id, or docUser.id
        docDentistRec = await Dentist.findOne({
            $or: [
                { _id: dentistId },
                { id: dentistId },
                { user_id: dentistId },
                ...(docUser ? [{ user_id: docUser.id }, { user_id: docUser._id }] : [])
            ]
        }).catch(() => null);

        if (!docUser && docDentistRec && docDentistRec.user_id) {
            docUser = await User.findById(docDentistRec.user_id).catch(() => null);
        }

        const possibleIds = [
            dentistId,
            docUser ? docUser.id : null,
            docUser ? docUser._id : null,
            docUser ? docUser.email : null,
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
                realName = u.name || (u.email ? u.email.split('@')[0] : 'Patient');
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

// 9. ADMIN / SUB-ADMIN COORDINATOR: UPDATE 6-STAGE ESCALATION STATUS & LOG PHONE FOLLOW-UP
exports.updateCoordinatorStatus = async (req, res) => {
    const { id } = req.params;
    const { status, coordinatorId, coordinatorName, doctorId, followUpNote, notes } = req.body || {};
    try {
        const problemReq = await PatientProblemRequest.findById(id);
        if (!problemReq) {
            return res.status(404).json({ success: false, message: 'Assistance request not found.' });
        }

        const patientUserObj = problemReq.patient_id ? await User.findById(problemReq.patient_id).catch(() => null) : null;
        const patientLocPayload = buildRequestPatientLocationPayload(problemReq, patientUserObj);
        const locRes = District.resolvePatientDistrictStrict(patientLocPayload);
        const finalDistrictName = locRes.districtName || 'Unassigned / Review';
        const finalDistrictId = locRes.districtId || null;

        const callerCtx = await resolveCallerAccessContext(req);
        if (callerCtx.isSubAdmin) {
            const check = SubAdminDistrict.canSubAdminAccessPatientSync(callerCtx.assignedDistricts, patientLocPayload);
            if (!check.allowed) {
                return res.status(403).json({
                    success: false,
                    code: 'DISTRICT_ACCESS_DENIED',
                    message: `Access Denied: You cannot manage assistance requests in '${finalDistrictName}'.`
                });
            }
        }

        const nextStage = normalizeCoordinatorStage(status);
        const stageLabel = COORDINATOR_STAGE_LABELS[nextStage] || 'Submitted';
        const parsed = parseCoordinatorMeta(problemReq.admin_notes);
        const meta = {
            ...parsed.meta,
            coordinatorStatus: stageLabel,
            assignedCoordinatorId: coordinatorId || parsed.meta.assignedCoordinatorId || req.user?.id || null,
            assignedCoordinatorName: coordinatorName || parsed.meta.assignedCoordinatorName || req.user?.name || null,
            districtName: finalDistrictName,
            followUpNotes: Array.isArray(parsed.meta.followUpNotes) ? [...parsed.meta.followUpNotes] : [],
        };

        const noteText = String(followUpNote || notes || '').trim();
        if (noteText) {
            meta.followUpNotes.push({
                note: noteText,
                by: req.user?.name || coordinatorName || 'Coordinator',
                status: stageLabel,
                at: new Date().toISOString(),
            });
        }

        const updatePayload = {
            status: nextStage,
            admin_notes: serializeCoordinatorMeta(noteText || parsed.humanNote, meta),
        };
        if (doctorId) {
            updatePayload.suggested_dentist_id = doctorId;
        }

        const updatedReq = await PatientProblemRequest.findByIdAndUpdate(id, updatePayload);

        if (problemReq.patient_id) {
            await Notification.create({
                recipient_role: 'Patient',
                recipient_id: problemReq.patient_id,
                title: `Assistance Update: ${stageLabel}`,
                message: noteText
                    ? `Your consultation assistance status is now "${stageLabel}": ${noteText}`
                    : `Your consultation assistance request status has been updated to "${stageLabel}".`,
                type: 'coordinator_status_update'
            }).catch(() => {});
        }

        return res.json({
            success: true,
            message: `Coordinator status updated to ${stageLabel}.`,
            coordinatorStatus: stageLabel,
            coordinatorMeta: meta,
            request: updatedReq || { ...problemReq, ...updatePayload }
        });
    } catch (err) {
        console.error('Update Coordinator Status Error:', err.message);
        return res.status(500).json({ success: false, message: 'Failed to update coordinator status.' });
    }
};


