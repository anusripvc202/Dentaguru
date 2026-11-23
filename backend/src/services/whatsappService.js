/**
 * DentaGuru WhatsApp Notification Service
 * Delivers real-time WhatsApp updates for Patient Referrals and Status Events.
 */

const https = require('https');
const { isOnScreenOtpTestMode } = require('./otpStoreService');

/**
 * Format clean phone number with standard country code (default +91 if 10 digits)
 */
const formatPhoneNumber = (phone) => {
    if (!phone) return '';
    const digits = String(phone).replace(/[^0-9]/g, '');
    if (digits.length === 10) return `91${digits}`;
    return digits;
};

const isWhatsAppProviderConfigured = () => {
    const hasTwilio = Boolean(process.env.TWILIO_ACCOUNT_SID && process.env.TWILIO_AUTH_TOKEN);
    const hasMeta = Boolean(process.env.WHATSAPP_API_TOKEN && process.env.WHATSAPP_PHONE_NUMBER_ID);
    return hasTwilio || hasMeta;
};

const _recentDispatches = new Map();

/**
 * Generic dispatcher for WhatsApp/SMS notifications.
 * Uses configured Twilio / Meta Cloud API credentials; never simulates delivery when unconfigured.
 */
const dispatchWhatsApp = async ({ to, message, templateName, dedupKey }) => {
    const formattedPhone = formatPhoneNumber(to);
    if (!formattedPhone) {
        console.warn('⚠️ WhatsApp dispatch: No valid recipient phone number provided.');
        return { success: false, providerConfigured: isWhatsAppProviderConfigured(), whatsappStatus: 'NoRecipientPhone', error: 'Invalid or missing phone number' };
    }

    const effectiveDedup = dedupKey ? `${formattedPhone}|${templateName || 'Custom'}|${dedupKey}` : null;
    if (effectiveDedup) {
        const lastSent = _recentDispatches.get(effectiveDedup);
        if (lastSent && Date.now() - lastSent < 60000) {
            return { success: true, deduplicated: true, whatsappStatus: 'Deduplicated' };
        }
        _recentDispatches.set(effectiveDedup, Date.now());
    }

    // 0. On-Screen OTP Testing Mode (NODE_ENV !== 'production' && OTP_DELIVERY_MODE === 'on_screen'):
    // Hard-block external Twilio and Meta WhatsApp API dispatches in testing mode.
    if (isOnScreenOtpTestMode()) {
        console.info(`🧪 [On-Screen OTP Test Mode] External WhatsApp/Twilio dispatch blocked for +${formattedPhone} (${templateName || 'Custom'}).`);
        return {
            success: false,
            providerConfigured: false,
            blockedInTestMode: true,
            whatsappStatus: isWhatsAppProviderConfigured() ? 'BlockedInTestingMode' : 'NotConfigured',
            error: 'External WhatsApp/Twilio dispatch is blocked in on-screen OTP testing mode.'
        };
    }

    // 1. Meta / Twilio WhatsApp Cloud Integration if configured
    const twilioAccountSid = process.env.TWILIO_ACCOUNT_SID;
    const twilioAuthToken = process.env.TWILIO_AUTH_TOKEN;
    const twilioFromNumber = process.env.TWILIO_WHATSAPP_FROM || 'whatsapp:+14155238886';

    if (twilioAccountSid && twilioAuthToken) {
        try {
            const client = require('twilio')(twilioAccountSid, twilioAuthToken);
            const res = await client.messages.create({
                from: twilioFromNumber,
                to: `whatsapp:+${formattedPhone}`,
                body: message,
            });
            console.log(`✅ WhatsApp delivered via Twilio SID: ${res.sid}`);
            return { success: true, providerConfigured: true, whatsappStatus: 'Sent', messageId: res.sid };
        } catch (err) {
            console.error(`❌ Twilio WhatsApp send notice: ${err.message}`);
            return { success: false, providerConfigured: true, whatsappStatus: 'Failed', error: err.message };
        }
    }

    // 2. Meta WhatsApp Cloud API if WHATSAPP_API_TOKEN is present
    const metaToken = process.env.WHATSAPP_API_TOKEN;
    const metaPhoneNumberId = process.env.WHATSAPP_PHONE_NUMBER_ID;

    if (metaToken && metaPhoneNumberId) {
        try {
            const payload = JSON.stringify({
                messaging_product: 'whatsapp',
                to: formattedPhone,
                type: 'text',
                text: { body: message }
            });

            const options = {
                hostname: 'graph.facebook.com',
                port: 443,
                path: `/v18.0/${metaPhoneNumberId}/messages`,
                method: 'POST',
                headers: {
                    'Authorization': `Bearer ${metaToken}`,
                    'Content-Type': 'application/json',
                    'Content-Length': Buffer.byteLength(payload)
                }
            };

            const metaRes = await new Promise((resolve, reject) => {
                const req = https.request(options, (res) => {
                    let data = '';
                    res.on('data', (chunk) => data += chunk);
                    res.on('end', () => resolve({ statusCode: res.statusCode, body: data }));
                });
                req.on('error', reject);
                req.write(payload);
                req.end();
            });

            if (metaRes.statusCode >= 200 && metaRes.statusCode < 300) {
                console.log(`✅ WhatsApp delivered via Meta API to +${formattedPhone}`);
                return { success: true, providerConfigured: true, whatsappStatus: 'Sent', response: metaRes.body };
            } else {
                console.warn(`⚠️ Meta API responded with status ${metaRes.statusCode}: ${metaRes.body}`);
                return { success: false, providerConfigured: true, whatsappStatus: 'Failed', error: metaRes.body };
            }
        } catch (e) {
            console.error(`❌ Meta WhatsApp send notice: ${e.message}`);
            return { success: false, providerConfigured: true, whatsappStatus: 'Failed', error: e.message };
        }
    }

    // 3. External SMS / WhatsApp provider is not configured (do not simulate successful delivery)
    console.info(`ℹ️ External WhatsApp/SMS provider not configured (skipped external send to +${formattedPhone} for ${templateName || 'Custom'}).`);
    return {
        success: false,
        providerConfigured: false,
        whatsappStatus: 'NotConfigured',
        error: 'External WhatsApp/SMS provider credentials are not configured.'
    };
};

