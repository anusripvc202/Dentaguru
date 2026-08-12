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
  const DentalAd({required this.brand,required this.tagline,required this.description,required this.badgeLabel,required this.website,required this.ctaText,required this.gradientColors,required this.icon,required this.emoji});
}

const List<DentalAd> _patientAds = [
  DentalAd(brand:'Colgate Total',tagline:'Advanced 12-Hour Protection',description:'Fight bacteria, plaque and tartar 24/7 with Colgate Total whitening formula. Trusted by dentists worldwide.',badgeLabel:'Dentist Recommended',website:'https://www.colgate.com/en-in/products/toothpaste',ctaText:'Shop Colgate',gradientColors:[Color(0xFF1A56DB),Color(0xFF0EA5E9)],icon:Icons.star_rounded,emoji:'🦷'),
  DentalAd(brand:'Oral-B iO Series',tagline:'AI Electric Toothbrush',description:'AI-powered oscillating brush removes 100% more plaque vs. regular manual. 6 smart modes for a perfect smile.',badgeLabel:'AI Brush Tech',website:'https://oralb.com/en-in/electric-toothbrushes',ctaText:'Explore Oral-B',gradientColors:[Color(0xFF0D9488),Color(0xFF06B6D4)],icon:Icons.electric_bolt_rounded,emoji:'⚡'),
  DentalAd(brand:'Listerine Cool Mint',tagline:'Kill 99.9% of Germs in 30s',description:'Clinical-strength antiseptic mouthwash. Clinically proven to fight gum disease and freshen breath instantly.',badgeLabel:'Clinically Proven',website:'https://www.listerine-me.com',ctaText:'Try Listerine',gradientColors:[Color(0xFF059669),Color(0xFF10B981)],icon:Icons.water_drop_rounded,emoji:'💧'),
  DentalAd(brand:'1mg Dental Store',tagline:'Dental Care Delivered Home',description:'Order toothpaste, floss, whitening kits and more at unbeatable prices. Free delivery on orders above Rs.199.',badgeLabel:'Free Delivery',website:'https://www.1mg.com/categories/dental-care',ctaText:'Order Now',gradientColors:[Color(0xFFDC2626),Color(0xFFEF4444)],icon:Icons.local_pharmacy_rounded,emoji:'💊'),
  DentalAd(brand:'Sensodyne Rapid Relief',tagline:'Instant Sensitivity Relief',description:'Say goodbye to tooth pain. Sensodyne clinically proven to relieve sensitivity in 60 seconds.',badgeLabel:'60-Second Relief',website:'https://www.sensodyne.co.in',ctaText:'Get Relief',gradientColors:[Color(0xFF7C3AED),Color(0xFF8B5CF6)],icon:Icons.healing_rounded,emoji:'🛡️'),
];

const List<DentalAd> _dentistAds = [
  DentalAd(brand:'Dentsply Sirona',tagline:'Professional Dental Equipment',description:'Industry-leading dental imaging, treatment units and instruments. Trusted by 300,000+ dentists worldwide.',badgeLabel:'#1 Dental Brand',website:'https://www.dentsplysirona.com',ctaText:'Explore Products',gradientColors:[Color(0xFF1A56DB),Color(0xFF3B82F6)],icon:Icons.medical_services_rounded,emoji:'🦷'),
  DentalAd(brand:'KaVo Kerr Group',tagline:'Next-Gen Handpieces',description:'High-speed handpieces, endo motors and curing lights for precision dentistry. ISO certified. Trusted globally.',badgeLabel:'ISO Certified',website:'https://www.kavokerr.com',ctaText:'Shop KaVo',gradientColors:[Color(0xFF0F766E),Color(0xFF0D9488)],icon:Icons.precision_manufacturing_rounded,emoji:'⚙️'),
  DentalAd(brand:'Henry Schein Dental',tagline:'Your Complete Supply Partner',description:'Everything from composites to PPE delivered next-day. Special pricing for registered practices. 800,000+ products.',badgeLabel:'Next-Day Delivery',website:'https://www.henryschein.com/dental',ctaText:'Order Supplies',gradientColors:[Color(0xFFB45309),Color(0xFFD97706)],icon:Icons.inventory_2_rounded,emoji:'📦'),
  DentalAd(brand:'Planmeca Imaging',tagline:'3D CBCT Panoramic Imaging',description:'Ultra-low-dose CBCT scanners with AI diagnostics. Upgrade your practice with world-class dental technology.',badgeLabel:'AI Diagnostics',website:'https://www.planmeca.com',ctaText:'Learn More',gradientColors:[Color(0xFF6D28D9),Color(0xFF7C3AED)],icon:Icons.biotech_rounded,emoji:'🔭'),
  DentalAd(brand:'Medline Dental PPE',tagline:'PPE and Consumables — Bulk',description:'High-quality gloves, masks, sterilization pouches and infection control supplies. Bulk discounts for clinics.',badgeLabel:'Bulk Pricing',website:'https://www.medline.com',ctaText:'Get Quote',gradientColors:[Color(0xFF047857),Color(0xFF059669)],icon:Icons.health_and_safety_rounded,emoji:'🛡️'),
];

