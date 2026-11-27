const {
    User,
    Dentist,
    MedicalRecord,
    Notification,
    SubAdminDistrict,
    resolveUserUuid,
    resolveDentistIds
} = require('../models/Schemas');
const supabaseStorageService = require('../services/supabaseStorageService');
const { resolveCallerAccessContext } = require('../middleware/auth');

const ALLOWED_CATEGORIES = [
    'Dental X-ray',
    'Prescription',
    'Dental Report',
    'Lab Report',
    'Treatment Documents',
    'Other'
];

const ALLOWED_EXTENSIONS = ['jpg', 'jpeg', 'png', 'pdf'];
const ALLOWED_MIME_TYPES = [
    'image/jpeg',
    'image/jpg',
    'image/png',
    'application/pdf'
];
const MAX_FILE_SIZE_BYTES = 20 * 1024 * 1024; // 20 MB

function parseRecordNotes(r) {
    if (!r || !r.notes) return {};
    if (typeof r.notes === 'object') return r.notes;
    try {
        return JSON.parse(r.notes);
    } catch (_) {
        return {};
    }
}

function formatRecord(r) {
    const parsedNotes = parseRecordNotes(r);
    const patientObj = r.patient && typeof r.patient === 'object' ? r.patient : {};
    const storageKey = parsedNotes.storageKey ||
        (Array.isArray(r.xray_urls) && r.xray_urls.length > 0 ? r.xray_urls[0] : '') ||
        (Array.isArray(r.lab_report_urls) && r.lab_report_urls.length > 0 ? r.lab_report_urls[0] : '');

    const category = parsedNotes.category ||
        (parsedNotes.type === 'xray'
            ? 'Dental X-ray'
            : parsedNotes.type === 'prescription'
                ? 'Prescription'
                : 'Other');

    const title = parsedNotes.title || r.diagnosis || 'Medical Health Record';
    const description = parsedNotes.description !== undefined
        ? parsedNotes.description
        : (parsedNotes.subtitle || '');

    return {
        id: r.id,
        patientId: r.patient_id,
        patientName: parsedNotes.patientName || patientObj.name || '',
        dentistId: r.dentist_id || parsedNotes.dentistId || null,
        appointmentId: r.appointment_id || parsedNotes.appointmentId || null,
        recordSource: parsedNotes.recordSource || (parsedNotes.fileName ? 'patient_upload' : 'doctor_issued'),
        type: parsedNotes.type || (category === 'Dental X-ray' ? 'xray' : category === 'Prescription' ? 'prescription' : 'document'),
        title,
        category,
        specialty: parsedNotes.specialty || '',
        department: parsedNotes.department || '',
        diagnosis: parsedNotes.diagnosis || r.diagnosis || title,
        symptoms: parsedNotes.symptoms || '',
        clinicalSections: parsedNotes.clinicalSections && typeof parsedNotes.clinicalSections === 'object' ? parsedNotes.clinicalSections : {},
        followUpDate: parsedNotes.followUpDate || '',
        instructions: parsedNotes.instructions || '',
        approvedByDoctor: parsedNotes.approvedByDoctor === true,
        doctorQualification: parsedNotes.doctorQualification || '',
        description,
        subtitle: parsedNotes.subtitle || description || category,
        doctorName: parsedNotes.doctorName || parsedNotes.doctor_name || '',
        clinicName: parsedNotes.clinicName || parsedNotes.clinic_name || '',
        fileName: parsedNotes.fileName || '',
        fileType: (parsedNotes.fileType || '').toString().toUpperCase(),
        mimeType: parsedNotes.mimeType || '',
        fileSize: Number(parsedNotes.fileSize || 0),
        storageKey,
        storageProvider: parsedNotes.storageProvider || 'supabase',
        sharedWith: Array.isArray(parsedNotes.sharedWith) ? parsedNotes.sharedWith : [],
        date: parsedNotes.uploadedAt || r.created_at,
        uploadedAt: parsedNotes.uploadedAt || r.created_at,
        updatedAt: parsedNotes.updatedAt || r.updated_at || r.created_at,
        items: Array.isArray(r.prescriptions) ? r.prescriptions : []
    };
}

