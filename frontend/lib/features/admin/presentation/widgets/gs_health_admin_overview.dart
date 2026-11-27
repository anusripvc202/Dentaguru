import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/models/referral_model.dart';
import '../../../../core/services/patient_problem_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/denta_guru_logo.dart';
import '../../../../core/widgets/dental_ads_banner.dart';
import '../../../../core/widgets/recent_updates_preview_section.dart';

const Color _kBorder = Color(0xFFE2E8F0);
const Color _kSoftNavy = Color(0x14012A58);
const Color _kSoftBorder = Color(0x40012A58);

// =============================================================================
// DATA MODELS
// =============================================================================

/// One statistic card in the 2-column grid.
class AdminStatCardData {
  final String id;
  final String label;
  final int? value;
  final IconData icon;

  /// Crimson accent = "needs attention"; navy accent = inventory counts.
  final bool accentRed;

  /// True when the signed-in role is not allowed to see this figure.
  final bool restricted;
  final VoidCallback? onTap;

  const AdminStatCardData({
    required this.id,
    required this.label,
    required this.value,
    required this.icon,
    this.accentRed = false,
    this.restricted = false,
    this.onTap,
  });
}

/// A quick-action card (Clinics & owners, Referrals, Sponsored ads, SMS login).
class AdminQuickActionData {
  final String id;
  final String label;
  final IconData icon;
  final bool restricted;
  final VoidCallback? onTap;

  const AdminQuickActionData({
    required this.id,
    required this.label,
    required this.icon,
    this.restricted = false,
    this.onTap,
  });
}

/// View-model for Admin appointments. Built strictly from real `appointments` rows
/// using the actual saved `dentist_id` and `clinic_id` (never substituting a later assignment).
class AdminAppointmentItem {
  final String id;
  final String patientId;
  final String patientName;
  final String phone;
  final String status;
  final String dateRaw;
  final String timeSlot;
  final String dentistId;
  final String dentistName;
  final String doctorSpecialty;
  final Uint8List? doctorPhotoBytes;
  final String doctorPhotoUrl;
  final String clinicId;
  final String clinicName;
  final String createdAtRaw;
  final String mode; // 'IN-CLINIC' | 'ONLINE' | ''
  final String notes;
  final String treatment;
  final String scheduledEndTime;
  final String actualStartAt;
  final String actualEndAt;
  final int delayMinutes;
  final String estimatedStartTime;
  final String rescheduleRequestStatus;
  final String rescheduleRequestedDate;
  final String rescheduleRequestedSlot;
  final String rescheduleRequestReason;

  const AdminAppointmentItem({
    required this.id,
    this.patientId = '',
    required this.patientName,
    required this.phone,
    required this.status,
    required this.dateRaw,
    required this.timeSlot,
    required this.dentistName,
    required this.clinicName,
    required this.mode,
    required this.notes,
    required this.treatment,
    this.dentistId = '',
    this.doctorSpecialty = '',
    this.doctorPhotoBytes,
    this.doctorPhotoUrl = '',
    this.clinicId = '',
    this.createdAtRaw = '',
    this.scheduledEndTime = '',
    this.actualStartAt = '',
    this.actualEndAt = '',
    this.delayMinutes = 0,
    this.estimatedStartTime = '',
    this.rescheduleRequestStatus = '',
    this.rescheduleRequestedDate = '',
    this.rescheduleRequestedSlot = '',
    this.rescheduleRequestReason = '',
  });

  static String _firstNonEmpty(Map row, List<String> keys) {
    for (final k in keys) {
      final v = row[k];
      if (v != null) {
        final s = v.toString().trim();
        if (s.isNotEmpty && s != 'null') return s;
      }
    }
    return '';
  }

  static String _normalizeMode(String raw) {
    final u = raw.toUpperCase();
    if (u.contains('CLINIC')) return 'IN-CLINIC';
    if (u.contains('ONLINE') || u.contains('VIDEO') || u.contains('TELE')) {
      return 'ONLINE';
    }
    return '';
  }

  static String _formatDoctorName(String raw) {
    final clean = raw.trim();
    if (clean.isEmpty) return '';
    final lower = clean.toLowerCase();
    if (lower.startsWith('dr.') || lower.startsWith('dr ')) return clean;
    return 'Dr. $clean';
  }

  static ({Uint8List? bytes, String url}) _parsePhoto(dynamic rawPhoto) {
    if (rawPhoto == null) return (bytes: null, url: '');
    final str = rawPhoto.toString().trim();
    if (str.isEmpty || str == 'null') return (bytes: null, url: '');
    if (str.startsWith('http://') || str.startsWith('https://')) {
      return (bytes: null, url: str);
    }
    try {
      final cleaned = str.contains(',') ? str.split(',').last.trim() : str;
      final decoded = base64Decode(cleaned);
      if (decoded.isNotEmpty) return (bytes: decoded, url: '');
    } catch (_) {}
    return (bytes: null, url: '');
  }

