// =============================================================================
// GS HEALTH – PATIENT ASSIGNMENT & IMMUTABLE AUDIT TRAIL CONTROLLER
// Module: Patient-to-Doctor Assignment Workflow, Reassignment & Audit Trail
// =============================================================================

const {
    PatientAssignmentHistory,
    SubAdminDistrict,
    District,
    User,
    Dentist,
    PatientProblemRequest,
    Notification,
    ASSIGNMENT_SOURCES
} = require('../models/Schemas');
const { resolveCallerAccessContext } = require('../middleware/auth');

// Helper: Check if Sub-Admin is authorized for a district
async function isSubAdminAuthorizedForDistrict(subAdminId, districtId, districtName) {
    if (!districtId && !districtName) return false;
    const assignedDistricts = await SubAdminDistrict.getDistrictsForSubAdmin(subAdminId);
    if (!assignedDistricts || assignedDistricts.length === 0) return false;

    return assignedDistricts.some(d => {
        if (districtId && (d.id === districtId || d.id === `dist-${districtId}`)) return true;
        if (districtName && d.name.toLowerCase() === districtName.toLowerCase()) return true;
        return false;
    });
}

// 1. ASSIGN PATIENT TO DOCTOR (Main Admin or Authorized Sub-Admin)
exports.assignPatientToDoctor = async (req, res) => {
    try {
        const { patientId, doctorId, requestId, appointmentId, reason, districtId } = req.body;

        if (!patientId || !doctorId) {
            return res.status(400).json({
                success: false,
                message: 'Both patientId and doctorId are required for assignment.'
            });
        }

        // Validate Authenticated User Identity
        const user = req.user;
        if (!user) {
            return res.status(401).json({ success: false, message: 'Authentication required.' });
        }

        const roleLower = (user.role || '').toLowerCase();
        const isMainAdmin = roleLower === 'admin' || roleLower === 'primaryadmin' || roleLower === 'primary_admin' || roleLower === 'superadmin' || roleLower === 'super_admin';
        const isSubAdmin = roleLower === 'sub-admin' || roleLower === 'subadmin' || roleLower === 'sub_admin';

        if (!isMainAdmin && !isSubAdmin) {
            return res.status(403).json({
                success: false,
                message: 'Access Denied: Only Administrators or Coordinators can assign patients to doctors.'
            });
        }

        // Fetch target patient
        const patient = await User.findById(patientId);
        if (!patient) {
            return res.status(404).json({ success: false, message: 'Target patient record not found.' });
        }

        // Fetch target doctor
        let doctor = await Dentist.findById(doctorId).catch(() => null);
        if (!doctor) {
            doctor = await Dentist.findOne({ user_id: doctorId }).catch(() => null);
        }
        if (!doctor) {
            return res.status(404).json({ success: false, message: 'Target doctor record not found.' });
        }

        // Resolve District Strictly from Patient's Registered Location (never doctor/clinic district, never spoofed body districtId for Sub-Admins)
        const patientDistRes = District.resolvePatientDistrictStrict(patient);
        let resolvedDistrict = null;
        if (patientDistRes.districtId && patientDistRes.isVerified) {
            resolvedDistrict = await District.findById(patientDistRes.districtId);
        } else if (isMainAdmin && districtId) {
            resolvedDistrict = await District.findById(districtId);
        }

        const finalDistrictId = resolvedDistrict ? resolvedDistrict.id : null;
        const finalDistrictName = resolvedDistrict ? resolvedDistrict.name : 'Unassigned / Review';

        // Sub-Admin District-level Security Enforcement (Strict districtId match on the patient's own district)
        if (isSubAdmin) {
            const assignedDistricts = await SubAdminDistrict.getDistrictsForSubAdmin(user.id);
            const check = SubAdminDistrict.canSubAdminAccessPatientSync(assignedDistricts, patient);
            if (!check.allowed) {
                return res.status(403).json({
                    success: false,
                    code: 'DISTRICT_ACCESS_DENIED',
                    message: `Access Denied: You are not authorized to assign patients in '${finalDistrictName}'. This patient belongs to a district outside your assigned jurisdiction or has unverified district information.`
                });
            }
            if (districtId && String(districtId).trim().toLowerCase() !== String(check.patientDistrict.districtId).trim().toLowerCase()) {
                return res.status(403).json({
                    success: false,
                    code: 'DISTRICT_ACCESS_DENIED',
                    message: 'Access Denied: Provided districtId does not match the patient\'s verified district.'
                });
            }
        }

        // Determine Assignment Source & User Snapshot
        const assignmentSource = isMainAdmin
            ? ASSIGNMENT_SOURCES.MAIN_ADMIN_ASSIGNMENT
            : ASSIGNMENT_SOURCES.SUB_ADMIN_ASSIGNMENT;
        const assignedByRole = isMainAdmin ? 'MAIN_ADMIN' : 'SUB_ADMIN';
        const assignedByName = user.name || (isMainAdmin ? 'Main Admin' : 'Sub-Admin');

        // Record Immutable Audit History
        const auditRecord = await PatientAssignmentHistory.recordAssignment({
            patientId,
            doctorId: doctor.id,
            appointmentId: appointmentId || null,
            requestId: requestId || null,
            assignedByUserId: user.id,
            assignedByName,
            assignedByRole,
            assignmentSource,
            districtId: finalDistrictId,
            districtName: finalDistrictName,
            previousAssignmentId: null,
            assignmentReason: reason || 'Specialist patient consultation assignment.',
            status: 'ASSIGNED'
        });

        // Update Patient Problem Request status if applicable
        if (requestId) {
            await PatientProblemRequest.findByIdAndUpdate(requestId, {
                status: 'DENTIST_ASSIGNED',
                suggested_dentist_id: doctor.id,
                district_id: finalDistrictId,
                district: finalDistrictName,
                admin_notes: reason || `Assigned to ${doctor.name || 'Specialist'} by ${assignedByName}.`
            }).catch(() => null);
        }

        // Send In-App Notifications
        await Notification.create({
            recipient_role: 'Patient',
            recipient_id: patientId,
            title: '🩺 Doctor Assigned',
            message: `${assignedByName} has assigned Dr. ${doctor.name || 'Specialist'} for your consultation.`,
            type: 'dentist_assigned'
        }).catch(() => null);

        await Notification.create({
            recipient_role: 'Dentist',
            recipient_id: doctor.user_id || doctor.id,
            title: '📋 New Patient Assigned',
            message: `Patient ${patient.name || 'Patient'} from ${finalDistrictName} has been assigned to your consultation schedule by ${assignedByName}.`,
            type: 'patient_assigned'
        }).catch(() => null);

        res.json({
            success: true,
            message: `Patient successfully assigned to Dr. ${doctor.name || 'Specialist'}. Immutable audit log generated.`,
            assignment: auditRecord
        });
    } catch (err) {
        console.error('Assign Patient Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to assign patient to doctor.' });
    }
};

