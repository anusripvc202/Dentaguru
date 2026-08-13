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
    // Render exact DentaGuru Logo vector graphic & typography matching user design
    final iconSize = height;
    final fontSize = height * 0.58;

    final Widget logoWidget = _buildVectorLogo(iconSize, fontSize);

    Widget content = logoWidget;
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
        child: logoWidget,
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

  Widget _buildVectorLogo(double iconSize, double fontSize) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Custom 3D Blue D + Tooth + Swoosh Icon
        SizedBox(
          width: iconSize * 1.1,
          height: iconSize,
          child: CustomPaint(
            painter: _DentaGuruIconPainter(),
          ),
        ),
        const SizedBox(width: 4),
        // 'enta' in Navy Blue & 'Guru' in Orange Gradient
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: 'enta',
                style: TextStyle(
                  color: const Color(0xFF003882),
                  fontWeight: FontWeight.w900,
                  fontSize: fontSize,
                  letterSpacing: -0.5,
                  fontFamily: 'Roboto',
                ),
              ),
              WidgetSpan(
                child: ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [Color(0xFFFF5500), Color(0xFFFF9900)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ).createShader(bounds),
                  child: Text(
                    'Guru',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: fontSize,
                      letterSpacing: -0.5,
                      fontFamily: 'Roboto',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// CustomPainter for the 3D Blue 'D' with White Tooth & Orbital Ring Swoosh
class _DentaGuruIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 1. Draw outer 'D' with 3D Blue Gradient
    final dPaint = Paint()
      ..shader = const LinearGradient(
          colors: [Color(0xFF0052CC), Color(0xFF002D80)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(Rect.fromLTWH(0, 0, w, h));

    final dPath = Path();
    final r = h * 0.2;
    dPath.moveTo(w * 0.05, h * 0.05);
    dPath.lineTo(w * 0.55, h * 0.05);
    dPath.cubicTo(w * 0.95, h * 0.05, w * 0.95, h * 0.95, w * 0.55, h * 0.95);
    dPath.lineTo(w * 0.05, h * 0.95);
    dPath.close();
    canvas.drawPath(dPath, dPaint);

    // 2. Draw White Tooth inside 'D'
    final toothPaint = Paint()..color = Colors.white;
    final toothPath = Path();

    toothPath.moveTo(w * 0.35, h * 0.25);
    toothPath.cubicTo(w * 0.40, h * 0.18, w * 0.50, h * 0.18, w * 0.55, h * 0.25);
    toothPath.cubicTo(w * 0.60, h * 0.18, w * 0.70, h * 0.18, w * 0.75, h * 0.25);
    toothPath.cubicTo(w * 0.80, h * 0.45, w * 0.75, h * 0.65, w * 0.68, h * 0.82);
    toothPath.cubicTo(w * 0.64, h * 0.88, w * 0.58, h * 0.70, w * 0.55, h * 0.65);
    toothPath.cubicTo(w * 0.52, h * 0.70, w * 0.46, h * 0.88, w * 0.42, h * 0.82);
    toothPath.cubicTo(w * 0.35, h * 0.65, w * 0.30, h * 0.45, w * 0.35, h * 0.25);
    toothPath.close();
    canvas.drawPath(toothPath, toothPaint);

    // 3. Draw Blue Orbital Swoosh Ring around Tooth
    final swooshPaint = Paint()
      ..color = const Color(0xFF0077FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = h * 0.08
      ..strokeCap = StrokeCap.round;

    final swooshPath = Path();
    swooshPath.addArc(
      Rect.fromLTWH(w * 0.02, h * 0.38, w * 0.96, h * 0.30),
      -0.5,
      3.2,
    );
    canvas.drawPath(swooshPath, swooshPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