function isDoctorAuthorizedForRecord(formattedRecord, doctorIdentifiersSet) {
    if (!formattedRecord || !doctorIdentifiersSet || doctorIdentifiersSet.size === 0) return false;
    const sharedWith = Array.isArray(formattedRecord.sharedWith) ? formattedRecord.sharedWith : [];
    for (const share of sharedWith) {
        if (!share) continue;
        const dId = String(share.doctorId || '').trim().toLowerCase();
        const dUserId = String(share.doctorUserId || '').trim().toLowerCase();
        const dEmail = String(share.doctorEmail || '').trim().toLowerCase();
        if ((dId && doctorIdentifiersSet.has(dId)) ||
            (dUserId && doctorIdentifiersSet.has(dUserId)) ||
            (dEmail && doctorIdentifiersSet.has(dEmail))) {
            return true;
        }
    }
    return false;
}

async function buildDoctorIdentifierSet(rawDoctorId, reqUser) {
    const ids = new Set();
    const candidates = [
        rawDoctorId,
        reqUser?.id,
        reqUser?.email
    ].filter(Boolean);

    for (const c of candidates) {
        const clean = String(c).trim();
        if (!clean) continue;
        ids.add(clean.toLowerCase());
        try {
            const resolved = await resolveDentistIds(clean);
            if (resolved.dentistTableId) ids.add(String(resolved.dentistTableId).toLowerCase());
            if (resolved.userTableId) ids.add(String(resolved.userTableId).toLowerCase());
            for (const item of (resolved.allIds || [])) {
                if (item) ids.add(String(item).toLowerCase());
            }
        } catch (_) {}
        try {
            const d = await Dentist.findById(clean);
            if (d) {
                if (d.id) ids.add(String(d.id).toLowerCase());
                if (d.user_id) ids.add(String(d.user_id).toLowerCase());
                if (d.users?.email) ids.add(String(d.users.email).toLowerCase());
            }
        } catch (_) {}
    }
    return ids;
}

// 1. GET ALL RECORDS FOR A PATIENT (OR SHARED WITH DOCTOR)
exports.getPatientRecords = async (req, res) => {
    const { patientId, doctorId } = req.query;
    try {
        const callerRole = String(req.user?.role || req.headers['x-user-role'] || '').trim().toLowerCase();
        const callerId = req.user?.id || req.headers['x-user-id'] || null;

        // If a doctor is querying records, enforce doctor-level filtering
        if (doctorId || callerRole === 'dentist' || callerRole === 'doctor') {
            const docIdSet = await buildDoctorIdentifierSet(doctorId || callerId, req.user);
            let query = {};
            if (patientId) {
                query.patient_id = patientId;
            }
            const records = await MedicalRecord.find(query);
            const formatted = records.map(formatRecord).filter(rec => {
                // Allow doctor's own issued prescriptions OR patient records explicitly shared with this doctor
                if (rec.recordSource === 'doctor_issued' && rec.dentistId && docIdSet.has(String(rec.dentistId).toLowerCase())) {
                    return true;
                }
                return isDoctorAuthorizedForRecord(rec, docIdSet);
            });

            return res.json({
                success: true,
                count: formatted.length,
                records: formatted
            });
        }

        // Patient ownership check
        const targetId = patientId || callerId;
        if (!targetId) {
            return res.status(400).json({
                success: false,
                message: 'patientId is required to fetch health records.'
            });
        }

        const resolvedTargetUuid = await resolveUserUuid(targetId);
        if (callerRole === 'patient' && callerId) {
            const resolvedCallerUuid = await resolveUserUuid(callerId);
            if (resolvedCallerUuid && resolvedTargetUuid && resolvedCallerUuid !== resolvedTargetUuid) {
                return res.status(403).json({
                    success: false,
                    message: 'Access Denied: You can only view your own health records.'
                });
            }
        }

        // Strict Sub-Admin District Access Check for Patient Health Records
        const callerCtx = await resolveCallerAccessContext(req);
        if (callerCtx.isSubAdmin) {
            const targetPatient = await User.findById(resolvedTargetUuid || targetId).catch(() => null);
            if (!targetPatient) {
                return res.status(404).json({
                    success: false,
                    message: 'Patient record not found.'
                });
            }
            const check = SubAdminDistrict.canSubAdminAccessPatientSync(callerCtx.assignedDistricts, targetPatient);
            if (!check.allowed) {
                return res.status(403).json({
                    success: false,
                    code: 'DISTRICT_ACCESS_DENIED',
                    message: 'Access Denied: You cannot access medical records for patients outside your assigned district.'
                });
            }
        }

        const records = await MedicalRecord.find({ patient_id: resolvedTargetUuid || targetId });
        const formatted = records.map(formatRecord);

        res.json({
            success: true,
            count: formatted.length,
            records: formatted
        });
    } catch (err) {
        console.error('Get Medical Records Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to fetch medical records.' });
    }
};

