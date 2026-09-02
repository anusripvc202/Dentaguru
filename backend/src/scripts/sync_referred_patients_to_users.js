const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '../../.env') });
const { createClient } = require('@supabase/supabase-js');

const supabase = createClient(
    process.env.SUPABASE_URL,
    process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.SUPABASE_ANON_KEY
);

async function syncReferredPatientsToUsers() {
    console.log('🔄 Checking all referrals in database and syncing referred patients to users table...\n');

    // 1. Fetch all referrals
    const { data: referrals, error: refErr } = await supabase
        .from('referrals')
        .select('*');

    if (refErr) {
        console.error('❌ Error fetching referrals:', refErr.message);
        return;
    }

    console.log(`Found ${referrals?.length || 0} referral(s) in database.\n`);

    for (const ref of referrals) {
        console.log(`--- Processing Referral: ${ref.id} (${ref.referred_patient_name} - ${ref.referred_patient_mobile}) ---`);
        const cleanMobile = (ref.referred_patient_mobile || '').trim();
        const digitsOnly = cleanMobile.replace(/[^0-9]/g, '');
        const raw10 = digitsOnly.length >= 10 ? digitsOnly.slice(-10) : digitsOnly;
        const patientEmail = `user_${raw10}@dentaguru.internal`;

        // Check if user already exists
        let { data: existingUser } = await supabase
            .from('users')
            .select('id, name, phone, email, role')
            .or(`phone.eq.${raw10},phone.eq.${cleanMobile},email.eq.${patientEmail}`)
            .maybeSingle();

        let patientUserId = existingUser?.id;

        if (!patientUserId) {
            console.log(`⚠️ Referred patient ${ref.referred_patient_name} does NOT exist in users table. Creating user record...`);
            
            const metaObj = {
                age: String(ref.referred_patient_age || ''),
                gender: ref.referred_patient_gender || '',
                emergencyContact: cleanMobile,
                address: ref.referred_patient_location || ''
            };

            const insertPayload = {
                name: ref.referred_patient_name || 'Referred Patient',
                email: patientEmail,
                password: `Referred_${raw10}_Secure!`,
                phone: raw10,
                role: 'Patient',
                city: ref.referred_patient_city || '',
                pincode: ref.referred_patient_pincode || '',
                state: ref.referred_patient_location || '',
                device_token: JSON.stringify(metaObj)
            };

            const { data: newUser, error: insertErr } = await supabase
                .from('users')
                .insert(insertPayload)
                .select('id, name, email, phone')
                .single();

            if (insertErr) {
                console.error(`❌ Error inserting referred patient to users: ${insertErr.message}`);
            } else {
                patientUserId = newUser.id;
                console.log(`✅ Successfully created patient user in database: ${newUser.name} (${newUser.id})`);
            }
        } else {
            console.log(`ℹ️ Patient user already exists: ${existingUser.name} (${existingUser.id})`);
        }

        // Link referral to user if not linked
        if (patientUserId && (ref.referred_patient_id !== patientUserId || ref.referred_user_id !== patientUserId)) {
            const { error: updateErr } = await supabase
                .from('referrals')
                .update({
                    referred_patient_id: patientUserId,
                    referred_user_id: patientUserId
                })
                .eq('id', ref.id);

            if (updateErr) {
                console.error(`❌ Error updating referral ${ref.id}:`, updateErr.message);
            } else {
                console.log(`✅ Referral ${ref.id} updated with referred_patient_id = ${patientUserId}`);
            }
        }

        // If referral is Accepted, ensure consultation appointment exists
        if (patientUserId && ref.status === 'Accepted') {
            const { data: existingAppt } = await supabase
                .from('appointments')
                .select('id')
                .eq('patient_id', patientUserId)
                .eq('dentist_id', ref.doctor_id)
                .maybeSingle();

            if (!existingAppt) {
                console.log(`Creating confirmed appointment for accepted referral...`);
                const { data: newAppt, error: apptErr } = await supabase
                    .from('appointments')
                    .insert({
                        patient_id: patientUserId,
                        dentist_id: ref.doctor_id,
                        appointment_date: new Date().toISOString().split('T')[0],
                        time_slot: '10:00 AM',
                        treatment: ref.required_specialist || 'Specialist Consultation',
                        status: 'CONFIRMED',
                        notes: `Referred Patient: ${ref.referred_patient_name} (${ref.referred_patient_mobile}). Clinical complaint: ${ref.clinical_complaint || ''}`
                    })
                    .select('id')
                    .maybeSingle();

                if (newAppt?.id) {
                    await supabase.from('referrals').update({ appointment_id: newAppt.id }).eq('id', ref.id);
                    console.log(`✅ Appointment created: ${newAppt.id}`);
                }
            }
        }
    }

    console.log('\n🎉 Finished syncing all referred patients to database users table!');
}

syncReferredPatientsToUsers().then(() => process.exit(0)).catch(e => {
    console.error(e);
    process.exit(1);
});
