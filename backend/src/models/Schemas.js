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

    async find(query = {}) {
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
                return result;
            }
            return data || [];
        } catch (e) {
            console.warn('⚠️ User find exception, falling back to simple select:', e.message);
            const simple = await supabaseAdmin.from('users').select('*');
            let result = simple.data || [];
            if (query.role) {
                result = result.filter(u => u.role && u.role.toLowerCase() === query.role.toLowerCase());
            }
            return result;
        }
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
            services: clinicData.services || ['General Dentistry', 'Gum Care', 'Root Canal'],
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
        try {
            let req = supabaseAdmin.from('dentists').select('*, users(name, email, phone, state, city, pincode, latitude, longitude), clinics(clinic_name, location)');
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
            if (query.speciality) {
                req = req.ilike('speciality', `%${query.speciality}%`);
            }
            // clinic_id filter
            if (query.clinic_id) {
                req = req.eq('clinic_id', query.clinic_id);
            }
            const { data, error } = await req;
            if (error) {
                console.warn('⚠️ Dentist query join failed, falling back to simple select:', error.message);
                const simple = await supabaseAdmin.from('dentists').select('*');
                return simple.data || [];
            }
            return data || [];
        } catch (e) {
            console.warn('⚠️ Dentist query error, falling back to simple select:', e.message);
            const simple = await supabaseAdmin.from('dentists').select('*');
            return simple.data || [];
        }
    },

    async create(dentistData) {
        const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
        const payload = {
            ...dentistData,
            user_id: (dentistData.user_id && uuidRegex.test(dentistData.user_id.toString())) ? dentistData.user_id.toString() : null,
            clinic_id: (dentistData.clinic_id && uuidRegex.test(dentistData.clinic_id.toString())) ? dentistData.clinic_id.toString() : null,
        };
        const { data, error } = await supabaseAdmin.from('dentists').insert(payload).select().single();
        if (error) {
            console.error('❌ Supabase Dentist Insert Error:', error.message);
            throw error;
        }
        return data;
    }
};

// 4. APPOINTMENT MODEL (Supabase PostgreSQL)
const isUUID = (str) => typeof str === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(str.trim());

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
    const str = String(input).trim();
    if (isUUID(str)) return str;

    try {
        let user = await User.findOne({ name: str });
        if (!user) user = await User.findOne({ email: str });
        if (user) {
            let d = await supabaseAdmin.from('dentists').select('*').eq('user_id', user.id).maybeSingle();
            if (d && d.data) return d.data.id;
        }

        const { data: dentists } = await supabaseAdmin.from('dentists').select('id').limit(1);
        if (dentists && dentists.length > 0) return dentists[0].id;
    } catch (e) {
        console.error('Error resolving dentist UUID:', e.message);
    }
    return null;
}

async function resolveClinicUuid(input) {
    if (!input) return null;
    const str = String(input).trim();
    if (isUUID(str)) return str;

    try {
        let c = await Clinic.findOne({ clinic_name: str });
        if (c) return c.id;

        const { data: clinics } = await supabaseAdmin.from('clinics').select('id').limit(1);
        if (clinics && clinics.length > 0) return clinics[0].id;
    } catch (e) {
        console.error('Error resolving clinic UUID:', e.message);
    }
    return null;
}