// 2. GET RECORDS EXPLICITLY SHARED WITH A DOCTOR
exports.getSharedRecordsForDoctor = async (req, res) => {
    const rawDoctorId = req.query.doctorId || req.headers['x-doctor-id'] || req.user?.id;
    const { patientId } = req.query;

    if (!rawDoctorId) {
        return res.status(400).json({
            success: false,
            message: 'doctorId is required to fetch shared patient records.'
        });
    }

    try {
        const docIdSet = await buildDoctorIdentifierSet(rawDoctorId, req.user);
        if (docIdSet.size === 0) {
            return res.status(403).json({
                success: false,
                message: 'Access Denied: Unable to verify doctor identity.'
            });
        }

        const query = {};
        if (patientId) {
            query.patient_id = patientId;
        }

        const allRecords = await MedicalRecord.find(query);
        const sharedRecords = allRecords
            .map(formatRecord)
            .filter(rec => isDoctorAuthorizedForRecord(rec, docIdSet));

        return res.json({
            success: true,
            count: sharedRecords.length,
            records: sharedRecords
        });
    } catch (err) {
        console.error('Get Shared Records For Doctor Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to fetch shared records for doctor.' });
    }
};

// 3. CREATE NEW MULTI-SPECIALTY MEDICAL HEALTH RECORD OR E-PRESCRIPTION
exports.createRecord = async (req, res) => {
    const {
        patientId,
        patientName,
        dentistId,
        doctorId,
        appointmentId,
        specialty,
        speciality,
        department,
        diagnosis,
        symptoms,
        clinicalSections,
        followUpDate,
        instructions,
        doctorQualification,
        approvedByDoctor,
        type,
        recordSource,
        title,
        category,
        description,
        subtitle,
        doctorName,
        clinicName,
        fileName,
        fileType,
        mimeType,
        fileSize,
        storageKey,
        storageProvider,
        items
    } = req.body;

    try {
        const effectivePatientId = patientId || req.user?.id;
        if (!effectivePatientId) {
            return res.status(400).json({
                success: false,
                message: 'patientId is required to create a health record.'
            });
        }

        const resolvedPatientUuid = await resolveUserUuid(effectivePatientId);
        if (!resolvedPatientUuid) {
            return res.status(404).json({
                success: false,
                message: 'Patient account not found in database.'
            });
        }

        // Enforce patient ownership if called by a logged-in patient
        if (req.user && String(req.user.role || '').toLowerCase() === 'patient') {
            const resolvedCallerUuid = await resolveUserUuid(req.user.id);
            if (resolvedCallerUuid && resolvedCallerUuid !== resolvedPatientUuid) {
                return res.status(403).json({
                    success: false,
                    message: 'Access Denied: You can only upload records to your own profile.'
                });
            }
        }

        const isDoctorIssuedPrescription = recordSource === 'doctor_issued' || (type === 'prescription' && !fileName && !storageKey);
        const isPatientUpload = !isDoctorIssuedPrescription && (recordSource === 'patient_upload' || Boolean(fileName || storageKey || category));
        const cleanTitle = String(title || diagnosis || '').trim();
        if (!cleanTitle) {
            return res.status(400).json({
                success: false,
                message: 'Record Name or Diagnosis is required.'
            });
        }

        let effectiveCategory = category || (type === 'prescription' ? 'Prescription' : 'Other');
        if (isPatientUpload && !ALLOWED_CATEGORIES.includes(effectiveCategory)) {
            return res.status(400).json({
                success: false,
                message: `Invalid record category. Allowed categories: ${ALLOWED_CATEGORIES.join(', ')}`
            });
        }

        // Validate file metadata on backend for patient uploads
        let normalizedExt = String(fileType || '').trim().toLowerCase().replace(/^\./, '');
        if (!normalizedExt && fileName && String(fileName).includes('.')) {
            normalizedExt = String(fileName).split('.').pop().trim().toLowerCase();
        }

        if (isPatientUpload) {
            if (!normalizedExt || !ALLOWED_EXTENSIONS.includes(normalizedExt)) {
                return res.status(400).json({
                    success: false,
                    message: `Unsupported file format '${normalizedExt || 'unknown'}'. Allowed formats: JPG, JPEG, PNG, PDF.`
                });
            }
            if (mimeType && !ALLOWED_MIME_TYPES.includes(String(mimeType).trim().toLowerCase())) {
                return res.status(400).json({
                    success: false,
                    message: `Unsupported MIME type '${mimeType}'. Allowed: image/jpeg, image/png, application/pdf.`
                });
            }
            const numericSize = Number(fileSize || 0);
            if (numericSize <= 0 || numericSize > MAX_FILE_SIZE_BYTES) {
                return res.status(400).json({
                    success: false,
                    message: numericSize <= 0
                        ? 'Uploaded file cannot be empty.'
                        : 'File size exceeds maximum limit of 20 MB.'
                });
            }
            if (!storageKey || String(storageKey).trim().length === 0) {
                return res.status(400).json({
                    success: false,
                    message: 'A secure storage reference key is required.'
                });
            }
        }

        let resolvedPatientName = patientName || '';
        if (!resolvedPatientName) {
            const pUser = await User.findById(resolvedPatientUuid);
            if (pUser && pUser.name) resolvedPatientName = pUser.name;
        }

        // Dynamically resolve doctor's dentist_id & specialization when issuing clinical prescriptions
        const rawDocId = dentistId || doctorId || ((req.user && ['dentist', 'doctor'].includes(String(req.user.role || '').toLowerCase())) ? req.user.id : null);
        let resolvedDentistUuid = null;
        let resolvedSpecialty = String(specialty || speciality || '').trim();
        let resolvedDepartment = String(department || '').trim();
        let resolvedDoctorName = doctorName || '';
        let resolvedDoctorQualification = doctorQualification || '';

        if (rawDocId) {
            try {
                const resolvedDocIds = await resolveDentistIds(rawDocId);
                resolvedDentistUuid = resolvedDocIds.dentistTableId || null;
                const docRow = await Dentist.findById(resolvedDentistUuid || rawDocId);
                if (docRow) {
                    if (!resolvedDentistUuid && docRow.id) resolvedDentistUuid = docRow.id;
                    if (!resolvedSpecialty) resolvedSpecialty = String(docRow.speciality || docRow.specialty || '').trim();
                    if (!resolvedDepartment) resolvedDepartment = String(docRow.department || '').trim();
                    if (!resolvedDoctorName) resolvedDoctorName = docRow.users?.name || docRow.name || '';
                    if (!resolvedDoctorQualification) resolvedDoctorQualification = docRow.qualifications || docRow.qualification || '';
                }
            } catch (_) {}
        }

        const cleanSections = (clinicalSections && typeof clinicalSections === 'object' && !Array.isArray(clinicalSections))
            ? clinicalSections
            : {};

        const nowIso = new Date().toISOString();
        const notesMeta = {
            recordSource: isPatientUpload ? 'patient_upload' : 'doctor_issued',
            type: type || (effectiveCategory === 'Dental X-ray' ? 'xray' : effectiveCategory === 'Prescription' ? 'prescription' : 'document'),
            title: cleanTitle,
            category: effectiveCategory,
            dentistId: resolvedDentistUuid || rawDocId || '',
            appointmentId: appointmentId ? String(appointmentId).trim() : '',
            specialty: resolvedSpecialty,
            department: resolvedDepartment,
            diagnosis: String(diagnosis || cleanTitle).trim(),
            symptoms: String(symptoms || '').trim(),
            clinicalSections: cleanSections,
            followUpDate: String(followUpDate || '').trim(),
            instructions: String(instructions || '').trim(),
            doctorQualification: String(resolvedDoctorQualification || '').trim(),
            approvedByDoctor: approvedByDoctor !== undefined ? Boolean(approvedByDoctor) : isDoctorIssuedPrescription,
            description: String(description || '').trim(),
            subtitle: String(subtitle || description || effectiveCategory).trim(),
            patientId: resolvedPatientUuid,
            patientName: resolvedPatientName,
            doctorName: resolvedDoctorName,
            clinicName: clinicName || '',
            fileName: fileName || '',
            fileType: normalizedExt.toUpperCase(),
            mimeType: mimeType || (normalizedExt === 'pdf' ? 'application/pdf' : `image/${normalizedExt === 'jpg' ? 'jpeg' : normalizedExt}`),
            fileSize: Number(fileSize || 0),
            storageKey: storageKey ? String(storageKey).trim() : '',
            storageProvider: storageProvider || 'supabase',
            uploadedAt: nowIso,
            updatedAt: nowIso,
            sharedWith: []
        };

        const isXray = effectiveCategory === 'Dental X-ray' || type === 'xray';
        const cleanKey = storageKey ? String(storageKey).trim() : '';

        const created = await MedicalRecord.create({
            patient_id: resolvedPatientUuid,
            dentist_id: resolvedDentistUuid || undefined,
            appointment_id: appointmentId ? String(appointmentId).trim() : undefined,
            diagnosis: String(diagnosis || cleanTitle).trim(),
            notes: JSON.stringify(notesMeta),
            prescriptions: Array.isArray(items) ? items : [],
            xray_urls: (isXray && cleanKey) ? [cleanKey] : [],
            lab_report_urls: (!isXray && cleanKey) ? [cleanKey] : []
        });

        res.status(201).json({
            success: true,
            message: 'Health record saved successfully.',
            record: formatRecord(created)
        });
    } catch (err) {
        console.error('Create Medical Record Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to create medical record.' });
    }
};

