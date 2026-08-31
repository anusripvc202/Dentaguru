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

// 4. GET ALL DENTISTS (with optional state/city/pincode/specialty/availability/language filters)
exports.getAllDentists = async (req, res) => {
    try {
        const { state, city, pincode, specialty, availability, language } = req.query;

        // Build filter query for dentists table
        const filterQuery = {};
        if (state && state.trim()) filterQuery.state = state.trim();
        if (city && city.trim()) filterQuery.city = city.trim();
        if (pincode && pincode.trim()) filterQuery.pincode = pincode.trim();
        if (specialty && specialty.trim()) filterQuery.speciality = specialty.trim();
        if (availability && availability.trim()) filterQuery.availability_status = availability.trim();
        if (language && language.trim()) filterQuery.language = language.trim();

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
                let userLangs = u.languages || ['English'];
                if (u.device_token && u.device_token.startsWith('{')) {
                    try {
                        const meta = JSON.parse(u.device_token);
                        if (meta.languages && Array.isArray(meta.languages)) userLangs = meta.languages;
                    } catch (_) {}
                }
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
                    languages: userLangs,
                    latitude: u.latitude || null,
                    longitude: u.longitude || null,
                    availability_status: 'Available',
                    license_number: 'DEN-LIC-REG',
                    users: { name: u.name, email: u.email, phone: u.phone, state: u.state || '', city: u.city || '', pincode: u.pincode || '', languages: userLangs, latitude: u.latitude, longitude: u.longitude }
                });
                existingEmails.add(emailClean);
            }
        }

        let formattedDentists = dentists.map(d => {
            const uObj = d.users || {};
            const cObj = d.clinics || {};
            const name = d.name || uObj.name || 'Dentist';
            const formattedName = name.startsWith('Dr.') ? name : `Dr. ${name}`;

            let doctorLangs = d.languages || uObj.languages;
            if (!doctorLangs || (Array.isArray(doctorLangs) && doctorLangs.length === 0)) {
                if (uObj.device_token && typeof uObj.device_token === 'string' && uObj.device_token.startsWith('{')) {
                    try {
                        const meta = JSON.parse(uObj.device_token);
                        if (meta.languages && Array.isArray(meta.languages)) doctorLangs = meta.languages;
                    } catch (_) {}
                }
            }
            if (!doctorLangs || (Array.isArray(doctorLangs) && doctorLangs.length === 0)) {
                doctorLangs = ['English'];
            } else if (typeof doctorLangs === 'string') {
                doctorLangs = doctorLangs.split(',').map(s => s.trim()).filter(Boolean);
            }

            return {
                id: d.id,
                user_id: d.user_id || uObj.id,
                name: formattedName,
                email: d.email || uObj.email || '',
                phone: d.phone || uObj.phone || '',
                speciality: d.speciality || d.specialty || 'General Dentistry',
                specialty: d.speciality || d.specialty || 'General Dentistry',
                license_number: d.license_number || d.licenseNumber || 'DEN-LIC-REG',
                licenseNumber: d.license_number || d.licenseNumber || 'DEN-LIC-REG',
                qualification: d.qualifications || d.qualification || 'BDS, MDS',
                experienceYears: d.experience_years || d.experienceYears || 5,
                experience_years: d.experience_years || d.experienceYears || 5,
                rating: d.rating || 5.0,
                reviews_count: d.reviews_count || d.reviewCount || 1,
                clinicName: cObj.clinic_name || d.clinicName || 'DentaGuru Practice',
                clinicAddress: cObj.location || d.clinicAddress || d.location || 'Healthcare Hub',
                state: d.state || uObj.state || '',
                city: d.city || uObj.city || '',
                pincode: d.pincode || uObj.pincode || '',
                languages: doctorLangs,
                latitude: d.latitude || uObj.latitude || null,
                longitude: d.longitude || uObj.longitude || null,
                availability_status: d.availability_status || d.status || 'Available',
                verificationStatus: d.verification_status || d.verificationStatus || 'VERIFIED',
                profilePhoto: uObj.biometric_token || d.profilePhoto || null,
                users: uObj,
                clinics: cObj
            };
        });

        if (language && language.trim()) {
            const langLower = language.trim().toLowerCase();
            formattedDentists = formattedDentists.filter(d => {
                return (d.languages || []).some(l => (l || '').toLowerCase().includes(langLower));
            });
        }

        const pCity = (req.query.patientCity || req.query.city || '').trim().toLowerCase();
        const pPin = (req.query.patientPincode || req.query.pincode || '').trim();

        if (pCity || pPin) {
            formattedDentists.sort((a, b) => {
                const aCity = (a.city || '').trim().toLowerCase();
                const aPin = (a.pincode || '').trim();
                const bCity = (b.city || '').trim().toLowerCase();
                const bPin = (b.pincode || '').trim();

                let scoreA = 3; // Other location
                if (pPin && aPin && aPin === pPin) scoreA = 1; // Same Pincode
                else if (pCity && aCity && (aCity === pCity || aCity.includes(pCity) || pCity.includes(aCity))) scoreA = 2; // Same City

                let scoreB = 3;
                if (pPin && bPin && bPin === pPin) scoreB = 1;
                else if (pCity && bCity && (bCity === pCity || bCity.includes(pCity) || pCity.includes(bCity))) scoreB = 2;

                if (scoreA !== scoreB) return scoreA - scoreB;
                return (b.rating || 5.0) - (a.rating || 5.0);
            });
        }

        res.json({ success: true, count: formattedDentists.length, dentists: formattedDentists });
    } catch (err) {
        console.error('Get All Dentists Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to fetch all dentists.' });
    }
};

