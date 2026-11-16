import 'package:flutter/material.dart';
import '../../../../core/services/patient_problem_service.dart';
import '../../../../core/theme/app_theme.dart';
import 'gs_health_assignment_timeline_dialog.dart';

class GsHealthPatientAssignmentPanel extends StatefulWidget {
  final PatientProblemService problemService;
  final VoidCallback onRefresh;

  const GsHealthPatientAssignmentPanel({
    super.key,
    required this.problemService,
    required this.onRefresh,
  });

  @override
  State<GsHealthPatientAssignmentPanel> createState() => _GsHealthPatientAssignmentPanelState();
}

class _GsHealthPatientAssignmentPanelState extends State<GsHealthPatientAssignmentPanel> {
  String _searchQuery = '';
  String _sourceFilter = 'ALL'; // 'ALL', 'PATIENT_DIRECT_BOOKING', 'MAIN_ADMIN_ASSIGNMENT', 'SUB_ADMIN_ASSIGNMENT'
  String _statusFilter = 'ALL'; // 'ALL', 'ACTIVE', 'REASSIGNED', 'COMPLETED', 'CANCELLED'

  @override
  Widget build(BuildContext context) {
    final history = widget.problemService.assignmentHistory;
    final stats = widget.problemService.assignmentStats;

    final totalCount = stats['totalAssignments'] ?? history.length;
    final directBookingsCount = stats['directBookings'] ?? history.where((h) => h['assignment_source'] == 'PATIENT_DIRECT_BOOKING').length;
    final mainAdminCount = stats['mainAdminAssignments'] ?? history.where((h) => h['assignment_source'] == 'MAIN_ADMIN_ASSIGNMENT').length;
    final subAdminCount = stats['subAdminAssignments'] ?? history.where((h) => h['assignment_source'] == 'SUB_ADMIN_ASSIGNMENT').length;

    final filtered = history.where((item) {
      final patientName = (item['patient_name'] ?? (item['patient'] is Map ? item['patient']['name'] : '') ?? '').toString().toLowerCase();
      final doctorName = (item['dentist_name'] ?? (item['dentist'] is Map ? item['dentist']['name'] : '') ?? '').toString().toLowerCase();
      final assignerName = (item['assigned_by_name'] ?? (item['assigned_by_user'] is Map ? item['assigned_by_user']['name'] : '') ?? '').toString().toLowerCase();
      final query = _searchQuery.trim().toLowerCase();

      final matchesQuery = query.isEmpty ||
          patientName.contains(query) ||
          doctorName.contains(query) ||
          assignerName.contains(query);

      final source = (item['assignment_source'] ?? '').toString();
      final matchesSource = _sourceFilter == 'ALL' || source == _sourceFilter;

      final status = (item['status'] ?? 'ACTIVE').toString().toUpperCase();
      final matchesStatus = _statusFilter == 'ALL' || status == _statusFilter;

      return matchesQuery && matchesSource && matchesStatus;
    }).toList();

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF012A58), Color(0xFF0F3D6E)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF012A58).withValues(alpha: 0.15),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.assignment_ind_rounded, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Patient Assignment & Audit Trail',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16.5,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Immutable append-only history of patient routing across all districts',
                        style: TextStyle(color: Colors.white70, fontSize: 11.5),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton.filled(
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  tooltip: 'Sync Assignments',
                  onPressed: widget.onRefresh,
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // KPI Stats Cards (4 items)
          Row(
            children: [
              Expanded(
                child: _buildKpiCard('Total Assignments', '$totalCount', Icons.receipt_long_rounded, const Color(0xFF012A58)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildKpiCard('Direct Bookings', '$directBookingsCount', Icons.flash_on_rounded, const Color(0xFF059669)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildKpiCard('Main Admin Assigned', '$mainAdminCount', Icons.shield_rounded, const Color(0xFF0284C7)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildKpiCard('Sub-Admin Assigned', '$subAdminCount', Icons.supervisor_account_rounded, const Color(0xFF7C3AED)),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Search & Filter Bar
          TextField(
            onChanged: (val) => setState(() => _searchQuery = val),
            style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w500),
            cursorColor: AppTheme.primaryBlue,
            decoration: InputDecoration(
              hintText: 'Search by patient, doctor, or assigner name...',
              hintStyle: const TextStyle(fontSize: 12.5, color: AppTheme.textMuted),
              prefixIcon: const Icon(Icons.search_rounded, size: 18, color: AppTheme.primaryBlue),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
            ),
          ),

          const SizedBox(height: 12),

          // Source Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: [
                _buildSourceFilterChip('All Sources', 'ALL'),
                const SizedBox(width: 8),
                _buildSourceFilterChip('⚡ Direct Patient', 'PATIENT_DIRECT_BOOKING'),
                const SizedBox(width: 8),
                _buildSourceFilterChip('🛡️ Main Admin', 'MAIN_ADMIN_ASSIGNMENT'),
                const SizedBox(width: 8),
                _buildSourceFilterChip('👤 Sub-Admin', 'SUB_ADMIN_ASSIGNMENT'),
                const SizedBox(width: 14),
                Container(height: 18, width: 1, color: const Color(0xFFCBD5E1)),
                const SizedBox(width: 14),
                _buildStatusFilterChip('All Statuses', 'ALL'),
                const SizedBox(width: 8),
                _buildStatusFilterChip('Active', 'ACTIVE'),
                const SizedBox(width: 8),
                _buildStatusFilterChip('Reassigned', 'REASSIGNED'),
                const SizedBox(width: 8),
                _buildStatusFilterChip('Completed', 'COMPLETED'),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Assignment Records List
          if (filtered.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF012A58).withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.assignment_outlined, size: 40, color: Color(0xFF012A58)),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    history.isEmpty ? 'No Patient Assignments Recorded Yet' : 'No Assignments Match Filters',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textDark),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'All patient consultation requests, direct bookings, and doctor reassignments are immutably audited here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: AppTheme.textMuted, height: 1.4),
                  ),
                ],
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filtered.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final item = filtered[index];
                return _buildAssignmentCard(item);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildKpiCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: color),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  label,
                  style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSourceFilterChip(String label, String value) {
    final isSelected = _sourceFilter == value;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => setState(() => _sourceFilter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF012A58) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? const Color(0xFF012A58) : const Color(0xFFE2E8F0),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? Colors.white : AppTheme.textMuted,
          ),
        ),
      ),
    );
  }

  Widget _buildStatusFilterChip(String label, String value) {
    final isSelected = _statusFilter == value;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => setState(() => _statusFilter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFE3434) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? const Color(0xFFFE3434) : const Color(0xFFE2E8F0),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? Colors.white : AppTheme.textMuted,
          ),
        ),
      ),
    );
  }

  Widget _buildAssignmentCard(Map<String, dynamic> item) {
    final String pName = (item['patient_name'] ?? (item['patient'] is Map ? item['patient']['name'] : '') ?? 'Patient').toString();
    final String pPhone = (item['patient_phone'] ?? (item['patient'] is Map ? item['patient']['phone'] : '') ?? '').toString();
    final String dName = (item['dentist_name'] ?? (item['dentist'] is Map ? item['dentist']['name'] : '') ?? 'Dental Specialist').toString();
    final String dClinic = (item['clinic_name'] ?? (item['clinic'] is Map ? item['clinic']['clinic_name'] : '') ?? 'GS HEALTH Clinic').toString();
    final String district = (item['district_name'] ?? (item['district'] is Map ? item['district']['name'] : '') ?? (item['patient_district'] ?? 'District Verified')).toString();
    final String source = (item['assignment_source'] ?? 'MAIN_ADMIN_ASSIGNMENT').toString();
    final String assignedBy = (item['assigned_by_name'] ?? (item['assigned_by_user'] is Map ? item['assigned_by_user']['name'] : '') ?? 'Administrator').toString();
    final String status = (item['status'] ?? 'ACTIVE').toString().toUpperCase();
    final String reason = (item['reason'] ?? '').toString();
    final String notes = (item['notes'] ?? '').toString();
    final String createdAt = (item['created_at'] ?? '').toString();
    final String? prevDocName = item['previous_dentist_name']?.toString();

    // Source Chip Data
    Color sourceColor = const Color(0xFF012A58);
    String sourceLabel = 'Main Admin';
    if (source == 'PATIENT_DIRECT_BOOKING') {
      sourceColor = const Color(0xFF059669);
      sourceLabel = 'Direct Booking';
    } else if (source == 'SUB_ADMIN_ASSIGNMENT') {
      sourceColor = const Color(0xFF7C3AED);
      sourceLabel = 'Sub-Admin ($assignedBy)';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row: Patient Name, Mobile & District Chip
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFF012A58).withValues(alpha: 0.1),
                child: Text(
                  pName.isNotEmpty ? pName[0].toUpperCase() : 'P',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF012A58), fontSize: 13),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pName,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textDark),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (pPhone.isNotEmpty)
                      Text(
                        pPhone,
                        style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.location_on_rounded, size: 12, color: Color(0xFF012A58)),
                    const SizedBox(width: 3),
                    Text(
                      district,
                      style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF012A58)),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Assigned Doctor Banner
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                const Icon(Icons.medical_services_rounded, color: Color(0xFF012A58), size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        dName,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A)),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        dClinic,
                        style: const TextStyle(fontSize: 11.5, color: Color(0xFF475569)),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (prevDocName != null && prevDocName.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Reassigned from: $prevDocName',
                          style: const TextStyle(fontSize: 10.5, fontStyle: FontStyle.italic, color: Color(0xFFDC2626)),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: sourceColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    sourceLabel,
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: sourceColor),
                  ),
                ),
              ],
            ),
          ),

          if (reason.isNotEmpty || notes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              notes.isNotEmpty ? 'Guidance: $notes' : 'Reason: $reason',
              style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontStyle: FontStyle.italic),
            ),
          ],

          const SizedBox(height: 10),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 8),

          // Footer Row: Status, Date, Reassign Button & Timeline Button
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: status == 'ACTIVE' ? const Color(0xFFDCFCE7) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.bold,
                    color: status == 'ACTIVE' ? const Color(0xFF16A34A) : const Color(0xFF475569),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (createdAt.isNotEmpty)
                Expanded(
                  child: Text(
                    _formatDate(createdAt),
                    style: const TextStyle(fontSize: 10.5, color: AppTheme.textMuted),
                    overflow: TextOverflow.ellipsis,
                  ),
                )
              else
                const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.timeline_rounded, size: 14),
                label: const Text('Timeline', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF012A58),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () {
                  final pId = (item['patient_id'] ?? (item['patient'] is Map ? item['patient']['id'] : '') ?? '').toString();
                  if (pId.isNotEmpty) {
                    GsHealthAssignmentTimelineDialog.show(
                      context,
                      patientId: pId,
                      patientName: pName,
                    );
                  }
                },
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.sync_rounded, size: 13),
                label: const Text('Reassign', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFFE3434),
                  side: const BorderSide(color: Color(0xFFFE3434)),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => _showReassignDoctorDialog(context, item),
              ),
            ],
          ),
        ],
      ),
    );
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

  void _showReassignDoctorDialog(BuildContext context, Map<String, dynamic> item) {
    final patientId = (item['patient_id'] ?? (item['patient'] is Map ? item['patient']['id'] : '') ?? '').toString();
    final patientName = (item['patient_name'] ?? (item['patient'] is Map ? item['patient']['name'] : '') ?? 'Patient').toString();
    final currentDentistId = (item['dentist_id'] ?? '').toString();
    final previousAssignmentId = (item['id'] ?? '').toString();

    final allDocs = widget.problemService.allDoctors.where((d) => d.id != currentDentistId).toList();
    DoctorModel? selectedDoctor = allDocs.isNotEmpty ? allDocs.first : null;
    final reasonCtrl = TextEditingController(text: 'Specialist reassignment requested');
    final notesCtrl = TextEditingController();
    bool isSaving = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFE3434).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.sync_rounded, color: Color(0xFFFE3434), size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Reassign $patientName',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Select New Doctor *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(height: 6),
                    if (allDocs.isEmpty)
                      const Text('No other doctors available for reassignment.', style: TextStyle(fontSize: 12, color: AppTheme.textMuted))
                    else
                      DropdownButtonFormField<DoctorModel>(
                        initialValue: selectedDoctor,
                        isExpanded: true,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        items: allDocs.map((doc) {
                          return DropdownMenuItem<DoctorModel>(
                            value: doc,
                            child: Text(
                              '${doc.name} • ${doc.specialty} (${doc.city})',
                              style: const TextStyle(fontSize: 12.5),
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (val) => setDialogState(() => selectedDoctor = val),
                      ),
                    const SizedBox(height: 12),
                    const Text('Reassignment Reason *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: reasonCtrl,
                      decoration: InputDecoration(
                        hintText: 'e.g. Patient requested closer clinic, specialty needed',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text('Clinical Notes (Optional)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: notesCtrl,
                      maxLines: 2,
                      decoration: InputDecoration(
                        hintText: 'Notes for the new doctor...',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.all(10),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF012A58),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: (selectedDoctor == null || isSaving)
                      ? null
                      : () async {
                          setDialogState(() => isSaving = true);
                          final res = await widget.problemService.reassignPatient(
                            patientId: patientId,
                            newDentistId: selectedDoctor!.id,
                            previousAssignmentId: previousAssignmentId.isNotEmpty ? previousAssignmentId : null,
                            reason: reasonCtrl.text.trim(),
                            notes: notesCtrl.text.trim(),
                          );
                          setDialogState(() => isSaving = false);
                          if (dialogCtx.mounted) Navigator.of(dialogCtx).pop();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(res['success'] == true ? '✓ Patient reassigned to ${selectedDoctor!.name}.' : '⚠️ Reassignment failed.'),
                                backgroundColor: res['success'] == true ? const Color(0xFF10B981) : const Color(0xFFDC2626),
                              ),
                            );
                          }
                        },
                  child: isSaving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Confirm Reassignment'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
