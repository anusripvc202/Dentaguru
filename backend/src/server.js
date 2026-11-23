require('dotenv').config();
const http = require('http');
const https = require('https');
const app = require('./app');
const { connectPostgresDB } = require('./config/db');
const { initializeStorageBucket } = require('./config/supabase');
const { validateCloudSecuritySecrets, isCloudEnv } = require('./config/secrets');
const { Server } = require('socket.io');
const { initializeFirebase } = require('./services/notificationService');
const { otpStoreService, isOnScreenOtpTestMode } = require('./services/otpStoreService');

const PORT = process.env.PORT || 5000;

const PRODUCTION_KEEP_ALIVE_URL = 'https://dentaguru-backend.onrender.com/api/v1/clinics';
const PRODUCTION_RENDER_HOST = 'dentaguru-backend.onrender.com';

/**
 * Resolve keep-alive ping URL:
 * - Always-On Starter hosting (ALWAYS_ON_HOSTING === 'true'): returns null (self-pings are unnecessary on paid instances).
 * - Production (NODE_ENV === 'production'): unchanged unless ALWAYS_ON_HOSTING=true.
 * - Non-production (local development / staging / test): disabled unless a non-production KEEP_ALIVE_URL or RENDER_EXTERNAL_URL is explicitly set.
 */
function resolveKeepAliveUrl(env = process.env) {
    if ((env.ALWAYS_ON_HOSTING || '').trim().toLowerCase() === 'true') {
        return null;
    }

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

function getSocketCorsOrigin(env = process.env) {
    const raw = (env.CORS_ORIGIN || '').trim();
    if (!raw || raw === '*') {
        return isCloudEnv(env) ? false : '*';
    }
    return raw.split(',').map(s => s.trim().replace(/\/+$/, '')).filter(Boolean);
}

function startServer() {
    // Fail-fast startup security checks for staging & production:
    // enforces strong JWT_SECRET / REFRESH_SECRET / OTP_SALT and Supabase RPC isolation.
    validateCloudSecuritySecrets(process.env);
    if (isCloudEnv(process.env) || isOnScreenOtpTestMode()) {
        otpStoreService._ensureProductionConfig();
    }

    // Initialize Firebase Admin SDK for FCM push notifications
    initializeFirebase();

    // Connect to Supabase PostgreSQL Database & ensure default storage bucket exists
    connectPostgresDB();
    initializeStorageBucket().catch(() => { });

    // Create HTTP Server
    const server = http.createServer(app);

    // Configure Socket.io
    const io = new Server(server, {
        cors: {
            origin: getSocketCorsOrigin(process.env),
            methods: ['GET', 'POST']
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

    let keepAliveTimer = null;

    // Graceful Shutdown (SIGTERM / SIGINT)
    const gracefulShutdown = (signal) => {
        console.log(`🛑 Received ${signal}. Closing HTTP & Socket.io servers gracefully...`);
        if (keepAliveTimer) {
            clearInterval(keepAliveTimer);
            keepAliveTimer = null;
        }
        try {
            io.close();
        } catch (_) { }
        server.close(() => {
            console.log('✅ All open connections closed cleanly. Exiting process.');
            process.exit(0);
        });
        setTimeout(() => {
            console.error('⚠️ Forced shutdown after 10s timeout.');
            process.exit(1);
        }, 10000).unref();
    };

    process.once('SIGTERM', () => gracefulShutdown('SIGTERM'));
    process.once('SIGINT', () => gracefulShutdown('SIGINT'));

    // Start Server listening
    const HOST = '0.0.0.0';
    server.listen(Number(PORT) || 5000, HOST, () => {
        console.log(`GS HEALTH API server running on ${HOST}:${PORT} [NODE_ENV=${process.env.NODE_ENV || 'development'}]`);
        if (isOnScreenOtpTestMode()) {
            console.log('🧪 [On-Screen OTP Testing Mode] ACTIVE — Real SMS hard-blocked; Supabase RPC storage enforced.');
        }

        // Keep-Alive Auto-Ping Service (disabled in local dev and on Always-On Starter hosting)
        const keepAliveUrl = resolveKeepAliveUrl(process.env);
        if (!keepAliveUrl) {
            const reason = (process.env.ALWAYS_ON_HOSTING || '').trim().toLowerCase() === 'true'
                ? 'skipped on Always-On Starter hosting'
                : 'disabled in local development';
            console.log(`ℹ️ [Keep-Alive] ${reason}.`);
            return;
        }

        const httpDriver = keepAliveUrl.startsWith('https') ? https : http;

        const pingServer = () => {
            try {
                const req = httpDriver.get(keepAliveUrl, (res) => {
                    res.resume();
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
        setTimeout(pingServer, 5000).unref();
        keepAliveTimer = setInterval(pingServer, 3 * 60 * 1000);
        keepAliveTimer.unref();
    });

    return server;
}

if (require.main === module) {
    process.on('unhandledRejection', (reason) => {
        console.error('❌ Unhandled Promise Rejection:', reason instanceof Error ? reason.stack : reason);
    });
    process.on('uncaughtException', (err) => {
        console.error('❌ Uncaught Exception (exiting for automatic supervisor restart):', err.stack || err.message);
        process.exit(1);
    });
    startServer();
}

module.exports = {
    resolveKeepAliveUrl,
    startServer,
    PRODUCTION_KEEP_ALIVE_URL,
};
