const bcrypt = require('bcryptjs');
const { supabaseAdmin } = require('../config/supabase');

// Helper to hash password
const hashPassword = async (password) => {
    const salt = await bcrypt.genSalt(10);
    return await bcrypt.hash(password, salt);
};

// Helper to compare password (supports bcrypt hash and plaintext fallback)
const comparePassword = async (plainPassword, hashedPassword) => {
    if (!hashedPassword) return false;
    if (plainPassword === hashedPassword) return true;
    try {
        return await bcrypt.compare(plainPassword, hashedPassword);
    } catch (_) {
        return plainPassword === hashedPassword;
    }
};

const PERMISSION_CONSTANTS = {
    PATIENT_VIEW: 'PATIENT_VIEW',
    PATIENT_ADD: 'PATIENT_ADD',
    PATIENT_EDIT: 'PATIENT_EDIT',

    DENTIST_VIEW: 'DENTIST_VIEW',
    DENTIST_CREATE: 'DENTIST_CREATE',
    DENTIST_EDIT: 'DENTIST_EDIT',

    ASSIGNMENT_VIEW: 'ASSIGNMENT_VIEW',
    ASSIGNMENT_CREATE: 'ASSIGNMENT_CREATE',

    APPOINTMENT_VIEW: 'APPOINTMENT_VIEW',
    APPOINTMENT_MANAGE: 'APPOINTMENT_MANAGE',

    PROBLEM_VIEW: 'PROBLEM_VIEW',
    PROBLEM_UPDATE: 'PROBLEM_UPDATE',

    REPORT_VIEW: 'REPORT_VIEW',
};

// 1. USER MODEL (Supabase PostgreSQL)
const User = {
    async findOne(query) {
        let req = supabaseAdmin.from('users').select('*');
        for (const [key, val] of Object.entries(query)) {
            req = req.eq(key, val);
        }
        req = req.limit(1);
        const { data, error } = await req;
        if (error) throw error;
        const record = (data && data.length > 0) ? data[0] : null;
        if (record && record.device_token && typeof record.device_token === 'string' && record.device_token.startsWith('{')) {
            try {
                const meta = JSON.parse(record.device_token);
                if (meta.languages && (!record.languages || record.languages.length === 0)) record.languages = meta.languages;
            } catch (_) {}
        }
        if (record && (record.role === 'Sub-Admin' || record.role === 'SUB_ADMIN')) {
            if (!record.permissions || record.permissions.length === 0) {
                record.permissions = await SubAdminPermission.getPermissionsForUser(record.id);
            }
            if ((!record.permissions || record.permissions.length === 0) && record.device_token && record.device_token.startsWith('{')) {
                try {
                    const meta = JSON.parse(record.device_token);
                    if (meta.permissions && Array.isArray(meta.permissions)) record.permissions = meta.permissions;
                    if (meta.status && !record.status) record.status = meta.status;
                } catch (_) {}
            }
        }
        return record;
    },


    async find(query = {}) {
        const unpackUser = (u) => {
            if (u && u.device_token && typeof u.device_token === 'string' && u.device_token.startsWith('{')) {
                try {
                    const meta = JSON.parse(u.device_token);
                    if (meta.status && !u.status) u.status = meta.status;
                    if (meta.permissions && (!u.permissions || u.permissions.length === 0)) u.permissions = meta.permissions;
                    if (meta.languages && (!u.languages || u.languages.length === 0)) u.languages = meta.languages;
                } catch (_) {}
            }
            return u;
        };

        try {
            let req = supabaseAdmin.from('users').select('*');
            if (query.role) {
                req = req.ilike('role', query.role);
            }
            for (const [key, val] of Object.entries(query)) {
                if (key !== 'role') {
                    req = req.eq(key, val);
                }
            }
            const { data, error } = await req.order('created_at', { ascending: false });
            if (error) {
                console.warn('⚠️ User find query error, falling back to simple select:', error.message);
                const simple = await supabaseAdmin.from('users').select('*');
                let result = simple.data || [];
                if (query.role) {
                    result = result.filter(u => u.role && u.role.toLowerCase() === query.role.toLowerCase());
                }
                return result.map(unpackUser);
            }
            return (data || []).map(unpackUser);
        } catch (e) {
            console.warn('⚠️ User find exception, falling back to simple select:', e.message);
            const simple = await supabaseAdmin.from('users').select('*');
            let result = simple.data || [];
            if (query.role) {
                result = result.filter(u => u.role && u.role.toLowerCase() === query.role.toLowerCase());
            }
            return result.map(unpackUser);
        }
    },

    async findById(id) {
        const { data, error } = await supabaseAdmin.from('users').select('*').eq('id', id).single();
        if (error) return null;
        if (data && data.device_token && typeof data.device_token === 'string' && data.device_token.startsWith('{')) {
            try {
                const meta = JSON.parse(data.device_token);
                if (meta.languages && (!data.languages || data.languages.length === 0)) data.languages = meta.languages;
            } catch (_) {}
        }
        if (data && (data.role === 'Sub-Admin' || data.role === 'SUB_ADMIN')) {
            if (!data.permissions || data.permissions.length === 0) {
                data.permissions = await SubAdminPermission.getPermissionsForUser(data.id);
            }
            if ((!data.permissions || data.permissions.length === 0) && data.device_token && data.device_token.startsWith('{')) {
                try {
                    const meta = JSON.parse(data.device_token);
                    if (meta.permissions && Array.isArray(meta.permissions)) data.permissions = meta.permissions;
                    if (meta.status && !data.status) data.status = meta.status;
                } catch (_) {}
            }
        }
        return data;
    },

    async create(userData) {
        if (!userData.password || (typeof userData.password === 'string' && userData.password.trim().length === 0)) {
            userData.password = `Pass_${(userData.phone || Date.now()).toString().slice(-6)}`;
        }
        if (userData.password && !userData.password.startsWith('$2a$') && !userData.password.startsWith('$2b$')) {
            userData.password = await hashPassword(userData.password);
        }
        if (!userData.email || (typeof userData.email === 'string' && userData.email.trim().length === 0)) {
            const cleanDigits = (userData.phone || '').replace(/[^0-9]/g, '') || Date.now().toString();
            userData.email = `user_${cleanDigits}@dentaguru.internal`;
        }

        // Pack extra profile metadata into device_token if not already a real push token
        if (!userData.device_token || userData.device_token.startsWith('{')) {
            const meta = {};
            if (userData.age) meta.age = userData.age;
            if (userData.gender) meta.gender = userData.gender;
            if (userData.blood_group) meta.bloodGroup = userData.blood_group;
            if (userData.emergency_contact) meta.emergencyContact = userData.emergency_contact;
            if (userData.languages) meta.languages = userData.languages;
            if (userData.permissions) meta.permissions = userData.permissions;
            if (userData.status) meta.status = userData.status;
            if (Object.keys(meta).length > 0) {
                userData.device_token = JSON.stringify(meta);
            }
        }

        const payload = {};
        for (const [key, val] of Object.entries(userData)) {
            if (val !== undefined && val !== null) {
                payload[key] = val;
            }
        }
        
        let insertedData = null;
        try {
            const { data, error } = await supabaseAdmin.from('users').insert(payload).select().single();
            if (error) throw error;
            insertedData = data;
        } catch (err) {
            // Fallback: Strip unmapped columns and use standard core columns
            const safePayload = {
                name: payload.name || 'User',
                email: payload.email,
                password: payload.password,
                phone: payload.phone,
                role: payload.role || 'Patient',
            };
            if (payload.city) safePayload.city = payload.city;
            if (payload.pincode) safePayload.pincode = payload.pincode;
            if (payload.state) safePayload.state = payload.state;
            if (payload.device_token) safePayload.device_token = payload.device_token;
            if (payload.biometric_token) safePayload.biometric_token = payload.biometric_token;

            const { data, error } = await supabaseAdmin.from('users').insert(safePayload).select().single();
            if (error) {
                console.error('❌ Supabase User Insert Error:', error.message);
                throw error;
            }
            insertedData = data;
        }

        if (insertedData && userData.permissions && Array.isArray(userData.permissions)) {
            await SubAdminPermission.setPermissionsForUser(insertedData.id, userData.permissions);
            insertedData.permissions = userData.permissions;
        }
        if (insertedData && userData.languages) {
            insertedData.languages = userData.languages;
        }

        return insertedData;
    },

    async findByIdAndUpdate(id, updateData) {
        if (updateData.password && !updateData.password.startsWith('$2a$') && !updateData.password.startsWith('$2b$')) {
            updateData.password = await hashPassword(updateData.password);
        }
        let updatedData = null;
        try {
            const { data, error } = await supabaseAdmin.from('users').update(updateData).eq('id', id).select().maybeSingle();
            if (error) throw error;
            updatedData = data;
        } catch (err) {
            const safeUpdate = { ...updateData };
            delete safeUpdate.permissions;
            delete safeUpdate.status;
            if (Object.keys(safeUpdate).length > 0) {
                const { data, error } = await supabaseAdmin.from('users').update(safeUpdate).eq('id', id).select().maybeSingle();
                if (error) throw error;
                updatedData = data;
            } else {
                updatedData = await this.findById(id);
            }
        }

        if (updateData.status || updateData.permissions) {
            try {
                const existing = await supabaseAdmin.from('users').select('device_token').eq('id', id).maybeSingle();
                let meta = {};
                if (existing.data && existing.data.device_token && existing.data.device_token.startsWith('{')) {
                    try { meta = JSON.parse(existing.data.device_token); } catch (_) {}
                }
                if (updateData.status) meta.status = updateData.status;
                if (updateData.permissions) meta.permissions = updateData.permissions;
                await supabaseAdmin.from('users').update({ device_token: JSON.stringify(meta) }).eq('id', id);
                if (updatedData) {
                    if (updateData.status) updatedData.status = updateData.status;
                    if (updateData.permissions) updatedData.permissions = updateData.permissions;
                }
            } catch (_) {}
        }

        if (!updatedData) {
            updatedData = await this.findById(id);
        }

        if (updateData.permissions && Array.isArray(updateData.permissions)) {
            await SubAdminPermission.setPermissionsForUser(id, updateData.permissions);
            if (updatedData) updatedData.permissions = updateData.permissions;
        }

        return updatedData;
    },

    comparePassword
};

// 1b. SUB-ADMIN PERMISSIONS MODEL (Supabase PostgreSQL)
const SubAdminPermission = {
    async getPermissionsForUser(userId) {
        try {
            const { data, error } = await supabaseAdmin
                .from('sub_admin_permissions')
                .select('permission')
                .eq('user_id', userId);
            if (error || !data) return [];
            return data.map(d => d.permission);
        } catch (_) {
            return [];
        }
    },

    async setPermissionsForUser(userId, permissions = []) {
        try {
            await supabaseAdmin
                .from('sub_admin_permissions')
                .delete()
                .eq('user_id', userId);

            if (permissions && permissions.length > 0) {
                const rows = permissions.map(p => ({
                    user_id: userId,
                    permission: (p || '').toString().trim().toUpperCase()
                })).filter(r => r.permission.length > 0);
                if (rows.length > 0) {
                    await supabaseAdmin.from('sub_admin_permissions').insert(rows);
                }
            }
        } catch (e) {
            console.warn('⚠️ sub_admin_permissions sync warning:', e.message);
        }
    }
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
        try {
            let req = supabaseAdmin.from('clinics').select('*');
            if (query.clinicName) {
                req = req.ilike('clinic_name', `%${query.clinicName}%`);
            }
            if (query.services) {
                req = req.contains('services', [query.services]);
            }
            const { data, error } = await req.order('created_at', { ascending: false });
            if (error) {
                console.warn('⚠️ Clinic query error, falling back to simple select:', error.message);
                const simple = await supabaseAdmin.from('clinics').select('*');
                return simple.data || [];
            }
            return data || [];
        } catch (e) {
            console.warn('⚠️ Clinic query exception, falling back to simple select:', e.message);
            const simple = await supabaseAdmin.from('clinics').select('*');
            return simple.data || [];
        }
    },

    async create(clinicData) {
        const rawUserId = clinicData.user_id || clinicData.userId;
        const isUuid = rawUserId && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(rawUserId.toString());
        const validUserId = isUuid ? rawUserId.toString() : null;

        const payload = {
            user_id: validUserId,
            clinic_name: clinicData.clinic_name || clinicData.clinicName || '',
            location: clinicData.location || '',
            rating: clinicData.rating || 5.0,
            reviews_count: clinicData.reviews_count || clinicData.reviewsCount || 0,
            verified: clinicData.verified !== undefined ? clinicData.verified : true,
            services: clinicData.services || clinicData.departments || ['General Dentistry', 'Gum Care', 'Root Canal'],
            pricing: clinicData.pricing || [],
            latitude: clinicData.latitude || clinicData.coordinates?.coordinates?.[1] || null,
            longitude: clinicData.longitude || clinicData.coordinates?.coordinates?.[0] || null
        };
        const { data, error } = await supabaseAdmin.from('clinics').insert(payload).select().single();
        if (error) {
            console.error('❌ Supabase Clinic Insert Error:', error.message);
            throw error;
        }
        return data;
    },

    async findByIdAndUpdate(id, updateData) {
        if (!id) return null;
        try {
            const payload = { ...updateData, updated_at: new Date().toISOString() };
            const { data, error } = await supabaseAdmin.from('clinics').update(payload).eq('id', id).select().maybeSingle();
            if (!error && data) return data;
        } catch (_) {}
        return await this.findById(id);
    }
};

