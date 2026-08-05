const { MedicalRecord } = require('../models/Schemas');

// 1. GET ALL RECORDS FOR A PATIENT
exports.getPatientRecords = async (req, res) => {
    const { patientId } = req.query;
    try {
        const query = patientId ? { patient_id: patientId } : {};
        const records = await MedicalRecord.find(query);

        const formatted = records.map(r => {
            let parsedNotes = {};
            try {
                parsedNotes = typeof r.notes === 'string' ? JSON.parse(r.notes) : (r.notes || {});
            } catch (e) {
                parsedNotes = {};
            }
            return {
                id: r.id,
                patientId: r.patient_id,
                type: parsedNotes.type || 'prescription',
                title: parsedNotes.title || r.diagnosis || 'E-Prescription Slip',
                subtitle: parsedNotes.subtitle || r.diagnosis || 'Dental Consultation',
                doctorName: parsedNotes.doctor_name || 'Attending Dentist',
                clinicName: parsedNotes.clinic_name || 'DentaGuru Practice',
                date: r.created_at,
                items: r.prescriptions || []
            };
        });

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

// 2. CREATE NEW MEDICAL RECORD
exports.createRecord = async (req, res) => {
    const { patientId, type, title, subtitle, doctorName, clinicName, items } = req.body;
    try {
        const newRecord = await MedicalRecord.create({
            patient_id: patientId,
            type,
            title,
            subtitle,
            doctor_name: doctorName,
            clinic_name: clinicName,
            date: new Date().toISOString(),
            details: JSON.stringify(items || [])
        });
        res.status(201).json({ success: true, record: newRecord });
    } catch (err) {
        console.error('Create Medical Record Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to create medical record.' });
    }
};
