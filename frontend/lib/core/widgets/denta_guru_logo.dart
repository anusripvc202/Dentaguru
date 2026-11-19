import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../constants/gs_health_brand_assets.dart';
import '../theme/app_theme.dart';

final Uint8List _kGsLogoLightBytes = base64Decode(kGsHealthLogoBase64);
final Uint8List _kGsLogoDarkBytes = base64Decode(kGsHealthLogoDarkBgBase64);
final Uint8List _kGsIconLightBytes = base64Decode(kGsHealthAppIconBase64);
final Uint8List _kGsIconDarkBytes = base64Decode(kGsHealthAppIconDarkBgBase64);

Widget _buildGsFullLogoImage({
  required double height,
  required BoxFit fit,
  required Alignment alignment,
  required bool useDarkSurface,
}) {
  final Uint8List bytes = useDarkSurface ? _kGsLogoDarkBytes : _kGsLogoLightBytes;
  final String assetPath = useDarkSurface
      ? 'assets/gs_health_full_logo_dark.png'
      : 'assets/gs_health_full_logo.png';
  try {
    return Image.memory(
      bytes,
      height: height,
      fit: fit,
      alignment: alignment,
      errorBuilder: (_, __, ___) => Image.asset(
        assetPath,
        height: height,
        fit: fit,
        alignment: alignment,
      ),
    );
  } catch (_) {
    return Image.asset(
      assetPath,
      height: height,
      fit: fit,
      alignment: alignment,
    );
  }
}

/// Official GS HEALTH Brand Logo Widget
/// Horizontally centered or custom aligned, maintaining exact original aspect ratio.
/// Uses in-memory decoded Base64 with asset fallback for 100% zero-failure display.
class GsHealthLogo extends StatelessWidget {
  final double height;
  final BoxFit fit;
  final Alignment alignment;
  final bool darkBg;
  final VoidCallback? onTap;

  const GsHealthLogo({
    super.key,
    this.height = 42.0,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.darkBg = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool useDarkSurface =
        darkBg || Theme.of(context).brightness == Brightness.dark;
    final logoImage = _buildGsFullLogoImage(
      height: height,
      fit: fit,
      alignment: alignment,
      useDarkSurface: useDarkSurface,
    );

    if (onTap != null) {
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: onTap,
          child: logoImage,
        ),
      );
    }

    return logoImage;
  }
}

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
    final logoImage = _buildGsFullLogoImage(
      height: height,
      fit: fit,
      alignment: Alignment.centerLeft,
      useDarkSurface: useDarkSurface,
    );

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
    final Uint8List bytes = useDarkSurface ? _kGsIconDarkBytes : _kGsIconLightBytes;

    try {
      return Image.memory(
        bytes,
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
              color: fallbackColor ?? AppTheme.gsRed,
            ),
          ),
        );
      },
    );
  }
}
