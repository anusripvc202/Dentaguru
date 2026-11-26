const {
    Appointment,
    Referral,
    User,
    Dentist,
    Clinic,
    District,
    SubAdminPermission,
    SubAdminDistrict,
} = require('../models/Schemas');
const { isCloudEnv } = require('../config/secrets');
const {
    getBookingRulesConfig,
    getNowPartsInTimezone,
    normalizeDateToTimezoneYmd,
    parseClockSlotMinutes,
    normalizeConsultationType,
} = require('../config/bookingRulesConfig');

const MAIN_ADMIN_ROLES = new Set([
    'admin',
    'primaryadmin',
    'primary_admin',
    'superadmin',
    'super_admin',
]);

const SUB_ADMIN_ROLES = new Set([
    'sub-admin',
    'subadmin',
    'sub_admin',
]);

const formatDoctorDisplayName = (rawName) => {
    const trimmed = String(rawName || '').trim();
    if (!trimmed) return 'Unassigned';
    const lower = trimmed.toLowerCase();
    if (lower.startsWith('dr.') || lower.startsWith('dr ') || lower.startsWith('any ')) {
        return trimmed;
    }
    return `Dr. ${trimmed}`;
};

const classifyAppointment = (appt) => {
    const rawStatus = String(appt?.status || 'PENDING').trim().toUpperCase();
    const isCompleted = rawStatus === 'COMPLETED';
    const isRejected = rawStatus === 'REJECTED' || rawStatus === 'DECLINED';
    const isCancelledOnly = rawStatus === 'CANCELLED' || rawStatus === 'CANCELED';
    const isCancelled = isCancelledOnly || isRejected;
    const isNoShow = rawStatus === 'NO_SHOW' || rawStatus === 'NOSHOW' || rawStatus === 'NO-SHOW';
    const isInProgress = rawStatus === 'IN_PROGRESS' || rawStatus === 'IN PROGRESS' || rawStatus === 'STARTED';
    const isPending = !isCompleted && !isCancelled && !isNoShow;

    // A patient counts as "checked" when consultation is completed or actively started
    const isPatientChecked = !isCancelled && !isNoShow && (
        isCompleted ||
        isInProgress ||
        Boolean(appt?.actual_start_at) ||
        Boolean(appt?.actual_end_at)
    );

    let statusCategory = 'Pending';
    if (isCompleted) statusCategory = 'Completed';
    else if (isCancelled) statusCategory = 'Cancelled';
    else if (isNoShow) statusCategory = 'No Show';

    const consultationType = normalizeConsultationType(
        appt?.consultationMode || appt?.consultation_type || appt?.treatment || 'In-Person'
    );

    return {
        rawStatus,
        statusCategory,
        isCompleted,
        isPending,
        isCancelled,
        isNoShow,
        isInProgress,
        isPatientChecked,
        consultationType,
    };
};

const normalizeReferralStatus = (rawStatus) => {
    const lower = String(rawStatus || 'Pending').trim().toLowerCase();
    if (lower === 'accepted' || lower === 'approved' || lower === 'confirmed') return 'Accepted';
    if (lower === 'completed' || lower === 'done') return 'Completed';
    if (lower === 'rejected' || lower === 'declined' || lower === 'cancelled' || lower === 'canceled') return 'Rejected';
    if (lower === 'contacted') return 'Contacted';
    return 'Pending';
};

const getUniquePatientKey = (appt) => {
    const pid = String(appt?.patient_id || appt?.patient?.id || '').trim();
    if (pid) return `id:${pid}`;
    const rawPhone = String(appt?.patient_phone || appt?.patient?.phone || '').replace(/\D/g, '');
    const p10 = rawPhone.length >= 10 ? rawPhone.slice(-10) : rawPhone;
    if (p10.length >= 10) return `ph:${p10}`;
    return `appt:${appt?.id || Math.random()}`;
};

const deduplicateById = (rows = [], fallbackKeyFn = null) => {
    const seen = new Set();
    const result = [];
    for (const row of (rows || [])) {
        if (!row) continue;
        const idKey = row.id ? `id:${String(row.id).trim()}` : (fallbackKeyFn ? fallbackKeyFn(row) : '');
        if (idKey) {
            if (seen.has(idKey)) continue;
            seen.add(idKey);
        }
        result.push(row);
    }
    return result;
};

