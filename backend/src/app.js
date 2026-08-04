const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const apiRoutes = require('./routes/api');

const app = express();

// ─────────────────────────────────────────────
// 1. CORS & PARSING MIDDLEWARE
// ─────────────────────────────────────────────
app.use(cors({
    origin: '*',
    methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization'],
    credentials: true
}));
app.options('*', cors());
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));

// ─────────────────────────────────────────────
// 2. SECURITY HEADERS — Helmet.js
// ─────────────────────────────────────────────
app.use(helmet({ crossOriginResourcePolicy: false }));

// Force HTTPS in production
if (process.env.NODE_ENV === 'production') {
    app.use((req, res, next) => {
        if (req.headers['x-forwarded-proto'] !== 'https') {
            return res.redirect(301, `https://${req.headers.host}${req.url}`);
        }
        next();
    });
}

// ─────────────────────────────────────────────
// 3. RATE LIMITING — Brute-force protection
// ─────────────────────────────────────────────

// General API rate limit: 100 requests per 15 minutes
const generalLimiter = rateLimit({
    windowMs: 15 * 60 * 1000,
    max: 100,
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

const { isConnected } = require('./config/db');
const { checkSupabaseHealth } = require('./config/supabase');

// Health check endpoint with MongoDB & Supabase diagnostic status
app.get('/health', async (req, res) => {
    const mongoStatus = isConnected() ? 'connected' : 'disconnected';
    const supabaseHealth = await checkSupabaseHealth();

    res.json({
        status: 'healthy',
        timestamp: new Date(),
        version: '2.0.0',
        services: {
            mongodb: {
                status: mongoStatus,
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
