const path = require('path');
require('dotenv').config({ path: path.resolve(__dirname, '../../.env') });
const { User, SubAdminPermission, PERMISSION_CONSTANTS } = require('../models/Schemas');

async function testCreate() {
    console.log('Testing Sub-Admin creation and retrieval...');
    try {
        const testEmail = 'demo_subadmin@dentaguru.com';
        const existing = await User.findOne({ email: testEmail });
        if (existing) {
            await SubAdminPermission.setPermissionsForUser(existing.id, []);
            const { supabaseAdmin } = require('../config/supabase');
            await supabaseAdmin.from('users').delete().eq('id', existing.id);
            console.log('Cleaned up previous demo subadmin.');
        }

        const subAdmin = await User.create({
            name: 'Demo Operations Sub-Admin',
            email: testEmail,
            password: 'Password123!',
            phone: '9876543210',
            role: 'Sub-Admin',
            status: 'ACTIVE',
            permissions: [
                PERMISSION_CONSTANTS.PATIENT_VIEW,
                PERMISSION_CONSTANTS.ASSIGNMENT_VIEW,
                PERMISSION_CONSTANTS.ASSIGNMENT_CREATE
            ]
        });

        console.log('✅ Created Sub-Admin successfully:', subAdmin.name);
        console.log('   Email:', subAdmin.email);
        console.log('   Permissions:', subAdmin.permissions);

        const subAdmins = await User.find({ role: 'Sub-Admin' });
        console.log(`✅ Retrieved ${subAdmins.length} Sub-Admins from database.`);
        console.log(JSON.stringify(subAdmins, null, 2));

    } catch (e) {
        console.error('❌ Error in testCreate:', e);
    } finally {
        process.exit(0);
    }
}

testCreate();
