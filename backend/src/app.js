const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const apiRoutes = require('./routes/api');

const app = express();

// Trust proxy for reverse proxy platforms like Render/Vercel
app.set('trust proxy', 1);

// ─────────────────────────────────────────────
// 1. CORS & PARSING MIDDLEWARE
// ─────────────────────────────────────────────
const corsOptions = {
    origin: '*',
    methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization', 'Accept', 'X-Requested-With'],
    credentials: true
};
app.use(cors(corsOptions));
app.options('*', cors(corsOptions));
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));

// ─────────────────────────────────────────────
// 2. SECURITY HEADERS — Helmet.js
// ─────────────────────────────────────────────
app.use(helmet({ crossOriginResourcePolicy: false }));

// Force HTTPS in production when header is present
if (process.env.NODE_ENV === 'production') {
    app.use((req, res, next) => {
        if (req.headers['x-forwarded-proto'] && req.headers['x-forwarded-proto'] !== 'https') {
            return res.redirect(301, `https://${req.headers.host}${req.url}`);
        }
        next();
    });
}

// ─────────────────────────────────────────────
// 3. RATE LIMITING — Brute-force protection
// ─────────────────────────────────────────────

// General API rate limit: 100 requests per 15 minutes in production (relaxed in local development
// so repeated dashboard syncs from localhost do not lock out testing; OTP rate limits stay strictly enforced).
const isProdEnv = (process.env.NODE_ENV || 'development').trim().toLowerCase() === 'production';
const generalLimiter = rateLimit({
    windowMs: 15 * 60 * 1000,
    max: isProdEnv ? 100 : 1000,
    standardHeaders: true,
    legacyHeaders: false,
    message: { success: false, message: 'Too many requests. Please try again later.' },
});

// Strict auth rate limit: 50 attempts per 15 minutes
const authLimiter = rateLimit({
    windowMs: 15 * 60 * 1000,
    max: 50,
    standardHeaders: true,
    legacyHeaders: false,
    message: { success: false, message: 'Too many authentication attempts. Please wait 15 minutes.' },
});

app.use('/api/v1/auth', authLimiter);
app.use('/api/', generalLimiter);

// ─────────────────────────────────────────────
// 4. ROUTES
// ─────────────────────────────────────────────
app.use('/api/v1', apiRoutes);

const { isPostgresConnected, isConnected } = require('./config/db');
const { checkSupabaseHealth } = require('./config/supabase');

// Health check endpoint with Supabase PostgreSQL diagnostic status
app.get('/health', async (req, res) => {
    const postgresStatus = isPostgresConnected() ? 'connected' : 'disconnected';
    const supabaseHealth = await checkSupabaseHealth();

    res.json({
        status: 'healthy',
        timestamp: new Date(),
        version: '2.0.0',
        services: {
            database: {
                engine: 'PostgreSQL (Supabase)',
                status: postgresStatus,
            },
            supabase: supabaseHealth
        }
    });
});

// ─────────────────────────────────────────────
// 5. ERROR HANDLERS
// ─────────────────────────────────────────────
app.use((req, res, next) => {
    res.status(404).json({ success: false, message: 'Resource endpoint not found.' });
});

app.use((err, req, res, next) => {
    console.error(err.stack);
    res.status(500).json({ success: false, message: 'Internal server error occurred.' });
});

module.exports = app;
