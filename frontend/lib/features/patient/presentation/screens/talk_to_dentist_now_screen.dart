import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/services/patient_problem_service.dart';
import 'ai_triage_screen.dart';

/// Screen allowing patients to instantly connect with an online dentist matching their language.
class TalkToDentistNowScreen extends StatefulWidget {
  const TalkToDentistNowScreen({super.key});

  @override
  State<TalkToDentistNowScreen> createState() => _TalkToDentistNowScreenState();
}

class _TalkToDentistNowScreenState extends State<TalkToDentistNowScreen> {
  final PatientProblemService _patientService = PatientProblemService();
  final TextEditingController _concernController = TextEditingController();
  final FocusNode _concernFocusNode = FocusNode();

  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _patientService.syncDoctorsFromApi();
    _patientService.syncMyDoctorsFromApi();
  }

  @override
  void dispose() {
    _concernController.dispose();
    _concernFocusNode.dispose();
    super.dispose();
  }

  List<DoctorModel> _getOnlineDentists() {
    return _patientService.allDoctors.where((d) {
      final status = d.status.trim().toLowerCase();
      final isOnline = status == 'available' || status == 'online';
      final isVerified = d.verificationStatus.toUpperCase() != 'REJECTED' &&
          d.verificationStatus.toUpperCase() != 'SUSPENDED';
      return isOnline && isVerified;
    }).toList();
  }

  DoctorModel? _matchOnlineDentist(List<DoctorModel> onlineDentists) {
    if (onlineDentists.isEmpty) return null;

    final patientLangs = _patientService.currentPatient.languages
        .map((l) => l.trim().toLowerCase())
        .where((l) => l.isNotEmpty)
        .toSet();

    // 1. Filter dentists who speak at least one of the patient's languages
    final matchingLangDoctors = onlineDentists.where((doc) {
      final docLangs = doc.languages.map((l) => l.trim().toLowerCase()).toSet();
      return patientLangs.any((pl) => docLangs.contains(pl));
    }).toList();

    if (matchingLangDoctors.isNotEmpty) {
      // 2. If multiple dentists speak the patient's language, prefer same city
      final patientCity = _patientService.currentPatient.city.trim().toLowerCase();
      if (patientCity.isNotEmpty) {
        final cityMatch = matchingLangDoctors.where((d) {
          final c = d.city.trim().toLowerCase();
          return c.isNotEmpty && (c == patientCity || patientCity.contains(c));
        }).toList();

        if (cityMatch.isNotEmpty) {
          cityMatch.sort((a, b) => b.rating.compareTo(a.rating));
          return cityMatch.first;
        }
      }
      matchingLangDoctors.sort((a, b) => b.rating.compareTo(a.rating));
      return matchingLangDoctors.first;
    }

    // 3. Fallback to highest rated online dentist
    final sorted = List<DoctorModel>.from(onlineDentists)..sort((a, b) => b.rating.compareTo(a.rating));
    return sorted.first;
  }

  Future<void> _handleConnectNow() async {
    FocusManager.instance.primaryFocus?.unfocus();

    // Guard against duplicate submissions
    if (_isSubmitting) return;

    final concern = _concernController.text.trim();
    if (concern.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please describe what\'s bothering you before connecting.'),
          backgroundColor: AppTheme.gsRed,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    final onlineDentists = _getOnlineDentists();

    if (onlineDentists.isEmpty) {
      _showNoDentistsDialog(concern);
      return;
    }

    final matchedDoctor = _matchOnlineDentist(onlineDentists)!;

    setState(() {
      _isSubmitting = true;
    });

    try {
      await _patientService.submitProblem(
        problemCategory: 'Immediate Consultation',
        problemDescription: concern,
        severity: 'Moderate',
        symptoms: 'Online Match: ${matchedDoctor.languages.join(", ")}',
        preferredDoctorId: matchedDoctor.id,
        preferredDoctorName: matchedDoctor.name,
        preferredDoctorClinic: matchedDoctor.clinicName.isNotEmpty
            ? matchedDoctor.clinicName
            : 'GS HEALTH Clinic',
      );

      if (!mounted) return;

      _showConnectedDialog(matchedDoctor);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit consultation request: $e'),
            backgroundColor: AppTheme.gsRed,
          ),
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

  void _showConnectedDialog(DoctorModel doctor) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: const Color(0xFF012A58).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.bolt_rounded,
                color: Color(0xFF012A58),
                size: 34,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Matched & Connected!',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              'You have been connected with ${doctor.name} (${doctor.specialty}).',
              style: const TextStyle(
                fontSize: 13.5,
                color: Color(0xFF475569),
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.translate_rounded, size: 14, color: AppTheme.gsNavy),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Languages: ${doctor.languages.join(", ")}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.gsNavy),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                key: const Key('talk_to_dentist_dialog_done_button'),
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
  }

  void _showNoDentistsDialog(String concern) {
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
              decoration: const BoxDecoration(
                color: Color(0xFFF1F5F9),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.nightlight_round, color: Color(0xFF64748B), size: 28),
            ),
            const SizedBox(height: 14),
            const Text(
              'No Doctors Online',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'All doctors are currently offline. You can run AI triage to evaluate your symptoms instantly, or queue your request for the next available doctor.',
              style: TextStyle(fontSize: 13, color: Color(0xFF64748B), height: 1.4),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                key: const Key('talk_to_dentist_no_dentists_ai_button'),
                icon: const Icon(Icons.auto_awesome_rounded, size: 16, color: Colors.white),
                label: const Text('Try AI Triage Now', style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.gsNavy,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AiTriageScreen(initialSymptom: concern),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                key: const Key('talk_to_dentist_no_dentists_queue_button'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.gsNavy,
                  side: const BorderSide(color: Color(0xFFCBD5E1)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: () async {
                  Navigator.of(ctx).pop();
                  setState(() => _isSubmitting = true);
                  try {
                    await _patientService.submitProblem(
                      problemCategory: 'General Consultation',
                      problemDescription: concern,
                      severity: 'Moderate',
                      symptoms: 'Queued consultation request (no online doctors)',
                    );
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Your request has been queued. Our clinical team will reach out promptly.'),
                          backgroundColor: Color(0xFF012A58),
                        ),
                      );
                      Navigator.of(context).pop();
                    }
                  } finally {
                    if (mounted) setState(() => _isSubmitting = false);
                  }
                },
                child: const Text('Queue Request for Later', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToAiTriage() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AiTriageScreen(
          initialSymptom: _concernController.text.trim(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _patientService,
      builder: (context, _) {
        final onlineDentists = _getOnlineDentists();
        final hasOnlineDentists = onlineDentists.isNotEmpty;

        return Scaffold(
          backgroundColor: const Color(0xFFF8FAFC),
          body: SafeArea(
            child: Column(
              children: [
                // 1. Header with back button, dynamic matched languages, and title
                _buildHeader(context),

                // 2. Scrollable content
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Online dentist availability card
                        _buildAvailabilityCard(hasOnlineDentists, onlineDentists.length),
                        const SizedBox(height: 24),

                        // Section label: WHAT'S BOTHERING YOU?
                        const Text(
                          "WHAT'S BOTHERING YOU?",
                          key: Key('talk_to_dentist_concern_label'),
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF64748B),
                            letterSpacing: 0.6,
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Multiline text input
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: TextField(
                            key: const Key('talk_to_dentist_concern_input'),
                            controller: _concernController,
                            focusNode: _concernFocusNode,
                            maxLines: 5,
                            minLines: 4,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF0F172A),
                            ),
                            decoration: const InputDecoration(
                              hintText: 'e.g. Sharp pain in lower left tooth for 3 days',
                              hintStyle: TextStyle(
                                fontSize: 14.5,
                                color: Color(0xFF94A3B8),
                                fontWeight: FontWeight.w400,
                              ),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.all(16),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Primary Action Button: ⚡ Connect me now
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            key: const Key('talk_to_dentist_connect_button'),
                            onPressed: _isSubmitting ? null : _handleConnectNow,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.gsNavy,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: AppTheme.gsNavy.withValues(alpha: 0.6),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              elevation: 0,
                            ),
                            child: _isSubmitting
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2.2,
                                    ),
                                  )
                                : const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.bolt_rounded,
                                        color: Colors.white,
                                        size: 22,
                                      ),
                                      SizedBox(width: 8),
                                      Flexible(
                                        child: Text(
                                          'Connect me now',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Secondary Action Button: ✦ Not sure? Try AI triage first
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: OutlinedButton(
                            key: const Key('talk_to_dentist_ai_triage_button'),
                            onPressed: _navigateToAiTriage,
                            style: OutlinedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: const Color(0xFF0F172A),
                              side: const BorderSide(
                                color: Color(0xFFE2E8F0),
                                width: 1.5,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.auto_awesome_rounded,
                                  color: Color(0xFF0F172A),
                                  size: 18,
                                ),
                                SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    'Not sure? Try AI triage first',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF0F172A),
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    final patient = _patientService.currentPatient;
    final langs = patient.languages.where((l) => l.trim().isNotEmpty).toList();
    final matchedBy = langs.isNotEmpty
        ? 'Matched by ${langs.join(' / ')}'
        : 'Matched by English / Hindi / Telugu';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Circular back button
          InkWell(
            key: const Key('talk_to_dentist_back_button'),
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
                child: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: 16,
                  color: Color(0xFF0F172A),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          // Subtitle and Main Title
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  matchedBy,
                  key: const Key('talk_to_dentist_matched_languages'),
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF64748B),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                const Text(
                  'Talk to a doctor now',
                  key: Key('talk_to_dentist_title'),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                    letterSpacing: -0.4,
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

  Widget _buildAvailabilityCard(bool hasOnlineDentists, int onlineCount) {
    return Container(
      key: const Key('talk_to_dentist_availability_card'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFE2E8F0),
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          Container(
            key: const Key('dentist_availability_dot'),
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: hasOnlineDentists ? const Color(0xFF012A58) : const Color(0xFF64748B),
              shape: BoxShape.circle,
              boxShadow: hasOnlineDentists
                  ? [
                      BoxShadow(
                        color: const Color(0xFF012A58).withValues(alpha: 0.45),
                        blurRadius: 4,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              hasOnlineDentists
                  ? '$onlineCount doctor${onlineCount > 1 ? "s" : ""} online right now'
                  : 'No doctors online right now',
              key: const Key('talk_to_dentist_availability_text'),
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1E293B),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
