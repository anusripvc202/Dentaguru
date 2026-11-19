const test = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const app = require('../src/app');
const { supabaseAdmin } = require('../src/config/supabase');
const { User } = require('../src/models/Schemas');

test('GS HEALTH Referral Persistence & Visibility Across Patient, Referred Doctor & Admin Dashboards', async (t) => {
  const suffix = Date.now().toString().slice(-6);
  const cleanupUserIds = [];
  const cleanupDentistIds = [];
  const cleanupReferralIds = [];

  const server = http.createServer(app);
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const port = server.address().port;
  const baseUrl = `http://127.0.0.1:${port}/api/v1`;

  async function api(path, { method = 'GET', token = null, body = null } = {}) {
    const res = await fetch(`${baseUrl}${path}`, {
      method,
      headers: {
        'Content-Type': 'application/json',
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
      },
      body: body ? JSON.stringify(body) : undefined,
    });
    const text = await res.text();
    let json = {};
    try {
      json = JSON.parse(text);
    } catch (_) {}
    return { status: res.status, json };
  }

  t.after(async () => {
    server.closeAllConnections?.();
    await new Promise((resolve) => server.close(resolve));
    for (const rId of cleanupReferralIds) {
      try { await supabaseAdmin.from('referrals').delete().eq('id', rId); } catch (_) {}
    }
    try { await supabaseAdmin.from('notifications').delete().ilike('message', `%${suffix}%`); } catch (_) {}
    for (const dId of cleanupDentistIds) {
      try { await supabaseAdmin.from('doctor_availability').delete().eq('dentist_id', dId); } catch (_) {}
      try { await supabaseAdmin.from('dentists').delete().eq('id', dId); } catch (_) {}
    }
    for (const uId of cleanupUserIds) {
      try { await supabaseAdmin.from('notifications').delete().eq('recipient_id', uId); } catch (_) {}
      try { await supabaseAdmin.from('users').delete().eq('id', uId); } catch (_) {}
    }
  });

  const referrerPatientPhone = `91${suffix.padStart(8, '1').slice(0, 8)}`;
  const referredPatientPhone = `92${suffix.padStart(8, '2').slice(0, 8)}`;
  const refDoctorAPhone = `93${suffix.padStart(8, '3').slice(0, 8)}`;
  const targetDoctorBPhone = `94${suffix.padStart(8, '4').slice(0, 8)}`;
  const adminPhone = `95${suffix.padStart(8, '5').slice(0, 8)}`;

  const pass = 'RefPass@123';

  let referrerPatientId;
  let referrerPatientToken;
  let referredPatientId;
  let referredPatientToken;
  let refDoctorAUserId;
  let refDoctorADentistId;
  let refDoctorAToken;
  let targetDoctorBUserId;
  let targetDoctorBDentistId;
  let targetDoctorBToken;
  let adminToken;
  let referral1Id;
  let referral2Id;

  await t.test('Setup: Register Referrer Patient, Referred Patient, Referrer Doctor A, Target Specialist B & Admin', async () => {
    const p1 = await api('/auth/register', {
      method: 'POST',
      body: {
        name: `Referrer Patient ${suffix}`,
        email: `refpat1.${suffix}@gshealth.test`,
        phone: referrerPatientPhone,
        password: pass,
        role: 'Patient',
        city: 'Hyderabad',
        pincode: '500081',
      },
    });
    assert.ok(p1.status === 200 || p1.status === 201, `p1 status=${p1.status}: ${JSON.stringify(p1.json)}`);
    referrerPatientToken = p1.json.token || p1.json.accessToken;
    referrerPatientId = p1.json.user?.id;
    cleanupUserIds.push(referrerPatientId);

    const p2 = await api('/auth/register', {
      method: 'POST',
      body: {
        name: `Referred Patient ${suffix}`,
        email: `refpat2.${suffix}@gshealth.test`,
        phone: referredPatientPhone,
        password: pass,
        role: 'Patient',
        city: 'Hyderabad',
        pincode: '500081',
      },
    });
    assert.ok(p2.status === 200 || p2.status === 201, `p2 status=${p2.status}: ${JSON.stringify(p2.json)}`);
    referredPatientToken = p2.json.token || p2.json.accessToken;
    referredPatientId = p2.json.user?.id;
    cleanupUserIds.push(referredPatientId);

    const dA = await api('/auth/register', {
      method: 'POST',
      body: {
        name: `Dr. Referrer A ${suffix}`,
        email: `refdocA.${suffix}@gshealth.test`,
        phone: refDoctorAPhone,
        password: pass,
        role: 'Dentist',
        specialty: 'General Medicine',
        qualification: 'MBBS, MD',
        experienceYears: 6,
        city: 'Hyderabad',
        pincode: '500081',
      },
    });
    assert.ok(dA.status === 200 || dA.status === 201, `dA status=${dA.status}: ${JSON.stringify(dA.json)}`);
    refDoctorAToken = dA.json.token || dA.json.accessToken;
    refDoctorAUserId = dA.json.user?.id;
    refDoctorADentistId = dA.json.user?.dentistId || dA.json.dentist?.id;
    cleanupUserIds.push(refDoctorAUserId);
    cleanupDentistIds.push(refDoctorADentistId);

    const dB = await api('/auth/register', {
      method: 'POST',
      body: {
        name: `Dr. Target Specialist B ${suffix}`,
        email: `refdocB.${suffix}@gshealth.test`,
        phone: targetDoctorBPhone,
        password: pass,
        role: 'Dentist',
        specialty: 'Cardiology',
        qualification: 'MBBS, MD, DM',
        experienceYears: 11,
        city: 'Hyderabad',
        pincode: '500081',
      },
    });
    assert.ok(dB.status === 200 || dB.status === 201, `dB status=${dB.status}: ${JSON.stringify(dB.json)}`);
    targetDoctorBToken = dB.json.token || dB.json.accessToken;
    targetDoctorBUserId = dB.json.user?.id;
    targetDoctorBDentistId = dB.json.user?.dentistId || dB.json.dentist?.id;
    cleanupUserIds.push(targetDoctorBUserId);
    cleanupDentistIds.push(targetDoctorBDentistId);

    // Ensure Target Specialist B is VERIFIED & available
    await supabaseAdmin
      .from('dentists')
      .update({ verification_status: 'VERIFIED', is_available: true, status: 'Available' })
      .eq('id', targetDoctorBDentistId);

    const admUser = await User.create({
      name: `Admin RefTest ${suffix}`,
      email: `refadm.${suffix}@gshealth.test`,
      phone: adminPhone,
      password: pass,
      role: 'Admin',
      isVerified: true,
    });
    assert.ok(admUser?.id, 'Admin DB user creation failed');
    cleanupUserIds.push(admUser.id);

    const admLogin = await api('/auth/login', {
      method: 'POST',
      body: {
        email: `refadm.${suffix}@gshealth.test`,
        password: pass,
        role: 'Admin',
      },
    });
    assert.equal(admLogin.status, 200, `admLogin status=${admLogin.status}: ${JSON.stringify(admLogin.json)}`);
    adminToken = admLogin.json.token || admLogin.json.accessToken;
    assert.ok(adminToken, 'Admin login token missing');
  });

  await t.test('Scenario 1: Patient refers friend -> visible in Referrer Patient, Referred Patient, Referred Doctor & Admin + Notifications', async () => {
    const createRes = await api('/referrals', {
      method: 'POST',
      token: referrerPatientToken,
      body: {
        referrerPatientId,
        referredPatientName: `Referred Patient ${suffix}`,
        referredPatientMobile: referredPatientPhone,
        referredPatientAge: 29,
        referredPatientGender: 'Female',
        referredPatientCity: 'Hyderabad',
        referredPatientPincode: '500081',
        referredPatientLocation: 'Madhapur',
        requiredSpecialist: 'Cardiology',
        clinicalComplaint: 'Persistent chest tightness for 4 days',
        doctorId: targetDoctorBDentistId,
      },
    });

    assert.equal(createRes.status, 201, `Create referral failed: ${JSON.stringify(createRes.json)}`);
    assert.equal(createRes.json.success, true);
    referral1Id = createRes.json.referral?.id;
    assert.ok(referral1Id, 'Referral 1 ID missing');
    cleanupReferralIds.push(referral1Id);

    assert.equal(createRes.json.referral.doctorId, targetDoctorBDentistId);
    assert.equal(createRes.json.referral.referrerPatientId, referrerPatientId);
    assert.equal(createRes.json.referral.referredPatientId, referredPatientId);

    // 1A. Referrer Patient sees it
    const myRefsRes = await api(`/referrals/my-referrals?referrerPatientId=${referrerPatientId}`, {
      token: referrerPatientToken,
    });
    assert.equal(myRefsRes.status, 200);
    assert.ok(myRefsRes.json.referrals.some((r) => r.id === referral1Id), 'Missing in /referrals/my-referrals');

    // 1B. Referred Patient sees it (by userId or phone)
    const forMeRes = await api(`/referrals/for-me?phone=${referredPatientPhone}`, {
      token: referredPatientToken,
    });
    assert.equal(forMeRes.status, 200);
    const forMeItem = forMeRes.json.referrals.find((r) => r.id === referral1Id);
    assert.ok(forMeItem, 'Missing in /referrals/for-me for referred patient');
    assert.ok(forMeItem.doctorName.includes('Target Specialist B'), `Expected doctorName populated, got ${forMeItem.doctorName}`);

    // 1C. Referred Doctor sees it (via dentistId AND via userId)
    const docRefsByDentistId = await api(`/referrals/doctor?doctorId=${targetDoctorBDentistId}`, {
      token: targetDoctorBToken,
    });
    assert.equal(docRefsByDentistId.status, 200);
    assert.ok(docRefsByDentistId.json.referrals.some((r) => r.id === referral1Id), 'Missing in /referrals/doctor by dentistId');

    const docRefsByUserId = await api(`/referrals/doctor?doctorId=${targetDoctorBUserId}`, {
      token: targetDoctorBToken,
    });
    assert.equal(docRefsByUserId.status, 200);
    assert.ok(docRefsByUserId.json.referrals.some((r) => r.id === referral1Id), 'Missing in /referrals/doctor by userId');

    // 1D. Admin sees it
    const adminRefs = await api('/referrals/all', { token: adminToken });
    assert.equal(adminRefs.status, 200);
    const admItem = adminRefs.json.referrals.find((r) => r.id === referral1Id);
    assert.ok(admItem, 'Missing in /referrals/all for admin');
    assert.equal(admItem.status, 'Pending');

    // 1E. Verify notifications persisted for Doctor, Referred Patient & ALL_ADMINS
    const { data: notifs, error: notifErr } = await supabaseAdmin
      .from('notifications')
      .select('recipient_id, recipient_role, type, message')
      .ilike('message', `%${suffix}%`);
    assert.equal(notifErr, null, `Notification query failed: ${notifErr?.message}`);
    assert.ok(Array.isArray(notifs) && notifs.length >= 3, `Expected >=3 notifications, got ${JSON.stringify(notifs)}`);
    assert.ok(notifs.some((n) => n.recipient_id === targetDoctorBUserId && n.recipient_role === 'Dentist'));
    assert.ok(notifs.some((n) => n.recipient_id === referredPatientId && n.recipient_role === 'Patient'));
    assert.ok(notifs.some((n) => n.recipient_id === 'ALL_ADMINS' && n.recipient_role === 'Admin'));
  });

  await t.test('Scenario 2: Doctor A refers patient to Doctor B -> visible in Doctor A, Referred Patient, Doctor B, Admin & Accept works', async () => {
    const docRefRes = await api('/referrals', {
      method: 'POST',
      token: refDoctorAToken,
      body: {
        // Deliberately pass dentists.id to verify canonical users.id FK resolution!
        referrerPatientId: refDoctorADentistId,
        referredPatientName: `Referred Patient ${suffix}`,
        referredPatientMobile: referredPatientPhone,
        referredPatientAge: 29,
        referredPatientGender: 'Female',
        referredPatientCity: 'Hyderabad',
        referredPatientPincode: '500081',
        referredPatientLocation: 'Jubilee Hills',
        requiredSpecialist: 'Cardiology',
        clinicalComplaint: 'Doctor-referred abnormal ECG follow-up',
        doctorId: targetDoctorBDentistId,
      },
    });

    assert.equal(docRefRes.status, 201, `Doctor create referral failed: ${JSON.stringify(docRefRes.json)}`);
    referral2Id = docRefRes.json.referral?.id;
    assert.ok(referral2Id, 'Referral 2 ID missing');
    cleanupReferralIds.push(referral2Id);

    // Doctor A sees their outgoing referral using either userId or dentistId
    const docAOutByUser = await api(`/referrals/my-referrals?referrerPatientId=${refDoctorAUserId}`, {
      token: refDoctorAToken,
    });
    assert.ok(docAOutByUser.json.referrals.some((r) => r.id === referral2Id), 'Doctor A cannot see outgoing referral via userId');

    const docAOutByDentist = await api(`/referrals/my-referrals?referrerPatientId=${refDoctorADentistId}`, {
      token: refDoctorAToken,
    });
    assert.ok(docAOutByDentist.json.referrals.some((r) => r.id === referral2Id), 'Doctor A cannot see outgoing referral via dentistId');

    // Doctor B accepts referral 2
    const acceptRes = await api(`/referrals/${referral2Id}/accept`, {
      method: 'PATCH',
      token: targetDoctorBToken,
      body: {
        doctorId: targetDoctorBDentistId,
        confirmedDate: new Date().toISOString().split('T')[0],
        confirmedTimeSlot: '11:30 AM',
      },
    });
    assert.equal(acceptRes.status, 200, `Accept failed: ${JSON.stringify(acceptRes.json)}`);

    // Verify fresh re-login persistence for Patient Dashboard, Doctor B Dashboard & Admin Dashboard
    const reLoginPat = await api('/auth/login', {
      method: 'POST',
      body: { email: `refpat2.${suffix}@gshealth.test`, password: pass, role: 'Patient' },
    });
    assert.equal(reLoginPat.status, 200);
    const freshPatToken = reLoginPat.json.token || reLoginPat.json.accessToken;

    const freshForMe = await api(`/referrals/for-me?phone=${referredPatientPhone}`, { token: freshPatToken });
    const acceptedForPat = freshForMe.json.referrals.find((r) => r.id === referral2Id);
    assert.ok(acceptedForPat, 'Referral 2 missing for patient after re-login');
    assert.equal(acceptedForPat.status, 'Accepted');

    const freshAdminAll = await api('/referrals/all', { token: adminToken });
    assert.ok(freshAdminAll.json.referrals.some((r) => r.id === referral1Id));
    const acceptedForAdmin = freshAdminAll.json.referrals.find((r) => r.id === referral2Id);
    assert.ok(acceptedForAdmin);
    assert.equal(acceptedForAdmin.status, 'Accepted');
  });
});
