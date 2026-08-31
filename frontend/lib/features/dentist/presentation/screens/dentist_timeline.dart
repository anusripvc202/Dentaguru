import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/denta_guru_logo.dart';
import '../../../../core/services/patient_problem_service.dart';
import '../../../../core/services/api_service.dart';
import '../../../../core/services/session_service.dart';
import '../../../../core/widgets/dental_ads_banner.dart';
import '../../../../core/widgets/whatsapp_chat_modal.dart';
import '../../../../core/models/referral_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DentistTimelineScreen extends StatefulWidget {
  const DentistTimelineScreen({super.key});

  @override
  State<DentistTimelineScreen> createState() => _DentistTimelineScreenState();
}

class _DentistTimelineScreenState extends State<DentistTimelineScreen> with TickerProviderStateMixin {
  int _currentIndex = 0;
  final PatientProblemService _patientService = PatientProblemService();

  Timer? _autoSyncTimer;
  RealtimeChannel? _realtimeChannel;

  late AnimationController _entryController;
  late AnimationController _pulseController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _pulseScaleAnimation;

  String _doctorReferralFilter = 'All';

  @override
  void initState() {
    super.initState();
    _patientService.addListener(_onServiceUpdate);
    _patientService.setDentistMode(true);
    _patientService.syncAllDataFromApi();
    _patientService.syncDoctorReferralsFromApi();
    _patientService.syncNotificationsFromApi(role: 'Dentist');

    // ⏱️ Auto-sync polling timer (every 4s) to catch assigned patients & direct referrals immediately
    _autoSyncTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted) {
        _patientService.syncProblemRequestsFromApi();
        _patientService.syncDentistAssignedRequestsFromApi();
        _patientService.syncDoctorReferralsFromApi();
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
            table: 'referrals',
            callback: (payload) {
              debugPrint('⚡ Realtime update on referrals for Dentist: ${payload.eventType}');
              if (mounted) {
                _patientService.syncDoctorReferralsFromApi();
                _patientService.syncNotificationsFromApi(role: 'Dentist');
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

    _fadeAnimation = CurvedAnimation(
      parent: _entryController,
      curve: Curves.easeOut,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entryController,
      curve: Curves.easeOutCubic,
    ));

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    _pulseScaleAnimation = Tween<double>(begin: 0.94, end: 1.06).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _entryController.forward();
  }

  @override
  void dispose() {
    _autoSyncTimer?.cancel();
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
    if (mounted) {
      setState(() {});
    }
  }

  void _showUpdateMyFeeAndSlotsDialog(BuildContext context) {
    final authUser = Supabase.instance.client.auth.currentUser;
    final currentDoc = _patientService.currentDoctor ?? (
      authUser != null ? DoctorModel(
        id: authUser.id,
        name: authUser.userMetadata?['name'] ?? 'Doctor',
        email: authUser.email ?? '',
        phone: '',
        specialty: 'General Dentistry',
        qualification: 'BDS, MDS',
        experienceYears: 5,
        rating: 5.0,
        reviewCount: 0,
        clinicName: 'Dental Practice',
        status: 'Available',
        nextAvailableSlots: ['Today, 2:00 PM'],
        consultationFee: '\$75',
      ) : null
    );
    final feeCtrl = TextEditingController(text: currentDoc?.consultationFee ?? '\$75');
    final slotCtrl = TextEditingController(
      text: (currentDoc?.nextAvailableSlots.isNotEmpty == true) ? currentDoc!.nextAvailableSlots.first : 'Today, 2:00 PM',
    );

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.edit_calendar_rounded, color: AppTheme.primaryBlue, size: 22),
              SizedBox(width: 8),
              Text('Update My Fee & Time Slots', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: feeCtrl,
                decoration: InputDecoration(
                  labelText: 'My Consultation Fee',
                  hintText: 'e.g. \$85',
                  prefixIcon: const Icon(Icons.payments_outlined),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: slotCtrl,
                decoration: InputDecoration(
                  labelText: 'Next Available Time Slot',
                  hintText: 'e.g. Today, 4:00 PM',
                  prefixIcon: const Icon(Icons.access_time_rounded),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogCtx).pop(), child: const Text('Cancel')),
            ElevatedButton.icon(
              icon: const Icon(Icons.check_circle_rounded, size: 16),
              label: const Text('Save & Publish', style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                final docId = currentDoc?.id ?? (authUser?.id ?? '');
                _patientService.updateDoctorFeeAndSlots(
                  doctorId: docId,
                  consultationFee: feeCtrl.text.trim(),
                  availableSlot: slotCtrl.text.trim(),
                );
                Navigator.of(dialogCtx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('🎉 Your fee is now ${feeCtrl.text.trim()} & slot updated to ${slotCtrl.text.trim()}!'),
                    backgroundColor: const Color(0xFF10B981),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  void _showAcceptAndScheduleModal(BuildContext context, PatientConsultationRequest req) {
    final currentDoc = _patientService.currentDoctor;
    final defaultSlot = currentDoc?.nextAvailableSlots.isNotEmpty == true
        ? currentDoc!.nextAvailableSlots.first
        : 'Today, 2:30 PM';
    final slotCtrl = TextEditingController(text: req.confirmedTimeSlot ?? defaultSlot);

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.event_available_rounded, color: Color(0xFF10B981), size: 24),
              SizedBox(width: 8),
              Text('Accept & Set Time Slot', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Patient: ${req.patientName}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              Text('Category: ${req.problemCategory}', style: const TextStyle(fontSize: 12, color: AppTheme.primaryBlue)),
              const SizedBox(height: 14),
              TextField(
                controller: slotCtrl,
                decoration: InputDecoration(
                  labelText: 'Set Confirmed Time Slot',
                  hintText: 'e.g. Today, 3:30 PM',
                  prefixIcon: const Icon(Icons.access_time_filled_rounded, color: AppTheme.primaryBlue),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.check_circle_rounded, size: 16),
              label: const Text('Confirm & Save Slot', style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                final chosenSlot = slotCtrl.text.trim().isNotEmpty ? slotCtrl.text.trim() : 'Today, 2:30 PM';

                debugPrint('[ACCEPT] Button clicked');
                debugPrint('[ACCEPT] Referral ID: ${req.id}');
                debugPrint('[ACCEPT] Patient ID: ${req.patientId}');
                debugPrint('[ACCEPT] Dentist ID: ${req.assignedDoctorId ?? ""}');

                await _patientService.acceptReferralByDentist(req.id, timeSlot: chosenSlot);

                if (dialogCtx.mounted) Navigator.of(dialogCtx).pop();

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('🎉 Accepted ${req.patientName}\'s consultation for $chosenSlot!'),
                      backgroundColor: const Color(0xFF10B981),
                    ),
                  );
                }
              },
            ),
          ],
        );
      },
    );
  }



  void _showPrescriptionModal(BuildContext context, dynamic reqOrName) {
    final String pName = reqOrName is PatientConsultationRequest ? reqOrName.patientName : reqOrName.toString();
    final diagnosisController = TextEditingController(text: reqOrName is PatientConsultationRequest ? reqOrName.problemCategory : 'Dental Evaluation');
    final medController = TextEditingController(text: 'Amoxicillin 500mg');
    final dosageController = TextEditingController(text: '1 Capsule every 8 hours');
    final frequencyController = TextEditingController(text: 'Twice Daily (1-0-1)');
    final durationController = TextEditingController(text: '7 Days');
    final notesController = TextEditingController(text: 'Take after meals with plenty of water.');

    showDialog(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.receipt_long_rounded, color: Color(0xFF10B981), size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Issue E-Prescription', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: AppTheme.textDark)),
                            Text('Patient: $pName', style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: diagnosisController,
                    decoration: InputDecoration(
                      labelText: 'Clinical Diagnosis',
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: medController,
                    decoration: InputDecoration(
                      labelText: 'Medication Name & Strength',
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: dosageController,
                          decoration: InputDecoration(
                            labelText: 'Dosage',
                            filled: true,
                            fillColor: const Color(0xFFF8FAFC),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: frequencyController,
                          decoration: InputDecoration(
                            labelText: 'Frequency',
                            filled: true,
                            fillColor: const Color(0xFFF8FAFC),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: durationController,
                    decoration: InputDecoration(
                      labelText: 'Duration',
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: notesController,
                    decoration: InputDecoration(
                      labelText: 'Instructions / Additional Notes',
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 18),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.check_circle_rounded, size: 18),
                    label: const Text('Send Digital E-Prescription to Patient', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () async {
                      final diagnosis = diagnosisController.text.trim();
                      final medName = medController.text.trim();
                      final dosage = dosageController.text.trim();
                      final freq = frequencyController.text.trim();
                      final duration = durationController.text.trim();
                      final notes = notesController.text.trim();

                      final newRecord = {
                        'id': 'REC-${DateTime.now().millisecondsSinceEpoch}',
                        'patient_id': pName,
                        'type': 'prescription',
                        'title': 'Digital Prescription Slips',
                        'subtitle': 'Diagnosis: ${diagnosis.isNotEmpty ? diagnosis : "Dental Care"} (${medName.isNotEmpty ? medName : "Medication"})',
                        'doctorName': _patientService.currentDoctor?.name ?? 'Attending Dentist',
                        'clinicName': _patientService.currentDoctor?.clinicName ?? 'DentaGuru Dental Clinic',
                        'date': DateTime.now().toString().split(' ').first,
                        'items': [
                          {
                            'name': medName.isNotEmpty ? medName : 'Amoxicillin 500mg',
                            'dosage': dosage.isNotEmpty ? dosage : '1 Capsule',
                            'frequency': freq.isNotEmpty ? freq : 'Twice Daily',
                            'duration': duration.isNotEmpty ? duration : '7 Days',
                            'instructions': notes,
                            'status': 'Active',
                          }
                        ],
                      };

                      _patientService.addMedicalRecord(newRecord);

                      await ApiService().createMedicalRecord(
                        patientId: pName,
                        type: 'prescription',
                        title: 'Digital Prescription Slips',
                        subtitle: 'Diagnosis: ${diagnosis.isNotEmpty ? diagnosis : "Dental Care"} (${medName.isNotEmpty ? medName : "Medication"})',
                        doctorName: _patientService.currentDoctor?.name ?? 'Attending Dentist',
                        clinicName: _patientService.currentDoctor?.clinicName ?? 'DentaGuru Dental Clinic',
                        items: [
                          {
                            'name': medName.isNotEmpty ? medName : 'Amoxicillin 500mg',
                            'dosage': dosage.isNotEmpty ? dosage : '1 Capsule',
                            'frequency': freq.isNotEmpty ? freq : 'Twice Daily',
                            'duration': duration.isNotEmpty ? duration : '7 Days',
                            'instructions': notes,
                            'status': 'Active',
                          }
                        ],
                      );

                      // Dispatch notification to Patient
                      _patientService.addNotification(
                        recipientRole: 'Patient',
                        recipientId: pName,
                        title: '💊 New E-Prescription Issued!',
                        message: 'Dr. ${_patientService.currentDoctor?.name ?? "Attending Dentist"} has issued an E-Prescription for $diagnosis.',
                      );

                      if (context.mounted) {
                        Navigator.of(dialogContext).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('💊 Digital E-Prescription issued to $pName! Live in Patient Health Locker.'),
                            backgroundColor: const Color(0xFF10B981),
                            duration: const Duration(seconds: 3),
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showDoctorChatModal(BuildContext context, String patientName, String roomId) {
    final doctor = _patientService.currentDoctor;
    WhatsAppChatModal.show(
      context,
      patientName: patientName,
      doctorName: doctor?.name ?? 'Doctor',
      currentUserRole: 'Dentist',
      doctorId: doctor?.id,
    );
  }

  void _showNotificationsModal(BuildContext context, String role) {
    _patientService.syncNotificationsFromApi(role: role);

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final notifs = _patientService.appNotifications.where((n) => n.recipientRole == role || n.recipientRole == 'ALL').toList();
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
                              iconColor = const Color(0xFF6366F1);
                            } else if (n.title.toLowerCase().contains('consultation') || n.title.toLowerCase().contains('assigned')) {
                              itemIcon = Icons.medical_services_rounded;
                              iconColor = const Color(0xFF0284C7);
                            } else if (n.title.toLowerCase().contains('prescription')) {
                              itemIcon = Icons.receipt_long_rounded;
                              iconColor = const Color(0xFF10B981);
                            }

                            return InkWell(
                              onTap: () async {
                                if (isUnread) {
                                  await _patientService.markNotificationRead(n.id);
                                  setModalState(() {});
                                }
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isUnread ? const Color(0xFFF0F9FF) : const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isUnread ? const Color(0xFFBAE6FD) : const Color(0xFFE2E8F0),
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
                                                    color: isUnread ? const Color(0xFF0369A1) : AppTheme.textDark,
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
                                                    color: const Color(0xFF0284C7),
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
      backgroundColor: AppTheme.softBlueBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        shadowColor: Colors.black.withValues(alpha: 0.05),
        automaticallyImplyLeading: false,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            DentaGuruLogo(height: 36),
            SizedBox(height: 2),
            Text(
              'Dentist Practitioner Workspace',
              style: TextStyle(fontSize: 10, color: AppTheme.textMuted, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Row(
              children: [
                Builder(
                  builder: (context) {
                    final notifs = _patientService.appNotifications.where((n) => n.recipientRole == 'Dentist' || n.recipientRole == 'ALL').toList();
                    final unreadCount = notifs.where((n) => !n.isRead).length;

                    return Stack(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.notifications_none_rounded, color: AppTheme.textDark, size: 24),
                          onPressed: () => _showNotificationsModal(context, 'Dentist'),
                        ),
                        if (unreadCount > 0)
                          Positioned(
                            right: 6,
                            top: 6,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(color: Color(0xFFEF4444), shape: BoxShape.circle),
                              child: Text(
                                '$unreadCount',
                                style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.logout_rounded, color: Color(0xFFEF4444), size: 22),
                  tooltip: 'Log Out',
                  onPressed: () async {
                    await SessionService().clearSession();
                    await _patientService.clearAllDataAndStorage();
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Logged out of Dentist workspace.'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                    context.go('/login');
                  },
                ),
              ],
            ),
          ),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: _buildCurrentTab(),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
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
          selectedItemColor: AppTheme.primaryBlue,
          unselectedItemColor: AppTheme.textMuted,
          selectedFontSize: 12,
          unselectedFontSize: 12,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold),
          onTap: (index) => setState(() => _currentIndex = index),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.dashboard_outlined),
              activeIcon: Icon(Icons.dashboard_rounded, color: AppTheme.primaryBlue),
              label: 'Timeline',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.people_outline_rounded),
              activeIcon: Icon(Icons.people_rounded, color: AppTheme.primaryBlue),
              label: 'Patients',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.receipt_long_outlined),
              activeIcon: Icon(Icons.receipt_long_rounded, color: AppTheme.primaryBlue),
              label: 'Prescriptions',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.bar_chart_rounded),
              activeIcon: Icon(Icons.bar_chart_rounded, color: AppTheme.primaryBlue),
              label: 'Analytics',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentTab() {
    switch (_currentIndex) {
      case 0:
        return _buildDashboardTab();
      case 1:
        return _buildPatientsTab();
      case 2:
        return _buildPrescriptionsTab();
      case 3:
        return _buildAnalyticsTab();
      default:
        return _buildDashboardTab();
    }
  }

  // ==========================================
  // TAB 1: DENTIST TIMELINE & QUEUE DASHBOARD
  // ==========================================
  Widget _buildDashboardTab() {
    var currentDoc = _patientService.currentDoctor;
    final authUser = Supabase.instance.client.auth.currentUser;
    if (authUser != null && authUser.email != null && authUser.email!.isNotEmpty) {
      final authEmailLower = authUser.email!.toLowerCase();
      final authName = (authUser.userMetadata?['name'] ?? '').toString().toLowerCase();
      final match = _patientService.allDoctors.where(
        (d) => d.email.toLowerCase() == authEmailLower ||
            (d.id.isNotEmpty && d.id == authUser.id) ||
            (d.userId.isNotEmpty && d.userId == authUser.id) ||
            (authName.isNotEmpty && d.name.toLowerCase().contains(authName)),
      ).firstOrNull;
      if (match != null) {
        currentDoc = match;
        _patientService.currentDoctor = currentDoc;
      }
    }

    final currentDocName = (currentDoc?.name ?? '').replaceAll('Dr.', '').replaceAll('Dr. ', '').trim().toLowerCase();
    final currentDocId = (currentDoc?.id ?? '').trim();
    final currentDocUserId = (currentDoc?.userId ?? '').trim();
    final currentDocEmail = (currentDoc?.email ?? '').trim().toLowerCase();
    final authUserId = (authUser?.id ?? '').trim();
    final authEmail = (authUser?.email ?? '').trim().toLowerCase();

    final myDoctorIds = <String>{
      if (currentDocId.isNotEmpty) currentDocId,
      if (currentDocUserId.isNotEmpty) currentDocUserId,
      if (authUserId.isNotEmpty) authUserId,
      if (currentDocEmail.isNotEmpty) currentDocEmail,
      if (authEmail.isNotEmpty) authEmail,
    };

    for (final d in _patientService.allDoctors) {
      if (myDoctorIds.contains(d.id) || (d.userId.isNotEmpty && myDoctorIds.contains(d.userId)) || (d.email.isNotEmpty && myDoctorIds.contains(d.email.toLowerCase()))) {
        if (d.id.isNotEmpty) myDoctorIds.add(d.id);
        if (d.userId.isNotEmpty) myDoctorIds.add(d.userId);
        if (d.email.isNotEmpty) myDoctorIds.add(d.email.toLowerCase());
      }
    }

    bool isAssignedToMe(PatientConsultationRequest r) {
      final aId = r.assignedDoctorId?.trim();
      if (aId != null && aId.isNotEmpty && myDoctorIds.contains(aId)) {
        return true;
      }
      
      final aName = r.assignedDoctorName?.replaceAll('Dr.', '').replaceAll('Dr. ', '').trim().toLowerCase();
      if (currentDocName.isNotEmpty &&
          aName != null && aName.isNotEmpty && (aName == currentDocName || currentDocName.contains(aName) || aName.contains(currentDocName))) {
        return true;
      }
      return false;
    }

    final Map<String, PatientConsultationRequest> uniqueMap = {};

    // 1. Add all requests assigned directly to this dentist from backend
    for (final r in _patientService.dentistAssignedRequests) {
      if (r.id.isNotEmpty) {
        final key = (r.id.startsWith('PR-'))
            ? '${r.patientName.trim().toLowerCase()}_${r.problemCategory.trim().toLowerCase()}'
            : r.id;
        uniqueMap[key] = r;
      }
    }

    // 2. Cross-reference general requests only if assigned to this specific doctor
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

    final requests = uniqueMap.values.toList();

    final docName = currentDoc?.name ?? 'Dentist Practitioner';
    final docSpecialty = currentDoc?.specialty ?? 'Dental Specialist';
    final clinicName = currentDoc?.clinicName ?? 'Registered Clinic';
    final photoBytes = currentDoc?.photoBytes;
    final docPhone = currentDoc?.phone ?? '';
    final docEmail = currentDoc?.email ?? '';
    final docCity = currentDoc?.city ?? '';
    final docPincode = currentDoc?.pincode ?? '';
    final docLanguages = (currentDoc?.languages != null && currentDoc!.languages.isNotEmpty) ? currentDoc.languages.join(', ') : 'English';

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Doctor Profile Greeting Banner
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: AppTheme.brandOrange, width: 2),
                          ),
                          child: photoBytes != null
                              ? CircleAvatar(
                                  radius: 24,
                                  backgroundImage: MemoryImage(photoBytes),
                                )
                              : const CircleAvatar(
                                  radius: 24,
                                  backgroundColor: AppTheme.primaryBlue,
                                  child: Text('DR', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                                ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                docName,
                                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppTheme.brandOrange.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      docSpecialty,
                                      style: const TextStyle(fontSize: 10, color: AppTheme.brandOrange, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      '• $clinicName',
                                      style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_calendar_rounded, color: Colors.white, size: 22),
                          tooltip: 'Update Consultation Fee & Available Slots',
                          onPressed: () => _showUpdateMyFeeAndSlotsDialog(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Mobile: ${docPhone.isNotEmpty ? docPhone : "Not provided"} • City: ${docCity.isNotEmpty ? docCity : "Not provided"} • PIN: ${docPincode.isNotEmpty ? docPincode : "Not provided"} • Languages: $docLanguages • Email: ${docEmail.isNotEmpty ? docEmail : "Not provided"}',
                              style: const TextStyle(fontSize: 10.5, color: Colors.white70),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // 2. Animated Practice Stat Boxes Row
              Builder(
                builder: (context) {
                  final doctorRefs = _patientService.doctorReceivedPatientReferrals;
                  final displayCount = requests.length + doctorRefs.length;
                  final pendingCount = requests.where((r) => r.status == 'Doctor Suggested' || r.status == 'Pending' || r.status == 'Doctor Assigned').length +
                      doctorRefs.where((r) => r.status == 'Pending').length;

                  return Row(
                    children: [
                      _buildQuickStatBox(
                        icon: Icons.groups_rounded,
                        count: '$displayCount',
                        label: "Patient Consultations",
                        accentColor: AppTheme.primaryBlue,
                      ),
                      const SizedBox(width: 10),
                      _buildQuickStatBox(
                        icon: Icons.receipt_long_rounded,
                        count: '$pendingCount',
                        label: 'Pending My Accept',
                        accentColor: const Color(0xFF10B981),
                      ),
                      const SizedBox(width: 10),
                      _buildQuickStatBox(
                        icon: Icons.star_rounded,
                        count: '${currentDoc?.rating ?? 5.0} ⭐',
                        label: 'Satisfaction',
                        accentColor: AppTheme.brandOrange,
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),

              // ── HERO ADS SECTION (GSI Implants Featured Partner) ──────
              const DentalAdsBanner(isDentist: true, firstSlideOnly: true),
              const SizedBox(height: 20),

              // 3. Quick Practitioner Actions Bar
              const Text('Practitioner Tools', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textDark)),
              const SizedBox(height: 10),

              Row(
                children: [
                  _buildActionChip(
                    icon: Icons.receipt_long_rounded,
                    title: 'New E-Prescription',
                    color: const Color(0xFF10B981),
                    onTap: () => _showPrescriptionModal(context, requests.isNotEmpty ? requests.first.patientName : 'Patient'),
                  ),
                  const SizedBox(width: 10),
                  _buildActionChip(
                    icon: Icons.view_in_ar_rounded,
                    title: '3D Teeth Logger',
                    color: AppTheme.brandOrange,
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('🦷 Opening 3D Teeth Mapping Logger...')),
                      );
                    },
                  ),
                  const SizedBox(width: 10),
                  _buildActionChip(
                    icon: Icons.local_hospital_rounded,
                    title: 'Queue Filter',
                    color: AppTheme.primaryBlue,
                    onTap: () {},
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // 4. Section: Admin Assigned Patients Stream
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Admin Assigned Patients', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textDark)),
                  ScaleTransition(
                    scale: _pulseScaleAnimation,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.sensors_rounded, size: 12, color: Color(0xFF10B981)),
                          SizedBox(width: 4),
                          Text('LIVE SYNC', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              Builder(
                builder: (context) {
                  final sortedRequests = requests;

                  if (sortedRequests.isEmpty) {
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFEEF2F6)),
                      ),
                      child: const Column(
                        children: [
                          Icon(Icons.person_search_rounded, size: 36, color: Colors.grey),
                          SizedBox(height: 8),
                          Text('No Patients Assigned Yet', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          SizedBox(height: 4),
                          Text(
                            'Patients assigned by Admin will appear here.',
                            style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    );
                  }

                  return Column(
                    children: sortedRequests.map<Widget>((req) {
                      final bool isConfirmed = req.status == 'Confirmed' || req.status == 'Accepted' || req.status == 'DENTIST_ACCEPTED';

                      return Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: isConfirmed ? const Color(0xFF10B981) : const Color(0xFF0284C7), width: 1.5),
                          boxShadow: [
                            BoxShadow(
                              color: (isConfirmed ? const Color(0xFF10B981) : const Color(0xFF0284C7)).withValues(alpha: 0.08),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 1. Header row: Title + Status Badge
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Row(
                                    children: [
                                      Icon(
                                        isConfirmed ? Icons.verified_user_rounded : Icons.assignment_ind_rounded,
                                        size: 18,
                                        color: isConfirmed ? const Color(0xFF10B981) : const Color(0xFF0284C7),
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          isConfirmed ? 'Active Patient ✓' : 'Admin Assigned Patient',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                            color: isConfirmed ? const Color(0xFF15803D) : AppTheme.textDark,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isConfirmed
                                        ? const Color(0xFFDCFCE7)
                                        : (req.severity == 'Severe' ? Colors.red.shade100 : Colors.orange.shade100),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    isConfirmed ? '🟢 Accepted by You' : '⏳ Pending Acceptance',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: isConfirmed
                                          ? const Color(0xFF15803D)
                                          : (req.severity == 'Severe' ? Colors.red.shade900 : Colors.orange.shade900),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 20),

                            // 2. Patient Name
                            Text(
                              (req.patientName.contains('-') && req.patientName.length > 20)
                                  ? (_patientService.currentPatient.name.isNotEmpty ? _patientService.currentPatient.name : 'Patient')
                                  : req.patientName,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textDark),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text('📌 Category: ${req.problemCategory}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue)),
                            const SizedBox(height: 4),
                            Text('Symptoms: "${req.problemDescription}"', style: const TextStyle(fontSize: 12, color: AppTheme.textMedium, height: 1.35)),

                            if (req.adminNotes != null && req.adminNotes!.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text('📝 Admin Note: ${req.adminNotes}', style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: AppTheme.textMuted)),
                            ],

                            // Location with City & Pincode
                            Builder(
                              builder: (_) {
                                final locParts = <String>[];
                                if (req.city.isNotEmpty) locParts.add('City: ${req.city}');
                                if (req.pincode.isNotEmpty) locParts.add('Pincode: ${req.pincode}');
                                if (req.state.isNotEmpty) locParts.add(req.state);
                                final displayLoc = locParts.isNotEmpty
                                    ? locParts.join(' • ')
                                    : (req.preferredLocation.isNotEmpty ? req.preferredLocation : 'Hyderabad');
                                return Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Icon(Icons.location_on_rounded, size: 14, color: AppTheme.primaryBlue),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          '📍 $displayLoc',
                                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.textMedium),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),

                            const SizedBox(height: 12),

                            if (isConfirmed) ...[
                              // Consultation Slot Info Badge
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                margin: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF0FDF4),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: const Color(0xFF86EFAC)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.event_available_rounded, size: 16, color: Color(0xFF16A34A)),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Consultation: ${req.confirmedTimeSlot ?? "Today, 4:00 PM"}',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF15803D)),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // Action Buttons AFTER Acceptance: [ 💬 Chat with Patient ] [ 📝 E-Prescription ]
                              Row(
                                children: [
                                  Expanded(
                                    child: SizedBox(
                                      height: 44,
                                      child: OutlinedButton.icon(
                                        icon: const Icon(Icons.chat_rounded, size: 15),
                                        label: const Text('💬 Chat with Patient', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: AppTheme.primaryBlue,
                                          side: const BorderSide(color: AppTheme.primaryBlue, width: 1.5),
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        ),
                                        onPressed: () {
                                          final docName = _patientService.currentDoctor?.name ?? 'DOCTOR';
                                          final rId = ApiService.getChatRoomId(patientIdOrName: req.patientName, dentistIdOrName: docName);
                                          _showDoctorChatModal(context, req.patientName, rId);
                                        },
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: SizedBox(
                                      height: 44,
                                      child: ElevatedButton.icon(
                                        icon: const Icon(Icons.receipt_long_rounded, size: 15),
                                        label: const Text('📝 E-Prescription', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF10B981),
                                          foregroundColor: Colors.white,
                                          elevation: 1,
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        ),
                                        onPressed: () => _showPrescriptionModal(context, req),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ] else ...[
                              // Action Buttons BEFORE Acceptance: [ Decline Referral ] [ Accept & Set Slot ]
                              Row(
                                children: [
                                  Expanded(
                                    child: SizedBox(
                                      height: 42,
                                      child: OutlinedButton.icon(
                                        icon: const Icon(Icons.close_rounded, size: 14, color: Color(0xFFEF4444)),
                                        label: const Text('Decline Referral', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFFEF4444)), maxLines: 1, overflow: TextOverflow.ellipsis),
                                        style: OutlinedButton.styleFrom(
                                          side: const BorderSide(color: Color(0xFFEF4444)),
                                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                        ),
                                        onPressed: () {
                                          _patientService.declineReferralByDentist(req.id);
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text('⚠️ Declined referral for ${req.patientName}. Returned to Admin pool.'),
                                              backgroundColor: const Color(0xFFEF4444),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: SizedBox(
                                      height: 42,
                                      child: ElevatedButton.icon(
                                        icon: const Icon(Icons.event_available_rounded, size: 14),
                                        label: const Text('Accept & Set Slot', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF10B981),
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                        ),
                                        onPressed: () => _showAcceptAndScheduleModal(context, req),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
              const SizedBox(height: 20),

              // 4b. Direct Patient Referrals Section
              _buildDoctorPatientReferralsSection(),
              const SizedBox(height: 24),

              // ── BOTTOM ADS SECTION (Single-card auto-transition under Admin Assigned Patients) ──
              const DentalAdsBanner(isDentist: true, remainingSlidesOnly: true),
              const SizedBox(height: 24),

              // 5. Daily Consultation Timeline Queue
              const Text("Today's Patient Schedule", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textDark)),
              const SizedBox(height: 12),

              Builder(
                builder: (context) {
                  final acceptedForMe = requests.where((req) {
                    final statusLower = req.status.trim().toLowerCase();
                    return statusLower == 'confirmed' ||
                        statusLower == 'accepted' ||
                        statusLower.contains('accept') ||
                        statusLower.contains('confirm');
                  }).toList();

                  if (acceptedForMe.isEmpty) {
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFEEF2F6)),
                      ),
                      child: const Center(
                        child: Text('No accepted appointments scheduled in queue for today.', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                      ),
                    );
                  }

                  return Column(
                    children: acceptedForMe.map((req) {
                      final slot = (req.confirmedTimeSlot != null && req.confirmedTimeSlot!.trim().isNotEmpty)
                          ? req.confirmedTimeSlot!
                          : 'Today, 3:00 PM';
                      return _buildTimelineNode(
                        req: req,
                        time: slot,
                      );
                    }).toList(),
                  );
                },
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickStatBox({
    required IconData icon,
    required String count,
    required String label,
    required Color accentColor,
  }) {
    return Expanded(
      child: Container(
        constraints: const BoxConstraints(minHeight: 112),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: accentColor, size: 16),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                count,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: accentColor),
              ),
            ),
            const SizedBox(height: 2),
            Flexible(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 9.5, color: AppTheme.textMuted, fontWeight: FontWeight.w600, height: 1.1),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionChip({
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 96),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 17),
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, height: 1.1, color: AppTheme.textDark),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTimelineNode({
    required PatientConsultationRequest req,
    required String time,
  }) {
    final patientName = (req.patientName.contains('-') && req.patientName.length > 20)
        ? (_patientService.currentPatient.name.isNotEmpty ? _patientService.currentPatient.name : 'anusha')
        : req.patientName;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF10B981).withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Patient Name & Contact + Severity Badge
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
                      child: const Icon(Icons.person_rounded, color: AppTheme.primaryBlue, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            patientName,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textDark),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (req.patientPhone.isNotEmpty && req.patientPhone != 'Not Provided') ...[
                            Text(
                              '📞 ${req.patientPhone}',
                              style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: req.severity == 'Severe' ? const Color(0xFFFEE2E2) : const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${req.severity} Severity',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: req.severity == 'Severe' ? const Color(0xFF991B1B) : const Color(0xFF92400E),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Row 2: Confirmed Time Slot Banner & Accepted Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFA7F3D0)),
            ),
            child: Row(
              children: [
                const Icon(Icons.access_time_filled_rounded, size: 16, color: Color(0xFF059669)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Confirmed Slot: $time',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF047857)),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_rounded, color: Colors.white, size: 12),
                      SizedBox(width: 4),
                      Text(
                        'Accepted & Scheduled',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Row 3: Procedure Category & Symptoms Description
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppTheme.primaryBlue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '📌 Category: ${req.problemCategory}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppTheme.primaryBlue),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Symptoms: "${req.problemDescription}"',
            style: const TextStyle(fontSize: 12, color: AppTheme.textMedium, height: 1.35),
          ),

          if (req.adminNotes != null && req.adminNotes!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '📝 Admin Note: ${req.adminNotes}',
              style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: AppTheme.textMuted),
            ),
          ],
          const SizedBox(height: 14),

          // Row 4: Action Buttons (Issue E-Prescription & Chat)
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 38,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.receipt_long_rounded, size: 14),
                    label: const Text('Issue E-Prescription', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.zero,
                      elevation: 1,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => _showPrescriptionModal(context, patientName),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 38,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.chat_bubble_outline_rounded, size: 14),
                    label: const Text('Chat', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.primaryBlue,
                      side: const BorderSide(color: AppTheme.primaryBlue),
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () {
                      final docName = _patientService.currentDoctor?.name ?? 'DOCTOR';
                      final rId = ApiService.getChatRoomId(patientIdOrName: patientName, dentistIdOrName: docName);
                      _showDoctorChatModal(context, patientName, rId);
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

  // ==========================================
  // TAB 2: PATIENTS TAB
  // ==========================================
  Widget _buildPatientsTab() {
    var currentDoc = _patientService.currentDoctor;
    final authUser = Supabase.instance.client.auth.currentUser;
    if (authUser != null && authUser.email != null && authUser.email!.isNotEmpty) {
      final authEmailLower = authUser.email!.toLowerCase();
      final authName = (authUser.userMetadata?['name'] ?? '').toString().toLowerCase();
      final match = _patientService.allDoctors.where(
        (d) => d.email.toLowerCase() == authEmailLower ||
            (d.id.isNotEmpty && d.id == authUser.id) ||
            (d.userId.isNotEmpty && d.userId == authUser.id) ||
            (authName.isNotEmpty && d.name.toLowerCase().contains(authName)),
      ).firstOrNull;
      if (match != null) {
        currentDoc = match;
        _patientService.currentDoctor = currentDoc;
      }
    }

    final currentDocName = (currentDoc?.name ?? '').replaceAll('Dr.', '').replaceAll('Dr. ', '').trim().toLowerCase();
    final currentDocId = (currentDoc?.id ?? '').trim();
    final currentDocUserId = (currentDoc?.userId ?? '').trim();
    final currentDocEmail = (currentDoc?.email ?? '').trim().toLowerCase();
    final authUserId = (authUser?.id ?? '').trim();
    final authEmail = (authUser?.email ?? '').trim().toLowerCase();

    final myDoctorIds = <String>{
      if (currentDocId.isNotEmpty) currentDocId,
      if (currentDocUserId.isNotEmpty) currentDocUserId,
      if (authUserId.isNotEmpty) authUserId,
      if (currentDocEmail.isNotEmpty) currentDocEmail,
      if (authEmail.isNotEmpty) authEmail,
    };

    for (final d in _patientService.allDoctors) {
      if (myDoctorIds.contains(d.id) || (d.userId.isNotEmpty && myDoctorIds.contains(d.userId)) || (d.email.isNotEmpty && myDoctorIds.contains(d.email.toLowerCase()))) {
        if (d.id.isNotEmpty) myDoctorIds.add(d.id);
        if (d.userId.isNotEmpty) myDoctorIds.add(d.userId);
        if (d.email.isNotEmpty) myDoctorIds.add(d.email.toLowerCase());
      }
    }

    bool isAssignedToMe(PatientConsultationRequest r) {
      final aId = r.assignedDoctorId?.trim();
      if (aId != null && aId.isNotEmpty && myDoctorIds.contains(aId)) {
        return true;
      }
      
      final aName = r.assignedDoctorName?.replaceAll('Dr.', '').replaceAll('Dr. ', '').trim().toLowerCase();
      if (currentDocName.isNotEmpty &&
          aName != null && aName.isNotEmpty && (aName == currentDocName || currentDocName.contains(aName) || aName.contains(currentDocName))) {
        return true;
      }
      return false;
    }

    final allPool = [
      ..._patientService.dentistAssignedRequests,
      ..._patientService.requests.where((r) => isAssignedToMe(r)),
    ];
    final patient = _patientService.currentPatient;
    final Map<String, Map<String, String>> uniquePatientMap = {};
    for (final req in allPool) {
      uniquePatientMap[req.patientName.trim().toLowerCase()] = {
        'name': req.patientName,
        'age': '${patient.age.isNotEmpty ? patient.age : "28"} Yrs',
        'blood': patient.bloodGroup.isNotEmpty ? patient.bloodGroup : 'O+',
        'issue': req.problemCategory,
      };
    }
    for (final ref in _patientService.doctorReceivedPatientReferrals) {
      final key = ref.referredPatientName.trim().toLowerCase();
      if (!uniquePatientMap.containsKey(key)) {
        uniquePatientMap[key] = {
          'name': ref.referredPatientName,
          'age': '${ref.referredPatientAge.isNotEmpty ? ref.referredPatientAge : "28"} Yrs (${ref.referredPatientGender})',
          'blood': 'O+',
          'issue': ref.requiredSpecialist.isNotEmpty ? ref.requiredSpecialist : 'Referral Consultation',
        };
      }
    }
    final myPatients = uniquePatientMap.values.toList();

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Patient Medical Directory', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textDark)),
          const SizedBox(height: 4),
          const Text('Access patient electronic dental records & X-rays', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
          const SizedBox(height: 16),
          if (myPatients.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: const Center(
                child: Text('No patient records found.', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
              ),
            )
          else
            ...myPatients.map((p) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _buildPatientListTile(
                  name: p['name'] ?? 'Patient',
                  age: p['age'] ?? '28 Yrs',
                  blood: p['blood'] ?? 'O+',
                  issue: p['issue'] ?? 'Dental Care',
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildPatientListTile({required String name, required String age, required String blood, required String issue}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 20,
            backgroundColor: AppTheme.softBlueBg,
            child: Icon(Icons.person_outline_rounded, color: AppTheme.primaryBlue, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textDark)),
                const SizedBox(height: 2),
                Text('$age • Blood: $blood • $issue', style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
              ],
            ),
          ),
          const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppTheme.textMuted),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 3: PRESCRIPTIONS TAB
  // ==========================================
  Widget _buildPrescriptionsTab() {
    final currentDoc = _patientService.currentDoctor;
    final currentDocName = (currentDoc?.name ?? '').replaceAll('Dr.', '').replaceAll('Dr. ', '').trim().toLowerCase();
    final currentDocId = (currentDoc?.id ?? '').trim();
    final currentDocUserId = (currentDoc?.userId ?? '').trim();

    return FutureBuilder<List<dynamic>>(
      future: ApiService().fetchMedicalRecords(),
      builder: (context, snapshot) {
        final records = (snapshot.data ?? []).where((r) {
          if (r['type'] != 'prescription') return false;
          final dName = (r['doctorName'] ?? r['doctor_name'] ?? '').toString().replaceAll('Dr.', '').replaceAll('Dr. ', '').trim().toLowerCase();
          final dId = (r['doctorId'] ?? r['doctor_id'] ?? '').toString();
          if (currentDocId.isNotEmpty && dId == currentDocId) return true;
          if (currentDocUserId.isNotEmpty && dId == currentDocUserId) return true;
          if (currentDocName.isNotEmpty && currentDocName != 'dentist' && dName == currentDocName) return true;
          return false;
        }).toList();

        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('E-Prescription Records', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textDark)),
              const SizedBox(height: 4),
              const Text('Issued digital medication slips', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
              const SizedBox(height: 16),
              if (records.isEmpty)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: const Center(
                    child: Text('No digital e-prescriptions issued yet.', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                  ),
                )
              else
                ...records.map((rec) {
                  final List items = rec['items'] is List ? rec['items'] : [];
                  final medStr = items.map((i) => i['name'] ?? '').join(', ');
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(rec['doctorName'] ?? 'Attending Doctor', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textDark)),
                            Text(rec['date'] ?? '', style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text('💊 ${medStr.isNotEmpty ? medStr : 'Active Medication'}', style: const TextStyle(fontSize: 12, color: Color(0xFF10B981), fontWeight: FontWeight.bold)),
                      ],
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }

  // ==========================================
  // TAB 4: ANALYTICS TAB
  // ==========================================
  Widget _buildAnalyticsTab() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Practice Analytics', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textDark)),
          const SizedBox(height: 4),
          const Text('Monthly consultations and procedure statistics', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: const Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(
                      children: [
                        Text('148', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue)),
                        Text('Monthly Consults', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                      ],
                    ),
                    Column(
                      children: [
                        Text('98.4%', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
                        Text('Positive Feedback', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // DIRECT PATIENT REFERRALS SECTION & MODALS
  // ==========================================
  Widget _buildDoctorPatientReferralsSection() {
    final allDoctorRefs = _patientService.doctorReceivedPatientReferrals;

    final filteredRefs = allDoctorRefs.where((r) {
      if (_doctorReferralFilter == 'Pending') return r.status == 'Pending';
      if (_doctorReferralFilter == 'Accepted') return r.status == 'Accepted';
      if (_doctorReferralFilter == 'Rejected') return r.status == 'Rejected';
      return true;
    }).toList();

    final pendingCount = allDoctorRefs.where((r) => r.status == 'Pending').length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Row(
                children: [
                  const Text(
                    'Direct Patient Referrals',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                  ),
                  if (pendingCount > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$pendingCount New',
                        style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 18, color: AppTheme.primaryBlue),
              onPressed: () => _patientService.syncDoctorReferralsFromApi(),
              tooltip: 'Refresh Referrals',
            ),
          ],
        ),
        const SizedBox(height: 2),
        const Text(
          'Patients referred directly to you by other patients',
          style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
        ),
        const SizedBox(height: 10),

        // Filter Chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: ['All', 'Pending', 'Accepted', 'Rejected'].map((filter) {
              final isSelected = _doctorReferralFilter == filter;
              int count = allDoctorRefs.length;
              if (filter == 'Pending') count = allDoctorRefs.where((r) => r.status == 'Pending').length;
              if (filter == 'Accepted') count = allDoctorRefs.where((r) => r.status == 'Accepted').length;
              if (filter == 'Rejected') count = allDoctorRefs.where((r) => r.status == 'Rejected').length;

              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(
                    '$filter ($count)',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected ? Colors.white : AppTheme.textDark,
                    ),
                  ),
                  selected: isSelected,
                  selectedColor: AppTheme.primaryBlue,
                  backgroundColor: Colors.white,
                  checkmarkColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(
                      color: isSelected ? AppTheme.primaryBlue : const Color(0xFFE2E8F0),
                    ),
                  ),
                  onSelected: (selected) {
                    if (selected) {
                      setState(() => _doctorReferralFilter = filter);
                    }
                  },
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 12),

        if (filteredRefs.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFEEF2F6)),
            ),
            child: Column(
              children: [
                Icon(Icons.person_add_disabled_rounded, size: 36, color: Colors.grey.withOpacity(0.4)),
                const SizedBox(height: 8),
                Text(
                  _doctorReferralFilter == 'All'
                      ? 'No direct patient referrals received yet.'
                      : 'No $_doctorReferralFilter patient referrals.',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                ),
                const SizedBox(height: 2),
                const Text(
                  'When patients refer friends or family to your clinic, they will appear here.',
                  style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          )
        else
          ...filteredRefs.map((ref) {
            final isPending = ref.status == 'Pending';
            final isAccepted = ref.status == 'Accepted';
            final isRejected = ref.status == 'Rejected';

            final statusColor = isAccepted
                ? const Color(0xFF10B981)
                : (isRejected ? const Color(0xFFEF4444) : const Color(0xFFF59E0B));
            final statusBg = isAccepted
                ? const Color(0xFFDCFCE7)
                : (isRejected ? const Color(0xFFFEE2E2) : const Color(0xFFFEF3C7));

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isPending
                      ? const Color(0xFFF59E0B).withOpacity(0.5)
                      : (isAccepted ? const Color(0xFF86EFAC) : const Color(0xFFE2E8F0)),
                  width: isPending ? 1.5 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: (isPending ? const Color(0xFFF59E0B) : Colors.black).withOpacity(0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top Row: Patient Name & Status
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: AppTheme.primaryBlue.withOpacity(0.12),
                              child: Text(
                                ref.referredPatientName.isNotEmpty ? ref.referredPatientName[0].toUpperCase() : 'P',
                                style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryBlue, fontSize: 14),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    ref.referredPatientName,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textDark),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    '+91 ${ref.referredPatientMobile} • ${ref.referredPatientAge} Yrs • ${ref.referredPatientGender}',
                                    style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (ref.referredPatientLocation.isNotEmpty || ref.referredPatientCity.isNotEmpty || ref.referredPatientPincode.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        const Icon(Icons.location_on_outlined, size: 12, color: Color(0xFF0284C7)),
                                        const SizedBox(width: 3),
                                        Expanded(
                                          child: Text(
                                            [
                                              if (ref.referredPatientLocation.isNotEmpty) ref.referredPatientLocation,
                                              if (ref.referredPatientCity.isNotEmpty) ref.referredPatientCity,
                                              if (ref.referredPatientPincode.isNotEmpty) '(${ref.referredPatientPincode})',
                                            ].join(', '),
                                            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500, color: Color(0xFF0369A1)),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: statusBg,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          ref.status,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: statusColor),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9)),
                  const SizedBox(height: 8),

                  // Referrer & Specialty Info
                  Row(
                    children: [
                      const Icon(Icons.person_pin_circle_outlined, size: 14, color: Color(0xFF6366F1)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: RichText(
                          text: TextSpan(
                            style: const TextStyle(fontSize: 11.5, color: AppTheme.textDark),
                            children: [
                              const TextSpan(text: 'Referred by: ', style: TextStyle(color: AppTheme.textMuted)),
                              TextSpan(text: ref.referrerPatientName, style: const TextStyle(fontWeight: FontWeight.bold)),
                              if (ref.referrerPatientPhone.isNotEmpty)
                                TextSpan(text: ' (+91 ${ref.referrerPatientPhone})', style: const TextStyle(color: AppTheme.textMuted)),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),

                  Row(
                    children: [
                      const Icon(Icons.medical_services_outlined, size: 14, color: Color(0xFF0D9488)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Category: ${ref.requiredSpecialist}',
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF0D9488)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),

                  if (ref.clinicalComplaint.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Problem / Clinical Complaint:', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppTheme.textMuted)),
                          const SizedBox(height: 2),
                          Text(
                            ref.clinicalComplaint,
                            style: const TextStyle(fontSize: 11.5, color: AppTheme.textDark, height: 1.3),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],

                  if (isRejected && ref.rejectionReason != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Rejection Reason: ${ref.rejectionReason}',
                      style: const TextStyle(fontSize: 11, color: Color(0xFFDC2626), fontWeight: FontWeight.w600),
                    ),
                  ],

                  const SizedBox(height: 12),

                  // Actions: View Details, Accept, Reject
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _showDoctorReferralDetailModal(context, ref),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: const Text('View Details', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      if (isPending) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _showRejectReferralDialog(context, ref),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFEF4444),
                              side: const BorderSide(color: Color(0xFFFCA5A5)),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            child: const Text('Reject', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => _acceptReferralDirectly(context, ref),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF10B981),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            child: const Text('Accept', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  Future<void> _acceptReferralDirectly(BuildContext context, PatientReferral ref) async {
    final success = await _patientService.acceptPatientReferralByDoctor(ref.id);
    if (!mounted) return;
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Accepted referral for ${ref.referredPatientName}. WhatsApp notification dispatched.'),
          backgroundColor: const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to accept referral. Please try again.')),
      );
    }
  }

  void _showRejectReferralDialog(BuildContext context, PatientReferral ref) {
    final reasonCtrl = TextEditingController(text: 'Doctor is currently unavailable for new referrals');
    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Text('Reject Referral for ${ref.referredPatientName}?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Please provide a brief reason for declining this patient referral:'),
              const SizedBox(height: 10),
              TextField(
                controller: reasonCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: 'e.g. Doctor schedule full, specialized surgery required elsewhere...',
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(dialogCtx);
                final reason = reasonCtrl.text.trim();
                final ok = await _patientService.rejectPatientReferralByDoctor(ref.id, rejectionReason: reason);
                if (!mounted) return;
                if (ok) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Referral for ${ref.referredPatientName} declined. Referrer notified.'),
                      backgroundColor: Colors.grey[800],
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
              child: const Text('Confirm Reject', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  void _showDoctorReferralDetailModal(BuildContext context, PatientReferral ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isPending = ref.status == 'Pending';
        return Container(
          height: MediaQuery.of(context).size.height * 0.85,
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Referral Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textDark)),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                ],
              ),
              const Divider(),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      // Section 1: Referrer
                      _buildDetailCard(
                        title: '1. REFERRER INFO',
                        icon: Icons.person_pin_rounded,
                        color: const Color(0xFF6366F1),
                        items: [
                          {'label': 'Referrer Name', 'value': ref.referrerPatientName},
                          {'label': 'Referrer Mobile', 'value': '+91 ${ref.referrerPatientPhone}'},
                          if (ref.referrerPatientEmail.isNotEmpty)
                            {'label': 'Referrer Email', 'value': ref.referrerPatientEmail},
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Section 2: Referred Patient
                      _buildDetailCard(
                        title: '2. REFERRED PATIENT INFO',
                        icon: Icons.person_rounded,
                        color: const Color(0xFF0284C7),
                        items: [
                          {'label': 'Patient Name', 'value': ref.referredPatientName},
                          {'label': 'Mobile Number', 'value': '+91 ${ref.referredPatientMobile}'},
                          {'label': 'Age & Gender', 'value': '${ref.referredPatientAge} Years • ${ref.referredPatientGender}'},
                          {'label': 'Location', 'value': '${ref.referredPatientLocation}, ${ref.referredPatientCity} (${ref.referredPatientPincode})'},
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Section 3: Referral Details
                      _buildDetailCard(
                        title: '3. REFERRAL & CLINICAL COMPLAINT',
                        icon: Icons.medical_information_rounded,
                        color: const Color(0xFF0D9488),
                        items: [
                          {'label': 'Specialist Category', 'value': ref.requiredSpecialist},
                          {'label': 'Complaint / Notes', 'value': ref.clinicalComplaint},
                          {'label': 'Referral Date', 'value': '${ref.referralDate.day}/${ref.referralDate.month}/${ref.referralDate.year}'},
                          {'label': 'Current Status', 'value': ref.status},
                          {'label': 'WhatsApp Status', 'value': ref.whatsappStatus},
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (isPending) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _showRejectReferralDialog(context, ref);
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFEF4444),
                          side: const BorderSide(color: Color(0xFFEF4444)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Reject Referral', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _acceptReferralDirectly(context, ref);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Accept Referral', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildDetailCard({
    required String title,
    required IconData icon,
    required Color color,
    required List<Map<String, String>> items,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...items.map((it) => Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 120,
                      child: Text(it['label'] ?? '', style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                    ),
                    Expanded(
                      child: Text(it['value'] ?? '', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppTheme.textDark)),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}
