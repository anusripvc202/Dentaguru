import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class DentalAd {
  final String brand;
  final String tagline;
  final String description;
  final String badgeLabel;
  final String website;
  final String ctaText;
  final List<Color> gradientColors;
  final IconData icon;
  final String emoji;
  final bool isDentaGuru;
  final bool isGsiPartner;
  final bool isGsCourse;

  const DentalAd({
    required this.brand,
    required this.tagline,
    required this.description,
    required this.badgeLabel,
    required this.website,
    required this.ctaText,
    required this.gradientColors,
    required this.icon,
    required this.emoji,
    this.isDentaGuru = false,
    this.isGsiPartner = false,
    this.isGsCourse = false,
  });
}

const List<DentalAd> _patientAds = [
  DentalAd(
    brand: 'DentaGuru',
    tagline: 'Comprehensive Dental Care Platform',
    description: 'Instant AI dental triage, certified specialist consultations, clinic appointments & digital e-prescriptions.',
    badgeLabel: 'Featured Platform',
    website: 'https://dentaguru.in',
    ctaText: 'Explore DentaGuru',
    gradientColors: [Color(0xFF0F172A), Color(0xFF2563EB)],
    icon: Icons.health_and_safety_rounded,
    emoji: '🦷',
    isDentaGuru: true,
  ),
  DentalAd(
    brand: 'Colgate Total',
    tagline: 'Advanced 12-Hour Protection',
    description: 'Fight bacteria, plaque and tartar 24/7 with Colgate Total whitening formula. Trusted by dentists worldwide.',
    badgeLabel: 'Dentist Recommended',
    website: 'https://www.colgate.com/en-in/products/toothpaste',
    ctaText: 'Shop Colgate',
    gradientColors: [Color(0xFF1A56DB), Color(0xFF0EA5E9)],
    icon: Icons.star_rounded,
    emoji: '✨',
  ),
  DentalAd(
    brand: 'Oral-B iO Series',
    tagline: 'AI Electric Toothbrush',
    description: 'AI-powered oscillating brush removes 100% more plaque vs. regular manual. 6 smart modes for a perfect smile.',
    badgeLabel: 'AI Brush Tech',
    website: 'https://oralb.com/en-in/electric-toothbrushes',
    ctaText: 'Explore Oral-B',
    gradientColors: [Color(0xFF0D9488), Color(0xFF06B6D4)],
    icon: Icons.electric_bolt_rounded,
    emoji: '⚡',
  ),
  DentalAd(
    brand: 'Listerine Cool Mint',
    tagline: 'Kill 99.9% of Germs in 30s',
    description: 'Clinical-strength antiseptic mouthwash. Clinically proven to fight gum disease and freshen breath instantly.',
    badgeLabel: 'Clinically Proven',
    website: 'https://www.listerine-me.com',
    ctaText: 'Try Listerine',
    gradientColors: [Color(0xFF059669), Color(0xFF10B981)],
    icon: Icons.water_drop_rounded,
    emoji: '💧',
  ),
  DentalAd(
    brand: 'Sensodyne Rapid Relief',
    tagline: 'Instant Sensitivity Relief',
    description: 'Say goodbye to tooth pain. Sensodyne clinically proven to relieve sensitivity in 60 seconds.',
    badgeLabel: '60-Second Relief',
    website: 'https://www.sensodyne.co.in',
    ctaText: 'Get Relief',
    gradientColors: [Color(0xFF7C3AED), Color(0xFF8B5CF6)],
    icon: Icons.healing_rounded,
    emoji: '🛡️',
  ),
  DentalAd(
    brand: 'GS Implants',
    tagline: 'Premium Dental Implant Systems',
    description: 'Advanced dental implant solutions, prosthetic components and precision implantology technology.',
    badgeLabel: 'Featured Partner',
    website: 'https://www.gsimplants.com/smooth-implant',
    ctaText: 'Buy GS Implants',
    gradientColors: [Color(0xFF0F172A), Color(0xFF2563EB)],
    icon: Icons.biotech_rounded,
    emoji: '⚙️',
    isGsiPartner: true,
  ),
];

