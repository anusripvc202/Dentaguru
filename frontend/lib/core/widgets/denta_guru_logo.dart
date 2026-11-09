import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:dentaguru/core/theme/app_theme.dart';
import '../constants/gs_health_brand_assets.dart';

class DentaGuruLogo extends StatelessWidget {
  final double height;
  final BoxFit fit;
  final bool darkBg;
  final VoidCallback? onTap;

  const DentaGuruLogo({
    super.key,
    this.height = 36.0,
    this.fit = BoxFit.contain,
    this.darkBg = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Zero-Failure Guaranteed High-Resolution GS HEALTH Logo (In-Memory + Asset Fallback)
    Widget logoImage;
    try {
      logoImage = Image.memory(
        base64Decode(kGsHealthLogoBase64),
        height: height,
        fit: fit,
        alignment: Alignment.centerLeft,
        errorBuilder: (_, __, ___) => Image.asset(
          'assets/gs_health_full_logo.png',
          height: height,
          fit: fit,
          alignment: Alignment.centerLeft,
        ),
      );
    } catch (_) {
      logoImage = Image.asset(
        'assets/gs_health_full_logo.png',
        height: height,
        fit: fit,
        alignment: Alignment.centerLeft,
      );
    }

    Widget content = logoImage;
    if (darkBg) {
      content = Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: logoImage,
      );
    }

    return InkWell(
      onTap: onTap ?? () {
        try {
          context.go('/auth');
        } catch (_) {}
      },
      borderRadius: BorderRadius.circular(8),
      child: content,
    );
  }
}

/// Standalone emblem icon for animated splash, gates and headers
class DentaGuruToothIcon extends StatelessWidget {
  final double size;
  final Color? fallbackColor;

  const DentaGuruToothIcon({super.key, this.size = 48.0, this.fallbackColor});

  @override
  Widget build(BuildContext context) {
    try {
      return Image.memory(
        base64Decode(kGsHealthAppIconBase64),
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => _buildFallback(context),
      );
    } catch (_) {
      return _buildFallback(context);
    }
  }

  Widget _buildFallback(BuildContext context) {
    return Image.asset(
      'assets/app_icon.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) {
        return Image.asset(
          'assets/dentaguru_tooth_icon.png',
          width: size,
          height: size,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => Image.asset(
            'assets/gs_health_full_logo.png',
            width: size,
            height: size,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => Icon(
              Icons.medical_services_rounded,
              size: size,
              color: fallbackColor ?? const Color(0xFF0D9488),
            ),
          ),
        );
      },
    );
  }
}
