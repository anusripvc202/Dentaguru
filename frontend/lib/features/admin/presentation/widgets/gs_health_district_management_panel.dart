import 'package:flutter/material.dart';
import '../../../../core/services/patient_problem_service.dart';
import '../../../../core/theme/app_theme.dart';

class GsHealthDistrictManagementPanel extends StatefulWidget {
  final PatientProblemService problemService;
  final VoidCallback onRefresh;

  const GsHealthDistrictManagementPanel({
    super.key,
    required this.problemService,
    required this.onRefresh,
  });

  @override
  State<GsHealthDistrictManagementPanel> createState() => _GsHealthDistrictManagementPanelState();
}

class _GsHealthDistrictManagementPanelState extends State<GsHealthDistrictManagementPanel> {
  String _searchQuery = '';
  String _selectedStatus = 'All'; // 'All', 'Active', 'Inactive'
  bool _isCreatingDistrict = false;

  @override
  Widget build(BuildContext context) {
    final districts = widget.problemService.districts;
    final totalCount = districts.length;
    final activeCount = districts.where((d) => d['is_active'] != false).length;
    final inactiveCount = totalCount - activeCount;

    final filteredDistricts = districts.where((d) {
      final name = (d['name'] ?? '').toString().toLowerCase();
      final state = (d['state'] ?? '').toString().toLowerCase();
      final code = (d['code'] ?? '').toString().toLowerCase();
      final query = _searchQuery.trim().toLowerCase();

      final matchesQuery = query.isEmpty ||
          name.contains(query) ||
          state.contains(query) ||
          code.contains(query);

      final isActive = d['is_active'] != false;
      final matchesStatus = _selectedStatus == 'All' ||
          (_selectedStatus == 'Active' && isActive) ||
          (_selectedStatus == 'Inactive' && !isActive);

      return matchesQuery && matchesStatus;
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
                  child: const Icon(Icons.map_rounded, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Multiple District Management',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16.5,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '$totalCount Districts Registered • $activeCount Active • $inactiveCount Inactive',
                        style: const TextStyle(color: Colors.white70, fontSize: 11.5),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.add_location_alt_rounded, size: 16),
                  label: const Text('+ Add District', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFE3434),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => _showAddEditDistrictDialog(context),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Search and Filter Bar
          Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: (val) => setState(() => _searchQuery = val),
                  style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w500),
                  cursorColor: AppTheme.primaryBlue,
                  decoration: InputDecoration(
                    hintText: 'Search districts by name, state, or code...',
                    hintStyle: const TextStyle(fontSize: 12.5, color: AppTheme.textMuted),
                    prefixIcon: const Icon(Icons.search_rounded, size: 18, color: AppTheme.primaryBlue),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.filled(
                icon: const Icon(Icons.refresh_rounded, size: 18),
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFF012A58),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                tooltip: 'Sync Districts',
                onPressed: widget.onRefresh,
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Status Filter Chips
          Row(
            children: [
              _buildFilterChip('All ($totalCount)', 'All'),
              const SizedBox(width: 8),
              _buildFilterChip('Active ($activeCount)', 'Active'),
              const SizedBox(width: 8),
              _buildFilterChip('Inactive ($inactiveCount)', 'Inactive'),
            ],
          ),

          const SizedBox(height: 16),

          // District List or Clean Empty State
          if (filteredDistricts.isEmpty)
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
                    child: const Icon(Icons.location_city_rounded, size: 42, color: Color(0xFF012A58)),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    districts.isEmpty ? 'No Districts Initialized Yet' : 'No Districts Match Filter',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textDark),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Add Indian districts to enforce granular district-level patient access, multi-district coordinator assignment, and automated clinic routing.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: AppTheme.textMuted, height: 1.4),
                  ),
                  if (districts.isEmpty) ...[
                    const SizedBox(height: 18),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.add_location_alt_rounded, size: 16),
                      label: const Text('Add First District', style: TextStyle(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF012A58),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => _showAddEditDistrictDialog(context),
                    ),
                  ],
                ],
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filteredDistricts.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final d = filteredDistricts[index];
                return _buildDistrictCard(d);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _selectedStatus == value;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => setState(() => _selectedStatus = value),
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

  Widget _buildDistrictCard(Map<String, dynamic> d) {
    final String id = (d['id'] ?? '').toString();
    final String name = (d['name'] ?? 'District').toString();
    final String state = (d['state'] ?? 'State').toString();
    final String code = (d['code'] ?? '').toString().toUpperCase();
    final bool isActive = d['is_active'] != false;

    final int subAdminsCount = (d['assigned_sub_admins_count'] ?? (d['sub_admins'] is List ? (d['sub_admins'] as List).length : 0)) is int
        ? (d['assigned_sub_admins_count'] ?? (d['sub_admins'] is List ? (d['sub_admins'] as List).length : 0))
        : int.tryParse(d['assigned_sub_admins_count']?.toString() ?? '0') ?? 0;

    final int doctorsCount = (d['assigned_doctors_count'] ?? (d['doctors_count'] ?? 0)) is int
        ? (d['assigned_doctors_count'] ?? (d['doctors_count'] ?? 0))
        : int.tryParse(d['assigned_doctors_count']?.toString() ?? '0') ?? 0;

    final int patientsCount = (d['assigned_patients_count'] ?? (d['patients_count'] ?? 0)) is int
        ? (d['assigned_patients_count'] ?? (d['patients_count'] ?? 0))
        : int.tryParse(d['assigned_patients_count']?.toString() ?? '0') ?? 0;

    final List subAdmins = (d['sub_admins'] is List) ? (d['sub_admins'] as List) : [];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isActive ? const Color(0xFFE2E8F0) : const Color(0x40FE3434)),
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
          // Top Row: District Name, State, Code Chip, and Active Toggle
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isActive
                      ? const Color(0xFF012A58).withValues(alpha: 0.08)
                      : const Color(0xFFFE3434).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.location_on_rounded,
                  color: isActive ? const Color(0xFF012A58) : const Color(0xFFFE3434),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textDark),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (code.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFFCBD5E1)),
                            ),
                            child: Text(
                              code,
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
                            ),
                          ),
                        ],
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: isActive ? const Color(0x14012A58) : const Color(0x14FE3434),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            isActive ? 'Active' : 'Inactive',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: isActive ? const Color(0xFFFE3434) : const Color(0xFFFE3434),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'State: $state',
                      style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Switch(
                value: isActive,
                activeThumbColor: const Color(0xFF012A58),
                onChanged: (val) async {
                  await widget.problemService.toggleDistrictStatus(id, val);
                  if (!mounted) return;
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(val ? '✓ District "$name" activated.' : '⛔ District "$name" deactivated.'),
                      backgroundColor: val ? const Color(0xFF012A58) : const Color(0xFFFE3434),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
              ),
            ],
          ),

          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 10),

          // District Coverage Metrics
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _buildMetricChip(Icons.supervisor_account_rounded, '$subAdminsCount Coordinators', const Color(0xFFFE3434)),
              _buildMetricChip(Icons.medical_services_rounded, '$doctorsCount Doctors', const Color(0xFF012A58)),
              _buildMetricChip(Icons.people_alt_rounded, '$patientsCount Patients', const Color(0xFF012A58)),
            ],
          ),

          if (subAdmins.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Assigned: ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textMuted)),
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: subAdmins.map((sa) {
                      final saName = sa is Map ? (sa['name'] ?? 'Coordinator').toString() : sa.toString();
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0x14FE3434),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0x40FE3434)),
                        ),
                        child: Text(
                          saName,
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF012A58)),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 10),

          // Action Button
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.edit_rounded, size: 14),
                label: const Text('Edit District', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF012A58),
                  side: const BorderSide(color: Color(0xFF012A58)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => _showAddEditDistrictDialog(context, existingDistrict: d),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricChip(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  void _showAddEditDistrictDialog(BuildContext context, {Map<String, dynamic>? existingDistrict}) {
    final bool isEdit = existingDistrict != null;
    final nameCtrl = TextEditingController(text: isEdit ? (existingDistrict['name'] ?? '').toString() : '');
    final stateCtrl = TextEditingController(text: isEdit ? (existingDistrict['state'] ?? '').toString() : 'Telangana');
    final codeCtrl = TextEditingController(text: isEdit ? (existingDistrict['code'] ?? '').toString() : '');
    bool isActive = isEdit ? (existingDistrict['is_active'] != false) : true;
    final formKey = GlobalKey<FormState>();

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
                      color: const Color(0xFF012A58).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.add_location_alt_rounded, color: Color(0xFF012A58), size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      isEdit ? 'Edit District' : 'Add New District',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('District Name *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: nameCtrl,
                        decoration: InputDecoration(
                          hintText: 'e.g. Hyderabad, Pune, Mumbai City',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'District name is required' : null,
                      ),
                      const SizedBox(height: 12),
                      const Text('State *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: stateCtrl,
                        decoration: InputDecoration(
                          hintText: 'e.g. Telangana, Maharashtra, Karnataka',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'State is required' : null,
                      ),
                      const SizedBox(height: 12),
                      const Text('District Code (Optional)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: codeCtrl,
                        textCapitalization: TextCapitalization.characters,
                        decoration: InputDecoration(
                          hintText: 'e.g. HYD, PUN, MUM',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Active Status', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          Switch(
                            value: isActive,
                            activeThumbColor: const Color(0xFF012A58),
                            onChanged: (val) => setDialogState(() => isActive = val),
                          ),
                        ],
                      ),
                    ],
                  ),
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
                  onPressed: _isCreatingDistrict
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) return;
                          setDialogState(() => _isCreatingDistrict = true);
                          bool success = false;
                          if (isEdit) {
                            success = await widget.problemService.updateDistrict(
                              id: existingDistrict['id'].toString(),
                              name: nameCtrl.text.trim(),
                              state: stateCtrl.text.trim(),
                              code: codeCtrl.text.trim(),
                              isActive: isActive,
                            );
                          } else {
                            success = await widget.problemService.createDistrict(
                              name: nameCtrl.text.trim(),
                              state: stateCtrl.text.trim(),
                              code: codeCtrl.text.trim(),
                              isActive: isActive,
                            );
                          }
                          setDialogState(() => _isCreatingDistrict = false);
                          if (dialogCtx.mounted) Navigator.of(dialogCtx).pop();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(success ? '✓ District saved successfully.' : '⚠️ Failed to save district.'),
                                backgroundColor: success ? const Color(0xFF012A58) : const Color(0xFFFE3434),
                              ),
                            );
                          }
                        },
                  child: Text(isEdit ? 'Save Changes' : 'Create District'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
