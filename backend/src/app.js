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
function buildCorsOriginEvaluator(env = process.env) {
    const rawOrigins = (env.CORS_ORIGIN || '').trim();
    const allowlist = rawOrigins
        .split(',')
        .map(o => o.trim().replace(/\/+$/, ''))
        .filter(o => o.length > 0 && o !== '*');

    const nodeEnv = (env.NODE_ENV || 'development').trim().toLowerCase();
    const isCloud = nodeEnv === 'production' || nodeEnv === 'staging';

    if (allowlist.length === 0) {
        if (isCloud && rawOrigins !== '*') {
            console.warn(`⚠️ [${nodeEnv}] CORS_ORIGIN is not set; browser cross-origin requests will be restricted to native mobile/non-origin clients.`);
            return (origin, callback) => {
                if (!origin) return callback(null, true);
                return callback(new Error('Origin not allowed by CORS policy.'), false);
            };
        }
        return '*';
    }

    return (origin, callback) => {
        if (!origin) return callback(null, true);
        const normalized = origin.trim().replace(/\/+$/, '');
        if (allowlist.includes(normalized)) {
            return callback(null, true);
        }
        return callback(new Error('Origin not allowed by CORS policy.'), false);
    };
}

const corsOptions = {
    origin: buildCorsOriginEvaluator(process.env),
    methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization', 'Accept', 'X-Requested-With', 'x-user-id', 'X-User-Id', 'x-staging-otp-key', 'X-Staging-Otp-Key'],
    credentials: true
};
app.use(cors(corsOptions));
app.options('*', cors(corsOptions));
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));

// Safe structured request logger (never logs bodies, OTP codes, passwords, or auth tokens)
app.use((req, res, next) => {
    const startedAt = Date.now();
    res.on('finish', () => {
        if (process.env.NODE_ENV === 'test') return;
        const durationMs = Date.now() - startedAt;
        const cleanPath = (req.originalUrl || req.url || '').split('?')[0];
        console.log(`[HTTP] ${req.method} ${cleanPath} -> ${res.statusCode} (${durationMs}ms)`);
    });
    next();
});

// ─────────────────────────────────────────────
// 2. SECURITY HEADERS — Helmet.js
// ─────────────────────────────────────────────
app.use(helmet({ crossOriginResourcePolicy: false }));

// Force HTTPS behind cloud reverse proxy in staging/production
if (process.env.NODE_ENV === 'production' || process.env.NODE_ENV === 'staging') {
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

// General API rate limit: 100 requests per 15 minutes in production (relaxed in local development/staging testing)
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

// Health check endpoint with live Supabase PostgreSQL diagnostic status (returns HTTP 503 when unhealthy)
app.get('/health', async (req, res) => {
    const supabaseHealth = await checkSupabaseHealth();
    const dbHealthy = supabaseHealth.status === 'connected';
    const postgresStatus = (isPostgresConnected() || dbHealthy) ? 'connected' : 'disconnected';

    if (!dbHealthy) {
        return res.status(503).json({
            status: 'unhealthy',
            timestamp: new Date(),
            version: '2.0.0',
            services: {
                database: {
                    engine: 'PostgreSQL (Supabase)',
                    status: 'disconnected',
                },
                supabase: supabaseHealth
            }
        });
    }

    return res.status(200).json({
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

app.buildCorsOriginEvaluator = buildCorsOriginEvaluator;

module.exports = app;
