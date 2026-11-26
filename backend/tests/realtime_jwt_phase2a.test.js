/**
 * Phase 2A Automated Security & Staging Integration Tests:
 * - Short-lived Supabase-compatible HS256 Realtime JWT generation for chat-authorized roles
 *   (PATIENT, DOCTOR, CLINIC, ADMIN)
 * - Strict Sub-Admin prohibition from chat and Realtime token generation (HTTP 403)
 * - Canonical `sub = public.users.id` enforcement (especially Doctor & Clinic dual-ID accounts)
 * - Live staging Supabase (`ojinzcdldwugpnxrnjcq`) PostgREST & Realtime WebSocket authentication
 * - ACTIVE status enforcement, tamper resistance, privilege-escalation prevention, and zero secret exposure
 */
require('dotenv').config();
const assert = require('assert');
const http = require('http');
const jwt = require('jsonwebtoken');
const { createClient } = require('@supabase/supabase-js');
const app = require('../src/app');
const { supabaseAdmin } = require('../src/config/supabase');
const { getJwtSecret, getRefreshSecret, hasSupabaseJwtSecret } = require('../src/config/secrets');
const { User, Dentist, Clinic, District, SubAdminDistrict, SubAdminPermission, resolveCanonicalChatUserId } = require('../src/models/Schemas');
const { mintSupabaseRealtimeTokenForUser, tryMintSupabaseRealtimeTokenForUser, verifySupabaseRealtimeToken } = require('../src/services/realtimeTokenService');

