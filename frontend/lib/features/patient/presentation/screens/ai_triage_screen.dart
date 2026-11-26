import 'package:flutter/material.dart';
import '../../../../core/models/medical_specialty_model.dart';
import '../../../../core/models/specialty_clinical_config.dart';
import '../../../../core/services/api_service.dart';
import '../../../../core/services/patient_problem_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../widgets/book_consultation_fab.dart';
import '../widgets/book_visit_flow_dialog.dart';
import 'doctor_profile_screen.dart';

/// Multi-specialty AI Health Triage screen.
/// Dynamically loads symptom categories, contextual triage guidance, emergency warnings,
/// and matching specialists for EVERY existing and future medical specialty.
class AiTriageScreen extends StatefulWidget {
  final String? initialSymptom;
  final String? initialSpecialty;
  final DoctorModel? initialDoctor;

  const AiTriageScreen({
    super.key,
    this.initialSymptom,
    this.initialSpecialty,
    this.initialDoctor,
  });

  @override
  State<AiTriageScreen> createState() => _AiTriageScreenState();
}

class _AiTriageScreenState extends State<AiTriageScreen> {
  final PatientProblemService _patientService = PatientProblemService();
  late final TextEditingController _symptomController;
  late final TextEditingController _specialtySearchController;

  late String _selectedSpecialty;
  String _specialtySearchQuery = '';
  DoctorModel? _selectedDoctor;
  late String _selectedCategory;
  String _selectedSeverity = 'Moderate';
  String _selectedDuration = '2-3 days';

  bool _isAnalyzing = false;
  bool _isSubmitting = false;
  bool _isLoadingDoctors = false;
  Map<String, dynamic>? _triageResult;
  List<DoctorModel> _matchingDoctors = [];

  final List<String> _severities = const ['Mild', 'Moderate', 'Severe'];
  final List<String> _durations = const ['< 24 hours', '2-3 days', '1-2 weeks', '> 2 weeks'];

  List<String> get _specialtyOptions => SpecialtyClinicalConfig.allSelectableSpecialties(
        activeSpecialties: _patientService.activeSpecialties,
        registeredDoctorSpecialties: _patientService.allDoctors.map((d) => d.specialty),
      );

  SpecialtyClinicalProfile get _activeProfile =>
      SpecialtyClinicalConfig.forSpecialty(_selectedSpecialty);

  List<String> get _categories => _activeProfile.triageCategories;