// 2. REASSIGN PATIENT TO NEW DOCTOR (Main Admin or Authorized Sub-Admin)
exports.reassignPatient = async (req, res) => {
    try {
        const { previousAssignmentId, patientId, newDoctorId, reason, districtId } = req.body;

        if (!patientId || !newDoctorId) {
            return res.status(400).json({
                success: false,
                message: 'patientId and newDoctorId are required for reassignment.'
            });
        }

        const user = req.user;
        if (!user) {
            return res.status(401).json({ success: false, message: 'Authentication required.' });
        }

        const roleLower = (user.role || '').toLowerCase();
        const isMainAdmin = roleLower === 'admin' || roleLower === 'primaryadmin' || roleLower === 'primary_admin' || roleLower === 'superadmin' || roleLower === 'super_admin';
        const isSubAdmin = roleLower === 'sub-admin' || roleLower === 'subadmin' || roleLower === 'sub_admin';

        if (!isMainAdmin && !isSubAdmin) {
            return res.status(403).json({
                success: false,
                message: 'Access Denied: Only Administrators or Coordinators can reassign patients.'
            });
        }

        // Fetch patient
        const patient = await User.findById(patientId);
        if (!patient) {
            return res.status(404).json({ success: false, message: 'Patient not found.' });
        }

        // Fetch new doctor
        let newDoctor = await Dentist.findById(newDoctorId).catch(() => null);
        if (!newDoctor) {
            newDoctor = await Dentist.findOne({ user_id: newDoctorId }).catch(() => null);
        }
        if (!newDoctor) {
            return res.status(404).json({ success: false, message: 'New doctor record not found.' });
        }

        // Resolve District Strictly from Patient's Registered Location
        const patientDistRes = District.resolvePatientDistrictStrict(patient);
        let resolvedDistrict = null;
        if (patientDistRes.districtId && patientDistRes.isVerified) {
            resolvedDistrict = await District.findById(patientDistRes.districtId);
        } else if (isMainAdmin && districtId) {
            resolvedDistrict = await District.findById(districtId);
        }

        const finalDistrictId = resolvedDistrict ? resolvedDistrict.id : null;
        const finalDistrictName = resolvedDistrict ? resolvedDistrict.name : 'Unassigned / Review';

        // Sub-Admin District-level Security Enforcement
        if (isSubAdmin) {
            const assignedDistricts = await SubAdminDistrict.getDistrictsForSubAdmin(user.id);
            const check = SubAdminDistrict.canSubAdminAccessPatientSync(assignedDistricts, patient);
            if (!check.allowed) {
                return res.status(403).json({
                    success: false,
                    code: 'DISTRICT_ACCESS_DENIED',
                    message: `Access Denied: You are not authorized to reassign patients in '${finalDistrictName}'.`
                });
            }
        }

        const assignmentSource = isMainAdmin
            ? ASSIGNMENT_SOURCES.MAIN_ADMIN_ASSIGNMENT
            : ASSIGNMENT_SOURCES.SUB_ADMIN_ASSIGNMENT;
        const assignedByRole = isMainAdmin ? 'MAIN_ADMIN' : 'SUB_ADMIN';
        const assignedByName = user.name || (isMainAdmin ? 'Main Admin' : 'Sub-Admin');

        // APPEND-ONLY: Create NEW history record referencing the previous assignment
        const newAuditRecord = await PatientAssignmentHistory.recordAssignment({
            patientId,
            doctorId: newDoctor.id,
            appointmentId: null,
            requestId: null,
            assignedByUserId: user.id,
            assignedByName,
            assignedByRole,
            assignmentSource,
            districtId: finalDistrictId,
            districtName: finalDistrictName,
            previousAssignmentId: previousAssignmentId || null,
            assignmentReason: reason || 'Patient consultation reassignment to another specialist.',
            status: 'REASSIGNED'
        });

        // Notifications
        await Notification.create({
            recipient_role: 'Patient',
            recipient_id: patientId,
            title: '🔄 Consultation Reassigned',
            message: `Your consultation has been reassigned to Dr. ${newDoctor.name || 'Specialist'} by ${assignedByName}.`,
            type: 'dentist_reassigned'
        }).catch(() => null);

        res.json({
            success: true,
            message: `Patient successfully reassigned to Dr. ${newDoctor.name || 'Specialist'}. New immutable audit record created.`,
            assignment: newAuditRecord
        });
    } catch (err) {
        console.error('Reassign Patient Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to reassign patient.' });
    }
};