async function resolveAdminCalendarCaller(req) {
    if (req.user && req.user.id) {
        return {
            id: String(req.user.id).trim(),
            role: String(req.user.role || '').trim(),
            permissions: Array.isArray(req.user.permissions) ? req.user.permissions : [],
            fromJwt: true,
        };
    }
    const headerUserId = (req.headers && req.headers['x-user-id'])
        ? String(req.headers['x-user-id']).trim()
        : '';
    if (!headerUserId) return null;

    const u = await User.findById(headerUserId).catch(() => null);
    if (u && u.id) {
        let perms = u.permissions || [];
        const rLower = String(u.role || '').trim().toLowerCase();
        if ((!perms || perms.length === 0) && SUB_ADMIN_ROLES.has(rLower)) {
            perms = await SubAdminPermission.getPermissionsForUser(u.id).catch(() => []);
        }
        return {
            id: String(u.id).trim(),
            role: String(u.role || '').trim(),
            permissions: perms,
            fromJwt: false,
        };
    }
    return null;
}

/**
 * Pure aggregation engine for the Admin Doctor Activity Calendar.
 * Separates date normalization, deduplication, doctor-wise stats, referral tracking,
 * filtering, and pagination so it can be unit-tested deterministically.
 */
function buildDoctorActivityCalendarPayload({
    rawAppointments = [],
    rawReferrals = [],
    rawUsers = [],
    rawDoctors = [],
    rawClinics = [],
    selectedDate,
    selectedMonth,
    todayYmd,
    timezone = 'Asia/Kolkata',
    filterDoctor = '',
    filterAppointmentStatus = '',
    filterReferralStatus = '',
    searchQuery = '',
    page = 1,
    pageSize = 25,
    canViewPatientContact = true,
    isSubAdminScoped = false,
    assignedDistricts = [],
} = {}) {
    const safePage = Math.max(1, parseInt(page, 10) || 1);
    const safePageSize = Math.min(100, Math.max(1, parseInt(pageSize, 10) || 25));

    const usersById = new Map();
    const usersByPhone = new Map();
    for (const u of (rawUsers || [])) {
        if (!u) continue;
        if (u.id) usersById.set(String(u.id).trim(), u);
        const digits = String(u.phone || '').replace(/\D/g, '');
        const p10 = digits.length >= 10 ? digits.slice(-10) : digits;
        if (p10.length === 10) usersByPhone.set(p10, u);
    }

    const clinicsById = new Map();
    for (const c of (rawClinics || [])) {
        if (c?.id) clinicsById.set(String(c.id).trim(), c);
    }

    // Build canonical doctor lookup keyed by both dentists.id and dentists.user_id
    const canonicalDoctors = deduplicateById(rawDoctors, (d) =>
        d.user_id ? `uid:${String(d.user_id).trim()}` : ''
    );
    const doctorsById = new Map();
    for (const d of canonicalDoctors) {
        const dId = String(d.id || '').trim();
        const uId = String(d.user_id || '').trim();
        const linkedUser = (uId && usersById.get(uId)) || d.users || null;
        const cId = String(d.clinic_id || d.clinics?.id || '').trim();
        const cObj = (cId && clinicsById.get(cId)) || d.clinics || null;
        const entry = {
            doctorId: dId || uId,
            userId: uId || null,
            doctorName: formatDoctorDisplayName(linkedUser?.name || d.name || 'Doctor'),
            specialty: d.speciality || d.specialty || 'General Medicine',
            clinicId: cId || null,
            clinicName: cObj?.clinic_name || d.clinic_name || '',
        };
        if (dId) doctorsById.set(dId, entry);
        if (uId) doctorsById.set(uId, entry);
    }

    const resolveDoctorInfo = (rawDocId, fallbackName = '', fallbackSpec = '', fallbackClinic = '') => {
        const cleanId = String(rawDocId || '').trim();
        if (cleanId && doctorsById.has(cleanId)) {
            return doctorsById.get(cleanId);
        }
        const linkedUser = cleanId ? usersById.get(cleanId) : null;
        if (linkedUser) {
            const roleLower = String(linkedUser.role || '').trim().toLowerCase();
            if (roleLower.includes('doctor') || roleLower.includes('dentist')) {
                return {
                    doctorId: cleanId,
                    userId: cleanId,
                    doctorName: formatDoctorDisplayName(linkedUser.name || fallbackName || 'Doctor'),
                    specialty: fallbackSpec || 'General Medicine',
                    clinicId: null,
                    clinicName: fallbackClinic || '',
                };
            }
        }
        if (cleanId || fallbackName) {
            return {
                doctorId: cleanId || `doc:${String(fallbackName).trim().toLowerCase()}`,
                userId: null,
                doctorName: formatDoctorDisplayName(fallbackName || 'Doctor'),
                specialty: fallbackSpec || 'General Medicine',
                clinicId: null,
                clinicName: fallbackClinic || '',
            };
        }
        return null;
    };

    // Deduplicate appointments and normalize dates in clinic timezone
    const uniqueAppts = deduplicateById(rawAppointments, (a) => {
        const ymd = normalizeDateToTimezoneYmd(a.date, timezone) || '';
        return `comp:${a.patient_id || ''}|${a.dentist_id || ''}|${ymd}|${a.time_slot || ''}`;
    });

    // Deduplicate referrals and normalize entries
    const uniqueRefs = deduplicateById(rawReferrals);

    const normalizedReferrals = uniqueRefs.map((ref) => {
        const refDateYmd = normalizeDateToTimezoneYmd(ref.referral_date || ref.created_at, timezone);
        const refStatus = normalizeReferralStatus(ref.status);
        const referrerId = String(ref.referrer_patient_id || ref.referrer_id || '').trim();
        const referredPatientId = String(ref.referred_patient_id || ref.referred_user_id || '').trim();
        const rawPatientMobile = String(ref.referred_patient_mobile || '').trim();
        const mobile10 = rawPatientMobile.replace(/\D/g, '').slice(-10);

        const referrerUser = (referrerId && usersById.get(referrerId)) || null;
        const referrerDoc = referrerId ? (doctorsById.get(referrerId) || null) : null;
        const referrerRoleLower = String(referrerUser?.role || (referrerDoc ? 'DOCTOR' : 'Patient')).trim().toLowerCase();
        const isReferredByDoctor = Boolean(referrerDoc) || referrerRoleLower.includes('doctor') || referrerRoleLower.includes('dentist');

        const referringDoctorId = isReferredByDoctor ? (referrerDoc?.doctorId || referrerId) : null;
        const referringDoctorUserId = isReferredByDoctor ? (referrerDoc?.userId || referrerId) : null;
        const referringDoctorName = isReferredByDoctor
            ? (referrerDoc?.doctorName || formatDoctorDisplayName(referrerUser?.name || ref.referrer_patient_name || 'Doctor'))
            : (referrerUser?.name || ref.referrer_patient_name || 'Patient Referrer');

        const rawTargetDocId = String(ref.doctor_id || ref.assigned_doctor_id || '').trim();
        const targetDoc = resolveDoctorInfo(
            rawTargetDocId,
            ref.doctor_name || ref.doctorName || '',
            ref.required_specialist || '',
            ref.doctor_clinic_name || ''
        );

        const referredUser = (referredPatientId && usersById.get(referredPatientId))
            || (mobile10.length === 10 && usersByPhone.get(mobile10))
            || null;

        return {
            referralId: String(ref.id || ''),
            id: String(ref.id || ''),
            referringDoctorId,
            referringDoctorUserId,
            referringDoctorName,
            referringRole: isReferredByDoctor ? 'Doctor' : 'Patient',
            isReferredByDoctor,
            referredDoctorId: targetDoc?.doctorId || null,
            referredDoctorUserId: targetDoc?.userId || null,
            referredDoctorName: targetDoc?.doctorName || 'Unassigned',
            patientId: referredPatientId || (referredUser?.id ? String(referredUser.id) : null),
            patientName: String(ref.referred_patient_name || referredUser?.name || 'Referred Patient').trim(),
            patientMobile: canViewPatientContact ? (rawPatientMobile || referredUser?.phone || '') : '',
            referralDate: refDateYmd,
            referralTimestamp: ref.referral_date || ref.created_at || null,
            referralStatus: refStatus,
            rawStatus: String(ref.status || 'Pending'),
            specialty: String(ref.required_specialist || targetDoc?.specialty || 'General Medicine').trim(),
            clinicalComplaint: String(ref.clinical_complaint || '').trim(),
        };
    });

    // Map referrals to patients for enriching appointment rows with referral info
    const referralByPatientId = new Map();
    const referralByPatientPhone = new Map();
    for (const r of normalizedReferrals) {
        if (r.patientId && !referralByPatientId.has(r.patientId)) {
            referralByPatientId.set(r.patientId, r);
        }
        const ph10 = String(r.patientMobile || '').replace(/\D/g, '').slice(-10);
        if (ph10.length === 10 && !referralByPatientPhone.has(ph10)) {
            referralByPatientPhone.set(ph10, r);
        }
    }

    const normalizedAppointments = uniqueAppts.map((a) => {
        const cls = classifyAppointment(a);
        const ymd = normalizeDateToTimezoneYmd(a.date, timezone);
        const pId = String(a.patient_id || a.patient?.id || '').trim();
        const pUser = (pId && usersById.get(pId)) || a.patient || null;
        const rawPhone = String(a.patient_phone || a.patient?.phone || pUser?.phone || '').trim();
        const ph10 = rawPhone.replace(/\D/g, '').slice(-10);

        const rawDocId = String(a.dentist_id || a.selectedDoctor?.id || '').trim();
        const docInfo = resolveDoctorInfo(
            rawDocId,
            a.dentist_name || a.selectedDoctor?.name || a.dentists?.users?.name || '',
            a.doctor_specialty || a.selectedDoctor?.specialty || a.dentists?.speciality || '',
            a.clinic_name || a.clinic?.clinic_name || a.clinics?.clinic_name || ''
        );

        const matchedRef = (pId && referralByPatientId.get(pId))
            || (ph10.length === 10 && referralByPatientPhone.get(ph10))
            || null;

        return {
            appointmentId: String(a.id || ''),
            id: String(a.id || ''),
            patientId: pId || null,
            patientName: String(a.patient_name || pUser?.name || 'Patient').trim(),
            patientPhone: canViewPatientContact ? rawPhone : '',
            patientEmail: canViewPatientContact ? String(a.patient_email || pUser?.email || '') : '',
            doctorId: docInfo?.doctorId || rawDocId || null,
            doctorUserId: docInfo?.userId || null,
            doctorName: docInfo?.doctorName || formatDoctorDisplayName(a.dentist_name || 'Doctor'),
            specialty: docInfo?.specialty || a.doctor_specialty || 'General Medicine',
            clinicId: String(a.clinic_id || a.clinic?.id || docInfo?.clinicId || '').trim() || null,
            clinicName: String(a.clinic_name || a.clinic?.clinic_name || docInfo?.clinicName || '').trim(),
            appointmentDate: ymd,
            appointmentTime: String(a.time_slot || '').trim(),
            scheduledEndTime: a.scheduled_end_time || null,
            consultationType: cls.consultationType,
            treatment: String(a.treatment || 'Medical Consultation').trim(),
            status: cls.rawStatus,
            statusCategory: cls.statusCategory,
            isCompleted: cls.isCompleted,
            isPending: cls.isPending,
            isCancelled: cls.isCancelled,
            isNoShow: cls.isNoShow,
            isPatientChecked: cls.isPatientChecked,
            uniquePatientKey: getUniquePatientKey(a),
            referralInfo: matchedRef ? {
                referralId: matchedRef.referralId,
                referringDoctorName: matchedRef.referringDoctorName,
                referringRole: matchedRef.referringRole,
                referralDate: matchedRef.referralDate,
                referralStatus: matchedRef.referralStatus,
            } : null,
        };
    });

    // Filter helpers
    const cleanDoctorFilter = String(filterDoctor || '').trim();
    const hasDoctorFilter = Boolean(cleanDoctorFilter && cleanDoctorFilter.toLowerCase() !== 'all');
    const doctorFilterLower = cleanDoctorFilter.toLowerCase();

    const cleanApptStatusFilter = String(filterAppointmentStatus || '').trim().toLowerCase();
    const hasApptStatusFilter = Boolean(cleanApptStatusFilter && cleanApptStatusFilter !== 'all');

    const cleanRefStatusFilter = String(filterReferralStatus || '').trim().toLowerCase();
    const hasRefStatusFilter = Boolean(cleanRefStatusFilter && cleanRefStatusFilter !== 'all');

    const cleanSearch = String(searchQuery || '').trim().toLowerCase();
    const hasSearch = cleanSearch.length > 0;

    const matchesDoctorTarget = (docId, docUserId, docName) => {
        if (!hasDoctorFilter) return true;
        if (docId && String(docId).trim() === cleanDoctorFilter) return true;
        if (docUserId && String(docUserId).trim() === cleanDoctorFilter) return true;
        if (docName && String(docName).toLowerCase().includes(doctorFilterLower)) return true;
        return false;
    };

    const matchesAppointmentFilters = (item) => {
        if (!matchesDoctorTarget(item.doctorId, item.doctorUserId, item.doctorName)) return false;
        if (hasApptStatusFilter) {
            const catLower = item.statusCategory.toLowerCase();
            const rawLower = item.status.toLowerCase();
            if (cleanApptStatusFilter === 'pending' && !item.isPending) return false;
            else if (cleanApptStatusFilter === 'completed' && !item.isCompleted) return false;
            else if (cleanApptStatusFilter === 'cancelled' && !item.isCancelled) return false;
            else if (
                cleanApptStatusFilter !== 'pending' &&
                cleanApptStatusFilter !== 'completed' &&
                cleanApptStatusFilter !== 'cancelled' &&
                catLower !== cleanApptStatusFilter &&
                rawLower !== cleanApptStatusFilter
            ) {
                return false;
            }
        }
        if (hasSearch) {
            const hay = [
                item.doctorName,
                item.doctorId,
                item.patientName,
                item.patientId,
                item.clinicName,
                item.specialty,
                item.appointmentId,
            ].join(' ').toLowerCase();
            if (!hay.includes(cleanSearch)) return false;
        }
        return true;
    };

    const matchesReferralFilters = (refItem) => {
        if (hasDoctorFilter) {
            const matchesReferred = matchesDoctorTarget(
                refItem.referredDoctorId,
                refItem.referredDoctorUserId,
                refItem.referredDoctorName
            );
            const matchesReferring = refItem.isReferredByDoctor && matchesDoctorTarget(
                refItem.referringDoctorId,
                refItem.referringDoctorUserId,
                refItem.referringDoctorName
            );
            if (!matchesReferred && !matchesReferring) return false;
        }
        if (hasRefStatusFilter) {
            if (refItem.referralStatus.toLowerCase() !== cleanRefStatusFilter) return false;
        }
        if (hasSearch) {
            const hay = [
                refItem.referralId,
                refItem.referringDoctorName,
                refItem.referredDoctorName,
                refItem.patientName,
                refItem.patientId,
                refItem.specialty,
            ].join(' ').toLowerCase();
            if (!hay.includes(cleanSearch)) return false;
        }
        return true;
    };

    const filteredAppointments = normalizedAppointments.filter(matchesAppointmentFilters);
    const filteredReferrals = normalizedReferrals.filter(matchesReferralFilters);

    // 1. Monthly Calendar Aggregation (`selectedMonth`)
    const monthlyCalendar = {};
    const ensureMonthBucket = (ymd) => {
        if (!monthlyCalendar[ymd]) {
            monthlyCalendar[ymd] = {
                date: ymd,
                totalAppointments: 0,
                completedAppointments: 0,
                pendingAppointments: 0,
                cancelledAppointments: 0,
                totalReferrals: 0,
                _activeDoctorIds: new Set(),
                activeDoctorsCount: 0,
                hasAppointments: false,
                hasCompleted: false,
                hasPending: false,
                hasCancelled: false,
                hasReferrals: false,
            };
        }
        return monthlyCalendar[ymd];
    };

    for (const appt of filteredAppointments) {
        const ymd = appt.appointmentDate;
        if (!ymd || !ymd.startsWith(selectedMonth)) continue;
        const b = ensureMonthBucket(ymd);
        b.totalAppointments += 1;
        b.hasAppointments = true;
        if (appt.doctorId) b._activeDoctorIds.add(appt.doctorId);
        if (appt.isCompleted) {
            b.completedAppointments += 1;
            b.hasCompleted = true;
        } else if (appt.isCancelled) {
            b.cancelledAppointments += 1;
            b.hasCancelled = true;
        } else if (appt.isPending) {
            b.pendingAppointments += 1;
            b.hasPending = true;
        }
    }

    for (const ref of filteredReferrals) {
        const ymd = ref.referralDate;
        if (!ymd || !ymd.startsWith(selectedMonth)) continue;
        const b = ensureMonthBucket(ymd);
        b.totalReferrals += 1;
        b.hasReferrals = true;
        if (ref.referredDoctorId) b._activeDoctorIds.add(ref.referredDoctorId);
        if (ref.referringDoctorId) b._activeDoctorIds.add(ref.referringDoctorId);
    }

    for (const ymd of Object.keys(monthlyCalendar)) {
        monthlyCalendar[ymd].activeDoctorsCount = monthlyCalendar[ymd]._activeDoctorIds.size;
        delete monthlyCalendar[ymd]._activeDoctorIds;
    }

    // 2. Selected Date Records
    const dailyAppointments = filteredAppointments
        .filter((a) => a.appointmentDate === selectedDate)
        .sort((a, b) => {
            const ma = parseClockSlotMinutes(a.appointmentTime || '') ?? 9999;
            const mb = parseClockSlotMinutes(b.appointmentTime || '') ?? 9999;
            if (ma !== mb) return ma - mb;
            return a.doctorName.localeCompare(b.doctorName);
        });

    const dailyReferrals = filteredReferrals
        .filter((r) => r.referralDate === selectedDate)
        .sort((a, b) => String(b.referralTimestamp || '').localeCompare(String(a.referralTimestamp || '')));

    // 3. Daily Summary & Doctor-wise Activity Table
    const doctorActivityMap = new Map();
    const ensureDoctorRow = (docId, docUserId, docName, specialty = 'General Medicine', clinicName = '') => {
        const key = String(docId || '').trim();
        if (!key) return null;
        if (!doctorActivityMap.has(key)) {
            const known = doctorsById.get(key) || (docUserId ? doctorsById.get(String(docUserId).trim()) : null);
            doctorActivityMap.set(key, {
                doctorId: known?.doctorId || key,
                userId: known?.userId || docUserId || null,
                doctorName: known?.doctorName || formatDoctorDisplayName(docName || 'Doctor'),
                specialty: known?.specialty || specialty || 'General Medicine',
                clinicName: known?.clinicName || clinicName || '',
                totalAppointments: 0,
                patientsChecked: 0,
                _checkedPatientsSet: new Set(),
                referralsReceived: 0,
                referralsGiven: 0,
                pendingAppointments: 0,
                completedAppointments: 0,
                cancelledAppointments: 0,
            });
        }
        return doctorActivityMap.get(key);
    };

    const dailyCheckedPatientsSet = new Set();
    let pendingAppointmentsCount = 0;
    let completedAppointmentsCount = 0;
    let cancelledAppointmentsCount = 0;

    for (const appt of dailyAppointments) {
        if (appt.isPatientChecked) {
            dailyCheckedPatientsSet.add(appt.uniquePatientKey);
        }
        if (appt.isCompleted) completedAppointmentsCount += 1;
        else if (appt.isCancelled) cancelledAppointmentsCount += 1;
        else if (appt.isPending) pendingAppointmentsCount += 1;

        const row = ensureDoctorRow(appt.doctorId, appt.doctorUserId, appt.doctorName, appt.specialty, appt.clinicName);
        if (row) {
            row.totalAppointments += 1;
            if (appt.isPatientChecked) row._checkedPatientsSet.add(appt.uniquePatientKey);
            if (appt.isCompleted) row.completedAppointments += 1;
            else if (appt.isCancelled) row.cancelledAppointments += 1;
            else if (appt.isPending) row.pendingAppointments += 1;
        }
    }

    for (const ref of dailyReferrals) {
        if (ref.referredDoctorId) {
            const receivedRow = ensureDoctorRow(
                ref.referredDoctorId,
                ref.referredDoctorUserId,
                ref.referredDoctorName,
                ref.specialty
            );
            if (receivedRow) receivedRow.referralsReceived += 1;
        }
        if (ref.isReferredByDoctor && ref.referringDoctorId) {
            const givenRow = ensureDoctorRow(
                ref.referringDoctorId,
                ref.referringDoctorUserId,
                ref.referringDoctorName,
                ref.specialty
            );
            if (givenRow) givenRow.referralsGiven += 1;
        }
    }

    const doctorActivity = Array.from(doctorActivityMap.values())
        .map((row) => {
            const patientsChecked = row._checkedPatientsSet.size;
            const cleanRow = { ...row, patientsChecked };
            delete cleanRow._checkedPatientsSet;
            return cleanRow;
        })
        .sort((a, b) => {
            const scoreA = a.totalAppointments + a.referralsReceived + a.referralsGiven;
            const scoreB = b.totalAppointments + b.referralsReceived + b.referralsGiven;
            if (scoreB !== scoreA) return scoreB - scoreA;
            return a.doctorName.localeCompare(b.doctorName);
        });

    const dailySummary = {
        date: selectedDate,
        totalDoctorsActive: doctorActivity.length,
        totalAppointments: dailyAppointments.length,
        totalPatientsChecked: dailyCheckedPatientsSet.size,
        totalReferrals: dailyReferrals.length,
        pendingAppointments: pendingAppointmentsCount,
        completedAppointments: completedAppointmentsCount,
        cancelledAppointments: cancelledAppointmentsCount,
    };

    // 4. Pagination for Daily Appointments & Referrals
    const apptTotal = dailyAppointments.length;
    const apptTotalPages = Math.max(1, Math.ceil(apptTotal / safePageSize));
    const apptClampedPage = Math.min(safePage, apptTotalPages);
    const apptStart = (apptClampedPage - 1) * safePageSize;
    const paginatedAppointments = dailyAppointments
        .slice(apptStart, apptStart + safePageSize)
        .map(({ uniquePatientKey, ...rest }) => rest);

    const refTotal = dailyReferrals.length;
    const refTotalPages = Math.max(1, Math.ceil(refTotal / safePageSize));
    const refClampedPage = Math.min(safePage, refTotalPages);
    const refStart = (refClampedPage - 1) * safePageSize;
    const paginatedReferrals = dailyReferrals.slice(refStart, refStart + safePageSize);

    // 5. Available doctors for dropdown filter
    const availableDoctorsMap = new Map();
    for (const d of canonicalDoctors) {
        const dId = String(d.id || d.user_id || '').trim();
        if (!dId || availableDoctorsMap.has(dId)) continue;
        const entry = doctorsById.get(dId);
        if (entry) {
            availableDoctorsMap.set(dId, {
                doctorId: entry.doctorId,
                userId: entry.userId,
                doctorName: entry.doctorName,
                specialty: entry.specialty,
            });
        }
    }
    const availableDoctors = Array.from(availableDoctorsMap.values())
        .sort((a, b) => a.doctorName.localeCompare(b.doctorName));

    return {
        success: true,
        timezone,
        today: todayYmd || selectedDate,
        month: selectedMonth,
        selectedDate,
        isSubAdminScoped,
        assignedDistricts: isSubAdminScoped ? assignedDistricts : [],
        monthlyCalendar,
        dailySummary,
        doctorActivity,
        appointments: paginatedAppointments,
        appointmentsPagination: {
            page: apptClampedPage,
            pageSize: safePageSize,
            totalItems: apptTotal,
            totalPages: apptTotalPages,
        },
        referrals: paginatedReferrals,
        referralsPagination: {
            page: refClampedPage,
            pageSize: safePageSize,
            totalItems: refTotal,
            totalPages: refTotalPages,
        },
        availableDoctors,
    };
}

