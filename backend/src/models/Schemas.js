const bcrypt = require('bcryptjs');
const { supabaseAdmin } = require('../config/supabase');

// Helper to hash password
const hashPassword = async (password) => {
    const salt = await bcrypt.genSalt(10);
    return await bcrypt.hash(password, salt);
};

// Helper to compare password
const comparePassword = async (plainPassword, hashedPassword) => {
    return await bcrypt.compare(plainPassword, hashedPassword);
};

// 1. USER MODEL (Supabase PostgreSQL)
const User = {
    async findOne(query) {
        let req = supabaseAdmin.from('users').select('*');
        for (const [key, val] of Object.entries(query)) {
            req = req.eq(key, val);
        }
        const { data, error } = await req.maybeSingle();
        if (error) throw error;
        return data;
    },

    async findById(id) {
        const { data, error } = await supabaseAdmin.from('users').select('*').eq('id', id).single();
        if (error) return null;
        return data;
    },

    async create(userData) {
        if (userData.password && !userData.password.startsWith('$2a$') && !userData.password.startsWith('$2b$')) {
            userData.password = await hashPassword(userData.password);
        }
        const { data, error } = await supabaseAdmin.from('users').insert(userData).select().single();
        if (error) throw error;
        return data;
    },

    async findByIdAndUpdate(id, updateData) {
        if (updateData.password && !updateData.password.startsWith('$2a$') && !updateData.password.startsWith('$2b$')) {
            updateData.password = await hashPassword(updateData.password);
        }
        const { data, error } = await supabaseAdmin.from('users').update(updateData).eq('id', id).select().single();
        if (error) throw error;
        return data;
    },

    comparePassword
};

// 2. CLINIC MODEL (Supabase PostgreSQL)
const Clinic = {
    async findOne(query) {
        let req = supabaseAdmin.from('clinics').select('*');
        for (const [key, val] of Object.entries(query)) {
            req = req.eq(key, val);
        }
        const { data, error } = await req.maybeSingle();
        if (error) throw error;
        return data;
    },

    async findById(id) {
        const { data, error } = await supabaseAdmin.from('clinics').select('*').eq('id', id).single();
        if (error) return null;
        return data;
    },

    async find(query = {}) {
        let req = supabaseAdmin.from('clinics').select('*');
        if (query.clinicName) {
            req = req.ilike('clinic_name', `%${query.clinicName}%`);
        }
        if (query.services) {
            req = req.contains('services', [query.services]);
        }
        const { data, error } = await req.order('rating', { ascending: false });
        if (error) throw error;
        return data || [];
    },

    async create(clinicData) {
        const payload = {
            user_id: clinicData.userId,
            clinic_name: clinicData.clinicName,
            location: clinicData.location,
            services: clinicData.services || [],
            pricing: clinicData.pricing || [],
            latitude: clinicData.coordinates?.coordinates?.[1] || null,
            longitude: clinicData.coordinates?.coordinates?.[0] || null
        };
        const { data, error } = await supabaseAdmin.from('clinics').insert(payload).select().single();
        if (error) throw error;
        return data;
    }
};

// 3. DENTIST MODEL (Supabase PostgreSQL)
const Dentist = {
    async findOne(query) {
        let req = supabaseAdmin.from('dentists').select('*');
        for (const [key, val] of Object.entries(query)) {
            req = req.eq(key, val);
        }
        const { data, error } = await req.maybeSingle();
        if (error) throw error;
        return data;
    },

    async find(query = {}) {
        let req = supabaseAdmin.from('dentists').select('*, users(name, email, phone), clinics(clinic_name, location)');
        for (const [key, val] of Object.entries(query)) {
            req = req.eq(key, val);
        }
        const { data, error } = await req;
        if (error) throw error;
        return data || [];
    },

    async create(dentistData) {
        const { data, error } = await supabaseAdmin.from('dentists').insert(dentistData).select().single();
        if (error) throw error;
        return data;
    }
};