const DENTAL_KEYWORDS = [
    'dentistry',
    'general dentistry',
    'orthodontics',
    'endodontics',
    'periodontics',
    'prosthodontics',
    'pediatric dentistry',
    'cosmetic dentistry',
    'oral surgery',
    'oral & maxillofacial surgery',
    'maxillofacial',
    'dental',
    'root canal',
    'implantology'
];

function isDentalSpecialtyText(text) {
    if (!text) return false;
    const lower = String(text).trim().toLowerCase();
    return DENTAL_KEYWORDS.some(k => lower.includes(k));
}

function getDefaultQualificationForSpecialty(spec) {
    if (!spec) return 'BDS, MDS';
    const lower = String(spec).trim().toLowerCase();
    if (isDentalSpecialtyText(lower)) return 'BDS, MDS';
    if (lower.includes('cardio')) return 'MBBS, MD, DM (Cardiology)';
    if (lower.includes('derma')) return 'MBBS, MD (Dermatology)';
    if (lower.includes('neuro')) return 'MBBS, MD, DM (Neurology)';
    if (lower.includes('ortho')) return 'MBBS, MS (Orthopedics)';
    if (lower.includes('pedia')) return 'MBBS, MD (Pediatrics)';
    if (lower.includes('gynec') || lower.includes('obstet')) return 'MBBS, MS (Obstetrics & Gynecology)';
    if (lower === 'ent' || lower.includes('otolaryng') || lower.includes('ear')) return 'MBBS, MS (ENT)';
    if (lower.includes('ophthal') || lower.includes('eye')) return 'MBBS, MS (Ophthalmology)';
    if (lower.includes('onco')) return 'MBBS, MD, DM (Oncology)';
    if (lower.includes('uro')) return 'MBBS, MS, MCh (Urology)';
    if (lower.includes('psych')) return 'MBBS, MD (Psychiatry)';
    if (lower.includes('gastro')) return 'MBBS, MD, DM (Gastroenterology)';
    if (lower.includes('pulmo') || lower.includes('respir')) return 'MBBS, MD (Pulmonology)';
    if (lower.includes('endocrin') || lower.includes('diabet')) return 'MBBS, MD, DM (Endocrinology)';
    if (lower.includes('general medicine') || lower.includes('internal medicine') || lower.includes('physician')) return 'MBBS, MD (General Medicine)';
    return 'MBBS, MD';
}

function matchesSpecialtyQuery(doctorSpec, filterSpec) {
    if (!filterSpec || filterSpec.trim().toLowerCase() === 'all') return true;
    const f = filterSpec.trim().toLowerCase();
    const d = (doctorSpec || 'General Dentistry').toString().trim().toLowerCase();
    if (d === f || d.includes(f) || f.includes(d)) return true;
    if (f === 'dentistry' || f === 'dental') {
        return isDentalSpecialtyText(d);
    }
    return false;
}

// 3. DENTIST / DOCTOR MODEL (Supabase PostgreSQL)
const Dentist = {
    async findOne(query) {
        if (!query) return null;
        try {
            let req = supabaseAdmin.from('dentists').select('*');
            if (query.$or && Array.isArray(query.$or)) {
                const conds = [];
                for (const item of query.$or) {
                    if (item.user_id && isUUID(item.user_id)) conds.push(`user_id.eq.${item.user_id}`);
                    if (item.id && isUUID(item.id)) conds.push(`id.eq.${item.id}`);
                    if (item._id && isUUID(item._id)) conds.push(`id.eq.${item._id}`);
                }
                if (conds.length > 0) {
                    req = req.or(conds.join(','));
                } else {
                    return null;
                }
            } else {
                for (const [key, val] of Object.entries(query)) {
                    if (key === '_id' || key === 'id') {
                        if (isUUID(val)) req = req.eq('id', val);
                    } else if (val !== undefined && val !== null) {
                        req = req.eq(key, val);
                    }
                }
            }
            const { data, error } = await req.maybeSingle();
            if (error) {
                return null;
            }
            return data;
        } catch (_) {
            return null;
        }
    },

    async find(query = {}) {
        try {
            let req = supabaseAdmin.from('dentists').select('*, users(name, email, phone, state, city, pincode, latitude, longitude, device_token, biometric_token), clinics(clinic_name, location)');
            // Apply direct dentists table filters
            if (query.state) {
                req = req.ilike('state', `%${query.state}%`);
            }
            if (query.city) {
                req = req.ilike('city', `%${query.city}%`);
            }
            if (query.pincode) {
                req = req.ilike('pincode', `%${query.pincode}%`);
            }
            if (query.availability_status) {
                req = req.eq('availability_status', query.availability_status);
            }
            const rawSpec = query.speciality || query.specialty;
            if (rawSpec && rawSpec.trim().toLowerCase() !== 'dentistry' && rawSpec.trim().toLowerCase() !== 'all') {
                req = req.ilike('speciality', `%${rawSpec.trim()}%`);
            }
            // clinic_id filter
            if (query.clinic_id) {
                req = req.eq('clinic_id', query.clinic_id);
            }
            const { data, error } = await req;
            let list = [];
            if (error) {
                console.warn('⚠️ Dentist query join failed, falling back to simple select:', error.message);
                const simple = await supabaseAdmin.from('dentists').select('*');
                list = simple.data || [];
            } else {
                list = data || [];
            }

            if (rawSpec && rawSpec.trim()) {
                list = list.filter(d => matchesSpecialtyQuery(d.speciality || d.specialty, rawSpec));
            }

            if (query.language && query.language.trim()) {
                const langLower = query.language.trim().toLowerCase();
                list = list.filter(d => {
                    if (d.languages && Array.isArray(d.languages)) {
                        return d.languages.some(l => (l || '').toLowerCase().includes(langLower));
                    }
                    if (typeof d.languages === 'string') {
                        return d.languages.toLowerCase().includes(langLower);
                    }
                    if (d.users?.device_token && d.users.device_token.startsWith('{')) {
                        try {
                            const meta = JSON.parse(d.users.device_token);
                            if (meta.languages && Array.isArray(meta.languages)) {
                                return meta.languages.some(l => (l || '').toLowerCase().includes(langLower));
                            }
                        } catch (_) {}
                    }
                    return false;
                });
            }
            return list;
        } catch (e) {
            console.warn('⚠️ Dentist query error, falling back to simple select:', e.message);
            const simple = await supabaseAdmin.from('dentists').select('*');
            return simple.data || [];
        }
    },

    async findById(id) {
        if (!id) return null;
        try {
            const isUUID = (str) => typeof str === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(str.trim());
            const str = String(id).trim();
            if (!isUUID(str)) {
                return await this.findOne({ $or: [{ name: str }, { email: str }] });
            }
            const { data, error } = await supabaseAdmin.from('dentists')
                .select('*, users(name, email, phone, state, city, pincode, device_token, biometric_token), clinics(clinic_name, location)')
                .or(`id.eq.${str},user_id.eq.${str}`)
                .maybeSingle();
            if (error || !data) {
                const simple = await supabaseAdmin.from('dentists').select('*').or(`id.eq.${str},user_id.eq.${str}`).maybeSingle();
                return simple.data || null;
            }
            return data;
        } catch (_) {
            return null;
        }
    },

    async create(dentistData) {
        const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
        const validUserId = (dentistData.user_id && uuidRegex.test(dentistData.user_id.toString())) ? dentistData.user_id.toString() : null;
        const validClinicId = (dentistData.clinic_id && uuidRegex.test(dentistData.clinic_id.toString())) ? dentistData.clinic_id.toString() : null;
        const resolvedSpec = dentistData.speciality || dentistData.specialty || 'General Dentistry';
        const resolvedQual = dentistData.qualifications || dentistData.qualification || getDefaultQualificationForSpecialty(resolvedSpec);

        const payload = {
            user_id: validUserId,
            clinic_id: validClinicId,
            speciality: resolvedSpec,
            license_number: dentistData.license_number || dentistData.licenseNumber || `REG-${validUserId ? validUserId.slice(0, 8) : Date.now()}`,
            experience_years: dentistData.experience_years || dentistData.experienceYears || 5,
            qualifications: resolvedQual,
            availability_status: dentistData.availability_status || dentistData.availabilityStatus || 'Available',
            verification_status: dentistData.verification_status || 'VERIFIED',
            rating: dentistData.rating || 5.0
        };
        if (dentistData.state) payload.state = dentistData.state;
        if (dentistData.city) payload.city = dentistData.city;
        if (dentistData.pincode) payload.pincode = dentistData.pincode;

        try {
            const { data, error } = await supabaseAdmin.from('dentists').insert(payload).select().single();
            if (error) throw error;
            return data;
        } catch (err) {
            console.error('❌ Supabase Dentist Insert Error:', err.message);
            throw err;
        }
    },

    async findByIdAndUpdate(id, updateData) {
        if (!id) return null;
        const str = String(id).trim();
        const payload = {};
        if (updateData.speciality || updateData.specialty) payload.speciality = updateData.speciality || updateData.specialty;
        if (updateData.qualifications || updateData.qualification) payload.qualifications = updateData.qualifications || updateData.qualification;
        if (updateData.experience_years !== undefined || updateData.experienceYears !== undefined) {
            payload.experience_years = parseInt(updateData.experience_years ?? updateData.experienceYears, 10) || 5;
        }
        if (updateData.license_number || updateData.licenseNumber) payload.license_number = updateData.license_number || updateData.licenseNumber;
        if (updateData.availability_status || updateData.availabilityStatus || updateData.status) {
            payload.availability_status = updateData.availability_status || updateData.availabilityStatus || updateData.status;
        }
        if (updateData.verification_status || updateData.verificationStatus) {
            payload.verification_status = updateData.verification_status || updateData.verificationStatus;
        }
        if (updateData.clinic_id !== undefined) payload.clinic_id = updateData.clinic_id;
        if (updateData.city !== undefined) payload.city = updateData.city;
        if (updateData.pincode !== undefined) payload.pincode = updateData.pincode;
        if (updateData.state !== undefined) payload.state = updateData.state;
        payload.updated_at = new Date().toISOString();

        try {
            const { data, error } = await supabaseAdmin
                .from('dentists')
                .update(payload)
                .or(`id.eq.${str},user_id.eq.${str}`)
                .select()
                .maybeSingle();
            if (!error && data) return data;
        } catch (e) {
            console.warn('⚠️ Dentist.findByIdAndUpdate warning:', e.message);
        }
        return await this.findById(str);
    }
};

// 4. APPOINTMENT MODEL (Supabase PostgreSQL)
const isUUID = (str) => typeof str === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(str.trim());

