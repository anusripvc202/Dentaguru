const jwt = require('jsonwebtoken');
const { User } = require('../models/Schemas');
const { supabase } = require('../config/supabase');

const authenticateJWT = async (req, res, next) => {
    const authHeader = req.headers.authorization;

    if (authHeader && authHeader.startsWith('Bearer ')) {
        const token = authHeader.split(' ')[1];

        // 1. Try Supabase Auth token validation first
        try {
            const { data: { user }, error } = await supabase.auth.getUser(token);
            if (!error && user) {
                req.user = {
                    id: user.id,
                    email: user.email,
                    role: user.user_metadata.role || 'patient',
                    user_metadata: user.user_metadata
                };
                return next();
            }
        } catch (sbError) {
            console.log('Supabase token verification failed, checking local fallback JWT...');
        }

        // 2. Local JWT Verification Fallback (development/mock mode)
        try {
            const decoded = jwt.verify(token, process.env.JWT_SECRET || 'supersecretjwtkey123');
            
            // Optional DB fetch fallback
            const user = await User.findById(decoded.id);
            if (user) {
                req.user = user;
            } else {
                req.user = {
                    id: decoded.id,
                    email: decoded.email,
                    role: decoded.role || 'patient'
                };
            }
            return next();
        } catch (err) {
            console.error('JWT Verification Error:', err.message);
            return res.status(403).json({ success: false, message: 'Invalid or expired token.' });
        }
    } else {
        return res.status(401).json({ success: false, message: 'Authorization header missing or invalid format.' });
    }
};

const optionalAuth = async (req, res, next) => {
    const authHeader = req.headers.authorization;

    if (authHeader && authHeader.startsWith('Bearer ')) {
        const token = authHeader.split(' ')[1];

        try {
            const { data: { user }, error } = await supabase.auth.getUser(token);
            if (!error && user) {
                let dbUser = null;
                try { dbUser = await User.findById(user.id); } catch (_) {}
                req.user = {
                    id: user.id,
                    email: user.email,
                    name: dbUser?.name || user.user_metadata?.name || user.email.split('@')[0],
                    role: dbUser?.role || user.user_metadata?.role || 'Patient',
                    user_metadata: user.user_metadata
                };
                return next();
            }
        } catch (_) {}

        try {
            const decoded = jwt.verify(token, process.env.JWT_SECRET || 'supersecretjwtkey123');
            const user = await User.findById(decoded.id);
            if (user) {
                req.user = user;
            } else {
                req.user = {
                    id: decoded.id,
                    email: decoded.email,
                    role: decoded.role || 'patient'
                };
            }
        } catch (_) {}
    }
    next();
};

// Role authorization checker
const requireRole = (allowedRoles) => {
    return (req, res, next) => {
        if (!req.user) {
            return res.status(401).json({ success: false, message: 'Authentication required.' });
        }

        if (!allowedRoles.includes(req.user.role)) {
            return res.status(403).json({ 
                success: false, 
                message: `Access denied. Role '${req.user.role}' is not authorized for this resource.` 
            });
        }

        next();
    };
};

module.exports = {
    authenticateJWT,
    optionalAuth,
    requireRole
};

