const test = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const app = require('../src/app');
const { supabaseAdmin } = require('../src/config/supabase');

test('GS HEALTH Manage Availability, Working Schedule & Block Date E2E Suite (Scenarios 1-8)', async (t) => {
  const suffix = Date.now().toString().slice(-6);
  const cleanupUserIds = [];
  const cleanupDentistIds = [];
  const cleanupApptIds = [];

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

  function nextWeekdayIso(targetWeekdayIdx, minDaysAhead = 2) {
    // targetWeekdayIdx: 0=Sun, 1=Mon, 2=Tue, 3=Wed, 4=Thu, 5=Fri, 6=Sat
    const now = new Date();
    for (let i = minDaysAhead; i <= 28; i++) {
      const d = new Date(now.getFullYear(), now.getMonth(), now.getDate() + i);
      if (d.getDay() === targetWeekdayIdx) {
        return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
      }
    }
    return '2026-12-01';
  }

  t.after(async () => {
    server.closeAllConnections?.();
    await new Promise((resolve) => server.close(resolve));
    for (const aId of cleanupApptIds) {
      try { await supabaseAdmin.from('appointments').delete().eq('id', aId); } catch (_) {}
    }
    for (const dId of cleanupDentistIds) {
      try { await supabaseAdmin.from('doctor_availability').delete().eq('dentist_id', dId); } catch (_) {}
      try { await supabaseAdmin.from('dentists').delete().eq('id', dId); } catch (_) {}
    }
    for (const uId of cleanupUserIds) {
      try { await supabaseAdmin.from('notifications').delete().eq('recipient_id', uId); } catch (_) {}
      try { await supabaseAdmin.from('users').delete().eq('id', uId); } catch (_) {}
    }
  });

  const doctorPhone = `9${suffix.padStart(9, '7').slice(0, 9)}`;
  const doctorEmail = `scheddoc.${suffix}@gshealth.test`;
  const doctorPass = 'DocPass@123';

  const patientPhone = `8${suffix.padStart(9, '6').slice(0, 9)}`;
  const patientEmail = `schedpat.${suffix}@gshealth.test`;
  const patientPass = 'PatPass@123';

  let doctorToken;
  let doctorDentistId;
  let patientToken;
  let patientId;

  // Date fixtures across weekdays: Monday, Tuesday, Wednesday, Thursday, Saturday
  const futureMon = nextWeekdayIso(1, 2);
  const futureTue = nextWeekdayIso(2, 2);
  const futureWed = nextWeekdayIso(3, 2);
  const futureThu = nextWeekdayIso(4, 2);
  const futureSat = nextWeekdayIso(6, 2);

  await t.test('Setup: Register Cardiology Doctor & Patient in gs-health-test', async () => {
    const docReg = await api('/auth/register', {
      method: 'POST',
      body: {
        name: `Dr. SchedTest ${suffix}`,
        email: doctorEmail,
        phone: doctorPhone,
        password: doctorPass,
        role: 'Dentist',
        specialty: 'Cardiology',
        qualification: 'MBBS, MD, DM (Cardiology)',
        experienceYears: 8,
        city: 'Hyderabad',
        pincode: '500081',
        languages: ['English', 'Hindi'],
      },
    });
    assert.ok(docReg.status === 200 || docReg.status === 201, `Doctor registration status=${docReg.status}`);
    doctorToken = docReg.json.token || docReg.json.accessToken;
    doctorDentistId = docReg.json.user?.dentistId || docReg.json.dentist?.id;
    const doctorUserId = docReg.json.user?.id;
    assert.ok(doctorToken && doctorDentistId && doctorUserId);
    cleanupUserIds.push(doctorUserId);
    cleanupDentistIds.push(doctorDentistId);

    const patReg = await api('/auth/register', {
      method: 'POST',
      body: {
        name: `Patient SchedTest ${suffix}`,
        email: patientEmail,
        phone: patientPhone,
        password: patientPass,
        role: 'Patient',
        city: 'Hyderabad',
        pincode: '500081',
      },
    });
    assert.ok(patReg.status === 200 || patReg.status === 201, `Patient registration status=${patReg.status}`);
    patientToken = patReg.json.token || patReg.json.accessToken;
    patientId = patReg.json.user?.id;
    assert.ok(patientToken && patientId);
    cleanupUserIds.push(patientId);
  });

  await t.test('Scenario 6 & 7: Configure Working Days (Mon, Wed, Fri), Hours (10:00 AM - 04:00 PM), Lunch Break (01:00 PM - 02:00 PM), Duration (30m) & verify slots', async () => {
    const updSched = await api('/doctor-availability/schedule', {
      method: 'PUT',
      token: doctorToken,
      body: {
        dentistId: doctorDentistId,
        workingDays: ['Mon', 'Wed', 'Fri'],
        startTime: '10:00 AM',
        endTime: '04:00 PM',
        slotDurationMinutes: 30,
        hasBreak: true,
        breakStartTime: '01:00 PM',
        breakEndTime: '02:00 PM',
        applyToUpcomingDays: true,
      },
    });
    assert.equal(updSched.status, 200);
    assert.equal(updSched.json.success, true);

    // Fetch slots on working Monday: 10:00 AM - 04:00 PM excluding 01:00 PM & 01:30 PM
    const monAvail = await api(`/doctor-availability?dentistId=${doctorDentistId}&date=${futureMon}`, {
      token: patientToken,
    });
    assert.equal(monAvail.status, 200);
    assert.equal(monAvail.json.availability.isWorkingDay, true);
    assert.equal(monAvail.json.availability.startTime, '10:00 AM');
    assert.equal(monAvail.json.availability.endTime, '04:00 PM');
    assert.equal(monAvail.json.availability.slotDurationMinutes, 30);
    assert.ok(monAvail.json.availability.availableSlots.includes('10:00 AM'));
    assert.ok(monAvail.json.availability.availableSlots.includes('12:30 PM'));
    assert.ok(monAvail.json.availability.availableSlots.includes('02:00 PM'));
    assert.ok(!monAvail.json.availability.availableSlots.includes('01:00 PM'), 'Lunch slot 01:00 PM must NOT be generated');
    assert.ok(!monAvail.json.availability.availableSlots.includes('01:30 PM'), 'Lunch slot 01:30 PM must NOT be generated');

    // Non-working Saturday should report isWorkingDay=false & 0 available slots
    const satAvail = await api(`/doctor-availability?dentistId=${doctorDentistId}&date=${futureSat}`, {
      token: patientToken,
    });
    assert.equal(satAvail.status, 200);
    assert.equal(satAvail.json.availability.isWorkingDay, false);
    assert.deepStrictEqual(satAvail.json.availability.availableSlots, []);

    // Direct booking inside Lunch Break or Non-Working Day must be rejected by backend
    const lunchBook = await api('/appointments', {
      method: 'POST',
      token: patientToken,
      body: {
        dentistId: doctorDentistId,
        patientId,
        date: futureMon,
        timeSlot: '01:00 PM',
        treatment: 'Cardiology Consultation',
      },
    });
    assert.equal(lunchBook.status, 400, 'Booking during lunch break must be rejected');

    const satBook = await api('/appointments', {
      method: 'POST',
      token: patientToken,
      body: {
        dentistId: doctorDentistId,
        patientId,
        date: futureSat,
        timeSlot: '10:00 AM',
        treatment: 'Cardiology Consultation',
      },
    });
    assert.equal(satBook.status, 409, 'Booking on non-working Saturday must be rejected');
  });

  let existingApptId = null;
  await t.test('Pre-condition & Scenario 1: Book valid slot on Wednesday, then switch Date Blocked ON -> persists across refresh & preserves existing appointment', async () => {
    const validBook = await api('/appointments', {
      method: 'POST',
      token: patientToken,
      body: {
        dentistId: doctorDentistId,
        patientId,
        date: futureWed,
        timeSlot: '10:30 AM',
        treatment: 'Cardiac Checkup',
      },
    });
    assert.equal(validBook.status, 201);
    existingApptId = validBook.json.appointment.id;
    cleanupApptIds.push(existingApptId);

    // Block Wednesday
    const blockRes = await api('/doctor-availability/block-date', {
      method: 'POST',
      token: doctorToken,
      body: {
        dentistId: doctorDentistId,
        date: futureWed,
        isBlocked: true,
        reason: 'Medical Conference Leave',
      },
    });
    assert.equal(blockRes.status, 200);
    assert.equal(blockRes.json.isBlocked, true);
    assert.equal(blockRes.json.existingAppointmentsCount, 1);

    // Refresh / Re-fetch date & blocked-dates list -> stays blocked ON
    const checkWed = await api(`/doctor-availability?dentistId=${doctorDentistId}&date=${futureWed}`, {
      token: doctorToken,
    });
    assert.equal(checkWed.status, 200);
    assert.equal(checkWed.json.availability.isBlocked, true);
    assert.deepStrictEqual(checkWed.json.availability.availableSlots, []);

    const blockedList = await api(`/doctor-availability/blocked-dates?dentistId=${doctorDentistId}`, {
      token: doctorToken,
    });
    assert.equal(blockedList.status, 200);
    assert.ok(blockedList.json.blockedDates.some((b) => b.date === futureWed));

    // Existing appointment remains intact in Supabase
    const { data: existingApptRow } = await supabaseAdmin
      .from('appointments')
      .select('id, status')
      .eq('id', existingApptId)
      .maybeSingle();
    assert.ok(existingApptRow && existingApptRow.id === existingApptId);
  });

  await t.test('Scenario 2 & 5: Doctor logout/re-login preserves blocked date & schedule; Patient cannot view slots or book on blocked date', async () => {
    // Re-login doctor
    const relogin = await api('/auth/login', {
      method: 'POST',
      body: { email: doctorEmail, password: doctorPass, role: 'Dentist' },
    });
    assert.equal(relogin.status, 200);
    const freshToken = relogin.json.token || relogin.json.accessToken;

    const schedAfterLogin = await api(`/doctor-availability/schedule?dentistId=${doctorDentistId}`, {
      token: freshToken,
    });
    assert.equal(schedAfterLogin.status, 200);
    assert.deepStrictEqual(schedAfterLogin.json.schedule.workingDays, ['Monday', 'Wednesday', 'Friday']);
    assert.equal(schedAfterLogin.json.schedule.startTime, '10:00 AM');
    assert.equal(schedAfterLogin.json.schedule.endTime, '04:00 PM');
    assert.ok(schedAfterLogin.json.blockedDates.some((b) => b.date === futureWed));

    // Patient checks Wednesday slots -> must return empty availableSlots & isBlocked=true
    const patWed = await api(`/doctor-availability?dentistId=${doctorDentistId}&date=${futureWed}`, {
      token: patientToken,
    });
    assert.equal(patWed.status, 200);
    assert.equal(patWed.json.availability.isBlocked, true);
    assert.deepStrictEqual(patWed.json.availability.availableSlots, []);

    // Patient tries booking on blocked Wednesday -> must fail with 409
    const patBookBlocked = await api('/appointments', {
      method: 'POST',
      token: patientToken,
      body: {
        dentistId: doctorDentistId,
        patientId,
        date: futureWed,
        timeSlot: '11:00 AM',
        treatment: 'Bypass Booking Test',
      },
    });
    assert.equal(patBookBlocked.status, 409);
  });

  await t.test('Scenario 3 & 4: Block multiple dates without duplicates, then unblock date OFF -> becomes available again', async () => {
    // Block multiple dates including futureWed again (tests deduplication!)
    const multiBlock = await api('/doctor-availability/block-date', {
      method: 'POST',
      token: doctorToken,
      body: {
        dentistId: doctorDentistId,
        dates: [futureWed, futureMon, futureThu],
        reason: 'Annual Leave',
        isBlocked: true,
      },
    });
    assert.equal(multiBlock.status, 200);

    const blockedRes = await api(`/doctor-availability/blocked-dates?dentistId=${doctorDentistId}`, {
      token: doctorToken,
    });
    assert.equal(blockedRes.status, 200);
    const blockedYmds = blockedRes.json.blockedDates.map((b) => b.date);
    assert.ok(blockedYmds.includes(futureWed));
    assert.ok(blockedYmds.includes(futureMon));
    assert.ok(blockedYmds.includes(futureThu));
    assert.equal(new Set(blockedYmds).size, blockedYmds.length, 'No duplicate blocked date rows allowed');

    // Switch Date Blocked OFF for futureMon using PATCH/DELETE
    const unblockMon = await api('/doctor-availability/block-date', {
      method: 'PATCH',
      token: doctorToken,
      body: {
        dentistId: doctorDentistId,
        date: futureMon,
        isBlocked: false,
      },
    });
    assert.equal(unblockMon.status, 200);
    assert.equal(unblockMon.json.isBlocked, false);

    // Check Monday is available again for Patient
    const monReopened = await api(`/doctor-availability?dentistId=${doctorDentistId}&date=${futureMon}`, {
      token: patientToken,
    });
    assert.equal(monReopened.status, 200);
    assert.equal(monReopened.json.availability.isBlocked, false);
    assert.ok(monReopened.json.availability.availableSlots.length > 0);
  });

  await t.test('Scenario 8: Multi-specialty check (Dermatology, Orthopedics, General Dentistry) schedule & block workflow works identically', async () => {
    const specs = ['Dermatology', 'Orthopedics', 'General Dentistry'];
    for (let i = 0; i < specs.length; i++) {
      const sSpec = specs[i];
      const spSuffix = `${suffix}${i}`;
      const reg = await api('/auth/register', {
        method: 'POST',
        body: {
          name: `Dr. ${sSpec} ${spSuffix}`,
          email: `spec.${i}.${suffix}@gshealth.test`,
          phone: `9${(parseInt(suffix, 10) + 100 + i).toString().slice(-9).padStart(9, '1')}`,
          password: doctorPass,
          role: 'Dentist',
          specialty: sSpec,
          city: 'Delhi',
          pincode: '110001',
        },
      });
      assert.ok(reg.status === 200 || reg.status === 201, `Spec ${sSpec} register failed: ${reg.status}`);
      const tok = reg.json.token || reg.json.accessToken;
      const dId = reg.json.user?.dentistId || reg.json.dentist?.id;
      const uId = reg.json.user?.id;
      cleanupUserIds.push(uId);
      cleanupDentistIds.push(dId);

      const schedRes = await api('/doctor-availability/schedule', {
        method: 'PUT',
        token: tok,
        body: {
          dentistId: dId,
          workingDays: ['Tue', 'Thu'],
          startTime: '09:00 AM',
          endTime: '01:00 PM',
          slotDurationMinutes: 45,
          hasBreak: false,
        },
      });
      assert.equal(schedRes.status, 200);

      const tueSlots = await api(`/doctor-availability?dentistId=${dId}&date=${futureTue}`, { token: tok });
      assert.equal(tueSlots.status, 200);
      assert.equal(tueSlots.json.availability.slotDurationMinutes, 45);
      assert.ok(tueSlots.json.availability.availableSlots.includes('09:00 AM'));

      const blk = await api('/doctor-availability/block-date', {
        method: 'POST',
        token: tok,
        body: { dentistId: dId, date: futureTue, isBlocked: true, reason: `${sSpec} Holiday` },
      });
      assert.equal(blk.status, 200);
      const tueAfterBlk = await api(`/doctor-availability?dentistId=${dId}&date=${futureTue}`, { token: patientToken });
      assert.equal(tueAfterBlk.json.availability.isBlocked, true);
      assert.deepStrictEqual(tueAfterBlk.json.availability.availableSlots, []);
    }
  });
});
