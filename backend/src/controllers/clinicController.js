const { Clinic, Dentist } = require('../models/Schemas');

// 1. REGISTER CLINIC PROFILE
exports.registerClinicProfile = async (req, res) => {
    const { clinicName, location, services, pricing, coordinates } = req.body;
    try {
        const role = req.user?.role || '';
        if (role !== 'SuperAdmin' && role !== 'Admin' && req.user?.id) {
            const clinic = await Clinic.findOne({ user_id: req.user.id });
            if (clinic) {
                return res.status(400).json({ success: false, message: 'Clinic profile already exists.' });
            }
        }

        const clinic = await Clinic.create({
            userId: req.user?.id || null,
            clinicName,
            location,
            services,
            pricing,
            coordinates: coordinates ? { type: 'Point', coordinates } : undefined
        });

        res.status(201).json({ success: true, message: 'Clinic profile created in Supabase PostgreSQL.', clinic });
    } catch (err) {
        console.error('Clinic Profile Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to create clinic profile.' });
    }
};

// 2. GET ALL CLINICS
exports.getClinics = async (req, res) => {
    const { search, service } = req.query;
    try {
        let query = {};
        if (search) query.clinicName = search;
        if (service) query.services = service;

        const clinics = await Clinic.find(query);
        res.json({ success: true, count: clinics.length, clinics });
    } catch (err) {
        res.status(500).json({ success: false, message: 'Failed to fetch clinics list.' });
    }
};

// 3. GET CLINIC DENTISTS
exports.getClinicDentists = async (req, res) => {
    const { clinicId } = req.params;
    try {
        const dentists = await Dentist.find({ clinic_id: clinicId });
        res.json({ success: true, count: dentists.length, dentists });
    } catch (err) {
        res.status(500).json({ success: false, message: 'Failed to fetch clinic dentists.' });
    }
};

// 4. GET ALL DENTISTS
exports.getAllDentists = async (req, res) => {
    try {
        const dentists = await Dentist.find();
        const { User } = require('../models/Schemas');
        const dentistUsers = await User.find({ role: 'Dentist' });
        
        const existingEmails = new Set(dentists.map(d => (d.email || d.users?.email || '').toLowerCase()));
        
        for (const u of dentistUsers) {
            const emailClean = (u.email || '').toLowerCase();
            if (emailClean && !existingEmails.has(emailClean)) {
                dentists.push({
                    id: u.id,
                    name: u.name.startsWith('Dr.') ? u.name : `Dr. ${u.name}`,
                    speciality: u.specialty || 'General Dentistry',
                    specialty: u.specialty || 'General Dentistry',
                    qualification: 'BDS, MDS',
                    experienceYears: 5,
                    rating: 5.0,
                    reviews_count: 1,
                    clinicName: u.clinic_name || 'DentaGuru Practice',
                    phone: u.phone || '',
                    email: u.email || '',
                    availability_status: 'Available',
                    license_number: 'DEN-LIC-REG',
                    users: { name: u.name, email: u.email, phone: u.phone }
                });
                existingEmails.add(emailClean);
            }
        }

        res.json({ success: true, count: dentists.length, dentists });
    } catch (err) {
        console.error('Get All Dentists Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to fetch all dentists.' });
    }
};
