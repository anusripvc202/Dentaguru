const {
    PatientProblemRequest,
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
    getNowPartsInTimezone,
    normalizeDateToTimezoneYmd,
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

const formatDoctorDisplayName = (rawName, fallback = 'Unassigned') => {
    const trimmed = String(rawName || '').trim();
    if (!trimmed || trimmed.toLowerCase() === 'null') return fallback;
    const lower = trimmed.toLowerCase();
    if (lower.startsWith('dr.') || lower.startsWith('dr ') || lower.startsWith('unassigned')) {
        return trimmed;
    }
    return `Dr. ${trimmed}`;
};

/**
 * Classifies a patient consultation/problem request status into one of:
 * - 'Pending'
 * - 'Approved'
 * - 'Rejected'
 */
const classifyRequestStatus = (rawStatus) => {
    const upper = String(rawStatus || 'PENDING_ADMIN_REVIEW')
        .trim()
        .toUpperCase()
        .replace(/[\s-]+/g, '_');

    if (
        upper === 'REJECTED' ||
        upper === 'DECLINED' ||
        upper === 'CANCELLED' ||
        upper === 'CANCELED'
    ) {
        return 'Rejected';
    }

    if (
        upper === 'APPROVED' ||
        upper === 'ACCEPTED' ||
        upper === 'CONFIRMED' ||
        upper === 'DENTIST_ASSIGNED' ||
        upper === 'DOCTOR_ASSIGNED' ||
        upper === 'DENTIST_SUGGESTED' ||
        upper === 'DENTIST_ACCEPTED' ||
        upper === 'DOCTOR_ACCEPTED' ||
        upper === 'ADMIN_REVIEWED' ||
        upper === 'ASSIGNED' ||
        upper === 'DOCTOR_IDENTIFIED' ||
        upper === 'RESOLVED' ||
        upper === 'COMPLETED' ||
        upper === 'CLOSED'
    ) {
        return 'Approved';
    }

    return 'Pending';
};

/**
 * Normalizes a referral status into existing GS Health referral statuses:
 * - 'Pending'
 * - 'Accepted'
 * - 'Completed'
 * - 'Rejected'
 */
const classifyReferralStatus = (rawStatus) => {
    const lower = String(rawStatus || 'Pending').trim().toLowerCase();
    if (lower === 'accepted' || lower === 'approved' || lower === 'confirmed') return 'Accepted';
    if (lower === 'completed' || lower === 'done') return 'Completed';
    if (lower === 'rejected' || lower === 'declined' || lower === 'cancelled' || lower === 'canceled') {
        return 'Rejected';
    }
    return 'Pending';
};

const formatTimeInTimezone = (rawDateValue, timeZone = 'Asia/Kolkata') => {
    if (!rawDateValue) return '';
    const d = new Date(rawDateValue);
    if (Number.isNaN(d.getTime())) return '';
    try {
        return new Intl.DateTimeFormat('en-US', {
            timeZone,
            hour: '2-digit',
            minute: '2-digit',
            hour12: true,
        }).format(d);
    } catch (_) {
        return d.toISOString().slice(11, 16);
    }
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
        };
    }
    if (isCloudEnv()) return null;
    const headerUserId = req.headers && req.headers['x-user-id'] ? String(req.headers['x-user-id']).trim() : '';
    if (!headerUserId) return null;
    const user = await User.findById(headerUserId).catch(() => null);
    if (!user || !user.id) return null;
    return {
        id: String(user.id).trim(),
        role: String(user.role || '').trim(),
    };
}

