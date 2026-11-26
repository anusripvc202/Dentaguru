/**
 * Backend Integration Tests: Patient Referral Status & Role Permissions
 * Verifies all 7 scenarios without mutating the live Supabase database:
 * 1. Patient creates referral -> Pending
 * 2. Patient sees Pending in /referrals/my-referrals
 * 3. Assigned Doctor accepts -> Accepted
 * 4. Patient refreshes /referrals/my-referrals -> sees Accepted
 * 5. Assigned Doctor rejects -> Rejected
 * 6. Patient refreshes /referrals/my-referrals -> sees Rejected
 * 7. Patient CANNOT accept/reject own referral (HTTP 403) & unassigned Doctor CANNOT accept/reject (HTTP 403)
 */
const assert = require('assert');
const http = require('http');
const path = require('path');
const express = require('express');
const jwt = require('jsonwebtoken');

try {
    require('dotenv').config({ path: path.resolve(__dirname, '../.env') });
} catch (_) { }

process.env.JWT_SECRET = process.env.JWT_SECRET || 'test_jwt_secret_referral_rbac_9f3a2c1e8b';
process.env.REFRESH_SECRET = process.env.REFRESH_SECRET || 'test_refresh_secret_referral_rbac_4d7e1a9b';

const Schemas = require('../src/models/Schemas');
const { User, Dentist, Clinic, Referral, Appointment, Notification } = Schemas;
const { supabase } = require('../src/config/supabase');
const { getJwtSecret } = require('../src/config/secrets');
const apiRoutes = require('../src/routes/api');

function requestJson(baseUrl, method, routePath, body = null, headers = {}) {
    return new Promise((resolve, reject) => {
        const payload = body ? JSON.stringify(body) : null;
        const req = http.request(`${baseUrl}${routePath}`, {
            method,
            headers: {
                ...(payload ? { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(payload) } : {}),
                ...headers,
            },
        }, (res) => {
            let data = '';
            res.on('data', (chunk) => { data += chunk; });
            res.on('end', () => {
                let json = {};
                try { json = data ? JSON.parse(data) : {}; } catch (_) { json = { raw: data }; }
                resolve({ status: res.statusCode, body: json });
            });
        });
        req.on('error', reject);
        if (payload) req.write(payload);
        req.end();
    });
}

