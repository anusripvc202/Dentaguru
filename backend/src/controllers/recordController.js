const { MedicalRecord } = require('../models/Schemas');

// 1. GET ALL RECORDS FOR A PATIENT
exports.getPatientRecords = async (req, res) => {
    const { patientId } = req.query;
    try {
        const query = patientId ? { patient_id: patientId } : {};
        const records = await MedicalRecord.find(query);

        res.json({
            success: true,
            count: records.length,
            records: records || []
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
