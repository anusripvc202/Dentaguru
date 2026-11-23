/**
 * End-to-End Integration Test:
 * Task 1: Clinic Dashboard Multiple Doctor Registration (One Clinic -> Many Doctors)
 * Task 2: Exact Medical Specialty Persistence (Dentistry, Cardiology, Dermatology, Neurology, Orthopedics, General Medicine)
 * Task 3 & 5: Persistence, Find Doctors Specialty Filtering & Cleanup
 */
require('dotenv').config();
const assert = require('assert');
const http = require('http');
const app = require('../src/app');
const { supabaseAdmin } = require('../src/config/supabase');

let BASE_URL = process.env.API_BASE_URL || '';

async function jsonFetch(url, options = {}) {
    const res = await fetch(url, {
        ...options,
        headers: {
            'Content-Type': 'application/json',
            ...(options.headers || {}),
        },
    });
    const text = await res.text();
    let body = {};
    try {
        body = text ? JSON.parse(text) : {};
    } catch (_) {
        body = { raw: text };
    }
    return { status: res.status, body };
}

(async () => {
    const ts = Date.now().toString().slice(-6);
    const createdUserIds = [];
    const createdDentistIds = [];
    let createdClinicId = null;
    let localServer = null;

    if (!BASE_URL) {
        localServer = http.createServer(app);
        await new Promise((resolve) => localServer.listen(0, '127.0.0.1', resolve));
        BASE_URL = `http://127.0.0.1:${localServer.address().port}/api/v1`;
    }

    try {
        console.log(`🧪 Starting Multi-Doctor & Specialty Persistence E2E Test (ts=${ts})...`);

        // 1. Register a multi-specialty Clinic
        const clinicPhone = `91${ts}00`;
        const clinicReg = await jsonFetch(`${BASE_URL}/auth/register`, {
            method: 'POST',
            body: JSON.stringify({
                name: `MultiSpec Clinic Admin ${ts}`,
                phone: clinicPhone,
                role: 'Clinic',
                clinicName: `Apex MultiSpec Clinic ${ts}`,
                city: 'Hyderabad',
                pincode: '500032',
            }),
        });
        assert.strictEqual(clinicReg.status, 201, `Clinic register failed: ${JSON.stringify(clinicReg.body)}`);
        createdUserIds.push(clinicReg.body.user.id);
        createdClinicId = clinicReg.body.user.clinicId;
        assert.ok(createdClinicId, 'Clinic registration must return clinicId');
        const clinicToken = clinicReg.body.accessToken;

        // 2. Register 6 doctors under this same clinic with different specialties,
        //    omitting email/city on some and reusing placeholder licenseNumber 'MED-LIC-REG' on others.
        const doctorsSpecPlan = [
            { name: `Dr. Ravi ${ts}`, phone: `92${ts}01`, specialty: 'Cardiology', omitEmail: true, omitCity: true, license: '' },
            { name: `Dr. Priya ${ts}`, phone: `92${ts}02`, specialty: 'Dermatology', omitEmail: true, omitCity: true, license: '' },
            { name: `Dr. Kumar ${ts}`, phone: `92${ts}03`, specialty: 'Dentistry', omitEmail: true, omitCity: false, license: 'MED-LIC-REG' },
            { name: `Dr. Anitha ${ts}`, phone: `92${ts}04`, specialty: 'Neurology', omitEmail: false, omitCity: true, license: 'MED-LIC-REG' },
            { name: `Dr. Suresh ${ts}`, phone: `92${ts}05`, specialty: 'Orthopedics', omitEmail: false, omitCity: false, license: '' },
            { name: `Dr. Meena ${ts}`, phone: `92${ts}06`, specialty: 'General Medicine', omitEmail: true, omitCity: true, license: '' },
        ];

        for (let i = 0; i < doctorsSpecPlan.length; i++) {
            const specItem = doctorsSpecPlan[i];
            const payload = {
                name: specItem.name,
                phone: specItem.phone,
                ...(specItem.omitEmail ? {} : { email: `doc_${i}_${ts}@gshealth.test` }),
                specialty: specItem.specialty,
                ...(specItem.omitCity ? {} : { city: 'Hyderabad' }),
                ...(specItem.license ? { licenseNumber: specItem.license } : {}),
                clinicName: `Apex MultiSpec Clinic ${ts}`,
            };

            const res = await jsonFetch(`${BASE_URL}/clinics/${createdClinicId}/doctors`, {
                method: 'POST',
                headers: { Authorization: `Bearer ${clinicToken}` },
                body: JSON.stringify(payload),
            });

            assert.strictEqual(res.status, 201, `Doctor ${i + 1} (${specItem.specialty}) failed: ${JSON.stringify(res.body)}`);
            assert.strictEqual(res.body.success, true);
            assert.strictEqual(res.body.doctor.specialty, specItem.specialty, `Expected specialty ${specItem.specialty}, got ${res.body.doctor.specialty}`);
            assert.strictEqual(res.body.doctor.clinic_id, createdClinicId);
            assert.ok(res.body.doctor.specialty_id, `Expected non-null specialty_id for ${specItem.specialty}`);

            createdDentistIds.push(res.body.doctor.id);
            if (res.body.doctor.user_id) createdUserIds.push(res.body.doctor.user_id);
        }

        // Also test /auth/register directly with clinicName & non-dental specialties without licenseNumber
        // Both legacy client role:'Dentist' and role:'DOCTOR' must persist users.role === 'DOCTOR' and exact specialty
        const authRegisterCases = [
            { name: `Dr. Cardio Auth ${ts}`, phone: `92${ts}07`, reqRole: 'Dentist', specialty: 'Cardiology' },
            { name: `Dr. Neuro Auth ${ts}`, phone: `92${ts}08`, reqRole: 'DOCTOR', specialty: 'Neurology' },
            { name: `Dr. GenMed Auth ${ts}`, phone: `92${ts}09`, reqRole: 'Dentist', specialty: 'General Medicine' },
            { name: `Dr. Ortho Auth ${ts}`, phone: `92${ts}10`, reqRole: 'DOCTOR', specialty: 'Orthopedics' },
        ];

        const authRegisteredDoctors = [];
        for (const c of authRegisterCases) {
            const authDocReg = await jsonFetch(`${BASE_URL}/auth/register`, {
                method: 'POST',
                body: JSON.stringify({
                    name: c.name,
                    phone: c.phone,
                    password: `Pass_${ts}!`,
                    role: c.reqRole,
                    specialty: c.specialty,
                    clinicName: `Apex MultiSpec Clinic ${ts}`,
                    city: 'Hyderabad',
                    licenseNumber: 'MED-LIC-REG',
                }),
            });
            assert.strictEqual(authDocReg.status, 201, `Auth doctor register (${c.specialty}) failed: ${JSON.stringify(authDocReg.body)}`);
            assert.strictEqual(authDocReg.body.user.role, 'DOCTOR', `Expected user.role === 'DOCTOR' for ${c.specialty}, got ${authDocReg.body.user.role}`);
            assert.strictEqual(authDocReg.body.user.specialty, c.specialty, `Expected user.specialty === ${c.specialty}, got ${authDocReg.body.user.specialty}`);
            assert.strictEqual(authDocReg.body.user.clinicId, createdClinicId);
            createdUserIds.push(authDocReg.body.user.id);
            createdDentistIds.push(authDocReg.body.user.dentistId);
            authRegisteredDoctors.push({ ...c, id: authDocReg.body.user.id, dentistId: authDocReg.body.user.dentistId, accessToken: authDocReg.body.accessToken });
        }

        // 2b. Verify login re-fetch & PUT /dentists/:id/profile do NOT reset specialty to 'Dentist'
        const targetProfileDoc = authRegisteredDoctors[0]; // Cardiology
        const loginCheck = await jsonFetch(`${BASE_URL}/auth/login`, {
            method: 'POST',
            body: JSON.stringify({
                phone: targetProfileDoc.phone,
                password: `Pass_${ts}!`,
                role: 'Dentist', // even if client sends legacy role filter, logged-in user stays DOCTOR + Cardiology
            }),
        });
        assert.strictEqual(loginCheck.status, 200, `Doctor login failed: ${JSON.stringify(loginCheck.body)}`);
        assert.strictEqual(loginCheck.body.user.role, 'DOCTOR');
        assert.strictEqual(loginCheck.body.user.specialty, 'Cardiology');

        // Profile edit WITHOUT specialty must preserve Cardiology (never overwrite with 'Dentist')
        const profileEditKeep = await jsonFetch(`${BASE_URL}/dentists/${targetProfileDoc.dentistId}/profile`, {
            method: 'PUT',
            headers: { Authorization: `Bearer ${targetProfileDoc.accessToken}` },
            body: JSON.stringify({
                name: `${targetProfileDoc.name} Updated`,
                city: 'Bengaluru',
            }),
        });
        assert.strictEqual(profileEditKeep.status, 200, `Profile update failed: ${JSON.stringify(profileEditKeep.body)}`);
        assert.strictEqual(profileEditKeep.body.doctor.specialty, 'Cardiology', `Profile edit without specialty reset specialty to ${profileEditKeep.body.doctor.specialty}`);

        // Profile edit WITH new specialty (Dermatology) must update accurately
        const profileEditSpec = await jsonFetch(`${BASE_URL}/dentists/${targetProfileDoc.dentistId}/profile`, {
            method: 'PUT',
            headers: { Authorization: `Bearer ${targetProfileDoc.accessToken}` },
            body: JSON.stringify({
                specialty: 'Dermatology',
            }),
        });
        assert.strictEqual(profileEditSpec.status, 200);
        assert.strictEqual(profileEditSpec.body.doctor.specialty, 'Dermatology');

        // Restore Cardiology so clinic total assertions match
        await jsonFetch(`${BASE_URL}/dentists/${targetProfileDoc.dentistId}/profile`, {
            method: 'PUT',
            headers: { Authorization: `Bearer ${targetProfileDoc.accessToken}` },
            body: JSON.stringify({ specialty: 'Cardiology' }),
        });

        // 3. Verify GET /clinics/:clinicId/doctors returns ALL 10 doctors with exact specialties
        const clinicDocsRes = await jsonFetch(`${BASE_URL}/clinics/${createdClinicId}/doctors?includeUnavailable=true`, {
            headers: { Authorization: `Bearer ${clinicToken}` },
        });
        assert.strictEqual(clinicDocsRes.status, 200);
        assert.strictEqual(clinicDocsRes.body.doctors.length, 10, `Expected 10 doctors in clinic, got ${clinicDocsRes.body.doctors.length}`);

        for (const item of [...doctorsSpecPlan, ...authRegisterCases]) {
            const match = clinicDocsRes.body.doctors.find(d => d.name.includes(item.name));
            assert.ok(match, `Missing doctor ${item.name} in clinic doctor list`);
            assert.strictEqual(match.specialty, item.specialty);
            assert.notStrictEqual(match.specialty, 'Dentist');
        }

        // 4. Verify Find Doctors filtering by each specialty returns matching doctors strictly
        for (const spec of ['Cardiology', 'Dermatology', 'Neurology', 'Orthopedics', 'General Medicine', 'Dentistry']) {
            const qRes = await jsonFetch(`${BASE_URL}/dentists?specialty=${encodeURIComponent(spec)}&search=${encodeURIComponent(ts)}`);
            assert.strictEqual(qRes.status, 200);
            const names = (qRes.body.dentists || []).map(d => d.name);
            assert.ok(names.length >= 1, `Expected >=1 doctor for specialty filter ${spec}, got 0`);
            for (const d of (qRes.body.dentists || [])) {
                assert.notStrictEqual(d.specialty, 'Dentist', `Doctor ${d.name} must not have raw 'Dentist' specialty`);
            }
        }

        // 5. Verify direct Supabase persistence in BOTH 'users' (role === 'DOCTOR') and 'dentists' tables
        const doctorUserIds = createdUserIds.filter(id => id !== clinicReg.body.user.id);
        const { data: dbUsers, error: dbUserErr } = await supabaseAdmin
            .from('users')
            .select('id, name, role')
            .in('id', doctorUserIds);
        assert.ifError(dbUserErr);
        assert.strictEqual(dbUsers.length, 10, `Expected 10 doctor rows in users table, got ${dbUsers.length}`);
        for (const u of dbUsers) {
            assert.strictEqual(u.role, 'DOCTOR', `Expected DB users.role === 'DOCTOR' for ${u.name}, got ${u.role}`);
        }

        const { data: dbRows, error: dbErr } = await supabaseAdmin
            .from('dentists')
            .select('id, user_id, clinic_id, speciality, specialty_id, department, license_number')
            .eq('clinic_id', createdClinicId);
        assert.ifError(dbErr);
        assert.strictEqual(dbRows.length, 10, `Expected 10 rows in Supabase dentists table, got ${dbRows.length}`);
        for (const r of dbRows) {
            assert.notStrictEqual(r.speciality, 'Dentist', `DB dentists.speciality must not be 'Dentist' (got ${r.speciality})`);
            assert.ok(r.specialty_id, `DB dentists.specialty_id must be populated for ${r.speciality}`);
        }
        const distinctLicenses = new Set(dbRows.map(r => r.license_number));
        assert.strictEqual(distinctLicenses.size, 10, 'Each doctor must have a unique license_number in DB');

        console.log('✅ All Multi-Doctor & Specialty Persistence E2E assertions passed!');
    } finally {
        // Clean up test rows cleanly
        for (const dId of createdDentistIds) {
            try { await supabaseAdmin.from('dentists').delete().eq('id', dId); } catch (_) { }
        }
        try { await supabaseAdmin.from('notifications').delete().ilike('message', `%${ts}%`); } catch (_) { }
        if (createdClinicId) {
            try { await supabaseAdmin.from('clinics').delete().eq('id', createdClinicId); } catch (_) { }
        }
        for (const uId of createdUserIds) {
            try { await supabaseAdmin.from('users').delete().eq('id', uId); } catch (_) { }
        }
        if (localServer) {
            localServer.closeAllConnections?.();
            await new Promise((resolve) => localServer.close(resolve));
        }
    }
})();