// 4. UPDATE DENTAL HEALTH RECORD DETAILS (PATIENT OWNER ONLY)
exports.updateRecord = async (req, res) => {
    const { id } = req.params;
    const { patientId, title, category, description } = req.body;

    try {
        const existing = await MedicalRecord.findById(id);
        if (!existing) {
            return res.status(404).json({ success: false, message: 'Health record not found.' });
        }

        const callerId = patientId || req.user?.id || req.headers['x-user-id'];
        const resolvedCallerUuid = callerId ? await resolveUserUuid(callerId) : null;
        if (!resolvedCallerUuid || String(existing.patient_id) !== String(resolvedCallerUuid)) {
            return res.status(403).json({
                success: false,
                message: 'Access Denied: Only the patient who owns this record can edit it.'
            });
        }

        if (category && !ALLOWED_CATEGORIES.includes(category)) {
            return res.status(400).json({
                success: false,
                message: `Invalid category. Allowed: ${ALLOWED_CATEGORIES.join(', ')}`
            });
        }

        const parsedNotes = parseRecordNotes(existing);
        const newTitle = title !== undefined && String(title).trim().length > 0
            ? String(title).trim()
            : (parsedNotes.title || existing.diagnosis);
        const newCategory = category || parsedNotes.category || 'Other';
        const newDescription = description !== undefined ? String(description).trim() : (parsedNotes.description || '');

        parsedNotes.title = newTitle;
        parsedNotes.category = newCategory;
        parsedNotes.description = newDescription;
        parsedNotes.subtitle = newDescription || newCategory;
        parsedNotes.type = newCategory === 'Dental X-ray' ? 'xray' : (newCategory === 'Prescription' ? 'prescription' : 'document');
        parsedNotes.updatedAt = new Date().toISOString();

        const updated = await MedicalRecord.findByIdAndUpdate(id, {
            diagnosis: newTitle,
            notes: JSON.stringify(parsedNotes)
        });

        res.json({
            success: true,
            message: 'Record details updated successfully.',
            record: formatRecord(updated)
        });
    } catch (err) {
        console.error('Update Medical Record Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to update record details.' });
    }
};

