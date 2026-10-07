import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';

/// "Need Any Help?" Support Card
/// Provides instant 24/7 "Call Us Now" and "Chat on WhatsApp" direct actions.
class NeedHelpCard extends StatelessWidget {
  final String helplineNumber;
  final String displayHelplineNumber;
  final String whatsappNumber;
  final String? customMessage;
  final EdgeInsetsGeometry? margin;

  const NeedHelpCard({
    super.key,
    this.helplineNumber = '9550686566',
    this.displayHelplineNumber = '+91 95506 86566',
    this.whatsappNumber = '9550686566',
    this.customMessage,
    this.margin,
  });

  String _cleanNumber(String phone) {
    var digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 10) {
      digits = '91$digits';
    }
    return digits;
  }

  Future<void> _makeCall(BuildContext context) async {
    final cleanDigits = _cleanNumber(helplineNumber);
    final telUri = Uri.parse('tel:+$cleanDigits');

    try {
      final launched = await launchUrl(telUri, mode: LaunchMode.externalApplication);
      if (!launched) {
        if (context.mounted) {
          _showCallDialog(context);
        }
      }
    } catch (_) {
      if (context.mounted) {
        _showCallDialog(context);
      }
    }
  }

  void _showCallDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFE0F2FE),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.phone_in_talk_rounded, color: AppTheme.primaryBlue, size: 22),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'DentaGuru Support',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Call our 24/7 clinical care helpline for dental emergencies, appointments, and consultations:',
              style: TextStyle(fontSize: 13, color: AppTheme.textMedium, height: 1.4),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.call_rounded, color: AppTheme.primaryBlue, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      displayHelplineNumber,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textDark,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 18, color: AppTheme.textMedium),
                    tooltip: 'Copy Number',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: displayHelplineNumber));
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('📋 Helpline number copied to clipboard!'),
                          backgroundColor: AppTheme.primaryBlue,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close', style: TextStyle(color: AppTheme.textMedium)),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.pop(ctx);
              final telUri = Uri.parse('tel:+${_cleanNumber(helplineNumber)}');
              await launchUrl(telUri, mode: LaunchMode.externalApplication);
            },
            icon: const Icon(Icons.call_rounded, size: 16),
            label: const Text('Call Now'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _chatOnWhatsApp(BuildContext context) async {
    final cleanPhone = _cleanNumber(whatsappNumber);
    final msg = customMessage ??
        'Hello DentaGuru Support Team! 👋\nI need assistance regarding dental consultations, appointments, or services.';

    final waUrl = Uri.parse('https://wa.me/$cleanPhone?text=${Uri.encodeComponent(msg)}');
    final intentUrl = Uri.parse('whatsapp://send?phone=$cleanPhone&text=${Uri.encodeComponent(msg)}');

    try {
      if (await canLaunchUrl(waUrl)) {
        await launchUrl(waUrl, mode: LaunchMode.externalApplication);
      } else if (await canLaunchUrl(intentUrl)) {
        await launchUrl(intentUrl, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(waUrl, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('📱 WhatsApp helpline: $displayHelplineNumber'),
            action: SnackBarAction(
              label: 'Copy',
              textColor: Colors.white,
              onPressed: () => Clipboard.setData(ClipboardData(text: displayHelplineNumber)),
            ),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin ?? EdgeInsets.zero,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFFFFFFFF),
            Color(0xFFF8FAFC),
            Color(0xFFEFF6FF),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFDBEAFE), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0052CC).withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Subtle decorative background circle
          Positioned(
            right: -25,
            top: -25,
            child: Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF38BDF8).withValues(alpha: 0.08),
              ),
            ),
          ),
          Positioned(
            right: 40,
            bottom: -30,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF25D366).withValues(alpha: 0.06),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Header Row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF0284C7), Color(0xFF0052CC)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF0284C7).withValues(alpha: 0.25),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.headset_mic_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Flexible(
                                child: Text(
                                  'Need Any Help?',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.textDark,
                                    letterSpacing: -0.2,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFDCFCE7),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: const Color(0xFF86EFAC)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: const BoxDecoration(
                                        color: Color(0xFF16A34A),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    const Text(
                                      '24/7 LIVE',
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF15803D),
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          const Text(
                            'Our dental care team is here to assist with consultations, emergency care & queries.',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textMedium,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Action Buttons: Call Us Now & Chat on WhatsApp side-by-side
                Row(
                  children: [
                    Expanded(
                      child: _SupportActionButton(
                        onTap: () => _makeCall(context),
                        icon: Icons.phone_in_talk_rounded,
                        title: 'Call Us Now',
                        subtitle: displayHelplineNumber,
                        gradientColors: const [Color(0xFF0284C7), Color(0xFF0052CC)],
                        shadowColor: const Color(0xFF0052CC).withValues(alpha: 0.22),
                        iconBgColor: Colors.white.withValues(alpha: 0.2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _SupportActionButton(
                        onTap: () => _chatOnWhatsApp(context),
                        icon: Icons.chat_rounded,
                        title: 'Chat on WhatsApp',
                        subtitle: 'Instant Reply ⚡',
                        gradientColors: const [Color(0xFF22C55E), Color(0xFF15803D)],
                        shadowColor: const Color(0xFF16A34A).withValues(alpha: 0.22),
                        iconBgColor: Colors.white.withValues(alpha: 0.2),
                        isWhatsApp: true,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SupportActionButton extends StatelessWidget {
  final VoidCallback onTap;
  final IconData icon;
  final String title;
  final String subtitle;
  final List<Color> gradientColors;
  final Color shadowColor;
  final Color iconBgColor;
  final bool isWhatsApp;

  const _SupportActionButton({
    required this.onTap,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.gradientColors,
    required this.shadowColor,
    required this.iconBgColor,
    this.isWhatsApp = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: gradientColors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: shadowColor,
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: iconBgColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: Colors.white,
                  size: 15,
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.2,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 9.5,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
