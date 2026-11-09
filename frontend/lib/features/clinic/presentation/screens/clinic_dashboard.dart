import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/widgets/denta_guru_logo.dart';
import '../../../../core/models/medical_specialty_model.dart';
import '../../../../core/services/patient_problem_service.dart';
import '../../../../core/services/session_service.dart';
import '../../../admin/presentation/widgets/doctor_slot_management_dialog.dart';
import '../../../patient/presentation/screens/doctor_profile_screen.dart';
import 'package:go_router/go_router.dart';

class ClinicDashboardScreen extends StatefulWidget {
  final String? clinicName;
  final int initialTab;
  const ClinicDashboardScreen({super.key, this.clinicName, this.initialTab = 0});

  @override
  State<ClinicDashboardScreen> createState() => _ClinicDashboardScreenState();
}

class _ClinicDashboardScreenState extends State<ClinicDashboardScreen> {
  int _currentIndex = 0;
  String? _selectedClinicOverride;
  String _selectedDoctorDepartmentFilter = 'All';
  String _searchDoctorQuery = '';
  String _selectedAppointmentDoctor = 'All';
  final PatientProblemService _problemService = PatientProblemService();

  String get _currentClinicName {
    if (_selectedClinicOverride != null && _selectedClinicOverride!.trim().isNotEmpty) {
      return _selectedClinicOverride!.trim();
    }
    if (widget.clinicName != null && widget.clinicName!.trim().isNotEmpty) {
      return widget.clinicName!.trim();
    }
    final session = SessionService().currentSession;
    final metaClinic = session?.metadata['clinicName'] ?? session?.metadata['clinic_name'];
    if (metaClinic != null && metaClinic.toString().trim().isNotEmpty) {
      return metaClinic.toString().trim();
    }
    final sessionRole = session?.role.toLowerCase() ?? '';
    if (session?.name != null && session!.name!.trim().isNotEmpty && !sessionRole.contains('admin')) {
      return session.name!.trim();
    }
    final allClinics = _problemService.allClinics;
    if (allClinics.isNotEmpty) {
      return allClinics.first.clinicName;
    }
    return 'GS HEALTH Partner Clinic';
  }

