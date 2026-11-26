import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/services/api_service.dart';
import '../../../../core/services/patient_problem_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/clinic_directions_helper.dart';
import '../../../clinic/presentation/screens/clinic_dashboard.dart';
import '../../../clinic/presentation/widgets/clinic_add_doctors_dialog.dart';
import '../../../patient/presentation/screens/doctor_profile_screen.dart';

/// GS Health Admin Dashboard — Complete Clinic Management & Clinic-wise Doctor Filtering
///
/// Features:
/// - Prominent dynamic Clinic Search bar (Clinic Name, Clinic ID, City, State, Pincode, Clinic Address)
/// - Case-insensitive partial matching, clear search button, loading/empty/error states, pagination
/// - Professional responsive Clinic Cards/Table showing Clinic Name, Clinic ID, Address, City, State, Pincode,
///   Total Associated Doctors, and View Details
/// - Complete Clinic Details View with:
///   * Clinic Information + interactive OpenStreetMap location preview & Get Directions
///   * Associated Doctors list (Doctor Name, Doctor ID, Specialization, Mobile Number, Clinic Name, Status, View Profile)
///   * Separate Doctor Search bar (Name, Specialization, Doctor ID, Mobile Number) + Specialization filter
///     + optional Department filter (only when non-empty in existing DB records — never inventing fake categories)
///   * Clear Filters, total matching doctor count, Add Doctors & Remove Association support
class AdminClinicManagementPanel extends StatefulWidget {
  final PatientProblemService problemService;
  final VoidCallback? onRegisterNewClinic;

  const AdminClinicManagementPanel({
    super.key,
    required this.problemService,
    this.onRegisterNewClinic,
  });

  @override
  State<AdminClinicManagementPanel> createState() => _AdminClinicManagementPanelState();
}

class _AdminClinicManagementPanelState extends State<AdminClinicManagementPanel> {
  final TextEditingController _clinicSearchController = TextEditingController();
  Timer? _searchDebounce;

  bool _isLoading = false;
  String? _errorMessage;
  List<ClinicModel> _remoteClinics = const [];
  bool _hasLoadedRemote = false;
  int _currentPage = 1;
  int _totalPages = 1;
  int _totalItems = 0;
  static const int _pageSize = 20;

  @override
  void initState() {
    super.initState();
    _fetchClinics();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _clinicSearchController.dispose();
    super.dispose();
  }