/**
 * 1. Send New Referral WhatsApp Notification to REFERRED PATIENT
 */
const sendNewReferralWhatsApp = async ({
    referredPatientName,
    referredPatientMobile,
    doctorName,
    doctorSpecialty,
    doctorClinic,
    doctorAddress,
    doctorCity,
    doctorPincode,
    doctorPhone,
    referrerName,
    clinicalComplaint
}) => {
    let cleanDoc = doctorName || 'Specialist Doctor';
    while (cleanDoc.toLowerCase().startsWith('dr. dr.') || cleanDoc.toLowerCase().startsWith('dr. dr ') || cleanDoc.toLowerCase().startsWith('dr dr ')) {
        cleanDoc = cleanDoc.substring(3).trim();
        if (cleanDoc.startsWith('.')) cleanDoc = cleanDoc.substring(1).trim();
    }
    const formattedDoctor = (cleanDoc.toLowerCase().startsWith('dr.') || cleanDoc.toLowerCase().startsWith('dr '))
        ? cleanDoc
        : `Dr. ${cleanDoc}`;

    const cleanComplaint = clinicalComplaint || 'General Medical Consultation';
    const cleanClinic = doctorClinic && doctorClinic !== 'GS HEALTH Partner Clinic' && doctorClinic !== 'GS HEALTH Partner Dental Clinic' ? doctorClinic : (doctorClinic || 'GS HEALTH Partner Clinic');
    const cleanSpecialty = doctorSpecialty || 'Specialized Healthcare';

    const locationParts = [
        doctorAddress,
        doctorCity,
        doctorPincode ? `PIN: ${doctorPincode}` : ''
    ].filter(s => s && s.trim().length > 0);
    const fullAddress = locationParts.join(', ');

    const mapQueryParts = [
        cleanClinic && cleanClinic !== 'GS HEALTH Partner Clinic' && cleanClinic !== 'GS HEALTH Partner Dental Clinic' ? cleanClinic : '',
        doctorAddress,
        doctorCity,
        doctorPincode
    ].filter(s => s && s.trim().length > 0);
    const mapQuery = mapQueryParts.join(', ');
    const mapUrl = mapQuery.length > 0 ? `https://maps.google.com/?q=${encodeURIComponent(mapQuery)}` : '';

    const lines = [];
    lines.push(`Hi ${referredPatientName || 'Patient'},`);
    lines.push('');
    lines.push(`I have referred you to *${formattedDoctor}* on GS HEALTH for your healthcare consultation.`);
    lines.push('');
    lines.push('👨‍⚕️ *Doctor & Clinic Details:*');
    lines.push(`• *Doctor:* ${formattedDoctor}`);
    lines.push(`• *Specialty:* ${cleanSpecialty}`);
    if (cleanClinic && cleanClinic.length > 0) {
        lines.push(`• *Clinic:* ${cleanClinic}`);
    }
    if (doctorPhone && doctorPhone.trim().length > 0) {
        const cleanPhone = doctorPhone.replace(/^\+91\s*/, '').trim();
        lines.push(`• *Doctor Mobile:* +91 ${cleanPhone}`);
    }
    if (fullAddress && fullAddress.length > 0) {
        lines.push(`• *Address:* ${fullAddress}`);
    }
    if (mapUrl && mapUrl.length > 0) {
        lines.push(`• 📍 *Location Map:* ${mapUrl}`);
    }
    if (cleanComplaint) {
        lines.push('');
        lines.push(`📋 *Clinical Reason / Diagnosis:* ${cleanComplaint}`);
    }
    lines.push('');
    lines.push('You can reach out directly to the clinic or doctor to schedule your appointment. Wishing you the best of health!');

    const message = lines.join('\n');

    return await dispatchWhatsApp({
        to: referredPatientMobile,
        message,
        templateName: 'NEW_REFERRAL_PATIENT'
    });
};