const List<DentalAd> _dentistAds = [
  DentalAd(
    brand: 'DentaGuru Pro',
    tagline: 'Next-Gen Dental Practice Platform',
    description: 'Streamline specialist referrals, digital case sheets, revenue analytics, and instant multi-clinic consultations.',
    badgeLabel: 'Featured Platform',
    website: 'https://dentaguru.in',
    ctaText: 'Explore DentaGuru Pro',
    gradientColors: [Color(0xFF0F172A), Color(0xFF2563EB)],
    icon: Icons.medical_services_rounded,
    emoji: '🦷',
    isDentaGuru: true,
  ),
  DentalAd(
    brand: 'Dentsply Sirona',
    tagline: 'Professional Dental Equipment',
    description: 'Industry-leading dental imaging, treatment units and instruments. Trusted by 300,000+ dentists worldwide.',
    badgeLabel: '#1 Dental Brand',
    website: 'https://www.dentsplysirona.com',
    ctaText: 'Explore Products',
    gradientColors: [Color(0xFF1A56DB), Color(0xFF3B82F6)],
    icon: Icons.medical_services_rounded,
    emoji: '💎',
  ),
  DentalAd(
    brand: 'KaVo Kerr Group',
    tagline: 'Next-Gen Handpieces',
    description: 'High-speed handpieces, endo motors and curing lights for precision dentistry. ISO certified. Trusted globally.',
    badgeLabel: 'ISO Certified',
    website: 'https://www.kavokerr.com',
    ctaText: 'Shop KaVo',
    gradientColors: [Color(0xFF0F766E), Color(0xFF0D9488)],
    icon: Icons.precision_manufacturing_rounded,
    emoji: '⚙️',
  ),
  DentalAd(
    brand: 'Henry Schein Dental',
    tagline: 'Your Complete Supply Partner',
    description: 'Everything from composites to PPE delivered next-day. Special pricing for registered practices. 800,000+ products.',
    badgeLabel: 'Next-Day Delivery',
    website: 'https://www.henryschein.com/dental',
    ctaText: 'Order Supplies',
    gradientColors: [Color(0xFFB45309), Color(0xFFD97706)],
    icon: Icons.inventory_2_rounded,
    emoji: '📦',
  ),
  DentalAd(
    brand: 'Planmeca Imaging',
    tagline: '3D CBCT Panoramic Imaging',
    description: 'Ultra-low-dose CBCT scanners with AI diagnostics. Upgrade your practice with world-class dental technology.',
    badgeLabel: 'AI Diagnostics',
    website: 'https://www.planmeca.com',
    ctaText: 'Learn More',
    gradientColors: [Color(0xFF6D28D9), Color(0xFF7C3AED)],
    icon: Icons.biotech_rounded,
    emoji: '🔭',
  ),
  DentalAd(
    brand: 'GS Implants',
    tagline: 'Premium Dental Implant Systems',
    description: 'Advanced dental implant solutions, prosthetic components and surgical kits for precision implantology.',
    badgeLabel: 'Featured Partner',
    website: 'https://www.gsimplants.com/smooth-implant',
    ctaText: 'Buy GS Implants',
    gradientColors: [Color(0xFF0F172A), Color(0xFF2563EB)],
    icon: Icons.biotech_rounded,
    emoji: '⚙️',
    isGsiPartner: true,
  ),
];

class DentalAdsBanner extends StatefulWidget {
  final bool isDentist;
  final bool firstSlideOnly;
  final bool remainingSlidesOnly;
  final String? customTitle;

  const DentalAdsBanner({
    super.key,
    this.isDentist = false,
    this.firstSlideOnly = false,
    this.remainingSlidesOnly = false,
    this.customTitle,
  });

  @override
  State<DentalAdsBanner> createState() => _DentalAdsBannerState();
}

class _DentalAdsBannerState extends State<DentalAdsBanner> {
  Timer? _autoScrollTimer;
  int _currentPage = 0;

  List<DentalAd> get _ads {
    final fullList = widget.isDentist ? _dentistAds : _patientAds;
    if (widget.firstSlideOnly) {
      return [fullList.first];
    } else if (widget.remainingSlidesOnly) {
      return fullList.skip(1).toList();
    }
    return fullList;
  }

