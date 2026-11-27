const Schemas = require('../models/Schemas');
const { ChatMessage, AuditLog, mapUserRoleToChatRole } = Schemas;

const CLINICAL_CONTENT_TYPES = new Set([
    'image', 'photo', 'jpg', 'jpeg', 'png', 'webp', 'xray', 'x-ray',
    'document', 'doc', 'pdf', 'file', 'attachment', 'report', 'lab_report',
    'dicom', 'dcm', 'application/dicom', 'image/dicom',
    'prescription', 'prescription_link', 'rx', 'eprescription', 'e-prescription',
    'system', 'notice', 'alert'
]);

function resolveOutgoingLegacyType(rawType, senderChatRole) {
    const cleanType = String(rawType ?? '').trim().toLowerCase();
    if (CLINICAL_CONTENT_TYPES.has(cleanType)) {
        return cleanType;
    }
    if (senderChatRole === 'DOCTOR') return 'doctor';
    if (senderChatRole === 'PATIENT') return 'patient';
    if (senderChatRole === 'ADMIN') return 'admin';
    return 'text';
}

function isExplicitlyActiveStatus(statusVal) {
    return statusVal !== null && statusVal !== undefined && String(statusVal).trim().toUpperCase() === 'ACTIVE';
}

async function recordMandatoryAdminAudit({ req, user, action, targetResource, details }) {
    const entry = await AuditLog.create(
        {
            user_id: user.id,
            user_email: user.email,
            user_role: user.role || 'Admin',
            action,
            target_resource: targetResource,
            details: {
                ...details,
                userAgent: req.headers['user-agent'] || 'unknown'
            },
            ip_address: req.ip || req.headers['x-forwarded-for'] || '127.0.0.1'
        },
        { strict: true }
    );
    if (!entry) {
        throw new Error(`Mandatory audit log entry (${action}) could not be persisted.`);
    }
    return entry;
}

// 1. GET ALL CONVERSATIONS / THREADS (Role-Enforced & Mandatory Admin Audit)
exports.getConversations = async (req, res) => {
    try {
        const user = req.user;
        if (!user || !user.id) {
            return res.status(401).json({ success: false, message: 'Authentication required.' });
        }

        if (!isExplicitlyActiveStatus(user.status)) {
            return res.status(403).json({
                success: false,
                code: 'ACCOUNT_DEACTIVATED',
                message: 'Access Denied: Only active accounts may access chat conversations.'
            });
        }

        const chatRole = req.chatRole || mapUserRoleToChatRole(user.role);
        if (!chatRole || chatRole === 'SUB_ADMIN') {
            return res.status(403).json({
                success: false,
                message: 'Access Denied: You are not authorized to access chat conversations.'
            });
        }

        const isMainAdmin = chatRole === 'ADMIN';
        const conversations = await ChatMessage.getConversations(user);

        // Mandatory Audit Log before returning Main Admin conversation list (fails closed if audit fails)
        if (isMainAdmin) {
            await recordMandatoryAdminAudit({
                req,
                user,
                action: 'ADMIN_CHAT_CONVERSATIONS_LIST',
                targetResource: 'ALL_CONVERSATIONS',
                details: { threadsCount: conversations.length }
            });
        }

        res.json({
            success: true,
            count: conversations.length,
            conversations
        });
    } catch (err) {
        console.error('Get Conversations Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to fetch conversations securely.' });
    }
};

