import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';

/// Persistent themed Floating Action Button shown across relevant Patient App screens
/// to start booking a consultation at any point (preserving any active specialty).
class BookConsultationFab extends StatelessWidget {
  final VoidCallback onPressed;
  final String? selectedSpecialty;

  const BookConsultationFab({
    super.key,
    required this.onPressed,
    this.selectedSpecialty,
  });

  @override
  Widget build(BuildContext context) {
    final spec = (selectedSpecialty ?? '').trim();
    final tooltipText = (spec.isNotEmpty && spec.toLowerCase() != 'all')
        ? 'Book a Consultation ($spec)'
        : 'Book a Consultation';

    return FloatingActionButton.extended(
      key: const Key('book_consultation_fab'),
      heroTag: null,
      onPressed: onPressed,
      tooltip: tooltipText,
      backgroundColor: AppTheme.gsNavy,
      foregroundColor: Colors.white,
      elevation: 4,
      icon: const Icon(Icons.calendar_month_rounded, size: 20),
      label: const Text(
        'Book a Consultation',
        style: TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
        ),
      ),
    );
  }
}
