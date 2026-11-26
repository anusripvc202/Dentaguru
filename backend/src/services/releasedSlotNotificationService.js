/**
 * GS HEALTH — Released Earlier Slot Notification Service
 *
 * Notifies eligible patients via FCM & persistent in-app Notification when a doctor finishes
 * a consultation early and releases a genuinely available slot:
 * - Respects favorite doctor + notify_earlier_slots opt-in
 * - Respects preferred consultation type ('Any' | 'Online' | 'In-Person'), preferred date, and time window
 * - Prevents duplicate notifications per (released_slot_id, patient_id)
 * - Safely clears invalid/expired FCM tokens without touching other users.device_token metadata
 * - Never notifies the patient whose own appointment just freed the slot
 */

const {
    User,
    Notification,
    PatientDoctorPreference,
    SlotNotificationDelivery,
} = require('../models/Schemas');
const { sendPushNotification } = require('./notificationService');
const { extractFcmToken, mergeDeviceTokenPayload } = require('../utils/deviceTokenHelper');
const { normalizeConsultationType } = require('../config/bookingRulesConfig');

function isPreferenceEligibleForReleasedSlot(pref, releasedSlot, excludePatientId = null) {
    if (!pref || !releasedSlot) return false;
    const patId = String(pref.patient_id || pref.patientId || '').trim();
    if (!patId) return false;
    if (excludePatientId && patId === String(excludePatientId).trim()) return false;

    const notifyEnabled = Boolean(pref.notify_earlier_slots ?? pref.notifyEarlierSlots);
    if (!notifyEnabled) return false;

    const slotMode = normalizeConsultationType(releasedSlot.consultation_type || releasedSlot.consultationType);
    const prefModeRaw = String(pref.preferred_consultation_type || pref.preferredConsultationType || 'Any').trim();
    if (prefModeRaw && prefModeRaw.toLowerCase() !== 'any') {
        const prefMode = normalizeConsultationType(prefModeRaw);
        if (prefMode !== slotMode) return false;
    }

    const prefDate = pref.preferred_date || pref.preferredDate || null;
    if (prefDate) {
        const cleanPrefDate = String(prefDate).trim().split('T')[0];
        const cleanSlotDate = String(releasedSlot.appointment_date || releasedSlot.appointmentDate || '').trim().split('T')[0];
        if (cleanPrefDate && cleanSlotDate && cleanPrefDate !== cleanSlotDate) return false;
    }

    const slotStartMin = Number(releasedSlot.start_min ?? releasedSlot.startMin);
    const earliest = pref.earliest_time_min ?? pref.earliestTimeMin;
    const latest = pref.latest_time_min ?? pref.latestTimeMin;
    if (Number.isFinite(slotStartMin)) {
        if (earliest !== null && earliest !== undefined && slotStartMin < Number(earliest)) return false;
        if (latest !== null && latest !== undefined && slotStartMin > Number(latest)) return false;
    }

    return true;
}

/**
 * Finds eligible opted-in patients for a released slot, deduplicates deliveries,
 * creates persistent in-app notifications, dispatches FCM pushes, and cleans invalid tokens safely.
 */
