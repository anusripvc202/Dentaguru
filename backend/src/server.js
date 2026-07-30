require('dotenv').config();
const http = require('http');
const app = require('./app');
const connectDB = require('./config/db');
const { Server } = require('socket.io');
const { initializeFirebase } = require('./services/notificationService');

const PORT = process.env.PORT || 5000;

// Initialize Firebase Admin SDK for FCM push notifications
initializeFirebase();


// Connect to Database
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
});