  @override
  void initState() {
    super.initState();
    if (_ads.length > 1 && !widget.firstSlideOnly) {
      _autoScrollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
        if (!mounted) return;
        setState(() {
          _currentPage = (_currentPage + 1) % _ads.length;
        });
      });
    }
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    super.dispose();
  }

  Future<void> _handleAdTap(DentalAd ad) async {
    if (ad.isDentaGuru || ad.brand.toLowerCase().contains('dentaguru')) {
      _showDentaGuruModal(context, isDentist: widget.isDentist);
    } else if (ad.isGsCourse || ad.brand.toLowerCase().contains('course')) {
      _showGsCoursesModal(context);
    } else if (ad.isGsiPartner || ad.brand.toLowerCase().contains('gs') || ad.brand.toLowerCase().contains('gsi')) {
      _showGsProductsModal(context);
    } else {
      _launch(ad.website);
    }
  }

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(uri);
      }
    } catch (e) {
      try {
        await launchUrl(uri);
      } catch (err) {
        debugPrint('Could not launch website $url: $err');
      }
    }
  }

  void _showDentaGuruModal(BuildContext context, {bool isDentist = false}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _DentaGuruPlatformSheet(onLaunchUrl: _launch, isDentist: isDentist),
    );
  }

  void _showGsProductsModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _GsProductsSheet(onLaunchUrl: _launch),
    );
  }

  void _showGsCoursesModal(BuildContext context) {
    _launch('https://www.gsimplants.com/courses');
  }

  @override
  Widget build(BuildContext context) {
    final isHero = widget.firstSlideOnly;

    // ── If this is the Hero Section, display the 50/50 Dual-Split Layout: GS Implants + Upcoming Courses ──
    if (isHero) {
      final headerTitle = widget.customTitle ?? 'GS Implants • Systems & Clinical Courses';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('🦷', style: TextStyle(fontSize: 14)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        headerTitle,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFBFDBFE)),
                ),
                child: const Text(
                  'Featured Partner',
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF1D4ED8)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _GsHeroSplitBanner(
            onOpenProducts: () => _showGsProductsModal(context),
            onOpenCourses: () => _showGsCoursesModal(context),
          ),
        ],
      );
    }

    if (_ads.isEmpty) return const SizedBox.shrink();

    final headerTitle = widget.customTitle ??
        (widget.remainingSlidesOnly
            ? (widget.isDentist ? 'Supply & Equipment Partners' : 'Recommended Dental Products')
            : (widget.isDentist ? 'Dental Supply Partners' : 'Featured Dental Products'));

    const headerIcon = '📢';
    const headerIconBg = Color(0xFFFFF7ED);
    const badgeLabel = 'Sponsored';
    const badgeBg = Color(0xFFFEF9C3);
    const badgeBorder = Color(0xFFFDE047);
    const badgeTextColor = Color(0xFF92400E);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Expanded(
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: headerIconBg, borderRadius: BorderRadius.circular(8)),
                child: const Text(headerIcon, style: TextStyle(fontSize: 14)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  headerTitle,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ]),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: badgeBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: badgeBorder),
            ),
            child: const Text(
              badgeLabel,
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: badgeTextColor),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        SizedBox(
          height: 160,
          width: double.infinity,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 550),
            transitionBuilder: (Widget child, Animation<double> animation) {
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.04, 0),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              );
            },
            child: KeyedSubtree(
              key: ValueKey<int>(_currentPage),
              child: _AdCard(
                ad: _ads[_currentPage % _ads.length],
                onTap: () => _handleAdTap(_ads[_currentPage % _ads.length]),
              ),
            ),
          ),
        ),
        if (_ads.length > 1) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_ads.length, (i) {
              final isActive = i == _currentPage;
              return GestureDetector(
                onTap: () => setState(() => _currentPage = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 280),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: isActive ? 20 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: isActive ? _ads[_currentPage % _ads.length].gradientColors.first : const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              );
            }),
          ),
        ],
      ],
    );
  }
}

// =========================================================================
// GS HERO SPLIT BANNER (50% GS IMPLANTS + 50% UPCOMING COURSES)
// =========================================================================
class _GsHeroSplitBanner extends StatelessWidget {
  final VoidCallback onOpenProducts;
  final VoidCallback onOpenCourses;

