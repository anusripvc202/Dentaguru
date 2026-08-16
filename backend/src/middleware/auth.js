const jwt = require('jsonwebtoken');
const { User, SubAdminPermission, PERMISSION_CONSTANTS } = require('../models/Schemas');
const { supabase, supabaseAdmin } = require('../config/supabase');

const authenticateJWT = async (req, res, next) => {
    const authHeader = req.headers.authorization;

    if (authHeader && authHeader.startsWith('Bearer ')) {
        const token = authHeader.split(' ')[1];

        // 1. Try Supabase Auth token validation first
        try {
            const { data: { user }, error } = await supabase.auth.getUser(token);
            if (!error && user) {
                let dbUser = null;
                try {
                    dbUser = await User.findById(user.id);
                    if (!dbUser && user.email) {
                        dbUser = await User.findOne({ email: user.email.toLowerCase() });
                    }
                } catch (_) {}

                let userPermissions = dbUser?.permissions || [];
                if ((!userPermissions || userPermissions.length === 0) && (dbUser?.role === 'Sub-Admin' || dbUser?.role === 'SUB_ADMIN')) {
                    userPermissions = await SubAdminPermission.getPermissionsForUser(user.id);
                }

                req.user = {
                    id: user.id,
                    email: user.email,
                    name: dbUser?.name || user.user_metadata?.name || user.email.split('@')[0],
                    role: dbUser?.role || user.user_metadata?.role || 'Patient',
                    status: dbUser?.status || 'ACTIVE',
                    permissions: userPermissions,
                    user_metadata: user.user_metadata
                };

                // Check active status
                if (req.user.status === 'INACTIVE' || req.user.status === 'DEACTIVATED') {
                    return res.status(403).json({
                        success: false,
                        message: 'Access Denied: Your account has been deactivated by the Main Admin.'
                    });
                }

                return next();
            }
        } catch (sbError) {
            console.log('Supabase token verification failed, checking local fallback JWT...');
        }

        // 2. Local JWT Verification Fallback (development/mock mode)
        try {
            const decoded = jwt.verify(token, process.env.JWT_SECRET || 'supersecretjwtkey123');
            
            const dbUser = await User.findById(decoded.id);
            let userPermissions = dbUser?.permissions || decoded.permissions || [];
            if ((!userPermissions || userPermissions.length === 0) && (dbUser?.role === 'Sub-Admin' || dbUser?.role === 'SUB_ADMIN')) {
                userPermissions = await SubAdminPermission.getPermissionsForUser(decoded.id);
            }

            req.user = {
                id: decoded.id,
                email: dbUser?.email || decoded.email,
                name: dbUser?.name || decoded.name || 'User',
                role: dbUser?.role || decoded.role || 'Patient',
                status: dbUser?.status || 'ACTIVE',
                permissions: userPermissions
            };

            // Check active status
            if (req.user.status === 'INACTIVE' || req.user.status === 'DEACTIVATED') {
                return res.status(403).json({
                    success: false,
                    message: 'Access Denied: Your account has been deactivated by the Main Admin.'
                });
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
                try {
                    dbUser = await User.findById(user.id);
                    if (!dbUser && user.email) {
                        dbUser = await User.findOne({ email: user.email.toLowerCase() });
                    }
                } catch (_) {}

                let userPermissions = dbUser?.permissions || [];
                if ((!userPermissions || userPermissions.length === 0) && (dbUser?.role === 'Sub-Admin' || dbUser?.role === 'SUB_ADMIN')) {
                    userPermissions = await SubAdminPermission.getPermissionsForUser(user.id);
                }

                req.user = {
                    id: user.id,
                    email: user.email,
                    name: dbUser?.name || user.user_metadata?.name || user.email.split('@')[0],
                    role: dbUser?.role || user.user_metadata?.role || 'Patient',
                    status: dbUser?.status || 'ACTIVE',
                    permissions: userPermissions,
                    user_metadata: user.user_metadata
                };
                return next();
            }
        } catch (_) {}

        try {
            const decoded = jwt.verify(token, process.env.JWT_SECRET || 'supersecretjwtkey123');
            const dbUser = await User.findById(decoded.id);
            let userPermissions = dbUser?.permissions || decoded.permissions || [];
            if ((!userPermissions || userPermissions.length === 0) && (dbUser?.role === 'Sub-Admin' || dbUser?.role === 'SUB_ADMIN')) {
                userPermissions = await SubAdminPermission.getPermissionsForUser(decoded.id);
            }

            req.user = {
                id: decoded.id,
                email: dbUser?.email || decoded.email,
                name: dbUser?.name || decoded.name || 'User',
                role: dbUser?.role || decoded.role || 'Patient',
                status: dbUser?.status || 'ACTIVE',
                permissions: userPermissions
            };
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

        const role = (req.user.role || '').toString().trim();
        const roleLower = role.toLowerCase();
        const matches = allowedRoles.some(r => r.toLowerCase() === roleLower);

        if (!matches) {
            return res.status(403).json({ 
                success: false, 
                message: `Access denied. Role '${req.user.role}' is not authorized for this resource.` 
            });
        }

        next();
    };
};

// Strictly Main Primary Admin only
const requireMainAdmin = (req, res, next) => {
    if (!req.user) {
        return res.status(401).json({ success: false, message: 'Authentication required.' });
    }

    const role = (req.user.role || '').toString().trim().toLowerCase();
    const isMainAdmin = role === 'admin' || role === 'primaryadmin' || role === 'primary_admin' || req.user.email === 'anusripvc202@gmail.com';

    if (!isMainAdmin) {
        return res.status(403).json({
            success: false,
            message: 'Access Denied: Only the Primary Main Admin is authorized to perform this operation.'
        });
    }

    next();
};

// Granular Permission Checker (Allows Main Admin or Sub-Admin with required permission)
const requirePermission = (requiredPermission, alternativePermissions = []) => {
    return async (req, res, next) => {
        if (!req.user) {
            return res.status(401).json({ success: false, message: 'Authentication required.' });
        }

        const role = (req.user.role || '').toString().trim().toLowerCase();

        // 1. Primary Main Admin always has unrestricted full access
        if (role === 'admin' || role === 'primaryadmin' || role === 'primary_admin' || req.user.email === 'anusripvc202@gmail.com') {
            return next();
        }

        // 2. Sub-Admin RBAC validation
        const isSubAdmin = role === 'sub-admin' || role === 'subadmin' || role === 'sub_admin';
        if (isSubAdmin) {
            // Check active status
            const status = (req.user.status || 'ACTIVE').toString().trim().toUpperCase();
            if (status === 'INACTIVE' || status === 'DEACTIVATED') {
                return res.status(403).json({
                    success: false,
                    message: 'Access Denied: Your Sub-Admin account has been deactivated by the Main Admin.'
                });
            }

            // Retrieve and normalize permissions
            let userPerms = req.user.permissions || [];
            if ((!userPerms || userPerms.length === 0) && req.user.id) {
                userPerms = await SubAdminPermission.getPermissionsForUser(req.user.id);
            }

            const permsList = (userPerms || []).map(p => (p || '').toString().trim().toUpperCase());
            const requiredUpper = (requiredPermission || '').toString().trim().toUpperCase();
            const alternativesUpper = (alternativePermissions || []).map(p => (p || '').toString().trim().toUpperCase());

            const hasPerm = permsList.includes('*') ||
                            permsList.includes('ALL') ||
                            permsList.includes(requiredUpper) ||
                            alternativesUpper.some(alt => permsList.includes(alt));

            if (hasPerm) {
                return next();
            }

            return res.status(403).json({
                success: false,
                message: `Access Denied: You lack the required permission '${requiredPermission}' to access this resource.`
            });
        }

        // 3. Any other role (Patient, Dentist) attempting to access admin-protected endpoint
        return res.status(403).json({
            success: false,
            message: `Access Denied: Role '${req.user.role}' is not authorized for this admin resource.`
        });
    };
};

module.exports = {
    authenticateJWT,
    optionalAuth,
    requireRole,
    requireMainAdmin,
    requirePermission
};