// 2. GET CHAT MESSAGES FROM SUPABASE DATABASE (Strictly Conversation-Scoped & Fail-Closed)
// - Rejects empty/missing conversationId & roomId (NEVER calls ChatMessage.find({})!)
// - Rejects requests when exact conversation cannot be resolved
// - Main Admin: verifies target conversation/room + persists mandatory audit log BEFORE returning messages
exports.getMessages = async (req, res) => {
    const rawRoomId = req.query?.roomId || req.query?.room_id || '';
    const rawConvId = req.query?.conversationId || req.query?.conversation_id || '';
    const roomId = String(rawRoomId).trim() || null;
    const conversationId = String(rawConvId).trim() || null;
    const markRead = req.query?.markRead;

    try {
        const user = req.user;
        if (!user || !user.id) {
            return res.status(401).json({ success: false, message: 'Authentication required.' });
        }

        if (!isExplicitlyActiveStatus(user.status)) {
            return res.status(403).json({
                success: false,
                code: 'ACCOUNT_DEACTIVATED',
                message: 'Access Denied: Only active accounts may view chat messages.'
            });
        }

        const chatRole = req.chatRole || mapUserRoleToChatRole(user.role);
        if (!chatRole || chatRole === 'SUB_ADMIN') {
            return res.status(403).json({
                success: false,
                message: 'Access Denied: You are not authorized to view chat messages.'
            });
        }

        if (!roomId && !conversationId) {
            return res.status(400).json({
                success: false,
                message: 'A valid conversationId or roomId is required to fetch messages.'
            });
        }

        // Resolve and authorize exact conversation for ALL roles (including Main Admin)
        const authCtx = (!conversationId && req.authorizedChatContext)
            ? req.authorizedChatContext
            : await Schemas.authorizeChatParticipantAndReceiver({
                callerUser: user,
                roomId,
                conversationId,
                operation: 'ACCESS'
            });

        if (!authCtx.authorized) {
            return res.status(authCtx.status || 403).json({
                success: false,
                message: authCtx.message || 'Access Denied: Target conversation could not be resolved or is unauthorized.'
            });
        }

        const resolvedConvId = authCtx.resolvedConversationId || null;
        const resolvedRoomId = authCtx.targetRoomId || authCtx.rawOrNormalizedRoomId || roomId || null;

        // If caller explicitly supplied conversationId, we MUST scope strictly by conversation_id
        if (conversationId && !resolvedConvId) {
            return res.status(404).json({
                success: false,
                message: 'Target conversation could not be resolved.'
            });
        }

        if (!resolvedConvId && !resolvedRoomId) {
            return res.status(400).json({
                success: false,
                message: 'Unable to resolve conversation scope.'
            });
        }

        const findQuery = resolvedConvId
            ? { conversation_id: resolvedConvId }
            : { room_id: resolvedRoomId, roomIds: authCtx.scopeRoomIds };

        const messages = await ChatMessage.find(findQuery, { user });

        const isMainAdmin = chatRole === 'ADMIN';

        // Only active clinical/patient participants mark messages read when opening a thread (never Admin audit views)
        if (!isMainAdmin && (markRead === 'true' || markRead === '1')) {
            await ChatMessage.markAsRead({
                conversationId: resolvedConvId,
                roomId: resolvedRoomId,
                roomIds: authCtx.scopeRoomIds,
                userId: user.id
            }).catch(() => { });
        }

        // Mandatory Audit Log BEFORE returning messages when Main Admin inspects a conversation
        if (isMainAdmin) {
            await recordMandatoryAdminAudit({
                req,
                user,
                action: 'ADMIN_CHAT_MESSAGES_VIEW',
                targetResource: conversationId || resolvedRoomId || resolvedConvId,
                details: {
                    roomId: resolvedRoomId || null,
                    conversationId: resolvedConvId || null,
                    messageCount: messages.length
                }
            });
        }

        res.json({
            success: true,
            count: messages.length,
            messages
        });
    } catch (err) {
        console.error('Get Messages Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to fetch chat messages securely.' });
    }
};

