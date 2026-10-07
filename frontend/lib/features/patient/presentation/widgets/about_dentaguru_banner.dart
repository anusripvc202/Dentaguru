import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';

class AboutDentaGuruBanner extends StatefulWidget {
  final VoidCallback? onBookConsultation;
  final VoidCallback? onViewPrescriptions;
  final VoidCallback? onViewRecords;

  const AboutDentaGuruBanner({
    super.key,
    this.onBookConsultation,
    this.onViewPrescriptions,
    this.onViewRecords,
  });

  @override
  State<AboutDentaGuruBanner> createState() => _AboutDentaGuruBannerState();
}

class _AboutDentaGuruBannerState extends State<AboutDentaGuruBanner> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  Timer? _autoSlideTimer;

  final List<Map<String, dynamic>> _slides = [
    {
      'badge': '✨ What is DentaGuru?',
      'title': 'Your Smart Digital Dental Healthcare Platform',
      'description':
          'DentaGuru connects you with accredited dental clinics and specialists. Report symptoms, get instant e-prescriptions, and manage your oral health with complete peace of mind.',
      'chips': ['🏥 Verified Clinics', '⚡ Fast Diagnosis', '🛡️ Safe Care'],
      'gradient': [const Color(0xFF0F172A), const Color(0xFF0052CC)],
      'icon': Icons.health_and_safety_rounded,
      'ctaText': 'How DentaGuru Works',
      'ctaIcon': Icons.info_outline_rounded,
      'type': 'how_it_works',
    },
    {
      'badge': '🧑‍⚕️ Specialized Care',
      'title': 'Connect with Top Verified Dental Specialists',
      'description':
          'From root canal therapy & aligners to implants and smile designing, get paired with the right experienced dental surgeon in your area.',
      'chips': ['🦷 Root Canal (Endo)', '💎 Braces & Aligners', '⚙️ Implants'],
      'gradient': [const Color(0xFF0F766E), const Color(0xFF0284C7)],
      'icon': Icons.verified_user_rounded,
      'ctaText': 'Book a Specialist',
      'ctaIcon': Icons.calendar_month_rounded,
      'type': 'book',
    },
    {
      'badge': '📝 100% Digital Records',
      'title': 'Instant E-Prescriptions & Treatment Timeline',
      'description':
          'Never lose a paper prescription again. Access clinical notes, precise dosage instructions, and complete treatment history on your phone 24/7.',
      'chips': ['🔒 Cloud Encrypted', '📲 Mobile Access', '💊 Clear Dosages'],
      'gradient': [const Color(0xFF1E1B4B), const Color(0xFF7C3AED)],
      'icon': Icons.receipt_long_rounded,
      'ctaText': 'View My Records',
      'ctaIcon': Icons.folder_shared_rounded,
      'type': 'records',
    },
  ];

  @override
  void initState() {
    super.initState();
    _startAutoSlide();
  }

  void _startAutoSlide() {
    _autoSlideTimer?.cancel();
    _autoSlideTimer = Timer.periodic(const Duration(seconds: 6), (timer) {
      if (!mounted) return;
      final nextPage = (_currentPage + 1) % _slides.length;
      _pageController.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _autoSlideTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _handleCtaAction(String type) {
    if (type == 'book') {
      widget.onBookConsultation?.call();
    } else if (type == 'records') {
      widget.onViewRecords?.call();
    } else {
      _showAboutDentaGuruSheet(context);
    }
  }

  void _showAboutDentaGuruSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Drag Handle
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Scrollable Details
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  children: [
                    // Header Banner
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF0F172A), Color(0xFF0052CC)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF0052CC).withValues(alpha: 0.25),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(Icons.health_and_safety_rounded, color: Colors.white, size: 28),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'About DentaGuru',
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  'India\'s Integrated Digital Dental Care Network',
                                  style: TextStyle(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.85)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Intro Paragraph
                    const Text(
                      'DentaGuru is designed to simplify oral healthcare for patients. We bridge the gap between patients, verified dental clinics, and specialized practitioners — providing quick symptom diagnosis, transparent treatment tracking, and certified e-prescriptions.',
                      style: TextStyle(fontSize: 13, height: 1.5, color: Color(0xFF334155), fontWeight: FontWeight.w400),
                    ),
                    const SizedBox(height: 20),

                    // Section: 3-Step Process
                    const Text(
                      'How It Works in 3 Simple Steps',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                    ),
                    const SizedBox(height: 12),

                    _buildStepCard(
                      stepNumber: '1',
                      title: 'Report Your Dental Concern',
                      description:
                          'Select your symptoms (toothache, aligners, gums, implant consultation) and optionally attach photos.',
                      icon: Icons.edit_note_rounded,
                      color: const Color(0xFF0284C7),
                    ),
                    const SizedBox(height: 10),
                    _buildStepCard(
                      stepNumber: '2',
                      title: 'Matched with Specialized Dentist',
                      description:
                          'A verified attending dentist evaluates your problem, recommends specialized treatment, or confirms a consultation slot.',
                      icon: Icons.person_search_rounded,
                      color: const Color(0xFF0D9488),
                    ),
                    const SizedBox(height: 10),
                    _buildStepCard(
                      stepNumber: '3',
                      title: 'Get Treated & Track Digital Rx',
                      description:
                          'Visit the accredited clinic, receive digital prescriptions with automated reminders, and maintain your dental history on your phone.',
                      icon: Icons.verified_rounded,
                      color: const Color(0xFF10B981),
                    ),
                    const SizedBox(height: 20),

                    // Section: Key Patient Benefits
                    const Text(
                      'Why Patients Trust DentaGuru',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                    ),
                    const SizedBox(height: 12),

                    _buildBenefitItem(
                      icon: Icons.verified_user_rounded,
                      title: 'Verified & Licensed Practitioners',
                      description: 'All registered dentists are vetted with valid Dental Council license numbers and clinic accreditations.',
                    ),
                    _buildBenefitItem(
                      icon: Icons.receipt_long_rounded,
                      title: 'Paperless E-Prescription Slips',
                      description: 'Doctors issue authentic digital prescriptions with clear dosage, frequency, and care instructions.',
                    ),
                    _buildBenefitItem(
                      icon: Icons.history_edu_rounded,
                      title: 'Lifetime Dental Health Record',
                      description: 'Keep your past procedures, X-ray evaluations, and check-up timelines securely stored in the cloud.',
                    ),
                    _buildBenefitItem(
                      icon: Icons.card_giftcard_rounded,
                      title: 'Patient Referral Program',
                      description: 'Invite family and friends to DentaGuru and unlock special wellness rewards and dental care coins.',
                    ),
                    const SizedBox(height: 24),

                    // CTA Button
                    ElevatedButton.icon(
                      icon: const Icon(Icons.calendar_month_rounded, size: 18),
                      label: const Text('Book a Dental Consultation Now', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 2,
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        widget.onBookConsultation?.call();
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepCard({
    required String stepNumber,
    required String title,
    required String description,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                stepNumber,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: color.withValues(alpha: 0.95)),
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: const TextStyle(fontSize: 11.5, color: Color(0xFF475569), height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBenefitItem({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.softBlueCard,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: AppTheme.primaryBlue),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Color(0xFF0F172A)),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.info_outline_rounded, size: 15, color: AppTheme.primaryBlue),
                ),
                const SizedBox(width: 8),
                const Text(
                  'About DentaGuru',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ],
            ),
            InkWell(
              onTap: () => _showAboutDentaGuruSheet(context),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primaryBlue.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'How It Works',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryBlue,
                      ),
                    ),
                    SizedBox(width: 3),
                    Icon(Icons.arrow_forward_ios_rounded, size: 10, color: AppTheme.primaryBlue),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Hero Cards Carousel
        SizedBox(
          height: 180,
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: (idx) => setState(() => _currentPage = idx),
            itemCount: _slides.length,
            itemBuilder: (context, index) {
              final slide = _slides[index];
              final List<Color> gradient = slide['gradient'] as List<Color>;
              final List<String> chips = slide['chips'] as List<String>;

              return Container(
                margin: const EdgeInsets.only(right: 4),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: gradient,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: gradient.last.withValues(alpha: 0.28),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    // Background Watermark Icon
                    Positioned(
                      right: -10,
                      bottom: -10,
                      child: Icon(
                        slide['icon'] as IconData,
                        size: 90,
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),

                    // Content
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Badge Tag
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                          ),
                          child: Text(
                            slide['badge'] as String,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Title
                        Text(
                          slide['title'] as String,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            height: 1.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),

                        // Description
                        Expanded(
                          child: Text(
                            slide['description'] as String,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.88),
                              fontSize: 11,
                              height: 1.3,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),

                        // Chips Row + CTA Button
                        Row(
                          children: [
                            Expanded(
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: chips.map((c) {
                                    return Container(
                                      margin: const EdgeInsets.only(right: 6),
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.22),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        c,
                                        style: const TextStyle(fontSize: 9.5, color: Colors.white, fontWeight: FontWeight.w500),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            InkWell(
                              onTap: () => _handleCtaAction(slide['type'] as String),
                              borderRadius: BorderRadius.circular(20),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.15),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(slide['ctaIcon'] as IconData, size: 12, color: const Color(0xFF0F172A)),
                                    const SizedBox(width: 4),
                                    Text(
                                      slide['ctaText'] as String,
                                      style: const TextStyle(
                                        color: Color(0xFF0F172A),
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(width: 2),
                                    const Icon(Icons.arrow_forward_rounded, size: 11, color: Color(0xFF0F172A)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),

        // Dots Indicator
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_slides.length, (idx) {
            final isSelected = idx == _currentPage;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: isSelected ? 16 : 6,
              height: 5,
              decoration: BoxDecoration(
                color: isSelected ? AppTheme.primaryBlue : const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(3),
              ),
            );
          }),
        ),
      ],
    );
  }
}