  /// Builds an item strictly from a raw `appointments` row, resolving the patient,
  /// originally selected doctor (`dentist_id`), and clinic (`clinic_id`) from the
  /// backend relational joins first, then falling back to synced directories by exact ID.
  factory AdminAppointmentItem.fromRow(
    Map row, {
    required List<PatientProfile> patients,
    required List<DoctorModel> doctors,
  }) {
    final patientObj = (row['patient'] is Map)
        ? row['patient'] as Map
        : (row['users'] is Map ? row['users'] as Map : const {});
    final selectedDocObj = (row['selectedDoctor'] is Map) ? row['selectedDoctor'] as Map : const {};
    final dentistObj = (row['dentist'] is Map) ? row['dentist'] as Map : const {};
    final dentistUserObj = (dentistObj['users'] is Map) ? dentistObj['users'] as Map : const {};
    final dentistClinicObj = (dentistObj['clinics'] is Map) ? dentistObj['clinics'] as Map : const {};
    final clinicObj = row['clinic'] is Map ? row['clinic'] as Map : const {};

    final patientId = _firstNonEmpty(row, ['patient_id', 'patientId']);
    final dentistId = _firstNonEmpty(row, ['dentist_id', 'dentistId']).isNotEmpty
        ? _firstNonEmpty(row, ['dentist_id', 'dentistId'])
        : _firstNonEmpty(selectedDocObj, ['id']);
    final clinicId = _firstNonEmpty(row, ['clinic_id', 'clinicId']).isNotEmpty
        ? _firstNonEmpty(row, ['clinic_id', 'clinicId'])
        : (_firstNonEmpty(clinicObj, ['id']).isNotEmpty
            ? _firstNonEmpty(clinicObj, ['id'])
            : _firstNonEmpty(dentistObj, ['clinic_id']));

    PatientProfile? matchedPatient;
    if (patientId.isNotEmpty) {
      for (final p in patients) {
        if (p.id == patientId) {
          matchedPatient = p;
          break;
        }
      }
    }
    DoctorModel? matchedDoctor;
    if (dentistId.isNotEmpty) {
      for (final d in doctors) {
        if (d.id == dentistId || (d.userId.isNotEmpty && d.userId == dentistId)) {
          matchedDoctor = d;
          break;
        }
      }
    }

    var name = _firstNonEmpty(patientObj, ['name']);
    if (name.isEmpty) name = _firstNonEmpty(row, ['patient_name', 'patientName']);
    if (name.isEmpty) name = matchedPatient?.name ?? '';

    var phone = _firstNonEmpty(patientObj, ['phone']);
    if (phone.isEmpty) phone = _firstNonEmpty(row, ['patient_phone', 'phone']);
    if (phone.isEmpty) phone = matchedPatient?.phone ?? '';

    var dentist = _firstNonEmpty(selectedDocObj, ['name']);
    if (dentist.isEmpty) dentist = _firstNonEmpty(dentistUserObj, ['name']);
    if (dentist.isEmpty) dentist = _firstNonEmpty(dentistObj, ['name']);
    if (dentist.isEmpty) dentist = _firstNonEmpty(row, ['dentist_name', 'dentistName']);
    if (dentist.isEmpty) dentist = matchedDoctor?.name ?? '';
    dentist = _formatDoctorName(dentist);

    var specialty = _firstNonEmpty(selectedDocObj, ['specialty', 'speciality']);
    if (specialty.isEmpty) specialty = _firstNonEmpty(dentistObj, ['speciality', 'specialty']);
    if (specialty.isEmpty) specialty = _firstNonEmpty(row, ['doctor_specialty', 'specialty']);
    if (specialty.isEmpty) specialty = matchedDoctor?.specialty ?? '';

    var clinic = _firstNonEmpty(clinicObj, ['clinic_name', 'name']);
    if (clinic.isEmpty) clinic = _firstNonEmpty(selectedDocObj, ['clinicName', 'clinic_name']);
    if (clinic.isEmpty) clinic = _firstNonEmpty(dentistClinicObj, ['clinic_name', 'name']);
    if (clinic.isEmpty) clinic = _firstNonEmpty(row, ['clinic_name', 'clinicName']);
    if (clinic.isEmpty) clinic = matchedDoctor?.clinicName ?? '';

    final dynamic rawPhoto = selectedDocObj['profilePhoto'] ??
        dentistUserObj['biometric_token'] ??
        dentistObj['profilePhoto'] ??
        row['doctor_photo'];
    final parsedPhoto = _parsePhoto(rawPhoto);
    final Uint8List? photoBytes = parsedPhoto.bytes ?? matchedDoctor?.photoBytes;
    final String photoUrl = parsedPhoto.url;

    var notes = _firstNonEmpty(row, ['notes', 'patient_notes', 'reason', 'symptoms']);
    if (notes.startsWith('{') || notes.startsWith('[')) notes = '';

    final createdRaw = _firstNonEmpty(row, ['booking_created_at', 'created_at', 'createdAt']);

    final reschedMap = row['reschedule_request'] is Map
        ? row['reschedule_request'] as Map
        : (row['rescheduleRequest'] is Map ? row['rescheduleRequest'] as Map : const {});

    return AdminAppointmentItem(
      id: _firstNonEmpty(row, ['id', '_id']),
      patientId: patientId.isNotEmpty
          ? patientId
          : _firstNonEmpty(patientObj, ['id']),
      patientName: name.isEmpty ? 'Patient Unavailable' : name,
      phone: phone,
      status: _firstNonEmpty(row, ['status']).isEmpty
          ? 'PENDING'
          : _firstNonEmpty(row, ['status']),
      dateRaw: _firstNonEmpty(row, ['date', 'appointment_date', 'appointmentDate']),
      timeSlot: _firstNonEmpty(row, ['time_slot', 'timeSlot', 'appointment_time']),
      dentistId: dentistId,
      dentistName: dentist,
      doctorSpecialty: specialty,
      doctorPhotoBytes: photoBytes,
      doctorPhotoUrl: photoUrl,
      clinicId: clinicId,
      clinicName: clinic,
      createdAtRaw: createdRaw,
      mode: _normalizeMode(_firstNonEmpty(row, [
        'consultation_type',
        'consultation_mode',
        'consultationMode',
        'mode',
        'visit_type',
        'visitType',
        'appointment_type',
      ])),
      notes: notes,
      treatment: _firstNonEmpty(row, ['treatment']),
      scheduledEndTime: _firstNonEmpty(row, ['scheduled_end_time', 'scheduledEndTime']),
      actualStartAt: _firstNonEmpty(row, ['actual_start_at', 'actualStartAt']),
      actualEndAt: _firstNonEmpty(row, ['actual_end_at', 'actualEndAt']),
      delayMinutes: int.tryParse((row['delay_minutes'] ?? row['delayMinutes'] ?? '0').toString()) ?? 0,
      estimatedStartTime: _firstNonEmpty(row, ['estimated_start_time', 'estimatedStartTime']),
      rescheduleRequestStatus: _firstNonEmpty(reschedMap, ['status']).isNotEmpty
          ? _firstNonEmpty(reschedMap, ['status'])
          : _firstNonEmpty(row, ['reschedule_request_status', 'rescheduleRequestStatus']),
      rescheduleRequestedDate: _firstNonEmpty(reschedMap, ['requestedDate', 'requested_date']).isNotEmpty
          ? _firstNonEmpty(reschedMap, ['requestedDate', 'requested_date'])
          : _firstNonEmpty(row, ['reschedule_requested_date', 'rescheduleRequestedDate']),
      rescheduleRequestedSlot: _firstNonEmpty(reschedMap, ['requestedTimeSlot', 'requested_time_slot']).isNotEmpty
          ? _firstNonEmpty(reschedMap, ['requestedTimeSlot', 'requested_time_slot'])
          : _firstNonEmpty(row, ['reschedule_requested_slot', 'rescheduleRequestedSlot']),
      rescheduleRequestReason: _firstNonEmpty(reschedMap, ['reason']).isNotEmpty
          ? _firstNonEmpty(reschedMap, ['reason'])
          : _firstNonEmpty(row, ['reschedule_request_reason', 'rescheduleRequestReason']),
    );
  }

  /// Fallback built from consultation requests when appointments table has no rows.
  factory AdminAppointmentItem.fromRequest(PatientConsultationRequest r) {
    return AdminAppointmentItem(
      id: r.id,
      patientId: r.patientId ?? '',
      patientName: r.patientName.trim().isEmpty ? 'Patient Unavailable' : r.patientName.trim(),
      phone: r.patientPhone,
      status: r.status,
      dateRaw: r.confirmedDate ?? r.submittedAt.toIso8601String(),
      timeSlot: r.confirmedTimeSlot ?? '',
      dentistId: r.assignedDoctorId ?? '',
      dentistName: r.assignedDoctorName ?? '',
      doctorSpecialty: r.problemCategory,
      clinicName: r.assignedDoctorClinic ?? '',
      createdAtRaw: r.submittedAt.toIso8601String(),
      mode: r.displayConsultationMode == 'Online' ? 'ONLINE' : 'IN-CLINIC',
      notes: '',
      treatment: r.problemCategory,
      scheduledEndTime: r.scheduledEndTime ?? '',
      actualStartAt: r.actualStartAt ?? '',
      actualEndAt: r.actualEndAt ?? '',
      delayMinutes: r.delayMinutes,
      estimatedStartTime: r.estimatedStartTime ?? '',
      rescheduleRequestStatus: r.rescheduleRequestStatus ?? '',
      rescheduleRequestedDate: r.rescheduleRequestedDate ?? '',
      rescheduleRequestedSlot: r.rescheduleRequestedSlot ?? '',
      rescheduleRequestReason: r.rescheduleRequestReason ?? '',
    );
  }
}

// =============================================================================
// SHARED HELPERS (also used by the Sub-Admin dashboard)
// =============================================================================

/// A request is "awaiting a doctor" when it is still in the admin-review stage
/// and no dentist has been assigned yet.
bool isWaitingForDoctor(PatientConsultationRequest r) {
  final st = r.status.trim().toLowerCase();
  final inReview =
      st == 'pending admin review' || st == 'submitted' || st == 'admin review';
  final hasDoctor = (r.assignedDoctorName != null &&
          r.assignedDoctorName!.trim().isNotEmpty &&
          r.assignedDoctorName != 'null') ||
      (r.assignedDoctorId != null && r.assignedDoctorId!.trim().isNotEmpty);
  return inReview && !hasDoctor;
}