async function runTests() {
    let passed = 0;
    let failed = 0;

    async function asyncTest(name, fn) {
        try {
            await fn();
            console.log(`✓ ${name}`);
            passed++;
        } catch (e) {
            console.error(`✗ ${name}:`, e.stack || e.message);
            failed++;
        }
    }

    const users = new Map([
        ['pat-1', { id: 'pat-1', name: 'Anu Sharma', phone: '9876500001', email: 'anu@test.in', role: 'Patient' }],
        ['pat-2', { id: 'pat-2', name: 'Other Patient', phone: '9876500002', email: 'other@test.in', role: 'Patient' }],
        ['doc-u-1', { id: 'doc-u-1', name: 'Dr. Sri', phone: '9876511111', email: 'sri@test.in', role: 'DOCTOR' }],
        ['doc-u-2', { id: 'doc-u-2', name: 'Dr. Other', phone: '9876522222', email: 'otherdoc@test.in', role: 'DOCTOR' }],
    ]);
    const dentists = new Map([
        ['doc-1', { id: 'doc-1', user_id: 'doc-u-1', name: 'Dr. Sri', speciality: 'Cardiology', availability_status: 'Available', users: users.get('doc-u-1') }],
        ['doc-2', { id: 'doc-2', user_id: 'doc-u-2', name: 'Dr. Other', speciality: 'Dentistry', availability_status: 'Available', users: users.get('doc-u-2') }],
    ]);
    const referrals = new Map();
    let refSeq = 0;

    // Backup originals
    const orig = {
        userFindById: User.findById,
        userFindOne: User.findOne,
        userCreate: User.create,
        dentistFindById: Dentist.findById,
        dentistFindOne: Dentist.findOne,
        clinicFindById: Clinic.findById,
        clinicFindOne: Clinic.findOne,
        refCreate: Referral.create,
        refFind: Referral.find,
        refFindById: Referral.findById,
        refFindByIdAndUpdate: Referral.findByIdAndUpdate,
        refCheckDup: Referral.checkDuplicate,
        apptCreate: Appointment.create,
        notifCreate: Notification.create,
        supaGetUser: supabase.auth.getUser,
    };

    const app = express();
    app.use(express.json());
    app.use('/api/v1', apiRoutes);
    const server = await new Promise((resolve) => {
        const s = app.listen(0, '127.0.0.1', () => resolve(s));
    });
    const baseUrl = `http://127.0.0.1:${server.address().port}/api/v1`;

    const pat1Token = jwt.sign({ id: 'pat-1', role: 'Patient' }, getJwtSecret(), { expiresIn: '1h' });
    const pat2Token = jwt.sign({ id: 'pat-2', role: 'Patient' }, getJwtSecret(), { expiresIn: '1h' });
    const doc1Token = jwt.sign({ id: 'doc-u-1', role: 'DOCTOR' }, getJwtSecret(), { expiresIn: '1h' });
    const doc2Token = jwt.sign({ id: 'doc-u-2', role: 'DOCTOR' }, getJwtSecret(), { expiresIn: '1h' });

    try {
        supabase.auth.getUser = async () => ({ data: { user: null }, error: { message: 'Local JWT test' } });
        User.findById = async (id) => users.get(id) || null;
        User.findOne = async (q = {}) => {
            for (const u of users.values()) {
                if (q.phone && u.phone === q.phone) return u;
                if (q.email && u.email === q.email) return u;
            }
            return null;
        };
        User.create = async (u) => {
            const id = u.id || `usr-${users.size + 1}`;
            const rec = { id, ...u };
            users.set(id, rec);
            return rec;
        };
        Dentist.findById = async (id) => dentists.get(id) || null;
        Dentist.findOne = async (q = {}) => {
            for (const d of dentists.values()) {
                if (q.user_id && d.user_id === q.user_id) return d;
                if (q.id && d.id === q.id) return d;
            }
            return null;
        };
        Clinic.findById = async () => null;
        Clinic.findOne = async () => null;
        Appointment.create = async (a) => ({ id: `appt-${Date.now()}`, ...a });
        Notification.create = async (n) => ({ id: `notif-${Date.now()}`, ...n });
        Referral.checkDuplicate = async () => null;
        Referral.create = async (data) => {
            refSeq++;
            const id = `ref-test-${refSeq}`;
            const rec = { id, created_at: new Date().toISOString(), updated_at: new Date().toISOString(), ...data };
            referrals.set(id, rec);
            return { ...rec };
        };
        Referral.find = async (query = {}) => {
            const list = Array.from(referrals.values());
            if (query.doctor_id && query.doctor_id.$in) {
                const allowed = new Set(query.doctor_id.$in);
                return list.filter((r) => allowed.has(r.doctor_id) || allowed.has(r.assigned_doctor_id));
            }
            return list;
        };
        Referral.findById = async (id) => (referrals.has(id) ? { ...referrals.get(id) } : null);
        Referral.findByIdAndUpdate = async (id, update) => {
            const existing = referrals.get(id);
            if (!existing) return null;
            const next = { ...existing, ...update, updated_at: new Date().toISOString() };
            referrals.set(id, next);
            return { ...next };
        };

        let refId1 = null;
        let refId2 = null;

        await asyncTest('1 & 2. Patient creates a referral and sees Pending status in My Referrals (scoped only to own referrals)', async () => {
            const createRes = await requestJson(baseUrl, 'POST', '/referrals', {
                referredPatientName: 'Satya Rao',
                referredPatientMobile: '9876599001',
                referredPatientAge: '34',
                referredPatientGender: 'Male',
                referredPatientCity: 'Hyderabad',
                referredPatientPincode: '500081',
                referredPatientLocation: 'Madhapur',
                requiredSpecialist: 'Cardiology',
                clinicalComplaint: 'Chest pain evaluation',
                doctorId: 'doc-1',
            }, { Authorization: `Bearer ${pat1Token}` });

            assert.strictEqual(createRes.status, 201);
            assert.strictEqual(createRes.body.success, true);
            assert.strictEqual(createRes.body.referral.status, 'Pending');
            refId1 = createRes.body.referral.id;

            const myRefsRes = await requestJson(baseUrl, 'GET', '/referrals/my-referrals', null, {
                Authorization: `Bearer ${pat1Token}`,
            });
            assert.strictEqual(myRefsRes.status, 200);
            assert.strictEqual(myRefsRes.body.referrals.length, 1);
            assert.strictEqual(myRefsRes.body.referrals[0].status, 'Pending');

            // Another patient cannot spoof ?userId=pat-1 to read Pat 1's referrals
            const otherPatientRes = await requestJson(baseUrl, 'GET', '/referrals/my-referrals?userId=pat-1', null, {
                Authorization: `Bearer ${pat2Token}`,
            });
            assert.strictEqual(otherPatientRes.status, 200);
            assert.strictEqual(otherPatientRes.body.referrals.length, 0);
        });

        await asyncTest('7. Patient cannot accept/reject own referral (403) and unassigned Doctor cannot accept/reject (403)', async () => {
            const patAccept = await requestJson(baseUrl, 'PATCH', `/referrals/${refId1}/accept`, {}, {
                Authorization: `Bearer ${pat1Token}`,
            });
            assert.strictEqual(patAccept.status, 403);
            assert.strictEqual(patAccept.body.success, false);

            const patReject = await requestJson(baseUrl, 'PATCH', `/referrals/${refId1}/reject`, {
                rejectionReason: 'Trying to self-reject',
            }, { Authorization: `Bearer ${pat1Token}` });
            assert.strictEqual(patReject.status, 403);

            const patStatus = await requestJson(baseUrl, 'PATCH', `/referrals/${refId1}/status`, {
                status: 'Accepted',
            }, { Authorization: `Bearer ${pat1Token}` });
            assert.strictEqual(patStatus.status, 403);

            // Unassigned Doctor B also blocked (403)
            const wrongDocAccept = await requestJson(baseUrl, 'PATCH', `/referrals/${refId1}/accept`, {}, {
                Authorization: `Bearer ${doc2Token}`,
            });
            assert.strictEqual(wrongDocAccept.status, 403);

            // Status must remain Pending
            assert.strictEqual(referrals.get(refId1).status, 'Pending');
        });

        await asyncTest('3 & 4. Assigned Doctor accepts referral -> Patient sees Accepted after refresh', async () => {
            const docAccept = await requestJson(baseUrl, 'PATCH', `/referrals/${refId1}/accept`, {}, {
                Authorization: `Bearer ${doc1Token}`,
            });
            assert.strictEqual(docAccept.status, 200);
            assert.strictEqual(docAccept.body.success, true);
            assert.strictEqual(docAccept.body.referral.status, 'Accepted');

            const refreshed = await requestJson(baseUrl, 'GET', '/referrals/my-referrals', null, {
                Authorization: `Bearer ${pat1Token}`,
            });
            assert.strictEqual(refreshed.status, 200);
            const found = refreshed.body.referrals.find((r) => r.id === refId1);
            assert.ok(found);
            assert.strictEqual(found.status, 'Accepted');
        });

        await asyncTest('5 & 6. Assigned Doctor rejects referral -> Patient sees Rejected with reason after refresh', async () => {
            const create2 = await requestJson(baseUrl, 'POST', '/referrals', {
                referredPatientName: 'Lakshmi Devi',
                referredPatientMobile: '9876599002',
                referredPatientAge: '42',
                referredPatientGender: 'Female',
                referredPatientCity: 'Hyderabad',
                referredPatientPincode: '500081',
                referredPatientLocation: 'Kondapur',
                requiredSpecialist: 'Cardiology',
                clinicalComplaint: 'BP check',
                doctorId: 'doc-1',
            }, { Authorization: `Bearer ${pat1Token}` });
            assert.strictEqual(create2.status, 201);
            refId2 = create2.body.referral.id;

            const docReject = await requestJson(baseUrl, 'PATCH', `/referrals/${refId2}/reject`, {
                rejectionReason: 'Doctor out of town this week',
            }, { Authorization: `Bearer ${doc1Token}` });
            assert.strictEqual(docReject.status, 200);
            assert.strictEqual(docReject.body.referral.status, 'Rejected');

            const refreshed = await requestJson(baseUrl, 'GET', '/referrals/my-referrals', null, {
                Authorization: `Bearer ${pat1Token}`,
            });
            assert.strictEqual(refreshed.status, 200);
            const found = refreshed.body.referrals.find((r) => r.id === refId2);
            assert.ok(found);
            assert.strictEqual(found.status, 'Rejected');
            assert.strictEqual(found.rejectionReason, 'Doctor out of town this week');
        });
    } finally {
        User.findById = orig.userFindById;
        User.findOne = orig.userFindOne;
        User.create = orig.userCreate;
        Dentist.findById = orig.dentistFindById;
        Dentist.findOne = orig.dentistFindOne;
        Clinic.findById = orig.clinicFindById;
        Clinic.findOne = orig.clinicFindOne;
        Referral.create = orig.refCreate;
        Referral.find = orig.refFind;
        Referral.findById = orig.refFindById;
        Referral.findByIdAndUpdate = orig.refFindByIdAndUpdate;
        Referral.checkDuplicate = orig.refCheckDup;
        Appointment.create = orig.apptCreate;
        Notification.create = orig.notifCreate;
        supabase.auth.getUser = orig.supaGetUser;
        server.close();
    }

    console.log('\n=================================================');
    console.log(`REFERRAL RBAC BACKEND RESULTS: ${passed} Passed, ${failed} Failed`);
    console.log('=================================================');
    process.exit(failed > 0 ? 1 : 0);
}

runTests().catch((err) => {
    console.error('Fatal test error:', err);
    process.exit(1);
});
