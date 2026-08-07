require('dotenv').config();
const { supabaseAdmin } = require('../config/supabase');
const { Clinic } = require('../models/Schemas');

async function testClinicInsert() {
    console.log('⚡ Testing Clinic Insertion to Supabase PostgreSQL...');
    try {
        const testClinic = await Clinic.create({
            clinicName: 'Test Apex Dental Clinic',
            location: '456 Healthcare Way, Suite 200, San Francisco, CA',
            services: ['Teeth Whitening', 'Implants', 'Orthodontics'],
            pricing: [{ service: 'Consultation', fee: '$50' }]
        });
        console.log('✅ Clinic Created in Supabase DB:', testClinic);

        const allClinics = await Clinic.find();
        console.log(`📊 Total Clinics in Supabase DB: ${allClinics.length}`);
        process.exit(0);
    } catch (err) {
        console.error('❌ Insert test error:', err.message);
        process.exit(1);
    }
}

testClinicInsert();