class DentalAdsBanner extends StatefulWidget {
  final bool isDentist;
  const DentalAdsBanner({super.key, this.isDentist = false});
  @override
  State<DentalAdsBanner> createState() => _DentalAdsBannerState();
}

class _DentalAdsBannerState extends State<DentalAdsBanner> {
  late PageController _pageController;
  Timer? _autoScrollTimer;
  int _currentPage = 0;
  List<DentalAd> get _ads => widget.isDentist ? _dentistAds : _patientAds;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _autoScrollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || !_pageController.hasClients) return;
      final next = (_currentPage + 1) % _ads.length;
      _pageController.animateToPage(next, duration: const Duration(milliseconds: 550), curve: Curves.easeInOut);
    });
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    try { if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication); } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Expanded(
            child: Row(children: [
              Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: const Color(0xFFFFF7ED), borderRadius: BorderRadius.circular(8)), child: const Text('📢', style: TextStyle(fontSize: 14))),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.isDentist ? 'Dental Supply Partners' : 'Featured Dental Products',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ]),
          ),
          const SizedBox(width: 6),
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: const Color(0xFFFEF9C3), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFFDE047))), child: const Text('Sponsored', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF92400E)))),
        ]),
        const SizedBox(height: 10),
        SizedBox(height: 160, child: PageView.builder(
          controller: _pageController,
          itemCount: _ads.length,
          onPageChanged: (i) => setState(() => _currentPage = i),
          itemBuilder: (ctx, i) => _AdCard(ad: _ads[i], onTap: () => _launch(_ads[i].website)),
        )),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(_ads.length, (i) {
          final isActive = i == _currentPage;
          return AnimatedContainer(duration: const Duration(milliseconds: 280), margin: const EdgeInsets.symmetric(horizontal: 3), width: isActive ? 20 : 6, height: 6,
            decoration: BoxDecoration(color: isActive ? _ads[_currentPage].gradientColors.first : const Color(0xFFCBD5E1), borderRadius: BorderRadius.circular(4)));
        })),
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
      child: ScaleTransition(scale: _scale, child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: ad.gradientColors, begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: ad.gradientColors.first.withValues(alpha: 0.30), blurRadius: 12, offset: const Offset(0, 5))],
        ),
        child: Stack(children: [
          Positioned(right: -20, top: -20, child: Container(width: 90, height: 90, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.07)))),
          Positioned(right: 28, bottom: -20, child: Container(width: 60, height: 60, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.06)))),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14), child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Container(width: 56, height: 56, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(16)),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Text(ad.emoji, style: const TextStyle(fontSize: 22)), const SizedBox(height: 2), Icon(ad.icon, color: Colors.white70, size: 13)])),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(8)),
                child: Text(ad.badgeLabel, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold))),
              const SizedBox(height: 4),
              Text(ad.brand, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15), overflow: TextOverflow.ellipsis, maxLines: 1),
              const SizedBox(height: 1),
              Text(ad.tagline, style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 11, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis, maxLines: 1),
              const SizedBox(height: 2),
              Text(ad.description, style: TextStyle(color: Colors.white.withValues(alpha: 0.70), fontSize: 9.5, height: 1.3), overflow: TextOverflow.ellipsis, maxLines: 2),
              const SizedBox(height: 6),
              Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(ad.ctaText, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: ad.gradientColors.first)),
                  const SizedBox(width: 3),
                  Icon(Icons.open_in_new_rounded, size: 10, color: ad.gradientColors.first),
                ])),
            ])),
          ])),
        ]),
      )),
    );
  }
}
