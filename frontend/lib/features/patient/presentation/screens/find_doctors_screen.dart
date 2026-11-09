import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/services/patient_problem_service.dart';
import 'doctor_profile_screen.dart';

class FindDoctorsScreen extends StatefulWidget {
  final int initialTabFilter; // 0 = All Doctors, 1 = My Favourite Doctors

  const FindDoctorsScreen({
    super.key,
    this.initialTabFilter = 0,
  });

  @override
  State<FindDoctorsScreen> createState() => _FindDoctorsScreenState();
}

class _FindDoctorsScreenState extends State<FindDoctorsScreen> {
  final PatientProblemService _patientService = PatientProblemService();
  final TextEditingController _searchController = TextEditingController();

  late int _doctorTabFilter;
  String _searchQuery = '';
  String _selectedSpecialty = 'All';
  bool _isSyncing = false;

  static const Color _successGreen = Color(0xFF10B981);
  static const LinearGradient _primaryGradient = LinearGradient(
    colors: [AppTheme.primaryBlue, AppTheme.primaryBlueDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const List<String> _specialties = [
    'All',
    'General Dentistry',
    'Orthodontics',
    'Endodontics',
    'Cosmetic Dentistry',
    'Periodontics',
    'Oral Surgery',
  ];

  @override
  void initState() {
    super.initState();
    _doctorTabFilter = widget.initialTabFilter;
    _patientService.addListener(_onServiceUpdated);
    _refreshDoctorsIfNeeded();
  }

  @override
  void dispose() {
    _patientService.removeListener(_onServiceUpdated);
    _searchController.dispose();
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
        builder: (_) => DoctorProfileScreen(doctor: doc),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allDocs = _patientService.allDoctors;
    final myDocs = _patientService.myDoctors;
    final baseDocs = _doctorTabFilter == 0 ? allDocs : myDocs;

    final filteredDocs = baseDocs.where((d) {
      final q = _searchQuery.trim().toLowerCase();
      final matchesSearch = q.isEmpty ||
          d.name.toLowerCase().contains(q) ||
          d.specialty.toLowerCase().contains(q) ||
          d.clinicName.toLowerCase().contains(q) ||
          d.city.toLowerCase().contains(q) ||
          d.qualification.toLowerCase().contains(q);
      final matchesSpec = _selectedSpecialty == 'All' ||
          d.specialty.toLowerCase().contains(_selectedSpecialty.toLowerCase());
      return matchesSearch && matchesSpec;
    }).toList();

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
        title: const Text(
          'Find Doctors',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppTheme.textDark,
          ),
        ),
        actions: [
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
            constraints: const BoxConstraints(maxWidth: 1080),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 36),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeaderBanner(allDocs.length),
                  const SizedBox(height: 18),
                  _buildTabSelector(allDocs.length, myDocs.length),
                  const SizedBox(height: 14),
                  _buildSearchBar(),
                  const SizedBox(height: 12),
                  _buildSpecialtyFilterChips(),
                  const SizedBox(height: 18),
                  if (_isSyncing && allDocs.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (filteredDocs.isEmpty)
                    _buildEmptyState()
                  else
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth >= 720;
                        if (isWide) {
                          final cardWidth = (constraints.maxWidth - 16) / 2;
                          return Wrap(
                            spacing: 16,
                            runSpacing: 16,
                            children: filteredDocs
                                .map(
                                  (doc) => SizedBox(
                                    width: cardWidth,
                                    child: _buildDoctorCard(doc),
                                  ),
                                )
                                .toList(),
                          );
                        }
                        return Column(
                          children: filteredDocs
                              .map(
                                (doc) => Padding(
                                  padding: const EdgeInsets.only(bottom: 14),
                                  child: _buildDoctorCard(doc),
                                ),
                              )
                              .toList(),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderBanner(int totalCount) {
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
                const Text(
                  'Discover Dental Specialists',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  totalCount > 0
                      ? '$totalCount verified doctors available for consultation & appointment booking'
                      : 'Browse verified dental specialists and book appointments online',
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
        controller: _searchController,
        onChanged: (v) => setState(() => _searchQuery = v),
        decoration: InputDecoration(
          hintText: 'Search by doctor name, specialty, qualification, clinic, or city...',
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

  Widget _buildSpecialtyFilterChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _specialties.map((s) {
          final isSelected = _selectedSpecialty == s;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
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
              onSelected: (_) => setState(() => _selectedSpecialty = s),
            ),
          );
        }).toList(),
      ),
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
                ? 'Switch to "All Doctors" and add your preferred specialists to access them quickly.'
                : 'No doctors match your current search or specialty filter.',
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

  Widget _buildDoctorCard(DoctorModel doc) {
    final isAvailable = doc.status.trim().toLowerCase() == 'available';
    final isAdded = _patientService.isDoctorAdded(doc.id.isNotEmpty ? doc.id : doc.userId);
    final cleanName = doc.name.replaceAll('Dr. ', '').replaceAll('Dr.', '').trim();
    final initial = cleanName.isNotEmpty ? cleanName[0].toUpperCase() : 'D';

    final locationDisplay = <String>[
      if (doc.clinicName.trim().isNotEmpty) doc.clinicName.trim(),
      if (doc.city.trim().isNotEmpty) doc.city.trim(),
    ].join(' • ');

    return Container(
      key: Key('doctor_card_${doc.id}'),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isAdded ? AppTheme.primaryBlue.withValues(alpha: 0.35) : Colors.grey.shade200,
          width: isAdded ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _openDoctorDetails(doc),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Doctor Profile Image (clickable)
                    GestureDetector(
                      key: Key('doctor_image_${doc.id}'),
                      onTap: () => _openDoctorDetails(doc),
                      child: Container(
                        width: 66,
                        height: 66,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
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
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                ),
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(width: 14),
                    // Doctor Name, Specialization, Qualification, Experience & Clinic/City
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: GestureDetector(
                                  key: Key('doctor_name_${doc.id}'),
                                  onTap: () => _openDoctorDetails(doc),
                                  child: Text(
                                    doc.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                      color: AppTheme.textDark,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: isAvailable
                                      ? _successGreen.withValues(alpha: 0.1)
                                      : AppTheme.brandOrange.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  doc.status.isNotEmpty ? doc.status : 'Available',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: isAvailable ? _successGreen : AppTheme.brandOrange,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          // Dental Specialization
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryBlue.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              doc.specialty.isNotEmpty ? doc.specialty : 'General Dentistry',
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.primaryBlue,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(height: 7),
                          // Qualification & Experience
                          Wrap(
                            spacing: 12,
                            runSpacing: 4,
                            children: [
                              if (doc.qualification.trim().isNotEmpty)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.school_outlined, size: 14, color: AppTheme.textMedium),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        doc.qualification.trim(),
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: AppTheme.textDark,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              if (doc.experienceYears > 0)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.workspace_premium_outlined, size: 14, color: AppTheme.primaryBlue),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${doc.experienceYears}+ yrs exp',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.textMedium,
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                          if (locationDisplay.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Icon(Icons.location_on_outlined, size: 14, color: AppTheme.textMedium),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    locationDisplay,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.textMedium,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Divider(height: 1),
                const SizedBox(height: 12),
                // Card Footer: View Profile Button & Favourite Toggle Button
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        key: Key('view_profile_button_${doc.id}'),
                        onPressed: () => _openDoctorDetails(doc),
                        icon: const Icon(Icons.person_search_rounded, size: 16),
                        label: const Text(
                          'View Profile',
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                          overflow: TextOverflow.ellipsis,
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryBlue,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          if (isAdded) {
                            await _patientService.removeDoctorFromMyDoctors(doc);
                          } else {
                            await _patientService.addDoctorToMyDoctors(doc);
                          }
                        },
                        icon: Icon(
                          isAdded ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                          size: 16,
                          color: isAdded ? AppTheme.statusCancelText : AppTheme.primaryBlue,
                        ),
                        label: Text(
                          isAdded ? 'Added to Favourites' : 'Add Favourite Doctor',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: isAdded ? AppTheme.textDark : AppTheme.primaryBlue,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: isAdded
                                ? Colors.grey.shade300
                                : AppTheme.primaryBlue.withValues(alpha: 0.4),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
    );
  }
}