/**
 * 2. Send Referral Accepted WhatsApp Notification to REFERRED PATIENT
 */
const sendReferralAcceptedWhatsApp = async ({
    referredPatientName,
    referredPatientMobile,
    doctorName,
    doctorSpecialty,
    doctorClinic,
    confirmedTimeSlot
}) => {
    const formattedDoctor = doctorName.startsWith('Dr.') ? doctorName : `Dr. ${doctorName}`;
    const cleanClinic = doctorClinic || 'GS HEALTH Partner Clinic';
    const cleanSpecialty = doctorSpecialty || 'Healthcare';
    const slotInfo = confirmedTimeSlot ? `\n\nScheduled Slot:\n${confirmedTimeSlot}` : '';

    const message = `Hello ${referredPatientName || 'Patient'},\n\nYour referral to ${formattedDoctor} has been accepted.${slotInfo}\n\nDoctor:\n${formattedDoctor}\n\nSpecialty:\n${cleanSpecialty}\n\nClinic:\n${cleanClinic}\n\nYou can now continue with GS HEALTH for further consultation.\n\nThank you,\nGS HEALTH`;

    return await dispatchWhatsApp({
        to: referredPatientMobile,
        message,
        templateName: 'REFERRAL_ACCEPTED_PATIENT'
    });
};

/**
 * 3. Send Referral Rejected WhatsApp Notification to REFERRED PATIENT
 */
const sendReferralRejectedWhatsApp = async ({
    referredPatientName,
    referredPatientMobile,
    doctorName,
    rejectionReason
}) => {
    const formattedDoctor = doctorName.startsWith('Dr.') ? doctorName : `Dr. ${doctorName}`;
    const reasonText = rejectionReason && rejectionReason.trim().length > 0 ? `\n\nNote: ${rejectionReason.trim()}` : '';

    const message = `Hello ${referredPatientName || 'Patient'},\n\nYour referral to ${formattedDoctor} could not be accepted at this time.${reasonText}\n\nPlease contact GS HEALTH or select another available doctor if required.\n\nThank you,\nGS HEALTH`;

    return await dispatchWhatsApp({
        to: referredPatientMobile,
        message,
        templateName: 'REFERRAL_REJECTED_PATIENT'
    });
};

const sendDoctorBookingAlert = async ({
    doctorPhone,
    doctorName,
    patientName,
    appointmentDate,
    appointmentTime,
    appointmentType,
    bookingId
}) => {
    const message = `GS HEALTH: New appointment booking (${appointmentType || 'Consultation'}) for ${doctorName || 'Doctor'}. Patient: ${patientName || 'Patient'}, Date: ${appointmentDate}, Time: ${appointmentTime}.`;
    return await dispatchWhatsApp({
        to: doctorPhone,
        message,
        templateName: 'DOCTOR_NEW_BOOKING',
        dedupKey: bookingId || `${appointmentDate}|${appointmentTime}`
    });
};

const sendClinicBookingAlert = async ({
    clinicPhone,
    clinicName,
    doctorName,
    patientName,
    appointmentDate,
    appointmentTime,
    bookingId
}) => {
    const message = `GS HEALTH (${clinicName || 'Clinic'}): New appointment booking with ${doctorName || 'Doctor'}. Patient: ${patientName || 'Patient'}, Date: ${appointmentDate}, Time: ${appointmentTime}.`;
    return await dispatchWhatsApp({
        to: clinicPhone,
        message,
        templateName: 'CLINIC_NEW_BOOKING',
        dedupKey: bookingId || `${appointmentDate}|${appointmentTime}`
    });
};

const sendDoctorReferralAlert = async ({
    doctorPhone,
    doctorName,
    patientName,
    specialty,
    referralDate,
    referralId
}) => {
    const message = `GS HEALTH: New ${specialty || 'Specialist'} referral for ${doctorName || 'Doctor'}. Patient: ${patientName || 'Patient'}, Date: ${referralDate}. Open GS HEALTH Doctor Dashboard to review.`;
    return await dispatchWhatsApp({
        to: doctorPhone,
        message,
        templateName: 'DOCTOR_NEW_REFERRAL',
        dedupKey: referralId
    });
};

const sendClinicReferralAlert = async ({
    clinicPhone,
    clinicName,
    doctorName,
    specialty,
    patientName,
    referralDate,
    referralId
}) => {
    const message = `GS HEALTH (${clinicName || 'Clinic'}): New patient referral to ${doctorName || 'Doctor'} (${specialty || 'Specialist'}). Patient: ${patientName || 'Patient'}, Date: ${referralDate}.`;
    return await dispatchWhatsApp({
        to: clinicPhone,
        message,
        templateName: 'CLINIC_NEW_REFERRAL',
        dedupKey: referralId
    });
};

module.exports = {
    isWhatsAppProviderConfigured,
    dispatchWhatsApp,
    sendNewReferralWhatsApp,
    sendReferralAcceptedWhatsApp,
    sendReferralRejectedWhatsApp,
    sendDoctorBookingAlert,
    sendClinicBookingAlert,
    sendDoctorReferralAlert,
    sendClinicReferralAlert
};