// 3. SEND CHAT MESSAGE (Strict Sender, Receiver, Status & Mandatory Admin Audit)
exports.sendMessage = async (req, res) => {
    const {
        roomId,
        room_id,
        conversationId,
        conversation_id,
        senderId,
        sender_id,
        receiverId,
        receiver_id,
        message,
        type,
        message_type,
        messageType
    } = req.body || {};

    try {
        if (!req.user || !req.user.id) {
            return res.status(401).json({
                success: false,
                message: 'Authentication required to send chat messages.'
            });
        }

        const trimmedMsg = (message || '').toString().trim();
        if (!trimmedMsg) {
            return res.status(400).json({
                success: false,
                message: 'Message text cannot be empty.'
            });
        }

        const targetRoomInput = roomId || room_id || null;
        const targetConvInput = conversationId || conversation_id || null;
        const targetReceiverInput = receiverId ?? receiver_id ?? null;
        const suppliedSenderInput = senderId ?? sender_id ?? null;

        // Full fail-closed authorization of logged-in sender, active account status, active conversation, and receiver
        const authResult = await Schemas.authorizeChatParticipantAndReceiver({
            callerUser: req.user,
            roomId: targetRoomInput,
            conversationId: targetConvInput,
            receiverId: targetReceiverInput,
            senderIdFromBody: suppliedSenderInput,
            operation: 'SEND'
        });

        if (!authResult.authorized) {
            return res.status(authResult.status || 403).json({
                success: false,
                message: authResult.message || 'Access Denied: You are not authorized to send this message.'
            });
        }

        // Persist mandatory Admin audit record BEFORE committing Admin message so audit failures abort the send
        if (authResult.senderChatRole === 'ADMIN') {
            await recordMandatoryAdminAudit({
                req,
                user: authResult.senderUser,
                action: 'ADMIN_CHAT_MESSAGE_SEND',
                targetResource: String(targetConvInput || '').trim() || authResult.targetRoomId || authResult.resolvedConversationId,
                details: {
                    roomId: authResult.targetRoomId,
                    conversationId: authResult.resolvedConversationId || null,
                    receiverId: authResult.receiverUser?.id || null
                }
            });
        }

        const outgoingType = resolveOutgoingLegacyType(type || message_type || messageType, authResult.senderChatRole);

        const chat = await ChatMessage.create(
            {
                room_id: authResult.targetRoomId,
                ...(authResult.resolvedConversationId ? { conversation_id: authResult.resolvedConversationId } : {}),
                sender_id: authResult.senderUser.id,
                receiver_id: authResult.receiverUser ? authResult.receiverUser.id : null,
                message: trimmedMsg,
                type: outgoingType,
                ...(message_type || messageType ? { message_type: message_type || messageType } : {})
            },
            {
                authorizedCaller: authResult.senderUser,
                authorizedChatRole: authResult.senderChatRole
            }
        );

        res.status(201).json({
            success: true,
            message: 'Chat message sent and saved to database successfully.',
            chat
        });
    } catch (err) {
        if (err && (err.statusCode === 400 || err.statusCode === 401 || err.statusCode === 403 || err.statusCode === 404)) {
            return res.status(err.statusCode).json({ success: false, message: err.message });
        }
        console.error('Send Chat Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to save chat message to database.' });
    }
};

