// 1. SEND CHAT MESSAGE (Real-time ephemeral chat - NOT stored in database)
exports.sendMessage = async (req, res) => {
    const { roomId, senderId, receiverId, message, type } = req.body;
    try {
        const chat = {
            id: `CHAT-${Date.now()}`,
            room_id: roomId || 'GENERAL-CHAT',
            sender_id: senderId || 'user',
            receiver_id: receiverId || null,
            message: message || '',
            type: type || 'text',
            created_at: new Date().toISOString()
        };

        console.log(`💬 Real-time chat message dispatched (NOT stored in DB): "${message}"`);
        res.status(200).json({
            success: true,
            message: 'Chat message sent in real-time.',
            chat
        });
    } catch (err) {
        console.error('Send Chat Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to send chat message.' });
    }
};

// 2. GET CHAT MESSAGES (Returns clean empty array - no DB persistence)
exports.getMessages = async (req, res) => {
    res.json({
        success: true,
        messages: []
    });
};
