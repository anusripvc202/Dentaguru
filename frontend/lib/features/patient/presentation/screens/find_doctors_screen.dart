import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/models/medical_specialty_model.dart';
import '../../../../core/services/patient_problem_service.dart';
import 'doctor_profile_screen.dart';

class FindDoctorsScreen extends StatefulWidget {
  final int initialTabFilter; // 0 = All Doctors, 1 = My Favourite Doctors
  final String initialSpecialty;
  final bool isSpecialtyPage;
  final bool isAdminView;
  final void Function(BuildContext context, DoctorModel doctor)? onAdminEditDoctor;
  final void Function(BuildContext context, DoctorModel doctor)? onAdminDeleteDoctor;
  final void Function(BuildContext context, DoctorModel doctor)? onAdminAssignDoctor;
  final VoidCallback? onAdminCreateDoctor;

  const FindDoctorsScreen({
    super.key,
    this.initialTabFilter = 0,
    this.initialSpecialty = 'All',
    this.isSpecialtyPage = false,
    this.isAdminView = false,
    this.onAdminEditDoctor,
    this.onAdminDeleteDoctor,
    this.onAdminAssignDoctor,
    this.onAdminCreateDoctor,
  });

  static String formatSpecialtyTitle(String specialty, {bool isAdminView = false, bool isSpecialtyPage = false}) {
    final clean = specialty.trim();
    if (clean.isEmpty || clean.toLowerCase() == 'all' || clean.toLowerCase() == 'all specialties') {
      return isAdminView ? 'All Doctors' : 'Find Doctors';
    }
    if (clean.toLowerCase() == 'dentistry') {
      return 'Dental Doctors';
    }
    if (clean.toLowerCase().endsWith('doctors')) {
      return clean;
    }
    return '$clean Doctors';
  }

  @override
  State<FindDoctorsScreen> createState() => _FindDoctorsScreenState();
}

class _FindDoctorsScreenState extends State<FindDoctorsScreen> {
  final PatientProblemService _patientService = PatientProblemService();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _cityFilterController = TextEditingController();
  final TextEditingController _pincodeFilterController = TextEditingController();

  late int _doctorTabFilter;
  String _searchQuery = '';
  String _cityFilter = '';
  String _pincodeFilter = '';
  late String _selectedSpecialty;
  bool _isSyncing = false;

