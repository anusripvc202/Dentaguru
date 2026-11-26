// Offline Phase 2B Chat Authorization, Role Fail-Closed & Read-Receipt Test Suite
// Runs strictly against Express routes with isolated in-memory Supabase/model stubs (zero network/SQL execution).

const assert = require('assert');
const fs = require('fs');
const http = require('http');
const path = require('path');
const crypto = require('crypto');
const jwt = require('jsonwebtoken');
require('dotenv').config({ path: path.join(__dirname, '../.env') });

const Schemas = require('../src/models/Schemas');
const supabaseCfg = require('../src/config/supabase');
const { getJwtSecret, getRefreshSecret, hasSupabaseJwtSecret } = require('../src/config/secrets');
const { mintSupabaseRealtimeTokenForUser, tryMintSupabaseRealtimeTokenForUser, verifySupabaseRealtimeToken } = require('../src/services/realtimeTokenService');
const { hashOtp } = require('../src/services/otpStoreService');
const app = require('../src/app');

function httpRequest(port, method, reqPath, headers = {}, body = null) {
    return new Promise((resolve, reject) => {
        const reqHeaders = { ...headers };
        let payload = null;
        if (body !== null) {
            payload = JSON.stringify(body);
            reqHeaders['Content-Type'] = 'application/json';
            reqHeaders['Content-Length'] = Buffer.byteLength(payload);
        }
        const req = http.request(
            { hostname: '127.0.0.1', port, path: reqPath, method, headers: reqHeaders },
            (res) => {
                let data = '';
                res.on('data', (chunk) => { data += chunk; });
                res.on('end', () => {
                    let json = {};
                    try { json = JSON.parse(data); } catch (_) { json = { raw: data }; }
                    resolve({ status: res.statusCode, body: json });
                });
            }
        );
        req.on('error', reject);
        if (payload !== null) req.write(payload);
        req.end();
    });
}