/// De-duplicates requests by patient + category (same intent as the existing
/// admin panel) and returns only those awaiting a doctor.
List<PatientConsultationRequest> waitingConsultationRequests(
  List<PatientConsultationRequest> all,
) {
  final map = <String, PatientConsultationRequest>{};
  for (final r in all) {
    final pKey = (r.patientId != null && r.patientId!.isNotEmpty)
        ? r.patientId!.trim().toLowerCase()
        : r.patientName.trim().toLowerCase();
    final key = pKey.isEmpty ? r.id : '${pKey}_${r.problemCategory.trim().toLowerCase()}';
    map.putIfAbsent(key, () => r);
  }
  return map.values.where(isWaitingForDoctor).toList();
}

/// Doctors whose profile still awaits admin verification.
bool isPendingVerificationDoctor(DoctorModel d) {
  final v = d.verificationStatus.trim().toUpperCase();
  return v == 'PENDING_VERIFICATION' || v == 'PENDING';
}

/// Returns sponsored ads from real backend records (empty when none are configured;
/// never falls back to hardcoded dummy partner ads).
List<DentalAd> sponsoredAdsForOverview() => const [];

/// Removes duplicate appointment items by exact ID and by identical booking fingerprint
/// (patient + doctor + date day + time slot + treatment + status) so retried/duplicate
/// rows never render multiple times in Admin/Sub-Admin dashboards.
List<AdminAppointmentItem> deduplicateAdminAppointments(
  List<AdminAppointmentItem> items,
) {
  final seenIds = <String>{};
  final seenFingerprints = <String>{};
  final result = <AdminAppointmentItem>[];
  for (final item in items) {
    final idKey = item.id.trim();
    if (idKey.isNotEmpty && !seenIds.add(idKey)) continue;
    final dateDay = item.dateRaw.split('T').first.trim().toLowerCase();
    final doctorKey = item.dentistId.trim().isNotEmpty
        ? item.dentistId.trim().toLowerCase()
        : item.dentistName.trim().toLowerCase();
    final fp = [
      item.patientName.trim().toLowerCase(),
      doctorKey,
      dateDay,
      item.timeSlot.trim().toLowerCase(),
      item.treatment.trim().toLowerCase(),
      item.status.trim().toLowerCase(),
    ].join('|');
    if (dateDay.isNotEmpty && item.timeSlot.trim().isNotEmpty && !seenFingerprints.add(fp)) {
      continue;
    }
    result.add(item);
  }
  return result;
}

const List<String> _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const List<String> _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _to24h(String slot) {
  final m = RegExp(r'(\d{1,2}):(\d{2})\s*(AM|PM)?', caseSensitive: false)
      .firstMatch(slot);
  if (m == null) return slot.trim();
  var h = int.parse(m.group(1)!);
  final mm = m.group(2)!;
  final ap = m.group(3)?.toUpperCase();
  if (ap == 'PM' && h < 12) h += 12;
  if (ap == 'AM' && h == 12) h = 0;
  return '${h.toString().padLeft(2, '0')}:$mm';
}

DateTime? _parseDate(String raw) => raw.isEmpty ? null : DateTime.tryParse(raw);

String formatAdminAppointmentDate(String raw) {
  final d = _parseDate(raw);
  if (d == null) return raw.isEmpty ? 'Date not set' : raw;
  final local = d.toLocal();
  return '${_weekdays[local.weekday - 1]}, ${local.day} ${_months[local.month - 1]} ${local.year}';
}

String formatAdminCreatedDateTime(String raw) {
  final d = _parseDate(raw);
  if (d == null) return raw.isEmpty ? 'Not recorded' : raw;
  final local = d.toLocal();
  final h12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final mm = local.minute.toString().padLeft(2, '0');
  final ampm = local.hour >= 12 ? 'PM' : 'AM';
  return '${local.day} ${_months[local.month - 1]} ${local.year}, $h12:$mm $ampm';
}

String _dateLabel(String raw) => formatAdminAppointmentDate(raw);

String adminStatusLabel(String raw) => _statusLabel(raw);

({Color bg, Color fg}) adminStatusColors(String raw) => _statusColors(raw);

/// Reusable avatar showing Doctor profile photo (bytes or network URL) or initials fallback.
class AdminDoctorAvatar extends StatelessWidget {
  final String doctorName;
  final Uint8List? photoBytes;
  final String photoUrl;
  final double radius;

  const AdminDoctorAvatar({
    super.key,
    required this.doctorName,
    this.photoBytes,
    this.photoUrl = '',
    this.radius = 18,
  });

  @override
  Widget build(BuildContext context) {
    final cleaned = doctorName.replaceAll('Dr.', '').replaceAll('Dr ', '').trim();
    final initial = cleaned.isNotEmpty ? cleaned[0].toUpperCase() : 'D';
    if (photoBytes != null && photoBytes!.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: _kSoftNavy,
        backgroundImage: MemoryImage(photoBytes!),
      );
    }
    if (photoUrl.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: _kSoftNavy,
        backgroundImage: NetworkImage(photoUrl),
        onBackgroundImageError: (_, __) {},
        child: null,
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: _kSoftNavy,
      child: Text(
        initial,
        style: TextStyle(
          fontSize: radius * 0.78,
          fontWeight: FontWeight.w800,
          color: AppTheme.gsNavy,
        ),
      ),
    );
  }
}

String _statusLabel(String raw) {
  final s = raw.replaceAll('_', ' ').trim().toLowerCase();
  if (s.isEmpty) return 'Pending';
  return s[0].toUpperCase() + s.substring(1);
}

({Color bg, Color fg}) _statusColors(String raw) {
  final u = raw.toUpperCase();
  if (u.contains('CANCEL') || u.contains('REJECT')) {
    return (bg: const Color(0xFFF1F5F9), fg: const Color(0xFF64748B));
  }
  if (u.contains('PENDING') || u.contains('REVIEW') || u.contains('SUBMITTED')) {
    return (bg: AppTheme.gsRed.withValues(alpha: 0.12), fg: const Color(0xFFFE3434));
  }
  return (bg: _kSoftNavy, fg: AppTheme.gsNavy);
}

// =============================================================================
// HEADER
// =============================================================================

/// Pinned header: GS HEALTH logo, role subtitle, title, notifications, profile.
class GsHealthAdminHeader extends StatelessWidget {
  final String subtitle;
  final String title;
  final int unreadCount;
  final VoidCallback? onNotifications;
  final VoidCallback? onProfile;

