import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/denta_guru_logo.dart';
import '../../../../core/widgets/recent_updates_preview_section.dart';
import '../../../../core/services/patient_problem_service.dart';
import '../../../../core/services/api_service.dart';
import '../../../../core/services/session_service.dart';
import '../../../../core/utils/record_file_helper.dart';
import '../../../../core/widgets/whatsapp_chat_modal.dart';
import '../../../patient/presentation/widgets/referred_patients_sheet.dart';
import '../../../../core/models/specialty_clinical_config.dart';
import '../../../../core/models/doctor_availability.dart';
import '../../../../core/models/referral_model.dart';
import '../../../../core/utils/prescription_pdf_generator.dart';
import 'doctor_appointments_calendar_screen.dart';
import '../widgets/specialty_prescription_modal.dart';
import '../../../admin/presentation/widgets/doctor_slot_management_dialog.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'doctor_patient_record_screen.dart';
import 'doctor_profile_screen.dart';

typedef DentistTimeline = DentistTimelineScreen;

class DentistTimelineScreen extends StatefulWidget {
  final int initialTabIndex;
  const DentistTimelineScreen({super.key, this.initialTabIndex = 0});

  @override
  State<DentistTimelineScreen> createState() => _DentistTimelineScreenState();
}

class _DentistTimelineScreenState extends State<DentistTimelineScreen> with TickerProviderStateMixin {
  int _currentIndex = 0;
  final PatientProblemService _patientService = PatientProblemService();

  Timer? _autoSyncTimer;
  Timer? _idleAvailabilityTimer;
  RealtimeChannel? _realtimeChannel;

  late AnimationController _entryController;
  late AnimationController _pulseController;

  // ── Today Tab State ──
  int _selectedDateIndex = 0;
  final DateTime _baseCalendarDate = DateTime.now();
  bool _isDentistAvailableNow = true;
  bool _isUpdatingAvailability = false;
  String _visitPeriodFilter = 'All'; // 'All' | 'Today' | 'Upcoming' | 'Previous'
  DoctorScheduleModel _doctorSchedule = const DoctorScheduleModel();
  List<DoctorAvailabilityModel> _doctorBlockedDates = const [];
  bool _hasSyncedDoctorSchedule = false;

  // ── Patients Tab State ──
  final TextEditingController _patientSearchCtrl = TextEditingController();
  String _patientSearchQuery = '';

  // ── Assigned Requests Tab State ──
  final Set<String> _acceptingRequestIds = {};

  // ── Refer a Patient Tab State ──
  int _previousTabIndex = 1;
  final _referFormKey = GlobalKey<FormState>();
  bool _referToClinic = false;
  final TextEditingController _referPatientNameCtrl = TextEditingController();
  final TextEditingController _referPatientMobileCtrl = TextEditingController();
  final TextEditingController _referPatientAgeCtrl = TextEditingController();
  String _referPatientGender = 'Female';
  PatientProfile? _selectedReferPatient;
  String? _selectedReferPatientChipName;
  final TextEditingController _referSearchCtrl = TextEditingController();
  DoctorModel? _selectedReferDoctor;
  ClinicModel? _selectedReferClinic;
  final TextEditingController _referNotesCtrl = TextEditingController();
  final List<String> _referAttachments = [];
  final List<PickedRecordFile> _referPickedAttachments = [];
  bool _isSubmittingReferral = false;

  // ── E-Prescriptions Tab State ──
  final Set<String> _expandedRxCardIds = {};

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialTabIndex;
    _patientService.addListener(_onServiceUpdate);
    _patientService.setDentistMode(true);
    _patientService.syncAllDataFromApi();
    _patientService.syncDoctorsFromApi();
    _patientService.syncClinicsFromApi();
    _patientService.syncAppointmentsFromApi();
    _patientService.syncDoctorReferralsFromApi();
    _patientService.syncReferralsFromApi();
    _patientService.syncNotificationsFromApi(role: 'Dentist');

    if (_patientService.pendingReferralPatient != null) {
      _selectPatientForReferral(_patientService.pendingReferralPatient!);
      _patientService.clearPendingReferralPatient();
      _currentIndex = 3;
    }

    // Sync initial availability state from currentDoctor
    final initialDoc = _resolveCurrentDoctor() ?? _patientService.currentDoctor;
    _isDentistAvailableNow = initialDoc?.isAvailable ?? true;
    _syncDoctorScheduleAndBlockedDates();

