import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/models/medical_specialty_model.dart';
import '../../../../core/services/api_service.dart';
import '../../../../core/services/patient_problem_service.dart';
import '../../../auth/presentation/widgets/gs_health_registration_view.dart' show kGsHealthLanguages;
import '../widgets/book_consultation_fab.dart';
import '../widgets/book_visit_flow_dialog.dart';
import 'doctor_profile_screen.dart';

class FindDoctorsScreen extends StatefulWidget {
  final int initialTabFilter; // 0 = All Doctors, 1 = My Favourite Doctors
  final String initialSpecialty;
  final String initialLanguage;
  final bool isSpecialtyPage;
  final bool isAdminView;
  final void Function(BuildContext context, DoctorModel doctor)? onAdminEditDoctor;
  final void Function(BuildContext context, DoctorModel doctor)? onAdminDeleteDoctor;
  final void Function(BuildContext context, DoctorModel doctor)? onAdminAssignDoctor;
  final VoidCallback? onAdminCreateDoctor;
  final VoidCallback? onBack;

  const FindDoctorsScreen({
    super.key,
    this.initialTabFilter = 0,
    this.initialSpecialty = 'All',
    this.initialLanguage = 'Any language',
    this.isSpecialtyPage = false,
    this.isAdminView = false,
    this.onAdminEditDoctor,
    this.onAdminDeleteDoctor,
    this.onAdminAssignDoctor,
    this.onAdminCreateDoctor,
    this.onBack,
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
  final TextEditingController _languageSearchController = TextEditingController();

  late int _doctorTabFilter;
  String _searchQuery = '';
  String _cityFilter = '';
  String _pincodeFilter = '';
  late String _selectedSpecialty;
  final Set<String> _selectedLanguages = <String>{};
  List<String> _backendDoctorLanguages = [];
  List<DoctorModel>? _backendFilteredDoctors;
  int _filterRequestSeq = 0;
  Timer? _filterDebounce;
  bool _isUsingMyLocation = false;
  bool _onlineOnlyFilter = false;
  bool _isSyncing = false;
  String? _syncError;
  static const int _pageSize = 20;
  int _visibleCount = _pageSize;

  static const LinearGradient _primaryGradient = LinearGradient(
    colors: [AppTheme.gsNavy, Color(0xFF012A58)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  List<String> get _availableSpecialtyOptions {
    final specs = <String>[
      'All',
      ...MedicalSpecialtyModel.coreInitialSpecialties,
    ];
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
    if (_selectedSpecialty.trim().isNotEmpty &&
        !specs.any((item) => item.toLowerCase() == _selectedSpecialty.trim().toLowerCase())) {
      specs.add(_selectedSpecialty.trim());
    }
    return specs;
  }

  /// Merges all canonical supported application languages with backend & registered
  /// doctor languages without duplicates, keeping English/Hindi/Telugu prioritized first.
  List<String> get _supportedAndDoctorLanguages {
    final Map<String, String> langMap = <String, String>{};
    final Set<String> canonicalKeys = <String>{};

    final canonicalSeed = <String>[
      'English',
      'Hindi',
      'Telugu',
      ...kGsHealthLanguages,
    ];
    for (final lang in canonicalSeed) {
      final key = ApiService.canonicalLanguageKey(lang);
      if (key.isNotEmpty && !ApiService.isAnyLanguageToken(key) && !langMap.containsKey(key)) {
        langMap[key] = ApiService.canonicalLanguageDisplayName(lang);
        canonicalKeys.add(key);
      }
    }

    void mergeRaw(Iterable<String> rawItems) {
      for (final raw in rawItems) {
        for (final token in ApiService.splitRawLanguages(raw)) {
          final key = ApiService.canonicalLanguageKey(token);
          if (key.isEmpty || ApiService.isAnyLanguageToken(key)) continue;
          if (!langMap.containsKey(key)) {
            langMap[key] = ApiService.canonicalLanguageDisplayName(token);
          }
        }
      }
    }

    mergeRaw(_backendDoctorLanguages);
    for (final d in _patientService.allDoctors) {
      mergeRaw(d.languages);
    }
    mergeRaw(_selectedLanguages);

    final canonicalList = <String>[];
    final customList = <String>[];
    langMap.forEach((key, value) {
      if (canonicalKeys.contains(key)) {
        canonicalList.add(value);
      } else {
        customList.add(value);
      }
    });
    customList.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return <String>[...canonicalList, ...customList];
  }

  List<String> get _availableLanguageOptions => <String>[
        'Any language',
        ..._supportedAndDoctorLanguages,
      ];

  @override
  void initState() {
    super.initState();
    _doctorTabFilter = widget.initialTabFilter;
    _selectedSpecialty = widget.initialSpecialty.trim().isNotEmpty ? widget.initialSpecialty.trim() : 'All';
    final rawInitLang = widget.initialLanguage.trim();
    if (rawInitLang.isNotEmpty && rawInitLang.toLowerCase() != 'any language') {
      for (final part in rawInitLang.split(',')) {
        final clean = part.trim();
        if (clean.isNotEmpty && clean.toLowerCase() != 'any language') {
          _selectedLanguages.add(clean);
        }
      }
    }
    _patientService.addListener(_onServiceUpdated);
    _refreshDoctorsIfNeeded();
  }

  @override
  void dispose() {
    _filterDebounce?.cancel();
    _patientService.removeListener(_onServiceUpdated);
    _searchController.dispose();
    _cityFilterController.dispose();
    _pincodeFilterController.dispose();
    _languageSearchController.dispose();
    super.dispose();
  }

  void _onServiceUpdated() {
    if (mounted) {
      setState(() {});
    }
  }

  bool get _hasActiveBackendFilters {
    final specClean = _selectedSpecialty.trim().toLowerCase();
    final hasSpec = specClean.isNotEmpty && specClean != 'all' && specClean != 'all specialties';
    return _selectedLanguages.isNotEmpty ||
        _cityFilter.trim().isNotEmpty ||
        _pincodeFilter.trim().isNotEmpty ||
        hasSpec ||
        _onlineOnlyFilter ||
        _searchQuery.trim().isNotEmpty;
  }

  void _triggerBackendFilterFetch({bool debounce = false}) {
    _filterDebounce?.cancel();
    // Always discard previous backend filter snapshot so changing filters never shows stale results.
    if (_backendFilteredDoctors != null) {
      if (mounted) {
        setState(() {
          _backendFilteredDoctors = null;
        });
      } else {
        _backendFilteredDoctors = null;
      }
    }
    if (!_hasActiveBackendFilters || (!widget.isAdminView && _doctorTabFilter == 1)) {
      _filterRequestSeq++;
      return;
    }
    if (debounce) {
      _filterDebounce = Timer(const Duration(milliseconds: 220), () {
        if (mounted) {
          _fetchFilteredDoctorsFromBackend();
        }
      });
    } else {
      _fetchFilteredDoctorsFromBackend();
    }
  }

  Future<void> _fetchFilteredDoctorsFromBackend() async {
    final seq = ++_filterRequestSeq;
    final specClean = _selectedSpecialty.trim();
    final effectiveSpec = (specClean.isEmpty ||
            specClean.toLowerCase() == 'all' ||
            specClean.toLowerCase() == 'all specialties')
        ? null
        : specClean;

    try {
      final api = ApiService();
      final remoteDocs = await _patientService.fetchDoctorsFiltered(
        city: _cityFilter.trim().isNotEmpty ? _cityFilter.trim() : null,
        pincode: _pincodeFilter.trim().isNotEmpty ? _pincodeFilter.trim() : null,
        specialty: effectiveSpec,
        availability: _onlineOnlyFilter ? 'Online' : null,
        languages: _selectedLanguages.isNotEmpty ? _selectedLanguages.toList() : null,
        search: _searchQuery.trim().isNotEmpty ? _searchQuery.trim() : null,
        includeUnavailable: !_onlineOnlyFilter,
      );
      if (!mounted || seq != _filterRequestSeq) return;
      if (api.lastFetchDentistsSucceeded) {
        setState(() {
          _backendFilteredDoctors = remoteDocs;
          if (api.lastAvailableDoctorLanguages.isNotEmpty) {
            _backendDoctorLanguages = api.lastAvailableDoctorLanguages;
          }
        });
      }
    } catch (_) {
      // Keep local filtering fallback active when backend API is unreachable
    }
  }

  Future<void> _refreshDoctorsIfNeeded() async {
    if (mounted) {
      setState(() {
        _isSyncing = true;
        _syncError = null;
      });
    }
    try {
      final api = ApiService();
      await _patientService.syncDoctorsFromApi(includeUnavailable: true);
      await _patientService.syncMyDoctorsFromApi();
      final fetchedLangs = await api.fetchAvailableDoctorLanguages(
        includeUnavailable: true,
      );
      final resolvedLangs = fetchedLangs.isNotEmpty
          ? fetchedLangs
          : api.lastAvailableDoctorLanguages;
      if (mounted && resolvedLangs.isNotEmpty) {
        setState(() {
          _backendDoctorLanguages = resolvedLangs;
        });
      }
      if (_hasActiveBackendFilters && (widget.isAdminView || _doctorTabFilter == 0)) {
        _backendFilteredDoctors = null;
        await _fetchFilteredDoctorsFromBackend();
      } else {
        _backendFilteredDoctors = null;
      }
    } catch (e) {
      if (mounted) {
        _syncError = e.toString().replaceFirst('Exception: ', '');
      }
    }
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

  bool _matchesSpecialty(DoctorModel d, String selectedSpec) {
    final clean = selectedSpec.trim();
    if (clean.isEmpty || clean.toLowerCase() == 'all' || clean.toLowerCase() == 'all specialties') {
      return true;
    }
    return MedicalSpecialtyModel.matchesSpecialtyFilter(
      d.specialty,
      clean,
      specialties: _patientService.specialties,
    );
  }

  bool _isLanguageSelected(String lang) {
    final targetKey = ApiService.canonicalLanguageKey(lang);
    if (targetKey.isEmpty) return false;
    return _selectedLanguages.any((s) => ApiService.canonicalLanguageKey(s) == targetKey);
  }

  void _toggleLanguageSelection(String lang) {
    final clean = ApiService.canonicalLanguageDisplayName(lang);
    final targetKey = ApiService.canonicalLanguageKey(lang);
    if (ApiService.isAnyLanguageToken(targetKey)) {
      setState(() {
        _selectedLanguages.clear();
        _visibleCount = _pageSize;
      });
      _triggerBackendFilterFetch();
      return;
    }
    setState(() {
      final existing = _selectedLanguages
          .where((s) => ApiService.canonicalLanguageKey(s) == targetKey)
          .toList();
      if (existing.isNotEmpty) {
        _selectedLanguages.removeAll(existing);
      } else {
        _selectedLanguages.add(clean.isNotEmpty ? clean : lang.trim());
      }
      _visibleCount = _pageSize;
    });
    _triggerBackendFilterFetch();
  }

  void _clearLanguageFilter() {
    setState(() {
      _selectedLanguages.clear();
      _visibleCount = _pageSize;
    });
    _triggerBackendFilterFetch();
  }

  bool _matchesLanguage(DoctorModel d) {
    return ApiService.doctorLanguagesMatch(d.languages, _selectedLanguages);
  }

  void _toggleUseMyLocation() {
    setState(() {
      _isUsingMyLocation = !_isUsingMyLocation;
      final patient = _patientService.currentPatient;
      if (_isUsingMyLocation) {
        if (patient.city.trim().isNotEmpty && _cityFilter.trim().isEmpty) {
          _cityFilter = patient.city.trim();
          _cityFilterController.text = _cityFilter;
        }
        if (patient.pincode.trim().isNotEmpty && _pincodeFilter.trim().isEmpty) {
          _pincodeFilter = patient.pincode.trim();
          _pincodeFilterController.text = _pincodeFilter;
        }
      } else {
        if (patient.city.trim().isNotEmpty && _cityFilter.trim().toLowerCase() == patient.city.trim().toLowerCase()) {
          _cityFilter = '';
          _cityFilterController.clear();
        }
        if (patient.pincode.trim().isNotEmpty && _pincodeFilter.trim().toLowerCase() == patient.pincode.trim().toLowerCase()) {
          _pincodeFilter = '';
          _pincodeFilterController.clear();
        }
      }
    });
    _triggerBackendFilterFetch();
  }

  void _handleSelectSpecialtyFromDropdown(String specialty) {
    final clean = specialty.trim();
    if (clean.isEmpty || clean.toLowerCase() == 'all' || clean.toLowerCase() == 'all specialties') {
      if (widget.isSpecialtyPage && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
        return;
      }
      setState(() => _selectedSpecialty = 'All');
      _triggerBackendFilterFetch();
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
          initialLanguage: _selectedLanguages.isEmpty ? 'Any language' : _selectedLanguages.join(','),
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
    final isFavTab = !widget.isAdminView && _doctorTabFilter == 1;
    final useBackendFiltered = !isFavTab && _hasActiveBackendFilters && _backendFilteredDoctors != null;
    final baseDocs = isFavTab
        ? myDocs
        : (useBackendFiltered ? _backendFilteredDoctors! : allDocs);

    final filteredDocs = baseDocs.where((d) {
      if (_onlineOnlyFilter && !d.isOnline) return false;
      final matchesSpec = _matchesSpecialty(d, _selectedSpecialty);
      if (!matchesSpec) return false;
      final matchesLang = _matchesLanguage(d);
      if (!matchesLang) return false;
      if (useBackendFiltered) return true;

      final q = _searchQuery.trim().toLowerCase();
      final matchesSearch = q.isEmpty ||
          d.name.toLowerCase().contains(q) ||
          d.specialty.toLowerCase().contains(q) ||
          d.clinicName.toLowerCase().contains(q) ||
          d.city.toLowerCase().contains(q) ||
          d.state.toLowerCase().contains(q) ||
          d.pincode.toLowerCase().contains(q) ||
          d.qualification.toLowerCase().contains(q) ||
          d.languages.any((l) => l.toLowerCase().contains(q));
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
      return matchesSearch && matchesCity && matchesPincode;
    }).toList();

    final visibleDocs = filteredDocs.length > _visibleCount
        ? filteredDocs.take(_visibleCount).toList()
        : filteredDocs;
    final hasMoreDocs = filteredDocs.length > visibleDocs.length;

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
          onTap: () {
            if (widget.onBack != null) {
              widget.onBack!();
            } else if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          },
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
                icon: const Icon(Icons.person_add_rounded, size: 16, color: AppTheme.gsNavy),
                label: const Text(
                  '+ Create Doctor',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppTheme.gsNavy),
                ),
              ),
            ),
          IconButton(
            tooltip: 'Refresh Doctors',
            onPressed: _refreshDoctorsIfNeeded,
            icon: const Icon(Icons.refresh_rounded, color: AppTheme.gsNavy),
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
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 84),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Verified by GS HEALTH',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Find a doctor',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textDark,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _buildHeaderBanner(filteredDocs.length, isSpecificSpecialty),
                  const SizedBox(height: 14),
                  if (!widget.isAdminView && !widget.isSpecialtyPage) ...[
                    _buildTabSelector(allDocs.length, myDocs.length),
                    const SizedBox(height: 12),
                  ],
                  _buildSearchBar(),
                  const SizedBox(height: 10),
                  _buildUseMyLocationRow(),
                  const SizedBox(height: 10),
                  _buildLocationFiltersRow(),
                  const SizedBox(height: 12),
                  _buildAllSpecialtyDropdownAndFilterRow(),
                  const SizedBox(height: 10),
                  _buildLanguageFilterRow(),
                  const SizedBox(height: 10),
                  _buildOnlineAvailabilityFilterRow(),
                  const SizedBox(height: 16),
                  if (_isSyncing && allDocs.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_syncError != null && allDocs.isEmpty)
                    _buildErrorState(_syncError!)
                  else if (filteredDocs.isEmpty)
                    _buildEmptyState()
                  else
                    Column(
                      children: [
                        ...visibleDocs.map(
                          (doc) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _buildDoctorRow(doc),
                          ),
                        ),
                        if (hasMoreDocs)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: OutlinedButton.icon(
                              key: const Key('find_doctors_load_more_button'),
                              onPressed: () {
                                setState(() {
                                  _visibleCount += _pageSize;
                                });
                              },
                              icon: const Icon(Icons.expand_more_rounded, size: 18),
                              label: Text(
                                'Load More Doctors (${filteredDocs.length - visibleDocs.length} remaining)',
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppTheme.gsNavy,
                                side: const BorderSide(color: AppTheme.gsNavy),
                                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: widget.isAdminView
          ? null
          : BookConsultationFab(
              selectedSpecialty: _selectedSpecialty,
              onPressed: () => BookVisitFlowDialog.show(
                context,
                initialSpecialtyFilter: isSpecificSpecialty ? _selectedSpecialty : null,
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
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: _primaryGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppTheme.gsNavy.withValues(alpha: 0.16),
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
              size: 26,
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
                    fontSize: 17,
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
                          : 'Browse verified medical specialists and book appointments online'),
                  style: TextStyle(
                    fontSize: 12,
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
              onTap: () {
                setState(() => _doctorTabFilter = 0);
                if (_hasActiveBackendFilters) {
                  _triggerBackendFilterFetch();
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                decoration: BoxDecoration(
                  color: _doctorTabFilter == 0 ? AppTheme.gsNavy : Colors.transparent,
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
                  color: _doctorTabFilter == 1 ? AppTheme.gsNavy : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.favorite_rounded,
                      size: 16,
                      color: _doctorTabFilter == 1 ? AppTheme.gsRed : AppTheme.textMedium,
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
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: TextField(
        key: const ValueKey('find_doctors_search_input'),
        controller: _searchController,
        onChanged: (v) {
          setState(() => _searchQuery = v);
          _triggerBackendFilterFetch(debounce: true);
        },
        decoration: InputDecoration(
          hintText: 'Name, speciality, clinic or pincode...',
          hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 13.5),
          prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.gsNavy, size: 20),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                    _triggerBackendFilterFetch();
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }

  Widget _buildUseMyLocationRow() {
    return Row(
      children: [
        InkWell(
          key: const Key('use_my_location_button'),
          onTap: _toggleUseMyLocation,
          borderRadius: BorderRadius.circular(24),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: _isUsingMyLocation ? AppTheme.gsNavy : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: _isUsingMyLocation ? AppTheme.gsNavy : const Color(0xFFCBD5E1),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.my_location_rounded,
                  size: 16,
                  color: _isUsingMyLocation ? Colors.white : AppTheme.gsNavy,
                ),
                const SizedBox(width: 7),
                Text(
                  'Use my location',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _isUsingMyLocation ? Colors.white : AppTheme.textDark,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        const Expanded(
          child: Text(
            'Only used to find nearby doctors',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Color(0xFF64748B),
              height: 1.25,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
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
              onChanged: (v) {
                setState(() => _cityFilter = v);
                _triggerBackendFilterFetch(debounce: true);
              },
              decoration: InputDecoration(
                hintText: 'Filter by City...',
                hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 12.5),
                prefixIcon: const Icon(Icons.location_city_rounded, color: AppTheme.gsNavy, size: 18),
                suffixIcon: _cityFilter.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 16),
                        onPressed: () {
                          _cityFilterController.clear();
                          setState(() => _cityFilter = '');
                          _triggerBackendFilterFetch();
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
              onChanged: (v) {
                setState(() => _pincodeFilter = v);
                _triggerBackendFilterFetch(debounce: true);
              },
              decoration: InputDecoration(
                hintText: 'Filter by Pincode...',
                hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 12.5),
                prefixIcon: const Icon(Icons.pin_drop_outlined, color: AppTheme.gsNavy, size: 18),
                suffixIcon: _pincodeFilter.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 16),
                        onPressed: () {
                          _pincodeFilterController.clear();
                          setState(() => _pincodeFilter = '');
                          _triggerBackendFilterFetch();
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
        // ALL Button — Medical Specialty Dropdown (preserves existing key & dropdown menu behavior)
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
                      color: isCurrent ? AppTheme.gsNavy : AppTheme.textMedium,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        displayLabel,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w600,
                          color: isCurrent ? AppTheme.gsNavy : AppTheme.textDark,
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
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFCBD5E1)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.tune_rounded, size: 15, color: AppTheme.gsNavy),
                SizedBox(width: 4),
                Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: AppTheme.gsNavy),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Horizontally Scrollable Specialty Pill Row (All, General Dentist, Orthodontist, ...)
        Expanded(
          child: SingleChildScrollView(
            key: const Key('specialty_filter_scroll_view'),
            scrollDirection: Axis.horizontal,
            child: Row(
              children: options.map((s) {
                final isChipAll = s.toLowerCase() == 'all';
                final isSelected = isChipAll
                    ? isAllSelected
                    : _selectedSpecialty.trim().toLowerCase() == s.trim().toLowerCase();
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      key: Key('specialty_chip_$s'),
                      borderRadius: BorderRadius.circular(24),
                      onTap: () {
                        setState(() {
                          _selectedSpecialty = isChipAll ? 'All' : s;
                          _visibleCount = _pageSize;
                        });
                        _triggerBackendFilterFetch();
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                        decoration: BoxDecoration(
                          color: isSelected ? AppTheme.gsNavy : Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: isSelected ? AppTheme.gsNavy : const Color(0xFFCBD5E1),
                            width: 1.1,
                          ),
                        ),
                        child: Text(
                          s,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                            color: isSelected ? Colors.white : AppTheme.textDark,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showLanguageMultiSelectDialog() async {
    final availableLangs = _supportedAndDoctorLanguages;
    final Set<String> draftSelected = Set<String>.from(_selectedLanguages);
    final ScrollController listScrollController = ScrollController();
    _languageSearchController.clear();
    String langSearch = '';

    bool isDraftSelected(String lang) {
      final targetKey = ApiService.canonicalLanguageKey(lang);
      if (targetKey.isEmpty) return false;
      return draftSelected.any((s) => ApiService.canonicalLanguageKey(s) == targetKey);
    }

    void toggleDraftLanguage(String lang) {
      final clean = ApiService.canonicalLanguageDisplayName(lang);
      final targetKey = ApiService.canonicalLanguageKey(lang);
      if (ApiService.isAnyLanguageToken(targetKey)) {
        draftSelected.clear();
        return;
      }
      final existing = draftSelected
          .where((s) => ApiService.canonicalLanguageKey(s) == targetKey)
          .toList();
      if (existing.isNotEmpty) {
        draftSelected.removeAll(existing);
      } else {
        draftSelected.add(clean.isNotEmpty ? clean : lang.trim());
      }
    }

    try {
      final applied = await showDialog<bool>(
        context: context,
        builder: (dialogCtx) {
          return StatefulBuilder(
            builder: (ctx, setModalState) {
              final q = langSearch.trim().toLowerCase();
              final matchingLangs = q.isEmpty
                  ? availableLangs
                  : availableLangs.where((l) => l.toLowerCase().contains(q)).toList();
              final media = MediaQuery.of(ctx);
              final screenSize = media.size;
              final availableHeight = (screenSize.height - media.viewInsets.bottom).clamp(220.0, 900.0);
              final dialogWidth = (screenSize.width - 56).clamp(230.0, 360.0);
              final listMaxHeight = (availableHeight * 0.38).clamp(120.0, 320.0);

              return AlertDialog(
                key: const Key('language_multiselect_dialog'),
                insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                title: Row(
                  children: [
                    const Icon(Icons.translate_rounded, color: AppTheme.gsNavy, size: 20),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Filter by Language',
                        style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800, color: AppTheme.textDark),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (draftSelected.isNotEmpty)
                      TextButton(
                        key: const Key('language_multiselect_clear_btn'),
                        onPressed: () {
                          setModalState(() => draftSelected.clear());
                        },
                        child: const Text(
                          'Clear',
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppTheme.gsRed),
                        ),
                      ),
                  ],
                ),
                content: SizedBox(
                  width: dialogWidth,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: EdgeInsets.only(bottom: 8),
                          child: Text(
                            'Select one or more languages. Shows doctors speaking at least one selected language.',
                            style: TextStyle(fontSize: 12, color: Color(0xFF64748B), height: 1.35),
                          ),
                        ),
                      ),
                      TextField(
                        key: const Key('language_search_input'),
                        controller: _languageSearchController,
                        onChanged: (val) {
                          setModalState(() => langSearch = val);
                        },
                        decoration: InputDecoration(
                          hintText: 'Search languages...',
                          hintStyle: const TextStyle(fontSize: 13, color: AppTheme.textMuted),
                          prefixIcon: const Icon(Icons.search_rounded, size: 18, color: AppTheme.gsNavy),
                          suffixIcon: langSearch.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear_rounded, size: 16),
                                  onPressed: () {
                                    _languageSearchController.clear();
                                    setModalState(() => langSearch = '');
                                  },
                                )
                              : null,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: AppTheme.gsNavy, width: 1.3),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: listMaxHeight),
                        child: Scrollbar(
                          controller: listScrollController,
                          thumbVisibility: matchingLangs.length > 5,
                          child: SingleChildScrollView(
                            controller: listScrollController,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (q.isEmpty || 'any language'.contains(q))
                                  CheckboxListTile(
                                    key: const Key('language_checkbox_Any language'),
                                    value: draftSelected.isEmpty,
                                    activeColor: AppTheme.gsNavy,
                                    contentPadding: EdgeInsets.zero,
                                    dense: true,
                                    controlAffinity: ListTileControlAffinity.leading,
                                    title: Text(
                                      'Any language',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: draftSelected.isEmpty ? FontWeight.w700 : FontWeight.w500,
                                        color: AppTheme.textDark,
                                      ),
                                    ),
                                    onChanged: (_) {
                                      setModalState(() => draftSelected.clear());
                                    },
                                  ),
                                if (matchingLangs.isEmpty)
                                  const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 12),
                                    child: Text(
                                      'No matching languages found.',
                                      style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
                                    ),
                                  )
                                else
                                  ...matchingLangs.map((lang) {
                                    final checked = isDraftSelected(lang);
                                    return CheckboxListTile(
                                      key: Key('language_checkbox_$lang'),
                                      value: checked,
                                      activeColor: AppTheme.gsNavy,
                                      contentPadding: EdgeInsets.zero,
                                      dense: true,
                                      controlAffinity: ListTileControlAffinity.leading,
                                      title: Text(
                                        lang,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: checked ? FontWeight.w700 : FontWeight.w500,
                                          color: AppTheme.textDark,
                                        ),
                                      ),
                                      onChanged: (_) {
                                        setModalState(() => toggleDraftLanguage(lang));
                                      },
                                    );
                                  }),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  ElevatedButton(
                    key: const Key('language_multiselect_done_btn'),
                    onPressed: () => Navigator.of(dialogCtx).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.gsNavy,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Done', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ],
              );
            },
          );
        },
      );

      if (applied == true && mounted) {
        setState(() {
          _selectedLanguages
            ..clear()
            ..addAll(draftSelected);
          _visibleCount = _pageSize;
        });
        _triggerBackendFilterFetch();
      }
    } finally {
      listScrollController.dispose();
    }
  }

  Widget _buildLanguageFilterRow() {
    final languages = _availableLanguageOptions;
    final isAnySelected = _selectedLanguages.isEmpty;
    final dropdownSummary = _selectedLanguages.isEmpty
        ? 'Filter by Language'
        : (_selectedLanguages.length <= 2
            ? _selectedLanguages.join(', ')
            : '${_selectedLanguages.length} Languages');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // Multi-Select Searchable "Filter by Language" Dropdown Button (no cramped fixed width)
            Flexible(
              child: InkWell(
                key: const Key('filter_by_language_dropdown'),
                onTap: _showLanguageMultiSelectDialog,
                borderRadius: BorderRadius.circular(24),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: _selectedLanguages.isNotEmpty ? const Color(0x14012A58) : Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: _selectedLanguages.isNotEmpty ? AppTheme.gsNavy : const Color(0xFFCBD5E1),
                      width: 1.1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.translate_rounded, size: 15, color: AppTheme.gsNavy),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          dropdownSummary,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: _selectedLanguages.isNotEmpty ? FontWeight.w700 : FontWeight.w600,
                            color: AppTheme.gsNavy,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: AppTheme.gsNavy),
                    ],
                  ),
                ),
              ),
            ),
            if (_selectedLanguages.isNotEmpty) ...[
              const SizedBox(width: 6),
              InkWell(
                key: const Key('clear_language_filter_button'),
                onTap: _clearLanguageFilter,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0x14FE3434),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0x40FE3434)),
                  ),
                  child: const Icon(Icons.close_rounded, size: 14, color: AppTheme.gsRed),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        // Full-Width Horizontally Scrollable Language Chips (displays all registered doctors' languages without clipping)
        SizedBox(
          width: double.infinity,
          child: SingleChildScrollView(
            key: const Key('language_filter_scroll_view'),
            scrollDirection: Axis.horizontal,
            child: Row(
              children: languages.map((lang) {
                final isAnyOption = lang.trim().toLowerCase() == 'any language';
                final isSelected = isAnyOption ? isAnySelected : _isLanguageSelected(lang);

                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      key: Key('language_filter_chip_$lang'),
                      borderRadius: BorderRadius.circular(24),
                      onTap: () => _toggleLanguageSelection(lang),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
                        decoration: BoxDecoration(
                          color: isSelected ? AppTheme.gsNavy : Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: isSelected ? AppTheme.gsNavy : const Color(0xFFCBD5E1),
                            width: 1.1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!isAnyOption) ...[
                              Icon(
                                isSelected ? Icons.check_circle_rounded : Icons.translate_rounded,
                                size: 13.5,
                                color: isSelected ? Colors.white : AppTheme.gsNavy,
                              ),
                              const SizedBox(width: 5),
                            ],
                            Text(
                              lang,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                                color: isSelected ? Colors.white : AppTheme.textDark,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOnlineAvailabilityFilterRow() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        InkWell(
          key: const Key('online_availability_filter_chip'),
          borderRadius: BorderRadius.circular(24),
          onTap: () {
            setState(() {
              _onlineOnlyFilter = !_onlineOnlyFilter;
              _visibleCount = _pageSize;
            });
            _triggerBackendFilterFetch();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: _onlineOnlyFilter ? const Color(0xFF047857) : Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: _onlineOnlyFilter ? const Color(0xFF047857) : const Color(0xFFCBD5E1),
                width: 1.1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _onlineOnlyFilter ? Colors.white : const Color(0xFF10B981),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'Available Online',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: _onlineOnlyFilter ? Colors.white : AppTheme.textDark,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    final hasLanguageFilter = _doctorTabFilter != 1 && _selectedLanguages.isNotEmpty;
    final hasActiveFilters = _searchQuery.trim().isNotEmpty ||
        _cityFilter.trim().isNotEmpty ||
        _pincodeFilter.trim().isNotEmpty ||
        _onlineOnlyFilter ||
        (_selectedSpecialty.trim().isNotEmpty && _selectedSpecialty.trim().toLowerCase() != 'all') ||
        _selectedLanguages.isNotEmpty;

    final emptyTitle = _doctorTabFilter == 1
        ? 'No Favourite Doctors Yet'
        : (hasLanguageFilter
            ? 'No doctors available for the selected language.'
            : (hasActiveFilters ? 'No Matching Doctors Found' : 'Search to find a doctor'));

    final emptySubtitle = _doctorTabFilter == 1
        ? 'Switch to "All Doctors" and open a doctor profile to add your preferred specialists.'
        : (hasLanguageFilter
            ? 'No doctors currently match ${_selectedLanguages.join(', ')}. Choose another language or reset the language filter.'
            : 'Type a name, speciality, city or pincode, or tap "Use my location" to see doctors near you.');

    return Container(
      key: const Key('find_doctors_empty_state'),
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppTheme.gsNavy.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(
              _doctorTabFilter == 1
                  ? Icons.favorite_border_rounded
                  : (hasLanguageFilter ? Icons.translate_rounded : Icons.search_rounded),
              size: 30,
              color: AppTheme.gsNavy,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            emptyTitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 17,
              color: AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            emptySubtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.textMedium, fontSize: 13.5, height: 1.4),
          ),
          if (_doctorTabFilter == 1) ...[
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: () => setState(() => _doctorTabFilter = 0),
              icon: const Icon(Icons.people_alt_rounded, size: 16),
              label: const Text('Browse All Doctors'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.gsNavy,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ] else if (hasLanguageFilter) ...[
            const SizedBox(height: 14),
            ElevatedButton.icon(
              key: const Key('empty_state_reset_language_filter_button'),
              onPressed: _clearLanguageFilter,
              icon: const Icon(Icons.filter_alt_off_rounded, size: 16),
              label: const Text('Reset Language Filter'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.gsNavy,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildErrorState(String errorMessage) {
    return Container(
      key: const Key('find_doctors_error_state'),
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x40FE3434)),
      ),
      child: Column(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppTheme.gsRed, size: 36),
          const SizedBox(height: 10),
          const Text(
            'Unable to load doctors',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppTheme.textDark),
          ),
          const SizedBox(height: 4),
          Text(
            errorMessage,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12.5, color: AppTheme.textMedium),
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            key: const Key('find_doctors_retry_button'),
            onPressed: _refreshDoctorsIfNeeded,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.gsNavy,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  /// Doctor listing card showing name, photo, specialization, qualifications, experience,
  /// clinic/hospital, languages, real consultation fee, online/available status, and next slot.
  Widget _buildDoctorRow(DoctorModel doc) {
    final cleanName = doc.name.replaceAll('Dr. ', '').replaceAll('Dr.', '').trim();
    final initial = cleanName.isNotEmpty ? cleanName[0].toUpperCase() : 'D';
    final displayName = doc.name.trim().toLowerCase().startsWith('dr')
        ? doc.name.trim()
        : 'Dr. ${doc.name.trim()}';
    final specialtyText = doc.specialty.trim().isNotEmpty ? doc.specialty.trim() : 'Medical Specialist';
    final qualText = doc.qualification.trim().isNotEmpty
        ? doc.qualification.trim()
        : MedicalSpecialtyModel.getDefaultQualificationForSpecialty(specialtyText);
    final clinicText = doc.clinicName.trim().isNotEmpty ? doc.clinicName.trim() : 'Independent Practice';
    final cityText = doc.city.trim();
    final isDocAvailable = doc.isAvailable;
    final isDocOnline = doc.isOnline;
    final isDocBusy = doc.isBusy;
    final expText = doc.experienceYears > 0 ? '${doc.experienceYears} yrs exp' : '';
    final cleanFee = doc.consultationFee.trim();
    final hasRealFee = cleanFee.isNotEmpty &&
        cleanFee.toLowerCase() != 'null' &&
        cleanFee != r'$75' &&
        cleanFee != '75';
    final nextSlot = doc.nextAvailableSlots.isNotEmpty ? doc.nextAvailableSlots.first.trim() : '';

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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Circular Doctor Profile Image with live Online dot (Left)
                GestureDetector(
                  key: Key('doctor_image_${doc.id}'),
                  onTap: () => _openDoctorDetails(doc),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 48,
                        height: 48,
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
                      if (isDocOnline)
                        Positioned(
                          right: -1,
                          bottom: -1,
                          child: Container(
                            key: Key('doctor_online_dot_${doc.id}'),
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                // Doctor Details (Middle)
                Expanded(
                  child: GestureDetector(
                    key: Key('doctor_name_${doc.id}'),
                    onTap: () => _openDoctorDetails(doc),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                displayName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15.5,
                                  color: AppTheme.textDark,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              key: Key('doctor_availability_badge_${doc.id}'),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                              decoration: BoxDecoration(
                                color: !isDocAvailable
                                    ? const Color(0xFFF1F5F9)
                                    : isDocBusy
                                        ? const Color(0xFFFEF3C7)
                                        : const Color(0x14012A58),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                !isDocAvailable
                                    ? 'Unavailable'
                                    : isDocBusy
                                        ? 'Busy'
                                        : (isDocOnline ? 'Online • Available' : 'Available'),
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: !isDocAvailable
                                      ? const Color(0xFF64748B)
                                      : isDocBusy
                                          ? const Color(0xFFB45309)
                                          : const Color(0xFF012A58),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          expText.isNotEmpty
                              ? '$specialtyText • $qualText • $expText'
                              : '$specialtyText • $qualText',
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primaryBlue,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          cityText.isNotEmpty ? '$clinicText • $cityText' : clinicText,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (doc.languages.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              const Icon(Icons.translate_rounded, size: 12, color: AppTheme.gsNavy),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  doc.languages.join(', '),
                                  key: Key('doctor_languages_${doc.id}'),
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    color: Color(0xFF475569),
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (hasRealFee || nextSlot.isNotEmpty || (doc.reviewCount > 0 && doc.rating > 0)) ...[
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 8,
                            runSpacing: 3,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (hasRealFee)
                                Text(
                                  'Fee: $cleanFee',
                                  key: Key('doctor_fee_${doc.id}'),
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.gsNavy,
                                  ),
                                ),
                              if (nextSlot.isNotEmpty)
                                Text(
                                  'Next: $nextSlot',
                                  key: Key('doctor_next_slot_${doc.id}'),
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF047857),
                                  ),
                                ),
                              if (doc.reviewCount > 0 && doc.rating > 0)
                                Text(
                                  '★ ${doc.rating.toStringAsFixed(1)} (${doc.reviewCount})',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFFB45309),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ],
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