// 5. GET PATIENT SAVED DOCTORS (My Doctors)
exports.getPatientDoctors = async (req, res) => {
    try {
        const { PatientDoctor } = require('../models/Schemas');
        const patientId = req.query.patientId || req.user?.id;
        if (!patientId) {
            return res.status(400).json({ success: false, message: 'patientId is required' });
        }
        const doctorIds = await PatientDoctor.getDoctorsForPatient(patientId);
        res.json({ success: true, count: doctorIds.length, doctorIds });
    } catch (err) {
        console.error('Get Patient Doctors Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to fetch patient doctors.' });
    }
};

// 6. ADD DOCTOR TO PATIENT'S "MY DOCTORS"
exports.addPatientDoctor = async (req, res) => {
    try {
        const { PatientDoctor } = require('../models/Schemas');
        const patientId = req.body.patientId || req.user?.id;
        const doctorId = req.body.doctorId;

        if (!patientId || !doctorId) {
            return res.status(400).json({ success: false, message: 'Both patientId and doctorId are required' });
        }

        const result = await PatientDoctor.addDoctorForPatient(patientId, doctorId);
        res.json({ success: true, message: 'Doctor added to My Doctors successfully.', data: result.data });
    } catch (err) {
        console.error('Add Patient Doctor Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to add doctor to patient list.' });
    }
};

// 7. REMOVE DOCTOR FROM PATIENT'S "MY DOCTORS"
exports.removePatientDoctor = async (req, res) => {
    try {
        const { PatientDoctor } = require('../models/Schemas');
        const patientId = req.query.patientId || req.body.patientId || req.user?.id;
        const doctorId = req.params.doctorId || req.body.doctorId;

        if (!patientId || !doctorId) {
            return res.status(400).json({ success: false, message: 'Both patientId and doctorId are required' });
        }

        await PatientDoctor.removeDoctorForPatient(patientId, doctorId);
        res.json({ success: true, message: 'Doctor removed from My Doctors successfully.' });
    } catch (err) {
        console.error('Remove Patient Doctor Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to remove doctor from patient list.' });
    }
};

