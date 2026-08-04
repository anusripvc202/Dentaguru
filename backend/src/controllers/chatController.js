const { ChatMessage, User } = require('../models/Schemas');

// 1. SEND CHAT MESSAGE
exports.sendMessage = async (req, res) => {
    const { roomId, senderId, receiverId, message, type } = req.body;
    try {
        let targetSenderId = senderId || (req.user ? req.user.id : null);
        
        // Resolve sender email/phone if passed
        if (targetSenderId && (targetSenderId.includes('@') || !targetSenderId.includes('-'))) {
            const matchedSender = await User.findOne({ email: targetSenderId }) || await User.findOne({ phone: targetSenderId });
            if (matchedSender) targetSenderId = matchedSender.id;
        }

        // Fallback sender if null
        if (!targetSenderId) {
            const { data: firstUsers } = await require('../config/supabase').supabaseAdmin.from('users').select('id').limit(1);
            if (firstUsers && firstUsers.length > 0) targetSenderId = firstUsers[0].id;
        }

        const chat = await ChatMessage.create({
            room_id: roomId || 'GENERAL-CHAT',
            sender_id: targetSenderId,
            receiver_id: receiverId || null,
            message: message || '',
            type: type || 'text'
        });

        console.log(`💬 Chat message saved in 'chat_messages' table: "${message}"`);
        res.status(201).json({
            success: true,
            message: 'Chat message sent successfully.',
            chat
        });
    } catch (err) {
        console.error('Send Chat Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to send chat message.' });
    }
};

// 2. GET CHAT MESSAGES
exports.getMessages = async (req, res) => {
    const { roomId } = req.query;
    try {
        const messages = await ChatMessage.find(roomId ? { room_id: roomId } : {});
        res.json({
            success: true,
            messages
        });
    } catch (err) {
        console.error('Get Messages Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to fetch chat messages.' });
    }
};