  Future<void> _fetchClinics({bool showSpinner = true}) async {
    if (showSpinner && mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    final res = await ApiService().fetchClinicsWithSearch(
      search: _clinicSearchController.text.trim().isEmpty
          ? null
          : _clinicSearchController.text.trim(),
      page: _currentPage,
      pageSize: _pageSize,
    );

    if (!mounted) return;

    if (res['success'] == true && res['clinics'] is List) {
      final parsed = (res['clinics'] as List)
          .whereType<Map>()
          .map((e) => ClinicModel.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      final pag = res['pagination'] is Map ? Map<String, dynamic>.from(res['pagination'] as Map) : null;
      setState(() {
        _remoteClinics = parsed;
        _hasLoadedRemote = true;
        _totalItems = (pag?['totalItems'] as int?) ?? (res['totalCount'] as int?) ?? parsed.length;
        _totalPages = ((pag?['totalPages'] as int?) ?? 1).clamp(1, 9999);
        _currentPage = ((pag?['page'] as int?) ?? _currentPage).clamp(1, _totalPages);
        _isLoading = false;
        _errorMessage = null;
      });
    } else {
      setState(() {
        _isLoading = false;
        if (!_hasLoadedRemote && widget.problemService.allClinics.isEmpty) {
          _errorMessage = (res['message'] ?? 'Failed to load clinics.').toString();
        }
      });
    }
  }

  void _onClinicSearchChanged(String _) {
    setState(() {}); // Immediate dynamic UI filtering while typing
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() => _currentPage = 1);
      _fetchClinics(showSpinner: false);
    });
  }

  List<ClinicModel> get _displayedClinics {
    final source = _hasLoadedRemote ? _remoteClinics : widget.problemService.allClinics;
    final kw = _clinicSearchController.text.trim().toLowerCase();
    if (kw.isEmpty) return source;
    return source.where((c) {
      final hay = [
        c.clinicName,
        c.id,
        c.displayAddress,
        c.location,
        c.city,
        c.state,
        c.pincode,
      ].join(' ').toLowerCase();
      return hay.contains(kw);
    }).toList();
  }

  int _associatedDoctorCountFor(ClinicModel clinic) {
    final localDocs = widget.problemService.getDoctorsForClinic(clinic);
    if (clinic.associatedDoctorsCount > 0) {
      return clinic.associatedDoctorsCount >= localDocs.length
          ? clinic.associatedDoctorsCount
          : localDocs.length;
    }
    return localDocs.length;
  }

  void _openClinicDetailsDialog(ClinicModel clinic) {
    showDialog<void>(
      context: context,
      builder: (_) => _AdminClinicDetailsDialog(
        clinic: clinic,
        problemService: widget.problemService,
        onClinicUpdated: () => _fetchClinics(showSpinner: false),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final clinics = _displayedClinics;
    final query = _clinicSearchController.text.trim();

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 720;

        return RefreshIndicator(
          onRefresh: () => _fetchClinics(showSpinner: false),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.all(isMobile ? 12 : 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            color: AppTheme.gsNavy.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.local_hospital_rounded, color: AppTheme.gsNavy, size: 22),
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Flexible(
                                    child: Text(
                                      'Clinic Management',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                        color: AppTheme.textDark,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    key: const Key('admin_clinics_count_badge'),
                                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2.5),
                                    decoration: BoxDecoration(
                                      color: AppTheme.gsNavy.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      '${clinics.length} Clinics',
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.gsNavy,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const Text(
                                'Search clinics, inspect map locations, and manage clinic-wise associated doctors',
                                style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          icon: const Icon(Icons.dashboard_customize_rounded, size: 15),
                          label: const Text('Open Clinic Dashboard'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.gsNavy,
                            side: const BorderSide(color: AppTheme.gsNavy),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ClinicDashboardScreen(
                                  clinicName: clinics.isNotEmpty ? clinics.first.clinicName : null,
                                ),
                              ),
                            );
                          },
                        ),
                        if (widget.onRegisterNewClinic != null)
                          ElevatedButton.icon(
                            icon: const Icon(Icons.add_location_alt_rounded, size: 16),
                            label: const Text('Register Clinic'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.gsNavy,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: widget.onRegisterNewClinic,
                          ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Prominent Clinic Search Bar
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const Key('admin_clinic_search_field'),
                          controller: _clinicSearchController,
                          onChanged: _onClinicSearchChanged,
                          decoration: InputDecoration(
                            hintText: 'Search clinics by Clinic Name, Clinic ID, City, State, Pincode, or Address...',
                            hintStyle: const TextStyle(fontSize: 13, color: AppTheme.textMuted),
                            prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.gsNavy),
                            suffixIcon: query.isNotEmpty
                                ? IconButton(
                                    key: const Key('admin_clinic_search_clear_btn'),
                                    tooltip: 'Clear search',
                                    icon: const Icon(Icons.close_rounded, size: 18),
                                    onPressed: () {
                                      _clinicSearchController.clear();
                                      setState(() => _currentPage = 1);
                                      _fetchClinics();
                                    },
                                  )
                                : null,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Refresh Clinics',
                        onPressed: _isLoading ? null : () => _fetchClinics(),
                        icon: _isLoading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.gsNavy),
                              )
                            : const Icon(Icons.refresh_rounded, color: AppTheme.gsNavy),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                if (_errorMessage != null && clinics.isEmpty)
                  _buildErrorCard()
                else if (_isLoading && clinics.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(child: CircularProgressIndicator(color: AppTheme.gsNavy)),
                  )
                else if (clinics.isEmpty)
                  _buildEmptyClinicsState(query)
                else ...[
                  if (isMobile)
                    Column(
                      children: clinics.map(_buildClinicCard).toList(),
                    )
                  else
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          key: const Key('admin_clinics_data_table'),
                          headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
                          horizontalMargin: 14,
                          columnSpacing: 14,
                          showCheckboxColumn: false,
                          columns: const [
                            DataColumn(label: Text('Clinic Name', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5))),
                            DataColumn(label: Text('Clinic ID', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5))),
                            DataColumn(label: Text('Clinic Address', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5))),
                            DataColumn(label: Text('City', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5))),
                            DataColumn(label: Text('State', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5))),
                            DataColumn(label: Text('Pincode', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5))),
                            DataColumn(numeric: true, label: Text('Doctors', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5))),
                            DataColumn(label: Text('Action', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5))),
                          ],
                          rows: clinics.map((c) {
                            final shortId = c.id.length > 10 ? '${c.id.substring(0, 10)}…' : c.id;
                            final docCount = _associatedDoctorCountFor(c);
                            return DataRow(
                              onSelectChanged: (_) => _openClinicDetailsDialog(c),
                              cells: [
                                DataCell(
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(maxWidth: 165),
                                    child: Text(
                                      c.clinicName.isNotEmpty ? c.clinicName : 'Clinic',
                                      style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.gsNavy, fontSize: 12.5),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                DataCell(Text(shortId, style: const TextStyle(fontSize: 12, color: AppTheme.textMuted))),
                                DataCell(
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(maxWidth: 175),
                                    child: Text(
                                      c.displayAddress.isNotEmpty ? c.displayAddress : '—',
                                      style: const TextStyle(fontSize: 12.5),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                DataCell(Text(c.city.isNotEmpty ? c.city : '—', style: const TextStyle(fontSize: 12.5))),
                                DataCell(Text(c.state.isNotEmpty ? c.state : '—', style: const TextStyle(fontSize: 12.5))),
                                DataCell(Text(c.pincode.isNotEmpty ? c.pincode : '—', style: const TextStyle(fontSize: 12.5))),
                                DataCell(
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: AppTheme.gsNavy.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      '$docCount',
                                      style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.gsNavy),
                                    ),
                                  ),
                                ),
                                DataCell(
                                  ElevatedButton(
                                    key: Key('admin_clinic_view_details_${c.id}'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.gsNavy,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    onPressed: () => _openClinicDetailsDialog(c),
                                    child: const Text('View Details', style: TextStyle(fontSize: 12)),
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  if (_totalPages > 1) ...[
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            'Page $_currentPage of $_totalPages ($_totalItems clinics)',
                            style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            OutlinedButton(
                              onPressed: _currentPage > 1
                                  ? () {
                                      setState(() => _currentPage -= 1);
                                      _fetchClinics();
                                    }
                                  : null,
                              child: const Text('Previous'),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton(
                              onPressed: _currentPage < _totalPages
                                  ? () {
                                      setState(() => _currentPage += 1);
                                      _fetchClinics();
                                    }
                                  : null,
                              child: const Text('Next'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildClinicCard(ClinicModel c) {
    final docCount = _associatedDoctorCountFor(c);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  c.clinicName.isNotEmpty ? c.clinicName : 'Clinic',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppTheme.textDark),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.gsNavy.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$docCount Doctors',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.gsNavy),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'ID: ${c.id}',
            style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (c.displayAddress.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              c.displayAddress,
              style: const TextStyle(fontSize: 12.5, color: AppTheme.textMedium),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (c.cityStatePincode.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              c.cityStatePincode,
              style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton(
              key: Key('admin_clinic_view_details_${c.id}'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.gsNavy,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => _openClinicDetailsDialog(c),
              child: const Text('View Details'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyClinicsState(String query) {
    return Container(
      key: const Key('admin_clinics_empty_state'),
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          const Icon(Icons.local_hospital_outlined, size: 42, color: AppTheme.textMuted),
          const SizedBox(height: 10),
          Text(
            query.isNotEmpty ? 'No clinics match "$query"' : 'No registered clinics found',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            query.isNotEmpty
                ? 'Try searching by Clinic Name, Clinic ID, City, State, Pincode, or Address.'
                : 'Clinics registered in GS Health will appear here automatically.',
            style: const TextStyle(fontSize: 12.5, color: AppTheme.textMuted),
            textAlign: TextAlign.center,
          ),
          if (query.isNotEmpty) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () {
                _clinicSearchController.clear();
                setState(() => _currentPage = 1);
                _fetchClinics();
              },
              icon: const Icon(Icons.clear_rounded, size: 16),
              label: const Text('Clear Search'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildErrorCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.gsRed.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppTheme.gsRed, size: 36),
          const SizedBox(height: 8),
          Text(_errorMessage ?? 'Unable to load clinics.', textAlign: TextAlign.center),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: () => _fetchClinics(),
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

/// Complete Clinic Details Dialog with Map Location + Associated Doctors Search & Filters
class _AdminClinicDetailsDialog extends StatefulWidget {
  final ClinicModel clinic;
  final PatientProblemService problemService;
  final VoidCallback? onClinicUpdated;

  const _AdminClinicDetailsDialog({
    required this.clinic,
    required this.problemService,
    this.onClinicUpdated,
  });

  @override
  State<_AdminClinicDetailsDialog> createState() => _AdminClinicDetailsDialogState();
}

class _AdminClinicDetailsDialogState extends State<_AdminClinicDetailsDialog> {
  final TextEditingController _doctorSearchController = TextEditingController();
  Timer? _debounce;
  String _selectedSpecialty = 'All';
  String _selectedDepartment = 'All';
  bool _isLoading = true;
  String? _errorMessage;
  List<DoctorModel> _allAssociatedDoctors = const [];
  List<DoctorModel> _filteredRemoteDoctors = const [];
  bool _hasRemoteFiltered = false;

  @override
  void initState() {
    super.initState();
    _allAssociatedDoctors = widget.problemService.getDoctorsForClinic(widget.clinic);
    _fetchDoctors();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _doctorSearchController.dispose();
    super.dispose();
  }

  Future<void> _fetchDoctors({bool isBaseFetch = true}) async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    final res = await ApiService().fetchClinicDoctorsFiltered(
      clinicId: widget.clinic.id,
      search: _doctorSearchController.text.trim().isEmpty
          ? null
          : _doctorSearchController.text.trim(),
      specialty: _selectedSpecialty == 'All' ? null : _selectedSpecialty,
      department: _selectedDepartment == 'All' ? null : _selectedDepartment,
    );

    if (!mounted) return;

    if (res['success'] == true) {
      final rawList = (res['doctors'] ?? res['dentists']) as List? ?? const [];
      final parsed = rawList
          .whereType<Map>()
          .map((e) => DoctorModel.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      setState(() {
        if (isBaseFetch && !_hasActiveDoctorFilters) {
          _allAssociatedDoctors = parsed;
        }
        _filteredRemoteDoctors = parsed;
        _hasRemoteFiltered = true;
        _isLoading = false;
      });
    } else {
      setState(() {
        _isLoading = false;
        if (_allAssociatedDoctors.isEmpty) {
          _errorMessage = (res['message'] ?? 'Unable to load associated doctors.').toString();
        }
      });
    }
  }

  bool get _hasActiveDoctorFilters =>
      _doctorSearchController.text.trim().isNotEmpty ||
      _selectedSpecialty != 'All' ||
      _selectedDepartment != 'All';

  void _onDoctorSearchChanged(String _) {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), () {
      if (mounted) _fetchDoctors(isBaseFetch: false);
    });
  }

  void _clearDoctorFilters() {
    _debounce?.cancel();
    _doctorSearchController.clear();
    setState(() {
      _selectedSpecialty = 'All';
      _selectedDepartment = 'All';
    });
    _fetchDoctors(isBaseFetch: true);
  }

  List<String> get _specialtyOptions {
    final set = <String>{'All'};
    for (final d in _allAssociatedDoctors) {
      final sp = d.specialty.trim();
      if (sp.isNotEmpty) set.add(sp);
    }
    return set.toList();
  }

  List<String> get _departmentOptions {
    final set = <String>{'All'};
    for (final d in _allAssociatedDoctors) {
      final dept = d.department.trim();
      if (dept.isNotEmpty) set.add(dept);
    }
    return set.toList();
  }

  List<DoctorModel> get _visibleDoctors {
    final source = _hasRemoteFiltered ? _filteredRemoteDoctors : _allAssociatedDoctors;
    final kw = _doctorSearchController.text.trim().toLowerCase();
    final kwDigits = kw.replaceAll(RegExp(r'\D'), '');

    return source.where((d) {
      if (_selectedSpecialty != 'All' &&
          d.specialty.trim().toLowerCase() != _selectedSpecialty.toLowerCase()) {
        return false;
      }
      if (_selectedDepartment != 'All' &&
          d.department.trim().toLowerCase() != _selectedDepartment.toLowerCase()) {
        return false;
      }
      if (kw.isEmpty) return true;
      return d.name.toLowerCase().contains(kw) ||
          d.specialty.toLowerCase().contains(kw) ||
          d.department.toLowerCase().contains(kw) ||
          d.id.toLowerCase().contains(kw) ||
          d.userId.toLowerCase().contains(kw) ||
          d.phone.toLowerCase().contains(kw) ||
          (kwDigits.length >= 3 && d.phone.replaceAll(RegExp(r'\D'), '').contains(kwDigits));
    }).toList();
  }

  Future<void> _removeDoctorAssociation(DoctorModel doc) async {
    final res = await ApiService().removeDoctorAssociationFromClinic(
      clinicId: widget.clinic.id,
      doctorId: doc.id,
    );
    if (!mounted) return;
    if (res['success'] == true) {
      await _fetchDoctors(isBaseFetch: true);
      widget.onClinicUpdated?.call();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${doc.name} removed from ${widget.clinic.clinicName}. Doctor account preserved.'),
          backgroundColor: AppTheme.gsNavy,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final clinic = widget.clinic;
    final visibleDoctors = _visibleDoctors;
    final specialties = _specialtyOptions;
    final departments = _departmentOptions;
    final hasDepartments = departments.length > 1;
    final hasCoords = ClinicDirectionsHelper.hasValidCoordinates(clinic.latitude, clinic.longitude);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 760),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.gsNavy.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.local_hospital_rounded, color: AppTheme.gsNavy, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        clinic.clinicName.isNotEmpty ? clinic.clinicName : 'Clinic Details',
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppTheme.textDark),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Clinic ID: ${clinic.id}',
                        style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const Divider(height: 20),

            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Section 1: Clinic Information & Map Location
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Clinic Information',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppTheme.gsNavy),
                          ),
                          const SizedBox(height: 8),
                          _infoRow('Clinic Name', clinic.clinicName),
                          _infoRow('Clinic Address', clinic.displayAddress.isNotEmpty ? clinic.displayAddress : 'Not provided'),
                          _infoRow('City', clinic.city.isNotEmpty ? clinic.city : '—'),
                          _infoRow('State', clinic.state.isNotEmpty ? clinic.state : '—'),
                          _infoRow('Pincode', clinic.pincode.isNotEmpty ? clinic.pincode : '—'),
                          if (hasCoords) ...[
                            const SizedBox(height: 10),
                            OsmLocationPreviewCard(
                              latitude: clinic.latitude!,
                              longitude: clinic.longitude!,
                              title: clinic.clinicName,
                              subtitle: clinic.displayAddress,
                              mapHeight: 150,
                              onOpenDirections: () => ClinicDirectionsHelper.launchDirections(
                                context: context,
                                latitude: clinic.latitude,
                                longitude: clinic.longitude,
                                clinicAddress: clinic.displayAddress,
                                clinicName: clinic.clinicName,
                                city: clinic.city,
                                state: clinic.state,
                                pincode: clinic.pincode,
                              ),
                            ),
                          ] else
                            const Padding(
                              padding: EdgeInsets.only(top: 6),
                              child: Row(
                                children: [
                                  Icon(Icons.location_off_outlined, size: 16, color: AppTheme.textMuted),
                                  SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'Map coordinates not pinned yet.',
                                      style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Section 2: Associated Doctors + Search & Filters
                    Row(
                      children: [
                        const Icon(Icons.medical_services_rounded, size: 18, color: AppTheme.gsNavy),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Row(
                            children: [
                              const Flexible(
                                child: Text(
                                  'Associated Doctors',
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppTheme.textDark),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                key: const Key('admin_clinic_doctors_count_badge'),
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppTheme.gsNavy.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '${visibleDoctors.length} matching',
                                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppTheme.gsNavy),
                                ),
                              ),
                            ],
                          ),
                        ),
                        ElevatedButton.icon(
                          key: const Key('admin_clinic_add_doctors_btn'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.gsNavy,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: () async {
                            final assocIds = _allAssociatedDoctors.map((d) => d.id).toSet();
                            await ClinicAddDoctorsDialog.show(
                              context,
                              clinicId: clinic.id,
                              clinicName: clinic.clinicName,
                              allRegisteredDoctors: widget.problemService.allDoctors,
                              alreadyAssociatedDoctorIds: assocIds,
                              onDoctorsAssociated: () {
                                _fetchDoctors(isBaseFetch: true);
                                widget.onClinicUpdated?.call();
                              },
                            );
                          },
                          icon: const Icon(Icons.person_add_alt_1_rounded, size: 15),
                          label: const Text('Add Doctors', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Doctor Search & Filter Toolbar
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                          width: 300,
                          child: TextField(
                            key: const Key('admin_clinic_doctor_search_field'),
                            controller: _doctorSearchController,
                            onChanged: _onDoctorSearchChanged,
                            decoration: InputDecoration(
                              hintText: 'Search by Doctor Name, Specialization, ID, Mobile...',
                              hintStyle: const TextStyle(fontSize: 12.5),
                              prefixIcon: const Icon(Icons.search_rounded, size: 18),
                              suffixIcon: _doctorSearchController.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.close_rounded, size: 16),
                                      onPressed: () {
                                        _doctorSearchController.clear();
                                        _fetchDoctors(isBaseFetch: false);
                                      },
                                    )
                                  : null,
                              isDense: true,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 190,
                          child: DropdownButtonFormField<String>(
                            key: const Key('admin_clinic_doctor_specialty_filter'),
                            initialValue: specialties.contains(_selectedSpecialty) ? _selectedSpecialty : 'All',
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: 'Specialization',
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            items: specialties
                                .map((s) => DropdownMenuItem(value: s, child: Text(s, overflow: TextOverflow.ellipsis)))
                                .toList(),
                            onChanged: (v) {
                              if (v == null) return;
                              setState(() => _selectedSpecialty = v);
                              _fetchDoctors(isBaseFetch: false);
                            },
                          ),
                        ),
                        if (hasDepartments)
                          SizedBox(
                            width: 180,
                            child: DropdownButtonFormField<String>(
                              key: const Key('admin_clinic_doctor_department_filter'),
                              initialValue: departments.contains(_selectedDepartment) ? _selectedDepartment : 'All',
                              isExpanded: true,
                              decoration: InputDecoration(
                                labelText: 'Department',
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              items: departments
                                  .map((d) => DropdownMenuItem(value: d, child: Text(d, overflow: TextOverflow.ellipsis)))
                                  .toList(),
                              onChanged: (v) {
                                if (v == null) return;
                                setState(() => _selectedDepartment = v);
                                _fetchDoctors(isBaseFetch: false);
                              },
                            ),
                          ),
                        if (_hasActiveDoctorFilters)
                          TextButton.icon(
                            key: const Key('admin_clinic_doctor_clear_filters_btn'),
                            onPressed: _clearDoctorFilters,
                            icon: const Icon(Icons.filter_alt_off_rounded, size: 16),
                            label: const Text('Clear Filters'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    if (_isLoading && visibleDoctors.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 28),
                        child: Center(child: CircularProgressIndicator(color: AppTheme.gsNavy)),
                      )
                    else if (_errorMessage != null && visibleDoctors.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(_errorMessage!, style: const TextStyle(color: AppTheme.gsRed)),
                      )
                    else if (visibleDoctors.isEmpty)
                      Container(
                        key: const Key('admin_clinic_doctors_empty_state'),
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          children: [
                            const Icon(Icons.person_off_outlined, size: 34, color: AppTheme.textMuted),
                            const SizedBox(height: 6),
                            const Text(
                              'No matching associated doctors',
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _hasActiveDoctorFilters
                                  ? 'Clear filters to view all doctors associated with ${clinic.clinicName}.'
                                  : 'No doctors are currently associated with ${clinic.clinicName}.',
                              style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    else
                      Column(
                        children: visibleDoctors.map((doc) {
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CircleAvatar(
                                  radius: 20,
                                  backgroundColor: AppTheme.gsNavy.withValues(alpha: 0.1),
                                  child: const Icon(Icons.person_rounded, color: AppTheme.gsNavy, size: 20),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              doc.name,
                                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF059669).withValues(alpha: 0.12),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              doc.status.isNotEmpty ? doc.status : 'Available',
                                              style: const TextStyle(
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.w700,
                                                color: Color(0xFF059669),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Specialization: ${doc.specialty}${doc.department.isNotEmpty ? ' • Dept: ${doc.department}' : ''}',
                                        style: const TextStyle(fontSize: 12, color: AppTheme.textMedium),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        'Doctor ID: ${doc.id} • Mobile: ${doc.phone.isNotEmpty ? doc.phone : 'N/A'} • Clinic: ${clinic.clinicName}',
                                        style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 6),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 6,
                                        children: [
                                          OutlinedButton.icon(
                                            onPressed: () {
                                              Navigator.of(context).push(
                                                MaterialPageRoute(
                                                  builder: (_) => DoctorProfileScreen(
                                                    doctor: doc,
                                                    isAdminView: true,
                                                  ),
                                                ),
                                              );
                                            },
                                            icon: const Icon(Icons.visibility_outlined, size: 15),
                                            label: const Text('View Profile', style: TextStyle(fontSize: 12)),
                                          ),
                                          TextButton.icon(
                                            onPressed: () => _removeDoctorAssociation(doc),
                                            icon: const Icon(Icons.link_off_rounded, size: 15, color: AppTheme.gsRed),
                                            label: const Text(
                                              'Remove Association',
                                              style: TextStyle(fontSize: 12, color: AppTheme.gsRed),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 115,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textMuted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.textDark),
            ),
          ),
        ],
      ),
    );
  }
}