// 3. GET ASSIGNMENT AUDIT HISTORY WITH FILTERS
exports.getAssignmentHistory = async (req, res) => {
    try {
        const {
            patientId,
            doctorId,
            districtId,
            assignedByUserId,
            assignedByRole,
            assignmentSource,
            status,
            search
        } = req.query;

        const callerCtx = await resolveCallerAccessContext(req);
        const isSubAdmin = callerCtx.isSubAdmin;

        if (isSubAdmin && districtId && String(districtId).toLowerCase() !== 'all') {
            if (!callerCtx.assignedDistrictIds.has(String(districtId).trim().toLowerCase())) {
                return res.status(403).json({
                    success: false,
                    code: 'DISTRICT_ACCESS_DENIED',
                    message: 'Access Denied: You cannot view assignment history outside your assigned district.'
                });
            }
        }

        if (isSubAdmin && patientId) {
            const targetPatient = await User.findById(patientId).catch(() => null);
            const check = SubAdminDistrict.canSubAdminAccessPatientSync(callerCtx.assignedDistricts, targetPatient);
            if (!targetPatient || !check.allowed) {
                return res.status(403).json({
                    success: false,
                    code: 'DISTRICT_ACCESS_DENIED',
                    message: 'Access Denied: You cannot view assignment history for a patient outside your assigned district.'
                });
            }
        }

        let history = await PatientAssignmentHistory.getHistory({
            patientId,
            doctorId,
            districtId,
            assignedByUserId,
            assignedByRole,
            assignmentSource,
            status,
            search
        });

        // If Sub-Admin, strictly filter to patients in their assigned districts by districtId
        if (isSubAdmin) {
            const allPatients = await User.find({ role: 'Patient' });
            const patientMap = new Map(allPatients.map(p => [String(p.id), p]));

            history = history.filter(h => {
                const p = h.patient_id ? patientMap.get(String(h.patient_id)) : null;
                if (p) {
                    return SubAdminDistrict.canSubAdminAccessPatientSync(callerCtx.assignedDistricts, p).allowed;
                }
                if (h.district_id && callerCtx.assignedDistrictIds.has(String(h.district_id).trim().toLowerCase())) {
                    return true;
                }
                return false;
            });
        }

        res.json({
            success: true,
            count: history.length,
            history
        });
    } catch (err) {
        console.error('Get Assignment History Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to retrieve assignment history.' });
    }
};

