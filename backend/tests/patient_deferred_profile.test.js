/**
 * Backend Integration & Unit Tests: DentaGuru Patient Login & Deferred Profile Completion
 * Exercises canonical phone lookup (zero duplicate accounts), Patient OTP auto-create,
 * unchanged Doctor/Clinic unregistered OTP flows, GET/PUT /auth/patient/profile validation & persistence,
 * and Schema column safety (excluding unsupported `address` column from `users` updates)
 * without mutating the live cloud database.
 */
const assert = require('assert');
const http = require('http');
const path = require('path');
const express = require('express');
const crypto = require('crypto');

try {
    require('dotenv').config({ path: path.resolve(__dirname, '../.env') });
} catch (_) { }

process.env.JWT_SECRET = process.env.JWT_SECRET || 'test_jwt_secret_deferred_profile_9f3a2c1e8b';
process.env.REFRESH_SECRET = process.env.REFRESH_SECRET || 'test_refresh_secret_deferred_profile_4d7e1a9b';

const Schemas = require('../src/models/Schemas');
const { User, Dentist, Clinic, canonicalPhone10 } = Schemas;
const { otpStoreService } = require('../src/services/otpStoreService');
const { supabase, supabaseAdmin } = require('../src/config/supabase');
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
                try {
                    json = data ? JSON.parse(data) : {};
                } catch (_) {
                    json = { raw: data };
                }
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

    // Snapshot originals for clean restoration
    const origFindByMobile = User.findByMobile;
    const origFindOne = User.findOne;
    const origFindById = User.findById;
    const origCreate = User.create;
    const origFindByIdAndUpdate = User.findByIdAndUpdate;
    const origVerifyOtp = otpStoreService.verifyOtp;
    const origSupabaseGetUser = supabase.auth.getUser;
    const origDentistFindById = Dentist.findById;
    const origDentistFindOne = Dentist.findOne;
    const origClinicFindOne = Clinic.findOne;

    const usersById = new Map();
    let createCallCount = 0;

    const installInMemoryMocks = () => {
        User.findByMobile = async (rawPhone) => {
            const c10 = canonicalPhone10(rawPhone);
            if (!c10) return null;
            for (const u of usersById.values()) {
                if (canonicalPhone10(u.phone) === c10) {
                    return { ...u };
                }
            }
            return null;
        };

        User.findOne = async (query = {}) => {
            if (query.phone) return User.findByMobile(query.phone);
            if (query.email) {
                const target = String(query.email).trim().toLowerCase();
                for (const u of usersById.values()) {
                    if (String(u.email || '').trim().toLowerCase() === target) {
                        return { ...u };
                    }
                }
            }
            if (query.id) return usersById.get(query.id) ? { ...usersById.get(query.id) } : null;
            return null;
        };

        User.findById = async (id) => {
            const found = usersById.get(id);
            return found ? { ...found } : null;
        };

        User.create = async (userData) => {
            createCallCount++;
            const id = userData.id || crypto.randomUUID();
            const created = {
                id,
                name: userData.name || 'Patient',
                email: userData.email || '',
                password: userData.password || '',
                phone: userData.phone || '',
                role: userData.role || 'Patient',
                city: userData.city || '',
                pincode: userData.pincode || '',
                age: userData.age || '',
                gender: userData.gender || '',
                blood_group: userData.blood_group || '',
                emergency_contact: userData.emergency_contact || '',
                languages: userData.languages || ['English'],
                referral_code: userData.referral_code || '',
                device_token: userData.device_token || null,
                biometric_token: userData.biometric_token ?? null,
                refresh_tokens: Array.isArray(userData.refresh_tokens) ? [...userData.refresh_tokens] : [],
                status: userData.status || 'ACTIVE',
                created_at: new Date().toISOString(),
            };
            usersById.set(id, created);
            return { ...created };
        };

        User.findByIdAndUpdate = async (id, updateData) => {
            const existing = usersById.get(id);
            if (!existing) return null;
            let meta = {};
            if (existing.device_token && String(existing.device_token).trim().startsWith('{')) {
                try { meta = JSON.parse(existing.device_token); } catch (_) { }
            }
            const nextMeta = { ...meta };
            if (updateData.age !== undefined) nextMeta.age = updateData.age;
            if (updateData.gender !== undefined) nextMeta.gender = updateData.gender;
            if (updateData.pincode !== undefined) nextMeta.pincode = updateData.pincode;
            if (updateData.city !== undefined) nextMeta.city = updateData.city;
            if (updateData.address !== undefined) nextMeta.address = updateData.address;
            if (updateData.blood_group !== undefined) nextMeta.bloodGroup = updateData.blood_group;
            if (updateData.emergency_contact !== undefined) nextMeta.emergencyContact = updateData.emergency_contact;
            if (updateData.languages !== undefined) nextMeta.languages = updateData.languages;
            if (updateData.biometric_token !== undefined) nextMeta.profilePhoto = updateData.biometric_token;

            const updated = {
                ...existing,
                ...updateData,
                device_token: JSON.stringify(nextMeta),
            };
            delete updated.address;
            usersById.set(id, updated);
            return { ...updated };
        };

        otpStoreService.verifyOtp = async (_identifier, code) => {
            if (String(code || '').trim() === '654321') {
                return { valid: true, message: 'Verified' };
            }
            return { valid: false, message: 'Invalid or expired OTP.' };
        };

        supabase.auth.getUser = async () => ({
            data: { user: null },
            error: { message: 'Local JWT test override' },
        });

        Dentist.findById = async () => null;
        Dentist.findOne = async () => null;
        Clinic.findOne = async () => null;
    };

    const app = express();
    app.use(express.json());
    app.use('/api/v1', apiRoutes);
    const server = await new Promise((resolve) => {
        const s = app.listen(0, '127.0.0.1', () => resolve(s));
    });
    const addr = server.address();
    const baseUrl = `http://127.0.0.1:${addr.port}/api/v1`;

    let createdPatientId = null;
    let patientJwt = null;

    try {
        installInMemoryMocks();

        await asyncTest('1. canonicalPhone10 normalizes +91, 91, 0, spaced and hyphenated formats consistently', async () => {
            assert.strictEqual(canonicalPhone10('9063663180'), '9063663180');
            assert.strictEqual(canonicalPhone10('+919063663180'), '9063663180');
            assert.strictEqual(canonicalPhone10('+91 90636-63180'), '9063663180');
            assert.strictEqual(canonicalPhone10('919063663180'), '9063663180');
            assert.strictEqual(canonicalPhone10('09063663180'), '9063663180');
        });

        await asyncTest('2. New Patient OTP login (autoCreatePatient=true) creates 1 minimal Patient row & returns isProfileComplete=false', async () => {
            const res = await requestJson(baseUrl, 'POST', '/auth/otp/verify', {
                phone: '9876501234',
                code: '654321',
                role: 'Patient',
                autoCreatePatient: true,
            });
            assert.strictEqual(res.status, 200);
            assert.strictEqual(res.body.success, true);
            assert.strictEqual(res.body.isNewPatient, true);
            assert.ok(res.body.accessToken, 'accessToken must be returned for Patient dashboard entry');
            assert.ok(res.body.user && res.body.user.id, 'user payload must contain id');
            assert.strictEqual(res.body.user.role, 'Patient');
            assert.strictEqual(res.body.user.phone, '9876501234');
            assert.strictEqual(res.body.user.isProfileComplete, false);
            assert.strictEqual(createCallCount, 1);

            createdPatientId = res.body.user.id;
            patientJwt = res.body.accessToken;
        });

        await asyncTest('3. Repeat OTP login with +91 98765-01234 reuses existing Patient ID without duplicate creation', async () => {
            const res = await requestJson(baseUrl, 'POST', '/auth/otp/verify', {
                phone: '+91 98765-01234',
                code: '654321',
                role: 'Patient',
                autoCreatePatient: true,
            });
            assert.strictEqual(res.status, 200);
            assert.strictEqual(res.body.success, true);
            assert.strictEqual(res.body.user.id, createdPatientId);
            assert.strictEqual(res.body.user.isProfileComplete, false);
            assert.strictEqual(createCallCount, 1, 'Must NOT create a second user row for +91 variant');
            assert.strictEqual(usersById.size, 1);
        });

        await asyncTest('4. Unregistered Doctor & Clinic OTP verification does NOT auto-create a Patient account', async () => {
            const docRes = await requestJson(baseUrl, 'POST', '/auth/otp/verify', {
                phone: '9876509988',
                code: '654321',
                role: 'Dentist',
                autoCreatePatient: false,
            });
            assert.strictEqual(docRes.status, 200);
            assert.strictEqual(docRes.body.success, true);
            assert.strictEqual(docRes.body.verified, true);
            assert.strictEqual(docRes.body.user, undefined);
            assert.strictEqual(docRes.body.accessToken, undefined);

            const clinicRes = await requestJson(baseUrl, 'POST', '/auth/otp/verify', {
                phone: '9876509977',
                code: '654321',
                role: 'Clinic',
                autoCreatePatient: false,
            });
            assert.strictEqual(clinicRes.status, 200);
            assert.strictEqual(clinicRes.body.success, true);
            assert.strictEqual(clinicRes.body.user, undefined);
            assert.strictEqual(createCallCount, 1);
        });

        await asyncTest('5. GET /auth/patient/profile enforces JWT auth and reflects incomplete state accurately', async () => {
            const unauth = await requestJson(baseUrl, 'GET', '/auth/patient/profile');
            assert.strictEqual(unauth.status, 401);

            const authed = await requestJson(baseUrl, 'GET', '/auth/patient/profile', null, {
                Authorization: `Bearer ${patientJwt}`,
            });
            assert.strictEqual(authed.status, 200);
            assert.strictEqual(authed.body.success, true);
            assert.strictEqual(authed.body.user.id, createdPatientId);
            assert.strictEqual(authed.body.user.isProfileComplete, false);
        });

        await asyncTest('6. PUT /auth/patient/profile allows optional photo, validates 6-digit pincode, age 1-120, gender, preserves photo on null & rejects non-Patient role', async () => {
            const validPhoto = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

            const noPhoto = await requestJson(baseUrl, 'PUT', '/auth/patient/profile', {
                pincode: '500081',
                age: '28',
                gender: 'Female',
            }, { Authorization: `Bearer ${patientJwt}` });
            assert.strictEqual(noPhoto.status, 200);
            assert.strictEqual(noPhoto.body.success, true);
            assert.strictEqual(noPhoto.body.user.isProfileComplete, true);

            // Setting a photo and then updating with profilePhoto: null must preserve existing photo
            const withPhoto = await requestJson(baseUrl, 'PUT', '/auth/patient/profile', {
                profilePhoto: validPhoto,
                pincode: '500081',
                age: '28',
                gender: 'Female',
            }, { Authorization: `Bearer ${patientJwt}` });
            assert.strictEqual(withPhoto.status, 200);
            assert.strictEqual(withPhoto.body.user.profilePhoto, validPhoto);

            const nullPhotoUpdate = await requestJson(baseUrl, 'PUT', '/auth/patient/profile', {
                profilePhoto: null,
                pincode: '500081',
                age: '29',
                gender: 'Female',
            }, { Authorization: `Bearer ${patientJwt}` });
            assert.strictEqual(nullPhotoUpdate.status, 200);
            assert.strictEqual(nullPhotoUpdate.body.user.profilePhoto, validPhoto);

            const badPin = await requestJson(baseUrl, 'PUT', '/auth/patient/profile', {
                profilePhoto: validPhoto,
                pincode: '500',
                age: '28',
                gender: 'Female',
            }, { Authorization: `Bearer ${patientJwt}` });
            assert.strictEqual(badPin.status, 400);

            const badAgeZero = await requestJson(baseUrl, 'PUT', '/auth/patient/profile', {
                profilePhoto: validPhoto,
                pincode: '500081',
                age: '0',
                gender: 'Female',
            }, { Authorization: `Bearer ${patientJwt}` });
            assert.strictEqual(badAgeZero.status, 400);

            const badAgeHigh = await requestJson(baseUrl, 'PUT', '/auth/patient/profile', {
                profilePhoto: validPhoto,
                pincode: '500081',
                age: '125',
                gender: 'Female',
            }, { Authorization: `Bearer ${patientJwt}` });
            assert.strictEqual(badAgeHigh.status, 400);

            const noGender = await requestJson(baseUrl, 'PUT', '/auth/patient/profile', {
                profilePhoto: validPhoto,
                pincode: '500081',
                age: '28',
                gender: '',
            }, { Authorization: `Bearer ${patientJwt}` });
            assert.strictEqual(noGender.status, 400);

            // Seed a Dentist user and verify 403 rejection
            const docUser = await User.create({
                id: 'doc-role-guard-1',
                name: 'Dr. Test',
                phone: '9876507777',
                email: 'docguard@test.in',
                role: 'Dentist',
            });
            const jwt = require('jsonwebtoken');
            const { getJwtSecret } = require('../src/config/secrets');
            const docToken = jwt.sign({ id: docUser.id, role: 'Dentist' }, getJwtSecret(), { expiresIn: '1h' });
            const nonPatientRes = await requestJson(baseUrl, 'PUT', '/auth/patient/profile', {
                profilePhoto: validPhoto,
                pincode: '500081',
                age: '35',
                gender: 'Male',
            }, { Authorization: `Bearer ${docToken}` });
            assert.strictEqual(nonPatientRes.status, 403);
            assert.strictEqual(nonPatientRes.body.message, 'Patient profile endpoint can only update Patient accounts.');
            usersById.delete(docUser.id);
        });

        await asyncTest('7. Valid PUT /auth/patient/profile updates existing Patient ID in-place and persists across reload/re-login', async () => {
            const validPhoto = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
            const saveRes = await requestJson(baseUrl, 'PUT', '/auth/patient/profile', {
                name: 'Meera Nair',
                profilePhoto: validPhoto,
                pincode: '500081',
                age: '28',
                gender: 'Female',
                city: 'Hyderabad',
            }, { Authorization: `Bearer ${patientJwt}` });

            assert.strictEqual(saveRes.status, 200);
            assert.strictEqual(saveRes.body.success, true);
            assert.strictEqual(saveRes.body.user.id, createdPatientId);
            assert.strictEqual(saveRes.body.user.name, 'Meera Nair');
            assert.strictEqual(saveRes.body.user.pincode, '500081');
            assert.strictEqual(saveRes.body.user.age, '28');
            assert.strictEqual(saveRes.body.user.gender, 'Female');
            assert.strictEqual(saveRes.body.user.isProfileComplete, true);
            assert.strictEqual(usersById.size, 1, 'Zero duplicate users may exist');

            // Subsequent GET returns complete profile
            const reloadRes = await requestJson(baseUrl, 'GET', '/auth/patient/profile', null, {
                Authorization: `Bearer ${patientJwt}`,
            });
            assert.strictEqual(reloadRes.status, 200);
            assert.strictEqual(reloadRes.body.user.id, createdPatientId);
            assert.strictEqual(reloadRes.body.user.isProfileComplete, true);
            assert.strictEqual(reloadRes.body.user.pincode, '500081');

            // Re-login with OTP returns complete profile
            const reloginRes = await requestJson(baseUrl, 'POST', '/auth/otp/verify', {
                phone: '9876501234',
                code: '654321',
                role: 'Patient',
                autoCreatePatient: true,
            });
            assert.strictEqual(reloginRes.status, 200);
            assert.strictEqual(reloginRes.body.user.id, createdPatientId);
            assert.strictEqual(reloginRes.body.user.isProfileComplete, true);
        });

        await asyncTest('8. Schemas.User.findByIdAndUpdate strips unsupported address column from Supabase users update payload', async () => {
            const mockFindByIdAndUpdate = User.findByIdAndUpdate;
            User.findByIdAndUpdate = origFindByIdAndUpdate;
            const origFrom = supabaseAdmin.from;
            const capturedUpdates = [];

            supabaseAdmin.from = (tableName) => ({
                select: () => ({
                    eq: () => ({
                        maybeSingle: async () => ({
                            data: { device_token: '{}' },
                            error: null,
                        }),
                    }),
                }),
                update: (payload) => {
                    capturedUpdates.push({ tableName, payload });
                    return {
                        eq: () => ({
                            select: () => ({
                                maybeSingle: async () => ({
                                    data: {
                                        id: 'pat-schema-1',
                                        pincode: '500081',
                                        age: '28',
                                        gender: 'Female',
                                        biometric_token: payload.biometric_token || 'data:image/png;base64,abc',
                                        device_token: payload.device_token || '{}',
                                    },
                                    error: null,
                                }),
                            }),
                            then: (cb) => Promise.resolve(cb({ error: null })),
                        }),
                    };
                },
            });

            try {
                const updated = await User.findByIdAndUpdate('pat-schema-1', {
                    pincode: '500081',
                    age: '28',
                    gender: 'Female',
                    address: 'Madhapur Lane 2',
                    biometric_token: 'data:image/png;base64,abc',
                });
                assert.ok(capturedUpdates.length >= 1);
                assert.strictEqual('address' in capturedUpdates[0].payload, false, 'Unsupported address column must be stripped from users SQL update');
                assert.strictEqual(capturedUpdates[0].payload.pincode, '500081');
                assert.strictEqual(capturedUpdates[0].payload.age, '28');
                assert.strictEqual(capturedUpdates[0].payload.gender, 'Female');
                assert.strictEqual(updated.address, 'Madhapur Lane 2', 'address must still unpack from device_token metadata');
            } finally {
                supabaseAdmin.from = origFrom;
                User.findByIdAndUpdate = mockFindByIdAndUpdate;
            }
        });

        await asyncTest('9. Patient POST /auth/register & PUT /auth/patient/profile accept null/empty image, pincode, and age (and also accept all optional fields)', async () => {
            // 9A. Patient registration without image, age, and pincode
            const regNoOpts = await requestJson(baseUrl, 'POST', '/auth/register', {
                name: 'Sita Devi',
                phone: '9876511001',
                role: 'Patient',
                city: 'Hyderabad',
                age: null,
                pincode: '',
                profilePhoto: null,
            });
            assert.strictEqual(regNoOpts.status, 201);
            assert.strictEqual(regNoOpts.body.success, true);
            assert.strictEqual(regNoOpts.body.user.age, '');
            assert.strictEqual(regNoOpts.body.user.pincode, '');
            assert.strictEqual(regNoOpts.body.user.profilePhoto, null);

            // 9B. Patient profile completion without image, pincode, or age (Gender only)
            const patToken = regNoOpts.body.accessToken;
            const completeMinimal = await requestJson(baseUrl, 'PUT', '/auth/patient/profile', {
                gender: 'Female',
                pincode: '',
                age: null,
                profilePhoto: null,
                completeProfile: true,
            }, { Authorization: `Bearer ${patToken}` });
            assert.strictEqual(completeMinimal.status, 200);
            assert.strictEqual(completeMinimal.body.success, true);
            assert.strictEqual(completeMinimal.body.user.isProfileComplete, true);

            // 9C. Patient registration WITH all optional fields
            const regWithAll = await requestJson(baseUrl, 'POST', '/auth/register', {
                name: 'Lakshmi Rao',
                phone: '9876511002',
                role: 'Patient',
                city: 'Hyderabad',
                age: '31',
                gender: 'Female',
                pincode: '500081',
                profilePhoto: 'https://ojinzcdldwugpnxrnjcq.supabase.co/storage/v1/object/public/dentaguru-storage/avatars/patients/p1.png',
            });
            assert.strictEqual(regWithAll.status, 201);
            assert.strictEqual(regWithAll.body.user.age, '31');
            assert.strictEqual(regWithAll.body.user.pincode, '500081');
            assert.ok(regWithAll.body.user.profilePhoto.includes('/dentaguru-storage/'));
        });

        await asyncTest('10. Doctor POST /auth/register uploads profile image to Supabase Storage, saves URL, succeeds without image, and handles upload failures clearly', async () => {
            const supabaseStorageService = require('../src/services/supabaseStorageService');
            const origUploadFile = supabaseStorageService.uploadFile;
            const origDentistCreate = Dentist.create;
            const origNotifCreate = Schemas.Notification.create;
            let capturedUploadArgs = null;
            const mockPublicUrl = 'https://ojinzcdldwugpnxrnjcq.supabase.co/storage/v1/object/public/dentaguru-storage/avatars/doctors/test_doc.png';
            const tinyPngDataUri = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

            Dentist.create = async (doc) => ({ id: `dent-${Date.now()}`, ...doc });
            Schemas.Notification.create = async () => ({ id: 'notif-mock' });

            try {
                // 10A. Upload succeeds -> URL saved to users.biometric_token and returned in user.profilePhoto
                supabaseStorageService.uploadFile = async (buf, filePath, mime) => {
                    capturedUploadArgs = { size: buf.length, filePath, mime };
                    return { success: true, path: filePath, publicUrl: mockPublicUrl, bucket: 'dentaguru-storage' };
                };

                const docWithPhoto = await requestJson(baseUrl, 'POST', '/auth/register', {
                    name: 'Dr. Kavitha Menon',
                    phone: '9876522001',
                    role: 'Dentist',
                    city: 'Hyderabad',
                    specialty: 'Cardiology',
                    qualification: 'MBBS, MD',
                    experienceYears: 7,
                    profilePhoto: tinyPngDataUri,
                });
                assert.strictEqual(docWithPhoto.status, 201);
                assert.strictEqual(docWithPhoto.body.success, true);
                assert.ok(capturedUploadArgs && capturedUploadArgs.filePath.startsWith('avatars/doctors/'));
                assert.strictEqual(capturedUploadArgs.mime, 'image/png');
                assert.strictEqual(docWithPhoto.body.user.profilePhoto, mockPublicUrl);

                // 10B. Doctor registration WITHOUT image succeeds cleanly (optional)
                const docNoPhoto = await requestJson(baseUrl, 'POST', '/auth/register', {
                    name: 'Dr. Vikram Patel',
                    phone: '9876522002',
                    role: 'Dentist',
                    city: 'Hyderabad',
                    specialty: 'General Medicine',
                    profilePhoto: null,
                });
                assert.strictEqual(docNoPhoto.status, 201);
                assert.strictEqual(docNoPhoto.body.success, true);
                assert.strictEqual(docNoPhoto.body.user.profilePhoto, null);

                // 10C. Upload failure returns clear 502 error with PROFILE_IMAGE_UPLOAD_FAILED
                supabaseStorageService.uploadFile = async () => {
                    throw new Error('Bucket temporarily unavailable');
                };
                const docFailedUpload = await requestJson(baseUrl, 'POST', '/auth/register', {
                    name: 'Dr. Upload Fail',
                    phone: '9876522003',
                    role: 'Dentist',
                    city: 'Hyderabad',
                    specialty: 'Dentistry',
                    profilePhoto: tinyPngDataUri,
                });
                assert.strictEqual(docFailedUpload.status, 502);
                assert.strictEqual(docFailedUpload.body.success, false);
                assert.strictEqual(docFailedUpload.body.code, 'PROFILE_IMAGE_UPLOAD_FAILED');
                assert.ok(String(docFailedUpload.body.message || '').toLowerCase().includes('upload'));
            } finally {
                supabaseStorageService.uploadFile = origUploadFile;
                Dentist.create = origDentistCreate;
                Schemas.Notification.create = origNotifCreate;
            }
        });

        await asyncTest('11. PUT /doctors/:id/profile uploads new doctor photo to Supabase Storage, saves URL, removes photo, and handles upload failure', async () => {
            const supabaseStorageService = require('../src/services/supabaseStorageService');
            const jwt = require('jsonwebtoken');
            const { getJwtSecret } = require('../src/config/secrets');
            const origUploadFile = supabaseStorageService.uploadFile;
            const origDentistUpdate = Dentist.findByIdAndUpdate;
            const origDentistFindByIdLocal = Dentist.findById;
            const tinyPngDataUri = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
            const editedPublicUrl = 'https://ojinzcdldwugpnxrnjcq.supabase.co/storage/v1/object/public/dentaguru-storage/avatars/doctors/edited_doc.png';

            const docUser = await User.create({
                id: 'doc-edit-usr-1',
                name: 'Dr. Edit Test',
                phone: '9876533001',
                email: 'docedit@test.in',
                role: 'DOCTOR',
            });
            const docToken = jwt.sign({ id: docUser.id, role: 'DOCTOR' }, getJwtSecret(), { expiresIn: '1h' });

            const dentistRec = {
                id: 'dent-edit-1',
                user_id: docUser.id,
                speciality: 'Cardiology',
                qualifications: 'MBBS, MD',
                availability_status: 'Available',
            };
            Dentist.findByIdAndUpdate = async (_id, data) => {
                Object.assign(dentistRec, data);
                return { ...dentistRec, users: await User.findById(docUser.id) };
            };
            Dentist.findById = async () => ({ ...dentistRec, users: await User.findById(docUser.id) });

            try {
                // 11A. Upload succeeds on Edit Profile
                supabaseStorageService.uploadFile = async (_buf, filePath) => ({
                    success: true,
                    path: filePath,
                    publicUrl: editedPublicUrl,
                    bucket: 'dentaguru-storage',
                });
                const editUpload = await requestJson(baseUrl, 'PUT', '/doctors/dent-edit-1/profile', {
                    name: 'Dr. Edit Updated',
                    profilePhoto: tinyPngDataUri,
                }, { Authorization: `Bearer ${docToken}` });
                assert.strictEqual(editUpload.status, 200);
                assert.strictEqual(editUpload.body.success, true);
                assert.strictEqual(editUpload.body.doctor.profilePhoto, editedPublicUrl);
                assert.strictEqual((await User.findById(docUser.id)).biometric_token, editedPublicUrl);

                // 11B. Remove photo clears users.biometric_token
                const editRemove = await requestJson(baseUrl, 'PUT', '/doctors/dent-edit-1/profile', {
                    removeProfilePhoto: true,
                }, { Authorization: `Bearer ${docToken}` });
                assert.strictEqual(editRemove.status, 200);
                assert.strictEqual(editRemove.body.doctor.profilePhoto, null);
                assert.strictEqual((await User.findById(docUser.id)).biometric_token, null);

                // 11C. Upload failure returns 502 PROFILE_IMAGE_UPLOAD_FAILED
                supabaseStorageService.uploadFile = async () => { throw new Error('Storage down'); };
                const editFail = await requestJson(baseUrl, 'PUT', '/doctors/dent-edit-1/profile', {
                    profilePhoto: tinyPngDataUri,
                }, { Authorization: `Bearer ${docToken}` });
                assert.strictEqual(editFail.status, 502);
                assert.strictEqual(editFail.body.code, 'PROFILE_IMAGE_UPLOAD_FAILED');
            } finally {
                supabaseStorageService.uploadFile = origUploadFile;
                Dentist.findByIdAndUpdate = origDentistUpdate;
                Dentist.findById = origDentistFindByIdLocal;
            }
        });
    } finally {
        User.findByMobile = origFindByMobile;
        User.findOne = origFindOne;
        User.findById = origFindById;
        User.create = origCreate;
        User.findByIdAndUpdate = origFindByIdAndUpdate;
        otpStoreService.verifyOtp = origVerifyOtp;
        supabase.auth.getUser = origSupabaseGetUser;
        Dentist.findById = origDentistFindById;
        Dentist.findOne = origDentistFindOne;
        Clinic.findOne = origClinicFindOne;
        await new Promise((resolve) => server.close(resolve));
    }

    console.log('\n=================================================');
    console.log(`DEFERRED PROFILE BACKEND RESULTS: ${passed} Passed, ${failed} Failed`);
    console.log('=================================================');
    process.exit(failed > 0 ? 1 : 0);
}

runTests().catch((err) => {
    console.error('Unhandled test runner error:', err);
    process.exit(1);
});