// 3b. MARK CHAT ROOM MESSAGES AS READ (Exact Conversation Scoping & Timestamp Checks)
exports.markRoomRead = async (req, res) => {
    const rawRoomId = req.body?.roomId || req.body?.room_id || req.query?.roomId || req.query?.room_id || '';
    const rawConvId = req.body?.conversationId || req.body?.conversation_id || req.query?.conversationId || req.query?.conversation_id || '';
    const roomId = String(rawRoomId).trim() || null;
    const conversationId = String(rawConvId).trim() || null;
    const lastReadMessageId = req.body?.lastReadMessageId || req.body?.last_read_message_id || req.body?.messageId || req.body?.message_id || null;
    const suppliedReadAt = req.body?.lastReadAt ?? req.body?.last_read_at ?? req.body?.readAt ?? req.body?.read_at;
    const suppliedUserId = req.body?.userId ?? req.body?.user_id ?? null;

    try {
        if (!req.user || !req.user.id) {
            return res.status(401).json({ success: false, message: 'Authentication required.' });
        }

        if (!roomId && !conversationId) {
            return res.status(400).json({ success: false, message: 'roomId or conversationId is required.' });
        }

        // Reject attempts to mark read on behalf of a different user
        if (suppliedUserId && String(suppliedUserId).trim() !== String(req.user.id).trim()) {
            return res.status(403).json({
                success: false,
                message: 'Access Denied: Cannot update read receipts for another user.'
            });
        }

        // Prevent independent read-timestamp manipulation without a valid message reference
        if (suppliedReadAt !== undefined && suppliedReadAt !== null && !lastReadMessageId) {
            return res.status(400).json({
                success: false,
                message: 'Cannot set or modify read timestamps independently without a valid lastReadMessageId.'
            });
        }

        const authCtx = await Schemas.authorizeChatParticipantAndReceiver({
            callerUser: req.user,
            roomId,
            conversationId,
            operation: 'READ_RECEIPT'
        });

        if (!authCtx.authorized) {
            return res.status(authCtx.status || 403).json({
                success: false,
                message: authCtx.message || 'Access Denied: Not authorized to update read receipts for this conversation.'
            });
        }

        // Admin audit role does not mutate clinical participant read receipts
        if (authCtx.senderChatRole === 'ADMIN') {
            return res.status(403).json({
                success: false,
                message: 'Access Denied: Administrative oversight accounts cannot modify clinical read receipts.'
            });
        }

        const resolvedConvId = authCtx.resolvedConversationId || null;
        const effectiveRoom = authCtx.targetRoomId || roomId;

        if (conversationId && !resolvedConvId) {
            return res.status(404).json({
                success: false,
                message: 'Target conversation could not be resolved.'
            });
        }

        // Validate lastReadMessageId strictly against exact conversation_id when conversation exists
        // (never relying solely on roomId)
        if (lastReadMessageId) {
            const cleanLastReadMsgId = String(lastReadMessageId).trim();
            const scopedQuery = resolvedConvId
                ? { conversation_id: resolvedConvId }
                : { room_id: effectiveRoom };
            const scopedMessages = await ChatMessage.find(scopedQuery);
            const matchedMsg = (scopedMessages || []).find(m =>
                String(m.id) === cleanLastReadMsgId &&
                m.is_deleted !== true &&
                (resolvedConvId ? String(m.conversation_id || '') === String(resolvedConvId) : !m.conversation_id)
            );
            if (!matchedMsg) {
                return res.status(403).json({
                    success: false,
                    message: 'Invalid lastReadMessageId: message does not belong to the authorized conversation.'
                });
            }

            if (suppliedReadAt !== undefined && suppliedReadAt !== null) {
                const parsedReadTs = Date.parse(String(suppliedReadAt));
                const msgCreatedTs = matchedMsg.created_at ? Date.parse(String(matchedMsg.created_at)) : 0;
                const nowTs = Date.now();
                if (
                    Number.isNaN(parsedReadTs) ||
                    (msgCreatedTs > 0 && parsedReadTs < msgCreatedTs) ||
                    parsedReadTs > (nowTs + 5000)
                ) {
                    return res.status(400).json({
                        success: false,
                        message: 'Invalid lastReadAt timestamp for the specified message.'
                    });
                }
            }
        }

        const updatedCount = await ChatMessage.markAsRead({
            conversationId: resolvedConvId,
            roomId: effectiveRoom,
            userId: authCtx.senderUser.id,
            lastReadMessageId: lastReadMessageId || null
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

// 4. CLEAR CHAT MESSAGES FROM SUPABASE DATABASE (Main Admin Only + Mandatory Pre-Clear Audit)
exports.clearMessages = async (req, res) => {
    const rawRoomId = req.body?.roomId || req.query?.roomId || req.body?.room_id || req.query?.room_id || '';
    const rawConvId = req.body?.conversationId || req.query?.conversationId || req.body?.conversation_id || req.query?.conversation_id || '';
    const rawMessageId = req.body?.messageId || req.query?.messageId || '';
    const roomId = String(rawRoomId).trim() || null;
    const conversationId = String(rawConvId).trim() || null;
    const messageId = String(rawMessageId).trim() || null;

    try {
        const user = req.user;
        if (!user || !user.id) {
            return res.status(401).json({ success: false, message: 'Authentication required.' });
        }

        if (!isExplicitlyActiveStatus(user.status)) {
            return res.status(403).json({
                success: false,
                code: 'ACCOUNT_DEACTIVATED',
                message: 'Access Denied: Only active Admin accounts may clear clinical chat records.'
            });
        }

        const chatRole = req.chatRole || mapUserRoleToChatRole(user.role);
        if (chatRole !== 'ADMIN') {
            return res.status(403).json({
                success: false,
                message: 'Access Denied: Only the Main Admin is authorized to clear or delete clinical chat records.'
            });
        }

        if (!roomId && !conversationId && !messageId) {
            return res.status(400).json({
                success: false,
                message: 'conversationId, roomId, or messageId is required.'
            });
        }

        // Write mandatory audit log BEFORE executing delete so audit failure aborts the deletion
        await recordMandatoryAdminAudit({
            req,
            user,
            action: 'ADMIN_CHAT_CLEAR',
            targetResource: conversationId || roomId || messageId,
            details: { conversationId, roomId, messageId }
        });

        await ChatMessage.delete({ conversationId, roomId, messageId });

        res.json({
            success: true,
            message: 'Chat history cleared successfully.'
        });
    } catch (err) {
        console.error('Clear Chat Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to clear chat history securely.' });
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