async function resolveDentistIds(input) {
    if (!input) return { dentistTableId: null, userTableId: null, allIds: [] };
    const str = String(input).trim();
    let dentistTableId = null;
    let userTableId = null;

    if (isUUID(str)) {
        try {
            const { data: d } = await supabaseAdmin.from('dentists').select('id, user_id').or(`id.eq.${str},user_id.eq.${str}`).maybeSingle();
            if (d) {
                dentistTableId = d.id;
                userTableId = d.user_id;
            }
        } catch (_) {}
    }

    if (!dentistTableId) {
        try {
            const { data: u } = await supabaseAdmin.from('users').select('id').or(`email.eq.${str},name.eq.${str}`).maybeSingle();
            if (u) {
                userTableId = u.id;
                const { data: d } = await supabaseAdmin.from('dentists').select('id, user_id').eq('user_id', u.id).maybeSingle();
                if (d) {
                    dentistTableId = d.id;
                }
            }
        } catch (_) {}
    }

    const allIds = [dentistTableId, userTableId, str].filter(Boolean).filter((v, i, a) => a.indexOf(v) === i);
    return { dentistTableId: dentistTableId, userTableId, allIds };
}

async function resolveUserUuid(input) {
    if (!input) return null;
    if (typeof input === 'object' && input.$in && Array.isArray(input.$in)) {
        const uuids = [];
        for (const item of input.$in) {
            const res = await resolveUserUuid(item);
            if (res && !uuids.includes(res)) uuids.push(res);
        }
        return uuids;
    }
    const str = String(input).trim();
    if (isUUID(str)) return str;

    try {
        let user = await User.findOne({ email: str });
        if (!user) user = await User.findOne({ phone: str });
        if (!user) user = await User.findOne({ name: str });
        if (!user) {
            // Try case-insensitive / partial match without "Dr." or "Dr "
            const clean = str.replace(/^dr\.?\s+/i, '').trim();
            const { data } = await supabaseAdmin.from('users').select('id, name, role').or(`name.ilike.%${clean}%,email.ilike.%${clean}%`).limit(1);
            if (data && data.length > 0) user = data[0];
        }
        if (user) return user.id;
    } catch (e) {
        console.error('Error resolving user UUID:', e.message);
    }
    return null;
}

async function resolveDentistUuid(input) {
    if (!input) return null;
    if (typeof input === 'object' && input.$in && Array.isArray(input.$in)) {
        const uuids = [];
        for (const item of input.$in) {
            const res = await resolveDentistUuid(item);
            if (res && !uuids.includes(res)) uuids.push(res);
        }
        return uuids;
    }
    const { dentistTableId } = await resolveDentistIds(input);
    return dentistTableId;
}

async function resolveClinicUuid(input) {
    if (!input) return null;
    const str = String(input).trim();
    if (isUUID(str)) return str;

    try {
        let c = await Clinic.findOne({ clinic_name: str });
        if (c && c.id) return c.id;
    } catch (e) {
        console.error('Error resolving clinic UUID:', e.message);
    }
    return null;
}

// 4. APPOINTMENT MODEL (Supabase PostgreSQL)
const Appointment = {
    async create(appData) {
        const patientId = await resolveUserUuid(appData.patient_id || appData.patientId);
        const dentistId = await resolveDentistUuid(appData.dentist_id || appData.dentistId);
        const clinicId = await resolveClinicUuid(appData.clinic_id || appData.clinicId);

        const apptDate = appData.date || appData.appointment_date || appData.appointmentDate || new Date().toISOString();
        const timeSlot = appData.time_slot || appData.timeSlot || 'Today, 2:30 PM';
        const treatmentName = appData.treatment || appData.notes || 'Dental Consultation';
        const statusVal = appData.status || 'PENDING';

        const payload = {
            patient_id: patientId,
            dentist_id: dentistId,
            clinic_id: clinicId,
            date: apptDate,
            time_slot: timeSlot,
            treatment: treatmentName,
            status: statusVal,
            qr_code_string: appData.qr_code_string || `DENTAGURU-${patientId || 'PATIENT'}-${Date.now()}`
        };

        try {
            const { data, error } = await supabaseAdmin.from('appointments').insert(payload).select().single();
            if (!error && data) return data;
            if (error) {
                // Fallback attempt with legacy column names
                const legacyPayload = {
                    patient_id: patientId,
                    dentist_id: dentistId,
                    clinic_id: clinicId,
                    appointment_date: apptDate,
                    status: statusVal,
                    type: 'In-Person',
                    notes: treatmentName
                };
                const { data: d2, error: e2 } = await supabaseAdmin.from('appointments').insert(legacyPayload).select().single();
                if (e2) throw e2;
                return d2;
            }
        } catch (err) {
            console.error('❌ Supabase Appointment Insert Error:', err.message);
            throw err;
        }
    },

    async find(query = {}) {
        let req = supabaseAdmin.from('appointments').select('*, patient:users!patient_id(name, email, phone), dentist:dentists!dentist_id(*, users(name, phone, email)), clinic:clinics!clinic_id(*)');
        const pId = query.patient_id || query.patientId;
        if (pId) {
            const resolvedP = await resolveUserUuid(pId);
            if (Array.isArray(resolvedP) && resolvedP.length > 0) {
                req = req.in('patient_id', resolvedP);
            } else if (typeof resolvedP === 'string' && resolvedP.length > 0) {
                req = req.eq('patient_id', resolvedP);
            } else {
                return [];
            }
        }
        const dId = query.dentist_id || query.dentistId;
        if (dId) {
            const { dentistTableId, userTableId } = await resolveDentistIds(dId);
            if (dentistTableId && userTableId && dentistTableId !== userTableId) {
                req = req.or(`dentist_id.eq.${dentistTableId},dentist_id.eq.${userTableId}`);
            } else if (dentistTableId) {
                req = req.eq('dentist_id', dentistTableId);
            } else {
                return [];
            }
        }
        if (query.status) {
            req = req.eq('status', query.status);
        }
        const { data, error } = await req.order('created_at', { ascending: false });
        if (error) {
            console.warn('⚠️ Appointment query error, falling back to simple select:', error.message);
            const simple = await supabaseAdmin.from('appointments').select('*').order('created_at', { ascending: false });
            return simple.data || [];
        }
        return data || [];
    },

    async findById(id) {
        const { data, error } = await supabaseAdmin.from('appointments').select('*, patient:users!patient_id(name, email, phone), dentist:dentists!dentist_id(*, users(name, phone, email)), clinic:clinics!clinic_id(*)').eq('id', id).single();
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
        const patientId = await resolveUserUuid(recordData.patient_id || recordData.patientId);
        const rawDentist = recordData.dentist_id || recordData.dentistId;
        const dentistId = rawDentist ? await resolveDentistUuid(rawDentist) : null;

        const notesVal = typeof recordData.notes === 'object' && recordData.notes !== null
            ? JSON.stringify(recordData.notes)
            : (recordData.notes || recordData.clinical_notes || recordData.clinicalNotes || '');

        const prescriptionsVal = Array.isArray(recordData.prescriptions)
            ? recordData.prescriptions
            : (Array.isArray(recordData.items) ? recordData.items : []);

        const xrayUrls = Array.isArray(recordData.xray_urls)
            ? recordData.xray_urls
            : (Array.isArray(recordData.xrayUrls) ? recordData.xrayUrls : []);

        const labReportUrls = Array.isArray(recordData.lab_report_urls)
            ? recordData.lab_report_urls
            : (Array.isArray(recordData.labReportUrls) ? recordData.labReportUrls : []);

        const payload = {
            patient_id: patientId,
            dentist_id: dentistId,
            diagnosis: recordData.diagnosis || recordData.title || 'Dental Health Record',
            notes: notesVal,
            prescriptions: prescriptionsVal,
            xray_urls: xrayUrls,
            lab_report_urls: labReportUrls
        };

        const { data, error } = await supabaseAdmin.from('medical_records').insert(payload).select().single();
        if (error) {
            console.error('❌ Supabase MedicalRecord Insert Error:', error.message);
            throw error;
        }
        return data;
    },

    async find(query = {}) {
        let req = supabaseAdmin.from('medical_records').select('*, patient:users!patient_id(id, name, email, phone)');
        const pId = query.patient_id || query.patientId;
        if (pId) {
            const resolvedP = await resolveUserUuid(pId);
            if (Array.isArray(resolvedP) && resolvedP.length > 0) {
                req = req.in('patient_id', resolvedP);
            } else if (typeof resolvedP === 'string' && resolvedP.length > 0) {
                req = req.eq('patient_id', resolvedP);
            } else {
                return [];
            }
        }
        const { data, error } = await req.order('created_at', { ascending: false });
        if (error) {
            // Fallback without join if foreign key join fails
            let simpleReq = supabaseAdmin.from('medical_records').select('*');
            if (pId) {
                const resolvedP = await resolveUserUuid(pId);
                if (Array.isArray(resolvedP) && resolvedP.length > 0) {
                    simpleReq = simpleReq.in('patient_id', resolvedP);
                } else if (typeof resolvedP === 'string' && resolvedP.length > 0) {
                    simpleReq = simpleReq.eq('patient_id', resolvedP);
                } else {
                    return [];
                }
            }
            const simple = await simpleReq.order('created_at', { ascending: false });
            if (simple.error) throw simple.error;
            return simple.data || [];
        }
        return data || [];
    },

    async findById(id) {
        if (!id || !isUUID(String(id).trim())) return null;
        const { data, error } = await supabaseAdmin
            .from('medical_records')
            .select('*, patient:users!patient_id(id, name, email, phone)')
            .eq('id', String(id).trim())
            .maybeSingle();
        if (error || !data) {
            const simple = await supabaseAdmin
                .from('medical_records')
                .select('*')
                .eq('id', String(id).trim())
                .maybeSingle();
            return simple.data || null;
        }
        return data;
    },

    async findByIdAndUpdate(id, updateData) {
        if (!id || !isUUID(String(id).trim())) return null;
        const payload = {
            ...updateData,
            updated_at: new Date().toISOString()
        };
        const { data, error } = await supabaseAdmin
            .from('medical_records')
            .update(payload)
            .eq('id', String(id).trim())
            .select()
            .single();
        if (error) throw error;
        return data;
    },

    async findByIdAndDelete(id) {
        if (!id || !isUUID(String(id).trim())) return null;
        const { data, error } = await supabaseAdmin
            .from('medical_records')
            .delete()
            .eq('id', String(id).trim())
            .select()
            .maybeSingle();
        if (error) throw error;
        return data;
    }
};

// 6. CHAT MESSAGE MODEL (Supabase PostgreSQL)
const normalizeChatRoomId = (roomId) => {
    if (!roomId) return 'PATIENT_GENERAL';
    const str = String(roomId).trim().toUpperCase();
    return str.replace(/[-]/g, '_');
};

