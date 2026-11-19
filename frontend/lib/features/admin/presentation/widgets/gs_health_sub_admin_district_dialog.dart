import 'package:flutter/material.dart';
import '../../../../core/services/patient_problem_service.dart';
import '../../../../core/theme/app_theme.dart';

class GsHealthSubAdminDistrictDialog extends StatefulWidget {
  final Map<String, dynamic> subAdmin;
  final PatientProblemService problemService;

  const GsHealthSubAdminDistrictDialog({
    super.key,
    required this.subAdmin,
    required this.problemService,
  });

  static Future<bool?> show(
    BuildContext context, {
    required Map<String, dynamic> subAdmin,
    required PatientProblemService problemService,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => GsHealthSubAdminDistrictDialog(
        subAdmin: subAdmin,
        problemService: problemService,
      ),
    );
  }

  @override
  State<GsHealthSubAdminDistrictDialog> createState() => _GsHealthSubAdminDistrictDialogState();
}

class _GsHealthSubAdminDistrictDialogState extends State<GsHealthSubAdminDistrictDialog> {
  final Set<String> _selectedDistrictIds = {};
  String _searchQuery = '';
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final rawAssigned = widget.subAdmin['assignedDistricts'] ?? widget.subAdmin['assigned_districts'];
    if (rawAssigned is List) {
      for (final item in rawAssigned) {
        if (item is Map) {
          final id = (item['id'] ?? item['district_id'] ?? '').toString();
          if (id.isNotEmpty) _selectedDistrictIds.add(id);
        } else if (item != null) {
          _selectedDistrictIds.add(item.toString());
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final subAdminName = (widget.subAdmin['name'] ?? 'Sub-Admin').toString();
    final allDistricts = widget.problemService.districts;

    final filteredDistricts = allDistricts.where((d) {
      final name = (d['name'] ?? '').toString().toLowerCase();
      final state = (d['state'] ?? '').toString().toLowerCase();
      final code = (d['code'] ?? '').toString().toLowerCase();
      final q = _searchQuery.trim().toLowerCase();
      return q.isEmpty || name.contains(q) || state.contains(q) || code.contains(q);
    }).toList();

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
            child: const Icon(Icons.share_location_rounded, color: Color(0xFF012A58), size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Assign Districts',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16.5, color: Color(0xFF0F172A)),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Jurisdiction for $subAdminName',
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
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Select one or multiple districts. Sub-Admin will have access strictly restricted to patient inquiries and clinics in these verified territories.',
              style: TextStyle(fontSize: 12, color: Color(0xFF475569), height: 1.4),
            ),
            const SizedBox(height: 12),

            // Search Bar
            TextField(
              onChanged: (val) => setState(() => _searchQuery = val),
              style: const TextStyle(fontSize: 13, color: Color(0xFF0F172A), fontWeight: FontWeight.w500),
              decoration: InputDecoration(
                hintText: 'Filter districts...',
                hintStyle: const TextStyle(fontSize: 12.5, color: AppTheme.textMuted),
                prefixIcon: const Icon(Icons.search_rounded, size: 18, color: Color(0xFF012A58)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              ),
            ),

            const SizedBox(height: 10),

            // Selection summary counter
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_selectedDistrictIds.length} of ${allDistricts.length} Districts Assigned',
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF012A58)),
                ),
                if (_selectedDistrictIds.isNotEmpty)
                  TextButton(
                    onPressed: () => setState(() => _selectedDistrictIds.clear()),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(50, 24),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Clear All', style: TextStyle(fontSize: 11, color: Color(0xFFFE3434))),
                  ),
              ],
            ),

            const SizedBox(height: 8),

            // Scrollable list of selectable district chips
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: allDistricts.isEmpty
                  ? Container(
                      padding: const EdgeInsets.all(20),
                      alignment: Alignment.center,
                      child: const Text(
                        'No districts configured. Please add districts first in District Management.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                      ),
                    )
                  : SingleChildScrollView(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: filteredDistricts.map((d) {
                          final String dId = (d['id'] ?? '').toString();
                          final String dName = (d['name'] ?? 'District').toString();
                          final String dState = (d['state'] ?? '').toString();
                          final bool isSelected = _selectedDistrictIds.contains(dId);

                          return FilterChip(
                            label: Text(
                              dState.isNotEmpty ? '$dName ($dState)' : dName,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                color: isSelected ? Colors.white : const Color(0xFF1E293B),
                              ),
                            ),
                            selected: isSelected,
                            selectedColor: const Color(0xFF012A58),
                            checkmarkColor: Colors.white,
                            backgroundColor: const Color(0xFFF1F5F9),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: BorderSide(
                                color: isSelected ? const Color(0xFF012A58) : const Color(0xFFCBD5E1),
                              ),
                            ),
                            onSelected: (val) {
                              setState(() {
                                if (val) {
                                  _selectedDistrictIds.add(dId); // Zero duplication guaranteed by Set
                                } else {
                                  _selectedDistrictIds.remove(dId);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF012A58),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: _isSaving
              ? null
              : () async {
                  setState(() => _isSaving = true);
                  final saId = (widget.subAdmin['id'] ?? '').toString();
                  final ok = await widget.problemService.assignSubAdminDistricts(
                    saId,
                    _selectedDistrictIds.toList(),
                  );
                  setState(() => _isSaving = false);
                  if (context.mounted) {
                    Navigator.of(context).pop(ok);
                  }
                },
          child: _isSaving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Save Jurisdiction', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