// 4. GET PATIENT CHRONOLOGICAL ASSIGNMENT TIMELINE
exports.getPatientTimeline = async (req, res) => {
    try {
        const { patientId } = req.params;
        const callerCtx = await resolveCallerAccessContext(req);

        if (callerCtx.isSubAdmin) {
            const targetPatient = await User.findById(patientId).catch(() => null);
            if (!targetPatient) {
                return res.status(404).json({ success: false, message: 'Patient record not found.' });
            }
            const check = SubAdminDistrict.canSubAdminAccessPatientSync(callerCtx.assignedDistricts, targetPatient);
            if (!check.allowed) {
                return res.status(403).json({
                    success: false,
                    code: 'DISTRICT_ACCESS_DENIED',
                    message: 'Access Denied: You cannot view assignment timeline for a patient outside your assigned district.'
                });
            }
        }

        const history = await PatientAssignmentHistory.getHistoryForPatient(patientId);

        // Enhance history with doctor and patient details
        const enrichedTimeline = [];
        for (const item of history) {
            const doctor = await Dentist.findById(item.doctor_id).catch(() => null);
            enrichedTimeline.push({
                ...item,
                doctor_name: doctor ? (doctor.name || doctor.users?.name || 'Dr. Specialist') : 'Dr. Specialist',
                doctor_specialty: doctor ? (doctor.speciality || 'General Medicine') : 'Specialist'
            });
        }

        res.json({
            success: true,
            patientId,
            count: enrichedTimeline.length,
            timeline: enrichedTimeline
        });
    } catch (err) {
        console.error('Get Patient Timeline Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to retrieve patient assignment timeline.' });
    }
};

// 5. GET DYNAMIC DASHBOARD METRICS & STATISTICS (Main Admin & District-Scoped Sub-Admin)
exports.getAssignmentStatistics = async (req, res) => {
    try {
        const callerCtx = await resolveCallerAccessContext(req);
        const allUsers = await User.find({});
        const allDistricts = await District.find({});
        const problemRequests = await PatientProblemRequest.find({});

        if (callerCtx.isSubAdmin) {
            const allPatients = allUsers.filter(u => String(u.role || 'Patient').toLowerCase() === 'patient');
            const allowedPatients = allPatients.filter(p =>
                SubAdminDistrict.canSubAdminAccessPatientSync(callerCtx.assignedDistricts, p).allowed
            );
            const allowedPatientIds = new Set(allowedPatients.map(p => String(p.id)));
            const patientMap = new Map(allPatients.map(p => [String(p.id), p]));

            const allHistory = await PatientAssignmentHistory.getHistory();
            const scopedHistory = allHistory.filter(h => {
                if (h.patient_id && allowedPatientIds.has(String(h.patient_id))) return true;
                const p = h.patient_id ? patientMap.get(String(h.patient_id)) : null;
                if (p) return false;
                return Boolean(h.district_id && callerCtx.assignedDistrictIds.has(String(h.district_id).trim().toLowerCase()));
            });

            const scopedProblemRequests = problemRequests.filter(r => {
                const p = r.patient_id ? patientMap.get(String(r.patient_id)) : null;
                const locPayload = {
                    districtId: p?.district_id || p?.districtId || r.district_id || null,
                    district: p?.district || r.district || null,
                    city: p?.city || r.city || '',
                    state: p?.state || r.state || '',
                    pincode: p?.pincode || r.pincode || '',
                    device_token: p?.device_token || null
                };
                return SubAdminDistrict.canSubAdminAccessPatientSync(callerCtx.assignedDistricts, locPayload).allowed;
            });

            const pendingDoctorAssignments = scopedProblemRequests.filter(r =>
                r.status === 'PENDING_ADMIN_REVIEW' || r.status === 'PENDING' || r.status === 'SUBMITTED'
            ).length;
            const assignedPatientSet = new Set(scopedHistory.map(h => String(h.patient_id || '')).filter(Boolean));

            return res.json({
                success: true,
                statistics: {
                    totalPatients: allowedPatients.length,
                    totalSubAdmins: 1,
                    activeSubAdmins: 1,
                    totalDistricts: callerCtx.assignedDistricts.length,
                    totalAssignedPatients: assignedPatientSet.size,
                    directPatientBookings: scopedHistory.filter(a => a.assignment_source === ASSIGNMENT_SOURCES.PATIENT_DIRECT_BOOKING).length,
                    adminAssignments: scopedHistory.filter(a => a.assignment_source === ASSIGNMENT_SOURCES.MAIN_ADMIN_ASSIGNMENT).length,
                    subAdminAssignments: scopedHistory.filter(a => a.assignment_source === ASSIGNMENT_SOURCES.SUB_ADMIN_ASSIGNMENT).length,
                    pendingDoctorAssignments,
                    totalRequests: scopedProblemRequests.length,
                    totalAssignments: scopedHistory.length
                }
            });
        }

        const stats = await PatientAssignmentHistory.getStatistics();
        const allPatients = allUsers.filter(u => String(u.role || 'Patient').toLowerCase() === 'patient');
        const subAdmins = allUsers.filter(u => {
            const r = (u.role || '').toLowerCase();
            return r === 'sub-admin' || r === 'subadmin' || r === 'sub_admin';
        });
        const activeSubAdmins = subAdmins.filter(s => (s.status || 'ACTIVE').toUpperCase() === 'ACTIVE');

        // Count pending doctor problem requests
        const pendingDoctorAssignments = problemRequests.filter(r => r.status === 'PENDING_ADMIN_REVIEW' || r.status === 'PENDING' || r.status === 'SUBMITTED').length;

        res.json({
            success: true,
            statistics: {
                totalPatients: allPatients.length,
                totalSubAdmins: subAdmins.length,
                activeSubAdmins: activeSubAdmins.length,
                totalDistricts: allDistricts.length,
                totalAssignedPatients: stats.totalAssignedPatients,
                directPatientBookings: stats.directBookings,
                adminAssignments: stats.adminAssignments,
                subAdminAssignments: stats.subAdminAssignments,
                pendingDoctorAssignments,
                totalRequests: problemRequests.length,
                totalAssignments: stats.totalAssignments
            }
        });
    } catch (err) {
        console.error('Get Assignment Statistics Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to retrieve assignment statistics.' });
    }
};

