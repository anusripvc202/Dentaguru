const { ChatMessage, AuditLog } = require('../models/Schemas');

// 1. GET ALL CONVERSATIONS / THREADS (Role-Enforced)
// - Main Admin: can view all patient-doctor conversations + audit logged
// - Sub-Admin: strictly forbidden (handled by requireChatAccess)
// - Dentist: views only their assigned patient threads
// - Patient: views only their own thread
exports.getConversations = async (req, res) => {
    try {
        const user = req.user;
        const role = (user?.role || '').toString().trim().toLowerCase();
        const isMainAdmin = role === 'admin' || role === 'primaryadmin' || role === 'primary_admin' || role === 'superadmin' || role === 'super_admin' || user?.email === 'admin@dentaguru.com';

        const conversations = await ChatMessage.getConversations(user);

        // Record Audit Log when Main Admin accesses conversation list
        if (isMainAdmin && user) {
            await AuditLog.create({
                user_id: user.id,
                user_email: user.email,
                user_role: user.role || 'Admin',
                action: 'ADMIN_CHAT_CONVERSATIONS_LIST',
                target_resource: 'ALL_CONVERSATIONS',
                details: {
                    threadsCount: conversations.length,
                    userAgent: req.headers['user-agent'] || 'unknown'
                },
                ip_address: req.ip || req.headers['x-forwarded-for'] || '127.0.0.1'
            });
        }

        res.json({
            success: true,
            count: conversations.length,
            conversations
        });
    } catch (err) {
        console.error('Get Conversations Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to fetch conversations from database.' });
    }
};

// 2. GET CHAT MESSAGES FROM SUPABASE DATABASE (Role-Enforced)
// - Main Admin: can view any room messages + audit logged
// - Sub-Admin: 403 Forbidden (handled by middleware)
// - Dentist/Patient: only their authorized rooms
exports.getMessages = async (req, res) => {
    const { roomId, markRead } = req.query;
    try {
        const user = req.user;
        const role = (user?.role || '').toString().trim().toLowerCase();
        const isMainAdmin = role === 'admin' || role === 'primaryadmin' || role === 'primary_admin' || role === 'superadmin' || role === 'super_admin' || user?.email === 'admin@dentaguru.com';

        const messages = await ChatMessage.find(roomId ? { room_id: roomId } : {}, { user });

        if (roomId && user && (markRead === 'true' || markRead === '1')) {
            await ChatMessage.markAsRead({ roomId, userId: user.id }).catch(() => { });
        }

        // Record Audit Log when Main Admin inspects a specific patient conversation
        if (isMainAdmin && user && roomId) {
            await AuditLog.create({
                user_id: user.id,
                user_email: user.email,
                user_role: user.role || 'Admin',
                action: 'ADMIN_CHAT_MESSAGES_VIEW',
                target_resource: roomId,
                details: {
                    roomId,
                    messageCount: messages.length,
                    userAgent: req.headers['user-agent'] || 'unknown'
                },
                ip_address: req.ip || req.headers['x-forwarded-for'] || '127.0.0.1'
            });
        }

        res.json({
            success: true,
            count: messages.length,
            messages
        });
    } catch (err) {
        console.error('Get Messages Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to fetch chat messages from database.' });
    }
};

// 3. SEND CHAT MESSAGE (Saved to Supabase 'chat_messages' table)
exports.sendMessage = async (req, res) => {
    const { roomId, senderId, receiverId, message, type, senderRole } = req.body;
    try {
        const trimmedMsg = (message || '').toString().trim();
        if (!trimmedMsg) {
            return res.status(400).json({
                success: false,
                message: 'Message text cannot be empty.'
            });
        }

        const effectiveSenderId = (req.user && req.user.id) ? req.user.id : (senderId || null);
        const effRole = (req.user?.role || senderRole || '').toString().trim().toLowerCase();
        const sStr = String(senderId || req.user?.name || '').toLowerCase();
        const isDoc = type === 'doctor' || effRole === 'dentist' || effRole === 'doctor' || sStr.startsWith('dr.') || sStr.includes('doctor') || sStr.includes('dentist');
        const msgType = isDoc ? 'doctor' : (type === 'patient' || effRole === 'patient' ? 'patient' : (type === 'admin' || effRole.includes('admin') ? 'admin' : 'text'));

        const chat = await ChatMessage.create({
            room_id: roomId || 'GENERAL-CHAT',
            sender_id: effectiveSenderId,
            receiver_id: receiverId || null,
            message: trimmedMsg,
            type: msgType
        });

        console.log(`💬 Chat message saved in Supabase 'chat_messages' table: "${trimmedMsg}"`);
        res.status(201).json({
            success: true,
            message: 'Chat message sent and saved to database successfully.',
            chat
        });
    } catch (err) {
        console.error('Send Chat Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to save chat message to database.' });
    }
};

// 3b. MARK CHAT ROOM MESSAGES AS READ
exports.markRoomRead = async (req, res) => {
    const roomId = req.body?.roomId || req.query?.roomId;
    try {
        if (!roomId) {
            return res.status(400).json({ success: false, message: 'roomId is required.' });
        }
        const updatedCount = await ChatMessage.markAsRead({
            roomId,
            userId: req.user?.id || null
        });
        res.json({
            success: true,
            updatedCount,
            message: 'Conversation marked as read.'
        });
    } catch (err) {
        console.error('Mark Chat Read Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to mark messages as read.' });
    }
};

// 4. CLEAR CHAT MESSAGES FROM SUPABASE DATABASE
exports.clearMessages = async (req, res) => {
    const roomId = req.body?.roomId || req.query?.roomId;
    const messageId = req.body?.messageId || req.query?.messageId;
    try {
        const user = req.user;
        const role = (user?.role || '').toString().trim().toLowerCase();
        const isMainAdmin = role === 'admin' || role === 'primaryadmin' || role === 'primary_admin' || role === 'superadmin' || role === 'super_admin' || user?.email === 'admin@dentaguru.com';

        await ChatMessage.delete({ roomId, messageId });
        console.log(`🗑️ Cleared chat messages for room "${roomId || messageId}"`);

        // Record Audit Log if Admin performs clear
        if (isMainAdmin && user) {
            await AuditLog.create({
                user_id: user.id,
                user_email: user.email,
                user_role: user.role || 'Admin',
                action: 'ADMIN_CHAT_CLEAR',
                target_resource: roomId || messageId || 'ALL',
                details: { roomId, messageId },
                ip_address: req.ip || req.headers['x-forwarded-for'] || '127.0.0.1'
            });
        }

        res.json({
            success: true,
            message: 'Chat history cleared successfully.'
        });
    } catch (err) {
        console.error('Clear Chat Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to clear chat history.' });
    }
};

// 5. GET AUDIT LOGS (Strictly Main Admin Only)
exports.getAuditLogs = async (req, res) => {
    try {
        const { action, targetResource, limit } = req.query;
        const query = {};
        if (action) query.action = action;
        if (targetResource) query.target_resource = targetResource;
        if (limit) query.limit = parseInt(limit, 10);

        const logs = await AuditLog.find(query);
        res.json({
            success: true,
            count: logs.length,
            logs
        });
    } catch (err) {
        console.error('Get Audit Logs Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to fetch audit logs.' });
    }
};