(async () => {
    console.log('--- STARTING PHASE 2B CHAT AUTHORIZATION & READ-RECEIPT SECURITY SUITE ---');

    const secret = getJwtSecret();

    const IDS = {
        mainAdmin: '10000000-0000-4000-8000-000000000001',
        subAdmin: '20000000-0000-4000-8000-000000000002',
        patientAnu: '30000000-0000-4000-8000-000000000003',
        patientAnusha: '30000000-0000-4000-8000-000000000099',
        patientStranger: '30000000-0000-4000-8000-000000000088',
        doctorAssigned: '40000000-0000-4000-8000-000000000004',
        doctorOther: '50000000-0000-4000-8000-000000000005',
        clinicUser: '60000000-0000-4000-8000-000000000006',
        clinicRecord: '70000000-0000-4000-8000-000000000007',
        dentistAssigned: '80000000-0000-4000-8000-000000000008',
        dentistOther: '90000000-0000-4000-8000-000000000009',
        clinicOtherUser: '60000000-0000-4000-8000-000000000066',
        clinicOtherRec: '70000000-0000-4000-8000-000000000077',
        unknownRoleUser: 'a0000000-0000-4000-8000-000000000010',
        missingRoleUser: 'a0000000-0000-4000-8000-000000000011',
        inactiveUser: 'a0000000-0000-4000-8000-000000000012',
        nullStatusUser: 'a0000000-0000-4000-8000-000000000013',
        convAnuDoc: 'c0000000-0000-4000-8000-000000000001',
        convStranger: 'c0000000-0000-4000-8000-000000000002',
        convClosed: 'c0000000-0000-4000-8000-000000000003',
        convBlocked: 'c0000000-0000-4000-8000-000000000004',
        convSharedRoomB: 'c0000000-0000-4000-8000-000000000005',
    };

    const usersList = [
        { id: IDS.mainAdmin, name: 'Main Admin', email: 'admin@gshealth.in', role: 'Admin', status: 'ACTIVE' },
        { id: IDS.subAdmin, name: 'Regional Sub', email: 'sub@gshealth.in', role: 'Sub-Admin', status: 'ACTIVE', permissions: ['*'] },
        { id: IDS.patientAnu, name: 'Anu', email: 'anu@patient.test', role: 'Patient', status: 'ACTIVE' },
        { id: IDS.patientAnusha, name: 'Anusha', email: 'anusha@patient.test', role: 'Patient', status: 'ACTIVE' },
        { id: IDS.patientStranger, name: 'Stranger Pat', email: 'stranger@patient.test', role: 'Patient', status: 'ACTIVE' },
        { id: IDS.doctorAssigned, name: 'Dr. Rohitha', email: 'rohitha@doctor.test', role: 'Dentist', status: 'ACTIVE' },
        { id: IDS.doctorOther, name: 'Dr. Arjun', email: 'arjun@doctor.test', role: 'Dentist', status: 'ACTIVE' },
        { id: IDS.clinicUser, name: 'Devi Clinic', email: 'devi@clinic.test', role: 'Clinic', status: 'ACTIVE' },
        { id: IDS.clinicOtherUser, name: 'Apollo Clinic', email: 'apollo@clinic.test', role: 'Clinic', status: 'ACTIVE' },
        { id: IDS.unknownRoleUser, name: 'External Guest', email: 'guest@external.test', role: 'superguest', status: 'ACTIVE' },
        { id: IDS.missingRoleUser, name: 'NoRole Account', email: 'norole@external.test', role: '', status: 'ACTIVE' },
        { id: IDS.inactiveUser, name: 'Inactive User', email: 'inactive@patient.test', role: 'Patient', status: 'INACTIVE' },
        { id: IDS.nullStatusUser, name: 'NullStatus Pat', email: 'nullstat@patient.test', role: 'Patient', status: null },
    ];

    const clinicsList = [
        { id: IDS.clinicRecord, user_id: IDS.clinicUser, clinic_name: 'Devi Clinic' },
        { id: IDS.clinicOtherRec, user_id: IDS.clinicOtherUser, clinic_name: 'Apollo Clinic' },
    ];

    const dentistsList = [
        { id: IDS.dentistAssigned, user_id: IDS.doctorAssigned, clinic_id: IDS.clinicRecord, speciality: 'Dermatology' },
        { id: IDS.dentistOther, user_id: IDS.doctorOther, clinic_id: IDS.clinicOtherRec, speciality: 'Cardiology' },
    ];

    const problemRequests = [
        { id: 'req-1', patient_id: IDS.patientAnu, patient_name: 'Anu', suggested_dentist_id: IDS.dentistAssigned, status: 'DENTIST_ASSIGNED' },
    ];
    const appointments = [
        { id: 'appt-1', patient_id: IDS.patientAnusha, dentist_id: IDS.dentistOther, status: 'Confirmed' },
    ];
    const conversations = [
        { id: IDS.convAnuDoc, conversation_type: 'PATIENT_DOCTOR', patient_id: IDS.patientAnu, dentist_id: IDS.dentistAssigned, clinic_id: IDS.clinicRecord, status: 'ACTIVE', legacy_room_id: 'PATIENT_ANU' },
        { id: IDS.convStranger, conversation_type: 'PATIENT_DOCTOR', patient_id: IDS.patientStranger, dentist_id: IDS.dentistOther, clinic_id: IDS.clinicOtherRec, status: 'ACTIVE', legacy_room_id: 'PATIENT_STRANGER_PAT' },
        { id: IDS.convClosed, conversation_type: 'PATIENT_DOCTOR', patient_id: IDS.patientAnu, dentist_id: IDS.dentistAssigned, clinic_id: IDS.clinicRecord, status: 'CLOSED', legacy_room_id: 'CONV_CLOSED_ANU' },
        { id: IDS.convBlocked, conversation_type: 'PATIENT_DOCTOR', patient_id: IDS.patientAnu, dentist_id: IDS.dentistAssigned, clinic_id: IDS.clinicRecord, status: 'BLOCKED', legacy_room_id: 'CONV_BLOCKED_ANU' },
        // Second conversation with an intentionally distinct conversation_id even if a message inside shares PATIENT_ANU room_id
        { id: IDS.convSharedRoomB, conversation_type: 'PATIENT_DOCTOR', patient_id: IDS.patientAnu, dentist_id: IDS.dentistAssigned, clinic_id: IDS.clinicRecord, status: 'ACTIVE', legacy_room_id: 'PATIENT_ANU_SECOND' },
    ];
    const participants = [
        { conversation_id: IDS.convAnuDoc, user_id: IDS.patientAnu, participant_role: 'PATIENT', is_active: true, can_send: true },
        { conversation_id: IDS.convAnuDoc, user_id: IDS.doctorAssigned, participant_role: 'DOCTOR', is_active: true, can_send: true },
        { conversation_id: IDS.convStranger, user_id: IDS.patientStranger, participant_role: 'PATIENT', is_active: true, can_send: true },
        { conversation_id: IDS.convStranger, user_id: IDS.doctorOther, participant_role: 'DOCTOR', is_active: true, can_send: true },
        { conversation_id: IDS.convClosed, user_id: IDS.patientAnu, participant_role: 'PATIENT', is_active: true, can_send: true },
        { conversation_id: IDS.convClosed, user_id: IDS.doctorAssigned, participant_role: 'DOCTOR', is_active: true, can_send: true },
        { conversation_id: IDS.convBlocked, user_id: IDS.patientAnu, participant_role: 'PATIENT', is_active: true, can_send: true },
        { conversation_id: IDS.convBlocked, user_id: IDS.doctorAssigned, participant_role: 'DOCTOR', is_active: true, can_send: true },
        { conversation_id: IDS.convSharedRoomB, user_id: IDS.patientAnu, participant_role: 'PATIENT', is_active: true, can_send: true },
        { conversation_id: IDS.convSharedRoomB, user_id: IDS.doctorAssigned, participant_role: 'DOCTOR', is_active: true, can_send: true },
    ];
    const chatMessages = [
        {
            id: '11111111-1111-4111-8111-000000000001',
            room_id: 'PATIENT_STRANGER_PAT',
            conversation_id: IDS.convStranger,
            sender_id: IDS.patientStranger,
            receiver_id: IDS.doctorOther,
            message: 'Private medical message of Stranger',
            type: 'patient',
            read: false,
            is_deleted: false,
            created_at: new Date(Date.now() - 60000).toISOString(),
            sender: usersList.find(u => u.id === IDS.patientStranger),
            receiver: usersList.find(u => u.id === IDS.doctorOther),
        },
        {
            id: '11111111-1111-4111-8111-000000000002',
            room_id: 'PATIENT_ANUSHA',
            conversation_id: null,
            sender_id: IDS.patientAnusha,
            receiver_id: IDS.doctorOther,
            message: 'Anusha private message',
            type: 'patient',
            read: false,
            is_deleted: false,
            created_at: new Date(Date.now() - 50000).toISOString(),
            sender: usersList.find(u => u.id === IDS.patientAnusha),
            receiver: usersList.find(u => u.id === IDS.doctorOther),
        },
        {
            // Seeded in a SECOND conversation whose room_id happens to collide with 'PATIENT_ANU'
            // to prove read receipts & retrieval filter strictly by exact conversation_id
            id: '11111111-1111-4111-8111-000000000003',
            room_id: 'PATIENT_ANU',
            conversation_id: IDS.convSharedRoomB,
            sender_id: IDS.patientAnu,
            receiver_id: IDS.doctorAssigned,
            message: 'Message inside convSharedRoomB',
            type: 'patient',
            read: false,
            is_deleted: false,
            created_at: new Date(Date.now() - 40000).toISOString(),
            sender: usersList.find(u => u.id === IDS.patientAnu),
            receiver: usersList.find(u => u.id === IDS.doctorAssigned),
        },
        {
            id: '11111111-1111-4111-8111-000000000004',
            room_id: 'CONV_CLOSED_ANU',
            conversation_id: IDS.convClosed,
            sender_id: IDS.patientAnu,
            receiver_id: IDS.doctorAssigned,
            message: 'Historical message in closed thread',
            type: 'patient',
            read: false,
            is_deleted: false,
            created_at: new Date(Date.now() - 30000).toISOString(),
            sender: usersList.find(u => u.id === IDS.patientAnu),
            receiver: usersList.find(u => u.id === IDS.doctorAssigned),
        },
    ];
    const auditLogs = [];

    const origUser = { ...Schemas.User };
    const origClinic = { ...Schemas.Clinic };
    const origDentist = { ...Schemas.Dentist };
    const origAudit = { ...Schemas.AuditLog };
    const origResolveClinic = Schemas.resolveClinicIds;
    const origHistory = { ...Schemas.PatientAssignmentHistory };
    const origReferral = { ...Schemas.Referral };
    const origPatDoc = { ...Schemas.PatientDoctor };
    const origSupaFrom = supabaseCfg.supabaseAdmin.from;

    try {
        Schemas.User.findById = async (id) => {
            const u = usersList.find(x => x.id === id);
            return u ? { ...u } : null;
        };
        Schemas.User.findOne = async (q = {}) => {
            const u = usersList.find(x =>
                (!q.id || x.id === q.id) &&
                (!q.email || String(x.email || '').toLowerCase() === String(q.email).toLowerCase())
            );
            return u ? { ...u } : null;
        };
        Schemas.Clinic.findById = async (id) => clinicsList.find(c => c.id === id) || null;
        Schemas.Clinic.findOne = async (q = {}) => clinicsList.find(c => (q.id && c.id === q.id) || (q.user_id && c.user_id === q.user_id)) || null;
        Schemas.Dentist.find = async (q = {}) => (q.clinic_id ? dentistsList.filter(d => d.clinic_id === q.clinic_id) : dentistsList).map(d => ({ ...d }));
        Schemas.Dentist.findById = async (id) => dentistsList.find(d => d.id === id || d.user_id === id) || null;
        Schemas.Dentist.findOne = async (q = {}) => dentistsList.find(d => q.user_id ? d.user_id === q.user_id : (q.id ? q.id === d.id : false)) || null;
        Schemas.AuditLog.create = async (entry) => { auditLogs.push(entry); return entry; };
        Schemas.PatientAssignmentHistory.getHistory = async () => [];
        Schemas.Referral.find = async () => [];
        Schemas.PatientDoctor.getDoctorsForPatient = async () => [];
        Schemas.resolveClinicIds = async (raw) => {
            const c = clinicsList.find(x => x.id === raw || x.user_id === raw);
            return c ? { clinicId: c.id, clinicUserId: c.user_id, allIds: [c.id, c.user_id] } : { clinicId: null, clinicUserId: null, allIds: [] };
        };

        // In-memory Supabase query builder for users/dentists/clinics/chat_messages/chat_conversations/chat_participants/requests/appointments
        supabaseCfg.supabaseAdmin.from = (table) => {
            const state = { filters: [], orExprs: [], inFilters: [], op: 'select', insertPayload: null, updatePatch: null };
            const applyFilter = (rows) => {
                let out = [...rows];
                for (const [col, val] of state.filters) {
                    out = out.filter(r => String(r[col] ?? '') === String(val));
                }
                for (const [col, vals] of state.inFilters) {
                    const set = new Set((vals || []).map(String));
                    out = out.filter(r => set.has(String(r[col] ?? '')));
                }
                for (const orExpr of state.orExprs) {
                    if (!orExpr) continue;
                    const parts = orExpr.split(',');
                    out = out.filter(r => parts.some(p => {
                        const m = p.match(/^([^.]+)\.eq\.(.+)$/);
                        if (m) return String(r[m[1]] ?? '').toUpperCase() === m[2].toUpperCase();
                        const neq = p.match(/^([^.]+)\.neq\.(.+)$/);
                        if (neq) return String(r[neq[1]] ?? '') !== neq[2];
                        const isNull = p.match(/^([^.]+)\.is\.null$/);
                        if (isNull) return r[isNull[1]] === null || r[isNull[1]] === undefined;
                        return false;
                    }));
                }
                return out;
            };
            const tableRows = () => {
                if (table === 'users') return usersList;
                if (table === 'dentists') return dentistsList.map(d => ({ ...d, users: usersList.find(u => u.id === d.user_id) || null }));
                if (table === 'clinics') return clinicsList;
                if (table === 'patient_problem_requests') return problemRequests;
                if (table === 'appointments') return appointments;
                if (table === 'chat_conversations') return conversations;
                if (table === 'chat_participants') return participants;
                if (table === 'chat_messages') return chatMessages;
                return [];
            };
            const chain = {
                select() { return chain; },
                eq(col, val) { state.filters.push([col, val]); return chain; },
                gte() { return chain; },
                lte(col, val) {
                    if (table === 'chat_messages') {
                        state._lteIso = val;
                    }
                    return chain;
                },
                in(col, vals) { state.inFilters.push([col, vals]); return chain; },
                or(expr) { state.orExprs.push(String(expr || '')); return chain; },
                order() { return chain; },
                limit() { return chain; },
                insert(payload) { state.op = 'insert'; state.insertPayload = payload; return chain; },
                update(patch) { state.op = 'update'; state.updatePatch = patch; return chain; },
                delete() { state.op = 'delete'; return chain; },
                async maybeSingle() {
                    const res = applyFilter(tableRows());
                    return { data: res[0] || null, error: null };
                },
                async single() {
                    const res = applyFilter(tableRows());
                    return { data: res[0] || null, error: null };
                },
                then(resolve) {
                    if (state.op === 'insert' && table === 'chat_messages') {
                        const row = {
                            id: crypto.randomUUID(),
                            ...state.insertPayload,
                            is_deleted: false,
                            created_at: new Date().toISOString(),
                            sender: usersList.find(u => u.id === state.insertPayload.sender_id) || null,
                            receiver: usersList.find(u => u.id === state.insertPayload.receiver_id) || null,
                        };
                        chatMessages.push(row);
                        return resolve({ data: [row], error: null });
                    }
                    if (state.op === 'update' && table === 'chat_messages') {
                        let matched = applyFilter(chatMessages);
                        if (state._lteIso) {
                            const lteMs = Date.parse(state._lteIso);
                            matched = matched.filter(r => Date.parse(r.created_at) <= lteMs);
                        }
                        for (const r of matched) Object.assign(r, state.updatePatch);
                        return resolve({ data: matched, error: null });
                    }
                    return resolve({ data: applyFilter(tableRows()), error: null });
                }
            };
            return chain;
        };

        const server = http.createServer(app);
        await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
        const { port } = server.address();

        try {
            const sign = (u, overrideRole) => jwt.sign(
                { id: u.id, email: u.email, name: u.name, role: overrideRole !== undefined ? overrideRole : u.role },
                secret,
                { expiresIn: '1h' }
            );

            const tokAdmin = sign(usersList.find(u => u.id === IDS.mainAdmin));
            const tokSubAdmin = sign(usersList.find(u => u.id === IDS.subAdmin));
            const tokPatAnu = sign(usersList.find(u => u.id === IDS.patientAnu));
            const tokPatAnusha = sign(usersList.find(u => u.id === IDS.patientAnusha));
            const tokDocAssigned = sign(usersList.find(u => u.id === IDS.doctorAssigned));
            const tokDocOther = sign(usersList.find(u => u.id === IDS.doctorOther));
            const tokClinic = sign(usersList.find(u => u.id === IDS.clinicUser));
            const tokClinicOther = sign(usersList.find(u => u.id === IDS.clinicOtherUser));
            const tokUnknownRole = sign(usersList.find(u => u.id === IDS.unknownRoleUser));
            const tokMissingRole = sign(usersList.find(u => u.id === IDS.missingRoleUser));
            const tokInactive = sign(usersList.find(u => u.id === IDS.inactiveUser));
            const tokNullStatus = sign(usersList.find(u => u.id === IDS.nullStatusUser));

            // 1. CRITICAL: Unauthenticated calls to ALL chat endpoints must fail with 401
            const unauthSend = await httpRequest(port, 'POST', '/api/v1/chat/send', {}, { roomId: 'PATIENT_ANU', message: 'hi' });
            assert.strictEqual(unauthSend.status, 401, 'Unauthenticated /chat/send must return 401');
            const unauthRead = await httpRequest(port, 'POST', '/api/v1/chat/read', {}, { roomId: 'PATIENT_ANU' });
            assert.strictEqual(unauthRead.status, 401, 'Unauthenticated /chat/read must return 401');

            // 2. UNKNOWN & MISSING ROLES MUST FAIL CLOSED (NEVER default to PATIENT)
            assert.strictEqual(Schemas.mapUserRoleToChatRole(''), null);
            assert.strictEqual(Schemas.mapUserRoleToChatRole(null), null);
            assert.strictEqual(Schemas.mapUserRoleToChatRole('superguest'), null);
            assert.strictEqual(Schemas.mapUserRoleToChatRole('receptionist'), null);
            assert.strictEqual(Schemas.mapUserRoleToChatRole('Patient'), 'PATIENT');
            assert.strictEqual(Schemas.mapUserRoleToChatRole('Dentist'), 'DOCTOR');

            const unkSend = await httpRequest(port, 'POST', '/api/v1/chat/send', { Authorization: `Bearer ${tokUnknownRole}` }, { roomId: 'PATIENT_ANU', message: 'hack' });
            assert.strictEqual(unkSend.status, 403, 'Unknown role user must be blocked with 403');
            const missSend = await httpRequest(port, 'POST', '/api/v1/chat/send', { Authorization: `Bearer ${tokMissingRole}` }, { roomId: 'PATIENT_ANU', message: 'hack' });
            assert.strictEqual(missSend.status, 403, 'Missing/empty role user must be blocked with 403');
            const unkConvs = await Schemas.ChatMessage.getConversations({ id: IDS.unknownRoleUser, role: 'superguest' });
            assert.strictEqual(unkConvs.length, 0, 'Model getConversations must return empty array for unknown role');
            const unkFind = await Schemas.ChatMessage.find({ room_id: 'PATIENT_ANU' }, { user: { id: IDS.unknownRoleUser, role: '' } });
            assert.strictEqual(unkFind.length, 0, 'Model ChatMessage.find must fail closed for empty/unknown role');

            // Sub-Admin, Inactive, and NULL-status users must ALL fail closed (never default NULL status to ACTIVE)
            const subSend = await httpRequest(port, 'POST', '/api/v1/chat/send', { Authorization: `Bearer ${tokSubAdmin}` }, { roomId: 'PATIENT_ANU', message: 'sub' });
            assert.strictEqual(subSend.status, 403, 'Sub-Admin must be blocked with 403');
            const inactSend = await httpRequest(port, 'POST', '/api/v1/chat/send', { Authorization: `Bearer ${tokInactive}` }, { roomId: 'PATIENT_ANU', message: 'inactive' });
            assert.strictEqual(inactSend.status, 403, 'Inactive user must be blocked with 403');
            const nullStatSend = await httpRequest(port, 'POST', '/api/v1/chat/send', { Authorization: `Bearer ${tokNullStatus}` }, { roomId: 'PATIENT_ANU', message: 'null status' });
            assert.strictEqual(nullStatSend.status, 403, 'NULL-status user must be blocked with 403 on /chat/send');
            const nullStatMsgs = await httpRequest(port, 'GET', `/api/v1/chat/messages?conversationId=${IDS.convAnuDoc}`, { Authorization: `Bearer ${tokNullStatus}` });
            assert.strictEqual(nullStatMsgs.status, 403, 'NULL-status user must be blocked with 403 on /chat/messages');
            const nullStatConvs = await httpRequest(port, 'GET', '/api/v1/chat/conversations', { Authorization: `Bearer ${tokNullStatus}` });
            assert.strictEqual(nullStatConvs.status, 403, 'NULL-status user must be blocked with 403 on /chat/conversations');
            assert.strictEqual((await Schemas.ChatMessage.getConversations({ id: IDS.nullStatusUser, role: 'Patient', status: null })).length, 0, 'Model getConversations must fail closed on NULL status');
            assert.strictEqual((await Schemas.ChatMessage.find({ conversation_id: IDS.convAnuDoc }, { user: { id: IDS.nullStatusUser, role: 'Patient', status: null } })).length, 0, 'Model ChatMessage.find must fail closed on NULL status');
            await assert.rejects(
                () => Schemas.ChatMessage.create(
                    { room_id: 'PATIENT_ANU', sender_id: IDS.nullStatusUser, message: 'nullstat bypass' },
                    { authorizedCaller: { id: IDS.nullStatusUser, role: 'Patient', status: 'ACTIVE' } }
                ),
                (err) => err.statusCode === 403,
                'ChatMessage.create must reject NULL-status DB sender even with caller status override'
            );
            await assert.rejects(
                () => Schemas.ChatMessage.create(
                    { room_id: 'PATIENT_ANU', sender_id: IDS.doctorAssigned, receiver_id: IDS.nullStatusUser, message: 'nullstat receiver' },
                    { authorizedCaller: { id: IDS.doctorAssigned, role: 'Dentist', status: 'ACTIVE' } }
                ),
                (err) => err.statusCode === 403,
                'ChatMessage.create must reject NULL-status receiver'
            );

            // 3. UNAUTHORIZED SENDER / RECEIVER COMBINATIONS & ARBITRARY RECEIVER BLOCKS
            // 3a. Spoofed senderId in body
            const spoofSenderRes = await httpRequest(port, 'POST', '/api/v1/chat/send', { Authorization: `Bearer ${tokPatAnu}` }, {
                roomId: 'PATIENT_STRANGER_PAT',
                senderId: IDS.patientStranger,
                receiverId: IDS.doctorOther,
                message: 'Impersonation attempt',
            });
            assert.strictEqual(spoofSenderRes.status, 403, 'Spoofing body senderId must be rejected with 403');

            // 3b. Patient sending to arbitrary unlinked Doctor (Dr. Arjun)
            const arbitraryDocRes = await httpRequest(port, 'POST', '/api/v1/chat/send', { Authorization: `Bearer ${tokPatAnu}` }, {
                roomId: 'PATIENT_ANU',
                receiverId: IDS.doctorOther,
                message: 'Unsolicited message to unlinked doctor',
            });
            assert.strictEqual(arbitraryDocRes.status, 403, 'Patient messaging unlinked doctor must fail with 403');

            // 3c. Patient sending to another Patient (Patient -> Patient forbidden)
            const patToPatRes = await httpRequest(port, 'POST', '/api/v1/chat/send', { Authorization: `Bearer ${tokPatAnu}` }, {
                roomId: 'PATIENT_ANU',
                receiverId: IDS.patientAnusha,
                message: 'Patient-to-patient attempt',
            });
            assert.strictEqual(patToPatRes.status, 403, 'Patient messaging another patient must fail with 403');

            // 3d. Patient sending to Sub-Admin or Admin directly
            const patToAdminRes = await httpRequest(port, 'POST', '/api/v1/chat/send', { Authorization: `Bearer ${tokPatAnu}` }, {
                roomId: 'PATIENT_ANU',
                receiverId: IDS.mainAdmin,
                message: 'Direct admin receiver inject',
            });
            assert.strictEqual(patToAdminRes.status, 403, 'Patient targeting Admin receiver must fail with 403');

            // 3e. Substring attack: Patient "Anu" trying to access "PATIENT_ANUSHA" (different patient!)
            const substrAttack = await httpRequest(port, 'GET', '/api/v1/chat/messages?roomId=PATIENT_ANUSHA', { Authorization: `Bearer ${tokPatAnu}` });
            assert.strictEqual(substrAttack.status, 403, 'Patient "Anu" must NOT access Patient "Anusha" room');
            const anuConvs = await httpRequest(port, 'GET', '/api/v1/chat/conversations', { Authorization: `Bearer ${tokPatAnu}` });
            assert.strictEqual(anuConvs.status, 200);
            assert.ok(!anuConvs.body.conversations.some(c => c.roomId === 'PATIENT_ANUSHA'), 'Conversations list must not leak PATIENT_ANUSHA to Anu');

            // 3f. Unscoped global room blocked for non-admin
            const globalRoomRes = await httpRequest(port, 'POST', '/api/v1/chat/send', { Authorization: `Bearer ${tokPatAnu}` }, {
                roomId: 'GENERAL-CHAT',
                message: 'Trying unscoped general chat',
            });
            assert.strictEqual(globalRoomRes.status, 403, 'Unscoped global chat room must fail with 403');

            // 3g. Doctor trying to message unassigned patient
            const docToUnassignedPat = await httpRequest(port, 'POST', '/api/v1/chat/send', { Authorization: `Bearer ${tokDocOther}` }, {
                roomId: 'PATIENT_ANU',
                receiverId: IDS.patientAnu,
                message: 'Unassigned doctor reaching Anu',
            });
            assert.strictEqual(docToUnassignedPat.status, 403, 'Unassigned doctor cannot message Anu (403)');

            // 3h. Doctor trying to message another Clinic they are not affiliated with
            const docToOtherClinic = await httpRequest(port, 'POST', '/api/v1/chat/send', { Authorization: `Bearer ${tokDocAssigned}` }, {
                roomId: 'PATIENT_ANU',
                receiverId: IDS.clinicOtherUser,
                message: 'Doctor messaging unaffiliated clinic',
            });
            assert.strictEqual(docToOtherClinic.status, 403, 'Doctor messaging unaffiliated clinic must fail with 403');

            // 3i. Clinic trying to message unaffiliated Doctor
            const clinicToOtherDoc = await httpRequest(port, 'POST', '/api/v1/chat/send', { Authorization: `Bearer ${tokClinic}` }, {
                roomId: 'PATIENT_ANU',
                receiverId: IDS.doctorOther,
                message: 'Clinic messaging unaffiliated doctor',
            });
            assert.strictEqual(clinicToOtherDoc.status, 403, 'Clinic messaging unaffiliated doctor must fail with 403');

            // 3j. Service-role model defense-in-depth: direct ChatMessage.create cannot insert with empty/unknown sender or Patient->Patient
            await assert.rejects(
                () => Schemas.ChatMessage.create(
                    { room_id: 'PATIENT_ANU', sender_id: IDS.unknownRoleUser, message: 'bypass' },
                    { authorizedCaller: { id: IDS.unknownRoleUser, role: 'Patient', status: 'ACTIVE' } }
                ),
                (err) => err.statusCode === 403
            );
            await assert.rejects(
                () => Schemas.ChatMessage.create(
                    { room_id: 'PATIENT_ANU', sender_id: IDS.patientAnu, receiver_id: IDS.patientAnusha, message: 'bypass' },
                    { authorizedCaller: { id: IDS.patientAnu, role: 'Patient', status: 'ACTIVE' } }
                ),
                (err) => err.statusCode === 403
            );

            // 3k. Mandatory authorizedCaller fail-closed model guard tests
            await assert.rejects(
                () => Schemas.ChatMessage.create({ room_id: 'PATIENT_ANU', sender_id: IDS.patientAnu, message: 'missing options' }),
                (err) => err.statusCode === 401
            );
            await assert.rejects(
                () => Schemas.ChatMessage.create({ room_id: 'PATIENT_ANU', sender_id: IDS.patientAnu, message: 'null caller' }, { authorizedCaller: null }),
                (err) => err.statusCode === 401
            );
            await assert.rejects(
                () => Schemas.ChatMessage.create({ room_id: 'PATIENT_ANU', sender_id: IDS.patientAnu, message: 'empty id' }, { authorizedCaller: { id: '', role: 'Patient', status: 'ACTIVE' } }),
                (err) => err.statusCode === 401
            );
            await assert.rejects(
                () => Schemas.ChatMessage.create({ room_id: 'PATIENT_ANU', sender_id: IDS.patientAnu, message: 'missing status' }, { authorizedCaller: { id: IDS.patientAnu, role: 'Patient' } }),
                (err) => err.statusCode === 403
            );
            await assert.rejects(
                () => Schemas.ChatMessage.create({ room_id: 'PATIENT_ANU', sender_id: IDS.patientAnu, message: 'null status' }, { authorizedCaller: { id: IDS.patientAnu, role: 'Patient', status: null } }),
                (err) => err.statusCode === 403
            );
            await assert.rejects(
                () => Schemas.ChatMessage.create({ room_id: 'PATIENT_ANU', sender_id: IDS.patientAnu, message: 'inactive status' }, { authorizedCaller: { id: IDS.patientAnu, role: 'Patient', status: 'INACTIVE' } }),
                (err) => err.statusCode === 403
            );
            await assert.rejects(
                () => Schemas.ChatMessage.create({ room_id: 'PATIENT_ANU', sender_id: IDS.patientAnu, message: 'missing role property' }, { authorizedCaller: { id: IDS.patientAnu, status: 'ACTIVE' } }),
                (err) => err.statusCode === 403
            );
            await assert.rejects(
                () => Schemas.ChatMessage.create({ room_id: 'PATIENT_ANU', sender_id: IDS.patientAnu, message: 'null role' }, { authorizedCaller: { id: IDS.patientAnu, role: null, status: 'ACTIVE' } }),
                (err) => err.statusCode === 403
            );
            await assert.rejects(
                () => Schemas.ChatMessage.create({ room_id: 'PATIENT_ANU', sender_id: IDS.patientAnu, message: 'empty role' }, { authorizedCaller: { id: IDS.patientAnu, role: '', status: 'ACTIVE' } }),
                (err) => err.statusCode === 403
            );
            await assert.rejects(
                () => Schemas.ChatMessage.create({ room_id: 'PATIENT_ANU', sender_id: IDS.patientAnu, message: 'unknown role' }, { authorizedCaller: { id: IDS.patientAnu, role: 'guest', status: 'ACTIVE' } }),
                (err) => err.statusCode === 403
            );
            await assert.rejects(
                () => Schemas.ChatMessage.create({ room_id: 'PATIENT_ANU', sender_id: IDS.subAdmin, message: 'subadmin caller' }, { authorizedCaller: { id: IDS.subAdmin, role: 'Sub-Admin', status: 'ACTIVE' } }),
                (err) => err.statusCode === 403
            );
            await assert.rejects(
                () => Schemas.ChatMessage.create({ room_id: 'PATIENT_ANU', sender_id: IDS.patientAnu, message: 'id mismatch' }, { authorizedCaller: { id: IDS.patientStranger, role: 'Patient', status: 'ACTIVE' } }),
                (err) => err.statusCode === 403
            );
            await assert.rejects(
                () => Schemas.ChatMessage.create(
                    { room_id: 'PATIENT_ANU', sender_id: IDS.patientAnu, message: 'role override' },
                    { authorizedCaller: { id: IDS.patientAnu, role: 'Patient', status: 'ACTIVE' }, authorizedChatRole: 'ADMIN' }
                ),
                (err) => err.statusCode === 403
            );

            // 4. LEGITIMATE PATIENT, DOCTOR, CLINIC & ADMIN CHAT FLOWS SUCCEED
            // 4a. Patient Anu -> Assigned Dr. Rohitha
            const validPatSend = await httpRequest(port, 'POST', '/api/v1/chat/send', { Authorization: `Bearer ${tokPatAnu}` }, {
                roomId: 'PATIENT_ANU',
                receiverId: IDS.doctorAssigned,
                message: 'Hello Dr. Rohitha, sharing my X-ray',
                type: 'image',
            });
            assert.strictEqual(validPatSend.status, 201, `Valid patient send failed: ${JSON.stringify(validPatSend.body)}`);
            assert.strictEqual(validPatSend.body.chat.type, 'image', 'Clinical image type must be preserved');
            const patMsgId = validPatSend.body.chat.id;

            // 4b. Assigned Dr. Rohitha replies -> Patient Anu
            const validDocSend = await httpRequest(port, 'POST', '/api/v1/chat/send', { Authorization: `Bearer ${tokDocAssigned}` }, {
                roomId: 'PATIENT_ANU',
                receiverId: IDS.patientAnu,
                message: 'Received Anu, issuing e-prescription',
                type: 'prescription',
            });
            assert.strictEqual(validDocSend.status, 201, `Valid doctor send failed: ${JSON.stringify(validDocSend.body)}`);
            assert.strictEqual(validDocSend.body.chat.type, 'prescription');

            // 4c. Affiliated Devi Clinic accesses & messages in affiliated clinic thread
            const validClinicMsgs = await httpRequest(port, 'GET', '/api/v1/chat/messages?roomId=PATIENT_ANU', { Authorization: `Bearer ${tokClinic}` });
            assert.strictEqual(validClinicMsgs.status, 200, 'Affiliated clinic can read clinic doctor thread');
            const validClinicSend = await httpRequest(port, 'POST', '/api/v1/chat/send', { Authorization: `Bearer ${tokClinic}` }, {
                roomId: 'PATIENT_ANU',
                receiverId: IDS.doctorAssigned,
                message: 'Clinic coordinator: slot confirmed for 4 PM',
            });
            assert.strictEqual(validClinicSend.status, 201, 'Affiliated clinic can message its affiliated doctor');

            // Unrelated Apollo Clinic must be denied
            const otherClinicMsgs = await httpRequest(port, 'GET', '/api/v1/chat/messages?roomId=PATIENT_ANU', { Authorization: `Bearer ${tokClinicOther}` });
            assert.strictEqual(otherClinicMsgs.status, 403, 'Unaffiliated clinic must get 403');

            // 4d. Main Admin audited inspection & reply
            const adminRead = await httpRequest(port, 'GET', '/api/v1/chat/messages?roomId=PATIENT_ANU&markRead=true', { Authorization: `Bearer ${tokAdmin}` });
            assert.strictEqual(adminRead.status, 200);
            assert.ok(auditLogs.some(l => l.action === 'ADMIN_CHAT_MESSAGES_VIEW' && l.target_resource === 'PATIENT_ANU'));
            assert.strictEqual(validPatSend.body.chat.read, false, 'Admin inspection must NOT mark patient messages as read');

            // 5. READ RECEIPT AUTHORIZATION & TIMESTAMP TAMPERING PROTECTION
            // 5a. Stranger cannot mark Anu's room read
            const strangerMarkRead = await httpRequest(port, 'POST', '/api/v1/chat/read', { Authorization: `Bearer ${tokPatAnusha}` }, {
                roomId: 'PATIENT_ANU',
                lastReadMessageId: patMsgId,
            });
            assert.strictEqual(strangerMarkRead.status, 403, 'Non-member cannot mark another room read');

            // 5b. Authorized user cannot mark read on behalf of another userId
            const forgedUserMarkRead = await httpRequest(port, 'POST', '/api/v1/chat/read', { Authorization: `Bearer ${tokDocAssigned}` }, {
                roomId: 'PATIENT_ANU',
                userId: IDS.patientAnu,
                lastReadMessageId: patMsgId,
            });
            assert.strictEqual(forgedUserMarkRead.status, 403, 'Cannot update read receipt for another user');

            // 5c. Authorized user CANNOT modify lastReadAt independently without lastReadMessageId
            const independentTsRes = await httpRequest(port, 'POST', '/api/v1/chat/read', { Authorization: `Bearer ${tokDocAssigned}` }, {
                roomId: 'PATIENT_ANU',
                lastReadAt: new Date().toISOString(),
            });
            assert.strictEqual(independentTsRes.status, 400, 'Independent lastReadAt without lastReadMessageId must be rejected');

            // 5d. Authorized user CANNOT supply cross-conversation messageId as lastReadMessageId
            const crossConvMsgRes = await httpRequest(port, 'POST', '/api/v1/chat/read', { Authorization: `Bearer ${tokDocAssigned}` }, {
                roomId: 'PATIENT_ANU',
                lastReadMessageId: '11111111-1111-4111-8111-000000000001', // belongs to PATIENT_STRANGER_PAT
            });
            assert.strictEqual(crossConvMsgRes.status, 403, 'Cross-conversation messageId in read receipt must be rejected');

            // 5e. Authorized user CANNOT supply timestamp earlier than message.created_at
            const backdatedTsRes = await httpRequest(port, 'POST', '/api/v1/chat/read', { Authorization: `Bearer ${tokDocAssigned}` }, {
                roomId: 'PATIENT_ANU',
                lastReadMessageId: patMsgId,
                lastReadAt: '2020-01-01T00:00:00.000Z',
            });
            assert.strictEqual(backdatedTsRes.status, 400, 'Backdated read timestamp must be rejected');

            // 5f. Non-admin cannot clear chat history (403)
            const patClearRes = await httpRequest(port, 'POST', '/api/v1/chat/clear', { Authorization: `Bearer ${tokPatAnu}` }, { roomId: 'PATIENT_ANU' });
            assert.strictEqual(patClearRes.status, 403, 'Non-admin cannot clear chat history');

            // 5g. Valid coupled read receipt by Dr. Rohitha for Pat Anu's message succeeds
            const validMarkRead = await httpRequest(port, 'POST', '/api/v1/chat/read', { Authorization: `Bearer ${tokDocAssigned}` }, {
                roomId: 'PATIENT_ANU',
                lastReadMessageId: patMsgId,
                lastReadAt: new Date().toISOString(),
            });
            assert.strictEqual(validMarkRead.status, 200, `Valid markRoomRead failed: ${JSON.stringify(validMarkRead.body)}`);
            assert.strictEqual(validMarkRead.body.updatedCount, 1);

            // 6. NEW FINDING REGRESSION TESTS: CONVERSATION-ID SCOPING, EMPTY QUERY, CROSS-CONV READ RECEIPT, INACTIVE CONVS & ADMIN AUDIT FAIL-CLOSED
            // 6a. Empty-query prevention on GET /chat/messages (NO roomId & NO conversationId must return 400 and NEVER call ChatMessage.find({}))
            const origFind = Schemas.ChatMessage.find.bind(Schemas.ChatMessage);
            let emptyFindCalled = false;
            Schemas.ChatMessage.find = async (q = {}, opts = {}) => {
                if (!q || (!q.conversation_id && !q.conversationId && !q.room_id && !q.roomId)) {
                    emptyFindCalled = true;
                }
                return origFind(q, opts);
            };
            try {
                const emptyPatMsgs = await httpRequest(port, 'GET', '/api/v1/chat/messages', { Authorization: `Bearer ${tokPatAnu}` });
                assert.strictEqual(emptyPatMsgs.status, 400, 'Empty GET /chat/messages must return 400 for patient');
                const emptyAdminMsgs = await httpRequest(port, 'GET', '/api/v1/chat/messages', { Authorization: `Bearer ${tokAdmin}` });
                assert.strictEqual(emptyAdminMsgs.status, 400, 'Empty GET /chat/messages must return 400 even for Admin');
                const missingConvAdmin = await httpRequest(port, 'GET', '/api/v1/chat/messages?conversationId=ffffffff-ffff-4fff-8fff-ffffffffffff', { Authorization: `Bearer ${tokAdmin}` });
                assert.strictEqual(missingConvAdmin.status, 404, 'Non-existent conversationId must fail with 404 for Admin too');
                assert.strictEqual(emptyFindCalled, false, 'ChatMessage.find({}) must NEVER be invoked from chatController.getMessages');
            } finally {
                Schemas.ChatMessage.find = origFind;
            }

            // 6b. Conversation-ID-only retrieval (no roomId in query) returns strictly that conversation's messages
            const patConvOnly = await httpRequest(port, 'GET', `/api/v1/chat/messages?conversationId=${IDS.convAnuDoc}`, { Authorization: `Bearer ${tokPatAnu}` });
            assert.strictEqual(patConvOnly.status, 200, `Conversation-ID-only retrieval failed for patient: ${JSON.stringify(patConvOnly.body)}`);
            assert.ok(patConvOnly.body.messages.every(m => m.conversation_id === IDS.convAnuDoc), 'Must return ONLY convAnuDoc messages');
            assert.ok(!patConvOnly.body.messages.some(m => m.id === '11111111-1111-4111-8111-000000000003'), 'Must NOT include convSharedRoomB message even though it shares room_id=PATIENT_ANU');

            const docConvOnly = await httpRequest(port, 'GET', `/api/v1/chat/messages?conversationId=${IDS.convSharedRoomB}`, { Authorization: `Bearer ${tokDocAssigned}` });
            assert.strictEqual(docConvOnly.status, 200);
            assert.strictEqual(docConvOnly.body.messages.length, 1);
            assert.strictEqual(docConvOnly.body.messages[0].id, '11111111-1111-4111-8111-000000000003');

            const adminConvOnly = await httpRequest(port, 'GET', `/api/v1/chat/messages?conversationId=${IDS.convStranger}`, { Authorization: `Bearer ${tokAdmin}` });
            assert.strictEqual(adminConvOnly.status, 200);
            assert.strictEqual(adminConvOnly.body.messages.length, 1);
            assert.strictEqual(adminConvOnly.body.messages[0].conversation_id, IDS.convStranger, 'Admin conversationId-only fetch must be strictly scoped (never all conversations)');

            // Unauthorized patient cannot read stranger conversationId
            const unauthConvOnly = await httpRequest(port, 'GET', `/api/v1/chat/messages?conversationId=${IDS.convStranger}`, { Authorization: `Bearer ${tokPatAnu}` });
            assert.strictEqual(unauthConvOnly.status, 403);

            // 6c. Cross-conversation read receipt rejection EVEN when room_id matches ('PATIENT_ANU' vs convSharedRoomB)
            const crossConvSameRoomRead = await httpRequest(port, 'POST', '/api/v1/chat/read', { Authorization: `Bearer ${tokDocAssigned}` }, {
                conversationId: IDS.convAnuDoc,
                lastReadMessageId: '11111111-1111-4111-8111-000000000003', // belongs to convSharedRoomB, NOT convAnuDoc!
            });
            assert.strictEqual(crossConvSameRoomRead.status, 403, 'Cross-conversation lastReadMessageId sharing same room_id must be rejected with 403');

            // Mismatched roomId + conversationId rejected
            const mismatchRoomConv = await httpRequest(port, 'GET', `/api/v1/chat/messages?conversationId=${IDS.convAnuDoc}&roomId=PATIENT_STRANGER_PAT`, { Authorization: `Bearer ${tokPatAnu}` });
            assert.strictEqual(mismatchRoomConv.status, 403, 'Mismatched conversationId and roomId must be rejected');

            // 6d. Inactive / CLOSED / BLOCKED conversation rejection (consistent for sender & receiver)
            const closedPatSend = await httpRequest(port, 'POST', '/api/v1/chat/send', { Authorization: `Bearer ${tokPatAnu}` }, {
                conversationId: IDS.convClosed,
                receiverId: IDS.doctorAssigned,
                message: 'Trying to message closed conversation',
            });
            assert.strictEqual(closedPatSend.status, 403, 'Patient sending into CLOSED conversation must fail with 403');
            const closedDocSend = await httpRequest(port, 'POST', '/api/v1/chat/send', { Authorization: `Bearer ${tokDocAssigned}` }, {
                conversationId: IDS.convClosed,
                receiverId: IDS.patientAnu,
                message: 'Doctor trying to message closed conversation',
            });
            assert.strictEqual(closedDocSend.status, 403, 'Doctor sending into CLOSED conversation must fail with 403');
            const closedReadReceipt = await httpRequest(port, 'POST', '/api/v1/chat/read', { Authorization: `Bearer ${tokDocAssigned}` }, {
                conversationId: IDS.convClosed,
                lastReadMessageId: '11111111-1111-4111-8111-000000000004',
            });
            assert.strictEqual(closedReadReceipt.status, 403, 'Updating read receipt on CLOSED conversation must fail with 403');
            // CLOSED history remains readable via GET
            const closedReadHist = await httpRequest(port, 'GET', `/api/v1/chat/messages?conversationId=${IDS.convClosed}`, { Authorization: `Bearer ${tokPatAnu}` });
            assert.strictEqual(closedReadHist.status, 200, 'CLOSED historical messages remain readable to authorized participant');

            const blockedMsgs = await httpRequest(port, 'GET', `/api/v1/chat/messages?conversationId=${IDS.convBlocked}`, { Authorization: `Bearer ${tokPatAnu}` });
            assert.strictEqual(blockedMsgs.status, 403, 'BLOCKED conversation messages cannot be read by non-admin');
            const blockedSend = await httpRequest(port, 'POST', '/api/v1/chat/send', { Authorization: `Bearer ${tokPatAnu}` }, {
                roomId: 'CONV_BLOCKED_ANU',
                receiverId: IDS.doctorAssigned,
                message: 'Trying blocked room',
            });
            assert.strictEqual(blockedSend.status, 403, 'BLOCKED conversation resolved via roomId must fail with 403');

            // 6e. Mandatory Admin audit reliability: when audit_logs write fails, Admin actions FAIL CLOSED and mutate nothing
            const origSupaFromInner = supabaseCfg.supabaseAdmin.from;
            const origAuditCreateInner = Schemas.AuditLog.create;
            try {
                // Restore real AuditLog.create so we test strict DB error handling end-to-end
                Schemas.AuditLog.create = origAudit.create;
                supabaseCfg.supabaseAdmin.from = (table) => {
                    if (table === 'audit_logs') {
                        return {
                            insert() {
                                return {
                                    select() {
                                        return {
                                            async maybeSingle() {
                                                return { data: null, error: { message: 'audit_logs write unavailable' } };
                                            }
                                        };
                                    }
                                };
                            }
                        };
                    }
                    return origSupaFromInner(table);
                };

                const beforeClearCount = chatMessages.length;
                const adminListAuditFail = await httpRequest(port, 'GET', '/api/v1/chat/conversations', { Authorization: `Bearer ${tokAdmin}` });
                assert.strictEqual(adminListAuditFail.status, 500, 'Admin /chat/conversations must fail closed if audit write fails');
                assert.ok(!adminListAuditFail.body.conversations, 'Failed audit must not leak conversations payload');

                const adminMsgAuditFail = await httpRequest(port, 'GET', `/api/v1/chat/messages?conversationId=${IDS.convStranger}`, { Authorization: `Bearer ${tokAdmin}` });
                assert.strictEqual(adminMsgAuditFail.status, 500, 'Admin /chat/messages must fail closed if audit write fails');
                assert.ok(!adminMsgAuditFail.body.messages, 'Failed audit must not leak messages payload');

                const adminSendAuditFail = await httpRequest(port, 'POST', '/api/v1/chat/send', { Authorization: `Bearer ${tokAdmin}` }, {
                    conversationId: IDS.convAnuDoc,
                    receiverId: IDS.patientAnu,
                    message: 'Should NOT persist without audit',
                });
                assert.strictEqual(adminSendAuditFail.status, 500, 'Admin /chat/send must fail closed if audit write fails');
                assert.strictEqual(chatMessages.length, beforeClearCount, 'Admin /chat/send must NOT insert message when audit fails');

                const adminClearAuditFail = await httpRequest(port, 'POST', '/api/v1/chat/clear', { Authorization: `Bearer ${tokAdmin}` }, {
                    conversationId: IDS.convStranger,
                });
                assert.strictEqual(adminClearAuditFail.status, 500, 'Admin /chat/clear must fail closed if audit write fails');
                assert.strictEqual(chatMessages.length, beforeClearCount, 'Admin /chat/clear must NOT delete messages when audit fails');
            } finally {
                supabaseCfg.supabaseAdmin.from = origSupaFromInner;
                Schemas.AuditLog.create = origAuditCreateInner;
            }

            // 7. STRICT SUB-ADMIN CHAT & REALTIME PROHIBITION REGRESSION TESTS (POSITIVE + NEGATIVE)
            const origUserFindOne = Schemas.User.findOne;
            const origUserFindByMobile = Schemas.User.findByMobile;
            const origUserFindByIdAndUpdate = Schemas.User.findByIdAndUpdate;
            const origSubAdminDistrictGet = Schemas.SubAdminDistrict.getDistrictsForSubAdmin;
            const origSubAdminPermGet = Schemas.SubAdminPermission.getPermissionsForUser;
            const origComparePassword = Schemas.comparePassword;
            const origRpc = supabaseCfg.supabaseAdmin.rpc;
            const origSbJwt = process.env.SUPABASE_JWT_SECRET;
            const origSbAnon = process.env.SUPABASE_ANON_KEY;

            try {
                // Ensure offline deterministic HS256 signing secrets if SUPABASE_JWT_SECRET is absent in CI
                if (!hasSupabaseJwtSecret()) {
                    const testSbSecret = 'offline_test_supabase_jwt_secret_key_32chars_min!';
                    process.env.SUPABASE_JWT_SECRET = testSbSecret;
                    process.env.SUPABASE_ANON_KEY = jwt.sign({ ref: 'ojinzcdldwugpnxrnjcq', role: 'anon' }, testSbSecret, { algorithm: 'HS256' });
                }

                // Assign test phone numbers in-memory for login / OTP regression checks
                const subAdminRecord = usersList.find(u => u.id === IDS.subAdmin);
                const patientRecord = usersList.find(u => u.id === IDS.patientAnu);
                const doctorRecord = usersList.find(u => u.id === IDS.doctorAssigned);
                const adminRecord = usersList.find(u => u.id === IDS.mainAdmin);
                subAdminRecord.phone = '9111111112';
                patientRecord.phone = '9111111113';
                doctorRecord.phone = '9111111114';
                adminRecord.phone = '9111111111';

                Schemas.User.findOne = async (q = {}) => {
                    const u = usersList.find(x =>
                        (!q.id || x.id === q.id) &&
                        (!q.phone || x.phone === q.phone) &&
                        (!q.email || String(x.email || '').toLowerCase() === String(q.email).toLowerCase())
                    );
                    return u ? { ...u } : null;
                };
                Schemas.User.findByMobile = async (p) => {
                    const clean = String(p || '').replace(/\D/g, '').slice(-10);
                    const u = usersList.find(x => String(x.phone || '').slice(-10) === clean);
                    return u ? { ...u } : null;
                };
                Schemas.User.findByIdAndUpdate = async (id, patch) => {
                    const u = usersList.find(x => x.id === id);
                    if (u && patch) Object.assign(u, patch);
                    return u ? { ...u } : null;
                };
                Schemas.SubAdminDistrict.getDistrictsForSubAdmin = async () => [{ id: 'd0000000-0000-4000-8000-000000000001', district_id: 'd0000000-0000-4000-8000-000000000001', name: 'Hyderabad' }];
                Schemas.SubAdminPermission.getPermissionsForUser = async (uid) => uid === IDS.subAdmin ? ['CHAT_VIEW', 'CHAT_SEND', '*'] : [];
                Schemas.comparePassword = async () => true;
                supabaseCfg.supabaseAdmin.rpc = async (fnName, params = {}) => {
                    if (fnName === 'verify_otp_challenge') {
                        const valid = params.p_incoming_hash === hashOtp('654321');
                        return { data: { valid, reason: valid ? 'VERIFIED' : 'INVALID_CODE' }, error: null };
                    }
                    return { data: null, error: null };
                };

                // 7a. Positive: PATIENT, DOCTOR, CLINIC & ADMIN obtain valid Realtime JWTs via /auth/realtime-token
                for (const [label, tok, expectedId, expectedAppRole] of [
                    ['PATIENT', tokPatAnu, IDS.patientAnu, 'PATIENT'],
                    ['DOCTOR', tokDocAssigned, IDS.doctorAssigned, 'DOCTOR'],
                    ['CLINIC', tokClinic, IDS.clinicUser, 'CLINIC'],
                    ['ADMIN', tokAdmin, IDS.mainAdmin, 'ADMIN'],
                ]) {
                    const rtPost = await httpRequest(port, 'POST', '/api/v1/auth/realtime-token', { Authorization: `Bearer ${tok}` });
                    assert.strictEqual(rtPost.status, 200, `${label} POST /auth/realtime-token must succeed`);
                    assert.ok(rtPost.body.realtimeToken && rtPost.body.realtimeTokenExpiresAt);
                    const decoded = verifySupabaseRealtimeToken(rtPost.body.realtimeToken);
                    assert.strictEqual(decoded.sub, expectedId);
                    assert.strictEqual(decoded.app_role, expectedAppRole);
                }

                // 7b. Negative: SUB_ADMIN rejected with HTTP 403 on GET & POST /auth/realtime-token (even with CHAT_VIEW & '*')
                for (const method of ['GET', 'POST']) {
                    const rtSub = await httpRequest(port, method, '/api/v1/auth/realtime-token', { Authorization: `Bearer ${tokSubAdmin}` });
                    assert.strictEqual(rtSub.status, 403, `SUB_ADMIN ${method} /auth/realtime-token must return 403`);
                    assert.strictEqual(rtSub.body.code, 'CHAT_FORBIDDEN_FOR_ROLE');
                    assert.strictEqual(rtSub.body.realtimeToken, undefined);
                }
                await assert.rejects(
                    () => mintSupabaseRealtimeTokenForUser(subAdminRecord),
                    (err) => err.statusCode === 403 && err.code === 'CHAT_FORBIDDEN_FOR_ROLE'
                );
                assert.strictEqual(await tryMintSupabaseRealtimeTokenForUser(subAdminRecord), null);

                // Forged/legacy SUB_ADMIN Realtime JWT rejected by verifier
                assert.throws(() => {
                    const forgedSubJwt = jwt.sign(
                        { aud: 'authenticated', role: 'authenticated', sub: IDS.subAdmin, app_role: 'SUB_ADMIN' },
                        process.env.SUPABASE_JWT_SECRET,
                        { algorithm: 'HS256', expiresIn: '5m' }
                    );
                    verifySupabaseRealtimeToken(forgedSubJwt);
                }, /prohibited/i);

                // 7c. Negative/Positive: /auth/login, /auth/refresh, /auth/otp/verify NEVER mint realtimeToken for SUB_ADMIN (while minting for Patient)
                const subLogin = await httpRequest(port, 'POST', '/api/v1/auth/login', {}, {
                    phone: subAdminRecord.phone,
                    otp: '654321',
                    role: 'Sub-Admin',
                });
                assert.strictEqual(subLogin.status, 200, `SUB_ADMIN login failed: ${JSON.stringify(subLogin.body)}`);
                assert.strictEqual(subLogin.body.realtimeToken, undefined, 'SUB_ADMIN login must NEVER return realtimeToken');
                assert.strictEqual(subLogin.body.realtimeTokenExpiresAt, undefined);

                const patLogin = await httpRequest(port, 'POST', '/api/v1/auth/login', {}, {
                    phone: patientRecord.phone,
                    otp: '654321',
                });
                assert.strictEqual(patLogin.status, 200);
                assert.ok(patLogin.body.realtimeToken && patLogin.body.realtimeTokenExpiresAt, 'PATIENT login must return realtimeToken');

                const refreshSecret = getRefreshSecret();
                const subRefreshTok = jwt.sign({ id: IDS.subAdmin }, refreshSecret, { expiresIn: '1h' });
                const patRefreshTok = jwt.sign({ id: IDS.patientAnu }, refreshSecret, { expiresIn: '1h' });

                const subRefresh = await httpRequest(port, 'POST', '/api/v1/auth/refresh', {}, { refreshToken: subRefreshTok });
                assert.strictEqual(subRefresh.status, 200);
                assert.strictEqual(subRefresh.body.realtimeToken, undefined, 'SUB_ADMIN refresh must NEVER return realtimeToken');
                assert.strictEqual(subRefresh.body.realtimeTokenExpiresAt, undefined);

                const patRefresh = await httpRequest(port, 'POST', '/api/v1/auth/refresh', {}, { refreshToken: patRefreshTok });
                assert.strictEqual(patRefresh.status, 200);
                assert.ok(patRefresh.body.realtimeToken && patRefresh.body.realtimeTokenExpiresAt, 'PATIENT refresh must return realtimeToken');

                const subOtpVerify = await httpRequest(port, 'POST', '/api/v1/auth/otp/verify', {}, {
                    phone: subAdminRecord.phone,
                    code: '654321',
                });
                assert.strictEqual(subOtpVerify.status, 200, `SUB_ADMIN verifyOTP failed: ${JSON.stringify(subOtpVerify.body)}`);
                assert.strictEqual(subOtpVerify.body.realtimeToken, undefined, 'SUB_ADMIN verifyOTP must NEVER return realtimeToken');
                assert.strictEqual(subOtpVerify.body.realtimeTokenExpiresAt, undefined);

                const patOtpVerify = await httpRequest(port, 'POST', '/api/v1/auth/otp/verify', {}, {
                    phone: patientRecord.phone,
                    code: '654321',
                });
                assert.strictEqual(patOtpVerify.status, 200);
                assert.ok(patOtpVerify.body.realtimeToken && patOtpVerify.body.realtimeTokenExpiresAt, 'PATIENT verifyOTP must return realtimeToken');

                // 7d. Verify Phase 2B SQL prohibits SUB_ADMIN on ALL chat:user & chat:conv topics while preserving ADMIN audited access
                const phase2bSql = fs.readFileSync(path.resolve(__dirname, '../migrations/03_realtime_chat_phase2b.sql'), 'utf8');
                const topicFnStart = phase2bSql.indexOf('CREATE OR REPLACE FUNCTION public.can_subscribe_chat_realtime_topic');
                const topicFnEnd = phase2bSql.indexOf('$$;', topicFnStart);
                assert.ok(topicFnStart !== -1 && topicFnEnd !== -1);
                const topicFnBody = phase2bSql.slice(topicFnStart, topicFnEnd);

                assert.ok(/IF\s+v_chat_role\s*=\s*'SUB_ADMIN'\s+THEN\s+RETURN\s+false;/i.test(topicFnBody), 'can_subscribe_chat_realtime_topic must immediately deny SUB_ADMIN');
                assert.ok(/v_chat_role\s+NOT\s+IN\s*\(\s*'PATIENT'\s*,\s*'DOCTOR'\s*,\s*'CLINIC'\s*,\s*'ADMIN'\s*\)/i.test(topicFnBody), 'chat:user channel must exclude SUB_ADMIN');
                assert.ok(!/SUBADMIN_CHAT_THREAD_OPEN/.test(phase2bSql), 'SUBADMIN_CHAT_THREAD_OPEN allow branch must be removed');
                assert.ok(/ADMIN_CHAT_THREAD_OPEN/.test(topicFnBody) && /is_authorized_chat_reader/.test(topicFnBody), 'ADMIN audited topic & PATIENT/DOCTOR/CLINIC reader checks must remain intact');
                const backfillStart = phase2bSql.indexOf('INSERT INTO public.chat_participants (conversation_id, user_id, participant_role');
                const backfillEnd = phase2bSql.indexOf('ON CONFLICT (conversation_id, user_id) DO NOTHING;', backfillStart);
                assert.ok(backfillStart !== -1 && backfillEnd !== -1);
                const backfillBlock = phase2bSql.slice(backfillStart, backfillEnd);
                assert.ok(!/sub-admin|subadmin|sub_admin/i.test(backfillBlock), 'chat_participants backfill must not enroll Sub-Admins');
            } finally {
                Schemas.User.findOne = origUserFindOne;
                Schemas.User.findByMobile = origUserFindByMobile;
                Schemas.User.findByIdAndUpdate = origUserFindByIdAndUpdate;
                Schemas.SubAdminDistrict.getDistrictsForSubAdmin = origSubAdminDistrictGet;
                Schemas.SubAdminPermission.getPermissionsForUser = origSubAdminPermGet;
                Schemas.comparePassword = origComparePassword;
                supabaseCfg.supabaseAdmin.rpc = origRpc;
                if (origSbJwt === undefined) delete process.env.SUPABASE_JWT_SECRET; else process.env.SUPABASE_JWT_SECRET = origSbJwt;
                if (origSbAnon === undefined) delete process.env.SUPABASE_ANON_KEY; else process.env.SUPABASE_ANON_KEY = origSbAnon;
            }

            console.log('✅ ALL PHASE 2B CHAT AUTHORIZATION, UNKNOWN ROLE & READ-RECEIPT TESTS PASSED!');
        } finally {
            server.close();
        }
    } finally {
        Object.assign(Schemas.User, origUser);
        Object.assign(Schemas.Clinic, origClinic);
        Object.assign(Schemas.Dentist, origDentist);
        Object.assign(Schemas.AuditLog, origAudit);
        Object.assign(Schemas.PatientAssignmentHistory, origHistory);
        Object.assign(Schemas.Referral, origReferral);
        Object.assign(Schemas.PatientDoctor, origPatDoc);
        Schemas.resolveClinicIds = origResolveClinic;
        supabaseCfg.supabaseAdmin.from = origSupaFrom;
    }
})();
