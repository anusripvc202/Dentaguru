import 'package:flutter/material.dart';
import '../../../../core/constants/booking_rules_config.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/services/patient_problem_service.dart';

enum AppointmentManagementMode {
  details,
  reschedule,
  cancel,
}

class AppointmentManagementDialog extends StatefulWidget {
  final PatientConsultationRequest appointment;
  final AppointmentManagementMode initialMode;
  final VoidCallback? onUpdated;

  const AppointmentManagementDialog({
    super.key,
    required this.appointment,
    this.initialMode = AppointmentManagementMode.details,
    this.onUpdated,
  });

  static Future<void> show(
    BuildContext context, {
    required PatientConsultationRequest appointment,
    AppointmentManagementMode initialMode = AppointmentManagementMode.details,
    VoidCallback? onUpdated,
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AppointmentManagementDialog(
        appointment: appointment,
        initialMode: initialMode,
        onUpdated: onUpdated,
      ),
    );
  }

  @override
  State<AppointmentManagementDialog> createState() => _AppointmentManagementDialogState();
}

class _AppointmentManagementDialogState extends State<AppointmentManagementDialog> {
  final PatientProblemService _patientService = PatientProblemService();

  late AppointmentManagementMode _mode;
  DateTime _newDate = DateTime.now().add(const Duration(days: 1));
  String? _newTimeSlot;
  bool _isProcessing = false;
  String? _errorMessage;