async function notifyEligiblePatientsForReleasedSlot({
    dentistId,
    doctorName = 'Your Doctor',
    releasedSlot,
    excludePatientId = null,
    pushSender = sendPushNotification,
}) {
    const summary = {
        releasedSlotId: releasedSlot?.id || null,
        eligibleCount: 0,
        sentCount: 0,
        inAppCreatedCount: 0,
        skippedDuplicates: 0,
        invalidTokensCleared: 0,
        failedCount: 0,
        notifiedPatientIds: [],
    };

    if (!dentistId || !releasedSlot || !releasedSlot.id) {
        return summary;
    }

    const prefs = await PatientDoctorPreference.findNotifyEligibleForDoctor(dentistId).catch(() => []);
    const eligiblePrefs = (prefs || []).filter(p =>
        isPreferenceEligibleForReleasedSlot(p, releasedSlot, excludePatientId)
    );
    summary.eligibleCount = eligiblePrefs.length;
    if (eligiblePrefs.length === 0) {
        return summary;
    }

    const cleanDate = String(releasedSlot.appointment_date || releasedSlot.appointmentDate || '').split('T')[0];
    const startTime = String(releasedSlot.start_time || releasedSlot.startTime || '').trim();
    const consultMode = normalizeConsultationType(releasedSlot.consultation_type || releasedSlot.consultationType);
    const formattedDoctor = doctorName && !doctorName.toLowerCase().startsWith('dr')
        ? `Dr. ${doctorName}`
        : (doctorName || 'Your Doctor');

    const title = `Earlier ${consultMode} Slot Available`;
    const body = `${formattedDoctor} has an earlier ${consultMode} slot open on ${cleanDate} at ${startTime}. Tap to book now (first to confirm gets it).`;
    const notifData = {
        type: 'earlier_slot_available',
        notificationType: 'EARLY_SLOT_RELEASED',
        dentistId: String(dentistId),
        doctorId: String(dentistId),
        date: cleanDate,
        appointmentDate: cleanDate,
        timeSlot: startTime,
        startTime,
        consultationType: consultMode,
        releasedSlotId: String(releasedSlot.id),
        expiresAt: releasedSlot.expires_at || releasedSlot.expiresAt || '',
    };

    for (const pref of eligiblePrefs) {
        const patientId = String(pref.patient_id || pref.patientId || '').trim();
        if (!patientId) continue;

        // Deduplication gate: claim delivery slot atomically before sending
        const claim = await SlotNotificationDelivery.tryClaim(releasedSlot.id, patientId);
        if (!claim.claimed) {
            summary.skippedDuplicates += 1;
            continue;
        }

        try {
            // 1. Always create persistent in-app notification with structured deep-link data
            await Notification.create({
                recipient_role: 'Patient',
                recipient_id: patientId,
                title,
                message: body,
                type: 'earlier_slot_available',
                data: notifData,
            });
            summary.inAppCreatedCount += 1;
            summary.notifiedPatientIds.push(patientId);

            // 2. Dispatch FCM push if patient has a valid token
            const patientUser = await User.findById(patientId).catch(() => null);
            const fcmToken = extractFcmToken(patientUser);
            if (!fcmToken) {
                await SlotNotificationDelivery.updateStatus(releasedSlot.id, patientId, {
                    delivery_status: 'SKIPPED',
                    error_message: 'No registered FCM token',
                });
                continue;
            }

            const pushRes = await pushSender(fcmToken, title, body, notifData);
            if (pushRes && pushRes.ok) {
                summary.sentCount += 1;
                await SlotNotificationDelivery.updateStatus(releasedSlot.id, patientId, {
                    delivery_status: 'SENT',
                    fcm_message_id: pushRes.messageId || null,
                });
            } else if (pushRes && pushRes.invalidToken) {
                summary.failedCount += 1;
                summary.invalidTokensCleared += 1;
                // Safely remove ONLY the expired/invalid FCM token while preserving all other metadata
                try {
                    const cleanedTokenPayload = mergeDeviceTokenPayload(patientUser?.device_token, {
                        fcmToken: null,
                        removeFcmToken: fcmToken,
                    });
                    await User.findByIdAndUpdate(patientId, { device_token: cleanedTokenPayload });
                } catch (_) {}
                await SlotNotificationDelivery.updateStatus(releasedSlot.id, patientId, {
                    delivery_status: 'FAILED',
                    error_message: pushRes.errorCode || 'INVALID_FCM_TOKEN',
                });
            } else if (pushRes && pushRes.skipped) {
                await SlotNotificationDelivery.updateStatus(releasedSlot.id, patientId, {
                    delivery_status: 'SKIPPED',
                    error_message: pushRes.reason || 'FCM_NOT_CONFIGURED',
                });
            } else if (typeof pushRes === 'string' && pushRes.length > 0) {
                summary.sentCount += 1;
                await SlotNotificationDelivery.updateStatus(releasedSlot.id, patientId, {
                    delivery_status: 'SENT',
                    fcm_message_id: pushRes,
                });
            } else {
                summary.failedCount += 1;
                await SlotNotificationDelivery.updateStatus(releasedSlot.id, patientId, {
                    delivery_status: 'FAILED',
                    error_message: (pushRes && (pushRes.errorMessage || pushRes.errorCode)) || 'FCM_SEND_FAILED',
                });
            }
        } catch (err) {
            summary.failedCount += 1;
            await SlotNotificationDelivery.updateStatus(releasedSlot.id, patientId, {
                delivery_status: 'FAILED',
                error_message: err?.message || 'UNEXPECTED_ERROR',
            }).catch(() => {});
        }
    }

    return summary;
}

module.exports = {
    isPreferenceEligibleForReleasedSlot,
    notifyEligiblePatientsForReleasedSlot,
};
