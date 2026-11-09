const {
    MedicalSpecialty,
    Dentist,
    Appointment,
    Referral,
    PatientProblemRequest,
    matchesSpecialtyQuery
} = require('../models/Schemas');

// 1. GET MEDICAL SPECIALTIES (Public / Patient / Doctor / Admin)
exports.getSpecialties = async (req, res) => {
    try {
        const activeOnly = req.query.activeOnly === 'true' || req.query.is_active === 'true';
        const specialties = await MedicalSpecialty.find({ activeOnly });
        res.json({
            success: true,
            count: specialties.length,
            specialties
        });
    } catch (err) {
        console.error('Get Specialties Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to fetch medical specialties.' });
    }
};

// 2. ADMIN: CREATE MEDICAL SPECIALTY
exports.createSpecialty = async (req, res) => {
    try {
        const {
            name,
            code,
            department,
            description,
            icon,
            default_qualifications,
            defaultQualifications,
            consultation_types,
            consultationTypes,
            sub_specialties,
            subSpecialties,
            is_active,
            isActive,
            display_order,
            displayOrder
        } = req.body;

        if (!name || !String(name).trim()) {
            return res.status(400).json({ success: false, message: 'Medical specialty name is required.' });
        }

        const specialty = await MedicalSpecialty.create({
            name: String(name).trim(),
            code,
            department,
            description,
            icon,
            default_qualifications: default_qualifications || defaultQualifications,
            consultation_types: consultation_types || consultationTypes,
            sub_specialties: sub_specialties || subSpecialties,
            is_active: is_active !== undefined ? is_active : (isActive !== undefined ? isActive : true),
            display_order: display_order || displayOrder
        });

        res.status(201).json({
            success: true,
            message: `Medical specialty "${specialty.name}" saved successfully.`,
            specialty
        });
    } catch (err) {
        console.error('Create Specialty Error:', err.message);
        res.status(500).json({ success: false, message: err.message || 'Failed to create medical specialty.' });
    }
};

// 3. ADMIN: UPDATE MEDICAL SPECIALTY
exports.updateSpecialty = async (req, res) => {
    try {
        const { id } = req.params;
        const updated = await MedicalSpecialty.findByIdAndUpdate(id, req.body);
        if (!updated) {
            return res.status(404).json({ success: false, message: 'Medical specialty not found.' });
        }
        res.json({
            success: true,
            message: `Medical specialty "${updated.name}" updated successfully.`,
            specialty: updated
        });
    } catch (err) {
        console.error('Update Specialty Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to update medical specialty.' });
    }
};

// 4. ADMIN: ACTIVATE / DEACTIVATE MEDICAL SPECIALTY
exports.toggleSpecialtyStatus = async (req, res) => {
    try {
        const { id } = req.params;
        const existing = await MedicalSpecialty.findById(id);
        if (!existing) {
            return res.status(404).json({ success: false, message: 'Medical specialty not found.' });
        }

        const nextStatus = req.body.is_active !== undefined
            ? Boolean(req.body.is_active)
            : (req.body.isActive !== undefined ? Boolean(req.body.isActive) : !existing.is_active);

        const updated = await MedicalSpecialty.findByIdAndUpdate(id, { is_active: nextStatus });
        res.json({
            success: true,
            message: `Medical specialty "${updated.name}" is now ${updated.is_active ? 'Active' : 'Inactive'}.`,
            specialty: updated
        });
    } catch (err) {
        console.error('Toggle Specialty Status Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to toggle medical specialty status.' });
    }
};

// 5. ADMIN: DELETE MEDICAL SPECIALTY
exports.deleteSpecialty = async (req, res) => {
    try {
        const { id } = req.params;
        const removed = await MedicalSpecialty.deleteOne(id);
        res.json({
            success: true,
            message: 'Medical specialty removed successfully.',
            specialty: removed
        });
    } catch (err) {
        console.error('Delete Specialty Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to delete medical specialty.' });
    }
};

// 6. ADMIN: SPECIALTY-BASED REPORTING & ANALYTICS
exports.getSpecialtyAnalyticsReport = async (req, res) => {
    try {
        const [specialties, doctors, appointments, referrals, requests] = await Promise.all([
            MedicalSpecialty.find({}),
            Dentist.find({}),
            Appointment.find({}),
            Referral.find({}),
            PatientProblemRequest.find({})
        ]);

        const doctorSpecialtyMap = new Map();
        for (const doc of doctors) {
            const spec = doc.speciality || doc.specialty || 'Dentistry';
            if (doc.id) doctorSpecialtyMap.set(String(doc.id), spec);
            if (doc.user_id) doctorSpecialtyMap.set(String(doc.user_id), spec);
        }

        const report = specialties.map(spec => {
            const specName = spec.name;
            const matchedDoctors = doctors.filter(d => matchesSpecialtyQuery(d.speciality || d.specialty, specName));
            const verifiedDoctors = matchedDoctors.filter(d => (d.verification_status || 'VERIFIED').toUpperCase() === 'VERIFIED');

            const matchedAppointments = appointments.filter(a => {
                const apptSpec = a.specialty || doctorSpecialtyMap.get(String(a.dentist_id || '')) || 'Dentistry';
                return matchesSpecialtyQuery(apptSpec, specName);
            });

            const matchedReferrals = referrals.filter(r => {
                const refSpec = r.specialty || r.required_specialist || doctorSpecialtyMap.get(String(r.doctor_id || r.assigned_doctor_id || '')) || 'Dentistry';
                return matchesSpecialtyQuery(refSpec, specName);
            });

            const matchedRequests = requests.filter(r => {
                const reqSpec = r.specialty || r.problem_category || doctorSpecialtyMap.get(String(r.suggested_dentist_id || '')) || 'Dentistry';
                return matchesSpecialtyQuery(reqSpec, specName);
            });

            return {
                id: spec.id,
                code: spec.code,
                name: spec.name,
                department: spec.department,
                is_active: spec.is_active !== false,
                totalDoctors: matchedDoctors.length,
                verifiedDoctors: verifiedDoctors.length,
                totalAppointments: matchedAppointments.length,
                totalReferrals: matchedReferrals.length,
                totalConsultations: matchedRequests.length
            };
        });

        res.json({
            success: true,
            count: report.length,
            report
        });
    } catch (err) {
        console.error('Specialty Analytics Report Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to generate specialty analytics report.' });
    }
};