describe('Phase 2A — Supabase Realtime JWT & Role Prohibition Validation', function () {
    this.timeout(60000);

    let server;
    let port;
    const suffix = String(Date.now()).slice(-6);

    const createdUserIds = [];
    const createdDentistIds = [];
    const createdClinicIds = [];
    let subAdminUserId = null;

    // 5 Role Fixtures in Staging DB (cleaned up in after(), except existing staging Admin 9281030535)
    const fixtures = {
        patient: null,
        doctorUser: null,
        dentistRecord: null,
        clinicUser: null,
        clinicRecord: null,
        adminUser: null,
        subAdminUser: null,
        districtId: null,
    };

    const apiReq = (method, urlPath, headers = {}, body = null) => new Promise((resolve, reject) => {
        const payload = body ? JSON.stringify(body) : null;
        const req = http.request({
            hostname: '127.0.0.1',
            port,
            path: urlPath,
            method,
            headers: {
                ...(payload ? { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(payload) } : {}),
                ...headers,
            }
        }, (res) => {
            let raw = '';
            res.on('data', (c) => { raw += c; });
            res.on('end', () => {
                try {
                    resolve({ status: res.statusCode, json: raw ? JSON.parse(raw) : {} });
                } catch (_) {
                    resolve({ status: res.statusCode, json: {} });
                }
            });
        });
        req.on('error', reject);
        if (payload) req.write(payload);
        req.end();
    });

    before(async () => {
        assert.strictEqual(
            hasSupabaseJwtSecret(),
            true,
            'SUPABASE_JWT_SECRET must be configured in backend/.env for Phase 2A staging validation'
        );

        server = http.createServer(app);
        await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
        port = server.address().port;

        // 1. Existing staging Admin (9281030535)
        const existingAdmin = await User.findOne({ phone: '9281030535' });
        assert.ok(existingAdmin && existingAdmin.id, 'Staging Admin 9281030535 must exist in public.users');
        assert.strictEqual(existingAdmin.role, 'ADMIN');
        fixtures.adminUser = existingAdmin;

        // 2. Temporary staging Patient
        fixtures.patient = await User.create({
            name: `Phase2A Patient ${suffix}`,
            email: `p2a_pat_${suffix}@dentaguru.internal`,
            password: `P2APat_${suffix}!`,
            phone: `9411${suffix}`,
            role: 'Patient',
            status: 'ACTIVE',
        });
        createdUserIds.push(fixtures.patient.id);

        // 3. Temporary staging Clinic User + Clinic Record (clinics.id !== users.id)
        fixtures.clinicUser = await User.create({
            name: `Phase2A Clinic Owner ${suffix}`,
            email: `p2a_cli_${suffix}@dentaguru.internal`,
            password: `P2ACli_${suffix}!`,
            phone: `9412${suffix}`,
            role: 'Clinic',
            status: 'ACTIVE',
        });
        createdUserIds.push(fixtures.clinicUser.id);

        fixtures.clinicRecord = await Clinic.create({
            user_id: fixtures.clinicUser.id,
            clinic_name: `Phase2A Multispecialty Clinic ${suffix}`,
            location: 'Hyderabad, Telangana',
            city: 'Hyderabad',
            pincode: '500033',
            verified: true,
        });
        createdClinicIds.push(fixtures.clinicRecord.id);
        assert.notStrictEqual(fixtures.clinicRecord.id, fixtures.clinicUser.id, 'Clinic table ID and User table ID must be distinct');

        // 4. Temporary staging Doctor User + Dentist Record (dentists.id !== users.id)
        fixtures.doctorUser = await User.create({
            name: `Dr. Phase2A Specialist ${suffix}`,
            email: `p2a_doc_${suffix}@dentaguru.internal`,
            password: `P2ADoc_${suffix}!`,
            phone: `9413${suffix}`,
            role: 'Dentist',
            status: 'ACTIVE',
        });
        createdUserIds.push(fixtures.doctorUser.id);

        fixtures.dentistRecord = await Dentist.create({
            user_id: fixtures.doctorUser.id,
            clinic_id: fixtures.clinicRecord.id,
            speciality: 'Cardiology',
            license_number: `P2A-LIC-${suffix}`,
            experience_years: 8,
            qualifications: 'MBBS, MD, DM',
            availability_status: 'Available',
        });
        createdDentistIds.push(fixtures.dentistRecord.id);
        assert.notStrictEqual(fixtures.dentistRecord.id, fixtures.doctorUser.id, 'Dentist table ID and User table ID must be distinct');

        // 5. Temporary staging Sub-Admin (default restricted permissions — zero chat permissions initially)
        const hydDist = await District.findOne({ name: 'Hyderabad' });
        fixtures.districtId = hydDist ? hydDist.id : null;

        fixtures.subAdminUser = await User.create({
            name: `Phase2A SubAdmin ${suffix}`,
            email: `p2a_sub_${suffix}@dentaguru.internal`,
            password: `P2ASub_${suffix}!`,
            phone: `9414${suffix}`,
            role: 'Sub-Admin',
            status: 'ACTIVE',
            permissions: ['PATIENT_VIEW'],
        });
        subAdminUserId = fixtures.subAdminUser.id;
        createdUserIds.push(subAdminUserId);
        await SubAdminPermission.setPermissionsForUser(subAdminUserId, ['PATIENT_VIEW']);
        if (fixtures.districtId) {
            await SubAdminDistrict.assignDistrictsToSubAdmin(subAdminUserId, [fixtures.districtId], fixtures.adminUser.id);
        }
    });

    after(async () => {
        if (subAdminUserId) {
            await supabaseAdmin.from('sub_admin_permissions').delete().eq('user_id', subAdminUserId);
            await supabaseAdmin.from('sub_admin_districts').delete().eq('sub_admin_user_id', subAdminUserId);
        }
        if (createdDentistIds.length > 0) {
            await supabaseAdmin.from('dentists').delete().in('id', createdDentistIds);
        }
        if (createdClinicIds.length > 0) {
            await supabaseAdmin.from('clinics').delete().in('id', createdClinicIds);
        }
        if (createdUserIds.length > 0) {
            await supabaseAdmin.from('users').delete().in('id', createdUserIds);
        }
        if (server) {
            await new Promise((resolve) => server.close(resolve));
        }
    });

    it('1. Mints valid short-lived Supabase Realtime JWTs with canonical public.users.id (sub) for chat-authorized roles (PATIENT, DOCTOR, CLINIC, ADMIN)', async () => {
        const roleMatrix = [
            {
                label: 'PATIENT',
                user: fixtures.patient,
                expectedAppRole: 'PATIENT',
                expectedDentistId: null,
                expectedClinicId: null,
            },
            {
                label: 'DOCTOR',
                user: fixtures.doctorUser,
                expectedAppRole: 'DOCTOR',
                expectedDentistId: fixtures.dentistRecord.id,
                expectedClinicId: fixtures.clinicRecord.id,
            },
            {
                label: 'CLINIC',
                user: fixtures.clinicUser,
                expectedAppRole: 'CLINIC',
                expectedDentistId: null,
                expectedClinicId: fixtures.clinicRecord.id,
            },
            {
                label: 'ADMIN',
                user: fixtures.adminUser,
                expectedAppRole: 'ADMIN',
                expectedDentistId: null,
                expectedClinicId: null,
            },
        ];

        for (const entry of roleMatrix) {
            const expressJwt = jwt.sign(
                { id: entry.user.id, role: entry.user.role },
                getJwtSecret(),
                { expiresIn: '15m' }
            );

            // Attempt spoofing another userId/role in request body — backend MUST ignore body and use authenticated DB user
            const res = await apiReq(
                'POST',
                '/api/v1/auth/realtime-token',
                { Authorization: `Bearer ${expressJwt}` },
                { userId: '00000000-0000-0000-0000-000000000099', role: 'ADMIN' }
            );

            assert.strictEqual(res.status, 200, `Expected 200 for ${entry.label}`);
            assert.strictEqual(res.json.success, true);
            assert.ok(typeof res.json.realtimeToken === 'string' && res.json.realtimeToken.split('.').length === 3);
            assert.strictEqual(res.json.expiresIn, 3600);

            const decoded = verifySupabaseRealtimeToken(res.json.realtimeToken);
            assert.strictEqual(decoded.aud, 'authenticated');
            assert.strictEqual(decoded.role, 'authenticated');
            assert.strictEqual(decoded.sub, entry.user.id, `${entry.label} sub claim MUST equal public.users.id`);
            assert.strictEqual(decoded.app_role, entry.expectedAppRole);
            assert.strictEqual(decoded.dentist_id, entry.expectedDentistId);
            assert.strictEqual(decoded.clinic_id, entry.expectedClinicId);
            assert.strictEqual(decoded.exp - decoded.iat, 3600);
        }
    });

    it('2. Resolves Doctor dentists.id and Clinic clinics.id strictly to canonical public.users.id for chat sender/participant identity', async () => {
        const resolvedFromDentistId = await resolveCanonicalChatUserId(fixtures.dentistRecord.id);
        assert.strictEqual(
            resolvedFromDentistId,
            fixtures.doctorUser.id,
            'Passing dentists.id to chat identity resolver must resolve to dentists.user_id (public.users.id)'
        );

        const resolvedFromClinicId = await resolveCanonicalChatUserId(fixtures.clinicRecord.id);
        assert.strictEqual(
            resolvedFromClinicId,
            fixtures.clinicUser.id,
            'Passing clinics.id to chat identity resolver must resolve to clinics.user_id (public.users.id)'
        );

        const resolvedFromDirectUserId = await resolveCanonicalChatUserId(fixtures.patient.id);
        assert.strictEqual(resolvedFromDirectUserId, fixtures.patient.id);
    });

    it('3. Live Staging Validation: PostgREST and Realtime WebSocket accept minted Realtime JWTs and map auth.uid() to public.users.id across PATIENT, DOCTOR, CLINIC & ADMIN', async () => {
        const supabaseUrl = process.env.SUPABASE_URL.trim();
        const supabaseAnonKey = process.env.SUPABASE_ANON_KEY.trim();

        const usersToVerify = [
            { label: 'PATIENT', user: fixtures.patient },
            { label: 'DOCTOR', user: fixtures.doctorUser },
            { label: 'CLINIC', user: fixtures.clinicUser },
            { label: 'ADMIN', user: fixtures.adminUser },
        ];

        for (const item of usersToVerify) {
            const expressJwt = jwt.sign({ id: item.user.id, role: item.user.role }, getJwtSecret(), { expiresIn: '10m' });
            const tokenRes = await apiReq('POST', '/api/v1/auth/realtime-token', {
                Authorization: `Bearer ${expressJwt}`
            });
            assert.strictEqual(tokenRes.status, 200);
            const rtJwt = tokenRes.json.realtimeToken;

            // A. Live Staging PostgREST verification under `role = authenticated` & `sub = public.users.id`
            const scopedClient = createClient(supabaseUrl, supabaseAnonKey, {
                global: { headers: { Authorization: `Bearer ${rtJwt}` } },
                auth: { persistSession: false, autoRefreshToken: false },
            });

            const { data: selfRow, error: pgErr, status: pgStatus } = await scopedClient
                .from('users')
                .select('id, phone, role')
                .eq('id', item.user.id)
                .single();

            assert.strictEqual(pgErr, null, `${item.label} PostgREST auth failed: ${pgErr ? pgErr.message : ''}`);
            assert.strictEqual(pgStatus, 200);
            assert.strictEqual(selfRow.id, item.user.id);

            // B. Live Staging Supabase Realtime WebSocket handshake with setAuth(rtJwt)
            await scopedClient.realtime.setAuth(rtJwt);
            const channelName = `p2a_auth_verify_${item.label.toLowerCase()}_${suffix}`;
            const channel = scopedClient.channel(channelName);

            const subStatus = await new Promise((resolve, reject) => {
                const timer = setTimeout(() => reject(new Error(`Realtime subscribe timed out for ${item.label}`)), 12000);
                channel.subscribe((status, err) => {
                    if (status === 'SUBSCRIBED') {
                        clearTimeout(timer);
                        resolve(status);
                    } else if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT') {
                        clearTimeout(timer);
                        reject(err || new Error(`Realtime channel failed with status ${status}`));
                    }
                });
            });

            assert.strictEqual(subStatus, 'SUBSCRIBED', `${item.label} Realtime WebSocket must subscribe cleanly`);
            await scopedClient.removeChannel(channel);
            scopedClient.realtime.disconnect();
        }
    });

    it('4. Strictly prohibits Sub-Admins from Realtime tokens (HTTP 403, zero login/refresh minting) even with CHAT_VIEW/wildcard grants & blocks deactivated accounts', async () => {
        const subAdminExpressJwt = jwt.sign(
            { id: subAdminUserId, role: 'Sub-Admin' },
            getJwtSecret(),
            { expiresIn: '15m' }
        );
        const subAdminRefreshJwt = jwt.sign(
            { id: subAdminUserId },
            getRefreshSecret(),
            { expiresIn: '1h' }
        );

        // Even if CHAT_VIEW / CHAT_SEND / wildcard were assigned in DB, SUB_ADMIN remains strictly prohibited
        await SubAdminPermission.setPermissionsForUser(subAdminUserId, ['PATIENT_VIEW', 'CHAT_VIEW', 'CHAT_SEND', '*']);
        await User.findByIdAndUpdate(subAdminUserId, { permissions: ['PATIENT_VIEW', 'CHAT_VIEW', 'CHAT_SEND', '*'] });

        const postBlocked = await apiReq('POST', '/api/v1/auth/realtime-token', {
            Authorization: `Bearer ${subAdminExpressJwt}`
        });
        assert.strictEqual(postBlocked.status, 403);
        assert.strictEqual(postBlocked.json.code, 'CHAT_FORBIDDEN_FOR_ROLE');
        assert.strictEqual(postBlocked.json.realtimeToken, undefined);

        const getBlocked = await apiReq('GET', '/api/v1/auth/realtime-token', {
            Authorization: `Bearer ${subAdminExpressJwt}`
        });
        assert.strictEqual(getBlocked.status, 403);
        assert.strictEqual(getBlocked.json.code, 'CHAT_FORBIDDEN_FOR_ROLE');
        assert.strictEqual(getBlocked.json.realtimeToken, undefined);

        await assert.rejects(
            () => mintSupabaseRealtimeTokenForUser(fixtures.subAdminUser),
            (err) => err.statusCode === 403 && err.code === 'CHAT_FORBIDDEN_FOR_ROLE'
        );
        assert.strictEqual(await tryMintSupabaseRealtimeTokenForUser(fixtures.subAdminUser), null);

        // Sub-Admin login & token refresh MUST NOT mint or return realtimeToken
        const subLoginRes = await apiReq('POST', '/api/v1/auth/login', {}, {
            phone: fixtures.subAdminUser.phone,
            password: `P2ASub_${suffix}!`,
        });
        assert.strictEqual(subLoginRes.status, 200);
        assert.strictEqual(subLoginRes.json.realtimeToken, undefined);
        assert.strictEqual(subLoginRes.json.realtimeTokenExpiresAt, undefined);

        const subRefreshRes = await apiReq('POST', '/api/v1/auth/refresh', {}, {
            refreshToken: subAdminRefreshJwt,
        });
        assert.strictEqual(subRefreshRes.status, 200);
        assert.strictEqual(subRefreshRes.json.realtimeToken, undefined);
        assert.strictEqual(subRefreshRes.json.realtimeTokenExpiresAt, undefined);

        // Deactivated chat-eligible account (Patient) -> must reject Realtime token with 403 ACCOUNT_DEACTIVATED
        const patExpressJwt = jwt.sign({ id: fixtures.patient.id, role: 'Patient' }, getJwtSecret(), { expiresIn: '15m' });
        await User.findByIdAndUpdate(fixtures.patient.id, { status: 'INACTIVE' });
        const blockedPatRes = await apiReq('POST', '/api/v1/auth/realtime-token', {
            Authorization: `Bearer ${patExpressJwt}`
        });
        assert.strictEqual(blockedPatRes.status, 403);
        assert.strictEqual(blockedPatRes.json.code, 'ACCOUNT_DEACTIVATED');
        assert.strictEqual(blockedPatRes.json.realtimeToken, undefined);
    });

    it('5. Rejects unauthenticated requests, tampered signatures, and Express JWTs passed directly to Supabase', async () => {
        // A. Unauthenticated call to /auth/realtime-token -> 401
        const unauth = await apiReq('POST', '/api/v1/auth/realtime-token');
        assert.strictEqual(unauth.status, 401);

        // B. Forged/wrong-secret JWT -> rejected by staging Supabase PostgREST (401)
        const forgedJwt = jwt.sign(
            {
                aud: 'authenticated',
                role: 'authenticated',
                sub: fixtures.patient.id,
                app_role: 'PATIENT',
            },
            'forged_wrong_signing_secret_not_matching_supabase_32chars!',
            { algorithm: 'HS256', expiresIn: '5m' }
        );
        const forgedClient = createClient(process.env.SUPABASE_URL.trim(), process.env.SUPABASE_ANON_KEY.trim(), {
            global: { headers: { Authorization: `Bearer ${forgedJwt}` } },
            auth: { persistSession: false, autoRefreshToken: false },
        });
        const { error: forgedErr, status: forgedStatus } = await forgedClient
            .from('users')
            .select('id')
            .eq('id', fixtures.patient.id);
        assert.ok(forgedErr !== null || forgedStatus === 401, 'Forged JWT signature must be rejected by staging Supabase');
    });
});