async function authorizeAdminCalendarAccess(req) {
    const caller = await resolveAdminCalendarCaller(req);
    if (!caller || !caller.id) {
        return {
            ok: false,
            status: 401,
            message: 'Authentication required to access Requests & Referrals Calendar.',
        };
    }

    const dbUser = await User.findById(caller.id).catch(() => null);
    const effectiveRole = String(dbUser?.role || caller.role || '').trim().toLowerCase();
    const effectiveStatus = String(dbUser?.status || 'ACTIVE').trim().toUpperCase();

    if (['INACTIVE', 'DEACTIVATED', 'SUSPENDED', 'BLOCKED'].includes(effectiveStatus)) {
        return {
            ok: false,
            status: 403,
            message: 'Access Denied: Your administrator account has been deactivated.',
        };
    }

    if (MAIN_ADMIN_ROLES.has(effectiveRole)) {
        return { ok: true, isMainAdmin: true, isSubAdmin: false, callerId: caller.id, allowedDistrictNames: null };
    }

    if (SUB_ADMIN_ROLES.has(effectiveRole)) {
        const perms = await SubAdminPermission.getPermissionsForUser(caller.id).catch(() => []);
        const upperPerms = new Set((perms || []).map((p) => String(p || '').toUpperCase()));
        const canView =
            upperPerms.size === 0 ||
            upperPerms.has('ALL') ||
            upperPerms.has('ASSIGNMENT_VIEW') ||
            upperPerms.has('PROBLEM_VIEW') ||
            upperPerms.has('PATIENT_VIEW') ||
            upperPerms.has('REPORT_VIEW') ||
            upperPerms.has('MANAGE_REQUESTS') ||
            upperPerms.has('MANAGE_REFERRALS');

        if (!canView) {
            return {
                ok: false,
                status: 403,
                message: 'Access Denied: Your Sub-Admin account does not have permission to view Requests & Referrals Calendar.',
            };
        }

        const assignedDistricts = await SubAdminDistrict.getDistrictsForSubAdmin(caller.id).catch(() => []);
        const allowedDistrictNames = Array.isArray(assignedDistricts) && assignedDistricts.length > 0
            ? new Set(
                assignedDistricts
                    .filter((d) => !d.status || String(d.status).toUpperCase() === 'ACTIVE')
                    .map((d) => String(d.name || '').trim().toLowerCase())
                    .filter(Boolean)
            )
            : null;

        return {
            ok: true,
            isMainAdmin: false,
            isSubAdmin: true,
            callerId: caller.id,
            allowedDistrictNames,
        };
    }

    return {
        ok: false,
        status: 403,
        message: 'Access Denied: Admin privileges are required to view the Requests & Referrals Calendar.',
    };
}

/**
 * GET /api/v1/admin/requests-referrals-calendar
 *
 * Query params:
 * - date: YYYY-MM-DD (defaults to today in Asia/Kolkata)
 * - month: YYYY-MM (defaults to date.slice(0, 7))
 * - search: optional search across Request ID, Referral ID, Patient Name, or Doctor Name
 * - requestStatus: optional ('All' | 'Pending' | 'Approved' | 'Rejected')
 * - requestType: optional ('All' or specific problem_category / request type)
 * - referralStatus: optional ('All' | 'Pending' | 'Accepted' | 'Completed' | 'Rejected')
 * - page: page number for daily records (default 1)
 * - pageSize: items per page (default 20, max 100)
 */