// 4. APPOINTMENT MODEL (Supabase PostgreSQL)
const Appointment = {
    async create(appData) {
        const targetPatientId = await resolveUserUuid(appData.patient_id || appData.patientId);
        const targetDentistId = await resolveDentistUuid(appData.dentist_id || appData.dentistId);
        const targetClinicId = await resolveClinicUuid(appData.clinic_id || appData.clinicId);

        const payload = {
            patient_id: targetPatientId,
            dentist_id: targetDentistId,
            clinic_id: targetClinicId,
            date: appData.date ? new Date(appData.date).toISOString() : new Date().toISOString(),
            time_slot: appData.time_slot || appData.timeSlot || 'Today, 2:30 PM',
            treatment: appData.treatment || 'Dental Consultation',
            status: appData.status || 'confirmed',
            payment_status: appData.payment_status || appData.paymentStatus || 'paid',
            qr_code_string: appData.qr_code_string || appData.qrCodeString || null
        };
        const { data, error } = await supabaseAdmin.from('appointments').insert(payload).select().single();
        if (error) {
            console.error('❌ Supabase Appointment Insert Error:', error.message);
            throw error;
        }
        return data;
    },

    async find(query = {}) {
        let req = supabaseAdmin.from('appointments').select('*, patient:users!patient_id(name, email, phone), clinic:clinics!clinic_id(clinic_name, location)');
        const pId = query.patientId || query.patient_id;
        const dId = query.dentistId || query.dentist_id;
        const cId = query.clinicId || query.clinic_id;

        if (pId) {
            const resolvedP = await resolveUserUuid(pId);
            if (Array.isArray(resolvedP) && resolvedP.length > 0) {
                req = req.in('patient_id', resolvedP);
            } else if (typeof resolvedP === 'string' && resolvedP.length > 0) {
                req = req.eq('patient_id', resolvedP);
            }
        }
        if (dId) {
            const resolvedD = await resolveDentistUuid(dId);
            if (Array.isArray(resolvedD) && resolvedD.length > 0) {
                req = req.in('dentist_id', resolvedD);
            } else if (typeof resolvedD === 'string' && resolvedD.length > 0) {
                req = req.eq('dentist_id', resolvedD);
            }
        }
        if (cId) {
            const resolvedC = await resolveClinicUuid(cId);
            if (typeof resolvedC === 'string' && resolvedC.length > 0) {
                req = req.eq('clinic_id', resolvedC);
            }
        }

        const { data, error } = await req.order('date', { ascending: true });
        if (error) {
            console.warn('⚠️ Appointment find warning, fallback to simple select:', error.message);
            const simple = await supabaseAdmin.from('appointments').select('*').order('date', { ascending: false });
            return simple.data || [];
        }
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
        const targetPatientId = await resolveUserUuid(recordData.patient_id || recordData.patientId);
        const targetDentistId = await resolveDentistUuid(recordData.dentist_id || recordData.dentistId);

        const diag = recordData.diagnosis || recordData.title || recordData.subtitle || 'Dental Consultation & Prescription';
        const docName = recordData.doctor_name || recordData.doctorName || 'Attending Dentist';
        const clinicName = recordData.clinic_name || recordData.clinicName || 'DentaGuru Practice';
        const rxItems = recordData.prescriptions || recordData.items || recordData.details || [];

        const payload = {
            patient_id: targetPatientId,
            dentist_id: targetDentistId,
            diagnosis: diag,
            prescriptions: typeof rxItems === 'string' ? JSON.parse(rxItems) : rxItems,
            notes: JSON.stringify({
                type: recordData.type || 'prescription',
                title: recordData.title || 'Digital Prescription Slip',
                subtitle: recordData.subtitle || diag,
                doctor_name: docName,
                clinic_name: clinicName
            })
        };

        const { data, error } = await supabaseAdmin.from('medical_records').insert(payload).select().single();
        if (error) {
            console.error('❌ Supabase MedicalRecord Insert Error:', error.message);
            throw error;
        }
        return data;
    },

    async find(query = {}) {
        let req = supabaseAdmin.from('medical_records').select('*');
        const pId = query.patient_id || query.patientId;
        if (pId) {
            const resolvedP = await resolveUserUuid(pId);
            if (Array.isArray(resolvedP) && resolvedP.length > 0) {
                req = req.in('patient_id', resolvedP);
            } else if (typeof resolvedP === 'string' && resolvedP.length > 0) {
                req = req.eq('patient_id', resolvedP);
            }
        }
        const { data, error } = await req.order('created_at', { ascending: false });
        if (error) throw error;
        return data || [];
    }
};