const ChatMessage = {
    async create(messageData) {
        const rawSender = messageData.sender_id || messageData.senderId || '';
        let senderId = null;

        if (rawSender) {
            const str = String(rawSender).trim();
            if (isUUID(str)) {
                senderId = str;
            } else {
                senderId = await resolveUserUuid(str);
            }
        }

        let receiverId = null;
        const rawReceiver = messageData.receiver_id || messageData.receiverId;
        if (rawReceiver) {
            const strR = String(rawReceiver).trim();
            if (isUUID(strR)) {
                receiverId = strR;
            } else {
                receiverId = await resolveUserUuid(strR);
            }
        }

        const normalizedRoom = normalizeChatRoomId(messageData.room_id || messageData.roomId);

        const payload = {
            room_id: normalizedRoom,
            sender_id: senderId || null,
            receiver_id: receiverId || null,
            message: messageData.message || '',
            type: messageData.type || 'text',
            read: messageData.read ?? false
        };

        const { data, error } = await supabaseAdmin.from('chat_messages').insert(payload).select('*, sender:users!sender_id(id, name, email, role), receiver:users!receiver_id(id, name, email, role)');
        if (error) {
            console.error('❌ Supabase ChatMessage Insert Error:', error.message);
            throw error;
        }
        return (data && data.length > 0) ? data[0] : payload;
    },

    async find(query = {}, options = {}) {
        // Enforce DB/Query-Level Access Control if caller user is passed in options
        if (options.user) {
            const role = (options.user.role || '').toString().trim().toLowerCase();
            const isSubAdmin = role === 'sub-admin' || role === 'subadmin' || role === 'sub_admin';

            // Sub-Admins NEVER receive chat messages
            if (isSubAdmin) {
                return [];
            }
        }

        let req = supabaseAdmin.from('chat_messages').select('*, sender:users!sender_id(id, name, email, role), receiver:users!receiver_id(id, name, email, role)');
        const rawRoom = query.room_id || query.roomId;
        if (rawRoom) {
            const normalized = normalizeChatRoomId(rawRoom);
            const hyphenated = normalized.replace(/_/g, '-');
            req = req.or(`room_id.eq.${normalized},room_id.eq.${hyphenated},room_id.eq.${rawRoom}`);
        }
        const sId = query.sender_id || query.senderId;
        if (sId) {
            const resolvedS = await resolveUserUuid(sId);
            if (typeof resolvedS === 'string' && resolvedS.length > 0) req = req.eq('sender_id', resolvedS);
        }
        const { data, error } = await req.order('created_at', { ascending: true });
        if (error) {
            // Fallback to simple sender select if receiver foreign key is missing
            const fallback = await supabaseAdmin.from('chat_messages').select('*, sender:users!sender_id(id, name, email, role)').order('created_at', { ascending: true });
            let msgs = fallback.data || [];
            if (rawRoom) {
                const norm = normalizeChatRoomId(rawRoom);
                msgs = msgs.filter(m => normalizeChatRoomId(m.room_id) === norm);
            }
            return msgs;
        }
        return data || [];
    },

    async getConversations(user) {
        if (!user) return [];
        const role = (user.role || '').toString().trim().toLowerCase();
        const isMainAdmin = role === 'admin' || role === 'primaryadmin' || role === 'primary_admin' || role === 'superadmin' || role === 'super_admin' || user.email === 'admin@dentaguru.com';
        const isSubAdmin = role === 'sub-admin' || role === 'subadmin' || role === 'sub_admin';

        // Sub-Admins are strictly forbidden
        if (isSubAdmin) {
            return [];
        }

        try {
            // Fetch all chat messages with sender info
            const { data: messages, error } = await supabaseAdmin
                .from('chat_messages')
                .select('*, sender:users!sender_id(id, name, email, role), receiver:users!receiver_id(id, name, email, role)')
                .order('created_at', { ascending: false });

            if (error) {
                const fallback = await supabaseAdmin
                    .from('chat_messages')
                    .select('*, sender:users!sender_id(id, name, email, role)')
                    .order('created_at', { ascending: false });
                if (!fallback.data || fallback.data.length === 0) return [];
                return this._assembleConversations(fallback.data, user, isMainAdmin, role);
            }

            if (!messages || messages.length === 0) return [];
            return this._assembleConversations(messages, user, isMainAdmin, role);
        } catch (e) {
            console.error('Error in getConversations:', e.message);
            return [];
        }
    },

    async _assembleConversations(messages, user, isMainAdmin, role) {
        // Group by normalized room_id
        const roomMap = new Map();
        for (const msg of messages) {
            const rId = normalizeChatRoomId(msg.room_id);
            if (!roomMap.has(rId)) {
                roomMap.set(rId, {
                    roomId: rId,
                    lastMessage: msg.message,
                    lastMessageType: msg.type,
                    lastMessageTime: msg.created_at,
                    lastSenderName: msg.sender?.name || (msg.type === 'doctor' ? 'Doctor' : 'Patient'),
                    lastSenderRole: msg.sender?.role || (msg.type === 'doctor' ? 'Dentist' : 'Patient'),
                    doctorName: null,
                    patientName: null,
                    totalMessages: 0,
                    unreadCount: 0
                });
            }
            const thread = roomMap.get(rId);
            thread.totalMessages += 1;
            if (!msg.read && msg.sender_id !== user?.id) {
                thread.unreadCount += 1;
            }
            thread.senderIds = thread.senderIds || new Set();
            thread.receiverIds = thread.receiverIds || new Set();
            if (msg.sender_id) thread.senderIds.add(msg.sender_id);
            if (msg.receiver_id) thread.receiverIds.add(msg.receiver_id);

            // Resolve doctor name from messages
            if (!thread.doctorName && (msg.type === 'doctor' || msg.sender?.role === 'Dentist')) {
                let dName = msg.sender?.name || '';
                if (dName && !dName.toLowerCase().startsWith('dr.') && !dName.toLowerCase().startsWith('dr ')) {
                    dName = `Dr. ${dName}`;
                }
                if (dName) thread.doctorName = dName;
            }
            // Resolve patient name from messages
            if (!thread.patientName && (msg.type === 'patient' || msg.sender?.role === 'Patient')) {
                if (msg.sender?.name) thread.patientName = msg.sender.name;
            }
        }

        // Fetch consultation requests and appointments to resolve doctor names and patient names
        let doctorLookup = new Map();
        let patientLookup = new Map();
        try {
            const { data: problemReqs } = await supabaseAdmin
                .from('patient_problem_requests')
                .select('patient_name, patient_id, suggested_dentist_id, suggested_dentist:dentists!suggested_dentist_id(id, user_id, users(name))');
            if (problemReqs) {
                for (const pr of problemReqs) {
                    const dName = pr.suggested_dentist?.users?.name;
                    if (dName) {
                        const formatted = dName.toLowerCase().startsWith('dr') ? dName : `Dr. ${dName}`;
                        if (pr.patient_name) doctorLookup.set(pr.patient_name.toLowerCase(), formatted);
                        if (pr.patient_id) doctorLookup.set(String(pr.patient_id).toLowerCase(), formatted);
                    }
                    if (pr.patient_name && pr.patient_id) {
                        patientLookup.set(String(pr.patient_id).toLowerCase(), pr.patient_name);
                    }
                }
            }

            const { data: appointments } = await supabaseAdmin
                .from('appointments')
                .select('patient_id, dentist_id, dentist:dentists!dentist_id(id, user_id, users(name)), patient:users!patient_id(name)');
            if (appointments) {
                for (const ap of appointments) {
                    const dName = ap.dentist?.users?.name;
                    if (dName) {
                        const formatted = dName.toLowerCase().startsWith('dr') ? dName : `Dr. ${dName}`;
                        if (ap.patient_id) doctorLookup.set(String(ap.patient_id).toLowerCase(), formatted);
                    }
                    if (ap.patient?.name && ap.patient_id) {
                        patientLookup.set(String(ap.patient_id).toLowerCase(), ap.patient.name);
                    }
                }
            }
        } catch (_) {}

        // Extract clean patient names and doctor names for each room
        const conversations = [];
        for (const [roomId, thread] of roomMap.entries()) {
            let inferredPatientName = thread.patientName;
            let inferredDoctorName = thread.doctorName;

            // Handle pair room syntax: CHAT_PATIENTNAME_DOCTORNAME
            if (roomId.startsWith('CHAT_')) {
                const parts = roomId.replace(/^CHAT_/, '').split('_');
                if (parts.length >= 2) {
                    if (!inferredPatientName) {
                        inferredPatientName = parts[0].charAt(0).toUpperCase() + parts[0].slice(1).toLowerCase();
                    }
                    if (!inferredDoctorName) {
                        const dToken = parts.slice(1).join(' ');
                        inferredDoctorName = dToken.toLowerCase().startsWith('dr') ? dToken : `Dr. ${dToken.charAt(0).toUpperCase() + dToken.slice(1).toLowerCase()}`;
                    }
                }
            }

            if (!inferredPatientName) {
                inferredPatientName = roomId.replace(/^PATIENT[-_]/i, '').replace(/_/g, ' ');
                if (!inferredPatientName || inferredPatientName.length === 0) {
                    inferredPatientName = 'Patient Consultation';
                }
                inferredPatientName = inferredPatientName.split(' ')
                    .map(word => word.charAt(0).toUpperCase() + word.slice(1).toLowerCase())
                    .join(' ');
            }

            const cleanKey = inferredPatientName.toLowerCase();
            let resolvedDoc = inferredDoctorName;
            if (!resolvedDoc) {
                for (const [k, v] of doctorLookup.entries()) {
                    if (cleanKey.includes(k) || k.includes(cleanKey) || roomId.toLowerCase().includes(k)) {
                        resolvedDoc = v;
                        break;
                    }
                }
            }
            if (!resolvedDoc) {
                resolvedDoc = 'Attending Dentist';
            }

            const conversation = {
                roomId,
                patientName: inferredPatientName,
                doctorName: resolvedDoc,
                lastMessage: thread.lastMessage,
                lastMessageType: thread.lastMessageType,
                lastMessageTime: thread.lastMessageTime,
                totalMessages: thread.totalMessages,
                unreadCount: thread.unreadCount
            };

            if (isMainAdmin) {
                conversations.push(conversation);
            } else if (role === 'dentist' || role === 'doctor') {
                const userDocName = (user?.name || '').replace(/^Dr\.\s*/i, '').trim().toLowerCase();
                const roomNorm = roomId.toLowerCase();
                const threadHasUser = (thread.senderIds && thread.senderIds.has(user.id)) ||
                                      (thread.receiverIds && thread.receiverIds.has(user.id));
                const nameMatches = userDocName.length > 0 && (
                    resolvedDoc.toLowerCase().includes(userDocName) ||
                    roomNorm.includes(userDocName)
                );

                if (threadHasUser || nameMatches) {
                    conversations.push(conversation);
                }
            } else if (role === 'patient') {
                const userNameNorm = (user?.name || '').toUpperCase().replace(/[^A-Z0-9]/g, '');
                const roomNorm = roomId.toUpperCase().replace(/[^A-Z0-9]/g, '');
                const threadHasUser = (thread.senderIds && thread.senderIds.has(user.id)) ||
                                      (thread.receiverIds && thread.receiverIds.has(user.id));
                if (threadHasUser || roomNorm.includes(userNameNorm) || (user?.id && roomNorm.includes(user.id))) {
                    conversations.push(conversation);
                }
            }
        }

        return conversations;
    },

    async delete(query = {}) {
        let req = supabaseAdmin.from('chat_messages').delete();
        if (query.messageId || query.id) {
            req = req.eq('id', query.messageId || query.id);
        } else if (query.roomId || query.room_id) {
            const raw = query.roomId || query.room_id;
            const norm = normalizeChatRoomId(raw);
            const hyph = norm.replace(/_/g, '-');
            req = req.or(`room_id.eq.${norm},room_id.eq.${hyph},room_id.eq.${raw}`);
        } else {
            return false;
        }
        const { error } = await req;
        if (error) throw error;
        return true;
    }
};


