const test = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const app = require('../src/app');
const { supabaseAdmin } = require('../src/config/supabase');

test('GS HEALTH Multi-Specialty AI Triage & Prescription E2E Suite', async (t) => {
  const suffix = Date.now().toString().slice(-6);
  const cleanupUserIds = [];
  const cleanupDentistIds = [];
  const cleanupRecordIds = [];
  const cleanupRequestIds = [];

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
    for (const rId of cleanupRecordIds) {
      try { await supabaseAdmin.from('medical_records').delete().eq('id', rId); } catch (_) {}
    }
    for (const qId of cleanupRequestIds) {
      try { await supabaseAdmin.from('patient_problem_requests').delete().eq('id', qId); } catch (_) {}
    }
    for (const dId of cleanupDentistIds) {
      try { await supabaseAdmin.from('dentists').delete().eq('id', dId); } catch (_) {}
    }
    for (const uId of cleanupUserIds) {
      try { await supabaseAdmin.from('notifications').delete().eq('recipient_id', uId); } catch (_) {}
      try { await supabaseAdmin.from('users').delete().eq('id', uId); } catch (_) {}
    }
  });

  // Register a patient + a Cardiologist + a Dermatologist
  const patReg = await api('/auth/register', {
    method: 'POST',
    body: {
      name: `PatMultiSpec ${suffix}`,
      phone: `81000${suffix.slice(-5)}`,
      role: 'Patient',
      city: 'Hyderabad',
      pincode: '500081',
    },
  });
  assert.equal(patReg.status, 201, `Patient reg failed: ${JSON.stringify(patReg.json)}`);
  const patientId = patReg.json.user.id;
  const patientToken = patReg.json.accessToken;
  cleanupUserIds.push(patientId);

  const cardioReg = await api('/auth/register', {
    method: 'POST',
    body: {
      name: `CardioDoc ${suffix}`,
      phone: `82000${suffix.slice(-5)}`,
      role: 'Dentist',
      specialty: 'Cardiology',
      qualification: 'MBBS, MD, DM (Cardiology)',
      city: 'Hyderabad',
      pincode: '500081',
      languages: ['English', 'Telugu'],
    },
  });
  assert.equal(cardioReg.status, 201);
  const cardioDocId = cardioReg.json.user.dentistId;
  const cardioToken = cardioReg.json.accessToken;
  cleanupUserIds.push(cardioReg.json.user.id);
  cleanupDentistIds.push(cardioDocId);

  const dermReg = await api('/auth/register', {
    method: 'POST',
    body: {
      name: `DermDoc ${suffix}`,
      phone: `83000${suffix.slice(-5)}`,
      role: 'Dentist',
      specialty: 'Dermatology',
      qualification: 'MBBS, MD (Dermatology)',
      city: 'Hyderabad',
      pincode: '500081',
      languages: ['English', 'Hindi'],
    },
  });
  assert.equal(dermReg.status, 201);
  const dermDocId = dermReg.json.user.dentistId;
  const dermToken = dermReg.json.accessToken;
  cleanupUserIds.push(dermReg.json.user.id);
  cleanupDentistIds.push(dermDocId);

  await t.test('1. /specialties & /specialties/clinical-config cover all major & future specialties dynamically', async () => {
    const listRes = await api('/specialties');
    assert.equal(listRes.status, 200);
    assert.ok(listRes.json.specialties.length >= 10);
    assert.ok(Array.isArray(listRes.json.specialties[0].triageCategories));
    assert.ok(listRes.json.specialties[0].prescriptionSchema);

    const expectedSpecialties = [
      { name: 'Dentistry', cat: 'Aligners & Orthodontics', diagLabel: 'Dental Diagnosis' },
      { name: 'Cardiology', cat: 'Chest Pain', diagLabel: 'Clinical Diagnosis' },
      { name: 'Dermatology', cat: 'Skin Allergies', diagLabel: 'Skin Diagnosis' },
      { name: 'Neurology', cat: 'Migraine', diagLabel: 'Neurological Diagnosis' },
      { name: 'Orthopedics', cat: 'Joint Pain', diagLabel: 'Diagnosis' },
      { name: 'Gynecology', cat: 'PCOS', diagLabel: 'Gynecological / Obstetric Diagnosis' },
      { name: 'Pediatrics', cat: 'Child Nutrition', diagLabel: 'Pediatric Diagnosis' },
      { name: 'General Medicine', cat: 'Fever & Viral Illness', diagLabel: 'Clinical Diagnosis' },
      { name: 'ENT', cat: 'Ear Pain & Infection', diagLabel: 'ENT Diagnosis' },
      { name: 'Ophthalmology', cat: 'Blurred Vision', diagLabel: 'Ophthalmic Diagnosis' },
      { name: 'Gastroenterology', cat: 'Acidity & Reflux', diagLabel: 'Gastroenterology Diagnosis' },
      { name: 'Oncology', cat: 'Cancer Screening & Second Opinion', diagLabel: 'Oncology Clinical Assessment' },
      { name: 'Psychiatry', cat: 'Anxiety & Stress', diagLabel: 'Psychiatric Assessment' },
      { name: 'Urology', cat: 'Kidney Stone Symptoms', diagLabel: 'Urological Diagnosis' },
      { name: 'Pulmonology', cat: 'Wheezing & Asthma', diagLabel: 'Pulmonary Diagnosis' },
      { name: 'Endocrinology', cat: 'Thyroid Symptoms', diagLabel: 'Endocrine Diagnosis' },
      { name: 'Physiotherapy', cat: 'Post-Surgery Rehabilitation', diagLabel: 'Rehabilitation Assessment' },
      { name: 'Geriatric Medicine', cat: 'Geriatric Medicine Consultation', diagLabel: 'Clinical Diagnosis' },
    ];

    for (const sp of expectedSpecialties) {
      const cfg = await api(`/specialties/clinical-config?specialty=${encodeURIComponent(sp.name)}`);
      assert.equal(cfg.status, 200);
      assert.ok(cfg.json.triageCategories.includes(sp.cat), `${sp.name} should include category "${sp.cat}"`);
      assert.equal(cfg.json.prescriptionSchema.diagnosisLabel, sp.diagLabel);
    }

    // Doctor ID auto-resolves registered specialty from database
    const docCfg = await api(`/specialties/clinical-config?doctorId=${encodeURIComponent(dermDocId)}`);
    assert.equal(docCfg.status, 200);
    assert.equal(docCfg.json.specialty, 'Dermatology');
    assert.ok(docCfg.json.triageCategories.includes('Acne'));
  });

  await t.test('2. /triage/analyze analyzes in specialty context, flags emergencies, avoids diagnosis & matches specialists', async () => {
    const cardioEmerg = await api('/triage/analyze', {
      method: 'POST',
      token: patientToken,
      body: {
        specialty: 'Cardiology',
        category: 'Chest Pain',
        symptoms: 'Sudden chest pain and shortness of breath on walking',
        severity: 'Severe',
        duration: '< 24 hours',
      },
    });
    assert.equal(cardioEmerg.status, 200);
    assert.equal(cardioEmerg.json.triage.specialty, 'Cardiology');
    assert.equal(cardioEmerg.json.triage.isEmergency, true);
    assert.ok(cardioEmerg.json.triage.disclaimer.toLowerCase().includes('not a medical diagnosis'));
    assert.ok(cardioEmerg.json.matchingDoctors.some((d) => d.id === cardioDocId), 'Must recommend registered Cardiologist');
    assert.ok(!cardioEmerg.json.matchingDoctors.some((d) => d.id === dermDocId), 'Must NOT recommend Dermatologist for Cardiology');

    // Doctor-selected triage auto-detects Dermatology
    const dermTriage = await api('/triage/analyze', {
      method: 'POST',
      token: patientToken,
      body: {
        doctorId: dermDocId,
        category: 'Rashes',
        symptoms: 'Mild itchy rash on forearm after new soap',
        severity: 'Mild',
        duration: '2-3 days',
      },
    });
    assert.equal(dermTriage.status, 200);
    assert.equal(dermTriage.json.triage.specialty, 'Dermatology');
    assert.equal(dermTriage.json.triage.isEmergency, false);
    assert.ok(dermTriage.json.matchingDoctors.some((d) => d.id === dermDocId));
  });

  await t.test('3. Multi-specialty E-Prescriptions save specialty, clinical sections, multiple medications & follow-up cleanly', async () => {
    // Cardiology prescription
    const cardioRx = await api('/records', {
      method: 'POST',
      token: cardioToken,
      body: {
        patientId,
        dentistId: cardioDocId,
        recordSource: 'doctor_issued',
        type: 'prescription',
        category: 'Prescription',
        title: 'Essential Hypertension',
        diagnosis: 'Essential Hypertension',
        specialty: 'Cardiology',
        clinicalSections: {
          investigations: '12-Lead ECG, Lipid Profile',
          monitoringInstructions: 'Record home BP morning and evening daily.',
        },
        followUpDate: '2026-12-05',
        instructions: 'Low sodium diet and 30 min daily walk.',
        approvedByDoctor: true,
        items: [
          { name: 'Amlodipine 5mg', dosage: '1 Tablet', frequency: 'Once Daily (1-0-0)', duration: '30 Days', instructions: 'Morning after breakfast' },
          { name: 'Atorvastatin 10mg', dosage: '1 Tablet', frequency: 'Once Daily (0-0-1)', duration: '30 Days', instructions: 'At bedtime' },
        ],
      },
    });
    assert.equal(cardioRx.status, 201, `Cardiology Rx failed: ${JSON.stringify(cardioRx.json)}`);
    cleanupRecordIds.push(cardioRx.json.record.id);
    assert.equal(cardioRx.json.record.specialty, 'Cardiology');
    assert.equal(cardioRx.json.record.items.length, 2);
    assert.equal(cardioRx.json.record.clinicalSections.investigations, '12-Lead ECG, Lipid Profile');
    assert.equal(cardioRx.json.record.followUpDate, '2026-12-05');

    // Dermatology prescription (auto-resolves specialty from dermDocId when omitted!)
    const dermRx = await api('/records', {
      method: 'POST',
      token: dermToken,
      body: {
        patientId,
        dentistId: dermDocId,
        recordSource: 'doctor_issued',
        type: 'prescription',
        category: 'Prescription',
        title: 'Contact Dermatitis',
        diagnosis: 'Contact Dermatitis',
        clinicalSections: {
          topicalTreatment: 'Hydrocortisone 1% Cream + Gentle Moisturizer',
          applicationInstructions: 'Apply thin layer twice daily for 7 days',
        },
        followUpDate: '2026-11-30',
        approvedByDoctor: true,
        items: [
          { name: 'Cetirizine 10mg', dosage: '1 Tablet', frequency: '0-0-1', duration: '5 Days', instructions: 'At night if itchy' },
        ],
      },
    });
    assert.equal(dermRx.status, 201, `Dermatology Rx failed: ${JSON.stringify(dermRx.json)}`);
    cleanupRecordIds.push(dermRx.json.record.id);
    assert.equal(dermRx.json.record.specialty, 'Dermatology');
    assert.equal(dermRx.json.record.clinicalSections.topicalTreatment, 'Hydrocortisone 1% Cream + Gentle Moisturizer');

    // Patient fetches records -> both specialty prescriptions persist with full history
    const patRecords = await api(`/records?patientId=${encodeURIComponent(patientId)}`, { token: patientToken });
    assert.equal(patRecords.status, 200);
    const ids = patRecords.json.records.map((r) => r.id);
    assert.ok(ids.includes(cardioRx.json.record.id));
    assert.ok(ids.includes(dermRx.json.record.id));
  });
});
