import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/denta_guru_logo.dart';
import '../../../../core/services/patient_problem_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  int _selectedAboutIndex = 0;

  late AnimationController _heroAnimationController;
  late AnimationController _pulseAnimationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _pulseScaleAnimation;

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();

    // Hero Entry Animation
    _heroAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _heroAnimationController,
      curve: Curves.easeOut,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _heroAnimationController,
      curve: Curves.easeOutCubic,
    ));

    // Continuous Badge Pulsing Animation
    _pulseAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _pulseScaleAnimation = Tween<double>(begin: 0.97, end: 1.03).animate(
      CurvedAnimation(parent: _pulseAnimationController, curve: Curves.easeInOut),
    );

    _heroAnimationController.forward();
  }

  @override
  void dispose() {
    _heroAnimationController.dispose();
    _pulseAnimationController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.softBlueBg,
      // Fixed Mobile App Top Header with DentaGuru Logo (dissolves 100% into navbar color)
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        shadowColor: Colors.black.withValues(alpha: 0.05),
        automaticallyImplyLeading: false,
        titleSpacing: 10,
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: DentaGuruLogo(height: 32),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _AnimatedAppButton(
              onPressed: () => context.go('/login'),
              backgroundColor: AppTheme.primaryBlue,
              foregroundColor: Colors.white,
              icon: Icons.login_rounded,
              label: 'Login',
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          controller: _scrollController,
          physics: const BouncingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ------------------ 1. HERO BANNER SECTION (ANIMATED) ------------------
              FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: _buildHeroBanner(context),
                ),
              ),

              const SizedBox(height: 24),

              // ------------------ 2. REDESIGNED ABOUT DENTAGURU SECTION ------------------
              _buildAboutApplicationSection(context),

              const SizedBox(height: 28),

              // ------------------ 3. EXTENDED APP FEATURES GRID (ANIMATED) ------------------
              _buildCoreFeaturesSection(context),

              const SizedBox(height: 28),

              // ------------------ 4. ADVANCED CLINICAL CARE MODULES ------------------
              _buildAdvancedModulesSection(context),

              const SizedBox(height: 28),

              // ------------------ 5. APP STATS BANNER ------------------
              _buildAppStatsBanner(),

              const SizedBox(height: 28),

              // ------------------ 6. HOW IT WORKS FLOW ------------------
              _buildHowItWorksSection(context),

              const SizedBox(height: 28),

              // ------------------ 7. REVIEWS & TESTIMONIALS ------------------
              _buildTestimonialsSection(context),

              const SizedBox(height: 32),

              // ------------------ 8. CALL TO ACTION FOOTER ------------------
              _buildFooterCta(context),

              const SizedBox(height: 24),

              // ------------------ 9. SINGLE LINE COMPANY FOOTER ------------------
              _buildCompanyFooter(),
            ],
          ),
        ),
      ),

    );
  }

  // ================= 1. HERO BANNER =================
  Widget _buildHeroBanner(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Pulsing Pill Tag
            ScaleTransition(
              scale: _pulseScaleAnimation,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.brandOrange.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.brandOrange.withValues(alpha: 0.4)),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.brandOrange.withValues(alpha: 0.2),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.auto_awesome_rounded, color: AppTheme.brandOrange, size: 14),
                    SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Next-Gen Dental Healthcare Platform',
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppTheme.brandOrange,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            const Text(
              'Modern Dental Care,\nSimplified for Everyone.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w800,
                height: 1.25,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 12),

            const Text(
              'DentaGuru connects patients, specialized dentists, and clinic teams into one intelligent platform. Experience AI dental triage, 1-tap booking, digital prescriptions, and 3D dental tracking.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 13,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),

            // Action Buttons Responsive Wrap for All Mobiles
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: [

                SizedBox(
                  width: MediaQuery.of(context).size.width < 400 ? double.infinity : null,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      _scrollController.animateTo(
                        380,
                        duration: const Duration(milliseconds: 600),
                        curve: Curves.easeInOutCubic,
                      );
                    },
                    icon: const Icon(Icons.info_outline_rounded, size: 18, color: Colors.white),
                    label: const Text(
                      'Explore Features',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.white),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      side: const BorderSide(color: Color(0xFF475569), width: 1.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ================= 2. REDESIGNED ABOUT DENTAGURU SECTION =================
  Widget _buildAboutApplicationSection(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: const Color(0xFFEEF2F6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.apps_rounded, color: AppTheme.primaryBlue, size: 22),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'About DentaGuru Application',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Discover how DentaGuru revolutionizes oral healthcare for patients, dentists, and clinic staff.',
            style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
          ),
          const SizedBox(height: 18),

          // 2x2 Grid Layout for Role Chips (2 per row)
          Column(
            children: [
              Row(
                children: [
                  Expanded(child: _buildRolePillChip(index: 0, label: 'Overview', icon: Icons.stars_rounded)),
                  const SizedBox(width: 8),
                  Expanded(child: _buildRolePillChip(index: 1, label: 'For Patients', icon: Icons.person_rounded)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _buildRolePillChip(index: 2, label: 'For Dentists', icon: Icons.medical_services_rounded)),
                  const SizedBox(width: 8),
                  Expanded(child: _buildRolePillChip(index: 3, label: 'AI Screening', icon: Icons.psychology_rounded)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Animated Content Card Switcher
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: _buildRoleContentCard(key: ValueKey<int>(_selectedAboutIndex), index: _selectedAboutIndex),
          ),
        ],
      ),
    );
  }

  Widget _buildRolePillChip({
    required int index,
    required String label,
    required IconData icon,
  }) {
    final bool isSelected = _selectedAboutIndex == index;

    return GestureDetector(
      onTap: () => setState(() => _selectedAboutIndex = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryBlue : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(14),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppTheme.primaryBlue.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : [],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? Colors.white : AppTheme.textMedium,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : AppTheme.textMedium,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleContentCard({required Key key, required int index}) {
    switch (index) {
      case 1:
        return _buildAboutDetailBody(
          badgeText: 'PATIENT EXPERIENCE',
          badgeColor: AppTheme.primaryBlue,
          title: 'Seamless Patient Dental Care',
          description: 'Patients enjoy effortless access to top dental care from their smartphones with 1-click appointment booking, instant AI teeth screening, and digital prescriptions.',
          bullets: [
            'Find & book top-rated local dental specialists',
            'Scan teeth photos with AI for instant pre-checks',
            'Store X-rays, prescriptions & dental history safely',
            'Receive automated check-up & cleaning reminders',
          ],
          icon: Icons.person_search_rounded,
        );
      case 2:
        return _buildAboutDetailBody(
          badgeText: 'PRACTITIONER WORKSPACE',
          badgeColor: const Color(0xFF0284C7),
          title: 'Dentist Digital Workspace & Timeline',
          description: 'Dentists get an interactive digital workspace to view daily patient queues, record dental charting, generate E-prescriptions, and track treatment progress over time.',
          bullets: [
            'Interactive teeth charting & procedure logger',
            'Instant patient history & allergies inspection',
            '1-Tap E-prescription & home care advice generator',
            'Patient follow-up timeline & recovery tracking',
          ],
          icon: Icons.health_and_safety_rounded,
        );
      case 3:
        return _buildAboutDetailBody(
          badgeText: 'AI CLINICAL TRIAGE',
          badgeColor: const Color(0xFF8B5CF6),
          title: 'AI Smart Dental Photo Screening',
          description: 'Powered by advanced vision models, DentaGuru AI pre-screens dental photos for potential cavities, plaque, or gum inflammation before the clinic visit.',
          bullets: [
            'Fast photo analysis & risk score calculation',
            'Pre-visit summary generated for attending dentist',
            'Emergency triage indicator for acute dental pain',
            'Educational insights on personal oral hygiene',
          ],
          icon: Icons.psychology_rounded,
        );
      case 0:
      default:
        return _buildAboutDetailBody(
          badgeText: 'PLATFORM OVERVIEW',
          badgeColor: AppTheme.brandOrange,
          title: 'Comprehensive Dental Platform',
          description: 'DentaGuru bridges the gap between patients, specialists, and dental clinic managers with real-time synchronization, cloud dental records, and AI workflow assistance.',
          bullets: [
            'Unified access for Patients, Dentists, and Clinic Admins',
            'Real-time appointment scheduling & slot locking',
            'Cloud-based electronic dental records (EDR)',
            'Multi-branch clinic administration & billing',
          ],
          icon: Icons.hub_rounded,
        );
    }
  }

  Widget _buildAboutDetailBody({
    required String badgeText,
    required Color badgeColor,
    required String title,
    required String description,
    required List<String> bullets,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 14, color: badgeColor),
                    const SizedBox(width: 6),
                    Text(
                      badgeText,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: badgeColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            description,
            style: const TextStyle(fontSize: 12, color: AppTheme.textMedium, height: 1.45),
          ),
          const SizedBox(height: 14),

          // Feature Highlight Items List
          Column(
            children: bullets
                .map(
                  (bullet) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          margin: const EdgeInsets.only(top: 2),
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                            color: Color(0xFF10B981),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.check, size: 10, color: Colors.white),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            bullet,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textDark,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  // ================= 3. EXTENDED APP FEATURES GRID =================
  Widget _buildCoreFeaturesSection(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.star_rounded, color: AppTheme.brandOrange, size: 22),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Platform Features',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Tap any card to interact with smart tools built into DentaGuru',
            style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
          ),
          const SizedBox(height: 14),

          // 6 Interactive Animated Feature Cards Grid
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 0.82,
            children: const [
              _AnimatedFeatureTile(
                title: 'AI Smart Scan',
                subtitle: 'Photo pre-screening for cavities, plaque & gum health',
                icon: Icons.auto_fix_high_rounded,
                color: Color(0xFF8B5CF6),
              ),
              _AnimatedFeatureTile(
                title: '24/7 Tele-Dentistry',
                subtitle: 'HD video consultations with certified dentists anytime',
                icon: Icons.videocam_rounded,
                color: Color(0xFF0284C7),
              ),
              _AnimatedFeatureTile(
                title: '1-Tap Booking',
                subtitle: 'Real-time doctor calendar slot reservation',
                icon: Icons.calendar_month_rounded,
                color: AppTheme.primaryBlue,
              ),
              _AnimatedFeatureTile(
                title: '3D Dental Chart',
                subtitle: 'Interactive dental map tracking fillings & crowns',
                icon: Icons.view_in_ar_rounded,
                color: AppTheme.brandOrange,
              ),
              _AnimatedFeatureTile(
                title: 'E-Prescriptions',
                subtitle: 'Digital medical slips & pharmacy product ordering',
                icon: Icons.receipt_long_rounded,
                color: Color(0xFF10B981),
              ),
              _AnimatedFeatureTile(
                title: 'Habit Tracker',
                subtitle: '2-min brushing timer & daily flossing streak logger',
                icon: Icons.timer_rounded,
                color: Color(0xFFEC4899),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ================= 4. ADVANCED CLINICAL CARE MODULES =================
  Widget _buildAdvancedModulesSection(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.verified_user_rounded, color: AppTheme.primaryBlue, size: 22),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Comprehensive Care Capabilities',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Designed to support patient wellness and clinic efficiency',
            style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
          ),
          const SizedBox(height: 14),

          _buildModuleRow(
            icon: Icons.family_restroom_rounded,
            title: 'Family Dental Profile Locker',
            subtitle: 'Manage appointments and treatment histories for your whole family in 1 account.',
            color: AppTheme.primaryBlue,
          ),
          const Divider(height: 20, color: Color(0xFFF1F5F9)),
          _buildModuleRow(
            icon: Icons.calculate_rounded,
            title: 'Cost Estimator & Insurance Check',
            subtitle: 'View transparent procedure pricing, insurance coverage, and co-pay breakdowns.',
            color: const Color(0xFF10B981),
          ),
          const Divider(height: 20, color: Color(0xFFF1F5F9)),
          _buildModuleRow(
            icon: Icons.notifications_active_rounded,
            title: 'Smart Reminders & Cleaning Alerts',
            subtitle: 'Automated notifications for biannual cleanings, aligner swaps & prescriptions.',
            color: AppTheme.brandOrange,
          ),
          const Divider(height: 20, color: Color(0xFFF1F5F9)),
          _buildModuleRow(
            icon: Icons.folder_zip_rounded,
            title: 'Digital X-Ray & DICOM Viewer',
            subtitle: 'Access high-resolution dental X-rays and 3D scans anytime from your device.',
            color: const Color(0xFF8B5CF6),
          ),
        ],
      ),
    );
  }

  Widget _buildModuleRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 11, color: AppTheme.textMuted, height: 1.35),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ================= 5. APP STATS BANNER =================
  Widget _buildAppStatsBanner() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.primaryBlue, AppTheme.primaryBlueDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryBlue.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          Expanded(child: _buildStatItem('50K+', 'Happy Patients')),
          _buildStatDivider(),
          Expanded(child: _buildStatItem('1,200+', 'Verified Doctors')),
          _buildStatDivider(),
          Expanded(child: _buildStatItem('99.4%', 'AI Accuracy')),
        ],
      ),
    );
  }

  Widget _buildStatItem(String number, String label) {
    return Column(
      children: [
        Text(
          number,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF93C5FD),
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildStatDivider() {
    return Container(
      height: 30,
      width: 1,
      color: Colors.white.withValues(alpha: 0.2),
    );
  }

  // ================= 6. HOW IT WORKS SECTION =================
  Widget _buildHowItWorksSection(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.route_rounded, color: AppTheme.primaryBlue, size: 22),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'How DentaGuru Works',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            '3 easy steps to access complete dental healthcare',
            style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
          ),
          const SizedBox(height: 14),

          _buildStepCard(
            stepNumber: '01',
            title: 'Tap Login & Select Your Portal',
            subtitle: 'Use top-right Login to access Patient, Dentist, or Admin accounts.',
            icon: Icons.touch_app_rounded,
          ),
          const SizedBox(height: 10),
          _buildStepCard(
            stepNumber: '02',
            title: 'Book Consultations & AI Scan',
            subtitle: 'Schedule appointments in 1-tap or run instant AI teeth pre-screening.',
            icon: Icons.calendar_month_rounded,
          ),
          const SizedBox(height: 10),
          _buildStepCard(
            stepNumber: '03',
            title: 'Track Dental Records & Care Timeline',
            subtitle: 'Access digital prescriptions, treatment plans, and oral hygiene reminders.',
            icon: Icons.health_and_safety_rounded,
          ),
        ],
      ),
    );
  }

  Widget _buildStepCard({
    required String stepNumber,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.primaryBlue.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Text(
              stepNumber,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 14,
                color: AppTheme.primaryBlue,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: AppTheme.textDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 11, color: AppTheme.textMuted, height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ================= 7. TESTIMONIALS SECTION =================
  Widget _buildTestimonialsSection(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.format_quote_rounded, color: AppTheme.brandOrange, size: 24),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Trusted by Doctors & Patients',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Testimonial Card
          Builder(
            builder: (context) {
              final firstDoc = PatientProblemService().allDoctors.firstOrNull;
              final docName = firstDoc?.name ?? 'Dr. Dental Specialist, BDS';
              final docSpec = firstDoc?.specialty ?? 'Senior Dental Practitioner';

              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const CircleAvatar(
                          radius: 16,
                          backgroundColor: AppTheme.primaryBlue,
                          child: Text('DR', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(docName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark), overflow: TextOverflow.ellipsis),
                              Text(docSpec, style: const TextStyle(fontSize: 10, color: AppTheme.textMuted), overflow: TextOverflow.ellipsis),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.star_rounded, color: Color(0xFFF59E0B), size: 14),
                            Icon(Icons.star_rounded, color: Color(0xFFF59E0B), size: 14),
                            Icon(Icons.star_rounded, color: Color(0xFFF59E0B), size: 14),
                            Icon(Icons.star_rounded, color: Color(0xFFF59E0B), size: 14),
                            Icon(Icons.star_rounded, color: Color(0xFFF59E0B), size: 14),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '"DentaGuru has streamlined our dental clinic queue management and digital prescription history. Patients love the instant booking and AI pre-screening features!"',
                      style: TextStyle(fontSize: 12, color: AppTheme.textMedium, fontStyle: FontStyle.italic, height: 1.3),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ================= 8. FOOTER CTA =================
  Widget _buildFooterCta(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        children: [
          const DentaGuruLogo(height: 46, darkBg: true),
          const SizedBox(height: 16),
          const Text(
            'Ready to Experience DentaGuru?',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  Widget _buildCompanyFooter() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
      ),
      child: Text.rich(
        TextSpan(
          text: 'Designed by ',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Color(0xFF94A3B8),
            letterSpacing: 0.4,
          ),
          children: [
            TextSpan(
              text: 'ThePatterns Company Pvt Ltd.',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF38BDF8),
                letterSpacing: 0.5,
                shadows: [
                  Shadow(
                    color: const Color(0xFF38BDF8).withValues(alpha: 0.3),
                    blurRadius: 6,
                  ),
                ],
              ),
            ),
          ],
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

// Custom Animated Feature Tile Component
class _AnimatedFeatureTile extends StatefulWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;

  const _AnimatedFeatureTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  @override
  State<_AnimatedFeatureTile> createState() => _AnimatedFeatureTileState();
}

class _AnimatedFeatureTileState extends State<_AnimatedFeatureTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isHovered = true),
        onTapUp: (_) => setState(() => _isHovered = false),
        onTapCancel: () => setState(() => _isHovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _isHovered ? widget.color.withValues(alpha: 0.04) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _isHovered ? widget.color : const Color(0xFFE2E8F0),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: _isHovered ? widget.color.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.03),
                blurRadius: _isHovered ? 14 : 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: widget.color.withValues(alpha: _isHovered ? 0.2 : 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(widget.icon, color: widget.color, size: 20),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, color: AppTheme.textMuted, height: 1.3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Custom Animated App Button
class _AnimatedAppButton extends StatefulWidget {
  final VoidCallback onPressed;
  final Color backgroundColor;
  final Color foregroundColor;
  final IconData icon;
  final String label;

  const _AnimatedAppButton({
    required this.onPressed,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.icon,
    required this.label,
  });

  @override
  State<_AnimatedAppButton> createState() => _AnimatedAppButtonState();
}

class _AnimatedAppButtonState extends State<_AnimatedAppButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onPressed();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: _isPressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeInOut,
        child: ElevatedButton.icon(
          onPressed: widget.onPressed,
          icon: Icon(widget.icon, size: 16),
          label: Text(
            widget.label,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: widget.backgroundColor,
            foregroundColor: widget.foregroundColor,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 3,
            shadowColor: widget.backgroundColor.withValues(alpha: 0.4),
          ),
        ),
      ),
    );
  }
}
