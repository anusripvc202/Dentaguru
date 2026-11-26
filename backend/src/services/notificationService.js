const admin = require('firebase-admin');

// Initialize Firebase Admin SDK using service account credentials from env
// In production: set FIREBASE_SERVICE_ACCOUNT env var as a JSON string of your
// Firebase service account key downloaded from Firebase Console > Project Settings > Service Accounts
let firebaseApp;

const INVALID_FCM_ERROR_CODES = new Set([
    'messaging/registration-token-not-registered',
    'messaging/invalid-registration-token',
    'messaging/invalid-argument',
    'messaging/mismatched-credential',
]);

function isInvalidFcmTokenError(err) {
    if (!err) return false;
    const code = String(err.code || err.errorInfo?.code || '').trim().toLowerCase();
    if (INVALID_FCM_ERROR_CODES.has(code)) return true;
    const msg = String(err.message || '').toLowerCase();
    return msg.includes('requested entity was not found') ||
        msg.includes('registration token is not a valid') ||
        msg.includes('not registered');
}

const initializeFirebase = () => {
    if (firebaseApp) return firebaseApp;

    try {
        const serviceAccount = process.env.FIREBASE_SERVICE_ACCOUNT
            ? JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT)
            : null;

        if (serviceAccount) {
            firebaseApp = admin.initializeApp({
                credential: admin.credential.cert(serviceAccount),
            });
            console.log('✅ Firebase Admin SDK initialized successfully.');
        } else {
            console.warn('⚠️  FIREBASE_SERVICE_ACCOUNT env not set. FCM notifications will be disabled.');
        }
    } catch (err) {
        console.error('❌ Firebase Admin initialization error:', err.message);
    }

    return firebaseApp;
};

/**
 * Send a Firebase Cloud Messaging (FCM) push notification to a single device.
 * Returns a structured delivery result `{ ok, skipped, invalidToken, messageId, errorCode, errorMessage }`.
 * @param {string} deviceToken - FCM registration token stored on the user document
 * @param {string} title       - Notification title
 * @param {string} body        - Notification body text
 * @param {object} data        - Optional key-value data payload
 */
const sendPushNotification = async (deviceToken, title, body, data = {}) => {
    if (!deviceToken) {
        console.log('FCM: No device token provided, skipping notification.');
        return { ok: false, skipped: true, invalidToken: false, reason: 'NO_DEVICE_TOKEN' };
    }

    if (!admin.apps.length) {
        console.warn('FCM: Firebase not initialized, skipping notification.');
        return { ok: false, skipped: true, invalidToken: false, reason: 'FIREBASE_NOT_INITIALIZED' };
    }

    const message = {
        token: deviceToken,
        notification: { title, body },
        data: Object.fromEntries(
            Object.entries(data).map(([k, v]) => [k, String(v)])
        ),
        android: {
            priority: 'high',
            notification: {
                icon: 'ic_launcher',
                color: '#0B41CD',
                sound: 'default',
                channelId: 'dentaguru_high_importance',
                notificationPriority: 'PRIORITY_HIGH',
                visibility: 'PUBLIC',
                defaultSound: true,
                defaultVibrateTimings: true,
            },
        },
        apns: {
            payload: {
                aps: {
                    sound: 'default',
                    badge: 1,
                    contentAvailable: true,
                },
            },
        },
    };

    try {
        const response = await admin.messaging().send(message);
        console.log(`✅ FCM notification sent. Message ID: ${response}`);
        return { ok: true, skipped: false, invalidToken: false, messageId: response };
    } catch (err) {
        const invalidToken = isInvalidFcmTokenError(err);
        const errorCode = err?.code || err?.errorInfo?.code || 'FCM_SEND_ERROR';
        console.error('❌ FCM send error:', err.message);
        return {
            ok: false,
            skipped: false,
            invalidToken,
            errorCode,
            errorMessage: err.message,
        };
    }
};

/**
 * Send FCM to multiple device tokens at once (multicast).
 * @param {string[]} tokens - Array of FCM device tokens
 * @param {string} title
 * @param {string} body
 * @param {object} data
 */
const sendMulticastNotification = async (tokens, title, body, data = {}) => {
    if (!tokens || tokens.length === 0) return { successCount: 0, failureCount: 0, invalidTokens: [] };
    if (!admin.apps.length) {
        console.warn('FCM: Firebase not initialized, skipping multicast.');
        return { successCount: 0, failureCount: 0, invalidTokens: [], skipped: true };
    }

    const message = {
        tokens,
        notification: { title, body },
        data: Object.fromEntries(
            Object.entries(data).map(([k, v]) => [k, String(v)])
        ),
        android: { notification: { color: '#0B41CD', sound: 'default' } },
        apns: { payload: { aps: { sound: 'default' } } },
    };

    try {
        const response = await admin.messaging().sendEachForMulticast(message);
        const invalidTokens = [];
        if (Array.isArray(response?.responses)) {
            response.responses.forEach((r, idx) => {
                if (!r.success && isInvalidFcmTokenError(r.error)) {
                    invalidTokens.push(tokens[idx]);
                }
            });
        }
        console.log(`✅ FCM multicast: ${response.successCount} sent, ${response.failureCount} failed.`);
        return { ...response, invalidTokens };
    } catch (err) {
        console.error('❌ FCM multicast error:', err.message);
        return { successCount: 0, failureCount: tokens.length, invalidTokens: [], errorMessage: err.message };
    }
};

module.exports = {
    initializeFirebase,
    sendPushNotification,
    sendMulticastNotification,
    isInvalidFcmTokenError,
};