  const _GsHeroSplitBanner({
    required this.onOpenProducts,
    required this.onOpenCourses,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        final cardHeight = screenWidth > 640 ? 175.0 : (screenWidth > 380 ? 195.0 : 210.0);

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left Half (50%): GS Implants Product Systems
            Expanded(
              child: _buildHalfCard(
                context: context,
                height: cardHeight,
                badgeText: 'Featured Partner',
                badgeBgColor: Colors.white.withValues(alpha: 0.18),
                badgeTextColor: Colors.white,
                title: 'GS Implants',
                subtitle: 'Premium Dental Implant Systems',
                description: 'Advanced bicortical solutions, prosthetic components & surgical kits.',
                ctaText: 'Buy GS Implants',
                ctaIcon: Icons.shopping_bag_rounded,
                gradientColors: const [Color(0xFF0F172A), Color(0xFF1E40AF)],
                avatarIcon: Icons.biotech_rounded,
                avatarEmoji: '🦷',
                onTap: onOpenProducts,
              ),
            ),
            const SizedBox(width: 10),
            // Right Half (50%): Upcoming Courses of GS Implants
            Expanded(
              child: _buildHalfCard(
                context: context,
                height: cardHeight,
                badgeText: 'Masterclass & CME',
                badgeBgColor: const Color(0xFF10B981).withValues(alpha: 0.25),
                badgeTextColor: const Color(0xFF6EE7B7),
                title: 'Upcoming Courses',
                subtitle: 'Basal & Cortical Masterclasses',
                description: 'Hands-on surgical training, immediate loading & live surgery workshops.',
                ctaText: 'View Courses',
                ctaIcon: Icons.school_rounded,
                gradientColors: const [Color(0xFF0F172A), Color(0xFF0D9488)],
                avatarIcon: Icons.workspace_premium_rounded,
                avatarEmoji: '🎓',
                onTap: onOpenCourses,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHalfCard({
    required BuildContext context,
    required double height,
    required String badgeText,
    required Color badgeBgColor,
    required Color badgeTextColor,
    required String title,
    required String subtitle,
    required String description,
    required String ctaText,
    required IconData ctaIcon,
    required List<Color> gradientColors,
    required IconData avatarIcon,
    required String avatarEmoji,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: height,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradientColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: gradientColors.last.withValues(alpha: 0.30),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              right: -15,
              top: -15,
              child: Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.06),
                ),
              ),
            ),
            Positioned(
              right: 15,
              bottom: -15,
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.05),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: badgeBgColor,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: badgeTextColor.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          badgeText,
                          style: TextStyle(
                            color: badgeTextColor,
                            fontSize: 8.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Text(avatarEmoji, style: const TextStyle(fontSize: 13)),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 14.5,
                          letterSpacing: 0.2,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                      const SizedBox(height: 1),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.88),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        description,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.70),
                          fontSize: 9.0,
                          height: 1.25,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4.5),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 3,
                          offset: const Offset(0, 1.5),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(ctaIcon, size: 11, color: gradientColors.last),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            ctaText,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: gradientColors.last,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(Icons.arrow_forward_rounded, size: 10, color: gradientColors.last),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdCard extends StatefulWidget {
  final DentalAd ad;
  final VoidCallback onTap;
  const _AdCard({required this.ad, required this.onTap});
  @override
  State<_AdCard> createState() => _AdCardState();
}

class _AdCardState extends State<_AdCard> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 120));
    _scale = Tween<double>(begin: 1.0, end: 0.97).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final ad = widget.ad;
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) => _ctrl.reverse(),
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: ad.gradientColors, begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [BoxShadow(color: ad.gradientColors.first.withValues(alpha: 0.30), blurRadius: 12, offset: const Offset(0, 5))],
          ),
          child: Stack(children: [
            Positioned(right: -20, top: -20, child: Container(width: 90, height: 90, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.07)))),
            Positioned(right: 28, bottom: -20, child: Container(width: 60, height: 60, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.06)))),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(ad.emoji, style: const TextStyle(fontSize: 22)),
                      const SizedBox(height: 2),
                      Icon(ad.icon, color: Colors.white70, size: 13),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(8)),
                      child: Text(ad.badgeLabel, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 4),
                    Text(ad.brand, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15), overflow: TextOverflow.ellipsis, maxLines: 1),
                    const SizedBox(height: 1),
                    Text(ad.tagline, style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 11, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis, maxLines: 1),
                    const SizedBox(height: 2),
                    Text(ad.description, style: TextStyle(color: Colors.white.withValues(alpha: 0.70), fontSize: 9.5, height: 1.3), overflow: TextOverflow.ellipsis, maxLines: 2),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.12),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(
                          ad.isDentaGuru
                              ? Icons.verified_rounded
                              : (ad.isGsiPartner ? Icons.shopping_bag_rounded : Icons.open_in_new_rounded),
                          size: 11,
                          color: ad.gradientColors.first,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          ad.ctaText,
                          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: ad.gradientColors.first),
                        ),
                        const SizedBox(width: 3),
                        Icon(Icons.arrow_forward_rounded, size: 10, color: ad.gradientColors.first),
                      ]),
                    ),
                  ]),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _DentaGuruPlatformSheet extends StatelessWidget {
  final Future<void> Function(String url) onLaunchUrl;
  final bool isDentist;

  const _DentaGuruPlatformSheet({
    required this.onLaunchUrl,
    this.isDentist = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 25,
            spreadRadius: 5,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 44,
              height: 4.5,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2563EB).withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.4)),
                  ),
                  child: const Text('🦷', style: TextStyle(fontSize: 24)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              isDentist ? 'DentaGuru Pro' : 'DentaGuru Platform',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.3,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.5)),
                            ),
                            child: const Text(
                              'OFFICIAL',
                              style: TextStyle(
                                color: Color(0xFF34D399),
                                fontSize: 8.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isDentist
                            ? 'Smart Practice Management & Specialist Network'
                            : 'AI Dental Triage, Consultations & Verified Clinics',
                        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: Colors.white70),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white10,
                    padding: const EdgeInsets.all(8),
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white12, height: 16),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              children: [
                _buildFeatureCard(
                  icon: Icons.psychology_rounded,
                  title: 'AI Dental Diagnostic Triage',
                  desc: 'Instant tooth-by-tooth AI symptom assessment, emergency urgency scoring & visual risk grading.',
                  color: const Color(0xFF3B82F6),
                ),
                const SizedBox(height: 12),
                _buildFeatureCard(
                  icon: Icons.medical_services_rounded,
                  title: 'Verified Specialist Network',
                  desc: 'Connect with certified Orthodontists, Endodontists, Implantologists & Oral Surgeons with live availability.',
                  color: const Color(0xFF10B981),
                ),
                const SizedBox(height: 12),
                _buildFeatureCard(
                  icon: Icons.receipt_long_rounded,
                  title: 'Digital E-Prescriptions & Case Sheets',
                  desc: 'Cloud-synced prescriptions with instant WhatsApp delivery to patients and verified pharmacy integration.',
                  color: const Color(0xFFF59E0B),
                ),
                const SizedBox(height: 12),
                _buildFeatureCard(
                  icon: Icons.share_location_rounded,
                  title: 'Multi-Clinic Direct Referrals',
                  desc: 'Seamless doctor-to-doctor clinical patient referrals with status tracking and automated WhatsApp notifications.',
                  color: const Color(0xFF8B5CF6),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            decoration: const BoxDecoration(
              color: Color(0xFF0B132B),
              border: Border(top: BorderSide(color: Colors.white10)),
            ),
            child: SafeArea(
              top: false,
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.check_circle_rounded, size: 18),
                  label: const Text(
                    'Return to DentaGuru Dashboard',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 3,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureCard({
    required IconData icon,
    required String title,
    required String desc,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  desc,
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =========================================================================
// GS PRODUCTS SHEET (OFFICIAL GS IMPLANTS CATALOG)
// =========================================================================
class _GsProductsSheet extends StatelessWidget {
  final Future<void> Function(String url) onLaunchUrl;

  const _GsProductsSheet({required this.onLaunchUrl});

  static const List<Map<String, dynamic>> _products = [
    {
      'title': 'Smooth GS Implants',
      'subtitle': 'Immediate Loading Bicortical System',
      'desc': 'Polished non-porous cervical collar designed for immediate extraction socket placement. Prevents bacterial adhesion and peri-implantitis.',
      'url': 'https://www.gsimplants.com/smooth-implant',
      'badge': 'Bestseller',
      'icon': Icons.shield_rounded,
      'color': Color(0xFF0284C7),
      'features': ['Anti-Peri-implantitis', 'Immediate Loading', 'Ti-6Al-4V Alloy'],
    },
    {
      'title': 'Rough GS Implants',
      'subtitle': 'SLA Micro-Porous Surface Architecture',
      'desc': 'Sand-blasted, Large-grit, Acid-etched surface with calcium phosphate treatment. Exceptional bone condensation for D3 and D4 bone density.',
      'url': 'https://www.gsimplants.com/rough-implant',
      'badge': 'High Stability',
      'icon': Icons.grain_rounded,
      'color': Color(0xFF2563EB),
      'features': ['SLA Surface', 'D3/D4 Bone Optimized', 'Deep Bicortical Grip'],
    },
    {
      'title': 'Combi GS Implants',
      'subtitle': 'Hybrid Dual-Surface Engineering',
      'desc': 'Combines rough osseointegrative thread body with smooth polished neck. Maximum shear resistance with bendable neck for parallel alignment.',
      'url': 'https://www.gsimplants.com/combi-implant',
      'badge': 'Hybrid Tech',
      'icon': Icons.hub_rounded,
      'color': Color(0xFF7C3AED),
      'features': ['Bendable Neck', 'Hybrid Dual Surface', 'Fracture-Resistant'],
    },
    {
      'title': 'GS Implant Surgical Kit',
      'subtitle': 'Complete Precision Instrumentation Set',
      'desc': 'High-precision lance pilot drills, titanium drivers, torque ratchets, and depth gauges housed in an autoclavable medical-grade cassette.',
      'url': 'https://www.gsimplants.com/kit',
      'badge': 'Complete Set',
      'icon': Icons.medical_services_rounded,
      'color': Color(0xFF0D9488),
      'features': ['Autoclavable Box', 'Lance Pilot Drills', 'Torque Ratchet Included'],
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 25,
            spreadRadius: 5,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 44,
              height: 4.5,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2563EB).withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.4)),
                  ),
                  child: const Icon(Icons.biotech_rounded, color: Color(0xFF60A5FA), size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Flexible(
                            child: Text(
                              'GS Implants',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.3,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.5)),
                            ),
                            child: const Text(
                              'OFFICIAL STORE',
                              style: TextStyle(
                                color: Color(0xFF34D399),
                                fontSize: 8.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Premium Dental Implant Systems & Surgical Equipment',
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: Colors.white70),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white10,
                    padding: const EdgeInsets.all(8),
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white12, height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () {
                      onLaunchUrl('https://www.gsimplants.com/assets/pdf/CATALOG_GS_IMPLANTS.pdf.pdf');
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.picture_as_pdf_rounded, color: Color(0xFFF87171), size: 14),
                          SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'Download PDF Catalog',
                              style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: InkWell(
                    onTap: () {
                      onLaunchUrl('https://www.gsimplants.com');
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2563EB).withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.4)),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.language_rounded, color: Color(0xFF60A5FA), size: 14),
                          SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'Visit Website',
                              style: TextStyle(color: Color(0xFF93C5FD), fontSize: 11, fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: InkWell(
                    onTap: () {
                      Navigator.pop(context);
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (ctx) => _GsCoursesSheet(onLaunchUrl: onLaunchUrl),
                      );
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0D9488).withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF14B8A6).withValues(alpha: 0.4)),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.school_rounded, color: Color(0xFF5EEAD4), size: 14),
                          SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              'CME Courses',
                              style: TextStyle(color: Color(0xFF5EEAD4), fontSize: 11, fontWeight: FontWeight.bold),
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
          ),
          const SizedBox(height: 6),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              itemCount: _products.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (ctx, index) {
                final p = _products[index];
                final pColor = p['color'] as Color;
                final features = p['features'] as List<String>;

                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: pColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: pColor.withValues(alpha: 0.35)),
                            ),
                            child: Icon(p['icon'] as IconData, color: pColor, size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        p['title'] as String,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 14.5,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: pColor.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        p['badge'] as String,
                                        style: TextStyle(
                                          color: pColor,
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  p['subtitle'] as String,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.75),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        p['desc'] as String,
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 11,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: features.map((f) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: Text(
                            '✓ $f',
                            style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 9.5),
                          ),
                        )).toList(),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                onLaunchUrl(p['url'] as String);
                              },
                              icon: const Icon(Icons.shopping_cart_checkout_rounded, size: 14),
                              label: Text(
                                'Buy ${p['title']}',
                                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis,
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: pColor,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                elevation: 0,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: () {
                              onLaunchUrl('tel:+919550686566');
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF38BDF8),
                              side: const BorderSide(color: Color(0xFF0284C7)),
                              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.phone_in_talk_rounded, size: 13),
                                SizedBox(width: 4),
                                Text('Inquire', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            decoration: const BoxDecoration(
              color: Color(0xFF0B132B),
              border: Border(top: BorderSide(color: Colors.white10)),
            ),
            child: SafeArea(
              top: false,
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    onLaunchUrl('https://www.gsimplants.com/smooth-implant');
                  },
                  icon: const Icon(Icons.storefront_rounded, size: 18),
                  label: const Text(
                    'Browse All GS Products on Official Store',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 3,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =========================================================================
// GS COURSES SHEET (UPCOMING COURSES OF GS IMPLANTS)
// =========================================================================
class _GsCoursesSheet extends StatelessWidget {
  final Future<void> Function(String url) onLaunchUrl;

  const _GsCoursesSheet({required this.onLaunchUrl});

  static const List<Map<String, dynamic>> _courses = [
    {
      'title': '3-Day Comprehensive Cortico-Basal Masterclass',
      'subtitle': 'Live Patient Surgeries & Bicortical Engagement Workshop',
      'desc': 'Intensive hands-on clinical residency covering flapless immediate functional loading, bicortical anchorage, and pterygoid/zygomatic bypass techniques for atrophic jaws.',
      'dates': 'November 14 – 16, 2026 (3 Days Full-Time)',
      'venue': 'GS Clinical Academy & Hospital, Hyderabad & Bangalore',
      'mentor': 'Lead Maxillofacial & Cortical Implant Mentors',
      'badge': '🔥 Bestseller Masterclass',
      'color': Color(0xFF0D9488),
      'icon': Icons.school_rounded,
      'cme': '24 CME Credit Points',
      'fee': '₹35,000',
      'highlights': [
        'Live Patient Surgeries',
        'Typodont Drilling & Torque Kit Included',
        'Pterygoid & Zygoma Bypass',
        'Immediate Load Occlusion',
        'DCI Recognized Mastership Certificate',
      ],
      'whatsappMsg': 'Hi GS Implants Academy, I would like to register for the 3-Day Comprehensive Cortico-Basal Masterclass on DentaGuru.',
    },
    {
      'title': 'Full-Arch Immediate Loading & Prosthetic Mastership',
      'subtitle': 'From Intraoral Digital Scan to Final Hybrid Zirconia',
      'desc': 'Advanced prosthodontic protocols for immediate restoration: multi-unit abutment selection, digital impression workflow, passivity verification, and long-term occlusal equilibrium.',
      'dates': 'December 05 – 07, 2026 (Intensive Mastership)',
      'venue': 'DentaGuru Training Academy, Mumbai & Delhi Centers',
      'mentor': 'Senior Prosthodontists & Implant Specialists',
      'badge': 'Advanced Prosthetics',
      'color': Color(0xFF2563EB),
      'icon': Icons.hub_rounded,
      'cme': '18 CME Credit Points',
      'fee': '₹28,000',
      'highlights': [
        'Digital Intraoral Scanning',
        'Multi-Unit Abutment Protocols',
        'Zirconia & Titanium Frameworks',
        'Complication Prevention & Care',
      ],
      'whatsappMsg': 'Hi GS Implants Academy, I would like to register for the Full-Arch Immediate Loading & Prosthetic Mastership on DentaGuru.',
    },
    {
      'title': 'Weekend Hands-On Typodont Surgical Workshop',
      'subtitle': 'Fundamental to Advanced Surgical Drilling & Flap Protocols',
      'desc': 'Step-by-step hands-on training on bone models of varying densities (D1–D4), osteotomy sequencing, torque calibration, and suturing for practicing dentists.',
      'dates': 'Every Alternate Weekend (Saturday – Sunday)',
      'venue': 'Regional Centers: Chennai, Pune, Kolkata, Vijayawada',
      'mentor': 'Certified GS Implants Clinical Faculty',
      'badge': 'Weekend Intensive',
      'color': Color(0xFF7C3AED),
      'icon': Icons.science_rounded,
      'cme': '12 CME Credit Points',
      'fee': '₹15,000',
      'highlights': [
        'D1–D4 Bone Density Drilling',
        'ISQ & Insertion Torque Calibration',
        'Soft Tissue Flap Design & Suturing',
        'Clinical Case Discussion',
      ],
      'whatsappMsg': 'Hi GS Implants Academy, I am interested in the Weekend Hands-On Typodont Surgical Workshop on DentaGuru.',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 25,
            spreadRadius: 5,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 44,
              height: 4.5,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D9488).withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF14B8A6).withValues(alpha: 0.4)),
                  ),
                  child: const Icon(Icons.school_rounded, color: Color(0xFF5EEAD4), size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Flexible(
                            child: Text(
                              'GS Implants Academy',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.3,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.5)),
                            ),
                            child: const Text(
                              'CME CERTIFIED',
                              style: TextStyle(
                                color: Color(0xFF34D399),
                                fontSize: 8.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Upcoming Masterclasses, Surgical Protocols & Clinical Workshops',
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: Colors.white70),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white10,
                    padding: const EdgeInsets.all(8),
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white12, height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () {
                      final waUrl = Uri.parse('https://wa.me/919550686566?text=${Uri.encodeComponent('Hi GS Implants Academy, I would like to request the full upcoming clinical course schedule and registration details on DentaGuru.')}');
                      onLaunchUrl(waUrl.toString());
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF25D366).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF25D366).withValues(alpha: 0.4)),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.chat_rounded, color: Color(0xFF4ADE80), size: 14),
                          SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'WhatsApp Course Desk',
                              style: TextStyle(color: Color(0xFF86EFAC), fontSize: 11, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: InkWell(
                    onTap: () {
                      onLaunchUrl('tel:+919550686566');
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.phone_in_talk_rounded, color: Color(0xFF60A5FA), size: 14),
                          SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'Call: +91 95506 86566',
                              style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
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
          ),
          const SizedBox(height: 6),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              itemCount: _courses.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (ctx, index) {
                final c = _courses[index];
                final cColor = c['color'] as Color;
                final highlights = c['highlights'] as List<String>;

                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: cColor.withValues(alpha: 0.3)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: cColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: cColor.withValues(alpha: 0.35)),
                            ),
                            child: Icon(c['icon'] as IconData, color: cColor, size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        c['title'] as String,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 14.5,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 2,
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: cColor.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        c['badge'] as String,
                                        style: TextStyle(
                                          color: cColor,
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  c['subtitle'] as String,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.8),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.calendar_month_rounded, size: 13, color: Color(0xFF38BDF8)),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    c['dates'] as String,
                                    style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 11, fontWeight: FontWeight.bold),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(Icons.location_on_outlined, size: 13, color: Color(0xFFF87171)),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    c['venue'] as String,
                                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10.5),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(Icons.military_tech_rounded, size: 13, color: Color(0xFFFBBF24)),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    '${c['cme']} • Fee: ${c['fee']}',
                                    style: const TextStyle(color: Color(0xFFFCD34D), fontSize: 11, fontWeight: FontWeight.bold),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        c['desc'] as String,
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 11,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: highlights.map((h) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: Text(
                            '✓ $h',
                            style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 9.5),
                          ),
                        )).toList(),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                final msg = c['whatsappMsg'] as String;
                                final waUrl = Uri.parse('https://wa.me/919550686566?text=${Uri.encodeComponent(msg)}');
                                onLaunchUrl(waUrl.toString());
                              },
                              icon: const Icon(Icons.chat_rounded, size: 14, color: Colors.white),
                              label: const Text(
                                'Register via WhatsApp',
                                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.white),
                                overflow: TextOverflow.ellipsis,
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF25D366),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                elevation: 0,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: () {
                              onLaunchUrl('tel:+919550686566');
                            },
                            icon: const Icon(Icons.phone_in_talk_rounded, size: 13),
                            label: const Text('Call', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF38BDF8),
                              side: const BorderSide(color: Color(0xFF0284C7)),
                              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            decoration: const BoxDecoration(
              color: Color(0xFF0B132B),
              border: Border(top: BorderSide(color: Colors.white10)),
            ),
            child: SafeArea(
              top: false,
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    final waUrl = Uri.parse('https://wa.me/919550686566?text=${Uri.encodeComponent('Hi GS Implants Academy, I would like to inquire about customized hands-on clinical implant training and workshop dates.')}');
                    onLaunchUrl(waUrl.toString());
                  },
                  icon: const Icon(Icons.school_rounded, size: 18),
                  label: const Text(
                    'Inquire Customized Clinical Training for Clinic/Colleagues',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0D9488),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 3,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
