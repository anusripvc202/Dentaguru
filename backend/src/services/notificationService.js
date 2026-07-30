const admin = require('firebase-admin');

// Initialize Firebase Admin SDK using service account credentials from env
// In production: set FIREBASE_SERVICE_ACCOUNT env var as a JSON string of your
// Firebase service account key downloaded from Firebase Console > Project Settings > Service Accounts
let firebaseApp;

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
 * @param {string} deviceToken - FCM registration token stored on the user document
 * @param {string} title       - Notification title
 * @param {string} body        - Notification body text
 * @param {object} data        - Optional key-value data payload
 */
const sendPushNotification = async (deviceToken, title, body, data = {}) => {
    if (!deviceToken) {
        console.log('FCM: No device token provided, skipping notification.');
        return;
    }

    if (!admin.apps.length) {
        console.warn('FCM: Firebase not initialized, skipping notification.');
        return;
    }

    const message = {
        token: deviceToken,
        notification: { title, body },
        data: Object.fromEntries(
            Object.entries(data).map(([k, v]) => [k, String(v)])
        ),
        android: {
            notification: {
                icon: 'ic_notification',
                color: '#0B41CD',
                sound: 'default',
            },
        },
        apns: {
            payload: {
                aps: {
                    sound: 'default',
                    badge: 1,
                },
            },
        },
    };

    try {
        const response = await admin.messaging().send(message);
        console.log(`✅ FCM notification sent. Message ID: ${response}`);
        return response;
    } catch (err) {
        console.error('❌ FCM send error:', err.message);
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
    if (!tokens || tokens.length === 0) return;
    if (!admin.apps.length) {
        console.warn('FCM: Firebase not initialized, skipping multicast.');
        return;
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
        console.log(`✅ FCM multicast: ${response.successCount} sent, ${response.failureCount} failed.`);
        return response;
    } catch (err) {
        console.error('❌ FCM multicast error:', err.message);
    }
};

module.exports = { initializeFirebase, sendPushNotification, sendMulticastNotification };
