const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '../../.env') });
const { Clinic, User } = require('../models/Schemas');

async function seedClinics() {
    try {
        console.log('🌱 Seeding sample Clinics into Supabase...');

        // 1. Find or create a default clinic manager user
        let manager = await User.findOne({ email: 'clinic.manager@dentaguru.com' });
        if (!manager) {
            manager = await User.create({
                name: 'Dr. Sarah Jenkins (Clinic Manager)',
                email: 'clinic.manager@dentaguru.com',
                password: 'Password123!',
                phone: '+919876543210',
                role: 'Clinic'
            });
            console.log('✅ Created Clinic Manager User:', manager.email);
        }

        // 2. Insert sample clinics
        const sampleClinics = [
            {
                user_id: manager.id,
                clinic_name: 'DentaGuru Care Center - Indiranagar',
                location: '100 Feet Rd, Indiranagar, Bengaluru, Karnataka 560038',
                rating: 4.9,
                reviews_count: 128,
                verified: true,
                services: ['Teeth Cleaning', 'Root Canal', 'Dental Implants', 'Orthodontics'],
                pricing: [
                    { service: 'Teeth Cleaning', price: 1500 },
                    { service: 'Root Canal', price: 6500 },
                    { service: 'Dental Implants', price: 25000 }
                ],
                latitude: 12.9784,
                longitude: 77.6408
            },
            {
                user_id: manager.id,
                clinic_name: 'DentaGuru Specialist Dental Clinic - Koramangala',
                location: '80 Feet Rd, 4th Block, Koramangala, Bengaluru, Karnataka 560034',
                rating: 4.8,
                reviews_count: 95,
                verified: true,
                services: ['Teeth Whitening', 'Invisible Braces', 'Pediatric Dentistry'],
                pricing: [
                    { service: 'Teeth Whitening', price: 4000 },
                    { service: 'Invisible Braces', price: 45000 }
                ],
                latitude: 12.9352,
                longitude: 77.6245
            }
        ];

        for (const clinicData of sampleClinics) {
            const existing = await Clinic.findOne({ clinic_name: clinicData.clinic_name });
            if (!existing) {
                const created = await Clinic.create(clinicData);
                console.log(`✅ Clinic Created: ${created.clinic_name} (ID: ${created.id})`);
            } else {
                console.log(`ℹ️ Clinic already exists: ${existing.clinic_name}`);
            }
        }

        console.log('🎉 Clinic seeding completed successfully!');
        process.exit(0);
    } catch (err) {
        console.error('❌ Error seeding clinics:', err);
        process.exit(1);
    }
}

seedClinics();
