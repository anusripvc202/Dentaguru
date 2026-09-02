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
  final bool isGsiPartner;

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
    this.isGsiPartner = false,
  });
}

const List<DentalAd> _patientAds = [
  DentalAd(
    brand: 'GSI Implants',
    tagline: 'Premium Dental Implant Systems',
    description: 'Advanced dental implant solutions, prosthetic components and precision implantology technology.',
    badgeLabel: 'Featured Partner',
    website: 'https://www.gsimplants.com/smooth-implant',
    ctaText: 'Buy GSI Implants',
    gradientColors: [Color(0xFF0F172A), Color(0xFF2563EB)],
    icon: Icons.biotech_rounded,
    emoji: '🦷',
    isGsiPartner: true,
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
];

const List<DentalAd> _dentistAds = [
  DentalAd(
    brand: 'GSI Implants',
    tagline: 'Premium Dental Implant Systems',
    description: 'Advanced dental implant solutions, prosthetic components and surgical kits for precision implantology.',
    badgeLabel: 'Featured Partner',
    website: 'https://www.gsimplants.com/smooth-implant',
    ctaText: 'Buy GSI Implants',
    gradientColors: [Color(0xFF0F172A), Color(0xFF2563EB)],
    icon: Icons.biotech_rounded,
    emoji: '🦷',
    isGsiPartner: true,
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
    if (_ads.length > 1) {
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
    if (ad.isGsiPartner || ad.brand.toLowerCase().contains('gsi')) {
      _showGsiProductsModal(context);
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

  void _showGsiProductsModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _GsiProductsSheet(onLaunchUrl: _launch),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_ads.isEmpty) return const SizedBox.shrink();

    final headerTitle = widget.customTitle ??
        (widget.firstSlideOnly
            ? 'Hero Partner'
            : (widget.remainingSlidesOnly
                ? (widget.isDentist ? 'Supply & Equipment Partners' : 'Recommended Dental Products')
                : (widget.isDentist ? 'Dental Supply Partners' : 'Featured Dental Products')));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Expanded(
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: const Color(0xFFFFF7ED), borderRadius: BorderRadius.circular(8)),
                child: Text(widget.firstSlideOnly ? '🌟' : '📢', style: const TextStyle(fontSize: 14)),
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
              color: const Color(0xFFFEF9C3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFDE047)),
            ),
            child: const Text(
              'Sponsored',
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF92400E)),
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
                          ad.isGsiPartner ? Icons.shopping_bag_rounded : Icons.open_in_new_rounded,
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

class _GsiProductsSheet extends StatelessWidget {
  final Future<void> Function(String url) onLaunchUrl;

  const _GsiProductsSheet({required this.onLaunchUrl});

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
      'title': 'Implant Surgical Kit',
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
        color: Color(0xFF0F172A), // Dark slate premium theme
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
          // Drag handle
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

          // Header
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
                          Flexible(
                            child: const Text(
                              'GSI Implants',
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

          // Action Quick Buttons Bar (PDF Catalog & Direct Website)
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
              ],
            ),
          ),

          const SizedBox(height: 6),

          // Product List
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

          // Bottom All-Products Action
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
                    'Browse All GSI Products on Official Store',
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
