import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/services/patient_problem_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../widgets/doctor_visits_calendar.dart';

/// Dedicated full-screen Doctor Appointments Calendar opened from the Doctor Dashboard Today page.
class DoctorAppointmentsCalendarScreen extends StatefulWidget {
  final String doctorId;
  final String doctorName;
  final String doctorSpecialty;
  final DateTime? initialSelectedDate;
  final List<PatientConsultationRequest>? initialAppointments;
  final void Function(PatientConsultationRequest request)? onOpenConsultationDetails;
  final void Function(PatientConsultationRequest request)? onOpenPrescription;

  const DoctorAppointmentsCalendarScreen({
    super.key,
    required this.doctorId,
    required this.doctorName,
    this.doctorSpecialty = 'General Medicine',
    this.initialSelectedDate,
    this.initialAppointments,
    this.onOpenConsultationDetails,
    this.onOpenPrescription,
  });

  @override
  State<DoctorAppointmentsCalendarScreen> createState() => _DoctorAppointmentsCalendarScreenState();
}

class _DoctorAppointmentsCalendarScreenState extends State<DoctorAppointmentsCalendarScreen> {
  final PatientProblemService _patientService = PatientProblemService();
  bool _isRefreshing = false;
  RealtimeChannel? _calendarRealtimeChannel;

  @override
  void initState() {
    super.initState();
    _patientService.addListener(_onServiceChanged);
    _subscribeRealtimeUpdates();
  }

  void _subscribeRealtimeUpdates() {
    try {
      final channelName = 'doctor_cal_${widget.doctorId}_${DateTime.now().microsecondsSinceEpoch}';
      _calendarRealtimeChannel = Supabase.instance.client
          .channel(channelName)
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'appointments',
            callback: (_) {
              if (mounted) unawaited(_refreshData());
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'doctor_availability',
            callback: (_) {
              if (mounted) unawaited(_refreshData());
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'released_slots',
            callback: (_) {
              if (mounted) unawaited(_refreshData());
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'doctor_scheduling_settings',
            callback: (_) {
              if (mounted) unawaited(_refreshData());
            },
          )
          .subscribe();
    } catch (_) {
      // Safe no-op when Supabase is uninitialized in unit tests
    }
  }

  @override
  void dispose() {
    if (_calendarRealtimeChannel != null) {
      try {
        Supabase.instance.client.removeChannel(_calendarRealtimeChannel!);
      } catch (_) {}
    }
    _patientService.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _refreshData() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    try {
      await Future.wait<void>([
        _patientService.syncAppointmentsFromApi(),
        _patientService.syncDentistAssignedRequestsFromApi(),
        _patientService.syncDoctorReferralsFromApi(doctorId: widget.doctorId),
      ]);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  List<PatientConsultationRequest> _resolveDoctorAppointments() {
    if (widget.initialAppointments != null &&
        _patientService.requests.isEmpty &&
        _patientService.dentistAssignedRequests.isEmpty) {
      return widget.initialAppointments!;
    }

    final docIdClean = widget.doctorId.trim();
    final docNameClean = widget.doctorName
        .replaceAll(RegExp(r'^dr\.?\s*', caseSensitive: false), '')
        .trim()
        .toLowerCase();

    final currentDoc = _patientService.currentDoctor;
    final myDoctorIds = <String>{
      if (docIdClean.isNotEmpty) docIdClean,
      if (currentDoc != null && currentDoc.id.trim().isNotEmpty) currentDoc.id.trim(),
      if (currentDoc != null && currentDoc.userId.trim().isNotEmpty) currentDoc.userId.trim(),
    };

    bool isAssignedToMe(PatientConsultationRequest r) {
      final assignedId = (r.assignedDoctorId ?? '').trim();
      if (assignedId.isNotEmpty) {
        return myDoctorIds.contains(assignedId);
      }
      final rDocName = (r.assignedDoctorName ?? '')
          .replaceAll(RegExp(r'^dr\.?\s*', caseSensitive: false), '')
          .trim()
          .toLowerCase();
      return docNameClean.isNotEmpty && rDocName.isNotEmpty && rDocName == docNameClean;
    }

    final uniqueMap = <String, PatientConsultationRequest>{};
    for (final r in _patientService.dentistAssignedRequests) {
      if (isAssignedToMe(r)) {
        uniqueMap[r.id] = r;
      }
    }
    for (final r in _patientService.requests) {
      if (isAssignedToMe(r)) {
        uniqueMap[r.id] = r;
      }
    }
    if (widget.initialAppointments != null) {
      for (final r in widget.initialAppointments!) {
        if (isAssignedToMe(r) && !uniqueMap.containsKey(r.id)) {
          uniqueMap[r.id] = r;
        }
      }
    }
    return uniqueMap.values.toList();
  }

  @override
  Widget build(BuildContext context) {
    final appointments = _resolveDoctorAppointments();

    return Scaffold(
      key: const Key('doctor_appointments_calendar_screen'),
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF0F172A)),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Appointments Calendar',
              style: TextStyle(
                fontSize: 17.5,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
              ),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              widget.doctorName,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF64748B),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          IconButton(
            key: const Key('doctor_calendar_screen_refresh_btn'),
            tooltip: 'Refresh Appointments',
            onPressed: _isRefreshing ? null : _refreshData,
            icon: _isRefreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.gsNavy),
                  )
                : const Icon(Icons.refresh_rounded, color: AppTheme.gsNavy),
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: Color(0xFFE2E8F0)),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _refreshData,
        color: AppTheme.gsNavy,
        child: SingleChildScrollView(
          key: const Key('doctor_calendar_screen_scroll_view'),
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
          child: DoctorVisitsCalendarSection(
            doctorId: widget.doctorId,
            doctorName: widget.doctorName,
            doctorSpecialty: widget.doctorSpecialty,
            assignedAppointments: appointments,
            receivedReferrals: _patientService.doctorReceivedPatientReferrals,
            initialSelectedDate: widget.initialSelectedDate,
            onOpenConsultationDetails: widget.onOpenConsultationDetails,
            onOpenPrescription: widget.onOpenPrescription,
            embeddedInScreen: true,
          ),
        ),
      ),
    );
  }
}