// 7. PATIENT PROBLEM REQUEST MODEL (Supabase PostgreSQL)
const PatientProblemRequest = {
    async create(reqData) {
        const patientId = await resolveUserUuid(reqData.patient_id || reqData.patientId);
        const suggestedDentistId = reqData.suggested_dentist_id || reqData.suggestedDentistId ? await resolveDentistUuid(reqData.suggested_dentist_id || reqData.suggestedDentistId) : null;
        const payload = {
            patient_id: patientId,
            patient_name: reqData.patient_name || reqData.patientName || null,
            patient_phone: reqData.patient_phone || reqData.patientPhone || null,
            city: reqData.city || null,
            pincode: reqData.pincode || null,
            state: reqData.state || null,
            problem_category: reqData.problem_category || reqData.problemCategory || 'General Dental Problem',
            problem_description: reqData.problem_description || reqData.problemDescription || '',
            symptoms: reqData.symptoms || '',
            preferred_location: reqData.preferred_location || reqData.preferredLocation || null,
            attachments: reqData.attachments || [],
            status: reqData.status || (suggestedDentistId ? 'DENTIST_ASSIGNED' : 'PENDING_ADMIN_REVIEW'),
            suggested_dentist_id: suggestedDentistId,
            admin_notes: reqData.admin_notes || reqData.adminNotes || null
        };
        try {
            const { data, error } = await supabaseAdmin.from('patient_problem_requests').insert(payload).select().single();
            if (error) throw error;
            return data;
        } catch (err) {
            // Fallback if some columns don't exist in schema
            const safePayload = {
                patient_id: patientId,
                problem_category: reqData.problem_category || reqData.problemCategory || 'General Dental Problem',
                problem_description: reqData.problem_description || reqData.problemDescription || '',
                symptoms: reqData.symptoms || '',
                preferred_location: reqData.preferred_location || reqData.preferredLocation || null,
                attachments: reqData.attachments || [],
                status: reqData.status || (suggestedDentistId ? 'DENTIST_ASSIGNED' : 'PENDING_ADMIN_REVIEW'),
                suggested_dentist_id: suggestedDentistId,
                admin_notes: reqData.admin_notes || reqData.adminNotes || null
            };
            const { data, error } = await supabaseAdmin.from('patient_problem_requests').insert(safePayload).select().single();
            if (error) {
                console.error('❌ Supabase PatientProblemRequest Insert Error:', error.message);
                throw error;
            }
            return data;
        }
    },

    async find(query = {}) {
        let req = supabaseAdmin.from('patient_problem_requests').select('*, patient:users!patient_id(name, email, phone), suggested_dentist:dentists!suggested_dentist_id(*, users(name, phone, email), clinics(clinic_name, location))');
        if (query.status) {
            req = req.eq('status', query.status);
        }
        if (query.patient_id || query.patientId) {
            const pId = await resolveUserUuid(query.patient_id || query.patientId);
            if (Array.isArray(pId) && pId.length > 0) {
                req = req.in('patient_id', pId);
            } else if (typeof pId === 'string' && pId.length > 0) {
                req = req.eq('patient_id', pId);
            } else {
                return [];
            }
        }

        // Strict Dentist Filtering: Check both direct assignment and dentist_suggestions
        const dId = query.suggested_dentist_id || query.dentist_id || query.assigned_doctor_id || query.dentistId;
        if (dId) {
            const rawList = (typeof dId === 'object' && dId.$in) ? dId.$in : (Array.isArray(dId) ? dId : [dId]);
            const dList = [];
            for (const item of rawList) {
                if (!item) continue;
                const str = String(item).trim();
                if (isUUID(str)) {
                    if (!dList.includes(str)) dList.push(str);
                    try {
                        const d = await supabaseAdmin.from('dentists').select('id, user_id').or(`id.eq.${str},user_id.eq.${str}`).maybeSingle();
                        if (d && d.data) {
                            if (d.data.id && !dList.includes(d.data.id)) dList.push(d.data.id);
                            if (d.data.user_id && !dList.includes(d.data.user_id)) dList.push(d.data.user_id);
                        }
                    } catch (_) {}
                } else {
                    const resolved = await resolveDentistUuid(str);
                    if (resolved && !dList.includes(resolved)) dList.push(resolved);
                }
            }

            if (dList.length > 0) {
                let suggestedReqIds = [];
                try {
                    const conds = dList.map(id => `dentist_id.eq.${id}`).join(',');
                    const { data: sData } = await supabaseAdmin.from('dentist_suggestions').select('request_id').or(conds);
                    if (sData && sData.length > 0) {
                        suggestedReqIds = sData.map(s => s.request_id).filter(Boolean);
                    }
                } catch (_) {}

                const orParts = [];
                for (const id of dList) {
                    orParts.push(`suggested_dentist_id.eq.${id}`);
                }
                for (const rId of suggestedReqIds) {
                    if (isUUID(rId)) orParts.push(`id.eq.${rId}`);
                }

                if (orParts.length > 0) {
                    req = req.or(orParts.join(','));
                } else {
                    return [];
                }
            } else {
                return [];
            }
        }

        const { data, error } = await req.order('created_at', { ascending: false });
        if (error) {
            console.warn('⚠️ Problem requests query error:', error.message);
            if (dId || query.patient_id || query.patientId) {
                return [];
            }
            const simple = await supabaseAdmin.from('patient_problem_requests').select('*').order('created_at', { ascending: false });
            return simple.data || [];
        }
        return data || [];
    },

    async findById(id) {
        const { data, error } = await supabaseAdmin.from('patient_problem_requests').select('*, patient:users!patient_id(name, email, phone), suggested_dentist:dentists!suggested_dentist_id(*, users(name, phone, email), clinics(clinic_name, location))').eq('id', id).maybeSingle();
        if (error || !data) {
            const simple = await supabaseAdmin.from('patient_problem_requests').select('*').eq('id', id).maybeSingle();
            return simple.data || null;
        }
        return data;
    },

    async findByIdAndUpdate(id, updateData) {
        const { data, error } = await supabaseAdmin.from('patient_problem_requests').update(updateData).eq('id', id).select().single();
        if (error) throw error;
        return data;
    },

    async findByIdAndDelete(id) {
        const { data, error } = await supabaseAdmin.from('patient_problem_requests').delete().eq('id', id).select().single();
        if (error) {
            console.error('❌ Supabase PatientProblemRequest Delete Error:', error.message);
            return null;
        }
        return data;
    }
};

// 8. DENTIST SUGGESTION MODEL (Supabase PostgreSQL)
const DentistSuggestion = {
    async create(suggestionData) {
        const requestId = suggestionData.request_id || suggestionData.requestId;
        const patientId = await resolveUserUuid(suggestionData.patient_id || suggestionData.patientId);
        const adminId = await resolveUserUuid(suggestionData.admin_id || suggestionData.adminId);
        const dentistId = await resolveDentistUuid(suggestionData.dentist_id || suggestionData.dentistId);

        const payload = {
            request_id: requestId,
            patient_id: patientId,
            admin_id: adminId,
            dentist_id: dentistId,
            patient_state: suggestionData.patient_state || suggestionData.patientState || '',
            patient_city: suggestionData.patient_city || suggestionData.patientCity || '',
            patient_pincode: suggestionData.patient_pincode || suggestionData.patientPincode || '',
            dentist_state: suggestionData.dentist_state || suggestionData.dentistState || '',
            dentist_city: suggestionData.dentist_city || suggestionData.dentistCity || '',
            dentist_pincode: suggestionData.dentist_pincode || suggestionData.dentistPincode || '',
            status: suggestionData.status || 'SUGGESTED',
            notes: suggestionData.notes || null
        };
        const { data, error } = await supabaseAdmin.from('dentist_suggestions').insert(payload).select().single();
        if (error) {
            console.error('❌ Supabase DentistSuggestion Insert Error:', error.message);
            throw error;
        }
        return data;
    },

    async find(query = {}) {
        let req = supabaseAdmin.from('dentist_suggestions').select('*, dentist:dentists!dentist_id(*, users(name, phone, email), clinics(clinic_name, location))');
        if (query.patient_id || query.patientId) {
            const pId = await resolveUserUuid(query.patient_id || query.patientId);
            if (pId) req = req.eq('patient_id', pId);
        }
        if (query.request_id || query.requestId) {
            req = req.eq('request_id', query.request_id || query.requestId);
        }
        const { data, error } = await req.order('created_at', { ascending: false });
        if (error) throw error;
        return data || [];
    }
};

// 9. NOTIFICATION MODEL (Supabase PostgreSQL)
const Notification = {
    async create(notifData) {
        const payload = {
            recipient_role: notifData.recipient_role || notifData.recipientRole || 'Patient',
            recipient_id: notifData.recipient_id || notifData.recipientId || 'ALL',
            title: notifData.title || '',
            message: notifData.message || '',
            type: notifData.type || notifData.notification_type || notifData.notificationType || 'general',
            read: notifData.read ?? notifData.read_status ?? false
        };
        if (notifData.referral_id || notifData.referralId) {
            payload.referral_id = notifData.referral_id || notifData.referralId;
        }

        try {
            const { data, error } = await supabaseAdmin.from('notifications').insert(payload).select().single();
            if (!error && data) return data;
            if (error) {
                // Fallback without referral_id column if not yet migrated in Supabase
                const safePayload = { ...payload };
                delete safePayload.referral_id;
                const { data: d2, error: e2 } = await supabaseAdmin.from('notifications').insert(safePayload).select().single();
                if (e2) throw e2;
                return d2;
            }
        } catch (err) {
            console.error('❌ Supabase Notification Insert Error:', err.message);
            return payload;
        }
        return payload;
    },

    async find(query = {}) {
        try {
            let req = supabaseAdmin.from('notifications').select('*');
            if (query.recipient_role || query.recipientRole) {
                req = req.eq('recipient_role', query.recipient_role || query.recipientRole);
            }
            if (query.recipient_id || query.recipientId) {
                const target = query.recipient_id || query.recipientId;
                req = req.or(`recipient_id.eq.${target},recipient_id.eq.ALL`);
            }
            if (query.referral_id || query.referralId) {
                req = req.eq('referral_id', query.referral_id || query.referralId);
            }
            const { data, error } = await req.order('created_at', { ascending: false });
            if (!error && data) return data;
        } catch (e) {
            console.warn('⚠️ Notifications query notice:', e.message);
        }
        return [];
    },

    async markAsRead(id) {
        try {
            const { data, error } = await supabaseAdmin.from('notifications').update({ read: true }).eq('id', id).select().single();
            if (error) throw error;
            return data;
        } catch (e) {
            return null;
        }
    }
};

// 10. AUDIT LOG MODEL (Admin Access & Chat Security Audit Trail)
const _inMemoryAuditLogs = [];

const AuditLog = {
    async create(logData) {
        const payload = {
            id: `audit-${Date.now()}-${Math.random().toString(36).substring(2, 9)}`,
            user_id: logData.user_id || logData.userId || null,
            user_email: logData.user_email || logData.userEmail || null,
            user_role: logData.user_role || logData.userRole || 'Admin',
            action: logData.action || 'ACCESS',
            target_resource: logData.target_resource || logData.targetResource || null,
            details: logData.details || {},
            ip_address: logData.ip_address || logData.ipAddress || null,
            created_at: new Date().toISOString()
        };

        _inMemoryAuditLogs.unshift(payload);
        if (_inMemoryAuditLogs.length > 500) _inMemoryAuditLogs.pop();

        try {
            const { data, error } = await supabaseAdmin.from('audit_logs').insert({
                user_id: payload.user_id,
                user_email: payload.user_email,
                user_role: payload.user_role,
                action: payload.action,
                target_resource: payload.target_resource,
                details: payload.details,
                ip_address: payload.ip_address,
                created_at: payload.created_at
            }).select().maybeSingle();

            if (error) {
                return payload;
            }
            return data || payload;
        } catch (err) {
            return payload;
        }
    },

    async find(query = {}) {
        try {
            let req = supabaseAdmin.from('audit_logs').select('*');
            if (query.action) req = req.eq('action', query.action);
            if (query.user_id || query.userId) req = req.eq('user_id', query.user_id || query.userId);
            if (query.target_resource || query.targetResource) req = req.eq('target_resource', query.target_resource || query.targetResource);
            const { data, error } = await req.order('created_at', { ascending: false }).limit(query.limit || 100);
            if (!error && data && data.length > 0) {
                return data;
            }
        } catch (_) {}

        // Fallback to in-memory audit logs
        let filtered = [..._inMemoryAuditLogs];
        if (query.action) filtered = filtered.filter(l => l.action === query.action);
        if (query.user_id || query.userId) filtered = filtered.filter(l => l.user_id === (query.user_id || query.userId));
        if (query.target_resource || query.targetResource) filtered = filtered.filter(l => l.target_resource === (query.target_resource || query.targetResource));
        if (query.limit) filtered = filtered.slice(0, parseInt(query.limit, 10));
        return filtered;
    }
};

// 12. REFERRAL MODEL (Patient Referrals & Organic User Acquisition Growth)
const _inMemoryReferrals = [];

