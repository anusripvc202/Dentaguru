const { createClient } = require('@supabase/supabase-js');
require('dotenv').config({ path: require('path').resolve(__dirname, '../../.env') });

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.SUPABASE_ANON_KEY);

async function getProblemAssignments() {
  console.log('=== PATIENT PROBLEM REQUESTS & ASSIGNED DOCTORS ===\n');

  // Fetch all problem requests with joined patient and dentist
  const { data: requests, error } = await supabase
    .from('patient_problem_requests')
    .select(`
      id,
      problem_category,
      problem_description,
      symptoms,
      preferred_location,
      status,
      admin_notes,
      created_at,
      patient:users!patient_id(id, name, email, phone, city, state, pincode),
      dentist:dentists!suggested_dentist_id(
        id,
        speciality,
        user:users!user_id(name, email, phone),
        clinic:clinics!clinic_id(clinic_name, location)
      )
    `);

  if (error) {
    console.error('Query error:', error);
    return;
  }

  console.log(`Total Requests Raised: ${requests.length}\n`);

  requests.forEach((r, idx) => {
    const patientName = r.patient?.name || 'N/A';
    const patientEmail = r.patient?.email || 'N/A';
    const patientPhone = r.patient?.phone || 'N/A';
    const patientLocation = `${r.patient?.city || r.preferred_location || ''} (PIN: ${r.patient?.pincode || ''})`.trim();

    const doctorName = r.dentist?.user?.name ? (r.dentist.user.name.startsWith('Dr.') ? r.dentist.user.name : `Dr. ${r.dentist.user.name}`) : 'Not Assigned';
    const doctorSpecialty = r.dentist?.speciality || 'N/A';
    const doctorEmail = r.dentist?.user?.email || 'N/A';
    const clinicName = r.dentist?.clinic?.clinic_name || 'DentaGuru Care Center';
    const clinicLocation = r.dentist?.clinic?.location || '';

    console.log(`====================================================`);
    console.log(`CASE #${idx + 1}`);
    console.log(`----------------------------------------------------`);
    console.log(`👤 PATIENT DETAILS:`);
    console.log(`   • Name:      ${patientName}`);
    console.log(`   • Email:     ${patientEmail}`);
    console.log(`   • Phone:     ${patientPhone}`);
    console.log(`   • Location:  ${patientLocation}`);
    console.log(``);
    console.log(`🩺 PROBLEM RAISED:`);
    console.log(`   • Problem:   ${r.problem_category}`);
    console.log(`   • Details:   ${r.problem_description || 'N/A'}`);
    console.log(`   • Symptoms:  ${r.symptoms || 'N/A'}`);
    console.log(`   • Raised At: ${r.created_at}`);
    console.log(``);
    console.log(`👨‍⚕️ ASSIGNED DOCTOR:`);
    console.log(`   • Doctor:    ${doctorName}`);
    console.log(`   • Specialty: ${doctorSpecialty}`);
    console.log(`   • Email:     ${doctorEmail}`);
    console.log(`   • Clinic:    ${clinicName} (${clinicLocation})`);
    console.log(``);
    console.log(`📋 ASSIGNMENT STATUS:`);
    console.log(`   • Status:    ${r.status}`);
    console.log(`   • Time Slot: ${r.confirmed_time_slot || 'Pending confirmation'}`);
    console.log(`   • Notes:     ${r.admin_notes || 'None'}`);
    console.log(`====================================================\n`);
  });
}

getProblemAssignments().then(() => process.exit(0)).catch(e => { console.error(e); process.exit(1); });
