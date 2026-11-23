// Comprehensive Backend Integration Verification for Admin Dashboard Fixes (Tasks 2, 3, 5, 6)
// Runs against Express app routes with isolated in-memory Schemas/Supabase stubs.

const assert = require('assert');
const http = require('http');
const path = require('path');
const jwt = require('jsonwebtoken');
require('dotenv').config({ path: path.join(__dirname, '../.env') });

const Schemas = require('../src/models/Schemas');
const supabaseCfg = require('../src/config/supabase');
const clinicController = require('../src/controllers/clinicController');
const { otpStoreService } = require('../src/services/otpStoreService');
const { getJwtSecret } = require('../src/config/secrets');
const app = require('../src/app');

function httpRequest(port, method, path, headers = {}, body = null) {
    return new Promise((resolve, reject) => {
        const reqHeaders = { ...headers };
        let payload = null;
        if (body !== null) {
            payload = JSON.stringify(body);
            reqHeaders['Content-Type'] = 'application/json';
            reqHeaders['Content-Length'] = Buffer.byteLength(payload);
        }
        const req = http.request({ hostname: '127.0.0.1', port, path, method, headers: reqHeaders }, (res) => {
            let data = '';
            res.on('data', chunk => { data += chunk; });
            res.on('end', () => {
                let json = {};
                try { json = JSON.parse(data); } catch (_) { json = { raw: data }; }
                resolve({ status: res.statusCode, body: json });
            });
        });
        req.on('error', reject);
        if (payload !== null) req.write(payload);
        req.end();
    });
}