const Referral = {
    async create(referralData) {
        const id = referralData.id || require('crypto').randomUUID();
        const referrerPatientId = referralData.referrer_patient_id || referralData.referrerPatientId || referralData.referrer_id || referralData.referrerId;
        const referredPatientId = referralData.referred_patient_id || referralData.referredPatientId || referralData.referred_user_id || referralData.referredUserId || null;
        const doctorId = referralData.doctor_id || referralData.doctorId || referralData.assigned_doctor_id || referralData.assignedDoctorId || null;

        const payload = {
            id,
            referrer_patient_id: referrerPatientId,
            referrer_id: referrerPatientId, // Backward compatibility
            referred_patient_id: referredPatientId,
            referred_user_id: referredPatientId, // Backward compatibility
            referred_patient_name: referralData.referred_patient_name || referralData.referredPatientName || '',
            referred_patient_mobile: referralData.referred_patient_mobile || referralData.referredPatientMobile || '',
            referred_patient_age: referralData.referred_patient_age || referralData.referredPatientAge || '',
            referred_patient_gender: referralData.referred_patient_gender || referralData.referredPatientGender || '',
            referred_patient_city: referralData.referred_patient_city || referralData.referredPatientCity || '',
            referred_patient_pincode: referralData.referred_patient_pincode || referralData.referredPatientPincode || '',
            referred_patient_location: referralData.referred_patient_location || referralData.referredPatientLocation || '',
            required_specialist: referralData.required_specialist || referralData.requiredSpecialist || '',
            clinical_complaint: referralData.clinical_complaint || referralData.clinicalComplaint || '',
            doctor_id: doctorId,
            assigned_doctor_id: doctorId,
            status: referralData.status || referralData.referralStatus || 'Pending',
            rejection_reason: referralData.rejection_reason || referralData.rejectionReason || null,
            whatsapp_status: referralData.whatsapp_status || referralData.whatsappStatus || 'Pending',
            referral_date: referralData.referral_date || referralData.referralDate || new Date().toISOString(),
            referral_code: (referralData.referral_code || referralData.referralCode || '').toString().toUpperCase().trim(),
            appointment_id: referralData.appointment_id || referralData.appointmentId || null,
            created_at: referralData.created_at || new Date().toISOString(),
            updated_at: referralData.updated_at || new Date().toISOString()
        };

        try {
            const { data, error } = await supabaseAdmin.from('referrals').insert(payload).select().single();
            if (!error && data) {
                const existingIdx = _inMemoryReferrals.findIndex(r => r.id === data.id);
                if (existingIdx !== -1) _inMemoryReferrals[existingIdx] = data;
                else _inMemoryReferrals.unshift(data);
                return data;
            }
            if (error) {
                // Fallback attempt with subset if some columns don't exist yet
                const safePayload = {
                    id: payload.id,
                    referrer_id: payload.referrer_id,
                    referred_user_id: payload.referred_user_id,
                    referral_code: payload.referral_code || 'DG-REF',
                    status: payload.status,
                    created_at: payload.created_at,
                    updated_at: payload.updated_at
                };
                const { data: d2, error: e2 } = await supabaseAdmin.from('referrals').insert(safePayload).select().single();
                if (!e2 && d2) {
                    const merged = { ...payload, ...d2 };
                    _inMemoryReferrals.unshift(merged);
                    return merged;
                }
            }
        } catch (e) {
            console.warn('⚠️ Supabase Referrals table insert notice:', e.message);
        }

        // In-memory cache fallback
        _inMemoryReferrals.unshift(payload);
        return payload;
    },

    async find(query = {}) {
        try {
            let req = supabaseAdmin.from('referrals').select('*, referrer:users!referrer_patient_id(id, name, email, phone), doctor:dentists!doctor_id(id, speciality, users(name, email, phone), clinics(clinic_name, location))');
            if (query.referrer_patient_id || query.referrerPatientId || query.referrer_id || query.referrerId) {
                const refId = query.referrer_patient_id || query.referrerPatientId || query.referrer_id || query.referrerId;
                req = req.or(`referrer_patient_id.eq.${refId},referrer_id.eq.${refId}`);
            }
            if (query.doctor_id || query.doctorId || query.assigned_doctor_id || query.assignedDoctorId) {
                const docId = query.doctor_id || query.doctorId || query.assigned_doctor_id || query.assignedDoctorId;
                req = req.or(`doctor_id.eq.${docId},assigned_doctor_id.eq.${docId}`);
            }
            if (query.referred_patient_id || query.referredPatientId || query.referred_user_id || query.referredUserId) {
                const refUserId = query.referred_patient_id || query.referredPatientId || query.referred_user_id || query.referredUserId;
                req = req.or(`referred_patient_id.eq.${refUserId},referred_user_id.eq.${refUserId}`);
            }
            if (query.referred_patient_mobile || query.referredPatientMobile) {
                req = req.eq('referred_patient_mobile', query.referred_patient_mobile || query.referredPatientMobile);
            }
            if (query.status) req = req.eq('status', query.status);
            const { data, error } = await req.order('created_at', { ascending: false });
            if (!error && data && data.length > 0) {
                return data;
            }
            if (error) {
                // Fallback to simpler select without complex foreign joins
                const simple = await supabaseAdmin.from('referrals').select('*').order('created_at', { ascending: false });
                if (simple.data && simple.data.length > 0) {
                    return simple.data;
                }
            }
        } catch (_) {}

        let filtered = [..._inMemoryReferrals];
        const rRefId = query.referrer_patient_id || query.referrerPatientId || query.referrer_id || query.referrerId;
        if (rRefId) {
            filtered = filtered.filter(r => (r.referrer_patient_id === rRefId || r.referrer_id === rRefId));
        }
        const rDocId = query.doctor_id || query.doctorId || query.assigned_doctor_id || query.assignedDoctorId;
        if (rDocId) {
            filtered = filtered.filter(r => (r.doctor_id === rDocId || r.assigned_doctor_id === rDocId));
        }
        const rPatId = query.referred_patient_id || query.referredPatientId || query.referred_user_id || query.referredUserId;
        if (rPatId) {
            filtered = filtered.filter(r => (r.referred_patient_id === rPatId || r.referred_user_id === rPatId));
        }
        const rPhone = query.referred_patient_mobile || query.referredPatientMobile;
        if (rPhone) {
            filtered = filtered.filter(r => (r.referred_patient_mobile === rPhone));
        }
        if (query.status) {
            filtered = filtered.filter(r => r.status === query.status);
        }
        return filtered;
    },

    async findById(id) {
        if (!id) return null;
        try {
            const { data, error } = await supabaseAdmin
                .from('referrals')
                .select('*, referrer:users!referrer_patient_id(id, name, email, phone), doctor:dentists!doctor_id(id, speciality, users(name, email, phone), clinics(clinic_name, location))')
                .eq('id', id)
                .maybeSingle();
            if (!error && data) return data;
            const simple = await supabaseAdmin.from('referrals').select('*').eq('id', id).maybeSingle();
            if (simple.data) return simple.data;
        } catch (_) {}

        return _inMemoryReferrals.find(r => r.id === id) || null;
    },

    async findByIdAndUpdate(id, updateData) {
        const payload = {
            ...updateData,
            updated_at: new Date().toISOString()
        };
        try {
            const { data, error } = await supabaseAdmin
                .from('referrals')
                .update(payload)
                .eq('id', id)
                .select()
                .maybeSingle();
            if (!error && data) {
                const idx = _inMemoryReferrals.findIndex(r => r.id === id);
                if (idx !== -1) _inMemoryReferrals[idx] = { ..._inMemoryReferrals[idx], ...data };
                return data;
            }
        } catch (e) {
            console.warn('⚠️ Supabase referral update notice:', e.message);
        }

        const idx = _inMemoryReferrals.findIndex(r => r.id === id);
        if (idx !== -1) {
            Object.assign(_inMemoryReferrals[idx], payload);
            return _inMemoryReferrals[idx];
        }
        return null;
    },

    async findByIdAndDelete(id) {
        if (!id) return null;
        try {
            await supabaseAdmin.from('referrals').delete().eq('id', id);
        } catch (e) {
            console.warn('⚠️ Supabase referral delete notice:', e.message);
        }

        const idx = _inMemoryReferrals.findIndex(r => r.id === id);
        if (idx !== -1) {
            const removed = _inMemoryReferrals.splice(idx, 1)[0];
            return removed;
        }
        return { id };
    },

    async checkDuplicate(referrerPatientId, referredPatientMobile, doctorId) {
        if (!referrerPatientId || !referredPatientMobile || !doctorId) return null;
        try {
            const { data } = await supabaseAdmin
                .from('referrals')
                .select('*')
                .eq('referrer_patient_id', referrerPatientId)
                .eq('referred_patient_mobile', referredPatientMobile)
                .eq('doctor_id', doctorId)
                .eq('status', 'Pending')
                .limit(1);
            if (data && data.length > 0) return data[0];
        } catch (_) {}

        return _inMemoryReferrals.find(r => 
            (r.referrer_patient_id === referrerPatientId || r.referrer_id === referrerPatientId) &&
            r.referred_patient_mobile === referredPatientMobile &&
            (r.doctor_id === doctorId || r.assigned_doctor_id === doctorId) &&
            r.status === 'Pending'
        ) || null;
    },

    async updateStatusForReferredUser(referredUserId, newStatus, extra = {}) {
        const payload = {
            status: newStatus,
            updated_at: new Date().toISOString(),
            ...extra
        };

        try {
            const { data, error } = await supabaseAdmin
                .from('referrals')
                .update(payload)
                .or(`referred_patient_id.eq.${referredUserId},referred_user_id.eq.${referredUserId}`)
                .select();
            if (!error && data && data.length > 0) {
                return data[0];
            }
        } catch (_) {}

        for (const item of _inMemoryReferrals) {
            if (item.referred_patient_id === referredUserId || item.referred_user_id === referredUserId) {
                Object.assign(item, payload);
                return item;
            }
        }
        return null;
    }
};

// 12. PATIENT SAVED DOCTORS MODEL (Supabase PostgreSQL + In-Memory Fallback)
const _inMemoryPatientDoctors = [];

const PatientDoctor = {
    async getDoctorsForPatient(patientId) {
        if (!patientId) return [];
        const cleanPId = patientId.toString().trim();
        try {
            const { data, error } = await supabaseAdmin
                .from('patient_doctors')
                .select('doctor_id, created_at')
                .eq('patient_id', cleanPId);
            if (!error && data) {
                return data.map(d => d.doctor_id);
            }
        } catch (_) {}

        return _inMemoryPatientDoctors
            .filter(r => r.patient_id === cleanPId)
            .map(r => r.doctor_id);
    },

    async addDoctorForPatient(patientId, doctorId) {
        if (!patientId || !doctorId) return { success: false, message: 'Missing patientId or doctorId' };
        const cleanPId = patientId.toString().trim();
        const cleanDId = doctorId.toString().trim();

        try {
            const { data, error } = await supabaseAdmin
                .from('patient_doctors')
                .upsert({ patient_id: cleanPId, doctor_id: cleanDId }, { onConflict: 'patient_id,doctor_id' })
                .select();
            if (!error) {
                return { success: true, data: data?.[0] };
            }
        } catch (e) {
            console.warn('⚠️ Supabase patient_doctors insert warning:', e.message);
        }

        const existing = _inMemoryPatientDoctors.find(r => r.patient_id === cleanPId && r.doctor_id === cleanDId);
        if (!existing) {
            _inMemoryPatientDoctors.push({
                id: `pd_${Date.now()}_${Math.floor(Math.random() * 1000)}`,
                patient_id: cleanPId,
                doctor_id: cleanDId,
                created_at: new Date().toISOString()
            });
        }
        return { success: true };
    },

    async removeDoctorForPatient(patientId, doctorId) {
        if (!patientId || !doctorId) return { success: false, message: 'Missing patientId or doctorId' };
        const cleanPId = patientId.toString().trim();
        const cleanDId = doctorId.toString().trim();

        try {
            const { error } = await supabaseAdmin
                .from('patient_doctors')
                .delete()
                .eq('patient_id', cleanPId)
                .eq('doctor_id', cleanDId);
            if (!error) {
                return { success: true };
            }
        } catch (e) {
            console.warn('⚠️ Supabase patient_doctors delete warning:', e.message);
        }

        const idx = _inMemoryPatientDoctors.findIndex(r => r.patient_id === cleanPId && r.doctor_id === cleanDId);
        if (idx !== -1) {
            _inMemoryPatientDoctors.splice(idx, 1);
        }
        return { success: true };
    }
};

// 12. DOCTOR AVAILABILITY MODEL (Doctor Slots, Working Hours, Blocked Dates)
const _inMemoryAvailability = [];