  static const LinearGradient _primaryGradient = LinearGradient(
    colors: [AppTheme.primaryBlue, AppTheme.primaryBlueDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  List<String> get _availableSpecialtyOptions {
    final specs = <String>['All'];
    for (final s in _patientService.activeSpecialties) {
      if (!specs.any((item) => item.toLowerCase() == s.name.toLowerCase())) {
        specs.add(s.name);
      }
    }
    for (final d in _patientService.allDoctors) {
      final sp = d.specialty.trim();
      if (sp.isNotEmpty && !specs.any((item) => item.toLowerCase() == sp.toLowerCase())) {
        specs.add(sp);
      }
    }
    return specs;
  }

  @override
  void initState() {
    super.initState();
    _doctorTabFilter = widget.initialTabFilter;
    _selectedSpecialty = widget.initialSpecialty.trim().isNotEmpty ? widget.initialSpecialty.trim() : 'All';
    _patientService.addListener(_onServiceUpdated);
    _refreshDoctorsIfNeeded();
  }

  @override
  void dispose() {
    _patientService.removeListener(_onServiceUpdated);
    _searchController.dispose();
    _cityFilterController.dispose();
    _pincodeFilterController.dispose();
    super.dispose();
  }

  void _onServiceUpdated() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _refreshDoctorsIfNeeded() async {
    if (_patientService.allDoctors.isEmpty) {
      setState(() => _isSyncing = true);
    }
    try {
      await _patientService.syncDoctorsFromApi();
      await _patientService.syncMyDoctorsFromApi();
    } catch (_) {}
    if (mounted) {
      setState(() => _isSyncing = false);
    }
  }

  void _openDoctorDetails(DoctorModel doc) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (profileContext) => DoctorProfileScreen(
          doctor: doc,
          isAdminView: widget.isAdminView,
          onAdminEditDoctor: widget.onAdminEditDoctor != null
              ? () => widget.onAdminEditDoctor!(profileContext, doc)
              : null,
          onAdminDeleteDoctor: widget.onAdminDeleteDoctor != null
              ? () => widget.onAdminDeleteDoctor!(profileContext, doc)
              : null,
          onAdminAssignDoctor: widget.onAdminAssignDoctor != null
              ? () => widget.onAdminAssignDoctor!(profileContext, doc)
              : null,
        ),
      ),
    );
  }

  void _handleSelectSpecialtyFromDropdown(String specialty) {
    final clean = specialty.trim();
    if (clean.isEmpty || clean.toLowerCase() == 'all' || clean.toLowerCase() == 'all specialties') {
      if (widget.isSpecialtyPage && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
        return;
      }
      setState(() => _selectedSpecialty = 'All');
      return;
    }

    if (widget.isSpecialtyPage && _selectedSpecialty.toLowerCase() == clean.toLowerCase()) {
      return;
    }

    // Navigate to a separate page for the selected specialty
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FindDoctorsScreen(
          initialSpecialty: clean,
          isSpecialtyPage: true,
          isAdminView: widget.isAdminView,
          onAdminEditDoctor: widget.onAdminEditDoctor,
          onAdminDeleteDoctor: widget.onAdminDeleteDoctor,
          onAdminAssignDoctor: widget.onAdminAssignDoctor,
          onAdminCreateDoctor: widget.onAdminCreateDoctor,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allDocs = _patientService.allDoctors;
    final myDocs = _patientService.myDoctors;
    final baseDocs = (!widget.isAdminView && _doctorTabFilter == 1) ? myDocs : allDocs;

    final filteredDocs = baseDocs.where((d) {
      final isInactiveStatus = d.status.trim().toLowerCase() == 'suspended' ||
          d.verificationStatus.trim().toUpperCase() == 'SUSPENDED';
      if (!widget.isAdminView && isInactiveStatus) {
        return false;
      }

      final q = _searchQuery.trim().toLowerCase();
      final matchesSearch = q.isEmpty ||
          d.name.toLowerCase().contains(q) ||
          d.specialty.toLowerCase().contains(q) ||
          d.clinicName.toLowerCase().contains(q) ||
          d.city.toLowerCase().contains(q) ||
          d.pincode.toLowerCase().contains(q) ||
          d.qualification.toLowerCase().contains(q);
      final matchesSpec = MedicalSpecialtyModel.matchesSpecialtyFilter(
        d.specialty,
        _selectedSpecialty,
        specialties: _patientService.specialties,
      );
      final cityQ = _cityFilter.trim().toLowerCase();
      final matchesCity = cityQ.isEmpty ||
          d.city.toLowerCase().contains(cityQ) ||
          d.state.toLowerCase().contains(cityQ) ||
          d.clinicAddress.toLowerCase().contains(cityQ) ||
          d.clinicName.toLowerCase().contains(cityQ);
      final pinQ = _pincodeFilter.trim().toLowerCase();
      final matchesPincode = pinQ.isEmpty ||
          d.pincode.toLowerCase().contains(pinQ) ||
          d.clinicAddress.toLowerCase().contains(pinQ);
      return matchesSearch && matchesSpec && matchesCity && matchesPincode;
    }).toList();

    final isSpecificSpecialty =
        _selectedSpecialty.trim().isNotEmpty && _selectedSpecialty.trim().toLowerCase() != 'all';
    final pageTitle = (widget.isSpecialtyPage && isSpecificSpecialty)
        ? FindDoctorsScreen.formatSpecialtyTitle(_selectedSpecialty, isAdminView: widget.isAdminView, isSpecialtyPage: widget.isSpecialtyPage)
        : (widget.isAdminView ? 'Doctors Directory' : 'Find Doctors');

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        leadingWidth: 110,
        leading: InkWell(
          key: const Key('back_to_patient_dashboard_button'),
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.of(context).pop(),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: AppTheme.textDark),
                SizedBox(width: 4),
                Flexible(
                  child: Text(
                    'Back',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textDark,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
        title: Text(
          pageTitle,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppTheme.textDark,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (widget.isAdminView && widget.onAdminCreateDoctor != null)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: TextButton.icon(
                onPressed: widget.onAdminCreateDoctor,
                icon: const Icon(Icons.person_add_rounded, size: 16, color: AppTheme.primaryBlue),
                label: const Text(
                  '+ Create Doctor',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppTheme.primaryBlue),
                ),
              ),
            ),
          IconButton(
            tooltip: 'Refresh Doctors',
            onPressed: _refreshDoctorsIfNeeded,
            icon: const Icon(Icons.refresh_rounded, color: AppTheme.primaryBlue),
          ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Colors.grey.shade200),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 36),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeaderBanner(filteredDocs.length, isSpecificSpecialty),
                  const SizedBox(height: 16),
                  if (!widget.isAdminView && !widget.isSpecialtyPage) ...[
                    _buildTabSelector(allDocs.length, myDocs.length),
                    const SizedBox(height: 14),
                  ],
                  _buildSearchBar(),
                  const SizedBox(height: 10),
                  _buildLocationFiltersRow(),
                  const SizedBox(height: 12),
                  _buildAllSpecialtyDropdownAndFilterRow(),
                  const SizedBox(height: 16),
                  if (_isSyncing && allDocs.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (filteredDocs.isEmpty)
                    _buildEmptyState()
                  else
                    Column(
                      children: filteredDocs
                          .map(
                            (doc) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _buildDoctorRow(doc),
                            ),
                          )
                          .toList(),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderBanner(int count, bool isSpecificSpecialty) {
    final bannerTitle = isSpecificSpecialty
        ? FindDoctorsScreen.formatSpecialtyTitle(_selectedSpecialty, isAdminView: widget.isAdminView, isSpecialtyPage: true)
        : 'Discover Healthcare Specialists';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: _primaryGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryBlue.withValues(alpha: 0.18),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.medical_services_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  bannerTitle,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  isSpecificSpecialty
                      ? '$count verified ${_selectedSpecialty.trim()} specialist${count == 1 ? "" : "s"} • Select a doctor to view complete profile & availability'
                      : (count > 0
                          ? '$count verified doctors across ${_patientService.activeSpecialties.length} medical specialties • Tap a doctor to view profile'
                          : 'Browse verified medical & dental specialists and book appointments online'),
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabSelector(int allCount, int myCount) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _doctorTabFilter = 0),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                decoration: BoxDecoration(
                  color: _doctorTabFilter == 0 ? AppTheme.primaryBlue : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.people_alt_rounded,
                      size: 16,
                      color: _doctorTabFilter == 0 ? Colors.white : AppTheme.textMedium,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'All Doctors ($allCount)',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: _doctorTabFilter == 0 ? Colors.white : AppTheme.textMedium,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _doctorTabFilter = 1),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                decoration: BoxDecoration(
                  color: _doctorTabFilter == 1 ? AppTheme.primaryBlue : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.favorite_rounded,
                      size: 16,
                      color: _doctorTabFilter == 1 ? Colors.white : AppTheme.textMedium,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'My Favourite Doctors ($myCount)',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: _doctorTabFilter == 1 ? Colors.white : AppTheme.textMedium,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: TextField(
        key: const ValueKey('find_doctors_search_input'),
        controller: _searchController,
        onChanged: (v) => setState(() => _searchQuery = v),
        decoration: InputDecoration(
          hintText: 'Search by doctor name, specialty, city, or pincode...',
          hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
          prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.primaryBlue, size: 20),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }

  Widget _buildLocationFiltersRow() {
    return Row(
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: TextField(
              key: const Key('filter_city_input'),
              controller: _cityFilterController,
              onChanged: (v) => setState(() => _cityFilter = v),
              decoration: InputDecoration(
                hintText: 'Filter by City...',
                hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 12.5),
                prefixIcon: const Icon(Icons.location_city_rounded, color: AppTheme.primaryBlue, size: 18),
                suffixIcon: _cityFilter.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 16),
                        onPressed: () {
                          _cityFilterController.clear();
                          setState(() => _cityFilter = '');
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: TextField(
              key: const Key('filter_pincode_input'),
              controller: _pincodeFilterController,
              onChanged: (v) => setState(() => _pincodeFilter = v),
              decoration: InputDecoration(
                hintText: 'Filter by Pincode...',
                hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 12.5),
                prefixIcon: const Icon(Icons.pin_drop_outlined, color: AppTheme.primaryBlue, size: 18),
                suffixIcon: _pincodeFilter.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 16),
                        onPressed: () {
                          _pincodeFilterController.clear();
                          setState(() => _pincodeFilter = '');
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAllSpecialtyDropdownAndFilterRow() {
    final options = _availableSpecialtyOptions;
    final isAllSelected = _selectedSpecialty.trim().isEmpty || _selectedSpecialty.trim().toLowerCase() == 'all';

    return Row(
      children: [
        // ALL Button — Medical Specialty Dropdown
        PopupMenuButton<String>(
          key: const Key('all_specialties_dropdown_button'),
          tooltip: 'Select Medical Specialty',
          position: PopupMenuPosition.under,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          color: Colors.white,
          onSelected: _handleSelectSpecialtyFromDropdown,
          itemBuilder: (context) {
            return options.map((spec) {
              final isItemAll = spec.toLowerCase() == 'all';
              final displayLabel = isItemAll ? 'All Specialties' : spec;
              final isCurrent = _selectedSpecialty.toLowerCase() == spec.toLowerCase();
              return PopupMenuItem<String>(
                key: Key('specialty_dropdown_item_$spec'),
                value: spec,
                child: Row(
                  children: [
                    Icon(
                      isCurrent ? Icons.check_circle_rounded : Icons.medical_services_outlined,
                      size: 16,
                      color: isCurrent ? AppTheme.primaryBlue : AppTheme.textMedium,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        displayLabel,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w600,
                          color: isCurrent ? AppTheme.primaryBlue : AppTheme.textDark,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
            }).toList();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_rounded, size: 15, color: Colors.white),
                const SizedBox(width: 6),
                Text(
                  isAllSelected ? 'All' : _selectedSpecialty,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.keyboard_arrow_down_rounded, size: 17, color: Colors.white),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        // Quick Horizontal Specialty Chips
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: options.where((s) => s.toLowerCase() != 'all').map((s) {
                final isSelected = _selectedSpecialty.toLowerCase() == s.toLowerCase();
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    key: Key('specialty_chip_$s'),
                    label: Text(
                      s,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isSelected ? Colors.white : AppTheme.textDark,
                      ),
                    ),
                    selected: isSelected,
                    selectedColor: AppTheme.primaryBlue,
                    backgroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(
                        color: isSelected ? AppTheme.primaryBlue : Colors.grey.shade300,
                      ),
                    ),
                    onSelected: (_) => _handleSelectSpecialtyFromDropdown(s),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Icon(
            _doctorTabFilter == 1 ? Icons.favorite_border_rounded : Icons.person_search_rounded,
            size: 46,
            color: AppTheme.textMuted,
          ),
          const SizedBox(height: 12),
          Text(
            _doctorTabFilter == 1
                ? 'No Favourite Doctors Yet'
                : 'No Matching Doctors Found',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _doctorTabFilter == 1
                ? 'Switch to "All Doctors" and open a doctor profile to add your preferred specialists.'
                : 'No doctors match your current search or medical specialty filter.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.textMedium, fontSize: 13),
          ),
          if (_doctorTabFilter == 1) ...[
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: () => setState(() => _doctorTabFilter = 0),
              icon: const Icon(Icons.people_alt_rounded, size: 16),
              label: const Text('Browse All Doctors'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Single-line compact doctor listing row:
  /// [Circular Doctor Image]  Dr. Full Name  →
  Widget _buildDoctorRow(DoctorModel doc) {
    final cleanName = doc.name.replaceAll('Dr. ', '').replaceAll('Dr.', '').trim();
    final initial = cleanName.isNotEmpty ? cleanName[0].toUpperCase() : 'D';
    final displayName = doc.name.trim().toLowerCase().startsWith('dr')
        ? doc.name.trim()
        : 'Dr. ${doc.name.trim()}';

    return Container(
      key: Key('doctor_card_${doc.id}'),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.025),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _openDoctorDetails(doc),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                // Circular Doctor Profile Image (Left)
                GestureDetector(
                  key: Key('doctor_image_${doc.id}'),
                  onTap: () => _openDoctorDetails(doc),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: doc.photoBytes == null ? _primaryGradient : null,
                      image: doc.photoBytes != null
                          ? DecorationImage(
                              image: MemoryImage(doc.photoBytes!),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    alignment: Alignment.center,
                    child: doc.photoBytes == null
                        ? Text(
                            initial,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          )
                        : null,
                  ),
                ),
                const SizedBox(width: 14),
                // Doctor Full Name (Middle)
                Expanded(
                  child: GestureDetector(
                    key: Key('doctor_name_${doc.id}'),
                    onTap: () => _openDoctorDetails(doc),
                    child: Text(
                      displayName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15.5,
                        color: AppTheme.textDark,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Subtle Right-Arrow Indicator
                InkWell(
                  key: Key('view_profile_button_${doc.id}'),
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => _openDoctorDetails(doc),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 16,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