(async () => {
    console.log('--- STARTING ADMIN DASHBOARD COMPLETE FIXES BACKEND SUITE ---');

    const secret = getJwtSecret();

    const mainAdmin = {
        id: '10000000-0000-4000-8000-000000000001',
        name: 'GS Health Admin',
        email: 'admin@gshealth.in',
        phone: '9281030535',
        role: 'Admin',
        status: 'ACTIVE',
        password: 'AdminPassword123!'
    };

    const subAdmin = {
        id: '20000000-0000-4000-8000-000000000002',
        name: 'Nikhil SubAdmin',
        email: 'nikhil@gshealth.in',
        phone: '+919063663181',
        role: 'Sub-Admin',
        status: 'ACTIVE',
        password: 'SubAdminPassword123!',
        permissions: ['PATIENT_VIEW', 'DENTIST_VIEW'],
        assignedDistricts: [{ id: 'dist-1', name: 'Hyderabad' }],
        refresh_tokens: [],
        device_token: JSON.stringify({ status: 'ACTIVE', permissions: ['PATIENT_VIEW', 'DENTIST_VIEW'] })
    };

    const patientAnu = {
        id: '30000000-0000-4000-8000-000000000003',
        name: 'Anu',
        email: 'anu@patient.test',
        phone: '9063663170',
        role: 'Patient',
        status: 'ACTIVE',
        password: 'PatientPassword1!'
    };

    const doctorRohithaUser = {
        id: '40000000-0000-4000-8000-000000000004',
        name: 'Dr. Rohitha',
        email: 'rohitha@doctor.test',
        phone: '8986754323',
        role: 'Dentist',
        status: 'ACTIVE',
        password: 'DocPassword1!'
    };

    const doctorOtherUser = {
        id: '50000000-0000-4000-8000-000000000005',
        name: 'Dr. Arjun',
        email: 'arjun@doctor.test',
        phone: '8986754329',
        role: 'Dentist',
        status: 'ACTIVE',
        password: 'DocPassword2!'
    };

    const clinicUser = {
        id: '60000000-0000-4000-8000-000000000006',
        name: 'Devi Clinic Admin',
        email: 'devi@clinic.test',
        phone: '8985732915',
        role: 'Clinic',
        status: 'ACTIVE',
        password: 'ClinicPassword1!'
    };

    const clinicDevi = {
        id: '70000000-0000-4000-8000-000000000007',
        user_id: clinicUser.id,
        clinic_name: 'Devi Multi-Specialty Clinic',
        location: 'Kompally, Hyderabad',
        phone: '8985732915',
        email: 'devi@clinic.test',
        services: ['Dermatology', 'Cardiology', 'General Medicine']
    };

    const dentistRohitha = {
        id: '80000000-0000-4000-8000-000000000008',
        user_id: doctorRohithaUser.id,
        clinic_id: clinicDevi.id,
        speciality: 'Dermatology',
        qualifications: 'MBBS, MD Dermatology',
        experience_years: 7,
        availability_status: 'Available',
        users: doctorRohithaUser,
        clinics: clinicDevi
    };

    const dentistArjun = {
        id: '90000000-0000-4000-8000-000000000009',
        user_id: doctorOtherUser.id,
        clinic_id: clinicDevi.id,
        speciality: 'Cardiology',
        qualifications: 'MBBS, DM Cardiology',
        experience_years: 10,
        availability_status: 'Unavailable',
        users: doctorOtherUser,
        clinics: clinicDevi
    };

    const usersList = [mainAdmin, subAdmin, patientAnu, doctorRohithaUser, doctorOtherUser, clinicUser];
    const clinicsList = [clinicDevi];
    const dentistsList = [dentistRohitha, dentistArjun];
    const chatMessages = [];
    const auditLogs = [];
    const memoryOtps = new Map();

    // Save originals to restore cleanly
    const origUser = { ...Schemas.User };
    const origClinic = { ...Schemas.Clinic };
    const origDentist = { ...Schemas.Dentist };
    const origChat = { ...Schemas.ChatMessage };
    const origAudit = { ...Schemas.AuditLog };
    const origPerms = { ...Schemas.SubAdminPermission };
    const origDists = { ...Schemas.SubAdminDistrict };
    const origHist = { ...Schemas.PatientAssignmentHistory };
    const origResolveClinic = clinicController.resolveClinicRecordAndDoctorIds;
    const origResolveIds = Schemas.resolveClinicIds;
    const origSupaFrom = supabaseCfg.supabaseAdmin.from;
    const origOtpReq = otpStoreService.requestAndStoreOtp;
    const origOtpVerify = otpStoreService.verifyOtp;

    try {
        Schemas.User.find = async () => usersList.map(u => ({ ...u }));
        Schemas.User.findById = async (id) => {
            const u = usersList.find(x => x.id === id);
            return u ? { ...u } : null;
        };
        Schemas.User.findOne = async (q = {}) => {
            const u = usersList.find(x => {
                if (q.id && x.id !== q.id) return false;
                if (q.email && String(x.email || '').toLowerCase() !== String(q.email).toLowerCase()) return false;
                if (q.phone && String(x.phone || '') !== String(q.phone)) return false;
                return true;
            });
            return u ? { ...u } : null;
        };
        Schemas.User.findByMobile = async (raw) => {
            const digits = String(raw || '').replace(/[^0-9]/g, '');
            const last10 = digits.length >= 10 ? digits.slice(-10) : digits;
            const u = usersList.find(x => {
                const xd = String(x.phone || '').replace(/[^0-9]/g, '');
                return xd.length >= 10 && xd.slice(-10) === last10;
            });
            return u ? { ...u } : null;
        };
        Schemas.User.findByIdAndUpdate = async (id, patch = {}) => {
            const u = usersList.find(x => x.id === id);
            if (!u) return null;
            Object.assign(u, patch);
            let meta = {};
            try { meta = JSON.parse(u.device_token || '{}'); } catch (_) {}
            if (patch.status) meta.status = patch.status;
            if (patch.status === 'INACTIVE') meta.revokedBefore = Date.now() + 10000;
            if (patch.status === 'ACTIVE') delete meta.revokedBefore;
            u.device_token = JSON.stringify(meta);
            return { ...u };
        };

        Schemas.SubAdminPermission.getPermissionsForUser = async (uid) => {
            const u = usersList.find(x => x.id === uid);
            return u?.permissions || [];
        };
        Schemas.SubAdminDistrict.getDistrictsForSubAdmin = async (uid) => {
            const u = usersList.find(x => x.id === uid);
            return u?.assignedDistricts || [];
        };
        Schemas.PatientAssignmentHistory.getHistory = async () => [];

        Schemas.Clinic.find = async () => clinicsList.map(c => ({ ...c }));
        Schemas.Clinic.findById = async (id) => clinicsList.find(c => c.id === id) || null;
        Schemas.Clinic.findOne = async (q = {}) => clinicsList.find(c =>
            (q.id && c.id === q.id) || (q.user_id && c.user_id === q.user_id) || (q.clinic_name && c.clinic_name === q.clinic_name)
        ) || null;

        Schemas.Dentist.find = async (q = {}) => {
            if (q.clinic_id) {
                return dentistsList.filter(d => d.clinic_id === q.clinic_id).map(d => ({ ...d }));
            }
            return dentistsList.map(d => ({ ...d }));
        };
        Schemas.Dentist.findById = async (id) => dentistsList.find(d => d.id === id || d.user_id === id) || null;
        Schemas.Dentist.findOne = async (q = {}) => dentistsList.find(d => q.user_id ? d.user_id === q.user_id : false) || null;
        Schemas.Dentist.findByIdAndUpdate = async (id, patch = {}) => {
            const d = dentistsList.find(x => x.id === id || x.user_id === id);
            if (!d) return null;
            Object.assign(d, patch);
            return { ...d };
        };

        Schemas.AuditLog.create = async (entry) => {
            auditLogs.push({ id: `audit-${auditLogs.length + 1}`, ...entry });
            return entry;
        };
        Schemas.AuditLog.find = async () => [...auditLogs];

        Schemas.ChatMessage.create = async (msg) => {
            const text = String(msg.message || '').trim();
            if (!text) throw new Error('Message text cannot be empty.');
            const now = Date.now();
            const dup = chatMessages.find(m =>
                m.room_id === msg.room_id &&
                m.sender_id === msg.sender_id &&
                m.message === text &&
                (now - new Date(m.created_at).getTime()) < 3000
            );
            if (dup) return dup;
            const senderObj = usersList.find(u => u.id === msg.sender_id) || null;
            const row = {
                id: `msg-${chatMessages.length + 1}`,
                room_id: msg.room_id,
                sender_id: msg.sender_id,
                receiver_id: msg.receiver_id || null,
                message: text,
                type: msg.type || 'text',
                read: false,
                created_at: new Date().toISOString(),
                sender: senderObj ? { id: senderObj.id, name: senderObj.name, email: senderObj.email, role: senderObj.role } : null
            };
            chatMessages.push(row);
            return row;
        };
        Schemas.ChatMessage.find = async (q = {}, opts = {}) => {
            if (opts.user && String(opts.user.role || '').toLowerCase().includes('sub')) return [];
            const r = q.room_id || q.roomId;
            if (r) return chatMessages.filter(m => m.room_id === r);
            return [...chatMessages];
        };
        Schemas.ChatMessage.markAsRead = async ({ roomId, userId }) => {
            let count = 0;
            for (const m of chatMessages) {
                if (m.room_id === roomId && !m.read && m.sender_id !== userId) {
                    m.read = true;
                    count++;
                }
            }
            return count;
        };
        Schemas.ChatMessage.getConversations = async (user) => {
            if (String(user?.role || '').toLowerCase().includes('sub')) return [];
            const map = new Map();
            for (const m of chatMessages) {
                if (!map.has(m.room_id)) {
                    map.set(m.room_id, {
                        roomId: m.room_id,
                        patientName: 'Anu',
                        doctorName: 'Dr. Rohitha',
                        lastMessage: m.message,
                        lastMessageTime: m.created_at,
                        totalMessages: 0,
                        unreadCount: 0
                    });
                }
                const c = map.get(m.room_id);
                c.totalMessages += 1;
                if (!m.read && m.sender_id !== user?.id) c.unreadCount += 1;
                c.lastMessage = m.message;
            }
            return Array.from(map.values());
        };
        Schemas.ChatMessage.delete = async ({ roomId }) => {
            for (let i = chatMessages.length - 1; i >= 0; i--) {
                if (chatMessages[i].room_id === roomId) chatMessages.splice(i, 1);
            }
            return true;
        };

        clinicController.resolveClinicRecordAndDoctorIds = async (rawId) => {
            const c = clinicsList.find(x => x.id === rawId || x.user_id === rawId || x.clinic_name === rawId) || null;
            const docs = c ? dentistsList.filter(d => d.clinic_id === c.id).flatMap(d => [d.id, d.user_id]) : [];
            return { clinic: c, clinicId: c?.id || null, clinicUserId: c?.user_id || null, clinicName: c?.clinic_name || '', allClinicIds: c ? [c.id, c.user_id] : [], doctorIds: docs };
        };

        // Stub supabaseAdmin.from for requireChatAccess Doctor/Clinic checks
        supabaseCfg.supabaseAdmin.from = (table) => {
            const chain = {
                _ids: null,
                _clinicId: null,
                _orFilter: '',
                select() { return chain; },
                or(expr) { chain._orFilter = String(expr || ''); return chain; },
                eq(col, val) {
                    if (table === 'dentists' && col === 'clinic_id') chain._clinicId = val;
                    return chain;
                },
                in(col, vals) { chain._ids = vals; return chain; },
                async maybeSingle() {
                    if (table === 'dentists') {
                        const matched = dentistsList.find(d =>
                            chain._orFilter.includes(d.id) || chain._orFilter.includes(d.user_id)
                        ) || null;
                        return { data: matched, error: null };
                    }
                    return { data: null, error: null };
                },
                then(resolve) {
                    if (table === 'patient_problem_requests') {
                        const isRohitha = chain._ids && (chain._ids.includes(dentistRohitha.id) || chain._ids.includes(doctorRohithaUser.id));
                        return resolve({
                            data: isRohitha ? [{ id: 'req-1', patient_name: 'Anu', patient_id: patientAnu.id, suggested_dentist_id: dentistRohitha.id }] : [],
                            error: null
                        });
                    }
                    if (table === 'appointments' || table === 'referrals') {
                        return resolve({ data: [], error: null });
                    }
                    if (table === 'dentists' && chain._clinicId) {
                        return resolve({ data: dentistsList.filter(d => d.clinic_id === chain._clinicId), error: null });
                    }
                    return resolve({ data: [], error: null });
                }
            };
            return chain;
        };

        otpStoreService.requestAndStoreOtp = async (phone, code) => {
            memoryOtps.set(phone.replace(/[^0-9]/g, '').slice(-10), code);
            return { allowed: true };
        };
        otpStoreService.verifyOtp = async (key, code) => {
            const last10 = String(key || '').replace(/[^0-9]/g, '').slice(-10);
            const expected = memoryOtps.get(last10);
            return { valid: Boolean(expected && String(code).trim() === expected), message: expected ? 'OK' : 'Invalid or expired OTP.' };
        };

        const server = http.createServer(app);
        await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
        const { port } = server.address();

        try {
            const adminToken = jwt.sign({ id: mainAdmin.id, role: 'Admin', email: mainAdmin.email }, secret, { expiresIn: '1h' });
            const patientToken = jwt.sign({ id: patientAnu.id, role: 'Patient', email: patientAnu.email }, secret, { expiresIn: '1h' });
            const rohithaToken = jwt.sign({ id: doctorRohithaUser.id, role: 'Dentist', email: doctorRohithaUser.email }, secret, { expiresIn: '1h' });
            const arjunToken = jwt.sign({ id: doctorOtherUser.id, role: 'Dentist', email: doctorOtherUser.email }, secret, { expiresIn: '1h' });

            // ─── TEST 1: TASK 6 — SUB-ADMIN MOBILE + OTP LOGIN ───
            console.log('1️⃣ Testing Sub-Admin registered mobile login + OTP verification...');
            const otpReqRes = await httpRequest(port, 'POST', '/api/v1/auth/otp/request', {}, { phone: '9063663181' });
            assert.strictEqual(otpReqRes.status, 200);
            const sentOtp = memoryOtps.get('9063663181');
            assert.ok(sentOtp, 'OTP should be stored for 9063663181');

            const otpVerifyRes = await httpRequest(port, 'POST', '/api/v1/auth/otp/verify', {}, { phone: '+91 9063663181', code: sentOtp });
            assert.strictEqual(otpVerifyRes.status, 200, `Expected 200 for active Sub-Admin OTP login, got ${otpVerifyRes.status}: ${JSON.stringify(otpVerifyRes.body)}`);
            assert.strictEqual(otpVerifyRes.body.user.role, 'Sub-Admin');
            assert.strictEqual(otpVerifyRes.body.user.status, 'ACTIVE');
            assert.ok(otpVerifyRes.body.accessToken, 'Active Sub-Admin should receive JWT accessToken');
            assert.deepStrictEqual(otpVerifyRes.body.user.permissions, ['PATIENT_VIEW', 'DENTIST_VIEW']);
            assert.strictEqual(otpVerifyRes.body.user.assignedDistricts.length, 1);

            const subAdminToken = otpVerifyRes.body.accessToken;

            // Patient trying Admin login still strictly blocked
            const patientAdminLogin = await httpRequest(port, 'POST', '/api/v1/auth/login', {}, { phone: patientAnu.phone, password: patientAnu.password, role: 'Admin' });
            assert.strictEqual(patientAdminLogin.status, 403, 'Patient must not be permitted into Admin portal');

            // ─── TEST 2: TASK 5 — SUB-ADMIN ACTIVE / DEACTIVE TOGGLE & SESSION BLOCKING ───
            console.log('2️⃣ Testing Sub-Admin Deactivation, Persistence, Session Block & Reactivation...');
            const deactRes = await httpRequest(port, 'PATCH', `/api/v1/admin/sub-admins/${subAdmin.id}/status`, { Authorization: `Bearer ${adminToken}` }, { status: 'INACTIVE' });
            assert.strictEqual(deactRes.status, 200);
            assert.strictEqual(deactRes.body.subAdmin.status, 'INACTIVE');
            assert.ok(deactRes.body.subAdmin.updated_at);
            assert.strictEqual(deactRes.body.subAdmin.updated_by, mainAdmin.id);

            const listRes = await httpRequest(port, 'GET', '/api/v1/admin/sub-admins', { Authorization: `Bearer ${adminToken}` });
            assert.strictEqual(listRes.status, 200);
            const listedSa = listRes.body.subAdmins.find(s => s.id === subAdmin.id);
            assert.strictEqual(listedSa.status, 'INACTIVE', 'Deactivated status must persist across reloads');

            // Previously issued Sub-Admin JWT is immediately blocked
            const blockedSessionRes = await httpRequest(port, 'GET', '/api/v1/dentists', { Authorization: `Bearer ${subAdminToken}` });
            assert.strictEqual(blockedSessionRes.status, 403, 'Deactivated Sub-Admin token must be blocked immediately');
            assert.strictEqual(blockedSessionRes.body.code, 'ACCOUNT_DEACTIVATED');

            // Password & OTP login blocked for deactivated Sub-Admin
            const blockedPassRes = await httpRequest(port, 'POST', '/api/v1/auth/login', {}, { phone: '9063663181', password: subAdmin.password, role: 'Sub-Admin' });
            assert.strictEqual(blockedPassRes.status, 403);
            assert.strictEqual(blockedPassRes.body.code, 'ACCOUNT_DEACTIVATED');

            await httpRequest(port, 'POST', '/api/v1/auth/otp/request', {}, { phone: '9063663181' });
            const blockedOtpRes = await httpRequest(port, 'POST', '/api/v1/auth/otp/verify', {}, { phone: '9063663181', code: memoryOtps.get('9063663181') });
            assert.strictEqual(blockedOtpRes.status, 403);
            assert.strictEqual(blockedOtpRes.body.code, 'ACCOUNT_DEACTIVATED');

            // Reactivate restores login
            const reactRes = await httpRequest(port, 'PATCH', `/api/v1/admin/sub-admins/${subAdmin.id}/status`, { Authorization: `Bearer ${adminToken}` }, { status: 'ACTIVE' });
            assert.strictEqual(reactRes.status, 200);
            assert.strictEqual(reactRes.body.subAdmin.status, 'ACTIVE');
            const reactLoginRes = await httpRequest(port, 'POST', '/api/v1/auth/login', {}, { phone: '9063663181', password: subAdmin.password, role: 'Sub-Admin' });
            assert.strictEqual(reactLoginRes.status, 200, 'Reactivated Sub-Admin must be able to sign in again');

            // ─── TEST 3: TASK 2 — CHAT FUNCTIONALITY, DEDUP, MARK READ & STRICT RBAC ───
            console.log('3️⃣ Testing Chat persistence, dedup, read status & RBAC...');
            const roomId = 'PATIENT_ANU';

            const blankChat = await httpRequest(port, 'POST', '/api/v1/chat/send', { Authorization: `Bearer ${patientToken}` }, { roomId, message: '   ' });
            assert.strictEqual(blankChat.status, 400, 'Empty messages must be rejected with 400');

            const pSend = await httpRequest(port, 'POST', '/api/v1/chat/send', { Authorization: `Bearer ${patientToken}` }, { roomId, receiverId: doctorRohithaUser.id, message: 'Hello Doctor, rash checkup needed', type: 'patient' });
            assert.strictEqual(pSend.status, 201);

            // Rapid duplicate prevention
            await httpRequest(port, 'POST', '/api/v1/chat/send', { Authorization: `Bearer ${patientToken}` }, { roomId, receiverId: doctorRohithaUser.id, message: 'Hello Doctor, rash checkup needed', type: 'patient' });
            assert.strictEqual(chatMessages.length, 1, 'Duplicate rapid identical messages must not create 2 rows');

            // Assigned doctor fetches messages & marks read
            const dMsgs = await httpRequest(port, 'GET', `/api/v1/chat/messages?roomId=${roomId}&markRead=true`, { Authorization: `Bearer ${rohithaToken}` });
            assert.strictEqual(dMsgs.status, 200);
            assert.strictEqual(dMsgs.body.messages.length, 1);
            assert.strictEqual(chatMessages[0].read, true, 'Message must be marked read when recipient reads room');

            // Unassigned doctor (Dr. Arjun) must be denied (403)
            const otherDocMsgs = await httpRequest(port, 'GET', `/api/v1/chat/messages?roomId=${roomId}`, { Authorization: `Bearer ${arjunToken}` });
            assert.strictEqual(otherDocMsgs.status, 403, 'Unrelated doctor must get 403 Forbidden on patient room');

            // Sub-Admin must get 403 on all chat endpoints
            const saConvRes = await httpRequest(port, 'GET', '/api/v1/chat/conversations', { Authorization: `Bearer ${reactLoginRes.body.accessToken}` });
            assert.strictEqual(saConvRes.status, 403, 'Sub-Admin must strictly get 403 on chat conversations');
            const saSendRes = await httpRequest(port, 'POST', '/api/v1/chat/send', { Authorization: `Bearer ${reactLoginRes.body.accessToken}` }, { roomId, message: 'Hi' });
            assert.strictEqual(saSendRes.status, 403, 'Sub-Admin must strictly get 403 on chat send');

            // Main Admin inspects & audit log recorded
            const adminMsgs = await httpRequest(port, 'GET', `/api/v1/chat/messages?roomId=${roomId}`, { Authorization: `Bearer ${adminToken}` });
            assert.strictEqual(adminMsgs.status, 200);
            assert.ok(auditLogs.some(l => l.action === 'ADMIN_CHAT_MESSAGES_VIEW' && l.target_resource === roomId));

            // ─── TEST 4: TASK 3 — CLINICS & REGISTERED DOCTORS ───
            console.log('4️⃣ Testing Clinic Registered Doctors listing & non-destructive removal...');
            const clinicDocsRes = await httpRequest(port, 'GET', `/api/v1/clinics/${clinicDevi.id}/doctors?includeUnavailable=true`, { Authorization: `Bearer ${adminToken}` });
            assert.strictEqual(clinicDocsRes.status, 200);
            assert.strictEqual(clinicDocsRes.body.doctors.length, 2, 'Should show both Dr. Rohitha (Available) & Dr. Arjun (Unavailable) registered to Devi Clinic');
            const rDoc = clinicDocsRes.body.doctors.find(d => d.name.includes('Rohitha'));
            const aDoc = clinicDocsRes.body.doctors.find(d => d.name.includes('Arjun'));
            assert.strictEqual(rDoc.isAvailable, true);
            assert.strictEqual(rDoc.specialty, 'Dermatology');
            assert.strictEqual(aDoc.isAvailable, false);
            assert.strictEqual(aDoc.availability_status, 'Unavailable');

            // Non-destructive remove preserves global dentist row
            const remDocRes = await httpRequest(port, 'DELETE', `/api/v1/clinics/${clinicDevi.id}/doctors/${dentistArjun.id}`, { Authorization: `Bearer ${adminToken}` });
            assert.strictEqual(remDocRes.status, 200);
            assert.strictEqual(dentistArjun.clinic_id, null, 'Doctor clinic_id cleared without deleting global record');
            assert.strictEqual(dentistsList.length, 2, 'Global doctors directory still has both doctors');

            console.log('✅ ALL ADMIN DASHBOARD FIXES BACKEND TESTS PASSED!');
        } finally {
            server.close();
        }
    } finally {
        Object.assign(Schemas.User, origUser);
        Object.assign(Schemas.Clinic, origClinic);
        Object.assign(Schemas.Dentist, origDentist);
        Object.assign(Schemas.ChatMessage, origChat);
        Object.assign(Schemas.AuditLog, origAudit);
        Object.assign(Schemas.SubAdminPermission, origPerms);
        Object.assign(Schemas.SubAdminDistrict, origDists);
        Object.assign(Schemas.PatientAssignmentHistory, origHist);
        clinicController.resolveClinicRecordAndDoctorIds = origResolveClinic;
        Schemas.resolveClinicIds = origResolveIds;
        supabaseCfg.supabaseAdmin.from = origSupaFrom;
        otpStoreService.requestAndStoreOtp = origOtpReq;
        otpStoreService.verifyOtp = origOtpVerify;
    }
})();
