const jwt = require('jsonwebtoken');
const { User, SubAdminPermission, PERMISSION_CONSTANTS } = require('../models/Schemas');
const { supabase, supabaseAdmin } = require('../config/supabase');
const { getJwtSecret, isCloudEnv } = require('../config/secrets');

const enforceActiveSubAdminStatus = (dbUser, tokenIssuedAtSec = null) => {
    if (!dbUser) return null;
    const roleLower = (dbUser.role || '').toString().trim().toLowerCase();
    const isSubAdmin = roleLower === 'sub-admin' || roleLower === 'subadmin' || roleLower === 'sub_admin' || roleLower === 'coordinator';
    const effectiveStatus = (dbUser.status || 'ACTIVE').toString().trim().toUpperCase();
    if (isSubAdmin && (effectiveStatus === 'INACTIVE' || effectiveStatus === 'DEACTIVATED')) {
        return 'Access Denied: Your Coordinator account has been deactivated by the Main Admin. Please contact the administrator.';
    }
    if (isSubAdmin && tokenIssuedAtSec && dbUser.device_token && typeof dbUser.device_token === 'string' && dbUser.device_token.trim().startsWith('{')) {
        try {
            const meta = JSON.parse(dbUser.device_token);
            if (meta.revokedBefore && (tokenIssuedAtSec * 1000) < Number(meta.revokedBefore)) {
                return 'Session invalidated by administrator. Please sign in again.';
            }
        } catch (_) { }
    }
    return null;
};

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
                } catch (_) { }

                let userPermissions = dbUser?.permissions || [];
                if ((!userPermissions || userPermissions.length === 0) && (dbUser?.role === 'Sub-Admin' || dbUser?.role === 'SUB_ADMIN')) {
                    userPermissions = await SubAdminPermission.getPermissionsForUser(user.id);
                }

                const resolvedSbRole = dbUser ? (dbUser.role ?? '') : (user.user_metadata?.role ?? '');
                const resolvedSbStatus = dbUser ? (dbUser.status ?? null) : (user.user_metadata?.status ?? null);
                req.user = {
                    id: dbUser?.id || user.id,
                    email: dbUser?.email || user.email,
                    name: dbUser?.name || user.user_metadata?.name || (user.email ? user.email.split('@')[0] : 'User'),
                    role: resolvedSbRole,
                    status: resolvedSbStatus,
                    permissions: userPermissions,
                    user_metadata: user.user_metadata
                };

                // Reject explicitly deactivated/suspended/blocked accounts on all routes;
                // chat routes additionally require explicit ACTIVE status via requireChatAccess.
                const upperSbStatus = req.user.status == null ? '' : String(req.user.status).trim().toUpperCase();
                if (['INACTIVE', 'DEACTIVATED', 'SUSPENDED', 'BLOCKED'].includes(upperSbStatus)) {
                    return res.status(403).json({
                        success: false,
                        code: 'ACCOUNT_DEACTIVATED',
                        message: 'Access Denied: Your account has been deactivated by the Main Admin.'
                    });
                }

                return next();
            }
        } catch (sbError) {
            console.log('Supabase token verification failed, checking local fallback JWT...');
        }

        // 2. Direct Supabase session token fallback (sb_direct_<userId> / sb_session_<userId>) — strictly disabled in cloud (staging/production)
        if (!isCloudEnv() && (token.startsWith('sb_direct_') || token.startsWith('sb_session_'))) {
            try {
                const directUserId = token.replace(/^sb_(?:direct|session)_/, '').trim();
                const dbUser = await User.findById(directUserId);
                if (dbUser) {
                    let userPermissions = dbUser.permissions || [];
                    if ((!userPermissions || userPermissions.length === 0) && (dbUser.role === 'Sub-Admin' || dbUser.role === 'SUB_ADMIN')) {
                        userPermissions = await SubAdminPermission.getPermissionsForUser(dbUser.id);
                    }
                    req.user = {
                        id: dbUser.id,
                        email: dbUser.email,
                        name: dbUser.name || 'User',
                        role: dbUser.role ?? '',
                        status: dbUser.status ?? null,
                        permissions: userPermissions
                    };
                    const upperDirectStatus = req.user.status == null ? '' : String(req.user.status).trim().toUpperCase();
                    if (['INACTIVE', 'DEACTIVATED', 'SUSPENDED', 'BLOCKED'].includes(upperDirectStatus)) {
                        return res.status(403).json({
                            success: false,
                            code: 'ACCOUNT_DEACTIVATED',
                            message: 'Access Denied: Your account has been deactivated by the Main Admin.'
                        });
                    }
                    return next();
                }
            } catch (_) { }
        }

        // 3. Local JWT Verification Fallback
        try {
            const decoded = jwt.verify(token, getJwtSecret());

            const dbUser = await User.findById(decoded.id);
            const blockedMsg = enforceActiveSubAdminStatus(dbUser, decoded.iat || null);
            if (blockedMsg) {
                return res.status(403).json({
                    success: false,
                    code: 'ACCOUNT_DEACTIVATED',
                    message: blockedMsg
                });
            }
            let userPermissions = dbUser?.permissions || decoded.permissions || [];
            if ((!userPermissions || userPermissions.length === 0) && (dbUser?.role === 'Sub-Admin' || dbUser?.role === 'SUB_ADMIN')) {
                userPermissions = await SubAdminPermission.getPermissionsForUser(decoded.id);
            }

            const resolvedJwtRole = dbUser ? (dbUser.role ?? '') : (decoded.role ?? '');
            const resolvedJwtStatus = dbUser ? (dbUser.status ?? null) : (decoded.status ?? null);
            req.user = {
                id: decoded.id,
                email: dbUser?.email || decoded.email,
                name: dbUser?.name || decoded.name || 'User',
                role: resolvedJwtRole,
                status: resolvedJwtStatus,
                permissions: userPermissions
            };

            // Reject explicitly deactivated/suspended/blocked accounts on all routes;
            // chat routes additionally require explicit ACTIVE status via requireChatAccess.
            const upperJwtStatus = req.user.status == null ? '' : String(req.user.status).trim().toUpperCase();
            if (['INACTIVE', 'DEACTIVATED', 'SUSPENDED', 'BLOCKED'].includes(upperJwtStatus)) {
                return res.status(403).json({
                    success: false,
                    code: 'ACCOUNT_DEACTIVATED',
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

    const enforceActiveSubAdminStatus = (dbUser, tokenIssuedAtSec = null) => {
        if (!dbUser) return null;
        const roleLower = (dbUser.role || '').toString().trim().toLowerCase();
        const isSubAdmin = roleLower === 'sub-admin' || roleLower === 'subadmin' || roleLower === 'sub_admin' || roleLower === 'coordinator';
        const effectiveStatus = (dbUser.status || 'ACTIVE').toString().trim().toUpperCase();
        if (isSubAdmin && (effectiveStatus === 'INACTIVE' || effectiveStatus === 'DEACTIVATED')) {
            return 'Access Denied: Your Coordinator account has been deactivated by the Main Admin. Please contact the administrator.';
        }
        if (isSubAdmin && tokenIssuedAtSec && dbUser.device_token && typeof dbUser.device_token === 'string' && dbUser.device_token.trim().startsWith('{')) {
            try {
                const meta = JSON.parse(dbUser.device_token);
                if (meta.revokedBefore && (tokenIssuedAtSec * 1000) < Number(meta.revokedBefore)) {
                    return 'Session invalidated by administrator. Please sign in again.';
                }
            } catch (_) { }
        }
        return null;
    };

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
                } catch (_) { }

                const blockedMsg = enforceActiveSubAdminStatus(dbUser);
                if (blockedMsg) {
                    return res.status(403).json({ success: false, code: 'ACCOUNT_DEACTIVATED', message: blockedMsg });
                }

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
        } catch (_) { }

        if (!isCloudEnv() && (token.startsWith('sb_direct_') || token.startsWith('sb_session_'))) {
            try {
                const directUserId = token.replace(/^sb_(?:direct|session)_/, '').trim();
                const dbUser = await User.findById(directUserId);
                if (dbUser) {
                    const blockedMsg = enforceActiveSubAdminStatus(dbUser);
                    if (blockedMsg) {
                        return res.status(403).json({ success: false, code: 'ACCOUNT_DEACTIVATED', message: blockedMsg });
                    }
                    let userPermissions = dbUser.permissions || [];
                    if ((!userPermissions || userPermissions.length === 0) && (dbUser.role === 'Sub-Admin' || dbUser.role === 'SUB_ADMIN')) {
                        userPermissions = await SubAdminPermission.getPermissionsForUser(dbUser.id);
                    }
                    req.user = {
                        id: dbUser.id,
                        email: dbUser.email,
                        name: dbUser.name || 'User',
                        role: dbUser.role || 'Patient',
                        status: dbUser.status || 'ACTIVE',
                        permissions: userPermissions
                    };
                    return next();
                }
            } catch (_) { }
        }

        try {
            const decoded = jwt.verify(token, getJwtSecret());
            const dbUser = await User.findById(decoded.id);
            const blockedMsg = enforceActiveSubAdminStatus(dbUser, decoded.iat || null);
            if (blockedMsg) {
                return res.status(403).json({ success: false, code: 'ACCOUNT_DEACTIVATED', message: blockedMsg });
            }
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
        } catch (_) { }
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
    const isMainAdmin = role === 'admin' || role === 'primaryadmin' || role === 'primary_admin' || role === 'superadmin' || role === 'super_admin';

    if (!isMainAdmin) {
        return res.status(403).json({
            success: false,
            message: 'Access Denied: Only the Primary Main Admin is authorized to perform this operation.'
        });
    }

    next();
};

const MODULE_PERMISSION_ALIASES = {
    DENTIST_VIEW: ['DOCTORS', 'DOCTOR_VIEW', 'DENTIST_MANAGE', 'DENTIST_VERIFY', 'DENTIST_EDIT', 'DENTIST_CREATE', 'VIEW_DENTISTS', 'MANAGE_DOCTORS'],
    DENTIST_EDIT: ['DOCTORS', 'DENTIST_VERIFY', 'DENTIST_MANAGE', 'MANAGE_DOCTORS'],
    DENTIST_VERIFY: ['DOCTORS', 'DENTIST_EDIT', 'DENTIST_MANAGE', 'MANAGE_DOCTORS'],
    DENTIST_MANAGE: ['DOCTORS', 'DENTIST_EDIT', 'MANAGE_DOCTORS'],
    PATIENT_VIEW: ['PATIENTS', 'PATIENT_CREATE', 'PATIENT_ADD', 'PATIENT_EDIT', 'PATIENT_DELETE', 'MANAGE_PATIENTS', 'VIEW_PATIENTS'],
    PATIENT_CREATE: ['PATIENTS', 'PATIENT_ADD', 'MANAGE_PATIENTS'],
    PATIENT_EDIT: ['PATIENTS', 'MANAGE_PATIENTS'],
    PATIENT_DELETE: ['PATIENTS', 'MANAGE_PATIENTS'],
    CLINIC_VIEW: ['CLINICS', 'CLINIC_MANAGE', 'MANAGE_CLINICS', 'VIEW_CLINICS'],
    CLINIC_MANAGE: ['CLINICS', 'MANAGE_CLINICS'],
    APPOINTMENT_VIEW: ['APPOINTMENTS', 'APPOINTMENT_MANAGE', 'MANAGE_APPOINTMENTS', 'VIEW_APPOINTMENTS'],
    APPOINTMENT_MANAGE: ['APPOINTMENTS', 'MANAGE_APPOINTMENTS'],
    PROBLEM_VIEW: ['REQUESTS', 'PROBLEM_UPDATE', 'ASSIGNMENT_VIEW', 'ASSIGNMENT_CREATE', 'MANAGE_REQUESTS', 'VIEW_REQUESTS'],
    PROBLEM_UPDATE: ['REQUESTS', 'ASSIGNMENT_CREATE', 'MANAGE_REQUESTS'],
    ASSIGNMENT_VIEW: ['REQUESTS', 'ASSIGNMENTS', 'ASSIGNMENT_CREATE', 'ASSIGNMENT_HISTORY_VIEW', 'PROBLEM_VIEW', 'MANAGE_REQUESTS'],
    ASSIGNMENT_CREATE: ['REQUESTS', 'ASSIGNMENTS', 'PATIENT_ASSIGN', 'PATIENT_REASSIGN', 'MANAGE_REQUESTS'],
    REFERRAL_VIEW: ['REFERRALS', 'REFERRAL_MANAGE', 'MANAGE_REFERRALS', 'VIEW_REFERRALS'],
    REFERRAL_MANAGE: ['REFERRALS', 'MANAGE_REFERRALS'],
    REPORT_VIEW: ['REPORTS', 'REPORT_ASSIGNMENT_VIEW', 'REPORT_DISTRICT_VIEW', 'VIEW_REPORTS', 'MANAGE_REPORTS']
};

const expandAcceptedPermissions = (requiredPermission, alternativePermissions = []) => {
    const base = [requiredPermission, ...(alternativePermissions || [])]
        .map(p => (p || '').toString().trim().toUpperCase())
        .filter(Boolean);
    const expanded = new Set(base);
    for (const key of base) {
        const aliases = MODULE_PERMISSION_ALIASES[key];
        if (Array.isArray(aliases)) {
            for (const alias of aliases) {
                expanded.add(alias);
            }
        }
    }
    return expanded;
};

// Granular Permission Checker (Allows Main Admin or Sub-Admin with required permission)
const requirePermission = (requiredPermission, alternativePermissions = []) => {
    return async (req, res, next) => {
        if (!req.user) {
            return res.status(401).json({ success: false, message: 'Authentication required.' });
        }

        const role = (req.user.role || '').toString().trim().toLowerCase();

        // 1. Primary Main Admin always has unrestricted full access
        if (role === 'admin' || role === 'primaryadmin' || role === 'primary_admin' || role === 'superadmin' || role === 'super_admin') {
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
                    code: 'ACCOUNT_DEACTIVATED',
                    message: 'Access Denied: Your Coordinator account has been deactivated by the Main Admin.'
                });
            }

            // Retrieve and normalize permissions
            let userPerms = req.user.permissions || [];
            if ((!userPerms || userPerms.length === 0) && req.user.id) {
                userPerms = await SubAdminPermission.getPermissionsForUser(req.user.id);
            }

            const permsList = (userPerms || []).map(p => (p || '').toString().trim().toUpperCase());
            const acceptedSet = expandAcceptedPermissions(requiredPermission, alternativePermissions);

            const hasPerm = permsList.includes('*') ||
                permsList.includes('ALL') ||
                permsList.some(p => acceptedSet.has(p));

            if (hasPerm) {
                return next();
            }

            return res.status(403).json({
                success: false,
                code: 'PERMISSION_DENIED',
                requiredPermission,
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

// Enforces module permission whenever an authenticated Sub-Admin (or non-Admin role) calls an admin endpoint,
// while allowing unauthenticated internal service/test calls that rely on optionalAuth.
const enforceSubAdminPermissionIfAuthenticated = (requiredPermission, alternativePermissions = []) => {
    const checker = requirePermission(requiredPermission, alternativePermissions);
    return async (req, res, next) => {
        if (!req.user) {
            return next();
        }
        return checker(req, res, next);
    };
};

// Strict Chat Access Guard (Fail-Closed Role & Conversation Membership Verification)
// Enforces:
// - Verified active DB user identity (never trusts client-supplied senderId / role)
// - Unknown, empty, or missing roles: STRICTLY FORBIDDEN (403, never defaults to Patient)
// - Sub-Admin: STRICTLY FORBIDDEN (403, disabled by default even with wildcard '*')
// - Main Admin: audited platform oversight
// - Doctor/Dentist: only verified assigned/appointed/referred/saved patient or own clinic conversations
// - Clinic: only conversations involving affiliated clinic doctors or clinic patients
// - Patient: only own authorized conversations (never arbitrary rooms or other patients' threads)
const requireChatAccess = async (req, res, next) => {
    if (!req.user || !req.user.id) {
        return res.status(401).json({
            success: false,
            message: 'Authentication required to access chat services.'
        });
    }

    try {
        const Schemas = require('../models/Schemas');
        const dbUser = await Schemas.User.findById(req.user.id);
        if (!dbUser) {
            return res.status(403).json({
                success: false,
                message: 'Access Denied: Authenticated user account could not be verified.'
            });
        }

        // Fail closed: user MUST have explicit status === 'ACTIVE' (NULL or missing status is rejected)
        const effectiveStatus = (dbUser.status === null || dbUser.status === undefined)
            ? ''
            : String(dbUser.status).trim().toUpperCase();
        if (effectiveStatus !== 'ACTIVE') {
            return res.status(403).json({
                success: false,
                code: 'ACCOUNT_DEACTIVATED',
                message: 'Access Denied: Only explicitly active accounts are permitted to access chat.'
            });
        }

        // Authoritative DB role; NEVER fall back to 'Patient' on empty/unknown roles
        const authoritativeRawRole = dbUser.role !== undefined ? dbUser.role : req.user.role;
        const chatRole = Schemas.mapUserRoleToChatRole(authoritativeRawRole);

        if (chatRole === 'SUB_ADMIN') {
            return res.status(403).json({
                success: false,
                message: 'Access Denied: Coordinators are strictly prohibited from viewing, searching, or accessing patient-doctor chat messages and conversations.'
            });
        }

        if (!chatRole) {
            return res.status(403).json({
                success: false,
                message: `Access Denied: Role '${authoritativeRawRole || '<empty>'}' is not authorized to access chat conversations.`
            });
        }

        // Sync authoritative user attributes onto req.user for downstream controllers
        req.user = {
            ...req.user,
            id: dbUser.id,
            email: dbUser.email || req.user.email,
            name: dbUser.name || req.user.name,
            role: authoritativeRawRole,
            status: effectiveStatus
        };
        req.chatRole = chatRole;

        const rawRoomId = req.query?.roomId || req.body?.roomId || req.query?.room_id || req.body?.room_id || '';
        const rawConvId = req.query?.conversationId || req.body?.conversationId || req.query?.conversation_id || req.body?.conversation_id || '';
        const roomId = String(rawRoomId).trim() || null;
        const conversationId = String(rawConvId).trim() || null;

        // Main Admin has audited oversight access (individual endpoints verify scope & fail closed on audit error)
        if (chatRole === 'ADMIN') {
            return next();
        }

        // Only GET /chat/conversations is unscoped (per-user filtered in model); /chat/messages, /chat/send, /chat/read require explicit scope
        const isConversationsList = req.method === 'GET' && req.path && req.path.endsWith('/conversations');
        if (!roomId && !conversationId) {
            if (isConversationsList) {
                return next();
            }
            if (req.path && req.path.endsWith('/clear') && (req.body?.messageId || req.query?.messageId)) {
                return next();
            }
            return res.status(400).json({
                success: false,
                message: 'A valid conversationId or roomId is required.'
            });
        }

        const isSendEndpoint = req.method === 'POST' && req.path && req.path.endsWith('/send');
        const isReadEndpoint = req.path && req.path.endsWith('/read');
        const authCheck = await Schemas.authorizeChatParticipantAndReceiver({
            callerUser: req.user,
            roomId,
            conversationId,
            receiverId: isSendEndpoint ? (req.body?.receiverId ?? req.body?.receiver_id ?? null) : null,
            senderIdFromBody: isSendEndpoint ? (req.body?.senderId ?? req.body?.sender_id ?? null) : null,
            operation: isSendEndpoint ? 'SEND_PRECHECK' : (isReadEndpoint ? 'READ_RECEIPT' : 'ACCESS')
        });

        if (!authCheck.authorized) {
            return res.status(authCheck.status || 403).json({
                success: false,
                message: authCheck.message || 'Access Denied: You are not authorized for this conversation.'
            });
        }

        req.authorizedChatContext = authCheck;
        return next();
    } catch (err) {
        console.error('Chat access verification error:', err.message);
        return res.status(500).json({
            success: false,
            message: 'Unable to verify conversation authorization.'
        });
    }
};

// Helper: Resolve caller role & assigned districts across both authenticated and optional-auth endpoints
const resolveCallerAccessContext = async (req) => {
    let user = req.user || null;
    if (!user) {
        const authHeader = req.headers?.authorization || req.headers?.Authorization;
        if (authHeader && typeof authHeader === 'string' && authHeader.startsWith('Bearer ')) {
            const token = authHeader.split(' ')[1];
            try {
                user = jwt.verify(token, getAccessSecret());
            } catch (_) { }
        }
    }
    if (!user && !isCloudEnv() && req.headers) {
        const headerId = req.headers['x-user-id'] ? String(req.headers['x-user-id']).trim() : '';
        const headerRole = req.headers['x-user-role'] ? String(req.headers['x-user-role']).trim() : '';
        if (headerId || headerRole) {
            let dbUser = null;
            if (headerId) {
                try {
                    const { User } = require('../models/Schemas');
                    dbUser = await User.findById(headerId);
                } catch (_) { }
            }
            user = dbUser || {
                id: headerId || 'local-caller',
                role: headerRole || 'Patient'
            };
        }
    }

    const roleLower = String(user?.role || '').trim().toLowerCase();
    const isMainAdmin = roleLower === 'admin' || roleLower === 'primaryadmin' || roleLower === 'primary_admin' || roleLower === 'superadmin' || roleLower === 'super_admin';
    const isSubAdmin = roleLower === 'sub-admin' || roleLower === 'subadmin' || roleLower === 'sub_admin' || roleLower === 'coordinator';

    let assignedDistricts = [];
    const assignedDistrictIds = new Set();
    const assignedDistrictNames = new Set();

    if (isSubAdmin && user?.id) {
        try {
            const { SubAdminDistrict } = require('../models/Schemas');
            assignedDistricts = await SubAdminDistrict.getDistrictsForSubAdmin(user.id);
            for (const d of (assignedDistricts || [])) {
                const dId = String(d?.id || d?.district_id || '').trim().toLowerCase();
                const dName = String(d?.name || d?.district_name || '').trim().toLowerCase();
                if (dId) assignedDistrictIds.add(dId);
                if (dName) assignedDistrictNames.add(dName);
            }
        } catch (_) { }
    }

    return {
        user,
        userId: user?.id ? String(user.id).trim() : null,
        roleLower,
        isMainAdmin,
        isSubAdmin,
        assignedDistricts,
        assignedDistrictIds,
        assignedDistrictNames
    };
};

// Middleware: Strict District-Level Access Control (Section 5)
// - Main Admin: full access to all districts
// - Sub-Admin: restricted strictly to assigned districts by districtId
// - Injects req.assignedDistricts, req.assignedDistrictIds, and req.isAuthorizedDistrict(districtId, districtName)
const enforceDistrictAccess = async (req, res, next) => {
    if (!req.user) {
        return res.status(401).json({ success: false, message: 'Authentication required.' });
    }

    const roleLower = (req.user.role || '').toLowerCase();
    const isMainAdmin = roleLower === 'admin' || roleLower === 'primaryadmin' || roleLower === 'primary_admin' || roleLower === 'superadmin' || roleLower === 'super_admin';

    if (isMainAdmin) {
        req.assignedDistricts = [];
        req.assignedDistrictIds = new Set();
        req.isAuthorizedDistrict = () => true;
        return next();
    }

    const isSubAdmin = roleLower === 'sub-admin' || roleLower === 'subadmin' || roleLower === 'sub_admin' || roleLower === 'coordinator';
    if (!isSubAdmin) {
        return res.status(403).json({ success: false, message: 'Unauthorized role.' });
    }

    const { SubAdminDistrict, District } = require('../models/Schemas');
    const assignedDistricts = await SubAdminDistrict.getDistrictsForSubAdmin(req.user.id);
    req.assignedDistricts = assignedDistricts;

    const authIds = new Set(assignedDistricts.map(d => String(d.id || d.district_id || '').trim().toLowerCase()).filter(Boolean));
    req.assignedDistrictIds = authIds;

    req.isAuthorizedDistrict = (dId, dName) => {
        if (authIds.size === 0) return false;
        if (dId) {
            return authIds.has(String(dId).trim().toLowerCase());
        }
        if (dName) {
            const resolved = District.resolveDistrictFromLocation({ district: dName });
            if (resolved && resolved.districtId && resolved.isVerified) {
                return authIds.has(String(resolved.districtId).trim().toLowerCase());
            }
        }
        return false;
    };

    // If request specifies a districtId or district, verify authorization
    const targetDistrictId = req.query?.districtId || req.body?.districtId;
    const targetDistrictName = req.query?.district || req.body?.district;
    if (targetDistrictId || targetDistrictName) {
        if (!req.isAuthorizedDistrict(targetDistrictId, targetDistrictName)) {
            return res.status(403).json({
                success: false,
                code: 'DISTRICT_ACCESS_DENIED',
                message: `Access Denied: You do not have authorization to access district '${targetDistrictName || targetDistrictId}'.`
            });
        }
    }

    next();
};

module.exports = {
    authenticateJWT,
    optionalAuth,
    requireRole,
    requireMainAdmin,
    requirePermission,
    enforceSubAdminPermissionIfAuthenticated,
    requireChatAccess,
    enforceDistrictAccess,
    resolveCallerAccessContext
};


