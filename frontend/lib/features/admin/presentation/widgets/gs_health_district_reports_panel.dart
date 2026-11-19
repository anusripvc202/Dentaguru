import 'package:flutter/material.dart';
import '../../../../core/services/patient_problem_service.dart';
import '../../../../core/theme/app_theme.dart';

class GsHealthDistrictReportsPanel extends StatefulWidget {
  final PatientProblemService problemService;
  final VoidCallback onRefresh;

  const GsHealthDistrictReportsPanel({
    super.key,
    required this.problemService,
    required this.onRefresh,
  });

  @override
  State<GsHealthDistrictReportsPanel> createState() => _GsHealthDistrictReportsPanelState();
}

class _GsHealthDistrictReportsPanelState extends State<GsHealthDistrictReportsPanel> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final districts = widget.problemService.districts;
    final allPatients = widget.problemService.allPatients;
    final allDoctors = widget.problemService.allDoctors;
    final allClinics = widget.problemService.allClinics;
    final allAssignments = widget.problemService.assignmentHistory;
    final subAdmins = widget.problemService.subAdmins;

    final filtered = districts.where((d) {
      final name = (d['name'] ?? '').toString().toLowerCase();
      final state = (d['state'] ?? '').toString().toLowerCase();
      final q = _searchQuery.trim().toLowerCase();
      return q.isEmpty || name.contains(q) || state.contains(q);
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
                colors: [Color(0xFF012A58), Color(0xFF012A58)],
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
                  child: const Icon(Icons.bar_chart_rounded, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'District-Wise Platform Reports',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16.5,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Real-time territorial breakdown of patients, doctors, and assignments',
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
                  tooltip: 'Sync Reports',
                  onPressed: widget.onRefresh,
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Search Field
          TextField(
            onChanged: (val) => setState(() => _searchQuery = val),
            style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w500),
            cursorColor: AppTheme.primaryBlue,
            decoration: InputDecoration(
              hintText: 'Filter reports by district or state...',
              hintStyle: const TextStyle(fontSize: 12.5, color: AppTheme.textMuted),
              prefixIcon: const Icon(Icons.search_rounded, size: 18, color: AppTheme.primaryBlue),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
            ),
          ),

          const SizedBox(height: 16),

          // District Reports List
          if (filtered.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: const Column(
                children: [
                  Icon(Icons.query_stats_rounded, size: 40, color: AppTheme.textMuted),
                  SizedBox(height: 12),
                  Text(
                    'No District Data Available',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textDark),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'District metrics will populate automatically as patients and doctors register.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
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
                final d = filtered[index];
                final String dName = (d['name'] ?? 'District').toString();
                final String dState = (d['state'] ?? 'State').toString();
                final String dId = (d['id'] ?? '').toString();

                // Calculate district-level counts dynamically
                final dLower = dName.toLowerCase();
                final patientCount = allPatients.where((p) => p.city.toLowerCase().contains(dLower) || (p.district ?? '').toLowerCase() == dLower).length;
                final docCount = allDoctors.where((doc) => doc.city.toLowerCase().contains(dLower)).length;
                final clinicCount = allClinics.where((c) => c.location.toLowerCase().contains(dLower)).length;
                final assignmentCount = allAssignments.where((a) => (a['district_id'] ?? '').toString() == dId || (a['district_name'] ?? '').toString().toLowerCase() == dLower).length;
                final saCount = subAdmins.where((sa) {
                  final assigned = sa['assignedDistricts'];
                  if (assigned is List) {
                    return assigned.any((item) => item is Map && (item['id']?.toString() == dId || item['name']?.toString().toLowerCase() == dLower));
                  }
                  return false;
                }).length;

                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.02),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.location_on_rounded, color: Color(0xFF012A58), size: 18),
                              const SizedBox(width: 8),
                              Text(
                                dName,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF0F172A)),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              dState,
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Divider(height: 1, color: Color(0xFFF1F5F9)),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: _buildReportMetric('Patients', '$patientCount', const Color(0xFF012A58))),
                          Expanded(child: _buildReportMetric('Doctors', '$docCount', const Color(0xFFFE3434))),
                          Expanded(child: _buildReportMetric('Clinics', '$clinicCount', const Color(0xFF012A58))),
                          Expanded(child: _buildReportMetric('Assignments', '$assignmentCount', const Color(0xFFFE3434))),
                          Expanded(child: _buildReportMetric('Sub-Admins', '$saCount', const Color(0xFFFE3434))),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildReportMetric(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 10.5, color: AppTheme.textMuted),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
