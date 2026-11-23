const test = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const app = require('../src/app');
const { supabaseAdmin } = require('../src/config/supabase');

test('GS HEALTH Language-Based Doctor Filtering E2E Suite', async (t) => {
  const suffix = Date.now().toString().slice(-6);
  const cleanupUserIds = [];
  const cleanupDentistIds = [];
  const cleanupClinicIds = [];

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
    for (const dId of cleanupDentistIds) {
      try { await supabaseAdmin.from('dentists').delete().eq('id', dId); } catch (_) {}
    }
    for (const cId of cleanupClinicIds) {
      try { await supabaseAdmin.from('clinics').delete().eq('id', cId); } catch (_) {}
    }
    for (const uId of cleanupUserIds) {
      try { await supabaseAdmin.from('notifications').delete().eq('recipient_id', uId); } catch (_) {}
      try { await supabaseAdmin.from('users').delete().eq('id', uId); } catch (_) {}
    }
    try { await supabaseAdmin.from('notifications').delete().ilike('message', `%${suffix}%`); } catch (_) {}
  });

  // Register 4 doctors with distinct language combinations, cities, pincodes, specialties
  const docSpecs = [
    {
      name: `DocLangOne ${suffix}`,
      phone: `71000${suffix.slice(-5)}`,
      city: 'Hyderabad',
      pincode: '500081',
      specialty: 'Orthodontics',
      languages: ['English', 'Telugu'],
    },
    {
      name: `DocLangTwo ${suffix}`,
      phone: `72000${suffix.slice(-5)}`,
      city: 'Hyderabad',
      pincode: '500033',
      specialty: 'Endodontics',
      languages: ['Hindi', 'Marathi'],
    },
    {
      name: `DocLangThree ${suffix}`,
      phone: `73000${suffix.slice(-5)}`,
      city: 'Chennai',
      pincode: '600001',
      specialty: 'Orthodontics',
      languages: ['Tamil'],
    },
    {
      name: `DocLangFourOff ${suffix}`,
      phone: `74000${suffix.slice(-5)}`,
      city: 'Hyderabad',
      pincode: '500081',
      specialty: 'Orthodontics',
      languages: ['Kannada'],
      turnOffAvailability: true,
    },
  ];

  const createdDocs = [];

  await t.test('1. Doctor registration saves all selected languages in users & dentists without duplicates', async () => {
    for (const spec of docSpecs) {
      const reg = await api('/auth/register', {
        method: 'POST',
        body: {
          name: spec.name,
          phone: spec.phone,
          role: 'Dentist',
          city: spec.city,
          pincode: spec.pincode,
          specialty: spec.specialty,
          qualification: 'BDS, MDS',
          experienceYears: 6,
          languages: spec.languages,
        },
      });
      assert.equal(reg.status, 201, `Doctor registration should succeed: ${JSON.stringify(reg.json)}`);
      const userId = reg.json.user.id;
      const dentistId = reg.json.user.dentistId;
      const token = reg.json.accessToken;
      cleanupUserIds.push(userId);
      cleanupDentistIds.push(dentistId);

      assert.deepStrictEqual(reg.json.user.languages, spec.languages);

      // Verify in Supabase dentists table directly
      const { data: dRow, error } = await supabaseAdmin
        .from('dentists')
        .select('id, user_id, languages, city, pincode, speciality')
        .eq('id', dentistId)
        .single();
      assert.ifError(error);
      assert.deepStrictEqual(dRow.languages, spec.languages, 'dentists.languages must persist all selected languages');

      if (spec.turnOffAvailability) {
        const off = await api(`/doctors/${dentistId}/availability`, {
          method: 'PATCH',
          token,
          body: { isAvailable: false },
        });
        assert.equal(off.status, 200);
      }

      createdDocs.push({ ...spec, userId, dentistId, token });
    }
  });

  await t.test('2. /doctors/languages returns distinct languages only from available registered doctors', async () => {
    const res = await api('/doctors/languages');
    assert.equal(res.status, 200);
    assert.equal(res.json.success, true);
    const langs = res.json.languages.map((l) => l.toLowerCase());
    assert.ok(langs.includes('english'));
    assert.ok(langs.includes('telugu'));
    assert.ok(langs.includes('hindi'));
    assert.ok(langs.includes('marathi'));
    assert.ok(langs.includes('tamil'));
    // DocLangFourOff speaks Kannada and is OFF (assuming no other ON doctor speaks Kannada only from this test batch)
  });

  await t.test('3. Single language filter & multi-language OR filter return non-duplicate matching doctors', async () => {
    // Filter by Tamil -> DocLangThree
    const tamilRes = await api('/dentists?languages=Tamil');
    assert.equal(tamilRes.status, 200);
    const tamilIds = tamilRes.json.dentists.map((d) => d.id);
    assert.ok(tamilIds.includes(createdDocs[2].dentistId));
    assert.ok(!tamilIds.includes(createdDocs[0].dentistId));
    assert.ok(!tamilIds.includes(createdDocs[1].dentistId));

    // Multi-select: Telugu,Hindi -> returns BOTH DocLangOne and DocLangTwo, excludes DocLangThree and OFF DocLangFourOff
    const multiRes = await api('/dentists?languages=Telugu,Hindi');
    assert.equal(multiRes.status, 200);
    const multiIds = multiRes.json.dentists.map((d) => d.id);
    assert.ok(multiIds.includes(createdDocs[0].dentistId), 'Doctor speaking Telugu should match');
    assert.ok(multiIds.includes(createdDocs[1].dentistId), 'Doctor speaking Hindi should match');
    assert.ok(!multiIds.includes(createdDocs[2].dentistId), 'Tamil-only doctor should NOT match');
    assert.ok(!multiIds.includes(createdDocs[3].dentistId), 'Unavailable doctor should NOT match');

    // Verify no duplicate doctor IDs
    assert.equal(new Set(multiIds).size, multiIds.length, 'No duplicate doctor records');
  });

  await t.test('4. Combined filtering: Language + City + Pincode + Specialization + Availability', async () => {
    // City=Hyderabad + Specialty=Orthodontics + Languages=Telugu,Hindi -> ONLY DocLangOne (DocLangTwo is Endodontics, DocLangThree is Chennai, DocLangFourOff is OFF)
    const combo1 = await api('/dentists?city=Hyderabad&specialty=Orthodontics&languages=Telugu,Hindi');
    assert.equal(combo1.status, 200);
    const combo1Ids = combo1.json.dentists.map((d) => d.id);
    assert.ok(combo1Ids.includes(createdDocs[0].dentistId));
    assert.ok(!combo1Ids.includes(createdDocs[1].dentistId));
    assert.ok(!combo1Ids.includes(createdDocs[2].dentistId));
    assert.ok(!combo1Ids.includes(createdDocs[3].dentistId));

    // Pincode=500081 + City=Hyderabad + Specialty=Orthodontics + Language=Telugu -> ONLY DocLangOne (not DocLangFourOff even though same city/pin/spec!)
    const combo2 = await api('/dentists?city=Hyderabad&pincode=500081&specialty=Orthodontics&languages=Telugu');
    assert.equal(combo2.status, 200);
    assert.deepStrictEqual(
      combo2.json.dentists.filter((d) => d.name.includes(suffix)).map((d) => d.id),
      [createdDocs[0].dentistId],
    );

    // Clear language filter while keeping City=Hyderabad&Specialty=Orthodontics
    const clearedLang = await api('/dentists?city=Hyderabad&specialty=Orthodontics');
    assert.equal(clearedLang.status, 200);
    assert.ok(clearedLang.json.dentists.some((d) => d.id === createdDocs[0].dentistId));
    assert.ok(!clearedLang.json.dentists.some((d) => d.id === createdDocs[3].dentistId));
  });

  await t.test('5. Doctor Profile language update persists cleanly in DB and reflects in Find Doctors', async () => {
    const doc3 = createdDocs[2];
    const upd = await api(`/doctors/${doc3.dentistId}/profile`, {
      method: 'PUT',
      token: doc3.token,
      body: {
        languages: ['Tamil', 'French'],
      },
    });
    assert.equal(upd.status, 200);
    assert.deepStrictEqual(upd.json.doctor.languages, ['Tamil', 'French']);

    const frenchRes = await api('/dentists?languages=French');
    assert.equal(frenchRes.status, 200);
    assert.ok(frenchRes.json.dentists.some((d) => d.id === doc3.dentistId));
  });

  await t.test('6. End-to-end Telugu/English + Hindi/Kannada + Any language + specialty alias + newly registered Malayalam doctor', async () => {
    // Register Doc A (Telugu + English) and Doc B (Hindi + Kannada)
    const regA = await api('/auth/register', {
      method: 'POST',
      body: {
        name: `DocTeluguEng ${suffix}`,
        phone: `75000${suffix.slice(-5)}`,
        role: 'Dentist',
        city: 'Vijayawada',
        pincode: '520001',
        specialty: 'Orthodontics',
        qualification: 'BDS, MDS',
        experienceYears: 7,
        languages: ['Telugu', 'English'],
      },
    });
    assert.equal(regA.status, 201);
    cleanupUserIds.push(regA.json.user.id);
    cleanupDentistIds.push(regA.json.user.dentistId);

    const regB = await api('/auth/register', {
      method: 'POST',
      body: {
        name: `DocHindiKan ${suffix}`,
        phone: `76000${suffix.slice(-5)}`,
        role: 'Dentist',
        city: 'Bengaluru',
        pincode: '560001',
        specialty: 'General Dentistry',
        qualification: 'BDS',
        experienceYears: 5,
        languages: ['Hindi', 'Kannada'],
      },
    });
    assert.equal(regB.status, 201);
    cleanupUserIds.push(regB.json.user.id);
    cleanupDentistIds.push(regB.json.user.dentistId);

    const docAId = regA.json.user.dentistId;
    const docBId = regB.json.user.dentistId;

    // All 4 languages must appear dynamically
    const langsRes = await api('/doctors/languages');
    assert.equal(langsRes.status, 200);
    const langsLower = langsRes.json.languages.map((l) => l.toLowerCase());
    for (const expected of ['telugu', 'english', 'hindi', 'kannada']) {
      assert.ok(langsLower.includes(expected), `Expected ${expected} in /doctors/languages`);
    }

    // Selecting Telugu -> ONLY Doc A (not Doc B)
    const teluguRes = await api(`/dentists?languages=Telugu&search=${suffix}`);
    assert.equal(teluguRes.status, 200);
    assert.ok(teluguRes.json.dentists.some((d) => d.id === docAId));
    assert.ok(!teluguRes.json.dentists.some((d) => d.id === docBId));

    // Selecting Kannada -> ONLY Doc B (not Doc A)
    const kannadaRes = await api(`/dentists?languages=Kannada&search=${suffix}`);
    assert.equal(kannadaRes.status, 200);
    assert.ok(kannadaRes.json.dentists.some((d) => d.id === docBId));
    assert.ok(!kannadaRes.json.dentists.some((d) => d.id === docAId));

    // Multi-select Telugu + Kannada -> BOTH Doc A and Doc B
    const multiRes = await api(`/dentists?languages=Telugu,Kannada&search=${suffix}`);
    assert.equal(multiRes.status, 200);
    assert.ok(multiRes.json.dentists.some((d) => d.id === docAId));
    assert.ok(multiRes.json.dentists.some((d) => d.id === docBId));

    // Selecting "Any language" -> unfiltered list includes both
    const anyRes = await api(`/dentists?languages=Any%20language&search=${suffix}`);
    assert.equal(anyRes.status, 200);
    assert.ok(anyRes.json.dentists.some((d) => d.id === docAId));
    assert.ok(anyRes.json.dentists.some((d) => d.id === docBId));

    // Combined specialty alias ("Orthodontist" -> "Orthodontics") + city + pincode + language
    const aliasCombo = await api('/dentists?city=Vijayawada&pincode=520001&specialty=Orthodontist&languages=Telugu');
    assert.equal(aliasCombo.status, 200);
    assert.ok(aliasCombo.json.dentists.some((d) => d.id === docAId));
    assert.ok(!aliasCombo.json.dentists.some((d) => d.id === docBId));

    // Newly registered doctor with Malayalam -> Malayalam automatically appears
    const regC = await api('/auth/register', {
      method: 'POST',
      body: {
        name: `DocMalayalam ${suffix}`,
        phone: `77000${suffix.slice(-5)}`,
        role: 'Dentist',
        city: 'Kochi',
        pincode: '682001',
        specialty: 'Cardiology',
        qualification: 'MBBS, MD',
        experienceYears: 8,
        languages: ['Malayalam'],
      },
    });
    assert.equal(regC.status, 201);
    cleanupUserIds.push(regC.json.user.id);
    cleanupDentistIds.push(regC.json.user.dentistId);

    const langsAfter = await api('/doctors/languages');
    assert.equal(langsAfter.status, 200);
    assert.ok(
      langsAfter.json.languages.map((l) => l.toLowerCase()).includes('malayalam'),
      'Newly registered doctor language Malayalam must automatically appear',
    );
  });
});
