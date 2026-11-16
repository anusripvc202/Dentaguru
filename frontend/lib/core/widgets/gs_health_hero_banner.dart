import 'package:flutter/material.dart';

/// Zero-Failure High-Resolution Healthcare Hero Banner
/// Displays the multi-specialty modern healthcare background image from assets with fallback.
class GsHealthHeroBanner extends StatelessWidget {
  final double? height;
  final BoxFit fit;

  const GsHealthHeroBanner({
    super.key,
    this.height,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/healthcare_hero_banner.jpg',
      height: height,
      width: double.infinity,
      fit: fit,
      errorBuilder: (_, __, ___) => Container(
        height: height,
        width: double.infinity,
        color: const Color(0xFF1E293B),
      ),
    );
  }
}


