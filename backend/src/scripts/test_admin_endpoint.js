const problemController = require('../controllers/problemRequestController');

async function testAdminEndpoint() {
  console.log('=== TESTING ADMIN PROBLEM REQUESTS ENDPOINT ===\n');

  const req = { query: {}, user: { id: '0e910148-3d14-462e-8360-cab694a70209', role: 'Admin' } };
  let responseData = null;
  const res = {
    json: (d) => { responseData = d; return d; },
    status: () => res
  };

  await problemController.getAdminProblemRequests(req, res);

  console.log(`Total Requests Returned to Admin: ${responseData?.count || responseData?.requests?.length}\n`);
  responseData?.requests?.forEach((r, idx) => {
    console.log(`Request #${idx + 1}:`);
    console.log(`  Patient:  ${r.patientName} (${r.patientPhone}) - ${r.city} (PIN: ${r.pincode})`);
    console.log(`  Problem:  ${r.problem_category} - "${r.problem_description}"`);
    console.log(`  Status:   ${r.status}`);
    console.log(`  Assigned: ${r.assigned_doctor_name} (${r.assigned_doctor_specialty}) @ ${r.assigned_doctor_clinic}`);
    console.log(`  Dentist: `, r.dentist);
    console.log('');
  });
}

testAdminEndpoint().then(() => process.exit(0)).catch(e => { console.error(e); process.exit(1); });
