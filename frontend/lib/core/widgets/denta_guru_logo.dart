import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
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
    final bool useDarkSurface =
        darkBg || Theme.of(context).brightness == Brightness.dark;
    final String base64Asset =
        useDarkSurface ? kGsHealthLogoDarkBgBase64 : kGsHealthLogoBase64;
    final String assetPath = useDarkSurface
        ? 'assets/gs_health_full_logo_dark.png'
        : 'assets/gs_health_full_logo.png';

    // Zero-Failure High-Resolution Transparent GS HEALTH Logo (In-Memory + Asset Fallback)
    Widget logoImage;
    try {
      logoImage = Image.memory(
        base64Decode(base64Asset),
        height: height,
        fit: fit,
        alignment: Alignment.centerLeft,
        errorBuilder: (_, __, ___) => Image.asset(
          assetPath,
          height: height,
          fit: fit,
          alignment: Alignment.centerLeft,
        ),
      );
    } catch (_) {
      logoImage = Image.asset(
        assetPath,
        height: height,
        fit: fit,
        alignment: Alignment.centerLeft,
      );
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: onTap ?? () {
          try {
            context.go('/auth');
          } catch (_) {}
        },
        child: logoImage,
      ),
    );
  }
}

/// Standalone emblem icon for animated splash, gates and headers
class DentaGuruToothIcon extends StatelessWidget {
  final double size;
  final Color? fallbackColor;
  final bool darkBg;

  const DentaGuruToothIcon({
    super.key,
    this.size = 48.0,
    this.fallbackColor,
    this.darkBg = false,
  });

  @override
  Widget build(BuildContext context) {
    final bool useDarkSurface =
        darkBg || Theme.of(context).brightness == Brightness.dark;
    final String base64Asset =
        useDarkSurface ? kGsHealthAppIconDarkBgBase64 : kGsHealthAppIconBase64;

    try {
      return Image.memory(
        base64Decode(base64Asset),
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) =>
            _buildFallback(context, useDarkSurface),
      );
    } catch (_) {
      return _buildFallback(context, useDarkSurface);
    }
  }

  Widget _buildFallback(BuildContext context, bool useDarkSurface) {
    final String primaryAsset =
        useDarkSurface ? 'assets/app_icon_dark.png' : 'assets/app_icon.png';
    return Image.asset(
      primaryAsset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) {
        return Image.asset(
          'assets/dentaguru_tooth_icon_transparent.png',
          width: size,
          height: size,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => Image.asset(
            useDarkSurface
                ? 'assets/gs_health_full_logo_dark.png'
                : 'assets/gs_health_full_logo.png',
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
