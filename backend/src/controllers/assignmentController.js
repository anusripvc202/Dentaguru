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
                message: 'Access Denied: Only Administrators or Sub-Administrators can assign patients to doctors.'
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

        // Resolve District for Patient
        let resolvedDistrict = null;
        if (districtId) {
            resolvedDistrict = await District.findById(districtId);
        }
        if (!resolvedDistrict) {
            const locRes = District.resolveDistrictFromLocation({
                city: patient.city,
                district: patient.district,
                state: patient.state,
                pincode: patient.pincode
            });
            if (locRes.districtId) {
                resolvedDistrict = await District.findById(locRes.districtId);
            }
        }

        const finalDistrictId = resolvedDistrict ? resolvedDistrict.id : (districtId || null);
        const finalDistrictName = resolvedDistrict ? resolvedDistrict.name : (patient.district || patient.city || 'Unassigned / Review');

        // Sub-Admin District-level Security Enforcement
        if (isSubAdmin) {
            const isAuthorized = await isSubAdminAuthorizedForDistrict(user.id, finalDistrictId, finalDistrictName);
            if (!isAuthorized) {
                return res.status(403).json({
                    success: false,
                    message: `Access Denied: You are not authorized to assign patients in '${finalDistrictName}'. This patient belongs to a district outside your assigned jurisdiction.`
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
                message: 'Access Denied: Only Administrators or Sub-Administrators can reassign patients.'
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

        // Resolve District
        let resolvedDistrict = null;
        if (districtId) {
            resolvedDistrict = await District.findById(districtId);
        }
        if (!resolvedDistrict) {
            const locRes = District.resolveDistrictFromLocation({
                city: patient.city,
                district: patient.district,
                state: patient.state,
                pincode: patient.pincode
            });
            if (locRes.districtId) {
                resolvedDistrict = await District.findById(locRes.districtId);
            }
        }

        const finalDistrictId = resolvedDistrict ? resolvedDistrict.id : (districtId || null);
        const finalDistrictName = resolvedDistrict ? resolvedDistrict.name : (patient.district || patient.city || 'Unassigned / Review');

        // Sub-Admin District-level Security Enforcement
        if (isSubAdmin) {
            const isAuthorized = await isSubAdminAuthorizedForDistrict(user.id, finalDistrictId, finalDistrictName);
            if (!isAuthorized) {
                return res.status(403).json({
                    success: false,
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

        const user = req.user;
        const roleLower = user ? (user.role || '').toLowerCase() : '';
        const isMainAdmin = roleLower === 'admin' || roleLower === 'primaryadmin' || roleLower === 'primary_admin' || roleLower === 'superadmin' || roleLower === 'super_admin';
        const isSubAdmin = roleLower === 'sub-admin' || roleLower === 'subadmin' || roleLower === 'sub_admin';

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

        // If Sub-Admin, strictly filter to their assigned districts only
        if (isSubAdmin && user.id) {
            const assignedDistricts = await SubAdminDistrict.getDistrictsForSubAdmin(user.id);
            const authorizedDistrictIds = new Set(assignedDistricts.map(d => d.id));
            const authorizedDistrictNames = new Set(assignedDistricts.map(d => d.name.toLowerCase()));

            history = history.filter(h => {
                if (h.district_id && authorizedDistrictIds.has(h.district_id)) return true;
                if (h.district_name && authorizedDistrictNames.has(h.district_name.toLowerCase())) return true;
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

// 5. GET DYNAMIC DASHBOARD METRICS & STATISTICS (Main Admin & Sub-Admin)
exports.getAssignmentStatistics = async (req, res) => {
    try {
        const stats = await PatientAssignmentHistory.getStatistics();
        const allUsers = await User.find({});
        const allDistricts = await District.find({});

        const subAdmins = allUsers.filter(u => {
            const r = (u.role || '').toLowerCase();
            return r === 'sub-admin' || r === 'subadmin' || r === 'sub_admin';
        });
        const activeSubAdmins = subAdmins.filter(s => (s.status || 'ACTIVE').toUpperCase() === 'ACTIVE');

        // Count pending doctor problem requests
        const problemRequests = await PatientProblemRequest.find({});
        const pendingDoctorAssignments = problemRequests.filter(r => r.status === 'PENDING_ADMIN_REVIEW' || r.status === 'PENDING').length;

        res.json({
            success: true,
            statistics: {
                totalSubAdmins: subAdmins.length,
                activeSubAdmins: activeSubAdmins.length,
                totalDistricts: allDistricts.length,
                totalAssignedPatients: stats.totalAssignedPatients,
                directPatientBookings: stats.directBookings,
                adminAssignments: stats.adminAssignments,
                subAdminAssignments: stats.subAdminAssignments,
                pendingDoctorAssignments,
                totalAssignments: stats.totalAssignments
            }
        });
    } catch (err) {
        console.error('Get Assignment Statistics Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to retrieve assignment statistics.' });
    }
};

// 6. GET DISTRICT-WISE COMPREHENSIVE REPORTS
exports.getDistrictReports = async (req, res) => {
    try {
        const districts = await District.find({});
        const allUsers = await User.find({});
        const allDoctors = await Dentist.find({});
        const allHistory = await PatientAssignmentHistory.getHistory();

        const reports = [];
        for (const dist of districts) {
            const dName = dist.name.toLowerCase();
            const dId = dist.id;

            // Sub-admins in district
            const subAdminIds = await SubAdminDistrict.getSubAdminsForDistrict(dId);

            // Patients belonging to this district
            const districtPatients = allUsers.filter(u => {
                if (u.role && u.role.toLowerCase() !== 'patient') return false;
                if (u.district_id === dId) return true;
                if (u.district && u.district.toLowerCase() === dName) return true;
                if (u.city && u.city.toLowerCase() === dName) return true;
                return false;
            });

            // Doctors practicing in this district
            const districtDoctors = allDoctors.filter(d => {
                if (d.district_id === dId) return true;
                if (d.district && d.district.toLowerCase() === dName) return true;
                if (d.city && d.city.toLowerCase() === dName) return true;
                return false;
            });

            // Assignments in this district
            const districtAssignments = allHistory.filter(h => {
                if (h.district_id === dId) return true;
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
