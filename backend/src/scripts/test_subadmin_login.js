const path = require('path');
require('dotenv').config({ path: path.resolve(__dirname, '../../.env') });
const { User } = require('../models/Schemas');
const jwt = require('jsonwebtoken');

async function testLogin() {
    try {
        const email = 'rahul202@gmail.com';
        const password = 'Trivikram';

        const user = await User.findOne({ email });
        if (!user) {
            console.log('User not found!');
            return;
        }

        const isMatch = await User.comparePassword(password, user.password);
        console.log('User found:', user.name);
        console.log('Password match result:', isMatch);

        if (isMatch) {
            const token = jwt.sign(
                { id: user.id, role: user.role, email: user.email },
                process.env.JWT_SECRET || 'fallback_secret',
                { expiresIn: '7d' }
            );
            console.log('✅ Generated JWT Token successfully!');
            console.log('✅ Sub-Admin permissions:', user.permissions);
        } else {
            console.log('❌ Password mismatch!');
        }

    } catch (e) {
        console.error('Error in testLogin:', e);
    } finally {
        process.exit(0);
    }
}

testLogin();
