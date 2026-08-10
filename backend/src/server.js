require('dotenv').config();
const http = require('http');
const https = require('https');
const app = require('./app');
const { connectDB } = require('./config/db');
const { Server } = require('socket.io');
const { initializeFirebase } = require('./services/notificationService');

const PORT = process.env.PORT || 5000;

// Initialize Firebase Admin SDK for FCM push notifications
initializeFirebase();

// Connect to MongoDB Database
connectDB();

// Create HTTP Server
const server = http.createServer(app);

// Configure Socket.io
const io = new Server(server, {
    cors: {
        origin: "*",
        methods: ["GET", "POST"]
    }
});

// Configure Socket Connection Logic (Chat & Real-time Alerts)
io.on('connection', (socket) => {
    console.log(`Socket Client Connected: ${socket.id}`);

    // Join room for chat
    socket.on('join_room', (roomId) => {
        socket.join(roomId);
        console.log(`Socket client joined room: ${roomId}`);
    });

    // Send and broadcast chat messages
    socket.on('send_message', (data) => {
        // data structure: { roomId, senderId, receiverId, message, type }
        socket.to(data.roomId).emit('receive_message', data);
        console.log(`Message broadcast in room: ${data.roomId}`);
    });

    socket.on('disconnect', () => {
        console.log(`Socket Client Disconnected: ${socket.id}`);
    });
});

// Start Server listening
server.listen(PORT, () => {
    console.log(`Denta Guru API server running on port: ${PORT}`);

    // Keep-Alive Auto-Ping Service (Keeps Render server 100% awake 24/7 with 0 cold-start delay)
    const keepAliveUrl = process.env.RENDER_EXTERNAL_URL || 'https://dentaguru-backend.onrender.com';
    const httpDriver = keepAliveUrl.startsWith('https') ? https : http;

    setInterval(() => {
        try {
            const req = httpDriver.get(keepAliveUrl, (res) => {
                console.log(`⚡ Keep-Alive ping executed (Status: ${res.statusCode}) - Server Warm 24/7.`);
            });
            req.on('error', (err) => {
                console.warn('⚠️ Keep-Alive ping warning:', err.message);
            });
        } catch (e) {
            console.warn('⚠️ Keep-Alive exception:', e.message);
        }
    }, 10 * 60 * 1000); // Self-ping every 10 minutes
});