// 5. DELETE DENTAL HEALTH RECORD (PATIENT OWNER ONLY)
exports.deleteRecord = async (req, res) => {
    const { id } = req.params;
    const patientId = req.query.patientId || req.body?.patientId || req.user?.id || req.headers['x-user-id'];

    try {
        const existing = await MedicalRecord.findById(id);
        if (!existing) {
            return res.status(404).json({ success: false, message: 'Health record not found.' });
        }

        const resolvedCallerUuid = patientId ? await resolveUserUuid(patientId) : null;
        if (!resolvedCallerUuid || String(existing.patient_id) !== String(resolvedCallerUuid)) {
            return res.status(403).json({
                success: false,
                message: 'Access Denied: Only the patient who owns this record can delete it.'
            });
        }

        const parsedNotes = parseRecordNotes(existing);
        const storageKey = parsedNotes.storageKey ||
            (Array.isArray(existing.xray_urls) && existing.xray_urls[0]) ||
            (Array.isArray(existing.lab_report_urls) && existing.lab_report_urls[0]);

        if (storageKey) {
            try {
                await supabaseStorageService.deleteFile(storageKey);
            } catch (_) {}
        }

        await MedicalRecord.findByIdAndDelete(id);

        res.json({
            success: true,
            message: 'Health record deleted permanently.'
        });
    } catch (err) {
        console.error('Delete Medical Record Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to delete health record.' });
    }
};

