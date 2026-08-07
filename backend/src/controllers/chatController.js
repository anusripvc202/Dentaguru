const { ChatMessage } = require('../models/Schemas');

// 1. SEND CHAT MESSAGE (Saved to Supabase 'chat_messages' table)
exports.sendMessage = async (req, res) => {
    const { roomId, senderId, receiverId, message, type, senderRole } = req.body;
    try {
        const sStr = String(senderId || '').toLowerCase();
        const isDoc = type === 'doctor' || senderRole === 'Dentist' || sStr.startsWith('dr.') || sStr.includes('doctor') || sStr.includes('dentist');
        const msgType = isDoc ? 'doctor' : (type === 'patient' ? 'patient' : 'text');

        const chat = await ChatMessage.create({
            room_id: roomId || 'GENERAL-CHAT',
            sender_id: senderId || (req.user ? req.user.id : null),
            receiver_id: receiverId || null,
            message: message || '',
            type: msgType
        });

        console.log(`💬 Chat message saved in Supabase 'chat_messages' table: "${message}"`);
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

// 2. GET CHAT MESSAGES FROM SUPABASE DATABASE
exports.getMessages = async (req, res) => {
    const { roomId } = req.query;
    try {
        const messages = await ChatMessage.find(roomId ? { room_id: roomId } : {});
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

// 3. CLEAR CHAT MESSAGES FROM SUPABASE DATABASE
exports.clearMessages = async (req, res) => {
    const roomId = req.body?.roomId || req.query?.roomId;
    const messageId = req.body?.messageId || req.query?.messageId;
    try {
        await ChatMessage.delete({ roomId, messageId });
        console.log(`🗑️ Cleared chat messages for room "${roomId || messageId}"`);
        res.json({
            success: true,
            message: 'Chat history cleared successfully.'
        });
    } catch (err) {
        console.error('Clear Chat Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to clear chat history.' });
    }
};
