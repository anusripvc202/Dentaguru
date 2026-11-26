const bcrypt = require('bcryptjs');
const crypto = require('crypto');
const { supabaseAdmin } = require('../config/supabase');
const {
    parseDeviceTokenPayload,
    extractFcmToken,
    extractFcmTokens,
    mergeDeviceTokenPayload,
} = require('../utils/deviceTokenHelper');
const {
    normalizeDateToTimezoneYmd,
    parseClockSlotMinutes,
    minutesToClockSlot,
    normalizeConsultationType,
    getConsultationTimingForType,
    getAppointmentOccupiedInterval,
    intervalsOverlap,
} = require('../config/bookingRulesConfig');
const {
    DEFAULT_SMART_SCHEDULE,
    sanitizeSmartSchedule,
    getModeScheduleWindow,
} = require('../services/smartSchedulingEngine');

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
    // 1. Patient Management
    PATIENT_VIEW: 'PATIENT_VIEW',
    PATIENT_DETAILS_VIEW: 'PATIENT_DETAILS_VIEW',
    PATIENT_RECORDS_VIEW: 'PATIENT_RECORDS_VIEW',
    PATIENT_ASSIGNMENT_HISTORY_VIEW: 'PATIENT_ASSIGNMENT_HISTORY_VIEW',
    PATIENT_ADD: 'PATIENT_ADD',
    PATIENT_EDIT: 'PATIENT_EDIT',

    // 2. Doctor / Dentist Management
    DENTIST_VIEW: 'DENTIST_VIEW',
    DOCTOR_VIEW: 'DOCTOR_VIEW',
    DOCTOR_AVAILABILITY_VIEW: 'DOCTOR_AVAILABILITY_VIEW',
    DOCTOR_PROFILE_VIEW: 'DOCTOR_PROFILE_VIEW',
    DENTIST_CREATE: 'DENTIST_CREATE',
    DENTIST_EDIT: 'DENTIST_EDIT',

    // 3. Patient Assignment
    ASSIGNMENT_VIEW: 'ASSIGNMENT_VIEW',
    ASSIGNMENT_CREATE: 'ASSIGNMENT_CREATE',
    PATIENT_ASSIGN: 'PATIENT_ASSIGN',
    PATIENT_REASSIGN: 'PATIENT_REASSIGN',
    ASSIGNMENT_HISTORY_VIEW: 'ASSIGNMENT_HISTORY_VIEW',

    // 4. Clinic Management
    CLINIC_VIEW: 'CLINIC_VIEW',
    CLINIC_MANAGE: 'CLINIC_MANAGE',

    // 5. Referral Management
    REFERRAL_VIEW: 'REFERRAL_VIEW',
    REFERRAL_MANAGE: 'REFERRAL_MANAGE',

    // 6. Reports & District Analytics
    REPORT_VIEW: 'REPORT_VIEW',
    REPORT_DISTRICT_VIEW: 'REPORT_DISTRICT_VIEW',
    REPORT_ASSIGNMENT_VIEW: 'REPORT_ASSIGNMENT_VIEW',

    // 7. Appointment & Problem Management (Legacy backward-compatibility)
    APPOINTMENT_VIEW: 'APPOINTMENT_VIEW',
    APPOINTMENT_MANAGE: 'APPOINTMENT_MANAGE',
    PROBLEM_VIEW: 'PROBLEM_VIEW',
    PROBLEM_UPDATE: 'PROBLEM_UPDATE',
};

const ASSIGNMENT_SOURCES = {
    PATIENT_DIRECT_BOOKING: 'PATIENT_DIRECT_BOOKING',
    MAIN_ADMIN_ASSIGNMENT: 'MAIN_ADMIN_ASSIGNMENT',
    SUB_ADMIN_ASSIGNMENT: 'SUB_ADMIN_ASSIGNMENT',
};

// Helper: canonical 10-digit Indian phone normalization across +91 / 91 / 0 / spaces / hyphens
function canonicalPhone10(rawPhone) {
    const clean = String(rawPhone || '').trim();
    if (!clean) return '';
    const digits = clean.replace(/[^0-9]/g, '');
    if (digits.length === 12 && digits.startsWith('91')) return digits.slice(2);
    if (digits.length === 11 && digits.startsWith('0')) return digits.slice(1);
    if (digits.length > 10) return digits.slice(-10);
    return digits;
}