// 6. SHARE ONE OR MULTIPLE RECORDS WITH A FAVOURITE DOCTOR
exports.shareRecordsWithDoctor = async (req, res) => {
    const {
        patientId,
        patientName,
        recordIds,
        doctorId,
        doctorUserId,
        doctorEmail,
        doctorName,
        doctorSpecialty,
        doctorClinic
    } = req.body;

    if (!doctorId && !doctorUserId) {
        return res.status(400).json({
            success: false,
            message: 'A target doctor must be selected to share records.'
        });
    }

    const idsList = Array.isArray(recordIds) ? recordIds.filter(Boolean) : [];
    if (idsList.length === 0) {
        return res.status(400).json({
            success: false,
            message: 'Please select at least one record to share.'
        });
    }

    try {
        const callerId = patientId || req.user?.id || req.headers['x-user-id'];
        const resolvedCallerUuid = callerId ? await resolveUserUuid(callerId) : null;
        if (!resolvedCallerUuid) {
            return res.status(401).json({
                success: false,
                message: 'Authentication required to share health records.'
            });
        }

        const resolvedDoc = await resolveDentistIds(doctorId || doctorUserId);
        const effectiveDentistId = resolvedDoc.dentistTableId || doctorId || '';
        const effectiveDentistUserId = resolvedDoc.userTableId || doctorUserId || '';
        const sharedAt = new Date().toISOString();

        let resolvedPatientName = patientName || '';
        if (!resolvedPatientName) {
            const pUser = await User.findById(resolvedCallerUuid);
            if (pUser && pUser.name) resolvedPatientName = pUser.name;
        }

        const updatedRecords = [];
        for (const recId of idsList) {
            const existing = await MedicalRecord.findById(recId);
            if (!existing) continue;

            if (String(existing.patient_id) !== String(resolvedCallerUuid)) {
                return res.status(403).json({
                    success: false,
                    message: 'Access Denied: You can only share your own health records.'
                });
            }

            const parsedNotes = parseRecordNotes(existing);
            const currentShares = Array.isArray(parsedNotes.sharedWith) ? parsedNotes.sharedWith : [];

            const filteredShares = currentShares.filter(s => {
                const sDocId = String(s.doctorId || '').toLowerCase();
                const sUserId = String(s.doctorUserId || '').toLowerCase();
                return !(
                    (effectiveDentistId && (sDocId === String(effectiveDentistId).toLowerCase() || sUserId === String(effectiveDentistId).toLowerCase())) ||
                    (effectiveDentistUserId && (sDocId === String(effectiveDentistUserId).toLowerCase() || sUserId === String(effectiveDentistUserId).toLowerCase()))
                );
            });

            filteredShares.push({
                doctorId: String(effectiveDentistId || doctorId || ''),
                doctorUserId: String(effectiveDentistUserId || doctorUserId || ''),
                doctorEmail: String(doctorEmail || '').toLowerCase(),
                doctorName: doctorName || 'Doctor',
                doctorSpecialty: doctorSpecialty || 'General Dentistry',
                doctorClinic: doctorClinic || '',
                sharedByPatientId: String(resolvedCallerUuid),
                sharedByPatientName: resolvedPatientName || 'Patient',
                sharedAt
            });

            parsedNotes.sharedWith = filteredShares;
            parsedNotes.updatedAt = sharedAt;

            const updated = await MedicalRecord.findByIdAndUpdate(recId, {
                notes: JSON.stringify(parsedNotes)
            });
            if (updated) {
                updatedRecords.push(formatRecord(updated));
            }
        }

        // Notify the doctor
        const targetNotifId = effectiveDentistId || effectiveDentistUserId || doctorId;
        if (targetNotifId && updatedRecords.length > 0) {
            try {
                await Notification.create({
                    recipient_role: 'Dentist',
                    recipient_id: String(targetNotifId),
                    title: 'New Health Records Shared',
                    message: `${resolvedPatientName || 'A patient'} shared ${updatedRecords.length} health record(s) with you.`,
                    type: 'RECORD_SHARED'
                });
            } catch (_) {}
        }

        res.json({
            success: true,
            message: `Successfully shared ${updatedRecords.length} record(s) with ${doctorName || 'Doctor'}.`,
            records: updatedRecords
        });
    } catch (err) {
        console.error('Share Medical Records Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to share dental health records.' });
    }
};

