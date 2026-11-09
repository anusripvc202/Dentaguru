const { Clinic, Dentist, matchesSpecialtyQuery, getDefaultQualificationForSpecialty } = require('../models/Schemas');

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

// 4. GET ALL DENTISTS / DOCTORS (with optional state/city/pincode/specialty/search/availability/language filters)
exports.getAllDentists = async (req, res) => {
    try {
        const { state, city, pincode, specialty, speciality, search, availability, language } = req.query;
        const effectiveSpecialty = (specialty || speciality || '').trim();
        const searchKw = (search || '').trim().toLowerCase();

        // Build filter query for dentists table
        const filterQuery = {};
        if (state && state.trim()) filterQuery.state = state.trim();
        if (city && city.trim()) filterQuery.city = city.trim();
        if (pincode && pincode.trim()) filterQuery.pincode = pincode.trim();
        if (effectiveSpecialty) filterQuery.speciality = effectiveSpecialty;
        if (availability && availability.trim()) filterQuery.availability_status = availability.trim();
        if (language && language.trim()) filterQuery.language = language.trim();

        const dentists = await Dentist.find(filterQuery);
        const { User } = require('../models/Schemas');

        // Also fetch user-based dentists / doctors and merge (those not yet in dentists table)
        const [dentistRoleUsers, doctorRoleUsers] = await Promise.all([
            User.find({ role: 'Dentist' }),
            User.find({ role: 'Doctor' })
        ]);
        let dentistUsers = [...dentistRoleUsers, ...doctorRoleUsers];

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
                let userMeta = {};
                if (u.device_token && u.device_token.startsWith('{')) {
                    try {
                        userMeta = JSON.parse(u.device_token);
                        if (userMeta.languages && Array.isArray(userMeta.languages)) userLangs = userMeta.languages;
                    } catch (_) {}
                }
                const uSpec = u.specialty || userMeta.specialty || 'General Dentistry';
                if (effectiveSpecialty && !matchesSpecialtyQuery(uSpec, effectiveSpecialty)) {
                    continue;
                }
                const uQual = u.qualification || userMeta.qualification || getDefaultQualificationForSpecialty(uSpec);
                const uExp = u.experienceYears || userMeta.experienceYears || 5;
                dentists.push({
                    id: u.id,
                    name: u.name.startsWith('Dr.') ? u.name : `Dr. ${u.name}`,
                    speciality: uSpec,
                    specialty: uSpec,
                    qualification: uQual,
                    experienceYears: uExp,
                    rating: 5.0,
                    reviews_count: 1,
                    clinicName: u.clinic_name || userMeta.clinicName || 'GS HEALTH Practice',
                    phone: u.phone || '',
                    email: u.email || '',
                    state: u.state || '',
                    city: u.city || '',
                    pincode: u.pincode || '',
                    languages: userLangs,
                    latitude: u.latitude || null,
                    longitude: u.longitude || null,
                    availability_status: 'Available',
                    license_number: userMeta.licenseNumber || 'MED-LIC-REG',
                    users: { name: u.name, email: u.email, phone: u.phone, state: u.state || '', city: u.city || '', pincode: u.pincode || '', languages: userLangs, latitude: u.latitude, longitude: u.longitude, biometric_token: u.biometric_token }
                });
                existingEmails.add(emailClean);
            }
        }

        let formattedDentists = dentists.map(d => {
            const uObj = d.users || {};
            const cObj = d.clinics || {};
            const name = d.name || uObj.name || 'Doctor';
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

            const resolvedSpec = d.speciality || d.specialty || 'General Dentistry';
            const resolvedQual = d.qualifications || d.qualification || getDefaultQualificationForSpecialty(resolvedSpec);

            return {
                id: d.id,
                user_id: d.user_id || uObj.id,
                name: formattedName,
                email: d.email || uObj.email || '',
                phone: d.phone || uObj.phone || '',
                speciality: resolvedSpec,
                specialty: resolvedSpec,
                license_number: d.license_number || d.licenseNumber || 'MED-LIC-REG',
                licenseNumber: d.license_number || d.licenseNumber || 'MED-LIC-REG',
                qualification: resolvedQual,
                experienceYears: d.experience_years || d.experienceYears || 5,
                experience_years: d.experience_years || d.experienceYears || 5,
                rating: d.rating || 5.0,
                reviews_count: d.reviews_count || d.reviewCount || 1,
                clinicName: cObj.clinic_name || d.clinicName || 'GS HEALTH Practice',
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

        if (searchKw) {
            formattedDentists = formattedDentists.filter(d => {
                return (d.name || '').toLowerCase().includes(searchKw) ||
                    (d.specialty || '').toLowerCase().includes(searchKw) ||
                    (d.qualification || '').toLowerCase().includes(searchKw) ||
                    (d.clinicName || '').toLowerCase().includes(searchKw) ||
                    (d.city || '').toLowerCase().includes(searchKw) ||
                    (d.pincode || '').includes(searchKw);
            });
        }

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

        res.json({ success: true, count: formattedDentists.length, dentists: formattedDentists, doctors: formattedDentists });
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

// 8. DELETE DENTIST (PERMANENT REMOVAL)
exports.deleteDentist = async (req, res) => {
    const { id } = req.params;
    try {
        if (!id) {
            return res.status(400).json({ success: false, message: 'Doctor ID is required.' });
        }

        const { supabaseAdmin } = require('../config/supabase');

        // 1. Delete from patient_doctors junction if any
        try {
            await supabaseAdmin.from('patient_doctors').delete().or(`doctor_id.eq.${id},patient_id.eq.${id}`);
        } catch (_) {}

        // 2. Check dentists table and delete
        let userId = null;
        try {
            const { data: dData } = await supabaseAdmin.from('dentists').select('id, user_id').or(`id.eq.${id},user_id.eq.${id}`).maybeSingle();
            if (dData) {
                userId = dData.user_id;
                await supabaseAdmin.from('dentists').delete().or(`id.eq.${dData.id},id.eq.${id},user_id.eq.${id}`);
            } else {
                await supabaseAdmin.from('dentists').delete().or(`id.eq.${id},user_id.eq.${id}`);
            }
        } catch (_) {}

        // 3. Delete from users table if applicable
        const targetUserId = userId || id;
        try {
            await supabaseAdmin.from('users').delete().eq('id', targetUserId);
            await supabaseAdmin.auth.admin.deleteUser(targetUserId);
        } catch (_) {}

        res.json({ success: true, message: 'Doctor deleted successfully.' });
    } catch (err) {
        console.error('Delete Dentist Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to delete doctor.' });
    }
};

// 9. UPDATE DOCTOR PROFESSIONAL PROFILE (Specialty, Qualification, Experience, Clinic, Availability)
exports.updateDoctorProfile = async (req, res) => {
    const { id } = req.params;
    const {
        name,
        specialty,
        speciality,
        qualification,
        qualifications,
        experienceYears,
        experience_years,
        licenseNumber,
        license_number,
        clinicName,
        city,
        pincode,
        state,
        status,
        availability_status
    } = req.body;
    try {
        if (!id) {
            return res.status(400).json({ success: false, message: 'Doctor ID is required.' });
        }

        const { User } = require('../models/Schemas');
        let clinicId = undefined;
        if (clinicName && String(clinicName).trim()) {
            const cName = String(clinicName).trim();
            let clinic = await Clinic.findOne({ clinic_name: cName });
            if (!clinic) {
                clinic = await Clinic.create({
                    clinic_name: cName,
                    location: city ? `${city}${pincode ? ' - ' + pincode : ''}` : 'GS HEALTH Medical Center',
                    verified: true,
                    services: [specialty || speciality || 'General Medicine']
                });
            }
            if (clinic && clinic.id) clinicId = clinic.id;
        }

        const updatedDentist = await Dentist.findByIdAndUpdate(id, {
            speciality: specialty || speciality,
            qualifications: qualification || qualifications,
            experience_years: experienceYears ?? experience_years,
            license_number: licenseNumber || license_number,
            availability_status: status || availability_status,
            ...(clinicId !== undefined ? { clinic_id: clinicId } : {}),
            ...(city !== undefined ? { city } : {}),
            ...(pincode !== undefined ? { pincode } : {}),
            ...(state !== undefined ? { state } : {})
        });

        const targetUserId = updatedDentist?.user_id || id;
        if (name || city || pincode) {
            try {
                await User.findByIdAndUpdate(targetUserId, {
                    ...(name ? { name } : {}),
                    ...(city ? { city } : {}),
                    ...(pincode ? { pincode } : {})
                });
            } catch (_) {}
        }

        res.json({
            success: true,
            message: 'Doctor professional profile updated successfully.',
            doctor: updatedDentist
        });
    } catch (err) {
        console.error('Update Doctor Profile Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to update doctor profile.' });
    }
};

// 10. UPDATE CLINIC DEPARTMENTS & SERVICES (Multi-Specialty Clinic Management)
exports.updateClinicDepartments = async (req, res) => {
    const { id } = req.params;
    const { clinicName, location, departments, services, pricing } = req.body;
    try {
        const mergedServices = Array.isArray(departments) && departments.length > 0
            ? departments
            : (Array.isArray(services) ? services : undefined);

        const updatePayload = {};
        if (clinicName) updatePayload.clinic_name = clinicName;
        if (location) updatePayload.location = location;
        if (mergedServices) updatePayload.services = mergedServices;
        if (pricing) updatePayload.pricing = pricing;

        let clinic = null;
        if (id && id !== 'default') {
            clinic = await Clinic.findByIdAndUpdate(id, updatePayload);
        } else if (clinicName) {
            const existing = await Clinic.findOne({ clinic_name: clinicName });
            if (existing) {
                clinic = await Clinic.findByIdAndUpdate(existing.id, updatePayload);
            } else {
                clinic = await Clinic.create({
                    clinic_name: clinicName,
                    location: location || 'GS HEALTH Multi-Specialty Center',
                    services: mergedServices || ['General Medicine', 'Dentistry'],
                    pricing: pricing || []
                });
            }
        }

        res.json({
            success: true,
            message: 'Clinic departments and services updated successfully.',
            clinic
        });
    } catch (err) {
        console.error('Update Clinic Departments Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to update clinic departments.' });
    }
};