// 6. CHAT MESSAGE MODEL (Supabase PostgreSQL)
const ChatMessage = {
    async create(messageData) {
        const rawSender = messageData.sender_id || messageData.senderId || '';
        let senderId = null;

        if (rawSender) {
            const str = String(rawSender).trim();
            if (isUUID(str)) {
                senderId = str;
            } else {
                let user = await User.findOne({ email: str }) || await User.findOne({ name: str });
                if (!user) {
                    const lower = str.toLowerCase();
                    if (lower.includes('doctor') || lower.includes('dentist') || lower.includes('dr')) {
                        user = await User.findOne({ role: 'Dentist' });
                    } else {
                        user = await User.findOne({ role: 'Patient' });
                    }
                }
                if (user) senderId = user.id;
            }
        }

        if (!senderId) {
            senderId = await resolveUserUuid(rawSender);
        }

        const receiverId = await resolveUserUuid(messageData.receiver_id || messageData.receiverId);

        const payload = {
            room_id: messageData.room_id || messageData.roomId || 'GENERAL-CHAT',
            sender_id: senderId,
            receiver_id: receiverId,
            message: messageData.message || '',
            type: messageData.type || 'text',
            read: messageData.read ?? false
        };

        const { data, error } = await supabaseAdmin.from('chat_messages').insert(payload).select().single();
        if (error) {
            console.error('❌ Supabase ChatMessage Insert Error:', error.message);
            throw error;
        }
        return data;
    },

    async find(query = {}) {
        let req = supabaseAdmin.from('chat_messages').select('*, sender:users!sender_id(name, email, role)');
        if (query.room_id || query.roomId) {
            req = req.eq('room_id', query.room_id || query.roomId);
        }
        const sId = query.sender_id || query.senderId;
        if (sId) {
            const resolvedS = await resolveUserUuid(sId);
            if (typeof resolvedS === 'string' && resolvedS.length > 0) req = req.eq('sender_id', resolvedS);
        }
        const { data, error } = await req.order('created_at', { ascending: true });
        if (error) throw error;
        return data || [];
    },

    async delete(query = {}) {
        let req = supabaseAdmin.from('chat_messages').delete();
        if (query.messageId || query.id) {
            req = req.eq('id', query.messageId || query.id);
        } else if (query.roomId || query.room_id) {
            req = req.eq('room_id', query.roomId || query.room_id);
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
        const payload = {
            patient_id: patientId,
            problem_category: reqData.problem_category || reqData.problemCategory || 'General Dental Problem',
            problem_description: reqData.problem_description || reqData.problemDescription || '',
            symptoms: reqData.symptoms || '',
            preferred_location: reqData.preferred_location || reqData.preferredLocation || null,
            attachments: reqData.attachments || [],
            status: reqData.status || 'PENDING_ADMIN_REVIEW',
            admin_notes: reqData.admin_notes || reqData.adminNotes || null
        };
        const { data, error } = await supabaseAdmin.from('patient_problem_requests').insert(payload).select().single();
        if (error) {
            console.error('❌ Supabase PatientProblemRequest Insert Error:', error.message);
            throw error;
        }
        return data;
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
            }
        }
        const { data, error } = await req.order('created_at', { ascending: false });
        if (error) {
            console.warn('⚠️ Problem requests query error, falling back to simple select:', error.message);
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
            type: notifData.type || 'general',
            read: notifData.read ?? false
        };
        const { data, error } = await supabaseAdmin.from('notifications').insert(payload).select().single();
        if (error) {
            console.error('❌ Supabase Notification Insert Error:', error.message);
            throw error;
        }
        return data;
    },

    async find(query = {}) {
        let req = supabaseAdmin.from('notifications').select('*');
        if (query.recipient_role || query.recipientRole) {
            req = req.eq('recipient_role', query.recipient_role || query.recipientRole);
        }
        if (query.recipient_id || query.recipientId) {
            req = req.or(`recipient_id.eq.${query.recipient_id || query.recipientId},recipient_id.eq.ALL`);
        }
        const { data, error } = await req.order('created_at', { ascending: false });
        if (error) throw error;
        return data || [];
    },

    async markAsRead(id) {
        const { data, error } = await supabaseAdmin.from('notifications').update({ read: true }).eq('id', id).select().single();
        if (error) throw error;
        return data;
    }
};

module.exports = {
    User,
    Clinic,
    Dentist,
    Appointment,
    MedicalRecord,
    ChatMessage,
    PatientProblemRequest,
    DentistSuggestion,
    Notification,
    comparePassword
};