  @override
  void initState() {
    super.initState();
    _symptomController = TextEditingController(text: widget.initialSymptom ?? '');
    _specialtySearchController = TextEditingController();
    _selectedDoctor = (widget.initialDoctor != null &&
            _patientService.isDoctorCurrentlyBookable(widget.initialDoctor!))
        ? widget.initialDoctor
        : null;

    final seedSpecialty = widget.initialDoctor?.specialty.trim().isNotEmpty == true
        ? widget.initialDoctor!.specialty.trim()
        : (widget.initialSpecialty?.trim().isNotEmpty == true
            ? widget.initialSpecialty!.trim()
            : 'General Medicine');

    final resolvedProfile = SpecialtyClinicalConfig.forSpecialty(seedSpecialty);
    _selectedSpecialty = resolvedProfile.name;
    _selectedCategory = resolvedProfile.triageCategories.first;

    _patientService.addListener(_onServiceUpdated);
    _patientService.syncSpecialtiesFromApi();
    _refreshFilteredDoctorsForCurrentSelection(initialLoad: true);

    if ((widget.initialSymptom ?? '').trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _runAiTriageAnalysis();
      });
    }
  }

  @override
  void dispose() {
    _patientService.removeListener(_onServiceUpdated);
    _symptomController.dispose();
    _specialtySearchController.dispose();
    super.dispose();
  }

  void _onServiceUpdated() {
    if (!mounted) return;
    setState(() {
      if (_selectedDoctor != null) {
        final latest = _patientService.allDoctors
            .where((d) => d.id == _selectedDoctor!.id || (d.userId.isNotEmpty && d.userId == _selectedDoctor!.userId))
            .firstOrNull;
        if (latest == null || !_patientService.isDoctorCurrentlyBookable(latest)) {
          _selectedDoctor = null;
        } else {
          _selectedDoctor = latest;
        }
      }
    });
  }

  Future<void> _refreshFilteredDoctorsForCurrentSelection({bool initialLoad = false}) async {
    final hasLocalDoctors = _patientService.allDoctors.isNotEmpty;
    if (!hasLocalDoctors && mounted) {
      setState(() => _isLoadingDoctors = true);
    }
    try {
      await _patientService.syncDoctorsFromApi(includeUnavailable: false);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _isLoadingDoctors = false;
      if (_selectedDoctor != null) {
        final currentFiltered = _filteredDoctorsResult.doctors;
        if (!currentFiltered.any((d) => d.id == _selectedDoctor!.id)) {
          _selectedDoctor = null;
        }
      }
    });
  }

  void _onSpecialtySearchChanged(String rawQuery) {
    final query = rawQuery.trim();
    String? matchedOption;
    if (query.isNotEmpty) {
      final qLower = query.toLowerCase();
      for (final opt in _specialtyOptions) {
        if (opt.toLowerCase() == qLower) {
          matchedOption = opt;
          break;
        }
      }
      matchedOption ??= _specialtyOptions
          .where((opt) =>
              opt.toLowerCase().contains(qLower) ||
              MedicalSpecialtyModel.matchesSpecialtyFilter(opt, query, specialties: _patientService.specialties))
          .firstOrNull;
    }

    setState(() {
      _specialtySearchQuery = query;
      if (matchedOption != null && matchedOption != _selectedSpecialty) {
        final profile = SpecialtyClinicalConfig.forSpecialty(matchedOption);
        _selectedSpecialty = profile.name;
        _selectedCategory = profile.triageCategories.first;
        _triageResult = null;
        _matchingDoctors = [];
      }
      if (_selectedDoctor != null) {
        final currentDocs = _filteredDoctorsResult.doctors;
        if (!currentDocs.any((d) => d.id == _selectedDoctor!.id)) {
          _selectedDoctor = null;
        }
      }
    });
  }

  ({
    List<DoctorModel> doctors,
    bool usedGeneralMedicineFallback,
    String resolvedSpecialty,
  }) get _filteredDoctorsResult {
    return _patientService.getAvailableDoctorsForSpecialtyWithFallback(
      _selectedSpecialty,
      searchQuery: _specialtySearchQuery,
    );
  }

  void _onSpecialtyChanged(String newSpecialty, {bool keepSelectedDoctor = false}) {
    final profile = SpecialtyClinicalConfig.forSpecialty(newSpecialty);
    setState(() {
      _selectedSpecialty = profile.name;
      if (_specialtySearchQuery.isNotEmpty) {
        _specialtySearchQuery = '';
        _specialtySearchController.clear();
      }
      if (!keepSelectedDoctor && _selectedDoctor != null) {
        final nextDocs = _patientService
            .getAvailableDoctorsForSpecialtyWithFallback(profile.name)
            .doctors;
        if (!nextDocs.any((d) => d.id == _selectedDoctor!.id)) {
          _selectedDoctor = null;
        }
      }
      _selectedCategory = profile.triageCategories.first;
      _triageResult = null;
      _matchingDoctors = [];
    });
  }

  void _onDoctorSelected(DoctorModel? doc) {
    if (doc == null) {
      setState(() => _selectedDoctor = null);
      return;
    }
    if (!_patientService.isDoctorCurrentlyBookable(doc)) {
      setState(() => _selectedDoctor = null);
      return;
    }
    final resolved = SpecialtyClinicalConfig.forSpecialty(doc.specialty);
    setState(() {
      _selectedDoctor = doc;
      // Preserve selected specialty if General Medicine fallback doctor was chosen,
      // otherwise sync to the selected doctor's specialty.
      final currentFallback = _filteredDoctorsResult.usedGeneralMedicineFallback;
      if (!currentFallback) {
        _selectedSpecialty = resolved.name;
        _selectedCategory = resolved.triageCategories.first;
      }
      _triageResult = null;
      _matchingDoctors = [];
    });
  }

  List<DoctorModel> _resolveMatchingDoctorsForSpecialty(String specialtyName) {
    return _patientService
        .getAvailableDoctorsForSpecialtyWithFallback(
          specialtyName,
          searchQuery: _specialtySearchQuery,
        )
        .doctors;
  }

  Future<void> _runAiTriageAnalysis() async {
    final text = _symptomController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please describe your symptoms first.'),
          backgroundColor: AppTheme.gsRed,
        ),
      );
      return;
    }

    setState(() {
      _isAnalyzing = true;
    });

    // Try authoritative backend multi-specialty triage API first, with seamless local fallback
    Map<String, dynamic>? backendData;
    try {
      backendData = await ApiService().analyzeAiTriage(
        specialty: _selectedSpecialty,
        doctorId: _selectedDoctor?.id,
        category: _selectedCategory,
        symptoms: text,
        severity: _selectedSeverity,
        duration: _selectedDuration,
      );
    } catch (_) {}

    if (!mounted) return;

    final Map<String, dynamic> triage = (backendData?['triage'] is Map<String, dynamic>)
        ? Map<String, dynamic>.from(backendData!['triage'] as Map)
        : SpecialtyClinicalConfig.analyzeLocally(
            specialty: _selectedSpecialty,
            category: _selectedCategory,
            symptoms: text,
            severity: _selectedSeverity,
            duration: _selectedDuration,
          );

    final urgencyLevel = (triage['urgencyLevel'] ?? 'Routine').toString();
    final isEmergency = triage['isEmergency'] == true || urgencyLevel.toLowerCase() == 'emergency';
    final Color urgencyColor = (isEmergency || urgencyLevel.toLowerCase() == 'urgent' || urgencyLevel.toLowerCase() == 'soon')
        ? AppTheme.gsRed
        : AppTheme.gsNavy;

    final matchedLocal = _resolveMatchingDoctorsForSpecialty(
      (triage['recommendedSpecialty'] ?? _selectedSpecialty).toString(),
    );

    setState(() {
      _isAnalyzing = false;
      _matchingDoctors = matchedLocal;
      _triageResult = {
        'urgency': (triage['urgency'] ?? 'Specialist Consultation Recommended').toString(),
        'urgencyLevel': urgencyLevel,
        'urgencyColor': urgencyColor,
        'isEmergency': isEmergency,
        'condition': (triage['clinicalSummary'] ??
                'Preliminary symptom guidance for $_selectedSpecialty ($_selectedCategory).')
            .toString(),
        'specialist': (triage['recommendedSpecialty'] ?? _selectedSpecialty).toString(),
        'homeCare': (triage['selfCareGuidance'] ?? _activeProfile.selfCareGuidance).toString(),
        'warning': (triage['emergencyWarning'] ?? _activeProfile.emergencyWarning).toString(),
        'disclaimer': (triage['disclaimer'] ??
                'Informational triage guidance only — this is NOT a medical diagnosis. Please consult a qualified doctor.')
            .toString(),
      };
    });
  }

  Future<void> _handleConfirmAndConnect() async {
    final text = _symptomController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please describe your symptoms.'),
          backgroundColor: AppTheme.gsRed,
        ),
      );
      return;
    }

    if (_isSubmitting) return;

    setState(() {
      _isSubmitting = true;
    });

    try {
      await _patientService.submitProblem(
        specialty: _selectedSpecialty,
        problemCategory: '$_selectedSpecialty — $_selectedCategory',
        problemDescription: text,
        severity: _selectedSeverity,
        symptoms:
            'Specialty: $_selectedSpecialty • Category: $_selectedCategory • Duration: $_selectedDuration • Urgency: ${_triageResult?['urgencyLevel'] ?? _selectedSeverity}',
        preferredDoctorId: _selectedDoctor?.id,
        preferredDoctorName: _selectedDoctor?.name,
        preferredDoctorClinic: _selectedDoctor?.clinicName,
      );

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppTheme.gsNavy.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle_rounded, color: AppTheme.gsNavy, size: 36),
              ),
              const SizedBox(height: 16),
              const Text(
                'Triage Request Submitted',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Your $_selectedSpecialty triage report ($_selectedCategory) has been shared with our clinical team${_selectedDoctor != null ? ' and ${_selectedDoctor!.name}' : ''}.',
                style: const TextStyle(fontSize: 13, color: Color(0xFF64748B), height: 1.4),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  key: const Key('ai_triage_dialog_done_button'),
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    Navigator.of(context).pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.gsNavy,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Back to Dashboard', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Submission failed: $e'), backgroundColor: AppTheme.gsRed),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final specialtyOptions = _specialtyOptions;
    final effectiveSpecialty = specialtyOptions.contains(_selectedSpecialty)
        ? _selectedSpecialty
        : (specialtyOptions.isNotEmpty ? specialtyOptions.first : 'General Medicine');
    final categories = _categories;
    final effectiveCategory = categories.contains(_selectedCategory)
        ? _selectedCategory
        : categories.first;
    final filteredDoctorsOutcome = _filteredDoctorsResult;
    final doctorsList = filteredDoctorsOutcome.doctors;
    final usedGeneralMedicineFallback = filteredDoctorsOutcome.usedGeneralMedicineFallback;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 104),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Intro banner (preserves exact GS HEALTH Navy card design)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.gsNavy,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Center(
                              child: Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 24),
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'AI Clinical Triage',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Select a medical specialty, describe what you feel, and get multi-specialty triage guidance.',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                    height: 1.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // 1. Dynamic Medical Specialty Selector
                    const Text(
                      'MEDICAL SPECIALTY',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF64748B),
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          key: const Key('ai_triage_specialty_dropdown'),
                          value: effectiveSpecialty,
                          isExpanded: true,
                          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF64748B)),
                          items: specialtyOptions.map((spec) {
                            return DropdownMenuItem<String>(
                              value: spec,
                              child: Text(
                                spec,
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) _onSpecialtyChanged(val);
                          },
                        ),
                      ),
                    ),

                    // Optional Specific Doctor Selector (filtered strictly by selected specialization + availability + General Medicine fallback)
                    const SizedBox(height: 14),
                    const Text(
                      'OR SELECT A SPECIFIC DOCTOR (AUTO-DETECTS SPECIALTY)',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF64748B),
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: TextField(
                        key: const Key('ai_triage_specialty_search_input'),
                        controller: _specialtySearchController,
                        onChanged: _onSpecialtySearchChanged,
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: Color(0xFF0F172A)),
                        decoration: InputDecoration(
                          hintText: 'Search specialization or doctor (e.g. Cardiology, Neurology)...',
                          hintStyle: const TextStyle(fontSize: 12.5, color: Color(0xFF94A3B8)),
                          prefixIcon: const Icon(Icons.search_rounded, size: 18, color: Color(0xFF64748B)),
                          suffixIcon: _specialtySearchQuery.isNotEmpty
                              ? IconButton(
                                  key: const Key('ai_triage_specialty_search_clear'),
                                  icon: const Icon(Icons.close_rounded, size: 16, color: Color(0xFF64748B)),
                                  onPressed: () {
                                    _specialtySearchController.clear();
                                    _onSpecialtySearchChanged('');
                                  },
                                )
                              : null,
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_isLoadingDoctors)
                      Container(
                        key: const Key('ai_triage_doctors_loading_indicator'),
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: const Row(
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.gsNavy),
                            ),
                            SizedBox(width: 10),
                            Flexible(
                              child: Text(
                                'Loading available doctors...',
                                style: TextStyle(fontSize: 13, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      )
                    else if (doctorsList.isEmpty)
                      Container(
                        key: const Key('ai_triage_no_available_doctors_message'),
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.info_outline_rounded, size: 18, color: Color(0xFF64748B)),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'No available doctors found for this specialization. Please try again later.',
                                style: TextStyle(fontSize: 13, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                              ),
                            ),
                          ],
                        ),
                      )
                    else ...[
                      if (usedGeneralMedicineFallback)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            'No available $effectiveSpecialty specialists right now — showing available General Medicine doctors.',
                            key: const Key('ai_triage_general_medicine_fallback_notice'),
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.gsNavy,
                            ),
                          ),
                        ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            key: const Key('ai_triage_doctor_dropdown'),
                            value: (_selectedDoctor != null && doctorsList.any((d) => d.id == _selectedDoctor!.id))
                                ? _selectedDoctor!.id
                                : '',
                            isExpanded: true,
                            icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF64748B)),
                            items: [
                              const DropdownMenuItem<String>(
                                value: '',
                                child: Text(
                                  'Any Specialist in Selected Department',
                                  style: TextStyle(fontSize: 13.5, color: Color(0xFF64748B)),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              ...doctorsList.map((doc) {
                                return DropdownMenuItem<String>(
                                  value: doc.id,
                                  child: Text(
                                    '${doc.name} · ${doc.specialty}',
                                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                );
                              }),
                            ],
                            onChanged: (docId) {
                              if (docId == null || docId.isEmpty) {
                                _onDoctorSelected(null);
                              } else {
                                final match = doctorsList.firstWhere((d) => d.id == docId);
                                _onDoctorSelected(match);
                              }
                            },
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),

                    // 2. Specialty-Contextual Symptom Description
                    const Text(
                      'DESCRIBE YOUR SYMPTOMS',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF64748B),
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: TextField(
                        key: const Key('ai_triage_symptom_input'),
                        controller: _symptomController,
                        maxLines: 4,
                        minLines: 3,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF0F172A),
                        ),
                        decoration: InputDecoration(
                          hintText: _activeProfile.symptomHint,
                          hintStyle: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF94A3B8),
                            fontWeight: FontWeight.w400,
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.all(14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // 3. Dynamic Specialty-Based Issue Category
                    const Text(
                      'ISSUE CATEGORY',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF64748B),
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          key: const Key('ai_triage_category_dropdown'),
                          value: effectiveCategory,
                          isExpanded: true,
                          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF64748B)),
                          items: categories.map((cat) {
                            return DropdownMenuItem<String>(
                              value: cat,
                              child: Text(
                                cat,
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF0F172A)),
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) setState(() => _selectedCategory = val);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // 4. Symptom Severity Level
                    const Text(
                      'SYMPTOM SEVERITY LEVEL',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF64748B),
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: _severities.map((sev) {
                        final isSelected = _selectedSeverity == sev;
                        final color = sev == 'Severe'
                            ? AppTheme.gsRed
                            : (sev == 'Moderate' ? AppTheme.gsRed : AppTheme.gsNavy);
                        return Expanded(
                          child: InkWell(
                            key: Key('ai_triage_severity_$sev'),
                            onTap: () => setState(() => _selectedSeverity = sev),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              margin: EdgeInsets.only(right: sev != _severities.last ? 8 : 0),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: isSelected ? color.withValues(alpha: 0.12) : Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected ? color : const Color(0xFFE2E8F0),
                                  width: isSelected ? 1.8 : 1.0,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  sev,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                    color: isSelected ? color : const Color(0xFF64748B),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 18),

                    // 5. Duration
                    const Text(
                      'HOW LONG HAVE YOU HAD THIS?',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF64748B),
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _durations.map((dur) {
                        final isSelected = _selectedDuration == dur;
                        return InkWell(
                          key: Key('ai_triage_duration_$dur'),
                          onTap: () => setState(() => _selectedDuration = dur),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: isSelected ? AppTheme.gsNavy.withValues(alpha: 0.1) : Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isSelected ? AppTheme.gsNavy : const Color(0xFFE2E8F0),
                                width: isSelected ? 1.6 : 1.0,
                              ),
                            ),
                            child: Text(
                              dur,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                color: isSelected ? AppTheme.gsNavy : const Color(0xFF64748B),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 22),

                    // Analyze button
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        key: const Key('ai_triage_run_button'),
                        onPressed: _isAnalyzing ? null : _runAiTriageAnalysis,
                        icon: _isAnalyzing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                              )
                            : const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 20),
                        label: Text(
                          _isAnalyzing ? 'Analyzing symptoms...' : 'Run AI Assessment',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.gsNavy,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // AI Assessment Result Card
                    if (_triageResult != null) ...[
                      Container(
                        key: const Key('ai_triage_result_card'),
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.03),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: (_triageResult!['urgencyColor'] as Color).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: _triageResult!['urgencyColor'] as Color,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        _triageResult!['urgency'].toString(),
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: _triageResult!['urgencyColor'] as Color,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              'PRELIMINARY TRIAGE GUIDANCE (NOT A DIAGNOSIS)',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _triageResult!['condition'].toString(),
                              style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A), height: 1.35),
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              'RECOMMENDED SPECIALIST DEPARTMENT',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _triageResult!['specialist'].toString(),
                              style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppTheme.gsNavy),
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              'SAFE PRE-CONSULTATION GUIDANCE',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _triageResult!['homeCare'].toString(),
                              style: const TextStyle(fontSize: 13, color: Color(0xFF334155), height: 1.4),
                            ),
                            const SizedBox(height: 14),
                            Container(
                              key: const Key('ai_triage_emergency_warning'),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0x14FE3434),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0x40FE3434)),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.warning_amber_rounded, color: AppTheme.gsRed, size: 18),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _triageResult!['warning'].toString(),
                                      style: const TextStyle(fontSize: 12, color: AppTheme.gsRed, height: 1.35, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _triageResult!['disclaimer'].toString(),
                              style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontStyle: FontStyle.italic),
                            ),

                            // Suitable Specialists for Selected Specialty
                            if (_matchingDoctors.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              Text(
                                'SUITABLE ${_selectedSpecialty.toUpperCase()} SPECIALISTS (${_matchingDoctors.length})',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
                              ),
                              const SizedBox(height: 8),
                              ..._matchingDoctors.take(4).map((doc) {
                                return Container(
                                  key: Key('ai_triage_doctor_card_${doc.id}'),
                                  margin: const EdgeInsets.only(bottom: 8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: const Color(0xFFE2E8F0)),
                                  ),
                                  child: ListTile(
                                    dense: true,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                                    leading: CircleAvatar(
                                      backgroundColor: AppTheme.gsNavy,
                                      radius: 18,
                                      child: Text(
                                        doc.name.replaceFirst(RegExp(r'^Dr\.?\s*', caseSensitive: false), '').isNotEmpty
                                            ? doc.name.replaceFirst(RegExp(r'^Dr\.?\s*', caseSensitive: false), '')[0].toUpperCase()
                                            : 'D',
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                      ),
                                    ),
                                    title: Text(
                                      doc.name,
                                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppTheme.textDark),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Text(
                                      '${doc.specialty}${doc.clinicName.isNotEmpty ? " · ${doc.clinicName}" : ""}',
                                      style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    trailing: TextButton(
                                      onPressed: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => DoctorProfileScreen(doctor: doc),
                                          ),
                                        );
                                      },
                                      child: const Text(
                                        'View',
                                        style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.gsNavy, fontSize: 12),
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ],

                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              height: 48,
                              child: ElevatedButton.icon(
                                key: const Key('ai_triage_confirm_button'),
                                onPressed: _isSubmitting ? null : _handleConfirmAndConnect,
                                icon: _isSubmitting
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                      )
                                    : const Icon(Icons.health_and_safety_rounded, color: Colors.white, size: 18),
                                label: Text(
                                  _isSubmitting ? 'Submitting Triage...' : 'Submit Triage & Request Doctor',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.gsRed,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  elevation: 0,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          color: const Color(0xFFF8FAFC),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Flexible(
                child: BookConsultationFab(
                  selectedSpecialty: _selectedSpecialty,
                  onPressed: () => BookVisitFlowDialog.show(
                    context,
                    preselectedDoctor: _selectedDoctor,
                    initialSpecialtyFilter: _selectedSpecialty,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          InkWell(
            key: const Key('ai_triage_back_button'),
            onTap: () => Navigator.of(context).pop(),
            borderRadius: BorderRadius.circular(22),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Center(
                child: Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: Color(0xFF0F172A)),
              ),
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'GS HEALTH Clinical Assistant',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF64748B),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 2),
                Text(
                  'AI Health Triage',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                    letterSpacing: -0.3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
