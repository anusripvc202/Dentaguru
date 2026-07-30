const jwt = require('jsonwebtoken');
const { User } = require('../models/Schemas');

const JWT_SECRET = process.env.JWT_SECRET || 'supersecretjwtkey123';
const REFRESH_SECRET = process.env.REFRESH_SECRET || 'supersecretrefreshkey456';

// Helper: Generate JWT tokens
const generateTokens = (user) => {
    const accessToken = jwt.sign(
        { id: user._id, role: user.role },
        JWT_SECRET,
        { expiresIn: '15m' } // 15 minutes
    );
    const refreshToken = jwt.sign(
        { id: user._id },
        REFRESH_SECRET,
        { expiresIn: '7d' } // 7 days
    );
    return { accessToken, refreshToken };
};

// 1. REGISTER
exports.register = async (req, res) => {
    const { name, email, password, phone, role, fcmToken } = req.body;
    try {
        // Check conflicts
        const existingEmail = await User.findOne({ email });
        if (existingEmail) {
            return res.status(400).json({ success: false, message: 'Email already registered.' });
        }

        const existingPhone = await User.findOne({ phone });
        if (existingPhone) {
            return res.status(400).json({ success: false, message: 'Phone number already registered.' });
        }

        const user = new User({ name, email, password, phone, role });
        // Save Firebase FCM device token if provided (for push notifications)
        if (fcmToken) user.deviceToken = fcmToken;
        await user.save();

        const { accessToken, refreshToken } = generateTokens(user);
        user.refreshTokens.push(refreshToken);
        await user.save();

        res.status(201).json({
            success: true,
            message: 'User registered successfully.',
            user: {
                id: user._id,
                name: user.name,
                email: user.email,
                phone: user.phone,
                role: user.role
            },
            accessToken,
            refreshToken
        });
    } catch (err) {
        console.error('Registration Error:', err.message);
        res.status(500).json({ success: false, message: 'Server registration error.' });
    }
};

// 2. LOGIN
exports.login = async (req, res) => {
    const { email, password, fcmToken } = req.body;
    try {
        const user = await User.findOne({ email });
        if (!user) {
            return res.status(400).json({ success: false, message: 'Invalid credentials.' });
        }

        const isMatch = await user.comparePassword(password);
        if (!isMatch) {
            return res.status(400).json({ success: false, message: 'Invalid credentials.' });
        }

        // Update FCM device token on login (tokens can rotate)
        if (fcmToken && user.deviceToken !== fcmToken) {
            user.deviceToken = fcmToken;
        }

        const { accessToken, refreshToken } = generateTokens(user);
        user.refreshTokens.push(refreshToken);
        await user.save();

        res.json({
            success: true,
            user: {
                id: user._id,
                name: user.name,
                email: user.email,
                role: user.role
            },
            accessToken,
            refreshToken
        });
    } catch (err) {
        console.error('Login Error:', err.message);
        res.status(500).json({ success: false, message: 'Server login error.' });
    }
};

// 3. OTP VERIFICATION SIMULATOR
exports.requestOTP = async (req, res) => {
    const { phone } = req.body;
    try {
        const user = await User.findOne({ phone });
        if (!user) {
            return res.status(404).json({ success: false, message: 'Phone number not found. Please register first.' });
        }
        
        // In production, trigger SMS gateway. Here we return mock code.
        res.json({
            success: true,
            message: 'OTP Code sent successfully via SMS.',
            mockCode: '8849' // Sent back for testing ease
        });
    } catch (err) {
        res.status(500).json({ success: false, message: 'Failed to request OTP.' });
    }
};

exports.verifyOTP = async (req, res) => {
    const { phone, code } = req.body;
    try {
        if (code !== '8849') {
            return res.status(400).json({ success: false, message: 'Invalid verification code.' });
        }

        const user = await User.findOne({ phone });
        if (!user) {
            return res.status(404).json({ success: false, message: 'User matching phone not found.' });
        }

        const { accessToken, refreshToken } = generateTokens(user);
        user.refreshTokens.push(refreshToken);
        await user.save();

        res.json({
            success: true,
            message: 'OTP Verified successfully.',
            user: {
                id: user._id,
                name: user.name,
                email: user.email,
                role: user.role
            },
            accessToken,
            refreshToken
        });
    } catch (err) {
        res.status(500).json({ success: false, message: 'OTP verification failed.' });
    }
};

// 4. REFRESH TOKEN
exports.refreshToken = async (req, res) => {
    const { token } = req.body;
    if (!token) return res.status(401).json({ success: false, message: 'Token required.' });

    try {
        const decoded = jwt.verify(token, REFRESH_SECRET);
        const user = await User.findById(decoded.id);

        if (!user || !user.refreshTokens.includes(token)) {
            return res.status(403).json({ success: false, message: 'Invalid refresh token.' });
        }

        // Generate new access token
        const newAccessToken = jwt.sign(
            { id: user._id, role: user.role },
            JWT_SECRET,
            { expiresIn: '15m' }
        );

        res.json({
            success: true,
            accessToken: newAccessToken
        });
    } catch (err) {
        res.status(403).json({ success: false, message: 'Invalid or expired refresh token.' });
    }
};

// 5. UPDATE BIOMETRIC TOKEN
exports.saveBiometric = async (req, res) => {
    const { biometricToken } = req.body;
    try {
        const user = await User.findById(req.user.id);
        user.biometricToken = biometricToken;
        await user.save();
        res.json({ success: true, message: 'Biometric token configured successfully.' });
    } catch (err) {
        res.status(500).json({ success: false, message: 'Failed to configure biometrics.' });
    }
};

// 6. UPDATE FCM DEVICE TOKEN (Firebase Push Notifications)
exports.updateFcmToken = async (req, res) => {
    const { fcmToken } = req.body;
    if (!fcmToken) {
        return res.status(400).json({ success: false, message: 'fcmToken is required.' });
    }
    try {
        await User.findByIdAndUpdate(req.user.id, { deviceToken: fcmToken });
        res.json({ success: true, message: 'FCM device token updated successfully.' });
    } catch (err) {
        res.status(500).json({ success: false, message: 'Failed to update FCM token.' });
    }
};
