import 'package:flutter/material.dart';
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

    for (final req in _patientService.requests) {
      if (req.id == widget.appointment.id) continue;
      final s = req.status.toUpperCase();
      if (s == 'CANCELLED' || s == 'REJECTED') continue;
      final reqDocId = req.assignedDoctorId ?? '';
      final reqDate = req.confirmedDate?.split('T').first ?? '';
      final reqSlot = (req.confirmedTimeSlot ?? '').trim();

      if ((reqDocId == docId || req.assignedDoctorName == docName) &&
          reqDate == dateStr &&
          reqSlot.toLowerCase() == slot.toLowerCase()) {
        return true;
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
                    color: const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFCA5A5)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626), size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(fontSize: 12, color: Color(0xFF991B1B)),
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
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFBFDBFE)),
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
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E3A8A)),
                    ),
                    Text(
                      req.assignedDoctorClinic ?? 'GS HEALTH Clinic',
                      style: const TextStyle(fontSize: 11.5, color: Color(0xFF2563EB)),
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
        if (req.problemDescription.isNotEmpty && req.problemDescription != 'Scheduled dental consultation') ...[
          const SizedBox(height: 10),
          _buildDetailItem(Icons.notes_rounded, 'Symptoms / Notes', req.problemDescription),
        ],
        const SizedBox(height: 10),
        _buildDetailItem(Icons.payments_rounded, 'Consultation Fee', '₹500 (Pay at clinic)'),
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
                    backgroundColor: const Color(0xFFFEE2E2),
                    foregroundColor: const Color(0xFFDC2626),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: const BorderSide(color: Color(0xFFFCA5A5)),
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
    final s = status.toUpperCase();
    final isConfirmed = s == 'CONFIRMED' || s == 'ACCEPTED';
    final isCancelled = s == 'CANCELLED' || s == 'REJECTED';
    final isRescheduled = s == 'RESCHEDULED';

    final bg = isConfirmed
        ? const Color(0xFFDCFCE7)
        : isCancelled
            ? const Color(0xFFFEE2E2)
            : isRescheduled
                ? const Color(0xFFDBEAFE)
                : const Color(0xFFFEF3C7);
    final text = isConfirmed
        ? const Color(0xFF15803D)
        : isCancelled
            ? const Color(0xFFDC2626)
            : isRescheduled
                ? const Color(0xFF1D4ED8)
                : const Color(0xFFD97706);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Text(
        status.isEmpty ? 'Pending' : status,
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
            color: const Color(0xFFFFF7ED),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFFED7AA)),
          ),
          child: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Color(0xFFEA580C), size: 24),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Are you sure you want to cancel this appointment? You can book a new appointment at any time.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF9A3412)),
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
                  backgroundColor: const Color(0xFFDC2626),
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
          const SnackBar(content: Text('✅ Appointment rescheduled successfully!'), backgroundColor: Color(0xFF16A34A)),
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
}