exports.getRequestsReferralsCalendar = async (req, res) => {
    try {
        const authCheck = await authorizeAdminCalendarAccess(req);
        if (!authCheck.ok) {
            return res.status(authCheck.status).json({
                success: false,
                message: authCheck.message,
            });
        }

        const timeZone = 'Asia/Kolkata';
        const nowParts = getNowPartsInTimezone(new Date(), timeZone);
        const todayYmd = nowParts.dateYmd;

        const rawDateParam = String(req.query.date || '').trim();
        const rawMonthParam = String(req.query.month || '').trim();

        const selectedDate = /^\d{4}-\d{2}-\d{2}$/.test(rawDateParam) ? rawDateParam : todayYmd;
        const selectedMonth = /^\d{4}-\d{2}$/.test(rawMonthParam)
            ? rawMonthParam
            : selectedDate.slice(0, 7);

        const searchQuery = String(req.query.search || '').trim().toLowerCase();
        const requestStatusFilter = String(req.query.requestStatus || 'All').trim();
        const requestTypeFilter = String(req.query.requestType || 'All').trim();
        const referralStatusFilter = String(req.query.referralStatus || 'All').trim();

        const page = Math.max(1, parseInt(req.query.page, 10) || 1);
        const pageSize = Math.min(100, Math.max(1, parseInt(req.query.pageSize, 10) || 20));

        const [rawRequests, rawReferrals, rawDentists, rawUsers, rawClinics] = await Promise.all([
            PatientProblemRequest.find({}).catch(() => []),
            Referral.find({}).catch(() => []),
            Dentist.find({}).catch(() => []),
            User.find({}).catch(() => []),
            Clinic.find({}).catch(() => []),
        ]);

        const usersById = new Map();
        for (const u of (rawUsers || [])) {
            if (u && u.id) usersById.set(String(u.id).trim(), u);
        }

        const clinicsById = new Map();
        for (const c of (rawClinics || [])) {
            if (c && c.id) clinicsById.set(String(c.id).trim(), c);
        }

        const doctorsById = new Map();
        const doctorsByUserId = new Map();
        for (const d of (rawDentists || [])) {
            if (!d) continue;
            const dId = String(d.id || '').trim();
            const uId = String(d.user_id || d.users?.id || '').trim();
            const linkedUser = uId ? usersById.get(uId) : null;
            const rawName = d.name || d.users?.name || linkedUser?.name || '';
            const docEntry = {
                doctorId: dId || uId,
                userId: uId,
                doctorName: formatDoctorDisplayName(rawName, 'Doctor'),
                specialty: String(d.speciality || d.specialty || 'General Medicine').trim(),
                clinicName: String(d.clinic_name || d.clinics?.clinic_name || clinicsById.get(String(d.clinic_id || ''))?.clinic_name || '').trim(),
            };
            if (dId) doctorsById.set(dId, docEntry);
            if (uId) doctorsByUserId.set(uId, docEntry);
        }

        const resolveDoctorInfo = (rawId, rawFallbackName = '') => {
            const cleanId = String(rawId || '').trim();
            if (cleanId) {
                const match = doctorsById.get(cleanId) || doctorsByUserId.get(cleanId);
                if (match) return match;
                const u = usersById.get(cleanId);
                if (u && u.name) {
                    return {
                        doctorId: cleanId,
                        userId: cleanId,
                        doctorName: formatDoctorDisplayName(u.name, 'Doctor'),
                        specialty: String(u.specialty || 'General Medicine').trim(),
                        clinicName: '',
                    };
                }
            }
            if (rawFallbackName && String(rawFallbackName).trim() && String(rawFallbackName).trim().toLowerCase() !== 'null') {
                return {
                    doctorId: cleanId,
                    userId: '',
                    doctorName: formatDoctorDisplayName(rawFallbackName, 'Unassigned'),
                    specialty: '',
                    clinicName: '',
                };
            }
            return null;
        };

        // Deduplicate Requests & Referrals
        const uniqueRequests = deduplicateById(
            rawRequests,
            (r) => `${r.patient_id || r.patient_name || ''}|${r.problem_category || ''}|${r.created_at || r.submitted_at || ''}`
        );
        const uniqueReferrals = deduplicateById(
            rawReferrals,
            (r) => `${r.referrer_patient_id || r.referrer_id || ''}|${r.referred_patient_mobile || ''}|${r.doctor_id || ''}|${r.referral_date || r.created_at || ''}`
        );

        // Build Monthly Calendar Map for selectedMonth
        const [yearStr, monthStr] = selectedMonth.split('-');
        const yearNum = parseInt(yearStr, 10);
        const monthNum = parseInt(monthStr, 10);
        const daysInMonth = new Date(yearNum, monthNum, 0).getDate();

        const monthlyMap = new Map();
        for (let day = 1; day <= daysInMonth; day++) {
            const dStr = `${selectedMonth}-${String(day).padStart(2, '0')}`;
            monthlyMap.set(dStr, {
                date: dStr,
                requestsCount: 0,
                pendingRequestsCount: 0,
                approvedRequestsCount: 0,
                rejectedRequestsCount: 0,
                referralsCount: 0,
                pendingReferralsCount: 0,
                acceptedReferralsCount: 0,
                completedReferralsCount: 0,
                rejectedReferralsCount: 0,
            });
        }

        const distinctRequestTypes = new Set();

        // Daily summary counters for selectedDate
        const dailySummary = {
            totalRequests: 0,
            pendingRequests: 0,
            approvedRequests: 0,
            rejectedRequests: 0,
            totalReferrals: 0,
            pendingReferrals: 0,
            acceptedReferrals: 0,
            completedReferrals: 0,
            rejectedReferrals: 0,
        };

        const dailyRequests = [];
        const dailyReferrals = [];

        // 1. Process Requests using STRICT request creation date (never appointment date)
        for (const reqRow of uniqueRequests) {
            const rawCreatedAt =
                reqRow.created_at ||
                reqRow.submitted_at ||
                reqRow.createdAt ||
                reqRow.submittedAt ||
                '';
            const reqDateYmd = normalizeDateToTimezoneYmd(rawCreatedAt, timeZone);
            if (!reqDateYmd) continue;

            const patientId = String(reqRow.patient_id || reqRow.patientId || reqRow.users?.id || '').trim();
            const patientUser = patientId ? usersById.get(patientId) : null;

            if (authCheck.allowedDistrictNames) {
                const locRes = District.resolveDistrictFromLocation({
                    city: reqRow.city || patientUser?.city,
                    district: reqRow.district || patientUser?.district,
                    state: reqRow.state || patientUser?.state,
                    pincode: reqRow.pincode || patientUser?.pincode,
                });
                const distLower = String(locRes.district || reqRow.city || patientUser?.city || '').trim().toLowerCase();
                if (!distLower || !authCheck.allowedDistrictNames.has(distLower)) {
                    continue;
                }
            }

            const requestId = String(reqRow.id || '').trim();
            const patientName = String(
                reqRow.patient_name ||
                reqRow.patientName ||
                reqRow.users?.name ||
                patientUser?.name ||
                'Patient'
            ).trim();
            const patientPhone = String(
                reqRow.patient_phone ||
                reqRow.patientPhone ||
                reqRow.users?.phone ||
                patientUser?.phone ||
                ''
            ).trim();

            const rawDocId =
                reqRow.suggested_dentist_id ||
                reqRow.suggestedDentistId ||
                reqRow.assigned_doctor_id ||
                reqRow.assignedDoctorId ||
                reqRow.dentists?.id ||
                '';
            const rawDocName =
                reqRow.assigned_doctor_name ||
                reqRow.assignedDoctorName ||
                reqRow.dentists?.name ||
                reqRow.dentists?.users?.name ||
                '';
            const docInfo = resolveDoctorInfo(rawDocId, rawDocName);
            const doctorName = docInfo ? docInfo.doctorName : 'Unassigned';
            const doctorId = docInfo ? docInfo.doctorId : String(rawDocId || '').trim();

            const requestType = String(
                reqRow.problem_category ||
                reqRow.problemCategory ||
                reqRow.request_type ||
                reqRow.requestType ||
                'General Consultation'
            ).trim();
            if (requestType) distinctRequestTypes.add(requestType);

            const statusCategory = classifyRequestStatus(reqRow.status);
            const rawStatusText = String(reqRow.status || 'PENDING_ADMIN_REVIEW').trim();
            const requestTime = formatTimeInTimezone(rawCreatedAt, timeZone);

            // Apply status, type, and search filters
            if (
                requestStatusFilter &&
                requestStatusFilter.toLowerCase() !== 'all' &&
                statusCategory.toLowerCase() !== requestStatusFilter.toLowerCase()
            ) {
                continue;
            }
            if (
                requestTypeFilter &&
                requestTypeFilter.toLowerCase() !== 'all' &&
                requestType.toLowerCase() !== requestTypeFilter.toLowerCase()
            ) {
                continue;
            }
            if (searchQuery) {
                const matchesSearch =
                    requestId.toLowerCase().includes(searchQuery) ||
                    patientName.toLowerCase().includes(searchQuery) ||
                    patientPhone.toLowerCase().includes(searchQuery) ||
                    doctorName.toLowerCase().includes(searchQuery) ||
                    requestType.toLowerCase().includes(searchQuery);
                if (!matchesSearch) continue;
            }

            if (reqDateYmd.startsWith(selectedMonth) && monthlyMap.has(reqDateYmd)) {
                const cell = monthlyMap.get(reqDateYmd);
                cell.requestsCount += 1;
                if (statusCategory === 'Approved') cell.approvedRequestsCount += 1;
                else if (statusCategory === 'Rejected') cell.rejectedRequestsCount += 1;
                else cell.pendingRequestsCount += 1;
            }

            if (reqDateYmd === selectedDate) {
                dailySummary.totalRequests += 1;
                if (statusCategory === 'Approved') dailySummary.approvedRequests += 1;
                else if (statusCategory === 'Rejected') dailySummary.rejectedRequests += 1;
                else dailySummary.pendingRequests += 1;

                dailyRequests.push({
                    requestId,
                    patientId,
                    patientName,
                    patientPhone,
                    doctorId,
                    doctorName,
                    requestType,
                    requestDate: reqDateYmd,
                    requestTime,
                    createdAt: rawCreatedAt,
                    status: statusCategory,
                    rawStatus: rawStatusText,
                    problemDescription: String(reqRow.problem_description || reqRow.problemDescription || '').trim(),
                    symptoms: String(reqRow.symptoms || '').trim(),
                    city: String(reqRow.city || patientUser?.city || '').trim(),
                    state: String(reqRow.state || patientUser?.state || '').trim(),
                    pincode: String(reqRow.pincode || patientUser?.pincode || '').trim(),
                    adminNotes: String(reqRow.admin_notes || reqRow.adminNotes || '').trim(),
                });
            }
        }

        // 2. Process Referrals using STRICT referral creation date (never appointment date)
        for (const refRow of uniqueReferrals) {
            const rawReferralCreatedAt =
                refRow.referral_date ||
                refRow.created_at ||
                refRow.referralDate ||
                refRow.createdAt ||
                '';
            const refDateYmd = normalizeDateToTimezoneYmd(rawReferralCreatedAt, timeZone);
            if (!refDateYmd) continue;

            const referralId = String(refRow.id || '').trim();
            const referredPatientId = String(refRow.referred_patient_id || refRow.referred_user_id || '').trim();
            const referredUser = referredPatientId ? usersById.get(referredPatientId) : null;

            const patientName = String(
                refRow.referred_patient_name ||
                refRow.referredPatientName ||
                referredUser?.name ||
                'Referred Patient'
            ).trim();
            const patientPhone = String(
                refRow.referred_patient_mobile ||
                refRow.referredPatientMobile ||
                referredUser?.phone ||
                ''
            ).trim();

            if (authCheck.allowedDistrictNames) {
                const locRes = District.resolveDistrictFromLocation({
                    city: refRow.referred_patient_city || referredUser?.city,
                    state: refRow.referred_patient_state || referredUser?.state,
                    pincode: refRow.referred_patient_pincode || referredUser?.pincode,
                });
                const distLower = String(locRes.district || refRow.referred_patient_city || '').trim().toLowerCase();
                if (!distLower || !authCheck.allowedDistrictNames.has(distLower)) {
                    continue;
                }
            }

            // Referring Doctor / Referrer
            const referrerId = String(refRow.referrer_patient_id || refRow.referrer_id || '').trim();
            const referrerDocInfo = resolveDoctorInfo(referrerId, refRow.referrer_patient_name || refRow.referrerPatientName || '');
            const referringDoctorName = referrerDocInfo
                ? referrerDocInfo.doctorName
                : (String(refRow.referrer_patient_name || refRow.referrerPatientName || usersById.get(referrerId)?.name || 'Referrer').trim());

            // Referred (Target) Doctor
            const targetDocId = String(refRow.doctor_id || refRow.assigned_doctor_id || '').trim();
            const targetDocInfo = resolveDoctorInfo(targetDocId, refRow.doctor_name || refRow.doctorName || '');
            const referredDoctorName = targetDocInfo
                ? targetDocInfo.doctorName
                : formatDoctorDisplayName(refRow.doctor_name || refRow.doctorName || '', 'Specialist');

            const statusCategory = classifyReferralStatus(refRow.status);
            const referralTime = formatTimeInTimezone(rawReferralCreatedAt, timeZone);
            const requiredSpecialist = String(
                refRow.required_specialist ||
                refRow.requiredSpecialist ||
                refRow.doctor_specialty ||
                targetDocInfo?.specialty ||
                'General Consultation'
            ).trim();

            if (
                referralStatusFilter &&
                referralStatusFilter.toLowerCase() !== 'all' &&
                statusCategory.toLowerCase() !== referralStatusFilter.toLowerCase()
            ) {
                continue;
            }
            if (searchQuery) {
                const matchesSearch =
                    referralId.toLowerCase().includes(searchQuery) ||
                    patientName.toLowerCase().includes(searchQuery) ||
                    patientPhone.toLowerCase().includes(searchQuery) ||
                    referringDoctorName.toLowerCase().includes(searchQuery) ||
                    referredDoctorName.toLowerCase().includes(searchQuery) ||
                    requiredSpecialist.toLowerCase().includes(searchQuery);
                if (!matchesSearch) continue;
            }

            if (refDateYmd.startsWith(selectedMonth) && monthlyMap.has(refDateYmd)) {
                const cell = monthlyMap.get(refDateYmd);
                cell.referralsCount += 1;
                if (statusCategory === 'Accepted') cell.acceptedReferralsCount += 1;
                else if (statusCategory === 'Completed') cell.completedReferralsCount += 1;
                else if (statusCategory === 'Rejected') cell.rejectedReferralsCount += 1;
                else cell.pendingReferralsCount += 1;
            }

            if (refDateYmd === selectedDate) {
                dailySummary.totalReferrals += 1;
                if (statusCategory === 'Accepted') dailySummary.acceptedReferrals += 1;
                else if (statusCategory === 'Completed') dailySummary.completedReferrals += 1;
                else if (statusCategory === 'Rejected') dailySummary.rejectedReferrals += 1;
                else dailySummary.pendingReferrals += 1;

                dailyReferrals.push({
                    referralId,
                    patientId: referredPatientId,
                    patientName,
                    patientPhone,
                    referringDoctorId: referrerId,
                    referringDoctorName,
                    referredDoctorId: targetDocId,
                    referredDoctorName,
                    requiredSpecialist,
                    clinicName: String(refRow.doctor_clinic_name || targetDocInfo?.clinicName || '').trim(),
                    referralDate: refDateYmd,
                    referralTime,
                    createdAt: rawReferralCreatedAt,
                    status: statusCategory,
                    rawStatus: String(refRow.status || 'Pending').trim(),
                    clinicalComplaint: String(refRow.clinical_complaint || refRow.clinicalComplaint || refRow.notes || '').trim(),
                });
            }
        }

        // Sort daily requests & referrals newest first
        dailyRequests.sort((a, b) => String(b.createdAt || '').localeCompare(String(a.createdAt || '')));
        dailyReferrals.sort((a, b) => String(b.createdAt || '').localeCompare(String(a.createdAt || '')));

        const reqTotal = dailyRequests.length;
        const reqTotalPages = Math.max(1, Math.ceil(reqTotal / pageSize));
        const safeReqPage = Math.min(page, reqTotalPages);
        const reqStart = (safeReqPage - 1) * pageSize;
        const paginatedRequests = dailyRequests.slice(reqStart, reqStart + pageSize);

        const refTotal = dailyReferrals.length;
        const refTotalPages = Math.max(1, Math.ceil(refTotal / pageSize));
        const safeRefPage = Math.min(page, refTotalPages);
        const refStart = (safeRefPage - 1) * pageSize;
        const paginatedReferrals = dailyReferrals.slice(refStart, refStart + pageSize);

        return res.json({
            success: true,
            timezone: timeZone,
            selectedDate,
            selectedMonth,
            monthlyCalendar: Array.from(monthlyMap.values()),
            dailySummary,
            requestTypes: Array.from(distinctRequestTypes).sort(),
            requests: paginatedRequests,
            requestsPagination: {
                page: safeReqPage,
                pageSize,
                totalItems: reqTotal,
                totalPages: reqTotalPages,
            },
            referrals: paginatedReferrals,
            referralsPagination: {
                page: safeRefPage,
                pageSize,
                totalItems: refTotal,
                totalPages: refTotalPages,
            },
        });
    } catch (err) {
        console.error('Get Requests & Referrals Calendar Error:', err.message);
        return res.status(500).json({
            success: false,
            message: 'Failed to load Requests & Referrals Calendar.',
        });
    }
};
