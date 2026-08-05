const { MedicalRecord } = require('../models/Schemas');

// 1. GET ALL RECORDS FOR A PATIENT
exports.getPatientRecords = async (req, res) => {
    const { patientId } = req.query;
    try {
        const query = patientId ? { patient_id: patientId } : {};
        const records = await MedicalRecord.find(query);
        
        // Default seed records if DB table is empty or pending sync
        const defaultRecords = [
            {
                id: 'REC-101',
                type: 'prescription',
                title: 'Digital Prescription Slips',
                subtitle: '3 Active Prescriptions (Amoxicillin, Pain Relief, Mouthwash)',
                doctorName: 'Dr. Elena Rodriguez',
                clinicName: 'Apex Dental Center',
                date: '2026-08-01',
                items: [
                    { name: 'Amoxicillin 500mg', dosage: '1 tablet every 8 hours', duration: '7 Days', status: 'Active' },
                    { name: 'Ibuprofen 400mg', dosage: '1 tablet as needed for pain', duration: '5 Days', status: 'Active' },
                    { name: 'Chlorhexidine 0.12% Rinse', dosage: '15ml swish & spit twice daily', duration: '14 Days', status: 'Active' }
                ]
            },
            {
                id: 'REC-102',
                type: 'xray',
                title: 'Panoramic X-Ray Scans',
                subtitle: '2 Scans Available (DICOM HD Format)',
                doctorName: 'Dr. Sarah Jenkins',
                clinicName: 'Metro Dental Radiology',
                date: '2026-07-28',
                items: [
                    { scanType: 'Full Panoramic Jaw Scan', format: 'DICOM HD', resolution: '4K', notes: 'No bone loss observed in upper molar region.' },
                    { scanType: 'Bitewing Molar X-Ray', format: 'DICOM HD', resolution: '1080p', notes: 'Minor interproximal shadow noted on Tooth #14.' }
                ]
            },
            {
                id: 'REC-103',
                type: 'chart',
                title: '3D Teeth Chart & History',
                subtitle: 'View fillings, crowns & aligner timeline',
                doctorName: 'Dr. Michael Chang',
                clinicName: 'City Center Dental Hub',
                date: '2026-06-15',
                items: [
                    { toothNumber: 14, procedure: 'Composite Filling', date: '2026-06-15', status: 'Restored' },
                    { toothNumber: 19, procedure: 'Zirconia Crown', date: '2026-04-10', status: 'Healthy' },
                    { toothNumber: 30, procedure: 'Scaling & Root Planing', date: '2026-02-20', status: 'Maintained' }
                ]
            }
        ];

        const result = (records && records.length > 0) ? records : defaultRecords;

        res.json({
            success: true,
            count: result.length,
            records: result
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
