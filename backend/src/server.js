require('dotenv').config();
const http = require('http');
const https = require('https');
const app = require('./app');
const { connectPostgresDB } = require('./config/db');
const { Server } = require('socket.io');
const { initializeFirebase } = require('./services/notificationService');
const { otpStoreService, isOnScreenOtpTestMode } = require('./services/otpStoreService');

const PORT = process.env.PORT || 5000;

const PRODUCTION_KEEP_ALIVE_URL = 'https://dentaguru-backend.onrender.com/api/v1/clinics';
const PRODUCTION_RENDER_HOST = 'dentaguru-backend.onrender.com';

/**
 * Resolve keep-alive ping URL:
 * - Production (NODE_ENV === 'production'): unchanged (KEEP_ALIVE_URL, RENDER_EXTERNAL_URL, or production Render URL).
 * - Non-production (local development / test): disabled (returns null) unless a non-production
 *   KEEP_ALIVE_URL or RENDER_EXTERNAL_URL is explicitly set. Never pings production Render in local dev.
 */
function resolveKeepAliveUrl(env = process.env) {
    const nodeEnv = (env.NODE_ENV || 'development').trim().toLowerCase();
    const explicitKeepAlive = (env.KEEP_ALIVE_URL || '').trim();
    const renderExternal = (env.RENDER_EXTERNAL_URL || '').trim();

    if (nodeEnv !== 'production') {
        const candidate = explicitKeepAlive
            || (renderExternal ? `${renderExternal.replace(/\/+$/, '')}/api/v1/clinics` : '');
        if (!candidate) {
            return null;
        }
        if (candidate.toLowerCase().includes(PRODUCTION_RENDER_HOST)) {
            return null;
        }
        return candidate;
    }

    return explicitKeepAlive
        || (renderExternal ? `${renderExternal.replace(/\/+$/, '')}/api/v1/clinics` : PRODUCTION_KEEP_ALIVE_URL);
}

function startServer() {
    // Fail-fast startup guard when OTP_DELIVERY_MODE=on_screen is enabled:
    // requires a separate testing Supabase project and refuses connecting to production Supabase.
    if (isOnScreenOtpTestMode()) {
        otpStoreService._ensureProductionConfig();
    }

    // Initialize Firebase Admin SDK for FCM push notifications
    initializeFirebase();

    // Connect to Supabase PostgreSQL Database
    connectPostgresDB();

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
    const HOST = '0.0.0.0';
    server.listen(Number(PORT) || 5000, HOST, () => {
        console.log(`GS HEALTH API server running on ${HOST}:${PORT} [NODE_ENV=${process.env.NODE_ENV || 'development'}]`);
        if (isOnScreenOtpTestMode()) {
            console.log('🧪 [On-Screen OTP Testing Mode] ACTIVE — Real SMS hard-blocked; Supabase RPC storage enforced.');
        }

        // Keep-Alive Auto-Ping Service
        // Production behavior unchanged; disabled during local development so dev never pings production Render.
        const keepAliveUrl = resolveKeepAliveUrl(process.env);
        if (!keepAliveUrl) {
            console.log('ℹ️ [Keep-Alive] Disabled in local development (production Render ping skipped).');
            return;
        }

        const httpDriver = keepAliveUrl.startsWith('https') ? https : http;

        const pingServer = () => {
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
        };

        // Ping immediately on launch, then every 3 minutes
        setTimeout(pingServer, 5000);
        setInterval(pingServer, 3 * 60 * 1000);
    });

    return server;
}

if (require.main === module) {
    startServer();
}

module.exports = {
    resolveKeepAliveUrl,
    startServer,
    PRODUCTION_KEEP_ALIVE_URL,
};
