/**
 * Backend Integration Tests: Doctor Dashboard Zero-Dummy Data & Strict Doctor Isolation
 * Verifies all 5 scenarios without mutating live Supabase:
 * 1. Newly registered doctor with zero appointments gets 0 appointments & 0 calendar stats
 * 2. Doctor with 1 real patient appointment sees exactly 1 appointment
 * 3. Doctor with multiple real appointments sees accurate upcoming/confirmed/rescheduled/completed records
 * 4. Doctor viewing completed visits sees accurate completed status & counts
 * 5. Doctor A cannot see Doctor B's appointments (and ?dentistId=<Doctor B> returns HTTP 403)
 */
const assert = require('assert');
const http = require('http');
const path = require('path');
const express = require('express');
const jwt = require('jsonwebtoken');

try {
    require('dotenv').config({ path: path.resolve(__dirname, '../.env') });
} catch (_) { }

process.env.JWT_SECRET = process.env.JWT_SECRET || 'test_jwt_secret_doc_iso_9f3a2c1e8b';
process.env.REFRESH_SECRET = process.env.REFRESH_SECRET || 'test_refresh_secret_doc_iso_4d7e1a9b';

const Schemas = require('../src/models/Schemas');
const { User, Dentist, Clinic, Appointment, Referral, MedicalRecord } = Schemas;
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
        ['usr-doc-new', { id: 'usr-doc-new', name: 'Dr. New Doctor', phone: '9876500101', email: 'newdoc@test.in', role: 'DOCTOR' }],
        ['usr-doc-b', { id: 'usr-doc-b', name: 'Dr. Existing B', phone: '9876500102', email: 'docb@test.in', role: 'DOCTOR' }],
        ['usr-pat-1', { id: 'usr-pat-1', name: 'Anu Sharma', phone: '9876500201', email: 'anu@test.in', role: 'Patient' }],
        ['usr-pat-2', { id: 'usr-pat-2', name: 'Kiran Rao', phone: '9876500202', email: 'kiran@test.in', role: 'Patient' }],
    ]);
    const dentists = new Map([
        ['dent-new', { id: 'dent-new', user_id: 'usr-doc-new', name: 'Dr. New Doctor', speciality: 'Cardiology', users: users.get('usr-doc-new') }],
        ['dent-b', { id: 'dent-b', user_id: 'usr-doc-b', name: 'Dr. Existing B', speciality: 'Dentistry', users: users.get('usr-doc-b') }],
    ]);

    const todayIso = new Date().toISOString().split('T')[0];
    const appointmentsStore = [
        {
            id: 'appt-doc-b-1',
            patient_id: 'usr-pat-1',
            dentist_id: 'dent-b',
            appointment_date: todayIso,
            time_slot: '10:00 AM',
            treatment: 'Root Canal',
            status: 'CONFIRMED',
            patient: users.get('usr-pat-1'),
            dentist: dentists.get('dent-b'),
            created_at: new Date().toISOString(),
        },
        {
            id: 'appt-doc-b-2',
            patient_id: 'usr-pat-2',
            dentist_id: 'dent-b',
            appointment_date: todayIso,
            time_slot: '11:30 AM',
            treatment: 'Dental Checkup',
            status: 'COMPLETED',
            patient: users.get('usr-pat-2'),
            dentist: dentists.get('dent-b'),
            created_at: new Date().toISOString(),
        },
    ];

    const orig = {
        userFind: User.find,
        userFindById: User.findById,
        dentistFind: Dentist.find,
        dentistFindById: Dentist.findById,
        dentistFindOne: Dentist.findOne,
        apptFind: Appointment.find,
        refFind: Referral.find,
        recFind: MedicalRecord.find,
        supaGetUser: supabase.auth.getUser,
    };

    const app = express();
    app.use(express.json());
    app.use('/api/v1', apiRoutes);
    const server = await new Promise((resolve) => {
        const s = app.listen(0, '127.0.0.1', () => resolve(s));
    });
    const baseUrl = `http://127.0.0.1:${server.address().port}/api/v1`;

    const newDocToken = jwt.sign({ id: 'usr-doc-new', role: 'DOCTOR' }, getJwtSecret(), { expiresIn: '1h' });
    const docBToken = jwt.sign({ id: 'usr-doc-b', role: 'DOCTOR' }, getJwtSecret(), { expiresIn: '1h' });

    try {
        supabase.auth.getUser = async () => ({ data: { user: null }, error: { message: 'Local JWT test' } });
        User.find = async () => Array.from(users.values());
        User.findById = async (id) => users.get(id) || null;
        Dentist.find = async () => Array.from(dentists.values());
        Dentist.findById = async (id) => dentists.get(id) || null;
        Dentist.findOne = async (q = {}) => {
            for (const d of dentists.values()) {
                if (q.user_id && d.user_id === q.user_id) return d;
                if (q.id && d.id === q.id) return d;
            }
            return null;
        };
        Referral.find = async () => [];
        MedicalRecord.find = async () => [];
        Appointment.find = async (query = {}) => {
            let list = [...appointmentsStore];
            if (query.dentist_id) {
                const allowed = new Set(Array.isArray(query.dentist_id.$in) ? query.dentist_id.$in : [query.dentist_id]);
                list = list.filter((a) => allowed.has(a.dentist_id));
            }
            if (query.status) {
                list = list.filter((a) => String(a.status).toUpperCase() === String(query.status).toUpperCase());
            }
            return list;
        };

        await asyncTest('1. Newly registered doctor with zero appointments receives empty list & zero stats (no dummy or other doctor data)', async () => {
            const res = await requestJson(baseUrl, 'GET', '/appointments', null, {
                Authorization: `Bearer ${newDocToken}`,
            });
            assert.strictEqual(res.status, 200);
            assert.strictEqual(res.body.success, true);
            assert.strictEqual(res.body.count, 0);
            assert.strictEqual(res.body.appointments.length, 0);

            const cal = await requestJson(baseUrl, 'GET', `/visits-calendar/doctor?date=${todayIso}`, null, {
                Authorization: `Bearer ${newDocToken}`,
            });
            assert.strictEqual(cal.status, 200);
            assert.strictEqual(cal.body.selectedDateStats.totalAppointments, 0);
            assert.strictEqual(cal.body.selectedDateStats.completedConsultations, 0);
            assert.strictEqual(cal.body.visits.length, 0);
        });

        await asyncTest('5. Doctor A cannot see Doctor B appointments via ?dentistId= or calendar ?doctorId= (HTTP 403)', async () => {
            const spoofAppts = await requestJson(baseUrl, 'GET', '/appointments?dentistId=dent-b', null, {
                Authorization: `Bearer ${newDocToken}`,
            });
            assert.strictEqual(spoofAppts.status, 403);
            assert.strictEqual(spoofAppts.body.success, false);

            const spoofCal = await requestJson(baseUrl, 'GET', `/visits-calendar/doctor?doctorId=dent-b&date=${todayIso}`, null, {
                Authorization: `Bearer ${newDocToken}`,
            });
            assert.strictEqual(spoofCal.status, 403);
        });

        await asyncTest('2, 3 & 4. Doctor with 1 and multiple real appointments (including completed) sees only their own accurate records', async () => {
            // Add 1 real appointment for new doctor
            appointmentsStore.push({
                id: 'appt-new-1',
                patient_id: 'usr-pat-1',
                dentist_id: 'dent-new',
                appointment_date: todayIso,
                time_slot: '02:00 PM',
                treatment: 'ECG Checkup',
                status: 'CONFIRMED',
                patient: users.get('usr-pat-1'),
                dentist: dentists.get('dent-new'),
                created_at: new Date().toISOString(),
            });

            const oneRes = await requestJson(baseUrl, 'GET', '/appointments', null, {
                Authorization: `Bearer ${newDocToken}`,
            });
            assert.strictEqual(oneRes.status, 200);
            assert.strictEqual(oneRes.body.appointments.length, 1);
            assert.strictEqual(oneRes.body.appointments[0].id, 'appt-new-1');

            // Add a 2nd COMPLETED appointment for new doctor
            appointmentsStore.push({
                id: 'appt-new-2',
                patient_id: 'usr-pat-2',
                dentist_id: 'dent-new',
                appointment_date: todayIso,
                time_slot: '04:00 PM',
                treatment: 'Follow-up',
                status: 'COMPLETED',
                patient: users.get('usr-pat-2'),
                dentist: dentists.get('dent-new'),
                created_at: new Date().toISOString(),
            });

            const multiRes = await requestJson(baseUrl, 'GET', '/appointments', null, {
                Authorization: `Bearer ${newDocToken}`,
            });
            assert.strictEqual(multiRes.status, 200);
            assert.strictEqual(multiRes.body.appointments.length, 2);
            assert.ok(multiRes.body.appointments.some((a) => a.status === 'CONFIRMED'));
            assert.ok(multiRes.body.appointments.some((a) => a.status === 'COMPLETED'));
            assert.ok(multiRes.body.appointments.every((a) => a.dentist_id === 'dent-new'));

            // Doctor B still sees ONLY Doctor B's 2 appointments
            const docBRes = await requestJson(baseUrl, 'GET', '/appointments', null, {
                Authorization: `Bearer ${docBToken}`,
            });
            assert.strictEqual(docBRes.status, 200);
            assert.strictEqual(docBRes.body.appointments.length, 2);
            assert.ok(docBRes.body.appointments.every((a) => a.dentist_id === 'dent-b'));
        });
    } finally {
        User.find = orig.userFind;
        User.findById = orig.userFindById;
        Dentist.find = orig.dentistFind;
        Dentist.findById = orig.dentistFindById;
        Dentist.findOne = orig.dentistFindOne;
        Appointment.find = orig.apptFind;
        Referral.find = orig.refFind;
        MedicalRecord.find = orig.recFind;
        supabase.auth.getUser = orig.supaGetUser;
        server.close();
    }

    console.log('\n=================================================');
    console.log(`DOCTOR ISOLATION BACKEND RESULTS: ${passed} Passed, ${failed} Failed`);
    console.log('=================================================');
    process.exit(failed > 0 ? 1 : 0);
}

runTests().catch((err) => {
    console.error('Fatal test error:', err);
    process.exit(1);
});