// 7. REVOKE DOCTOR SHARING PERMISSION (PATIENT OWNER ONLY)
exports.revokeRecordShare = async (req, res) => {
    const { id } = req.params;
    const doctorId = req.params.doctorId || req.body?.doctorId || req.query?.doctorId;
    const patientId = req.body?.patientId || req.query?.patientId || req.user?.id || req.headers['x-user-id'];

    if (!doctorId) {
        return res.status(400).json({ success: false, message: 'doctorId is required to revoke sharing permission.' });
    }

    try {
        const existing = await MedicalRecord.findById(id);
        if (!existing) {
            return res.status(404).json({ success: false, message: 'Health record not found.' });
        }

        const resolvedCallerUuid = patientId ? await resolveUserUuid(patientId) : null;
        if (!resolvedCallerUuid || String(existing.patient_id) !== String(resolvedCallerUuid)) {
            return res.status(403).json({
                success: false,
                message: 'Access Denied: Only the patient owner can revoke sharing permissions.'
            });
        }

        const resolvedDoc = await resolveDentistIds(doctorId);
        const targetIds = new Set(
            [doctorId, resolvedDoc.dentistTableId, resolvedDoc.userTableId]
                .filter(Boolean)
                .map(x => String(x).trim().toLowerCase())
        );

        const parsedNotes = parseRecordNotes(existing);
        const currentShares = Array.isArray(parsedNotes.sharedWith) ? parsedNotes.sharedWith : [];
        parsedNotes.sharedWith = currentShares.filter(s => {
            const sDocId = String(s.doctorId || '').trim().toLowerCase();
            const sUserId = String(s.doctorUserId || '').trim().toLowerCase();
            const sEmail = String(s.doctorEmail || '').trim().toLowerCase();
            return !(targetIds.has(sDocId) || targetIds.has(sUserId) || targetIds.has(sEmail));
        });
        parsedNotes.updatedAt = new Date().toISOString();

        const updated = await MedicalRecord.findByIdAndUpdate(id, {
            notes: JSON.stringify(parsedNotes)
        });

        res.json({
            success: true,
            message: 'Sharing permission revoked successfully.',
            record: formatRecord(updated)
        });
    } catch (err) {
        console.error('Revoke Share Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to revoke sharing permission.' });
    }
};