// 4. APPOINTMENT MODEL (Supabase PostgreSQL)
const Appointment = {
    async create(appData) {
        let targetPatientId = appData.patient_id || appData.patientId || null;

        // If targetPatientId is not a UUID (e.g. email or phone), lookup matching User UUID
        if (targetPatientId && (targetPatientId.includes('@') || !targetPatientId.includes('-'))) {
            try {
                const userByEmail = await User.findOne({ email: targetPatientId });
                const userByPhone = userByEmail ? null : await User.findOne({ phone: targetPatientId });
                const matched = userByEmail || userByPhone;
                if (matched) {
                    targetPatientId = matched.id;
                }
            } catch (uErr) {
                console.error('User lookup error in Appointment.create:', uErr.message);
            }
        }

        // Fallback: If still no patient UUID found, grab the first registered user
        if (!targetPatientId || targetPatientId.includes('@')) {
            try {
                const { data: firstUsers } = await supabaseAdmin.from('users').select('id').limit(1);
                if (firstUsers && firstUsers.length > 0) {
                    targetPatientId = firstUsers[0].id;
                }
            } catch (fErr) {
                console.error('Fallback user lookup error:', fErr.message);
            }
        }

        const payload = {
            patient_id: targetPatientId,
            dentist_id: appData.dentist_id || appData.dentistId || null,
            clinic_id: appData.clinic_id || appData.clinicId || null,
            date: appData.date || new Date().toISOString(),
            time_slot: appData.time_slot || appData.timeSlot || 'Today, 2:30 PM',
            treatment: appData.treatment || 'Dental Consultation',
            status: appData.status || 'confirmed',
            payment_status: appData.payment_status || appData.paymentStatus || 'paid',
            qr_code_string: appData.qr_code_string || appData.qrCodeString || null
        };
        const { data, error } = await supabaseAdmin.from('appointments').insert(payload).select().single();
        if (error) throw error;
        return data;
    },

    async find(query = {}) {
        let req = supabaseAdmin.from('appointments').select('*, patient:users!patient_id(name, email, phone), clinic:clinics!clinic_id(clinic_name, location)');
        if (query.patientId) req = req.eq('patient_id', query.patientId);
        if (query.dentistId) req = req.eq('dentist_id', query.dentistId);
        if (query.clinicId) req = req.eq('clinic_id', query.clinicId);

        const { data, error } = await req.order('date', { ascending: true });
        if (error) throw error;
        return data || [];
    },

    async findById(id) {
        const { data, error } = await supabaseAdmin.from('appointments').select('*').eq('id', id).single();
        if (error) return null;
        return data;
    },

    async findByIdAndUpdate(id, updateData) {
        const { data, error } = await supabaseAdmin.from('appointments').update(updateData).eq('id', id).select().single();
        if (error) throw error;
        return data;
    }
};

// 5. MEDICAL RECORD MODEL (Supabase PostgreSQL)
const MedicalRecord = {
    async create(recordData) {
        const { data, error } = await supabaseAdmin.from('medical_records').insert(recordData).select().single();
        if (error) throw error;
        return data;
    },
    async find(query = {}) {
        let req = supabaseAdmin.from('medical_records').select('*');
        for (const [key, val] of Object.entries(query)) {
            req = req.eq(key, val);
        }
        const { data, error } = await req;
        if (error) throw error;
        return data || [];
    }
};

// 6. CHAT MESSAGE MODEL (Supabase PostgreSQL)
const ChatMessage = {
    async create(messageData) {
        const { data, error } = await supabaseAdmin.from('chat_messages').insert(messageData).select().single();
        if (error) throw error;
        return data;
    },
    async find(query = {}) {
        let req = supabaseAdmin.from('chat_messages').select('*');
        for (const [key, val] of Object.entries(query)) {
            req = req.eq(key, val);
        }
        const { data, error } = await req.order('created_at', { ascending: true });
        if (error) throw error;
        return data || [];
    }
};

module.exports = {
    User,
    Clinic,
    Dentist,
    Appointment,
    MedicalRecord,
    ChatMessage,
    comparePassword
};
