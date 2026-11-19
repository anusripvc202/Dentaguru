import 'package:flutter/material.dart';
import '../../../../core/services/api_service.dart';
import '../../../../core/theme/app_theme.dart';

class GsHealthAssignmentTimelineDialog extends StatefulWidget {
  final String patientId;
  final String patientName;

  const GsHealthAssignmentTimelineDialog({
    super.key,
    required this.patientId,
    required this.patientName,
  });

  static Future<void> show(
    BuildContext context, {
    required String patientId,
    required String patientName,
  }) {
    return showDialog(
      context: context,
      builder: (ctx) => GsHealthAssignmentTimelineDialog(
        patientId: patientId,
        patientName: patientName,
      ),
    );
  }

  @override
  State<GsHealthAssignmentTimelineDialog> createState() => _GsHealthAssignmentTimelineDialogState();
}

class _GsHealthAssignmentTimelineDialogState extends State<GsHealthAssignmentTimelineDialog> {
  bool _isLoading = true;
  List<dynamic> _timeline = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchTimeline();
  }

  Future<void> _fetchTimeline() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await ApiService().fetchPatientAssignmentTimeline(widget.patientId);
      if (mounted) {
        setState(() {
          _timeline = res;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      actionsPadding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF012A58).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.timeline_rounded, color: Color(0xFF012A58), size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Assignment Audit Timeline',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16.5, color: Color(0xFF0F172A)),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'History for ${widget.patientName}',
                  style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
      content: Container(
        width: double.maxFinite,
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 380),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF012A58)))
            : _errorMessage != null
                ? Center(
                    child: Text(
                      'Error loading timeline: $_errorMessage',
                      style: const TextStyle(color: Color(0xFFFE3434), fontSize: 12),
                    ),
                  )
                : _timeline.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.history_toggle_off_rounded, size: 40, color: AppTheme.textMuted),
                            SizedBox(height: 10),
                            Text(
                              'No assignment events recorded yet.',
                              style: TextStyle(fontSize: 13, color: AppTheme.textMuted, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _timeline.length,
                        itemBuilder: (context, index) {
                          final event = _timeline[index];
                          final dName = (event['dentist_name'] ?? (event['dentist'] is Map ? event['dentist']['name'] : '') ?? 'Specialist').toString();
                          final dClinic = (event['clinic_name'] ?? (event['clinic'] is Map ? event['clinic']['clinic_name'] : '') ?? 'Clinic').toString();
                          final source = (event['assignment_source'] ?? '').toString();
                          final assignedBy = (event['assigned_by_name'] ?? (event['assigned_by_user'] is Map ? event['assigned_by_user']['name'] : '') ?? 'Admin').toString();
                          final status = (event['status'] ?? 'ACTIVE').toString().toUpperCase();
                          final reason = (event['reason'] ?? '').toString();
                          final notes = (event['notes'] ?? '').toString();
                          final createdAt = (event['created_at'] ?? '').toString();
                          final prevDentist = (event['previous_dentist_name'] ?? '').toString();

                          Color dotColor = const Color(0xFF012A58);
                          if (source == 'PATIENT_DIRECT_BOOKING') dotColor = const Color(0xFF012A58);
                          if (source == 'SUB_ADMIN_ASSIGNMENT') dotColor = const Color(0xFFFE3434);

                          return IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Column(
                                  children: [
                                    Container(
                                      width: 14,
                                      height: 14,
                                      decoration: BoxDecoration(
                                        color: dotColor,
                                        shape: BoxShape.circle,
                                        border: Border.all(color: Colors.white, width: 2),
                                        boxShadow: [
                                          BoxShadow(
                                            color: dotColor.withValues(alpha: 0.3),
                                            blurRadius: 4,
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (index != _timeline.length - 1)
                                      Expanded(
                                        child: Container(
                                          width: 2,
                                          color: const Color(0xFFE2E8F0),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.only(bottom: 16),
                                    child: Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF8FAFC),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: const Color(0xFFE2E8F0)),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  dName,
                                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A)),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: dotColor.withValues(alpha: 0.1),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  status,
                                                  style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: dotColor),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 2),
                                          Text(dClinic, style: const TextStyle(fontSize: 11.5, color: Color(0xFF475569))),
                                          if (prevDentist.isNotEmpty) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              'Reassigned from: $prevDentist',
                                              style: const TextStyle(fontSize: 10.5, fontStyle: FontStyle.italic, color: Color(0xFFFE3434)),
                                            ),
                                          ],
                                          const SizedBox(height: 4),
                                          Text(
                                            'Assigned by: $assignedBy • Source: ${_formatSource(source)}',
                                            style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B)),
                                          ),
                                          if (reason.isNotEmpty || notes.isNotEmpty) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              notes.isNotEmpty ? 'Guidance: $notes' : 'Reason: $reason',
                                              style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Color(0xFF334155)),
                                            ),
                                          ],
                                          if (createdAt.isNotEmpty) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              _formatDate(createdAt),
                                              style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
      ),
      actions: [
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF012A58),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  String _formatSource(String s) {
    if (s == 'PATIENT_DIRECT_BOOKING') return 'Direct Patient Booking';
    if (s == 'SUB_ADMIN_ASSIGNMENT') return 'Sub-Admin Assignment';
    return 'Main Admin Assignment';
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final min = dt.minute.toString().padLeft(2, '0');
      final ampm = dt.hour >= 12 ? 'PM' : 'AM';
      return '${dt.day} ${months[dt.month - 1]} ${dt.year}, $hour:$min $ampm';
    } catch (_) {
      return iso;
    }
  }
}