// 8. VERIFY ACCESS & GENERATE SIGNED VIEW/DOWNLOAD URL (PATIENT OWNER OR AUTHORIZED SHARED DOCTOR ONLY)
exports.getRecordFileAccess = async (req, res) => {
    const { id } = req.params;
    const requesterId = req.query.requesterId || req.query.patientId || req.query.doctorId || req.user?.id || req.headers['x-user-id'];
    const requesterRole = String(req.query.role || req.user?.role || req.headers['x-user-role'] || '').trim().toLowerCase();

    try {
        const existing = await MedicalRecord.findById(id);
        if (!existing) {
            return res.status(404).json({ success: false, message: 'Health record not found.' });
        }

        const formatted = formatRecord(existing);
        if (!requesterId) {
            return res.status(401).json({
                success: false,
                message: 'Authentication required to view or download this record.'
            });
        }

        let isAuthorized = false;

        // Check 1: Is requester the patient owner?
        if (requesterRole !== 'dentist' && requesterRole !== 'doctor' && requesterRole !== 'clinic') {
            const resolvedRequesterUuid = await resolveUserUuid(requesterId);
            if (resolvedRequesterUuid && String(existing.patient_id) === String(resolvedRequesterUuid)) {
                isAuthorized = true;
            }
        }

        // Check 2: Is requester an authorized shared doctor?
        if (!isAuthorized && (requesterRole === 'dentist' || requesterRole === 'doctor' || req.query.doctorId)) {
            const docIdSet = await buildDoctorIdentifierSet(req.query.doctorId || requesterId, req.user);
            if (isDoctorAuthorizedForRecord(formatted, docIdSet)) {
                isAuthorized = true;
            } else if (formatted.recordSource === 'doctor_issued' && formatted.dentistId && docIdSet.has(String(formatted.dentistId).toLowerCase())) {
                isAuthorized = true;
            }
        }

        if (!isAuthorized) {
            return res.status(403).json({
                success: false,
                authorized: false,
                message: 'Access Denied: You do not have permission to view or download this health record.'
            });
        }

        let signedUrl = null;
        if (formatted.storageKey) {
            try {
                const signedRes = await supabaseStorageService.getSignedUrl(formatted.storageKey, 900);
                signedUrl = signedRes.signedUrl;
            } catch (_) {}
        }

        return res.json({
            success: true,
            authorized: true,
            record: formatted,
            signedUrl,
            expiresIn: 900
        });
    } catch (err) {
        console.error('Get Record File Access Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to authorize record file access.' });
    }
};
