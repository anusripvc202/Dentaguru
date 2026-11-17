import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/services/patient_problem_service.dart';

/// Screen providing interactive AI dental symptom triage and specialist matching.
class AiTriageScreen extends StatefulWidget {
  final String? initialSymptom;

  const AiTriageScreen({
    super.key,
    this.initialSymptom,
  });

  @override
  State<AiTriageScreen> createState() => _AiTriageScreenState();
}

class _AiTriageScreenState extends State<AiTriageScreen> {
  final PatientProblemService _patientService = PatientProblemService();
  late final TextEditingController _symptomController;

  String _selectedCategory = 'Toothache & Sensitivity';
  String _selectedSeverity = 'Moderate';
  String _selectedDuration = '2-3 days';

  bool _isAnalyzing = false;
  bool _isSubmitting = false;
  Map<String, dynamic>? _triageResult;

  final List<String> _categories = [
    'Toothache & Sensitivity',
    'Swollen or Bleeding Gums',
    'Broken or Chipped Tooth',
    'Wisdom Tooth Pain',
    'Aligners & Orthodontics',
    'Jaw Pain or Clicking',
    'Routine Checkup & Cleaning',
  ];

  final List<String> _severities = ['Mild', 'Moderate', 'Severe'];
  final List<String> _durations = ['< 24 hours', '2-3 days', '1-2 weeks', '> 2 weeks'];

  @override
  void initState() {
    super.initState();
    _symptomController = TextEditingController(text: widget.initialSymptom ?? '');
    if ((widget.initialSymptom ?? '').trim().isNotEmpty) {
      _runAiTriageAnalysis();
    }
  }

  @override
  void dispose() {
    _symptomController.dispose();
    super.dispose();
  }

  void _runAiTriageAnalysis() {
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

    // Generate clinical triage analysis based on user inputs
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted) return;

      final lower = text.toLowerCase();
      String urgency;
      Color urgencyColor;
      String condition;
      String specialist;
      String homeCare;
      String warning;

      if (_selectedSeverity == 'Severe' ||
          lower.contains('swelling') ||
          lower.contains('fever') ||
          lower.contains('unbearable') ||
          lower.contains('bleed')) {
        urgency = 'Immediate Care Recommended (< 24 hrs)';
        urgencyColor = AppTheme.gsRed;
        condition = 'Acute Medical Emergency / Severe Inflammation';
        specialist = 'Endodontist or Oral Surgeon';
        homeCare = 'Apply cold compress externally. Do not place hot compresses or aspirin on gums.';
        warning = 'If you experience difficulty swallowing, breathing, or rapid facial swelling, visit urgent care immediately.';
      } else if (_selectedSeverity == 'Moderate' ||
          lower.contains('sharp') ||
          lower.contains('pain') ||
          lower.contains('cold') ||
          lower.contains('hot')) {
        urgency = 'Consultation Recommended within 48-72 hrs';
        urgencyColor = const Color(0xFFF59E0B);
        condition = 'Suspected Dental Pulpitis or Enamel Decay';
        specialist = 'General Dentist or Endodontist';
        homeCare = 'Rinse gently with warm salt water. Avoid extreme hot/cold foods and chewing on this side.';
        warning = 'Untreated tooth decay can advance quickly to the dental pulp causing intense pain.';
      } else {
        urgency = 'Routine Evaluation Suggested';
        urgencyColor = const Color(0xFF10B981);
        condition = 'Mild Enamel Sensitivity or Early Gingival Irritation';
        specialist = 'General Dentist';
        homeCare = 'Maintain gentle brushing with a soft-bristled toothbrush and desensitizing toothpaste.';
        warning = 'Schedule a preventative exam to keep minor sensitivity from developing into a cavity.';
      }

      setState(() {
        _isAnalyzing = false;
        _triageResult = {
          'urgency': urgency,
          'urgencyColor': urgencyColor,
          'condition': condition,
          'specialist': specialist,
          'homeCare': homeCare,
          'warning': warning,
        };
      });
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
        problemCategory: _selectedCategory,
        problemDescription: text,
        severity: _selectedSeverity,
        symptoms: 'Duration: $_selectedDuration • AI Triage: ${_triageResult?['condition'] ?? "Evaluated"}',
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
                  color: const Color(0xFF10B981).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 36),
              ),
              const SizedBox(height: 16),
              const Text(
                'Triage Request Submitted',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Our clinical coordination team and matching specialists have received your triage report. We will connect you shortly.',
                style: TextStyle(fontSize: 13, color: Color(0xFF64748B), height: 1.4),
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
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Intro banner
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
                                  'Describe what you feel and get clinical insights in seconds.',
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

                    // Symptom input
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
                        decoration: const InputDecoration(
                          hintText: 'e.g. Throbbing pain on the lower left side when chewing or having cold drinks...',
                          hintStyle: TextStyle(
                            fontSize: 14,
                            color: Color(0xFF94A3B8),
                            fontWeight: FontWeight.w400,
                          ),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.all(14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Category
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
                          value: _selectedCategory,
                          isExpanded: true,
                          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF64748B)),
                          items: _categories.map((cat) {
                            return DropdownMenuItem(
                              value: cat,
                              child: Text(
                                cat,
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF0F172A)),
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

                    // Pain Severity
                    const Text(
                      'PAIN SEVERITY LEVEL',
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
                            : (sev == 'Moderate' ? const Color(0xFFF59E0B) : const Color(0xFF10B981));
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

                    // Duration
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
                                        _triageResult!['urgency'],
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
                              'POTENTIAL CONDITION',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _triageResult!['condition'],
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              'RECOMMENDED SPECIALIST',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _triageResult!['specialist'],
                              style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: AppTheme.gsNavy),
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              'IMMEDIATE HOME CARE TIP',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _triageResult!['homeCare'],
                              style: const TextStyle(fontSize: 13, color: Color(0xFF334155), height: 1.4),
                            ),
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFFBEB),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFFFDE68A)),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.info_outline_rounded, color: Color(0xFFB45309), size: 18),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _triageResult!['warning'],
                                      style: const TextStyle(fontSize: 12, color: Color(0xFF92400E), height: 1.35),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 18),
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
