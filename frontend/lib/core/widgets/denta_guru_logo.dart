import 'package:flutter/material.dart';

class DentaGuruLogo extends StatelessWidget {
  final double height;
  final BoxFit fit;
  final bool darkBg;

  const DentaGuruLogo({
    super.key,
    this.height = 42.0,
    this.fit = BoxFit.contain,
    this.darkBg = false,
  });

  @override
  Widget build(BuildContext context) {
    // Exact Real DentaGuru Logo Image Asset with 100% Transparent Background
    final Widget logoImage = Image.asset(
      'assets/dentaguru_logo.png',
      height: height,
      fit: fit,
      alignment: Alignment.centerLeft,
    );

    if (darkBg) {
      return Container(
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

    return logoImage;
  }
}