  const GsHealthAdminHeader({
    super.key,
    this.subtitle = 'Admin console',
    this.title = 'GS HEALTH',
    this.unreadCount = 0,
    this.onNotifications,
    this.onProfile,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _kBorder)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const GsHealthLogo(height: 30, alignment: Alignment.centerLeft),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      subtitle,
                      key: const Key('admin_header_subtitle'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        color: AppTheme.textMedium,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      title,
                      key: const Key('admin_header_title'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.gsNavy,
                        letterSpacing: -0.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _CircleIconButton(
                key: const Key('admin_header_bell'),
                icon: Icons.notifications_none_rounded,
                badge: unreadCount,
                onTap: onNotifications,
              ),
              const SizedBox(width: 10),
              _CircleIconButton(
                key: const Key('admin_header_profile'),
                icon: Icons.person_outline_rounded,
                onTap: onProfile,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final int badge;
  final VoidCallback? onTap;

  const _CircleIconButton({super.key, required this.icon, this.badge = 0, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: _kBorder, width: 1.2),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Icon(icon, color: AppTheme.gsNavy, size: 22),
            if (badge > 0)
              Positioned(
                top: 2,
                right: 0,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 18),
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppTheme.gsRed,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: Text(
                    badge > 9 ? '9+' : '$badge',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// OVERVIEW PAGE (ONE CONTINUOUS SCROLL VIEW)
// =============================================================================

class GsHealthAdminOverview extends StatefulWidget {
  final List<AdminStatCardData> stats;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback? onRetry;
  final Future<void> Function()? onRefresh;

  final int waitingCount;
  final bool assignRestricted;
  final VoidCallback? onAssign;

  final AdminQuickActionData clinicsAction;
  final AdminQuickActionData referralsAction;
  final AdminQuickActionData sponsoredAction;
  final AdminQuickActionData smsAction;

  final List<DentalAd> ads;

  final List<AdminAppointmentItem> appointments;
  final bool appointmentsRestricted;
  final bool canViewPhone;
  final void Function(AdminAppointmentItem item)? onAppointmentTap;
  final VoidCallback? onViewAllAppointments;
  final List<PatientConsultationRequest> recentRequests;
  final VoidCallback? onViewAllRequests;
  final List<PatientReferral> recentReferrals;
  final VoidCallback? onViewAllReferrals;
  final List<DoctorModel> recentDoctors;
  final VoidCallback? onViewAllDoctors;
  final List<ClinicModel> recentClinics;
  final VoidCallback? onViewAllClinics;
  final List<PatientProfile> recentPatients;
  final VoidCallback? onViewAllPatients;
  final Widget? footer;

  const GsHealthAdminOverview({
    super.key,
    required this.stats,
    required this.waitingCount,
    required this.clinicsAction,
    required this.referralsAction,
    required this.sponsoredAction,
    required this.smsAction,
    required this.ads,
    required this.appointments,
    this.isLoading = false,
    this.errorMessage,
    this.onRetry,
    this.onRefresh,
    this.assignRestricted = false,
    this.onAssign,
    this.appointmentsRestricted = false,
    this.canViewPhone = true,
    this.onAppointmentTap,
    this.onViewAllAppointments,
    this.recentRequests = const <PatientConsultationRequest>[],
    this.onViewAllRequests,
    this.recentReferrals = const <PatientReferral>[],
    this.onViewAllReferrals,
    this.recentDoctors = const <DoctorModel>[],
    this.onViewAllDoctors,
    this.recentClinics = const <ClinicModel>[],
    this.onViewAllClinics,
    this.recentPatients = const <PatientProfile>[],
    this.onViewAllPatients,
    this.footer,
  });

  @override
  State<GsHealthAdminOverview> createState() => _GsHealthAdminOverviewState();
}

class _GsHealthAdminOverviewState extends State<GsHealthAdminOverview> {
  static const int _pageSize = 10;
  int _visibleAppointments = _pageSize;
  int _adPage = 0;
  late final PageController _adController = PageController();

  @override
  void dispose() {
    _adController.dispose();
    super.dispose();
  }

  Future<void> _openAd(DentalAd ad) async {
    final uri = Uri.tryParse(ad.website);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final content = SingleChildScrollView(
      key: const Key('admin_overview_scroll'),
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.errorMessage != null) ...[
            _buildErrorBanner(),
            const SizedBox(height: 14),
          ],
          _buildStatsGrid(),
          const SizedBox(height: 18),
          _buildAssignButton(),
          const SizedBox(height: 14),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _QuickActionCard(data: widget.clinicsAction)),
                const SizedBox(width: 12),
                Expanded(child: _QuickActionCard(data: widget.referralsAction)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _QuickActionCard(data: widget.sponsoredAction, centered: true),
          const SizedBox(height: 12),
          _QuickActionCard(data: widget.smsAction, centered: true),
          const SizedBox(height: 22),
          _buildAdsCarousel(),
          const SizedBox(height: 26),
          _buildLatestAppointments(),
          if (widget.onViewAllRequests != null || widget.recentRequests.isNotEmpty) ...[
            const SizedBox(height: 22),
            _buildRecentRequestsPreview(),
          ],
          if (widget.onViewAllReferrals != null || widget.recentReferrals.isNotEmpty) ...[
            const SizedBox(height: 22),
            _buildRecentReferralsPreview(),
          ],
          if (widget.onViewAllDoctors != null || widget.recentDoctors.isNotEmpty) ...[
            const SizedBox(height: 22),
            _buildRecentDoctorsPreview(),
          ],
          if (widget.onViewAllClinics != null || widget.recentClinics.isNotEmpty) ...[
            const SizedBox(height: 22),
            _buildRecentClinicsPreview(),
          ],
          if (widget.onViewAllPatients != null || widget.recentPatients.isNotEmpty) ...[
            const SizedBox(height: 22),
            _buildRecentPatientsPreview(),
          ],
          if (widget.footer != null) ...[
            const SizedBox(height: 20),
            widget.footer!,
          ],
        ],
      ),
    );

    if (widget.onRefresh == null) return content;
    return RefreshIndicator(
      color: AppTheme.gsNavy,
      onRefresh: widget.onRefresh!,
      child: content,
    );
  }

  // ---------------------------------------------------------------- error ----
  Widget _buildErrorBanner() {
    return Container(
      key: const Key('admin_overview_error_banner'),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.gsRed.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.gsRed.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppTheme.gsRed),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.errorMessage!,
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.textDark,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (widget.onRetry != null)
            TextButton(
              key: const Key('admin_overview_retry'),
              onPressed: widget.onRetry,
              child: const Text(
                'Retry',
                style: TextStyle(
                  color: AppTheme.gsRed,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- stats ----
  Widget _buildStatsGrid() {
    final rows = <Widget>[];
    for (var i = 0; i < widget.stats.length; i += 2) {
      final left = widget.stats[i];
      final right = i + 1 < widget.stats.length ? widget.stats[i + 1] : null;
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _StatCard(data: left, isLoading: widget.isLoading)),
              const SizedBox(width: 12),
              Expanded(
                child: right == null
                    ? const SizedBox.shrink()
                    : _StatCard(data: right, isLoading: widget.isLoading),
              ),
            ],
          ),
        ),
      );
      if (i + 2 < widget.stats.length) rows.add(const SizedBox(height: 12));
    }
    return Column(key: const Key('admin_stats_grid'), children: rows);
  }

  // --------------------------------------------------------------- assign ----
  Widget _buildAssignButton() {
    final String label;
    final bool tappable;
    if (widget.assignRestricted) {
      label = 'Doctor assignment restricted';
      tappable = false;
    } else if (widget.isLoading && widget.waitingCount == 0) {
      label = 'Loading requests…';
      tappable = false;
    } else if (widget.waitingCount > 0) {
      label = 'Assign ${widget.waitingCount} waiting request(s)';
      tappable = true;
    } else {
      label = 'No requests waiting for a doctor';
      tappable = widget.onAssign != null;
    }
    final active = tappable && widget.waitingCount > 0;
    return SizedBox(
      width: double.infinity,
      height: 58,
      child: ElevatedButton.icon(
        key: const Key('admin_assign_waiting_button'),
        onPressed: tappable ? widget.onAssign : null,
        icon: Icon(
          widget.assignRestricted ? Icons.lock_outline_rounded : Icons.arrow_forward_rounded,
          size: 20,
        ),
        label: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.gsNavy,
          foregroundColor: Colors.white,
          disabledBackgroundColor:
              widget.assignRestricted ? const Color(0xFFE2E8F0) : AppTheme.gsNavy.withValues(alpha: 0.55),
          disabledForegroundColor:
              widget.assignRestricted ? AppTheme.textMuted : Colors.white,
          elevation: active ? 2 : 0,
          shadowColor: AppTheme.gsNavy.withValues(alpha: 0.35),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ ads ----
  Widget _buildAdsCarousel() {
    if (widget.ads.isEmpty) {
      return Container(
        key: const Key('admin_ads_empty'),
        width: double.infinity,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: _kBorder),
        ),
        child: const Row(
          children: [
            Icon(Icons.campaign_outlined, color: AppTheme.textMuted),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'No sponsored ads available right now.',
                style: TextStyle(color: AppTheme.textMedium, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: PageView.builder(
            key: const Key('admin_ads_carousel'),
            controller: _adController,
            itemCount: widget.ads.length,
            onPageChanged: (p) => setState(() => _adPage = p),
            itemBuilder: (context, i) => _AdSlide(
              ad: widget.ads[i],
              onTap: () => _openAd(widget.ads[i]),
            ),
          ),
        ),
        if (widget.ads.length > 1) ...[
          const SizedBox(height: 12),
          Row(
            key: const Key('admin_ads_dots'),
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(widget.ads.length, (i) {
              final active = i == _adPage;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: active ? 20 : 7,
                height: 7,
                decoration: BoxDecoration(
                  color: active ? AppTheme.gsNavy : const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(6),
                ),
              );
            }),
          ),
        ],
      ],
    );
  }

  // --------------------------------------------------------- appointments ----
  DateTime _appointmentSortTimestamp(AdminAppointmentItem item) {
    final created = _parseDate(item.createdAtRaw);
    final apptDate = _parseDate(item.dateRaw);
    return apptDate ?? created ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  Widget _buildLatestAppointments() {
    final bool useStrictTwoRecordPreview = widget.onViewAllAppointments != null;
    final List<AdminAppointmentItem> sortedAppointments = useStrictTwoRecordPreview
        ? takeLatestPreviewRecords<AdminAppointmentItem>(
            widget.appointments,
            limit: widget.appointments.length,
            compareDesc: (a, b) => _appointmentSortTimestamp(b).compareTo(_appointmentSortTimestamp(a)),
          )
        : widget.appointments;
    final total = sortedAppointments.length;
    final shown = useStrictTwoRecordPreview
        ? (total < kDashboardRecentPreviewLimit ? total : kDashboardRecentPreviewLimit)
        : (total < _visibleAppointments ? total : _visibleAppointments);
    return Column(
      key: const Key('admin_latest_appointments_section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Latest appointments',
                key: Key('admin_latest_appointments_title'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.gsNavy,
                  letterSpacing: -0.3,
                ),
              ),
            ),
            if (widget.onViewAllAppointments != null)
              TextButton(
                key: const Key('admin_view_all_appointments_btn'),
                onPressed: widget.onViewAllAppointments,
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.gsNavy,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'View All',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.gsNavy,
                      ),
                    ),
                    SizedBox(width: 2),
                    Icon(Icons.chevron_right_rounded, size: 18, color: AppTheme.gsNavy),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (widget.appointmentsRestricted)
          _infoCard(
            key: const Key('admin_appointments_restricted'),
            icon: Icons.lock_outline_rounded,
            text: 'Your role does not include viewing appointments.',
          )
        else if (widget.isLoading && total == 0)
          Column(
            key: const Key('admin_appointments_loading'),
            children: List.generate(
              2,
              (_) => Container(
                height: 112,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: _kBorder),
                ),
                child: const Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4, color: AppTheme.gsNavy),
                  ),
                ),
              ),
            ),
          )
        else if (total == 0)
          _infoCard(
            key: const Key('admin_appointments_empty'),
            icon: Icons.event_busy_rounded,
            text: 'No appointments yet.',
          )
        else ...[
          for (var i = 0; i < shown; i++)
            _AppointmentCard(
              key: Key('admin_appointment_card_$i'),
              item: sortedAppointments[i],
              showPhone: widget.canViewPhone,
              onTap: widget.onAppointmentTap == null
                  ? null
                  : () => widget.onAppointmentTap!(sortedAppointments[i]),
            ),
          if (!useStrictTwoRecordPreview && shown < total)
            Center(
              child: TextButton.icon(
                key: const Key('admin_appointments_load_more'),
                onPressed: () => setState(() => _visibleAppointments += _pageSize),
                icon: const Icon(Icons.expand_more_rounded, color: AppTheme.gsNavy),
                label: Text(
                  'Load more (${total - shown} remaining)',
                  style: const TextStyle(color: AppTheme.gsNavy, fontWeight: FontWeight.w800),
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildRecentRequestsPreview() {
    final latestRequests = takeLatestPreviewRecords<PatientConsultationRequest>(
      widget.recentRequests,
      limit: kDashboardRecentPreviewLimit,
      compareDesc: (a, b) => b.submittedAt.compareTo(a.submittedAt),
    );
    return RecentUpdatesPreviewSection(
      sectionKey: const Key('admin_recent_requests_section'),
      viewAllKey: const Key('admin_view_all_requests_btn'),
      emptyStateKey: const Key('admin_recent_requests_empty'),
      title: 'Recent Requests',
      totalCount: widget.recentRequests.length,
      icon: Icons.inbox_outlined,
      onViewAll: widget.onViewAllRequests,
      isLoading: widget.isLoading,
      emptyIcon: Icons.inbox_outlined,
      emptyTitle: 'No consultation requests yet.',
      emptySubtitle: 'New patient consultation requests will appear here.',
      previewChildren: latestRequests.asMap().entries.map((entry) {
        final idx = entry.key;
        final req = entry.value;
        final d = req.submittedAt.toLocal();
        final h12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
        final mm = d.minute.toString().padLeft(2, '0');
        final ampm = d.hour >= 12 ? 'PM' : 'AM';
        final dateStr = '${d.day} ${_months[d.month - 1]} ${d.year}, $h12:$mm $ampm';
        final stColors = _statusColors(req.status);
        final pName = req.patientName.trim().isNotEmpty ? req.patientName.trim() : 'Patient';
        final reqType = req.problemCategory.trim().isNotEmpty
            ? req.problemCategory.trim()
            : 'General Consultation';
        return RecentUpdatePreviewCard(
          cardKey: Key('admin_recent_request_card_$idx'),
          leadingIcon: Icons.medical_information_outlined,
          title: '$pName • $reqType',
          subtitle: 'Request ID: ${req.id} • Type: $reqType',
          metaLine: 'Date: $dateStr${req.patientPhone.trim().isNotEmpty ? " • Mobile: ${req.patientPhone.trim()}" : ""}',
          statusLabel: _statusLabel(req.status),
          statusColor: stColors.fg,
          statusBgColor: stColors.bg,
          onTap: widget.onViewAllRequests,
        );
      }).toList(),
    );
  }

  Widget _buildRecentReferralsPreview() {
    final latestReferrals = takeLatestPreviewRecords<PatientReferral>(
      widget.recentReferrals,
      limit: kDashboardRecentPreviewLimit,
      compareDesc: (a, b) => b.createdAt.compareTo(a.createdAt),
    );
    return RecentUpdatesPreviewSection(
      sectionKey: const Key('admin_recent_referrals_section'),
      viewAllKey: const Key('admin_view_all_referrals_btn'),
      emptyStateKey: const Key('admin_recent_referrals_empty'),
      title: 'Recent Referrals',
      totalCount: widget.recentReferrals.length,
      icon: Icons.share_outlined,
      onViewAll: widget.onViewAllReferrals,
      isLoading: widget.isLoading,
      emptyIcon: Icons.share_outlined,
      emptyTitle: 'No referrals yet.',
      emptySubtitle: 'Doctor and patient referrals will appear here.',
      previewChildren: latestReferrals.asMap().entries.map((entry) {
        final idx = entry.key;
        final ref = entry.value;
        final d = ref.createdAt.toLocal();
        final h12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
        final mm = d.minute.toString().padLeft(2, '0');
        final ampm = d.hour >= 12 ? 'PM' : 'AM';
        final dateStr = '${d.day} ${_months[d.month - 1]} ${d.year}, $h12:$mm $ampm';
        final stColors = _statusColors(ref.status);
        final referringDoc = ref.referrerPatientName.trim().isNotEmpty
            ? ref.referrerPatientName.trim()
            : 'Referring Doctor';
        final referredDoc = ref.doctorName.trim().isNotEmpty
            ? ref.doctorName.trim()
            : (ref.requiredSpecialist.trim().isNotEmpty ? ref.requiredSpecialist.trim() : 'Specialist');
        return RecentUpdatePreviewCard(
          cardKey: Key('admin_recent_referral_card_$idx'),
          leadingIcon: Icons.assignment_ind_outlined,
          title: '${ref.referredPatientName} → $referredDoc',
          subtitle: 'Referral ID: ${ref.id} • Referring: $referringDoc • Referred: $referredDoc',
          metaLine: 'Date: $dateStr${ref.referredPatientMobile.trim().isNotEmpty ? " • Mobile: ${ref.referredPatientMobile.trim()}" : ""}',
          statusLabel: _statusLabel(ref.status),
          statusColor: stColors.fg,
          statusBgColor: stColors.bg,
          onTap: widget.onViewAllReferrals,
        );
      }).toList(),
    );
  }

  Widget _buildRecentDoctorsPreview() {
    final latestDoctors = takeLatestPreviewRecords<DoctorModel>(
      widget.recentDoctors,
      limit: kDashboardRecentPreviewLimit,
    );
    return RecentUpdatesPreviewSection(
      sectionKey: const Key('admin_recent_doctors_section'),
      viewAllKey: const Key('admin_view_all_doctors_btn'),
      emptyStateKey: const Key('admin_recent_doctors_empty'),
      title: 'Recent Doctor Registrations',
      totalCount: widget.recentDoctors.length,
      icon: Icons.medical_services_outlined,
      onViewAll: widget.onViewAllDoctors,
      isLoading: widget.isLoading,
      emptyIcon: Icons.medical_services_outlined,
      emptyTitle: 'No registered doctors yet.',
      emptySubtitle: 'Newly registered doctors will appear here.',
      previewChildren: latestDoctors.asMap().entries.map((entry) {
        final idx = entry.key;
        final doc = entry.value;
        final isPending = isPendingVerificationDoctor(doc);
        return RecentUpdatePreviewCard(
          cardKey: Key('admin_recent_doctor_card_$idx'),
          leadingIcon: Icons.person_outline_rounded,
          title: doc.name,
          subtitle: '${doc.specialty}${doc.qualification.isNotEmpty ? " • ${doc.qualification}" : ""}',
          metaLine: [
            if (doc.clinicName.trim().isNotEmpty) doc.clinicName.trim(),
            if (doc.city.trim().isNotEmpty) doc.city.trim(),
            if (doc.phone.trim().isNotEmpty) doc.phone.trim(),
          ].join(' • '),
          statusLabel: isPending ? 'Pending' : (doc.isAvailable ? 'Available' : 'Offline'),
          statusColor: isPending ? AppTheme.gsRed : AppTheme.gsNavy,
          statusBgColor: isPending ? AppTheme.gsRed.withValues(alpha: 0.12) : _kSoftNavy,
          onTap: widget.onViewAllDoctors,
        );
      }).toList(),
    );
  }

  Widget _buildRecentClinicsPreview() {
    final latestClinics = takeLatestPreviewRecords<ClinicModel>(
      widget.recentClinics,
      limit: kDashboardRecentPreviewLimit,
    );
    return RecentUpdatesPreviewSection(
      sectionKey: const Key('admin_recent_clinics_section'),
      viewAllKey: const Key('admin_view_all_clinics_btn'),
      emptyStateKey: const Key('admin_recent_clinics_empty'),
      title: 'Recent Clinic Registrations',
      totalCount: widget.recentClinics.length,
      icon: Icons.local_hospital_outlined,
      onViewAll: widget.onViewAllClinics,
      isLoading: widget.isLoading,
      emptyIcon: Icons.local_hospital_outlined,
      emptyTitle: 'No registered clinics yet.',
      emptySubtitle: 'Newly registered clinics will appear here.',
      previewChildren: latestClinics.asMap().entries.map((entry) {
        final idx = entry.key;
        final c = entry.value;
        return RecentUpdatePreviewCard(
          cardKey: Key('admin_recent_clinic_card_$idx'),
          leadingIcon: Icons.apartment_rounded,
          title: c.clinicName.isNotEmpty ? c.clinicName : 'Clinic',
          subtitle: c.displayAddress.isNotEmpty ? c.displayAddress : 'Address not provided',
          metaLine: [
            if (c.cityStatePincode.isNotEmpty) c.cityStatePincode,
            'ID: ${c.id}',
          ].join(' • '),
          statusLabel: '${c.associatedDoctorsCount} Doctors',
          statusColor: AppTheme.gsNavy,
          statusBgColor: _kSoftNavy,
          onTap: widget.onViewAllClinics,
        );
      }).toList(),
    );
  }

  Widget _buildRecentPatientsPreview() {
    final latestPatients = takeLatestPreviewRecords<PatientProfile>(
      widget.recentPatients,
      limit: kDashboardRecentPreviewLimit,
    );
    return RecentUpdatesPreviewSection(
      sectionKey: const Key('admin_recent_patients_section'),
      viewAllKey: const Key('admin_view_all_patients_btn'),
      emptyStateKey: const Key('admin_recent_patients_empty'),
      title: 'Recent Patients',
      totalCount: widget.recentPatients.length,
      icon: Icons.people_outline_rounded,
      onViewAll: widget.onViewAllPatients,
      isLoading: widget.isLoading,
      emptyIcon: Icons.people_outline_rounded,
      emptyTitle: 'No registered patients in this jurisdiction.',
      emptySubtitle: 'Verified patients matching your district access will appear here.',
      previewChildren: latestPatients.asMap().entries.map((entry) {
        final idx = entry.key;
        final pat = entry.value;
        final resolved = PatientProblemService().resolvePatientDistrictStrict(
          districtId: pat.districtId,
          district: pat.district,
          city: pat.city,
          state: pat.state,
          pincode: pat.pincode,
        );
        final distLabel = resolved.isVerified && (resolved.districtName ?? '').isNotEmpty
            ? '${resolved.districtName}${(resolved.state ?? '').isNotEmpty ? ", ${resolved.state}" : ""}'
            : (pat.city.trim().isNotEmpty ? pat.city.trim() : 'District Pending Verification');
        return RecentUpdatePreviewCard(
          cardKey: Key('admin_recent_patient_card_$idx'),
          leadingIcon: Icons.person_outline_rounded,
          title: pat.name.trim().isNotEmpty ? pat.name.trim() : 'Patient',
          subtitle: 'Location: $distLabel${pat.pincode.trim().isNotEmpty ? " (${pat.pincode.trim()})" : ""}',
          metaLine: [
            if (widget.canViewPhone && pat.phone.trim().isNotEmpty) 'Mobile: ${pat.phone.trim()}',
            if (pat.email.trim().isNotEmpty && !pat.email.endsWith('@dentaguru.internal')) pat.email.trim(),
          ].join(' • '),
          statusLabel: resolved.isVerified ? 'Verified' : 'Unverified',
          statusColor: resolved.isVerified ? AppTheme.gsNavy : AppTheme.gsRed,
          statusBgColor: resolved.isVerified ? _kSoftNavy : AppTheme.gsRed.withValues(alpha: 0.12),
          onTap: widget.onViewAllPatients,
        );
      }).toList(),
    );
  }

  Widget _infoCard({Key? key, required IconData icon, required String text}) {
    return Container(
      key: key,
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _kBorder),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.textMuted),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: AppTheme.textMedium, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// STAT CARD
// =============================================================================

class _StatCard extends StatelessWidget {
  final AdminStatCardData data;
  final bool isLoading;

  const _StatCard({required this.data, required this.isLoading});

  @override
  Widget build(BuildContext context) {
    final accent = data.accentRed ? AppTheme.gsRed : AppTheme.gsNavy;
    final Widget valueWidget;
    if (data.restricted) {
      valueWidget = const Text(
        '—',
        style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: AppTheme.textMuted),
      );
    } else if (isLoading && data.value == null) {
      valueWidget = Container(
        key: Key('admin_stat_loading_${data.id}'),
        width: 40,
        height: 30,
        decoration: BoxDecoration(
          color: const Color(0xFFE2E8F0),
          borderRadius: BorderRadius.circular(8),
        ),
      );
    } else {
      valueWidget = FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          '${data.value ?? 0}',
          key: Key('admin_stat_value_${data.id}'),
          style: const TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.w800,
            color: AppTheme.gsNavy,
            height: 1.1,
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: data.restricted ? const Color(0xFFF8FAFC) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _kBorder),
        boxShadow: [
          BoxShadow(
            color: AppTheme.gsNavy.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: Key('admin_stat_${data.id}'),
          borderRadius: BorderRadius.circular(22),
          onTap: data.onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(child: Align(alignment: Alignment.centerLeft, child: valueWidget)),
                    const SizedBox(width: 6),
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.10),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        data.restricted ? Icons.lock_outline_rounded : data.icon,
                        size: 17,
                        color: data.restricted ? AppTheme.textMuted : accent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  data.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    height: 1.25,
                    fontWeight: FontWeight.w500,
                    color: data.restricted ? AppTheme.textMuted : AppTheme.textMedium,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// QUICK ACTION CARD
// =============================================================================

class _QuickActionCard extends StatelessWidget {
  final AdminQuickActionData data;
  final bool centered;

  const _QuickActionCard({required this.data, this.centered = false});

  @override
  Widget build(BuildContext context) {
    final restricted = data.restricted;
    final iconColor = restricted ? AppTheme.textMuted : AppTheme.gsRed;
    final textColor = restricted ? AppTheme.textMuted : AppTheme.gsNavy;
    return Material(
      color: restricted ? const Color(0xFFF1F5F9) : _kSoftNavy,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        key: Key('admin_action_${data.id}'),
        borderRadius: BorderRadius.circular(18),
        onTap: data.onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: restricted ? _kBorder : _kSoftBorder),
          ),
          child: Row(
            mainAxisAlignment: centered ? MainAxisAlignment.center : MainAxisAlignment.start,
            children: [
              Icon(restricted ? Icons.lock_outline_rounded : data.icon, size: 22, color: iconColor),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  data.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: centered ? TextAlign.center : TextAlign.start,
                  style: TextStyle(
                    fontSize: 16,
                    height: 1.2,
                    fontWeight: FontWeight.w800,
                    color: textColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// SPONSORED AD SLIDE
// =============================================================================

class _AdSlide extends StatelessWidget {
  final DentalAd ad;
  final VoidCallback onTap;

  const _AdSlide({required this.ad, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            fit: StackFit.expand,
            children: [
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF012A58), AppTheme.gsNavy, Color(0xFF012A58)],
                  ),
                ),
              ),
              Positioned(
                right: -14,
                top: 18,
                child: Icon(ad.icon, size: 150, color: Colors.white.withValues(alpha: 0.10)),
              ),
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 36, 20, 50),
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(ad.icon, color: Colors.white, size: 32),
                          const SizedBox(height: 6),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 280),
                            child: Text(
                              ad.brand.toUpperCase(),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 14,
                top: 14,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Text(
                    'SPONSORED',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.9,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black.withValues(alpha: 0.72)],
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          ad.tagline,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            height: 1.2,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Icon(Icons.open_in_new_rounded, color: Colors.white, size: 20),
                    ],
                  ),
                ),
              ),
              const Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SizedBox(
                  height: 4,
                  child: ColoredBox(color: AppTheme.gsRed),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// APPOINTMENT CARD
// =============================================================================

class _AppointmentCard extends StatelessWidget {
  final AdminAppointmentItem item;
  final bool showPhone;
  final VoidCallback? onTap;

  const _AppointmentCard({super.key, required this.item, required this.showPhone, this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = _statusColors(item.status);
    final date = _parseDate(item.dateRaw);
    final dayAbbr = date == null ? '—' : _weekdays[date.toLocal().weekday - 1];
    final time = item.timeSlot.isEmpty ? '—' : _to24h(item.timeSlot);
    final displayDoctorName = item.dentistName.isNotEmpty ? item.dentistName : 'Doctor Unavailable';
    final displaySpecialty = item.doctorSpecialty.isNotEmpty ? item.doctorSpecialty : 'Specialty Not Listed';
    final displayClinic = item.clinicName.isNotEmpty ? item.clinicName : 'Clinic Not Listed';
    final displayPhone = item.phone.isNotEmpty ? item.phone : 'No mobile';
    final dateLine = [
      if (item.dateRaw.isNotEmpty) _dateLabel(item.dateRaw),
      if (item.timeSlot.isNotEmpty) item.timeSlot,
    ].join(' · ');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _kBorder),
        boxShadow: [
          BoxShadow(
            color: AppTheme.gsNavy.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 68,
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                  decoration: BoxDecoration(
                    color: _kSoftNavy,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        dayAbbr,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppTheme.textMedium,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          time,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.gsNavy,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              item.patientName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 16,
                                height: 1.2,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.textDark,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            flex: 0,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                              decoration: BoxDecoration(
                                color: colors.bg,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Text(
                                _statusLabel(item.status),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                  color: colors.fg,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (showPhone) ...[
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            const Icon(Icons.phone_outlined, size: 13, color: AppTheme.textMuted),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                displayPhone,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12.5, color: AppTheme.textMedium),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (dateLine.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          dateLine,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12.5, color: AppTheme.textMedium, fontWeight: FontWeight.w600),
                        ),
                      ],
                      const SizedBox(height: 8),
                      // Selected Doctor box (photo + name + specialization + clinic)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _kBorder),
                        ),
                        child: Row(
                          children: [
                            AdminDoctorAvatar(
                              doctorName: displayDoctorName,
                              photoBytes: item.doctorPhotoBytes,
                              photoUrl: item.doctorPhotoUrl,
                              radius: 17,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    displayDoctorName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w800,
                                      color: AppTheme.gsNavy,
                                    ),
                                  ),
                                  const SizedBox(height: 1),
                                  Text(
                                    '$displaySpecialty • $displayClinic',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12, color: AppTheme.textMedium),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (item.createdAtRaw.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Booked on: ${formatAdminCreatedDateTime(item.createdAtRaw)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
                        ),
                      ],
                      if (item.mode.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                item.mode == 'ONLINE' ? Icons.videocam_outlined : Icons.apartment_rounded,
                                size: 14,
                                color: AppTheme.gsNavy,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                item.mode,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.gsNavy,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (item.notes.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          '“${item.notes}”',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontStyle: FontStyle.italic,
                            color: AppTheme.textMedium,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// SHEETS
// =============================================================================

Future<void> _showSheet(BuildContext context, Widget Function(BuildContext) builder) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: builder,
  );
}

Widget _sheetHandle() => Center(
      child: Container(
        width: 42,
        height: 4,
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFCBD5E1),
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );

Widget _sheetTitle(String text, {IconData? icon}) => Row(
      children: [
        if (icon != null) ...[
          Icon(icon, color: AppTheme.gsRed, size: 22),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: AppTheme.gsNavy,
            ),
          ),
        ),
      ],
    );

/// Read-only list of the sponsored ads patients currently see.
Future<void> showAdminSponsoredAdsSheet(BuildContext context, List<DentalAd> ads) {
  return _showSheet(
    context,
    (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sheetHandle(),
              _sheetTitle('Sponsored ads', icon: Icons.campaign_outlined),
              const SizedBox(height: 6),
              const Text(
                'Ads currently shown to patients. This list is read-only here.',
                style: TextStyle(fontSize: 13, color: AppTheme.textMedium),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ads.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Text('No sponsored ads available right now.'),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: ads.length,
                        separatorBuilder: (_, __) => const Divider(height: 1, color: _kBorder),
                        itemBuilder: (_, i) {
                          final ad = ads[i];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              backgroundColor: _kSoftNavy,
                              child: Icon(ad.icon, color: AppTheme.gsNavy, size: 20),
                            ),
                            title: Text(
                              ad.brand,
                              style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.textDark),
                            ),
                            subtitle: Text(ad.tagline, maxLines: 2, overflow: TextOverflow.ellipsis),
                            trailing: const Icon(Icons.open_in_new_rounded, size: 18, color: AppTheme.gsNavy),
                            onTap: () async {
                              final uri = Uri.tryParse(ad.website);
                              if (uri == null) return;
                              try {
                                await launchUrl(uri, mode: LaunchMode.externalApplication);
                              } catch (_) {}
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Read-only description of the existing mobile-OTP (SMS) sign-in flow.
Future<void> showAdminSmsLoginSheet(BuildContext context) {
  Widget row(IconData icon, String title, String body) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: _kSoftNavy, borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, size: 19, color: AppTheme.gsNavy),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 14.5, color: AppTheme.textDark)),
                  const SizedBox(height: 2),
                  Text(body,
                      style: const TextStyle(fontSize: 13, height: 1.35, color: AppTheme.textMedium)),
                ],
              ),
            ),
          ],
        ),
      );

  return _showSheet(
    context,
    (ctx) => SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sheetHandle(),
              _sheetTitle('SMS login', icon: Icons.sms_outlined),
              const SizedBox(height: 14),
              row(Icons.phone_iphone_rounded, 'Sign-in method',
                  'Patients and dentists sign in with their mobile number and a one-time code (OTP).'),
              row(Icons.pin_outlined, 'Code format', 'A 4-digit code is generated by the server for each request.'),
              row(Icons.send_rounded, 'Delivery',
                  'The server sends the code by SMS through its configured gateway (Fast2SMS for +91 numbers, Twilio for others).'),
              row(Icons.lock_outline_rounded, 'Configuration',
                  'Gateway keys live in the backend environment and are not exposed to the app, so they cannot be changed from here.'),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Read-only appointment details.
Future<void> showAdminAppointmentDetailsSheet(
  BuildContext context,
  AdminAppointmentItem item, {
  required bool canViewPhone,
  VoidCallback? onOpenSchedule,
}) {
  Widget line(String label, String value) => value.isEmpty
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 96,
                child: Text(label,
                    style: const TextStyle(fontSize: 13, color: AppTheme.textMuted, fontWeight: FontWeight.w600)),
              ),
              Expanded(
                child: Text(value,
                    style: const TextStyle(fontSize: 14, color: AppTheme.textDark, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        );

  final colors = _statusColors(item.status);
  return _showSheet(
    context,
    (ctx) => SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sheetHandle(),
              Row(
                children: [
                  Expanded(child: _sheetTitle(item.patientName)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: colors.bg, borderRadius: BorderRadius.circular(14)),
                    child: Text(_statusLabel(item.status),
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: colors.fg)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Selected Doctor summary header with profile photo
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _kBorder),
                ),
                child: Row(
                  children: [
                    AdminDoctorAvatar(
                      doctorName: item.dentistName.isNotEmpty ? item.dentistName : 'Doctor',
                      photoBytes: item.doctorPhotoBytes,
                      photoUrl: item.doctorPhotoUrl,
                      radius: 22,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'SELECTED DOCTOR',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppTheme.textMuted, letterSpacing: 0.6),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.dentistName.isNotEmpty ? item.dentistName : 'Doctor Unavailable',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppTheme.gsNavy),
                          ),
                          Text(
                            item.doctorSpecialty.isNotEmpty ? item.doctorSpecialty : 'Specialty Not Listed',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12.5, color: AppTheme.textMedium),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              line('Patient', item.patientName),
              if (canViewPhone) line('Mobile', item.phone.isNotEmpty ? item.phone : 'Not provided'),
              line('Doctor', item.dentistName.isNotEmpty ? item.dentistName : 'Doctor Unavailable'),
              line('Specialty', item.doctorSpecialty.isNotEmpty ? item.doctorSpecialty : 'Specialty Not Listed'),
              line('Clinic', item.clinicName.isNotEmpty ? item.clinicName : 'Clinic Not Listed'),
              line('Appt. Date', item.dateRaw.isEmpty ? 'Date not set' : formatAdminAppointmentDate(item.dateRaw)),
              line('Appt. Time', item.timeSlot.isEmpty ? 'Time not set' : item.timeSlot),
              line('Booked On', item.createdAtRaw.isEmpty ? 'Not recorded' : formatAdminCreatedDateTime(item.createdAtRaw)),
              line('Status', _statusLabel(item.status)),
              line('Treatment', item.treatment),
              line('Type', item.mode),
              line('Notes', item.notes),
              if (onOpenSchedule != null) ...[
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      onOpenSchedule();
                    },
                    icon: const Icon(Icons.calendar_month_rounded, size: 18),
                    label: const Text('Open appointments schedule',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.gsNavy,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

/// Simple notifications list used by the Sub-Admin dashboard.
Future<void> showAdminNotificationsSheet(
  BuildContext context, {
  required List<AppNotificationModel> notifications,
  VoidCallback? onMarkAllRead,
}) {
  return _showSheet(
    context,
    (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.75),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sheetHandle(),
              Row(
                children: [
                  Expanded(child: _sheetTitle('Notifications', icon: Icons.notifications_active_outlined)),
                  if (onMarkAllRead != null && notifications.any((n) => !n.isRead))
                    TextButton(
                      onPressed: () {
                        onMarkAllRead();
                        Navigator.of(ctx).pop();
                      },
                      child: const Text('Mark all read',
                          style: TextStyle(color: AppTheme.gsNavy, fontWeight: FontWeight.w800)),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Flexible(
                child: notifications.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(child: Text('No notifications yet.')),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: notifications.length,
                        separatorBuilder: (_, __) => const Divider(height: 1, color: _kBorder),
                        itemBuilder: (_, i) {
                          final n = notifications[i];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              n.isRead ? Icons.notifications_none_rounded : Icons.notifications_active_rounded,
                              color: n.isRead ? AppTheme.textMuted : AppTheme.gsRed,
                            ),
                            title: Text(n.title, style: const TextStyle(fontWeight: FontWeight.w800)),
                            subtitle: Text(n.message),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
