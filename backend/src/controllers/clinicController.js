const { Clinic, Dentist } = require('../models/Schemas');

// 1. REGISTER CLINIC PROFILE
exports.registerClinicProfile = async (req, res) => {
    const { clinicName, location, services, pricing, coordinates } = req.body;
    try {
        let clinic = await Clinic.findOne({ userId: req.user.id });
        if (clinic) {
            return res.status(400).json({ success: false, message: 'Clinic profile already exists.' });
        }

        clinic = new Clinic({
            userId: req.user.id,
            clinicName,
            location,
            services,
            pricing,
            coordinates: coordinates ? { type: 'Point', coordinates } : undefined
        });

        await clinic.save();
        res.status(201).json({ success: true, message: 'Clinic profile created.', clinic });
    } catch (err) {
        res.status(500).json({ success: false, message: 'Failed to create clinic profile.' });
    }
};

// 2. GET ALL CLINICS (Searching & filtering)
exports.getClinics = async (req, res) => {
    const { search, service } = req.query;
    try {
        let query = {};
        if (search) {
            query.clinicName = { $regex: search, $options: 'i' };
        }
        if (service) {
            query.services = service;
        }

        const clinics = await Clinic.find(query).sort({ rating: -1 });
        res.json({ success: true, count: clinics.length, clinics });
    } catch (err) {
        res.status(500).json({ success: false, message: 'Failed to fetch clinics list.' });
    }
};

// 3. GET CLINIC DENTISTS
exports.getClinicDentists = async (req, res) => {
    const { clinicId } = req.params;
    try {
        const dentists = await Dentist.find({ clinicId })
            .populate('userId', 'name email phone');
        res.json({ success: true, count: dentists.length, dentists });
    } catch (err) {
        res.status(500).json({ success: false, message: 'Failed to fetch clinic dentists.' });
    }
};