const DoctorAvailability = {
    async findOne(query = {}) {
        const dentistId = query.dentist_id || query.dentistId;
        const date = query.date;
        if (!dentistId || !date) return null;

        let idsToMatch = [dentistId];
        try {
            const { dentistTableId, userTableId } = await resolveDentistIds(dentistId);
            idsToMatch = [...new Set([dentistId, dentistTableId, userTableId].filter(Boolean))];
        } catch (_) {}

        try {
            let req = supabaseAdmin
                .from('doctor_availability')
                .select('*')
                .eq('date', date);
            if (idsToMatch.length === 1) {
                req = req.eq('dentist_id', idsToMatch[0]);
            } else {
                req = req.in('dentist_id', idsToMatch);
            }
            const { data, error } = await req.limit(1).maybeSingle();
            if (!error && data) return data;
        } catch (e) {
            console.warn('⚠️ DoctorAvailability.findOne Supabase notice:', e.message);
        }

        return _inMemoryAvailability.find(a => 
            (idsToMatch.includes(a.dentist_id) || idsToMatch.includes(a.dentistId)) && 
            a.date === date
        ) || null;
    },

    async find(query = {}) {
        const dentistId = query.dentist_id || query.dentistId;
        let idsToMatch = dentistId ? [dentistId] : [];
        if (dentistId) {
            try {
                const { dentistTableId, userTableId } = await resolveDentistIds(dentistId);
                idsToMatch = [...new Set([dentistId, dentistTableId, userTableId].filter(Boolean))];
            } catch (_) {}
        }
        try {
            let req = supabaseAdmin.from('doctor_availability').select('*');
            if (idsToMatch.length === 1) req = req.eq('dentist_id', idsToMatch[0]);
            else if (idsToMatch.length > 1) req = req.in('dentist_id', idsToMatch);
            if (query.date) req = req.eq('date', query.date);
            const { data, error } = await req.order('date', { ascending: true });
            if (!error && data && data.length > 0) return data;
        } catch (e) {
            console.warn('⚠️ DoctorAvailability.find Supabase notice:', e.message);
        }

        return _inMemoryAvailability.filter(a => {
            if (idsToMatch.length > 0 && !idsToMatch.includes(a.dentist_id) && !idsToMatch.includes(a.dentistId)) return false;
            if (query.date && a.date !== query.date) return false;
            return true;
        });
    },

    async upsert(availData) {
        const dentistId = availData.dentist_id || availData.dentistId;
        const date = availData.date;
        const slots = Array.isArray(availData.slots) ? availData.slots : [];
        const isBlocked = Boolean(availData.is_blocked || availData.isBlocked);
        const blockedReason = availData.blocked_reason || availData.blockedReason || null;
        const startTime = availData.start_time || availData.startTime || '09:00 AM';
        const endTime = availData.end_time || availData.endTime || '05:00 PM';
        const slotDuration = parseInt(availData.slot_duration_minutes || availData.slotDurationMinutes, 10) || 30;
        const dayOfWeek = availData.day_of_week || availData.dayOfWeek || '';

        const payload = {
            id: availData.id || `avail-${Date.now()}-${Math.random().toString(36).substring(2, 7)}`,
            dentist_id: dentistId,
            date: date,
            day_of_week: dayOfWeek,
            start_time: startTime,
            end_time: endTime,
            slot_duration_minutes: slotDuration,
            slots: slots,
            is_blocked: isBlocked,
            blocked_reason: blockedReason,
            updated_at: new Date().toISOString()
        };

        try {
            const { data, error } = await supabaseAdmin
                .from('doctor_availability')
                .upsert({
                    dentist_id: dentistId,
                    date: date,
                    day_of_week: dayOfWeek,
                    start_time: startTime,
                    end_time: endTime,
                    slot_duration_minutes: slotDuration,
                    slots: slots,
                    is_blocked: isBlocked,
                    blocked_reason: blockedReason,
                    updated_at: payload.updated_at
                }, { onConflict: 'dentist_id,date' })
                .select()
                .single();
            if (!error && data) return data;
        } catch (e) {
            console.warn('⚠️ DoctorAvailability.upsert Supabase notice:', e.message);
        }

        const idx = _inMemoryAvailability.findIndex(a => 
            (a.dentist_id === dentistId || a.dentistId === dentistId) && a.date === date
        );
        if (idx !== -1) {
            _inMemoryAvailability[idx] = { ..._inMemoryAvailability[idx], ...payload };
            return _inMemoryAvailability[idx];
        } else {
            _inMemoryAvailability.push(payload);
            return payload;
        }
    },

    async deleteOne(query = {}) {
        const dentistId = query.dentist_id || query.dentistId;
        const date = query.date;
        try {
            await supabaseAdmin
                .from('doctor_availability')
                .delete()
                .eq('dentist_id', dentistId)
                .eq('date', date);
        } catch (e) {
            console.warn('⚠️ DoctorAvailability.deleteOne Supabase notice:', e.message);
        }

        const idx = _inMemoryAvailability.findIndex(a => 
            (a.dentist_id === dentistId || a.dentistId === dentistId) && a.date === date
        );
        if (idx !== -1) {
            _inMemoryAvailability.splice(idx, 1);
        }
        return { success: true };
    }
};

// 13. MEDICAL SPECIALTIES MODEL (Dynamic Multi-Specialty Healthcare Configuration)
const DEFAULT_MEDICAL_SPECIALTIES = [
    {
        id: 'spec-general-medicine',
        code: 'GEN_MED',
        name: 'General Medicine',
        department: 'Department of Internal & General Medicine',
        description: 'Primary care, internal medicine, acute & chronic illnesses, fever, and preventive health checkups.',
        icon: 'medical_services',
        default_qualifications: 'MBBS, MD (General Medicine)',
        consultation_types: ['General Consultation', 'Fever & Viral Infection', 'Diabetes & Blood Pressure Review', 'Preventive Health Checkup', 'Chronic Illness Follow-up'],
        sub_specialties: ['Internal Medicine', 'Family Medicine'],
        is_active: true,
        display_order: 1
    },
    {
        id: 'spec-cardiology',
        code: 'CARDIO',
        name: 'Cardiology',
        department: 'Department of Cardiology & Vascular Sciences',
        description: 'Diagnosis and treatment of heart conditions, hypertension, arrhythmias, and cardiovascular diseases.',
        icon: 'MonitorHeart',
        default_qualifications: 'MBBS, MD, DM (Cardiology)',
        consultation_types: ['Cardiac Consultation', 'ECG & Echo Review', 'Hypertension & Lipid Management', 'Chest Pain Evaluation', 'Post-Angioplasty Follow-up'],
        sub_specialties: ['Interventional Cardiology', 'Electrophysiology'],
        is_active: true,
        display_order: 2
    },
    {
        id: 'spec-dermatology',
        code: 'DERM',
        name: 'Dermatology',
        department: 'Department of Dermatology, Venereology & Cosmetology',
        description: 'Skin, hair, nail disorders, acne, eczema, psoriasis, and clinical dermatological procedures.',
        icon: 'FaceRetouchingNatural',
        default_qualifications: 'MBBS, MD (Dermatology, Venereology & Leprosy)',
        consultation_types: ['Skin & Acne Consultation', 'Hair Fall & Scalp Evaluation', 'Allergy & Rash Treatment', 'Eczema / Psoriasis Care', 'Cosmetic Dermatology'],
        sub_specialties: ['Clinical Dermatology', 'Cosmetology', 'Trichology'],
        is_active: true,
        display_order: 3
    },
    {
        id: 'spec-neurology',
        code: 'NEURO',
        name: 'Neurology',
        department: 'Department of Neurology & Neurosciences',
        description: 'Disorders of the brain, spinal cord, peripheral nerves, migraine, epilepsy, and stroke care.',
        icon: 'Psychology',
        default_qualifications: 'MBBS, MD, DM (Neurology)',
        consultation_types: ['Neurological Consultation', 'Migraine & Headache Clinic', 'Epilepsy & Seizure Management', 'Stroke Recovery & Neuropathy', 'Memory & Movement Disorders'],
        sub_specialties: ['Stroke Medicine', 'Epileptology'],
        is_active: true,
        display_order: 4
    },
    {
        id: 'spec-orthopedics',
        code: 'ORTHO',
        name: 'Orthopedics',
        department: 'Department of Orthopedics & Joint Replacement',
        description: 'Bone, joint, ligament, spine, sports injuries, arthritis, and fracture management.',
        icon: 'AccessibilityNew',
        default_qualifications: 'MBBS, MS (Orthopedics)',
        consultation_types: ['Bone & Joint Consultation', 'Back & Spine Pain Evaluation', 'Sports Injury & Ligament Care', 'Arthritis & Knee Replacement Review', 'Fracture & Trauma Follow-up'],
        sub_specialties: ['Joint Replacement', 'Spine Surgery', 'Sports Medicine'],
        is_active: true,
        display_order: 5
    },
    {
        id: 'spec-pediatrics',
        code: 'PEDIA',
        name: 'Pediatrics',
        department: 'Department of Pediatrics & Child Health',
        description: 'Comprehensive medical care for infants, children, and adolescents including vaccinations and growth tracking.',
        icon: 'ChildCare',
        default_qualifications: 'MBBS, MD (Pediatrics), DCH',
        consultation_types: ['Child Health Consultation', 'Vaccination & Immunization', 'Growth & Nutrition Assessment', 'Pediatric Fever & Infection', 'Newborn & Infant Care'],
        sub_specialties: ['Neonatology', 'Pediatric Critical Care'],
        is_active: true,
        display_order: 6
    },
    {
        id: 'spec-gynecology',
        code: 'GYNEC',
        name: 'Gynecology',
        department: 'Department of Obstetrics & Gynecology',
        description: 'Women\'s reproductive health, pregnancy care, prenatal checkups, PCOS, and gynecological wellness.',
        icon: 'PregnantWoman',
        default_qualifications: 'MBBS, MS / DGO (Obstetrics & Gynecology)',
        consultation_types: ['Gynecology Consultation', 'Antenatal / Pregnancy Checkup', 'PCOS & Hormonal Evaluation', 'Menstrual Health Clinic', 'Postnatal & Fertility Care'],
        sub_specialties: ['Obstetrics', 'Fetal Medicine', 'Reproductive Medicine'],
        is_active: true,
        display_order: 7
    },
    {
        id: 'spec-ent',
        code: 'ENT',
        name: 'ENT',
        department: 'Department of Otorhinolaryngology (Ear, Nose & Throat)',
        description: 'Ear infections, hearing loss, sinusitis, tonsillitis, throat disorders, and vertigo management.',
        icon: 'Hearing',
        default_qualifications: 'MBBS, MS (ENT)',
        consultation_types: ['ENT Consultation', 'Ear Pain & Hearing Assessment', 'Sinusitis & Nasal Allergy', 'Throat & Tonsil Infection', 'Vertigo & Balance Evaluation'],
        sub_specialties: ['Otology', 'Rhinology', 'Laryngology'],
        is_active: true,
        display_order: 8
    },
    {
        id: 'spec-ophthalmology',
        code: 'OPHTHAL',
        name: 'Ophthalmology',
        department: 'Department of Ophthalmology & Vision Sciences',
        description: 'Comprehensive eye exams, cataract, glaucoma, retina care, and vision correction.',
        icon: 'Visibility',
        default_qualifications: 'MBBS, MS (Ophthalmology)',
        consultation_types: ['Comprehensive Eye Exam', 'Cataract & Lens Consultation', 'Retina & Diabetic Eye Screening', 'Glaucoma Evaluation', 'Dry Eye & Vision Correction'],
        sub_specialties: ['Retina', 'Cornea', 'Glaucoma'],
        is_active: true,
        display_order: 9
    },
    {
        id: 'spec-oncology',
        code: 'ONCO',
        name: 'Oncology',
        department: 'Department of Oncology & Cancer Care',
        description: 'Medical, surgical, and radiation oncology consultations, cancer screening, and follow-up care.',
        icon: 'Biotech',
        default_qualifications: 'MBBS, MD, DM (Medical Oncology) / MCh',
        consultation_types: ['Oncology Consultation', 'Cancer Screening & Prevention', 'Chemotherapy / Immunotherapy Review', 'Second Opinion & Tumor Board', 'Survivorship Follow-up'],
        sub_specialties: ['Medical Oncology', 'Surgical Oncology', 'Radiation Oncology'],
        is_active: true,
        display_order: 10
    },
    {
        id: 'spec-urology',
        code: 'URO',
        name: 'Urology',
        department: 'Department of Urology & Renal Sciences',
        description: 'Kidney stones, urinary tract infections, prostate health, and reconstructive urology.',
        icon: 'WaterDrop',
        default_qualifications: 'MBBS, MS, MCh (Urology)',
        consultation_types: ['Urology Consultation', 'Kidney Stone Evaluation', 'Urinary Tract Infection (UTI)', 'Prostate Health Screening', 'Bladder & Renal Follow-up'],
        sub_specialties: ['Endourology', 'Andrology', 'Uro-Oncology'],
        is_active: true,
        display_order: 11
    },
    {
        id: 'spec-psychiatry',
        code: 'PSYCH',
        name: 'Psychiatry',
        department: 'Department of Psychiatry & Behavioral Sciences',
        description: 'Mental health consultations, anxiety, depression, stress management, sleep disorders, and counseling.',
        icon: 'SelfImprovement',
        default_qualifications: 'MBBS, MD (Psychiatry)',
        consultation_types: ['Psychiatric Consultation', 'Anxiety & Stress Management', 'Depression & Mood Clinic', 'Sleep Disorder Evaluation', 'Behavioral & De-addiction Support'],
        sub_specialties: ['Adult Psychiatry', 'Child & Adolescent Psychiatry'],
        is_active: true,
        display_order: 12
    },
    {
        id: 'spec-gastroenterology',
        code: 'GASTRO',
        name: 'Gastroenterology',
        department: 'Department of Gastroenterology & Hepatology',
        description: 'Digestive tract, stomach, liver, pancreas, acidity, IBS, and endoscopy consultations.',
        icon: 'MedicationLiquid',
        default_qualifications: 'MBBS, MD, DM (Gastroenterology)',
        consultation_types: ['Gastroenterology Consultation', 'Acidity, Reflux & Ulcer Care', 'Liver & Hepatology Evaluation', 'IBS & Digestive Disorder Clinic', 'Endoscopy / Colonoscopy Review'],
        sub_specialties: ['Hepatology', 'Therapeutic Endoscopy'],
        is_active: true,
        display_order: 13
    },
    {
        id: 'spec-pulmonology',
        code: 'PULMO',
        name: 'Pulmonology',
        department: 'Department of Pulmonology & Respiratory Medicine',
        description: 'Asthma, COPD, bronchitis, sleep apnea, lung infections, and allergy management.',
        icon: 'Air',
        default_qualifications: 'MBBS, MD (Pulmonary Medicine)',
        consultation_types: ['Pulmonology Consultation', 'Asthma & Allergy Clinic', 'Chronic Cough & COPD Care', 'Sleep Apnea & Breathing Study', 'Post-Infection Lung Recovery'],
        sub_specialties: ['Interventional Pulmonology', 'Sleep Medicine'],
        is_active: true,
        display_order: 14
    },
    {
        id: 'spec-endocrinology',
        code: 'ENDO',
        name: 'Endocrinology',
        department: 'Department of Endocrinology, Diabetes & Metabolism',
        description: 'Diabetes mellitus, thyroid disorders, hormonal imbalances, osteoporosis, and metabolic care.',
        icon: 'Bloodtype',
        default_qualifications: 'MBBS, MD, DM (Endocrinology)',
        consultation_types: ['Endocrinology Consultation', 'Comprehensive Diabetes Management', 'Thyroid Disorder Clinic', 'PCOS & Adrenal Hormone Review', 'Metabolic & Bone Density Care'],
        sub_specialties: ['Diabetology', 'Thyroid & Metabolic Medicine'],
        is_active: true,
        display_order: 15
    },
    {
        id: 'spec-dentistry',
        code: 'DENTAL',
        name: 'Dentistry',
        department: 'Department of Dental Sciences & Oral Healthcare',
        description: 'General dentistry, orthodontics, endodontics, root canal, periodontics, prosthodontics, and oral surgery.',
        icon: 'HealthAndSafety',
        default_qualifications: 'BDS, MDS',
        consultation_types: ['General Consultation', 'Dental Pain / Toothache', 'Tooth Decay / Cavity', 'Root Canal Consultation', 'Orthodontics / Braces', 'Periodontics / Gum Care', 'Tooth Extraction', 'Dental Cleaning & Scaling'],
        sub_specialties: ['General Dentistry', 'Orthodontics', 'Endodontics', 'Periodontics', 'Prosthodontics', 'Pediatric Dentistry', 'Cosmetic Dentistry', 'Oral & Maxillofacial Surgery', 'Oral Surgery'],
        is_active: true,
        display_order: 16
    }
];

