import 'package:flutter/material.dart';

class DentaGuruLogo extends StatelessWidget {
  final double height;

  const DentaGuruLogo({
    super.key,
    this.height = 42.0,
  });

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/dentaguru_logo.png',
      height: height,
      fit: BoxFit.contain,
      alignment: Alignment.centerLeft,
      errorBuilder: (context, error, stackTrace) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Styled 3D Tooth "D" Logo Emblem
            Container(
              width: height * 0.9,
              height: height * 0.9,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0052CC), Color(0xFF0B46A4)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0052CC).withOpacity(0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Center(
                child: Icon(
                  Icons.health_and_safety_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
            const SizedBox(width: 8),
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: 'Denta',
                    style: TextStyle(
                      fontFamily: 'Outfit',
                      fontSize: height * 0.65,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF0052CC),
                    ),
                  ),
                  TextSpan(
                    text: 'Guru',
                    style: TextStyle(
                      fontFamily: 'Outfit',
                      fontSize: height * 0.65,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFFFF7A00),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