  List<DoctorModel> get _clinicDoctors {
    return _problemService.getClinicDoctors(_currentClinicName);
  }

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialTab.clamp(0, 4);
    if (widget.clinicName != null && widget.clinicName!.trim().isNotEmpty) {
      _selectedClinicOverride = widget.clinicName!.trim();
    }
    _problemService.addListener(_onServiceUpdate);
    _loadSavedProcedurePrices();
    _problemService.syncAllDataFromApi();
  }

  Future<void> _loadSavedProcedurePrices() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('dentaguru_clinic_procedure_prices');
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map && mounted) {
          setState(() {
            decoded.forEach((k, v) {
              _procedurePrices[k.toString()] = v.toString();
            });
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _saveProcedurePrices() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('dentaguru_clinic_procedure_prices', jsonEncode(_procedurePrices));
    } catch (_) {}
  }

  @override
  void dispose() {
    _problemService.removeListener(_onServiceUpdate);
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final allClinics = _problemService.allClinics;

    return Scaffold(
      appBar: AppBar(
        leading: Navigator.of(context).canPop()
            ? IconButton(
                icon: const Icon(Icons.arrow_back, color: Color(0xFF0F172A)),
                tooltip: 'Back',
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const DentaGuruLogo(height: 24),
            const SizedBox(width: 8),
            Flexible(
              child: allClinics.length > 1
                  ? PopupMenuButton<String>(
                      tooltip: 'Switch Clinic',
                      initialValue: _currentClinicName,
                      onSelected: (val) {
                        setState(() {
                          _selectedClinicOverride = val;
                        });
                      },
                      itemBuilder: (ctx) => allClinics
                          .map((c) => PopupMenuItem(
                                value: c.clinicName,
                                child: Text(c.clinicName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                              ))
                          .toList(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0D9488).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF0D9488).withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                _currentClinicName,
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0D9488)),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.arrow_drop_down, size: 16, color: Color(0xFF0D9488)),
                          ],
                        ),
                      ),
                    )
                  : Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0D9488).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _currentClinicName,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0D9488)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
            tooltip: 'Log Out',
            onPressed: () async {
              await SessionService().clearSession();
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Logged out of Clinic workspace.'),
                  duration: Duration(seconds: 2),
                ),
              );
              context.go('/login');
            },
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _buildOverviewTab(theme),
          _buildDoctorsTab(theme),
          _buildDepartmentsTab(theme),
          _buildAppointmentsTab(theme),
          _buildServicesTab(theme),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFF0D9488),
        unselectedItemColor: Colors.grey.shade600,
        selectedFontSize: 11.5,
        unselectedFontSize: 11,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard_outlined), label: 'Overview'),
          BottomNavigationBarItem(icon: Icon(Icons.people_alt_outlined), label: 'Doctors'),
          BottomNavigationBarItem(icon: Icon(Icons.apartment_rounded), label: 'Departments'),
          BottomNavigationBarItem(icon: Icon(Icons.calendar_month_outlined), label: 'Appointments'),
          BottomNavigationBarItem(icon: Icon(Icons.list_alt), label: 'Services'),
        ],
      ),
    );
  }

  Widget _buildOverviewTab(ThemeData theme) {
    final doctors = _problemService.allDoctors;
    final requests = _problemService.requests;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Clinic Insights', style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          
          // Row of stats cards
          Row(
            children: [
              Expanded(
                child: _buildMetricCard('${doctors.length}', 'Attached Doctors', Colors.teal, theme),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricCard('${_problemService.clinicDepartments.length}', 'Active Departments', Colors.indigo, theme),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricCard('${requests.length}', 'Total Bookings', Colors.blue, theme),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Working hours card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.watch_later_outlined, color: Color(0xFF0D9488)),
                      const SizedBox(width: 8),
                      Text('Working Hours', style: theme.textTheme.titleMedium),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Monday - Friday'),
                      Text('09:00 AM - 08:00 PM', style: TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const Divider(height: 24),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Saturday'),
                      Text('10:00 AM - 05:00 PM', style: TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Platform active subscription details
          Card(
            color: const Color(0xFF0F172A),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Premium subscription', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      SizedBox(height: 4),
                      Text('Renew date: Aug 24, 2026', style: TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.teal.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text('ACTIVE', style: TextStyle(color: Colors.tealAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                  )
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildMetricCard(String val, String label, Color color, ThemeData theme) {
    return Card(
      elevation: 0,
      color: color.withOpacity(0.05),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: color.withOpacity(0.15)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(val, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _buildDoctorsTab(ThemeData theme) {
    final clinicDocs = _clinicDoctors;
    final doctors = clinicDocs.where((d) {
      final matchesDept = _selectedDoctorDepartmentFilter == 'All' ||
          MedicalSpecialtyModel.matchesSpecialtyFilter(
            d.specialty,
            _selectedDoctorDepartmentFilter,
            specialties: _problemService.specialties,
          );
      final q = _searchDoctorQuery.trim().toLowerCase();
      final matchesSearch = q.isEmpty ||
          d.name.toLowerCase().contains(q) ||
          d.specialty.toLowerCase().contains(q) ||
          d.qualification.toLowerCase().contains(q);
      return matchesDept && matchesSearch;
    }).toList();

    final filterChips = <String>['All', ..._problemService.clinicDepartments];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Clinic Header & Add Doctor
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Attached Doctors (${doctors.length})',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'Doctors registered & associated with $_currentClinicName',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              key: const Key('clinic_add_doctor_button'),
              icon: const Icon(Icons.add, size: 16, color: Colors.white),
              label: const Text('Add Doctor', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0D9488),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => _showAddDoctorDialog(context),
            )
          ],
        ),
        const SizedBox(height: 12),

        // Search Doctor Input
        TextField(
          onChanged: (val) => setState(() => _searchDoctorQuery = val),
          decoration: InputDecoration(
            hintText: 'Search doctor by name or specialty...',
            prefixIcon: const Icon(Icons.search, size: 20, color: Color(0xFF0D9488)),
            suffixIcon: _searchDoctorQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () => setState(() => _searchDoctorQuery = ''),
                  )
                : null,
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Department filter chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: filterChips.map((dept) {
              final selected = _selectedDoctorDepartmentFilter == dept;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(dept, style: TextStyle(fontSize: 11.5, color: selected ? Colors.white : Colors.black87)),
                  selected: selected,
                  selectedColor: const Color(0xFF0D9488),
                  onSelected: (_) => setState(() => _selectedDoctorDepartmentFilter = dept),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 14),

        if (doctors.isEmpty)
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: [
                const Icon(Icons.medical_services_outlined, size: 40, color: Colors.grey),
                const SizedBox(height: 12),
                const Text('No Doctors Associated with this Clinic', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 6),
                Text(
                  'Click "Add Doctor" above to register or associate a doctor with $_currentClinicName.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          )
        else
          ...doctors.map((doc) => _buildDoctorListRow(doc)),
      ],
    );
  }

  void _openClinicDoctorProfile(DoctorModel doc) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DoctorProfileScreen(
          doctor: doc,
          isClinicView: true,
          onAdminEditDoctor: () => _showEditClinicDoctorDialog(context, doc),
          onClinicRemoveDoctor: () => _confirmRemoveDoctorFromClinic(context, doc),
        ),
      ),
    );
  }

  Widget _buildDoctorListRow(DoctorModel doc) {
    final isAvailable = doc.status.toLowerCase() == 'available';
    final statusColor = isAvailable ? Colors.green : Colors.amber.shade800;
    final statusText = isAvailable ? 'Active' : (doc.status.isNotEmpty ? doc.status : 'Inactive');

    final rawInitial = doc.name.replaceAll(RegExp(r'^Dr\.?\s*', caseSensitive: false), '').trim();
    final initial = rawInitial.isNotEmpty ? rawInitial[0].toUpperCase() : 'D';

    return Card(
      key: Key('clinic_doctor_card_${doc.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 0,
      color: Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _openClinicDoctorProfile(doc),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Doctor Profile Image (CircleAvatar)
                  GestureDetector(
                    key: Key('clinic_doctor_image_${doc.id}'),
                    onTap: () => _openClinicDoctorProfile(doc),
                    child: CircleAvatar(
                      radius: 24,
                      backgroundColor: const Color(0xFF0D9488).withValues(alpha: 0.12),
                      backgroundImage: doc.photoBytes != null ? MemoryImage(doc.photoBytes!) : null,
                      child: doc.photoBytes == null
                          ? Text(
                              initial,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                                color: Color(0xFF0D9488),
                              ),
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Doctor Full Name & Specialty
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GestureDetector(
                          key: Key('clinic_doctor_name_${doc.id}'),
                          onTap: () => _openClinicDoctorProfile(doc),
                          child: Text(
                            doc.name,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          doc.specialty,
                          style: const TextStyle(fontSize: 12, color: Color(0xFF0D9488), fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (doc.qualification.isNotEmpty)
                          Text(
                            doc.qualification,
                            style: const TextStyle(fontSize: 11, color: Colors.black54),
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  // Active / Inactive Status Badge
                  InkWell(
                    key: Key('clinic_status_toggle_${doc.id}'),
                    borderRadius: BorderRadius.circular(8),
                    onTap: () async {
                      final newStatus = isAvailable ? 'Inactive' : 'Available';
                      await _problemService.updateDoctorProfessionalProfile(
                        doctorId: doc.id,
                        status: newStatus,
                      );
                      setState(() {});
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Dr. ${doc.name} status updated to $newStatus')),
                        );
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            statusText,
                            style: TextStyle(fontSize: 11, color: statusColor, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Divider(height: 1, color: Color(0xFFF1F5F9)),
              const SizedBox(height: 8),

              // Action Toolbar: View Profile, Edit, Availability, Remove
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  OutlinedButton.icon(
                    key: Key('clinic_view_profile_${doc.id}'),
                    onPressed: () => _openClinicDoctorProfile(doc),
                    icon: const Icon(Icons.person_outline_rounded, size: 14, color: Color(0xFF0D9488)),
                    label: const Text('View Profile', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF0D9488))),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF0D9488)),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        key: Key('clinic_edit_button_${doc.id}'),
                        tooltip: 'Edit Doctor Details',
                        icon: const Icon(Icons.edit_outlined, size: 18, color: Colors.blueGrey),
                        onPressed: () => _showEditClinicDoctorDialog(context, doc),
                      ),
                      IconButton(
                        key: Key('clinic_slots_button_${doc.id}'),
                        tooltip: 'Update Availability Slots',
                        icon: const Icon(Icons.event_available_rounded, size: 18, color: Color(0xFF0D9488)),
                        onPressed: () => DoctorSlotManagementDialog.show(context, initialDoctor: doc),
                      ),
                      IconButton(
                        key: Key('clinic_remove_button_${doc.id}'),
                        tooltip: 'Remove Doctor from Clinic',
                        icon: const Icon(Icons.person_remove_outlined, size: 18, color: Colors.redAccent),
                        onPressed: () => _confirmRemoveDoctorFromClinic(context, doc),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDepartmentsTab(ThemeData theme) {
    final activeSpecs = _problemService.activeSpecialties;
    final enabledDepts = _problemService.clinicDepartments;
    final customDeptCtrl = TextEditingController();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                'Medical Departments (${enabledDepts.length})',
                style: theme.textTheme.titleMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.add_business_rounded, size: 16, color: Colors.white),
              label: const Text('Add Department', style: TextStyle(color: Colors.white, fontSize: 12)),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0D9488)),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (dialogCtx) => AlertDialog(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    title: const Text('Add Clinic Department', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    content: TextField(
                      controller: customDeptCtrl,
                      decoration: InputDecoration(
                        labelText: 'Department / Specialty Name',
                        hintText: 'e.g. Cardiology or Nephrology',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.of(dialogCtx).pop(), child: const Text('Cancel')),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0D9488)),
                        onPressed: () async {
                          final val = customDeptCtrl.text.trim();
                          if (val.isNotEmpty) {
                            await _problemService.addClinicDepartment(val);
                            if (dialogCtx.mounted) Navigator.of(dialogCtx).pop();
                          }
                        },
                        child: const Text('Save Department', style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'Enable or disable medical specialties offered at this clinic and view attached specialists per department.',
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
        const SizedBox(height: 16),
        ...activeSpecs.map((spec) {
          final isEnabled = enabledDepts.any((d) => d.toLowerCase() == spec.name.toLowerCase());
          final deptDoctors = _problemService.allDoctors
              .where((d) => MedicalSpecialtyModel.matchesSpecialtyFilter(d.specialty, spec.name, specialties: _problemService.specialties))
              .toList();
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: const Color(0xFF0D9488).withValues(alpha: 0.12),
                child: Icon(spec.iconData, color: const Color(0xFF0D9488), size: 20),
              ),
              title: Text(spec.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              subtitle: Text(
                '${spec.department} • ${deptDoctors.length} Attached Doctor(s) • Default: ${spec.defaultQualifications}',
                style: const TextStyle(fontSize: 11.5),
              ),
              trailing: Switch(
                value: isEnabled,
                activeThumbColor: const Color(0xFF0D9488),
                onChanged: (val) {
                  if (val) {
                    _problemService.addClinicDepartment(spec.name);
                  } else {
                    _problemService.removeClinicDepartment(spec.name);
                  }
                },
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildAppointmentsTab(ThemeData theme) {
    final clinicDocs = _clinicDoctors;
    final clinicDocNames = clinicDocs.map((d) => d.name.toLowerCase()).toSet();
    final clinicDocIds = clinicDocs.map((d) => d.id).toSet();
    final clinicNameClean = _currentClinicName.trim().toLowerCase();

    // Filter appointments associated with this clinic's doctors
    final allClinicAppointments = _problemService.requests.where((req) {
      final reqClinic = (req.assignedDoctorClinic ?? '').trim().toLowerCase();
      if (reqClinic.isNotEmpty && (reqClinic == clinicNameClean || clinicNameClean.contains(reqClinic) || reqClinic.contains(clinicNameClean))) {
        return true;
      }
      if (req.assignedDoctorId != null && clinicDocIds.contains(req.assignedDoctorId)) {
        return true;
      }
      if (req.assignedDoctorName != null && clinicDocNames.contains(req.assignedDoctorName!.toLowerCase())) {
        return true;
      }
      if (clinicNameClean.contains('gs health') || clinicNameClean.contains('partner clinic')) {
        return true;
      }
      return false;
    }).toList();

    // Doctor-wise filtering
    final filteredAppointments = allClinicAppointments.where((req) {
      if (_selectedAppointmentDoctor == 'All') return true;
      final docName = req.displayDoctorName.toLowerCase();
      final selName = _selectedAppointmentDoctor.toLowerCase();
      return docName == selName || docName.contains(selName) || (req.assignedDoctorId == _selectedAppointmentDoctor);
    }).toList();

    // Check for overlapping appointment slots across active appointments
    final slotCounts = <String, int>{};
    for (final appt in allClinicAppointments) {
      final s = appt.status.toUpperCase();
      if (s == 'CANCELLED' || s == 'REJECTED') continue;
      final docKey = appt.assignedDoctorId ?? appt.assignedDoctorName ?? 'Unassigned';
      final dateKey = appt.confirmedDate ?? appt.submittedAt.toIso8601String().split('T').first;
      final slotKey = (appt.confirmedTimeSlot ?? 'Pending').trim().toLowerCase();
      if (slotKey != 'pending' && slotKey.isNotEmpty) {
        final uniqueKey = '${docKey}_${dateKey}_$slotKey';
        slotCounts[uniqueKey] = (slotCounts[uniqueKey] ?? 0) + 1;
      }
    }
    final hasOverlaps = slotCounts.values.any((c) => c > 1);

    final doctorFilterOptions = <String>[
      'All',
      ...clinicDocs.map((d) => d.name),
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Clinic Appointments (${allClinicAppointments.length})', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  Text('Doctor-wise consultation schedules & booking management', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Overlapping slot warning banner
        if (hasOverlaps)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFCA5A5)),
            ),
            child: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.red, size: 22),
                SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Overlapping Slot Alert Detected',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.red),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Multiple bookings exist for the same doctor, date, and time slot. Reschedule conflicting slots to avoid patient wait times.',
                        style: TextStyle(fontSize: 11, color: Colors.black87),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

        // Doctor-wise filter strip
        if (doctorFilterOptions.length > 1) ...[
          const Text('Filter by Doctor Schedule:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: doctorFilterOptions.map((docName) {
                final selected = _selectedAppointmentDoctor == docName;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(
                      docName,
                      style: TextStyle(fontSize: 11.5, color: selected ? Colors.white : Colors.black87),
                    ),
                    selected: selected,
                    selectedColor: const Color(0xFF0D9488),
                    onSelected: (_) => setState(() => _selectedAppointmentDoctor = docName),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 14),
        ],

        if (filteredAppointments.isEmpty)
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: const Column(
              children: [
                Icon(Icons.calendar_month_outlined, size: 36, color: Colors.grey),
                SizedBox(height: 10),
                Text('No Appointments Scheduled', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                SizedBox(height: 4),
                Text('Appointments for clinic doctors will appear here automatically.', style: TextStyle(fontSize: 11.5, color: Colors.grey)),
              ],
            ),
          )
        else
          ...filteredAppointments.map((req) {
            final isConfirmed = req.status.toUpperCase().contains('CONFIRM') || req.status.toUpperCase().contains('ACCEPT');
            final isCancelled = req.status.toUpperCase() == 'CANCELLED';

            final docKey = req.assignedDoctorId ?? req.assignedDoctorName ?? 'Unassigned';
            final dateKey = req.confirmedDate ?? req.submittedAt.toIso8601String().split('T').first;
            final slotKey = (req.confirmedTimeSlot ?? 'Pending').trim().toLowerCase();
            final isConflicted = !isCancelled && slotKey != 'pending' && (slotCounts['${docKey}_${dateKey}_$slotKey'] ?? 0) > 1;

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: isConflicted ? Colors.red.shade300 : const Color(0xFFE2E8F0),
                  width: isConflicted ? 1.5 : 1,
                ),
              ),
              color: Colors.white,
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: (isConflicted
                                  ? Colors.red
                                  : (isConfirmed ? Colors.green : Colors.blue))
                              .withValues(alpha: 0.12),
                          child: Icon(
                            isConflicted
                                ? Icons.warning_rounded
                                : (isConfirmed ? Icons.event_available_rounded : Icons.schedule_rounded),
                            color: isConflicted
                                ? Colors.red
                                : (isConfirmed ? Colors.green : Colors.blue),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${req.patientName} • ${req.problemCategory}',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                'Doctor: ${req.displayDoctorName.isNotEmpty ? req.displayDoctorName : "Unassigned"} (${req.displayDoctorSpecialty.isNotEmpty ? req.displayDoctorSpecialty : "General"})',
                                style: const TextStyle(fontSize: 11.5, color: Color(0xFF0D9488), fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                '📅 ${req.confirmedDate ?? "Date pending"} • ⏰ ${req.confirmedTimeSlot ?? "Time pending"}',
                                style: const TextStyle(fontSize: 11, color: Colors.black54),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: (isCancelled
                                    ? Colors.grey
                                    : (isConfirmed ? Colors.green : Colors.orange))
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            req.status,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: isCancelled
                                  ? Colors.grey.shade700
                                  : (isConfirmed ? Colors.green.shade700 : Colors.orange.shade800),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (isConflicted) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.error_outline_rounded, size: 14, color: Colors.red.shade700),
                            const SizedBox(width: 5),
                            Text(
                              'Overlapping Slot Conflict with another patient',
                              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.red.shade700),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  final Map<String, String> _procedurePrices = {
    'General Consultation & Checkup': '\$75',
    'Tooth Decay / Cavity Filling': '\$85',
    'Periodontics & Gum Care': '\$95',
    'Tooth Extraction Surgery': '\$110',
    'Root Canal Therapy (RCT)': '\$180',
    'Orthodontic Consultation & Braces': '\$200',
  };

  void _showEditPriceDialog(String service, String currentPrice) {
    final priceCtrl = TextEditingController(text: currentPrice);
    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Text('Edit Rate for $service', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          content: TextField(
            controller: priceCtrl,
            style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w500),
            cursorColor: const Color(0xFF0D9488),
            decoration: InputDecoration(
              labelText: 'New Procedure Rate',
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogCtx).pop(), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0D9488)),
              onPressed: () {
                setState(() {
                  _procedurePrices[service] = priceCtrl.text.trim();
                });
                _saveProcedurePrices();
                Navigator.of(dialogCtx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('💰 Rate for $service updated to ${priceCtrl.text.trim()}!')),
                );
              },
              child: const Text('Save Rate', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  void _showAddProcedureDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final priceCtrl = TextEditingController(text: '\$75');
    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text('Add Procedure Rate', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w500),
                cursorColor: const Color(0xFF0D9488),
                decoration: InputDecoration(
                  labelText: 'Procedure Name *',
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: priceCtrl,
                style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w500),
                cursorColor: const Color(0xFF0D9488),
                decoration: InputDecoration(
                  labelText: 'Rate *',
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogCtx).pop(), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0D9488)),
              onPressed: () {
                final name = nameCtrl.text.trim();
                final rate = priceCtrl.text.trim();
                if (name.isEmpty || rate.isEmpty) return;
                setState(() {
                  _procedurePrices[name] = rate;
                });
                _saveProcedurePrices();
                Navigator.of(dialogCtx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('✅ Added procedure "$name" ($rate)')),
                );
              },
              child: const Text('Add Procedure', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  void _showAddDoctorDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final licenseCtrl = TextEditingController();
    final qualCtrl = TextEditingController();
    final expCtrl = TextEditingController(text: '5');
    final feeCtrl = TextEditingController(text: '₹500');
    final bioCtrl = TextEditingController();
    final cityCtrl = TextEditingController();
    final pincodeCtrl = TextEditingController();

    String selectedSpecialty = 'General Medicine';
    final List<String> selectedDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'];
    final List<String> selectedSlots = ['09:00 AM', '11:30 AM', '02:00 PM', '04:30 PM'];

    DoctorModel? detectedExistingDoctor;

    final allDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final defaultSlotOptions = ['09:00 AM', '10:00 AM', '11:30 AM', '02:00 PM', '04:00 PM', '05:30 PM'];

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            void checkExisting() {
              final ph = phoneCtrl.text.trim();
              final em = emailCtrl.text.trim();
              final lic = licenseCtrl.text.trim();
              final match = _problemService.findExistingDoctor(
                phone: ph.length >= 10 ? ph : null,
                email: em.contains('@') ? em : null,
                licenseNumber: lic.isNotEmpty ? lic : null,
              );
              if (match?.id != detectedExistingDoctor?.id) {
                setModalState(() {
                  detectedExistingDoctor = match;
                  if (match != null) {
                    if (nameCtrl.text.trim().isEmpty) nameCtrl.text = match.name;
                    if (qualCtrl.text.trim().isEmpty) qualCtrl.text = match.qualification;
                    if (licenseCtrl.text.trim().isEmpty) licenseCtrl.text = match.licenseNumber;
                    if (bioCtrl.text.trim().isEmpty) bioCtrl.text = match.bio;
                    if (selectedSpecialty.isEmpty) selectedSpecialty = match.specialty;
                  }
                });
              }
            }

            final activeSpecNames = <String>{
              'General Medicine',
              ..._problemService.activeSpecialtyNames,
              'Dentistry',
              'Cardiology',
              'Dermatology',
              'Pediatrics',
              'Orthopedics',
            }.toList();

            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 580, maxHeight: 720),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0D9488).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.person_add_alt_1_rounded, color: Color(0xFF0D9488), size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Add Attached Doctor',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF0F172A)),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  'Add & Associate Doctor with $_currentClinicName',
                                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 20, color: Colors.grey),
                            onPressed: () => Navigator.of(dialogCtx).pop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Divider(height: 1),
                      const SizedBox(height: 12),

                      // Existing Doctor Detected Banner
                      if (detectedExistingDoctor != null)
                        Container(
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFF93C5FD)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.verified_user_rounded, color: Color(0xFF2563EB), size: 18),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Existing GS HEALTH Doctor Found: ${detectedExistingDoctor!.name}',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Color(0xFF1E3A8A)),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Specialty: ${detectedExistingDoctor!.specialty} • Current: ${detectedExistingDoctor!.clinicName.isNotEmpty ? detectedExistingDoctor!.clinicName : "Independent"}\nAssociate with $_currentClinicName without creating a duplicate account.',
                                style: const TextStyle(fontSize: 11, color: Color(0xFF1E40AF)),
                              ),
                            ],
                          ),
                        ),

                      // Form Fields Body
                      Expanded(
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Full Name & Profile Image Avatar Preview
                              Row(
                                children: [
                                  CircleAvatar(
                                    radius: 22,
                                    backgroundColor: const Color(0xFF0D9488).withValues(alpha: 0.15),
                                    child: Text(
                                      nameCtrl.text.trim().isNotEmpty
                                          ? nameCtrl.text.trim().replaceAll('Dr.', '').trim().characters.first.toUpperCase()
                                          : 'DR',
                                      style: const TextStyle(color: Color(0xFF0D9488), fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: TextField(
                                      controller: nameCtrl,
                                      onChanged: (_) => setModalState(() {}),
                                      decoration: InputDecoration(
                                        labelText: 'Doctor Full Name *',
                                        hintText: 'e.g. Dr. Jane Miller',
                                        prefixIcon: const Icon(Icons.person_outline, size: 18),
                                        filled: true,
                                        fillColor: const Color(0xFFF8FAFC),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),

                              // Mobile Number & Email Address
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: phoneCtrl,
                                      keyboardType: TextInputType.phone,
                                      onChanged: (_) => checkExisting(),
                                      decoration: InputDecoration(
                                        labelText: 'Mobile Number *',
                                        hintText: 'e.g. 9876543210',
                                        prefixIcon: const Icon(Icons.phone_android_rounded, size: 18),
                                        filled: true,
                                        fillColor: const Color(0xFFF8FAFC),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TextField(
                                      controller: emailCtrl,
                                      keyboardType: TextInputType.emailAddress,
                                      onChanged: (_) => checkExisting(),
                                      decoration: InputDecoration(
                                        labelText: 'Email Address',
                                        hintText: 'e.g. jane@gshealth.com',
                                        prefixIcon: const Icon(Icons.email_outlined, size: 18),
                                        filled: true,
                                        fillColor: const Color(0xFFF8FAFC),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),

                              // Medical Specialty & Qualification
                              Row(
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: DropdownButtonFormField<String>(
                                      initialValue: activeSpecNames.contains(selectedSpecialty) ? selectedSpecialty : activeSpecNames.first,
                                      isExpanded: true,
                                      decoration: InputDecoration(
                                        labelText: 'Medical Specialty *',
                                        prefixIcon: const Icon(Icons.medical_services_outlined, size: 18),
                                        filled: true,
                                        fillColor: const Color(0xFFF8FAFC),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                      items: activeSpecNames
                                          .map((s) => DropdownMenuItem(
                                                value: s,
                                                child: Text(s, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
                                              ))
                                          .toList(),
                                      onChanged: (val) {
                                        if (val != null) {
                                          setModalState(() {
                                            selectedSpecialty = val;
                                            if (qualCtrl.text.trim().isEmpty) {
                                              qualCtrl.text = MedicalSpecialtyModel.getDefaultQualificationForSpecialty(val);
                                            }
                                          });
                                        }
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    flex: 2,
                                    child: TextField(
                                      controller: qualCtrl,
                                      decoration: InputDecoration(
                                        labelText: 'Qualification',
                                        hintText: 'MBBS, MD',
                                        prefixIcon: const Icon(Icons.school_outlined, size: 18),
                                        filled: true,
                                        fillColor: const Color(0xFFF8FAFC),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),

                              // Registration Number & Years of Experience & Fee
                              Row(
                                children: [
                                  Expanded(
                                    flex: 2,
                                    child: TextField(
                                      controller: licenseCtrl,
                                      onChanged: (_) => checkExisting(),
                                      decoration: InputDecoration(
                                        labelText: 'Registration / License No.',
                                        hintText: 'e.g. MED-8849',
                                        prefixIcon: const Icon(Icons.badge_outlined, size: 18),
                                        filled: true,
                                        fillColor: const Color(0xFFF8FAFC),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    flex: 1,
                                    child: TextField(
                                      controller: expCtrl,
                                      keyboardType: TextInputType.number,
                                      decoration: InputDecoration(
                                        labelText: 'Years Exp.',
                                        hintText: '5',
                                        prefixIcon: const Icon(Icons.work_history_outlined, size: 18),
                                        filled: true,
                                        fillColor: const Color(0xFFF8FAFC),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    flex: 1,
                                    child: TextField(
                                      controller: feeCtrl,
                                      decoration: InputDecoration(
                                        labelText: 'Fee',
                                        hintText: '₹500',
                                        prefixIcon: const Icon(Icons.payments_outlined, size: 18),
                                        filled: true,
                                        fillColor: const Color(0xFFF8FAFC),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),

                              // About / Bio
                              TextField(
                                controller: bioCtrl,
                                maxLines: 2,
                                decoration: InputDecoration(
                                  labelText: 'About / Professional Bio',
                                  hintText: 'Brief summary of clinical expertise and experience...',
                                  filled: true,
                                  fillColor: const Color(0xFFF8FAFC),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
                              const SizedBox(height: 10),

                              // City & Pincode
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: cityCtrl,
                                      decoration: InputDecoration(
                                        labelText: 'City',
                                        hintText: 'e.g. Hyderabad',
                                        prefixIcon: const Icon(Icons.location_city_outlined, size: 18),
                                        filled: true,
                                        fillColor: const Color(0xFFF8FAFC),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TextField(
                                      controller: pincodeCtrl,
                                      keyboardType: TextInputType.number,
                                      decoration: InputDecoration(
                                        labelText: 'Pincode',
                                        hintText: 'e.g. 500032',
                                        prefixIcon: const Icon(Icons.pin_drop_outlined, size: 18),
                                        filled: true,
                                        fillColor: const Color(0xFFF8FAFC),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),

                              // Available Days selection chips
                              const Text('Available Consultation Days:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: allDays.map((day) {
                                  final isSel = selectedDays.contains(day);
                                  return FilterChip(
                                    label: Text(day, style: TextStyle(fontSize: 11, color: isSel ? Colors.white : Colors.black87)),
                                    selected: isSel,
                                    selectedColor: const Color(0xFF0D9488),
                                    checkmarkColor: Colors.white,
                                    onSelected: (val) {
                                      setModalState(() {
                                        if (val) {
                                          selectedDays.add(day);
                                        } else {
                                          selectedDays.remove(day);
                                        }
                                      });
                                    },
                                  );
                                }).toList(),
                              ),
                              const SizedBox(height: 10),

                              // Available Time Slots selection chips
                              const Text('Available Consultation Slots:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: defaultSlotOptions.map((slot) {
                                  final isSel = selectedSlots.contains(slot);
                                  return FilterChip(
                                    label: Text(slot, style: TextStyle(fontSize: 11, color: isSel ? Colors.white : Colors.black87)),
                                    selected: isSel,
                                    selectedColor: const Color(0xFF0D9488),
                                    checkmarkColor: Colors.white,
                                    onSelected: (val) {
                                      setModalState(() {
                                        if (val) {
                                          selectedSlots.add(slot);
                                        } else {
                                          selectedSlots.remove(slot);
                                        }
                                      });
                                    },
                                  );
                                }).toList(),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Action Buttons
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(dialogCtx).pop(),
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 8),
                          if (detectedExistingDoctor != null) ...[
                            ElevatedButton.icon(
                              key: const Key('clinic_associate_existing_doctor_button'),
                              icon: const Icon(Icons.link_rounded, size: 16, color: Colors.white),
                              label: const Text('Associate Existing Doctor', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB)),
                              onPressed: () async {
                                await _problemService.associateDoctorWithClinic(
                                  doctorId: detectedExistingDoctor!.id,
                                  clinicName: _currentClinicName,
                                  specialty: selectedSpecialty,
                                  consultationFee: feeCtrl.text.trim().isNotEmpty ? feeCtrl.text.trim() : detectedExistingDoctor!.consultationFee,
                                  availableDays: selectedDays,
                                  availableSlots: selectedSlots,
                                );
                                Navigator.of(dialogCtx).pop();
                                setState(() {});
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('🎉 Doctor ${detectedExistingDoctor!.name} associated with $_currentClinicName without creating a duplicate account!'),
                                    backgroundColor: const Color(0xFF10B981),
                                  ),
                                );
                              },
                            ),
                          ] else ...[
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0D9488),
                                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              onPressed: () {
                                final name = nameCtrl.text.trim();
                                final phone = phoneCtrl.text.trim();
                                final license = licenseCtrl.text.trim();
                                final city = cityCtrl.text.trim();
                                final pincode = pincodeCtrl.text.trim();
                                if (name.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('⚠️ Full Name is mandatory.')),
                                  );
                                  return;
                                }
                                final cleanPhone = phone.replaceAll(RegExp(r'[^0-9]'), '');
                                if (cleanPhone.length < 10) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('⚠️ Enter a valid 10-digit Contact Number.')),
                                  );
                                  return;
                                }
                                final expYears = int.tryParse(expCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 5;
                                final qual = qualCtrl.text.trim().isNotEmpty
                                    ? qualCtrl.text.trim()
                                    : MedicalSpecialtyModel.getDefaultQualificationForSpecialty(selectedSpecialty);

                                final newDoc = _problemService.registerDoctor(
                                  name: name,
                                  phone: phone,
                                  email: emailCtrl.text.trim(),
                                  licenseNumber: license.isNotEmpty ? license : 'MED-LIC-REG',
                                  specialty: selectedSpecialty,
                                  qualification: qual,
                                  clinicName: _currentClinicName,
                                  experienceYears: expYears,
                                  consultationFee: feeCtrl.text.trim().isNotEmpty ? feeCtrl.text.trim() : '₹500',
                                  city: city,
                                  pincode: pincode,
                                );

                                // Attach slots and bio if provided
                                if (selectedSlots.isNotEmpty || bioCtrl.text.trim().isNotEmpty) {
                                  _problemService.updateDoctorProfessionalProfile(
                                    doctorId: newDoc.id,
                                    bio: bioCtrl.text.trim(),
                                    status: 'Available',
                                    verificationStatus: 'VERIFIED',
                                  );
                                }

                                Navigator.of(dialogCtx).pop();
                                setState(() {});
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('🎉 Doctor $name added and associated with $_currentClinicName!'),
                                    backgroundColor: const Color(0xFF10B981),
                                  ),
                                );
                              },
                              child: const Text('Save Doctor', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showEditClinicDoctorDialog(BuildContext context, DoctorModel doc) {
    final nameCtrl = TextEditingController(text: doc.name);
    final qualCtrl = TextEditingController(text: doc.qualification);
    final expCtrl = TextEditingController(text: '${doc.experienceYears}');
    final feeCtrl = TextEditingController(text: doc.consultationFee);
    final licenseCtrl = TextEditingController(text: doc.licenseNumber);
    final bioCtrl = TextEditingController(text: doc.bio);
    final cityCtrl = TextEditingController(text: doc.city);
    String selectedSpecialty = doc.specialty;
    String selectedStatus = doc.status;

    final activeSpecNames = <String>{
      doc.specialty,
      'General Medicine',
      ..._problemService.activeSpecialtyNames,
      'Dentistry',
    }.toList();

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              title: Text('Edit ${doc.name}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: InputDecoration(
                        labelText: 'Doctor Name',
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: activeSpecNames.contains(selectedSpecialty) ? selectedSpecialty : activeSpecNames.first,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: 'Medical Specialty',
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      items: activeSpecNames
                          .map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontSize: 12))))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) setModalState(() => selectedSpecialty = val);
                      },
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: qualCtrl,
                      decoration: InputDecoration(
                        labelText: 'Qualification',
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: expCtrl,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Years Exp.',
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: feeCtrl,
                            decoration: InputDecoration(
                              labelText: 'Consultation Fee',
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: licenseCtrl,
                      decoration: InputDecoration(
                        labelText: 'Medical License Number',
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: bioCtrl,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: 'About / Professional Bio',
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: selectedStatus == 'Inactive' ? 'Inactive' : 'Available',
                      decoration: InputDecoration(
                        labelText: 'Doctor Status',
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'Available', child: Text('Active / Available')),
                        DropdownMenuItem(value: 'Inactive', child: Text('Inactive / Suspended')),
                      ],
                      onChanged: (val) {
                        if (val != null) setModalState(() => selectedStatus = val);
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(dialogCtx).pop(), child: const Text('Cancel')),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0D9488)),
                  onPressed: () async {
                    final expYears = int.tryParse(expCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? doc.experienceYears;
                    await _problemService.updateDoctorProfessionalProfile(
                      doctorId: doc.id,
                      name: nameCtrl.text.trim().isNotEmpty ? nameCtrl.text.trim() : doc.name,
                      specialty: selectedSpecialty,
                      qualification: qualCtrl.text.trim().isNotEmpty ? qualCtrl.text.trim() : doc.qualification,
                      experienceYears: expYears,
                      consultationFee: feeCtrl.text.trim().isNotEmpty ? feeCtrl.text.trim() : doc.consultationFee,
                      licenseNumber: licenseCtrl.text.trim().isNotEmpty ? licenseCtrl.text.trim() : doc.licenseNumber,
                      bio: bioCtrl.text.trim().isNotEmpty ? bioCtrl.text.trim() : doc.bio,
                      status: selectedStatus,
                    );
                    Navigator.of(dialogCtx).pop();
                    setState(() {});
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('✅ Doctor ${doc.name} details updated!')),
                    );
                  },
                  child: const Text('Save Changes', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _confirmRemoveDoctorFromClinic(BuildContext context, DoctorModel doc) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.person_remove_rounded, color: Colors.redAccent, size: 22),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Remove Doctor from Clinic',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to remove Dr. ${doc.name} from $_currentClinicName?\n\nThis will disassociate the doctor from this clinic without deleting the doctor\'s global GS HEALTH account or patient consultation records.',
          style: const TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            key: const Key('confirm_remove_doctor_button'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              await _problemService.removeDoctorFromClinic(
                doctorId: doc.id,
                clinicName: _currentClinicName,
              );
              Navigator.of(dialogCtx).pop();
              setState(() {});
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Dr. ${doc.name} was removed from $_currentClinicName. Global account preserved.'),
                  backgroundColor: Colors.orange.shade800,
                ),
              );
            },
            child: const Text('Remove Doctor'),
          ),
        ],
      ),
    );
  }

  Widget _buildServicesTab(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Procedure Price List', style: theme.textTheme.titleMedium),
            IconButton(
              icon: const Icon(Icons.add_box_outlined, color: Color(0xFF0D9488)),
              onPressed: () => _showAddProcedureDialog(context),
            )
          ],
        ),
        const SizedBox(height: 16),
        ..._procedurePrices.entries.map((entry) => _buildServicePricingRow(entry.key, entry.value)),
      ],
    );
  }

  Widget _buildServicePricingRow(String service, String price) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        title: Text(service, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(price, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0D9488), fontSize: 16)),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 18, color: Color(0xFF0D9488)),
              onPressed: () => _showEditPriceDialog(service, price),
            ),
          ],
        ),
        subtitle: const Text('Duration: 45 Mins • Standard Practice Rate'),
      ),
    );
  }
}