/**
 * GET /api/v1/admin/doctor-activity-calendar
 */
exports.getDoctorActivityCalendar = async (req, res) => {
    try {
        const rules = getBookingRulesConfig();
        const tz = rules.timezone || 'Asia/Kolkata';
        const nowParts = getNowPartsInTimezone(rules.debugNowOverride || new Date(), tz);

        const caller = await resolveAdminCalendarCaller(req);
        if (!caller && isCloudEnv()) {
            return res.status(401).json({
                success: false,
                message: 'Authentication required to access the Doctor Activity Calendar.',
            });
        }

        const callerRoleLower = String(caller?.role || '').trim().toLowerCase();
        const isMainAdmin = !caller || MAIN_ADMIN_ROLES.has(callerRoleLower);
        const isSubAdmin = SUB_ADMIN_ROLES.has(callerRoleLower);

        if (caller && !isMainAdmin && !isSubAdmin) {
            return res.status(403).json({
                success: false,
                message: 'Access Denied: Only Administrators and authorized Sub-Administrators can access the Doctor Activity Calendar.',
            });
        }

        let assignedDistricts = [];
        let canViewPatientContact = true;
        if (isSubAdmin && caller?.id) {
            const permsUpper = (caller.permissions || []).map((p) => String(p || '').toUpperCase());
            const hasCalendarPerm = permsUpper.includes('*') ||
                permsUpper.includes('ALL') ||
                permsUpper.includes('APPOINTMENT_VIEW') ||
                permsUpper.includes('REPORT_VIEW') ||
                permsUpper.includes('CLINIC_VIEW') ||
                permsUpper.includes('DENTIST_VIEW');
            if (!hasCalendarPerm) {
                return res.status(403).json({
                    success: false,
                    message: "Access Denied: Your Sub-Admin account lacks 'APPOINTMENT_VIEW' or 'REPORT_VIEW' permission.",
                });
            }
            canViewPatientContact = permsUpper.includes('*') || permsUpper.includes('ALL') || permsUpper.includes('PATIENT_VIEW');
            assignedDistricts = await SubAdminDistrict.getDistrictsForSubAdmin(caller.id).catch(() => []);
        }

        const authDistrictIds = new Set((assignedDistricts || []).map((d) => String(d.id || '').trim()).filter(Boolean));
        const authDistrictNames = new Set((assignedDistricts || []).map((d) => String(d.name || '').trim().toLowerCase()).filter(Boolean));

        const isLocationPermitted = ({ districtId, districtName, city, state, pincode, location }) => {
            if (!isSubAdmin) return true;
            if (authDistrictIds.size === 0 && authDistrictNames.size === 0) return false;
            if (districtId && authDistrictIds.has(String(districtId).trim())) return true;
            if (districtName && authDistrictNames.has(String(districtName).trim().toLowerCase())) return true;
            if (city && authDistrictNames.has(String(city).trim().toLowerCase())) return true;

            const resolved = District.resolveDistrictFromLocation({
                city: city || location || '',
                district: districtName || '',
                state: state || '',
                pincode: pincode || '',
            });
            if (resolved?.districtId && authDistrictIds.has(String(resolved.districtId).trim())) return true;
            if (resolved?.districtName && authDistrictNames.has(String(resolved.districtName).trim().toLowerCase())) return true;
            if (location) {
                const locLower = String(location).toLowerCase();
                for (const dName of authDistrictNames) {
                    if (dName && locLower.includes(dName)) return true;
                }
            }
            return false;
        };

        const selectedDate = normalizeDateToTimezoneYmd(req.query.date, tz) || nowParts.ymd;
        const selectedMonth = (req.query.month && /^\d{4}-\d{2}$/.test(String(req.query.month).trim()))
            ? String(req.query.month).trim()
            : selectedDate.slice(0, 7);

        const [rawAppts, rawReferrals, rawUsers, rawDoctors, rawClinics] = await Promise.all([
            Appointment.find({}).catch(() => []),
            Referral.find({}).catch(() => []),
            User.find({}).catch(() => []),
            Dentist.find({}).catch(() => []),
            Clinic.find({}).catch(() => []),
        ]);

        const permittedClinics = (rawClinics || []).filter((c) =>
            isLocationPermitted({
                districtId: c.district_id,
                districtName: c.district,
                city: c.city,
                state: c.state,
                pincode: c.pincode,
                location: c.location,
            })
        );
        const permittedClinicIds = new Set(permittedClinics.map((c) => String(c.id).trim()));

        const permittedDoctors = (rawDoctors || []).filter((d) => {
            if (!isSubAdmin) return true;
            if (d.clinic_id && permittedClinicIds.has(String(d.clinic_id).trim())) return true;
            return isLocationPermitted({
                districtId: d.district_id || d.users?.district_id,
                districtName: d.district || d.users?.district,
                city: d.city || d.users?.city,
                state: d.state || d.users?.state,
                pincode: d.pincode || d.users?.pincode,
                location: d.clinic_address || d.location,
            });
        });

        const permittedDoctorIds = new Set();
        for (const d of permittedDoctors) {
            if (d?.id) permittedDoctorIds.add(String(d.id).trim());
            if (d?.user_id) permittedDoctorIds.add(String(d.user_id).trim());
        }

        const permittedAppointments = (rawAppts || []).filter((a) => {
            if (!isSubAdmin) return true;
            const dId = String(a.dentist_id || a.selectedDoctor?.id || '').trim();
            const cId = String(a.clinic_id || a.clinic?.id || '').trim();
            if (cId && permittedClinicIds.has(cId)) return true;
            if (dId && permittedDoctorIds.has(dId)) return true;
            return isLocationPermitted({
                city: a.patient_city || a.patient?.city,
                pincode: a.patient_pincode || a.patient?.pincode,
                location: a.clinic?.location || a.clinic_name,
            });
        });

        const permittedReferrals = (rawReferrals || []).filter((r) => {
            if (!isSubAdmin) return true;
            const rDocId = String(r.doctor_id || r.assigned_doctor_id || '').trim();
            const rRefId = String(r.referrer_patient_id || r.referrer_id || '').trim();
            const rClinicId = String(r.clinic_id || '').trim();
            if (rDocId && permittedDoctorIds.has(rDocId)) return true;
            if (rRefId && permittedDoctorIds.has(rRefId)) return true;
            if (rClinicId && permittedClinicIds.has(rClinicId)) return true;
            return isLocationPermitted({
                city: r.referred_patient_city || r.doctor_city,
                pincode: r.referred_patient_pincode || r.doctor_pincode,
                location: r.referred_patient_location || r.doctor_location,
            });
        });

        const payload = buildDoctorActivityCalendarPayload({
            rawAppointments: permittedAppointments,
            rawReferrals: permittedReferrals,
            rawUsers,
            rawDoctors: permittedDoctors,
            rawClinics: permittedClinics,
            selectedDate,
            selectedMonth,
            todayYmd: nowParts.ymd,
            timezone: tz,
            filterDoctor: req.query.doctorId || req.query.doctor || '',
            filterAppointmentStatus: req.query.appointmentStatus || req.query.status || '',
            filterReferralStatus: req.query.referralStatus || '',
            searchQuery: req.query.search || req.query.q || '',
            page: req.query.page || 1,
            pageSize: req.query.pageSize || req.query.limit || 25,
            canViewPatientContact,
            isSubAdminScoped: isSubAdmin,
            assignedDistricts,
        });

        return res.json(payload);
    } catch (err) {
        console.error('Get Doctor Activity Calendar Error:', err.message);
        return res.status(500).json({
            success: false,
            message: 'Failed to load Doctor Activity Calendar.',
        });
    }
};

exports._buildDoctorActivityCalendarPayload = buildDoctorActivityCalendarPayload;
exports._classifyAppointment = classifyAppointment;
exports._normalizeReferralStatus = normalizeReferralStatus;