// Helper: unpack JSON metadata safely stored in users.device_token
function _unpackUserRecord(record) {
    if (!record) return record;
    if (record.device_token && typeof record.device_token === 'string' && record.device_token.trim().startsWith('{')) {
        try {
            const meta = JSON.parse(record.device_token);
            if (meta.languages && (!record.languages || record.languages.length === 0)) {
                record.languages = meta.languages;
            }
            const colStatus = record.status ? String(record.status).trim().toUpperCase() : '';
            const metaStatus = meta.status ? String(meta.status).trim().toUpperCase() : '';
            if (!colStatus && metaStatus) {
                record.status = metaStatus;
            } else if (colStatus) {
                record.status = colStatus;
            }
            if (meta.permissions && Array.isArray(meta.permissions) && (!record.permissions || record.permissions.length === 0)) {
                record.permissions = meta.permissions;
            }
            if (meta.statusUpdatedAt && !record.status_updated_at) {
                record.status_updated_at = meta.statusUpdatedAt;
            }
            if (meta.statusUpdatedBy && !record.status_updated_by) {
                record.status_updated_by = meta.statusUpdatedBy;
            }
            if (meta.city && !record.city) record.city = meta.city;
            if (meta.pincode && !record.pincode) record.pincode = meta.pincode;
            if (meta.age && !record.age) record.age = meta.age;
            if (meta.gender && !record.gender) record.gender = meta.gender;
            if (meta.bloodGroup && !record.blood_group) record.blood_group = meta.bloodGroup;
            if (meta.emergencyContact && !record.emergency_contact) record.emergency_contact = meta.emergencyContact;
            if (meta.address && !record.address) record.address = meta.address;
            if (meta.profilePhoto && !record.biometric_token) record.biometric_token = meta.profilePhoto;
        } catch (_) { }
    }
    const resolvedFcmToken = extractFcmToken(record);
    if (resolvedFcmToken && !record.fcm_token) {
        record.fcm_token = resolvedFcmToken;
    }
    const resolvedFcmTokens = extractFcmTokens(record);
    if (resolvedFcmTokens.length > 0 && !record.fcm_tokens) {
        record.fcm_tokens = resolvedFcmTokens;
    }
    return record;
}

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
        const record = _unpackUserRecord((data && data.length > 0) ? data[0] : null);
        if (record && (record.role === 'Sub-Admin' || record.role === 'SUB_ADMIN' || record.role === 'SUB-ADMIN')) {
            if (!record.permissions || record.permissions.length === 0) {
                record.permissions = await SubAdminPermission.getPermissionsForUser(record.id);
            }
            if (!record.status) record.status = 'ACTIVE';
        }
        return record;
    },

    async findByMobile(rawPhone) {
        const clean = String(rawPhone || '').trim();
        if (!clean) return null;
        const digits = clean.replace(/[^0-9]/g, '');
        const last10 = canonicalPhone10(clean);
        const candidates = Array.from(new Set([
            clean,
            digits,
            last10,
            last10 ? `+91${last10}` : '',
            last10 ? `+91 ${last10}` : '',
            last10 ? `91${last10}` : '',
            last10 ? `0${last10}` : ''
        ].filter(Boolean)));

        for (const c of candidates) {
            const found = await this.findOne({ phone: c });
            if (found) return found;
        }

        if (last10 && last10.length >= 10) {
            const { data } = await supabaseAdmin
                .from('users')
                .select('*')
                .ilike('phone', `%${last10}%`)
                .limit(5);
            if (data && data.length > 0) {
                const match = data.find(u => canonicalPhone10(u.phone) === last10) || data[0];
                const unpacked = _unpackUserRecord(match);
                if (unpacked && (unpacked.role === 'Sub-Admin' || unpacked.role === 'SUB_ADMIN' || unpacked.role === 'SUB-ADMIN')) {
                    if (!unpacked.permissions || unpacked.permissions.length === 0) {
                        unpacked.permissions = await SubAdminPermission.getPermissionsForUser(unpacked.id);
                    }
                    if (!unpacked.status) unpacked.status = 'ACTIVE';
                }
                return unpacked;
            }

            // Fallback for interior spacing/hyphens (e.g. "+91 98765 43210") using trailing 4 digits
            const last4 = last10.slice(-4);
            const { data: spacedData } = await supabaseAdmin
                .from('users')
                .select('*')
                .ilike('phone', `%${last4}%`)
                .limit(25);
            if (spacedData && spacedData.length > 0) {
                const match = spacedData.find(u => canonicalPhone10(u.phone) === last10);
                if (match) {
                    const unpacked = _unpackUserRecord(match);
                    if (unpacked && (unpacked.role === 'Sub-Admin' || unpacked.role === 'SUB_ADMIN' || unpacked.role === 'SUB-ADMIN')) {
                        if (!unpacked.permissions || unpacked.permissions.length === 0) {
                            unpacked.permissions = await SubAdminPermission.getPermissionsForUser(unpacked.id);
                        }
                        if (!unpacked.status) unpacked.status = 'ACTIVE';
                    }
                    return unpacked;
                }
            }
        }
        return null;
    },


    async find(query = {}) {
        const unpackUser = (u) => {
            const unpacked = _unpackUserRecord(u);
            if (unpacked && (unpacked.role === 'Sub-Admin' || unpacked.role === 'SUB_ADMIN') && !unpacked.status) {
                unpacked.status = 'ACTIVE';
            }
            return unpacked;
        };

        const matchesRoleFilter = (userRole, roleQuery) => {
            if (!roleQuery) return true;
            const normUserRole = String(userRole || '').trim().toLowerCase();
            if (typeof roleQuery === 'object' && Array.isArray(roleQuery.$in)) {
                return roleQuery.$in.some(r => String(r || '').trim().toLowerCase() === normUserRole);
            }
            return normUserRole === String(roleQuery || '').trim().toLowerCase();
        };

        try {
            let req = supabaseAdmin.from('users').select('*');
            if (query.role) {
                if (typeof query.role === 'object' && Array.isArray(query.role.$in)) {
                    req = req.in('role', query.role.$in);
                } else {
                    req = req.ilike('role', query.role);
                }
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
                    result = result.filter(u => matchesRoleFilter(u.role, query.role));
                }
                return result.map(unpackUser);
            }
            return (data || []).map(unpackUser);
        } catch (e) {
            console.warn('⚠️ User find exception, falling back to simple select:', e.message);
            const simple = await supabaseAdmin.from('users').select('*');
            let result = simple.data || [];
            if (query.role) {
                result = result.filter(u => matchesRoleFilter(u.role, query.role));
            }
            return result.map(unpackUser);
        }
    },

    async findById(id) {
        const { data, error } = await supabaseAdmin.from('users').select('*').eq('id', id).single();
        if (error) return null;
        const record = _unpackUserRecord(data);
        if (record && (record.role === 'Sub-Admin' || record.role === 'SUB_ADMIN')) {
            if (!record.permissions || record.permissions.length === 0) {
                record.permissions = await SubAdminPermission.getPermissionsForUser(record.id);
            }
            if (!record.status) record.status = 'ACTIVE';
        }
        return record;
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
            if (payload.status) safePayload.status = String(payload.status).trim().toUpperCase();
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

    async updateFcmToken(id, fcmToken) {
        const cleanToken = typeof fcmToken === 'string' ? fcmToken.trim() : '';
        if (!id || !cleanToken || cleanToken.startsWith('{')) {
            return null;
        }
        const existing = await supabaseAdmin.from('users').select('device_token').eq('id', id).maybeSingle();
        const mergedDeviceToken = mergeDeviceTokenPayload(existing.data?.device_token, { fcmToken: cleanToken });
        const { data, error } = await supabaseAdmin
            .from('users')
            .update({ device_token: mergedDeviceToken })
            .eq('id', id)
            .select()
            .maybeSingle();
        if (error) throw error;
        return _unpackUserRecord(data);
    },

    async findByIdAndUpdate(id, updateData) {
        if (updateData.password && !updateData.password.startsWith('$2a$') && !updateData.password.startsWith('$2b$')) {
            updateData.password = await hashPassword(updateData.password);
        }
        let updatedData = null;
        const dbPayload = { ...updateData };
        delete dbPayload.permissions;
        delete dbPayload.languages;
        delete dbPayload.address;
        delete dbPayload.status_updated_at;
        delete dbPayload.status_updated_by;
        if (dbPayload.status !== undefined) {
            dbPayload.status = String(dbPayload.status).trim().toUpperCase();
        }
        // Non-destructive guard: never allow raw device_token updates to overwrite existing schedule/profile metadata or FCM tokens
        if (dbPayload.device_token !== undefined && dbPayload.device_token !== null) {
            try {
                const existing = await supabaseAdmin.from('users').select('device_token').eq('id', id).maybeSingle();
                dbPayload.device_token = mergeDeviceTokenPayload(existing.data?.device_token, dbPayload.device_token);
            } catch (_) {
                dbPayload.device_token = mergeDeviceTokenPayload(null, dbPayload.device_token);
            }
        }

        try {
            if (Object.keys(dbPayload).length > 0) {
                const { data, error } = await supabaseAdmin.from('users').update(dbPayload).eq('id', id).select().maybeSingle();
                if (error) throw error;
                updatedData = data;
            }
        } catch (err) {
            // Strip optional schema columns that may not exist in legacy tables (e.g. updated_at, refresh_tokens, address)
            const safeUpdate = { ...dbPayload };
            delete safeUpdate.updated_at;
            delete safeUpdate.refresh_tokens;
            delete safeUpdate.status_updated_at;
            delete safeUpdate.status_updated_by;
            delete safeUpdate.address;
            if (err && typeof err.message === 'string' && err.message.toLowerCase().includes('status')) {
                delete safeUpdate.status;
            }
            if (Object.keys(safeUpdate).length > 0) {
                const { data, error } = await supabaseAdmin.from('users').update(safeUpdate).eq('id', id).select().maybeSingle();
                if (error) throw error;
                updatedData = data;
            }
        }

        const hasProfileMetaUpdates =
            updateData.age !== undefined ||
            updateData.gender !== undefined ||
            updateData.pincode !== undefined ||
            updateData.city !== undefined ||
            updateData.state !== undefined ||
            updateData.address !== undefined ||
            updateData.blood_group !== undefined ||
            updateData.emergency_contact !== undefined ||
            updateData.biometric_token !== undefined;

        if (updateData.status || updateData.permissions || updateData.languages || updateData.status_updated_at || updateData.status_updated_by || updateData.refresh_tokens !== undefined || hasProfileMetaUpdates) {
            try {
                const existing = await supabaseAdmin.from('users').select('device_token').eq('id', id).maybeSingle();
                const rawDt = existing.data?.device_token;
                let meta = {};
                if (rawDt && typeof rawDt === 'string' && rawDt.trim().startsWith('{')) {
                    try { meta = JSON.parse(rawDt); } catch (_) { }
                } else if (rawDt && typeof rawDt === 'string' && rawDt.trim().length > 0) {
                    meta.fcmToken = rawDt.trim();
                }
                if (updateData.status) meta.status = String(updateData.status).trim().toUpperCase();
                if (updateData.permissions) meta.permissions = updateData.permissions;
                if (updateData.languages) meta.languages = normalizeLanguagesList(updateData.languages);
                if (updateData.status_updated_at) meta.statusUpdatedAt = updateData.status_updated_at;
                if (updateData.status_updated_by) meta.statusUpdatedBy = updateData.status_updated_by;
                if (updateData.age !== undefined) meta.age = String(updateData.age || '');
                if (updateData.gender !== undefined) meta.gender = String(updateData.gender || '');
                if (updateData.pincode !== undefined) meta.pincode = String(updateData.pincode || '');
                if (updateData.city !== undefined) meta.city = String(updateData.city || '');
                if (updateData.state !== undefined) meta.state = String(updateData.state || '');
                if (updateData.address !== undefined) meta.address = String(updateData.address || '');
                if (updateData.blood_group !== undefined) meta.bloodGroup = String(updateData.blood_group || '');
                if (updateData.emergency_contact !== undefined) meta.emergencyContact = String(updateData.emergency_contact || '');
                if (updateData.biometric_token !== undefined && updateData.biometric_token) {
                    meta.profilePhoto = String(updateData.biometric_token);
                }
                if (updateData.status === 'INACTIVE' || updateData.status === 'DEACTIVATED') {
                    meta.revokedBefore = Date.now();
                } else if (updateData.status === 'ACTIVE') {
                    delete meta.revokedBefore;
                }

                await supabaseAdmin.from('users').update({ device_token: JSON.stringify(meta) }).eq('id', id);

                if (updatedData) {
                    updatedData.device_token = JSON.stringify(meta);
                }
            } catch (_) { }
        }

        updatedData = _unpackUserRecord(updatedData || await this.findById(id));
        if (updatedData) {
            if (updateData.status) updatedData.status = String(updateData.status).trim().toUpperCase();
            if (updateData.permissions) updatedData.permissions = updateData.permissions;
            if (updateData.languages) updatedData.languages = normalizeLanguagesList(updateData.languages);
            if (updateData.status_updated_at) updatedData.status_updated_at = updateData.status_updated_at;
            if (updateData.status_updated_by) updatedData.status_updated_by = updateData.status_updated_by;
            if (updateData.address !== undefined) updatedData.address = updateData.address;
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

// 1c. DISTRICTS & MULTI-DISTRICT MANAGEMENT MODEL (Supabase PostgreSQL + In-Memory Fallback)
const DEFAULT_DISTRICTS = [
    { id: 'dist-hyd', name: 'Hyderabad', state: 'Telangana', country: 'India', is_active: true },
    { id: 'dist-medchal', name: 'Medchal-Malkajgiri', state: 'Telangana', country: 'India', is_active: true },
    { id: 'dist-rangareddy', name: 'Rangareddy', state: 'Telangana', country: 'India', is_active: true },
    { id: 'dist-warangal', name: 'Warangal', state: 'Telangana', country: 'India', is_active: true },
    { id: 'dist-karimnagar', name: 'Karimnagar', state: 'Telangana', country: 'India', is_active: true },
    { id: 'dist-nizamabad', name: 'Nizamabad', state: 'Telangana', country: 'India', is_active: true },
    { id: 'dist-adilabad', name: 'Adilabad', state: 'Telangana', country: 'India', is_active: true },
    { id: 'dist-khammam', name: 'Khammam', state: 'Telangana', country: 'India', is_active: true },
    { id: 'dist-nalgonda', name: 'Nalgonda', state: 'Telangana', country: 'India', is_active: true },
    { id: 'dist-mahabubnagar', name: 'Mahabubnagar', state: 'Telangana', country: 'India', is_active: true },
    { id: 'dist-mumbai-city', name: 'Mumbai City', state: 'Maharashtra', country: 'India', is_active: true },
    { id: 'dist-mumbai-sub', name: 'Mumbai Suburban', state: 'Maharashtra', country: 'India', is_active: true },
    { id: 'dist-pune', name: 'Pune', state: 'Maharashtra', country: 'India', is_active: true },
    { id: 'dist-thane', name: 'Thane', state: 'Maharashtra', country: 'India', is_active: true },
    { id: 'dist-bengaluru', name: 'Bengaluru Urban', state: 'Karnataka', country: 'India', is_active: true },
    { id: 'dist-chennai', name: 'Chennai', state: 'Tamil Nadu', country: 'India', is_active: true },
    { id: 'dist-delhi', name: 'Delhi', state: 'Delhi', country: 'India', is_active: true }
];

const _inMemoryDistricts = DEFAULT_DISTRICTS.map(d => ({
    ...d,
    created_at: new Date().toISOString(),
    updated_at: new Date().toISOString()
}));

function _syncDistrictToMemory(row) {
    if (!row || !row.name) return row;
    const idx = _inMemoryDistricts.findIndex(
        d => d.id === row.id || d.name.toLowerCase() === String(row.name).toLowerCase()
    );
    if (idx !== -1) {
        _inMemoryDistricts[idx] = { ..._inMemoryDistricts[idx], ...row };
    } else {
        _inMemoryDistricts.push(row);
    }
    return row;
}

const District = {
    async find(query = {}) {
        try {
            let req = supabaseAdmin.from('districts').select('*');
            if (query.is_active !== undefined) req = req.eq('is_active', query.is_active);
            if (query.state) req = req.eq('state', query.state);
            req = req.order('name', { ascending: true });
            const { data, error } = await req;
            if (!error && data && data.length > 0) {
                for (const row of data) {
                    _syncDistrictToMemory(row);
                }
            }
        } catch (_) { }

        // Return merged district list from synced memory store
        let list = [..._inMemoryDistricts];
        if (query.is_active !== undefined) list = list.filter(d => d.is_active === query.is_active);
        if (query.state) list = list.filter(d => d.state.toLowerCase() === query.state.toLowerCase());
        if (query.search) {
            const q = query.search.toLowerCase();
            list = list.filter(d => d.name.toLowerCase().includes(q) || d.state.toLowerCase().includes(q));
        }
        return list;
    },

    async findById(id) {
        if (!id) return null;
        try {
            const { data, error } = await supabaseAdmin.from('districts').select('*').eq('id', id).maybeSingle();
            if (!error && data) return _syncDistrictToMemory(data);
        } catch (_) { }
        return _inMemoryDistricts.find(d => d.id === id) || null;
    },

    async findOne(query = {}) {
        try {
            let req = supabaseAdmin.from('districts').select('*');
            for (const [k, v] of Object.entries(query)) {
                req = req.eq(k, v);
            }
            const { data, error } = await req.limit(1);
            if (!error && data && data.length > 0) return _syncDistrictToMemory(data[0]);
        } catch (_) { }
        return _inMemoryDistricts.find(d => {
            return Object.entries(query).every(([k, v]) => d[k] === v);
        }) || null;
    },

    async create(districtData) {
        const row = {
            id: districtData.id || `dist-${Date.now()}-${Math.floor(Math.random() * 1000)}`,
            name: (districtData.name || '').trim(),
            state: (districtData.state || 'Telangana').trim(),
            country: districtData.country || 'India',
            is_active: districtData.is_active !== undefined ? districtData.is_active : true,
            created_at: new Date().toISOString(),
            updated_at: new Date().toISOString()
        };

        try {
            const { data, error } = await supabaseAdmin.from('districts').insert(row).select().single();
            if (!error && data) {
                _inMemoryDistricts.push(data);
                return data;
            }
        } catch (_) { }

        _inMemoryDistricts.push(row);
        return row;
    },

    async findByIdAndUpdate(id, updates) {
        const updatePayload = {
            ...updates,
            updated_at: new Date().toISOString()
        };

        try {
            const { data, error } = await supabaseAdmin.from('districts').update(updatePayload).eq('id', id).select().single();
            if (!error && data) {
                const idx = _inMemoryDistricts.findIndex(d => d.id === id);
                if (idx !== -1) _inMemoryDistricts[idx] = { ..._inMemoryDistricts[idx], ...data };
                return data;
            }
        } catch (_) { }

        const idx = _inMemoryDistricts.findIndex(d => d.id === id);
        if (idx !== -1) {
            _inMemoryDistricts[idx] = { ..._inMemoryDistricts[idx], ...updatePayload };
            return _inMemoryDistricts[idx];
        }
        return null;
    },

    resolveDistrictFromLocation({ city, district, state, pincode }) {
        const cLower = (city || '').trim().toLowerCase();
        const dLower = (district || '').trim().toLowerCase();
        const pin = (pincode || '').toString().trim();

        // 1. Direct district name match
        if (dLower) {
            const matched = _inMemoryDistricts.find(d => d.name.toLowerCase() === dLower || d.name.toLowerCase().includes(dLower));
            if (matched) return { district: matched.name, districtId: matched.id, status: 'IDENTIFIED' };
        }

        // 2. City name match
        if (cLower) {
            if (cLower.includes('hyderabad')) {
                const matched = _inMemoryDistricts.find(d => d.name === 'Hyderabad');
                return { district: matched?.name || 'Hyderabad', districtId: matched?.id, status: 'IDENTIFIED' };
            }
            if (cLower.includes('secunderabad') || cLower.includes('medchal') || cLower.includes('malkajgiri')) {
                const matched = _inMemoryDistricts.find(d => d.name === 'Medchal-Malkajgiri');
                return { district: matched?.name || 'Medchal-Malkajgiri', districtId: matched?.id, status: 'IDENTIFIED' };
            }
            if (cLower.includes('rangareddy') || cLower.includes('cyberabad') || cLower.includes('gachibowli') || cLower.includes('madhapur')) {
                const matched = _inMemoryDistricts.find(d => d.name === 'Rangareddy');
                return { district: matched?.name || 'Rangareddy', districtId: matched?.id, status: 'IDENTIFIED' };
            }
            if (cLower.includes('warangal') || cLower.includes('hanamkonda') || cLower.includes('kazipet')) {
                const matched = _inMemoryDistricts.find(d => d.name === 'Warangal');
                return { district: matched?.name || 'Warangal', districtId: matched?.id, status: 'IDENTIFIED' };
            }
            if (cLower.includes('karimnagar')) {
                const matched = _inMemoryDistricts.find(d => d.name === 'Karimnagar');
                return { district: matched?.name || 'Karimnagar', districtId: matched?.id, status: 'IDENTIFIED' };
            }
            if (cLower.includes('nizamabad')) {
                const matched = _inMemoryDistricts.find(d => d.name === 'Nizamabad');
                return { district: matched?.name || 'Nizamabad', districtId: matched?.id, status: 'IDENTIFIED' };
            }
            if (cLower.includes('adilabad')) {
                const matched = _inMemoryDistricts.find(d => d.name === 'Adilabad');
                return { district: matched?.name || 'Adilabad', districtId: matched?.id, status: 'IDENTIFIED' };
            }
            if (cLower.includes('mumbai') || cLower.includes('bandra') || cLower.includes('andheri') || cLower.includes('juhu') || cLower.includes('borivali')) {
                const matched = _inMemoryDistricts.find(d => d.name === 'Mumbai Suburban');
                return { district: matched?.name || 'Mumbai Suburban', districtId: matched?.id, status: 'IDENTIFIED' };
            }
            if (cLower.includes('colaba') || cLower.includes('dadar') || cLower.includes('nariman')) {
                const matched = _inMemoryDistricts.find(d => d.name === 'Mumbai City');
                return { district: matched?.name || 'Mumbai City', districtId: matched?.id, status: 'IDENTIFIED' };
            }
            if (cLower.includes('pune')) {
                const matched = _inMemoryDistricts.find(d => d.name === 'Pune');
                return { district: matched?.name || 'Pune', districtId: matched?.id, status: 'IDENTIFIED' };
            }
            if (cLower.includes('thane')) {
                const matched = _inMemoryDistricts.find(d => d.name === 'Thane');
                return { district: matched?.name || 'Thane', districtId: matched?.id, status: 'IDENTIFIED' };
            }
            if (cLower.includes('bengaluru') || cLower.includes('bangalore')) {
                const matched = _inMemoryDistricts.find(d => d.name === 'Bengaluru Urban');
                return { district: matched?.name || 'Bengaluru Urban', districtId: matched?.id, status: 'IDENTIFIED' };
            }
            if (cLower.includes('chennai') || cLower.includes('madras')) {
                const matched = _inMemoryDistricts.find(d => d.name === 'Chennai');
                return { district: matched?.name || 'Chennai', districtId: matched?.id, status: 'IDENTIFIED' };
            }
            if (cLower.includes('delhi')) {
                const matched = _inMemoryDistricts.find(d => d.name === 'Delhi');
                return { district: matched?.name || 'Delhi', districtId: matched?.id, status: 'IDENTIFIED' };
            }
        }

        // 3. Indian Postal Pincode prefix match
        if (pin.length >= 3) {
            const prefix = pin.substring(0, 3);
            if (prefix === '500') {
                const matched = _inMemoryDistricts.find(d => d.name === 'Hyderabad');
                return { district: matched?.name || 'Hyderabad', districtId: matched?.id, status: 'IDENTIFIED' };
            }
            if (prefix === '506') {
                const matched = _inMemoryDistricts.find(d => d.name === 'Warangal');
                return { district: matched?.name || 'Warangal', districtId: matched?.id, status: 'IDENTIFIED' };
            }
            if (prefix === '505') {
                const matched = _inMemoryDistricts.find(d => d.name === 'Karimnagar');
                return { district: matched?.name || 'Karimnagar', districtId: matched?.id, status: 'IDENTIFIED' };
            }
            if (prefix === '503') {
                const matched = _inMemoryDistricts.find(d => d.name === 'Nizamabad');
                return { district: matched?.name || 'Nizamabad', districtId: matched?.id, status: 'IDENTIFIED' };
            }
            if (prefix === '504') {
                const matched = _inMemoryDistricts.find(d => d.name === 'Adilabad');
                return { district: matched?.name || 'Adilabad', districtId: matched?.id, status: 'IDENTIFIED' };
            }
            if (prefix === '400') {
                const matched = _inMemoryDistricts.find(d => d.name === 'Mumbai Suburban');
                return { district: matched?.name || 'Mumbai Suburban', districtId: matched?.id, status: 'IDENTIFIED' };
            }
            if (prefix === '411') {
                const matched = _inMemoryDistricts.find(d => d.name === 'Pune');
                return { district: matched?.name || 'Pune', districtId: matched?.id, status: 'IDENTIFIED' };
            }
            if (prefix === '560') {
                const matched = _inMemoryDistricts.find(d => d.name === 'Bengaluru Urban');
                return { district: matched?.name || 'Bengaluru Urban', districtId: matched?.id, status: 'IDENTIFIED' };
            }
        }

        // 4. District unidentifiable -> Requires admin review
        return {
            district: null,
            districtId: null,
            status: 'PENDING_ADMIN_REVIEW'
        };
    }
};

// 1d. SUB-ADMIN DISTRICT MAPPINGS MODEL (Many-to-Many: Sub-Admin <-> District)
const _inMemorySubAdminDistricts = [];

const SubAdminDistrict = {
    async getDistrictsForSubAdmin(userId) {
        if (!userId) return [];
        try {
            const { data, error } = await supabaseAdmin
                .from('sub_admin_districts')
                .select('district_id, districts(*)')
                .eq('sub_admin_user_id', userId);
            if (!error && data && data.length > 0) {
                return data.map(d => d.districts).filter(Boolean);
            }
        } catch (_) { }

        // In-memory fallback (resolves against synced _inMemoryDistricts and Supabase District.findById)
        const mappings = _inMemorySubAdminDistricts.filter(m => m.sub_admin_user_id === userId);
        const resolved = [];
        for (const m of mappings) {
            const dist = _inMemoryDistricts.find(d => d.id === m.district_id)
                || await District.findById(m.district_id);
            if (dist) resolved.push(dist);
        }
        return resolved;
    },

    async getSubAdminsForDistrict(districtId) {
        if (!districtId) return [];
        const dbIds = [];
        try {
            const { data, error } = await supabaseAdmin
                .from('sub_admin_districts')
                .select('sub_admin_user_id')
                .eq('district_id', districtId);
            if (!error && Array.isArray(data)) {
                for (const row of data) {
                    if (row.sub_admin_user_id) dbIds.push(row.sub_admin_user_id);
                }
            }
        } catch (_) { }

        const memIds = _inMemorySubAdminDistricts
            .filter(m => m.district_id === districtId)
            .map(m => m.sub_admin_user_id);
        return [...new Set([...dbIds, ...memIds])];
    },

    async assignDistrictsToSubAdmin(userId, districtIds = [], assignedBy = null) {
        if (!userId) return [];
        // Deduplicate district IDs
        const uniqueDistrictIds = [...new Set(districtIds.filter(Boolean))];

        try {
            await supabaseAdmin.from('sub_admin_districts').delete().eq('sub_admin_user_id', userId);
            if (uniqueDistrictIds.length > 0) {
                const rows = uniqueDistrictIds.map(dId => ({
                    sub_admin_user_id: userId,
                    district_id: dId,
                    assigned_by: assignedBy,
                    created_at: new Date().toISOString()
                }));
                await supabaseAdmin.from('sub_admin_districts').insert(rows);
            }
        } catch (_) { }

        // In-memory update
        for (let i = _inMemorySubAdminDistricts.length - 1; i >= 0; i--) {
            if (_inMemorySubAdminDistricts[i].sub_admin_user_id === userId) {
                _inMemorySubAdminDistricts.splice(i, 1);
            }
        }
        for (const dId of uniqueDistrictIds) {
            _inMemorySubAdminDistricts.push({
                id: `sad-${Date.now()}-${Math.floor(Math.random() * 1000)}`,
                sub_admin_user_id: userId,
                district_id: dId,
                assigned_by: assignedBy,
                created_at: new Date().toISOString()
            });
        }

        return this.getDistrictsForSubAdmin(userId);
    },

    async removeDistrictFromSubAdmin(userId, districtId) {
        if (!userId || !districtId) return false;
        try {
            await supabaseAdmin.from('sub_admin_districts')
                .delete()
                .eq('sub_admin_user_id', userId)
                .eq('district_id', districtId);
        } catch (_) { }

        const idx = _inMemorySubAdminDistricts.findIndex(
            m => m.sub_admin_user_id === userId && m.district_id === districtId
        );
        if (idx !== -1) {
            _inMemorySubAdminDistricts.splice(idx, 1);
            return true;
        }
        return false;
    }
};

// 1e. PERMISSION CHANGE AUDIT LOG MODEL
const _inMemoryPermissionHistory = [];

const PermissionChangeHistory = {
    async logChange({ subAdminUserId, changedByUserId, changedByRole = 'Admin', action, permissionKey, previousState = null, newState = null, reason = '' }) {
        const record = {
            id: `pch-${Date.now()}-${Math.floor(Math.random() * 1000)}`,
            sub_admin_user_id: subAdminUserId,
            changed_by_user_id: changedByUserId,
            changed_by_role: changedByRole,
            action: action || 'MODIFIED',
            permission_key: permissionKey,
            previous_state: previousState,
            new_state: newState,
            reason: reason || 'Permission updated by administrator.',
            created_at: new Date().toISOString()
        };

        try {
            await supabaseAdmin.from('permission_change_history').insert(record);
        } catch (_) { }

        _inMemoryPermissionHistory.unshift(record);
        return record;
    },

    async getHistoryForUser(subAdminUserId) {
        try {
            const { data, error } = await supabaseAdmin
                .from('permission_change_history')
                .select('*')
                .eq('sub_admin_user_id', subAdminUserId)
                .order('created_at', { ascending: false });
            if (!error && data && data.length > 0) return data;
        } catch (_) { }

        return _inMemoryPermissionHistory.filter(h => h.sub_admin_user_id === subAdminUserId);
    }
};

// 1f. IMMUTABLE PATIENT ASSIGNMENT AUDIT HISTORY MODEL
const _inMemoryAssignmentHistory = [];

const PatientAssignmentHistory = {
    async recordAssignment({
        patientId,
        doctorId,
        appointmentId = null,
        requestId = null,
        assignedByUserId = null,
        assignedByName = 'Direct Patient Booking',
        assignedByRole = 'PATIENT',
        assignmentSource = ASSIGNMENT_SOURCES.PATIENT_DIRECT_BOOKING,
        districtId = null,
        districtName = '',
        previousAssignmentId = null,
        assignmentReason = '',
        status = 'ASSIGNED'
    }) {
        const record = {
            id: `pah-${Date.now()}-${Math.floor(Math.random() * 10000)}`,
            patient_id: patientId,
            doctor_id: doctorId,
            appointment_id: appointmentId,
            request_id: requestId,
            assigned_by_user_id: assignedByUserId,
            assigned_by_name: assignedByName,
            assigned_by_role: assignedByRole,
            assignment_source: assignmentSource,
            district_id: districtId,
            district_name: districtName,
            previous_assignment_id: previousAssignmentId,
            assignment_reason: assignmentReason,
            status: status,
            created_at: new Date().toISOString()
        };

        try {
            const { data, error } = await supabaseAdmin
                .from('patient_assignment_history')
                .insert(record)
                .select()
                .single();
            if (!error && data) {
                _inMemoryAssignmentHistory.unshift(data);
                return data;
            }
        } catch (_) { }

        _inMemoryAssignmentHistory.unshift(record);
        return record;
    },

    async getHistory(filters = {}) {
        let dbRows = [];
        try {
            let req = supabaseAdmin.from('patient_assignment_history').select('*');
            if (filters.patientId) req = req.eq('patient_id', filters.patientId);
            if (filters.doctorId) req = req.eq('doctor_id', filters.doctorId);
            if (filters.districtId) req = req.eq('district_id', filters.districtId);
            if (filters.assignedByUserId) req = req.eq('assigned_by_user_id', filters.assignedByUserId);
            if (filters.assignedByRole) req = req.eq('assigned_by_role', filters.assignedByRole);
            if (filters.assignmentSource) req = req.eq('assignment_source', filters.assignmentSource);
            if (filters.status) req = req.eq('status', filters.status);
            req = req.order('created_at', { ascending: false });
            const { data, error } = await req;
            if (!error && Array.isArray(data)) {
                dbRows = data;
            }
        } catch (_) { }

        // Merge Supabase rows with in-memory fallback records (deduplicated by id)
        const seenIds = new Set(dbRows.map(r => r.id));
        let list = [
            ...dbRows,
            ..._inMemoryAssignmentHistory.filter(h => !seenIds.has(h.id))
        ];
        if (filters.patientId) list = list.filter(h => h.patient_id === filters.patientId);
        if (filters.doctorId) list = list.filter(h => h.doctor_id === filters.doctorId);
        if (filters.districtId) list = list.filter(h => h.district_id === filters.districtId);
        if (filters.assignedByUserId) list = list.filter(h => h.assigned_by_user_id === filters.assignedByUserId);
        if (filters.assignedByRole) list = list.filter(h => h.assigned_by_role === filters.assignedByRole);
        if (filters.assignmentSource) list = list.filter(h => h.assignment_source === filters.assignmentSource);
        if (filters.status) list = list.filter(h => h.status === filters.status);
        if (filters.search) {
            const q = filters.search.toLowerCase();
            list = list.filter(h =>
                (h.assigned_by_name && h.assigned_by_name.toLowerCase().includes(q)) ||
                (h.district_name && h.district_name.toLowerCase().includes(q)) ||
                (h.assignment_reason && h.assignment_reason.toLowerCase().includes(q)) ||
                (h.patient_id && h.patient_id.toLowerCase().includes(q))
            );
        }
        return list;
    },

    async getHistoryForPatient(patientId) {
        if (!patientId) return [];
        return this.getHistory({ patientId });
    },

    async getStatistics() {
        const history = await this.getHistory();
        const directBookings = history.filter(h => h.assignment_source === ASSIGNMENT_SOURCES.PATIENT_DIRECT_BOOKING).length;
        const adminAssignments = history.filter(h => h.assignment_source === ASSIGNMENT_SOURCES.MAIN_ADMIN_ASSIGNMENT).length;
        const subAdminAssignments = history.filter(h => h.assignment_source === ASSIGNMENT_SOURCES.SUB_ADMIN_ASSIGNMENT).length;
        const uniquePatientsAssigned = new Set(history.map(h => h.patient_id)).size;

        const districtCounts = {};
        for (const h of history) {
            const dName = h.district_name || 'Unassigned / Review';
            districtCounts[dName] = (districtCounts[dName] || 0) + 1;
        }

        return {
            totalAssignments: history.length,
            totalAssignedPatients: uniquePatientsAssigned,
            directBookings,
            adminAssignments,
            subAdminAssignments,
            districtCounts
        };
    }
};

// Helper: attach associated owner email/phone to clinic rows cleanly
function _hydrateClinicRecord(c) {
    if (!c) return c;
    const u = Array.isArray(c.users) ? c.users[0] : c.users;
    return {
        ...c,
        email: c.email || u?.email || '',
        phone: c.phone || u?.phone || ''
    };
}

// 2. CLINIC MODEL (Supabase PostgreSQL)
const Clinic = {
    async findOne(query) {
        let req = supabaseAdmin.from('clinics').select('*, users(id, name, email, phone)');
        for (const [key, val] of Object.entries(query)) {
            if (key === 'clinic_name' && typeof val === 'string') {
                const safePattern = val.trim().replace(/[%_]/g, '\\$&');
                req = req.ilike('clinic_name', safePattern);
            } else {
                req = req.eq(key, val);
            }
        }
        let { data, error } = await req.limit(1);
        if (error) {
            let fallbackReq = supabaseAdmin.from('clinics').select('*');
            for (const [key, val] of Object.entries(query)) {
                if (key === 'clinic_name' && typeof val === 'string') {
                    const safePattern = val.trim().replace(/[%_]/g, '\\$&');
                    fallbackReq = fallbackReq.ilike('clinic_name', safePattern);
                } else {
                    fallbackReq = fallbackReq.eq(key, val);
                }
            }
            const fb = await fallbackReq.limit(1);
            if (fb.error) throw fb.error;
            data = fb.data;
        }
        const row = Array.isArray(data) ? (data[0] || null) : data;
        return _hydrateClinicRecord(row);
    },

    async findById(id) {
        let { data, error } = await supabaseAdmin.from('clinics').select('*, users(id, name, email, phone)').eq('id', id).single();
        if (error) {
            const fb = await supabaseAdmin.from('clinics').select('*').eq('id', id).single();
            if (fb.error) return null;
            data = fb.data;
        }
        return _hydrateClinicRecord(data);
    },

    async find(query = {}) {
        try {
            let req = supabaseAdmin.from('clinics').select('*, users(id, name, email, phone)');
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
                return (simple.data || []).map(_hydrateClinicRecord);
            }
            return (data || []).map(_hydrateClinicRecord);
        } catch (e) {
            console.warn('⚠️ Clinic query exception, falling back to simple select:', e.message);
            const simple = await supabaseAdmin.from('clinics').select('*');
            return (simple.data || []).map(_hydrateClinicRecord);
        }
    },

    async create(clinicData) {
        const rawUserId = clinicData.user_id || clinicData.userId;
        const isUuid = rawUserId && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(rawUserId.toString());
        const validUserId = isUuid ? rawUserId.toString() : null;

        const parsedLat = clinicData.latitude !== undefined && clinicData.latitude !== null && String(clinicData.latitude).trim() !== ''
            ? Number(clinicData.latitude)
            : (clinicData.coordinates?.coordinates?.[1] !== undefined ? Number(clinicData.coordinates.coordinates[1]) : null);
        const parsedLng = clinicData.longitude !== undefined && clinicData.longitude !== null && String(clinicData.longitude).trim() !== ''
            ? Number(clinicData.longitude)
            : (clinicData.coordinates?.coordinates?.[0] !== undefined ? Number(clinicData.coordinates.coordinates[0]) : null);

        const payload = {
            user_id: validUserId,
            clinic_name: clinicData.clinic_name || clinicData.clinicName || '',
            location: clinicData.location || '',
            rating: clinicData.rating ?? 0,
            reviews_count: clinicData.reviews_count || clinicData.reviewsCount || 0,
            verified: clinicData.verified !== undefined ? clinicData.verified : true,
            services: clinicData.services || clinicData.departments || ['General Medicine', 'General Consultation'],
            pricing: clinicData.pricing || [],
            latitude: Number.isFinite(parsedLat) ? parsedLat : null,
            longitude: Number.isFinite(parsedLng) ? parsedLng : null
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
        } catch (_) { }
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

const SUPPORTED_LANGUAGES = [
    'English',
    'Hindi',
    'Telugu',
    'Tamil',
    'Kannada',
    'Malayalam',
    'Marathi',
    'Bengali',
    'Gujarati',
    'Punjabi',
    'Urdu',
    'Odia',
];

const LANGUAGE_ALIASES = {
    en: 'english',
    eng: 'english',
    english: 'english',
    hi: 'hindi',
    hin: 'hindi',
    hindi: 'hindi',
    te: 'telugu',
    tel: 'telugu',
    telugu: 'telugu',
    ta: 'tamil',
    tam: 'tamil',
    tamil: 'tamil',
    kn: 'kannada',
    kan: 'kannada',
    kannada: 'kannada',
    ml: 'malayalam',
    mal: 'malayalam',
    malayalam: 'malayalam',
    mr: 'marathi',
    mar: 'marathi',
    marathi: 'marathi',
    bn: 'bengali',
    ben: 'bengali',
    bangla: 'bengali',
    bengali: 'bengali',
    gu: 'gujarati',
    guj: 'gujarati',
    gujarati: 'gujarati',
    pa: 'punjabi',
    pan: 'punjabi',
    panjabi: 'punjabi',
    punjabi: 'punjabi',
    ur: 'urdu',
    urd: 'urdu',
    urdu: 'urdu',
    or: 'odia',
    ori: 'odia',
    oriya: 'odia',
    odia: 'odia',
};

const _CANONICAL_LANGUAGE_DISPLAY_MAP = SUPPORTED_LANGUAGES.reduce((acc, lang) => {
    acc[lang.toLowerCase()] = lang;
    return acc;
}, {});

function _splitRawLanguageTokens(rawInput) {
    let items = [];
    if (Array.isArray(rawInput)) {
        items = rawInput;
    } else if (typeof rawInput === 'string') {
        const trimmed = rawInput.trim();
        if (!trimmed) return [];
        if (trimmed.startsWith('[')) {
            try {
                const parsed = JSON.parse(trimmed);
                if (Array.isArray(parsed)) {
                    items = parsed;
                } else {
                    items = trimmed.split(/[,;/|]+/);
                }
            } catch (_) {
                items = trimmed.split(/[,;/|]+/);
            }
        } else if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
            items = trimmed.slice(1, -1).split(/[,;/|]+/);
        } else {
            items = trimmed.split(/[,;/|]+/);
        }
    } else {
        return [];
    }

    const tokens = [];
    for (const item of items) {
        if (item == null) continue;
        if (Array.isArray(item)) {
            tokens.push(..._splitRawLanguageTokens(item));
            continue;
        }
        let str = String(item).trim();
        if (!str) continue;
        if ((str.startsWith('"') && str.endsWith('"')) || (str.startsWith("'") && str.endsWith("'"))) {
            str = str.slice(1, -1).trim();
        }
        if (/[,;/|]/.test(str)) {
            for (const part of str.split(/[,;/|]+/)) {
                const collapsed = part.replace(/\s+/g, ' ').trim();
                if (collapsed) tokens.push(collapsed);
            }
        } else {
            const collapsed = str.replace(/\s+/g, ' ').trim();
            if (collapsed) tokens.push(collapsed);
        }
    }
    return tokens;
}

function canonicalLanguageKey(raw) {
    if (raw == null) return '';
    let cleaned = String(raw).replace(/\s+/g, ' ').trim().toLowerCase();
    if (!cleaned) return '';
    // Strip parenthetical qualifiers such as "Telugu (Fluent)" -> "telugu"
    cleaned = cleaned.replace(/\s*\([^)]*\)/g, ' ').replace(/\s+/g, ' ').trim();
    if (!cleaned) return '';
    if (LANGUAGE_ALIASES[cleaned]) {
        return LANGUAGE_ALIASES[cleaned];
    }
    return cleaned;
}

function canonicalLanguageDisplayName(raw) {
    const collapsed = String(raw || '').replace(/\s+/g, ' ').trim();
    if (!collapsed) return '';
    const key = canonicalLanguageKey(collapsed);
    if (key && _CANONICAL_LANGUAGE_DISPLAY_MAP[key]) {
        return _CANONICAL_LANGUAGE_DISPLAY_MAP[key];
    }
    // Strip parenthetical qualifier if present so label remains clean unless needed
    const withoutParen = collapsed.replace(/\s*\([^)]*\)/g, ' ').replace(/\s+/g, ' ').trim();
    const base = withoutParen || collapsed;
    if (base === base.toLowerCase() || base === base.toUpperCase()) {
        return base.split(' ').map(w => (w ? w[0].toUpperCase() + w.slice(1).toLowerCase() : '')).join(' ');
    }
    return base;
}

function normalizeLanguagesList(rawLanguages) {
    const tokens = _splitRawLanguageTokens(rawLanguages);
    const seen = new Set();
    const result = [];
    for (const token of tokens) {
        const key = canonicalLanguageKey(token);
        if (!key) continue;
        if (!seen.has(key)) {
            seen.add(key);
            result.push(canonicalLanguageDisplayName(token));
        }
    }
    return result;
}

function parseLanguageFilters(rawInput) {
    if (!rawInput) return [];
    const tokens = _splitRawLanguageTokens(rawInput);
    const seen = new Set();
    const result = [];
    for (const token of tokens) {
        const key = canonicalLanguageKey(token);
        if (!key || key === 'any' || key === 'any language' || key === 'all' || key === 'all languages') {
            continue;
        }
        if (!seen.has(key)) {
            seen.add(key);
            result.push(key);
        }
    }
    return result;
}

function mergeSupportedAndDoctorLanguages(doctorLanguagesIterable = []) {
    const seen = new Set();
    const canonicalList = [];
    const extraCustomList = [];

    for (const lang of SUPPORTED_LANGUAGES) {
        const key = canonicalLanguageKey(lang);
        if (key && !seen.has(key)) {
            seen.add(key);
            canonicalList.push(lang);
        }
    }

    for (const rawLang of (doctorLanguagesIterable || [])) {
        for (const token of _splitRawLanguageTokens(rawLang)) {
            const key = canonicalLanguageKey(token);
            if (!key || key === 'any' || key === 'any language' || key === 'all' || key === 'all languages') {
                continue;
            }
            if (!seen.has(key)) {
                seen.add(key);
                extraCustomList.push(canonicalLanguageDisplayName(token));
            }
        }
    }

    extraCustomList.sort((a, b) => a.toLowerCase().localeCompare(b.toLowerCase()));
    return [...canonicalList, ...extraCustomList];
}

function extractDoctorLanguages(d) {
    if (!d || typeof d !== 'object') return ['English'];
    const uObj = d.users && typeof d.users === 'object' ? d.users : {};
    const dLangs = normalizeLanguagesList(d.languages);
    const uLangs = normalizeLanguagesList(uObj.languages);
    let metaLangs = [];
    const devToken = uObj.device_token || d.device_token;
    if (devToken && typeof devToken === 'string' && devToken.trim().startsWith('{')) {
        try {
            const meta = JSON.parse(devToken);
            if (meta && meta.languages) {
                metaLangs = normalizeLanguagesList(meta.languages);
            }
        } catch (_) { }
    }

    // Prefer dentists.languages when explicitly populated beyond the default ['English'],
    // or fall back to users.languages / users.device_token.languages when legacy rows only had default ['English'].
    if (dLangs.length > 1 || (dLangs.length === 1 && dLangs[0].toLowerCase() !== 'english')) {
        return dLangs;
    }
    if (uLangs.length > 1 || (uLangs.length === 1 && uLangs[0].toLowerCase() !== 'english')) {
        return uLangs;
    }
    if (metaLangs.length > 0) {
        return metaLangs;
    }
    if (dLangs.length > 0) return dLangs;
    if (uLangs.length > 0) return uLangs;
    return ['English'];
}

function doctorMatchesLanguages(doctor, selectedLangsInput) {
    const selected = parseLanguageFilters(selectedLangsInput);
    if (selected.length === 0) return true;
    const docLangKeys = extractDoctorLanguages(doctor)
        .flatMap(l => _splitRawLanguageTokens(l))
        .map(l => canonicalLanguageKey(l))
        .filter(Boolean);
    return selected.some(target =>
        docLangKeys.some(dl => dl === target || dl.startsWith(`${target} `))
    );
}

const CANONICAL_SPECIALTY_GROUPS = {
    NEURO: ['neurology', 'neurologist', 'neurosciences', 'stroke medicine', 'epileptology'],
    CARDIO: ['cardiology', 'cardiologist', 'interventional cardiology', 'electrophysiology', 'cardiovascular'],
    GEN_MED: ['general physician / mbbs', 'general physician', 'general medicine', 'internal medicine', 'family medicine', 'mbbs physician', 'primary care physician', 'mbbs'],
    ORTHO: ['orthopedics', 'orthopaedics', 'orthopedist', 'orthopedic surgeon', 'orthopaedic surgeon', 'joint replacement', 'spine surgery', 'sports medicine'],
    DERM: ['dermatology', 'dermatologist', 'clinical dermatology', 'cosmetology', 'trichology', 'venereology'],
    PEDIA: ['pediatrics', 'paediatrics', 'pediatrician', 'neonatology', 'pediatric critical care'],
    GYNEC: ['gynecology', 'gynaecology', 'gynecologist', 'obstetrics', 'obstetrics & gynecology', 'obgyn', 'fetal medicine', 'reproductive medicine'],
    ENT: ['ent', 'otorhinolaryngology', 'otolaryngology', 'ear, nose & throat', 'ear nose throat', 'otology', 'rhinology', 'laryngology'],
    OPHTHAL: ['ophthalmology', 'ophthalmologist', 'retina', 'cornea', 'glaucoma'],
    ONCO: ['oncology', 'oncologist', 'medical oncology', 'surgical oncology', 'radiation oncology'],
    URO: ['urology', 'urologist', 'endourology', 'andrology', 'uro-oncology'],
    PSYCH: ['psychiatry', 'psychiatrist', 'adult psychiatry', 'child & adolescent psychiatry'],
    GASTRO: ['gastroenterology', 'gastroenterologist', 'hepatology', 'therapeutic endoscopy'],
    PULMO: ['pulmonology', 'pulmonologist', 'pulmonary medicine', 'respiratory medicine', 'interventional pulmonology', 'sleep medicine'],
    ENDO: ['endocrinology', 'endocrinologist', 'diabetology', 'thyroid & metabolic medicine'],
};

function _resolveCanonicalSpecialtyGroup(rawText) {
    const s = String(rawText || '').trim().toLowerCase();
    if (!s) return null;
    if (isDentalSpecialtyText(s) || s === 'dentist' || s === 'general dentist' || s.includes('orthodont') || s.includes('endodont') || s.includes('periodont') || s.includes('prosthodont') || s.includes('pedodont')) {
        return 'DENTAL';
    }
    for (const [group, aliases] of Object.entries(CANONICAL_SPECIALTY_GROUPS)) {
        if (aliases.some(alias => s === alias || s.includes(alias))) {
            return group;
        }
    }
    return null;
}

function matchesSpecialtyQuery(doctorSpec, filterSpec) {
    if (!filterSpec || filterSpec.trim().toLowerCase() === 'all' || filterSpec.trim().toLowerCase() === 'all specialties') return true;
    const f = filterSpec.trim().toLowerCase();
    const d = String(doctorSpec || '').trim().toLowerCase();
    if (!d) return false;
    if (d === f) return true;

    const isDentalDoc = _resolveCanonicalSpecialtyGroup(d) === 'DENTAL';
    const isDentalFilter = _resolveCanonicalSpecialtyGroup(f) === 'DENTAL';

    if (f === 'dentistry' || f === 'dental') {
        return isDentalDoc;
    }
    if (isDentalFilter) {
        if (!isDentalDoc) return false;
        if (f.includes('general dentist')) return d.includes('general dentist') || d === 'dentistry' || d === 'dental' || d === 'dentist';
        if (f.includes('orthodont')) return d.includes('orthodont');
        if (f.includes('endodont')) return d.includes('endodont');
        if (f.includes('periodont')) return d.includes('periodont');
        if (f.includes('prosthodont')) return d.includes('prosthodont');
        if (f.includes('pedodont') || f.includes('pediatric dentist')) return d.includes('pedodont') || d.includes('pediatric dentist');
        if (f.includes('oral')) return d.includes('oral') || d.includes('maxillofacial');
        if (f.includes('cosmetic')) return d.includes('cosmetic');
        if (f.includes('implant')) return d.includes('implant');
        return d === f;
    }
    if (isDentalDoc) return false;

    const fGroup = _resolveCanonicalSpecialtyGroup(f);
    const dGroup = _resolveCanonicalSpecialtyGroup(d);
    if (fGroup || dGroup) {
        return Boolean(fGroup && fGroup === dGroup);
    }

    for (const spec of _inMemorySpecialties) {
        const specLower = String(spec.name || '').trim().toLowerCase();
        if (specLower === f) {
            if (d === specLower) return true;
            if (Array.isArray(spec.sub_specialties) && spec.sub_specialties.some(sub => {
                const subLower = String(sub || '').trim().toLowerCase();
                return subLower && (d === subLower || d.includes(subLower));
            })) {
                return true;
            }
        }
    }

    return false;
}

const GENERIC_PLACEHOLDER_LICENSES = new Set([
    'med-lic-reg',
    'med-lic-registered',
    'pending',
    'na',
    'n/a',
]);

async function resolveMedicalSpecialtyRecord(rawSpecialty, rawSpecialtyId = null) {
    const cleanInput = String(rawSpecialty || '').trim();
    const cleanId = rawSpecialtyId && isUUID(String(rawSpecialtyId)) ? String(rawSpecialtyId).trim() : null;
    try {
        const list = await MedicalSpecialty.find({ activeOnly: true });
        if (cleanId) {
            const byId = list.find(s => String(s.id) === cleanId);
            if (byId) {
                return {
                    specialty: cleanInput || byId.name,
                    specialty_id: isUUID(String(byId.id)) ? byId.id : null,
                    department: byId.department || `Department of ${byId.name}`
                };
            }
        }
        if (cleanInput) {
            const lower = cleanInput.toLowerCase();
            const exact = list.find(s =>
                (s.name && s.name.toLowerCase() === lower) ||
                (s.code && s.code.toLowerCase() === lower) ||
                (Array.isArray(s.sub_specialties) && s.sub_specialties.some(sub => String(sub).toLowerCase() === lower))
            );
            if (exact) {
                return {
                    specialty: cleanInput,
                    specialty_id: isUUID(String(exact.id)) ? exact.id : null,
                    department: exact.department || `Department of ${exact.name}`
                };
            }
            const { getSpecialtyClinicalConfig } = require('../config/specialtyClinicalConfig');
            const cfg = getSpecialtyClinicalConfig(cleanInput);
            if (cfg) {
                const byCfg = list.find(s =>
                    (s.code && cfg.code && s.code.toLowerCase() === cfg.code.toLowerCase()) ||
                    (s.name && cfg.name && s.name.toLowerCase() === cfg.name.toLowerCase())
                );
                if (byCfg) {
                    return {
                        specialty: cleanInput,
                        specialty_id: isUUID(String(byCfg.id)) ? byCfg.id : null,
                        department: byCfg.department || `Department of ${byCfg.name}`
                    };
                }
            }
        }
    } catch (_) { }
    const fallbackSpec = (cleanInput && cleanInput.toLowerCase() !== 'dentist') ? cleanInput : 'General Medicine';
    return {
        specialty: fallbackSpec,
        specialty_id: cleanId,
        department: `Department of ${fallbackSpec}`
    };
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
            let req = supabaseAdmin.from('dentists').select('*, users(name, email, phone, state, city, pincode, latitude, longitude, device_token, biometric_token), clinics(clinic_name, location, latitude, longitude)');
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

            const langFilters = parseLanguageFilters(query.languages || query.language);
            if (langFilters.length > 0) {
                list = list.filter(d => doctorMatchesLanguages(d, langFilters));
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
                .select('*, users(name, email, phone, state, city, pincode, latitude, longitude, device_token, biometric_token), clinics(clinic_name, location, latitude, longitude)')
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
        const rawSpecInput = (dentistData.speciality || dentistData.specialty || dentistData.specialtyName || '').toString().trim();
        const specResolution = await resolveMedicalSpecialtyRecord(
            rawSpecInput || 'General Medicine',
            dentistData.specialty_id || dentistData.specialtyId || null
        );
        const resolvedSpec = specResolution.specialty;
        const resolvedQual = dentistData.qualifications || dentistData.qualification || getDefaultQualificationForSpecialty(resolvedSpec);

        const cleanLanguages = normalizeLanguagesList(dentistData.languages || dentistData.languagesKnown);
        const finalLanguages = cleanLanguages.length > 0 ? cleanLanguages : ['English'];

        let candidateLic = String(dentistData.license_number || dentistData.licenseNumber || '').trim();
        if (!candidateLic || GENERIC_PLACEHOLDER_LICENSES.has(candidateLic.toLowerCase())) {
            candidateLic = `MED-LIC-${Date.now()}-${Math.floor(1000 + Math.random() * 9000)}`;
        } else {
            const existingByLic = await this.findOne({ license_number: candidateLic }).catch(() => null);
            if (existingByLic && (!validUserId || existingByLic.user_id !== validUserId)) {
                candidateLic = `${candidateLic}-${Date.now().toString().slice(-5)}-${Math.floor(100 + Math.random() * 900)}`;
            }
        }

        const { normalizeConsultationMode, validateCoordinates } = require('../utils/doctorClinicLocationHelper');
        const resolvedConsultationMode = normalizeConsultationMode(
            dentistData.consultation_mode || dentistData.consultationMode,
            'BOTH'
        );
        const coordCheck = validateCoordinates(dentistData.latitude, dentistData.longitude, false);

        const payload = {
            user_id: validUserId,
            clinic_id: resolvedConsultationMode === 'ONLINE_ONLY' ? null : validClinicId,
            speciality: resolvedSpec,
            specialty_id: specResolution.specialty_id || null,
            department: dentistData.department || specResolution.department || '',
            license_number: candidateLic,
            experience_years: dentistData.experience_years || dentistData.experienceYears || 5,
            qualifications: resolvedQual,
            availability_status: dentistData.availability_status || dentistData.availabilityStatus || 'Available',
            verification_status: dentistData.verification_status || 'VERIFIED',
            languages: finalLanguages,
            rating: dentistData.rating ?? 0,
            reviews_count: dentistData.reviews_count ?? 0,
            consultation_fee: (dentistData.consultation_fee || dentistData.consultationFee || '').toString(),
            bio: (dentistData.bio || '').toString(),
            consultation_mode: resolvedConsultationMode
        };
        if (resolvedConsultationMode !== 'ONLINE_ONLY') {
            const rawClinicName = (dentistData.clinic_name ?? dentistData.clinicName ?? '').toString().trim();
            const rawClinicAddress = (dentistData.clinic_address ?? dentistData.clinicAddress ?? '').toString().trim();
            if (rawClinicName) payload.clinic_name = rawClinicName;
            if (rawClinicAddress) payload.clinic_address = rawClinicAddress;
            if (coordCheck.ok && coordCheck.hasUpdate) {
                payload.latitude = coordCheck.latitude;
                payload.longitude = coordCheck.longitude;
            }
        } else {
            payload.clinic_name = null;
            payload.clinic_address = null;
            payload.latitude = null;
            payload.longitude = null;
        }
        if (dentistData.state !== undefined && dentistData.state !== null) payload.state = String(dentistData.state).trim();
        if (dentistData.city !== undefined && dentistData.city !== null) payload.city = String(dentistData.city).trim();
        if (dentistData.pincode !== undefined && dentistData.pincode !== null) payload.pincode = String(dentistData.pincode).trim();

        try {
            const { data, error } = await supabaseAdmin.from('dentists').insert(payload).select().single();
            if (error) throw error;
            return data;
        } catch (err) {
            const errMsg = (err && err.message ? err.message : '').toLowerCase();
            if (errMsg.includes('dentists_license_number_key')) {
                const retryPayload = {
                    ...payload,
                    license_number: `MED-LIC-${Date.now()}-${Math.floor(10000 + Math.random() * 90000)}`
                };
                const { data: retryData, error: retryErr } = await supabaseAdmin.from('dentists').insert(retryPayload).select().single();
                if (!retryErr && retryData) return retryData;
            }
            if (
                errMsg.includes('languages') ||
                errMsg.includes('clinic_name') ||
                errMsg.includes('clinic_address') ||
                errMsg.includes('consultation_mode') ||
                errMsg.includes('column')
            ) {
                const fallbackPayload = { ...payload };
                if (errMsg.includes('languages')) delete fallbackPayload.languages;
                delete fallbackPayload.clinic_name;
                delete fallbackPayload.clinic_address;
                delete fallbackPayload.consultation_mode;
                const { data: retryData, error: retryErr } = await supabaseAdmin.from('dentists').insert(fallbackPayload).select().single();
                if (!retryErr && retryData) return retryData;
            }
            console.error('❌ Supabase Dentist Insert Error:', err.message);
            throw err;
        }
    },

    async findByIdAndUpdate(id, updateData) {
        if (!id) return null;
        const str = String(id).trim();
        const payload = {};
        const rawSpecUpdate = (updateData.speciality || updateData.specialty || updateData.specialtyName || '').toString().trim();
        if (rawSpecUpdate || updateData.specialty_id || updateData.specialtyId) {
            const specRes = await resolveMedicalSpecialtyRecord(
                rawSpecUpdate,
                updateData.specialty_id || updateData.specialtyId || null
            );
            if (rawSpecUpdate) payload.speciality = specRes.specialty;
            if (specRes.specialty_id) payload.specialty_id = specRes.specialty_id;
            if (specRes.department) payload.department = specRes.department;
        }
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
        if (updateData.consultation_fee !== undefined || updateData.consultationFee !== undefined) {
            payload.consultation_fee = String(updateData.consultation_fee ?? updateData.consultationFee ?? '');
        }
        if (updateData.bio !== undefined) {
            payload.bio = String(updateData.bio ?? '');
        }
        const { normalizeConsultationMode, validateCoordinates } = require('../utils/doctorClinicLocationHelper');
        if (updateData.clinic_id !== undefined) payload.clinic_id = updateData.clinic_id;
        if (updateData.clinic_name !== undefined || updateData.clinicName !== undefined) {
            const val = updateData.clinic_name ?? updateData.clinicName;
            payload.clinic_name = val === null ? null : String(val).trim();
        }
        if (updateData.clinic_address !== undefined || updateData.clinicAddress !== undefined) {
            const val = updateData.clinic_address ?? updateData.clinicAddress;
            payload.clinic_address = val === null ? null : String(val).trim();
        }
        if (updateData.consultation_mode !== undefined || updateData.consultationMode !== undefined) {
            payload.consultation_mode = normalizeConsultationMode(
                updateData.consultation_mode ?? updateData.consultationMode,
                'BOTH'
            );
        }
        if (updateData.city !== undefined) payload.city = updateData.city;
        if (updateData.pincode !== undefined) payload.pincode = updateData.pincode;
        if (updateData.state !== undefined) payload.state = updateData.state;
        const coordCheck = validateCoordinates(
            updateData.latitude,
            updateData.longitude,
            updateData.clearLocation === true
        );
        if (coordCheck.ok && coordCheck.hasUpdate) {
            payload.latitude = coordCheck.latitude;
            payload.longitude = coordCheck.longitude;
        }
        if (updateData.languages !== undefined || updateData.languagesKnown !== undefined) {
            const normalizedLangs = normalizeLanguagesList(updateData.languages ?? updateData.languagesKnown);
            if (normalizedLangs.length > 0) {
                payload.languages = normalizedLangs;
            }
        }
        payload.updated_at = new Date().toISOString();

        try {
            const { data, error } = await supabaseAdmin
                .from('dentists')
                .update(payload)
                .or(`id.eq.${str},user_id.eq.${str}`)
                .select()
                .maybeSingle();
            if (!error && data) return data;
            if (error) {
                const errMsg = (error.message || '').toLowerCase();
                if (
                    errMsg.includes('clinic_name') ||
                    errMsg.includes('clinic_address') ||
                    errMsg.includes('consultation_mode') ||
                    errMsg.includes('column')
                ) {
                    const fallbackPayload = { ...payload };
                    delete fallbackPayload.clinic_name;
                    delete fallbackPayload.clinic_address;
                    delete fallbackPayload.consultation_mode;
                    const retry = await supabaseAdmin
                        .from('dentists')
                        .update(fallbackPayload)
                        .or(`id.eq.${str},user_id.eq.${str}`)
                        .select()
                        .maybeSingle();
                    if (!retry.error && retry.data) return retry.data;
                }
            }
        } catch (e) {
            console.warn('⚠️ Dentist.findByIdAndUpdate warning:', e.message);
        }
        return await this.findById(str);
    }
};

// 4. APPOINTMENT MODEL (Supabase PostgreSQL)
const isUUID = (str) => typeof str === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(str.trim());

async function resolveDentistIds(input) {
    if (!input) return { dentistTableId: null, userTableId: null, allIds: [], uuidIds: [] };
    if (typeof input === 'object' && input.$in && Array.isArray(input.$in)) {
        return resolveDentistIds(input.$in);
    }
    if (Array.isArray(input)) {
        let firstDentistId = null;
        let firstUserId = null;
        const allIdsSet = new Set();
        const uuidIdsSet = new Set();
        for (const item of input) {
            if (!item) continue;
            const sub = await resolveDentistIds(item);
            if (!firstDentistId && sub.dentistTableId) firstDentistId = sub.dentistTableId;
            if (!firstUserId && sub.userTableId) firstUserId = sub.userTableId;
            for (const id of sub.allIds) allIdsSet.add(id);
            for (const id of (sub.uuidIds || [])) uuidIdsSet.add(id);
        }
        return {
            dentistTableId: firstDentistId,
            userTableId: firstUserId,
            allIds: Array.from(allIdsSet),
            uuidIds: Array.from(uuidIdsSet)
        };
    }

    const str = String(input).trim();
    if (!str || str === '[object Object]') {
        return { dentistTableId: null, userTableId: null, allIds: [], uuidIds: [] };
    }
    let dentistTableId = null;
    let userTableId = null;

    if (isUUID(str)) {
        try {
            const { data: d } = await supabaseAdmin.from('dentists').select('id, user_id').or(`id.eq.${str},user_id.eq.${str}`).maybeSingle();
            if (d) {
                dentistTableId = d.id;
                userTableId = d.user_id;
            }
        } catch (_) { }
    }

    if (!dentistTableId) {
        try {
            const clean = str.replace(/^dr\.?\s+/i, '').trim();
            const { data: u } = await supabaseAdmin
                .from('users')
                .select('id')
                .or(`email.eq.${str},name.eq.${str},name.ilike.${clean}`)
                .limit(1)
                .maybeSingle();
            if (u) {
                userTableId = u.id;
                const { data: d } = await supabaseAdmin.from('dentists').select('id, user_id').eq('user_id', u.id).maybeSingle();
                if (d) {
                    dentistTableId = d.id;
                }
            }
        } catch (_) { }
    }

    const allIds = [dentistTableId, userTableId, str].filter(Boolean).filter((v, i, a) => a.indexOf(v) === i);
    const uuidIds = allIds.filter(id => isUUID(id));
    return { dentistTableId, userTableId, allIds, uuidIds };
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

async function resolveClinicIds(input) {
    if (!input) {
        return { clinicRecord: null, clinicId: null, clinicUserId: null, clinicName: '', allIds: [] };
    }
    const str = String(input).trim();
    if (!str) {
        return { clinicRecord: null, clinicId: null, clinicUserId: null, clinicName: '', allIds: [] };
    }

    let clinic = null;
    try {
        if (isUUID(str)) {
            const { data } = await supabaseAdmin
                .from('clinics')
                .select('*')
                .or(`id.eq.${str},user_id.eq.${str}`)
                .limit(1)
                .maybeSingle();
            if (data) clinic = data;
        }
        if (!clinic) {
            const { data } = await supabaseAdmin
                .from('clinics')
                .select('*')
                .ilike('clinic_name', str)
                .limit(1)
                .maybeSingle();
            if (data) clinic = data;
        }
    } catch (e) {
        console.error('Error resolving clinic IDs:', e.message);
    }

    const ids = new Set([str]);
    if (clinic?.id) ids.add(String(clinic.id));
    if (clinic?.user_id) ids.add(String(clinic.user_id));
    if (clinic?.clinic_name) ids.add(String(clinic.clinic_name).trim());

    return {
        clinicRecord: clinic,
        clinicId: clinic?.id || (isUUID(str) ? str : null),
        clinicUserId: clinic?.user_id || null,
        clinicName: (clinic?.clinic_name || '').toString().trim(),
        allIds: Array.from(ids),
    };
}

async function resolveClinicUuid(input) {
    const resolved = await resolveClinicIds(input);
    return resolved.clinicId;
}

// 4. APPOINTMENT MODEL (Supabase PostgreSQL)
const Appointment = {
    async create(appData) {
        const patientId = await resolveUserUuid(appData.patient_id || appData.patientId);
        const dentistId = await resolveDentistUuid(appData.dentist_id || appData.dentistId);
        const clinicId = await resolveClinicUuid(appData.clinic_id || appData.clinicId);

        const rawDate = appData.date || appData.appointment_date || appData.appointmentDate || new Date().toISOString();
        const apptDateYmd = normalizeDateToTimezoneYmd(appData.appointment_date || appData.appointmentDate || rawDate) || new Date().toISOString().split('T')[0];
        const apptDateTs = `${apptDateYmd}T00:00:00.000Z`;
        const timeSlot = String(appData.time_slot || appData.timeSlot || '10:00 AM').trim();
        const treatmentName = appData.treatment || appData.notes || 'Medical Consultation';
        const statusVal = appData.status || 'PENDING';
        const mode = normalizeConsultationType(appData.consultation_type || appData.consultationType || appData.consultationMode, treatmentName);
        const defaultTiming = getConsultationTimingForType(mode);
        const startMin = appData.scheduled_start_min !== undefined && appData.scheduled_start_min !== null
            ? Number(appData.scheduled_start_min)
            : parseClockSlotMinutes(timeSlot);
        const durMin = Number(appData.duration_minutes || appData.durationMinutes) > 0
            ? Number(appData.duration_minutes || appData.durationMinutes)
            : defaultTiming.durationMinutes;
        const bufMin = appData.buffer_minutes !== undefined && Number(appData.buffer_minutes) >= 0
            ? Number(appData.buffer_minutes)
            : (appData.bufferMinutes !== undefined && Number(appData.bufferMinutes) >= 0 ? Number(appData.bufferMinutes) : defaultTiming.bufferMinutes);

        const basePayload = {
            patient_id: patientId,
            dentist_id: dentistId,
            clinic_id: clinicId,
            date: apptDateTs,
            time_slot: timeSlot,
            treatment: treatmentName,
            status: statusVal,
            qr_code_string: appData.qr_code_string || `DENTAGURU-${patientId || 'PATIENT'}-${Date.now()}`
        };

        const richPayload = {
            ...basePayload,
            appointment_date: apptDateYmd,
            consultation_type: mode,
            ...(appData.capacity_lane ? { capacity_lane: appData.capacity_lane } : {}),
            duration_minutes: durMin,
            buffer_minutes: bufMin,
            delay_minutes: Number(appData.delay_minutes || 0) || 0,
            ...(startMin !== null && Number.isFinite(startMin) ? {
                scheduled_start_min: startMin,
                scheduled_end_min: startMin + durMin,
                effective_end_min: startMin + durMin + bufMin,
            } : {}),
            ...(appData.actual_start_at ? { actual_start_at: appData.actual_start_at } : {}),
            ...(appData.actual_end_at ? { actual_end_at: appData.actual_end_at } : {}),
            ...(appData.finished_early !== undefined ? { finished_early: Boolean(appData.finished_early) } : {}),
            ...(appData.released_slot_id ? { released_slot_id: appData.released_slot_id } : {}),
        };

        try {
            const { data, error } = await supabaseAdmin.from('appointments').insert(richPayload).select().single();
            if (!error && data) return data;
            if (error) {
                const msg = String(error.message || '').toLowerCase();
                // Re-throw real constraint/exclusion violations immediately (never silently bypass GiST!)
                if (error.code === '23P01' || error.code === '23514' || msg.includes('exclusion') || msg.includes('chk_appointments')) {
                    throw error;
                }
                // Fallback to pre-Migration-04 base columns when new columns do not exist yet
                const { data: dBase, error: eBase } = await supabaseAdmin.from('appointments').insert(basePayload).select().single();
                if (!eBase && dBase) return dBase;
                const legacyPayload = {
                    patient_id: patientId,
                    dentist_id: dentistId,
                    clinic_id: clinicId,
                    appointment_date: apptDateTs,
                    status: statusVal,
                    type: mode,
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
        let req = supabaseAdmin.from('appointments').select('*, patient:users!patient_id(*), dentist:dentists!dentist_id(id, user_id, clinic_id, speciality, qualifications, experience_years, availability_status, users(id, name, phone, email, biometric_token), clinics(id, clinic_name, location)), clinic:clinics!clinic_id(id, clinic_name, location)');
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
            const { dentistTableId, userTableId, uuidIds } = await resolveDentistIds(dId);
            if (Array.isArray(uuidIds) && uuidIds.length > 1) {
                req = req.in('dentist_id', uuidIds);
            } else if (Array.isArray(uuidIds) && uuidIds.length === 1) {
                req = req.eq('dentist_id', uuidIds[0]);
            } else if (dentistTableId && userTableId && dentistTableId !== userTableId) {
                req = req.or(`dentist_id.eq.${dentistTableId},dentist_id.eq.${userTableId}`);
            } else if (dentistTableId) {
                req = req.eq('dentist_id', dentistTableId);
            } else {
                return [];
            }
        }
        const cId = query.clinic_id || query.clinicId;
        if (cId) {
            const { clinicId: resolvedC, clinicRecord } = await resolveClinicIds(cId);
            if (!resolvedC) {
                return [];
            }
            const clinicDocIds = new Set();
            try {
                const { data: docsByClinic } = await supabaseAdmin
                    .from('dentists')
                    .select('id')
                    .eq('clinic_id', resolvedC);
                for (const d of (docsByClinic || [])) {
                    if (d?.id) clinicDocIds.add(String(d.id));
                }
            } catch (_) { }
            // Also accept explicit pre-resolved dentist IDs passed by caller (e.g. name-matched legacy rows)
            if (Array.isArray(query.clinic_dentist_ids)) {
                for (const id of query.clinic_dentist_ids) {
                    if (id && isUUID(String(id))) clinicDocIds.add(String(id));
                }
            }
            const docIdList = Array.from(clinicDocIds);
            if (docIdList.length > 0 && isUUID(resolvedC)) {
                req = req.or(`clinic_id.eq.${resolvedC},dentist_id.in.(${docIdList.join(',')})`);
            } else if (isUUID(resolvedC)) {
                req = req.eq('clinic_id', resolvedC);
            } else if (clinicRecord?.id) {
                req = req.eq('clinic_id', clinicRecord.id);
            } else {
                return [];
            }
        }
        if (query.status) {
            req = req.eq('status', query.status);
        }
        const { data, error } = await req.order('created_at', { ascending: false });
        if (error) {
            console.warn('⚠️ Appointment query error, falling back to filtered simple select:', error.message);
            // Strict isolation: never return unfiltered appointments when a doctor, patient, or clinic filter was requested
            if (pId || dId || cId) {
                try {
                    let fallbackReq = supabaseAdmin.from('appointments').select('*');
                    if (pId) {
                        const resolvedP = await resolveUserUuid(pId);
                        if (Array.isArray(resolvedP) && resolvedP.length > 0) {
                            fallbackReq = fallbackReq.in('patient_id', resolvedP);
                        } else if (typeof resolvedP === 'string' && resolvedP.length > 0) {
                            fallbackReq = fallbackReq.eq('patient_id', resolvedP);
                        } else {
                            return [];
                        }
                    }
                    if (dId) {
                        const { dentistTableId, userTableId, uuidIds } = await resolveDentistIds(dId);
                        if (Array.isArray(uuidIds) && uuidIds.length > 1) {
                            fallbackReq = fallbackReq.in('dentist_id', uuidIds);
                        } else if (Array.isArray(uuidIds) && uuidIds.length === 1) {
                            fallbackReq = fallbackReq.eq('dentist_id', uuidIds[0]);
                        } else if (dentistTableId && userTableId && dentistTableId !== userTableId) {
                            fallbackReq = fallbackReq.or(`dentist_id.eq.${dentistTableId},dentist_id.eq.${userTableId}`);
                        } else if (dentistTableId) {
                            fallbackReq = fallbackReq.eq('dentist_id', dentistTableId);
                        } else {
                            return [];
                        }
                    }
                    if (cId) {
                        const { clinicId: resolvedC } = await resolveClinicIds(cId);
                        if (!resolvedC) return [];
                        fallbackReq = fallbackReq.eq('clinic_id', resolvedC);
                    }
                    if (query.status) {
                        fallbackReq = fallbackReq.eq('status', query.status);
                    }
                    const simple = await fallbackReq.order('created_at', { ascending: false });
                    return simple.error ? [] : (simple.data || []);
                } catch (_) {
                    return [];
                }
            }
            const simple = await supabaseAdmin.from('appointments').select('*').order('created_at', { ascending: false });
            return simple.error ? [] : (simple.data || []);
        }
        return data || [];
    },

    async findById(id) {
        const { data, error } = await supabaseAdmin.from('appointments').select('*, patient:users!patient_id(*), dentist:dentists!dentist_id(id, user_id, clinic_id, speciality, qualifications, experience_years, availability_status, users(id, name, phone, email, biometric_token), clinics(id, clinic_name, location)), clinic:clinics!clinic_id(id, clinic_name, location)').eq('id', id).single();
        if (error) return null;
        return data;
    },

    async findByIdAndUpdate(id, updateData) {
        const { data, error } = await supabaseAdmin.from('appointments').update(updateData).eq('id', id).select().single();
        if (!error && data) return data;
        if (error) {
            const msg = String(error.message || '').toLowerCase();
            if (error.code === '23P01' || error.code === '23514' || msg.includes('exclusion') || msg.includes('chk_appointments')) {
                throw error;
            }
            // Pre-Migration-04 graceful fallback: strip Phase 2 columns if DB does not have them yet
            const PHASE2_COLS = [
                'appointment_date', 'consultation_type', 'capacity_lane', 'duration_minutes',
                'buffer_minutes', 'delay_minutes', 'scheduled_start_min', 'scheduled_end_min',
                'effective_end_min', 'scheduled_start_at', 'scheduled_end_at', 'actual_start_at',
                'actual_end_at', 'finished_early', 'released_slot_id'
            ];
            const safeUpdate = { ...updateData };
            let stripped = false;
            for (const col of PHASE2_COLS) {
                if (col in safeUpdate) {
                    delete safeUpdate[col];
                    stripped = true;
                }
            }
            if (stripped && Object.keys(safeUpdate).length > 0) {
                const { data: d2, error: e2 } = await supabaseAdmin.from('appointments').update(safeUpdate).eq('id', id).select().single();
                if (e2) throw e2;
                return d2;
            }
            throw error;
        }
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

        const rawAppt = recordData.appointment_id || recordData.appointmentId;
        const apptUuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
        const validApptId = (rawAppt && apptUuidRegex.test(String(rawAppt).trim())) ? String(rawAppt).trim() : null;

        const payload = {
            patient_id: patientId,
            dentist_id: dentistId,
            ...(validApptId ? { appointment_id: validApptId } : {}),
            diagnosis: recordData.diagnosis || recordData.title || 'Medical Health Record',
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
        const cleanMessage = (messageData.message || '').toString().trim();
        if (!cleanMessage) {
            throw new Error('Message text cannot be empty.');
        }

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

        // Deduplicate rapid double-submits (same room, sender, and message within 3 seconds)
        try {
            const sinceIso = new Date(Date.now() - 3000).toISOString();
            let dupReq = supabaseAdmin
                .from('chat_messages')
                .select('*, sender:users!sender_id(id, name, email, role), receiver:users!receiver_id(id, name, email, role)')
                .eq('room_id', normalizedRoom)
                .eq('message', cleanMessage)
                .gte('created_at', sinceIso)
                .limit(1);
            if (senderId) {
                dupReq = dupReq.eq('sender_id', senderId);
            }
            const { data: dupRows } = await dupReq;
            if (dupRows && dupRows.length > 0) {
                return dupRows[0];
            }
        } catch (_) { }

        const payload = {
            room_id: normalizedRoom,
            sender_id: senderId || null,
            receiver_id: receiverId || null,
            message: cleanMessage,
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
        let isMainAdmin = true;
        let callerRole = '';
        let callerUser = options.user || null;
        if (callerUser) {
            callerRole = (callerUser.role || '').toString().trim().toLowerCase();
            isMainAdmin = callerRole === 'admin' || callerRole === 'primaryadmin' || callerRole === 'primary_admin' || callerRole === 'superadmin' || callerRole === 'super_admin' || callerUser.email === 'admin@dentaguru.com';
            const isSubAdmin = callerRole === 'sub-admin' || callerRole === 'subadmin' || callerRole === 'sub_admin';

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
        let rows = data || [];
        if (error) {
            // Fallback to simple sender select if receiver foreign key is missing
            const fallback = await supabaseAdmin.from('chat_messages').select('*, sender:users!sender_id(id, name, email, role)').order('created_at', { ascending: true });
            rows = fallback.data || [];
            if (rawRoom) {
                const norm = normalizeChatRoomId(rawRoom);
                rows = rows.filter(m => normalizeChatRoomId(m.room_id) === norm);
            }
        }

        // If caller is non-admin (Patient / Doctor) and requested unscoped listing, restrict to authorized conversations
        if (callerUser && !isMainAdmin && !rawRoom) {
            const allowedConvs = await this.getConversations(callerUser);
            const allowedRoomSet = new Set(allowedConvs.map(c => normalizeChatRoomId(c.roomId)));
            rows = rows.filter(m =>
                allowedRoomSet.has(normalizeChatRoomId(m.room_id)) ||
                m.sender_id === callerUser.id ||
                m.receiver_id === callerUser.id
            );
        }

        return rows;
    },

    async markAsRead({ roomId, userId }) {
        if (!roomId) return 0;
        const normalized = normalizeChatRoomId(roomId);
        const hyphenated = normalized.replace(/_/g, '-');
        try {
            let req = supabaseAdmin
                .from('chat_messages')
                .update({ read: true })
                .eq('read', false)
                .or(`room_id.eq.${normalized},room_id.eq.${hyphenated},room_id.eq.${roomId}`);
            if (userId) {
                req = req.or(`sender_id.is.null,sender_id.neq.${userId}`);
            }
            const { data, error } = await req.select('id');
            if (error) throw error;
            return (data || []).length;
        } catch (err) {
            console.warn('⚠️ markAsRead warning:', err.message);
            return 0;
        }
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
                    lastSenderRole: msg.sender?.role || (msg.type === 'doctor' ? 'DOCTOR' : 'Patient'),
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
            const msgSenderRoleLower = String(msg.sender?.role || '').trim().toLowerCase();
            if (!thread.doctorName && (msg.type === 'doctor' || msgSenderRoleLower === 'dentist' || msgSenderRoleLower === 'doctor')) {
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
                    const prDentist = /** @type {any} */ (Array.isArray(pr.suggested_dentist) ? pr.suggested_dentist[0] : pr.suggested_dentist);
                    const prUser = Array.isArray(prDentist?.users) ? prDentist.users[0] : prDentist?.users;
                    const dName = prUser?.name;
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
                    const apDentist = /** @type {any} */ (Array.isArray(ap.dentist) ? ap.dentist[0] : ap.dentist);
                    const apDocUser = Array.isArray(apDentist?.users) ? apDentist.users[0] : apDentist?.users;
                    const apPatient = /** @type {any} */ (Array.isArray(ap.patient) ? ap.patient[0] : ap.patient);
                    const dName = apDocUser?.name;
                    if (dName) {
                        const formatted = dName.toLowerCase().startsWith('dr') ? dName : `Dr. ${dName}`;
                        if (ap.patient_id) doctorLookup.set(String(ap.patient_id).toLowerCase(), formatted);
                    }
                    if (apPatient?.name && ap.patient_id) {
                        patientLookup.set(String(ap.patient_id).toLowerCase(), apPatient.name);
                    }
                }
            }
        } catch (_) { }

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
                resolvedDoc = 'Attending Doctor';
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
            } else if (role === 'clinic' || role === 'clinic_admin') {
                // Clinic can view threads belonging to doctors affiliated with this clinic
                if (!this._clinicDocNamesCache || this._clinicDocCacheFor !== user.id) {
                    this._clinicDocCacheFor = user.id;
                    this._clinicDocNamesCache = new Set();
                    this._clinicDocIdsCache = new Set();
                    try {
                        const cResolved = await resolveClinicIds(user.id);
                        const cId = cResolved.clinicId;
                        if (cId) {
                            const { data: clinicDocs } = await supabaseAdmin
                                .from('dentists')
                                .select('id, user_id, users(name)')
                                .eq('clinic_id', cId);
                            for (const d of (clinicDocs || [])) {
                                if (d.id) this._clinicDocIdsCache.add(d.id);
                                if (d.user_id) this._clinicDocIdsCache.add(d.user_id);
                                const du = Array.isArray(d.users) ? d.users[0] : d.users;
                                const dName = (du?.name || '').replace(/^Dr\.\s*/i, '').trim().toLowerCase();
                                if (dName) this._clinicDocNamesCache.add(dName);
                            }
                        }
                    } catch (_) { }
                }
                const threadHasClinicDoc = Array.from(this._clinicDocIdsCache || []).some(cid =>
                    (thread.senderIds && thread.senderIds.has(cid)) ||
                    (thread.receiverIds && thread.receiverIds.has(cid))
                );
                const docNameLower = resolvedDoc.replace(/^Dr\.\s*/i, '').trim().toLowerCase();
                const roomLower = roomId.toLowerCase();
                const nameMatchesClinicDoc = Array.from(this._clinicDocNamesCache || []).some(dn =>
                    dn.length > 0 && (docNameLower.includes(dn) || roomLower.includes(dn))
                );
                if (threadHasClinicDoc || nameMatchesClinicDoc) {
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
            problem_category: reqData.problem_category || reqData.problemCategory || 'General Medical Consultation',
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
                problem_category: reqData.problem_category || reqData.problemCategory || 'General Medical Consultation',
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
                    } catch (_) { }
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
                } catch (_) { }

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
            recipient_id: String(notifData.recipient_id || notifData.recipientId || 'ALL').trim(),
            title: (notifData.title || '').toString().trim(),
            message: (notifData.message || '').toString().trim(),
            type: notifData.type || notifData.notification_type || notifData.notificationType || 'general',
            read: notifData.read ?? notifData.read_status ?? false
        };
        if (notifData.referral_id || notifData.referralId) {
            payload.referral_id = notifData.referral_id || notifData.referralId;
        }
        if (notifData.data && typeof notifData.data === 'object') {
            payload.data = notifData.data;
        }

        try {
            // Avoid duplicate notifications created within a 15-second window for the same recipient + title + message
            const windowIso = new Date(Date.now() - 15000).toISOString();
            const { data: existing } = await supabaseAdmin
                .from('notifications')
                .select('*')
                .eq('recipient_role', payload.recipient_role)
                .eq('recipient_id', payload.recipient_id)
                .eq('title', payload.title)
                .eq('message', payload.message)
                .gte('created_at', windowIso)
                .order('created_at', { ascending: false })
                .limit(1);
            if (Array.isArray(existing) && existing.length > 0) {
                return existing[0];
            }
        } catch (_) { }

        try {
            const { data, error } = await supabaseAdmin.from('notifications').insert(payload).select().single();
            if (!error && data) return data;
            if (error) {
                // Fallback without referral_id / data columns if not yet migrated in Supabase
                const safePayload = /** @type {Record<string, any>} */ ({ ...payload });
                delete safePayload.referral_id;
                delete safePayload.data;
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

    async findForUser(options = {}) {
        const { role, userId } = /** @type {{ role?: string, userId?: string }} */ (options || {});
        try {
            const normRole = (role || '').toString().trim().toLowerCase();
            const rawUserId = (userId || '').toString().trim();

            const { data: allRows, error } = await supabaseAdmin
                .from('notifications')
                .select('*')
                .order('created_at', { ascending: false })
                .limit(300);
            if (error || !Array.isArray(allRows)) return [];

            let candidateUserIds = new Set();
            if (rawUserId) candidateUserIds.add(rawUserId);

            const isAdminRole = normRole === 'admin' || normRole === 'sub-admin' || normRole === 'subadmin' || normRole === 'primaryadmin' || normRole === 'superadmin';
            const isDoctorRole = normRole === 'dentist' || normRole === 'doctor';
            const isClinicRole = normRole === 'clinic' || normRole === 'clinic_admin';
            const isPatientRole = normRole === 'patient';

            if (isDoctorRole && rawUserId) {
                const { dentistTableId, userTableId, allIds } = await resolveDentistIds(rawUserId);
                if (dentistTableId) candidateUserIds.add(String(dentistTableId));
                if (userTableId) candidateUserIds.add(String(userTableId));
                for (const id of (allIds || [])) candidateUserIds.add(String(id));
            } else if (isClinicRole && rawUserId) {
                const { clinicId, clinicUserId, allIds } = await resolveClinicIds(rawUserId);
                if (clinicId) candidateUserIds.add(String(clinicId));
                if (clinicUserId) candidateUserIds.add(String(clinicUserId));
                for (const id of (allIds || [])) candidateUserIds.add(String(id));
            } else if (isPatientRole && rawUserId) {
                const resolvedP = await resolveUserUuid(rawUserId);
                if (resolvedP) candidateUserIds.add(String(resolvedP));
            }

            const filtered = allRows.filter(n => {
                const nRole = (n.recipient_role || '').toString().trim().toLowerCase();
                const nRecId = (n.recipient_id || '').toString().trim();
                const nRecUpper = nRecId.toUpperCase();

                if (isAdminRole) {
                    if (nRole === 'admin' || nRole === 'sub-admin' || nRole === 'subadmin') {
                        if (!rawUserId || nRecUpper === 'ALL' || nRecUpper === 'ALL_ADMINS' || candidateUserIds.has(nRecId)) {
                            return true;
                        }
                    }
                    if (nRecUpper === 'ALL_ADMINS') return true;
                    if (rawUserId && candidateUserIds.has(nRecId)) return true;
                    return false;
                }

                if (isDoctorRole) {
                    const roleMatches = nRole === 'dentist' || nRole === 'doctor' || nRole === 'all';
                    if (!rawUserId) return false;
                    if (roleMatches && candidateUserIds.has(nRecId)) return true;
                    if (roleMatches && nRecUpper === 'ALL') return true;
                    return false;
                }

                if (isClinicRole) {
                    const roleMatches = nRole === 'clinic' || nRole === 'clinic_admin' || nRole === 'all';
                    if (rawUserId && roleMatches && candidateUserIds.has(nRecId)) return true;
                    if (rawUserId && nRole === 'clinic' && candidateUserIds.has(nRecId)) return true;
                    if (roleMatches && nRecUpper === 'ALL_CLINICS') return true;
                    return false;
                }

                if (isPatientRole) {
                    const roleMatches = nRole === 'patient' || nRole === 'all';
                    if (rawUserId && candidateUserIds.has(nRecId)) return true;
                    if (roleMatches && nRecUpper === 'ALL') return true;
                    return false;
                }

                // Fallback when no role is specified
                if (rawUserId && candidateUserIds.has(nRecId)) return true;
                return false;
            });

            // Deduplicate identical notifications (same recipient_id + title + message within same minute)
            const seenKeys = new Set();
            const deduped = [];
            for (const n of filtered) {
                const minuteBucket = (n.created_at || '').toString().slice(0, 16);
                const key = `${n.recipient_role}|${n.recipient_id}|${n.title}|${n.message}|${minuteBucket}`;
                if (seenKeys.has(key)) continue;
                seenKeys.add(key);
                deduped.push(n);
            }
            return deduped;
        } catch (e) {
            console.warn('⚠️ Notification.findForUser warning:', e.message);
            return [];
        }
    },

    async markAsRead(id) {
        try {
            const { data, error } = await supabaseAdmin.from('notifications').update({ read: true }).eq('id', id).select().single();
            if (error) throw error;
            return data;
        } catch (e) {
            return null;
        }
    },

    async markAllAsReadForUser(options = {}) {
        const { role, userId } = /** @type {{ role?: string, userId?: string }} */ (options || {});
        try {
            const matching = await this.findForUser({ role, userId });
            const unreadIds = matching.filter(n => !n.read && n.id).map(n => n.id);
            if (unreadIds.length === 0) return 0;
            const { error } = await supabaseAdmin
                .from('notifications')
                .update({ read: true })
                .in('id', unreadIds);
            if (error) throw error;
            return unreadIds.length;
        } catch (e) {
            console.warn('⚠️ Notification.markAllAsReadForUser warning:', e.message);
            return 0;
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
        } catch (_) { }

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
        const rawReferrerId = referralData.referrer_patient_id || referralData.referrerPatientId || referralData.referrer_id || referralData.referrerId;
        const referrerPatientId = await resolveUserUuid(rawReferrerId) || rawReferrerId;
        const rawReferredPatientId = referralData.referred_patient_id || referralData.referredPatientId || referralData.referred_user_id || referralData.referredUserId || null;
        const referredPatientId = rawReferredPatientId ? (await resolveUserUuid(rawReferredPatientId) || rawReferredPatientId) : null;

        const rawDoctorId = referralData.doctor_id || referralData.doctorId || referralData.assigned_doctor_id || referralData.assignedDoctorId || null;
        const rawClinicId = referralData.clinic_id || referralData.clinicId || null;
        let doctorId = null;
        let resolvedDoctorClinicId = null;
        if (rawDoctorId && isUUID(rawDoctorId)) {
            try {
                const { data: dRow } = await supabaseAdmin
                    .from('dentists')
                    .select('id, clinic_id')
                    .or(`id.eq.${rawDoctorId},user_id.eq.${rawDoctorId}`)
                    .limit(1)
                    .maybeSingle();
                if (dRow?.id) {
                    doctorId = dRow.id;
                    resolvedDoctorClinicId = dRow.clinic_id || null;
                }
            } catch (_) { }
        }
        const clinicId = (rawClinicId && isUUID(rawClinicId))
            ? rawClinicId
            : (resolvedDoctorClinicId || await resolveClinicUuid(rawClinicId || referralData.doctor_clinic_name || referralData.doctorClinicName));

        const payload = {
            id,
            referrer_patient_id: referrerPatientId || null,
            referrer_id: referrerPatientId || null,
            referred_patient_id: referredPatientId,
            referred_user_id: referredPatientId,
            referred_patient_name: referralData.referred_patient_name || referralData.referredPatientName || '',
            referred_patient_mobile: referralData.referred_patient_mobile || referralData.referredPatientMobile || '',
            referred_patient_age: referralData.referred_patient_age || referralData.referredPatientAge || '',
            referred_patient_gender: referralData.referred_patient_gender || referralData.referredPatientGender || '',
            referred_patient_city: referralData.referred_patient_city || referralData.referredPatientCity || '',
            referred_patient_pincode: referralData.referred_patient_pincode || referralData.referredPatientPincode || '',
            referred_patient_location: referralData.referred_patient_location || referralData.referredPatientLocation || '',
            required_specialist: referralData.required_specialist || referralData.requiredSpecialist || '',
            specialty: referralData.specialty || referralData.required_specialist || referralData.requiredSpecialist || '',
            clinical_complaint: referralData.clinical_complaint || referralData.clinicalComplaint || '',
            doctor_id: doctorId,
            assigned_doctor_id: doctorId,
            clinic_id: clinicId || null,
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
                const enrichedData = { ...data, clinic_id: data.clinic_id || clinicId || null };
                const existingIdx = _inMemoryReferrals.findIndex(r => r.id === enrichedData.id);
                if (existingIdx !== -1) _inMemoryReferrals[existingIdx] = enrichedData;
                else _inMemoryReferrals.unshift(enrichedData);
                return enrichedData;
            }
            if (error) {
                console.warn('⚠️ Supabase Referrals primary insert notice:', error.message);
                const safePayload = /** @type {Record<string, any>} */ ({ ...payload });
                delete safePayload.assigned_doctor_id;
                delete safePayload.clinic_id;
                const { data: d2, error: e2 } = await supabaseAdmin.from('referrals').insert(safePayload).select().single();
                if (!e2 && d2) {
                    const merged = { ...payload, ...d2, clinic_id: clinicId || null };
                    _inMemoryReferrals.unshift(merged);
                    return merged;
                }
                if (e2) {
                    console.warn('⚠️ Supabase Referrals secondary insert notice:', e2.message);
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
        const refIdRaw = query.referrer_patient_id || query.referrerPatientId || query.referrer_id || query.referrerId;
        const docIdRaw = query.doctor_id || query.doctorId || query.assigned_doctor_id || query.assignedDoctorId;
        const patIdRaw = query.referred_patient_id || query.referredPatientId || query.referred_user_id || query.referredUserId;
        const mobileRaw = query.referred_patient_mobile || query.referredPatientMobile;

        const applyFilters = (req) => {
            if (refIdRaw) {
                req = req.or(`referrer_patient_id.eq.${refIdRaw},referrer_id.eq.${refIdRaw}`);
            }
            if (docIdRaw) {
                const docIdList = Array.isArray(docIdRaw?.$in)
                    ? docIdRaw.$in.map(v => String(v || '').trim()).filter(Boolean)
                    : [String(docIdRaw).trim()].filter(Boolean);
                if (docIdList.length > 0) {
                    const docOr = docIdList
                        .map(dId => `doctor_id.eq.${dId},assigned_doctor_id.eq.${dId}`)
                        .join(',');
                    req = req.or(docOr);
                }
            }
            if (patIdRaw) {
                req = req.or(`referred_patient_id.eq.${patIdRaw},referred_user_id.eq.${patIdRaw}`);
            }
            if (mobileRaw) {
                req = req.eq('referred_patient_mobile', mobileRaw);
            }
            if (query.status) req = req.eq('status', query.status);
            return req;
        };

        try {
            const req = applyFilters(
                supabaseAdmin
                    .from('referrals')
                    .select('*, referrer:users!referrer_patient_id(id, name, email, phone), doctor:dentists!doctor_id(id, user_id, speciality, users(name, email, phone), clinics(clinic_name, location))')
            );
            const { data, error } = await req.order('created_at', { ascending: false });
            if (!error && Array.isArray(data)) {
                return data;
            }
            if (error) {
                console.warn('⚠️ Referral.find join notice, retrying simple select:', error.message);
                const simpleReq = applyFilters(supabaseAdmin.from('referrals').select('*'));
                const simple = await simpleReq.order('created_at', { ascending: false });
                if (!simple.error && Array.isArray(simple.data)) {
                    return simple.data;
                }
            }
        } catch (_) { }

        let filtered = [..._inMemoryReferrals];
        if (refIdRaw) {
            filtered = filtered.filter(r => (r.referrer_patient_id === refIdRaw || r.referrer_id === refIdRaw));
        }
        if (docIdRaw) {
            const docIdList = Array.isArray(docIdRaw?.$in)
                ? docIdRaw.$in.map(v => String(v || '').trim()).filter(Boolean)
                : [String(docIdRaw).trim()].filter(Boolean);
            filtered = filtered.filter(r =>
                docIdList.includes(String(r.doctor_id || '').trim()) ||
                docIdList.includes(String(r.assigned_doctor_id || '').trim())
            );
        }
        if (patIdRaw) {
            filtered = filtered.filter(r => (r.referred_patient_id === patIdRaw || r.referred_user_id === patIdRaw));
        }
        if (mobileRaw) {
            filtered = filtered.filter(r => (r.referred_patient_mobile === mobileRaw));
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
        } catch (_) { }

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
        if (!referrerPatientId || !referredPatientMobile) return null;
        try {
            let q = supabaseAdmin
                .from('referrals')
                .select('*')
                .eq('referrer_patient_id', referrerPatientId)
                .eq('referred_patient_mobile', referredPatientMobile)
                .eq('status', 'Pending');
            if (doctorId) {
                q = q.eq('doctor_id', doctorId);
            }
            const { data } = await q.limit(1);
            if (data && data.length > 0) return data[0];
        } catch (_) { }

        return _inMemoryReferrals.find(r =>
            (r.referrer_patient_id === referrerPatientId || r.referrer_id === referrerPatientId) &&
            r.referred_patient_mobile === referredPatientMobile &&
            (!doctorId || r.doctor_id === doctorId || r.assigned_doctor_id === doctorId) &&
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
        } catch (_) { }

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
        } catch (_) { }

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

// 12. DOCTOR AVAILABILITY MODEL (Doctor Slots, Working Hours, Blocked Dates, Weekly Schedule)
const _inMemoryAvailability = [];
const _inMemorySchedule = new Map();

const FULL_WEEKDAYS = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const SHORT_TO_FULL_WEEKDAY = {
    mon: 'Monday', monday: 'Monday',
    tue: 'Tuesday', tues: 'Tuesday', tuesday: 'Tuesday',
    wed: 'Wednesday', wednesday: 'Wednesday',
    thu: 'Thursday', thur: 'Thursday', thurs: 'Thursday', thursday: 'Thursday',
    fri: 'Friday', friday: 'Friday',
    sat: 'Saturday', saturday: 'Saturday',
    sun: 'Sunday', sunday: 'Sunday',
};

function extractDateYmd(raw) {
    if (!raw) return '';
    if (raw instanceof Date) {
        const y = raw.getFullYear();
        const m = String(raw.getMonth() + 1).padStart(2, '0');
        const d = String(raw.getDate()).padStart(2, '0');
        return `${y}-${m}-${d}`;
    }
    const str = String(raw).trim();
    const match = str.match(/^(\d{4}-\d{2}-\d{2})/);
    if (match) return match[1];
    const parsed = new Date(str);
    if (!Number.isNaN(parsed.getTime())) {
        return parsed.toISOString().split('T')[0];
    }
    return '';
}

function getWeekdayNameFromYmd(ymd) {
    const clean = extractDateYmd(ymd);
    if (!clean) return '';
    const [y, m, d] = clean.split('-').map(n => parseInt(n, 10));
    const dt = new Date(Date.UTC(y, m - 1, d, 12, 0, 0));
    const idx = dt.getUTCDay(); // 0=Sun..6=Sat
    return ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'][idx] || '';
}

function normalizeWorkingDays(rawDays) {
    let arr = [];
    if (Array.isArray(rawDays)) {
        arr = rawDays;
    } else if (typeof rawDays === 'string') {
        const trimmed = rawDays.trim();
        if (trimmed.startsWith('[')) {
            try {
                const parsed = JSON.parse(trimmed);
                if (Array.isArray(parsed)) arr = parsed;
            } catch (_) {
                arr = trimmed.split(',');
            }
        } else if (trimmed) {
            arr = trimmed.split(',');
        }
    }
    const out = [];
    for (const item of arr) {
        const key = String(item || '').trim().toLowerCase();
        const mapped = SHORT_TO_FULL_WEEKDAY[key];
        if (mapped && !out.includes(mapped)) out.push(mapped);
    }
    // Order Mon..Sun cleanly
    return FULL_WEEKDAYS.filter(d => out.includes(d));
}

const DEFAULT_DOCTOR_SCHEDULE = {
    workingDays: ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'],
    startTime: '09:00 AM',
    endTime: '05:00 PM',
    slotDurationMinutes: 30,
    hasBreak: true,
    breakStartTime: '01:00 PM',
    breakEndTime: '02:00 PM',
    isConfigured: false,
};

function sanitizeSchedulePayload(raw = {}, fallback = DEFAULT_SMART_SCHEDULE) {
    return sanitizeSmartSchedule(raw, fallback);
}

const _inMemoryBlockedSlots = new Map(); // key: `${dentistId}_${dateYmd}` -> Array<{startTime, endTime, reason, ...}>
const _inMemorySlotLocks = new Map(); // key: lockId -> lock row
const _inMemoryReleasedSlots = new Map(); // key: releasedSlotId -> released slot row
const _inMemoryPatientPrefs = new Map(); // key: `${patientId}::${dentistId}` -> preference row
const _inMemoryNotifDeliveries = new Map(); // key: `${releasedSlotId}::${patientId}` -> delivery row

const DoctorSchedulingSettings = {
    async getByDentistId(dentistId) {
        if (!dentistId) return { ...DEFAULT_SMART_SCHEDULE };
        const { canonicalId, dentistTableId, userTableId, idsToMatch } = await DoctorAvailability.resolveCanonicalIds(dentistId);

        // 1. Primary source of truth: dedicated public.doctor_scheduling_settings table
        const lookupId = dentistTableId || (isUUID(canonicalId) ? canonicalId : null);
        if (lookupId && isUUID(lookupId)) {
            try {
                const { data, error } = await supabaseAdmin
                    .from('doctor_scheduling_settings')
                    .select('*')
                    .eq('dentist_id', lookupId)
                    .maybeSingle();
                if (!error && data) {
                    const sanitized = sanitizeSmartSchedule({ ...data, isConfigured: true });
                    for (const k of idsToMatch) _inMemorySchedule.set(k, sanitized);
                    return sanitized;
                }
            } catch (e) {
                console.warn('⚠️ DoctorSchedulingSettings.getByDentistId notice:', e.message);
            }
        }

        // 2. In-memory cache (for pre-migration staging or mocked unit tests)
        for (const k of idsToMatch) {
            if (_inMemorySchedule.has(k)) {
                return sanitizeSmartSchedule(_inMemorySchedule.get(k));
            }
        }

        // 3. Read-only legacy migration fallback from users.device_token.schedule (NEVER writes back to device_token!)
        const targetUserId = userTableId || (dentistTableId ? null : dentistId);
        if (targetUserId && isUUID(targetUserId)) {
            try {
                const { data: uRow } = await supabaseAdmin
                    .from('users')
                    .select('id, device_token')
                    .eq('id', targetUserId)
                    .maybeSingle();
                if (uRow?.device_token && typeof uRow.device_token === 'string' && uRow.device_token.startsWith('{')) {
                    const meta = JSON.parse(uRow.device_token);
                    if (meta?.schedule && typeof meta.schedule === 'object') {
                        return sanitizeSmartSchedule({
                            ...meta.schedule,
                            blockedTimeRanges: meta.blockedSlotsByDate || meta.schedule.blockedTimeRanges || {},
                            isConfigured: meta.schedule.isConfigured !== false,
                        });
                    }
                }
            } catch (_) { }
        }

        return { ...DEFAULT_SMART_SCHEDULE };
    },

    async upsert(dentistId, scheduleData = {}) {
        if (!dentistId) return { ...DEFAULT_SMART_SCHEDULE };
        const { canonicalId, dentistTableId, idsToMatch } = await DoctorAvailability.resolveCanonicalIds(dentistId);
        const existing = await this.getByDentistId(dentistId);
        const nextSchedule = sanitizeSmartSchedule({ ...scheduleData, isConfigured: true }, existing);

        for (const k of idsToMatch) {
            _inMemorySchedule.set(k, nextSchedule);
        }

        const targetDentistId = dentistTableId || (isUUID(canonicalId) ? canonicalId : null);
        if (targetDentistId && isUUID(targetDentistId)) {
            try {
                const dbPayload = {
                    dentist_id: targetDentistId,
                    working_days: nextSchedule.workingDays,
                    start_time: nextSchedule.startTime,
                    end_time: nextSchedule.endTime,
                    breaks: nextSchedule.breaks,
                    default_duration_minutes: nextSchedule.defaultDurationMinutes,
                    in_person_enabled: nextSchedule.inPersonEnabled,
                    in_person_duration_minutes: nextSchedule.inPersonDurationMinutes,
                    online_enabled: nextSchedule.onlineEnabled,
                    online_duration_minutes: nextSchedule.onlineDurationMinutes,
                    online_working_days: nextSchedule.onlineWorkingDays,
                    online_start_time: nextSchedule.onlineStartTime,
                    online_end_time: nextSchedule.onlineEndTime,
                    buffer_minutes: nextSchedule.bufferMinutes,
                    online_buffer_minutes: nextSchedule.onlineBufferMinutes,
                    in_person_buffer_minutes: nextSchedule.inPersonBufferMinutes,
                    max_appointments_per_day: nextSchedule.maxAppointmentsPerDay,
                    allow_simultaneous_online_and_in_person: nextSchedule.allowSimultaneousOnlineAndInPerson,
                    blocked_time_ranges: nextSchedule.blockedTimeRanges || {},
                    updated_at: new Date().toISOString(),
                };
                const { data, error } = await supabaseAdmin
                    .from('doctor_scheduling_settings')
                    .upsert(dbPayload, { onConflict: 'dentist_id' })
                    .select()
                    .single();
                if (!error && data) {
                    const persisted = sanitizeSmartSchedule({ ...data, isConfigured: true });
                    for (const k of idsToMatch) _inMemorySchedule.set(k, persisted);
                    return persisted;
                }
                if (error) {
                    console.warn('⚠️ DoctorSchedulingSettings.upsert Supabase notice (keeping scheduling out of users.device_token):', error.message);
                }
            } catch (e) {
                console.warn('⚠️ DoctorSchedulingSettings.upsert notice:', e.message);
            }
        }
        return nextSchedule;
    },

    _clearInMemory() {
        _inMemorySchedule.clear();
        _inMemoryBlockedSlots.clear();
    },
};

const ReleasedSlot = {
    async create(slotData) {
        const cleanDate = normalizeDateToTimezoneYmd(slotData.appointment_date || slotData.appointmentDate);
        const mode = normalizeConsultationType(slotData.consultation_type || slotData.consultationType);
        const startMin = Number(slotData.start_min ?? slotData.startMin ?? parseClockSlotMinutes(slotData.start_time || slotData.startTime));
        const durMin = Number(slotData.duration_minutes ?? slotData.durationMinutes ?? 20);
        const endMin = Number(slotData.end_min ?? slotData.endMin ?? (startMin + durMin));
        const bufMin = Number(slotData.buffer_minutes ?? slotData.bufferMinutes ?? 0);
        const dentistId = slotData.dentist_id || slotData.dentistId;

        const payload = {
            dentist_id: dentistId,
            source_appointment_id: slotData.source_appointment_id || slotData.sourceAppointmentId || null,
            appointment_date: cleanDate,
            start_time: slotData.start_time || slotData.startTime || minutesToClockSlot(startMin),
            end_time: slotData.end_time || slotData.endTime || minutesToClockSlot(endMin),
            start_min: startMin,
            end_min: endMin,
            duration_minutes: durMin,
            buffer_minutes: bufMin,
            consultation_type: mode,
            status: 'AVAILABLE',
            claimed_by_appointment_id: null,
            expires_at: slotData.expires_at || slotData.expiresAt || new Date(Date.now() + 30 * 60 * 1000).toISOString(),
        };

        // In-memory duplicate guard (same doctor/date/mode/overlapping window)
        for (const existing of _inMemoryReleasedSlots.values()) {
            if (
                String(existing.dentist_id) === String(dentistId) &&
                existing.appointment_date === cleanDate &&
                existing.consultation_type === mode &&
                (existing.status === 'AVAILABLE' || existing.status === 'LOCKED') &&
                intervalsOverlap(startMin, endMin, existing.start_min, existing.end_min)
            ) {
                return existing;
            }
        }

        if (isUUID(dentistId)) {
            try {
                const { data, error } = await supabaseAdmin
                    .from('released_slots')
                    .insert(payload)
                    .select()
                    .single();
                if (!error && data) {
                    _inMemoryReleasedSlots.set(String(data.id), data);
                    return data;
                }
            } catch (e) {
                console.warn('⚠️ ReleasedSlot.create Supabase notice:', e.message);
            }
        }

        const memRow = {
            id: slotData.id || crypto.randomUUID(),
            ...payload,
            created_at: new Date().toISOString(),
        };
        _inMemoryReleasedSlots.set(String(memRow.id), memRow);
        return memRow;
    },

    async findById(id) {
        if (!id) return null;
        if (isUUID(id)) {
            try {
                const { data, error } = await supabaseAdmin
                    .from('released_slots')
                    .select('*')
                    .eq('id', id)
                    .maybeSingle();
                if (!error && data) return data;
            } catch (_) { }
        }
        return _inMemoryReleasedSlots.get(String(id)) || null;
    },

    async findForDoctorAndDate(dentistId, dateYmd, options = {}) {
        const cleanDate = normalizeDateToTimezoneYmd(dateYmd);
        if (!dentistId || !cleanDate) return [];
        const nowMs = (options.now ? new Date(options.now) : new Date()).getTime();
        const { idsToMatch } = await DoctorAvailability.resolveCanonicalIds(dentistId);

        // Auto-expire stale in-memory released slots
        for (const row of _inMemoryReleasedSlots.values()) {
            if (row.status === 'AVAILABLE' && new Date(row.expires_at).getTime() <= nowMs) {
                row.status = 'EXPIRED';
            }
        }

        const uuidIds = idsToMatch.filter(id => isUUID(id));
        if (uuidIds.length > 0) {
            try {
                let req = supabaseAdmin
                    .from('released_slots')
                    .select('*')
                    .eq('appointment_date', cleanDate);
                if (uuidIds.length === 1) req = req.eq('dentist_id', uuidIds[0]);
                else req = req.in('dentist_id', uuidIds);
                if (options.onlyAvailable) {
                    req = req.eq('status', 'AVAILABLE').gt('expires_at', new Date(nowMs).toISOString());
                }
                const { data, error } = await req.order('start_min', { ascending: true });
                if (!error && Array.isArray(data)) {
                    for (const row of data) _inMemoryReleasedSlots.set(String(row.id), row);
                    return data;
                }
            } catch (_) { }
        }

        return Array.from(_inMemoryReleasedSlots.values())
            .filter(r => {
                if (!idsToMatch.includes(String(r.dentist_id))) return false;
                if (r.appointment_date !== cleanDate) return false;
                if (options.onlyAvailable) {
                    if (r.status !== 'AVAILABLE') return false;
                    if (new Date(r.expires_at).getTime() <= nowMs) return false;
                }
                return true;
            })
            .sort((a, b) => a.start_min - b.start_min);
    },

    _clearInMemory() {
        _inMemoryReleasedSlots.clear();
    },
};

const AppointmentSlotLock = {
    _expireInMemory(dentistId, cleanDate, nowMs = Date.now()) {
        for (const lock of _inMemorySlotLocks.values()) {
            if (
                String(lock.dentist_id) === String(dentistId) &&
                lock.appointment_date === cleanDate &&
                lock.status === 'ACTIVE' &&
                new Date(lock.expires_at).getTime() <= nowMs
            ) {
                lock.status = 'EXPIRED';
                if (lock.released_slot_id) {
                    const rel = _inMemoryReleasedSlots.get(String(lock.released_slot_id));
                    if (rel && rel.status === 'LOCKED') {
                        rel.status = new Date(rel.expires_at).getTime() > nowMs ? 'AVAILABLE' : 'EXPIRED';
                    }
                }
            }
        }
        for (const rel of _inMemoryReleasedSlots.values()) {
            if (
                String(rel.dentist_id) === String(dentistId) &&
                rel.appointment_date === cleanDate &&
                rel.status === 'AVAILABLE' &&
                new Date(rel.expires_at).getTime() <= nowMs
            ) {
                rel.status = 'EXPIRED';
            }
        }
    },

    async findActiveForDoctorAndDate(dentistId, dateYmd, options = {}) {
        const cleanDate = normalizeDateToTimezoneYmd(dateYmd);
        if (!dentistId || !cleanDate) return [];
        const nowMs = (options.now ? new Date(options.now) : new Date()).getTime();
        const { idsToMatch } = await DoctorAvailability.resolveCanonicalIds(dentistId);
        for (const id of idsToMatch) this._expireInMemory(id, cleanDate, nowMs);

        const uuidIds = idsToMatch.filter(id => isUUID(id));
        if (uuidIds.length > 0) {
            try {
                let req = supabaseAdmin
                    .from('appointment_slot_locks')
                    .select('*')
                    .eq('appointment_date', cleanDate)
                    .eq('status', 'ACTIVE')
                    .gt('expires_at', new Date(nowMs).toISOString());
                if (uuidIds.length === 1) req = req.eq('dentist_id', uuidIds[0]);
                else req = req.in('dentist_id', uuidIds);
                const { data, error } = await req;
                if (!error && Array.isArray(data)) return data;
            } catch (_) { }
        }

        return Array.from(_inMemorySlotLocks.values()).filter(l =>
            idsToMatch.includes(String(l.dentist_id)) &&
            l.appointment_date === cleanDate &&
            l.status === 'ACTIVE' &&
            new Date(l.expires_at).getTime() > nowMs
        );
    },

    async acquire({
        dentistId,
        patientId,
        date,
        startTime,
        endTime,
        startMin,
        endMin,
        consultationType = 'In-Person',
        releasedSlotId = null,
        ttlSeconds = 300,
        now = null,
    }) {
        const cleanDate = normalizeDateToTimezoneYmd(date);
        const mode = normalizeConsultationType(consultationType);
        const sMin = Number(startMin ?? parseClockSlotMinutes(startTime));
        const eMin = Number(endMin);
        const safeTtl = Math.max(30, Math.min(900, parseInt(String(ttlSeconds || 300), 10) || 300));
        const nowDate = now ? new Date(now) : new Date();
        const nowMs = nowDate.getTime();

        if (!dentistId || !patientId || !cleanDate || !Number.isFinite(sMin) || !Number.isFinite(eMin) || sMin < 0 || sMin >= 1440 || eMin <= sMin) {
            return { success: false, reason: 'INVALID_INTERVAL', message: 'Invalid appointment slot parameters.' };
        }
        if (parseClockSlotMinutes(startTime) !== sMin) {
            return { success: false, reason: 'INVALID_INTERVAL', message: 'startTime does not match startMin.' };
        }

        const { canonicalId, dentistTableId } = await DoctorAvailability.resolveCanonicalIds(dentistId);
        const effectiveDentistId = dentistTableId || canonicalId || dentistId;

        // 1. Primary path: Supabase atomic RPC acquire_appointment_slot_lock (when Migration 04 is applied & IDs are UUIDs)
        if (!now && isUUID(effectiveDentistId) && isUUID(patientId) && (!releasedSlotId || isUUID(releasedSlotId))) {
            try {
                const { data, error } = await supabaseAdmin.rpc('acquire_appointment_slot_lock', {
                    p_dentist_id: effectiveDentistId,
                    p_patient_id: patientId,
                    p_date: cleanDate,
                    p_start_time: String(startTime).trim(),
                    p_end_time: String(endTime || minutesToClockSlot(eMin)).trim(),
                    p_start_min: sMin,
                    p_end_min: eMin,
                    p_consultation_type: mode,
                    p_released_slot_id: releasedSlotId || null,
                    p_ttl_seconds: safeTtl,
                });
                if (!error && data && typeof data === 'object') {
                    return data;
                }
            } catch (_) { }
        }

        // 2. Atomic in-memory fallback (full parity with Migration 04 RPC!)
        this._expireInMemory(effectiveDentistId, cleanDate, nowMs);
        const schedule = await DoctorSchedulingSettings.getByDentistId(effectiveDentistId);
        const modeWin = getModeScheduleWindow(schedule, mode);
        const lane = modeWin.capacityLane;

        // Validate daily limit
        const existingAppts = await Appointment.find({ dentistId: effectiveDentistId }).catch(() => []);
        const activeDateAppts = (existingAppts || []).filter(a => {
            const st = String(a.status || 'PENDING').toUpperCase();
            if (['CANCELLED', 'CANCELED', 'REJECTED', 'NO_SHOW'].includes(st)) return false;
            return normalizeDateToTimezoneYmd(a.appointment_date || a.date) === cleanDate;
        });
        if (schedule.maxAppointmentsPerDay !== null && activeDateAppts.length >= schedule.maxAppointmentsPerDay) {
            return { success: false, reason: 'DAILY_LIMIT_REACHED', message: 'Maximum appointments for this date have been reached.' };
        }

        // Step C: Validate released slot OR block regular lock from hijacking an active released slot
        let targetRel = null;
        if (releasedSlotId) {
            targetRel = _inMemoryReleasedSlots.get(String(releasedSlotId)) || null;
            if (
                !targetRel ||
                String(targetRel.dentist_id) !== String(effectiveDentistId) ||
                targetRel.appointment_date !== cleanDate ||
                targetRel.consultation_type !== mode ||
                targetRel.start_min !== sMin ||
                (targetRel.start_min + targetRel.duration_minutes + targetRel.buffer_minutes) !== eMin ||
                targetRel.status !== 'AVAILABLE' ||
                new Date(targetRel.expires_at).getTime() <= nowMs
            ) {
                return { success: false, reason: 'RELEASED_SLOT_UNAVAILABLE', message: 'This slot is no longer available. Please select another time.' };
            }
        } else {
            const overlappingRel = Array.from(_inMemoryReleasedSlots.values()).find(r =>
                String(r.dentist_id) === String(effectiveDentistId) &&
                r.appointment_date === cleanDate &&
                (r.status === 'AVAILABLE' || r.status === 'LOCKED') &&
                new Date(r.expires_at).getTime() > nowMs &&
                (lane === 'SHARED' || r.consultation_type.toUpperCase() === lane) &&
                intervalsOverlap(sMin, eMin, r.start_min, r.start_min + r.duration_minutes + r.buffer_minutes)
            );
            if (overlappingRel) {
                return { success: false, reason: 'RELEASED_SLOT_LOCK_REQUIRED', message: 'This released slot must be locked using its released slot ID.' };
            }
        }

        // Step D: Validate no overlapping active appointment (uses getAppointmentOccupiedInterval for early-completion truncation & delays)
        const conflictAppt = activeDateAppts.find(a => {
            const occ = getAppointmentOccupiedInterval(a);
            if (!occ) return false;
            if (lane !== 'SHARED' && occ.consultationType.toUpperCase() !== lane) return false;
            return intervalsOverlap(sMin, eMin, occ.startMin, occ.occupiedEndMin);
        });
        if (conflictAppt) {
            return { success: false, reason: 'APPOINTMENT_CONFLICT', message: 'This slot is no longer available. Please select another time.' };
        }

        // Step E: Validate no overlapping active lock held by another patient
        const conflictLock = Array.from(_inMemorySlotLocks.values()).find(l =>
            String(l.dentist_id) === String(effectiveDentistId) &&
            l.appointment_date === cleanDate &&
            l.status === 'ACTIVE' &&
            new Date(l.expires_at).getTime() > nowMs &&
            String(l.patient_id) !== String(patientId) &&
            (lane === 'SHARED' || l.consultation_type.toUpperCase() === lane) &&
            intervalsOverlap(sMin, eMin, l.start_min, l.end_min)
        );
        if (conflictLock) {
            return { success: false, reason: 'SLOT_LOCKED', message: 'This slot is no longer available. Please select another time.' };
        }

        // Step F: All validations passed -> safely release caller's previous active lock on this doctor/date
        for (const prev of _inMemorySlotLocks.values()) {
            if (
                String(prev.dentist_id) === String(effectiveDentistId) &&
                String(prev.patient_id) === String(patientId) &&
                prev.appointment_date === cleanDate &&
                prev.status === 'ACTIVE'
            ) {
                prev.status = 'RELEASED';
                if (prev.released_slot_id && String(prev.released_slot_id) !== String(releasedSlotId || '')) {
                    const oldRel = _inMemoryReleasedSlots.get(String(prev.released_slot_id));
                    if (oldRel && oldRel.status === 'LOCKED') {
                        oldRel.status = new Date(oldRel.expires_at).getTime() > nowMs ? 'AVAILABLE' : 'EXPIRED';
                    }
                }
            }
        }

        const lockId = crypto.randomUUID();
        const expiresAt = new Date(nowMs + safeTtl * 1000).toISOString();
        const lockRow = {
            id: lockId,
            dentist_id: effectiveDentistId,
            patient_id: patientId,
            appointment_date: cleanDate,
            start_time: String(startTime).trim(),
            end_time: String(endTime || minutesToClockSlot(eMin)).trim(),
            start_min: sMin,
            end_min: eMin,
            consultation_type: mode,
            released_slot_id: releasedSlotId || null,
            status: 'ACTIVE',
            expires_at: expiresAt,
            created_at: nowDate.toISOString(),
        };
        _inMemorySlotLocks.set(lockId, lockRow);
        if (targetRel) {
            targetRel.status = 'LOCKED';
        }

        return { success: true, lockId, expiresAt };
    },

    async release(lockId, patientId) {
        if (!lockId) return { success: false, reason: 'NOT_FOUND' };
        if (isUUID(lockId) && isUUID(patientId)) {
            try {
                const { data, error } = await supabaseAdmin.rpc('release_appointment_slot_lock', {
                    p_lock_id: lockId,
                    p_patient_id: patientId,
                });
                if (!error && data && typeof data === 'object') {
                    return data;
                }
            } catch (_) { }
        }

        const lock = _inMemorySlotLocks.get(String(lockId));
        if (!lock) return { success: false, reason: 'NOT_FOUND' };
        if (patientId && String(lock.patient_id) !== String(patientId)) {
            return { success: false, reason: 'FORBIDDEN' };
        }
        if (lock.status !== 'ACTIVE') {
            return { success: true, status: lock.status };
        }
        lock.status = 'RELEASED';
        if (lock.released_slot_id) {
            const rel = _inMemoryReleasedSlots.get(String(lock.released_slot_id));
            if (rel && rel.status === 'LOCKED') {
                rel.status = new Date(rel.expires_at).getTime() > Date.now() ? 'AVAILABLE' : 'EXPIRED';
            }
        }
        return { success: true, status: 'RELEASED' };
    },

    /**
     * Mandatory-lock atomic booking confirmation. Mirrors Migration 04 `confirm_appointment_booking` RPC exactly:
     * - Rejects NULL / missing / expired / mismatched lockId
     * - Rejects direct booking of AVAILABLE released slot without an owning active lock
     */
    async confirmBooking({
        patientId,
        dentistId,
        clinicId = null,
        date,
        timeSlot,
        startMin,
        durationMinutes,
        bufferMinutes = 0,
        consultationType = 'In-Person',
        treatment = 'Medical Consultation',
        status = 'PENDING',
        qrCodeString = null,
        lockId,
        releasedSlotId = null,
        now = null,
    }) {
        if (!lockId) {
            return {
                success: false,
                reason: 'LOCK_REQUIRED',
                message: 'An active slot lock is required to confirm this booking.',
            };
        }

        const cleanDate = normalizeDateToTimezoneYmd(date);
        const mode = normalizeConsultationType(consultationType, treatment);
        const sMin = Number(startMin ?? parseClockSlotMinutes(timeSlot));
        const durMin = Number(durationMinutes);
        const bufMin = Math.max(0, Number(bufferMinutes || 0));
        const occupiedEndMin = sMin + durMin + bufMin;

        if (!patientId || !dentistId || !cleanDate || !Number.isFinite(sMin) || !Number.isFinite(durMin) || durMin <= 0 || parseClockSlotMinutes(timeSlot) !== sMin) {
            return { success: false, reason: 'INVALID_PARAMETERS', message: 'Invalid booking parameters.' };
        }

        const { canonicalId, dentistTableId } = await DoctorAvailability.resolveCanonicalIds(dentistId);
        const effectiveDentistId = dentistTableId || canonicalId || dentistId;

        // 1. Primary path: Supabase atomic RPC confirm_appointment_booking
        if (!now && isUUID(effectiveDentistId) && isUUID(patientId) && isUUID(lockId) && (!releasedSlotId || isUUID(releasedSlotId))) {
            try {
                const { data, error } = await supabaseAdmin.rpc('confirm_appointment_booking', {
                    p_patient_id: patientId,
                    p_dentist_id: effectiveDentistId,
                    p_clinic_id: isUUID(clinicId) ? clinicId : null,
                    p_date: cleanDate,
                    p_time_slot: String(timeSlot).trim(),
                    p_start_min: sMin,
                    p_duration_minutes: durMin,
                    p_buffer_minutes: bufMin,
                    p_consultation_type: mode,
                    p_treatment: treatment,
                    p_status: status || 'PENDING',
                    p_qr_code_string: qrCodeString || `DENTAGURU-${patientId}-${Date.now()}`,
                    p_lock_id: lockId,
                    p_released_slot_id: releasedSlotId || null,
                });
                if (!error && data && typeof data === 'object') {
                    return data;
                }
            } catch (_) { }
        }

        // 2. Full-parity in-memory + Appointment.create fallback
        const nowMs = (now ? new Date(now) : new Date()).getTime();
        this._expireInMemory(effectiveDentistId, cleanDate, nowMs);

        const lock = _inMemorySlotLocks.get(String(lockId));
        if (
            !lock ||
            String(lock.patient_id) !== String(patientId) ||
            String(lock.dentist_id) !== String(effectiveDentistId) ||
            lock.appointment_date !== cleanDate ||
            lock.start_min !== sMin ||
            lock.end_min !== occupiedEndMin ||
            String(lock.start_time || '').trim().toLowerCase() !== String(timeSlot || '').trim().toLowerCase() ||
            lock.consultation_type !== mode ||
            (lock.released_slot_id || null) !== (releasedSlotId || null) ||
            lock.status !== 'ACTIVE' ||
            new Date(lock.expires_at).getTime() <= nowMs
        ) {
            return {
                success: false,
                reason: 'LOCK_MISMATCH_OR_EXPIRED',
                message: 'This slot is no longer available. Please select another time.',
            };
        }

        const schedule = await DoctorSchedulingSettings.getByDentistId(effectiveDentistId);
        const modeWin = getModeScheduleWindow(schedule, mode);
        const lane = modeWin.capacityLane;

        // Strict released-slot ownership validation: MUST be LOCKED and owned by this exact active lock!
        let targetRel = null;
        if (releasedSlotId) {
            targetRel = _inMemoryReleasedSlots.get(String(releasedSlotId)) || null;
            if (
                !targetRel ||
                String(targetRel.dentist_id) !== String(effectiveDentistId) ||
                targetRel.appointment_date !== cleanDate ||
                targetRel.consultation_type !== mode ||
                targetRel.start_min !== sMin ||
                targetRel.duration_minutes !== durMin ||
                (targetRel.start_min + targetRel.duration_minutes + targetRel.buffer_minutes) !== occupiedEndMin ||
                new Date(targetRel.expires_at).getTime() <= nowMs ||
                targetRel.status !== 'LOCKED' ||
                String(lock.released_slot_id || '') !== String(releasedSlotId)
            ) {
                return {
                    success: false,
                    reason: 'RELEASED_SLOT_LOCK_MISMATCH',
                    message: 'This slot is no longer available. Please select another time.',
                };
            }
        } else {
            const overlappingRel = Array.from(_inMemoryReleasedSlots.values()).find(r =>
                String(r.dentist_id) === String(effectiveDentistId) &&
                r.appointment_date === cleanDate &&
                (r.status === 'AVAILABLE' || r.status === 'LOCKED') &&
                new Date(r.expires_at).getTime() > nowMs &&
                (lane === 'SHARED' || r.consultation_type.toUpperCase() === lane) &&
                intervalsOverlap(sMin, occupiedEndMin, r.start_min, r.start_min + r.duration_minutes + r.buffer_minutes)
            );
            if (overlappingRel) {
                return {
                    success: false,
                    reason: 'RELEASED_SLOT_LOCK_REQUIRED',
                    message: 'This released slot must be booked via its active released-slot lock.',
                };
            }
        }

        const otherLock = Array.from(_inMemorySlotLocks.values()).find(l =>
            String(l.dentist_id) === String(effectiveDentistId) &&
            l.appointment_date === cleanDate &&
            l.status === 'ACTIVE' &&
            new Date(l.expires_at).getTime() > nowMs &&
            String(l.patient_id) !== String(patientId) &&
            (lane === 'SHARED' || l.consultation_type.toUpperCase() === lane) &&
            intervalsOverlap(sMin, occupiedEndMin, l.start_min, l.end_min)
        );
        if (otherLock) {
            return { success: false, reason: 'SLOT_LOCKED', message: 'This slot is no longer available. Please select another time.' };
        }

        const created = await Appointment.create({
            patient_id: patientId,
            dentist_id: effectiveDentistId,
            clinic_id: clinicId,
            date: `${cleanDate}T00:00:00.000Z`,
            appointment_date: cleanDate,
            time_slot: String(timeSlot).trim(),
            treatment,
            status: status || 'PENDING',
            qr_code_string: qrCodeString,
            consultation_type: mode,
            capacity_lane: lane,
            duration_minutes: durMin,
            buffer_minutes: bufMin,
            scheduled_start_min: sMin,
            released_slot_id: releasedSlotId || null,
        });

        lock.status = 'CONFIRMED';
        if (targetRel) {
            targetRel.status = 'BOOKED';
            targetRel.claimed_by_appointment_id = created?.id || null;
        }

        return { success: true, appointment: created };
    },

    getInMemoryLock(lockId) {
        return _inMemorySlotLocks.get(String(lockId)) || null;
    },

    _clearInMemory() {
        _inMemorySlotLocks.clear();
    },
};

const PatientDoctorPreference = {
    async upsert({
        patientId,
        dentistId,
        isFavorite = false,
        notifyEarlierSlots = false,
        preferredConsultationType = 'Any',
        preferredDate = null,
        earliestTimeMin = null,
        latestTimeMin = null,
    }) {
        if (!patientId || !dentistId) throw new Error('patientId and dentistId are required.');
        const { canonicalId, dentistTableId } = await DoctorAvailability.resolveCanonicalIds(dentistId);
        const effectiveDentistId = dentistTableId || canonicalId || dentistId;
        const cleanPrefMode = ['Any', 'Online', 'In-Person'].includes(String(preferredConsultationType))
            ? String(preferredConsultationType)
            : 'Any';
        const cleanPrefDate = preferredDate ? normalizeDateToTimezoneYmd(preferredDate) : null;

        const payload = {
            patient_id: patientId,
            dentist_id: effectiveDentistId,
            is_favorite: Boolean(isFavorite),
            notify_earlier_slots: Boolean(notifyEarlierSlots),
            preferred_consultation_type: cleanPrefMode,
            preferred_date: cleanPrefDate || null,
            earliest_time_min: earliestTimeMin !== null && earliestTimeMin !== undefined && earliestTimeMin !== '' ? Number(earliestTimeMin) : null,
            latest_time_min: latestTimeMin !== null && latestTimeMin !== undefined && latestTimeMin !== '' ? Number(latestTimeMin) : null,
            updated_at: new Date().toISOString(),
        };

        const key = `${patientId}::${effectiveDentistId}`;
        if (isUUID(patientId) && isUUID(effectiveDentistId)) {
            try {
                const { data, error } = await supabaseAdmin
                    .from('patient_doctor_preferences')
                    .upsert(payload, { onConflict: 'patient_id,dentist_id' })
                    .select()
                    .single();
                if (!error && data) {
                    _inMemoryPatientPrefs.set(key, data);
                    return data;
                }
            } catch (e) {
                console.warn('⚠️ PatientDoctorPreference.upsert Supabase notice:', e.message);
            }
        }

        const existing = _inMemoryPatientPrefs.get(key);
        const row = { id: existing?.id || crypto.randomUUID(), created_at: existing?.created_at || new Date().toISOString(), ...payload };
        _inMemoryPatientPrefs.set(key, row);
        return row;
    },

    async findForPatient(patientId, dentistId = null) {
        if (!patientId) return [];
        const targetDoc = dentistId ? (await DoctorAvailability.resolveCanonicalIds(dentistId)).canonicalId : null;
        if (isUUID(patientId)) {
            try {
                let req = supabaseAdmin.from('patient_doctor_preferences').select('*').eq('patient_id', patientId);
                if (targetDoc && isUUID(targetDoc)) req = req.eq('dentist_id', targetDoc);
                const { data, error } = await req;
                if (!error && Array.isArray(data)) return data;
            } catch (_) { }
        }
        return Array.from(_inMemoryPatientPrefs.values()).filter(p =>
            String(p.patient_id) === String(patientId) &&
            (!targetDoc || String(p.dentist_id) === String(targetDoc))
        );
    },

    async findNotifyEligibleForDoctor(dentistId) {
        if (!dentistId) return [];
        const { idsToMatch } = await DoctorAvailability.resolveCanonicalIds(dentistId);
        const uuidIds = idsToMatch.filter(id => isUUID(id));
        if (uuidIds.length > 0) {
            try {
                let req = supabaseAdmin
                    .from('patient_doctor_preferences')
                    .select('*')
                    .eq('notify_earlier_slots', true);
                if (uuidIds.length === 1) req = req.eq('dentist_id', uuidIds[0]);
                else req = req.in('dentist_id', uuidIds);
                const { data, error } = await req;
                if (!error && Array.isArray(data)) return data;
            } catch (_) { }
        }
        return Array.from(_inMemoryPatientPrefs.values()).filter(p =>
            idsToMatch.includes(String(p.dentist_id)) && Boolean(p.notify_earlier_slots)
        );
    },

    _clearInMemory() {
        _inMemoryPatientPrefs.clear();
    },
};

const SlotNotificationDelivery = {
    async tryClaim(releasedSlotId, patientId) {
        if (!releasedSlotId || !patientId) return { claimed: false };
        const key = `${releasedSlotId}::${patientId}`;
        if (_inMemoryNotifDeliveries.has(key)) {
            return { claimed: false, duplicate: true };
        }

        if (isUUID(releasedSlotId) && isUUID(patientId)) {
            try {
                const { data, error } = await supabaseAdmin
                    .from('slot_notification_deliveries')
                    .insert({
                        released_slot_id: releasedSlotId,
                        patient_id: patientId,
                        delivery_status: 'PENDING',
                    })
                    .select()
                    .single();
                if (!error && data) {
                    _inMemoryNotifDeliveries.set(key, data);
                    return { claimed: true, record: data };
                }
                if (error && (error.code === '23505' || String(error.message || '').toLowerCase().includes('duplicate'))) {
                    return { claimed: false, duplicate: true };
                }
            } catch (_) { }
        }

        const row = {
            id: crypto.randomUUID(),
            released_slot_id: releasedSlotId,
            patient_id: patientId,
            delivery_status: 'PENDING',
            created_at: new Date().toISOString(),
        };
        _inMemoryNotifDeliveries.set(key, row);
        return { claimed: true, record: row };
    },

    async updateStatus(releasedSlotId, patientId, patch = {}) {
        const key = `${releasedSlotId}::${patientId}`;
        const existing = _inMemoryNotifDeliveries.get(key);
        if (existing) {
            Object.assign(existing, patch);
        }
        if (isUUID(releasedSlotId) && isUUID(patientId)) {
            try {
                await supabaseAdmin
                    .from('slot_notification_deliveries')
                    .update(patch)
                    .eq('released_slot_id', releasedSlotId)
                    .eq('patient_id', patientId);
            } catch (_) { }
        }
    },

    getAllInMemory() {
        return Array.from(_inMemoryNotifDeliveries.values());
    },

    _clearInMemory() {
        _inMemoryNotifDeliveries.clear();
    },
};

const DoctorAvailability = {
    extractDateYmd,
    getWeekdayNameFromYmd,
    normalizeWorkingDays,

    async resolveCanonicalIds(dentistId) {
        if (!dentistId) return { canonicalId: null, dentistTableId: null, userTableId: null, idsToMatch: [] };
        let dentistTableId = null;
        let userTableId = null;
        try {
            const resolved = await resolveDentistIds(dentistId);
            dentistTableId = resolved.dentistTableId || null;
            userTableId = resolved.userTableId || null;
        } catch (_) { }
        const canonicalId = dentistTableId || dentistId;
        const idsToMatch = [...new Set([dentistId, dentistTableId, userTableId].filter(Boolean))];
        return { canonicalId, dentistTableId, userTableId, idsToMatch };
    },

    async getSchedule(dentistId) {
        return await DoctorSchedulingSettings.getByDentistId(dentistId);
    },

    async saveSchedule(dentistId, scheduleData = {}) {
        return await DoctorSchedulingSettings.upsert(dentistId, scheduleData);
    },

    async findOne(query = {}) {
        const dentistId = query.dentist_id || query.dentistId;
        const cleanDate = extractDateYmd(query.date);
        if (!dentistId || !cleanDate) return null;

        const { idsToMatch } = await this.resolveCanonicalIds(dentistId);

        try {
            let req = supabaseAdmin
                .from('doctor_availability')
                .select('*')
                .eq('date', cleanDate);
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
            extractDateYmd(a.date) === cleanDate
        ) || null;
    },

    async find(query = {}) {
        const dentistId = query.dentist_id || query.dentistId;
        const cleanFilterDate = query.date ? extractDateYmd(query.date) : null;
        const { idsToMatch } = dentistId ? await this.resolveCanonicalIds(dentistId) : { idsToMatch: [] };
        try {
            let req = supabaseAdmin.from('doctor_availability').select('*');
            if (idsToMatch.length === 1) req = req.eq('dentist_id', idsToMatch[0]);
            else if (idsToMatch.length > 1) req = req.in('dentist_id', idsToMatch);
            if (cleanFilterDate) req = req.eq('date', cleanFilterDate);
            if (query.is_blocked !== undefined) req = req.eq('is_blocked', Boolean(query.is_blocked));
            const { data, error } = await req.order('date', { ascending: true });
            if (!error && Array.isArray(data)) {
                // Deduplicate by normalized date
                const byDate = new Map();
                for (const row of data) {
                    const dKey = extractDateYmd(row.date);
                    if (!dKey) continue;
                    if (!byDate.has(dKey) || row.is_blocked) {
                        byDate.set(dKey, { ...row, date: dKey });
                    }
                }
                return Array.from(byDate.values()).sort((a, b) => a.date.localeCompare(b.date));
            }
        } catch (e) {
            console.warn('⚠️ DoctorAvailability.find Supabase notice:', e.message);
        }

        const filtered = _inMemoryAvailability.filter(a => {
            if (idsToMatch.length > 0 && !idsToMatch.includes(a.dentist_id) && !idsToMatch.includes(a.dentistId)) return false;
            if (cleanFilterDate && extractDateYmd(a.date) !== cleanFilterDate) return false;
            if (query.is_blocked !== undefined && Boolean(a.is_blocked) !== Boolean(query.is_blocked)) return false;
            return true;
        });
        return filtered.sort((a, b) => extractDateYmd(a.date).localeCompare(extractDateYmd(b.date)));
    },

    async upsert(availData) {
        const rawDentistId = availData.dentist_id || availData.dentistId;
        const cleanDate = extractDateYmd(availData.date);
        const { canonicalId, dentistTableId, idsToMatch } = await this.resolveCanonicalIds(rawDentistId);
        const targetDentistId = dentistTableId || canonicalId || rawDentistId;

        const slots = Array.isArray(availData.slots) ? [...new Set(availData.slots.map(s => String(s).trim()).filter(Boolean))] : [];
        const isBlocked = Boolean(availData.is_blocked ?? availData.isBlocked ?? false);
        const blockedReason = isBlocked ? (availData.blocked_reason || availData.blockedReason || 'Doctor on Leave / Clinic Closed') : null;
        const startTime = availData.start_time || availData.startTime || '09:00 AM';
        const endTime = availData.end_time || availData.endTime || '05:00 PM';
        const slotDuration = parseInt(availData.slot_duration_minutes || availData.slotDurationMinutes, 10) || 30;
        const dayOfWeek = String(availData.day_of_week || availData.dayOfWeek || getWeekdayNameFromYmd(cleanDate) || '').slice(0, 20);

        const payload = {
            id: availData.id || `avail-${Date.now()}-${Math.random().toString(36).substring(2, 7)}`,
            dentist_id: targetDentistId,
            date: cleanDate,
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
            if (isUUID(targetDentistId)) {
                const { data, error } = await supabaseAdmin
                    .from('doctor_availability')
                    .upsert({
                        dentist_id: targetDentistId,
                        date: cleanDate,
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
                if (error) {
                    console.warn('⚠️ DoctorAvailability.upsert Supabase error:', error.message);
                }
            }
        } catch (e) {
            console.warn('⚠️ DoctorAvailability.upsert Supabase notice:', e.message);
        }

        const idx = _inMemoryAvailability.findIndex(a =>
            (idsToMatch.includes(a.dentist_id) || idsToMatch.includes(a.dentistId)) && extractDateYmd(a.date) === cleanDate
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
        const rawDentistId = query.dentist_id || query.dentistId;
        const cleanDate = extractDateYmd(query.date);
        const { idsToMatch } = await this.resolveCanonicalIds(rawDentistId);
        try {
            if (idsToMatch.length > 0 && cleanDate) {
                const uuidIds = idsToMatch.filter(id => isUUID(id));
                if (uuidIds.length > 0) {
                    await supabaseAdmin
                        .from('doctor_availability')
                        .delete()
                        .in('dentist_id', uuidIds)
                        .eq('date', cleanDate);
                }
            }
        } catch (e) {
            console.warn('⚠️ DoctorAvailability.deleteOne Supabase notice:', e.message);
        }

        for (let i = _inMemoryAvailability.length - 1; i >= 0; i--) {
            const a = _inMemoryAvailability[i];
            if ((idsToMatch.includes(a.dentist_id) || idsToMatch.includes(a.dentistId)) && extractDateYmd(a.date) === cleanDate) {
                _inMemoryAvailability.splice(i, 1);
            }
        }
        return { success: true };
    },

    async getBlockedSlotsForDate(dentistId, dateYmd) {
        const cleanDate = extractDateYmd(dateYmd);
        if (!dentistId || !cleanDate) return [];
        const { idsToMatch } = await this.resolveCanonicalIds(dentistId);

        // 1. Primary source: doctor_scheduling_settings.blocked_time_ranges (keeps scheduling out of users.device_token)
        const settings = await DoctorSchedulingSettings.getByDentistId(dentistId);
        if (settings?.blockedTimeRanges && Array.isArray(settings.blockedTimeRanges[cleanDate]) && settings.blockedTimeRanges[cleanDate].length > 0) {
            return settings.blockedTimeRanges[cleanDate];
        }

        for (const k of idsToMatch) {
            const mem = _inMemoryBlockedSlots.get(`${k}_${cleanDate}`);
            if (Array.isArray(mem)) return mem;
        }
        return [];
    },

    async saveBlockedSlotsForDate(dentistId, dateYmd, blockedSlots = []) {
        const cleanDate = extractDateYmd(dateYmd);
        if (!dentistId || !cleanDate) return [];
        const { idsToMatch } = await this.resolveCanonicalIds(dentistId);
        const sanitized = Array.isArray(blockedSlots) ? blockedSlots : [];

        for (const k of idsToMatch) {
            _inMemoryBlockedSlots.set(`${k}_${cleanDate}`, sanitized);
        }

        // Persist strictly into doctor_scheduling_settings.blocked_time_ranges (NEVER writes to users.device_token!)
        const current = await DoctorSchedulingSettings.getByDentistId(dentistId);
        const nextMap = { ...(current.blockedTimeRanges || {}) };
        if (sanitized.length === 0) {
            delete nextMap[cleanDate];
        } else {
            nextMap[cleanDate] = sanitized;
        }
        await DoctorSchedulingSettings.upsert(dentistId, {
            ...current,
            blockedTimeRanges: nextMap,
        });
        return sanitized;
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
        } catch (_) { }

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
        } catch (_) { }

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
        } catch (_) { }

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
        } catch (_) { }

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
        } catch (_) { }

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

/**
 * Canonical Doctor Availability helpers (reuses existing `dentists.availability_status` column)
 * - ON  => 'Available'
 * - OFF => 'Unavailable' (also treats legacy 'Offline', 'Inactive', 'On Leave', 'OFF', 'Suspended' as OFF)
 */
const UNAVAILABLE_STATUS_VALUES = new Set([
    'unavailable',
    'offline',
    'inactive',
    'on leave',
    'on_leave',
    'off',
    'false',
    'disabled',
    'suspended'
]);

function isDoctorAvailableStatus(status) {
    if (status === false) return false;
    if (status === true || status === null || status === undefined) return true;
    const normalized = String(status).trim().toLowerCase();
    if (!normalized) return true;
    return !UNAVAILABLE_STATUS_VALUES.has(normalized);
}

function isDoctorRecordAvailable(doctor) {
    if (!doctor) return false;
    const verStatus = String(doctor.verification_status || doctor.verificationStatus || '').trim().toUpperCase();
    if (verStatus === 'SUSPENDED') return false;
    const rawStatus = doctor.availability_status !== undefined
        ? doctor.availability_status
        : doctor.status;
    return isDoctorAvailableStatus(rawStatus);
}

function normalizeAvailabilityStatus(input) {
    if (typeof input === 'boolean') {
        return input ? 'Available' : 'Unavailable';
    }
    const normalized = String(input ?? '').trim().toLowerCase();
    if (!normalized) return null;
    if (normalized === 'online') return 'Online';
    if (normalized.includes('busy') && normalized.includes('online')) return 'Busy – Online Consultation';
    if (normalized.includes('busy') && (normalized.includes('in-person') || normalized.includes('in person') || normalized.includes('clinic'))) {
        return 'Busy – In-Person Consultation';
    }
    if (normalized === 'busy' || normalized === 'in consultation' || normalized === 'in_consultation') return 'Busy';
    if (normalized === 'delayed' || normalized === 'running late' || normalized === 'running_late') return 'Delayed';
    if (normalized === 'on' || normalized === 'true' || normalized === 'available' || normalized === 'active') {
        return 'Available';
    }
    if (UNAVAILABLE_STATUS_VALUES.has(normalized)) {
        return normalized === 'offline' ? 'Offline' : 'Unavailable';
    }
    return null;
}

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
    DoctorSchedulingSettings,
    AppointmentSlotLock,
    ReleasedSlot,
    PatientDoctorPreference,
    SlotNotificationDelivery,
    MedicalSpecialty,
    DEFAULT_MEDICAL_SPECIALTIES,
    District,
    DEFAULT_DISTRICTS,
    SubAdminDistrict,
    PermissionChangeHistory,
    PatientAssignmentHistory,
    ASSIGNMENT_SOURCES,
    isDentalSpecialtyText,
    getDefaultQualificationForSpecialty,
    resolveMedicalSpecialtyRecord,
    matchesSpecialtyQuery,
    normalizeLanguagesList,
    parseLanguageFilters,
    extractDoctorLanguages,
    doctorMatchesLanguages,
    SUPPORTED_LANGUAGES,
    canonicalLanguageKey,
    canonicalLanguageDisplayName,
    mergeSupportedAndDoctorLanguages,
    isDoctorAvailableStatus,
    isDoctorRecordAvailable,
    normalizeAvailabilityStatus,
    resolveUserUuid,
    resolveDentistIds,
    resolveClinicIds,
    resolveClinicUuid,
    canonicalPhone10,
    comparePassword
};