// 6. GET DISTRICT-WISE COMPREHENSIVE REPORTS (District-Scoped for Sub-Admin)
exports.getDistrictReports = async (req, res) => {
    try {
        const callerCtx = await resolveCallerAccessContext(req);
        let districts = await District.find({});
        if (callerCtx.isSubAdmin) {
            districts = districts.filter(d => callerCtx.assignedDistrictIds.has(String(d.id).trim().toLowerCase()));
        }

        const allUsers = await User.find({});
        const allDoctors = await Dentist.find({});
        const allHistory = await PatientAssignmentHistory.getHistory();

        const reports = [];
        for (const dist of districts) {
            const dName = dist.name.toLowerCase();
            const dId = dist.id;
            const dIdLower = String(dId).toLowerCase();

            // Sub-admins in district
            const subAdminIds = await SubAdminDistrict.getSubAdminsForDistrict(dId);

            // Patients belonging strictly to this district by resolved districtId
            const districtPatients = allUsers.filter(u => {
                if (u.role && u.role.toLowerCase() !== 'patient') return false;
                const resolved = District.resolvePatientDistrictStrict(u);
                return Boolean(resolved.isVerified && resolved.districtId && String(resolved.districtId).toLowerCase() === dIdLower);
            });

            // Doctors practicing in this district
            const districtDoctors = allDoctors.filter(d => {
                const resolved = District.resolveDistrictFromLocation({
                    districtId: d.district_id,
                    district: d.district,
                    city: d.city,
                    state: d.state,
                    pincode: d.pincode
                });
                return Boolean(resolved.isVerified && resolved.districtId && String(resolved.districtId).toLowerCase() === dIdLower);
            });

            // Assignments in this district
            const districtAssignments = allHistory.filter(h => {
                if (h.district_id && String(h.district_id).toLowerCase() === dIdLower) return true;
                if (h.district_name && h.district_name.toLowerCase() === dName) return true;
                return false;
            });

            reports.push({
                district_id: dId,
                district_name: dist.name,
                state: dist.state,
                is_active: dist.is_active,
                total_patients: districtPatients.length,
                total_doctors: districtDoctors.length,
                total_sub_admins: subAdminIds.length,
                total_assignments: districtAssignments.length,
                direct_bookings: districtAssignments.filter(a => a.assignment_source === ASSIGNMENT_SOURCES.PATIENT_DIRECT_BOOKING).length,
                admin_assignments: districtAssignments.filter(a => a.assignment_source === ASSIGNMENT_SOURCES.MAIN_ADMIN_ASSIGNMENT).length,
                sub_admin_assignments: districtAssignments.filter(a => a.assignment_source === ASSIGNMENT_SOURCES.SUB_ADMIN_ASSIGNMENT).length
            });
        }

        res.json({
            success: true,
            count: reports.length,
            reports
        });
    } catch (err) {
        console.error('Get District Reports Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to retrieve district reports.' });
    }
};