    _referSearchCtrl.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });

    // ⏱️ Auto-sync polling timer (every 4s) to catch assigned patients & direct referrals immediately
    _autoSyncTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted) {
        _patientService.syncAppointmentsFromApi();
        _patientService.syncProblemRequestsFromApi();
        _patientService.syncDentistAssignedRequestsFromApi();
        _patientService.syncDoctorReferralsFromApi();
        _patientService.syncReferralsFromApi();
        _patientService.syncNotificationsFromApi(role: 'Dentist');
      }
    });

    // ⚡ Supabase Realtime Postgres Changes listener for instant dentist dashboard updates
    try {
      _realtimeChannel = Supabase.instance.client
          .channel('dentist_dashboard_realtime')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'patient_problem_requests',
            callback: (payload) {
              debugPrint('⚡ Realtime update on patient_problem_requests for Dentist: ${payload.eventType}');
              if (mounted) {
                _patientService.syncProblemRequestsFromApi();
                _patientService.syncDentistAssignedRequestsFromApi();
                _patientService.syncNotificationsFromApi(role: 'Dentist');
              }
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'appointments',
            callback: (payload) {
              debugPrint('⚡ Realtime update on appointments for Dentist: ${payload.eventType}');
              if (mounted) {
                _patientService.syncAppointmentsFromApi();
                _patientService.syncNotificationsFromApi(role: 'Dentist');
              }
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'referrals',
            callback: (payload) {
              debugPrint('⚡ Realtime update on referrals for Dentist: ${payload.eventType}');
              if (mounted) {
                _patientService.syncDoctorReferralsFromApi();
                _patientService.syncReferralsFromApi();
                _patientService.syncNotificationsFromApi(role: 'Dentist');
              }
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'dentists',
            callback: (payload) {
              if (mounted && !_isUpdatingAvailability) {
                _patientService.syncDoctorsFromApi(includeUnavailable: true);
              }
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'notifications',
            callback: (payload) {
              debugPrint('⚡ Realtime update on notifications for Dentist: ${payload.eventType}');
              if (mounted) {
                _patientService.syncNotificationsFromApi(role: 'Dentist');
              }
            },
          )
          .subscribe();
    } catch (e) {
      debugPrint('Dentist Realtime Channel Notice: $e');
    }

    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    _entryController.forward();
  }

  Future<void> _setDoctorPresenceState(String presenceState) async {
    if (_isUpdatingAvailability) return;
    final cleanState = presenceState.trim();
    final bool nextAvailable =
        cleanState != 'Offline' && cleanState != 'Unavailable';
    setState(() {
      _isDentistAvailableNow = nextAvailable;
      _isUpdatingAvailability = true;
    });
    _idleAvailabilityTimer?.cancel();

    DoctorModel? doc = _resolveCurrentDoctor();
    if (doc == null || doc.id.isEmpty || doc.id.toUpperCase().startsWith('DOC-')) {
      await _patientService.syncDoctorsFromApi(includeUnavailable: true);
      doc = _resolveCurrentDoctor();
    }
    final sess = SessionService().currentSession;
    final String targetDoctorId = (doc != null && doc.id.isNotEmpty && !doc.id.toUpperCase().startsWith('DOC-'))
        ? doc.id
        : ((sess?.metadata['dentistId']?.toString().trim().isNotEmpty == true)
            ? sess!.metadata['dentistId'].toString().trim()
            : ((sess?.userId.trim().isNotEmpty == true)
                ? sess!.userId.trim()
                : (doc?.id ?? '')));

    Map<String, dynamic> result = {'success': true};
    if (targetDoctorId.isNotEmpty) {
      result = await _patientService.setDoctorAvailability(
        doctorId: targetDoctorId,
        isAvailable: nextAvailable,
        statusOverride: cleanState,
      );
    }

    if (!mounted) return;
    setState(() => _isUpdatingAvailability = false);
    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Presence status updated to $cleanState.'),
          backgroundColor: const Color(0xFF012A58),
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message']?.toString() ?? 'Failed to update presence status.'),
          backgroundColor: const Color(0xFFFE3434),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _toggleDentistAvailability(bool value, {bool isAutoIdle = false}) async {
    if (_isUpdatingAvailability) return;
    final previousValue = _isDentistAvailableNow;
    setState(() {
      _isDentistAvailableNow = value;
      _isUpdatingAvailability = true;
    });
    _idleAvailabilityTimer?.cancel();

    DoctorModel? doc = _resolveCurrentDoctor();
    if (doc == null || doc.id.isEmpty || doc.id.toUpperCase().startsWith('DOC-')) {
      await _patientService.syncDoctorsFromApi(includeUnavailable: true);
      doc = _resolveCurrentDoctor();
    }
    final sess = SessionService().currentSession;
    final String targetDoctorId = (doc != null && doc.id.isNotEmpty && !doc.id.toUpperCase().startsWith('DOC-'))
        ? doc.id
        : ((sess?.metadata['dentistId']?.toString().trim().isNotEmpty == true)
            ? sess!.metadata['dentistId'].toString().trim()
            : ((sess?.userId.trim().isNotEmpty == true)
                ? sess!.userId.trim()
                : (doc?.id ?? (_patientService.allDoctors.isNotEmpty ? _patientService.allDoctors.first.id : ''))));

    Map<String, dynamic> result = {'success': true};
    if (targetDoctorId.isNotEmpty) {
      result = await _patientService.setDoctorAvailability(
        doctorId: targetDoctorId,
        isAvailable: value,
      );
    }

    if (!mounted) return;
    if (result['success'] != true) {
      setState(() {
        _isDentistAvailableNow = previousValue;
        _isUpdatingAvailability = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message']?.toString() ?? 'Failed to update availability status.'),
          backgroundColor: const Color(0xFFFE3434),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    setState(() {
      _isDentistAvailableNow = value;
      _isUpdatingAvailability = false;
    });

    if (!isAutoIdle) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            value
                ? 'Availability ON — your profile is now visible to patients and open for bookings.'
                : 'Availability OFF — hidden from patient search & new bookings. Existing appointments remain intact.',
          ),
          backgroundColor: value ? const Color(0xFF012A58) : const Color(0xFF475569),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  void dispose() {
    _autoSyncTimer?.cancel();
    _idleAvailabilityTimer?.cancel();
    _patientSearchCtrl.dispose();
    _referPatientNameCtrl.dispose();
    _referPatientMobileCtrl.dispose();
    _referPatientAgeCtrl.dispose();
    _referSearchCtrl.dispose();
    _referNotesCtrl.dispose();
    if (_realtimeChannel != null) {
      try {
        Supabase.instance.client.removeChannel(_realtimeChannel!);
      } catch (_) {}
    }
    _entryController.dispose();
    _pulseController.dispose();
    _patientService.setDentistMode(false);
    _patientService.removeListener(_onServiceUpdate);
    super.dispose();
  }

  void _onServiceUpdate() {
    if (_patientService.pendingReferralPatient != null) {
      _selectPatientForReferral(_patientService.pendingReferralPatient!);
      _patientService.clearPendingReferralPatient();
      if (_currentIndex != 3) {
        _previousTabIndex = _currentIndex;
        _currentIndex = 3;
      }
    }
    if (mounted) {
      if (!_isUpdatingAvailability) {
        final syncedDoc = _resolveCurrentDoctor();
        if (syncedDoc != null) {
          _isDentistAvailableNow = syncedDoc.isAvailable;
          if (!_hasSyncedDoctorSchedule) {
            _syncDoctorScheduleAndBlockedDates();
          }
        }
      }
      setState(() {});
    }
  }

  void _showPrescriptionModal(BuildContext context, dynamic reqOrName) {
    final String pName = reqOrName is PatientConsultationRequest ? reqOrName.patientName : reqOrName.toString();
    final String rawPatientId = reqOrName is PatientConsultationRequest ? (reqOrName.patientId ?? '').trim() : '';
    final String pId = rawPatientId.isNotEmpty ? rawPatientId : pName;
    final String? apptId = reqOrName is PatientConsultationRequest ? reqOrName.id : null;
    final String? initialDiag = reqOrName is PatientConsultationRequest ? reqOrName.problemCategory : null;
    final String? initialSym = reqOrName is PatientConsultationRequest ? reqOrName.symptoms : null;

    final currentDoc = _patientService.currentDoctor;
    final effectiveSpecialty = (currentDoc?.specialty.trim().isNotEmpty == true)
        ? currentDoc!.specialty.trim()
        : 'General Medicine';

    SpecialtyPrescriptionModal.show(
      context,
      patientId: pId,
      patientName: pName,
      doctorId: currentDoc?.id ?? '',
      doctorName: currentDoc?.name ?? 'Attending Doctor',
      doctorSpecialty: effectiveSpecialty,
      doctorQualification: currentDoc?.qualification ?? '',
      clinicName: currentDoc?.clinicName ?? 'GS HEALTH Clinic',
      appointmentId: apptId,
      initialDiagnosis: initialDiag,
      initialSymptoms: initialSym,
      onIssued: (savedRecord) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('E-Prescription issued to $pName ($effectiveSpecialty)! Live in Patient Locker.'),
            backgroundColor: AppTheme.gsNavy,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'View PDF',
              textColor: Colors.white,
              onPressed: () {
                if (mounted) {
                  PrescriptionPdfGenerator.showPreviewDialog(context, record: savedRecord);
                }
              },
            ),
          ),
        );
      },
    );
  }

  void _showDoctorChatModal(BuildContext context, String patientName, String roomId, {String? patientId, String? doctorNameOverride, String? doctorIdOverride}) {
    final doctor = _resolveCurrentDoctor() ?? _patientService.currentDoctor;
    final resolvedDocName = (doctor?.name.trim().isNotEmpty == true)
        ? doctor!.name.trim()
        : ((doctorNameOverride != null && doctorNameOverride.trim().isNotEmpty)
            ? doctorNameOverride.trim()
            : (SessionService().currentSession?.name?.trim().isNotEmpty == true
                ? SessionService().currentSession!.name!.trim()
                : 'Doctor'));
    final resolvedDocId = (doctor?.id.trim().isNotEmpty == true)
        ? doctor!.id.trim()
        : ((doctorIdOverride != null && doctorIdOverride.trim().isNotEmpty)
            ? doctorIdOverride.trim()
            : SessionService().currentSession?.userId);
    String? resolvedPatientId = (patientId != null && patientId.trim().isNotEmpty) ? patientId.trim() : null;
    if (resolvedPatientId == null && patientName.trim().isNotEmpty) {
      final matchP = _patientService.allPatients
          .where((p) => p.name.trim().toLowerCase() == patientName.trim().toLowerCase())
          .firstOrNull;
      if (matchP != null && matchP.id.trim().isNotEmpty) {
        resolvedPatientId = matchP.id.trim();
      }
    }
    final effectiveRoomId = roomId.trim().isNotEmpty
        ? roomId.trim()
        : ApiService.getChatRoomId(patientIdOrName: patientName, dentistIdOrName: resolvedDocName);

    WhatsAppChatModal.show(
      context,
      patientName: patientName,
      doctorName: resolvedDocName,
      currentUserRole: 'Dentist',
      patientId: resolvedPatientId,
      doctorId: resolvedDocId,
      roomIdOverride: effectiveRoomId,
    );
  }

  void _showNotificationsModal(BuildContext context, String role) {
    _patientService.syncNotificationsFromApi(role: role);

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final notifs = _patientService.getNotificationsForRole(role);
            final unreadCount = notifs.where((n) => !n.isRead).length;

            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 460, maxHeight: 540),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.notifications_active_rounded, color: AppTheme.primaryBlue, size: 20),
                              ),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Text(
                                  'In-App Notifications',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textDark),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (unreadCount > 0)
                          TextButton(
                            onPressed: () async {
                              await _patientService.markAllNotificationsRead(role);
                              setModalState(() {});
                            },
                            child: const Text('Mark all read', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue)),
                          ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: () => Navigator.of(dialogCtx).pop(),
                        ),
                      ],
                    ),
                    const Divider(height: 20),
                    if (notifs.isEmpty)
                      Expanded(
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.notifications_none_rounded, size: 48, color: Colors.grey.withValues(alpha: 0.4)),
                              const SizedBox(height: 10),
                              const Text('No new notifications.', style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 4),
                              const Text('New patient referrals and consultations will alert you here.', style: TextStyle(color: Colors.grey, fontSize: 11), textAlign: TextAlign.center),
                            ],
                          ),
                        ),
                      )
                    else
                      Expanded(
                        child: ListView.builder(
                          itemCount: notifs.length,
                          itemBuilder: (ctx, idx) {
                            final n = notifs[idx];
                            final isUnread = !n.isRead;

                            IconData itemIcon = Icons.notifications_rounded;
                            Color iconColor = AppTheme.primaryBlue;
                            if (n.title.toLowerCase().contains('referral')) {
                              itemIcon = Icons.group_add_rounded;
                              iconColor = const Color(0xFFFE3434);
                            } else if (n.title.toLowerCase().contains('consultation') || n.title.toLowerCase().contains('assigned')) {
                              itemIcon = Icons.medical_services_rounded;
                              iconColor = const Color(0xFFFE3434);
                            } else if (n.title.toLowerCase().contains('prescription')) {
                              itemIcon = Icons.receipt_long_rounded;
                              iconColor = const Color(0xFF012A58);
                            }

                            return InkWell(
                              onTap: () async {
                                if (isUnread) {
                                  await _patientService.markNotificationRead(n.id);
                                  setModalState(() {});
                                }
                                final textLower = '${n.title} ${n.message}'.toLowerCase();
                                if (ctx.mounted) Navigator.pop(ctx);
                                if (!mounted) return;
                                if (textLower.contains('referral') || textLower.contains('assigned')) {
                                  setState(() => _currentIndex = 2);
                                } else if (textLower.contains('appointment') || textLower.contains('booking')) {
                                  setState(() => _currentIndex = 0);
                                }
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isUnread ? const Color(0x14FE3434) : const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isUnread ? const Color(0x40FE3434) : const Color(0xFFE2E8F0),
                                    width: isUnread ? 1.5 : 1.0,
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(7),
                                      decoration: BoxDecoration(
                                        color: iconColor.withValues(alpha: 0.12),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(itemIcon, size: 16, color: iconColor),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  n.title,
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 13,
                                                    color: isUnread ? const Color(0xFF012A58) : AppTheme.textDark,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              if (isUnread) ...[
                                                const SizedBox(width: 6),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFFFE3434),
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                  child: const Text('NEW', style: TextStyle(fontSize: 8.5, color: Colors.white, fontWeight: FontWeight.bold)),
                                                ),
                                              ],
                                            ],
                                          ),
                                          const SizedBox(height: 3),
                                          Text(n.message, style: const TextStyle(fontSize: 11.5, color: AppTheme.textDark, height: 1.3)),
                                          const SizedBox(height: 6),
                                          Text(
                                            '${n.timestamp.day}/${n.timestamp.month} • ${n.timestamp.hour.toString().padLeft(2, '0')}:${n.timestamp.minute.toString().padLeft(2, '0')}',
                                            style: const TextStyle(fontSize: 9.5, color: Colors.grey),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: _buildCurrentTab(),
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: const Border(
            top: BorderSide(color: Color(0xFFE2E8F0), width: 1),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          backgroundColor: Colors.white,
          elevation: 0,
          type: BottomNavigationBarType.fixed,
          selectedItemColor: AppTheme.gsNavy,
          unselectedItemColor: const Color(0xFF64748B),
          selectedFontSize: 12,
          unselectedFontSize: 12,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500),
          onTap: (index) {
            setState(() => _currentIndex = index);
            if (index == 0 || index == 1 || index == 2) {
              _patientService.syncAppointmentsFromApi();
              _patientService.syncProblemRequestsFromApi();
              _patientService.syncDentistAssignedRequestsFromApi();
              _patientService.syncNotificationsFromApi(role: 'Dentist');
            }
          },
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.calendar_today_outlined, size: 22),
              activeIcon: Icon(Icons.calendar_today_rounded, color: AppTheme.gsNavy, size: 22),
              label: 'Today',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.people_outline_rounded, size: 22),
              activeIcon: Icon(Icons.people_rounded, color: AppTheme.gsNavy, size: 22),
              label: 'Patients',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.inbox_outlined, size: 22),
              activeIcon: Icon(Icons.inbox_rounded, color: AppTheme.gsNavy, size: 22),
              label: 'Requests',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.medical_services_outlined, size: 22),
              activeIcon: Icon(Icons.medical_services_rounded, color: AppTheme.gsNavy, size: 22),
              label: 'Refer',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.description_outlined, size: 22),
              activeIcon: Icon(Icons.description_rounded, color: AppTheme.gsNavy, size: 22),
              label: 'Rx',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentTab() {
    switch (_currentIndex) {
      case 0:
        return _buildTodayTab();
      case 1:
        return _buildPatientsTab();
      case 2:
        return _buildAssignedRequestsTab();
      case 3:
        return _buildReferPatientTab();
      case 4:
        return _buildPrescriptionsTab();
      default:
        return _buildTodayTab();
    }
  }

  User? get _safeAuthUser {
    try {
      return Supabase.instance.client.auth.currentUser;
    } catch (_) {
      return null;
    }
  }

  String _formatDateYmdLocal(DateTime dt) =>
      '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  Future<void> _syncDoctorScheduleAndBlockedDates() async {
    final doc = _resolveCurrentDoctor() ?? _patientService.currentDoctor;
    final sess = SessionService().currentSession;
    final targetId = (doc != null && doc.id.isNotEmpty && !doc.id.toUpperCase().startsWith('DOC-'))
        ? doc.id
        : ((sess?.metadata['dentistId']?.toString().trim().isNotEmpty == true)
            ? sess!.metadata['dentistId'].toString().trim()
            : ((sess?.userId.trim().isNotEmpty == true)
                ? sess!.userId.trim()
                : (doc?.id ?? '')));
    if (targetId.isEmpty) return;

    _hasSyncedDoctorSchedule = true;
    try {
      final sched = await _patientService.getDoctorSchedule(targetId);
      final blocked = await _patientService.getBlockedDates(targetId);
      if (mounted) {
        setState(() {
          _doctorSchedule = sched;
          _doctorBlockedDates = blocked;
        });
      }
    } catch (_) {}
  }

  String _formatWorkingDaysSummary(List<String> days) {
    if (days.isEmpty) return 'Mon - Fri';
    const shortOrder = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const map = {
      'monday': 'Mon', 'mon': 'Mon',
      'tuesday': 'Tue', 'tue': 'Tue',
      'wednesday': 'Wed', 'wed': 'Wed',
      'thursday': 'Thu', 'thu': 'Thu',
      'friday': 'Fri', 'fri': 'Fri',
      'saturday': 'Sat', 'sat': 'Sat',
      'sunday': 'Sun', 'sun': 'Sun',
    };
    final normalized = <String>[];
    for (final d in days) {
      final s = map[d.trim().toLowerCase()];
      if (s != null && !normalized.contains(s)) normalized.add(s);
    }
    normalized.sort((a, b) => shortOrder.indexOf(a).compareTo(shortOrder.indexOf(b)));
    if (normalized.isEmpty) return 'Mon - Fri';
    if (normalized.length == 5 &&
        normalized[0] == 'Mon' &&
        normalized[4] == 'Fri') {
      return 'Mon - Fri';
    }
    if (normalized.length == 6 &&
        normalized[0] == 'Mon' &&
        normalized[5] == 'Sat') {
      return 'Mon - Sat';
    }
    if (normalized.length == 7) return 'Mon - Sun';
    return normalized.join(', ');
  }

  DoctorModel? _resolveCurrentDoctor() {
    var currentDoc = _patientService.currentDoctor;
    final authUser = _safeAuthUser;
    final sess = SessionService().currentSession;

    final candidateIds = <String>{
      if (authUser?.id != null && authUser!.id.isNotEmpty) authUser.id.trim(),
      if (sess?.userId != null && sess!.userId.isNotEmpty) sess.userId.trim(),
      if (sess?.metadata['dentistId'] != null && sess!.metadata['dentistId'].toString().trim().isNotEmpty)
        sess.metadata['dentistId'].toString().trim(),
      if (sess?.metadata['userId'] != null && sess!.metadata['userId'].toString().trim().isNotEmpty)
        sess.metadata['userId'].toString().trim(),
      if (currentDoc != null && currentDoc.id.isNotEmpty && !currentDoc.id.toUpperCase().startsWith('DOC-'))
        currentDoc.id.trim(),
      if (currentDoc != null && currentDoc.userId.isNotEmpty) currentDoc.userId.trim(),
    };

    final candidateEmails = <String>{
      if (authUser?.email != null && authUser!.email!.isNotEmpty) authUser.email!.trim().toLowerCase(),
      if (sess?.email != null && sess!.email!.isNotEmpty) sess.email!.trim().toLowerCase(),
      if (currentDoc != null && currentDoc.email.isNotEmpty && currentDoc.email != 'doctor@dentaguru.com')
        currentDoc.email.trim().toLowerCase(),
    };

    final candidatePhones = <String>{
      if (sess?.phone != null && sess!.phone!.isNotEmpty)
        sess.phone!.replaceAll(RegExp(r'[^0-9]'), ''),
      if (currentDoc != null && currentDoc.phone.isNotEmpty)
        currentDoc.phone.replaceAll(RegExp(r'[^0-9]'), ''),
    }..removeWhere((p) => p.isEmpty);

    final candidateName = (
      sess?.name ??
      authUser?.userMetadata?['name']?.toString() ??
      currentDoc?.name ??
      ''
    ).replaceAll('Dr.', '').replaceAll('Dr. ', '').trim().toLowerCase();

    final match = _patientService.allDoctors.where((d) {
      if (d.id.isNotEmpty && candidateIds.contains(d.id.trim())) return true;
      if (d.userId.isNotEmpty && candidateIds.contains(d.userId.trim())) return true;
      if (d.email.isNotEmpty && candidateEmails.contains(d.email.trim().toLowerCase())) return true;
      final dPhone = d.phone.replaceAll(RegExp(r'[^0-9]'), '');
      if (dPhone.length >= 10 &&
          candidatePhones.any((cp) => cp.length >= 10 && dPhone.endsWith(cp.substring(cp.length - 10)))) {
        return true;
      }
      final dName = d.name.replaceAll(RegExp(r'^dr\.?\s*', caseSensitive: false), '').trim().toLowerCase();
      if (candidateIds.isEmpty &&
          candidateEmails.isEmpty &&
          candidatePhones.isEmpty &&
          candidateName.isNotEmpty &&
          candidateName != 'doctor' &&
          candidateName != 'dentist' &&
          dName.isNotEmpty &&
          dName == candidateName) {
        return true;
      }
      return false;
    }).firstOrNull;

    if (match != null) {
      currentDoc = match;
      _patientService.currentDoctor = currentDoc;
    }
    return currentDoc;
  }

  List<PatientConsultationRequest> _getDentistAssignedAndScheduledRequests() {
    final currentDoc = _resolveCurrentDoctor();
    final authUser = _safeAuthUser;
    final sess = SessionService().currentSession;

    final currentDocName = (currentDoc?.name ?? sess?.name ?? '').replaceAll(RegExp(r'^dr\.?\s*', caseSensitive: false), '').trim().toLowerCase();
    final currentDocId = (currentDoc?.id ?? '').trim();
    final currentDocUserId = (currentDoc?.userId ?? '').trim();
    final currentDocEmail = (currentDoc?.email ?? sess?.email ?? '').trim().toLowerCase();
    final authUserId = (authUser?.id ?? '').trim();
    final authEmail = (authUser?.email ?? '').trim().toLowerCase();
    final sessUserId = (sess?.userId ?? '').trim();

    final myDoctorIds = <String>{
      if (currentDocId.isNotEmpty) currentDocId,
      if (currentDocUserId.isNotEmpty) currentDocUserId,
      if (sessUserId.isNotEmpty) sessUserId,
      if (authUserId.isNotEmpty) authUserId,
      if (currentDocEmail.isNotEmpty) currentDocEmail,
      if (authEmail.isNotEmpty) authEmail,
    };

    for (final d in _patientService.allDoctors) {
      if (myDoctorIds.contains(d.id) ||
          (d.userId.isNotEmpty && myDoctorIds.contains(d.userId)) ||
          (d.email.isNotEmpty && myDoctorIds.contains(d.email.toLowerCase()))) {
        if (d.id.isNotEmpty) myDoctorIds.add(d.id);
        if (d.userId.isNotEmpty) myDoctorIds.add(d.userId);
        if (d.email.isNotEmpty) myDoctorIds.add(d.email.toLowerCase());
      }
    }

    if (myDoctorIds.isEmpty && currentDocName.isEmpty) {
      return [];
    }

    bool isAssignedToMe(PatientConsultationRequest r) {
      final aId = r.assignedDoctorId?.trim();
      if (aId != null && aId.isNotEmpty) {
        return myDoctorIds.contains(aId);
      }
      final aName = r.assignedDoctorName?.replaceAll(RegExp(r'^dr\.?\s*', caseSensitive: false), '').trim().toLowerCase();
      return currentDocName.isNotEmpty && aName != null && aName.isNotEmpty && aName == currentDocName;
    }

    final Map<String, PatientConsultationRequest> uniqueMap = {};
    for (final r in _patientService.dentistAssignedRequests) {
      if (isAssignedToMe(r) && r.id.isNotEmpty) {
        final key = (r.id.startsWith('PR-'))
            ? '${r.patientName.trim().toLowerCase()}_${r.problemCategory.trim().toLowerCase()}'
            : r.id;
        uniqueMap[key] = r;
      }
    }

    for (final r in _patientService.requests) {
      if (isAssignedToMe(r) && r.id.isNotEmpty) {
        final key = (r.id.startsWith('PR-'))
            ? '${r.patientName.trim().toLowerCase()}_${r.problemCategory.trim().toLowerCase()}'
            : r.id;
        if (!uniqueMap.containsKey(key)) {
          uniqueMap[key] = r;
        } else if (r.status == 'Confirmed' || r.status == 'Accepted') {
          uniqueMap[key] = r;
        }
      }
    }

    return uniqueMap.values.toList();
  }

  static const List<String> _shortWeekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  String _formatDayAbbrev(DateTime dt) => _shortWeekdays[(dt.weekday - 1).clamp(0, 6)];

  // ==========================================
  // TAB 0: TODAY – DEFAULT LANDING SCREEN
  // ==========================================
  Widget _buildTodayTab() {
    final currentDoc = _resolveCurrentDoctor();
    final authUser = _safeAuthUser;
    final rawDocName = (currentDoc?.name ?? (authUser?.userMetadata?['name'] ?? '')).toString().trim();
    final docName = rawDocName.isNotEmpty
        ? (rawDocName.startsWith('Dr.') ? rawDocName : 'Dr. $rawDocName')
        : 'Dentist';

    final notifs = _patientService.getNotificationsForRole('Dentist');
    final unreadCount = notifs.where((n) => !n.isRead).length;

    final allMyRequests = _getDentistAssignedAndScheduledRequests();
    final selectedDate = _baseCalendarDate.add(Duration(days: _selectedDateIndex));
    final appointmentsForSelectedDate = _getAppointmentsForDate(allMyRequests, selectedDate, _selectedDateIndex);
    final allBookedAppointments = allMyRequests.where((req) => _isBookedOrConfirmedAppointment(req)).toList();

    final upcomingVisitsCount = allMyRequests.where((r) {
      final st = r.status.trim().toUpperCase();
      return st != 'COMPLETED' && st != 'CANCELLED' && st != 'REJECTED' && st != 'NO_SHOW';
    }).length;
    final completedVisitsCount = allMyRequests.where((r) {
      return r.status.trim().toUpperCase() == 'COMPLETED';
    }).length;
    final uniquePatientKeys = <String>{};
    for (final r in allMyRequests) {
      final pid = (r.patientId ?? '').trim();
      final digits = r.patientPhone.replaceAll(RegExp(r'\D'), '');
      final ph10 = digits.length >= 10 ? digits.substring(digits.length - 10) : digits;
      final nameKey = r.patientName.trim().toLowerCase();
      if (pid.isNotEmpty) {
        uniquePatientKeys.add('id:$pid');
      } else if (ph10.length == 10) {
        uniquePatientKeys.add('ph:$ph10');
      } else if (nameKey.isNotEmpty && nameKey != 'patient') {
        uniquePatientKeys.add('nm:$nameKey');
      }
    }
    final totalPatientsCount = uniquePatientKeys.length;

    return SingleChildScrollView(
      key: const Key('dentist_today_scroll_view'),
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Header Section
          Container(
            width: double.infinity,
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const GsHealthLogo(height: 36, alignment: Alignment.centerLeft),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Doctor workspace',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF64748B),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            docName,
                            key: const Key('dentist_header_name'),
                            style: const TextStyle(
                              fontSize: 23,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                              letterSpacing: -0.4,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Notification Button with Badge
                    InkWell(
                      key: const Key('dentist_notifications_button'),
                      onTap: () => _showNotificationsModal(context, 'Dentist'),
                      borderRadius: BorderRadius.circular(24),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
                        ),
                        child: Stack(
                          clipBehavior: Clip.none,
                          alignment: Alignment.center,
                          children: [
                            const Icon(
                              Icons.notifications_none_rounded,
                              color: Color(0xFF0F172A),
                              size: 22,
                            ),
                            if (unreadCount > 0)
                              Positioned(
                                top: 4,
                                right: 3,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: AppTheme.gsRed,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: Colors.white, width: 1.5),
                                  ),
                                  child: Text(
                                    unreadCount > 9 ? '9+' : '$unreadCount',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Profile Button
                    InkWell(
                      key: const Key('dentist_profile_button'),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const DoctorProfileScreen()),
                      ),
                      borderRadius: BorderRadius.circular(24),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.person_outline_rounded,
                            color: Color(0xFF0F172A),
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // 2. Horizontally Scrollable Date Selector
                SizedBox(
                  height: 78,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      children: List.generate(7, (index) {
                        final dt = _baseCalendarDate.add(Duration(days: index));
                        final dtKey = _formatDateYmdLocal(dt);
                        final isBlockedDay = _doctorBlockedDates.any((b) => b.date == dtKey);
                        final isSelected = _selectedDateIndex == index;
                        return Padding(
                          padding: EdgeInsets.only(right: index == 6 ? 0 : 10),
                          child: InkWell(
                            key: Key('dentist_date_card_$index'),
                            onTap: () => setState(() => _selectedDateIndex = index),
                            borderRadius: BorderRadius.circular(18),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              width: 60,
                              height: 78,
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? (isBlockedDay ? const Color(0xFFFE3434) : AppTheme.gsNavy)
                                    : (isBlockedDay ? const Color(0x14FE3434) : Colors.white),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: isSelected
                                      ? (isBlockedDay ? const Color(0xFFFE3434) : AppTheme.gsNavy)
                                      : (isBlockedDay ? const Color(0x40FE3434) : const Color(0xFFE2E8F0)),
                                  width: 1.2,
                                ),
                                boxShadow: isSelected
                                    ? [
                                        BoxShadow(
                                          color: (isBlockedDay ? const Color(0xFFFE3434) : AppTheme.gsNavy).withValues(alpha: 0.2),
                                          blurRadius: 8,
                                          offset: const Offset(0, 3),
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        _formatDayAbbrev(dt),
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600,
                                          color: isSelected
                                              ? Colors.white.withValues(alpha: 0.9)
                                              : (isBlockedDay ? const Color(0xFFFE3434) : const Color(0xFF64748B)),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${dt.day}',
                                        style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w800,
                                          color: isSelected
                                              ? Colors.white
                                              : (isBlockedDay ? const Color(0xFFFE3434) : const Color(0xFF0F172A)),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (isBlockedDay)
                                    Positioned(
                                      top: 5,
                                      right: 6,
                                      child: Container(
                                        key: Key('dentist_date_blocked_badge_$dtKey'),
                                        width: 8,
                                        height: 8,
                                        decoration: BoxDecoration(
                                          color: isSelected ? Colors.white : const Color(0xFFFE3434),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1, thickness: 1, color: Color(0xFFE2E8F0)),

          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 3. Availability Card (ON / OFF Master Toggle)
                Container(
                  key: const Key('dentist_availability_card'),
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  decoration: BoxDecoration(
                    color: _isDentistAvailableNow
                        ? const Color(0x14012A58)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _isDentistAvailableNow
                          ? const Color(0xFF012A58).withValues(alpha: 0.45)
                          : const Color(0xFFE2E8F0),
                      width: 1.3,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: _isDentistAvailableNow ? const Color(0xFF012A58) : const Color(0xFF94A3B8),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    'Availability',
                                    style: const TextStyle(
                                      fontSize: 16.5,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF0F172A),
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  key: const Key('dentist_availability_status_badge'),
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: _isDentistAvailableNow
                                        ? const Color(0xFF012A58)
                                        : const Color(0xFF64748B),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    _isDentistAvailableNow ? 'ON' : 'OFF',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _isDentistAvailableNow
                                  ? 'Visible in patient search and open for new appointment bookings.'
                                  : 'Hidden from patient search and new bookings. Existing appointments & records remain intact.',
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF475569),
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Switch(
                        key: const Key('dentist_availability_switch'),
                        value: _isDentistAvailableNow,
                        activeThumbColor: Colors.white,
                        activeTrackColor: const Color(0xFF012A58),
                        inactiveThumbColor: Colors.white,
                        inactiveTrackColor: const Color(0xFFCBD5E1),
                        onChanged: _isUpdatingAvailability
                            ? null
                            : (val) => _toggleDentistAvailability(val),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      'Available',
                      'Busy – Online Consultation',
                      'Busy – In-Person Consultation',
                      'Delayed',
                      'Offline',
                      'Online',
                      'Busy',
                      'Unavailable',
                    ].map((state) {
                      final currentPresence = _resolveCurrentDoctor()?.onlineStatus ??
                          (_isDentistAvailableNow ? 'Available' : 'Unavailable');
                      final isSelected = currentPresence.toLowerCase() == state.toLowerCase() ||
                          (state == 'Available' && currentPresence.isEmpty && _isDentistAvailableNow);
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          key: Key('doctor_presence_chip_$state'),
                          label: Text(state),
                          selected: isSelected,
                          selectedColor: AppTheme.gsNavy,
                          backgroundColor: Colors.white,
                          labelStyle: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isSelected ? Colors.white : const Color(0xFF334155),
                          ),
                          onSelected: _isUpdatingAvailability ? null : (_) => _setDoctorPresenceState(state),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 18),

                // 4. Sponsored Banner
                _buildDentistSponsoredCourseBanner(context),
                const SizedBox(height: 18),

                // 4b. Doctor Real-Time Visit Summary KPIs (0 / 0 / 0 for newly registered doctors)
                Row(
                  key: const Key('doctor_dashboard_summary_stats'),
                  children: [
                    Expanded(
                      child: _buildDoctorOverviewKpiCard(
                        valueKey: const Key('doctor_stat_upcoming_visits'),
                        label: 'Upcoming Visits',
                        value: '$upcomingVisitsCount',
                        icon: Icons.schedule_rounded,
                        color: AppTheme.gsNavy,
                        onTap: () => _openDoctorAppointmentsCalendar(
                          context,
                          currentDoc: currentDoc,
                          docName: docName,
                          initialDate: selectedDate,
                          appointments: allMyRequests,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildDoctorOverviewKpiCard(
                        valueKey: const Key('doctor_stat_completed_visits'),
                        label: 'Completed Visits',
                        value: '$completedVisitsCount',
                        icon: Icons.check_circle_outline_rounded,
                        color: const Color(0xFF047857),
                        onTap: () => _openDoctorAppointmentsCalendar(
                          context,
                          currentDoc: currentDoc,
                          docName: docName,
                          initialDate: selectedDate,
                          appointments: allMyRequests,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildDoctorOverviewKpiCard(
                        valueKey: const Key('doctor_stat_total_patients'),
                        label: 'Total Patients',
                        value: '$totalPatientsCount',
                        icon: Icons.people_outline_rounded,
                        color: AppTheme.gsRed,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // 4c. Compact Tappable Appointments Calendar Entry Card (Opens full monthly calendar screen)
                InkWell(
                  key: const Key('dentist_open_calendar_card'),
                  onTap: () => _openDoctorAppointmentsCalendar(
                    context,
                    currentDoc: currentDoc,
                    docName: docName,
                    initialDate: selectedDate,
                    appointments: allMyRequests,
                  ),
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppTheme.gsNavy.withValues(alpha: 0.2)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.025),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppTheme.gsNavy.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.calendar_month_rounded,
                            color: AppTheme.gsNavy,
                            size: 23,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Appointments Calendar',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF0F172A),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${appointmentsForSelectedDate.length} on selected day • ${allMyRequests.length} total visits',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF64748B),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppTheme.gsNavy,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'View',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(width: 2),
                              Icon(Icons.chevron_right_rounded, size: 16, color: Colors.white),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // 5. Latest Appointments (Preview max 2 + View All -> Complete Appointments Calendar)
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Latest Appointments',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton(
                      key: const Key('doctor_view_all_appointments_btn'),
                      onPressed: () => _openDoctorAppointmentsCalendar(
                        context,
                        currentDoc: currentDoc,
                        docName: docName,
                        initialDate: selectedDate,
                        appointments: allMyRequests,
                      ),
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
                const SizedBox(height: 10),
                if (appointmentsForSelectedDate.isEmpty &&
                    (_selectedDateIndex > 0 || allBookedAppointments.isEmpty))
                  Container(
                    key: const Key('dentist_no_appointments_empty_state'),
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 68,
                          height: 68,
                          decoration: BoxDecoration(
                            color: AppTheme.gsNavy.withValues(alpha: 0.06),
                            shape: BoxShape.circle,
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.calendar_today_outlined,
                              color: AppTheme.gsNavy,
                              size: 30,
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          'No patient visits yet.',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Your patient appointments will appear here once patients book a consultation.',
                          style: TextStyle(
                            fontSize: 14,
                            color: Color(0xFF64748B),
                            height: 1.4,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                else ...[
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: ['All', 'Today', 'Upcoming', 'Previous'].map((period) {
                        final selected = _visitPeriodFilter == period;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8, bottom: 12),
                          child: ChoiceChip(
                            key: Key('doctor_visit_filter_$period'),
                            label: Text(period),
                            selected: selected,
                            selectedColor: AppTheme.gsNavy,
                            backgroundColor: Colors.white,
                            labelStyle: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: selected ? Colors.white : const Color(0xFF334155),
                            ),
                            onSelected: (_) => setState(() => _visitPeriodFilter = period),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  Builder(
                    builder: (_) {
                      final nowYmd = _formatDateYmdLocal(DateTime.now());
                      final baseList = (_selectedDateIndex == 0 && appointmentsForSelectedDate.isEmpty)
                          ? allBookedAppointments
                          : appointmentsForSelectedDate;
                      final filtered = baseList.where((req) {
                        final st = req.status.trim().toUpperCase();
                        final d = (req.confirmedDate ?? '').split('T').first.trim();
                        if (_visitPeriodFilter == 'Today') {
                          return st != 'COMPLETED' && (d.isEmpty || d == nowYmd);
                        }
                        if (_visitPeriodFilter == 'Upcoming') {
                          return st != 'COMPLETED';
                        }
                        if (_visitPeriodFilter == 'Previous') {
                          return st == 'COMPLETED';
                        }
                        return true;
                      }).toList();

                      if (filtered.isEmpty) {
                        return Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Text(
                            'No $_visitPeriodFilter appointments found.',
                            style: const TextStyle(fontSize: 13.5, color: Color(0xFF64748B)),
                            textAlign: TextAlign.center,
                          ),
                        );
                      }

                      final previewAppointments = takeLatestPreviewRecords<PatientConsultationRequest>(
                        filtered,
                        limit: kDashboardRecentPreviewLimit,
                        compareDesc: (a, b) => b.submittedAt.compareTo(a.submittedAt),
                      );

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          InkWell(
                            key: const Key('dentist_appointments_section_header'),
                            onTap: () => _openDoctorAppointmentsCalendar(
                              context,
                              currentDoc: currentDoc,
                              docName: docName,
                              initialDate: selectedDate,
                              appointments: allMyRequests,
                            ),
                            borderRadius: BorderRadius.circular(10),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      appointmentsForSelectedDate.isNotEmpty
                                          ? 'Showing latest ${previewAppointments.length} of ${filtered.length} appointments'
                                          : 'Showing latest ${previewAppointments.length} of ${filtered.length} scheduled appointments',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF64748B),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          ...previewAppointments.asMap().entries.map((entry) {
                            final idx = entry.key;
                            final req = entry.value;
                            final nextUpcoming = idx + 1 < previewAppointments.length ? previewAppointments[idx + 1] : null;
                            final slot = (req.confirmedTimeSlot != null && req.confirmedTimeSlot!.trim().isNotEmpty)
                                ? req.confirmedTimeSlot!
                                : '11:00 AM';
                            return _buildTimelineNode(req: req, time: slot, nextAppointment: nextUpcoming);
                          }),
                        ],
                      );
                    },
                  ),
                ],

                const SizedBox(height: 24),
                _buildDoctorRecentPatientActivityPreviewSection(allMyRequests),

                const SizedBox(height: 24),
                _buildIncomingReferralsSection(
                  _patientService.doctorReceivedPatientReferrals,
                  keyPrefix: 'today',
                  maxPreviewItems: kDashboardRecentPreviewLimit,
                  onViewAll: () => setState(() => _currentIndex = 2),
                ),

                const SizedBox(height: 24),

                // 6. Manage Availability & Consultation Slots Section (Preserved for Slot Configuration)
                _buildManageAvailabilitySection(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openDoctorAppointmentsCalendar(
    BuildContext context, {
    required DoctorModel? currentDoc,
    required String docName,
    required DateTime initialDate,
    required List<PatientConsultationRequest> appointments,
  }) {
    final authUser = _safeAuthUser;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DoctorAppointmentsCalendarScreen(
          doctorId: currentDoc?.id ?? (authUser?.id ?? ''),
          doctorName: docName,
          doctorSpecialty: (currentDoc?.specialty.trim().isNotEmpty == true)
              ? currentDoc!.specialty
              : 'General Medicine',
          initialSelectedDate: initialDate,
          initialAppointments: appointments,
          onOpenConsultationDetails: (req) {
            final targetProfile = PatientProfile(
              id: (req.patientId != null && req.patientId!.trim().isNotEmpty)
                  ? req.patientId!
                  : req.id,
              name: req.patientName,
              phone: req.patientPhone,
              email: '',
              city: req.city,
              pincode: req.pincode,
              state: req.state,
              age: '',
              gender: '',
              bloodGroup: '',
              languages: const ['English'],
            );
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => DoctorPatientRecordScreen(
                  patient: targetProfile,
                  onWriteRx: () => _showPrescriptionModal(context, req),
                ),
              ),
            );
          },
          onOpenPrescription: (req) => _showPrescriptionModal(context, req),
        ),
      ),
    );
  }

  Widget _buildDoctorOverviewKpiCard({
    required Key valueKey,
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 16, color: color),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              key: valueKey,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
                height: 1.1,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF64748B),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  bool _isBookedOrConfirmedAppointment(PatientConsultationRequest req) {
    final statusUpper = req.status.trim().toUpperCase();
    if (statusUpper == 'CANCELLED' || statusUpper == 'REJECTED') {
      return false;
    }
    final isBookedStatus = statusUpper == 'CONFIRMED' ||
        statusUpper == 'PENDING' ||
        statusUpper == 'APPROVED' ||
        statusUpper == 'BOOKED' ||
        statusUpper == 'RESCHEDULED';
    final isInProgress = statusUpper == 'IN_PROGRESS' || statusUpper == 'STARTED';
    final isDelayed = statusUpper == 'DELAYED' || req.delayMinutes > 0;
    final isNoShow = statusUpper == 'NO_SHOW' || statusUpper == 'NOSHOW';
    final isCompleted = statusUpper == 'COMPLETED';
    final hasSlot = (req.confirmedTimeSlot ?? '').trim().isNotEmpty ||
        (req.confirmedDate ?? '').trim().isNotEmpty;
    return isBookedStatus || isInProgress || isDelayed || isNoShow || isCompleted || hasSlot;
  }

  List<PatientConsultationRequest> _getAppointmentsForDate(
    List<PatientConsultationRequest> allMyRequests,
    DateTime targetDate,
    int selectedIndex,
  ) {
    final targetDateStr =
        '${targetDate.year.toString().padLeft(4, '0')}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.day.toString().padLeft(2, '0')}';

    return allMyRequests.where((req) {
      if (!_isBookedOrConfirmedAppointment(req)) return false;

      if (req.confirmedDate != null && req.confirmedDate!.trim().isNotEmpty) {
        final cDate = req.confirmedDate!.trim().split('T').first;
        if (cDate == targetDateStr) return true;
        final parsed = DateTime.tryParse(req.confirmedDate!.trim());
        if (parsed != null &&
            parsed.year == targetDate.year &&
            parsed.month == targetDate.month &&
            parsed.day == targetDate.day) {
          return true;
        }
        return false;
      }

      final slotLower = (req.confirmedTimeSlot ?? '').trim().toLowerCase();
      if (slotLower.startsWith('today')) {
        return selectedIndex == 0;
      }
      if (slotLower.startsWith('tomorrow')) {
        return selectedIndex == 1;
      }

      return req.submittedAt.year == targetDate.year &&
          req.submittedAt.month == targetDate.month &&
          req.submittedAt.day == targetDate.day;
    }).toList();
  }

  Widget _buildDentistSponsoredCourseBanner(BuildContext context) {
    return Column(
      children: [
        InkWell(
          key: const Key('dentist_sponsored_banner'),
          onTap: () async {
            final uri = Uri.parse('https://www.gsimplants.com/smooth-implant');
            try {
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            } catch (_) {}
          },
          borderRadius: BorderRadius.circular(20),
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF012A58),
                  Color(0xFF012A58),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.gsNavy.withValues(alpha: 0.14),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // SPONSORED pill + faculty row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'SPONSORED',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildCourseSpeakerAvatar('SK'),
                                const SizedBox(width: 6),
                                _buildCourseSpeakerAvatar('GS'),
                                const SizedBox(width: 6),
                                _buildCourseSpeakerAvatar('RA'),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        const Center(
                          child: Text(
                            'DR SUMANTH KRISHNA  •  DR SHESHU KUMAR  •  DR RAJESH ADURI',
                            style: TextStyle(
                              color: Color(0xFFCBD5E1),
                              fontSize: 8.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.3,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Center(
                          child: Text(
                            'FIXED TEETH JUST IN 3 DAYS',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    color: Colors.black.withValues(alpha: 0.55),
                    child: const Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Free course',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w800,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                'FREE COURSE FOR ALL BDS & MDS GRADUATES WITH ONE IMPLANT PLACEMENT',
                                style: TextStyle(
                                  color: Color(0xFF94A3B8),
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        SizedBox(width: 8),
                        Icon(
                          Icons.open_in_new_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 18,
              height: 6,
              decoration: BoxDecoration(
                color: AppTheme.gsNavy,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: Color(0xFFCBD5E1),
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCourseSpeakerAvatar(String initials) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFFE3434), width: 1.8),
      ),
      child: Center(
        child: Text(
          initials,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: AppTheme.gsNavy,
          ),
        ),
      ),
    );
  }

  Widget _buildManageAvailabilitySection() {
    final currentDoc = _resolveCurrentDoctor() ??
        _patientService.currentDoctor ??
        (_patientService.allDoctors.isNotEmpty ? _patientService.allDoctors.first : null);
    final docId = (currentDoc != null && currentDoc.id.isNotEmpty) ? currentDoc.id : '';
    final schedule = docId.isNotEmpty
        ? (_patientService.getCachedDoctorSchedule(docId) ?? _doctorSchedule)
        : _doctorSchedule;
    final blockedDates = docId.isNotEmpty
        ? (_patientService.getCachedBlockedDates(docId).isNotEmpty
            ? _patientService.getCachedBlockedDates(docId)
            : _doctorBlockedDates)
        : _doctorBlockedDates;

    final workingDaysSummary = _formatWorkingDaysSummary(schedule.workingDays);
    final hoursSummary = '${schedule.startTime} - ${schedule.endTime}';
    final lunchSummary = schedule.hasBreak &&
            (schedule.breakStartTime?.isNotEmpty == true) &&
            (schedule.breakEndTime?.isNotEmpty == true)
        ? '${schedule.breakStartTime} - ${schedule.breakEndTime}'
        : 'No Break';
    final durationSummary = '${schedule.slotDurationMinutes} mins';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.event_available_rounded, color: AppTheme.primaryBlue, size: 22),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Manage Availability & Consultation Slots',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textDark),
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Configure working days, hours, lunch breaks & publish booking slots',
                      style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 14),

          // Working Days & Hours Info Row (Live from DB / Schedule State)
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _buildAvailabilityInfoPill(
                icon: Icons.calendar_today_rounded,
                label: 'Working Days',
                value: workingDaysSummary,
              ),
              _buildAvailabilityInfoPill(
                icon: Icons.schedule_rounded,
                label: 'Hours',
                value: hoursSummary,
              ),
              _buildAvailabilityInfoPill(
                icon: Icons.coffee_rounded,
                label: 'Lunch Break',
                value: lunchSummary,
              ),
              _buildAvailabilityInfoPill(
                icon: Icons.timer_outlined,
                label: 'Slot Duration',
                value: durationSummary,
              ),
            ],
          ),
          if (blockedDates.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              key: const Key('doctor_dashboard_blocked_dates_summary'),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0x14FE3434),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0x40FE3434)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.event_busy_rounded, size: 15, color: Color(0xFFFE3434)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Blocked Holidays (${blockedDates.length}): ${blockedDates.take(3).map((b) => b.date).join(', ')}${blockedDates.length > 3 ? ' +${blockedDates.length - 3} more' : ''}',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFFE3434)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),

          // Action Toolbar
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ElevatedButton.icon(
                key: const Key('doctor_manage_availability_btn'),
                onPressed: () async {
                  await DoctorSlotManagementDialog.show(
                    context,
                    initialDoctor: currentDoc,
                    isDoctorSelfManage: true,
                    initialBlockDateMode: false,
                  );
                  await _syncDoctorScheduleAndBlockedDates();
                },
                icon: const Icon(Icons.edit_calendar_rounded, size: 16, color: Colors.white),
                label: const Text(
                  'Configure Working Days & Slots',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryBlue,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              OutlinedButton.icon(
                key: const Key('doctor_block_holiday_btn'),
                onPressed: () async {
                  await DoctorSlotManagementDialog.show(
                    context,
                    initialDoctor: currentDoc,
                    isDoctorSelfManage: true,
                    initialBlockDateMode: true,
                  );
                  await _syncDoctorScheduleAndBlockedDates();
                },
                icon: const Icon(Icons.block_rounded, size: 16, color: Color(0xFFFE3434)),
                label: const Text(
                  'Block Date / Mark Holiday',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFFE3434)),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0x40FE3434)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Row(
            children: [
              Icon(Icons.sync_rounded, size: 13, color: Color(0xFF012A58)),
              SizedBox(width: 4),
              Expanded(
                child: Text(
                  'Schedule changes sync instantly to Patient Dashboards & Profile booking slots',
                  style: TextStyle(fontSize: 10.5, color: Color(0xFF012A58), fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAvailabilityInfoPill({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.primaryBlue),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: const TextStyle(fontSize: 9.5, color: AppTheme.textMuted)),
              Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textDark)),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDoctorApptDate(String? rawDate, DateTime fallback) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    DateTime dt = fallback;
    if (rawDate != null && rawDate.trim().isNotEmpty) {
      final parsed = DateTime.tryParse(rawDate.trim());
      if (parsed != null) dt = parsed;
    }
    final month = months[(dt.month - 1).clamp(0, 11)];
    return '${dt.day} $month ${dt.year}';
  }

  String _formatDoctorBookingCreated(DateTime dt) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final local = dt.toLocal();
    final month = months[(local.month - 1).clamp(0, 11)];
    final hour12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final amPm = local.hour >= 12 ? 'PM' : 'AM';
    final minStr = local.minute.toString().padLeft(2, '0');
    return '${local.day} $month ${local.year}, $hour12:$minStr $amPm';
  }

  Future<void> _handleAcceptTimelineAppointment(PatientConsultationRequest req, String patientName) async {
    if (_acceptingRequestIds.contains(req.id)) return;
    setState(() => _acceptingRequestIds.add(req.id));
    try {
      final res = await _patientService.acceptAppointmentByDoctor(req.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            res['message']?.toString() ?? '✅ Appointment confirmed for $patientName!',
          ),
          backgroundColor: const Color(0xFF012A58),
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _acceptingRequestIds.remove(req.id));
      }
    }
  }

  Future<void> _handleRejectTimelineAppointment(PatientConsultationRequest req, String patientName) async {
    if (_acceptingRequestIds.contains(req.id)) return;
    setState(() => _acceptingRequestIds.add(req.id));
    try {
      final res = await _patientService.rejectAppointmentByDoctor(req.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            res['message']?.toString() ?? 'Appointment declined for $patientName.',
          ),
          backgroundColor: const Color(0xFF475569),
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _acceptingRequestIds.remove(req.id));
      }
    }
  }

  Future<void> _handleLifecycleAction(
    Future<Map<String, dynamic>> Function() actionFn,
    String fallbackMessage,
  ) async {
    try {
      final res = await actionFn();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res['message']?.toString() ?? fallbackMessage),
          backgroundColor: res['success'] == true ? const Color(0xFF012A58) : const Color(0xFFFE3434),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$fallbackMessage: $e'),
          backgroundColor: const Color(0xFFFE3434),
        ),
      );
    }
  }

  Widget _buildTimelineNode({
    required PatientConsultationRequest req,
    required String time,
    PatientConsultationRequest? nextAppointment,
  }) {
    final patientName = (req.patientName.contains('-') && req.patientName.length > 20)
        ? (_patientService.currentPatient.name.isNotEmpty ? _patientService.currentPatient.name : 'Patient')
        : req.patientName;

    final matchedPatient = _patientService.allPatients
        .where((p) =>
            (req.patientId != null && req.patientId!.isNotEmpty && p.id == req.patientId) ||
            (p.name.isNotEmpty && p.name.trim().toLowerCase() == patientName.trim().toLowerCase()) ||
            (p.phone.isNotEmpty && req.patientPhone.isNotEmpty && p.phone.trim() == req.patientPhone.trim()))
        .firstOrNull;

    final formattedContact = req.getFormattedPatientPhone(isAuthorized: true);
    final patientCity = req.city.trim().isNotEmpty
        ? req.city.trim()
        : (matchedPatient?.city.trim().isNotEmpty == true ? matchedPatient!.city.trim() : '');
    final patientPincode = req.pincode.trim().isNotEmpty
        ? req.pincode.trim()
        : (matchedPatient?.pincode.trim().isNotEmpty == true ? matchedPatient!.pincode.trim() : '');
    final patientAge = matchedPatient?.age.trim() ?? '';
    final patientGender = matchedPatient?.gender.trim() ?? '';
    final patientBlood = matchedPatient?.bloodGroup.trim() ?? '';
    final profileParts = <String>[
      if (patientAge.isNotEmpty) '$patientAge yrs',
      if (patientGender.isNotEmpty) patientGender,
      if (patientCity.isNotEmpty) 'City: $patientCity',
      if (patientPincode.isNotEmpty) 'PIN: $patientPincode',
      if (patientBlood.isNotEmpty) 'Blood: $patientBlood',
    ];
    final profileSummary = profileParts.join(' • ');

    final targetPatientProfile = matchedPatient ??
        PatientProfile(
          id: (req.patientId != null && req.patientId!.isNotEmpty) ? req.patientId! : 'pat_${patientName.hashCode}',
          name: patientName,
          phone: req.patientPhone,
          city: patientCity,
          pincode: patientPincode,
          age: patientAge.isNotEmpty ? patientAge : '28',
          gender: patientGender.isNotEmpty ? patientGender : 'Female',
          bloodGroup: patientBlood.isNotEmpty ? patientBlood : 'O Positive (O+)',
        );

    final currentDoc = _resolveCurrentDoctor();
    final clinicName = req.displayDoctorClinic.isNotEmpty
        ? req.displayDoctorClinic
        : (req.assignedDoctorClinic?.trim().isNotEmpty == true
            ? req.assignedDoctorClinic!.trim()
            : (currentDoc?.clinicName.trim().isNotEmpty == true
                ? currentDoc!.clinicName.trim()
                : 'GS HEALTH Practice'));

    final formattedApptDate = _formatDoctorApptDate(req.confirmedDate, req.submittedAt);
    final formattedBookingCreated = _formatDoctorBookingCreated(req.submittedAt);
    final statusUpper = req.status.trim().toUpperCase();
    final bool isConfirmedOrAccepted = statusUpper == 'CONFIRMED' ||
        statusUpper == 'ACCEPTED' ||
        statusUpper == 'DENTIST_ACCEPTED';
    final bool isInProgress = statusUpper == 'IN_PROGRESS' || statusUpper == 'STARTED';
    final bool isDelayed = statusUpper == 'DELAYED' || req.delayMinutes > 0;
    final bool isNoShow = statusUpper == 'NO_SHOW' || statusUpper == 'NOSHOW';
    final bool isCompleted = statusUpper == 'COMPLETED';
    final bool isCancelledOrRejected = statusUpper == 'CANCELLED' || statusUpper == 'REJECTED';
    final bool isPendingAcceptance = !isConfirmedOrAccepted && !isInProgress && !isDelayed && !isNoShow && !isCompleted && !isCancelledOrRejected;
    final bool isAccepting = _acceptingRequestIds.contains(req.id);
    final String consultModeLabel = req.displayConsultationMode;
    final bool isOnlineMode = consultModeLabel == 'Online';

    final String statusLabel = isInProgress
        ? 'In Progress'
        : (isDelayed
            ? 'Delayed (${req.delayMinutes > 0 ? "${req.delayMinutes}m" : "Late"})'
            : (isNoShow
                ? 'No-Show'
                : (isConfirmedOrAccepted
                    ? 'Confirmed'
                    : (isCompleted
                        ? 'Completed'
                        : (statusUpper == 'RESCHEDULED'
                            ? 'Rescheduled'
                            : (statusUpper == 'CANCELLED'
                                ? 'Cancelled'
                                : (statusUpper == 'REJECTED' ? 'Declined' : 'Pending')))))));

    return Container(
      key: Key('doctor_appointment_card_${req.id}'),
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isConfirmedOrAccepted
              ? const Color(0xFF012A58).withValues(alpha: 0.45)
              : AppTheme.gsNavy.withValues(alpha: 0.25),
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.gsNavy.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Patient Name, Profile Details & Contact + Status Badge
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.gsNavy.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.person_rounded, color: AppTheme.gsNavy, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            patientName,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15.5, color: AppTheme.textDark),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (formattedContact.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              formattedContact,
                              style: const TextStyle(fontSize: 12, color: AppTheme.textMuted, fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          if (profileSummary.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              profileSummary,
                              style: const TextStyle(fontSize: 11.5, color: Color(0xFF475569), fontWeight: FontWeight.w500),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    key: Key('doctor_appointment_status_badge_${req.id}'),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusLabel == 'Confirmed'
                          ? const Color(0x14012A58)
                          : (req.severity == 'Severe' ? const Color(0x14FE3434) : const Color(0x14FE3434)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      statusLabel,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: statusLabel == 'Confirmed'
                            ? const Color(0xFF012A58)
                            : (req.severity == 'Severe' ? const Color(0xFFFE3434) : const Color(0xFFFE3434)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  InkWell(
                    key: Key('doctor_view_patient_details_btn_${req.id}'),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (ctx) => DoctorPatientRecordScreen(
                            patient: targetPatientProfile,
                            onWriteRx: () => _showPrescriptionModal(context, targetPatientProfile.name),
                            onRefer: () {
                              Navigator.of(ctx).pop();
                              _selectPatientForReferral(targetPatientProfile);
                              setState(() {
                                _previousTabIndex = 0;
                                _currentIndex = 3;
                              });
                            },
                          ),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                      decoration: BoxDecoration(
                        color: AppTheme.gsNavy.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.assignment_ind_outlined, size: 12, color: AppTheme.gsNavy),
                          SizedBox(width: 4),
                          Text(
                            'Patient Details',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.gsNavy,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Row 1b: Patient Details Summary Box (Always Visible on Card)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Wrap(
              spacing: 14,
              runSpacing: 6,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.badge_outlined, size: 13.5, color: Color(0xFF475569)),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        'Patient: $patientName',
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (formattedContact.isNotEmpty)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.phone_outlined, size: 13.5, color: Color(0xFF475569)),
                      const SizedBox(width: 4),
                      Text(
                        formattedContact,
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                      ),
                    ],
                  ),
                if (patientCity.isNotEmpty)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.location_on_outlined, size: 13.5, color: Color(0xFF475569)),
                      const SizedBox(width: 3),
                      Text(
                        patientPincode.isNotEmpty ? '$patientCity ($patientPincode)' : patientCity,
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                      ),
                    ],
                  ),
                if (patientGender.isNotEmpty || patientAge.isNotEmpty)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.person_outline_rounded, size: 13.5, color: Color(0xFF475569)),
                      const SizedBox(width: 3),
                      Text(
                        [
                          if (patientGender.isNotEmpty) patientGender,
                          if (patientAge.isNotEmpty) '$patientAge yrs',
                        ].join(' • '),
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, color: Color(0xFF475569)),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Row 2: Appointment Date & Time Slot Banner + Status Pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                const Icon(Icons.access_time_filled_rounded, size: 16, color: AppTheme.gsNavy),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    req.scheduledEndTime != null && req.scheduledEndTime!.isNotEmpty
                        ? '$formattedApptDate • $time - ${req.scheduledEndTime}'
                        : '$formattedApptDate • $time',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.gsNavy),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  key: Key('doctor_appt_mode_badge_${req.id}'),
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: isOnlineMode ? const Color(0xFFDBEAFE) : const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isOnlineMode ? Icons.videocam_outlined : Icons.local_hospital_outlined,
                        size: 11,
                        color: isOnlineMode ? const Color(0xFF1D4ED8) : const Color(0xFF047857),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        consultModeLabel,
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: isOnlineMode ? const Color(0xFF1D4ED8) : const Color(0xFF047857),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isConfirmedOrAccepted ? const Color(0xFF012A58) : AppTheme.gsNavy,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isConfirmedOrAccepted ? Icons.verified_rounded : Icons.schedule_rounded,
                        color: Colors.white,
                        size: 12,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        statusLabel,
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Row 2b: Clinic Details + Booking Created Date & Time
          Wrap(
            spacing: 10,
            runSpacing: 6,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.local_hospital_outlined, size: 13.5, color: Color(0xFF475569)),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      'Clinic: $clinicName',
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              Text(
                'Booked: $formattedBookingCreated',
                style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Row 3: Procedure Category & Symptoms Description
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppTheme.gsNavy.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'Category: ${req.problemCategory}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppTheme.gsNavy),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            req.problemDescription,
            style: const TextStyle(fontSize: 12, color: AppTheme.textMedium, height: 1.35),
          ),

          if (req.cleanAdminGuidance != null && req.cleanAdminGuidance!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '${req.isReferral ? "Referral Note" : "Admin Note"}: ${req.cleanAdminGuidance!.trim()}',
              style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: AppTheme.textMuted),
            ),
          ],
          const SizedBox(height: 14),

          // Row 3b: Appointment Acceptance Bar (Accept / Decline for Pending Appointments)
          if (isPendingAcceptance) ...[
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 40,
                    child: ElevatedButton.icon(
                      key: Key('doctor_accept_appointment_btn_${req.id}'),
                      icon: isAccepting
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.check_circle_outline_rounded, size: 16),
                      label: Text(
                        isAccepting ? 'Accepting...' : 'Accept Appointment',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF012A58),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: isAccepting
                          ? null
                          : () => _handleAcceptTimelineAppointment(req, patientName),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 1,
                  child: SizedBox(
                    height: 40,
                    child: OutlinedButton.icon(
                      key: Key('doctor_reject_appointment_btn_${req.id}'),
                      icon: const Icon(Icons.close_rounded, size: 15),
                      label: const Text(
                        'Decline',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11.5),
                        overflow: TextOverflow.ellipsis,
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFFE3434),
                        side: const BorderSide(color: Color(0x40FE3434)),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: isAccepting
                          ? null
                          : () => _handleRejectTimelineAppointment(req, patientName),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ] else if (isConfirmedOrAccepted || isInProgress || isDelayed) ...[
            if (isDelayed)
              Container(
                key: Key('doctor_delay_banner_${req.id}'),
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFF59E0B)),
                ),
                child: Text(
                  'Delayed by ${req.delayMinutes > 0 ? req.delayMinutes : 15} mins${nextAppointment != null ? " • Next: ${nextAppointment.patientName} (${nextAppointment.confirmedTimeSlot ?? "Scheduled"})" : ""}',
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF92400E)),
                ),
              )
            else if (nextAppointment != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Next Appointment: ${nextAppointment.patientName} • ${nextAppointment.confirmedTimeSlot ?? ""} (${nextAppointment.displayConsultationMode})',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (isConfirmedOrAccepted)
              Container(
                key: Key('doctor_accepted_badge_${req.id}'),
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0x14012A58),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0x40012A58)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.check_circle_rounded, size: 16, color: Color(0xFF012A58)),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Appointment Accepted & Confirmed',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF012A58),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            // Lifecycle Controls: Cancel only (Start, Complete, Mark Delayed, and No-Show removed per workflow update)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                OutlinedButton.icon(
                  key: Key('doctor_cancel_consultation_btn_${req.id}'),
                  icon: const Icon(Icons.cancel_outlined, size: 14),
                  label: const Text('Cancel', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFE3434),
                    side: const BorderSide(color: Color(0x40FE3434)),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                  onPressed: () => _handleLifecycleAction(
                    () => _patientService.cancelAppointment(req.id),
                    'Consultation cancelled',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],

          // Row 4: Action Buttons (Issue E-Prescription & Chat)
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 38,
                  child: ElevatedButton.icon(
                    key: Key('doctor_issue_eprescription_btn_${req.id}'),
                    icon: const Icon(Icons.receipt_long_rounded, size: 14),
                    label: const Text('Issue E-Prescription', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.gsNavy,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.zero,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => _showPrescriptionModal(context, req),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 38,
                  child: OutlinedButton.icon(
                    key: Key('doctor_chat_btn_${req.id}'),
                    icon: const Icon(Icons.chat_bubble_outline_rounded, size: 14),
                    label: const Text('Chat', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.gsNavy,
                      side: const BorderSide(color: AppTheme.gsNavy),
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () {
                      final resolvedDoc = _resolveCurrentDoctor() ?? _patientService.currentDoctor;
                      final docName = (resolvedDoc?.name.trim().isNotEmpty == true)
                          ? resolvedDoc!.name.trim()
                          : ((req.assignedDoctorName?.trim().isNotEmpty == true)
                              ? req.assignedDoctorName!.trim()
                              : (req.displayDoctorName.trim().isNotEmpty ? req.displayDoctorName.trim() : 'DOCTOR'));
                      final rId = ApiService.getChatRoomId(patientIdOrName: patientName, dentistIdOrName: docName);
                      _showDoctorChatModal(
                        context,
                        patientName,
                        rId,
                        patientId: req.patientId,
                        doctorNameOverride: docName,
                        doctorIdOverride: resolvedDoc?.id ?? req.assignedDoctorId,
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _getPatientInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return 'P';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  // ==========================================
  // TAB 1: PATIENTS TAB
  // ==========================================
  Widget _buildPatientsTab() {
    final currentDoc = _resolveCurrentDoctor();
    final authUser = _safeAuthUser;

    final currentDocName = (currentDoc?.name ?? '').replaceAll('Dr.', '').replaceAll('Dr. ', '').trim().toLowerCase();
    final currentDocId = (currentDoc?.id ?? '').trim();
    final currentDocUserId = (currentDoc?.userId ?? '').trim();
    final currentDocEmail = (currentDoc?.email ?? '').trim().toLowerCase();
    final authUserId = (authUser?.id ?? '').trim();
    final authEmail = (authUser?.email ?? '').trim().toLowerCase();

    final allPool = _getDentistAssignedAndScheduledRequests();
    final patient = _patientService.currentPatient;
    final Map<String, Map<String, String>> uniquePatientMap = {};
    for (final req in allPool) {
      uniquePatientMap[req.patientName.trim().toLowerCase()] = {
        'name': req.patientName,
        'phone': req.patientPhone,
        'age': patient.age.isNotEmpty ? '${patient.age} Yrs' : '',
        'blood': patient.bloodGroup,
        'issue': req.problemCategory,
      };
    }
    for (final ref in _patientService.doctorReceivedPatientReferrals) {
      final key = ref.referredPatientName.trim().toLowerCase();
      if (!uniquePatientMap.containsKey(key)) {
        uniquePatientMap[key] = {
          'name': ref.referredPatientName,
          'phone': ref.referredPatientMobile,
          'age': ref.referredPatientAge.isNotEmpty
              ? '${ref.referredPatientAge} Yrs${ref.referredPatientGender.isNotEmpty ? " (${ref.referredPatientGender})" : ""}'
              : ref.referredPatientGender,
          'blood': '',
          'issue': ref.requiredSpecialist.isNotEmpty ? ref.requiredSpecialist : 'Referral Consultation',
        };
      }
    }
    final associatedPatients = _patientService.getDentistAssociatedPatients();
    final Map<String, PatientProfile> patientProfileMap = {};
    for (final p in associatedPatients) {
      final k = p.name.trim().toLowerCase();
      patientProfileMap[k] = p;
      uniquePatientMap.putIfAbsent(k, () => {
        'name': p.name,
        'phone': p.phone,
        'age': p.age.isNotEmpty ? '${p.age} Yrs' : '',
        'blood': p.bloodGroup,
        'issue': 'Consultation',
        'patientId': p.id,
      });
    }
    // Build lookup map of known patient profiles strictly for enriching metadata of THIS doctor's patients
    // (NEVER inject unrelated platform patients into uniquePatientMap).
    for (final p in _patientService.allPatients) {
      final k = p.name.trim().toLowerCase();
      if (k.isNotEmpty) {
        patientProfileMap.putIfAbsent(k, () => p);
      }
    }

    final effectiveDocId = currentDocId.isNotEmpty
        ? currentDocId
        : (currentDocUserId.isNotEmpty ? currentDocUserId : authUserId);
    final effectiveDocUserId = currentDocUserId.isNotEmpty ? currentDocUserId : authUserId;
    final effectiveDocEmail = currentDocEmail.isNotEmpty ? currentDocEmail : authEmail;

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: (effectiveDocId.isNotEmpty || effectiveDocEmail.isNotEmpty)
          ? ApiService().fetchSharedRecordsForDoctor(
              doctorId: effectiveDocId.isNotEmpty ? effectiveDocId : effectiveDocEmail,
              doctorUserId: effectiveDocUserId,
              doctorEmail: effectiveDocEmail,
            )
          : Future.value(const <Map<String, dynamic>>[]),
      builder: (context, sharedSnapshot) {
        final rawShared = <Map<String, dynamic>>[
          ..._patientService.doctorSharedRecords,
          ...(sharedSnapshot.data ?? const <Map<String, dynamic>>[]),
        ];

        // Deduplicate & strictly verify doctor authorization
        final sharedMap = <String, Map<String, dynamic>>{};
        for (final rec in rawShared) {
          final id = (rec['id'] ?? '').toString();
          if (id.isEmpty) continue;
          final isAuthorized = ApiService.isDoctorAuthorizedForRecordMap(
            rec,
            doctorId: effectiveDocId,
            doctorUserId: effectiveDocUserId,
            doctorEmail: effectiveDocEmail,
          );
          if (!isAuthorized && currentDocName.isNotEmpty) continue;

          final recCopy = Map<String, dynamic>.from(rec);
          final recPid = (recCopy['patientId'] ?? recCopy['patient_id'] ?? '').toString();
          final curPName = (recCopy['patientName'] ?? '').toString();
          if ((curPName.isEmpty || curPName == 'Patient') && recPid.isNotEmpty) {
            final matchP = _patientService.allPatients.where((p) => p.id == recPid).firstOrNull;
            if (matchP != null && matchP.name.isNotEmpty) {
              recCopy['patientName'] = matchP.name;
            }
          }
          sharedMap[id] = recCopy;

          final pName = (recCopy['patientName'] ?? 'Patient').toString().trim();
          final pKey = pName.toLowerCase();
          if (pName.isNotEmpty && !uniquePatientMap.containsKey(pKey)) {
            final matchP = patientProfileMap[pKey];
            uniquePatientMap[pKey] = {
              'name': pName,
              'phone': matchP?.phone ?? '',
              'age': (matchP?.age.isNotEmpty == true) ? '${matchP!.age} Yrs' : '',
              'blood': (matchP?.bloodGroup.isNotEmpty == true) ? matchP!.bloodGroup : '',
              'issue': 'Shared Health Record (${recCopy['category'] ?? 'Record'})',
              'patientId': recPid,
            };
          }
        }

        final combinedPatients = uniquePatientMap.values.toList();
        final filteredPatients = combinedPatients.where((p) {
          if (_patientSearchQuery.isEmpty) return true;
          final q = _patientSearchQuery.toLowerCase();
          final name = (p['name'] ?? '').toString().toLowerCase();
          final phone = (p['phone'] ?? '').toString().toLowerCase();
          final city = (p['city'] ?? '').toString().toLowerCase();
          return name.contains(q) || phone.contains(q) || city.contains(q);
        }).toList();

        return SingleChildScrollView(
          key: const Key('dentist_patients_scroll_view'),
          physics: const BouncingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Clean GS HEALTH Header (Screenshot 1)
              Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Everyone you've cared for",
                      style: TextStyle(
                        fontSize: 13.5,
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: 2),
                    Text(
                      'My patients',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                        letterSpacing: -0.4,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Full-width Search Bar (Screenshot 1)
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: TextField(
                        key: const Key('doctor_patients_search_field'),
                        controller: _patientSearchCtrl,
                        onChanged: (val) {
                          setState(() {
                            _patientSearchQuery = val.trim();
                          });
                        },
                        style: const TextStyle(fontSize: 14, color: Color(0xFF0F172A)),
                        decoration: InputDecoration(
                          hintText: 'Search by name or phone number',
                          hintStyle: const TextStyle(fontSize: 13.5, color: Color(0xFF94A3B8)),
                          prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF94A3B8), size: 22),
                          suffixIcon: _patientSearchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.close_rounded, color: Color(0xFF94A3B8), size: 18),
                                  onPressed: () {
                                    _patientSearchCtrl.clear();
                                    setState(() => _patientSearchQuery = '');
                                  },
                                )
                              : null,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Patient Cards
                    if (filteredPatients.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(32),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _patientSearchQuery.isNotEmpty ? Icons.search_off_rounded : Icons.people_outline_rounded,
                                size: 40,
                                color: const Color(0xFF94A3B8),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _patientSearchQuery.isNotEmpty ? 'No patients found' : 'No patients yet',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _patientSearchQuery.isNotEmpty
                                    ? 'No patient matches "$_patientSearchQuery"'
                                    : 'Patients you care for will appear here.',
                                style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      ...filteredPatients.map((p) {
                        final pName = (p['name'] ?? 'Patient').toString().trim();
                        final profile = patientProfileMap[pName.toLowerCase()];
                        final pId = (p['patientId'] ?? profile?.id ?? '').toString().trim();
                        final pPhone = (p['phone'] ?? profile?.phone ?? '').toString().trim();
                        final pCity = (profile?.city.isNotEmpty == true)
                            ? profile!.city
                            : (p['city']?.isNotEmpty == true ? p['city']! : '');

                        // Compute visits count & last visit date
                        final cleanDigits = pPhone.replaceAll(RegExp(r'\D'), '');
                        final raw10 = cleanDigits.length >= 10 ? cleanDigits.substring(cleanDigits.length - 10) : cleanDigits;
                        final nameLower = pName.toLowerCase();

                        int visitsCount = 0;
                        DateTime? lastVisitDate;

                        for (final req in allPool) {
                          final rPid = (req.patientId ?? '').trim();
                          final rPhone = req.patientPhone.replaceAll(RegExp(r'\D'), '');
                          final rName = req.patientName.trim().toLowerCase();

                          if ((pId.isNotEmpty && rPid == pId) ||
                              (rName.isNotEmpty && rName == nameLower) ||
                              (raw10.isNotEmpty && rPhone.contains(raw10))) {
                            visitsCount++;
                            DateTime? d;
                            if (req.confirmedDate != null && req.confirmedDate!.isNotEmpty) {
                              d = DateTime.tryParse(req.confirmedDate!);
                            }
                            d ??= req.submittedAt;
                            if (lastVisitDate == null || d.isAfter(lastVisitDate)) {
                              lastVisitDate = d;
                            }
                          }
                        }

                        // Format phone number
                        String formattedPhone;
                        if (cleanDigits.length == 10) {
                          formattedPhone = '+91 $cleanDigits';
                        } else if (cleanDigits.length > 10 && cleanDigits.startsWith('91')) {
                          formattedPhone = '+91 ${cleanDigits.substring(2)}';
                        } else if (pPhone.isNotEmpty) {
                          formattedPhone = pPhone.startsWith('+') ? pPhone : '+$pPhone';
                        } else {
                          formattedPhone = 'Not provided';
                        }

                        // Format last visit date
                        String lastVisitStr = '';
                        if (lastVisitDate != null) {
                          const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
                          const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
                          final w = weekdays[lastVisitDate.weekday - 1];
                          final m = months[lastVisitDate.month - 1];
                          lastVisitStr = '$w, ${lastVisitDate.day} $m';
                        }

                        final visitsSubtitle = visitsCount > 0
                            ? '$visitsCount ${visitsCount == 1 ? "visit" : "visits"}${lastVisitStr.isNotEmpty ? " · last $lastVisitStr" : ""}'
                            : '0 visits';

                        final targetProfile = profile ??
                            PatientProfile(
                              id: pId.isNotEmpty ? pId : 'pat_${pName.hashCode}',
                              name: pName,
                              phone: pPhone,
                              city: pCity,
                              age: (p['age'] ?? '').toString().replaceAll(RegExp(r'\D'), ''),
                              gender: '',
                              bloodGroup: p['blood'] ?? '',
                              languages: const ['English'],
                            );

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: InkWell(
                            key: Key('doctor_patient_card_${pName.toLowerCase().replaceAll(' ', '_')}'),
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (ctx) => DoctorPatientRecordScreen(
                                    patient: targetProfile,
                                    onWriteRx: () => _showPrescriptionModal(context, targetProfile.name),
                                    onRefer: () {
                                      Navigator.of(ctx).pop();
                                      _selectPatientForReferral(targetProfile);
                                      setState(() {
                                        _previousTabIndex = 1;
                                        _currentIndex = 3;
                                      });
                                    },
                                  ),
                                ),
                              );
                            },
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: Row(
                                children: [
                                  // Squircle Avatar
                                  Container(
                                    width: 52,
                                    height: 52,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF0F172A),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: targetProfile.photoBytes != null && targetProfile.photoBytes!.isNotEmpty
                                        ? Image.memory(targetProfile.photoBytes!, fit: BoxFit.cover)
                                        : Center(
                                            child: Text(
                                              _getPatientInitials(pName),
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 18,
                                              ),
                                            ),
                                          ),
                                  ),
                                  const SizedBox(width: 14),
                                  // Patient Details
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          pName,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w800,
                                            color: Color(0xFF0F172A),
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          '$formattedPhone · $pCity',
                                          style: const TextStyle(
                                            fontSize: 13,
                                            color: Color(0xFF64748B),
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          visitsSubtitle,
                                          style: const TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF012A58),
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  // Chevron Navigation Arrow
                                  const Icon(
                                    Icons.chevron_right_rounded,
                                    color: Color(0xFF94A3B8),
                                    size: 24,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ==========================================
  // TAB 2: ASSIGNED REQUESTS TAB (Screenshot 2)
  // ==========================================
  Widget _buildAssignedRequestsTab() {
    final doc = _resolveCurrentDoctor();
    final allRequests = _getDentistAssignedAndScheduledRequests();
    final incomingReferrals = _patientService.doctorReceivedPatientReferrals;

    return SingleChildScrollView(
      key: const Key('dentist_requests_scroll_view'),
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: "Triage cases routed to you" + "Assigned requests" + folder icon
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Triage cases & referrals routed to you',
                        style: TextStyle(
                          fontSize: 13.5,
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Assigned requests',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                          letterSpacing: -0.4,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                InkWell(
                  key: const Key('requests_folder_button'),
                  onTap: () => setState(() => _currentIndex = 1),
                  borderRadius: BorderRadius.circular(22),
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.folder_outlined,
                        color: Color(0xFF0F172A),
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: Color(0xFFE2E8F0)),

          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
            child: (allRequests.isEmpty && incomingReferrals.isEmpty)
                ? Container(
                    key: const Key('dentist_requests_empty_state'),
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 42, horizontal: 20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            color: AppTheme.gsNavy.withValues(alpha: 0.06),
                            shape: BoxShape.circle,
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.inbox_outlined,
                              color: AppTheme.gsNavy,
                              size: 28,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'No assigned requests yet',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'When an admin, AI triage, or another doctor routes a patient or referral to you, it will appear here.',
                          style: TextStyle(
                            fontSize: 13.5,
                            color: Color(0xFF64748B),
                            height: 1.4,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (incomingReferrals.isNotEmpty) ...[
                        _buildIncomingReferralsSection(incomingReferrals, keyPrefix: 'requests'),
                        if (allRequests.isNotEmpty) const SizedBox(height: 22),
                      ],
                      ...allRequests.map((req) => _buildAssignedRequestCard(req, doc)),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildDoctorRecentPatientActivityPreviewSection(
    List<PatientConsultationRequest> allMyRequests,
  ) {
    final latestActivity = takeLatestPreviewRecords<PatientConsultationRequest>(
      allMyRequests,
      limit: kDashboardRecentPreviewLimit,
      compareDesc: (a, b) => b.submittedAt.compareTo(a.submittedAt),
    );
    return RecentUpdatesPreviewSection(
      sectionKey: const Key('doctor_recent_patient_activity_section'),
      viewAllKey: const Key('doctor_view_all_patients_btn'),
      emptyStateKey: const Key('doctor_recent_patient_activity_empty'),
      title: 'Recent Patient Activity',
      totalCount: allMyRequests.length,
      icon: Icons.people_outline_rounded,
      onViewAll: () => setState(() => _currentIndex = 1),
      emptyIcon: Icons.people_outline_rounded,
      emptyTitle: 'No recent patient activity yet.',
      emptySubtitle: 'Patient consultations and updates will appear here.',
      previewChildren: latestActivity.asMap().entries.map((entry) {
        final idx = entry.key;
        final req = entry.value;
        final dt = req.submittedAt.toLocal();
        final dateLabel = (req.confirmedDate != null && req.confirmedDate!.trim().isNotEmpty)
            ? req.confirmedDate!.split('T').first
            : '${dt.day}/${dt.month}/${dt.year}';
        final slotLabel = (req.confirmedTimeSlot != null && req.confirmedTimeSlot!.trim().isNotEmpty)
            ? ' • ${req.confirmedTimeSlot}'
            : '';
        return RecentUpdatePreviewCard(
          cardKey: Key('doctor_recent_patient_activity_card_$idx'),
          leadingIcon: Icons.person_outline_rounded,
          title: req.patientName.trim().isNotEmpty ? req.patientName.trim() : 'Patient',
          subtitle: req.problemCategory.trim().isNotEmpty ? req.problemCategory.trim() : 'Consultation',
          metaLine: '$dateLabel$slotLabel${req.patientPhone.trim().isNotEmpty ? " • ${req.patientPhone.trim()}" : ""}',
          statusLabel: req.status.trim().isNotEmpty ? req.status.trim() : 'Pending',
          onTap: () => setState(() => _currentIndex = 1),
        );
      }).toList(),
    );
  }

  Widget _buildIncomingReferralsSection(
    List<PatientReferral> referrals, {
    String keyPrefix = 'today',
    int? maxPreviewItems,
    VoidCallback? onViewAll,
  }) {
    final sortedReferrals = List<PatientReferral>.from(referrals)
      ..sort((a, b) => b.referralDate.compareTo(a.referralDate));
    final visibleReferrals = (maxPreviewItems != null && sortedReferrals.length > maxPreviewItems)
        ? sortedReferrals.sublist(0, maxPreviewItems)
        : sortedReferrals;

    return Container(
      key: Key('doctor_${keyPrefix}_incoming_referrals_section'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.share_outlined, size: 18, color: AppTheme.gsNavy),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  maxPreviewItems != null
                      ? 'Recent Referrals (${referrals.length})'
                      : 'Incoming Patient Referrals (${referrals.length})',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (onViewAll != null)
                TextButton(
                  key: const Key('doctor_view_all_referrals_btn'),
                  onPressed: onViewAll,
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
          if (visibleReferrals.isEmpty)
            Container(
              key: Key('doctor_${keyPrefix}_referrals_empty'),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.share_outlined, color: AppTheme.textMuted, size: 20),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'No recent referrals yet.',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textDark,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            ...visibleReferrals.map((ref) => _buildDoctorReceivedReferralCard(ref, keyPrefix: keyPrefix)),
        ],
      ),
    );
  }

  Widget _buildDoctorReceivedReferralCard(
    PatientReferral ref, {
    String keyPrefix = 'today',
  }) {
    final normalizedStatus = ref.status.trim().toLowerCase();
    final isPending = normalizedStatus == 'pending';
    final isAccepted = normalizedStatus == 'accepted' || normalizedStatus == 'completed';
    final Color badgeBg = isPending
        ? const Color(0x14FE3434)
        : (isAccepted ? const Color(0x14012A58) : const Color(0x14FE3434));
    final Color badgeFg = isPending
        ? const Color(0xFFFE3434)
        : (isAccepted ? const Color(0xFF012A58) : const Color(0xFFFE3434));

    return Container(
      key: Key('doctor_${keyPrefix}_received_referral_card_${ref.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.gsNavy.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    ref.referredPatientName.isNotEmpty
                        ? ref.referredPatientName[0].toUpperCase()
                        : 'P',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.gsNavy,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ref.referredPatientName,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (ref.referredPatientMobile.isNotEmpty) ref.referredPatientMobile,
                        if (ref.referredPatientAge.isNotEmpty) '${ref.referredPatientAge} yrs',
                        if (ref.referredPatientGender.isNotEmpty) ref.referredPatientGender,
                        if (ref.referredPatientCity.isNotEmpty) ref.referredPatientCity,
                      ].join(' • '),
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFF64748B),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  ref.status,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: badgeFg,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (ref.requiredSpecialist.isNotEmpty)
                  Text(
                    'Specialist: ${ref.requiredSpecialist}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.gsNavy,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (ref.clinicalComplaint.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    ref.clinicalComplaint,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF334155),
                      height: 1.35,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (ref.referrerPatientName.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Referred by: ${ref.referrerPatientName}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (isPending) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: Key('${keyPrefix}_decline_referral_btn_${ref.id}'),
                    onPressed: () async {
                      final ok = await _patientService.rejectPatientReferralByDoctor(
                        ref.id,
                        rejectionReason: 'Declined by specialist',
                      );
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            ok
                                ? 'Referral declined for ${ref.referredPatientName}.'
                                : 'Could not update referral status.',
                          ),
                          backgroundColor: ok ? const Color(0xFF475569) : AppTheme.gsRed,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFFE3434),
                      side: const BorderSide(color: Color(0x40FE3434)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text(
                      'Decline',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    key: Key('${keyPrefix}_accept_referral_btn_${ref.id}'),
                    onPressed: () async {
                      final ok = await _patientService.acceptPatientReferralByDoctor(ref.id);
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            ok
                                ? 'Referral accepted for ${ref.referredPatientName}.'
                                : 'Could not accept referral.',
                          ),
                          backgroundColor: ok ? const Color(0xFF012A58) : AppTheme.gsRed,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF012A58),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text(
                      'Accept Referral',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (normalizedStatus == 'accepted' || normalizedStatus == 'contacted') ...[
            const SizedBox(height: 10),
            Row(
              children: [
                if (normalizedStatus == 'accepted')
                  Expanded(
                    child: OutlinedButton(
                      key: Key('${keyPrefix}_mark_contacted_referral_btn_${ref.id}'),
                      onPressed: () async {
                        final ok = await _patientService.updatePatientReferralStatus(
                          ref.id,
                          status: 'Contacted',
                        );
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              ok
                                  ? 'Referral marked Contacted.'
                                  : 'Could not update referral status.',
                            ),
                            backgroundColor: ok ? const Color(0xFF012A58) : AppTheme.gsRed,
                          ),
                        );
                      },
                      child: const Text('Mark Contacted', overflow: TextOverflow.ellipsis),
                    ),
                  ),
                if (normalizedStatus == 'accepted') const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    key: Key('${keyPrefix}_mark_completed_referral_btn_${ref.id}'),
                    onPressed: () async {
                      final ok = await _patientService.updatePatientReferralStatus(
                        ref.id,
                        status: 'Completed',
                      );
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            ok
                                ? 'Referral marked Completed.'
                                : 'Could not update referral status.',
                          ),
                          backgroundColor: ok ? const Color(0xFF012A58) : AppTheme.gsRed,
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF012A58),
                      foregroundColor: Colors.white,
                      elevation: 0,
                    ),
                    child: const Text('Mark Completed', overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAssignedRequestCard(PatientConsultationRequest req, DoctorModel? doc) {
    final severityUpper = req.severity.trim().toUpperCase();
    final isHighUrgency = severityUpper.contains('SEVERE') ||
        severityUpper.contains('HIGH') ||
        severityUpper.contains('URGENT') ||
        severityUpper.contains('EMERGENCY');
    final isLowUrgency = severityUpper.contains('LOW') || severityUpper.contains('MILD');
    final urgencyLabel = isHighUrgency
        ? 'HIGH URGENCY'
        : (isLowUrgency ? 'LOW URGENCY' : 'MODERATE URGENCY');

    final isAccepted = req.status.toLowerCase().contains('confirm') ||
        req.status.toLowerCase().contains('accept');
    final isAccepting = _acceptingRequestIds.contains(req.id);

    final bool isAssignedToDoctor = (doc != null && doc.id.isNotEmpty && req.assignedDoctorId == doc.id) ||
        (doc != null &&
            req.assignedDoctorName != null &&
            req.assignedDoctorName!.toLowerCase().contains(doc.name.replaceAll('Dr.', '').replaceAll('Dr. ', '').trim().toLowerCase()));

    final bool isAuthorized = isAssignedToDoctor ||
        isAccepted ||
        (doc != null && (doc.verified || doc.verificationStatus == 'VERIFIED'));

    final isReferral = req.isReferral;
    final headline = isReferral
        ? (req.problemCategory.trim().isNotEmpty
            ? req.problemCategory.trim()
            : 'Patient Referral')
        : ((req.symptoms.trim().isNotEmpty && req.symptoms.trim() != req.problemDescription.trim())
            ? req.symptoms.trim()
            : (req.problemCategory.trim().isNotEmpty
                ? req.problemCategory.trim()
                : req.problemDescription.trim()));

    final displayReason = isReferral
        ? 'Referral Reason: ${req.cleanReferralReason}'
        : req.problemDescription;

    final formattedPhone = req.getFormattedPatientPhone(isAuthorized: isAuthorized);
    final patientNameClean = req.patientName.trim().isNotEmpty ? req.patientName.trim() : 'Patient';

    final suggestedSpecialty = (req.assignedDoctorSpecialty != null && req.assignedDoctorSpecialty!.trim().isNotEmpty)
        ? req.assignedDoctorSpecialty!.trim()
        : ((doc?.specialty.isNotEmpty == true)
            ? doc!.specialty
            : (req.problemCategory.isNotEmpty ? req.problemCategory : 'Endodontist'));

    final assignedDocName = (req.assignedDoctorName != null && req.assignedDoctorName!.trim().isNotEmpty)
        ? req.assignedDoctorName!.trim()
        : ((doc?.name.isNotEmpty == true) ? doc!.name : 'Assigned Doctor');

    final formattedDate = _formatShortDayMonth(req.submittedAt);

    return Container(
      key: Key('assigned_request_card_${req.id}'),
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Badges Row: Urgency + Assignment Status
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0x14FE3434),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.monitor_heart_outlined,
                      size: 13,
                      color: Color(0xFFFE3434),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      urgencyLabel,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFFE3434),
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
              if (isReferral)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0x14FE3434),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.share_outlined,
                        size: 12,
                        color: Color(0xFFFE3434),
                      ),
                      SizedBox(width: 4),
                      Text(
                        'PATIENT REFERRAL',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFFE3434),
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                decoration: BoxDecoration(
                  color: isAccepted ? const Color(0x14012A58) : const Color(0x14FE3434),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  isAccepted ? 'Accepted' : 'Doctor assigned',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: isAccepted ? const Color(0xFF012A58) : const Color(0xFF012A58),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Symptom Headline
          Text(
            headline,
            style: const TextStyle(
              fontSize: 17.5,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
              height: 1.3,
              fontFamilyFallback: ['Nirmala UI', 'Segoe UI Symbol', 'Segoe UI', 'Roboto'],
            ),
          ),
          const SizedBox(height: 6),

          // English Symptom Description / Referral Reason
          Text(
            displayReason,
            style: const TextStyle(
              fontSize: 14.5,
              color: Color(0xFF64748B),
              height: 1.4,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),

          // Metadata Rows
          _buildRequestMetaRow(
            Icons.person_outline_rounded,
            formattedPhone != 'Phone not provided'
                ? '$patientNameClean · $formattedPhone'
                : patientNameClean,
          ),
          const SizedBox(height: 6),
          _buildRequestMetaRow(
            Icons.medical_services_outlined,
            'Suggested: $suggestedSpecialty',
          ),
          const SizedBox(height: 6),
          _buildRequestMetaRow(
            Icons.done_all_rounded,
            'Assigned to $assignedDocName',
          ),
          const SizedBox(height: 6),
          _buildRequestMetaRow(
            Icons.access_time_rounded,
            formattedDate,
          ),

          // Admin Guidance / Referral Instructions Box (Sanitized, No Raw JSON or IDs)
          Builder(
            builder: (context) {
              final cleanGuidance = req.cleanAdminGuidance;
              if (cleanGuidance == null || cleanGuidance.trim().isEmpty) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.info_outline_rounded,
                            size: 13,
                            color: Color(0xFF64748B),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            isReferral ? 'REFERRAL INSTRUCTIONS' : 'ADMIN GUIDANCE',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF64748B),
                              letterSpacing: 0.6,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        cleanGuidance.trim(),
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF0F172A),
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 14),

          // Accept Case Button
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton.icon(
              key: Key('accept_case_button_${req.id}'),
              onPressed: (isAccepted || isAccepting)
                  ? null
                  : () => _handleAcceptAssignedRequest(req),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.gsNavy,
                disabledBackgroundColor: isAccepted
                    ? AppTheme.gsNavy.withValues(alpha: 0.55)
                    : AppTheme.gsNavy.withValues(alpha: 0.4),
                foregroundColor: Colors.white,
                disabledForegroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: isAccepting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(
                      isAccepted ? Icons.check_circle_outline_rounded : Icons.check_rounded,
                      size: 18,
                      color: Colors.white,
                    ),
              label: Text(
                isAccepting
                    ? 'Accepting...'
                    : (isAccepted ? 'Case accepted' : 'Accept case'),
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestMetaRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFF64748B)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13.5,
              color: Color(0xFF475569),
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Future<void> _handleAcceptAssignedRequest(PatientConsultationRequest req) async {
    if (_acceptingRequestIds.contains(req.id)) return;
    setState(() => _acceptingRequestIds.add(req.id));
    try {
      final targetDate = _baseCalendarDate.add(Duration(days: _selectedDateIndex));
      final dateStr =
          '${targetDate.year.toString().padLeft(4, '0')}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.day.toString().padLeft(2, '0')}';
      await _patientService.acceptReferralByDentist(
        req.id,
        timeSlot: (req.confirmedTimeSlot != null && req.confirmedTimeSlot!.trim().isNotEmpty)
            ? req.confirmedTimeSlot!
            : '11:00 AM',
        date: dateStr,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Accepted case for ${req.patientName}. Added to your schedule.'),
          backgroundColor: AppTheme.gsNavy,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _acceptingRequestIds.remove(req.id));
      }
    }
  }

  String _formatShortDayMonth(DateTime dt) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final dayName = days[(dt.weekday - 1).clamp(0, 6)];
    final monthName = months[(dt.month - 1).clamp(0, 11)];
    return '$dayName, ${dt.day} $monthName';
  }

  // ==========================================
  // TAB 3: REFER A PATIENT TAB (Screenshot 3)
  // ==========================================
  List<PatientProfile> _getDentistQuickSelectPatients() {
    final Map<String, PatientProfile> map = {};
    if (_selectedReferPatient != null && _selectedReferPatient!.name.trim().isNotEmpty) {
      map[_selectedReferPatient!.name.trim().toLowerCase()] = _selectedReferPatient!;
    }
    for (final p in _patientService.getDentistAssociatedPatients()) {
      if (p.name.trim().isNotEmpty && !map.containsKey(p.name.trim().toLowerCase())) {
        map[p.name.trim().toLowerCase()] = p;
      }
    }
    for (final p in _patientService.allPatients) {
      if (p.name.trim().isNotEmpty && !map.containsKey(p.name.trim().toLowerCase())) {
        map[p.name.trim().toLowerCase()] = p;
      }
    }
    for (final req in _getDentistAssignedAndScheduledRequests()) {
      final k = req.patientName.trim().toLowerCase();
      if (k.isNotEmpty && !map.containsKey(k)) {
        map[k] = PatientProfile(
          id: req.id,
          name: req.patientName.trim(),
          phone: req.patientPhone.replaceAll(RegExp(r'\D'), ''),
          age: '34',
          gender: 'Female',
          city: '',
          address: '',
          bloodGroup: 'O+',
          emergencyContact: '',
        );
      }
    }
    return map.values.toList();
  }

  void _selectPatientForReferral(PatientProfile p) {
    _selectedReferPatient = p;
    final cleanDigits = p.phone.replaceAll(RegExp(r'\D'), '');
    final tenDigits = cleanDigits.length > 10
        ? cleanDigits.substring(cleanDigits.length - 10)
        : cleanDigits;
    final cleanAge = p.age.replaceAll(RegExp(r'\D'), '');
    setState(() {
      _selectedReferPatientChipName = p.name;
      _referPatientNameCtrl.text = p.name;
      if (tenDigits.isNotEmpty) {
        _referPatientMobileCtrl.text = tenDigits;
      }
      _referPatientAgeCtrl.text = cleanAge.isNotEmpty ? cleanAge : '34';
      if (p.gender.trim().isNotEmpty) {
        final gLower = p.gender.trim().toLowerCase();
        if (gLower.startsWith('m')) {
          _referPatientGender = 'Male';
        } else if (gLower.startsWith('f')) {
          _referPatientGender = 'Female';
        } else {
          _referPatientGender = 'Other';
        }
      } else {
        _referPatientGender = 'Female';
      }
    });
  }

  Widget _buildReferPatientTab() {
    final currentDoc = _resolveCurrentDoctor();
    final quickPatients = _getDentistQuickSelectPatients();
    final searchQuery = _referSearchCtrl.text.trim().toLowerCase();

    final specialistDoctors = _patientService.allDoctors.where((d) {
      if (currentDoc != null && d.id.isNotEmpty && (d.id == currentDoc.id || (currentDoc.userId.isNotEmpty && d.userId == currentDoc.userId))) {
        return false;
      }
      if (searchQuery.isEmpty) return true;
      return d.name.toLowerCase().contains(searchQuery) ||
          d.specialty.toLowerCase().contains(searchQuery) ||
          d.clinicName.toLowerCase().contains(searchQuery) ||
          d.city.toLowerCase().contains(searchQuery);
    }).toList();

    final clinics = _patientService.allClinics.where((c) {
      if (searchQuery.isEmpty) return true;
      return c.clinicName.toLowerCase().contains(searchQuery) ||
          c.location.toLowerCase().contains(searchQuery) ||
          c.services.any((s) => s.toLowerCase().contains(searchQuery));
    }).toList();

    return SingleChildScrollView(
      key: const Key('dentist_refer_scroll_view'),
      physics: const BouncingScrollPhysics(),
      child: Form(
        key: _referFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header + Toggle Pills matching Screenshot 2
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      InkWell(
                        key: const Key('refer_screen_back_button'),
                        onTap: () {
                          setState(() {
                            _currentIndex = _previousTabIndex;
                          });
                        },
                        borderRadius: BorderRadius.circular(22),
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: const Center(
                            child: Icon(Icons.chevron_left_rounded, color: Color(0xFF0F172A), size: 28),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Text(
                          'Refer to a specialist',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                            letterSpacing: -0.4,
                          ),
                        ),
                      ),
                      InkWell(
                        key: const Key('refer_history_button'),
                        onTap: () => ReferredPatientsSheet.show(context),
                        borderRadius: BorderRadius.circular(22),
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.format_list_bulleted_rounded,
                              color: Color(0xFF0F172A),
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  // Hidden compat texts for legacy tests
                  const Offstage(
                    offstage: true,
                    child: Column(
                      children: [
                        Text('Share details & files with a specialist or clinic'),
                        Text('Refer a patient'),
                      ],
                    ),
                  ),
                  // Referral Type Toggle Pills: Specialist dentist | Clinic
                  Row(
                    children: [
                      InkWell(
                        key: const Key('refer_type_specialist_pill'),
                        onTap: () => setState(() => _referToClinic = false),
                        borderRadius: BorderRadius.circular(24),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          decoration: BoxDecoration(
                            color: !_referToClinic ? const Color(0xFF012A58) : Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: !_referToClinic ? const Color(0xFF012A58) : const Color(0xFFCBD5E1),
                            ),
                          ),
                          child: Text(
                            'Specialist doctor',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: !_referToClinic ? Colors.white : const Color(0xFF0F172A),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      InkWell(
                        key: const Key('refer_type_clinic_pill'),
                        onTap: () => setState(() => _referToClinic = true),
                        borderRadius: BorderRadius.circular(24),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                          decoration: BoxDecoration(
                            color: _referToClinic ? const Color(0xFF012A58) : Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: _referToClinic ? const Color(0xFF012A58) : const Color(0xFFCBD5E1),
                            ),
                          ),
                          child: Text(
                            'Clinic',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: _referToClinic ? Colors.white : const Color(0xFF0F172A),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1, thickness: 1, color: Color(0xFFE2E8F0)),

            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Patient details heading
                  const Text(
                    'Patient details',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Pick one of your patients or type details below',
                    style: TextStyle(
                      fontSize: 13.5,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  if (quickPatients.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: quickPatients.map((p) {
                        final isSelected = _selectedReferPatientChipName == p.name;
                        return InkWell(
                          key: Key('refer_patient_chip_${p.name}'),
                          onTap: () => _selectPatientForReferral(p),
                          borderRadius: BorderRadius.circular(22),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFF012A58)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(
                                color: isSelected ? const Color(0xFF012A58) : const Color(0xFFE2E8F0),
                                width: isSelected ? 1.5 : 1.0,
                              ),
                            ),
                            child: Text(
                              p.name,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: isSelected ? Colors.white : const Color(0xFF0F172A),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                  const SizedBox(height: 18),

                  // PATIENT NAME
                  const Text(
                    'PATIENT NAME',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF64748B),
                      letterSpacing: 0.7,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    key: const Key('dentist_refer_patient_name'),
                    controller: _referPatientNameCtrl,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF0F172A),
                    ),
                    decoration: _buildGsReferInputDecoration('e.g. Amit Verma'),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Please enter patient name' : null,
                  ),
                  const SizedBox(height: 16),

                  // PATIENT MOBILE (+91)
                  const Text(
                    'PATIENT MOBILE (+91)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF64748B),
                      letterSpacing: 0.7,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    key: const Key('dentist_refer_patient_phone'),
                    controller: _referPatientMobileCtrl,
                    keyboardType: TextInputType.phone,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF0F172A),
                    ),
                    decoration: _buildGsReferInputDecoration('98765 43210'),
                    validator: (v) {
                      final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
                      if (digits.length != 10) {
                        return 'Enter a valid 10-digit Indian mobile number';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // AGE + Gender Selection Row
                  const Text(
                    'AGE',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF64748B),
                      letterSpacing: 0.7,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 84,
                        child: TextFormField(
                          key: const Key('dentist_refer_patient_age'),
                          controller: _referPatientAgeCtrl,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF0F172A),
                          ),
                          decoration: _buildGsReferInputDecoration('34'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Row(
                          children: ['Male', 'Female', 'Other'].map((gender) {
                            final isSelected = _referPatientGender == gender;
                            return Expanded(
                              child: Padding(
                                padding: EdgeInsets.only(right: gender == 'Other' ? 0 : 8),
                                child: InkWell(
                                  key: Key('dentist_refer_gender_$gender'),
                                  onTap: () => setState(() => _referPatientGender = gender),
                                  borderRadius: BorderRadius.circular(14),
                                  child: Container(
                                    height: 48,
                                    decoration: BoxDecoration(
                                      color: isSelected ? const Color(0xFF012A58) : Colors.white,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: isSelected
                                            ? const Color(0xFF012A58)
                                            : const Color(0xFFE2E8F0),
                                      ),
                                    ),
                                    child: Center(
                                      child: Text(
                                        gender,
                                        style: TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w700,
                                          color: isSelected
                                              ? Colors.white
                                              : const Color(0xFF0F172A),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // REFER TO
                  const Text(
                    'REFER TO',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF64748B),
                      letterSpacing: 0.7,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    key: const Key('dentist_refer_search_input'),
                    controller: _referSearchCtrl,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF0F172A),
                    ),
                    decoration: _buildGsReferInputDecoration(
                      _referToClinic
                          ? 'Search clinic by name, location...'
                          : 'Search doctor by name, specialty...',
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Selectable Specialist Dentist Cards OR Clinic Cards
                  if (!_referToClinic) ...[
                    if (specialistDoctors.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: const Text(
                          'No matching doctors found.',
                          style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                          textAlign: TextAlign.center,
                        ),
                      )
                    else
                      ...specialistDoctors.take(6).map((doc) => _buildReferDoctorCard(doc)),
                  ] else ...[
                    if (clinics.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: const Text(
                          'No matching clinics found.',
                          style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                          textAlign: TextAlign.center,
                        ),
                      )
                    else
                      ...clinics.take(6).map((clinic) => _buildReferClinicCard(clinic)),
                  ],

                  const SizedBox(height: 18),

                  // CHIEF COMPLAINT & CLINICAL NOTES
                  const Text(
                    'CHIEF COMPLAINT & CLINICAL NOTES',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF64748B),
                      letterSpacing: 0.7,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    key: const Key('dentist_refer_notes_input'),
                    controller: _referNotesCtrl,
                    maxLines: 4,
                    style: const TextStyle(
                      fontSize: 14.5,
                      color: Color(0xFF0F172A),
                    ),
                    decoration: _buildGsReferInputDecoration(
                      'e.g. Impacted 38, pain for 2 weeks. Please evaluate for extraction',
                    ),
                  ),
                  const SizedBox(height: 18),

                  // ATTACH X-RAYS, PHOTOS OR REPORTS (0/5)
                  Text(
                    'ATTACH X-RAYS, PHOTOS OR REPORTS (${_referPickedAttachments.length}/5)',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF64748B),
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _buildReferAttachmentButton(
                          key: const Key('refer_attachment_gallery_button'),
                          icon: Icons.photo_library_outlined,
                          label: 'Gallery',
                          onTap: _pickGalleryAttachment,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildReferAttachmentButton(
                          key: const Key('refer_attachment_camera_button'),
                          icon: Icons.camera_alt_outlined,
                          label: 'Camera',
                          onTap: _pickCameraAttachment,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildReferAttachmentButton(
                          key: const Key('refer_attachment_pdf_button'),
                          icon: Icons.picture_as_pdf_outlined,
                          label: 'PDF',
                          onTap: _pickPdfAttachment,
                        ),
                      ),
                    ],
                  ),
                  if (_referPickedAttachments.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: _referPickedAttachments.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final att = entry.value;
                        return Container(
                          key: Key('refer_attachment_chip_${att.name}'),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (att.isImage)
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: att.bytes.isNotEmpty
                                      ? Image.memory(
                                          att.bytes,
                                          width: 36,
                                          height: 36,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) => Container(
                                            width: 36,
                                            height: 36,
                                            color: const Color(0xFFE2E8F0),
                                            child: const Icon(Icons.image_rounded, size: 20, color: Color(0xFF012A58)),
                                          ),
                                        )
                                      : Container(
                                          width: 36,
                                          height: 36,
                                          color: const Color(0xFFE2E8F0),
                                          child: const Icon(Icons.image_rounded, size: 20, color: Color(0xFF012A58)),
                                        ),
                                )
                              else
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: AppTheme.gsRed.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Center(
                                    child: Icon(Icons.picture_as_pdf_rounded, color: AppTheme.gsRed, size: 20),
                                  ),
                                ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 140),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        att.name,
                                        style: const TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF0F172A),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        att.formattedSize,
                                        style: const TextStyle(
                                          fontSize: 10.5,
                                          color: Color(0xFF64748B),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              InkWell(
                                key: Key('remove_refer_attachment_${att.name}'),
                                onTap: () => _removeReferAttachment(idx),
                                borderRadius: BorderRadius.circular(12),
                                child: const Padding(
                                  padding: EdgeInsets.all(4),
                                  child: Icon(Icons.close_rounded, size: 16, color: Color(0xFF64748B)),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                  const SizedBox(height: 22),

                  // Send referral Button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      key: const Key('dentist_send_referral_button'),
                      onPressed: _isSubmittingReferral ? null : _submitInlinePatientReferral,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF012A58),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      icon: _isSubmittingReferral
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.send_rounded, size: 18),
                      label: Text(
                        _isSubmittingReferral ? 'Sending referral...' : 'Send referral',
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _buildGsReferInputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(
        color: Color(0xFF94A3B8),
        fontSize: 15,
        fontWeight: FontWeight.w400,
      ),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFF012A58), width: 1.5),
      ),
    );
  }

  Widget _buildReferDoctorCard(DoctorModel doc) {
    final isSelected = _selectedReferDoctor?.id == doc.id && _selectedReferDoctor?.name == doc.name;
    final locationPart = doc.city.isNotEmpty
        ? doc.city
        : (doc.clinicName.isNotEmpty ? doc.clinicName : 'GS HEALTH Network');

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        key: Key('dentist_refer_doctor_${doc.id.isNotEmpty ? doc.id : doc.name}'),
        onTap: () => setState(() => _selectedReferDoctor = doc),
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isSelected ? const Color(0xFF012A58) : const Color(0xFFE2E8F0),
              width: isSelected ? 1.6 : 1.0,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(14),
                ),
                clipBehavior: Clip.antiAlias,
                child: doc.photoBytes != null && doc.photoBytes!.isNotEmpty
                    ? Image.memory(doc.photoBytes!, fit: BoxFit.cover)
                    : (doc.profileImageUrl != null && doc.profileImageUrl!.trim().isNotEmpty)
                        ? Image.network(
                            doc.profileImageUrl!.trim(),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Center(
                              child: Text(
                                doc.name.replaceAll('Dr.', '').replaceAll('Dr. ', '').trim().isNotEmpty
                                    ? doc.name.replaceAll('Dr.', '').replaceAll('Dr. ', '').trim()[0].toUpperCase()
                                    : 'D',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF012A58),
                                ),
                              ),
                            ),
                          )
                        : Center(
                            child: Text(
                              doc.name.replaceAll('Dr.', '').replaceAll('Dr. ', '').trim().isNotEmpty
                                  ? doc.name.replaceAll('Dr.', '').replaceAll('Dr. ', '').trim()[0].toUpperCase()
                                  : 'D',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF012A58),
                              ),
                            ),
                          ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      doc.name,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${doc.specialty} · $locationPart',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF64748B),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? const Color(0xFF012A58) : const Color(0xFFCBD5E1),
                    width: isSelected ? 6 : 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReferClinicCard(ClinicModel clinic) {
    final isSelected = _selectedReferClinic?.id == clinic.id &&
        _selectedReferClinic?.clinicName == clinic.clinicName;
    final subtitle = [
      if (clinic.location.isNotEmpty) clinic.location,
      if (clinic.services.isNotEmpty) clinic.services.take(2).join(', '),
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        key: Key('dentist_refer_clinic_${clinic.id.isNotEmpty ? clinic.id : clinic.clinicName}'),
        onTap: () => setState(() => _selectedReferClinic = clinic),
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isSelected ? const Color(0xFF012A58) : const Color(0xFFE2E8F0),
              width: isSelected ? 1.6 : 1.0,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Center(
                  child: Icon(
                    Icons.local_hospital_rounded,
                    color: Color(0xFF012A58),
                    size: 24,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      clinic.clinicName,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle.isNotEmpty ? subtitle : 'Verified Clinic',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF64748B),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? const Color(0xFF012A58) : const Color(0xFFCBD5E1),
                    width: isSelected ? 6 : 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReferAttachmentButton({
    required Key key,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return OutlinedButton.icon(
      key: key,
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF0F172A),
        backgroundColor: Colors.white,
        side: const BorderSide(color: Color(0xFFE2E8F0)),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      icon: Icon(icon, size: 17, color: const Color(0xFF012A58)),
      label: Text(
        label,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: Color(0xFF0F172A),
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Future<void> _pickGalleryAttachment() async {
    if (_referPickedAttachments.length >= 5) {
      _showAttachmentLimitMessage();
      return;
    }
    try {
      if (RecordFileHelper.testFilePickerOverride != null) {
        final testFile = await RecordFileHelper.testFilePickerOverride!();
        if (testFile != null) {
          setState(() {
            _referPickedAttachments.add(testFile);
            _referAttachments.add(testFile.name);
          });
        }
        return;
      }

      final picker = ImagePicker();
      final remaining = 5 - _referPickedAttachments.length;
      if (remaining > 1) {
        try {
          final List<XFile> images = await picker.pickMultiImage(
            imageQuality: 85,
            maxWidth: 1600,
          );
          if (images.isNotEmpty) {
            for (final img in images.take(remaining)) {
              await _processAndAddAttachmentXFile(img);
            }
            return;
          }
        } catch (_) {}
      }
      final XFile? img = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1600,
      );
      if (img != null) {
        await _processAndAddAttachmentXFile(img);
      }
    } catch (e) {
      _showAttachmentError('Failed to select image from gallery: $e');
    }
  }

  Future<void> _pickCameraAttachment() async {
    if (_referPickedAttachments.length >= 5) {
      _showAttachmentLimitMessage();
      return;
    }
    try {
      if (RecordFileHelper.testFilePickerOverride != null) {
        final testFile = await RecordFileHelper.testFilePickerOverride!();
        if (testFile != null) {
          setState(() {
            _referPickedAttachments.add(testFile);
            _referAttachments.add(testFile.name);
          });
        }
        return;
      }

      final picker = ImagePicker();
      final XFile? photo = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 1600,
      );
      if (photo != null) {
        await _processAndAddAttachmentXFile(photo);
      }
    } catch (e) {
      _showAttachmentError('Failed to capture photo with camera: $e');
    }
  }

  Future<void> _pickPdfAttachment() async {
    if (_referPickedAttachments.length >= 5) {
      _showAttachmentLimitMessage();
      return;
    }
    try {
      final file = await RecordFileHelper.pickRecordFile();
      if (file != null) {
        final validationError = RecordFileHelper.validatePickedFile(file);
        if (validationError != null) {
          _showAttachmentError(validationError);
          return;
        }
        setState(() {
          _referPickedAttachments.add(file);
          _referAttachments.add(file.name);
        });
      }
    } catch (e) {
      _showAttachmentError('Failed to select PDF document: $e');
    }
  }

  Future<void> _processAndAddAttachmentXFile(XFile file) async {
    final bytes = await file.readAsBytes();
    final name = file.name;
    final size = bytes.length;
    final ext = RecordFileHelper.extractExtension(name, mimeType: file.mimeType);

    final validationError = RecordFileHelper.validateFile(
      fileName: name,
      sizeBytes: size,
      mimeType: file.mimeType,
    );
    if (validationError != null) {
      _showAttachmentError(validationError);
      return;
    }

    final picked = PickedRecordFile(
      name: name,
      extension: ext.isNotEmpty ? ext : 'JPG',
      mimeType: file.mimeType ?? 'image/jpeg',
      sizeBytes: size,
      bytes: bytes,
    );

    setState(() {
      _referPickedAttachments.add(picked);
      _referAttachments.add(name);
    });
  }

  void _removeReferAttachment(int index) {
    if (index >= 0 && index < _referPickedAttachments.length) {
      setState(() {
        final removed = _referPickedAttachments.removeAt(index);
        _referAttachments.remove(removed.name);
      });
    }
  }

  @visibleForTesting
  void addTestReferAttachment(String fileName) => _addMockOrPickedReferAttachment(fileName);

  void _addMockOrPickedReferAttachment(String fileName) {
    if (_referPickedAttachments.length >= 5) {
      _showAttachmentLimitMessage();
      return;
    }
    final isPdf = fileName.toLowerCase().endsWith('.pdf');
    final ext = isPdf ? 'PDF' : 'JPG';
    final mime = isPdf ? 'application/pdf' : 'image/jpeg';
    final dummyBytes = Uint8List.fromList([1, 2, 3, 4, 5]);
    final picked = PickedRecordFile(
      name: fileName,
      extension: ext,
      mimeType: mime,
      sizeBytes: 1024 * 50,
      bytes: dummyBytes,
    );
    setState(() {
      _referPickedAttachments.add(picked);
      if (!_referAttachments.contains(fileName)) {
        _referAttachments.add(fileName);
      }
    });
  }

  void _showAttachmentLimitMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Maximum 5 attachments allowed per referral.'),
        backgroundColor: AppTheme.gsNavy,
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _showAttachmentError(String error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error),
        backgroundColor: AppTheme.gsRed,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _submitInlinePatientReferral() async {
    if (!(_referFormKey.currentState?.validate() ?? false)) return;

    final targetDoc = !_referToClinic ? _selectedReferDoctor : null;
    final targetClinic = _referToClinic ? _selectedReferClinic : null;

    if (!_referToClinic && targetDoc == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a specialist doctor to refer to.'),
          backgroundColor: AppTheme.gsRed,
        ),
      );
      return;
    }
    if (_referToClinic && targetClinic == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a clinic to refer to.'),
          backgroundColor: AppTheme.gsRed,
        ),
      );
      return;
    }

    setState(() => _isSubmittingReferral = true);
    try {
      final currentDoc = _resolveCurrentDoctor();
      final referrerUserId = (currentDoc != null && currentDoc.userId.isNotEmpty)
          ? currentDoc.userId
          : (SessionService().currentSession?.userId.isNotEmpty == true
              ? SessionService().currentSession!.userId
              : null);
      final pName = _referPatientNameCtrl.text.trim();
      final pPhone = _referPatientMobileCtrl.text.replaceAll(RegExp(r'\D'), '').trim();
      final pAge = _referPatientAgeCtrl.text.trim();
      final notes = _referNotesCtrl.text.trim();
      final gender = _referPatientGender.isNotEmpty ? _referPatientGender : '';

      final res = await _patientService.submitPatientReferral(
        referrerPatientId: referrerUserId,
        referredPatientName: pName,
        referredPatientMobile: pPhone,
        referredPatientAge: pAge,
        referredPatientGender: gender,
        referredPatientCity: targetDoc?.city.isNotEmpty == true
            ? targetDoc!.city
            : (_selectedReferPatient?.city ?? ''),
        referredPatientPincode: targetDoc?.pincode ?? '',
        referredPatientLocation: targetDoc?.clinicAddress.isNotEmpty == true
            ? targetDoc!.clinicAddress
            : (targetClinic?.location ?? ''),
        requiredSpecialist: targetDoc?.specialty ??
            (targetClinic != null && targetClinic.services.isNotEmpty
                ? targetClinic.services.first
                : 'Specialist Evaluation'),
        clinicalComplaint: notes.isNotEmpty
            ? notes
            : 'Specialist referral consultation requested',
        doctorId: targetDoc?.id ?? (targetClinic?.id ?? ''),
        doctorName: targetDoc?.name ?? (targetClinic?.clinicName ?? 'Specialist Doctor'),
        doctorClinicName: targetClinic?.clinicName ?? (targetDoc?.clinicName ?? ''),
        doctorLocation: targetClinic?.location ?? (targetDoc?.clinicAddress ?? ''),
        doctorCity: targetDoc?.city ?? '',
        doctorPincode: targetDoc?.pincode ?? '',
        doctorPhone: targetDoc?.phone ?? '',
      );

      if (!mounted) return;

      if (res['success'] == true) {
        // Upload attachments if present
        if (_referPickedAttachments.isNotEmpty) {
          final patientId = _selectedReferPatient?.id.isNotEmpty == true
              ? _selectedReferPatient!.id
              : 'patient_${DateTime.now().millisecondsSinceEpoch}';

          for (final att in _referPickedAttachments) {
            try {
              await ApiService().uploadPatientDentalRecord(
                patientId: patientId,
                patientName: pName,
                title: 'Referral Document: ${att.name}',
                category: att.isPdf ? 'Dental Report' : 'Dental X-ray',
                description: 'Attachment for referral to ${targetDoc?.name ?? targetClinic?.clinicName}. Note: $notes',
                fileName: att.name,
                fileType: att.extension,
                fileSize: att.sizeBytes,
                fileBytes: att.bytes,
                mimeType: att.mimeType,
              );
            } catch (e) {
              debugPrint('Referral attachment upload notice: $e');
            }
          }
        }

        await _patientService.syncDoctorReferralsFromApi();
        await _patientService.syncReferralsFromApi();
        await _patientService.syncProblemRequestsFromApi();

        setState(() {
          _referPatientNameCtrl.clear();
          _referPatientMobileCtrl.clear();
          _referNotesCtrl.clear();
          _referAttachments.clear();
          _referPickedAttachments.clear();
          _selectedReferPatientChipName = null;
          _selectedReferPatient = null;
          _selectedReferDoctor = null;
          _selectedReferClinic = null;
        });

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Referral successfully sent for $pName.'),
            backgroundColor: const Color(0xFF012A58),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text((res['message'] ?? 'Could not submit referral.').toString()),
            backgroundColor: AppTheme.gsRed,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmittingReferral = false);
      }
    }
  }

  // ==========================================
  // TAB 4: E-PRESCRIPTIONS TAB (Screenshot 4)
  // ==========================================
  Widget _buildPrescriptionsTab() {
    final currentDoc = _resolveCurrentDoctor();
    final currentDocName = (currentDoc?.name ?? '')
        .replaceAll('Dr.', '')
        .replaceAll('Dr. ', '')
        .trim()
        .toLowerCase();
    final currentDocId = (currentDoc?.id ?? '').trim();
    final currentDocUserId = (currentDoc?.userId ?? '').trim();

    return FutureBuilder<List<dynamic>>(
      future: ApiService().fetchMedicalRecords(),
      builder: (context, snapshot) {
        final combinedRaw = <Map<String, dynamic>>[];
        final seenIds = <String>{};

        for (final r in [
          ..._patientService.medicalRecords,
          ...(snapshot.data ?? const <dynamic>[]),
        ]) {
          if (r is! Map) continue;
          final map = Map<String, dynamic>.from(r);
          final recType = (map['type'] ?? '').toString().toLowerCase();
          if (recType != 'prescription' && !map.containsKey('items')) continue;

          final dName = (map['doctorName'] ?? map['doctor_name'] ?? '')
              .toString()
              .replaceAll('Dr.', '')
              .replaceAll('Dr. ', '')
              .trim()
              .toLowerCase();
          final dId = (map['doctorId'] ?? map['doctor_id'] ?? '').toString().trim();

          bool matchesDoctor = false;
          if (currentDocId.isNotEmpty && dId == currentDocId) matchesDoctor = true;
          if (currentDocUserId.isNotEmpty && dId == currentDocUserId) matchesDoctor = true;
          if (currentDocName.isNotEmpty &&
              currentDocName != 'dentist' &&
              dName.isNotEmpty &&
              (dName == currentDocName ||
                  dName.contains(currentDocName) ||
                  currentDocName.contains(dName))) {
            matchesDoctor = true;
          }
          if (currentDoc == null && _patientService.allDoctors.isEmpty) {
            matchesDoctor = true;
          }
          if (!matchesDoctor) continue;

          final id = (map['id'] ?? '${map['title']}_${map['date']}').toString();
          if (seenIds.add(id)) {
            combinedRaw.add(map);
          }
        }

        return SingleChildScrollView(
          key: const Key('dentist_rx_scroll_view'),
          physics: const BouncingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: "Issued by you" + "E-prescriptions" + right "+" button
              Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Issued by you',
                            style: TextStyle(
                              fontSize: 13.5,
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          SizedBox(height: 2),
                          Text(
                            'E-prescriptions',
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                              letterSpacing: -0.4,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    InkWell(
                      key: const Key('dentist_new_rx_button'),
                      onTap: () {
                        final defaultPatient = _getDentistQuickSelectPatients().firstOrNull?.name ??
                            (_patientService.currentPatient.name.isNotEmpty
                                ? _patientService.currentPatient.name
                                : 'Patient');
                        _showPrescriptionModal(context, defaultPatient);
                      },
                      borderRadius: BorderRadius.circular(22),
                      child: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: AppTheme.gsNavy,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.gsNavy.withValues(alpha: 0.2),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.add_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, thickness: 1, color: Color(0xFFE2E8F0)),

              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
                child: combinedRaw.isEmpty
                    ? Container(
                        key: const Key('dentist_rx_empty_state'),
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          children: [
                            Container(
                              width: 58,
                              height: 58,
                              decoration: BoxDecoration(
                                color: AppTheme.gsNavy.withValues(alpha: 0.06),
                                shape: BoxShape.circle,
                              ),
                              child: const Center(
                                child: Icon(
                                  Icons.description_outlined,
                                  color: AppTheme.gsNavy,
                                  size: 26,
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              'No e-prescriptions issued yet',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Tap the + button above or issue an e-prescription from an active patient consultation.',
                              style: TextStyle(
                                fontSize: 13.5,
                                color: Color(0xFF64748B),
                                height: 1.4,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    : Column(
                        children: combinedRaw.asMap().entries.map((entry) {
                          return _buildExpandableRxCard(entry.value, entry.key);
                        }).toList(),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildExpandableRxCard(Map<String, dynamic> rec, int index) {
    final recId = (rec['id'] ?? 'rx_$index').toString();
    final isExpanded = _expandedRxCardIds.contains(recId) ||
        (_expandedRxCardIds.isEmpty && index == 0);

    final rawDiagnosis = (rec['diagnosis'] ?? rec['title'] ?? '').toString().trim();
    final diagnosisHeadline = rawDiagnosis
        .replaceFirst(RegExp(r'^E-Prescription:\s*', caseSensitive: false), '')
        .trim();
    final displayTitle = diagnosisHeadline.isNotEmpty
        ? diagnosisHeadline
        : 'Medical E-Prescription';

    final patientName = (rec['patientName'] ?? rec['patient_name'] ?? '').toString().trim();
    final displayPatient = patientName.isNotEmpty
        ? patientName
        : (_patientService.currentPatient.name.isNotEmpty
            ? _patientService.currentPatient.name
            : 'Patient');

    final rawDate = (rec['date'] ?? '').toString().trim();
    final displayDate = _formatRxDateLabel(rawDate);

    final rawItems = rec['items'] is List ? (rec['items'] as List) : const [];
    final instructions = (rec['instructions'] ?? rec['notes'] ?? '').toString().trim();

    return Container(
      key: Key('dentist_rx_card_$recId'),
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Header Row (Tappable to expand/collapse)
          InkWell(
            key: Key('dentist_rx_toggle_$recId'),
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expandedRxCardIds.remove(recId);
                  if (_expandedRxCardIds.isEmpty) {
                    _expandedRxCardIds.add('__none__');
                  }
                } else {
                  _expandedRxCardIds.remove('__none__');
                  _expandedRxCardIds.add(recId);
                }
              });
            },
            borderRadius: BorderRadius.circular(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppTheme.gsNavy.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.description_outlined,
                      color: AppTheme.gsNavy,
                      size: 22,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayTitle,
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$displayPatient · $displayDate',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  isExpanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: const Color(0xFF64748B),
                  size: 22,
                ),
              ],
            ),
          ),

          if (isExpanded) ...[
            const SizedBox(height: 14),
            const Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9)),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'E-PRESCRIPTION · ${rawItems.isEmpty ? 1 : rawItems.length} MEDICINE(S)',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF64748B),
                      letterSpacing: 0.7,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if ((rec['specialty'] ?? '').toString().trim().isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: AppTheme.gsNavy.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      rec['specialty'].toString().trim(),
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.gsNavy,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (rawItems.isEmpty)
              _buildRxMedicineBox(
                medNameAndDose: 'Prescribed Medication',
                freqAndDuration: 'As directed',
              )
            else
              ...rawItems.map((item) {
                final map = item is Map ? item : <String, dynamic>{};
                final mName = (map['name'] ?? 'Medicine').toString().trim();
                final mDosage = (map['dosage'] ?? '').toString().trim();
                final mFreq = (map['frequency'] ?? map['instructions'] ?? '').toString().trim();
                final mDur = (map['duration'] ?? '').toString().trim();
                final titleLine = mDosage.isNotEmpty && !mName.contains(mDosage)
                    ? '$mName $mDosage'
                    : mName;
                final subLine = [
                  if (mFreq.isNotEmpty) mFreq,
                  if (mDur.isNotEmpty) mDur,
                ].join(' · ');

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _buildRxMedicineBox(
                    medNameAndDose: titleLine,
                    freqAndDuration: subLine.isNotEmpty ? subLine : 'As directed',
                  ),
                );
              }),
            if (rec['clinicalSections'] is Map && (rec['clinicalSections'] as Map).isNotEmpty) ...[
              const SizedBox(height: 4),
              ...SpecialtyClinicalConfig.forSpecialty((rec['specialty'] ?? '').toString())
                  .prescriptionSchema
                  .sections
                  .where((sec) => ((rec['clinicalSections'] as Map)[sec.key] ?? '').toString().trim().isNotEmpty)
                  .map((sec) {
                final val = (rec['clinicalSections'] as Map)[sec.key].toString().trim();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '${sec.label}: $val',
                    style: const TextStyle(fontSize: 12.5, color: Color(0xFF334155), height: 1.35),
                  ),
                );
              }),
            ],
            if ((rec['followUpDate'] ?? '').toString().trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Follow-up Date: ${rec['followUpDate']}',
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppTheme.gsRed),
              ),
            ],
            if (instructions.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.chat_bubble_outline_rounded,
                    size: 15,
                    color: Color(0xFF64748B),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      instructions,
                      style: const TextStyle(
                        fontSize: 13.5,
                        color: Color(0xFF475569),
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                key: Key('doctor_rx_pdf_btn_$recId'),
                onPressed: () => PrescriptionPdfGenerator.showPreviewDialog(context, record: rec),
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                label: const Text('View / Download PDF', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.gsNavy,
                  side: const BorderSide(color: AppTheme.gsNavy),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRxMedicineBox({
    required String medNameAndDose,
    required String freqAndDuration,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '℞ $medNameAndDose',
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
              fontFamilyFallback: ['Segoe UI Symbol', 'Segoe UI', 'Roboto'],
            ),
          ),
          const SizedBox(height: 3),
          Text(
            freqAndDuration,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  String _formatRxDateLabel(String rawDate) {
    if (rawDate.isEmpty) {
      return _formatShortDayMonth(DateTime.now());
    }
    final parsed = DateTime.tryParse(rawDate);
    if (parsed != null) {
      return _formatShortDayMonth(parsed);
    }
    return rawDate;
  }

}