const _inMemorySpecialties = DEFAULT_MEDICAL_SPECIALTIES.map(s => ({
    ...s,
    created_at: new Date().toISOString(),
    updated_at: new Date().toISOString()
}));

const MedicalSpecialty = {
    async find(query = {}) {
        const onlyActive = query.is_active === true || query.activeOnly === true;
        try {
            let req = supabaseAdmin.from('medical_specialties').select('*');
            if (onlyActive) {
                req = req.eq('is_active', true);
            }
            const { data, error } = await req.order('display_order', { ascending: true });
            if (!error && data && data.length > 0) {
                // Sync in-memory cache with DB rows
                for (const row of data) {
                    const idx = _inMemorySpecialties.findIndex(
                        m => m.code === row.code || m.name.toLowerCase() === (row.name || '').toLowerCase() || m.id === row.id
                    );
                    if (idx !== -1) {
                        _inMemorySpecialties[idx] = { ..._inMemorySpecialties[idx], ...row };
                    } else {
                        _inMemorySpecialties.push(row);
                    }
                }
                return data;
            }
        } catch (_) {}

        let list = [..._inMemorySpecialties];
        if (onlyActive) {
            list = list.filter(s => s.is_active !== false);
        }
        list.sort((a, b) => (a.display_order || 100) - (b.display_order || 100));
        return list;
    },

    async findById(idOrCodeOrName) {
        if (!idOrCodeOrName) return null;
        const target = String(idOrCodeOrName).trim();
        try {
            if (isUUID(target)) {
                const { data, error } = await supabaseAdmin.from('medical_specialties').select('*').eq('id', target).maybeSingle();
                if (!error && data) return data;
            } else {
                const { data, error } = await supabaseAdmin
                    .from('medical_specialties')
                    .select('*')
                    .or(`code.ilike.${target},name.ilike.${target}`)
                    .maybeSingle();
                if (!error && data) return data;
            }
        } catch (_) {}

        const lower = target.toLowerCase();
        return _inMemorySpecialties.find(
            s => s.id === target || (s.code && s.code.toLowerCase() === lower) || (s.name && s.name.toLowerCase() === lower)
        ) || null;
    },

    async create(specData) {
        const name = (specData.name || '').toString().trim();
        if (!name) throw new Error('Specialty name is required.');
        const code = (specData.code || name.toUpperCase().replace(/[^A-Z0-9]+/g, '_').replace(/^_|_$/g, '')).substring(0, 40);
        const now = new Date().toISOString();

        const payload = {
            code,
            name,
            department: specData.department || `Department of ${name}`,
            description: specData.description || `${name} consultations, diagnostics, and specialized care.`,
            icon: specData.icon || 'medical_services',
            default_qualifications: specData.default_qualifications || specData.defaultQualifications || getDefaultQualificationForSpecialty(name),
            consultation_types: Array.isArray(specData.consultation_types || specData.consultationTypes)
                ? (specData.consultation_types || specData.consultationTypes)
                : ['General Consultation', `${name} Specialist Evaluation`, 'Follow-up Consultation'],
            sub_specialties: Array.isArray(specData.sub_specialties || specData.subSpecialties)
                ? (specData.sub_specialties || specData.subSpecialties)
                : [],
            is_active: specData.is_active !== undefined ? Boolean(specData.is_active) : (specData.isActive !== undefined ? Boolean(specData.isActive) : true),
            display_order: parseInt(specData.display_order ?? specData.displayOrder, 10) || (_inMemorySpecialties.length + 1),
            updated_at: now
        };

        try {
            const { data, error } = await supabaseAdmin
                .from('medical_specialties')
                .upsert(payload, { onConflict: 'code' })
                .select()
                .single();
            if (!error && data) {
                const idx = _inMemorySpecialties.findIndex(s => s.code === data.code || s.name.toLowerCase() === data.name.toLowerCase());
                if (idx !== -1) _inMemorySpecialties[idx] = data;
                else _inMemorySpecialties.push(data);
                return data;
            }
        } catch (_) {}

        const existingIdx = _inMemorySpecialties.findIndex(
            s => s.code.toLowerCase() === code.toLowerCase() || s.name.toLowerCase() === name.toLowerCase()
        );
        const fullRecord = {
            id: existingIdx !== -1 ? _inMemorySpecialties[existingIdx].id : `spec-${code.toLowerCase()}-${Date.now()}`,
            ...payload,
            created_at: existingIdx !== -1 ? _inMemorySpecialties[existingIdx].created_at : now
        };
        if (existingIdx !== -1) {
            _inMemorySpecialties[existingIdx] = fullRecord;
        } else {
            _inMemorySpecialties.push(fullRecord);
        }
        return fullRecord;
    },

    async findByIdAndUpdate(id, updateData) {
        if (!id) return null;
        const target = String(id).trim();
        const now = new Date().toISOString();

        const patch = { updated_at: now };
        if (updateData.name !== undefined) patch.name = String(updateData.name).trim();
        if (updateData.code !== undefined) patch.code = String(updateData.code).trim().toUpperCase();
        if (updateData.department !== undefined) patch.department = String(updateData.department).trim();
        if (updateData.description !== undefined) patch.description = String(updateData.description).trim();
        if (updateData.icon !== undefined) patch.icon = String(updateData.icon).trim();
        if (updateData.default_qualifications !== undefined || updateData.defaultQualifications !== undefined) {
            patch.default_qualifications = String(updateData.default_qualifications ?? updateData.defaultQualifications).trim();
        }
        if (updateData.consultation_types !== undefined || updateData.consultationTypes !== undefined) {
            const ct = updateData.consultation_types ?? updateData.consultationTypes;
            patch.consultation_types = Array.isArray(ct) ? ct : String(ct).split(',').map(s => s.trim()).filter(Boolean);
        }
        if (updateData.sub_specialties !== undefined || updateData.subSpecialties !== undefined) {
            const ss = updateData.sub_specialties ?? updateData.subSpecialties;
            patch.sub_specialties = Array.isArray(ss) ? ss : String(ss).split(',').map(s => s.trim()).filter(Boolean);
        }
        if (updateData.is_active !== undefined || updateData.isActive !== undefined) {
            patch.is_active = Boolean(updateData.is_active ?? updateData.isActive);
        }
        if (updateData.display_order !== undefined || updateData.displayOrder !== undefined) {
            patch.display_order = parseInt(updateData.display_order ?? updateData.displayOrder, 10) || 100;
        }

        try {
            let req = supabaseAdmin.from('medical_specialties').update(patch);
            if (isUUID(target)) {
                req = req.eq('id', target);
            } else {
                req = req.or(`code.eq.${target},name.ilike.${target}`);
            }
            const { data, error } = await req.select().maybeSingle();
            if (!error && data) {
                const idx = _inMemorySpecialties.findIndex(
                    s => s.id === target || s.code === data.code || s.name.toLowerCase() === data.name.toLowerCase()
                );
                if (idx !== -1) _inMemorySpecialties[idx] = { ..._inMemorySpecialties[idx], ...data };
                return data;
            }
        } catch (_) {}

        const lower = target.toLowerCase();
        const idx = _inMemorySpecialties.findIndex(
            s => s.id === target || (s.code && s.code.toLowerCase() === lower) || (s.name && s.name.toLowerCase() === lower)
        );
        if (idx !== -1) {
            _inMemorySpecialties[idx] = { ..._inMemorySpecialties[idx], ...patch };
            return _inMemorySpecialties[idx];
        }
        return null;
    },

    async deleteOne(id) {
        if (!id) return null;
        const target = String(id).trim();
        try {
            if (isUUID(target)) {
                await supabaseAdmin.from('medical_specialties').delete().eq('id', target);
            } else {
                await supabaseAdmin.from('medical_specialties').delete().or(`code.eq.${target},name.ilike.${target}`);
            }
        } catch (_) {}

        const lower = target.toLowerCase();
        const idx = _inMemorySpecialties.findIndex(
            s => s.id === target || (s.code && s.code.toLowerCase() === lower) || (s.name && s.name.toLowerCase() === lower)
        );
        if (idx !== -1) {
            return _inMemorySpecialties.splice(idx, 1)[0];
        }
        return { id: target };
    }
};

module.exports = {
    User,
    SubAdminPermission,
    PERMISSION_CONSTANTS,
    Clinic,
    Dentist,
    Appointment,
    MedicalRecord,
    ChatMessage,
    PatientProblemRequest,
    DentistSuggestion,
    Notification,
    AuditLog,
    Referral,
    PatientDoctor,
    DoctorAvailability,
    MedicalSpecialty,
    DEFAULT_MEDICAL_SPECIALTIES,
    isDentalSpecialtyText,
    getDefaultQualificationForSpecialty,
    matchesSpecialtyQuery,
    resolveUserUuid,
    resolveDentistIds,
    comparePassword
};