  static const List<String> _timeSlots = [
    '09:30 AM',
    '10:30 AM',
    '11:30 AM',
    '02:00 PM',
    '03:00 PM',
    '04:00 PM',
    '05:00 PM',
    '06:00 PM',
    '07:00 PM',
  ];

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    if (widget.appointment.confirmedTimeSlot != null && widget.appointment.confirmedTimeSlot!.isNotEmpty) {
      _newTimeSlot = widget.appointment.confirmedTimeSlot;
    }
  }

  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return 'Pending Confirmation';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${weekdays[dt.weekday - 1]}, ${dt.day.toString().padLeft(2, '0')} ${months[dt.month - 1]} ${dt.year}';
  }

  bool _isSlotBooked(String slot) {
    final docId = widget.appointment.assignedDoctorId ?? '';
    final docName = widget.appointment.assignedDoctorName ?? '';
    final dateStr = _newDate.toIso8601String().split('T').first;
    final candidateStart = BookingRulesConfig.parseClockSlotMinutes(slot);
    final candidateMode = BookingRulesConfig.normalizeConsultationMode(
      widget.appointment.consultationMode ?? widget.appointment.problemCategory,
    );
    final candidateOccupied = (widget.appointment.durationMinutes ?? BookingRulesConfig.durationForMode(candidateMode)) +
        (widget.appointment.bufferMinutes ?? BookingRulesConfig.bufferForMode(candidateMode));

    for (final req in _patientService.requests) {
      if (req.id == widget.appointment.id) continue;
      final s = req.status.toUpperCase();
      if (s == 'CANCELLED' || s == 'REJECTED' || s == 'NO_SHOW' || s == 'COMPLETED') continue;
      final reqDocId = req.assignedDoctorId ?? '';
      final reqDate = req.confirmedDate?.split('T').first ?? '';
      final reqSlot = (req.confirmedTimeSlot ?? '').trim();

      if ((reqDocId == docId || req.assignedDoctorName == docName) && reqDate == dateStr) {
        if (reqSlot.toLowerCase() == slot.toLowerCase()) return true;
        final existingStart = BookingRulesConfig.parseClockSlotMinutes(reqSlot);
        if (candidateStart != null && existingStart != null) {
          final existingMode = BookingRulesConfig.normalizeConsultationMode(
            req.consultationMode ?? req.problemCategory,
          );
          final existingOccupied = (req.durationMinutes ?? BookingRulesConfig.durationForMode(existingMode)) +
              (req.bufferMinutes ?? BookingRulesConfig.bufferForMode(existingMode)) +
              req.delayMinutes;
          if (BookingRulesConfig.intervalsOverlap(
            candidateStart,
            candidateStart + candidateOccupied,
            existingStart,
            existingStart + existingOccupied,
          )) {
            return true;
          }
        }
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      _mode == AppointmentManagementMode.details
                          ? 'Appointment Details'
                          : _mode == AppointmentManagementMode.reschedule
                              ? 'Reschedule Visit'
                              : 'Cancel Appointment',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: AppTheme.textDark),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: AppTheme.textMuted),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const Divider(height: 16, color: Color(0xFFF1F5F9)),

              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: const Color(0x14FE3434),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0x40FE3434)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded, color: Color(0xFFFE3434), size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(fontSize: 12, color: Color(0xFFFE3434)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              if (_mode == AppointmentManagementMode.details)
                _buildDetailsContent()
              else if (_mode == AppointmentManagementMode.reschedule)
                _buildRescheduleContent()
              else
                _buildCancelContent(),
            ],
          ),
        ),
      ),
    );
  }

  // Details View
  Widget _buildDetailsContent() {
    final req = widget.appointment;
    final isUpcoming = req.status.toUpperCase() != 'COMPLETED' &&
        req.status.toUpperCase() != 'CANCELLED' &&
        req.status.toUpperCase() != 'REJECTED';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Doctor Card
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0x14012A58),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0x40012A58)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: AppTheme.primaryBlue.withValues(alpha: 0.15),
                child: Text(
                  req.assignedDoctorName != null && req.assignedDoctorName!.isNotEmpty
                      ? req.assignedDoctorName!.replaceAll('Dr.', '').replaceAll('Dr. ', '').trim()[0].toUpperCase()
                      : 'D',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryBlue),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      req.assignedDoctorName ?? 'Attending Specialist',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF012A58)),
                    ),
                    Text(
                      req.assignedDoctorClinic ?? 'GS HEALTH Clinic',
                      style: const TextStyle(fontSize: 11.5, color: Color(0xFF012A58)),
                    ),
                  ],
                ),
              ),
              _buildStatusBadge(req.status),
            ],
          ),
        ),
        const SizedBox(height: 16),

        _buildDetailItem(Icons.calendar_today_rounded, 'Date', _formatDate(req.confirmedDate)),
        const SizedBox(height: 10),
        _buildDetailItem(Icons.access_time_rounded, 'Time Slot', req.confirmedTimeSlot ?? 'Pending Confirmation'),
        const SizedBox(height: 10),
        _buildDetailItem(Icons.medical_services_rounded, 'Treatment / Problem', req.problemCategory),
        if (req.problemDescription.isNotEmpty && req.problemDescription != 'Scheduled dental consultation' && req.problemDescription != 'Scheduled medical consultation') ...[
          const SizedBox(height: 10),
          _buildDetailItem(Icons.notes_rounded, 'Symptoms / Notes', req.problemDescription),
        ],
        const SizedBox(height: 10),
        _buildDetailItem(
          req.displayConsultationMode == 'Online'
              ? Icons.videocam_outlined
              : Icons.local_hospital_outlined,
          'Consultation Mode',
          '${req.displayConsultationMode} Consultation',
        ),
        const SizedBox(height: 10),
        _buildDetailItem(
          Icons.payments_rounded,
          'Consultation Fee',
          BookingRulesConfig.formatRealFee(
            req.displayConsultationFee,
            emptyFallback: 'As per clinic tariff',
          ),
        ),
        if (req.delayMinutes > 0 || (req.estimatedStartTime != null && req.estimatedStartTime!.isNotEmpty)) ...[
          const SizedBox(height: 14),
          Container(
            key: const Key('appointment_delay_notice_card'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFF59E0B)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.schedule_send_rounded, size: 18, color: Color(0xFFB45309)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        req.estimatedStartTime != null && req.estimatedStartTime!.isNotEmpty
                            ? 'Doctor running ~${req.delayMinutes}m late • Est. start: ${req.estimatedStartTime}'
                            : 'Doctor running ~${req.delayMinutes} mins late',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5,
                          color: Color(0xFF92400E),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    OutlinedButton(
                      key: const Key('delay_action_wait_btn'),
                      onPressed: _isProcessing ? null : () => _handleDelayChoice('WAIT'),
                      child: Text(
                        req.patientDelayChoice == 'WAIT' ? 'Waiting ✓' : 'Wait',
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                      ),
                    ),
                    OutlinedButton(
                      key: const Key('delay_action_request_reschedule_btn'),
                      onPressed: _isProcessing
                          ? null
                          : () {
                              setState(() {
                                _mode = AppointmentManagementMode.reschedule;
                                _errorMessage = null;
                              });
                              _handleDelayChoice('REQUEST_RESCHEDULE', popAfter: false);
                            },
                      child: const Text('Request Reschedule', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                    ),
                    OutlinedButton(
                      key: const Key('delay_action_switch_doctor_btn'),
                      onPressed: _isProcessing ? null : _handleSwitchDoctorSuggestions,
                      child: const Text('Switch Doctor', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),

        // Action Buttons if appointment is active
        if (isUpcoming) ...[
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => setState(() {
                    _mode = AppointmentManagementMode.reschedule;
                    _errorMessage = null;
                  }),
                  icon: const Icon(Icons.edit_calendar_rounded, size: 16),
                  label: const Text('Reschedule', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppTheme.primaryBlue),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => setState(() {
                    _mode = AppointmentManagementMode.cancel;
                    _errorMessage = null;
                  }),
                  icon: const Icon(Icons.cancel_outlined, size: 16),
                  label: const Text('Cancel Visit', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0x14FE3434),
                    foregroundColor: const Color(0xFFFE3434),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: const BorderSide(color: Color(0x40FE3434)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildDetailItem(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppTheme.primaryBlue),
        const SizedBox(width: 10),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(fontSize: 12.5, color: AppTheme.textDark),
              children: [
                TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textMuted)),
                TextSpan(text: value),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusBadge(String status) {
    final label = BookingRulesConfig.formatAppointmentStatusLabel(status);
    final isPositive = label == 'Confirmed' || label == 'Completed';
    final isNeutralInfo = label == 'Rescheduled' || label == 'Pending';

    final bg = isPositive
        ? const Color(0xFFECFDF5)
        : isNeutralInfo
            ? const Color(0x14012A58)
            : const Color(0x14FE3434);
    final text = isPositive
        ? const Color(0xFF047857)
        : isNeutralInfo
            ? const Color(0xFF012A58)
            : const Color(0xFFFE3434);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Text(
        label,
        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: text),
      ),
    );
  }

  // Reschedule View
  Widget _buildRescheduleContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Select New Appointment Date', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: AppTheme.textDark)),
        const SizedBox(height: 8),

        SizedBox(
          height: 64,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: 14,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, idx) {
              final date = DateTime.now().add(Duration(days: idx + 1));
              final isSelected = date.year == _newDate.year &&
                  date.month == _newDate.month &&
                  date.day == _newDate.day;
              const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

              return InkWell(
                onTap: () => setState(() {
                  _newDate = date;
                  _newTimeSlot = null;
                }),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 54,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected ? AppTheme.primaryBlue : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: isSelected ? AppTheme.primaryBlue : const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(weekdays[date.weekday - 1], style: TextStyle(fontSize: 10.5, color: isSelected ? Colors.white : AppTheme.textMuted)),
                      Text(date.day.toString().padLeft(2, '0'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : AppTheme.textDark)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),

        const Text('Select New Time Slot', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: AppTheme.textDark)),
        const SizedBox(height: 8),

        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _timeSlots.map((slot) {
            final isBooked = _isSlotBooked(slot);
            final isSelected = _newTimeSlot == slot;

            return InkWell(
              onTap: isBooked ? null : () => setState(() => _newTimeSlot = slot),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: isBooked ? const Color(0xFFF1F5F9) : isSelected ? AppTheme.primaryBlue : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: isBooked ? const Color(0xFFE2E8F0) : isSelected ? AppTheme.primaryBlue : const Color(0xFFCBD5E1)),
                ),
                child: Text(
                  slot,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: isBooked ? const Color(0xFF94A3B8) : isSelected ? Colors.white : AppTheme.textDark,
                    decoration: isBooked ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),

        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => setState(() => _mode = AppointmentManagementMode.details),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Back', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                onPressed: _newTimeSlot == null || _isProcessing ? null : _handleReschedule,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: _isProcessing
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Confirm Reschedule', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // Cancel View
  Widget _buildCancelContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0x14FE3434),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0x14FE3434)),
          ),
          child: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Color(0xFFFE3434), size: 24),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Are you sure you want to cancel this appointment? You can book a new appointment at any time.',
                  style: TextStyle(fontSize: 12, color: Color(0xFFFE3434)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => setState(() => _mode = AppointmentManagementMode.details),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Keep Visit', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                onPressed: _isProcessing ? null : _handleCancel,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFE3434),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: _isProcessing
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Yes, Cancel Visit', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _handleReschedule() async {
    if (_newTimeSlot == null) return;
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      final res = await _patientService.rescheduleAppointment(
        appointmentId: widget.appointment.id,
        date: _newDate.toIso8601String(),
        timeSlot: _newTimeSlot!,
      );

      if (!mounted) return;

      if (res['success'] == true) {
        Navigator.of(context).pop();
        widget.onUpdated?.call();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Appointment rescheduled successfully!'), backgroundColor: Color(0xFFFE3434)),
        );
      } else {
        setState(() {
          _isProcessing = false;
          _errorMessage = res['message']?.toString() ?? 'Failed to reschedule appointment.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _errorMessage = 'Error rescheduling: $e';
      });
    }
  }

  Future<void> _handleCancel() async {
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      final res = await _patientService.cancelAppointment(widget.appointment.id);
      if (!mounted) return;

      if (res['success'] == true) {
        Navigator.of(context).pop();
        widget.onUpdated?.call();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Appointment has been cancelled.'), backgroundColor: Color(0xFF64748B)),
        );
      } else {
        setState(() {
          _isProcessing = false;
          _errorMessage = res['message']?.toString() ?? 'Failed to cancel appointment.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _errorMessage = 'Error cancelling: $e';
      });
    }
  }

  Future<void> _handleDelayChoice(String action, {bool popAfter = true}) async {
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });
    try {
      final res = await _patientService.submitPatientDelayResponse(
        appointmentId: widget.appointment.id,
        action: action,
      );
      if (!mounted) return;
      setState(() => _isProcessing = false);
      if (res['success'] == true) {
        widget.onUpdated?.call();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res['message']?.toString() ?? 'Response saved.'),
            backgroundColor: AppTheme.gsNavy,
          ),
        );
        if (popAfter) Navigator.of(context).pop();
      } else {
        setState(() => _errorMessage = res['message']?.toString() ?? 'Failed to submit response.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _errorMessage = 'Failed to submit response: $e';
      });
    }
  }

  Future<void> _handleSwitchDoctorSuggestions() async {
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });
    final res = await _patientService.submitPatientDelayResponse(
      appointmentId: widget.appointment.id,
      action: 'SWITCH_DOCTOR',
    );
    if (!mounted) return;
    setState(() => _isProcessing = false);
    final alts = (res['alternateDoctors'] is List)
        ? (res['alternateDoctors'] as List).whereType<Map>().toList()
        : const <Map>[];
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          alts.isNotEmpty
              ? '${alts.length} alternate doctor(s) available: ${alts.take(2).map((d) => d['name']).join(', ')}'
              : 'You can browse alternate available doctors in Find Doctors.',
        ),
        backgroundColor: AppTheme.gsNavy,
      ),
    );
  }
}