// 11. ASSOCIATE EXISTING DOCTOR WITH CLINIC (No Duplicate Account Creation)
exports.associateClinicDoctor = async (req, res) => {
    const { clinicId } = req.params;
    const { doctorId, phone, email, licenseNumber, clinicName, specialty, consultationFee, availableDays, availableSlots } = req.body;
    try {
        const { User } = require('../models/Schemas');
        let resolvedClinicId = clinicId !== 'default' ? clinicId : undefined;
        if (clinicName && String(clinicName).trim()) {
            let clinic = await Clinic.findOne({ clinic_name: String(clinicName).trim() });
            if (!clinic) {
                clinic = await Clinic.create({
                    clinic_name: String(clinicName).trim(),
                    location: 'GS HEALTH Partner Clinic',
                    verified: true,
                    services: [specialty || 'General Medicine']
                });
            }
            if (clinic && clinic.id) resolvedClinicId = clinic.id;
        }

        let targetDoctor = null;
        if (doctorId) {
            targetDoctor = await Dentist.findById(doctorId);
        }
        if (!targetDoctor && (phone || email || licenseNumber)) {
            const allDentists = await Dentist.find({});
            targetDoctor = allDentists.find(d => {
                const dPhone = (d.phone || d.users?.phone || '').replace(/[^0-9]/g, '');
                const qPhone = (phone || '').replace(/[^0-9]/g, '');
                if (qPhone.length >= 10 && dPhone.length >= 10 && dPhone.slice(-10) === qPhone.slice(-10)) return true;
                if (email && (d.email || d.users?.email || '').toLowerCase() === String(email).trim().toLowerCase()) return true;
                if (licenseNumber && (d.license_number || '').toLowerCase() === String(licenseNumber).trim().toLowerCase()) return true;
                return false;
            });
        }

        if (!targetDoctor && (phone || email)) {
            const existingUser = email ? await User.findOne({ email: String(email).trim() }) : null;
            if (existingUser) {
                targetDoctor = await Dentist.create({
                    user_id: existingUser.id,
                    clinic_id: resolvedClinicId || null,
                    speciality: specialty || existingUser.specialty || 'General Medicine',
                    qualifications: existingUser.qualification || getDefaultQualificationForSpecialty(specialty || 'General Medicine'),
                    license_number: licenseNumber || 'MED-LIC-REG',
                    experience_years: existingUser.experienceYears || 5,
                    availability_status: 'Available'
                });
            }
        }

        if (!targetDoctor) {
            return res.status(404).json({
                success: false,
                message: 'No existing GS HEALTH doctor account found matching the provided details.'
            });
        }

        const updated = await Dentist.findByIdAndUpdate(targetDoctor.id, {
            ...(resolvedClinicId ? { clinic_id: resolvedClinicId } : {}),
            ...(specialty ? { speciality: specialty } : {}),
            availability_status: 'Available'
        });

        res.json({
            success: true,
            associated: true,
            message: 'Existing doctor associated with clinic successfully without creating a duplicate account.',
            doctor: updated || targetDoctor,
            extra: { consultationFee, availableDays, availableSlots }
        });
    } catch (err) {
        console.error('Associate Clinic Doctor Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to associate doctor with clinic.' });
    }
};

// 12. REMOVE DOCTOR FROM CLINIC (Preserves Global Doctor Account & Patient Records)
exports.removeDoctorFromClinic = async (req, res) => {
    const { doctorId } = req.params;
    try {
        if (!doctorId) {
            return res.status(400).json({ success: false, message: 'Doctor ID is required.' });
        }

        // Only clear clinic association (clinic_id: null) — never delete the user or dentist record
        const updated = await Dentist.findByIdAndUpdate(doctorId, {
            clinic_id: null
        });

        res.json({
            success: true,
            message: 'Doctor removed from clinic directory. Global doctor account and patient records preserved.',
            doctor: updated
        });
    } catch (err) {
        console.error('Remove Doctor From Clinic Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to remove doctor from clinic.' });
    }
};

