import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/services/patient_problem_service.dart';
import '../../../../core/models/referral_model.dart';

class ReferFriendDialog extends StatefulWidget {
  final PatientProblemService patientService;

  const ReferFriendDialog({
    super.key,
    required this.patientService,
  });

  static Future<void> show(BuildContext context, PatientProblemService service) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => ReferFriendDialog(patientService: service),
    );
  }

  @override
  State<ReferFriendDialog> createState() => _ReferFriendDialogState();
}

class _ReferFriendDialogState extends State<ReferFriendDialog> {
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadReferralData();
  }

  Future<void> _loadReferralData() async {
    await widget.patientService.syncReferralsFromApi();
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  String _getReferralMessage(String code, String link) {
    return 'Join DentaGuru to easily connect with verified dentists and specialists, book consultations, manage appointments, and access your dental care digitally.\n\n👉 Register here: $link\nUse Referral Code: $code';
  }

  Future<void> _shareViaWhatsApp(String code, String link) async {
    final message = _getReferralMessage(code, link);
    final encoded = Uri.encodeComponent(message);
    final waUrl = Uri.parse('https://wa.me/?text=$encoded');
    try {
      if (await canLaunchUrl(waUrl)) {
        await launchUrl(waUrl, mode: LaunchMode.externalApplication);
      } else {
        final intentUrl = Uri.parse('whatsapp://send?text=$encoded');
        await launchUrl(intentUrl, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      _copyToClipboard(message, 'WhatsApp launch failed. Referral message copied to clipboard!');
    }
  }

  Future<void> _shareViaSms(String code, String link) async {
    final message = _getReferralMessage(code, link);
    final encoded = Uri.encodeComponent(message);
    final smsUri = Uri.parse('sms:?body=$encoded');
    try {
      if (await canLaunchUrl(smsUri)) {
        await launchUrl(smsUri, mode: LaunchMode.externalApplication);
      } else {
        _copyToClipboard(message, 'SMS launch failed. Referral message copied to clipboard!');
      }
    } catch (_) {
      _copyToClipboard(message, 'Referral message copied to clipboard!');
    }
  }

  void _copyToClipboard(String text, String successMessage) {
    Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(successMessage, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
            ],
          ),
          backgroundColor: const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    final referralCode = widget.patientService.myReferralCode;
    final referralLink = 'https://dentaguru.app/register?ref=$referralCode';
    final stats = widget.patientService.myReferralStats;
    final referralsList = widget.patientService.myReferrals;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      backgroundColor: Colors.white,
      elevation: 24,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: 580,
          maxHeight: screenHeight * 0.90,
        ),
        padding: EdgeInsets.all(screenWidth < 400 ? 14 : 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── HEADER ROW ──
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF8B5CF6), Color(0xFF6366F1)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF8B5CF6).withValues(alpha: 0.25),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.group_add_rounded, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Refer a Friend & Grow',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textDark),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Invite friends to access verified dental specialists',
                        style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: AppTheme.textMuted, size: 22),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            const SizedBox(height: 12),

            // ── SCROLLABLE CONTENT ──
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // ── 1. REFERRAL CODE CARD ──
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFFF5F3FF), Color(0xFFEEF2FF)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFFC4B5FD), width: 1.5),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.08),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                const Text(
                                  'YOUR UNIQUE REFERRAL CODE',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.1,
                                    color: Color(0xFF6D28D9),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: const Color(0xFFDDD6FE)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        referralCode,
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 2,
                                          color: Color(0xFF5B21B6),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      InkWell(
                                        onTap: () => _copyToClipboard(referralCode, 'Referral code copied to clipboard!'),
                                        child: const Icon(Icons.copy_rounded, size: 16, color: Color(0xFF7C3AED)),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  referralLink,
                                  style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280), fontWeight: FontWeight.w500),
                                  textAlign: TextAlign.center,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),

                          // ── 2. SHARING ACTION BUTTONS ──
                          Row(
                            children: [
                              // WhatsApp
                              Expanded(
                                child: _buildShareButton(
                                  label: 'WhatsApp',
                                  icon: Icons.chat_rounded,
                                  color: const Color(0xFF25D366),
                                  onTap: () => _shareViaWhatsApp(referralCode, referralLink),
                                ),
                              ),
                              const SizedBox(width: 8),
                              // SMS
                              Expanded(
                                child: _buildShareButton(
                                  label: 'SMS Invite',
                                  icon: Icons.sms_rounded,
                                  color: const Color(0xFF0284C7),
                                  onTap: () => _shareViaSms(referralCode, referralLink),
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Copy Link
                              Expanded(
                                child: _buildShareButton(
                                  label: 'Copy Link',
                                  icon: Icons.link_rounded,
                                  color: const Color(0xFF7C3AED),
                                  onTap: () => _copyToClipboard(referralLink, 'Referral link copied to clipboard!'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),

                          // ── 3. REFERRAL METRICS SUMMARY (3 KPI CARDS) ──
                          const Row(
                            children: [
                              Icon(Icons.analytics_rounded, size: 16, color: AppTheme.primaryBlue),
                              SizedBox(width: 6),
                              Text(
                                'My Referrals Summary',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: _buildStatCard(
                                  title: 'Total Referred',
                                  count: stats.totalReferred,
                                  color: const Color(0xFF8B5CF6),
                                  icon: Icons.group_rounded,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _buildStatCard(
                                  title: 'Registered Users',
                                  count: stats.registered + stats.consultationBooked + stats.consultationsCompleted,
                                  color: const Color(0xFF0284C7),
                                  icon: Icons.how_to_reg_rounded,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _buildStatCard(
                                  title: 'Consultations',
                                  count: stats.consultationsCompleted + stats.consultationBooked,
                                  color: const Color(0xFF10B981),
                                  icon: Icons.task_alt_rounded,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),

                          // ── 4. REFERRED FRIENDS LIST ──
                          Row(
                            children: [
                              const Icon(Icons.people_alt_rounded, size: 16, color: AppTheme.primaryBlue),
                              const SizedBox(width: 6),
                              const Text(
                                'Referred Friends Activity',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark),
                              ),
                              const Spacer(),
                              Text(
                                '${referralsList.length} total',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),

                          if (referralsList.isEmpty)
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: const Column(
                                children: [
                                  Icon(Icons.diversity_3_rounded, color: AppTheme.textMuted, size: 36),
                                  SizedBox(height: 8),
                                  Text(
                                    'No Friends Referred Yet',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'Share your unique link via WhatsApp or SMS to invite family and friends to DentaGuru.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                  ),
                                ],
                              ),
                            )
                          else
                            ...referralsList.map((ref) => _buildReferredFriendItem(ref)),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShareButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required int count,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: color, size: 15),
              Text(
                '$count',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: color),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppTheme.textDark),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildReferredFriendItem(ReferralItem ref) {
    final bool isCompleted = ref.status == 'CONSULTATION_COMPLETED';
    final bool isBooked = ref.status == 'CONSULTATION_BOOKED';

    final Color statusColor = isCompleted
        ? const Color(0xFF10B981)
        : (isBooked ? const Color(0xFF0284C7) : const Color(0xFF6B7280));

    final String statusLabel = isCompleted
        ? 'Consultation Completed'
        : (isBooked ? 'Consultation Booked' : 'Registered');

    final dateStr = '${ref.createdAt.day}/${ref.createdAt.month}/${ref.createdAt.year}';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: const Color(0xFF8B5CF6).withValues(alpha: 0.12),
            child: Text(
              ref.referredUserName.isNotEmpty ? ref.referredUserName[0].toUpperCase() : 'F',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF8B5CF6)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ref.referredUserName,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: AppTheme.textDark),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Joined $dateStr • ${ref.referredUserPhone}',
                  style: const TextStyle(fontSize: 10.5, color: AppTheme.textMuted),
                  overflow: TextOverflow.ellipsis,
                ),
                if (ref.assignedDoctorName != null && ref.assignedDoctorName!.isNotEmpty)
                  Text(
                    '👨‍⚕️ ${ref.assignedDoctorName}${ref.assignedClinicName != null ? " (${ref.assignedClinicName})" : ""}',
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF0D9488)),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: statusColor.withValues(alpha: 0.3)),
            ),
            child: Text(
              statusLabel,
              style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: statusColor),
            ),
          ),
        ],
      ),
    );
  }
}
