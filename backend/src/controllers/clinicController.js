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

// 4. GET ALL DENTISTS (with optional state/city/pincode/specialty/availability filters)
exports.getAllDentists = async (req, res) => {
    try {
        const { state, city, pincode, specialty, availability } = req.query;

        // Build filter query for dentists table
        const filterQuery = {};
        if (state && state.trim()) filterQuery.state = state.trim();
        if (city && city.trim()) filterQuery.city = city.trim();
        if (pincode && pincode.trim()) filterQuery.pincode = pincode.trim();
        if (specialty && specialty.trim()) filterQuery.speciality = specialty.trim();
        if (availability && availability.trim()) filterQuery.availability_status = availability.trim();

        const dentists = await Dentist.find(filterQuery);
        const { User } = require('../models/Schemas');

        // Also fetch user-based dentists and merge (those not yet in dentists table)
        let dentistUsers = await User.find({ role: 'Dentist' });

        if (state && state.trim()) {
            const stateLower = state.trim().toLowerCase();
            dentistUsers = dentistUsers.filter(u => (u.state || '').toLowerCase().includes(stateLower));
        }
        if (city && city.trim()) {
            const cityLower = city.trim().toLowerCase();
            dentistUsers = dentistUsers.filter(u => (u.city || '').toLowerCase().includes(cityLower));
        }
        if (pincode && pincode.trim()) {
            dentistUsers = dentistUsers.filter(u => (u.pincode || '').includes(pincode.trim()));
        }

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
                    state: u.state || '',
                    city: u.city || '',
                    pincode: u.pincode || '',
                    latitude: u.latitude || null,
                    longitude: u.longitude || null,
                    availability_status: 'Available',
                    license_number: 'DEN-LIC-REG',
                    users: { name: u.name, email: u.email, phone: u.phone, state: u.state || '', city: u.city || '', pincode: u.pincode || '', latitude: u.latitude, longitude: u.longitude }
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
