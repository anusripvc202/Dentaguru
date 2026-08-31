import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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
    // 100% Perfect High-Resolution DentaGuru Logo Image Asset with Transparent Background
    final Widget logoImage = Image.asset(
      'assets/dentaguru_logo.png',
      height: height,
      fit: fit,
      alignment: Alignment.centerLeft,
    );

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

/// Standalone tooth emblem icon for animated splash, gates and headers
class DentaGuruToothIcon extends StatelessWidget {
  final double size;

  const DentaGuruToothIcon({super.key, this.size = 48.0});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/dentaguru_tooth_icon_transparent.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) {
        return Icon(
          Icons.medical_services_rounded,
          size: size,
          color: const Color(0xFF0052CC),
        );
      },
    );
  }
}
